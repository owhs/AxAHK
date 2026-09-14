#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
;@Ahk2Exe-AddResource %U_AxLib%\components\Gauge\AxGauge.css, AX_COMPONENTS_GAUGE_AXGAUGE_CSS

; =============================================================================
;  AxGauge.ahk -- a dial that shows one number.
;
;      g.AddGauge("vcpu w120 Max=100 Ticks", 42)
;      cpu.Value := 73
;
;  This is the worked example for components\README.md: the smallest thing
;  that is a complete pack. It registers itself, brings its own stylesheet,
;  adds one method to AxGui, and carries a manifest so the studio puts it in
;  the toolbox. Nothing in the core or in the studio knows it exists.
;
;  The dial is drawn with divs and borders, not SVG: Trident will not animate
;  an SVG stroke-dasharray, but it will rotate a half-ring, and a half-ring
;  rotated 0..180 degrees is a gauge. The rings are borders round nothing, so
;  the middle is a real hole: whatever the gauge sits on -- the page, a card,
;  a tinted panel -- shows through it.
; =============================================================================

class AxGauge {
    static _reg := AxRich.Register("Gauge", "components\Gauge\AxGauge.css", (*) => (
        AxRich.AddMethod("AddGauge", (c, a*) => AxGauge._Add(c, a*)),
        ; ctl.Value and g.Value(id) read and move the dial, as on any control
        AxWindow.RegisterValue("gauge",
            (w, el) => AxWindow._Attr(el, "data-value"),
            (w, el, v) => AxGauge.Value(w, el.id, v))))

    ; g.AddGauge(options, value)
    static _Add(container, opts := "", value := "") {
        g := container.G
        o := container._Opt(opts, "gauge")
        AxRich.Use(g, "Gauge")
        v := (value = "") ? 0 : value
        max := o.Kv.Has("max") ? o.Kv["max"] : 100
        html := AxGauge.Html(o.Id, {Value: v, Max: max, Ticks: o.Flags.Has("ticks"), Width: o.W}, container._Common(o, ""))
        return container._Reg(o, "Gauge", html)
    }

    ; The markup, so the same dial can be dropped into a page that was not
    ; built with AxGui.
    static Html(id, opts, attrs := "") {
        v := opts.HasOwnProp("Value") ? opts.Value : 0
        max := opts.HasOwnProp("Max") ? opts.Max : 100
        deg := AxGauge._Deg(v, max)
        cls := "gauge" (opts.HasOwnProp("Ticks") && opts.Ticks ? " ticks" : "")
        ; the ring is 18% of the width: the stylesheet has it for the usual
        ; 120px, and a gauge of another width says its own
        w := (opts.HasOwnProp("Width") && IsNumber(opts.Width)) ? opts.Width : 0
        ; (not Max(): max is this function's own local, the gauge's top value)
        bw := (w && w != 120) ? ' style="border-width:' (w < 12 ? 2 : Round(w * 0.18)) 'px"' : ""
        if (attrs != "") {
            n := 0
            a := RegExReplace(attrs, 'S)class="([^"]*)"', 'class="' cls ' $1"', &n)
            if !n
                a .= ' class="' cls '"'
        } else
            a := ' id="' AxWindow._Esc(id) '" class="' cls '"'
        return '<div' a ' data-role="gauge" data-value="' AxWindow._Esc(v) '" data-max="' AxWindow._Esc(max) '">'
             . '<div class="gauge-face"><div class="gauge-track"><i' bw '></i></div>'
             . '<div class="gauge-fill" style="transform:rotate(' deg 'deg);-ms-transform:rotate(' deg 'deg)">'
             . '<div class="gauge-ring"><i' bw '></i></div></div></div>'
             . '<div class="gauge-text">' AxWindow._Esc(v) '</div></div>'
    }
    static _Deg(v, max) {
        m := (max = 0) ? 100 : max
        f := v / m
        f := (f < 0) ? 0 : (f > 1) ? 1 : f
        return Round(f * 180)
    }

    ; Value(win, id) reads it, Value(win, id, n) sets it -- what ctl.Value and
    ; g.Value(id) come through to, by the gauge's data-role.
    static Value(win, id, value := unset) {
        el := win.El(id)
        if !IsObject(el)
            return ""
        if !IsSet(value)
            return AxWindow._Attr(el, "data-value")
        max := AxWindow._Attr(el, "data-max")
        el.setAttribute("data-value", value)
        deg := AxGauge._Deg(value, max = "" ? 100 : max)
        try {
            fill := el.querySelector(".gauge-fill")
            fill.style.transform := "rotate(" deg "deg)"
            fill.style.msTransform := "rotate(" deg "deg)"
            AxWindow._SetText(el.querySelector(".gauge-text"), value)
        }
        return win
    }
}
