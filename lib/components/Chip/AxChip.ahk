#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Chip\AxChip.css, AX_COMPONENTS_CHIP_AXCHIP_CSS

; ============================================================================
;  AxChip.ahk -- Chip.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxChip.ahk     what g.AddChip() writes and the markup that becomes
;      AxChip.css     its shape -- the theme says what it looks like
;      Chip.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxChip {
    static _reg := AxRich.Register("Chip", "components\Chip\AxChip.css",
                                   (*) => AxChip._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddChip", (c, a*) => AxChip._Chip(c, a*))
        AxTags.Register("ax-chip", 28, (el, inner, id) => AxChip._Tag("ax-chip", el, inner, id))
        return true
    }

    static _Chip(c, opts := "", text := "") {
        o := c._Opt(opts, "chip")
        return c._Reg(o, "Chip", '<ax-chip' c._Common(o) (o.Flags.Has("on") || o.Flags.Has("checked") ? " on" : "") '>' AxTags.E(text) '</ax-chip>')
        }

    ; ---- the markup <ax-chip> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-chip":
            return '<span' Root(el, "chip" (Has(el, "on") ? " on" : "")) '>' inner '</span>'
        }
        return inner
    }
}
