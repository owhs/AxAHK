#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes/icons (single-file exe)
#Include ..\lib\AxGui.ahk
#Include ..\lib\AxAssets.ahk

; ==============================================================================
;  Embed.ahk — Advanced AxGui Integration
; ==============================================================================
;  Native ActiveX controls docked inside the page. AddActiveX() drops a
;  placeholder into the layout and the library keeps a real child control
;  glued to it (resize, page switch, scroll, dialogs).
;
;    Web        Second Shell.Explorer.2 with an AHK-built toolbar around it
;    Video      VLC ActiveX plugin (falls back to Windows Media Player) with
;               custom transport controls
;    Documents  Shell.Explorer.2 again, showing any local document or folder
;
;  No HTML, CSS or JS is written anywhere in this file.
; ==============================================================================


; ------------------------------------------------------------------------------
;  Gui Setup
; ------------------------------------------------------------------------------

g := AxGui({
    Title:     "Embed",
    AppName:   "AxGui Embed",
    Width:     980,
    Height:    660,
    MinWidth:  640,
    MinHeight: 420,
    Theme:     "system",
    Accent:    "system"
})


; ==============================================================================
;  WEB PAGE
; ==============================================================================

g.AddPage("web", "Web", "E774")

g.AddButton("vbtnBack Icon", "◀")
    .SetTip("Back")
g.AddButton("vbtnFwd Icon x+4", "▶")
    .SetTip("Forward")
g.AddButton("vbtnReload Icon x+4", "⟳")
    .SetTip("Reload")

url := g.AddEdit(
    'vurl fill x+8 placeholder="Enter an address and press Enter"',
    "https://www.wikipedia.org"
)

g.AddButton("vbtnGo Accent x+8", "Go")

browser := g.AddActiveX("vbrowser Stretch", "Shell.Explorer.2")

g.AddText("vstatus hint", "Ready")


; ==============================================================================
;  VIDEO PAGE
; ==============================================================================

; VLC registers "VideoLAN.VLCPlugin.2" when installed with its ActiveX plugin;
; WMPlayer.OCX exists only where the "Windows Media Player Legacy" feature is on.

engine := AxGui.HasControl("VideoLAN.VLCPlugin.2") ? "vlc"
        : AxGui.HasControl("WMPlayer.OCX")         ? "wmp"
        : ""

g.AddPage("video", "Video", "E714")

if (engine = "") {
    g.AddInfoBar(
        'Kind=warning Title="No media control found." noclose',
        "Install VLC (with its ActiveX plugin) or enable the Windows Media "
        . "Player Legacy feature, then restart this example."
    )
} else {
    g.AddButton("vbtnOpen Accent", "Open file…")

    g.AddText(
        "vmediaName fill x+12 hint",
        "Nothing loaded. Space plays or pauses, F toggles full screen, Escape leaves it."
    )

    g.AddBadge("vengine x+12", engine = "vlc" ? "VLC" : "Windows Media Player")

    player := g.AddActiveX(
        "vplayer Stretch",
        engine = "vlc" ? "VideoLAN.VLCPlugin.2" : "WMPlayer.OCX"
    )

    g.AddButton("vbtnPlay Icon", "▶")
        .SetTip("Play / Pause (Space)")
    g.AddButton("vbtnStop Icon x+4", "■")
        .SetTip("Stop")

    pos := g.AddSlider("vpos fill x+8 Max=1000 novalue", 0)

    g.AddText("vtime w110 right x+8", "0:00 / 0:00")

    g.AddText("x+16", "Volume")
    vol := g.AddSlider("vvol w140 x+8 novalue", 70)

    g.AddSwitch("vmute x+12", "Mute")

    g.AddButton("vbtnFull Icon x+12", "⛶")
        .SetTip("Full screen (F)")
}


; ==============================================================================
;  DOCUMENTS PAGE
; ==============================================================================

g.AddPage("docs", "Documents", "E8A5")

g.AddInfoBar(
    'Title="Anything Windows can show in a browser frame."',
    "PDFs, folders, images, text files: pick one and Trident renders it in place."
)

g.AddButton("vbtnDoc Accent", "Open document…")
g.AddButton("vbtnDownloads x+8", "Downloads folder")

viewer := g.AddActiveX("vviewer Stretch", "Shell.Explorer.2")


; ==============================================================================
;  ABOUT PAGE
; ==============================================================================

g.AddPage("about", "About", "E946")

