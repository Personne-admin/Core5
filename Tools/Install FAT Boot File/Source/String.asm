; eax = first string, edx = second string
; returns ZF set when equal
String.Equals:
	push	eax edx
.Next:
	mov	cl, [eax]
	cmp	cl, [edx]
	jne	.Done

	inc	eax
	inc	edx

	test	cl, cl
	jnz	.Next
.Done:
	pop	edx eax
	retn
