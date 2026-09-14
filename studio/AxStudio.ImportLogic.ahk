#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\AxStudio.Host.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk
#Include %A_LineFile%\..\AxStudio.Auto.ahk
#Include %A_LineFile%\..\AxStudio.Import.ahk
#Include %A_LineFile%\..\AxStudio.Steps.ahk

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
;  AxStudio.ImportLogic.ahk -- what a script DOES, brought in as the studio's
;  no-code lists rather than as code.
;
;  The design importers (AxImport, AxImportGui) turn the window into a design
;  and put everything else -- hotkeys, hotstrings, timers, the settings at the
;  top, the tray -- into the window's script, word for word. That is safe and
;  it is also a wall of code. This reads that code (and a script with no
;  window at all) and finds what Logic and App already have a place for:
;
;      F1::Send("hello")             a hotkey          Logic > Hotkeys
;      ::btw::by the way             a typed shortcut  Logic > Typed shortcuts
;      #HotIf WinActive("Notepad")   where they work   (or a condition)
;      SetTimer(Tick, 1000)          a timer           Logic > Timers
;      count := 0                    a value           Logic > Values
;      SendMode("Input"), #UseHook   script settings   App > Script settings
;      TraySetIcon, A_TrayMenu.Add   the tray icon     App > Tray icon
;        (its items, separators, submenus made with Menu(), their icons,
;        which are greyed out, the default and what one click does)
;      OnClipboardChange, OnExit     things that happen Logic > In Windows
;      FileInstall("x.png", ...)     a carried file    App > Files
;
;  A body is only taken when every statement in it is one the step words say
;  exactly (send, type, run, wait, beep, message, notify, activate, call,
;  exit, reload); anything else stays code, untouched, and the report says
;  which and why. Scan() finds; Apply() does it, for the kinds the user ticks
;  in the import wizard -- so nothing is converted that was not asked for.
; =============================================================================
class AxImportLogic {
    ; -------------------------------------------------------- a plain script
    ; A script with no window at all: a project whose main window starts
    ; hidden (nothing shows, as before), with the script as its code -- then
    ; Scan finds what it does.
    static Plain(path, src) {
        SplitPath(path, , , , &stem)
        p := AxProject()
        w := p.Main()
        w.Title := stem, w.Name := "Main"
        w.StartState := "hidden"
        keep := "", notes := []
        for line in StrSplit(StrReplace(src, "`r"), "`n") {
            t := Trim(line)
            if RegExMatch(t, "i)^#Requires\b")
                continue
            if RegExMatch(t, "i)^#SingleInstance\s*(\w*)", &m) {
                if (m[1] != "" && m[1] != "Force")
                    AxAsset.SetCompile(p, "instance", m[1])
                continue
            }
            keep .= line "`n"
        }
        w.Script := Trim(keep, "`n")
        notes.Push("It has no window, so the design is an empty window that starts hidden -- the program "
            . "shows nothing, as before. Give it controls and set Starts to As it is designed to have one.")
        return {Project: p, Notes: notes, N: {Controls: 0, Pages: 0, Events: 0, Code: 0, Script: 1, Plain: true}}
    }

    ; ------------------------------------------------------------------ Scan
    ; What can be brought in without code: [{Kind, Say, Src, A, B, Do}]
    ;   Src  which text it is in ({Get, Set}), A/B its characters there
    ;   Do   what Apply writes: {Field, Line} or a closure
    static Scan(p) {
        out := []
        ; every function the program defines, by its parameters: a tray item
        ; in one block may call a function written in another
        AxImportLogic.Ext := Map(), AxImportLogic.Ext.CaseSense := false
        for w in p.Wins
            for txt in [w.Script, w.Init]
                for line in StrSplit(StrReplace(String(txt), "`r"), "`n")
                    if RegExMatch(line, "^\s*([A-Za-z_]\w*)\(([^()]*)\)\s*\{?\s*$", &m) && !RegExMatch(m[1], "i)^(if|while|for|loop|switch|catch)$")
                        AxImportLogic.Ext[m[1]] := m[2]
        for wi, w in p.Wins
            AxImportLogic.ScanText(p, w, AxImportLogic.Src(w, "Script"), out)
        for wi, w in p.Wins
            for n in AxImport.Nodes(w.Root)
                if (n.Type = "Code" && n.Parent = w.Root)
                    AxImportLogic.ScanText(p, w, AxImportLogic.NodeSrc(n), out)
        return out
    }
    static Src(w, field) => {Get: (*) => w.%field%, Set: (v) => w.%field% := v, Name: field}
    static NodeSrc(n) => {Get: (*) => n.Arg, Set: (v) => n.Arg := v, Name: "code"}

