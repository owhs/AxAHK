#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\GroupBox\AxGroupBox.css, AX_COMPONENTS_GROUPBOX_AXGROUPBOX_CSS

; ============================================================================
;  AxGroupBox.ahk -- Group box.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxGroupBox.ahk     what g.AddGroupBox() writes and the markup that becomes
;      AxGroupBox.css     the legend's place in the frame, on every theme
;      GroupBox.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxGroupBox {
    static _reg := AxRich.Register("GroupBox", "components\GroupBox\AxGroupBox.css",
                                   (*) => AxGroupBox._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddGroupBox", (c, a*) => AxGroupBox._GroupBox(c, a*))
        AxTags.Register("ax-group", 6, (el, inner, id) => AxGroupBox._Tag("ax-group", el, inner, id))
        return true
    }

    static _GroupBox(c, opts := "", legend := "") {
        o := c._Opt(opts, "grp")
        return c._Sub(o, "GroupBox", '<ax-group' c._Common(o) ' legend="' AxTags.E(legend) '">{inner}</ax-group>')
        }

    ; ---- the markup <ax-group> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-group":
            ; a real fieldset: the browser cuts the frame for the legend over
            ; whatever is behind it, so no theme has to paint a patch to match
            return '<fieldset' Root(el, "group") '><legend class="legend">' E(A(el, "legend")) '</legend>' inner '</fieldset>'
        }
        return inner
    }
}
