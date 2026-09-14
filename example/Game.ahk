#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\lib\AxGui.ahk
#Include ..\lib\AxAssets.ahk

; =============================================================================
;  Game.ahk -- Gem Rush: a low-poly 3D game on AddGame, the library's small
;  game engine.
;
;  Fly the ship with WASD or the arrows, Space to hop, Shift to boost. Pick up
;  the gems; the rocks roll after you. Every 120 points is a level: more
;  rocks, and faster. P pauses, Enter starts again after the game is over.
;
;  Who does what:
;    the page (AxGame.js)   60 steps a second: the keys, movement, gravity,
;                           rolling, chasing, collisions, particles, drawing
;    this script            the rules, ~30 ticks a second: what a gem or a
;                           rock does to you, spawning, score, lives, levels,
;                           the HUD -- and the debug panel on the right, which
;                           reads the engine's numbers and writes its settings
; =============================================================================

g := AxGui({Title: "Gem Rush", Width: 1180, Height: 760, MinWidth: 860, MinHeight: 560, Theme: "dark", Icon: "E7FC",
            Css: "#panel { height: 300px; overflow-y: auto; overflow-x: hidden; margin-bottom: 0; }"})
g.AddStatusBar([{Id: "msg", Text: "Click the game, then WASD or the arrows", Icon: "E7FC", Grow: true},
                {Id: "fps", Text: "", Width: 120, Dim: true}])

gameCtl := g.AddGame("vgame Grow h420 Tick=30")

; ------------------------------------------------------------ the debug panel
panel := g.AddCard("vpanel x+12 w300 Grow", "Engine")          ; grows with the game, scrolls inside (Css above)
g.AddText("Caption", "Read from the engine a few times a second")
statFps   := g.AddText("vstatFps Fill", "-")
statTris  := g.AddText("vstatTris Fill", "-")
statAhk   := g.AddText("vstatAhk Fill", "-")
statShip  := g.AddText("vstatShip Fill", "-")
g.AddSeparator()
g.AddText("Caption", "Written to the engine as you change them")
chkStats := g.AddCheckBox("vchkStats Checked", "Stats on the game")
chkCol   := g.AddCheckBox("vchkCol", "Show colliders and names")
chkWire  := g.AddCheckBox("vchkWire", "Wireframe")
chkPause := g.AddCheckBox("vchkPause", "Pause")
g.AddButton("x+8 Subtle Icon=E893", "Step").OnClick((*) => eng.Step())
g.AddText("", "Time")
speed := g.AddSegmented("vspeed x+8 Choose3", "0.25:¼×|0.5:½×|1:1×|2:2×")
g.AddText("", "Gravity")
grav := g.AddSlider("vgrav x+8 w150 Min=4 Max=60", 24)
g.AddSeparator()
g.AddText("Caption", "Everything in the world, from the engine")
ents := g.AddListView("vents h190 NoSortHdr -Multi", ["Id", "Tag", "X", "Z"])
ents.ModifyCol(1, 90), ents.ModifyCol(2, 60), ents.ModifyCol(3, 50), ents.ModifyCol(4, 50)
g.Use()

chkStats.OnChange((c, v, *) => eng.Debug({Stats: v}))
chkCol.OnChange((c, v, *) => (eng.Debug({Colliders: v}), eng.List(true)))
chkWire.OnChange((c, v, *) => eng.Debug({Wire: v}))
chkPause.OnChange((c, v, *) => SetPaused(v))
speed.OnChange((c, v, *) => eng.TimeScale(v))
grav.OnChange((c, v, *) => eng.World({Gravity: v}))

g.Show()
eng := gameCtl.Component
eng.List(true)                                 ; the entity list in every few ticks

; ---------------------------------------------------------------- the state
Score := 0, Lives := 3, Level := 1, Over := false, Invulnerable := 0
RockClock := 0, HeartClock := 0, Boost := false, Ticks := 0, NextId := 0
GemColours := ["#44e0ff", "#ff5fd2", "#7dff6b", "#ffd84a", "#b08cff"]

NewGame() {
    global Score := 0, Lives := 3, Level := 1, Over := false, Invulnerable := 0, RockClock := 0, HeartClock := 0
    eng.Clear()
    eng.World({Gravity: grav.Value, Sky: ["#101830", "#6f86bd"], Fog: [16, 52], Ambient: 0.42, Bounds: 22,
               Light: [-0.5, 0.85, 0.3], Ground: {Tile: 4, Colors: ["#33603e", "#3b6b46"], Radius: 10}})
    eng.Spawn("ship", {Mesh: "ship", Color: "#ffb900", Y: 0.7, Scale: 1.25, Solid: true, Gravity: 1,
                       Control: {Speed: 12, Accel: 7, Jump: 10}, Bounds: "clamp", Tag: "player",
                       Hits: ["gem", "rock", "heart"], Watch: true})
    eng.Camera({Follow: "ship", Dist: 14, Height: 10, Fov: 58})
    Scenery()
    loop 5
        AddGem()
    eng.Hud("score", {X: 18, Y: 14, Size: 22})
    eng.Hud("lives", {X: 18, Y: 44, Size: 18, Color: "#ff6b7d"})
    eng.Hud("level", {X: "50%", Y: 14, Size: 18, Align: "center", Color: "#cfe3ff"})
    eng.Hud("help", {X: 18, Y: -34, Size: 13, Bold: false, Color: "#dfe8ff",
                     Text: "WASD / arrows  fly      Space  hop      Shift  boost      P  pause"})
    eng.Hud("big", {X: "50%", Y: "38%", Size: 40, Align: "center", Text: "", Color: "#ffffff"})
    ShowHud()
    Say("Go!  Pick up the gems, dodge the rocks.")
}

