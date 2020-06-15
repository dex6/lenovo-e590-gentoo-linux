#!/bin/bash
# vim: set ft=sh:
# This script goes to /usr/src/mkkernel.sh.


KERNEL_CMD="ro root=/dev/mapper/sirius--nvme-root print-fatal-signals=1"
INITRAMFS_CHROOT="/mnt/chroot_initramfs"

# Specify cert/key file name without extension for signing kernel image for
# UEFI Secure Boot. .crt with PEM certificate and .key with PEM private key
# are needed. Comment out to disable.
EFI_SIGN_KEYS="/efikeys/db"
# When sign key/crt are stored on an external USB device, it may be mounted
# automatically. In such case above paths are relative to EFI_SIGN_DEV root.
EFI_SIGN_DEV="LABEL=keydev"

# Same settings but for module signing. You may use the same key, although
# different format (but mkkeys.sh creates it) - .prv with PEM private key
# + cert (combined) is needed.
MOD_SIGN_KEYS="/efikeys/db"
MOD_SIGN_DEV="LABEL=keydev"


usage() {
	echo -e "Kernel Building Script."
	echo -e
	echo -e "Usage:"
	echo -e "\t$(basename $0) <action> [args]"
	echo -e
	echo -e "Where <action> may be one of:"
	echo -e "\tupdate-kernel <kernel-sources-dir> [config-path]"
	echo -e "\t\tSwitches /usr/src/linux symlink to specified dir and prepares kernel config"
	echo -e "\t\t(using make oldconfig on [config-path] or /proc/config.gz)"
	echo -e "\tbuild"
	echo -e "\t\tCompiles kernel and embedded initramfs image."
	echo -e "\tinstall"
	echo -e "\t\tInstalls kernel for being executed by the PBA image and modules."
}


prepare_kernel_sources() {
	local src="$1"
	local cfg="$2"
	[ -z "$src" ] && { echo "Need argument: please specify kernel sources dir like /usr/src/linux-5.1.5-gentoo/"; return 1; }
	[ -L "$src" ] && { echo "Must specify directory, not a symlink"; return 1; }
	[ -d "$src" ] || { echo "Error: $src not found"; return 1; }
	local version="$(make -s -C "$src" kernelversion)"

	echo "Cleaning old sources..."
	make -s -C "$KERNEL_DIR" clean

	echo "Linking kernel $version sources..."
	rm "$KERNEL_DIR"
	ln -s "$src" "$KERNEL_DIR"

	echo "Preparing configuration  [make oldconfig]"
	( if [ -n "$cfg" ]; then cat "$cfg"; else zcat /proc/config.gz; fi ) > "$KERNEL_DIR/.config" || return 1
	make -s -C "$KERNEL_DIR" oldconfig

	echo
	echo "Kernel prepared! You may adjust kernel configuration with"
	echo "    make -C $KERNEL_DIR menuconfig"
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
	[ -z "$EFI_SIGN_KEYS" ] || [ -z "$MOD_SIGN_KEYS" ] && return 0

	echo
	echo "Setting up signing keys..."

	if [ -n "$EFI_SIGN_KEYS" ]; then
		mount_keydir_dev "$EFI_SIGN_DEV"

		[ -f "${keydir}${EFI_SIGN_KEYS}.crt" ] || { echo "No signing cert! (${EFI_SIGN_KEYS}.crt)"; return 1; }
		[ -f "${keydir}${EFI_SIGN_KEYS}.key" ] || { echo "No signing key! (${EFI_SIGN_KEYS}.key)"; return 1; }

		efi_sign_crt="${keydir}${EFI_SIGN_KEYS}.crt"
		efi_sign_key="${keydir}${EFI_SIGN_KEYS}.key"
		echo "Using $efi_sign_key for signing kernel image"
	fi

	if [ -n "$MOD_SIGN_KEYS" ]; then
		mount_keydir_dev "$MOD_SIGN_DEV"

		# symlink .pem to avoid copying and storing secrets in kernel source tree
		# and don't symlink the .x509 - kernel will regenerate it and would fail when the FS with keys is read-only
		[ -f "${keydir}${MOD_SIGN_KEYS}.prv" ] || { echo "No signing key (${MOD_SIGN_KEYS}.prv)!"; return 1; }

		[ -L "$KERNEL_DIR/certs/signing_key.pem" ] && rm "$KERNEL_DIR/certs/signing_key.pem"
		[ -f "$KERNEL_DIR/certs/signing_key.pem" ] && mv -v "$KERNEL_DIR/certs/signing_key.pem" "$KERNEL_DIR/certs/signing_key.pem.old"
		ln -s "${keydir}${MOD_SIGN_KEYS}.prv" "$KERNEL_DIR/certs/signing_key.pem"
		echo "Using ${keydir}${MOD_SIGN_KEYS}.prv for signing kernel modules"
	fi
}


