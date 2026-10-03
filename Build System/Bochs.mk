BOCHS				?= bochs
BOCHS_DEBUG			?= $(BOCHS)
ENV_SUBSTITUTE		?= envsubst

BOCHS_CONFIG_TEMPLATE	:= $(BUILDSYSTEM_ROOT)$(PATH_SEPARATOR)Configuration Scripts$(PATH_SEPARATOR)Bochs.bochsrc.in
BOCHS_CONFIG			:= $(EMULATOR_WORK_ROOT)$(PATH_SEPARATOR)Bochs.bochsrc
BOCHS_RUN_COMMANDS		:= $(BUILDSYSTEM_ROOT)$(PATH_SEPARATOR)Configuration Scripts$(PATH_SEPARATOR)Bochs Run.rc

eBOCHS_CONFIG_TEMPLATE	:= $(call escape_path,$(BOCHS_CONFIG_TEMPLATE))
eBOCHS_CONFIG			:= $(call escape_path,$(BOCHS_CONFIG))

BOCHS_CPU			?= pentium
BOCHS_MEMORY		?= 8
BOCHS_HDD_CYLINDERS	?= $(HDD_CYLINDERS)
BOCHS_HDD_HEADS		?= $(HDD_HEADS)
BOCHS_HDD_SECTORS	?= $(HDD_SPT)

BOCHS_ENVIRONMENT = \
	CORE_BOCHS_CPU="$(BOCHS_CPU)" \
	CORE_BOCHS_MEMORY="$(BOCHS_MEMORY)" \
	CORE_BOCHS_HDD_IMAGE="$(HDD_IMG)" \
	CORE_BOCHS_HDD_CYLINDERS="$(BOCHS_HDD_CYLINDERS)" \
	CORE_BOCHS_HDD_HEADS="$(BOCHS_HDD_HEADS)" \
	CORE_BOCHS_HDD_SECTORS="$(BOCHS_HDD_SECTORS)" \
	CORE_BOCHS_FLOPPY_IMAGE="$(FLOPPY_IMG)" \
	CORE_BOCHS_BOOT="$(BOCHS_BOOT)"

.PHONY: bochs-floppy bochs-hdd bochs-floppy-debug bochs-hdd-debug bochs bochs-debug FORCE_BOCHS_CONFIG

bochs-floppy bochs-floppy-debug:	BOCHS_BOOT := floppy
bochs-hdd bochs-hdd-debug:			BOCHS_BOOT := disk

$(eBOCHS_CONFIG): $(eBOCHS_CONFIG_TEMPLATE) FORCE_BOCHS_CONFIG
	@$(CMD_MKDIR_P) "$(EMULATOR_WORK_ROOT)"
	@$(BOCHS_ENVIRONMENT) $(ENV_SUBSTITUTE) < "$<" > "$@"

FORCE_BOCHS_CONFIG:

bochs-floppy bochs-hdd: $(eFLOPPY_IMG) $(eHDD_IMG) $(eBOCHS_CONFIG)
	@$(BOCHS) -unlock -f "$(BOCHS_CONFIG)" -q -rc "$(BOCHS_RUN_COMMANDS)"

bochs-floppy-debug bochs-hdd-debug: $(eFLOPPY_IMG) $(eHDD_IMG) $(eBOCHS_CONFIG)
	@$(BOCHS_DEBUG) -unlock -f "$(BOCHS_CONFIG)" -q

bochs: bochs-floppy
bochs-debug: bochs-floppy-debug
