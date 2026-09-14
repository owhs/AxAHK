#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\AxStudio.Lit.ahk
#Include %A_LineFile%\..\AxStudio.Acts.ahk

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
;  AxStudio.Bind.ahk -- data binding, and the small engine it needs.
;
;  Rules (AxStudio.Flow.ahk) are things that happen once, when something is
;  clicked. A binding is standing: this control and this value are the same
;  thing, and they stay the same thing.
;
;      Variables (the project)         Bindings (this window)
;      who = "World"                   nameBox.Text <-> who
;      loud = 0                        hello.Text <- greeting
;      greeting <- "Hello " who        saveBtn.Enabled <- loud
;
;  `<->` is two way: the control follows the variable, and typing in the
;  control writes it back. `<-` is one way, variable to control. A variable
;  declared with `<-` is derived -- an expression, recomputed on every sync.
;
;  A variable can be an object, and a binding can reach into it:
;
;      Hero = {Name: "Aria", HP: 20, MaxHP: 20, Gold: 0}
;      HpPct <- Round(Hero.HP * 100 / Hero.MaxHP)
;      nameBox <-> Hero.Name          hpBar <- HpPct        gold <- Hero.Gold
;
;  Pushing only writes a control whose value has changed since the last push
;  (AxBindPut): a sync costs nothing for what stayed the same, so a game can
;  sync thirty times a second without laying the page out thirty times.
;
;  THE ENGINE. Variables are ordinary AutoHotkey globals, not entries in a
;  store, which is the decision everything else falls out of:
;
;    * a derived expression is written into the script exactly as you typed
;      it, because `"Hello " who` already means the right thing when `who` is
;      a global. No parser, no rewriting, no eval -- none of which AutoHotkey
;      would have given us anyway.
;    * your own handler code can read and write them like any other variable.
;      Assign one and call AxBindSync() and every bound control catches up.
;
;  Two generated functions do the work. AxBindSync() recomputes every derived
;  variable and pushes every binding out; AxBindPull(name) reads one control
;  back into its variable and then syncs. Sync recomputes *everything* rather
;  than tracking which value depends on which: a window has tens of bindings,
;  not thousands, and a dependency graph that is wrong in one place is far
;  worse than a loop that is a microsecond slower.
;
;  A push can make a control fire its own Change, which would call Pull, which
;  would sync again -- so a flag makes the whole thing re-entrant-safe. It is
;  set and cleared without a try around it on purpose: if a binding throws, the
;  error should surface (in a debug build the Output tab has it) rather than
;  being swallowed to protect a flag.
; =============================================================================