    static ScanText(p, w, src, out) {
        text := StrReplace(src.Get.Call(), "`r")
        if (Trim(text) = "" || !AxHost.Ready)
            return
        try t := AxHost.TreeText(text)
        catch
            return
        S := AxImportLogic
        fns := Map(), fns.CaseSense := false
        for i in t.Children(0)
            if (t.Type(i) = "Method")
                fns[t.Value(i)] := i
        ; a Menu() made at the top, filled with Add, then hung on the tray
        S.Menus := Map(), S.Menus.CaseSense := false
        where := "always", hotif := -1, hotifUsed := false, conds := 0
        region := []                         ; what a #HotIf governs, to drop it when all of it goes
        Close() {
            if (hotif >= 0)
                out.Push({Kind: "hotif", Say: "", Src: src, A: t.Start(hotif), B: t.End(hotif), Needs: region})
        }
        for i in t.Children(0) {
            ty := t.Type(i), code := t.Text(i, text)
            switch ty {
            case "Directive":
                v := Trim(t.Value(i))
                if RegExMatch(v, "i)^#HotIf\b\s*(.*)$", &m) {
                    Close()
                    region := []
                    hotif := (Trim(m[1]) = "") ? -1 : i
                    where := (Trim(m[1]) = "") ? "always" : S.HotIfWhere(p, Trim(m[1]), &conds, out, src, i)
                    if (Trim(m[1]) = "")        ; the reset belongs with the region before
                        out.Push({Kind: "hotif", Say: "", Src: src, A: t.Start(i), B: t.End(i), Needs: []})
                } else if RegExMatch(v, "i)^#UseHook\b")
                    out.Push(S.Item("setting", "Hotkeys cannot set themselves off (#UseHook)", src, t, i, {Key: "usehook", V: "1"}))
                else if RegExMatch(v, "i)^#NoTrayIcon\b")
                    out.Push(S.Item("tray", "No tray icon (#NoTrayIcon)", src, t, i, {Tray: "show = 0"}))
                else if RegExMatch(v, "i)^#Persistent\b")
                    out.Push(S.Item("setting", "#Persistent (not needed: the program stays running by itself)", src, t, i, {}))
            case "Hotkey":
                it := S.HotkeyItem(p, t, text, i, where, fns, src)
                if IsObject(it)
                    out.Push(it), region.Push(it)
                else if (hotif >= 0)
                    region.Push("")          ; one stays: so does its #HotIf
            case "Hotstring":
                it := S.HotstringItem(p, t, text, i, where, fns, src)
                if IsObject(it)
                    out.Push(it), region.Push(it)
                else if (hotif >= 0)
                    region.Push("")
            case "Remap":
                if RegExMatch(code, "^\s*(\S+?)::(\S+)\s*$", &m)
                    it := S.Item("hotkey", m[1] " acts as " m[2], src, t, i,
                        {Field: "Hotkeys", Line: m[1] " | " S.HkWhere(where) " | remap | " m[2]}), out.Push(it), region.Push(it)
            case "BinaryExpr":
                S.Assign(p, t, text, i, src, out)
            case "Call":
                S.CallItem(p, t, text, i, fns, src, out)
            }
        }
        Close()
    }
    static Menus := Map()
    ; what a menu item runs: a function that needs nothing, called; or the
    ; one line a (*) => ... holds. "" when neither.
    static MenuCode(t, text, fns, arg) {
        if RegExMatch(arg, "^\w+$") && !AxImportLogic.Menus.Has(arg)
            return AxImportLogic.NoArgs(t, text, fns, arg) ? arg "()" : ""
        if RegExMatch(arg, "s)^\(\s*\*\s*\)\s*=>\s*(.+)$", &m) && !InStr(m[1], "`n")
            return Trim(m[1])
        return ""
    }
    ; "shell32.dll", 14 -> shell32.dll,13 (an icon's number counts from 0 in
    ; the studio, as it does everywhere in Windows but TraySetIcon)
    static IconSpec(file, n) {
        if (n = "")
            return file
        n := Integer(n)
        return file "," (n > 0 ? n - 1 : n)
    }
    ; a hotstring's "front:" is a hotkey's "other:" (Logic keeps them apart)
    static HkWhere(w) => (SubStr(w, 1, 6) = "front:") ? "other:" SubStr(w, 7) : w
    static Item(kind, say, src, t, i, do) => {Kind: kind, Say: say, Src: src, A: t.Start(i), B: t.End(i), Do: do}

