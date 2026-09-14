#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
#Include %A_LineFile%\..\..\DataView\AxDataView.ahk

; =============================================================================
;  AxListView -- AutoHotkey's ListView and TreeView, drawn as a data view.
;
;      lv := g.AddListView("vfiles w420 h260 Checked", ["Name", "Size"])
;      lv.Add(, "readme.md", 1240)
;      lv.ModifyCol(2, "Integer")
;      lv.OnEvent("DoubleClick", (lv, row) => MsgBox(lv.GetText(row)))
;
;      tv := g.AddTreeView("vtree w260 h300")
;      fruit := tv.Add("Fruit")
;      tv.Add("Apple", fruit), tv.Add("Pear", fruit, "Select")
;
;  Everything Gui's two controls answer to is answered the same way here --
;  row numbers and item ids, options, events, before the window is up as
;  well as after -- so a script written for Gui() fills these unchanged.
;  Underneath each is a DataView, so it also sorts, filters, sizes its
;  columns and ticks like one; ctl.Component is that DataView.
;
;  The second argument can be the design's text instead:
;      a list view   the first line is the column titles, each line after it
;                    a row, its cells split by |
;      a tree view   one item a line, indented under the item it belongs to
;  and a line that starts "[x] " is ticked.
;
;  ------------------------------------------------------------------ options
;    Checked      a tick box on every row / item
;    -Multi       one row at a time (a tree is always one at a time)
;    Grid         lines between the cells
;    NoSortHdr    the column titles do not sort
;    -Hdr         no column titles
;    Sort / SortDesc   kept in order of the first column
;    Search       a filter box above it
;    PageSize=N   N rows a page, with a pager under it
;    Expanded     (a tree) items start opened
;
;  ------------------------------------------------------------------- events
;    list   Click(lv, row)  DoubleClick(lv, row)  ColClick(lv, col)
;           ItemSelect(lv, row, selected)  ItemCheck(lv, row, checked)
;           ItemFocus(lv, row)  ContextMenu(lv, row, isRightClick, x, y)
;    tree   Click(tv, id)  DoubleClick(tv, id)  ItemSelect(tv, id)
;           ItemCheck(tv, id, checked)  ItemExpand(tv, id, expanded)
;           ContextMenu(tv, id, isRightClick, x, y)
;  A handler is given as many of those as it takes. The rest (Change, Focus,
;  Blur, KeyDown ...) are the ordinary control's.
;
;  ------------------------------------------------- managing it, in one call
;    RemoveSelected()     the picked rows (a tree: the picked item) go
;    TickAll(on := true)  every row ticked, or none
;    ToText() / FromText(text)   the rows as the design's text, and back
;    SaveTo(path) / LoadFrom(path)   the same text, in a file -- a list that
;                         keeps what was put in it from one run to the next
;    FillFolder(dir, pattern := "*.*")   a list of the files there: name,
;                         size, when each was changed
; =============================================================================
class AxListView {
    static _reg := AxRich.Register("ListView", "", (*) => (
        AxRich.AddMethod("AddListView", (c, o := "", d := "") => AxListView._Add(c, o, d, false)),
        AxRich.AddMethod("AddTreeView", (c, o := "", d := "") => AxListView._Add(c, o, d, true))))

    static _Add(container, opts, data, tree) {
        o := container._Opt(opts, tree ? "tv" : "lv")
        f := o.Flags
        On(name) => f.Has(name) && f[name]
        Off(name) => f.Has("-" name) || (f.Has(name) && !f[name])    ; ParseOpts keeps the - on
        ctl := AxListView.Ctl(container.G, o.Id, tree ? "TreeView" : "ListView", tree)
        ctl._single := tree || Off("multi") || On("single")
        ctl._open := On("expanded") || On("expand")
        ; what it holds to begin with
        if tree
            ctl._FromLines(data)
        else
            ctl._FromText(data)
        header := !tree && !Off("hdr") && !On("noheader")
        tools := On("search") || On("tools")
        foot := o.KV.Has("pagesize") || On("status")
        if On("nosorthdr")
            for c in ctl._cols
                c.Sort := false
        if (!tree && (On("sort") || On("sortdesc")) && ctl._cols.Length)
            ctl._sortKey := ctl._cols[1].Key, ctl._sortDir := On("sortdesc") ? -1 : 1
        cls := (tree ? "tvw" : "lvw") (header ? "" : " nohead") (foot ? "" : " nofoot") (On("grid") ? " gridlines" : "")
        h := (o.H != "") ? Integer(o.H) : (tree ? 240 : 220)
        body := h - 2 - (header ? 34 : 0) - (tools ? 42 : 0) - (foot ? 36 : 0)
        cfg := {Columns: ctl._DvCols(), Rows: ctl._Data(), Tree: tree, Preview: true, Fixed: true,
                Height: Max(40, body), Select: On("noselect") ? "none" : ctl._single ? "single" : "multi",
                Checkboxes: On("checked") || On("checkboxes"), CheckTree: On("checktree"), CheckAll: !tree,
                Search: tools, Tools: tools, ColumnMenu: !tree && header, Empty: "",
                Style: (o.W != "" ? "width:" o.W "px;" : "") (o.Inline && o.Gap != 8 ? "margin-left:" (o.Gap - 8) "px;" : "")
                    . (o.Top != "" ? "margin-top:" o.Top "px;" : "") (o.KV.Has("style") ? o.KV["style"] : ""),
                Class: Trim(cls ((o.W = "" || f.Has("fill")) ? " fill" : "") (o.KV.Has("class") ? " " o.KV["class"] : ""))}
        if o.KV.Has("pagesize")
            cfg.PageSize := Integer(o.KV["pagesize"])
        if (ctl._sortKey != "")
            cfg.Sort := {Key: ctl._sortKey, Dir: ctl._sortDir}
        container._Reg(o, tree ? "TreeView" : "ListView", AxDataView.Html(o.Id, cfg))
        container.G._controls[o.Id] := ctl          ; this one, not the plain control _Reg made
        container.G.OnReady((w) => ctl._Ready(w, cfg))
        return ctl
    }

