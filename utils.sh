set -ex

LOOPDEV=${LOOPDEV-'/dev/loop0'}

## DISK-UTILS
#fdisk create menu: num, start, size/end
function formatBiosMBR
{
	local -r disk="$1"

	fdisk "$disk" <<- EOF
	o
	n




	w
	EOF

	losetup -P -f  "$disk"
	mkfs.ext4 ${LOOPDEV}p1
}


function __formatUEFIHybrid
{
	local -r disk="$1"

	sgdisk -Z "$disk"
	# Create EFI System Partition (700MB)
	# -t: type code, 1: partition number, EF00: EFI System Partition, bit 2 (legacy BIOS bootable)
	sgdisk -n 1:0:+700M -t 1:EF00 -A 1:set:2 $disk
	# Create rootfs partition using remaining space, 8300: Linux filesystem
	sgdisk -n 2:0:0 -t 2:8300 $disk

}

function __formatUEFI
{
	local -r disk="$1"

	sgdisk -Z "$disk"

	sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS" $disk
	# Create EFI System Partition (700MB)
	# -t: type code, 2: partition number, EF00: EFI System Partition, bit 2 (legacy BIOS bootable)
	sgdisk -n 2:0:+700M -t 2:ef00 -c 2:"EFI" $disk
	# Create rootfs partition using remaining space, 8300: Linux filesystem
	sgdisk -n 3:0:0 -t 3:8300 -c 3:"ROOTFS" $disk

}
function formatUEFI
{
	local -r disk="$1"

	#__formatUEFIHybrid "$disk" #TODO not working then on chroot for grub-legacy install...
	__formatUEFI "$disk" #extra part just f or mbr grub....

	losetup -P -f "$disk"
	mkfs.vfat -F32 ${LOOPDEV}p2
	mkfs.ext4 ${LOOPDEV}p3
}

function mountUEFI
{
	local -r loop=$1
	local -r chroot=$2

	mount ${loop}p3 "$chroot"
	mkdir $CHROOT/boot
	mount ${LOOPDEV}p2 $CHROOT/boot
}

## SYS-MISC
#add console to linux kernel cmdline
function grubSetSerialConsoleQemu
{
local -r chroot="$1"
local -r __grub="$chroot/etc/default/grub"

[[ ! -r "$__grub" ]] && return -1

python3 -c """
with open('$chroot/etc/default/grub') as f: lines = f.readlines()
#remove dflts
for i,l in enumerate(lines):
	if any(x in l for x in ('GRUB_TIMEOUT', 'GRUB_CMDLINE_LINUX_DEFAULT',
		'GRUB_TERMINAL', 'GRUB_SERIAL_COMMAND')):
		lines[i]=''

lines.append('GRUB_TIMEOUT=1')
lines.append('GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=5 console=ttyS0,115200\"')

lines.append('GRUB_TERMINAL=\"console serial\"')
lines.append('GRUB_SERIAL_COMMAND=\"serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1\"')

with open('$chroot/etc/default/grub', 'w') as f: f.write('\n'.join(lines))

"""

}

function __chroot
{
local -r chroot=$1
local -r init_chroot=$2
local -r distro=$3

if [[ $distro == "ARCH" ]]; then
	arch-chroot $chroot $init_chroot
else
	mount --bind /sys $chroot/sys
	mount --bind /dev $chroot/dev
	mount --bind /proc $chroot/proc
	chroot "$chroot" "$init_chroot"
fi

return $?
}

function __chrootExit
{
local -r chroot=$1
local -r distro=$2

if [[ $distro != "ARCH" ]]; then
	umount $chroot/sys $chroot/dev $chroot/proc || true
fi
umount $chroot/boot $chroot
}

### TESTS
function formatTests
{
losetup -D
TESTDISK='/tmp/d'
rm -f "$TESTDISK" && touch "$TESTDISK" && truncate -s 1G "$TESTDISK"

formatBiosMBR  "$TESTDISK"
sleep .1
lsblk -f ${LOOPDEV}
read -p "formatBiosMBR ENDED"
losetup -D


rm -f "$TESTDISK" && touch "$TESTDISK" && truncate -s 1G "$TESTDISK"

formatUEFI  "$TESTDISK"
sleep .1
lsblk -f ${LOOPDEV}
losetup -D
read -p "formatUEFI ENDED"
}

##if __name__ == __main__
if [[ $0 == ${BASH_SOURCE[0]} ]]; then

formatTests

fi
