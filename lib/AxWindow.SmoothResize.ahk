#Requires AutoHotkey v2.0
; =============================================================================
;  AxWindow.SmoothResize.ahk — dragging the left or top edge without judder.
;
;      AxWindow(file, {SmoothResize: false})      ; opt out (on by default)
;
;  Dragging the right or bottom edge is smooth in any Windows app: the
;  window's origin stays put. Dragging the left or top edge moves the origin
;  as well, and DWM shows the moved window with its old picture -- pinned to
;  the old top-left corner -- before the page has drawn the new one, so
;  everything anchored to the far side shakes back and forth. No WM_NCCALCSIZE
;  answer, paint order or DwmFlush fixes that part; it happens in DWM.
;
;  So the window never moves during such a drag:
;
;    start  it grows ONCE to cover every place the drag can reach (to the
;           edge of the monitor's work area). Its old pixels stay where they
;           are on screen (WM_NCCALCSIZE valid rectangles) and the browser
;           moves along with them, so nothing seen changes.
;    drag   only the browser moves and resizes, inside a window that stands
;           still, its pixels not copied (SWP_NOCOPYBITS): the side not being
;           dragged stays exactly where it is, as with a bottom-right drag.
;    end    the window shrinks to what is seen, pixels kept in place again.
;
;  What lies outside the visible part while the window is grown must be see-
;  through, which is why the window is colour-keyed for good (set up once,
;  when the page is ready: switching it at the start of a drag flickers):
;  the window's own background is the key colour, and only ever shows while a
;  drag is on. For the same reason Windows' border is swapped, for good, for
;  one drawn on the page, with the rounded corners cut out in the key colour.
;
;  Windows' shadow belongs to the real window -- the grown one -- so for the
;  drag the window's frame style and rounding are switched off (that takes
;  both) and a second, framed window under the visible part carries the
;  shadow and the smooth corners instead (AxResizeHost).
;
;  The right and bottom edges alone are left to Windows. A window the script
;  made layered itself (a colour key of its own, Opacity) is left alone too.
; =============================================================================
class AxWindowSmoothResize {
    static SrKey := "010203"            ; the colour key: never painted by the page

