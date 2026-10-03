Install.Error.Invalid = 1
Install.Error.Full = 2
Install.Error.TooLarge = 3
Install.Error.GapTooSmall = 4

Install.MaxStage2Sectors = 59

segment readable writeable
Install.Image dd 0
Install.ImageSize dd 0
Install.Source dd 0
Install.SourceSize dd 0
Install.SourcePath dd 0
Install.BytesPerSector dd 0
Install.BytesPerCluster dd 0
Install.FatOffset dd 0
Install.FatBytes dd 0
Install.FatCount dd 0
Install.RootOffset dd 0
Install.RootEntries dd 0
Install.DataOffset dd 0
Install.ClusterCount dd 0
Install.FirstCluster dd 0

Install.Offset.BytesPerSector = 11
Install.Offset.SectorsPerCluster = 13
Install.Offset.ReservedSectors = 14
Install.Offset.FATs = 16
Install.Offset.RootDirectoryEntries = 17
Install.Offset.Sectors = 19
Install.Offset.SectorsPerFAT = 22
Install.Offset.LargeSectors = 32

segment readable executable

; eax = image, edx = image size, ecx = source, ebx = source size, esi = source path
; returns zero on success
Install.Install:
	mov	[Install.Image], eax
	mov	[Install.ImageSize], edx
	mov	[Install.Source], ecx
	mov	[Install.SourceSize], ebx
	mov	[Install.SourcePath], esi

	; the image must have the bios signature
	cmp	word [eax + 510], 0xAA55
	jne	.Invalid

	; mbr + fat32, stage2 goes into reserved sectors before the first partition
	call	Install.IsMbrFat32
	test	eax, eax
	jnz	Install.InstallReserved

	; fat12 path

	call	Install.ReadLayout
	test	eax, eax
	jnz	.Done

	call	Install.FindDirectorySlot
	test	eax, eax
	js	.Full

	push	eax
	call	Install.AllocateAndCopy
	test	eax, eax
	jnz	.AllocationFailed

	pop	eax
	call	Install.InsertDirectoryEntry
.Success:
	xor	eax, eax
.Done:
	retn

.AllocationFailed:
	add	esp, 4
	retn

.Invalid:
	mov	eax, Install.Error.Invalid
	retn

.Full:
	mov	eax, Install.Error.Full
	retn

; detect if the image is mbr + fat32 rather than fat12
Install.IsMbrFat32:
	; seek to the first partition entry in mbr
	mov	edx, [Install.Image]
	lea edx, [edx + 446]

	; scan up to the four primary paritions
	mov ecx, 4
.Next:
	mov	al, [edx + 4]
	cmp	al, 0xB											; fat32 using standard CHS/LBA
	je	.CheckStart
	cmp	al, 0xC											; fat32 using LBA extensions
	je	.CheckStart
	cmp	al, 0x1B										; hidden fat32
	je	.CheckStart
	cmp	al, 0x1C										; hidden fat32 using LBA extensions
	jne	.Advance
.CheckStart:
	; is the starting LBA sector valid?
	cmp	dword [edx + 8], 0
	jne	.Yes
.Advance:
	; check the next entry
	add	edx, 16
	loop	.Next

	; none found
	xor	eax, eax
	retn

.Yes:
	mov	eax, 1
	retn

