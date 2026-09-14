#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
#Include %A_LineFile%\..\..\ScreenPick\AxScreenPick.ahk
; single-file exe: embed this component's stylesheet (harmless uncompiled).
; The main script must set U_AxLib, exactly as lib\AxAssets.ahk documents.
;@Ahk2Exe-AddResource %U_AxLib%\components\ColorPicker\AxColorPicker.css, AX_COMPONENTS_COLORPICKER_AXCOLORPICKER_CSS

; =============================================================================
;  AxColorPicker — hue ring, saturation/value square, live preview.
;
;  A rich component, so it comes at four levels; pick the one that fits.
;
;    hex := AxColorPicker.Show({Current: "#333333"})   standalone modal window
;    hex := g.PickColor({Current: g.Accent})           ... owned by a window
;    g.AddColorButton("vAccent", "#0078ff")            swatch that opens it
;    g.AddColorPicker("vBig Size=300", "#0078ff")      the whole thing inline
;
;  ------------------------------------------------------------------ layout
;  Pass a Current colour and the top splits into two preview panels, Current
;  on the left and New on the right. Leave it out and the New panel spans the
;  whole width instead. Either way the wheel's disc is painted over the lower
;  half of the panels, which is what carves the concave bite out of them.
;
;  Inside the ring: the saturation/value square, a vertical Value track down
;  its left and a horizontal Saturation track underneath. The tracks mirror
;  the square's two axes, so either can be dragged on its own for a fine
;  adjustment without disturbing the other.
;
;  ----------------------------------------------------------------- options
;    Value          "#0078ff"   the colour being edited
;    Current        "#333333"   the colour being replaced; "" = single preview
;    Size           280         wheel diameter in CSS px (everything scales)
;    Fields         true        the R / G / B / Hex row
;    Swatches       array of hex chips, or false
;    Recent         true        a second row of recently chosen colours.
;                               The list is AxColorPicker.Recent, a plain
;                               Array every picker in the process shares — read
;                               or replace it to persist the list yourself.
;                               Pass an Array to show that one instead.
;    Eyedropper     true        the pipette on the New panel
;    CurrentAction  "pick"      clicking Current: "pick" from screen |
;                               "revert" to it | "none"
;    Labels         {Current, New, R, G, B, Hex}
;  Dialog only:
;    Title          "Pick a colour"
;    Heading        the big line inside the page; "" removes it
;    Icon           "E790" (a Fluent palette glyph). "auto" borrows the owner
;                   process's icon; "shell32.dll,13" or "imageres.dll,-109"
;                   extract one; "logo.png" or a data: URI use an image;
;                   "" or "none" leaves the title bar bare.
;    Buttons        ["Cancel", "OK"]     Owner, Theme, Accent, Width, Height
; =============================================================================
class AxColorPicker {
    static Pi := 3.141592653589793
    static _reg := AxColorPicker._Install()

    ; ------------------------------------------------------------ plug-in
    static _Install() {
        rec := AxRich.Register("ColorPicker", "components\ColorPicker\AxColorPicker.css", (*) => (
            AxRich.AddMethod("AddColorPicker", (c, o := "", v := "") => AxColorPicker._AddPicker(c, o, v)),
            AxRich.AddMethod("AddColorButton", (c, o := "", v := "") => AxColorPicker._AddButton(c, o, v)),
            AxRich.WindowMethod("PickColor", (w, o := "") => AxColorPicker.Show(AxColorPicker._Owned(w, o))),
            AxWindow.RegisterValue("colorpicker",
                (w, el) => AxWindow._Attr(el, "data-value"),
                (w, el, v) => AxColorPicker._SetVia(w, el, v)),
            AxWindow.RegisterValue("colorbutton",
                (w, el) => AxWindow._Attr(el, "data-value"),
                (w, el, v) => AxColorPicker._SetVia(w, el, v))))
        return rec
    }
    static _SetVia(win, el, v) {
        c := AxRich.At(win, el.id)
        if IsObject(c)
            c.Value := v
        else
            el.setAttribute("data-value", v)
    }
    static _Owned(win, opts) {
        o := {Owner: AxRich.Owner(win)}
        if IsObject(opts)
            for k, v in opts.OwnProps()
                o.%k% := v
        return o
    }

