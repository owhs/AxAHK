#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\AxJson.ahk
#Include %A_LineFile%\..\AxStudio.Catalog.ahk

; Part of AxStudio, not a program on its own. Running this file directly would
; only load a class and stop, so it hands over to the entry point instead.
if (A_LineFile = A_ScriptFullPath) {
    SplitPath(A_LineFile, , &axDir)
    axEntry := axDir "\AxStudio.ahk"
    if FileExist(axEntry)
        Run('"' A_AhkPath '" "' axEntry '"')
    else
        MsgBox("Run studio\AxStudio.ahk -- this file is only one part of it.", "AxStudio")
    ExitApp()
}

; =============================================================================
;  AxStudio.Model.ahk -- the design tree.
;
;  A project is a Root node whose children are Pages (or, with no pages, plain
;  controls). Every node carries three bags and nothing else:
;
;      L   layout   w h x y place gap top fill hidden class style tip
;      P   props    whatever the catalog entry declares for its type
;      Ev  events   [{name, code}]
;
;  That is the whole AST. It serialises to JSON as it stands -- no separate
;  save format to keep in step -- and Undo is a snapshot of the same JSON,
;  which is why an undo can never leave the tree half-changed.
; =============================================================================

class AxNode {
    __New(type, id := "") {
        this.Id := id
        this.Type := type
        this.Name := ""                  ; the vName the generated code uses
        this.Arg := ""                   ; the second argument to Add* (text, options, src, ...)
        this.L := Map()
        this.P := Map()
        this.Ev := []
        this.Kids := []
        this.Parent := ""
    }
    Box => (this.Type = "Root" || this.Type = "Page" || (AxCat.Has(this.Type) && AxCat.Get(this.Type).Box))
    Cat => AxCat.Has(this.Type) ? AxCat.Get(this.Type) : ""
    Label {
        get {
            if (this.Type = "Page")
                return this.P.Has("title") && this.P["title"] != "" ? this.P["title"] : this.Name
            if (this.Name != "")
                return this.Name
            return AxCat.Has(this.Type) ? AxCat.Get(this.Type).Label : this.Type
        }
    }
    Lay(k, def := "") => this.L.Has(k) ? this.L[k] : def
    Prop(k, def := "") => this.P.Has(k) ? this.P[k] : def

    ; --- serialisation ------------------------------------------------
    ToMap() {
        m := Map()
        m["id"] := this.Id, m["type"] := this.Type, m["name"] := this.Name, m["arg"] := this.Arg
        m["layout"] := AxNode._Copy(this.L)
        m["props"] := AxNode._Copy(this.P)
        ev := []
        for e in this.Ev
            ev.Push(Map("name", e["name"], "code", e["code"]))
        m["events"] := ev
        kids := []
        for k in this.Kids
            kids.Push(k.ToMap())
        m["kids"] := kids
        return m
    }
    static FromMap(m) {
        n := AxNode(AxJson.Get(m, "type", "Text"), AxJson.Get(m, "id", ""))
        n.Name := AxJson.Get(m, "name", "")
        n.Arg := AxJson.Get(m, "arg", "")
        for k, v in AxNode._AsMap(AxJson.Get(m, "layout", ""))
            n.L[k] := v
        for k, v in AxNode._AsMap(AxJson.Get(m, "props", ""))
            n.P[k] := v
        for e in AxNode._AsArr(AxJson.Get(m, "events", "")) {
            code := AxJson.Get(e, "code", "")
            n.Ev.Push(Map("name", AxJson.Get(e, "name", "Click"), "code", code))
        }
        for k in AxNode._AsArr(AxJson.Get(m, "kids", "")) {
            c := AxNode.FromMap(k)
            c.Parent := n
            n.Kids.Push(c)
        }
        return n
    }
    static _Copy(m) {
        out := Map()
        for k, v in m
            out[k] := v
        return out
    }
    static _AsMap(v) => (v is Map) ? v : Map()
    static _AsArr(v) => (v is Array) ? v : []
}

