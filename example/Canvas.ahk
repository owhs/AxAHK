#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\lib\AxGui.ahk
#Include ..\lib\AxAssets.ahk

; =============================================================================
;  Canvas.ahk -- drawing, animation and sound, all driven from AutoHotkey.
;
;    Paint     freehand painting: colours, brush sizes, an eraser, undo, save as PNG
;    Shapes    a scene you can drag about; click a shape to spin it, shuffle them
;    Clock     a clock face drawn once, with hands that tick every second
;    Patterns  spirograph curves of thousands of points, redrawn as you move a slider
;    Sound     an MP3 player you control from code, with a disc that turns as it plays
;
;  The canvas is AddCanvas (lib\components\Canvas); the player is AddAudio.
; =============================================================================

g := AxGui({Title: "Canvas & sound (Proof of concept)", Width: 1040, Height: 720, MinWidth: 720, MinHeight: 520, Theme: "dark"})
g.AddStatusBar([{Id: "msg", Text: "Ready", Icon: "E930", Grow: true},
                {Id: "info", Text: "", Width: 260, Dim: true}])
Say(text, info := "") => (g.Status("msg", text), info != "" ? g.Status("info", info) : "")

; ------------------------------------------------------------------- Paint
g.AddPage("paint", "Paint", "E771")
Colours := ["#ffffff", "#ff5f6d", "#ffb900", "#7ed957", "#00b7c3", "#3a96dd", "#8764b8", "#e3008c", "#2b2b2b"]
palette := g.AddPalette("vpaintColour Small Value=#ffffff", Colours[1] "," Colours[2] "," Colours[3] "," Colours[4] ","
                      . Colours[5] "," Colours[6] "," Colours[7] "," Colours[8] "," Colours[9])
g.AddText("x+18", "Size")
brush := g.AddSlider("vbrushSize x+8 w150 Min=1 Max=60", 6)
eraser := g.AddButton("veraser x+18 Subtle Icon=E75C", "Eraser")
g.AddButton("x+4 Subtle Icon=E7A7", "Undo").OnClick((*) => paint.Undo())
g.AddButton("x+4 Subtle Icon=E74D", "Clear").OnClick((*) => paint.Clear())
g.AddButton("x+4 Icon=E74E", "Save...").OnClick((*) => SavePaint())
paintCtl := g.AddCanvas("vpaintCv Fill Grow h300 Paint Brush=#ffffff Size=6 Background=#1d1d1d")

Erasing := false
palette.OnChange(PickColour)
brush.OnChange((c, v, *) => Erasing ? paint.Eraser() : paint.Paint(true, palette.Value, v))
eraser.OnClick(ToggleEraser)
PickColour(c, v, *) {
    global Erasing := false
    eraser.Text := "Eraser"
    paint.Paint(true, v, brush.Value)
}
ToggleEraser(*) {
    global Erasing
    Erasing := !Erasing
    eraser.Text := Erasing ? "Brush" : "Eraser"
    if Erasing
        paint.Eraser()
    else
        paint.Paint(true, palette.Value, brush.Value)
    Say(Erasing ? "Eraser: drag to rub out" : "Brush")
}
SavePaint() {
    path := FileSelect("S16", A_Desktop "\painting.png", "Save the painting", "PNG picture (*.png)")
    if (path = "")
        return
    if !RegExMatch(path, "i)\.png$")
        path .= ".png"
    if paint.Save(path)
        Say("Saved " path)
}

; ------------------------------------------------------------------ Shapes
g.AddPage("shapes", "Shapes", "E80A")
g.AddButton("Accent Icon=E8B1", "Shuffle").OnClick((*) => Shuffle())
g.AddButton("x+8 Icon=E8FD", "Line up").OnClick((*) => LineUp())
g.AddButton("x+8 Icon=E710", "Add a shape").OnClick((*) => AddShape())
g.AddButton("x+8 Subtle Icon=E74D", "Clear").OnClick((*) => (scene.ClearShapes(), Say("Cleared")))
g.AddText("x+16 Hint", "Drag a shape. Click one to spin it.")
sceneCtl := g.AddCanvas("vsceneCv Fill Grow h300")

; ------------------------------------------------------------------- Clock
g.AddPage("clock", "Clock", "E823")
clockCtl := g.AddCanvas("vclockCv Fill Grow h300")

