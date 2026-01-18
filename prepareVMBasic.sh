#!/bin/bash
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


set -ex

umask 0022

CHROOT="${CHROOT-/mnt/tmp}"
INIT_CHROOT="${INIT_CHROOT-/root/init.sh}"
VM_DISK_IMG="${VM_DISK_IMG-vm.raw}"
VM_DISK_SZ=${VM_DISK_SZ-'3g'}

BASE_PKGS="base linux-firmware linux-hardened grub dhcpcd sudo"
BASE_PKGS+=" lsof util-linux which python3 m4 patch man"
EXTRA_PKGS0="dhcpcd curl vim git openssh tmux tree wget pcre2 pcre openbsd-netcat fish"
EXTRA_PKGS1="sqlite diffutils cryptsetup ctags iptables usbutils usb_modeswitch usbguard usbview xdp-tools nvim"
EXTRA_PKGS1+=" xf86-video-fbdev xorg xorg-xinit i3 firefox grub"
touch $VM_DISK_IMG
truncate -s $VM_DISK_SZ $VM_DISK_IMG

fdisk $VM_DISK_IMG << EOF
o
n




w
EOF
fdisk -l $VM_DISK_IMG

losetup -P -f  $VM_DISK_IMG

mkfs.ext4 /dev/loop0p1
mkdir -p $CHROOT
mount /dev/loop0p1 $CHROOT

trap "umount $CHROOT || (killall gpg-agent && umount $CHROOT); losetup -D" EXIT
pacstrap -K $CHROOT $BASE_PKGS

#add console to linux kernel cmdline
python3 -c """
with open('$CHROOT/etc/default/grub') as f: lines = f.readlines()
#remove dflts
for i,l in enumerate(lines):
	if any(x in l for x in ('GRUB_TIMEOUT', 'GRUB_CMDLINE_LINUX_DEFAULT',
		'GRUB_TERMINAL', 'GRUB_SERIAL_COMMAND')):
		lines[i]=''

lines.append('GRUB_TIMEOUT=1')
lines.append('GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=5 console=ttyS0,115200\"')

lines.append('GRUB_TERMINAL=\"console serial\"')
lines.append('GRUB_SERIAL_COMMAND=\"serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1\"')

with open('$CHROOT/etc/default/grub', 'w') as f: f.write('\n'.join(lines))

"""

echo """
#!/bin/bash
echo -n test | passwd -s

useradd u
echo -n test | passwd -s u
mkdir -p /home/u && chown u:u -R /home/u

pacman -Syu --noconfirm $EXTRA_PKGS0 #$EXTRA_PKGS1

mkinitcpio -P

mkdir -p /boot/grub
grub-install --target=i386-pc /dev/loop0
grub-mkconfig -o /boot/grub/grub.cfg
""" > $CHROOT/$INIT_CHROOT
chmod 0700 $CHROOT/$INIT_CHROOT
arch-chroot $CHROOT $INIT_CHROOT



#to me gpg stays pending even at this point... blocking umount
pgrep -fa gpg | grep "$CHROOT" | awk '{print $1}' | xargs kill
sleep 1
