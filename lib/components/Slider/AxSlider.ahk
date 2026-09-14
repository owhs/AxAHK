#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Slider\AxSlider.css, AX_COMPONENTS_SLIDER_AXSLIDER_CSS

; ============================================================================
;  AxSlider.ahk -- Slider.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxSlider.ahk     what g.AddSlider() writes and the markup that becomes
;      AxSlider.css     its shape -- the theme says what it looks like
;      Slider.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxSlider {
    static _reg := AxRich.Register("Slider", "components\Slider\AxSlider.css",
                                   (*) => AxSlider._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddSlider", (c, a*) => AxSlider._Slider(c, a*))
        AxTags.Register("ax-slider", 22, (el, inner, id) => AxSlider._Tag("ax-slider", el, inner, id))
        AxWindow.RegisterBox("slider")
        return true
    }

    static _Slider(c, opts := "", value := 0) {
        o := c._Opt(opts, "sl")
        return c._Reg(o, "Slider", '<ax-slider' c._Common(o) ' value="' value '" min="' c._Kv(o, "min", 0) '" max="' c._Kv(o, "max", 100) '" step="' c._Kv(o, "step", 1) '"'
            . ' suffix="' AxTags.E(c._Kv(o, "suffix")) '"' (o.Flags.Has("novalue") ? " novalue" : "") '></ax-slider>')
        }

    ; ---- the markup <ax-slider> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-slider":
            outId := A(el, "out", id != "" ? id "_out" : "")
            showOut := !Has(el, "novalue")
            return '<div' Root(el, "slider", true, ' data-role="slider"' (outId != "" ? ' data-out="' E(outId) '"' : "") ' data-suffix="' E(A(el, "suffix")) '"') '>'
                . '<input type="range" min="' E(A(el, "min", "0")) '" max="' E(A(el, "max", "100")) '" step="' E(A(el, "step", "1")) '" value="' E(A(el, "value", "0")) '">'
                . (showOut && outId != "" ? '<span class="out" id="' E(outId) '">' E(A(el, "value", "0")) E(A(el, "suffix")) '</span>' : "") '</div>'
        }
        return inner
    }
}
