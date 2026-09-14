#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; ============================================================================
;  AxText.ahk -- Label.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxText.ahk     what g.AddText() writes
;      Text.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxText {
    static _reg := AxRich.Register("Text", "",
                                   (*) => AxText._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddText", (c, a*) => AxText._Text(c, a*))
        return true
    }

    static _Text(c, opts := "", text := "") {
        o := c._Opt(opts, "txt")
        cls := "ax-text" (o.Flags.Has("right") ? " right" : "") (o.Flags.Has("center") ? " center" : "") (o.Flags.Has("caption") ? " caption" : "") (o.Flags.Has("hint") ? " hint" : "")
        return c._Reg(o, "Text", '<div' c._Common(o, cls) '>' AxTags.E(text) '</div>')
        }
}
