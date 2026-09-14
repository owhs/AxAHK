#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\AxStudio.Import.ahk
#Include %A_LineFile%\..\AxStudio.Layout.ahk
#Include %A_LineFile%\..\AxStudio.Theme.ahk

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
;  AxStudio.ImportGui.ahk -- a script built on AutoHotkey's own Gui(), as a
;  design.
;
;  Where each control is: the script is not run. Its Gui calls are replayed,
;  with their option strings worked out, on a native window of the studio's
;  own that is never shown, and Windows is asked where each control landed.
;  So xp, yp+24, Section, default sizes and the font in force all come out
;  exactly as AutoHotkey places them -- nothing here imitates its rules.
;
;  What the options are: worked out from what the script knows before it
;  runs -- literals, Format(), sums, the locals set above, a class's own
;  starting values. Where a branch depends on the machine (a GPU feature,
;  whether it is elevated) the design takes the first way, and says so.
;
;  Two kinds of window:
;
;    made at the top of the script     the whole thing comes over: the design,
;                                      its handlers, and the rest split into
;                                      the design's rules, code blocks and the
;                                      window's script
;    made inside a function or class   its look comes over as a window of the
;                                      design; the function that builds it is
;                                      kept as it is, because what it wires up
;                                      (this.Refresh, this.Gpu ...) lives in
;                                      the class
;
;  Every control lands where it was, fixed. AxLayout turns that into rows
;  that resize, and back, from the same design.
; =============================================================================
class AxImportGui extends AxImport {
    ; native type -> the design's type. "" = handled on its own.
    static Types := Map("text", "Text", "edit", "Edit", "button", "Button", "checkbox", "CheckBox",
        "radio", "Radio", "dropdownlist", "DDL", "ddl", "DDL", "combobox", "DDL", "listbox", "ListBox",
        "slider", "Slider", "progress", "Progress", "groupbox", "GroupBox", "picture", "Picture", "pic", "Picture",
        "link", "Link", "hotkey", "Hotkey", "datetime", "Date", "monthcal", "Calendar", "listview", "ListView",
        "treeview", "TreeView", "tab", "Tab", "tab2", "Tab", "tab3", "Tab", "activex", "ActiveX",
        "updown", "", "statusbar", "", "custom", "")
    ; native event -> the design's
    static Events := Map("click", "Click", "doubleclick", "DoubleClick", "change", "Change", "focus", "Focus",
        "losefocus", "Blur", "contextmenu", "ContextMenu", "itemselect", "ItemSelect", "itemcheck", "ItemCheck",
        "itemexpand", "ItemExpand", "itemfocus", "ItemFocus", "colclick", "ColClick")
    ; what can be worked out before the script runs
    static Known := Map("format", Format, "round", Round, "floor", Floor, "ceil", Ceil, "integer", Integer,
        "abs", Abs, "min", Min, "max", Max, "strlen", StrLen, "substr", SubStr, "trim", Trim, "chr", Chr,
        "string", String, "number", Number, "strupper", StrUpper, "strlower", StrLower, "strreplace", StrReplace)

    __New(path, src, t) {
        super.__New(path, src, t)
        this.Env := Map()
        this.Env.CaseSense := false
        this.Wins := []
        this.Consumed := Map()              ; top-level statements the design now does
        this.Admin := false
        this.Guessed := 0
        this.N.Rules := 0
        this.N.Windows := 0
    }

    ; Either kind of script: AxGui windows go to AxImport, Gui() ones here.
    static FromFile(path) {
        src := FileRead(path, "UTF-8")
        t := AxHost.Tree(path)
        if (!AxImportGui.Uses(t, "AxGui") && AxImportGui.Uses(t, "Gui"))
            return AxImportGui(path, src, t).Run()
        ; no window at all -- hotkeys, hotstrings, timers: a project that is
        ; only what it does (AxStudio.ImportLogic.ahk finds it)
        if !AxImportGui.Uses(t, "AxGui")
            return AxImportLogic.Plain(path, src)
        return AxImport(path, src, t).Run()
    }
    static Uses(t, fn) {
        loop t.count {
            i := A_Index - 1
            if (t.Type(i) = "Call") {
                c := t.FirstChild(i)
                if (c >= 0 && t.Type(c) = "Identifier" && t.Value(c) = fn)
                    return true
            }
        }
        return false
    }
    ; Is there a Gui() anywhere in it?
    static Finds(t) {
        loop t.count {
            i := A_Index - 1
            if (t.Type(i) = "Call") {
                c := t.FirstChild(i)
                if (c >= 0 && t.Type(c) = "Identifier" && t.Value(c) = "Gui")
                    return true
            }
        }
        return false
    }

    Run() {
        t := this.T
        this.Admin := !!RegExMatch(this.Src, "i)\*RunAs\b") && InStr(this.Src, "A_IsAdmin")
        if this.Admin {
            AxAsset.SetCompile(this.P, "admin", "1")
            this.Notes.Push("It asks for administrator rights, so the design is set to run as administrator"
                . " (App > Script settings), and shows the window the way it looks elevated.")
        }
        this.Find()
        if !this.Wins.Length
            throw Error("This script makes no Gui() window that has any controls, so there is no design in it to bring in.")
        main := ""
        for idx, w in this.Wins
            if (w.Fn < 0 && !IsObject(main)) {
                main := w
                this.Wins.RemoveAt(idx), this.Wins.InsertAt(1, w)     ; the window of the design
                break
            }
        this.Main := main
        first := true
        for w in this.Wins {
            AxImportGui.Shadow(w)
            win := first ? this.P.Wins[1] : this.P.AddWin("window", this.WinName(w))
            if first
                win.Name := IsObject(main) && w = main ? "Main" : this.WinName(w)
            this.Build(w, win, IsObject(main) && w = main)
            first := false
            this.N.Windows++
        }
        if IsObject(main) {
            this.Gv := ""                       ; set again when the walk reaches it
            this.W := this.P.Wins[1], this.Root := this.W.Root, this.Cur := this.Root
            for i in t.Children(0)
                this.Top(i)
            if (Trim(this.Before) != "") {
                n := this.CodeNode(this.Before)
                this.P.Insert(this.Root, n, 1)
                this.Park(n)
            }
            for n in this.Root.Kids
                if (n.Type = "Code")
                    this.Park(n)
            this.W.Script := Trim(this.Script, "`r`n")
        } else {
            ; No window at the top: every one is made by the script's own
            ; code, which is kept -- with its Gui() calls pointed at the design.
            this.Gv := "(none)", this.Shown := true
            for i in t.Children(0)
                this.Top(i)
            this.P.Wins[1].Script := Trim(this.Script, "`r`n")
        }
        for p in t.Problems
            this.Notes.Push("Line " AxJson.Get(AxJson.Get(p, "start", Map()), "line", "?") ": the parser says "
                . AxJson.Get(p, "message", "?"))
        this.Rules()
        this.P.Cur := 1
        this.P.Dirty := true
        return {Project: this.P, Notes: this.Notes, N: this.N}
    }
    WinName(w) {
        base := (w.Cls != "") ? w.Cls : RegExReplace(w.Key, "^this\.", "")
        base := AxProject.CleanName(base)
        return this.P.UniqueWinName(base = "" ? "Window" : base)
    }

    ; ------------------------------------------------------- finding windows
    Find() {
        t := this.T
        loop t.count {
            i := A_Index - 1
            if !(t.Type(i) = "BinaryExpr" && t.Value(i) = ":=")
                continue
            l := t.FirstChild(i), r := t.Next(l)
            if (t.Type(r) != "Call")
                continue
            c := t.FirstChild(r)
            if !(t.Type(c) = "Identifier" && t.Value(c) = "Gui")
                continue
            key := this.Ref(l)
            if (key = "")
                continue
            fn := -1, cls := "", p := t.Parent(i)
            while (p >= 0) {
                if (fn < 0 && t.Type(p) = "Method")
                    fn := p
                if (t.Type(p) = "Class") {
                    cls := t.Value(p)
                    break
                }
                p := t.Parent(p)
            }
            w := {Key: key, Stmt: i, Fn: fn, Cls: cls, ClsNode: (p >= 0 ? p : -1), GuiOpts: "", Title: "",
                  EventObj: false, Items: [], Ctl: Map(), Show: "", ShowStmt: -1, Back: "", MarginX: "", MarginY: "",
                  Armed: false, Tab: "", TabIdx: 0, BaseFont: "", Font: "", WinEvents: [], Guess: [], Stmts: Map()}
            w.Ctl.CaseSense := false
            this.Replay(w)
            if AxImportGui.CountCtl(w)
                this.Wins.Push(w)
        }
    }
    static CountCtl(w) {
        n := 0
        for it in w.Items
            if (it.Kind = "ctl")
                n++
        return n
    }

