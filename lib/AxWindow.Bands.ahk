#Requires AutoHotkey v2.0
; =============================================================================
;  AxWindow.Bands.ahk — a header band that is part of the title bar, a footer
;  pinned under the page, and CSS whose colours follow the look.
;
;      win.Header('<div class="hero">...</div>', {Tabs: "Tabs"})
;      win.Footer('<span>Hello</span><span class="btn" id="ok">OK</span>')
;
;  The window becomes a column -- the band, the page, the footer (and the
;  status bar under it) -- and the page gets whatever height is left, however
;  tall the band is at this width and whatever the stylesheet makes its
;  title bar. Nothing is measured; resizing needs no code.
;
;  Header opts:
;    Tabs   the id of a tab control: its strip moves to the bottom of the
;           band, and only the tab's page scrolls under it
;    Under  true (default): the band starts at the window's top edge and the
;           caption sits on it (the title bar goes transparent); false: the
;           band goes under the title bar
;    Drag   true (default): pressing the band drags the window and a double-
;           click maximises, as the title bar does -- not on anything that
;           takes a click itself (a tab, a button, a link, an input, an
;           element with its own click handler, or [data-nodrag])
;
;  Calling Header / Footer again replaces the content; "" removes the band.
;
;  ThemedCss(id, css, vars?) is SetExtraCss with colour tokens, worked out
;  again on every theme / stylesheet / accent / tint change -- Trident has no
;  CSS variables, so without it a script rebuilds its CSS by hand each time:
;
;      win.ThemedCss("hero", "#axHeader{background:{tint|mix:{back}:.9}}"
;                          . ".lit{box-shadow:0 0 {=14*k}px {tint|alpha:.55}}", {k: () => glow})
;
;    {accent}  the accent in force         {tint}  the tint, else the accent
;    {back}    the page's background       {window} the window's colour
;    {text}    the theme's text colour     {name}  vars.name (a function is called)
;    {dark?a:b} a in dark mode, else b     {=.55*k} a number: numbers and vars multiplied
;
;  and filters after a colour, chained with |, arguments split by :
;
;    mix:other:t   toward other (a hex or a {token}) by t (0..1, or n*var)
;    lighten:t  darken:t   toward white / black
;    alpha:a       rgba() at opacity a
;    readable[:bg[:ratio]]  moved toward black or white until it reads on bg
;                  (default {back}, 4.5:1 -- the WCAG floor for body text)
;    on            #000 or #fff, whichever reads on it
; =============================================================================
class AxWindowBands {
    Header(html := "", opts := "") {
        o := (n, d) => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        this._band := this.HasOwnProp("_band") ? this._band : {}
        this._band.Head := (html = "") ? "" : {Html: html, Tabs: o("Tabs", ""), Under: o("Under", true), Drag: o("Drag", true)}
        return this._BandsSoon()
    }
    Footer(html := "") {
        this._band := this.HasOwnProp("_band") ? this._band : {}
        this._band.Foot := html
        return this._BandsSoon()
    }
    ; now if the page is up, else as it comes up (before the first paint)
    _BandsSoon() {
        if (this.HasOwnProp("Ready") && this.Ready)
            this._PlaceBands()
        else if !this.HasOwnProp("_bandWait") {
            this._bandWait := true
            this.OnReady((*) => this._PlaceBands())
        }
        return this
    }
    _PlaceBands() {
        if !this.HasOwnProp("_band")
            return
        d := this.Doc, b := d.body
        tb := d.getElementById("titlebar")
        ; ---- the header
        hd := this._band.HasOwnProp("Head") ? this._band.Head : ""
        h := d.getElementById("axHeader")
        if IsObject(hd) {
            if !IsObject(h) {
                h := d.createElement("div")
                h.id := "axHeader"
                h.innerHTML := '<div id="axHeaderBody"></div>'
                if IsObject(tb) {
                    tb.parentNode.insertBefore(h, tb)
                    if hd.Under
                        h.insertBefore(tb, h.firstChild)
                    else
                        tb.parentNode.insertBefore(h, tb.nextSibling)
                } else
                    b.insertBefore(h, b.firstChild)
            }
            d.getElementById("axHeaderBody").innerHTML := hd.Html
            if (hd.Tabs != "")
                try {
                    strip := this.El(hd.Tabs)
                    if (IsObject(strip) && strip.parentNode.uniqueID != h.uniqueID)
                        h.appendChild(strip)
                }
            this.BodyClass("ax-header-under", hd.Under)
            if (hd.Drag && !this.HasOwnProp("_bandDrag")) {
                this._bandDrag := true
                this.On("mousedown", "axHeader", (el, ev) => this._BandDown(ev))
            }
        } else if IsObject(h) {                                 ; removed: the title bar back where it was
            if (IsObject(tb) && tb.parentNode.uniqueID = h.uniqueID)
                b.insertBefore(tb, h)
            h.parentNode.removeChild(h)
            this.BodyClass("ax-header-under", false)
        }
        this._bandDrag := this.HasOwnProp("_bandDrag") && this._bandDrag && IsObject(hd) && hd.Drag
        ; ---- the footer: under the page, over the status bar
        ft := this._band.HasOwnProp("Foot") ? this._band.Foot : ""
        f := d.getElementById("axFooter")
        if (ft != "") {
            if !IsObject(f) {
                f := d.createElement("div")
                f.id := "axFooter"
                shell := d.getElementById("shell")
                if IsObject(shell)
                    shell.parentNode.insertBefore(f, shell.nextSibling)
                else
                    b.appendChild(f)
            }
            f.innerHTML := ft
        } else if IsObject(f)
            f.parentNode.removeChild(f)
        this.BodyClass("has-header", IsObject(hd))
        this.BodyClass("has-footer", ft != "")
        this.BodyClass("ax-flow", IsObject(hd) || ft != "")
    }
    ; a press on the band: the title bar's drag, unless it is on something
    ; that takes the click itself
    _BandDown(ev) {
        if !this._bandDrag
            return
        try el := ev.srcElement
        catch
            return
        static tags := Map("INPUT", 1, "SELECT", 1, "TEXTAREA", 1, "BUTTON", 1, "A", 1)
        static classes := ["tab", "btn", "link", "winbtn", "ax-act", "axtb-item", "seg", "chip", "spin", "swatch", "imgbox"]
        clickHooks := this.Hooks.Has("click") ? this.Hooks["click"] : Map()
        loop {
            if !IsObject(el) || el.id = "axHeader"
                break
            try {
                if (tags.Has(el.tagName) || el.hasAttribute("data-nodrag") || el.hasAttribute("data-role"))
                    return
                if (el.id != "" && clickHooks.Has(el.id))
                    return
                for c in classes
                    if AxWindow._HasClass(el, c)
                        return
            }
            try el := el.parentNode
            catch
                break
        }
        this._TitlebarDown(ev)
    }

