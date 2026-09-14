#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Svg\AxSvg.css, AX_COMPONENTS_SVG_AXSVG_CSS

; ============================================================================
;  AxSvg.ahk -- Inline SVG.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxSvg.ahk     what g.AddSvg() writes
;      AxSvg.css     its shape -- the theme says what it looks like
;      Svg.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxSvg {
    static _reg := AxRich.Register("Svg", "components\Svg\AxSvg.css",
                                   (*) => AxSvg._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddSvg", (c, a*) => AxSvg._Svg(c, a*))
        return true
    }

    static _Svg(c, opts := "", markup := "") {
        o := c._Opt(opts, "svg")
        return c._Reg(o, "Svg", '<div' c._Common(o, "ax-svg") '>' markup '</div>')
        }
}
