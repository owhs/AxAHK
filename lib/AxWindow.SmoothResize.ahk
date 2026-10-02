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
;  answer, paint order or DwmFlush fixes that part; it happens in DWM. And
;  Trident paints a resized page piece by piece, over 20-40 ms, so whatever
;  Windows composes meanwhile is half old, half new.
;
;  So for such a drag the page is shown by an overlay that never moves:
;
;    start  a borderless, colour-keyed window (AxResizeOverlay), owned by
;           this one -- so always just above it, never active -- covers every
;           place the drag can reach, showing exactly what is on screen. The
;           browser is then hidden from the screen (an empty window region:
;           it still lays out as ever).
;    drag   each step the page is resized and laid out by everything that
;           lays it out (_OnSize: AxGui's layout, a script's own,
;           OnEvent("Size"), embeds; the page's resize handlers), drawn
;           off-screen (PrintWindow: synchronous, whole) and put on the
;           overlay with one BitBlt: every frame Windows composes is a whole
;           page, at the size seen, its far side still. The real window is
;           moved to the same rectangle under it, painted with the same
;           picture -- it keeps its focus, Windows' own shadow, border and
;           rounded corners, which show through the overlay's see-through
;           edge and corners.
;    end    the browser back on the screen, under the overlay, painted; then
;           the overlay goes.
;
;  The top edge dragged to the top of the screen is handed to Windows, for
;  its snap (full height, with its preview), and taken back if the mouse
;  comes down again.
;
;  The right and bottom edges alone are left to Windows, and so is a window
;  the script made layered itself (a colour key of its own, Opacity).
; =============================================================================
class AxWindowSmoothResize {
    static SrKey := "010203"            ; the overlay's colour key: never painted by the page
    ; Frames the window waits after the overlay on each step. The overlay is
    ; layered, and Windows puts a layered window's new pixels on screen about
    ; a frame later than it moves an ordinary one (0 measured the smoothest).
    static WindowLag := 0
    static DebugFill := ""              ; tests: the window painted in this colour under the overlay, so it shows wherever it is out of step

    ; once the page is up
    _SrSetup() {
        if (this._srOn || !this.SmoothResize || !this.Resizable || this.Closing)
            return
        this._srOn := true
    }

    ; a 32-bit off-screen bitmap, filled with brush br
    static _SrBuf(w, h, br) {
        bi := Buffer(40, 0)
        NumPut("UInt", 40, "Int", w, "Int", -h, "UShort", 1, "UShort", 32, bi)
        dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        hbm := DllCall("CreateDIBSection", "Ptr", dc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
        if !hbm {
            DllCall("DeleteDC", "Ptr", dc)
            return ""
        }
        old := DllCall("SelectObject", "Ptr", dc, "Ptr", hbm, "Ptr")
        rc := Buffer(16, 0), NumPut("Int", 0, "Int", 0, "Int", w, "Int", h, rc)
        DllCall("FillRect", "Ptr", dc, "Ptr", rc, "Ptr", br)
        return {dc: dc, hbm: hbm, old: old, w: w, h: h}
    }
    _SrFree() {
        for p in ["_srSnap", "_srCanvas", "_srShot"] {
            if !IsObject(this.%p%)
                continue
            s := this.%p%, this.%p% := ""
            DllCall("SelectObject", "Ptr", s.dc, "Ptr", s.old), DllCall("DeleteObject", "Ptr", s.hbm), DllCall("DeleteDC", "Ptr", s.dc)
        }
    }

    ; The page drawn off-screen into the page buffer (_srSnap), to be seen at
    ; screen x1,y1-x2,y2 -- the browser, then the embeds over it -- and into
    ; the canvas (_srCanvas: the overlay as it is to be seen) in place of what
    ; was at the old rectangle o, with the window's border and rounded corners
    ; over it (_SrChrome).
    ;
    ; Not the real window's own, seen through: for a frame after it is
    ; resized, Windows shows a window's previous picture pinned to its top-
    ; left -- too wide (a corner of what was inside) or too narrow (nothing)
    ; -- and its edge and corners are where that shows.
    _SrDrawFrame(ies, x1, y1, x2, y2, o := "") {
        s := this._srSnap, c := this._srCanvas, gx := this._srG[1], gy := this._srG[2]
        if !DllCall("PrintWindow", "Ptr", ies, "Ptr", s.dc, "UInt", 0)
            return false
        if (this.HasOwnProp("_embeds") && this._embeds.Count) {
            pt := Buffer(8, 0), rc := Buffer(16, 0)
            for id, e in this._embeds {
                try hc := e.Ctl.Hwnd
                catch
                    continue
                if !DllCall("IsWindowVisible", "Ptr", hc)
                    continue
                DllCall("GetClientRect", "Ptr", hc, "Ptr", rc)
                NumPut("Int", 0, "Int", 0, pt)
                DllCall("MapWindowPoints", "Ptr", hc, "Ptr", this.Gui.Hwnd, "Ptr", pt, "UInt", 1)
                ew := NumGet(rc, 8, "Int"), eh := NumGet(rc, 12, "Int")
                if (ew < 1 || eh < 1)
                    continue
                tmp := AxWindowSmoothResize._SrBuf(ew, eh, this._srBrBg)
                if !IsObject(tmp)
                    continue
                DllCall("PrintWindow", "Ptr", hc, "Ptr", tmp.dc, "UInt", 3)   ; PW_CLIENTONLY|PW_RENDERFULLCONTENT
                DllCall("BitBlt", "Ptr", s.dc, "Int", NumGet(pt, 0, "Int"), "Int", NumGet(pt, 4, "Int"), "Int", ew, "Int", eh, "Ptr", tmp.dc, "Int", 0, "Int", 0, "UInt", 0xCC0020)
                DllCall("SelectObject", "Ptr", tmp.dc, "Ptr", tmp.old), DllCall("DeleteObject", "Ptr", tmp.hbm), DllCall("DeleteDC", "Ptr", tmp.dc)
            }
        }
        s.x1 := x1, s.y1 := y1, s.x2 := x2, s.y2 := y2
        rc := Buffer(16, 0), brK := this._srBrKey
        Key(a, b, cc, d) {
            NumPut("Int", a - gx, "Int", b - gy, "Int", cc - gx, "Int", d - gy, rc)
            DllCall("FillRect", "Ptr", c.dc, "Ptr", rc, "Ptr", brK)
        }
        if IsObject(o)
            Key(o[1], o[2], o[3], o[4])
        DllCall("BitBlt", "Ptr", c.dc, "Int", x1 - gx, "Int", y1 - gy, "Int", x2 - x1, "Int", y2 - y1, "Ptr", s.dc, "Int", 0, "Int", 0, "UInt", 0xCC0020)
        this._SrChrome(x1 - gx, y1 - gy, x2 - gx, y2 - gy)
        ; what the window under it is painted (_SrSubProc): a colour per
        ; quarter, the page's own beside each corner -- whatever Windows
        ; shifts of it, the soft rim round each corner looks the same
        ww := x2 - x1, hh := y2 - y1, m := Min(2, ww // 2, hh // 2)
        this._srQuad := [DllCall("GetPixel", "Ptr", s.dc, "Int", m, "Int", m, "UInt"), DllCall("GetPixel", "Ptr", s.dc, "Int", ww - 1 - m, "Int", m, "UInt")
                       , DllCall("GetPixel", "Ptr", s.dc, "Int", m, "Int", hh - 1 - m, "UInt"), DllCall("GetPixel", "Ptr", s.dc, "Int", ww - 1 - m, "Int", hh - 1 - m, "UInt")]
        return true
    }
    ; The window's border and rounded corners as Windows drew them when the
    ; drag started (_srShot, off the screen), onto the frame at canvas x1,y1-
    ; x2,y2: each edge's pixels from the shot, its two halves held to their
    ; own ends (a title bar's stays by the top, a status bar's by the bottom),
    ; the gap between drawn out; the corners as they were, see-through
    ; beyond the curve -- where the real window's own soft rim shows.
    _SrChrome(x1, y1, x2, y2) {
        s := this._srShot, c := this._srCanvas.dc
        if !IsObject(s)
            return
        sw := s.w, sh := s.h, nw := x2 - x1, nh := y2 - y1
        Run_(sx, sy, horiz, dx, dy) {                           ; one edge, 1 px thick
            sl := horiz ? sw : sh, nl := horiz ? nw : nh, half := sl // 2
            n1 := Min(half, nl), n2 := Min(sl - half, nl)
            Copy(dx, dy, 0, n1), Copy(horiz ? x2 - n2 : dx, horiz ? dy : y2 - n2, sl - n2, n2)
            if (nl > sl)                                         ; the gap: the pixel at the middle, drawn out
                DllCall("StretchBlt", "Ptr", c, "Int", horiz ? dx + half : dx, "Int", horiz ? dy : dy + half, "Int", horiz ? nl - sl : 1, "Int", horiz ? 1 : nl - sl
                      , "Ptr", s.dc, "Int", horiz ? half : sx, "Int", horiz ? sy : half, "Int", 1, "Int", 1, "UInt", 0xCC0020)
            Copy(tx, ty, from, len) {
                if (len > 0)
                    DllCall("BitBlt", "Ptr", c, "Int", tx, "Int", ty, "Int", horiz ? len : 1, "Int", horiz ? 1 : len
                          , "Ptr", s.dc, "Int", horiz ? from : sx, "Int", horiz ? sy : from, "UInt", 0xCC0020)
            }
        }
        Run_(0, 0, true, x1, y1), Run_(0, sh - 1, true, x1, y2 - 1)
        Run_(0, 0, false, x1, y1), Run_(sw - 1, 0, false, x2 - 1, y1)
        r := this._srCorner
        if (!r || nw < 2 * r || nh < 2 * r || sw < 2 * r || sh < 2 * r)
            return
        key := AxSys.ColorRef(AxWindowSmoothResize.SrKey)
        ; inside the curve: the page as it is now (the frame is already there)
        ; -- nothing of the shot, which carried whatever was in the corner then
        ; (a button running into it) to wherever the corner is now. Beyond it:
        ; see-through, where the real window's smoothed rim and border show.
        for cn in [[0, 0, x1, y1], [sw - r, 0, x2 - r, y1], [0, sh - r, x1, y2 - r], [sw - r, sh - r, x2 - r, y2 - r]] {
            right := cn[1] > 0, bottom := cn[2] > 0
            for p in this._srCornerOut
                DllCall("SetPixelV", "Ptr", c, "Int", cn[3] + (right ? r - 1 - p[1] : p[1]), "Int", cn[4] + (bottom ? r - 1 - p[2] : p[2]), "UInt", key)
        }
    }
    ; the pixels of a top-left corner r px square that lie beyond its curve
    ; (a pixel the curve only crosses counts as beyond: the real window's
    ; smoothed rim shows there)
    static _SrCornerOut(r) {
        out := []
        loop r {
            py := A_Index - 1
            loop r {
                px := A_Index - 1
                if ((px + 0.5 - r) ** 2 + (py + 0.5 - r) ** 2 > (r - 1) ** 2)
                    out.Push([px, py])
            }
        }
        return out
    }
    ; the window as it is on screen now, border and corners as Windows draws them
    _SrShotTake(x1, y1, x2, y2) {
        sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
        dc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
        hbm := DllCall("CreateCompatibleBitmap", "Ptr", sdc, "Int", x2 - x1, "Int", y2 - y1, "Ptr")
        old := DllCall("SelectObject", "Ptr", dc, "Ptr", hbm, "Ptr")
        DllCall("BitBlt", "Ptr", dc, "Int", 0, "Int", 0, "Int", x2 - x1, "Int", y2 - y1, "Ptr", sdc, "Int", x1, "Int", y1, "UInt", 0x40CC0020)   ; SRCCOPY|CAPTUREBLT
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
        this._srShot := {dc: dc, hbm: hbm, old: old, w: x2 - x1, h: y2 - y1}
    }
    ; ...and the canvas put on the overlay, screen rectangle x1,y1-x2,y2 of it, in one BitBlt
    _SrShowFrame(x1, y1, x2, y2) {
        hw := this._srOverlay.hw, gx := this._srG[1], gy := this._srG[2]
        dc := DllCall("GetDC", "Ptr", hw, "Ptr")
        DllCall("BitBlt", "Ptr", dc, "Int", x1 - gx, "Int", y1 - gy, "Int", x2 - x1, "Int", y2 - y1, "Ptr", this._srCanvas.dc, "Int", x1 - gx, "Int", y1 - gy, "UInt", 0xCC0020)
        DllCall("ReleaseDC", "Ptr", hw, "Ptr", dc)
        DllCall("GdiFlush")
    }
    ; Drag() hands the edges that move the window's origin here
    _SrDrag(edge) {
        static mine := Map("W", "L", "N", "T", "NW", "LT", "NE", "TR", "SW", "LB")
        e := StrUpper(edge)
        if (!this._srOn || this._srActive || !mine.Has(e) || this.IsMaximized())
            return false
        if (DllCall("GetWindowLongPtr", "Ptr", this.Gui.Hwnd, "Int", -20, "Ptr") & 0x80000)   ; made see-through by the script
            return false                                        ; (WinSetTransparent...): an opaque overlay would not match
        if !AxWindowSmoothResize._SrTrident(this.Ax.Hwnd)
            return false
        DllCall("user32\ReleaseCapture")                        ; the page's own
        SetTimer(ObjBindMethod(this, "_SrLoop", mine[e]), -1)
        return true
    }
    ; The main window (during a drag, id 1) and the overlay (for good, id 2)
    ; are subclassed rather than hooked with OnMessage: a subclass procedure
    ; runs the moment a message is sent, whatever state the script's thread is
    ; in, where a message monitor can be skipped.
    static _SrSubCb() {
        static cb := CallbackCreate(ObjBindMethod(AxWindowSmoothResize, "_SrSubProc"), "F", 6)
        return cb
    }
    static _SrSubProc(hWnd, uMsg, wParam, lParam, uId, refData) {
        if (uId = 1) {
            if (uMsg = 0x83 && wParam) {                        ; WM_NCCALCSIZE: client = whole window, as ever (_SrPlace:
                win := AxWindow._byHwnd.Has(hWnd) ? AxWindow._byHwnd[hWnd] : ""   ; its pixels kept in place)
                return (IsObject(win) && win._srAnchor) ? win._SrValidRects(lParam) : 0
            }
            if (uMsg = 0x05 || uMsg = 0x24)                     ; WM_SIZE, WM_GETMINMAXINFO: the drag lays the page
                return 0                                        ; out itself, at each step
            ; WM_NCACTIVATE "inactive" during the drag (moving the window, and
            ; showing the overlay it owns, can bring one though it keeps the
            ; focus): not passed on -- Windows would give it the smaller,
            ; lighter shadow of an inactive window, and the page would dim.
            ; One that really meant it is said at the end (_SrLoop).
            if (uMsg = 0x86 && !wParam)
                return 1
            if (uMsg = 0x14 && AxWindow._byHwnd.Has(hWnd)) {    ; WM_ERASEBKGND: under the overlay, the same picture
                win := AxWindow._byHwnd[hWnd]
                rc := Buffer(16, 0)
                if (AxWindowSmoothResize.DebugFill != "") {
                    DllCall("GetClientRect", "Ptr", hWnd, "Ptr", rc)
                    br := DllCall("CreateSolidBrush", "UInt", AxSys.ColorRef(AxWindowSmoothResize.DebugFill), "Ptr")
                    DllCall("FillRect", "Ptr", wParam, "Ptr", rc, "Ptr", br), DllCall("DeleteObject", "Ptr", br)
                    return 1
                }
                if IsObject(win._srQuad) {                      ; a colour per quarter (_SrDrawFrame)
                    DllCall("GetClientRect", "Ptr", hWnd, "Ptr", rc)
                    cw := NumGet(rc, 8, "Int"), ch := NumGet(rc, 12, "Int"), mx := cw // 2, my := ch // 2
                    for q in [[0, 0, mx, my, 1], [mx, 0, cw, my, 2], [0, my, mx, ch, 3], [mx, my, cw, ch, 4]] {
                        NumPut("Int", q[1], "Int", q[2], "Int", q[3], "Int", q[4], rc)
                        br := DllCall("CreateSolidBrush", "UInt", win._srQuad[q[5]], "Ptr")
                        DllCall("FillRect", "Ptr", wParam, "Ptr", rc, "Ptr", br), DllCall("DeleteObject", "Ptr", br)
                    }
                    return 1
                }
            }
        } else if (uId = 2) {
            if (uMsg = 0x83 && wParam)                          ; WM_NCCALCSIZE: client = whole window
                return 0
            if (uMsg = 0x84)                                    ; WM_NCHITTEST: never in the mouse's way
                return -1
            if (uMsg = 0x21)                                    ; WM_MOUSEACTIVATE: MA_NOACTIVATE
                return 3
            if (uMsg = 0x14 && AxResizeOverlay._byHwnd.Has(hWnd)) {   ; WM_ERASEBKGND: the canvas
                win := AxResizeOverlay._byHwnd[hWnd].win
                if IsObject(win._srCanvas) {
                    rc := Buffer(16, 0)
                    DllCall("GetClientRect", "Ptr", hWnd, "Ptr", rc)
                    DllCall("BitBlt", "Ptr", wParam, "Int", 0, "Int", 0, "Int", NumGet(rc, 8, "Int"), "Int", NumGet(rc, 12, "Int")
                          , "Ptr", win._srCanvas.dc, "Int", 0, "Int", 0, "UInt", 0xCC0020)
                    return 1
                }
            }
        }
        return DllCall("comctl32\DefSubclassProc", "Ptr", hWnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }

    ; Trident's own window (Internet Explorer_Server) under the ActiveX host
    static _SrTrident(ax) {
        found := 0, cls := Buffer(128)
        Look(hc, *) {
            DllCall("GetClassNameW", "Ptr", hc, "Ptr", cls, "Int", 64)
            if (StrGet(cls) = "Internet Explorer_Server") {
                found := hc
                return 0
            }
            return 1
        }
        cb := CallbackCreate(Look, "F", 2)
        try DllCall("EnumChildWindows", "Ptr", ax, "Ptr", cb, "Ptr", 0)
        CallbackFree(cb)
        return found
    }

    ; Windows' own top-edge snap: dragged to the top of the screen, the top edge
    ; makes the window full height (and back, dragged off again), with its
    ; preview. That belongs to Windows' resize, so at the top of the screen
    ; the drag is handed to it (_SrLoop) -- nothing seen moves any more there,
    ; so nothing can shake -- and taken back if the mouse comes down again
    ; without letting go (Windows' WM_SIZING, here).
    static _SrSizing(wParam, lParam, msg, hwnd) {
        if !AxWindow._byHwnd.Has(hwnd)
            return
        win := AxWindow._byHwnd[hwnd]
        if (win._srNativeTop = "")
            return
        if (msg = 0x232) {                                      ; WM_EXITSIZEMOVE: Windows' drag over
            win._srNativeTop := ""
            return
        }
        pt := Buffer(8, 0)
        DllCall("GetCursorPos", "Ptr", pt)
        if (NumGet(pt, 4, "Int") > win._srNativeTop + 6) {      ; down off the top again: smooth again
            grab := win._srNativeGrab
            win._srNativeTop := ""
            DllCall("user32\ReleaseCapture")                    ; (ends Windows' drag)
            SetTimer(ObjBindMethod(win, "_SrLoop", "T", "", grab), -1)
        }
    }
    static _SrNudge() => DllCall("mouse_event", "UInt", 1, "Int", 0, "Int", 0, "UInt", 0, "UPtr", 0)   ; a mouse move where it is: Windows looks at the edge now

    ; the drag itself. edge: "L" "T" "LT" "TR" "LB". path (tests): [[x, y], ...]
    ; cursor positions to play instead of following the mouse. grabT: where
    ; the edge was held (a drag taken back from Windows, _SrSizing)
    _SrLoop(edge, path := "", grabT := "") {
        hw := this.Gui.Hwnd, ax := this.Ax.Hwnd
        ies := AxWindowSmoothResize._SrTrident(ax)
        if !ies
            return
        hasL := InStr(edge, "L"), hasT := InStr(edge, "T"), hasR := InStr(edge, "R"), hasB := InStr(edge, "B")
        WinGetPos(&sL, &sT, &sW, &sH, hw)
        sR := sL + sW, sB := sT + sH
        mi := Buffer(40, 0), NumPut("UInt", 40, mi)
        DllCall("GetMonitorInfoW", "Ptr", DllCall("MonitorFromWindow", "Ptr", hw, "UInt", 2, "Ptr"), "Ptr", mi)
        gL := hasL ? Min(NumGet(mi, 20, "Int"), sL) : sL, gT := hasT ? Min(NumGet(mi, 24, "Int"), sT) : sT   ; what the drag can reach
        gR := hasR ? Max(NumGet(mi, 28, "Int"), sR) : sR, gB := hasB ? Max(NumGet(mi, 32, "Int"), sB) : sB
        k := (DllCall("GetDpiForWindow", "Ptr", hw, "UInt") || 96) / 96
        minW := Round(this.MinWidth * k), minH := Round(this.MinHeight * k)
        pt := Buffer(8, 0)
        if IsObject(path)
            cx := path[1][1], cy := path[1][2]
        else
            DllCall("GetCursorPos", "Ptr", pt), cx := NumGet(pt, 0, "Int"), cy := NumGet(pt, 4, "Int")
        offL := cx - sL, offT := cy - sT, offR := cx - sR, offB := cy - sB
        if (grabT != "")
            offT := grabT
        ; the top edge alone, by the mouse, with "snap" sizing on: at the top
        ; of the screen it is Windows' drag (_SrSizing)
        monTop := NumGet(mi, 8, "Int"), handover := false
        snapTop := (edge = "T" && !IsObject(path) && DllCall("SystemParametersInfo", "UInt", 0x8E, "UInt", 0, "Int*", &snapOn := 0, "UInt", 0) && snapOn)   ; SPI_GETSNAPSIZING
        cur := DllCall("LoadCursor", "Ptr", 0, "Ptr", edge = "L" ? 32644 : edge = "T" ? 32645 : edge = "LT" ? 32642 : 32643, "Ptr")
        if !IsObject(this._srOverlay)
            this._srOverlay := AxResizeOverlay(this)
        this._srG := [gL, gT]                                   ; the overlay's top-left on screen
        ; the corners Windows rounds (8 px at 96 dpi), left see-through on the overlay
        this._srCorner := (this.RoundCorners && VerCompare(A_OSVersion, "10.0.22000") >= 0) ? Round(8 * k) : 0

        ; --- start: the overlay up, showing what is on screen
        this._srActive := true
        this._srBrKey := DllCall("CreateSolidBrush", "UInt", AxSys.ColorRef(AxWindowSmoothResize.SrKey), "Ptr")
        this._srBrBg := DllCall("CreateSolidBrush", "UInt", AxSys.ColorRef(this.BackColor), "Ptr")
        this.CloseContextMenu(), this._CloseDropdown(), this._HideTip(true)
        this._RunJs("window.__axSrResize=window.__axSrResize||function(){try{var e=document.createEvent('UIEvents');"
                  . "e.initUIEvent('resize',false,false,window,0);window.dispatchEvent(e)}catch(x){}};")
        gw := gR - gL, gh := gB - gT
        this._SrShotTake(sL, sT, sR, sB)                        ; the border and corners as Windows draws them (_SrChrome)
        this._srCornerOut := AxWindowSmoothResize._SrCornerOut(this._srCorner)
        this._srSnap := AxWindowSmoothResize._SrBuf(gw, gh, this._srBrBg)
        this._srCanvas := AxWindowSmoothResize._SrBuf(gw, gh, this._srBrKey)
        if !IsObject(this._srSnap) || !IsObject(this._srCanvas) || !this._SrDrawFrame(ies, sL, sT, sR, sB) {
            this._SrEnd()                                       ; no memory, or no drawing: Windows' own drag
            if !IsObject(path) && GetKeyState("LButton", "P")
                PostMessage(0xA1, Map("L", 10, "T", 12, "LT", 13, "TR", 14, "LB", 16)[edge], 0, , hw)
            return
        }
        DllCall("comctl32\SetWindowSubclass", "Ptr", hw, "Ptr", AxWindowSmoothResize._SrSubCb(), "Ptr", 1, "Ptr", 0)
        if !IsObject(path)
            DllCall("SetCapture", "Ptr", hw)
        DllCall("SetCursor", "Ptr", cur)
        this._srOverlay.Show(gL, gT, gR, gB)
        DllCall("dwmapi\DwmFlush"), DllCall("dwmapi\DwmFlush")   ; the overlay on screen (a layered window's first frame is late)...
        DllCall("SetWindowRgn", "Ptr", ax, "Ptr", DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr"), "Int", 0)   ; ...then the browser off it

        ; --- drag
        vL := sL, vT := sT, vR := sR, vB := sB, i := 1, lastDraw := A_TickCount
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
                oV := [vL, vT, vR, vB]
                vL := nL, vT := nT, vR := nR, vB := nB
                ; 1. The page at the new size, laid out by everything that lays
                ;    it out -- off the screen, nothing of it shows yet
                DllCall("SetWindowPos", "Ptr", ax, "Ptr", 0, "Int", 0, "Int", 0, "Int", vR - vL, "Int", vB - vT, "UInt", 0x11E)   ; NOMOVE|NOZORDER|NOREDRAW|NOACTIVATE|NOCOPYBITS
                try this._OnSize(0, Round((vR - vL) / k), Round((vB - vT) / k))
                try this.Doc.parentWindow.__axSrResize()        ; the page's own resize handlers, now
                try this.Doc.documentElement.offsetWidth        ; laid out at the new size, now
                ; 2. Drawn whole, off-screen, and put on the overlay in one go
                this._SrDrawFrame(ies, vL, vT, vR, vB, oV)
                this._SrShowFrame(Min(oV[1], vL), Min(oV[2], vT), Max(oV[3], vR), Max(oV[4], vB))
                ; 3. The window under it, with its shadow, border and corners
                loop AxWindowSmoothResize.WindowLag
                    DllCall("dwmapi\DwmFlush")
                this._SrPlace(vL, vT, vR, vB)
                lastDraw := A_TickCount
                if this.HasOwnProp("_srOnStep")                     ; tests
                    this._srOnStep.Call(vL, vT, vR, vB)
            } else if (A_TickCount - lastDraw > 150) {
                ; the mouse at rest: what the page did meanwhile (a late
                ; layout, an animation), a few times a second
                if this._SrDrawFrame(ies, vL, vT, vR, vB)
                    this._SrShowFrame(vL, vT, vR, vB)
                lastDraw := A_TickCount
            } else
                DllCall("dwmapi\DwmFlush")                          ; nothing new: wait for the next frame
            if (snapTop && cy <= monTop && vT = gT) {               ; at the top of the screen, the edge with it
                handover := true
                break
            }
            DllCall("SetCursor", "Ptr", cur)
            Sleep(-1)                                               ; let the page run
        }

        ; --- end: the browser back on the screen, under the overlay; then the overlay goes
        this._SrPlace(vL, vT, vR, vB)
        DllCall("SetWindowRgn", "Ptr", ax, "Ptr", 0, "Int", 0)
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", hw, "Ptr", AxWindowSmoothResize._SrSubCb(), "Ptr", 1)
        this._srActive := false
        if (DllCall("GetActiveWindow", "Ptr") != hw)            ; really deactivated meanwhile: said now
            SendMessage(0x86, 0, 0, , hw)
        this._OnSize(0, Round((vR - vL) / k), Round((vB - vT) / k))   ; what a resize does: page, embeds, border, max rect
        DllCall("RedrawWindow", "Ptr", hw, "Ptr", 0, "Ptr", 0, "UInt", 0x185)   ; INVALIDATE|ERASE|ALLCHILDREN|UPDATENOW
        loop 3                                                  ; (Trident's paint reaching the screen)
            DllCall("dwmapi\DwmFlush")
        if !IsObject(path)
            DllCall("user32\ReleaseCapture")
        this._SrEnd()
        if (handover && GetKeyState("LButton", "P") && !this.Closing) {   ; at the top of the screen: Windows' drag from here
            static hooked := false
            if !hooked {
                hooked := true
                OnMessage(0x214, ObjBindMethod(AxWindowSmoothResize, "_SrSizing"))   ; WM_SIZING
                OnMessage(0x232, ObjBindMethod(AxWindowSmoothResize, "_SrSizing"))   ; WM_EXITSIZEMOVE
            }
            this._srNativeTop := monTop, this._srNativeGrab := offT
            PostMessage(0xA1, 12, 0, , hw)                      ; WM_NCLBUTTONDOWN, HTTOP
            SetTimer(ObjBindMethod(AxWindowSmoothResize, "_SrNudge"), -40)
        }
    }
    ; the real window to rectangle x1,y1-x2,y2, painted at once with the frame
    ; Its pixels the old and new rectangles share stay where they are on
    ; screen (_SrValidRects): Windows shows a moved window's old pixels until
    ; it paints, pinned to its top-left otherwise -- through the overlay's
    ; see-through corners, a corner of whatever was inside.
    _SrPlace(x1, y1, x2, y2) {
        hw := this.Gui.Hwnd
        WinGetPos(&px, &py, &pw, &ph, hw)
        if (px = x1 && py = y1 && pw = x2 - x1 && ph = y2 - y1)
            return
        this._srAnchor := true
        DllCall("SetWindowPos", "Ptr", hw, "Ptr", 0, "Int", x1, "Int", y1, "Int", x2 - x1, "Int", y2 - y1, "UInt", 0x14)   ; NOZORDER|NOACTIVATE
        this._srAnchor := false
        ; that shifts the children too: back where the page has them
        DllCall("SetWindowPos", "Ptr", this.Ax.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x1D)   ; NOSIZE|NOZORDER|NOREDRAW|NOACTIVATE
        if (this.HasOwnProp("_embeds") && this._embeds.Count) {
            for id, e in this._embeds
                e.Last := ""
            this._LayoutEmbeds()
        }
        DllCall("RedrawWindow", "Ptr", hw, "Ptr", 0, "Ptr", 0, "UInt", 0x205)   ; INVALIDATE|ERASE|ERASENOW: the rest, at once
    }
    ; WM_NCCALCSIZE for _SrPlace: client = whole window, the pixels old and new
    ; share on screen kept in place
    _SrValidRects(l) {
        a := Max(NumGet(l, 0, "Int"), NumGet(l, 32, "Int")), b := Max(NumGet(l, 4, "Int"), NumGet(l, 36, "Int"))
        c := Min(NumGet(l, 8, "Int"), NumGet(l, 40, "Int")), d := Min(NumGet(l, 12, "Int"), NumGet(l, 44, "Int"))
        if (c <= a || d <= b)
            return 0
        for off in [16, 32]                                     ; valid destination = valid source
            NumPut("Int", a, "Int", b, "Int", c, "Int", d, l, off)
        return 0x400                                            ; WVR_VALIDRECTS
    }
    _SrEnd() {
        if IsObject(this._srOverlay)
            this._srOverlay.Hide()
        this._SrFree()
        for b in [this._srBrKey, this._srBrBg]
            if b
                DllCall("DeleteObject", "Ptr", b)
        this._srBrKey := 0, this._srBrBg := 0, this._srQuad := ""
        this._srActive := false
    }
}

; -----------------------------------------------------------------------------
; AxResizeOverlay: what is seen of the page during a smooth drag. Borderless,
; colour-keyed (see-through wherever the key is: round the page, its outermost
; pixel, its corners), owned by the AxWindow -- so it sits just above it, off
; the taskbar -- never active, never in the mouse's way.
; -----------------------------------------------------------------------------
class AxResizeOverlay {
    static _byHwnd := Map()

    __New(win) {
        this.win := win
        this.g := Gui("-Caption -DPIScale +ToolWindow +E0x08080020 +Owner" win.Gui.Hwnd)   ; NOACTIVATE|LAYERED|TRANSPARENT
        this.hw := this.g.Hwnd
        AxResizeOverlay._byHwnd[this.hw] := this
        DllCall("SetLayeredWindowAttributes", "Ptr", this.hw, "UInt", AxSys.ColorRef(AxWindowSmoothResize.SrKey), "UChar", 0, "UInt", 1)   ; LWA_COLORKEY
        DllCall("comctl32\SetWindowSubclass", "Ptr", this.hw, "Ptr", AxWindowSmoothResize._SrSubCb(), "Ptr", 2, "Ptr", 0)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.hw, "UInt", 3, "Int*", 1, "UInt", 4)    ; DWMWA_TRANSITIONS_FORCEDISABLED
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.hw, "UInt", 33, "Int*", 1, "UInt", 4)   ; DWMWCP_DONOTROUND
        AxSys.Border(this.hw, "none")
        DllCall("SetWindowPos", "Ptr", this.hw, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x37)   ; FRAMECHANGED
    }
    ; just above the main window (owned windows stay above their owner)
    Show(x1, y1, x2, y2) {
        above := DllCall("GetWindow", "Ptr", this.win.Gui.Hwnd, "UInt", 3, "Ptr")   ; GW_HWNDPREV
        if (above = this.hw || (above && (DllCall("GetWindowLongPtr", "Ptr", above, "Int", -20, "Ptr") & 0x8)))   ; itself, or topmost:
            above := 0                                                                                   ; the top of the ordinary ones
        DllCall("SetWindowPos", "Ptr", this.hw, "Ptr", above, "Int", x1, "Int", y1, "Int", x2 - x1, "Int", y2 - y1, "UInt", 0x50)   ; SHOWWINDOW|NOACTIVATE
        DllCall("RedrawWindow", "Ptr", this.hw, "Ptr", 0, "Ptr", 0, "UInt", 0x305)   ; INVALIDATE|ERASE|UPDATENOW|ERASENOW: painted at once
    }
    Hide() => DllCall("ShowWindow", "Ptr", this.hw, "Int", 0)
    Destroy() {
        AxResizeOverlay._byHwnd.Delete(this.hw)
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", this.hw, "Ptr", AxWindowSmoothResize._SrSubCb(), "Ptr", 2)
        try this.g.Destroy()
    }
}
