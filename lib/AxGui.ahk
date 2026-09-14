#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\AxWindow.ahk

;@Ahk2Exe-IgnoreBegin
; The F12 inspector, for every script that runs as a .ahk -- and left out of
; every compiled exe, where it has no business: it answers F12 in a shipped
; program, patches two prototypes, and brings every component pack with it.
; Ahk2Exe drops everything between these two lines. A build that does want it
; includes lib\dev\AxInspector.ahk itself (the studio's File > Compile has a
; switch that does exactly that).
#Include %A_LineFile%\..\dev\AxInspector.ahk
;@Ahk2Exe-IgnoreEnd


; =============================================================================
;  AxGui.ahk — build an AxWindow window from AutoHotkey alone
;
;  Same shape as the native Gui class: Add* methods with an option string and
;  a text/value argument, controls with OnEvent/Value/Text, UseTab. No HTML,
;  CSS or files are written by you; the page is generated in memory with the
;  Windows 11 stylesheet embedded and loaded straight from the string.
;
;      g := AxGui({Title: "My app", Width: 800, Height: 520, Theme: "system"})
;      g.AddPage("home", "Home", "E80F")
;      g.AddText("", "Profile name:")
;      name := g.AddEdit("vName w260 x+8", "Jane Doe")
;      g.AddButton("vGo Accent", "Save").OnEvent("Click", (ctl, *) => g.Toast("Saved " name.Value))
;      g.AddPage("settings", "Settings", "E713")
;      g.AddSwitch("vDark Checked", "Dark mode").OnEvent("Change", (ctl, v) => g.SetTheme(v ? "dark" : "light"))
;      g.Show()
;
;  Option string (space separated, quotes allowed in values):
;      vName            control id (used for events, Value(), El())
;      wN hN            width / height in px            Fill  -> stretch to the line
;      x+N              stay on the previous line, N px after it (default: new line)
;      y+N              extra top margin                 xN yN -> absolute position in the page
;      Accent Subtle Danger Icon    button kinds         Checked Disabled Hidden ReadOnly
;      ChooseN          preselect the Nth option (DDL / ListBox / Radio / Tab / Segmented)
;      Key=Value        Icon=E713  Tip="..."  Min=0 Max=100 Step=5 Value=..  Placeholder=".."
;                       Suffix="%"  Rows=3  On=On Off=Off  Desc=".."  Colors="#..,#.."  Kind=success
;
;  Containers (return a container; later Adds go into it via UseTab / Use):
;      AddPage(id, title, icon)   AddTab(opts, names)+UseTab(n)   AddRow(opts, title, desc)
;      AddGroupBox(opts, legend)  AddCard(opts, title)  AddExpander(opts, title, desc)  AddGrid(opts)
;  Controls:
;      Text Button Link CheckBox Switch Radio Edit Password Search Number Slider DDL/DropDownList
;      ListBox Progress InfoBar Badge Chip Palette Rating Segmented Hotkey Console Picture Tile Html
;      Image ImageButton Svg DropZone FileList Thumbs
;  Window chrome (not page content, so these go on the Gui, not a container):
;      AddMenuBar(menus, opts)   AddStatusBar(parts, opts)
; =============================================================================
class AxGui extends AxWindow {
    ; the library's release (github.com/owhs/axahk, version.json "axahk")
    static Version := "1.0"
    __New(opts := "") {
        if !IsObject(opts)
            opts := {}
        this._opts := opts
        this._n := 0
        this._pending := []          ; [type, id, fn] applied when the DOM exists
        this._embedPending := []     ; [id, progId] docked ActiveX controls created once the Gui exists
        this._controls := Map()
        this._root := AxGui.Container(this, "", "content")
        this._pages := []
        this._cur := this._root      ; where Add* goes
        this._built := false
        this._early := false         ; Show(): the window comes up once the page and its bars are in
        this.ShowNav := opts.HasOwnProp("Nav") ? opts.Nav : true
        ; base-class state that callers may touch before Show(). The lists
        ; survive the base constructor, and _Wire must be first: the page can
        ; finish loading synchronously inside that constructor.
        this.Ready := false, this.Closing := false
        this._readyCbs := [ObjBindMethod(this, "_Wire")], this._closeCbs := [], this._pageCbs := []
        this.Hooks := Map(), this._valueCbs := Map(), this._ctx := Map()   ; On/OnValue/ContextMenu usable before Show()
    }

    ; ------------------------------------------------------------ building
    ; Use(container) directs later Add* calls there; Use() returns to the
    ; current page (or the root when there are no pages).
    Use(container := "") {
        this._cur := IsObject(container) ? container : (this._pages.Length ? this._pages[-1] : this._root)
        return this
    }
    AddPage(id, title := "", icon := "") {
        p := AxGui.Container(this, "page", id)
        p.Title := title, p.Icon := icon
        this._pages.Push(p)
        this._cur := p
        return p
    }
    ; ---------------------------------------------------------- window bars
    ; The menu bar and the status bar are window chrome rather than page
    ; content, so they are declared on the Gui and rendered outside
    ; <ax-content>: the bar markup goes in the page, the menus and parts are
    ; bound once the DOM exists (see AxWindow.Bars.ahk).
    ;
    ;   g.AddMenuBar([{Title: "&File", Items: [["&New", fn], "-", ["E&xit", fn]]}],
    ;                {Reveal: "alt"})
    ;   g.AddStatusBar([{Id: "msg", Text: "Ready", Grow: true}, {Id: "pos", Text: ""}])
    AddMenuBar(menus, opts := "") {
        this._menubar := {Menus: menus, Opts: opts}
        if this.Ready
            this.MenuBar("axMenuBar", menus, opts)
        return this
    }
    AddStatusBar(parts, opts := "") {
        this._statusbar := {Parts: parts, Opts: opts}
        if this.Ready
            this.StatusBar("axStatusBar", parts, opts)
        return this
    }
    ; Things of your own in the title bar: a burger, a glyph, a word, an SVG,
    ; a picture -- each able to run a function, drop a menu or open a popover.
    ; See AxWindow.Titlebar.ahk for the item fields.
    ;
    ;   g.AddTitleBar([{Id: "menu", Kind: "burger", Click: (*) => Toggle()},
    ;                  {Id: "brand", Text: "Notes"}], {ShowTitle: false})
    AddTitleBar(items, opts := "") {
        this._titlebar := {Items: items, Opts: opts}
        if this.Ready
            this.TitleBar(items, opts)
        return this
    }
    ; every other Add* is forwarded to the current container
    __Call(name, args) {
        if (SubStr(name, 1, 3) = "Add" && this._cur.HasMethod(name))
            return this._cur.%name%(args*)
        throw MethodError("Unknown method: " name, -1)
    }
    Add(type, opts := "", text := "") => this._cur.Add(type, opts, text)
    UseTab(n := 0) => this._cur.UseTab(n)

