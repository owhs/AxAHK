#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\AxStudio.Gen.ahk
#Include %A_LineFile%\..\AxStudio.Flow.ahk
#Include %A_LineFile%\..\AxStudio.Host.ahk
#Include %A_LineFile%\..\AxStudio.Import.ahk
#Include %A_LineFile%\..\AxStudio.StepsUi.ahk

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
;  AxStudio.Map.ahk -- the whole program as a map: what starts things, what
;  they do, what that calls, and what it reads and writes.
;
;  Not a drawing of the design: a reading of the program. The script the
;  export would write is parsed (bin\AstHost.exe) and walked, so the map has
;  the rules, the handlers, your own functions and your classes' methods --
;  whatever the code really calls, not what anything claims.
;
;      When   a control's event, a rule's trigger, a hotkey, a timer, a
;             message, the program starting
;      Does   what those run first: a handler, a rule, a method
;      Uses   what that calls in turn
;      Data   the values and controls it all reads (dotted) and writes
;
;  Drawn by AXM in AxStudio.Map.js. Clicking a node keeps it and what it
;  touches in view and fogs the rest; the lines in and out stay, so it is
;  plain where a value comes from and where it goes. Double-click opens it.
; =============================================================================
class AxMap {
    static Key := ""            ; the project as it was when the map was read
    static Json := ""           ; ... and the map read from it
    static Go := Map()          ; node id -> where double-clicking it goes
    static Problem := ""

    ; ------------------------------------------------------------- the page
    ; The whole program: what starts what, what reads and writes what. One
    ; piece of it as a flowchart is the Steps workspace (AxStudio.StepsUi.ahk),
    ; which a card opens.
    static Page(s) {
        h := '<div class="axm">'
           . '<div class="axm-bar">'
           .   '<span class="axm-ponly">'
           .   '<input id="axmFind" class="axd-rfindbox axm-find" autocomplete="off" placeholder="Find -- a control, a function, a value">'
           .   '<span class="axm-chip on" data-mlane="0" data-tip="What starts things: events, rules, hotkeys, timers">When</span>'
           .   '<span class="axm-chip on" data-mlane="1" data-tip="What they run first">Does</span>'
           .   '<span class="axm-chip on" data-mlane="2" data-tip="What that calls in turn">Uses</span>'
           .   '<span class="axm-chip on" data-mlane="3" data-tip="Values and controls read and written">Data</span>'
           .   '<span class="axm-sep"></span>'
           .   '<span class="axm-btn" data-mdo="out" data-tip="Smaller">&#x2212;</span>'
           .   '<span class="axm-btn" data-mdo="in" data-tip="Bigger">+</span>'
           .   '<span class="axm-btn" data-mdo="fit" data-tip="All of it in view">Fit</span>'
           .   '<span class="axm-btn" data-mdo="clear" data-tip="Nothing picked, nothing filtered (Esc)">Clear</span>'
           .   '</span>'
           .   '<span class="axm-count" id="axmCount"></span>'
           .   '<span class="axm-btn axm-ponly" data-mdo="rebuild" data-tip="Read the program again">Read again</span>'
           . '</div>'
           . '<div class="axm-body">'
           .   '<div id="axmView"><div id="axmPlane"><svg id="axmSvg" xmlns="http://www.w3.org/2000/svg"></svg>'
           .     '<div id="axmNodes"></div></div></div>'
           .   '<div id="axmInfo"><div class="axm-hint">Click anything to keep it and what it touches in view; '
           .     'the rest goes to fog, and the lines in and out stay. Double-click to open it. Type to find.</div></div>'
           . '</div></div>'
        return h
    }
    ; Kept for the places that still say "the map, step by step": that is
    ; the Steps workspace now.
    static SetMode(s, mode) {
        if (mode = "steps")
            return (s.Ws = "steps") ? AxStepsUi.Paint(s) : s.SetWs("steps")
        s.SetWs("map")
    }
    ; Drawn after the page is: the map from the program as it is now.
    static Paint(s, force := false, fresh := true) {
        key := s.P.Json("")
        read := false
        if (force || key != AxMap.Key || AxMap.Json = "") {
            read := true
            AxMap.Key := key
            try AxMap.Json := AxMap.Build(s.P)
            catch as e {
                AxMap.Json := ""
                AxMap.Problem := e.Message
            }
        }
        if (AxMap.Json = "")
            return s.Html("axmInfo", '<div class="axm-hint">The map could not be read: ' AxTags.E(AxMap.Problem) '</div>')
        if (read || fresh)
            try s.Js("AXM.load(" AxMap.Json ");")
    }

