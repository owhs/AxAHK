#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes/icons (single-file exe)
#Include ..\lib\AxGui.ahk
#Include ..\lib\AxAssets.ahk

; =============================================================================
;  Retro.ahk — one window, three eras
;  ---------------------------------------------------------------------------
;  Switch the whole stylesheet live:
;    • Windows 11        → themes/win11.css
;    • Windows 98 Classic → themes/win98.css
;    • Windows XP Luna   → themes/winxp.css
;  Same markup, same behaviour — only the CSS changes.
; =============================================================================


; ─────────────────────────────────────────────────────────────────────────────
;  Window — initialization
; ─────────────────────────────────────────────────────────────────────────────

g := AxGui({
    Title:      "Control Panel",
    Width:      720,
    Height:     560,
    MinWidth:   560,
    MinHeight:  420,
    Stylesheet: "win98",
    Theme:      "light",
    BackColor:  "c0c0c0"
})


; ─────────────────────────────────────────────────────────────────────────────
;  Page: General
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("general", "General", "E713")

g.AddText("Caption", "Appearance")

g.AddSegmented("vtheme Choose2", "win11:Windows 11:E7C4|win98:Windows 98:E7F4|winxp:Windows XP:E7E8")
    .OnChange((c, v, *) => SwitchTheme(v))

g.AddInfoBar('vibar Kind=info Title="Tip:"', "Right-click the title bar for the real system menu. The icon in the corner is the script's own icon.")


; -- Group: Display -----------------------------------------------------------

g.AddGroupBox("", "Display")

g.AddText("w120", "Colour scheme:")
g.AddDDL("vscheme x+6 w180 Choose1", "std:Windows Standard|hc:High Contrast Black|rain:Rainy Day|brick:Brick|eggplant:Eggplant|rose:Rose|slate:Slate")
    .OnChange((c, v, *) => SetScheme(v))

g.AddText("w120", "Screen resolution:")
g.AddSlider('vres x+6 w200 Min=640 Max=1920 Step=160 Suffix=" px"', 1024)

g.AddText("w120", "Refresh rate:")
g.AddNumber('vhz x+6 Min=60 Max=240 Step=15 Suffix=" Hz"', 75)

g.AddCheckBox("vfx Checked", "Show window contents while dragging")
g.AddCheckBox("x+12 vsmooth", "Smooth edges of screen fonts")

g.Use()


; -- Group: Sounds ------------------------------------------------------------

g.AddGroupBox("", "Sounds")

g.AddText("w120", "Scheme:")
g.AddRadio("vsnd x+6 Choose1", "default:Windows Default|jungle:Jungle|utopia:Utopia|none:No Sounds")

g.AddText("w120", "Volume:")
g.AddSlider('vvol x+6 w200 Suffix="%"', 60)

g.AddText("w120", "Startup:")
g.AddSwitch("vstartup x+6 Checked", "Play")

g.Use()


; -- Group: Progress ----------------------------------------------------------

g.AddText("Caption", "Progress")

g.AddProgress("vpb w300", 40)
g.AddButton("x+8", "Scan")
    .OnClick((*) => StartScan())

g.AddButton("vok Accent", "OK")
    .OnClick((*) => (g.Toast("Settings saved.", 1500), EvLogger("OK")))

g.AddButton("x+6", "Cancel")
    .OnClick((*) => g.Confirm("Discard changes?", "Control Panel") ? g.Toast("Discarded", 1200) : "")

g.AddButton("x+6", "Apply")
    .OnClick((*) => g.Alert("Your settings have been applied.`n`nSome changes take effect after you restart.", "Display Properties"))


; ─────────────────────────────────────────────────────────────────────────────
;  Page: Programs
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("programs", "Programs", "E8FD")

g.AddText("Caption", "Installed programs (Ctrl+click to select several)")

progs := g.AddListBox("vprogs w320 h120 Multi", "ie:Internet Explorer 6|wmp:Windows Media Player 9|paint:Paint|solitaire:Solitaire|minesweeper:Minesweeper|pinball:3D Pinball for Windows")
progs.OnChange((c, v, *) => EvLogger("Selected: " (v.Length ? Join(v) : "(none)")))

g.AddText("Caption", "Windows components (checkbox list)")

