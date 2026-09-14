#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Palette\AxPalette.css, AX_COMPONENTS_PALETTE_AXPALETTE_CSS

; ============================================================================
;  AxPalette.ahk -- Colour palette.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxPalette.ahk     what g.AddPalette() writes, the markup that becomes and
;                        what a click on it does
;      AxPalette.css     its shape -- the theme says what it looks like
;      Palette.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxPalette {
    static _reg := AxRich.Register("Palette", "components\Palette\AxPalette.css",
                                   (*) => AxPalette._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddPalette", (c, a*) => AxPalette._Palette(c, a*))
        AxTags.Register("ax-palette", 29, (el, inner, id) => AxPalette._Tag("ax-palette", el, inner, id))
        AxWindow.RegisterClick("swatch", (w, el, t, ev) => AxPalette._Click("swatch", w, el, t, ev), true)
        AxWindow.RegisterBox("palette")
        return true
    }

    static _Palette(c, opts := "", colors := "") {
        o := c._Opt(opts, "pal")
        if IsObject(colors) {
            s := ""
            for c in colors
                s .= (s = "" ? "" : ",") c
            colors := s
        }
        return c._Reg(o, "Palette", '<ax-palette' c._Common(o) ' colors="' AxTags.E(colors) '" value="' AxTags.E(c._Kv(o, "value")) '"' (o.Flags.Has("showhex") ? " showhex" : "") (o.Flags.Has("small") ? " small" : "") '></ax-palette>')
        }

    ; ---- the markup <ax-palette> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-palette":
            val := A(el, "value"), sw := "", hexId := A(el, "out", id != "" ? id "_hex" : "")
            for c in StrSplit(A(el, "colors"), ",") {
                c := Trim(c)
                if (c != "")
                    sw .= '<div class="swatch' (Has(el, "small") ? "" : " big") (c = val ? " selected" : "") '" data-value="' E(c) '" style="background:' E(c) '"></div>'
            }
            return '<div' Root(el, "palette", true, ' data-role="palette" data-value="' E(val) '"' (Has(el, "showhex") && hexId != "" ? ' data-out="' E(hexId) '"' : "")) '>' sw
                . (Has(el, "showhex") && hexId != "" ? '<span class="hex" id="' E(hexId) '" style="margin-left:8px;vertical-align:top;">' E(val) '</span>' : "") '</div>'
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "swatch":
            pal := win._RoleAncestor(t, "palette")
            if pal
                win._SelectItem(pal, "palette", AxWindow._Attr(t, "data-value"), t)
        }
    }
}
