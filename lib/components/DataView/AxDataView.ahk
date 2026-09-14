#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: embed this component's stylesheet (harmless uncompiled)
;@Ahk2Exe-AddResource %U_AxLib%\components\DataView\AxDataView.css, AX_COMPONENTS_DATAVIEW_AXDATAVIEW_CSS

; =============================================================================
;  AxDataView — list, tree and grouped grid in one rich component.
;
;      dv := g.AddDataView("vfiles Fill h340 Checkboxes Multi", {
;          Columns: [{Key: "name", Title: "Name",  Width: 260, Icon: true},
;                    {Key: "size", Title: "Size",  Width: 100, Align: "right", Sort: "number"},
;                    {Key: "kind", Title: "Kind",  Width: 140}],
;          Rows: [{name: "readme.md", size: 1240, kind: "Document"}, ...],
;          PageSize: 25})
;      dv.Component.OnSelect((rows, c) => ...)
;
;  A tree is the same thing with Children on a row; a grouped list is the same
;  thing with Group set. All three share one pipeline, run on every change:
;
;      filter -> sort -> group -> flatten -> paginate -> render
;
;  ----------------------------------------------------------------- options
;    Columns    [{Key, Title, Width, MinWidth, MaxWidth, Align, Sort, Format,
;                 Icon, Hidden, Hideable}]
;               Sort: true | false | "text" | "number" | "date" | fn(a, b)
;               Format: fn(value, row) -> the text to show
;               Icon: true puts the row's Icon glyph and the tree twisty here
;               (the first column gets them by default)
;    Rows       Array of objects or Maps. Recognised keys: Key (identity),
;               Icon (glyph), Checked, Expanded, Selected, Children (an Array
;               -> a tree), plus one entry per column Key.
;    Tree       true to draw twisties even before Children arrive
;    Group      a column key, or fn(row) -> group name
;    PageSize   rows per page; 0 (default) shows everything
;    Select     "multi" (default) | "single" | "none". Multi: false is the
;               older spelling of "single".
;    Checkboxes true adds a tick box to every row
;    CheckMode  "box" (default) ticks only from the box itself; "row" lets a
;               click anywhere on the row toggle it
;    CheckTree  in a tree, ticking a branch ticks everything under it and
;               branches show a dash while only some of their rows are ticked
;    CheckAll   true (default) puts the tri-state tick box in the header
;    Columns UI the header's right-click menu (and the Columns button) hides
;               and shows columns and sizes them to fit; double-clicking the
;               edge between two headers sizes that one column
;    Search     true (default) shows the filter box
;    Tools      true (default) shows the toolbar at all
;    Sort       {Key, Dir} to start sorted
;    Empty      the message shown when nothing matches
;    Fixed      true: the body is always Height tall, as a native list is,
;               rather than at most that tall
;
;  ------------------------------------------------------------------ events
;    OnSelect(rows, dv)     OnCheck(rows, dv)     OnActivate(row, dv)
;    OnSort(key, dir, dv)   OnPage(page, dv)      OnExpand(row, open, dv)
;    OnExpandAll(open, dv)  -- the Expand all / Collapse all buttons
;    OnHeader(key, dv)      -- a column title clicked, whether it sorts or not
;    OnState(dv)            -- the selection or the ticks set from code
;                              (SelectKeys, ClearSelection, Check), which
;                              fire nothing else
;
;  Reload(rows?) is SetRows for rows that changed in place: the selection,
;  the cursor, the ticks and the open branches follow each row by its Key,
;  and the page stays. A row that carries Checked, Expanded or Selected
;  itself is taken at its word.
;
;  Value / OnValue give the selected keys, so the control joins the ordinary
;  AxGui contract: ctl.Value is an Array of keys, ctl.OnChange fires on select.
; =============================================================================
class AxDataView {
    static _reg := AxRich.Register("DataView", "components\DataView\AxDataView.css", (*) => (
        AxRich.AddMethod("AddDataView", (c, o := "", d := "") => AxDataView._Add(c, o, d)),
        AxWindow.RegisterValue("dataview",
            (w, el) => AxDataView._Via(w, el, unset),
            (w, el, v) => AxDataView._Via(w, el, v))))
    ; Map.Delete throws on a key that is not there, and half of this component
    ; toggles keys in and out of Maps, so every removal goes through here.
    static _Drop(map, key) {
        if map.Has(key)
            map.Delete(key)
    }
    static _Via(win, el, value?) {
        c := AxRich.At(win, el.id)
        if !IsObject(c)
            return []
        if IsSet(value)
            return c.SelectKeys(IsObject(value) ? value : StrSplit(String(value), "|"))
        return c.SelectedKeys()
    }

    ; ---------------------------------------------------------------- markup
    static Html(id, opts := "") {
        o := (n, d := "") => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        E := (x) => AxWindow._Esc(x)
        h := o("Height", 320), tools := o("Tools", true), search := o("Search", true)
        s := '<div class="dv' (o("Class", "") != "" ? " " E(o("Class", "")) : "") '" id="' E(id) '"'
           . ' data-role="dataview"' (o("Style", "") != "" ? ' style="' E(o("Style", "")) '"' : "") '>'
        if tools {
            s .= '<div class="dv-tools" id="' E(id) '_tools">'
            if search
                s .= '<div class="searchbox"><input type="text" id="' E(id) '_q" autocomplete="off"'
                  .  ' placeholder="' E(o("SearchPlaceholder", "Filter…")) '"><span class="ico">&#xE721;</span></div>'
            s .= '<span class="btn subtle" id="' E(id) '_expand" tabindex="0">Expand all</span>'
              .  '<span class="btn subtle" id="' E(id) '_collapse" tabindex="0">Collapse all</span>'
            if o("ColumnMenu", true)
                s .= '<span class="btn subtle" id="' E(id) '_cols" tabindex="0">'
                  .  '<span class="ico">&#xE71D;</span> Columns</span>'
            s .= '<span class="dv-count" id="' E(id) '_count"></span></div>'
        }
        ; Normally the head and the body are left empty here and filled in by
        ; the instance, which is created OnReady. A designer never shows its
        ; window -- it builds the markup as a string -- so OnReady never runs
        ; and the grid comes out as a toolbar with a pager under it and nothing
        ; in between, which reads as broken rather than as unbuilt.
        ;
        ; Preview writes a static head and body from whatever columns and rows
        ; it was handed, with the same classes the instance uses, so there is
        ; one description of what a row looks like rather than two.
        pv := AxDataView._Preview(opts)
        s .= '<div class="dv-frame" id="' E(id) '_frame">'
          .  '<div class="dv-headwrap" id="' E(id) '_headwrap"><table class="dv-table" id="'
          .  E(id) '_htable"' (pv.Width ? ' style="width:' pv.Width 'px"' : "") '>'
          .  '<colgroup id="' E(id) '_hcols">' pv.Cols '</colgroup>'
          .  '<thead><tr id="' E(id) '_head">' pv.Head '</tr></thead></table></div>'
          .  '<div class="dv-bodywrap" id="' E(id) '_scroll" tabindex="0" style="'
          .  (o("Fixed", false) ? "height:" : "max-height:") h 'px">'
          .  '<table class="dv-table" id="' E(id) '_btable"'
          .  (pv.Width ? ' style="width:' pv.Width 'px"' : "") '>'
          .  '<colgroup id="' E(id) '_bcols">' pv.Cols '</colgroup>'
          .  '<tbody id="' E(id) '_body">' pv.Body '</tbody></table></div></div>'
        s .= '<div class="dv-foot" id="' E(id) '_foot">'
          .  '<span class="btn" id="' E(id) '_first" tabindex="0">&#x00AB;</span>'
          .  '<span class="btn" id="' E(id) '_prev" tabindex="0">&#x2039;</span>'
          .  '<span class="dv-page" id="' E(id) '_page">1 / 1</span>'
          .  '<span class="btn" id="' E(id) '_next" tabindex="0">&#x203A;</span>'
          .  '<span class="btn" id="' E(id) '_last" tabindex="0">&#x00BB;</span>'
          .  '<span class="dv-status" id="' E(id) '_status"></span></div>'
        return s '</div>'
    }