; =============================================================================
;  One window: everything AxWindow's constructor takes, the furniture authored
;  as text, and the tree of controls inside it. A project is a list of these,
;  because an app is a main window plus its settings window plus two dialogs,
;  and designing each of those as a separate project meant they could not open
;  one another.
;
;  Name is the identifier the generated builder function is named after, so it
;  has to be unique and legal. Kind decides how the window is opened:
;
;      main     built and shown at the top of the script
;      window   built on demand by ShowName(), shown non-modally, reused
;      dialog   built on demand, shown modally, returns its outputs
;      tool     like window, but comes up beside the main one
;
;  Inputs and Outputs are the data flow, one per line: an input becomes a
;  parameter of the builder, an output an expression read back when it closes.
; =============================================================================
class AxWin {
    __New(name := "Main") {
        this.Name := name
        this.Kind := "main"
        this.Inputs := ""                   ; one per line: name = default
        this.Outputs := ""                  ; one per line: name = expression
        this.Title := "My app"
        this.Width := 820
        this.Height := 560
        this.MinWidth := 0
        this.MinHeight := 0
        this.Theme := "dark"                ; dark | light | system
        this.Stylesheet := "win11"
        this.Accent := ""
        this.Tint := ""
        this.TintStrength := 0.18
        this.Nav := 1                       ; show the page rail
        this.Headings := ""                 ; "" = let AxGui decide, 1 / 0 to force
        this.EscapeCloses := 0
        this.Resizable := 1
        ; the rest of what AxWindow's constructor takes, at their own defaults
        this.MaximizeBox := 1
        this.MinimizeBox := 1
        this.RoundCorners := 1
        this.SnapLayouts := 1
        this.BorderColor := ""              ; "" default | none | #rrggbb
        this.SnapBorder := ""               ; ... when snapped or maximized
        this.AlwaysOnTop := 0
        this.NoActivate := 0                ; come up without taking focus
        this.ExitOnClose := 1
        ; before it closes, however it is closed (AxWindow.OnBeforeClose)
        this.AskClose := ""                 ; "" just close | dirty: ask to save unsaved changes | always
        this.SaveWith := ""                 ; the script's function that saves (returns false to stay)
        this.BeforeClose := ""              ; a function of the script's own: fn(win, why), true keeps it
        this.Opacity := ""                  ; 0-255, blank for opaque
        this.AppName := ""                  ; notifications carry this name
        this.FocusRing := ""                ; accent | contrast | none | #rrggbb
        this.AllowZoom := 0
        this.NativeContextMenu := 0
        this.Composited := 0
        this.TooltipDelay := ""             ; ms before a tooltip shows, blank for 450
        this.UseAccent := 1                 ; the accent colour's CSS on controls
        this.AppId := ""                    ; an AppUserModelID of its own, blank to derive one
        this.Frame := 1                     ; the title bar and resize edges; off is a bare page
        this.PageScroll := ""               ; "" as Windows 11 does it | always | never
        this.ImportLayout := ""             ; brought in from a Gui() script: fixed | rows (AxStudio.Layout.ahk)
        this.ImportResize := 0              ; ... and whether it resized, as the script had it
        this.BackColor := ""
        this.WinX := ""
        this.WinY := ""
        ; how it starts (see AxStart in AxStudio.Gen.ahk)
        this.StartState := ""               ; "" normal | max | min | hidden
        this.StartPos := ""                 ; "" Windows decides | mouse | remember | xy
        this.TabOrder := ""                 ; control names, one per line, in the order Tab visits
        this.DefaultBtn := ""               ; the button Enter presses
        this.CancelBtn := ""                ; and the one Escape presses
        this.Icon := "auto"
        ; The window's own furniture, authored as text (see AxStudio.Chrome.ahk).
        this.Menus := ""                    ; menu bar, indentation = submenus
        this.Ctx := ""                      ; right-click menus: "name | on", its items indented
        this.Status := ""                   ; status bar, one part per line
        this.TitleItems := ""               ; title bar items, one per line
        this.TitleShow := 1                 ; show the caption text at all
        this.TitleCenter := 0               ; centre it across the whole bar
        ; Escape hatches: an AHK expression here wins over the text above.
        this.MenuBar := ""
        this.StatusBar := ""
        ; A small stylesheet of its own, layered over the one it picked. Look
        ; is one token per line (see AxStudio.Theme.ahk), Css is free-form.
        this.Look := ""
        this.Css := ""
        ; Behaviour without code, one rule per line (see AxStudio.Flow.ahk).
        this.Flows := ""
        this.States := ""
        this.Binds := ""                    ; control <-> variable, one per line
        this.Hotkeys := ""                  ; keys | where | what | detail, one per line
        this.Init := ""                     ; runs after the controls, before Show()
        this.Script := ""                   ; extra functions appended to the file
        this.Root := AxNode("Root", "root")
    }

