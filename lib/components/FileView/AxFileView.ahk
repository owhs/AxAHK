#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
#Include %A_LineFile%\..\..\FileSource\AxFileSource.ahk
; single-file exe: this component's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\FileView\AxFileView.css, AX_COMPONENTS_FILEVIEW_AXFILEVIEW_CSS

; =============================================================================
;  AxFileView.ahk — a file window, in parts.
;
;  Everything here is one idea: a *state* holds where you are and what you are
;  looking at, and any number of *parts* draw it. The parts do not talk to
;  each other and none of them owns the state, so you can use one, or all of
;  them, or write a seventh, and the rest carry on.
;
;      st := AxFileState({Name: "files", Source: AxFileLocal(A_MyDocuments)})
;
;      g.AddFileTools("State=files")             ; back, forward, up, search, views
;      g.AddFilePath("State=files")              ; breadcrumbs, or a path box
;      g.AddFileTree("w220 State=files")         ; the folders, down the side
;      g.AddFileView("Fill State=files")         ; the files themselves
;      g.AddFilePreview("w300 State=files")      ; what the one you picked is
;      g.AddFileStatus("State=files")            ; how many, how big
;
;  or, when you want the usual arrangement and not the argument:
;
;      g.AddFileExplorer("Fill", {Source: AxFileLocal()})
;
;  The source is the other half, and it is in FileSource/: the disk, a tree
;  you made up, the registry, the inside of a .zip, or anything you write.
;  Nothing below knows which of those it is drawing.
;
;  ---------------------------------------------------------------- the state
;    Go(path)  Back()  Forward()  Up()  Home()  Refresh()  Open(item)
;    SetMode("details"|"list"|"tiles"|"icons"|"thumbs")
;    SetSort(key, dir?)   SetGroup(key)   SetFilter(text)
;    SetColumns([...])    ShowColumn(key, on)
;    Show("hidden"|"checks"|"preview"|"tree", on)   IconSize(px)
;    Select(keys)  SelectAll()  Invert()  Selected()  Checked()
;
;    OnPath(fn)      where you are changed        fn(path, state)
;    OnItems(fn)     a new listing arrived        fn(items, state)
;    OnSelect(fn)    the selection changed        fn(items, state)
;    OnActivate(fn)  something was opened         fn(item, state)
;    OnCheck(fn)     a tick box moved             fn(items, state)
;    OnEdit(fn)      an editable cell was typed   fn(item, key, value, state)
;    OnDrop(fn)      files were dropped on it     fn(paths, targetItem, state)
;    OnMenu(fn)      a right-click; return items  fn(item, state)
;    OnError(fn)     a folder would not open      fn(message, state)
;
;  --------------------------------------------------------------- the columns
;  A column is what to read and how to draw it:
;
;      {Key: "size", Title: "Size", Width: 90, Align: "right", Render: "size"}
;      {Key: "used", Title: "Space", Width: 160, Render: "bar", Max: 100,
;       Color: (v, it) => v > 90 ? "#e74c3c" : ""}
;      {Key: "rating", Title: "Rating", Width: 110, Render: "rating", Edit: true}
;      {Key: "tags", Title: "Tags", Width: 180, Render: "chips"}
;      {Key: "note", Title: "Note", Width: 200, Edit: "text"}
;      {Key: "kind", Title: "Kind", Width: 130, Html: (it, c) => "<b>...</b>"}
;
;  Render: "name" (icon, twisty, tick box), "text", "size", "date", "bar",
;  "progress", "rating", "chips", "swatch", "toggle", "spark", "icon", "path".
;  Edit: true or "text" | "number" | "rating" | "choice" (with Options) makes
;  the cell editable in place; the change reaches OnEdit and the item.
;  Html is the way out of all of that: return your own markup for the cell.
; =============================================================================

class AxFileState {
    static _named := Map()
    ; States are found by name so a part can be added from a designer, or from
    ; a different file, without the object having to be passed along.
    static Named(name) => AxFileState._named.Has(name) ? AxFileState._named[name] : ""

    ; -------------------------------------------------------------- building
    __New(opts := "") {
        o := (n, d := "") => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        this.Name       := o("Name", "files" (AxFileState._named.Count + 1))
        this.Source     := o("Source", AxFileVirtual([]))
        this.Path       := o("Path", this.Source.RootPath)
        this.Mode       := StrLower(String(o("Mode", "details")))
        this.Group      := o("Group", "")
        this.Query      := ""
        this.Hidden     := o("ShowHidden", false)
        this.Checks     := o("Checkboxes", false)
        this.Size       := Integer(o("IconSize", 64))
        this.Multi      := o("Multi", true)
        this.FoldersFirst := o("FoldersFirst", true)
        this.Empty      := o("Empty", "This folder is empty.")
        this.Modes      := o("Modes", ["details", "list", "tiles", "icons", "thumbs"])
        this.SortKey    := "", this.SortDir := 1
        if IsObject(o("Sort", ""))
            this.SortKey := o("Sort").Key,
            this.SortDir := (o("Sort").HasOwnProp("Dir") && o("Sort").Dir < 0) ? -1 : 1
        else if (o("Sort", "") != "")
            this.SortKey := o("Sort")
        if (this.SortKey = "")
            this.SortKey := "name"

        this.Items   := []                  ; the raw listing
        this.Rows    := []                  ; after filter, sort and grouping
        this.Sel     := Map()               ; key -> true
        this.Chk     := Map()
        this.Cursor  := ""                  ; the key the keyboard is on
        this.Anchor  := ""                  ; where a shift-range starts
        this.Error   := ""
        this.Busy    := false
        this.Back_   := [], this.Fwd_ := []
        this.Tree    := o("Tree", true)
        this.Preview := o("Preview", false)
        this.Open    := Map()               ; tree: expanded paths
        this._parts  := []
        this._cbs    := Map("path", [], "items", [], "select", [], "activate", [],
                            "check", [], "edit", [], "drop", [], "menu", [], "error", [], "mode", [])
        this._thumbs := Map()               ; path -> a URL we already found
        ; Places: somewhere to go, in groups. A local source defaults to the
        ; folders Windows names for everyone plus the drives; anything else
        ; starts with its own root and whatever the caller adds.
        this.Pins := o("Pinned", [])
        this._places := o("Places", "")
        this.SetColumns(o("Columns", AxFileState.DefaultColumns()), false)
        AxFileState._named[this.Name] := this
        this.Reload(false)
    }

    ; The columns a view has when nobody said otherwise: the four a file
    ; window has always had.
    static DefaultColumns() {
        return [{Key: "name",     Title: "Name",     Width: 280, Render: "name", Sort: "text"},
                {Key: "modified", Title: "Modified", Width: 150, Render: "date", Sort: "text"},
                {Key: "type",     Title: "Type",     Width: 130, Render: "text", Sort: "text"},
                {Key: "size",     Title: "Size",     Width: 90,  Render: "size", Sort: "number", Align: "right"}]
    }
    SetColumns(cols, refresh := true) {
        this.Cols := []
        for i, c in cols {
            d := {Key: "", Title: "", Width: 140, MinWidth: 40, MaxWidth: 900, Align: "left",
                  Sort: true, Render: "text", Format: "", Value: "", Html: "", Edit: false,
                  Options: "", Max: "", Color: "", Hidden: false, Hideable: true, Tip: ""}
            if IsObject(c) {
                for k, v in (c is Map ? c : c.OwnProps())
                    d.%k% := v
            } else
                d.Key := c
            if (d.Title = "")
                d.Title := AxFileState.Titleise(d.Key)
            if (i = 1 && d.Render = "text")
                d.Render := "name"
            d.Width := Integer(d.Width), d.MinWidth := Integer(d.MinWidth)
            this.Cols.Push(d)
        }
        if refresh
            this._Emit("columns")
        return this
    }
    static Titleise(k) => StrUpper(SubStr(String(k), 1, 1)) SubStr(String(k), 2)
    Column(key) {
        for c in this.Cols
            if (c.Key = key)
                return c
        return ""
    }
    ShowColumn(key, on := true) {
        c := this.Column(key)
        if (!IsObject(c) || !c.Hideable)
            return this
        if !on {
            left := 0
            for x in this.Cols
                if !x.Hidden
                    left++
            if (left <= 1 && !c.Hidden)          ; never show nothing
                return this
        }
        c.Hidden := !on
        this._Emit("columns")
        return this
    }
    ToggleColumn(key) {
        c := this.Column(key)
        return IsObject(c) ? this.ShowColumn(key, c.Hidden) : this
    }
    VisibleColumns() {
        out := []
        for c in this.Cols
            if !c.Hidden
                out.Push(c)
        if (!out.Length && this.Cols.Length)
            out.Push(this.Cols[1])
        return out
    }
    SetWidth(key, px) {
        c := this.Column(key)
        if IsObject(c) {
            c.Width := Max(c.MinWidth, Min(c.MaxWidth, Round(px)))
            this._Emit("columns")
        }
        return this
    }

    ; ------------------------------------------------------------- places
    ; The list a places pane draws: what was set (or the sensible default for
    ; this source), with the pinned ones gathered at the top.
    PlaceList() {
        base := this._places
        if !(base is Array)
            base := this.DefaultPlaces()
        out := []
        seen := Map()
        for path in this.Pins {
            pl := AxFileState._Place(base, path)
            if !IsObject(pl)
                pl := {Label: this.Source.Name(path), Path: path, Icon: "E8B7", Group: "Pinned"}
            out.Push({Label: pl.Label, Path: pl.Path, Icon: pl.Icon, Group: "Pinned"})
            seen[StrLower(path)] := true
        }
        for pl in base
            if !seen.Has(StrLower(pl.Path))
                out.Push(pl)
        return out
    }
    static _Place(list, path) {
        for pl in list
            if (StrLower(pl.Path) = StrLower(path))
                return pl
        return ""
    }
    DefaultPlaces() {
        ; the known folders and the drives belong to the local source, which is
        ; the only one that can have them
        if (this.Source.Scheme = "file") {
            out := AxFileLocal.Known()
            for d in AxFileLocal.Drives()
                out.Push(d)
            return out
        }
        return [{Label: this.Source.Label, Path: this.Source.RootPath,
                 Icon: this.Source.Icon, Group: this.Source.Label}]
    }
    SetPlaces(list) {
        this._places := (list is Array) ? list : ""
        this._Emit("places")
        return this
    }
    AddPlace(label, path, icon := "E8B7", group := "Places") {
        if !(this._places is Array)
            this._places := this.DefaultPlaces()
        this._places.Push({Label: label, Path: path, Icon: icon, Group: group})
        this._Emit("places")
        return this
    }
    RemovePlace(path) {
        if (this._places is Array)
            for i, pl in this._places
                if (StrLower(pl.Path) = StrLower(path)) {
                    this._places.RemoveAt(i)
                    break
                }
        this.Unpin(path)
        this._Emit("places")
        return this
    }
    IsPinned(path) {
        for p in this.Pins
            if (StrLower(p) = StrLower(path))
                return true
        return false
    }
    ; Pin takes a path or an item, so the view's menu can hand one straight over.
    Pin(what) {
        path := IsObject(what) ? what.Path : String(what)
        if (path = "" || this.IsPinned(path))
            return this
        this.Pins.Push(path)
        this._Emit("places")
        return this
    }
    Unpin(what) {
        path := IsObject(what) ? what.Path : String(what)
        for i, p in this.Pins
            if (StrLower(p) = StrLower(path)) {
                this.Pins.RemoveAt(i)
                break
            }
        this._Emit("places")
        return this
    }
    TogglePin(what) {
        path := IsObject(what) ? what.Path : String(what)
        return this.IsPinned(path) ? this.Unpin(path) : this.Pin(path)
    }
    ; What to write to an .ini, and what to hand back next time as Pinned.
    PinnedPaths() => this.Pins.Clone()

    ; ---------------------------------------------------------------- parts
    ; A part is anything with an Update(what) method. It is called for
    ; "items", "path", "select", "check", "columns", "mode", "busy" and
    ; "edit", and may ignore any of them.
    Attach(part) {
        this._parts.Push(part)
        try part.Update("attach")
        return this
    }
    Detach(part) {
        for i, p in this._parts
            if (p == part) {
                this._parts.RemoveAt(i)
                break
            }
        return this
    }
    _Emit(what) {
        for p in this._parts.Clone()
            try p.Update(what)
        return this
    }
    _Fire(name, args) {
        if !this._cbs.Has(name)
            return this
        for fn in this._cbs[name].Clone()
            try fn(args*)
        return this
    }
    _On(name, fn) {
        this._cbs[name].Push(fn)
        return this
    }
    OnPath(fn)     => this._On("path", fn)
    OnItems(fn)    => this._On("items", fn)
    OnSelect(fn)   => this._On("select", fn)
    OnActivate(fn) => this._On("activate", fn)
    OnCheck(fn)    => this._On("check", fn)
    OnEdit(fn)     => this._On("edit", fn)
    OnDrop(fn)     => this._On("drop", fn)
    OnMenu(fn)     => this._On("menu", fn)
    OnError(fn)    => this._On("error", fn)
    OnMode(fn)     => this._On("mode", fn)

    ; ------------------------------------------------------------ navigation
    ; Go somewhere. push:=false is how Back and Forward move without adding to
    ; the history they are walking.
    Go(path, push := true) {
        p := String(path)
        if (p = this.Path && this.Items.Length)
            return this
        if push {
            this.Back_.Push(this.Path)
            this.Fwd_ := []
            if (this.Back_.Length > 64)
                this.Back_.RemoveAt(1)
        }
        this.Path := p
        this.Sel := Map(), this.Cursor := "", this.Anchor := ""
        this.Reload()
        this._Fire("path", [this.Path, this])
        this._Emit("path")
        return this
    }
    CanBack    => this.Back_.Length > 0
    CanForward => this.Fwd_.Length > 0
    CanUp      => this.Source.Parent(this.Path) != "" || this.Path != this.Source.RootPath
    Back() {
        if !this.Back_.Length
            return this
        this.Fwd_.Push(this.Path)
        p := this.Back_.Pop()
        return this.Go(p, false)
    }
    Forward() {
        if !this.Fwd_.Length
            return this
        this.Back_.Push(this.Path)
        p := this.Fwd_.Pop()
        return this.Go(p, false)
    }
    Up() {
        up := this.Source.Parent(this.Path)
        if (up = "" && this.Path = this.Source.RootPath)
            return this
        return this.Go(up)
    }
    Home() => this.Go(this.Source.RootPath)
    ; Open what is under the cursor: a folder is somewhere to go, anything
    ; else is the caller's business.
    Activate(item) {
        if !IsObject(item)
            return this
        if AxFileSource.IsBranch(item)
            return this.Go(item.Path)
        this._Fire("activate", [item, this])
        return this
    }
    ; Swap the whole source out. The view, the tree and the crumbs all follow,
    ; which is what a "drive" drop-down or a "open this zip" button wants.
    SetSource(source, path := unset) {
        this.Source := source
        this.Back_ := [], this.Fwd_ := [], this.Open := Map()
        this.Path := IsSet(path) ? path : source.RootPath
        this.Sel := Map(), this.Chk := Map(), this.Cursor := ""
        this._thumbs := Map()
        this.Reload()
        this._Fire("path", [this.Path, this])
        this._Emit("path")
        return this
    }