    ; ------------------------------------------------------------- reading
    static Build(p) {
        path := A_Temp "\axstudio_map.ahk"
        code := AxGen.Script(p, path, "")
        t := AxHost.TreeText(code)
        g := AxMapGraph(p, t, code)
        g.Run()
        AxMap.Go := g.Go
        j := g.ToJson()
        AxMap.Nodes := g.Pcs
        return j
    }
    static Nodes := Map()

    ; ---------------------------------------------------------- connecting
    ; A line dragged from card a to card b: what it can mean, from what the
    ; two are, asked in one form -- then written the no-code way where there
    ; is one (a rule, a binding) and as a step of a flowchart where not.
    static Connect(s, a, b) {
        na := AxMap.Nodes.Has(a) ? AxMap.Nodes[a] : "", nb := AxMap.Nodes.Has(b) ? AxMap.Nodes[b] : ""
        if !IsObject(na) || !IsObject(nb)
            return
        opts := [], ev := "", ctl := ""
        ; what starts it: a control's event is a rule; code of its own, a step
        if RegExMatch(a, "^ev:([^:]+):(\w+)$", &m) {
            n := s.P.Find(m[1])
            ctl := IsObject(n) ? n.Name : m[1], ev := m[2]
        }
        bn := RegExReplace(b, "^\w+:")
        if (ctl != "") {
            if (SubStr(b, 1, 3) = "fn:" && !InStr(bn, "."))
                opts.Push({V: "rule|call " bn, L: "Call " bn "()", Icon: "E945", Desc: "A rule: when " ctl " " StrLower(ev) "s, " bn " runs. No code."})
            if (SubStr(b, 1, 4) = "ctl:") {
                for v in [["show", "Show it"], ["hide", "Hide it"], ["enable", "Let it be used"], ["disable", "Grey it out"]]
                    opts.Push({V: "rule|" v[1] " " bn, L: v[2], Icon: "E945", Desc: "A rule: " ctl " " StrLower(ev) " -> " v[1] " " bn "."})
                opts.Push({V: "ruleval|set " bn, L: "Set what it holds...", Icon: "E945", Desc: "A rule, with the value you give below."})
                opts.Push({V: "rule|copy " ctl " " bn, L: "Copy " ctl " into it", Icon: "E945", Desc: "A rule: what " ctl " holds goes into " bn "."})
            }
            if (SubStr(b, 1, 4) = "var:")
                opts.Push({V: "ruleval|assign " bn, L: "Set " bn " to...", Icon: "E945", Desc: "A rule, with the value you give below."})
            if (SubStr(b, 1, 4) = "win:")
                opts.Push({V: "rule|open " bn, L: "Open " bn, Icon: "E945", Desc: "A rule: the window opens."})
        }
        if (na.Pc != "") {
            if (SubStr(b, 1, 3) = "fn:")
                opts.Push({V: "step|" bn "()", L: "Add a step: do " bn "()", Icon: "E8FD", Desc: "At the end of " na.Label "'s steps."})
            if (SubStr(b, 1, 4) = "var:")
                opts.Push({V: "stepval|" bn " := ", L: "Add a step: set " bn " to...", Icon: "E8FD", Desc: "At the end of " na.Label "'s steps."})
            if (SubStr(b, 1, 4) = "ctl:")
                opts.Push({V: "stepval|" bn ".Text := ", L: "Add a step: set " bn "'s text to...", Icon: "E8FD", Desc: "At the end of " na.Label "'s steps."})
            if (SubStr(b, 1, 4) = "win:")
                opts.Push({V: "step|Show" AxProject.CleanName(bn) "()", L: "Add a step: open " bn, Icon: "E8FD", Desc: "At the end of " na.Label "'s steps."})
        }
        ; a control and a value: kept in step
        cv := (SubStr(a, 1, 4) = "ctl:" && SubStr(b, 1, 4) = "var:") ? [RegExReplace(a, "^ctl:"), bn]
            : (SubStr(a, 1, 4) = "var:" && SubStr(b, 1, 4) = "ctl:") ? [bn, RegExReplace(a, "^var:")] : ""
        if IsObject(cv) {
            opts.Push({V: "bind|" cv[1] " <-> " cv[2], L: "Keep them the same, both ways", Icon: "E8C8", Desc: "A binding: change either and the other follows."})
            opts.Push({V: "bind|" cv[1] " <- " cv[2], L: cv[1] " shows " cv[2], Icon: "E8C8", Desc: "A binding: the control follows the value."})
        }
        if !opts.Length
            return s.Status("msg", "Nothing to make of a line from " na.Label " to " nb.Label
                . " -- try a control's event onto a function, a control or a value; or a control onto a value.")
        r := AxForm.Show(s, {Title: "Connect " na.Label " to " nb.Label, Icon: "E71B", Width: 600,
            Intro: "What should the line mean?",
            Fields: [{Id: "how", Kind: "pick", L: "", V: opts[1].V, Items: opts, Tiles: opts.Length > 4},
                     {Id: "val", L: "Value", Kind: "text", V: "", Ph: "text, a number, or {box} for what a control holds",
                      When: (V) => InStr(V["how"], "val|")}],
            Buttons: ["Connect them", "Cancel"]})
        if !r.Ok
            return
        p := StrSplit(r.V["how"], "|", , 2), what := p[2], val := Trim(r.V["val"])
        s.Mark()
        switch p[1] {
        case "rule", "ruleval":
            n := s.P.FindByName(ctl)
            if IsObject(n)
                s.P.Cur := s.P.WinIndex(s.P.WinOf(n))
            s.PutLine("Flows", "", ctl " " ev " -> " what (p[1] = "ruleval" ? " " val : ""), false)
            s.Status("msg", "A rule: when " ctl " " StrLower(ev) "s, " what (p[1] = "ruleval" ? " " val : "") ". (Logic > Rules)")
        case "step", "stepval":
            pc := AxSteps.FromKey(na.Pc)
            M := AxSteps.Read(s, pc)
            if !IsObject(M)
                return s.Alert("Its code does not read as AutoHotkey yet: " AxSteps.Problem, "Connect")
            code := what (p[1] = "stepval" ? AxFlow.V(val) : "")
            AxSteps.Put(s, pc, AxStepsEdit.Insert(M, "root", M.Lists["root"].Items.Length, code))
            s.Status("msg", "A step at the end of " na.Label ": " code)
        case "bind":
            s.P.Binds := Trim(String(s.P.Binds) "`n" what, "`r`n")
            s.Status("msg", "Bound: " what ". (Logic > Bindings)")
        }
        s.QueueLive()
        AxMap.Paint(s, true)
    }

