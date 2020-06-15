#!/bin/bash


SOURCE_DIR="$(realpath "$(dirname "$0")")"
TARGET_DIR="$1"
[ -n "$1" ] || { echo "need target dir argument! (eg. $0 /usr/src)"; exit 1; }
[ -e "$TARGET_DIR/mkkernel.sh" ] && { echo "$TARGET_DIR/mkkernel.sh already exist; refusing to blindly overwrite. Remove it and try again"; exit 1; }
[ -e "$TARGET_DIR/initramfs" ] && { echo "$TARGET_DIR/initramfs already exist; refusing to blindly overwrite. Remove it and try again"; exit 1; }

set -e -x
mkdir -p "$TARGET_DIR/initramfs"

cp "$SOURCE_DIR/mkkernel.sh" "$TARGET_DIR/"
chmod 754 "$TARGET_DIR/mkkernel.sh"

cp "$SOURCE_DIR/initramfs/mkinitramfs.sh" "$TARGET_DIR/initramfs"
chmod 754 "$TARGET_DIR/initramfs/mkinitramfs.sh"

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

echo "All done!"
echo "Please adjust config variables in $TARGET_DIR/mkkernel.sh and $TARGET_DIR/initramfs/mkinitramfs.sh"
