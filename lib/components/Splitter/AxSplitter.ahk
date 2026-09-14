#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
;@Ahk2Exe-AddResource %U_AxLib%\components\Splitter\AxSplitter.css, AX_COMPONENTS_SPLITTER_AXSPLITTER_CSS

; =============================================================================
;  AxSplitter.ahk — a divider you can drag, between two parts of a page.
;
;      g.AddSplitter("vsp1 Target=sidePane Min=140 Max=460")     ; vertical
;      g.AddSplitter("vsp2 Horizontal Target=topPane Min=80")    ; horizontal
;
;  The splitter resizes ONE element: the one named by Target, which is normally
;  the control just before it. A vertical splitter sets that element's width, a
;  horizontal one its height. Everything beside it keeps whatever the layout
;  gives it, so a `Fill` control on the other side takes up the slack — which
;  is what a two-pane arrangement wants and needs no second measurement.
;
;  Options
;      Target=id     the element to resize (default: the previous sibling)
;      Horizontal    drag up and down instead of left and right
;      Min= Max=     limits in px (default 60 and 4000)
;      Tip="..."     tooltip
;
;  Events: OnChange(fn) fires with the new size, once, when you let go.
;
;  ------------------------------------------------------------------ the drag
;  Trident delivers mousemove to the document sink, but AxWindow only forwards
;  it while its own drag-reorder or a slider is running, and never to a user
;  hook — so a component cannot simply listen for it. Rather than change the
;  core, the drag is a short polling timer: mousedown starts it, it reads the
;  cursor through GetCursorPos/ScreenToClient (which is DPI-correct, the same
;  conversion the components use for hit-testing), and it stops when the left
;  button comes up. At 60 a second that is a handful of DllCalls per frame and
;  no measurable cost, and it keeps this file a plugin rather than a patch.
; =============================================================================
class AxSplitter {
    static _reg := AxSplitter._Register()
    static _live := Map()                      ; hwnd -> the drag in progress

    static _Register() {
        return AxRich.Register("Splitter", "components\Splitter\AxSplitter.css", (*) => (
            AxRich.AddMethod("AddSplitter", (c, o := "", t := "") => AxSplitter._Add(c, o, t)),
            AxRich.WindowMethod("SplitterSize", (w, id, v := unset) => AxSplitter._Size(w, id, v?))))
    }

    ; --------------------------------------------------------------- markup
    static Html(id, cfg, attrs := "") {
        cls := "axsp " (cfg.Horizontal ? "horiz" : "vert")
        if (attrs != "") {
            n := 0
            a := RegExReplace(attrs, 'S)class="([^"]*)"', 'class="' cls ' $1"', &n)
            if !n
                a .= ' class="' cls '"'
        } else
            a := ' id="' AxWindow._Esc(id) '" class="' cls '"'
        return '<div' a ' data-role="splitter"'
             . ' data-target="' AxWindow._Esc(cfg.Target) '"'
             . ' data-axis="' (cfg.Horizontal ? "y" : "x") '"'
             . ' data-min="' cfg.Min '" data-max="' cfg.Max '"'
             . (cfg.Tip != "" ? ' data-tip="' AxWindow._Esc(cfg.Tip) '"' : "")
             . '><div class="grip"></div></div>'
    }

    ; ------------------------------------------------------------- AxGui add
    static _Add(container, opts, text) {
        o := container._Opt(opts, "sp")
        cfg := {Horizontal: o.Flags.Has("horizontal") || o.Flags.Has("horiz"),
                Target: container._Kv(o, "target"),
                Min: Integer(container._Kv(o, "min", 60)),
                Max: Integer(container._Kv(o, "max", 4000)),
                Tip: container._Kv(o, "tip")}
        c := container._Reg(o, "Splitter", AxSplitter.Html(o.Id, cfg, container._Common(o, "")))
        container.G.OnReady((w) => AxSplitter._Wire(w))
        return c
    }
    ; One set of hooks per window, however many splitters it has.
    static _Wire(win) {
        if win.HasOwnProp("_axspWired")
            return
        win._axspWired := true
        win.On("mousedown", "*", (el, ev) => AxSplitter._Down(win, el, ev))
    }

