#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Stat\AxStat.css, AX_COMPONENTS_STAT_AXSTAT_CSS

; =============================================================================
;  AxStat -- one number that matters, with where it is heading.
;
;    s := g.AddStat('vSales Label=Revenue Trend=+12% Note="vs last month" Spark="3,5,4,8,6,9"', "$24,300")
;    s.Value := "$25,100"          s.SetTrend("-3%")          s.Push(11)
;
;  Label is the small line on top, Icon a glyph beside it, Trend a pill that
;  is green going up and red going down (Good=down turns that round -- for
;  errors, costs, wait times), Note a line under the number, Spark a line of
;  numbers drawn as a sparkline under it all. Push(n) adds a point to the
;  sparkline and lets the oldest go.
; =============================================================================
class AxStat {
    static _reg := AxRich.Register("Stat", "components\Stat\AxStat.css", (*) => AxStat._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddStat", (c, o := "", v := "") => AxStat._Add(c, o, v))
        AxWindow.RegisterValue("stat",
            (w, el) => AxWindow._Attr(el, "data-value"),
            (w, el, v) => AxStat._SetVia(w, el, v))
        return true
    }
    static _SetVia(win, el, v) {
        c := AxRich.At(win, el.id)
        if IsObject(c)
            c.Value := v
    }
    static _Add(c, opts, value) {
        o := c._Opt(opts, "stat")
        cfg := {Label: c._Kv(o, "label", ""), Icon: c._Kv(o, "icon", ""), Trend: c._Kv(o, "trend", ""),
                Note: c._Kv(o, "note", ""), Spark: AxStat.Nums(c._Kv(o, "spark", "")),
                GoodDown: StrLower(c._Kv(o, "good", "up")) = "down", Value: String(value)}
        if (o.W = "" && !o.Flags.Has("fill"))
            o.W := 220
        ctl := c._Reg(o, "Stat", AxStat.Html(o.Id, cfg, c._Common(o, "")))
        c.G.OnReady((w) => AxStat(w, o.Id, cfg))
        return ctl
    }
    static Nums(v) {
        out := []
        for x in (IsObject(v) ? v : StrSplit(String(v), [",", " ", "|"]))
            if IsNumber(Trim(x))
                out.Push(Trim(x) + 0)
        return out
    }
    ; up, down or flat, from the sign the trend is written with
    static Way(t) {
        t := Trim(String(t))
        if (t = "")
            return ""
        c := SubStr(t, 1, 1)
        if (c = "+" || c = Chr(0x2191))
            return "up"
        if (c = "-" || c = Chr(0x2212) || c = Chr(0x2193))
            return "down"
        n := RegExReplace(t, "[^0-9.]")
        return (IsNumber(n) && n > 0) ? "up" : "flat"
    }
    static Html(id, cfg, attrs := "") {
        E := (x) => AxWindow._Esc(x)
        cls := "axstat"
        if (attrs != "") {
            n := 0
            a := RegExReplace(attrs, 'S)class="([^"]*)"', 'class="' cls ' $1"', &n)
            if !n
                a .= ' class="' cls '"'
        } else
            a := ' id="' E(id) '" class="' cls '"'
        return '<div' a ' data-role="stat" data-value="' E(cfg.Value) '"><div id="' E(id) '_r">' AxStat.Inner(id, cfg) '</div></div>'
    }
    static Inner(id, cfg) {
        E := (x) => AxWindow._Esc(x)
        way := AxStat.Way(cfg.Trend)
        good := (way = "flat" || way = "") ? "" : ((way = "up") != cfg.GoodDown) ? " good" : " bad"
        glyph := (way = "up") ? "E74A" : (way = "down") ? "E74B" : "E738"
        h := '<div class="axstat-top"><span class="axstat-lbl">'
          .  (cfg.Icon != "" ? '<span class="ico">&#x' E(cfg.Icon) ';</span>' : "") E(cfg.Label) '</span>'
          .  (cfg.Trend != "" ? '<span class="axstat-tr ' way good '"><span class="ico">&#x' glyph ';</span>' E(LTrim(cfg.Trend, "+")) '</span>' : "")
          .  '</div><div class="axstat-v">' E(cfg.Value) '</div>'
          .  (cfg.Note != "" ? '<div class="axstat-note">' E(cfg.Note) '</div>' : "")
        if (cfg.Spark.Length >= 2)
            h .= '<div class="axstat-sp">' AxStat.Spark(cfg.Spark, way good) '</div>'
        return h
    }
    ; a sparkline: the line, and a soft fill under it
    static Spark(nums, cls := "") {
        w := 200, h := 36, pad := 3
        lo := nums[1], hi := nums[1]
        for v in nums
            lo := Min(lo, v), hi := Max(hi, v)
        span := (hi - lo) ? (hi - lo) : 1
        pts := ""
        for i, v in nums {
            x := Round((i - 1) * w / (nums.Length - 1), 1)
            y := Round(pad + (h - 2 * pad) * (1 - (v - lo) / span), 1)
            pts .= (pts = "" ? "" : " ") x "," y
        }
        return '<svg class="axstat-svg ' cls '" width="100%" height="' h '" viewBox="0 0 ' w ' ' h '" preserveAspectRatio="none">'
             . '<polygon class="axstat-area" points="0,' h ' ' pts ' ' w ',' h '"/>'
             . '<polyline class="axstat-line" points="' pts '"/></svg>'
    }

    __New(win, id, cfg) {
        this.W := win, this.Id := id, this.Cfg := cfg
        AxRich.Bind(win, id, this)
    }
    Value {
        get => this.Cfg.Value
        set {
            this.Cfg.Value := String(value)
            this.Render()
        }
    }
    SetTrend(t) {
        this.Cfg.Trend := t
        return this.Render()
    }
    SetNote(t) {
        this.Cfg.Note := t
        return this.Render()
    }
    SetSpark(nums) {
        this.Cfg.Spark := AxStat.Nums(nums)
        return this.Render()
    }
    Push(n, keep := 0) {
        this.Cfg.Spark.Push(n + 0)
        keep := keep ? keep : Max(12, this.Cfg.Spark.Length - 1)
        while (this.Cfg.Spark.Length > keep)
            this.Cfg.Spark.RemoveAt(1)
        return this.Render()
    }
    Render() {
        try {
            this.W.El(this.Id "_r").innerHTML := AxStat.Inner(this.Id, this.Cfg)
            this.W.El(this.Id).setAttribute("data-value", this.Cfg.Value)
        }
        return this
    }
}