    ; once the page is up: what a drag needs, set up for good
    _SrSetup() {
        if (this._srOn || !this.SmoothResize || !this.Resizable || this.Closing)
            return
        hw := this.Gui.Hwnd
        ex := DllCall("GetWindowLongPtr", "Ptr", hw, "Int", -20, "Ptr")
        if (ex & 0x80000)                                    ; layered by the script: not ours to change
            return
        sty := DllCall("GetWindowLongPtr", "Ptr", hw, "Int", -16, "Ptr")
        DllCall("SetWindowLongPtr", "Ptr", hw, "Int", -16, "Ptr", sty | 0x02000000)   ; WS_CLIPCHILDREN: the Gui never paints over the page
        DllCall("SetWindowLongPtr", "Ptr", hw, "Int", -20, "Ptr", ex | 0x80000)      ; WS_EX_LAYERED
        DllCall("SetLayeredWindowAttributes", "Ptr", hw, "UInt", AxSys.ColorRef(AxWindowSmoothResize.SrKey), "UChar", 0, "UInt", 1)   ; LWA_COLORKEY
        try this.Gui.BackColor := AxWindowSmoothResize.SrKey
        this._srOn := true
        this._SrFrame()
        this._UpdateBorder()
    }
    ; the border and the corner cut-outs, drawn on the page (idempotent: a
    ; page that rebuilt its body gets them back)
    _SrFrame() {
        doc := this.Doc
        if !IsObject(doc) || IsObject(doc.getElementById("axSrFrame"))
            return
        rad := (this.RoundCorners && VerCompare(A_OSVersion, "10.0.22000") >= 0) ? "8px" : "0"
        try {
            el := doc.createElement("div")
            el.id := "axSrFrame"
            el.style.cssText := "position:fixed;left:0;top:0;right:0;bottom:0;border:1px solid transparent;border-radius:" rad
                             .  ";pointer-events:none;z-index:2147483647"
            doc.body.appendChild(el)
            ; a hard-edged circle cut-out per corner, in the key colour: see-
            ; through, so the corners stay round while Windows' rounding is off
            if (rad != "0")
                for c in [["left:0;top:0", "100% 100%"], ["right:0;top:0", "0 100%"], ["left:0;bottom:0", "100% 0"], ["right:0;bottom:0", "0 0"]] {
                    m := doc.createElement("div")
                    m.className := "axSrCorner"
                    m.style.cssText := "position:fixed;" c[1] ";width:" rad ";height:" rad ";pointer-events:none;z-index:2147483647;"
                                    .  "background:radial-gradient(circle " rad " at " c[2] ",transparent " rad ",#" AxWindowSmoothResize.SrKey " " rad ")"
                    doc.body.appendChild(m)
                }
            if !IsObject(doc.getElementById("axSrStyle")) {
                s := doc.createElement("style")
                s.id := "axSrStyle"
                s.appendChild(doc.createTextNode("body.maximized #axSrFrame,body.maximized .axSrCorner{display:none}"))
                doc.getElementsByTagName("head").item(0).appendChild(s)
            }
        }
        this._srBorderCss := ""
    }
    ; the page-drawn border in the colour BorderColor / SnapBorder ask for
    _SrBorder(color) {
        css := (color = "" || color = "none") ? "transparent"
             : (color = "default") ? AxWindowSmoothResize._SrDefaultBorder() : "#" LTrim(color, "#")
        if (css = this._srBorderCss)
            return
        try {
            this.Doc.getElementById("axSrFrame").style.borderColor := css
            this._srBorderCss := css
        }
    }
    ; what Windows 11 draws: the accent with "Show accent colour on title bars
    ; and window borders" on, a soft grey otherwise
    static _SrDefaultBorder() {
        try if RegRead("HKCU\Software\Microsoft\Windows\DWM", "ColorPrevalence") {
            DllCall("dwmapi\DwmGetColorizationColor", "UInt*", &argb := 0, "Int*", &opaque := 0)
            return Format("#{:06X}", argb & 0xFFFFFF)
        }
        return "rgba(128,128,128,0.45)"
    }

