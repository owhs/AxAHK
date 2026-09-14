#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\AxStudio.Lit.ahk
; Code() asks the generator what a window's variable and builder are called.
; Gen includes this file in turn; #Include loads a file once, so it resolves.
#Include %A_LineFile%\..\AxStudio.Gen.ahk
; and AxActs for the one question both of them ask: which member of a
; control holds its value.
#Include %A_LineFile%\..\AxStudio.Acts.ahk
#Include %A_LineFile%\..\AxStudio.Bind.ahk

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
;  AxStudio.Flow.ahk -- behaviour without writing code, and states to put it in.
;
;  Two text fields per window, authored the same way the menu bar is: one thing
;  per line, and the same text drives the studio and the exported script.
;
;      Flows                                States
;      saveBtn Click -> state busy          busy: saveBtn.Enabled = 0, bar.Visible = 1
;      saveBtn Click -> toast "Saved"       idle: saveBtn.Enabled = 1, bar.Visible = 0
;      nameBox Change -> enable saveBtn
;      helpLink Click -> open Help
;      addBtn Click -> addrow files {nameBox} | {sizeBox} | new
;      delBtn Click -> removerow files
;      saveBtn Click -> saverows files items.txt
;
;  {name} in a row's cells is what the control of that name holds.
;
;  A pack's own events (a game's Tick, Hit and Key) take their handler's
;  parameters into the rule, and can be narrowed to one value of the one the
;  pack names: `world Hit:coin -> add Hero.Gold 1` runs only when the thing
;  hit is tagged coin, and a `do` line can use the handler's own names:
;
;      world Hit:coin -> add Hero.Gold 1
;      world Hit:coin -> do eng.Kill(b)
;      world Key:p -> do eng.Pause(!eng.Paused)
;
;  A value can be an object (Hero = {Name: "Aria", HP: 20}); `assign`, `add`
;  and `take` reach into it by a dotted path, and so does a binding.
;
;  A rule is `<control> <Event> -> <verb> [what]`. A state is a name and a list
;  of control properties to set. Both become plain AutoHotkey: the rules for
;  one control and event become a Flow_ function, and the states become one
;  <Window>State(name) with a switch in it.
;
;  It is not a second way to write handlers -- it is the layer above them. The
;  generated handler calls its Flow_ function first and then runs whatever you
;  typed in the editor, so the two live together and neither overwrites the
;  other. That call is also what Harvest() strips when it reads a script back,
;  so a round trip never mistakes a flow for something you wrote.
;
;  Every verb here emits a call the library actually has. There is deliberately
;  no `log` verb: AxLog only exists in a debug build, and a rule that works
;  under F5 and not in the export would be a trap.
; =============================================================================

class AxFlow {
    ; --- rules ---------------------------------------------------------
    static Parse(w) {
        out := []
        for line in StrSplit(StrReplace(String(w.Flows), "`r", ""), "`n") {
            t := Trim(line)
            if (t = "" || SubStr(t, 1, 1) = ";")
                continue
            if !RegExMatch(t, "^(\S+)\s+(\S+)\s*->\s*(\S+)\s*(.*)$", &m)
                continue
            out.Push({Ctl: m[1], Ev: m[2], Verb: StrLower(m[3]), Arg: Trim(m[4]), Line: t})
        }
        return out
    }
    ; The rules for one control and one event, in the order they were written.
    static For(w, ctlName, event) {
        out := []
        for f in AxFlow.Parse(w)
            if (f.Ctl = ctlName && f.Ev = event)
                out.Push(f)
        return out
    }
    ; The function the generated handler calls first, or "" when there are none.
    static FnName(w, ctlName, event) {
        if !AxFlow.For(w, ctlName, event).Length
            return ""
        q := AxFlow.EvQual(event)
        return "Flow_" AxProject.CleanName(ctlName) "_" AxProject.CleanName(AxFlow.EvBase(event)) (q != "" ? "_" AxProject.CleanName(q) : "")
    }
    ; "Hit:coin" -> "Hit" and "coin"; a plain event has no qualifier
    static EvBase(event) => (p := InStr(event, ":")) ? SubStr(event, 1, p - 1) : event
    static EvQual(event) => (p := InStr(event, ":")) ? SubStr(event, p + 1) : ""
    ; The lines a handler for this event opens with: a call to the rules of
    ; the event itself, then to each narrowed version of it ("Hit:coin").
    ; A pack's event hands its own parameters on.
    static CallsFor(w, ctlName, event) {
        out := [], args := AxCat.FlowArgs(event)
        call := "(" (args != "" ? AxFlow.ArgNames(args) : "") ")"
        for pair in AxFlow.Pairs(w)
            if (pair.Ctl = ctlName && AxFlow.EvBase(pair.Ev) = event)
                out.Push(AxFlow.FnName(w, pair.Ctl, pair.Ev) call)
        return out
    }
    ; "eng, a, b, tag" -> the same, without any defaults or stars
    static ArgNames(sig) {
        out := ""
        for part in StrSplit(sig, ",") {
            n := RegExReplace(Trim(part), "[\s:=*].*$")
            if (n != "")
                out .= (out = "" ? "" : ", ") n
        }
        return out
    }
    ; Every (control, event) pair a window has rules for.
    static Pairs(w) {
        seen := Map(), out := []
        for f in AxFlow.Parse(w) {
            k := f.Ctl "|" f.Ev
            if seen.Has(k)
                continue
            seen[k] := true
            out.Push({Ctl: f.Ctl, Ev: f.Ev})
        }
        return out
    }