    ; ----------------------------------------------------------- geometry
    ; Everything derives from the wheel diameter, so Size is the only knob.
    static Geometry(size) {
        ring := Round(size * 0.08)
        gap  := Round(size * 0.0333)
        content := Floor((size - 2 * (ring + gap)) / 1.41421356) - 2      ; square inscribed in the ring
        bar := Max(10, Round(size * 0.042))
        pad := Max(10, Round(size * 0.042))
        sq  := content - bar - pad
        l   := Round((size - content) / 2)
        return {Size: size, Ring: ring, Gap: gap, Bar: bar, Pad: pad, Sq: sq,
                L: l, Content: content, R: (size - ring) / 2, C: size / 2}
    }
    static _Pt(c, r, deg) {
        rad := deg * AxColorPicker.Pi / 180
        return {X: Round(c + r * Cos(rad), 2), Y: Round(c - r * Sin(rad), 2)}   ; y flipped: hue runs anticlockwise
    }
    ; The hue ring as inline SVG: one stroked arc per segment, each carrying a
    ; gradient between its two hues. Trident has no conic-gradient, and 72
    ; segments are far past the point where the joins are visible.
    static RingSvg(id, size, ring, segments := 72) {
        c := size / 2, r := (size - ring) / 2, step := 360 / segments
        defs := "", arcs := ""
        loop segments {
            h0 := (A_Index - 1) * step, h1 := A_Index * step
            p0 := AxColorPicker._Pt(c, r, h0), p1 := AxColorPicker._Pt(c, r, h1)
            pe := AxColorPicker._Pt(c, r, h1 + step * 0.08)               ; overlap the next arc: no seams
            gid := id "_hg" A_Index
            defs .= '<linearGradient id="' gid '" gradientUnits="userSpaceOnUse"'
                 .  ' x1="' p0.X '" y1="' p0.Y '" x2="' p1.X '" y2="' p1.Y '">'
                 .  '<stop offset="0" stop-color="' AxSys.HsvHex(h0, 1, 1) '"/>'
                 .  '<stop offset="1" stop-color="' AxSys.HsvHex(h1, 1, 1) '"/></linearGradient>'
            arcs .= '<path d="M ' p0.X ' ' p0.Y ' A ' Round(r, 2) ' ' Round(r, 2) ' 0 0 0 ' pe.X ' ' pe.Y '"'
                 .  ' fill="none" stroke="url(#' gid ')" stroke-width="' ring '"/>'
        }
        edge := '<circle cx="' c '" cy="' c '" r="' Round(r + ring / 2 - 0.5, 2) '" fill="none"'
              . ' stroke="#000000" stroke-opacity=".38" stroke-width="1"/>'
              . '<circle cx="' c '" cy="' c '" r="' Round(r - ring / 2 + 0.5, 2) '" fill="none"'
              . ' stroke="#000000" stroke-opacity=".38" stroke-width="1"/>'
        return '<svg class="axcp-ring" width="' size '" height="' size '" viewBox="0 0 ' size ' ' size '">'
             . '<defs>' defs '</defs>' arcs edge '</svg>'
    }

