#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
#Include %A_LineFile%\..\..\..\AxJson.ahk
; single-file exe: this component's stylesheet and script travel inside it
;@Ahk2Exe-AddResource %U_AxLib%\components\Canvas\AxCanvas.css, AX_COMPONENTS_CANVAS_AXCANVAS_CSS
;@Ahk2Exe-AddResource %U_AxLib%\components\Canvas\AxCanvas.js, AX_COMPONENTS_CANVAS_AXCANVAS_JS

; =============================================================================
;  AxCanvas -- a surface to draw on: shapes, text, pictures and gradients from
;  AutoHotkey, shapes that move, animate and can be dragged and clicked, and
;  freehand painting. Drawn by the page's own <canvas>, sharp on any screen.
;
;      cv := g.AddCanvas("vart w600 h400 Background=#151515").Component    ; after Show()
;      cv.Rect(20, 20, 200, 120, {Fill: ["#ff5f6d", "#ffc371"], Radius: 12})
;        .Text(40, 60, "Hello", {Size: 28, Bold: true, Fill: "#fff"})
;      ball := cv.Add("circle", {X: 300, Y: 200, R: 30, Fill: "accent", Drag: true})
;      ball.Animate({X: 500}, 800, "bounce")
;      cv.OnClick((cv, shape, x, y) => ToolTip(shape ? shape.Id : x ", " y))
;
;  --------------------------------------------------------- the picture
;  Drawn once and kept; the scene above it can change without drawing it again.
;    Clear(colour?)                      Background(colour)
;    Rect(x, y, w, h, style?)            Circle(x, y, r, style?)
;    Ellipse(x, y, rx, ry, style?)       Arc(x, y, r, fromDeg, toDeg, style?)
;    Line(x1, y1, x2, y2, style?)        Poly(points, style?)   [x1, y1, x2, y2 ...]
;    Path(svgPathData, style?)           Text(x, y, text, style?)
;    Image(file or url, x, y, w?, h?, style?)
;    Ctx(method, args*)  Ctx("=property", value)    anything else a 2D context does
;  A style is an object, or a colour string (a fill; a line's stroke):
;    Fill Stroke Width Radius Opacity Rotate Shadow ("#000 12 0 4": colour
;    blur x y) Dash ([6, 4]) Cap Join Blend, and for text Size Font Bold
;    Italic Align Baseline. A colour is #rgb, #rrggbb, rgba(...), a name, or
;    accent / text / back / muted from the window's look. A list of colours is
;    a gradient across the shape: Fill: ["#f00", "#00f"], Angle: 90, Radial.
;
;  ------------------------------------------------------------ the scene
;    s := cv.Add(kind, props)   kind: rect circle ellipse arc line poly path text image
;         props: the geometry (X Y W H R RX RY X2 Y2 Points D Text Src Start End
;         Pie) and a style, plus Id, Drag (true / "x" / "y"), Cursor, Hit (false:
;         the pointer goes through), Hidden, Bounds (false: may leave the canvas)
;    s.Set(props)  s.Move(x, y)  s.Animate(props, ms, ease?, done?)  s.Remove()
;    s.Front()  s.Back()  s.X  s.Y  s.Get(name)  s.Id
;         ease: linear in out inout back bounce elastic
;    cv.Shape(id)  cv.Shapes  cv.ClearShapes()  cv.At(x, y) -> shape or ""
;
;  ------------------------------------------------------------ painting
;    Paint(on := true, colour?, size?)  Eraser(on := true)  Undo()
;
;  -------------------------------------------------------------- events
;    OnClick(fn(cv, shape, x, y, button))  OnDoubleClick(...)  OnDrop(fn(cv, shape, x, y))
;    OnHover(fn(cv, shape, was))  OnPaint(fn(cv))  OnResize(fn(cv, w, h))
;    s.OnClick(fn(shape, x, y, button))  s.OnDrop(fn(shape, x, y))
;    shape is "" where the canvas itself was clicked.
;
;  ---------------------------------------------------------------- more
;    Width  Height  Every(ms, fn(cv))  Every(0)  Save(path.png)  DataUri()
;    Hold() ... Flush(): drawing is sent in one batch at the end of the
;    current thread; Hold keeps it back until Flush, for a frame built over
;    several threads.
;
;  Options: Background=colour  Paint  Brush=colour  Size=n  (and the usual w h
;  Fill Grow). ES5 in the page (AxCanvas.js): everything here is IE11's canvas.
; =============================================================================
class AxCanvas {
    static _reg := AxRich.Register("Canvas", "components\Canvas\AxCanvas.css",
        (*) => AxRich.AddMethod("AddCanvas", (c, o := "", v := "") => AxCanvas._Add(c, o, v)))
    static JsPath := "components\Canvas\AxCanvas.js"

    ; ------------------------------------------------------------- markup
    ; What shows before the page's script runs, and on the studio's canvas,
    ; where it never does: a dashed box that says what it is.
    static Html(id, cfg, attrs := "") {
        E := (x) => AxWindow._Esc(x)
        st := cfg.HasOwnProp("Style") ? cfg.Style : ""
        return '<div id="' E(id) '" class="axcv' (cfg.HasOwnProp("Class") ? " " E(cfg.Class) : "") '"'
             . ' data-role="canvas" style="' E(st) '">'
             . '<canvas class="axcv-c"></canvas>'
             . '<div class="axcv-ph"><span class="ico">&#xE771;</span> Canvas</div>'
             . '<textarea class="axcv-q" id="' E(id) '_q"></textarea><span class="axcv-req" id="' E(id) '_req"></span></div>'
    }

    ; ----------------------------------------------------------- AxGui
    static _Add(container, opts, value) {
        o := container._Opt(opts, "canvas")
        kv := (k, d := "") => container._Kv(o, k, d)
        cfg := {Background: kv("background"), Paint: o.Flags.Has("paint") && o.Flags["paint"],
                Brush: kv("brush", "text"), Size: kv("size", 4)}
        h := (o.H != "") ? Integer(o.H) : 240
        cfg.Style := "height:" h "px;" (o.W != "" ? "width:" o.W "px;" : "") kv("style")
        cfg.Class := (o.W = "" || o.Flags.Has("fill")) ? "fill" : ""
        c := container._Reg(o, "Canvas", AxCanvas.Html(o.Id, cfg))
        container.G.OnReady((w) => AxCanvas(w, o.Id, cfg))
        return c
    }

    ; ======================================================== a canvas
    __New(win, id, cfg) {
        this.W := win, this.Id := id, this.Cfg := cfg
        this._buf := "", this._held := 0, this._ready := false, this._n := 0, this._tick := ""
        this._shp := Map(), this._shp.CaseSense := false
        this._on := Map(), this._done := Map()
        this._flushFn := ObjBindMethod(this, "_Auto")
        AxRich.Use(win, "Canvas")
        AxRich.Bind(win, id, this)
        if !AxRich.UseJs(win, AxCanvas.JsPath)
            return
        this._inbox := [], this._drainFn := ObjBindMethod(this, "_Drain")
        try {
            this.JS.make(id, AxJson.Stringify(Map("background", cfg.Background), ""))
            this._ready := true
            ; messages come in through a function handed to the page (a call is
            ; far cheaper than a click down the library's click path) and are
            ; handled on a thread of their own, after the page's turn
            this.JS.hook(id, ObjBindMethod(this, "_Hear"))
        }
        win.On("click", id "_req", (*) => this._Ask())
        if cfg.Paint
            this.Paint(true, cfg.Brush, cfg.Size)
    }
    JS => this.W.Doc.parentWindow.AXCV

    ; ------------------------------------------------------- the batch
    ; Every call adds one command to a JSON array written straight into a
    ; string; the page gets the lot in one call, at the end of the thread.
    _Cmd(op, args*) {
        s := '["' op '"'
        for a in args
            s .= "," AxCanvas._J(a)
        this._buf .= (this._buf = "" ? "" : ",") s "]"
        if (!this._held && !this._armed)
            this._armed := true, SetTimer(this._flushFn, -1)
        return this
    }
    _armed := false
    Hold() => (this._held += 1, this)
    ; Flush() sends what is waiting; after Hold() it ends that hold first
    Flush() {
        if (this._held > 0)
            this._held -= 1
        return this._held ? this : this._Send()
    }
    ; the end-of-thread send: not while held
    _Auto() {
        this._armed := false
        return this._held ? this : this._Send()
    }
    _Send() {
        if (this._buf = "" || !this._ready)
            return this
        b := this._buf, this._buf := ""
        try this.JS.run(this.Id, "[" b "]")
        return this
    }
    static _J(a) {
        if (a is Array)                      ; a list (points, a gradient) written as it goes: thousands of numbers are common
            return AxCanvas._Arr(a)
        if IsObject(a)
            return AxJson.Stringify(AxCanvas._Props(a), "")
        if (Type(a) = "Integer" || Type(a) = "Float")
            return String(a)
        return '"' AxJson.Escape(String(a)) '"'
    }
    static _Arr(a) {
        s := ""
        for v in a {
            if IsObject(v)
                s .= "," AxCanvas._J(v)
            else if (Type(v) = "Integer" || Type(v) = "Float")
                s .= "," v
            else
                s .= ',"' AxJson.Escape(String(v)) '"'
        }
        return "[" SubStr(s, 2) "]"
    }
    ; a style or props object as the page wants it: keys in lower case, and a
    ; number given as text sent as a number, so that it can be animated
    static _Props(o) {
        if (o is Array)
            return o
        m := Map()
        for k, v in (o is Map ? o : o.OwnProps()) {
            k := StrLower(k)
            if (k = "points")
                k := "pts", v := AxCanvas._Points(v)
            else if (!IsObject(v) && !(k ~= "^(text|id|src|d|font|fill|stroke|cursor|shadow|blend|align|baseline|cap|join)$") && IsNumber(v))
                v := v + 0
            m[k] := IsObject(v) && !(v is Array) ? AxCanvas._Props(v) : v
        }
        return m
    }
    ; [x1, y1, x2, y2 ...] or [[x1, y1], [x2, y2] ...] -> the flat list
    static _Points(p) {
        out := []
        for v in p {
            if IsObject(v)
                out.Push(v[1] + 0, v[2] + 0)
            else
                out.Push(v + 0)
        }
        return out
    }
    static _Style(st, lineish := false) {
        if IsObject(st)
            return st
        if (st = "")
            return Map()
        return lineish ? Map("stroke", st) : Map("fill", st)
    }

    ; ---------------------------------------------------------- the picture
    Clear(colour := "") => this._Cmd("clear", colour)
    Background(colour) => this._Cmd("bg", colour)
    Rect(x, y, w, h, st := "") => this._Cmd("rect", x + 0, y + 0, w + 0, h + 0, AxCanvas._Style(st))
    Circle(x, y, r, st := "") => this._Cmd("circle", x + 0, y + 0, r + 0, AxCanvas._Style(st))
    Ellipse(x, y, rx, ry, st := "") => this._Cmd("ellipse", x + 0, y + 0, rx + 0, ry + 0, AxCanvas._Style(st))
    Arc(x, y, r, a0, a1, st := "") => this._Cmd("arc", x + 0, y + 0, r + 0, a0 + 0, a1 + 0, AxCanvas._Style(st, true))
    Line(x1, y1, x2, y2, st := "") => this._Cmd("line", x1 + 0, y1 + 0, x2 + 0, y2 + 0, AxCanvas._Style(st, true))
    Poly(points, st := "") => this._Cmd("poly", AxCanvas._Points(points), AxCanvas._Style(st, true))
    Path(d, st := "") => this._Cmd("path", String(d), AxCanvas._Style(st))
    Text(x, y, text, st := "") => this._Cmd("text", x + 0, y + 0, String(text), AxCanvas._Style(st))
    Image(src, x, y, w := 0, h := 0, st := "") => this._Cmd("image", AxCanvas._Src(src), x + 0, y + 0, w + 0, h + 0, AxCanvas._Style(st))
    Ctx(method, args*) {
        if (SubStr(method, 1, 1) = "=")
            return this._Cmd("ctx", method, args.Length ? args[1] : "")
        return this._Cmd("ctx", method, args)
    }
    ; a picture on disk goes in as a data: URI -- a file: URL would mark the
    ; canvas as foreign, and Save() would then be refused
    static _Src(src) {
        if (src = "" || RegExMatch(src, "i)^(https?|data|res|about):"))
            return src
        p := src
        if !RegExMatch(p, "^[A-Za-z]:|^\\\\")
            p := A_ScriptDir "\" p
        try return AxWindow.ImageDataUri(p)
        return src
    }

    ; ------------------------------------------------------------ the scene
    Add(kind, props := "") {
        props := IsObject(props) ? AxCanvas._Props(props) : Map()
        id := props.Has("id") ? props["id"] : "s" (++this._n)
        if (StrLower(kind) = "image" && props.Has("src"))
            props["src"] := AxCanvas._Src(props["src"])
        s := AxCanvasShape(this, id, StrLower(kind), props)
        this._shp[id] := s
        this._Cmd("add", id, StrLower(kind), props)
        return s
    }
    Shape(id) => this._shp.Has(id) ? this._shp[id] : ""
    Shapes {
        get {
            out := []
            for id, s in this._shp
                out.Push(s)
            return out
        }
    }
    ClearShapes() {
        this._shp := Map(), this._shp.CaseSense := false
        return this._Cmd("wipe")
    }
    At(x, y) {
        this._Send()
        id := ""
        try id := this.JS.call(this.Id, "at", "[" (x + 0) "," (y + 0) "]")
        return this.Shape(id)
    }

    ; ------------------------------------------------------------ painting
    Paint(on := true, colour := "", size := "") {
        if !on
            return this._Cmd("paint", 0)
        b := Map()
        if (colour != "")
            b["color"] := colour
        if (size != "")
            b["size"] := size + 0
        this._brush := b
        return this._Cmd("paint", b)
    }
    _brush := ""
    Eraser(on := true) {
        b := IsObject(this._brush) ? this._brush.Clone() : Map()
        b["eraser"] := on ? 1 : 0
        if on && !b.Has("size")
            b["size"] := 18
        return this._Cmd("paint", b)
    }
    Undo() => this._Cmd("undo")

    ; -------------------------------------------------------------- events
    _Listen(kind, fn) {
        if !this._on.Has(kind)
            this._on[kind] := []
        this._on[kind].Push(fn)
        return this._Cmd("listen", kind, 1)
    }
    OnClick(fn) => this._Listen("click", fn)
    OnDoubleClick(fn) => this._Listen("dblclick", fn)
    OnDrop(fn) => this._Listen("drop", fn)
    OnHover(fn) => this._Listen("hover", fn)
    OnPaint(fn) => this._Listen("paint", fn)
    OnResize(fn) => this._Listen("resize", fn)
    _Fire(kind, args) {
        if this._on.Has(kind)
            for fn in this._on[kind].Clone()
                try AxGuiCompat.CallFit(fn, args)
    }
    _Hear(json) {
        this._inbox.Push(json)
        if (this._inbox.Length = 1)
            SetTimer(this._drainFn, -1)
        return 0
    }
    _Drain() {
        while this._inbox.Length
            this._Ask(this._inbox.RemoveAt(1))
    }
    _Ask(raw := "") {
        if (raw = "")
            try raw := this.W.El(this.Id "_q").value
        if (raw = "")
            return
        m := ""
        try m := AxJson.Parse(raw)
        if !(m is Map)
            return
        kind := m.Get("kind", "")
        s := this.Shape(m.Get("id", ""))
        switch kind {
        case "click", "dblclick":
            x := m.Get("x", 0), y := m.Get("y", 0), b := m.Get("button", 1)
            if (IsObject(s) && kind = "click")
                s._Fire("click", [s, x, y, b])
            this._Fire(kind, [this, s, x, y, b])
        case "drop":
            if IsObject(s) {
                s.P["x"] := m.Get("x", 0), s.P["y"] := m.Get("y", 0)
                s._Fire("drop", [s, s.X, s.Y])
            }
            this._Fire("drop", [this, s, m.Get("x", 0), m.Get("y", 0)])
        case "hover":
            this._Fire("hover", [this, s, this.Shape(m.Get("was", ""))])
        case "paint":
            this._Fire("paint", [this])
        case "resize":
            this._Fire("resize", [this, m.Get("w", 0), m.Get("h", 0)])
        case "done":
            t := m.Get("token", 0)
            if this._done.Has(t) {
                fn := this._done[t]
                this._done.Delete(t)
                try AxGuiCompat.CallFit(fn, [s, this])
            }
        }
    }

    ; ---------------------------------------------------------------- more
    _Size() {
        this._Send()
        r := ""
        try r := this.JS.call(this.Id, "size", "[]")
        return (r != "") ? AxJson.Parse(r) : Map("w", 0, "h", 0)
    }
    Width => this._Size()["w"]
    Height => this._Size()["h"]
    ; fn(cv) every ms, drawn in one batch each time; Every(0) stops it
    Every(ms, fn := "") {
        if IsObject(this._tick)
            SetTimer(this._tick, 0), this._tick := ""
        if (ms <= 0 || !IsObject(fn))
            return this
        this._tick := () => (AxGuiCompat.CallFit(fn, [this]), this._Send())
        SetTimer(this._tick, ms)
        return this
    }
    DataUri(withScene := true) {
        this._Send()
        r := ""
        try r := this.JS.call(this.Id, "png", "[" (withScene ? 1 : 0) "]")
        return r
    }
    ; the picture (and the scene, unless told not to) as a PNG file
    Save(path, withScene := true) {
        uri := this.DataUri(withScene)
        if !(i := InStr(uri, ","))
            return false
        b64 := SubStr(uri, i + 1)
        n := 0
        DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &n, "Ptr", 0, "Ptr", 0)
        buf := Buffer(n)
        if !DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &n, "Ptr", 0, "Ptr", 0)
            return false
        f := FileOpen(path, "w")
        f.RawWrite(buf, n)
        f.Close()
        return true
    }
}

