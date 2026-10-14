macro bits? n*
end macro

macro global? line&
end macro

macro extern? sym*
end macro

__dcc_i8086_model_unreal := 0

macro section? line&
    match pre =align==n, line
        if n > 1
            db (-$) and (n - 1) dup 0
        end if
    end match
end macro

macro align? boundary*, fill:0
    match =db? val, fill
        db (-$) and (boundary - 1) dup (val)
    else
        db (-$) and (boundary - 1) dup (fill)
    end match
end macro

macro a32? insn&
    db 67h
    insn
end macro

macro o32? insn&
    db 66h
    insn
end macro