class AxBind {
    ; --- the variables (project-wide, so a dialog can write what the main
    ;     window reads) -------------------------------------------------
    static Vars(p) {
        out := []
        for line in StrSplit(StrReplace(String(p.Vars), "`r", ""), "`n") {
            t := Trim(line)
            if (t = "" || SubStr(t, 1, 1) = ";")
                continue
            if RegExMatch(t, "^([A-Za-z_][A-Za-z0-9_]*)\s*<-\s*(.+)$", &m) {
                out.Push({Name: m[1], Expr: Trim(m[2]), Derived: true, Line: t})
                continue
            }
            if RegExMatch(t, "^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$", &m)
                out.Push({Name: m[1], Expr: Trim(m[2]), Derived: false, Line: t})
        }
        ; The program's own settings are values too: each starts at its first
        ; value, and SettingsLoad puts back what the last run kept (see
        ; AxStudio.Auto2.ahk). They are written in a list of their own, so
        ; they carry no Line here -- the Values table leaves them out.
        if p.HasProp("Settings") {
            seen := Map()
            seen.CaseSense := false
            for v in out
                seen[v.Name] := true
            for line in StrSplit(StrReplace(String(p.Settings), "`r", ""), "`n") {
                f := StrSplit(line, "|", " `t")
                t := Trim(line)
                if (t = "" || SubStr(t, 1, 1) = ";" || !RegExMatch(f[1], "^[A-Za-z_][A-Za-z0-9_]*$") || seen.Has(f[1]))
                    continue
                kind := (f.Length > 2) ? StrLower(f[3]) : "text", d := (f.Length > 1) ? f[2] : ""
                expr := (kind = "onoff" || kind = "startup") ? (InStr("|1|yes|on|true|", "|" StrLower(d) "|") ? "1" : "0")
                      : (kind = "number") ? (IsNumber(d) ? d : "0") : AxLit.S(d)
                seen[f[1]] := true
                out.Push({Name: f[1], Expr: expr, Derived: false, Line: "", Setting: true})
            }
        }
        return out
    }
    ; A name, or a dotted path into an object value: Hero.HP. The first part
    ; must be a value; the next, when the value is written as an object, one
    ; of its fields.
    static HasVar(p, name) {
        parts := StrSplit(name, ".")
        for v in AxBind.Vars(p)
            if (v.Name = parts[1]) {
                if (parts.Length = 1)
                    return true
                f := AxBind.Fields(v.Expr)
                if !f.Length                          ; not an object written out: whatever it holds
                    return true
                for x in f
                    if (x = parts[2])
                        return true
                return false
            }
        return false
    }
    ; The fields of a value written as an object, {Name: "Aria", HP: 20} ->
    ; ["Name", "HP"]: top level only, quotes and nesting skipped over.
    static Fields(expr) {
        out := []
        for f in AxBind.FieldPairs(expr)
            out.Push(f.K)
        return out
    }
    ; ... and with what each starts as: [{K: "Name", V: '"Aria"'}, ...]
    static FieldPairs(expr) {
        out := [], t := Trim(String(expr))
        if (SubStr(t, 1, 1) != "{" || SubStr(t, -1) != "}")
            return out
        t := SubStr(t, 2, -1) ",", depth := 0, q := "", start := true, i := 0, cur := "", from := 0
        while (++i <= StrLen(t)) {
            ch := SubStr(t, i, 1)
            if (q != "") {
                if (ch = "``")
                    i += 1
                else if (ch = q)
                    q := ""
                continue
            }
            if (ch = '"' || ch = "'")
                q := ch
            else if InStr("{[(", ch)
                depth += 1
            else if InStr("}])", ch)
                depth -= 1
            else if (ch = "," && depth = 0) {
                if (cur != "")
                    out.Push({K: cur, V: Trim(SubStr(t, from, i - from))})
                cur := "", start := true
            }
            else if (start && depth = 0 && RegExMatch(t, "A)\s*([A-Za-z_]\w*)\s*:", &m, i)) {
                cur := m[1], i += m.Len - 1, from := i + 1, start := false
            }
        }
        return out
    }
    ; Every name a rule or a binding can pick: each value, and each field of
    ; a value written as an object (Hero, Hero.Name, Hero.HP ...)
    static Paths(p) {
        out := []
        for v in AxBind.Vars(p) {
            out.Push(v.Name)
            for f in AxBind.Fields(v.Expr)
                out.Push(v.Name "." f)
        }
        return out
    }
    static VarNames(p) {
        out := []
        for v in AxBind.Vars(p)
            out.Push(v.Name)
        return out
    }

    ; --- the bindings (per window, because they name its controls) -----
    static Binds(w) {
        out := []
        for line in StrSplit(StrReplace(String(w.Binds), "`r", ""), "`n") {
            t := Trim(line)
            if (t = "" || SubStr(t, 1, 1) = ";")
                continue
            if !RegExMatch(t, "^([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z]+))?\s*(<->|<-)\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_]\w*)*)\s*$", &m)
                continue
            out.Push({Ctl: m[1], Prop: m[2], Var: m[4], Both: (m[3] = "<->"), Line: t})
        }
        return out
    }
    ; The member the binding writes: what was asked for, or whichever one holds
    ; that control's value.
    static PropOf(project, b) {
        if (b.Prop != "")
            return b.Prop
        n := project.FindByName(b.Ctl)
        return IsObject(n) ? AxActs.ValueProp(n.Type) : "Text"
    }
    ; A two-way binding needs an event to hear the control change on.
    static PullEvent(project, b) {
        if !b.Both
            return ""
        n := project.FindByName(b.Ctl)
        if !IsObject(n)
            return ""
        for name in AxCat.Get(n.Type).Events
            if (name = "Change")
                return "Change"
        return ""
    }
    ; Every two-way binding on one control, so the generator knows which
    ; controls need an event wired whether or not they have a handler.
    static PullsFor(project, w, ctlName) {
        out := []
        for b in AxBind.Binds(w)
            if (b.Ctl = ctlName && AxBind.PullEvent(project, b) != "")
                out.Push(b)
        return out
    }
    ; A new value for a control starts at what the control shows now.
    static SeedFor(n) {
        if !IsObject(n)
            return Chr(34) Chr(34)
        if RegExMatch(n.Type, "i)^(CheckBox|Switch)$")
            return n.Prop("checked", 0) ? "1" : "0"
        v := n.Prop("value", "")
        if (v = "" && !RegExMatch(n.Type, "i)^(DDL|ListBox|Radio|Segmented|AutoComplete|Palette|Stepper|Breadcrumb|Tab)$"))
            v := n.Arg
        if (v = "" && RegExMatch(n.Type, "i)^(Number|Slider|Rating|Progress|Gauge)$"))
            v := 0
        if (n.Type = "Stepper" && v = "")
            v := 1
        return IsNumber(v) ? String(v) : AxLit.S(v)
    }
    static Any(project) {
        if AxBind.Vars(project).Length
            return true
        for w in project.Wins
            if AxBind.Binds(w).Length
                return true
        return false
    }

