#!/bin/bash

SOURCE_DIR="$(realpath "$(dirname "$0")")"
TARGET_DIR="$1/disk-unlocker"
[ -n "$1" ] || { echo "need target dir argument! (eg. $0 /usr/src)"; exit 1; }
[ -e "$TARGET_DIR" ] && { echo "$TARGET_DIR already exist; refusing to blindly overwrite. Remove it and try again"; exit 1; }

set -e -x
mkdir -p "$TARGET_DIR/initramfs"

cp "$SOURCE_DIR/mkunlocker.sh" "$TARGET_DIR/"
chmod 754 "$TARGET_DIR/mkunlocker.sh"

cp "$SOURCE_DIR/initramfs/mkinitramfs.sh" "$TARGET_DIR/initramfs"
chmod 754 "$TARGET_DIR/initramfs/mkinitramfs.sh"

cp "$SOURCE_DIR/kernel-config" "$TARGET_DIR/"
chmod 644 "$TARGET_DIR/kernel-config"

tar zxvpf "$SOURCE_DIR/initramfs/rootfs-basedirs.tgz" -C "$TARGET_DIR/initramfs/"
cp -rav "$SOURCE_DIR/initramfs/rootfs" "$TARGET_DIR/initramfs"

echo
echo "Do you wish to set root password inside $TARGET_DIR/initramfs/rootfs/etc/passwd?"
select yn in "Yes" "No"; do
	case $yn in
		Yes)
			PSWD="$(mkpasswd -5)"
			sed -i -e "s#root:x:#root:$PSWD:#" "$TARGET_DIR/initramfs/rootfs/etc/passwd"
			break;;
		No) break;;
	esac
done

echo -e "All done!\n\nPlease adjust config variables in:\n- $TARGET_DIR/mkunlocker.sh\n- $TARGET_DIR/initramfs/mkinitramfs.sh\n- $TARGET_DIR/initramfs/rootfs/etc/unlocker.conf\n\nand put encrypted disk password file into $TARGET_DIR/initramfs/rootfs/etc/disk_key.enc"