    ; #HotIf's expression as a hotkey's "where"; a condition of its own when
    ; it is not simply one window in front
    static HotIfWhere(p, expr, &n, out, src, i) {
        q := '"((?:[^"``]|``.)*)"'
        if RegExMatch(expr, "i)^WinActive\(\s*" q "\s*\)$", &m)
            return "front:" m[1]
        if RegExMatch(expr, "i)^(?:!|not\s+)WinActive\(\s*" q "\s*\)$", &m)
            return "not:" m[1]
        n++
        name := "when" n
        kind := "expr", detail := expr
        if RegExMatch(expr, "i)^WinExist\(\s*" q "\s*\)$", &m)
            kind := "exists", detail := m[1], name := "open" n
        else if RegExMatch(expr, "i)^GetKeyState\(\s*" q "\s*,\s*`"T`"\s*\)$", &m)
            kind := "key", detail := m[1] " on", name := StrLower(AxProject.CleanName(m[1])) "_on"
        out.Push({Kind: "cond", Say: "A condition for the keys under #HotIf " expr, Src: src, A: -1, B: -1,
                  Do: {Field: "Conds", Line: name " | " kind " | " detail}})
        return "cond:" name
    }

    ; ------------------------------------------------------- step words
    ; One statement as a step word, or "" when the words cannot say it
    ; exactly. Text with a comma in it cannot be a step (commas part them).
    static Step(t, text, i, fns) {
        q := '"((?:[^"``]|``.)*)"'
        c := Trim(t.Text(i, text))
        un := (x) => StrReplace(StrReplace(x, '``"', '"'), "````", "``")
        ok := (x) => !InStr(x, ",") && !InStr(x, "``")
        if RegExMatch(c, "i)^(Send|SendInput|SendEvent)\(\s*" q "\s*\)$", &m) && ok(m[2])
            return "send " un(m[2])
        if RegExMatch(c, "i)^SendText\(\s*" q "\s*\)$", &m) && ok(m[1])
            return "type " un(m[1])
        if RegExMatch(c, "i)^Run\(\s*" q "\s*\)$", &m) && ok(m[1])
            return "run " un(m[1])
        if RegExMatch(c, "i)^MsgBox\(\s*" q "\s*\)$", &m) && ok(m[1])
            return "message " un(m[1])
        if RegExMatch(c, "i)^TrayTip\(\s*" q "\s*\)$", &m) && ok(m[1])
            return "notify " un(m[1])
        if RegExMatch(c, "i)^WinActivate\(\s*" q "\s*\)$", &m) && ok(m[1])
            return "activate " un(m[1])
        if RegExMatch(c, "i)^Sleep\(\s*(\d+)\s*\)$", &m)
            return "wait " m[1]
        if RegExMatch(c, "i)^SoundBeep\(\s*\)$")
            return "beep"
        if RegExMatch(c, "i)^ExitApp\(\s*\)$")
            return "exit"
        if RegExMatch(c, "i)^Reload\(\s*\)$")
            return "reload"
        if RegExMatch(c, "i)^(\w+)\(\s*\)$", &m) && AxImportLogic.NoArgs(t, text, fns, m[1])
            return "call " m[1]
        return ""
    }
    ; a body -- a block, or one statement -- as steps, or "" when any is not one
    static Steps(t, text, body, fns) {
        if (body < 0)
            return ""
        list := []
        if (t.Type(body) = "Block") {
            for c in t.Children(body) {
                if (t.Type(c) = "Comment")
                    continue
                st := AxImportLogic.Step(t, text, c, fns)
                if (st = "")
                    return ""
                list.Push(st)
            }
        } else {
            st := AxImportLogic.Step(t, text, body, fns)
            if (st = "")
                return ""
            list.Push(st)
        }
        return list.Length ? list : ""
    }
    static Join(list) {
        s := ""
        for x in list
            s .= (s = "" ? "" : ", ") x
        return s
    }

    ; ------------------------------------------------------------- hotkeys
    static HotkeyItem(p, t, text, i, where, fns, src) {
        keys := t.Value(i)
        body := t.FirstChild(i)
        steps := AxImportLogic.Steps(t, text, body, fns)
        if !IsObject(steps)
            return ""
        act := "steps", detail := AxImportLogic.Join(steps)
        if (steps.Length = 1) {
            v := RegExReplace(steps[1], " .*$"), rest := Trim(SubStr(steps[1], StrLen(v) + 1))
            if (v = "send" || v = "type" || v = "run")
                act := v, detail := rest
            else if (v = "call")
                act := "own", detail := rest
        }
        return {Kind: "hotkey", Say: AxLogic.KeyWords(keys) " -- " AxImportLogic.Join(steps), Src: src,
                A: t.Start(i), B: t.End(i), Do: {Field: "Hotkeys", Line: keys " | " AxImportLogic.HkWhere(where) " | " act " | " detail}}
    }
    ; ::btw::by the way   :*:sig::`n...   ::now:: { Send(...) }
    static HotstringItem(p, t, text, i, where, fns, src) {
        v := t.Value(i)
        if !RegExMatch(v, "s)^:([^:]*):(.+?)::(.*)$", &m)
            return ""
        opts := m[1], abbr := m[2], rep := m[3]
        ; "::now:: {" -- a block: the parser reads the brace as the text and
        ; the block as statements of their own, so it stays code, whole
        if InStr(abbr, "|") || RegExMatch(rep, "\{\s*$")
            return ""
        body := t.FirstChild(i)
        if (body >= 0 || InStr(opts, "X")) {
            steps := (body >= 0) ? AxImportLogic.Steps(t, text, body, fns) : ""
            if !IsObject(steps) && InStr(opts, "X") && Trim(rep) != "" {
                ; :X:abbr::Fn()   -- the rest of the line is the code
                x := ""
                try {
                    tr := AxHost.TreeText(rep), c1 := tr.FirstChild(0)
                    if (c1 >= 0)
                        x := AxImportLogic.Step(tr, rep, c1, fns)
                }
                steps := (x != "") ? [x] : ""
            }
            if !IsObject(steps)
                return ""
            return {Kind: "hotstring", Say: abbr " does " AxImportLogic.Join(steps), Src: src, A: t.Start(i), B: t.End(i),
                    Do: {Field: "Strings", Line: abbr " | " StrReplace(opts, "X") "X | " where " | " AxImportLogic.Join(steps)}}
        }
        if InStr(rep, "|")
            return ""
        return {Kind: "hotstring", Say: abbr " becomes " SubStr(rep, 1, 40), Src: src, A: t.Start(i), B: t.End(i),
                Do: {Field: "Strings", Line: abbr " | " opts " | " where " | " StrReplace(rep, "`n", "``n")}}
    }

    ; ------------------------------------------------------- x := something
    static Assign(p, t, text, i, src, out) {
        if !t.Has(i, "assign") || t.Value(i) != ":="
            return
        l := t.FirstChild(i), r := t.Next(l)
        name := t.Text(l, text), val := Trim(t.Text(r, text))
        lit := (t.Type(r) = "String" || t.Type(r) = "Number" || (t.Type(r) = "Identifier" && RegExMatch(val, "i)^(true|false)$")))
        S := AxImportLogic
        ; sub := Menu(): perhaps a submenu of the tray's (CallItem fills it)
        if (t.Type(l) = "Identifier" && RegExMatch(val, "i)^Menu\(\s*\)$")) {
            rec := {Lines: [], Items: [], Bad: false}
            AxImportLogic.Menus[name] := rec
            it := AxImportLogic.Item("tray", "", src, t, i, {})
            it.Part := rec, rec.Items.Push(it)
            return out.Push(it)
        }
        switch StrLower(name) {
        case "a_traymenu.default":
            if (t.Type(r) = "String")
                out.Push(S.Item("tray", "The tray menu's bold item: " val, src, t, i, {Tray: "@" S.Unq(val) " | default"}))
            return
        case "a_traymenu.clickcount":
            if (val = "1")
                out.Push(S.Item("tray", "One click on the tray icon does the bold item", src, t, i, {Tray: "click = default"}))
            return
        case "a_maxhotkeysperinterval":
            if IsInteger(val)
                out.Push(S.Item("setting", "Warn after " val " hotkeys in two seconds", src, t, i, {Key: "maxhk", V: val}))
            return
        case "a_icontip":
            if (t.Type(r) = "String")
                out.Push(S.Item("tray", "The tray icon's tip: " val, src, t, i, {Tray: "tip = " S.Unq(val)}))
            return
        }
        ; a continuation section ("(...)" over many lines) is a literal too,
        ; but not one a line of Values can hold
        if (t.Type(l) != "Identifier" || !lit || SubStr(name, 1, 2) = "A_" || InStr(val, "`n") || StrLen(val) > 200)
            return
        if IsObject(p.FindByName(name)) || AxBind.HasVar(p, name)
            return
        out.Push(S.Item("value", name " starts as " val, src, t, i, {Field: "Vars", Line: name " = " val}))
    }
    static Unq(s) => RegExMatch(s, '^"(.*)"$', &m) ? StrReplace(StrReplace(m[1], '``"', '"'), "````", "``") : s

    ; ------------------------------------------------------------ calls
    static CallItem(p, t, text, i, fns, src, out) {
        c := Trim(t.Text(i, text))
        S := AxImportLogic
        q := '"((?:[^"``]|``.)*)"'
        if RegExMatch(c, "i)^SendMode\(\s*" q "\s*\)$", &m)
            return out.Push(S.Item("setting", "Keys are typed the " m[1] " way", src, t, i, {Key: "sendmode", V: m[1]}))
        if RegExMatch(c, "i)^SetTitleMatchMode\(\s*(?:" q "|(\d))\s*\)$", &m) {
            v := (m[2] != "") ? m[2] : m[1]
            if (v = "1" || v = "2" || v = "3" || v = "RegEx")
                return out.Push(S.Item("setting", "Window names match: " v, src, t, i, {Key: "titlematch", V: v}))
            return
        }
        if RegExMatch(c, "i)^DetectHiddenWindows\(\s*(true|1|`"On`")\s*\)$")
            return out.Push(S.Item("setting", "Finds hidden windows too", src, t, i, {Key: "hidden", V: "1"}))
        if RegExMatch(c, "i)^CoordMode\(\s*`"(Mouse|Pixel)`"\s*,\s*`"(Screen|Window|Client)`"\s*\)$", &m)
            return out.Push(S.Item("setting", m[1] " positions count from the " StrLower(m[2]), src, t, i, {Key: "coord", V: m[2]}))
        if RegExMatch(c, "i)^SetWorkingDir\(\s*A_ScriptDir\s*\)$")
            return out.Push(S.Item("setting", "Finds files beside the program", src, t, i, {Key: "workdir", V: "1"}))
        if RegExMatch(c, "i)^KeyHistory\(\s*0\s*\)$")
            return out.Push(S.Item("setting", "Keeps typing private (KeyHistory 0)", src, t, i, {Key: "nohistory", V: "1"}))
        if RegExMatch(c, "i)^ProcessSetPriority\(\s*" q "\s*\)$", &m)
            return out.Push(S.Item("setting", "Runs at " m[1] " priority", src, t, i, {Key: "priority", V: m[1]}))
        if RegExMatch(c, "i)^Persistent\(\s*\)$")
            return out.Push(S.Item("setting", "Persistent() (not needed: the program stays running by itself)", src, t, i, {}))
        if RegExMatch(c, "i)^TraySetIcon\(\s*" q "\s*(?:,\s*(-?\d+)\s*)?\)$", &m)
            return out.Push(S.Item("tray", "The tray icon is " m[1], src, t, i, {Tray: "icon = " S.IconSpec(m[1], m[2])}))
        ; the tray's own menu, and the Menu()s hung on it
        if RegExMatch(c, "i)^A_TrayMenu\.Delete\(\s*\)$")
            return out.Push(S.Item("tray", "The tray menu starts empty (AutoHotkey's own items go)", src, t, i, {}))
        if RegExMatch(c, "i)^(\w+)\.Add\(\s*\)$", &m) && (m[1] = "A_TrayMenu" || S.Menus.Has(m[1])) {
            if (m[1] = "A_TrayMenu")
                return out.Push(S.Item("tray", "A line in the tray menu", src, t, i, {Tray: "-"}))
            rec := S.Menus[m[1]], rec.Lines.Push("-")
            it := S.Item("tray", "", src, t, i, {}), it.Part := rec, rec.Items.Push(it)
            return out.Push(it)
        }
        if RegExMatch(c, "i)^(\w+)\.Add\(\s*" q "\s*,\s*(.+)\)$", &m) && (m[1] = "A_TrayMenu" || S.Menus.Has(m[1])) {
            label := m[2], arg := Trim(m[3]), sub := ""
            code := S.MenuCode(t, text, fns, arg)
            if (m[1] = "A_TrayMenu" && S.Menus.Has(arg) && !S.Menus[arg].Bad) {
                sub := S.Menus[arg]
                lines := label
                for l in sub.Lines
                    lines .= "`n    " l
                it := S.Item("tray", "A tray submenu: " label " (" sub.Lines.Length " items)", src, t, i, {Tray: lines})
                for x in sub.Items
                    x.Part := it
                return out.Push(it)
            }
            if (code = "") {
                if S.Menus.Has(m[1])
                    S.Menus[m[1]].Bad := true
                return
            }
            if (m[1] = "A_TrayMenu")
                return out.Push(S.Item("tray", "A tray menu item: " label, src, t, i, {Tray: label " | " code}))
            rec := S.Menus[m[1]], rec.Lines.Push(label " | " code)
            it := S.Item("tray", "", src, t, i, {}), it.Part := rec, rec.Items.Push(it)
            return out.Push(it)
        }
        if RegExMatch(c, "i)^A_TrayMenu\.SetIcon\(\s*" q "\s*,\s*" q "\s*(?:,\s*(-?\d+)\s*)?\)$", &m) && !InStr(m[2], " ")
            return out.Push(S.Item("tray", "The tray item " m[1] " has a picture", src, t, i, {Tray: "@" m[1] " | icon=" S.IconSpec(m[2], m[3])}))
        if RegExMatch(c, "i)^A_TrayMenu\.Disable\(\s*" q "\s*\)$", &m)
            return out.Push(S.Item("tray", "The tray item " m[1] " is greyed out", src, t, i, {Tray: "@" m[1] " | off"}))
        ; anything else done to one of those menus: it stays code, and so
        ; does whatever hangs it on the tray
        if RegExMatch(c, "i)^(\w+)\.\w+\(", &m) && S.Menus.Has(m[1])
            S.Menus[m[1]].Bad := true
        if RegExMatch(c, "i)^OnClipboardChange\(\s*(\w+)\s*\)$", &m) && AxImportLogic.NoArgs(t, text, fns, m[1])
            return out.Push(S.Item("event", "When the clipboard changes: " m[1] "()", src, t, i,
                {Field: "Events", Line: "clipboard |  | call " m[1]}))
        if RegExMatch(c, "i)^OnExit\(\s*(\w+)\s*\)$", &m) && AxImportLogic.NoArgs(t, text, fns, m[1])
            return out.Push(S.Item("event", "When the program ends: " m[1] "()", src, t, i,
                {Field: "Events", Line: "exit |  | call " m[1]}))
        if RegExMatch(c, "i)^FileInstall\(\s*" q "\s*,\s*(?:A_ScriptDir\s*`"\\)?`"?([^`"\\]+)`"\s*(?:,\s*\w+\s*)?\)$", &m) {
            SplitPath(m[1], &fname)
            if (fname = m[2])
                return out.Push(S.Item("file", m[1] " is carried with the program", src, t, i,
                    {Field: "Files", Line: AxAsset.FileLine(AxProject.CleanName(RegExReplace(fname, "\.[^.]*$")), m[1], "install")}))
        }
        ; SetTimer(Name, period): a timer; its function's steps come with it
        ; when that is all the function is for and the words can say it
        if RegExMatch(c, "i)^SetTimer\(\s*(\w+)\s*(?:,\s*(-?\d+)\s*)?\)$", &m) && AxImportLogic.NoArgs(t, text, fns, m[1]) {
            fn := m[1], ms := (m[2] = "") ? 250 : Integer(m[2])
            fi := fns[fn]
            steps := AxImportLogic.Steps(t, text, AxStepsRead.BodyOf(t, fi), fns)
            only := (AxImportLogic.Mentions(text, fn) <= 2)       ; its definition, and this
            inline := IsObject(steps) && only && t.ChildCount(t.FirstChild(fi)) = 0
            name := StrLower(AxProject.CleanName(fn))
            every := (ms < 0 ? "once " (-ms) : ms) "ms"
            it := S.Item("timer", (ms < 0 ? "Once, after " (-ms) " ms: " : "Every " ms " ms: ") (inline ? AxImportLogic.Join(steps) : fn "()"),
                src, t, i, {Field: "Timers", Line: name " | " every " | start |  | " (inline ? AxImportLogic.Join(steps) : "call " fn)})
            out.Push(it)
            if inline
                out.Push({Kind: "timer", Say: "", Src: src, A: t.Start(fi), B: t.End(fi), Do: {}, Part: it})
        }
    }
    ; can it be called with nothing? (Fn(), Fn(*), Fn(a := 1)) -- a step's
    ; "call" gives nothing, where OnClipboardChange would have given a kind
    static Ext := Map()
    static NoArgs(t, text, fns, name) {
        if !fns.Has(name) {
            if !AxImportLogic.Ext.Has(name)
                return false
            for pt in StrSplit(AxImportLogic.Ext[name], ",")
                if (Trim(pt) != "" && !(Trim(pt) = "*" || SubStr(Trim(pt), -1) = "*" || InStr(pt, ":=") || SubStr(Trim(pt), -1) = "?"))
                    return false
            return true
        }
        ps := t.FirstChild(fns[name])
        if (ps < 0 || t.Type(ps) != "Parameters")
            return true
        for c in t.Children(ps) {
            pt := Trim(t.Text(c, text))
            if !(pt = "*" || SubStr(pt, -1) = "*" || InStr(pt, ":=") || SubStr(pt, -1) = "?")
                return false
        }
        return true
    }
    static Mentions(text, name) {
        n := 0, pos := 1
        while (pos := RegExMatch(text, "i)(?<![\w.])" name "(?!\w)", &m, pos))
            n++, pos += m.Len
        return n
    }

