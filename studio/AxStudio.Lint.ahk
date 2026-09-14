#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\AxStudio.Gen.ahk
#Include %A_LineFile%\..\AxStudio.Flow.ahk
#Include %A_LineFile%\..\AxStudio.Bind.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk

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
;  AxStudio.Lint.ahk -- what is wrong with this design.
;
;  Every rule here is something that was once found the hard way: a control
;  called `log` beside a function called Log() (AutoHotkey refuses both as
;  globals, and the export fails at the last step), a window nothing opens, a
;  handler that was added and never written. The point is to say so while it
;  can still be clicked on, rather than at the bottom of an export dialog.
;
;  A finding is {Sev, Msg, Hint, Win, Node}. Sev is "error" when the script
;  will not run or will not do what the design says, "warn" when it is
;  probably a mistake, and "info" when it is worth knowing.
;
;  Nothing here changes the project. Run() is called on every refresh, so it
;  walks the tree once and keeps out of the way.
; =============================================================================

class AxLint {
    static Run(p) {
        out := []
        AxLint._Names(p, out)
        AxLint._Windows(p, out)
        AxLint._Events(p, out)
        AxLint._Layout(p, out)
        AxLint._Chrome(p, out)
        AxLint._Refs(p, out)
        AxLint._Flows(p, out)
        AxLint._Binds(p, out)
        AxLint._Assets(p, out)
        return out
    }
    static Count(list, sev) {
        n := 0
        for f in list
            if (f.Sev = sev)
                n++
        return n
    }

