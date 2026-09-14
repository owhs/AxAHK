#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Form.ahk
#Include %A_LineFile%\..\AxStudio.Model.ahk

; Part of AxStudio, not a program on its own. Running this file directly would
; only load a class and stop, so it hands over to the entry point instead.
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
;  AxStudio.Helpers.ahk -- the AutoHotkey a real script keeps needing.
;
;  A window is the easy half. The half that makes something worth running is
;  the plumbing around it: a hotkey that only works in the right place, a
;  listener that hears a device arrive, a timer that does not pile up, a
;  settings file, a tray menu, restarting elevated. All of it is well known and
;  none of it is enjoyable to type from memory, so it lives here as a list.
;
;  An entry is data:
;      Id      what the palette and the settings file call it
;      Cat     which group it appears under
;      Name    one line, in plain words
;      Desc    what it is for, and the catch if there is one
;      Fields  AxForm fields -- what this helper needs to know
;      Init    (V) -> the lines that go in the startup code
;      Fn      (V) -> the functions that go with them, at file level
;
;  The code itself is written in continuation sections, so what is in this file
;  looks exactly like what it writes -- real quotes, real backticks, nothing
;  escaped and nothing to get wrong. Three things to know about those:
;
;      "                     a lone quote is literal in there; "" would be TWO
;      (`                    the backtick option, or `n in the code being
;                            written would turn into an actual newline
;      )                     a line starting with ) ENDS the section, so a line
;                            of generated code must never begin with one
;
;  A section cannot have anything substituted into it, so the answers arrive as
;  {name} placeholders and AxHelp.Fill puts them in. An unknown one is left
;  alone, which is what keeps Send("{Enter}") intact.
;
;  Every entry's default output is run through the interpreter's own parser by
;  the check harness, so a helper that does not compile cannot ship.
; =============================================================================
class AxHelp {
    static _all := ""