    ; The static head and body for Preview. Off unless asked for, so nothing
    ; that shows a real window pays for it.
    static _Preview(opts) {
        none := {Cols: "", Head: "", Body: "", Width: 0}
        o := (n, d := "") => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        if !o("Preview", false)
            return none
        columns := o("Columns", "")
        if !(columns is Array) || !columns.Length
            return none
        E := (x) => AxWindow._Esc(x)
        ; not C: names are not case-sensitive, and "for c in columns" below would
        ; overwrite it with a column, the next call then failing on an Object
        Prop := (c, n, d := "") => (IsObject(c) && c.HasOwnProp(n)) ? c.%n% : d
        cols := "", head := "", total := 0
        for c in columns {
            w := Prop(c, "Width", 160)
            total += w
            cols .= '<col style="width:' w 'px">'
            align := Prop(c, "Align", "left")
            head .= '<th class="dv-hcell' (align != "left" ? " " align : "") '">'
                 .  '<span class="dv-htext">' E(Prop(c, "Title", Prop(c, "Key", ""))) '</span>'
                 .  '<span class="dv-sort"></span><span class="dv-grip"></span></th>'
        }
        rows := o("Rows", "")
        ; a tree is drawn opened all the way down, so the design shows all of it
        tree := o("Tree", false), ticks := o("Checkboxes", false)
        if (!tree && rows is Array)
            for r in rows
                if (Prop(r, "Children", "") is Array)
                    tree := true
        Draw(list, depth) {
            out := ""
            for r in list {
                kids := Prop(r, "Children", "")
                kids := (kids is Array && kids.Length) ? kids : ""
                out .= '<tr class="dv-row">'
                for i, c in columns {
                    align := Prop(c, "Align", "left")
                    out .= '<td class="dv-cell' (align != "left" ? " " align : "") (i > 1 ? " dim" : "") '">'
                    if (i = 1) {
                        if depth
                            out .= '<span class="dv-indent" style="width:' (depth * 18) 'px"></span>'
                        if tree
                            out .= '<span class="dv-twisty' (kids ? " open" : " leaf") '"></span>'
                        if ticks
                            out .= '<span class="dv-check' (Prop(r, "Checked", 0) ? " on" : "") '"></span>'
                        if (Prop(r, "Icon", "") != "")
                            out .= '<span class="ico dv-icon">&#x' E(Prop(r, "Icon", "")) ';</span>'
                    }
                    out .= '<span class="dv-text">' E(Prop(r, Prop(c, "Key", ""), "")) '</span></td>'
                }
                out .= '</tr>'
                if kids
                    out .= Draw(kids, depth + 1)
            }
            return out
        }
        body := (rows is Array) ? Draw(rows, 0) : ""
        if (body = "")
            body := '<tr><td class="dv-empty" colspan="' columns.Length '">'
                  . E(o("Empty", "Nothing to show")) '</td></tr>'
        return {Cols: cols, Head: head, Body: body, Width: total}
    }

    ; ------------------------------------------------------------ construction
    __New(win, id, opts := "") {
        this.W := win, this.Id := id
        this._probeHdr := -1                 ; which font the _Measure probe carries
        this.Opts := IsObject(opts) ? opts : {}
        o := (n, d := "") => this.Opts.HasOwnProp(n) ? this.Opts.%n% : d
        sel := StrLower(String(o("Select", o("Multi", true) ? "multi" : "single")))
        this.Select     := (sel = "none" || sel = "single") ? sel : "multi"
        this.Multi      := (this.Select = "multi")
        this.Checkboxes := o("Checkboxes", false)
        this.CheckMode  := StrLower(String(o("CheckMode", "box")))
        this.CheckTree  := o("CheckTree", false)
        this.ShowCheckAll := o("CheckAll", true)      ; not "CheckAll": that is a method
        this.PageSize   := Integer(o("PageSize", 0))
        this.Tree       := o("Tree", false)
        this.Group      := o("Group", "")
        this.Empty      := o("Empty", "Nothing to show.")
        this.TypeToFind := o("TypeToFind", true)
        this.Page       := 1
        this.Query      := ""
        this.SortKey    := "", this.SortDir := 1
        this._cbs := Map("select", [], "check", [], "activate", [], "sort", [], "page", [], "expand", [], "expandall", [], "header", [], "state", [])
        this._sel := Map(), this._chk := Map(), this._open := Map()
        this._cursor := 0
        this._nodes := Map(), this._flat := [], this._view := [], this._srcRows := []
        this._anchor := 0, this._hasTree := false
        this._find := "", this._findAt := 0                ; type-to-find buffer
        this._pages := 1, this._total := 0
        if IsObject(o("Sort", ""))
            this.SortKey := o("Sort").Key, this.SortDir := (o("Sort").HasOwnProp("Dir") && o("Sort").Dir < 0) ? -1 : 1
        this.SetColumns(o("Columns", [{Key: "name", Title: "Name", Width: 240}]), false)
        AxRich.Use(win, "DataView")
        AxRich.Bind(win, id, this)
        this._Wire()
        this.SetRows(o("Rows", []))
    }
    ; --- columns
    SetColumns(cols, refresh := true) {
        this.Cols := []
        for i, c in cols {
            d := {Key: "", Title: "", Width: 140, MinWidth: 48, MaxWidth: 640, Align: "left",
                  Sort: true, Format: "", Icon: (i = 1), Hidden: false, Hideable: true}
            if IsObject(c)
                for k, v in (c is Map ? c : c.OwnProps())
                    d.%k% := v
            else
                d.Key := c, d.Title := c
            if (d.Title = "")
                d.Title := d.Key
            d.Width := Integer(d.Width), d.MinWidth := Integer(d.MinWidth)
            this.Cols.Push(d)
        }
        if refresh
            this.Refresh()
        return this
    }
    ; --- visible columns. Hiding one must not disturb sorting or resizing, so
    ; the DOM keeps the ORIGINAL column index in data-c and the ornaments (tree
    ; twisty, tick box, icon) move to the first visible column that wants them.
    _Vis() {
        out := []
        for i, c in this.Cols
            if !c.Hidden
                out.Push({I: i, C: c, Orn: false})
        if !out.Length && this.Cols.Length
            out.Push({I: 1, C: this.Cols[1], Orn: false})       ; never show nothing
        at := 0
        for j, v in out
            if (v.C.Icon && !at)
                at := j
        out[at ? at : 1].Orn := true
        return out
    }
    _VisPos(i) {                                   ; original index -> DOM position
        for j, v in this._Vis()
            if (v.I = i)
                return j
        return 0
    }
    _ColIndex(key) {
        for i, c in this.Cols
            if (c.Key = key)
                return i
        return 0
    }
    ; ShowColumn("size", false) / HideColumn / ToggleColumn — the last visible
    ; column refuses to hide, so the view can never go blank.
    ShowColumn(key, on := true) {
        i := IsNumber(key) ? Integer(key) : this._ColIndex(key)
        if (!i || !this.Cols.Has(i))
            return this
        if (!on) {
            if !this.Cols[i].Hideable                  ; pinned by the caller
                return this
            left := 0
            for c in this.Cols
                if !c.Hidden
                    left++
            if (left <= 1 && !this.Cols[i].Hidden)
                return this
        }
        this.Cols[i].Hidden := !on
        this.Render()
        return this
    }
    HideColumn(key) => this.ShowColumn(key, false)
    ToggleColumn(key) {
        i := IsNumber(key) ? Integer(key) : this._ColIndex(key)
        return i ? this.ShowColumn(i, this.Cols[i].Hidden) : this
    }
    ShowAllColumns() {
        for c in this.Cols
            c.Hidden := false
        this.Render()
        return this
    }
    VisibleColumns() {
        out := []
        for v in this._Vis()
            out.Push(v.C.Key)
        return out
    }
    ; The header's right-click menu: tick a column to show or hide it.
    ColumnMenu(x := "", y := "") {
        items := []
        for i, c in this.Cols
            items.Push({Label: (c.Hidden ? "      " : "✓   ") c.Title,
                        Click: this._ColFn(i), Disabled: !c.Hideable})
        items.Push("-")
        items.Push(["Size columns to fit", (*) => this.AutoSizeAll()])
        items.Push(["Show all columns", (*) => this.ShowAllColumns()])
        this.W.ShowMenu(items, x, y)
        return this
    }
    _ColFn(i) => (*) => this.ToggleColumn(i)

