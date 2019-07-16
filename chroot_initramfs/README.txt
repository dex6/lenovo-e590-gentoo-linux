This describes how to create a mini-Gentoo install inside a chroot in order to
compile binaries later used to build initramfs/disk unlocker.

Based on:
- https://wiki.gentoo.org/wiki/Chroot
- https://wiki.gentoo.org/wiki/Steam#Chroot

1. Create target dir (might as well install on a dedicated LVM; 1-2GB should
be more than enough)
# mkdir /mnt/chroot_initramfs
# cd /mnt/chroot_initramfs

2. Download stage3:
-> https://www.gentoo.org/downloads/#other-arches -> amd64 stage3 vanilla uclibc (cause why not)
# wget https://mirror.netcologne.de/gentoo/releases/amd64/autobuilds/current-stage3-amd64-uclibc-vanilla/stage3-amd64-uclibc-vanilla-20190505.tar.bz2

3. Unpack:
# tar xpvf stage3-*.tar.bz2 --xattrs-include='*.*' --numeric-owner

4. Add config files from this repo and from base system:
# cp -r ./etc/* /mnt/chroot_initramfs/etc/
# cp ./chroot.sh /mnt/chroot_initramfs/
# mkdir /mnt/chroot_initramfs/etc/portage/repos.conf/
# cp /etc/portage/repos.conf/{gentoo,dexlay}.conf /mnt/chroot_initramfs/etc/portage/repos.conf/

5. Enter the chroot using helper script which does the mounting etc.
# /mnt/chroot_initramfs/chroot.sh enter

6. When run for the first time, some extra setup is needed:
# eselect profile set default/linux/amd64/17.0/uclibc
# emerge -avuDN @world
# eselect news read  # you probably have seen them already...
# emerge -a --depclean
# (optionally, but highly recommended) emerge -ave @world

7. Emerge packages needed later in initramfs / disk unlocker
# emerge -av =sys-boot/plymouth-9999::dexlay
# emerge -av thinkpad-themes::dexlay liberation-fonts
# emerge -av libaio::dexlay lvm2
# emerge -av efibootmgr::dexlay
# emerge -av inotify-tools kexec-tools