    ; Stylesheet name ("win11" | "win98" | "winxp" | "aurora" | ...) or a .css path
    ; -> CSS text.
    ;
    ; A sheet may open with "/* @extends win11 */" to say it is a restyle of
    ; another rather than a sheet from nothing: the base is loaded first and
    ; the sheet appended, so it only carries what it actually changes and it
    ; picks up later fixes to the base. Nesting is allowed; a cycle stops.
    static ThemeCss(name, seen := "") {
        if (name = "")
            name := "win11"
        if !IsObject(seen)
            seen := Map()
        css := ""
        if (!InStr(name, ".css") && !InStr(name, "\"))
            css := AxWindow.ReadLib("themes\" name ".css")       ; lib folder or exe resource
        else
            try css := FileRead(name, "UTF-8")
        key := StrLower(String(name))
        if seen.Has(key)
            return css
        seen[key] := true
        if RegExMatch(css, "i)^\s*/\*\s*@extends\s+([A-Za-z0-9_.\-]+)\s*\*/", &m) {
            base := AxGui.ThemeCss(m[1], seen)
            if (base != "")
                css := base "`n" css
        }
        return css
    }
    ; The window colour behind each stylesheet, light and dark.
    static SheetBack := Map("win11",      ["f3f3f3", "202020"],
                            "win98",      ["c0c0c0", "3f3f3f"],
                            "winxp",      ["ece9d8", "3a3a3a"],
                            "win365",     ["f3f2f1", "1b1a19"],
                            "cyber",      ["eceef0", "0e0f11"],
                            "rpg",        ["e8dcc0", "241c14"],
                            "cozy",       ["fdf3ec", "241f22"],
                            "aurora",     ["f5f7fc", "0a0c11"],
                            "instrument", ["edeae4", "1b1a18"],
                            "precision",  ["eceef1", "18191c"],
                            "inset",      ["e8eaee", "1a1c1f"],
                            "brutalist",  ["b9bec6", "222428"])
    ; The accent each stylesheet paints with when none is chosen, light and
    ; dark: what its accent button and its switch are filled with. The
    ; component packs are written in Fluent blue and take this in its place,
    ; so a calendar, a range slider or a tag chip matches the sheet it is on.
    static SheetAccent := Map("win11",      ["#005fb8", "#60cdff"],
                              "win98",      ["#000080", "#000080"],
                              "winxp",      ["#316ac5", "#316ac5"],
                              "win365",     ["#0f6cbd", "#479ef5"],
                              "cyber",      ["#0088a8", "#00d8ff"],
                              "rpg",        ["#d9bd6c", "#d9bd6c"],
                              "cozy",       ["#ff8a5c", "#ff8a5c"],
                              "aurora",     ["#5b8cff", "#5b8cff"],
                              "instrument", ["#9a7434", "#c8a15a"],
                              "precision",  ["#0a7f5c", "#10b981"],
                              "inset",      ["#10b981", "#10b981"],
                              "brutalist",  ["#10b981", "#10b981"])
    DefaultAccent(mode) {
        n := AxGui.SheetName(this.HasOwnProp("Stylesheet") ? this.Stylesheet : "win11")
        pair := AxGui.SheetAccent.Has(n) ? AxGui.SheetAccent[n] : AxGui.SheetAccent["win11"]
        return (mode = "light") ? pair[1] : pair[2]
    }
    ; The surfaces a sheet actually paints on top of that background, when they
    ; are not derived from it. Each entry is [light, dark].
    ;
    ;   Panel   cards, expanders, tiles          Well    fields, lists, menus
    ;   Chrome  the task pane and the two bars (omit when they are background)
    ;
    ; SetTint mixes into these. Without an entry the pair is derived from the
    ; background, which is right for a sheet whose surfaces are shades of it and
    ; wrong for one that lays white paper on a grey canvas: win365's cards came
    ; out darker than the cards themselves, so the lift went out of the window
    ; the moment a tint was set.
    static SheetSurf := Map(
        "win98",  {Panel: ["#c0c0c0", "#3f3f3f"], Well: ["#ffffff", "#232323"]},
        "winxp",  {Panel: ["#ffffff", "#444444"], Well: ["#ffffff", "#262626"]},
        "win365", {Panel: ["#ffffff", "#262524"], Well: ["#ffffff", "#1f1e1d"],
                   Chrome: ["#ffffff", "#201f1e"]})
    ; Sheets that keep the Windows 11 rounded window corner. Everything else is
    ; square: a bevel, a hard rim or a painted band all read wrong with a
    ; rounded DWM corner clipping them.
    static RoundSheets := Map("win11", true, "win365", true)
    static SheetRound(name) {
        if (name = "" || name = "win11")
            return true
        n := AxGui.SheetName(name)                 ; a path resolves to its base name
        return (n != "win11") && AxGui.RoundSheets.Has(n)
    }
    ThemeBack(mode) {
        n := AxGui.SheetName(this.HasOwnProp("Stylesheet") ? this.Stylesheet : "win11")
        c := AxGui.SheetBack.Has(n) ? AxGui.SheetBack[n] : AxGui.SheetBack["win11"]
        return (mode = "light") ? c[1] : c[2]
    }
    ; "win98" out of "win98", "themes\win98.css" or a full path
    static SheetName(name) {
        if (name = "")
            return "win11"
        SplitPath(name, , , , &base)
        n := StrLower(base != "" ? base : name)
        return AxGui.SheetBack.Has(n) ? n : "win11"
    }
    ; --------------------------------------------------------- accent + tint
    ; The retro chrome follows the accent because the sheet itself is re-hued
    ; when it is injected (AxSys.RecolourCss): every blue in it turns to the
    ; accent's hue, keeping its own lightness, so gradients and bevels hold
    ; their shape. That needs no list of selectors and so cannot fall behind
    ; the stylesheets. This hook has only the tint left to do.
    ;
    ; Nothing moves until an accent is actually chosen: at the default the
    ; classic navy and Luna blue stand, and so does any colour scheme a script
    ; layers on with SetExtraCss (example/Retro.ahk).
    _SheetCss(hex, onA, light) {
        n := AxGui.SheetName(this.HasOwnProp("Stylesheet") ? this.Stylesheet : "win11")
        if (n = "win11")
            return ""
        M := (a, b, t) => AxWindow._Mix(a, b, t)
        ; The blue in these sheets is remapped to the accent's hue when the
        ; sheet itself is injected (AxSys.RecolourCss), so there is nothing to
        ; enumerate here -- only the tint, which mixes a colour into the flat
        ; surfaces the way it does on win11.
        css := ""
        b := "body.sheet-" n (light ? ".theme-light" : ".theme-dark")
        tint := this.Tint
        if (tint = "accent")
            tint := hex
        if (tint = "")
            return css
        t := this.TintStrength
        ; the sheet's own background, not a guess: every sheet registers its
        ; light and dark pair in SheetBack, so a new one is tinted correctly
        ; without being added to a list here
        pair := AxGui.SheetBack.Has(n) ? AxGui.SheetBack[n] : AxGui.SheetBack["win11"]
        base := "#" (light ? pair[1] : pair[2])
        i := light ? 1 : 2
        ; A sheet whose surfaces are not made out of its own background says so
        ; in SheetSurf; everything else derives them -- wells sinking away from
        ; the background, panels lifting towards it.
        surf := AxGui.SheetSurf.Has(n) ? AxGui.SheetSurf[n] : ""
        well  := IsObject(surf) ? surf.Well[i]  : M(base, light ? "#ffffff" : "#000000", 0.55)
        panel := IsObject(surf) ? surf.Panel[i] : M(base, light ? "#ffffff" : "#ffffff", 0.06)
        ; Chrome is the rail and the two bars. On most sheets they are the
        ; background, and stay in the group below; a sheet that builds them out
        ; of panel material instead registers that and they follow the panel.
        chrome := (IsObject(surf) && surf.HasOwnProp("Chrome")) ? surf.Chrome[i] : ""
        bg := M(base, tint, t), pn := M(panel, tint, t * 0.8), wl := M(well, tint, t * 0.45)
        if (chrome != "") {
            ch := M(chrome, tint, t * 0.8)
            css .= b " #sidebar," b " .axmb," b " .axsb," b " .axsb-part{background:" ch "}"
        }
        css .= b "," b " .group>.legend," b " .tab," b " .tab-panel," b " .btn,"
            .  (chrome != "" ? "" : b " .axmb," b " .axsb," b " .axsb-part,")
            .  b " #axCtx," b " .axctx," b " #axDlg,"
            .  b " .axdlg-btn," b " .tile," b " .chip," b " .dropzone," b " .winbtn,"
            .  b " .exp-header .chev," b " .numberbox .spin," b " .dd-value:after,"
            .  b " .segmented .seg," b " .imgbox," b " .thumb," b " .dv-hcell,"
            ; #content only. The title bar and the task pane are chrome, not
            ; surfaces: they follow the accent, and a flat tint over them wipes
            ; out Luna's gradient and 9x's caption entirely.
            .  b " #content{background:" bg "}"
            .  b " .card," b " .expander," b " .dv-row.group>.dv-cell{background:" pn "}"
            .  b " input," b " textarea," b " .textbox input," b " .textbox textarea,"
            .  b " .searchbox input," b " .numberbox input," b " .passwordbox input,"
            .  b " .hotkeybox input," b " .list," b " .dd-value," b " .dd-menu," b " .progress,"
            .  b " .sort-list .drag-item," b " .filelist," b " .dv-frame," b " .hex,"
            .  b " .sw-track," b " .badge{background:" wl "}"
        return css
    }
    ; swap the whole look at runtime: SetStylesheet("win98" | "winxp" | "win11" | path)
    SetStylesheet(name) {
        this.Stylesheet := name
        this.SetRoundCorners(AxGui.SheetRound(name))
        super.SetStylesheet(AxGui.ThemeCss(name))
        ; every sheet gets a body class, so a component can adapt to the look
        ; without the core having to know which components exist
        for k in AxGui.SheetBack
            this.BodyClass("sheet-" k, false)
        this.BodyClass("sheet-" AxGui.SheetName(name), true)
        this.SetBackColor(this.ThemeBack(this.Theme))
        this.SetAccent(this.Accent)                 ; the new sheet's own accent, unless one was chosen
        return this
    }
    ; HTML for the whole page (embedded stylesheet, no external files).
    ; (Named PageHtml: Html(id, value) is the core's DOM helper.)
    ; The <body> contents on their own: the bars, the nav, the pages. Lifted
    ; out of PageHtml so a designer can ask for exactly what the finished
    ; window will hold, without the <head> around it.
    BodyHtml() {
        o := this._opts
        if (this.HasOwnProp("_prebuilt") && this._prebuilt != "")
            return this._prebuilt
        body := ""
        if this.HasOwnProp("_menubar") {
            alt := IsObject(this._menubar.Opts) && this._menubar.Opts.HasOwnProp("Reveal")
                   && this._menubar.Opts.Reveal = "alt"
            body .= '<ax-menubar id="axMenuBar"' (alt ? " alt" : "") '></ax-menubar>'
        }
        if (this._pages.Length && this.ShowNav) {
            nav := ""
            for p in this._pages
                nav .= p.Id ":" StrReplace(StrReplace(p.Title, ",", " "), ":", " ") ":" p.Icon ","
            body .= '<ax-nav pages="' AxTags.E(RTrim(nav, ",")) '"></ax-nav>'
        }
        content := this._root.InnerHtml()
        ; The nav names the page, so the page does not name itself again. With
        ; no nav there is nothing else carrying the name, so the heading stays.
        ; Headings: true / false overrides either way.
        heads := o.HasOwnProp("Headings") ? o.Headings
               : !(this._pages.Length && this.ShowNav)
        for i, p in this._pages
            content .= '<ax-page id="' AxTags.E(p.Id) '" title="' AxTags.E(p.Title) '"'
                    . (heads ? "" : " noheading") (i = 1 ? " active" : "") '>'
                    . p.InnerHtml() '</ax-page>'
        ; "shell": the content gets the window's height even with no nav, so
        ; the status bar is at the bottom and a Grow control has room to fill.
        ; Shell: false keeps the old flow, for a window that places #content
        ; itself (AxStudio) or sizes itself to its content (AxRichDialog).
        shell := !(this._pages.Length && this.ShowNav) && !(o.HasOwnProp("Shell") && !o.Shell)
        body .= '<ax-content' (shell ? " shell" : "") '>' content '</ax-content>'
        if this.HasOwnProp("_statusbar")
            body .= '<ax-status id="axStatusBar"></ax-status>'
        return body
    }
    ; Markup that was already built and already expanded -- by AxStudio, when
    ; the script was exported. Everything else is unchanged: the Add* calls
    ; still run, because that is what registers your controls and starts the
    ; components. What goes away is AxTags.Expand's one-reparse-per-control,
    ; which is where the time was.
    ;
    ; It has to match the design it came from. Nothing checks that, and nothing
    ; can: it is a string. Re-export after changing the window.
    Prebuilt(html) {
        this._prebuilt := html
        return this
    }
    PageHtml() {
        o := this._opts
        this.Stylesheet := o.HasOwnProp("Stylesheet") ? o.Stylesheet : "win11"
        css := AxGui.ThemeCss(this.Stylesheet)
        this._rawBase := css            ; embedded, but still ours to re-hue
        title := o.HasOwnProp("Title") ? o.Title : "AxGui"
        theme := o.HasOwnProp("Theme") ? o.Theme : "dark"
        if (theme = "system")
            theme := AxWindow.SystemTheme()
        body := this.BodyHtml()
        base := StrReplace(A_ScriptDir, "\", "/") "/"
        ; The component packs go in first, so the theme that follows can
        ; restyle a control rather than fight it. Only the packs actually
        ; included are registered, so an unused one costs nothing here.
        packBase := ""
        try packBase := AxRich.CoreCss()
        this._rawPack := packBase       ; kept as written, so the accent can be put into it
        ; what each of our <style>s holds as written, so the start does not
        ; set one again to the same text (_PutCss) -- for the page about to be
        ; written, not a copy asked of a window already open
        if !(this.HasOwnProp("Doc") && IsObject(this.Doc)) {
            this._cssNow := Map("axBase", css)
            if (packBase != "")
                this._cssNow["axPackBase"] := packBase
            if this.HasOwnProp("_baseCssPre")
                for id, c in this._baseCssPre
                    if (c != "")
                        this._cssNow["axPack_" id] := c
            if this.HasOwnProp("_extraCss")
                for id, x in this._extraCss
                    if (x[1] != "")
                        this._cssNow["axExtra_" id] := x[1]
        }
        ; the overlays' sheet and markup (menus, dialogs, toasts, tips) go in
        ; the page as it is written: added after, a sheet at the front of
        ; <head> restyles every element there is (_InjectUI finds them here)
        return '<!DOCTYPE html><html><head><meta http-equiv="X-UA-Compatible" content="IE=edge"><meta charset="utf-8">'
            . '<style type="text/css">' AxGui.UiCss '</style>'
            . '<title>' AxTags.E(title) '</title><base href="file:///' base '">'
            . (packBase != "" ? '<style id="axPackBase">' packBase '</style>' : "")
            . this._BaseCssHtml()
            . '<style id="axBase">' css '</style>'
            . '<style>' AxGui.Css '</style>'
            . (o.HasOwnProp("Css") ? '<style>' o.Css '</style>' : "")
            . this._ExtraCssHtml()
            . '</head><body class="theme-' theme ' sheet-' AxGui.SheetName(this.Stylesheet)
            . this._TitleBarClasses() '">'
            . body AxGui.UiHtml '</body></html>'
    }
    static UiCss  := AxWindow.ReadLib("themes\base.css")
    static UiHtml := AxWindow.ReadLib("ui\overlays.html")
    ; ShowTitle / CenterTitle are body classes; they go into the markup rather
    ; than being set afterwards, so a window that hides its caption text never
    ; paints it for a frame first.
    _TitleBarClasses() {
        if !this.HasOwnProp("_titlebar")
            return ""
        o := this._titlebar.Opts
        g := (n, d) => (IsObject(o) && o.HasOwnProp(n)) ? o.%n% : d
        return (g("ShowTitle", true) ? "" : " axtb-notitle") (g("CenterTitle", false) ? " axtb-center" : "")
    }
    static Css := AxWindow.ReadLib("themes\builder.css")

    ; ------------------------------------------------------------- show
    ; Show(false) builds and loads the page without displaying the window
    Show(visible := true) {
        if !this._built {
            this._built := true
            o := this._opts
            o2 := {}
            for k, v in o.OwnProps()
                o2.%k% := v
            o2.Html := this.PageHtml()
            if !o2.HasOwnProp("RoundCorners")
                o2.RoundCorners := AxGui.SheetRound(this.Stylesheet)
            if !o2.HasOwnProp("BackColor")
                o2.BackColor := this.ThemeBack(o2.HasOwnProp("Theme") && o2.Theme = "light" ? "light" : "dark")
            if !o2.HasOwnProp("Title")
                o2.Title := "AxGui"
            ; The page loads inside the constructor, and the components start
            ; after it -- every one of them, on every page, visible or not. The
            ; window does not wait for that: _Wire shows it as soon as the page,
            ; the menu bar and the status bar are in, and paints it, and the
            ; components carry on behind it. Show() still returns once they are
            ; all started, so nothing after it sees a half-built window. The
            ; pages not in view are read after that first paint, not before it.
            this._early := visible
            this._splitPages := visible
            super.__New("", o2)
        }
        if !visible
            this.WaitReady()                 ; hidden build: make the DOM usable before returning
        if (this._early == "shown")
            return (this._early := false, this)
        this._early := false
        return visible ? super.Show() : this
    }
    ; A named stylesheet asked for before Show() goes into the page's own
    ; <head>, so the first paint already wears it; once the window exists
    ; the base class does it, and finds that same <style> by its id. Before
    ; this, a design's own CSS (AxStudio's Look and Css, and what it writes
    ; for page scrolling or a bare window) threw before the window existed.
    SetExtraCss(id, css, themed := false) {
        if this._built
            return super.SetExtraCss(id, css, themed)
        if !this.HasOwnProp("_extraCss")
            this._extraCss := Map()
        this._extraCss[id] := [css, themed]
        return this
    }
    _ExtraCssHtml() {
        s := ""
        if this.HasOwnProp("_extraCss")
            for id, x in this._extraCss
                if (x[1] != "")
                    s .= '<style id="axExtra_' AxTags.E(id) '" type="text/css">' x[1] '</style>'
        return s
    }
    ; The same for a pack's own sheet, the layer under the theme: a pack that
    ; is not in every page (a gauge, say) asks for its sheet as the control is
    ; added, and that is before Show() -- where the window had nowhere to put
    ; it, so the dial came up as a bare number.
    SetBaseCss(id, css) {
        if this._built
            return super.SetBaseCss(id, css)
        if !this.HasOwnProp("_baseCssPre")
            this._baseCssPre := Map()
        this._baseCssPre[id] := css
        return this
    }
    _BaseCssHtml() {
        s := ""
        if this.HasOwnProp("_baseCssPre")
            for id, css in this._baseCssPre
                if (css != "")
                    s .= '<style id="axPack_' AxTags.E(id) '" type="text/css">' css '</style>'
        return s
    }
    ShowPage(id) {
        r := super.ShowPage(id)
        this.FitNow()                        ; a page just shown gets its heights now, not on the next tick
        this.Shown()                         ; and what measures itself (a code editor) catches up, before the paint
        return r
    }

    ; ------------------------------------------------------------- Grow
    ; "Grow" on a control: it takes the height its container has left, so a
    ; list, an editor or a grid fills the window and follows it as the window
    ; is resized. hN with it is the least it is ever given; the page scrolls
    ; rather than squeeze it below that.
    ;
    ; Measured, not left to flexbox. Trident gives a flex item's children no
    ; definite height to be a percentage of, so a list stretched by its line
    ; would not scroll inside itself. A few lines of script in the page set a
    ; real height instead -- the one every control already honours as hN --
    ; whenever the window, the page or the content around it changes.
    static Grows(o) => o.Flags.Has("grow") && o.Flags["grow"]
    ; The root tag of a control's markup, marked: the class the script looks
    ; for, and hN as the least height it may have.
    static GrowHtml(html, o) {
        if !AxGui.Grows(o)
            return html
        end := InStr(html, ">")
        if !end
            return html
        tag := SubStr(html, 1, end), rest := SubStr(html, end + 1)
        if RegExMatch(tag, ' class="')
            tag := RegExReplace(tag, ' class="', ' class="ax-growy ', , 1)
        else
            tag := RegExReplace(tag, "^<([\w-]+)", '<$1 class="ax-growy"', , 1)
        if (o.H != "") {
            m := "min-height:" o.H "px;"
            if RegExMatch(tag, ' style="')
                tag := RegExReplace(tag, ' style="', ' style="' m, , 1)
            else
                tag := RegExReplace(tag, "^<([\w-]+)", '<$1 style="' m '"', , 1)
        }
        return tag rest
    }
    ; Something has just come into view (a page, a tab) or changed size: the
    ; page's own window.axShown lets each component that measures itself do it
    ; now, in this turn, so the first frame is already right -- rather than on
    ; its own timer a frame or two after, which shows as a flash.
    Shown() {
        try this.Doc.parentWindow.axShown()
        return this
    }
    ; Fit every Grow control now. The page keeps itself fitted after this (on
    ; resize, and a light check a few times a second); this is for the moments
    ; AutoHotkey knows something moved -- a page shown, a panel opened.
    FitNow() {
        try {
            if !IsObject(this.Doc) || !IsObject(this.Doc.querySelector(".ax-growy"))
                return this
            AxGui.UseFit(this.Doc)
            this.Doc.parentWindow.axFit()
        }
        return this
    }
    ; The page rail: "full" (icons and names), "compact" (icons only),
    ; "hidden", or "toggle" -- full and compact in turn, what a burger in the
    ; title bar wants. Returns the mode now in force.
    ;   g.AddTitleBar([{Id: "menu", Kind: "burger", Click: (*) => g.NavMode("toggle")}])
    NavMode(mode := "") {
        cur := this.HasOwnProp("_navMode") ? this._navMode : "full"
        if (mode = "")
            return cur
        if (mode = "toggle")
            mode := (cur = "full") ? "compact" : "full"
        if !(mode = "full" || mode = "compact" || mode = "hidden")
            throw ValueError("NavMode takes full, compact, hidden or toggle", -1, mode)
        this._navMode := mode
        this.BodyClass("nav-compact", mode = "compact")
        this.BodyClass("nav-hidden", mode = "hidden")
        this.TitleAlign()                               ; a burger over the rail follows its icons
        this.FitNow()
        this.Shown()
        return mode
    }
    ; Put the script in a document once. Also what AxStudio calls for its
    ; canvas, which is why it takes a document rather than a window.
    static UseFit(doc) {
        try if IsObject(doc.getElementById("axFitJs"))
            return true
        try {
            s := doc.createElement("script")
            s.id := "axFitJs"
            s.text := AxGui.FitJs
            doc.getElementsByTagName("head").item(0).appendChild(s)
            return true
        }
        return false
    }
    ; The limit a control grows against is the nearest of: #content, anything
    ; marked ax-limit, a control that grows itself, anything with a height of
    ; its own, and a tab panel whose frame has one. Its end is found with an
    ; empty div put after the last thing in it for a moment -- that is the
    ; one measure that counts collapsed margins the way the page lays them
    ; out. Controls on one line share the line's height, so a list and a panel
    ; beside it grow together; lines that grow against one limit split what it
    ; has left evenly. Everything is in the element's own pixels, so a
    ; scaled canvas (AxStudio's zoom) measures the same as the window.
    static FitJs := "
    (
(function () {
  if (window.axFit) return;
  var pass = 0;
  function has(el, c) { return (' ' + (el.className || '') + ' ').indexOf(' ' + c + ' ') >= 0; }
  function shown(el) { return el.offsetWidth > 0 || el.offsetHeight > 0; }
  function px(v) { v = parseFloat(v); return isNaN(v) ? 0 : v; }
  function limitOf(el) {
    for (var p = el.parentNode; p && p.nodeType == 1; p = p.parentNode) {
      if (p.id == 'content' || has(p, 'ax-limit') || has(p, 'ax-growy') || (p.style && p.style.height)) return p;
      if (has(p, 'tab-panel') && p.parentNode && (has(p.parentNode, 'ax-growy') || p.parentNode.style.height)) return p;
    }
    return null;
  }
  function scaleOf(B) { var h = B.offsetHeight; return h ? (B.getBoundingClientRect().height / h) || 1 : 1; }
  function lastBottom(B) {
    for (var c = B.lastChild; c; c = c.previousSibling)
      if (c.nodeType == 1 && shown(c)) return Math.round((c.getBoundingClientRect().bottom - B.getBoundingClientRect().top) / scaleOf(B));
    return 0;
  }
  function endOf(B) {
    var s = document.createElement('div');
    s.style.cssText = 'height:0;margin:0;padding:0;border:0;clear:both;display:block';
    B.appendChild(s);
    var y = (s.getBoundingClientRect().top - B.getBoundingClientRect().top) / scaleOf(B) - B.clientTop + B.scrollTop;
    B.removeChild(s);
    return y;
  }
  function sigOf(B, units) {
    var s = B.clientHeight + '|' + B.clientWidth + '|' + lastBottom(B);
    for (var i = 0; i < units.length; i++)
      for (var j = 0; j < units[i].grow.length; j++) s += '|' + units[i].grow[j].offsetHeight;
    return s;
  }
  function setH(el, h) {
    el.style.height = h + 'px';
    var d = h - el.offsetHeight;
    if (d && Math.abs(d) < 60) el.style.height = Math.max(0, h + d) + 'px';
  }
  // Everything that grows against one limit shares what that limit has left:
  // two lists stacked get half each, a keypad's rows a fifth each.
  function fitGroup(B, units) {
    var sig = sigOf(B, units);
    if (B.axSig === sig) return;
    var i, j;
    for (i = 0; i < units.length; i++)
      for (j = 0; j < units[i].grow.length; j++) units[i].grow[j].style.height = '';
    var cs = B.currentStyle || window.getComputedStyle(B);
    var slack = Math.floor(B.clientHeight - px(cs.paddingBottom) - endOf(B));
    if (slack > 0) {
      var share = Math.floor(slack / units.length), left = slack - share * units.length;
      for (i = 0; i < units.length; i++) {
        var u = units[i], target = u.el.offsetHeight + share + (i < left ? 1 : 0);
        for (j = 0; j < u.grow.length; j++) {
          var g = u.grow[j], gs = g.currentStyle || window.getComputedStyle(g);
          setH(g, target - (u.el === g ? 0 : px(gs.marginTop) + px(gs.marginBottom)));
        }
      }
    }
    B.axSig = sigOf(B, units);
  }
  window.axFit = function (root) {
    pass++;
    var list = (root || document).querySelectorAll('.ax-growy'), groups = [];
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (!shown(el)) continue;
      var u = (el.parentNode && has(el.parentNode, 'ax-line')) ? el.parentNode : el;
      if (u.axPass === pass) continue;
      u.axPass = pass;
      var grow = [];
      if (u === el) grow.push(el);
      else for (var c = u.firstChild; c; c = c.nextSibling)
        if (c.nodeType == 1 && has(c, 'ax-growy') && shown(c)) grow.push(c);
      var B = limitOf(u);
      if (!B) continue;
      // groups are kept in the order their limits are met, which is outer
      // before inner: a box that grows is sized before what grows inside it
      var grp = null;
      for (var k = 0; k < groups.length; k++) if (groups[k].B === B) { grp = groups[k]; break; }
      if (!grp) groups.push(grp = {B: B, units: []});
      grp.units.push({el: u, grow: grow});
    }
    for (var m = 0; m < groups.length; m++) {
      try { fitGroup(groups[m].B, groups[m].units); } catch (e) {}
    }
  };  window.attachEvent ? window.attachEvent('onresize', function () { window.axFit(); })
                     : window.addEventListener('resize', function () { window.axFit(); });
  setInterval(function () { if (document.querySelector('.ax-growy')) window.axFit(); }, 250);
})();
    )"
    _Wire(*) {
        if this.HasOwnProp("_menubar")
            this.MenuBar("axMenuBar", this._menubar.Menus, this._menubar.Opts)
        if this.HasOwnProp("_statusbar")
            this.StatusBar("axStatusBar", this._statusbar.Parts, this._statusbar.Opts)
        if this.HasOwnProp("_titlebar")
            this.TitleBar(this._titlebar.Items, this._titlebar.Opts)
        ; handlers first -- they only register, and the window may be up and
        ; taking clicks before the rest is done; tips and hotkeys read their
        ; element, which may be on a page not yet put back, so they wait
        later := []
        for h in this._pending {
            switch h[1] {
            case "value": this.OnValue(h[2], h[3])
            case "ctx":   this.ContextMenu(h[2], h[3])
            case "hotkey", "tip": later.Push(h)
            default:      this.On(h[1], h[2], h[3])
            }
        }
        this._pending := []
        if (this.HasOwnProp("_navMode") && this._navMode != "full")    ; NavMode() called before Show()
            this.NavMode(this._navMode)
        if this.HasOwnProp("_extraCss") {                 ; a themed sheet asked for before Show()
            for id, x in this._extraCss                    ; is registered, so the accent re-hues it
                if x[2]
                    super.SetExtraCss(id, x[1], true)
            this._extraCss := Map()
        }
        if this.HasOwnProp("_baseCssPre") {               ; and so is a pack's sheet
            for id, css in this._baseCssPre
                super.SetBaseCss(id, css)
            this._baseCssPre := Map()
        }
        this.FitNow()                        ; anything marked Grow: fitted before the first paint
        if (this._early == true) {           ; see Show(): up now, painted, the rest behind it
            this._early := "shown"
            AxWindow.Prototype.Show.Call(this)
            DllCall("RedrawWindow", "Ptr", this.Gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
        }
        this._FillPages()                    ; the pages not in view, back in the page
        for h in later
            (h[1] = "tip") ? this.Tooltip(h[2], h[3]) : this.Hotkey(h[2], h[3])
        ; an embedded control is a native window of its own, so an ActiveX
        ; control on a page not in view no longer holds the window back
        for e in this._embedPending
            this.Embed(e[1], e[2])
        this._embedPending := []
    }
    _Hook(kind, id, fn) {
        if this.Ready {
            switch kind {
            case "value": this.OnValue(id, fn)
            case "ctx":   this.ContextMenu(id, fn)
            case "hotkey": this.Hotkey(id, fn)
            case "tip":   this.Tooltip(id, fn)
            default:      this.On(kind, id, fn)
            }
        } else
            this._pending.Push([kind, id, fn])
    }
    _NextId(prefix := "ax") => prefix "_" (++this._n)
    Ctl(id) => this._controls.Has(id) ? this._controls[id] : ""

    ; Cursor=hand on any control: the pointer over it. The names AutoHotkey and
    ; Windows use (A_Cursor, IDC_*) or CSS's own; anything else is passed on.
    static Cursors := Map("arrow", "default", "hand", "pointer", "ibeam", "text", "no", "not-allowed",
        "wait", "wait", "appstarting", "progress", "help", "help", "cross", "crosshair",
        "sizeall", "move", "sizewe", "ew-resize", "sizens", "ns-resize",
        "sizenwse", "nwse-resize", "sizenesw", "nesw-resize", "uparrow", "n-resize")
    static CursorCss(name) {
        n := StrLower(Trim(String(name)))
        return AxGui.Cursors.Has(n) ? AxGui.Cursors[n] : RegExReplace(n, "[^a-z-]")
    }
    ; ==================================================================
    ; option string parser:  "vName w200 x+8 Accent Tip=`"hello`" Min=0"
    static ParseOpts(str) {
        o := {Id: "", W: "", H: "", X: "", Y: "", Inline: false, Gap: 8, Top: "", Flags: Map(), KV: Map(), Choose: 0}
        pos := 1
        while RegExMatch(str, 'S)\s*(?:([A-Za-z][\w+\-]*)=("[^"]*"|\S*)|(\S+))', &m, pos) {
            pos := m.Pos + m.Len
            if (m[1] != "") {
                v := m[2]
                if (SubStr(v, 1, 1) = '"')
                    v := SubStr(v, 2, -1)
                o.KV[StrLower(m[1])] := v
                continue
            }
            t := m[3]
            if (t = "")
                break
            c := SubStr(t, 1, 1), rest := SubStr(t, 2)
            static words := " vertical visible "          ; flags that happen to start with v
            if (c = "v" && rest != "" && !InStr(words, " " StrLower(t) " "))
                o.Id := rest
            else if (c = "w" && IsNumber(rest))
                o.W := rest
            else if (c = "h" && IsNumber(rest))
                o.H := rest
            else if (SubStr(t, 1, 2) = "x+")
                o.Inline := true, o.Gap := (SubStr(t, 3) != "" ? Integer(SubStr(t, 3)) : 8)
            else if (SubStr(t, 1, 2) = "y+")
                o.Top := SubStr(t, 3)
            else if (c = "x" && IsNumber(rest))
                o.X := rest
            else if (c = "y" && IsNumber(rest))
                o.Y := rest
            else if (SubStr(t, 1, 6) = "Choose" && IsNumber(SubStr(t, 7)))
                o.Choose := Integer(SubStr(t, 7))
            else
                o.Flags[StrLower(LTrim(t, "+"))] := (SubStr(t, 1, 1) != "-")
        }
        return o
    }

    ; ==================================================================
    class Container {
        __New(g, kind, id) {
            this.G := g, this.Kind := kind, this.Id := id
            this.Items := []             ; html strings or nested containers
            this._line := ""             ; open inline line (array of html)
            this._lineGrow := false      ; ... and whether something on it grows
            this.Title := "", this.Icon := ""
            this._tabs := []             ; AddTab panels
            this.Html := ""              ; wrapper template with {inner}
            this.Flat := false           ; true: children are not grouped into .ax-line rows (grids)
        }
        ; --- html assembly
        _Flush() {
            if IsObject(this._line) {
                ; a line holding a box is written when the page is, once the
                ; box has its content; one of controls only is written now
                boxed := false
                for x in this._line
                    boxed := boxed || IsObject(x)
                if boxed {
                    parts := this._line, grow := this._lineGrow
                    this.Items.Push({OuterHtml: (*) => '<div class="ax-line' (grow ? " ax-grow" : "") '">' this._Join(parts) '</div>'})
                } else
                    this.Items.Push('<div class="ax-line' (this._lineGrow ? " ax-grow" : "") '">' this._Join(this._line) '</div>')
                this._line := "", this._lineGrow := false
            }
        }
        _Join(arr) {
            s := ""
            for x in arr
                s .= IsObject(x) ? x.OuterHtml() : x
            return s
        }
        InnerHtml() {
            this._Flush()
            s := ""
            for it in this.Items
                s .= IsObject(it) ? it.OuterHtml() : it
            return s
        }
        OuterHtml() => StrReplace(this.Html, "{inner}", this.InnerHtml())
        _Place(html, o) {
            ; absolute positioning / flat containers: bypass lines
            if (o.X != "" || o.Y != "" || this.Flat) {
                this._Flush()
                this.Items.Push(html)
                return
            }
            if (o.Inline && IsObject(this._line)) {
                this._line.Push(html)
                this._lineGrow := this._lineGrow || AxGui.Grows(o)
                return
            }
            this._Flush()
            this._line := [html]
            this._lineGrow := AxGui.Grows(o)
        }
        ; style/attr string shared by every control
        _Common(o, extraCls := "") {
            st := ""
            if (o.W != "")
                st .= "width:" o.W "px;"
            if (o.H != "")
                st .= "height:" o.H "px;"
            if (o.X != "" || o.Y != "")
                st .= "position:absolute;" (o.X != "" ? "left:" o.X "px;" : "") (o.Y != "" ? "top:" o.Y "px;" : "")
            if (o.Top != "")
                st .= "margin-top:" o.Top "px;"
            if (o.Inline && o.Gap != 8)
                st .= "margin-left:" (o.Gap - 8) "px;"
            if o.KV.Has("cursor")
                st .= "cursor:" AxGui.CursorCss(o.KV["cursor"]) ";"
            if o.KV.Has("style")
                st .= o.KV["style"]
            cls := extraCls (o.Flags.Has("fill") ? " fill" : "") (o.Flags.Has("hidden") ? " ax-hidden" : "") (o.KV.Has("class") ? " " o.KV["class"] : "")
            a := ' id="' AxTags.E(o.Id) '"'
            if (Trim(cls) != "")
                a .= ' class="' Trim(cls) '"'
            if (st != "")
                a .= ' style="' AxTags.E(st) '"'
            if o.KV.Has("tip")
                a .= ' tip="' AxTags.E(o.KV["tip"]) '"'
            return a
        }
        _Kv(o, key, def := "") => o.KV.Has(key) ? o.KV[key] : def
        _Opt(opts, prefix := "ax") {
            o := AxGui.ParseOpts(opts)
            if (o.Id = "")
                o.Id := this.G._NextId(prefix)
            return o
        }
        _Reg(o, type, html) {
            c := AxGui.Control(this.G, o.Id, type)
            this.G._controls[o.Id] := c
            html := AxGui.GrowHtml(html, o)
            this._Place(html, o)
            if this.G.Ready                      ; live add after Show()
                this.G._LiveAdd(this, html)
            return c
        }
        ; options="a:A|b:B" or array of labels / [value,label] pairs
        _Options(o, text, choose := 0) {
            list := ""
            if IsObject(text) {
                for i, it in text {
                    v := IsObject(it) ? it[1] : it, l := IsObject(it) ? it[2] : it
                    list .= (list = "" ? "" : "|") StrReplace(v, "|", " ") ":" StrReplace(l, "|", " ")
                }
            } else
                list := text
            sel := this._Kv(o, "value")
            if (choose > 0) {
                parts := StrSplit(list, InStr(list, "|") ? "|" : ",")
                if (choose <= parts.Length) {
                    p := parts[choose], k := InStr(p, ":")
                    sel := Trim(k ? SubStr(p, 1, k - 1) : p)
                }
            }
            return [list, sel]
        }

        ; --- generic dispatcher (like Gui.Add)
        Add(type, opts := "", text := "") {
            static alias := Map("ddl", "DDL", "dropdownlist", "DDL", "combobox", "DDL", "check", "CheckBox", "checkbox", "CheckBox",
                "edit", "Edit", "text", "Text", "button", "Button", "link", "Link", "switch", "Switch", "radio", "Radio",
                "password", "Password", "search", "Search", "autocomplete", "AutoComplete", "combo", "AutoComplete", "number", "Number", "updown", "Number", "slider", "Slider",
                "listbox", "ListBox", "progress", "Progress", "infobar", "InfoBar", "badge", "Badge", "chip", "Chip",
                "palette", "Palette", "rating", "Rating", "segmented", "Segmented", "hotkey", "Hotkey", "console", "Console",
                "picture", "Picture", "pic", "Picture", "activex", "ActiveX", "html", "Html", "separator", "Separator", "tile", "Tile",
                "image", "Image", "img", "Image", "imagebutton", "ImageButton", "imgbutton", "ImageButton", "svg", "Svg",
                "dropzone", "DropZone", "drop", "DropZone", "filelist", "FileList", "files", "FileList", "thumbs", "Thumbs",
                "groupbox", "GroupBox", "card", "Card", "row", "Row", "expander", "Expander", "grid", "Grid", "tab", "Tab", "tab3", "Tab",
                "listview", "ListView", "treeview", "TreeView", "dataview", "DataView")
            k := StrLower(type)
            if !alias.Has(k)
                throw ValueError("Unknown control type: " type, -1)
            return this.%("Add" alias[k])%(opts, text)
        }

        ; --- simple controls ------------------------------------------
        ; AddAutoComplete("vCity Strict w240 placeholder=City", "lon:London|par:Paris")
        ; Strict = list values only (a non-matching entry clears on blur); else free text with suggestions
        ; AddActiveX("vweb Stretch", "Shell.Explorer.2") — a real ActiveX control docked
        ; over the placeholder; ctl.Object is the COM object. Stretch = fill the rest
        ; of the page height; otherwise give it hN (default 240).
        ; --- pictures, vectors, drops ---------------------------------
        ; AddImage("vhero w320 Fit=contain Caption=\"Sunset\"", "assets\photo.jpg")
        ; The id names the box, so OnClick works and SetImage(id, url) can
        ; swap the source and report success or failure.
        ; AddSvg("vchart w420 h220", "<svg ...>...</svg>") — the markup is not
        ; escaped; give the shapes ids and drive them with On/Attr/AddClass.
        ; AddDropZone('vdz Accept=images Browse Desc="PNG, JPG, GIF"', "Drop images here")
        ; .OnDrop(fn) attaches the callback; the zone is registered up front so
        ; the filter applies even before a handler exists.

        ; --- containers -----------------------------------------------
        ; containers auto-enter: later Add* calls go inside until Use()/UseTab()
        _Sub(o, type, wrapper) {
            c := AxGui.Container(this.G, type, o.Id)
            c.Html := AxGui.GrowHtml(wrapper, o)
            ; x+ puts a box beside what came before it, as it does a control
            if (o.Inline && IsObject(this._line) && o.X = "" && o.Y = "" && !this.Flat) {
                this._line.Push(c)
                this._lineGrow := this._lineGrow || AxGui.Grows(o)
            } else {
                this._Flush()
                this.Items.Push(c)
            }
            this.G._controls[o.Id] := AxGui.Control(this.G, o.Id, type)
            this.G._cur := c
            return c
        }
        ; AddTab(opts, ["Basic", "Advanced"]) then UseTab(1)
        UseTab(n := 0) {
            if (this.Kind = "Tab" && n >= 1 && n <= this._tabs.Length)
                this.G._cur := this._tabs[n]
            else
                this.G.Use()
            return this
        }
        Use() {
            this.G._cur := this
            return this
        }
        ; A container is an element too, and clicking a card, a setting row or
        ; a tile grid is a perfectly ordinary thing to want. _Sub already
        ; registered a Control over the same id, so this is a forward rather
        ; than a second implementation -- and it is what a designer generates
        ; the moment a box control is given an event.
        OnEvent(name, fn) {
            c := this.G.Ctl(this.Id)
            if !IsObject(c)
                c := AxGui.Control(this.G, this.Id, this.Kind)
            c.OnEvent(name, fn)
            return this
        }
        OnClick(fn) => this.OnEvent("Click", fn)
        OnDoubleClick(fn) => this.OnEvent("DoubleClick", fn)
        OnContextMenu(fn) => this.OnEvent("ContextMenu", fn)
    }

    ; live add after Show(): append into the container's element and expand
    _LiveAdd(container, html) {
        try {
            el := this.El(container.Id)
            if !IsObject(el)
                return
            el.insertAdjacentHTML("beforeend", container.Flat ? html : '<div class="ax-line">' html '</div>')
            AxTags.Expand(this.Doc)
            this._MakeFocusable()
        }
    }

    ; The stand-in Control.Object hands back before the window exists.
    ; Calls and assignments wait for OnReady; reading needs the real thing.
    class EmbedLater {
        __New(g, id) {
            this.DefineProp("_g", {Value: g}), this.DefineProp("_id", {Value: id})
        }
        __Call(name, args) {
            id := this._id
            this._g.OnReady((w) => AxGui.EmbedLater._Do(w, id, name, args))
            return ""
        }
        __Set(name, params, value) {
            id := this._id
            this._g.OnReady((w) => AxGui.EmbedLater._Put(w, id, name, value))
        }
        __Get(name, params) {
            throw Error("The ActiveX control " this._id " is made when its window opens, so " name
                      . " cannot be read before Show(). Read it in g.OnReady(...) or in a handler.", -1)
        }
        static _Do(w, id, name, args) {
            o := w.EmbedObj(id)
            if IsObject(o)
                o.%name%(args*)
        }
        static _Put(w, id, name, value) {
            o := w.EmbedObj(id)
            if IsObject(o)
                o.%name% := value
        }
    }
    ; ==================================================================
    class Control {
        __New(g, id, type) {
            this.G := g, this.Id := id, this.Type := type
        }
        ; OnEvent("Click"|"Change"|"DoubleClick"|"Focus"|"Blur"|"KeyUp"|"KeyDown"|"ContextMenu", fn)
        ; fn(ctl, valueOrEvent, el)
        OnEvent(name, fn) {
            static evmap := Map("click", "click", "doubleclick", "dblclick", "focus", "focusin", "blur", "focusout",
                "keyup", "keyup", "keydown", "keydown", "contextmenu", "contextmenu", "mousedown", "mousedown", "mouseup", "mouseup",
                "mouseover", "mouseover", "mouseout", "mouseout")
            n := StrLower(name)
            if (n = "change" || n = "value")
                this.G._Hook("value", this.Id, (v, el) => fn(this, v, el))
            else if (n = "hotkey")
                this.G._Hook("hotkey", this.Id, (*) => fn(this))
            else if evmap.Has(n)
                this.G._Hook(evmap[n], this.Id, (el, ev) => fn(this, ev, el))
            else
                throw ValueError("Unknown event: " name, -1)
            return this
        }
        OnClick(fn) => this.OnEvent("Click", fn)
        OnChange(fn) => this.OnEvent("Change", fn)
        OnDoubleClick(fn) => this.OnEvent("DoubleClick", fn)
        ; Trident follows the old IE button model on mousedown: 1 left, 2
        ; right, 4 middle. The default middle-click autoscroll is swallowed.
        OnMiddleClick(fn) {
            this.OnEvent("MouseDown", (c, ev, el) =>
                (AxGui.Control._Btn(ev) = 4 ? (fn(c, ev, el), ev.returnValue := false) : ""))
            return this
        }
        ; OnMultiClick(3, fn) for a triple click, 4 for a quadruple, and so on.
        ; There is no such DOM event, so the clicks are counted here: any two
        ; landing more than `gap` apart start the count again.
        OnMultiClick(times, fn, gap := 400) {
            st := {N: 0, At: 0}
            this.OnEvent("Click", (c, ev, el) => AxGui.Control._Multi(st, times, gap, fn, c, ev, el))
            return this
        }
        OnTripleClick(fn) => this.OnMultiClick(3, fn)
        static _Btn(ev) {
            try return ev.button
            return 1
        }
        static _Multi(st, times, gap, fn, c, ev, el) {
            now := A_TickCount
            st.N := (now - st.At > gap) ? 1 : st.N + 1
            st.At := now
            if (st.N >= times) {
                st.N := 0
                fn(c, ev, el)
            }
        }
        ContextMenu(items) {
            this.G._Hook("ctx", this.Id, items)
            return this
        }
        El => this.G.El(this.Id)
        ; Set before the window is up -- in start-up code, which runs ahead of
        ; Show() -- a value, a text, a tick, whether it shows or is enabled is
        ; kept and given to the control once the page is there. Read before
        ; then, it is what was set.
        Value {
            get => this.G.Ready ? this.G.Value(this.Id) : this._Pending("Value")
            set => this.G.Ready ? this.G.Value(this.Id, value) : this._Later("Value", value)
        }
        Text {
            get => this.G.Ready ? this.G.Text(this.Id) : this._Pending("Text")
            set => this.G.Ready ? this.G.Text(this.Id, value) : this._Later("Text", value)
        }
        Checked {
            get => this.G.Ready ? (this._Input().checked ? 1 : 0) : this._Pending("Checked", 0)
            set => this.G.Ready ? (this._Input().checked := value ? true : false) : this._Later("Checked", value)
        }
        _Later(prop, v) {
            if !this.HasOwnProp("_pend") {
                this._pend := Map()
                this.G.OnReady((*) => this._ApplyPending())
            }
            this._pend[prop] := v
        }
        _Pending(prop, d := "") => (this.HasOwnProp("_pend") && this._pend.Has(prop)) ? this._pend[prop] : d
        _ApplyPending() {
            p := this._pend.Clone()
            this._pend.Clear()
            for k, v in p
                this.%k% := v
        }
        _Input() {
            el := this.El
            try return (el.tagName = "INPUT" || el.tagName = "TEXTAREA") ? el : el.querySelector("input")
            return el
        }
        Visible {
            get => this.G.Ready ? !AxWindow._HasClass(this.El, "ax-hidden") : this._Pending("Visible", 1)
            set => this.G.Ready ? AxWindow._SetClass(this.El, "ax-hidden", !value) : this._Later("Visible", value)
        }
        Enabled {
            get => this.G.Ready ? !AxWindow._HasClass(this.El, "disabled") : this._Pending("Enabled", 1)
            set => this.G.Ready ? AxWindow._SetClass(this.El, "disabled", !value) : this._Later("Enabled", value)
        }
        ; AddActiveX: the hosted COM object. It is made when the window is, so
        ; before then -- in startup code that runs ahead of Show() -- this is
        ; a stand-in that does what it is told once the real one exists:
        ; web.Object.Navigate(url) written before Show() navigates on open.
        Object {
            get {
                o := this.G.EmbedObj(this.Id)
                return (IsObject(o) || this.G.Ready) ? o : AxGui.EmbedLater(this.G, this.Id)
            }
        }
        ; AddDropZone: fn(files, id, info) when files are dropped (or picked)
        OnDrop(fn, opts := "") => (this.G.DropZone(this.Id, fn, opts), this)
        ; AddImage: swap the picture and watch whether it arrives
        SetImage(src, opts := "") => (this.G.SetImage(this.Id, src, opts), this)
        ClearImage(message := "") => (this.G.ClearImage(this.Id, message), this)
        ImageState => this.G.ImageState(this.Id)
        ; AddFileList / AddThumbs: fill from an array of paths
        SetFiles(files, opts := "") => (this.G.SetFileList(this.Id, files, opts), this)
        SetThumbs(files, opts := "") => (this.G.SetThumbs(this.Id, files, opts), this)
        SetOptions(options) => (this.G.SetOptions(this.Id, options), this)   ; AddAutoComplete: replace suggestions
        Focus() => this.G.Focus(this.Id)
        SetTip(text) => (this.G._Hook("tip", this.Id, text), this)
        AddClass(c) => this.G.AddClass(this.Id, c)
        RemoveClass(c) => this.G.RemoveClass(this.Id, c)
        Style(prop, v) => this.G.Style(this.Id, prop, v)
    }
}

; The control packs. Each is a folder under lib\controls with its own
; manifest; AxGui carries them so that including this file alone still
; gives you every control, exactly as it did when they lived in here.
#Include %A_LineFile%\..\components\_all.ahk
; what scripts written for Gui() reach for: g["name"], Submit(), ctl.Opt(), ...
#Include %A_LineFile%\..\AxGui.Compat.ahk