    ; --- size to fit. The cell text sits in its own inline span, so its layout
    ; box still reports the full width even where the cell clips it.
    AutoSize(i) {
        if (IsNumber(i) = 0)
            i := this._ColIndex(i)
        if (!i || !this.Cols.Has(i))
            return this
        col := this.Cols[i], pos := this._VisPos(i)
        if !pos
            return this
        orn := this._Vis()[pos].Orn
        w := this._Measure(col.Title, true) + 56                  ; sort arrow, grip, padding
        ; Every row used to go through the DOM probe, and each probe forces
        ; Trident to lay the page out -- one forced layout per row per column,
        ; so "size columns to fit" on a long view stalls for as long as it takes
        ; to relayout the page a few thousand times. Score the strings in
        ; AutoHotkey first, which costs no COM at all, and measure only the
        ; handful that could plausibly be the widest.
        cands := []
        for v in this._view {
            if (v.Kind = "group") {
                if orn
                    cands.Push({S: v.Name " " v.Count, H: true, P: 58})
                continue
            }
            row := this._nodes[v.Id].Row
            p := 22
            if orn {
                p += v.Depth * 18
                p += (this._hasTree || this.Tree) ? 18 : 0
                p += this.Checkboxes ? 24 : 0
                p += (this._Val(row, "Icon") != "") ? 24 : 0
            }
            cands.Push({S: this._Text(row, col), H: false, P: p})
        }
        for c in AxDataView._Widest(cands)
            w := Max(w, this._Measure(c.S, c.H) + c.P)
        this._Resize(i, w)                                        ; _Resize clamps to Min/MaxWidth
        return this
    }
    ; How many candidates survive to a real measurement. A view with fewer rows
    ; than this is measured in full, exactly as before.
    static _Cand := 16
    ; Rough proportional width, in character-ish units. This only decides which
    ; strings are worth a DOM measurement -- the width that ends up on the
    ; column still comes from Trident -- so it can afford to be approximate. It
    ; cannot afford to be blind to case, though: ten W's are wider than twenty
    ; l's, and ranking on StrLen alone would miss that and clip the column.
    static _Score(s) {
        if (s = "")
            return 0
        n := StrLen(s)
        wide   := n - StrLen(RegExReplace(s, "[WMQG@%&mw#_]", ""))
        narrow := n - StrLen(RegExReplace(s, "[ijlItf.,:;'!|()\[\] ]", ""))
        return n + wide * 0.7 - narrow * 0.45
    }
    ; Top _Cand entries by score, highest first. One pass, inserting into a list
    ; that never grows past _Cand, so a long view costs no sort.
    static _Widest(cands) {
        if (cands.Length <= AxDataView._Cand)
            return cands
        best := []
        for c in cands {
            sc := AxDataView._Score(c.S) + c.P / 7.0        ; indent and icons count too
            if (best.Length >= AxDataView._Cand && sc <= best[best.Length].Sc)
                continue
            c.Sc := sc
            at := best.Length + 1
            loop best.Length
                if (sc > best[A_Index].Sc) {
                    at := A_Index
                    break
                }
            best.InsertAt(at, c)
            if (best.Length > AxDataView._Cand)
                best.Pop()
        }
        return best
    }
    ; A cell clips its own text, so it cannot be measured where it sits; one
    ; hidden probe span outside the table gives the natural width instead.
    _Measure(text, header := false) {
        if (text = "")
            return 0
        try {
            el := this.W.El(this.Id "_probe")
            if !IsObject(el) {
                this.W.Doc.body.insertAdjacentHTML("beforeend",
                    '<span id="' this.Id '_probe" style="position:absolute;visibility:hidden;'
                    . "white-space:nowrap;top:-9999px;left:-9999px" '"></span>')
                el := this.W.El(this.Id "_probe")
                this._probeHdr := -1                  ; fresh span: styles are back to default
            }
            ; AutoSize calls this once per cell, so the two style writes and the
            ; text write are all on the hot path. The font only changes between
            ; the header row and the body, and innerHTML costs a fifth of
            ; innerText -- escaped, so a "<" in the data cannot change the width
            ; being measured.
            want := header ? 1 : 0
            if (this._probeHdr != want) {
                el.style.fontSize := header ? "12px" : "13px"
                el.style.fontWeight := header ? "600" : "400"
                this._probeHdr := want
            }
            el.innerHTML := AxWindow._Esc(String(text))
            return el.offsetWidth
        }
        return 0
    }
    AutoSizeAll() {
        for i, c in this.Cols
            if !c.Hidden
                this.AutoSize(i)
        return this
    }