    ; a, this.a, a.b.c -> the key it is known by
    Ref(i) {
        t := this.T
        switch t.Type(i) {
        case "Identifier":
            return t.Value(i)
        case "This":
            return "this"
        case "Member":
            o := this.Ref(t.FirstChild(i))
            return (o = "") ? "" : o "." t.Value(i)
        }
        return ""
    }

    ; ------------------------------------------------------ replaying the code
    Replay(w) {
        t := this.T
        env := Map()
        env.CaseSense := false
        env["A_IsAdmin"] := this.Admin ? 1 : 0
        env["A_ScreenWidth"] := A_ScreenWidth, env["A_ScreenHeight"] := A_ScreenHeight
        env["A_ScriptDir"] := this.Dir, env["A_PtrSize"] := 8
        if (w.ClsNode >= 0)
            this.ClassEnv(w.ClsNode, env)
        this.Env := env
        this.MenuObj := Map()                   ; key -> a Menu() / MenuBar() being filled
        this.MenuObj.CaseSense := false
        body := (w.Fn >= 0) ? this.Body(w.Fn) : 0
        for s in t.Children(body)
            this.S(s, w, true)
    }
    Body(fn) {
        for c in this.T.Children(fn)
            if (this.T.Type(c) = "Block")
                return c
        return -1
    }
    ; A class's starting values: `x := 1` in its body, `this.x := 1` in its methods.
    ClassEnv(cls, env) {
        t := this.T
        for m in t.Children(cls) {
            ty := t.Type(m)
            if (ty = "StaticAssign" || ty = "Declaration") {
                v := t.FirstChild(m)
                if (v >= 0) {
                    x := this.Eval(v, &ok)
                    if ok
                        env["this." t.Value(m)] := x
                }
            } else if (ty = "Method") {
                b := this.Body(m)
                if (b < 0)
                    continue
                for s in t.Children(b) {
                    if !(t.Type(s) = "BinaryExpr" && t.Value(s) = ":=")
                        continue
                    l := t.FirstChild(s)
                    k := this.Ref(l)
                    if (SubStr(k, 1, 5) != "this." || env.Has(k))
                        continue
                    x := this.Eval(t.Next(l), &ok)
                    if ok
                        env[k] := x
                }
            }
        }
    }

    ; One statement. top: it is a statement of the list the window lives in,
    ; so what it does to the window can be taken out of the code.
    S(i, w, top := false) {
        t := this.T
        switch t.Type(i) {
        case "Block":
            for c in t.Children(i)
                this.S(c, w)
        case "If":
            k := this.Kids(i)
            if (k.Length < 2)
                return
            els := (k.Length >= 3 && t.Type(k[3]) = "Else") ? t.FirstChild(k[3]) : -1
            c := this.Eval(k[1], &ok)
            if ok {
                if c
                    this.S(k[2], w)
                else if (els >= 0)
                    this.S(els, w)
            } else {
                if w.Armed
                    w.Guess.Push(t.StartLine(i))
                this.S(k[2], w)
            }
        case "Try":
            c := t.FirstChild(i)
            if (c >= 0)
                this.S(c, w)
        case "For":
            this.ForLoop(i, w)
        case "Loop":
            this.LoopN(i, w)
        case "MultiStatement":
            for c in this.Kids(i)
                this.S(c, w, top)
        case "BinaryExpr":
            if t.Has(i, "assign")
                this.Assign(i, w, top)
        case "Call":
            this.CallStmt(i, w, top)
        }
    }
    ForLoop(i, w) {
        t := this.T
        k := this.Kids(i)
        if (k.Length < 3)
            return
        vars := this.Kids(k[1])
        coll := this.Eval(k[2], &ok)
        if (!ok || !(coll is Array) || coll.Length > 200) {
            if w.Armed && RegExMatch(this.Text(k[3]), "i)\.Add\w*\(")
                w.Guess.Push(t.StartLine(i))
            return
        }
        for idx, v in coll {
            if (vars.Length = 1)
                this.Env[t.Value(vars[1])] := v
            else if (vars.Length >= 2)
                this.Env[t.Value(vars[1])] := idx, this.Env[t.Value(vars[2])] := v
            this.S(k[3], w)
        }
    }
    LoopN(i, w) {
        t := this.T
        k := this.Kids(i)
        if (t.Value(i) != "" || k.Length < 2)
            return
        n := this.Eval(k[1], &ok)
        if (!ok || !IsInteger(n) || n > 200) {
            if w.Armed && RegExMatch(this.Text(k[-1]), "i)\.Add\w*\(")
                w.Guess.Push(t.StartLine(i))
            return
        }
        loop n {
            this.Env["A_Index"] := A_Index
            this.S(k[2], w)
        }
    }

    Assign(i, w, top) {
        t := this.T
        l := t.FirstChild(i), r := t.Next(l)
        key := this.Ref(l)
        ; m := Menu() / MenuBar(): a menu being made, wherever it is made
        if (key != "" && t.Type(r) = "Call") {
            c := t.FirstChild(r)
            if (t.Type(c) = "Identifier" && (t.Value(c) = "Menu" || t.Value(c) = "MenuBar")) {
                this.MenuObj[key] := {Bar: t.Value(c) = "MenuBar", Items: [], Stmts: [{I: i, Top: top}]}
                return
            }
        }
        ; the window itself
        if (i = w.Stmt) {
            a := this.Kids(t.Next(t.FirstChild(r)))
            w.Armed := true
            if (a.Length >= 1 && t.Type(a[1]) != "Omitted")
                w.GuiOpts := String(this.Eval(a[1], &ok))
            if (a.Length >= 2 && t.Type(a[2]) != "Omitted")
                w.Title := String(this.Eval(a[2], &ok))
            if (a.Length >= 3)
                w.EventObj := true, w.SinkText := this.Text(a[3])
            if top
                w.Stmts[i] := true
            return
        }
        if w.Armed {
            ; an item of a tree kept for the ones under it: p := TV.Add("x")
            if (t.Type(r) = "Call" && key != "") {
                c := this.ChainR(r)
                if (IsObject(c) && w.Ctl.Has(c.Root) && w.Ctl[c.Root].Type = "treeview"
                    && c.Calls.Length = 1 && StrLower(c.Calls[1].Name) = "add") {
                    if (top && w.Fn < 0 && this.DataAdd(w.Ctl[c.Root], c.Calls[1], key, i, c.Root))
                        w.Stmts[i] := true
                    else {
                        ; not held by the design: whatever p was before, it is
                        ; not known now, and nothing may go under it there
                        if this.Env.Has(key)
                            this.Env.Delete(key)
                        if w.Ctl[c.Root].TreeVars.Has(key)
                            w.Ctl[c.Root].TreeVars.Delete(key)
                    }
                    return
                }
            }
            ; a control made and kept: x := g.Add...(...)
            if (t.Type(r) = "Call") {
                c := this.ChainR(r)
                if (IsObject(c) && c.Root = w.Key) {
                    it := this.Control(c.Calls, w, key)
                    if IsObject(it) {
                        if top
                            w.Stmts[i] := true
                        if (key != "") {
                            w.Ctl[key] := it
                            if this.Env.Has(key)
                                this.Env.Delete(key)
                        }
                        return
                    }
                }
            }
            ; the window's own properties
            if (t.Type(l) = "Member") {
                o := this.Ref(t.FirstChild(l)), p := StrLower(t.Value(l))
                if (o = w.Key) {
                    v := this.Eval(r, &ok)
                    if ok {
                        switch p {
                        case "backcolor": w.Back := String(v)
                        case "title":     w.Title := String(v)
                        case "marginx":   w.MarginX := v
                        case "marginy":   w.MarginY := v
                        default:          ok := false
                        }
                        if (ok && top)
                            w.Stmts[i] := true
                    } else if (p = "menubar" && this.MenuObj.Has(this.Ref(r))) {
                        w.MenuBar := this.Ref(r), w.MenuStmt := {I: i, Top: top, Left: l}
                    }
                    return
                }
                if w.Ctl.Has(o) {
                    v := this.Eval(r, &ok)
                    if ok {
                        it := w.Ctl[o]
                        switch p {
                        case "value", "text": it.Set := v, it.SetProp := p
                        case "enabled":      it.Disabled := !v
                        case "visible":      it.Hidden := !v
                        default:             ok := false
                        }
                        if (ok && top)
                            w.Stmts[i] := true
                    }
                    return
                }
            }
        }
        if (key = "")
            return
        op := t.Value(i)
        if (op = ":=") {
            v := this.Eval(r, &ok)
        } else if (this.Env.Has(key)) {
            b := this.Eval(r, &ok)
            v := ok ? AxImportGui.Op(SubStr(op, 1, -1), this.Env[key], b, &ok) : ""
        } else
            ok := false
        if ok
            this.Env[key] := v
        else if this.Env.Has(key)
            this.Env.Delete(key)
    }

