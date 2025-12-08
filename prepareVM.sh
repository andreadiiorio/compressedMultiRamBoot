##!/bin/bash
#pyQemu, QEMU command-line and tap scripts generator for minimal&secure virtual machines creation.
#Copyright (C) 2025 Andrea Di Iorio
#
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see <https://www.gnu.org/licenses/>.


set -e

export DEBUG=1 DISTRO=DEBIAN DEB_CACHE=/tmp/debCACHE/ ARCH_CACHE=/tmp/archCACHE/
[[ $DEBUG == 1 ]] && set -x && export DEBUG="set -x"
##TODO DBG

umask 0022

SCRIPTDIR=$(dirname ${BASH_SOURCE[@]})
. $SCRIPTDIR/utils.sh

CHROOT="${CHROOT-/mnt/tmp}"
INIT_CHROOT="${INIT_CHROOT-/root/init.sh}"
VM_DISK_IMG="${VM_DISK_IMG-/tmp/vm.raw}"
VM_DISK_SZ=${VM_DISK_SZ-'7g'}

UEFI=${UEFI-1}
LOOPDEV=${LOOPDEV-$(losetup -f)}

RAMBOOT=1
#deb/arch, most simple common names
BASE_PKGS_0="dhcpcd curl vim git tmux tree wget fish"

ARCH_BASE_PKGS="base linux-firmware linux-hardened grub dhcpcd sudo"
ARCH_BASE_PKGS+=" lsof util-linux which python3 m4 patch man"
ARCH_EXTRA_PKGS0=$BASE_PKGS_0
ARCH_EXTRA_PKGS0+=" openssh pcre2 pcre openbsd-netcat"
ARCH_EXTRA_PKGS1="sqlite diffutils cryptsetup ctags iptables usbutils usb_modeswitch usbguard usbview xdp-tools nvim"
ARCH_EXTRA_PKGS1+=" xf86-video-fbdev xorg xorg-xinit i3 firefox grub"

DEBIAN_BASE_PKGS="linux-base linux-image-amd64 systemd systemd-sysv initramfs-tools"
DEBIAN_BASE_PKGS+=" grub-efi-amd64-signed"
DEBIAN_BASE_PKGS+=" login sudo passwd"
DEBIAN_EXTRA_PKGS0=$BASE_PKGS_0
DEBIAN_EXTRA_PKGS0+=" openssh-server netcat-openbsd pcre2-utils"



function ARCHInitChroot
{
echo """
pacman -Syu --noconfirm $ARCH_EXTRA_PKGS0 #$ARCH_EXTRA_PKGS1

mkinitcpio -P || true

mkdir -p /boot/grub
grub-install --target=i386-pc /dev/loop0
grub-mkconfig -o /boot/grub/grub.cfg
"""
}


function DEBIANInitChroot
{
echo """
export PATH=\$PATH:/sbin

apt install -y $DEBIAN_BASE_PKGS $DEBIAN_EXTRA_PKGS0

##update-initramfs

mkdir -p /boot/grub
grub-install --target=i386-pc /dev/loop0
grub-mkconfig -o /boot/grub/grub.cfg
"""
}

__ARCH_RAMBOOT="initramfs/arch/ramBoot"
function ARCHRamboot
{
cp "$__ARCH_RAMBOOT/mkinitcpio.conf"	"$CHROOT/etc"
cp -r -f "$__ARCH_RAMBOOT/*"	"$CHROOT/etc/initcpio/"
#cp "$__ARCH_RAMBOOT/hooks/ramboot"	"$CHROOT/etc/initcpio/hooks"
#cp "$__ARCH_RAMBOOT/install/ramboot"	"$CHROOT/etc/initcpio/install/ramboot"
}

__DEB_RAMBOOT="initramfs/deb/ramBoot"
function DEBIANRamboot
{
cp -r -f "$__DEB_RAMBOOT/*"	"$CHROOT/etc/initramfs-tools/"
}

function ARCHBasePrepare
{
[[ -d "$ARCH_CACHE" ]] && cp -a "$ARCH_CACHE"/* "$CHROOT" && return 0
pacstrap -K $CHROOT $ARCH_BASE_PKGS
}


function DEBIANBasePrepare
{
[[ -d "$DEB_CACHE" ]] && cp -a "$DEB_CACHE"/* "$CHROOT" && return 0
debootstrap --verbose --variant=buildd --merged-usr --include=grub2 stable "$CHROOT"

}

##### ##### ##### 	MAIN 		#####  #####  #####
##if __name__ != __main__
[[ $0 != ${BASH_SOURCE[0]} ]] && return

[[ -r "$VM_DISK_IMG" ]] && echo "$VM_DISK_IMG will be created, so must not be present!" && exit 1

touch $VM_DISK_IMG
truncate -s $VM_DISK_SZ $VM_DISK_IMG

mkdir -p $CHROOT

if [[ $UEFI ]]; then
	formatUEFI "$VM_DISK_IMG"
else
	exit 111 #TODO update for multi OS
	formatBiosMBR "$VM_DISK_IMG"
	mount ${LOOPDEV}p1 $CHROOT
fi
trap "__chrootExit $CHROOT || (killall gpg-agent && umount $CHROOT); losetup -D" EXIT
##[[ $DEBUG ]] && trap "" EXIT

if [[ $DEBUG ]]; then
	sgdisk -p "$LOOPDEV"; lsblk -f "$LOOPDEV";
	read -p "the above parts layout is good ?? "
fi

p=$UEFI_FIRST_ROOTFS_PART
for distro in DEBIAN ARCH; do
	mountUEFI ${LOOPDEV} "$CHROOT" $((p++))

	${distro}BasePrepare
	grubSetSerialConsoleQemu "$CHROOT"

	# CHROOT SETUP
	# users
	echo """
	#!/bin/bash
	$DEBUG
	set -e
	export PATH=\$PATH:/sbin

	$( ${distro}InitChroot )
	echo -n test | passwd -s

	useradd u
	echo -n test | passwd -s u
	mkdir -p /home/u && chown u:u -R /home/u
	""" | tr -d '\t' > "$CHROOT/$INIT_CHROOT"

	cat "$CHROOT/$INIT_CHROOT"


	if [[ $UEFI ]]; then
		echo "grub-install --target=x86_64-efi --no-nvram ${LOOPDEV}p2 --efi-directory=/boot" >>  "$CHROOT/$INIT_CHROOT"
	fi

	chmod 0700 $CHROOT/$INIT_CHROOT
	[[ $RAMBOOT ]] && ${distro}Ramboot
	__chroot $CHROOT $INIT_CHROOT $distro

	[[ $DEBUG ]] && read -p "Done $distro!!!! press anything to continue!"
	#to me gpg stays pending even at this point... blocking umount
	pgrep -f gpg | grep "$CHROOT" | xargs kill || true
	sleep 1

	cp $CHROOT/boot/grub/grub.cfg $CHROOT/boot/grub/grub.cfg.$distro
	__umount "$CHROOT"
done
