#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; =============================================================================
;  AxScreenPick.ahk — pick a colour from anywhere on screen.
;
;      hex := AxScreenPick.Color()                       ; "" if cancelled
;      hex := AxScreenPick.Color({Zoom: 12, Size: 190, OnMove: fn})
;
;  A borderless always-on-top magnifier follows the cursor: the screen around
;  the pointer is blitted with nearest-neighbour scaling (so pixels stay
;  square), a grid is drawn once the zoom is coarse enough, the centre pixel
;  is ringed, and a strip underneath shows the hex, the RGB triplet and the
;  screen coordinates. The wheel changes zoom, left click accepts, right
;  click or Escape cancels.
;
;  The window sits far enough from the cursor that it never samples itself, so
;  it cannot rely on the pointer being over it. Mouse capture is what makes
;  that work -- but only the FOREGROUND window can capture the mouse across
;  the screen. A background window "receives messages only for mouse events
;  that occur when the cursor hot spot is within the visible portion of the
;  window", so a NoActivate magnifier held away from the cursor saw nothing at
;  all and every click fell through to whatever was underneath. The magnifier
;  therefore activates itself, captures, and hands activation back to its
;  owner when it closes.
;
;  Global blocking hotkeys are deliberately NOT used for this. An earlier
;  attempt registered "*LButton" and friends, and any failure to tear them
;  down -- or merely tripping AHK's #MaxHotkeysPerInterval warning, which
;  spinning the wheel does easily -- left a modal dialog on screen that could
;  not be clicked, because the thing swallowing the clicks was the picker.
;  Nothing here may ever block input globally: if this code goes wrong the
;  user must still be able to click, Alt+Tab and kill the script.
;
;  Capture is a best effort, not a requirement. It is what lets the click be
;  CONSUMED rather than also landing on whatever is underneath, but it cannot
;  be relied on to deliver the click: the live OnMove preview writes into the
;  owner's document sixty times a second, and any focus that moves there takes
;  the capture with it. So the loop reads the physical buttons itself. Losing
;  capture is never a reason to cancel -- doing that turned every click into a
;  cancel, because the click was what moved the focus.
;
;  The button poll is armed only after the button has been seen UP, so the
;  release that opened the picker cannot be mistaken for a pick.
;
;  Escape works by two independent paths: the loop reads the key directly, and
;  the window handles WM_KEYDOWN when it does have focus.
;
;  opts: {Zoom: 8, Size: 168, Grid: true, Owner: hwnd, Info: true,
;         OnMove: fn(hex, x, y), OnPick: fn(hex, x, y)}
; =============================================================================
class AxScreenPick {
    ; a rich component with no markup of its own: it registers so the layer
    ; can list it, and installs win.PickScreenColor() on every AxWindow
    static _reg := AxRich.Register("ScreenPick", "",
        (*) => AxRich.WindowMethod("PickScreenColor",
            (win, opts := "") => AxScreenPick.Color(AxScreenPick._Owned(win, opts))))
    static _Owned(win, opts) {
        o := {Owner: AxRich.Owner(win)}
        if IsObject(opts)
            for k, v in opts.OwnProps()
                o.%k% := v
        return o
    }
    static Steps := [2, 3, 4, 6, 8, 12, 16, 24, 32]
    static _live := ""                 ; the session currently on screen

    static Color(opts := "") {
        if IsObject(AxScreenPick._live)                 ; never two at once
            return ""
        o := (n, d := "") => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        s := {Zoom: o("Zoom", 8), Size: o("Size", 168), Grid: o("Grid", true),
              Info: o("Info", true), OnMove: o("OnMove", ""), OnPick: o("OnPick", ""),
              Hex: "", X: 0, Y: 0, Done: false, Result: "",
              Owner: o("Owner", 0), T0: A_TickCount}
        s.InfoH := s.Info ? 44 : 0
        AxScreenPick._live := s
        try
            return AxScreenPick._Run(s)
        finally
            AxScreenPick._live := ""
    }