    CallStmt(i, w, top) {
        t := this.T
        c := this.ChainR(i)
        if !IsObject(c)
            return
        ; m.Add("&Open`tCtrl+O", fn) / m.Add("&File", sub) / m.Add()
        if (this.MenuObj.Has(c.Root) && c.Calls.Length = 1 && StrLower(c.Calls[1].Name) = "add") {
            m := this.MenuObj[c.Root]
            a := this.Kids(c.Calls[1].Args)
            m.Stmts.Push({I: i, Top: top})
            if !a.Length
                return m.Items.Push({Sep: true})
            label := this.Eval(a[1], &ok)
            if !ok
                label := "(worked out as it runs)"
            sub := (a.Length >= 2) ? this.Ref(a[2]) : ""
            if (sub != "" && this.MenuObj.Has(sub))
                return m.Items.Push({Label: String(label), Sub: sub})
            return m.Items.Push({Label: String(label), Fn: (a.Length >= 2) ? a[2] : -1, Pos: m.Items.Length + 1})
        }
        ; anything else done to a menu (an icon, a tick, Show): it stays code
        if this.MenuObj.Has(c.Root)
            this.MenuObj[c.Root].Other := true
        if !w.Armed
            return
        if (c.Root = w.Key) {
            first := c.Calls[1]
            a := this.Kids(first.Args)
            switch StrLower(first.Name) {
            case "setfont":
                o := (a.Length >= 1 && t.Type(a[1]) != "Omitted") ? String(this.Eval(a[1], &ok1)) : ""
                f := (a.Length >= 2) ? String(this.Eval(a[2], &ok2)) : ""
                w.Items.Push({Kind: "font", Opts: o, Name: f})
                w.Font := AxImportGui.FontStep(w.Font, o, f)
                if top
                    w.Stmts[i] := true
                return
            case "show":
                w.Show := (a.Length >= 1) ? String(this.Eval(a[1], &ok)) : ""
                w.ShowStmt := i
                if top
                    w.Stmts[i] := true
                return
            case "opt":
                if (a.Length = 1)
                    w.GuiOpts .= " " String(this.Eval(a[1], &ok))
                if top
                    w.Stmts[i] := true
                return
            case "onevent":
                if (a.Length >= 2)
                    w.WinEvents.Push({Name: StrLower(this.Lit(a[1], &ok)), Fn: a[2], Stmt: i})
                return
            }
            it := this.Control(c.Calls, w, "")
            if (IsObject(it) && top)
                w.Stmts[i] := true
            return
        }
        if !w.Ctl.Has(c.Root)
            return
        it := w.Ctl[c.Root]
        ; LV.Add(, "a", "b") / TV.Add("x", parent) / DDL.Add(["a", "b"]): what
        ; the design can hold itself
        if (c.Calls.Length = 1 && StrLower(c.Calls[1].Name) = "add"
            && RegExMatch(it.Type, "i)^(listview|treeview|dropdownlist|ddl|combobox|listbox)$")) {
            if (top && w.Fn < 0 && this.DataAdd(it, c.Calls[1], "", i, c.Root))
                w.Stmts[i] := true
            else
                it.DataStop := true
            return
        }
        if this.OnCtl(it, c.Calls, w) && top
            w.Stmts[i] := true
    }
    ; One LV.Add / TV.Add the design can hold instead of the script: nothing
    ; in it worked out as it runs, and no option but a tick (or, on a tree,
    ; opened). A tree item kept in a variable stays one only if nothing but
    ; the items under it use the variable -- DataTree checks that.
    DataAdd(it, call, key, stmt, root := "") {
        t := this.T
        a := this.Kids(call.Args)
        ; Only while nothing else has touched it: a row added by code the
        ; design does not hold, then one it does, would come out in the wrong
        ; order -- the design's first. So the design holds the ones before
        ; anything else, and none after.
        if it.DataStop
            return false
        if (root != "" && it.HasOwnProp("Call")) {
            from := it.HasOwnProp("DataAt") ? it.DataAt : t.End(it.Call)
            between := SubStr(this.Src, from + 1, Max(0, t.Start(stmt) - from))
            if RegExMatch(between, "i)(?<![\w.])\Q" root "\E\.(Add|Insert|Delete|Modify|Choose)\b") {
                it.DataStop := true
                return false
            }
            it.DataAt := t.End(stmt)
        }
        Val(x, &ok) {
            if (t.Type(x) = "Omitted")
                return (ok := true, "")
            return this.Eval(x, &ok)
        }
        if RegExMatch(it.Type, "i)^(dropdownlist|ddl|combobox|listbox)$") {
            if (a.Length != 1)
                return false
            more := Val(a[1], &ok)
            if (!ok || !(more is Array))
                return false
            list := (it.Text is Array) ? it.Text.Clone() : (String(it.Text) = "" ? [] : StrSplit(String(it.Text), "|"))
            for y in more
                list.Push(y)
            it.Text := list
            return true
        }
        if (it.Type = "listview") {
            if (it.TextExpr != "" || (it.Text is String && Trim(it.Text) = ""))
                return false                            ; no titles: the design's text would have none either
            opts := a.Length ? Val(a[1], &ok) : ""
            if (a.Length && !ok) || !RegExMatch(opts, "i)^\s*(\+?Check(ed)?\s*)?$")
                return false
            vals := []
            loop a.Length - 1 {
                v := Val(a[A_Index + 1], &ok)
                if (!ok || IsObject(v))
                    return false
                vals.Push(v)
            }
            it.Rows.Push({Vals: vals, Check: opts != "", Stmt: stmt})
            return true
        }
        if !a.Length
            return false
        name := Val(a[1], &ok)
        if (!ok || IsObject(name))
            return false
        parent := 0
        if (a.Length >= 2 && t.Type(a[2]) != "Omitted") {
            ref := this.Ref(a[2])
            if (ref != "" && it.TreeVars.Has(ref))
                parent := it.TreeVars[ref], it.TreeUses[ref] := it.TreeUses.Get(ref, 0) + 1
            else {
                p := this.Eval(a[2], &ok)
                if !(ok && p = 0)
                    return false
            }
        }
        opts := (a.Length >= 3) ? Val(a[3], &ok) : ""
        if (a.Length >= 3 && !ok) || !RegExMatch(opts, "i)^(\s*\+?(Check|Expand)\s*)*$")
            return false
        it.TreeItems.Push({Name: String(name), Parent: parent, Check: !!RegExMatch(opts, "i)Check"),
                           Expand: !!RegExMatch(opts, "i)Expand"), Stmt: stmt, Var: key})
        if (key != "") {
            it.TreeVars[key] := it.TreeItems.Length
            if this.Env.Has(key)
                this.Env.Delete(key)
        }
        return true
    }
    ; The tree's items the script added, as the design's indented lines --
    ; or none of them, with their code left where it was, when one of the
    ; variables it kept an item in is used for anything else.
    DataTree(it, w) {
        t := this.T
        for v, idx in it.TreeVars {
            uses := 0
            loop t.count
                if (t.Type(A_Index - 1) = "Identifier" && t.Value(A_Index - 1) = v)
                    uses++
            if (uses != 1 + it.TreeUses.Get(v, 0)) {
                for x in it.TreeItems
                    if w.Stmts.Has(x.Stmt)
                        w.Stmts.Delete(x.Stmt)
                it.TreeItems := []
                return ""
            }
        }
        out := ""
        Put(parent, depth) {
            s := ""
            for idx, x in it.TreeItems
                if (x.Parent = parent) {
                    pad := ""
                    loop depth
                        pad .= "    "
                    mark := (x.Check || x.Expand) ? "[" (x.Check ? "x" : "") (x.Expand ? "+" : "") "] " : ""
                    s .= pad mark StrReplace(x.Name, "`n", " ") "`n" Put(idx, depth + 1)
                }
            return s
        }
        return RTrim(Put(0, 0), "`n")
    }

