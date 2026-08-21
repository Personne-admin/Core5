FAT12.Error.Invalid = 1
FAT12.Error.Full = 2
FAT12.Error.TooLarge = 3

segment readable writeable
FAT12.Image dd 0
FAT12.ImageSize dd 0
FAT12.Source dd 0
FAT12.SourceSize dd 0
FAT12.SourcePath dd 0
FAT12.BytesPerSector dd 0
FAT12.BytesPerCluster dd 0
FAT12.FatOffset dd 0
FAT12.FatBytes dd 0
FAT12.FatCount dd 0
FAT12.RootOffset dd 0
FAT12.RootEntries dd 0
FAT12.DataOffset dd 0
FAT12.ClusterCount dd 0
FAT12.FirstCluster dd 0

FAT12.Offset.BytesPerSector = 11
FAT12.Offset.SectorsPerCluster = 13
FAT12.Offset.ReservedSectors = 14
FAT12.Offset.FATs = 16
FAT12.Offset.RootDirectoryEntries = 17
FAT12.Offset.Sectors = 19
FAT12.Offset.SectorsPerFAT = 22
FAT12.Offset.LargeSectors = 32

segment readable executable

; eax = image, edx = image size, ecx = source, ebx = source size, esi = source path
; returns zero on success
FAT12.Install:
	mov	[FAT12.Image], eax
	mov	[FAT12.ImageSize], edx
	mov	[FAT12.Source], ecx
	mov	[FAT12.SourceSize], ebx
	mov	[FAT12.SourcePath], esi

	; the image must have the bios signature
	cmp	word [eax + 510], 0xAA55
	jne	.Invalid

	; TODO support fat32 installation.
	call	FAT12.IsMbrFat32
	test	eax, eax
	jnz	.Success

	; fat12 path

	call	FAT12.ReadLayout
	test	eax, eax
	jnz	.Done

	call	FAT12.FindDirectorySlot
	test	eax, eax
	js	.Full

	push	eax
	call	FAT12.AllocateAndCopy
	test	eax, eax
	jnz	.AllocationFailed

	pop	eax
	call	FAT12.InsertDirectoryEntry
.Success:
	xor	eax, eax
.Done:
	retn

.AllocationFailed:
	add	esp, 4
	retn

.Invalid:
	mov	eax, FAT12.Error.Invalid
	retn

.Full:
	mov	eax, FAT12.Error.Full
	retn

; detect if the image is mbr + fat32 rather than fat12
FAT12.IsMbrFat32:
	; seek to the first partition entry in mbr
	mov	edx, [FAT12.Image]
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
FAT12.ReadLayout:
	push	ebx esi edi ebp

	; verify bytes per sector to be at least 512
	mov	esi, [FAT12.Image]
	movzx	eax, word [esi + FAT12.Offset.BytesPerSector]
	cmp	eax, 512
	jb	.Invalid

	; verify po2 bytes per sector
	mov	edx, eax
	dec	edx
	test	eax, edx
	jnz	.Invalid

	mov	[FAT12.BytesPerSector], eax

	movzx	ebx, byte [esi + FAT12.Offset.SectorsPerCluster]
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

	mov	[FAT12.BytesPerCluster], eax

	movzx	ebp, word [esi + FAT12.Offset.ReservedSectors]
	test	ebp, ebp
	jz	.Invalid

	movzx	edi, byte [esi + FAT12.Offset.FATs]
	test	edi, edi
	jz	.Invalid

	mov	[FAT12.FatCount], edi
	movzx	ecx, word [esi + FAT12.Offset.RootDirectoryEntries]
	test	ecx, ecx
	jz	.Invalid

	mov	[FAT12.RootEntries], ecx
	movzx	ebx, word [esi + FAT12.Offset.SectorsPerFAT]
	test	ebx, ebx
	jz	.Invalid

	; calculate the number of bytes per FAT
	mov	eax, ebx
	mul	dword [FAT12.BytesPerSector]
	test	edx, edx
	jnz	.Invalid

	mov	[FAT12.FatBytes], eax

	; calculate the FAT offset
	mov	eax, ebp
	mul	dword [FAT12.BytesPerSector]
	test	edx, edx
	jnz	.Invalid

	mov	[FAT12.FatOffset], eax

	; calculate the root directory offset
	mov	eax, ebx
	mul	edi
	add	eax, ebp
	jc	.Invalid

	mul	dword [FAT12.BytesPerSector]
	test	edx, edx
	jnz	.Invalid

	mov	[FAT12.RootOffset], eax

	; calculate the data region offset
	mov	eax, ecx
	shl	eax, 5
	add	eax, [FAT12.BytesPerSector]
	dec	eax

	xor	edx, edx
	div	dword [FAT12.BytesPerSector]
	mul	dword [FAT12.BytesPerSector]

	add	eax, [FAT12.RootOffset]
	jc	.Invalid

	mov	[FAT12.DataOffset], eax

	; if FAT12.Sectors == 0, use the large sector count entry
	movzx	eax, word [esi + FAT12.Offset.Sectors]
	test	eax, eax
	jnz	.HaveSectors

	mov	eax, [esi + FAT12.Offset.LargeSectors]
