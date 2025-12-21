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

[[ $DEBUG == 1 ]] && set -x && export DEBUG="set -x" && export CACHE=/tmp/CACHE/

umask 0022

SCRIPTDIR=$(realpath $(dirname ${BASH_SOURCE[@]}))
. $SCRIPTDIR/utils.sh

CHROOT="${CHROOT-/mnt/tmp}"
MAIN_CHROOT="${MAIN_CHROOT-/root/init.sh}"
PKG_CHROOT="${PKG_CHROOT-/root/pkgInstall.sh}"

VM_DISK_IMG="${VM_DISK_IMG-/tmp/vm.raw}"
VM_DISK_SZ=${VM_DISK_SZ-'5000M'}

UEFI=${UEFI-1}
LOOPDEV=${LOOPDEV-$(losetup -f)} #(dflt loopdev for OSs prepare is next avail)

DISTRO_AR_MNT=${DISTRO_AR_MNT-"/mnt/tmp1"}

DISTRO=( DEBIAN ARCH )
#deb/arch, most simple common names
BASE_PKGS_0="dhcpcd curl vim git tmux tree wget fish sudo man"

ARCH_BASE_PKGS="base linux-firmware linux-hardened grub"
ARCH_EXTRA_PKGS0=$BASE_PKGS_0
ARCH_EXTRA_PKGS0+=" lsof util-linux which python3 m4 patch grub dhcpcd "
ARCH_EXTRA_PKGS0+=" openssh openbsd-netcat iptables nftables pcre2 pcre"
ARCH_EXTRA_PKGS1="sqlite diffutils cryptsetup ctags"
ARCH_EXTRA_PKGS1+=" usbutils usb_modeswitch usbguard usbview xdp-tools"
ARCH_EXTRA_PKGS2="xorg xorg-xinit xf86-video-fbdev xf86-video-vesa i3 firefox xfce4-terminal"

DEBIAN_BASE_PKGS="linux-base linux-image-amd64 systemd systemd-sysv initramfs-tools"
DEBIAN_BASE_PKGS+=" grub-efi-amd64-signed"
DEBIAN_BASE_PKGS+=" lsof util-linux util-linux-extra login sudo passwd iproute2"
DEBIAN_BASE_PKGS+=" m4 patch man"
DEBIAN_EXTRA_PKGS0="$DEBIAN_BASE_PKGS"
DEBIAN_EXTRA_PKGS0+=" openssh-server netcat-openbsd iptables nftables pcre2-utils"
DEBIAN_EXTRA_PKGS1=" sqlite3 sqlite-utils sqlite3-tools diffutils cryptsetup universal-ctags"
DEBIAN_EXTRA_PKGS1+=" usbutils usb-modeswitch usbguard usbview usbtop usb* xdp-tools"
DEBIAN_EXTRA_PKGS2="xorg xinit xserver-xorg-video-fbdev i3 firefox-esr xfce4-terminal"

COMPRESS_CMD=${COMPRESS_CMD-"xz -vv0T0"}

function ARCHPkgInstall
{
local -r __chrootDir="$1"

echo """
#!/bin/bash
set -ex
pacman -Syu --noconfirm $ARCH_EXTRA_PKGS0 $ARCH_EXTRA_PKGS1 $ARCH_EXTRA_PKGS2
""" > "$__chrootDir/$PKG_CHROOT"

chmod 0700 "$__chrootDir/$PKG_CHROOT"
__chrootWrap "$__chrootDir" "$PKG_CHROOT"
}

function ARCHInitChroot
{
echo """
pacman -Syu --noconfirm $ARCH_EXTRA_PKGS0 $ARCH_EXTRA_PKGS1 $ARCH_EXTRA_PKGS2

mkinitcpio -P || true

mkdir -p /boot/grub
grub-install --target=i386-pc /dev/loop0
grub-mkconfig -o /boot/grub/grub.ARCH.cfg
#cp /boot/grub/grub.ARCH.cfg /boot/grub/grub.cfg
"""
}



function DEBIANPkgInstall
{
local -r __chrootDir="$1"

echo """
#!/bin/bash
set -ex
echo 1 | apt install -y $DEBIAN_BASE_PKGS $DEBIAN_EXTRA_PKGS0 $DEBIAN_EXTRA_PKGS1
""" > "$__chrootDir/$PKG_CHROOT"

chmod 0700 "$__chrootDir/$PKG_CHROOT"
__chrootWrap "$__chrootDir" "$PKG_CHROOT"
}

function DEBIANInitChroot
{
echo """
export PATH=\$PATH:/sbin

update-initramfs -k all -u

mkdir -p /boot/grub
grub-install --target=i386-pc /dev/loop0
grub-mkconfig -o /boot/grub/grub.DEBIAN.cfg
#cp /boot/grub/grub.DEBIAN.cfg /boot/grub/grub.cfg
"""
}

__ARCH_RAMBOOT="$SCRIPTDIR/initramfs/arch/ramBoot-tar"
function ARCHRamboot
{
local -r __chrootDir=$1

cp "$__ARCH_RAMBOOT/mkinitcpio.conf"	"$__chrootDir/etc"
mkdir -p "$__chrootDir/etc/initcpio/"
cp -r -f "$__ARCH_RAMBOOT/"*	"$__chrootDir/etc/initcpio/"
#cp "$__ARCH_RAMBOOT/hooks/ramboot"	"$__chrootDir/etc/initcpio/hooks"
#cp "$__ARCH_RAMBOOT/install/ramboot"	"$__chrootDir/etc/initcpio/install/ramboot"
}

