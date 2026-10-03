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

label	UseLBA:byte at EBR.Reserved
label	DataLBA:word at EBR.Signature

Stage2LoadAddress	= 0x500
TransitionBuffer	= 0x7E00
Stage2MaxSize		= 0x7600

match =Stage2Path, Stage2Path
	err 'internal error: Stage2Path is not defined'
end match

virtual at 0
	file Stage2Path
	Stage2Size = $
end virtual

Stage2Sectors = (Stage2Size + 511) shr 9

assert Stage2Sectors >= 1 & Stage2Sectors <= 59

Start:
	xor	ax, ax
	mov	ss, ax
	mov	sp, 0x7C00

	mov	ds, ax
	mov	es, ax
	cld

	mov	[EBR.DriveNumber], dl
	test	dl, dl
	jns	Floppy

HardDisk:
	; IBM/MS INT 13 Extensions - INSTALLATION CHECK
	; AH = 41h
	; BX = 55AAh
	; DL = drive (80h-FFh)
	mov	ah, 0x41
	mov	bx, 0x55AA
	int	0x13
	jc	Error

	cmp	bx, 0xAA55
	jne	Error

	; packet interface supported?
	test	cl, 1
	jz	Error

	inc	byte [UseLBA]

	mov	ax, 1
	mov	cx, Stage2Sectors
	mov	bx, Stage2LoadAddress
	call	ReadSectors

Launch:
	mov	dl, [EBR.DriveNumber]
	jmp	0x0000:Stage2LoadAddress

Floppy:
	; calculate the lba of the root directory
	mov	al, [BPB.FatCount]
	mul	word [BPB.SectorsPerFat]
	add	ax, [BPB.ReservedSectors]

	; calculate the number of sectors in the directory
	mov	cx, [BPB.RootEntries]
	add	cx, 15
	shr	cx, 4

	; calculate the data section lba
	push	ax
	add	ax, cx
	mov	[DataLBA], ax
	pop	ax

	; load the root directory
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

	je	LoadStage2

	; next entry
	add	di, 32
	loop	.Search
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

LoadStage2:
	; verify the size limit
	cmp	word [di + 30], 0
	jne	Error
	cmp	word [di + 28], Stage2MaxSize
	ja	Error

	push	word [di + 26]											; first cluster

	; load FAT #0
	mov	ax, [BPB.ReservedSectors]
	mov	cx, [BPB.SectorsPerFat]
	mov	bx, TransitionBuffer
	call	ReadSectors

	; follow the cluster chain
	pop	ax
	mov	bx, Stage2LoadAddress
.NextCluster:
	; a cyclic or overlong chain would run into the stack and this sector
	; (exact for 1 sector per cluster)
	cmp	bx, Stage2LoadAddress + Stage2MaxSize
	jae	Error

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
	shr	dx, 4
.Even:
	and	dx, 0xFFF
	xchg	ax, dx

	; 0x000 free, 0x001 reserved, chain is broken
	cmp	ax, 2
	jb	Error

	; 0x002..0xFEF: next cluster
	cmp	ax, 0xFF0
	jb	.NextCluster

	; 0xFF0..0xFF6 reserved, 0xFF7 bad cluster
	cmp	ax, 0xFF8
	jb	Error

	; 0xFF8..0xFFF: end of chain
	jmp	Launch

; ax = starting lba, cx = sector count, es:bx = destination buffer
; returns ax/bx advanced
; trashes dx, di, si
ReadSectors:
.Next:
	mov	di, 3													; retries
.Retry:
	pusha
	cmp	byte [UseLBA], 0
	je	.CHS

	; Offset  Size    Description     (Table 00272)
	; 00h    BYTE    size of packet (10h or 18h)
	; 01h    BYTE    reserved (0)
	; 02h    WORD    number of blocks to transfer (max 007Fh for Phoenix EDD)
	; 04h    DWORD   -> transfer buffer
	; 08h    QWORD   starting absolute block number
	push	0													; LBA bits 48..63
	push	0													; LBA bits 32..47
	push	0													; LBA bits 16..31
	push	ax													; LBA bits  0..15
	push	es													; buffer segment
	push	bx													; buffer offset
	push	1													; sector count
	push	0x10												; packet size, reserved
	; IBM/MS INT 13 Extensions - EXTENDED READ
	; AH = 42h
	; DL = drive number
	; DS:SI -> disk address packet (see #00272)
	mov	si, sp
	mov	dl, [EBR.DriveNumber]
	mov	ah, 0x42
	int	0x13

	; drop the packet, lea preserves CF
	lea	sp, [si + 16]
	jmp	.Check

	; convert lba to chs
.CHS:
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
	mov	dl, [EBR.DriveNumber]
	int	0x13
.Check:
	jnc	.Ok

	; DISK - RESET DISK SYSTEM
	; AH = 00h
	; DL = drive (if bit 7 is set both hard disks and floppy disks reset)
	xor	ah, ah
	int	0x13

	popa

	; try again
	dec	di
	jnz	.Retry
	jmp	Error

.Ok:
	popa

	inc	ax
	add	bx, 512
	loop	.Next

	ret

Stage2FileName:	db 'BOOT    BIN'
ErrorMessage:	db 'Boot error', 13, 10, 0

assert	$ - $$ <= 0x1B8

	db	0x1B8 - ($ - $$) dup 0

DiskSignature:	dd 0
				dw 0
PartitionTable:	db 64 dup 0

	dw	0xAA55