    ; ----------------------------------------------------------------- Apply
    ; The kinds ticked: their lines into the project, their code out of the
    ; text it was in. Each text is cut from the end back, so one cut never
    ; moves the next. A #HotIf goes when everything it governed went.
    static Apply(p, found, kinds) {
        want := Map()
        for k in kinds
            want[k] := true
        want["hotif"] := true
        taken := Map()
        n := Map()
        ; the parts of something after it: a submenu's items come before the
        ; line that hangs it on the tray, and go only if that line does
        order := []
        for it in found
            if !it.HasOwnProp("Part")
                order.Push(it)
        for it in found
            if it.HasOwnProp("Part")
                order.Push(it)
        for it in order {
            if !want.Has(it.Kind) || it.Kind = "hotif"
                continue
            if it.HasOwnProp("Part") && !taken.Has(it.Part)
                continue
            taken[it] := true
            n[it.Kind] := (n.Has(it.Kind) ? n[it.Kind] : 0) + (it.Say != "" ? 1 : 0)
            d := it.Do
            if d.HasOwnProp("Field")
                p.%d.Field% := RTrim(String(p.%d.Field%), "`r`n") (Trim(String(p.%d.Field%)) = "" ? "" : "`n") d.Line
            else if d.HasOwnProp("Key")
                AxAsset.SetCompile(p, d.Key, d.V)
            else if d.HasOwnProp("Tray")
                p.Tray := RTrim(String(p.Tray), "`r`n") (Trim(String(p.Tray)) = "" ? "" : "`n") d.Tray
        }
        ; conditions are only wanted when something that uses them went
        cuts := Map()
        for it in found {
            if (it.A < 0)
                continue
            cut := taken.Has(it)
            if (it.Kind = "hotif") {
                cut := true
                for x in it.Needs
                    cut := cut && IsObject(x) && taken.Has(x)
                if (it.Needs.Length = 0)
                    cut := AxImportLogic.RegionGone(found, it, taken)
            }
            if !cut
                continue
            if !cuts.Has(it.Src)
                cuts[it.Src] := []
            cuts[it.Src].Push([it.A, it.B])
        }
        for src, list in cuts {
            text := StrReplace(src.Get.Call(), "`r")
            ; from the end back
            s := ""
            for x in list
                s .= Format("{:010}", x[1]) "`t" x[2] "`n"
            for line in StrSplit(Sort(RTrim(s, "`n"), "R"), "`n") {
                a := Integer(StrSplit(line, "`t")[1]), b := Integer(StrSplit(line, "`t")[2])
                ; the whole lines it stood on
                ls := a
                while (ls > 0 && SubStr(text, ls, 1) != "`n")
                    ls--
                le := InStr(text, "`n", , b + 1)
                le := le ? le : StrLen(text)
                if (Trim(SubStr(text, ls + 1, a - ls)) = "")
                    text := SubStr(text, 1, ls) SubStr(text, le + 1)
                else
                    text := SubStr(text, 1, a) SubStr(text, b + 1)
            }
            src.Set.Call(RegExReplace(Trim(text, "`n"), "\n{3,}", "`n`n"))
        }
        ; the conditions the kept keys need
        for it in found
            if (it.Kind = "cond" && AxImportLogic.CondUsed(p, it.Do.Line))
                p.Conds := RTrim(String(p.Conds), "`r`n") (Trim(String(p.Conds)) = "" ? "" : "`n") it.Do.Line
        return n
    }
    ; the "#HotIf" reset: gone when the region it closes has nothing left
    static RegionGone(found, reset, taken) {
        before := ""
        for it in found
            if (it.Kind = "hotif" && it.Src = reset.Src && it.A < reset.A && it.Needs.Length)
                before := it
        if !IsObject(before)
            return true
        for x in before.Needs
            if !(IsObject(x) && taken.Has(x))
                return false
        return true
    }
    static CondUsed(p, line) {
        name := Trim(StrSplit(line, "|")[1])
        for w in p.Wins
            if InStr(w.Hotkeys, "cond:" name)
                return true
        return InStr(p.Strings, "cond:" name) > 0
    }