g.AddCard("", "How this works")
g.AddText("fill",
    "Each dock is a real Win32 child window created with Gui.Add('ActiveX'). "
    . "The library reads the placeholder's rectangle from the DOM sixteen times "
    . "a second and moves the control onto it, clipped to the content viewport, "
    . "hidden while a dialog is open or the page is not the active one."
)
g.AddText("fill Top=8",
    "You get the COM object back (ctl.Object), so the whole automation surface "
    . "of the control is one property away: Navigate, Document, playlist.play(), "
    . "audio.volume…"
)
g.Use()

g.AddCard("Top=12", "Try")
g.AddText("fill",
    "Resize the window, switch pages, collapse the sidebar with Ctrl+B, open a "
    . "dialog: the controls follow."
)
g.AddButton("vbtnDlg Top=8", "Open a dialog over the video")
    .OnClick((*) => (g.ShowPage("video"), g.Confirm("The player hides while I am open, so I stay on top.", "Dialog")))
g.Use()

g.Show()


; ==============================================================================
;  WEB — Navigation & Events
; ==============================================================================

wb := browser.Object
wb.Silent := true                               ; no script-error popups

; COM events pass some args ByRef — unwrap VarRef if needed.
Deref(v) => v is VarRef ? %v% : v

class WebSink {
    static TitleChange(text, *)      => g.Text("status", Deref(text))
    static NavigateComplete2(pDisp, u, *) => url.Value := String(Deref(u))
    static StatusTextChange(text, *) => (Deref(text) != "" ? g.Text("status", Deref(text)) : 0)

    static CommandStateChange(cmd, enable, *) {
        if (cmd = 2) {
            g.Ctl("btnBack").Enabled := Deref(enable)
        } else if (cmd = 1) {
            g.Ctl("btnFwd").Enabled := Deref(enable)
        }
    }
}

ComObjConnect(wb, WebSink)

; Disconnect events early during shutdown to avoid re-entrancy.
g.OnClose((*) => ComObjConnect(wb))
OnExit((*) => ComObjConnect(wb))

Go(*) {
    u := Trim(url.Value)
    if (u = "") {
        return
    }
    if !RegExMatch(u, "i)^(https?|file|ftp|about):") {
        u := (InStr(u, " ") || !InStr(u, "."))
            ? "https://duckduckgo.com/?q=" u
            : "https://" u
    }
    try wb.Navigate(u)
}

g.Ctl("btnGo").OnClick(Go)
url.OnEvent("KeyDown", (c, ev, *) => (ev.keyCode = 13 ? Go() : 0))

g.Ctl("btnBack").OnClick((*) => wb.GoBack())
g.Ctl("btnFwd").OnClick((*) => wb.GoForward())
g.Ctl("btnReload").OnClick((*) => wb.Refresh())

g.ContextMenu("browser", [
    ["Copy address",            (*) => A_Clipboard := wb.LocationURL],
    ["Open in default browser", (*) => Run(wb.LocationURL)]
])

wb.Navigate(url.Value)


; ==============================================================================
;  VIDEO — MediaAdapter + Transport + Shortcuts
; ==============================================================================

; One tiny adapter so the page code does not care which engine it got.
; VLC's input object blocks when nothing is loaded, so every call is guarded
; by Loaded; volume/mute are applied to the app's audio session once it exists.

class MediaAdapter {

    __New(obj, engine) {
        this.o        := obj
        this.vlc      := (engine = "vlc")
        this.wantVol  := 70
        this.wantMute := false
        this.applied  := false

        if this.vlc {
            try obj.Toolbar := false
        } else {
            obj.uiMode              := "none"
            obj.stretchToFit        := true
            obj.settings.autoStart  := true
        }
    }

    ; True only when a media item is actually loaded and its input is valid.
    Loaded => this.vlc
        ? (this.o.playlist.itemCount > 0 && this.o.input.state != 0 && this.o.input.state != 5 && this.o.input.state != 7)
        : IsObject(this.o.currentMedia)