    ; A handler is handed as many of the arguments as it takes, so one
    ; written (ctl, row) and one written (ctl, ev, el) both work.
    static _Call(fn, args) => AxGuiCompat.CallFit(fn, args)
    static _Throw(e) {
        throw e
    }
    ; a tree's ids are numbers; "5" from an edit box is the same item
    static _Id(x) => (IsObject(x) || !IsInteger(x)) ? x : Integer(x)
    ; "Check -Select Col2 Icon3 Expand0" -> [{W: "check", On: true, N: ""}, ...]
    static _Words(opts) {
        out := []
        for tok in StrSplit(Trim(String(opts)), [" ", "`t"]) {
            if (tok = "")
                continue
            on := SubStr(tok, 1, 1) != "-"
            t := LTrim(tok, "+-")
            if IsInteger(t) {
                out.Push({W: "", On: on, N: Integer(t)})
                continue
            }
            if !RegExMatch(t, "i)^([a-z]+)(-?\d*)$", &m)
                continue
            n := m[2]
            if (n = "0")
                on := false
            out.Push({W: StrLower(m[1]), On: on, N: n})
        }
        return out
    }

    ; ======================================================================
    class Ctl extends AxGui.Control {
        __New(g, id, type, tree) {
            super.__New(g, id, type)
            this._tree := tree, this._single := tree, this._open := false
            this._cols := [], this._colN := 0
            this._rows := [], this._next := 0             ; a list: its rows, in the order they came
            this._items := Map(), this._roots := []       ; a tree: id -> item, and the top ones
            this._dv := "", this._redraw := true, this._due := false
            this._flushFn := ObjBindMethod(this, "_Flush")
            this._focus := "", this._scroll := "", this._auto := Map()
            this._sortKey := "", this._sortDir := 1, this._viewC := "", this._flatC := "", this._refC := ""
            this._colsDirty := false, this._sortPush := false
            this._evs := Map()
        }

        ; ------------------------------------------------ what it starts with
        _FromText(data) {
            titles := [], lines := []
            if (data is Array)
                titles := data
            else {
                all := StrSplit(StrReplace(String(data), "`r"), "`n")
                while (all.Length && Trim(all[1]) = "")
                    all.RemoveAt(1)
                if all.Length {
                    titles := AxListView.Ctl._Cells(all.RemoveAt(1))
                    lines := all
                }
            }
            for t in titles
                this._cols.Push(this._NewCol(String(t)))
            for txt in lines {
                if (Trim(txt) = "")
                    continue
                tick := this._Tick(&txt)
                r := this._NewRow(AxListView.Ctl._Cells(txt))
                r.Checked := tick
                this._rows.Push(r)
            }
            this._Guess()
        }
        static _Cells(line) {
            parts := StrSplit(line, InStr(line, "|") ? "|" : InStr(line, "`t") ? "`t" : "|")
            out := []
            for p in parts
                out.Push(Trim(p))
            return out
        }
        ; "[x] " ticks a line, "[+] " opens it (a tree), "[x+] " both
        _Tick(&txt, &open := 0) {
            if RegExMatch(txt, "i)^\s*\[(x?)(\+?)\]\s?", &m) {
                txt := SubStr(txt, m.Len + 1)
                open := (m[2] != "")
                return (m[1] != "") ? 1 : 0
            }
            if RegExMatch(txt, "^\s*\[ \]\s?", &m)
                txt := SubStr(txt, m.Len + 1)
            return 0
        }
        _FromLines(data) {
            this._cols.Push(this._NewCol("Name"))
            if (data is Array || Trim(String(data)) = "")
                return
            stack := []
            for txt in StrSplit(StrReplace(String(data), "`r"), "`n") {
                if (Trim(txt) = "")
                    continue
                RegExMatch(txt, "^[ \t]*", &m)
                depth := StrLen(StrReplace(m[0], "`t", "    "))
                txt := SubStr(txt, m.Len + 1)
                open := 0
                tick := this._Tick(&txt, &open)
                while (stack.Length && stack[stack.Length].D >= depth)
                    stack.Pop()
                id := this._TvAdd(RTrim(txt), stack.Length ? stack[stack.Length].Id : 0,
                                  (tick ? "Check " : "") (open ? "Expand" : ""))
                stack.Push({D: depth, Id: id})
            }
        }
        ; column widths from what is in them, as near as text can say
        _Guess() {
            for i, c in this._cols {
                w := StrLen(c.Title)
                for r in this._rows
                    if r.HasOwnProp(c.Key)
                        w := Max(w, StrLen(String(r.%c.Key%)))
                c.Width := Min(360, Max(64, w * 7 + 34 + (i = 1 ? 28 : 0)))
            }
        }
        _NewCol(title) => {Key: "c" (++this._colN), Title: title, Width: Min(360, Max(64, StrLen(title) * 7 + 40)),
                           Align: "left", Sort: true}
        _NewRow(cells) {
            r := {Key: "r" (++this._next), Checked: 0, Selected: 0}
            for i, v in cells
                if (i <= this._cols.Length)
                    r.%this._cols[i].Key% := v
            return r
        }
        ; what the DataView is handed: copies of the columns, and the rows themselves
        _DvCols() {
            out := []
            for c in this._cols
                out.Push({Key: c.Key, Title: c.Title, Width: c.Width, Align: c.Align, Sort: c.Sort})
            return out
        }
        _Data() => this._tree ? this._roots : this._rows

