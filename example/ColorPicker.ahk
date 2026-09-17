#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes/icons + rich component CSS
#Include ..\lib\AxRichAll.ahk
#Include ..\lib\AxAssets.ahk

; ==============================================================================
;  ColorPicker.ahk — the rich colour picker at every level it offers.
;
;  Rich components (lib\rich) are plugins: each lives in its own folder, ships
;  its own stylesheet, and installs itself when you include it. Nothing in the
;  core knows they exist, and a window that never uses one carries none of
;  their CSS. Include AxRichAll.ahk for the lot, or one component on its own.
; ==============================================================================

g := AxGui({
    Title:    "Rich components — colour picker",
    Width:    880,
    Height:   660,
    MinWidth: 640,
    MinHeight: 480,
    BackColor: "202020",
    Theme:     "dark"
})

Accent := "#60cdff"

EventLogger(msg) {
    if !g.Ready
        return
    g.Append("logBox", "<div>[" FormatTime(, "HH:mm:ss") "] " AxWindow._Esc(msg) "</div>")
    logBox.El.scrollTop := logBox.El.scrollHeight
}

; ==============================================================================
; The swatch button — the short way in
; ==============================================================================

g.AddPage("buttons", "Colour buttons", "E790")

g.AddInfoBar('Title="One click from a swatch to a colour."',
    "AddColorButton draws a live preview, opens the picker with its own colour as Current, "
    . "writes the result back into itself and fires OnChange. That is the whole workflow.")

g.AddRow("Icon=E790", "Window accent", "The picker result is applied the moment it is chosen")
g.AddColorButton("vcbAccent", "#60cdff")
    .OnChange((c, v, *) => (g.SetAccent(v), EventLogger("Accent -> " v)))
g.Use()

g.AddRow("Icon=E7E7", "Surface tint", "Same control, different job")
g.AddColorButton("vcbTint", "#4c4a48")
    .OnChange((c, v, *) => (g.SetTint(v = "#4C4A48" ? "" : v, 0.14), EventLogger("Tint -> " v)))
g.Use()

g.AddRow("Icon=E771", "Chip only", "NoHex hides the label when the swatch says enough")
g.AddColorButton("vcbPlain NoHex", "#e3008c")
    .OnChange((c, v, *) => EventLogger("Plain button -> " v))
g.AddColorButton("x+8 vcbPlain2 NoHex", "#10893e")
    .OnChange((c, v, *) => EventLogger("Plain button 2 -> " v))
g.AddColorButton("x+8 vcbPlain3 NoHex", "#f7630c")
    .OnChange((c, v, *) => EventLogger("Plain button 3 -> " v))
g.Use()

g.AddText("Caption", "The same value is readable as a control value, so OnValue and Value work")
g.AddButton("", "Read every button")
    .OnClick((*) => EventLogger("Buttons: " g.Value("cbAccent") " / " g.Value("cbTint") " / " g.Value("cbPlain")))
g.AddButton("x+8", "Set the accent button to red")
    .OnClick((*) => g.Value("cbAccent", "#e74856"))


; ==============================================================================
; The standalone dialog
; ==============================================================================

g.AddPage("dialog", "Standalone dialog", "E8A9")

g.AddInfoBar('Title="A window of its own."',
    "AxRichDialog gives a rich component dialog manners: no minimise or maximise box, a fixed "
    . "size, Escape closes, closing it never exits the script, and it is modal to its owner.")

g.AddRow("Icon=E8EF", "With a Current colour", "The top splits into Current and New")
g.AddButton("Accent", "Pick…")
    .OnClick((*) => ShowDual())
g.Use()

g.AddRow("Icon=E790", "Without one", "The New panel spans the whole width instead")
g.AddButton("", "Pick…")
    .OnClick((*) => ShowSolo())
g.Use()

g.AddRow("Icon=E713", "Trimmed down", "Fields, swatches and the heading are all optional")
g.AddButton("", "Minimal")
    .OnClick((*) => EventLogger("Minimal -> " (AxColorPicker.Show({Owner: g, Value: Accent, Size: 240,
        Fields: false, Swatches: false, Heading: "", Title: "Colour", Height: 420}) || "(cancelled)")))
g.Use()

g.AddRow("Icon=E81C", "Recently chosen", "Every accepted colour joins the Recent row")
g.AddButton("", "Pick, twice")
    .OnClick((*) => (AxColorPicker.Show({Owner: g, Current: Accent}),
        EventLogger("Recent: " Join(AxColorPicker.Recent))))
g.AddButton("x+8", "Without the row")
    .OnClick((*) => AxColorPicker.Show({Owner: g, Current: Accent, Recent: false}))
g.Use()

g.AddRow("Icon=E946", "Live while you choose", "OnChange fires on every drag, not just on OK")
g.AddButton("", "Live preview")
    .OnClick((*) => LivePreview())
