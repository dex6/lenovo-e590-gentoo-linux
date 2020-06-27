#!/bin/bash
# vim: set ft=sh:

KERNEL_CMD="ro quiet splash"
INITRAMFS_CHROOT="/mnt/chroot_initramfs"

# path where EFI System Partition is mounted. The disk on which this partition
# is located is the target disk where PBA is installed.
EFI_PARTITION="/boot/efi"
# path (on EFI System Partition) where main unlocker image is kept
UNLOCKER_PATH_PRIMARY="EFI/gentoo/unlocker.efi"
# previous (backup) image of unlocker in case new one does not work
UNLOCKER_PATH_BACKUP="EFI/gentoo/unlocker-old.efi"
# extra unlocker placements in the MBR shadow *only* (like Windows unlocker)
UNLOCKER_PATH_SHADOWS=("EFI/Boot/bootx64.efi" "EFI/Microsoft/Boot/bootmgfw.efi")

# Specify cert/key file name without extension for signing kernel image for
# UEFI Secure Boot. .crt with PEM certificate and .key with PEM private key
# are needed. Comment out to disable.
EFI_SIGN_KEYS="/efikeys/db"
# When sign key/crt are stored on an external USB device, it may be mounted
# automatically. In such case above paths are relative to EFI_SIGN_DEV root.
EFI_SIGN_DEV="LABEL=keydev"

# OPAL password file location for sedutil. Needed only for installing new PBA
# in the MBR shadow area. This file should contain plaintext password which
# will be passed to sedutil via cmdline. There should be better way to do it,
# but... sigh.
SEDUTIL_PASSWD_FILE="/disk_key.txt"
SEDUTIL_PASSWD_DEV="LABEL=keydev"


usage() {
	echo -e "TCG Opal SED (Self Encrypting Drive) PBA (Pre-Boot Authentication) Image Maker"
	echo -e "AKA The Disk Unlocker."
	echo -e
	echo -e "Usage:"
	echo -e "\t$(basename $0) <action> [args]"
	echo -e
	echo -e "Where <action> may be one of:"
	echo -e "\tupdate-kernel [kernel-sources-dir]"
	echo -e "\t\tCopies [kernel-sources-dir] (or current /usr/src/linux if not given)"
	echo -e "\t\tto $KERNEL_DIR and prepares kernel config."
	echo -e "\tbuild"
	echo -e "\t\tCompiles kernel, initramfs and assembles disk unlocker binary."
	echo -e "\t\tInstalls it to staging area (EFI System Partition) for testing."
	echo -e "\tinstall"
	echo -e "\t\tAssembles real PBA image from the contents of EFI System Partition"
	echo -e "\t\tand installs it to disk shadow MBR area."
}


copy_kernel_sources() {
	local src="${1:-/usr/src/linux}"
	[ -d "$src" ] || { echo "Error: $src not found"; return 1; }
	local version="$(make -s -C "$src" kernelversion)"

	echo "Copying kernel $version sources..."
	[ -d "$KERNEL_DIR" ] && rm -rf "$KERNEL_DIR"
	mkdir "$KERNEL_DIR"
	cp -ra --reflink=auto "$src/"* "$KERNEL_DIR/" || return 1

	echo "Cleaning sources..."
	make -s -C "$KERNEL_DIR" clean

	echo "Preparing configuration  [make oldconfig]"
	cp "$TOP_DIR/kernel-config" "$KERNEL_DIR/.config"
	make -s -C "$KERNEL_DIR" oldconfig

	echo
	echo "Kernel prepared! You may adjust kernel configuration with"
	echo "    make -C $KERNEL_DIR menuconfig && cp -v \"$KERNEL_DIR/.config\" \"$TOP_DIR/kernel-config\""
	echo
	echo "and then execute to continue:"
	echo "    $0 build"
}

mount_keydir_dev() {
	local dev_spec="$1"

	if [ -n "$dev_spec" ]; then
		local dev="$(findfs "$dev_spec")"
		local mnt="$(findmnt -nro TARGET "$dev")"
		if [ $? -ne 0 ] || [ -z "$mnt" ]; then
			mnt="/mnt/$(lsblk -nro LABEL "$dev")"
			if [ "$mnt" = "/mnt/" ] || [ ! -d "$mnt" ] || mountpoint -q "$mnt"; then
				mnt="/run/media/0/$(echo "$dev" | md5sum - | cut -d" " -f1)"
				mkdir -p "$mnt"
			fi
			echo "Mounting $dev on $mnt"
			mount -o ro "$dev" "$mnt"
		fi
		keydir="$mnt/"
	else
		keydir=""
	fi
}

