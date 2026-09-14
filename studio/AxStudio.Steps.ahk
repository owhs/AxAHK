#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\AxStudio.Host.ahk
#Include %A_LineFile%\..\AxStudio.Gen.ahk
#Include %A_LineFile%\..\AxStudio.Lit.ahk

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
;  AxStudio.Steps.ahk -- any piece of code as steps: a flowchart you can read
;  and change without writing code.
;
;  A piece is a handler, a window's startup code, one of your own functions
;  (or a method, or a hotkey) in its script, or -- read only -- the whole
;  script as exported. It is parsed (bin\AstHost.exe) and every statement
;  becomes a step, said in words: "If Current is empty", "Show a message:
;  ...", "Set Dirty to false", "Repeat 3 times". Branches sit side by side,
;  loops hold what they repeat, and each step carries the values it reads and
;  the ones it changes.
;
;  Changing it is text, not a tree. The parser gives every statement its
;  place in the piece (Start/End, UTF-16 offsets -- the same units an AHK
;  string counts in), so a change replaces those characters and nothing
;  else: the rest of the piece, its comments and its layout, are untouched.
;  That matters, because the engine's own writer is not 1:1 with what was
;  typed (see memory: joined lines, moved comments). After a change the piece
;  is read again, so what is drawn is always what is there.
;
;  The lists a step can be added to are kept with how to add to them:
;      block   { ... } -- after the brace, at the children's indent
;      bare    one statement on its own line under an if/loop, no braces:
;              a second one means putting braces round both
;      same    one statement on the same line as its owner (try X, F1::X):
;              the same, with the brace on that line
;      else    the "otherwise" of an if that has none yet
;      root    the piece itself
; =============================================================================
class AxSteps {
    static Pc := ""           ; the piece on show: {Kind, Win, Id, Index, Fn}
    static M := ""            ; the reading of it (AxStepsRead)
    static Sel := ""          ; the step picked, by id
    static Problem := ""

    ; ------------------------------------------------------------- pieces
    ; Every piece of code in the project, window by window, for the list
    ; down the left: startup code, the handlers, then what the script defines.
    static Pieces(p) {
        out := []
        for wi, w in p.Wins {
            out.Push({Key: "init." wi, Label: "When it starts", Sub: "startup code", Icon: "E768", Win: wi,
                      Head: w.Name, Pc: {Kind: "init", Win: wi}, Lines: AxSteps.Count(w.Init)})
            had := Map(), had.CaseSense := false
            for n in AxSteps.EvNodes(w.Root)
                for j, ev in n.Ev {
                    had[n.Name "|" ev["name"]] := 1
                    out.Push({Key: "ev." wi "." n.Id "." j, Label: (n.Name != "" ? n.Name : n.Type) " " ev["name"],
                              Sub: "when it happens", Icon: "E7C9", Win: wi,
                              Pc: {Kind: "event", Win: wi, Id: n.Id, Index: j}, Lines: AxSteps.Count(ev["code"])})
                }
            ; an event with rules and no code of its own is a piece too: its
            ; steps are the rules, and the first step added makes it code
            try for pair in AxFlow.Pairs(w)
                if !had.Has(pair.Ctl "|" pair.Ev)
                    out.Push({Key: "rules." wi "." pair.Ctl "." pair.Ev, Label: pair.Ctl " " pair.Ev, Sub: "rules",
                              Icon: "E945", Win: wi, Pc: {Kind: "rules", Win: wi, Ctl: pair.Ctl, Ev: pair.Ev},
                              Lines: AxFlow.For(w, pair.Ctl, pair.Ev).Length})
            for d in AxSteps.Defs(w.Script)
                out.Push({Key: "fn." wi "." d.Name, Label: d.Label, Sub: d.Sub, Icon: d.Icon, Win: wi,
                          Pc: {Kind: "fn", Win: wi, Fn: d.Name}, Lines: d.Lines})
        }
        return out
    }
    static EvNodes(root) {
        list := []
        AxSteps._Ev(root, list)
        return list
    }
    static _Ev(n, list) {
        if n.Ev.Length
            list.Push(n)
        for c in n.Kids
            AxSteps._Ev(c, list)
    }
    static Count(text) {
        n := 0
        for l in StrSplit(StrReplace(text, "`r"), "`n")
            n += (Trim(l) != "" && SubStr(Trim(l), 1, 1) != ";")
        return n
    }
    ; What a script defines that has steps of its own: functions, methods
    ; (Class.Name), hotkeys and hotstrings with code. Read from the parse.
    static Defs(script) {
        out := []
        if (Trim(script) = "" || !AxHost.Ready)
            return out
        try t := AxHost.TreeText(script)
        catch
            return out
        for i in t.Children(0)
            AxSteps._Def(t, script, i, "", out)
        return out
    }
    static _Def(t, src, i, cls, out) {
        ty := t.Type(i)
        if (ty = "Method") {
            nm := (cls != "" ? cls "." : "") t.Value(i)
            out.Push({Name: nm, Label: nm "()", Sub: cls != "" ? "method" : "your function", Icon: "E8F4",
                      Lines: t.EndLine(i) - t.StartLine(i) + 1})
        } else if (ty = "Class") {
            for c in t.Children(i)
                AxSteps._Def(t, src, c, (cls != "" ? cls "." : "") t.Value(i), out)
        } else if (ty = "Hotkey") {
            out.Push({Name: "hk:" t.Value(i), Label: t.Value(i), Sub: "hotkey", Icon: "E765",
                      Lines: t.EndLine(i) - t.StartLine(i) + 1})
        }
    }
    static Key(pc) {
        if !IsObject(pc)
            return ""
        switch pc.Kind {
        case "event": return "ev." pc.Win "." pc.Id "." pc.Index
        case "init":  return "init." pc.Win
        case "fn":    return "fn." pc.Win "." pc.Fn
        case "rules": return "rules." pc.Win "." pc.Ctl "." pc.Ev
        case "gen":   return "gen"
        }
        return ""
    }
    static FromKey(key) {
        p := StrSplit(key, ".", , 4)
        switch p[1] {
        case "ev":   return {Kind: "event", Win: Integer(p[2]), Id: p[3], Index: Integer(p[4])}
        case "rules": return {Kind: "rules", Win: Integer(p[2]), Ctl: p[3], Ev: p[4]}
        case "init": return {Kind: "init", Win: Integer(p[2])}
        case "fn":   return {Kind: "fn", Win: Integer(p[2]), Fn: SubStr(key, InStr(key, ".", , , 2) + 1)}
        case "gen":  return {Kind: "gen"}
        }
        return ""
    }
    static ReadOnly(pc) => IsObject(pc) && pc.Kind = "gen"