; a ring of low-poly trees and stones round the edge of the field
Scenery() {
    loop 22 {
        a := A_Index / 22 * 6.2832, r := 25 + Mod(A_Index * 7, 5)
        x := Round(r * Cos(a), 2), z := Round(r * Sin(a), 2), k := 0.8 + Mod(A_Index * 13, 7) / 10
        if Mod(A_Index, 3) {
            eng.Spawn("trunk" A_Index, {Mesh: "prism", Color: "#6b4a2f", X: x, Z: z, Y: 0.9 * k, SX: 0.45 * k, SY: 1.8 * k, SZ: 0.45 * k})
            eng.Spawn("crown" A_Index, {Mesh: "pyramid", Color: Mod(A_Index, 2) ? "#2f8f4e" : "#3a9e5a", X: x, Z: z, Y: 2.9 * k,
                                        SX: 2.4 * k, SY: 2.8 * k, SZ: 2.4 * k, RY: A_Index * 17})
        } else
            eng.Spawn("stone" A_Index, {Mesh: "ico", Color: "#7d7a86", X: x, Z: z, Y: 0.6 * k, Scale: 1.6 * k, RY: A_Index * 29})
    }
}

AddGem() {
    global NextId
    id := "gem" (++NextId)
    eng.Spawn(id, {Mesh: "octa", Color: GemColours[Mod(NextId, 5) + 1], X: Random(-19, 19), Z: Random(-19, 19), Y: 1.3,
                   Scale: 1.3, Spin: [0, 140, 0], Bob: {Amp: 0.35, Speed: 3}, Tag: "gem", Glow: true, Radius: 0.9})
}
AddRock() {
    global NextId
    side := Random(0, 3), p := Random(-20, 20), k := Random(14, 24) / 10
    x := side = 0 ? -21 : side = 1 ? 21 : p
    z := side = 2 ? -21 : side = 3 ? 21 : p
    eng.Spawn("rock" (++NextId), {Mesh: "ico", Color: ["#8d7d6c", "#7a6f66", "#96846e"][Random(1, 3)], X: x, Z: z, Y: k * 0.6,
                                  Scale: k, Solid: true, Gravity: 1, Roll: true, Tag: "rock", Bounds: "kill", Life: 24,
                                  Chase: {Target: "ship", Speed: 2.6 + Level * 0.9, Turn: 0.7}})
}
AddHeart() {
    global NextId
    eng.Spawn("heart" (++NextId), {Mesh: "cube", Color: "#ff4d6d", X: Random(-18, 18), Z: Random(-18, 18), Y: 1.2, Scale: 0.9,
                                   RZ: 45, Spin: [0, 90, 0], Bob: {Amp: 0.25, Speed: 4}, Tag: "heart", Glow: true, Life: 12})
}

; ----------------------------------------------------------------- the rules
eng.OnHit(Hit)
Hit(eng, a, b, tag) {
    global Score, Lives, Level, Invulnerable, Over
    if Over
        return
    ship := eng.Entity("ship")
    switch tag {
    case "gem":
        gem := eng.Entity(b)
        eng.Burst({X: gem ? gem.X : ship.X, Y: 1.2, Z: gem ? gem.Z : ship.Z, N: 18, Color: gem ? gem.Get("color", "#fff") : "#fff", Speed: 7, Mesh: "octa", Size: 0.3})
        eng.Kill(b)
        AddGem()
        Score += 10 * Level
        g.PlaySound("assets\ding.mp3", 45)
        if (Score >= Level * 120)
            LevelUp()
    case "heart":
        eng.Burst({X: ship.X, Y: 1, Z: ship.Z, N: 14, Color: "#ff4d6d", Speed: 5})
        eng.Kill(b)
        Lives := Min(Lives + 1, 5)
        Say("An extra life")
    case "rock":
        if (eng.LastTick.Time < Invulnerable)
            return
        Lives -= 1
        eng.Shake(0.9)
        eng.Burst({X: ship.X, Y: 1, Z: ship.Z, N: 26, Color: "#ff7043", Speed: 9})
        eng.Kill(b)
        if (Lives <= 0)
            return GameOver()
        Invulnerable := eng.LastTick.Time + 2
        eng.Set("ship", {Flash: true})
        Say("Ouch! " Lives " " (Lives = 1 ? "life" : "lives") " left")
    }
    ShowHud()
}
LevelUp() {
    global Level
    Level += 1
    eng.Hud("big", {Text: "Level " Level, Color: "#ffe066"})
    SetTimer(() => eng.Hud("big", {Text: ""}), -1600)
    ; the sky darkens a little each level
    eng.World({Sky: [Format("#{:02x}{:02x}{:02x}", Min(16 + Level * 6, 70), 22, Max(24, 48 - Level * 3)), "#6f86bd"]})
    Say("Level " Level ": the rocks are quicker")
}
GameOver() {
    global Over := true
    eng.Set("ship", {Hidden: true, Frozen: true, Flash: false})
    eng.Burst({X: eng.Entity("ship").X, Y: 1, Z: eng.Entity("ship").Z, N: 40, Color: "#ffb900", Speed: 11, Life: 1.4})
    eng.Hud("big", {Text: "Game over`nScore " Score "`n`nPress Enter to play again", Color: "#ffffff"})
    Say("Game over. Enter plays again.")
    ShowHud()
}