    ; --------------------------------------------------------------- markup
    ; Html(id, opts) is the whole component; drop it into any page (an AxGui
    ; AddHtml, or a hand-written HTML file) and bind it with AxColorPicker().
    static Html(id, opts := "") {
        o := (n, d := "") => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        lab := (n, d := "") => (IsObject(o("Labels", "")) && o("Labels", {}).HasOwnProp(n)) ? o("Labels", {}).%n% : d
        E := (x) => AxWindow._Esc(x)
        size := Integer(o("Size", 280))
        gm := AxColorPicker.Geometry(size)
        cur := Trim(String(o("Current", "")))
        val := Trim(String(o("Value", "#0078ff")))
        if !AxSys.HexToRgb(val).Ok
            val := "#0078ff"
        dual := (cur != "" && AxSys.HexToRgb(cur).Ok)
        topH := Integer(o("TopHeight", Round(size * 0.47)))
        over := Integer(o("Overlap", Round(topH * 0.52)))
        bleed := Max(8, Round(size * 0.035))
        eye := o("Eyedropper", true)
        act := StrLower(o("CurrentAction", "pick"))
        style := o("Style", ""), cls := o("Class", "")

        h := '<div class="axcp' (dual ? "" : " axcp-solo") (cls != "" ? " " E(cls) : "") '" id="' E(id) '"'
           . ' data-role="colorpicker" data-value="' E(val) '"' (style != "" ? ' style="' E(style) '"' : "") '>'
        ; --- preview panels
        h .= '<div class="axcp-top" style="height:' topH 'px">'
        if dual {
            h .= '<div class="axcp-sw axcp-cur' (act = "none" ? "" : " pickable") '" id="' E(id) '_cur"'
              .  ' style="background:' E(cur) '"'
              .  (act = "pick" ? ' data-tip="Click to pick a colour from the screen"'
                  : act = "revert" ? ' data-tip="Click to go back to this colour"' : "") '>'
              .  '<div class="axcp-cap">' E(lab("Current", "Current")) '</div>'
              .  '<div class="axcp-hexlbl" id="' E(id) '_curhex">' E(StrUpper(cur)) '</div></div>'
        }
        h .= '<div class="axcp-sw axcp-new" id="' E(id) '_new" style="background:' E(val) '">'
          .  (eye ? '<span class="axcp-eye ico" id="' E(id) '_eye" data-tip="Pick a colour from the screen">&#xEF3C;</span>' : "")
          .  '<div class="axcp-cap">' E(lab("New", "New")) '</div>'
          .  '<div class="axcp-hexlbl" id="' E(id) '_newhex">' E(StrUpper(val)) '</div></div>'
        h .= '</div>'
        ; --- wheel: the disc is what bites into the panels above
        sqL := gm.L + gm.Bar + gm.Pad
        h .= '<div class="axcp-wheel" id="' E(id) '_wheel" style="width:' size 'px;height:' size 'px;margin-top:-' over 'px">'
          .  '<div class="axcp-disc" id="' E(id) '_disc" style="left:-' bleed 'px;top:-' bleed 'px;'
          .      'width:' (size + bleed * 2) 'px;height:' (size + bleed * 2) 'px"></div>'
          .  AxColorPicker.RingSvg(id, size, gm.Ring)
          .  '<div class="axcp-track axcp-vbar" id="' E(id) '_vbar" style="left:' gm.L 'px;top:' gm.L 'px;'
          .      'width:' gm.Bar 'px;height:' gm.Sq 'px"></div>'
          .  '<div class="axcp-sq" id="' E(id) '_sq" style="left:' sqL 'px;top:' gm.L 'px;'
          .      'width:' gm.Sq 'px;height:' gm.Sq 'px"></div>'
          .  '<div class="axcp-track axcp-hbar" id="' E(id) '_hbar" style="left:' sqL 'px;'
          .      'top:' (gm.L + gm.Sq + gm.Pad) 'px;width:' gm.Sq 'px;height:' gm.Bar 'px"></div>'
          .  '<div class="axcp-knob" id="' E(id) '_hueknob"></div>'
          .  '<div class="axcp-knob" id="' E(id) '_sqknob"></div>'
          .  '<div class="axcp-knob" id="' E(id) '_vknob"></div>'
          .  '<div class="axcp-knob" id="' E(id) '_hknob"></div>'
          .  '</div>'
        ; --- numeric fields
        if o("Fields", true) {
            h .= '<div class="axcp-fields" id="' E(id) '_fields">'
            for f in [["r", lab("R", "R")], ["g", lab("G", "G")], ["b", lab("B", "B")]]
                h .= '<div class="axcp-f"><div class="axcp-flbl">' E(f[2]) '</div>'
                  .  '<div class="axcp-fbox" id="' E(id) '_box' f[1] '">'
                  .  '<input type="text" id="' E(id) '_' f[1] '" autocomplete="off"></div></div>'
            h .= '<div class="axcp-f wide"><div class="axcp-flbl">' E(lab("Hex", "Hex")) '</div>'
              .  '<div class="axcp-fbox" id="' E(id) '_boxhex">'
              .  '<input type="text" id="' E(id) '_hex" autocomplete="off"></div></div></div>'
        }
        ; --- swatch groups: the fixed palette, and the recently chosen row
        sw := o("Swatches", false)
        rec := o("Recent", false)
        if (!IsObject(rec) && rec)
            rec := AxColorPicker.Recent                       ; true means the shared list
        hasRec := IsObject(rec) && rec.Length
        if IsObject(sw)
            h .= AxColorPicker.SwatchGroup(id "_sw", lab("Swatches", "Standard colours"), sw, hasRec)
        if IsObject(rec)                                      ; empty renders hidden, ready to fill
            h .= AxColorPicker.SwatchGroup(id "_rc", lab("Recent", "Recent"), rec, true)
        return h '</div>'
    }
    static DefaultSwatches := ["#ffffff", "#c8c8c8", "#7a7574", "#000000", "#ffb900", "#f7630c",
                               "#e74856", "#e3008c", "#b146c2", "#8764b8", "#0078d4", "#60cdff",
                               "#00b7c3", "#00cc6a", "#10893e", "#498205"]
    ; Recently chosen colours, newest first — shared by every picker in the
    ; process. It is a plain Array, so a script that wants it to survive a
    ; restart just saves it and assigns it back:
    ;     AxColorPicker.Recent := StrSplit(IniRead(f, "ui", "recent", ""), ",")
    static Recent := []
    static RecentMax := 18
    ; Record a colour as used (deduped, newest first, capped at RecentMax).
    static PushRecent(hex) {
        c := AxSys.HexToRgb(hex)
        if !c.Ok
            return AxColorPicker.Recent
        hex := AxSys.RgbToHex(c.R, c.G, c.B)
        out := [hex]
        for v in AxColorPicker.Recent {
            if (StrUpper(v) != StrUpper(hex) && out.Length < AxColorPicker.RecentMax)
                out.Push(v)
        }
        AxColorPicker.Recent := out
        return out
    }

