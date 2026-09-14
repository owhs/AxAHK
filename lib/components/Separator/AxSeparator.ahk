#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; ============================================================================
;  AxSeparator.ahk -- Separator.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxSeparator.ahk     what g.AddSeparator() writes
;      Separator.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxSeparator {
    static _reg := AxRich.Register("Separator", "",
                                   (*) => AxSeparator._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddSeparator", (c, a*) => AxSeparator._Separator(c, a*))
        return true
    }

    static _Separator(c, opts := "") {
        o := c._Opt(opts, "sep")
        return c._Reg(o, "Separator", '<div' c._Common(o, "ax-sep fill") '></div>')
        }
}
