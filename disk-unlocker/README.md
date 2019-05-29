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

For day-to-day use, there's another password, which I'll call unlock password
[3]. It may be something easier to remember, and can be changed independently
of the disk password [1]. During setup, the unlock password [3] is hashed using
Argon2id algorithm, producing a key for encrypting (AES-256) the hashed disk
password file [2] into encrypted hash file [4]. This encrypted hash file is
stored within the PBA image. Later, when user enters unlock password in the
PBA's prompt, it gets hashed again reproducing the AES key which decrypts
bundled hash [4] back into raw hash [2] used to unlock the drive. Had the
password [4] been entered wrong, the decrypted hash will be also wrong and the
disk will refuse to unlock itself.

Note #1: the unlock password is hashed using machine's serial number as a salt.
Hence the unlock-with-password may be used only on the machine disk has been
configured on. This behavior can be easily disabled by editing one script,
though.

Note #2: while this scheme is effectivaly a two way unlock, it's NOT a two
factor authentication. You need either USB key or the password, not both of
them to unlock the drive. However, if you wish to have 2FA instead, don't store
the PBA image in disk's MBR Shadow area, but rather write it to the USB thumb
drive instead of the hashed password file [2], and use the thumb drive to boot
the PC. This way you would need both USB key and the password... however I've
never tested such configuration.


