TMPD="${TMPD-/tmp/${0/.sh/}}"
VM_DISK_IMG="${VM_DISK_IMG-$TMPD/vm.raw}"
VM_DISK_SZ=${VM_DISK_SZ-'5000M'}
UEFI=${UEFI-1}
DISTRO=( DEBIAN ARCH )
CONSOLE_BOOT=${CONSOLE_BOOT-1}

MAIN_CHROOT="${MAIN_CHROOT-/root/init.sh}"
PKG_CHROOT="${PKG_CHROOT-/root/pkgInstall.sh}"
COMPRESS_CMD=${COMPRESS_CMD-"xz -vv0T0"}

DISTRO_LOOP_SZ=${DISTRO_LOOP_SZ-"5g"}

DISTRO_AR_MNT=${DISTRO_AR_MNT-"$TMPD/ARCHIVES"}

if [[ ! $SSH_PK ]]; then
	SSH_PK=/tmp/sshK
	yes | ssh-keygen -f "$SSH_PK" -trsa -b4096 -N ''
fi
#deb/arch, most simple common names
BASE_PKGS0="dhcpcd curl vim git tmux tree wget fish sudo man"
BASE_PKGS0+=" diffutils lsof util-linux which python3 m4 patch lshw dmidecode"
BASE_PKGS0+=" dstat htop iotop iftop iw iwd net-tools "
BASE_PKGS0+=" cryptsetup openssl sshfs socat iptables nftables iproute2"
BASE_PKGS1=" pciutils usbutils usbguard usbview xdp-tools"
BASE_PKGS1+=" ntfs-3g btrfs-progs f2fs-tools smartmontools nmap tcpdump "

ARCH_BASE_PKGS="base linux-firmware linux-hardened grub"
ARCH_BASE_PKGS0="$BASE_PKGS0 wireless_tools"
ARCH_BASE_PKGS0+=" openssh openbsd-netcat pcre2 pcre"
ARCH_BASE_PKGS1="$BASE_PKGS1 usb_modeswitch sqlite ctags"
ARCH_BASE_PKGS2="xorg xorg-xinit xf86-video-fbdev xf86-video-vesa i3 firefox xfce4-terminal"

DEBIAN_BASE_PKGS="linux-base linux-image-amd64 systemd systemd-sysv initramfs-tools"
DEBIAN_BASE_PKGS+=" $BASE_PKGS0 firmware-linux-free "
DEBIAN_BASE_PKGS+=" util-linux-extra login passwd wireless-tools"
DEBIAN_BASE_PKGS+=" grub-efi-amd64-signed"
DEBIAN_BASE_PKGS0="$DEBIAN_BASE_PKGS"
DEBIAN_BASE_PKGS0+=" openssh-server netcat-openbsd pcre2-utils"
DEBIAN_BASE_PKGS1=" sqlite3 sqlite-utils sqlite3-tools universal-ctags"
DEBIAN_BASE_PKGS1+=" $BASE_PKGS1 usb-modeswitch usbtop usb* xdp-tools"
DEBIAN_BASE_PKGS2="xorg xinit xserver-xorg-video-fbdev i3 firefox-esr xfce4-terminal"

DEBIAN_ADV0_PKGS="eject udisks2 hdparm"
DEBIAN_ADV0_PKGS+=" dosfstools exfatprogs"
DEBIAN_ADV0_PKGS+=" acpid p7zip-full"
DEBIAN_ADV1_PKGS="gddrescue testdisk foremost "
DEBIAN_ADV1_PKGS+=" scalpel sleuthkit autopsy guymager dc3dd parted gpart psmisc procps"
DEBIAN_ADV2_PKGS="wireshark"

##if __name__ == __main__
if [[ $0 == ${BASH_SOURCE[0]} ]]; then
ARCH=( $ARCH_BASE_PKGS $ARCH_BASE_PKGS0 $ARCH_BASE_PKGS1 $ARCH_BASE_PKGS2 )
DEB=(  $DEBIAN_BASE_PKGS0 $DEBIAN_BASE_PKGS1 $DEBIAN_BASE_PKGS2 $DEBIAN_ADV0_PKGS $DEBIAN_ADV1_PKGS  $DEBIAN_ADV2_PKGS )

echo "${ARCH[@]}"
echo "${DEB[@]}"
fi
