#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\AutoComplete\AxAutoComplete.css, AX_COMPONENTS_AUTOCOMPLETE_AXAUTOCOMPLETE_CSS

; ============================================================================
;  AxAutoComplete.ahk -- Autocomplete.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxAutoComplete.ahk     what g.AddAutoComplete() writes, the markup that becomes
;                             and what a click on it does
;      AxAutoComplete.css     its shape -- the theme says what it looks like
;      AutoComplete.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxAutoComplete {
    static _reg := AxRich.Register("AutoComplete", "components\AutoComplete\AxAutoComplete.css",
                                   (*) => AxAutoComplete._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddAutoComplete", (c, a*) => AxAutoComplete._AutoComplete(c, a*))
        AxTags.Register("ax-autocomplete", 20, (el, inner, id) => AxAutoComplete._Tag("ax-autocomplete", el, inner, id))
        AxWindow.RegisterClick("autocomplete", (w, el, t, ev) => AxAutoComplete._Click("autocomplete", w, el, t, ev))
        return true
    }

    static _AutoComplete(c, opts := "", options := "") {
        o := c._Opt(opts, "ac")
        r := c._Options(o, options)
        return c._Reg(o, "AutoComplete", '<ax-autocomplete' c._Common(o) ' options="' AxTags.E(r[1]) '" value="' AxTags.E(c._Kv(o, "value", r[2])) '"'
            . ' placeholder="' AxTags.E(c._Kv(o, "placeholder")) '"' (o.Flags.Has("strict") ? " strict" : "") '></ax-autocomplete>')
        }

    ; ---- the markup <ax-autocomplete> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-autocomplete":
            ; free-typed text with suggestions; strict = only listed values, a
            ; non-matching entry clears itself when focus leaves
            val := A(el, "value"), label := "", items := ""
            for o in AxTags.Options(A(el, "options")) {
                if (o[1] = val)
                    label := o[2]
                items .= '<div class="dd-item" data-value="' E(o[1]) '">' E(o[2]) '</div>'
            }
            st := (A(el, "width") != "" ? "min-width:" A(el, "width") "px;" : "") E(A(el, "style"))
            return '<div class="textbox autocomplete' (A(el, "class") != "" ? " " E(A(el, "class")) : "") '"' (id != "" ? ' id="' E(id) '"' : "")
                . ' data-role="autocomplete" data-value="' E(val) '"' (Has(el, "strict") ? ' data-strict="1"' : "") (st != "" ? ' style="' st '"' : "")
                . (A(el, "tip") != "" ? ' data-tip="' E(A(el, "tip")) '"' : "")
                . '><input type="text" autocomplete="off" value="' E(label != "" ? label : val) '" placeholder="' E(A(el, "placeholder")) '"><div class="dd-menu ac-menu">' items '</div></div>'
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "autocomplete":                                   ; click in the box itself: (re)open the list
            if !(IsObject(win._ddOpen) && win._ddOpen.uniqueID = t.uniqueID)
                win._AcFilter(t, t.querySelector("input").value)
        }
    }
}
