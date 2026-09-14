#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
#Include %A_LineFile%\..\..\..\AxJson.ahk
; single-file exe: this component's stylesheet and script travel inside it
;@Ahk2Exe-AddResource %U_AxLib%\components\Audio\AxAudio.css, AX_COMPONENTS_AUDIO_AXAUDIO_CSS
;@Ahk2Exe-AddResource %U_AxLib%\components\Audio\AxAudio.js, AX_COMPONENTS_AUDIO_AXAUDIO_JS

; =============================================================================
;  AxAudio -- a sound player: the page's own <audio>, which in IE11 plays MP3
;  and AAC (.m4a), with a small player drawn round it, or none.
;
;      a := g.AddAudio("vmusic w420 Loop", "assets\tune.mp3").Component   ; after Show()
;      a.Play(), a.Volume := 60, a.Seek(30)
;      a.OnTime((a, pos, dur) => ToolTip(Round(pos) " of " Round(dur)))
;      a.OnEnd((a) => a.Load("next.mp3", true))
;      g.PlaySound("assets\ding.mp3")          ; a sound, no player: fire and forget
;
;    Play()  Pause()  Toggle()  Stop()  Seek(seconds)  Load(file or url, play := false)
;    Position  Duration  Playing  Ended  Volume (0-100)  Muted  Loop  Rate (0.25-4)
;    OnPlay(fn(a))  OnPause(fn(a))  OnEnd(fn(a))  OnReady(fn(a, duration))
;    OnTime(fn(a, pos, duration), every := 250)  OnError(fn(a, message))
;
;  Options: Loop  Autoplay  NoUi (the player is not shown)  Volume=0-100
;  WAV, OGG and FLAC are not IE11's: convert them to MP3 first.
; =============================================================================
class AxAudio {
    static _reg := AxRich.Register("Audio", "components\Audio\AxAudio.css", (*) => (
        AxRich.AddMethod("AddAudio", (c, o := "", v := "") => AxAudio._Add(c, o, v)),
        AxRich.WindowMethod("PlaySound", (w, src, vol := 100) => AxAudio.Sound(w, src, vol))))
    static JsPath := "components\Audio\AxAudio.js"

    static Html(id, cfg) {
        E := (x) => AxWindow._Esc(x)
        ui := !(cfg.HasOwnProp("NoUi") && cfg.NoUi)
        return '<div id="' E(id) '" class="axau' (ui ? "" : " axau-noui") (cfg.HasOwnProp("Class") ? " " E(cfg.Class) : "") '"'
             . ' data-role="audio" style="' E(cfg.HasOwnProp("Style") ? cfg.Style : "") '">'
             . '<audio id="' E(id) '_a" preload="auto"' (cfg.Src != "" ? ' src="' E(cfg.Src) '"' : "") '></audio>'
             . (ui ? '<span class="axau-btn axau-play ico" id="' E(id) '_play" title="Play">&#xE768;</span>'
                   . '<span class="axau-time" id="' E(id) '_t">0:00</span>'
                   . '<div class="axau-bar" id="' E(id) '_bar"><div class="axau-fill link" id="' E(id) '_fill"></div></div>'
                   . '<span class="axau-time" id="' E(id) '_d">0:00</span>'
                   . '<span class="axau-btn axau-vol ico" id="' E(id) '_vol" title="Mute">&#xE995;</span>' : "")
             . '<textarea class="axau-q" id="' E(id) '_q"></textarea><span class="axau-req" id="' E(id) '_req"></span></div>'
    }

