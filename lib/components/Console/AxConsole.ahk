#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Console\AxConsole.css, AX_COMPONENTS_CONSOLE_AXCONSOLE_CSS

; ============================================================================
;  AxConsole.ahk -- Log box.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxConsole.ahk     what g.AddConsole() writes and the markup that becomes
;      AxConsole.css     its shape -- the theme says what it looks like
;      Console.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxConsole {
    static _reg := AxRich.Register("Console", "components\Console\AxConsole.css",
                                   (*) => AxConsole._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddConsole", (c, a*) => AxConsole._Console(c, a*))
        AxTags.Register("ax-console", 33, (el, inner, id) => AxConsole._Tag("ax-console", el, inner, id))
        return true
    }

    static _Console(c, opts := "") {
        o := c._Opt(opts, "con")
        return c._Reg(o, "Console", '<ax-console' c._Common(o, "fill") '></ax-console>')
        }

    ; ---- the markup <ax-console> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-console":
            return '<div' Root(el, "console", true, ' data-selectable="1"') '>' inner '</div>'
        ; ----------------------------------------------------------- media
        }
        return inner
    }
}
