#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Avatar\AxAvatar.css, AX_COMPONENTS_AVATAR_AXAVATAR_CSS

; =============================================================================
;  AxAvatar -- a person: their picture, or their initials on a colour of
;  their own, and whether they are about.
;
;    g.AddAvatar("vMe Size=40 Status=online", "Ada Lovelace")
;    g.AddAvatar('vThem Named Sub="Product design" Image=ada.png', "Ada Lovelace")
;    av.Value := "Grace Hopper"     av.SetStatus("away")     av.SetImage("grace.jpg")
;
;  The colour comes from the name, so the same person is always the same
;  colour. Status is online, away, busy or offline; Named puts the name (and
;  Sub under it) beside the circle, which makes it a persona card.
; =============================================================================
class AxAvatar {
    static _reg := AxRich.Register("Avatar", "components\Avatar\AxAvatar.css", (*) => AxAvatar._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddAvatar", (c, o := "", v := "") => AxAvatar._Add(c, o, v))
        AxWindow.RegisterValue("avatar",
            (w, el) => AxWindow._Attr(el, "data-value"),
            (w, el, v) => AxAvatar._SetVia(w, el, v))
        return true
    }
    static _SetVia(win, el, v) {
        c := AxRich.At(win, el.id)
        if IsObject(c)
            c.Value := v
    }
    static Colours := ["#8764b8", "#0078d4", "#038387", "#107c10", "#ca5010", "#c239b3",
                       "#4f6bed", "#8e562e", "#e3008c", "#498205", "#986f0b", "#5c2e91"]
    static ColourOf(name) {
        h := 0
        loop parse String(name)
            h := Mod(h * 31 + Ord(A_LoopField), 1000003)
        return AxAvatar.Colours[Mod(h, AxAvatar.Colours.Length) + 1]
    }
    static Initials(name) {
        words := []
        for w in StrSplit(Trim(RegExReplace(String(name), "[^\w\s'-]", " ")), " ")
            if (w != "")
                words.Push(w)
        if !words.Length
            return "?"
        if (words.Length = 1)
            return StrUpper(SubStr(words[1], 1, 2))
        return StrUpper(SubStr(words[1], 1, 1) SubStr(words[words.Length], 1, 1))
    }
    static _Add(c, opts, name) {
        o := c._Opt(opts, "av")
        cfg := {Name: String(name), Size: Integer(c._Kv(o, "size", 40)), Status: StrLower(c._Kv(o, "status", "")),
                Image: c._Kv(o, "image", ""), Named: o.Flags.Has("named") && o.Flags["named"], Sub: c._Kv(o, "sub", ""),
                Square: o.Flags.Has("square") && o.Flags["square"]}
        ctl := c._Reg(o, "Avatar", AxAvatar.Html(o.Id, cfg, c._Common(o, "")))
        c.G.OnReady((w) => AxAvatar(w, o.Id, cfg))
        return ctl
    }
    static Html(id, cfg, attrs := "") {
        cls := "axav" (cfg.Named ? " named" : "")
        if (attrs != "") {
            n := 0
            a := RegExReplace(attrs, 'S)class="([^"]*)"', 'class="' cls ' $1"', &n)
            if !n
                a .= ' class="' cls '"'
        } else
            a := ' id="' AxWindow._Esc(id) '" class="' cls '"'
        return '<span' a ' data-role="avatar" data-value="' AxWindow._Esc(cfg.Name) '"><span class="axav-r" id="'
             . AxWindow._Esc(id) '_r">' AxAvatar.Inner(cfg) '</span></span>'
    }
    static Inner(cfg) {
        E := (x) => AxWindow._Esc(x)
        s := Max(16, cfg.Size)
        dot := Max(8, Round(s * 0.28))
        st := 'width:' s 'px;height:' s 'px;line-height:' s 'px;font-size:' Round(s * 0.38) 'px;background:' AxAvatar.ColourOf(cfg.Name) ';'
        h := '<span class="axav-c' (cfg.Square ? " square" : "") '" style="' st '" data-tip="' E(cfg.Name) '">'
        h .= (cfg.Image != "") ? '<img src="' E(cfg.Image) '" alt="">' : E(AxAvatar.Initials(cfg.Name))
        if (cfg.Status != "")
            h .= '<span class="axav-st ' E(cfg.Status) '" style="width:' dot 'px;height:' dot 'px"></span>'
        h .= '</span>'
        if cfg.Named
            h .= '<span class="axav-n"><b>' E(cfg.Name) '</b>' (cfg.Sub != "" || cfg.Status != ""
               ? '<small>' E(cfg.Sub != "" ? cfg.Sub : StrUpper(SubStr(cfg.Status, 1, 1)) SubStr(cfg.Status, 2)) '</small>' : "") '</span>'
        return h
    }

    __New(win, id, cfg) {
        this.W := win, this.Id := id, this.Cfg := cfg
        AxRich.Bind(win, id, this)
    }
    Value {
        get => this.Cfg.Name
        set {
            this.Cfg.Name := String(value)
            this.Render()
        }
    }
    SetStatus(s) {
        this.Cfg.Status := StrLower(s)
        return this.Render()
    }
    SetImage(path) {
        this.Cfg.Image := path
        return this.Render()
    }
    SetSub(t) {
        this.Cfg.Sub := t
        return this.Render()
    }
    Render() {
        try {
            this.W.El(this.Id "_r").innerHTML := AxAvatar.Inner(this.Cfg)
            this.W.El(this.Id).setAttribute("data-value", this.Cfg.Name)
        }
        return this
    }
}
