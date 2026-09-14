#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes/icons (single-file exe)
#Include ..\lib\AxGui.ahk

; =============================================================================
;  Glass.ahk — Mica and Acrylic behind a Trident page
;  ---------------------------------------------------------------------------
;  A stress test more than a showcase: every switch on the first page changes
;  the real window, so each material, tint and stylesheet and the controls
;  on the other pages can be judged on the glass. Dark only (see below).
;
;  Measured before this was written (scratch tests, 2026-09-14):
;
;   • Trident paints every pixel OPAQUE. Read back from the window, the page
;     has alpha 255 everywhere -- black included, GPU or CPU drawing. So the
;     trick that works for plain Gui controls (paint black, extend the frame,
;     black turns to glass) does nothing for a page: GDI leaves alpha at 0,
;     the browser does not. (For Gui controls it is additive, too: #202020
;     over Acrylic comes out 0x20 brighter, which is why text goes pale.)
;   • A COLOUR KEY does work. On a layered window DWM treats the keyed pixels
;     as holes and the backdrop shows in them; every other pixel stays solid.
;   • The key goes on the PAGE ALONE: the browser's host window is a child,
;     and child windows can be layered. Its keyed pixels show our own window
;     behind it, painted black -- alpha 0 to DWM, so the backdrop. A click on
;     the glass lands on our window, not the desktop: the title bar and the
;     edges answer WM_NCHITTEST (so dragging, Snap, double-click and sizing
;     are Windows' own), and a button or the wheel is handed on to the page.
;     Keying the whole window instead (Transparent.ahk's way) lets clicks on
;     the glass fall through to whatever is behind it, and focus with them.
;
;  What that means for a design:
;
;   • One bit. A pixel is glass or it is solid; nothing is half see-through.
;     So the default is Windows 11's own layout: the title bar and the nav rail
;     on the backdrop, the page on a solid layer. "Content on glass" drops the
;     layer to show what the controls do without it.
;   • DARK ONLY. The key is a shade off the dark sheets' own background, so
;     every translucent hover comes out as designed and anti-aliased edges
;     read as that background. Light glass was tried and dropped: a light key
;     would have to change with the theme (a key change and the page's repaint
;     cannot share a frame, so the old background flashes as a solid block),
;     and on the dark key light text, hovers and edges all went muddy.
;   • TINT is the window behind the page, painted a colour instead of black.
;     GDI's alpha is 0, so DWM ADDS that colour over the backdrop: a wash of
;     colour or light on any material, never darker. Changing it repaints
;     nothing of the page -- the page's host window is layered, a surface of
;     its own, so painting its parent cannot touch it.
;   • No CSS opacity on anything over the key. The element is blended as a
;     whole, key included, and the blend rounds a level off: a transparent
;     box at opacity .7 comes out a solid strip one shade from the key. The
;     same goes for the rounded corners of a box with no background: they are
;     anti-aliased anyway, so on the glass round only what is painted.
;   • A glass pixel is our window, not the page, so the page never hears the
;     mouse move over it. Nav items and window buttons are lit from here
;     (class axglass-hover) until the pointer is over something painted.
;   • Mica and Acrylic go flat while the window is inactive -- Windows' rule.
;   • The older accent-policy blur (SetWindowCompositionAttribute, what
;     Windows 10 apps used) was tried and dropped: behind this window it
;     showed plain black, with the backdrop type at NONE or AUTO alike.
; =============================================================================


; ─────────────────────────────────────────────────────────────────────────────
;  The window: AxGui plus a backdrop behind a colour key on the page
; ─────────────────────────────────────────────────────────────────────────────

class GlassGui extends AxGui {
    static Key := "201F23"    ; see above: a shade off #202020, and not a grey
    static Tints := Map("white", "FFFFFF", "warm", "FF9A3C", "rose", "FF4F8B", "green", "3CD08A")
    Material  := "acrylic"    ; "none" | "mica" | "tabbed" | "acrylic"
    OnGlass   := false        ; the page content straight on the backdrop, no layer under it
    GlassTintColor := "none"       ; "none" | "accent" | a name in Tints | "rrggbb"
    GlassTintStrength := 35        ; 0..100
    Said      := Map()        ; what each Windows call returned, for the diagnostics

    __New(opts := "") {
        super.__New(opts)
        this._dark := "", this._tracking := false
        this._offFn := ObjBindMethod(this, "_GlassOffLate")
        if (this.Material != "none")
            this.SetExtraCss("glass", this._GlassCss())         ; in the page's <head>: glass from the first frame
        fn := ObjBindMethod(this, "_GlassMouse")
        for msg in [0xA0, 0x200, 0x201, 0x203, 0x204, 0x205, 0x206, 0x207, 0x208, 0x209, 0x20A, 0x20E, 0x2A3]
            OnMessage(msg, fn)
        this._lit := false
    }

    ; ------------------------------------------------------------ switches
    ; Each one changes only what it has to: nothing here forces the page to
    ; repaint, and a material change touches the backdrop alone.
    SetMaterial(m) {
        was := this.Material
        if (m = was)
            return this
        this.Material := m
        if (was = "none") {
            ; on: the backdrop first, then the page onto the key. Off had the
            ; base set a caption colour and dark mode; both are ours again.
            SetTimer(this._offFn, 0)
            this._dark := ""
            AxGlassDwm(this.Gui.Hwnd, 35, 0xFFFFFFFF)                ; DWMWA_CAPTION_COLOR: default
            this._GlassMaterial()
            this.SetExtraCss("glass", this._GlassCss())
            this.BodyClass("onglass", this.OnGlass)
            this.SetBackColor(this._GlassBack())
        } else if (m = "none") {
            ; off: the page off the key first; the backdrop goes once it has
            ; repainted, or the glass shows as black for a frame
            this.SetExtraCss("glass", "")
            this.BodyClass("onglass", false)
            this.SetBackColor(this.ThemeBack(this.Theme))
            SetTimer(this._offFn, -120)
        } else
            this._GlassMaterial()
        return this
    }
    SetOnGlass(on) {
        this.OnGlass := on
        this.BodyClass("onglass", on && this.Material != "none")
        return this
    }
    ; SetTint("accent" | "warm" | "rrggbb" | "none", 0..100); either may be ""
    SetTint(color := "", strength := "") {
        if (color != "")
            this.GlassTintColor := color
        if (strength != "")
            this.GlassTintStrength := strength
        if (this.Material != "none")
            this.SetBackColor(this._GlassBack())
        return this
    }
    ; the colour DWM adds over the backdrop (see top): the tint, scaled
    _GlassBack() {
        t := this.GlassTintColor
        if (t = "none" || this.GlassTintStrength <= 0)
            return "000000"
        hex := (t = "accent") ? LTrim(this._accent != "" ? this._accent : "#60cdff", "#")
             : GlassGui.Tints.Has(t) ? GlassGui.Tints[t] : LTrim(t, "#")
        c := Integer("0x" hex), f := this.GlassTintStrength / 100 * 0.4
        return Format("{:02X}{:02X}{:02X}", Round((c >> 16 & 0xFF) * f), Round((c >> 8 & 0xFF) * f), Round((c & 0xFF) * f))
    }
    ; the layer takes the new sheet's colours
    SetStylesheet(name) {
        super.SetStylesheet(name)
        if (this.Material != "none")
            this.SetExtraCss("glass", this._GlassCss())
        return this
    }

    ; ------------------------------------------------------ base overrides
    ThemeBack(mode) => (this.Material = "none") ? super.ThemeBack(mode) : this._GlassBack()

    ; Every theme, stylesheet and tint change comes through here. With the
    ; glass on, the window under the page is only ever black or the tint, and
    ; the key stays the key, so the base's work (caption colour, dark mode
    ; guessed from the colour, a forced repaint of the page) is left out: it
    ; is what made the title bar flicker.
    SetBackColor(hex) {
        if (this.Material = "none")
            return super.SetBackColor(hex)
        back := this._GlassBack()
        this.BackColor := back
        try if (this.Gui.BackColor != back)
            this.Gui.BackColor := back
        this._GlassBrushes()
        this._GlassDark()
        return this
    }

    ; the page has just loaded: key its host window, for good
    _InstallSubclasses() {
        super._InstallSubclasses()
        if this.HasOwnProp("_keyed")
            return
        this._keyed := true
        h := this.Ax.Hwnd
        DllCall("SetWindowLongPtr", "Ptr", h, "Int", -20, "Ptr", DllCall("GetWindowLongPtr", "Ptr", h, "Int", -20, "Ptr") | 0x80000)
        rgb := Integer("0x" GlassGui.Key)
        ok := DllCall("SetLayeredWindowAttributes", "Ptr", h,
                      "UInt", ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | (rgb >> 16), "UChar", 0, "UInt", 1)
        this.Said["page key"] := ok ? "#" GlassGui.Key " on the page's host window" : "FAILED (error " A_LastError ")"
        this._GlassHoverJs()
        if (this.Material != "none")                             ; before the window is first shown
            this._GlassMaterial()
    }

    ; Show() puts a 1px frame on (the drop shadow); the glass needs the whole
    ; client as frame, or our black is not read as alpha 0
    _UpdateBorder() {
        super._UpdateBorder()
        if (this.Material != "none")
            this._GlassFrame()
    }

    _OnMsg(w, l, msg, hwnd) {
        if (this.Material != "none") {
            ; the base answers WM_NCACTIVATE itself to skip a frame repaint, so
            ; DWM would never hear the window is active and the backdrop would
            ; stay in its flat, inactive look. -1: update, paint nothing.
            if (msg = 0x86)
                DllCall("DefWindowProc", "Ptr", hwnd, "UInt", 0x86, "Ptr", w, "Ptr", -1)
            else if (msg = 0x84) {
                r := super._OnMsg(w, l, msg, hwnd)          ; the maximize button first (Snap Layouts)
                return (r != "") ? r : this._GlassHit(l)
            }
        }
        return super._OnMsg(w, l, msg, hwnd)
    }

    ; ------------------------------------------------------------- Windows
    _GlassMaterial() {
        hwnd := this.Gui.Hwnd
        m := this.Material
        type := (m = "mica") ? 2 : (m = "acrylic") ? 3 : (m = "tabbed") ? 4 : 1
        hr := AxGlassDwm(hwnd, 38, type)                         ; DWMWA_SYSTEMBACKDROP_TYPE, build 22621+
        said := "type " type " -> " AxGlassHr(hr)
        if (hr != 0 && m = "mica") {                             ; build 22000 had only an on/off Mica
            hr := AxGlassDwm(hwnd, 1029, 1)
            said .= "; DWMWA_MICA_EFFECT -> " AxGlassHr(hr)
        }
        this.Said["system backdrop"] := said
        this._GlassFrame()
    }

    ; The whole client as frame, or the black under the page is not read as
    ; alpha 0 and shows as black: a window that is not layered is only
    ; see-through inside its frame.
    _GlassFrame() {
        m := Buffer(16)
        NumPut("Int", -1, "Int", -1, "Int", -1, "Int", -1, m)
        try DllCall("dwmapi\DwmExtendFrameIntoClientArea", "Ptr", this.Gui.Hwnd, "Ptr", m)
    }

    ; after SetMaterial("none"), once the page has repainted off the key
    _GlassOffLate() {
        if (this.Material != "none")
            return
        this._GlassMaterial()
        AxSys.Shadow(this.Gui.Hwnd)
    }

    ; the backdrop's dark look, set once (each change is a transition DWM animates)
    _GlassDark() {
        if (this._dark == 1)
            return
        this._dark := 1
        try AxGlassDwm(this.Gui.Hwnd, 20, 1)
    }

    ; the key in the host windows' class brushes: a gap a resize has not
    ; painted yet is glass too, not a black or white bar
    _GlassBrushes() {
        static brush := 0
        if !brush {
            rgb := Integer("0x" GlassGui.Key)
            brush := DllCall("CreateSolidBrush", "UInt", ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | (rgb >> 16), "Ptr")
        }
        for h in this._subclassed
            DllCall("SetClassLongPtr", "Ptr", h, "Int", -10, "Ptr", brush)
    }

    ; The page on the key. The layer under the content is the sheet's own
    ; background, so every control on it looks exactly as it does without
    ; glass; "onglass" takes the layer away.
    _GlassCss() {
        k := GlassGui.Key
        bd := AxGui.Prototype.ThemeBack.Call(this, "dark")
        return "html{background:transparent!important}"
            . "body{background:#" k "!important}"
            . "#titlebar,#sidebar{background:transparent!important}"
            . "#content{background:#" bd "!important;border-radius:8px;border:1px solid rgba(255,255,255,.07)}"
            . "body.onglass #content{background:transparent!important;border-color:transparent}"
            ; a transparent box with rounded corners still anti-aliases them,
            ; a level off the key: round a nav item only while it is lit
            . ".nav-item{border-radius:0}.nav-item:hover,.nav-item.active,.nav-item.axglass-hover{border-radius:4px}"
            . ".nav-item.axglass-hover,.winbtn.axglass-hover{background:rgba(255,255,255,.0605)}"
            . "#btnClose.axglass-hover{background:#c42b1c!important;color:#fff!important}"
    }

    ; The hover the page cannot see (top): elementFromPoint, up to a nav item
    ; or a window button, and a class on it. The page drops the class itself
    ; as soon as it hears the mouse anywhere outside that element.
    _GlassHoverJs() {
        js := "window.axGlassHover=function(x,y){var e=x<0?null:document.elementFromPoint(x,y),h=null;"
            . "while(e&&e.nodeType===1&&e!==document.body){var c=e.className;"
            . "if(typeof c==='string'&&/(^|\s)(nav-item|winbtn)(\s|$)/.test(c)){h=e;break}e=e.parentNode}"
            . "var o=window.__axgh;if(h!==o){"
            . "if(o)o.className=o.className.replace(/(^|\s)axglass-hover/g,'');"
            . "if(h)h.className+=' axglass-hover';window.__axgh=h}return h?1:0};"
            . "document.addEventListener('mousemove',function(ev){var o=window.__axgh;"
            . "if(o&&!o.contains(ev.target))window.axGlassHover(-1,-1)},false);"
        try {
            s := this.Doc.createElement("script")
            s.text := js
            head := this.Doc.getElementsByTagName("head").item(0)
            head.appendChild(s), head.removeChild(s)
        }
    }

    ; ------------------------------------------------------- glass pixels
    ; WM_NCHITTEST on our own window: only ever for a glass pixel of the page.
    ; Edges size, the title bar drags, the rest is client (handed on below).
    _GlassHit(l) {
        x := l & 0xFFFF, y := (l >> 16) & 0xFFFF
        x := (x > 0x7FFF) ? x - 0x10000 : x, y := (y > 0x7FFF) ? y - 0x10000 : y
        WinGetPos(&wx, &wy, &ww, &wh, this.Gui)
        x -= wx, y -= wy
        k := this._GlassScale()
        if (this.Resizable && !this.IsMaximized()) {
            e := Round(5 * k), c := Round(8 * k)
            if (y < c && x < c)
                return 13                                        ; HTTOPLEFT
            if (y < c && x >= ww - c)
                return 14                                        ; HTTOPRIGHT
            if (y >= wh - c && x < c)
                return 16                                        ; HTBOTTOMLEFT
            if (y >= wh - c && x >= ww - c)
                return 17                                        ; HTBOTTOMRIGHT
            if (y < e)
                return 12                                        ; HTTOP
            if (y >= wh - e)
                return 15                                        ; HTBOTTOM
            if (x < e)
                return 10                                        ; HTLEFT
            if (x >= ww - e)
                return 11                                        ; HTRIGHT
        }
        if (y < Round(32 * k) && x < ww - Round(138 * k))       ; the caption, short of the three buttons
            return 2                                             ; HTCAPTION
        return 1                                                 ; HTCLIENT
    }

    ; page px -> device px, the ratio AxWindow._IconMenu uses
    _GlassScale() {
        try {
            cw := this.Doc.documentElement.clientWidth
            rc := Buffer(16), DllCall("GetClientRect", "Ptr", this.Ax.Hwnd, "Ptr", rc)
            if cw
                return NumGet(rc, 8, "Int") / cw
        }
        return A_ScreenDPI / 96
    }

    ; The mouse on a glass pixel of the client. A move lights what is under
    ; it; a button or the wheel is posted to the page at the same point --
    ; the page takes the capture on the press, so the release and any drag go
    ; straight to it after that.
    _GlassMouse(w, l, msg, hwnd) {
        if (this.Material = "none" || !this.HasOwnProp("Gui") || hwnd != this.Gui.Hwnd)
            return
        ie := this._IeHwnd()
        if !ie
            return
        if (msg = 0x2A3 || msg = 0xA0) {                         ; WM_MOUSELEAVE, or onto the caption / an edge
            if (msg = 0x2A3)
                this._tracking := false
            if this._lit
                try this._lit := this.Doc.parentWindow.axGlassHover(-1, -1)
            return
        }
        if (msg = 0x20A || msg = 0x20E) {                        ; the wheel: screen coordinates already
            DllCall("PostMessage", "Ptr", ie, "UInt", msg, "Ptr", w, "Ptr", l)
            return 0
        }
        x := l & 0xFFFF, y := (l >> 16) & 0xFFFF
        pt := Buffer(8)
        NumPut("Int", (x > 0x7FFF) ? x - 0x10000 : x, "Int", (y > 0x7FFF) ? y - 0x10000 : y, pt)
        DllCall("MapWindowPoints", "Ptr", hwnd, "Ptr", ie, "Ptr", pt, "UInt", 1)
        if (msg = 0x200) {                                       ; WM_MOUSEMOVE
            if !this._tracking {
                tme := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
                NumPut("UInt", tme.Size, "UInt", 2, tme)         ; TME_LEAVE
                NumPut("Ptr", hwnd, tme, 8)
                this._tracking := DllCall("TrackMouseEvent", "Ptr", tme)
            }
            k := this._GlassScale()
            try this._lit := this.Doc.parentWindow.axGlassHover(NumGet(pt, 0, "Int") / k, NumGet(pt, 4, "Int") / k)
            return
        }
        DllCall("PostMessage", "Ptr", ie, "UInt", msg, "Ptr", w,
                "Ptr", ((NumGet(pt, 4, "Int") & 0xFFFF) << 16) | (NumGet(pt, 0, "Int") & 0xFFFF))
        return 0
    }

    _IeHwnd() {
        if (this.HasOwnProp("_ie") && DllCall("IsWindow", "Ptr", this._ie))
            return this._ie
        this._ie := 0
        try for h in WinGetControlsHwnd(this.Gui)
            if (WinGetClass(h) = "Internet Explorer_Server")
                return this._ie := h
        return 0
    }
}

AxGlassDwm(hwnd, attr, value) {
    v := Buffer(4), NumPut("UInt", value, v)
    return DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", attr, "Ptr", v, "UInt", 4, "Int")
}
AxGlassHr(hr) => (hr = 0) ? "S_OK" : Format("0x{:08X}", hr & 0xFFFFFFFF)


; ─────────────────────────────────────────────────────────────────────────────
;  The demo
; ─────────────────────────────────────────────────────────────────────────────

g := GlassGui({
    Title:     "Glass (Experiment)",
    Width:     1000,
    Height:    700,
    MinWidth:  700,
    MinHeight: 480,
    Theme:     "dark",
    ; everything on the glass is painted solid, never with opacity (see top)
    Css:       "#sidebar{position:relative}"
             . "#glLive{position:absolute;left:14px;right:14px;bottom:14px;font-size:12px;line-height:18px}"
             . "#glLive .row1{display:flex;align-items:center}"
             . "#glClock{font:600 20px Consolas,monospace;margin-left:10px}"
             . ".glSpin{display:inline-block;width:18px;height:18px;border-radius:50%;border:2px solid #555558;"
             . "border-top-color:#60cdff;animation:glSpin 1s linear infinite}"
             . "@keyframes glSpin{to{transform:rotate(360deg)}}"
             . ".glDim{color:#b8b8b8}"
             . "#glDiag div{padding:2px 0;font-size:12px}#glDiag b{font-weight:600;display:inline-block;min-width:130px}"
             . ".glBar{height:6px;border-radius:3px;background:rgba(128,128,128,.25);overflow:hidden;position:relative}"
             . ".glBar i{position:absolute;top:0;bottom:0;width:30%;border-radius:3px;background:#60cdff;animation:glSlide 1.4s ease-in-out infinite}"
             . "@keyframes glSlide{0%{left:-30%}100%{left:100%}}"
             . ".glType h1{margin:0 0 6px}.glType p{max-width:560px}"
             . ".glAccent{color:#60cdff}"
             . ".glRule{height:1px;background:#6b6b6b;margin:14px 0}"
})

Sheets := [["win11", "Windows 11"], ["win365", "Microsoft 365"], ["precision", "Precision"],
           ["aurora", "Aurora"], ["cozy", "Cozy"], ["cyber", "Cyber"], ["inset", "Inset"],
           ["instrument", "Instrument"], ["brutalist", "Brutalist"]]


; -- 1. the switches --------------------------------------------------------

g.AddPage("glass", "Backdrop", "E771")

g.AddInfoBar('Title="What you are looking at"',
    "The title bar, the nav rail and the gap round the page are one colour, keyed away: Windows fills "
    . "those pixels with the backdrop. Everything else is solid — a pixel is glass or it is not.")

g.AddRow("Icon=E771", "Material", "Mica tints from the wallpaper; Acrylic blurs what is behind the window")
g.AddSegmented("vMaterial Choose4", "none:Off|mica:Mica|tabbed:Mica Alt|acrylic:Acrylic")
    .OnChange((c, v, *) => (g.SetMaterial(v), Diag()))
g.Use()

g.AddRow("Icon=E8A1", "Content on glass", "Off: the page sits on a solid layer, as in Settings. On: every control straight on the backdrop")
g.AddSwitch("vOnGlass").OnChange((c, v, *) => g.SetOnGlass(v))
g.Use()

g.AddRow("Icon=E790", "Tint", "A colour added over the glass, any material: it can only lighten")
g.AddSegmented("vTint Choose1", "none:None|accent:Accent|white:White|warm:Warm|rose:Rose|green:Green")
    .OnChange((c, v, *) => (g.SetTint(v), Diag()))
g.Use()

g.AddRow("Icon=E706", "Tint strength", "How much of it")
g.AddSlider('vGlassStrength Min=0 Max=100 Step=5 w220 Suffix="%"', g.GlassTintStrength)
    .OnChange((c, v, *) => (g.SetTint(, Round(v)), Diag()))
g.Use()

sheetList := ""
for s in Sheets
    sheetList .= (sheetList = "" ? "" : "|") s[1] ":" s[2]
g.AddRow("Icon=E8D2", "Stylesheet", "The layer under the page takes each sheet's own background")
g.AddDDL("vSheet w180 Choose1", sheetList).OnChange((c, v, *) => (g.SetStylesheet(v), Diag()))
g.Use()

g.AddText("Caption", "What Windows said")
g.AddHtml("", '<div id="glDiag"></div>')


; -- 2. controls --------------------------------------------------------------

g.AddPage("controls", "Controls", "E80A")

g.AddText("Caption", "Buttons")
g.AddButton("Accent", "Accent")
g.AddButton("x+8", "Standard")
g.AddButton("x+8 Subtle", "Subtle")
g.AddButton("x+8 Danger", "Danger")
g.AddButton("vbtnDlg x+24", "Open a dialog").OnClick((*) => g.Dialog(
    "A dialog dims the whole page, glass included: the dimming is paint, so it is solid.",
    "On the glass", ["OK", "Cancel"]))
g.AddLink("x+16", "A link")

g.AddText("Caption", "Choices")
g.AddSwitch("vsw1 Checked", "A switch")
g.AddCheckBox("x+24 Checked", "A check box")
g.AddRadio("x+24 Choose1", "a:One|b:Two|c:Three")
g.AddSegmented("Choose2", "day:Day|week:Week|month:Month")

g.AddText("Caption", "Values")
g.AddSlider('w240 Suffix="%"', 60)
g.AddProgress("x+24 w200", 45)
g.AddNumber("x+24 w110 Min=0 Max=10", 3)

g.AddText("Caption", "Text")
g.AddEdit('w260 Placeholder="Type here"', "")
g.AddPassword("x+8 w180", "hunter2")
g.AddDDL("x+8 w160 Choose1", "one:First|two:Second|three:Third")

g.AddText("Caption", "Labels")
g.AddChip("", "A chip")
g.AddChip("x+8", "Another")
g.AddBadge("x+16 Kind=success", "Done")
g.AddBadge("x+8 Kind=warning", "Careful")
g.AddBadge("x+8 Kind=error", "Failed")
g.AddInfoBar('Kind=success Title="Saved."', "An info bar, on whatever is under it.")
g.AddInfoBar('Kind=warning Title="Heads up."', "Its colours are paint: on the glass it is a solid box.")

g.AddText("Caption", "A list")
g.AddListBox("w300 Choose2", "a:Apples|b:Bananas|c:Cherries|d:Dates")


; -- 3. motion ----------------------------------------------------------------

g.AddPage("motion", "Motion", "E768")

g.AddInfoBar('Title="Keep an eye on the nav rail."',
    "The clock, the spinner and the frame rate at the bottom left sit on the glass. If they stop until "
    . "the mouse moves, the layered window is not picking up the page's repaints.")

g.AddRow("Icon=E768", "Animate from AutoHotkey", "Sixty writes a second into the page: a bar and a counter")
g.AddSwitch("vAnim").OnChange((c, v, *) => SetTimer(Tick, v ? 16 : 0))
g.Use()
g.AddProgress("vpbAnim Fill", 0)
g.AddText("vtxAnim Hint", "0 updates")

g.AddText("Caption", "A CSS animation")
g.AddHtml("", '<div class="glBar"><i></i></div>')


; -- 4. type ------------------------------------------------------------------

g.AddPage("type", "Type", "E8D2")

g.AddInfoBar('Title="Turn on Content on glass for this page."',
    "Then the text below is drawn straight on the backdrop: each letter's anti-aliased edge blends into the "
    . "key colour, not into the glass.")

g.AddHtml("", '<div class="glType">'
    . '<h1>Glass, one bit deep</h1>'
    . '<p>Body text at 14px. The quick brown fox jumps over the lazy dog, 0123456789.</p>'
    . '<p class="caption">A caption at 12px, at the lower contrast the sheet gives it.</p>'
    . '<p class="glAccent"><b>Accent colour, bold.</b> And a light weight, <span style="font-weight:300">like this</span>.</p>'
    . '<div class="glRule"></div>'
    . '<svg width="320" height="90"><circle cx="45" cy="45" r="36" fill="#60cdff"/>'
    . '<circle cx="130" cy="45" r="36" fill="none" stroke="#e05252" stroke-width="3"/>'
    . '<rect x="190" y="12" width="110" height="66" rx="14" fill="rgba(255,255,255,.5)"/></svg>'
    . '<p class="caption">Solid, outlined and half-transparent shapes: the last one is paint over the key, so it is solid too.</p>'
    . '</div>')


; ─────────────────────────────────────────────────────────────────────────────
;  Start
; ─────────────────────────────────────────────────────────────────────────────

g.Show()
LiveBlock()
Diag()
SetTimer(Clock, 1000)
Clock()


; The live corner of the nav rail, on the glass. The frame rate is the page's
; own requestAnimationFrame count: it is what the page thinks it is drawing.
LiveBlock() {
    global g
    try g.Doc.getElementById("sidebar").insertAdjacentHTML("beforeEnd",
        '<div id="glLive"><div class="row1"><span class="glSpin"></span><span id="glClock">--:--:--</span></div>'
        . '<div id="glFps" class="glDim">&ndash; fps</div></div>')
    js := "(function(){var el=document.getElementById('glFps'),n=0,t=new Date().getTime();"
        . "function f(){n++;var now=new Date().getTime();if(now-t>=500){el.innerHTML=Math.round(n*1000/(now-t))+' fps';"
        . "n=0;t=now}window.requestAnimationFrame(f)}window.requestAnimationFrame(f)})();"
    try {
        s := g.Doc.createElement("script")
        s.text := js
        head := g.Doc.getElementsByTagName("head").item(0)
        head.appendChild(s), head.removeChild(s)
    }
}

Clock() {
    global g
    try g.Html("glClock", FormatTime(, "HH:mm:ss"))
}

Tick() {
    global g
    static n := 0
    n++
    try {
        g.Ctl("pbAnim").Value := Mod(n, 101)
        g.Text("txAnim", n " updates")
    }
}

; What each call came back with, and the things the demo cannot know for you
Diag() {
    global g
    gpu := "unset (CPU)"
    try gpu := RegRead("HKCU\Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_GPU_RENDERING",
                       StrSplit(A_IsCompiled ? A_ScriptFullPath : A_AhkPath, "\")[-1]) ? "on (GPU)" : "off (CPU)"
    build := StrSplit(A_OSVersion, ".")
    b := build.Length >= 3 ? Integer(build[3]) : 0
    rows := [["Windows", A_OSVersion (b >= 22621 ? " — all four system backdrops" : b >= 22000 ? " — Mica only (build 22000)" : " — no system backdrop: Off only")],
             ["Material", g.Material],
             ["System backdrop", g.Said.Has("system backdrop") ? g.Said["system backdrop"] : "–"],
             ["Key", g.Said.Has("page key") ? g.Said["page key"] : "–"],
             ["Page drawing", gpu],
             ["Inactive", "Mica and Acrylic go flat when this window loses focus: Windows' rule"]]
    h := ""
    for r in rows
        h .= "<div><b>" AxWindow._Esc(r[1]) "</b>" AxWindow._Esc(r[2]) "</div>"
    try g.Html("glDiag", h)
}