    ; --- rows. Every node is stamped with a numeric id, so selection,
    ; checking and expansion survive filtering, sorting and paging.
    SetRows(rows) {
        this._nodes := Map(), this._roots := []
        this._next := 0
        ; the ids start again from 1, so what was picked, ticked or opened
        ; by the old ones would land on whichever new row took that number
        this._sel := Map(), this._chk := Map(), this._open := Map()
        this._cursor := 0, this._anchor := 0
        this._srcRows := IsObject(rows) ? rows : []
        this._Ingest(this._srcRows, 0, 0)
        this._hasTree := false
        for n, node in this._nodes
            if IsObject(node.Kids) {
                this._hasTree := true
                break
            }
        this.Page := 1
        this.Refresh()
        return this
    }
    Rows => this._srcRows
    Reload(rows := "") {
        keep := {Sel: Map(), Chk: Map(), Open: Map(), Cur: "", Anchor: ""}
        for n, node in this._nodes {
            k := String(node.Key)
            if this._sel.Has(n)
                keep.Sel[k] := true
            if this._chk.Has(n)
                keep.Chk[k] := true
            if this._open.Has(n)
                keep.Open[k] := true
            if (n = this._cursor)
                keep.Cur := k
            if (n = this._anchor)
                keep.Anchor := k
        }
        closed := []                                    ; collapsed groups are keyed by name
        for k in this._open
            if (Type(k) = "String" && SubStr(k, 1, 1) = "!")
                closed.Push(k)
        page := this.Page
        this._nodes := Map(), this._roots := [], this._next := 0
        this._sel := Map(), this._chk := Map(), this._open := Map()
        this._cursor := 0, this._anchor := 0
        if IsObject(rows)
            this._srcRows := rows
        this._Ingest(this._srcRows, 0, 0)
        Own(row, name) => (row is Map) ? row.Has(name) : (IsObject(row) && row.HasOwnProp(name))
        for n, node in this._nodes {
            k := String(node.Key), row := node.Row
            if Own(row, "Checked") {
                if !this._Val(row, "Checked")
                    AxDataView._Drop(this._chk, n)
            } else if keep.Chk.Has(k)
                this._chk[n] := true
            if Own(row, "Expanded") {
                if !this._Val(row, "Expanded")
                    AxDataView._Drop(this._open, n)
            } else if keep.Open.Has(k)
                this._open[n] := true
            if (Own(row, "Selected") ? this._Val(row, "Selected") : keep.Sel.Has(k))
                this._sel[n] := true
            if (k = keep.Cur)
                this._cursor := n
            if (k = keep.Anchor)
                this._anchor := n
        }
        for k in closed
            this._open[k] := true
        this._hasTree := false
        for n, node in this._nodes
            if IsObject(node.Kids) {
                this._hasTree := true
                break
            }
        this.Page := page
        this.Refresh()
        return this
    }
    _Ingest(list, parent, depth) {
        for row in list {
            n := ++this._next
            kids := this._Val(row, "Children")
            node := {Id: n, Row: row, Parent: parent, Depth: depth,
                     Kids: (IsObject(kids) && kids.Length) ? [] : "",
                     Key: this._Val(row, "Key")}
            if (node.Key = "")
                node.Key := "n" n
            this._nodes[n] := node
            if parent
                this._nodes[parent].Kids.Push(n)
            else
                this._roots.Push(n)
            if this._Val(row, "Checked")
                this._chk[n] := true
            if (this._Val(row, "Expanded") || this.Opts.HasOwnProp("Expanded") && this.Opts.Expanded)
                this._open[n] := true
            if IsObject(kids)
                this._Ingest(kids, n, depth + 1)
        }
    }
    _Val(row, key) {
        try {
            if (row is Map)
                return row.Has(key) ? row[key] : ""
            return row.HasOwnProp(key) ? row.%key% : ""
        }
        return ""
    }

    ; ------------------------------------------------------------- pipeline
    ; filter -> sort -> group -> flatten -> paginate -> render
    Refresh() {
        keep := this._FilterSet()
        rows := this._SortIds(this._roots.Clone(), keep)
        this._flat := []
        if this._Grouped()
            this._FlattenGrouped(rows, keep)
        else
            this._Flatten(rows, keep, 0)
        total := this._flat.Length
        size := this.PageSize
        pages := size ? Max(1, Ceil(total / size)) : 1
        this.Page := Min(Max(1, this.Page), pages)
        this._pages := pages, this._total := total
        this._view := []
        if size {
            from := (this.Page - 1) * size + 1
            loop Min(size, total - from + 1)
                this._view.Push(this._flat[from + A_Index - 1])
        } else
            this._view := this._flat
        this.Render()
        return this
    }
    ; A node survives the filter when it matches, or an ancestor or descendant
    ; does — so a hit deep in a tree still shows its path.
    _FilterSet() {
        q := Trim(this.Query)
        fn := this.Opts.HasOwnProp("FilterFn") ? this.Opts.FilterFn : ""
        if (q = "" && !fn)
            return ""                                    ; "" means everything
        keep := Map()
        Walk(ids) {
            hit := false
            for n in ids {
                node := this._nodes[n]
                mine := fn ? fn(node.Row, q) : this._Matches(node.Row, q)
                below := IsObject(node.Kids) ? Walk(node.Kids) : false
                if (mine || below) {
                    keep[n] := true, hit := true
                    if below
                        this._open[n] := true            ; open the path to a hit
                }
            }
            return hit
        }
        Walk(this._roots)
        return keep
    }
    _Matches(row, q) {
        for c in this.Cols {
            v := this._Text(row, c)
            if (v != "" && InStr(v, q))
                return true
        }
        return false
    }
    _SortIds(ids, keep) {
        if (this.SortKey = "")
            return ids
        col := ""
        for c in this.Cols
            if (c.Key = this.SortKey)
                col := c
        if !col
            return ids
        arr := []
        for n in ids
            arr.Push(n)
        this._SortArray(arr, col)
        return arr
    }
    ; insertion sort: stable, and these lists are page-sized in practice
    _SortArray(arr, col) {
        dir := this.SortDir
        cmp := (a, b) => this._Cmp(a, b, col) * dir
        loop arr.Length - 1 {
            i := A_Index + 1, v := arr[i], j := i - 1
            while (j >= 1 && cmp(arr[j], v) > 0) {
                arr[j + 1] := arr[j]
                j--
            }
            arr[j + 1] := v
        }
    }
    _Cmp(na, nb, col) {
        ra := this._nodes[na].Row, rb := this._nodes[nb].Row
        if (IsObject(col.Sort) && HasMethod(col.Sort, "Call"))
            return col.Sort(ra, rb)
        a := this._Val(ra, col.Key), b := this._Val(rb, col.Key)
        ; Sort may be true, a name, or a comparator; v2 refuses to compare a
        ; number with a non-numeric string, so settle the type before testing
        kind := (Type(col.Sort) = "String") ? StrLower(col.Sort) : "auto"
        if (kind = "" || kind = "auto")
            kind := (IsNumber(a) && IsNumber(b)) ? "number" : "text"
        if (kind = "number") {
            ; a number column may still hold "n/a" or "12 KB": those count as 0
            a := IsNumber(a) ? Number(a) : 0, b := IsNumber(b) ? Number(b) : 0
            return (a < b) ? -1 : (a > b) ? 1 : 0
        }
        ; v2's < and > are numeric only, so text goes through StrCompare
        return StrCompare(String(a), String(b), false)
    }
    _Flatten(ids, keep, depth) {
        for n in ids {
            if (keep != "" && !keep.Has(n))
                continue
            node := this._nodes[n]
            this._flat.Push({Kind: "row", Id: n, Depth: depth})
            if (IsObject(node.Kids) && this._open.Has(n))
                this._Flatten(this._SortIds(node.Kids.Clone(), keep), keep, depth + 1)
        }
    }
    _FlattenGrouped(ids, keep) {
        g := this.Group
        order := [], bucket := Map()
        for n in ids {
            if (keep != "" && !keep.Has(n))
                continue
            name := (IsObject(g) && HasMethod(g, "Call")) ? g(this._nodes[n].Row)
                                                          : this._Val(this._nodes[n].Row, g)
            name := (name = "") ? "(none)" : String(name)
            if !bucket.Has(name)
                bucket[name] := [], order.Push(name)
            bucket[name].Push(n)
        }
        for name in order {
            gk := "g:" name                                   ; "!" gk marks it collapsed
            this._flat.Push({Kind: "group", Key: gk, Name: name, Count: bucket[name].Length,
                             Depth: 0, Open: !this._open.Has("!" gk)})
            if !this._open.Has("!" gk)                    ; "!" marks a collapsed group
                this._Flatten(bucket[name], keep, 1)
        }
    }

