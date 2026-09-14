#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; ============================================================================
;  AxSearch.ahk -- Search box.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxSearch.ahk     what g.AddSearch() writes and the markup that becomes
;      Search.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxSearch {
    static _reg := AxRich.Register("Search", "",
                                   (*) => AxSearch._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddSearch", (c, a*) => AxSearch._Search(c, a*))
        AxTags.Register("ax-search", 19, (el, inner, id) => AxSearch._Tag("ax-search", el, inner, id))
        return true
    }

    static _Search(c, opts := "", text := "") {
        o := c._Opt(opts, "q")
        return c._Reg(o, "Search", '<ax-search' c._Common(o) ' value="' AxTags.E(text) '" placeholder="' AxTags.E(c._Kv(o, "placeholder", "Search")) '"></ax-search>')
        }

    ; ---- the markup <ax-search> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-search":
            return '<div' Root(el, "searchbox", false) '><input type="text"' (id != "" ? ' id="' E(id) '"' : "") ' value="' E(A(el, "value")) '"'
                . ' placeholder="' E(A(el, "placeholder", "Search")) '"><span class="ico">&#xE721;</span></div>'
        }
        return inner
    }
}
