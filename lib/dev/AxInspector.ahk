#Requires AutoHotkey v2.0
; It uses AxGui, AxWindow, AxRich and the DataView component, so it says so
; rather than relying on having been included after them. AxRichAll pulls in
; AxRich, which pulls in AxGui, which pulls in AxWindow -- and AHK includes any
; given file only once, so this costs nothing when they are already loaded.
#Include %A_LineFile%\..\..\AxRichAll.ahk
; =============================================================================
;  AxInspector — a DevTools-style inspector for an AxWindow.
;
;      #Include lib\dev\AxInspector.ahk        ; development only
;
;  That include is the whole installation. F12 or Ctrl+Shift+I opens the
;  inspector for whichever AxWindow is in front, and closes it again; press it
;  over the inspector itself and it acts on the window being inspected. There
;  is nothing to call and, more to the point, nothing to remember to take out.
;  AxInspector.Attach(g) still works if a script wants it open from the start.
;
;  The hotkeys are registered by static __New, which AHK runs when the class is
;  loaded, and they are scoped by a HotIf callback to windows that are actually
;  AxWindows -- so F12 keeps working normally in every other application.
;
;  A development tool, meant never to reach a build: nothing in the library
;  includes it and it carries no ;@Ahk2Exe-AddResource line, so leaving the
;  #Include out is the whole of "not shipping it".
;
;  Why this is small when Chrome's is not: DevTools talks to another process
;  over a debugger protocol. Here the inspector is a second window in the same
;  AHK process, so it holds the target and reads target.Doc directly. No
;  protocol, nothing to serialise, no lag.
;
;  Laid out the way DevTools is: tree on the left, a tabbed detail panel on the
;  right, the ancestor trail along the bottom. What it adds that a real
;  inspector cannot is the AHK tab -- the AxGui control, the rich component
;  bound to the element, and the control's live value.
;
;  It touches nothing in the core. Picking polls elementFromPoint rather than
;  hooking the target's event router, so inspecting cannot change how the app
;  behaves.
;
;  Known limits, by design for now:
;    • Both windows share one STA thread, so a busy app freezes the inspector.
;    • The tree is a snapshot; Refresh after the page changes.
;    • Styles are computed values. Which rule won is the next stage.
; =============================================================================

class AxInspector {
    static _open := Map()                      ; target hwnd -> inspector
    ; target hwnd -> "queued" | "building", for the gap between F12 being seen
    ; and the inspector reaching _open. Both halves of opening are deferred and
    ; the Gui constructor pumps messages, so without this a second F12 inside
    ; that window finds _open still empty and builds a second inspector.
    static _opening := Map()

    ; --------------------------------------------------------- installation
    ; Runs once, when the class is loaded, so an #Include is all it takes.
    static __New() {
        AxInspector._PatchOrigins()
        try {
            HotIf((*) => AxInspector._ActiveTarget() != "")
            Hotkey("F12", (*) => AxInspector.Toggle(), "On")
            Hotkey("^+i", (*) => AxInspector.Toggle(), "On")
            HotIf()
        }
    }
    ; ---------------------------------------------------- handler provenance
    ; A Func object carries no source location, so the only moment the origin
    ; of a handler is knowable is the moment it is registered -- while the
    ; registering line is still on the call stack. Error("", -N) reports the
    ; file and line N frames up, so wrapping the two funnels every handler
    ; passes through and walking out past the library's own frames records
    ; where each one was actually written.
    ;
    ; This is why the inspector is a development-only include: it patches two
    ; prototypes. Both wrappers do nothing but note the site and call straight
    ; through, and the patch happens once, before any app code runs.
    static _sites := Map()                     ; target -> Map("kind|id" -> "file:line")