    ; --------------------------------------------------------------- render
    Render() {
        w := this.W, id := this.Id
        vis := this._Vis()
        total := 0, cols := "", head := ""
        for v in vis {
            c := v.C, total += c.Width
            cols .= '<col style="width:' c.Width 'px">'
            sorted := (this.SortKey = c.Key)
            head .= '<th class="dv-hcell' (c.Align != "left" ? " " c.Align : "")
                 .  (c.Sort ? "" : " nosort") (sorted ? " sorted" : "") '" data-c="' v.I '">'
            if (this.Checkboxes && this.ShowCheckAll && v.Orn)
                head .= '<span class="dv-check' this._AllState() '" data-act="all"></span>'
            head .= '<span class="dv-htext">' AxWindow._Esc(c.Title) '</span>'
                 .  '<span class="dv-sort">' (sorted ? (this.SortDir > 0 ? "&#xE70E;" : "&#xE70D;") : "") '</span>'
                 .  '<span class="dv-grip" data-c="' v.I '"></span></th>'
        }
        body := ""
        for i, r in this._view
            body .= this._RowHtml(r, i, vis)
        if !this._view.Length
            body := '<tr><td class="dv-empty" colspan="' vis.Length '">'
                  . AxWindow._Esc(this.Empty) '</td></tr>'
        try {
            w.Html(id "_hcols", cols), w.Html(id "_bcols", cols)
            w.Html(id "_head", head)
            w.Html(id "_body", body)
            w.El(id "_htable").style.width := total "px"
            w.El(id "_btable").style.width := total "px"
            this._Footer()
        }
        return this
    }
    _RowHtml(v, index, vis) {
        E := (x) => AxWindow._Esc(x)
        if (v.Kind = "group") {
            s := '<tr class="dv-row group" data-i="' index '" data-g="' E(v.Key) '">'
            for j, col in vis {
                s .= '<td class="dv-cell' (col.C.Align != "left" ? " " col.C.Align : "") '">'
                if col.Orn
                    s .= '<span class="dv-twisty' (v.Open ? " open" : "") '"></span>'
                      .  '<span class="dv-text">' E(v.Name) '</span>'
                      .  '<span class="dv-gcount">' v.Count '</span>'
                s .= '</td>'
            }
            return s '</tr>'
        }
        node := this._nodes[v.Id], row := node.Row
        cls := "dv-row" (this._sel.Has(v.Id) ? " selected" : "") (this._cursor = v.Id ? " cursor" : "")
        s := '<tr class="' cls '" data-i="' index '" data-n="' v.Id '">'
        for j, col in vis {
            c := col.C
            s .= '<td class="dv-cell' (c.Align != "left" ? " " c.Align : "")
              .  (col.Orn ? "" : " dim") '">'
            if col.Orn {
                if (v.Depth > 0)
                    s .= '<span class="dv-indent" style="width:' (v.Depth * 18) 'px"></span>'
                if (this._hasTree || this.Tree)          ; leaves keep the column, so text lines up
                    s .= '<span class="dv-twisty' (IsObject(node.Kids) ? (this._open.Has(v.Id) ? " open" : "") : " leaf") '"></span>'
                if this.Checkboxes
                    s .= '<span class="dv-check' this._ChkState(v.Id) '" data-act="chk"></span>'
                glyph := this._Val(row, "Icon")
                if (glyph != "")
                    s .= '<span class="ico dv-icon">&#x' E(glyph) ';</span>'
            }
            s .= '<span class="dv-text">' E(this._Text(row, c)) '</span></td>'
        }
        return s '</tr>'
    }
    ; "" | " on" | " some" -- a branch shows a dash while only part of it is ticked
    _ChkState(n) {
        if this._chk.Has(n)
            return " on"
        if (this.CheckTree && IsObject(this._nodes[n].Kids) && this._AnyChecked(n))
            return " some"
        return ""
    }
    _AnyChecked(n) {
        for k in this._nodes[n].Kids {
            if this._chk.Has(k)
                return true
            if (IsObject(this._nodes[k].Kids) && this._AnyChecked(k))
                return true
        }
        return false
    }
    ; ticking a branch ticks everything under it, and every ancestor becomes
    ; ticked exactly when all of its children are
    _CheckTree(n, on) {
        stack := [n]
        while stack.Length {
            m := stack.Pop()
            if on
                this._chk[m] := true
            else
                AxDataView._Drop(this._chk, m)
            if IsObject(this._nodes[m].Kids)
                for k in this._nodes[m].Kids
                    stack.Push(k)
        }
        p := this._nodes[n].Parent
        while p {
            all := true
            for k in this._nodes[p].Kids
                if !this._chk.Has(k)
                    all := false
            if all
                this._chk[p] := true
            else
                AxDataView._Drop(this._chk, p)
            p := this._nodes[p].Parent
        }
    }
    _Text(row, col) {
        v := this._Val(row, col.Key)
        if (IsObject(col.Format) && HasMethod(col.Format, "Call")) {
            f := col.Format
            try return String(f(v, row))
        }
        return String(v)
    }
    _AllState() {
        n := 0, total := 0
        for v in this._flat {
            if (v.Kind != "row")
                continue
            total++
            if this._chk.Has(v.Id)
                n++
        }
        return (total && n = total) ? " on" : (n ? " some" : "")
    }
    _Footer() {
        w := this.W, id := this.Id
        pages := this._pages, size := this.PageSize
        try {
            w.Text(id "_page", this.Page " / " pages)
            from := size ? (this._total ? (this.Page - 1) * size + 1 : 0) : (this._total ? 1 : 0)
            to := size ? Min(this._total, this.Page * size) : this._total
            w.Text(id "_status", this._total
                ? (size ? from "–" to " of " this._total : this._total " row" (this._total = 1 ? "" : "s"))
                  (this._sel.Count ? "   ·   " this._sel.Count " selected" : "")
                  (this.Checkboxes && this._chk.Count ? "   ·   " this._chk.Count " ticked" : "")
                : "nothing to show")
            for b, off in Map(id "_first", 1, id "_prev", 1, id "_next", pages, id "_last", pages)
                AxWindow._SetClass(w.El(b), "disabled", false)
            if (this.Page <= 1)
                for b in [id "_first", id "_prev"]
                    AxWindow._SetClass(w.El(b), "disabled", true)
            if (this.Page >= pages)
                for b in [id "_next", id "_last"]
                    AxWindow._SetClass(w.El(b), "disabled", true)
            w.El(id "_foot").style.display := (size || this._sel.Count || this._chk.Count) ? "flex" : "flex"
            for b in [id "_first", id "_prev", id "_next", id "_last", id "_page"]
                w.El(b).style.display := size ? "" : "none"
            if this.Opts.HasOwnProp("Tools") && !this.Opts.Tools
                return
            w.Text(id "_count", this._total " of " this._nodes.Count)
            vis := (this._Grouped() || this.Tree || this._HasKids()) ? "" : "none"
            for b in [id "_expand", id "_collapse"]
                try w.El(b).style.display := vis
        }
    }
    _HasKids() => this._hasTree
    _Grouped() => IsObject(this.Group) || String(this.Group) != ""

