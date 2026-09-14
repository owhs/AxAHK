#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\InfoBar\AxInfoBar.css, AX_COMPONENTS_INFOBAR_AXINFOBAR_CSS

; ============================================================================
;  AxInfoBar.ahk -- Info bar.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxInfoBar.ahk     what g.AddInfoBar() writes, the markup that becomes and
;                        what a click on it does
;      AxInfoBar.css     its shape -- the theme says what it looks like
;      InfoBar.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxInfoBar {
    static _reg := AxRich.Register("InfoBar", "components\InfoBar\AxInfoBar.css",
                                   (*) => AxInfoBar._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddInfoBar", (c, a*) => AxInfoBar._InfoBar(c, a*))
        AxTags.Register("ax-infobar", 26, (el, inner, id) => AxInfoBar._Tag("ax-infobar", el, inner, id))
        AxWindow.RegisterClick("infobar-close", (w, el, t, ev) => AxInfoBar._Click("infobar-close", w, el, t, ev))
        AxWindow.RegisterBox("infobar")
        ; ctl.Value is the message, and setting it leaves the icon, the title
        ; and the close button where they are
        AxWindow.RegisterValue("infobar", (w, el) => AxInfoBar._Msg(el, unset), (w, el, v) => AxInfoBar._Msg(el, v))
        return true
    }
    static _Msg(el, v?) {
        m := ""
        try m := el.querySelector(".ib-msg")
        if !IsObject(m)
            return IsSet(v) ? "" : el.innerText
        if !IsSet(v)
            return m.innerText
        AxWindow._SetText(m, v)
        return ""
    }

    static _InfoBar(c, opts := "", text := "") {
        o := c._Opt(opts, "ib")
        return c._Reg(o, "InfoBar", '<ax-infobar' c._Common(o, "fill") ' kind="' c._Kv(o, "kind", "info") '" title="' AxTags.E(c._Kv(o, "title")) '"' (o.Flags.Has("noclose") ? " noclose" : "") '>' AxTags.E(text) '</ax-infobar>')
        }

    ; ---- the markup <ax-infobar> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-infobar":
            static icons := Map("info", "E946", "success", "E930", "warning", "E7BA", "error", "EA39")
            kind := A(el, "kind", "info")
            return '<div' Root(el, "infobar " kind, true, ' data-role="infobar"') '>' Ico(icons.Has(kind) ? icons[kind] : "E946")
                . '<div class="text">' (A(el, "title") != "" ? '<b>' E(A(el, "title")) '</b> ' : "") '<span class="ib-msg">' inner '</span></div>'
                . (Has(el, "noclose") ? "" : '<div class="close ico" data-role="infobar-close">&#xE8BB;</div>') '</div>'
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "infobar-close":
            ib := win._RoleAncestor(t, "infobar")
            if ib
                ib.style.display := "none"
        }
    }
}