        ; ------------------------------------------------------- the window
        _Ready(w, cfg) {
            cfg.Columns := this._DvCols(), cfg.Rows := this._Data()
            if (this._sortKey != "")
                cfg.Sort := {Key: this._sortKey, Dir: this._sortDir}
            dv := AxDataView(w, this.Id, cfg)
            this._dv := dv
            dv.OnSelect((rows, d) => this._OnSelect(rows))
            dv.OnCheck((rows, d) => this._OnCheck())
            dv.OnActivate((row, d) => this._Fire("doubleclick", this._Ref(row)))
            dv.OnSort((key, dir, d) => this._OnSort(key, dir))
            dv.OnHeader((key, d) => this._OnHeader(key))
            dv.OnState((d) => this._OnState())
            dv.OnExpand((row, open, d) => this._OnExpand(row, open))
            dv.OnExpandAll((open, d) => this._OnExpandAll(open))
            ; one handler to an element: the grid's own click runs, then Gui's
            try {
                prev := w.Hooks["click"][this.Id]
                w.On("click", this.Id, (el, ev) => (prev.Call(el, ev), this._OnClick(ev)))
            }
            w.On("contextmenu", this.Id, (el, ev) => this._OnMenu(ev))
            ; the grid has these on the same element: Focus, Blur, KeyDown and
            ; MouseDown handlers run after its own, not instead of them
            for kind, name in Map("focusin", "focus", "focusout", "blur", "keydown", "keydown", "mousedown", "mousedown")
                this._Chain(w, kind, name)
            this._colsDirty := false
            this._Flush()
        }
        ; Something changed: the grid is drawn again once the script is done
        ; for the moment, so a thousand Add()s in a row draw it once, not a
        ; thousand times. -Redraw holds it until +Redraw.
        _Changed(now := false, keepView := false) {
            if !keepView
                this._viewC := ""
            this._flatC := "", this._refC := ""
            if (!IsObject(this._dv) || !this._redraw)
                return
            if now
                return this._Flush()
            if this._due
                return
            this._due := true
            SetTimer(this._flushFn, -10)
        }
        _Flush() {
            this._due := false
            dv := this._dv
            if !IsObject(dv)
                return
            if this._colsDirty {
                ; a width the user dragged, and a column they hid, stay
                for dc in dv.Cols
                    for c in this._cols
                        if (c.Key = dc.Key) {
                            if !c.HasOwnProp("_set")
                                c.Width := dc.Width
                            c.Hidden := dc.Hidden
                        }
                cols := this._DvCols()
                for i, c in this._cols {
                    if c.HasOwnProp("Hidden")
                        cols[i].Hidden := c.Hidden
                    if c.HasOwnProp("_set")
                        c.DeleteProp("_set")
                }
                dv.SetColumns(cols, false)
                this._colsDirty := false
            }
            if this._sortPush {
                dv.SortKey := this._sortKey, dv.SortDir := this._sortDir
                this._sortPush := false
            }
            dv.Reload(this._Data())
            if IsObject(this._focus) {
                n := this._NodeOf(this._focus)
                if (n && n != dv._cursor) {
                    dv._cursor := n
                    dv.Render()
                }
            }
            if this._auto.Count {
                for i, c in this._cols
                    if this._auto.Has(c.Key)
                        dv.AutoSize(i)
                this._auto := Map()
            }
            if IsObject(this._scroll) {
                n := this._NodeOf(this._scroll)
                this._scroll := ""
                if n
                    dv._ScrollTo(n)
            }
        }
        _Chain(w, kind, name) {
            prev := ""
            try prev := w.Hooks[kind][this.Id]
            w.On(kind, this.Id, (el, ev) => (IsObject(prev) ? prev.Call(el, ev) : "", this._Fire(name, ev, el)))
        }
        _NodeOf(row) {
            for n, node in this._dv._nodes
                if (node.Row == row)
                    return n
            return 0
        }