    static All() {
        if IsObject(AxHelp._all)
            return AxHelp._all
        out := []
        H := (id, cat, name, desc, icon, fields, init, fn := "") =>
             out.Push({Id: id, Cat: cat, Name: name, Desc: desc, Icon: icon,
                       Fields: fields, Init: init, Fn: fn})

        ; ================================================ keys and typing
        H("hotstring", "Keys and typing", "An abbreviation that expands",
          "Type the short form and it replaces itself with the long one.", "E92E",
          [{Id: "short", L: "You type", Kind: "text", V: "btw"},
           {Id: "long",  L: "It becomes", Kind: "text", V: "by the way"},
           {Id: "here",  L: "Only while this window is in front", Kind: "flag", V: 0,
            Hint: "Off means it works in every program."}],
          (V) => AxHelp.Scoped(V["here"], AxHelp.Fill('Hotstring("::{short}", "{long}")',
              Map("short", AxHelp.Bare(V["short"]), "long", AxHelp.Esc(V["long"])))))

        H("remap", "Keys and typing", "Turn one key into another",
          "A remap is a hotkey whose whole job is to send a different key.", "E765",
          [{Id: "from", L: "Press", Kind: "hotkey", V: "CapsLock"},
           {Id: "to",   L: "Send",  Kind: "text",   V: "Escape",
            Hint: "A key name, on its own."},
           {Id: "here", L: "Only while this window is in front", Kind: "flag", V: 1}],
          ; Fill puts the answer inside the braces Send wants, so {to} becomes
          ; Escape and the line comes out as Send("{Escape}")
          (V) => AxHelp.Scoped(V["here"], AxHelp.Fill('Hotkey("{from}", (*) => Send("{{to}}"))',
              Map("from", AxHelp.Esc(V["from"]), "to", AxHelp.Bare(V["to"])))))

        H("paste", "Keys and typing", "Paste text into whatever is in front",
          "Goes through the clipboard, which is the only reliable way to put a lot of "
        . "text somewhere, and puts back what was there.", "E77F",
          [{Id: "hk",   L: "Hotkey", Kind: "hotkey", V: "^!v"},
           {Id: "text", L: "Text",   Kind: "multiline", Rows: 3, V: "Yours sincerely,"}],
          (V) => AxHelp.Fill('Hotkey("{hk}", (*) => PasteText("{text}"))',
              Map("hk", AxHelp.Esc(V["hk"]), "text", AxHelp.Esc(V["text"]))),
          (V) => "
          (`
; Put text into the window in front. The clipboard is restored afterwards,
; because taking someone's clipboard and not giving it back is rude.
PasteText(text) {
    saved := ClipboardAll()
    A_Clipboard := text
    if !ClipWait(1) {
        A_Clipboard := saved
        return false
    }
    Send("^v")
    Sleep 120
    A_Clipboard := saved
    return true
}
          )")

        H("longpress", "Keys and typing", "Tell a tap from a long press",
          "One key, two jobs: a quick tap does one thing, holding it does another.", "E916",
          [{Id: "hk", L: "Key",      Kind: "hotkey", V: "F1"},
           {Id: "ms", L: "Held for", Kind: "int", V: 350, Min: 100, Max: 2000, Suffix: "ms"}],
          (V) => AxHelp.Fill('Hotkey("{hk}", (*) => OnTapOrHold("{hk}", {ms}))',
              Map("hk", AxHelp.Esc(V["hk"]), "ms", AxHelp.Int(V["ms"], 350))),
          (V) => "
          (`
OnTapOrHold(key, ms) {
    global g
    t := A_TickCount
    KeyWait(RegExReplace(key, "[#!^+]"))          ; wait for it to come back up
    if (A_TickCount - t >= ms)
        g.Toast("held")
    else
        g.Toast("tapped")
}
          )")

        H("inputhook", "Keys and typing", "Read a line of typing without a text box",
          "Collects keys until Enter or Escape, from anywhere. The start of a command bar.",
          "E721",
          [{Id: "hk", L: "Opens with", Kind: "hotkey", V: "^!Space"}],
          (V) => AxHelp.Fill('Hotkey("{hk}", (*) => ReadALine())',
              Map("hk", AxHelp.Esc(V["hk"]))),
          (V) => "
          (`
ReadALine() {
    global g
    ih := InputHook("V T10", "{Enter}{Escape}")   ; V lets the keys through as usual
    ih.Start()
    ih.Wait()
    if (ih.EndReason != "EndKey" || ih.EndKey = "Escape")
        return
    g.Toast("you typed: " ih.Input)
}
          )")

        ; =============================================== windows and apps
        H("waitwin", "Windows and apps", "Wait for a window, then do something",
          "Blocks until it turns up, or gives up after the timeout.", "E7C4",
          [{Id: "win", L: "Window", Kind: "text", V: "ahk_exe notepad.exe",
            Hint: "Title text, ahk_class Notepad, ahk_exe notepad.exe, ahk_id ..."},
           {Id: "sec", L: "Give up after", Kind: "int", V: 10, Min: 1, Max: 600, Suffix: "s"}],
          (V) => AxHelp.Fill("
          (`
if WinWait("{win}", , {sec}) {
    WinActivate()
    g.Toast("it is here")
} else
    g.Toast("gave up waiting")
          )", Map("win", AxHelp.Esc(V["win"]), "sec", AxHelp.Int(V["sec"], 10))))

        H("watchwin", "Windows and apps", "Notice when a window opens or closes",
          "Checks a few times a second and says the moment it changes. Cheap, and it "
        . "works for every window -- unlike a shell hook.", "E7B3",
          [{Id: "win", L: "Window", Kind: "text", V: "ahk_exe notepad.exe"},
           {Id: "ms",  L: "Check every", Kind: "int", V: 400, Min: 100, Max: 5000, Suffix: "ms"}],
          (V) => AxHelp.Fill('SetTimer(() => WatchWindow("{win}"), {ms})',
              Map("win", AxHelp.Esc(V["win"]), "ms", AxHelp.Int(V["ms"], 400))),
          (V) => "
          (`
WatchWindow(win) {
    global g
    static was := false
    now := WinExist(win) ? true : false
    if (now = was)
        return
    was := now
    g.Toast(now ? "opened" : "closed")
}
          )")

        H("runwait", "Windows and apps", "Run a command and read what it printed",
          "Runs it with no console window and hands back everything it wrote.", "E756",
          [{Id: "cmd", L: "Command", Kind: "text", V: "ipconfig /all"}],
          (V) => AxHelp.Fill('g.Toast(SubStr(RunCapture("{cmd}"), 1, 200))',
              Map("cmd", AxHelp.Esc(V["cmd"]))),
          (V) => "
          (`
; cmd.exe with its output piped back. Nothing flashes up on screen.
RunCapture(command) {
    shell := ComObject("WScript.Shell")
    exec := shell.Exec(A_ComSpec " /c " command)
    return exec.StdOut.ReadAll()
}
          )")

        H("running", "Windows and apps", "Start a program only if it is not already up",
          "The usual launcher behaviour: bring it to the front if it is there, start it "
        . "if it is not.", "E768",
          [{Id: "exe", L: "Program", Kind: "text", V: "notepad.exe"}],
          (V) => AxHelp.Fill("
          (`
if ProcessExist("{exe}")
    WinActivate("ahk_exe {exe}")
else
    Run("{exe}")
          )", Map("exe", AxHelp.Bare(V["exe"]))))

        ; ================================================ screen and mouse
        H("monitors", "Screen and mouse", "What monitors are there",
          "Count, work area and which is primary. The work area is the part not under "
        . "the taskbar, which is the number you actually want.", "E7F4",
          [], (V) => "g.Alert(MonitorSummary(), " Chr(34) "Monitors" Chr(34) ")",
          (V) => "
          (`
MonitorSummary() {
    out := ""
    loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        out .= "Monitor " A_Index ": " (r - l) "x" (b - t)
             . (A_Index = MonitorGetPrimary() ? "  (primary)" : "") "`n"
    }
    return RTrim(out, "`n")
}
          )")

        H("centre", "Screen and mouse", "Put the window where the mouse is",
          "Centres it on whichever monitor the pointer is on, which is nearly always the "
        . "one being looked at.", "E799",
          [], (V) => "CentreOnMouse(g)",
          (V) => "
          (`
CentreOnMouse(win) {
    MouseGetPos(&mx, &my)
    loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        if (mx >= l && mx < r && my >= t && my < b) {
            WinGetPos(, , &w, &h, "ahk_id " win.Hwnd)
            win.Move(l + (r - l - w) // 2, t + (b - t - h) // 2)
            return
        }
    }
}
          )")

        H("pixel", "Screen and mouse", "Read the colour under the mouse",
          "A colour picker in three lines, and it copies the hex. Handy for matching a "
        . "design to something already on screen.", "E790",
          [{Id: "hk", L: "Hotkey", Kind: "hotkey", V: "^!p"}],
          (V) => AxHelp.Fill('Hotkey("{hk}", (*) => PickPixel())', Map("hk", AxHelp.Esc(V["hk"]))),
          (V) => "
          (`
PickPixel() {
    global g
    CoordMode("Pixel", "Screen")
    CoordMode("Mouse", "Screen")
    MouseGetPos(&x, &y)
    hex := Format("#{:06X}", PixelGetColor(x, y) & 0xFFFFFF)
    A_Clipboard := hex
    g.Toast(hex " -- copied")
}
          )")

        ; ===================================================== listeners
        H("clipwatch", "Listeners", "Do something whenever the clipboard changes",
          "Fires on every copy, including your own -- guard it, or a script that writes "
        . "to the clipboard will set itself off.", "E8C8",
          [], (V) => "OnClipboardChange(ClipChanged)",
          (V) => "
          (`
ClipChanged(type) {
    global g
    if (type != 1)                                ; 1 = text, 2 = something else
        return
    g.Toast("copied: " SubStr(A_Clipboard, 1, 40))
}
          )")

        H("devices", "Listeners", "Hear a device being plugged in or pulled out",
          "WM_DEVICECHANGE. USB sticks, headsets, controllers -- anything Windows "
        . "notices, this notices.", "E772",
          [], (V) => "OnMessage(0x0219, DeviceChanged)          `; WM_DEVICECHANGE",
          (V) => "
          (`
DeviceChanged(wParam, lParam, msg, hwnd) {
    global g
    if (wParam = 0x8000)                          ; DBT_DEVICEARRIVAL
        g.Toast("something was plugged in")
    else if (wParam = 0x8004)                     ; DBT_DEVICEREMOVECOMPLETE
        g.Toast("something was unplugged")
}
          )")

        H("display", "Listeners", "Hear the screen layout change",
          "A monitor unplugged, a resolution changed, a laptop docked. Anything placed "
        . "by hand has to be put back after one of these.", "E7F4",
          [], (V) => "OnMessage(0x007E, DisplayChanged)         `; WM_DISPLAYCHANGE",
          (V) => "
          (`
DisplayChanged(wParam, lParam, msg, hwnd) {
    global g
    g.Toast("the screen layout changed")
}
          )")

        H("theme", "Listeners", "Follow Windows when it goes light or dark",
          "The window's own Theme can be set to Follow Windows, which does this for "
        . "you. This is for when you want to do something else as well.", "E793",
          [], (V) => "OnMessage(0x001A, SettingChanged)         `; WM_SETTINGCHANGE",
          (V) => "
          (`
SettingChanged(wParam, lParam, msg, hwnd) {
    global g
    try if (StrGet(lParam, "UTF-16") = "ImmersiveColorSet")
        g.SetTheme(WindowsWantsLight() ? "light" : "dark")
}
WindowsWantsLight() {
    try return RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes"
                     . "\Personalize", "AppsUseLightTheme", 1)
    return 1
}
          )")

        H("onexit", "Listeners", "Save something before the script closes",
          "Runs however it is closed -- the tray menu, Alt+F4, a reload.", "E74E",
          [], (V) => "OnExit(BeforeExit)",
          (V) => "
          (`
BeforeExit(reason, code) {
    ; save whatever needs saving here
    return 0                                      ; anything else cancels the exit
}
          )")

        H("onerror", "Listeners", "Catch every error the script does not",
          "Without this, one unhandled error puts AutoHotkey's own dialog in front of "
        . "whoever is using your program.", "EA39",
          [], (V) => "OnError(WhoopsHandler)",
          (V) => "
          (`
WhoopsHandler(err, mode) {
    global g
    try g.Alert(err.Message "`n`n" err.File " line " err.Line, "Something went wrong", "error")
    return true                                   ; true = it has been dealt with
}
          )")

        ; ================================================ time and timers
        H("timer", "Time and timers", "Do something over and over",
          "The plain repeating timer. Negative milliseconds would make it run once.", "E823",
          [{Id: "ms", L: "Every", Kind: "int", V: 1000, Min: 50, Max: 3600000, Suffix: "ms"}],
          (V) => "SetTimer(Tick, " AxHelp.Int(V["ms"], 1000) ")",
          (V) => "
          (`
Tick() {
    global g
    g.Status("msg", FormatTime(, "HH:mm:ss"))
}
          )")

        H("debounce", "Time and timers", "Wait until things settle, then act once",
          "Call it as often as you like; the work happens once, after the calls stop. "
        . "This is how a live search box stays quick.", "E916",
          [{Id: "ms", L: "Settle for", Kind: "int", V: 300, Min: 50, Max: 5000, Suffix: "ms"}],
          (V) => "`; call Settle() as often as you like -- DoTheWork runs once, "
               . AxHelp.Int(V["ms"], 300) "ms after the last call",
          (V) => AxHelp.Fill("
          (`
Settle() {
    static fn := DoTheWork
    SetTimer(fn, 0)                               ; cancel the one already waiting
    SetTimer(fn, -{ms})
}
DoTheWork() {
    global g
    g.Toast("done")
}
          )", Map("ms", AxHelp.Int(V["ms"], 300))))

        H("everyday", "Time and timers", "Do something at a particular time of day",
          "Checks once a minute and fires when the clock reaches it. Survives the "
        . "machine sleeping through the moment, which a one-shot timer does not.", "E787",
          [{Id: "at", L: "At", Kind: "text", V: "09:00", Hint: "24-hour clock."}],
          (V) => AxHelp.Fill('SetTimer(() => AtTimeOfDay("{at}"), 60000)',
              Map("at", AxHelp.Bare(V["at"]))),
          (V) => "
          (`
AtTimeOfDay(hhmm) {
    global g
    static done := ""
    now := FormatTime(, "HH:mm")
    today := FormatTime(, "yyyyMMdd")
    if (now != hhmm || done = today)
        return
    done := today
    g.Toast("it is " hhmm)
}
          )")

        ; =============================================== tray and alerts
        H("tray", "Tray and alerts", "A tray menu of your own",
          "Replaces AutoHotkey's. Keep an Exit on it, or there is no way out without "
        . "the task manager.", "E8B7",
          [{Id: "items", L: "Items", Kind: "code", Rows: 4, V: "Show`nSettings`n-`nExit",
            Hint: "One per line. A hyphen on its own is a separator."}],
          (V) => AxHelp.TrayCode(V["items"]))

        H("notify", "Tray and alerts", "A proper Windows notification",
          "The kind that stacks in the action centre, with buttons. Falls back to a tray "
        . "balloon when the script has no registered app name.", "E91C",
          [{Id: "title", L: "Title", Kind: "text", V: "Finished"},
           {Id: "text",  L: "Text",  Kind: "text", V: "The thing you asked for is done."}],
          (V) => AxHelp.Fill('g.Notify("{title}", "{text}", "info", '
                           . '{Buttons: ["Open", "Later"], OnClick: NotifyClicked})',
              Map("title", AxHelp.Esc(V["title"]), "text", AxHelp.Esc(V["text"]))),
          (V) => "
          (`
NotifyClicked(arg, label) {
    global g
    if (label = "Open") {
        g.Show()
        WinActivate("ahk_id " g.Hwnd)
    }
}
          )")

        ; ============================================== files and settings
        H("ini", "Files and settings", "Remember settings between runs",
          "An ini beside the script. Boring, readable, and it survives being hand-edited "
        . "-- which is more than can be said for most of the alternatives.", "E713",
          [{Id: "keys", L: "Settings", Kind: "code", Rows: 4,
            V: "theme = dark`nlastFile =`nzoom = 100",
            Hint: "One  name = default  per line. Each becomes a global."}],
          (V) => "LoadSettings()",
          (V) => AxHelp.IniCode(V["keys"]))

        H("watchdir", "Files and settings", "Notice when a folder changes",
          "Polls, rather than hooking: a change hook needs a message loop of its own and "
        . "this needs nothing.", "E8B7",
          [{Id: "dir", L: "Folder", Kind: "text", V: "%A_MyDocuments%",
            Hint: "A path, or one of AutoHotkey's own like A_ScriptDir."},
           {Id: "pat", L: "Matching", Kind: "text", V: "*.txt"},
           {Id: "ms",  L: "Check every", Kind: "int", V: 2000, Min: 250, Max: 60000, Suffix: "ms"}],
          ; one backslash: it is not an escape character, so "\\" would be two
          (V) => AxHelp.Fill('SetTimer(() => WatchFolder({dir} . "\{pat}"), {ms})',
              Map("dir", AxHelp.PathExpr(V["dir"]), "pat", AxHelp.Bare(V["pat"]),
                  "ms", AxHelp.Int(V["ms"], 2000))),
          (V) => "
          (`
WatchFolder(pattern) {
    global g
    static seen := ""
    now := ""
    loop files pattern
        now .= A_LoopFileName "|" A_LoopFileTimeModified "`n"
    if (seen = "") {                              ; first pass: just remember
        seen := now
        return
    }
    if (now != seen) {
        seen := now
        g.Toast("the folder changed")
    }
}
          )")

        H("drop", "Files and settings", "Let files be dropped on the window",
          "The window becomes a target for anything dragged out of Explorer.", "E7C3",
          [], (V) => "g.OnDrop(FilesDropped)",
          (V) => "
          (`
FilesDropped(files, id, info) {
    global g
    g.Toast(files.Length " file(s): " files[1])
}
          )")

        ; ============================================== the script itself
        H("single", "The script itself", "Only ever one copy running",
          "Starting it again replaces the copy already there, rather than leaving two "
        . "fighting over the same hotkeys.", "E8C8",
          [], (V) => "#SingleInstance Force")

        H("admin", "The script itself", "Restart itself with admin rights",
          "Needed to send keys to an elevated window, and for most of the registry. Ask "
        . "for it only when you need it -- everything running as admin is how accidents "
        . "happen.", "E7EF",
          [], (V) => "EnsureAdmin()",
          (V) => "
          (`
EnsureAdmin() {
    if A_IsAdmin
        return
    try {
        Run('*RunAs "' A_ScriptFullPath '" /restart')
        ExitApp()
    }
}
          )")

        H("startup", "The script itself", "Start with Windows",
          "A shortcut in the Startup folder. The registry would do it too, but this one "
        . "the person can see, and delete.", "E7E8",
          [{Id: "on", L: "Turn it on when the script starts", Kind: "flag", V: 1}],
          (V) => "RunAtLogin(" (V["on"] ? "true" : "false") ")",
          (V) => "
          (`
RunAtLogin(want) {
    link := A_Startup "\" StrReplace(A_ScriptName, ".ahk") ".lnk"
    if want {
        if !FileExist(link)
            FileCreateShortcut(A_IsCompiled ? A_ScriptFullPath : A_AhkPath, link, A_ScriptDir,
                               A_IsCompiled ? "" : '"' A_ScriptFullPath '"')
    } else if FileExist(link)
        FileDelete(link)
}
          )")

        H("args", "The script itself", "Read the command line",
          "Whatever came after the script's name, in order. A_Args is empty, not unset, "
        . "when there was nothing.", "E756",
          [], (V) => "
          (`
if A_Args.Length
    g.Toast("started with: " A_Args[1])
          )")

        H("reload", "The script itself", "Reload and edit hotkeys",
          "The two keys every script under development wants. Ctrl+Alt+R starts it again "
        . "from the file, Ctrl+Alt+E opens it.", "E777",
          [], (V) => "
          (`
Hotkey("^!r", (*) => Reload())
Hotkey("^!e", (*) => Edit())
          )")

        AxHelp._all := out
        return out
    }

    ; ------------------------------------------------------------ helpers
    ; {name} -> its answer. An unknown one is left exactly as it is, which is
    ; what keeps Send("{Enter}") and Format("{:06X}") intact.
    static Fill(tpl, vals) {
        for k, v in vals
            tpl := StrReplace(tpl, "{" k "}", String(v))
        return tpl
    }
    ; Wrap a hotkey or a hotstring in HotIf, so it only works where it should.
    static Scoped(here, line) {
        if !here
            return line
        return "HotIfWinActive(`"ahk_id `" g.Hwnd)`n" line "`nHotIfWinActive()"
    }
    ; Safe inside a double-quoted AutoHotkey string: the backtick is the escape
    ; character, and a quote is doubled.
    static Esc(t) => StrReplace(StrReplace(String(t), "``", "````"), Chr(34), Chr(34) Chr(34))
    ; For somewhere a quote cannot appear at all: a key name, a file mask.
    static Bare(t) => StrReplace(StrReplace(String(t), Chr(34)), "``")
    static Int(v, d) {
        v := RegExReplace(Trim(String(v)), "[^0-9\-]")
        return (v = "" || v = "-") ? d : Integer(v)
    }
    ; A path field may hold a built-in variable rather than a literal path.
    static PathExpr(t) {
        t := Trim(String(t))
        if RegExMatch(t, "^%(A_\w+)%$", &m)
            return m[1]
        return Chr(34) AxHelp.Esc(t) Chr(34)
    }
    static Lines(text) {
        out := []
        for raw in StrSplit(String(text), "`n", "`r")
            if (Trim(raw) != "")
                out.Push(Trim(raw))
        return out
    }
    static TrayCode(items) {
        q := Chr(34), nl := "`n"
        out := "A_TrayMenu.Delete()" nl
        for t in AxHelp.Lines(items) {
            if (t = "-") {
                out .= "A_TrayMenu.Add()" nl
                continue
            }
            if (t = "Exit")
                body := "(*) => ExitApp()"
            else if (t = "Show")
                body := "(*) => (g.Show(), WinActivate(" q "ahk_id " q " g.Hwnd))"
            else
                body := "(*) => g.Toast(" q AxHelp.Esc(t) q ")"
            out .= "A_TrayMenu.Add(" q AxHelp.Esc(t) q ", " body ")" nl
        }
        return RTrim(out, "`n")
    }
    ; One Load/Save pair for the settings named in the field, as globals.
    static IniCode(keys) {
        q := Chr(34), nl := "`n"
        names := [], defs := []
        for line in AxHelp.Lines(keys) {
            p := InStr(line, "=")
            n := AxProject.CleanName(p ? SubStr(line, 1, p - 1) : line)
            if (n = "")
                continue
            names.Push(n)
            defs.Push(p ? Trim(SubStr(line, p + 1)) : "")
        }
        if !names.Length
            names.Push("theme"), defs.Push("dark")
        list := ""
        for n in names
            list .= (list = "" ? "" : ", ") n
        out := "global " list nl nl
             . "SettingsFile() => A_ScriptDir " q "\settings.ini" q nl nl
             . "LoadSettings() {" nl "    global" nl
        for i, n in names
            out .= "    " n " := IniRead(SettingsFile(), " q "main" q ", " q n q ", "
                 . q AxHelp.Esc(defs[i]) q ")" nl
        out .= "}" nl nl "SaveSettings() {" nl "    global" nl
        for n in names
            out .= "    IniWrite(" n ", SettingsFile(), " q "main" q ", " q n q ")" nl
        return out "}"
    }

    ; ------------------------------------------------------------ the flow
    static Cats() {
        out := []
        for h in AxHelp.All() {
            found := false
            for c in out
                if (c = h.Cat)
                    found := true
            if !found
                out.Push(h.Cat)
        }
        return out
    }
    static Get(id) {
        for h in AxHelp.All()
            if (h.Id = id)
                return h
        return ""
    }
    ; Pick one, fill in what it needs, see exactly what it will write.
    static Pick(s, cat := "") {
        items := []
        for h in AxHelp.All()
            if (cat = "" || h.Cat = cat)
                items.Push({V: h.Id, L: h.Name, Desc: h.Cat " -- " h.Desc, Icon: h.Icon})
        id := AxForm.Choose(s, "Script helpers",
            "The plumbing a real script keeps needing. Pick one and it is written for "
          . "you, with somewhere obvious to change what it does.",
            items, {Icon: "E943", Width: 580, Ok: "Next", Scroll: true})
        if (id = "")
            return
        AxHelp.Configure(s, id)
    }
    static Configure(s, id) {
        h := AxHelp.Get(id)
        if !IsObject(h)
            return
        fields := []
        for f in h.Fields
            fields.Push(f)
        fields.Push({Id: "_d", Kind: "divider", L: ""})
        fields.Push({Id: "_p", Kind: "note", L: "The lines below go in the startup code, "
                   . "and any functions they need go with your own. Both are yours to "
                   . "edit afterwards."})
        r := AxForm.Show(s, {Title: h.Name, Icon: h.Icon, Width: 580, Intro: h.Desc,
            Fields: fields, Buttons: ["Add it", "Back", "Cancel"], CancelIndex: 3,
            Preview: (V) => AxHelp.Preview(h, V)})
        if (r.Btn = 2)
            return AxHelp.Pick(s)
        if !r.Ok
            return
        s.Mark()
        init := AxHelp.Part(h, "Init", r.V)
        fn := AxHelp.Part(h, "Fn", r.V)
        if (init != "")
            s.InsertInit(init)
        if (fn != "") {
            cur := RTrim(String(s.P.Script), "`r`n")
            s.P.Script := (Trim(cur) = "") ? fn : cur "`n`n" fn
        }
        s.EditScript(init != "" ? "init" : "script")
        s.Refresh()
        s.Status("msg", h.Name " added.")
    }
    static Part(h, which, V) {
        f := h.%which%
        if !f
            return ""
        try return Trim(f(V), " `t`r`n")
        return ""
    }
    static Preview(h, V) {
        init := AxHelp.Part(h, "Init", V)
        fn := AxHelp.Part(h, "Fn", V)
        if (init != "" && fn != "")
            return init "`n`n" fn
        return (init != "") ? init : fn
    }
    ; The default answers, for the check harness: every helper's output has to
    ; go through the interpreter's own parser before it can be offered.
    static Defaults(h) {
        m := Map()
        for f in h.Fields
            m[f.Id] := f.HasOwnProp("V") ? f.V : ""
        return m
    }
}