; ---------------------------------------------------------------- Patterns
g.AddPage("patterns", "Patterns", "E790")
g.AddText("", "Outer")
bigR := g.AddSlider("vbigR x+8 w150 Min=40 Max=200", 120)
g.AddText("x+16", "Inner")
smallR := g.AddSlider("vsmallR x+8 w150 Min=5 Max=190", 47)
g.AddText("x+16", "Pen")
pen := g.AddSlider("vpen x+8 w150 Min=5 Max=200", 80)
g.AddButton("x+16 Icon=E8B1", "Surprise me").OnClick((*) => Surprise())
patternCtl := g.AddCanvas("vpatternCv Fill Grow h300")
for slider in [bigR, smallR, pen]
    slider.OnChange((*) => DrawPattern())

; ------------------------------------------------------------------- Sound
g.AddPage("sound", "Sound", "E767")
playerCtl := g.AddAudio("vplayer Fill Loop", "assets\tune.mp3")
g.AddButton("Accent Icon=E768", "Play / pause").OnClick((*) => player.Toggle())
g.AddButton("x+8 Icon=E71A", "Stop").OnClick((*) => player.Stop())
g.AddButton("x+8 Subtle Icon=E892", "5 s back").OnClick((*) => player.Seek(player.Position - 5))
g.AddButton("x+4 Subtle Icon=E893", "5 s on").OnClick((*) => player.Seek(player.Position + 5))
g.AddText("", "Speed")
speed := g.AddSegmented("vspeed x+8 Choose2", "0.5:0.5×|1:1×|1.5:1.5×|2:2×")
g.AddText("x+18", "Volume")
volume := g.AddSlider("vvolume x+8 w120", 80)
g.AddButton("x+18 Subtle Icon=EA8F", "Ding").OnClick((*) => g.PlaySound("assets\ding.mp3"))
discCtl := g.AddCanvas("vdiscCv Fill Grow h260")
speed.OnChange((c, v, *) => (player.Rate := v, Say("Speed " v "×")))
volume.OnChange((c, v, *) => player.Volume := v)

g.Show()

; The components behind the controls exist once the window is up.
paint  := paintCtl.Component
scene  := sceneCtl.Component
clock  := clockCtl.Component
patt   := patternCtl.Component
player := playerCtl.Component
disc   := discCtl.Component

g.OnPage((id, *) => PageShown(id))
PageShown(id) {
    switch id {
    case "paint":    Say("Paint: drag on the canvas", "brush " brush.Value " px")
    case "shapes":
        if !Populated {                     ; first shown: now the canvas has a size to spread them over
            global Populated := true
            for k in Kinds
                AddShape(k)
        }
        Say("Shapes: drag them, click them", scene.Shapes.Length " shapes")
    case "clock":    Say("A face drawn once; the hands are shapes that move", "")
    case "patterns": DrawPattern()
    case "sound":    Say("tune.mp3, made with ffmpeg for this example", "")
    }
}

; ------------------------------------------------------------ Paint, set up
paint.OnPaint((*) => Say("A stroke; Undo takes it back"))
Say("Paint: drag on the canvas", "brush 6 px")

; ------------------------------------------------------------- Shapes, set up
Kinds := ["circle", "rect", "star", "ellipse", "circle", "rect", "star"]
AddShape(kind := "") {
    static n := 0
    w := Max(scene.Width, 300), h := Max(scene.Height, 200)
    kind := kind != "" ? kind : Kinds[Random(1, Kinds.Length)]
    col := Colours[Mod(n++, 8) + 1]
    x := Random(60, w - 60), y := Random(60, h - 60)
    common := {Fill: [col, Shade(col)], Drag: true, Shadow: "rgba(0,0,0,.45) 14 0 6", Opacity: 0}
    switch kind {
    case "circle":  s := scene.Add("circle", Mix(common, {X: x, Y: y, R: Random(26, 46)}))
    case "rect":    s := scene.Add("rect", Mix(common, {X: x - 45, Y: y - 30, W: 90, H: 60, Radius: 12}))
    case "ellipse": s := scene.Add("ellipse", Mix(common, {X: x, Y: y, RX: 56, RY: 30}))
    default:        s := scene.Add("poly", Mix(common, {X: x, Y: y, Points: Star(5, 44, 20)}))
    }
    s.Animate({Opacity: 1}, 350)
    Say("Added a " kind, scene.Shapes.Length " shapes")
    return s
}
Mix(a, b) {
    for k, v in b.OwnProps()
        a.%k% := v
    return a
}
; a colour a little darker, for the far end of a shape's gradient
Shade(hex) {
    n := Integer("0x" SubStr(hex, 2))
    r := (n >> 16) & 255, gg := (n >> 8) & 255, b := n & 255
    return Format("#{:02x}{:02x}{:02x}", r * 0.62, gg * 0.62, b * 0.62)
}
; a star around 0,0: points, outer and inner radius
Star(points, outer, inner) {
    pts := []
    loop points * 2 {
        a := (A_Index - 1) * 3.14159265 / points - 3.14159265 / 2
        r := Mod(A_Index, 2) ? outer : inner
        pts.Push(Round(r * Cos(a), 1), Round(r * Sin(a), 1))
    }
    return pts
}
; where a shape's X and Y go for it to be centred on cx, cy
Anchor(s, cx, cy) {
    switch s.Kind {
    case "rect": return {X: cx - s.Get("w") / 2, Y: cy - s.Get("h") / 2}
    default:     return {X: cx, Y: cy}
    }
}
Shuffle() {
    w := scene.Width, h := scene.Height
    for s in scene.Shapes
        s.Animate(Anchor(s, Random(70, w - 70), Random(70, h - 70)), 900, "back")
    Say("Shuffled")
}
LineUp() {
    list := scene.Shapes, w := scene.Width, h := scene.Height
    if !list.Length
        return
    step := (w - 120) / Max(list.Length - 1, 1)
    for i, s in list
        s.Animate(Anchor(s, 60 + (i - 1) * step, h / 2), 700 + i * 60, "bounce")
    Say("Lined up")
}
scene.OnClick((cv, s, x, y) => s ? (s.Animate({Rotate: s.Get("rotate", 0) + 360}, 800, "back"), Say("Spun " s.Id)) : "")
scene.OnDrop((cv, s, x, y) => Say("Moved " s.Id " to " x ", " y))
Populated := false