    ; ---------------------------------------------------------------- events
    _Wire() {
        w := this.W, id := this.Id
        w.On("click", id, (el, ev) => this._Click(ev))
        w.On("dblclick", id, (el, ev) => this._DblClick(ev))
        w.On("mousedown", id, (el, ev) => this._Down(ev))
        w.On("keyup", id "_q", (el, ev) => this.Filter(el.value))
        w.On("keydown", id, (el, ev) => this._Key(ev))
        ; the frame shows where the keyboard is
        w.On("focusin", id, (*) => this.W.AddClass(id "_frame", "focus"))
        w.On("focusout", id, (*) => this.W.RemoveClass(id "_frame", "focus"))
        for b, fn in Map("_first", (*) => this.GoPage(1), "_prev", (*) => this.GoPage(this.Page - 1),
                         "_next", (*) => this.GoPage(this.Page + 1), "_last", (*) => this.GoPage(this._pages),
                         "_expand", (*) => this.ExpandAll(), "_collapse", (*) => this.CollapseAll(),
                         "_cols", (*) => this.ColumnMenu())
            w.On("click", id b, fn)
        w.On("contextmenu", id "_head", (el, ev) => this.ColumnMenu(ev.clientX, ev.clientY))
        ; the header has to follow the body's horizontal scroll
        this._scrollFn := (*) => this._SyncScroll()
        try w.El(id "_scroll").attachEvent("onscroll", this._scrollFn)
    }
    _SyncScroll() {
        try this.W.El(this.Id "_headwrap").scrollLeft := this.W.El(this.Id "_scroll").scrollLeft
    }
    ; nearest ancestor carrying that class, without leaving the component
    _Up(el, cls) {
        loop 12 {
            if !IsObject(el)
                return ""
            if AxWindow._HasClass(el, cls)
                return el
            try {
                if (el.id = this.Id)
                    return ""
            }
            el := AxWindow._ParentEl(el)
        }
        return ""
    }
    _Click(ev) {
        try el := ev.srcElement
        catch
            return
        if (chk := this._Up(el, "dv-check")) {
            if (AxWindow._Attr(chk, "data-act") = "all")
                return this.CheckAll(!InStr(" " AxWindow._ClassOf(chk) " ", " on "))
            row := this._Up(chk, "dv-row")
            if row
                return this.Check(Integer(AxWindow._Attr(row, "data-n")), , true)
        }
        if (hc := this._Up(el, "dv-hcell")) {
            if this._Up(el, "dv-grip")
                return
            c := this.Cols[Integer(AxWindow._Attr(hc, "data-c"))]
            if c.Sort
                this.SortBy(c.Key)
            this._Fire("header", [c.Key, this])
            return
        }
        if (tw := this._Up(el, "dv-twisty")) {
            row := this._Up(tw, "dv-row")
            if row
                return this._Toggle(row)
        }
        if (row := this._Up(el, "dv-row")) {
            if AxWindow._HasClass(row, "group")
                return this._Toggle(row)
            n := Integer(AxWindow._Attr(row, "data-n"))
            if (this.Checkboxes && this.CheckMode = "row")
                this.Check(n, , true)
            if (this.Select != "none")
                this._Pick(n, GetKeyState("Ctrl", "P"), GetKeyState("Shift", "P"))
            this.Focus()                    ; so the arrows carry on from here
            if (this.Select = "none")
                this._MoveTo(n, false)      ; no selection, but keep a cursor
            ; The first click draws the row again, so the second lands on a
            ; new element and Trident sends a second click instead of a
            ; dblclick: two clicks on one row in the double-click time are one.
            now := A_TickCount
            if (this.HasOwnProp("_clickN") && this._clickN = n && now - this._clickAt <= DllCall("GetDoubleClickTime", "UInt")) {
                this._clickN := 0, this._dblAt := now
                this._Activate(n)
            } else
                this._clickN := n, this._clickAt := now
        }
    }
    _DblClick(ev) {
        try el := ev.srcElement
        catch
            return
        if (grip := this._Up(el, "dv-grip")) {          ; the classic size-to-fit gesture
            if (this.HasOwnProp("_gripDbl") && A_TickCount - this._gripDbl < 800)
                return                                  ; _Down saw it already
            this.AutoSize(Integer(AxWindow._Attr(grip, "data-c")))
            return
        }
        row := this._Up(el, "dv-row")
        if (!row || AxWindow._HasClass(row, "group"))
            return
        if (this.HasOwnProp("_dblAt") && A_TickCount - this._dblAt < 800)
            return                                      ; _Click saw it already
        this._clickN := 0
        this._Activate(Integer(AxWindow._Attr(row, "data-n")))
    }
    _Activate(n) {
        if !this._nodes.Has(n)
            return
        node := this._nodes[n]
        if IsObject(node.Kids) {
            try {
                rows := this.W.Doc.querySelectorAll("#" this.Id " .dv-row")
                loop rows.length
                    if (AxWindow._Attr(r := rows.item(A_Index - 1), "data-n") = String(n)) {
                        this._Toggle(r)
                        break
                    }
            }
        }
        this._Fire("activate", [node.Row, this])
    }
    _Down(ev) {
        try el := ev.srcElement
        catch
            return
        grip := this._Up(el, "dv-grip")
        if !grip
            return
        i := Integer(AxWindow._Attr(grip, "data-c"))
        from := 0
        try from := ev.clientX
        ; Two presses on one grip in the double-click time are the size-to-fit
        ; gesture, counted here: Trident's own dblclick is lost whenever the
        ; header changed under the pointer between the two, and it took five
        ; tries to get one. A capture from the first press still running (a
        ; fast pair can beat its poll) is dropped, or its release would put
        ; the old width back over the fitted one.
        now := A_TickCount
        if (this.HasOwnProp("_gripAt") && this._gripC = i && Abs(from - this._gripX) <= 4
            && now - this._gripAt <= DllCall("GetDoubleClickTime", "UInt")) {
            this._gripAt := 0, this._gripDbl := now
            this.W.ReleasePointer()
            this._GripEnd(grip)
            this.AutoSize(i)
            return
        }
        this._gripC := i, this._gripAt := now, this._gripX := from
        pos := this._VisPos(i)
        try r := this.W.El(this.Id "_head").children.item(pos - 1).getBoundingClientRect()
        catch
            return
        start := r.right - r.left
        ; nothing on the page changes until the pointer moves: a press that
        ; is half of a double-click leaves the header exactly as it was
        st := {On: false}
        mv := (x, y) => this._GripMove(st, grip, i, start + (x - from), Abs(x - from) >= 2)
        this.W.PointerCapture(mv, (x, y) => (st.On ? (this._Resize(i, start + (x - from)), this._GripEnd(grip),
            this._Fire("resize", [i, this.Cols[i].Width, this])) : 0))
    }
    _GripMove(st, grip, i, width, moved) {
        if (!st.On && !moved)
            return
        if !st.On {
            st.On := true
            AxWindow._SetClass(grip, "active", true)
            this.W.BodyClass("dv-resizing", true)
        }
        this._Resize(i, width)
    }
    _GripEnd(grip) {
        AxWindow._SetClass(grip, "active", false)
        this.W.BodyClass("dv-resizing", false)
    }
    ; one <col> per table, so a drag writes two widths and not one per cell
    _Resize(i, width) {
        c := this.Cols[i]
        c.Width := Min(c.MaxWidth, Max(c.MinWidth, Round(width)))
        pos := this._VisPos(i)
        if !pos
            return
        total := 0
        for v in this._Vis()
            total += v.C.Width
        try {
            for g in [this.Id "_hcols", this.Id "_bcols"]
                this.W.El(g).children.item(pos - 1).style.width := c.Width "px"
            this.W.El(this.Id "_htable").style.width := total "px"
            this.W.El(this.Id "_btable").style.width := total "px"
        }
    }
    ; ------------------------------------------------------------- keyboard
    ; Put the keyboard on the grid. The body carries the tabindex, so this is
    ; what a caller (or a row click) uses to make the arrows live.
    Focus() {
        try this.W.El(this.Id "_scroll").focus()
        return this
    }
    ; the ids of the rows currently on screen, in the order they are drawn
    _RowIds() {
        out := []
        for v in this._view
            if (v.Kind = "row")
                out.Push(v.Id)
        return out
    }
    ; how many rows fit in the body, for PageUp / PageDown
    _PageRows() {
        try {
            sc := this.W.El(this.Id "_scroll")
            r := this.W.Doc.querySelector("#" this.Id " .dv-row")
            if IsObject(r) {
                b := r.getBoundingClientRect()
                h := b.bottom - b.top
                if (h > 0)
                    return Max(1, Floor(sc.clientHeight / h) - 1)
            }
        }
        return 10
    }
    ; keep the cursor row inside the scrolled body
    _ScrollTo(n) {
        try {
            sc := this.W.El(this.Id "_scroll")
            row := this._RowEl(n)
            if !IsObject(row)
                return
            rb := row.getBoundingClientRect(), sb := sc.getBoundingClientRect()
            if (rb.top < sb.top)
                sc.scrollTop := sc.scrollTop - (sb.top - rb.top)
            else if (rb.bottom > sb.bottom)
                sc.scrollTop := sc.scrollTop + (rb.bottom - sb.bottom)
        }
    }
    _RowEl(n) {
        for r in this.W.Doc.querySelectorAll("#" this.Id " .dv-row")
            if (AxWindow._Attr(r, "data-n") = String(n))
                return r
        return ""
    }
    ; move the cursor to a row, selecting it unless the grid takes no selection
    _MoveTo(n, shift := false) {
        if (this.Select = "none") {
            this._cursor := n
            this.Render()
        } else
            this._Pick(n, false, shift)
        this._ScrollTo(n)
    }
    _Key(ev) {
        k := ev.keyCode
        if !this._view.Length
            return
        ctrl := GetKeyState("Ctrl", "P"), shift := GetKeyState("Shift", "P")
        alt := GetKeyState("Alt", "P")
        ids := this._RowIds()
        if !ids.Length
            return
        at := 0
        for i, n in ids
            if (n = this._cursor)
                at := i
        Go(i) {
            if (i < 1)
                i := 1
            if (i > ids.Length)
                i := ids.Length
            this._MoveTo(ids[i], shift)
            ev.returnValue := false
        }
        ; --- Ctrl+A takes the whole page
        if (k = 65 && ctrl) {
            if this.Multi {
                this._sel := Map()
                for n in ids
                    this._sel[n] := true
                this.Render()
                this._Fire("select", [this.Selected(), this])
            }
            ev.returnValue := false
            return
        }
        if (k = 38 || k = 40) {                              ; up / down
            if !at
                return Go(k = 40 ? 1 : ids.Length)
            return Go(at + (k = 40 ? 1 : -1))
        }
        if (k = 36 || k = 35)                                ; home / end
            return Go(k = 36 ? 1 : ids.Length)
        if (k = 33 || k = 34) {                              ; page up / page down
            if !at
                return Go(k = 34 ? 1 : ids.Length)
            return Go(at + (k = 34 ? this._PageRows() : -this._PageRows()))
        }
        if (k = 13 && this._cursor) {                        ; enter activates
            this._Fire("activate", [this._nodes[this._cursor].Row, this])
            ev.returnValue := false
            return
        }
        if (k = 32 && this._cursor && this.Checkboxes) {     ; space ticks
            this.Check(this._cursor, , true)
            ev.returnValue := false
            return
        }
        ; --- left and right walk the tree: open, close, step in, step out
        if ((k = 39 || k = 37) && this._cursor) {
            n := this._cursor, node := this._nodes[n]
            kids := IsObject(node.Kids) && node.Kids.Length
            open := this._open.Has(n)
            if (k = 39) {                                    ; right
                if (kids && !open) {
                    this._open[n] := true
                    this._Fire("expand", [node.Row, true, this])
                    this.Refresh()
                    this._ScrollTo(n)
                } else if (kids && open) {                   ; open already: step in
                    for i, m in ids
                        if (i > at && this._nodes[m].Parent = n) {
                            this._MoveTo(m, shift)
                            break
                        }
                }
            } else {                                         ; left
                if (kids && open) {
                    AxDataView._Drop(this._open, n)
                    this._Fire("expand", [node.Row, false, this])
                    this.Refresh()
                    this._ScrollTo(n)
                } else if (node.Parent && this._nodes.Has(node.Parent))
                    this._MoveTo(node.Parent, shift)         ; step out to the parent
            }
            ev.returnValue := false
            return
        }
        ; --- type to find
        if (this.TypeToFind && !ctrl && !alt) {
            ch := ""
            if (k >= 65 && k <= 90) || (k >= 48 && k <= 57)
                ch := Chr(k)
            else if (k >= 96 && k <= 105)
                ch := Chr(k - 48)
            else if (k = 32 && !this.Checkboxes)
                ch := " "
            if (ch != "") {
                this._Type(ch)
                ev.returnValue := false
                return
            }
            if (k = 8 && this._find != "") {                 ; backspace trims it
                this._find := SubStr(this._find, 1, StrLen(this._find) - 1)
                this._findAt := A_TickCount
                if (this._find != "")
                    this._Seek(this._find, false)
                ev.returnValue := false
                return
            }
            if (k = 27 && this._find != "") {                ; escape drops it
                this._find := ""
                ev.returnValue := false
                return
            }
        }
    }
    ; A character arrived. Within the timeout it extends the search; after it,
    ; it starts a new one. Repeating one character steps through the rows that
    ; begin with it, which is what Explorer does.
    _Type(ch) {
        fresh := (A_TickCount - this._findAt > 900)
        this._findAt := A_TickCount
        if fresh {
            this._find := ch
            this._Seek(ch, true)
        } else if (this._find = ch)
            this._Seek(ch, true)                     ; same letter again: next match
        else {
            this._find .= ch
            this._Seek(this._find, false)
        }
    }
    ; Find a row whose leading column starts with `pre`. `after` starts the
    ; search past the cursor and wraps; without it the cursor row itself is
    ; allowed, so extending a search does not jump off the row it just matched.
    _Seek(pre, after) {
        ids := this._RowIds()
        if !ids.Length
            return false
        at := 0
        for i, n in ids
            if (n = this._cursor)
                at := i
        start := after ? at : at - 1
        loop ids.Length {
            i := Mod(start + A_Index - 1, ids.Length) + 1
            n := ids[i]
            if (SubStr(this._SearchText(n), 1, StrLen(pre)) = pre) {
                this._MoveTo(n, false)
                return true
            }
        }
        return false
    }
    ; what typing matches against: the row's first visible column
    _SearchText(n) {
        for c in this.Cols
            if !c.Hidden
                return StrUpper(String(this._Val(this._nodes[n].Row, c.Key)))
        return ""
    }
    _Toggle(rowEl) {
        g := AxWindow._Attr(rowEl, "data-g")
        if (g != "") {                                        ; a group header
            key := "!" g
            if this._open.Has(key)
                AxDataView._Drop(this._open, key)
            else
                this._open[key] := true
            return this.Refresh()
        }
        n := Integer(AxWindow._Attr(rowEl, "data-n"))
        if !IsObject(this._nodes[n].Kids)
            return
        open := !this._open.Has(n)
        if open
            this._open[n] := true
        else
            AxDataView._Drop(this._open, n)
        this._Fire("expand", [this._nodes[n].Row, open, this])
        this.Refresh()
    }
    _Pick(n, ctrl, shift) {
        if (this.Select = "none")
            return
        if (!this.Multi) {
            this._sel := Map(), this._sel[n] := true
        } else if shift {
            a := this._IndexOf(this._anchor), b := this._IndexOf(n)
            if (a && b) {
                this._sel := Map()
                lo := Min(a, b), hi := Max(a, b)
                loop hi - lo + 1
                    if (this._view[lo + A_Index - 1].Kind = "row")
                        this._sel[this._view[lo + A_Index - 1].Id] := true
            } else
                this._sel[n] := true
        } else if ctrl {
            if this._sel.Has(n)
                AxDataView._Drop(this._sel, n)
            else
                this._sel[n] := true
            this._anchor := n
        } else {
            this._sel := Map(), this._sel[n] := true, this._anchor := n
        }
        if !this._anchor
            this._anchor := n
        this._cursor := n
        this.Render()
        this._Fire("select", [this.Selected(), this])
        try this.W._FireValue(this.W.El(this.Id), this.SelectedKeys())
    }
    _IndexOf(n) {
        for i, v in this._view
            if (v.Kind = "row" && v.Id = n)
                return i
        return 0
    }
    _Fire(name, args) {
        if !this._cbs.Has(name)
            return
        for fn in this._cbs[name].Clone()
            try fn(args*)
    }