g.Use()

g.AddText("Caption", "Title-bar icon — the same Icon option every AxWindow takes")
for spec in [["E790", "Fluent glyph (default)"], ["auto", "This process's icon"],
             ["shell32.dll,13", "Extracted from shell32"], ["imageres.dll,-109", "By resource id"],
             ["assets\logo.png", "An image file"], ["", "No icon at all"]]
    g.AddButton((A_Index = 1 ? "" : "x+8"), spec[2])
        .OnClick(IconDemo(spec[1]))

IconDemo(icon) => (*) => AxColorPicker.Show({Owner: g, Current: Accent, Icon: icon,
    Title: "Pick a colour" (icon != "" ? "" : "  (no icon)")})

ShowDual() {
    got := AxColorPicker.Show({Owner: g, Current: Accent, Value: Accent})
    if (got = "") {
        EventLogger("Dialog cancelled")
        return
    }
    global Accent := got
    g.SetAccent(got), g.Value("cbAccent", got)
    EventLogger("Dialog -> " got)
}

ShowSolo() {
    got := g.PickColor({Value: "#8764b8", Title: "Choose a colour", Heading: "Choose a colour"})
    EventLogger("Solo dialog -> " (got = "" ? "(cancelled)" : got))
}

LivePreview() {
    before := g.Accent
    got := AxColorPicker.Show({Owner: g, Current: before, Value: before,
        OnChange: (hex, cp) => g.SetAccent(hex)})
    g.SetAccent(got != "" ? got : before)
    EventLogger("Live preview -> " (got = "" ? "(reverted)" : got))
}


; ==============================================================================
; Inline on a page
; ==============================================================================

g.AddPage("inline", "Inline", "E8FD")

g.AddInfoBar('Title="The same component, no window of its own."',
    "AddColorPicker drops the whole thing onto a page. Everything scales from Size, so it fits "
    . "wherever you put it.")

g.AddCard()
g.AddColorPicker("vcpInline Size=260 Swatches Recent", "#0078ff")
g.Use()
inlineOut := g.AddText("vinlineOut Caption", "#0078FF")
g.AddText("Hint", "The Recent row is shared by every picker in the process (AxColorPicker.Recent), "
    . "so colours chosen in the dialogs above turn up here.")
g.AddButton("", "Refresh recent")
    .OnClick((*) => g.Ctl("cpInline").Component.RefreshRecent())
g.AddButton("x+8", "Forget recent")
    .OnClick((*) => (AxColorPicker.Recent := [], g.Ctl("cpInline").Component.RefreshRecent(),
        EventLogger("Recent colours cleared")))


; ==============================================================================
; Screen eyedropper
; ==============================================================================

g.AddPage("screen", "Screen picker", "EF3C")

g.AddInfoBar('Title="Pick from anywhere on screen."',
    "A magnifier follows the cursor: the wheel changes zoom, left click takes the colour, right "
    . "click or Escape cancels. It is a rich component of its own, so it works without the picker.")

g.AddRow("Icon=EF3C", "Grab a colour", "AxScreenPick.Color() — or g.PickScreenColor()")
g.AddButton("Accent", "Eyedropper")
    .OnClick((*) => GrabColor())
g.Use()

g.AddRow("Icon=E71E", "Start zoomed in", "Zoom, magnifier size and the pixel grid are all options")
g.AddButton("", "24x, no grid")
    .OnClick((*) => EventLogger("Screen -> " (g.PickScreenColor({Zoom: 24, Grid: false, Size: 200}) || "(cancelled)")))
g.Use()

g.AddText("Caption", "Inside the picker the same thing is one click away: the pipette on the New "
    . "panel, and the Current panel itself.")
g.AddText("Hint", "Clicking Current runs the eyedropper by default; CurrentAction: `"revert`" makes "
    . "it go back to the old colour instead, and `"none`" makes it inert.")

GrabColor() {
    got := AxScreenPick.Color({Owner: g})
    if (got = "") {
        EventLogger("Eyedropper cancelled")
        return
    }
    g.Value("cbPlain", got)
    EventLogger("Eyedropper -> " got " (copied into the third colour button)")
}


; ==============================================================================
; Console
; ==============================================================================

g.AddPage("console", "Console", "E756")
logBox := g.AddConsole("vlogBox")
g.AddButton("", "Clear")
    .OnClick((*) => logBox.Text := "")


; ==============================================================================
; Run
; ==============================================================================

g.OnReady((app) => (
    app.Ctl("cpInline").Component.OnChange((hex, cp) => (inlineOut.Text := hex,
        app.Style("inlineOut", "color", hex))),
    EventLogger("Ready. Rich components loaded: " Join(AxRich.Names()))
))

Join(arr, sep := ", ") {
    s := ""
    for v in arr
        s .= (s = "" ? "" : sep) v
    return s
}

g.Show()
