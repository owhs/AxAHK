#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Breadcrumb\AxBreadcrumb.css, AX_COMPONENTS_BREADCRUMB_AXBREADCRUMB_CSS

; =============================================================================
;  AxBreadcrumb -- where you are, and the way back.
;
;    bc := g.AddBreadcrumb("vWhere", "home:Home:E80F`ndocs:Documents`nax:AxGui")
;    bc.OnChange((ctl, v, *) => Go(v))          ; someone clicked a step back
;    bc.Push("src", "Source")                   ; one level deeper
;    bc.Pop()                                   ; one back
;    bc.Path := "home:Home`nmusic:Music"        ; a whole new trail
;
;  Items are one per line (or | between them): value:Label:Glyph, where the
;  value and the glyph are optional -- the same shape a segmented control and
;  a drop-down take. The last one is where you are; the rest are links.
;  Clicking one goes back to it: the steps after it drop off (NoTrim keeps
;  them), and Change fires with its value. ctl.Value is the value of where
;  you are; setting it to one of the steps goes back to that step.
;
;  A trail longer than Max (5) folds its middle into a "..." that opens the
;  hidden steps as a popover. Home shows a glyph alone for the first step.
; =============================================================================
class AxBreadcrumb {
    static _reg := AxRich.Register("Breadcrumb", "components\Breadcrumb\AxBreadcrumb.css",
                                   (*) => AxBreadcrumb._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddBreadcrumb", (c, o := "", items := "") => AxBreadcrumb._Add(c, o, items))
        AxWindow.RegisterValue("breadcrumb",
            (w, el) => AxWindow._Attr(el, "data-value"),
            (w, el, v) => AxBreadcrumb._SetVia(w, el, v))
        return true
    }
    static _SetVia(win, el, v) {
        c := AxRich.At(win, el.id)
        if IsObject(c)
            c.Value := v
    }
    static _Add(c, opts, items) {
        o := c._Opt(opts, "bc")
        cfg := {Max: Integer(c._Kv(o, "max", 5)), Home: o.Flags.Has("home") && o.Flags["home"],
                Trim: !(o.Flags.Has("notrim") && o.Flags["notrim"]), Sep: c._Kv(o, "sep", "")}
        list := AxBreadcrumb.Parse(items)
        ctl := c._Reg(o, "Breadcrumb", AxBreadcrumb.Html(o.Id, list, cfg, c._Common(o, "")))
        c.G.OnReady((w) => AxBreadcrumb(w, o.Id, list, cfg))
        return ctl
    }
    ; "a:A:E80F`nb:B" or "A|B|C" or an array of strings / [value, label, glyph]
    static Parse(items) {
        out := []
        if IsObject(items) {
            for it in items {
                if IsObject(it)
                    out.Push({V: it[1], L: it.Length > 1 ? it[2] : it[1], G: it.Length > 2 ? it[3] : ""})
                else
                    out.Push(AxBreadcrumb._One(it))
            }
            return out
        }
        t := StrReplace(String(items), "`r", "")
        for line in StrSplit(t, InStr(t, "`n") ? "`n" : "|") {
            if (Trim(line) != "")
                out.Push(AxBreadcrumb._One(Trim(line)))
        }
        return out
    }
    static _One(s) {
        p := StrSplit(s, ":")
        if (p.Length = 1)
            return {V: p[1], L: p[1], G: ""}
        if (p.Length = 2)
            return (RegExMatch(p[2], "^[0-9A-Fa-f]{4,5}$") ? {V: p[1], L: p[1], G: p[2]} : {V: p[1], L: p[2], G: ""})
        return {V: p[1], L: p[2], G: p[3]}
    }
    static Text(list) {
        s := ""
        for it in list
            s .= (s = "" ? "" : "`n") it.V ":" it.L (it.G != "" ? ":" it.G : "")
        return s
    }

