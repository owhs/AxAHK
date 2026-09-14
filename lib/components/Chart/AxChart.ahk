#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Chart\AxChart.css, AX_COMPONENTS_CHART_AXCHART_CSS

; =============================================================================
;  AxChart -- numbers as a picture: bars, a line, an area or a donut.
;
;    c := g.AddChart('vsales Kind=bar Labels="Mon,Tue,Wed,Thu,Fri" h220',
;                    "Visits: 12,18,9,22,17`nSales: 4,7,3,9,6")
;    c.Value := "Visits: 3,5,8"      c.Push(14)       c.SetKind("line")
;
;  The data is text, one series per line (or ; between them), each an
;  optional  Name:  and then its numbers. Text rather than an object because
;  that is what a designer can type, what a binding can hand it
;  (chart.Value <- expr), and what g.Value("sales") gives back.
;
;  Options
;      Kind=bar|line|area|donut   bar is the default
;      Labels="a,b,c"             along the bottom (a donut: its slices)
;      Max=N                      the top of the scale; otherwise a round
;                                 number just above the largest value
;      Suffix="%"                 after every number it writes
;      Legend / NoLegend          a legend is shown for two series or more,
;                                 and for a donut; either way can be forced
;      NoAxis                     no numbers up the side, no grid
;      Numbers                    each bar or point carries its number
;
;  Bars, points and the grid are boxes placed by percentage, so they are
;  sharp at any size and follow the box when it is resized or set to fill the
;  height. A line is an SVG in the plot's own pixels, drawn again when the
;  plot changes size. Hovering a bar, a point or a slice names it.
; =============================================================================
class AxChart {
    static _reg := AxRich.Register("Chart", "components\Chart\AxChart.css", (*) => AxChart._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddChart", (c, o := "", v := "") => AxChart._Add(c, o, v))
        AxWindow.RegisterValue("chart",
            (w, el) => AxWindow._Attr(el, "data-value"),
            (w, el, v) => AxChart._SetVia(w, el, v))
        return true
    }
    static _SetVia(win, el, v) {
        c := AxRich.At(win, el.id)
        if IsObject(c)
            c.Value := v
    }
    static _Add(c, opts, data) {
        o := c._Opt(opts, "chart")
        kv := (k, d := "") => c._Kv(o, k, d)
        cfg := {Kind: StrLower(kv("kind", "bar")), Labels: AxChart.List(kv("labels")),
                Max: kv("max"), Suffix: kv("suffix"),
                Legend: o.Flags.Has("legend") ? 1 : o.Flags.Has("nolegend") ? 0 : -1,
                Axis: !o.Flags.Has("noaxis"), Values: o.Flags.Has("numbers"),
                Data: AxChart.Parse(data)}
        if (o.H = "")
            o.H := 220
        ctl := c._Reg(o, "Chart", AxChart.Html(o.Id, cfg, c._Common(o, "")))
        c.G.OnReady((w) => AxChart(w, o.Id, cfg))
        return ctl
    }

    ; --------------------------------------------------------------- data
    ; "Visits: 1,2,3`nSales: 4,5,6" -> [{Name: "Visits", Nums: [1,2,3]}, ...]
    static Parse(text) {
        out := []
        if IsObject(text) {                                  ; an array of arrays, or of numbers
            if (text is Array) && text.Length && !IsObject(text[1])
                return [{Name: "", Nums: AxChart.Nums(text)}]
            for s in text
                out.Push({Name: "", Nums: AxChart.Nums(s)})
            return out
        }
        for line in StrSplit(StrReplace(StrReplace(String(text), "`r", ""), ";", "`n"), "`n") {
            line := Trim(line)
            if (line = "")
                continue
            name := ""
            if RegExMatch(line, "^([^:0-9.\-+][^:]*):\s*(.*)$", &m)
                name := Trim(m[1]), line := m[2]
            out.Push({Name: name, Nums: AxChart.Nums(line)})
        }
        return out
    }
    static Nums(v) {
        out := []
        for x in (IsObject(v) ? v : StrSplit(String(v), [",", " ", "|"]))
            if IsNumber(Trim(x))
                out.Push(Trim(x) + 0)
        return out
    }
    static List(v) {
        out := []
        if (Trim(String(v)) = "")
            return out
        for x in StrSplit(String(v), InStr(v, "|") ? "|" : ",")
            out.Push(Trim(x))
        return out
    }
    ; the data back as the text it was given in
    static Text(data) {
        s := ""
        for ser in data {
            line := ""
            for n in ser.Nums
                line .= (line = "" ? "" : ",") AxChart.Num(n)
            s .= (s = "" ? "" : "`n") (ser.Name != "" ? ser.Name ": " : "") line
        }
        return s
    }
    static Num(n) {
        if !IsNumber(n)
            return String(n)
        if (Floor(n) = n)
            return String(Integer(n))
        return RTrim(RTrim(Format("{:.2f}", n), "0"), ".")
    }
    ; a round top for the scale: 1, 2, 2.5 or 5 times a power of ten
    static Nice(hi) {
        if (hi <= 0)
            return 1
        p := 10 ** Floor(Log(hi))
        for f in [1, 2, 2.5, 5, 10]
            if (f * p >= hi)
                return f * p
        return 10 * p
    }

