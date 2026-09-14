#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxJson.ahk
#Include %A_LineFile%\..\AxStudio.Lit.ahk
#Include %A_LineFile%\..\AxStudio.Catalog.ahk
#Include %A_LineFile%\..\AxStudio.Model.ahk
#Include %A_LineFile%\..\AxStudio.Host.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk
#Include %A_LineFile%\..\AxStudio.Pkg.ahk
#Include %A_LineFile%\..\AxStudio.Flow.ahk

; Part of AxStudio, not a program on its own.
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
;  AxStudio.Import.ahk -- a script that builds an AxGui window, as a design.
;
;  The parser (bin\AstHost.exe) says what every statement is; this walks the
;  top of the script in order and does what AxGui would do with it, keeping
;  its own idea of where the next control goes:
;
;      g := AxGui({...})          the window and its options
;      g.AddPage(id, title, ico)  a page, and where controls go from now
;      x := g.AddButton(o, t)     a control -- its option string read by
;        .OnClick((*) => ...)     AxGui.ParseOpts itself, its handlers kept
;      g.Use() / c.Use()          back to the page / into a container
;      tabs.UseTab(2)             into a tab
;      g.Show()                   the end of building; what follows is the
;                                 rest of the program
;
;  What it cannot turn into a design is not dropped and not guessed at. Code
;  that ran while the window was being built -- a loop making a row of
;  buttons, a table filled from a file -- becomes a Code block at the point
;  it ran, and the export writes it back there, so it still runs in the same
;  order with the same controls around it. Functions, classes, hotkeys, and
;  everything after Show() go to the window's script, word for word.
;
;      r := AxImport.FromFile(path)   ; {Project, Notes, N}
; =============================================================================
class AxImport {
    static FromFile(path) {
        src := FileRead(path, "UTF-8")
        im := AxImport(path, src, AxHost.Tree(path))
        return im.Run()
    }

    ; the generic Add(type, ...) spells types the way Gui.Add does
    static Alias := Map("ddl", "DDL", "dropdownlist", "DDL", "combobox", "DDL", "check", "CheckBox", "checkbox", "CheckBox",
        "edit", "Edit", "text", "Text", "button", "Button", "link", "Link", "switch", "Switch", "radio", "Radio",
        "password", "Password", "search", "Search", "autocomplete", "AutoComplete", "combo", "AutoComplete", "number", "Number",
        "updown", "Number", "slider", "Slider", "listbox", "ListBox", "progress", "Progress", "infobar", "InfoBar", "badge", "Badge",
        "chip", "Chip", "palette", "Palette", "rating", "Rating", "segmented", "Segmented", "hotkey", "Hotkey", "console", "Console",
        "picture", "Picture", "pic", "Picture", "activex", "ActiveX", "html", "Html", "separator", "Separator", "tile", "Tile",
        "image", "Image", "img", "Image", "imagebutton", "ImageButton", "imgbutton", "ImageButton", "svg", "Svg",
        "dropzone", "DropZone", "drop", "DropZone", "filelist", "FileList", "files", "FileList", "thumbs", "Thumbs",
        "groupbox", "GroupBox", "card", "Card", "row", "Row", "expander", "Expander", "grid", "Grid", "tab", "Tab", "tab3", "Tab",
        "listview", "ListView", "treeview", "TreeView", "dataview", "DataView")

    ; AxGui's constructor options, by the name the window keeps them under
    static WinKeys := Map("title", "Title", "width", "Width", "height", "Height", "minwidth", "MinWidth",
        "minheight", "MinHeight", "theme", "Theme", "stylesheet", "Stylesheet", "accent", "Accent", "tint", "Tint",
        "tintstrength", "TintStrength", "nav", "Nav", "headings", "Headings", "escapecloses", "EscapeCloses",
        "resizable", "Resizable", "icon", "Icon", "maximizebox", "MaximizeBox", "minimizebox", "MinimizeBox",
        "roundcorners", "RoundCorners", "snaplayouts", "SnapLayouts", "bordercolor", "BorderColor",
        "snapborder", "SnapBorder", "noactivate", "NoActivate", "exitonclose", "ExitOnClose", "allowzoom", "AllowZoom",
        "nativecontextmenu", "NativeContextMenu", "composited", "Composited", "tooltipdelay", "TooltipDelay",
        "useaccent", "UseAccent", "appid", "AppId", "frame", "Frame", "backcolor", "BackColor", "appname", "AppName",
        "focusring", "FocusRing", "x", "WinX", "y", "WinY", "alwaysontop", "AlwaysOnTop", "opacity", "Opacity")

    __New(path, src, t) {
        this.Path := path, this.Src := src, this.T := t
        SplitPath(path, , &dir, , &stem)
        this.Dir := dir, this.Stem := stem
        this.P := AxProject()
        this.W := this.P.Main()
        this.Root := this.W.Root
        this.Cur := this.Root               ; where the next control goes
        this.Tab := 0                       ; ... and which tab of it, when it is a Tab
        this.Page := ""
        this.Gv := ""                       ; the window's variable, as the script spells it
        this.Vars := Map()                  ; a variable of the script -> the node it holds
        this.Vars.CaseSense := false
        this.Names := Map()                 ; a control's name -> its node
        this.Names.CaseSense := false
        this.Notes := []
        this.Before := ""                   ; code above the window
        this.Script := ""                   ; code that goes to the window's script
        this.ScriptEnd := -1
        this.Shown := false
        this.Lead := -1                     ; where the comments above the next statement start
        this.Seen := Map()                  ; window options the script gave
        this.Seen.CaseSense := false
        this.Consts := Map()                ; name := "literal" above the window
        this.Consts.CaseSense := false
        this.N := {Controls: 0, Pages: 0, Events: 0, Code: 0, Script: 0}
    }

