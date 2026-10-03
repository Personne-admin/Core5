CheckCpu:
	pushf
	pop	ax
	mov	cx, ax

	; 8086/80186: flags bits 12..15 always read as set
	and	ax, 0x0FFF
	push	ax
	popf

	pushf
	pop	ax

	and	ax, 0xF000
	cmp	ax, 0xF000
	je	.Old

	; 80286 in real mode: flags bits 12..15 always read as clear
	mov	ax, cx
	or	ax, 0xF000

	push	ax
	popf

	pushf
	pop	ax

	; restore the original flags
	push	cx
	popf

	test	ax, 0xF000
	jz	.Old
	ret

.Old:
	mov	si, Message.Not386
	jmp	Fatal

EnableA20:
	call	A20.Check
	jnz	.Done

	; SYSTEM - later PS/2s - ENABLE A20 GATE
	; AX = 2401h
	mov	ax, 0x2401
	int	0x15
	call	A20.Check
	jnz	.Done

	call	A20.Fast
	call	A20.CheckSlow
	jnz	.Done

	call	A20.Keyboard
	call	A20.CheckSlow
	jnz	.Done

	mov	si, Message.NoA20
	jmp	Fatal

.Done:
	ret

; returns ZF clear if A20 is enabled
A20.Check:
	push	ds es si di

	xor	ax, ax
	mov	ds, ax

	not	ax
	mov	es, ax

	mov	si, 0x7DFE
	mov	di, 0x7E0E

	; save both bytes
	mov	al, [es:di]
	push	ax
	mov	al, [ds:si]
	push	ax

	; if the write to the low address shows up high, the addresses wrap
	mov	byte [es:di], 0x00
	mov	byte [ds:si], 0xFF
	cmp	byte [es:di], 0xFF

	; restore the bytes
	pop	ax
	mov	[ds:si], al
	pop	ax
	mov	[es:di], al

	pop	di si es ds
	ret

; some chipsets take a moment to switch the gate
A20.CheckSlow:
	mov	cx, 0x1000
.Again:
	call	A20.Check
	jnz	.Done
	loop	.Again
.Done:
	ret

; try enable A20 through the output port of the 8042 keyboard controller
A20.Keyboard:
	call	A20.WaitInput
	mov	al, 0xAD											; disable the keyboard
	out	0x64, al

	call	A20.WaitInput
	mov	al, 0xD0											; read the output port
	out	0x64, al

	call	A20.WaitOutput
	in	al, 0x60
	push	ax

	call	A20.WaitInput
	mov	al, 0xD1											; write the output port
	out	0x64, al

	call	A20.WaitInput
	pop	ax
	or	al, 3
	out	0x60, al

	call	A20.WaitInput
	mov	al, 0xAE											; enable the keyboard
	out	0x64, al

	call	A20.WaitInput
	ret

; the timeouts keep machines without an 8042 from hanging
A20.WaitInput:
	mov	cx, 0xFFFF
.Poll:
	in	al, 0x64
	test	al, 2
	jz	.Done
	loop	.Poll
.Done:
	ret

A20.WaitOutput:
	mov	cx, 0xFFFF
.Poll:
	in	al, 0x64
	test	al, 1
	jnz	.Done
	loop	.Poll
.Done:
	ret

; try enable A20 through system control port A
A20.Fast:
	in	al, 0x92
	test	al, 2
	jnz	.Done

	or	al, 2
	and	al, 0xFE											; bit 0 is a fast reset
	out	0x92, al
.Done:
	ret
