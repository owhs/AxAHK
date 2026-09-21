#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\AxGui.ahk
; single-file exe: the layer's own dialog chrome (harmless uncompiled)
;@Ahk2Exe-AddResource %U_AxLib%\AxRich.css, AX_AXRICH_CSS

; =============================================================================
;  AxRich.ahk — the rich-component layer. This file is the layer only; it
;  pulls in no components. Include the ones you want, or AxRichAll.ahk for
;  every component that ships with the library.
;
;      #Include lib\AxRich.ahk
;      #Include lib\components\ColorPicker\AxColorPicker.ahk
;
;  ---------------------------------------------------------------- what one is
;  A rich component is bigger than a control and smaller than an app. Each one
;  lives in its own folder under lib\components and behaves like a plugin: drop the
;  folder in, include its .ahk, and it wires itself up. Nothing in the core
;  knows it exists, and a window that never uses it carries none of its CSS.
;
;      lib\components\<Name>\Ax<Name>.ahk   the component (it registers itself)
;      lib\components\<Name>\Ax<Name>.css   its own styles, under the theme
;
;  A component ships as a pack of parts, so the same thing can be reached at
;  whatever level suits the caller:
;
;    1. the component     Html(id, opts) markup that drops into any page, and
;                         a class that binds behaviour to it
;    2. the config layer   one options object shared by every entry point
;    3. the front ends     a standalone modal window (AxRichDialog), an AxGui
;                          Add* method, an AxWindow method, and any shortcut
;                          that suits it (the colour picker adds a swatch
;                          button that opens the dialog and updates itself)
;
;  ------------------------------------------------------------ writing one
;      class AxThing {
;          static _reg := AxRich.Register("Thing", "components\Thing\AxThing.css",
;              (*) => AxRich.AddMethod("AddThing", (c, o := "", t := "") => ...))
;          static Html(id, opts) { ... }
;      }
;
;  Compiling: a component embeds its own stylesheet, so including its .ahk
;  is all that is needed for a single-file exe as well. Each one carries
;
;      ;@Ahk2Exe-AddResource %U_AxLib%\components\<Name>\Ax<Name>.css, AX_COMPONENTS_<NAME>_AX<NAME>_CSS
;
;  next to its class (the name is AxSys.ResName of the path relative to lib),
;  and AxWindow.ReadLib looks in the exe's resources before the lib folder.
;
;  Register(name, css, install, core) records the component, remembers where
;  its stylesheet lives, and runs `install` once at load so the component can add
;  its Add* methods to AxGui and its own methods to AxWindow. Call
;  AxRich.Use(win, "Thing") before your markup goes into a window: it injects
;  that component's stylesheet under its own <style> id, once per window.
; =============================================================================
class AxRich {
    static Components := Map()          ; name -> {Name, Css, Text}
    static _used := Map()               ; hwnd -> Map(name -> true)
    static _bound := Map()              ; hwnd -> Map(element id -> component)
    static _installed := AxRich._Setup()      ; name must differ from the method:
                                              ; AHK property names are case-insensitive
    static _Setup() {
        ; ctl.Component reaches the rich object behind an AxGui control, so
        ; g.AddColorButton("vAccent").Component.OnChange(...) works.
        AxGui.Control.Prototype.DefineProp("Component", {Get: (self) => AxRich.At(self.G, self.Id)})
        ; and any method the component itself defines is reachable straight off
        ; the control, so a component can grow methods (OnPreview, Recent, ...)
        ; without AxGui.Control having to know about them. A component that
        ; returns itself for chaining hands back the control instead, so the
        ; chain stays in control-land.
        AxGui.Control.Prototype.DefineProp("__Call", {Call: (self, name, args) => AxRich._Fwd(self, name, args)})
        AxRich.Register("AxRich", "AxRich.css")      ; the dialog chrome itself
        return true
    }