    ; ----------------------------------------------------------------- public
    OnSelect(fn)   => (this._cbs["select"].Push(fn), this)
    OnCheck(fn)    => (this._cbs["check"].Push(fn), this)
    OnActivate(fn) => (this._cbs["activate"].Push(fn), this)
    OnSort(fn)     => (this._cbs["sort"].Push(fn), this)
    OnPage(fn)     => (this._cbs["page"].Push(fn), this)
    OnExpand(fn)   => (this._cbs["expand"].Push(fn), this)
    OnExpandAll(fn) => (this._cbs["expandall"].Push(fn), this)
    OnHeader(fn)   => (this._cbs["header"].Push(fn), this)
    OnState(fn)    => (this._cbs["state"].Push(fn), this)

    Filter(text) {
        this.Query := String(text)
        this.Page := 1
        this.Refresh()
        return this
    }
    SortBy(key, dir := "") {
        if (dir = "")
            dir := (this.SortKey = key) ? -this.SortDir : 1
        this.SortKey := key, this.SortDir := dir < 0 ? -1 : 1
        this.Refresh()
        this._Fire("sort", [key, this.SortDir, this])
        return this
    }
    GoPage(n) {
        n := Min(Max(1, Integer(n)), this._pages)
        if (n = this.Page)
            return this
        this.Page := n
        this.Refresh()
        this._Fire("page", [n, this])
        return this
    }
    ExpandAll() {
        for n, node in this._nodes
            if IsObject(node.Kids)
                this._open[n] := true
        for v in this._flat
            if (v.Kind = "group")
                AxDataView._Drop(this._open, "!" v.Key)
        this.Refresh()
        this._Fire("expandall", [true, this])
        return this
    }
    CollapseAll() {
        groups := []
        for v in this._flat
            if (v.Kind = "group")
                groups.Push(v.Key)
        this._open := Map()
        for k in groups
            this._open["!" k] := true
        this.Refresh()
        this._Fire("expandall", [false, this])
        return this
    }
    ; --- selection
    Selected() {
        out := []
        for v in this._flat
            if (v.Kind = "row" && this._sel.Has(v.Id))
                out.Push(this._nodes[v.Id].Row)
        return out
    }
    SelectedKeys() {
        out := []
        for v in this._flat
            if (v.Kind = "row" && this._sel.Has(v.Id))
                out.Push(this._nodes[v.Id].Key)
        return out
    }
    SelectKeys(keys) {
        this._sel := Map()
        want := Map()
        for k in keys
            want[String(k)] := true
        for n, node in this._nodes
            if want.Has(String(node.Key))
                this._sel[n] := true
        this.Render()
        this._Fire("state", [this])
        return this
    }
    ClearSelection() {
        this._sel := Map(), this._cursor := 0
        this.Render()
        this._Fire("state", [this])
        return this
    }
    ; --- checkboxes
    Check(n, on := "", fire := false) {
        if (on = "")
            on := !this._chk.Has(n)
        if this.CheckTree
            this._CheckTree(n, on)
        else if on
            this._chk[n] := true
        else
            AxDataView._Drop(this._chk, n)
        this.Render()
        if fire
            this._Fire("check", [this.CheckedRows(), this])
        else
            this._Fire("state", [this])
        return this
    }
    CheckAll(on := true) {
        for v in this._flat
            if (v.Kind = "row") {
                if on
                    this._chk[v.Id] := true
                else
                    AxDataView._Drop(this._chk, v.Id)
            }
        this.Render()
        this._Fire("check", [this.CheckedRows(), this])
        return this
    }
    CheckedRows() {
        out := []
        for n, node in this._nodes
            if this._chk.Has(n)
                out.Push(node.Row)
        return out
    }
    CheckedKeys() {
        out := []
        for n, node in this._nodes
            if this._chk.Has(n)
                out.Push(node.Key)
        return out
    }
    Value {
        get => this.SelectedKeys()
        set => this.SelectKeys(IsObject(value) ? value : StrSplit(String(value), "|"))
    }
    Count => this._total

