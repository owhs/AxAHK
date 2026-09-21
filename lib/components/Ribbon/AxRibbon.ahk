#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Ribbon\AxRibbon.css, AX_COMPONENTS_RIBBON_AXRIBBON_CSS

; =============================================================================
;  AxRibbon.ahk — the band of commands across the top, in four shapes.
;
;      rib := g.AddRibbon("vrib", {
;          Mode: "office",
;          Tabs: [
;            {Id: "home", Title: "Home", Groups: [
;               {Id: "clip", Title: "Clipboard", Launcher: true, Items: [
;                  {Id: "paste", Label: "Paste", Icon: "E77F", Size: "large",
;                   Kind: "split", Menu: [["Keep formatting", ""], ["Text only", ""]]},
;                  {Id: "cut",   Label: "Cut",   Icon: "E8C6"},
;                  {Id: "copy",  Label: "Copy",  Icon: "E8C8"}]},
;               {Id: "font", Title: "Font", Items: [
;                  {Id: "bold", Label: "Bold", Icon: "E8DD", Kind: "toggle", Key: "B"},
;                  {Kind: "sep"},
;                  {Id: "colour", Label: "Colour", Icon: "E790", Kind: "color"}]}]}]})
;      rib.OnCommand((id, item, r) => Do(id))
;
;  --------------------------------------------------------------- the shapes
;    "office"    tabs over grouped panels, each group titled, with a launcher
;                arrow — the classic ribbon
;    "simple"    tabs over one compact line of commands, the rest behind "..."
;    "strip"     no tabs at all: one persistent line of grouped commands
;    "titlebar"  the tabs live in the window's own title bar, the panel under
;                it. Needs a window with the injected frame, which is every
;                AxGui window
;
;  SetMode() swaps between them while the window is open, and nothing else
;  changes — the same Tabs describe all four.
;
;  ---------------------------------------------------------------- the items
;    Kind    "button" (default) "toggle" "split" "menu" "check" "gallery"
;            "color" "input" "label" "sep" "spacer"
;    Size    "large" (icon over label, full panel height) | "small" (default)
;    Id Label Icon Tip Key Disabled Hidden Checked Width
;    Menu    items for "menu" and "split" — the same shape ShowMenu takes
;    Items   for "gallery": [{Id, Label, Icon, Color}]
;    Value   for "input" and "color"
;
;  ------------------------------------------------------------------- events
;  Each of these is a method on the ribbon, and also a key in the config --
;  ctl.Component is blank until the window is ready, so a ribbon wired up in
;  the same statement that creates it passes its handlers in:
;
;      g.AddRibbon("vrib Fill", {Tabs: ..., OnCommand: (id, it, r) => Do(id)})
;
;    OnCommand(fn)    anything clicked          fn(id, item, ribbon)
;    OnToggle(fn)     a toggle or check moved   fn(id, on, ribbon)
;    OnTab(fn)        a tab was chosen          fn(tabId, ribbon)
;    OnLauncher(fn)   a group's corner arrow    fn(groupId, ribbon)
;    OnCollapse(fn)   rolled up or down         fn(collapsed, ribbon)
;    OnInput(fn)      an input box changed      fn(id, value, ribbon)
;
;  ------------------------------------------------------------- what it does
;    Double-click a tab to roll the ribbon up; click a tab while it is rolled
;    up and the panel floats over the page until you click away. Contextual
;    tabs are declared like any other and shown when they apply:
;    rib.ShowContext("picture", true). Groups that do not fit collapse, right
;    to left, into a button that drops the whole group. Alt shows the key tips
;    (the window's own Alt is the app's to bind: g.On("keydown", "*", ...) and
;    call rib.ShowKeyTips()).
;
;    A quick access toolbar sits in the title bar in "titlebar" mode, and above
;    the tabs otherwise: QuickAccess: ["save", "undo", "redo"] names item ids.
; =============================================================================
class AxRibbon {
    static _reg := AxRich.Register("Ribbon", "components\Ribbon\AxRibbon.css",
                                   (*) => AxRibbon._Install())
    static _Install() {
        AxRich.AddMethod("AddRibbon", (c, o := "", d := "") => AxRibbon._Add(c, o, d))
        AxWindow.RegisterValue("ribbon",
            (w, el) => AxRibbon._Via(w, el, unset),
            (w, el, v) => AxRibbon._Via(w, el, v))
        return true
    }
    static _Via(win, el, value?) {
        r := AxRich.At(win, el.id)
        if !IsObject(r)
            return ""
        if IsSet(value)
            return r.ShowTab(value)
        return r.Tab
    }
    static Modes := ["office", "simple", "strip", "titlebar"]

    ; ------------------------------------------------------- reading the spec
    ; Everything below works on normalised records, so the rest of the file
    ; never has to ask whether a field was given.
    static _P(o, n, d := "") {
        if !IsObject(o)
            return d
        if (o is Map)
            return o.Has(n) ? o[n] : d
        return o.HasOwnProp(n) ? o.%n% : d
    }
    static _Tabs(spec) {
        out := []
        for t in (spec is Array ? spec : []) {
            tab := {Id: AxRibbon._P(t, "Id", ""), Title: AxRibbon._P(t, "Title", ""),
                    Icon: AxRibbon._P(t, "Icon", ""), Key: AxRibbon._P(t, "Key", ""),
                    Contextual: AxRibbon._P(t, "Contextual", false),
                    Colour: AxRibbon._P(t, "Color", AxRibbon._P(t, "Colour", "")),
                    Set: AxRibbon._P(t, "Set", ""),        ; the band a contextual tab belongs to
                    Hidden: AxRibbon._P(t, "Hidden", false), Groups: []}
            if (tab.Id = "")
                tab.Id := "tab" out.Length + 1
            if (tab.Title = "")
                tab.Title := tab.Id
            for gsrc in (AxRibbon._P(t, "Groups", []) is Array ? AxRibbon._P(t, "Groups", []) : []) {
                grp := {Id: AxRibbon._P(gsrc, "Id", ""), Title: AxRibbon._P(gsrc, "Title", ""),
                        Icon: AxRibbon._P(gsrc, "Icon", ""),
                        Launcher: AxRibbon._P(gsrc, "Launcher", false),
                        Hidden: AxRibbon._P(gsrc, "Hidden", false), Items: []}
                if (grp.Id = "")
                    grp.Id := tab.Id "g" tab.Groups.Length + 1
                for isrc in (AxRibbon._P(gsrc, "Items", []) is Array ? AxRibbon._P(gsrc, "Items", []) : [])
                    grp.Items.Push(AxRibbon._Item(isrc, grp.Id, grp.Items.Length + 1))
                tab.Groups.Push(grp)
            }
            out.Push(tab)
        }
        return out
    }
    static _Item(src, groupId, n) {
        it := {Id: AxRibbon._P(src, "Id", ""),
               Label: AxRibbon._P(src, "Label", ""),
               Icon: AxRibbon._P(src, "Icon", ""),
               Kind: StrLower(String(AxRibbon._P(src, "Kind", ""))),
               Size: StrLower(String(AxRibbon._P(src, "Size", "small"))),
               Tip: AxRibbon._P(src, "Tip", ""),
               Key: AxRibbon._P(src, "Key", ""),
               Menu: AxRibbon._P(src, "Menu", ""),
               Items: AxRibbon._P(src, "Items", ""),
               Value: AxRibbon._P(src, "Value", ""),
               Width: AxRibbon._P(src, "Width", ""),
               Checked: AxRibbon._P(src, "Checked", false),
               Disabled: AxRibbon._P(src, "Disabled", false),
               Hidden: AxRibbon._P(src, "Hidden", false),
               Click: AxRibbon._P(src, "Click", "")}
        if (it.Kind = "")
            it.Kind := IsObject(it.Menu) ? "menu" : "button"
        if (it.Id = "" && it.Kind != "sep" && it.Kind != "spacer")
            it.Id := groupId "i" n
        if (it.Label = "" && it.Kind = "button")
            it.Label := it.Id
        return it
    }