eng.OnTick(Tick)
Tick(eng, t) {
    global RockClock, HeartClock, Invulnerable, Boost, Ticks
    Ticks += 1
    if (Over && t.Pressed.Has("enter"))
        return NewGame()
    if t.Pressed.Has("p")
        chkPause.Value := !chkPause.Value, SetPaused(chkPause.Value)
    if !Over && !eng.Paused {
        ; rocks come faster with each level; a heart now and then
        RockClock += t.Dt, HeartClock += t.Dt
        if (RockClock > Max(0.6, 2.6 - Level * 0.3)) {
            RockClock := 0
            AddRock()
        }
        if (HeartClock > 14) {
            HeartClock := 0
            AddHeart()
        }
        if (Invulnerable && t.Time > Invulnerable) {
            Invulnerable := 0
            eng.Set("ship", {Flash: false})
        }
        ; Shift: the rules change how the ship flies, the page flies it
        want := t.Keys.Has("shift")
        if (want != Boost) {
            Boost := want
            eng.Set("ship", {Control: {Speed: Boost ? 20 : 12, Accel: Boost ? 10 : 7, Jump: 10}})
        }
    }
    if !Mod(Ticks, 12)                         ; the panel: 2.5 times a second is plenty to read
        ShowPanel(t)
}

ShowHud() {
    hearts := ""
    loop Lives
        hearts .= "♥ "
    eng.Hud("score", {Text: "Score " Score})
    eng.Hud("lives", {Text: Trim(hearts)})
    eng.Hud("level", {Text: "Level " Level})
}
; Whatever the script does to the page is done on the page's own thread, so
; the frame after it waits. Texts are cheap; redrawing a list of 45 rows is
; ~13 ms of work and layout -- a dropped frame -- so the list follows the
; world once a second while you play, and at every chance while paused.
ListAt := 0, ListShown := ""
ShowPanel(t) {
    global ListAt, ListShown
    s := t.Stats
    SetText(statFps,  s.Get("fps", 0) " frames a second, " Round(s.Get("ms", 0), 1) " ms of work each")
    SetText(statTris, s.Get("tris", 0) " polygons, " s.Get("ents", 0) " things")
    SetText(statAhk,  "AHK: " s.Get("tickHz", 0) " ticks a second, " Round(s.Get("rtt", 0), 1) " ms there and back, rules " Round(s.Get("logic", 0), 1) " ms")
    ship := eng.Entity("ship")
    if IsObject(ship)
        SetText(statShip, Format("Ship at {:.1f}, {:.1f}  going {:.1f}", ship.X, ship.Z, Sqrt(ship.VX ** 2 + ship.VZ ** 2)))
    g.Status("fps", s.Get("fps", 0) " fps")
    if IsObject(t.List) && (t.List != ListShown) && (eng.Paused || A_TickCount - ListAt > 1000) {
        ListAt := A_TickCount, ListShown := t.List
        try ents.Opt("-Redraw")
        ents.Delete()
        for row in t.List
            ents.Add(, row[1], row[2], Round(row[3], 1), Round(row[5], 1))
        try ents.Opt("+Redraw")
    }
}
SetText(ctl, text) {
    static last := Map()
    if (last.Get(ctl.Id, "") !== text)         ; the same text again would still lay the page out
        last[ctl.Id] := text, ctl.Text := text
}
SetPaused(on) {
    eng.Pause(on)
    eng.Hud("big", {Text: on ? "Paused" : Over ? "Game over`nScore " Score "`n`nPress Enter to play again" : ""})
    Say(on ? "Paused: Step moves one frame at a time" : "Go!")
}
Say(text) => g.Status("msg", text)

NewGame()
eng.Focus()