    ; ----------------------------------------------------------- the drag
    static _Down(win, el, ev) {
        sp := AxSplitter._Closest(win, el)
        if !sp
            return
        try {
            if !AxWindow._IsLeft(ev)
                return
        }
        tgt := AxSplitter._Target(win, sp)
        if !IsObject(tgt)
            return
        horiz := (AxWindow._Attr(sp, "data-axis") = "y")
        r := tgt.getBoundingClientRect()
        pt := AxSplitter._Cursor(win)
        d := {Win: win, El: sp, Target: tgt, Horiz: horiz,
              Start: horiz ? pt.Y : pt.X,
              Size: horiz ? (r.bottom - r.top) : (r.right - r.left),
              Min: Integer(AxWindow._Attr(sp, "data-min")),
              Max: Integer(AxWindow._Attr(sp, "data-max")),
              Now: 0}
        if (d.Min < 1)
            d.Min := 60
        if (d.Max < d.Min)
            d.Max := 4000
        d.Now := d.Size
        AxWindow._SetClass(sp, "dragging", true)
        win.BodyClass("axsp-dragging", true)
        win.BodyClass("axsp-row", horiz)
        AxSplitter._live[win.Gui.Hwnd] := d
        d.Timer := AxSplitter._TickFn(win.Gui.Hwnd)
        SetTimer(d.Timer, 16)
        try ev.returnValue := false
    }
    static _TickFn(hwnd) => (*) => AxSplitter._Tick(hwnd)
    static _Tick(hwnd) {
        if !AxSplitter._live.Has(hwnd)
            return
        d := AxSplitter._live[hwnd]
        if (!GetKeyState("LButton", "P") || d.Win.Closing) {
            AxSplitter._Up(hwnd)
            return
        }
        pt := AxSplitter._Cursor(d.Win)
        delta := (d.Horiz ? pt.Y : pt.X) - d.Start
        v := d.Size + delta
        v := Max(d.Min, Min(d.Max, Round(v)))
        if (v = d.Now)
            return
        d.Now := v
        try d.Target.style.%(d.Horiz ? "height" : "width")% := v "px"
    }
    static _Up(hwnd) {
        if !AxSplitter._live.Has(hwnd)
            return
        d := AxSplitter._live[hwnd]
        AxSplitter._live.Delete(hwnd)
        SetTimer(d.Timer, 0)
        try AxWindow._SetClass(d.El, "dragging", false)
        try {
            d.Win.BodyClass("axsp-dragging", false)
            d.Win.BodyClass("axsp-row", false)
        }
        try d.Win._FireValue(d.El, d.Now)
    }

    ; --------------------------------------------------------------- helpers
    ; The cursor in the page's own coordinates: screen -> client, then out of
    ; device pixels, which is the conversion the hit tests use.
    static _Cursor(win) {
        pt := Buffer(8, 0)
        try {
            DllCall("GetCursorPos", "Ptr", pt)
            DllCall("ScreenToClient", "Ptr", win.Gui.Hwnd, "Ptr", pt)
        }
        scale := A_ScreenDPI / 96
        return {X: NumGet(pt, 0, "Int") / scale, Y: NumGet(pt, 4, "Int") / scale}
    }
    static _Closest(win, el) {
        n := 0
        while (IsObject(el) && n++ < 12) {
            if (AxWindow._Attr(el, "data-role") = "splitter")
                return el
            try el := el.parentElement
            catch
                return ""
        }
        return ""
    }
    ; Target=id, or the element immediately before the splitter.
    static _Target(win, sp) {
        id := AxWindow._Attr(sp, "data-target")
        if (id != "") {
            el := win.El(id)
            if IsObject(el)
                return el
        }
        try {
            p := sp.previousSibling
            while (IsObject(p) && p.nodeType != 1)
                p := p.previousSibling
            return p
        }
        return ""
    }
    static _Size(win, id, v?) {
        sp := win.El(id)
        if !IsObject(sp)
            return 0
        tgt := AxSplitter._Target(win, sp)
        if !IsObject(tgt)
            return 0
        horiz := (AxWindow._Attr(sp, "data-axis") = "y")
        if IsSet(v) {
            try tgt.style.%(horiz ? "height" : "width")% := Round(v) "px"
            return win
        }
        r := tgt.getBoundingClientRect()
        return horiz ? (r.bottom - r.top) : (r.right - r.left)
    }
}
