#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Lit.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk
#Include %A_LineFile%\..\AxStudio.Bind.ahk
#Include %A_LineFile%\..\AxStudio.Flow.ahk
#Include %A_LineFile%\..\AxStudio.Panes.ahk
#Include %A_LineFile%\..\AxStudio.Form.ahk

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
;  AxStudio.Auto.ahk -- what AutoHotkey is for, kept as lists.
;
;  Conditions, hotstrings and timers, and the settings a script starts with.
;  Each list is text in the project, one thing per line, like rules and
;  hotkeys: Logic shows it as a table you add to, change and take out of,
;  "Edit as text" shows the text, and the export turns it into ordinary
;  AutoHotkey.
;
;      Conds     name | kind | detail
;                notepad | front | ahk_exe notepad.exe
;                working | time | 09:00-17:30
;      Strings   abbreviation | options | where | becomes
;                btw | * | always | by the way
;                sig |  | cond:working | Kind regards,`nMe
;                now | X | always | type the time, toast Typed
;      Timers    name | every | starts | condition | steps
;                clock | 1s | start |  | status clock the time
;
;  A condition is asked when it matters: a hotkey, a hotstring or a timer can
;  say "only when" one holds. Steps -- what a timer, a hotstring or a hotkey
;  does -- are the rule words: toast, open, run, send, type, set, state,
;  start and stop a timer, beep, wait, call, show, hide, front, exit.
; =============================================================================

class AxAuto {
    static Split(line, n) {
        out := []
        for p in StrSplit(line, "|", " `t", n)
            out.Push(Trim(p))
        while (out.Length < n)
            out.Push("")
        return out
    }
    ; the globals a generated function needs: the main window and every value
    static Decl(p) {
        names := "g", seen := Map()
        seen.CaseSense := false
        for v in AxBind.Vars(p)
            names .= ", " v.Name, seen[v.Name] := true
        ; and the main window's controls, which a step can change
        for n in AxAuto.Named(p, p.Main())
            if !seen.Has(n.Name)
                names .= ", " n.Name, seen[n.Name] := true
        return "    global " names "`n"
    }
    static Named(p, w) {
        out := []
        p.Walk(w.Root, AxAuto.NamedFn(out))
        return out
    }
    static NamedFn(out) => (n) => ((n.Type != "Page" && n.Type != "Root" && n.Name != "") ? out.Push(n) : 0, false)
    ; Steps written with a comma between them; a comma inside quotes stays.
    static Steps(text) {
        out := [], cur := "", q := false
        loop parse String(text) {
            c := A_LoopField
            if (c = '"')
                q := !q
            if (c = "," && !q) {
                if (Trim(cur) != "")
                    out.Push(Trim(cur))
                cur := ""
                continue
            }
            cur .= c
        }
        if (Trim(cur) != "")
            out.Push(Trim(cur))
        return out
    }
    static StepsCode(p, steps, pad) {
        s := ""
        for st in steps {
            c := AxAsset.StepCode(p, st)
            s .= pad c "`n"
        }
        return s
    }

    ; ============================================================ conditions
    static CondKinds := "front:A program or a window is in front|notfront:It is not in front|"
                      . "exists:A window is open|value:A value is something|time:It is between two times|"
                      . "key:A key is on, or held down|idle:Nobody has touched the keyboard or mouse for a while|"
                      . "expr:An expression of your own"
    static Conds(p) {
        out := []
        for line in AxAsset.Lines(p.Conds) {
            f := AxAuto.Split(line, 3)
            name := AxProject.CleanName(f[1])
            if (name != "")
                out.Push({Name: name, Kind: StrLower(f[2]), Detail: f[3], Line: line})
        }
        return out
    }
    static HasCond(p, name) {
        for c in AxAuto.Conds(p)
            if (c.Name = name)
                return true
        return false
    }
    static CondExpr(c) {
        d := c.Detail, q := Chr(34)
        switch c.Kind {
        case "front":    return "WinActive(" AxLit.S(d) ")"
        case "notfront": return "!WinActive(" AxLit.S(d) ")"
        case "exists":   return "WinExist(" AxLit.S(d) ")"
        case "value":
            if !RegExMatch(d, "^\s*([A-Za-z_]\w*)\s*(!=|<=|>=|=|<|>|contains)\s*(.*)$", &m)
                return "false"
            if (m[2] = "contains")
                return "InStr(" m[1] ", " AxFlow.V(m[3]) ")"
            return "(" m[1] " " m[2] " " AxFlow.V(m[3]) ")"
        case "time":
            if !RegExMatch(d, "(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})", &m)
                return "false"
            a := Format("{:02}{:02}", m[1], m[2]), b := Format("{:02}{:02}", m[3], m[4])
            now := "(A_Hour A_Min)"
            return (a <= b) ? "(" now " >= " q a q " && " now " < " q b q ")"
                            : "(" now " >= " q a q " || " now " < " q b q ")"
        case "key":
            if !RegExMatch(d, "^(\S+)\s*(\S*)", &m)
                return "false"
            mode := StrLower(m[2])
            return (mode = "held") ? "GetKeyState(" AxLit.S(m[1]) ", " q "P" q ")"
                 : (mode = "off")  ? "!GetKeyState(" AxLit.S(m[1]) ", " q "T" q ")"
                 : "GetKeyState(" AxLit.S(m[1]) ", " q "T" q ")"
        case "idle":
            secs := RegExReplace(d, "[^0-9.]")
            return "(A_TimeIdlePhysical >= " (secs = "" ? 60 : Round(secs * 1000)) ")"
        case "expr":     return Trim(d) != "" ? "(" d ")" : "false"
        }
        return "false"
    }
    static CondWords(c) {
        d := c.Detail
        switch c.Kind {
        case "front":    return d " is in front"
        case "notfront": return d " is not in front"
        case "exists":   return d " is open"
        case "value":    return d
        case "time":     return "between " StrReplace(d, "-", " and ")
        case "key":      return d
        case "idle":     return "idle for " d " seconds"
        case "expr":     return d
        }
        return d
    }
    static CondCode(p) {
        list := AxAuto.Conds(p)
        if !list.Length
            return ""
        s := "; Conditions -- each true or false, asked when it matters: a hotkey," "`n"
           . "; a hotstring or a timer that works only when one holds." "`n"
        decl := AxAuto.Decl(p)
        for c in list
            s .= "Cond_" c.Name "() {`n" decl "    return " AxAuto.CondExpr(c) "`n}`n"
        return s
    }
    ; HotIf and its reset, for "where" on a hotkey or a hotstring
    static Where(where) {
        w := Trim(where)
        if (SubStr(w, 1, 5) = "cond:")
            return ["HotIf((*) => Cond_" AxProject.CleanName(SubStr(w, 6)) "())", "HotIf()"]
        if (SubStr(w, 1, 6) = "front:")
            return ["HotIfWinActive(" AxLit.S(Trim(SubStr(w, 7))) ")", "HotIfWinActive()"]
        if (SubStr(w, 1, 4) = "not:")
            return ["HotIfWinNotActive(" AxLit.S(Trim(SubStr(w, 5))) ")", "HotIfWinNotActive()"]
        return ["", ""]
    }
    static WhereWords(where) {
        w := Trim(where)
        if (SubStr(w, 1, 5) = "cond:")
            return "only when " SubStr(w, 6)
        if (SubStr(w, 1, 6) = "front:")
            return "in " Trim(SubStr(w, 7))
        if (SubStr(w, 1, 4) = "not:")
            return "anywhere but " Trim(SubStr(w, 5))
        return "everywhere"
    }

    ; ============================================================ hotstrings
    static Strings(p) {
        out := []
        for line in AxAsset.Lines(p.Strings) {
            f := AxAuto.Split(line, 4)
            if (f[1] = "")
                continue
            out.Push({Abbr: f[1], Opts: f[2], Where: f[3], Text: f[4],
                      Does: InStr(f[2], "X") ? true : false, Line: line})
        }
        return out
    }
    static StringLine(V) {
        opts := ""
        for k in ["auto", "inside", "case", "omit", "raw"]
            if V[k]
                opts .= Map("auto", "*", "inside", "?", "case", "C", "omit", "O", "raw", "T")[k]
        if (V["kind"] = "steps")
            opts .= "X"
        text := StrReplace(StrReplace(Trim(V["text"], "`r`n"), "`r", ""), "`n", "``n")
        return Trim(V["abbr"]) " | " opts " | " AxAuto.WhereLine(V) " | " text
    }
    static WhereLine(V) {
        switch V["where"] {
        case "front": return "front:" Trim(V["win"])
        case "not":   return "not:" Trim(V["win"])
        case "cond":  return "cond:" Trim(V["cond"])
        }
        return "always"
    }
    static StringCode(p) {
        list := AxAuto.Strings(p)
        if !list.Length
            return ""
        s := "; Hotstrings: type the abbreviation, and it becomes the text -- or does the steps." "`n"
           . "AxHotstrings() {`n"
        fns := ""
        decl := AxAuto.Decl(p)
        for i, h in list {
            ctx := AxAuto.Where(h.Where)
            opts := StrReplace(h.Opts, "X")
            trig := AxLit.S(":" opts ":" h.Abbr)
            if (ctx[1] != "")
                s .= "    " ctx[1] "`n"
            if h.Does {
                s .= "    Hotstring(" trig ", Hotstring_" i ")`n"
                fns .= "Hotstring_" i "(*) {`n" decl AxAuto.StepsCode(p, AxAuto.Steps(h.Text), "    ") "}`n"
            } else
                s .= "    Hotstring(" trig ", " AxLit.S(StrReplace(h.Text, "``n", "`n")) ")`n"
            if (ctx[2] != "")
                s .= "    " ctx[2] "`n"
        }
        return s "}`n" fns
    }

    ; ================================================================ timers
    static Timers(p) {
        out := []
        for line in AxAsset.Lines(p.Timers) {
            f := AxAuto.Split(line, 5)
            name := AxProject.CleanName(f[1])
            if (name = "")
                continue
            ev := AxAuto.Every(f[2])
            out.Push({Name: name, Every: f[2], Ms: ev.Ms, Once: ev.Once, Starts: StrLower(f[3]),
                      Cond: AxProject.CleanName(f[4]), Steps: AxAuto.Steps(f[5]), Text: f[5], Line: line})
        }
        return out
    }
    ; "5s", "250ms", "2 min", "1h", "once 10s" -> milliseconds, and whether once
    static Every(t) {
        t := Trim(StrLower(t)), once := false
        if (SubStr(t, 1, 5) = "once ")
            once := true, t := Trim(SubStr(t, 6))
        ms := 1000
        if RegExMatch(t, "^(\d+(?:\.\d+)?)\s*(ms|s|sec|m|min|h)?$", &m) {
            u := m[2]
            ms := Round(m[1] * ((u = "ms") ? 1 : (u = "m" || u = "min") ? 60000 : (u = "h") ? 3600000 : 1000))
        }
        return {Ms: Max(10, ms), Once: once}
    }
    static EveryWords(t) {
        e := AxAuto.Every(t.Every)
        n := e.Ms, w := (n >= 3600000 && Mod(n, 3600000) = 0) ? (n // 3600000) " h"
                     : (n >= 60000 && Mod(n, 60000) = 0) ? (n // 60000) " min"
                     : (n >= 1000 && Mod(n, 1000) = 0) ? (n // 1000) " s" : n " ms"
        return (e.Once ? "once, after " : "every ") w
    }
    static TimerCode(p) {
        list := AxAuto.Timers(p)
        if !list.Length
            return ""
        decl := AxAuto.Decl(p)
        s := "; Timers. TimerStart(" Chr(34) "name" Chr(34) ") and TimerStop(...) from anywhere." "`n"
        m := ""
        for t in list {
            s .= "Timer_" t.Name "() {`n" decl
            if (t.Cond != "")
                s .= "    if !Cond_" t.Cond "()`n        return`n"
            s .= AxAuto.StepsCode(p, t.Steps, "    ") "}`n"
            m .= (m = "" ? "" : ", ") Chr(34) t.Name Chr(34) ", [Timer_" t.Name ", " (t.Once ? -t.Ms : t.Ms) "]"
        }
        s .= "TimerStart(name, on := true) {`n"
           . "    static all := Map(" m ")`n"
           . "    if all.Has(name)`n"
           . "        SetTimer(all[name][1], on ? all[name][2] : 0)`n"
           . "}`n"
           . "TimerStop(name) => TimerStart(name, false)`n"
        return s
    }
    ; what runs at start: hotstrings made, timers that start with it started
    static StartCode(p) {
        s := ""
        if AxAuto.Strings(p).Length
            s .= "AxHotstrings()`n"
        for t in AxAuto.Timers(p)
            if (t.Starts = "start")
                s .= "SetTimer(Timer_" t.Name ", " (t.Once ? -t.Ms : t.Ms) ")`n"
        return s
    }

    ; ======================================================= script settings
    ; Kept in the same name = value text the Compile form writes (App > Details).
    static SettingsCode(p) {
        cfg := AxAsset.Compile(p)
        G := (k, d := "") => (cfg.Has(k) && cfg[k] != "") ? cfg[k] : d
        nl := "`n", s := ""
        if AxAsset.Truthy(G("usehook", 0))
            s .= "#UseHook" nl
        if AxAsset.Truthy(G("admin", 0))
            s .= AxAuto.AdminBlock
        if (G("sendmode") != "" && G("sendmode") != "Input")
            s .= "SendMode(" AxLit.S(G("sendmode")) ")" nl
        if (G("titlematch") != "" && G("titlematch") != "2")
            s .= "SetTitleMatchMode(" (G("titlematch") = "RegEx" ? AxLit.S("RegEx") : G("titlematch")) ")" nl
        if AxAsset.Truthy(G("hidden", 0))
            s .= "DetectHiddenWindows(true)" nl
        if (G("coord") != "" && G("coord") != "Client")
            s .= "CoordMode(" AxLit.S("Mouse") ", " AxLit.S(G("coord")) "), CoordMode(" AxLit.S("Pixel") ", " AxLit.S(G("coord")) ")" nl
        ; on unless turned off: a file named without a folder is looked for
        ; beside the script, however it was started
        if AxAsset.Truthy(G("workdir", 1))
            s .= "SetWorkingDir(A_ScriptDir)" nl
        if AxAsset.Truthy(G("nohistory", 0))
            s .= "KeyHistory(0)" nl
        if (G("maxhk") != "" && IsInteger(G("maxhk")))
            s .= "A_MaxHotkeysPerInterval := " Integer(G("maxhk")) nl
        if (G("priority") != "" && G("priority") != "Normal")
            s .= "ProcessSetPriority(" AxLit.S(G("priority")) ")" nl
        return s
    }
    static AdminBlock := "
(`
; It runs as administrator: started without, it starts itself again with, and
; this copy stops. Its arguments go along with it.
if !A_IsAdmin && !RegExMatch(DllCall("GetCommandLine", "Str"), " /restart(?!\S)") {
    AxAdminArgs := ""
    for AxAdminArg in A_Args
        AxAdminArgs .= ' "' AxAdminArg '"'
    try {
        if A_IsCompiled
            Run('*RunAs "' A_ScriptFullPath '" /restart' AxAdminArgs)
        else
            Run('*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"' AxAdminArgs)
    }
    ExitApp()
}

)"
}

; =============================================================================
;  The Logic sections and the forms for them.
; =============================================================================
class AxAutoUi {
    static CondOpts(p, none := true) {
        s := none ? AxPanes.NONE ":(always)" : ""
        for c in AxAuto.Conds(p)
            s .= (s = "" ? "" : "|") c.Name ":" c.Name
        return s
    }
    ; ------------------------------------------------------------- sections
    static Conds(s, add) {
        list := AxAuto.Conds(s.P)
        rows := ""
        for c in list
            rows .= '<tr><td class="axd-lgname" data-row="edit|' AxTags.E("conditions|" c.Line) '">'
                 .  '<span class="ico">&#xE9D5;</span>' AxTags.E(c.Name) '</td>'
                 .  '<td>' AxTags.E(AxAuto.CondWords(c)) '</td>'
                 .  '<td class="axd-mono axd-dim">Cond_' AxTags.E(c.Name) '()</td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("conditions", c.Line) '</td></tr>'
        list2 := (rows = "") ? "" : AxLogic.Table(["Condition", "True when", "In code", ""], rows)
        raw := add({Id: "lg_conds", L: "One per line", Kind: "multiline", Rows: 5,
                    Get: (*) => s.P.Conds, Set: (v) => (s.P.Conds := v, s.QueueLive())})
             . '<div class="axd-note"><b>name | kind | detail</b> -- kinds are front, notfront, exists, '
             . 'value, time, key, idle and expr.</div>'
        return AxLogic.Wrap(s, "conditions", "Conditions (" list.Length ")",
            '<span class="axd-hbtn" data-do="cond.add">Add a condition...</span>', list2, raw,
            "Named yes-or-no questions -- a program is in front, it is working hours, CapsLock is on "
            . "-- that hotkeys, hotstrings and timers can be made to wait for.")
    }
    static Strings(s, add) {
        list := AxAuto.Strings(s.P)
        rows := ""
        for h in list {
            what := h.Does ? "does: " h.Text : StrReplace(h.Text, "``n", " / ")
            rows .= '<tr><td class="axd-lgname" data-row="edit|' AxTags.E("hotstrings|" h.Line) '">'
                 .  '<span class="ico">&#xE8D2;</span>' AxTags.E(h.Abbr) '</td>'
                 .  '<td>' AxTags.E(SubStr(what, 1, 80)) '</td>'
                 .  '<td><span class="axd-dim">' AxTags.E(AxAutoUi.OptWords(h.Opts)) '</span></td>'
                 .  '<td><span class="axd-dim">' AxTags.E(AxAuto.WhereWords(h.Where)) '</span></td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("hotstrings", h.Line) '</td></tr>'
        }
        list2 := (rows = "") ? "" : AxLogic.Table(["Type", "Becomes", "How", "Works", ""], rows)
        raw := add({Id: "lg_strings", L: "One per line", Kind: "multiline", Rows: 5,
                    Get: (*) => s.P.Strings, Set: (v) => (s.P.Strings := v, s.QueueLive())})
             . '<div class="axd-note"><b>abbreviation | options | where | text</b> -- options are '
             . 'AutoHotkey&#39;s (* ? C O T), and X makes the text steps. Where is always, '
             . 'front:<i>window</i>, not:<i>window</i> or cond:<i>name</i>.</div>'
        return AxLogic.Wrap(s, "hotstrings", "Typed shortcuts (" list.Length ")",
            '<span class="axd-hbtn" data-do="hs.add">Add a typed shortcut...</span>', list2, raw,
            "Type a few letters anywhere and they become something longer -- a signature, an "
            . "address, today's date -- or do the steps you give them. (AutoHotkey calls these hotstrings.)")
    }
    static OptWords(o) {
        w := ""
        for pair in [["*", "at once"], ["?", "inside words"], ["C", "case matters"], ["O", "no end key"], ["T", "raw"]]
            if InStr(o, pair[1], true)
                w .= (w = "" ? "" : ", ") pair[2]
        return w = "" ? "after a space or Enter" : w
    }
    static Timers(s, add) {
        list := AxAuto.Timers(s.P)
        rows := ""
        for t in list {
            bad := (t.Cond != "" && !AxAuto.HasCond(s.P, t.Cond)) ? "there is no condition " t.Cond : ""
            rows .= '<tr' (bad != "" ? ' class="axd-badrow"' : "") '><td class="axd-lgname" data-row="edit|'
                 .  AxTags.E("timers|" t.Line) '"><span class="ico">&#xE916;</span>' AxTags.E(t.Name) '</td>'
                 .  '<td>' AxTags.E(AxAuto.EveryWords(t)) '</td>'
                 .  '<td>' AxTags.E(t.Text) (bad != "" ? '<br><span class="axd-lgerr">' AxTags.E(bad) '</span>' : "") '</td>'
                 .  '<td><span class="axd-dim">' (t.Starts = "start" ? "with the program" : "when started")
                 .  (t.Cond != "" ? ", only when " AxTags.E(t.Cond) : "") '</span></td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("timers", t.Line) '</td></tr>'
        }
        list2 := (rows = "") ? "" : AxLogic.Table(["Timer", "When", "Does", "Runs", ""], rows)
        raw := add({Id: "lg_timers", L: "One per line", Kind: "multiline", Rows: 4,
                    Get: (*) => s.P.Timers, Set: (v) => (s.P.Timers := v, s.QueueLive())})
             . '<div class="axd-note"><b>name | every | starts | condition | steps</b> -- every is '
             . '5s, 250ms, 2min or once 10s; starts is start or manual.</div>'
        return AxLogic.Wrap(s, "timers", "Timers (" list.Length ")",
            '<span class="axd-hbtn" data-do="timer.add">Add a timer...</span>', list2, raw,
            "Things that happen by themselves: every so often, or once after a while. A rule, a "
            . "hotkey or your code starts and stops one by name.")
    }

    ; ---------------------------------------------------------------- forms
    static StepHint := "Steps, with commas between: toast Saved, open Settings, run notepad.exe, "
                    . "send ^c, type Hello, set count 5, state busy, start clock, stop clock, wait 500, "
                    . "beep, message Done, notify Saved, activate Notepad, call MyFunction, show, hide, front, exit."
    static Cond(s, old := "") {
        O := (k, d) => IsObject(old) ? old.%k% : d
        r := AxForm.Show(s, {Title: IsObject(old) ? "Change a condition" : "Add a condition", Icon: "E9D5", Width: 520,
            Intro: "A named question with a yes or no answer, asked each time something depends on it.",
            Fields: [
                {Id: "name", L: "Called", Kind: "text", V: O("Name", "notepadFront")},
                {Id: "kind", L: "True when", Kind: "choice", V: O("Kind", "front"), Opts: AxAuto.CondKinds},
                {Id: "detail", L: "Which", Kind: "text", V: O("Detail", "ahk_exe notepad.exe"),
                 Hint: "front / not in front / open: a window -- ahk_exe notepad.exe, ahk_class Notepad, some "
                     . "title text.  A value: count > 3, theme = dark.  Times: 09:00-17:30.  A key: CapsLock on, "
                     . "Shift held.  Idle: seconds.  Expression: anything AutoHotkey reads as true."}],
            Buttons: [IsObject(old) ? "Save" : "Add it", "Cancel"],
            Check: (V) => AxProject.CleanName(V["name"]) = "" ? "Enter a name." : Trim(V["detail"]) = "" ? "Say which." : "",
            Preview: (V) => "Cond_" AxProject.CleanName(V["name"]) "() => " AxAuto.CondExpr({Kind: V["kind"], Detail: Trim(V["detail"])})})
        if !r.Ok
            return
        s.PutLine("Conds", IsObject(old) ? old.Line : "",
                  AxProject.CleanName(r.V["name"]) " | " r.V["kind"] " | " Trim(r.V["detail"]))
        s.LogicSec := "conditions"
        s.Refresh()
    }
    static Hotstring(s, old := "") {
        O := (k, d) => IsObject(old) ? old.%k% : d
        opts := O("Opts", "")
        w := O("Where", "always"), wk := (SubStr(w, 1, 6) = "front:") ? "front" : (SubStr(w, 1, 4) = "not:") ? "not"
             : (SubStr(w, 1, 5) = "cond:") ? "cond" : "always"
        wv := (wk = "front") ? SubStr(w, 7) : (wk = "not") ? SubStr(w, 5) : ""
        cv := (wk = "cond") ? SubStr(w, 6) : ""
        conds := AxAutoUi.CondOpts(s.P, false)
        r := AxForm.Show(s, {Title: IsObject(old) ? "Change a hotstring" : "Add a hotstring", Icon: "E8D2", Width: 560,
            Intro: "Type the abbreviation anywhere, and it becomes the text -- or does the steps.",
            Fields: [
                {Id: "abbr", L: "When you type", Kind: "text", V: O("Abbr", "btw")},
                {Id: "kind", L: "It", Kind: "seg", V: InStr(opts, "X") ? "steps" : "text",
                 Opts: "text:Becomes text|steps:Does steps"},
                {Id: "text", L: "Becomes", Kind: "multiline", Rows: 3, V: StrReplace(O("Text", "by the way"), "``n", "`n"),
                 Hint: "Text can run over several lines.", When: (V) => V["kind"] = "text"},
                {Id: "text2", L: "Does", Kind: "text", V: InStr(opts, "X") ? O("Text", "") : "type the date, beep",
                 Hint: AxAutoUi.StepHint, When: (V) => V["kind"] = "steps"},
                {Id: "h1", L: "How", Kind: "heading"},
                {Id: "auto", L: "At once, without a space or Enter after it", Kind: "flag", V: InStr(opts, "*") ? 1 : 0},
                {Id: "inside", L: "Inside other words too", Kind: "flag", V: InStr(opts, "?") ? 1 : 0},
                {Id: "case", L: "Only in the same capitals", Kind: "flag", V: InStr(opts, "C", true) ? 1 : 0},
                {Id: "omit", L: "Leave out the space or Enter that set it off", Kind: "flag", V: InStr(opts, "O", true) ? 1 : 0},
                {Id: "raw", L: "Send the text exactly, braces and all", Kind: "flag", V: InStr(opts, "T", true) ? 1 : 0},
                {Id: "h2", L: "Where", Kind: "heading"},
                {Id: "where", L: "Works", Kind: "choice", V: wk,
                 Opts: "always:Everywhere|front:Only in one program|not:Everywhere but one program"
                     . (conds != "" ? "|cond:Only when a condition holds" : "")},
                {Id: "win", L: "That program", Kind: "text", V: wv != "" ? wv : "ahk_exe notepad.exe",
                 When: (V) => V["where"] = "front" || V["where"] = "not"},
                {Id: "cond", L: "Condition", Kind: "choice", V: cv, Opts: conds != "" ? conds : "-:(none)",
                 When: (V) => V["where"] = "cond"}],
            Buttons: [IsObject(old) ? "Save" : "Add it", "Cancel"],
            Check: (V) => (Trim(V["abbr"]) = "") ? "Say what you type." : InStr(V["abbr"], "|") ? "An abbreviation cannot hold a |." : "",
            Preview: (V) => AxAutoUi.HsPreview(V)})
        if !r.Ok
            return
        s.PutLine("Strings", IsObject(old) ? old.Line : "", AxAutoUi.HsLine(r.V))
        s.LogicSec := "hotstrings"
        s.Refresh()
        s.Status("msg", "Hotstring " Trim(r.V["abbr"]) " -- in Logic, under Hotstrings.")
    }
    static HsPreview(V) {
        f := AxAuto.Split(AxAutoUi.HsLine(V), 4)
        ctx := AxAuto.Where(f[3])
        return (ctx[1] != "" ? ctx[1] "`n" : "") "Hotstring(" AxLit.S(":" StrReplace(f[2], "X") ":" f[1]) ", "
             . (V["kind"] = "steps" ? "...steps" : AxLit.S(SubStr(V["text"], 1, 40))) ")"
    }
    static HsLine(V) {
        m := Map()
        for k in ["abbr", "kind", "auto", "inside", "case", "omit", "raw", "where", "win", "cond"]
            m[k] := V[k]
        m["text"] := (V["kind"] = "steps") ? V["text2"] : V["text"]
        return AxAuto.StringLine(m)
    }
    static Timer(s, old := "") {
        O := (k, d) => IsObject(old) ? old.%k% : d
        conds := AxAutoUi.CondOpts(s.P)
        e := AxAuto.Every(O("Every", "5s"))
        r := AxForm.Show(s, {Title: IsObject(old) ? "Change a timer" : "Add a timer", Icon: "E916", Width: 540,
            Intro: "Something that happens by itself, every so often or once after a while.",
            Fields: [
                {Id: "name", L: "Called", Kind: "text", V: O("Name", "clock")},
                {Id: "once", L: "It happens", Kind: "seg", V: e.Once ? "once" : "every",
                 Opts: "every:Every|once:Once, after"},
                {Id: "every", L: "How long", Kind: "text", V: RegExReplace(O("Every", "5s"), "i)^once\s+"),
                 Hint: "250ms, 5s, 2min, 1h"},
                {Id: "steps", L: "Does", Kind: "text", V: O("Text", "toast Tick"), Hint: AxAutoUi.StepHint},
                {Id: "starts", L: "Starts", Kind: "seg", V: O("Starts", "start") = "manual" ? "manual" : "start",
                 Opts: "start:With the program|manual:When something starts it"},
                {Id: "cond", L: "Only when", Kind: "choice", V: (O("Cond", "") = "") ? AxPanes.NONE : O("Cond", ""), Opts: conds}],
            Buttons: [IsObject(old) ? "Save" : "Add it", "Cancel"],
            Check: (V) => AxProject.CleanName(V["name"]) = "" ? "Enter a name." : Trim(V["steps"]) = "" ? "Say what it does." : "",
            Preview: (V) => "SetTimer(Timer_" AxProject.CleanName(V["name"]) ", "
                          . (V["once"] = "once" ? "-" : "") AxAuto.Every(V["every"]).Ms ")"})
        if !r.Ok
            return
        c := (r.V["cond"] = AxPanes.NONE) ? "" : r.V["cond"]
        line := AxProject.CleanName(r.V["name"]) " | " (r.V["once"] = "once" ? "once " : "") Trim(r.V["every"])
              . " | " r.V["starts"] " | " c " | " Trim(r.V["steps"])
        s.PutLine("Timers", IsObject(old) ? old.Line : "", line)
        s.LogicSec := "timers"
        s.Refresh()
        s.Status("msg", "Timer " AxProject.CleanName(r.V["name"]) (r.V["starts"] = "start" ? " starts with the program."
                      : " -- start it with a rule or a hotkey: start " AxProject.CleanName(r.V["name"]) "."))
    }

    ; ------------------------------------------------------ script settings
    static Settings(s, add) {
        cfg := AxAsset.Compile(s.P)
        G := (k, d := "") => (cfg.Has(k) && cfg[k] != "") ? cfg[k] : d
        F := (k) => AxPanes.CompileFn(s, k)
        B := (k) => (v) => AxAsset.SetCompile(s.P, k, v ? "1" : "")
        sub := (t) => '<div class="axd-rpsub">' t '</div>'
        ; Every setting says what it changes for the person using the program,
        ; in the words they would use. One that changed nothing anyone could
        ; notice would not be here.
        return sub("Starting")
             . add({Id: "sc_admin", L: "Run as administrator", Kind: "flag", Get: (*) => AxAsset.Truthy(G("admin", 0)), Set: B("admin"),
                    Desc: "Needed to click, type into or read windows of programs that run as administrator (Task Manager, installers, "
                        . "some games). Windows shows its yes/no prompt each time the program starts."})
             . add({Id: "sc_startup", L: "Start with Windows", Kind: "flag", Get: (*) => AxAsset.Truthy(G("startup", 0)), Set: B("startup"),
                    Desc: "Starts by itself when you sign in to Windows. To let whoever uses it choose, add a "
                        . "<b>start with Windows</b> setting under Logic &gt; Settings instead."})
             . add({Id: "sc_workdir", L: "Find files beside the program", Kind: "flag", Get: (*) => AxAsset.Truthy(G("workdir", 1)),
                    Set: (v) => AxAsset.SetCompile(s.P, "workdir", v ? "1" : "0"),
                    Desc: "A file named without a folder -- <b>notes.txt</b> -- is looked for in the program's own folder, even when "
                        . "it was started from a shortcut or from somewhere else. Turned off, it is looked for wherever it was started from."})
             . add({Id: "sc_setin", L: "Save its settings", Kind: "choice", Get: (*) => G("settingsin", "beside"), Set: F("settingsin"),
                    Opts: "beside:Beside the program, in a .ini|appdata:In the user's AppData folder",
                    Desc: "Where the choices made under Logic &gt; Settings are kept. AppData suits a program installed in a folder "
                        . "the user cannot write to, such as Program Files."})
             . add({Id: "sc_prio", L: "Speed when the computer is busy", Kind: "choice", Get: (*) => G("priority", "Normal"), Set: F("priority"),
                    Opts: "Normal:Normal|AboveNormal:A little ahead of other programs|High:Ahead of other programs|BelowNormal:Behind other programs|Low:Only when nothing else wants it",
                    Desc: "How Windows shares the computer between this and everything else running. Leave it at Normal "
                        . "unless the program must keep up while something heavy runs."})
             . sub("Keys and hotkeys")
             . add({Id: "sc_send", L: "How keys are typed", Kind: "choice", Get: (*) => G("sendmode", "Input"), Set: F("sendmode"),
                    Opts: "Input:All at once -- fastest, suits nearly everything|Event:One at a time -- for a program that drops keys|"
                        . "Play:The way games like it|InputThenPlay:All at once, or the games way if that is blocked",
                    Desc: "When a step types text or presses keys in another program. Change it only if a program misses keys "
                        . "or ignores them."})
             . add({Id: "sc_hook", L: "Hotkeys cannot set themselves off", Kind: "flag", Get: (*) => AxAsset.Truthy(G("usehook", 0)), Set: B("usehook"),
                    Desc: "A hotkey that presses its own key -- F1 that sends F1 -- would otherwise start itself again and again. "
                        . "It also lets hotkeys work in a few programs that swallow them."})
             . add({Id: "sc_maxhk", L: "Warn when hotkeys go wild", Kind: "num", Get: (*) => G("maxhk"), Set: F("maxhk"), Hint: "70",
                    Desc: "If hotkeys fire more than this many times in two seconds, the program stops and asks whether to carry on "
                        . "-- in case one is stuck in a loop. Raise it for a hotkey held down or on the mouse wheel. Blank: 70."})
             . add({Id: "sc_nohist", L: "Keep typing private", Kind: "flag", Get: (*) => AxAsset.Truthy(G("nohistory", 0)), Set: B("nohistory"),
                    Desc: "AutoHotkey keeps a list of the last keys pressed, which anyone can open from the tray icon's menu. "
                        . "Turn this on for a program that sees passwords."})
             . sub("Finding windows and places")
             . add({Id: "sc_title", L: "A window name matches", Kind: "choice", Get: (*) => G("titlematch", "2"), Set: F("titlematch"),
                    Opts: "2:If it is anywhere in the title|1:If the title starts with it|3:Only the exact title|RegEx:As a pattern (regular expression)",
                    Desc: "When a hotkey, rule or macro names a window -- <b>Notepad</b> -- which titles count as that window."})
             . add({Id: "sc_hidden", L: "Find hidden windows too", Kind: "flag", Get: (*) => AxAsset.Truthy(G("hidden", 0)), Set: B("hidden"),
                    Desc: "Steps that look for a window also find ones that are not on screen, such as a program sitting in the tray."})
             . add({Id: "sc_coord", L: "Count mouse positions from", Kind: "choice", Get: (*) => G("coord", "Client"), Set: F("coord"),
                    Opts: "Client:The inside of the window|Window:The window's top-left corner|Screen:The top-left of the screen",
                    Desc: "When a step clicks at a place, or looks at a pixel, where 0, 0 is. The inside of the window leaves out "
                        . "its title bar, so a click lands in the same place however the window is styled."})
             . '<div class="axd-note">These are written at the very top of the script, before anything else runs.</div>'
    }
}
