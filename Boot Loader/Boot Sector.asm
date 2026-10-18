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
	Stage2Data::
	file Stage2Path
	Stage2Size = $
end virtual

Stage2Sectors = (Stage2Size + 511) shr 9

assert Stage2Size >= 1 & Stage2Size <= Stage2MaxSize

; CRC-32 (IEEE 802.3, with polynomial 0xEDB88320) computed at build time
; This is the register value BEFORE the final inversion
Stage2Crc = 0xFFFFFFFF
repeat Stage2Size, i:0
	load Stage2Byte:1 from Stage2Data:i
	Stage2Crc = Stage2Crc xor Stage2Byte
	repeat 8
		if Stage2Crc and 1
			Stage2Crc = (Stage2Crc shr 1) xor 0xEDB88320
		else
			Stage2Crc = Stage2Crc shr 1
		end if
	end repeat
end repeat

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
	; do not check for BIOS extension, let it fail on the read and report 'D'
	inc	byte [UseLBA]

	inc	ax
	mov	cx, Stage2Sectors
	mov	bx, Stage2LoadAddress
	call	ReadSectors

Verify:
	; CRC-32 over exactly Stage2Size bytes, dx:ax is the 32-bit register
	mov	si, Stage2LoadAddress
	mov	cx, Stage2Size
	mov	ax, -1
	mov	dx, ax
.Byte:
	xor	al, [si]
	inc	si
	mov	bl, 8
.Bit:
	shr	dx, 1
	rcr	ax, 1
	jnc	.NoXor
	xor	dx, 0xEDB8
	xor	ax, 0x8320
.NoXor:
	dec	bl
	jnz	.Bit
	loop	.Byte

	xor	ax, Stage2Crc and 0xFFFF
	xor	dx, Stage2Crc shr 16
	or	ax, dx
	mov	al, 'C'
	jnz	Error

Launch:
	mov	dl, [EBR.DriveNumber]
	jmp	0x0000:Stage2LoadAddress

Floppy:
	; calculate the lba of the root directory
	mov	al, [BPB.FatCount]
	mul	word [BPB.SectorsPerFat]
	add	ax, [BPB.ReservedSectors]

	; data lba = root lba + root directory sectors
	mov	cx, [BPB.RootEntries]
	add	cx, 15
	shr	cx, 4
	add	cx, ax
	mov	[DataLBA], cx

	; BOOT.BIN is guaranteed to be entry 0
	inc	cx
	mov	bx, TransitionBuffer
	call	ReadSectors

	; entry 0 must have exactly this build's size
	cmp	word [TransitionBuffer + 28], Stage2Size
	mov	al, 'S'
	jne	Error

	cmp	word [TransitionBuffer + 30], 0
	jne	Error

	push	word [TransitionBuffer + 26]							; first cluster

	; load FAT #0 over the directory sector
	mov	ax, [BPB.ReservedSectors]
	mov	cx, [BPB.SectorsPerFat]
	mov	bx, TransitionBuffer
	call	ReadSectors

	; walk exactly Stage2Sectors clusters
	pop	ax
	mov	bx, Stage2LoadAddress
	mov	bp, Stage2Sectors
.NextCluster:
	push	ax

	; 0x002..0xFEF are data clusters, reject the rest
	dec	ax
	dec	ax
	cmp	ax, 0xFF0 - 2
	jae	.BadChain

	add	ax, [DataLBA]
	mov	cx, 1
	call	ReadSectors

	pop	ax

	; FAT12 entry lives at cluster * 1.5
	mov	si, ax
	shr	si, 1
	add	si, ax
	mov	dx, [si + TransitionBuffer]
	test	al, 1
	jz	.Even

	; entry is the high 12 bits, shift them into the low ones
	shr	dx, 4
.Even:
	and	dx, 0xFFF
	xchg	ax, dx

	dec	bp
	jnz	.NextCluster
	jmp	Verify

.BadChain:
	mov	al, 'F'
	; fall through

; al = error code character
Error:
	mov	[ErrorCode], al
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

	; record the BIOS status as two hex digits for the error message
	mov	di, ErrorStatus
	mov	cx, 2
.Hex:
	rol	ah, 4
	mov	al, ah
	and	al, 0xF
	cmp	al, 10
	sbb	al, 0x69
	das
	stosb
	loop	.Hex

	; DISK - RESET DISK SYSTEM
	; AH = 00h
	; DL = drive (if bit 7 is set both hard disks and floppy disks reset)
	xor	ah, ah
	int	0x13

	popa

	; try again
	dec	di
	jnz	.Retry
	mov	al, 'D'
	jmp	Error

.Ok:
	popa

	inc	ax
	add	bx, 512
	loop	.Next

	ret

ErrorMessage:	db 'Boot error '
ErrorCode:		db '?', ' '
ErrorStatus:	db '--', 13, 10, 0

assert	$ - $$ <= 0x1B8

	db	0x1B8 - ($ - $$) dup 0

DiskSignature:	dd 0
				dw 0
PartitionTable:	db 64 dup 0

	dw	0xAA55
