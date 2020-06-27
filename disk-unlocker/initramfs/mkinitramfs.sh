#!/bin/bash
# vim: set ft=sh:

[ -z "$INITRAMFS_DIR" ] && INITRAMFS_DIR="$(dirname "$0")"
[ -z "$INITRAMFS_CHROOT" ] && INITRAMFS_CHROOT="/mnt/chroot_initramfs"

DIRS="rootfs"
UTILS="/bin/busybox /usr/sbin/kexec /usr/sbin/efibootmgr /usr/sbin/sed-opal-unlocker \
	/usr/bin/setleds /usr/bin/inotifywait /bin/plymouth /sbin/plymouthd"
LIBS="libgcc_s.so.1"
PLYTHEME=(/usr/share/plymouth/themes/thinkpad/ \
	/usr/share/plymouth/themes/text/ /usr/share/plymouth/themes/details/ \
	/usr/lib64/plymouth/two-step.so /usr/lib64/plymouth/text.so \
	/usr/lib64/plymouth/details.so /usr/lib64/plymouth/label.so \
	/usr/lib64/plymouth/renderers/frame-buffer.so \
	/usr/share/plymouth/plymouthd.defaults /usr/share/fonts/liberation-fonts/LiberationSans-Regular.ttf)


#########################################################################
TARGET="$INITRAMFS_DIR/image.cpio"
CHROOT="${INITRAMFS_CHROOT%%/}"
"$CHROOT"/chroot.sh mount || exit 1
TMP_DIR="$(mktemp --tmpdir="$CHROOT/tmp" -d mkinitramfs.XXXXXX)"
LC_ALL=C

echo "Assembling initramfs in $TMP_DIR"
[ -z "${TMP_DIR}" ] && { echo "Unable to create tmpdir"; exit 1; }
[ -d "${TMP_DIR}" ] || { echo "Tmpdir does not exist"; exit 1; }
chmod 0755 "${TMP_DIR}" || { echo "Unable to chmod initramfs root"; exit 1; }

copy_with_libs() {
	local src="$1"
	[[ $src == $CHROOT/* ]] && src="${src##${CHROOT}}"
	[[ $src == /* ]] || src="/$src"
	local out="$2"
	local dst="$out$src"
	local chsrc="$CHROOT$src"
	local x=""

	[ -x "$dst" ] && return
	mkdir -p "$(dirname "$dst")"

	# symlink; copy link and its target
	if [ -L "$chsrc" ]; then
		cp -dp "$chsrc" "$dst"
		local ltarget="$(readlink "$chsrc")"
		[ "${ltarget:0:1}" == "/" ] || ltarget="$(dirname "$chsrc")/$ltarget"
		copy_with_libs "$ltarget" "$out"
	elif [ -f "$chsrc" ]; then
		cp -a "$chsrc" "$dst"
		if file "$chsrc" | egrep -q 'ELF.*(executable|shared object).*dynamically linked'; then
			[[ $(basename "$src") = lib*.so* ]] && echo "$(dirname "$src")" >> "$out/etc/ld.so.conf.tmp"
			local lib=""
			chroot $CHROOT ldd "$src" | sed -nre 's#^.*?( =>)?[ \t](/[^ ]+) \(.*$#\2#p' | while read lib; do
				copy_with_libs "$lib" "$out"
			done
		fi
	elif [ -d "$chsrc" ]; then
		for x in "$chsrc"/*; do
			[ -e "$x" ] && copy_with_libs "$x" "$out"
		done
	else
		echo "Not a file / symlink: $src"
		exit 1
	fi
}

for d in $DIRS; do
	echo "Copying $d into $TMP_DIR ..."
	pushd "${INITRAMFS_DIR}/${d}" >/dev/null
	cp -a * "$TMP_DIR/" || exit 1
	popd >/dev/null
done

for u in $UTILS; do
	echo "Copying $u into $TMP_DIR ..."
	copy_with_libs "$u" "$TMP_DIR" || exit 1
done

for l in $LIBS; do
	src="$(chroot "$CHROOT" ldconfig -p | grep "$l" -m 1 | sed -re 's@^.*=>[^/]*(/.+)$@\1@')"
	[ -z "$src" ] && continue
	copy_with_libs "$src" "$TMP_DIR" || exit 1
done

if [ -n "$PLYTHEME" ]; then
	PLYNAME="$(basename "${PLYTHEME[0]}")"
	mkdir -p "$TMP_DIR/etc/plymouth" "$TMP_DIR/var/lib/plymouth" "$TMP_DIR/var/spool/plymouth"
	for u in "${PLYTHEME[@]}"; do
		copy_with_libs "$u" "$TMP_DIR"
	done
	echo -en "[Daemon]\nTheme=$PLYNAME\n" > "$TMP_DIR/etc/plymouth/plymouthd.conf"
fi

# generate ld.so.cache
sort "$TMP_DIR/etc/ld.so.conf.tmp" | uniq > "$TMP_DIR/etc/ld.so.conf"
rm "$TMP_DIR/etc/ld.so.conf.tmp"
chroot "$CHROOT" ldconfig -r "${TMP_DIR##${CHROOT}}"

# pack it
pushd "$TMP_DIR" >/dev/null
find . -print0 | cpio --null -ov --format=newc > "$TARGET" && echo "$TARGET updated" || echo "ERROR compressing $TARGET!!"
ls -l "$TARGET"
popd >/dev/null