    ; One labelled row of clickable chips. `labelled` false drops the caption,
    ; which keeps a lone palette as compact as it used to be.
    static SwatchGroup(id, label, colors, labelled := true) {
        E := (x) => AxWindow._Esc(x)
        h := '<div class="axcp-swgroup' (colors.Length ? "" : " empty") '" id="' E(id) 'grp">'
        if labelled
            h .= '<span class="axcp-swlbl">' E(label) '</span>'
        h .= '<div class="axcp-swrow" id="' E(id) 'row">' AxColorPicker.ChipsHtml(id, colors) '</div>'
        return h '</div>'
    }
    static ChipsHtml(id, colors) {
        E := (x) => AxWindow._Esc(x)
        h := ""
        for i, c in colors
            h .= '<span class="axcp-chipc" id="' E(id) i '" data-c="' E(c) '"'
              .  ' style="background:' E(c) '" data-tip="' E(StrUpper(c)) '"></span>'
        return h
    }

    ; ------------------------------------------------------------ behaviour
    ; AxColorPicker(win, id, opts) binds a block of that markup in `win`.
    __New(win, id, opts := "") {
        this.W := win, this.Id := id
        this.Opts := IsObject(opts) ? opts : {}
        o := (n, d := "") => this.Opts.HasOwnProp(n) ? this.Opts.%n% : d
        this.Size := Integer(o("Size", 280))
        this.Gm := AxColorPicker.Geometry(this.Size)
        this.Fields := o("Fields", true)
        this.CurrentAction := StrLower(o("CurrentAction", "pick"))
        this.Cur := Trim(String(o("Current", "")))
        this._cbs := []
        this._rect := ""
        this._busy := false
        val := Trim(String(o("Value", "#0078ff")))
        c := AxSys.HexToRgb(AxSys.HexToRgb(val).Ok ? val : "#0078ff")
        hsv := AxSys.RgbToHsv(c.R, c.G, c.B)
        this.H := hsv.H, this.S := hsv.S, this.V := hsv.V
        this.Hex := val
        AxRich.Use(win, "ColorPicker")
        AxRich.Bind(win, id, this)
        this._Wire()
        this.SyncBackdrop()
        this.Sync(false)
    }
    _Wire() {
        w := this.W, id := this.Id
        w.On("mousedown", id "_wheel",   (el, ev) => this._RingDown(ev))
        w.On("mousedown", id "_hueknob", (el, ev) => this._RingDown(ev))
        w.On("mousedown", id "_sq",      (el, ev) => this._Grab("_sq", (x, y) => this._SqMove(x, y)))
        w.On("mousedown", id "_sqknob",  (el, ev) => this._Grab("_sq", (x, y) => this._SqMove(x, y)))
        w.On("mousedown", id "_vbar",    (el, ev) => this._Grab("_vbar", (x, y) => this._VMove(x, y)))
        w.On("mousedown", id "_vknob",   (el, ev) => this._Grab("_vbar", (x, y) => this._VMove(x, y)))
        w.On("mousedown", id "_hbar",    (el, ev) => this._Grab("_hbar", (x, y) => this._SMove(x, y)))
        w.On("mousedown", id "_hknob",   (el, ev) => this._Grab("_hbar", (x, y) => this._SMove(x, y)))
        w.On("click", id "_eye", (*) => this.PickFromScreen())
        if (this.Cur != "" && this.CurrentAction = "pick")
            w.On("click", id "_cur", (*) => this.PickFromScreen())
        else if (this.Cur != "" && this.CurrentAction = "revert")
            w.On("click", id "_cur", (*) => this.SetHex(this.Cur))
        if this.Fields {
            for f in ["r", "g", "b"] {
                w.On("keyup", id "_" f, (el, ev) => this._RgbEdit())
                w.On("change", id "_" f, (el, ev) => this._RgbEdit())
            }
            w.On("keyup", id "_hex", (el, ev) => this._HexEdit())
            w.On("change", id "_hex", (el, ev) => this._HexEdit())
        }
        sw := this.Opts.HasOwnProp("Swatches") ? this.Opts.Swatches : false
        if IsObject(sw)
            this._WireChips(id "_sw", sw)
        this.RefreshRecent()
    }
    _WireChips(prefix, colors) {
        for i, c in colors
            this.W.On("click", prefix i, this._SwatchFn(c))
    }
    _SwatchFn(hex) => (el, ev) => this.SetHex(hex)
    ; Re-render the recent row from the current list (it is shared and grows
    ; while the picker is open, so an inline one can call this whenever).
    RefreshRecent() {
        rec := this.Opts.HasOwnProp("Recent") ? this.Opts.Recent : false
        if (!IsObject(rec)) {
            if !rec
                return this
            rec := AxColorPicker.Recent
        }
        w := this.W, id := this.Id
        try {
            row := w.El(id "_rcrow")
            if !IsObject(row)
                return this
            row.innerHTML := AxColorPicker.ChipsHtml(id "_rc", rec)
            AxWindow._SetClass(w.El(id "_rcgrp"), "empty", !rec.Length)
            this._WireChips(id "_rc", rec)
        }
        return this
    }
    ; the disc has to match whatever the window paints behind it
    SyncBackdrop(color := "") {
        if (color = "")
            color := "#" LTrim(this.W.BackColor, "#")
        try this.W.Style(this.Id "_disc", "backgroundColor", color)
        return this
    }

