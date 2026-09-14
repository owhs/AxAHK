#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Row\AxRow.css, AX_COMPONENTS_ROW_AXROW_CSS

; ============================================================================
;  AxRow.ahk -- Setting row.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxRow.ahk     what g.AddRow() writes and the markup that becomes
;      AxRow.css     its shape -- the theme says what it looks like
;      Row.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxRow {
    static _reg := AxRich.Register("Row", "components\Row\AxRow.css",
                                   (*) => AxRow._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddRow", (c, a*) => AxRow._Row(c, a*))
        AxTags.Register("ax-row", 4, (el, inner, id) => AxRow._Tag("ax-row", el, inner, id))
        return true
    }

    static _Row(c, opts := "", title := "", desc := "") {
        o := c._Opt(opts, "row")
        ; Desc="..." as well as the third argument: the studio writes the
        ; option, and it used to be dropped, so every row lost its second line
        if (desc = "" && o.KV.Has("desc"))
            desc := o.KV["desc"]
        return c._Sub(o, "Row", '<ax-row' c._Common(o) ' title="' AxTags.E(title) '" desc="' AxTags.E(desc) '"' (o.KV.Has("icon") ? ' icon="' o.KV["icon"] '"' : "") (o.Flags.Has("nocard") ? " nocard" : "") '>{inner}</ax-row>')
        }

    ; ---- the markup <ax-row> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-row":
            row := '<div class="card-row">' Ico(A(el, "icon"))
                . '<div class="text"><div class="title">' E(A(el, "title")) '</div>'
                . (A(el, "desc") != "" ? '<div class="desc">' E(A(el, "desc")) '</div>' : "") '</div>'
                . '<div class="ctl">' inner '</div></div>'
            return Has(el, "nocard") ? row : '<div' Root(el, "card") '>' row '</div>'
        }
        return inner
    }
}
