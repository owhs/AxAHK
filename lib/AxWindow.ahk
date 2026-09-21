#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\AxSys.ahk

; =============================================================================
;  AxWindow.ahk — the core window class (borderless HTML/CSS window for AHK v2).
;  AxGui.ahk builds on it; use AxWindow directly to load your own HTML file.
;
;  A reusable class that hosts a local HTML file inside a Shell.Explorer
;  ActiveX control and drives ALL behaviour from AHK through COM event sinks
;  on the live DOM. The HTML never needs a <script> tag.
;
;  Features
;    • Frameless window with custom title bar (drag, double-click, min/max/
;      close) and 8 invisible resize hotspots — all wired by element id.
;    • Windows 11 Snap Layouts flyout when hovering the maximize button.
;    • Right-click handling: native IE menu suppressed, optional custom
;      HTML context menus (per element) or native AHK Menu objects.
;    • Custom in-page dialogs (Alert / Confirm / Prompt / Dialog) and toasts.
;    • Small DOM helper API (Text, Html, Value, AddClass, ...).
;    • Body classes "maximized" and "inactive" so CSS can restyle the chrome.
;
;  Layers
;    1. Window     frame injected by the library (title bar, caption buttons,
;                  resize hotspots), drag, Snap Layouts, DPI, no-flicker paint
;    2. Bridge     On / OnValue / DOM helpers / dialogs / menus / tooltips
;    3. Components <ax-*> tags (AxTags.ahk) -> markup styled by win11.css
;                  and driven here by data-role
;    4. Page script <script type="text/ahk"> blocks in the HTML, synced to
;                  "<html>.ahk" and included by the host with #Include *i
;
;  Minimal host script
;      #Include lib\AxWindow.ahk
;      #Include *i app.html.ahk
;      AxWindow(A_ScriptDir "\app.html", {Width: 800, Theme: "system"}).Show()
;
;  Pass Frame: false to supply your own chrome (ids: titlebar, btnMin,
;  btnMax, btnClose, rzN..rzSE; renameable through opts.Chrome).
; =============================================================================
class AxWindow {
    static _byHwnd := Map()
    static _hooked := false
    ; lib folder (themes\, ui\, icons\ live next to this file)
    static LibDir := SubStr(A_LineFile, 1, InStr(A_LineFile, "\", , -1))
    ; ReadLib("themes\win11.css"): from the exe's resources when compiled with
    ; AxAssets.ahk included, else from the lib folder
    static ReadLib(rel) {
        if (A_IsCompiled && (t := AxSys.ResourceText(AxSys.ResName(rel))) != "")
            return t
        try return FileRead(AxWindow.LibDir rel, "UTF-8")
        return ""
    }
    ; copy every method/property of a mixin class (instance + static) onto this class
    static Mixin(cls) {
        for name in cls.Prototype.OwnProps()
            if (name != "__Class" && name != "__Init")
                AxWindow.Prototype.DefineProp(name, cls.Prototype.GetOwnPropDesc(name))
        for name in cls.OwnProps()
            if (name != "Prototype" && name != "__Class" && name != "__Init" && name != "__New")
                AxWindow.DefineProp(name, cls.GetOwnPropDesc(name))
    }
    ; ------------------------------------------------------------------ ctor
    __New(htmlFile, opts := "") {
        if !IsObject(opts)
            opts := {}
        o := (n, d) => opts.HasOwnProp(n) ? opts.%n% : d
        this.HtmlFile          := htmlFile
        this.HtmlString        := o("Html", "")                ; load this markup instead of a file
        this._wroteHtml        := false
        this._tagsDone         := false                         ; <ax-*> expanded in the text already
        if !this.HasOwnProp("_splitPages")
            this._splitPages   := false                         ; the hidden pages read after the first paint
        this._pagesLater       := []                            ; ... and what they hold till then
        this.Title             := o("Title", "")                ; "" = use the page's <title>
        this.Width             := o("Width", 800)
        this.Height            := o("Height", 540)
        this.MinWidth          := o("MinWidth", 320)
        this.MinHeight         := o("MinHeight", 200)
        this.BackColor         := o("BackColor", "1b1e27")
        this.EscapeCloses      := o("EscapeCloses", false)
        this.ExitOnClose       := o("ExitOnClose", true)
        this.NativeContextMenu := o("NativeContextMenu", false)   ; keep IE's own right-click menu?
        this.SnapLayouts       := o("SnapLayouts", true)
        this.RoundCorners      := o("RoundCorners", true)
        this.BorderColor       := o("BorderColor", "default")   ; Win11 DWM border when floating: "default", "none", "#rrggbb"
        this.SnapBorder        := o("SnapBorder", "none")       ; ... and when snapped/maximized (edges meet the screen)
        this.TooltipDelay      := o("TooltipDelay", 450)        ; ms before a data-tip tooltip shows
        this.BrowserEmulation  := o("BrowserEmulation", 11001)  ; FEATURE_BROWSER_EMULATION value, or false to skip
        this.GpuRendering      := o("GpuRendering", "")         ; false: pages drawn by the CPU, ~150 ms sooner up (AxSys.GpuRendering); "" leaves it
        this.AutoRestart       := o("AutoRestart", true)        ; relaunch once if Trident ignored the emulation value
        this.Composited        := o("Composited", false)        ; WS_EX_COMPOSITED double-buffering (try if resize still flickers)
        this.Theme             := o("Theme", "")                ; "dark" | "light" | "system" | "" (leave page as-is)
        this.Accent            := o("Accent", "")               ; "#rrggbb" | "system" | "" (theme default)
        this.Tint              := o("Tint", "")                 ; "#rrggbb" surface tint | "accent" | "" (none)
        this.TintStrength      := o("TintStrength", 0.12)       ; 0..1 how much tint is mixed into surfaces
        this.Frame             := o("Frame", true)              ; inject title bar + resize hotspots if the page has none
        ; Icon: "auto" (the window's own icon) | a Segoe Fluent Icons glyph
        ; ("E790") | "shell32.dll,13" / "imageres.dll,-109" / "thing.ico" /
        ; "app.exe" (extracted) | a .png/.jpg/.gif/.svg path or data: URI |
        ; "" or "none" for no icon at all.
        this.Icon              := o("Icon", "auto")
        this.X                 := o("X", "")                    ; window position; "" lets Windows place it
        this.Y                 := o("Y", "")
        this.NoActivate        := o("NoActivate", false)        ; come up without taking focus
        this.Resizable         := o("Resizable", true)          ; WS_THICKFRAME + resize hotspots
        this.MaximizeBox       := o("MaximizeBox", true)        ; WS_MAXIMIZEBOX: taskbar/system menu/Snap + the frame button
        ; comes up maximised, rather than maximised after. AxGui builds its
        ; window in Show(), running this again: a StartMaximized set on it
        ; before then is kept, not reset
        this.StartMaximized    := o("Maximized", this.HasOwnProp("StartMaximized") ? this.StartMaximized : false)
        this.MinimizeBox       := o("MinimizeBox", true)        ; WS_MINIMIZEBOX + the frame button
        this.UseAccent         := o("UseAccent", true)          ; emit accent-colour CSS (retro stylesheets turn this off)
        this.AllowZoom         := o("AllowZoom", false)         ; Ctrl+wheel / Ctrl+plus-minus / pinch zoom of the page
        this.FocusRing         := o("FocusRing", "accent")      ; keyboard focus ring: "accent" | "contrast" | "none" | "#rrggbb"
        this.AppName           := o("AppName", "")              ; registers an AppUserModelID so notifications carry this name
        this.AppId             := o("AppId", "")                ; ... optional explicit AUMID (default derived from AppName)
        if (this.AppName != "")
            AxSys.RegisterApp(this.AppName, this.AppId)
        this.Components        := o("Components", true)         ; expand <ax-*> tags (see AxTags.ahk)
        this.Chrome := {Titlebar: "titlebar", Min: "btnMin", Max: "btnMax", Close: "btnClose", Resize: "rz"}
        if opts.HasOwnProp("Chrome")
            for k, v in opts.Chrome.OwnProps()
                this.Chrome.%k% := v

        if !this.HasOwnProp("Hooks")
            this.Hooks := Map()     ; eventType -> Map(id -> fn)
        this.Doc      := ""
        this.Ready    := false
        this.Closing  := false
        ; a subclass may have queued callbacks before calling this constructor
        ; (the page can finish loading synchronously inside it)
        if !this.HasOwnProp("_readyCbs")
            this._readyCbs := []
        if !this.HasOwnProp("_closeCbs")
            this._closeCbs := []
        if !this.HasOwnProp("_ctx")
            this._ctx := Map()      ; element id (or "*") -> items / Menu
        this._ctxItems  := Map()    ; open-menu item id -> fn
        this._ctxOpen   := false
        this._ctxPin    := ""       ; submenu pinned open by a click
        this._ctxPinLevel := 0
        this._ctxCloseLevel := 0
        if !this.HasOwnProp("_pop")
            this._pop := Map()      ; popover anchor id -> spec
        this._popOpen := "", this._popPend := ""
        if !this.HasOwnProp("_tb")
            this._tb := []          ; title-bar items (AxWindow.Titlebar.ahk)
        this._ctxTarget := ""
        this._dlg       := ""
        this._maxRect   := ""       ; maximize button, device px in main-window client coords
        this._maxRectDirty := true  ; measured on the first hit-test, not on every theme change
        this._maxHover  := false
        this._subclassed := Map()
        this._tbLastDown := 0
        this._tipUid := "", this._tipEl := ""
        if !this.HasOwnProp("_valueCbs")
            this._valueCbs := Map() ; component id -> [fn(value, el), ...]
        this._ddOpen := ""          ; currently open dropdown element
        this._acFocus := "", this._acLast := "", this._acHandled := false, this._acHover := "", this._acDown := false   ; autocomplete state
        this._accent := ""
        ; what the caller chose; "" means the sheet's own.
        ;
        ; Not cleared here: the options were read further up, and this line
        ; used to throw away whatever Accent: said -- so the documented option
        ; did nothing at all, and every generated script that set one was
        ; quietly using the sheet's default instead.
        if !this.HasOwnProp("Accent")
            this.Accent := ""
        this._libCss := Map()          ; our own stylesheets, kept raw for re-hueing
        this._baseCss := Map()         ; the same, for the layer under the theme
        if !this.HasOwnProp("_cssNow")
            this._cssNow := Map()      ; <style> id -> the text last put in it (_PutCss)
        this._drag := ""            ; active drag-reorder state
        if !this.HasOwnProp("_pageCbs")
            this._pageCbs := []
        this.CurrentPage := ""
        this._ihk := "", this._ihkBox := ""   ; InputHook while a hotkey box has focus
        this._activeObj := ""
        this._nbStepped := false
        this._pressed := ""          ; element carrying the "pressed" class during a mouse press
        this._shielded := []         ; scrollers whose scrollbar is hidden while a dropdown is open
        this._slActive := ""        ; slider being dragged (Trident sends no change/input for ranges)
        this._slLast := ""
        this._snapPollFn := ObjBindMethod(this, "_SnapPoll")
        this._toastFn    := ObjBindMethod(this, "_HideToast")
        this._tipShowFn  := ObjBindMethod(this, "_ShowTip")
        this._revealFn   := ObjBindMethod(this, "_RevealAx")
        this._popShowFn  := ObjBindMethod(this, "_PopShow")
        this._popHideFn  := ObjBindMethod(this, "_PopHide")
        this._popOpenFn  := ObjBindMethod(this, "_PopOpenPending")
        this._popLeaveFn := ObjBindMethod(this, "_PopLeave")
        this._dragArmFn  := ObjBindMethod(this, "_DragArm")
        this._ctxCloseFn := ObjBindMethod(this, "_CtxCloseDeeper")

        if this.BrowserEmulation
            AxSys.BrowserEmulation(this.BrowserEmulation)
        if (this.GpuRendering != "")                      ; read when the browser starts, so before it does
            AxSys.GpuRendering(this.GpuRendering)
        AxWindow._HookMessages()

        g := this.Gui := Gui("-Caption" (this.Resizable ? " +Resize" : "") (this.Composited ? " +E0x02000000" : ""), this.Title != "" ? this.Title : "ActiveX GUI")
        g.BackColor := this.BackColor
        g.OnEvent("Close",  (*) => (this.Close(false, "system"), true))   ; Alt+F4, the taskbar, the system menu; true: the Gui is not hidden when a question kept it
        g.OnEvent("Escape", (*) => this._OnEscape())
        g.OnEvent("Size",   (gg, mm, w, h) => this._OnSize(mm, w, h))
        AxWindow._byHwnd[g.Hwnd] := this

        ; WS_MINIMIZEBOX / WS_MAXIMIZEBOX drive the taskbar preview, the system
        ; menu, Aero Snap and Win+Arrows even though the caption is custom
        style := DllCall("GetWindowLongPtr", "Ptr", g.Hwnd, "Int", -16, "Ptr")
        style := (style & ~0x30000) | (this.MinimizeBox ? 0x20000 : 0) | (this.MaximizeBox ? 0x10000 : 0)
        DllCall("SetWindowLongPtr", "Ptr", g.Hwnd, "Int", -16, "Ptr", style)

        ; Hidden until the page has loaded so Trident's white first paint is
        ; never seen; the Gui's BackColor shows instead.
        this.Ax := g.Add("ActiveX", "x0 y0 w" this.Width " h" this.Height " Hidden", "Shell.Explorer.2")
        this.WB := this.Ax.Value
        this._wbSink := AxWindow.BrowserSink(this)
        ComObjConnect(this.WB, this._wbSink)
        try this.WB.Silent := true
        if (this.HtmlFile != "")
            this.WB.Navigate("file:///" StrReplace(this.HtmlFile, "\", "/"))
        else
            this.WB.Navigate("about:blank")               ; HtmlString is written on DocumentComplete
    }
    ; ---------------------------------------------------------------- window
    Show() {
        pos := (this.X != "" ? " x" this.X : "") (this.Y != "" ? " y" this.Y : "")
        ; NoActivate leaves the user's foreground window alone -- for a tool or
        ; palette window, and for anything running in the background
        this.Gui.Show((this.NoActivate ? "NoActivate " : "") (this.StartMaximized ? "Maximize " : "")
                    . "w" this.Width " h" this.Height pos)
        SetTimer(this._revealFn, -3000)          ; safety net if DocumentComplete never fires
        this.SetRoundCorners(this.RoundCorners)   ; Win11 rounds by default: "false" must ask for square
        AxSys.Shadow(this.Gui.Hwnd)
        this._UpdateBorder()
        return this
    }
    Hide()     => this.Gui.Hide()
    ; WaitReady(ms): pump messages until the page has loaded (Ready). Needed
    ; when building without showing: DocumentComplete may arrive asynchronously.
    WaitReady(ms := 3000) {
        t := A_TickCount
        while (!this.Ready && !this.Closing && A_TickCount - t < ms)
            Sleep(10)
        return this.Ready
    }
    Minimize() => this.Gui.Minimize()
    Maximize() => this.Gui.Maximize()
    Restore()  => this.Gui.Restore()
    IsMaximized() => DllCall("IsZoomed", "Ptr", this.Gui.Hwnd, "Int") != 0
    ToggleMaximize() => !this.MaximizeBox ? this : (this.IsMaximized() ? this.Restore() : this.Maximize())
    AlwaysOnTop(on := true) => WinSetAlwaysOnTop(on ? 1 : 0, this.Gui)
    SetTitle(t) {
        this.Title := t
        this.Gui.Title := (this._dirty ? "• " : "") t     ; the taskbar keeps the unsaved dot (Dirty)
        try this.Text("titleText", t)
        return this
    }
    ; Pages: any element with class "page"; nav items carry data-page="pageId".
    ShowPage(id) {
        if !IsObject(this.Doc)
            return this
        try {
            pages := this.Doc.querySelectorAll(".page")
            loop pages.length {
                p := pages.item(A_Index - 1)
                AxWindow._SetClass(p, "visible", p.id = id)
            }
            navs := this.Doc.querySelectorAll(".nav-item")
            loop navs.length {
                n := navs.item(A_Index - 1)
                AxWindow._SetClass(n, "active", AxWindow._Attr(n, "data-page") = id)
            }
        }
        this.CurrentPage := id
        for cb in this._pageCbs
            try cb(id, this)
        this._LayoutEmbeds()
        return this
    }
    OnPage(fn) {
        this._pageCbs.Push(fn)
        return this
    }
    Hwnd => this.Gui.Hwnd
    ; SetBackColor("202020"): the colour shown wherever the page has not
    ; painted yet (resize, load). Applied to the Gui and to the class
    ; background brushes of the browser's host windows, which are white by
    ; default and are what flashes during a resize.
    SetBackColor(hex) {
        static brushes := Map()
        hex := LTrim(hex, "#")
        this.BackColor := hex
        try this.Gui.BackColor := hex
        try {
            rgb := Integer("0x" hex)
            colorref := ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | (rgb >> 16)
            if !brushes.Has(hex)
                brushes[hex] := DllCall("CreateSolidBrush", "UInt", colorref, "Ptr")
            for h in this._subclassed
                DllCall("SetClassLongPtr", "Ptr", h, "Int", -10, "Ptr", brushes[hex])   ; GCLP_HBRBACKGROUND
            AxSys.Backdrop(this.Gui.Hwnd, hex)           ; DWM paints this where the app has not yet (live resize)
        }
        ; changing Gui.BackColor repaints the parent over the browser child;
        ; make the browser (and its host windows) paint again right away
        try DllCall("RedrawWindow", "Ptr", this.Ax.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x185)   ; INVALIDATE|ERASE|ALLCHILDREN|UPDATENOW
        return this
    }
    static RegisterApp(name, aumid := "", icon := "", iconIndex := 0) => AxSys.RegisterApp(name, aumid, icon, iconIndex)
    ; SetIcon(file, index): tray + window icon (TraySetIcon) and the frame image
    SetIcon(file, index := 1) {
        TraySetIcon(file, index)
        this._RefreshFrameIcon()
        return this
    }
    ; native system menu (Restore / Move / Size / Minimize / Maximize / Close)
    ShowSystemMenu(x?, y?) {
        if !IsSet(x) {
            pt := Buffer(8, 0)
            DllCall("GetCursorPos", "Ptr", pt)
            x := NumGet(pt, 0, "Int"), y := NumGet(pt, 4, "Int")
        }
        PostMessage(0x313, 0, (y << 16) | (x & 0xFFFF), , this.Gui)   ; WM_POPUPSYSTEMMENU
        return this
    }
    ; SetExtraCss(id, css): create/replace a named <style> at the end of <head>
    ; (e.g. a colour scheme layered over the stylesheet); "" removes it
    ; themed:=true marks the sheet as the library's own, so _ReTheme may
    ; re-hue it when the accent changes
    SetExtraCss(id, css, themed := false) {
        if themed
            this._libCss[id] := css
        else
            AxWindow._DropKey(this._libCss, id)
        if (themed && this.Accent != "")
            css := AxSys.RecolourCss(css, this._accent)
        try {
            doc := this.Doc
            st := doc.getElementById("axExtra_" id)
            if (css = "") {
                AxWindow._DropKey(this._cssNow, "axExtra_" id)
                if IsObject(st)
                    st.parentNode.removeChild(st)
                return this
            }
            if !IsObject(st) {
                st := doc.createElement("style")
                st.id := "axExtra_" id, st.type := "text/css"
                head := doc.getElementsByTagName("head").item(0)
                accent := doc.getElementById("axAccentCss")
                ; in front of the accent sheet, so a chosen accent or tint
                ; always has the last word on colour
                if IsObject(accent)
                    head.insertBefore(st, accent)
                else
                    head.appendChild(st)
                AxWindow._DropKey(this._cssNow, "axExtra_" id)
            }
            this._PutCss(st, "axExtra_" id, css)
        }
        return this
    }
    ; Setting a stylesheet restyles the whole page, even to the text it
    ; already has -- and a window's start used to do that half a dozen times
    ; over (the theme re-hued to no change, a pack's sheet re-registered as
    ; written). _PutCss skips a write of the same text; _cssNow knows what
    ; each of the library's <style> elements holds, the page's own included
    ; (AxGui enters those as it writes them). A new element is always written.
    _PutCss(st, key, css) {
        if (this._cssNow.Has(key) && this._cssNow[key] == css)
            return
        AxWindow._SetStyleText(st, css)
        this._cssNow[key] := css
    }
    ; SetBaseCss(id, css): a named <style> placed BEFORE the page's stylesheet,
    ; so the theme has the last word over it; "" removes it.
    ;
    ; This is where a component's own stylesheet goes. A component knows what
    ; shape it is and the theme knows what it looks like, and the two only stay
    ; separable if the component's sheet is underneath: put it on top instead
    ; and a theme that tries to restyle the component quietly loses.
    SetBaseCss(id, css) {
        if (css = "")
            AxWindow._DropKey(this._baseCss, id)
        else
            this._baseCss[id] := css
        if (css != "" && this.Accent != "")
            css := AxSys.RecolourCss(css, this._accent)
        try {
            doc := this.Doc
            st := doc.getElementById("axPack_" id)
            if (css = "") {
                AxWindow._DropKey(this._cssNow, "axPack_" id)
                if IsObject(st)
                    st.parentNode.removeChild(st)
                return this
            }
            if !IsObject(st) {
                st := doc.createElement("style")
                st.id := "axPack_" id, st.type := "text/css"
                head := doc.getElementsByTagName("head").item(0)
                ; in front of the theme, which is the whole point. With no
                ; theme sheet on the page yet, the front of <head> is the
                ; same place -- anything added later still lands after it.
                anchor := doc.getElementById("axPackBase")
                if !IsObject(anchor)
                    anchor := doc.getElementById("axBase")
                if IsObject(anchor)
                    head.insertBefore(st, anchor)
                else if IsObject(head.firstChild)
                    head.insertBefore(st, head.firstChild)
                else
                    head.appendChild(st)
                AxWindow._DropKey(this._cssNow, "axPack_" id)
            }
            this._PutCss(st, "axPack_" id, css)
        }
        return this
    }
    SetRoundCorners(on := true) {
        AxSys.RoundCorners(this.Gui.Hwnd, on)
        return this
    }
    ; replace the page's base stylesheet at runtime (id "axBase" is created
    ; if the page has none); pass CSS text or a .css file path
    SetStylesheet(cssOrPath) {
        css := cssOrPath
        if (!InStr(css, "{") && FileExist(cssOrPath))
            css := FileRead(cssOrPath, "UTF-8")
        this._rawBase := css                        ; the sheet as written, for re-hueing
        try {
            doc := this.Doc
            st := doc.getElementById("axBase")
            if !IsObject(st) {
                st := doc.createElement("style")
                st.id := "axBase", st.type := "text/css"
                doc.getElementsByTagName("head").item(0).appendChild(st)
                AxWindow._DropKey(this._cssNow, "axBase")
            }
            this._PutCss(st, "axBase", AxSys.RecolourCss(css, this.Accent = "" ? "" : this._accent))
            this._ApplyAccentCss(this._accent)      ; keep accent rules after the base sheet
            this._UpdateMaxRect()
        }
        this._FireLook()                            ; a new stylesheet is a new surface
        return this
    }
    ; Re-inject the library's own stylesheets with the accent's hue in place of
    ; their built-in blue. Called whenever the accent moves; a script's own
    ; SetExtraCss is left alone, because that is the script's colour, not ours.
    _ReTheme() {
        ; _accent always holds a concrete colour (it falls back to the Fluent
        ; blue), so the question "did the caller pick one" is Accent, not that
        acc := (this.Accent = "") ? "" : this._accent
        ; the library's own component CSS always takes the accent in force --
        ; the stylesheet's own when none is chosen -- so a calendar or a range
        ; slider on cozy is cozy's orange, not the Fluent blue it is written in
        eff := (this.HasOwnProp("_accent") && this._accent != "") ? this._accent : this.DefaultAccent(this.Theme)
        ; their blends of the blue (a range's band, a hover) turn with it, on
        ; any sheet whose accent is not the Fluent blue they were written in
        hue := (acc != "") ? acc : (eff = ((this.Theme = "light") ? "#005fb8" : "#60cdff")) ? "" : eff
        Pack(raw) {
            css := AxSys.AccentCss(raw, eff)
            if (hue = "")
                return css
            ; the remaining blues follow the chosen hue; the accent itself is
            ; already exact, so it sits out that pass under a name that is not
            ; a colour
            return StrReplace(AxSys.RecolourCss(StrReplace(css, eff, "#axACCENT"), hue), "#axACCENT", eff)
        }
        try {
            doc := this.Doc
            if this.HasOwnProp("_rawBase") {
                st := doc.getElementById("axBase")
                if IsObject(st)
                    this._PutCss(st, "axBase", AxSys.RecolourCss(this._rawBase, acc))
            }
            if this.HasOwnProp("_rawPack") {                 ; the core packs, put in the page by AxGui
                st := doc.getElementById("axPackBase")
                if IsObject(st)
                    this._PutCss(st, "axPackBase", Pack(this._rawPack))
            }
            for id, raw in this._libCss {
                st := doc.getElementById("axExtra_" id)
                if IsObject(st)
                    this._PutCss(st, "axExtra_" id, Pack(raw))
            }
            for id, raw in this._baseCss {
                st := doc.getElementById("axPack_" id)
                if IsObject(st)
                    this._PutCss(st, "axPack_" id, Pack(raw))
            }
        }
    }
    ; Trident document mode actually in use (11 = IE11 standards). Anything
    ; lower means FEATURE_BROWSER_EMULATION did not apply to this process.
    DocMode {
        get {
            try return this.Doc.documentMode
            return 0
        }
    }
    ; Call after changing the HTML layout of the title bar so the Snap
    ; Layouts hit-test rectangle follows the maximize button.
    RefreshChrome() {
        this._UpdateMaxRect()
        return this
    }
    ; Start a native move (HTCAPTION) or resize loop. edge: "N","S","E","W",
    ; "NW","NE","SW","SE" or "" for move.
    Drag(edge := "") {
        static ht := Map("", 2, "W", 10, "E", 11, "N", 12, "NW", 13, "NE", 14, "S", 15, "SW", 16, "SE", 17)
        DllCall("user32\ReleaseCapture")
        PostMessage(0xA1, ht[StrUpper(edge)], 0, , this.Gui)   ; WM_NCLBUTTONDOWN
    }
    OnReady(fn) {
        this._readyCbs.Push(fn)
        if this.Ready
            fn(this)
        return this
    }
    OnClose(fn) {
        this._closeCbs.Push(fn)
        return this
    }
    ; ------------------------------------------------ closing, asked first
    ; OnBeforeClose(fn): fn(win, why) runs before the window closes, however
    ; the close was asked for -- return true to keep the window open. why:
    ;   "button"  the title bar's close button    "icon"    the icon, double-clicked
    ;   "system"  Alt+F4, the taskbar, the system menu's Close (WM_CLOSE)
    ;   "escape"  Escape, with EscapeCloses       "exit"    the tray's Exit or Reload
    ;   "code"    win.Close() from the script;    win.Close(true) asks nobody
    OnBeforeClose(fn) {
        this._beforeCbs.Push(fn)
        if !AxWindow._exitHooked                    ; the tray's Exit and Reload ask too
            AxWindow._exitHooked := true, OnExit(ObjBindMethod(AxWindow, "_OnExit"))
        return this
    }
    ; Unsaved changes: set it when something changes, clear it once saved.
    ; The title shows a dot meanwhile, and AskBeforeClose asks only then.
    Dirty {
        get => this._dirty
        set {
            this._dirty := value ? true : false
            this.BodyClass("ax-dirty", this._dirty)
            try this.Gui.Title := (this._dirty ? "• " : "") this.Title
        }
    }
    ; The usual question, ready made. With unsaved changes: "Save them before
    ; closing?" -- Save / Don't save / Cancel. save(win) saves and returns
    ; anything but false; false (a Save As that was cancelled) keeps the
    ; window open. Without a save function: Close anyway / Cancel.
    ;   opts: Text, Title, Always (ask even with nothing unsaved), CloseText
    AskBeforeClose(save := "", opts := "") {
        this._saveFn := save, this._askOpts := IsObject(opts) ? opts : {}
        if !this._askOn
            this._askOn := true, this.OnBeforeClose(ObjBindMethod(this, "_AskSave"))
        return this
    }
    _AskSave(win, why) {
        opt := (n, d) => this._askOpts.HasOwnProp(n) ? this._askOpts.%n% : d
        title := opt("Title", this.Title)
        if !this._dirty
            return opt("Always", false) ? !this.Confirm(opt("CloseText", "Close " title "?"), title, "Close", "Cancel") : false
        hasSave := IsObject(this._saveFn)
        btns := hasSave ? ["Save", "Don't save", "Cancel"] : ["Close anyway", "Cancel"]
        r := this.Dialog(opt("Text", "There are unsaved changes. " (hasSave ? "Save them before closing?" : "Close anyway, and lose them?")),
                         title, btns, {Kind: "warning", Cancel: btns.Length})
        switch r.Button {
        case "Save":
            ok := AxGuiCompat.CallFit(this._saveFn, [this])
            if (ok is Integer && ok = 0)            ; not saved after all: stay
                return true
            this.Dirty := false
            return false
        case "Don't save", "Close anyway":
            return false
        }
        return true                                  ; Cancel, or Escape
    }
    ; Every OnBeforeClose, in turn, until one keeps the window. A window that
    ; is minimised comes back first, so the question can be seen.
    _Allowed(why) {
        if (!this._beforeCbs.Length || !this.Ready)    ; no page yet: nothing to ask in
            return true
        if (this._asking || this._dlg)               ; a question is on screen already
            return false
        try {
            if DllCall("IsIconic", "Ptr", this.Gui.Hwnd)
                this.Restore()
        }
        this._asking := true
        keep := false
        try {
            for fn in this._beforeCbs.Clone()
                if AxGuiCompat.CallFit(fn, [this, why]) {
                    keep := true
                    break
                }
        } finally
            this._asking := false
        return !keep
    }
    static _exitHooked := false
    static _exitAsked := false
    ; The tray's Exit and Reload. OnExit cannot wait for a question on the
    ; page -- nothing else runs while it does -- so the exit is called off,
    ; the question is asked on a thread of its own, and only then does the
    ; script exit (or reload) for real.
    static _OnExit(reason, code) {
        if (AxWindow._exitAsked || !InStr("|Menu|Close|Reload|", "|" reason "|"))
            return 0
        ask := []
        for h, w in AxWindow._byHwnd
            if (!w.Closing && w.Ready && w._beforeCbs.Length)
                ask.Push(w)
        if !ask.Length
            return 0
        SetTimer(AxWindow._AskExitFn(ask, reason), -1)
        return 1
    }
    static _AskExitFn(ask, reason) => (*) => AxWindow._AskExit(ask, reason)
    static _AskExit(ask, reason) {
        for w in ask
            if (!w.Closing && !w._Allowed("exit"))
                return                                   ; Cancel: the script stays
        AxWindow._exitAsked := true
        if (reason = "Reload")
            Reload()
        else
            ExitApp()
    }
    _beforeCbs := []
    _dirty := false
    _asking := false
    _askOn := false
    _saveFn := ""
    _askOpts := ""
    Close(force := false, why := "code") {
        if this.Closing
            return
        ; A menu still open on this thread runs its own loop over everything
        ; else -- the system menu, when the icon is double-clicked: the first
        ; click opened it, the second closes the window. Closing under it
        ; leaves the menu on screen and the script running until something
        ; dismisses it. So dismiss it first, take the window off the screen at
        ; once, and close for good once the menu's loop has gone (timers only
        ; run again then). A system menu still waiting in the queue is refused
        ; meanwhile (_OnMsg, WM_POPUPSYSTEMMENU).
        if (this._menuWaits < 40 && AxWindow._EndMenus()) {
            this._menuWaits += 1
            if (force || !this._beforeCbs.Length)    ; with a question to ask, it has to stay in sight
                try DllCall("ShowWindow", "Ptr", this.Gui.Hwnd, "Int", 0)
            SetTimer(ObjBindMethod(this, "Close", force, why), -15)
            return
        }
        ; anyone who wants a say -- unsaved changes -- has it now, however the
        ; close was asked for (see OnBeforeClose)
        if (!force && !this._Allowed(why)) {
            this._menuWaits := 0
            return false
        }
        this.Closing := true
        for cb in this._closeCbs
            try cb(this)
        this._HotkeyCapture("")
        SetTimer(this._snapPollFn, 0)
        SetTimer(this._toastFn, 0)
        SetTimer(this._tipShowFn, 0)
        SetTimer(this._revealFn, 0)
        for f in [this._popShowFn, this._popHideFn, this._popOpenFn, this._popLeaveFn,
                  this._dragArmFn, this._ctxCloseFn]
            SetTimer(f, 0)
        try ComObjConnect(this.Doc, "")
        try ComObjConnect(this.WB, "")
        this._RemoveDropTarget()
        AxWindow._byHwnd.Delete(this.Gui.Hwnd)
        for h in this._subclassed
            try DllCall("comctl32\RemoveWindowSubclass", "Ptr", h, "Ptr", AxWindow._SubclassCb(), "Ptr", 1)
        try this.Gui.Destroy()
        if this.ExitOnClose
            ExitApp()
    }
    _menuWaits := 0
    ; whether this thread is inside a menu's loop (GetGUIThreadInfo, GUI_INMENUMODE)
    static _InMenu() {
        gti := Buffer(8 + 6 * A_PtrSize + 16, 0)
        NumPut("UInt", gti.Size, gti, 0)
        if !DllCall("GetGUIThreadInfo", "UInt", DllCall("GetCurrentThreadId", "UInt"), "Ptr", gti)
            return false
        return (NumGet(gti, 4, "UInt") & 0x4) != 0
    }
    ; End the menu this thread has open, if it has one: true when there was.
    ; EndMenu alone leaves a system menu standing; WM_CANCELMODE to the window
    ; that owns it is what Windows itself sends to call a menu off, and a
    ; WM_NULL wakes its loop to notice.
    static _EndMenus() {
        gti := Buffer(8 + 6 * A_PtrSize + 16, 0)
        NumPut("UInt", gti.Size, gti, 0)
        if !DllCall("GetGUIThreadInfo", "UInt", DllCall("GetCurrentThreadId", "UInt"), "Ptr", gti)
            return false
        if !(NumGet(gti, 4, "UInt") & 0x4)                          ; GUI_INMENUMODE
            return false
        owner := NumGet(gti, 8 + 3 * A_PtrSize, "Ptr")              ; hwndMenuOwner
        DllCall("EndMenu")
        if owner {
            DllCall("SendMessageTimeoutW", "Ptr", owner, "UInt", 0x1F, "Ptr", 0, "Ptr", 0,
                    "UInt", 2, "UInt", 250, "Ptr*", 0)              ; WM_CANCELMODE, SMTO_ABORTIFHUNG
            DllCall("PostMessageW", "Ptr", owner, "UInt", 0, "Ptr", 0, "Ptr", 0)
        }
        return true
    }
    ; ---------------------------------------------------------------- events
    ; Supported types: click dblclick mousedown mouseup mouseover mouseout
    ; change keyup keydown focusin focusout contextmenu
    ; fn(el, ev): el = matched element (walks up like Element.closest()),
    ;             ev = raw Trident event object (srcElement, keyCode, ...)
    On(eventType, id, fn) {
        if !this.Hooks.Has(eventType)
            this.Hooks[eventType] := Map()
        this.Hooks[eventType][id] := fn
        return this
    }
    Off(eventType, id) {
        if this.Hooks.Has(eventType)
            AxWindow._DropKey(this.Hooks[eventType], id)
        return this
    }
    ; -------------------------------------------------------------- DOM API
    El(id) => this.Doc.getElementById(id)
    ; A text box's text is its value: an <input> or a <textarea> has no
    ; innerText of its own, so reading that gave "" whatever was typed
    Text(id, value?) {
        el := this.El(id)
        box := AxWindow._IsTextBox(el)
        if IsSet(value) {
            if box {
                if (el.value !== String(value))     ; the same again would put the caret at the end
                    el.value := String(value)
            }
            else
                AxWindow._SetText(el, value)
            return this
        }
        return box ? el.value : el.innerText
    }
    static _IsTextBox(el) {
        try {
            t := el.tagName
            if (t = "TEXTAREA")
                return true
            if (t = "INPUT")
                return RegExMatch(el.type, "i)^(text|password|search|email|url|tel|number)$") ? true : false
        }
        return false
    }
    Html(id, value?) {
        el := this.El(id)
        if IsSet(value) {
            el.innerHTML := value
            return this
        }
        return el.innerHTML
    }
    ; Components outside the core (lib\rich) join the Value/OnValue contract
    ; by registering a data-role here, so ctl.Value and OnChange work on them
    ; exactly as they do on a dropdown.
    static ValueHandlers := Map()
    static RegisterValue(role, getFn, setFn) {
        AxWindow.ValueHandlers[role] := {Get: getFn, Set: setFn}
    }
    ; A component joins the click contract the same way: it says which
    ; data-role it answers to, and gets called with the window as `this`.
    ;
    ; The distinction the dispatcher needs is between a *part* and a *box*.
    ; A part is the piece that was clicked -- a menu item, a star, a swatch --
    ; and is usually found by its class. A box is the whole control -- a
    ; dropdown, a slider, a switch -- and a click inside one belongs to
    ; whichever part is nearer, so the search walks past it.
    static ClickHandlers := Map()        ; role -> fn(win, el, ev)
    static ClickParts := []              ; classes that mark a clickable part
    static ClickBoxes := Map()           ; roles that are the control itself
    static RegisterClick(role, fn, byClass := false) {
        AxWindow.ClickHandlers[role] := fn
        if byClass {
            for c in AxWindow.ClickParts
                if (c = role)
                    return
            AxWindow.ClickParts.Push(role)
        }
    }
    static RegisterBox(roles*) {
        for r in roles
            AxWindow.ClickBoxes[r] := true
    }
    ; The page rail is the window's own, not a control's, so the core keeps it
    ; and registers it exactly the way a component would. `sortable` is the
    ; drag-to-reorder machinery, which serves any control.
    static _clickCore := AxWindow._SeedClicks()
    static _SeedClicks() {
        AxWindow.RegisterClick("nav-item", (w, el, t, ev) => w._NavClick(t), true)
        AxWindow.RegisterBox("sortable")
        return true
    }
    ; A menu opened from the bar leaves a highlighted title behind, so the
    ; bar is told whenever any menu closes.
    _BarMenuClosed() {
        if (!this.HasOwnProp("_mb") || this._mb.Switching)
            return                                   ; mid-swap between two menus
        if this._mb.Open {
            this._mb.Open := 0
            this._MbActivate(false)                  ; picking an item ends menu mode
        }
    }
    Value(id, value?) {
        el := this.El(id)
        if !IsObject(el)
            throw ValueError("Value(): no element with id '" id "'", -1)
        role := AxWindow._Attr(el, "data-role")
        if AxWindow.ValueHandlers.Has(role) {
            h := AxWindow.ValueHandlers[role]
            ; through a local: h.Set(...) would be a method call and pass h in
            if IsSet(value) {
                set := h.Set
                set(this, el, value)
                return this
            }
            get := h.Get
            return get(this, el)
        }
        if IsSet(value) {
            if (role = "list" && AxWindow._Attr(el, "data-multi") != "") {
                want := IsObject(value) ? value : StrSplit(value, "|")
                items := el.querySelectorAll(".list-item")
                loop items.length {
                    it := items.item(A_Index - 1), on := false
                    for v in want
                        if (v = AxWindow._Attr(it, "data-value"))
                            on := true
                    AxWindow._SetClass(it, "selected", on)
                }
                this._CommitMulti(el)
            } else if (role = "dropdown" || role = "list" || role = "palette")
                this._SelectItem(el, role, value)
            else if (role = "hotkey")
                this._SetHotkeyValue(el, value, AxWindow.HotkeyDisplay(value))
            else if (role = "rating") {
                stars := el.querySelectorAll(".star")
                loop stars.length
                    AxWindow._SetClass(stars.item(A_Index - 1), "on", A_Index <= Integer(value))
                el.setAttribute("data-value", value), this._UpdateOut(el, value)
            } else if (role = "segmented") {
                segs := el.querySelectorAll(".seg")
                loop segs.length {
                    sg := segs.item(A_Index - 1)
                    AxWindow._SetClass(sg, "active", AxWindow._Attr(sg, "data-value") = value)
                }
                el.setAttribute("data-value", value)
            }
            else if (role = "numberbox" || role = "slider")
                this._SetInput(el, value)
            else if (role = "autocomplete") {
                label := value, items := el.querySelectorAll(".dd-item")
                loop items.length
                    if (AxWindow._Attr(items.item(A_Index - 1), "data-value") = value)
                        label := items.item(A_Index - 1).innerText
                el.querySelector("input").value := label
                el.setAttribute("data-value", value)
            }
            else if (role = "switch" || role = "check")
                el.querySelector("input").checked := value ? true : false
            else if (role = "radiogroup") {
                radios := el.querySelectorAll("input")
                loop radios.length {
                    r := radios.item(A_Index - 1)
                    r.checked := (AxWindow._Attr(r.parentElement, "data-value") = value)
                }
            } else
                el.value := value
            return this
        }
        if (role = "list" && AxWindow._Attr(el, "data-multi") != "")
            return StrSplit(AxWindow._Attr(el, "data-value"), "|", , -1)
        if (role = "dropdown" || role = "list" || role = "palette" || role = "hotkey" || role = "rating" || role = "segmented")
            return AxWindow._Attr(el, "data-value")
        if (role = "autocomplete")                 ; strict: chosen value; free: whatever is typed
            return AxWindow._Attr(el, "data-strict") != "" ? AxWindow._Attr(el, "data-value") : el.querySelector("input").value
        if (role = "radiogroup") {
            radios := el.querySelectorAll("input")
            loop radios.length {
                r := radios.item(A_Index - 1)
                if r.checked
                    return AxWindow._Attr(r.parentElement, "data-value")
            }
            return ""
        }
        if (role = "switch" || role = "check")
            return el.querySelector("input").checked ? 1 : 0
        if (role = "numberbox" || role = "slider")
            return el.querySelector("input").value
        return el.value
    }
    Checked(id, value?) {
        el := this.El(id)
        if IsSet(value) {
            el.checked := value ? true : false
            return this
        }
        return el.checked ? true : false
    }
    Attr(id, name, value?) {
        el := this.El(id)
        if IsSet(value) {
            el.setAttribute(name, value)
            return this
        }
        return el.getAttribute(name)
    }
    Style(id, prop, value) {
        this.El(id).style.%prop% := value
        return this
    }
    ShowEl(id, display := "block") => this.Style(id, "display", display)
    HideEl(id) => this.Style(id, "display", "none")
    Focus(id) {
        try this.El(id).focus()
        return this
    }
    HasClass(id, cls) => AxWindow._HasClass(this.El(id), cls)
    AddClass(id, cls) {
        AxWindow._SetClass(this.El(id), cls, true)
        return this
    }
    RemoveClass(id, cls) {
        AxWindow._SetClass(this.El(id), cls, false)
        return this
    }
    ToggleClass(id, cls, on?) {
        if IsSet(on)
            AxWindow._SetClass(this.El(id), cls, on)
        else
            AxWindow._SetClass(this.El(id), cls)     ; omitted = toggle, one read
        return this
    }
    Append(id, html) {
        this.El(id).insertAdjacentHTML("beforeend", html)
        return this
    }
    BodyClass(cls, on) {
        try AxWindow._SetClass(this.Doc.body, cls, on)
        return this
    }
    ; --------------------------------------------------------------- theme
    ; SetTheme("dark"|"light"|"system", accent := "") toggles body classes
    ; theme-dark / theme-light and applies the accent colour ("#rrggbb",
    ; "system" for the Windows accent, or "" for the theme's default).
    SetTheme(mode := "system", accent := "") {
        if (mode = "system" || mode = "")
            mode := AxWindow.SystemTheme()
        this.Theme := mode
        this.BodyClass("theme-dark", mode = "dark")
        this.BodyClass("theme-light", mode = "light")
        ; the tray menu, the system menu and any Menu.Show() follow it
        h := 0
        try h := this.Gui.Hwnd
        try AxSys.MenuTheme(mode = "dark", h)
        this.SetBackColor(this.ThemeBack(mode))
        if (accent = "")
            accent := this.Accent
        this.SetAccent(accent)
        return this
    }
    SetAccent(hex := "") {
        this.Accent := hex
        if (hex = "system")
            hex := AxWindow.SystemAccent()
        if (hex = "")
            hex := this.DefaultAccent(this.Theme)
        this._accent := hex
        this._ApplyAccentCss(hex)
        this._FireLook()            ; SetTheme ends here too, so both are covered
        return this
    }
    ; The window colour behind the page for a theme. AxGui overrides this so
    ; each stylesheet brings its own pair; anything else gets the Fluent one.
    ThemeBack(mode) => (mode = "light") ? "f3f3f3" : "202020"
    ; The accent a stylesheet has when none is chosen. AxGui overrides this so
    ; each stylesheet names its own; anything else gets the Fluent pair.
    DefaultAccent(mode) => (mode = "light") ? "#005fb8" : "#60cdff"
    ; Accent and tint CSS a stylesheet wants on top of the Fluent rules above.
    ; AxGui implements it for win98 and winxp, whose chrome (title bar, task
    ; pane, menu bar, status bar) is painted rather than themed.
    _SheetCss(hex, onA, light) => ""
    ; "dark" or "light" from Windows' "Choose your app mode" setting
    static SystemTheme() => AxSys.SystemTheme()
    static SystemAccent() => AxSys.SystemAccent()
    ; SetTint("#rrggbb" | "accent" | "", strength?) tints the window surfaces
    ; (background, legends, dialog footer, light-mode cards) toward a colour.
    SetTint(hex := "", strength?) {
        this.Tint := hex
        if IsSet(strength)
            this.TintStrength := strength
        this._ApplyAccentCss(this._accent)
        this._FireLook()
        return this
    }
    ; OnLook(fn): fn(win) after the theme, the stylesheet, the accent or the
    ; tint changes. A component that paints anything from AHK rather than from
    ; its own stylesheet -- an accent applied inline, a surface read off the
    ; page -- has no other way to hear that the ground moved under it, and the
    ; alternative is every caller remembering to repaint it by hand.
    OnLook(fn) {
        if !this.HasOwnProp("_lookCbs")
            this._lookCbs := []
        this._lookCbs.Push(fn)
        return this
    }
    _FireLook() {
        if !this.HasOwnProp("_lookCbs")
            return this
        for fn in this._lookCbs.Clone()
            try fn(this)
        return this
    }
    ; OnValue(id, fn): fn(value, el) when a data-role component changes
    ; (dropdown, list, numberbox, slider, palette, switch, check, radio).
    OnValue(id, fn) {
        if !this._valueCbs.Has(id)
            this._valueCbs[id] := []
        this._valueCbs[id].Push(fn)            ; several listeners per id (e.g. Hotkey() + your own)
        return this
    }
    OffValue(id) {
        AxWindow._DropKey(this._valueCbs, id)      ; nothing registered is not an error
        return this
    }
    ; AxWindow.Toast(...) -> AxSys.Toast: see AxSys.ahk for the options object
    static Toast(opts, text := "", image := "", silent := false) => AxSys.Toast(opts, text, image, silent)
    ; =========================================================== internals
    _OnDocComplete() {
        if this.Closing
            return
        try url := this.WB.LocationURL
        catch
            url := ""
        if InStr(url, "about:blank") {
            if (this.HtmlString = "" || this._wroteHtml)
                return                          ; Shell.Explorer's placeholder page
            ; string mode: write the markup into the blank document. No further
            ; DocumentComplete follows, so carry on synchronously.
            this._wroteHtml := true
            ; the <ax-*> tags expanded in the text, so the page is parsed
            ; once (AxTags.ExpandHtml); "" back means expand it live below
            html := this.HtmlString
            if this.Components {
                pre := AxTags.ExpandHtmlCached(html)
                if (pre != "")
                    html := pre, this._tagsDone := !InStr(pre, "<ax-")
            }
            ; a window of pages shows one of them: what the others hold is
            ; most of the markup, and read now it is most of the wait. It is
            ; cut out here and put back just after the first paint
            if this._splitPages
                this._pagesLater := AxWindow._SplitPages(&html)
            d := this.WB.Document
            d.open()
            d.write(html)
            d.close()
        }
        try ComObjConnect(this.Doc, "")
        this.Doc := this.WB.Document
        this._docSink := AxWindow.DocSink(this)
        ComObjConnect(this.Doc, this._docSink)
        ; contextmenu is wired through attachEvent instead of the sink: Trident
        ; only honours a cancel when the handler returns a real VARIANT_BOOL
        ; false, which a connection-point sink cannot deliver.
        this._ctxFn := (*) => this._CtxHandler()
        try this.Doc.attachEvent("oncontextmenu", this._ctxFn)
        ; drag-selecting page text is suppressed everywhere except inputs,
        ; textareas and anything inside an element with data-selectable
        this._selFn := (*) => this._SelectStartHandler()
        try this.Doc.attachEvent("onselectstart", this._selFn)
        ; ... and so is Trident's native element drag, which otherwise lets an
        ; image, an <svg> or a link be dragged out of the window and paints a
        ; translucent copy of it under the cursor while you do
        this._dsFn := (*) => this._DragStartHandler()
        try this.Doc.attachEvent("ondragstart", this._dsFn)
        ; number boxes: reject non-numeric characters at keypress level
        this._keyFn := (*) => this._KeyPressHandler()
        try this.Doc.attachEvent("onkeypress", this._keyFn)
        ; Trident's document sink (ComObjConnect) delivers mouse events but NOT
        ; keyboard or focus events; those must be registered with attachEvent.
        this._kdFn := (*) => this._AttachedDispatch("keydown")
        this._kuFn := (*) => this._AttachedDispatch("keyup")
        this._fiFn := (*) => this._AttachedDispatch("focusin")
        this._foFn := (*) => this._AttachedDispatch("focusout")
        try this.Doc.attachEvent("onkeydown", this._kdFn)
        try this.Doc.attachEvent("onkeyup", this._kuFn)
        try this.Doc.attachEvent("onfocusin", this._fiFn)
        try this.Doc.attachEvent("onfocusout", this._foFn)
        this._InjectUI()
        this._WireChrome()
        this.BodyClass("maximized", this.IsMaximized())
        if this._MaybeRelaunch()
            return
        if (this.Components && this._tagsDone) {
            try AxTags.Shell(this.Doc.body)
        } else if this.Components {
            try AxTags.Expand(this.Doc)
        }
        this._InjectFrame()
        this._TbRender()                             ; anything TitleBar() asked for
        this._MakeFocusable()
        this.BodyClass("noresize", !this.Resizable), this.BodyClass("nomax", !this.MaximizeBox), this.BodyClass("nomin", !this.MinimizeBox)
        if (this.Title = "") {
            try this.Title := this.Doc.title
            if (this.Title != "")
                this.SetTitle(this.Title)
        } else
            try this.Text("titleText", this.Title)
        try {                                        ; first page visible if none is
            vis := this.Doc.querySelector(".page.visible")
            if IsObject(vis) {
                this.CurrentPage := vis.id
                ; and its nav item lit, as ShowPage would (no page callbacks yet)
                navs := this.Doc.querySelectorAll(".nav-item")
                loop navs.length {
                    n := navs.item(A_Index - 1)
                    AxWindow._SetClass(n, "active", AxWindow._Attr(n, "data-page") = vis.id)
                }
            } else {
                p := this.Doc.querySelector(".page")
                if IsObject(p)
                    this.ShowPage(p.id)
            }
        }
        if (this.Theme != "")
            this.SetTheme(this.Theme, this.Accent)
        else if (this.Accent != "")
            this.SetAccent(this.Accent)
        if !this.AllowZoom
            try  DPI := A_ScreenDPI / 96 * 100
              ,  this.WB.ExecWB(63, 2, Round(A_ScreenDPI / 96 * DPI), 0)             ; OLECMDID_OPTICAL_ZOOM -> 100%             
        this._RevealAx()
        ; IOleInPlaceActiveObject of the browser: key messages are routed
        ; through its TranslateAccelerator (see _SubclassProc)
        try this._activeObj := ComObjQuery(this.WB, "{00000117-0000-0000-C000-000000000046}")
        catch
            this._activeObj := ""
        this._InstallSubclasses()
        this._InstallDropTarget()          ; no-op unless a DropZone was registered
        this._UpdateMaxRect()
        if this._dirty                      ; set before the page was there
            this.BodyClass("ax-dirty", true)
        this.Ready := true
        ; the first callback is AxGui's _Wire, which shows the window before it
        ; puts the pages back; after it they are back whatever it did
        for cb in this._readyCbs
            cb(this), this._FillPages()
    }
    ; --- frame injection ---------------------------------------------------
    _InjectFrame() {
        if !this.Frame
            return
        doc := this.Doc
        if IsObject(doc.getElementById(this.Chrome.Titlebar))
            return
        spec := this._IconSpec()                  ; drawn once, not once to ask and once to use
        icon := (spec.Kind = "none") ? "" : '<span class="app-icon" id="axAppIcon"></span>'
        html := StrReplace(AxWindow.ReadLib("ui\frame.html"), "{icon}", icon)
        doc.body.insertAdjacentHTML("afterbegin", html)
        doc.body.insertAdjacentHTML("beforeend", AxWindow.ReadLib("ui\resize.html"))
        this._RefreshFrameIcon(spec)
    }
    ; What the Icon option asks for. Kind is "none", "glyph" or "img".
    _IconSpec() {
        v := Trim(String(this.Icon))
        if (v = "" || v = "none" || v = "0")
            return {Kind: "none"}
        if (v = "auto")
            return {Kind: "img", Src: AxSys.WindowIconDataUri(this.Gui.Hwnd)}
        if RegExMatch(v, "i)^[0-9A-F]{4,5}$")
            return {Kind: "glyph", Glyph: v}
        if (SubStr(v, 1, 5) = "data:")
            return {Kind: "img", Src: v}
        if RegExMatch(v, "i)\.(png|jpe?g|gif|bmp|svg)$")
            return {Kind: "img", Src: AxWindow.FileUrl(v)}
        return {Kind: "img", Src: AxSys.IconDataUri(v, 32)}      ; "file,index", .ico, .exe, .dll
    }
    ; SetFrameIcon(spec): change the title-bar icon at run time (same values as
    ; the Icon option). The tray/taskbar icon is SetIcon()'s job.
    SetFrameIcon(spec) {
        this.Icon := spec
        this._RefreshFrameIcon()
        return this
    }
    _RefreshFrameIcon(spec := "") {
        try {
            host := this.Doc.getElementById("axAppIcon")
            if !IsObject(host)
                return
            if !IsObject(spec)
                spec := this._IconSpec()
            if (spec.Kind = "glyph") {
                host.className := "ico app-icon"
                host.innerHTML := "&#x" spec.Glyph ";"
            } else if (spec.Kind = "img" && spec.Src != "") {
                host.className := "app-icon"
                host.innerHTML := '<img id="axAppIconImg" alt="" src="' AxWindow._Esc(spec.Src) '">'
            } else {
                host.className := "app-icon"
                host.innerHTML := ""
                host.style.display := "none"
            }
        }
    }
    static WindowIconDataUri(hwnd) => AxSys.WindowIconDataUri(hwnd)
    ; Trident read FEATURE_BROWSER_EMULATION before it was written (only
    ; possible if mshtml was already loaded in this process): relaunch once.
    _MaybeRelaunch() {
        if !this.AutoRestart || !this.BrowserEmulation || this.DocMode >= 11
            return false
        for a in A_Args
            if (a = "--ax-relaunched")
                return false
        this.Closing := true
        try Run(A_IsCompiled ? '"' A_ScriptFullPath '" --ax-relaunched' : '"' A_AhkPath '" "' A_ScriptFullPath '" --ax-relaunched')
        ExitApp()
    }
    _RevealAx() {
        SetTimer(this._revealFn, 0)
        try this.Ax.Visible := true
    }
    ; --- pages read after the first paint ----------------------------------
    ; What the hidden pages hold is most of a paged window's markup: Showcase's
    ; visible page is 180 elements of 2,500. _SplitPages empties every
    ; <div class="page"> but the visible one in the markup, before it is
    ; written, and hands back [[id, inner], ...]; _FillPages puts them back
    ; once the window is up, before anything else goes looking for what is on
    ; them. With no visible page, or markup it cannot follow, nothing is cut.
    static _SplitPages(&html) {
        static pageRe := 'iS)<div\s[^>]*?\bclass="page(?:\s[^"]*)?"[^>]*>'
        static tokRe  := 'iS)<(/?)div[\s>]|<(textarea|script|style|xmp)[\s>]|<!--'
        cut := [], out := "", at := 1
        if !RegExMatch(html, 'iS)<div\s[^>]*?\bclass="page\s(?:[^"]*\s)?visible[\s"]')
            return cut
        if !(pos := InStr(html, "<body"))
            return cut
        while RegExMatch(html, pageRe, &m, pos) {
            pos := m.Pos + m.Len
            if RegExMatch(m[0], 'i)\bclass="[^"]*\bvisible\b') || !RegExMatch(m[0], 'i)\sid="([^"]+)"', &idm)
                continue
            ; its own </div>: <div>s counted, and the text of a textarea, a
            ; script or a comment passed over whole -- that is not markup
            depth := 1, p := pos
            while depth {
                if !RegExMatch(html, tokRe, &t, p)
                    return []
                if (t[2] != "") {
                    if !(q := InStr(html, "</" t[2], false, t.Pos + t.Len))
                        return []
                    p := q + 2
                } else if (t[0] = "<!--") {
                    if !(q := InStr(html, "-->", , t.Pos + 4))
                        return []
                    p := q + 3
                } else {
                    depth += (t[1] = "/") ? -1 : 1
                    p := t.Pos + t.Len
                }
            }
            close := t.Pos
            cut.Push([AxTags.Unent(idm[1]), SubStr(html, pos, close - pos)])
            out .= SubStr(html, at, pos - at)
            at := close, pos := close
        }
        if cut.Length
            html := out SubStr(html, at)
        return cut
    }
    _FillPages() {
        if !this._pagesLater.Length
            return this
        later := this._pagesLater, this._pagesLater := []
        for pg in later {
            try {
                el := this.Doc.getElementById(pg[1])
                try el.innerHTML := pg[2]
                catch
                    el.insertAdjacentHTML("afterbegin", pg[2])
                this._MakeFocusable(el)
            }
        }
        return this
    }
    _WireChrome() {
        c := this.Chrome
        this.On("mousedown", c.Titlebar, (el, ev) => this._TitlebarDown(ev))
        for edge in ["N", "S", "E", "W", "NW", "NE", "SW", "SE"]
            this.On("mousedown", c.Resize edge, this._MakeResize(edge))
        for id in [c.Min, c.Max, c.Close]
            this.On("mousedown", id, (*) => "")        ; swallow, don't bubble to titlebar drag
        this.On("dblclick", c.Titlebar, (*) => this.ToggleMaximize())
        this.On("contextmenu", c.Titlebar, (el, ev) => this.ShowSystemMenu())
        this.On("mousedown", "axAppIcon", (*) => "")            ; don't start a drag from the icon
        this.On("click", "axAppIcon", (el, ev) => this._IconMenu(el))
        this.On("dblclick", "axAppIcon", (*) => this.Close(false, "icon"))
        this.On("click", c.Min,   (*) => this.Minimize())
        this.On("click", c.Max,   (*) => this.ToggleMaximize())
        this.On("click", c.Close, (*) => this.Close(false, "button"))
    }
    _MakeResize(edge) => (el, ev) => (this.Resizable && AxWindow._IsLeft(ev)) ? this.Drag(edge) : ""
    _IconMenu(el) {
        ; open already: a click on the icon closes it, as Windows' own does --
        ; and a double-click then meets no menu to close under
        if AxWindow._EndMenus()
            return
        try {
            r := el.getBoundingClientRect()
            rc := Buffer(16, 0), DllCall("GetClientRect", "Ptr", this.Ax.Hwnd, "Ptr", rc)
            k := NumGet(rc, 8, "Int") / this.Doc.documentElement.clientWidth
            pt := Buffer(8, 0), NumPut("Int", Round(r.left * k), pt, 0), NumPut("Int", Round(r.bottom * k), pt, 4)
            DllCall("ClientToScreen", "Ptr", this.Gui.Hwnd, "Ptr", pt)
            this.ShowSystemMenu(NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int"))
        } catch
            this.ShowSystemMenu()
    }
    ; The native move loop started by the first click swallows the second
    ; click's messages, so Trident never sees a dblclick on the title bar.
    ; Detect the double-click here instead, before starting a drag.
    _TitlebarDown(ev) {
        if !AxWindow._IsLeft(ev)
            return
        now := A_TickCount
        if (now - this._tbLastDown <= DllCall("GetDoubleClickTime", "UInt")) {
            this._tbLastDown := 0
            this.ToggleMaximize()
            return
        }
        this._tbLastDown := now
        this.Drag()
    }
    static _IsLeft(ev) {
        try return (ev.button != 2 && ev.button != 4)
        return true
    }
    _ApplyFocusCss(hex) {
        sel := ".btn:focus, .dropdown:focus, .list:focus, .tab:focus, .seg:focus, .chip:focus, .link:focus, .rating:focus, .swatch:focus, .axdlg-btn:focus, .imgbox.button:focus, .dropzone:focus"
        fr := this.FocusRing
        if (fr = "contrast")
            css := ""                                   ; the stylesheet's own ring
        else if (fr = "none" || fr = "")
            css := sel " { outline: none !important; }"
        else {
            color := (SubStr(fr, 1, 1) = "#") ? fr : hex
            css := sel " { outline: 1px solid " color " !important; outline-offset: 1px !important; }"
                . " body.theme-light " StrReplace(sel, ", ", ", body.theme-light ") " { outline-color: " color " !important; }"
                . " .list-item.kb { outline: 1px dashed " color " !important; }"
        }
        this.SetExtraCss("focus", css)
    }
    _ApplyAccentCss(hex) {
        this._ReTheme()
        if !IsObject(this.Doc)
            return
        this._ApplyFocusCss(hex != "" ? hex : this.DefaultAccent(this.Theme))
        if !this.UseAccent {
            try {
                st := this.Doc.getElementById("axAccentCss")
                if IsObject(st)
                    this._PutCss(st, "axAccentCss", "")
            }
            return
        }
        light := (this.Theme = "light")
        onA   := AxWindow._Luma(hex) > 0.45 ? "#000000" : "#ffffff"
        hov   := AxWindow._Mix(hex, light ? "#ffffff" : "#000000", 0.1)
        prs   := AxWindow._Mix(hex, light ? "#ffffff" : "#000000", 0.2)
        soft  := AxWindow._Rgba(hex, 0.18)
        css := ".btn.accent,.axdlg-btn.primary{background:" hex ";border-color:" hex ";color:" onA "}"
            . ".btn.accent:hover,.axdlg-btn.primary:hover{background:" hov ";border-color:" hov "}"
            . ".btn.accent:active,.axdlg-btn.primary:active{background:" prs ";border-color:" prs "}"
            . ".switch input:checked+.sw-track{background:" hex ";border-color:" hex "}"
            . ".switch input:checked+.sw-track:before{background:" onA "}"
            . ".check input:checked+.box{background:" hex ";border-color:" hex ";color:" onA "}"
            . ".radio input:checked+.ring{border-color:" hex "}"
            . ".textbox input:focus,.textbox textarea:focus,.numberbox.focus input,.searchbox input:focus,.dropdown.open .dd-value{border-bottom-color:" hex "}"
            . ".textbox input:focus,.textbox textarea:focus,.numberbox.focus input,.searchbox input:focus{border-bottom-width:2px}"
            . "input[type=range]::-ms-fill-lower{background:" hex "}"
            . "input[type=range]::-ms-thumb{background:" hex "}"
            . ".tab.active:after,.nav-item.active:before,.list-item.selected:before,.dd-item.selected:before,.pivot .tab.active:after{background:" hex "}"
            . ".progress .bar,.progress.indeterminate .bar{background:" hex "}"
            . ".swatch.selected{border-color:" hex "}"
            . "a,.link,.hyperlink{color:" hex "}"
            . ".badge.accent{background:" hex ";color:" onA "}"
            . ".infobar.accent{background:" soft "}"
            . ".card.hot{border-color:" hex "}"
            . ".chip.on{background:" hex ";border-color:" hex ";color:" onA "}"
            . ".axctx-item:hover .axctx-kbd{color:inherit}"
            . ".rating .star.on{color:" hex "}"
            . ".segmented .seg.active{background:" hex ";color:" onA "}"
            . ".drag-ghost{border-color:" hex "}"
            . ".dropzone.dragover{border-color:" hex ";background:" soft "}"
            . ".dropzone.dragover .dz-ico{color:" hex "}"
            . ".imgbox.button:hover,.thumb:hover{border-color:" hex "}"
        ; light: the sheet's "body.theme-light .btn" / ".chip" outrank a bare
        ; ".btn.accent", which left accent buttons and picked chips white.
        ; "body " is just enough: a sheet's own "body.sheet-x .btn.accent" still wins
        if light
            css := AxWindow._Scoped(css, "body ")
        tint := this.Tint
        if (tint = "accent")
            tint := hex
        if (tint != "") {
            ; selectors are prefixed with the body theme class so they outrank
            ; win11.css's own "body.theme-light .card" style rules
            st := this.TintStrength
            b := light ? "body.theme-light" : "body"
            pre := b " "
            bg := AxWindow._Mix(light ? "#f3f3f3" : "#202020", tint, st)
            css .= b "," pre ".group>.legend," pre "#axDlgBtns{background:" bg "}"
            if light {
                c1 := AxWindow._Mix("#fbfbfb", tint, st * 0.6), c2 := AxWindow._Mix("#f9f9f9", tint, st * 0.6)
                css .= pre ".card," pre ".expander," pre ".tile," pre ".sort-list .drag-item," pre ".dd-value," pre ".btn," pre ".list," pre ".hex,"
                    .  pre ".textbox input," pre ".textbox textarea," pre ".searchbox input," pre ".numberbox input," pre ".passwordbox input{background:" c1 "}"
                    .  pre ".dd-menu," pre "#axCtx," pre "#axDlg," pre "#axToast," pre "#axTip{background:" c2 "}"
            } else {
                css .= pre ".dd-menu," pre "#axCtx," pre "#axToast," pre "#axTip{background:" AxWindow._Mix("#2c2c2c", tint, st) "}"
                    .  pre "#axDlg{background:" AxWindow._Mix("#2b2b2b", tint, st) "}"
            }
        }
        css .= this._SheetCss(hex, onA, light)        ; whatever the stylesheet adds
        doc := this.Doc
        try {
            st := doc.getElementById("axAccentCss")
            if !IsObject(st) {
                st := doc.createElement("style")
                st.id := "axAccentCss"
                st.type := "text/css"
                doc.getElementsByTagName("head").item(0).appendChild(st)
                AxWindow._DropKey(this._cssNow, "axAccentCss")
            }
            this._PutCss(st, "axAccentCss", css)      ; reuse the element: replacing it is ignored by Trident
        }
    }
    ; "a,b{...}c{...}" -> "pre a,pre b{...}pre c{...}" (flat rules only)
    static _Scoped(css, pre) {
        out := ""
        for rule in StrSplit(css, "}") {
            if (i := InStr(rule, "{")) {
                sels := ""
                for s in StrSplit(SubStr(rule, 1, i - 1), ",")
                    sels .= (sels = "" ? "" : ",") pre Trim(s)
                out .= sels SubStr(rule, i) "}"
            }
        }
        return out
    }
    ; Trident: a <style> created at runtime only takes effect through
    ; styleSheet.cssText once it is in the document (text nodes are ignored
    ; in documents produced by document.write); fall back to a text node.
    static _SetStyleText(st, css) {
        try {
            st.styleSheet.cssText := css
            if (st.styleSheet.cssText != "")
                return
        }
        try {
            while IsObject(st.firstChild)
                st.removeChild(st.firstChild)
            st.appendChild(st.ownerDocument.createTextNode(css))
        }
    }
    static _Luma(hex) => AxSys.Luma(hex)
    ; Map.Delete throws on a key that is not there
    static _DropKey(map, key) {
        if map.Has(key)
            map.Delete(key)
    }
    static _Mix(a, b, t) => AxSys.Mix(a, b, t)
    static _Rgba(hex, a) => AxSys.Rgba(hex, a)
    static _Attr(el, name) {
        try {
            v := el.getAttribute(name)
            if IsObject(v) || (v = "null")
                return ""
            return v
        }
        return ""
    }
    ; --- DOM event router --------------------------------------------------
    _Dispatch(type) {
        if this.Closing || !IsObject(this.Doc)
            return
        try ev := this.Doc.parentWindow.event
        catch
            return
        if !IsObject(ev)
            return
        try el := ev.srcElement
        catch
            return
        if (type = "keydown" && this._OnKeyDown(ev))
            return
        if (type = "mouseover") {
            this._TipOver(el), this._acHover := el
            this._PopOver(el)
            if this._ctxOpen
                this._CtxHover(el)
        }
        else if (type = "mouseout")
            this._TipOut(ev), this._PopOut(el)
        else if (type = "mousedown" || type = "keydown")
            this._HideTip(true)
        if (type = "mousedown" && this._ctxOpen && !this._InAnyMenu(el))
            this.CloseContextMenu()
        ; A click on the open popover's own anchor is left alone: the toggle
        ; below turns it off, and closing here first would only reopen it.
        if (type = "mousedown" && this._popOpen != "" && !this._InPopover(el)
            && this._PopAnchor(el) != this._popOpen)
            this.ClosePopover()
        if (type = "click" && this._pop.Count && !this._InPopover(el)) {
            a := this._PopAnchor(el)
            if (a != "" && this._pop[a].On = "click")
                this.TogglePopover(a)
        }
        if (type = "mousemove") {
            this._DragMove(ev)
            this._SliderPoll()
            return
        }
        if (type = "mouseup") {
            this._DragUp(ev)
            this._SliderPoll()
            this._slActive := ""
        }
        if (type = "mousedown") {
            sl := this._RoleAncestor(el, "slider")
            if sl {
                this._slActive := sl
                this._slLast := sl.querySelector("input").value
            }
        }
        if (type = "keyup" && sl := this._RoleAncestor(el, "slider")) {
            this._slActive := sl
            this._SliderPoll()
            this._slActive := ""
        }
        if (type = "mousedown" && IsObject(this._ihkBox)) {   ; click outside the hotkey box ends recording
            try inside := this._HasAncestorUid(el, this._ihkBox.uniqueID)
            catch
                inside := false
            if !inside
                this._HotkeyCapture("")
        }
        if (type = "mousedown" && IsObject(this._ddOpen)) {
            try inside := this._HasAncestorUid(el, this._ddOpen.uniqueID)
            catch
                inside := false
            ; a press on the popup's native scrollbar reports the document as
            ; its source element: judge by position as well
            if !inside
                try inside := this._PointIn(this._ddOpen, ev.clientX, ev.clientY) || this._PointIn(this._ddOpen.querySelector(".dd-menu"), ev.clientX, ev.clientY)
            if !inside
                this._CloseDropdown()
            else if (r := this._ClosestRole(el)) && r.role = "dd-item" && (ac := this._RoleAncestor(r.el, "autocomplete")) {
                ; autocomplete: pick on mousedown, before the input loses focus
                this._acDown := false
                this._AcPick(ac, r.el)
                try ev.returnValue := false
                return
            } else if (ac := this._RoleAncestor(el, "autocomplete")) && el.tagName != "INPUT" {
                ; press on the list or its scrollbar: keep the caret in the box
                ; (cancelling mousedown stops the focus change; the native
                ; scrollbar still drags), so nothing closes the list
                this._acDown := true
                try ev.returnValue := false
                return
            }
        }

        ; modal dialog: only its own controls receive events
        if this._dlg {
            if !this._IsInside(el, "axDlg")
                return
            if (type = "click") {
                hit := this._Closest(el, (id) => InStr(id, "axDlgBtn") = 1)
                if hit
                    this._EndDialog(Integer(SubStr(hit.id, 9)))
                else if this._Closest(el, (id) => id = "axDlgClose")
                    this._EndDialog(this._dlg.Cancel)       ; the corner x answers as Escape does
            }
            return
        }
        ; open html context menu: route clicks to its items
        if (type = "click" && this._ctxOpen) {
            hit := this._Closest(el, (id) => this._ctxItems.Has(id))
            if hit {
                this._CtxClick(hit.id, ev)
                return
            }
        }
        if (type = "mousedown") {
            this._DragDown(el, ev)
            ; pressed look: Trident does not reliably apply :active on a
            ; single click, so the class is set here and cleared on mouseup
            if AxWindow._IsLeft(ev) {
                pb := this._ClosestClass(el, "btn")
                for c in ["axdlg-btn", "winbtn", "axtb-item", "seg", "tab", "spin", "chip", "imgbox"]
                    if !pb
                        pb := this._ClosestClass(el, c)
                if pb {
                    AxWindow._SetClass(pb, "pressed", true)
                    this._pressed := pb
                }
            }
        }
        if (type = "mouseup" || type = "mouseout")
            this._Unpress()
        if (type = "focusin" || type = "focusout")
            this._TbFocusMark(el, type = "focusin")
        if (type = "click" || type = "change" || type = "focusin" || type = "focusout" || type = "keydown" || type = "keyup")
            this._Components(type, el, ev)
        if !this.Hooks.Has(type)
            return
        hooks := this.Hooks[type]
        hit := this._Closest(el, (id) => hooks.Has(id))
        if hit
            hooks[hit.id].Call(hit, ev)
        else if hooks.Has("*")                       ; wildcard: page-wide handler (e.g. keyboard input)
            hooks["*"].Call(el, ev)
    }
    ; Trident's own accelerators. The control is a browser, so Ctrl+F opens a
    ; find bar over the page, Ctrl+L and Ctrl+O offer to load a different
    ; document, Ctrl+P prints it, Ctrl+S saves it, and F5 (or Ctrl+R) reloads
    ; the URL -- which in a window whose page was written into the document
    ; means the stylesheet, the frame and every handler are simply gone.
    ;
    ; The default action is cancelled, but the event is NOT swallowed: it goes
    ; on to the page's own handlers, so an app is still free to bind Ctrl+F to
    ; its own search box (example/Todo.ahk does) or F5 to its own refresh. Only
    ; the browser's meaning of the key is taken away.
    static BrowserKeys := Map(70, "find", 76, "open", 79, "open",
                              80, "print", 82, "refresh", 83, "save")
    _BlockBrowserKey(ev) {
        try {
            k := ev.keyCode
            if (k = 116 || (ev.ctrlKey && AxWindow.BrowserKeys.Has(k)))
                ev.returnValue := false
        }
    }
    _OnKeyDown(ev) {
        this._BlockBrowserKey(ev)
        key := ev.keyCode
        ; an open menu owns the keyboard, then the menu bar, then the page
        if (this._ctxOpen && this._CtxKey(ev)) {
            ev.returnValue := false
            return true
        }
        if this._MbKeyDown(ev) {
            ev.returnValue := false
            return true
        }
        if (key = 27) {                              ; Escape
            if (this._popOpen != "") {
                this.ClosePopover()
                return true
            }
            if IsObject(this._ddOpen) {
                this._CloseDropdown()
                return true
            }
            if this._ctxOpen {
                this.CloseContextMenu()
                return true
            }
            if this._dlg {
                this._EndDialog(this._dlg.Cancel)
                return true
            }
            if this.EscapeCloses {
                this.Close(false, "escape")
                return true
            }
        }
        if this._dlg {                               ; a dialog has the keyboard: arrows, Tab, Enter, Space
            if this._DlgKey(ev) {
                ev.returnValue := false
                return true
            }
            return false
        }
        return false
    }
    ; attachEvent -> _Dispatch; returns VT_BOOL false when a handler cancelled
    ; the event (ev.returnValue := false), which is what Trident honours
    _AttachedDispatch(type) {
        this._Dispatch(type)
        allow := true
        try {
            ev := this.Doc.parentWindow.event
            if (IsObject(ev) && ev.returnValue = 0)
                allow := false
        }
        return ComValue(0xB, allow ? -1 : 0)
    }
    ; WM_MOUSEWHEEL from the subclassed host windows: a wheel over a popup or a
    ; scrollable box scrolls that box only; at its ends nothing leaks into the
    ; page behind it. Returns true when the message must be swallowed.
    _PointIn(el, x, y) {
        if !IsObject(el)
            return false
        r := el.getBoundingClientRect()
        return x >= r.left && x < r.right && y >= r.top && y < r.bottom
    }
    _WheelMsg(wParam, lParam) {
        if !IsObject(this.Doc)
            return false
        try {
            delta := (wParam >> 16) & 0xFFFF, delta := delta > 0x7FFF ? delta - 0x10000 : delta
            x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
            x := x > 0x7FFF ? x - 0x10000 : x, y := y > 0x7FFF ? y - 0x10000 : y
            pt := Buffer(8), NumPut("Int", x, "Int", y, pt)
            DllCall("ScreenToClient", "Ptr", this.Gui.Hwnd, "Ptr", pt)
            scale := A_ScreenDPI / 96
            el := this.Doc.elementFromPoint(NumGet(pt, 0, "Int") / scale, NumGet(pt, 4, "Int") / scale)
            box := "", popup := false
            loop 16 {
                if !IsObject(el)
                    break
                cls := " " el.className " "
                if (el.id = "axCtx" || InStr(cls, " dd-menu ") || InStr(cls, " ac-menu ")) {
                    box := el, popup := true
                    break
                }
                if (InStr(cls, " list ") || InStr(cls, " console ") || InStr(cls, " sort-list ")) {
                    box := el
                    break
                }
                el := el.parentElement
            }
            if !IsObject(box)
                return false
            before := box.scrollTop
            box.scrollTop := before + Round(-delta / 120 * 48)
            return popup || box.scrollTop != before      ; a list passes the wheel on only when it could not scroll
        }
        return false
    }
    _KeyPressHandler() {
        allow := true
        try {
            ev := this.Doc.parentWindow.event
            el := ev.srcElement
            if this._RoleAncestor(el, "numberbox") {
                c := ev.keyCode
                if (c >= 32)
                    allow := (c >= 48 && c <= 57) || c = 46 || c = 45   ; 0-9 . -
            }
        }
        return ComValue(0xB, allow ? -1 : 0)
    }
    ; Only a text field may start a drag; everywhere else the page is chrome,
    ; not content, so dragging it out makes no sense.
    _DragStartHandler() {
        allow := false
        try {
            ev := this.Doc.parentWindow.event
            el := ev.srcElement
            tag := el.tagName
            allow := (tag = "INPUT" || tag = "TEXTAREA" || el.isContentEditable)
        }
        return ComValue(0xB, allow ? -1 : 0)
    }
    _SelectStartHandler() {
        allow := false
        try {
            ev := this.Doc.parentWindow.event
            el := ev.srcElement
            tag := el.tagName
            if (tag = "INPUT" || tag = "TEXTAREA" || el.isContentEditable)
                allow := true
            else {
                loop 24 {
                    if !IsObject(el)
                        break
                    if (AxWindow._Attr(el, "data-selectable") != "") {
                        allow := true
                        break
                    }
                    try el := el.parentElement
                    catch
                        break
                }
            }
        }
        return ComValue(0xB, allow ? -1 : 0)
    }
    _Closest(el, pred) {
        loop 16 {
            if !IsObject(el)
                return ""
            try id := el.id
            catch
                id := ""
            if (id != "" && pred(id))
                return el
            el := AxWindow._ParentEl(el)
        }
        return ""
    }
    _IsInside(el, id) => this._Closest(el, (i) => i = id) != ""
    ; --- window plumbing ---------------------------------------------------
    ; snapped (Win11 "arranged") or maximized: edges touch the screen, so the
    ; DWM border reads as a stray line there
    IsSnapped() {
        if this.IsMaximized()
            return true
        if AxSys.IsArranged(this.Gui.Hwnd)
            return true
        ; fallback: window flush with a work-area edge
        try {
            WinGetPos(&x, &y, &w, &h, this.Gui)
            MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
            return (x = l || y = t || x + w = r || y + h = b)
        }
        return false
    }
    _UpdateBorder() {
        AxSys.Border(this.Gui.Hwnd, this.IsSnapped() ? this.SnapBorder : this.BorderColor)
    }
    _OnSize(mm, w, h) {
        if this.Closing || mm = -1
            return
        this._UpdateBorder()
        try this.Ax.Move(, , w, h)
        this._LayoutEmbeds()
        this.CloseContextMenu()
        this._CloseDropdown()
        this._HideTip(true)
        this._DragUp("")
        this.BodyClass("maximized", mm = 1)
        this._UpdateMaxRect()
    }
    _OnEscape() {
        if this._dlg
            this._EndDialog(this._dlg.Cancel)
        else if (this._popOpen != "")
            this.ClosePopover()
        else if this._ctxOpen
            this.CloseContextMenu()
        else if this.EscapeCloses
            this.Close(false, "escape")
    }
    _OnMsg(w, l, msg, hwnd) {
        if this.Closing
            return
        switch msg {
        case 0x313:                                      ; WM_POPUPSYSTEMMENU
            if this._menuWaits                           ; closing: a click's menu arriving late is not opened
                return 0
        case 0x83:                                       ; WM_NCCALCSIZE: client = whole window
            if w
                return 0
        case 0x24:                                       ; WM_GETMINMAXINFO
            return this._MinMaxInfo(l, hwnd)
        case 0x86:                                       ; WM_NCACTIVATE: skip frame repaint
            this.BodyClass("inactive", !w)
            if !w {
                this.CloseContextMenu()
                this._HideTip(true)
                this._HotkeyCapture("")
                this._MbBlur()                       ; an Alt-revealed bar hides again
            }
            return 1
        case 0x84:                                       ; WM_NCHITTEST
            if this._InMaxRect(l)
                return 9                                 ; HTMAXBUTTON -> Snap Layouts flyout
        case 0xA0:                                       ; WM_NCMOUSEMOVE
            if (w = 9 && !this._maxHover) {
                this._maxHover := true
                try this.AddClass(this.Chrome.Max, "hover")
                SetTimer(this._snapPollFn, 60)
            }
        case 0xA1, 0xA3:                                 ; WM_NCLBUTTONDOWN / DBLCLK on the button
            if (w = 9)
                return 0
        case 0xA2:                                       ; WM_NCLBUTTONUP
            if (w = 9) {
                this.ToggleMaximize()
                return 0
            }
        case 0xA4, 0xA5:                                 ; right button on the button: ignore
            if (w = 9)
                return 0
        case 0x233:                                      ; WM_DROPFILES (only if RegisterDragDrop failed)
            return this._OnDropFiles(w)
        case 0x100, 0x104, 0x105:                        ; keys that land on the frame itself,
            if this._MenuKey(msg, w)                     ; not on the browser child
                return 0
        }
    }
    _MinMaxInfo(lParam, hwnd) {
        hMon := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
        if !hMon
            return
        mi := Buffer(40, 0), NumPut("UInt", 40, mi, 0)
        if !DllCall("GetMonitorInfoW", "Ptr", hMon, "Ptr", mi)
            return
        monLeft := NumGet(mi, 4, "Int"),  monTop := NumGet(mi, 8, "Int")
        wkLeft := NumGet(mi, 20, "Int"), wkTop := NumGet(mi, 24, "Int")
        wkW := NumGet(mi, 28, "Int") - wkLeft, wkH := NumGet(mi, 32, "Int") - wkTop
        k := A_ScreenDPI / 96
        NumPut("Int", wkW, lParam, 8), NumPut("Int", wkH, lParam, 12)                         ; ptMaxSize
        NumPut("Int", wkLeft - monLeft, lParam, 16), NumPut("Int", wkTop - monTop, lParam, 20) ; ptMaxPosition (monitor-relative)
        NumPut("Int", Round(this.MinWidth * k), lParam, 24), NumPut("Int", Round(this.MinHeight * k), lParam, 28) ; ptMinTrackSize
        NumPut("Int", wkW, lParam, 32), NumPut("Int", wkH, lParam, 36)                        ; ptMaxTrackSize
        return 0
    }
    ; --- window subclassing ------------------------------------------------
    ; The ActiveX host and IE's inner windows are subclassed for two things:
    ;  * WM_ERASEBKGND is swallowed so a fast resize never flashes white.
    ;  * Snap Layouts: Windows 11 shows the flyout when the TOP-LEVEL window
    ; answers WM_NCHITTEST with HTMAXBUTTON. The ActiveX control and IE's
    ; inner windows own every pixel, so they are subclassed to answer
    ; HTTRANSPARENT inside the maximize button's rectangle, which makes
    ; Windows keep asking up the parent chain until our window replies.
    ; Hover is mirrored to the HTML button as class "hover".
    _InstallSubclasses() {
        list := []
        enumCb := CallbackCreate((h, l) => (list.Push(h), 1), "F", 2)
        DllCall("EnumChildWindows", "Ptr", this.Gui.Hwnd, "Ptr", enumCb, "Ptr", 0)
        CallbackFree(enumCb)
        for h in list {
            if this._subclassed.Has(h)
                continue
            if DllCall("comctl32\SetWindowSubclass", "Ptr", h, "Ptr", AxWindow._SubclassCb(), "Ptr", 1, "Ptr", this.Gui.Hwnd)
                this._subclassed[h] := true
        }
        this.SetBackColor(this.BackColor)             ; kill the white class brushes
    }
    static _SubclassCb() {
        static cb := CallbackCreate(ObjBindMethod(AxWindow, "_SubclassProc"), "F", 6)
        return cb
    }
    static _SubclassProc(hWnd, uMsg, wParam, lParam, uId, refData) {
        if (uMsg = 0x14)                                     ; WM_ERASEBKGND: never paint white
            return 1
        if (uMsg = 0x87)                                     ; WM_GETDLGCODE: keep arrows/Tab/chars away from
            return 0x87                                      ; the Gui's IsDialogMessage (WANTALLKEYS|ARROWS|TAB|CHARS)
        ; zoom lock: Ctrl+wheel, Ctrl + / - / 0 (main and numpad), and pinch
        ; (WM_GESTURE) never reach Trident unless AllowZoom is set
        if (AxWindow._byHwnd.Has(refData) && !AxWindow._byHwnd[refData].AllowZoom) {
            if (uMsg = 0x20A && (wParam & 0x8))                 ; WM_MOUSEWHEEL with MK_CONTROL
                return 0
            if ((uMsg = 0x100 || uMsg = 0x104) && GetKeyState("Ctrl", "P")
                && (wParam = 187 || wParam = 189 || wParam = 107 || wParam = 109 || wParam = 48 || wParam = 96))
                return 0
            if (uMsg = 0x119)                                   ; WM_GESTURE (pinch/zoom)
                return 0
        }
        if (uMsg = 0x20A && AxWindow._byHwnd.Has(refData) && AxWindow._byHwnd[refData]._WheelMsg(wParam, lParam))
            return 0                                             ; wheel consumed by a popup / scrollable box
        ; Alt, Alt+letter and F10 belong to the menu bar when there is one
        if ((uMsg = 0x104 || uMsg = 0x105 || uMsg = 0x100) && AxWindow._byHwnd.Has(refData)
            && AxWindow._byHwnd[refData]._MenuKey(uMsg, wParam))
            return 0
        ; WM_KEYDOWN..WM_SYSDEADCHAR: Trident only raises DOM key events (and
        ; handles Tab/accelerators) when the host feeds key messages through
        ; IOleInPlaceActiveObject::TranslateAccelerator. AHK's ActiveX host
        ; does not, so do it here; S_OK means the browser consumed it.
        ; A key that arrives while the one before is still with Trident (the
        ; script checks its messages while it runs a handler for that one)
        ; waits its turn: let straight through, Trident would take it as it
        ; comes -- no key events for the page, and a Tab that moves the focus
        ; out of the box being typed in.
        if (uMsg >= 0x100 && uMsg <= 0x109 && AxWindow._byHwnd.Has(refData)) {
            if (AxWindow._rawKey && AxWindow._rawKey = hWnd "|" uMsg "|" wParam "|" lParam) {
                AxWindow._rawKey := false                    ; a waiting key, on its way to Trident itself
                return DllCall("comctl32\DefSubclassProc", "Ptr", hWnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
            }
            if AxWindow._keyBusy {
                AxWindow._keyQ.Push([hWnd, uMsg, wParam, lParam, refData])
                return 0
            }
            if AxWindow._TranslateKey(AxWindow._byHwnd[refData], hWnd, uMsg, wParam, lParam)
                return AxWindow._KeyQueue()
            AxWindow._keyBusy := true
            try r := DllCall("comctl32\DefSubclassProc", "Ptr", hWnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
            AxWindow._keyBusy := false
            AxWindow._KeyQueue()
            return IsSet(r) ? r : 0
        }
        if (uMsg = 0x84 && AxWindow._byHwnd.Has(refData) && AxWindow._byHwnd[refData]._InMaxRect(lParam)
            && AxWindow._byHwnd[refData].SnapLayouts)
            return -1                                        ; HTTRANSPARENT
        return DllCall("comctl32\DefSubclassProc", "Ptr", hWnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
    static _keyBusy := false, _rawKey := false, _keyQ := []
    ; the keys that waited, in the order they came: each to Trident's
    ; accelerators, and what they leave to its window procedure (a typed
    ; character) sent there straight
    static _KeyQueue() {
        while (AxWindow._keyQ.Length && !AxWindow._keyBusy) {
            ; Both _TranslateKey and SendMessageW below pump messages, and an
            ; AHK timer can interrupt between any two statements, so the queue
            ; can be drained by a re-entrant call between the test above and
            ; the removal here. RemoveAt(1) on an empty array throws.
            q := ""
            try q := AxWindow._keyQ.RemoveAt(1)
            if !IsObject(q)
                break
            if !AxWindow._byHwnd.Has(q[5]) || !DllCall("IsWindow", "Ptr", q[1])
                continue
            if AxWindow._TranslateKey(AxWindow._byHwnd[q[5]], q[1], q[2], q[3], q[4])
                continue
            AxWindow._keyBusy := true, AxWindow._rawKey := q[1] "|" q[2] "|" q[3] "|" q[4]
            try DllCall("SendMessageW", "Ptr", q[1], "UInt", q[2], "Ptr", q[3], "Ptr", q[4], "Ptr")
            AxWindow._rawKey := false, AxWindow._keyBusy := false
        }
        return 0
    }
    static _TranslateKey(inst, hWnd, uMsg, wParam, lParam) {
        if AxWindow._keyBusy || !IsObject(inst._activeObj)
            return false
        AxWindow._keyBusy := true
        hr := 1
        try {
            msg := Buffer(A_PtrSize = 8 ? 48 : 28, 0)          ; MSG
            NumPut("Ptr", hWnd, msg, 0)
            NumPut("UInt", uMsg, msg, A_PtrSize)
            NumPut("Ptr", wParam, msg, 2 * A_PtrSize)
            NumPut("Ptr", lParam, msg, 3 * A_PtrSize)
            NumPut("UInt", A_TickCount, msg, 4 * A_PtrSize)
            p := inst._activeObj.Ptr
            hr := DllCall(NumGet(NumGet(p, 0, "Ptr") + 5 * A_PtrSize, "Ptr"), "Ptr", p, "Ptr", msg, "Int")
        }
        AxWindow._keyBusy := false
        return (hr = 0)
    }
    ; getBoundingClientRect and clientWidth both force Trident to lay the page
    ; out, and this used to run three times during startup -- twice from
    ; SetTheme, right after a fresh stylesheet had dirtied every box on the
    ; page. Nothing reads _maxRect until the pointer reaches the non-client
    ; area, so invalidate here and measure there.
    _UpdateMaxRect() {
        this._maxRect := ""
        this._maxRectDirty := true
    }
    _ComputeMaxRect() {
        this._maxRect := "", this._maxRectDirty := false
        if !IsObject(this.Doc) || this.Closing || !this.SnapLayouts || !this.MaximizeBox
            return
        try {
            r := this.El(this.Chrome.Max).getBoundingClientRect()
            rc := Buffer(16, 0)
            DllCall("GetClientRect", "Ptr", this.Ax.Hwnd, "Ptr", rc)
            k := NumGet(rc, 8, "Int") / this.Doc.documentElement.clientWidth   ; CSS px -> device px
            l := Round(r.left * k), t := Round(r.top * k), rt := Round(r.right * k), b := Round(r.bottom * k)
            if (rt > l && b > t)
                this._maxRect := {L: l, T: t, R: rt, B: b}
        }
    }
    ; lParam = packed screen coords (as delivered by WM_NCHITTEST)
    _InMaxRect(lParam) {
        if this.Closing
            return false
        if this._maxRectDirty
            this._ComputeMaxRect()          ; measured once, then reused until invalidated
        rc := this._maxRect
        if !rc
            return false
        pt := Buffer(8, 0)
        NumPut("Int", (lParam << 48) >> 48, pt, 0)
        NumPut("Int", (lParam << 32) >> 48, pt, 4)
        DllCall("ScreenToClient", "Ptr", this.Gui.Hwnd, "Ptr", pt)
        x := NumGet(pt, 0, "Int"), y := NumGet(pt, 4, "Int")
        return (x >= rc.L && x < rc.R && y >= rc.T && y < rc.B)
    }
    _SnapPoll() {
        if this.Closing
            return
        pt := Buffer(8, 0)
        DllCall("GetCursorPos", "Ptr", pt)
        packed := (NumGet(pt, 4, "Int") << 16) | (NumGet(pt, 0, "Int") & 0xFFFF)
        if !this._InMaxRect(packed) {
            this._maxHover := false
            SetTimer(this._snapPollFn, 0)
            try this.RemoveClass(this.Chrome.Max, "hover")
        }
    }
    ; --- statics -----------------------------------------------------------
    static _HookMessages() {
        if AxWindow._hooked
            return
        AxWindow._hooked := true
        route := ObjBindMethod(AxWindow, "_Route")
        for msg in [0x83, 0x24, 0x86, 0x84, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x233,
                    0x100, 0x104, 0x105, 0x313]
            OnMessage(msg, route)
    }
    static _Route(w, l, msg, hwnd) {
        if AxWindow._byHwnd.Has(hwnd)
            return AxWindow._byHwnd[hwnd]._OnMsg(w, l, msg, hwnd)
    }
    static _Esc(s) => StrReplace(StrReplace(StrReplace(StrReplace(String(s), "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), '"', "&quot;")
    ; Write plain text into an element. Trident's innerText setter costs about
    ; five times its innerHTML setter for the same result, so single-line text
    ; is escaped and written as markup. Anything carrying a line break keeps the
    ; old path: innerText has its own line-break behaviour and matching it
    ; exactly is not worth the microseconds.
    static _SetText(el, text) {
        s := String(text)
        if (!InStr(s, "`n") && !InStr(s, "`r"))
            try {
                el.innerHTML := AxWindow._Esc(s)
                return
            }
        try el.innerText := text
    }
    ; className is a plain string on HTML elements but a read-only
    ; SVGAnimatedString on SVG ones, so the class attribute is the fallback:
    ; every class helper in the library works on inline SVG shapes too.
    ; _ClassGet reads the list once and reports whether className itself can be
    ; written. Taking that probe out of the write is what lets _SetClass touch
    ; the DOM twice instead of four times: it used to read the list in
    ; _HasClass, read it again in _ClassOf, and _WriteClass read className a
    ; third time just to find out which way to write.
    static _ClassGet(el, &plain) {
        plain := false
        try {
            c := el.className
            if !IsObject(c) {
                plain := true
                return c
            }
        }
        try {
            c := el.getAttribute("class")
            if (!IsObject(c) && c != "null")
                return c
        }
        return ""
    }
    static _ClassPut(el, value, plain) {
        if plain {
            try {
                el.className := value
                return
            }
        }
        try el.setAttribute("class", value)
    }
    static _ClassOf(el) {
        plain := false
        return AxWindow._ClassGet(el, &plain)
    }
    static _WriteClass(el, value) {
        plain := false
        AxWindow._ClassGet(el, &plain)
        AxWindow._ClassPut(el, value, plain)
    }
    ; Class names are case sensitive, hence InStr's third argument: a padded
    ; substring test is exactly what the regex was doing, for a fraction of it.
    ;
    ; These two read className inline rather than through _ClassGet. An
    ; AutoHotkey call frame costs the better part of a microsecond, which is
    ; most of what a DOM property read costs, and these are the hottest
    ; helpers in the library -- _SetClass alone has over a hundred call sites.
    ; Inline SVG (where className is a read-only SVGAnimatedString) falls
    ; through to _ClassGet, so the fallback still lives in exactly one place.
    static _HasClass(el, cls) {
        if (cls = "")
            return false
        try {
            c := el.className
            if !IsObject(c)
                return InStr(" " c " ", " " cls " ", true) > 0
        }
        plain := false
        try return InStr(" " AxWindow._ClassGet(el, &plain) " ", " " cls " ", true) > 0
        return false
    }
    ; on omitted means toggle, so ToggleClass needs only the one read too.
    static _SetClass(el, cls, on?) {
        if (!IsObject(el) || cls = "")
            return
        plain := true
        try cur := el.className
        if (!IsSet(cur) || IsObject(cur))
            cur := AxWindow._ClassGet(el, &plain)
        pad := " " cur " ", n := StrLen(cls)
        at := InStr(pad, " " cls " ", true)
        want := IsSet(on) ? (on ? 1 : 0) : (at ? 0 : 1)
        if (want = (at ? 1 : 0))
            return                                   ; already as asked: no write
        if want
            nw := Trim(cur " " cls)
        else {
            while (at := InStr(pad, " " cls " ", true))
                pad := SubStr(pad, 1, at) SubStr(pad, at + n + 2)
            nw := Trim(pad)
        }
        if plain {
            try {
                el.className := nw
                return
            }
        }
        try el.setAttribute("class", nw)
    }
    ; parentElement is missing on some SVG nodes in Trident: fall back to
    ; parentNode so the "closest ancestor" helpers keep walking.
    static _ParentEl(el) {
        try {
            p := el.parentElement
            if IsObject(p)
                return p
        }
        try {
            p := el.parentNode
            if (IsObject(p) && p.nodeType = 1)
                return p
        }
        return ""
    }

    ; --- COM event sinks ---------------------------------------------------
    ; Trident's document events pass NO parameters; the event object is only
    ; reachable through document.parentWindow.event (read in _Dispatch).
    class BrowserSink {
        __New(owner) {
            this.owner := owner
        }
        DocumentComplete(*) => this.owner._OnDocComplete()
    }
    class DocSink {
        __New(owner) {
            this.owner := owner
        }
        onclick(*)       => this.owner._Dispatch("click")
        ondblclick(*)    => this.owner._Dispatch("dblclick")
        onmousedown(*)   => this.owner._Dispatch("mousedown")
        onmouseup(*)     => this.owner._Dispatch("mouseup")
        onmousemove(*)   => (this.owner._drag || this.owner._slActive) ? this.owner._Dispatch("mousemove") : ""
        onmouseover(*)   => this.owner._Dispatch("mouseover")
        onmouseout(*)    => this.owner._Dispatch("mouseout")
        onchange(*)      => this.owner._Dispatch("change")
        ; keydown / keyup / focusin / focusout are registered with attachEvent
        ; in _OnDocComplete (the sink never delivers them)
    }
}

; The behaviour mixins live in their own files and are merged into the class
; here. They are included at this point rather than at the top of the file on
; purpose, and AxTags.ahk comes with them: all of them reach back to AxWindow
; for its static helpers, and a file parsed before "class AxWindow" has been
; declared reads that name as an unassigned local -- which is exactly what
; #Warn VarUnset reports. Nothing in any of them runs at load time, so where
; they sit costs nothing else.
#Include %A_LineFile%\..\AxTags.ahk
#Include %A_LineFile%\..\AxWindow.Components.ahk
#Include %A_LineFile%\..\AxWindow.Overlays.ahk
#Include %A_LineFile%\..\AxWindow.Bars.ahk
#Include %A_LineFile%\..\AxWindow.Titlebar.ahk
#Include %A_LineFile%\..\AxWindow.Embed.ahk
#Include %A_LineFile%\..\AxWindow.Media.ahk
#Include %A_LineFile%\..\AxWindow.DragDrop.ahk

AxWindow.Mixin(AxWindowComponents)
AxWindow.Mixin(AxWindowOverlays)
AxWindow.Mixin(AxWindowBars)
AxWindow.Mixin(AxWindowTitlebar)
AxWindow.Mixin(AxWindowEmbed)
AxWindow.Mixin(AxWindowMedia)
AxWindow.Mixin(AxWindowDragDrop)