    ; --------------------------------------------------------------- listing
    Reload(emit := true) {
        this.Error := ""
        items := []
        try items := this.Source.List(this.Path)
        catch as e {
            this.Error := e.Message
            this._Fire("error", [e.Message, this])
        }
        this.Items := (items is Array) ? items : []
        this.Build()
        if emit {
            this._Fire("items", [this.Items, this])
            this._Emit("items")
        }
        return this
    }
    Refresh() {
        try this.Source.Refresh(this.Path)
        return this.Reload()
    }

    ; filter -> sort -> group. Rows come out as {Kind: "group"|"item"} so
    ; every view walks one list and none of them groups things twice.
    Build() {
        keep := []
        q := StrLower(Trim(this.Query))
        for it in this.Items {
            if (it.Hidden && !this.Hidden)
                continue
            if (q != "" && !InStr(StrLower(it.Name), q) && !InStr(StrLower(String(it.Type)), q))
                continue
            keep.Push(it)
        }
        this.Sorted := this._Sort(keep)
        this.Rows := []
        if (this.Group = "") {
            for it in this.Sorted
                this.Rows.Push({Kind: "item", Item: it})
            return this
        }
        order := [], bucket := Map()
        g := this.Group
        for it in this.Sorted {
            name := (IsObject(g) && HasMethod(g, "Call")) ? g(it) : this.Cell(it, g)
            name := (name = "") ? "Other" : String(name)
            if !bucket.Has(name)
                bucket[name] := [], order.Push(name)
            bucket[name].Push(it)
        }
        for name in order {
            this.Rows.Push({Kind: "group", Name: name, Count: bucket[name].Length})
            for it in bucket[name]
                this.Rows.Push({Kind: "item", Item: it, Group: name})
        }
        return this
    }
    ; Folders before files, then whatever the sort column says. Insertion
    ; sort is fine for a page of rows and quadratic for a folder of ten
    ; thousand, so this is a merge sort: stable, and it does not care.
    _Sort(list) {
        col := this.Column(this.SortKey)
        dir := this.SortDir
        foldersFirst := this.FoldersFirst
        cmp := (a, b) => AxFileState._Rank(a, b, foldersFirst, col, dir, this)
        return AxFileState.MergeSort(list, cmp)
    }
    static _Rank(a, b, foldersFirst, col, dir, st) {
        if foldersFirst {
            fa := AxFileSource.IsBranch(a) ? 0 : 1, fb := AxFileSource.IsBranch(b) ? 0 : 1
            if (fa != fb)
                return fa - fb
        }
        if !IsObject(col)
            return StrCompare(a.Name, b.Name, false) * dir
        if (IsObject(col.Sort) && HasMethod(col.Sort, "Call")) {
            cmp := col.Sort                 ; through a local: col.Sort(a, b) is a
            return cmp(a, b) * dir          ; METHOD call, and col arrives as the first argument
        }
        x := st.Cell(a, col.Key), y := st.Cell(b, col.Key)
        kind := (Type(col.Sort) = "String") ? StrLower(col.Sort) : "auto"
        if (kind = "" || kind = "auto" || kind = "true")
            kind := (IsNumber(x) && IsNumber(y)) ? "number" : "text"
        if (kind = "number") {
            x := IsNumber(x) ? Number(x) : -1, y := IsNumber(y) ? Number(y) : -1
            return ((x < y) ? -1 : (x > y) ? 1 : 0) * dir
        }
        ; a column may hold an Array (a sparkline) or any other object, and
        ; String() on one of those throws rather than comparing
        if IsObject(x)
            x := ""
        if IsObject(y)
            y := ""
        return StrCompare(String(x), String(y), false) * dir
    }
    static MergeSort(list, cmp) {
        n := list.Length
        if (n < 2)
            return list.Clone()
        mid := n // 2
        left := [], right := []
        loop mid
            left.Push(list[A_Index])
        loop n - mid
            right.Push(list[mid + A_Index])
        left := AxFileState.MergeSort(left, cmp)
        right := AxFileState.MergeSort(right, cmp)
        out := [], i := 1, j := 1
        while (i <= left.Length && j <= right.Length) {
            if (cmp(right[j], left[i]) < 0)          ; strictly less keeps it stable
                out.Push(right[j]), j++
            else
                out.Push(left[i]), i++
        }
        while (i <= left.Length)
            out.Push(left[i]), i++
        while (j <= right.Length)
            out.Push(right[j]), j++
        return out
    }
    ; What a column reads off an item. "name", "size", "modified", "type" and
    ; "kind" are spelled for you; anything else is a property the source put
    ; there, and a column with a Value function overrides the lot.
    Cell(it, key) {
        c := this.Column(key)
        if (IsObject(c) && IsObject(c.Value) && HasMethod(c.Value, "Call")) {
            read := c.Value                 ; a local, or c would be passed in as well
            return read(it, this)
        }
        switch StrLower(String(key)) {
        case "name":     return it.Name
        case "size":     return it.Size
        case "modified": return it.Modified
        case "type":     return it.Type
        case "kind":     return it.Kind
        case "path":     return it.Path
        case "family":   return AxFileSource.Family(it.Name)
        case "ext":      return AxFileSource.Ext(it.Name)
        }
        return it.HasOwnProp(key) ? it.%key% : ""
    }
    Find(key) {
        for it in this.Items
            if (it.Key = key)
                return it
        return ""
    }

    ; ------------------------------------------------------------- the knobs
    SetMode(mode) {
        m := StrLower(String(mode))
        if (m = this.Mode)
            return this
        this.Mode := m
        this._Fire("mode", [m, this])
        this._Emit("mode")
        return this
    }
    ; Clicking a column that is already the sort turns it round. A column whose
    ; Sort is false is not a sort key by any route -- the header knows that, and
    ; so must the menu and anyone calling this.
    SetSort(key, dir := "") {
        c := this.Column(key)
        if (IsObject(c) && !c.Sort && !(IsObject(c.Sort) && HasMethod(c.Sort, "Call")))
            return this
        if (key != "" && key = this.SortKey && dir = "")
            this.SortDir := -this.SortDir
        else {
            this.SortKey := key
            this.SortDir := (dir = "") ? 1 : (dir < 0 || dir = "desc" ? -1 : 1)
        }
        this.Build()
        this._Emit("items")
        return this
    }
    SetGroup(key) {
        this.Group := key
        this.Build()
        this._Emit("items")
        return this
    }
    SetFilter(text) {
        this.Query := String(text)
        this.Build()
        this._Emit("items")
        return this
    }
    IconSize(px := "") {
        if (px = "")
            return this.Size
        this.Size := Max(24, Min(256, Integer(px)))
        this._Emit("mode")
        return this
    }
    ; Show("hidden", true) / Show("checks") / Show("tree", false). The two
    ; panes are a class on the frame, so the explorer does the layout.
    Show(what, on := true) {
        switch StrLower(String(what)) {
        case "hidden":  this.Hidden := on, this.Build(), this._Emit("items")
        case "checks":  this.Checks := on, this._Emit("items")
        case "preview": this.Preview := on, this._Emit("panes")
        case "tree":    this.Tree := on, this._Emit("panes")
        case "foldersfirst": this.FoldersFirst := on, this.Build(), this._Emit("items")
        }
        return this
    }
    Toggle(what) {
        switch StrLower(String(what)) {
        case "hidden":  return this.Show("hidden", !this.Hidden)
        case "checks":  return this.Show("checks", !this.Checks)
        case "preview": return this.Show("preview", !(this.HasOwnProp("Preview") && this.Preview))
        case "tree":    return this.Show("tree", !(this.HasOwnProp("Tree") && this.Tree))
        case "foldersfirst": return this.Show("foldersfirst", !this.FoldersFirst)
        }
        return this
    }

    ; ------------------------------------------------------------- selection
    Select(keys, fire := true) {
        this.Sel := Map()
        for k in (keys is Array ? keys : [keys])
            if (k != "")
                this.Sel[k] := true
        this._Emit("select")
        if fire
            this._Fire("select", [this.Selected(), this])
        return this
    }
    Pick(key, ctrl := false, shift := false) {
        if (!this.Multi || (!ctrl && !shift)) {
            this.Sel := Map()
            this.Sel[key] := true
            this.Anchor := key
        } else if ctrl {
            if this.Sel.Has(key)
                this.Sel.Delete(key)
            else
                this.Sel[key] := true
            this.Anchor := key
        } else {
            this.Sel := Map()
            a := 0, b := 0
            for i, r in this.Rows {
                if (r.Kind != "item")
                    continue
                if (r.Item.Key = this.Anchor)
                    a := i
                if (r.Item.Key = key)
                    b := i
            }
            if (!a)
                a := b
            lo := Min(a, b), hi := Max(a, b)
            loop hi - lo + 1 {
                r := this.Rows[lo + A_Index - 1]
                if (r.Kind = "item")
                    this.Sel[r.Item.Key] := true
            }
        }
        this.Cursor := key
        this._Emit("select")
        this._Fire("select", [this.Selected(), this])
        return this
    }
    SelectAll() {
        keys := []
        for r in this.Rows
            if (r.Kind = "item")
                keys.Push(r.Item.Key)
        return this.Select(keys)
    }
    ClearSelection() => this.Select([])
    Invert() {
        keys := []
        for r in this.Rows
            if (r.Kind = "item" && !this.Sel.Has(r.Item.Key))
                keys.Push(r.Item.Key)
        return this.Select(keys)
    }
    Selected() {
        out := []
        for r in this.Rows
            if (r.Kind = "item" && this.Sel.Has(r.Item.Key))
                out.Push(r.Item)
        return out
    }
    SelectedKeys() {
        out := []
        for it in this.Selected()
            out.Push(it.Key)
        return out
    }
    Current() {
        if (this.Cursor != "")
            for r in this.Rows
                if (r.Kind = "item" && r.Item.Key = this.Cursor)
                    return r.Item
        s := this.Selected()
        return s.Length ? s[1] : ""
    }
    ; --- ticks, which are not the selection: you tick a set to act on, and
    ; you select to look at.
    Check(key, on := unset, fire := true) {
        state := IsSet(on) ? on : !this.Chk.Has(key)
        if state
            this.Chk[key] := true
        else if this.Chk.Has(key)
            this.Chk.Delete(key)
        this._Emit("check")
        if fire
            this._Fire("check", [this.Checked(), this])
        return this
    }
    CheckAll(on := true) {
        for r in this.Rows
            if (r.Kind = "item") {
                if on
                    this.Chk[r.Item.Key] := true
                else if this.Chk.Has(r.Item.Key)
                    this.Chk.Delete(r.Item.Key)
            }
        this._Emit("check")
        this._Fire("check", [this.Checked(), this])
        return this
    }
    Checked() {
        out := []
        for r in this.Rows
            if (r.Kind = "item" && this.Chk.Has(r.Item.Key))
                out.Push(r.Item)
        return out
    }
    AllChecked {
        get {
            n := 0, c := 0
            for r in this.Rows
                if (r.Kind = "item")
                    n++, c += this.Chk.Has(r.Item.Key) ? 1 : 0
            return !n ? 0 : (c = n) ? 1 : (c ? -1 : 0)      ; 1 all, -1 some, 0 none
        }
    }

    ; ---------------------------------------------------------------- edits
    ; A cell that was typed into. The item is changed here so every part
    ; redraws from one truth, and the handler decides whether that reaches
    ; the disk, the database or nothing at all.
    Edit(key, colKey, value) {
        it := this.Find(key)
        if !IsObject(it)
            return this
        try it.%colKey% := value
        this._Fire("edit", [it, colKey, value, this])
        this.Build()
        this._Emit("items")
        return this
    }
    ; A thumbnail URL for an item, asked of the source once and remembered.
    Thumb(it) {
        if !IsObject(it)
            return ""
        if this._thumbs.Has(it.Path)
            return this._thumbs[it.Path]
        u := ""
        try u := this.Source.Thumb(it)
        this._thumbs[it.Path] := u
        return u
    }
    ; What the status line says, and what a caller may want anyway.
    Stats() {
        n := 0, folders := 0, bytes := 0
        for r in this.Rows
            if (r.Kind = "item") {
                n++
                if AxFileSource.IsBranch(r.Item)
                    folders++
                else if IsNumber(r.Item.Size)
                    bytes += r.Item.Size
            }
        return {Count: n, Folders: folders, Files: n - folders, Bytes: bytes,
                Selected: this.Sel.Count, Checked: this.Chk.Count,
                Hidden: this.Items.Length - n}
    }
    Count => this.Rows.Length
}

; =============================================================================
;  AxFileView — the files themselves, in whichever of five shapes.
;
;  Details is a table with a head that sorts, sizes and hides its columns;
;  list is the same rows without it; tiles, icons and thumbs are flowed boxes
;  at whatever icon size the state carries. One Render() draws all five, so a
;  mode is a class on the frame and a branch in one function, not a fifth
;  implementation of selection, ticking, grouping and the keyboard.
; =============================================================================
class AxFileView {
    static _reg := AxRich.Register("FileView", "components\FileView\AxFileView.css",
                                   (*) => AxFileView._Install())
    static _Install() {
        AxRich.AddMethod("AddFileView",    (c, o := "", s := "") => AxFileView._Add(c, o, s))
        AxRich.AddMethod("AddFileTree",    (c, o := "", s := "") => AxFileTree._Add(c, o, s))
        AxRich.AddMethod("AddFilePath",    (c, o := "", s := "") => AxFilePath._Add(c, o, s))
        AxRich.AddMethod("AddFilePreview", (c, o := "", s := "") => AxFilePreview._Add(c, o, s))
        AxRich.AddMethod("AddFilePlaces",  (c, o := "", s := "") => AxFilePlaces._Add(c, o, s))
        AxRich.AddMethod("AddFileStatus",  (c, o := "", s := "") => AxFileStatus._Add(c, o, s))
        AxRich.AddMethod("AddFileTools",   (c, o := "", s := "") => AxFileTools._Add(c, o, s))
        AxRich.AddMethod("AddFileExplorer", (c, o := "", s := "") => AxFileExplorer._Add(c, o, s))
        AxWindow.RegisterValue("fileview",
            (w, el) => AxFileView._Via(w, el, unset),
            (w, el, v) => AxFileView._Via(w, el, v))
        return true
    }
    static _Via(win, el, value?) {
        c := AxRich.At(win, el.id)
        if !IsObject(c)
            return []
        if IsSet(value)
            return c.State.Select(IsObject(value) ? value : StrSplit(String(value), "|"))
        return c.State.SelectedKeys()
    }
    ; A part takes its state as an object, as a name, or as State=name in the
    ; option string — whichever the caller has to hand.
    static _State(spec, o := "") {
        if IsObject(spec)
            return spec
        if (spec != "" && (st := AxFileState.Named(spec)) != "")
            return st
        if (IsObject(o) && o.KV.Has("state")) {
            st := AxFileState.Named(o.KV["state"])
            if (st != "")
                return st
        }
        ; nothing of that name: a state over an empty tree, so the part draws
        ; rather than throwing, and SetSource fills it in later
        return AxFileState({Name: (IsObject(o) ? o.Id : "files"), Source: AxFileVirtual([])})
    }

