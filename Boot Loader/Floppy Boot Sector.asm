use16
org 0x7C00

	jmp	short Start
	nop
	db	'CORE5   '

	db	62 - ($ - $$) dup 0

Start:
	cli
.Halt:
	hlt
	jmp	.Halt

	db	510 - ($ - $$) dup 0
	dw	0xAA55
