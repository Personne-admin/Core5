QEMU		?= qemu-system-i386
GDB			?= gdb
SOCAT		?= socat
SETSID		?= setsid

EMULATOR_WORK_ROOT		:= $(WORK_ROOT)$(PATH_SEPARATOR)Emulators
QEMU_MONITOR_SOCKET		:= $(EMULATOR_WORK_ROOT)$(PATH_SEPARATOR)QEMU Monitor.sock
QEMU_GDB_COMMANDS		:= $(BUILDSYSTEM_ROOT)$(PATH_SEPARATOR)Configuration Scripts$(PATH_SEPARATOR)QEMU GDB.gdb
QEMU_GDB_TARGET_XML		:= $(BUILDSYSTEM_ROOT)$(PATH_SEPARATOR)Configuration Scripts$(PATH_SEPARATOR)i8086-target.xml
QEMU_GDB_LISTING_LOOKUP	:= $(BUILDSYSTEM_ROOT)$(PATH_SEPARATOR)Configuration Scripts$(PATH_SEPARATOR)Listing Lookup.sh

QEMU_LOG_FLAGS			?= cpu_reset,guest_errors
QEMU_LOG_FILE			:= $(EMULATOR_WORK_ROOT)$(PATH_SEPARATOR)QEMU.log

QEMU_MACHINE	?= pc
QEMU_CPU		?= pentium
QEMU_MEMORY		?= 8M
QEMU_GDB_PORT	?= 1234

QEMU_SYSTEM_OPTIONS = \
	-machine $(QEMU_MACHINE),accel=tcg \
	-cpu $(QEMU_CPU) \
	-m $(QEMU_MEMORY) \
	-smp 1 \
	-boot order=$(QEMU_BOOT_ORDER) \
	-drive file="$(HDD_IMG)",format=raw,if=ide,index=0 \
	-drive file="$(FLOPPY_IMG)",format=raw,if=floppy,index=0 \
	-nic none \
	-no-reboot \
	-no-shutdown \
	-d $(QEMU_LOG_FLAGS) -D "$(QEMU_LOG_FILE)"

QEMU_MONITOR_OPTIONS = \
	-monitor unix:"$(QEMU_MONITOR_SOCKET)",server=on,wait=off

.PHONY: qemu-floppy qemu-hdd qemu-floppy-debug qemu-hdd-debug qemu-monitor
.PHONY: qemu qemu-debug quick-emulator quick-emulator-debug

qemu-floppy qemu-floppy-debug:	QEMU_BOOT_ORDER := a
qemu-hdd qemu-hdd-debug:		QEMU_BOOT_ORDER := c

qemu-floppy qemu-hdd: $(eFLOPPY_IMG) $(eHDD_IMG)
	@$(CMD_MKDIR_P) "$(EMULATOR_WORK_ROOT)"
	@rm -f "$(QEMU_MONITOR_SOCKET)"
	@$(QEMU) $(QEMU_SYSTEM_OPTIONS) $(QEMU_MONITOR_OPTIONS)

qemu-floppy-debug qemu-hdd-debug: $(eFLOPPY_IMG) $(eHDD_IMG) $(eBOOTLOADER_STAGE1_SYMBOLS) $(eBOOTLOADER_STAGE2_SYMBOLS)
	@$(CMD_MKDIR_P) "$(EMULATOR_WORK_ROOT)"
	@rm -f "$(QEMU_MONITOR_SOCKET)"
	@$(SETSID) $(QEMU) $(QEMU_SYSTEM_OPTIONS) $(QEMU_MONITOR_OPTIONS) -S -gdb tcp::$(QEMU_GDB_PORT) & \
		qemu_pid=$$!; \
		trap 'kill "$$qemu_pid" 2>/dev/null; wait "$$qemu_pid" 2>/dev/null; true' EXIT TERM HUP; \
		$(GDB) -q -iex "set pagination off" \
			-ex "set \$$listings = \"$(BOOTLOADER_OUTPUT_ROOT)\"" \
			-ex "set \$$lstscript = \"$(QEMU_GDB_LISTING_LOOKUP)\"" \
			-x "$(QEMU_GDB_COMMANDS)" \
			-ex "set tdesc filename $(QEMU_GDB_TARGET_XML)" \
			-ex "add-symbol-file \"$(BOOTLOADER_STAGE1_SYMBOLS)\" 0x7C00" \
			-ex "add-symbol-file \"$(BOOTLOADER_STAGE2_SYMBOLS)\" $(BOOTLOADER_STAGE2_LOAD_ADDRESS)" \
			-ex "target remote localhost:$(QEMU_GDB_PORT)"

qemu quick-emulator: qemu-floppy
qemu-debug quick-emulator-debug: qemu-floppy-debug

qemu-monitor:
	@$(SOCAT) -,rawer "UNIX-CONNECT:$(QEMU_MONITOR_SOCKET)"