    ; Register(name, cssRelativeToLib, installFn, core := false) -> the record.
    ; Called from a component's static initialiser, so including the file is
    ; all it takes to install it.
    ;
    ; core:=true means the pack holds everyday controls, so its stylesheet is
    ; part of every page rather than something to inject when the component is
    ; first used. Either way the sheet lands in the layer under the theme.
    static Register(name, css := "", install := "", core := false) {
        rec := {Name: name, Css: css, Text: "", Core: core}
        AxRich.Components[name] := rec
        if install
            try install()
        return rec
    }
    static Has(name) => AxRich.Components.Has(name)
    ; The stylesheets of every core pack that is included, run together. AxGui
    ; puts this in the page ahead of the theme: these are the controls any page
    ; may use, and their shape has to be there in the first paint.
    static CoreCss() {
        out := ""
        for n, rec in AxRich.Components
            if (rec.Core && (t := AxRich.CssText(n)) != "")
                out .= (out = "" ? "" : "`n") t
        return out
    }
    static Names() {
        out := []
        for n in AxRich.Components
            out.Push(n)
        return out
    }
    ; Use(win, "Thing"): make sure that component's stylesheet is in the
    ; window. Each component gets its own <style id="axExtra_axrich_Thing">,
    ; so components stay independent and can be added at any time.
    ; ------------------------------------------------------------ scripts
    ; UseJs(win, rel): a component's own JavaScript, run once in that window.
    ; `rel` is relative to lib, like a stylesheet, and is read the same way --
    ; from the exe's resources when compiled -- so a component that carries
    ;
    ;   ;@Ahk2Exe-AddResource %U_AxLib%\components\<Name>\Ax<Name>.js, AX_COMPONENTS_<NAME>_AX<NAME>_JS
    ;
    ; is a single-file exe with its script inside. Returns true when it ran.
    static UseJs(win, rel) {
        key := "js:" rel
        hwnd := AxRich.Owner(win)
        if hwnd {
            if !AxRich._used.Has(hwnd)
                AxRich._used[hwnd] := Map()
            if AxRich._used[hwnd].Has(key)
                return true
        }
        code := AxWindow.ReadLib(rel)
        if (code = "")
            return false
        if !AxRich.RunJs(win, code)
            return false
        if hwnd
            AxRich._used[hwnd][key] := true
        return true
    }
    ; UseJsFile(win, path): your own script beside the program (a path, not
    ; lib-relative): read from the exe when compiled with
    ;   ;@Ahk2Exe-AddResource my.js, <AxSys.ResName("my.js")>
    ; and from the file otherwise. Run once per window.
    static UseJsFile(win, path) {
        key := "file:" path
        hwnd := AxRich.Owner(win)
        if (hwnd && AxRich._used.Has(hwnd) && AxRich._used[hwnd].Has(key))
            return true
        code := ""
        SplitPath(path, &name)
        if A_IsCompiled
            code := AxSys.ResourceText(AxSys.ResName(name))
        if (code = "")
            try code := FileRead(path, "UTF-8")
        if (code = "" || !AxRich.RunJs(win, code))
            return false
        if hwnd {
            if !AxRich._used.Has(hwnd)
                AxRich._used[hwnd] := Map()
            AxRich._used[hwnd][key] := true
        }
        return true
    }
    ; RunJs(win, code): run a script in the page, now
    static RunJs(win, code) {
        try {
            d := win.Doc
            s := d.createElement("script")
            s.text := code
            head := d.getElementsByTagName("head").item(0)
            head.appendChild(s)
            head.removeChild(s)
            return true
        }
        return false
    }
    static Use(win, name) {
        if (!AxRich.Components.Has(name) || !IsObject(win))
            return win
        rec := AxRich.Components[name]
        if (rec.Css = "")
            return win
        try hwnd := win.Gui.Hwnd
        catch
            hwnd := 0
        if hwnd {
            if !AxRich._used.Has(hwnd)
                AxRich._used[hwnd] := Map()
            if AxRich._used[hwnd].Has(name)
                return win
            AxRich._used[hwnd][name] := true
        }
        if (rec.Text = "")
            rec.Text := AxWindow.ReadLib(rec.Css)
        ; under the theme, not over it, so a sheet can restyle the component
        try win.SetBaseCss("axrich_" name, rec.Text)
        return win
    }
    ; The stylesheet text of a component (read once, then cached). Useful when
    ; a window is being built: pass it as the AxGui Css option and the styles
    ; are in the first paint instead of arriving a moment later.
    static CssText(name) {
        if !AxRich.Components.Has(name)
            return ""
        rec := AxRich.Components[name]
        if (rec.Text = "" && rec.Css != "")
            rec.Text := AxWindow.ReadLib(rec.Css)
        return rec.Text
    }
    ; Bind(win, id, obj) / At(win, id): the live component behind an element.
    static Bind(win, id, obj) {
        h := AxRich.Owner(win)
        if !AxRich._bound.Has(h)
            AxRich._bound[h] := Map()
        AxRich._bound[h][id] := obj
        return obj
    }
    ; ctl.Whatever(...) -> the bound component's Whatever(...).
    ; Most components are only built once the window is ready, so a call made
    ; while the page is still being laid out is queued rather than refused --
    ; that is what lets g.AddColorButton(...).OnPreview(...) read naturally.
    static _Fwd(ctl, name, args) {
        c := AxRich.At(ctl.G, ctl.Id)
        if !IsObject(c) {
            ; Ready is NOT "every component exists": a component is built in
            ; an OnReady handler, and Ready is already true while that queue
            ; is still draining. A timer set in the startup code can fire in
            ; that gap and ask a chart to take a new point before the chart
            ; has been made -- which threw "Unknown method: Push" at a chart
            ; that has had Push all along, once, a second into the program.
            ;
            ; Not ready yet: queue it, as before. Ready but not built yet:
            ; try again at the end of this message, by which time the queue
            ; has drained. Still missing then, and it really is missing.
            if !ctl.G.Ready {
                ctl.G.OnReady((w) => AxRich._Later(ctl, name, args))
                return ctl
            }
            SetTimer(AxRich._SoonFn(ctl, name, args), -1)
            return ctl
        }
        if !c.HasMethod(name)
            throw MethodError("Unknown method: " name, -1)
        r := c.%name%(args*)
        return (r == c) ? ctl : r
    }
    static _SoonFn(ctl, name, args) => (*) => AxRich._Soon(ctl, name, args)
    ; The second and last attempt. Whatever the answer is now, it is the
    ; truth: a component that is still not there is one that never will be.
    static _Soon(ctl, name, args) {
        c := AxRich.At(ctl.G, ctl.Id)
        if !IsObject(c)
            throw MethodError("Unknown method: " name " -- " ctl.Id
                . " has no rich component behind it", -1)
        if !c.HasMethod(name)
            throw MethodError("Unknown method: " name, -1)
        c.%name%(args*)
    }
    static _Later(ctl, name, args) {
        c := AxRich.At(ctl.G, ctl.Id)
        if (IsObject(c) && c.HasMethod(name))
            c.%name%(args*)
    }
    static At(win, id) {
        h := AxRich.Owner(win)
        return (AxRich._bound.Has(h) && AxRich._bound[h].Has(id)) ? AxRich._bound[h][id] : ""
    }
    ; Add an Add* method to every AxGui container (that is where Add* lives;
    ; AxGui forwards unknown Add* calls to the current container).
    static AddMethod(name, fn) {
        AxGui.Container.Prototype.DefineProp(name, {Call: fn})
    }
    ; Add a method to AxWindow (and so to AxGui), e.g. win.PickColor().
    static WindowMethod(name, fn) {
        AxWindow.Prototype.DefineProp(name, {Call: fn})
    }
    ; Activate, and mean it. WinActivate alone is refused when the calling
    ; thread does not own the foreground window -- Windows' foreground lock --
    ; and the dialog then opens behind whatever was in front. Borrowing the
    ; foreground thread's input queue lifts the restriction for the one call.
    static Focus(hwnd) {
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return false
        try WinActivate("ahk_id " hwnd)
        if WinActive("ahk_id " hwnd)
            return true
        try {
            fg := DllCall("GetForegroundWindow", "Ptr")
            if (fg = hwnd)
                return true
            them := DllCall("GetWindowThreadProcessId", "Ptr", fg, "Ptr", 0, "UInt")
            us   := DllCall("GetCurrentThreadId", "UInt")
            if (them && them != us) {
                DllCall("AttachThreadInput", "UInt", them, "UInt", us, "Int", true)
                DllCall("SetForegroundWindow", "Ptr", hwnd)
                DllCall("AttachThreadInput", "UInt", them, "UInt", us, "Int", false)
            } else
                DllCall("SetForegroundWindow", "Ptr", hwnd)
        }
        return WinActive("ahk_id " hwnd) ? true : false
    }