    Run() {
        t := this.T
        for i in t.Children(0)
            this.Top(i)
        if (this.Gv = "")
            throw Error("This script does not make an AxGui window (a line like  g := AxGui({...})  at the top level),"
                . " so there is no design in it to bring in.")
        if (Trim(this.Before) != "") {
            n := this.CodeNode(this.Before)
            this.P.Insert(this.Root, n, 1)
        }
        this.W.Script := Trim(this.Script, "`r`n")
        if !this.Seen.Has("title")
            this.W.Title := this.Stem
        if !this.Seen.Has("width")
            this.W.Width := 800
        if !this.Seen.Has("height")
            this.W.Height := 540
        if (this.Seen.Has("tint") && !this.Seen.Has("tintstrength"))
            this.W.TintStrength := 0.12
        for p in t.Problems
            this.Notes.Push("Line " AxJson.Get(AxJson.Get(p, "start", Map()), "line", "?") ": the parser says "
                . AxJson.Get(p, "message", "?"))
        this.Rules()
        this.P.Dirty := true
        return {Project: this.P, Notes: this.Notes, N: this.N}
    }

    ; ------------------------------------------------------ code into rules
    ; A handler that is only something the rules can say -- run a program,
    ; send keys, enable a control, call a function -- becomes rules, which
    ; are the design's no-code layer (Logic > Rules), and stops being code.
    Rules() {
        if !this.N.HasOwnProp("Rules")
            this.N.Rules := 0
        for win in this.P.Wins {
            names := Map()
            names.CaseSense := false
            for n in AxImport.Nodes(win.Root)
                if (n.Name != "")
                    names[n.Name] := true
            for n in AxImport.Nodes(win.Root) {
                keep := []
                for e in n.Ev {
                    lines := AxImport.AsRules(e["code"], names, this.Fns())
                    if (IsObject(lines) && n.Name != "") {
                        for l in lines
                            win.Flows .= n.Name " " e["name"] " -> " l "`n"
                        this.N.Rules++, this.N.Events--
                    } else
                        keep.Push(e)
                }
                n.Ev := keep
            }
        }
    }
    ; the functions the script defines, by name
    Fns() {
        if this.HasOwnProp("_fns")
            return this._fns
        m := Map()
        m.CaseSense := false
        for i in this.T.Children(0)
            if (this.T.Type(i) = "Method")
                m[this.T.Value(i)] := true
        return this._fns := m
    }
    static Nodes(root) {
        out := []
        for k in root.Kids {
            out.Push(k)
            for x in AxImport.Nodes(k)
                out.Push(x)
        }
        return out
    }
    ; Each line of the code as a rule, or "" when any line is not one.
    static AsRules(code, names, fns) {
        out := []
        q := '"(?:[^"``]|``.)*"'
        for line in StrSplit(Trim(StrReplace(code, "`r", ""), "`n"), "`n") {
            line := Trim(line)
            if (line = "")
                continue
            if RegExMatch(line, "i)^Run\(\s*(" q ")\s*\)$", &m)
                out.Push("run " m[1])
            else if RegExMatch(line, "i)^Send\(\s*(" q ")\s*\)$", &m)
                out.Push("send " m[1])
            else if RegExMatch(line, "i)^SendText\(\s*(" q ")\s*\)$", &m)
                out.Push("type " m[1])
            else if RegExMatch(line, "i)^SoundBeep\(\s*\)$")
                out.Push("beep")
            else if RegExMatch(line, "i)^Sleep\(\s*(\d+)\s*\)$", &m)
                out.Push("wait " m[1])
            else if RegExMatch(line, "i)^g\.Toast\(\s*(" q ")\s*\)$", &m)
                out.Push("toast " m[1])
            else if RegExMatch(line, "i)^g\.ShowPage\(\s*(" q ")\s*\)$", &m)
                out.Push("page " SubStr(m[1], 2, -1))
            else if RegExMatch(line, "i)^g\.Close\(\s*\)$")
                out.Push("close")
            else if RegExMatch(line, "i)^(\w+)\.(Enabled|Visible)\s*:=\s*(true|false|1|0)$", &m) && names.Has(m[1])
                out.Push(((m[2] = "Enabled") ? (m[3] = "true" || m[3] = "1" ? "enable " : "disable ")
                                             : (m[3] = "true" || m[3] = "1" ? "show " : "hide ")) m[1])
            else if RegExMatch(line, "i)^(\w+)\(\s*\)$", &m) && fns.Has(m[1])
                out.Push("call " m[1])
            else
                return ""
        }
        return out.Length ? out : ""
    }

