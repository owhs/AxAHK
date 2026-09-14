#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\DDL\AxDDL.css, AX_COMPONENTS_DDL_AXDDL_CSS

; ============================================================================
;  AxDDL.ahk -- Drop-down.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxDDL.ahk     what g.AddDDL() writes, the markup that becomes and what
;                    a click on it does
;      AxDDL.css     its shape -- the theme says what it looks like
;      DDL.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxDDL {
    static _reg := AxRich.Register("DDL", "components\DDL\AxDDL.css",
                                   (*) => AxDDL._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddDDL", (c, a*) => AxDDL._DDL(c, a*))
        ; the AutoHotkey names for the same control
        AxRich.AddMethod("AddDropDownList", (c, a*) => AxDDL._DropDownList(c, a*))
        AxRich.AddMethod("AddComboBox", (c, a*) => AxDDL._ComboBox(c, a*))
        AxTags.Register("ax-dropdown", 23, (el, inner, id) => AxDDL._Tag("ax-dropdown", el, inner, id))
        AxWindow.RegisterClick("dropdown", (w, el, t, ev) => AxDDL._Click("dropdown", w, el, t, ev))
        AxWindow.RegisterClick("dd-item", (w, el, t, ev) => AxDDL._Click("dd-item", w, el, t, ev), true)
        return true
    }

    static _DDL(c, opts := "", options := "") {
        o := c._Opt(opts, "dd")
        r := c._Options(o, options, o.Choose)
        return c._Reg(o, "DDL", '<ax-dropdown' c._Common(o) ' options="' AxTags.E(r[1]) '" value="' AxTags.E(r[2]) '"' (o.W != "" ? ' width="' o.W '"' : "") ' placeholder="' AxTags.E(c._Kv(o, "placeholder", "Select…")) '"></ax-dropdown>')
        }

    ; g.AddDropDownList() and g.AddComboBox() are the AutoHotkey names for it
    static _DropDownList(c, opts := "", options := "") => c.AddDDL(opts, options)

    static _ComboBox(c, opts := "", options := "") => c.AddDDL(opts, options)

    ; ---- the markup <ax-dropdown> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-dropdown":
            val := A(el, "value"), label := "", items := ""
            for o in AxTags.Options(A(el, "options")) {
                sel := (o[1] = val)
                if sel
                    label := o[2]
                items .= '<div class="dd-item' (sel ? " selected" : "") '" data-value="' E(o[1]) '">' E(o[2]) '</div>'
            }
            st := (A(el, "width") != "" || A(el, "style") != "") ? ' style="' (A(el, "width") != "" ? "min-width:" A(el, "width") "px;" : "") E(A(el, "style")) '"' : ""
            return '<div class="dropdown' (A(el, "class") != "" ? " " E(A(el, "class")) : "") '"' (id != "" ? ' id="' E(id) '"' : "") ' data-role="dropdown" data-value="' E(val) '"' st
                . (A(el, "tip") != "" ? ' data-tip="' E(A(el, "tip")) '"' : "") '><div class="dd-value">' E(label != "" ? label : A(el, "placeholder", "Select…")) '</div><div class="dd-menu">' items '</div></div>'
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "dropdown":
            if AxWindow._HasClass(t, "disabled")
                return
            try t.focus()                                      ; arrows/Enter/Esc then reach it
            if (IsObject(win._ddOpen) && win._ddOpen.uniqueID = t.uniqueID)
                win._CloseDropdown()
            else {
                win._CloseDropdown()
                AxWindow._SetClass(t, "open", true)
                win._ddOpen := t
                win._ShieldScrollers(t)
                try h := t.querySelector(".dd-menu").offsetHeight     ; settle layout before the first paint
            }
        case "dd-item":
            if ac := win._RoleAncestor(t, "autocomplete") {
                win._AcPick(ac, t)
                return
            }
            dd := win._RoleAncestor(t, "dropdown")
            if (dd && !AxWindow._HasClass(dd, "disabled")) {
                win._SelectItem(dd, "dropdown", AxWindow._Attr(t, "data-value"), t)
                win._CloseDropdown()
            }
        }
    }
}