    ; The window fields that are saved. Root is stored separately, and the
    ; project owns the id counter, so neither is in here.
    static Fields := ["Name", "Kind", "Inputs", "Outputs",
                      "Title", "Width", "Height", "MinWidth", "MinHeight", "Theme", "Stylesheet",
                      "Accent", "Tint", "TintStrength", "Nav", "Headings", "EscapeCloses", "Resizable",
                      "Icon", "Menus", "Ctx", "Status", "TitleItems", "TitleShow", "TitleCenter",
                      "MaximizeBox", "MinimizeBox", "RoundCorners", "SnapLayouts",
                      "BorderColor", "SnapBorder", "AlwaysOnTop", "NoActivate", "ExitOnClose",
                      "Opacity", "AppName", "FocusRing", "AllowZoom", "NativeContextMenu",
                      "Composited", "BackColor", "WinX", "WinY", "TooltipDelay", "UseAccent", "AppId", "Frame", "PageScroll", "ImportLayout", "ImportResize",
                      "StartState", "StartPos", "TabOrder", "DefaultBtn", "CancelBtn",
                      "MenuBar", "StatusBar", "Look", "Css", "Flows", "States", "Binds",
                      "Hotkeys", "Init", "Script", "AskClose", "SaveWith", "BeforeClose"]
    ; What a project forwards to the window being edited: the saved fields and
    ; the tree. Built on the first ask rather than in a static initialiser --
    ; this is read on every property access, but it must not depend on the
    ; order the class's own statics happen to be set up in.
    static Own := ""
    static Owns(name) {
        if !(AxWin.Own is Map) {
            m := Map()
            m.CaseSense := "Off"
            for f in AxWin.Fields
                m[f] := true
            m["Root"] := true
            AxWin.Own := m
        }
        return AxWin.Own.Has(name)
    }

    ToMap() {
        m := Map()
        for f in AxWin.Fields
            m[StrLower(f)] := this.%f%
        m["root"] := this.Root.ToMap()
        return m
    }
    ; Reads the flat, one-window shape too: an axstudio/1 project put the
    ; window's fields at the top level, so the same code loads both.
    static FromMap(m) {
        w := AxWin()
        for f in AxWin.Fields {
            k := StrLower(f)
            if (m is Map) && m.Has(k)
                w.%f% := m[k]
        }
        r := AxJson.Get(m, "root", "")
        w.Root := (r is Map) ? AxNode.FromMap(r) : AxNode("Root", "root")
        w.Root.Id := "root"
        if (Trim(String(w.Name)) = "")
            w.Name := "Main"
        return w
    }
    ; The builder function this window generates, e.g. ShowSettings.
    Fn => (this.Kind = "main") ? "" : (this.Kind = "code" ? "Make" : "Show") AxProject.CleanName(this.Name)
    ; The variable its AxGui lands in.
    Var => (this.Kind = "main") ? "g" : "g" AxProject.CleanName(this.Name)
}

