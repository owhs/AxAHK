#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\DropZone\AxDropZone.css, AX_COMPONENTS_DROPZONE_AXDROPZONE_CSS

; ============================================================================
;  AxDropZone.ahk -- Drop zone.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxDropZone.ahk     what g.AddDropZone() writes, the markup that becomes and
;                         what a click on it does
;      AxDropZone.css     its shape -- the theme says what it looks like
;      DropZone.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxDropZone {
    static _reg := AxRich.Register("DropZone", "components\DropZone\AxDropZone.css",
                                   (*) => AxDropZone._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddDropZone", (c, a*) => AxDropZone._DropZone(c, a*))
        AxTags.Register("ax-drop", 35, (el, inner, id) => AxDropZone._Tag("ax-drop", el, inner, id))
        AxWindow.RegisterClick("dropzone", (w, el, t, ev) => AxDropZone._Click("dropzone", w, el, t, ev))
        return true
    }

    static _DropZone(c, opts := "", title := "") {
        o := c._Opt(opts, "dz")
        accept := c._Kv(o, "accept", "*")
        c := c._Reg(o, "DropZone", '<ax-drop' c._Common(o, o.W = "" ? "fill" : "") ' accept="' AxTags.E(accept) '"'
            . ' title="' AxTags.E(title != "" ? title : "Drop files here") '" desc="' AxTags.E(c._Kv(o, "desc")) '"'
            . (o.KV.Has("icon") ? ' icon="' o.KV["icon"] '"' : "") (o.Flags.Has("compact") ? " compact" : "") '></ax-drop>')
        c.G.DropZone(o.Id, "", {Accept: accept, Browse: o.Flags.Has("browse"),
            Multi: !o.Flags.Has("single"), Expand: o.Flags.Has("expand"), Recurse: o.Flags.Has("recurse")})
        return c
        }

    ; ---- the markup <ax-drop> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-drop":
            return '<div' Root(el, "dropzone" (Has(el, "compact") ? " compact" : ""), true,
                    ' data-role="dropzone" data-accept="' E(A(el, "accept", "*")) '"') '>'
                . '<span class="ico dz-ico">&#x' A(el, "icon", "E896") ';</span>'
                . '<div class="dz-title">' E(A(el, "title", "Drop files here")) '</div>'
                . (A(el, "desc") != "" ? '<div class="dz-desc">' E(A(el, "desc")) '</div>' : "")
                . inner '</div>'
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "dropzone":
            ; clicking a zone opens its picker (only when Browse is set);
            ; buttons and controls placed inside it keep their own click
            if !win._ClosestClass(el, "btn")
                win._DropBrowse(t)
        }
    }
}
