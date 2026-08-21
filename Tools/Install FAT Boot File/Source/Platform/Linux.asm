namespace ELF.Settings
	Class	:= 1
	Type	:= 2
	Machine	:= 3
	ABI	:= 3
	BaseAddress	:= 0x8048000
end namespace

include ELFEXE_INCLUDE

SYS.Exit = 1
SYS.Read = 3
SYS.Write = 4
SYS.Open = 5
SYS.Close = 6
SYS.LSeek = 19
SYS.Brk = 45
SYS.FSync = 118

O.ReadOnly = 0
O.ReadWrite = 2
SEEK.Set = 0
SEEK.End = 2

Platform.HeapGranularity = 0x10000
Platform.StandardError = 2

use32
segment readable writeable

Platform.ArgumentCount dd 0
Platform.ArgumentVector dd 0
Platform.HeapEnd dd 0
Platform.HeapLimit dd 0

segment readable executable

entry Platform.Start
Platform.Start:
	mov	eax, [esp]
	mov	[Platform.ArgumentCount], eax

	lea	eax, [esp + 4]
	mov	[Platform.ArgumentVector], eax

	call	Platform.HeapInitialize
	call	Main

	mov	ebx, eax

; ebx = exit code
Platform.Exit:
	mov	eax, SYS.Exit
	int	0x80

Platform.GetArgumentCount:
	mov	eax, [Platform.ArgumentCount]
	retn

; eax = index
; returns eax = argument or zero
Platform.GetArgument:
	cmp	eax, [Platform.ArgumentCount]
	jae	.OutOfRange

	mov	edx, [Platform.ArgumentVector]
	mov	eax, [edx + eax*dword]
	retn

.OutOfRange:
	xor	eax, eax
	retn

; eax = byte count
; returns eax = allocation or zero
Platform.Allocate:
	push	ebx esi edi

	test	eax, eax
	jz	.Failed

	; align.
	add	eax, 15
	jc	.Failed
	and	eax, -16

	mov	esi, eax
	mov	edi, [Platform.HeapEnd]

	; waay too much allocated.
	add	eax, edi
	jc	.Failed

	; do we need to request more memory from the operating system?
	cmp	eax, [Platform.HeapLimit]
	jbe	.Fits

	; new break.
	lea	ebx, [eax + Platform.HeapGranularity - 1]
	and	ebx, -Platform.HeapGranularity
	push	ebx
	mov	eax, SYS.Brk
	int	0x80
	pop	ebx

	; did we allocate enough?
	cmp	eax, ebx
	jb	.Failed

	mov	[Platform.HeapLimit], eax
.Fits:
	lea	eax, [edi + esi]
	mov	[Platform.HeapEnd], eax
	mov	eax, edi
	jmp	.Done

.Failed:
	xor	eax, eax
.Done:
	pop	edi esi ebx
	retn

Platform.GetHeapMark:
	mov	eax, [Platform.HeapEnd]
	retn

; eax = mark
Platform.ReleaseToMark:
	mov	[Platform.HeapEnd], eax
	retn

; eax = path
; returns handle or negative error
Platform.OpenRead:
	mov	ebx, eax
	mov	ecx, O.ReadOnly
	xor	edx, edx
	mov	eax, SYS.Open
	int	0x80
	retn

; eax = path
; returns handle or negative error
Platform.OpenReadWrite:
	mov	ebx, eax
	mov	ecx, O.ReadWrite
	xor	edx, edx
	mov	eax, SYS.Open
	int	0x80
	retn

; eax = handle
Platform.Close:
	mov	ebx, eax
	mov	eax, SYS.Close
	int	0x80
	retn

; eax = handle
; returns size or negative error
Platform.GetSize:
	push	ebx

	mov	ebx, eax
	xor	ecx, ecx
	mov	edx, SEEK.End
	mov	eax, SYS.LSeek
	int	0x80

	test	eax, eax
	js	.Done

	push	eax
	xor	ecx, ecx
	mov	edx, SEEK.Set
	mov	eax, SYS.LSeek
	int	0x80
	pop	edx

	test	eax, eax
	js	.Done

	mov	eax, edx
.Done:
	pop	ebx
	retn

; eax = handle, ecx = absolute offset
Platform.Seek:
	mov	ebx, eax
	mov	eax, SYS.LSeek
	mov	edx, SEEK.Set
	int	0x80
	retn

; eax = handle, ecx = buffer, edx = byte count
Platform.Read:
	push	ebx esi edi ebp

	mov	ebx, eax
	mov	esi, ecx
	mov	edi, edx
	xor	ebp, ebp
.Next:
	cmp	ebp, edi
	jae	.Complete

	lea	ecx, [esi + ebp]
	mov	edx, edi
	sub	edx, ebp
	mov	eax, SYS.Read
	int	0x80

	test	eax, eax
	js	.Done
	jz	.Complete

	add	ebp, eax
	jmp	.Next

.Complete:
	mov	eax, ebp
.Done:
	pop	ebp edi esi ebx
	retn

; eax = handle, ecx = buffer, edx = byte count
Platform.Write:
	push	ebx esi edi ebp

	mov	ebx, eax
	mov	esi, ecx
	mov	edi, edx
	xor	ebp, ebp
.Next:
	cmp	ebp, edi
	jae	.Complete

	lea	ecx, [esi + ebp]
	mov	edx, edi
	sub	edx, ebp
	mov	eax, SYS.Write
	int	0x80

	test	eax, eax
	js	.Done
	jz	.Complete

	add	ebp, eax
	jmp	.Next

.Complete:
	mov	eax, ebp
.Done:
	pop	ebp edi esi ebx
	retn

; eax = handle
Platform.Flush:
	mov	ebx, eax
	mov	eax, SYS.FSync
	int	0x80
	retn

; eax = buffer, ecx = byte count
Platform.WriteError:
	mov	edx, ecx
	mov	ecx, eax
	mov	ebx, Platform.StandardError
	mov	eax, SYS.Write
	int	0x80
	retn

; eax = path
; returns eax = buffer, edx = size, or zero
Platform.LoadFile:
	push	ebx esi edi

	call	Platform.OpenRead
	test	eax, eax
	js	.Failed

	mov	ebx, eax

	call	Platform.GetSize
	test	eax, eax
	js	.CloseFailed

	mov	edi, eax
	inc	eax

	call	Platform.Allocate
	test	eax, eax
	jz	.CloseFailed

	mov	esi, eax
	mov	edx, edi
	mov	ecx, esi
	mov	eax, ebx

	call	Platform.Read
	cmp	eax, edi
	jne	.CloseFailed

	; null terminate.
	mov	byte [esi + edi], 0
	mov	eax, ebx

	call	Platform.Close
	mov	eax, esi
	mov	edx, edi
	jmp	.Done

.CloseFailed:
	mov	eax, ebx
	call	Platform.Close
.Failed:
	xor	eax, eax
	xor	edx, edx
.Done:
	pop	edi esi ebx
	retn

Platform.HeapInitialize:
	push	ebx

	xor	ebx, ebx
	mov	eax, SYS.Brk
	int	0x80
	mov	[Platform.HeapEnd], eax
	mov	[Platform.HeapLimit], eax

	pop	ebx
	retn
