#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; ============================================================================
;  AxHtml.ahk -- Raw HTML.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxHtml.ahk     what g.AddHtml() writes
;      Html.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxHtml {
    static _reg := AxRich.Register("Html", "",
                                   (*) => AxHtml._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddHtml", (c, a*) => AxHtml._Html(c, a*))
        return true
    }

    static _Html(c, opts := "", html := "") {
        o := c._Opt(opts, "html")
        return c._Reg(o, "Html", '<div' c._Common(o) '>' html '</div>')
        }
}