        ; ------------------------------------------------ what the user did
        _OnSelect(rows) {
            ; from the grid's own record, not `rows`: that leaves out a picked
            ; row the filter is hiding, which is still picked
            dv := this._dv
            now := Map()
            for n in dv._sel
                if dv._nodes.Has(n)
                    now[dv._nodes[n].Row] := true
            changed := []
            for r in this._All()
                if (!!r.Selected != now.Has(r)) {
                    r.Selected := now.Has(r) ? 1 : 0
                    changed.Push(r)
                }
            cur := (dv._cursor && dv._nodes.Has(dv._cursor)) ? dv._nodes[dv._cursor].Row : ""
            if (IsObject(cur) && !(cur == this._focus)) {
                this._focus := cur
                if !this._tree
                    this._Fire("itemfocus", this._Ref(cur))
            }
            for r in changed                             ; the ones let go first, as Gui does
                if !r.Selected && !this._tree
                    this._Fire("itemselect", this._Ref(r), 0)
            for r in changed
                if (r.Selected && this._tree)
                    this._Fire("itemselect", r.Key)
                else if r.Selected
                    this._Fire("itemselect", this._Ref(r), 1)
        }
        _OnCheck() {
            dv := this._dv
            for n, node in dv._nodes {
                r := node.Row, on := dv._chk.Has(n) ? 1 : 0
                if (on != (r.Checked ? 1 : 0)) {
                    r.Checked := on
                    this._Fire("itemcheck", this._Ref(r), on)
                }
            }
        }
        _OnSort(key, dir) {
            this._sortKey := key, this._sortDir := dir, this._viewC := "", this._refC := ""
        }
        ; code went to the grid itself (ctl.Component.Check / SelectKeys /
        ; ClearSelection): the rows take what the grid now shows, so the
        ; next redraw keeps it rather than putting the old picture back
        _OnState() {
            dv := this._dv
            for n, node in dv._nodes {
                node.Row.Selected := dv._sel.Has(n) ? 1 : 0
                node.Row.Checked := dv._chk.Has(n) ? 1 : 0
            }
        }
        _OnHeader(key) {                                 ; with NoSortHdr too, as Gui's
            for i, c in this._cols
                if (c.Key = key)
                    this._Fire("colclick", i)
        }
        _OnExpand(row, open) {
            row.Expanded := open ? 1 : 0
            this._flatC := ""
            this._Fire("itemexpand", row.Key, open ? 1 : 0)
        }
        _OnExpandAll(open) {
            for id, it in this._items
                if it.Children.Length
                    it.Expanded := open ? 1 : 0
        }
        _OnClick(ev) {
            if this._evs.Has("click")
                this._Fire("click", this._Ref(this._RowAtEl(ev)))
        }
        _OnMenu(ev) {
            if !(this._evs.Has("contextmenu") && this._evs["contextmenu"].Length)
                return
            row := this._RowAtEl(ev)
            ; a right click picks what it lands on, as it does in Explorer
            if (IsObject(row) && !row.Selected) {
                n := this._NodeOf(row)
                if n
                    this._dv._Pick(n, false, false)
            }
            try ev.returnValue := false
            x := 0, y := 0
            try x := ev.clientX, y := ev.clientY
            this._Fire("contextmenu", this._Ref(row), 1, x, y)
        }
        _RowAtEl(ev) {
            try {
                tr := this._dv._Up(ev.srcElement, "dv-row")
                if (tr && !AxWindow._HasClass(tr, "group")) {
                    n := Integer(AxWindow._Attr(tr, "data-n"))
                    if this._dv._nodes.Has(n)
                        return this._dv._nodes[n].Row
                }
            }
            return ""
        }
        ; The grid calls these inside a try, which would swallow a mistake in a
        ; handler without a word; it is thrown again once the grid is done.
        _Fire(name, args*) {
            if !this._evs.Has(name)
                return
            for fn in this._evs[name].Clone() {
                try {
                    AxListView._Call(fn, [this, args*])
                } catch as e {
                    SetTimer(AxListView._Throw.Bind(AxListView, e), -1)
                }
            }
        }
        ; a row's number (a list) or its id (a tree); 0 for none
        _Ref(row) {
            if !IsObject(row)
                return 0
            if this._tree
                return row.Key
            ; row -> number, once per change: a thousand ticks at once would
            ; otherwise be a thousand walks down a thousand rows
            if !IsObject(this._refC) {
                this._refC := Map()
                for i, r in this._View()
                    this._refC[r] := i
            }
            return this._refC.Has(row) ? this._refC[row] : 0
        }