    ; ------------------------------------------------------------- markup
    static Html(id, cfg, attrs := "") {
        E := (x) => AxWindow._Esc(x)
        cls := "axchart"
        if (attrs != "") {
            n := 0
            a := RegExReplace(attrs, 'S)class="([^"]*)"', 'class="' cls ' $1"', &n)
            if !n
                a .= ' class="' cls '"'
        } else
            a := ' id="' E(id) '" class="' cls '"'
        return '<div' a ' data-role="chart" data-value="' E(AxChart.Text(cfg.Data)) '">'
             . '<div class="axchart-in" id="' E(id) '_r">' AxChart.Inner(cfg) '</div></div>'
    }
    static Inner(cfg) {
        E := (x) => AxWindow._Esc(x)
        data := cfg.Data
        if !data.Length || !data[1].Nums.Length
            return '<div class="axchart-empty">No numbers yet</div>'
        legend := (cfg.Legend = 1) || (cfg.Legend = -1 && (data.Length > 1 || cfg.Kind = "donut"))
        leg := ""
        if legend {
            if (cfg.Kind = "donut") {
                for i, n in data[1].Nums
                    leg .= '<span class="axchart-key"><i class="s' AxChart.Slot(i) '"></i>'
                         . E(cfg.Labels.Has(i) ? cfg.Labels[i] : "Part " i) '</span>'
            } else
                for i, ser in data
                    leg .= '<span class="axchart-key"><i class="s' AxChart.Slot(i) '"></i>'
                         . E(ser.Name != "" ? ser.Name : "Series " i) '</span>'
            leg := '<div class="axchart-legend">' leg '</div>'
        }
        body := (cfg.Kind = "donut") ? AxChart.Donut(cfg) : AxChart.Plot(cfg)
        return '<div class="axchart-body' (legend ? " haslegend" : "") '">' body '</div>' leg
    }
    static Slot(i) => Mod(i - 1, 6) + 1
    static Plot(cfg) {
        E := (x) => AxWindow._Esc(x)
        data := cfg.Data, suf := cfg.Suffix
        count := 0, hi := 0, lo := 0
        for ser in data {
            count := Max(count, ser.Nums.Length)
            for n in ser.Nums
                hi := Max(hi, n), lo := Min(lo, n)
        }
        ; four steps up the side, each a round number
        top := (cfg.Max != "" && IsNumber(cfg.Max)) ? cfg.Max + 0 : 4 * AxChart.Nice(hi / 4)
        bot := (lo < 0) ? -4 * AxChart.Nice(-lo / 4) : 0
        span := (top - bot) ? (top - bot) : 1
        Y := (v) => Round(100 * (v - bot) / span, 3)            ; % up from the bottom
        h := ""
        ; the grid and the numbers up the side
        if cfg.Axis {
            axis := ""
            loop 5 {
                v := bot + span * (A_Index - 1) / 4
                p := Y(v)
                h .= '<div class="axchart-grid' (v = 0 ? " zero" : "") '" style="bottom:' p '%"></div>'
                axis .= '<div class="axchart-y" style="bottom:' p '%">' E(AxChart.Num(v) suf) '</div>'
            }
            h := '<div class="axchart-axis">' axis '</div>' h
        }
        plot := ""
        if (cfg.Kind = "line" || cfg.Kind = "area") {
            ; the line in the plot's own pixels, as far as they are known (the
            ; instance redraws it at the real size once the page is laid out);
            ; the points are boxes placed by percentage, so they stay round
            VW := cfg.HasOwnProp("VW") ? cfg.VW : 600, VH := cfg.HasOwnProp("VH") ? cfg.VH : 170
            svg := ""
            for si, ser in data {
                pts := "", dots := ""
                for i, n in ser.Nums {
                    x := (count > 1) ? Round(VW * (i - 1) / (count - 1), 1) : Round(VW / 2, 1)
                    yy := Round(VH - VH * Y(n) / 100, 1)
                    pts .= (pts = "" ? "" : " ") x "," yy
                    tip := (cfg.Labels.Has(i) ? cfg.Labels[i] ": " : "") (ser.Name != "" ? ser.Name " " : "") AxChart.Num(n) suf
                    dots .= '<div class="axchart-pt s' AxChart.Slot(si) '" style="left:' Round(100 * x / VW, 3) '%;bottom:' Y(n) '%"'
                          . ' data-tip="' E(tip) '">' (cfg.Values ? '<span>' E(AxChart.Num(n) suf) '</span>' : "") '</div>'
                }
                if (cfg.Kind = "area" && ser.Nums.Length > 1)
                    svg .= '<polygon class="axchart-area s' AxChart.Slot(si) '" points="0,' VH ' ' pts ' '
                         . ((count > 1) ? Round(VW * (ser.Nums.Length - 1) / (count - 1), 1) : Round(VW / 2, 1)) ',' VH '"/>'
                svg .= '<polyline class="axchart-line s' AxChart.Slot(si) '" points="' pts '"/>'
                plot .= dots
            }
            plot := '<svg class="axchart-svg" viewBox="0 0 ' VW ' ' VH '" preserveAspectRatio="none">' svg '</svg>' plot
        } else {
            ; bars: one group per label, one bar per series in it
            gw := 100 / Max(count, 1), ns := data.Length
            loop count {
                i := A_Index
                bars := ""
                for si, ser in data {
                    if !ser.Nums.Has(i)
                        continue
                    v := ser.Nums[i]
                    b := Y(Min(v, 0)), t := Y(Max(v, 0))
                    tip := (cfg.Labels.Has(i) ? cfg.Labels[i] ": " : "") (ser.Name != "" ? ser.Name " " : "") AxChart.Num(v) suf
                    ; the bars of one label share its middle two thirds
                    bars .= '<div class="axchart-bar s' AxChart.Slot(si) '" style="left:' Round(17 + 66 * (si - 1) / ns, 3) '%;width:'
                          . Round(66 / ns, 3) '%;bottom:' b '%;height:' Round(t - b, 3) '%" data-tip="' E(tip) '">'
                          . (cfg.Values ? '<span>' E(AxChart.Num(v) suf) '</span>' : "") '</div>'
                }
                plot .= '<div class="axchart-group" style="left:' Round(gw * (i - 1), 3) '%;width:' Round(gw, 3) '%">' bars '</div>'
            }
        }
        xl := ""
        if cfg.Labels.Length
            loop count {
                i := A_Index
                if !cfg.Labels.Has(i)
                    continue
                x := (cfg.Kind = "line" || cfg.Kind = "area")
                   ? ((count > 1) ? 100 * (i - 1) / (count - 1) : 50)
                   : (100 / count) * (i - 0.5)
                xl .= '<div class="axchart-x" style="left:' Round(x, 3) '%">' E(cfg.Labels[i]) '</div>'
            }
        return '<div class="axchart-plot' (cfg.Axis ? "" : " noaxis") (xl != "" ? "" : " nolabels") '">'
             . h '<div class="axchart-marks k-' (cfg.Kind = "area" ? "line" : cfg.Kind) '">' plot '</div>'
             . (xl != "" ? '<div class="axchart-xs">' xl '</div>' : "") '</div>'
    }
    ; a ring of slices; the total in the middle
    static Donut(cfg) {
        E := (x) => AxWindow._Esc(x)
        nums := cfg.Data[1].Nums, total := 0
        for n in nums
            total += Max(n, 0)
        if (total <= 0)
            return '<div class="axchart-empty">Nothing to share out</div>'
        r := 40, c := 2 * 3.14159265 * r, at := 0, rings := ""
        for i, n in nums {
            if (n <= 0)
                continue
            len := c * n / total
            tip := (cfg.Labels.Has(i) ? cfg.Labels[i] ": " : "") AxChart.Num(n) cfg.Suffix " (" Round(100 * n / total) "%)"
            rings .= '<circle class="axchart-slice s' AxChart.Slot(i) '" cx="50" cy="50" r="' r '"'
                   . ' stroke-dasharray="' Round(len, 3) ' ' Round(c - len, 3) '" stroke-dashoffset="' Round(-at, 3) '"'
                   . ' transform="rotate(-90 50 50)" data-tip="' E(tip) '"></circle>'
            at += len
        }
        return '<div class="axchart-donut"><svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid meet">'
             . '<circle class="axchart-track" cx="50" cy="50" r="' r '"/>' rings '</svg>'
             . '<div class="axchart-total"><b>' E(AxChart.Num(total) cfg.Suffix) '</b><span>total</span></div></div>'
    }

    ; ----------------------------------------------------------- instance
    __New(win, id, cfg) {
        this.W := win, this.Id := id, this.Cfg := cfg
        AxRich.Bind(win, id, this)
        this.Fit()
        ; a line is drawn in pixels, so a chart that changes size -- the
        ; window resized, a Grow box given its height -- is drawn again
        this._fit := ObjBindMethod(this, "Fit")
        SetTimer(this._fit, 400)
    }
    ; Redraw a line or an area when its plot is not the size it was drawn at.
    Fit() {
        if this.W.Closing {
            SetTimer(this._fit, 0)
            return
        }
        if !(this.Cfg.Kind = "line" || this.Cfg.Kind = "area")
            return
        try {
            p := this.W.El(this.Id "_r").querySelector(".axchart-marks")
            if !IsObject(p) || !p.offsetWidth
                return
            w := p.offsetWidth, h := p.offsetHeight
            if (Abs(w - (this.Cfg.HasOwnProp("VW") ? this.Cfg.VW : 600)) > 2
             || Abs(h - (this.Cfg.HasOwnProp("VH") ? this.Cfg.VH : 170)) > 2) {
                this.Cfg.VW := w, this.Cfg.VH := h
                this.Render()
            }
        }
    }
    ; the data, as text; setting it redraws
    Value {
        get => AxChart.Text(this.Cfg.Data)
        set {
            this.Cfg.Data := AxChart.Parse(value)
            this.Render()
        }
    }
    SetData(data) {
        this.Cfg.Data := AxChart.Parse(data)
        return this.Render()
    }
    SetLabels(labels) {
        this.Cfg.Labels := IsObject(labels) ? labels : AxChart.List(labels)
        return this.Render()
    }
    SetKind(kind) {
        this.Cfg.Kind := StrLower(kind)
        return this.Render()
    }
    ; one more number on a series, the oldest let go once there are `keep`
    ; (0: as many as there are labels, or 12); a live feed in one line
    Push(n, series := 1, keep := 0) {
        d := this.Cfg.Data
        while (d.Length < series)
            d.Push({Name: "", Nums: []})
        d[series].Nums.Push(n + 0)
        keep := keep ? keep : (this.Cfg.Labels.Length ? this.Cfg.Labels.Length : 12)
        while (d[series].Nums.Length > keep)
            d[series].Nums.RemoveAt(1)
        return this.Render()
    }
    Render() {
        try {
            this.W.El(this.Id "_r").innerHTML := AxChart.Inner(this.Cfg)
            this.W.El(this.Id).setAttribute("data-value", AxChart.Text(this.Cfg.Data))
        }
        return this
    }
}
