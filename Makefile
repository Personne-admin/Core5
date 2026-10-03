.DEFAULT_GOAL := all

ifeq ($(OS),Core5)
    HOST			:= Core5
    PATH_SEPARATOR	:= \
    SHELL			:= Binaries:\Shell Host.bin
    SILENCE			:= 2> Dev:\Null
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Linux)
        HOST			:= Linux
        PATH_SEPARATOR	:= /
        SHELL			:= /bin/bash
        SILENCE			:= 2>/dev/null
    else
        $(error Unsupported architecture $(UNAME_S))
    endif
endif

export HOST PATH_SEPARATOR

SELF_MAKEFILE	:= $(lastword $(MAKEFILE_LIST))
ABS_ROOT		:= $(realpath $(dir $(SELF_MAKEFILE)))

export ABS_ROOT

WORK_ROOT			:= $(ABS_ROOT)$(PATH_SEPARATOR)Work
TOOLS_ROOT			:= $(ABS_ROOT)$(PATH_SEPARATOR)Tools
THIRDPARTY_ROOT		:= $(ABS_ROOT)$(PATH_SEPARATOR)Third Party
BUILDSYSTEM_ROOT	:= $(ABS_ROOT)$(PATH_SEPARATOR)Build System

export WORK_ROOT TOOLS_ROOT THIRDPARTY_ROOT

EMPTY	:=
SPACE	:= $(EMPTY) $(EMPTY)
TAB		:= $(EMPTY)	$(EMPTY)

escape_path = $(subst $(SPACE),\$(SPACE),$(1))

export SPACE TAB
export escape_path

PATH_SPACE_TOKEN	:= @SP@
decode_path			= $(subst $(PATH_SPACE_TOKEN),$(SPACE),$(1))
encode_path			= $(subst $(SPACE),$(PATH_SPACE_TOKEN),$(1))

export decode_path encode_path

LATEST_TAG	:= $(shell git describe --tags --abbrev=0 $(SILENCE))
ifeq ($(LATEST_TAG),)
    VERSION		:= 0.0.0-dev
    BUILD_ID	:= dev
else
    FULL_DESC	:= $(shell git describe --tags $(SILENCE))

    ifeq ($(FULL_DESC),$(LATEST_TAG))
        VERSION			:= $(LATEST_TAG)-release
        BUILD_ID		:= release
    else
        COMMIT_COUNT	:= $(shell git rev-list --count $(LATEST_TAG)..HEAD)
        VERSION			:= $(LATEST_TAG)-dev.$(COMMIT_COUNT)
        BUILD_ID 		:= dev
    endif
endif

export VERSION BUILD_ID

VERSION_FILE	:= $(WORK_ROOT)/Version
eVERSION_FILE	:= $(call encode_path,$(VERSION_FILE))

export VERSION_FILE



HOST_SPECIFIC_MACROS	:= $(BUILDSYSTEM_ROOT)$(PATH_SEPARATOR)Host Specific Macros.mk
FASMG_TOOLCHAIN			:= $(BUILDSYSTEM_ROOT)$(PATH_SEPARATOR)Flat Assembler G Toolchain.mk
HOST_TOOLS				:= $(BUILDSYSTEM_ROOT)$(PATH_SEPARATOR)Host Tools.mk
BOOTLOADER_MODULE		:= $(ABS_ROOT)$(PATH_SEPARATOR)Boot Loader$(PATH_SEPARATOR)Module.mk
QUICK_EMULATOR_MODULE	:= $(BUILDSYSTEM_ROOT)$(PATH_SEPARATOR)Quick Emulator.mk
BOCHS_MODULE			:= $(BUILDSYSTEM_ROOT)$(PATH_SEPARATOR)Bochs.mk

include $(call escape_path,$(HOST_SPECIFIC_MACROS))
include $(call escape_path,$(FASMG_TOOLCHAIN))
include $(call escape_path,$(HOST_TOOLS))
include $(call escape_path,$(BOOTLOADER_MODULE))



IMAGE_DIR		:= $(WORK_ROOT)$(PATH_SEPARATOR)Images
STAGING_DIR		:= $(WORK_ROOT)$(PATH_SEPARATOR)Staging
FLOPPY_IMG		:= $(IMAGE_DIR)$(PATH_SEPARATOR)Core5.img

eSTAGING_DIR	:= $(call encode_path,$(STAGING_DIR))
eFLOPPY_IMG		:= $(call encode_path,$(FLOPPY_IMG))

FAT12_OEM_SIZE			:= 11 # JMP instruction + OEM name
FAT12_BPP_SIZE			:= 25
FAT12_EBR_SIZE			:= 26
FAT12_BOOTCODE_START	:= 62

export IMAGE_DIR STAGING_DIR

$(eFLOPPY_IMG): $(eBOOTLOADER_STAGE1) $(eBOOTLOADER_STAGE2) $(eINSTALL_FAT_BOOT_FILE) | $(eSTAGING_DIR)
	@$(CMD_MKDIR_P) "$(call decode_path,$(dir $@))"
	@$(call CMD_FORMAT,$(call decode_path,$@),2880,fat12)
	@$(call CMD_COPY_BLOCKS,$(call decode_path,$<),$(call decode_path,$@),1,3,0,0) $(SILENCE)
	@$(call CMD_COPY_BLOCKS,$(call decode_path,$<),$(call decode_path,$@),1,450,62,62) $(SILENCE)
	@$(call CMD_INSTALL_FAT_BOOT_FILE,$(call decode_path,$@),$(BOOTLOADER_STAGE2))

$(eSTAGING_DIR):
	@$(CMD_MKDIR_P) "$(call decode_path,$(eSTAGING_DIR))"



ifeq ($(HOST),Linux)
    include $(call escape_path,$(QUICK_EMULATOR_MODULE))
    include $(call escape_path,$(BOCHS_MODULE))
endif



ifeq ($(HOST),Core5)
    UPDATE_VERSION = \
        If ( File-Exists "$(call decode_path,$@)" ) Then
            Set CURRENT "%%$(CMD_CAT)"$(call decode_path,$@)"%%";
        Else
            Set CURRENT "";
        End
        If ( %CURRENT% != "$(VERSION)" ) Then
            $(CMD_PRINTF) '%s\n' "$(VERSION)" > "$(call decode_path,$@).tmp";
			$(CMD_MV) "$(call decode_path,$@).tmp" "$(call decode_path,$@)";
        End
else
    UPDATE_VERSION = \
        if [ -f "$(call decode_path,$@)" ]; then \
            current=$$($(CMD_CAT) "$(call decode_path,$@)"); \
        else \
            current=""; \
        fi; \
        if [ "$$current" != "$(VERSION)" ]; then \
            $(CMD_PRINTF) '%s\n' "$(VERSION)" > "$(call decode_path,$@).tmp" && $(CMD_MV) "$(call decode_path,$@).tmp" "$(call decode_path,$@)"; \
        fi
endif

$(eVERSION_FILE): FORCE_VERSION
	@$(CMD_MKDIR_P) "$(call decode_path,$(dir $@))"
	@$(UPDATE_VERSION)

FORCE_VERSION:
.PHONY: FORCE_VERSION



.PHONY: all build image floppy bootloader clean version

all: build

build: bootloader floppy

bootloader: $(eBOOTLOADER_STAGE1_FLOPPY) $(eBOOTLOADER_STAGE2)

floppy: $(eFLOPPY_IMG)

image: floppy

version: $(eVERSION_FILE)

clean:
	$(CMD_RM_RF) "$(WORK_ROOT)"