; validate the BPB and calculate all byte offsets.
Install.ReadLayout:
	push	ebx esi edi ebp

	; verify bytes per sector to be at least 512
	mov	esi, [Install.Image]
	movzx	eax, word [esi + Install.Offset.BytesPerSector]
	cmp	eax, 512
	jb	.Invalid

	; verify po2 bytes per sector
	mov	edx, eax
	dec	edx
	test	eax, edx
	jnz	.Invalid

	mov	[Install.BytesPerSector], eax

	movzx	ebx, byte [esi + Install.Offset.SectorsPerCluster]
	test	ebx, ebx
	jz	.Invalid

	; verify po2 sectors per cluster
	mov	edx, ebx
	dec	edx
	test	ebx, edx
	jnz	.Invalid

	; calculate the number of bytes per cluster
	mul	ebx
	test	edx, edx
	jnz	.Invalid

	mov	[Install.BytesPerCluster], eax

	movzx	ebp, word [esi + Install.Offset.ReservedSectors]
	test	ebp, ebp
	jz	.Invalid

	movzx	edi, byte [esi + Install.Offset.FATs]
	test	edi, edi
	jz	.Invalid

	mov	[Install.FatCount], edi
	movzx	ecx, word [esi + Install.Offset.RootDirectoryEntries]
	test	ecx, ecx
	jz	.Invalid

	mov	[Install.RootEntries], ecx
	movzx	ebx, word [esi + Install.Offset.SectorsPerFAT]
	test	ebx, ebx
	jz	.Invalid

	; calculate the number of bytes per FAT
	mov	eax, ebx
	mul	dword [Install.BytesPerSector]
	test	edx, edx
	jnz	.Invalid

	mov	[Install.FatBytes], eax

	; calculate the FAT offset
	mov	eax, ebp
	mul	dword [Install.BytesPerSector]
	test	edx, edx
	jnz	.Invalid

	mov	[Install.FatOffset], eax

	; calculate the root directory offset
	mov	eax, ebx
	mul	edi
	add	eax, ebp
	jc	.Invalid

	mul	dword [Install.BytesPerSector]
	test	edx, edx
	jnz	.Invalid

	mov	[Install.RootOffset], eax

	; calculate the data region offset
	mov	eax, ecx
	shl	eax, 5
	add	eax, [Install.BytesPerSector]
	dec	eax

	xor	edx, edx
	div	dword [Install.BytesPerSector]
	mul	dword [Install.BytesPerSector]

	add	eax, [Install.RootOffset]
	jc	.Invalid

	mov	[Install.DataOffset], eax

	; if Install.Sectors == 0, use the large sector count entry
	movzx	eax, word [esi + Install.Offset.Sectors]
	test	eax, eax
	jnz	.HaveSectors

	mov	eax, [esi + Install.Offset.LargeSectors]
.HaveSectors:
	test	eax, eax
	jz	.Invalid

	; calculate the total size
	mul	dword [Install.BytesPerSector]
	test	edx, edx
	jnz	.Invalid

	; ensure that the disk image is not smaller than fat expects
	cmp	eax, [Install.ImageSize]
	ja	.Invalid

	sub	eax, [Install.DataOffset]
	jc	.Invalid

	; calculate the data area cluster count
	xor	edx, edx
	div	dword [Install.BytesPerCluster]
	test	eax, eax
	jz	.Invalid

	; verify the count is within fat12 bounds
	cmp	eax, 4085
	jae	.Invalid

	mov	[Install.ClusterCount], eax

	; calculate the number of bytes required to address the data area
	add	eax, 2
	lea	eax, [eax + eax*word]
	inc	eax
	shr	eax, 1

	; verify the FAT is capable of addressing the entire data area
	cmp	eax, [Install.FatBytes]
	ja	.Invalid

	xor	eax, eax
	jmp	.Done

.Invalid:
	mov	eax, Install.Error.Invalid
.Done:
	pop	ebp edi esi ebx
	retn

; find a free entry in the root directory
Install.FindDirectorySlot:
	mov	edx, [Install.Image]
	add	edx, [Install.RootOffset]
	xor	eax, eax
	; iterate the root directory directory entries
.Next:
	cmp	eax, [Install.RootEntries]
	jae	.Full

	; found free spot
	mov	cl, [edx]
	test	cl, cl
	jz	.Done

	; found a deleted entry, can be reused
	cmp	cl, 0xE5
	je	.Done

	; move to the next directory entry
	inc	eax
	add	edx, 32
	jmp	.Next

.Full:
	or	eax, -1
.Done:
	retn

; allocates free data clusters for and copies the source file to them
Install.AllocateAndCopy:
	push	ebx esi edi ebp

	mov	eax, [Install.SourceSize]
	test	eax, eax
	jz	.Empty

	add	eax, [Install.BytesPerCluster]
	jc	.TooLarge

	; calculate the number of clusters needed for the source file
	dec	eax
	xor	edx, edx
	div	dword [Install.BytesPerCluster]
	mov	ebp, eax

	; verify the source file fits onto the image
	cmp	eax, [Install.ClusterCount]
	ja	.TooLarge

	; verify there are enough free cluster for the source file
	mov	esi, 2
	xor	ebx, ebx