    static _Add(container, opts, src) {
        o := container._Opt(opts, "audio")
        kv := (k, d := "") => container._Kv(o, k, d)
        f := (name) => o.Flags.Has(name) && o.Flags[name]
        cfg := {Src: AxAudio.Url(src), Loop: f("loop"), Autoplay: f("autoplay"), NoUi: f("noui"),
                Volume: kv("volume", "")}
        cfg.Style := (o.W != "" ? "width:" o.W "px;" : "") kv("style")
        cfg.Class := (o.W = "" || f("fill")) ? "fill" : ""
        c := container._Reg(o, "Audio", AxAudio.Html(o.Id, cfg))
        container.G.OnReady((w) => AxAudio(w, o.Id, cfg))
        return c
    }
    ; a file beside the script, a full path, or a URL, as the page wants it
    static Url(src) {
        if (src = "" || RegExMatch(src, "i)^(https?|file|data):"))
            return src
        p := RegExMatch(src, "^[A-Za-z]:|^\\\\") ? src : A_ScriptDir "\" src
        return AxWindow.FileUrl(p)
    }
    ; g.PlaySound(file, volume): a sound with no player, any number at once
    static Sound(win, src, vol := 100) {
        if !AxRich.UseJs(win, AxAudio.JsPath)
            return false
        try return win.Doc.parentWindow.AXAU.sound(AxAudio.Url(src), vol / 100)
        return false
    }

    ; ======================================================== a player
    __New(win, id, cfg) {
        this.W := win, this.Id := id, this.Cfg := cfg, this._ready := false, this._on := Map()
        AxRich.Use(win, "Audio")
        AxRich.Bind(win, id, this)
        if !AxRich.UseJs(win, AxAudio.JsPath)
            return
        m := Map("loop", cfg.Loop ? 1 : 0, "autoplay", cfg.Autoplay ? 1 : 0)
        if (cfg.Volume != "")
            m["volume"] := cfg.Volume + 0
        try {
            this.JS.make(id, AxJson.Stringify(m, ""))
            this._ready := true
        }
        win.On("click", id "_req", (*) => this._Ask())
    }
    JS => this.W.Doc.parentWindow.AXAU
    _Call(name, args*) {
        if !this._ready
            return ""
        try return this.JS.call(this.Id, name, AxJson.Stringify(args, ""))
        return ""
    }
    _Get(key) {
        r := this._Call("get")
        return (r != "") ? AxJson.Parse(r).Get(key, "") : ""
    }

    Play() => (this._Call("play"), this)
    Pause() => (this._Call("pause"), this)
    Toggle() => (this._Call("toggle"), this)
    Stop() => (this._Call("stop"), this)
    Seek(seconds) => (this._Call("seek", seconds + 0), this)
    Load(src, play := false) => (this._Call("load", AxAudio.Url(src), play ? 1 : 0), this)
    Position {
        get => this._Get("pos")
        set => this.Seek(value)
    }
    Duration => this._Get("duration")
    Playing => !this._Get("paused")
    Ended => !!this._Get("ended")
    Src => this._Get("src")
    Volume {
        get => this._Get("volume")
        set => this._Call("set", "volume", value + 0)
    }
    Muted {
        get => !!this._Get("muted")
        set => this._Call("set", "muted", value ? 1 : 0)
    }
    Loop {
        get => !!this._Get("loop")
        set => this._Call("set", "loop", value ? 1 : 0)
    }
    Rate {
        get => this._Get("rate")
        set => this._Call("set", "rate", value + 0)
    }
    ; ctl.Value is where it is, in seconds
    Value {
        get => this.Position
        set => this.Seek(value)
    }

    _Listen(kind, fn, every := 0) {
        if !this._on.Has(kind)
            this._on[kind] := []
        this._on[kind].Push(fn)
        this._Call("listen", kind, 1, every)
        return this
    }
    OnPlay(fn) => this._Listen("play", fn)
    OnPause(fn) => this._Listen("pause", fn)
    OnEnd(fn) => this._Listen("end", fn)
    OnReady(fn) => this._Listen("ready", fn)
    OnError(fn) => this._Listen("error", fn)
    OnTime(fn, every := 250) => this._Listen("time", fn, every)
    _Ask() {
        raw := ""
        try raw := this.W.El(this.Id "_q").value
        m := ""
        try m := AxJson.Parse(raw)
        if !(m is Map)
            return
        kind := m.Get("kind", "")
        args := [this]
        switch kind {
        case "time": args.Push(m.Get("pos", 0), m.Get("duration", 0))
        case "ready": args.Push(m.Get("duration", 0))
        case "error": args.Push(m.Get("message", ""))
        }
        if this._on.Has(kind)
            for fn in this._on[kind].Clone()
                try AxGuiCompat.CallFit(fn, args)
    }
}
