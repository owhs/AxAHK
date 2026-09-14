#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\CheckBox\AxCheckBox.css, AX_COMPONENTS_CHECKBOX_AXCHECKBOX_CSS

; ============================================================================
;  AxCheckBox.ahk -- Check box.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxCheckBox.ahk     what g.AddCheckBox() writes and the markup that becomes
;      AxCheckBox.css     its shape -- the theme says what it looks like
;      CheckBox.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxCheckBox {
    static _reg := AxRich.Register("CheckBox", "components\CheckBox\AxCheckBox.css",
                                   (*) => AxCheckBox._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddCheckBox", (c, a*) => AxCheckBox._CheckBox(c, a*))
        AxTags.Register("ax-check", 14, (el, inner, id) => AxCheckBox._Tag("ax-check", el, inner, id))
        AxWindow.RegisterBox("check")
        return true
    }

    static _CheckBox(c, opts := "", text := "") {
        o := c._Opt(opts, "chk")
        return c._Reg(o, "CheckBox", '<ax-check' c._Common(o) (o.Flags.Has("checked") ? " checked" : "") '>' AxTags.E(text) '</ax-check>')
        }

    ; ---- the markup <ax-check> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-check":
            return '<label' Root(el, "check", true, ' data-role="check"') '><input type="checkbox"' (Has(el, "checked") ? " checked" : "") '>'
                . '<span class="box"></span>' (inner != "" ? '<span class="lbl">' inner '</span>' : "") '</label>'
        }
        return inner
    }
}
