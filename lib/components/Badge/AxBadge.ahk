#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Badge\AxBadge.css, AX_COMPONENTS_BADGE_AXBADGE_CSS

; ============================================================================
;  AxBadge.ahk -- Badge.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxBadge.ahk     what g.AddBadge() writes and the markup that becomes
;      AxBadge.css     its shape -- the theme says what it looks like
;      Badge.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxBadge {
    static _reg := AxRich.Register("Badge", "components\Badge\AxBadge.css",
                                   (*) => AxBadge._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddBadge", (c, a*) => AxBadge._Badge(c, a*))
        AxTags.Register("ax-badge", 27, (el, inner, id) => AxBadge._Tag("ax-badge", el, inner, id))
        return true
    }

    static _Badge(c, opts := "", text := "") {
        o := c._Opt(opts, "bd")
        return c._Reg(o, "Badge", '<ax-badge' c._Common(o) ' kind="' c._Kv(o, "kind") '">' AxTags.E(text) '</ax-badge>')
        }

    ; ---- the markup <ax-badge> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-badge":
            return '<span' Root(el, "badge" (A(el, "kind") != "" ? " " A(el, "kind") : "")) '>' inner '</span>'
        }
        return inner
    }
}