    ; The text of a piece, and putting it back. "" and false when it is gone
    ; (a handler deleted, a window removed).
    static Get(s, pc) {
        if !IsObject(pc)
            return ""
        if (pc.Kind = "gen")
            return AxGen.Script(s.P, s.P.Path != "" ? s.P.Path : s.ScriptPath(), "")
        if (pc.Win < 1 || pc.Win > s.P.Wins.Length)
            return ""
        w := s.P.Wins[pc.Win]
        switch pc.Kind {
        case "init": return StrReplace(w.Init, "`r")
        case "fn":   return StrReplace(w.Script, "`r")
        case "rules": return ""
        case "event":
            n := s.P.Find(pc.Id)
            return (IsObject(n) && pc.Index <= n.Ev.Length) ? StrReplace(n.Ev[pc.Index]["code"], "`r") : ""
        }
        return ""
    }
    static Put(s, pc, text) {
        w := s.P.Wins[pc.Win]
        switch pc.Kind {
        case "init": w.Init := text
        case "fn":   w.Script := text
        case "event":
            n := s.P.Find(pc.Id)
            if !IsObject(n) || pc.Index > n.Ev.Length
                return false
            n.Ev[pc.Index]["code"] := text
        case "rules":
            ; the first step after an event's rules: it gets code of its own,
            ; which runs after them, and the piece is that handler from now on
            n := s.P.FindByName(pc.Ctl)
            if !IsObject(n)
                return false
            n.Ev.Push(Map("name", pc.Ev, "code", text))
            AxSteps.Pc := {Kind: "event", Win: pc.Win, Id: n.Id, Index: n.Ev.Length}
        default:
            return false
        }
        s.P.Dirty := true
        return true
    }
    static Title(s, pc) {
        if !IsObject(pc)
            return ""
        if (pc.Kind = "gen")
            return "The whole script"
        w := (pc.Win >= 1 && pc.Win <= s.P.Wins.Length) ? s.P.Wins[pc.Win] : ""
        where := (IsObject(w) && s.P.Wins.Length > 1) ? " -- " w.Name : ""
        switch pc.Kind {
        case "rules": return pc.Ctl " " pc.Ev where
        case "init": return "When it starts" where
        case "fn":   return (SubStr(pc.Fn, 1, 3) = "hk:" ? "The hotkey " SubStr(pc.Fn, 4) : pc.Fn "()") where
        case "event":
            n := s.P.Find(pc.Id)
            return IsObject(n) && pc.Index <= n.Ev.Length ? (n.Name != "" ? n.Name : n.Type) " " n.Ev[pc.Index]["name"] where : "(gone)"
        }
        return ""
    }

    ; ------------------------------------------------------------- reading
    static Read(s, pc) {
        AxSteps.Problem := ""
        text := AxSteps.Get(s, pc)
        try AxSteps.M := AxStepsRead(s.P, pc, text)
        catch as e {
            AxSteps.M := ""
            AxSteps.Problem := e.Message
        }
        return AxSteps.M
    }
}

; One reading of one piece: the steps, and where each list can take more.
class AxStepsRead {
    __New(p, pc, text) {
        this.P := p, this.Pc := pc, this.Text := text
        this.Lists := Map()       ; key -> {Kind, Items [ids], Open, Ind, OwnerInd, OwnerEnd, Owner}
        this.Steps := Map()       ; id -> {S, E, List, Kind, Node}
        this.Shared := []         ; names declared global
        this.Ctls := Map(), this.Ctls.CaseSense := false
        this.Vals := Map(), this.Vals.CaseSense := false
        this.Fns := Map(), this.Fns.CaseSense := false       ; the project's own functions
        AxStepsRead.Names(p, this.Ctls, this.Vals, this.Fns)
        this.Off := 0
        src := text
        if (pc.Kind = "event") {
            ; a handler is a body: read it as one
            pre := "AxStepsBody(*) {`n"
            src := pre text "`n}"
            this.Off := StrLen(pre)
        }
        this.Src := src
        this.T := AxHost.TreeText(src)
        t := this.T
        this.Root := []
        if (pc.Kind = "event") {
            body := AxStepsRead.BodyOf(t, t.FirstChild(0))
            this.Root := this.List("root", body, "root", "", 0, -1)
        } else if (pc.Kind = "fn") {
            at := this.FindDef(0, "", pc.Fn)
            if (at < 0)
                throw Error(pc.Fn " is not in the script any more.")
            this.DefNode := at
            body := AxStepsRead.BodyOf(t, at)
            if (body >= 0 && t.Type(body) = "Block")
                this.Root := this.List("root", body, "block", this.IndentAt(t.Start(at)), t.Start(at), at)
            else if (body >= 0 && t.Type(body) = "FatArrowBody")
                this.Root := this.List("root", body, "fixed", this.IndentAt(t.Start(at)), t.Start(at), at)
            else if (body >= 0)
                this.Root := this.List("root", body, "same", this.IndentAt(t.Start(at)), t.Start(at), at)
        } else {
            this.Root := this.List("root", 0, "root", "", 0, -1)
        }
    }
    ; the names that mean something in this project: controls, values, and
    ; the functions a step can open
    static Names(p, ctls, vals, fns) {
        for w in p.Wins {
            for n in AxImport.Nodes(w.Root)
                if (n.Name != "")
                    ctls[AxProject.CleanName(n.Name)] := n
            for d in AxSteps.Defs(w.Script)
                if (SubStr(d.Name, 1, 3) != "hk:")
                    fns[d.Name] := w
        }
        for v in AxBind.Vars(p)
            vals[v.Name] := v
    }
    ; the piece a generated function is: a control's handler, or your own
    PieceOf(fn) {
        if !this.HasOwnProp("_hand") {
            this._hand := Map(), this._hand.CaseSense := false
            for wi, w in this.P.Wins {
                for n in AxImport.Nodes(w.Root)
                    for j, e in n.Ev
                        this._hand[AxGen.HandlerName(n, e["name"])] := "ev." wi "." n.Id "." j
                for d in AxSteps.Defs(w.Script)
                    this._hand[d.Name] := "fn." wi "." d.Name
            }
        }
        return this._hand.Has(fn) ? this._hand[fn] : ""
    }
    ; a window's own variable (g), so g.Text(...) reads as the window's verb
    WinVar(nm) {
        for w in this.P.Wins
            if (w.Var = nm)
                return true
        return false
    }
    FindDef(i, cls, want) {
        t := this.T
        for c in t.Children(i) {
            ty := t.Type(c)
            if (ty = "Method" && (cls != "" ? cls "." : "") t.Value(c) = want)
                return c
            if (ty = "Hotkey" && "hk:" t.Value(c) = want)
                return c
            if (ty = "Class") {
                r := this.FindDef(c, (cls != "" ? cls "." : "") t.Value(c), want)
                if (r >= 0)
                    return r
            }
        }
        return -1
    }
    ; the statement that is a function's, a hotkey's, a loop's body
    static BodyOf(t, i) {
        last := -1
        for c in t.Children(i) {
            ty := t.Type(c)
            if (ty != "Parameters" && ty != "Until")
                last := c
        }
        return last
    }