    ; g.Add("Type", o, t) / g.AddType(o, t), and what is chained on it
    Control(calls, w, key) {
        t := this.T
        first := calls[1]
        name := StrLower(first.Name)
        a := this.Kids(first.Args)
        if (name = "add") {
            if !a.Length
                return ""
            type := StrLower(this.Eval(a[1], &ok))
            if !ok
                return ""
            a.RemoveAt(1)
        } else if (SubStr(name, 1, 3) = "add")
            type := SubStr(name, 4)
        else
            return ""
        if !AxImportGui.Types.Has(type)
            return ""
        opts := "", text := "", guessed := false
        if (a.Length >= 1 && t.Type(a[1]) != "Omitted") {
            opts := this.Eval(a[1], &ok)
            if !ok
                opts := this.Partial(a[1]), guessed := true
        }
        if (a.Length >= 2 && t.Type(a[2]) != "Omitted") {
            text := this.Eval(a[2], &ok)
            if !ok
                text := "", guessed := true, textExpr := this.Text(a[2])
        }
        it := {Kind: "ctl", Type: type, Opts: String(opts), Text: text, TextExpr: IsSet(textExpr) ? textExpr : "",
               Call: first.Node, NodeRef: "",
               Key: key, Tab: w.Tab, TabIdx: w.TabIdx, Font: w.Font, Events: [], Set: "", SetProp: "", Disabled: "", Hidden: "",
               Guessed: guessed, Line: t.StartLine(first.Node), X: "", Y: "", W: "", H: "", OwnFont: "",
               PageX: "", PageY: "", Rows: [], TreeItems: [], TreeVars: Map(), TreeUses: Map(), DataStop: false}
        w.Items.Push(it)
        if (type = "tab" || type = "tab2" || type = "tab3")
            w.Tab := it, w.TabIdx := 1          ; what follows goes on its first tab
        if (calls.Length > 1)
            this.OnCtl(it, AxImport.Tail(calls, 2), w)
        return it
    }
    ; ctl.OnEvent / SetFont / Opt / UseTab: true when all of it is understood
    OnCtl(it, calls, w) {
        t := this.T
        all := true
        for c in calls {
            a := this.Kids(c.Args)
            switch StrLower(c.Name) {
            case "onevent":
                if (a.Length >= 2) {
                    ev := this.Lit(a[1], &ok)
                    if ok {
                        it.Events.Push({Name: StrLower(ev), Fn: a[2]})
                        continue
                    }
                }
                all := false
            case "setfont":
                o := (a.Length >= 1) ? String(this.Eval(a[1], &ok1)) : ""
                f := (a.Length >= 2) ? String(this.Eval(a[2], &ok2)) : ""
                it.OwnFont := AxImportGui.FontStep(it.Font, o, f)
            case "opt":
                o := (a.Length = 1) ? this.Eval(a[1], &ok) : ""
                it.Opts .= " " String(o)
            case "usetab":
                n := (a.Length >= 1) ? this.Eval(a[1], &ok) : 0
                w.Items.Push({Kind: "usetab", Tab: it, Idx: IsInteger(n) ? n : 0})
                w.Tab := (IsInteger(n) && n >= 1) ? it : "", w.TabIdx := IsInteger(n) ? n : 0
            default:
                all := false
            }
        }
        return all
    }
    ; a.B(x).C(y) with any root: g, this.Gui, obj.gui
    ChainR(e) {
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
        k := this.Ref(e)
        return (k = "") ? "" : {Root: k, Calls: calls}
    }
    ; "x34 yp+24 w" colW: the literal parts of an option string that could
    ; not be worked out whole, so the positions that are known still count
    Partial(i) {
        t := this.T
        if (t.Type(i) = "BinaryExpr" && t.Value(i) = "." || t.Type(i) = "Concat") {
            l := t.FirstChild(i), r := t.Next(l)
            return this.Partial(l) " " this.Partial(r)
        }
        v := this.Eval(i, &ok)
        return ok ? String(v) : ""
    }

    ; ---------------------------------------------------------- the evaluator
    ; The value of an expression from what is known before the script runs.
    Eval(i, &ok) {
        t := this.T
        ok := true
        switch t.Type(i) {
        case "String", "Number", "Grouped":
            v := this.Lit(i, &ok)
            if (ok || t.Type(i) != "Grouped")
                return v
            k := this.Kids(i)
            return (k.Length = 1) ? this.Eval(k[1], &ok) : (ok := false, "")
        case "Identifier":
            n := t.Value(i)
            if (StrLower(n) = "true")
                return 1
            if (StrLower(n) = "false")
                return 0
            if this.Env.Has(n)
                return this.Env[n]
        case "Member":
            k := this.Ref(i)
            if (k != "" && this.Env.Has(k))
                return this.Env[k]
        case "UnaryExpr":
            v := this.Eval(t.FirstChild(i), &ok)
            if ok {
                switch t.Value(i), false {
                case "-":       return IsNumber(v) ? -v : (ok := false, "")
                case "+":       return v
                case "!", "not": return !v
                }
            }
        case "Concat":
            l := t.FirstChild(i), r := t.Next(l)
            a := this.Eval(l, &ok1), b := this.Eval(r, &ok2)
            if (ok1 && ok2)
                return a b
        case "BinaryExpr":
            op := t.Value(i)
            if t.Has(i, "assign")
                return (ok := false, "")
            l := t.FirstChild(i), r := t.Next(l)
            a := this.Eval(l, &ok1)
            if (ok1 && (op = "&&" || StrLower(op) = "and") && !a)
                return 0
            if (ok1 && (op = "||" || StrLower(op) = "or") && a)
                return a
            b := this.Eval(r, &ok2)
            if (ok1 && ok2)
                return AxImportGui.Op(op, a, b, &ok)
        case "Ternary":
            k := this.Kids(i)
            c := this.Eval(k[1], &okc)
            if okc
                return this.Eval(c ? k[2] : k[3], &ok)
            this.Guessed++
            return this.Eval(k[2], &ok)
        case "Array":
            out := []
            for x in this.Kids(i) {
                v := this.Eval(x, &okx)
                if !okx
                    return (ok := false, "")
                out.Push(v)
            }
            return out
        case "Call":
            callee := t.FirstChild(i)
            if (t.Type(callee) = "Identifier" && AxImportGui.Known.Has(StrLower(t.Value(callee)))) {
                args := []
                for x in this.Kids(t.Next(callee)) {
                    v := this.Eval(x, &okx)
                    if !okx
                        return (ok := false, "")
                    args.Push(v)
                }
                try return AxImportGui.Known[StrLower(t.Value(callee))](args*)
            }
        }
        ok := false
        return ""
    }
    static Op(op, a, b, &ok) {
        ok := true
        try {
            switch op, false {
            case ".":         return a b
            case "+":         return a + b
            case "-":         return a - b
            case "*":         return a * b
            case "/":         return a / b
            case "//":        return a // b
            case "**":        return a ** b
            case "=":         return a = b
            case "==":        return a == b
            case "!=", "<>":  return a != b
            case "!==":       return a !== b
            case "<":         return a < b
            case ">":         return a > b
            case "<=":        return a <= b
            case ">=":        return a >= b
            case "&&", "and": return a && b
            case "||", "or":  return a || b
            }
        }
        ok := false
        return ""
    }

    ; ----------------------------------------------------------- font state
    ; Gui's SetFont is cumulative: each call changes what it names and keeps
    ; the rest. The state is kept as a Map so a control can take a copy.
    static FontStep(prev, opts, name := "") {
        f := Map()
        if (prev is Map)
            for k, v in prev
                f[k] := v
        for word in StrSplit(Trim(opts), " ") {
            if (word = "")
                continue
            if RegExMatch(word, "i)^s(\d+(?:\.\d+)?)$", &m)
                f["size"] := m[1]
            else if RegExMatch(word, "i)^w(\d+)$", &m)
                f["weight"] := m[1]
            else if RegExMatch(word, "i)^c(.+)$", &m)
                f["color"] := AxGuiCompat.Color(m[1])
            else if (word = "Bold")
                f["weight"] := 700
            else if (word = "Italic")
                f["italic"] := 1
            else if (word = "Underline")
                f["under"] := 1
            else if (word = "Strike")
                f["strike"] := 1
            else if (word = "Norm")
                f["weight"] := 400, f["italic"] := 0, f["under"] := 0, f["strike"] := 0
        }
        if (name != "")
            f["name"] := name
        return f
    }
    ; the difference between a control's font and the window's, as CSS
    static FontCss(f, base) {
        if !(f is Map)
            return ""
        css := ""
        G := (m, k) => (m is Map && m.Has(k)) ? m[k] : ""
        if (G(f, "name") != G(base, "name") && G(f, "name") != "")
            css .= "font-family:'" G(f, "name") "';"
        if (G(f, "size") != G(base, "size") && G(f, "size") != "")
            css .= "font-size:" G(f, "size") "pt;"
        if (G(f, "weight") != G(base, "weight") && G(f, "weight") != "")
            css .= "font-weight:" G(f, "weight") ";"
        if (G(f, "italic") != G(base, "italic") && G(f, "italic") != "")
            css .= "font-style:" (G(f, "italic") ? "italic" : "normal") ";"
        if (G(f, "under") || G(f, "strike"))
            css .= "text-decoration:" (G(f, "under") ? "underline" : "line-through") ";"
        if (G(f, "color") != G(base, "color") && G(f, "color") != "")
            css .= "color:" G(f, "color") ";"
        return css
    }