    ; ----------------------------------------------------------- dragging
    _Grab(suffix, mover) {
        try {
            r := this.W.El(this.Id suffix).getBoundingClientRect()
            this._rect := {L: r.left, T: r.top, W: Max(1, r.right - r.left), H: Max(1, r.bottom - r.top)}
        } catch
            return
        this.W.PointerCapture(mover, mover)
    }
    _RingDown(ev) {
        try {
            r := this.W.El(this.Id "_wheel").getBoundingClientRect()
            cx := r.left + this.Gm.C, cy := r.top + this.Gm.C
            dx := ev.clientX - cx, dy := ev.clientY - cy
            d := Sqrt(dx * dx + dy * dy)
            band := this.Gm.Ring / 2 + 6
            if (d < this.Gm.R - band || d > this.Gm.R + band)
                return                                        ; the press missed the ring
            this._rect := {CX: cx, CY: cy}
        } catch
            return
        mv := (x, y) => this._HueMove(x, y)
        this.W.PointerCapture(mv, mv)
    }
    _HueMove(x, y) {
        r := this._rect
        if !IsObject(r) || !r.HasOwnProp("CX")
            return
        deg := AxSys.Atan2(r.CY - y, x - r.CX) * 180 / AxColorPicker.Pi
        this.H := Mod(Mod(deg, 360) + 360, 360)
        this.Sync()
    }
    _SqMove(x, y) {
        r := this._rect
        this.S := Min(1, Max(0, (x - r.L) / r.W))
        this.V := Min(1, Max(0, 1 - (y - r.T) / r.H))
        this.Sync()
    }
    _VMove(x, y) {
        r := this._rect
        this.V := Min(1, Max(0, 1 - (y - r.T) / r.H))
        this.Sync()
    }
    _SMove(x, y) {
        r := this._rect
        this.S := Min(1, Max(0, (x - r.L) / r.W))
        this.Sync()
    }

    ; ------------------------------------------------------------- fields
    _RgbEdit() {
        if this._busy
            return
        try {
            r := this._Num(this.Id "_r"), g := this._Num(this.Id "_g"), b := this._Num(this.Id "_b")
            this.SetHex(AxSys.RgbToHex(r, g, b))
        }
    }
    _Num(id) {
        v := this.W.El(id).value
        return Min(255, Max(0, IsNumber(Trim(v)) ? Round(Number(Trim(v))) : 0))
    }
    _HexEdit() {
        if this._busy
            return
        try {
            raw := Trim(this.W.El(this.Id "_hex").value)
            c := AxSys.HexToRgb(raw)
            AxWindow._SetClass(this.W.El(this.Id "_boxhex"), "bad", !c.Ok && raw != "")
            if c.Ok
                this.SetHex(AxSys.RgbToHex(c.R, c.G, c.B))
        }
    }

    ; -------------------------------------------------------------- state
    Value {
        get => this.Hex
        set => this.SetHex(value)
    }
    SetHex(hex, fire := true) {
        c := AxSys.HexToRgb(hex)
        if !c.Ok
            return this
        hsv := AxSys.RgbToHsv(c.R, c.G, c.B)
        if (hsv.S > 0.0005 && hsv.V > 0.0005)              ; grey carries no hue: keep the ring where it is
            this.H := hsv.H
        this.S := hsv.S, this.V := hsv.V
        this.Sync(fire)
        return this
    }
    ; Change the "Current" panel (and what CurrentAction: "revert" goes back to)
    SetCurrent(hex) {
        if !AxSys.HexToRgb(hex).Ok
            return this
        this.Cur := hex
        try {
            this.W.Style(this.Id "_cur", "backgroundColor", hex)
            this.W.Text(this.Id "_curhex", StrUpper(hex))
            this._Contrast(this.Id "_cur", hex)
        }
        return this
    }
    OnChange(fn) {
        this._cbs.Push(fn)
        return this
    }
    ; Hand the screen eyedropper the wheel; live-preview while it moves.
    PickFromScreen() {
        before := this.Hex
        got := AxScreenPick.Color({Owner: AxRich.Owner(this.W),
            OnMove: (hex, x, y) => this.SetHex(hex)})
        this.SetHex(got != "" ? got : before)
        return got
    }

