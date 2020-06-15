## Kernel Building

Gentoo traditionally installs kernel sources and expects user to configure and compile kernel himself. Well, this changed a few months ago, now similarly to other distros a generic kernel can be automatically installed using regular system update tools. But I stick to the traditional way and use gentoo-sources, which gives me possibility to configure the kernel my way and install only driver my laptop needs.


### Stuff present in this directory

- config-X.Y-gentoo files are kernel configs I'm currently using for gentoo-sources package
- mkkernel.sh is script installed into /usr/src which:
  - `update-kernel` operation - used once after installing new gentoo-sources with emerge:
    - switches /usr/src/linux to new sources
    - prepares .config basing on currently running kernel and `make oldconfig`
    - `make clean` in previous sources, so `emerge -P gentoo-sources` can remove it cleanly
  - `build` operation
    - compiles kernel, modules, and prepares embedded initramfs (I'm using embedded initramfs since it can be signed and verified by EFI Secure Boot and signed kexec easily)
  - `install` operation
    - signs and installs kernel binary to /boot
    - installs modules to /lib/modules
    - reinstalls out-of-tree modules (`emerge @module-rebuild`)
    - switches traditional /boot/vmlinuz etc. symlinks to the new kernel image
- initramfs directory is also intalled to /usr/src/initramfs, contains extremely simple and hand-crafted initramfs system which:
  - saves Opal Disk key in the kernel for S3 sleep support (if used together with disk-unlocker) 
  - activates LVM volumes
  - mounts rootfs stored on one of them
  - switches to the real init (openrc; probably would also work with systemd)
- installme.sh - pseudo-installer (see below)


### Installation

The stuff just resides in /usr/src. Since initramfs contains some device nodes in /dev, and git cannot store them, it's partially tar.gzipped in this repo. For user convenience, installme.sh script unpacks and copies everything to target directory and assists to configure root password inside the initramfs /etc/passwd.
Usage (root required):

```sh
# ./installme.sh /usr/src
```

You may change `/usr/src` to another directory like `/tmp/test` to see what would be written to `/usr/src`. After installation, you may need to customize some config variables at the beginning of installed scripts.


### Typical Usage Flow

After `emerge -avuDN @world` installs new gentoo-sources and you decide to compile the kernel (lets say it's version 5.6.18):

```sh
# cd /usr/src
# ./mkkernel.sh update-kernel linux-5.6.18-gentoo
# ./mkkernel.sh build
# ./mkkernel.sh install
```