    ; ------------------------------------------------------------ text help
    ; everything in piece units: the piece's own text, not the wrapper
    S(i) => this.T.Start(i) - this.Off
    E(i) => this.T.End(i) - this.Off
    Tx(i) => SubStr(this.Src, this.T.Start(i) + 1, this.T.End(i) - this.T.Start(i))
    LineStart(pos) {
        k := pos
        while (k > 0 && SubStr(this.Text, k, 1) != "`n")
            k--
        return k                      ; 0-based offset of the line's first character
    }
    LineEnd(pos) {
        k := InStr(this.Text, "`n", , pos + 1)
        return k ? k - 1 : StrLen(this.Text)        ; 0-based offset of its "`n" (or the end)
    }
    IndentAt(srcPos) {
        pos := srcPos - this.Off
        if (pos < 0)
            return ""
        ls := this.LineStart(pos)
        RegExMatch(SubStr(this.Text, ls + 1), "^[ \t]*", &m)
        return m[0]
    }
    ; is the text before this position, on its line, only blanks?
    StartsLine(pos) => Trim(SubStr(this.Text, this.LineStart(pos) + 1, pos - this.LineStart(pos)), " `t") = ""

    ; -------------------------------------------------------------- lists
    ; key: the list's name; node: the Block (or Program, or the one statement)
    ; kind: block | bare | same | root; ownerInd: the owner's indent
    List(key, node, kind, ownerInd, ownerStart, owner) {
        t := this.T
        stmts := []
        if (node >= 0) {
            ty := t.Type(node)
            if (ty = "Block" || ty = "Program" || ty = "Method" || ty = "CaseBody" || ty = "DefaultBody") {
                for c in t.Children(node)
                    if (t.Type(c) != "Parameters")
                        stmts.Push(c)
                if (ty = "CaseBody" || ty = "DefaultBody")
                    kind := "case"
            } else
                stmts.Push(node)
        }
        L := {Kind: kind, Items: [], OwnerInd: ownerInd, Owner: owner, Node: node, Ind: "", Open: -1}
        if (node >= 0 && t.Type(node) = "Block") {
            ; after the "{" and its line break
            L.Open := this.LineEnd(this.S(node)) + 1
            L.Close := this.E(node) - 1
        }
        this.Lists[key] := L
        out := []
        ; The whole script: its set-up (directives, the library's includes,
        ; the regions' comments) is one line at the top, not forty blocks
        if (this.Pc.Kind = "gen" && key = "root") {
            keep := [], dirs := 0, incs := 0
            for c in stmts {
                ty := t.Type(c)
                if (ty = "Comment")
                    continue
                if (ty = "Directive") {
                    (InStr(t.Value(c), "#Include") = 1) ? incs++ : dirs++
                    continue
                }
                keep.Push(c)
            }
            stmts := keep
            out.Push(Map("id", "setup", "k", "note", "t", "Set-up: " dirs " line" (dirs = 1 ? "" : "s") " for AutoHotkey itself, and "
                . incs " file" (incs = 1 ? "" : "s") " it includes -- AxGui, its controls, your code files and libraries",
                "code", "", "reads", [], "writes", []))
        }
        for c in stmts {
            st := this.Step(c, key)
            if !IsObject(st)
                continue
            L.Items.Push(st["id"])
            out.Push(st)
        }
        if L.Items.Length
            L.Ind := this.IndentAt(this.T.Start(stmts[1]))
        else
            L.Ind := ownerInd (InStr(this.Text, "`t") && !InStr(this.Text, "    ") ? "`t" : "    ")
        if (kind = "root" && !L.Items.Length)
            L.Ind := (this.Pc.Kind = "fn") ? "    " : ""
        return out
    }

    ; -------------------------------------------------------------- a step
    Step(i, listKey) {
        t := this.T
        ty := t.Type(i)
        if (ty = "Declaration" && t.Meta(i) = "global") {
            for c in AxStepsRead.Chain(t, i)
                this.Shared.Push(t.Value(c))
            return ""
        }
        id := "s" this.S(i)
        st := Map("id", id, "k", "code", "t", "", "code", AxStepsRead.OneLine(this.Tx(i)),
                  "reads", [], "writes", [])
        this.Steps[id] := {S: this.S(i), E: this.E(i), List: listKey, Node: i, Kind: ""}
        ind := this.IndentAt(t.Start(i))
        switch ty {
        case "If":
            st["k"] := "if", st["br"] := this.Branches(i, id, ind)
            st["t"] := "If " AxSay.Cond(this, t.FirstChild(i))
            st["code"] := AxStepsRead.OneLine(this.Tx(t.FirstChild(i)))
            this.Uses(t.FirstChild(i), st)
            ; changing an if changes its test, never what it holds
            this.Steps[id].HeadS := this.S(t.FirstChild(i)), this.Steps[id].HeadE := this.E(t.FirstChild(i))
        case "Loop", "While", "For":
            st["k"] := "loop"
            body := AxStepsRead.BodyOf(t, i)
            st["t"] := AxSay.LoopHead(this, i)
            st["code"] := AxStepsRead.OneLine(SubStr(this.Tx(i), 1, (body >= 0 ? t.Start(body) - t.Start(i) : 200)))
            st["body"] := this.Sub(id ":body", body, i, ind)
            st["bkey"] := id ":body"
            lastHead := -1
            for c in t.Children(i)
                if (c != body)
                    this.Uses(c, st), lastHead := c
            ; its first line, up to what it repeats
            this.Steps[id].HeadS := this.S(i)
            this.Steps[id].HeadE := (lastHead >= 0) ? this.E(lastHead) : this.S(i) + StrLen(RegExReplace(this.Tx(i), "^(\w+).*", "$1"))
        case "Try":
            st["k"] := "try", st["t"] := "Try this"
            kids := []
            for c in t.Children(i)
                kids.Push(c)
            st["body"] := this.Sub(id ":try", kids.Length ? kids[1] : -1, i, ind), st["bkey"] := id ":try"
            br := []
            for c in kids {
                if (t.Type(c) = "Catch") {
                    b := AxStepsRead.BodyOf(t, c)
                    br.Push(Map("l", "If it fails" (t.Meta(c) != "" ? " (as " t.Meta(c) ")" : ""), "key", id ":catch",
                                "steps", this.Sub(id ":catch", b, c, ind)))
                } else if (t.Type(c) = "Finally") {
                    b := AxStepsRead.BodyOf(t, c)
                    br.Push(Map("l", "Either way, after", "key", id ":fin", "steps", this.Sub(id ":fin", b, c, ind)))
                }
            }
            ; nothing for when it fails yet: a list that makes one, as an if's
            ; "otherwise" (and the try is not drawn as a fork with one side)
            if !br.Length {
                this.Lists[id ":catch"] := {Kind: "catch", Items: [], OwnerInd: ind, Owner: i, Node: -1,
                    Ind: ind "    ", Open: -1, End: this.E(i)}
                br.Push(Map("l", "If it fails", "key", id ":catch", "steps", [], "none", 1,
                            "add", "Add what happens if it fails"))
            }
            st["br"] := br
        case "Switch":
            st["k"] := "if", st["sw"] := 1
            subj := t.FirstChild(i)
            st["t"] := "Depending on " AxSay.Val(this, subj)
            st["code"] := "switch " AxStepsRead.OneLine(this.Tx(subj))
            this.Uses(subj, st)
            br := [], n := 0
            for c in t.Children(i) {
                if (c = subj)
                    continue
                n++
                if (t.Type(c) = "Case") {
                    vals := "", body := -1
                    for v in t.Children(c)
                        if (t.Type(v) = "CaseBody")
                            body := v
                        else
                            vals .= (vals = "" ? "" : " or ") AxSay.Val(this, v)
                    br.Push(Map("l", "When it is " vals, "key", id ":" n, "steps", this.Sub(id ":" n, body, c, ind)))
                } else if (t.Type(c) = "Default") {
                    body := t.FirstChild(c)
                    br.Push(Map("l", "Anything else", "key", id ":" n, "steps", this.Sub(id ":" n, body, c, ind)))
                }
            }
            st["br"] := br
        case "Return":
            v := t.FirstChild(i)
            st["k"] := "end", st["t"] := (v >= 0) ? "Give back " AxSay.Val(this, v) " and stop" : "Stop here"
            if (v >= 0)
                this.Uses(v, st)
        case "Break":
            st["k"] := "end", st["t"] := "Stop repeating"
        case "Continue":
            st["k"] := "end", st["t"] := "Go round again"
        case "Comment":
            st["k"] := "note", st["t"] := Trim(RegExReplace(this.Tx(i), "^\s*(;|/\*)|\*/\s*$"))
        case "Declaration":
            names := ""
            for c in AxStepsRead.Chain(t, i)
                names .= (names = "" ? "" : ", ") t.Value(c)
            st["k"] := "note", st["t"] := (t.Meta(i) = "static" ? "Keeps between runs: " : "Its own: ") names
        case "BinaryExpr", "PostfixExpr", "UnaryExpr":
            if (ty = "BinaryExpr" && t.Has(i, "assign")) || ty = "PostfixExpr" || (ty = "UnaryExpr" && (t.Value(i) = "++" || t.Value(i) = "--")) {
                st["k"] := "set", st["t"] := AxSay.Set(this, i)
                this.Uses(i, st)
            } else {
                st["t"] := AxStepsRead.OneLine(this.Tx(i))
                this.Uses(i, st)
            }
        case "Call":
            st["k"] := "act", st["t"] := AxSay.Act(this, i, st)
            this.Uses(i, st)
        case "Method":
            st["k"] := "note", st["t"] := "Defines " t.Value(i) "()"
            ; in the whole script, a function that is a piece of its own
            ; (a handler, one of yours) opens as that piece
            if (this.Pc.Kind = "gen")
                st["piece"] := this.PieceOf(t.Value(i))
        case "Hotkey", "Hotstring":
            st["k"] := "note", st["t"] := (ty = "Hotkey" ? "The hotkey " : "The hotstring ") t.Value(i)
        case "Class":
            st["k"] := "note", st["t"] := "Defines the class " t.Value(i)
        case "Directive":
            st["k"] := "note", st["t"] := t.Value(i)
        default:
            st["t"] := AxStepsRead.OneLine(this.Tx(i))
            this.Uses(i, st)
        }
        this.Steps[id].Kind := st["k"]
        return st
    }
    ; declared names: "global a, b" is a, with b under it
    static Chain(t, i) {
        out := [i]
        for c in t.Children(i)
            if (t.Type(c) = "Declaration")
                for x in AxStepsRead.Chain(t, c)
                    out.Push(x)
        return out
    }
    ; what a loop repeats, what a branch holds: a list of its own
    Sub(key, body, owner, ownerInd) {
        t := this.T
        if (body < 0)
            return this.List(key, -1, "block", ownerInd, t.Start(owner), owner)
        if (t.Type(body) = "Block")
            return this.List(key, body, "block", ownerInd, t.Start(owner), owner)
        if (t.Type(body) = "CaseBody" || t.Type(body) = "DefaultBody")
            return this.List(key, body, "case", ownerInd, t.Start(owner), owner)
        return this.List(key, body, this.StartsLine(this.S(body)) ? "bare" : "same", ownerInd, t.Start(owner), owner)
    }
    ; If, then each "else if", then the last "else" -- side by side
    Branches(i, id, ind) {
        t := this.T
        br := [], cur := i, n := 0
        loop {
            kids := []
            for c in t.Children(cur)
                kids.Push(c)
            n++
            cond := kids[1], body := kids.Length >= 2 ? kids[2] : -1
            els := (kids.Length >= 3 && t.Type(kids[3]) = "Else") ? kids[3] : -1
            label := (n = 1) ? "Yes" : "Otherwise, if " AxSay.Cond(this, cond)
            br.Push(Map("l", label, "key", id ":" n, "steps", this.Sub(id ":" n, (t.Type(body) = "Else" ? -1 : body), cur, ind)))
            if (els < 0) {
                ; no "otherwise" yet: a list that makes one
                this.Lists[id ":else"] := {Kind: "else", Items: [], OwnerInd: ind, Owner: i, Node: -1,
                    Ind: ind "    ", Open: -1, End: this.E(i)}
                br.Push(Map("l", "Otherwise", "key", id ":else", "steps", [], "none", 1))
                break
            }
            inner := t.FirstChild(els)
            if (inner >= 0 && t.Type(inner) = "If" && !this.StartsLine(this.S(inner))) {
                cur := inner                ; else if: the chain goes on
                continue
            }
            br.Push(Map("l", "Otherwise", "key", id ":else", "steps", this.Sub(id ":else", inner, els, ind)))
            break
        }
        return br
    }
    ; the names a step reads and the ones it changes: controls and values of
    ; the project, and what it declares global -- not every local
    Uses(i, st) {
        t := this.T
        last := t.SubtreeEnd(i)
        k := i
        while (k < last) {
            ty := t.Type(k)
            if (ty = "Identifier") {
                nm := t.Value(k)
                par := t.Parent(k)
                isFn := (par >= 0 && t.Type(par) = "Call" && t.FirstChild(par) = k)
                if !isFn && (this.Ctls.Has(nm) || this.Vals.Has(nm) || AxStepsRead.Has(this.Shared, nm)) {
                    w := AxStepsRead.IsWrite(t, k)
                    lst := w ? st["writes"] : st["reads"]
                    if !AxStepsRead.Has(lst, nm)
                        lst.Push(nm)
                }
            }
            k++
        }
    }
    static IsWrite(t, k) {
        p := t.Parent(k)
        while (p >= 0 && t.Type(p) = "Member")
            k := p, p := t.Parent(p)
        return (p >= 0 && t.Type(p) = "BinaryExpr" && t.Has(p, "assign") && t.FirstChild(p) = k)
            || (p >= 0 && t.Type(p) = "PostfixExpr")
    }
    static Has(arr, v) {
        for x in arr
            if (x = v)
                return true
        return false
    }
    static OneLine(s) {
        s := Trim(RegExReplace(s, "[ \t]*\R[ \t]*", " "))
        return StrLen(s) > 120 ? SubStr(s, 1, 117) "..." : s
    }

    ; ------------------------------------------------------------ as JSON
    Json() {
        m := Map("steps", this.Root, "shared", this.Shared, "ro", AxSteps.ReadOnly(this.Pc) ? 1 : 0)
        return AxJson.Stringify(m, "")
    }
}

; =============================================================================
;  AxSay -- code, said in words. Only what reads better in words is turned
;  into words; anything else is shown as the code it is, short.
; =============================================================================
class AxSay {
    ; what a call statement does
    static Acts := Map(
        "MsgBox", "Show a message: {1}", "ToolTip", "Show a tooltip: {1}", "TrayTip", "Show a notification: {1}",
        "Sleep", "Wait {1}", "Send", "Press keys {1}", "SendInput", "Press keys {1}", "SendEvent", "Press keys {1}",
        "SendText", "Type {1}", "SendPlay", "Press keys {1}", "Run", "Run {1}", "RunWait", "Run {1} and wait for it to finish",
        "FileAppend", "Add {1} to the file {2}", "FileDelete", "Delete the file {1}", "FileCopy", "Copy the file {1} to {2}",
        "FileMove", "Move the file {1} to {2}", "DirCreate", "Make the folder {1}", "DirDelete", "Delete the folder {1}",
        "FileRecycle", "Put the file {1} in the Recycle Bin", "IniWrite", "Save {1} in {2}", "IniDelete", "Forget {3} in {1}",
        "WinActivate", "Bring {1} to the front", "WinClose", "Close the window {1}", "WinMinimize", "Minimise {1}",
        "WinMaximize", "Maximise {1}", "WinRestore", "Restore {1}", "WinHide", "Hide the window {1}", "WinShow", "Show the window {1}",
        "WinWait", "Wait for the window {1}", "WinWaitActive", "Wait until {1} is in front", "WinWaitClose", "Wait until {1} closes",
        "Click", "Click {1}", "MouseMove", "Move the mouse to {1}, {2}", "MouseClick", "Click the {1} button",
        "SoundBeep", "Beep", "SoundPlay", "Play the sound {1}", "ExitApp", "Quit the program", "Reload", "Restart the program",
        "Suspend", "Turn the hotkeys off or on", "Pause", "Pause the program", "ClipWait", "Wait for the clipboard to fill",
        "KeyWait", "Wait for {1} to be let go", "Hotkey", "Set the hotkey {1}", "OutputDebug", "Write to the debug log: {1}",
        "Download", "Download {1} to {2}", "ControlSend", "Press keys {1} in {3}", "ControlClick", "Click {1} in {2}",
        "ProcessClose", "Close the program {1}", "Shutdown", "Shut down or restart Windows", "BlockInput", "Block the keyboard and mouse",
        "SetTitleMatchMode", "Match window names this way: {1}", "DetectHiddenWindows", "Find hidden windows: {1}",
        "SetWorkingDir", "Work in the folder {1}", "TraySetIcon", "Use the tray icon {1}", "A_TrayMenu.Add", "Add {1} to the tray menu",
        "Critical", "Do not let anything interrupt this", "SetKeyDelay", "Type with a delay of {1}")
    ; what a method call does, by the method's name
    static Meths := Map("Show", "Show {0}", "Hide", "Hide {0}", "Destroy", "Close {0} for good", "Focus", "Put the keyboard in {0}",
        "Push", "Add {1} to the end of {0}", "Pop", "Take the last one off {0}", "InsertAt", "Put {2} into {0} at {1}",
        "RemoveAt", "Remove item {1} from {0}", "Delete", "Remove {1} from {0}", "Set", "Set {1} in {0} to {2}",
        "Clear", "Empty {0}", "Add", "Add {1} to {0}", "Choose", "Pick {1} in {0}", "Move", "Move {0}",
        "Minimize", "Minimise {0}", "Maximize", "Maximise {0}", "Restore", "Restore {0}", "Close", "Close {0}",
        "Write", "Write {1} to {0}", "WriteLine", "Write the line {1} to {0}", "Read", "Read from {0}",
        "Page", "Go to the page {1}", "Toast", "Show a notification: {1}", "Value", "Set {1} to {2}", "Text", "Set the text of {1} to {2}",
        "Enable", "Turn {1} on", "Disable", "Grey out {1}", "ShowCtl", "Show {1}", "HideCtl", "Hide {1}")