    ; ---------------------------------------------------------------- the walk
    Top(i) {
        t := this.T, ty := t.Type(i)
        if (ty = "Comment") {
            if (this.Lead < 0)
                this.Lead := t.Start(i)
            return
        }
        ; The parser hands a comment INSIDE a statement (the end of one line
        ; of a long array) over before the statement itself. Its text is in
        ; the statement's own, where it was, so the statement starts where it
        ; starts -- taken from the comment on, it lost its head.
        from := (this.Lead >= 0) ? Min(this.Lead, t.Start(i)) : t.Start(i)
        this.Lead := -1
        text := AxImport.NoCompilerLines(SubStr(this.Src, from + 1, t.End(i) - from))
        switch ty {
        case "Directive":
            return this.Directive(i, text, from)
        case "Method", "Class", "Hotkey", "Hotstring", "Remap", "Label":
            return this.ToScript(text, from, t.End(i))
        case "Error", "Warning":
            this.Note(i, "The parser could not read this: " t.Value(i) ". It is kept as it was.")
        }
        if (this.Gv = "") {
            if this.Window(i)
                return
            this.Remember(i)
            this.Before .= text "`n"
            return
        }
        if (!this.Shown && this.Ui(i))
            return
        ; Everything else runs where it stood: before Show() it is part of
        ; building the window, after it the rest of the program.
        if this.Shown
            this.ToScript(text, from, t.End(i))
        else
            this.CodeHere(text)
    }

