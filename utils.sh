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


function formatUEFI
{
	local -r disk="$1"

	fdisk "$disk" <<- EOF
	g
	n


	+700M

	n




	w
	EOF

	losetup -P -f "$disk"
	mkfs.vfat -F32 ${LOOPDEV}p1
	mkfs.ext4 ${LOOPDEV}p2
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

if [[ $distro == "arch" ]]; then
	arch-chroot $chroot $init_chroot
else
	mount --bind /sys $chroot/sys
	mount --bind /dev $chroot/dev
	mount --bind /proc $chroot/proc
	chroot "$chroot" "$init_chroot"
fi

return $?
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