        ; ------------------------------------------------------ Gui's words
        OnEvent(name, fn, add := 1) {
            static mine := " click doubleclick itemselect itemcheck itemfocus colclick itemexpand contextmenu itemedit "
                         .  "focus blur losefocus keydown mousedown "
            k := StrLower(name)
            if (k = "losefocus")
                k := "blur"
            if !InStr(mine, " " k " ")
                return super.OnEvent(name, fn)
            if (fn is String)                            ; Gui(, , obj): its method by name
                fn := AxGuiCompat.Named(this.G, fn)
            if !this._evs.Has(k)
                this._evs[k] := []
            list := this._evs[k]
            if (add = 0) {
                for i, f in list
                    if (f == fn) {
                        list.RemoveAt(i)
                        break
                    }
            } else if (add < 0)
                list.InsertAt(1, fn)
            else
                list.Push(fn)
            return this
        }
        Opt(opts) {
            if RegExMatch(opts, "i)(^|\s)-Redraw\b")
                this._redraw := false
            else if RegExMatch(opts, "i)(^|\s)\+?Redraw\b") {
                this._redraw := true
                this._Changed(true)
            }
            return super.Opt(opts)
        }
        SetImageList(*) => 0

        ; Add: a list takes (options, cells*); a tree (name, parent, options)
        Add(p*) {
            if this._tree
                return this._TvAdd(p.Has(1) ? p[1] : "", p.Has(2) ? p[2] : 0, p.Has(3) ? p[3] : "")
            opts := p.Has(1) ? p[1] : ""
            cells := []
            loop p.Length - 1
                cells.Push(p.Has(A_Index + 1) ? p[A_Index + 1] : "")
            return this._LvInsert(this._rows.Length + 1, opts, cells)
        }
        Insert(row, opts := "", cells*) {
            list := []
            loop cells.Length
                list.Push(cells.Has(A_Index) ? cells[A_Index] : "")
            return this._LvInsert(row, opts, list)
        }
        _LvInsert(at, opts, cells) {
            r := this._NewRow(cells)
            this._RowOpts(r, opts)
            if (this._sortKey = "") {
                if (at >= 1 && at <= this._rows.Length)
                    this._rows.InsertAt(at, r)
                else
                    this._rows.Push(r), at := this._rows.Length
                this._Changed()
                return at
            }
            ; sorted: it goes where it sorts to, found with one walk -- not a
            ; fresh sort of every row for every row added
            view := this._View()
            this._rows.Push(r)
            if (view == this._rows) {                    ; sorted by a column no longer there
                this._Changed()
                return this._rows.Length
            }
            pos := view.Length + 1
            for i, x in view
                if (this._CmpRows(x, r) * this._sortDir > 0) {
                    pos := i
                    break
                }
            view.InsertAt(pos, r)
            this._Changed(false, true)
            return pos
        }
        ; Modify: a list's (row, options, cells*) -- row 0 is every row;
        ; a tree's (id, options, name) -- an id alone selects it
        Modify(ref, opts := "", more*) {
            if this._tree {
                ref := AxListView._Id(ref)
                if !this._items.Has(ref)
                    return 0
                it := this._items[ref]
                if (opts = "" && !more.Length)
                    opts := "Select"
                if (more.Length && more.Has(1))
                    it.c1 := String(more[1])
                this._TvOpts(it, opts, false)
                this._Changed()
                return ref
            }
            targets := []
            if (ref = 0)
                targets := this._rows.Clone()
            else {
                r := this._RowAt(ref)
                if !IsObject(r)
                    return 0
                targets.Push(r)
            }
            from := 1
            for x in AxListView._Words(opts)
                if (x.W = "col" && IsInteger(x.N))
                    from := Integer(x.N)
            for r in targets {
                this._RowOpts(r, opts)
                loop more.Length
                    if (more.Has(A_Index) && from + A_Index - 1 <= this._cols.Length)
                        r.%this._cols[from + A_Index - 1].Key% := more[A_Index]
            }
            this._Changed()
            return 1
        }
        Delete(ref?) {
            if IsSet(ref) && this._tree
                ref := AxListView._Id(ref)
            if !IsSet(ref) {
                this._rows := [], this._items := Map(), this._roots := [], this._focus := ""
                this._Changed()
                return 1
            }
            if this._tree {
                if !this._items.Has(ref)
                    return 0
                it := this._items[ref]
                sibs := this._Sibs(it)
                for i, x in sibs
                    if (x == it) {
                        sibs.RemoveAt(i)
                        break
                    }
                this._Forget(it)
                this._Changed()
                return 1
            }
            r := this._RowAt(ref)
            if !IsObject(r)
                return 0
            for i, x in this._rows
                if (x == r) {
                    this._rows.RemoveAt(i)
                    break
                }
            if (r == this._focus)
                this._focus := ""
            this._Changed()
            return 1
        }
        ; ------------------------------------------- managing it, in one call
        RemoveSelected() {
            n := 0
            if this._tree {
                if (id := this.GetSelection())
                    this.Delete(id), n := 1
                return n
            }
            keep := []
            for r in this._rows
                if r.Selected
                    n++
                else
                    keep.Push(r)
            if n {
                if (IsObject(this._focus) && this._focus.Selected)
                    this._focus := ""
                this._rows := keep
                this._Changed()
            }
            return n
        }
        TickAll(on := true) {
            for r in this._All()
                r.Checked := on ? 1 : 0
            this._Changed()
            return this
        }
        Clear() => this.Delete()
        ; the rows as the design's text: titles, then a row a line ("[x] " ticked);
        ; a tree: an item a line, indented under its own ("[+] " open)
        ToText() {
            Cell := (v) => StrReplace(StrReplace(String(v), "|", "/"), "`n", " ")
            Lines(list, pad) {
                s := ""
                for it in list {
                    mark := (it.Checked || it.Expanded) ? "[" (it.Checked ? "x" : "") (it.Expanded ? "+" : "") "] " : ""
                    s .= pad mark Cell(it.c1) "`n" Lines(it.Children, pad "    ")
                }
                return s
            }
            if this._tree
                return RTrim(Lines(this._roots, ""), "`n")
            out := ""
            for i, c in this._cols
                out .= (i = 1 ? "" : " | ") Cell(c.Title)
            for r in this._View() {
                line := ""
                for i, c in this._cols
                    line .= (i = 1 ? "" : " | ") Cell(r.HasOwnProp(c.Key) ? r.%c.Key% : "")
                out .= "`n" (r.Checked ? "[x] " : "") line
            }
            return out
        }
        FromText(text) {
            this._focus := "", this._scroll := ""
            if this._tree {
                this._items := Map(), this._roots := []
                if !this._cols.Length
                    this._cols.Push(this._NewCol("Name"))
                stack := []
                for txt in StrSplit(StrReplace(String(text), "`r"), "`n") {
                    if (Trim(txt) = "")
                        continue
                    RegExMatch(txt, "^[ \t]*", &m)
                    depth := StrLen(StrReplace(m[0], "`t", "    "))
                    txt := SubStr(txt, m.Len + 1)
                    open := 0
                    tick := this._Tick(&txt, &open)
                    while (stack.Length && stack[stack.Length].D >= depth)
                        stack.Pop()
                    id := this._TvAdd(RTrim(txt), stack.Length ? stack[stack.Length].Id : 0,
                                      (tick ? "Check " : "") (open ? "Expand" : ""))
                    stack.Push({D: depth, Id: id})
                }
            } else {
                sortKey := this._sortKey, sortAt := 0
                for i, c in this._cols
                    if (c.Key = sortKey)
                        sortAt := i
                this._cols := [], this._colN := 0, this._rows := []
                this._FromText(String(text))
                ; still sorted by the same column, when there is one
                this._sortKey := (sortAt && sortAt <= this._cols.Length) ? this._cols[sortAt].Key : ""
                this._sortPush := true, this._colsDirty := true
            }
            this._Changed()
            return this
        }
        SaveTo(path) {
            try {
                f := FileOpen(path, "w", "UTF-8")
                f.Write(this.ToText())
                f.Close()
                return true
            }
            return false
        }
        LoadFrom(path) {
            if !FileExist(path)
                return false
            this.FromText(FileRead(path, "UTF-8"))
            return true
        }
        FillFolder(dir, pattern := "*.*") {
            if this._tree {
                this.Delete()
                loop files dir "\" pattern, "FD"
                    this.Add(A_LoopFileName)
                return this
            }
            this._cols := [], this._colN := 0, this._rows := []
            for t in ["Name", "Size", "Modified"]
                this._cols.Push(this._NewCol(t))
            this._cols[2].Sort := "number", this._cols[2].Align := "right"
            loop files dir "\" pattern, "F"
                this._rows.Push(this._NewRow([A_LoopFileName, A_LoopFileSize,
                    FormatTime(A_LoopFileTimeModified, "yyyy-MM-dd HH:mm")]))
            this._Guess()
            this._sortKey := "", this._sortPush := true, this._colsDirty := true
            this._auto["c1"] := true
            this._Changed()
            return this
        }
        _Forget(it) {
            this._items.Delete(it.Key)
            if (it == this._focus)
                this._focus := ""
            for k in it.Children
                this._Forget(k)
        }
        GetCount(mode := "") {
            m := StrLower(SubStr(String(mode), 1, 1))
            if (m = "c")
                return this._cols.Length
            if (m = "s") {
                n := 0
                for r in this._All()
                    if r.Selected
                        n++
                return n
            }
            return this._tree ? this._items.Count : this._rows.Length
        }
        ; GetNext: a list's next selected (or "C"hecked, "F"ocused) row after
        ; the one given; a tree's next sibling, or with "Full" / "Checked" the
        ; next item going down the whole tree
        GetNext(ref := 0, mode := "") {
            ref := AxListView._Id(ref)
            m := StrLower(SubStr(String(mode), 1, 1))
            if this._tree {
                if (m = "") {
                    if (ref = 0)
                        return this._roots.Length ? this._roots[1].Key : 0
                    if !this._items.Has(ref)
                        return 0
                    sibs := this._Sibs(this._items[ref])
                    for i, x in sibs
                        if (x.Key = ref)
                            return (i < sibs.Length) ? sibs[i + 1].Key : 0
                    return 0
                }
                past := (ref = 0)
                for it in this._Flat() {
                    if !past {
                        past := (it.Key = ref)
                        continue
                    }
                    if (m != "c" || it.Checked)
                        return it.Key
                }
                return 0
            }
            view := this._View()
            if (m = "f")
                return (IsObject(this._focus) && (i := this._Ref(this._focus)) > ref) ? i : 0
            loop view.Length - Max(0, ref) {
                i := Max(0, ref) + A_Index, r := view[i]
                if (m = "c" ? r.Checked : r.Selected)
                    return i
            }
            return 0
        }
        GetText(ref, col := 1) {
            ref := AxListView._Id(ref)
            if this._tree
                return this._items.Has(ref) ? String(this._items[ref].c1) : ""
            if (col < 1 || col > this._cols.Length)
                return ""
            if (ref = 0)
                return this._cols[col].Title
            r := this._RowAt(ref)
            k := this._cols[col].Key
            return (IsObject(r) && r.HasOwnProp(k)) ? String(r.%k%) : ""
        }

