#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; ============================================================================
;  AxCard.ahk -- Card.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxCard.ahk     what g.AddCard() writes and the markup that becomes
;      Card.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxCard {
    static _reg := AxRich.Register("Card", "",
                                   (*) => AxCard._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddCard", (c, a*) => AxCard._Card(c, a*))
        AxTags.Register("ax-card", 5, (el, inner, id) => AxCard._Tag("ax-card", el, inner, id))
        return true
    }

    static _Card(c, opts := "", title := "") {
        o := c._Opt(opts, "card")
        return c._Sub(o, "Card", '<ax-card' c._Common(o) (title != "" ? ' title="' AxTags.E(title) '"' : "") '>{inner}</ax-card>')
        }

    ; ---- the markup <ax-card> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-card":
            return '<div' Root(el, "card") '>' (A(el, "title") != "" ? '<h3 style="margin-top:0">' E(A(el, "title")) '</h3>' : "") inner '</div>'
        }
        return inner
    }
}
