#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Segmented\AxSegmented.css, AX_COMPONENTS_SEGMENTED_AXSEGMENTED_CSS

; ============================================================================
;  AxSegmented.ahk -- Segmented.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxSegmented.ahk     what g.AddSegmented() writes, the markup that becomes and
;                          what a click on it does
;      AxSegmented.css     its shape -- the theme says what it looks like
;      Segmented.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxSegmented {
    static _reg := AxRich.Register("Segmented", "components\Segmented\AxSegmented.css",
                                   (*) => AxSegmented._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddSegmented", (c, a*) => AxSegmented._Segmented(c, a*))
        AxTags.Register("ax-segmented", 31, (el, inner, id) => AxSegmented._Tag("ax-segmented", el, inner, id))
        AxWindow.RegisterClick("seg", (w, el, t, ev) => AxSegmented._Click("seg", w, el, t, ev), true)
        AxWindow.RegisterBox("segmented")
        return true
    }

    static _Segmented(c, opts := "", options := "") {
        o := c._Opt(opts, "seg")
        r := c._Options(o, options, o.Choose)
        return c._Reg(o, "Segmented", '<ax-segmented' c._Common(o) ' options="' AxTags.E(r[1]) '" value="' AxTags.E(r[2]) '"></ax-segmented>')
        }

    ; ---- the markup <ax-segmented> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-segmented":
            val := A(el, "value"), segs := ""
            for o in AxTags.Options(A(el, "options")) {
                glyph := "", lab := o[2], p := InStr(lab, ":")
                if p
                    glyph := SubStr(lab, p + 1), lab := SubStr(lab, 1, p - 1)
                segs .= '<div class="seg' (o[1] = val ? " active" : "") '" data-value="' E(o[1]) '">' Ico(glyph) (glyph != "" ? " " : "") E(lab) '</div>'
            }
            return '<div' Root(el, "segmented", true, ' data-role="segmented" data-value="' E(val) '"') '>' segs '</div>'
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "seg":
            sg := win._RoleAncestor(t, "segmented")
            if !sg
                return
            try t.focus()
            segs := sg.querySelectorAll(".seg")
            loop segs.length {
                sgi := segs.item(A_Index - 1)
                AxWindow._SetClass(sgi, "active", sgi.uniqueID = t.uniqueID)
            }
            v := AxWindow._Attr(t, "data-value")
            sg.setAttribute("data-value", v)
            win._FireValue(sg, v)
        }
    }
}