        ; --- a list's columns
        ModifyCol(col?, opts := "", title?) {
            this._viewC := ""
            if !IsSet(col) {
                for c in this._cols
                    this._auto[c.Key] := true
                this._Changed()
                return 1
            }
            if (col < 1 || col > this._cols.Length)
                return 0
            c := this._cols[col]
            if IsSet(title)
                c.Title := String(title)
            if (opts = "" && !IsSet(title))
                this._auto[c.Key] := true               ; ModifyCol(n) alone fits it
            for x in AxListView._Words(opts) {
                switch x.W {
                case "":
                    c.Width := x.N, c._set := true
                case "auto", "autohdr":
                    this._auto[c.Key] := true
                case "integer", "float", "number":
                    c.Sort := "number", c.Align := "right"
                case "text":
                    c.Sort := "text", c.Align := "left"
                case "left", "right", "center":
                    c.Align := x.W
                case "nosort":
                    c.Sort := false
                case "sort", "sortdesc":
                    this._sortKey := c.Key, this._sortDir := (x.W = "sortdesc") ? -1 : 1
                    this._sortPush := true
                }
            }
            this._colsDirty := true
            this._Changed()
            return 1
        }
        InsertCol(col, opts := "", title := "") {
            c := this._NewCol(String(title))
            at := (col >= 1 && col <= this._cols.Length) ? col : this._cols.Length + 1
            this._cols.InsertAt(at, c)
            this._colsDirty := true
            if (opts != "")
                this.ModifyCol(at, opts)
            this._Changed()
            return at
        }
        DeleteCol(col) {
            if (col < 1 || col > this._cols.Length)
                return 0
            if (this._cols[col].Key = this._sortKey)      ; its sort goes with it
                this._sortKey := "", this._sortPush := true
            this._cols.RemoveAt(col)
            this._colsDirty := true
            this._Changed()
            return 1
        }

