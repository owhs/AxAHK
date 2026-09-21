#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Lit.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk
#Include %A_LineFile%\..\AxStudio.Bind.ahk
#Include %A_LineFile%\..\AxStudio.Auto.ahk
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
;  AxStudio.Auto2.ahk -- what a program does on its own: events, folders,
;  macros, the settings it keeps, and starting with Windows.
;
;      Events    event | detail | steps
;                clipboard | text | toast Copied: {text}
;                winopen | ahk_exe notepad.exe | toast Notepad is open
;      Watchers  name | folder | files | when | subfolders | steps
;                inbox | A_MyDocuments\Inbox | *.pdf | added | no | toast New: {name}
;      Macros    name | repeat | speed | hotkey          (then the steps, indented)
;                hello | 1 | 1 | ^!m
;                    key #r
;                    wait 400
;                    text notepad
;                    key {Enter}
;      Settings  name | default | kind | label | options
;                theme | dark | choice | Theme | dark,light,system
;                autostart | 0 | startup | Start with Windows
;
;  Steps can carry what happened in braces: {file} {name} {kind} for a
;  watcher, {window} for a window, {text} for the clipboard, {drive} for a
;  drive, {mode} for the theme, {reason} for exit.
;
;  The folder watcher is the kernel's: ReadDirectoryChangesW, overlapped, one
;  handle per folder, and a single timer that asks each handle whether it has
;  news with a zero wait -- no folder is ever listed or compared, whatever is
;  in it. A save that touches a file several times in a burst is one change.
; =============================================================================

class AxAuto2 {
    ; ================================================================ events
    static EventKinds := "start:The program starts|exit:The program ends|clipboard:The clipboard changes|"
        . "winopen:A window opens|winclose:A window closes|winfront:A window comes to the front|"
        . "lock:The screen locks|unlock:The screen unlocks|sleep:The computer goes to sleep|"
        . "wake:The computer wakes up|display:The screens change|driveadd:A drive is plugged in|"
        . "driveremove:A drive is taken out|theme:Windows switches dark or light|"
        . "idle:Nobody touches the keyboard or mouse for a while|back:Somebody is back after being idle|"
        . "message:A window message arrives"
    static KindWord(list, k) {
        for part in StrSplit(list, "|") {
            p := InStr(part, ":")
            if (SubStr(part, 1, p - 1) = k)
                return SubStr(part, p + 1)
        }
        return k
    }
    static Events(p) {
        out := []
        for line in AxAsset.Lines(p.Events) {
            f := AxAuto.Split(line, 3)
            if (f[1] != "")
                out.Push({Kind: StrLower(f[1]), Detail: f[2], Text: f[3], Steps: AxAuto.Steps(f[3]), Line: line})
        }
        return out
    }
    ; The steps, with what happened put where the braces ask for it.
    static StepsWith(p, steps, ph, pad := "    ") {
        s := ""
        for st in steps {
            c := AxAsset.StepCode(p, st)
            for k, v in ph
                c := StrReplace(c, "{" k "}", '" ' v ' "')
            s .= pad c "`n"
        }
        return s
    }
    static EventCode(p) {
        list := AxAuto2.Events(p)
        if !list.Length
            return ""
        decl := AxAuto.Decl(p), q := Chr(34)
        fns := "", start := "", shell := Map("winopen", [], "winclose", [], "winfront", [])
        msgs := Map()                      ; message number -> [function calls]
        idle := []
        for i, e in list {
            fn := "Event_" i
            switch e.Kind {
            case "start":
                fns .= fn "() {`n" decl AxAuto2.StepsWith(p, e.Steps, Map()) "}`n"
                start .= "    " fn "()`n"
            case "exit":
                why := (Trim(e.Detail) = "" || e.Detail = "any") ? "" : RegExReplace(Trim(e.Detail), "\s*[,;]\s*", "|")
                fns .= fn "(axReason, *) {`n" decl
                     . (why != "" ? "    if !InStr(" AxLit.S("|" why "|") ", " q "|" q " axReason " q "|" q ")`n        return 0`n" : "")
                     . AxAuto2.StepsWith(p, e.Steps, Map("reason", "axReason")) "    return 0`n}`n"
                start .= "    OnExit(" fn ")`n"
            case "clipboard":
                fns .= fn "(axType) {`n" decl
                     . ((e.Detail = "text") ? "    if (axType != 1)`n        return`n" : "")
                     . "    axText := (axType = 1) ? A_Clipboard : " q q "`n"
                     . AxAuto2.StepsWith(p, e.Steps, Map("text", "axText")) "}`n"
                start .= "    OnClipboardChange(" fn ")`n"
            case "winopen", "winclose", "winfront":
                fns .= fn "(axHwnd, axTitle) {`n" decl AxAuto2.StepsWith(p, e.Steps, Map("window", "axTitle")) "}`n"
                shell[e.Kind].Push({Fn: fn, Crit: e.Detail})
            case "lock", "unlock":
                fns .= fn "() {`n" decl AxAuto2.StepsWith(p, e.Steps, Map()) "}`n"
                AxAuto2._Msg(msgs, 0x2B1, "if (wp = " (e.Kind = "lock" ? 7 : 8) ")`n            " fn "()")
            case "sleep":
                fns .= fn "() {`n" decl AxAuto2.StepsWith(p, e.Steps, Map()) "}`n"
                AxAuto2._Msg(msgs, 0x218, "if (wp = 4)`n            " fn "()")
            case "wake":
                fns .= fn "() {`n" decl AxAuto2.StepsWith(p, e.Steps, Map()) "}`n"
                AxAuto2._Msg(msgs, 0x218, "if (wp = 7 || wp = 18) && AxOnce(" q "wake" q ", 5000)`n            " fn "()")
            case "display":
                fns .= fn "() {`n" decl AxAuto2.StepsWith(p, e.Steps, Map()) "}`n"
                AxAuto2._Msg(msgs, 0x7E, "if AxOnce(" q "display" q ", 1000)`n            SetTimer(" fn ", -500)")
            case "driveadd", "driveremove":
                fns .= fn "(axDrive) {`n" decl AxAuto2.StepsWith(p, e.Steps, Map("drive", "axDrive")) "}`n"
                AxAuto2._Msg(msgs, 0x219, "if (wp = " (e.Kind = "driveadd" ? "0x8000" : "0x8004") ") && (d := AxDrives(lp)) != " q q "`n            " fn "(d)")
            case "theme":
                fns .= fn "(axMode) {`n" decl AxAuto2.StepsWith(p, e.Steps, Map("mode", "axMode")) "}`n"
                AxAuto2._Msg(msgs, 0x1A, "if lp && StrGet(lp) = " q "ImmersiveColorSet" q " && AxOnce(" q "theme" q ", 1500)`n            "
                    . fn "(RegRead(" q "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" q ", " q "AppsUseLightTheme" q ", 1) ? " q "light" q " : " q "dark" q ")")
            case "idle", "back":
                fns .= fn "() {`n" decl AxAuto2.StepsWith(p, e.Steps, Map()) "}`n"
                secs := RegExReplace(e.Detail, "[^0-9.]")
                idle.Push({Fn: fn, Ms: (secs = "" ? 300 : secs) * 1000, Back: e.Kind = "back"})
            case "message":
                n := Trim(e.Detail)
                if !(IsInteger(n) || RegExMatch(n, "i)^0x[0-9a-f]+$"))
                    continue
                fns .= fn "(axWp, axLp) {`n" decl AxAuto2.StepsWith(p, e.Steps, Map("wparam", "axWp", "lparam", "axLp")) "}`n"
                AxAuto2._Msg(msgs, Integer(n), fn "(wp, lp)")
            }
        }
        s := "; Program events: what the program does when something happens around it.`n"
           . "AxEventsStart() {`n    global g`n" start
        ; windows: the shell tells the program's own window about every one
        if (shell["winopen"].Length || shell["winclose"].Length || shell["winfront"].Length) {
            s .= "    DllCall(" q "RegisterShellHookWindow" q ", " q "Ptr" q ", g.Hwnd)`n"
               . "    OnMessage(DllCall(" q "RegisterWindowMessage" q ", " q "Str" q ", " q "SHELLHOOK" q ", " q "UInt" q "), AxShell)`n"
            for c in shell["winclose"]
                s .= "    for h in WinGetList(" AxLit.S(c.Crit) ")`n        AxShell(-1, h)`n"
        }
        if msgs.Has(0x2B1)
            s .= "    DllCall(" q "wtsapi32\WTSRegisterSessionNotification" q ", " q "Ptr" q ", g.Hwnd, " q "UInt" q ", 0)`n"
        for num, calls in msgs
            s .= "    OnMessage(" Format("0x{:X}", num) ", AxMsg_" Format("{:X}", num) ")`n"
        if idle.Length
            s .= "    SetTimer(AxIdleCheck, 1000)`n"
        s .= "}`n" fns
        for num, calls in msgs {
            s .= "AxMsg_" Format("{:X}", num) "(wp, lp, *) {`n"
            for c in calls
                s .= "    try {`n        " c "`n    }`n"
            s .= "}`n"
        }
        if (shell["winopen"].Length || shell["winclose"].Length || shell["winfront"].Length) {
            ; a window is made before it has its title: looked at a moment later
            s .= "AxShell(wp, lp, *) {`n"
               . "    static open := Map()`n"
               . "    w := wp & 0x7FFF`n"
               . "    if (wp = -1 || w = 1)`n"
               . "        return SetTimer(AxShellNew.Bind(lp, open, wp = -1), -250)`n"
               . "    if (w = 2 && open.Has(lp)) {`n"
               . "        for c in open[lp]`n"
               . "            try c[1](lp, c[2])`n"
               . "        open.Delete(lp)`n"
               . "        return`n"
               . "    }`n"
               . "    if (w = 4) {`n"
            for c in shell["winfront"]
                s .= "        if WinExist(" AxLit.S(c.Crit) " " q " ahk_id " q " lp)`n            try " c.Fn "(lp, WinGetTitle(" q "ahk_id " q " lp))`n"
            s .= "    }`n}`n"
               . "AxShellNew(lp, open, already) {`n"
               . "    try title := WinGetTitle(" q "ahk_id " q " lp)`n"
               . "    catch`n        return`n"
            for c in shell["winopen"]
                s .= "    if !already && WinExist(" AxLit.S(c.Crit) " " q " ahk_id " q " lp)`n        try " c.Fn "(lp, title)`n"
            for c in shell["winclose"]
                s .= "    if WinExist(" AxLit.S(c.Crit) " " q " ahk_id " q " lp) {`n"
                   . "        if !open.Has(lp)`n            open[lp] := []`n"
                   . "        open[lp].Push([" c.Fn ", title])`n    }`n"
            s .= "}`n"
        }
        if msgs.Has(0x219)
            s .= "AxDrives(lp) {`n"
               . "    if !lp || NumGet(lp, 4, " q "UInt" q ") != 2`n        return " q q "`n"
               . "    mask := NumGet(lp, 12, " q "UInt" q "), out := " q q "`n"
               . "    loop 26`n        if (mask & (1 << (A_Index - 1)))`n            out .= Chr(64 + A_Index) " q ":" q "`n"
               . "    return out`n}`n"
        if (msgs.Has(0x218) || msgs.Has(0x7E) || msgs.Has(0x1A))
            s .= "AxOnce(key, ms) {`n    static last := Map()`n"
               . "    if last.Has(key) && A_TickCount - last[key] < ms`n        return false`n"
               . "    last[key] := A_TickCount`n    return true`n}`n"
        if idle.Length {
            s .= "AxIdleCheck() {`n    static away := Map()`n"
            for i, x in idle
                if x.Back
                    s .= "    if away.Has(" i ") && A_TimeIdlePhysical < 1000`n        away.Delete(" i "), " x.Fn "()`n"
                       . "    else if (A_TimeIdlePhysical >= " Round(x.Ms) ")`n        away[" i "] := true`n"
                else
                    s .= "    if (A_TimeIdlePhysical >= " Round(x.Ms) ") {`n        if !away.Has(" i ")`n"
                       . "            away[" i "] := true, " x.Fn "()`n    } else if away.Has(" i ")`n        away.Delete(" i ")`n"
            s .= "}`n"
        }
        return s
    }
    static _Msg(msgs, num, call) {
        if !msgs.Has(num)
            msgs[num] := []
        msgs[num].Push(call)
    }