    ; Drag() hands the edges that move the window's origin here
    _SrDrag(edge) {
        static mine := Map("W", "L", "N", "T", "NW", "LT", "NE", "TR", "SW", "LB")
        e := StrUpper(edge)
        if (!this._srOn || this._srActive || !mine.Has(e) || this.IsMaximized())
            return false
        ; still colour-keyed as set up? A script that made the window see-through
        ; since (WinSetTransparent / WinSetTransColor) replaced it: Windows' drag
        key := 0, flags := 0
        if !DllCall("GetLayeredWindowAttributes", "Ptr", this.Gui.Hwnd, "UInt*", &key, "Ptr", 0, "UInt*", &flags)
            || flags != 1 || key != AxSys.ColorRef(AxWindowSmoothResize.SrKey)
            return false
        DllCall("user32\ReleaseCapture")                        ; the page's own
        SetTimer(ObjBindMethod(this, "_SrLoop", mine[e]), -1)
        return true
    }
    ; The main window (during a drag, id 1) and the shadow host (for good, id 2)
    ; are subclassed rather than hooked with OnMessage: a subclass procedure
    ; runs the moment a message is sent, whatever state the script's thread is
    ; in, where a message monitor can be skipped -- and one skipped
    ; WM_NCCALCSIZE gives the host a frame, or leaves the pixels to jump.
    static _SrSubCb() {
        static cb := CallbackCreate(ObjBindMethod(AxWindowSmoothResize, "_SrSubProc"), "F", 6)
        return cb
    }
    static _SrSubProc(hWnd, uMsg, wParam, lParam, uId, refData) {
        if (uId = 1) {
            if (uMsg = 0x83 && wParam && AxWindow._byHwnd.Has(hWnd)) {   ; WM_NCCALCSIZE: client = whole window,
                win := AxWindow._byHwnd[hWnd]                            ; the pixels kept in place round a grow/shrink
                return win._srAnchor ? win._SrValidRects(lParam) : 0
            }
            if (uMsg = 0x05 || uMsg = 0x24)                     ; WM_SIZE, WM_GETMINMAXINFO: the grown window is
                return 0                                        ; not the page's size, and may pass the usual limits
        } else if (uId = 2) {
            if (uMsg = 0x83 && wParam)                          ; WM_NCCALCSIZE: client = whole window
                return 0
            if (uMsg = 0x84)                                    ; WM_NCHITTEST: never in the mouse's way
                return -1
            if (uMsg = 0x85)                                    ; WM_NCPAINT: no frame to paint -- ever
                return 0
            if (uMsg = 0x86)                                    ; WM_NCACTIVATE: DWM hears it (the active, darker
                return DllCall("comctl32\DefSubclassProc", "Ptr", hWnd, "UInt", uMsg, "Ptr", wParam, "Ptr", -1, "Ptr")   ; shadow);
        }                                                       ; -1: no classic frame painted over the window
        return DllCall("comctl32\DefSubclassProc", "Ptr", hWnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }

    ; WM_NCCALCSIZE while the window grows or shrinks round a drag: the pixels
    ; old and new share on screen stay where they are (and so does the browser)
    _SrValidRects(l) {
        a := Max(NumGet(l, 0, "Int"), NumGet(l, 32, "Int")), b := Max(NumGet(l, 4, "Int"), NumGet(l, 36, "Int"))
        c := Min(NumGet(l, 8, "Int"), NumGet(l, 40, "Int")), d := Min(NumGet(l, 12, "Int"), NumGet(l, 44, "Int"))
        if (c <= a || d <= b)
            return 0
        for off in [16, 32]                                     ; valid destination = valid source
            NumPut("Int", a, "Int", b, "Int", c, "Int", d, l, off)
        return 0x400                                            ; WVR_VALIDRECTS
    }

    ; the drag itself. edge: "L" "T" "LT" "TR" "LB". path (tests): [[x, y], ...]
    ; cursor positions to play instead of following the mouse
    _SrLoop(edge, path := "") {
        hw := this.Gui.Hwnd, ax := this.Ax.Hwnd
        hasL := InStr(edge, "L"), hasT := InStr(edge, "T"), hasR := InStr(edge, "R"), hasB := InStr(edge, "B")
        WinGetPos(&sL, &sT, &sW, &sH, hw)
        sR := sL + sW, sB := sT + sH
        mi := Buffer(40, 0), NumPut("UInt", 40, mi)
        DllCall("GetMonitorInfoW", "Ptr", DllCall("MonitorFromWindow", "Ptr", hw, "UInt", 2, "Ptr"), "Ptr", mi)
        gL := hasL ? Min(NumGet(mi, 20, "Int"), sL) : sL, gT := hasT ? Min(NumGet(mi, 24, "Int"), sT) : sT   ; the grown window
        gR := hasR ? Max(NumGet(mi, 28, "Int"), sR) : sR, gB := hasB ? Max(NumGet(mi, 32, "Int"), sB) : sB
        k := (DllCall("GetDpiForWindow", "Ptr", hw, "UInt") || 96) / 96
        minW := Round(this.MinWidth * k), minH := Round(this.MinHeight * k)
        pt := Buffer(8, 0)
        if IsObject(path)
            cx := path[1][1], cy := path[1][2]
        else
            DllCall("GetCursorPos", "Ptr", pt), cx := NumGet(pt, 0, "Int"), cy := NumGet(pt, 4, "Int")
        offL := cx - sL, offT := cy - sT, offR := cx - sR, offB := cy - sB
        cur := DllCall("LoadCursor", "Ptr", 0, "Ptr", edge = "L" ? 32644 : edge = "T" ? 32645 : edge = "LT" ? 32642 : 32643, "Ptr")
        if !IsObject(this._srHost)
            this._srHost := AxResizeHost(this)

        ; --- start: grow once; nothing seen moves
        this._srActive := true
        DllCall("comctl32\SetWindowSubclass", "Ptr", hw, "Ptr", AxWindowSmoothResize._SrSubCb(), "Ptr", 1, "Ptr", 0)
        this.CloseContextMenu(), this._CloseDropdown(), this._HideTip(true)
        this._SrFrame()
        if !IsObject(path)
            DllCall("SetCapture", "Ptr", hw)
        DllCall("SetCursor", "Ptr", cur)
        DllCall("dwmapi\DwmFlush")                              ; a whole frame to do this in
        ; Windows' shadow would lie round the grown window: its frame style and
        ; rounding off (it takes both), the host's shadow round what is seen
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hw, "UInt", 33, "Int*", 1, "UInt", 4)   ; DWMWCP_DONOTROUND
        sty := DllCall("GetWindowLongPtr", "Ptr", hw, "Int", -16, "Ptr")
        DllCall("SetWindowLongPtr", "Ptr", hw, "Int", -16, "Ptr", sty & ~0x40000)               ; WS_THICKFRAME
        this._srAnchor := true
        DllCall("SetWindowPos", "Ptr", hw, "Ptr", 0, "Int", gL, "Int", gT, "Int", gR - gL, "Int", gB - gT, "UInt", 0x34)   ; NOZORDER|NOACTIVATE|FRAMECHANGED
        this._srAnchor := false
        DllCall("SetWindowPos", "Ptr", ax, "Ptr", 0, "Int", sL - gL, "Int", sT - gT, "Int", sW, "Int", sH, "UInt", 0x114)   ; where it is on screen
        this._srHost.Show(hw, sL, sT, sR, sB)

        ; --- drag: only the browser moves
        vL := sL, vT := sT, vR := sR, vB := sB, i := 1
        try loop {
            if IsObject(path) {
                if (++i > path.Length)
                    break
                cx := path[i][1], cy := path[i][2]
            } else {
                if (!GetKeyState("LButton", "P") || this.Closing)
                    break
                DllCall("GetCursorPos", "Ptr", pt), cx := NumGet(pt, 0, "Int"), cy := NumGet(pt, 4, "Int")
            }
            nL := hasL ? Min(Max(cx - offL, gL), sR - minW) : sL
            nT := hasT ? Min(Max(cy - offT, gT), sB - minH) : sT
            nR := hasR ? Max(Min(cx - offR, gR), sL + minW) : sR
            nB := hasB ? Max(Min(cy - offB, gB), sT + minH) : sB
            if (nL != vL || nT != vT || nR != vR || nB != vB) {
                vL := nL, vT := nT, vR := nR, vB := nB
                DllCall("SetWindowPos", "Ptr", ax, "Ptr", 0, "Int", vL - gL, "Int", vT - gT, "Int", vR - vL, "Int", vB - vT, "UInt", 0x114)   ; NOZORDER|NOACTIVATE|NOCOPYBITS
                this._srHost.Move(vL, vT, vR, vB)
                try this.Doc.documentElement.offsetWidth            ; lay out at the new size now...
                DllCall("RedrawWindow", "Ptr", ax, "Ptr", 0, "Ptr", 0, "UInt", 0x180)   ; ...and paint it (ALLCHILDREN|UPDATENOW)
                if this.HasOwnProp("_srOnStep")                     ; tests
                    this._srOnStep.Call(vL, vT, vR, vB)
            }
            DllCall("SetCursor", "Ptr", cur)
            Sleep(-1)                                               ; let the page run
            DllCall("dwmapi\DwmFlush")                              ; one step per frame
        }

        ; --- end: shrink to what is seen; nothing seen moves
        DllCall("dwmapi\DwmFlush")
        sty := DllCall("GetWindowLongPtr", "Ptr", hw, "Int", -16, "Ptr")
        DllCall("SetWindowLongPtr", "Ptr", hw, "Int", -16, "Ptr", sty | 0x40000)
        this._srAnchor := true
        DllCall("SetWindowPos", "Ptr", hw, "Ptr", 0, "Int", vL, "Int", vT, "Int", vR - vL, "Int", vB - vT, "UInt", 0x34)
        this._srAnchor := false
        DllCall("SetWindowPos", "Ptr", ax, "Ptr", 0, "Int", 0, "Int", 0, "Int", vR - vL, "Int", vB - vT, "UInt", 0x114)
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", hw, "Ptr", AxWindowSmoothResize._SrSubCb(), "Ptr", 1)
        AxSys.RoundCorners(hw, this.RoundCorners)               ; Windows' shadow back on the real window...
        this._srHost.Hide()                                     ; ...and the host's gone
        if !IsObject(path)
            DllCall("user32\ReleaseCapture")
        this._srActive := false
        this._OnSize(0, Round((vR - vL) / k), Round((vB - vT) / k))   ; what a resize does besides: embeds, border, max rect
    }
}