        ; --- a tree's items
        _TvAdd(name, parent := 0, opts := "") {
            id := ++this._next
            parent := AxListView._Id(parent)
            it := {Key: id, c1: String(name), Children: [], Checked: 0, Expanded: this._open ? 1 : 0,
                   Selected: 0, _p: this._items.Has(parent) ? parent : 0, _b: 0}
            sibs := it._p ? this._items[it._p].Children : this._roots
            at := sibs.Length + 1
            for x in AxListView._Words(opts) {
                if (x.W = "first") {
                    at := 1
                } else if (x.W = "" && x.N != 0) {       ; an id: go in after it
                    for i, s in sibs
                        if (s.Key = x.N)
                            at := i + 1
                } else if (x.W = "sort") {
                    at := sibs.Length + 1
                    for i, s in sibs
                        if (StrCompare(s.c1, it.c1) > 0) {
                            at := i
                            break
                        }
                }
            }
            sibs.InsertAt(at, it)
            this._items[id] := it
            this._TvOpts(it, opts, true)
            this._Changed()
            return id
        }
        _TvOpts(it, opts, isNew) {
            for x in AxListView._Words(opts) {
                switch x.W {
                case "check":
                    it.Checked := x.On ? 1 : 0
                case "expand":
                    it.Expanded := x.On ? 1 : 0
                case "bold":
                    it._b := x.On ? 1 : 0
                case "select":
                    if x.On
                        this._Pick(it)
                    else
                        it.Selected := 0
                case "vis", "visfirst":
                    this._Show(it)
                }
            }
        }
        ; open the branches above it and bring it into view
        _Show(it) {
            p := it._p
            while (p && this._items.Has(p)) {
                this._items[p].Expanded := 1
                p := this._items[p]._p
            }
            this._scroll := it
        }
        _Sibs(it) => (it._p && this._items.Has(it._p)) ? this._items[it._p].Children : this._roots
        GetSelection() {
            for id, it in this._items
                if it.Selected
                    return id
            return 0
        }
        GetParent(id) => this._items.Has(id := AxListView._Id(id)) ? this._items[id]._p : 0
        GetChild(id) {
            id := AxListView._Id(id)
            if (id = 0)
                return this._roots.Length ? this._roots[1].Key : 0
            return (this._items.Has(id) && this._items[id].Children.Length) ? this._items[id].Children[1].Key : 0
        }
        GetPrev(id) {
            id := AxListView._Id(id)
            if !this._items.Has(id)
                return 0
            sibs := this._Sibs(this._items[id])
            for i, x in sibs
                if (x.Key = id)
                    return (i > 1) ? sibs[i - 1].Key : 0
            return 0
        }
        Get(id, attr) {
            id := AxListView._Id(id)
            if !this._items.Has(id)
                return 0
            it := this._items[id]
            switch StrLower(SubStr(attr, 1, 1)) {
            case "e": return it.Expanded ? id : 0
            case "c": return it.Checked ? id : 0
            case "b": return it._b ? id : 0
            }
            return 0
        }
        ; every item going down the tree, closed branches included
        _Flat() {
            if IsObject(this._flatC)
                return this._flatC
            out := []
            Walk(list) {
                for it in list {
                    out.Push(it)
                    Walk(it.Children)
                }
            }
            Walk(this._roots)
            return this._flatC := out
        }

