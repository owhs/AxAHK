#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes, icons and the component's styles
#Include ..\lib\AxGui.ahk
#Include ..\lib\AxAssets.ahk

; =============================================================================
;  Ribbon.ahk — a small editor, driven entirely from its ribbon.
;
;  There is no side bar and no page of demonstration buttons: the ribbon is
;  the window's command surface, the way it is in the applications the ribbon
;  came from. Everything the app can do is on it, including changing the
;  ribbon's own shape.
;
;  One set of tabs describes all four shapes, and SetMode swaps between them
;  while the window is open:
;
;    office     tabs over grouped panels, each group titled, with a launcher
;    simple     tabs over one compact line
;    strip      no tabs: one persistent line of grouped commands
;    titlebar   the tabs live in the window's own title bar
;
;  What to try
;    · Double-click a tab to roll the ribbon up; click a tab while it is up
;      and the panel floats over the document until you click away.
;    · Press Alt for the key tips, then the letter. Escape puts them away.
;    · Put the caret in the document and press Insert ▸ Picture: a contextual
;      tab appears, coloured and banded, and goes when you deselect.
;    · Make the window narrow. Groups fold, right to left, into the ⋯ at the
;      end of the panel, and come back when there is room.
;    · View ▸ Style and View ▸ Density redress the ribbon four ways and three:
;      fluent, classic, flat, outlined × compact, comfortable, roomy.
;    · View ▸ Look changes the stylesheet and theme under it, all twelve.
; =============================================================================

g := AxGui({
    Title:     "Untitled — AxAHK Ribbon",
    AppName:   "AxAHK Ribbon",
    Width:     1100,
    Height:    720,
    MinWidth:  420,
    MinHeight: 380,
    BackColor: "202020",
    Theme:     "dark",
    Nav:       false                 ; a ribbon app has no side bar
})

Doc := ""
Dirty := false
LogText := ""

; ─────────────────────────────────────────────────────────────────────────────
;  The commands. One description, four shapes.
; ─────────────────────────────────────────────────────────────────────────────

Palette := ["#e74c3c", "#e67e22", "#f1c40f", "#2ecc71", "#3498db", "#9b59b6", "#ffffff"]

Sheets := []
for s in [["win11", "11"], ["win365", "365"], ["winxp", "XP"], ["win98", "98"],
          ["cozy", "Coz"], ["cyber", "Cyb"], ["brutalist", "Bru"], ["aurora", "Aur"],
          ["inset", "Ins"], ["precision", "Pre"], ["instrument", "Instr"], ["rpg", "RPG"]]
    Sheets.Push({Id: s[1], Label: s[2]})

