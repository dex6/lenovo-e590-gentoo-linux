This directory contains scripts and tools I'm using to utilize hardware disk
encryption (TCG OPAL SED). For configuring SED, standard
[sedutil-cli](https://github.com/Drive-Trust-Alliance/sedutil) utility is used.
However, for unlocking the drive, I'm using my own Pre-Boot Authentication
(PBA) image, not sedutil's one for reasons explained below.

### Hardware

I've got an "enterprisey" Intel NVMe SSD 7600p. It supports OPAL, unlike its
760p brother ("consumer" version). Among other drives which supports OPAL
encryption, I would recommend Samsung EVO/PRO 970 series, however they run too
hot for a laptop in my opinion. Unfortunately, most consumer grade products
don't support OPAL. If you don't have such drive, these notes wouldn't be very
useful to you.

And BTW how to tell whether drive supports OPAL before buying: use google image
search and find a real-life photos of drive you're interested in. Photos taken
on wooden-table(tm) are especially good ;-) Look at the label, if you see
"PSID: [32 random characters]" printed somewhere, then the disk most likely
supports OPAL; if there's nothing like that, it probably doesn't. The PSID code
allows recovering the disk (but not data stored on it) when the password has
been lost.

### Why not LUKS?

I value LUKS very much and use it elsewhere, it's far superior than OPAL when
it comes to issues like trust, transparency and technical credibility. (As a
side note: I'm pretty sure that OPAL firmwares may have some backdoors for
3-letter agencies and/or ordinary security bugs; mostly because they cannot be
audited in any way, it's trivial to hide something like that there...)

However, for this particular laptop I only want a simple mechanism to block the
drive while maintaining maximum performance without eating CPU (=draining
battery) like software encryption does. However, if you wish, nothing stops you
from running LUKS container on _top_ of an OPAL encrypted drive ;)

### Custom PBA Image

I've developed my own software to unlock the drive. It's stored in the disk
Shadow MBR area, which is presented to the BIOS when the disk is locked. Why
not use standard sedutil PBA image? It's simple... my own have more features
and is prettier! :)