.CountFree:
	mov	eax, [Install.ClusterCount]
	inc	eax
	cmp	esi, eax
	ja	.TooLarge

	mov	eax, esi
	call	Install.GetEntry
	test	eax, eax
	jnz	.CountNext

	inc	ebx
	cmp	ebx, ebp
	je	.EnoughFree
.CountNext:
	inc	esi
	jmp	.CountFree

	; there are enough free clusters
.EnoughFree:
	mov	esi, 2
	xor	edi, edi
	xor	ebx, ebx
.Find:
	mov	eax, [Install.ClusterCount]
	inc	eax
	cmp	esi, eax
	ja	.TooLarge

	mov	eax, esi
	call	Install.GetEntry
	test	eax, eax
	jnz	.Advance

	test	edi, edi
	jnz	.Link

	; store the first allocated cluster
	mov	[Install.FirstCluster], esi
	jmp	.Record

.Link:
	mov	eax, edi
	mov	edx, esi
	call	Install.SetEntry
.Record:
	mov	edi, esi
	inc	ebx
	cmp	ebx, ebp
	je	.Finish
.Advance:
	inc	esi
	jmp	.Find

.Finish:
	mov	eax, edi
	mov	edx, 0xFFF
	call	Install.SetEntry

	mov	ebx, [Install.FirstCluster]
	mov	ebp, [Install.SourceSize]
	mov	esi, [Install.Source]
.Copy:
	; compute the address of the ebx'th cluster
	mov	eax, ebx
	sub	eax, 2
	mul	dword [Install.BytesPerCluster]
	add	eax, [Install.DataOffset]
	add	eax, [Install.Image]
	mov	edi, eax

	; every cluster is full except possibly the last
	mov	ecx, [Install.BytesPerCluster]
	cmp	ebp, ecx
	jae	.CountReady
	mov	ecx, ebp
.CountReady:
	; use the count before it get's eaten by rep
	sub	ebp, ecx
	mov	edx, ecx
	rep	movsb

	; zero the tail of the cluster
	mov	ecx, [Install.BytesPerCluster]
	sub	ecx, edx
	xor	eax, eax
	rep	stosb

	; recheck clobbered flags, are we done?
	test	ebp, ebp
	jz	.Success

	; get the next entry
	mov	eax, ebx
	call	Install.GetEntry
	mov	ebx, eax
	jmp	.Copy

.Empty:
	mov	dword [Install.FirstCluster], 0
.Success:
	xor	eax, eax
	jmp	.Done

.TooLarge:
	mov	eax, Install.Error.TooLarge
.Done:
	pop	ebp edi esi ebx
	retn

; eax = cluster number
; returns eax = 12-bit fat entry for that cluster
Install.GetEntry:
	push	ebx

	; calculate the address of the entry
	mov	ebx, eax
	shr	eax, 1
	add	eax, ebx
	add	eax, [Install.FatOffset]
	add	eax, [Install.Image]

	; load-now determine parity later, movzx doesn't touch flags
	movzx	eax, word [eax]
	test	bl, 1
	jz	.Even

	; entry is the high 12 bits, shift them into the low ones
	shr	eax, 4
.Even:
	and	eax, 0xFFF

	pop	ebx
	retn

; eax = cluster number, edx = new 12-bit value
Install.SetEntry:
	push	eax ebx ecx edx esi

	; calculate the address of the entry
	mov	ebx, eax
	shr	eax, 1
	add	eax, ebx
	add	eax, [Install.FatOffset]
	add	eax, [Install.Image]

	; prepare the mask based on the parity
	and	edx, 0xFFF

	; even: it is the top nibble
	mov	esi, 0xF000
	test	bl, 1
	jz	.Prepared

	; odd: occupies high 12 bits and it's the bottom nibble
	shl	edx, 4
	mov	esi, 0x000F