        ; --- the value, the text
        Value {
            get => this._tree ? this.GetSelection() : this.G.Value(this.Id)
            set {
                if this._tree {
                    if this._items.Has(v := AxListView._Id(value)) {
                        this._Pick(this._items[v])
                        this._Changed()
                    }
                    return
                }
                ; the rows say what is picked, so the rows are what change
                want := Map()
                for k in (IsObject(value) ? value : StrSplit(String(value), "|"))
                    want[String(k)] := true
                for r in this._rows
                    r.Selected := want.Has(String(r.Key)) ? 1 : 0
                this._Changed()
            }
        }
        Text {
            get {
                if this._tree
                    return this.GetText(this.GetSelection())
                r := IsObject(this._focus) ? this._focus : ""
                if !IsObject(r)
                    for x in this._View()
                        if x.Selected {
                            r := x
                            break
                        }
                return IsObject(r) ? this.GetText(this._Ref(r)) : ""
            }
            set => ""
        }

        ; ------------------------------------------------------ row helpers
        _All() => this._tree ? this._Flat() : this._rows
        _RowAt(n) {
            v := this._View()
            return (IsInteger(n) && n >= 1 && n <= v.Length) ? v[n] : ""
        }
        _Pick(r) {
            if this._single
                for x in this._All()
                    x.Selected := 0
            r.Selected := 1
            if this._tree
                this._Show(r)
        }
        _RowOpts(r, opts) {
            for x in AxListView._Words(opts) {
                switch x.W {
                case "check":
                    r.Checked := x.On ? 1 : 0
                case "select":
                    if x.On
                        this._Pick(r)
                    else
                        r.Selected := 0
                case "focus":
                    if x.On
                        this._focus := r
                case "vis":
                    this._scroll := r
                }
            }
        }
        ; a list's rows in the order they are shown: the order they came, or
        ; sorted by the column the user (or ModifyCol) sorted by
        _View() {
            if (this._sortKey = "")
                return this._rows
            if IsObject(this._viewC)
                return this._viewC
            col := ""
            for c in this._cols
                if (c.Key = this._sortKey)
                    col := c
            if !IsObject(col)
                return this._viewC := this._rows
            arr := this._rows.Clone(), dir := this._sortDir
            ; the same stable insertion sort the grid uses, so the numbers
            ; agree with what is on screen
            loop arr.Length - 1 {
                i := A_Index + 1, v := arr[i], j := i - 1
                while (j >= 1 && this._CmpRows(arr[j], v) * dir > 0) {
                    arr[j + 1] := arr[j]
                    j--
                }
                arr[j + 1] := v
            }
            return this._viewC := arr
        }
        ; two rows by the sort column, as the grid compares them
        _CmpRows(ra, rb) {
            k := this._sortKey, col := ""
            for c in this._cols
                if (c.Key = k)
                    col := c
            kind := (IsObject(col) && Type(col.Sort) = "String") ? StrLower(col.Sort) : "auto"
            a := ra.HasOwnProp(k) ? ra.%k% : "", b := rb.HasOwnProp(k) ? rb.%k% : ""
            if (kind = "" || kind = "auto")
                kind := (IsNumber(a) && IsNumber(b)) ? "number" : "text"
            if (kind = "number") {
                a := IsNumber(a) ? Number(a) : 0, b := IsNumber(b) ? Number(b) : 0
                return (a < b) ? -1 : (a > b) ? 1 : 0
            }
            return StrCompare(String(a), String(b), false)
        }
    }
}
