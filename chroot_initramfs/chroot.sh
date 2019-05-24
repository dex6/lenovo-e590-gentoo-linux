#!/bin/bash

[ $EUID -eq 0 ] || { echo "Must be root!"; exit 1; }
CHROOT="/mnt/chroot_initramfs"

mount_fs() {
	mountpoint -q "$CHROOT/dev" && return  # check if already mounted

	mount --rbind /dev "$CHROOT/dev"
	mount --make-rslave "$CHROOT/dev"
	mount -t proc /proc "$CHROOT/proc"
	mount --rbind /sys "$CHROOT/sys"
	mount --make-rslave "$CHROOT/sys"
	mount -t tmpfs tmpfs "$CHROOT/tmp"
	mkdir -p "$CHROOT/mnt/gentoo"
	mount --rbind /mnt/gentoo "$CHROOT/mnt/gentoo"
	mount --make-rslave "$CHROOT/mnt/gentoo"

	cp /etc/resolv.conf "$CHROOT/etc/"
}

umount_fs() {
	mountpoint -q "$CHROOT/dev" || return
	umount -R "$CHROOT/mnt/gentoo"
	umount -R "$CHROOT/tmp"
	umount -R "$CHROOT/sys"
	umount -R "$CHROOT/proc"
	umount -R "$CHROOT/dev"
}

enter_chroot() {
	mount_fs
	echo ""                                > "$CHROOT/tmp/.bashrc"
	echo "env-update 2>/dev/null"         >> "$CHROOT/tmp/.bashrc"
	echo "source /etc/profile"            >> "$CHROOT/tmp/.bashrc"
	echo "export LC_ALL=C"                >> "$CHROOT/tmp/.bashrc"
	echo "export PS1=\"(chroot) \$PS1\""  >> "$CHROOT/tmp/.bashrc"
	chroot "$CHROOT" /bin/env -i HOME="/root" TERM="$TERM" \
		/bin/bash --rcfile /tmp/.bashrc -i
}

case "$1" in
	mount|start)
		mount_fs
		;;
	umount|stop)
		umount_fs
		;;
	enter)
		enter_chroot
		;;
	*)
		echo -ne "Usage:\n\t$0 <enter|mount|umount>\n"
		exit 1
		;;
esac