; =============================================================================
class AxProject {
    __New() {
        ; A project is one or more windows, and the one being edited. Every
        ; P.Title / P.Root in the studio reads through to Wins[Cur] (see
        ; __Get below), which is why growing from one window to several
        ; changed the model and almost nothing else.
        this.Wins := [AxWin("Main")]
        this.Cur := 1
        this.Uid := 0                       ; node ids are unique project-wide
        ; The data behind the design. Project-wide on purpose: a dialog that
        ; cannot write what the main window reads is not much of a dialog.
        this.Vars := ""
        ; --- the script, rather than any window in it ------------------
        ; Files it needs at run time. One per line:
        ;     name | path | how        how = install | resource | path
        this.Files := ""
        ; Extra #Include lines. One per line: a path, or <LibName>.
        this.Includes := ""
        ; Libraries installed by Aris that the script uses. One Author/Name per
        ; line; the files are in Lib\Aris beside the project (AxStudio.Pkg.ahk).
        this.Packages := ""
        this.Adaptors := ""                  ; methods of .NET and libraries, as your functions (AxStudio.DotNet.ahk)
        ; What it accepts on the command line. One per line:
        ;     name | default | what it is for
        this.Args := ""
        ; Named ways of starting. One per line:
        ;     name | what it does
        ; where what-it-does is the same grammar a rule uses, comma separated.
        this.Modes := ""
        ; The tray icon and its menu (see AxStudio.Assets.ahk).
        this.Tray := ""
        ; What Ahk2Exe should do, and how the script starts. One per line: name = value.
        this.Compile := ""
        ; What AutoHotkey is for, as lists (see AxStudio.Auto.ahk).
        this.Conds := ""                    ; name | kind | detail
        this.Strings := ""                  ; abbreviation | options | where | text
        this.Timers := ""                   ; name | every | starts | condition | steps
        ; ... and what it does on its own (see AxStudio.Auto2.ahk)
        this.Events := ""                   ; event | detail | steps
        this.Watchers := ""                 ; name | folder | files | when | subfolders | steps
        this.Macros := ""                   ; name | repeat | speed | hotkey, then its steps indented
        this.Settings := ""                 ; name | first value | kind | label | options
        this.Path := ""
        this.Dirty := false
        ; The .ahk this design was last written to. Not saved with the project
        ; -- an absolute path in a file people copy about is a path that goes
        ; stale. It is found again instead: the script beside the project that
        ; names it in its @axstudio line (see AxStudio.Merge.ahk).
        this.ExportedTo := ""
    }

    ; --- the window being edited --------------------------------------
    W {
        get {
            if (this.Cur < 1 || this.Cur > this.Wins.Length)
                this.Cur := 1
            return this.Wins[this.Cur]
        }
    }
    ; Anything the window owns is read and written straight through to it.
    ; Anything else behaves exactly as it would without these hooks: reading a
    ; property that does not exist raises, and assigning one makes it.
    __Get(name, params) {
        if AxWin.Owns(name)
            return this.W.%name%
        throw PropertyError('This value of type "AxProject" has no property named "' name '".', -1, name)
    }
    __Set(name, params, value) {
        if AxWin.Owns(name)
            return this.W.%name% := value
        ; Anything else belongs to the project itself. __Set is called for the
        ; *first* assignment to a property as well as later ones, so refusing
        ; here would refuse `this.Wins := ...` in the constructor -- this hook
        ; has to do what AutoHotkey would have done without it, which is to
        ; make the property.
        this.DefineProp(name, {Value: value})
    }