    ; --------------------------------------------------------------- paint
    Sync(fire := true) {
        w := this.W, id := this.Id, gm := this.Gm
        hex := AxSys.HsvHex(this.H, this.S, this.V)
        this.Hex := hex
        pure := AxSys.HsvHex(this.H, 1, 1)
        sqL := gm.L + gm.Bar + gm.Pad
        this._busy := true
        try {
            w.Attr(id, "data-value", hex)
            w.Style(id "_new", "backgroundColor", hex)
            w.Text(id "_newhex", StrUpper(hex))
            this._Contrast(id "_new", hex)
            if (this.Cur != "")
                this._Contrast(id "_cur", this.Cur)
            ; hue knob on the ring
            p := AxColorPicker._Pt(gm.C, gm.R, this.H)
            this._Knob(id "_hueknob", p.X, p.Y, pure)
            ; saturation / value square
            sq := w.El(id "_sq")
            sq.style.backgroundColor := pure
            sq.style.backgroundImage := "linear-gradient(to top, #000000, rgba(0,0,0,0)),"
                                      . "linear-gradient(to right, #ffffff, rgba(255,255,255,0))"
            this._Knob(id "_sqknob", sqL + this.S * gm.Sq, gm.L + (1 - this.V) * gm.Sq, hex)
            ; the two axis tracks
            w.El(id "_vbar").style.backgroundImage :=
                "linear-gradient(to top, #000000, " AxSys.HsvHex(this.H, this.S, 1) ")"
            this._Knob(id "_vknob", gm.L + gm.Bar / 2, gm.L + (1 - this.V) * gm.Sq, hex)
            w.El(id "_hbar").style.backgroundImage :=
                "linear-gradient(to right, " AxSys.HsvHex(this.H, 0, this.V) ", " AxSys.HsvHex(this.H, 1, this.V) ")"
            this._Knob(id "_hknob", sqL + this.S * gm.Sq, gm.L + gm.Sq + gm.Pad + gm.Bar / 2, hex)
            if this.Fields
                this._SyncFields(hex)
        }
        this._busy := false
        if fire {
            for fn in this._cbs.Clone()
                try fn(hex, this)
            try w._FireValue(w.El(id), hex)          ; so OnValue / ctl.OnChange work too
        }
    }
    _Knob(id, x, y, color) {
        el := this.W.El(id)
        if !IsObject(el)
            return
        el.style.left := Round(x) "px", el.style.top := Round(y) "px"
        el.style.backgroundColor := color
    }
    _SyncFields(hex) {
        w := this.W, id := this.Id, c := AxSys.HexToRgb(hex)
        try act := w.Doc.activeElement.id
        catch
            act := ""
        for f, v in Map(id "_r", c.R, id "_g", c.G, id "_b", c.B, id "_hex", StrUpper(hex))
            if (act != f)
                try w.El(f).value := v
        try AxWindow._SetClass(w.El(id "_boxhex"), "bad", false)
    }
    ; a panel's text has to stay legible over whatever colour it carries
    _Contrast(id, hex) {
        el := this.W.El(id)
        if !IsObject(el)
            return
        light := AxSys.Luma(hex) > 0.58
        AxWindow._SetClass(el, "axcp-onlight", light)
        AxWindow._SetClass(el, "axcp-ondark", !light)
    }