Tabs := [
  {Id: "home", Title: "Home", Key: "H", Groups: [
     {Id: "clip", Title: "Clipboard", Launcher: true, Items: [
        {Id: "paste", Label: "Paste", Icon: "E77F", Size: "large", Kind: "split", Key: "V",
         Menu: [["Keep formatting", (*) => Paste(false)],
                ["Text only",       (*) => Paste(true)]]},
        {Id: "cut",   Label: "Cut",   Icon: "E8C6", Key: "X"},
        {Id: "copy",  Label: "Copy",  Icon: "E8C8", Key: "C"},
        {Id: "fmt",   Label: "Format painter", Icon: "E790", Key: "F"}]},

     {Id: "font", Title: "Font", Launcher: true, Items: [
        {Id: "face", Kind: "input", Value: "Consolas", Width: 122, Tip: "Typeface"},
        {Id: "size", Kind: "input", Value: "13", Width: 38, Tip: "Size in points"},
        {Kind: "sep"},
        {Id: "bold",   Label: "Bold",      Icon: "E8DD", Kind: "toggle", Key: "1", Tip: "Bold"},
        {Id: "italic", Label: "Italic",    Icon: "E8DB", Kind: "toggle", Key: "2"},
        {Id: "under",  Label: "Underline", Icon: "E8DC", Kind: "toggle", Key: "3"},
        {Kind: "sep"},
        {Id: "colour", Label: "Colour", Icon: "E790", Kind: "color", Value: "#dcdcdc",
         Items: Palette, Key: "K", Tip: "Text colour"}]},

     {Id: "para", Title: "Paragraph", Items: [
        {Id: "bullets", Label: "Bullets", Icon: "E8FD", Kind: "menu", Key: "U",
         Menu: [["Dots",   (*) => Bullet(Chr(0x2022))],
                ["Dashes", (*) => Bullet(Chr(0x2013))],
                ["Arrows", (*) => Bullet(Chr(0x2192))]]},
        {Id: "stamp",  Label: "Timestamp", Icon: "E787", Key: "T"},
        {Id: "rule",   Label: "Divider",   Icon: "E739"},
        {Kind: "sep"},
        {Id: "upper",  Label: "UPPER",     Icon: "E8D2", Key: "G"},
        {Id: "lower",  Label: "lower",     Icon: "E8D2"},
        {Id: "trim",   Label: "Trim ends", Icon: "E8C8"}]},

     {Id: "editing", Title: "Editing", Items: [
        {Id: "find",    Label: "Find",       Icon: "E721", Size: "large", Key: "F"},
        {Id: "wrap",    Label: "Word wrap",  Kind: "check", Checked: true, Key: "W"},
        {Id: "selall",  Label: "Select all", Icon: "E8B3"},
        {Id: "clear",   Label: "Clear",      Icon: "E894"}]}]},

  {Id: "insert", Title: "Insert", Key: "N", Groups: [
     {Id: "media", Title: "Illustrations", Items: [
        {Id: "picture", Label: "Picture", Icon: "EB9F", Size: "large", Key: "P",
         Tip: "Puts a placeholder in, and brings up the picture tools"}]},
     {Id: "tables", Title: "Tables", Items: [
        {Id: "table", Label: "Table", Icon: "E80A", Size: "large", Kind: "menu",
         Menu: [["2 columns", (*) => Table(2)], ["3 columns", (*) => Table(3)],
                ["4 columns", (*) => Table(4)]]}]},
     {Id: "links", Title: "Links & symbols", Items: [
        {Id: "link",   Label: "Link",   Icon: "E71B"},
        {Id: "bullet", Label: "Symbol", Icon: "E8AB", Kind: "menu",
         Menu: [["Arrow",  (*) => Put(Chr(0x2192))], ["Degree", (*) => Put(Chr(0x00B0))],
                ["Em dash", (*) => Put(Chr(0x2014))]]},
        {Id: "path",   Label: "This file's path", Icon: "E8E5"}]}]},

  {Id: "view", Title: "View", Key: "W", Groups: [
     {Id: "shape", Title: "Shape", Launcher: true, Items: [
        {Id: "m_office",   Label: "Office",   Icon: "E7C4", Size: "large", Key: "O"},
        {Id: "m_simple",   Label: "Simplified", Icon: "E8A9"},
        {Id: "m_strip",    Label: "Strip",    Icon: "E700"},
        {Id: "m_titlebar", Label: "In the title bar", Icon: "E737"}]},
     {Id: "dress", Title: "Style", Items: [
        {Id: "s_fluent",   Label: "Fluent",   Icon: "E790", Key: "1"},
        {Id: "s_classic",  Label: "Classic",  Icon: "E7C4", Key: "2"},
        {Id: "s_flat",     Label: "Flat",     Icon: "E739", Key: "3"},
        {Kind: "sep"},
        {Id: "s_outlined", Label: "Outlined", Icon: "E80A", Key: "4"}]},
     {Id: "dens", Title: "Density", Items: [
        {Id: "d_compact",     Label: "Compact",     Icon: "E73F"},
        {Id: "d_comfortable", Label: "Comfortable", Icon: "E73E"},
        {Id: "d_roomy",       Label: "Roomy",       Icon: "E740"}]},
     {Id: "panes", Title: "Show", Items: [
        {Id: "showlog", Label: "Event log", Kind: "check", Key: "E"},
        {Id: "keytips", Label: "Key tips",  Icon: "E765"},
        {Id: "rollup",  Label: "Roll the ribbon up", Icon: "E70E"}]},
     {Id: "look", Title: "Look", Launcher: true, Items: [
        {Id: "sheet", Kind: "gallery", Items: Sheets}]},
     {Id: "colours", Title: "Theme", Items: [
        {Id: "dark",  Label: "Dark",  Icon: "E708"},
        {Id: "light", Label: "Light", Icon: "E706"},
        {Id: "system", Label: "Follow Windows", Icon: "E713"},
        {Kind: "sep"},
        {Id: "acc", Label: "Accent", Icon: "E790", Kind: "color", Value: "#60cdff",
         Items: Palette, Size: "large"}]}]},

  ; declared with the rest, shown only when a picture is selected
  {Id: "pictools", Title: "Format", Key: "J", Contextual: true, Set: "Picture tools",
   Colour: "#c27bdb", Hidden: true, Groups: [
     {Id: "adjust", Title: "Adjust", Items: [
        {Id: "crop",   Label: "Crop",   Icon: "E7A8", Size: "large"},
        {Id: "rotate", Label: "Rotate", Icon: "E7AD"},
        {Id: "remove", Label: "Remove background", Icon: "E894"}]},
     {Id: "picstyles", Title: "Picture styles", Items: [
        {Id: "border", Label: "Border", Icon: "E91B", Kind: "color", Value: "#c27bdb",
         Items: Palette},
        {Id: "effects", Label: "Effects", Icon: "E790", Kind: "menu",
         Menu: [["Shadow", (*) => LogLine("Shadow")], ["Glow", (*) => LogLine("Glow")]]},
        {Id: "deselect", Label: "Deselect", Icon: "E711"}]}]}]


