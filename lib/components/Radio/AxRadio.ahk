#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Radio\AxRadio.css, AX_COMPONENTS_RADIO_AXRADIO_CSS

; ============================================================================
;  AxRadio.ahk -- Radio group.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxRadio.ahk     what g.AddRadio() writes and the markup that becomes
;      AxRadio.css     its shape -- the theme says what it looks like
;      Radio.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxRadio {
    static _reg := AxRich.Register("Radio", "components\Radio\AxRadio.css",
                                   (*) => AxRadio._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddRadio", (c, a*) => AxRadio._Radio(c, a*))
        AxTags.Register("ax-radio", 15, (el, inner, id) => AxRadio._Tag("ax-radio", el, inner, id))
        AxWindow.RegisterBox("radio", "radiogroup")
        return true
    }

    static _Radio(c, opts := "", options := "") {
        o := c._Opt(opts, "rg")
        r := c._Options(o, options, o.Choose)
        ; group=name: radio groups that share a name are one choice, wherever they sit
        grp := c._Kv(o, "group")
        return c._Reg(o, "Radio", '<ax-radio' c._Common(o) ' options="' AxTags.E(r[1]) '" value="' AxTags.E(r[2]) '"'
            . (grp != "" ? ' group="' AxTags.E(grp) '"' : "") (o.Flags.Has("vertical") ? "" : " inline") '></ax-radio>')
        }

    ; ---- the markup <ax-radio> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-radio":
            name := (A(el, "group") != "" ? A(el, "group") : id != "" ? id : "rg" A_TickCount), val := A(el, "value")
            h := '<div' Root(el, "radiogroup" (Has(el, "inline") ? " inline" : ""), true, ' data-role="radiogroup"') '>'
            for o in AxTags.Options(A(el, "options"))
                h .= '<label class="radio" data-role="radio" data-value="' E(o[1]) '"><input type="radio" name="' E(name) '"' (o[1] = val ? " checked" : "") '>'
                   . '<span class="ring"></span><span class="lbl">' E(o[2]) '</span></label>'
            return h '</div>'
        }
        return inner
    }
}