    ; ============================================================ front ends
    ; Show(opts) -> "#RRGGBB", or "" if cancelled.
    static Show(opts := "") => AxColorPickerDialog(opts).ShowModal()
    ; Pick(current, opts) — the one-liner form.
    static Pick(current := "", opts := "") {
        o := {Current: current}
        if IsObject(opts)
            for k, v in opts.OwnProps()
                o.%k% := v
        return AxColorPicker.Show(o)
    }
    ; --- AxGui: the whole component inline on a page
    static _AddPicker(container, opts, value) {
        o := container._Opt(opts, "cp")
        cfg := AxColorPicker._Cfg(container, o, value)
        cfg.Recent := o.Flags.Has("recent")          ; inline stays compact unless asked
        cfg.Style := (o.W != "" ? "width:" o.W "px;" : "") (o.KV.Has("style") ? o.KV["style"] : "")
        ; with no explicit width it fills its line, so the preview panels, the
        ; fields and the swatches all line up with the container
        cfg.Class := ((o.W = "" || o.Flags.Has("fill")) ? "fill" : "") (o.KV.Has("class") ? " " o.KV["class"] : "")
        c := container._Reg(o, "ColorPicker", AxColorPicker.Html(o.Id, cfg))
        container.G.OnReady((w) => AxColorPicker(w, o.Id, cfg))
        return c
    }
    ; --- AxGui: the swatch button that opens the dialog
    static _AddButton(container, opts, value) {
        o := container._Opt(opts, "cb")
        cfg := AxColorPicker._Cfg(container, o, value)
        cfg.ShowHex := !o.Flags.Has("nohex")
        cfg.Wide := o.Flags.Has("wide")
        cfg.Title := container._Kv(o, "title", "Pick a colour")
        c := container._Reg(o, "ColorButton", AxColorButton.Html(o.Id, cfg, container._Common(o, "")))
        container.G.OnReady((w) => AxColorButton(w, o.Id, cfg))
        return c
    }
    static _Cfg(container, o, value) {
        cfg := {Value: value != "" ? value : container._Kv(o, "value", "#0078ff")}
        cfg.Size := Integer(container._Kv(o, "size", 280))
        cfg.Current := container._Kv(o, "current")
        cfg.CurrentAction := container._Kv(o, "currentaction", "pick")
        cfg.Fields := !o.Flags.Has("nofields")
        cfg.Eyedropper := !o.Flags.Has("noeyedropper")
        if o.Flags.Has("swatches")
            cfg.Swatches := AxColorPicker.DefaultSwatches
        if o.KV.Has("icon")
            cfg.Icon := o.KV["icon"]
        return cfg
    }
}

; =============================================================================
;  AxColorButton — the shortest way to let someone change a colour: a live
;  swatch that opens the picker on click, writes the result back into itself
;  and fires OnChange. The dialog gets the button's colour as Current, so the
;  split preview appears without the caller arranging anything.
; =============================================================================
class AxColorButton {
    static Html(id, opts := "", attrs := "") {
        o := (n, d := "") => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        E := (x) => AxWindow._Esc(x)
        val := Trim(String(o("Value", "#0078ff")))
        if !AxSys.HexToRgb(val).Ok
            val := "#0078ff"
        cls := "axcbtn" (o("ShowHex", true) ? "" : " nohex") (o("Wide", false) ? " wide" : "")
        ; attrs comes from AxGui's _Common (id / class / style / tip): merge the
        ; component class into whatever class it already carries, or write our
        ; own attributes when the markup is being generated by hand
        if (attrs != "") {
            n := 0
            a := RegExReplace(attrs, 'S)class="([^"]*)"', 'class="' cls ' $1"', &n)
            if !n
                a .= ' class="' cls '"'
        } else
            a := ' id="' E(id) '" class="' cls '"'
        return '<span' a ' data-role="colorbutton" data-value="' E(val) '">'
             . '<span class="axcbtn-chip" id="' E(id) '_chip" style="background:' E(val) '"></span>'
             . '<span class="axcbtn-hex" id="' E(id) '_hex">' E(StrUpper(val)) '</span></span>'
    }
    __New(win, id, opts := "") {
        this.W := win, this.Id := id
        this.Opts := IsObject(opts) ? opts : {}
        this.Hex := Trim(String(this._O("Value", "#0078ff")))
        this._cbs := [], this._pcbs := []
        AxRich.Use(win, "ColorPicker")
        AxRich.Bind(win, id, this)
        win.On("click", id, (*) => this.Open())
        this.Sync(false)
    }
    _O(n, d := "") => this.Opts.HasOwnProp(n) ? this.Opts.%n% : d
    Value {
        get => this.Hex
        set => this.SetHex(value)
    }
    SetHex(hex, fire := true) {
        c := AxSys.HexToRgb(hex)
        if !c.Ok
            return this
        v := AxSys.RgbToHex(c.R, c.G, c.B)
        ; a colour that did not move is not a change. Without this a handler
        ; that writes the colour it was just handed -- the usual "repaint the
        ; window, then show it on the swatch" shape -- would bounce forever.
        same := (v = this.Hex)
        this.Hex := v
        this.Sync(fire && !same)
        return this
    }
    OnChange(fn) {
        this._cbs.Push(fn)
        return this
    }
    ; OnPreview(fn) fires for every colour the picker passes through while it
    ; is open, so a window can repaint itself live. Cancelling calls it once
    ; more with the colour it started on, so nothing is left half-applied.
    OnPreview(fn) {
        this._pcbs.Push(fn)
        return this
    }
    _Preview(hex) {
        for fn in this._pcbs.Clone()
            try fn(hex, this)
    }
    ; Open the picker with this colour as Current, and take what comes back.
    Open() {
        o := {}
        for k, v in this.Opts.OwnProps()
            o.%k% := v
        o.Owner := AxRich.Owner(this.W)
        o.Current := this.Hex
        o.Value := this.Hex
        before := this.Hex
        if this._pcbs.Length
            o.OnChange := (hex, cp) => this._Preview(hex)
        got := AxColorPicker.Show(o)
        if (got != "")
            this.SetHex(got)
        else
            this._Preview(before)                   ; cancelled: put it back
        return got
    }
    Sync(fire := true) {
        w := this.W, id := this.Id
        try {
            w.Attr(id, "data-value", this.Hex)
            w.Style(id "_chip", "backgroundColor", this.Hex)
            w.Text(id "_hex", StrUpper(this.Hex))
        }
        if fire {
            for fn in this._cbs.Clone()
                try fn(this.Hex, this)
            try w._FireValue(w.El(id), this.Hex)
        }
    }
}

