EnterUnreal:
	push	ds es
	cli

	; load the unreal gdt
	lgdt	[Gdt.Pointer]

	; enter protected mode
	mov	eax, cr0
	or	al, 1
	mov	cr0, eax
	jmp	$ + 2											; flush the prefetch queue pipeline

	; all flat segments
	mov	bx, Gdt.FlatData
	mov	ds, bx
	mov	es, bx
	mov	fs, bx
	mov	gs, bx

	; drop back into real address mode
	and	al, 0xFE
	mov	cr0, eax
	jmp	$ + 2											; flush the prefetch queue pipeline

	; reload real mode values, does not change the descriptor cache
	xor	bx, bx
	mov	fs, bx
	mov	gs, bx
	pop	es ds

	sti
	ret

Gdt:
	dq	0
Gdt.FlatData = $ - Gdt
	dw	0xFFFF, 0x0000
	db	0x00, 10010010b, 10001111b, 0x00
Gdt.Size = $ - Gdt

Gdt.Pointer:
	dw	Gdt.Size - 1
	dd	Gdt
