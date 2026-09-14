#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Tile\AxTile.css, AX_COMPONENTS_TILE_AXTILE_CSS

; ============================================================================
;  AxTile.ahk -- Tile.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxTile.ahk     what g.AddTile() writes, the markup that becomes and what
;                     a click on it does
;      AxTile.css     its shape -- the theme says what it looks like
;      Tile.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxTile {
    static _reg := AxRich.Register("Tile", "components\Tile\AxTile.css",
                                   (*) => AxTile._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddTile", (c, a*) => AxTile._Tile(c, a*))
        AxTags.Register("ax-tile", 10, (el, inner, id) => AxTile._Tag("ax-tile", el, inner, id))
        AxWindow.RegisterClick("remove-item", (w, el, t, ev) => AxTile._Click("remove-item", w, el, t, ev))
        return true
    }

    static _Tile(c, opts := "", name := "") {
        o := c._Opt(opts, "tile")
        return c._Reg(o, "Tile", '<ax-tile' c._Common(o) ' value="' AxTags.E(c._Kv(o, "value", name)) '" name="' AxTags.E(name) '" desc="' AxTags.E(c._Kv(o, "desc")) '"'
            . (o.KV.Has("icon") ? ' icon="' o.KV["icon"] '"' : "") (o.Flags.Has("removable") ? " removable" : "") '></ax-tile>')
        }

    ; ---- the markup <ax-tile> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-tile":
            return '<div' Root(el, "tile drag-item", true, ' data-value="' E(A(el, "value", A(el, "name"))) '"') '>'
                . (A(el, "icon") != "" ? '<span class="ico">&#x' A(el, "icon") ';</span>' : "")
                . '<div class="name">' E(A(el, "name")) '</div>' (A(el, "desc") != "" ? '<div class="desc">' E(A(el, "desc")) '</div>' : "") inner
                . (Has(el, "removable") ? '<div class="remove ico" data-role="remove-item">&#xE8BB;</div>' : "") '</div>'
        ; -------------------------------------------------------- controls
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "remove-item":
            it := win._ClosestClass(t, "drag-item")
            if !it
                return
            cont := win._RoleAncestor(it, "sortable")
            parent := it.parentNode
            it.parentNode.removeChild(it)
            if cont
                win._FireValue(cont, win.SortOrder(cont.id))
            else if (IsObject(parent) && AxWindow._Attr(parent, "data-list") != "")
                win._FireValue(parent, win.SortOrder(parent.id))
        }
    }
}