    ; Owner(x) -> an hwnd, from an AxWindow / AxGui, a Gui, or a raw hwnd.
    static Owner(x) {
        if !x
            return 0
        if IsObject(x) {
            try return x.Gui.Hwnd
            try return x.Hwnd
            return 0
        }
        return Integer(x)
    }
}

; =============================================================================
;  AxRichDialog — the standalone-window half of a rich component.
;
;  It owns an AxGui window with dialog manners: no minimise or maximise box,
;  a fixed size, Escape closes, closing it never exits the script, and it is
;  modal to its owner while it is up (and inherits the owner's theme, accent
;  and stylesheet unless told otherwise). A subclass fills in _Content(g) and
;  calls Done(result) to finish.
; =============================================================================
class AxRichDialog {
    ; opts handled here (a subclass adds its own):
    ;   Title, Icon, Owner, Theme, Accent, Tint, Stylesheet, BackColor, Css,
    ;   Width, Height, Resizable, MinimizeBox, MaximizeBox, Modal, Center,
    ;   X, Y, EscapeCloses, Fit ("both" | "height" | false: size the window to
    ;   its content once the page has loaded; a Width or Height given wins)
    __New(opts := "") {
        this.Opts := IsObject(opts) ? opts : {}
        this.Result := ""
        this.G := ""
        this._done := false
        this._modal := false, this._released := false
        this._ownerHwnd := AxRich.Owner(this.O("Owner", 0))
    }
    O(name, def := "") => this.Opts.HasOwnProp(name) ? this.Opts.%name% : def