    ; --- the script's outside ------------------------------------------
    ; Files, includes, arguments, modes and the tray. None of these stop the
    ; script compiling, and every one of them stops it working.
    ; where a listed file is: relative to the project's folder, which is where
    ; the exported script goes (before it is saved, the studio's folder)
    static FilePath(p, path) {
        if (SubStr(path, 1, 1) = "\" || InStr(path, ":\") = 2)
            return path
        if (p.Path != "") {
            SplitPath(p.Path, , &d)
            return d "\" path
        }
        return AxStudioPaths.Root "\" path
    }
    static _Assets(p, out) {
        main := p.Main()
        ; two files under one name would generate two functions with one name
        seen := Map()
        for f in AxAsset.Files(p) {
            key := AxProject.CleanName(f.Name)
            if (key = "") {
                out.Push({Sev: "error", Win: main, Node: "",
                          Msg: "A file called " f.Name " has nothing usable in its name",
                          Hint: f.Line})
                continue
            }
            if seen.Has(key)
                out.Push({Sev: "error", Win: main, Node: "",
                          Msg: "Two files would both become " AxAsset.FileFn(f.Name) "()",
                          Hint: f.Line})
            seen[key] := true
            ; FileInstall needs a path it can read AT COMPILE TIME, and it is
            ; the one thing here that cannot be worked out later
            if (f.How = "install" && InStr(f.Path, "%"))
                out.Push({Sev: "error", Win: main, Node: "",
                          Msg: f.Name " is carried with FileInstall, and its path is worked"
                             . " out at run time",
                          Hint: "FileInstall reads the file when the script is compiled, so"
                              . " the path has to be a literal one."})
            else if (!InStr(f.Path, "%") && !FileExist(AxLint.FilePath(p, f.Path)) && f.How != "path")
                out.Push({Sev: "warn", Win: main, Node: "",
                          Msg: "There is no file at " f.Path " to carry",
                          Hint: "A path without a folder is beside the project file. App > Files says which are there."})
        }
        ; an argument is a global: it cannot be named after a control
        for a in AxAsset.Args(p) {
            if IsObject(p.FindByName(a.Name))
                out.Push({Sev: "error", Win: main, Node: "",
                          Msg: "The argument " a.Name " has the same name as a control",
                          Hint: "Both become globals in one script. Rename one of them."})
            if AxBind.HasVar(p, a.Name)
                out.Push({Sev: "error", Win: main, Node: "",
                          Msg: "The argument " a.Name " has the same name as a value",
                          Hint: a.Line})
        }
        ; a mode's steps use the rule grammar, so the same things can be wrong
        states := Map()
        for st in AxFlow.States(main)
            states[st.Name] := true
        for m in AxAsset.Modes(p) {
            if !m.Steps.Length
                out.Push({Sev: "info", Win: main, Node: "",
                          Msg: "The mode " m.Name " does nothing", Hint: m.Line})
            for step in m.Steps
                AxLint._ModeStep(p, main, m, step, states, out)
        }
        ; and the tray, where switching the icon off is a decision with a catch
        if (Trim(String(p.Tray)) != "") {
            cfg := AxAsset.Tray(p)
            if (!cfg.Show && !main.EscapeCloses && main.ExitOnClose = 0)
                out.Push({Sev: "warn", Win: main, Node: "",
                          Msg: "There is no tray icon, and closing the window does not quit",
                          Hint: "Whoever runs it would have to use the task manager."})
        }
        ; a right-click menu opening on a control that is not there any more
        for w in p.Wins
            for m in AxChrome.Ctx(w.Ctx)
                if (m.On != "" && m.On != "*" && m.On != "window" && !IsObject(p.FindByName(m.On)))
                    out.Push({Sev: "warn", Win: w, Node: "",
                              Msg: "The right-click menu " m.Name " opens on " m.On ", and there is no control called that",
                              Hint: "Logic > Menus: say what it opens on."})
        ; a macro reaching into another window's elements needs the UIA library
        if AxAuto2.UsesUia(p) && !AxPkg.Installed(AxPkg.ProjDir(p)).Has(AxPkg.UiaLib)
            out.Push({Sev: "error", Win: main, Node: "",
                      Msg: "A macro works on another window's elements, and " AxPkg.UiaLib " is not installed for this project",
                      Hint: "App > Libraries installs it."})
        ; adaptors into .NET need AHK# beside the project, and a library's
        ; own adaptors need that library
        have := AxPkg.Installed(AxPkg.ProjDir(p))
        for lib in AxPkg.Used(p)
            if !have.Has(lib) && (lib = AxNet.Lib || (lib = AxPkg.UiaLib && !AxAuto2.UsesUia(p)))
                out.Push({Sev: "error", Win: main, Node: "",
                          Msg: (lib = AxNet.Lib ? "Adaptors into .NET need AHK# (" lib ")" : "Steps in other programs need " lib)
                             . ", and it is not installed for this project",
                          Hint: "App > Libraries > In this program shows it; open it and press Install."})
    }
    static _ModeStep(p, main, m, step, states, out) {
        t := Trim(step)
        i := InStr(t, " ")
        verb := StrLower(i ? SubStr(t, 1, i - 1) : t)
        arg := i ? Trim(SubStr(t, i + 1)) : ""
        static known := "|toast|page|state|hide|show|exit|run|open|"
        if !InStr(known, "|" verb "|") {
            out.Push({Sev: "error", Win: main, Node: "",
                      Msg: "The mode " m.Name " says " verb ", which is not one of the verbs",
                      Hint: "toast, page, state, hide, show, exit, run, open"})
            return
        }
        if (verb = "state" && arg != "" && !states.Has(arg))
            out.Push({Sev: "error", Win: main, Node: "",
                      Msg: "The mode " m.Name " applies the state " arg ", which does not exist",
                      Hint: m.Line})
        if (verb = "open" && arg != "" && !IsObject(p.WinByName(arg)))
            out.Push({Sev: "error", Win: main, Node: "",
                      Msg: "The mode " m.Name " opens " arg ", and there is no such window",
                      Hint: m.Line})
    }

    ; --- names ---------------------------------------------------------
    ; Everything in the generated file is a global in one script: two windows
    ; cannot both have a `list1`, and no control can be called the same as a
    ; function the studio is about to write.
    static _Names(p, out) {
        seen := Map()
        seen.CaseSense := "Off"
        reserved := Map()
        reserved.CaseSense := "Off"
        reserved["g"] := "the main window"
        ; Run adds a debug block to the script (see AxStudio.Debug.ahk), and a
        ; control sharing one of its names breaks F5 while leaving Export fine
        ; -- which is a confusing way to find out.
        for nm in AxDbg.Names
            reserved[nm] := "something Run adds to the script"
        for w in p.Wins {
            reserved[AxGen.InitFn(w)] := w.Name " startup"
            if (w.Kind != "main") {
                reserved[w.Var] := w.Name
                reserved[AxGen.Fn(w)] := "the function that opens " w.Name
                if (w.Kind = "dialog")
                    reserved[AxProject.CleanName(w.Name) "Result"] := w.Name
            }
            ; the binding engine's own names, and every variable -- they are
            ; ordinary globals, so a control called the same thing is the same
            ; clash as a control called the same as a function
            for nm in AxBind.Names
                reserved[nm] := "part of the binding engine"
            for v in AxBind.Vars(p)
                reserved[v.Name] := "a variable"
            ; the rules and states become functions too
            if AxFlow.States(w).Length
                reserved[AxFlow.StateFn(w)] := "the states of " w.Name
            for pair in AxFlow.Pairs(w)
                reserved[AxFlow.FnName(w, pair.Ctl, pair.Ev)] := "a rule on " pair.Ctl
        }
        for w in p.Wins
            p.Walk(w.Root, AxLint._NameFn(p, w, seen, reserved, out))
    }
    ; Every callback below is made by a function that takes the window as a
    ; parameter, rather than written inline in the loop. A closure does not
    ; capture a for-loop control variable in AutoHotkey v2 -- it sees an unset
    ; one and throws on the first walk -- so the window is bound as an
    ; argument, which is why the rest of the studio is written this way too.
    static _NameFn(p, w, seen, reserved, out) => (n) => (AxLint._Name(p, w, n, seen, reserved, out), false)
    static _EvFn(p, w, out) => (n) => (AxLint._Ev(p, w, n, out), false)
    static _LayFn(p, w, abs, out) => (n) => (AxLint._Lay(p, w, n, abs, out), false)
    static _Name(p, w, n, seen, reserved, out) {
        if (n.Type = "Page" && Trim(n.Name) = "")
            return
        nm := Trim(n.Name)
        if (nm = "")
            return
        if (AxProject.CleanName(nm) != nm)
            out.Push({Sev: "error", Win: w, Node: n,
                      Msg: nm " is not a name AutoHotkey can use",
                      Hint: "Letters, digits and underscores, not starting with a digit."})
        if seen.Has(nm) {
            other := seen[nm]
            out.Push({Sev: "error", Win: w, Node: n,
                      Msg: "Two controls are called " nm,
                      Hint: "The other one is in " other ". Both become the same global."})
        } else
            seen[nm] := w.Name
        if reserved.Has(nm)
            out.Push({Sev: "error", Win: w, Node: n,
                      Msg: nm " is already the name of " reserved[nm],
                      Hint: "AutoHotkey will not take a variable and a function with one name."})
    }

    ; --- windows -------------------------------------------------------
    static _Windows(p, out) {
        links := p.Links()
        for w in p.Wins {
            if (w.Kind = "main")
                continue
            reached := false
            for l in links
                if (l.To = w.Name)
                    reached := true
            if !reached
                out.Push({Sev: "warn", Win: w, Node: "",
                          Msg: w.Name " is never opened",
                          Hint: "Nothing calls " AxGen.Fn(w) "(). Windows > Open it from... writes the call."})
            if (w.Kind = "dialog" && Trim(w.Outputs) = "")
                out.Push({Sev: "info", Win: w, Node: "",
                          Msg: w.Name " hands nothing back",
                          Hint: "A modal dialog with no outputs is a message box with extra steps."})
            if (w.Kind != "main" && w.ExitOnClose)
                out.Push({Sev: "warn", Win: w, Node: "",
                          Msg: "Closing " w.Name " ends the whole script",
                          Hint: "Turn off the setting that ends the script when this window closes."})
        }
        empty := 0
        for w in p.Wins
            if !w.Root.Kids.Length
                empty++
        if (empty && p.Wins.Length > 1)
            out.Push({Sev: "info", Win: "", Node: "",
                      Msg: empty " window" (empty = 1 ? " has" : "s have") " nothing in " (empty = 1 ? "it" : "them"),
                      Hint: ""})
    }

    ; --- events --------------------------------------------------------
    static _Events(p, out) {
        for w in p.Wins
            p.Walk(w.Root, AxLint._EvFn(p, w, out))
    }
    static _Ev(p, w, n, out) {
        seen := Map()
        for e in n.Ev {
            if (Trim(e["code"]) = "")
                out.Push({Sev: "warn", Win: w, Node: n,
                          Msg: n.Label " has an empty " e["name"] " handler",
                          Hint: "It will be written as a function that does nothing."})
            if seen.Has(e["name"])
                out.Push({Sev: "error", Win: w, Node: n,
                          Msg: n.Label " has two " e["name"] " handlers",
                          Hint: "Only one of them will be wired up."})
            seen[e["name"]] := true
        }
    }

    ; --- layout --------------------------------------------------------
    static _Layout(p, out) {
        for w in p.Wins {
            abs := []
            p.Walk(w.Root, AxLint._LayFn(p, w, abs, out))
            ; a pair that covers the same ground is nearly always one dragged
            ; onto another by accident
            i := 0
            for a in abs {
                i++
                j := 0
                for b in abs {
                    j++
                    if (j <= i)
                        continue
                    if AxLint._Overlap(a, b)
                        out.Push({Sev: "warn", Win: w, Node: a.N,
                                  Msg: a.N.Label " sits on top of " b.N.Label,
                                  Hint: "Both are placed by hand and their boxes cross."})
                }
            }
        }
    }
    static _Lay(p, w, n, abs, out) {
        if (n.Type = "Page" || n.Type = "Root")
            return
        if (n.Lay("place", "flow") != "abs")
            return
        ; a layout value that was cleared is "", and Integer("") throws
        num := (k) => (n.Lay(k, 0) = "") ? 0 : Integer(n.Lay(k, 0))
        x := num("x"), y := num("y")
        cw := num("w"), ch := num("h")
        if (x < 0 || y < 0 || x > w.Width || y > w.Height)
            out.Push({Sev: "warn", Win: w, Node: n,
                      Msg: n.Label " is placed outside the window",
                      Hint: "At " x ", " y " in a window " w.Width " by " w.Height "."})
        if (cw > 0 && ch > 0)
            abs.Push({N: n, X: x, Y: y, W: cw, H: ch})
    }
    static _Overlap(a, b) {
        return (a.X < b.X + b.W) && (b.X < a.X + a.W)
            && (a.Y < b.Y + b.H) && (b.Y < a.Y + a.H)
    }

    ; --- what the code points at ---------------------------------------
    ; Code outlives the things it mentions. Rename a window and the studio
    ; rewrites the calls, but delete one and every ShowThat() left behind is a
    ; script that will not start -- and the interpreter will not say so until
    ; the export, in a dialog, at the worst possible moment.
    static _Refs(p, out) {
        names := Map()
        names.CaseSense := "Off"
        for w in p.Wins {
            if (w.Kind != "main")
                names[AxGen.Fn(w)] := true
            ; a hand-written ShowSomething() in a script block is a definition,
            ; not a dangling call
            pos := 1
            while (pos := RegExMatch(String(w.Script), "m)^\s*(Show[A-Za-z0-9_]*)\s*\(", &d, pos)) {
                pos += StrLen(d[0])
                names[d[1]] := true
            }
        }
        for w in p.Wins {
            AxLint._RefsIn(p, w, w.Init, "the startup code", names, out)
            AxLint._RefsIn(p, w, w.Script, "your own functions", names, out)
            p.Walk(w.Root, AxLint._RefFn(p, w, names, out))
        }
    }
    static _RefFn(p, w, names, out) => (n) => (AxLint._RefNode(p, w, n, names, out), false)
    static _RefNode(p, w, n, names, out) {
        for e in n.Ev
            AxLint._RefsIn(p, w, e["code"], n.Label " . " e["name"], names, out)
        ; a splitter that resizes a control nobody can find resizes nothing
        if (n.Type = "Splitter") {
            t := Trim(n.Prop("target", ""))
            if (t != "" && !IsObject(p.FindByName(t)))
                out.Push({Sev: "error", Win: w, Node: n,
                          Msg: n.Label " resizes " t ", and there is no such control",
                          Hint: "Pick one again under Actions, or clear the property."})
        }
        ; the generator can only wire a handler to a control it can name
        if (n.Ev.Length && Trim(n.Name) = "" && !n.Box)
            out.Push({Sev: "error", Win: w, Node: n,
                      Msg: n.Label " has a handler but no name",
                      Hint: "There is nothing for the generated code to hook the handler to."})
    }
    static _RefsIn(p, w, code, where, names, out) {
        pos := 1
        ; g.ShowPage() is a method of a window, not a window of the project
        while (pos := RegExMatch(String(code), "(?<![\w.])Show([A-Za-z_][A-Za-z0-9_]*)\s*\(", &m, pos)) {
            pos += StrLen(m[0])
            if names.Has("Show" m[1])
                continue
            out.Push({Sev: "error", Win: w, Node: "",
                      Msg: where " calls Show" m[1] "(), and nothing defines it",
                      Hint: "No window is called " m[1] " -- it was renamed or deleted."
                          . " Windows > Open it from... writes a fresh call."})
        }
    }

    ; --- rules and states ----------------------------------------------
    ; A rule is text, so it can name something that is not there. Saying so is
    ; the difference between a rule that quietly does nothing and one you fix.
    static _Flows(p, out) {
        for w in p.Wins {
            names := Map()
            for s in AxFlow.States(w)
                names[s.Name] := true
            for f in AxFlow.Parse(w)
                AxLint._Flow(p, w, f, names, out)
        }
    }
    static _Flow(p, w, f, states, out) {
        if !IsObject(p.FindByName(f.Ctl))
            out.Push({Sev: "error", Win: w, Node: "",
                      Msg: "A rule starts with " f.Ctl ", and there is no such control",
                      Hint: f.Line})
        else if (AxFlow.Code(p, w, f) = "")
            out.Push({Sev: "warn", Win: w, Node: "",
                      Msg: "A rule does nothing: " f.Line,
                      Hint: "The verb or what follows it is not one the studio knows."})
        if (f.Verb = "state" && !states.Has(AxFlow._Word(f.Arg)))
            out.Push({Sev: "error", Win: w, Node: "",
                      Msg: "A rule asks for the state " AxFlow._Word(f.Arg) ", which is not defined",
                      Hint: f.Line})
        if (f.Verb = "open" && !IsObject(p.WinByName(AxFlow._Word(f.Arg))))
            out.Push({Sev: "error", Win: w, Node: "",
                      Msg: "A rule opens " AxFlow._Word(f.Arg) ", and there is no such window",
                      Hint: f.Line})
        ; a library's step needs the library, installed beside the project
        ; (the macros' ui steps are checked once, in _Assets)
        if IsObject(st := AxPkg.Step(f.Verb)) && !AxPkg.Installed(AxPkg.ProjDir(p)).Has(st.Lib)
            out.Push({Sev: "error", Win: w, Node: "",
                      Msg: "A rule uses " st.Lib ", which is not installed for this project",
                      Hint: f.Line "  --  App > Libraries installs it"})
    }

    ; --- bindings --------------------------------------------------------
    static _Binds(p, out) {
        for w in p.Wins
            for b in AxBind.Binds(w)
                AxLint._Bind(p, w, b, out)
        for v in AxBind.Vars(p)
            if (!v.Derived && v.Expr = "")
                out.Push({Sev: "warn", Win: "", Node: "",
                          Msg: "The variable " v.Name " starts out empty",
                          Hint: v.Line " -- give it a value, even if it is just 0."})
    }
    static _Bind(p, w, b, out) {
        n := p.FindByName(b.Ctl)
        if !IsObject(n) {
            out.Push({Sev: "error", Win: w, Node: "",
                      Msg: "A binding names " b.Ctl ", and there is no such control",
                      Hint: b.Line})
            return
        }
        if !AxBind.HasVar(p, b.Var)
            out.Push({Sev: "error", Win: w, Node: n,
                      Msg: "A binding uses the variable " b.Var ", which is not declared",
                      Hint: b.Line " -- add it under Variables."})
        if (b.Both && AxBind.PullEvent(p, b) = "")
            out.Push({Sev: "warn", Win: w, Node: n,
                      Msg: b.Ctl " cannot be bound both ways",
                      Hint: "It has no Change event, so it will follow " b.Var
                          . " but never write it back."})
        for v in AxBind.Vars(p)
            if (v.Name = b.Var && v.Derived && b.Both)
                out.Push({Sev: "warn", Win: w, Node: n,
                          Msg: b.Var " is worked out from other values, so writing it back does nothing",
                          Hint: b.Line " -- the next sync recomputes it. Use <- instead."})
    }

    ; --- menus, status bars, title bars --------------------------------
    ; Two items under one menu with the same &letter means one of them cannot
    ; be reached from the keyboard, which nothing else will ever tell you.
    static _Chrome(p, out) {
        for w in p.Wins {
            seen := Map()
            seen.CaseSense := "Off"
            for line in StrSplit(StrReplace(String(w.Menus), "`r", ""), "`n") {
                t := Trim(line)
                if (t = "" || t = "-")
                    continue
                top := (SubStr(line, 1, 1) != " " && SubStr(line, 1, 1) != "`t")
                if !top
                    continue
                if !RegExMatch(t, "&(.)", &m)
                    continue
                k := m[1]
                if seen.Has(k)
                    out.Push({Sev: "warn", Win: w, Node: "",
                              Msg: "Two menus answer to Alt+" k " in " w.Name,
                              Hint: t " and " seen[k] "."})
                else
                    seen[k] := t
            }
        }
    }
}