    ; ============================================================== watchers
    static Watchers(p) {
        out := []
        for line in AxAsset.Lines(p.Watchers) {
            f := AxAuto.Split(line, 6)
            name := AxProject.CleanName(f[1])
            if (name != "" && f[2] != "")
                out.Push({Name: name, Folder: f[2], Files: f[3], When: f[4] = "" ? "any" : StrLower(f[4]),
                          Subs: AxAsset.Truthy(f[5]), Text: f[6], Steps: AxAuto.Steps(f[6]), Line: line})
        }
        return out
    }
    ; "A_MyDocuments\Inbox" is the folder under Documents; anything else is as written
    static FolderExpr(t) {
        if RegExMatch(Trim(t), "^(A_\w+)(.*)$", &m)
            return m[2] != "" ? m[1] " " AxLit.S(m[2]) : m[1]
        return AxLit.S(Trim(t))
    }
    static WatchCode(p) {
        list := AxAuto2.Watchers(p)
        if !list.Length
            return ""
        decl := AxAuto.Decl(p), q := Chr(34)
        s := "; Folder watchers: Windows says when something in a folder changes.`nAxWatchersStart() {`n"
        fns := ""
        for w in list {
            mask := 0
            when := (w.When = "any") ? "added,removed,changed,renamed" : w.When
            if (InStr(when, "added") || InStr(when, "removed") || InStr(when, "renamed"))
                mask |= 0x3                       ; file and folder names
            if InStr(when, "changed")
                mask |= 0x18                      ; size and last write
            s .= "    if !AxWatch.Add(" AxAuto2.FolderExpr(w.Folder) ", " (w.Subs ? "true" : "false") ", "
               . AxLit.S(w.Files) ", " mask ", Watch_" w.Name ")`n"
               . "        OutputDebug(" q "watcher " w.Name ": no such folder" q ")`n"
            fns .= "Watch_" w.Name "(axKind, axFile) {`n" decl
                 . "    if !InStr(" AxLit.S("|" StrReplace(when, ",", "|") "|") ", " q "|" q " axKind " q "|" q ")`n        return`n"
                 . "    SplitPath(axFile, &axName)`n"
                 . AxAuto2.StepsWith(p, w.Steps, Map("file", "axFile", "name", "axName", "kind", "axKind")) "}`n"
        }
        return s "}`n" fns AxAuto2.WatchClass
    }
    static WatchClass := "
(`
; One overlapped ReadDirectoryChangesW per folder, and one timer asking each,
; with a zero wait, whether it has news. Nothing is listed or compared.
class AxWatch {
    static All := [], Last := Map()
    static Add(dir, subs, files, mask, fn) {
        dir := RTrim(dir, "\")
        if !DirExist(dir)
            return false
        h := DllCall("CreateFile", "Str", dir, "UInt", 1, "UInt", 7, "Ptr", 0, "UInt", 3
                   , "UInt", 0x42000000, "Ptr", 0, "Ptr")
        if (h = -1)
            return false
        w := {Dir: dir, Subs: subs, Files: files, Mask: mask, Fn: fn, H: h,
              Buf: Buffer(65536, 0), Ov: Buffer(A_PtrSize = 8 ? 32 : 20, 0),
              Ev: DllCall("CreateEvent", "Ptr", 0, "Int", 1, "Int", 0, "Ptr", 0, "Ptr")}
        NumPut("Ptr", w.Ev, w.Ov, A_PtrSize = 8 ? 24 : 16)
        AxWatch.Arm(w)
        AxWatch.All.Push(w)
        if (AxWatch.All.Length = 1)
            SetTimer(ObjBindMethod(AxWatch, "Poll"), 100)
        return true
    }
    static Arm(w) {
        DllCall("ResetEvent", "Ptr", w.Ev)
        return DllCall("ReadDirectoryChangesW", "Ptr", w.H, "Ptr", w.Buf, "UInt", w.Buf.Size
                     , "Int", w.Subs, "UInt", w.Mask, "Ptr", 0, "Ptr", w.Ov, "Ptr", 0)
    }
    static Poll(*) {
        for w in AxWatch.All {
            if (DllCall("WaitForSingleObject", "Ptr", w.Ev, "UInt", 0) != 0)
                continue
            got := 0, seen := []
            if DllCall("GetOverlappedResult", "Ptr", w.H, "Ptr", w.Ov, "UInt*", &got, "Int", 0) && got {
                off := 0
                loop {
                    nxt := NumGet(w.Buf, off, "UInt"), act := NumGet(w.Buf, off + 4, "UInt")
                    len := NumGet(w.Buf, off + 8, "UInt")
                    seen.Push([act, StrGet(w.Buf.Ptr + off + 12, len // 2, "UTF-16")])
                    if !nxt
                        break
                    off += nxt
                }
            }
            AxWatch.Arm(w)
            for e in seen {
                if (e[1] = 4)                     ; the old name of a rename
                    continue
                file := w.Dir "\" e[2]
                if (w.Files != "" && !AxWatch.Match(e[2], w.Files))
                    continue
                kind := (e[1] = 1) ? "added" : (e[1] = 2) ? "removed" : (e[1] = 3) ? "changed" : "renamed"
                key := kind "|" file
                if (AxWatch.Last.Has(key) && A_TickCount - AxWatch.Last[key] < 300)
                    continue                      ; one save is several writes: one change
                if (AxWatch.Last.Count > 500)
                    AxWatch.Last.Clear()
                AxWatch.Last[key] := A_TickCount
                try w.Fn.Call(kind, file)
            }
        }
    }
    ; "*.pdf; report-??.txt" against the name alone
    static Match(name, pats) {
        SplitPath(name, &fn)
        for pat in StrSplit(pats, [";", ","], " ") {
            if (pat = "")
                continue
            rx := RegExReplace(pat, "[.+^$(){}|\[\]\\]", "\$0")
            if RegExMatch(fn, "i)^" StrReplace(StrReplace(rx, "*", ".*"), "?", ".") "$")
                return true
        }
        return false
    }
}

)"

    ; ================================================================ macros
    ; A header line, then its steps indented under it.
    static Macros(p) {
        out := [], cur := ""
        for raw in StrSplit(StrReplace(String(p.Macros), "`r", ""), "`n") {
            if (Trim(raw) = "" || SubStr(Trim(raw), 1, 1) = ";")
                continue
            if RegExMatch(raw, "^\s") {
                if IsObject(cur)
                    cur.Steps.Push(Trim(raw))
                continue
            }
            f := AxAuto.Split(raw, 4)
            name := AxProject.CleanName(f[1])
            if (name = "") {
                cur := ""
                continue
            }
            cur := {Name: name, Repeat: IsInteger(f[2]) ? Integer(f[2]) : 1,
                    Speed: IsNumber(f[3]) && f[3] > 0 ? f[3] + 0 : 1, Hotkey: f[4], Steps: []}
            out.Push(cur)
        }
        return out
    }
    static MacroText(list) {
        s := ""
        for m in list {
            s .= (s = "" ? "" : "`n") m.Name " | " m.Repeat " | " m.Speed " | " m.Hotkey
            for st in m.Steps
                s .= "`n    " st
        }
        return s
    }
    static FindMacro(p, name) {
        for m in AxAuto2.Macros(p)
            if (m.Name = name)
                return m
        return ""
    }
    ; One macro step, as code. The macro words first; anything else is a step
    ; word any rule, timer or hotkey knows.
    static MacroStep(p, st, speed) {
        t := Trim(st), q := Chr(34)
        sp := InStr(t, " "), verb := StrLower(sp ? SubStr(t, 1, sp - 1) : t), arg := sp ? Trim(SubStr(t, sp + 1)) : ""
        nums := []
        pos := 1
        while RegExMatch(arg, "-?\d+", &m, pos)
            nums.Push(Integer(m[0])), pos := m.Pos + m.Len
        btn := RegExMatch(arg, "i)\b(right|middle)\b", &bm) ? StrLower(bm[1]) : "left"
        switch verb {
        case "key":     return "Send(" AxLit.S(arg) ")"
        case "down":    return "Send(" AxLit.S("{" arg " down}") ")"
        case "up":      return "Send(" AxLit.S("{" arg " up}") ")"
        case "text":    return "SendText(" AxLit.S(arg) ")"
        case "wait":    return "Sleep(" Round((nums.Length ? nums[1] : 500) / speed) ")"
        case "click", "dblclick":
            cnt := (verb = "dblclick") ? 2 : 1
            return nums.Length >= 2 ? "Click(" nums[1] ", " nums[2] ", " q btn q ", " cnt ")" : "Click(" q btn q ", " cnt ")"
        case "move":    return nums.Length >= 2 ? "MouseMove(" nums[1] ", " nums[2] ", " Max(0, Round(4 / speed)) ")" : ""
        case "drag":
            return nums.Length >= 4 ? "MouseClickDrag(" q btn q ", " nums[1] ", " nums[2] ", " nums[3] ", " nums[4] ", " Max(0, Round(8 / speed)) ")" : ""
        case "scroll":
            dir := InStr(arg, "down") ? "WheelDown" : InStr(arg, "left") ? "WheelLeft" : InStr(arg, "right") ? "WheelRight" : "WheelUp"
            return "Click(" q dir q ", " (nums.Length ? nums[1] : 1) ")"
        case "activate": return "try WinActivate(" AxLit.S(arg) ")"
        case "waitwin":
            crit := RegExReplace(arg, "\s+\d+\s*s?$")
            secs := RegExMatch(arg, "(\d+)\s*s?$", &wm) ? wm[1] : 10
            return "if !WinWait(" AxLit.S(crit) ", , " secs ")`n        break`n    WinActivate()"
        case "stop":    return "return"
        ; an element of another window, through Descolada's UIA library:
        ;   uiclick  window | {Name: "Save"}
        ;   uitype   window | {AutomationId: "q"} | what to type
        ;   uiwait   window | {Name: "Done"} | 10
        ;   uiread   value window | {Type: 50020}
        ; The window is a WinTitle; the braces are the conditions to find the
        ; element by, as UIA-v2 takes them. A step whose element is not there
        ; ends the macro, the way waitwin does.
        case "uiclick", "uitype", "uiwait", "uiread":
            who := ""
            if (verb = "uiread") {
                who := RegExMatch(arg, "^(\S+)\s+(.*)$", &rm) ? rm[1] : ""
                arg := IsObject(rm) ? rm[2] : ""
                if (who = "")
                    return ""
            }
            u := AxAuto2.UiParts(arg)
            if (u.Cond = "")
                return ""
            wait := (verb = "uiwait" && IsNumber(u.Rest)) ? Round(u.Rest * 1000) : 3000
            find := "if !(axEl := AxUiaFind(" AxLit.S(u.Win) ", " u.Cond ", " wait "))`n        break"
            switch verb {
            case "uiclick": return find "`n    axEl.Click()"
            case "uitype":  return find "`n    axEl.Value := " AxLit.S(u.Rest)
            case "uiwait":  return find
            case "uiread":  return find "`n    " who " := axEl.Value" (AxBind.HasVar(p, who) ? ", AxBindSync()" : "")
            }
        }
        return AxAsset.StepCode(p, t)
    }
    ; "window | {conditions} | the rest" -- the conditions are kept as typed:
    ; an object literal, or a bare name taken to be the element's Name
    static UiParts(arg) {
        f := StrSplit(arg, "|", " `t", 3)
        c := f.Length >= 2 ? f[2] : ""
        if (c != "" && SubStr(c, 1, 1) != "{")
            c := "{Name: " AxLit.S(c) "}"
        return {Win: f[1], Cond: c, Rest: f.Length >= 3 ? f[3] : ""}
    }
    ; if / otherwise / end: a step that opens a block, and what it tests
    ;   if window ahk_exe notepad.exe
    ;   if element ahk_exe notepad.exe | {Name: "Save"}
    ;   if not window ... / if not element ...
    static IfCode(p, st) {
        if !RegExMatch(Trim(st), "i)^if\s+(not\s+)?(window|element)\s+(.*)$", &m)
            return ""
        neg := m[1] != "" ? "!" : ""
        if (StrLower(m[2]) = "window")
            return "if " neg "WinExist(" AxLit.S(Trim(m[3])) ")"
        u := AxAuto2.UiParts(m[3])
        return (u.Cond = "") ? "" : "if " neg "AxUiaFind(" AxLit.S(u.Win) ", " u.Cond ", 1500)"
    }
    static StepKind(st) {
        t := StrLower(Trim(st))
        if RegExMatch(t, "^if\s")
            return "if"
        return (t = "else" || t = "otherwise") ? "else" : (t = "end" || t = "end if") ? "end" : ""
    }
    ; whether any macro reaches into another window's elements
    static UsesUia(p) {
        for m in AxAuto2.Macros(p)
            for st in m.Steps
                if RegExMatch(Trim(st), "i)^(ui(click|type|wait|read)\s|if\s+(not\s+)?element\s)")
                    return true
        return false
    }
    static UiaHelper := "
    (
; An element of another window, found by UIA (Descolada/UIA): the window
; waited for, then the element, both up to wait ms. "" when it is not there.
AxUiaFind(win, cond, wait := 3000) {
    if !WinWait(win, , Max(1, wait // 1000))
        return ""
    try return UIA.ElementFromHandle(WinExist(win)).WaitElement(cond, wait) || ""
    return ""
}
    )"
    static MacroCode(p) {
        list := AxAuto2.Macros(p)
        if !list.Length
            return ""
        decl := AxAuto.Decl(p)
        s := "; Macros: keys, text, clicks and waits, played back. Escape stops one.`n"
        for m in list {
            body := "", depth := 0
            Pad := (d) => "            " (d ? Format("{:" d * 4 "}", "") : "")
            for st in m.Steps {
                switch AxAuto2.StepKind(st) {
                case "if":
                    c := AxAuto2.IfCode(p, st)
                    body .= Pad(depth) (c != "" ? c : "if false  `; " Trim(st)) " {`n"
                    depth++
                    continue
                case "else":
                    if depth
                        body .= Pad(depth - 1) "} else {`n"
                    continue
                case "end":
                    if depth
                        depth--, body .= Pad(depth) "}`n"
                    continue
                }
                c := AxAuto2.MacroStep(p, st, m.Speed)
                if (c = "")
                    continue
                if (c = "return") {                   ; stop: nothing after it could run
                    body .= Pad(depth) "return`n"
                    continue
                }
                body .= Pad(depth) StrReplace(c, "`n    ", "`n" Pad(depth)) "`n"
                      . Pad(depth) "if AxMacroStop`n" Pad(depth) "    break`n"
            }
            while depth                            ; an if left open is closed at the end
                depth--, body .= Pad(depth) "}`n"
            s .= "Macro_" m.Name "() {`n" decl "    global AxMacroStop`n"
               . "    static running := false`n    if running`n        return`n"
               . "    running := true, AxMacroStop := false`n"
               . "    CoordMode(" Chr(34) "Mouse" Chr(34) ", " Chr(34) "Screen" Chr(34) ")`n"
               . "    Hotkey(" Chr(34) "Esc" Chr(34) ", AxMacroHalt, " Chr(34) "On" Chr(34) ")`n"
               . "    try {`n        loop " (m.Repeat <= 0 ? "" : m.Repeat) " {`n"
               . (body != "" ? body : "            break`n")
               . "        }`n    } finally {`n"
               . "        Hotkey(" Chr(34) "Esc" Chr(34) ", " Chr(34) "Off" Chr(34) ")`n"
               . "        running := false`n    }`n}`n"
        }
        s .= "AxMacroStop := false`n"
           . "AxMacroHalt(*) {`n    global AxMacroStop := true`n}`n"
        if AxAuto2.UsesUia(p)
            s .= AxAuto2.UiaHelper "`n"
        return s
    }
    static MacroStart(p) {
        s := ""
        for m in AxAuto2.Macros(p)
            if (Trim(m.Hotkey) != "")
                s .= "Hotkey(" AxLit.S(m.Hotkey) ", (*) => Macro_" m.Name "())`n"
        return s
    }

    ; ============================================================== settings
    static SetKinds := "text:Text|number:A number|onoff:On or off|choice:One of a list|"
                     . "startup:Starts with Windows (the Startup folder)"
    static Settings(p) {
        out := []
        for line in AxAsset.Lines(p.Settings) {
            f := AxAuto.Split(line, 5)
            name := AxProject.CleanName(f[1])
            if (name != "")
                out.Push({Name: name, Default: f[2], Kind: f[3] = "" ? "text" : StrLower(f[3]),
                          Label: f[4] != "" ? f[4] : name, Options: f[5], Line: line})
        }
        return out
    }
    ; a setting's first value, as AutoHotkey
    static SetDefault(x) {
        if (x.Kind = "onoff" || x.Kind = "startup")
            return AxAsset.Truthy(x.Default) ? "1" : "0"
        if (x.Kind = "number")
            return IsNumber(x.Default) ? x.Default : "0"
        return AxLit.S(x.Default)
    }
    static SetCode(p) {
        list := AxAuto2.Settings(p)
        if !list.Length
            return ""
        names := ""
        for x in list
            names .= (names = "" ? "" : ", ") x.Name
        cfg := AxAsset.Compile(p)
        appdata := cfg.Has("settingsin") && cfg["settingsin"] = "appdata"
        app := (cfg.Has("name") && cfg["name"] != "") ? AxProject.CleanName(cfg["name"]) : ""
        q := Chr(34)
        s := "; Settings: remembered between runs, in a small .ini.`n"
           . "SettingsFile() {`n    static f := " q q "`n    if (f = " q q ") {`n"
        if appdata
            s .= "        dir := A_AppData " q "\" q " " (app != "" ? AxLit.S(app) : "RegExReplace(A_ScriptName, " q "\.[^.]*$" q ")") "`n"
               . "        try DirCreate(dir)`n        f := dir " q "\settings.ini" q "`n"
        else
            s .= "        f := RegExReplace(A_ScriptFullPath, " q "\.[^.\\]*$" q ") " q ".ini" q "`n"
        s .= "    }`n    return f`n}`n"
           . "SettingsLoad() {`n    global " names "`n    axF := SettingsFile()`n"
        for x in list {
            if (x.Kind = "startup") {
                s .= "    " x.Name " := AxStartupIs()`n"
                continue
            }
            s .= "    axV := IniRead(axF, " q "Settings" q ", " AxLit.S(x.Name) ", " x.Name ")`n"
               . "    " x.Name " := " ((x.Kind = "number" || x.Kind = "onoff") ? "IsNumber(axV) ? axV + 0 : " x.Name : "axV") "`n"
        }
        s .= "}`nSettingsSave() {`n    global " names "`n    axF := SettingsFile()`n"
        for x in list
            s .= (x.Kind = "startup") ? "    AxStartup(" x.Name ")`n"
               : "    try IniWrite(" x.Name ", axF, " q "Settings" q ", " AxLit.S(x.Name) ")`n"
        s .= "}`nSettingsReset() {`n    global " names "`n"
        for x in list
            s .= "    " x.Name " := " AxAuto2.SetDefault(x) "`n"
        return s "}`n"
    }

    ; ======================================================= start with Windows
    static NeedsStartup(p) {
        cfg := AxAsset.Compile(p)
        if (cfg.Has("startup") && AxAsset.Truthy(cfg["startup"]))
            return true
        for x in AxAuto2.Settings(p)
            if (x.Kind = "startup")
                return true
        all := p.Timers "`n" p.Strings "`n" p.Events "`n" p.Watchers "`n" p.Macros "`n" p.Modes
        for w in p.Wins
            all .= "`n" w.Hotkeys "`n" w.Flows
        return RegExMatch(all, "i)\bstartup\b") ? true : false
    }
    static StartupFns := "
(`
; A shortcut in the Startup folder: there, the program starts with Windows.
AxStartupLnk() => A_Startup "\" RegExReplace(A_ScriptName, "\.[^.]*$") ".lnk"
AxStartupIs() => FileExist(AxStartupLnk()) ? 1 : 0
AxStartup(on := 1) {
    lnk := AxStartupLnk()
    if !on {
        try FileDelete(lnk)
        return
    }
    if FileExist(lnk)
        return
    try {
        if A_IsCompiled
            FileCreateShortcut(A_ScriptFullPath, lnk, A_ScriptDir)
        else
            FileCreateShortcut(A_AhkPath, lnk, A_ScriptDir, '"' A_ScriptFullPath '"')
    }
}

)"

    ; ============================================================ the whole
    ; what runs at start, after the main window is up
    static StartCode(p) {
        s := ""
        cfg := AxAsset.Compile(p)
        if (cfg.Has("startup") && AxAsset.Truthy(cfg["startup"]))
            s .= "AxStartup(1)`n"
        if AxAuto2.Settings(p).Length
            s .= "OnExit((*) => (SettingsSave(), 0))`n"
        if AxAuto2.Watchers(p).Length
            s .= "AxWatchersStart()`n"
        if AxAuto2.Events(p).Length
            s .= "AxEventsStart()`n"
        s .= AxAuto2.MacroStart(p)
        return s
    }
    static Regions(p) {
        out := []
        for rg in [["settings", AxAuto2.SetCode(p)], ["progevents", AxAuto2.EventCode(p)],
                   ["watchers", AxAuto2.WatchCode(p)], ["macros", AxAuto2.MacroCode(p)],
                   ["startup", AxAuto2.NeedsStartup(p) ? AxAuto2.StartupFns : ""]]
            if (Trim(rg[2]) != "")
                out.Push(rg)
        return out
    }
}

; =============================================================================
;  The Logic sections, the forms, and the macro recorder.
; =============================================================================
class AxAuto2Ui {
    static PhHint := "Braces carry what happened: {file} {name} {kind} {window} {text} {drive} {mode} {reason}."
    ; ------------------------------------------------------------- settings
    static Settings(s, add) {
        list := AxAuto2.Settings(s.P)
        rows := ""
        for x in list
            rows .= '<tr><td class="axd-lgname" data-row="edit|' AxTags.E("settings|" x.Line) '">'
                 .  '<span class="ico">&#xE713;</span>' AxTags.E(x.Name) '</td>'
                 .  '<td>' AxTags.E(x.Label) '</td>'
                 .  '<td><span class="axd-dim">' AxTags.E(AxAuto2.KindWord(AxAuto2.SetKinds, x.Kind)) '</span></td>'
                 .  '<td class="axd-mono">' AxTags.E(x.Kind = "startup" ? "(the Startup folder)" : x.Default) '</td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("settings", x.Line) '</td></tr>'
        list2 := (rows = "") ? "" : AxLogic.Table(["Setting", "Shown as", "Kind", "First value", ""], rows)
                 . '<div class="axd-note"><span class="axd-hbtn" data-do="set.page">Put them on this page, as setting rows</span> '
                 . 'Each becomes a row with the right control, bound to the setting.</div>'
        raw := add({Id: "lg_settings", L: "One per line", Kind: "multiline", Rows: 5,
                    Get: (*) => s.P.Settings, Set: (v) => (s.P.Settings := v, s.QueueLive())})
             . '<div class="axd-note"><b>name | first value | kind | label | options</b> -- kinds are text, '
             . 'number, onoff, choice (options a,b,c) and startup.</div>'
        return AxLogic.Wrap(s, "settings", "Settings (" list.Length ")",
            '<span class="axd-hbtn" data-do="set.add">Add a setting...</span>', list2, raw,
            "What the program you are making remembers between runs -- its own settings, kept in a "
            . "small .ini. Each is a value too: bind it to a control, set it in a rule, read it in code.")
    }
    static Setting(s, old := "") {
        O := (k, d) => IsObject(old) ? old.%k% : d
        r := AxForm.Show(s, {Title: IsObject(old) ? "Change a setting" : "Add a setting", Icon: "E713", Width: 520,
            Intro: "Something the program keeps from one run to the next.",
            Fields: [
                {Id: "name", L: "Called", Kind: "text", V: O("Name", "theme"), Hint: "The value your code and rules use."},
                {Id: "label", L: "Shown as", Kind: "text", V: O("Label", "Theme")},
                {Id: "kind", L: "Kind", Kind: "choice", V: O("Kind", "text"), Opts: AxAuto2.SetKinds},
                {Id: "def", L: "First value", Kind: "text", V: O("Default", ""),
                 When: (V) => V["kind"] != "startup", Hint: "What it is until somebody changes it. On or off: 1 or 0."},
                {Id: "opts", L: "The choices", Kind: "text", V: O("Options", "dark,light,system"),
                 When: (V) => V["kind"] = "choice", Hint: "With commas between."}],
            Buttons: [IsObject(old) ? "Save" : "Add it", "Cancel"],
            Check: (V) => AxProject.CleanName(V["name"]) = "" ? "Enter a name." : ""})
        if !r.Ok
            return
        s.PutLine("Settings", IsObject(old) ? old.Line : "",
            AxProject.CleanName(r.V["name"]) " | " Trim(r.V["def"]) " | " r.V["kind"] " | " Trim(r.V["label"])
            . (r.V["kind"] = "choice" ? " | " Trim(r.V["opts"]) : ""))
        s.LogicSec := "settings"
        s.Refresh()
    }
    ; A card of setting rows, each bound to its setting, on the page in front.
    static ToPage(s) {
        list := AxAuto2.Settings(s.P)
        if !list.Length
            return
        s.Mark()
        P := s.P
        card := P.NewNode("Card")
        card.Arg := "Settings"
        P.Insert(s.CurPage() ? s.CurPage() : P.Root, card)
        binds := ""
        for x in list {
            row := P.NewNode("Row")
            row.Arg := x.Label
            if (x.Kind = "startup")
                row.P["desc"] := "Adds a shortcut to the Startup folder"
            P.Insert(card, row)
            type := (x.Kind = "onoff" || x.Kind = "startup") ? "Switch" : (x.Kind = "number") ? "Number"
                  : (x.Kind = "choice") ? "DDL" : "Edit"
            if !AxCat.Has(type)
                continue
            c := P.NewNode(type)
            c.Name := P.NewName("set" x.Name)
            ; showing its first value, as it will before the last run's is put back
            if (type = "DDL") {
                opts := ""
                for o in StrSplit(x.Options, ",", " ")
                    opts .= (opts = "" ? "" : "`n") o ":" o
                c.Arg := opts
                c.P["value"] := x.Default
            } else if (type = "Switch") {
                c.P["nolabel"] := 1
                if (x.Kind = "onoff" && AxAsset.Truthy(x.Default))
                    c.P["checked"] := 1
            } else
                c.Arg := x.Default
            P.Insert(row, c)
            binds .= "`n" c.Name " <-> " x.Name
        }
        P.W.Binds := Trim(String(P.W.Binds) binds, "`r`n")
        s.SelIds := [card.Id]
        s.SetWs("design")
        s.Refresh()
        s.Status("msg", list.Length " setting rows, each bound to its setting. Their values are saved when the program closes.")
    }

    ; --------------------------------------------------------------- events
    static Events(s, add) {
        list := AxAuto2.Events(s.P)
        rows := ""
        for e in list
            rows .= '<tr><td class="axd-lgname" data-row="edit|' AxTags.E("events|" e.Line) '">'
                 .  '<span class="ico">&#xE7C1;</span>' AxTags.E(AxAuto2.KindWord(AxAuto2.EventKinds, e.Kind)) '</td>'
                 .  '<td><span class="axd-dim">' AxTags.E((e.Kind = "idle" || e.Kind = "back") && e.Detail != "" ? "after " e.Detail " s" : e.Detail) '</span></td>'
                 .  '<td>' AxTags.E(e.Text) '</td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("events", e.Line) '</td></tr>'
        list2 := (rows = "") ? "" : AxLogic.Table(["When", "Which", "Does", ""], rows)
        raw := add({Id: "lg_events", L: "One per line", Kind: "multiline", Rows: 5,
                    Get: (*) => s.P.Events, Set: (v) => (s.P.Events := v, s.QueueLive())})
             . '<div class="axd-note"><b>event | detail | steps</b>. ' AxAuto2Ui.PhHint '</div>'
        return AxLogic.Wrap(s, "events", "When something happens in Windows (" list.Length ")",
            '<span class="axd-hbtn" data-do="ev.add">Add one...</span>', list2, raw,
            "What the program does when something happens around it: a window opens, the clipboard "
            . "changes, the screen locks, a drive is plugged in, the computer wakes up.")
    }
    static Event(s, old := "") {
        O := (k, d) => IsObject(old) ? old.%k% : d
        r := AxForm.Show(s, {Title: IsObject(old) ? "Change an event" : "Add an event", Icon: "E7C1", Width: 540,
            Intro: "When this happens, the program does the steps.",
            Fields: [
                {Id: "kind", L: "When", Kind: "choice", V: O("Kind", "clipboard"), Opts: AxAuto2.EventKinds},
                {Id: "detail", L: "Which", Kind: "text", V: O("Detail", ""),
                 Hint: "A window: ahk_exe notepad.exe or some title text.  The clipboard: text, or blank for anything.  "
                     . "Idle: seconds.  The end: Logoff, Shutdown, Close, Exit -- or blank for any.  A message: its number."},
                {Id: "steps", L: "Does", Kind: "text", V: O("Text", "toast Copied: {text}"),
                 Hint: AxAutoUi.StepHint " " AxAuto2Ui.PhHint}],
            Buttons: [IsObject(old) ? "Save" : "Add it", "Cancel"],
            Check: (V) => Trim(V["steps"]) = "" ? "Say what it does." : ""})
        if !r.Ok
            return
        s.PutLine("Events", IsObject(old) ? old.Line : "", r.V["kind"] " | " Trim(r.V["detail"]) " | " Trim(r.V["steps"]))
        s.LogicSec := "events"
        s.Refresh()
    }

    ; ------------------------------------------------------------- watchers
    static Watchers(s, add) {
        list := AxAuto2.Watchers(s.P)
        rows := ""
        for w in list
            rows .= '<tr><td class="axd-lgname" data-row="edit|' AxTags.E("watchers|" w.Line) '">'
                 .  '<span class="ico">&#xE8B7;</span>' AxTags.E(w.Name) '</td>'
                 .  '<td class="axd-mono">' AxTags.E(w.Folder) (w.Subs ? " (and below)" : "") '</td>'
                 .  '<td><span class="axd-dim">' AxTags.E((w.Files = "" ? "any file" : w.Files) ", " w.When) '</span></td>'
                 .  '<td>' AxTags.E(w.Text) '</td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("watchers", w.Line) '</td></tr>'
        list2 := (rows = "") ? "" : AxLogic.Table(["Watcher", "Folder", "Files", "Does", ""], rows)
        raw := add({Id: "lg_watchers", L: "One per line", Kind: "multiline", Rows: 4,
                    Get: (*) => s.P.Watchers, Set: (v) => (s.P.Watchers := v, s.QueueLive())})
             . '<div class="axd-note"><b>name | folder | files | when | subfolders | steps</b> -- when is added, '
             . 'removed, changed, renamed (commas) or any.</div>'
        return AxLogic.Wrap(s, "watchers", "When a folder changes (" list.Length ")",
            '<span class="axd-hbtn" data-do="watch.add">Watch a folder...</span>', list2, raw,
            "A file appears, changes, goes or is renamed in a folder, and the program does the steps. Windows "
            . "tells it -- nothing is scanned, however big the folder.")
    }
    static Watcher(s, old := "") {
        O := (k, d) => IsObject(old) ? old.%k% : d
        when := O("When", "added")
        r := AxForm.Show(s, {Title: IsObject(old) ? "Change a folder watcher" : "Watch a folder", Icon: "E8B7", Width: 560,
            Intro: "When something changes in the folder, the program does the steps.",
            Fields: [
                {Id: "name", L: "Called", Kind: "text", V: O("Name", "inbox")},
                {Id: "folder", L: "Folder", Kind: "text", V: O("Folder", "A_MyDocuments\Inbox"),
                 Hint: "A path, or A_Desktop, A_MyDocuments, A_ScriptDir... followed by \more."},
                {Id: "files", L: "Files", Kind: "text", V: O("Files", "*.*"), Hint: "*.pdf; report-??.txt -- or blank for any."},
                {Id: "h1", L: "When a file is", Kind: "heading"},
                {Id: "added", L: "Added", Kind: "flag", V: (when = "any" || InStr(when, "added")) ? 1 : 0},
                {Id: "changed", L: "Changed", Kind: "flag", V: (when = "any" || InStr(when, "changed")) ? 1 : 0},
                {Id: "removed", L: "Removed", Kind: "flag", V: (when = "any" || InStr(when, "removed")) ? 1 : 0},
                {Id: "renamed", L: "Renamed", Kind: "flag", V: (when = "any" || InStr(when, "renamed")) ? 1 : 0},
                {Id: "subs", L: "And in the folders inside it", Kind: "flag", V: O("Subs", 0) ? 1 : 0},
                {Id: "steps", L: "Does", Kind: "text", V: O("Text", "toast New: {name}"),
                 Hint: AxAutoUi.StepHint " {file} is the whole path, {name} the file's name, {kind} what happened."}],
            Buttons: [IsObject(old) ? "Save" : "Add it", "Cancel"],
            Check: (V) => AxProject.CleanName(V["name"]) = "" ? "Enter a name."
                        : Trim(V["folder"]) = "" ? "Say which folder."
                        : !(V["added"] || V["changed"] || V["removed"] || V["renamed"]) ? "Tick at least one kind of change." : ""})
        if !r.Ok
            return
        w := ""
        for k in ["added", "changed", "removed", "renamed"]
            if r.V[k]
                w .= (w = "" ? "" : ",") k
        s.PutLine("Watchers", IsObject(old) ? old.Line : "",
            AxProject.CleanName(r.V["name"]) " | " Trim(r.V["folder"]) " | " Trim(r.V["files"]) " | " w
            . " | " (r.V["subs"] ? "yes" : "no") " | " Trim(r.V["steps"]))
        s.LogicSec := "watchers"
        s.Refresh()
    }

    ; --------------------------------------------------------------- macros
    static MacroHint := "Macro steps: key ^c, key {Enter}, down Shift, up Shift, text Hello, wait 300, click 100 200, "
        . "click right 100 200, dblclick 100 200, move 500 300, drag 10 10 200 10, scroll down 3, activate ahk_exe notepad.exe, "
        . "waitwin Untitled - Notepad 10s -- and any step word: run, toast, play, set, start... Blocks: if window ahk_exe x.exe, "
        . "if element ahk_exe x.exe | {Name: `"Save`"}, if not ..., else, end; stop ends the macro. Another window's elements: "
        . "uiclick, uitype, uiwait and uiread (Descolada/UIA), written for you by Pick an element."
    static Macros(s, add) {
        list := AxAuto2.Macros(s.P)
        if (!IsObject(AxAuto2.FindMacro(s.P, s.MacroSel)) && list.Length)
            s.MacroSel := list[1].Name
        rows := ""
        for m in list
            rows .= '<tr' (m.Name = s.MacroSel ? ' class="axd-rowon"' : "") '><td class="axd-lgname" data-mac="' AxTags.E(m.Name) '">'
                 .  '<span class="ico">&#xE768;</span>' AxTags.E(m.Name) '</td>'
                 .  '<td>' m.Steps.Length ' step' (m.Steps.Length = 1 ? "" : "s") '</td>'
                 .  '<td><span class="axd-dim">' (m.Repeat <= 0 ? "until Escape" : m.Repeat = 1 ? "once" : m.Repeat " times")
                 .  (m.Speed != 1 ? ", " m.Speed "x speed" : "") '</span></td>'
                 .  '<td class="axd-mono">' AxTags.E(m.Hotkey != "" ? AxLogic.KeyWords(m.Hotkey) : "") '</td>'
                 .  '<td class="axd-narrow"><span class="axd-racts"><span class="axd-ract" data-mac="' AxTags.E(m.Name) '">Open</span>'
                 .  '<span class="axd-ract axd-ractdel" data-macdel="' AxTags.E(m.Name) '" data-tip="Remove it. Ctrl+Z brings it back.">&#xE711;</span></span></td></tr>'
        list2 := (rows = "") ? "" : AxLogic.Table(["Macro", "Steps", "Plays", "Hotkey", ""], rows)
        m := AxAuto2.FindMacro(s.P, s.MacroSel)
        if IsObject(m)
            list2 .= AxAuto2Ui.MacroEditor(s, add, m)
        raw := add({Id: "lg_macros", L: "The macros", Kind: "multiline", Rows: 8,
                    Get: (*) => s.P.Macros, Set: (v) => (s.P.Macros := v, s.QueueLive())})
             . '<div class="axd-note">A line <b>name | repeat | speed | hotkey</b>, then its steps indented under it.</div>'
        return AxLogic.Wrap(s, "macros", "Macros (" list.Length ")",
            '<span class="axd-hbtn" data-do="mac.add">Add a macro</span>', list2, raw,
            "Keys, text, clicks and waits, played back -- by a hotkey, a hotstring, a timer, a rule "
            . "(play name) or your code (Macro_name()). Record one, or build it step by step. Escape stops it.")
    }
    static MacroEditor(s, add, m) {
        nm := m.Name
        ; by the one open now, not by the name it had when drawn: the name
        ; box commits on every key, and each key renames it
        F := (fld) => (v) => AxAuto2Ui.MacroSet(s, s.MacroSel, fld, v)
        b := (k, t) => '<span class="axd-hbtn" data-macstep="' k '">' t '</span> '
        return '<div class="axd-rpform axd-maced"><div class="axd-rpsub">The macro ' AxTags.E(nm) '</div>'
             . add({Id: "mc_name", L: "Called", Kind: "text", Get: (*) => nm, Set: F("Name")})
             . add({Id: "mc_repeat", L: "Plays", Kind: "choice", Get: (*) => String(m.Repeat), Set: F("Repeat"), Rebuild: true,
                    Opts: "1:Once|2:Twice|3:3 times|5:5 times|10:10 times|0:Until Escape"})
             . add({Id: "mc_speed", L: "Speed", Kind: "choice", Get: (*) => String(m.Speed), Set: F("Speed"), Rebuild: true,
                    Opts: "0.5:Half speed|1:As recorded|2:Twice as fast|4:Four times as fast|10:As fast as it can"})
             . add({Id: "mc_hotkey", L: "Hotkey", Kind: "text", Get: (*) => m.Hotkey, Set: F("Hotkey"),
                    Hint: "^!m is Ctrl+Alt+M -- blank for none"})
             . add({Id: "mc_steps", L: "Steps", Kind: "options", Shape: "st", Get: (*) => AxAuto2Ui.JoinSteps(m),
                    Set: F("Steps")})
             . '<div class="axd-align">' b("key", "+ Keys") b("text", "+ Text") b("wait", "+ Wait") b("click", "+ Click")
             . b("move", "+ Move") b("scroll", "+ Scroll") b("activate", "+ Window") b("waitwin", "+ Wait for a window")
             . b("run", "+ Run") '</div>'
             . '<div class="axd-align">' b("if", "+ If a window is there") b("ifel", "+ If an element is there")
             . b("else", "+ Otherwise") b("end", "+ End") b("stop", "+ Stop") '</div>'
             . '<div class="axd-align"><span class="axd-hbtn axd-go" data-pkg="uiapick">Pick an element...</span> '
             . '<span class="axd-dim">Point at a button, a box, a menu in any program: the macro clicks it, types into it, '
             . 'waits for it or reads it -- found again by what it is, not where it was.</span></div>'
             . '<div class="axd-align"><span class="axd-hbtn axd-go" data-do="mac.record">Record...</span> '
             . '<span class="axd-dim">Keys, clicks, scrolling and the pauses between them, until F12.</span></div>'
             . '<div class="axd-note">' AxAuto2Ui.MacroHint '</div></div>'
    }
    static JoinSteps(m) {
        s := ""
        for st in m.Steps
            s .= (s = "" ? "" : "`n") st
        return s
    }
    ; one field of one macro, written back into the text
    static MacroSet(s, name, fld, v) {
        list := AxAuto2.Macros(s.P)
        for m in list {
            if (m.Name != name)
                continue
            switch fld {
            case "Name":
                nn := AxProject.CleanName(v)
                if (nn = "" || IsObject(AxAuto2.FindMacro(s.P, nn)))
                    return
                m.Name := nn, s.MacroSel := nn
            case "Repeat": m.Repeat := IsInteger(v) ? Integer(v) : 1
            case "Speed":  m.Speed := IsNumber(v) ? v + 0 : 1
            case "Hotkey": m.Hotkey := Trim(v)
            case "Steps":
                m.Steps := []
                for line in StrSplit(StrReplace(v, "`r", ""), "`n")
                    if (Trim(line) != "")
                        m.Steps.Push(Trim(line))
            }
        }
        s.P.Macros := AxAuto2.MacroText(list)
        s.QueueLive()
    }
    static AddMacro(s) {
        s.Mark()
        n := 1
        while IsObject(AxAuto2.FindMacro(s.P, "macro" n))
            n++
        list := AxAuto2.Macros(s.P)
        list.Push({Name: "macro" n, Repeat: 1, Speed: 1, Hotkey: "", Steps: ["key #r", "wait 400", "text notepad", "key {Enter}"]})
        s.P.Macros := AxAuto2.MacroText(list)
        s.MacroSel := "macro" n
        s.GoSec("macros", "logic")
    }
    static AddStep(s, kind) {
        static tpl := Map("key", "key ^c", "text", "text Hello", "wait", "wait 500", "click", "click 100 200",
                          "move", "move 500 300", "scroll", "scroll down 3", "activate", "activate ahk_exe notepad.exe",
                          "waitwin", "waitwin ahk_exe notepad.exe 10s", "run", "run notepad.exe",
                          "if", "if window ahk_exe notepad.exe", "ifel", "if element ahk_exe notepad.exe | {Name: `"Save`"}",
                          "else", "else", "end", "end", "stop", "stop")
        m := AxAuto2.FindMacro(s.P, s.MacroSel)
        if !IsObject(m)
            return
        s.Mark()
        AxAuto2Ui.MacroSet(s, m.Name, "Steps", AxAuto2Ui.JoinSteps(m) "`n" (tpl.Has(kind) ? tpl[kind] : kind))
        s.Reflect(false)
    }
    static DropMacro(s, name) {
        s.Mark()
        out := []
        for m in AxAuto2.Macros(s.P)
            if (m.Name != name)
                out.Push(m)
        s.P.Macros := AxAuto2.MacroText(out)
        s.Reflect(false)
    }
}

; =============================================================================
;  Recording a macro: the keys through an InputHook that lets them pass,
;  clicks and the wheel through pass-through hotkeys, the pauses from the
;  clock -- until F12. The studio steps aside while it listens.
; =============================================================================
class AxRecorder {
    static S := "", Name := "", Steps := [], Text := "", Last := 0, Ih := "", Opts := "", On := false, Quiet := false
    static Start(s) {
        m := AxAuto2.FindMacro(s.P, s.MacroSel)
        if !IsObject(m)
            return
        r := AxForm.Show(s, {Title: "Record " m.Name, Icon: "E7C8", Width: 500,
            Intro: "When you press Start, the studio steps aside. Do what the macro should do; press F12 to stop. "
                 . "What you record is added after the steps it has.",
            Fields: [{Id: "clicks", L: "Mouse clicks and the wheel", Kind: "flag", V: 1},
                     {Id: "pauses", L: "The pauses between things", Kind: "flag", V: 1},
                     {Id: "keep", L: "Keep the steps it has", Kind: "flag", V: 1}],
            Buttons: ["Start", "Cancel"]})
        if !r.Ok
            return
        AxRecorder.S := s, AxRecorder.Name := m.Name, AxRecorder.Opts := r.V
        AxRecorder.Steps := [], AxRecorder.Text := "", AxRecorder.Last := A_TickCount
        ih := InputHook("V")
        ih.KeyOpt("{All}", "N")
        ih.OnKeyDown := (hook, vk, sc) => AxRecorder.Key(vk, sc)
        ih.OnChar := (hook, ch) => AxRecorder.Char(ch)
        ih.Start()
        AxRecorder.Ih := ih
        if r.V["clicks"]
            for k in ["~*LButton", "~*RButton", "~*MButton", "~*WheelUp", "~*WheelDown"]
                Hotkey(k, ObjBindMethod(AxRecorder, "Mouse", k), "On")
        Hotkey("F12", (*) => AxRecorder.Stop(), "On")
        AxRecorder.On := true
        try WinMinimize("ahk_id " s.Hwnd)
        ToolTip("Recording " m.Name " -- F12 stops", 10, 10)
    }
    static Gap() {
        now := A_TickCount, d := now - AxRecorder.Last
        AxRecorder.Last := now
        return d
    }
    static Pause(d) {
        if (AxRecorder.Opts["pauses"] && d >= 150)
            AxRecorder.Steps.Push("wait " Round(d / 50) * 50)
    }
    static Flush() {
        if (AxRecorder.Text != "")
            AxRecorder.Steps.Push("text " AxRecorder.Text), AxRecorder.Text := ""
    }
    static Mods() {
        if AxRecorder.Quiet                     ; fed by the probe: the keyboard is someone else's
            return ""
        m := ""
        m .= GetKeyState("Ctrl") ? "^" : ""
        m .= GetKeyState("Alt") ? "!" : ""
        m .= (GetKeyState("LWin") || GetKeyState("RWin")) ? "#" : ""
        return m
    }
    ; keys that do not type: Enter, Tab, the arrows, F-keys -- and anything
    ; with Ctrl, Alt or Win held
    static Key(vk, sc) {
        if !AxRecorder.On
            return
        name := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
        if (name = "" || name = "F12" || InStr("|LControl|RControl|Control|LShift|RShift|Shift|LAlt|RAlt|Alt|LWin|RWin|", "|" name "|"))
            return
        mods := AxRecorder.Mods()
        if (mods = "" && (StrLen(name) = 1 || name = "Space"))
            return                                    ; it types: OnChar has it
        d := AxRecorder.Gap()
        AxRecorder.Flush()
        AxRecorder.Pause(d)
        if (!AxRecorder.Quiet && GetKeyState("Shift"))
            mods .= "+"
        AxRecorder.Steps.Push("key " mods (StrLen(name) = 1 ? StrLower(name) : "{" name "}"))
    }
    static Char(ch) {
        if (!AxRecorder.On || Ord(ch) < 32 || AxRecorder.Mods() != "")
            return
        d := AxRecorder.Gap()
        if (d >= 800 && AxRecorder.Text != "") {
            AxRecorder.Flush()
            AxRecorder.Pause(d)
        } else if (AxRecorder.Text = "")
            AxRecorder.Pause(d)
        AxRecorder.Text .= ch
    }
    static Mouse(key, *) {
        if !AxRecorder.On
            return
        d := AxRecorder.Gap()
        AxRecorder.Flush()
        AxRecorder.Pause(d)
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        k := StrReplace(key, "~*")
        switch k {
        case "LButton": AxRecorder.Steps.Push("click " x " " y)
        case "RButton": AxRecorder.Steps.Push("click right " x " " y)
        case "MButton": AxRecorder.Steps.Push("click middle " x " " y)
        case "WheelUp", "WheelDown":
            dir := (k = "WheelUp") ? "up" : "down"
            n := AxRecorder.Steps.Length
            if (n && RegExMatch(AxRecorder.Steps[n], "^scroll " dir " (\d+)$", &sm))
                AxRecorder.Steps[n] := "scroll " dir " " (sm[1] + 1)
            else
                AxRecorder.Steps.Push("scroll " dir " 1")
        }
    }
    static Stop() {
        if !AxRecorder.On
            return
        AxRecorder.On := false
        AxRecorder.Flush()
        try AxRecorder.Ih.Stop()
        for k in ["~*LButton", "~*RButton", "~*MButton", "~*WheelUp", "~*WheelDown"]
            try Hotkey(k, "Off")
        try Hotkey("F12", "Off")
        ToolTip()
        s := AxRecorder.S
        if !AxRecorder.Quiet {              ; the probe feeds it by hand, and never takes focus
            try WinRestore("ahk_id " s.Hwnd)
            try WinActivate("ahk_id " s.Hwnd)
        }
        m := AxAuto2.FindMacro(s.P, AxRecorder.Name)
        if !IsObject(m)
            return
        s.Mark()
        text := ""
        for st in AxRecorder.Steps
            text .= (text = "" ? "" : "`n") st
        AxAuto2Ui.MacroSet(s, m.Name, "Steps", (AxRecorder.Opts["keep"] ? AxAuto2Ui.JoinSteps(m) "`n" : "") text)
        s.GoSec("macros", "logic")
        s.Status("msg", "Recorded " AxRecorder.Steps.Length " steps into " m.Name ".")
    }
}