build_kernel_1st_pass() {
	echo
	echo "Building kernel (1st pass; dummy initramfs)"
	# Clear initramfs
	truncate -s 0 "$INITRAMFS_DIR/image.cpio"
	# Ensure paths and arguments in config are okay
	sed -i -e "s@^.*CONFIG_INITRAMFS_SOURCE[ =].*\$@CONFIG_INITRAMFS_SOURCE=\"$INITRAMFS_DIR/image.cpio\"@" "$KERNEL_DIR/.config"
	sed -i -e "s@^.*CONFIG_CMDLINE[ =].*\$@CONFIG_CMDLINE=\"$KERNEL_CMD\"@" "$KERNEL_DIR/.config"
	# Build it!
	time make -j8 -C "$KERNEL_DIR"
}

build_initramfs() {
	echo
	echo "Building initramfs"
	bash "$INITRAMFS_DIR/mkinitramfs.sh"
}

build_kernel_2nd_pass() {
	echo
	echo "Building kernel (2nd pass; real initramfs)"
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

install_modules() {
	local version="$(make -s -C "$KERNEL_DIR" kernelversion)"
	echo "Installing kernel $version.... last chance for CTRL+C"
	sleep 3
	make -C "$KERNEL_DIR" modules_install

	touch "/lib/modules/$version/.marker" || return 1
	emerge -v1 @module-rebuild
	echo
	if [ -n "$MOD_SIGN_KEYS" ]; then
		local hash="$(sed -nre 's/^CONFIG_MODULE_SIG_HASH="(sha[0-9]+)"$/\1/p' "$KERNEL_DIR/.config")"
		[ -n "$hash" ] || { echo "Unable to determine hash used to sign modules!"; return 1; }
		echo "Signing out-of-tree modules using $hash ..."
		find "/lib/modules/$version" -type f -name "*.ko" -newer "/lib/modules/$version/.marker" \
			-printf "-> '%P'...\n" -exec "$KERNEL_DIR/scripts/sign-file" "$hash" \
			"$KERNEL_DIR/certs/signing_key.pem" "$KERNEL_DIR/certs/signing_key.x509" {} \;
		echo
	fi
	rm "/lib/modules/$version/.marker"
}

install_kernel_image() {
	local date="$(date +%Y%m%d-%H%M%S)"
	local version="$(make -s -C "$KERNEL_DIR" kernelversion)"
	local kernel
	[ -z "$EFI_SIGN_KEYS" ] && kernel="bzImage" || kernel="bzImage.signed"

	echo "Installing kernel files ..."
	cp -av "$KERNEL_DIR/arch/x86/boot/$kernel" "/boot/vmlinuz-$version-$date"
	cp -av "$KERNEL_DIR/System.map" "/boot/System.map-$version-$date"
	cp -av "$KERNEL_DIR/.config" "/boot/config-$version-$date"
	echo

	echo "Switching kernel symlinks ..."
	local file
	for file in config System.map vmlinuz; do
		[ -L "/boot/$file" ] && { rm -f "/boot/$file.old"; mv "/boot/$file" "/boot/$file.old"; }
		ln -sfv "$file-$version-$date" "/boot/$file"
	done
}


export KERNEL_DIR="/usr/src/linux"
export INITRAMFS_DIR="/usr/src/initramfs"
export INITRAMFS_CHROOT

case "$1" in
	update-kernel)
		prepare_kernel_sources "$2" "$3"
		exit $?
		;;

	build)
		setup_signing_keys && \
			build_kernel_1st_pass && \
			build_initramfs && \
			build_kernel_2nd_pass
		exit $?
		;;

	install)
		setup_signing_keys && \
			sign_kernel && \
			install_modules && \
			install_kernel_image
		exit $?
		;;

	*)
		echo "Unknown action!"
		usage
		exit 1
		;;
esac
