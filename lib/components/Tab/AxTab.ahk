#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Tab\AxTab.css, AX_COMPONENTS_TAB_AXTAB_CSS

; ============================================================================
;  AxTab.ahk -- Tabs.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxTab.ahk     what g.AddTab() writes, the markup that becomes and what
;                    a click on it does
;      AxTab.css     its shape -- the theme says what it looks like
;      Tab.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxTab {
    static _reg := AxRich.Register("Tab", "components\Tab\AxTab.css",
                                   (*) => AxTab._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddTab", (c, a*) => AxTab._Tab(c, a*))
        AxTags.Register("ax-tabs", 7, (el, inner, id) => AxTab._Tag("ax-tabs", el, inner, id))
        AxWindow.RegisterClick("tab", (w, el, t, ev) => AxTab._Click("tab", w, el, t, ev), true)
        AxWindow.RegisterBox("tabs")
        ; tabs.Value is the tab showing, counted from 1; setting it shows
        ; another -- by number, or by its name
        AxWindow.RegisterValue("tabs", (w, el) => AxTab._Get(w, el), (w, el, v) => AxTab._Set(w, el, v))
        return true
    }
    ; the strip of tabs: the element itself, or inside it when it is framed
    static _Strip(el) {
        if AxWindow._HasClass(el, "tabs")
            return el
        try return el.querySelector(".tabs")
        return el
    }
    static _Get(win, el) {
        try {
            all := AxTab._Strip(el).children
            loop all.length
                if AxWindow._HasClass(all.item(A_Index - 1), "active")
                    return A_Index
        }
        return 0
    }
    static _Set(win, el, v) {
        try {
            all := AxTab._Strip(el).children
            loop all.length {
                t := all.item(A_Index - 1)
                if (IsInteger(v) ? (A_Index = Integer(v)) : (Trim(t.innerText) = v || AxWindow._Attr(t, "data-target") = v)) {
                    AxTab._Show(win, t)
                    return
                }
            }
        }
    }
    ; one tab active and its page shown, the rest put away
    static _Show(win, t) {
        all := t.parentNode.children                ; its own strip: not a tabs control on one of its pages
        loop all.length {
            tb := all.item(A_Index - 1)
            on := (tb.uniqueID = t.uniqueID)
            AxWindow._SetClass(tb, "active", on)
            tgt := AxWindow._Attr(tb, "data-target")
            if (tgt != "")
                try win.Doc.getElementById(tgt).style.display := on ? "block" : "none"
        }
        try win.FitNow()                            ; a page that grows gets its height now
        try win.Shown()                             ; and what measures itself catches up before the paint
    }

    static _Tab(c, opts := "", names := "") {
        o := c._Opt(opts, "tabs")
        t := c._Sub(o, "Tab", '<ax-tabs' c._Common(o) '>{inner}</ax-tabs>')
        if !IsObject(names)
            names := StrSplit(names, "|")
        for i, n in names {
            icon := "", p := InStr(n, ":")
            if p
                icon := SubStr(n, p + 1), n := SubStr(n, 1, p - 1)
            panel := AxGui.Container(c.G, "TabPanel", o.Id "_" i)
            panel.Html := '<ax-tab label="' AxTags.E(n) '"' (icon != "" ? ' icon="' icon '"' : "") '>{inner}</ax-tab>'
            t.Items.Push(panel)
            t._tabs.Push(panel)
        }
        t.UseTab(1)
        return t
        }

    ; ---- the markup <ax-tabs> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-tabs":
            tabs := el.getElementsByTagName("ax-tab")
            head := "", panels := "", n := 0
            loop tabs.length {
                t := tabs.item(A_Index - 1)
                if (t.parentNode.uniqueID != el.uniqueID)
                    continue
                n++
                pid := (id != "" ? id : "tabs") "_" n
                active := (n = 1)
                head .= '<div class="tab' (active ? " active" : "") '" data-role="tab" data-target="' pid '">' Ico(A(t, "icon")) E(A(t, "label")) '</div>'
                panels .= '<div class="tab-panel' (active ? " visible" : "") '" id="' pid '">' AxTags.Inner(t) '</div>'
            }
            ; Placed or sized (a design of fixed places): the strip and its
            ; pages go in one box of that size, and the page showing is what
            ; the controls on it are placed in -- otherwise the pages flow
            ; after a strip that is somewhere else, with their controls placed
            ; against whatever happens to be round them.
            ; Grow is a size too: the frame is what gets the height, and the
            ; page showing fills what the strip leaves.
            st := A(el, "style")
            if RegExMatch(st, "i)(^|;)\s*(left|top|height)\s*:") || RegExMatch(A(el, "class"), "(^|\s)ax-growy(\s|$)") {
                idc := RegExMatch(A(el, "class"), "\baxd-id-\S+", &dm) ? " " dm[0] : ""
                return '<div' Root(el, "tabs-frame", true, ' data-role="tabs"') '><div class="tabs' idc '">'
                     . head '</div>' panels '</div>'
            }
            return '<div' Root(el, "tabs", true, ' data-role="tabs"') '>' head '</div>' panels
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "tab":
            tabs := win._RoleAncestor(t, "tabs")
            if !tabs
                return
            try t.focus()
            AxTab._Show(win, t)
            win._FireValue(tabs, AxWindow._Attr(t, "data-target"))
        }
    }
}