    ; A step at the end of a card's piece, from the map: the flowchart's own
    ; form, and the map read again -- nothing else moves.
    static AddStep(s, key) {
        pc := AxSteps.FromKey(key)
        if !IsObject(pc)
            return
        AxSteps.Pc := pc, AxSteps.Sel := ""
        M := AxSteps.Read(s, pc)
        if !IsObject(M) || !M.Lists.Has("root")
            return s.Status("msg", "That piece does not read as steps: " AxSteps.Problem)
        AxStepsUi.Add(s, "root", M.Lists["root"].Items.Length)
        AxMap.Paint(s, true)
    }
    ; A rule for a control's event, from the map: the wizard, filled in.
    static Rule(s, id) {
        if !RegExMatch(id, "^ev:([^:]+):(\w+)$", &m)
            return
        n := s.P.Find(m[1])
        if !IsObject(n) || n.Name = ""
            return
        s.P.Cur := s.P.WinIndex(s.P.WinOf(n))
        s.LogicSec := "rules"
        AxWiz.Flow(s, "", {Ctl: n.Name, Ev: m[2]})
    }

    ; ------------------------------------------------------------ opening
    static Open(s, id) {
        if !AxMap.Go.Has(id)
            return
        go := AxMap.Go[id]
        switch go.K {
        case "event":
            n := s.P.Find(go.Node)
            if !IsObject(n)
                return
            s.P.Cur := s.P.WinIndex(s.P.WinOf(n))
            for i, e in n.Ev
                if (e["name"] = go.Ev)
                    return s.EditEvent(n, i)
            return s.GoToNode(n.Id)
        case "node":
            return s.GoToNode(go.Node)
        case "rules":
            return s.GoSec("rules", "logic")
        case "lib":
            AxPkgUi.Sel := go.Name
            return s.GoSec("libraries", "app")
        case "logic":
            return s.GoSec(go.Sec, "logic")
        case "window":
            s.P.Cur := go.Win, s.PageId := "", s.SelIds := []
            return s.SetWs("design")
        case "script":
            s.P.Cur := go.Win
            s.EditScript(go.Part)
            try s.Ce.Select(go.At)
        }
    }
}