    Directive(i, text, from) {
        t := this.T
        line := Trim(t.Value(i))
        RegExMatch(line, "^(#\w+)\s*(.*)$", &m)
        name := IsObject(m) ? StrLower(m[1]) : ""
        args := IsObject(m) ? Trim(RegExReplace(m[2], "\s+;.*$")) : ""
        if (name = "#requires")
            return
        if (name = "#singleinstance") {
            if (args != "" && args != "Force")
                AxAsset.SetCompile(this.P, "instance", args)
            return
        }
        if (name = "#include" || name = "#includeagain") {
            ; a library Aris installed is one of the project's libraries
            if RegExMatch(args, "i)^<Aris[\\/](.+?)>$", &am) {
                AxPkg.Use(this.P, StrReplace(am[1], "\", "/"))
                return
            }
            p := this.IncludePath(args)
            if (p != "" && AxImport.InLib(p))
                return                          ; the library: the export names its own
            if (p = "") {
                this.Note(i, "Kept an #Include it could not follow: " args)
                this.P.Includes .= args "`n"
            } else
                this.P.Includes .= p "`n"
            return
        }
        ; #HotIf and the rest belong with the hotkeys and code they govern
        this.ToScript(text, from, t.End(i))
    }
    IncludePath(args) {
        a := Trim(RegExReplace(args, "i)^\*i\s+"))
        a := Trim(a, "`"' ")
        if RegExMatch(a, "^<.*>$")
            return ""
        a := StrReplace(a, "%A_ScriptDir%", this.Dir)
        a := StrReplace(a, "%A_LineFile%\..", this.Dir)
        a := StrReplace(a, "%A_LineFile%", this.Path)
        if !RegExMatch(a, "^[A-Za-z]:\\|^\\\\")
            a := this.Dir "\" a
        full := ""
        loop files a, "FD"
            full := A_LoopFileFullPath
        return full
    }
    static InLib(p) {
        lib := AxSys.LibDir
        return SubStr(StrLower(p), 1, StrLen(lib)) = StrLower(lib)
    }

    ; Css := "..." above the window, for an option that names it: the value
    ; it has when AxGui({Css: Css}) reads it.
    Remember(i) {
        t := this.T
        if !(t.Type(i) = "BinaryExpr" && t.Value(i) = ":=")
            return
        l := t.FirstChild(i)
        if (t.Type(l) != "Identifier")
            return
        v := this.Lit(t.Next(l), &ok)
        if ok
            this.Consts[t.Value(l)] := v
        else if this.Consts.Has(t.Value(l))
            this.Consts.Delete(t.Value(l))
    }

    ; g := AxGui({...})
    Window(i) {
        t := this.T
        if !(t.Type(i) = "BinaryExpr" && t.Value(i) = ":=")
            return false
        l := t.FirstChild(i), r := t.Next(l)
        if (t.Type(l) != "Identifier" || t.Type(r) != "Call")
            return false
        callee := t.FirstChild(r)
        if !(t.Type(callee) = "Identifier" && t.Value(callee) = "AxGui")
            return false
        this.Gv := t.Value(l)
        args := this.Kids(t.Next(callee))
        late := []
        if (args.Length >= 1 && t.Type(args[1]) = "Object") {
            for kv in this.Kids(args[1]) {
                kn := t.FirstChild(kv), vn := t.Next(kn)
                key := StrLower(t.Type(kn) = "String" ? this.Lit(kn, &ok0) : t.Value(kn))
                v := this.Lit(vn, &ok)
                if (!ok && t.Type(vn) = "Identifier" && this.Consts.Has(t.Value(vn)))
                    v := this.Consts[t.Value(vn)], ok := true
                if (key = "css") {
                    if ok
                        this.W.Css .= (this.W.Css = "" ? "" : "`n") v
                    else
                        late.Push(".SetExtraCss(" AxLit.S("axCss") ", " this.Text(vn) ")")
                    this.Seen[key] := true
                    continue
                }
                if !AxImport.WinKeys.Has(key) {
                    this.Note(kv, "Left out a window option the studio has no place for: " this.Text(kv))
                    continue
                }
                if !ok {
                    ; set on the window before it is shown, which is when AxGui reads these
                    set := Map("width", "Width", "height", "Height", "x", "X", "y", "Y", "theme", "Theme", "accent", "Accent")
                    if set.Has(key)
                        late.Push("." set[key] " := " this.Text(vn))
                    else if (key = "title")
                        late.Push(".SetTitle(" this.Text(vn) ")")
                    else
                        this.Note(kv, "Left out a window option that is worked out as the script runs: " this.Text(kv))
                    continue
                }
                f := AxImport.WinKeys[key]
                this.W.%f% := v
                this.Seen[key] := true
                if (f = "WinX" || f = "WinY")
                    this.W.StartPos := "xy"
            }
        } else if (args.Length >= 1)
            this.Note(i, "The window's options are worked out as the script runs, so it starts with the studio's own.")
        if (this.Gv != "g")
            this.CodeHere(this.Gv " := g")      ; the name the rest of the script calls it by
        for x in late
            this.CodeHere("g" x)
        return true
    }

    ; One statement that builds the window. False when it is anything the
    ; design cannot hold -- it is then kept as code, where it stood.
    Ui(i) {
        t := this.T
        target := "", e := i
        if (t.Type(i) = "BinaryExpr" && t.Value(i) = ":=") {
            l := t.FirstChild(i)
            if (t.Type(l) != "Identifier")
                return false
            target := t.Value(l), e := t.Next(l)
        }
        c := this.Chain(e)
        if !IsObject(c)
            return false
        calls := c.Calls
        if (c.Root = this.Gv) {
            first := calls[1]
            rest := AxImport.Tail(calls, 2)
            switch first.Name, false {
            case "AddPage":
                return (rest.Length = 0) && this.AddPage(first.Args, target)
            case "Use":
                if (rest.Length || target != "")
                    return false
                a := this.Kids(first.Args)
                if (a.Length = 0)
                    return (this.Cur := (IsObject(this.Page) ? this.Page : this.Root), this.Tab := 0, true)
                if (a.Length = 1 && t.Type(a[1]) = "Identifier" && this.Vars.Has(t.Value(a[1])))
                    return (this.Cur := this.Vars[t.Value(a[1])], this.Tab := 0, true)
                return false
            case "UseTab":
                if (rest.Length || target != "")
                    return false
                a := this.Kids(first.Args)
                k := (a.Length = 1) ? this.Lit(a[1], &ok) : 0
                if (a.Length = 1 && !ok)
                    return false
                return this.UseTab(this.Cur, k)
            case "AddMenuBar", "AddStatusBar":
                a := this.Kids(first.Args)
                f := (StrLower(first.Name) = "addmenubar") ? "MenuBar" : "StatusBar"
                if (a.Length != 1 || rest.Length || target != "" || this.W.%f% != "")
                    return false
                this.W.%f% := this.Text(a[1])
                return true
            case "SetExtraCss":
                a := this.Kids(first.Args)
                if (a.Length != 2 || rest.Length || target != "")
                    return false
                css := this.Lit(a[2], &ok)
                if !ok
                    return false
                this.W.Css .= (this.W.Css = "" ? "" : "`n") css
                return true
            case "Show":
                this.ShowOpts(first.Args)
                this.Shown := true
                return rest.Length = 0
            case "On":
                ; g.On("click", "id", fn) on a control of the design: its event
                return (rest.Length = 0 && target = "") && this.DomEvent(first.Args)
            case "Ctl":
                a := this.Kids(first.Args)
                name := (a.Length = 1) ? this.Lit(a[1], &ok) : ""
                if (name = "" || !this.Names.Has(name) || target != "" || rest.Length = 0)
                    return false
                return this.Events(this.Names[name], rest)
            }
            type := this.AddType(first, &args)
            if (type = "")
                return false
            return this.AddCtl(type, args, target, rest, "")
        }
        if !this.Vars.Has(c.Root)
            return false
        node := this.Vars[c.Root]
        first := calls[1]
        rest := AxImport.Tail(calls, 2)
        if (StrLower(first.Name) = "use" && !rest.Length && target = "" && !this.Kids(first.Args).Length)
            return (this.Cur := node, this.Tab := 0, true)
        if (StrLower(first.Name) = "usetab" && !rest.Length && target = "") {
            a := this.Kids(first.Args)
            k := (a.Length = 1) ? this.Lit(a[1], &ok) : 0
            return (a.Length != 1 || ok) && this.UseTab(node, k)
        }
        if node.Box {
            type := this.AddType(first, &args)
            if (type != "")
                return this.AddCtl(type, args, target, rest, node)
        }
        return (target = "") && this.Events(node, calls)
    }

    ; a.B(x).C(y) as the object at the bottom and the calls on it, first call
    ; first. g.Ctl("name") and g["name"] stand for that control.
    Chain(e) {
        t := this.T
        calls := []
        loop {
            if (t.Type(e) != "Call")
                break
            callee := t.FirstChild(e)
            if (t.Type(callee) != "Member")
                return ""
            calls.InsertAt(1, {Name: t.Value(callee), Args: t.Next(callee), Node: e})
            e := t.FirstChild(callee)
        }
        if !calls.Length
            return ""
        if (t.Type(e) = "Identifier")
            return {Root: t.Value(e), Calls: calls}
        if (t.Type(e) = "Index") {
            k := this.Kids(e)
            if (k.Length = 2 && t.Type(k[1]) = "Identifier" && t.Value(k[1]) = this.Gv) {
                name := this.Lit(k[2], &ok)
                if (ok && this.Names.Has(name)) {
                    v := "_ctl_" name
                    this.Vars[v] := this.Names[name]
                    return {Root: v, Calls: calls}
                }
            }
        }
        return ""
    }

    AddType(call, &args) {
        name := call.Name
        args := this.Kids(call.Args)
        if (StrLower(name) = "add") {
            if (args.Length < 1)
                return ""
            k := StrLower(this.Lit(args[1], &ok))
            if (!ok || !AxImport.Alias.Has(k))
                return ""
            args.RemoveAt(1)
            name := "Add" AxImport.Alias[k]
        }
        if (SubStr(name, 1, 3) != "Add")
            return ""
        type := SubStr(name, 4)
        for tt in AxCat.Order                   ; the catalog's spelling
            if (tt = type)
                return tt
        return ""
    }

    UseTab(node, k) {
        ; tabs.UseTab(n) goes into its tab n; UseTab() or 0 goes back to the page
        if (node.Type = "Tab" && IsInteger(k) && k >= 1) {
            this.Cur := node, this.Tab := Integer(k)
            return true
        }
        this.Cur := IsObject(this.Page) ? this.Page : this.Root, this.Tab := 0
        return true
    }

    AddPage(argsNode, target) {
        a := this.Kids(argsNode)
        vals := []
        for x in a {
            v := this.Lit(x, &ok)
            if !ok
                return false
            vals.Push(v)
        }
        if (vals.Length < 1 || vals.Length > 3)
            return false
        n := AxNode("Page", this.P.NewId())
        n.Name := vals[1]
        n.P["title"] := (vals.Length >= 2) ? vals[2] : ""
        n.P["icon"] := (vals.Length >= 3) ? vals[3] : ""
        this.P.Insert(this.Root, n)
        this.Page := n, this.Cur := n, this.Tab := 0
        if (target != "")
            this.Vars[target] := n
        this.N.Pages++
        return true
    }

    ; ----------------------------------------------------------- one control
    AddCtl(type, args, target, rest, into) {
        t := this.T
        e := AxCat.Get(type)
        opts := ""
        if (args.Length >= 1 && t.Type(args[1]) != "Omitted") {
            opts := this.Lit(args[1], &ok)
            if !ok
                return false
        }
        n := AxNode(type, this.P.NewId())
        n.L["place"] := "flow"
        this.Opts(n, e, opts)
        if !this.Arg(n, e, type, args)
            return false

        ; its name: the variable it was put in, unless the id in its options
        ; is what the rest of the script asks for it by
        vn := n.Name, alias := ""
        if (target != "") {
            if (vn = "" || vn = target)
                n.Name := target
            else if this.Mentioned(vn)
                alias := target
            else
                n.Name := target
        }

        parent := IsObject(into) ? into : this.Cur
        if (!IsObject(into) && parent.Type = "Tab" && this.Tab >= 1)
            n.L["tab"] := this.Tab
        this.P.Insert(parent, n)
        if n.Box                               ; containers take what comes next
            this.Cur := n, this.Tab := 0
        if (target != "")
            this.Vars[target] := n
        if (n.Name != "")
            this.Names[n.Name] := n
        this.N.Controls++
        if (alias != "")
            this.CodeHere(alias " := " AxProject.CleanName(n.Name))
        if rest.Length && !this.Events(n, rest)
            return this.Fail(n, rest)
        return true
    }
    ; The chained calls this could not read as handlers still happen, right
    ; after the control is made, exactly as written.
    Fail(n, rest) {
        if (n.Name = "")
            n.Name := this.P.NewName(AxCat.Get(n.Type).Prefix)
        s := this.Src
        from := this.T.End(this.T.FirstChild(this.T.FirstChild(rest[1].Node)))   ; where the control's own call ends
        tail := SubStr(s, from + 1, this.T.End(rest[-1].Node) - from)
        this.CodeHere(AxProject.CleanName(n.Name) tail)
        return true
    }

    ; The option string, read by AxGui's own reader, back into the fields
    ; the studio writes it from. Anything else stays, word for word.
    Opts(n, e, s) {
        o := AxGui.ParseOpts(s)
        extra := ""
        n.Name := o.Id
        if (o.X != "" || o.Y != "") {
            n.L["place"] := "abs"
            n.L["x"] := (o.X = "") ? 0 : o.X + 0
            n.L["y"] := (o.Y = "") ? 0 : o.Y + 0
        } else if o.Inline {
            n.L["place"] := "same"
            if (o.Gap != 8)
                n.L["gap"] := o.Gap
        }
        if (o.W != "")
            n.L["w"] := o.W + 0
        if (o.H != "")
            n.L["h"] := o.H + 0
        if (o.Top != "")
            n.L["top"] := o.Top
        if o.Choose
            extra .= " Choose" o.Choose
        for k, on in o.Flags {
            if (on && (k = "fill" || k = "grow")) {
                n.L[k] := 1
                continue
            }
            if (on && k = "hidden") {
                n.L["hidden"] := 1
                continue
            }
            got := false
            if on {
                for pr in e.Props {
                    if (pr.Emit = "flag" && StrLower(pr.W) = k) {
                        n.P[pr.K] := 1, got := true
                        break
                    }
                    if (pr.Emit = "flagset") {
                        for opt in StrSplit(pr.Opts, "|")
                            if (opt != "" && StrLower(opt) = k)
                                n.P[pr.K] := opt, got := true
                        if got
                            break
                    }
                }
            }
            if !got
                extra .= " " k
        }
        for k, v in o.KV {
            if (k = "class" || k = "style" || k = "tip") {
                n.L[k] := v
                continue
            }
            got := false
            for pr in e.Props
                if (pr.Emit = "kv" && StrLower(pr.W) = k) {
                    n.P[pr.K] := v, got := true
                    break
                }
            if !got
                extra .= " " k "=" AxLit.Q(v)
        }
        if (Trim(extra) != "")
            n.L["opts"] := Trim(extra)
    }

    ; The text, list, value or expression after the options.
    Arg(n, e, type, args) {
        t := this.T
        a := (args.Length >= 2 && t.Type(args[2]) != "Omitted") ? args[2] : -1
        ; AddRow / AddExpander take a description third
        if (args.Length >= 3) {
            if !((type = "Row" || type = "Expander") && args.Length = 3)
                return false
            d := this.Lit(args[3], &ok)
            if !ok
                return false
            n.P["desc"] := d
        }
        if (a < 0)
            return true
        if !IsObject(e.Arg)
            return false                        ; a second argument to a control that takes none
        if (e.Arg.HasOwnProp("Raw") && e.Arg.Raw) {
            n.Arg := this.Text(a)
            return true
        }
        if (e.Arg.Kind = "options") {
            if (t.Type(a) = "Array") {
                lines := ""
                for it in this.Kids(a) {
                    if (t.Type(it) = "Array") {
                        pair := this.Kids(it)
                        if (pair.Length != 2)
                            return false
                        v := this.Lit(pair[1], &ok1), l := this.Lit(pair[2], &ok2)
                        if !(ok1 && ok2)
                            return false
                        lines .= v ":" l "`n"
                    } else {
                        v := this.Lit(it, &ok)
                        if !ok
                            return false
                        lines .= v "`n"
                    }
                }
                n.Arg := RTrim(lines, "`n")
                return true
            }
            v := this.Lit(a, &ok)
            if !ok
                return false
            sep := (type = "Palette") ? "," : "|"
            n.Arg := StrReplace(v, sep, "`n")
            return true
        }
        ; AddListView(o, ["Name", "Size"]): its column titles, the first line of its text
        if (type = "ListView" && t.Type(a) = "Array") {
            line := ""
            for it in this.Kids(a) {
                v := this.Lit(it, &ok)
                if !ok
                    return false
                line .= (line = "" ? "" : " | ") StrReplace(v, "|", "/")
            }
            n.Arg := line
            return true
        }
        v := this.Lit(a, &ok)
        if !ok
            return false
        n.Arg := String(v)
        return true
    }

    ; --------------------------------------------------------------- handlers
    ; .OnEvent("Change", fn) and .OnClick(fn): handlers the design can hold.
    ; All or nothing -- a chain with anything else in it stays code.
    Events(n, calls) {
        t := this.T
        e := AxCat.Get(n.Type)
        got := []
        for c in calls {
            a := this.Kids(c.Args)
            if (StrLower(c.Name) = "onevent") {
                if (a.Length != 2)
                    return false
                ev := this.Lit(a[1], &ok)
                if !ok
                    return false
                fn := a[2]
            } else if (SubStr(c.Name, 1, 2) = "On" && a.Length = 1) {
                ev := SubStr(c.Name, 3), fn := a[1]
            } else
                return false
            canon := ""
            for x in e.Events
                if (StrLower(x) = StrLower(ev))
                    canon := x
            if (canon = "")
                return false
            for h in n.Ev
                if (h["name"] = canon)
                    return false
            for g in got
                if (g.Name = canon)
                    return false
            got.Push({Name: canon, Fn: fn})
        }
        if (n.Name = "")
            n.Name := this.P.NewName(e.Prefix)
        for g in got {
            n.Ev.Push(Map("name", g.Name, "code", this.Handler(g.Fn, g.Name)))
            this.N.Events++
        }
        return true
    }

    static Dom := Map("click", "Click", "dblclick", "DoubleClick", "contextmenu", "ContextMenu", "keydown", "KeyDown",
        "keyup", "KeyUp", "mousedown", "MouseDown", "mouseup", "MouseUp", "mouseover", "MouseOver",
        "mouseout", "MouseOut", "focusin", "Focus", "focusout", "Blur")
    ; g.On(event, id, fn) calls fn(el, ev); the control's own event calls
    ; (ctl, ev, el) -- so the handler passes its el and ev on in that order
    DomEvent(argsNode) {
        a := this.Kids(argsNode)
        if (a.Length != 3)
            return false
        ev := StrLower(this.Lit(a[1], &ok1)), id := this.Lit(a[2], &ok2)
        if !(ok1 && ok2 && AxImport.Dom.Has(ev) && this.Names.Has(id))
            return false
        n := this.Names[id]
        canon := AxImport.Dom[ev], has := false
        for x in AxCat.Get(n.Type).Events
            if (x = canon)
                has := true
        for h in n.Ev
            if (h["name"] = canon)
                has := false
        if !has
            return false
        n.Ev.Push(Map("name", canon, "code", this.Pass(a[3], ["el", "ev"])))
        this.N.Events++
        return true
    }
    ; A function value called with what the handler has, under these names.
    Pass(fn, sig) {
        t := this.T
        pass := AxImport.Join(sig)
        if (t.Type(fn) = "Identifier")
            return t.Value(fn) "(" pass ")"
        if (t.Type(fn) = "FatArrow") {
            code := this.Arrow(fn, sig)
            if (code != "")
                return code
        }
        return "axFn := " AxImport.Tidy(this.Text(fn)) "`naxFn(" pass ")"
    }
    ; What the handler does, as the body of the studio's handler function --
    ; which is called with the same arguments AxGui would have called the
    ; original with, so passing them on is the same call.
    Handler(fn, ev) {
        t := this.T
        sig := []
        for s in StrSplit(AxCat.Sig(ev), ",")
            sig.Push(Trim(s))
        pass := AxImport.Join(sig)
        ty := t.Type(fn)
        if (ty = "Identifier")
            return t.Value(fn) "(" pass ")"
        if (ty = "FatArrow") {
            code := this.Arrow(fn, sig)
            if (code != "")
                return code
        }
        return "axFn := " AxImport.Tidy(this.Text(fn)) "`naxFn(" pass ")"
    }
    ; (c, v, *) => SetReveal(v): the body, with the arrow's own names for the
    ; arguments set from the handler's. "" when that would not be the same.
    Arrow(fn, sig) {
        t := this.T
        params := t.FirstChild(fn), body := t.Next(params)
        bodyText := this.Text(body)
        lines := ""
        k := 0
        for p in this.Kids(params) {
            k++
            pn := t.Value(p)
            if (pn = "*")
                continue
            if t.Has(p, "variadic") || t.Has(p, "byref")
                return ""
            for j, s in sig
                if (j != k && s = pn)
                    return ""                   ; (el, ev) against (ctl, ev, el): renaming would clobber
            if (k > sig.Length) {
                d := t.FirstChild(p)
                if (d >= 0)
                    lines .= pn " := " this.Text(d) "`n"
                continue
            }
            if (pn != sig[k] && AxImport.Uses(bodyText, pn)) {
                if (this.Names.Has(pn) || this.Vars.Has(pn) || pn = this.Gv)
                    return ""                   ; would overwrite a global the handler declares
                lines .= pn " := " sig[k] "`n"
            }
        }
        bt := t.Type(body)
        if (bt = "Grouped") {
            inner := t.FirstChild(body)
            if (t.Type(inner) = "Sequence") {
                items := this.Kids(inner)
                all := true
                for x in items
                    if !this.Statementish(x)
                        all := false
                if all {
                    for x in items
                        lines .= AxImport.Tidy(this.Text(x)) "`n"
                    return RTrim(lines, "`n")
                }
            } else if this.Statementish(inner)
                return lines AxImport.Tidy(this.Text(inner))
            return lines "return " AxImport.Tidy(bodyText)
        }
        if this.Statementish(body)
            return lines AxImport.Tidy(bodyText)
        return lines "return " AxImport.Tidy(bodyText)
    }
    Statementish(x) {
        t := this.T, ty := t.Type(x)
        if (ty = "Call" || ty = "PostfixExpr")
            return true
        if (ty = "BinaryExpr" && t.Has(x, "assign"))
            return true
        return ty = "UnaryExpr" && (t.Value(x) = "++" || t.Value(x) = "--")
    }

    ShowOpts(argsNode) {
        t := this.T
        a := this.Kids(argsNode)
        if !a.Length
            return
        v := this.Lit(a[1], &ok)
        if !ok
            return this.Note(a[1], "The window is shown with options worked out as it runs; the design shows it as usual.")
        if (v = 0 && t.Type(a[1]) != "String")
            return this.W.StartState := "hidden"
        v := String(v)
        if RegExMatch(v, "i)\bw(\d+)", &m)
            this.W.Width := m[1] + 0
        if RegExMatch(v, "i)\bh(\d+)", &m)
            this.W.Height := m[1] + 0
        if RegExMatch(v, "i)\bx(-?\d+)", &m)
            this.W.WinX := m[1] + 0, this.W.StartPos := "xy"
        if RegExMatch(v, "i)\by(-?\d+)", &m)
            this.W.WinY := m[1] + 0, this.W.StartPos := "xy"
        if RegExMatch(v, "i)\bMaximize\b")
            this.W.StartState := "max"
        else if RegExMatch(v, "i)\bMinimize\b")
            this.W.StartState := "min"
        else if RegExMatch(v, "i)\bHide\b")
            this.W.StartState := "hidden"
    }

    ; ------------------------------------------------------------------- code
    CodeNode(text) {
        n := AxNode("Code", this.P.NewId())
        n.Name := ""
        n.Arg := text
        n.L["place"] := "flow"
        return n
    }
    ; Code that ran at this point of building the window, as a block at this
    ; point of the design. Pieces with nothing between them are one block.
    CodeHere(text) {
        text := RTrim(text, "`r`n")
        tab := (this.Cur.Type = "Tab" && this.Tab >= 1) ? this.Tab : 0
        kids := this.Cur.Kids
        if (kids.Length && kids[-1].Type = "Code" && Integer(kids[-1].Lay("tab", 0)) = tab) {
            kids[-1].Arg .= "`n" text
            return
        }
        n := this.CodeNode(text)
        if tab
            n.L["tab"] := tab
        this.P.Insert(this.Cur, n)
        this.N.Code++
    }
    ToScript(text, from, to) {
        text := RTrim(text, "`r`n")
        if (this.Script != "") {
            gap := SubStr(this.Src, this.ScriptEnd + 1, from - this.ScriptEnd)
            this.Script .= (StrLen(gap) - StrLen(StrReplace(gap, "`n")) >= 2) ? "`n`n" : "`n"
        }
        this.Script .= text
        this.ScriptEnd := to
        this.N.Script++
    }
    Note(i, msg) => this.Notes.Push("Line " this.T.StartLine(i) ": " msg)

    ; -------------------------------------------------------------- literals
    Kids(i) {
        out := []
        if (i < 0)
            return out
        for c in this.T.Children(i)
            if (this.T.Type(c) != "Comment")
                out.Push(c)
        return out
    }
    Text(i) => SubStr(this.Src, this.T.Start(i) + 1, this.T.End(i) - this.T.Start(i))

    ; The value of an expression that is only literals: a string, a number,
    ; true/false, and those joined up. ok is false for anything else.
    Lit(i, &ok) {
        t := this.T
        ok := true
        switch t.Type(i) {
        case "String":
            ; a continuation section comes already joined by the parser's rules
            return AxImport.Unq(t.Value(i), &ok, SubStr(t.Meta(i), 1, 4) = "raw:")
        case "Number":
            v := t.Value(i)
            return IsNumber(v) ? v + 0 : (ok := false, "")
        case "Identifier":
            v := StrLower(t.Value(i))
            return (v = "true") ? 1 : (v = "false") ? 0 : (ok := false, "")
        case "Grouped":
            k := this.Kids(i)
            return (k.Length = 1) ? this.Lit(k[1], &ok) : (ok := false, "")
        case "UnaryExpr":
            if (t.Value(i) = "-") {
                v := this.Lit(t.FirstChild(i), &ok)
                return (ok && IsNumber(v)) ? -v : (ok := false, "")
            }
        case "BinaryExpr", "Concat":
            if (t.Type(i) = "Concat" || t.Value(i) = ".") {
                l := t.FirstChild(i), r := t.Next(l)
                a := this.Lit(l, &ok1), b := this.Lit(r, &ok2)
                if (ok1 && ok2)
                    return a b
            }
        }
        ok := false
        return ""
    }
    ; "abc`n" / 'it`'s' -> its value
    static Unq(s, &ok, joined := false) {
        ok := false
        q := SubStr(s, 1, 1)
        if !((q = '"' || q = "'") && StrLen(s) >= 2 && SubStr(s, -1) = q)
            return ""
        body := SubStr(s, 2, -1)
        if (!joined && InStr(body, "`n"))
            return ""
        body := StrReplace(body, "`r`n", "`n")
        out := "", i := 1
        while (p := InStr(body, "``", true, i)) {
            out .= SubStr(body, i, p - i)
            c := SubStr(body, p + 1, 1)
            out .= (c == "n") ? "`n" : (c == "r") ? "`r" : (c == "t") ? "`t" : (c == "b") ? "`b"
                 : (c == "v") ? "`v" : (c == "a") ? "`a" : (c == "f") ? "`f" : (c == "s") ? " " : c
            i := p + 2
        }
        ok := true
        return out SubStr(body, i)
    }

    ; ---------------------------------------------------------- small helpers
    Mentioned(name) {
        pos := 1, n := 0
        while (pos := RegExMatch(this.Src, "i)[`"']\Q" name "\E[`"']", &m, pos))
            n++, pos += m.Len
        return n > 0
    }
    static Uses(text, name) => RegExMatch(text, "i)(?<![\w.])\Q" name "\E(?!\w)") > 0
    static Join(a) {
        s := ""
        for x in a
            s .= (s = "" ? "" : ", ") x
        return s
    }
    static Tail(a, from) {
        out := []
        loop a.Length - from + 1
            out.Push(a[from + A_Index - 1])
        return out
    }
    ; A handler written across several lines keeps its shape: the lines after
    ; the first lose the indentation they had in the script and sit one step
    ; in, as the continuation they are.
    static Tidy(text) {
        lines := StrSplit(StrReplace(text, "`r", ""), "`n")
        if (lines.Length < 2)
            return text
        least := 1000
        loop lines.Length - 1 {
            ln := lines[A_Index + 1]
            if (Trim(ln) = "")
                continue
            RegExMatch(ln, "^[ \t]*", &m)
            least := Min(least, StrLen(m[0]))
        }
        out := lines[1]
        loop lines.Length - 1 {
            ln := lines[A_Index + 1]
            out .= "`n" (Trim(ln) = "" ? "" : "    " SubStr(ln, least + 1))
        }
        return out
    }
    ; Ahk2Exe reads its ;@Ahk2Exe- lines from anywhere in a script, and the
    ; export writes its own. An old one carried along would win over them.
    static NoCompilerLines(text) => RegExReplace(text, "im)^[ \t]*;@Ahk2Exe-[^\r\n]*(\r?\n)?")
}