    ; Build the window. `defaults` supplies the subclass's fall-backs; the
    ; caller's opts always win.
    _Build(defaults := "") {
        d := (n, v := "") => (IsObject(defaults) && defaults.HasOwnProp(n)) ? defaults.%n% : v
        o := {}
        o.Title        := this.O("Title", d("Title", "Dialog"))
        o.Width        := this.O("Width", d("Width", 460))
        o.Height       := this.O("Height", d("Height", 520))
        o.MinWidth     := o.Width
        o.MinHeight    := o.Height
        o.Resizable    := this.O("Resizable", d("Resizable", false))
        o.MinimizeBox  := this.O("MinimizeBox", d("MinimizeBox", false))
        o.MaximizeBox  := this.O("MaximizeBox", d("MaximizeBox", false))
        o.EscapeCloses := this.O("EscapeCloses", true)
        o.ExitOnClose  := false
        o.Icon         := this.O("Icon", d("Icon", ""))
        o.Nav          := false
        o.Shell        := false             ; it is sized to its content (_FitContent)
        for k in ["Theme", "Accent", "Tint", "TintStrength", "Stylesheet", "BackColor",
                  "AppName", "FocusRing", "RoundCorners", "BorderColor", "Css"]
            if this.Opts.HasOwnProp(k)
                o.%k% := this.Opts.%k%
        ; inherit the owner's look when the caller did not say
        if (this._ownerHwnd && AxWindow._byHwnd.Has(this._ownerHwnd)) {
            ow := AxWindow._byHwnd[this._ownerHwnd]
            for k in ["Theme", "Accent", "BackColor", "Stylesheet", "Tint", "TintStrength"]
                if (!o.HasOwnProp(k) && ow.HasOwnProp(k) && ow.%k% != "")
                    o.%k% := ow.%k%
        }
        o.Css := AxRich.CssText("AxRich") (this.Opts.HasOwnProp("Css") ? this.Opts.Css : "")
        g := this.G := AxGui(o)
        ; closed by its own x, Escape or Alt+F4: hand the owner back before the
        ; window goes, exactly as a button does (see _Release)
        g.OnClose((*) => this._Release())
        this._hasFooter := false
        this._Content(g)
        return g
    }
    ; A full-width bar pinned to the bottom of the dialog.
    ; _Footer(g, ["Cancel", "OK"], fn) calls fn(index, isDefault) on a click;
    ; the last button is the accent (default) one.
    _Footer(g, labels, onClick) {
        if (!IsObject(labels) || !labels.Length)
            return 0
        h := ""
        for i, b in labels
            h .= '<span class="btn' (i = labels.Length ? " accent" : "") '" id="axrichBtn' i '"'
              .  ' tabindex="0">' AxWindow._Esc(b) '</span>'
        g.AddHtml("vaxrichFooter Class=axrich-footer", h)
        for i, b in labels
            g.On("click", "axrichBtn" i, this._FooterFn(onClick, i, labels.Length))
        this._hasFooter := true
        return AxRichDialog.FooterHeight
    }
    _FooterFn(fn, i, last) => (*) => fn(i, i = last)
    static FooterHeight := 65        ; 14 + 36 + 14 + border, as .axrich-footer draws it
    _Content(g) {                                    ; subclasses build the page
    }
    ; Size the window to what its page holds, measured in the loaded page
    ; rather than guessed: the widest line at its natural width, and the whole
    ; flow's height at that width, each with the page's own padding. A guess
    ; could not follow a stylesheet's spacing, a font, or a mode that shows
    ; more -- two months and a column of presets, a row of times.
    ;   how: "both" (width and height) or "height". A Width or Height the
    ;   caller gave is kept as given.
    _FitContent(g, how := "both") {
        fitW := (how = "both") && !this.Opts.HasOwnProp("Width")
        fitH := !this.Opts.HasOwnProp("Height")
        if !(fitW || fitH)
            return
        Px(v) => RegExMatch(String(v), "-?[\d.]+", &m) ? Number(m[0]) : 0
        try {
            doc := g.Doc, de := doc.documentElement, c := doc.getElementById("content")
            if !IsObject(c)
                return
            cs := c.currentStyle
            side := Px(cs.paddingLeft) + Px(cs.paddingRight) + Px(cs.borderLeftWidth) + Px(cs.borderRightWidth)
            chromeW := de.clientWidth - c.offsetWidth       ; what sits beside #content
            chromeH := de.clientHeight - c.offsetHeight     ; and above it: the title bar
            w := g.Width, h := g.Height
            if fitW {
                ; room to spare, so nothing wraps or shrinks while it is measured
                c.style.width := "4000px"
                natural := 0
                lines := c.querySelectorAll(".ax-line")
                loop lines.length {
                    ln := lines.item(A_Index - 1)
                    if IsObject(ln.querySelector("#axrichFooter"))  ; pinned, full-bleed: not content
                        continue
                    left := ln.getBoundingClientRect().left, kids := ln.children
                    loop kids.length
                        natural := Max(natural, kids.item(A_Index - 1).getBoundingClientRect().right - left)
                }
                ; never narrower than the footer's two buttons want
                w := Max(340, chromeW + Ceil(natural) + 2 + side)
                c.style.width := (w - chromeW) "px"
            }
            if fitH {
                c.style.height := "auto", c.style.overflowY := "visible"
                h := chromeH + c.offsetHeight
            }
            c.style.width := "", c.style.height := "", c.style.overflowY := ""
            ; and never past the screen it opens on
            k := A_ScreenDPI / 96
            MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
            w := Min(Round(w), Floor((r - l) / k) - 40), h := Min(Round(h), Floor((b - t) / k) - 40)
            if fitW
                g.Width := w, g.MinWidth := w
            if fitH
                g.Height := h, g.MinHeight := h
        }
    }
    _Ready(g) {                                      ; subclasses wire the DOM
    }
    ; Centre on the owner window, else on the monitor holding the cursor.
    _Center() {
        g := this.G, k := A_ScreenDPI / 96
        pw := Round(g.Width * k), ph := Round(g.Height * k)
        x := "", y := ""
        if (this._ownerHwnd && WinExist("ahk_id " this._ownerHwnd)) {
            try {
                WinGetPos(&ox, &oy, &ow, &oh, "ahk_id " this._ownerHwnd)
                x := ox + (ow - pw) // 2, y := oy + (oh - ph) // 2
            }
        }
        if (x = "") {
            MouseGetPos(&mx, &my)
            mon := MonitorGetPrimary()
            loop MonitorGetCount()
                if (MonitorGet(A_Index, &l, &t, &r, &b) && mx >= l && mx < r && my >= t && my < b)
                    mon := A_Index
            MonitorGetWorkArea(mon, &l, &t, &r, &b)
            x := l + (r - l - pw) // 2, y := t + (b - t - ph) // 2
        }
        g.X := this.O("X", x), g.Y := this.O("Y", y)
    }
    ; Show it and block until it closes; returns this.Result.
    ShowModal() {
        g := IsObject(this.G) ? this.G : this._Build()
        g.Show(false)                                ; build and load, still hidden
        ; Owned by the window it came from, which is a different thing from
        ; being modal. Disabling the opener stops it being used; ownership is
        ; what keeps the dialog IN FRONT of it, off the taskbar, and minimising
        ; and restoring with it. Set while still hidden -- Windows only applies
        ; an owner cleanly before the window is first shown.
        if this._ownerHwnd
            try g.Gui.Opt("+Owner" this._ownerHwnd)
        g.BodyClass("axrich-dlg", true)
        g.BodyClass("has-footer", this._hasFooter)
        this._Ready(g)
        ; Fit: "both" | "height" | false -- a subclass sets its own default
        fit := this.O("Fit", this.HasOwnProp("FitDefault") ? this.FitDefault : false)
        if fit
            this._FitContent(g, fit = "height" ? "height" : "both")
        if this.O("Center", true)
            this._Center()
        this._modal := this.O("Modal", true) && this._ownerHwnd
        if this._modal
            try WinSetEnabled(false, "ahk_id " this._ownerHwnd)
        g.Show()
        AxRich.Focus(g.Gui.Hwnd)
        while (!this._done && !g.Closing)
            Sleep(10)
        this._Release()
        try g.Close()
        return this.Result
    }
    ; Give the owner back, once, however the dialog ends. The order is the
    ; whole point: a dialog destroyed while its owner is still disabled hands
    ; the activation to whatever window Windows finds next -- often another
    ; program, which comes to the front over the owner until the owner is
    ; activated again: the host flickered away and back on every close. And
    ; activating the owner while the dialog still shows repaints the dialog
    ; as inactive for a frame. So: enable the owner, then hide the dialog --
    ; Windows activates the owner itself when an active owned window hides --
    ; and only then is it destroyed.
    _Release() {
        this._done := true
        if this._released
            return
        this._released := true
        if this._modal
            try WinSetEnabled(true, "ahk_id " this._ownerHwnd)
        try this.G.Gui.Hide()
        if (this._ownerHwnd && !WinActive("ahk_id " this._ownerHwnd))
            AxRich.Focus(this._ownerHwnd)
    }
    ; Finish with a result ("" means cancelled).
    Done(result := "") {
        this.Result := result
        this._done := true
        return this
    }
}