    ; --------------------------------------------------------------- markup
    static Html(id, cfg := "") {
        o := (n, d := "") => (IsObject(cfg) && cfg.HasOwnProp(n)) ? cfg.%n% : d
        E := (x) => AxWindow._Esc(x)
        h := o("Height", 0)
        sc := h ? ((o("Fixed", false) ? "height:" : "max-height:") h "px") : ""
        return '<div class="fv ' E(o("Mode", "details")) (o("Class", "") != "" ? " " E(o("Class", "")) : "") '"'
             . ' id="' E(id) '" data-role="fileview"'
             . (o("Style", "") != "" ? ' style="' E(o("Style", "")) '"' : "") '>'
             . '<div class="fv-headwrap" id="' E(id) '_headwrap">'
             . '<table class="fv-table"><colgroup id="' E(id) '_hcols"></colgroup>'
             . '<thead><tr id="' E(id) '_head"></tr></thead></table></div>'
             . '<div class="fv-scroll" id="' E(id) '_scroll" tabindex="0"'
             . (sc != "" ? ' style="' sc '"' : "") '>'
             . '<div class="fv-canvas" id="' E(id) '_body"></div></div></div>'
    }

    ; ----------------------------------------------------------- the instance
    __New(win, id, state, cfg := "") {
        this.W := win, this.Id := id, this.State := state
        this.Cfg := IsObject(cfg) ? cfg : {}
        o := (n, d := "") => this.Cfg.HasOwnProp(n) ? this.Cfg.%n% : d
        this.Drag := o("Drag", true)               ; drag items onto folders
        this._edit := ""                           ; the cell being typed into
        this._clickKey := "", this._clickAt := 0
        this._colWidth := 0
        AxRich.Use(win, "FileView")
        AxRich.Bind(win, id, this)
        state.Attach(this)
        this._Wire()
        this.Render()
    }
    ; --- the part contract
    Update(what) {
        switch what {
        case "attach": return
        case "select", "check": return this._Marks()
        }
        this.Render()
    }

    _Wire() {
        w := this.W, id := this.Id
        w.On("click",       id, (el, ev) => this._Click(ev))
        w.On("dblclick",    id, (el, ev) => this._DblClick(ev))
        w.On("mousedown",   id, (el, ev) => this._Down(ev))
        w.On("keydown",     id, (el, ev) => this._Key(ev))
        w.On("contextmenu", id, (el, ev) => this._Menu(ev))
        w.On("focusin",     id, (*) => this.W.AddClass(this.Id, "focus"))
        w.On("focusout",    id, (*) => this.W.RemoveClass(this.Id, "focus"))
        ; real files dropped on it from anywhere else in Windows
        if (this.Cfg.HasOwnProp("Drop") ? this.Cfg.Drop : true)
            w.DropZone(id, (files, *) => this._Dropped(files), {Expand: false})
        this._scrollFn := (*) => this._Sync()
        try w.El(id "_scroll").attachEvent("onscroll", this._scrollFn)
    }
    _Sync() {
        try this.W.El(this.Id "_headwrap").scrollLeft := this.W.El(this.Id "_scroll").scrollLeft
    }
    Focus() {
        try this.W.El(this.Id "_scroll").focus()
        return this
    }

    ; ---------------------------------------------------------------- render
    Render() {
        st := this.State, mode := st.Mode
        this._Commit(false)                       ; a redraw under an open editor loses it
        try this.W.El(this.Id).className := "fv " mode (st.Checks ? " checks" : "")
            . (this.Cfg.HasOwnProp("Class") && this.Cfg.Class != "" ? " " this.Cfg.Class : "")
        details := (mode = "details")
        try this.W.El(this.Id "_headwrap").style.display := details ? "block" : "none"
        if details
            this._Head()
        ; Building the markup is the caller's code as much as ours -- a column's
        ; Format, Value, Color or Html is a function somebody wrote -- so a throw
        ; here says so in the view instead of leaving it mysteriously blank.
        html := ""
        try html := details ? this._Rows() : this._Boxes()
        catch as e
            html := '<div class="fv-empty">' AxWindow._Esc(e.Message) '</div>'
        try this.W.El(this.Id "_body").innerHTML := html
        this._Marks()
        return this
    }
    ; --- the column head: title, sort arrow, and a grip to drag
    _Head() {
        E := (x) => AxWindow._Esc(x)
        st := this.State, cols := "", head := "", total := 0
        for c in st.Cols {
            if c.Hidden
                continue
            total += c.Width
            cols .= '<col style="width:' c.Width 'px">'
            arrow := (st.SortKey = c.Key) ? (st.SortDir > 0 ? "&#xE70E;" : "&#xE70D;") : ""
            head .= '<th class="fv-h' (c.Align != "left" ? " " E(c.Align) : "")
                 .  (st.SortKey = c.Key ? " sorted" : "") '" data-col="' E(c.Key) '"'
                 .  (c.Tip != "" ? ' data-tip="' E(c.Tip) '"' : "") '>'
                 .  '<span class="fv-ht">' E(c.Title) '</span>'
                 .  '<span class="fv-sortmark ico">' arrow '</span>'
                 .  '<span class="fv-grip" data-grip="' E(c.Key) '"></span></th>'
        }
        this._colWidth := total
        try {
            this.W.El(this.Id "_hcols").innerHTML := cols
            this.W.El(this.Id "_head").innerHTML := head
            this.W.El(this.Id "_headwrap").getElementsByTagName("table").item(0).style.width := total "px"
        }
        return this
    }
    ; --- details: one table, group headers as full-width rows
    _Rows() {
        E := (x) => AxWindow._Esc(x)
        st := this.State, vis := st.VisibleColumns()
        cols := ""
        for c in vis
            cols .= '<col style="width:' c.Width 'px">'
        body := ""
        for r in st.Rows {
            if (r.Kind = "group") {
                body .= '<tr class="fv-group"><td colspan="' vis.Length '">'
                     .  '<span class="fv-gname">' E(r.Name) '</span>'
                     .  '<span class="fv-gcount">' r.Count '</span></td></tr>'
                continue
            }
            it := r.Item
            body .= '<tr class="fv-row' (it.Hidden ? " hidden-item" : "") '" data-k="' E(it.Key) '">'
            for i, c in vis
                body .= '<td class="fv-c' (c.Align != "left" ? " " E(c.Align) : "")
                     .  (i > 1 ? " dim" : "") (c.Edit ? " editable" : "") '" data-col="' E(c.Key) '">'
                     .  this._Cell(it, c, i = 1) '</td>'
            body .= '</tr>'
        }
        if (body = "")
            return '<div class="fv-empty">' E(this._EmptyText()) '</div>'
        return '<table class="fv-table" style="width:' (this._colWidth ? this._colWidth : 600) 'px">'
             . '<colgroup>' cols '</colgroup><tbody>' body '</tbody></table>'
    }
    ; --- list, tiles, icons, thumbs: flowed boxes, one function, four shapes
    _Boxes() {
        E := (x) => AxWindow._Esc(x)
        st := this.State, mode := st.Mode, sz := st.Size
        out := "", open := false
        for r in st.Rows {
            if (r.Kind = "group") {
                if open
                    out .= "</div>", open := false
                out .= '<div class="fv-ghead"><span class="fv-gname">' E(r.Name) '</span>'
                    .  '<span class="fv-gcount">' r.Count '</span></div>'
                continue
            }
            if !open
                out .= '<div class="fv-flow">', open := true
            out .= this._Box(r.Item, mode, sz)
        }
        if open
            out .= "</div>"
        if (out = "")
            return '<div class="fv-empty">' E(this._EmptyText()) '</div>'
        return out
    }
    _Box(it, mode, sz) {
        E := (x) => AxWindow._Esc(x)
        st := this.State
        w := (mode = "list") ? 0 : (mode = "tiles") ? (sz * 3) : (sz + 36)
        style := w ? ' style="width:' w 'px"' : ""
        s := '<div class="fv-box' (it.Hidden ? " hidden-item" : "") '" data-k="' E(it.Key) '"'
           . ' data-tip="' E(it.Name) '"' style '>'
        if st.Checks
            s .= '<span class="fv-check" data-check="1"></span>'
        s .= '<span class="fv-art"' ((mode = "icons" || mode = "thumbs")
             ? ' style="height:' sz 'px;line-height:' sz 'px"' : "") '>' this._Art(it, mode, sz) '</span>'
        s .= '<span class="fv-label"><span class="fv-name">' E(it.Name) '</span>'
        if (mode = "tiles")
            s .= '<span class="fv-meta">' E(it.Type) '</span>'
              .  '<span class="fv-meta">' E(this._Size(it)) '</span>'
        else if (mode = "list")
            s .= '<span class="fv-meta">' E(this._Size(it)) '</span>'
        s .= '</span>'
        ; the extras a box carries: whichever columns the caller named
        if (this.Cfg.HasOwnProp("Badges") && this.Cfg.Badges is Array) {
            b := ""
            for key in this.Cfg.Badges {
                c := st.Column(key)
                if IsObject(c)
                    b .= '<span class="fv-badge" data-col="' E(c.Key) '">' this._Cell(it, c, false) '</span>'
            }
            if (b != "")
                s .= '<span class="fv-badges">' b '</span>'
        }
        return s "</div>"
    }
    ; The picture on a box: a thumbnail where the source has one and the mode
    ; wants one, otherwise the glyph.
    _Art(it, mode, sz) {
        if (mode = "thumbs" || mode = "icons") {
            u := this.State.Thumb(it)
            if (u != "")
                return '<img class="fv-thumb" src="' AxWindow._Esc(u) '" style="max-width:' sz
                     . 'px;max-height:' sz 'px">'
        }
        big := (mode = "icons" || mode = "thumbs") ? ' style="font-size:' Round(sz * 0.55) 'px"' : ""
        return '<span class="ico fv-glyph' (AxFileSource.IsBranch(it) ? " folder" : "") '"' big
             . '>&#x' (it.Icon != "" ? it.Icon : "E7C3") ';</span>'
    }
    _Size(it) => AxFileSource.IsBranch(it) ? "" : (IsNumber(it.Size) ? AxWindow.FileSize(it.Size) : "")
    _EmptyText() {
        st := this.State
        if (st.Error != "")
            return st.Error
        if (st.Query != "")
            return "Nothing here matches " Chr(0x201C) st.Query Chr(0x201D) "."
        if (st.Items.Length && !st.Rows.Length)
            return st.Items.Length " hidden item" (st.Items.Length = 1 ? "" : "s")
                 . " here. Turn hidden items on to see them."
        return st.Empty
    }

    ; ------------------------------------------------------------- the cells
    ; One column, one item, one piece of markup. Html short-circuits the lot;
    ; otherwise Render picks the shape and Format the words.
    _Cell(it, c, first) {
        E := (x) => AxWindow._Esc(x)
        st := this.State
        ; Every one of these goes through a local. c.Html(...) is a METHOD call in
        ; v2, so the column itself would arrive as the first argument and a
        ; three-parameter function would fail with "too many parameters".
        if (IsObject(c.Html) && HasMethod(c.Html, "Call")) {
            draw := c.Html
            return draw(it, c, st)
        }
        v := st.Cell(it, c.Key)
        text := v
        if (IsObject(c.Format) && HasMethod(c.Format, "Call")) {
            fmt := c.Format
            text := fmt(v, it, st)
        }
        body := ""
        switch StrLower(String(c.Render)) {
        case "name":
            body := '<span class="fv-name">' E(text) '</span>'
        case "size":
            body := '<span class="fv-num">' E(IsNumber(v) ? AxWindow.FileSize(v) : text) '</span>'
        case "date":
            body := '<span class="fv-num">' E(AxFileView.Stamp(v)) '</span>'
        case "bar", "progress":
            body := this._Bar(v, c, it)
        case "rating":
            body := this._Stars(v, c)
        case "chips":
            body := this._Chips(v)
        case "swatch":
            body := '<span class="fv-swatch" style="background:' E(String(v) != "" ? v : "transparent") '"></span>'
                  . '<span class="fv-swtext">' E(text) '</span>'
        case "toggle":
            body := '<span class="fv-toggle' (v ? " on" : "") '"><span class="knob"></span></span>'
        case "spark":
            body := this._Spark(v, c)
        case "icon":
            body := (String(v) != "") ? '<span class="ico fv-cico">&#x' E(v) ';</span>' : ""
        case "path":
            body := '<span class="fv-path">' E(text) '</span>'
        default:
            body := '<span class="fv-text">' E(text) '</span>'
        }
        if !first
            return body
        ; the first column carries the ornaments: the tick box, the icon and,
        ; in a grouped view, nothing else — the tree lives in its own pane
        lead := ""
        if st.Checks
            lead .= '<span class="fv-check" data-check="1"></span>'
        lead .= '<span class="ico fv-glyph' (AxFileSource.IsBranch(it) ? " folder" : "") '">&#x'
             .  (it.Icon != "" ? it.Icon : "E7C3") ';</span>'
        return lead body
    }
    ; A filled bar with its number beside it. Max is a number, a column key,
    ; or nothing at all, in which case the value is read as a percentage.
    _Bar(v, c, it) {
        E := (x) => AxWindow._Esc(x)
        ; not "max": that is a built-in variable name, and a local of the same
        ; name is a warning under #Warn All
        top := c.Max
        if (IsObject(top) && HasMethod(top, "Call"))
            top := top(it, this.State)
        else if (top != "" && !IsNumber(top))
            top := this.State.Cell(it, top)
        top := IsNumber(top) ? Number(top) : 100
        n := IsNumber(v) ? Number(v) : 0
        pct := top ? Max(0, Min(100, Round(n / top * 100))) : 0
        colour := c.Color
        if (IsObject(colour) && HasMethod(colour, "Call"))
            colour := colour(n, it, this.State)
        label := (StrLower(String(c.Render)) = "progress") ? pct "%" : String(v)
        if (IsObject(c.Format) && HasMethod(c.Format, "Call")) {
            fmt := c.Format
            label := fmt(v, it, this.State)
        }
        return '<span class="fv-bar"><span class="fv-bar-fill" style="width:' pct '%'
             . (colour != "" ? ";background:" E(colour) : "") '"></span></span>'
             . '<span class="fv-bar-text">' E(label) '</span>'
    }
    ; Five stars. With Edit on, clicking one is the edit — there is no text
    ; box to open and nothing to confirm.
    _Stars(v, c) {
        n := IsNumber(v) ? Round(Number(v)) : 0
        out := '<span class="fv-stars' (c.Edit ? " live" : "") '">'
        loop 5
            out .= '<span class="ico fv-star' (A_Index <= n ? " on" : "") '" data-star="' A_Index '">&#x'
                 . (A_Index <= n ? "E735" : "E734") ';</span>'
        return out "</span>"
    }
    _Chips(v) {
        E := (x) => AxWindow._Esc(x)
        list := IsObject(v) ? v : StrSplit(String(v), ",")
        out := ""
        for t in list {
            t := Trim(String(t))
            if (t != "")
                out .= '<span class="fv-chip">' E(t) '</span>'
        }
        return out
    }
    ; A row of little bars from an array of numbers: a shape, not a chart.
    _Spark(v, c) {
        if !(v is Array) || !v.Length
            return ""
        peak := 0
        for n in v
            peak := Max(peak, IsNumber(n) ? Number(n) : 0)
        if !peak
            peak := 1
        out := '<span class="fv-spark">'
        for n in v
            out .= '<span class="fv-spark-b" style="height:'
                 . Max(8, Round((IsNumber(n) ? Number(n) : 0) / peak * 100)) '%"></span>'
        return out "</span>"
    }
    ; "12 Mar 2024, 09:14" — the same width whatever the locale does with it.
    static Stamp(v) {
        s := String(v)
        if (s = "" || StrLen(s) < 8 || !IsNumber(s))
            return s
        try return FormatTime(s, "dd MMM yyyy" (StrLen(s) > 8 ? ", HH:mm" : ""))
        return s
    }

