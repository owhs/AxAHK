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
        case "alert":    return gv ".Alert(" AxFlow.V(a) ")"
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
        case "call":
            ; "call Speak words" -- a function of yours, or an adaptor from
            ; Libraries, WITH what it needs. It used to be the name alone, so
            ; the one kind of function a rule most wants to call -- an adaptor,
            ; which is a .NET method that takes something -- could not be
            ; called at all from a rule. A flowchart could; a rule could not.
            if (one = "")
                return ""
            return AxFlow.CallCode(project, one, Trim(SubStr(a, StrLen(one) + 1)))
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
            ; "assign page Fetch address" -- keep what a function gives back,
            ; rather than the words "Fetch address". Only when the first word
            ; really is one of this program's functions: everything else is
            ; text, as it always was.
            fn := AxFlow._Word(rest)
            if (fn != "" && IsObject(AxNet.Find(project, fn)))
                return one " := " AxFlow.CallCode(project, fn, Trim(SubStr(rest, StrLen(fn) + 1)))
                     . ", AxBindSync()"
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
        case "goto", "goup", "goback", "goforward", "refresh", "viewmode", "viewsort", "viewfilter",
             "pickall", "pin":
            return AxFlow.FileCode(project, f.Verb, one, Trim(SubStr(a, StrLen(one) + 1)))
        case "ribmode", "ribstyle", "ribdensity", "ribcolour", "ribtab", "ribshowtab", "ribhidetab",
             "ribshowgroup", "ribhidegroup", "ribcheck", "ribuncheck", "ribenable", "ribdisable",
             "ribcollapse", "ribexpand", "ribkeytips", "riblabel":
            return AxFlow.RibbonCode(project, f.Verb, one, Trim(SubStr(a, StrLen(one) + 1)))
        }
        ; a step a library offers (App > Libraries), which also has the
        ; script include that library
        return AxPkg.StepCode(project, w, f)
    }
    ; --- a file window, managed by a rule ------------------------------
    ; Where it is looking, how it is showing it, what it is sorted by. The
    ; explorer hands its state's own methods out, so a rule says the same
    ; thing a line of code would.
    static FileCode(project, verb, name, rest) {
        n := (name != "") ? project.FindByName(name) : ""
        static kinds := "|FileExplorer|FileView|FileTree|FilePath|FilePlaces|FileStatus|FileTools|"
        if (!IsObject(n) || !InStr(kinds, "|" n.Type "|"))
            return ""
        c := name ".Component"
        rest := Trim(rest)
        word := AxFlow._Word(rest)
        after := Trim(SubStr(rest, StrLen(word) + 1))
        switch verb {
        case "goto":       return (rest = "") ? "" : c ".Go(" AxAsset.PathExpr(rest, project) ")"
        case "goup":       return c ".Up()"
        case "goback":     return c ".Back()"
        case "goforward":  return c ".Forward()"
        case "refresh":    return c ".Refresh()"
        case "viewmode":   return (word = "") ? "" : c ".SetMode(" AxLit.S(word) ")"
        case "viewsort":   return (word = "") ? "" : c ".SetSort(" AxLit.S(word) (after != "" ? ", " AxLit.S(after) : "") ")"
        case "viewfilter": return c ".SetFilter(" AxFlow.V(rest) ")"
        case "pickall":    return c ".SelectAll()"
        case "pin":        return (rest = "") ? "" : c ".Pin(" AxAsset.PathExpr(rest, project) ")"
        }
        return ""
    }
    ; --- a ribbon, managed by a rule -----------------------------------
    ; A ribbon is a command surface with forty things on it, and everything
    ; anyone ever does to one is here: what shape it takes, what it looks
    ; like, which contextual tab is showing, which button is in or out.
    ; Without these, the one template with a ribbon in it had to be a page of
    ; hand-written code -- so the richest control in the library showed the
    ; least of what the studio can do.
    ;
    ; `one` is the ribbon's name; `rest` is whatever the verb needs.
    static RibbonCode(project, verb, name, rest) {
        n := (name != "") ? project.FindByName(name) : ""
        if (!IsObject(n) || n.Type != "Ribbon")
            return ""
        c := name ".Component"
        rest := Trim(rest)
        word := AxFlow._Word(rest)
        after := Trim(SubStr(rest, StrLen(word) + 1))
        switch verb {
        case "ribmode":      return (word = "") ? "" : c ".SetMode(" AxLit.S(word) ")"
        case "ribstyle":     return (word = "") ? "" : c ".SetStyle(" AxLit.S(word) ")"
        case "ribdensity":   return (word = "") ? "" : c ".SetDensity(" AxLit.S(word) ")"
        case "ribcolour":    return (word = "") ? "" : c ".SetColor(" AxLit.S(word) ")"
        case "ribtab":       return (word = "") ? "" : c ".ShowTab(" AxLit.S(word) ")"
        case "ribshowtab":   return (word = "") ? "" : c ".ShowContext(" AxLit.S(word) ", true)"
        case "ribhidetab":   return (word = "") ? "" : c ".ShowContext(" AxLit.S(word) ", false)"
        case "ribshowgroup": return (word = "") ? "" : c ".ShowGroup(" AxLit.S(word) ", true)"
        case "ribhidegroup": return (word = "") ? "" : c ".ShowGroup(" AxLit.S(word) ", false)"
        case "ribcheck":     return (word = "") ? "" : c ".Check(" AxLit.S(word) ", true)"
        case "ribuncheck":   return (word = "") ? "" : c ".Check(" AxLit.S(word) ", false)"
        case "ribenable":    return (word = "") ? "" : c ".Enable(" AxLit.S(word) ", true)"
        case "ribdisable":   return (word = "") ? "" : c ".Enable(" AxLit.S(word) ", false)"
        case "ribcollapse":  return c ".Collapse(true)"
        case "ribexpand":    return c ".Collapse(false)"
        case "ribkeytips":   return c ".ToggleKeyTips()"
        case "riblabel":
            ; riblabel rib bold Bolder -- what one button says
            return (word = "" || after = "") ? "" : c ".SetItem(" AxLit.S(word) ", {Label: " AxFlow.V(after) "})"
        }
        return ""
    }
    ; A list managed by a rule: a list view, a tree view, a drop-down or a
    ; list box, by what each of them can do.
    ; The same verbs, for a data view. `rest` is the cells in column order,
    ; separated by | -- the same way a list view's row is written -- and each
    ; one is read as a rule reads any value: a name in braces is what that
    ; control holds, a value's name is that value, anything else is text.
    static DataCode(project, verb, name, n, rest) {
        c := name ".Component"
        switch verb {
        case "clearlist":  return c ".Clear()"
        case "removerow":  return c ".RemoveSelected()"
        case "tickall":    return c ".CheckAll(true)"
        case "untickall":  return c ".CheckAll(false)"
        case "saverows":   return (rest != "") ? c ".SaveTo(" AxAsset.PathExpr(rest, project) ")" : ""
        case "loadrows":   return (rest != "") ? c ".LoadFrom(" AxAsset.PathExpr(rest, project) ")" : ""
        case "folderrows": return (rest != "") ? c ".FillFolder(" AxAsset.PathExpr(rest, project) ")" : ""
        case "addrow":
            ; the columns are read out of the control's own expression, so the
            ; cells land under the right names rather than in a fixed order
            cols := AxGen.DataColumns(n.Arg)
            parts := StrSplit(rest, "|")
            pairs := ""
            for i, col in cols {
                if (i > parts.Length)
                    break
                v := Trim(parts[i])
                if (v = "")
                    continue
                pairs .= (pairs = "" ? "" : ", ") col.Key ": " AxFlow.Cell(project, v)
            }
            if (pairs = "")
                return ""
            ; a Key of its own, so ticking and picking can tell rows apart
            return c ".AddRow({Key: " AxFlow.NewKey() ", " pairs "})"
        }
        return ""
    }
    ; Something no other row will have. A_TickCount alone repeats when two
    ; rows land in the same millisecond, which ticking then cannot tell apart.
    static NewKey() => '"r" A_TickCount "_" (A_Index)'

    static ListCode(project, verb, name, rest) {
        n := (name != "") ? project.FindByName(name) : ""
        if !IsObject(n)
            return ""
        t := n.Type
        rows := (t = "ListView" || t = "TreeView")
        ; A data view is the table this library is actually about -- sortable,
        ; filterable, grouped, ticked -- and a rule could not put a single row
        ; in one. Its methods live on the component rather than on the control,
        ; and its rows are objects with named cells rather than a list of
        ; strings, so it takes its own answer rather than joining the others.
        if (t = "DataView")
            return AxFlow.DataCode(project, verb, name, n, rest)
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
        ; A leading = is an expression, the way a spreadsheet means it. Without
        ; it a cell is text or a control, which is right nine times in ten --
        ; but inside a repeat, the row being added is built out of whatever the
        ; loop is holding (=item.FullName), and there was no way to say so.
        if (SubStr(c, 1, 1) = "=" && StrLen(c) > 1)
            return Trim(SubStr(c, 2))
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
    ; A call to one of this program's functions, and what to give it.
    ;
    ; Arguments are separated by commas, and each is read the way a person
    ; means it: a value's name is that value, a control's name is what the
    ; control holds, a number is a number, and anything else is text. So
    ; "call Speak words" passes the VALUE words rather than the word "words".
    ;
    ; An adaptor set to run in the background hands back the work rather than
    ; the answer, which is no use to a rule -- a rule is one line and has
    ; nowhere to put a handler. WaitFor is wrapped round it: the call still
    ; happens off the AutoHotkey thread, and the window still answers while it
    ; runs, but the rule reads as one thing that finishes.
    static CallCode(project, name, args) {
        nm := AxProject.CleanName(name)
        if (nm = "")
            return ""
        list := ""
        for one in StrSplit(args, ",") {
            one := Trim(one)
            if (one = "")
                continue
            list .= (list = "" ? "" : ", ") AxFlow.Arg(project, one)
        }
        call := nm "(" list ")"
        a := AxNet.Find(project, nm)
        return (IsObject(a) && AxNet.IsAsync(a)) ? "WaitFor(" call ")" : call
    }
    static Arg(project, one) {
        if (SubStr(one, 1, 1) = '"' && SubStr(one, -1) = '"')
            return one
        if (RegExMatch(one, "^-?\d+(\.\d+)?$") || RegExMatch(one, "i)^(true|false)$"))
            return one
        if AxBind.HasVar(project, one)
            return one
        n := project.FindByName(one)
        if IsObject(n)
            return one "." AxFlow.PropOf(project, one)
        return AxLit.S(one)
    }
    static V(v) {
        t := Trim(String(v))
        if (t = "")
            return '""'
        ; "=" means what follows is worked out rather than said: the same
        ; convention a row's cells already use, so there is one rule for it
        ; and not two. It is how a rule reaches the handler's own names --
        ;     rib Toggle:bold -> assign bold =on
        ; -- and how it does arithmetic without a line of code.
        if (SubStr(t, 1, 1) = "=" && SubStr(t, 1, 2) != "==")
            return Trim(SubStr(t, 2))
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
    ; `names` is every global a rule can see -- the controls and the values.
    ; The declaration is built per function rather than once, because a rule
    ; for an event that hands its own parameters on must not declare a global
    ; of the same name: AutoHotkey refuses to load a function that does, and
    ; the parameter is the one that was meant.
    static Funcs(project, w, names) {
        out := ""
        ; The states function takes no parameters, so it declares the lot.
        ; The rule functions build their own below, because each one leaves
        ; out whatever it already has as a parameter.
        all := AxGen._Globals(names, "    ")
        for pair in AxFlow.Pairs(w) {
            body := ""
            base := AxFlow.EvBase(pair.Ev), q := AxFlow.EvQual(pair.Ev)
            args := AxCat.FlowArgs(base), filt := AxCat.Filter(base)
            decl := AxGen._GlobalsBut(names, "    ", args)
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
            out .= AxFlow.StateFn(w) "(name) {`n" all "    switch name {`n"
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