; -------------------------------------------------------------- Clock, set up
Hands := Map()
DrawFace(*) {
    w := clock.Width, h := clock.Height
    cx := w / 2, cy := h / 2 - 10, r := Max(Min(w, h) / 2 - 40, 60)
    clock.Clear()
        .Circle(cx, cy, r + 14, {Fill: ["#3a3a3a", "#111"], Radial: true, Shadow: "rgba(0,0,0,.6) 30 0 10"})
        .Circle(cx, cy, r, {Fill: "#1b1b1b", Stroke: "#444", Width: 2})
    loop 60 {
        a := (A_Index - 1) * 6 * 3.14159265 / 180
        big := !Mod(A_Index - 1, 5)
        r1 := r - (big ? 16 : 7)
        clock.Line(cx + r1 * Sin(a), cy - r1 * Cos(a), cx + (r - 3) * Sin(a), cy - (r - 3) * Cos(a),
                   {Stroke: big ? "#eee" : "#777", Width: big ? 3 : 1})
        if big {
            n := (A_Index - 1) // 5, n := n ? n : 12
            clock.Text(cx + (r - 36) * Sin(a), cy - (r - 36) * Cos(a) - 11, n, {Size: 18, Fill: "#ddd", Align: "center"})
        }
    }
    Hands["c"] := {X: cx, Y: cy, R: r}
    clock.ClearShapes()
    Hands["h"] := clock.Add("line", {X: cx, Y: cy, X2: cx, Y2: cy, Stroke: "#fff", Width: 7, Hit: false})
    Hands["m"] := clock.Add("line", {X: cx, Y: cy, X2: cx, Y2: cy, Stroke: "#ddd", Width: 4, Hit: false})
    Hands["s"] := clock.Add("line", {X: cx, Y: cy, X2: cx, Y2: cy, Stroke: "accent", Width: 2, Hit: false})
    clock.Add("circle", {X: cx, Y: cy, R: 7, Fill: "accent", Hit: false})
    Hands["t"] := clock.Add("text", {X: cx, Y: cy + r + 22, Text: "", Size: 15, Fill: "muted", Align: "center", Hit: false})
    Tick(true)
}
Tick(jump := false) {
    if !Hands.Has("c")
        return
    c := Hands["c"], t := A_Hour * 3600 + A_Min * 60 + A_Sec
    for name, spec in Map("h", [Mod(t / 3600, 12) * 30, 0.5], "m", [t / 60 * 6, 0.78], "s", [A_Sec * 6, 0.88]) {
        a := spec[1] * 3.14159265 / 180, len := c.R * spec[2]
        to := {X2: c.X + len * Sin(a), Y2: c.Y - len * Cos(a)}
        if (jump || name != "s")
            Hands[name].Set(to)
        else
            Hands[name].Animate(to, 260, "elastic")
    }
    Hands["t"].Set({Text: FormatTime(, "dddd d MMMM  ·  HH:mm:ss")})
}
clock.OnResize(DrawFace)
DrawFace()
clock.Every(1000, (*) => Tick())

