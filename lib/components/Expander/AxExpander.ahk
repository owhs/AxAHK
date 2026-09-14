#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Expander\AxExpander.css, AX_COMPONENTS_EXPANDER_AXEXPANDER_CSS

; ============================================================================
;  AxExpander.ahk -- Expander.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxExpander.ahk     what g.AddExpander() writes, the markup that becomes and
;                         what a click on it does
;      AxExpander.css     its shape -- the theme says what it looks like
;      Expander.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxExpander {
    static _reg := AxRich.Register("Expander", "components\Expander\AxExpander.css",
                                   (*) => AxExpander._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddExpander", (c, a*) => AxExpander._Expander(c, a*))
        AxTags.Register("ax-expander", 8, (el, inner, id) => AxExpander._Tag("ax-expander", el, inner, id))
        AxWindow.RegisterClick("expander-header", (w, el, t, ev) => AxExpander._Click("expander-header", w, el, t, ev))
        AxWindow.RegisterBox("expander")
        return true
    }

    static _Expander(c, opts := "", title := "", desc := "") {
        o := c._Opt(opts, "exp")
        return c._Sub(o, "Expander", '<ax-expander' c._Common(o) ' title="' AxTags.E(title) '" desc="' AxTags.E(desc) '"' (o.KV.Has("icon") ? ' icon="' o.KV["icon"] '"' : "") (o.Flags.Has("open") ? " open" : "") '>{inner}</ax-expander>')
        }

    ; ---- the markup <ax-expander> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-expander":
            return '<div' Root(el, "expander" (Has(el, "open") ? " open" : ""), true, ' data-role="expander"') '>'
                . '<div class="exp-header" data-role="expander-header">' (A(el, "icon") != "" ? '<span class="ico" style="margin-right:14px;">&#x' A(el, "icon") ';</span>' : "")
                . '<div class="text"><div class="title">' E(A(el, "title")) '</div>' (A(el, "desc") != "" ? '<div class="desc">' E(A(el, "desc")) '</div>' : "") '</div>'
                . '<div class="chev ico"></div></div><div class="exp-body">' inner '</div></div>'
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "expander-header":
            ex := win._RoleAncestor(t, "expander")
            if ex
                AxWindow._SetClass(ex, "open", !AxWindow._HasClass(ex, "open"))
        }
    }
}
