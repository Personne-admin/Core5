
ifeq ($(HOST),Core5)
    CMD_MKDIR_P			:= Make-Dir -Recrusive
    CMD_RM_RF			:= Remove -All -Force
    CMD_MV				:= Move-File
    CMD_CAT				:= Read-File
    CMD_PRINTF			:= POSIX\Printf
else
    CMD_MKDIR_P			:= mkdir -p
    CMD_RM_RF			:= rm -rf
    CMD_MV				:= mv
    CMD_CAT				:= cat
    CMD_PRINTF			:= printf
endif

ifeq ($(HOST),Core5)
    CMD_FORMAT			= Format-Fat -Image "$(1)" -Size $(2) -Format $(3)
    CMD_COPY_BLOCKS	    = Write-Blocks -Source "$(1)" -Target "$(2)" -BlockSize $(3) -Count $(4) -SourceOffset $(5) -TargetOffset $(6)
    CMD_MCOPY			= Copy-To-Disk -Target "$(1)" -Source "$(2)" -Path "\$(3)"
else
    CMD_FORMAT			= mformat -i "$(1)" -f $(2) -C
    CMD_COPY_BLOCKS	    = dd if="$(1)" of="$(2)" bs=$(3) count=$(4) skip=$(5) seek=$(6) conv=notrunc
    CMD_MCOPY			= mcopy -i "$(1)" "$(2)" "::/$(3)"
endif

export CMD_MKDIR_P CMD_RM_RF CMD_MV CMD_CAT CMD_PRINTF
export CMD_FORMAT CMD_COPY_BLOCKS CMD_MCOPY