    ; ------------------------------------------------------------------ AxGui
    static _Add(container, opts, data) {
        o := container._Opt(opts, "dv")
        cfg := {}
        if IsObject(data)
            for k, v in data.OwnProps()
                cfg.%k% := v
        ; a flag in the option string overrides the data object; where no flag
        ; is present, whatever the caller passed stands
        Set(name, value) => cfg.%name% := value
        Fall(name, value) => cfg.HasOwnProp(name) ? "" : cfg.%name% := value
        if (o.H != "")
            Set("Height", Integer(o.H))
        Fall("Height", 320)
        if o.Flags.Has("noselect")
            Set("Select", "none")
        else if o.Flags.Has("single")
            Set("Select", "single")
        Fall("Select", "multi")
        if (o.Flags.Has("checkboxes") || o.Flags.Has("checks"))
            Set("Checkboxes", true)
        Fall("Checkboxes", false)
        if o.Flags.Has("checkrow")
            Set("CheckMode", "row")
        Fall("CheckMode", "box")
        if o.Flags.Has("checktree")
            Set("CheckTree", true)
        Fall("CheckTree", false)
        if o.Flags.Has("nocheckall")
            Set("CheckAll", false)
        Fall("CheckAll", true)
        if o.Flags.Has("nocolumnmenu")
            Set("ColumnMenu", false)
        Fall("ColumnMenu", true)
        if o.Flags.Has("tree")
            Set("Tree", true)
        Fall("Tree", false)
        if o.Flags.Has("nosearch")
            Set("Search", false)
        Fall("Search", true)
        if o.Flags.Has("notools")
            Set("Tools", false)
        Fall("Tools", true)
        if o.KV.Has("pagesize")
            cfg.PageSize := Integer(o.KV["pagesize"])
        if o.KV.Has("group")
            cfg.Group := o.KV["group"]
        cfg.Style := (o.W != "" ? "width:" o.W "px;" : "") (o.Inline && o.Gap != 8 ? "margin-left:" (o.Gap - 8) "px;" : "")
            . (o.Top != "" ? "margin-top:" o.Top "px;" : "") (o.KV.Has("style") ? o.KV["style"] : "")
        cfg.Class := ((o.W = "" || o.Flags.Has("fill")) ? "fill" : "") (o.KV.Has("class") ? " " o.KV["class"] : "")
        c := container._Reg(o, "DataView", AxDataView.Html(o.Id, cfg))
        container.G.OnReady((w) => AxDataView(w, o.Id, cfg))
        return c
    }
}
