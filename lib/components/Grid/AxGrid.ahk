#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Grid\AxGrid.css, AX_COMPONENTS_GRID_AXGRID_CSS

; ============================================================================
;  AxGrid.ahk -- Tile grid.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxGrid.ahk     what g.AddGrid() writes and the markup that becomes
;      AxGrid.css     its shape -- the theme says what it looks like
;      Grid.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxGrid {
    static _reg := AxRich.Register("Grid", "components\Grid\AxGrid.css",
                                   (*) => AxGrid._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddGrid", (c, a*) => AxGrid._Grid(c, a*))
        AxTags.Register("ax-grid", 9, (el, inner, id) => AxGrid._Tag("ax-grid", el, inner, id))
        return true
    }

    static _Grid(c, opts := "") {
        o := c._Opt(opts, "grid")
        c := c._Sub(o, "Grid", '<ax-grid' c._Common(o) '>{inner}</ax-grid>')
        c.Flat := true
        return c
        }

    ; ---- the markup <ax-grid> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-grid":
            return '<div' Root(el, "tile-grid", true, ' data-role="sortable" data-axis="x"') '>' inner '</div>'
        }
        return inner
    }
}