    ; --------------------------------------------------------------- markup
    ; The shell only; the tab strip and the panel are filled by the instance,
    ; so a designer that never shows its window still gets the right boxes.
    static Html(id, cfg := "") {
        o := (n, d := "") => AxRibbon._P(cfg, n, d)
        E := (x) => AxWindow._Esc(x)
        mode := StrLower(String(o("Mode", "office")))
        cls := "rib " mode
             . " style-" StrLower(String(o("Style", "fluent")))
             . " density-" StrLower(String(o("Density", "comfortable")))
             . (o("Flush", true) ? " flush" : "")
             . (o("Class", "") != "" ? " " E(o("Class", "")) : "")
        return '<div class="' cls '" id="' E(id) '" data-role="ribbon"'
             . (o("Css", "") != "" ? ' style="' E(o("Css", "")) '"' : "") '>'
             . '<div class="rib-bar" id="' E(id) '_bar">'
             . '<div class="rib-qat" id="' E(id) '_qat"></div>'
             . '<div class="rib-tabs" id="' E(id) '_tabs"></div>'
             . '<div class="rib-right" id="' E(id) '_right"></div></div>'
             . '<div class="rib-body" id="' E(id) '_body"></div></div>'
    }

    ; ------------------------------------------------------------ design time
    ; The same ribbon, as a block of HTML, with nobody's window behind it.
    ;
    ; AddRibbon builds the shell and fills it in from the instance it creates
    ; OnReady -- and a designer never shows its window, so OnReady never runs
    ; and the canvas got an empty dark band where the ribbon should be. Showing
    ; nothing is the worst possible answer: the control you just dropped looks
    ; broken before you have configured it.
    ;
    ; Rather than a second, simplified renderer that would drift away from the
    ; real one within a week, the real one is pointed somewhere else. AxRibPaper
    ; is the smallest thing Render() can write into -- named boxes that hold an
    ; innerHTML and swallow a style -- so the markup on the canvas is the markup
    ; in the window, off the same code path, including the tabs, the groups, the
    ; items and the quick access toolbar.
    ;
    ; What a paper cannot do is measure: everything measured (the overflow fold,
    ; the full-bleed margins, the floating panel's offset) reads zero and stops,
    ; which is the right answer for a picture of a ribbon.
    static DesignHtml(id, cfg := "") {
        paper := AxRibPaper(id)
        try AxRibbon(paper, id, cfg, true)
        catch as e
            return '<div class="rib" id="' AxWindow._Esc(id) '"><div class="rib-bar">'
                 . '<span class="rib-tab">' AxWindow._Esc(e.Message) '</span></div></div>'
        E := (x) => AxWindow._Esc(x)
        root := paper.Cell(id)
        return '<div class="' E(root.className) '" id="' E(id) '" data-role="ribbon"'
             . (AxRibbon._P(cfg, "Css", "") != "" ? ' style="' E(AxRibbon._P(cfg, "Css")) '"' : "") '>'
             . '<div class="rib-bar" id="' E(id) '_bar">'
             . '<div class="rib-qat" id="' E(id) '_qat">' paper.Html(id "_qat") '</div>'
             . '<div class="rib-tabs" id="' E(id) '_tabs">' paper.Html(id "_tabs") '</div>'
             . '<div class="rib-right" id="' E(id) '_right">' paper.Html(id "_right") '</div></div>'
             . '<div class="rib-body" id="' E(id) '_body">' paper.Html(id "_body") '</div></div>'
    }

    ; ----------------------------------------------------------- the instance
    __New(win, id, cfg := "", design := false) {
        this.W := win, this.Id := id
        ; drawn on a paper rather than in a window: no events to hook, nothing
        ; to measure, and the accent has to be written into the markup because
        ; there is no document to go back over afterwards
        this._design := design
        this.Cfg := IsObject(cfg) ? cfg : {}
        o := (n, d := "") => AxRibbon._P(this.Cfg, n, d)
        this.Mode := StrLower(String(o("Mode", "office")))
        this.Tabs := AxRibbon._Tabs(o("Tabs", []))
        this.File := o("File", "")                    ; the backstage tab, if any
        this.QuickAccess := o("QuickAccess", [])
        this.Collapsed := o("Collapsed", false)
        this.Floating := false
        this.Tab := ""
        this.KeyTips := false
        this._overflow := Map()                       ; group id -> true when collapsed
        this._tabClick := "", this._tabAt := 0        ; the double-click gesture
        this.Style := StrLower(String(o("Style", "fluent")))
        this.Density := StrLower(String(o("Density", "comfortable")))
        this.Colour := o("Color", o("Colour", ""))
        this._cbs := Map("command", [], "toggle", [], "tab", [], "launcher", [],
                         "collapse", [], "input", [])
        ; Handlers may be given in the config as well as attached later. The
        ; instance does not exist until the window is ready, so ctl.Component
        ; is blank while the page is still being built -- passing them here is
        ; the way to wire a ribbon up in one statement.
        for name in ["command", "toggle", "tab", "launcher", "collapse", "input"] {
            fn := o("On" StrUpper(SubStr(name, 1, 1)) SubStr(name, 2), "")
            if (IsObject(fn) && HasMethod(fn, "Call"))
                this._cbs[name].Push(fn)
        }
        if !design {
            AxRich.Use(win, "Ribbon")
            AxRich.Bind(win, id, this)
        }
        for t in this.Tabs
            if (this.Tab = "" && !t.Hidden && !t.Contextual)
                this.Tab := t.Id
        ; Tab: which one it opens on. Worth having in its own right, and it is
        ; what lets a designer show the tab you are editing rather than always
        ; the first one.
        if (o("Tab", "") != "" && IsObject(this.Find(o("Tab"))))
            this.Tab := o("Tab")
        if !design {
            this._Wire()
            ; the accent and the surface are painted from here, not from the
            ; sheet, so the ribbon has to hear when the window's look changes
            try win.OnLook((*) => this.Render())
        }
        this.Render()
    }
    ; --- events
    _On(name, fn) {
        this._cbs[name].Push(fn)
        return this
    }
    OnCommand(fn)  => this._On("command", fn)
    OnToggle(fn)   => this._On("toggle", fn)
    OnTab(fn)      => this._On("tab", fn)
    OnLauncher(fn) => this._On("launcher", fn)
    OnCollapse(fn) => this._On("collapse", fn)
    OnInput(fn)    => this._On("input", fn)
    _Fire(name, args) {
        for fn in this._cbs[name].Clone()
            try fn(args*)
        return this
    }

    _Wire() {
        w := this.W, id := this.Id
        w.On("click",    id, (el, ev) => this._Click(ev))
        w.On("dblclick", id, (el, ev) => this._DblClick(ev))
        w.On("keydown",  id, (el, ev) => this._Key(ev))
        w.On("change",   id, (el, ev) => this._Changed(el))
        ; the floating panel closes when the page is clicked elsewhere
        w.On("click", "*", (el, ev) => this._Outside(el))
        w.On("click", id "_dpanel", (el, ev) => this._DrawerClick(ev))
        this._resizeFn := (*) => this._Reflow()
        try w.Doc.parentWindow.attachEvent("onresize", this._resizeFn)
    }

    ; ---------------------------------------------------------------- render
    Render() {
        E := (x) => AxWindow._Esc(x)
        try this.W.El(this.Id).className := "rib " this.Mode
            . " style-" this.Style " density-" this.Density
            . (AxRibbon._P(this.Cfg, "Flush", true) ? " flush" : "")
            . (this.Collapsed ? " collapsed" : "")
            . (this.Floating ? " floating" : "")
            . (this.KeyTips ? " keytips" : "")
            . (AxRibbon._P(this.Cfg, "Class", "") != "" ? " " AxRibbon._P(this.Cfg, "Class") : "")
        this._Bar()
        this._Panel()
        this._Reflow()
        this._Accent()          ; after the markup: it paints elements that _Bar just wrote
        this._Bleed()
        this._FloatBox()
        return this
    }
    ; The rolled-up panel, floated over the page by a tab click.
    ;
    ; Both of its properties used to be constants in the sheet, and both were
    ; wrong. It sat at top: 36px -- the height of the tab strip -- which is a
    ; lie at every density and simply absurd in the two modes that HAVE no
    ; strip: in "titlebar" the tabs are up in the frame and in "strip" there
    ; are none, so the panel hung 36px down the document with a band of the
    ; page showing above it. And its surface was a hex per theme plus four
    ; sheets named by hand, so cozy, cyber, aurora and rpg painted #1b1b1b on
    ; a light window -- a black ribbon over a white page.
    ;
    ; Both are read off the window instead. The offset is whatever the strip
    ; actually measures (0 when there is none), and the surface is the page's
    ; own background, which is opaque, sheet-correct and theme-correct by
    ; construction -- the panel's tint then lands on it exactly as it does
    ; when the ribbon is docked.
    _FloatBox() {
        el := ""
        try el := this.W.El(this.Id "_body")
        if !IsObject(el)
            return this
        if (!this.Collapsed || !this.Floating) {
            try el.style.top := ""
            try el.style.backgroundColor := ""
            return this
        }
        try {
            bar := this.W.El(this.Id "_bar")
            h := 0
            ; a hidden strip measures 0, which is the answer we want
            if (IsObject(bar) && bar.currentStyle.display != "none")
                h := Round(bar.offsetHeight)
            el.style.top := h "px"
        }
        try {
            bg := this._PageBg()
            if (bg != "")
                el.style.backgroundColor := bg
        }
        return this
    }
    ; The nearest opaque background behind the ribbon. A sheet may leave the
    ; content pane transparent and paint the body, or paint neither and leave
    ; the frame to do it, so walk out until something answers.
    _PageBg() {
        try {
            el := this.W.El(this.Id)
            n := 0
            while (IsObject(el) && n++ < 8) {
                c := ""
                try c := el.currentStyle.backgroundColor
                c := String(c)
                if (c != "" && c != "transparent" && !InStr(c, "rgba(0, 0, 0, 0)")
                    && !InStr(c, "rgba(255, 255, 255, 0)"))
                    return c
                el := AxWindow._ParentEl(el)
            }
        }
        return ""
    }
    ; Full bleed, measured. The ribbon belongs to the window rather than to the
    ; page, so it cancels whatever padding the shell put round the content --
    ; and every stylesheet sets that padding differently, so it is read off the
    ; page instead of written into the component's sheet three times and
    ; guessed nine more.
    static _Px(v) {
        s := String(v)
        if RegExMatch(s, "(-?[\d.]+)", &m)
            return Round(m[1])
        return 0
    }
    _Bleed() {
        el := ""
        try el := this.W.El(this.Id)
        if !IsObject(el)
            return this
        if !AxRibbon._P(this.Cfg, "Flush", true) {
            try el.style.margin := ""
            return this
        }
        try {
            c := this.W.Doc.getElementById("content")
            if !IsObject(c)
                return this
            cs := c.currentStyle
            el.style.marginTop := (-AxRibbon._Px(cs.paddingTop)) "px"
            el.style.marginLeft := (-AxRibbon._Px(cs.paddingLeft)) "px"
            el.style.marginRight := (-AxRibbon._Px(cs.paddingRight)) "px"
            ; and the row the builder put it on carries a margin of its own,
            ; which is the gap between the ribbon and whatever follows it
            line := el.parentElement
            gap := 0
            if IsObject(line)
                gap := AxRibbon._Px(line.currentStyle.marginBottom)
            el.style.marginBottom := (-gap) "px"
        }
        return this
    }

    ; The accent is the window's, not a colour written into this sheet. A
    ; component stylesheet only gets AxSys.RecolourCss when the app has set an
    ; accent of its own, so a theme with a gold or green accent of its own
    ; would otherwise be stuck with a blue File tab. Color: overrides both.
    Accent {
        get {
            if (this.Colour != "")
                return this.Colour
            acc := ""
            try acc := this.W.Accent
            if (acc = "") {
                try acc := this.W.DefaultAccent(this.W.Theme)
            }
            return (acc != "") ? acc : "#60cdff"
        }
    }
    ; On a paper the accent goes into the markup as it is written (_Ac below);
    ; in a window it is painted over the markup afterwards, because Render is
    ; also what a theme change calls and the tabs must not be rebuilt for it.
    _Ac(what) {
        if !this._design
            return ""
        return ' style="background:' AxWindow._Esc(this.Accent) '"'
    }
    _Accent() {
        if this._design
            return this
        hex := this.Accent
        ; the File tab, the live tab's rule and the tick boxes are the only
        ; accent material; everything else is the theme's own surface
        try this.W.El(this.Id).style.color := ""
        try {
            f := this.W.Doc.querySelectorAll("#" this.Id " .rib-file")
            loop f.length
                f.item(A_Index - 1).style.background := hex
        }
        try {
            u := this.W.Doc.querySelectorAll("#" this.Id " .rib-rule")
            loop u.length
                u.item(A_Index - 1).style.background := hex
        }
        return this
    }

    ; --- the tab strip, the quick access toolbar, and whatever sits right
    _Bar() {
        E := (x) => AxWindow._Esc(x)
        tabs := ""
        if (this.Mode != "strip") {
            if IsObject(this.File)
                tabs .= '<span class="rib-file" data-file="1"'
                     .  (AxRibbon._P(this.File, "Color", "") != ""
                         ? ' style="background:' E(AxRibbon._P(this.File, "Color")) '"'
                         : this._Ac("file")) '>'
                     .  E(AxRibbon._P(this.File, "Label", "File")) '</span>'
            band := ""
            for t in this.Tabs {
                if t.Hidden
                    continue
                ; a contextual tab carries a coloured band above it, and a run
                ; of them that share a Set gets one band across the lot
                if (t.Contextual && t.Set != "" && t.Set != band) {
                    band := t.Set
                    tabs .= '<span class="rib-band"' (t.Colour != ""
                         ? ' style="background:' E(t.Colour) '"' : "") '>' E(t.Set) '</span>'
                } else if !t.Contextual
                    band := ""
                on := (this.Tab = t.Id)
                tabs .= '<span class="rib-tab' (on ? " on" : "")
                     .  (t.Contextual ? " ctx" : "") '" data-tab="' E(t.Id) '"'
                     .  (t.Colour != "" ? ' style="color:' E(t.Colour) '"' : "")
                     .  (t.Key != "" ? ' data-key="' E(t.Key) '"' : "") '>'
                     .  (t.Icon != "" ? '<span class="ico">&#x' E(t.Icon) ';</span>' : "")
                     .  E(t.Title)
                     .  (t.Key != "" ? '<span class="rib-key">' E(t.Key) '</span>' : "")
                     .  (on ? '<span class="rib-rule"' this._Ac("rule") '></span>' : "")
                     .  '</span>'
            }
        }
        ; An entry is the id of a command on the ribbon, or a small record of
        ; its own for something that is not on it (Save, Undo). Naming an id
        ; that does not exist used to drop the button silently.
        qat := ""
        for wanted in (this.QuickAccess is Array ? this.QuickAccess : []) {
            it := IsObject(wanted) ? AxRibbon._Item(wanted, "qat", A_Index) : this.Item(wanted)
            if !IsObject(it) {
                w := String(wanted)
                it := AxRibbon._Item({Id: w, Icon: AxRibbon.QatIcon(w),
                                      Label: StrUpper(SubStr(w, 1, 1)) SubStr(w, 2)}, "qat", A_Index)
            }
            qat .= '<span class="rib-q' (it.Disabled ? " disabled" : "") '" data-cmd="' E(it.Id) '"'
                .  ' data-tip="' E(it.Tip != "" ? it.Tip : it.Label) '">'
                .  '<span class="ico">&#x' E(it.Icon != "" ? it.Icon : "E700") ';</span></span>'
        }
        right := '<span class="rib-roll" data-roll="1" data-tip="'
               . (this.Collapsed ? "Show the ribbon" : "Roll the ribbon up")
               . '"><span class="ico">&#x' (this.Collapsed ? "E70D" : "E70E") ';</span></span>'
        ; The quick access toolbar goes in the window's own title bar, which is
        ; where every ribbon has put it since it stopped being a floating row
        ; of its own. QuickAccessIn: "bar" keeps it on the tab strip instead.
        inTitle := (StrLower(String(AxRibbon._P(this.Cfg, "QuickAccessIn", "titlebar"))) = "titlebar")
        try {
            ; in titlebar mode the tabs are handed to the frame -- but a
            ; paper has no frame, so they stay in the strip where they can be
            ; seen and clicked on the canvas
            this.W.El(this.Id "_tabs").innerHTML :=
                (this.Mode = "titlebar" && !this._design) ? "" : tabs
            ; and the quick access toolbar with them: it lives in the frame
            ; unless told otherwise, and a paper has no frame
            this.W.El(this.Id "_qat").innerHTML := (inTitle && !this._design) ? "" : qat
            this.W.El(this.Id "_right").innerHTML := (this.Mode = "strip") ? "" : right
        }
        this._Titlebar(tabs, qat, inTitle)
        return this
    }
    ; One call builds whatever of ours belongs in the frame: the quick access
    ; toolbar always, and the tab strip too in titlebar mode.
    _Titlebar(tabs, qat, inTitle) {
        if this._design
            return this
        items := []
        if (inTitle && qat != "")
            items.Push({Id: this.Id "_tbq", Kind: "html", Class: "rib-tbq", Html: qat})
        if (this.Mode = "titlebar")
            items.Push({Id: this.Id "_tbtabs", Kind: "html", Class: "rib-tbtabs",
                        Html: '<span class="rib-intitle" id="' AxWindow._Esc(this.Id)
                            . '_intitle">' tabs '</span>'})
        try this.W.TitleBar(items, {ShowTitle: true})
        if items.Length {
            this.W.On("click", this.Id "_intitle", (el, ev) => this._Click(ev))
            this.W.On("dblclick", this.Id "_intitle", (el, ev) => this._DblClick(ev))
            this.W.On("click", this.Id "_tbq", (el, ev) => this._Click(ev))
        }
        return this
    }

    ; --- the panel under the strip: the current tab's groups
    _Panel() {
        E := (x) => AxWindow._Esc(x)
        tab := this.Find(this.Tab)
        if !IsObject(tab) {
            try this.W.El(this.Id "_body").innerHTML := ""
            return this
        }
        line := (this.Mode = "simple" || this.Mode = "strip")
        html := '<div class="rib-panel' (line ? " line" : "") '" id="' E(this.Id) '_panel">'
        for grp in tab.Groups {
            if grp.Hidden
                continue
            html .= this._Group(grp, line)
        }
        html .= '<span class="rib-more" id="' E(this.Id) '_more" data-more="1"'
             .  ' data-tip="The groups that did not fit"><span class="ico">&#xE712;</span>'
             .  '<span class="rib-mt">More</span></span>'
        html .= '</div>'
        try this.W.El(this.Id "_body").innerHTML := html
        return this
    }
    _Group(grp, line) {
        E := (x) => AxWindow._Esc(x)
        items := ""
        col := ""                       ; small items stack three to a column
        rows := 0
        for it in grp.Items {
            if it.Hidden
                continue
            if (it.Kind = "sep") {
                items .= this._Flush(&col, &rows) '<span class="rib-vsep"></span>'
                continue
            }
            if (it.Kind = "spacer") {
                items .= this._Flush(&col, &rows) '<span class="rib-spacer"></span>'
                continue
            }
            if (it.Size = "large" || line) {
                items .= this._Flush(&col, &rows) this._Item(it, it.Size = "large" && !line)
                continue
            }
            col .= this._Item(it, false)
            if (++rows >= 3)
                items .= this._Flush(&col, &rows)
        }
        items .= this._Flush(&col, &rows)
        ; The folded face: one button with the group's name, which drops the
        ; whole group as a panel. A group that does not fit is not a group that
        ; should be clipped, and it is not a flat list on a menu either -- it
        ; is the same panel, somewhere else.
        fold := '<div class="rib-fold" data-fold="' E(grp.Id) '" data-tip="' E(grp.Title) '">'
              . '<span class="ico">&#x' E(grp.Icon != "" ? grp.Icon : "E712") ';</span>'
              . '<span class="rib-ft">' E(grp.Title) '</span>'
              . '<span class="rib-arrow">&#xE70D;</span></div>'
        return '<div class="rib-group" data-group="' E(grp.Id) '">'
             . '<div class="rib-gitems">' items '</div>'
             . (line ? "" : '<div class="rib-gfoot">' E(grp.Title)
                 . (grp.Launcher ? '<span class="rib-launch" data-launch="' E(grp.Id) '"'
                     . ' data-tip="More ' E(grp.Title) ' options">&#xE70D;</span>' : "")
                 . '</div>')
             . fold '</div>'
    }
    _Flush(&col, &rows) {
        if (col = "")
            return ""
        out := '<span class="rib-col">' col '</span>'
        col := "", rows := 0
        return out
    }
    ; --- one command, whatever kind it is
    _Item(it, large) {
        E := (x) => AxWindow._Esc(x)
        ico := (it.Icon != "") ? '<span class="ico">&#x' E(it.Icon) ';</span>' : ""
        key := (it.Key != "") ? '<span class="rib-key">' E(it.Key) '</span>' : ""
        tip := (it.Tip != "") ? ' data-tip="' E(it.Tip) '"' : ""
        cls := "rib-item " (large ? "large" : "small")
             . (it.Disabled ? " disabled" : "") (it.Checked ? " on" : "")
        switch it.Kind {
        case "label":
            return '<span class="rib-label">' E(it.Label) '</span>'
        case "input":
            return '<span class="rib-input"><input type="text" id="' E(this.Id) '_in_' E(it.Id) '"'
                 . ' data-input="' E(it.Id) '" value="' E(it.Value) '"'
                 . (it.Width != "" ? ' style="width:' E(it.Width) 'px"' : "") tip '></span>'
        case "color":
            return '<span class="' cls ' rib-colour" data-cmd="' E(it.Id) '" data-menu="colour"' tip '>'
                 . ico '<span class="rib-swatch" style="background:'
                 . E(it.Value != "" ? it.Value : "#60cdff") '"></span>'
                 . (large ? '<span class="rib-t">' E(it.Label) '</span>' : '<span class="rib-t">' E(it.Label) '</span>')
                 . '<span class="rib-arrow">&#xE70D;</span>' key '</span>'
        case "gallery":
            cells := ""
            for cell in (it.Items is Array ? it.Items : []) {
                cells .= '<span class="rib-cell" data-cell="' E(AxRibbon._P(cell, "Id", "")) '"'
                      .  ' data-cmd="' E(it.Id) '" data-tip="' E(AxRibbon._P(cell, "Label", "")) '"'
                      .  (AxRibbon._P(cell, "Color", "") != ""
                          ? ' style="background:' E(AxRibbon._P(cell, "Color")) '"' : "") '>'
                      .  (AxRibbon._P(cell, "Icon", "") != ""
                          ? '<span class="ico">&#x' E(AxRibbon._P(cell, "Icon")) ';</span>'
                          : E(AxRibbon._P(cell, "Label", ""))) '</span>'
            }
            return '<span class="rib-gallery" data-group-item="' E(it.Id) '">' cells '</span>'
        case "split":
            return '<span class="' cls ' split" data-split="' E(it.Id) '"' tip '>'
                 . '<span class="rib-main" data-cmd="' E(it.Id) '">' ico
                 . '<span class="rib-t">' E(it.Label) '</span></span>'
                 . '<span class="rib-drop" data-menu="' E(it.Id) '">'
                 . '<span class="rib-arrow">&#xE70D;</span></span>' key '</span>'
        case "menu":
            return '<span class="' cls '" data-menu="' E(it.Id) '"' tip '>' ico
                 . '<span class="rib-t">' E(it.Label) '</span>'
                 . '<span class="rib-arrow">&#xE70D;</span>' key '</span>'
        case "check":
            return '<span class="' cls ' check" data-toggle="' E(it.Id) '"' tip '>'
                 . '<span class="rib-box"></span>'
                 . '<span class="rib-t">' E(it.Label) '</span>' key '</span>'
        case "toggle":
            return '<span class="' cls ' toggle" data-toggle="' E(it.Id) '"' tip '>' ico
                 . (it.Label != "" ? '<span class="rib-t">' E(it.Label) '</span>' : "") key '</span>'
        }
        return '<span class="' cls '" data-cmd="' E(it.Id) '"' tip '>' ico
             . '<span class="rib-t">' E(it.Label) '</span>' key '</span>'
    }

    ; ------------------------------------------------------------- the model
    Find(tabId) {
        for t in this.Tabs
            if (t.Id = tabId)
                return t
        return ""
    }
    Group(groupId) {
        for t in this.Tabs
            for g in t.Groups
                if (g.Id = groupId)
                    return g
        return ""
    }
    ; Item("bold") anywhere in the ribbon, whichever tab it is on.
    Item(itemId) {
        for t in this.Tabs
            for g in t.Groups
                for it in g.Items
                    if (it.Id = itemId)
                        return it
        return ""
    }
    ; SetItem("bold", {Checked: true, Disabled: false, Label: "Bolder"})
    SetItem(itemId, patch) {
        it := this.Item(itemId)
        if !IsObject(it)
            return this
        for k, v in (patch is Map ? patch : patch.OwnProps())
            it.%k% := v
        this._Panel()
        this._Bar()
        this._Reflow()
        return this
    }
    Checked(itemId) {
        it := this.Item(itemId)
        return IsObject(it) ? it.Checked : false
    }
    Check(itemId, on := true) => this.SetItem(itemId, {Checked: on})
    Enable(itemId, on := true) => this.SetItem(itemId, {Disabled: !on})
    ShowItem(itemId, on := true) => this.SetItem(itemId, {Hidden: !on})

    ; --------------------------------------------------------------- the tabs
    ShowTab(tabId) {
        t := this.Find(tabId)
        if (!IsObject(t) || t.Hidden)
            return this
        this.Tab := tabId
        if this.Collapsed
            this.Floating := true
        this.Render()
        this._Fire("tab", [tabId, this])
        try this.W._FireValue(this.W.El(this.Id), tabId)
        return this
    }
    ; A contextual tab is declared with the rest and shown when it applies.
    ShowContext(tabId, on := true) {
        t := this.Find(tabId)
        if !IsObject(t)
            return this
        t.Hidden := !on
        if (!on && this.Tab = tabId) {
            for x in this.Tabs
                if (!x.Hidden && !x.Contextual) {
                    this.Tab := x.Id
                    break
                }
        }
        if (on && AxRibbon._P(this.Cfg, "FollowContext", true))
            this.Tab := tabId
        this.Render()
        return this
    }
    ShowGroup(groupId, on := true) {
        g := this.Group(groupId)
        if IsObject(g) {
            g.Hidden := !on
            this._Panel()
            this._Reflow()
        }
        return this
    }
    SetMode(mode) {
        m := StrLower(String(mode))
        ok := false
        for x in AxRibbon.Modes
            ok := ok || (x = m)
        if !ok
            return this
        this.Mode := m
        this.Floating := false
        this.Render()
        return this
    }
    static Styles := ["fluent", "classic", "flat", "outlined"]
    static Densities := ["comfortable", "compact", "roomy"]
    ; The look, independent of the shape: SetMode says how the ribbon is built,
    ; SetStyle how it is dressed, SetDensity how tightly it is packed.
    SetStyle(style) {
        st := StrLower(String(style))
        for x in AxRibbon.Styles
            if (x = st) {
                this.Style := st
                return this.Render()
            }
        return this
    }
    SetDensity(d) {
        v := StrLower(String(d))
        for x in AxRibbon.Densities
            if (x = v) {
                this.Density := v
                return this.Render()
            }
        return this
    }
    SetColor(hex) {
        this.Colour := hex
        return this.Render()
    }
    Collapse(on := true) {
        this.Collapsed := on
        this.Floating := false
        this.Render()
        this._Fire("collapse", [on, this])
        return this
    }
    ToggleCollapse() => this.Collapse(!this.Collapsed)

    ; --------------------------------------------------------------- overflow
    ; Groups that do not fit are folded, right to left, into a button that
    ; drops the whole group. Measuring is a handful of DOM reads per render,
    ; and only in the two modes that lay groups out side by side.
    ; How wide a folded group is at this density -- the CSS says 46, 40 and 54,
    ; plus its padding. Folding is decided against this rather than measured,
    ; because a group has to be folded before it can be measured folded.
    _FoldWidth() {
        switch this.Density {
        case "compact": return 50
        case "roomy":   return 64
        }
        return 56
    }
    _Reflow() {
        this._overflow := Map()
        if (this.Collapsed && !this.Floating)
            return this
        try {
            panel := this.W.El(this.Id "_panel")
            if !IsObject(panel)
                return this
            room := panel.getBoundingClientRect()
            wide := room.right - room.left - 14        ; the panel's own padding
            if (wide <= 0)
                return this
            ; every group, in order, at its full width
            ids := [], widths := []
            groups := panel.getElementsByTagName("div")
            loop groups.length {
                el := groups.item(A_Index - 1)
                gid := AxWindow._Attr(el, "data-group")
                if (gid = "")
                    continue
                AxWindow._SetClass(el, "folded", false)
                r := el.getBoundingClientRect()
                ids.Push(gid), widths.Push(r.right - r.left)
            }
            if !ids.Length
                return this
            ; Fold from the right until what is left fits. Marking everything
            ; past the limit in one pass is not enough: a folded group is much
            ; narrower, so folding one often makes room for the next, and the
            ; groups still open keep their own width whatever happens later.
            foldW := this._FoldWidth(), moreW := foldW
            n := ids.Length
            nOpen := n, folded := 0, gone := 0
            Total() {
                t := 0
                loop nOpen
                    t += widths[A_Index]
                return t + folded * foldW + ((folded || gone) ? moreW : 0)
            }
            ; Phase one: fold from the right, every group if it comes to that.
            ; Stopping at the last one leaves a group wider than the window and
            ; the row runs off the end.
            while (Total() > wide && nOpen > 0) {
                nOpen--
                folded++
            }
            ; Phase two: when even the folded buttons will not fit, the ones on
            ; the end come off the row entirely and live on the More menu.
            while (Total() > wide && folded > 0) {
                folded--
                gone++
            }
            ; Phases one and two are an estimate, and an estimate of a folded
            ; group's width is a constant that will be wrong at some font or
            ; density. Apply it, then MEASURE, and keep folding until the row
            ; really fits -- a handful of DOM reads, and no constant to get
            ; wrong.
            Apply() {
                this._overflow := Map(), this._hidden := Map()
                loop n {
                    if (A_Index <= nOpen)
                        continue
                    gid := ids[A_Index]
                    this._overflow[gid] := true
                    if (A_Index > nOpen + folded)
                        this._hidden[gid] := true
                }
                loop groups.length {
                    el := groups.item(A_Index - 1)
                    gid := AxWindow._Attr(el, "data-group")
                    if (gid = "")
                        continue
                    AxWindow._SetClass(el, "folded", this._overflow.Has(gid))
                    AxWindow._SetClass(el, "gone", this._hidden.Has(gid))
                }
                AxWindow._SetClass(this.W.El(this.Id "_more"), "show", this._hidden.Count > 0)
            }
            Fits() {
                edge := room.left
                loop groups.length {
                    el := groups.item(A_Index - 1)
                    gid := AxWindow._Attr(el, "data-group")
                    if (gid = "" || this._hidden.Has(gid))
                        continue
                    r := el.getBoundingClientRect()
                    edge := Max(edge, r.right)
                }
                if this._hidden.Count {
                    m := this.W.El(this.Id "_more")
                    if IsObject(m) {
                        r := m.getBoundingClientRect()
                        edge := Max(edge, r.right)
                    }
                }
                return edge <= room.right + 1
            }
            Apply()
            loop 16 {
                if Fits()
                    break
                if (nOpen > 0)
                    nOpen--, folded++
                else if (folded > 0)
                    folded--, gone++
                else
                    break
                Apply()
            }
        }
        return this
    }
    _MoreMenu(x := "", y := "") {
        items := []
        tab := this.Find(this.Tab)
        if !IsObject(tab)
            return this
        hid := this.HasOwnProp("_hidden") ? this._hidden : Map()
        for grp in tab.Groups {
            if (grp.Hidden || !hid.Has(grp.Id))
                continue
            sub := []
            for it in grp.Items {
                if (it.Hidden || it.Kind = "sep" || it.Kind = "spacer" || it.Kind = "label")
                    continue
                sub.Push({Label: (it.Label != "" ? it.Label : it.Id), Icon: it.Icon,
                          Checked: it.Checked, Disabled: it.Disabled, Click: this._CmdFn(it.Id)})
            }
            if sub.Length
                items.Push({Label: grp.Title, Icon: grp.Icon, Items: sub})
        }
        if items.Length
            this.W.ShowMenu(items, x, y)
        return this
    }
    _CmdFn(id) => (*) => this._Run(id)

    ; OpenGroup("clip"): the group, drawn exactly as it is in the panel, in a
    ; popover under its folded button. The markup comes from the same _Group
    ; that builds the panel, so a folded group is never a second design.
    OpenGroup(groupId) {
        grp := this.Group(groupId)
        if !IsObject(grp)
            return this
        this._popGroup := groupId
        anchor := ""
        try {
            nodes := this.W.El(this.Id "_panel").getElementsByTagName("div")
            loop nodes.length {
                el := nodes.item(A_Index - 1)
                if (AxWindow._Attr(el, "data-fold") = groupId) {
                    anchor := el
                    break
                }
            }
        }
        if !IsObject(anchor)
            return this
        id := this.Id "_drawer"
        try {
            old := this.W.El(id)
            if IsObject(old)
                old.id := ""
        }
        try anchor.id := id
        this.W.Popover(id, {On: "none", Class: "rib-pop", Align: "left", Gap: 2,
                            Build: (*) => this._DrawerHtml()})
        this.W.ShowPopover(id)
        return this
    }
    _DrawerHtml() {
        grp := this.Group(this.HasOwnProp("_popGroup") ? this._popGroup : "")
        if !IsObject(grp)
            return ""
        ; the same panel markup, in a sheet of its own
        return '<div class="rib rib-drawer style-' AxWindow._Esc(this.Style)
             . ' density-' AxWindow._Esc(this.Density) '" id="' AxWindow._Esc(this.Id) '_dpanel">'
             . '<div class="rib-panel">' this._Group(grp, false) '</div></div>'
    }

    ; ------------------------------------------------------------------ input
    _Hit(el, attr) {
        n := 0
        while (IsObject(el) && n++ < 8) {
            v := AxWindow._Attr(el, attr)
            if (v != "")
                return v
            try {
                if (el.id = this.Id)
                    return ""
            }
            el := AxWindow._ParentEl(el)
        }
        return ""
    }
    _Disabled(el) {
        n := 0
        while (IsObject(el) && n++ < 6) {
            if AxWindow._HasClass(el, "disabled")
                return true
            el := AxWindow._ParentEl(el)
        }
        return false
    }
    _Click(ev) {
        try el := ev.srcElement
        catch
            return
        if this._Disabled(el)
            return
        if this.KeyTips
            this.HideKeyTips()
        ; the roll-up chevron, and the backstage tab
        if (this._Hit(el, "data-roll") != "")
            return this.ToggleCollapse()
        if (this._Hit(el, "data-file") != "")
            return this._Fire("command", ["file", this.File, this])
        if ((fg := this._Hit(el, "data-fold")) != "")
            return this.OpenGroup(fg)
        if (this._Hit(el, "data-more") != "") {
            x := "", y := ""
            try x := ev.clientX, y := ev.clientY
            return this._MoreMenu(x, y)
        }
        if ((t := this._Hit(el, "data-tab")) != "") {
            ; Trident redraws the strip the moment the first click selects a
            ; tab, so the second click lands on a NEW element and arrives as a
            ; click rather than a dblclick -- the gesture has to be counted
            ; here or double-click-to-roll-up simply never happens.
            now := A_TickCount
            if (this._tabClick = t && now - this._tabAt <= DllCall("GetDoubleClickTime", "UInt")) {
                this._tabClick := "", this._tabAt := 0, this._dblAt := now
                return this.Collapse(!this.Collapsed)
            }
            this._tabClick := t, this._tabAt := now
            ; a click on the tab you are already on, while rolled up, closes
            ; the floating panel again
            if (this.Collapsed && this.Tab = t && this.Floating) {
                this.Floating := false
                return this.Render()
            }
            return this.ShowTab(t)
        }
        if ((g := this._Hit(el, "data-launch")) != "")
            return this._Fire("launcher", [g, this])
        ; a gallery cell reports the cell it was, through the item it is in
        if ((cell := this._Hit(el, "data-cell")) != "") {
            id := this._Hit(el, "data-cmd")
            it := this.Item(id)
            if IsObject(it) {
                it.Value := cell
                this._Panel()
            }
            return this._Fire("command", [id, (IsObject(it) ? it : cell), this])
        }
        ; a drop arrow, on its own or on the right of a split button
        if ((m := this._Hit(el, "data-menu")) != "") {
            if (m = "colour")
                return this._Colours(this._Hit(el, "data-cmd"), ev)
            return this._Menu(m, ev)
        }
        if ((tg := this._Hit(el, "data-toggle")) != "") {
            it := this.Item(tg)
            if IsObject(it) {
                it.Checked := !it.Checked
                this._Panel()
                this._Reflow()
                this._Fire("toggle", [tg, it.Checked, this])
                this._Fire("command", [tg, it, this])
            }
            return
        }
        if ((c := this._Hit(el, "data-cmd")) != "")
            return this._Run(c)
    }
    _Run(id) {
        it := this.Item(id)
        if (IsObject(it) && it.Disabled)
            return this
        ; an item may carry its own handler, which runs before the general one
        if (IsObject(it) && IsObject(it.Click) && HasMethod(it.Click, "Call")) {
            fn := it.Click
            try fn(id, it, this)
        }
        this._Fire("command", [id, (IsObject(it) ? it : ""), this])
        return this
    }
    _Menu(id, ev) {
        it := this.Item(id)
        if (!IsObject(it) || !IsObject(it.Menu))
            return this._Run(id)
        x := "", y := ""
        try x := ev.clientX, y := ev.clientY
        this.W.ShowMenu(it.Menu, x, y)
        return this
    }
    ; The swatch button's palette. A component of its own would be a heavier
    ; dependency than this deserves: it is a menu of coloured items.
    _Colours(id, ev) {
        it := this.Item(id)
        if !IsObject(it)
            return this
        list := (it.Items is Array && it.Items.Length) ? it.Items : AxRibbon.Swatches
        items := []
        for c in list {
            label := IsObject(c) ? AxRibbon._P(c, "Label", "") : String(c)
            hex := IsObject(c) ? AxRibbon._P(c, "Color", AxRibbon._P(c, "Colour", "")) : String(c)
            items.Push({Label: (label != "" ? label : hex), Click: this._ColourFn(id, hex),
                        Checked: (it.Value = hex)})
        }
        x := "", y := ""
        try x := ev.clientX, y := ev.clientY
        this.W.ShowMenu(items, x, y)
        return this
    }
    _ColourFn(id, hex) => (*) => this._SetColour(id, hex)
    _SetColour(id, hex) {
        it := this.Item(id)
        if IsObject(it) {
            it.Value := hex
            this._Panel()
            this._Reflow()
        }
        this._Fire("command", [id, (IsObject(it) ? it : hex), this])
        return this
    }
    static Swatches := ["#e74c3c", "#e67e22", "#f1c40f", "#2ecc71", "#1abc9c",
                        "#3498db", "#60cdff", "#9b59b6", "#ffffff", "#808080", "#202020"]
    ; The glyphs for the commands a quick access toolbar always has, so naming
    ; "save" is enough and the caller does not have to look one up.
    static QatGlyphs := Map("save", "E74E", "saveas", "E792", "open", "E8E5", "new", "E710",
                            "undo", "E7A7", "redo", "E7A6", "print", "E749", "find", "E721",
                            "cut", "E8C6", "copy", "E8C8", "paste", "E77F", "delete", "E74D",
                            "refresh", "E72C", "settings", "E713", "help", "E897")
    static QatIcon(id) => AxRibbon.QatGlyphs.Has(StrLower(id)) ? AxRibbon.QatGlyphs[StrLower(id)] : "E700"
    _Changed(el) {
        id := AxWindow._Attr(el, "data-input")
        if (id = "")
            return
        v := ""
        try v := el.value
        it := this.Item(id)
        if IsObject(it)
            it.Value := v
        this._Fire("input", [id, v, this])
    }
    ; Double-click a tab to roll up, and again to roll down. The classic
    ; gesture, and the reason the strip and the panel are separate elements.
    ; Trident does still deliver a real dblclick when the strip happened not to
    ; be redrawn; _Click counts the pair, so this only has to avoid acting twice.
    _DblClick(ev) {
        try el := ev.srcElement
        catch
            return
        if (this._Hit(el, "data-tab") = "")
            return
        if (this.HasOwnProp("_dblAt") && A_TickCount - this._dblAt < 700)
            return
        this._tabClick := "", this._dblAt := A_TickCount
        this.Collapse(!this.Collapsed)
        try ev.returnValue := false
    }
    ; A command chosen in the drawer runs and then puts the drawer away, the
    ; way a menu does.
    _DrawerClick(ev) {
        this._Click(ev)
        try {
            el := ev.srcElement
            if (this._Hit(el, "data-cmd") != "" || this._Hit(el, "data-toggle") != ""
                || this._Hit(el, "data-cell") != "")
                this.W.ClosePopover()
        }
    }
    ; A floating panel goes away when the page is clicked anywhere else.
    _Outside(el) {
        if (!this.Floating || !this.Collapsed)
            return
        n := 0
        while (IsObject(el) && n++ < 14) {
            try {
                if (el.id = this.Id || el.id = this.Id "_intitle")
                    return
            }
            el := AxWindow._ParentEl(el)
        }
        this.Floating := false
        this.Render()
    }

    ; ------------------------------------------------------------- key tips
    ; Alt belongs to the app -- the page's wildcard keydown is a single hook
    ; and an app may already own it -- so the ribbon does not take it. Bind it
    ; where you bind the rest:
    ;
    ;     g.On("keydown", "*", (el, ev) => (ev.keyCode = 18 ? rib.ShowKeyTips() : ""))
    ; While the tips are up the ribbon owns the page's keyboard, because the
    ; focus is wherever the user left it -- a text box, usually -- and a
    ; component's own keydown only fires when the component has the focus.
    ; The page's wildcard hook is a single slot an app may already be using,
    ; so it is borrowed and handed straight back, never clobbered.
    ShowKeyTips(on := true) {
        on := on ? true : false
        if (on = this.KeyTips)
            return this
        if on {
            this._prevKey := ""
            try {
                if (this.W.Hooks.Has("keydown") && this.W.Hooks["keydown"].Has("*"))
                    this._prevKey := this.W.Hooks["keydown"]["*"]
            }
            this.W.On("keydown", "*", (el, ev) => this._TipKey(ev))
        } else {
            try {
                if (this.HasOwnProp("_prevKey") && this._prevKey != "")
                    this.W.On("keydown", "*", this._prevKey)
                else
                    this.W.Off("keydown", "*")
            }
            this._prevKey := ""
        }
        this.KeyTips := on
        this._keys := ""
        ; No focus() here: this runs from inside a keydown, and moving the
        ; focus there pumps messages back through the key queue.
        this.Render()
        return this
    }
    ; Escape and Alt put the tips away; a letter runs its command; anything
    ; else goes on to whoever owned the keyboard before we borrowed it.
    _TipKey(ev) {
        code := 0
        try code := ev.keyCode
        if (code = 27 || code = 18) {
            this.HideKeyTips()
            try ev.returnValue := false
            return
        }
        if this._TipHit(code) {
            try ev.returnValue := false
            return
        }
        fn := (this.HasOwnProp("_prevKey") ? this._prevKey : "")
        if fn {
            el := ""
            try el := ev.srcElement
            try fn(el, ev)
        }
    }
    ; The tab keys first, then the commands on the tab you are looking at.
    ; Returns true when the key was ours.
    _TipHit(code) {
        ch := ""
        try ch := Chr(code)
        if !RegExMatch(String(ch), "^[A-Za-z0-9]$")
            return false
        for t in this.Tabs
            if (!t.Hidden && t.Key != "" && StrUpper(t.Key) = StrUpper(ch)) {
                this.HideKeyTips()
                this.ShowTab(t.Id)
                return true
            }
        tab := this.Find(this.Tab)
        if IsObject(tab)
            for g in tab.Groups
                for it in g.Items
                    if (!it.Hidden && !it.Disabled && it.Key != ""
                        && StrUpper(it.Key) = StrUpper(ch)) {
                        this.HideKeyTips()
                        if (it.Kind = "toggle" || it.Kind = "check") {
                            it.Checked := !it.Checked
                            this._Panel()
                            this._Fire("toggle", [it.Id, it.Checked, this])
                        }
                        this._Run(it.Id)
                        return true
                    }
        return false
    }
    HideKeyTips() => this.ShowKeyTips(false)
    ToggleKeyTips() => this.ShowKeyTips(!this.KeyTips)
    _Key(ev) {
        try code := ev.keyCode
        catch
            return
        if (code = 27) {
            if this.KeyTips
                return this.HideKeyTips()
            if (this.Floating) {
                this.Floating := false
                return this.Render()
            }
            return
        }
        ; the arrows walk the tabs, which is what a tab strip is expected to do
        if (code = 37 || code = 39)
            return this._Step(code = 39 ? 1 : -1)
        if this.KeyTips
            this._TipHit(code)
    }
    _Step(by) {
        list := []
        for t in this.Tabs
            if !t.Hidden
                list.Push(t.Id)
        if !list.Length
            return this
        at := 1
        for i, id in list
            if (id = this.Tab)
                at := i
        to := Mod(at - 1 + by + list.Length, list.Length) + 1
        return this.ShowTab(list[to])
    }

    ; ------------------------------------------------------------------ AxGui
    static _Add(container, opts, data) {
        o := container._Opt(opts, "rib")
        cfg := {}
        if IsObject(data)
            for k, v in (data is Map ? data : data.OwnProps())
                cfg.%k% := v
        Fall(name, value) => cfg.HasOwnProp(name) ? "" : cfg.%name% := value
        for m in AxRibbon.Modes
            if o.Flags.Has(m)
                cfg.Mode := m
        if o.KV.Has("mode")
            cfg.Mode := StrLower(o.KV["mode"])
        Fall("Mode", "office")
        if o.Flags.Has("collapsed")
            cfg.Collapsed := true
        Fall("Collapsed", false)
        if o.Flags.Has("inset")                 ; leave the page's margins alone
            cfg.Flush := false
        Fall("Flush", true)
        for x in AxRibbon.Styles
            if o.Flags.Has(x)
                cfg.Style := x
        if o.KV.Has("style2")
            cfg.Style := StrLower(o.KV["style2"])
        if o.KV.Has("look")
            cfg.Style := StrLower(o.KV["look"])
        Fall("Style", "fluent")
        for x in AxRibbon.Densities
            if o.Flags.Has(x)
                cfg.Density := x
        if o.KV.Has("density")
            cfg.Density := StrLower(o.KV["density"])
        Fall("Density", "comfortable")
        if o.KV.Has("color")
            cfg.Color := o.KV["color"]
        ; not Style: that is the ribbon's own look, below
        cfg.Css := (o.W != "" ? "width:" o.W "px;" : "")
                 . (o.Top != "" ? "margin-top:" o.Top "px;" : "")
                 . (o.KV.Has("style") ? o.KV["style"] : "")
        cfg.Class := ((o.W = "" || o.Flags.Has("fill")) ? "fill" : "")
                   . (o.KV.Has("class") ? " " o.KV["class"] : "")
        ; Design: the whole ribbon, drawn now, for a canvas whose window is
        ; never shown -- see DesignHtml.
        if AxRibbon._P(cfg, "Design", false)
            return container._Reg(o, "Ribbon", AxRibbon.DesignHtml(o.Id, cfg))
        c := container._Reg(o, "Ribbon", AxRibbon.Html(o.Id, cfg))
        container.G.OnReady((w) => AxRibbon(w, o.Id, cfg))
        return c
    }
}

; =============================================================================
;  AxRibPaper -- a window the ribbon can draw on when there is no window.
;
;  The designer's canvas is built as text: there is no document to look things
;  up in and nothing has a size yet. So the ribbon is handed one of these
;  instead of an AxWindow. It answers El() with a box that remembers what was
;  written into it and shrugs off everything else -- a style assignment, a
;  class, a measurement -- so Render() runs to the end and leaves its markup
;  behind in the boxes.
;
;  Everything measured answers zero, and every caller of a measurement already
;  treats zero as "not laid out yet" and stops. That is deliberate: a picture
;  of a ribbon has no overflow to fold and no page margins to cancel.
; =============================================================================
class AxRibPaper {
    ; The boxes the shell has, and only those. Asking for anything else -- the
    ; panel inside the body, say -- answers "not there", exactly as a document
    ; would before that markup had been put into it, which is what stops the
    ; measuring code measuring a box that does not exist yet.
    __New(id) {
        this._cells := Map()
        for suffix in ["", "_bar", "_qat", "_tabs", "_right", "_body"]
            this._cells[id suffix] := AxRibPaperEl()
        this.Doc := AxRibPaperDoc()
        this.Accent := ""
    }
    Cell(id) => this._cells.Has(id) ? this._cells[id] : AxRibPaperEl()
    El(id) => this._cells.Has(id) ? this._cells[id] : ""
    Html(id) => this._cells.Has(id) ? this._cells[id].innerHTML : ""
    ; the three the ribbon asks a window for
    On(*) => this
    OnLook(*) => this
    TitleBar(*) => this
}
class AxRibPaperEl {
    __New() {
        this.innerHTML := ""
        this.className := ""
        this.id := ""
        this.style := AxRibPaperStyle()
        this.offsetHeight := 0
        this.offsetWidth := 0
        this.parentElement := ""
    }
    ; nothing on a paper has been laid out, and an empty rectangle is what
    ; every caller of this already tests for
    getBoundingClientRect() => {left: 0, top: 0, right: 0, bottom: 0}
}
; A style object takes whatever is set on it and keeps it; currentStyle is
; deliberately absent, so a read of a computed value throws and the measuring
; code takes the branch it takes when the browser has not laid out yet.
class AxRibPaperStyle {
    __New() => this.DefineProp("__Set", {Call: (this_, name, params, value) =>
        this_.DefineProp(name, {Value: value})})
}
class AxRibPaperDoc {
    getElementById(id) => ""
    querySelectorAll(sel) => AxRibPaperList()
    parentWindow => ""
}
class AxRibPaperList {
    length := 0
    item(i) => ""
}
