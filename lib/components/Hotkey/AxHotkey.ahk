#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Hotkey\AxHotkey.css, AX_COMPONENTS_HOTKEY_AXHOTKEY_CSS

; ============================================================================
;  AxHotkey.ahk -- Hotkey box.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxHotkey.ahk     what g.AddHotkey() writes, the markup that becomes and
;                       what a click on it does
;      AxHotkey.css     its shape -- the theme says what it looks like
;      Hotkey.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxHotkey {
    static _reg := AxRich.Register("Hotkey", "components\Hotkey\AxHotkey.css",
                                   (*) => AxHotkey._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddHotkey", (c, a*) => AxHotkey._Hotkey(c, a*))
        AxTags.Register("ax-hotkey", 32, (el, inner, id) => AxHotkey._Tag("ax-hotkey", el, inner, id))
        AxWindow.RegisterClick("hotkey-clear", (w, el, t, ev) => AxHotkey._Click("hotkey-clear", w, el, t, ev))
        AxWindow.RegisterBox("hotkey")
        return true
    }

    static _Hotkey(c, opts := "", value := "") {
        o := c._Opt(opts, "hk")
        return c._Reg(o, "Hotkey", '<ax-hotkey' c._Common(o) ' value="' AxTags.E(value) '" placeholder="' AxTags.E(c._Kv(o, "placeholder", "Press a key combination")) '"></ax-hotkey>')
        }

    ; ---- the markup <ax-hotkey> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-hotkey":
            val := A(el, "value")
            return '<div' Root(el, "hotkeybox" (val != "" ? " has-value" : ""), true, ' data-role="hotkey" data-value="' E(val) '"') '>'
                . '<span class="ico kb">&#xE765;</span><input type="text" readonly value="' E(AxSys.HotkeyDisplay(val)) '" placeholder="' E(A(el, "placeholder", "Press a key combination")) '">'
                . '<div class="clear ico" data-role="hotkey-clear" data-tip="Clear">&#xE8BB;</div></div>'
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "hotkey-clear":
            hk := win._RoleAncestor(t, "hotkey")
            if hk
                win._SetHotkeyValue(hk, "", "")
        }
    }
}