g.AddListBox("vcomps w320 h100 Checklist Value=ie|games", "ie:Internet Explorer|games:Games|msn:MSN Messenger|fax:Fax Services|iis:Internet Information Services")
    .OnChange((c, v, *) => EvLogger("Components: " Join(v)))

g.AddButton("", "Add/Remove…")
    .OnClick((*) => g.Prompt("Program name:", "Add program", "") != "" ? g.Toast("Installed.", 1500, "success") : "")

g.AddButton("x+6 Danger", "Remove")
    .OnClick((*) => g.Dialog("Remove " Join(g.Value("progs")) "?", "Confirm File Deletion", ["Yes", "No"], {Kind: "warning"}).Button = "Yes" ? g.Toast("Removed.", 1500) : "")

g.AddText("Caption", "Rating")
g.AddRating("vrate", 4)

g.AddText("Caption", "Tiles")
g.AddGrid("vtiles")

for t in [["mycomp", "E7F4", "My Computer"], ["docs", "E8A5", "My Documents"], ["net", "E774", "Network Neighborhood"], ["bin", "E74D", "Recycle Bin"]]
    g.AddTile("Value=" t[1] " Icon=" t[2] " Removable", t[3])

g.Use()


; ─────────────────────────────────────────────────────────────────────────────
;  Page: About
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("about", "About", "E946")

g.AddHtml("Fill",
    '<div style="text-align:center;padding:20px 0;"><div class="ico" style="font-size:48px;">&#xE7C4;</div>'
    . '<h2>AxWindow</h2><div>Microsoft (R) Windows-style themes for AutoHotkey v2</div>'
    . '<div class="hint">Same markup and behaviour; only the stylesheet changes.</div></div>'
)

g.AddConsole("vlog")


; ─────────────────────────────────────────────────────────────────────────────
;  Ready / Show
; ─────────────────────────────────────────────────────────────────────────────

g.OnReady((app) => (
    EvLogger("Ready — theme: " app.Stylesheet),
    app.Ctl("scheme").Enabled := (app.Stylesheet = "win98")
))

g.Show()

; =============================================================================
;  Helpers & state
; =============================================================================

Progress := 0

Join(arr, sep := ", ") {
    s := ""
    for v in arr
        s .= (s = "" ? "" : sep) v
    return s
}

EvLogger(msg) {
    if (g.Ready)
        g.Append("log", "<div>[" FormatTime(, "HH:mm:ss") "] " AxWindow._Esc(msg) "</div>")
}


; ─────────────────────────────────────────────────────────────────────────────
;  Colour schemes — layered over the stylesheet via SetExtraCss
;  [face, title start, title end, highlight, text, title text, window, window text]
; ─────────────────────────────────────────────────────────────────────────────

Schemes := Map(
    "std",      ["#c0c0c0", "#000080", "#1084d0", "#000080", "#000000", "#ffffff", "#ffffff", "#000000"],
    "hc",       ["#000000", "#800080", "#800080", "#008000", "#ffffff", "#ffffff", "#000000", "#ffffff"],
    "rain",     ["#8ba0b4", "#4a6b8a", "#7e9ab5", "#4a6b8a", "#000000", "#ffffff", "#ffffff", "#000000"],
    "brick",    ["#c0a890", "#800000", "#c86428", "#800000", "#000000", "#ffffff", "#ffffff", "#000000"],
    "eggplant", ["#c0c0c0", "#5c3d5c", "#9c7a9c", "#5c3d5c", "#000000", "#ffffff", "#ffffff", "#000000"],
    "rose",     ["#cfafb7", "#9f6070", "#e0b0c0", "#9f6070", "#000000", "#ffffff", "#ffffff", "#000000"],
    "slate",    ["#9db2c4", "#3c5b78", "#7a9bbd", "#3c5b78", "#000000", "#ffffff", "#ffffff", "#000000"]
)

