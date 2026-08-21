if HOST_LINUX = 1
	include	'Platform/Linux.asm'
else if HOST_CORE5 = 1
	include	'Platform/Core5.asm'
end if

include 'String.asm'
include 'Arguments.asm'
include 'FAT12.asm'

segment readable writeable

Main.Usage db 'Usage: Install FAT Boot File -Image <image> -Source <binary>', 10
Main.Usage.Length = $ - Main.Usage

Main.SourceError db 'Install FAT Boot File: cannot read source file', 10
Main.SourceError.Length = $ - Main.SourceError

Main.ImageError db 'Install FAT Boot File: cannot read or write image', 10
Main.ImageError.Length = $ - Main.ImageError

Main.FormatError db 'Install FAT Boot File: unsupported or invalid filesystem', 10
Main.FormatError.Length = $ - Main.FormatError

Main.SpaceError db 'Install FAT Boot File: FAT12 image has insufficient space', 10
Main.SpaceError.Length = $ - Main.SpaceError

Main.SourceBuffer dd 0
Main.SourceSize dd 0
Main.ImageBuffer dd 0
Main.ImageSize dd 0

segment readable executable

Main:
	call	Arguments.Parse
	test	eax, eax
	jnz	.ReportUsage

	mov	eax, [Arguments.SourcePath]
	call	Platform.LoadFile
	test	eax, eax
	jz	.ReportSourceError

	mov	[Main.SourceBuffer], eax
	mov	[Main.SourceSize], edx

	mov	eax, [Arguments.ImagePath]
	call	Platform.LoadFile
	test	eax, eax
	jz	.ReportImageError

	mov	[Main.ImageBuffer], eax
	mov	[Main.ImageSize], edx

	mov	ecx, [Main.SourceBuffer]
	mov	ebx, [Main.SourceSize]
	mov	esi, [Arguments.SourcePath]
	call	FAT12.Install
	test	eax, eax
	jz	.WriteImage

	cmp	eax, FAT12.Error.Invalid
	je	.ReportFormatError
	jmp	.ReportSpaceError

.WriteImage:
	mov	eax, [Arguments.ImagePath]
	call	Platform.OpenReadWrite
	test	eax, eax
	js	.ReportImageError

	mov	edi, eax
	mov	ecx, [Main.ImageBuffer]
	mov	edx, [Main.ImageSize]
	call	Platform.Write
	cmp	eax, [Main.ImageSize]
	jne	.CloseImageError

	mov	eax, edi
	call	Platform.Flush
	test	eax, eax
	js	.CloseImageError

	mov	eax, edi
	call	Platform.Close
	xor	eax, eax
	retn

.CloseImageError:
	mov	eax, edi
	call	Platform.Close
.ReportImageError:
	mov	eax, Main.ImageError
	mov	ecx, Main.ImageError.Length
	jmp	.Report

.ReportSourceError:
	mov	eax, Main.SourceError
	mov	ecx, Main.SourceError.Length
	jmp	.Report

.ReportFormatError:
	mov	eax, Main.FormatError
	mov	ecx, Main.FormatError.Length
	jmp	.Report

.ReportSpaceError:
	mov	eax, Main.SpaceError
	mov	ecx, Main.SpaceError.Length
	jmp	.Report

.ReportUsage:
	mov	eax, Main.Usage
	mov	ecx, Main.Usage.Length
.Report:
	call	Platform.WriteError
	mov	eax, 1
	retn
