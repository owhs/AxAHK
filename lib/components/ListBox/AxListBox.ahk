#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\ListBox\AxListBox.css, AX_COMPONENTS_LISTBOX_AXLISTBOX_CSS

; ============================================================================
;  AxListBox.ahk -- List box.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxListBox.ahk     what g.AddDropDownList() writes, the markup that becomes
;                        and what a click on it does
;      AxListBox.css     its shape -- the theme says what it looks like
;      ListBox.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxListBox {
    static _reg := AxRich.Register("ListBox", "components\ListBox\AxListBox.css",
                                   (*) => AxListBox._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddListBox", (c, a*) => AxListBox._ListBox(c, a*))
        AxTags.Register("ax-list", 24, (el, inner, id) => AxListBox._Tag("ax-list", el, inner, id))
        AxWindow.RegisterClick("list-item", (w, el, t, ev) => AxListBox._Click("list-item", w, el, t, ev), true)
        AxWindow.RegisterBox("list")
        return true
    }

    static _ListBox(c, opts := "", options := "") {
        o := c._Opt(opts, "lst")
        r := c._Options(o, options, o.Choose)
        multi := o.Flags.Has("checklist") ? "check" : o.Flags.Has("multi") ? "ctrl" : ""
        return c._Reg(o, "ListBox", '<ax-list' c._Common(o) ' options="' AxTags.E(r[1]) '" value="' AxTags.E(r[2]) '"' (o.H != "" ? ' height="' o.H '"' : "") (multi != "" ? ' multi="' multi '"' : "") '></ax-list>')
        }

    ; ---- the markup <ax-list> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-list":
            val := A(el, "value"), items := ""
            for o in AxTags.Options(A(el, "options"))
                items .= '<div class="list-item' (o[1] = val ? " selected" : "") '" data-value="' E(o[1]) '">' E(o[2]) '</div>'
            st := (A(el, "height") != "" ? "max-height:" A(el, "height") "px;" : "") (A(el, "width") != "" ? "width:" A(el, "width") "px;" : "") E(A(el, "style"))
            multi := A(el, "multi")                      ; "" | "ctrl" (Ctrl+click toggles) | "check" (checkbox list)
            if (multi != "") {                           ; value may be "a|b"
                items := ""
                for o in AxTags.Options(A(el, "options")) {
                    sel := false
                    for v in StrSplit(val, "|")
                        if (v = o[1])
                            sel := true
                    items .= '<div class="list-item' (sel ? " selected" : "") '" data-value="' E(o[1]) '">' E(o[2]) '</div>'
                }
            }
            return '<div class="list' (multi != "" ? " multi " (multi = "check" ? "checklist" : multi) : "") (A(el, "class") != "" ? " " E(A(el, "class")) : "") '"' (id != "" ? ' id="' E(id) '"' : "") ' data-role="list" data-value="' E(val) '"' (multi != "" ? ' data-multi="' multi '"' : "") (st != "" ? ' style="' st '"' : "") '>' items inner '</div>'
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "list-item":
            lst := win._RoleAncestor(t, "list")
            if !lst
                return
            try lst.focus()
            multi := AxWindow._Attr(lst, "data-multi")
            if (multi = "" || (multi = "ctrl" && !GetKeyState("Ctrl", "P")))
                win._SelectItem(lst, "list", AxWindow._Attr(t, "data-value"), t)
            else {                                             ; toggle this item, keep the others
                AxWindow._SetClass(t, "selected", !AxWindow._HasClass(t, "selected"))
                win._CommitMulti(lst)
            }
        }
    }
}