__DEB_RAMBOOT="$SCRIPTDIR/initramfs/deb/ramBoot-tar"
function DEBIANRamboot
{
local -r __chrootDir=$1

mkdir -p "$__chrootDir/etc/initramfs-tools/"
cp -a -f "$__DEB_RAMBOOT/"*	"$__chrootDir/etc/initramfs-tools/"
}

function ARCHStrap
{
local -r __chrootDir=$1
mkdir -p "$__chrootDir"

pacstrap -K "$__chrootDir" $ARCH_BASE_PKGS
}


function DEBIANStrap
{
local -r __chrootDir=$1
mkdir -p "$__chrootDir"

debootstrap --verbose --variant=buildd --merged-usr --include=grub2 \
	    stable "$__chrootDir"

}


function initChroot
{

local -r __distro=$1
local -r __chrootDir=$2
local -r __chrootScriptPath=$3

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
""" | tr -d '\t' > "$__chrootScriptPath"
if [[ $UEFI ]]; then
	echo "grub-install --target=x86_64-efi --no-nvram ${LOOPDEV}p2 --efi-directory=/boot" \
		>>  "$__chrootScriptPath"
fi
${distro}Ramboot $__chrootDir

chmod 0700 "$__chrootScriptPath"
[[ $DEBUG ]] && cat "$__chrootScriptPath"

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
	#formatBiosMBR "$VM_DISK_IMG"
	#mount ${LOOPDEV}p1 $CHROOT
fi
trap	"set +e; pkill -KILL gpg-agent;
	umount ${LOOPDEV}p3;umount ${LOOPDEV}p3; ${LOOPDEV}p2;umount ${LOOPDEV}p2;
	umount $CHROOT/boot; umount $DISTRO_AR_MNT; umount  $CHROOT/boot; umount ${LOOPDEV}p2;umount ${LOOPDEV}p2;
	losetup -d $LOOPDEV"  \
	EXIT
#losetup -d $LOOPDEV" EXIT


if [[ $DEBUG ]]; then
	sgdisk -p "$LOOPDEV"; lsblk -f "$LOOPDEV";
	read -p "the above parts layout is good ?? "
fi


mkdir -p "$CHROOT/boot" "$DISTRO_AR_MNT"
mount ${LOOPDEV}p${LOOPDEV_BOOTPART} "$CHROOT/boot"
mount ${LOOPDEV}p${LOOPDEV_COMPRESSED_DISTROS} "$DISTRO_AR_MNT"

__distros=( ${DISTRO[@]} )
#if CACHE, just untar them instead of installing them from scrach
if [[ $DEBUG && -d $CACHE ]]; then
	for distro in ${DISTRO[@]}; do
		__chroot="$CHROOT/$distro"
		mkdir -p $__chroot
		cd $__chroot
		tar xf $CACHE/$distro.txz
		cp $CACHE/$distro.txz $DISTRO_AR_MNT
	done
	__distros=()
	set +e	#the needed -n flag of wait would fail if nothing is started
fi
#NB: the following loops uses __distros so with CACHE they're skipped
#install in a distro's subdir pkgs in parallel!
for distro in ${__distros[@]}; do
	__chroot="$CHROOT/$distro"
	mkdir -p $__chroot
	(
	${distro}Strap 		 "$__chroot" || true
	${distro}PkgInstall	 "$__chroot"
	grubSetSerialConsoleQemu "$__chroot"
	) | tee "$distro.log" &
done
#NB: wait returns the status of the last ID... so do them 1 by 1
wait -n
wait -n
set -e
#compress distro's dirs
for distro in ${__distros[@]}; do
	__chroot="$CHROOT/$distro"
	cd $__chroot
	tar cf $distro.txz -I "$COMPRESS_CMD" --exclude ./boot *
	mv $distro.txz $DISTRO_AR_MNT
done
#end CACHE skippable

#create ramdisks with chroot scripts per OS
#TODO for parallel compute at least flock on a common dir to avoid grub raceConds!
for distro in ${DISTRO[@]}; do
	__chroot="$CHROOT/$distro"
	#cp distro /boot stuff to target /boot partition
	cp -r $__chroot/boot/* $CHROOT/boot
	#mount (again) the boot part into the OS's /boot for chroot ramdisk gen
	mount ${LOOPDEV}p${LOOPDEV_BOOTPART} $__chroot/boot

	initChroot "$distro" "$__chroot" "$CHROOT/$distro/$MAIN_CHROOT"
	__chrootWrap "$__chroot" "$MAIN_CHROOT" | tee -a "$distro.log"

	umount $__chroot/boot
done

cp $CHROOT/boot/grub/grub.ARCH.cfg $CHROOT/boot/grub/grub.cfg

umount "$CHROOT/boot"
umount "$DISTRO_AR_MNT"

#to me gpg for pacman stays pending even at this point... blocking umount
pgrep -f gpg | grep "$CHROOT" | xargs kill -KILL || pkill -KILL gpg || true
sleep 1