SetScheme(name) {
    global Schemes

    if (!Schemes.Has(name))
        return
    c    := Schemes[name]
    face := c[1]
    hi   := c[4]
    txt  := c[5]
    win  := c[7]
    wtxt := c[8]
    hc   := (name = "hc")

    ; -- window face + text ------------------------------------------------
    ; -- "window" surfaces (list boxes, inputs, menus) + selection + title bar
    css := ""
    css .= "body, .card, .tab, .tab-panel, .group > .legend, .btn, .axdlg-btn, .segmented .seg, .numberbox .spin, .winbtn, .exp-header .chev, .exp-header, .chip, .tile, #axCtx, #axDlg, .dd-value:after, .sw-track:before, .passwordbox .reveal, .infobar .close, .hotkeybox .clear, .tile .remove, .sort-list .remove { background: " . face . "; color: " . txt . "; }"
    css .= " body, .card, .tab, .tab-panel, .btn, .axdlg-btn, .caption, .hint, .card-row .desc, .tile .desc, h1, h2, h3, .group > .legend, .exp-header, .exp-header .desc, .axctx-item, #axDlgText, .slider .out, .winbtn:before, .numberbox .spin:before, .dd-value:after, .exp-header .chev:before, .infobar .close:before, .hotkeybox .clear:before, .tile .remove:before, .sort-list .remove:before, .passwordbox .reveal { color: " . txt . "; }"
    css .= " #sidebar, .list, .dd-value, .dd-menu, .textbox input, .textbox textarea, .searchbox input, .numberbox input, .passwordbox input, .hotkeybox input, #axDlgInput, .check .box, .radio .ring, .sw-track, .hex, .infobar, .infobar.info, .infobar.success, .infobar.warning, .infobar.error, .sort-list .drag-item, .progress { background: " . win . "; color: " . wtxt . "; }"
    css .= " .nav-item, .dd-item, .list-item, .infobar .text, .infobar .ico, .check input:checked + .box, .radio input:checked + .ring:after, .sort-list .text, .sort-list .drag-handle, .hotkeybox .kb, .searchbox .ico { color: " . wtxt . "; }"
    css .= " .radio input:checked + .ring:after { background: " . wtxt . "; }"
    css .= " .nav-item.active, .dd-item.selected, .list-item.selected, .dd-item:hover, .list-item:hover, .axctx-item:hover, .chip.on, .switch input:checked + .sw-track, .badge.accent, .segmented .seg.active { background: " . hi . "; color: #ffffff; }"
    css .= " .progress .bar { background: repeating-linear-gradient(90deg, " . hi . " 0, " . hi . " 8px, " . win . " 8px, " . win . " 10px); }"
    css .= " .rating .star.on, .tile .ico, .link { color: " . (hc ? "#ffff00" : hi) . "; }"
    css .= " #titlebar, #axDlgTitle { background-color: " . c[2] . "; background-image: linear-gradient(90deg, " . c[2] . ", " . c[3] . "); color: " . c[6] . "; }"

    if (hc) {
        ; High Contrast: bevels become plain white lines, disabled = green as in Windows
        css .= " .btn, .axdlg-btn, .tab, .segmented .seg, .card, .group, .list, .dd-value, .textbox input, .numberbox input, .searchbox input, .passwordbox input, .hotkeybox input, .check .box, .radio .ring, .sw-track, .progress, #sidebar, .infobar, .sort-list .drag-item, .tile, .winbtn, .numberbox .spin, .dd-value:after { border-color: #ffffff; box-shadow: none; }"
        css .= " .btn:active, .winbtn:active { box-shadow: none; } .btn.disabled, .dropdown.disabled .dd-value { color: #00ff00; text-shadow: none; }"
    }

    g.SetExtraCss("scheme", g.Stylesheet = "win98" ? css : "")
    EvLogger("Scheme -> " name)
}

SwitchTheme(name) {
    g.SetStylesheet(name)
    g.Ctl("scheme").Enabled := (name = "win98")          ; classic colour schemes only exist in the Classic look
    SetScheme(g.Value("scheme"))
    g.SetTheme(name = "win11" ? "dark" : "light")
    g.Toast(name = "win98" ? "It is now safe to turn off your computer." : name = "winxp" ? "Welcome" : "Windows 11", 1500)
    EvLogger("Theme -> " name)
}


; ─────────────────────────────────────────────────────────────────────────────
;  Scan simulation
; ─────────────────────────────────────────────────────────────────────────────

StartScan() {
    global Progress := 0
    SetTimer(ScanTick, 50)
}

ScanTick() {
    global Progress += 3
    g.Style("pb_bar", "width", Progress "%")
    if (Progress >= 100)
        SetTimer(ScanTick, 0), g.Toast("Scan complete.", 1500, "success")
}