    ; ---------------------------------------------------------------- private
    static _Run(s) {
        ; No WS_EX_NOACTIVATE and no NoActivate: this window has to be the
        ; foreground one or SetCapture below is limited to its own rectangle.
        g := s.Gui := Gui("-Caption +AlwaysOnTop +ToolWindow")
        g.BackColor := "101010"
        g.Show("x-4000 y-4000 w" s.Size " h" (s.Size + s.InfoH))
        s.Hwnd := g.Hwnd
        try WinActivate("ahk_id " s.Hwnd)
        AxScreenPick._Round(s.Hwnd, s.Size, s.Size + s.InfoH, 10)
        s.Cursor := DllCall("user32\LoadCursorW", "Ptr", 0, "Ptr", 32515, "Ptr")    ; IDC_CROSS

        msgs := [0x200, 0x20A, 0x201, 0x202, 0x204, 0x20, 0x8, 0x100]               ; MOUSEMOVE, WHEEL, LBTN, RBTN, SETCURSOR, KILLFOCUS, KEYDOWN
        route := ObjBindMethod(AxScreenPick, "_Msg")
        for m in msgs
            OnMessage(m, route)
        DllCall("user32\SetCapture", "Ptr", s.Hwnd)

        tick := ObjBindMethod(AxScreenPick, "_Tick", s)
        SetTimer(tick, 16)
        try {
            armed := false          ; wait for the button to come up first
            while !s.Done {
                Sleep(10)
                if (GetKeyState("Escape", "P") || !WinExist("ahk_id " s.Hwnd)) {
                    s.Done := true, s.Result := ""
                    break
                }
                down := GetKeyState("LButton", "P")
                if !down
                    armed := true
                else if armed {                           ; a fresh press: take it
                    AxScreenPick._Take(s)
                    break
                }
                if (armed && GetKeyState("RButton", "P")) {
                    s.Result := "", s.Done := true
                    break
                }
                ; Hold capture where we can, so the click is swallowed instead
                ; of also landing on the window underneath -- but never treat
                ; losing it as a cancel. The click is often the very thing that
                ; moves the focus, so cancelling on loss cancelled every pick.
                if (DllCall("user32\GetCapture", "Ptr") != s.Hwnd)
                    DllCall("user32\SetCapture", "Ptr", s.Hwnd)
                if (A_TickCount - s.T0 > 180000)          ; nothing runs forever
                    s.Done := true, s.Result := ""
            }
        } finally {
            SetTimer(tick, 0)
            DllCall("user32\ReleaseCapture")
            for m in msgs
                OnMessage(m, route, 0)
            ; the owner first, then the magnifier goes: destroyed while it was
            ; still the active window, Windows handed the activation to some
            ; other program and the owner flickered behind it until activated
            if s.Owner
                try WinActivate("ahk_id " s.Owner)
            try g.Destroy()
        }
        if (s.Result != "" && s.OnPick) {
            cb := s.OnPick                       ; a local: s.OnPick(...) would pass s in
            try cb(s.Result, s.X, s.Y)
        }
        return s.Result
    }
    static _Msg(wParam, lParam, msg, hwnd) {
        s := AxScreenPick._live
        if (!IsObject(s) || hwnd != s.Hwnd)
            return
        switch msg {
        case 0x20:                                     ; WM_SETCURSOR
            DllCall("user32\SetCursor", "Ptr", s.Cursor)
            return 1
        case 0x20A:                                    ; WM_MOUSEWHEEL
            d := (wParam >> 16) & 0xFFFF
            AxScreenPick._Zoom(s, (d > 0x7FFF ? d - 0x10000 : d) > 0 ? 1 : -1)
            return 0
        case 0x202:                                    ; WM_LBUTTONUP: take it
            AxScreenPick._Take(s)
            return 0
        case 0x204:                                    ; WM_RBUTTONDOWN: cancel
            s.Result := "", s.Done := true
            return 0
        case 0x201:
            return 0
        case 0x100:                                    ; WM_KEYDOWN
            if (wParam = 0x1B)                         ; VK_ESCAPE
                s.Result := "", s.Done := true
            else if (wParam = 0x0D || wParam = 0x20)   ; Enter / Space accept
                AxScreenPick._Take(s)
            return 0
        case 0x8:                                      ; WM_KILLFOCUS: capture lost
            return 0
        }
    }
    ; Read the pixel now rather than trusting the last frame. The magnifier
    ; samples on a 16ms timer and the loop polls on a 10ms one, so the cached
    ; value can be a frame behind the cursor -- which is exactly how a pick
    ; comes back as the colour next to the one that was pointed at.
    static _Take(s) {
        if (!IsObject(s) || s.Done)
            return
        pt := Buffer(8, 0)
        DllCall("GetCursorPos", "Ptr", pt)
        x := NumGet(pt, 0, "Int"), y := NumGet(pt, 4, "Int")
        hex := AxScreenPick._At(x, y)
        s.X := x, s.Y := y
        s.Result := (hex != "") ? hex : s.Hex
        s.Done := true
    }
    static _At(x, y) {
        dc := DllCall("GetDC", "Ptr", 0, "Ptr")
        bgr := DllCall("gdi32\GetPixel", "Ptr", dc, "Int", x, "Int", y, "UInt")
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", dc)
        return (bgr = 0xFFFFFFFF) ? "" : AxSys.ColorRefToHex(bgr)
    }
    static _Zoom(s, dir) {
        steps := AxScreenPick.Steps, at := 1
        for i, v in steps
            if (v <= s.Zoom)
                at := i
        at := Min(steps.Length, Max(1, at + dir))
        s.Zoom := steps[at]
    }
    ; one frame: blit the screen through the magnifier, draw grid + readout
    static _Tick(s, *) {
        static SRCCOPY := 0x00CC0020
        if s.Done
            return
        pt := Buffer(8, 0)
        DllCall("GetCursorPos", "Ptr", pt)
        mx := NumGet(pt, 0, "Int"), my := NumGet(pt, 4, "Int")
        s.X := mx, s.Y := my
        size := s.Size, zoom := s.Zoom
        src := Max(2, size // zoom)                       ; screen pixels sampled
        src += (Mod(src, 2) ? 0 : 1)                      ; odd, so one pixel is dead centre
        half := src // 2

        hScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        bgr := DllCall("gdi32\GetPixel", "Ptr", hScreen, "Int", mx, "Int", my, "UInt")
        if (bgr != 0xFFFFFFFF)
            s.Hex := AxSys.ColorRefToHex(bgr)
        h := size + s.InfoH
        hWin := DllCall("GetDC", "Ptr", s.Hwnd, "Ptr")
        mem := DllCall("gdi32\CreateCompatibleDC", "Ptr", hWin, "Ptr")
        bmp := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", hWin, "Int", size, "Int", h, "Ptr")
        old := DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", bmp, "Ptr")

        DllCall("gdi32\SetStretchBltMode", "Ptr", mem, "Int", 3)          ; COLORONCOLOR = no smoothing
        DllCall("gdi32\StretchBlt", "Ptr", mem, "Int", 0, "Int", 0, "Int", src * zoom, "Int", src * zoom,
                "Ptr", hScreen, "Int", mx - half, "Int", my - half, "Int", src, "Int", src, "UInt", SRCCOPY)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hScreen)

        if (s.Grid && zoom >= 6)
            AxScreenPick._Grid(mem, src, zoom)
        AxScreenPick._CentreCell(mem, half * zoom, half * zoom, zoom, s.Hex)
        if s.Info
            AxScreenPick._Info(mem, s, size, h)
        AxScreenPick._Frame(mem, size, h)

        DllCall("gdi32\BitBlt", "Ptr", hWin, "Int", 0, "Int", 0, "Int", size, "Int", h,
                "Ptr", mem, "Int", 0, "Int", 0, "UInt", SRCCOPY)
        DllCall("gdi32\SelectObject", "Ptr", mem, "Ptr", old)
        DllCall("gdi32\DeleteObject", "Ptr", bmp)
        DllCall("gdi32\DeleteDC", "Ptr", mem)
        DllCall("ReleaseDC", "Ptr", s.Hwnd, "Ptr", hWin)

        AxScreenPick._Follow(s, mx, my, half)
        if s.OnMove {
            cb := s.OnMove
            try cb(s.Hex, mx, my)
        }
    }
    ; keep the window clear of the pixels it is sampling, and on screen
    static _Follow(s, mx, my, half) {
        gapX := half + 18, w := s.Size, h := s.Size + s.InfoH
        x := mx + gapX, y := my + gapX
        MonitorGetWorkArea(AxScreenPick._MonAt(mx, my), &l, &t, &r, &b)
        if (x + w > r)
            x := mx - gapX - w
        if (y + h > b)
            y := my - gapX - h
        x := Min(r - w, Max(l, x)), y := Min(b - h, Max(t, y))
        if (!s.HasOwnProp("PX") || s.PX != x || s.PY != y) {
            s.PX := x, s.PY := y
            DllCall("SetWindowPos", "Ptr", s.Hwnd, "Ptr", -1, "Int", x, "Int", y,
                    "Int", 0, "Int", 0, "UInt", 0x0215)                  ; NOSIZE|NOACTIVATE|SHOWWINDOW
        }
    }
    static _MonAt(x, y) {
        loop MonitorGetCount()
            if (MonitorGet(A_Index, &l, &t, &r, &b) && x >= l && x < r && y >= t && y < b)
                return A_Index
        return MonitorGetPrimary()
    }
    static _Grid(hdc, src, zoom) {
        pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", 1, "UInt", 0x303030, "Ptr")
        old := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
        len := src * zoom
        loop src + 1 {
            p := (A_Index - 1) * zoom
            DllCall("gdi32\MoveToEx", "Ptr", hdc, "Int", p, "Int", 0, "Ptr", 0)
            DllCall("gdi32\LineTo", "Ptr", hdc, "Int", p, "Int", len)
            DllCall("gdi32\MoveToEx", "Ptr", hdc, "Int", 0, "Int", p, "Ptr", 0)
            DllCall("gdi32\LineTo", "Ptr", hdc, "Int", len, "Int", p)
        }
        DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", old)
        DllCall("gdi32\DeleteObject", "Ptr", pen)
    }
    ; ring the pixel actually under the cursor, in black then white so it
    ; stays visible over any colour
    static _CentreCell(hdc, x, y, zoom, hex) {
        for i, col in [0x000000, 0xFFFFFF] {
            pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", 1, "UInt", col, "Ptr")
            oldP := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
            oldB := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr",
                            DllCall("gdi32\GetStockObject", "Int", 5, "Ptr"), "Ptr")   ; NULL_BRUSH
            d := i - 1
            DllCall("gdi32\Rectangle", "Ptr", hdc, "Int", x - d, "Int", y - d,
                    "Int", x + zoom + d, "Int", y + zoom + d)
            DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", oldB)
            DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", oldP)
            DllCall("gdi32\DeleteObject", "Ptr", pen)
        }
    }
    static _Info(hdc, s, w, h) {
        top := h - s.InfoH
        AxScreenPick._Fill(hdc, 0, top, w, h, 0x181818)
        c := AxSys.HexToRgb(s.Hex)
        AxScreenPick._Fill(hdc, 8, top + 9, 34, top + 35, AxSys.ColorRef(s.Hex = "" ? "#000000" : s.Hex))
        AxScreenPick._Fill(hdc, 8, top + 9, 34, top + 10, 0x000000)      ; hairline top
        AxScreenPick._Text(hdc, 48, top + 5, w - 54, 18, s.Hex, 0xF0F0F0, 15, true)
        AxScreenPick._Text(hdc, 48, top + 23, w - 54, 16,
            c.R "," c.G "," c.B "   " s.X "," s.Y "   " s.Zoom "x", 0x9A9A9A, 12)
    }
    static _Frame(hdc, w, h) {
        for i, col in [0x000000, 0x505050] {
            pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", 1, "UInt", col, "Ptr")
            oldP := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
            oldB := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr",
                            DllCall("gdi32\GetStockObject", "Int", 5, "Ptr"), "Ptr")
            d := i - 1
            DllCall("gdi32\Rectangle", "Ptr", hdc, "Int", d, "Int", d, "Int", w - d, "Int", h - d)
            DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", oldB)
            DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", oldP)
            DllCall("gdi32\DeleteObject", "Ptr", pen)
        }
    }
    static _Fill(hdc, x1, y1, x2, y2, colorref) {
        rc := Buffer(16, 0)
        NumPut("Int", x1, "Int", y1, "Int", x2, "Int", y2, rc)
        br := DllCall("gdi32\CreateSolidBrush", "UInt", colorref, "Ptr")
        DllCall("user32\FillRect", "Ptr", hdc, "Ptr", rc, "Ptr", br)
        DllCall("gdi32\DeleteObject", "Ptr", br)
    }
    static _Text(hdc, x, y, w, h, text, colorref, size, bold := false) {
        static fonts := Map()
        key := size "|" (bold ? 1 : 0)
        if !fonts.Has(key)
            fonts[key] := DllCall("gdi32\CreateFontW", "Int", -size, "Int", 0, "Int", 0, "Int", 0,
                "Int", bold ? 700 : 400, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1, "UInt", 0,
                "UInt", 0, "UInt", 4, "UInt", 0, "WStr", "Segoe UI", "Ptr")
        old := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", fonts[key], "Ptr")
        DllCall("gdi32\SetBkMode", "Ptr", hdc, "Int", 1)                  ; TRANSPARENT
        DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", colorref)
        rc := Buffer(16, 0)
        NumPut("Int", x, "Int", y, "Int", x + w, "Int", y + h, rc)
        DllCall("user32\DrawTextW", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", rc, "UInt", 0x20)  ; SINGLELINE
        DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", old)
    }
    static _Round(hwnd, w, h, r) {
        rgn := DllCall("gdi32\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", w + 1, "Int", h + 1,
                       "Int", r, "Int", r, "Ptr")
        if rgn
            DllCall("user32\SetWindowRgn", "Ptr", hwnd, "Ptr", rgn, "Int", 1)
    }
}
