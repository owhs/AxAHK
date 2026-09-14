#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Progress\AxProgress.css, AX_COMPONENTS_PROGRESS_AXPROGRESS_CSS

; ============================================================================
;  AxProgress.ahk -- Progress bar.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxProgress.ahk     what g.AddProgress() writes and the markup that becomes
;      AxProgress.css     its shape -- the theme says what it looks like
;      Progress.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxProgress {
    static _reg := AxRich.Register("Progress", "components\Progress\AxProgress.css",
                                   (*) => AxProgress._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddProgress", (c, a*) => AxProgress._Progress(c, a*))
        AxTags.Register("ax-progress", 25, (el, inner, id) => AxProgress._Tag("ax-progress", el, inner, id))
        return true
    }

    static _Progress(c, opts := "", value := 0) {
        o := c._Opt(opts, "pb")
        return c._Reg(o, "Progress", '<ax-progress' c._Common(o, o.W = "" ? "fill" : "") ' value="' value '"' (o.Flags.Has("indeterminate") ? " indeterminate" : "") '></ax-progress>')
        }

    ; ---- the markup <ax-progress> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-progress":
            return '<div' Root(el, "progress" (Has(el, "indeterminate") ? " indeterminate" : "")) '><div class="bar"' (id != "" ? ' id="' E(id) '_bar"' : "") ' style="width:' E(A(el, "value", "0")) '%"></div></div>'
        }
        return inner
    }
}