; One shape of a canvas's scene: what cv.Add() gives back.
class AxCanvasShape {
    __New(cv, id, kind, props) {
        this.Cv := cv, this.Id := id, this.Kind := kind, this.P := props
        this._on := Map()
    }
    Get(name, d := "") => this.P.Has(StrLower(name)) ? this.P[StrLower(name)] : d
    X => this.Get("x", 0)
    Y => this.Get("y", 0)
    Set(props) {
        p := AxCanvas._Props(props)
        for k, v in p
            this.P[k] := v
        this.Cv._Cmd("set", this.Id, p)
        return this
    }
    Move(x, y) => this.Set(Map("x", x + 0, "y", y + 0))
    ; the numbers and #rrggbb colours in props, eased there over ms
    Animate(props, ms := 400, ease := "out", done := "") {
        p := AxCanvas._Props(props)
        for k, v in p
            this.P[k] := v
        static seq := 0
        t := 0
        if IsObject(done) {
            t := ++seq
            this.Cv._done[t] := done
        }
        this.Cv._Cmd("anim", this.Id, p, ms + 0, ease, t)
        return this
    }
    Remove() {
        if this.Cv._shp.Has(this.Id)
            this.Cv._shp.Delete(this.Id)
        this.Cv._Cmd("del", this.Id)
    }
    Front() => (this.Cv._Cmd("order", this.Id, "front"), this)
    Back() => (this.Cv._Cmd("order", this.Id, "back"), this)
    OnClick(fn) => (this._Hook("click", fn), this.Cv._Cmd("listen", "click", 1), this)
    OnDrop(fn) => (this._Hook("drop", fn), this.Cv._Cmd("listen", "drop", 1), this)
    _Hook(kind, fn) {
        if !this._on.Has(kind)
            this._on[kind] := []
        this._on[kind].Push(fn)
    }
    _Fire(kind, args) {
        if this._on.Has(kind)
            for fn in this._on[kind].Clone()
                try AxGuiCompat.CallFit(fn, args)
    }
}