.Prepared:
	mov	ecx, [Install.FatCount]
.Next:
	; rmf as the word is shared with the neighbour entry
	movzx	ebx, word [eax]
	and	ebx, esi
	or	ebx, edx
	mov	[eax], bx

	add	eax, [Install.FatBytes]
	dec	ecx
	jnz	.Next

	pop	esi edx ecx ebx eax
	retn

; eax = index of the free slot
Install.InsertDirectoryEntry:
	push	esi edi

	mov	edi, [Install.Image]
	add	edi, [Install.RootOffset]

	; if the free slot is already slot 0, there is nothing to move
	test	eax, eax
	jz	.Create

	; shift entries 0..k-1 down into 1..k, overwriting the free slot
	; lfn entries must stay contiguous, forcing a full shift
	push	edi

	; k entries are exactly 8k dwords
	lea	ecx, [eax*8]

	; copy backwards as the destination is higher (and they overlap)
	shl	eax, 5
	lea	edi, [edi + eax + 28]											; last dword of slot k
	lea	esi, [edi - 32]													; last dword of slot k-1

	std
	rep	movsd
	cld

	pop edi

	; fill in the fat12 directory entry
.Create:
	; 0..10: 8.3 name
	; 11: attribute 0x27, ascii `'`, ro, hidden, system and archive
	mov	dword [edi], 'BOOT'
	mov	dword [edi + 4], '    '
	mov	dword [edi + 8], 'BIN'''

	; 12..15: reserved byte, creation tenths, creation time
	mov	dword [edi + 12], 0

	; 16: creation date, 18: last access date.
	mov	dword [edi + 16], 0x00210021

	; 20: high word of the first cluster
	; 22: last write time
	mov	dword [edi + 20], 0

	; 24: last write date
	; 26: first cluster
	mov	eax, [Install.FirstCluster]
	shl	eax, 16
	or	eax, 0x21
	mov	[edi + 24], eax

	; 28: file size in bytes
	mov	eax, [Install.SourceSize]
	mov	[edi + 28], eax

	pop	edi esi
	xor	eax, eax
	retn

; returns zero on success
Install.InstallReserved:
	push	ebx esi edi

	; find the lowest starting lba of any used partition
	mov	esi, [Install.Image]
	lea esi, [esi + 446]
	or	ebx, -1
	mov	ecx, 4
.Scan:
	; empty entry
	cmp	byte [esi + 4], 0
	je	.Skip
	mov	eax, [esi + 8]
	test	eax, eax
	jz	.Skip

	; already have a better candidate
	cmp	eax, ebx
	jae	.Skip

	; update the candidate
	mov	ebx, eax
.Skip:
	; move to the next partition
	add	esi, 16
	loop	.Scan

	; IsMbrFat32 guarantees one valid entry, the gap is LBA 1..start-1
	dec	ebx
	jz	.GapTooSmall

	; stage1 cannot load more than its window regardless of the gap
	cmp	ebx, Install.MaxStage2Sectors
	jbe	.HaveGap
	mov	ebx, Install.MaxStage2Sectors
.HaveGap:
	; calculate the number of sectors the source needs
	mov	eax, [Install.SourceSize]
	add	eax, 511
	jc	.GapTooSmall
	shr	eax, 9
	cmp	eax, ebx
	ja	.GapTooSmall

	; the image must actually contain those sectors
	inc	eax
	shl	eax, 9
	cmp	eax, [Install.ImageSize]
	ja	.Invalid

	; copy the source to LBA 1
	mov	edi, [Install.Image]
	add	edi, 512
	mov	esi, [Install.Source]
	mov	ecx, [Install.SourceSize]
	mov	edx, ecx
	rep	movsb

	; zero the tail of the last sector
	neg	edx
	and	edx, 511
	mov	ecx, edx
	xor	eax, eax
	rep	stosb

	xor	eax, eax
	jmp	.Done

.GapTooSmall:
	mov	eax, Install.Error.GapTooSmall
	jmp	.Done

.Invalid:
	mov	eax, Install.Error.Invalid
.Done:
	pop	edi esi ebx
	retn