    ; --- what it all becomes -------------------------------------------
    ; A push has to know whether the window holding the control is up: a
    ; window built on demand has unset control variables until it is. Its
    ; own variable is unset too, the first time: the first sync runs at the
    ; top of the script, above the region where `gSettings := ""` is.
    static _Guard(project, w) {
        return (w.Kind = "main") ? "" : "IsSet(" w.Var ") && IsObject(" w.Var ") && !" w.Var ".Closing"
    }
    static Region(project, decl) {
        nl := "`n"
        vars := AxBind.Vars(project)
        s := ""                          ; AxBindBusy is set before AxBindInit runs (AxGen.Script)
        ; the starting values, before anything is shown
        s .= "AxBindInit() {" nl decl
        for v in vars {
            if v.Derived
                continue
            s .= "    " v.Name " := " (v.Expr = "" ? '""' : v.Expr) nl
        }
        if !vars.Length
            s .= "    `; no variables declared yet" nl
        s .= "}" nl nl
        ; recompute, then push
        s .= "AxBindSync() {" nl decl
        s .= "    global AxBindBusy" nl
        s .= "    if AxBindBusy" nl
        s .= "        return" nl
        s .= "    AxBindBusy := true" nl
        any := false
        for v in vars {
            if !v.Derived
                continue
            s .= "    " v.Name " := " v.Expr nl
            any := true
        }
        for w in project.Wins {
            guard := AxBind._Guard(project, w)
            for b in AxBind.Binds(w) {
                ; A binding to a control or a value that is not there -- Logic
                ; shows the row red -- would be a line that stops the script at
                ; start-up. It is left out, and the script says why.
                if (!IsObject(project.FindByName(b.Ctl)) || !AxBind.HasVar(project, b.Var)) {
                    s .= "    `; left out: " b.Ctl " <- " b.Var ", which is not there" nl
                    continue
                }
                line := "AxBindPut(" b.Ctl ", " AxLit.S(AxBind.PropOf(project, b)) ", " b.Var ")"
                s .= (guard = "") ? ("    " line nl)
                                  : ("    if (" guard ")" nl "        " line nl)
                any := true
            }
        }
        if !any
            s .= "    `; nothing bound yet" nl
        s .= "    AxBindBusy := false" nl
        s .= "}" nl nl
        ; and the other direction
        ; the parameter is spelled out of the way of anything a project might
        ; call a variable: a global and a parameter of one name is an error
        s .= "AxBindPull(axWhich) {" nl decl
        s .= "    global AxBindBusy" nl
        s .= "    if AxBindBusy" nl
        s .= "        return" nl
        s .= "    switch axWhich {" nl
        seen := Map()
        for w in project.Wins {
            for b in AxBind.Binds(w) {
                if !b.Both || AxBind.PullEvent(project, b) = ""
                    continue
                if (!IsObject(project.FindByName(b.Ctl)) || !AxBind.HasVar(project, b.Var))
                    continue
                if !seen.Has(b.Ctl)
                    seen[b.Ctl] := []
                seen[b.Ctl].Push(b)
            }
        }
        for ctl, list in seen {
            s .= '    case "' ctl '":' nl
            for b in list
                s .= "        " b.Var " := " ctl "." AxBind.PropOf(project, b) nl
        }
        if !seen.Count
            s .= "    `; nothing is bound both ways yet" nl
        s .= "    }" nl
        s .= "    AxBindSync()" nl
        s .= "}" nl nl
        ; a control is written only when what it would get has changed
        s .= "; A control is written only when its value has changed since the last" nl
        s .= "; push, so a sync costs nothing for what stayed the same." nl
        s .= "AxBindPut(ctl, prop, v) {" nl
        s .= "    static last := Map()" nl
        s .= "    if !last.Has(ctl)" nl
        s .= "        last[ctl] := Map()" nl
        s .= "    was := last[ctl]" nl
        s .= "    if (was.Has(prop) && was[prop] == v)" nl
        s .= "        return" nl
        s .= "    was[prop] := v" nl
        s .= "    ctl.%prop% := v" nl
        s .= "}" nl
        return s
    }
    ; The names the engine puts in the script, so a control cannot take one.
    static Names := ["AxBindBusy", "AxBindInit", "AxBindSync", "AxBindPull", "AxBindPut"]
}
