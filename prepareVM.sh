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

[[ $DEBUG == 1 ]] && set -x && export DEBUG="set -x" && CACHE=${CACHE-/tmp/CACHE/}

umask 0022

SCRIPTDIR=$(realpath $(dirname ${BASH_SOURCE[@]}))

LOOPDEV=${LOOPDEV-$(losetup -f)} #(dflt loopdev for OSs prepare is next avail)
. $SCRIPTDIR/config.sh
. $SCRIPTDIR/utils.sh


function ARCHPkgInstall
{
local -r __chrootDir="$1"

echo """
#!/bin/bash
set -ex
pacman -Syu --noconfirm $ARCH_BASE_PKGS0 $ARCH_BASE_PKGS1 $ARCH_BASE_PKGS2 \
 $ARCH_ADV_PKGS0 $ARCH_ADV_PKGS1 $ARCH_ADV_PKGS2
""" > "$__chrootDir/$PKG_CHROOT"

chmod 0700 "$__chrootDir/$PKG_CHROOT"
__chrootWrap "$__chrootDir" "$PKG_CHROOT"
}

function ARCHInitChroot
{
echo """
mkinitcpio -P || true

mkdir -p /boot/grub
"""
}



function DEBIANPkgInstall
{
local -r __chrootDir="$1"

echo """
#!/bin/bash
set -ex

#prepare keys layout to avoid forced interaction during install
mkdir -p /etc/default/
echo \
\"\"\"
# KEYBOARD CONFIGURATION FILE

# Consult the keyboard(5) manual page.

XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""

BACKSPACE="guess"
\"\"\" > /etc/default/keyboard
#cat /etc/default/keyboard | debconf-set-selections
#TODO fix above to force keyboard layout avoiding interactions
#the bellow opts might silently fail?
export DEBIAN_FRONTEND=noninteractive

echo 1 | apt install -y $DEBIAN_BASE_PKGS0 $DEBIAN_BASE_PKGS1 $DEBIAN_BASE_PKGS2
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

echo 1 | debootstrap --verbose --variant=buildd --merged-usr --include=grub2 \
	    stable "$__chrootDir"

}


function __grubCfg
{
	local -r __distro=$1
	echo /boot/grub/grub.$__distro.cfg
}

function servicesInitChroot
{

echo """

echo \
\"\"\"
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
Port 2222
\"\"\" >> /etc/ssh/sshd_config
chown u:u -R /home/u/

mkdir -p /etc/systemd/system/
echo \
\"\"\"
#/etc/systemd/system/start.service
[Unit]
Description="START SCRIPT"

[Service]
Type=oneshot
ExecStart=/root/start.sh

[Install]
WantedBy=multi-user.target
\"\"\" > /etc/systemd/system/start.service

systemctl enable start
systemctl enable sshd
systemctl disable dhcpcd

echo \
\"\"\"#!/bin/bash
set -x

/usr/sbin/sysctl -w net.ipv4.icmp_echo_ignore_all=1
/usr/sbin/sysctl -w net.ipv4.conf.all.arp_announce=2
/usr/sbin/sysctl -w net.ipv4.conf.all.arp_ignore=1

/usr/sbin/sysctl -w net.ipv6.conf.all.disable_ipv6=1

IP=10.0.2.15/24
IF=\\\$(ls -a /sys/class/net/ | grep -vie lo -e wlan -e '\.' | grep -e eth -e en | head -1 )
ip l set up \\\$IF
ip a flush \\\$IF
ip a add \\\$IP dev \\\$IF

# IPTABLES
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

iptables -A INPUT -p udp -m udp --sport 53 -m conntrack --ctstate ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp -m tcp --sport 443 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -s 10.0.2.0/24 -d 10.0.2.0/24 -p tcp -m tcp --dport  2222 -j ACCEPT
iptables -A INPUT -s 10.0.2.0/24 -d 10.0.2.0/24 -p tcp -m tcp --sport  2222 -j ACCEPT
iptables -A INPUT -j LOG
iptables -A OUTPUT -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
iptables -A OUTPUT -p tcp -m tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -s 10.0.2.0/24 -d 10.0.2.0/24 -p tcp -m tcp --sport 2222 -j ACCEPT
iptables -A OUTPUT -s 10.0.2.0/24 -d 10.0.2.0/24 -p tcp -m tcp --dport 2222 -j ACCEPT

\"\"\" > /root/start.sh
chmod 0700 /root/start.sh

"""

}
function chrootScriptGen
{

local -r __distro="$1"
local -r __chrootDir="$2"
local -r __chrootScriptPath="$3"
local -r __sshPKey="$4"
local -r ____grubCfg=$(__grubCfg "$__distro")

[[ ! -r $__sshPKey ]] && return 1

mkdir -p $__chrootDir/home/u/.ssh/
ssh-keygen -y -f $__sshPKey >  $__chrootDir/home/u/.ssh/authorized_keys

# TMPD SETUP
# users
echo """
#!/bin/bash
$DEBUG
set -e
export PATH=\$PATH:/sbin

$( ${distro}InitChroot )
grub-install --target=i386-pc $LOOPDEV
grub-mkconfig -o $____grubCfg

## USER
echo -n test | passwd -s

useradd u || true
#TODO bcs of DEBUG, might already exist

echo -n test | passwd -s u
mkdir -p /home/u && chown u:u -R /home/u

# SERVICES
(
$( servicesInitChroot )
) || true
""" | tr -d '\t' > "$__chrootScriptPath"
if [[ $UEFI ]]; then
	echo "grub-install --target=x86_64-efi --no-nvram ${LOOPDEV}p${LOOPDEV_BOOTPART} --efi-directory=/boot" \
		>>  "$__chrootScriptPath"
fi
${distro}Ramboot $__chrootDir

chmod 0700 "$__chrootScriptPath"
[[ ! $DEBUG ]] || cat "$__chrootScriptPath"

}

DISTRO_LOOPDEVS=()
function prepareDistroLoop
{
	local -r __distro=$1
	local -r __chroot="$TMPD/$__distro"
	local -r __chrootImg="$__chroot.img"

	mkdir -p $__chroot
	touch "$__chrootImg"
	truncate -s $DISTRO_LOOP_SZ "$__chrootImg"

	mkfs.ext4 "$__chrootImg"
	#flock /tmp/ \
	local -r __loop=$(losetup -f)
	losetup -f $__chrootImg
	DISTRO_LOOPDEVS+=($__loop)

	mount $__loop "$__chroot"
}

function __unpackFromCache
{
	local -r __distro=$1
	local -r __chroot="$TMPD/$__distro"
	local -r __cachedArchive=${2-"$CACHE/$__distro.txz"}

	cd $__chroot
	tar xf "$__cachedArchive"
	cp "$__cachedArchive" $DISTRO_AR_MNT

}

function installDistro
{
	local -r __distro=$1
	local -r __chroot="$TMPD/$__distro"

	${__distro}Strap 	 "$__chroot" #|| true
	${__distro}PkgInstall	 "$__chroot"
}

function compressDistro
{
	local -r __distro=$1
	local -r __chroot="$TMPD/$__distro"


	cd $__chroot
	rm -rf var/cache
	tar cf /tmp/$__distro.txz -I "$COMPRESS_CMD" --exclude ./boot *
	mv /tmp/$__distro.txz $DISTRO_AR_MNT
	cd $SCRIPTDIR
}

function __cleanup
{
	set +e

	cd $SCRIPTDIR

	[[ $DEBUG && ! $OK ]] && mount && read -p "__cleanup, ERR!"

	pkill -KILL gpg-agent;
	umount ${LOOPDEV}p${LOOPDEV_COMPRESSED_DISTROS};
	umount ${LOOPDEV}p${LOOPDEV_COMPRESSED_DISTROS};
	umount ${LOOPDEV}p${LOOPDEV_BOOTPART};
	umount ${LOOPDEV}p${LOOPDEV_BOOTPART};
	umount ${LOOPDEV}p${LOOPDEV_BOOTPART};
	umount $TMPD/boot; umount $DISTRO_AR_MNT; umount  $TMPD/boot;
	losetup -d $LOOPDEV; losetup -D

	#for distro in ${DISTRO[@]}; do umount "$TMPD/$distro"; done
	for loop in ${DISTRO_LOOPDEVS[@]}; do
		umount $loop;
		losetup -d $loop;
	done
}

##### ##### ##### 	MAIN 		#####  #####  #####
[[ $0 != ${BASH_SOURCE[0]} ]] && return		##if __name__ != __main__

[[ -r "$VM_DISK_IMG" ]] && echo "$VM_DISK_IMG will be created, so must not be present!" && exit 1

mkdir -p $(dirname $VM_DISK_IMG)
touch $VM_DISK_IMG
truncate -s $VM_DISK_SZ $VM_DISK_IMG
rootUUID=""

if [[ $UEFI ]]; then
	formatUEFI "$VM_DISK_IMG" rootUUID
else
	exit 111 #TODO update for multi OS
	#formatBiosMBR "$VM_DISK_IMG"
	#mount ${LOOPDEV}p1 $TMPD
fi

trap __cleanup EXIT

if [[ $DEBUG ]]; then
	sgdisk -p "$LOOPDEV"; lsblk -f "$LOOPDEV";
	read -p "above there's the parts layout	"
fi

mkdir -p "$TMPD/boot" "$DISTRO_AR_MNT"
mount ${LOOPDEV}p${LOOPDEV_BOOTPART} "$TMPD/boot"
mount ${LOOPDEV}p${LOOPDEV_COMPRESSED_DISTROS} "$DISTRO_AR_MNT"

#Installation of base OSs: create a loopdev per OS and get the pkgs there

__distros=( ${DISTRO[@]} )
for distro in ${DISTRO[@]}; do	prepareDistroLoop $distro; done

if [[ $DEBUG && -d $CACHE ]]; then 	#if CACHE, just untar them
	for distro in ${DISTRO[@]}; do
		__unpackFromCache $distro &
	done
	for distro in ${DISTRO[@]}; do wait -n; done
else					#install from scratch
	for distro in ${DISTRO[@]}; do
		(installDistro 	$distro 2>&1 | tee "$distro.log") &
	done
	for distro in ${DISTRO[@]}; do wait -n; done
fi

[[ $DEBUG ]] && read -p "distro pkgs ready!, now final chroot init!"

#create ramdisks with chroot scripts per OS
#TODO for parallel compute at least flock on a common dir to avoid grub raceConds!
for distro in ${DISTRO[@]}; do
	__chroot="$TMPD/$distro"
	[[ $CONSOLE_BOOT == 1 ]] && grubSetSerialConsoleQemu "$__chroot"

	#copy distro /boot/* to target /boot partition, not a must but proper
	cp -r $__chroot/boot/* $TMPD/boot
	#mount (again) the boot part into the OS's /boot for chroot ramdisk gen
	mount ${LOOPDEV}p${LOOPDEV_BOOTPART} $__chroot/boot
	#NB: above copied stuff should be present now in OS's /boot

	chrootScriptGen "$distro" "$__chroot" "$TMPD/$distro/$MAIN_CHROOT" "$SSH_PK"
	__chrootWrap "$__chroot" "$MAIN_CHROOT" 2>&1 | tee -a "$distro.log"

done

cp $TMPD/boot/grub/grub.ARCH.cfg $TMPD/boot/grub/grub.cfg
__grub="$TMPD/boot/grub/grub.cfg"
grubFixUUID "$__grub"  "$rootUUID"
lsblk; df -h
[[ $DEBUG ]] && read -p "distros STRAPed, now compressing"
for distro in ${DISTRO[@]}; do
	__chroot="$TMPD/$distro"

	compressDistro	$distro


	sync
	sync
	set +e
	sleep 1.4;
	lsof -f -- $__chroot/boot ; lsof -f -- $__chroot
	lsof +f -- $__chroot/boot ; lsof +f -- $__chroot
	lsof  -- $__chroot/boot ; lsof  -- $__chroot
	set -e

	umount $__chroot/boot
	umount $__chroot ||umount -l $__chroot
done

[[ $DEBUG ]] && OK=1

#make proper EFI files layout
cd "$TMPD/boot"
cp -r EFI/arch EFI/BOOT
cd EFI/BOOT/
cp grubx64.efi BOOTx64.EFI || cp * BOOTx64.EFI
cd $SCRIPTDIR

umount "$TMPD/boot"
umount "$DISTRO_AR_MNT"

#to me gpg for pacman stays pending even at this point... blocking umount
pgrep -f gpg | grep "$TMPD" | xargs kill -KILL || pkill -KILL gpg || true
sleep 1
