
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

    SFDISK              ?= sfdisk
endif

ifeq ($(HOST),Core5)
    CMD_FORMAT			= Format-Fat -Image "$(1)" -Size $(2) -Format $(3)
    CMD_COPY_BLOCKS		= Write-Blocks -Source "$(1)" -Target "$(2)" -BlockSize $(3) -Count $(4) -SourceOffset $(5) -TargetOffset $(6)
    CMD_MCOPY			= Copy-To-Disk -Target "$(1)" -Source "$(2)" -Path "\$(3)"
    CMD_CREATE_IMAGE	= Create-File -Path "$(1)" -Size $(2)
    CMD_PARTITION		= Partition-Disk -Image "$(1)" -Start $(2) -Size $(3) -Type 0xC -Bootable
    CMD_FORMAT_PARTITION= Format-Fat -Image "$(1)" -Offset $(2) -Size $(3) -Hidden $(4) -Heads $(5) -SectorsPerTrack $(6) -SectorsPerCluster $(7) -Format fat32
else
    CMD_FORMAT			= mformat -i "$(1)" -f $$(( $(2) / 2 )) -C
    CMD_COPY_BLOCKS		= dd if="$(1)" of="$(2)" bs=$(3) count=$(4) skip=$(5) seek=$(6) conv=notrunc
    CMD_MCOPY			= mcopy -i "$(1)" "$(2)" "::/$(3)"
    CMD_CREATE_IMAGE	= truncate -s $(2) "$(1)"
    CMD_PARTITION		= printf 'label: dos\nstart=%s, size=%s, type=c, bootable\n' $(2) $(3) | $(SFDISK) -q "$(1)"
    CMD_FORMAT_PARTITION= mformat -i "$(1)@@$(2)" -F -c $(7) -T $(3) -H $(4) -h $(5) -s $(6) ::
endif

export CMD_MKDIR_P CMD_RM_RF CMD_MV CMD_CAT CMD_PRINTF
export CMD_FORMAT CMD_COPY_BLOCKS CMD_MCOPY
