#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes/icons (single-file exe)
#Include ..\lib\AxGui.ahk
#Include ..\lib\AxAssets.ahk

; =============================================================================
;  Transparent.ahk — how far a Trident-hosted window can be made see-through
;  ---------------------------------------------------------------------------
;  Four mechanisms, side by side, so the claims can be checked rather than
;  taken on trust. Open each one and watch the console at the bottom.
;
;   1. UNIFORM ALPHA          SetLayeredWindowAttributes / LWA_ALPHA
;      WinSetTransparent fades the whole window, browser content included.
;      Works on anything. Not per-pixel: text fades with the panel.
;
;   2. COLOUR KEY             SetLayeredWindowAttributes / LWA_COLORKEY
;      Every pixel of one exact colour becomes fully transparent AND
;      click-through, while everything else stays opaque and hit-testable.
;      The shape is whatever the CSS paints, which is the useful part.
;      Binary: there is no partial alpha, so edges are aliased.
;
;   3. WINDOW REGION          SetWindowRgn
;      An arbitrary outline clipped out of the window, child browser and all.
;      Also binary, also click-through outside the region, and it has to be
;      re-applied on every resize.
;
;   4. CLICK-THROUGH HUD      the two above, full screen
;      A borderless full-screen window whose background is keyed away: the
;      painted cards stay clickable, everything else passes to the desktop.
;      WS_EX_TRANSPARENT is the blunt alternative — it makes the whole window
;      click-through, floating elements included.
;
;  What NOT to expect, and why:
;
;   • Per-pixel alpha out of the page. UpdateLayeredWindow wants a
;     premultiplied ARGB bitmap; MSHTML paints through GDI onto an opaque
;     surface and never writes alpha bits, so there is no channel to hand
;     the compositor. Same root cause as the Mica note in the README.
;   • Mica / Acrylic by painting black. Trident paints every pixel opaque, so
;     black stays black. They do show in keyed pixels: see Glass.ahk.
;   • Smooth edges. Both shape mechanisms are one-bit. DWM's own rounded
;     corners (AxWindow's RoundCorners) are the one anti-aliased option,
;     and they only do the standard Win11 radius.
;
;  What this demo settled the hard way — all of it cost a run to find:
;
;   • "transparent" html/body does NOT expose the window's brush. A windowed
;     WebBrowser control paints its canvas white whatever the CSS says, so the
;     key colour never reached the screen and the window stayed opaque. The
;     page has to paint the key colour itself.
;   • PICK A KEY CLOSE TO YOUR EDGES, not a colour "nothing could be". This is
;     the opposite of the usual advice and it matters more than anything else
;     here. A key is one-bit: every antialiased pixel along a curve is a blend
;     of the edge colour and the key, matches neither, and survives. Against
;     magenta that leftover is a pink halo on every rounded corner; against a
;     near-black key the same pixels read as ordinary antialiasing. Nothing
;     removes the fringe — only its colour is yours to choose. A window region
;     has no fringe at all, which is the real reason to prefer one for a solid
;     shape.
;   • A BLURRED SHADOW CANNOT BE KEYED AT ALL. It is a gradient between the
;     shadow and the key across its whole width, so the entire halo survives
;     however well the key is chosen. Hard edges only, anywhere near the key.
;   • style.background (the shorthand) throws across IE's COM bridge and takes
;     the whole assignment with it; style.backgroundColor does not.
;   • An exception inside a COM event callback surfaces nowhere. ApplyShape
;     aborted silently for two rounds and simply looked like "the region does
;     nothing" — hence the try/catch that logs e.What.
;   • RDW_ERASE over a full-screen layered window is a visible flash once a
;     second. Invalidate the one element's rectangle, and never ask for an
;     erase pass.
;
;  Still open, and what the two switches are for: whether the DWM shadow stays
;  rectangular around a keyed shape, and whether the repaint nudge is needed
;  at all — turn "Nudge the repaint" off and see whether the clock still ticks.
; =============================================================================


; The key colour. The usual advice is "pick something no real pixel could be",
; which is how you end up at magenta -- and magenta is the worst choice there
; is. A colour key is one-bit: every antialiased pixel along a curve is a
; BLEND of the edge colour and the key, matches neither, and survives. With
; magenta those leftovers glow pink around every rounded corner.
;
; So the rule is the opposite of the folklore: pick a key CLOSE IN LUMINANCE
; to the edges it will sit against. The blends then read as a faint dark
; outline -- indistinguishable from ordinary antialiasing -- instead of a
; halo. Near-black is the safe general answer for dark artwork. Flip the
; "Key colour" control to magenta to see the same shape fringe horribly.
KEY        := "0A0B0D"
shapeWin   := ""            ; the shaped demo window
hudWin     := ""            ; the full-screen overlay
logBox     := ""
shapeMode  := "key"


; ─────────────────────────────────────────────────────────────────────────────
;  Control panel
; ─────────────────────────────────────────────────────────────────────────────

g := AxGui({
    Title:      "Transparency",
    Width:      740,
    Height:     660,
    MinWidth:   560,
    MinHeight:  520,
    Stylesheet: "precision",
    Theme:      "dark"
})

g.AddPage("main", "Transparency", "E890")

g.AddInfoBar('Kind=info Title="Every effect here is applied to a real window."',
    "Nothing is simulated in CSS. Drag the shaped window over something bright to judge the edges.")


; -- 1. uniform alpha ---------------------------------------------------------

g.AddText("Caption", "Uniform alpha")

g.AddRow("Icon=E7B3", "Whole-window opacity",
    "SetLayeredWindowAttributes with LWA_ALPHA, applied to this window")
g.AddSlider('vAlpha Min=40 Max=255 Step=5 w220', 255)
    .OnChange((c, v, *) => SetAlpha(v))
g.Use()

g.AddRow("Icon=E72C", "Back to opaque", "255 is the same as not being layered at all")
g.AddButton("", "Reset").OnClick((*) => (g.Ctl("Alpha").Value := 255, SetAlpha(255)))
g.Use()


; -- 2 + 3. shape ------------------------------------------------------------

g.AddText("Caption", "Shaped window")

g.AddRow("Icon=E790", "Key colour",
    "One-bit: blends against the key survive it. Pick one close to your edges.")
g.AddSegmented("vKeyColour Choose2", "FF00FE:Magenta|0A0B0D:Near-black")
    .OnChange((c, v, *) => SetKey(v))
g.Use()

g.AddRow("Icon=E80A", "How the shape is cut",
    "Colour key reads the shape out of the CSS; Round and Polygon are regions made in AHK")
g.AddSegmented("vShapeMode Choose1",
    "key:Colour key|round:Round|poly:Polygon|none:None")
    .OnChange((c, v, *) => SetShapeMode(v))
g.Use()

g.AddRow("Icon=E8A7", "Shaped window", "Opens borderless; drag it by its body, X to close")
g.AddButton("vBtnShape Accent", "Open").OnClick((*) => ToggleShape())
g.Use()

g.AddRow("Icon=E7E6", "Drop shadow",
    "AxWindow adds one with DwmExtendFrameIntoClientArea — does it stay rectangular?")
g.AddSwitch("vShadow Checked").OnEvent("Change", (c, v, *) => SetShadow(v))
g.Use()

g.AddRow("Icon=E72C", "Force a repaint", "Does Trident come back cleanly inside a layered window?")
g.AddButton("", "Repaint").OnClick((*) => Repaint())
g.Use()


; -- 4. full-screen HUD -------------------------------------------------------

g.AddText("Caption", "Full-screen overlay")

g.AddRow("Icon=E7F4", "Click-through HUD",
    "Full screen, keyed background: cards stay clickable, the gaps do not")
g.AddButton("vBtnHud Accent", "Open").OnClick((*) => ToggleHud())
g.Use()

g.AddRow("Icon=E72C", "Nudge the repaint",
    "Redraw the clock's own rectangle each tick — does it still tick with this off?")
g.AddSwitch("vNudge Checked")
g.Use()

g.AddRow("Icon=E8B0", "Click through everything",
    "WS_EX_TRANSPARENT — the blunt version: the cards stop responding too")
g.AddSwitch("vPassAll").OnEvent("Change", (c, v, *) => SetPassThrough(v))
g.Use()

g.AddText("hint", "The overlay is always on top. Esc closes it from anywhere.")


; -- what happened ------------------------------------------------------------

g.AddText("Caption", "Console")
logBox := g.AddConsole("vlog h150")

g.AddStatusBar([
    {Id: "msg", Text: "Ready", Icon: "E930", Grow: true},
    {Id: "key", Text: "key #" KEY, Width: 130, Dim: true}
])

g.OnClose((*) => (CloseShape(), CloseHud()))
g.Show()
EvLogger("Ready. Screen is " A_ScreenWidth "x" A_ScreenHeight ".")


; ─────────────────────────────────────────────────────────────────────────────
;  1. uniform alpha
; ─────────────────────────────────────────────────────────────────────────────

SetAlpha(v) {
    global g
    v := Round(v)
    if (v >= 255) {
        WinSetTransparent("Off", g.Gui)
        EvLogger("Alpha off (window is no longer layered).")
    } else {
        WinSetTransparent(v, g.Gui)
        EvLogger("Alpha " v "/255 — note the text fades with the panel: this is not per-pixel.")
    }
    g.Status("msg", "Alpha " (v >= 255 ? "off" : v))
}


; ─────────────────────────────────────────────────────────────────────────────
;  2 + 3. the shaped window
; ─────────────────────────────────────────────────────────────────────────────

ToggleShape() {
    global shapeWin
    if IsObject(shapeWin)
        CloseShape()
    else
        OpenShape()
}

OpenShape() {
    global shapeWin, g, KEY, shapeMode
    ; Resizable:false keeps the window rect equal to the client rect, so the
    ; region coordinates below map 1:1 onto what the page paints. With
    ; WS_THICKFRAME there is a sizing border in between and every point moves.
    ; AxWindow's first argument is a file path -- markup goes in opts.Html,
    ; which is exactly how AxGui feeds it a generated page.
    shapeWin := AxWindow("", {
        Html:        ShapeHtml(),
        Title:       "Shape",
        Width:       420,
        Height:      300,
        X:           A_ScreenWidth // 2 - 210,
        Y:           A_ScreenHeight // 2 - 150,
        BackColor:   KEY,          ; the page is transparent, so this is what shows
        Frame:       false,        ; the page brings its own drag handle and close
        Chrome:      {Titlebar: "dragArea"},   ; NOT "titlebar" -- see the note below
        Resizable:   false,
        MaximizeBox: false,
        MinimizeBox: false,
        RoundCorners: false,
        ExitOnClose: false,
        Theme:       ""
    })
    shapeWin.Show()
    shapeWin.WaitReady()
    shapeWin.On("click", "btnClose", (*) => CloseShape())
    g.Text("BtnShape", "Close")
    EvLogger("Shaped window open (" shapeMode ").")
    ApplyShape()
}

CloseShape() {
    global shapeWin, g
    if !IsObject(shapeWin)
        return
    try shapeWin.Close()
    shapeWin := ""
    try g.Text("BtnShape", "Open")
    EvLogger("Shaped window closed.")
}

SetKey(hex) {
    global KEY, shapeWin, g
    KEY := hex
    if IsObject(shapeWin)
        shapeWin.SetBackColor(KEY)
    ApplyShape()
    g.Status("key", "key #" KEY)
    EvLogger("Key colour -> #" hex
        . (hex = "FF00FE" ? " — watch the rounded corners fringe pink" : " — fringe reads as a dark edge"))
}

SetShapeMode(v) {
    global shapeMode
    shapeMode := v
    ApplyShape()
    EvLogger("Shape mode -> " v)
}

; Clear whatever the last mode set, then apply the new one. Both mechanisms
; have to be undone explicitly: a stale region survives a colour-key change
; and the two together are very confusing to look at.
ApplyShape() {
    global shapeWin, shapeMode, KEY
    if !IsObject(shapeWin)
        return
    hwnd := shapeWin.Gui.Hwnd
    try {
        ; WinSetTransColor("Off") on a window that was never layered is the prime
        ; suspect for the abort, so only ask for it when WS_EX_LAYERED is actually
        ; set. GWL_EXSTYLE is -20, WS_EX_LAYERED is 0x80000.
        if (DllCall("GetWindowLongPtr", "Ptr", hwnd, "Int", -20, "Ptr") & 0x80000)
            WinSetTransColor("Off", shapeWin.Gui)
        DllCall("User32\SetWindowRgn", "Ptr", hwnd, "Ptr", 0, "Int", 1)
        WinGetPos(, , &w, &h, shapeWin.Gui)
        ; Window rect vs client rect: if these differ the window still has a
        ; non-client frame, and every region coordinate below is off by it.
        rc := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
        EvLogger("apply " shapeMode ": win " w "x" h ", client "
            . NumGet(rc, 8, "Int") "x" NumGet(rc, 12, "Int"))
        ; Only the colour-key mode wants the page painted magenta; in the region
        ; modes nothing removes it, so it would just be a magenta window.
        SetPageBg(shapeWin, (shapeMode = "key") ? "#" KEY : "#14171c")
        switch shapeMode {
            case "key":
                WinSetTransColor(KEY, shapeWin.Gui)
            case "round":
                RoundRegion(hwnd, w, h, 90)
            case "poly":
                PolyRegion(hwnd, [[w // 2, 0], [w, h // 3], [w - 40, h], [40, h], [0, h // 3]])
            case "none":
                EvLogger("no shape: the window is a plain rectangle again")
        }
        Repaint()
    } catch as e
        EvLogger("ApplyShape FAILED in " e.What ": " e.Message)
}

; The page paints the key colour itself rather than leaving html/body
; transparent. A windowed WebBrowser control paints its canvas white whatever
; "transparent" says, so the Gui's BackColor never reaches the screen and the
; key would match nothing -- the window just stays opaque white.
SetPageBg(w, color) {
    try {
        w.Doc.documentElement.style.backgroundColor := color
        w.Doc.body.style.backgroundColor := color
        EvLogger("page background -> " color
            . " (body now reports " w.Doc.body.currentStyle.backgroundColor ")")
    } catch as e
        EvLogger("SetPageBg FAILED: " e.Message)
}

; SetWindowRgn takes ownership of the region — deleting it here would be a
; double free the moment the window repaints.
RoundRegion(hwnd, w, h, r) {
    rgn := DllCall("Gdi32\CreateRoundRectRgn", "Int", 0, "Int", 0,
                   "Int", w + 1, "Int", h + 1, "Int", r, "Int", r, "Ptr")
    ok := DllCall("User32\SetWindowRgn", "Ptr", hwnd, "Ptr", rgn, "Int", 1)
    EvLogger("CreateRoundRectRgn -> " (rgn ? "ok" : "NULL")
        . " | SetWindowRgn -> " (ok ? "ok" : "FAILED err " A_LastError))
}

PolyRegion(hwnd, pts) {
    buf := Buffer(pts.Length * 8, 0)
    for i, p in pts {
        NumPut("Int", p[1], buf, (i - 1) * 8)
        NumPut("Int", p[2], buf, (i - 1) * 8 + 4)
    }
    rgn := DllCall("Gdi32\CreatePolygonRgn", "Ptr", buf, "Int", pts.Length,
                   "Int", 1, "Ptr")            ; 1 = ALTERNATE
    ok := DllCall("User32\SetWindowRgn", "Ptr", hwnd, "Ptr", rgn, "Int", 1)
    EvLogger("CreatePolygonRgn -> " (rgn ? "ok" : "NULL")
        . " | SetWindowRgn -> " (ok ? "ok" : "FAILED err " A_LastError))
}

; AxWindow.Show calls AxSys.Shadow, which is DwmExtendFrameIntoClientArea with
; a 1px margin all round. Zero margins take it back off.
SetShadow(on) {
    global shapeWin
    if !IsObject(shapeWin) {
        EvLogger("Open the shaped window first.")
        return
    }
    if on
        AxSys.Shadow(shapeWin.Gui.Hwnd)
    else {
        m := Buffer(16, 0)
        DllCall("dwmapi\DwmExtendFrameIntoClientArea", "Ptr", shapeWin.Gui.Hwnd, "Ptr", m)
    }
    Repaint()
    EvLogger("Drop shadow " (on ? "on" : "off") " — watch whether it follows the shape.")
}

Repaint() {
    global shapeWin, hudWin
    for w in [shapeWin, hudWin] {
        if !IsObject(w)
            continue
        ; RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW. No RDW_ERASE: an
        ; erase pass over a full-screen layered window is a visible white flash
        ; once a second, which is exactly what it looked like.
        DllCall("User32\RedrawWindow", "Ptr", w.Gui.Hwnd, "Ptr", 0, "Ptr", 0,
                "UInt", 0x1 | 0x80 | 0x100)
    }
}

; Invalidate one element's rectangle rather than the whole screen. The browser
; renders at the ActiveX control's client size, so page coordinates have to be
; scaled by the same ratio AxWindow._IconMenu uses to place the icon menu.
RedrawEl(w, id) {
    try {
        r  := w.El(id).getBoundingClientRect()
        rc := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", w.Ax.Hwnd, "Ptr", rc)
        k  := NumGet(rc, 8, "Int") / w.Doc.documentElement.clientWidth
        box := Buffer(16, 0)
        NumPut("Int", Round(r.left   * k) - 2, box, 0)
        NumPut("Int", Round(r.top    * k) - 2, box, 4)
        NumPut("Int", Round(r.right  * k) + 2, box, 8)
        NumPut("Int", Round(r.bottom * k) + 2, box, 12)
        DllCall("User32\RedrawWindow", "Ptr", w.Ax.Hwnd, "Ptr", box, "Ptr", 0,
                "UInt", 0x1 | 0x100)          ; INVALIDATE | UPDATENOW, no erase
    }
}


; ─────────────────────────────────────────────────────────────────────────────
;  4. the click-through overlay
; ─────────────────────────────────────────────────────────────────────────────

ToggleHud() {
    global hudWin
    if IsObject(hudWin)
        CloseHud()
    else
        OpenHud()
}

OpenHud() {
    global hudWin, g, KEY
    hudWin := AxWindow("", {
        Html:        HudHtml(),
        Title:       "Overlay",
        Width:       A_ScreenWidth,
        Height:      A_ScreenHeight,
        X:           0,
        Y:           0,
        BackColor:   KEY,
        Frame:       false,
        Resizable:   false,
        MaximizeBox: false,
        MinimizeBox: false,
        RoundCorners: false,
        ExitOnClose: false,
        Theme:       ""
    })
    hudWin.Show()
    hudWin.WaitReady()
    hudWin.AlwaysOnTop(true)
    m := Buffer(16, 0)          ; undo AxSys.Shadow: no frame extension on a full-screen sheet
    DllCall("dwmapi\DwmExtendFrameIntoClientArea", "Ptr", hudWin.Gui.Hwnd, "Ptr", m)
    ; the keyed pixels go transparent AND stop hit-testing, which is the whole
    ; trick: no WS_EX_TRANSPARENT needed for the gaps to pass clicks through
    WinSetTransColor(KEY, hudWin.Gui)
    hudWin.On("click", "hudBtn", (*) => (EvLogger("HUD button clicked — painted pixels still hit-test."),
                                          hudWin.Html("hudMsg", "clicked at " FormatTime(, "HH:mm:ss")),
                                          Repaint()))
    hudWin.On("click", "hudClose", (*) => CloseHud())
    SetTimer(HudClock, 1000)
    Hotkey("~Escape", (*) => CloseHud(), "On")
    g.Text("BtnHud", "Close")
    EvLogger("Overlay open. Click a card, then click the desktop through a gap.")
}

CloseHud() {
    global hudWin, g
    if !IsObject(hudWin)
        return
    SetTimer(HudClock, 0)
    try Hotkey("~Escape", "Off")
    try hudWin.Close()
    hudWin := ""
    try g.Text("BtnHud", "Open")
    try g.Ctl("PassAll").Checked := false
    EvLogger("Overlay closed.")
}

; A layered window does not re-composite just because Trident repainted a
; child: the DOM changes, the screen does not. Every content update has to be
; followed by a RedrawWindow over the whole window and its children.
HudClock() {
    global hudWin, g
    if !IsObject(hudWin)
        return
    try {
        hudWin.Html("hudClock", FormatTime(, "HH:mm:ss"))
        if (IsObject(g.Ctl("Nudge")) && g.Ctl("Nudge").Checked)
            RedrawEl(hudWin, "hudClock")
    }
}

; WS_EX_TRANSPARENT (0x20): the whole window stops hit-testing, cards included.
SetPassThrough(on) {
    global hudWin
    if !IsObject(hudWin) {
        EvLogger("Open the overlay first.")
        return
    }
    WinSetExStyle((on ? "+" : "-") "0x20", hudWin.Gui)
    EvLogger("WS_EX_TRANSPARENT " (on ? "on — the cards have stopped responding too."
                                : "off — the cards are live again."))
}


; ─────────────────────────────────────────────────────────────────────────────
;  Pages
; ─────────────────────────────────────────────────────────────────────────────

; The page paints the key colour itself. Leaving html and body "transparent"
; and letting the Gui's BackColor show through does NOT work here: a windowed
; WebBrowser control paints its canvas white regardless, so the key matched
; nothing and the window stayed opaque. Paint the key, then key it away.
;
; The wrapper is #dragArea, not #titlebar. base.css is injected into every
; page (AxWindow._InjectUI) and carries "#titlebar{height:32px;display:flex}",
; so a full-bleed #titlebar collapses to 32px — height beats the top/bottom
; pair. opts.Chrome.Titlebar renames the drag handle instead.
ShapeHtml() {
    global KEY
    h := '<!DOCTYPE html><html><head><meta http-equiv="X-UA-Compatible" content="IE=edge">'
    h .= '<meta charset="utf-8"><title>Shape</title><style>'
    h .= 'html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#' KEY ';'
    h .= 'font-family:"Segoe UI",sans-serif;-ms-user-select:none;user-select:none;cursor:default}'
    h .= '#dragArea{position:absolute;left:0;top:0;right:0;bottom:0}'
    h .= '#blob{position:absolute;left:30px;top:30px;right:30px;bottom:30px;'
    h .= 'background:#10b981;border-radius:120px 24px 120px 24px;color:#052b20;'
    h .= 'box-shadow:0 0 0 3px #052b20}'
    h .= '#label{position:absolute;left:0;right:0;top:50%;margin-top:-34px;text-align:center;'
    h .= 'font-size:15px;font-weight:600;line-height:20px}'
    h .= '#label small{display:block;font-weight:400;opacity:.72;font-size:12px;margin-top:6px}'
    h .= '#btnClose{position:absolute;right:14px;top:10px;width:22px;height:22px;line-height:22px;'
    h .= 'text-align:center;font-size:13px;background:#052b20;color:#10b981;border-radius:11px}'
    h .= '#btnClose:hover{background:#e05252;color:#fff}'
    h .= '</style></head><body><div id="dragArea"><div id="blob">'
    h .= '<div id="btnClose">&#215;</div>'
    h .= '<div id="label">Drag me over something bright'
    h .= '<small>Switch the key to magenta and watch these corners</small></div>'
    h .= '</div></div></body></html>'
    return h
}

; Full-bleed key colour with a few opaque cards on top. The gaps are the key,
; so they vanish and stop hit-testing at the same time.
HudHtml() {
    global KEY
    h := '<!DOCTYPE html><html><head><meta http-equiv="X-UA-Compatible" content="IE=edge">'
    h .= '<meta charset="utf-8"><title>Overlay</title><style>'
    h .= 'html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#' KEY ';'
    h .= 'font-family:"Segoe UI",sans-serif;-ms-user-select:none;user-select:none;cursor:default;color:#dfe3e8}'
    ; No box-shadow anywhere near the key colour: a blurred shadow is a
    ; gradient BETWEEN the shadow and the key, so not one of its pixels is an
    ; exact match and the entire halo survives as a magenta glow. Hard edges
    ; only. This is the sharpest practical limit of colour keying.
    h .= '.card{position:absolute;background:#14171c;border:1px solid #3f434a;padding:14px 16px}'
    h .= '.k{font:600 10px Consolas,monospace;letter-spacing:.16em;text-transform:uppercase;color:#5c6470;'
    h .= 'display:block;margin-bottom:8px}'
    h .= '#c1{left:40px;top:40px;width:250px}'
    h .= '#c2{right:40px;top:40px;width:270px}'
    h .= '#c3{left:50%;margin-left:-190px;bottom:52px;width:380px;text-align:center}'
    h .= '#hudClock{font:600 34px Consolas,monospace;color:#10b981;letter-spacing:.04em}'
    h .= '#hudBtn{display:inline-block;margin-top:4px;padding:7px 16px;background:#10b981;color:#052b20;'
    h .= 'font-size:13px;font-weight:600}'
    h .= '#hudBtn:hover{background:#1ecb92}'
    h .= '#hudClose{position:absolute;right:10px;top:8px;width:20px;height:20px;line-height:20px;'
    h .= 'text-align:center;font-size:13px;color:#5c6470}'
    h .= '#hudClose:hover{background:#e05252;color:#fff}'
    h .= '#hudMsg{font-size:12px;color:#8e97a3;margin-top:8px;min-height:16px}'
    h .= '</style></head><body>'
    h .= '<div class="card" id="c1"><span class="k">Clock</span>'
    h .= '<div id="hudClock">--:--:--</div></div>'
    h .= '<div class="card" id="c2"><div id="hudClose">&#215;</div><span class="k">Read me</span>'
    h .= 'The desktop between these cards is still yours: click it, drag an icon, '
    h .= 'select text in a window underneath. Only what is painted takes the mouse.</div>'
    h .= '<div class="card" id="c3"><span class="k">Hit test</span>'
    h .= '<div id="hudBtn">Click this card</div><div id="hudMsg"></div></div>'
    h .= '</body></html>'
    return h
}


; ─────────────────────────────────────────────────────────────────────────────
;  Console
; ─────────────────────────────────────────────────────────────────────────────

EvLogger(msg) {
    global g, logBox
    if (!IsObject(g) || !g.Ready)
        return
    g.Append(logBox.Id, '<div>[' FormatTime(, "HH:mm:ss") '] ' AxWindow._Esc(msg) '</div>')
    logBox.El.scrollTop := logBox.El.scrollHeight
}
