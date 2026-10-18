  Core5 Operating System

This repository holds the build system alongside
all of the source code of the Core5 Boot Loader,
Kernel, all of the necessary tools needed to build
the project and many development and usage utilities.

    Building

Core5 can be built on GNU/Linux (also known as SystemD/Linux)
or (in the future) on Core5 itself. On GNU/Linux the following
programs are required to be installed on the build machine:

 GNU Make, Bash, mtools, sfdisk, coreutils and git.
Flat assembler g (fasmg) is vendored as a git submodule and must
be fetched before the build commences.

QEMU and/or Bochs must be available in order to run the disk images
in said emulators, with GDB, socat and awk required in order to debug
disk images with QEMU and Bochs built with it's internal debugger required
for debugging images with Bochs.

On non-x86 hosts, a multiarch gdb and cross objcopy supporting elf32-i386
must be used in order to properly debug with QEMU.

Invoking the Make default rule will build the Boot Loader along with
the two supported disk images at `Work/Images/`.