; One reading of the program into nodes and lines.
class AxMapGraph {
    __New(p, t, src) {
        this.P := p, this.T := t, this.Src := src
        this.Nodes := Map(), this.Order := []
        this.Edges := [], this.Seen := Map()
        this.Go := Map()
        this.Fns := Map(), this.Fns.CaseSense := false       ; name -> tree index (functions)
        this.Meths := Map(), this.Meths.CaseSense := false   ; Class.Name -> tree index
        this.Globals := Map(), this.Globals.CaseSense := false
        this.Ctls := Map(), this.Ctls.CaseSense := false     ; control variable -> design node
        this.Handlers := Map(), this.Handlers.CaseSense := false   ; handler fn -> {Node, Ev}
        this.Wins := Map(), this.Wins.CaseSense := false     ; Show/Make fn -> window index
        this.Props := Map()                                  ; Class.prop -> Map(method -> "r"|"w")
        this.Plumbing := Map(), this.Plumbing.CaseSense := false   ; the studio's own functions
        this.WinVars := Map(), this.WinVars.CaseSense := false
        ; what the libraries the script includes offer: a function or a class
        ; name -> the library (App > Libraries), so a call into one is on the map
        this.LibFns := Map(), this.LibFns.CaseSense := false
        this.LibCls := Map(), this.LibCls.CaseSense := false
        dir := AxPkg.ProjDir(p)
        if (dir != "")
            for lib in AxPkg.Needed(p)
                for it in AxPkg.Api(dir, lib)
                    if (it.Kind = "function")
                        this.LibFns[it.Name] := lib
                    else if (it.Kind = "class")
                        this.LibCls[it.Name] := lib
    }
    ; a call into a library: one node for what is called, under the library
    LibCall(from, label, lib) {
        id := "lib:" label
        this.Add(id, 2, "library", label, lib, 0, {K: "lib", Name: lib})
        this.Edge(from, id, "call")
    }

    Run() {
        t := this.T, p := this.P
        ; what the design knows: handlers, windows, controls
        for wi, w in p.Wins {
            this.Plumbing[AxGen.InitFn(w)] := true
            this.Plumbing[AxFlow.StateFn(w)] := true
            this.WinVars[w.Var] := true
            if (w.Kind != "main")
                this.Wins[AxGen.Fn(w)] := wi
            for n in AxImport.Nodes(w.Root) {
                if (n.Name != "")
                    this.Ctls[AxProject.CleanName(n.Name)] := n
                for e in n.Ev
                    this.Handlers[AxGen.HandlerName(n, e["name"])] := {Node: n, Ev: e["name"], Win: wi}
            }
        }
        ; the program's own functions, classes and globals
        for i in t.Children(0) {
            switch t.Type(i) {
            case "Method":
                this.Fns[t.Value(i)] := i
            case "Class":
                this.ClassMethods(i, t.Value(i))
            case "BinaryExpr":
                if t.Has(i, "assign") {
                    l := t.FirstChild(i)
                    if (t.Type(l) = "Identifier")
                        this.Globals[t.Value(l)] := true
                }
            }
        }
        ; what starts things
        for wi, w in p.Wins {
            for n in AxImport.Nodes(w.Root)
                for e in n.Ev
                    this.Trigger("ev:" n.Id ":" e["name"], n.Name != "" ? n.Name : n.Type, e["name"], wi,
                        {K: "event", Node: n.Id, Ev: e["name"]}, AxGen.HandlerName(n, e["name"]))
            for pair in AxFlow.Pairs(w) {
                n := p.FindByName(pair.Ctl)
                ; a rule with no code of its own beside it: the handler the
                ; export writes only calls the rule, so the rule stands for it
                if IsObject(n) {
                    hn := AxGen.HandlerName(n, pair.Ev)
                    if !this.Handlers.Has(hn)
                        this.Plumbing[hn] := true
                }
                rules := ""
                for f in AxFlow.For(w, pair.Ctl, pair.Ev)
                    rules .= (rules = "" ? "" : ", ") f.Verb (f.Arg != "" ? " " f.Arg : "")
                fn := AxFlow.FnName(w, pair.Ctl, pair.Ev)
                id := "ev:" (IsObject(n) ? n.Id : pair.Ctl) ":" pair.Ev
                this.Trigger(id, pair.Ctl, pair.Ev, wi, {K: "rules"}, "")
                this.Add("fn:" fn, 1, "rule", pair.Ctl " " pair.Ev, rules, wi, {K: "rules"})
                this.Edge(id, "fn:" fn, "trig")
            }
        }
        ; top-level code: hotkeys, the program starting, timers and messages set up there
        start := false
        for i in t.Children(0) {
            ty := t.Type(i)
            if (ty = "Hotkey" || ty = "Hotstring") {
                id := "hk:" t.StartLine(i)
                this.Add(id, 0, "hotkey", t.Value(i), (ty = "Hotkey" ? "hotkey" : "hotstring"), 0,
                    this.ScriptGo(t.Start(i)))
                this.Body(i, id, "")
            } else if (ty != "Method" && ty != "Class" && ty != "Comment" && ty != "Directive") {
                if !start
                    this.Add("start", 0, "start", "When it starts", "the program's first lines", 0, {K: "logic", Sec: "values"}), start := true
                this.Body(i, "start", "")
            }
        }
        for name, i in this.Fns
            this.Function(i, name, "")
        for name, i in this.Meths {
            cls := SubStr(name, 1, InStr(name, ".") - 1)
            this.Function(i, name, cls)
        }
        this.SharedProps()
        this.Lanes()
    }
    ClassMethods(cls, name) {
        t := this.T
        for m in t.Children(cls) {
            if (t.Type(m) = "Method")
                this.Meths[name "." t.Value(m)] := m
            else if (t.Type(m) = "Class")
                this.ClassMethods(m, t.Value(m))
        }
    }

