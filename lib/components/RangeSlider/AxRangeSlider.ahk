#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\RangeSlider\AxRangeSlider.css, AX_COMPONENTS_RANGESLIDER_AXRANGESLIDER_CSS

; =============================================================================
;  AxRangeSlider -- a slider with two thumbs: a low end and a high end.
;
;    r := g.AddRangeSlider("vPrice Min=0 Max=1000 Step=10 Prefix=$", "200,800")
;    r.OnChange((ctl, v, *) => Filter(r.Component.Lo, r.Component.Hi))
;
;  The value is "lo,hi". Drag either thumb, or press on the track and the
;  nearer one jumps there; with a thumb focused, the arrows move it a step,
;  Page Up / Page Down ten, Home and End to the ends. Prefix and Suffix dress
;  the numbers shown over the thumbs; NoLabels leaves them off.
; =============================================================================
class AxRangeSlider {
    static _reg := AxRich.Register("RangeSlider", "components\RangeSlider\AxRangeSlider.css",
                                   (*) => AxRangeSlider._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddRangeSlider", (c, o := "", v := "") => AxRangeSlider._Add(c, o, v))
        AxWindow.RegisterValue("rangeslider",
            (w, el) => AxWindow._Attr(el, "data-value"),
            (w, el, v) => AxRangeSlider._SetVia(w, el, v))
        return true
    }
    static _SetVia(win, el, v) {
        c := AxRich.At(win, el.id)
        if IsObject(c)
            c.Value := v
        else
            el.setAttribute("data-value", v)
    }
    static _Add(c, opts, value) {
        o := c._Opt(opts, "rs")
        K := (k, d := "") => c._Kv(o, k, d)
        mn := IsNumber(K("min", 0)) ? K("min", 0) + 0 : 0
        mx := IsNumber(K("max", 100)) ? K("max", 100) + 0 : 100
        cfg := {Min: mn, Max: (mx > mn) ? mx : mn + 1, Step: IsNumber(K("step", 1)) && K("step", 1) > 0 ? K("step", 1) + 0 : 1,
                Prefix: K("prefix"), Suffix: K("suffix"), Labels: !(o.Flags.Has("nolabels") && o.Flags["nolabels"])}
        pair := AxRangeSlider.Pair(value != "" ? value : K("value"), cfg)
        cfg.Lo := pair[1], cfg.Hi := pair[2]
        if (o.W = "" && !o.Flags.Has("fill"))
            o.W := 280
        ctl := c._Reg(o, "RangeSlider", AxRangeSlider.Html(o.Id, cfg, c._Common(o, "")))
        c.G.OnReady((w) => AxRangeSlider(w, o.Id, cfg))
        return ctl
    }
    ; "20,80" / "20-80" / "20|80" / [20, 80] -> [lo, hi], snapped and in order
    static Pair(v, cfg) {
        if IsObject(v)
            a := v[1], b := v.Length > 1 ? v[2] : cfg.Max
        else if RegExMatch(String(v), "^\s*(-?[\d.]+)\s*(?:,|\||\.\.|\s-\s|-)\s*(-?[\d.]+)\s*$", &m)
            a := m[1], b := m[2]
        else
            a := cfg.Min, b := cfg.Max
        a := AxRangeSlider.Snap(IsNumber(a) ? a + 0 : cfg.Min, cfg)
        b := AxRangeSlider.Snap(IsNumber(b) ? b + 0 : cfg.Max, cfg)
        return (a <= b) ? [a, b] : [b, a]
    }
    static Snap(v, cfg) {
        v := Min(cfg.Max, Max(cfg.Min, v))
        n := Round((v - cfg.Min) / cfg.Step) * cfg.Step + cfg.Min
        n := Min(cfg.Max, Max(cfg.Min, n))
        return (n = Floor(n)) ? Integer(n) : Round(n, 6) + 0
    }
    static Pct(v, cfg) => Round((v - cfg.Min) * 100 / (cfg.Max - cfg.Min), 3)
    static Label(v, cfg) => cfg.Prefix v cfg.Suffix
    static Html(id, cfg, attrs := "") {
        E := (x) => AxWindow._Esc(x)
        cls := "axrs" (cfg.Labels ? " labels" : "")
        if (attrs != "") {
            n := 0
            a := RegExReplace(attrs, 'S)class="([^"]*)"', 'class="' cls ' $1"', &n)
            if !n
                a .= ' class="' cls '"'
        } else
            a := ' id="' E(id) '" class="' cls '"'
        pa := AxRangeSlider.Pct(cfg.Lo, cfg), pb := AxRangeSlider.Pct(cfg.Hi, cfg)
        lab := (v) => cfg.Labels ? '<span class="axrs-lbl">' E(AxRangeSlider.Label(v, cfg)) '</span>' : ""
        return '<div' a ' data-role="rangeslider" data-value="' cfg.Lo "," cfg.Hi '">'
             . '<div class="axrs-t" id="' E(id) '_t"><div class="axrs-rail"></div>'
             . '<div class="axrs-fill" id="' E(id) '_f" style="left:' pa '%;width:' (pb - pa) '%"></div>'
             . '<span class="axrs-th" id="' E(id) '_a" tabindex="0" style="left:' pa '%">' lab(cfg.Lo) '</span>'
             . '<span class="axrs-th" id="' E(id) '_b" tabindex="0" style="left:' pb '%">' lab(cfg.Hi) '</span>'
             . '</div><div class="axrs-ends"><span>' E(AxRangeSlider.Label(cfg.Min, cfg)) '</span>'
             . '<span class="axrs-hi">' E(AxRangeSlider.Label(cfg.Max, cfg)) '</span></div></div>'
    }