    ; ------------------------------------------------------------ themed css
    ThemedCss(id, css, vars := "") {
        if !this.HasOwnProp("_tokCss")
            this._tokCss := Map()
        if (css = "")
            AxWindow._DropKey(this._tokCss, id)
        else
            this._tokCss[id] := {Css: css, Vars: vars}
        try this.SetExtraCss(id, css = "" ? "" : this.ResolveCss(css, vars))
        return this
    }
    ; every themed sheet worked out again: on its own on a look change and as
    ; the page comes up; by hand when a var it reads changes
    RefreshThemedCss() => this._TokRefresh()
    _TokRefresh() {
        if !this.HasOwnProp("_tokCss")
            return
        for id, t in this._tokCss
            try this.SetExtraCss(id, this.ResolveCss(t.Css, t.Vars))
    }
    ; the theme as it stands -- before an AxGui is shown, the one it was given
    LookTheme() {
        t := (this.HasOwnProp("Theme") && this.Theme != "") ? this.Theme
           : (this.HasOwnProp("_opts") && IsObject(this._opts) && this._opts.HasOwnProp("Theme")) ? this._opts.Theme : "dark"
        return (t = "system") ? AxSys.SystemTheme() : t
    }
    ; the accent in force, and the tint (the accent when there is none)
    LookAccent() {
        if (this.HasOwnProp("_accent") && this._accent != "")
            return this._accent
        return this.DefaultAccent(this.LookTheme())
    }
    LookTint() {
        t := this.HasOwnProp("Tint") ? this.Tint : ""
        return (t != "" && t != "accent") ? "#" LTrim(t, "#") : this.LookAccent()
    }
    ResolveCss(css, vars := "") {
        if !InStr(css, "{")
            return css
        ; the innermost tokens first, so a filter's argument may be a token
        loop 8 {
            n := 0
            css := RegExReplace(css, "\{=([\w.*\s-]+)\}", "{_n_$1}")    ; numbers: kept apart from the colour tokens below
            out := "", pos := 1
            while RegExMatch(css, "\{(_n_[\w.*\s-]+|(?:dark|light)\?[^{}:]*:[^{}]*|[a-zA-Z]\w*(?:\|[^{}]*)?)\}", &m, pos) {
                out .= SubStr(css, pos, m.Pos - pos) this._Tok(m[1], vars), pos := m.Pos + m.Len, n++
            }
            css := out SubStr(css, pos)
            if !n
                break
        }
        return css
    }
    _Tok(t, vars) {
        if (SubStr(t, 1, 3) = "_n_") {
            v := this._TokNum(SubStr(t, 4), vars)
            return (v = Round(v)) ? String(Round(v)) : RTrim(RTrim(Format("{:.3f}", v), "0"), ".")
        }
        if RegExMatch(t, "^(dark|light)\?([^:]*):(.*)$", &c)
            return ((this.LookTheme() = "dark") = (c[1] = "dark")) ? c[2] : c[3]
        parts := StrSplit(t, "|")
        v := this._TokBase(Trim(parts[1]), vars)
        loop parts.Length - 1 {
            f := StrSplit(Trim(parts[A_Index + 1]), ":")
            switch StrLower(f[1]) {
            case "mix":      v := AxSys.Mix(v, this._TokColour(f[2], vars), this._TokNum(f[3], vars))
            case "lighten":  v := AxSys.Mix(v, "#ffffff", this._TokNum(f[2], vars))
            case "darken":   v := AxSys.Mix(v, "#000000", this._TokNum(f[2], vars))
            case "alpha":    v := AxSys.Rgba(v, this._TokNum(f[2], vars))
            case "on":       v := AxSys.Luma(v) > 0.55 ? "#000000" : "#ffffff"
            case "readable": v := AxSys.Readable(v, f.Length > 1 ? this._TokColour(f[2], vars) : this._TokBase("back", vars)
                                                 , f.Length > 2 ? this._TokNum(f[3], vars) : 4.5)
            default:         throw ValueError("ThemedCss: unknown filter '" f[1] "'", -1)
            }
        }
        return v
    }
    _TokBase(name, vars) {
        if (IsObject(vars) && (vars is Map ? vars.Has(name) : vars.HasOwnProp(name))) {
            v := vars is Map ? vars[name] : vars.%name%
            return HasMethod(v) ? v() : v
        }
        mode := this.LookTheme()
        switch StrLower(name) {
        case "accent": return this.LookAccent()
        case "tint":   return this.LookTint()
        case "back":   return "#" LTrim(this.HasMethod("PageBack") ? this.PageBack(mode) : this.ThemeBack(mode), "#")
        case "window": return "#" LTrim(this.ThemeBack(mode), "#")
        case "text":   return (mode = "light") ? "#1b1b1b" : "#ffffff"
        }
        throw ValueError("ThemedCss: unknown token '" name "'", -1)
    }
    _TokColour(s, vars) => (SubStr(s, 1, 1) = "#") ? s : this._TokBase(s, vars)
    _TokNum(s, vars) {
        v := 1.0
        for p in StrSplit(s, "*") {
            p := Trim(p)
            v *= IsNumber(p) ? Number(p) : Number(this._TokBase(p, vars))
        }
        return v
    }
}