    static Act(r, i, st) {
        t := r.T
        c := t.FirstChild(i)
        args := AxSay.Args(r, i)
        if (t.Type(c) = "Identifier") {
            nm := t.Value(c)
            if (StrLower(nm) = "settimer")
                return AxSay.Timer(r, args)
            if r.Fns.Has(nm) {
                st["call"] := nm
                return "Do " nm (args.Length ? " with " AxSay.Join(args) : "")
            }
            ; an adaptor says what it is for (Libraries)
            try if IsObject(a := AxNet.Find(r.P, nm))
                return (a.Doc != "" ? a.Doc : nm) (args.Length ? ": " AxSay.Join(args) : "")
            for k, tpl in AxSay.Acts
                if (k = nm)
                    return AxSay.Fill(tpl, args, "")
            return nm "(" AxSay.Join(args, ", ") ")"
        }
        if (t.Type(c) = "Member") {
            meth := t.Value(c), obj := t.FirstChild(c)
            who := AxSay.Val(r, obj)
            if (t.Type(obj) = "This")
                who := "this"
            full := r.Tx(obj) "." meth
            if r.Fns.Has(full)
                st["call"] := full
            ; building the window
            if (meth = "AddPage")
                return "Start the page " (args.Length > 1 ? args[2] : args.Length ? args[1] : "")
            if RegExMatch(meth, "^Add(\w+)$", &mm)
                return "Add a " AxSay.CtlWord(mm[1]) (args.Length ? ": " args[args.Length] : "")
            if (meth = "Use" && !args.Length)
                return "Carry on adding to " who " itself"
            for k, tpl in AxSay.Acts
                if (k = full)
                    return AxSay.Fill(tpl, args, who)
            ; g.Value("x", 1), g.Text("x", "hi"), g.Enable("x")...: the
            ; window's own verbs name the control first
            if (r.Tx(obj) = "g" || r.WinVar(r.Tx(obj))) && args.Length && RegExMatch(meth, "i)^(Value|Text|Enable|Disable|Page|Toast)$")
                return AxSay.Fill(AxSay.Meths[meth], args, who)
            for k, tpl in AxSay.Meths
                if (k = meth && !RegExMatch(k, "^(Value|Text|Enable|Disable|ShowCtl|HideCtl|Page|Toast)$"))
                    return AxSay.Fill(tpl, args, who)
            return who ": " meth "(" AxSay.Join(args, ", ") ")"
        }
        return AxStepsRead.OneLine(r.Tx(i))
    }
    ; what AddX makes, as people call it
    static CtlWord(x) {
        static m := Map("Row", "setting row", "Radio", "radio group", "Text", "label", "Edit", "text box",
            "Check", "check box", "CheckBox", "check box", "DDL", "drop-down", "DropDown", "drop-down",
            "ListBox", "list box", "ListView", "list", "TreeView", "tree", "DataView", "table", "Tab", "set of tabs",
            "Card", "card", "Group", "group box", "Switch", "switch", "Slider", "slider", "Picture", "picture",
            "Progress", "progress bar", "Link", "link", "Button", "button", "Spin", "number box", "Number", "number box",
            "MenuBar", "menu bar", "StatusBar", "status bar", "Hotkey", "hotkey box", "Html", "block of HTML")
        for k, w in m
            if (k = x)
                return w
        return StrLower(x)
    }
    static Timer(r, args) {
        fn := args.Length ? args[1] : "it"
        if (args.Length < 2)
            return "Start the timer " fn
        p := args[2]
        if (p = "0" || StrLower(Trim(p, "`"'")) = "off")
            return "Stop the timer " fn
        if RegExMatch(p, "^-(\d+)$", &m)
            return "In " AxSay.Ms(m[1]) ", run " fn " once"
        return "Every " AxSay.Ms(p) ", run " fn
    }
    static Ms(v) {
        if !IsInteger(v)
            return v " ms"
        v := Integer(v)
        return (v >= 60000 && !Mod(v, 60000)) ? (v // 60000) " min" : (v >= 1000 && !Mod(v, 1000)) ? (v // 1000) " s" : v " ms"
    }
    static Args(r, call) {
        t := r.T
        out := []
        a := t.Next(t.FirstChild(call))
        if (a >= 0 && t.Type(a) = "Arguments")
            for x in t.Children(a)
                out.Push(t.Type(x) = "Omitted" ? "" : AxSay.Val(r, x))
        return out
    }
    static Fill(tpl, args, who) {
        s := StrReplace(tpl, "{0}", who)
        loop 4
            s := StrReplace(s, "{" A_Index "}", args.Length >= A_Index ? args[A_Index] : "")
        s := RegExReplace(s, "\s+(,|$)", "$1")
        s := RegExReplace(s, "[:,]\s*$")
        ; "Sleep 500" reads as "Wait 500 ms"
        if RegExMatch(tpl, "^Wait \{1\}$") && args.Length && IsInteger(args[1])
            s := "Wait " AxSay.Ms(args[1])
        return Trim(s)
    }
    static Join(args, sep := ", ") {
        s := ""
        for a in args
            s .= (A_Index > 1 ? sep : "") a
        return s
    }

    ; a value, said: text in quotes, a control's property as its, a few
    ; calls by what they give
    static Val(r, i) {
        t := r.T
        ty := t.Type(i)
        switch ty {
        case "String", "Number":
            return AxStepsRead.OneLine(r.Tx(i))
        case "Identifier":
            nm := t.Value(i)
            static words := Map("A_ScriptDir", "the program's folder", "A_Now", "now", "A_Clipboard", "the clipboard",
                "A_Index", "the time round", "A_LoopField", "this part", "A_LoopFileName", "this file's name",
                "A_LoopFilePath", "this file", "A_UserName", "the user's name", "A_Desktop", "the desktop",
                "A_MyDocuments", "Documents", "A_Temp", "the temp folder", "A_ComputerName", "the computer's name",
                "A_TickCount", "the time in ms", "A_IsAdmin", "running as administrator", "A_ThisHotkey", "the hotkey pressed")
            for k, w in words
                if (k = nm)
                    return w
            return nm
        case "Member":
            o := t.FirstChild(i), prop := t.Value(i)
            if (t.Type(o) = "This")
                return "this." prop
            whose := AxSay.Val(r, o)
            static props := Map("Value", "value", "Text", "text", "Checked", "tick", "Enabled", "enabled",
                "Visible", "visible", "Length", "length", "Count", "count")
            for k, w in props
                if (k = prop)
                    return whose "'s " w
            return whose "." prop
        case "Call":
            c := t.FirstChild(i)
            if (t.Type(c) = "Identifier") {
                args := AxSay.Args(r, i)
                nm := t.Value(c)
                static gives := Map("FileRead", "the text of the file {1}", "IniRead", "{3} from {1}",
                    "InputBox", "what the user types", "FileSelect", "a file the user picks", "DirSelect", "a folder the user picks",
                    "StrLen", "the length of {1}", "Trim", "{1} without spaces round it", "StrUpper", "{1} in capitals",
                    "StrLower", "{1} in small letters", "Round", "{1} rounded", "Random", "a random number from {1} to {2}",
                    "FormatTime", "the date and time", "WinGetTitle", "the title of {1}", "ControlGetText", "the text of {1}",
                    "Map", "a new list of pairs", "Array", "a new list", "Integer", "{1} as a whole number", "String", "{1} as text")
                for k, w in gives
                    if (k = nm)
                        return AxSay.Fill(w, args, "")
            }
            return AxStepsRead.OneLine(r.Tx(i))
        case "Grouped":
            c := t.FirstChild(i)
            return c >= 0 ? AxSay.Val(r, c) : "()"
        case "Array":
            return t.ChildCount(i) ? "the list " AxStepsRead.OneLine(r.Tx(i)) : "an empty list"
        case "Object":
            return t.ChildCount(i) ? AxStepsRead.OneLine(r.Tx(i)) : "an empty object"
        }
        return AxStepsRead.OneLine(r.Tx(i))
    }

    ; a condition, said
    static Cond(r, i) {
        t := r.T
        ty := t.Type(i)
        if (ty = "Grouped")
            return AxSay.Cond(r, t.FirstChild(i))
        if (ty = "UnaryExpr" && (t.Value(i) = "!" || StrLower(t.Value(i)) = "not")) {
            c := t.FirstChild(i)
            inner := AxSay.Cond(r, c)
            return (t.Type(c) = "Identifier" || t.Type(c) = "Member") ? inner " is off" : "not (" inner ")"
        }
        if (ty = "BinaryExpr") {
            op := StrLower(t.Value(i))
            a := t.FirstChild(i), b := t.Next(a)
            if (op = "&&" || op = "and")
                return AxSay.Cond(r, a) " and " AxSay.Cond(r, b)
            if (op = "||" || op = "or")
                return AxSay.Cond(r, a) " or " AxSay.Cond(r, b)
            lhs := AxSay.Val(r, a), rhs := AxSay.Val(r, b)
            empty := (t.Type(b) = "String" && (r.Tx(b) = '""' || r.Tx(b) = "''"))
            switch op {
            case "=", "==": return empty ? lhs " is empty" : lhs " is " rhs
            case "!=", "!==", "<>": return empty ? lhs " is not empty" : lhs " is not " rhs
            case ">":  return lhs " is more than " rhs
            case "<":  return lhs " is less than " rhs
            case ">=": return lhs " is at least " rhs
            case "<=": return lhs " is at most " rhs
            case "~=": return lhs " matches " rhs
            case "is": return lhs " is a " rhs
            case "in": return lhs " is in " rhs
            case "contains": return lhs " contains " rhs
            }
            return AxStepsRead.OneLine(r.Tx(i))
        }
        if (ty = "Call") {
            c := t.FirstChild(i)
            if (t.Type(c) = "Identifier") {
                args := AxSay.Args(r, i)
                static conds := Map("InStr", "{1} contains {2}", "FileExist", "the file {1} exists", "DirExist", "the folder {1} exists",
                    "WinExist", "the window {1} exists", "WinActive", "{1} is in front", "GetKeyState", "{1} is held down",
                    "IsSet", "{1} has a value", "RegExMatch", "{1} matches {2}", "IsNumber", "{1} is a number",
                    "IsInteger", "{1} is a whole number", "ProcessExist", "{1} is running", "IsObject", "{1} is an object",
                    "MsgBox", "the answer to {1}")
                for k, w in conds
                    if (k = t.Value(c))
                        return AxSay.Fill(w, args, "")
            }
            return AxSay.Val(r, i)
        }
        if (ty = "Identifier" || ty = "Member")
            return AxSay.Val(r, i)
        return AxStepsRead.OneLine(r.Tx(i))
    }

    ; a change to a value, said
    static Set(r, i) {
        t := r.T
        ty := t.Type(i)
        if (ty = "PostfixExpr" || ty = "UnaryExpr") {
            who := AxSay.Val(r, t.FirstChild(i))
            return (t.Value(i) = "++" ? "Add 1 to " : "Take 1 from ") who
        }
        a := t.FirstChild(i), b := t.Next(a)
        op := t.Value(i)
        who := AxSay.Target(r, a)
        v := AxSay.Val(r, b)
        ; building the window: x := g.AddButton(...) makes a button called x
        if (op = ":=" && t.Type(b) = "Call") {
            cm := t.FirstChild(b)
            if (t.Type(cm) = "Member" && RegExMatch(t.Value(cm), "^Add(\w+)$", &mm))
                return "Make the " AxSay.CtlWord(mm[1]) " " who
            if (t.Type(cm) = "Identifier" && (t.Value(cm) = "AxGui" || t.Value(cm) = "Gui"))
                return "Make the window " who
        }
        switch op {
        case ":=":
            if (r.Tx(a) = "A_Clipboard")
                return "Put " v " on the clipboard"
            ; x := !x
            if (t.Type(b) = "UnaryExpr" && (t.Value(b) = "!" || StrLower(t.Value(b)) = "not") && r.Tx(t.FirstChild(b)) = r.Tx(a))
                return "Switch " who " the other way"
            return "Set " who " to " v
        case "+=": return "Add " v " to " who
        case "-=": return "Take " v " from " who
        case ".=": return "Add " v " to the end of " who
        case "*=": return "Multiply " who " by " v
        case "/=": return "Divide " who " by " v
        }
        return AxStepsRead.OneLine(r.Tx(i))
    }
    static Target(r, i) => AxSay.Val(r, i)

    ; a loop's first line, said
    static LoopHead(r, i) {
        t := r.T
        ty := t.Type(i)
        body := AxStepsRead.BodyOf(t, i)
        heads := []
        for c in t.Children(i)
            if (c != body)
                heads.Push(c)
        if (ty = "While")
            return "Repeat while " AxSay.Cond(r, heads[1])
        if (ty = "For") {
            vars := "", list := ""
            for c in heads
                if (t.Type(c) = "ForVars") {
                    for v in t.Children(c)
                        vars .= (vars = "" ? "" : ", ") t.Value(v)
                } else
                    list := AxSay.Val(r, c)
            return "For each " vars " in " list
        }
        kind := StrLower(t.Value(i))
        switch kind {
        case "files": return "For each file in " (heads.Length ? AxSay.Val(r, heads[1]) : "")
        case "parse": return "For each part of " (heads.Length ? AxSay.Val(r, heads[1]) : "")
        case "read":  return "For each line of the file " (heads.Length ? AxSay.Val(r, heads[1]) : "")
        case "reg":   return "For each registry entry in " (heads.Length ? AxSay.Val(r, heads[1]) : "")
        }
        if !heads.Length
            return "Repeat, until something stops it"
        n := r.Tx(heads[1])
        return "Repeat " (IsInteger(n) ? n " time" (n = 1 ? "" : "s") : AxSay.Val(r, heads[1]) " times")
    }
}

; =============================================================================
;  AxStepsEdit -- a change to a piece, as text: each takes the reading (M)
;  and gives back the piece's new text, or throws with why it cannot.
;  `code` is what the step says in AutoHotkey, one statement, written at no
;  indent; it is indented here to sit where it goes.
; =============================================================================
class AxStepsEdit {
    ; the whole lines a step takes: A the first one's start, B past the last
    ; one's line break (or the end of the piece)
    static Span(M, id) {
        st := M.Steps[id]
        a := M.StartsLine(st.S) ? M.LineStart(st.S) : st.S
        le := M.LineEnd(Max(st.S, st.E - 1))
        b := (le < StrLen(M.Text)) ? le + 1 : le
        return {A: a, B: b, S: st.S, E: st.E, Ind: M.IndentAt(st.S + M.Off), Same: !M.StartsLine(st.S)}
    }
    static Cut(text, a, b, put) => SubStr(text, 1, a) put SubStr(text, b + 1)
    ; code lines at an indent
    static Indent(code, ind) {
        out := ""
        for i, l in StrSplit(StrReplace(code, "`r"), "`n")
            out .= (i > 1 ? "`n" : "") (l != "" ? ind l : "")
        return out
    }
    ; a block of existing lines, moved in by one level
    static Deeper(lines, by := "    ") {
        out := ""
        for i, l in StrSplit(lines, "`n")
            out .= (i > 1 ? "`n" : "") (Trim(l) != "" ? by l : l)
        return out
    }
    static Ends(s) => SubStr(s, -1) = "`n"

    ; ------------------------------------------------------------ add one
    ; into list `key`, before its item number pos+1 (pos = its count: last)
    static Insert(M, key, pos, code) {
        if !M.Lists.Has(key)
            throw Error("That place is not in the code any more.")
        L := M.Lists[key], txt := M.Text
        if (L.Kind = "fixed")
            throw Error("This is a one-line function (=>): it holds one expression, not steps. Change it in the code.")
        n := L.Items.Length
        pos := Max(0, Min(n, pos))
        lines := AxStepsEdit.Indent(code, L.Ind)
        if (L.Kind = "else" || L.Kind = "catch") {
            ; the "otherwise" an if has not got yet, or a try's "catch"
            at := L.End, kw := L.Kind
            closeBrace := SubStr(txt, at, 1) = "}"
            put := (closeBrace ? " " kw " {`n" : "`n" L.OwnerInd kw " {`n") AxStepsEdit.Indent(code, L.OwnerInd "    ")
                 . "`n" L.OwnerInd "}"
            return AxStepsEdit.Cut(txt, at, at, put)
        }
        if (n = 0) {
            if (L.Kind = "root")
                return (Trim(txt) = "") ? lines : txt (AxStepsEdit.Ends(txt) ? "" : "`n") lines
            if (L.Open < 0)
                throw Error("There is nowhere to put a step here.")
            if (L.Open > L.Close)          ; { } on one line
                return AxStepsEdit.Cut(txt, L.Close, L.Close, "`n" lines "`n" L.OwnerInd)
            return AxStepsEdit.Cut(txt, L.Open, L.Open, lines "`n")
        }
        if (L.Kind = "bare" || L.Kind = "same") {
            ; one statement with no braces: braces round it and the new one
            sp := AxStepsEdit.Span(M, L.Items[1])
            if (L.Kind = "bare") {
                old := RTrim(SubStr(txt, sp.A + 1, sp.B - sp.A), "`n")
                body := (pos = 0) ? lines "`n" old : old "`n" lines
                put := L.OwnerInd "{`n" body "`n" L.OwnerInd "}" (sp.B > sp.A && SubStr(txt, sp.B, 1) = "`n" ? "`n" : "")
                return AxStepsEdit.Cut(txt, sp.A, sp.B, put)
            }
            ind := L.OwnerInd "    "
            old := ind Trim(SubStr(txt, sp.S + 1, sp.E - sp.S))
            nl := AxStepsEdit.Indent(code, ind)
            put := "{`n" ((pos = 0) ? nl "`n" old : old "`n" nl) "`n" L.OwnerInd "}"
            return AxStepsEdit.Cut(txt, sp.S, sp.E, put)
        }
        if (pos < n) {
            sp := AxStepsEdit.Span(M, L.Items[pos + 1])
            if sp.Same
                throw Error("A step cannot go in front of one that shares its line.")
            return AxStepsEdit.Cut(txt, sp.A, sp.A, lines "`n")
        }
        sp := AxStepsEdit.Span(M, L.Items[n])
        if (sp.B >= StrLen(txt) && !AxStepsEdit.Ends(txt))
            return txt "`n" lines
        return AxStepsEdit.Cut(txt, sp.B, sp.B, lines "`n")
    }
    ; after a step: into its own list, one place on
    static After(M, id, code) {
        st := M.Steps[id]
        L := M.Lists[st.List]
        for i, x in L.Items
            if (x = id)
                return AxStepsEdit.Insert(M, st.List, i, code)
        throw Error("That step is not in the code any more.")
    }

    ; ------------------------------------------------------------- the rest
    static Delete(M, id) {
        st := M.Steps[id], L := M.Lists[st.List], txt := M.Text
        sp := AxStepsEdit.Span(M, id)
        if (L.Items.Length = 1 && L.Kind = "bare")
            return AxStepsEdit.Cut(txt, sp.A, sp.B, L.OwnerInd "{`n" L.OwnerInd "}" (SubStr(txt, sp.B, 1) = "`n" ? "`n" : ""))
        if (L.Items.Length = 1 && L.Kind = "same")
            return AxStepsEdit.Cut(txt, sp.S, sp.E, "{`n" L.OwnerInd "}")
        if (L.Kind = "fixed")
            throw Error("A one-line function (=>) needs its expression. Change it in the code.")
        return AxStepsEdit.Cut(txt, sp.A, sp.B, "")
    }
    ; the statement (or, for an if or a loop, only its test) replaced
    static Replace(M, id, code) {
        st := M.Steps[id]
        a := st.S, b := st.E
        if st.HasOwnProp("HeadS")
            a := st.HeadS, b := st.HeadE
        ind := M.IndentAt(st.S + M.Off)
        lines := StrSplit(StrReplace(code, "`r"), "`n")
        put := ""
        for i, l in lines
            put .= (i > 1 ? "`n" ind : "") l
        return AxStepsEdit.Cut(M.Text, a, b, put)
    }
    static Move(M, id, d) {
        st := M.Steps[id], L := M.Lists[st.List], txt := M.Text
        if !(L.Kind = "block" || L.Kind = "root" || L.Kind = "case")
            throw Error("It is the only step here.")
        at := 0
        for i, x in L.Items
            if (x = id)
                at := i
        j := at + d
        if (j < 1 || j > L.Items.Length)
            throw Error(d < 0 ? "It is the first step already." : "It is the last step already.")
        one := AxStepsEdit.Span(M, L.Items[Min(at, j)]), two := AxStepsEdit.Span(M, L.Items[Max(at, j)])
        if (one.Same || two.Same)
            throw Error("Those two share a line.")
        x := SubStr(txt, one.A + 1, one.B - one.A), y := SubStr(txt, two.A + 1, two.B - two.A)
        gap := SubStr(txt, one.B + 1, two.A - one.B)
        tail := !AxStepsEdit.Ends(y)
        if tail
            y .= "`n", x := RTrim(x, "`n")
        return SubStr(txt, 1, one.A) y gap x SubStr(txt, two.B + 1)
    }
    ; A step's own text at no indent: what Insert takes, so a step can be
    ; copied or moved to a list at another depth.
    static Plain(M, id) {
        sp := AxStepsEdit.Span(M, id)
        if sp.Same
            return Trim(SubStr(M.Text, sp.S + 1, sp.E - sp.S))
        out := ""
        for i, l in StrSplit(RTrim(SubStr(M.Text, sp.A + 1, sp.B - sp.A), "`n"), "`n")
            out .= (i > 1 ? "`n" : "") ((sp.Ind != "" && SubStr(l, 1, StrLen(sp.Ind)) = sp.Ind) ? SubStr(l, StrLen(sp.Ind) + 1) : LTrim(l, " `t"))
        return out
    }
    ; Anywhere else: into list `key` before its item pos+1, as Insert. Done
    ; as an insert and a cut on the same text, the cut moved along by the
    ; insert when it came first -- so neither has to read the piece again.
    static MoveTo(M, id, key, pos) {
        st := M.Steps[id], sp := AxStepsEdit.Span(M, id)
        if sp.Same
            throw Error("It shares a line with what it is in: move it in the code.")
        if !M.Lists.Has(key)
            throw Error("That place is not in the code any more.")
        ; the same list, next to itself: nothing to do
        if (key = st.List) {
            for i, x in M.Lists[key].Items
                if (x = id && (pos = i - 1 || pos = i))
                    return M.Text
        }
        old := M.Text
        put := AxStepsEdit.Insert(M, key, pos, AxStepsEdit.Plain(M, id))
        ; where the insert changed the text: the common start and end
        n := StrLen(old), k := 0
        while (k < n && SubStr(old, k + 1, 1) == SubStr(put, k + 1, 1))
            k++
        e := 0, pn := StrLen(put)
        while (e < n - k && e < pn - k && SubStr(old, n - e, 1) == SubStr(put, pn - e, 1))
            e++
        ; the stretch of old that was rewritten: touching the step's own
        ; lines means it was put inside itself (or its braces were redrawn)
        a := k, b := n - e
        if (b > sp.A && a < sp.B && !(a = b && (a = sp.A || a = sp.B)))
            throw Error("A step cannot go inside itself. To move it there, do that one in the code.")
        d := pn - n
        return (a <= sp.A) ? AxStepsEdit.Cut(put, sp.A + d, sp.B + d, "") : AxStepsEdit.Cut(put, sp.A, sp.B, "")
    }
    ; the step inside a new "if"
    static Wrap(M, id, cond) {
        sp := AxStepsEdit.Span(M, id), txt := M.Text
        if sp.Same
            throw Error("It shares a line with what it is in: change that in the code.")
        old := SubStr(txt, sp.A + 1, sp.B - sp.A)
        nl := AxStepsEdit.Ends(old)
        old := RTrim(old, "`n")
        put := sp.Ind "if (" cond ") {`n" AxStepsEdit.Deeper(old) "`n" sp.Ind "}" (nl ? "`n" : "")
        return AxStepsEdit.Cut(txt, sp.A, sp.B, put)
    }
}