    __New(win, id, cfg) {
        this.W := win, this.Id := id, this.Cfg := cfg
        this._cbs := [], this._which := "", this._rect := ""
        AxRich.Bind(win, id, this)
        win.On("mousedown", id "_t", (el, ev) => this._Down(ev))
        win.On("keydown", id "_a", (el, ev) => this._Key("a", ev))
        win.On("keydown", id "_b", (el, ev) => this._Key("b", ev))
    }
    Lo => this.Cfg.Lo
    Hi => this.Cfg.Hi
    Value {
        get => this.Cfg.Lo "," this.Cfg.Hi
        set {
            p := AxRangeSlider.Pair(value, this.Cfg)
            this.Set(p[1], p[2], false)
        }
    }
    OnChange(fn) {
        this._cbs.Push(fn)
        return this
    }
    Set(lo, hi, fire := true) {
        lo := AxRangeSlider.Snap(lo, this.Cfg), hi := AxRangeSlider.Snap(hi, this.Cfg)
        if (lo > hi)
            tmp := lo, lo := hi, hi := tmp
        if (lo = this.Cfg.Lo && hi = this.Cfg.Hi)
            return this
        this.Cfg.Lo := lo, this.Cfg.Hi := hi
        this._Paint()
        if fire {
            v := this.Value
            for fn in this._cbs.Clone()
                try fn(v, this)
            try this.W._FireValue(this.W.El(this.Id), v)
        }
        return this
    }
    _Paint() {
        w := this.W, id := this.Id, c := this.Cfg
        pa := AxRangeSlider.Pct(c.Lo, c), pb := AxRangeSlider.Pct(c.Hi, c)
        try {
            w.El(id "_f").style.left := pa "%"
            w.El(id "_f").style.width := (pb - pa) "%"
            w.El(id "_a").style.left := pa "%"
            w.El(id "_b").style.left := pb "%"
            if c.Labels {
                w.El(id "_a").innerHTML := '<span class="axrs-lbl">' AxWindow._Esc(AxRangeSlider.Label(c.Lo, c)) '</span>'
                w.El(id "_b").innerHTML := '<span class="axrs-lbl">' AxWindow._Esc(AxRangeSlider.Label(c.Hi, c)) '</span>'
            }
            w.El(id).setAttribute("data-value", c.Lo "," c.Hi)
        }
    }
    _At(x) {
        r := this._rect
        return this.Cfg.Min + (this.Cfg.Max - this.Cfg.Min) * Min(1, Max(0, (x - r.L) / r.W))
    }
    _Down(ev) {
        try {
            r := this.W.El(this.Id "_t").getBoundingClientRect()
            this._rect := {L: r.left, W: Max(1, r.right - r.left)}
            x := ev.clientX
        } catch
            return
        v := this._At(x)
        src := ""
        try src := ev.srcElement.id
        ; the thumb pressed, or the nearer one; at a tie, the one the value
        ; would move away from -- so two thumbs on one spot still come apart
        if (src = this.Id "_a" || src = this.Id "_b")
            this._which := SubStr(src, -1)
        else
            this._which := (Abs(v - this.Cfg.Lo) < Abs(v - this.Cfg.Hi)) ? "a"
                         : (Abs(v - this.Cfg.Lo) > Abs(v - this.Cfg.Hi)) ? "b" : (v < this.Cfg.Lo ? "a" : "b")
        try this.W.El(this.Id "_" this._which).focus()
        this._Move(x)
        mv := (x, y) => this._Move(x)
        this.W.PointerCapture(mv, mv)
        try ev.returnValue := false
    }
    _Move(x) {
        v := this._At(x)
        if (this._which = "a")
            this.Set(Min(v, this.Cfg.Hi), this.Cfg.Hi)
        else
            this.Set(this.Cfg.Lo, Max(v, this.Cfg.Lo))
    }
    _Key(which, ev) {
        try k := ev.keyCode
        catch
            return
        c := this.Cfg, st := c.Step
        cur := (which = "a") ? c.Lo : c.Hi
        switch k {
        case 37, 40: nv := cur - st
        case 39, 38: nv := cur + st
        case 33:     nv := cur + st * 10
        case 34:     nv := cur - st * 10
        case 36:     nv := (which = "a") ? c.Min : c.Lo
        case 35:     nv := (which = "b") ? c.Max : c.Hi
        default:     return
        }
        if (which = "a")
            this.Set(Min(nv, c.Hi), c.Hi)
        else
            this.Set(c.Lo, Max(nv, c.Lo))
        try ev.returnValue := false
    }
}