    ; ---------------------------------------------------------------- nodes
    Add(id, lane, kind, label, sub, win, go) {
        if this.Nodes.Has(id)
            return this.Nodes[id]
        n := {id: id, lane: lane, kind: kind, label: label, sub: sub, win: win, code: ""}
        this.Nodes[id] := n, this.Order.Push(n)
        if IsObject(go)
            this.Go[id] := go
        return n
    }
    Edge(a, b, k) {
        key := a ">" b ">" k
        if (a = b || this.Seen.Has(key))
            return
        this.Seen[key] := true
        this.Edges.Push({a: a, b: b, k: k})
    }
    Trigger(id, label, sub, win, go, fn) {
        this.Add(id, 0, "event", label, sub, win, go)
        if (fn != "")
            this.Edge(id, "fn:" fn, "trig")
    }
    ; the node for something called: a function, a method, a window
    Callee(name, cls := "") {
        if this.Wins.Has(name) {
            wi := this.Wins[name], w := this.P.Wins[wi]
            this.Add("win:" w.Name, 1, "window", w.Name, "opens a window", wi, {K: "window", Win: wi})
            return "win:" w.Name
        }
        if (cls != "" && this.Meths.Has(cls "." name))
            return "fn:" cls "." name
        if this.Fns.Has(name)
            return "fn:" name
        return ""
    }

