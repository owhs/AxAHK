#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes/icons + rich component CSS
#Include ..\lib\AxRichAll.ahk
#Include ..\lib\AxAssets.ahk

; ==============================================================================
;  Actions.ahk — header actions: the little buttons at the end of a header.
;
;  Windows keeps a section's own commands in one spot: the trailing end of its
;  header. About's "Copy", a card's "..." menu, a split "Export" button, the
;  copy button on a code block. The spot and the look are the library's;
;  what each button does is yours:
;
;      g.Actions("specs", [{Glyph: "E8C8", Text: "Copy", Copy: SpecsText}])
;
;  Items take the title bar's fields (Glyph, Text, Tip, Click, Menu, Popover,
;  Toggle) plus Copy. Click + Menu together make a split button.
; ==============================================================================

g := AxGui({
    Title:     "Header actions",
    Width:     820,
    Height:    720,
    MinWidth:  520,
    MinHeight: 420,
    BackColor: "202020",
    Theme:     "dark"
})

Say(msg) => g.Toast(msg)

SPECS := [["Device name", A_ComputerName], ["User", A_UserName],
          ["Windows", A_OSVersion], ["AutoHotkey", A_AhkVersion],
          ["Screen", A_ScreenWidth " x " A_ScreenHeight " @ " A_ScreenDPI " dpi"]]
SpecsText() {
    out := ""
    for s in SPECS
        out .= s[1] ": " s[2] "`n"
    return RTrim(out, "`n")
}

g.AddPage("main", "Header actions", "E8B3")

g.AddInfoBar('Title="One strip, many jobs."',
    "Every box below has the same thing at the end of its header -- the place Windows puts a section's commands. "
    . "Only the buttons differ.")

; ---- 1. the About page: Copy on an expander --------------------------------
; A box hands back its container, so the strip can be chained on as it is made
specsBox := g.AddExpander("vspecs Icon=E7F4 Open", "Device specifications", "Copy puts the lot on the clipboard")
    .Actions([
        {Glyph: "E8C8", Text: "Copy", Copy: SpecsText},
        {Glyph: "E712", Tip: "More", Menu: () => [
            {Label: "Copy as one line", Icon: "E8C8", Click: (*) => (A_Clipboard := StrReplace(SpecsText(), "`n", " | "), Say("Copied as one line"))},
            "-",
            {Label: "Rename this PC...", Icon: "E70F", Click: (*) => Say("Rename...")}]}
    ])
for spec in SPECS {
    g.AddRow("", spec[1])
    g.AddText("", spec[2])
    specsBox.Use()                                       ; back into the expander, not the page
}
g.Use()

; ---- 2. a card: refresh, pin (toggle), info (popover), more (menu) ---------
g.AddCard("vstorage", "Storage")
g.AddText("", "C:  412 GB free of 953 GB")
g.AddProgress("", 57)
g.Use()
g.Actions("storage", [
    {Id: "stRefresh", Glyph: "E72C", Tip: "Refresh", Click: (*) => Say("Refreshed")},
    {Id: "stPin", Glyph: "E718", Tip: "Pin", Toggle: true,
        Click: (id, w) => Say(w.Action(id).On ? "Pinned" : "Unpinned")},
    {Glyph: "E946", Tip: "What counts", Popover: {Width: 240, Html:
        "<b>What counts as used</b><div style='margin-top:6px;opacity:.8'>Apps, system files, temporary files and "
        . "everything in your user folder. Recycle Bin is counted until it is emptied.</div>"}},
    "-",
    {Glyph: "E712", Tip: "More", Menu: [["Open Storage settings", (*) => Say("Settings")],
                                        ["Clean up now",          (*) => Say("Cleaning...")]]}
])

; ---- 3. a split button and a primary action ---------------------------------
g.AddExpander("vreport Icon=E9F9", "Weekly report", "A split button: the face exports, the arrow picks how")
g.AddText("", "Export runs the usual format; the arrow offers the others.")
g.Use()
g.Actions("report", [
    {Id: "rpExport", Glyph: "EDE1", Text: "Export", Primary: true,
        Click: (*) => Say("Exported as PDF"),
        Menu: [["As PDF", (*) => Say("PDF")], ["As CSV", (*) => Say("CSV")], ["As HTML", (*) => Say("HTML")]]},
    {Id: "rpDelete", Glyph: "E74D", Tip: "Delete", Click: (*) => Say("Deleted")}
])

; ---- 4. a code block: copy appears on hover ---------------------------------
CODE := 'g.Actions("specs", [{Glyph: "E8C8", Text: "Copy", Copy: SpecsText}])'
g.AddCard("vcode", "")
g.AddHtml("", '<pre style="margin:0;font:13px Consolas,monospace;white-space:pre-wrap">' AxWindow._Esc(CODE) '</pre>')
g.Use()
g.Actions("code", [{Glyph: "E8C8", Copy: CODE}], {Reveal: "hover"})

; ---- 5. live: change a button after the fact ---------------------------------
g.AddCard("vlive", "Changing them live")
g.AddSwitch("vlock", "Lock the storage card's buttons")
    .OnEvent("Change", (c, v, *) => (g.Action("stRefresh", {Disabled: v}), g.Action("stPin", {Disabled: v})))
g.AddSwitch("vhideDel", "Hide Delete on the report")
    .OnEvent("Change", (c, v, *) => g.Action("rpDelete", {Hidden: v}))
g.Use()

g.Show()