    ; ---------------------------------------------------------- the shadow
    ; The Gui calls again, on a native window of the studio's own that is
    ; never shown, to ask Windows where everything landed. Nothing of the
    ; script runs: only Gui() itself, with the options worked out.
    static Shadow(w) {
        scale := A_ScreenDPI / 96
        sh := ""
        try sh := Gui(AxImportGui.SafeGui(w.GuiOpts))
        catch
            sh := Gui()
        try {
            if (w.MarginX != "")
                sh.MarginX := w.MarginX
            if (w.MarginY != "")
                sh.MarginY := w.MarginY
            made := Map()
            for it in w.Items {
                switch it.Kind {
                case "font":
                    try sh.SetFont(it.Opts, it.Name)
                case "usetab":
                    if made.Has(it.Tab)
                        try made[it.Tab].UseTab(it.Idx)
                case "ctl":
                    c := AxImportGui.ShadowAdd(sh, it, w)
                    if IsObject(c) {
                        made[it] := c
                        try {
                            c.GetPos(&x, &y, &cw, &ch)
                            it.X := Round(x / scale), it.Y := Round(y / scale)
                            it.W := Round(cw / scale), it.H := Round(ch / scale)
                        }
                        ; a tab's pages start below its row (or rows) of tabs:
                        ; Windows says where, for this font and these names
                        if RegExMatch(it.Type, "i)^tab")
                            try {
                                rc := Buffer(16, 0)
                                NumPut("int", 0, "int", 0, "int", cw, "int", ch, rc)
                                SendMessage(0x1328, 0, rc.Ptr, c.Hwnd)          ; TCM_ADJUSTRECT
                                it.PageX := Round((x + NumGet(rc, 0, "int")) / scale)
                                it.PageY := Round((y + NumGet(rc, 4, "int")) / scale)
                            }
                    }
                }
            }
            try sh.Show("Hide " AxImportGui.SafeShow(w.Show))
            sh.GetClientPos(, , &cw, &ch)
            w.CW := Round(cw / scale), w.CH := Round(ch / scale)
        } catch as e {
            w.CW := 600, w.CH := 400
        }
        try sh.Destroy()
    }
    static ShadowAdd(sh, it, w) {
        type := it.Type, opts := AxImportGui.SafeOpts(it.Opts), text := it.Text
        ; nothing that loads anything: an ActiveX control or a picture stands
        ; in as a text of the same size
        if (type = "activex" || type = "custom" || type = "picture" || type = "pic") {
            if (type = "picture" || type = "pic") && !RegExMatch(opts, "i)(^|\s)w\d") && !RegExMatch(opts, "i)(^|\s)h\d")
                opts .= " w32 h32"
            type := "text", text := ""
        }
        if (type = "statusbar")
            text := ""
        try return sh.Add(type, opts, text)
        try return sh.Add(type, AxImportGui.GeomOpts(opts), (text is Array) ? text : String(text))
        try return sh.Add("text", AxImportGui.GeomOpts(opts), "")
        return ""
    }
    ; no names (two controls may share one there), no owner, no event object
    static SafeOpts(o) => Trim(RegExReplace(String(o), "i)(^|\s)[+]?v\w+", " "))
    static SafeGui(o) => Trim(RegExReplace(String(o), "i)(^|\s)[+-]?(Owner|Parent)\S*", " "))
    static SafeShow(o) => Trim(RegExReplace(String(o), "i)(^|\s)(Minimize|Maximize|Restore|NA|NoActivate|Hide|Center|xCenter|yCenter)\b", " "))
    static GeomOpts(o) {
        out := ""
        for word in StrSplit(o, " ")
            if RegExMatch(word, "i)^([xywh][+-]?(p|m|s)?[+-]?\d*|r\d+|Section)$")
                out .= " " word
        return Trim(out)
    }