    ; --- the windows --------------------------------------------------
    Main() {
        for w in this.Wins
            if (w.Kind = "main")
                return w
        return this.Wins[1]
    }
    WinByName(name) {
        for w in this.Wins
            if (w.Name = name)
                return w
        return ""
    }
    WinIndex(win) {
        for i, w in this.Wins
            if AxProject.Same(w, win)
                return i
        return 0
    }
    ; Which window a node lives in. Nodes carry a parent chain up to a Root,
    ; and each window has its own, so this is a walk up rather than a search.
    WinOf(node) {
        n := node
        while IsObject(n) && IsObject(n.Parent)
            n := n.Parent
        for w in this.Wins
            if AxProject.Same(w.Root, n)
                return w
        return ""
    }
    ; Every node in the project, not just the window on screen. Naming and
    ; code generation both need this: the script is one file, so two windows
    ; cannot each have a control called `list1`.
    WalkAll(fn) {
        for w in this.Wins
            if this.Walk(w.Root, fn)
                return true
        return false
    }
    AddWin(kind := "window", name := "") {
        w := AxWin(name != "" ? name : this.UniqueWinName(kind = "dialog" ? "Dialog" : "Window"))
        w.Kind := kind
        w.Nav := 0
        if (kind = "dialog" || kind = "tool") {
            w.Width := 420, w.Height := 260
            w.MaximizeBox := 0, w.MinimizeBox := 0, w.Resizable := (kind = "tool")
            w.EscapeCloses := 1
            w.ExitOnClose := 0
        } else
            w.ExitOnClose := 0
        w.Title := w.Name
        this.Wins.Push(w)
        return w
    }
    RemoveWin(win) {
        i := this.WinIndex(win)
        if (!i || this.Wins.Length < 2 || win.Kind = "main")
            return false
        this.Wins.RemoveAt(i)
        if (this.Cur > this.Wins.Length)
            this.Cur := this.Wins.Length
        return true
    }
    ; A window name becomes part of a function name, so it has to be a legal
    ; identifier and unique. Loading a hand-edited file goes through here.
    FixWinNames() {
        seen := Map()
        seen.CaseSense := "Off"
        mains := 0
        for w in this.Wins {
            n := AxProject.CleanName(w.Name)
            if (n = "")
                n := "Window"
            if seen.Has(n) {
                i := 2
                while seen.Has(n i)
                    i++
                n := n i
            }
            seen[n] := true
            w.Name := n
            if (w.Kind = "main" && ++mains > 1)
                w.Kind := "window"
        }
        if (!mains && this.Wins.Length)
            this.Wins[1].Kind := "main"
    }
    UniqueWinName(base) {
        base := AxProject.CleanName(base)
        if (base = "")
            base := "Window"
        if !this.WinByName(base)
            return base
        i := 2
        while this.WinByName(base i)
            i++
        return base i
    }
    ; Which window opens which, read out of the handler code: the manager
    ; draws this, and it is also how an unreachable window is spotted.
    Links() {
        out := []
        for w in this.Wins
            this._Link(w, out)
        return out
    }
    ; One window's worth, in its own call: a closure written inside the loop
    ; above would not see the loop variable (AutoHotkey v2 does not capture
    ; one), so the window arrives here as a parameter instead.
    _Link(w, out) {
        calls := Map()
        AxProject._Calls(this, w.Init, calls)
        AxProject._Calls(this, w.Script, calls)
        this.Walk(w.Root, AxProject._CallFn(this, calls))
        ; A rule ("saveBtn Click -> open Settings") and a hotkey ("^!s | always |
        ; open | Settings") open a window with no code at all. They are links
        ; too -- counting only code made the easy way the one that did not.
        for line in StrSplit(StrReplace(String(w.Flows), "`r", ""), "`n")
            if RegExMatch(line, "i)->\s*open\s+([A-Za-z_]\w*)", &m)
                AxProject._LinkTo(this, m[1], calls)
        for line in StrSplit(StrReplace(String(w.Hotkeys), "`r", ""), "`n")
            if RegExMatch(line, "i)\|\s*open\s*\|\s*([A-Za-z_]\w*)", &m)
                AxProject._LinkTo(this, m[1], calls)
        for name in calls
            out.Push({From: w.Name, To: name})
    }
    static _LinkTo(p, name, calls) {
        t := p.WinByName(name)
        if IsObject(t)
            calls[t.Name] := true
    }
    static _CallFn(p, calls) => (n) => (AxProject._EvCalls(p, n, calls), false)
    static _EvCalls(p, n, calls) {
        for e in n.Ev
            AxProject._Calls(p, e["code"], calls)
    }
    static _Calls(p, code, calls) {
        for w in p.Wins {
            if (w.Fn = "")
                continue
            if RegExMatch(String(code), "i)\b" w.Fn "\s*\(")
                calls[w.Name] := true
        }
    }

    ; --- ids and names ------------------------------------------------
    NewId() => "n" (++this.Uid)
    ; A name that is unique in the project and is a legal AHK variable, so the
    ; generated file compiles whatever the user typed.
    NewName(prefix) {
        prefix := RegExReplace(prefix, "[^A-Za-z0-9_]")
        if (prefix = "")
            prefix := "ctl"
        i := 1
        while this.FindByName(prefix i)
            i++
        return prefix i
    }
    static CleanName(s) {
        s := RegExReplace(String(s), "[^A-Za-z0-9_]")
        if (s != "" && IsDigit(SubStr(s, 1, 1)))
            s := "c" s
        return s
    }
    ; Project-wide, not window-wide: every control becomes a global in one
    ; generated file, so a name used in another window is a name taken.
    FindByName(name, skip := "") {
        found := ""
        this.WalkAll((n) => (n.Name = name && !AxProject.Same(n, skip)) ? (found := n, true) : false)
        return found
    }

    ; --- walking ------------------------------------------------------
    ; fn(node) -> truthy stops the walk. Returns true when it was stopped.
    Walk(node, fn) {
        for k in node.Kids {
            if fn(k)
                return true
            if this.Walk(k, fn)
                return true
        }
        return false
    }
    Find(id) {
        if (id = "root")
            return this.Root
        found := ""
        this.Walk(this.Root, (n) => (n.Id = id) ? (found := n, true) : false)
        if IsObject(found)
            return found
        ; not on screen: the outline and the problems list name nodes in every
        ; window, so an id from either has to resolve
        this.WalkAll((n) => (n.Id = id) ? (found := n, true) : false)
        return found
    }
    ; The page a node lives on ("" for a node above every page).
    PageOf(node) {
        n := node
        while IsObject(n) {
            if (n.Type = "Page")
                return n
            n := n.Parent
        }
        return ""
    }
    Pages() {
        out := []
        for k in this.Root.Kids
            if (k.Type = "Page")
                out.Push(k)
        return out
    }
    IndexOf(node) {
        if !IsObject(node) || !IsObject(node.Parent)
            return 0
        for i, k in node.Parent.Kids
            if AxProject.Same(k, node)
                return i
        return 0
    }
    ; true when `anc` is `node` or one of its ancestors -- the check that stops
    ; a container being dropped into its own child.
    static Same(a, b) => (IsObject(a) && IsObject(b) && ObjPtr(a) = ObjPtr(b))
    static IsAncestor(anc, node) {
        n := node
        while IsObject(n) {
            if AxProject.Same(n, anc)
                return true
            n := n.Parent
        }
        return false
    }

    ; --- building -----------------------------------------------------
    NewNode(type) {
        e := AxCat.Has(type) ? AxCat.Get(type) : ""
        n := AxNode(type, this.NewId())
        n.Name := this.NewName(IsObject(e) ? e.Prefix : "ctl")
        if (IsObject(e) && IsObject(e.Arg))
            n.Arg := e.Arg.HasOwnProp("Def") ? e.Arg.Def : ""
        if IsObject(e)
            for p in e.Props
                if (p.Def != "")
                    n.P[p.K] := p.Def
        n.L["place"] := "flow"
        return n
    }
    NewPage(title := "") {
        n := AxNode("Page", this.NewId())
        n.Name := this.NewName("page")
        if (title = "")
            title := "Page " (this.Pages().Length + 1)
        n.P["title"] := title
        n.P["icon"] := "E80F"
        return n
    }
    Insert(parent, node, index := 0) {
        if !IsObject(parent)
            parent := this.Root
        node.Parent := parent
        if (index <= 0 || index > parent.Kids.Length + 1)
            parent.Kids.Push(node)
        else
            parent.Kids.InsertAt(index, node)
        return node
    }
    Remove(node) {
        i := this.IndexOf(node)
        if i
            node.Parent.Kids.RemoveAt(i)
        node.Parent := ""
        return node
    }
    ; Move `node` into `parent` at `index`, counting the index in the list as it
    ; is *after* the node has been taken out -- which is what a drop target
    ; computed from the on-screen order means.
    Move(node, parent, index) {
        if (!IsObject(node) || !IsObject(parent) || AxProject.IsAncestor(node, parent))
            return false
        this.Remove(node)
        this.Insert(parent, node, index)
        return true
    }
    Duplicate(node) {
        m := node.ToMap()
        copy := AxNode.FromMap(m)
        this.Renumber(copy)
        this.Insert(node.Parent, copy, this.IndexOf(node) + 1)
        return copy
    }
    ; Fresh ids and names for a subtree that has just been copied.
    Renumber(node) {
        node.Id := this.NewId()
        if (node.Name != "")
            node.Name := this.NewName(RegExReplace(node.Name, "\d+$"))
        for k in node.Kids
            this.Renumber(k)
    }

    ; --- serialisation ------------------------------------------------
    ; What belongs to the script rather than to a window. Listed once so a new
    ; one is saved, loaded and forwarded without three separate edits.
    static ScriptFields := ["Files", "Includes", "Packages", "Adaptors", "Args", "Modes", "Tray", "Compile", "Conds", "Strings", "Timers",
                            "Events", "Watchers", "Macros", "Settings"]
    ToMap() {
        m := Map()
        m["format"] := "axstudio/2"
        m["uid"] := this.Uid
        m["cur"] := this.Cur
        m["vars"] := this.Vars
        for f in AxProject.ScriptFields
            m[StrLower(f)] := this.%f%
        wins := []
        for w in this.Wins
            wins.Push(w.ToMap())
        m["windows"] := wins
        return m
    }
    ; Reads both shapes. An axstudio/1 file is one window written flat, so it
    ; loads as a project with a single window and nothing else to do -- which
    ; is what keeps every saved project and every template working.
    static FromMap(m) {
        p := AxProject()
        p.Uid := Integer(AxJson.Get(m, "uid", 0))
        p.Vars := AxJson.Get(m, "vars", "")
        for f in AxProject.ScriptFields
            p.%f% := AxJson.Get(m, StrLower(f), "")
        ws := AxJson.Get(m, "windows", "")
        if (ws is Array) && ws.Length {
            p.Wins := []
            for w in ws
                p.Wins.Push(AxWin.FromMap(w))
        } else
            p.Wins := [AxWin.FromMap(m)]
        p.Cur := Integer(AxJson.Get(m, "cur", 1))
        if (p.Cur < 1 || p.Cur > p.Wins.Length)
            p.Cur := 1
        p.FixWinNames()
        ; a project saved by hand may not have kept the counter ahead of the ids
        maxN := p.Uid
        highest := (n) => (RegExMatch(n.Id, "^n(\d+)$", &mm) && Integer(mm[1]) > maxN ? (maxN := Integer(mm[1]), false) : false)
        for w in p.Wins
            p.Walk(w.Root, highest)
        p.Uid := maxN
        return p
    }
    Json(indent := "  ") => AxJson.Stringify(this.ToMap(), indent)
    static FromJson(text) => AxProject.FromMap(AxJson.Parse(text))
    Clone() => AxProject.FromJson(this.Json(""))

}

; =============================================================================
;  Undo: whole-tree snapshots. A design tree is a few kilobytes of JSON, so a
;  snapshot costs less than the bookkeeping a command stack would need, and it
;  cannot leave the tree in a state no sequence of edits could reach.
class AxUndo {
    __New(limit := 120) {
        this.Limit := limit
        this.Back := []
        this.Fwd := []
    }
    Reset() {
        this.Back := [], this.Fwd := []
    }
    Push(project) {
        this.Back.Push(project.Json(""))
        if (this.Back.Length > this.Limit)
            this.Back.RemoveAt(1)
        this.Fwd := []
    }
    CanUndo => this.Back.Length > 0
    CanRedo => this.Fwd.Length > 0
    Undo(current) {
        if !this.Back.Length
            return ""
        this.Fwd.Push(current.Json(""))
        return AxProject.FromJson(this.Back.Pop())
    }
    Redo(current) {
        if !this.Fwd.Length
            return ""
        this.Back.Push(current.Json(""))
        return AxProject.FromJson(this.Fwd.Pop())
    }
}