    Load(src) {
        this.applied := false

        if this.vlc {
            this.o.playlist.clear()
            ; "C:\x" is a path, "http://x" or "dvd://" an MRL: a scheme is 2+ letters.
            id := this.o.playlist.add(
                RegExMatch(src, "i)^[a-z][a-z0-9+.-]+:")
                    ? src
                    : "file:///" StrReplace(src, "\", "/")
            )
            this.o.playlist.playItem(id)
        } else {
            this.o.URL := src
        }
    }

    Playing => this.Loaded && (this.vlc
        ? (this.o.playlist.isPlaying ? true : false)
        : (this.o.playState = 3))

    Toggle() => !this.Loaded ? 0
        : this.vlc ? this.o.playlist.togglePause()
        : (this.Playing ? this.o.controls.pause() : this.o.controls.play())

    Stop() => !this.Loaded ? 0
        : this.vlc ? this.o.playlist.stop()
        : this.o.controls.stop()

    Length => !this.Loaded ? 0
        : this.vlc ? Max(0, this.o.input.length / 1000)
        : (IsObject(this.o.currentMedia) ? this.o.currentMedia.duration : 0)

    Time {
        get => !this.Loaded ? 0
            : this.vlc ? this.o.input.time / 1000
            : this.o.controls.currentPosition
        set => !this.Loaded ? 0
            : this.vlc ? (this.o.input.time := Round(value * 1000))
            : (this.o.controls.currentPosition := value)
    }

    Volume {
        set => (this.wantVol := value, this.Loaded ? this._ApplyAudio() : 0)
    }

    Mute {
        set => (this.wantMute := value ? true : false, this.Loaded ? this._ApplyAudio() : 0)
    }

    ; Volume and mute go through the process's Windows audio session
    ; (AxSys.AppVolume) rather than the player: VLC's ActiveX audio.* calls
    ; can deadlock, and the mixer route works the same for every engine.
    _ApplyAudio() {
        this.applied := AxSys.AppVolume(this.wantVol, this.wantMute)
    }

    Fullscreen() {
        if !this.Loaded {
            return
        }
        try {
            if this.vlc {
                this.o.video.toggleFullscreen()
            } else {
                this.o.fullScreen := !this.o.fullScreen
            }
        }
    }

    ; Call from a timer: applies audio once playback actually exists.
    Tick() {
        if (!this.applied && this.Playing) {
            this._ApplyAudio()
        }
    }
}

if (engine != "") {

    pl := MediaAdapter(player.Object, engine)

    LoadMedia(src) {
        if (src = "") {
            return
        }
        SplitPath(src, &name)
        g.Text("mediaName", name)
        try pl.Load(src)
        catch as e {
            g.Toast("Could not load: " e.Message)
        }
    }

    g.Ctl("btnOpen").OnClick((*) => LoadMedia(FileSelect(
        1,,
        "Open media",
        "Media (*.mp4;*.mkv;*.avi;*.wmv;*.mov;*.webm;*.mp3;*.wav;*.m4a;*.flac;*.ogg;*.wma)"
    )))
    g.Ctl("btnPlay").OnClick((*) => pl.Toggle())
    g.Ctl("btnStop").OnClick((*) => pl.Stop())
    g.Ctl("btnFull").OnClick((*) => pl.Fullscreen())

    shownPos := -1                              ; last value the poll wrote, so it never seeks itself

    pos.OnChange((c, v, *) => (pl.Length > 0 && Abs(v - shownPos) > 2
        ? pl.Time := pl.Length * v / 1000
        : 0))
    vol.OnChange((c, v, *) => pl.Volume := v)
    g.Ctl("mute").OnChange((c, v, *) => pl.Mute := v)

    Clock(s) => Format("{}:{:02}", Floor(s / 60), Mod(Round(s), 60))

    PollPlayer() {
        global shownPos
        try {
            pl.Tick()
            g.Text("btnPlay", pl.Playing ? "❚❚" : "▶")

            d := pl.Length
            if (d > 0) {
                p := pl.Time
                g.Text("time", Clock(p) " / " Clock(d))
                v := Round(p * 1000 / d)
                if (v != shownPos) {
                    shownPos := v
                    pos.Value := v
                }
            } else {
                g.Text("time", "0:00 / 0:00")
            }
        }
    }

    SetTimer(PollPlayer, 250)

    EmbedPid := DllCall("GetCurrentProcessId", "UInt")

    ; ----------------------------------------------------------------------
    ;  VLC / YouTube-style shortcuts — also live when VLC/WMP is fullscreen
    ;  (its overlay window owns the foreground, so g.Hwnd is not WinActive).
    ;  Typing guard still applies except for F / Escape.
    ; ----------------------------------------------------------------------

    IsTyping() {
        try {
            el := g.Doc.activeElement
            if !IsObject(el) {
                return false
            }
            tag := el.tagName
            if (tag = "TEXTAREA" || tag = "SELECT") {
                return true
            }
            if (tag = "INPUT") {
                try typ := StrLower(el.getAttribute("type"))
                catch {
                    typ := ""
                }
                if (typ = "" || RegExMatch(typ, "^(text|password|search|number|email|url|tel)$")) {
                    return true
                }
            }
            try if (el.isContentEditable) {
                return true
            }
        }
        return false
    }

    IsFs(*) {
        try {
            if (pl.vlc) {
                return !!pl.o.video.fullscreen
            }
            return !!pl.o.fullScreen
        }
        return false
    }

    OnVideoPageAny(*) {
        if (g.CurrentPage != "video") {
            return false
        }
        if IsFs() {
            return WinActive("ahk_pid " EmbedPid)
        }
        return WinActive("ahk_id " g.Hwnd) || WinActive("ahk_pid " EmbedPid)
    }

    OnVideoPage(*) {
        if !OnVideoPageAny() {
            return false
        }
        return !IsTyping()
    }

    SeekRel(d) {
        if (!pl.Loaded || pl.Length <= 0) {
            return
        }
        t := pl.Time + d
        pl.Time := Max(0, Min(pl.Length, t))
    }

    SeekPct(p) {
        if (!pl.Loaded || pl.Length <= 0) {
            return
        }
        pl.Time := pl.Length * p
    }

    VolRel(d) {
        v := vol.Value + d
        v := Min(Max(v, 0), 100)
        vol.Value := v
        pl.Volume := v
        if (d > 0 && g.Value("mute")) {
            g.Value("mute", 0)
            pl.Mute := 0
        }
    }

    ToggleMute(*) {
        cur := g.Value("mute") ? 1 : 0
        g.Value("mute", !cur)
        pl.Mute := !cur
    }

    ; --- Hotkeys blocked while typing (YouTube / VLC behaviour) -----------

    HotIf(OnVideoPage)

    Hotkey("Space",     (*) => pl.Toggle())
    Hotkey("k",         (*) => pl.Toggle())
    Hotkey("m",         (*) => ToggleMute())
    Hotkey("j",         (*) => SeekRel(-10))
    Hotkey("l",         (*) => SeekRel(10))
    Hotkey("Left",      (*) => SeekRel(-5))
    Hotkey("Right",     (*) => SeekRel(5))
    Hotkey("Up",        (*) => VolRel(5))
    Hotkey("Down",      (*) => VolRel(-5))
    Hotkey("0",         (*) => SeekPct(0))
    Hotkey("1",         (*) => SeekPct(0.10))
    Hotkey("2",         (*) => SeekPct(0.20))
    Hotkey("3",         (*) => SeekPct(0.30))
    Hotkey("4",         (*) => SeekPct(0.40))
    Hotkey("5",         (*) => SeekPct(0.50))
    Hotkey("6",         (*) => SeekPct(0.60))
    Hotkey("7",         (*) => SeekPct(0.70))
    Hotkey("8",         (*) => SeekPct(0.80))
    Hotkey("9",         (*) => SeekPct(0.90))
    Hotkey("Numpad0",   (*) => SeekPct(0))
    Hotkey("Numpad1",   (*) => SeekPct(0.10))
    Hotkey("Numpad2",   (*) => SeekPct(0.20))
    Hotkey("Numpad3",   (*) => SeekPct(0.30))
    Hotkey("Numpad4",   (*) => SeekPct(0.40))
    Hotkey("Numpad5",   (*) => SeekPct(0.50))
    Hotkey("Numpad6",   (*) => SeekPct(0.60))
    Hotkey("Numpad7",   (*) => SeekPct(0.70))
    Hotkey("Numpad8",   (*) => SeekPct(0.80))
    Hotkey("Numpad9",   (*) => SeekPct(0.90))
    Hotkey("Home",      (*) => SeekPct(0))
    Hotkey("End",       (*) => (pl.Length > 0 ? pl.Time := pl.Length : 0))
    Hotkey("-",         (*) => VolRel(-5))
    Hotkey("=",         (*) => VolRel(5))
    Hotkey("NumpadAdd", (*) => VolRel(5))
    Hotkey("NumpadSub", (*) => VolRel(-5))

    ; --- Hotkeys that work even while typing and in fullscreen overlay ----

    HotIf(OnVideoPageAny)

    Hotkey("f",      (*) => pl.Fullscreen())
    Hotkey("Escape", (*) => IsFs() ? pl.Fullscreen() : 0)

    HotIf()
}


; ==============================================================================
;  DOCUMENTS — File / Folder Viewer
; ==============================================================================

docWb := viewer.Object
docWb.Silent := true

g.Ctl("btnDoc").OnClick((*) => (f := FileSelect(
    1,,
    "Open a document",
    "Documents (*.pdf;*.txt;*.htm;*.html;*.png;*.jpg;*.gif;*.svg;*.md)"
)) != "" ? docWb.Navigate(f) : 0)

OpenDownloads(*) {
    try docWb.Navigate(A_MyDocuments "\..\Downloads")
}
g.Ctl("btnDownloads").OnClick(OpenDownloads)

try docWb.Navigate(A_MyDocuments "\..\Downloads")

g.ShowPage("web")