    ; ----------------------------------------------------------- the design
    Build(w, win, isMain) {
        root := win.Root
        win.Title := (w.Title != "") ? w.Title : this.Stem
        ; the room the controls are given (AxLayout.SX/SY), AxGui's own title
        ; bar, and the page's padding round them, so a window that fitted
        ; still fits without a scrollbar
        win.Width := Round(Max(w.CW, 160) * AxLayout.SX) + 24
        win.Height := Round(Max(w.CH, 80) * AxLayout.SY) + 32 + 40
        win.Nav := 0
        win.Kind := isMain ? "main" : "window"
        o := " " w.GuiOpts " "
        win.Resizable := RegExMatch(o, "i)\s\+?Resize\b") ? 1 : 0
        win.MaximizeBox := (win.Resizable || RegExMatch(o, "i)\s\+?MaximizeBox\b")) && !RegExMatch(o, "i)\s-MaximizeBox\b") ? 1 : 0
        win.MinimizeBox := RegExMatch(o, "i)\s-MinimizeBox\b") ? 0 : 1
        if RegExMatch(o, "i)\s\+?AlwaysOnTop\b")
            win.AlwaysOnTop := 1
        if RegExMatch(o, "i)\s-Caption\b")
            win.Frame := 0
        base := ""
        for it in w.Items
            if (it.Kind = "font")
                base := AxImportGui.FontStep(base, it.Opts, it.Name)
            else if (it.Kind = "ctl")
                break
        w.BaseFont := base
        ; the window's font, colours and background as the Look page's own
        ; settings, which the canvas and the export both follow
        if (base is Map) {
            if base.Has("name")
                AxTheme.Set(win, "font", base["name"])
            if base.Has("size")
                AxTheme.Set(win, "size", Round(base["size"] * 4 / 3))    ; points, as pixels
            if (base.Has("color") && base["color"] != "")
                AxTheme.Set(win, "fg", base["color"])
        }
        dark := false
        if (w.Back != "") {
            hex := AxGuiCompat.Color(w.Back)
            win.BackColor := LTrim(hex, "#")
            AxTheme.Set(win, "bg", hex)
            if RegExMatch(hex, "^#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})$", &m)
                dark := (0.299 * ("0x" m[1]) + 0.587 * ("0x" m[2]) + 0.114 * ("0x" m[3])) < 128
        }
        win.Theme := dark ? "dark" : "light"
        this.ShowOptsNative(w.Show, win)
        w.Design := win                        ; for its right-click menus (CtxOf)
        if (w.HasOwnProp("MenuBar") && w.MenuBar != "")
            this.MenuBarOf(w, win)
        ; a right-click anywhere that only shows a Menu(): the window's own
        for ev in w.WinEvents
            if (ev.Name = "contextmenu" && (key := this.MenuShowKey(ev.Fn)) != "") {
                this.CtxOf(key, "*", w, win)
                w.Stmts[ev.Stmt] := true
                ev.Done := true
            }

        ; the controls, in the order they were made
        radios := []
        tabs := Map()
        last := ""
        for it in w.Items {
            if (it.Kind != "ctl")
                continue
            if (it.Type = "radio") {
                if (radios.Length && !RegExMatch(it.Opts, "i)(^|\s)\+?Group\b") && IsObject(last) && last.Type = "radio")
                    radios[-1].Push(it)
                else
                    radios.Push([it])
                last := it
                continue
            }
            last := it
            if (it.Type = "updown") {
                it.NodeRef := this.UpDown(it, win)
                continue
            }
            if (it.Type = "statusbar") {
                it.NodeRef := "window"
                win.Status := (it.Text is Array) ? "" : String(it.Text)
                if (win.Status = "")
                    win.Status := "Ready"
                win.Height += 24
                ; SB.SetText("x", 2) is the window's own SetText, which sets
                ; the design's status bar -- so SB is simply the window
                if (isMain && it.Key != "" && !InStr(it.Key, "."))
                    this.Before .= it.Key " := g.AsStatusBar()`n"
                continue
            }
            n := this.Node(it, w, win)
            if IsObject(n) {
                this.Place(n, it, tabs, root, w)
                it.NodeRef := n
                ; a text only known as it runs is given to it where it was made
                if (isMain && it.TextExpr != "") {
                    if (n.Name = "")
                        n.Name := this.P.NewName(AxCat.Get(n.Type).Prefix)
                    c := this.CodeNode("AxGuiCompat.Init(g[" AxLit.S(n.Name) "], " it.TextExpr ")")
                    if (n.Lay("tab", "") != "")
                        c.L["tab"] := n.L["tab"]
                    this.P.Insert(n.Parent, c)
                    this.Park(c)
                }
            }
        }
        for grp in radios {
            n := this.RadioGroup(grp, w, win)
            this.Place(n, grp[1], tabs, root, w)
            for it in grp
                it.NodeRef := n
        }
        if w.Guess.Length {
            lines := ""
            for l in w.Guess
                lines .= (lines = "" ? "" : ", ") l
            this.Notes.Push((isMain ? "" : win.Name ": ") "where it decides as it runs (line " lines "), the design shows the first way"
                . (this.Admin ? " -- elevated, where that is what it asks" : "") ".")
        }
        if (w.Fn >= 0)
            this.Wire(w, win)
        AxLayout.MarkFixed(win)
        AxLayout.ToFixed(win)                          ; placed from the script's own numbers
    }
    ; A node for one native control: its type, name, text and options.
    Node(it, w, win) {
        type := AxImportGui.Types[it.Type]
        if (type = "")
            return ""
        o := " " it.Opts " "
        if (type = "Edit" && RegExMatch(o, "i)\s\+?Password"))
            type := "Password"
        if (type = "Text" && RegExMatch(o, "i)\s\+?0x10\b") && (it.Text = ""))
            type := "Separator"
        e := AxCat.Get(type)
        n := AxNode(type, this.P.NewId())
        n.L["place"] := "flow"
        if RegExMatch(o, "i)\sv(\w+)", &m) && !RegExMatch(m[0], "i)^\s(Vertical|Visible)$")
            n.Name := m[1]
        if (n.Name = "" && it.Key != "" && !InStr(it.Key, "."))
            n.Name := it.Key
        else if (n.Name = "" && it.Key != "")
            n.Name := RegExReplace(it.Key, ".*\.")        ; this.txtGpuName -> txtGpuName
        text := it.Text
        switch type {
        case "Text", "Button", "CheckBox", "Link", "GroupBox", "Edit", "Password", "Hotkey":
            n.Arg := (text is Array) ? "" : String(text)
            if (type = "Text" && RegExMatch(o, "i)\s\+?Center\b"))
                n.P["align"] := "Center"
            else if (type = "Text" && RegExMatch(o, "i)\s\+?Right\b"))
                n.P["align"] := "Right"
            if (type = "Button" && RegExMatch(o, "i)\s\+?Default\b"))
                n.P["kind"] := "Accent"
            if (type = "CheckBox" && RegExMatch(o, "i)\s\+?Checked(1)?\b"))
                n.P["checked"] := 1
            if (type = "Edit") {
                if RegExMatch(o, "i)\sr(\d+)\b", &m) && m[1] > 1
                    n.P["rows"] := m[1]
                else if RegExMatch(o, "i)\s\+?Multi\b") && it.H > 30
                    n.P["rows"] := Max(2, Round(it.H / 17))
                if RegExMatch(o, "i)\s\+?ReadOnly\b")
                    n.P["readonly"] := 1
            }
        case "DDL", "ListBox", "Tab":
            ; Gui's list gives back the chosen item's number as its Value and
            ; its words as its Text: so each item's value is its number
            items := (text is Array) ? text : StrSplit(String(text), "|")
            lines := ""
            for x in items
                if (String(x) != "")
                    lines .= (type = "Tab" ? "" : A_Index ":") StrReplace(String(x), "`n", " ") "`n"
            n.Arg := RTrim(lines, "`n")
            if RegExMatch(o, "i)\sChoose(\d+)\b", &m) && m[1] <= items.Length && type != "Tab"
                n.P["value"] := String(m[1])
            if (type = "ListBox" && RegExMatch(o, "i)\s\+?Multi\b"))
                n.P["multi"] := 1
        case "Slider", "Progress":
            n.Arg := (text = "" ? "0" : String(text))
            if RegExMatch(o, "i)\sRange(-?\d+)-(-?\d+)", &m)
                n.P["min"] := m[1], n.P["max"] := m[2]
            if (type = "Progress" && n.P.Has("min"))
                n.P.Delete("min")
        case "Date", "Calendar":
            n.Arg := ""
        case "Picture":
            src := String(text)
            if (src != "" && !RegExMatch(src, "i)^([a-z]:\\|\\\\|https?:)") && !InStr(src, "*"))
                src := this.Dir "\" src
            n.Arg := src
        case "ListView":
            ; the column titles, then the rows the script added itself
            cols := (text is Array) ? text : StrSplit(String(text), "|")
            Cell := (v) => StrReplace(StrReplace(String(v), "|", "/"), "`n", " ")
            lines := ""
            for c in cols
                lines .= (A_Index = 1 ? "" : " | ") Cell(c)
            for r in it.Rows {
                row := ""
                for v in r.Vals
                    row .= (A_Index = 1 ? "" : " | ") Cell(v)
                lines .= "`n" (r.Check ? "[x] " : "") row
            }
            n.Arg := lines
            if RegExMatch(o, "i)\s\+?Checked\b")
                n.P["checked"] := 1
            if RegExMatch(o, "i)\s-Multi\b")
                n.P["single"] := 1
            if RegExMatch(o, "i)\s\+?Grid\b")
                n.P["grid"] := 1
            if RegExMatch(o, "i)\s\+?NoSortHdr\b")
                n.P["nosorthdr"] := 1
        case "TreeView":
            n.Arg := this.DataTree(it, w)
            if RegExMatch(o, "i)\s\+?Checked\b")
                n.P["checked"] := 1
        case "ActiveX":
            n.Arg := String(text)
        }
        if (it.TextExpr != "")
            this.Notes.Push("Line " it.Line ": " (n.Name != "" ? n.Name : type) "'s text is worked out as it runs (" it.TextExpr "); the design shows it empty, and the program gives it that as it starts.")
        if (RegExMatch(o, "i)\s\+?Disabled\b") || it.Disabled = 1) {
            if (type = "Button")
                n.P["disabled"] := 1
            else
                n.L["opts"] := Trim(n.Lay("opts", "") " Disabled")
        }
        if (RegExMatch(o, "i)\s\+?Hidden\b") || it.Hidden = 1)
            n.L["hidden"] := 1
        ; a value set after it was made: on a check box that is whether it is
        ; ticked, on a list which item is chosen, anywhere else what it says
        if (it.Set != "" && type != "Tab") {
            if (type = "CheckBox" && it.SetProp = "value") {
                if it.Set
                    n.P["checked"] := 1
                else if n.P.Has("checked")
                    n.P.Delete("checked")
            } else if ((type = "DDL" || type = "ListBox") && it.SetProp = "value") {
                lines := StrSplit(n.Arg, "`n")
                if (IsInteger(it.Set) && it.Set >= 1 && it.Set <= lines.Length)
                    n.P["value"] := String(it.Set)
            } else if (type = "DDL" || type = "ListBox") {
                for one in StrSplit(n.Arg, "`n")               ; .Text := "Green": the item that says so
                    if (SubStr(one, InStr(one, ":") + 1) = String(it.Set))
                        n.P["value"] := SubStr(one, 1, InStr(one, ":") - 1)
            }
            else
                n.Arg := String(it.Set)
        }
        style := AxImportGui.FontCss(it.OwnFont is Map ? it.OwnFont : it.Font, w.BaseFont)
        ; a colour of its own: cRed / c00E5FF (and not Center, Checked, Choose2)
        for word in StrSplit(Trim(it.Opts), " ")
            if RegExMatch(word, "i)^\+?c([0-9A-Fa-f]{6}|[A-Za-z]+)$", &m)
                && !RegExMatch(m[1], "i)^(heck|hecked|hoose\d*|enter|aption|lip.*|lass.*)$")
                style .= "color:" AxGuiCompat.Color(m[1]) ";"
        if (style != "")
            n.L["style"] := style
        if it.Guessed
            n.L["tip"] := ""
        this.Handlers(n, it, w)
        this.N.Controls++
        return n
    }
    ; Radio buttons one after another are one group in Gui; here a group is
    ; one control with a line per button.
    RadioGroup(grp, w, win) {
        n := AxNode("Radio", this.P.NewId())
        n.L["place"] := "flow"
        lines := "", val := ""
        x0 := 1e9, y0 := 1e9, x1 := 0, y1 := 0, vertical := true
        for idx, it in grp {
            lines .= idx ":" String(it.Text) "`n"
            if RegExMatch(" " it.Opts " ", "i)\s\+?Checked(1)?\b")
                val := idx
            if (it.X != "") {
                x0 := Min(x0, it.X), y0 := Min(y0, it.Y), x1 := Max(x1, it.X + it.W), y1 := Max(y1, it.Y + it.H)
                if (idx > 1 && Abs(it.X - grp[1].X) > 4)
                    vertical := false
            }
        }
        n.Arg := RTrim(lines, "`n")
        if (val != "")
            n.P["value"] := val
        if (vertical && grp.Length > 1)
            n.P["vertical"] := 1
        first := grp[1]
        if RegExMatch(" " first.Opts " ", "i)\sv(\w+)", &m)
            n.Name := m[1]
        else if (first.Key != "")
            n.Name := RegExReplace(first.Key, ".*\.")
        if (x0 < 1e9)
            first.X := x0, first.Y := y0, first.W := x1 - x0, first.H := y1 - y0
        for it in grp
            for e in it.Events
                if (StrLower(e.Name) = "click")
                    e.Name := "change"
        this.Handlers(n, first, w)
        if (grp.Length > 1)
            this.Notes.Push("Line " first.Line ": " grp.Length " radio buttons became one group" (n.Name != "" ? " (" n.Name ")" : "")
                . "; its Value is the number of the one chosen.")
        this.N.Controls++
        return n
    }
    ; An UpDown gives the Edit before it arrows: that pair is a number box.
    UpDown(it, win) {
        ; the Edit it belongs to was placed just before it
        for n in AxImportGui.AllNodes(win.Root) {
            prev := n
        }
        if !IsSet(prev) || !(prev.Type = "Edit" || prev.Type = "Number")
            return ""
        prev.Type := "Number"
        for k in ["rows", "readonly"]
            if prev.P.Has(k)
                prev.P.Delete(k)
        if RegExMatch(" " it.Opts " ", "i)\sRange(-?\d+)-(-?\d+)", &m)
            prev.P["min"] := m[1], prev.P["max"] := m[2]
        if (it.Text != "" && !(it.Text is Array))
            prev.Arg := String(it.Text)                 ; the UpDown's own number is where it starts
        else if (prev.Arg = "")
            prev.Arg := "0"
        if (it.W != "" && prev.Lay("w", "") != "")
            prev.L["w"] := prev.L["w"] + it.W
        return prev
    }
    static NeedsWidth(n) {
        switch n.Type {
        case "Edit", "Password", "Number", "DDL", "ListBox", "Slider", "Progress", "GroupBox", "Tab",
             "DataView", "ListView", "TreeView", "Date", "Calendar", "Hotkey", "Picture", "ActiveX", "Separator":
            return true
        }
        return false
    }
    static AllNodes(root) {
        out := []
        for k in root.Kids {
            out.Push(k)
            for x in AxImportGui.AllNodes(k)
                out.Push(x)
        }
        return out
    }
    ; Fixed where Windows put it; on its tab when it is on one.
    Place(n, it, tabs, root, w) {
        parent := root
        dx := 0, dy := 0
        if IsObject(it.Tab) && it.TabIdx >= 1 && tabs.Has(it.Tab) {
            parent := tabs[it.Tab]
            n.L["tab"] := it.TabIdx
            ; inside a tab the page it sits on is the reference
            dx := (it.Tab.PageX != "") ? it.Tab.PageX : it.Tab.X + 4
            dy := (it.Tab.PageY != "") ? it.Tab.PageY : it.Tab.Y + 28
        }
        if (it.X != "") {
            n.L["place"] := "abs"
            n.L["x"] := Max(0, it.X - dx), n.L["y"] := Max(0, it.Y - dy)
            ; a width the script gave, or one a control has no size without;
            ; a label or a button the script let size itself sizes itself here
            if (RegExMatch(" " it.Opts " ", "i)\sw\d") || AxImportGui.NeedsWidth(n)) && it.W > 0
                n.L["w"] := it.W
            if (it.H > 0 && AxLayout.KeepsHeight(n))
                n.L["h"] := it.H
        }
        this.P.Insert(parent, n)
        if (n.Type = "Tab")
            tabs[it] := n
    }