    ; ------------------------------------------------------------- markup
    static Html(id, list, cfg, attrs := "") {
        cls := "axcrumb"
        if (attrs != "") {
            n := 0
            a := RegExReplace(attrs, 'S)class="([^"]*)"', 'class="' cls ' $1"', &n)
            if !n
                a .= ' class="' cls '"'
        } else
            a := ' id="' AxWindow._Esc(id) '" class="' cls '"'
        cur := list.Length ? list[list.Length].V : ""
        return '<nav' a ' data-role="breadcrumb" data-value="' AxWindow._Esc(cur) '">'
             . '<span class="axcrumb-r" id="' AxWindow._Esc(id) '_r">' AxBreadcrumb.Inner(id, list, cfg) '</span></nav>'
    }
    static Inner(id, list, cfg) {
        E := (x) => AxWindow._Esc(x)
        mx := Max(3, IsObject(cfg) && cfg.HasOwnProp("Max") ? cfg.Max : 5)
        home := IsObject(cfg) && cfg.HasOwnProp("Home") && cfg.Home
        sepG := (IsObject(cfg) && cfg.HasOwnProp("Sep") && cfg.Sep != "") ? cfg.Sep : "E76C"
        sep := '<span class="axcrumb-sep ico">&#x' sepG ';</span>'
        n := list.Length
        ; which to show: all of them, or the first, "...", and the last few
        fold := (n > mx)
        keepTail := mx - 2
        h := ""
        for i, it in list {
            if (fold && i > 1 && i <= n - keepTail) {
                if (i = 2)
                    h .= sep '<span class="axcrumb-i axcrumb-more" id="' E(id) '_more" data-tip="'
                      .  (n - keepTail - 1) ' more">&#x2026;</span>'
                continue
            }
            last := (i = n)
            glyph := (it.G != "") ? it.G : (home && i = 1) ? "E80F" : ""
            lab := (home && i = 1 && it.G = "") ? "" : E(it.L)
            h .= (i > 1 ? sep : "")
              .  '<span class="axcrumb-i' (last ? " cur" : "") (lab = "" ? " icon" : "") '"'
              .  (last ? "" : ' data-i="' i '"') (lab = "" ? ' data-tip="' E(it.L) '"' : "") '>'
              .  (glyph != "" ? '<span class="ico">&#x' glyph ';</span>' : "") lab '</span>'
        }
        return h
    }

    ; ----------------------------------------------------------- behaviour
    __New(win, id, list, cfg) {
        this.W := win, this.Id := id, this.List := list, this.Cfg := cfg
        this._cbs := []
        AxRich.Bind(win, id, this)
        win.On("click", id "_r", (el, ev) => this._Click(ev))
        win.Popover(id "_more", {On: "none", Build: (*) => this._MoreHtml(), Class: "axcrumb-pop", Align: "left", Gap: 4})
        win.On("click", id "_pop", (el, ev) => this._PopClick(ev))
    }
    Items => this.List
    Value {
        get => this.List.Length ? this.List[this.List.Length].V : ""
        set {
            for i, it in this.List
                if (it.V = value)
                    return this._Trim(i, false)
        }
    }
    Path {
        get => AxBreadcrumb.Text(this.List)
        set {
            this.List := AxBreadcrumb.Parse(value)
            this.Render()
        }
    }
    Push(value, label := "", glyph := "") {
        this.List.Push({V: value, L: label != "" ? label : value, G: glyph})
        return this.Render()
    }
    Pop() {
        if (this.List.Length > 1)
            this.List.Pop()
        return this.Render()
    }
    OnChange(fn) {
        this._cbs.Push(fn)
        return this
    }
    Render() {
        try {
            this.W.El(this.Id "_r").innerHTML := AxBreadcrumb.Inner(this.Id, this.List, this.Cfg)
            this.W.El(this.Id).setAttribute("data-value", this.Value)
        }
        return this
    }
    _Trim(i, fire := true) {
        if (i < 1 || i > this.List.Length)
            return this
        v := this.List[i].V
        if this.Cfg.Trim
            while (this.List.Length > i)
                this.List.Pop()
        this.Render()
        if fire {
            for fn in this._cbs.Clone()
                try fn(v, this)
            try this.W._FireValue(this.W.El(this.Id), v)
        }
        return this
    }
    _Click(ev) {
        try el := ev.srcElement
        catch
            return
        loop 4 {
            if !IsObject(el)
                return
            try {
                if (el.id = this.Id "_more")
                    return this.W.TogglePopover(this.Id "_more")
            }
            i := AxWindow._Attr(el, "data-i")
            if (i != "")
                return this._Trim(Integer(i))
            el := AxWindow._ParentEl(el)
        }
    }
    _MoreHtml() {
        E := (x) => AxWindow._Esc(x)
        n := this.List.Length, keepTail := Max(3, this.Cfg.Max) - 2
        h := '<div class="axcrumb-menu" id="' E(this.Id) '_pop">'
        loop n - keepTail - 1 {
            it := this.List[A_Index + 1]
            h .= '<div class="axcrumb-pi" data-i="' (A_Index + 1) '">'
              .  '<span class="ico">&#x' (it.G != "" ? it.G : "E8B7") ';</span>' E(it.L) '</div>'
        }
        return h '</div>'
    }
    _PopClick(ev) {
        try el := ev.srcElement
        catch
            return
        loop 3 {
            if !IsObject(el)
                return
            i := AxWindow._Attr(el, "data-i")
            if (i != "") {
                this.W.ClosePopover()
                return this._Trim(Integer(i))
            }
            el := AxWindow._ParentEl(el)
        }
    }
}