    ; ---------------------------------------------------------- marks only
    ; Selection and ticks change far more often than the rows do, so they are
    ; painted by walking the DOM rather than by building it again.
    _Marks() {
        st := this.State
        try {
            nodes := this.W.El(this.Id "_body").getElementsByTagName("*")
            loop nodes.length {
                el := nodes.item(A_Index - 1)
                k := AxWindow._Attr(el, "data-k")
                if (k = "")
                    continue
                AxWindow._SetClass(el, "sel", st.Sel.Has(k))
                AxWindow._SetClass(el, "cursor", st.Cursor = k)
                AxWindow._SetClass(el, "ticked", st.Chk.Has(k))
            }
        }
        return this
    }
    _Up(el, attr) {
        loop 10 {
            if !IsObject(el)
                return ""
            if (AxWindow._Attr(el, attr) != "")
                return el
            try {
                if (el.id = this.Id)
                    return ""
            }
            el := AxWindow._ParentEl(el)
        }
        return ""
    }
    _UpClass(el, cls) {
        loop 10 {
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

    ; ---------------------------------------------------------------- input
    _Click(ev) {
        try el := ev.srcElement
        catch
            return
        st := this.State
        ; the editor's own box: leave it alone
        if this._UpClass(el, "fv-input")
            return
        ; a column head sorts, unless the grip was what was hit
        if (h := this._Up(el, "data-col")) {
            if (AxWindow._Attr(h, "data-grip") != "" || this._Up(el, "data-grip"))
                return
            try {
                if (h.tagName = "TH") {
                    c := st.Column(AxWindow._Attr(h, "data-col"))
                    if (IsObject(c) && c.Sort)
                        st.SetSort(c.Key)
                    return
                }
            }
        }
        row := this._Up(el, "data-k")
        if !row {
            this._Commit()
            return st.ClearSelection()
        }
        key := AxWindow._Attr(row, "data-k")
        ; a tick box is not a selection
        if this._UpClass(el, "fv-check")
            return st.Check(key)
        ; a star in an editable rating column is the edit itself
        if (star := this._Up(el, "data-star")) {
            cell := this._Up(star, "data-col")
            if cell {
                c := st.Column(AxWindow._Attr(cell, "data-col"))
                if (IsObject(c) && c.Edit)
                    return st.Edit(key, c.Key, Integer(AxWindow._Attr(star, "data-star")))
            }
        }
        picked := st.Sel.Has(key)
        st.Pick(key, GetKeyState("Ctrl", "P"), GetKeyState("Shift", "P"))
        this.Focus()
        ; a second, unhurried click on a cell that says it is editable opens
        ; the editor — the rename gesture, generalised to any column
        cell := this._Up(el, "data-col")
        if (cell && picked && !GetKeyState("Ctrl", "P") && !GetKeyState("Shift", "P")) {
            c := st.Column(AxWindow._Attr(cell, "data-col"))
            if (IsObject(c) && c.Edit && StrLower(String(c.Render)) != "rating") {
                if (this._clickKey = key && A_TickCount - this._clickAt > DllCall("GetDoubleClickTime", "UInt")
                    && A_TickCount - this._clickAt < 2500)
                    return this._Open(cell, key, c)
            }
        }
        ; Trident redraws the row under the pointer, so the second click lands
        ; on a new element and arrives as a click rather than a dblclick
        now := A_TickCount
        if (this._clickKey = key && now - this._clickAt <= DllCall("GetDoubleClickTime", "UInt")) {
            this._clickKey := "", this._dblAt := now
            this._Activate(key)
        } else
            this._clickKey := key, this._clickAt := now
    }
    _DblClick(ev) {
        try el := ev.srcElement
        catch
            return
        if (grip := this._Up(el, "data-grip"))
            return this.AutoSize(AxWindow._Attr(grip, "data-grip"))
        row := this._Up(el, "data-k")
        if !row
            return
        if (this.HasOwnProp("_dblAt") && A_TickCount - this._dblAt < 800)
            return                                ; _Click counted it already
        this._clickKey := ""
        this._Activate(AxWindow._Attr(row, "data-k"))
    }
    _Activate(key) {
        it := this.State.Find(key)
        if IsObject(it)
            this.State.Activate(it)
        return this
    }
    _Menu(ev) {
        try el := ev.srcElement
        catch
            return
        st := this.State
        ; on the head: which columns to show
        try {
            if (this._Up(el, "data-col") && this._Up(el, "data-col").tagName = "TH")
                return this.ColumnMenu(ev.clientX, ev.clientY)
        }
        row := this._Up(el, "data-k")
        it := ""
        if row {
            key := AxWindow._Attr(row, "data-k")
            if !st.Sel.Has(key)
                st.Pick(key, false, false)
            it := st.Find(key)
        }
        items := []
        for fn in st._cbs["menu"].Clone() {
            r := ""
            try r := fn(it, st)
            if (r is Array)
                items := r
        }
        if !items.Length
            items := this._DefaultMenu(it)
        if items.Length {
            x := "", y := ""
            try x := ev.clientX, y := ev.clientY
            this.W.ShowMenu(items, x, y)
        }
    }
    _DefaultMenu(it) {
        st := this.State
        items := []
        if IsObject(it) {
            items.Push(["Open", this._ActFn(it.Key)])
            if AxFileSource.IsBranch(it)
                items.Push({Label: "Pinned to the places list",
                            Checked: st.IsPinned(it.Path), Click: this._PinFn(it.Path)})
            items.Push(["Copy the path", this._CopyFn(it.Path)])
            items.Push("-")
        }
        items.Push(["Refresh", (*) => st.Refresh()])
        items.Push(["Select all", (*) => st.SelectAll()])
        items.Push(["Invert selection", (*) => st.Invert()])
        items.Push("-")
        items.Push({Label: "Hidden items", Checked: st.Hidden, Click: (*) => st.Toggle("hidden")})
        items.Push({Label: "Tick boxes", Checked: st.Checks, Click: (*) => st.Toggle("checks")})
        return items
    }
    _ActFn(key) => (*) => this._Activate(key)
    _PinFn(path) => (*) => this.State.TogglePin(path)
    _CopyFn(path) => (*) => A_Clipboard := path

    ; --- the keyboard: arrows, Home/End, Enter, Backspace, space, and typing
    ; a few letters to jump to a name
    _Key(ev) {
        st := this.State
        try code := ev.keyCode
        catch
            return
        if IsObject(this._edit) {
            if (code = 13)
                return this._Commit(true)
            if (code = 27)
                return this._Commit(false)
            return
        }
        keys := []
        for r in st.Rows
            if (r.Kind = "item")
                keys.Push(r.Item.Key)
        if !keys.Length
            return
        at := 0
        for i, k in keys
            if (k = st.Cursor)
                at := i
        step := (st.Mode = "details" || st.Mode = "list") ? 1 : this._PerRow()
        switch code {
        case 38: to := at - step                       ; up
        case 40: to := at + step                       ; down
        case 37: to := at - ((st.Mode = "details") ? 0 : 1)
        case 39: to := at + ((st.Mode = "details") ? 0 : 1)
        case 33: to := at - step * 5
        case 34: to := at + step * 5
        case 36: to := 1
        case 35: to := keys.Length
        case 13:
            return st.Cursor != "" ? this._Activate(st.Cursor) : ""
        case 8:
            return st.Up()
        case 32:
            return (st.Checks && st.Cursor != "") ? st.Check(st.Cursor) : ""
        case 65:                                        ; Ctrl+A
            return GetKeyState("Ctrl", "P") ? st.SelectAll() : this._Type(ev)
        case 116:                                       ; F5
            return st.Refresh()
        case 113:                                       ; F2
            return (st.Cursor != "") ? this._OpenNamed(st.Cursor) : ""
        default:
            return this._Type(ev)
        }
        to := Max(1, Min(keys.Length, to))
        if (!at && to)
            to := 1
        st.Pick(keys[to], false, GetKeyState("Shift", "P"))
        this._Scroll(keys[to])
        try ev.returnValue := false
    }
    ; How many boxes fit on a line: the arrows have to move by a row, and a
    ; flowed layout only knows that once it is on the screen.
    _PerRow() {
        try {
            flow := this.W.El(this.Id "_body").getElementsByTagName("div")
            box := 0, wide := 0
            loop flow.length {
                el := flow.item(A_Index - 1)
                if AxWindow._HasClass(el, "fv-box") {
                    r := el.getBoundingClientRect()
                    box := r.right - r.left
                    break
                }
            }
            r := this.W.El(this.Id "_scroll").getBoundingClientRect()
            wide := r.right - r.left
            if (box > 0 && wide > 0)
                return Max(1, Floor(wide / box))
        }
        return 1
    }
    _Type(ev) {
        try ch := Chr(ev.keyCode)
        catch
            return
        if !RegExMatch(ch, "^[A-Za-z0-9 ._-]$")
            return
        st := this.State
        now := A_TickCount
        if (!this.HasOwnProp("_findAt") || now - this._findAt > 900)
            this._find := ""
        this._findAt := now, this._find .= ch
        for r in st.Rows
            if (r.Kind = "item" && InStr(r.Item.Name, this._find) = 1) {
                st.Pick(r.Item.Key, false, false)
                this._Scroll(r.Item.Key)
                return
            }
    }
    _Scroll(key) {
        try {
            nodes := this.W.El(this.Id "_body").getElementsByTagName("*")
            loop nodes.length {
                el := nodes.item(A_Index - 1)
                if (AxWindow._Attr(el, "data-k") = key) {
                    el.scrollIntoView(false)
                    return
                }
            }
        }
    }

    ; ------------------------------------------------------- editable cells
    ; The cell keeps its size and gains a text box; Enter or losing the focus
    ; keeps what was typed, Escape puts the old value back.
    _Open(cell, key, col) {
        this._Commit(false)
        st := this.State
        it := st.Find(key)
        if !IsObject(it)
            return
        v := st.Cell(it, col.Key)
        this._edit := {Key: key, Col: col.Key, Was: v, Cell: cell}
        E := (x) => AxWindow._Esc(x)
        html := ""
        if (StrLower(String(col.Edit)) = "choice" && col.Options != "") {
            html := '<select class="fv-input" id="' E(this.Id) '_ed">'
            for opt in (col.Options is Array ? col.Options : StrSplit(String(col.Options), "|"))
                html .= '<option value="' E(opt) '"' (String(opt) = String(v) ? " selected" : "") '>'
                     .  E(opt) '</option>'
            html .= '</select>'
        } else
            html := '<input class="fv-input" id="' E(this.Id) '_ed" type="text" value="' E(v) '">'
        try {
            cell.innerHTML := html
            el := this.W.El(this.Id "_ed")
            el.focus()
            try el.select()
        }
        return this
    }
    _OpenNamed(key) {
        c := this.State.Column("name")
        if (!IsObject(c) || !c.Edit)
            return this
        try {
            nodes := this.W.El(this.Id "_body").getElementsByTagName("td")
            loop nodes.length {
                el := nodes.item(A_Index - 1)
                if (AxWindow._Attr(el, "data-col") = "name") {
                    row := this._Up(el, "data-k")
                    if (row && AxWindow._Attr(row, "data-k") = key)
                        return this._Open(el, key, c)
                }
            }
        }
        return this
    }
    _Commit(keep := true) {
        if !IsObject(this._edit)
            return this
        e := this._edit
        this._edit := ""
        v := e.Was
        if keep {
            try v := this.W.El(this.Id "_ed").value
        }
        if (keep && String(v) != String(e.Was)) {
            c := this.State.Column(e.Col)
            if (IsObject(c) && StrLower(String(c.Edit)) = "number")
                v := IsNumber(v) ? Number(v) : 0
            this.State.Edit(e.Key, e.Col, v)          ; redraws everything
            return this
        }
        this.Render()
        return this
    }
    _Blur() {
        this.W.RemoveClass(this.Id, "focus")
        ; the focus leaves the box the moment the editor opens, so a commit
        ; here has to wait for the editor to be gone or it eats its own input
        if IsObject(this._edit)
            SetTimer(this._BlurFn(), -120)
    }
    _BlurFn() => (*) => this._BlurLater()
    _BlurLater() {
        if !IsObject(this._edit)
            return
        try {
            if (this.W.Doc.activeElement.id = this.Id "_ed")
                return
        }
        this._Commit(true)
    }

    ; -------------------------------------------------------- column sizing
    _Down(ev) {
        try el := ev.srcElement
        catch
            return
        grip := this._Up(el, "data-grip")
        if !grip {
            if (this.Drag && this._Up(el, "data-k"))
                this._DragStart(ev)
            return
        }
        try {
            if !AxWindow._IsLeft(ev)
                return
        }
        key := AxWindow._Attr(grip, "data-grip")
        c := this.State.Column(key)
        if !IsObject(c)
            return
        from := 0
        try from := ev.clientX
        this._grip := {Key: key, Start: from, Was: c.Width}
        this.W.PointerCapture((x, y, *) => this._GripMove(x), (*) => this._GripUp())
        try ev.returnValue := false
    }
    _GripMove(x) {
        if !IsObject(this._grip)
            return
        g := this._grip
        this.State.SetWidth(g.Key, g.Was + (x - g.Start))
    }
    _GripUp() {
        this._grip := ""
    }
    ; Size a column to the longest thing in it. The text of a cell sits in its
    ; own span, so its box still reports the full width where the cell clips.
    AutoSize(key) {
        c := this.State.Column(key)
        if !IsObject(c)
            return this
        wide := 0
        try {
            nodes := this.W.El(this.Id "_body").getElementsByTagName("td")
            loop nodes.length {
                el := nodes.item(A_Index - 1)
                if (AxWindow._Attr(el, "data-col") != key)
                    continue
                n := el.getElementsByTagName("*")
                inner := 0
                loop n.length {
                    r := n.item(A_Index - 1).getBoundingClientRect()
                    inner := Max(inner, r.right - r.left)
                }
                wide := Max(wide, inner + 44)
            }
        }
        if (wide > 0)
            this.State.SetWidth(key, wide)
        return this
    }
    ColumnMenu(x := "", y := "") {
        st := this.State
        items := []
        for c in st.Cols
            items.Push({Label: c.Title, Checked: !c.Hidden,
                        Click: this._ColFn(c.Key), Disabled: !c.Hideable})
        items.Push("-")
        items.Push(["Size this column to fit", (*) => this.AutoSize(st.SortKey)])
        items.Push(["Show every column", (*) => this._ShowAll()])
        this.W.ShowMenu(items, x, y)
        return this
    }
    _ColFn(key) => (*) => this.State.ToggleColumn(key)
    _ShowAll() {
        for c in this.State.Cols
            c.Hidden := false
        this.State._Emit("columns")
        return this
    }

    ; --------------------------------------------------------- drag and drop
    ; Files dragged in from the rest of Windows. The handler decides what that
    ; means; the view only says where they landed.
    _Dropped(files) {
        st := this.State
        target := ""
        try {
            el := this.W.Doc.elementFromPoint(this._DropPt().X, this._DropPt().Y)
            row := this._Up(el, "data-k")
            if row {
                it := st.Find(AxWindow._Attr(row, "data-k"))
                if (IsObject(it) && AxFileSource.IsBranch(it))
                    target := it
            }
        }
        if (target = "")
            target := st.Source.Item(st.Path)
        st._Fire("drop", [files, target, st])
        return this
    }
    _DropPt() {
        pt := Buffer(8, 0)
        try {
            DllCall("GetCursorPos", "Ptr", pt)
            DllCall("ScreenToClient", "Ptr", this.W.Gui.Hwnd, "Ptr", pt)
        }
        scale := A_ScreenDPI / 96
        return {X: NumGet(pt, 0, "Int") / scale, Y: NumGet(pt, 4, "Int") / scale}
    }
    ; Dragging items within the view: onto a folder is a move, and what a
    ; move means is the handler's business. Trident's own drag events do not
    ; reach a component here, so this is the pointer capture the sliders use.
    _DragStart(ev) {
        try {
            if !AxWindow._IsLeft(ev)
                return
        }
        row := this._Up(ev.srcElement, "data-k")
        if !row
            return
        key := AxWindow._Attr(row, "data-k")
        from := this._DropPt()
        this._drag := {Key: key, X: from.X, Y: from.Y, Live: false, Over: ""}
        this.W.PointerCapture((x, y, *) => this._DragMove(x, y), (*) => this._DragUp())
    }
    _DragMove(x, y) {
        if !IsObject(this._drag)
            return
        d := this._drag
        if (!d.Live && Abs(x - d.X) < 5 && Abs(y - d.Y) < 5)
            return
        if !d.Live {
            d.Live := true
            st := this.State
            if !st.Sel.Has(d.Key)
                st.Pick(d.Key, false, false)
            this.W.BodyClass("fv-dragging", true)
        }
        over := ""
        try {
            el := this.W.Doc.elementFromPoint(x, y)
            row := this._Up(el, "data-k")
            if row {
                it := this.State.Find(AxWindow._Attr(row, "data-k"))
                if (IsObject(it) && AxFileSource.IsBranch(it) && !this.State.Sel.Has(it.Key))
                    over := it.Key
            }
        }
        if (over != d.Over) {
            this._Over(d.Over, false)
            this._Over(over, true)
            d.Over := over
        }
    }
    _Over(key, on) {
        if (key = "")
            return
        try {
            nodes := this.W.El(this.Id "_body").getElementsByTagName("*")
            loop nodes.length {
                el := nodes.item(A_Index - 1)
                if (AxWindow._Attr(el, "data-k") = key)
                    AxWindow._SetClass(el, "droptarget", on)
            }
        }
    }
    _DragUp() {
        if !IsObject(this._drag)
            return
        d := this._drag
        this._drag := ""
        this.W.BodyClass("fv-dragging", false)
        this._Over(d.Over, false)
        if (!d.Live || d.Over = "")
            return
        st := this.State
        target := st.Find(d.Over)
        paths := []
        for it in st.Selected()
            paths.Push(it.Path)
        if (paths.Length && IsObject(target))
            st._Fire("drop", [paths, target, st])
    }

    ; ------------------------------------------------------------------ add
    static _Add(container, opts, spec) {
        o := container._Opt(opts, "fv")
        st := AxFileView._State(spec, o)
        cfg := {Mode: st.Mode}
        if (o.H != "")
            cfg.Height := Integer(o.H), cfg.Fixed := o.Flags.Has("fixed")
        cfg.Style := (o.W != "" ? "width:" o.W "px;" : "")
                   . (o.Top != "" ? "margin-top:" o.Top "px;" : "")
                   . (o.KV.Has("style") ? o.KV["style"] : "")
        cfg.Class := ((o.W = "" || o.Flags.Has("fill")) ? "fill" : "")
                   . (o.KV.Has("class") ? " " o.KV["class"] : "")
        cfg.Drop := !o.Flags.Has("nodrop")
        cfg.Drag := !o.Flags.Has("nodrag")
        if o.KV.Has("badges")
            cfg.Badges := StrSplit(o.KV["badges"], ",")
        c := container._Reg(o, "FileView", AxFileView.Html(o.Id, cfg))
        container.G.OnReady((w) => AxFileView(w, o.Id, st, cfg))
        return c
    }
}

; =============================================================================
;  AxFileTree — the folders, down the side.
;
;  Branches only, fetched when a twisty is opened and not before, so a tree
;  over a slow source costs one listing per folder you actually look in. Going
;  somewhere in the view opens the tree down to it and highlights it; clicking
;  in the tree goes there. Nothing is kept in the tree that is not in the
;  state, so the two can never disagree.
; =============================================================================
class AxFileTree {
    static Html(id, cfg := "") {
        o := (n, d := "") => (IsObject(cfg) && cfg.HasOwnProp(n)) ? cfg.%n% : d
        E := (x) => AxWindow._Esc(x)
        return '<div class="ft' (o("Class", "") != "" ? " " E(o("Class", "")) : "") '" id="' E(id) '"'
             . ' data-role="filetree"' (o("Style", "") != "" ? ' style="' E(o("Style", "")) '"' : "") '>'
             . '<div class="ft-body" id="' E(id) '_body" tabindex="0"></div></div>'
    }
    __New(win, id, state, cfg := "") {
        this.W := win, this.Id := id, this.State := state
        this.Cfg := IsObject(cfg) ? cfg : {}
        AxRich.Use(win, "FileView")
        AxRich.Bind(win, id, this)
        state.Attach(this)
        win.On("click", id, (el, ev) => this._Click(ev))
        win.On("contextmenu", id, (el, ev) => this._Menu(ev))
        win.On("keydown", id, (el, ev) => this._Key(ev))
        win.On("focusin", id, (*) => this.W.AddClass(this.Id, "focus"))
        win.On("focusout", id, (*) => this.W.RemoveClass(this.Id, "focus"))
        this._find := "", this._findAt := 0
        this._OpenTo(state.Path)          ; the root, and the way down to here
        this.Render()
    }
    Update(what) {
        switch what {
        case "select", "check", "columns", "mode": return
        }
        if (what = "path")
            this._OpenTo(this.State.Path)
        this.Render()
    }
    ; Opening the tree down to a path is what makes it follow the view.
    _OpenTo(path) {
        src := this.State.Source, p := String(path)
        loop 64 {
            if (p = "" || p = src.RootPath)
                break
            p := src.Parent(p)
            if (p = "")
                break
            this.State.Open[p] := true
        }
        this.State.Open[src.RootPath] := true
        return this
    }
    Render() {
        E := (x) => AxWindow._Esc(x)
        src := this.State.Source
        root := {Path: src.RootPath, Name: src.Label, Icon: src.Icon, Kind: "root", Kids: 1}
        html := this._Row(root, 0, true)
        if this.State.Open.Has(src.RootPath)
            html .= this._Level(src.RootPath, 1)
        try this.W.El(this.Id "_body").innerHTML := html
        return this
    }
    _Level(path, depth) {
        if (depth > 24)
            return ""
        out := ""
        kids := []
        try kids := this.State.Source.Branches(path)
        for it in kids {
            if (it.Hidden && !this.State.Hidden)
                continue
            out .= this._Row(it, depth, false)
            if this.State.Open.Has(it.Path)
                out .= this._Level(it.Path, depth + 1)
        }
        return out
    }
    _Row(it, depth, isRoot) {
        E := (x) => AxWindow._Esc(x)
        open := this.State.Open.Has(it.Path)
        leaf := (!isRoot && it.Kids = 0)
        return '<div class="ft-row' (this.State.Path = it.Path ? " cur" : "") '"'
             . ' data-p="' E(it.Path) '" style="padding-left:' (8 + depth * 16) 'px">'
             . '<span class="ft-twisty ico' (leaf ? " leaf" : (open ? " open" : "")) '" data-twist="1">'
             . (leaf ? "" : "&#xE76C;") '</span>'
             . '<span class="ico ft-ico">&#x' (it.Icon != "" ? it.Icon : "E8B7") ';</span>'
             . '<span class="ft-name">' E(it.Name) '</span></div>'
    }
    ; The rows that are on screen, in the order they are drawn. The keyboard
    ; walks this rather than the tree, so an arrow moves by a row and does not
    ; have to know how deep it is.
    _Flat() {
        src := this.State.Source
        out := [{Path: src.RootPath, Name: src.Label, Depth: 0, Kids: 1}]
        if this.State.Open.Has(src.RootPath)
            this._FlatLevel(src.RootPath, 1, out)
        return out
    }
    _FlatLevel(path, depth, out) {
        if (depth > 24)
            return
        kids := []
        try kids := this.State.Source.Branches(path)
        for it in kids {
            if (it.Hidden && !this.State.Hidden)
                continue
            out.Push({Path: it.Path, Name: it.Name, Depth: depth, Kids: it.Kids})
            if this.State.Open.Has(it.Path)
                this._FlatLevel(it.Path, depth + 1, out)
        }
    }
    ; Arrows move and go, as a folder pane has always done; right opens a
    ; branch and then steps into it, left closes it and then steps out; and a
    ; few letters jump to a name, the same gesture the view has.
    _Key(ev) {
        try code := ev.keyCode
        catch
            return
        rows := this._Flat()
        if !rows.Length
            return
        at := 1
        for i, r in rows
            if (r.Path = this.State.Path)
                at := i
        cur := rows[at]
        switch code {
        case 38: to := at - 1                                  ; up
        case 40: to := at + 1                                  ; down
        case 36: to := 1                                       ; Home
        case 35: to := rows.Length                             ; End
        case 33: to := at - 10
        case 34: to := at + 10
        case 39:                                               ; right
            if (cur.Kids != 0 && !this.State.Open.Has(cur.Path)) {
                this.State.Open[cur.Path] := true
                this.Render()
                return this._Stop(ev)
            }
            to := at + 1
        case 37:                                               ; left
            if this.State.Open.Has(cur.Path) {
                this.State.Open.Delete(cur.Path)
                this.Render()
                return this._Stop(ev)
            }
            up := this.State.Source.Parent(cur.Path)
            if (up != "" || cur.Path != this.State.Source.RootPath)
                this.State.Go(up)
            return this._Stop(ev)
        case 13, 32:                                           ; Enter, space
            if this.State.Open.Has(cur.Path)
                this.State.Open.Delete(cur.Path)
            else
                this.State.Open[cur.Path] := true
            this.Render()
            return this._Stop(ev)
        case 116:                                              ; F5
            this.State.Refresh()
            return this._Stop(ev)
        default:
            return this._Type(ev, rows)
        }
        to := Max(1, Min(rows.Length, to))
        if (rows[to].Path != this.State.Path)
            this.State.Go(rows[to].Path)
        this._Show(rows[to].Path)
        return this._Stop(ev)
    }
    _Stop(ev) {
        try ev.returnValue := false
    }
    _Type(ev, rows) {
        try ch := Chr(ev.keyCode)
        catch
            return
        if !RegExMatch(ch, "^[A-Za-z0-9 ._-]$")
            return
        now := A_TickCount
        if (now - this._findAt > 900)
            this._find := ""
        this._findAt := now, this._find .= ch
        for r in rows
            if (InStr(r.Name, this._find) = 1) {
                this.State.Go(r.Path)
                this._Show(r.Path)
                return this._Stop(ev)
            }
    }
    _Show(path) {
        try {
            nodes := this.W.El(this.Id "_body").getElementsByTagName("div")
            loop nodes.length {
                el := nodes.item(A_Index - 1)
                if (AxWindow._Attr(el, "data-p") = path) {
                    el.scrollIntoView(false)
                    return
                }
            }
        }
    }
    _Click(ev) {
        try el := ev.srcElement
        catch
            return
        try this.W.El(this.Id "_body").focus()       ; so the arrows carry on from here
        twist := false
        n := 0
        while (IsObject(el) && n++ < 6) {
            if (AxWindow._Attr(el, "data-twist") != "")
                twist := true
            p := AxWindow._Attr(el, "data-p")
            if (p != "") {
                ; the twisty toggles; the row opens and goes. Clicking the folder
                ; you are already in used to do nothing at all -- Go() has nothing
                ; to do, so the expand was never painted -- so that toggles too.
                if (twist || p = this.State.Path) {
                    if this.State.Open.Has(p)
                        this.State.Open.Delete(p)
                    else
                        this.State.Open[p] := true
                    return this.Render()
                }
                this.State.Open[p] := true
                this.State.Go(p)
                return this.Render()
            }
            el := AxWindow._ParentEl(el)
        }
    }
    _Menu(ev) {
        try el := ev.srcElement
        catch
            return
        p := ""
        n := 0
        while (IsObject(el) && n++ < 6) {
            p := AxWindow._Attr(el, "data-p")
            if (p != "")
                break
            el := AxWindow._ParentEl(el)
        }
        if (p = "")
            return
        st := this.State
        x := "", y := ""
        try x := ev.clientX, y := ev.clientY
        this.W.ShowMenu([["Open", this._GoFn(p)],
                         ["Expand", this._OpenFn(p, true)],
                         ["Collapse", this._OpenFn(p, false)], "-",
                         ["Refresh", (*) => st.Refresh()]], x, y)
    }
    _GoFn(p) => (*) => this.State.Go(p)
    _OpenFn(p, on) => (*) => (on ? this.State.Open[p] := true
                                 : (this.State.Open.Has(p) ? this.State.Open.Delete(p) : ""), this.Render())

    static _Add(container, opts, spec) {
        o := container._Opt(opts, "ft")
        st := AxFileView._State(spec, o)
        cfg := {}
        cfg.Style := (o.W != "" ? "width:" o.W "px;" : "") (o.H != "" ? "height:" o.H "px;" : "")
                   . (o.Top != "" ? "margin-top:" o.Top "px;" : "")
                   . (o.KV.Has("style") ? o.KV["style"] : "")
        cfg.Class := (o.Flags.Has("fill") ? "fill" : "") (o.KV.Has("class") ? " " o.KV["class"] : "")
        c := container._Reg(o, "FileTree", AxFileTree.Html(o.Id, cfg))
        container.G.OnReady((w) => AxFileTree(w, o.Id, st, cfg))
        return c
    }
}

; =============================================================================
;  AxFilePath — where you are, with two faces.
;
;  Normally a trail of steps, each with a chevron after it that drops the
;  folders beside it, so you can go sideways without going back first. Click
;  the empty space after the last step and the whole thing turns into the path
;  as text, with the caret in it: type, press Enter, and you are there.
;  Escape puts the steps back.
;
;  Options: NoEdit (the steps only), NoChevrons, Prefix=scheme (show "reg:\"
;  and friends in the text face).
; =============================================================================
class AxFilePath {
    static Html(id, cfg := "") {
        o := (n, d := "") => (IsObject(cfg) && cfg.HasOwnProp(n)) ? cfg.%n% : d
        E := (x) => AxWindow._Esc(x)
        return '<div class="fp' (o("Class", "") != "" ? " " E(o("Class", "")) : "") '" id="' E(id) '"'
             . ' data-role="filepath"' (o("Style", "") != "" ? ' style="' E(o("Style", "")) '"' : "") '>'
             . '<div class="fp-crumbs" id="' E(id) '_crumbs"></div>'
             . '<input class="fp-box" id="' E(id) '_box" type="text" autocomplete="off" spellcheck="false">'
             . '</div>'
    }
    __New(win, id, state, cfg := "") {
        this.W := win, this.Id := id, this.State := state
        this.Cfg := IsObject(cfg) ? cfg : {}
        o := (n, d := "") => this.Cfg.HasOwnProp(n) ? this.Cfg.%n% : d
        this.Editable := o("Editable", true)
        this.Chevrons := o("Chevrons", true)
        this.Editing := false
        AxRich.Use(win, "FileView")
        AxRich.Bind(win, id, this)
        state.Attach(this)
        win.On("click", id, (el, ev) => this._Click(ev))
        win.On("keydown", id "_box", (el, ev) => this._Key(el, ev))
        win.On("focusout", id "_box", (*) => this._Leave())
        win.Popover(id "_pop", {On: "none", Build: (*) => this._Branches(), Class: "fp-pop", Align: "left", Gap: 2})
        win.On("click", id "_poplist", (el, ev) => this._PopClick(ev))
        this.Render()
    }
    Update(what) {
        switch what {
        case "path", "items", "attach": this.Render()
        }
    }
    Render() {
        E := (x) => AxWindow._Esc(x)
        st := this.State, src := st.Source
        crumbs := []
        try crumbs := src.Crumbs(st.Path)
        h := ""
        for i, c in crumbs {
            last := (i = crumbs.Length)
            h .= '<span class="fp-step' (last ? " cur" : "") '" data-p="' E(c.Path) '">'
              .  (c.Icon != "" ? '<span class="ico">&#x' E(c.Icon) ';</span>' : "")
              .  '<span class="fp-t">' E(c.Label) '</span></span>'
            if this.Chevrons
                h .= '<span class="fp-chev ico" data-chev="' E(c.Path) '">&#xE76C;</span>'
        }
        ; the rest of the bar: clicking it is how you get to the text face
        h .= '<span class="fp-rest" data-rest="1"' (this.Editable ? ' data-tip="Click to type a path"' : "") '></span>'
        try {
            this.W.El(this.Id "_crumbs").innerHTML := h
            this.W.El(this.Id "_box").value := this.Text()
        }
        this._Face(false)
        return this
    }
    ; The path as you would type it. A source with a scheme of its own says so,
    ; so "reg:HKCU\Software" cannot be mistaken for a folder on disk.
    Text() {
        st := this.State, src := st.Source
        p := String(st.Path)
        if (p = "" && src.RootPath = "")
            return src.Label
        return (src.Scheme = "file") ? p : (src.Scheme ":" p)
    }
    _Face(edit) {
        this.Editing := edit && this.Editable
        try {
            this.W.El(this.Id "_crumbs").style.display := this.Editing ? "none" : "block"
            this.W.El(this.Id "_box").style.display := this.Editing ? "block" : "none"
            if this.Editing {
                el := this.W.El(this.Id "_box")
                el.value := this.Text()
                el.focus()
                try el.select()
            }
        }
        AxWindow._SetClass(this.W.El(this.Id), "editing", this.Editing)
        return this
    }
    Edit() => this._Face(true)
    _Leave() {
        if this.Editing
            SetTimer(this._LeaveFn(), -100)
    }
    _LeaveFn() => (*) => (this.Editing ? this.Render() : "")
    _Key(el, ev) {
        try code := ev.keyCode
        catch
            return
        if (code = 13) {
            v := ""
            try v := el.value
            this._Face(false)
            return this.GoText(v)
        }
        if (code = 27)
            return this.Render()
    }
    ; What the text face does with what was typed. A scheme prefix is stripped;
    ; a path the source does not know about is reported rather than obeyed.
    GoText(text) {
        st := this.State, src := st.Source
        p := Trim(String(text))
        if (src.Scheme != "file" && InStr(p, src.Scheme ":") = 1)
            p := SubStr(p, StrLen(src.Scheme) + 2)
        if (p = src.Label)
            p := src.RootPath
        ok := false
        try ok := src.Exists(p)
        if ok
            return st.Go(p)
        st.Error := Chr(0x201C) p Chr(0x201D) " is not a place this can go."
        st._Fire("error", [st.Error, st])
        st._Emit("items")
        return st
    }
    _Click(ev) {
        try el := ev.srcElement
        catch
            return
        n := 0
        while (IsObject(el) && n++ < 6) {
            if (AxWindow._Attr(el, "data-rest") != "")
                return this.Editable ? this._Face(true) : ""
            chev := AxWindow._Attr(el, "data-chev")
            if (chev != "")
                return this._Drop(el, chev)
            p := AxWindow._Attr(el, "data-p")
            if (p != "")
                return this.State.Go(p)
            el := AxWindow._ParentEl(el)
        }
    }
    ; The chevron's popover: the folders inside that step, so you can step
    ; sideways from halfway along the trail.
    _Drop(el, path) {
        this._popAt := path
        ; the popover anchors to an id, and only one chevron may wear it
        try {
            old := this.W.El(this.Id "_pop")
            if IsObject(old)
                old.id := ""
        }
        try el.id := this.Id "_pop"
        this.W.Popover(this.Id "_pop", {On: "none", Build: (*) => this._Branches(),
                                        Class: "fp-pop", Align: "left", Gap: 2})
        this.W.ShowPopover(this.Id "_pop")
        return this
    }
    _Branches() {
        E := (x) => AxWindow._Esc(x)
        st := this.State
        kids := []
        try kids := st.Source.Branches(this._popAt)
        h := '<div class="fp-poplist" id="' E(this.Id) '_poplist">'
        if !kids.Length
            h .= '<div class="fp-pi empty">No folders here</div>'
        for it in kids {
            if (it.Hidden && !st.Hidden)
                continue
            h .= '<div class="fp-pi' (InStr(st.Path, it.Path) = 1 ? " on" : "") '" data-p="' E(it.Path) '">'
              .  '<span class="ico">&#x' (it.Icon != "" ? it.Icon : "E8B7") ';</span>' E(it.Name) '</div>'
        }
        return h "</div>"
    }
    _PopClick(ev) {
        try el := ev.srcElement
        catch
            return
        n := 0
        while (IsObject(el) && n++ < 4) {
            p := AxWindow._Attr(el, "data-p")
            if (p != "") {
                this.W.ClosePopover()
                return this.State.Go(p)
            }
            el := AxWindow._ParentEl(el)
        }
    }

    static _Add(container, opts, spec) {
        o := container._Opt(opts, "fp")
        st := AxFileView._State(spec, o)
        cfg := {Editable: !o.Flags.Has("noedit"), Chevrons: !o.Flags.Has("nochevrons")}
        cfg.Style := (o.W != "" ? "width:" o.W "px;" : "") (o.Top != "" ? "margin-top:" o.Top "px;" : "")
                   . (o.KV.Has("style") ? o.KV["style"] : "")
        cfg.Class := ((o.W = "" || o.Flags.Has("fill")) ? "fill" : "")
                   . (o.KV.Has("class") ? " " o.KV["class"] : "")
        c := container._Reg(o, "FilePath", AxFilePath.Html(o.Id, cfg))
        container.G.OnReady((w) => AxFilePath(w, o.Id, st, cfg))
        return c
    }
}

; =============================================================================
;  AxFilePreview — what the thing you picked is.
;
;  The pane itself knows nothing about files. It asks a list of renderers, in
;  order, which of them will take this item, and the first that says yes draws
;  it. Adding a kind of preview is therefore one call and no edits here:
;
;      AxFilePreview.Register("pdf", (it, st) => AxFileSource.Ext(it.Name) = "pdf",
;          (it, st, w) => '<embed src="' AxSys.FileUrl(it.Path) '" ...>', 40)
;
;  match(item, state) -> true when this renderer takes it
;  draw(item, state, win) -> the markup for the pane
;  order: lower goes first; the built-in ones sit at 100 and the fallback at
;  9000, so anything you add is asked before them unless you say otherwise.
; =============================================================================
class AxFilePreview {
    static Renderers := []
    static Register(name, match, draw, order := 50) {
        for i, r in AxFilePreview.Renderers
            if (r.Name = name) {
                AxFilePreview.Renderers[i] := {Name: name, Match: match, Draw: draw, Order: order}
                return AxFilePreview._Sort()
            }
        AxFilePreview.Renderers.Push({Name: name, Match: match, Draw: draw, Order: order})
        return AxFilePreview._Sort()
    }
    static Remove(name) {
        for i, r in AxFilePreview.Renderers
            if (r.Name = name) {
                AxFilePreview.Renderers.RemoveAt(i)
                return true
            }
        return false
    }
    static _Sort() {
        list := AxFilePreview.Renderers
        loop list.Length - 1 {
            i := A_Index + 1, v := list[i], j := i - 1
            while (j >= 1 && list[j].Order > v.Order) {
                list[j + 1] := list[j]
                j--
            }
            list[j + 1] := v
        }
        return true
    }
    static _builtin := AxFilePreview._Builtins()
    static _Builtins() {
        ; a picture, where the source can produce one
        AxFilePreview.Register("image",
            (it, st) => st.Thumb(it) != "",
            (it, st, w) => '<div class="fpv-art"><img src="' AxWindow._Esc(st.Thumb(it)) '"></div>'
                         . AxFilePreview.Facts(it, st), 100)
        ; a folder: what is in it, counted
        AxFilePreview.Register("folder",
            (it, st) => AxFileSource.IsBranch(it),
            (it, st, w) => AxFilePreview.Folder(it, st), 110)
        ; a registry value: its data, big
        AxFilePreview.Register("value",
            (it, st) => (StrLower(String(it.Kind)) = "value"),
            (it, st, w) => '<div class="fpv-data">' AxWindow._Esc(String(it.Data)) '</div>'
                         . AxFilePreview.Facts(it, st), 120)
        ; anything the source will give us as words
        AxFilePreview.Register("text",
            (it, st) => AxFilePreview._Textish(it, st),
            (it, st, w) => '<pre class="fpv-text">'
                         . AxWindow._Esc(SubStr(st.Source.Read(it.Path, 40000), 1, 40000))
                         . '</pre>' AxFilePreview.Facts(it, st), 130)
        ; and when nothing else will have it, say what it is
        AxFilePreview.Register("facts", (it, st) => true,
            (it, st, w) => '<div class="fpv-big"><span class="ico">&#x'
                         . (it.Icon != "" ? it.Icon : "E7C3") ';</span></div>'
                         . AxFilePreview.Facts(it, st), 9000)
        return true
    }
    static _Textish(it, st) {
        if AxFileSource.IsBranch(it)
            return false
        t := ""
        try t := st.Source.Read(it.Path, 4096)
        return (t != "")
    }
    ; The little table under every preview: the properties an item carries.
    static Facts(it, st) {
        E := (x) => AxWindow._Esc(x)
        rows := ""
        Row(k, v) {
            if (String(v) = "")
                return ""
            return '<div class="fpv-row"><span class="fpv-k">' E(k) '</span>'
                 . '<span class="fpv-v">' E(v) '</span></div>'
        }
        rows .= Row("Name", it.Name)
        rows .= Row("Kind", it.Type)
        if (!AxFileSource.IsBranch(it) && IsNumber(it.Size))
            rows .= Row("Size", AxWindow.FileSize(it.Size) " (" it.Size " bytes)")
        rows .= Row("Modified", AxFileView.Stamp(it.Modified))
        rows .= Row("Where", it.Path)
        ; whatever else the source put on it, as long as it is worth showing
        static skip := "Key,Name,Path,Kind,Icon,Size,Modified,Type,Hidden,Kids,Data,Text,Image,Attrib"
        for k, v in it.OwnProps() {
            if InStr("," skip ",", "," k ",")
                continue
            if (IsObject(v) && !(v is Array))
                continue
            rows .= Row(AxFileState.Titleise(k), (v is Array) ? AxFilePreview._Join(v) : v)
        }
        return '<div class="fpv-facts">' rows '</div>'
    }
    static _Join(a) {
        s := ""
        for x in a
            s .= (s = "" ? "" : ", ") String(x)
        return s
    }
    static Folder(it, st) {
        E := (x) => AxWindow._Esc(x)
        kids := []
        try kids := st.Source.List(it.Path)
        folders := 0, files := 0, bytes := 0, names := ""
        for k in kids {
            if AxFileSource.IsBranch(k)
                folders++
            else {
                files++
                if IsNumber(k.Size)
                    bytes += k.Size
            }
            if (A_Index <= 8)
                names .= '<div class="fpv-mini"><span class="ico">&#x'
                      .  (k.Icon != "" ? k.Icon : "E7C3") ';</span>' E(k.Name) '</div>'
        }
        more := kids.Length - 8
        return '<div class="fpv-big"><span class="ico folder">&#x' (it.Icon != "" ? it.Icon : "E8B7") ';</span></div>'
             . '<div class="fpv-sum">' folders " folder" (folders = 1 ? "" : "s") ", "
             . files " file" (files = 1 ? "" : "s")
             . (bytes ? ", " AxWindow.FileSize(bytes) : "") '</div>'
             . '<div class="fpv-list">' names
             . (more > 0 ? '<div class="fpv-mini more">and ' more ' more</div>' : "") '</div>'
             . AxFilePreview.Facts(it, st)
    }

    ; ------------------------------------------------------------- the pane
    static Html(id, cfg := "") {
        o := (n, d := "") => (IsObject(cfg) && cfg.HasOwnProp(n)) ? cfg.%n% : d
        E := (x) => AxWindow._Esc(x)
        return '<div class="fpv' (o("Class", "") != "" ? " " E(o("Class", "")) : "") '" id="' E(id) '"'
             . ' data-role="filepreview"' (o("Style", "") != "" ? ' style="' E(o("Style", "")) '"' : "") '>'
             . '<div class="fpv-head" id="' E(id) '_head"></div>'
             . '<div class="fpv-body" id="' E(id) '_body"></div></div>'
    }
    __New(win, id, state, cfg := "") {
        this.W := win, this.Id := id, this.State := state
        this.Cfg := IsObject(cfg) ? cfg : {}
        AxRich.Use(win, "FileView")
        AxRich.Bind(win, id, this)
        state.Attach(this)
        this.Render()
    }
    Update(what) {
        switch what {
        case "columns", "mode", "check": return
        }
        this.Render()
    }
    Render() {
        E := (x) => AxWindow._Esc(x)
        st := this.State
        sel := st.Selected()
        head := "", body := ""
        if (sel.Length > 1) {
            bytes := 0
            for it in sel
                if (!AxFileSource.IsBranch(it) && IsNumber(it.Size))
                    bytes += it.Size
            head := E(sel.Length " items")
            body := '<div class="fpv-big"><span class="ico">&#xE8B7;</span></div>'
                  . '<div class="fpv-sum">' sel.Length ' selected'
                  . (bytes ? ", " AxWindow.FileSize(bytes) : "") '</div>'
        } else {
            it := sel.Length ? sel[1] : st.Current()
            if !IsObject(it) {
                try it := st.Source.Item(st.Path)
            }
            if !IsObject(it) {
                head := "Nothing selected"
                body := '<div class="fpv-none">Pick something to see it here.</div>'
            } else {
                head := E(it.Name)
                body := this._Draw(it)
            }
        }
        try {
            this.W.El(this.Id "_head").innerHTML := head
            this.W.El(this.Id "_body").innerHTML := body
        }
        return this
    }
    _Draw(it) {
        for r in AxFilePreview.Renderers {
            ok := false
            m := r.Match
            try ok := m(it, this.State)
            if ok {
                d := r.Draw
                try return d(it, this.State, this.W)
                catch as e
                    return '<div class="fpv-none">' AxWindow._Esc(e.Message) '</div>'
            }
        }
        return ""
    }

    static _Add(container, opts, spec) {
        o := container._Opt(opts, "fpv")
        st := AxFileView._State(spec, o)
        cfg := {}
        cfg.Style := (o.W != "" ? "width:" o.W "px;" : "") (o.H != "" ? "height:" o.H "px;" : "")
                   . (o.Top != "" ? "margin-top:" o.Top "px;" : "")
                   . (o.KV.Has("style") ? o.KV["style"] : "")
        cfg.Class := (o.Flags.Has("fill") ? "fill" : "") (o.KV.Has("class") ? " " o.KV["class"] : "")
        c := container._Reg(o, "FilePreview", AxFilePreview.Html(o.Id, cfg))
        container.G.OnReady((w) => AxFilePreview(w, o.Id, st, cfg))
        return c
    }
}

; =============================================================================
;  AxFilePlaces — the short list of somewhere to go.
;
;      g.AddFilePlaces("w220 State=files")
;
;  Quick access, the drives, and whatever the user pinned, in groups with a
;  heading each. A place is {Label, Path, Icon, Group}; the state holds the
;  list, so a caller can replace it wholesale, add one, or let it default to
;  the folders Windows gives everyone a name for.
;
;      st.SetPlaces(AxFileLocal.Known())         ; Desktop, Documents, ...
;      st.AddPlace("Work", "D:\\work", "E821", "Projects")
;      st.Pin(item)                              ; a folder from the view
;      st.PinnedPaths()                          ; to write to an .ini
;
;  A pin appears on hover and on anything pinned; clicking it pins or unpins.
;  Options: NoPins (no pinning at all), NoGroups (one flat list).
; =============================================================================
class AxFilePlaces {
    static Html(id, cfg := "") {
        o := (n, d := "") => (IsObject(cfg) && cfg.HasOwnProp(n)) ? cfg.%n% : d
        E := (x) => AxWindow._Esc(x)
        return '<div class="fpl' (o("Class", "") != "" ? " " E(o("Class", "")) : "") '" id="' E(id) '"'
             . ' data-role="fileplaces"' (o("Style", "") != "" ? ' style="' E(o("Style", "")) '"' : "") '>'
             . '<div class="fpl-body" id="' E(id) '_body" tabindex="0"></div></div>'
    }
    __New(win, id, state, cfg := "") {
        this.W := win, this.Id := id, this.State := state
        this.Cfg := IsObject(cfg) ? cfg : {}
        o := (n, d := "") => this.Cfg.HasOwnProp(n) ? this.Cfg.%n% : d
        this.Pins := o("Pins", true)
        this.Groups := o("Groups", true)
        this._find := "", this._findAt := 0
        AxRich.Use(win, "FileView")
        AxRich.Bind(win, id, this)
        state.Attach(this)
        win.On("click", id, (el, ev) => this._Click(ev))
        win.On("contextmenu", id, (el, ev) => this._Menu(ev))
        win.On("keydown", id, (el, ev) => this._Key(ev))
        this.Render()
    }
    Update(what) {
        switch what {
        case "path", "places", "attach": this.Render()
        }
    }
    Render() {
        E := (x) => AxWindow._Esc(x)
        st := this.State
        list := st.PlaceList()
        html := "", group := ""
        for pl in list {
            g := this.Groups ? String(pl.Group) : ""
            if (g != group) {
                group := g
                if (g != "")
                    html .= '<div class="fpl-head">' E(g) '</div>'
            }
            on := (st.Path = pl.Path)
            pinned := st.IsPinned(pl.Path)
            html .= '<div class="fpl-row' (on ? " cur" : "") '" data-place="' E(pl.Path) '"'
                 .  ' data-tip="' E(pl.Path) '">'
                 .  '<span class="ico fpl-ico">&#x' (pl.Icon != "" ? pl.Icon : "E8B7") ';</span>'
                 .  '<span class="fpl-name">' E(pl.Label) '</span>'
            if this.Pins
                html .= '<span class="ico fpl-pin' (pinned ? " on" : "") '" data-pin="' E(pl.Path) '">'
                     .  (pinned ? "&#xE77A;" : "&#xE718;") '</span>'
            html .= '</div>'
        }
        if (html = "")
            html := '<div class="fpl-none">Nowhere pinned yet.</div>'
        try this.W.El(this.Id "_body").innerHTML := html
        return this
    }
    _Hit(el, attr) {
        n := 0
        while (IsObject(el) && n++ < 5) {
            v := AxWindow._Attr(el, attr)
            if (v != "")
                return v
            el := AxWindow._ParentEl(el)
        }
        return ""
    }
    _Click(ev) {
        try el := ev.srcElement
        catch
            return
        try this.W.El(this.Id "_body").focus()
        if (this.Pins && (pin := this._Hit(el, "data-pin")) != "")
            return this.State.TogglePin(pin)
        p := this._Hit(el, "data-place")
        if (p != "")
            return this.State.Go(p)
    }
    _Menu(ev) {
        try el := ev.srcElement
        catch
            return
        p := this._Hit(el, "data-place")
        if (p = "")
            return
        st := this.State
        x := "", y := ""
        try x := ev.clientX, y := ev.clientY
        this.W.ShowMenu([["Open", this._GoFn(p)], "-",
            {Label: "Pinned", Checked: st.IsPinned(p), Click: this._PinFn(p)},
            ["Remove from the list", this._DropFn(p)]], x, y)
    }
    _GoFn(p) => (*) => this.State.Go(p)
    _PinFn(p) => (*) => this.State.TogglePin(p)
    _DropFn(p) => (*) => this.State.RemovePlace(p)
    ; Arrows walk the list, Enter goes, and a few letters jump to a label.
    _Key(ev) {
        try code := ev.keyCode
        catch
            return
        list := this.State.PlaceList()
        if !list.Length
            return
        at := 0
        for i, pl in list
            if (pl.Path = this.State.Path)
                at := i
        switch code {
        case 38: to := at - 1
        case 40: to := at + 1
        case 36: to := 1
        case 35: to := list.Length
        case 13: return
        default:
            try ch := Chr(code)
            catch
                return
            if !RegExMatch(ch, "^[A-Za-z0-9 ._-]$")
                return
            now := A_TickCount
            if (now - this._findAt > 900)
                this._find := ""
            this._findAt := now, this._find .= ch
            for pl in list
                if (InStr(pl.Label, this._find) = 1) {
                    this.State.Go(pl.Path)
                    break
                }
            try ev.returnValue := false
            return
        }
        if (!at && to)
            to := 1
        to := Max(1, Min(list.Length, to))
        this.State.Go(list[to].Path)
        try ev.returnValue := false
    }

    static _Add(container, opts, spec) {
        o := container._Opt(opts, "fpl")
        st := AxFileView._State(spec, o)
        cfg := {Pins: !o.Flags.Has("nopins"), Groups: !o.Flags.Has("nogroups")}
        cfg.Style := (o.W != "" ? "width:" o.W "px;" : "") (o.H != "" ? "height:" o.H "px;" : "")
                   . (o.Top != "" ? "margin-top:" o.Top "px;" : "")
                   . (o.KV.Has("style") ? o.KV["style"] : "")
        cfg.Class := (o.Flags.Has("fill") ? "fill" : "") (o.KV.Has("class") ? " " o.KV["class"] : "")
        c := container._Reg(o, "FilePlaces", AxFilePlaces.Html(o.Id, cfg))
        container.G.OnReady((w) => AxFilePlaces(w, o.Id, st, cfg))
        return c
    }
}

; =============================================================================
;  AxFileStatus — how many, how big, how many of them you picked.
; =============================================================================
class AxFileStatus {
    static Html(id, cfg := "") {
        o := (n, d := "") => (IsObject(cfg) && cfg.HasOwnProp(n)) ? cfg.%n% : d
        E := (x) => AxWindow._Esc(x)
        return '<div class="fst' (o("Class", "") != "" ? " " E(o("Class", "")) : "") '" id="' E(id) '"'
             . ' data-role="filestatus"' (o("Style", "") != "" ? ' style="' E(o("Style", "")) '"' : "") '>'
             . '<span class="fst-l" id="' E(id) '_l"></span>'
             . '<span class="fst-r" id="' E(id) '_r"></span></div>'
    }
    __New(win, id, state, cfg := "") {
        this.W := win, this.Id := id, this.State := state
        this.Cfg := IsObject(cfg) ? cfg : {}
        this.Views := (IsObject(cfg) && cfg.HasOwnProp("Views")) ? cfg.Views : true
        AxRich.Use(win, "FileView")
        AxRich.Bind(win, id, this)
        state.Attach(this)
        win.On("click", id "_r", (el, ev) => this._Click(ev))
        this.Render()
    }
    Update(what) => this.Render()
    Render() {
        E := (x) => AxWindow._Esc(x)
        st := this.State, s := st.Stats()
        left := s.Count " item" (s.Count = 1 ? "" : "s")
        if s.Selected
            left .= "  ·  " s.Selected " selected"
        else if s.Bytes
            left .= "  ·  " AxWindow.FileSize(s.Bytes)
        if s.Checked
            left .= "  ·  " s.Checked " ticked"
        if (s.Hidden && !st.Hidden)
            left .= "  ·  " s.Hidden " hidden"
        if (st.Error != "")
            left := E(st.Error)
        right := ""
        if this.Views {
            static glyph := Map("details", "E71D", "list", "EA37", "tiles", "E80A",
                                "icons", "E8FD", "thumbs", "E91B")
            for m in st.Modes
                right .= '<span class="fst-v' (st.Mode = m ? " on" : "") '" data-mode="' E(m) '"'
                      .  ' data-tip="' E(AxFileState.Titleise(m)) '"><span class="ico">&#x'
                      .  (glyph.Has(m) ? glyph[m] : "E71D") ';</span></span>'
        }
        try {
            this.W.El(this.Id "_l").innerHTML := (st.Error != "") ? left : E(left)
            this.W.El(this.Id "_r").innerHTML := right
        }
        return this
    }
    _Click(ev) {
        try el := ev.srcElement
        catch
            return
        n := 0
        while (IsObject(el) && n++ < 4) {
            m := AxWindow._Attr(el, "data-mode")
            if (m != "")
                return this.State.SetMode(m)
            el := AxWindow._ParentEl(el)
        }
    }
    static _Add(container, opts, spec) {
        o := container._Opt(opts, "fst")
        st := AxFileView._State(spec, o)
        cfg := {Views: !o.Flags.Has("noviews")}
        cfg.Style := (o.W != "" ? "width:" o.W "px;" : "") (o.Top != "" ? "margin-top:" o.Top "px;" : "")
                   . (o.KV.Has("style") ? o.KV["style"] : "")
        cfg.Class := ((o.W = "" || o.Flags.Has("fill")) ? "fill" : "")
                   . (o.KV.Has("class") ? " " o.KV["class"] : "")
        c := container._Reg(o, "FileStatus", AxFileStatus.Html(o.Id, cfg))
        container.G.OnReady((w) => AxFileStatus(w, o.Id, st, cfg))
        return c
    }
}

; =============================================================================
;  AxFileTools — back, forward, up, refresh, a search box and the knobs.
;
;  Every button here is a call on the state and nothing else, so the toolbar
;  is replaceable: put your own buttons on your own row, call the same
;  methods, and the rest of the parts will not notice.
;
;  Options: NoSearch, NoViews, NoNav, NoOptions, Buttons=back,fwd,up,... to
;  choose exactly which appear and in which order.
; =============================================================================
class AxFileTools {
    static All := ["back", "forward", "up", "refresh", "gap", "search", "gap",
                   "sort", "group", "view", "options"]
    static Html(id, cfg := "") {
        o := (n, d := "") => (IsObject(cfg) && cfg.HasOwnProp(n)) ? cfg.%n% : d
        E := (x) => AxWindow._Esc(x)
        want := o("Buttons", AxFileTools.All)
        h := ""
        for b in want {
            switch b {
            case "gap":     h .= '<span class="fx-gap"></span>'
            case "search":  h .= '<div class="searchbox fx-search"><input type="text" id="' E(id)
                                 . '_q" autocomplete="off" placeholder="' E(o("SearchPlaceholder", "Search this folder"))
                                 . '"><span class="ico">&#xE721;</span></div>'
            default:        h .= AxFileTools._Btn(id, b)
            }
        }
        return '<div class="fx-tools' (o("Class", "") != "" ? " " E(o("Class", "")) : "") '" id="' E(id) '"'
             . ' data-role="filetools"' (o("Style", "") != "" ? ' style="' E(o("Style", "")) '"' : "") '>'
             . h '</div>'
    }
    static _Btn(id, b) {
        static spec := Map(
            "back",    ["E72B", "Back"],        "forward", ["E72A", "Forward"],
            "up",      ["E74A", "Up one level"],"refresh", ["E72C", "Refresh"],
            "sort",    ["E8CB", "Sort"],        "group",   ["F168", "Group"],
            "view",    ["E8A9", "View"],        "options", ["E712", "More"])
        if !spec.Has(b)
            return ""
        s := spec[b]
        return '<span class="btn subtle fx-b" id="' AxWindow._Esc(id) '_' b '" data-act="' b '"'
             . ' data-tip="' s[2] '" tabindex="0"><span class="ico">&#x' s[1] ';</span></span>'
    }
    __New(win, id, state, cfg := "") {
        this.W := win, this.Id := id, this.State := state
        this.Cfg := IsObject(cfg) ? cfg : {}
        AxRich.Use(win, "FileView")
        AxRich.Bind(win, id, this)
        state.Attach(this)
        win.On("click", id, (el, ev) => this._Click(ev))
        win.On("keyup", id "_q", (el, ev) => this._Query(el))
        this.Render()
    }
    Update(what) {
        switch what {
        case "path", "items", "mode", "attach": this.Render()
        }
    }
    Render() {
        st := this.State
        this._Dim("back", !st.CanBack)
        this._Dim("forward", !st.CanForward)
        this._Dim("up", !st.CanUp)
        return this
    }
    _Dim(name, off) {
        el := this.W.El(this.Id "_" name)
        if IsObject(el)
            AxWindow._SetClass(el, "disabled", off)
    }
    _Query(el) {
        v := ""
        try v := el.value
        this.State.SetFilter(v)
    }
    _Click(ev) {
        try el := ev.srcElement
        catch
            return
        n := 0
        act := ""
        while (IsObject(el) && n++ < 5) {
            act := AxWindow._Attr(el, "data-act")
            if (act != "")
                break
            el := AxWindow._ParentEl(el)
        }
        if (act = "")
            return
        if AxWindow._HasClass(el, "disabled")
            return
        st := this.State
        switch act {
        case "back":    return st.Back()
        case "forward": return st.Forward()
        case "up":      return st.Up()
        case "refresh": return st.Refresh()
        case "sort":    return this.SortMenu()
        case "group":   return this.GroupMenu()
        case "view":    return this.ViewMenu()
        case "options": return this.OptionsMenu()
        }
    }
    SortMenu() {
        st := this.State
        items := []
        for c in st.Cols
            items.Push({Label: c.Title, Checked: (st.SortKey = c.Key), Radio: true,
                        Click: this._SortFn(c.Key)})
        items.Push("-")
        items.Push({Label: "Ascending", Checked: (st.SortDir > 0), Radio: true, Click: (*) => st.SetSort(st.SortKey, 1)})
        items.Push({Label: "Descending", Checked: (st.SortDir < 0), Radio: true, Click: (*) => st.SetSort(st.SortKey, -1)})
        items.Push("-")
        items.Push({Label: "Folders first", Checked: st.FoldersFirst, Click: (*) => st.Toggle("foldersfirst")})
        this.W.ShowMenu(items)
        return this
    }
    _SortFn(key) => (*) => this.State.SetSort(key, this.State.SortKey = key ? "" : 1)
    GroupMenu() {
        st := this.State
        items := [{Label: "Don't group", Checked: (st.Group = ""), Radio: true, Click: (*) => st.SetGroup("")}]
        items.Push("-")
        for c in st.Cols {
            if (c.Key = "name")
                continue
            items.Push({Label: c.Title, Checked: (st.Group = c.Key), Radio: true, Click: this._GroupFn(c.Key)})
        }
        items.Push({Label: "What it is", Checked: (st.Group = "family"), Radio: true, Click: this._GroupFn("family")})
        this.W.ShowMenu(items)
        return this
    }
    _GroupFn(key) => (*) => this.State.SetGroup(key)
    ViewMenu() {
        st := this.State
        items := []
        for m in st.Modes
            items.Push({Label: AxFileState.Titleise(m), Checked: (st.Mode = m), Radio: true,
                        Click: this._ModeFn(m)})
        items.Push("-")
        for n in [32, 48, 64, 96, 128, 180]
            items.Push({Label: n " px icons", Checked: (st.Size = n), Radio: true, Click: this._SizeFn(n)})
        this.W.ShowMenu(items)
        return this
    }
    _ModeFn(m) => (*) => this.State.SetMode(m)
    _SizeFn(n) => (*) => this.State.IconSize(n)
    OptionsMenu() {
        st := this.State
        items := [{Label: "Hidden items", Checked: st.Hidden, Click: (*) => st.Toggle("hidden")},
                  {Label: "Tick boxes", Checked: st.Checks, Click: (*) => st.Toggle("checks")},
                  {Label: "Folder pane", Checked: st.Tree, Click: (*) => st.Toggle("tree")},
                  {Label: "Preview pane", Checked: st.Preview, Click: (*) => st.Toggle("preview")},
                  "-",
                  ["Select all", (*) => st.SelectAll()],
                  ["Invert selection", (*) => st.Invert()],
                  ["Clear selection", (*) => st.ClearSelection()], "-"]
        cols := []
        for c in st.Cols
            cols.Push({Label: c.Title, Checked: !c.Hidden, Click: this._ColFn(c.Key),
                       Disabled: !c.Hideable})
        items.Push({Label: "Columns", Items: cols})
        this.W.ShowMenu(items)
        return this
    }
    _ColFn(key) => (*) => this.State.ToggleColumn(key)

    static _Add(container, opts, spec) {
        o := container._Opt(opts, "fxt")
        st := AxFileView._State(spec, o)
        cfg := {}
        if o.KV.Has("buttons")
            cfg.Buttons := StrSplit(o.KV["buttons"], ",")
        else {
            want := []
            for b in AxFileTools.All {
                if (b = "search" && o.Flags.Has("nosearch"))
                    continue
                if ((b = "back" || b = "forward" || b = "up" || b = "refresh") && o.Flags.Has("nonav"))
                    continue
                if (b = "view" && o.Flags.Has("noviews"))
                    continue
                if (b = "options" && o.Flags.Has("nooptions"))
                    continue
                want.Push(b)
            }
            cfg.Buttons := want
        }
        if o.KV.Has("placeholder")
            cfg.SearchPlaceholder := o.KV["placeholder"]
        cfg.Style := (o.W != "" ? "width:" o.W "px;" : "") (o.Top != "" ? "margin-top:" o.Top "px;" : "")
                   . (o.KV.Has("style") ? o.KV["style"] : "")
        cfg.Class := ((o.W = "" || o.Flags.Has("fill")) ? "fill" : "")
                   . (o.KV.Has("class") ? " " o.KV["class"] : "")
        c := container._Reg(o, "FileTools", AxFileTools.Html(o.Id, cfg))
        container.G.OnReady((w) => AxFileTools(w, o.Id, st, cfg))
        return c
    }
}

; =============================================================================
;  AxFileExplorer — all six parts, arranged the way they usually are.
;
;      g.AddFileExplorer("Fill", {Source: AxFileLocal(), Preview: true})
;
;  It is a convenience and nothing more: it builds a state, lays the parts
;  out with two draggable grips, and hands the state back on .State so you
;  can go on driving it. Everything it does you could do yourself with the
;  six Add* methods and a Splitter, which is the point.
;
;  Options: NoTree, NoPreview, NoTools, NoPath, NoStatus, Tree=220,
;  Preview=300 for the two pane widths.
; =============================================================================
class AxFileExplorer {
    static Html(id, state, cfg := "") {
        o := (n, d := "") => (IsObject(cfg) && cfg.HasOwnProp(n)) ? cfg.%n% : d
        E := (x) => AxWindow._Esc(x)
        tree := o("Tree", true), preview := o("Preview", false)
        h := '<div class="fx' (o("Class", "") != "" ? " " E(o("Class", "")) : "") '" id="' E(id) '"'
           . ' data-role="fileexplorer"' (o("Style", "") != "" ? ' style="' E(o("Style", "")) '"' : "") '>'
        if (o("Tools", true) || o("Path", true)) {
            h .= '<div class="fx-top">'
            if o("Tools", true)
                h .= AxFileTools.Html(id "_tools", {Class: "", Buttons: o("Buttons", AxFileTools.All)})
            if o("Path", true)
                h .= AxFilePath.Html(id "_path", {Class: "fill"})
            h .= '</div>'
        }
        places := o("Places", false)
        h .= '<div class="fx-mid" id="' E(id) '_mid" style="height:' o("MidHeight", 420) 'px">'
        if (tree || places) {
            ; one side column: the places list on top, at its natural height,
            ; and the tree taking whatever is left under it
            h .= '<div class="fx-side" id="' E(id) '_side" style="width:'
              .  o("TreeWidth", 220) 'px">'
            if places
                h .= AxFilePlaces.Html(id "_places", {})
            if tree
                h .= AxFileTree.Html(id "_tree", {})
            h .= '</div><div class="fx-grip" data-grip="side"></div>'
        }
        h .= AxFileView.Html(id "_view", {Class: "fill"})
        if preview {
            h .= '<div class="fx-grip" data-grip="preview"></div>'
              .  AxFilePreview.Html(id "_preview", {Style: "width:" o("PreviewWidth", 300) "px"})
        }
        h .= '</div>'
        if o("Status", true)
            h .= AxFileStatus.Html(id "_status", {Class: "fill"})
        return h '</div>'
    }
    __New(win, id, state, cfg := "") {
        this.W := win, this.Id := id, this.State := state
        this.Cfg := IsObject(cfg) ? cfg : {}
        o := (n, d := "") => this.Cfg.HasOwnProp(n) ? this.Cfg.%n% : d
        AxRich.Use(win, "FileView")
        AxRich.Bind(win, id, this)
        this.Parts := Map()
        this.Broken := []
        ; Each part is built on its own. One that threw used to take every part
        ; after it with it, so a single mistake left the explorer as a row of
        ; empty boxes with nothing to say why.
        this._Build("tools",  o("Tools", true),    (w2, i) => AxFileTools(w2, i, state, {}))
        this._Build("path",   o("Path", true),     (w2, i) => AxFilePath(w2, i, state, {}))
        this._Build("places", o("Places", false),  (w2, i) => AxFilePlaces(w2, i, state, {}))
        this._Build("tree",   o("Tree", true),     (w2, i) => AxFileTree(w2, i, state, {}))
        this._Build("view",   true,                (w2, i) => AxFileView(w2, i, state, o("View", {})))
        this._Build("preview", o("Preview", false), (w2, i) => AxFilePreview(w2, i, state, {}))
        this._Build("status", o("Status", true),   (w2, i) => AxFileStatus(w2, i, state, {}))
        state.Tree := o("Tree", true)
        state.Preview := o("Preview", false)
        state.Attach(this)
        win.On("mousedown", id, (el, ev) => this._Down(ev))
        this._Panes()
    }
    ; ------------------------------------------------------------- events
    ; The explorer is a window over a state, and it is the state that raises
    ; things. Handing them on from here is what lets the designer wire them
    ; like any other control's -- explorer.OnPath(...) rather than reaching
    ; behind the control for the state by name.
    OnPath(fn)     => (this.State.OnPath(fn), this)
    OnItems(fn)    => (this.State.OnItems(fn), this)
    OnSelect(fn)   => (this.State.OnSelect(fn), this)
    OnActivate(fn) => (this.State.OnActivate(fn), this)
    OnCheck(fn)    => (this.State.OnCheck(fn), this)
    OnEdit(fn)     => (this.State.OnEdit(fn), this)
    OnDrop(fn)     => (this.State.OnDrop(fn), this)
    OnMenu(fn)     => (this.State.OnMenu(fn), this)
    OnError(fn)    => (this.State.OnError(fn), this)
    OnMode(fn)     => (this.State.OnMode(fn), this)
    ; and what anyone ever asks an explorer to do
    Go(path)       => (this.State.Go(path), this)
    Up()           => (this.State.Up(), this)
    Back()         => (this.State.Back(), this)
    Forward()      => (this.State.Forward(), this)
    Refresh()      => (this.State.Refresh(), this)
    SetMode(mode)  => (this.State.SetMode(mode), this)
    SetSort(key, dir := "") => (this.State.SetSort(key, dir), this)
    SetFilter(text) => (this.State.SetFilter(text), this)
    SelectAll()    => (this.State.SelectAll(), this)
    Pin(what)      => (this.State.Pin(what), this)
    Path           => this.State.Path
    Selected()     => this.State.Selected()

    ; Broken holds "<part>: <message>" for anything that would not build.
    _Build(name, wanted, make) {
        if !wanted
            return
        try
            this.Parts[name] := make(this.W, this.Id "_" name)
        catch as e {
            this.Broken.Push(name ": " e.Message)
            try this.W.Html(this.Id "_" name, '<div class="fv-empty">'
                . AxWindow._Esc(name " could not be built — " e.Message) '</div>')
        }
    }
    Part(name) => this.Parts.Has(name) ? this.Parts[name] : ""
    Update(what) {
        if (what = "panes")
            this._Panes()
    }
    ; The two side panes are hidden rather than destroyed, so turning one back
    ; on costs nothing and it comes back the width it was.
    _Panes() {
        st := this.State
        try {
            if (this.Parts.Has("tree") || this.Parts.Has("places"))
                this.W.El(this.Id "_side").style.display := (st.HasOwnProp("Tree") && !st.Tree) ? "none" : "block"
            if this.Parts.Has("preview")
                this.W.El(this.Id "_preview").style.display := (st.HasOwnProp("Preview") && !st.Preview) ? "none" : "block"
            grips := this.W.El(this.Id "_mid").getElementsByTagName("div")
            loop grips.length {
                el := grips.item(A_Index - 1)
                g := AxWindow._Attr(el, "data-grip")
                if (g = "side")
                    el.style.display := (st.HasOwnProp("Tree") && !st.Tree) ? "none" : "block"
                else if (g = "preview")
                    el.style.display := (st.HasOwnProp("Preview") && !st.Preview) ? "none" : "block"
            }
        }
        return this
    }
    ; The grips between the panes. The same poll-the-cursor drag the splitter
    ; uses, kept here so the explorer needs no other component.
    _Down(ev) {
        try el := ev.srcElement
        catch
            return
        g := ""
        n := 0
        while (IsObject(el) && n++ < 4) {
            g := AxWindow._Attr(el, "data-grip")
            if (g != "")
                break
            el := AxWindow._ParentEl(el)
        }
        if (g != "side" && g != "preview")
            return
        try {
            if !AxWindow._IsLeft(ev)
                return
        }
        pane := this.W.El(this.Id "_" g)
        if !IsObject(pane)
            return
        r := pane.getBoundingClientRect()
        from := 0
        try from := ev.clientX
        this._pane := {El: pane, Was: r.right - r.left, Start: from, Sign: (g = "side") ? 1 : -1}
        this.W.BodyClass("axsp-dragging", true)
        this.W.PointerCapture((x, y, *) => this._Move(x), (*) => this._Up())
        try ev.returnValue := false
    }
    _Move(x) {
        if !IsObject(this._pane)
            return
        p := this._pane
        v := Max(120, Min(760, Round(p.Was + (x - p.Start) * p.Sign)))
        try p.El.style.width := v "px"
    }
    _Up() {
        this._pane := ""
        this.W.BodyClass("axsp-dragging", false)
    }

    static _Add(container, opts, spec) {
        o := container._Opt(opts, "fx")
        ; the explorer may be handed a state, or the options to build one
        st := ""
        cfg := {}
        if (IsObject(spec) && spec is AxFileState)
            st := spec
        else if IsObject(spec) {
            for k, v in spec.OwnProps()
                cfg.%k% := v
            opt := {}
            for k, v in spec.OwnProps()
                opt.%k% := v
            if !opt.HasOwnProp("Name")
                opt.Name := o.Id
            st := AxFileState(opt)
        } else
            st := AxFileView._State(spec, o)
        cfg.Tools   := !o.Flags.Has("notools")
        cfg.Path    := !o.Flags.Has("nopath")
        cfg.Status  := !o.Flags.Has("nostatus")
        cfg.Tree    := !o.Flags.Has("notree") && (cfg.HasOwnProp("Tree") ? cfg.Tree : true)
        cfg.Preview := !o.Flags.Has("nopreview") && (cfg.HasOwnProp("Preview") ? cfg.Preview : false)
        if o.KV.Has("tree")
            cfg.TreeWidth := Integer(o.KV["tree"])
        cfg.Places := o.Flags.Has("places") || (cfg.HasOwnProp("Places") ? cfg.Places : false)
        if o.KV.Has("places")
            cfg.TreeWidth := Integer(o.KV["places"]), cfg.Places := true
        if o.KV.Has("preview")
            cfg.PreviewWidth := Integer(o.KV["preview"]), cfg.Preview := true
        if (o.H != "")
            cfg.MidHeight := Integer(o.H)
        cfg.Style := (o.W != "" ? "width:" o.W "px;" : "")
                   . (o.Top != "" ? "margin-top:" o.Top "px;" : "")
                   . (o.KV.Has("style") ? o.KV["style"] : "")
        cfg.Class := ((o.W = "" || o.Flags.Has("fill")) ? "fill" : "")
                   . (o.KV.Has("class") ? " " o.KV["class"] : "")
        c := container._Reg(o, "FileExplorer", AxFileExplorer.Html(o.Id, st, cfg))
        container.G.OnReady((w) => AxFileExplorer(w, o.Id, st, cfg))
        return c
    }
}
