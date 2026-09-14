#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; ============================================================================
;  AxLink.ahk -- Link.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxLink.ahk     what g.AddLink() writes and the markup that becomes
;      Link.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxLink {
    static _reg := AxRich.Register("Link", "",
                                   (*) => AxLink._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddLink", (c, a*) => AxLink._Link(c, a*))
        AxTags.Register("ax-link", 12, (el, inner, id) => AxLink._Tag("ax-link", el, inner, id))
        return true
    }

    static _Link(c, opts := "", text := "") {
        o := c._Opt(opts, "lnk")
        return c._Reg(o, "Link", '<ax-link' c._Common(o) '>' AxTags.E(text) '</ax-link>')
        }

    ; ---- the markup <ax-link> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-link":
            return '<span' Root(el, "link") '>' inner '</span>'
        }
        return inner
    }
}
