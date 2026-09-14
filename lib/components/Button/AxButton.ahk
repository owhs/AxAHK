#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; ============================================================================
;  AxButton.ahk -- Button.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxButton.ahk     what g.AddButton() writes and the markup that becomes
;      Button.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxButton {
    static _reg := AxRich.Register("Button", "",
                                   (*) => AxButton._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddButton", (c, a*) => AxButton._Button(c, a*))
        AxTags.Register("ax-button", 11, (el, inner, id) => AxButton._Tag("ax-button", el, inner, id))
        return true
    }

    static _Button(c, opts := "", text := "") {
        o := c._Opt(opts, "btn")
        kind := c._Kv(o, "kind")
        for k in ["accent", "subtle", "danger", "icon"]
            if o.Flags.Has(k)
                kind := k
        return c._Reg(o, "Button", '<ax-button' c._Common(o) (kind != "" ? ' kind="' kind '"' : "") (o.KV.Has("icon") ? ' icon="' o.KV["icon"] '"' : "")
            . (o.Flags.Has("disabled") ? " disabled" : "") '>' AxTags.E(text) '</ax-button>')
        }

    ; ---- the markup <ax-button> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-button":
            kind := A(el, "kind")
            ; icon-only buttons carry the glyph as their own text (no inner
            ; span) so it centres exactly like a text label
            if (kind = "icon" && A(el, "icon") != "" && inner = "")
                return '<span' Root(el, "btn icon" (Has(el, "disabled") ? " disabled" : "")) '>&#x' A(el, "icon") ';</span>'
            return '<span' Root(el, "btn" (kind != "" ? " " kind : "") (Has(el, "disabled") ? " disabled" : "")) '>'
                . Ico(A(el, "icon")) (A(el, "icon") != "" && inner != "" ? " " : "") inner '</span>'
        }
        return inner
    }
}