    ; --------------------------------------------------------- the menu bar
    ; Gui's MenuBar, as the design's own menu bar text: one menu a line, its
    ; items indented under it, each "label | shortcut | what it does". A menu
    ; item called its function with (ItemName, ItemPos, MyMenu), and that is
    ; what the design's item passes it.
    MenuBarOf(w, win) {
        win.Menus := RTrim(this.MenuText(w.MenuBar, 0, Map()), "`n")
        win.Height += 30
        used := Map()
        this.MenusUsed(w.MenuBar, used)
        for key in used
            for st in this.MenuObj[key].Stmts
                if st.Top
                    w.Stmts[st.I] := true
        ms := w.MenuStmt
        if (w.Fn >= 0) {
            ; built in a class: the design has the bar, so the class's own
            ; is kept aside instead of replacing it
            if !this.HasOwnProp("Edits")
                this.Edits := []
            this.Edits.Push({S: this.T.Start(ms.Left), E: this.T.End(ms.Left), T: w.Key ".MenuBarObject"})
        } else if ms.Top
            w.Stmts[ms.I] := true
    }
    ; The Menu() a handler does nothing but show: (*) => m.Show(), or a
    ; function whose whole body is m.Show(...). "" when it does anything else,
    ; or when something else is done to the menu (it stays code then).
    MenuShowKey(fn) {
        t := this.T
        body := ""
        ty := t.Type(fn)
        if (ty = "FatArrow")
            body := this.Text(t.Next(t.FirstChild(fn)))
        else if (ty = "Identifier") {
            nm := t.Value(fn)
            for i in t.Children(0)
                if (t.Type(i) = "Method" && t.Value(i) = nm)
                    body := RegExMatch(this.Text(i), "s)\{\s*(.*?)\s*\}\s*$", &mm) ? mm[1] : ""
        }
        body := Trim(body, " `t`r`n")
        if RegExMatch(body, "s)^\((.*)\)$", &w1)          ; (m.Show()) -- a bracketed body
            body := Trim(w1[1])
        if !RegExMatch(body, "i)^(\w+)\.Show\([^()]*\)$", &m)
            return ""
        return (this.MenuObj.Has(m[1]) && !this.MenuObj[m[1]].HasOwnProp("Other") && !this.MenuObj[m[1]].Bar) ? m[1] : ""
    }
    ; ... as one of the design window's right-click menus, opening on `on`
    CtxOf(key, on, w, win) {
        name := AxProject.CleanName(key)
        body := RTrim(this.MenuText(key, 1, Map()), "`n")
        win.Ctx := RTrim(String(win.Ctx), "`r`n") (Trim(String(win.Ctx)) = "" ? "" : "`n") name " | " on (body != "" ? "`n" body : "")
        used := Map()
        this.MenusUsed(key, used)
        for k in used
            for st in this.MenuObj[k].Stmts
                if st.Top
                    w.Stmts[st.I] := true
        this.Notes.Push("The right-click menu " key " (on " (on = "*" ? "the window" : on) ") is in Logic > Menus now.")
    }
    MenusUsed(key, used) {
        if used.Has(key) || !this.MenuObj.Has(key)
            return
        used[key] := true
        for it in this.MenuObj[key].Items
            if it.HasOwnProp("Sub")
                this.MenusUsed(it.Sub, used)
    }
    MenuText(key, depth, seen) {
        if seen.Has(key) || !this.MenuObj.Has(key)
            return ""
        seen[key] := true
        pad := "", out := ""
        loop depth
            pad .= "    "
        for it in this.MenuObj[key].Items {
            if it.HasOwnProp("Sep") {
                out .= pad "-`n"
                continue
            }
            parts := StrSplit(it.Label, "`t", , 2)
            label := StrReplace(parts[1], "|", "/"), keys := (parts.Length > 1) ? parts[2] : ""
            if it.HasOwnProp("Sub") {
                out .= pad label "`n" this.MenuText(it.Sub, depth + 1, seen)
                continue
            }
            code := (it.Fn >= 0) ? this.MenuAction(it.Fn, it.Label, it.Pos) : ""
            out .= pad label (keys != "" || code != "" ? " | " keys " | " code : "") "`n"
        }
        return out
    }
    ; one line of code for the item: a function called as Gui's menu called it
    MenuAction(fn, label, pos) {
        t := this.T
        if (t.Type(fn) = "Identifier") {
            nm := t.Value(fn)
            for i in t.Children(0)
                if (t.Type(i) = "Method" && t.Value(i) = nm) {
                    ps := this.Kids(t.FirstChild(i))
                    return nm (ps.Length ? "(" AxLit.S(label) ", " pos ', "")' : "()")
                }
            return nm "(" AxLit.S(label) ", " pos ', "")'
        }
        code := this.Pass(fn, [AxLit.S(label), pos, '""'])
        if !InStr(code, "`n")
            return RegExReplace(code, "^return\s+")
        ; several lines: one expression of them, in order
        parts := ""
        for ln in StrSplit(code, "`n")
            if (Trim(ln) != "")
                parts .= (parts = "" ? "" : ", ") RegExReplace(Trim(ln), "^return\s+")
        return "(" parts ")"
    }

