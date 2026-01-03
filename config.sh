VM_DISK_IMG="${VM_DISK_IMG-$TMPD/vm.raw}"
VM_DISK_SZ=${VM_DISK_SZ-'5000M'}
UEFI=${UEFI-1}
DISTRO=( DEBIAN ARCH )
CONSOLE_BOOT=${CONSOLE_BOOT-1}

TMPD="${TMPD-/tmp/${0/.sh/}}"
MAIN_CHROOT="${MAIN_CHROOT-/root/init.sh}"
PKG_CHROOT="${PKG_CHROOT-/root/pkgInstall.sh}"
COMPRESS_CMD=${COMPRESS_CMD-"xz -vv0T0"}

DISTRO_LOOP_SZ=${DISTRO_LOOP_SZ-"5g"}

DISTRO_AR_MNT=${DISTRO_AR_MNT-"$TMPD/ARCHIVES"}

#PKGS to install
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
DEBIAN_BASE_PKGS+=" $BASE_PKGS_0"
DEBIAN_BASE_PKGS+=" m4 patch man"
DEBIAN_EXTRA_PKGS0="$DEBIAN_BASE_PKGS"
DEBIAN_EXTRA_PKGS0+=" openssh-server netcat-openbsd iptables nftables pcre2-utils"
DEBIAN_EXTRA_PKGS1=" sqlite3 sqlite-utils sqlite3-tools diffutils cryptsetup universal-ctags"
DEBIAN_EXTRA_PKGS1+=" usbutils usb-modeswitch usbguard usbview usbtop usb* xdp-tools"
DEBIAN_EXTRA_PKGS2="xorg xinit xserver-xorg-video-fbdev i3 firefox-esr xfce4-terminal"

