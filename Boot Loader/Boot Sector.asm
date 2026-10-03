use16
org 0x7C00

	jmp	short Start
	nop

OEMName:				db 'CORE5   '
BPB.BytesPerSector:		dw 512
BPB.SectorsPerCluster:	db 1
BPB.ReservedSectors:	dw 1
BPB.FatCount:			db 2
BPB.RootEntries:		dw 224
BPB.TotalSectors16:		dw 2880
BPB.Media:				db 0xF0
BPB.SectorsPerFat:		dw 9
BPB.SectorsPerTrack:	dw 18
BPB.HeadCount:			dw 2
BPB.HiddenSectors:		dd 0
BPB.TotalSectors32:		dd 0

EBR.DriveNumber:		db 0
EBR.Reserved:			db 0
EBR.Signature:			db 0x29
EBR.Serial:				dd 0
EBR.Label:				db 'NO NAME    '
EBR.Type:				db 'FAT12   '

label	RootLBA:word at EBR.Signature
label	DataLBA:word at EBR.Signature + 2

Stage2LoadAddress	= 0x500
TransitionBuffer	= 0x7E00
Stage2MaxSize		= 0x7600

Start:
	xor	ax, ax
	mov	ss, ax
	mov	sp, 0x7C00

	mov	ds, ax
	cld

	mov [EBR.DriveNumber], dl

	; calculate the lba of the root directory
	mov	al, [BPB.FatCount]
	mul	word [BPB.SectorsPerFat]
	add	ax, [BPB.ReservedSectors]

	mov	[RootLBA], ax

	; calculate the number of sectors in the directory
	mov	cx, [BPB.RootEntries]
	add	cx, 15
	shr	cx, 4

	; calculate the data section lba
	add	ax, cx
	mov	[DataLBA], ax

	; load the root directory
	mov	ax, [RootLBA]
	mov	bx, TransitionBuffer
	call	ReadSectors

	; search the root directory for BOOT.BIN
	mov	cx, [BPB.RootEntries]
	mov	di, TransitionBuffer
.Search:
	cmp	byte [di], 0											; eod
	je	Error

	push	cx di

	mov	si, Stage2FileName
	mov	cx, 11
	repe	cmpsb

	pop	di cx

	je	.Found

	; next entry
	add	di, 32
	loop	.Search
	jmp	Error

.Found:
	; verify the size limit
	cmp	word [di + 30], 0
	jne	Error
	cmp	word [di + 28], Stage2MaxSize
	ja	Error

	push	word [di + 26]			; first cluster

	; load FAT #0
	mov	ax, [BPB.ReservedSectors]
	mov	cx, [BPB.SectorsPerFat]
	mov	bx, TransitionBuffer
	call	ReadSectors

	; follow the cluster chain
	pop	ax
	mov	bx, Stage2LoadAddress
.NextCluster:
	push	ax

	sub	ax, 2
	mov	cl, [BPB.SectorsPerCluster]
	xor	ch, ch
	mul	cx
	add	ax, [DataLBA]
	call	ReadSectors

	pop	ax

	; calculate the address of the entry
	mov	si, ax
	shr	si, 1
	add	si, ax

	; load-now determine parity later, movzx doesn't touch flags
	mov	dx, [si + TransitionBuffer]
	test	al, 1
	jz	.Even

	; entry is the high 12 bits, shift them into the low ones
	mov	cl, 4
	shr	dx, cl
.Even:
	and	dx, 0xFFF

	; next cluster number
	mov	ax, dx

	cmp	ax, 0xFF8
	jb	.NextCluster

	; verify for corruption markers

	; hand control over
	mov	dl, [EBR.DriveNumber]
	jmp	0x0000:Stage2LoadAddress

; ax = starting lba, cx = sector count, es:bx = destination buffer
; returns ax/bx advanced
; trashes dx, di
ReadSectors:
	push ax cx

	; convert lba to chs

	; calculate the sector
	xor	dx, dx
	div	word [BPB.SectorsPerTrack]
	inc	dx
	mov	cl, dl

	; calculate the cylinder and head
	xor	dx, dx
	div	word [BPB.HeadCount]
	mov	ch, al
	mov	dh, dl

	mov	dl, [EBR.DriveNumber]

	; retry reading from the floppy up to three times
	mov	di, 3
.Retry:
	; DISK - READ SECTOR(S) INTO MEMORY
	; AH = 02h
	; AL = number of sectors to read (must be nonzero)
	; CH = low eight bits of cylinder number
	; CL = sector number 1-63 (bits 0-5)
	; high two bits of cylinder (bits 6-7, hard disk only)
	; DH = head number
	; DL = drive number (bit 7 set for hard disk)
	; ES:BX -> data buffer
	; https://www.ctyme.com/intr/rb-0607.htm
	mov	ax, 0x201
	int	0x13
	jnc	.Done

	; DISK - RESET DISK SYSTEM
	; AH = 00h
	; DL = drive (if bit 7 is set both hard disks and floppy disks reset)
	xor	ah, ah
	int	0x13

	; try again
	dec	di
	jnz	.Retry
	jmp	Error

.Done:
	pop	cx ax

	inc	ax
	add	bx, [BPB.BytesPerSector]
	loop	ReadSectors

	ret

Error:
	mov	si, ErrorMessage
.Print:
	lodsb
	test	al, al
	jz	WaitKeyStroke

	; VIDEO - TELETYPE OUTPUT
	; AH = 0Eh
	; AL = character to write
	; BH = page number
	; BL = foreground color (graphics modes only)
	mov	ah, 0xE
	mov	bx, 0x7
	int	0x10
	jmp	.Print

WaitKeyStroke:
	; KEYBOARD - GET KEYSTROKE
	; AH = 00h
	xor	ah, ah
	int	0x16
Reboot:
	; SYSTEM - BOOTSTRAP LOADER
	int	0x19

Stage2FileName:	db 'BOOT    BIN'
ErrorMessage:	db 'Boot error', 13, 10, 0

	db	510 - ($ - $$) dup 0
	dw	0xAA55