    static _PatchOrigins() {
        static done := false
        if done
            return
        done := true
        ; AxGui._Hook is where every control event funnels (OnClick -> OnEvent
        ; -> _Hook), whether it is wired now or queued until the page is ready
        try {
            h := AxGui.Prototype.GetOwnPropDesc("_Hook").Call
            AxGui.Prototype.DefineProp("_Hook", {Call: (self, kind, id, fn) =>
                (AxInspector._Note(self, kind, id, true), h(self, kind, id, fn))})
        }
        ; and AxWindow.On is the raw path a script uses directly
        try {
            o := AxWindow.Prototype.GetOwnPropDesc("On").Call
            AxWindow.Prototype.DefineProp("On", {Call: (self, type, id, fn) =>
                (AxInspector._Note(self, type, id, false), o(self, type, id, fn))})
        }
    }
    ; force:=false is the "only if we do not already know" case. A hook queued
    ; before the page was ready is flushed later by the library itself, and
    ; that flush would otherwise overwrite the real registration site with
    ; whichever line happened to call Show().
    static _Note(self, kind, id, force) {
        try {
            if !AxInspector._sites.Has(self)
                AxInspector._sites[self] := Map()
            m := AxInspector._sites[self]
            k := kind "|" id
            if (!force && m.Has(k))
                return
            site := AxInspector._CallerSite()
            if (site != "")
                m[k] := site
        }
    }
    static SiteOf(target, kind, id) {
        try {
            if AxInspector._sites.Has(target) {
                m := AxInspector._sites[target]
                if m.Has(kind "|" id)
                    return m[kind "|" id]
            }
        }
        return ""
    }
    ; the first frame that is not inside lib\ -- i.e. the app's own code
    static _CallerSite() {
        loop 12 {
            try {
                e := Error("", -A_Index)
                f := String(e.File)
                if (f != "" && !InStr(f, "\lib\") && !InStr(f, "/lib/")) {
                    SplitPath(f, &nm)
                    return nm ":" e.Line
                }
            }
        }
        return ""
    }

    ; The AxWindow behind the foreground window: every AxWindow registers
    ; itself in AxWindow._byHwnd, so this is a lookup rather than a guess. If
    ; the front window is an inspector, the answer is the window it inspects,
    ; which is what makes F12 toggle from either side.
    static _ActiveTarget() {
        try {
            h := WinExist("A")
            if !AxWindow._byHwnd.Has(h)
                return ""
            w := AxWindow._byHwnd[h]
            for , ins in AxInspector._open {
                same := false
                try same := (ins.W = w)
                if same
                    return ins.T
            }
            return w
        }
        return ""
    }
    ; Both halves are deferred onto a fresh thread with a negative SetTimer.
    ; A hotkey fires as an interrupting pseudo-thread, and F12 arrives while
    ; the window's subclass proc is still on the stack feeding that very key to
    ; Trident. Destroying the Gui from inside it unwinds into DefSubclassProc
    ; on a window that no longer exists -- an 0xc0000005 with the subclass proc
    ; at the top of the call stack, every time. Creating is deferred for the
    ; same reason: Gui creation pumps messages.
    static Toggle() {
        t := AxInspector._ActiveTarget()
        if !IsObject(t)
            return
        h := 0
        try h := t.Gui.Hwnd
        if (h && AxInspector._open.Has(h)) {
            ins := AxInspector._open[h]
            SetTimer((*) => ins.Close(), -1)
            return
        }
        if (h && AxInspector._opening.Has(h))
            return                             ; one is already on its way
        if h
            AxInspector._opening[h] := "queued"
        SetTimer((*) => AxInspector.Attach(t), -1)
    }

    static Attach(target, opts := "") {
        h := 0
        try h := target.Gui.Hwnd
        if (h && AxInspector._open.Has(h)) {
            AxInspector._opening.Delete(h)
            ins := AxInspector._open[h]
            try WinActivate("ahk_id " ins.W.Gui.Hwnd)
            return ins
        }
        ; re-entered while the constructor below was pumping messages
        if (h && AxInspector._opening.Get(h, "") = "building")
            return ""
        if h
            AxInspector._opening[h] := "building"
        ins := ""
        try {
            ins := AxInspector(target, opts)
            if h
                AxInspector._open[h] := ins
        } finally {
            if h
                AxInspector._opening.Delete(h)
        }
        return ins
    }

    __New(target, opts := "") {
        o := (n, d := "") => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        this.T := target
        this.Nodes := []                       ; index -> element; a row's key
        this.Sel := ""
        this.SelIdx := 0
        this.Picking := false
        this.Tab := 1                          ; only the visible tab is filled
        this.Hot := ""                         ; element under the cursor while picking
        this._pickT0 := 0                      ; when picking started, for the watchdog
        this.Mon := false                      ; event monitor attached?
        this._monFns := Map()
        this.ById := Map()                     ; uniqueID -> index into Nodes
        this._rules := ""                      ; flattened stylesheet snapshot
        this._propNames := ""                  ; computed-style property names
        this.Drawer := false                   ; console drawer open?
        this.Hist := []                        ; console history, newest last
        this.HistAt := 0

        title := "Inspector"
        try title .= " — " target.Title
        w := AxGui({Title: title, Theme: "dark", Width: Integer(o("Width", 1180)),
                    Height: Integer(o("Height", 720)), MinWidth: 900, MinHeight: 520,
                    Nav: false, Shell: false, ExitOnClose: false, NoActivate: true})
        this.W := w
        w.AddPage("elements", "Elements", "E8A5")
        this._Build(w)
        w.Show()
        ; Opens at its own size. Maximized:true is there for a second monitor,
        ; but taking the whole screen uninvited is not the tool's call to make.
        if o("Maximized", false)
            try w.Maximize()
        ; The document loads asynchronously, so nothing may be touched until it
        ; is ready: El() would hand back "" and every write would fail. This is
        ; why the first version threw on innerHTML.
        w.OnReady((*) => (this._Skin(), this._Mount(), this._Wire(), this._WhenTargetReady()))
        return this
    }

    ; Attach(g) is usually written before g.Show(), so the target may have no
    ; document yet. OnReady fires immediately if it is already up, so this is
    ; correct either way.
    _WhenTargetReady() {
        try {
            this.T.OnReady((*) => (this.Refresh(), this.ApplyCss()))
            return
        }
        this.Refresh()
    }

    ; ------------------------------------------------------------------ layout
    ; The chrome is built here as one block of markup rather than out of pages,
    ; cards and lines.
    ;
    ; That is deliberate. AxGui's page layout is built for settings pages: every
    ; control sits in a line, containers auto-enter, and a tab container always
    ; begins a line of its own -- so a tree and a tabbed panel can never be put
    ; side by side in it. Trying to force that with CSS meant fighting the
    ; layout on every change. The two grids are mountable on their own
    ; (AxDataView.Html emits the markup, the constructor gives it behaviour), so
    ; the shell is written out directly and the grids are dropped into it. The
    ; result is a fixed frame that owns the whole client area and does not care
    ; what the page layout would rather do.
    _Build(w) {
        this.TreeCfg := {
            Columns: [{Key: "label", Title: "Element", Width: 330, Icon: true},
                      {Key: "size", Title: "Size", Width: 78, Sort: false},
                      {Key: "kind", Title: "From", Width: 92, Sort: false}],
            Rows: [], Tree: true, Select: "single", Height: 400,
            SearchPlaceholder: "Filter…", Empty: "Press Refresh."}
        this.CssCfg := {
            Columns: [{Key: "prop", Title: "Property", Width: 200},
                      {Key: "val", Title: "Value", Width: 250, Sort: false}],
            Rows: [], Select: "single", Height: 400, Tools: true,
            SearchPlaceholder: "Filter…", Empty: "Select an element."}

        B := (act, label) => "<span class='ins-btn' data-act='" act "' id='ins" act "'>"
                           . label "</span>"
        ; AddClass("insmon", ...) needs the id to be exactly that
        T := (n, label) => "<span class='ins-tab" (n = 1 ? " on" : "") "' data-tab='" n "'>"
                         . label "</span>"
        html := "<div id='insRoot'>"
              . "<div id='insBar'>"
              . B("pick", "Select") B("refresh", "Refresh")
              . B("expand", "Expand") B("collapse", "Collapse") B("mon", "Monitor")
              . B("drawer", "Console")
              . "<span class='ins-tip'>point at the window, click to pick, Esc to stop"
              .   " &nbsp;&middot;&nbsp; F12 closes</span>"
              . "</div>"
              . "<div id='insLeft'>" AxDataView.Html("tree", this.TreeCfg) "</div>"
              . "<div id='insRight'>"
              .   "<div id='insTabs'>" T(1, "Element") T(6, "Styles") T(2, "Computed")
              .     T(3, "Layout") T(5, "Properties") T(4, "AHK") T(7, "CSS") "</div>"
              .   "<div class='ins-pane' id='insP1'><div id='attrs'>"
              .     "<span class='ins-dim'>Nothing selected.</span></div></div>"
              .   "<div class='ins-pane' id='insP2' style='display:none'>"
              .     AxDataView.Html("css", this.CssCfg) "</div>"
              .   "<div class='ins-pane' id='insP3' style='display:none'><div id='box'>"
              .     "<span class='ins-dim'>Nothing selected.</span></div></div>"
              .   "<div class='ins-pane' id='insP4' style='display:none'><div id='ahk'>"
              .     "<span class='ins-dim'>Nothing selected.</span></div></div>"
              .   "<div class='ins-pane' id='insP6' style='display:none'><div id='rules'>"
              .     "<span class='ins-dim'>Nothing selected.</span></div></div>"
              .   "<div class='ins-pane' id='insP5' style='display:none'><div id='props'>"
              .     "<span class='ins-dim'>Nothing selected.</span></div></div>"
              .   "<div class='ins-pane' id='insP7' style='display:none'>"
              .     "<div id='cssBar'>"
              .       "<span class='ins-act' data-act='cssseed'>From selection</span>"
              .       "<span class='ins-act' data-act='cssapply'>Apply</span>"
              .       "<span class='ins-act' data-act='cssclear'>Clear</span>"
              .       "<span class='ins-act' data-act='csscopy'>Copy</span>"
              .       "<span class='ins-act' data-act='csssave'>Save</span>"
              .       "<span class='ins-act' data-act='cssload'>Load</span>"
              .       "<label class='ins-lv'><input type='checkbox' id='cssAuto' checked>"
              .         " live</label>"
              .       "<span id='cssStat' class='ins-dim'></span></div>"
              ; The textarea sits inside a positioned wrapper and fills it with
              ; percentages. IE11 treats a form control as replaced content:
              ; given left/right/top/bottom but no explicit size it ignores
              ; them and uses the intrinsic cols/rows box -- which is how this
              ; came out 150x20 with two scrollbars. rows/cols stay as a
              ; readable fallback if the percentages ever fail too.
              .     "<div id='cssWrap'><textarea id='cssEdit' rows='24' cols='60'"
              .     " spellcheck='false' wrap='off' placeholder='"
              .     "Type CSS here, or press From selection for a rule that beats the theme."
              .     "'></textarea></div>"
              .   "</div>"
              . "</div>"
              ; The console is a drawer across the foot of the window, the way
              ; DevTools has had it since it stopped being a tab: it stays open
              ; while any panel is in use, which is the whole point of it.
              . "<div id='insDrawer'>"
              .   "<div id='insDrawerBar'>Console"
              .     "<span class='ins-x' data-act='drawer'>&times;</span></div>"
              .   "<div id='insLog'></div>"
              .   "<div id='insCmdRow'><span id='insCaret'>&rsaquo;</span>"
              .     "<input id='insCmd' type='text' spellcheck='false'"
              .     " placeholder='type help'></div></div>"
              . "<div id='insFoot'><span id='insCount'></span>"
              .   "<span id='crumbs'><span class='ins-dim'>no selection</span></span></div>"
              . "</div>"
        w.AddHtml("vshell", html)
    }

    ; The grids only exist as markup until they are given behaviour, which is
    ; what the constructor does -- the same thing AddDataView arranges when a
    ; page builds one the ordinary way.
    _Mount() {
        try AxDataView(this.W, "tree", this.TreeCfg)
        try AxDataView(this.W, "css", this.CssCfg)
    }

    ; Chrome DevTools' own palette and proportions: #202124 ground, #292a2d
    ; chrome, #3c4043 rules, #8ab4f8 for anything active, and the four box
    ; model colours it has used for years -- tan margin, yellow border, green
    ; padding, blue content. Row heights and the 11px UI font are DevTools' too.
    _Skin() {
        C := "#202124", C2 := "#292a2d", LN := "#3c4043", FG := "#e8eaed", DIM := "#9aa0a6"
        AC := "#8ab4f8", HOV := "#35363a", SEL := "#394457"
        this.W.SetExtraCss("axinspector",
        ; -- the window is the tool: no page chrome, no card, no heading ------
          "body, #content { background: " C " !important; color: " FG " !important; }"
        . "#insRoot { position: fixed; left: 0; right: 0; top: 32px; bottom: 0;"
        . " font: 11px 'Segoe UI', sans-serif; background: " C "; }"
        . "#titlebar { background: " C2 "; border-bottom: 1px solid " LN "; }"
        . "#content { padding: 0 !important; }"
        . "h1 { display: none !important; }"
        . ".card, .ax-line { background: none !important; border: none !important;"
        . " padding: 0 !important; margin: 0 !important; }"
        ; -- toolbar ---------------------------------------------------------
        . "#insBar { position: absolute; left: 0; right: 0; top: 0; height: 27px;"
        . " line-height: 27px; padding: 0 4px; white-space: nowrap;"
        . " background: " C2 "; border-bottom: 1px solid " LN "; }"
        . ".ins-btn { display: inline-block; height: 19px; line-height: 17px; padding: 0 8px;"
        . " margin-right: 2px; border: 1px solid transparent; border-radius: 2px;"
        . " color: " DIM "; cursor: default; -ms-user-select: none; user-select: none; }"
        . ".ins-btn:hover { background: " HOV "; color: " FG "; }"
        . ".ins-btn.on { background: rgba(138,180,248,.20); border-color: " AC "; color: " AC "; }"
        . ".ins-tip { opacity: .38; margin-left: 8px; }"
        ; -- the two panes ---------------------------------------------------
        . "#insLeft { position: absolute; left: 0; top: 27px; bottom: 22px; width: 46%;"
        . " min-width: 420px; overflow: hidden; }"
        . "#insRight { position: absolute; left: 46%; right: 0; top: 27px; bottom: 22px;"
        . " overflow: hidden; border-left: 1px solid " LN "; background: " C "; }"
        ; -- sub-tabs, DevTools' underline ------------------------------------
        . "#insTabs { position: absolute; left: 0; right: 0; top: 0; height: 26px;"
        . " line-height: 26px; padding: 0 2px; white-space: nowrap;"
        . " background: " C2 "; border-bottom: 1px solid " LN "; }"
        . ".ins-tab { display: inline-block; height: 25px; padding: 0 10px; cursor: default;"
        . " -ms-user-select: none; user-select: none; color: " DIM "; }"
        . ".ins-tab:hover { color: " FG "; background: " HOV "; }"
        . ".ins-tab.on { color: " FG "; background: " C "; border-bottom: 2px solid " AC "; }"
        . ".ins-pane { position: absolute; left: 0; right: 0; top: 26px; bottom: 0;"
        . " overflow: auto; padding: 8px 10px; }"
        . "#insP2, #insP5 { padding: 0; }"
        ; -- the grids, dense and flush ---------------------------------------
        . ".dv-frame { border: none !important; border-radius: 0 !important;"
        . " background: none !important; }"
        . ".dv-tools { padding: 3px 6px !important; background: " C2 " !important;"
        . " border-bottom: 1px solid " LN "; }"
        ; the left pane is 600px and carries four controls: give the filter a
        ; smaller share so the buttons never have to compete for room
        . ".dv-tools > * { margin-right: 6px !important; }"
        . ".dv-tools .searchbox { width: 150px !important; }"
        . ".dv-tools .searchbox input { height: 21px; font-size: 11px;"
        . " background: " C " !important; border-color: " LN " !important; }"
        . ".dv-tools .btn { height: 19px; line-height: 17px; font-size: 11px; padding: 0 11px;"
        . " background: " C2 " !important; border-color: " LN " !important; }"
        . ".dv-count { font-size: 10px; color: " DIM "; }"
        . ".dv-foot { display: none !important; }"
        . ".dv-hcell { height: 21px !important; font-size: 10px; font-weight: 400;"
        . " background: " C2 " !important; color: " DIM " !important;"
        . " border-bottom: 1px solid " LN " !important; }"
        . ".dv-cell { height: 20px !important;"
        . " font: 11px Consolas, 'Cascadia Mono', monospace; border: none !important; }"
        . ".dv-row:hover > .dv-cell { background: " HOV " !important; }"
        . ".dv-row.selected > .dv-cell { background: " SEL " !important; }"
        . "#insLeft .dv-bodywrap { max-height: calc(100vh - 137px) !important; }"
        . "#insP2 .dv-bodywrap { max-height: calc(100vh - 136px) !important; }"
        ; -- syntax colouring, DevTools' Elements panel ------------------------
        . "#attrs, #box, #crumbs, #ahk { font: 11px Consolas, 'Cascadia Mono', monospace; }"
        . "#attrs div, #ahk div { padding: 1px 0; }"
        . ".ins-tag { color: #5db0d7; } .ins-id { color: #f29766; }"
        . ".ins-cls { color: #9bbbdc; } .ins-key { color: #9bbbdc; } .ins-val { color: #f29766; }"
        . ".ins-dim { color: " DIM "; }"
        . ".ins-h { font: 10px 'Segoe UI', sans-serif; text-transform: uppercase;"
        . " letter-spacing: .09em; color: " DIM "; margin: 10px 0 3px; }"
        . ".ins-h:first-child { margin-top: 0; }"
        ; -- the box model, drawn the way DevTools draws it --------------------
        . ".bm { position: relative; padding: 17px 46px; text-align: center;"
        . " color: #202124; font: 10px Consolas, monospace; }"
        . ".bm-name { position: absolute; left: 4px; top: 3px; font-size: 9px;"
        . " letter-spacing: .07em; text-transform: uppercase; opacity: .75; }"
        . ".bm-t, .bm-b { position: absolute; left: 0; right: 0; }"
        . ".bm-t { top: 4px; } .bm-b { bottom: 4px; }"
        . ".bm-l, .bm-r { position: absolute; top: 50%; margin-top: -6px; }"
        . ".bm-l { left: 6px; } .bm-r { right: 6px; }"
        . ".bm-margin { background: #f9cc9d; }"
        . ".bm-border { background: #fdd663; }"
        . ".bm-padding { background: #c3d08b; }"
        . ".bm-content { background: #9dc0e0; padding: 14px 8px; font-size: 11px; }"
        . "#bmWrap { max-width: 430px; }"
        ; -- the AHK panel -----------------------------------------------------
        . ".ins-act { display: inline-block; height: 20px; line-height: 18px; padding: 0 9px;"
        . " margin: 0 4px 4px 0; border: 1px solid " LN "; border-radius: 2px;"
        . " background: " C2 "; color: " FG "; cursor: default;"
        . " font: 11px 'Segoe UI', sans-serif; -ms-user-select: none; user-select: none; }"
        . ".ins-act:hover { background: " HOV "; border-color: " AC "; }"
        . ".ins-in { height: 20px; padding: 0 6px; background: " C "; color: " FG ";"
        . " border: 1px solid " LN "; border-radius: 2px; outline: none;"
        . " font: 11px Consolas, monospace; }"
        . ".ins-in:focus { border-color: " AC "; }"
        . ".ins-ev { color: #b5cea8; }"
        ; -- the cascade ------------------------------------------------------
        . "#rules { font: 11px Consolas, 'Cascadia Mono', monospace; }"
        . ".rl { margin-bottom: 8px; border-bottom: 1px solid rgba(255,255,255,.05);"
        . " padding-bottom: 6px; }"
        . ".rl-h { padding: 1px 0 3px; }"
        . ".rl-src { float: right; color: " DIM "; font-size: 10px; }"
        . ".rl-d { padding: 1px 0 1px 14px; }"
        . ".rl-d.dead { text-decoration: line-through; opacity: .42; }"
        . ".rl-d:hover, .rl-h:hover { background: " HOV "; cursor: default; }"
        . ".rl-h { cursor: default; }"
        ; -- the console -------------------------------------------------------
        ; -- the drawer: closed it is out of the layout entirely -------------
        . "#insDrawer { display: none; position: absolute; left: 0; right: 0;"
        . " bottom: 22px; height: 210px; background: " C ";"
        . " border-top: 1px solid " LN "; }"
        . "body.drawer #insDrawer { display: block; }"
        . "body.drawer #insLeft, body.drawer #insRight { bottom: 232px; }"
        . "#insDrawerBar { height: 22px; line-height: 22px; padding: 0 8px;"
        . " background: " C2 "; border-bottom: 1px solid " LN "; color: " DIM ";"
        . " font: 10px 'Segoe UI', sans-serif; text-transform: uppercase;"
        . " letter-spacing: .09em; -ms-user-select: none; user-select: none; }"
        . ".ins-x { float: right; padding: 0 4px; cursor: default;"
        . " font-size: 13px; line-height: 22px; }"
        . ".ins-x:hover { color: " FG "; }"
        . "#insLog { position: absolute; left: 0; right: 0; top: 22px; bottom: 26px;"
        . " overflow: auto; padding: 6px 8px;"
        . " font: 11px Consolas, 'Cascadia Mono', monospace; }"
        . "#insLog div { padding: 1px 0; border-bottom: 1px solid rgba(255,255,255,.04);"
        . " white-space: pre-wrap; word-wrap: break-word; }"
        . "#insLog .e { color: #f28b82; } #insLog .i { color: " DIM "; }"
        . "#insLog .c { color: " AC "; }"
        . "#insP7 { padding: 0; }"
        . "#cssBar { position: absolute; left: 0; right: 0; top: 0; height: 28px;"
        . " line-height: 26px; padding: 3px 6px 0; white-space: nowrap;"
        . " background: " C2 "; border-bottom: 1px solid " LN "; }"
        . ".ins-lv { color: " DIM "; margin-left: 4px; -ms-user-select: none;"
        . " user-select: none; }"
        . "#cssStat { margin-left: 10px; font: 10px Consolas, monospace; }"
        . "#cssWrap { position: absolute; left: 0; right: 0; top: 28px; bottom: 0; }"
        . "#cssEdit { width: 100%; height: 100%; box-sizing: border-box;"
        . " padding: 8px 10px; background: " C "; color: " FG ";"
        . " border: none; outline: none; resize: none; overflow: auto;"
        . " font: 12px Consolas, 'Cascadia Mono', monospace; line-height: 17px; }"
        . "#props { font: 11px Consolas, 'Cascadia Mono', monospace; }"
        . "#props div { padding: 1px 0; }"
        . "#insCmdRow { position: absolute; left: 0; right: 0; bottom: 0; height: 26px;"
        . " border-top: 1px solid " LN "; background: " C2 "; }"
        . "#insCaret { position: absolute; left: 7px; top: 4px; color: " AC "; }"
        . "#insCmd { position: absolute; left: 20px; right: 4px; top: 3px; height: 20px;"
        . " background: transparent; border: none; color: " FG "; outline: none;"
        . " font: 11px Consolas, 'Cascadia Mono', monospace; }"
        ; -- the trail ---------------------------------------------------------
        . "#insFoot { position: absolute; left: 0; right: 0; bottom: 0; height: 22px;"
        . " line-height: 22px; padding: 0 8px; white-space: nowrap; overflow: hidden;"
        . " background: " C2 "; border-top: 1px solid " LN "; }"
        . "#insCount { float: right; color: " DIM ";"
        . " font: 11px Consolas, 'Cascadia Mono', monospace; }"
        . ".ins-crumb { padding: 1px 4px; cursor: default; }"
        . ".ins-crumb:hover { background: " HOV "; }"
        . ".ins-crumb.here { background: " SEL "; }"
        . ".ins-sep { color: " DIM "; opacity: .5; padding: 0 1px; }")
    }

    _Wire() {
        w := this.W
        ; the toolbar and the tabs are plain markup, so one handler each reads
        ; whichever child was actually hit
        w.On("click", "insBar", (el, ev) => this._BarClick(ev))
        w.On("click", "insTabs", (el, ev) => this._TabClick(ev))
        w.On("click", "crumbs", (el, ev) => this._CrumbClick(ev))
        w.On("click", "ahk", (el, ev) => this._AhkClick(ev))
        w.On("click", "cssBar", (el, ev) => this._CssClick(ev))
        w.On("click", "rules", (el, ev) => this._RulesClick(ev))
        w.On("keydown", "cssEdit", (el, ev) => this._CssKey(ev))
        w.On("keyup", "cssEdit", (*) => this._CssTyped())
        w.On("keydown", "insCmd", (el, ev) => this._CmdKey(ev))
        w.On("click", "insDrawerBar", (el, ev) => this._BarClick(ev))
        ; Esc is DevTools' drawer key. While picking it means "stop picking",
        ; which is the more urgent of the two.
        w.On("keydown", "*", (el, ev) => this._WinKey(ev))
        try w.Ctl("tree").Component.OnSelect((rows, dv) => this._PickedRow(rows))
        try AxRich.At(w, "tree").OnSelect((rows, dv) => this._PickedRow(rows))
        ; off the target's own close thread, for the reason given at Toggle
        try this.T.OnClose((*) => SetTimer((*) => this.Close(), -1))
        w.OnClose((*) => this._Teardown())
    }
    ; what a data- attribute says, from wherever inside the button the click landed
    static _ActOf(ev, name) {
        try {
            el := ev.srcElement
            loop 4 {
                if !IsObject(el)
                    return ""
                v := AxWindow._Attr(el, name)
                if (v != "")
                    return v
                el := AxWindow._ParentEl(el)
            }
        }
        return ""
    }
    _BarClick(ev) {
        switch AxInspector._ActOf(ev, "data-act") {
            case "pick":     this.TogglePick()
            case "refresh":  this.Refresh()
            case "expand":   try AxRich.At(this.W, "tree").ExpandAll()
            case "collapse": try AxRich.At(this.W, "tree").CollapseAll()
            case "mon":      this.ToggleMonitor()
            case "drawer":   this.ToggleDrawer()
        }
    }
    _TabClick(ev) {
        n := AxInspector._ActOf(ev, "data-tab")
        if (n = "")
            return
        this.ShowTab(Integer(n))
    }
    ShowTab(n) {
        this.Tab := n
        this._FillTab(n)
        loop 7 {
            i := A_Index
            try this.W.Style("insP" i, "display", i = n ? "block" : "none")
        }
        ; the tab strip marks itself
        try {
            els := this.W.Doc.querySelectorAll("#insTabs .ins-tab")
            loop els.length {
                el := els.item(A_Index - 1)
                AxWindow._SetClass(el, "on", AxWindow._Attr(el, "data-tab") = String(n))
            }
        }
    }

    ; ------------------------------------------------------------------- tree
    Refresh() {
        this.Nodes := []
        this.ById := Map()                     ; uniqueID -> index, see _IndexOf
        this._rules := ""                      ; the sheet snapshot goes stale
        this.Sel := "", this.SelIdx := 0
        rows := []
        try {
            body := this.T.Doc.body
            if IsObject(body)
                rows.Push(this._Node(body, 0))
        }
        try AxRich.At(this.W, "tree").SetRows(rows)
        try this.W.Html("insCount", this.Nodes.Length " nodes")
        this._Show("", 0)
    }
    _Node(el, depth) {
        this.Nodes.Push(el)
        idx := this.Nodes.Length
        ; Open, but not all the way. A real page here is ~1500 elements and
        ; expanding every one of them means the grid lays out 1500 rows before
        ; the window will even paint -- which is what made the inspector look
        ; like it had hung. Four levels is the shape of the page; "Expand all"
        ; is still one click away. Opts.Expanded would override this for every
        ; row at once, which is why it is set per row instead.
        ; IE gives every element a stable uniqueID string; keying on it turns
        ; _IndexOf from a linear walk of COM identity comparisons into a hash
        ; lookup. The trail alone did that once per ancestor per selection.
        try this.ById[el.uniqueID] := idx
        row := {Key: idx, label: AxInspector.Describe(el, 3),
                size: AxInspector.SizeOf(el), kind: this._Origin(el),
                Icon: this._Glyph(el), Expanded: (depth < 4)}
        if (depth < 24) {
            kids := []
            try {
                ch := el.children
                loop ch.length {
                    c := ch.item(A_Index - 1)
                    if !IsObject(c)
                        continue
                    tag := ""
                    try tag := StrUpper(c.tagName)
                    if (tag = "SCRIPT" || tag = "STYLE")
                        continue
                    if (AxWindow._Attr(c, "id") = "axInspectHL")     ; our own marker
                        continue
                    kids.Push(this._Node(c, depth + 1))
                }
            }
            if kids.Length
                row.Children := kids
        }
        return row
    }
    ; max: how many classes to spell out before summarising the rest. A tree
    ; row has no room for
    ; body.theme-dark.sheet-win11.has-menubar.has-statusbar.inactive, and the
    ; column ellipsis cut it at a meaningless place; three classes and a count
    ; keeps the row readable and still says how much was left out. Everything
    ; that builds a selector asks for all of them.
    static Describe(el, max := 0) {
        s := ""
        try s := StrLower(el.tagName)
        id := AxWindow._Attr(el, "id")
        if (id != "")
            s .= "#" id
        cls := ""
        try cls := AxWindow._ClassOf(el)
        list := []
        for c in StrSplit(Trim(cls), " ")
            if (c != "")
                list.Push(c)
        for i, c in list {
            if (max && i > max) {
                s .= " +" (list.Length - max)
                break
            }
            s .= "." c
        }
        return s
    }
    ; the same thing with colour, for the panels that take markup
    static DescribeHtml(el) {
        E := (x) => AxWindow._Esc(String(x))
        tag := ""
        try tag := StrLower(el.tagName)
        s := "<span class='ins-tag'>" E(tag) "</span>"
        id := AxWindow._Attr(el, "id")
        if (id != "")
            s .= "<span class='ins-id'>#" E(id) "</span>"
        cls := ""
        try cls := AxWindow._ClassOf(el)
        for c in StrSplit(Trim(cls), " ")
            if (c != "")
                s .= "<span class='ins-cls'>." E(c) "</span>"
        return s
    }
    ; offsetWidth/offsetHeight rather than getBoundingClientRect: the same two
    ; numbers for a whole-pixel layout, without building a rect object per node.
    ; On a page of a few hundred elements that is most of a refresh.
    static SizeOf(el) {
        try
            return Round(el.offsetWidth) "x" Round(el.offsetHeight)
        return ""
    }
    _Origin(el) {
        id := AxWindow._Attr(el, "id")
        if (id = "")
            return ""
        try {
            c := AxRich.At(this.T, id)
            if IsObject(c)
                return Type(c)
        }
        try {
            ctl := this.T.Ctl(id)
            if IsObject(ctl)
                return ctl.Type
        }
        for name in ["titlebar", "titleText", "btnMin", "btnMax", "btnClose",
                     "sidebar", "content", "shell", "axMenuBar", "axStatusBar"]
            if (id = name)
                return "frame"
        return ""
    }
    _Glyph(el) {
        tag := ""
        try tag := StrUpper(el.tagName)
        if (tag = "INPUT" || tag = "TEXTAREA" || tag = "SELECT")
            return "E70F"
        if (tag = "IMG" || tag = "SVG")
            return "EB9F"
        if (tag = "TABLE" || tag = "TR" || tag = "TD" || tag = "TH")
            return "E80A"
        return "E8A5"
    }

    ; --------------------------------------------------------------- selection
    _PickedRow(rows) {
        if (!IsObject(rows) || !rows.Length)
            return
        k := 0
        try k := Integer(rows[1].Key)
        if (k >= 1 && k <= this.Nodes.Length)
            this._Show(this.Nodes[k], k)
    }
    ; Only the visible tab is filled. Computed styles alone enumerate a couple
    ; of hundred properties, and building all four panels on every selection --
    ; sixteen times a second while picking -- was most of what made this feel
    ; slow. Switching tabs fills the one being switched to.
    _Show(el, idx := 0) {
        this.Sel := el, this.SelIdx := idx
        if !IsObject(el) {
            this.W.Html("attrs", "<i>Nothing selected.</i>")
            this.W.Html("ahk", "<i>Nothing selected.</i>")
            this.W.Html("box", "<i>Nothing selected.</i>")
            this.W.Html("crumbs", "<span class='ins-dim'>no selection</span>")
            try AxRich.At(this.W, "css").SetRows([])
            this.Highlight("")
            return
        }
        this.W.Html("crumbs", this._CrumbHtml(el))
        this.Highlight(el)
        this._FillTab(this.Tab, el)
    }
    _FillTab(n, el := "") {
        if !IsObject(el)
            el := this.Sel
        if !IsObject(el)
            return
        switch n {
            case 1: this.W.Html("attrs", this._AttrHtml(el))
            case 2: this._FillStyles(el)
            case 3: this._FillBox(el)
            case 4: this.W.Html("ahk", this._AhkHtml(el))
            case 5: this.W.Html("props", this._PropsHtml(el))
            case 6: this.W.Html("rules", this._RulesHtml(el))
            ; 7 is an editor, not a view of the selection: never overwritten
        }
    }

    ; ----------------------------------------------------------------- panels
    _AttrHtml(el) {
        E := (x) => AxWindow._Esc(String(x))
        h := "<div style='margin-bottom:6px'>" AxInspector.DescribeHtml(el) "</div>"
        rows := ""
        try {
            att := el.attributes
            loop att.length {
                a := att.item(A_Index - 1)
                n := "", v := ""
                try n := a.name
                try v := a.value
                if (n = "")
                    continue
                spec := true
                try spec := a.specified          ; skip everything IE invents
                if !spec
                    continue
                rows .= "<div><span class='ins-key'>" E(n) "</span>"
                     .  "<span class='ins-dim'>=</span><span class='ins-val'>&quot;"
                     .  E(StrLen(String(v)) > 120 ? SubStr(String(v), 1, 120) "…" : v)
                     .  "&quot;</span></div>"
            }
        }
        h .= rows ? rows : "<div class='ins-dim'>no attributes</div>"
        txt := ""
        try txt := Trim(el.innerText)
        if (txt != "")
            h .= "<div class='ins-h'>text</div><div>"
               . E(StrLen(txt) > 140 ? SubStr(txt, 1, 140) "…" : txt) "</div>"
        return h
    }
    ; What a browser inspector cannot show: which AHK handler will actually run.
    ; AxWindow keeps Hooks as eventType -> Map(id -> fn) and dispatch walks up
    ; from the clicked node to the nearest ancestor with a hook -- so the
    ; question "what happens if I click this" is answered by walking the same
    ; way, and naming the element that would win.
    _AhkHtml(el) {
        E := (x) => AxWindow._Esc(String(x))
        id := AxWindow._Attr(el, "id")
        h := ""
        ctl := ""
        if (id != "")
            try ctl := this.T.Ctl(id)
        if IsObject(ctl) {
            h .= "<div class='ins-h'>AxGui control</div>"
               . "<div><span class='ins-val'>g.Ctl(&quot;" E(id) "&quot;)</span></div>"
               . "<div><span class='ins-key'>type</span> " E(ctl.Type) "</div>"
            v := ""
            try v := this.T.Value(id)
            if IsObject(v) {
                sv := ""
                for item in v
                    sv .= (sv = "" ? "" : ", ") String(item)
                v := "[" sv "]"
            }
            h .= "<div><span class='ins-key'>value</span> "
               . "<input class='ins-in' id='insVal' style='width:180px' value='"
               . E(v) "'> <span class='ins-act' data-act='setval'>Set</span></div>"
        }
        comp := ""
        if (id != "")
            try comp := AxRich.At(this.T, id)
        if IsObject(comp)
            h .= "<div class='ins-h'>rich component</div>"
               . "<div><span class='ins-val'>AxRich.At(g, &quot;" E(id) "&quot;)</span></div>"
               . "<div><span class='ins-key'>class</span> " E(Type(comp)) "</div>"

        ; -- what is actually wired ---------------------------------------
        h .= "<div class='ins-h'>AHK events</div>"
        rows := ""
        try {
            ; not "type" and "map": identifiers ignore case, so those ARE
            ; Type() and Map() for this whole function, Type(comp) above included
            for evType, hookMap in this.T.Hooks {
                owner := this._HookOwner(el, hookMap)
                if (owner = "")
                    continue
                site := AxInspector.SiteOf(this.T, evType, owner)
                rows .= "<div><span class='ins-ev'>" E(evType) "</span> "
                      . (owner = id ? "<span class='ins-dim'>on this element</span>"
                                    : "<span class='ins-dim'>via</span> <span class='ins-id'>#"
                                      E(owner) "</span>")
                      . (site != "" ? " <span class='rl-src'>" E(site) "</span>" : "")
                      . "</div>"
            }
        }
        h .= rows ? rows : "<div class='ins-dim'>nothing wired to this element "
                         . "or its ancestors</div>"
        role := AxWindow._Attr(el, "data-role")
        if (role != "")
            h .= "<div><span class='ins-key'>data-role</span> " E(role)
               . " <span class='ins-dim'>(value contract)</span></div>"

        ; -- things worth doing to it -------------------------------------
        h .= "<div class='ins-h'>actions</div><div>"
           . "<span class='ins-act' data-act='click'>Click</span>"
           . "<span class='ins-act' data-act='focus'>Focus</span>"
           . "<span class='ins-act' data-act='scroll'>Scroll into view</span>"
           . "<span class='ins-act' data-act='flash'>Flash</span>"
           . "<span class='ins-act' data-act='copysel'>Copy selector</span>"
           . "<span class='ins-act' data-act='cssseed'>Style it</span>"
           . "</div>"
        h .= "<div class='ins-h'>class</div><div>"
           . "<input class='ins-in' id='insCls' style='width:150px' placeholder='name'> "
           . "<span class='ins-act' data-act='addcls'>Add</span>"
           . "<span class='ins-act' data-act='delcls'>Remove</span></div>"
        return h
    }
    ; dispatch finds the nearest ancestor-or-self carrying a hook; this reports
    ; which one that is, so a click that "does nothing" can be traced
    _HookOwner(el, map) {
        node := el
        loop 12 {
            if !IsObject(node)
                return ""
            nid := AxWindow._Attr(node, "id")
            if (nid != "" && map.Has(nid))
                return nid
            node := AxWindow._ParentEl(node)
        }
        return ""
    }
    _FillStyles(el) {
        rows := []
        try {
            cs := this.T.Doc.parentWindow.getComputedStyle(el)
            for n in this._Names(cs) {
                v := ""
                try v := cs.getPropertyValue(n)
                if (v = "")
                    try v := cs.%n%
                if (String(v) != "")
                    rows.Push({Key: n, prop: n, val: String(v)})
            }
        }
        try AxRich.At(this.W, "css").SetRows(rows)
    }
    ; The name list is a property of the engine, not of the element, so it is
    ; enumerated once and reused -- it was being rebuilt on every selection.
    _Names(cs) {
        if IsObject(this._propNames)
            return this._propNames
        this._propNames := AxInspector._PropNames(cs)
        return this._propNames
    }
    static _PropNames(cs) {
        out := []
        try {
            n := cs.length + 0
            if (n > 0) {
                loop n {
                    p := cs.item(A_Index - 1)
                    if (p != "")
                        out.Push(p)
                }
            }
        }
        if out.Length
            return out
        for p in ["display", "position", "top", "right", "bottom", "left", "float", "clear",
                  "width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight",
                  "margin", "padding", "border", "borderRadius", "boxShadow", "boxSizing",
                  "overflow", "overflowX", "overflowY", "visibility", "opacity", "zIndex",
                  "color", "backgroundColor", "backgroundImage", "backgroundSize",
                  "backgroundPosition", "backgroundRepeat",
                  "font", "fontFamily", "fontSize", "fontWeight", "fontStyle",
                  "lineHeight", "letterSpacing", "textAlign", "textDecoration",
                  "textTransform", "whiteSpace", "textOverflow",
                  "cursor", "transform", "transition"]
            out.Push(p)
        return out
    }
    ; The nested diagram DevTools draws, in its colours: tan margin, yellow
    ; border, green padding, blue content, dark figures on top. The four edge
    ; numbers sit on the edges they describe rather than in a row, which is the
    ; whole reason the picture is quicker to read than the numbers.
    _FillBox(el) {
        try {
            cs := this.T.Doc.parentWindow.getComputedStyle(el)
            G := (p) => AxInspector._Px(cs, p)
            r := el.getBoundingClientRect()
            w := Round(r.right - r.left), h := Round(r.bottom - r.top)
            bl := G("borderLeftWidth"), br := G("borderRightWidth")
            bt := G("borderTopWidth"), bb := G("borderBottomWidth")
            pl := G("paddingLeft"), pr := G("paddingRight")
            pt := G("paddingTop"), pb := G("paddingBottom")
            cw := w - bl - br - pl - pr, ch := h - bt - bb - pt - pb
            ; a zero edge is drawn as a dash, the way DevTools does, so a real
            ; zero is never mistaken for a missing reading
            D := (v) => (v = 0) ? "-" : String(v)
            L := (cls, name, t, rr, b, l, inner) =>
                "<div class='bm bm-" cls "'><span class='bm-name'>" name "</span>"
              . "<span class='bm-t'>" D(t) "</span><span class='bm-r'>" D(rr) "</span>"
              . "<span class='bm-b'>" D(b) "</span><span class='bm-l'>" D(l) "</span>"
              . inner "</div>"
            content := "<div class='bm bm-content'>" cw " &times; " ch "</div>"
            html := "<div id='bmWrap'>"
                  . L("margin", "margin", G("marginTop"), G("marginRight"),
                      G("marginBottom"), G("marginLeft"),
                      L("border", "border", bt, br, bb, bl,
                        L("padding", "padding", pt, pr, pb, pl, content)))
                  . "</div>"
            K := (k, v) => "<div><span class='ins-key'>" k "</span> "
                         . "<span class='ins-val'>" v "</span></div>"
            html .= "<div class='ins-h'>border box</div>" K("size", w " x " h)
                  . "<div class='ins-h'>position</div>"
                  . K("left", Round(r.left)) K("top", Round(r.top))
                  . K("right", Round(r.right)) K("bottom", Round(r.bottom))
            sc := ""
            try sc := String(cs.position)
            if (sc != "" && sc != "static")
                html .= "<div class='ins-h'>positioned</div>" K("position", sc)
            this.W.Html("box", html)
        }
    }
    static _Px(cs, prop) {
        v := ""
        try v := cs.%prop%
        if (v = "" || v = "auto")
            return 0
        return Round(StrReplace(String(v), "px", "") + 0)
    }

    ; ------------------------------------------------------------------ trail
    ; The ancestors, oldest first, each clickable -- DevTools' breadcrumb.
    _CrumbHtml(el) {
        chain := []
        node := el
        loop 40 {
            if !IsObject(node)
                break
            tag := ""
            try tag := StrUpper(node.tagName)
            if (tag = "" || tag = "HTML")
                break
            chain.InsertAt(1, node)
            if (tag = "BODY")
                break
            node := AxWindow._ParentEl(node)
        }
        if !chain.Length
            return "<span class='ins-dim'>no selection</span>"
        h := ""
        for i, n in chain {
            idx := this._IndexOf(n)
            here := false
            try here := (n = el)
            h .= (h = "" ? "" : "<span class='ins-sep'>&rsaquo;</span>")
               . "<span class='ins-crumb" (here ? " here" : "") "' data-i='" idx "'>"
               . AxInspector.DescribeHtml(n) "</span>"
        }
        return h
    }
    _IndexOf(el) {
        try {
            u := el.uniqueID
            if this.ById.Has(u)
                return this.ById[u]
        }
        return 0
    }
    _CrumbClick(ev) {
        try {
            el := ev.srcElement
            loop 4 {                            ; the click may land on an inner span
                if !IsObject(el)
                    return
                i := AxWindow._Attr(el, "data-i")
                if (i != "") {
                    n := Integer(i)
                    if (n >= 1 && n <= this.Nodes.Length) {
                        this._Show(this.Nodes[n], n)
                        try AxRich.At(this.W, "tree").SelectKeys([n])
                    }
                    return
                }
                el := AxWindow._ParentEl(el)
            }
        }
    }

    ; A rule in the Styles panel is one click from being overridden: the same
    ; selector written again into the user sheet, which is appended after the
    ; theme and so wins the tie on document order -- exactly what DevTools does
    ; when you edit a rule.
    _RulesClick(ev) {
        sel := AxInspector._ActOf(ev, "data-cs")
        if (sel = "")
            return
        prop := AxInspector._ActOf(ev, "data-cp")
        if (prop != "") {
            val := AxInspector._ActOf(ev, "data-cv")
            this._CssAppend(sel, prop ": " val ";")
            return
        }
        all := AxInspector._ActOf(ev, "data-call")     ; the header: whole rule
        if (all = "")
            return
        body := ""
        for d in StrSplit(all, ";")
            if (Trim(d) != "")
                body .= (body = "" ? "" : "`n    ") Trim(d) ";"
        this._CssAppend(sel, body)
    }
    _CssAppend(sel, body) {
        cur := ""
        try cur := this.W.El("cssEdit").value
        this._CssSet(AxInspector._CssUpsert(cur, sel, body))
        this.ShowTab(7)
        try this.W.El("cssEdit").focus()
    }
    ; Overriding three declarations on one element used to leave three separate
    ; blocks with the same selector -- legal CSS, but it reads badly and the
    ; later block quietly wins, so editing the first one appears to do nothing.
    ; Declarations are folded into the rule that is already there instead:
    ; matched by property name, so setting a property twice replaces it rather
    ; than stacking a dead copy above the live one.
    static _CssUpsert(text, sel, body) {
        incoming := AxInspector._Decls(body)
        for b in AxInspector._Blocks(text) {
            if (AxInspector._NormSel(b.sel) != AxInspector._NormSel(sel))
                continue
            decls := AxInspector._Decls(b.body)
            for d in incoming {
                hit := false
                for e in decls {
                    if (StrLower(e.p) = StrLower(d.p)) {
                        e.v := d.v, hit := true
                        break
                    }
                }
                if !hit
                    decls.Push(d)
            }
            return SubStr(text, 1, b.s - 1) AxInspector._Render(sel, decls)
                 . AxInspector._DropNl(SubStr(text, b.c + 1))
        }
        head := RTrim(text, " `t`r`n")
        return head (head = "" ? "" : "`n`n") AxInspector._Render(sel, incoming)
    }
    ; every "selector { ... }" in the text, in order. Plain CSS does not nest,
    ; so the first } after a { closes it.
    static _Blocks(text) {
        out := [], i := 1, start := 1
        while (o := InStr(text, "{", , i)) {
            c := InStr(text, "}", , o + 1)
            if !c
                break
            raw := SubStr(text, start, o - start)
            lead := StrLen(raw) - StrLen(LTrim(raw, " `t`r`n"))
            out.Push({sel: Trim(raw, " `t`r`n"),
                      body: SubStr(text, o + 1, c - o - 1), s: start + lead, c: c})
            i := c + 1, start := c + 1
        }
        return out
    }
    static _Decls(css) {
        out := []
        for d in StrSplit(css, ";") {
            d := Trim(d, " `t`r`n")
            if (d = "")
                continue
            c := InStr(d, ":")
            if !c
                continue
            out.Push({p: Trim(SubStr(d, 1, c - 1)), v: Trim(SubStr(d, c + 1))})
        }
        return out
    }
    static _Render(sel, decls) {
        b := ""
        for d in decls
            b .= "    " d.p ": " d.v ";`n"
        return sel " {`n" b "}`n"
    }
    static _DropNl(t) {
        if (SubStr(t, 1, 2) = "`r`n")
            return SubStr(t, 3)
        if (SubStr(t, 1, 1) = "`n")
            return SubStr(t, 2)
        return t
    }
    static _NormSel(x) => RegExReplace(Trim(x), "\s+", " ")

    ; ------------------------------------------------------------ custom CSS
    ; A stylesheet of your own, layered over the target and reapplied on every
    ; keystroke. SetExtraCss already does exactly this -- a named sheet that is
    ; replaced wholesale by id and removed when handed an empty string -- so
    ; the editor is a textarea wired to it and nothing more.
    ;
    ; One thing worth knowing: SetExtraCss inserts ahead of the accent sheet,
    ; so a chosen accent or tint still has the last word on colour. To beat one
    ; deliberately, mark the declaration !important.
    _CssTyped() {
        auto := true
        try auto := this.W.El("cssAuto").checked ? true : false
        if !auto
            return
        if !this.HasOwnProp("_cssFn")
            this._cssFn := (*) => this.ApplyCss()
        SetTimer(this._cssFn, -250)          ; coalesce a burst of typing
    }
    ; Enter keeps the current indentation and adds a level after an opening
    ; brace; Tab completes a property name if the caret is on a word and
    ; indents if it is not. IE9+ exposes selectionStart/End on a textarea, so
    ; the caret can be read and put back; if it cannot be read the key is left
    ; alone and the browser does its default thing.
    _CssKey(ev) {
        k := 0
        try k := ev.keyCode
        if (k != 13 && k != 9)
            return
        el := "", txt := "", pos := ""
        try {
            el := this.W.El("cssEdit")
            txt := el.value
            pos := el.selectionStart + 0
        }
        if (!IsObject(el) || pos = "")
            return
        ls := pos
        while (ls > 0 && SubStr(txt, ls, 1) != "`n")
            ls -= 1
        line := SubStr(txt, ls + 1, pos - ls)
        if (k = 13) {
            ind := ""
            loop parse line {
                if (A_LoopField != " " && A_LoopField != "`t")
                    break
                ind .= A_LoopField
            }
            if (SubStr(RTrim(line), -1) = "{")
                ind .= "    "
            this._CssPut(el, txt, pos, pos, "`n" ind)
        } else {
            word := "", i := pos
            while (i > 0) {
                c := SubStr(txt, i, 1)
                if !RegExMatch(c, "[A-Za-z\-]")
                    break
                word := c word
                i -= 1
            }
            hits := (word = "") ? [] : AxInspector._CssMatch(word)
            if hits.Length {
                this._CssPut(el, txt, pos - StrLen(word), pos, hits[1] ": ")
                this._CssHint(hits)
            } else
                this._CssPut(el, txt, pos, pos, "    ")
        }
        try ev.returnValue := false
        this._CssTyped()                 ; respects the "live" checkbox
    }
    ; replace [from, to) with ins and leave the caret after it
    _CssPut(el, txt, from, to, ins) {
        try {
            el.value := SubStr(txt, 1, from) ins SubStr(txt, to + 1)
            np := from + StrLen(ins)
            el.selectionStart := np, el.selectionEnd := np
        }
    }
    _CssHint(hits) {
        s := ""
        for i, h in hits {
            if (i > 8) {
                s .= " …"
                break
            }
            s .= (s = "" ? "" : "  ") h
        }
        try this.W.Html("cssStat", "<span class='ins-dim'>" AxWindow._Esc(s) "</span>")
    }
    ; The properties Trident actually honours, plus the -ms- ones that matter
    ; here. Long-hand first so a prefix lands on the common spelling.
    static _CssMatch(prefix) {
        static props := ["background", "background-color", "background-image",
            "background-position", "background-repeat", "background-size",
            "border", "border-bottom", "border-bottom-color", "border-color",
            "border-left", "border-radius", "border-right", "border-style",
            "border-top", "border-top-color", "border-width", "bottom",
            "box-shadow", "box-sizing", "clear", "color", "cursor", "direction",
            "display", "filter", "float", "font", "font-family", "font-size",
            "font-style", "font-weight", "height", "left", "letter-spacing",
            "line-height", "list-style", "margin", "margin-bottom", "margin-left",
            "margin-right", "margin-top", "max-height", "max-width", "min-height",
            "min-width", "opacity", "outline", "outline-offset", "overflow",
            "overflow-x", "overflow-y", "padding", "padding-bottom", "padding-left",
            "padding-right", "padding-top", "position", "right", "text-align",
            "text-decoration", "text-overflow", "text-shadow", "text-transform",
            "top", "transform", "transition", "vertical-align", "visibility",
            "white-space", "width", "word-wrap", "z-index",
            "-ms-transform", "-ms-user-select", "-ms-overflow-style"]
        out := []
        p := StrLower(prefix)
        for n in props
            if (SubStr(n, 1, StrLen(p)) = p)
                out.Push(n)
        return out
    }
    ApplyCss() {
        css := ""
        try css := this.W.El("cssEdit").value
        try {
            this.T.SetExtraCss("axinspector-user", css)
            if (Trim(css) = "") {
                this.W.Html("cssStat", "cleared")
                return
            }
            ; Read back how many rules the engine actually kept. Text in the
            ; box is not the same as CSS the browser accepted, and "applied"
            ; on its own says nothing about whether a selector was mistyped or
            ; a declaration ended up outside a block.
            n := this._CssRuleCount()
            this.W.Html("cssStat", StrLen(css) " chars &middot; "
                . ((n = "") ? "applied"
                   : (n = 0) ? "<span class='e'>0 rules parsed &mdash; check the syntax</span>"
                   : n " rule" (n = 1 ? "" : "s"))
                . " &middot; " FormatTime(, "HH:mm:ss"))
        } catch as e
            try this.W.Html("cssStat", "<span class='e'>" AxWindow._Esc(e.Message) "</span>")
    }
    _CssRuleCount() {
        try {
            st := this.T.Doc.getElementById("axExtra_axinspector-user")
            r := st.styleSheet.rules
            if !IsObject(r)
                r := st.styleSheet.cssRules
            return r.length + 0
        }
        return ""
    }
    _CssSet(text) {
        try this.W.El("cssEdit").value := text
        this.ApplyCss()
    }
    _CssClick(ev) {
        switch AxInspector._ActOf(ev, "data-act") {
            case "cssapply": this.ApplyCss()
            case "cssclear": this._CssSet("")
            case "cssseed":  this._CssSeed()
            case "csscopy":
                try A_Clipboard := this.W.El("cssEdit").value
                this.EvLogger("CSS copied to the clipboard", "i")
            case "csssave":
                f := FileSelect("S24", A_ScriptDir "\custom.css", "Save CSS", "CSS (*.css)")
                if (f = "")
                    return
                try {
                    if FileExist(f)
                        FileDelete(f)
                    FileAppend(this.W.El("cssEdit").value, f, "UTF-8")
                    this.EvLogger("saved " f, "i")
                } catch as e
                    this.EvLogger(e.Message, "e")
            case "cssload":
                f := FileSelect(3, A_ScriptDir "\custom.css", "Load CSS", "CSS (*.css)")
                if (f = "")
                    return
                try this._CssSet(FileRead(f, "UTF-8"))
                catch as e
                    this.EvLogger(e.Message, "e")
        }
    }
    ; A starting rule for whatever is selected, specific enough to actually
    ; win: the sheet and theme classes the stylesheets themselves are scoped
    ; with, then an id if there is one, else the tag and its classes.
    _CssSeed() {
        el := this.Sel
        if !IsObject(el) {
            this.EvLogger("select an element first", "e")
            return
        }
        id := AxWindow._Attr(el, "id")
        if (id != "")
            sel := "#" id
        else {
            sel := ""
            try sel := StrLower(el.tagName)
            cls := ""
            try cls := AxWindow._ClassOf(el)
            for c in StrSplit(Trim(cls), " ")
                if (c != "")
                    sel .= "." c
        }
        scope := ""
        try {
            for c in StrSplit(Trim(AxWindow._ClassOf(this.T.Doc.body)), " ")
                if (SubStr(c, 1, 6) = "sheet-" || SubStr(c, 1, 6) = "theme-")
                    scope .= "." c
        }
        cur := ""
        try cur := this.W.El("cssEdit").value
        ; through the same upsert, so seeding a selector that is already in the
        ; sheet moves to it rather than writing a second empty copy
        this._CssSet(AxInspector._CssUpsert(cur, "body" scope " " sel, ""))
        try this.W.El("cssEdit").focus()
        this.ShowTab(7)
    }

    ; ------------------------------------------------------------ properties
    ; The live object, not the markup: what the element measures, what it holds
    ; and what state it is in right now. getBoundingClientRect and the layout
    ; numbers answer "why is it the wrong size", the form group answers "what
    ; would AHK read out of this", and the scroll group answers "is there more
    ; of it than is showing".
    _PropsHtml(el) {
        E := (x) => AxWindow._Esc(String(x))
        h := ""
        grp := (title) => "<div class='ins-h'>" title "</div>"
        row := (k, v) => (String(v) = "") ? ""
              : "<div><span class='ins-key'>" E(k) "</span> "
              . "<span class='ins-val'>" E(v) "</span></div>"
        P := (name) => AxInspector._Prop(el, name)

        h .= grp("identity")
           . row("tagName", StrLower(String(P("tagName"))))
           . row("id", P("id")) . row("className", P("className"))
           . row("nodeType", P("nodeType"))
           . row("children", P("childElementCount"))
        h .= grp("layout")
           . row("offset", P("offsetWidth") " x " P("offsetHeight"))
           . row("offset pos", P("offsetLeft") ", " P("offsetTop"))
           . row("client", P("clientWidth") " x " P("clientHeight"))
           . row("offsetParent", AxInspector._ParentDesc(el))
        sw := P("scrollWidth"), sh := P("scrollHeight")
        if (sw != "" || sh != "")
            h .= grp("scroll")
               . row("scroll size", sw " x " sh)
               . row("scrolled", P("scrollLeft") ", " P("scrollTop"))
               . row("overflowing", (sh + 0 > P("clientHeight") + 0) ? "yes" : "no")
        f := ""
        for n in ["value", "checked", "disabled", "readOnly", "type", "name",
                  "placeholder", "href", "src", "title"]
            f .= row(n, P(n))
        if (f != "")
            h .= grp("form / media") f
        h .= grp("content")
           . row("innerText length", StrLen(String(P("innerText"))))
           . row("innerHTML length", StrLen(String(P("innerHTML"))))
        ; whatever AHK would actually get back for this element
        id := AxWindow._Attr(el, "id")
        if (id != "") {
            v := ""
            try v := this.T.Value(id)
            if IsObject(v) {
                sv := ""
                for item in v
                    sv .= (sv = "" ? "" : ", ") String(item)
                v := "[" sv "]"
            }
            if (String(v) != "")
                h .= grp("AxGui value") . row("g.Value(" Chr(34) id Chr(34) ")", v)
        }
        return h
    }
    ; a missing property on an IE element throws rather than returning ""
    static _Prop(el, name) {
        try {
            v := el.%name%
            if (v = "" || IsObject(v))
                return ""
            return String(v)
        }
        return ""
    }
    static _ParentDesc(el) {
        try {
            pp := el.offsetParent
            if IsObject(pp)
                return AxInspector.Describe(pp)
        }
        return ""
    }

    ; ------------------------------------------------------------- the cascade
    ; Computed values say what an element ended up with; this says WHY. Every
    ; stylesheet in the document is walked, every selector tested against the
    ; element, and the matches sorted the way the cascade sorts them --
    ; specificity first, document order to break a tie. The last one to set a
    ; property wins, so walking the sorted list and remembering what has
    ; already been claimed marks every losing declaration as overridden.
    ;
    ; A rule's selectorText may be a comma list, and only the part that matches
    ; carries the specificity that counts, so the parts are tested separately.
    ; Reading a rule across COM -- selectorText, style.cssText -- is far more
    ; expensive than testing one, and the sheets do not change between
    ; selections. So the whole document is flattened into plain AHK values once
    ; and every later selection only runs msMatchesSelector over that snapshot.
    ; Refresh drops it. On a page carrying win11.css that is a couple of
    ; thousand COM round trips saved per click.
    _Sheets() {
        if IsObject(this._rules)
            return this._rules
        out := []
        try {
            sheets := this.T.Doc.styleSheets
            loop sheets.length {
                sh := sheets.item(A_Index - 1)
                sname := ""
                try sname := sh.id
                if (sname = "")
                    try sname := sh.href
                if (sname = "")
                    sname := "sheet " A_Index
                rules := ""
                try rules := sh.rules
                if !IsObject(rules)
                    try rules := sh.cssRules
                if !IsObject(rules)
                    continue
                loop rules.length {
                    r := rules.item(A_Index - 1)
                    sel := "", css := ""
                    try sel := r.selectorText
                    try css := r.style.cssText
                    if (sel = "" || Trim(css) = "")
                        continue
                    for part in StrSplit(sel, ",") {
                        part := Trim(part)
                        if (part = "")
                            continue
                        out.Push({sel: part, spec: AxInspector.Spec(part),
                                  sheet: sname, css: css, ord: out.Length})
                    }
                }
            }
        }
        this._rules := out
        return out
    }
    _RulesHtml(el) {
        E := (x) => AxWindow._Esc(String(x))
        matched := []
        for r in this._Sheets()
            if AxInspector._Matches(el, r.sel)
                matched.Push(r)
        ; cascade order: weakest first, so the strongest is applied last
        _Cmp(a, b) => (a.spec != b.spec) ? a.spec - b.spec : a.ord - b.ord
        n := matched.Length
        loop n - 1 {                                  ; small lists, plain sort
            i := A_Index
            loop n - i {
                j := A_Index
                if (_Cmp(matched[j], matched[j + 1]) > 0) {
                    t := matched[j], matched[j] := matched[j + 1], matched[j + 1] := t
                }
            }
        }
        ; walk strongest -> weakest, claiming each property once
        won := Map()
        html := ""
        inline := ""
        try inline := el.style.cssText
        if (Trim(inline) != "") {
            html .= this._RuleBlock("element.style", "inline", inline, won, true)
        }
        i := n
        while (i >= 1) {
            m := matched[i]
            html .= this._RuleBlock(m.sel, m.sheet " &middot; spec " m.spec, m.css, won, false)
            i -= 1
        }
        if (html = "")
            return "<span class='ins-dim'>No rule in any sheet matches this element.</span>"
        return "<div class='ins-dim' style='margin-bottom:6px'>" n
             . " matching rule(s), strongest first &middot; "
             . "click a declaration to override it, a selector for the whole rule"
             . "</div>" html
    }
    ; one rule, with every declaration the cascade has already given away
    ; struck through -- the same thing DevTools does with a line through it
    _RuleBlock(sel, meta, css, won, isInline) {
        E := (x) => AxWindow._Esc(String(x))
        body := ""
        for decl in StrSplit(css, ";") {
            decl := Trim(decl)
            if (decl = "")
                continue
            c := InStr(decl, ":")
            if !c
                continue
            prop := Trim(SubStr(decl, 1, c - 1)), val := Trim(SubStr(decl, c + 1))
            key := StrLower(prop)
            dead := won.Has(key)
            if !dead
                won[key] := true
            ; every declaration carries what it would take to override it, so
            ; a click can hand the whole thing to the CSS editor
            body .= "<div class='rl-d" (dead ? " dead" : "") "'"
                  . " data-cs=" Chr(34) E(sel) Chr(34)
                  . " data-cp=" Chr(34) E(StrLower(prop)) Chr(34)
                  . " data-cv=" Chr(34) E(val) Chr(34) ">"
                  . "<span class='ins-key'>" E(StrLower(prop)) "</span>: "
                  . "<span class='ins-val'>" E(val) "</span>;</div>"
        }
        if (body = "")
            return ""
        return "<div class='rl'><div class='rl-h' data-cs=" Chr(34) E(sel) Chr(34)
             . " data-call=" Chr(34) E(css) Chr(34) ">"
             . "<span class='" (isInline ? "ins-id" : "ins-cls") "'>" E(sel) "</span>"
             . "<span class='rl-src'>" meta "</span></div>" body "</div>"
    }
    ; IE9+ spells it msMatchesSelector; a bad selector throws rather than
    ; returning false, which is why this is wrapped
    static _Matches(el, sel) {
        try
            return el.msMatchesSelector(sel) ? true : false
        try
            return el.matches(sel) ? true : false
        return false
    }
    ; CSS specificity as one comparable number: ids, then classes and
    ; pseudo-classes and attribute selectors, then element names. Base 256 is
    ; far more headroom than any real selector needs.
    static Spec(sel) {
        s := RegExReplace(sel, "::[A-Za-z-]+", " ")       ; pseudo-elements count as elements
        N := (pat) => AxInspector._All(s, pat).Length
        a := N("#[A-Za-z_][\w-]*")
        b := N("\.[A-Za-z_][\w-]*") + N("\[[^\]]*\]") + N(":(?!:)[A-Za-z-]+")
        c := N("(?:^|[\s>+~])[A-Za-z][\w-]*")
        return a * 65536 + b * 256 + c
    }
    static _All(hay, pat) {
        out := [], pos := 1
        while (pos := RegExMatch(hay, pat, &m, pos)) {
            out.Push(m[0])
            pos += Max(1, StrLen(m[0]))
        }
        return out
    }

    ; ------------------------------------------------------- the event monitor
    ; The wildcard hook AxWindow supports is a FALLBACK -- dispatch only reaches
    ; it when no element-specific hook matched -- so it cannot see the events
    ; that matter. Listening on the document itself does, and for each one the
    ; same ancestor walk dispatch uses says which AHK handler will run. That
    ; answers "my click does nothing" directly: the event is there, and either
    ; a hook owns it or nothing does.
    ToggleMonitor() => this.Mon ? this.StopMonitor() : this.StartMonitor()
    StartMonitor() {
        if this.Mon
            return
        this._monFns := Map()
        for t in ["click", "dblclick", "mousedown", "change", "focusin", "keydown", "contextmenu"] {
            fn := this._MakeMon(t)
            this._monFns[t] := fn
            try this.T.Doc.attachEvent("on" t, fn)
        }
        this.Mon := true
        try this.W.AddClass("insmon", "on")
        this.ShowDrawer(true)
        this.EvLogger("monitoring click, dblclick, mousedown, change, focusin, keydown, "
               . "contextmenu on the target", "i")
    }
    StopMonitor() {
        if !this.Mon
            return
        this.Mon := false
        if !this._TargetGone() {
            for t, fn in this._monFns
                try this.T.Doc.detachEvent("on" t, fn)
        }
        this._monFns := Map()
        try this.W.RemoveClass("insmon", "on")
        this.EvLogger("monitor stopped", "i")
    }
    _MakeMon(type) => (*) => this._MonHit(type)
    _MonHit(type) {
        try {
            ev := this.T.Doc.parentWindow.event
            el := ev.srcElement
            if !IsObject(el)
                return
            extra := ""
            if (type = "keydown")
                try extra := " key " ev.keyCode
            who := ""
            if this.T.Hooks.Has(type)
                who := this._HookOwner(el, this.T.Hooks[type])
            site := (who != "") ? AxInspector.SiteOf(this.T, type, who) : ""
            this.EvLogger(type extra "  " AxInspector.Describe(el)
                   . (who != "" ? "   -> #" who (site != "" ? "  " site : "")
                                : "   (no AHK hook)"),
                     who != "" ? "" : "i")
        }
    }

    ; ------------------------------------------------------- AHK panel actions
    _AhkClick(ev) {
        act := AxInspector._ActOf(ev, "data-act")
        if (act = "" || !IsObject(this.Sel))
            return
        el := this.Sel, id := AxWindow._Attr(el, "id")
        try {
            switch act {
                case "click":  el.click(), this.EvLogger("clicked " AxInspector.Describe(el))
                case "focus":  el.focus(), this.EvLogger("focused " AxInspector.Describe(el))
                case "scroll": el.scrollIntoView(), this.EvLogger("scrolled into view")
                case "flash":  this._Flash(el)
                case "copysel":
                    A_Clipboard := AxInspector.Describe(el)
                    this.EvLogger("copied " A_Clipboard)
                case "cssseed":
                    this._CssSeed()
                case "setval":
                    if (id = "")
                        return this.EvLogger("no id, so no control to set", "e")
                    v := this.W.El("insVal").value
                    this.T.Value(id, v)
                    this.EvLogger("g.Value(" Chr(34) id Chr(34) ", " Chr(34) v Chr(34) ")", "c")
                case "addcls", "delcls":
                    c := Trim(this.W.El("insCls").value)
                    if (c = "")
                        return
                    if (act = "addcls")
                        AxWindow._SetClass(el, c, true), this.EvLogger("+ ." c)
                    else
                        AxWindow._SetClass(el, c, false), this.EvLogger("- ." c)
                    this._FillTab(1)
            }
        } catch as e
            this.EvLogger(e.Message, "e")
    }
    ; three quick pulses of the highlight: finds an element on a busy page
    ; faster than reading a rectangle off the screen
    _Flash(el) {
        this.Highlight(el)
        loop 3 {
            try this.T.Doc.getElementById("axInspectHL").style.display := "none"
            Sleep(70)
            try this.T.Doc.getElementById("axInspectHL").style.display := "block"
            Sleep(70)
        }
    }

    ; -------------------------------------------------------------- drawer
    ToggleDrawer() => this.ShowDrawer(!this.Drawer)
    ShowDrawer(on) {
        this.Drawer := on
        try this.W.BodyClass("drawer", on)
        try on ? this.W.AddClass("insdrawer", "on") : this.W.RemoveClass("insdrawer", "on")
        if on
            try this.W.El("insCmd").focus()
    }
    _WinKey(ev) {
        k := 0
        try k := ev.keyCode
        if (k != 27)                                     ; Esc
            return
        if this.Picking {
            this.StopPick()
            return
        }
        this.ToggleDrawer()
    }

    ; ------------------------------------------------------------- console
    ; There is no eval here: IE11 in edge mode dropped execScript, and nothing
    ; in this process can compile an AHK expression at run time either. What
    ; there is instead is a small verb language over the things the inspector
    ; already holds -- the document and the AxWindow -- which covers most of
    ; what a console gets used for and cannot go wrong quietly.
    EvLogger(msg, cls := "") {
        try {
            this.W.Append("insLog", "<div class='" cls "'>"
                . AxWindow._Esc(String(msg)) "</div>")
            el := this.W.El("insLog")
            el.scrollTop := el.scrollHeight
        }
    }
    _CmdKey(ev) {
        k := 0
        try k := ev.keyCode
        if (k = 27) {                                   ; Esc closes the drawer
            this.ShowDrawer(false)
            return
        }
        if (k = 13) {                                   ; Enter
            line := ""
            try line := Trim(this.W.El("insCmd").value)
            try this.W.El("insCmd").value := ""
            if (line = "")
                return
            this.Hist.Push(line), this.HistAt := this.Hist.Length + 1
            this.EvLogger("> " line, "c")
            this._Run(line)
            return
        }
        if (k = 38 || k = 40) {                         ; history, up / down
            if !this.Hist.Length
                return
            this.HistAt += (k = 38) ? -1 : 1
            this.HistAt := Max(1, Min(this.Hist.Length + 1, this.HistAt))
            try this.W.El("insCmd").value :=
                (this.HistAt > this.Hist.Length) ? "" : this.Hist[this.HistAt]
            try ev.returnValue := false
        }
    }
    _Run(line) {
        sp := InStr(line, " ")
        verb := StrLower(sp ? SubStr(line, 1, sp - 1) : line)
        rest := sp ? Trim(SubStr(line, sp + 1)) : ""
        el := this.Sel
        needs := (*) => IsObject(el) ? true : (this.EvLogger("select an element first", "e"), false)
        try {
            switch verb {
                case "help", "?":
                    this.EvLogger("sel <css>          select the first match in the page`n"
                           . "count <css>        how many match`n"
                           . "html               outerHTML of the selection`n"
                           . "text <s>           set innerText`n"
                           . "attr n=v           set an attribute (omit =v to read)`n"
                           . "css prop: value    set an inline style`n"
                           . "class +n / -n      add or remove a class`n"
                           . "value <s>          set the bound AxGui control's value`n"
                           . "click | focus      dispatch on the selection`n"
                           . "toast <s>          target.Toast`n"
                           . "theme dark|light   target.SetTheme`n"
                           . "accent <#rrggbb>   target.SetAccent`n"
                           . "tint <#rrggbb|off> target.SetTint`n"
                           . "refresh | clear", "i")
                case "clear":
                    this.W.Html("insLog", "")
                case "refresh":
                    this.Refresh(), this.EvLogger("tree rebuilt: " this.Nodes.Length " nodes", "i")
                case "sel":
                    n := this.T.Doc.querySelector(rest)
                    if !IsObject(n)
                        return this.EvLogger("no match", "e")
                    this._Show(n, this._IndexOf(n))
                    this.EvLogger(AxInspector.Describe(n))
                case "count":
                    this.EvLogger(this.T.Doc.querySelectorAll(rest).length " match(es)")
                case "html":
                    if needs()
                        this.EvLogger(el.outerHTML)
                case "text":
                    if needs()
                        el.innerText := rest, this.EvLogger("ok")
                case "attr":
                    if !needs()
                        return
                    if (eq := InStr(rest, "=")) {
                        n := Trim(SubStr(rest, 1, eq - 1)), v := Trim(SubStr(rest, eq + 1))
                        el.setAttribute(n, v), this.EvLogger("ok"), this._FillTab(1)
                    } else
                        this.EvLogger(AxWindow._Attr(el, rest))
                case "css":
                    if !needs()
                        return
                    c := InStr(rest, ":")
                    if !c
                        return this.EvLogger("css prop: value", "e")
                    el.style.setAttribute(AxInspector._Camel(Trim(SubStr(rest, 1, c - 1))),
                                          Trim(SubStr(rest, c + 1)))
                    this.EvLogger("ok")
                case "class":
                    if !needs()
                        return
                    op := SubStr(rest, 1, 1), nm := Trim(SubStr(rest, 2))
                    if (op != "+" && op != "-")
                        return this.EvLogger("class +name  or  class -name", "e")
                    AxWindow._SetClass(el, nm, op = "+"), this.EvLogger("ok"), this._FillTab(1)
                case "value":
                    if !needs()
                        return
                    id := AxWindow._Attr(el, "id")
                    if (id = "")
                        return this.EvLogger("the selection has no id", "e")
                    this.T.Value(id, rest), this.EvLogger("ok")
                case "click":
                    if needs()
                        el.click(), this.EvLogger("ok")
                case "focus":
                    if needs()
                        el.focus(), this.EvLogger("ok")
                case "toast":
                    this.T.Toast(rest), this.EvLogger("ok")
                case "theme":
                    this.T.SetTheme(rest), this.EvLogger("ok")
                case "accent":
                    this.T.SetAccent(rest), this.EvLogger("ok")
                case "tint":
                    this.T.SetTint(rest = "off" ? "" : rest), this.EvLogger("ok")
                default:
                    this.EvLogger("unknown verb " Chr(34) verb Chr(34) " -- try help", "e")
            }
        } catch as e
            this.EvLogger(e.Message, "e")
    }
    ; "background-color" -> "backgroundColor": IE's style object is camelCase
    static _Camel(prop) {
        out := "", up := false
        loop parse prop {
            if (A_LoopField = "-") {
                up := true
                continue
            }
            out .= up ? StrUpper(A_LoopField) : A_LoopField
            up := false
        }
        return out
    }

    ; ------------------------------------------------------------- highlight
    Highlight(el) {
        if this._TargetGone()
            return
        try {
            doc := this.T.Doc
            hl := doc.getElementById("axInspectHL")
            if !IsObject(el) {
                if IsObject(hl)
                    hl.style.display := "none"
                return
            }
            if !IsObject(hl) {
                doc.body.insertAdjacentHTML("beforeend",
                    "<div id='axInspectHL' style='position:fixed;z-index:2147483000;"
                  . "pointer-events:none;display:none;background:rgba(96,205,255,.22);"
                  . "outline:1px solid #60cdff'></div>")
                hl := doc.getElementById("axInspectHL")
            }
            r := el.getBoundingClientRect()
            st := hl.style
            st.left := Round(r.left) "px", st.top := Round(r.top) "px"
            st.width := Round(r.right - r.left) "px"
            st.height := Round(r.bottom - r.top) "px"
            st.display := "block"
        }
    }

    ; ------------------------------------------------------------------ pick
    TogglePick() => this.Picking ? this.StopPick() : this.StartPick()
    ; "LButton" here is a BLOCKING hotkey -- it has to be, or picking an
    ; element would also press the button under the cursor. It is scoped by
    ; HotIfWinActive to the inspected window, so a leak could only ever deaden
    ; clicks in that one window rather than the whole desktop, and _PickTick
    ; below stops the session if that window goes away or if picking has simply
    ; been left on. Nothing in this library may block input globally.
    StartPick() {
        if this.Picking
            return
        this.Picking := true
        this._pickT0 := A_TickCount
        try this.W.AddClass("inspick", "on")
        if !this.HasOwnProp("_pickFn")
            this._pickFn := (*) => this._PickTick()
        SetTimer(this._pickFn, 60)
        try {
            HotIfWinActive("ahk_id " this.T.Gui.Hwnd)
            Hotkey("~*Escape", (*) => this.StopPick(), "On")
            Hotkey("LButton", (*) => this._PickConfirm(), "On")
            HotIf()
        }
    }
    StopPick() {
        if !this.Picking
            return
        this.Picking := false
        try this.W.RemoveClass("inspick", "on")
        if this.HasOwnProp("_pickFn")
            SetTimer(this._pickFn, 0)
        try {
            HotIfWinActive("ahk_id " this.T.Gui.Hwnd)
            Hotkey("~*Escape", "Off")
            Hotkey("LButton", "Off")
            HotIf()
        }
    }
    ; Sixteen times a second, so it does the least it can: move the highlight
    ; and name the element in the trail. Filling the panels here meant
    ; recomputing every style on every mouse move, which is what made picking
    ; feel like treacle. The panels are filled once, on confirm.
    _PickTick() {
        ; the two ways a pick session can be orphaned: the window it belongs to
        ; is gone, or it was started and forgotten
        if (this._TargetGone() || A_TickCount - this._pickT0 > 120000) {
            this.StopPick()
            return
        }
        el := this._ElementUnderCursor()
        if !IsObject(el)
            return
        same := false
        try same := (el = this.Hot)
        if same
            return
        this.Hot := el
        this.Highlight(el)
        try this.W.Html("crumbs", AxInspector.DescribeHtml(el)
            . " <span class='ins-dim'>" AxInspector.SizeOf(el) "</span>")
    }
    _PickConfirm() {
        el := this._ElementUnderCursor()
        this.StopPick()
        if !IsObject(el)
            return
        i := this._IndexOf(el)
        this._Show(el, i)
        if i
            try AxRich.At(this.W, "tree").SelectKeys([i])
    }
    _ElementUnderCursor() {
        try {
            MouseGetPos(&mx, &my, &win)
            if (win != this.T.Gui.Hwnd)
                return ""
            pt := Buffer(8, 0)
            NumPut("Int", mx, pt, 0), NumPut("Int", my, pt, 4)
            DllCall("user32\ScreenToClient", "Ptr", this.T.Gui.Hwnd, "Ptr", pt)
            return this.T.Doc.elementFromPoint(NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int"))
        }
        return ""
    }

    ; ------------------------------------------------------------------ close
    Close() {
        try this.W.Close()
    }
    _Teardown() {
        this.StopPick()
        this.StopMonitor()
        ; If the target is going away too, its document is already being pulled
        ; apart underneath us. A COM call into a half-freed document does not
        ; raise something catchable -- it faults -- so the only safe move is
        ; not to make it.
        if !this._TargetGone() {
            try {
                hl := this.T.Doc.getElementById("axInspectHL")
                if IsObject(hl)
                    hl.parentNode.removeChild(hl)
            }
        }
        try AxInspector._open.Delete(this.T.Gui.Hwnd)
        try AxInspector._opening.Delete(this.T.Gui.Hwnd)
    }
    _TargetGone() {
        try {
            if this.T.Closing
                return true
            return !DllCall("IsWindow", "Ptr", this.T.Gui.Hwnd, "Int")
        }
        return true
    }
}
