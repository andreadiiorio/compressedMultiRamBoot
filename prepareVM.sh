#!/bin/bash
#Copyright 2025 Andrea Di Iorio
#Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
#1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
#2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
#3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

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
for i,l in enumerate(lines):
	if l.find('GRUB_TIMEOUT') >= 0:
		lines[i] = 'GRUB_TIMEOUT=1'
		continue
	if l.find('GRUB_CMDLINE_LINUX_DEFAULT') >= 0:
		lines[i] = 'GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=5 console=ttyS0,115200 console=tty0\"'
		break

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
