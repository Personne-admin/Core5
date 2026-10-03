use16
org 0x500

StackTop	= 0x7C00
StackSize	= 0x400

Stage2.Start:
	xor	ax, ax
	mov	ds, ax
	mov	es, ax
	mov	ss, ax
	mov	sp, StackTop
	sti
	cld

	mov	[BootInfo.Drive], dl

	; VIDEO - SET VIDEO MODE
	; AH = 00h
	; AL = desired video mode (see #00010)
	mov ax, 0x3
	int 0x10

	mov	si, Message.Banner
	call	Print

	call	CheckCpu
	call	EnableA20
	call	EnterUnreal

	mov	si, Message.Ready
	call	Print

	cli
.Halt:
	hlt
	jmp	.Halt

include 'Unreal.asm'
include 'Cpu.asm'

; si = zero terminated string
Print:
	lodsb
	test	al, al
	jz	.Done

	; VIDEO - TELETYPE OUTPUT
	; AH = 0Eh
	; AL = character to write
	; BH = page number
	; BL = foreground color (graphics modes only)
	mov	ah, 0xE
	mov	bx, 0x7
	int	0x10
	jmp	Print

.Done:
	ret

; si = message
Fatal:
	call	Print
	mov	si, Message.PressKey
	call	Print

	; KEYBOARD - GET KEYSTROKE
	; AH = 00h
	xor	ah, ah
	int	0x16
	; SYSTEM - BOOTSTRAP LOADER
	int	0x19

Message.Banner		db 'Core5 stage 2 loader', 13, 10, 0
Message.Ready		db '!', 13, 10, 0
Message.Not386		db 'Boot error: a 386 or newer is required', 13, 10, 0
Message.NoA20		db 'Boot error: cannot enable the A20 line', 13, 10, 0
Message.PressKey	db 'Press any key to reboot', 13, 10, 0

BootInfo.Drive		db ?

assert	$ <= StackTop - StackSize
