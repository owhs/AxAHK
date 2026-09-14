#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Switch\AxSwitch.css, AX_COMPONENTS_SWITCH_AXSWITCH_CSS

; ============================================================================
;  AxSwitch.ahk -- Switch.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxSwitch.ahk     what g.AddSwitch() writes and the markup that becomes
;      AxSwitch.css     its shape -- the theme says what it looks like
;      Switch.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxSwitch {
    static _reg := AxRich.Register("Switch", "components\Switch\AxSwitch.css",
                                   (*) => AxSwitch._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddSwitch", (c, a*) => AxSwitch._Switch(c, a*))
        AxTags.Register("ax-switch", 13, (el, inner, id) => AxSwitch._Tag("ax-switch", el, inner, id))
        AxWindow.RegisterBox("switch")
        return true
    }

    static _Switch(c, opts := "", text := "") {
        o := c._Opt(opts, "sw")
        on := c._Kv(o, "on", text != "" ? text : "On"), off := c._Kv(o, "off", text != "" ? text : "Off")
        return c._Reg(o, "Switch", '<ax-switch' c._Common(o) ' on="' AxTags.E(on) '" off="' AxTags.E(off) '"' (o.Flags.Has("checked") ? " checked" : "") (o.Flags.Has("nolabel") ? " nolabel" : "") '></ax-switch>')
        }

    ; ---- the markup <ax-switch> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-switch":
            on := A(el, "on", "On"), off := A(el, "off", "Off"), chk := Has(el, "checked")
            return '<label' Root(el, "switch", true, ' data-role="switch" data-on="' E(on) '" data-off="' E(off) '"') '>'
                . '<input type="checkbox"' (chk ? " checked" : "") '><span class="sw-track"></span>'
                . (Has(el, "nolabel") ? "" : '<span class="sw-label">' E(chk ? on : off) '</span>') '</label>'
        }
        return inner
    }
}