; -----------------------------------------------------------------------------
; AxResizeHost: Windows' own shadow round the visible part during a still drag.
; A second window framed like AxWindow's (WS_THICKFRAME, the 1 px extended
; frame, rounded corners, client = whole window), filled with the page's
; background, sits just under the main one and follows the visible rectangle
; each step. The page covers it: what shows is what Windows draws round it --
; the shadow, and the smooth corners through the page's corner cut-outs. It is
; told it is active, for the active window's (darker) shadow. Only it moves
; during the drag, and being one colour it has nothing to judder.
; -----------------------------------------------------------------------------
class AxResizeHost {
    static _byHwnd := Map()

    __New(win) {
        this.win := win
        this.g := Gui("-Caption +Resize +ToolWindow -DPIScale +E0x08000000")   ; WS_EX_NOACTIVATE
        this.hw := this.g.Hwnd
        AxResizeHost._byHwnd[this.hw] := this
        ; no frame, no hit-testing, never a classic frame painted (see _SrSubProc)
        DllCall("comctl32\SetWindowSubclass", "Ptr", this.hw, "Ptr", AxWindowSmoothResize._SrSubCb(), "Ptr", 2, "Ptr", 0)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.hw, "UInt", 3, "Int*", 1, "UInt", 4)   ; DWMWA_TRANSITIONS_FORCEDISABLED
        AxSys.Shadow(this.hw)
        AxSys.RoundCorners(this.hw, win.RoundCorners)
        AxSys.Border(this.hw, "none")                            ; the page draws the border
        DllCall("SetWindowPos", "Ptr", this.hw, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x37)   ; FRAMECHANGED
    }
    Show(hwMain, x1, y1, x2, y2) {
        bg := LTrim(this.win.BackColor, "#")                     ; the page's own background, if it says
        try {
            c := this.win.Doc.body.currentStyle.backgroundColor
            if RegExMatch(c, "^#([0-9a-fA-F]{6})$", &mm)
                bg := mm[1]
            else if RegExMatch(c, "rgba?\((\d+),\s*(\d+),\s*(\d+)", &mm)
                bg := Format("{:02X}{:02X}{:02X}", mm[1], mm[2], mm[3])
        }
        try this.g.BackColor := bg
        ; what DWM fills in where this window has not painted yet -- the strip
        ; it gains on each step, and all of it before its first paint -- or
        ; that shows white through the page's corner cut-outs
        AxSys.Backdrop(this.hw, bg)
        DllCall("SetWindowPos", "Ptr", this.hw, "Ptr", hwMain, "Int", x1, "Int", y1, "Int", x2 - x1, "Int", y2 - y1, "UInt", 0x50)   ; SHOWWINDOW|NOACTIVATE, under the main one
        DllCall("RedrawWindow", "Ptr", this.hw, "Ptr", 0, "Ptr", 0, "UInt", 0x305)   ; INVALIDATE|ERASE|UPDATENOW|ERASENOW: painted now
        DllCall("SendMessage", "Ptr", this.hw, "UInt", 0x86, "Ptr", 1, "Ptr", 0)   ; WM_NCACTIVATE: the active window's shadow (no frame repaint: _SrSubProc)
    }
    Move(x1, y1, x2, y2) {
        DllCall("SetWindowPos", "Ptr", this.hw, "Ptr", 0, "Int", x1, "Int", y1, "Int", x2 - x1, "Int", y2 - y1, "UInt", 0x14)
        DllCall("RedrawWindow", "Ptr", this.hw, "Ptr", 0, "Ptr", 0, "UInt", 0x300)   ; UPDATENOW|ERASENOW: the strip it gained, painted now
    }
    Hide() => DllCall("ShowWindow", "Ptr", this.hw, "Int", 0)
    Destroy() {
        AxResizeHost._byHwnd.Delete(this.hw)
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", this.hw, "Ptr", AxWindowSmoothResize._SrSubCb(), "Ptr", 2)
        try this.g.Destroy()
    }
}