    ; ------------------------------------------------ a window built in code
    ; A window a function or class builds is made from the design instead:
    ; its Gui() becomes Make<Name>(), which hands back the design's window,
    ; and each Add...() it made becomes that window's control of the same
    ; name. Everything else in the function -- its handlers on this.Refresh,
    ; its this.txtTemp.Text := ..., Show() -- stays exactly as written and
    ; runs against the design's window (lib\AxGui.Compat.ahk speaks Gui).
    Wire(w, win) {
        t := this.T
        win.Kind := "code", win.ExitOnClose := 0
        if !this.HasOwnProp("Edits")
            this.Edits := []
        for n in AxImportGui.AllNodes(win.Root)
            if (n.Name = "")
                n.Name := this.P.NewName(AxCat.Has(n.Type) ? AxCat.Get(n.Type).Prefix : "ctl")
        r := t.Next(t.FirstChild(w.Stmt))
        ; Gui(opts, title, this): the handlers it names are that object's
        this.Edits.Push({S: t.Start(r), E: t.End(r),
            T: AxGen.Fn(win) "()" (w.EventObj ? ".EventSink(" w.SinkText ")" : "")})
        made := 0
        for it in w.Items {
            if (it.Kind != "ctl" || !it.HasOwnProp("Call") || it.NodeRef = "")
                continue
            ref := (it.NodeRef = "window") ? w.Key ".AsStatusBar()" : w.Key "[" AxLit.S(it.NodeRef.Name) "]"
            ; its text was an expression: the control is given it as it runs
            if (it.TextExpr != "" && it.NodeRef != "window")
                ref := "AxGuiCompat.Init(" ref ", " it.TextExpr ")"
            this.Edits.Push({S: t.Start(it.Call), E: t.End(it.Call), T: ref})
            made++
        }
        this.Notes.Push(win.Name ": " (w.Cls != "" ? w.Cls "." : "") t.Value(w.Fn) "() now makes its window from the design --"
            . " its Gui() is " AxGen.Fn(win) "(), and its " made " Add...() calls are the design's controls."
            . " The rest of it is as it was.")
    }
    ; The script's own text between two places, with the design's edits in it.
    Patched(from, to) {
        s := "", at := from
        if this.HasOwnProp("Edits") {
            list := []
            for e in this.Edits
                if (e.S >= from && e.E <= to)
                    list.Push(e)
            AxLayout.Sort(list, (a, b) => a.S - b.S)
            for e in list {
                if (e.S < at)
                    continue                            ; inside one already made
                s .= SubStr(this.Src, at + 1, e.S - at) e.T
                at := e.E
            }
        }
        return s SubStr(this.Src, at + 1, to - at)
    }
    ToScript(text, from, to) {
        if this.HasOwnProp("Edits")
            text := AxImport.NoCompilerLines(this.Patched(from, to))
        return super.ToScript(text, from, to)
    }

    ; ------------------------------------------------------------- handlers
    ; For a window made at the top of the script: its handlers, as the
    ; design's own (or its rules, when they are that simple).
    Handlers(n, it, w) {
        if (w.Fn >= 0)
            return
        e := AxCat.Get(n.Type)
        for ev in it.Events {
            ; a right-click that only shows a Menu(): the control's right-click
            ; menu (Logic > Menus), not a handler
            if (ev.Name = "contextmenu" && (key := this.MenuShowKey(ev.Fn)) != "") {
                if (n.Name = "")
                    n.Name := this.P.NewName(e.Prefix)
                this.CtxOf(key, n.Name, w, w.HasOwnProp("Design") ? w.Design : this.W)
                continue
            }
            name := AxImportGui.Events.Has(ev.Name) ? AxImportGui.Events[ev.Name] : ""
            ok := false
            for x in e.Events
                if (x = name)
                    ok := true
            if !ok {
                this.Notes.Push("Line " it.Line ": the " ev.Name " event of " (n.Name != "" ? n.Name : n.Type)
                    . " has no match in the design; its code is kept in the script but no longer called.")
                continue
            }
            if (n.Name = "")
                n.Name := this.P.NewName(e.Prefix)
            ; Gui calls a handler (ctl, info); the design's handler has ctl
            ; first too, and the info a Gui handler reads is not there
            code := this.NativeHandler(ev.Fn, AxImportGui.InfoArgs(n.Type, name), w)
            n.Ev.Push(Map("name", name, "code", code))
            this.N.Events++
        }
    }
    NativeHandler(fn, args := "", w := "") {
        t := this.T
        if !IsObject(args)
            args := ["ctl", '""']
        list := ""
        for a in args
            list .= (A_Index = 1 ? "" : ", ") a
        ty := t.Type(fn)
        if (ty = "String") {
            ; Gui(, , obj) and a method of obj named: obj.Method(ctl, info)
            nm := AxImport.Unq(t.Value(fn), &ok)
            sink := (IsObject(w) && w.HasOwnProp("SinkText")) ? w.SinkText : ""
            if (sink != "" && RegExMatch(sink, "^[\w.]+$"))
                return sink "." nm "(" list ")"
            return "AxGuiCompat.Named(ctl.Gui, " AxLit.S(nm) ")(" list ")"
        }
        if (ty = "Identifier")
            return t.Value(fn) "(" list ")"
        if (ty = "FatArrow") {
            pad := args.Clone()
            while (pad.Length < 5)
                pad.Push(pad.Length < 3 ? '""' : "0")
            code := this.Arrow(fn, pad)
            if (code != "")
                return code
        }
        return "axFn := " AxImport.Tidy(this.Text(fn)) "`naxFn(" list ")"
    }
    ; What Gui handed a handler, as the design's handler has it: a list's
    ; and a tree's events carry the row or the item; the rest carried
    ; nothing the design's handler has
    static InfoArgs(type, ev) {
        if (type != "ListView" && type != "TreeView")
            return ["ctl", '""']
        switch ev {
        case "Click", "DoubleClick": return ["ctl", "ev"]
        case "ContextMenu":          return ["ctl", "ev", "el", "0", "0"]
        case "ItemSelect":           return (type = "TreeView") ? ["ctl", "item"] : ["ctl", "item", "selected"]
        case "ItemCheck":            return ["ctl", "item", "checked"]
        case "ItemExpand":           return ["ctl", "item", "expanded"]
        case "ItemFocus":            return ["ctl", "item"]
        case "ColClick":             return ["ctl", "column"]
        }
        return ["ctl", '""']
    }

    ; ------------------------------------------------------ the rest of it
    ; The walk over the top of the script, for the window made there: what
    ; the design now does is dropped, the rest kept where it ran.
    Top(i) {
        if (IsObject(this.Main) && this.T.Type(i) != "Comment" && this.Taken(i)) {
            this.Lead := -1
            return
        }
        return super.Top(i)
    }
    Taken(i) {
        m := this.Main
        if (i = m.Stmt) {
            this.Gv := m.Key
            k := this.Gv
            if (k != "g")
                this.Before := k " := g`n" this.Before
            if m.EventObj                                  ; after whatever makes the object
                this.Before .= "g.EventSink(" m.SinkText ")`n"
            return true
        }
        if (i = m.ShowStmt) {
            this.Shown := true
            return true
        }
        if m.Stmts.Has(i)
            return true
        for ev in m.WinEvents
            if (ev.Stmt = i)
                return this.WinEvent(ev)
        ; an elevation block the design's own setting now does
        if (this.T.Type(i) = "If" && this.Admin && RegExMatch(this.Text(i), "i)\*RunAs") && InStr(this.Text(i), "A_IsAdmin"))
            return true
        return false
    }
    Window(i) => false
    Ui(i) => false
    WinEvent(ev) {
        t := this.T
        body := (t.Type(ev.Fn) = "FatArrow") ? this.Text(t.Next(t.FirstChild(ev.Fn))) : ""
        if ev.HasOwnProp("Done")                     ; the window's right-click menu now
            return true
        if (ev.Name = "close" && RegExMatch(body, "i)^\(?\s*ExitApp\(?\)?\s*\)?$")) {
            this.W.ExitOnClose := 1
            return true
        }
        if (ev.Name = "escape" && RegExMatch(body, "i)^\(?\s*(ExitApp\(?\)?|\w+\.(Hide|Destroy)\(\))\s*\)?$")) {
            this.W.EscapeCloses := 1
            return true
        }
        return false
    }
    ; A code block in a window of fixed places has no place among them: it is
    ; kept off the canvas (the Outline lists it, with its eye to show it) and
    ; runs where it ran all the same.
    Park(n) {
        n.L["dhide"] := 1
    }
    ShowOptsNative(v, win) {
        v := String(v)
        if RegExMatch(v, "i)(^|\s)x(-?\d+)", &m)
            win.WinX := m[2] + 0, win.StartPos := "xy"
        if RegExMatch(v, "i)(^|\s)y(-?\d+)", &m)
            win.WinY := m[2] + 0, win.StartPos := "xy"
        if RegExMatch(v, "i)\bMaximize\b")
            win.StartState := "max"
        else if RegExMatch(v, "i)\bMinimize\b")
            win.StartState := "min"
        else if RegExMatch(v, "i)\bHide\b")
            win.StartState := "hidden"
        if RegExMatch(v, "i)\b(NA|NoActivate)\b")
            win.NoActivate := 1
    }
}
