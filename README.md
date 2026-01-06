CompressedMultiRamBoot
----------------------

Create a disk image (as a raw file, editable with a loopdevice)
including multiple OS, created from scratch,
stored with custom compression in a data partition.
The rootfs of the OS selected at boot will be copied in ram (in a tmpfs)
allowing to remove the disk as soon as the OS finished the boot phase.

# Use Cases
- volatile systems, for highly dangerous experiments (untrusted software/hardware, misc experiments)
    since the system might not be compromised if removed as the first user interaction done!
- integrity of executed software, since the whole installation process happens through
    official tools, downloading software only with https from the official SW repo sources.
    (TODO: add integrity validation of distros root gpg keys...)
- multi OS to boot from a USB, ready to use with (essential) packages, but to run FAST!! since copied entirely in RAM

# Supports
- DEBIAN and ARCH-LINUX installation creation from scratch with debootstrap and arch-strap
  I thought to use
    - ARCH-LINUX as fully fledged, super updated distro (so more packages there),
    - DEBIAN as minimal and stable distro (very minimal packages)
    - both the above distro selected pkgs include enough to load Xorg, i3 and firefox.

- Minimal setup for security
    - minimal iptables
    - kernel networking restrictions
    - no NetworkManager (dhcpcd, iwd, iw instead)
    - ssh key generated at image creation time in `/tmp/sshK`,
        and stored as `authorized_key` for all the distros installations

- MBR-UEFI dual boot capability thanks to a special partitioning and path use
- distributions storage with custom compression level
- initram script for all distribution to hook at the end of the boot process
    - move mount the data partition (the linux kernel `root=<DATA-PART-UUID>` param in GRUB)
    - uncompress and extract the distro in a tmpfs
    - make linux boot from there

- Multiple pkg layers to add at boot time,
    to adapt the system to boot with the ram availability of the target system
# Post creation accessing
Currently it's required to use arch-linux for creating the disk image

The password for the user `u` and `root` is `test`>

At image creation time a ssh private key at `/tmp/sshK` will be created,
that can be used later to access both the installed distro after booted at port 2222 with ssh

EFI support vary from various systems... it might be needed to manually add an entry pointing to `/EFI/BOOT/BOOTx64.EFI`.