; =============================================================================
;  AxColorPickerDialog — the picker as a window of its own.
; =============================================================================
class AxColorPickerDialog extends AxRichDialog {
    _Build(defaults := "") {
        size := Integer(this.O("Size", 280))
        topH := Integer(this.O("TopHeight", Round(size * 0.47)))
        over := Round(topH * 0.52)
        heading := this.O("Heading", this.O("Title", "Pick a colour"))
        fields := this.O("Fields", true)
        sw := this.O("Swatches", AxColorPicker.DefaultSwatches)
        btns := this.O("Buttons", ["Cancel", "OK"])
        width := this.O("Width", Max(400, size + 160))
        ; height from the pieces the page actually renders: title bar, the
        ; content padding, the heading line, the component, and the footer
        ; (which is pinned, so it costs #content padding rather than flow)
        rec := this.O("Recent", true)
        if (!IsObject(rec) && rec)
            rec := AxColorPicker.Recent
        perRow := Max(1, (width - 44) // 32)                  ; 26px chip + 3px margins
        swRows := (IsObject(sw) && sw.Length) ? Ceil(sw.Length / perRow) : 0
        rcRows := (IsObject(rec) && rec.Length) ? Ceil(rec.Length / perRow) : 0
        swH := 0
        if swRows                                             ; label only when both rows show
            swH += swRows * 32 + (rcRows ? 32 : 14)
        if rcRows
            swH += rcRows * 32 + 32
        pickerH := topH + (size - over) + (fields ? 88 : 0) + swH
        footer := (IsObject(btns) && btns.Length) ? 80 : 24   ; padding-bottom .has-footer adds
        h := 32 + 6 + (heading != "" ? 72 : 0) + pickerH + 10 + footer + 4
        d := {Title: this.O("Title", "Pick a colour"),
              Width: width, Height: h,
              ; a Fluent palette glyph: stable across Windows versions, unlike
              ; shell32 icon indices. Icon: "shell32.dll,13", "imageres.dll,-109",
              ; "auto", "logo.png" and "" all work too.
              Icon: "E790"}
        if !this.Opts.HasOwnProp("Css")                 ; styles present in the first paint
            this.Opts.Css := AxRich.CssText("ColorPicker")
        return super._Build(d)
    }
    _Content(g) {
        heading := this.O("Heading", this.O("Title", "Pick a colour"))
        if (heading != "")
            g.AddHtml("", "<h1>" AxWindow._Esc(heading) "</h1>")
        cfg := {}
        for k in ["Value", "Current", "Size", "Fields", "Eyedropper", "CurrentAction",
                  "Labels", "Swatches", "Recent", "TopHeight", "Overlap"]
            if this.Opts.HasOwnProp(k)
                cfg.%k% := this.Opts.%k%
        if !cfg.HasOwnProp("Value")
            cfg.Value := this.O("Current", "#0078ff")
        if !cfg.HasOwnProp("Swatches")
            cfg.Swatches := AxColorPicker.DefaultSwatches
        if !cfg.HasOwnProp("Recent")
            cfg.Recent := true
        this._cfg := cfg
        g.AddHtml("vaxcpHost Fill", AxColorPicker.Html("axcp", cfg))
        this._Footer(g, this.O("Buttons", ["Cancel", "OK"]),
            (i, isDefault) => this._Finish(isDefault))
        g.On("keydown", "*", (el, ev) => (ev.keyCode = 13 ? this._Finish(true) : ""))
    }
    ; Accepting records the colour, so the next picker opens with it to hand.
    _Finish(accept) {
        if !accept
            return this.Done("")
        hex := this.CP.Hex
        r := this.O("Recent", true)
        if (IsObject(r) || r)
            AxColorPicker.PushRecent(hex)
        return this.Done(hex)
    }
    _Ready(g) {
        this.CP := AxColorPicker(g, "axcp", this._cfg)
        if this.Opts.HasOwnProp("OnChange")
            this.CP.OnChange(this.Opts.OnChange)
    }
}
