#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
#Include %A_LineFile%\..\..\..\AxJson.ahk
#Include %A_LineFile%\..\..\Canvas\AxCanvas.ahk
; single-file exe: this component's stylesheet and script travel inside it
;@Ahk2Exe-AddResource %U_AxLib%\components\Game\AxGame.css, AX_COMPONENTS_GAME_AXGAME_CSS
;@Ahk2Exe-AddResource %U_AxLib%\components\Game\AxGame.js, AX_COMPONENTS_GAME_AXGAME_JS

; =============================================================================
;  AxGame -- a small low-poly 3D game engine: the page runs the frames, your
;  script runs the rules.
;
;      eng := g.AddGame("vgame Fill Grow h400 Tick=30").Component       ; after Show()
;      eng.World({Gravity: 22, Sky: ["#1b2440", "#7a93c4"], Bounds: 24})
;      ship := eng.Spawn("ship", {Mesh: "ship", Color: "#ffb900", Y: 1, Solid: true,
;                                 Gravity: 1, Control: {Speed: 13, Jump: 9}, Hits: ["gem"]})
;      eng.Camera({Follow: "ship"})
;      eng.OnHit((eng, a, b, tag) => tag = "gem" ? eng.Kill(b) : "")
;      eng.OnTick((eng, t) => t.Pressed.Has("p") ? eng.Pause(!eng.Paused) : "")
;
;  The page (AxGame.js) steps the world 60 times a second: the keyboard,
;  movement, gravity and the ground, the behaviours below, collisions,
;  particles, the camera and drawing. About Tick times a second it tells
;  the script what happened, and the script answers in one batch.
;
;  ------------------------------------------------------------- entities
;    Spawn(id, props) -> entity    Set(id, props)    Kill(id)    KillTag(tag)
;    e := eng.Entity(id): e.Set(props)  e.Kill()  e.X e.Y e.Z e.VX e.VZ (watched: live)
;    Mesh: cube tetra octa pyramid ico prism ship, or your own (Mesh(name, verts, faces))
;    X Y Z  VX VY VZ  RX RY RZ (degrees)  Scale / SX SY SZ  Color  Radius  Tag
;    Gravity (1 = the world's)  Solid (stands on the ground)  Bounce  Drag
;    Spin: [x, y, z] deg/s   Bob: {Amp, Speed}   Roll (rolls as it moves)
;    Control: {Speed, Accel, Jump, Turn}   the keys (WASD / arrows, Space) move it
;    Chase: {Target, Speed, Turn}          Bounds: "clamp" | "bounce" | "kill"
;    Hits: [tags]   collisions with those are reported   Life: seconds
;    Hidden  Frozen  Flash (blinks)  Glow (unlit)  Shadow: false
;
;  ------------------------------------------------------------- the world
;    World({Gravity, Sky: [top, bottom], Fog: [near, far], FogColor, Ambient,
;           Light: [x, y, z], Ground: {Tile, Colors: [a, b], Radius}, Bounds,
;           TimeScale, Shake})
;    Camera({Follow: id, Dist, Height, Fov, Smooth}) or {X, Y, Z} for a fixed one
;    Hud(id, {Text, X, Y, Size, Color, Align, Hidden}) -- X/Y negative from the
;        right/bottom edge, or "50%"; Hud(id) removes it
;    Burst({X, Y, Z, N, Color, Speed, Life, Size, Mesh})   particles
;    Pause(on)  Paused  Step()  TimeScale(x)  Shake(amount)  Clear()
;    Debug({Stats, Colliders, Wire})  List(on): OnTick's t.List, every entity
;
;  ------------------------------------------------------- the 2D world
;    g.AddGame("vworld Mode=2D ...") or World({Mode: "2d"}): top down, in
;    tiles, x right and y down. World({Tile: 32, Zoom: 1, Back: "#111"})
;    Map(rows, Map(".", {Color: "#4a7a3a", Deco: "grass"}, "#", {Color: "#777",
;        Solid: true, Deco: "brick"}, ...))   Deco: grass flowers brick water
;        planks path tree rock door roof; Sprite: a sprite drawn on the tile
;    Tile(x, y, ch)  TileAt(x, y)   Sprite(name, rows, palette)   pixel art
;    things: Sprite (built in: hero elder villager slime coin potion key chest
;        heart gem) or Shape (circle box diamond) + Color, Size (tiles), Text,
;        Label, Solid (stops at solid tiles), Control {Speed}, Chase {Target,
;        Speed, Range}, Wander {Speed, Every}, Layer (0 flat, 1 standing)
;    Float(x, y, "+1", {Color})   Near(id, tag, dist) -> id   Within(x, y, d, tag)
;    Hud(id, {..., Box: true | colour, Width, Border}) for speech and signs
;
;  ---------------------------------------------------------------- events
;    OnTick(fn(eng, t))   t.Dt t.Time t.Keys t.Pressed (Maps of key names:
;        left right up down space enter escape shift ctrl tab, a..z, 0..9)
;        t.Hits t.Watch t.Stats t.List
;    OnHit(fn(eng, a, b, tag))   OnKey(fn(eng, key)) (a key just pressed)
;    Key(name) -> held now (as of the last tick)   Stats -> Map (fps, ms,
;    tris, ents, rtt, logic, tickHz, bytes)
; =============================================================================
class AxGame {
    static _reg := AxRich.Register("Game", "components\Game\AxGame.css",
        (*) => AxRich.AddMethod("AddGame", (c, o := "", v := "") => AxGame._Add(c, o, v)))
    static JsPath := "components\Game\AxGame.js"

    static Html(id, cfg) {
        E := (x) => AxWindow._Esc(x)
        return '<div id="' E(id) '" class="axge' (cfg.Class != "" ? " " E(cfg.Class) : "") '" data-role="game" style="' E(cfg.Style) '">'
             . '<canvas class="axge-c"></canvas>'
             . '<div class="axge-ph"><span class="ico">&#xE7FC;</span> Game</div>'
             . '<textarea class="axge-q" id="' E(id) '_q"></textarea><span class="axge-req" id="' E(id) '_req"></span></div>'
    }
    static _Add(container, opts, value) {
        o := container._Opt(opts, "game")
        kv := (k, d := "") => container._Kv(o, k, d)
        cfg := {Tick: kv("tick", 30), Mode: kv("mode", "3d")}
        h := (o.H != "") ? Integer(o.H) : 360
        cfg.Style := "height:" h "px;" (o.W != "" ? "width:" o.W "px;" : "") kv("style")
        cfg.Class := (o.W = "" || o.Flags.Has("fill")) ? "fill" : ""
        c := container._Reg(o, "Game", AxGame.Html(o.Id, cfg))
        container.G.OnReady((w) => AxGame(w, o.Id, cfg))
        return c
    }

    ; ======================================================== an engine
    __New(win, id, cfg) {
        this.W := win, this.Id := id, this.Cfg := cfg
        this._buf := "", this._armed := false, this._ready := false, this._paused := false
        this._ents := Map(), this._ents.CaseSense := false
        this._tickFns := [], this._hitFns := [], this._keyFns := []
        this._keys := Map(), this._stats := Map(), this.LastTick := "", this._list := "", this._map := []
        this._flushFn := ObjBindMethod(this, "_Send")
        this._askFn := ObjBindMethod(this, "_Ask"), this._inbox := "", this._asking := false, this._js := ""
        AxRich.Use(win, "Game")
        AxRich.Bind(win, id, this)
        if !AxRich.UseJs(win, AxGame.JsPath)
            return
        try {
            this._js := win.Doc.parentWindow.AXGE             ; kept: three COM reads a call otherwise
            this.JS.make(id, AxJson.Stringify(Map("tick", cfg.Tick + 0, "mode", StrLower(cfg.Mode)), ""))
            this._ready := true
            ; The ticks come in through a function handed to the page: a call
            ; costs under a microsecond, a click on a hidden element goes down
            ; the library's whole click path. The click stays as the fallback.
            this.JS.hook(id, ObjBindMethod(this, "_Hear"))
        }
        win.On("click", id "_req", (*) => this._Ask(true))
    }
    JS => this._js != "" ? this._js : this.W.Doc.parentWindow.AXGE
    ; The page calls this with a tick. It only files it: the rules run on a
    ; thread of their own once the page has finished its frame, so however
    ; long they take, the frame they came from is already on the screen.
    _Hear(json) {
        this._inbox := json
        if !this._asking
            this._asking := true, SetTimer(this._askFn, -1)
        return 0
    }
    static _Ms() {
        static f := 0
        if !f
            DllCall("QueryPerformanceFrequency", "Int64*", &f)
        DllCall("QueryPerformanceCounter", "Int64*", &c := 0)
        return c * 1000 / f
    }

    ; the batch: one call into the page at the end of the thread
    _Cmd(op, args*) {
        s := '["' op '"'
        for a in args
            s .= "," ((a is AxGameRaw) ? a.Json : AxCanvas._J(a))
        this._buf .= (this._buf = "" ? "" : ",") s "]"
        if !this._armed
            this._armed := true, SetTimer(this._flushFn, -1)
        return this
    }
    _Send() {
        this._armed := false
        if (this._buf = "" || !this._ready)
            return this
        b := this._buf, this._buf := ""
        try this.JS.run(this.Id, "[" b "]")
        return this
    }
    Flush() => this._Send()

    ; ---------------------------------------------------------- entities
    Spawn(id, props := "") {
        p := IsObject(props) ? AxCanvas._Props(props) : Map()
        e := AxGameEntity(this, id, p)
        this._ents[id] := e
        this._Cmd("spawn", id, p)
        return e
    }
    Set(id, props) {
        p := AxCanvas._Props(props)
        if this._ents.Has(id)
            for k, v in p
                this._ents[id].P[k] := v
        return this._Cmd("set", id, p)
    }
    Kill(id) {
        if this._ents.Has(id)
            this._ents.Delete(id)
        return this._Cmd("kill", id)
    }
    KillTag(tag) {
        gone := []
        for id, e in this._ents
            if (e.Tag = tag)
                gone.Push(id)
        for id in gone
            this._ents.Delete(id)
        return this._Cmd("killtag", tag)
    }
    Entity(id) => this._ents.Has(id) ? this._ents[id] : ""
    Entities {
        get {
            out := []
            for id, e in this._ents
                out.Push(e)
            return out
        }
    }
    ; a mesh of your own: verts [[x, y, z] ...], faces [[a, b, c] ...] or
    ; [a, b, c, "#colour"], around the origin, convex; the winding is fixed for you
    Mesh(name, verts, faces) => this._Cmd("mesh", name, verts, faces)
    Watch(id, on := true) => this._Cmd("watch", id, on ? 1 : 0)

    ; ------------------------------------------------------- the 2D world
    ; Map(rows, legend): rows are strings, a character a tile; legend is a Map
    ; from the character to what it is -- {Color, Solid, Deco, Sprite, Accent}
    Map(rows, legend) {
        this._map := []
        for r in rows
            this._map.Push(String(r))
        return this._Cmd("map", this._map, AxGame._Chars(legend))
    }
    ; one tile changed: a door opens, a chest is emptied
    Tile(x, y, ch) {
        if (y >= 0 && y < this._map.Length && x >= 0) {
            row := this._map[y + 1]
            this._map[y + 1] := SubStr(row, 1, x) ch SubStr(row, x + 2)
        }
        return this._Cmd("tile", x, y, ch)
    }
    ; the character at a tile (0-based, as the page counts them); "" off the map
    TileAt(x, y) {
        x := Floor(x), y := Floor(y)
        if (y < 0 || y >= this._map.Length || x < 0)
            return ""
        return SubStr(this._map[y + 1], x + 1, 1)
    }
    ; Sprite(name, rows, palette): pixel art. rows are strings, "." is
    ; see-through; palette is a Map from each other character to a colour
    Sprite(name, rows, palette) => this._Cmd("sprite", name, rows, AxGame._Chars(palette))
    ; a Map keyed by single characters, sent as it is: "T" and "t" are two
    ; different tiles (the usual writer lower-cases every key)
    static _Chars(m) {
        s := ""
        for k, v in (m is Map ? m : m.OwnProps())
            s .= (s = "" ? "" : ",") '"' AxJson.Escape(String(k)) '":' AxCanvas._J(v)
        return AxGameRaw("{" s "}")
    }
    ; a word that rises off a place and fades: "+1", "-3", "Level up!"
    Float(x, y, text, props := "") => this._Cmd("float", x, y, String(text), IsObject(props) ? props : Map())
    ; Near(id, tag, dist) -> the id of the nearest thing with that tag within
    ; dist of id, or "". Within(x, y, dist, tag) -> an Array of ids. Both ask
    ; the page there and then, after anything still waiting to go to it.
    Near(id, tag := "", dist := 1.5) {
        this._Send()
        try return String(this.JS.call(this.Id, "near", "[" AxCanvas._J(id) "," AxCanvas._J(tag) "," AxCanvas._J(dist + 0) "]"))
        return ""
    }
    Within(x, y, dist, tag := "") {
        this._Send()
        out := []
        try {
            r := AxJson.Parse(this.JS.call(this.Id, "within", "[" AxCanvas._J(x + 0) "," AxCanvas._J(y + 0) "," AxCanvas._J(dist + 0) "," AxCanvas._J(tag) "]"))
            if (r is Array)
                out := r
        }
        return out
    }

    ; ---------------------------------------------------------- the world
    World(props) => this._Cmd("world", props)
    Camera(props) => this._Cmd("cam", props)
    Hud(id, props := "") => this._Cmd("hud", id, IsObject(props) ? props : "")
    Burst(props) => this._Cmd("burst", props)
    Debug(props) => this._Cmd("debug", props)
    List(on := true) => this._Cmd("list", on ? 1 : 0)
    Tick(hz) => this._Cmd("tick", hz + 0)
    Pause(on := true) {
        this._paused := !!on
        return this._Cmd("world", Map("paused", on ? 1 : 0))
    }
    Paused => this._paused
    Step() => this._Cmd("step")
    TimeScale(x) => this._Cmd("world", Map("timescale", x + 0))
    Shake(amount := 0.6) => this._Cmd("world", Map("shake", amount + 0))
    Clear() {
        this._ents := Map(), this._ents.CaseSense := false
        return this._Cmd("clear")
    }
    Focus() {
        try this.JS.call(this.Id, "focus", "[]")
        return this
    }

    ; ------------------------------------------------------------- events
    OnTick(fn) => (this._tickFns.Push(fn), this)
    OnHit(fn) => (this._hitFns.Push(fn), this)
    OnKey(fn) => (this._keyFns.Push(fn), this)
    OnError(fn) => (this._errFns.Push(fn), this)
    LastError := ""
    _errFns := []
    _Error(err) {
        SplitPath(err.File, &where)
        msg := err.Message " (" where ", line " err.Line ")"
        if (msg = this.LastError)                   ; once, not every tick
            return
        this.LastError := msg
        OutputDebug("AxGame rule error: " msg "`n" err.Stack)
        this.Hud("axRuleError", {Text: "Rule error: " msg, X: 14, Y: -60, Size: 13, Bold: false, Color: "#ff8a8a"})
        for fn in this._errFns
            try AxGuiCompat.CallFit(fn, [this, err])
    }
    Key(name) => this._keys.Has(name)
    Stats => this._stats
    ; one tick from the page: the keys, what hit what, where the watched
    ; things are; the rules run, and the answer goes back with an ack that
    ; times the round trip
    _Ask(clicked := false) {
        t0 := AxGame._Ms()
        this._asking := false
        raw := this._inbox, this._inbox := ""
        if clicked
            try raw := this.W.El(this.Id "_q").value
        m := ""
        try m := AxJson.Parse(raw)
        if !(m is Map) || m.Get("kind", "") != "tick"
            return
        keys := Map(), pressed := Map()
        for k in m.Get("keys", [])
            keys[k] := true
        for k in m.Get("pressed", [])
            pressed[k] := true
        this._keys := keys
        this._stats := m.Get("stats", Map())
        for id in m.Get("gone", [])                  ; what the page removed by itself (Life, Bounds)
            if this._ents.Has(id)
                this._ents.Delete(id)
        watch := m.Get("watch", Map())
        if (watch is Map)
            for id, st in watch
                if (IsObject(st) && this._ents.Has(id))
                    for k, v in st
                        this._ents[id].P[k] := v
        if IsObject(m.Get("list", ""))                 ; sent every few ticks: t.List is the latest
            this._list := m["list"]
        time := m.Get("time", m.Get("t", 0))
        t := {Seq: m.Get("seq", 0), Time: time, Dt: this.LastTick ? time - this.LastTick.Time : 0,
              Keys: keys, Pressed: pressed, Hits: m.Get("hits", []), Watch: watch, Stats: this._stats,
              List: this._list}
        this.LastTick := t
        ; The rules are your code. An error in one is shown on the game itself
        ; (and to OutputDebug, and to OnError), not swallowed and not a dialog
        ; thirty times a second -- and the page still gets its ack.
        try {
            for k in pressed
                for fn in this._keyFns
                    AxGuiCompat.CallFit(fn, [this, k])
            for h in t.Hits
                for fn in this._hitFns
                    AxGuiCompat.CallFit(fn, [this, h[1], h[2], h[3]])
            for fn in this._tickFns
                AxGuiCompat.CallFit(fn, [this, t])
        } catch as err
            this._Error(err)
        this._Cmd("ack", t.Seq, Round(AxGame._Ms() - t0, 2))
        this._Send()                                  ; at once: the page is waiting for the ack
    }
}

; One thing in the world: what eng.Spawn() gives back. X, Y, Z and the
; velocities are live for a watched entity (Watch: true, or eng.Watch(id)).
class AxGameEntity {
    __New(eng, id, props) {
        this.Eng := eng, this.Id := id, this.P := props
        if (props.Has("watch") && props["watch"])
            eng.Watch(id)
    }
    Get(name, d := 0) => this.P.Has(StrLower(name)) ? this.P[StrLower(name)] : d
    X => this.Get("x")
    Y => this.Get("y")
    Z => this.Get("z")
    VX => this.Get("vx")
    VY => this.Get("vy")
    VZ => this.Get("vz")
    Tag => this.Get("tag", "")
    Set(props) => (this.Eng.Set(this.Id, props), this)
    Kill() => this.Eng.Kill(this.Id)
}

; JSON already written, passed through _Cmd untouched
class AxGameRaw {
    __New(json) => this.Json := json
}
