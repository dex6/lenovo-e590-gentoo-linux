Your lecture number one:
https://wiki.gentoo.org/wiki/Sakaki%27s_EFI_Install_Guide/Configuring_Secure_Boot

Number two:
http://www.rodsbooks.com/efi-bootloaders/controlling-sb.html


1. emerge -av efitools sbsigntools

# NOTE: efitools 1.9.2 required! Pre-1.9.0 will fail with Lenovo's BIOS. Note
# that keylists (.esl and .auth files) must be generated with efitools-1.9.2;
# it's not sufficient to have new version just to install them.
# See: https://git.kernel.org/pub/scm/linux/kernel/git/jejb/efitools.git/commit/?id=e57bafc268511ad54598627b663a7ae86bd856f5


2. Create a directory in some safe place where all key material will be
stored. Sakaki suggests /etc/efikeys, I'm storing it on an external flash
drive, you may choose this, that or something else if you wish. Note that it
should be chmod 700 and chown root:root, and that you'll need it for any
kernel or disk unlocker update.

mkdir /mnt/usb/efikeys
chmod 700 /mnt/usb/efikeys
chown 0:0 /mnt/usb/efikeys
cd /mnt/usb/efikeys


3. Backup original (HW/SW vendor, i.e. Lenovo/Microsoft) keys:

efi-readvar -v PK  -o orig_PK.esl
efi-readvar -v KEK -o orig_KEK.esl
efi-readvar -v db  -o orig_db.esl
efi-readvar -v dbx -o orig_dbx.esl


4. Create keys

bash /path/to/dir/containing/this/readme/mkkeys.sh


5. Goto BIOS, clear Secure Boot keys (switch platform to Setup Mode).

(Secure Boot should be disabled already at this point... We're now installing
custom keys to enable it at the end of this tutorial.)

ThinkPad E590 BIOS has three operations in its Security -> Secure Boot section:
- Reset To Setup Mode - removes only PK, leaving KEK/db/dbx intact
- Restore Factory Keys - when you mess up and wish to restore Lenovo/MS keys
- Clear All Secure Boot Keys - removes all variables (PK/KEK/db/dbx)

Choose the last one. First is also usable, but requires different procedure to
install new keys.


6. Install custom keys

efi-updatevar -f orig_dbx.auth dbx
efi-updatevar -f db.compound.auth db
efi-updatevar -f KEK.auth KEK
efi-updatevar -f PK.auth PK

The last command will switch platform to User mode, and make the whole trust
chain complete.

If you don't want to dual-boot with Windows, you may use db.auth instead of
db.compound.auth to skip reinstalling Lenovo/Microsoft keys back. Note that
BIOS update with ISO image while Secure Boot is enabled will cease to work in
such case, cause it's signed with Lenovo's key.

If you used "Reset To Setup Mode" to clear only the PK, you need to:

chattr -i  /sys/firmware/efi/efivars/{PK,KEK,db,dbx}-*

and then above 4 commands in *reversed* order (PK first, then KEK, etc.),
however it might fail without obvious reasons why...


7. Configure signing keys in mkunlocker.sh and mkkernel.sh scripts
(set EFI_SIGN_KEYS and optionally EFI_SIGN_DEV variables in these scripts to
point to the db key)


8. Build and install signed kernel and disk unlocker images.


9. Reboot to confirm they boot correctly.


10. Reboot once again, enter the BIOS and enable Secure Boot. If your signed
kernel and disk unlocker still boots, congratulations! Your machine now uses
your own keys to verify what is allowed to boot.


11. Remember to secure BIOS access with password. Secure Boot is useless when
Evil Maid can disable it easily.


Misc stuff:

a) When updating keys in User mode (PK already installed), using auth files not
always works; sometimes it fails. If replace is rejected, try using esl+key files:
    efi-updatevar -f db.compound.esl -k KEK.key -e db
or remove all keylists using series of
    efi-updatevar -d <idx> -k <PK/KEK>.key <var>
and then re-add.


b) Errors returned by efi-updatevar:

"Failed to update PK: Operation not permitted" = immutable flag set; clear it:
    chattr -i  /sys/firmware/efi/efivars/{PK,KEK,db,dbx}-*
and retry.

"Cannot write to PK, wrong filesystem permissions" = UEFI rejected update
(wrong format? not in setup mode? auth required? duplicates?), hard to tell why.
When it happens, it also breaks efivarfs and now you also cannot read variables:

    efi-readvar
        Variable PK, length -4

Solution -> reboot or just remount efivarfs
    umount /sys/firmware/efi/efivars
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars

