#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Thumbs\AxThumbs.css, AX_COMPONENTS_THUMBS_AXTHUMBS_CSS

; ============================================================================
;  AxThumbs.ahk -- Thumbnail strip.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxThumbs.ahk     what g.AddThumbs() writes and the markup that becomes
;      AxThumbs.css     its shape -- the theme says what it looks like
;      Thumbs.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxThumbs {
    static _reg := AxRich.Register("Thumbs", "components\Thumbs\AxThumbs.css",
                                   (*) => AxThumbs._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddThumbs", (c, a*) => AxThumbs._Thumbs(c, a*))
        AxTags.Register("ax-thumbs", 37, (el, inner, id) => AxThumbs._Tag("ax-thumbs", el, inner, id))
        return true
    }

    static _Thumbs(c, opts := "", empty := "") {
        o := c._Opt(opts, "th")
        hh := o.H, o.H := ""
        return c._Reg(o, "Thumbs", '<ax-thumbs' c._Common(o, o.W = "" ? "fill" : "")
            . (hh != "" ? ' height="' hh '"' : "") ' empty="' AxTags.E(empty != "" ? empty : "No pictures yet.") '"></ax-thumbs>')
        }

    ; ---- the markup <ax-thumbs> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-thumbs":
            st := (A(el, "height") != "" ? "max-height:" A(el, "height") "px;" : "") E(A(el, "style"))
            return '<div class="thumbs' (A(el, "class") != "" ? " " E(A(el, "class")) : "") '"'
                . (id != "" ? ' id="' E(id) '"' : "") ' data-list="1"' (st != "" ? ' style="' st '"' : "") '>'
                . (inner != "" ? inner : '<div class="fl-empty">' E(A(el, "empty", "No pictures yet.")) '</div>') '</div>'
        }
        return inner
    }
}