; ----------------------------------------------------------- Patterns, set up
; A hypotrochoid: the path of a pen on a small wheel rolling inside a big one.
DrawPattern() {
    t0 := A_TickCount
    w := patt.Width, h := patt.Height, cx := w / 2, cy := h / 2
    ; (big and small, not R and r: AutoHotkey's names ignore case)
    big := bigR.Value + 0, small := smallR.Value + 0, d := pen.Value + 0
    if (small = big)
        small -= 1
    ; the curve closes after small / gcd(big, small) turns of the big wheel
    a := big, b := small
    while b
        tmp := b, b := Mod(a, b), a := tmp
    turns := small / a
    k := Min(w, h) / 2 / (Abs(big - small) + d + 4)      ; fitted to the canvas
    n := Min(Round(turns * 360), 12000), pts := []
    loop n + 1 {
        th := (A_Index - 1) / n * turns * 2 * 3.14159265
        pts.Push(Round(cx + k * ((big - small) * Cos(th) + d * Cos((big - small) / small * th)), 1),
                 Round(cy + k * ((big - small) * Sin(th) - d * Sin((big - small) / small * th)), 1))
    }
    patt.Clear().Poly(pts, {Stroke: ["#ff5f6d", "#ffc371", "#7ed957", "#00b7c3", "#8764b8"], Angle: 45, Width: 1.4, Opacity: 0.9})
        .Text(16, 14, "outer " big "   inner " small "   pen " d, {Size: 13, Fill: "muted"})
    patt.Flush()
    Say("Patterns: move a slider", (n + 1) " points, drawn in " A_TickCount - t0 " ms")
}
Surprise() {
    bigR.Value := Random(80, 200), smallR.Value := Random(10, 150), pen.Value := Random(20, 200)
    DrawPattern()
}
patt.OnResize((*) => DrawPattern())

; -------------------------------------------------------------- Sound, set up
Parts := Map()     ; (not "Disc": that is the canvas, disc -- names ignore case)
DrawDisc(*) {
    w := disc.Width, h := disc.Height, cx := w / 2, cy := h / 2, r := Max(Min(w, h) / 2 - 24, 50)
    disc.Clear().Circle(cx, cy, r, {Fill: ["#2a2a2a", "#0a0a0a"], Radial: true, Shadow: "rgba(0,0,0,.6) 24 0 8"})
    loop 14
        disc.Circle(cx, cy, r - 8 - A_Index * (r * 0.045), {Stroke: "rgba(255,255,255,.05)", Width: 1})
    disc.ClearShapes()
    Parts["c"] := {X: cx, Y: cy, R: r}
    Parts["ring"] := disc.Add("arc", {X: cx, Y: cy, R: r + 10, Start: 0, End: 0.1, Stroke: "accent", Width: 4, Hit: false})
    Parts["label"] := disc.Add("circle", {X: cx, Y: cy, R: r * 0.34, Fill: ["accent", "#222"], Radial: true, Hit: false})
    Parts["spoke"] := disc.Add("rect", {X: cx - 3, Y: cy - r * 0.9, W: 6, H: r * 0.5, Radius: 3, Fill: "rgba(255,255,255,.35)", Hit: false})
    Parts["time"] := disc.Add("text", {X: cx, Y: cy - 9, Text: "0:00", Size: 16, Bold: true, Fill: "#fff", Align: "center", Hit: false})
    ShowTime(player.Position, player.Duration)
}
; the spoke is turned about the middle of the disc, not its own middle, so
; it is put where the turn takes it
ShowTime(pos, dur) {
    if !Parts.Has("c")
        return
    c := Parts["c"], a := pos * 200 * 3.14159265 / 180, far := c.R * 0.65
    Parts["spoke"].Set({X: c.X + far * Sin(a) - 3, Y: c.Y - far * Cos(a) - c.R * 0.25, Rotate: pos * 200})
    Parts["ring"].Set({End: dur ? Max(pos / dur * 360, 0.1) : 0.1})
    secs := Floor(pos)
    Parts["time"].Set({Text: Format("{}:{:02}", secs // 60, Mod(secs, 60))})
}
player.OnTime((a, pos, dur) => ShowTime(pos, dur), 50)
player.OnPlay((*) => Say("Playing", "speed " player.Rate "×, volume " player.Volume))
player.OnPause((*) => Say("Paused at " Round(player.Position, 1) " s"))
player.OnReady((a, dur) => g.Status("info", "tune.mp3, " Round(dur, 1) " s"))
player.OnError((a, msg) => Say("Can't play it: " msg))
player.Volume := 80
disc.OnResize(DrawDisc)
DrawDisc()
