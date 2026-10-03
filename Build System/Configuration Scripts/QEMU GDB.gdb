set osabi none
set disassembly-flavor intel
set disassemble-next-line off
set pagination off
set confirm off
set breakpoint pending on
set print pretty on
set style enabled on
set style disassembler enabled on

define hook-stop
  x/i $cs*16 + $eip
end

define nint
  tbreak *($pc + 2)
  continue
end
document nint
Step over an INT instruction instead of descending into the BIOS.
end

define lst
  eval "shell \"%s\" %016X \"%s\"/*.lst", $lstscript, $cs*16 + $eip, $listings
end
document lst
Show the fasmg listing lines around the current instruction.
end

define stk
  x/8xh (unsigned int)$ss*16 + ((unsigned int)$esp & 0xffff)
end

define xso
  if $argc != 2
    echo usage: xso <segment> <offset>\n
  else
    x/16xb ($arg0)*16 + ($arg1)
  end
end