- two ways to unlock the disk: a password or a file on external USB drive
- executes target kernel with kexec or eventually MS Windows with a reboot
- UEFI-only, with possibility to support Secure Boot using custom PK (TBD)
- uses [plymouth](https://www.freedesktop.org/wiki/Software/Plymouth/) for
  graphical password entry; when used on recent Intel hardware offers
  flicker-free transition to unlocked Linux OS

### Password Flow

During initial setup, the disk is locked with disk password [1]. This may be
long, incomprehensible ASCII password, you won't need to remember it.
sedutil-cli gets it on cmdline, hashes it using PKBDF2 algorithm and such hash
value [2] is the password that is really configured in the disk's firmware.

My other tool from
[sed-opal-unlocker](https://github.com/dex6/sed-opal-unlocker) repository,
sedutil-passhasher.py, can replicate this hashing process and write the hash
value [2] to a file. Such file may stored on a small USB thumb-drive. When it
is inserted into the locked PC, PBA will unlock disk without any questions.
Hide but don't loose the thumb drive; you may use it as primary unlock tool or
as a backup way to recover the disk in case password has been forgotten.

For day-to-day use, there's another password, which I'll call unlock passphrase
[3]. It may be something easier to remember, and can be changed independently
of the disk password [1]. During setup, the unlock passphrase [3] is hashed
using Argon2id algorithm, producing a key for encrypting (XOR one-time-pad) the
hashed disk password file [2] into encrypted hash file [4]. This encrypted hash
file is stored within the PBA image. Later, when user enters unlock passphrase
in the PBA's prompt, it gets hashed again reproducing the key which is xor-ed
with bundled encrypted hash [4] back into real hash [2] used to unlock the
drive. Had the passphrase [3] been entered wrong, the decrypted hash will be
also wrong and the disk will refuse to unlock itself.

Note #1: the unlock password is hashed using machine's serial number as a salt.
Hence the unlock-with-password may be used only on the machine disk has been
configured on. This behavior can be easily disabled when generating encrypted
hash file [4], though.

Note #2: I was initially considering AES-256-CTR to encrypt the [2] into [4],
however given the key and data sizes were equal and small (32B = 2 AES blocks),
the AES would just became a fancy "hash", transforming one 32 byte key and a
random nonce into another 32 byte "key", xored with plaintext to produce
ciphertext. Since this seemed clearly over engineered, I've decided to directly
xor both hashes, since both are equally secret, it should be equally safe.

Note #3: while this scheme is effectively a two way unlock, it's NOT a two
factor authentication. You need either USB key or the password, not both of
them to unlock the drive. However, if you wish to have 2FA instead, don't store
the PBA image in disk's MBR Shadow area, but rather write it to the USB thumb
drive instead of the hashed password file [2], and use the thumb drive to boot
the PC. This way you would need both USB key and the password... however I've
never tested such configuration.



### Configuring The Drive

Replace password1234 with out real password and /dev/nvme0n1 with proper path.

```
# you don't wish to have password stored in .bash_history, do you?
export HISTFILE=/dev/null

sedutil-cli --initialSetup password1234 /dev/nvme0n1
    One or more header fields have 0 length
    Properties exchange failed
    takeOwnership complete
    Locking SP Activate Complete
    LockingRange0 disabled
    LockingRange0 set to RW
    MBRDone set on
    MBRDone set on
    MBREnable set on
    Initial setup of TPer complete on /dev/nvme0n1

sedutil-cli --setMBREnable on password1234 /dev/nvme0n1
    MBRDone set on
    MBREnable set on

sedutil-cli --enableLockingRange 0 password1234 /dev/nvme0n1
    One or more header fields have 0 length
    Properties exchange failed
    LockingRange0 enabled ReadLocking,WriteLocking

```


### Setting Up Unlocker Image

```
sedutil-passhasher /dev/nvme0n1 /mnt/usb/disk_key.hash
    Checking /dev/nvme0n1...
    Found <disk> with firmware <version> and serial b'<serial number>     '
    Password hash will be written into disk_key.hash
    Enter SED password for /dev/nvme0n1 (CTRL+C to quit): <enter: password1234>
    Hashed password saved! Protect that file properly (chown/chmod at least).

chmod 400 /mnt/usb/disk_key.hash

sedutil-passhasher /dev/nvme0n1 /usr/src/disk-unlocker/initramfs/rootfs/etc/disk_key.enc 1
    Checking /dev/nvme0n1...
    Found <disk> with firmware <version> and serial b'<serial number>     '
    Encrypted password hash will be written into disk_key.enc
    Argon2id CPU cost = 10 iterations
    Argon2id MEM cost = 433.125 MB
    Argon2id threads  = 4
    Enter SED password for /dev/nvme0n1 (CTRL+C to quit): <enter: password1234>
    Enter passphrase for unlocking encrypted passwordhash file: <enter unlock passphrase>
    Enter passphrase again for verification: <enter unlock passphrase again>
    Use DMI data to generate passphrase salt?
    If you say Y, the passphrase will work only on this system. [y/n]: y
    Hashed password saved! Protect that file properly (chown/chmod at least).

chmod 400 /usr/src/disk-unlocker/initramfs/rootfs/etc/disk_key.enc


# Verify and ensure this works!
sedutil-cli --setLockingRange 0 LK password1234 /dev/nvme0n1
    LockingRange0 set to LK

sedutil-cli --listLockingRanges password1234 /dev/nvme0n1
    Locking Range Configuration for /dev/nvme0n1
    LR0 Begin 0 for 0
                RLKEna = Y  WLKEna = Y  RLocked = Y  WLocked = Y
    ...
    # 4x "Y" = Rd/Wr locking enabled and both locked

sed-opal-unlocker unlock /dev/nvme0n1 disk_key.enc
    Please enter key unlock passphrase: <enter unlock passphrase>

sedutil-cli --listLockingRanges password1234 /dev/nvme0n1
    Locking Range Configuration for /dev/nvme0n1
    LR0 Begin 0 for 0
                RLKEna = Y  WLKEna = Y  RLocked = N  WLocked = N
    ...
    # 2x "Y" + 2x "N" = Rd/Wr locking enabled and both UNlocked

# meaning, it works! Once again for the second key

sedutil-cli --setLockingRange 0 LK password1234 /dev/nvme0n1
    LockingRange0 set to LK

sed-opal-unlocker unlock /dev/nvme0n1 disk_key.hash

sedutil-cli --listLockingRanges password1234 /dev/nvme0n1
    (you know what to expect...)

```

TODO: configuration of disk unlocker (/etc/unlocker.conf)