; ─────────────────────────────────────────────────────────────────────────────
;  The window: a ribbon, a document, a status bar. Nothing else.
; ─────────────────────────────────────────────────────────────────────────────

g.AddRibbon("vrib Fill", {
    Mode: "office",
    File: {Label: "File", Color: "#60cdff"},
    QuickAccess: ["save", "undo", "find"],
    Tabs: Tabs,
    OnCommand:  (id, it, r) => Command(id, it, r),
    OnToggle:   (id, on, r) => Toggled(id, on),
    OnTab:      (id, r) => LogLine("Tab: " id),
    OnLauncher: (id, r) => LogLine("Launcher: " id),
    OnCollapse: (on, r) => LogLine(on ? "Ribbon rolled up" : "Ribbon rolled down"),
    OnInput:    (id, v, r) => LogLine(id " = " v)})

; the ribbon object only exists once the window is up, so ask for it then
R() => g.Ctl("rib").Component

Doc := g.AddEdit("vdoc Fill Multi Rows=22 Style=font-family:Consolas,monospace;font-size:13px",
    "A small editor whose only command surface is the ribbon above it.`n`n"
    . "Put the caret somewhere and try Home " Chr(0x25B8) " Timestamp, or Insert " Chr(0x25B8)
    . " Symbol, or Home " Chr(0x25B8) " UPPER on a selection.`n`n"
    . "Insert " Chr(0x25B8) " Picture brings up a contextual tab. View " Chr(0x25B8)
    . " The ribbon changes the ribbon's own shape, and View " Chr(0x25B8)
    . " Look changes the stylesheet under all of it.`n")
Doc.OnEvent("Change", (*) => MarkDirty())

logBox := g.AddEdit("vlog Fill Multi Rows=7 ReadOnly Hidden "
    . "Style=font-family:Consolas,monospace;font-size:11px", "")

g.AddStatusBar([{Id: "msg",  Text: "Ready", Icon: "E7C4", Grow: true},
                {Id: "mode", Text: "Office", Width: 120},
                {Id: "chars", Text: "", Width: 110}])

g.OnReady((w) => Started())
g.Show()

Started() {
    global logBox, LogText
    try logBox.Value := LogText
    LogLine("Ready.")
    Count()
}


; ─────────────────────────────────────────────────────────────────────────────
;  What the commands do
; ─────────────────────────────────────────────────────────────────────────────