    ; --- what one rule becomes ----------------------------------------
    static Code(project, w, f) {
        gv := w.Var
        a := f.Arg
        one := AxFlow._Word(a)
        switch f.Verb {
        case "toast":    return gv ".Toast(" AxFlow.V(a) ")"
        case "close":    return gv ".Close()"
        ; unsaved changes: the title's dot, and what Ask before closing asks about
        case "dirty":    return gv ".Dirty := true"
        case "clean":    return gv ".Dirty := false"
        case "open":
            t := project.WinByName(one)
            return IsObject(t) && t.Kind != "main" ? AxGen.Fn(t) "()" : ""
        case "page":     return gv ".ShowPage(" AxFlow.V(one) ")"
        case "show":     return one != "" ? one ".Visible := true" : ""
        case "hide":     return one != "" ? one ".Visible := false" : ""
        case "enable":   return one != "" ? one ".Enabled := true" : ""
        case "disable":  return one != "" ? one ".Enabled := false" : ""
        case "state":    return one != "" ? AxFlow.StateFn(w) "(" AxFlow.V(one) ")" : ""
        case "run":      return "Run(" AxFlow.V(a) ")"
        case "send":     return "Send(" AxFlow.V(a) ")"
        case "type":     return "SendText(" AxFlow.V(a) ")"
        case "start":    return one != "" ? "TimerStart(" AxFlow.V(one) ")" : ""
        case "stop":     return one != "" ? "TimerStop(" AxFlow.V(one) ")" : ""
        case "beep":     return "SoundBeep()"
        case "wait":     return "Sleep(" (IsNumber(one) ? one : 500) ")"
        case "call":     return one != "" ? AxProject.CleanName(one) "()" : ""
        case "play":     return AxAsset.StepCode(project, "play " one)
        case "startup":  return AxAsset.StepCode(project, "startup " one)
        case "save":     return AxAsset.StepCode(project, "save settings")
        case "reset", "load": return AxAsset.StepCode(project, f.Verb " settings")
        case "assign":
            ; the join between rules and bindings: change the value, and every
            ; control bound to it follows. Setting the control instead would
            ; not, because a programmatic write fires no Change event.
            rest := Trim(SubStr(a, StrLen(one) + 1))
            if (one = "" || !AxBind.HasVar(project, one))
                return ""
            return one " := " AxFlow.V(rest) ", AxBindSync()"
        case "add", "take":
            ; a number up or down: Hero.Gold, Score -- by a number, or by what
            ; another value holds
            rest := Trim(SubStr(a, StrLen(one) + 1))
            if (one = "" || !AxBind.HasVar(project, one))
                return ""
            by := (rest = "") ? "1" : AxFlow.N(project, rest)
            return one (f.Verb = "add" ? " += " : " -= ") by ", AxBindSync()"
        case "do":
            ; one line of AutoHotkey, as written: the escape hatch, and the way
            ; a game's rule reaches the thing it hit (eng.Kill(b))
            return a
        case "status":
            rest := Trim(SubStr(a, StrLen(one) + 1))
            return (one = "") ? "" : gv ".Status(" AxFlow.V(one) ", " AxFlow.V(rest) ")"
        case "set":
            rest := Trim(SubStr(a, StrLen(one) + 1))
            return (one = "") ? "" : one "." AxFlow.PropOf(project, one) " := " AxFlow.V(rest)
        case "copy":
            two := AxFlow._Word(Trim(SubStr(a, StrLen(one) + 1)))
            if (one = "" || two = "")
                return ""
            return two "." AxFlow.PropOf(project, two) " := " one "." AxFlow.PropOf(project, one)
        case "addrow", "removerow", "clearlist", "tickall", "untickall", "saverows", "loadrows", "folderrows":
            return AxFlow.ListCode(project, f.Verb, one, Trim(SubStr(a, StrLen(one) + 1)))
        }
        ; a step a library offers (App > Libraries), which also has the
        ; script include that library
        return AxPkg.StepCode(project, w, f)
    }
    ; A list managed by a rule: a list view, a tree view, a drop-down or a
    ; list box, by what each of them can do.
    static ListCode(project, verb, name, rest) {
        n := (name != "") ? project.FindByName(name) : ""
        if !IsObject(n)
            return ""
        t := n.Type
        rows := (t = "ListView" || t = "TreeView")
        if !(rows || t = "DDL" || t = "ListBox")
            return ""
        ; the path: as written (beside the script unless it says otherwise),
        ; or {box} -- whatever the control of that name holds
        path := RegExMatch(rest, "^\{(\w+)\}$") ? AxFlow.Cell(project, rest) : AxAsset.PathExpr(rest, project)
        switch verb {
        case "addrow":
            cells := []
            for c in StrSplit(rest, "|")
                cells.Push(AxFlow.Cell(project, c))
            if !cells.Length
                cells.Push('""')
            if (t = "ListView") {
                list := ""
                for c in cells
                    list .= ", " c
                return name '.Add(""' list ')'
            }
            if (t = "TreeView")                          ; under the picked one, if any
                return name ".Add(" cells[1] ", " name ".GetSelection())"
            return name ".Add([" cells[1] "])"
        case "removerow":
            return rows ? name ".RemoveSelected()" : ""
        case "clearlist":
            return name ".Delete()"
        case "tickall", "untickall":
            return rows ? name ".TickAll(" (verb = "tickall" ? "true" : "false") ")" : ""
        case "saverows":
            return (rows && rest != "") ? name ".SaveTo(" path ")" : ""
        case "loadrows":
            return (rows && rest != "") ? name ".LoadFrom(" path ")" : ""
        case "folderrows":
            return (rows && rest != "") ? name ".FillFolder(" path ")" : ""
        }
        return ""
    }
    ; One cell of a row a rule adds: {name} is that control's value
    static Cell(project, c) {
        c := Trim(c)
        if RegExMatch(c, "^\{(\w+)\}$", &m) && IsObject(project.FindByName(m[1]))
            return m[1] "." AxFlow.PropOf(project, m[1])
        return AxFlow.V(c)
    }
    ; An amount: a number as it is, a value's name (or a dotted path into
    ; one) as that value, anything else as text.
    static N(project, v) {
        t := Trim(String(v))
        if RegExMatch(t, "^-?\d+(\.\d+)?$")
            return t
        if RegExMatch(t, "^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$") && AxBind.HasVar(project, t)
            return t
        return AxFlow.V(t)
    }
    static _Word(s) {
        return RegExMatch(Trim(s), "^(\S+)", &m) ? m[1] : ""
    }
    ; A value as the user typed it: a number or true/false goes through, an
    ; already-quoted string goes through, and a bare word becomes a string --
    ; which is what makes `toast Saved` and `toast "Saved"` both work.
    static V(v) {
        t := Trim(String(v))
        if (t = "")
            return '""'
        if RegExMatch(t, "^-?\d+(\.\d+)?$") || RegExMatch(t, "i)^(true|false)$")
            return t
        if (SubStr(t, 1, 1) = '"' && SubStr(t, -1) = '"')
            return t
        return AxLit.S(t)
    }
    ; Which member of a control holds its value.
    static PropOf(project, name) {
        n := project.FindByName(name)
        if IsObject(n) && (n.Type = "ListView" || n.Type = "TreeView")
            return "Text"                               ; the picked row's first cell, the picked item
        return IsObject(n) ? AxActs.ValueProp(n.Type) : "Text"
    }

    ; --- states --------------------------------------------------------
    static StateFn(w) => AxProject.CleanName(w.Name) "State"
    static States(w) {
        out := []
        for line in StrSplit(StrReplace(String(w.States), "`r", ""), "`n") {
            t := Trim(line)
            if (t = "" || SubStr(t, 1, 1) = ";")
                continue
            if !RegExMatch(t, "^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$", &m)
                continue
            sets := []
            for part in StrSplit(m[2], ",") {
                if !RegExMatch(Trim(part), "^([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z]+)\s*=\s*(.*)$", &d)
                    continue
                sets.Push({Ctl: d[1], Prop: d[2], Val: Trim(d[3])})
            }
            out.Push({Name: m[1], Sets: sets})
        }
        return out
    }

    ; --- the region ----------------------------------------------------
    ; One Flow_ function per control and event, then the window's states.
    static Funcs(project, w, decl) {
        out := ""
        for pair in AxFlow.Pairs(w) {
            body := ""
            base := AxFlow.EvBase(pair.Ev), q := AxFlow.EvQual(pair.Ev)
            args := AxCat.FlowArgs(base), filt := AxCat.Filter(base)
            ; "Hit:coin": only when the handler's tag is coin
            if (q != "" && filt != "")
                body .= "    if !(" filt " = " AxLit.S(q) ")`n        return`n"
            for f in AxFlow.For(w, pair.Ctl, pair.Ev) {
                c := AxFlow.Code(project, w, f)
                body .= "    " (c = "" ? "`; " f.Line " -- the studio does not know that one" : c) "`n"
            }
            out .= AxFlow.FnName(w, pair.Ctl, pair.Ev) "(" (args != "" ? AxFlow.ArgNames(args) : "") ") {`n" decl body "}`n`n"
        }
        st := AxFlow.States(w)
        if st.Length {
            out .= AxFlow.StateFn(w) "(name) {`n" decl "    switch name {`n"
            for s in st {
                out .= '    case "' s.Name '":`n'
                if !s.Sets.Length
                    out .= "        `; nothing set in this one`n"
                for x in s.Sets
                    out .= "        " x.Ctl "." x.Prop " := " AxFlow.V(x.Val) "`n"
            }
            out .= "    }`n}`n`n"
        }
        return out
    }
    static Any(w) => (AxFlow.Pairs(w).Length || AxFlow.States(w).Length)
}