.HaveSectors:
	test	eax, eax
	jz	.Invalid

	; calculate the total size
	mul	dword [FAT12.BytesPerSector]
	test	edx, edx
	jnz	.Invalid

	; ensure that the disk image is not smaller than fat expects
	cmp	eax, [FAT12.ImageSize]
	ja	.Invalid

	sub	eax, [FAT12.DataOffset]
	jc	.Invalid

	; calculate the data area cluster count
	xor	edx, edx
	div	dword [FAT12.BytesPerCluster]
	test	eax, eax
	jz	.Invalid

	; verify the count is within fat12 bounds
	cmp	eax, 4085
	jae	.Invalid

	mov	[FAT12.ClusterCount], eax

	; calculate the number of bytes required to address the data area
	add	eax, 2
	lea	eax, [eax + eax*word]
	inc	eax
	shr	eax, 1

	; verify the FAT is capable of addressing the entire data area
	cmp	eax, [FAT12.FatBytes]
	ja	.Invalid

	xor	eax, eax
	jmp	.Done

.Invalid:
	mov	eax, FAT12.Error.Invalid
.Done:
	pop	ebp edi esi ebx
	retn

; find a free entry in the root directory
FAT12.FindDirectorySlot:
	mov	edx, [FAT12.Image]
	add	edx, [FAT12.RootOffset]
	xor	eax, eax
	; iterate the root directory directory entries
.Next:
	cmp	eax, [FAT12.RootEntries]
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
FAT12.AllocateAndCopy:
	push	ebx esi edi ebp

	mov	eax, [FAT12.SourceSize]
	test	eax, eax
	jz	.Empty

	add	eax, [FAT12.BytesPerCluster]
	jc	.TooLarge

	; calculate the number of clusters needed for the source file
	dec	eax
	xor	edx, edx
	div	dword [FAT12.BytesPerCluster]
	mov	ebp, eax

	; verify the source file fits onto the image
	cmp	eax, [FAT12.ClusterCount]
	ja	.TooLarge

	; verify there are enough free cluster for the source file
	mov	esi, 2
	xor	ebx, ebx
.CountFree:
	mov	eax, [FAT12.ClusterCount]
	inc	eax
	cmp	esi, eax
	ja	.TooLarge

	mov	eax, esi
	call	FAT12.GetEntry
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
	mov	eax, [FAT12.ClusterCount]
	inc	eax
	cmp	esi, eax
	ja	.TooLarge

	mov	eax, esi
	call	FAT12.GetEntry
	test	eax, eax
	jnz	.Advance

	test	edi, edi
	jnz	.Link

	; store the first allocated cluster
	mov	[FAT12.FirstCluster], esi
	jmp	.Record

.Link:
	mov	eax, edi
	mov	edx, esi
	call	FAT12.SetEntry
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
	call	FAT12.SetEntry

	mov	ebx, [FAT12.FirstCluster]
	mov	ebp, [FAT12.SourceSize]
	mov	esi, [FAT12.Source]
.Copy:
	; compute the address of the ebx'th cluster
	mov	eax, ebx
	sub	eax, 2
	mul	dword [FAT12.BytesPerCluster]
	add	eax, [FAT12.DataOffset]
	add	eax, [FAT12.Image]
	mov	edi, eax

	; every cluster is full except possibly the last
	mov	ecx, [FAT12.BytesPerCluster]
	cmp	ebp, ecx
	jae	.CountReady
	mov	ecx, ebp
.CountReady:
	; use the count before it get's eaten by rep
	sub	ebp, ecx
	mov	edx, ecx
	rep	movsb

	; zero the tail of the cluster
	mov	ecx, [FAT12.BytesPerCluster]
	sub	ecx, edx
	xor	eax, eax
	rep	stosb

	; recheck clobbered flags, are we done?
	test	ebp, ebp
	jz	.Success

	; get the next entry
	mov	eax, ebx
	call	FAT12.GetEntry
	mov	ebx, eax
	jmp	.Copy

.Empty:
	mov	dword [FAT12.FirstCluster], 0
.Success:
	xor	eax, eax
	jmp	.Done

.TooLarge:
	mov	eax, FAT12.Error.TooLarge
.Done:
	pop	ebp edi esi ebx
	retn

; eax = cluster number
; returns eax = 12-bit fat entry for that cluster
FAT12.GetEntry:
	push	ebx

	; calculate the address of the entry
	mov	ebx, eax
	shr	eax, 1
	add	eax, ebx
	add	eax, [FAT12.FatOffset]
	add	eax, [FAT12.Image]

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
FAT12.SetEntry:
	push	eax ebx ecx edx esi

	; calculate the address of the entry
	mov	ebx, eax
	shr	eax, 1
	add	eax, ebx
	add	eax, [FAT12.FatOffset]
	add	eax, [FAT12.Image]

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
	mov	ecx, [FAT12.FatCount]
.Next:
	; rmf as the word is shared with the neighbour entry
	movzx	ebx, word [eax]
	and	ebx, esi
	or	ebx, edx
	mov	[eax], bx

	add	eax, [FAT12.FatBytes]
	dec	ecx
	jnz	.Next

	pop	esi edx ecx ebx eax
	retn

; eax = index of the free slot
FAT12.InsertDirectoryEntry:
	push	esi edi

	mov	edi, [FAT12.Image]
	add	edi, [FAT12.RootOffset]

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
	mov	eax, [FAT12.FirstCluster]
	shl	eax, 16
	or	eax, 0x21
	mov	[edi + 24], eax

	; 28: file size in bytes
	mov	eax, [FAT12.SourceSize]
	mov	[edi + 28], eax

	pop	edi esi
	xor	eax, eax
	retn
