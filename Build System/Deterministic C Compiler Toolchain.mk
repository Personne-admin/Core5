DCC_ROOT		:= $(THIRDPARTY_ROOT)$(PATH_SEPARATOR)dcc

ifeq ($(HOST),Core5)
    DCC		?= Binaries:\Deterministic-C-Compiler.bin
else
    DCC		?= dcc
endif

eDCC		:= $(call encode_path,$(DCC))

CMD_DCC		= "$(call decode_path,$(eDCC))" $(3) -o "$(2)" "$(1)"
CMD_DCC_ASM	= $(call CMD_DCC,$(1),$(2),-S $(3))
CMD_DCC_OBJ	= $(call CMD_DCC,$(1),$(2),-c $(3))

export DCC_ROOT DCC eDCC
export CMD_DCC CMD_DCC_ASM CMD_DCC_OBJ