Command(id, it, r) {
    switch id {
    ; --- the ribbon's own shape
    case "m_office", "m_simple", "m_strip", "m_titlebar":
        m := SubStr(id, 3)
        r.SetMode(m)
        g.Status("mode", Title(m))
        LogLine("Mode: " m)
        return
    case "s_fluent", "s_classic", "s_flat", "s_outlined":
        st := SubStr(id, 3)
        r.SetStyle(st)
        g.Status("msg", "Style: " Title(st))
        LogLine("Style: " st)
        return
    case "d_compact", "d_comfortable", "d_roomy":
        d := SubStr(id, 3)
        r.SetDensity(d)
        g.Status("msg", "Density: " Title(d))
        LogLine("Density: " d)
        return
    case "rollup":  return r.ToggleCollapse()
    case "keytips": return r.ToggleKeyTips()

    ; --- look
    case "dark", "light", "system":
        g.SetTheme(id)
        LogLine("Theme: " id)
        return
    case "sheet":
        if (IsObject(it) && it.Value != "") {
            g.SetStylesheet(it.Value)
            LogLine("Stylesheet: " it.Value)
        }
        return
    case "acc":
        if (IsObject(it) && it.Value != "") {
            g.SetAccent(it.Value)
            LogLine("Accent: " it.Value)
        }
        return

    ; --- editing
    case "stamp":   return Put(FormatTime(, "yyyy-MM-dd HH:mm") "  ")
    case "rule":    return Put("`n" StrReplace(Format("{:60}", ""), " ", Chr(0x2500)) "`n")
    case "upper":   return Transform("upper")
    case "lower":   return Transform("lower")
    case "trim":    return Transform("trim")
    case "selall":  return (g.Focus("doc"), LogLine("Select all"))
    case "clear":   return (Doc.Value := "", MarkDirty(), Count(), LogLine("Cleared"))
    case "path":    return Put(A_ScriptFullPath)
    case "link":    return Put("https://github.com/")
    case "copy":    return (A_Clipboard := Doc.Value, LogLine("Copied the document"))
    case "cut":     return (A_Clipboard := Doc.Value, Doc.Value := "", MarkDirty(), Count(), LogLine("Cut"))
    case "paste":   return Paste(false)
    case "find":    return Find()
    case "save":    return Save()

    ; --- the contextual tab
    case "picture":
        Put("[ picture ]")
        r.ShowContext("pictools", true)
        g.Status("msg", "A picture is selected — the Format tab applies to it")
        LogLine("Picture inserted; contextual tab shown")
        return
    case "deselect":
        r.ShowContext("pictools", false)
        g.Status("msg", "Ready")
        LogLine("Deselected")
        return
    case "file":
        g.Alert("A real app would open its backstage here: New, Open, Save as, Print.", "File")
        return
    }
    LogLine("Command: " id (IsObject(it) && it.Value != "" ? "  (" it.Value ")" : ""))
}

Toggled(id, on) {
    switch id {
    case "showlog":
        try g.Ctl("log").Visible := on
        LogLine("Event log " (on ? "shown" : "hidden"))
        return
    case "wrap":
        LogLine("Word wrap " (on ? "on" : "off"))
        return
    }
    LogLine("Toggle " id ": " (on ? "on" : "off"))
}

Put(text) {
    Doc.Value := Doc.Value text
    MarkDirty()
    Count()
    g.Focus("doc")
}
Bullet(ch) {
    Put("`n" ch " ")
}
Table(cols) {
    line := ""
    loop cols
        line .= (line = "" ? "" : " | ") Format("{:10}", "col " A_Index)
    Put("`n" line "`n" StrReplace(Format("{:" (cols * 13) "}", ""), " ", Chr(0x2500)) "`n")
}
Paste(textOnly) {
    t := ""
    try t := A_Clipboard
    if (t = "")
        return LogLine("Nothing on the clipboard")
    Put(textOnly ? RegExReplace(t, "\s+", " ") : t)
    LogLine("Pasted" (textOnly ? " as text" : ""))
}
Transform(how) {
    v := Doc.Value
    Doc.Value := (how = "upper") ? StrUpper(v) : (how = "lower") ? StrLower(v) : Trim(v)
    MarkDirty()
    Count()
    LogLine(how)
}
Find() {
    r := g.Prompt("What are you looking for?", "Find")
    if (r.Button != "OK" || r.Value = "")
        return
    n := 0, at := 0
    while (at := InStr(Doc.Value, r.Value, false, at + 1))
        n++
    g.Status("msg", n " match" (n = 1 ? "" : "es") " for " Chr(0x201C) r.Value Chr(0x201D))
    LogLine("Find " Chr(0x201C) r.Value Chr(0x201D) ": " n)
}
Save() {
    global Dirty
    Dirty := false
    g.SetTitle("Untitled — AxAHK Ribbon")
    g.Status("msg", "Saved")
    g.Toast("Saved")
    LogLine("Saved")
}
MarkDirty() {
    global Dirty
    if !Dirty {
        Dirty := true
        g.SetTitle("Untitled* — AxAHK Ribbon")
    }
    Count()
}
Count() {
    try g.Status("chars", StrLen(Doc.Value) " characters")
}
LogLine(msg) {
    global logBox, LogText
    LogText := FormatTime(, "HH:mm:ss") "  " msg "`n" LogText
    if IsSet(logBox) && IsObject(logBox)
        try logBox.Value := LogText
}
Title(s) => StrUpper(SubStr(s, 1, 1)) SubStr(s, 2)

; Alt is the app's to bind: a component must not take the page's one wildcard
; keydown hook out from under whatever else wants it.
g.On("keydown", "*", (el, ev) => AltKey(ev))
AltKey(ev) {
    try {
        if (ev.keyCode = 18) {
            R().ToggleKeyTips()
            ev.returnValue := false
        }
    }
}
