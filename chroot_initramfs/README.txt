This describes how to create a mini-Gentoo install inside a chroot in order to
compile binaries later used to build initramfs/disk unlocker.

You'll need my overlay installed. See https://github.com/dex6/dexlay. I have
it on the host and copy relevant config to chroot, but it should be pretty
easy to install inside chroot only.

It should be also possible to do this on a non-Gentoo host with some minor
changes. At least additionally you'll need to download Portage tree snapshot
and modify chroot.sh script to not use the host one. And probably more.

Based on:
- https://wiki.gentoo.org/wiki/Chroot
- https://wiki.gentoo.org/wiki/Steam#Chroot


1. Create target dir (might as well install on a dedicated LVM; 1-2GB should
be more than enough)
# mkdir /mnt/chroot_initramfs
# cd /mnt/chroot_initramfs

2. Download stage3:
-> https://www.gentoo.org/downloads/#other-arches -> amd64 stage3 nomultilib
# wget https://mirror.netcologne.de/gentoo/releases/amd64/autobuilds/current-stage3-amd64-nomultilib/stage3-amd64-nomultilib-20200610T214505Z.tar.xz
(previously I was using uClibc, but it's not widely used, so it lacks extensive testing and causes too much headaches when compilation fails...)

3. Unpack:
# tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

4. Add config files from this repo and from base system:
# rm -f /mnt/chroot_initramfs/etc/portage/savedconfig/sys-apps/busybox-*
# cp -r ./etc/* /mnt/chroot_initramfs/etc/
# cp ./chroot.sh /mnt/chroot_initramfs/
# mkdir /mnt/chroot_initramfs/etc/portage/repos.conf/
# cp /etc/portage/repos.conf/{gentoo,dexlay}.conf /mnt/chroot_initramfs/etc/portage/repos.conf/

5. Enter the chroot using helper script which does the mounting etc.
# /mnt/chroot_initramfs/chroot.sh enter

6. When run for the first time, some extra setup is needed:
# eselect profile set default/linux/amd64/17.1/no-multilib
# emerge -avuDN @world
# eselect news read  # you probably have seen them already...
# emerge -a --depclean
# . /etc/profile
# (optionally, but recommended) emerge -ave @world

7. Emerge packages needed later in initramfs / disk unlocker
# emerge -av lvm2 efibootmgr inotify-tools kexec-tools
# emerge -av sys-boot/plymouth::dexlay
# emerge -av thinkpad-themes::dexlay liberation-fonts
# emerge -av sed-opal-unlocker::dexlay