setup_signing_keys() {
	[ -z "$EFI_SIGN_KEYS" ] && return 0

	echo
	echo "Setting up signing keys..."
	mount_keydir_dev "$EFI_SIGN_DEV"

	# unlocker image does not use kernel modules, but they need to be enabled with sig verification,
	# cause it's needed to enable (indirectly...) kexec bzImage verification.
	# Since it would generate and embed x509 certificate in kernel, we would rather use our own as well.
	[ -f "${keydir}${EFI_SIGN_KEYS}.crt" ] || { echo "No signing cert! (${EFI_SIGN_KEYS}.crt)"; return 1; }
	[ -f "${keydir}${EFI_SIGN_KEYS}.key" ] || { echo "No signing key! (${EFI_SIGN_KEYS}.key)"; return 1; }
	[ -f "${keydir}${EFI_SIGN_KEYS}.prv" ] || { echo "No signing key (${EFI_SIGN_KEYS}.prv)!"; return 1; }

	# symlink .pem to avoid copying and storing secrets in kernel source tree
	# and don't symlink the .x509 - kernel will regenerate it and would fail when the FS with keys is read-only
	[ -L "$KERNEL_DIR/certs/signing_key.pem" ] && rm "$KERNEL_DIR/certs/signing_key.pem"
	[ -f "$KERNEL_DIR/certs/signing_key.pem" ] && mv -v "$KERNEL_DIR/certs/signing_key.pem" "$KERNEL_DIR/certs/signing_key.pem.old"
	ln -s "${keydir}${EFI_SIGN_KEYS}.prv" "$KERNEL_DIR/certs/signing_key.pem"

	efi_sign_crt="${keydir}${EFI_SIGN_KEYS}.crt"
	efi_sign_key="${keydir}${EFI_SIGN_KEYS}.key"
	echo "Using $efi_sign_key"
}


build_initramfs() {
	echo
	echo "Building real initramfs"
	bash "$INITRAMFS_DIR/mkinitramfs.sh"
}

build_kernel() {
	echo
	echo "Building kernel"
	# Ensure paths in config are okay
	sed -i -e "s@^.*CONFIG_INITRAMFS_SOURCE[ =].*\$@CONFIG_INITRAMFS_SOURCE=\"$INITRAMFS_DIR/image.cpio\"@" "$KERNEL_DIR/.config"
	sed -i -e "s@^.*CONFIG_CMDLINE[ =].*\$@CONFIG_CMDLINE=\"$KERNEL_CMD\"@" "$KERNEL_DIR/.config"
	# Build it!
	time make -j8 -C "$KERNEL_DIR"
}

sign_kernel() {
	[ -z "$EFI_SIGN_KEYS" ] && return 0

	echo
	echo "Signing kernel EFI executable"
	sbsign --key "$efi_sign_key" --cert "$efi_sign_crt" \
		--output "$KERNEL_DIR/arch/x86/boot/bzImage.signed" \
		"$KERNEL_DIR/arch/x86/boot/bzImage"
}

stage_for_testing() {
	local kernel
	[ -z "$EFI_SIGN_KEYS" ] && kernel="bzImage" || kernel="bzImage.signed"

	local target="$EFI_PARTITION/$UNLOCKER_PATH_PRIMARY"
	[ -f "$target" ] || { mkdir -p "$(dirname "$target")"; cp -av "$KERNEL_DIR/arch/x86/boot/$kernel" "$target"; }  # for 1st install, so .bck is created as well
	[ -f "$target.bck" ] || cp -av "$target" "$target.bck" || return 1
	cp -av "$KERNEL_DIR/arch/x86/boot/$kernel" "$target" || return 1
	ls -l "$target"*
	[ -f "$EFI_PARTITION/$UNLOCKER_PATH_BACKUP" ] && ls -l "$EFI_PARTITION/$UNLOCKER_PATH_BACKUP"

	echo
	echo -e "New unlocker image installed on EFI System Partition."
	echo -e "Please reboot (*no* power cycle) and test whether it works."
	echo -e "If does, do \"mkunlocker.sh install\" after the reboot."
	echo -e "If doesn't, power cycle and unlock with previous unlocker on MBR Shadow area"
	echo -e "  and investigate problems or revert with:"
	echo
	echo -e "\tmv -v $target.bck $target"
}


