segment readable writeable

Arguments.Image db '-Image', 0
Arguments.Source db '-Source', 0
Arguments.ImagePath dd 0
Arguments.SourcePath dd 0

segment readable executable

; returns eax = zero on success
Arguments.Parse:
	cmp	dword [Platform.ArgumentCount], 5
	jne	.Failed

	; iterate the four arguments
	mov	esi, 1
.Next:
	cmp	esi, 5
	jae	.Done

	; check for -Image
	mov	eax, esi
	call	Platform.GetArgument
	mov	ebx, eax
	mov	edx, Arguments.Image
	call	String.Equals
	je	.Image

	; check for -Source
	mov	eax, ebx
	mov	edx, Arguments.Source
	call	String.Equals
	je	.Source

	jmp	.Failed

.Image:
	; duplicates?
	cmp	dword [Arguments.ImagePath], 0
	jne	.Failed

	; save the value of the flag
	mov	eax, esi
	inc	eax
	call	Platform.GetArgument
	mov	[Arguments.ImagePath], eax
	jmp	.Advance

.Source:
	; duplicates?
	cmp	dword [Arguments.SourcePath], 0
	jne	.Failed

	; save the value of the flag
	mov	eax, esi
	inc	eax
	call	Platform.GetArgument
	mov	[Arguments.SourcePath], eax
.Advance:
	add	esi, 2
	jmp	.Next

.Done:
	cmp	dword [Arguments.ImagePath], 0
	je	.Failed

	cmp	dword [Arguments.SourcePath], 0
	je	.Failed

	xor	eax, eax
	retn

.Failed:
	mov	eax, 1
	retn