    ; One function or method: the node, and everything its body touches.
    Function(i, name, cls) {
        t := this.T
        if (cls = "" && !this.Handlers.Has(name) && (SubStr(name, 1, 2) = "Ax" || this.Plumbing.Has(name)))
            return
        if (cls = "" && this.Wins.Has(name))
            return                                          ; a window's builder: the window node stands for it
        id := "fn:" name
        if this.Handlers.Has(name) {
            h := this.Handlers[name]
            n := this.Add(id, 1, "handler", h.Node.Name != "" ? h.Node.Name : h.Node.Type, h.Ev " handler", h.Win,
                {K: "event", Node: h.Node.Id, Ev: h.Ev})
        } else if (SubStr(name, 1, 5) = "Flow_") {
            n := this.Add(id, 1, "rule", SubStr(name, 6), "rules", 0, {K: "rules"})
        } else if (cls != "") {
            n := this.Add(id, 2, "method", SubStr(name, InStr(name, ".") + 1), cls, 0, this.ScriptGo(t.Start(i)))
        } else {
            n := this.Add(id, 2, "function", name, "function", 0, this.ScriptGo(t.Start(i)))
        }
        n.code := SubStr(this.Text(i), 1, 900)
        this.Body(i, id, cls)
    }
    ; Calls, and values read and written, anywhere inside node i.
    Body(i, from, cls) {
        t := this.T
        ; what this function keeps local: its parameters, and what it
        ; assigns without declaring global
        params := Map(), params.CaseSense := false
        declared := Map(), declared.CaseSense := false
        assigned := Map(), assigned.CaseSense := false
        last := t.SubtreeEnd(i)
        k := i + 1
        while (k < last) {
            ty := t.Type(k)
            if (ty = "Parameter" && t.Parent(t.Parent(k)) = i)
                params[t.Value(k)] := true
            else if (ty = "Declaration" && InStr(t.Meta(k), "global"))
                declared[t.Value(k)] := true
            else if (ty = "Declaration" && t.Meta(k) = "" && t.Type(t.Parent(k)) = "Declaration")
                declared[t.Value(k)] := true           ; global a, b: b sits under a
            else if (ty = "BinaryExpr" && t.Has(k, "assign")) {
                l := t.FirstChild(k)
                if (t.Type(l) = "Identifier")
                    assigned[t.Value(l)] := true
            }
            k++
        }
        k := i + 1
        while (k < last) {
            ty := t.Type(k)
            if (ty = "Method" && k != i) {                  ; a nested function is its own
                k := t.SubtreeEnd(k)
                continue
            }
            if (ty = "Call") {
                c := t.FirstChild(k)
                if (t.Type(c) = "Identifier") {
                    nm := t.Value(c)
                    if (StrLower(nm) = "settimer" || StrLower(nm) = "onmessage")
                        this.Hook(k, nm, from, cls)
                    else if ((to := this.Callee(nm, "")) != "")
                        this.Edge(from, to, "call")
                    else if this.Meths.Has(nm ".__New")
                        this.Edge(from, "fn:" nm ".__New", "call")
                    else if this.LibFns.Has(nm)
                        this.LibCall(from, nm "()", this.LibFns[nm])
                    else if this.LibCls.Has(nm)
                        this.LibCall(from, nm "()", this.LibCls[nm])
                } else if (t.Type(c) = "Member") {
                    o := t.FirstChild(c)
                    if (t.Type(o) = "This" && cls != "" && (to := this.Callee(t.Value(c), cls)) != "")
                        this.Edge(from, to, "call")
                    else if (t.Type(o) = "Identifier" && this.Meths.Has(t.Value(o) "." t.Value(c)))
                        this.Edge(from, "fn:" t.Value(o) "." t.Value(c), "call")
                    else if (StrLower(t.Value(c)) = "onevent" && cls != "")
                        this.ClassEvent(k, from, cls)
                    else if (t.Type(o) = "Identifier" && this.LibCls.Has(t.Value(o)))
                        this.LibCall(from, t.Value(o) "." t.Value(c) "()", this.LibCls[t.Value(o)])
                }
            } else if (ty = "Identifier") {
                nm := t.Value(k)
                isLocal := params.Has(nm) || (assigned.Has(nm) && !declared.Has(nm) && from != "start")
                if !isLocal {
                    w := this.IsWrite(k)
                    if this.Ctls.Has(nm) {
                        if (from != "start")                        ; making the controls is not news
                            this.Data("ctl:" nm, nm, "control", from, w, {K: "node", Node: this.Ctls[nm].Id})
                    }
                    ; (ctl12: the variable the export gives a control with no
                    ; name -- plumbing, not a value anyone made)
                    else if (this.Globals.Has(nm) && !this.Fns.Has(nm) && !this.WinVars.Has(nm) && SubStr(nm, 1, 2) != "Ax"
                             && !RegExMatch(nm, "^ctl\d+$"))
                        this.Data("var:" nm, nm, "value", from, w, this.VarGo(nm))
                }
            } else if (ty = "Member" && cls != "") {
                o := t.FirstChild(k)
                if (t.Type(o) = "This" && !this.Meths.Has(cls "." t.Value(k))) {
                    pk := cls "." t.Value(k)
                    if !this.Props.Has(pk)
                        this.Props[pk] := Map()
                    this.Props[pk][from] := this.IsWrite(k) ? "w" : (this.Props[pk].Has(from) ? this.Props[pk][from] : "r")
                }
            }
            k++
        }
    }
    ; x := ..., x.Text := ..., x += ...: the thing on the left is written
    IsWrite(k) {
        t := this.T
        p := t.Parent(k)
        while (p >= 0 && t.Type(p) = "Member")
            k := p, p := t.Parent(p)
        return (p >= 0 && t.Type(p) = "BinaryExpr" && t.Has(p, "assign") && t.FirstChild(p) = k)
            || (p >= 0 && t.Type(p) = "PostfixExpr")
    }
    Data(id, label, sub, from, write, go) {
        this.Add(id, 3, sub = "control" ? "control" : "value", label, sub, 0, go)
        this.Edge(from, id, write ? "write" : "read")
    }
    ; SetTimer(fn, ms) / OnMessage(msg, fn): a trigger of its own
    Hook(k, nm, from, cls) {
        t := this.T
        a := []
        for x in t.Children(t.Next(t.FirstChild(k)))
            a.Push(x)
        if !a.Length
            return
        fnArg := (StrLower(nm) = "settimer") ? a[1] : (a.Length >= 2 ? a[2] : -1)
        if (fnArg < 0)
            return
        to := this.FnRef(fnArg, cls)
        label := (StrLower(nm) = "settimer") ? "timer" : "message " this.Text(a[1])
        every := (StrLower(nm) = "settimer" && a.Length >= 2) ? "every " this.Text(a[2]) " ms" : ""
        if (to = "") {
            ; SetTimer(() => (...), 1000): the arrow is what the timer does
            if (t.Type(fnArg) != "FatArrow")
                return
            id := "tm:" from ":" t.Start(k)
            n := this.Add(id, 0, "timer", label, every, 0, this.ScriptGo(t.Start(k)))
            n.code := SubStr(this.Text(fnArg), 1, 900)
            this.Edge(from, id, "call")
            this.Body(fnArg, id, cls)
            for e in this.Edges
                if (e.a = id && e.k = "call")
                    e.k := "trig"
            return
        }
        id := "tm:" to ":" label
        this.Add(id, 0, "timer", label, every, 0, this.ScriptGo(t.Start(k)))
        this.Edge(from, id, "call")
        this.Edge(id, to, "trig")
    }
    ; ctl.OnEvent("Click", (*) => this.Go()) inside a class: a trigger
    ClassEvent(k, from, cls) {
        t := this.T
        c := t.FirstChild(k)
        a := []
        for x in t.Children(t.Next(c))
            a.Push(x)
        if (a.Length < 2 || t.Type(a[1]) != "String")
            return
        who := t.FirstChild(c)
        whoText := RegExReplace(this.Text(who), "^this\.")
        ev := Trim(t.Value(a[1]), "`"'")
        id := "oe:" cls "." whoText ":" ev
        this.Add(id, 0, "event", whoText, ev, 0, this.ScriptGo(t.Start(k)))
        ; what it runs: a function named, or whatever the arrow calls
        to := this.FnRef(a[2], cls)
        if (to != "")
            return this.Edge(id, to, "trig")
        if (t.Type(a[2]) = "FatArrow") {
            this.Body(a[2], id, cls)
            ; what the arrow calls is what the event runs
            for e in this.Edges
                if (e.a = id && e.k = "call")
                    e.k := "trig"
        }
    }
    ; a function value: Name, this.Name, ObjBindMethod(this, "Name"), this.Name.Bind(this)
    FnRef(i, cls) {
        t := this.T
        ty := t.Type(i)
        if (ty = "Identifier")
            return this.Callee(t.Value(i), "")
        if (ty = "Member" && t.Type(t.FirstChild(i)) = "This")
            return this.Callee(t.Value(i), cls)
        if (ty = "Call") {
            c := t.FirstChild(i)
            if (t.Type(c) = "Member" && StrLower(t.Value(c)) = "bind")
                return this.FnRef(t.FirstChild(c), cls)
            if (t.Type(c) = "Identifier" && StrLower(t.Value(c)) = "objbindmethod") {
                a := []
                for x in t.Children(t.Next(c))
                    a.Push(x)
                if (a.Length >= 2 && t.Type(a[2]) = "String")
                    return this.Callee(Trim(t.Value(a[2]), "`"'"), cls)
            }
        }
        return ""
    }
    ; A class's own state, as data: only what one method writes and another
    ; reads, so the map shows what connects them rather than every field
    SharedProps() {
        for pk, uses in this.Props {
            w := 0, r := 0
            for fn, how in uses {
                if (how = "w")
                    w++
                else
                    r++
            }
            if !(w && (r || uses.Count > 1))
                continue
            id := "prop:" pk
            this.Add(id, 3, "value", SubStr(pk, InStr(pk, ".") + 1), SubStr(pk, 1, InStr(pk, ".") - 1), 0, "")
            for fn, how in uses
                this.Edge(fn, id, how = "w" ? "write" : "read")
        }
    }
    ; what starts things runs what is next to it; everything further is used
    Lanes() {
        first := Map()
        for e in this.Edges
            if (e.k = "trig" && this.Nodes.Has(e.b))
                first[e.b] := true
        for n in this.Order
            if (n.lane = 2 && first.Has(n.id))
                n.lane := 1
    }

    ; ---------------------------------------------------------- where to go
    ScriptGo(at) {
        ; the text at `at` in the export: find the same text in a window's
        ; own script, and go there
        t := SubStr(this.Src, at + 1, 60)
        head := RegExReplace(t, "\R.*", "")
        for wi, w in this.P.Wins
            for part in ["script", "init"] {
                txt := StrReplace((part = "script") ? w.Script : w.Init, "`r")     ; the editor counts a line break as one
                p := InStr(txt, head)
                if p
                    return {K: "script", Win: wi, Part: part, At: p - 1}
            }
        return ""
    }
    VarGo(nm) {
        for v in AxBind.Vars(this.P)
            if (v.Name = nm)
                return {K: "logic", Sec: "values"}
        for wi, w in this.P.Wins {
            if RegExMatch(StrReplace(w.Script, "`r"), "im)^[ \t]*\Q" nm "\E\s*:=", &m)
                return {K: "script", Win: wi, Part: "script", At: m.Pos - 1}
            if RegExMatch(StrReplace(w.Init, "`r"), "im)^[ \t]*\Q" nm "\E\s*:=", &m)
                return {K: "script", Win: wi, Part: "init", At: m.Pos - 1}
        }
        return ""
    }
    Text(i) => SubStr(this.Src, this.T.Start(i) + 1, this.T.End(i) - this.T.Start(i))

    ; the piece of code a node is, for Step by step: a handler, one of your
    ; functions, the startup code -- "" when it is not one you can open there
    PieceKey(n, defs) {
        if (n.id = "start") {
            for wi, w in this.P.Wins
                if (w.Kind = "main")
                    return "init." wi
            return "init.1"
        }
        go := this.Go.Has(n.id) ? this.Go[n.id] : ""
        if IsObject(go) && go.K = "event" {
            nd := this.P.Find(go.Node)
            if IsObject(nd)
                for j, e in nd.Ev
                    if (e["name"] = go.Ev)
                        return "ev." this.P.WinIndex(this.P.WinOf(nd)) "." nd.Id "." j
        }
        if (SubStr(n.id, 1, 3) = "fn:" && defs.Has(SubStr(n.id, 4)))
            return "fn." defs[SubStr(n.id, 4)] "." SubStr(n.id, 4)
        return ""
    }
    ToJson() {
        defs := Map(), defs.CaseSense := false
        for wi, w in this.P.Wins
            for d in AxSteps.Defs(w.Script)
                defs[d.Name] := wi
        nodes := []
        this.Pcs := Map()
        for n in this.Order {
            if !this.Used(n)
                continue
            wn := (n.win && n.win <= this.P.Wins.Length) ? this.P.Wins[n.win].Name : ""
            pc := this.PieceKey(n, defs)
            this.Pcs[n.id] := {Kind: n.kind, Label: String(n.label), Pc: pc}
            nodes.Push(Map("id", n.id, "lane", n.lane, "kind", n.kind, "label", String(n.label),
                "sub", String(n.sub), "win", wn, "code", n.code, "go", this.Go.Has(n.id) ? 1 : 0,
                "pc", pc))
        }
        edges := []
        for e in this.Edges
            if (this.Nodes.Has(e.a) && this.Nodes.Has(e.b))
                edges.Push(Map("a", e.a, "b", e.b, "k", e.k))
        return AxJson.Stringify(Map("nodes", nodes, "edges", edges), "")
    }
    ; a function nothing reaches and that reaches nothing is still shown;
    ; the start node only when the first lines do something
    Used(n) {
        if (n.id != "start")
            return true
        for e in this.Edges
            if (e.a = "start")
                return true
        return false
    }
}
