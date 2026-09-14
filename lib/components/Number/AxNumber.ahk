#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Number\AxNumber.css, AX_COMPONENTS_NUMBER_AXNUMBER_CSS

; ============================================================================
;  AxNumber.ahk -- Number box.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxNumber.ahk     what g.AddNumber() writes, the markup that becomes and
;                       what a click on it does
;      AxNumber.css     its shape -- the theme says what it looks like
;      Number.axc.json  what the studio puts in the toolbox
;
;      g.AddNumber("vVol Min=0 Max=100 Step=5 BigStep=25 SmallStep=1", 50)
;
;  Up and Down (and the spin buttons) move it a Step; with Shift, a BigStep,
;  and with Ctrl, a SmallStep. Either left out, that key moves it a Step.
; ============================================================================

class AxNumber {
    static _reg := AxRich.Register("Number", "components\Number\AxNumber.css",
                                   (*) => AxNumber._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddNumber", (c, a*) => AxNumber._Number(c, a*))
        AxTags.Register("ax-number", 21, (el, inner, id) => AxNumber._Tag("ax-number", el, inner, id))
        AxWindow.RegisterClick("spin-up", (w, el, t, ev) => AxNumber._Click("spin-up", w, el, t, ev))
        AxWindow.RegisterClick("spin-down", (w, el, t, ev) => AxNumber._Click("spin-down", w, el, t, ev))
        AxWindow.RegisterBox("numberbox")
        return true
    }

    static _Number(c, opts := "", value := 0) {
        o := c._Opt(opts, "num")
        return c._Reg(o, "Number", '<ax-number' c._Common(o) ' value="' value '" min="' c._Kv(o, "min") '" max="' c._Kv(o, "max") '" step="' c._Kv(o, "step", 1) '"'
            . ' bigstep="' AxTags.E(c._Kv(o, "bigstep")) '" smallstep="' AxTags.E(c._Kv(o, "smallstep")) '"'
            . (o.KV.Has("out") ? ' out="' o.KV["out"] '"' : "") ' suffix="' AxTags.E(c._Kv(o, "suffix")) '"></ax-number>')
        }

    ; ---- the markup <ax-number> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-number":
            out := A(el, "out")
            h := '<div' Root(el, "numberbox", true, ' data-role="numberbox"' (out != "" ? ' data-out="' E(out) '"' : "") (A(el, "suffix") != "" ? ' data-suffix="' E(A(el, "suffix")) '"' : "")) '>'
                . '<input type="text" value="' E(A(el, "value", "0")) '" data-min="' E(A(el, "min")) '" data-max="' E(A(el, "max")) '" data-step="' E(A(el, "step", "1")) '"'
                . (A(el, "bigstep") != "" ? ' data-bigstep="' E(A(el, "bigstep")) '"' : "")
                . (A(el, "smallstep") != "" ? ' data-smallstep="' E(A(el, "smallstep")) '"' : "") '>'
                . '<div class="spin up" data-role="spin-up"></div><div class="spin down" data-role="spin-down"></div></div>'
            return h
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "spin-up", "spin-down":
            nb := win._RoleAncestor(t, "numberbox")
            if !nb
                return
            win._NumberStep(nb, role = "spin-up" ? 1 : -1, ev)      ; Shift / Ctrl work here too
        }
    }
}
