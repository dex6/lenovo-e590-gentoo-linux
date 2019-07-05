BIOS Update
How to upgrade BIOS on ThinkPad E590 without Windows and with custom logo?

Despite no README accompanying the BIOS files says anything about a custom
logo, it's still possible to use your own. It works like in other Lenovo
Thinkpads, you just need to add one file before updating the BIOS. However, it
seems very picky about files it would render correctly. In particular, I've
found JPG files to not work at all, BMPs were either garbled or over the size
limit, and only GIFs worked. Well, not always, sometimes they were garbled as
well. I'm not sure what requirements are to guarantee proper rendering. I'm
using 768x256, 8-bit RGB, ~12kB file. Particularly I've found indexed mode
files like [1] suggests to not work in 99% of cases...


If you wish to experiment a bit, and write the same BIOS several times with
different logos, you must allow that in the BIOS itself, otherwise it will
refuse to write the same or older version. First, go to BIOS settings (F1
during startup), navigate to Security tab, then UEFI BIOS Update Option, and
set Secure RollBack Prevention to Disabled.


Update procedure:

1. Download BIOS ISO file from:
https://support.lenovo.com/pl/en/downloads/DS506071

eg:
wget https://download.lenovo.com/pccbbs/mobiles/r0yuj07wd.iso


2. Convert the ISO to normal disk image:

geteltorito -o bios.img r0yuj07wd.iso


3. Write to an empty flash drive:

dd if=bios.img of=/dev/sdX bs=1M status=progress


4. Mount the drive and copy logo:

mount /dev/sdX1 /mnt/usb
cp LOGO.GIF /mnt/usb/FLASH/LOGO.GIF
sync; umount /mnt/usb


5. Boot from the USB drive, select "2" to update the BIOS, confirm several
dialogs (it should even show one about the custom logo), and the update will
start. After a short while, it'll ask to reboot. Confirm again and watch the
BIOS being written into flash memory. Then, you'll see "shutdown or reboot in
5s", and the machine will seem to go down. After a while (about a minute) I've
pressed power button, although it did not seem to do anything (probably that's
not necessary). The machine had come up about a minute-two later, upgraded EC
firmware, and rebooted one last time.

6. That's all!


Misc notes:
- When the image has been applied already, you don't need to copy it again
  during subsequent updates. The flashing app detects that there's custom logo
  and offers an option to preserve it.

- BIOS 1.15 image seems to refuse the logo; first detects the logo presence
  and asks to use it, but then shows red dialog "The custom start up image
  file is not found for this system" (!?). After some poking around, I've
  discovered a workaround: mount the flash drive, move all files from it to
  another directory (leaving empty partition) and then move them back. There's
  very little space on the ISO-extracted image, probably its unfortunate
  fragmentation causes some problem later when the logo is applied.

  If move-out-move-back does not help, you may try to create a larger FAT
  partition, copy these files and try to boot from that.

  If that also does not work, you might try to update to 1.14 with custom logo
  first (which worked for me; links in procedure above), and then update to
  1.15 using the option to preserve current logo mentioned earlier.


Useful resources:
[1] https://www.youtube.com/watch?v=HfaJVyM1y-c
[2] http://akpoff.com/archive/2019/setting_the_boot_logo_on_a_thinkpad.html
[3] https://forums.lenovo.com/t5/Lenovo-IdeaPad-1xx-3xx-5xx-7xx/Change-bios-logo-Lenovo-700-15ISK-700-17ISK/td-p/3775878