    ; --------------------------------------------------------- the wizard
    ; What was found, by kind, each a tick; returns the kinds ticked, or ""
    ; for none (and the import goes on as code).
    static Kinds := [["hotkey", "Hotkeys", "Logic > Hotkeys"], ["hotstring", "Typed shortcuts", "Logic > Typed shortcuts"],
        ["timer", "Timers", "Logic > Timers"], ["value", "Values", "Logic > Values"],
        ["event", "Things that happen", "Logic > In Windows"], ["setting", "Script settings", "App > Script settings"],
        ["tray", "The tray icon", "App > Tray icon"], ["file", "Files it carries", "App > Files"]]
    static Wizard(s, found, name) {
        count := Map(), eg := Map()
        for it in found
            if (it.Say != "" && it.Kind != "cond" && it.Kind != "hotif") {
                count[it.Kind] := (count.Has(it.Kind) ? count[it.Kind] : 0) + 1
                if !eg.Has(it.Kind)
                    eg[it.Kind] := []
                if (eg[it.Kind].Length < 3)
                    eg[it.Kind].Push(it.Say)
            }
        if !count.Count
            return []
        fields := [{Id: "n0", Kind: "note", L: "These are things the studio has a place for. Ticked, each becomes an entry "
            . "you can read and change without code; the code they were is taken out. Anything not ticked stays as it was, "
            . "in the window's code."}]
        for k in AxImportLogic.Kinds {
            if !count.Has(k[1])
                continue
            ex := ""
            for x in eg[k[1]]
                ex .= (ex = "" ? "" : "  ·  ") x
            fields.Push({Id: "k_" k[1], L: count[k[1]] " " StrLower(k[2]) " -- into " k[3], Kind: "flag", V: 1,
                         Hint: SubStr(ex, 1, 160)})
        }
        r := AxForm.Show(s, {Title: "Bring " name " in without code", Icon: "E8B5", Width: 620,
            Intro: "Found in the script, and ready to become the studio's own lists:",
            Fields: fields, Buttons: ["Bring them in", "Keep it all as code"]})
        if !r.Ok
            return []
        out := []
        for k in AxImportLogic.Kinds
            if (r.V.Has("k_" k[1]) && r.V["k_" k[1]])
                out.Push(k[1])
        return out
    }
}
