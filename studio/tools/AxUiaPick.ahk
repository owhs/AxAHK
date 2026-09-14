#Requires AutoHotkey v2.0

; =============================================================================
;  AxUiaPick.ahk -- the element picker AxStudio opens from a macro.
;
;  Not included by the studio. It runs as a process of its own, started by
;  AxUiaUi.Pick (AxStudio.PkgUi.ahk) through a few lines written for the
;  purpose, which include lib\AxGui.ahk, the project's own copy of Descolada's
;  UIA library (Lib\Aris\Descolada\UIA.ahk) and this file, and then call
;
;      AxUiaPick.Run(outFile, theme)
;
;  Point at anything, in any program: the element under the pointer is
;  outlined and described. F8 keeps it. Then say how to find it again -- by
;  its automation id, its name, its type, its class -- and what the macro
;  does with it, and Send writes that to outFile as JSON and closes:
;
;      {"win": "ahk_exe notepad.exe", "title": "...", "cond": "{Name: \"Save\"}",
;       "act": "click", "text": "", "name": "...", "type": "button"}
;
;  The studio turns it into a macro step (uiclick, uitype, uiwait, uiread,
;  or an "if element" block). Esc or closing the window sends nothing.
;  This process only reads the other window, and clicks nothing itself.
; =============================================================================
class AxUiaPick {
    static Out := "", G := "", El := "", Hwnd := 0, Held := false, Key := ""
    static Info := Map()
    static Test := false            ; set by a test: off the screen, not activated, no hotkeys
    static TickFn := ObjBindMethod(AxUiaPick, "Tick")

