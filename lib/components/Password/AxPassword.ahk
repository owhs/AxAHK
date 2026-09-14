#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Password\AxPassword.css, AX_COMPONENTS_PASSWORD_AXPASSWORD_CSS

; ============================================================================
;  AxPassword.ahk -- Password.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxPassword.ahk     what g.AddPassword() writes, the markup that becomes and
;                         what a click on it does
;      AxPassword.css     its shape -- the theme says what it looks like
;      Password.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxPassword {
    static _reg := AxRich.Register("Password", "components\Password\AxPassword.css",
                                   (*) => AxPassword._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddPassword", (c, a*) => AxPassword._Password(c, a*))
        AxTags.Register("ax-password", 18, (el, inner, id) => AxPassword._Tag("ax-password", el, inner, id))
        AxWindow.RegisterClick("reveal", (w, el, t, ev) => AxPassword._Click("reveal", w, el, t, ev))
        AxWindow.RegisterBox("passwordbox")
        return true
    }

    static _Password(c, opts := "", text := "") {
        o := c._Opt(opts, "pw")
        return c._Reg(o, "Password", '<ax-password' c._Common(o) ' value="' AxTags.E(text) '" placeholder="' AxTags.E(c._Kv(o, "placeholder")) '"></ax-password>')
        }

    ; ---- the markup <ax-password> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-password":
            return '<div' Root(el, "passwordbox", false, ' data-role="passwordbox"') '><input type="password"' (id != "" ? ' id="' E(id) '"' : "")
                . ' value="' E(A(el, "value")) '" placeholder="' E(A(el, "placeholder")) '">'
                . '<div class="reveal" data-role="reveal"><span class="ico"></span>' E(A(el, "label", "Reveal")) '</div></div>'
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "reveal":
            pb := win._RoleAncestor(t, "passwordbox")
            if pb {
                inp := pb.querySelector("input")
                show := (inp.type = "password")
                try inp.type := show ? "text" : "password"
                AxWindow._SetClass(pb, "revealed", show)
            }
        }
    }
}