create_mbr_shadow_image() {
	local unlocker="$EFI_PARTITION/$UNLOCKER_PATH_PRIMARY"
	[ -f "$unlocker.bck" ] || { echo "No new image found! Please build first."; return 1; }

	# prepare sparse image file
	rm -f /tmp/unlocker_img.*
	image_file="$(mktemp /tmp/unlocker_img.XXXXXXXX)"
	echo
	echo "Preparing MBR Shadow image at $image_file"
	dd if=/dev/zero of="$image_file" bs=1 count=0 seek=128M status=none
	[ $? -eq 0 ] || { echo "Failed to create image file"; return 1; }

	# partition it, preserving all original UUIDs so EFI Boot variables
	# refers to MBR Shadow image as well
	local efi_dev="$(findmnt -nro SOURCE "$EFI_PARTITION")"
	efi_disk="/dev/$(lsblk -dnro PKNAME "$efi_dev")"
	local efi_disk_uuid="$(lsblk -dnro PTUUID "$efi_dev")"
	local efi_part_uuid="$(lsblk -dnro PARTUUID "$efi_dev")"
	local efi_fs_uuid="$(lsblk -dnro UUID "$efi_dev" | sed -e 's/-//g')"
	local efi_part_size="$(lsblk -dnro SIZE -b "$efi_dev")"
	sgdisk  -n "1:1M:+$((efi_part_size / 1024))k" \
		-t 1:EF00 \
		-u "1:$efi_part_uuid" \
		-U "$efi_disk_uuid" \
		"$image_file"
	[ $? -eq 0 ] || { echo "Failed to create partition on image file :("; return 1; }
	echo
	sgdisk -p "$image_file"
	sgdisk -i 1 "$image_file"

	# setup loop device and format partition
	local image_dev="$(losetup -P --show -f "$image_file")"
	[ -b "$image_dev" ] || { echo "Failed to create loop device"; return 1; }
	trap 'losetup -d "'"$image_dev"'" 2>/dev/null' SIGINT SIGQUIT SIGTERM EXIT
	mkfs.vfat -F 32 -i "$efi_fs_uuid" -n SYSTEM "${image_dev}p1"
	[ $? -eq 0 ] || { echo "Failed to create FAT filesystem :("; return 1; }

	# mount image
	mkdir -p /run/media/0/
	local image_dir="$(mktemp -d /run/media/0/unlocker_img.XXXXXXXXX)"
	[ -n "$image_dir" ] || { echo "Failed to create MBR Shadow image mountpoint"; return 1; }
	mount "${image_dev}p1" "$image_dir"
	[ $? -eq 0 ] || { echo "Failed to mount MBR Shadow image"; return 1; }
	trap 'umount "'"$image_dir"'"; rmdir "'"$image_dir"'"; losetup -d "'"$image_dev"'" 2>/dev/null' SIGINT SIGQUIT SIGTERM EXIT

	# copy unlocker binary to target paths
	mkdir -p "$(dirname "$image_dir/$UNLOCKER_PATH_PRIMARY")" || return 1
	cp -av "$unlocker" "$image_dir/$UNLOCKER_PATH_PRIMARY" || return 1
	mkdir -p "$(dirname "$image_dir/$UNLOCKER_PATH_BACKUP")" || return 1
	cp -av "$unlocker.bck" "$image_dir/$UNLOCKER_PATH_BACKUP" || return 1
	local f
	for f in "${UNLOCKER_PATH_SHADOWS[@]}"; do
		mkdir -p "$(dirname "$image_dir/$f")" || return 1
		cp -av "$unlocker" "$image_dir/$f" || return 1
	done

	# some fancy info and we're done
	sync
	echo
	tree -pugshD "$image_dir"
	df -h "$image_dir"
	echo
	echo "MBR Shadow image ready!"

	# but yea...let's cleanup as well
	umount "$image_dir"
	rmdir "$image_dir"
	losetup -d "$image_dev"
	trap '' SIGINT SIGQUIT SIGTERM EXIT
	# output variables: image_file, efi_disk
	return 0
}

install_mbr_shadow_image() {
	echo
	echo "Installing to ${efi_disk}. This will take a while! Please be patient ..."

	mount_keydir_dev "$SEDUTIL_PASSWD_DEV"
	[ -f "${keydir}${SEDUTIL_PASSWD_FILE}" ] || { echo "No sedutil password file! (${keydir}${SEDUTIL_PASSWD_FILE})"; return 1; }
	local passwd="$(cat "${keydir}${SEDUTIL_PASSWD_FILE}")"

	sedutil-cli --loadPBAimage "$passwd" "$image_file" "$efi_disk"
	passwd=""
	return 0
}

finalize_install() {
	echo
	echo "Finalizing install..."

	# this is quite easy
	local unlocker_new="$EFI_PARTITION/$UNLOCKER_PATH_PRIMARY"
	local unlocker_bck="$EFI_PARTITION/$UNLOCKER_PATH_PRIMARY.bck"
	local unlocker_old="$EFI_PARTITION/$UNLOCKER_PATH_BACKUP"
	mv -v "$unlocker_bck" "$unlocker_old" || return 1

	echo
	ls -l "$unlocker_new" "$unlocker_old"
}


TOP_DIR="$(dirname "$(realpath "$0")")"
export KERNEL_DIR="$TOP_DIR/kernel"
export INITRAMFS_DIR="$TOP_DIR/initramfs"
export INITRAMFS_CHROOT

case "$1" in
	update-kernel)
		copy_kernel_sources "$2"
		exit $?
		;;

	build)
		# since we don't have any kernel modules, initramfs can be built first,
		# and then we may include it in the kernel without need for 2-pass build.
		setup_signing_keys && \
			build_initramfs && \
			build_kernel && \
			sign_kernel && \
			stage_for_testing
		exit $?
		;;

	install)
		create_mbr_shadow_image && \
			install_mbr_shadow_image && \
			finalize_install
		exit $?
		;;

	*)
		echo "Unknown action!"
		usage
		exit 1
		;;
esac