    static Run(out, theme := "dark") {
        AxUiaPick.Out := out
        g := AxGui({Title: "Pick an element", Width: 500, Height: 620, MinWidth: 440, MinHeight: 520,
                    Theme: theme, Nav: false, AlwaysOnTop: true, MaximizeBox: false, MinimizeBox: false,
                    Icon: "E8B0", ExitOnClose: true, Headings: false, NoActivate: AxUiaPick.Test,
                    X: AxUiaPick.Test ? -3200 : "", Y: AxUiaPick.Test ? -3200 : ""})
        AxUiaPick.G := g
        g.AddInfoBar("vtip Info NoClose Title=`"Point at anything`"", "In any program. F8 keeps what is under the "
            . "pointer; Esc gives up.")
        for k in ["Window", "Type", "Name", "AutomationId", "ClassName", "Value"] {
            g.AddText("w110 Hint", k = "AutomationId" ? "Automation id" : k = "ClassName" ? "Class" : k)
            g.AddText("x+ w320 vinfo" k, "-")
            AxUiaPick.Info[k] := "info" k
        }
        g.AddText("vbyLbl", "Find it again by")
        AxUiaPick.ById := g.AddCheckBox("vbyId", "its automation id")
        AxUiaPick.ByName := g.AddCheckBox("vbyName x+16", "its name")
        AxUiaPick.ByType := g.AddCheckBox("vbyType x+16", "its type")
        AxUiaPick.ByClass := g.AddCheckBox("vbyClass x+16", "its class")
        g.AddText("vactLbl y+10", "Then the macro")
        AxUiaPick.Act := g.AddDDL("vact w300 Value=click", "click:clicks it|type:types into it|wait:waits for it (10 s)"
            . "|read:reads its text into a value|if:does the next steps only if it is there")
        AxUiaPick.Text := g.AddEdit("vtext w300 Placeholder=`"What to type, or the value to read into`"")
        AxUiaPick.Send := g.AddButton("vsend y+14 Accent Icon=E724", "Send to the macro")
        g.AddButton("vagain x+", "Pick again").OnEvent("Click", (*) => AxUiaPick.Again())
        g.AddButton("vcancel x+ Subtle", "Cancel").OnEvent("Click", (*) => ExitApp())
        AxUiaPick.Send.OnEvent("Click", (*) => AxUiaPick.Done())
        AxUiaPick.Send.Enabled := false
        g.AddStatusBar([{Id: "msg", Text: "Looking...", Icon: "E8B0", Grow: true}])
        g.Show()
        if AxUiaPick.Test
            return
        Hotkey("F8", (*) => AxUiaPick.Hold(), "On")
        Hotkey("Esc", (*) => ExitApp(), "On")
        OnExit((*) => AxUiaPick.Clear())
        SetTimer(AxUiaPick.TickFn, 150)
    }
    ; the element under the pointer, outlined, unless one is held
    static Tick() {
        if AxUiaPick.Held
            return
        MouseGetPos(&x, &y, &hwnd)
        if (hwnd = AxUiaPick.G.Hwnd)
            return
        el := ""
        try el := UIA.ElementFromPoint(x, y)
        if !IsObject(el)
            return
        key := AxUiaPick.Get(el, "Name") "|" AxUiaPick.Get(el, "LocalizedType") "|" AxUiaPick.RectKey(el)
        if (key = AxUiaPick.Key)
            return
        AxUiaPick.Key := key
        AxUiaPick.Clear()
        AxUiaPick.El := el, AxUiaPick.Hwnd := hwnd
        try el.Highlight(0, "Blue", 3)
        AxUiaPick.Show(el, hwnd)
    }
    static Get(el, prop) {
        try return String(el.%prop%)
        return ""
    }
    static RectKey(el) {
        try {
            r := el.BoundingRectangle
            return r.l "," r.t "," r.r "," r.b
        }
        return ""
    }
    static Show(el, hwnd) {
        exe := "", title := ""
        try exe := WinGetProcessName("ahk_id " hwnd)
        try title := WinGetTitle("ahk_id " hwnd)
        vals := Map("Window", (title != "" ? title "  --  " : "") exe,
                    "Type", AxUiaPick.Get(el, "LocalizedType") " (" AxUiaPick.Get(el, "Type") ")",
                    "Name", AxUiaPick.Get(el, "Name"), "AutomationId", AxUiaPick.Get(el, "AutomationId"),
                    "ClassName", AxUiaPick.Get(el, "ClassName"), "Value", SubStr(AxUiaPick.Get(el, "Value"), 1, 120))
        for k, id in AxUiaPick.Info
            try AxUiaPick.G.Text(id, vals[k] != "" ? vals[k] : "-")
    }
    ; F8: this one. The boxes start on the steadiest way to find it again:
    ; an automation id when it has one, otherwise its name and type.
    static Hold() {
        el := AxUiaPick.El
        if !IsObject(el)
            return
        AxUiaPick.Held := true
        id := AxUiaPick.Get(el, "AutomationId"), nm := AxUiaPick.Get(el, "Name")
        AxUiaPick.ById.Value := id != "" ? 1 : 0
        AxUiaPick.ByName.Value := (id = "" && nm != "") ? 1 : 0
        AxUiaPick.ByType.Value := (id = "") ? 1 : 0
        AxUiaPick.ByClass.Value := 0
        AxUiaPick.Send.Enabled := true
        AxUiaPick.G.Status("msg", "Kept. Choose how to find it and what to do, then Send.")
        if !AxUiaPick.Test
            try WinActivate("ahk_id " AxUiaPick.G.Hwnd)
    }
    static Again() {
        AxUiaPick.Held := false, AxUiaPick.Key := ""
        AxUiaPick.Send.Enabled := false
        AxUiaPick.G.Status("msg", "Looking...")
    }
    static Clear() {
        try AxUiaPick.El.Highlight("clear")
    }
    ; the conditions as UIA-v2 takes them, written as AutoHotkey
    static Cond() {
        el := AxUiaPick.El, parts := []
        Q := (v) => '"' StrReplace(StrReplace(v, "``", "````"), '"', '``"') '"'
        if AxUiaPick.ById.Value && (v := AxUiaPick.Get(el, "AutomationId")) != ""
            parts.Push("AutomationId: " Q(v))
        if AxUiaPick.ByName.Value && (v := AxUiaPick.Get(el, "Name")) != ""
            parts.Push("Name: " Q(v))
        if AxUiaPick.ByType.Value && (v := AxUiaPick.Get(el, "Type")) != ""
            parts.Push("Type: " v)
        if AxUiaPick.ByClass.Value && (v := AxUiaPick.Get(el, "ClassName")) != ""
            parts.Push("ClassName: " Q(v))
        s := ""
        for p in parts
            s .= (s = "" ? "" : ", ") p
        return (s = "") ? "" : "{" s "}"
    }
    static Done() {
        el := AxUiaPick.El
        cond := AxUiaPick.Cond()
        if (cond = "")
            return AxUiaPick.G.Status("msg", "Tick at least one way to find it again.")
        exe := ""
        try exe := WinGetProcessName("ahk_id " AxUiaPick.Hwnd)
        title := ""
        try title := WinGetTitle("ahk_id " AxUiaPick.Hwnd)
        r := Map("win", exe != "" ? "ahk_exe " exe : "ahk_id " AxUiaPick.Hwnd, "title", title, "cond", cond,
                 "act", AxUiaPick.Act.Value, "text", AxUiaPick.Text.Text,
                 "name", AxUiaPick.Get(el, "Name"), "type", AxUiaPick.Get(el, "LocalizedType"))
        try FileDelete(AxUiaPick.Out)
        FileAppend(AxUiaPick.Json(r), AxUiaPick.Out, "UTF-8")
        if !AxUiaPick.Test
            ExitApp()
    }
    static Json(m) {
        s := ""
        for k, v in m
            s .= (s = "" ? "" : ", ") '"' k '": "' StrReplace(StrReplace(StrReplace(StrReplace(v, "\", "\\"), '"', '\"'), "`n", "\n"), "`r", "") '"'
        return "{" s "}"
    }
}
