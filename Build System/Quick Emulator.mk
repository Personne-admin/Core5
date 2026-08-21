QEMU		?= qemu-system-i386
QEMU_IMG	?= qemu-img
GDB			?= gdb
SOCAT		?= socat
SETSID		?= setsid

EMULATOR_HDD_IMAGE		?= $(IMAGE_DIR)$(PATH_SEPARATOR)Core5 HDD.img
EMULATOR_HDD_SIZE		?= 67092480
eEMULATOR_HDD_IMAGE		:= $(call escape_path,$(EMULATOR_HDD_IMAGE))

EMULATOR_WORK_ROOT		:= $(WORK_ROOT)$(PATH_SEPARATOR)Emulators
QEMU_MONITOR_SOCKET		:= $(EMULATOR_WORK_ROOT)$(PATH_SEPARATOR)QEMU Monitor.sock
QEMU_GDB_COMMANDS		:= $(BUILDSYSTEM_ROOT)$(PATH_SEPARATOR)Configuration Scripts$(PATH_SEPARATOR)QEMU GDB.gdb

QEMU_MACHINE	?= pc
QEMU_CPU		?= pentium
QEMU_MEMORY		?= 8M
QEMU_GDB_PORT	?= 1234

QEMU_SYSTEM_OPTIONS = \
	-machine $(QEMU_MACHINE),accel=tcg \
	-cpu $(QEMU_CPU) \
	-m $(QEMU_MEMORY) \
	-smp 1 \
	-boot order=a \
	-drive file="$(EMULATOR_HDD_IMAGE)",format=raw,if=ide,index=0 \
	-drive file="$(FLOPPY_IMG)",format=raw,if=floppy,index=0 \
	-nic none \
	-no-reboot

QEMU_MONITOR_OPTIONS = \
	-monitor unix:"$(QEMU_MONITOR_SOCKET)",server=on,wait=off

$(eEMULATOR_HDD_IMAGE):
	@$(CMD_MKDIR_P) "$(IMAGE_DIR)"
	@$(QEMU_IMG) create -q -f raw "$@" $(EMULATOR_HDD_SIZE)

.PHONY: emulator-hdd quick-emulator quick-emulator-debug qemu qemu-debug qemu-monitor

emulator-hdd: $(eEMULATOR_HDD_IMAGE)

quick-emulator qemu: $(eFLOPPY_IMG) $(eEMULATOR_HDD_IMAGE)
	@$(CMD_MKDIR_P) "$(EMULATOR_WORK_ROOT)"
	@rm -f "$(QEMU_MONITOR_SOCKET)"
	@$(QEMU) $(QEMU_SYSTEM_OPTIONS) $(QEMU_MONITOR_OPTIONS)

quick-emulator-debug qemu-debug: $(eFLOPPY_IMG) $(eEMULATOR_HDD_IMAGE) $(eBOOTLOADER_STAGE1_SYMBOLS)
	@$(CMD_MKDIR_P) "$(EMULATOR_WORK_ROOT)"
	@rm -f "$(QEMU_MONITOR_SOCKET)"
	@$(SETSID) $(QEMU) $(QEMU_SYSTEM_OPTIONS) $(QEMU_MONITOR_OPTIONS) -S -gdb tcp::$(QEMU_GDB_PORT) & \
		qemu_pid=$$!; \
		trap 'kill "$$qemu_pid" 2>/dev/null; wait "$$qemu_pid" 2>/dev/null; true' EXIT TERM HUP; \
		$(GDB) -x "$(QEMU_GDB_COMMANDS)" \
			-ex "add-symbol-file \"$(BOOTLOADER_STAGE1_SYMBOLS)\" 0x7C00" \
			-ex "target remote localhost:$(QEMU_GDB_PORT)"

qemu-monitor:
	@$(SOCAT) -,rawer "UNIX-CONNECT:$(QEMU_MONITOR_SOCKET)"

export EMULATOR_HDD_IMAGE EMULATOR_HDD_SIZE
