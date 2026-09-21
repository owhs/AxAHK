#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\..\lib\AxRichAll.ahk
#Include %A_LineFile%\..\AxStudio.Gen.ahk
#Include %A_LineFile%\..\AxStudio.Panes.ahk
#Include %A_LineFile%\..\AxStudio.RibbonUi.ahk
#Include %A_LineFile%\..\AxStudio.Templates.ahk
#Include %A_LineFile%\..\AxStudio.Complete.ahk
#Include %A_LineFile%\..\AxStudio.Form.ahk
#Include %A_LineFile%\..\AxStudio.Wizards.ahk
#Include %A_LineFile%\..\AxStudio.Helpers.ahk
#Include %A_LineFile%\..\AxStudio.Logic.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk
#Include %A_LineFile%\..\AxStudio.Data.ahk
#Include %A_LineFile%\..\AxStudio.Pre.ahk
#Include %A_LineFile%\..\AxStudio.Build.ahk
#Include %A_LineFile%\..\AxStudio.Gallery.ahk
#Include %A_LineFile%\..\AxStudio.ImportGui.ahk
#Include %A_LineFile%\..\AxStudio.Map.ahk
#Include %A_LineFile%\..\AxStudio.StepsUi.ahk
#Include %A_LineFile%\..\AxStudio.Files.ahk
#Include %A_LineFile%\..\AxStudio.ImportLogic.ahk
#Include %A_LineFile%\..\AxStudio.DotNetUi.ahk
#Include %A_LineFile%\..\AxStudio.Arrange.ahk
#Include %A_LineFile%\..\AxStudio.PkgUi.ahk
#Include %A_LineFile%\..\AxStudio.Titlebar.ahk
#Include %A_LineFile%\..\AxStudio.Menus.ahk
#Include %A_LineFile%\..\AxStudio.Update.ahk
#Include %A_LineFile%\..\AxStudio.Snips.ahk

; Part of AxStudio, not a program on its own. Running this file directly would
; only load a class and stop, so it hands over to the entry point instead.
if (A_LineFile = A_ScriptFullPath) {
    SplitPath(A_LineFile, , &axDir)
    axEntry := axDir "\AxStudio.ahk"
    if FileExist(axEntry)
        Run('"' A_AhkPath '" "' axEntry '"')
    else
        MsgBox("Run studio\AxStudio.ahk -- this file is only one part of it.", "AxStudio")
    ExitApp()
}

; =============================================================================
;  AxStudio.App.ahk -- the designer window.
;
;  Three panes and a canvas, built with the same library it designs for. The
;  canvas is not a drawing of your window: it is the markup AxGui would
;  generate, rendered by the same stylesheet, so what you drag is the control
;  itself.
;
;  Two things here are load-bearing and easy to undo by accident:
;
;  1. Messages from the canvas are queued and handled on a *fresh* AHK thread.
;     A click posted from JavaScript arrives while that JavaScript is still on
;     the stack; rewriting the document from inside it -- which is what every
;     edit does -- leaves Trident dispatching an event into nodes that no
;     longer exist. Answering on a new thread costs a millisecond and is the
;     difference between a designer and one that stops responding on the first
;     drop.
;
;  2. #content and the status bar are both positioned by hand. AxGui only
;     builds the #shell box when the page has a nav, and this window has none,
;     so the status bar would otherwise sit in the flow directly under the
;     menu bar and print itself across the top of the panes.
; =============================================================================

class AxStudio extends AxGui {
    static Ver := "0.9"                 ; the studio's release (version.json "axstudio")
    StudioVer() => AxStudio.Ver
    ; When this window started, and the newest of the studio's and the
    ; library's files at that moment -- so About can say the code on disk has
    ; moved on since, and a restart is what it takes to see it.
    static StartedAt := A_Now
    static CodeAt := ""
    ; Set by AxStudio.Probe.ahk: the studio run to look at itself. It keeps a
    ; store of its own, shows without taking focus, and skips the start screen.
    static Probing := false
    static OnReadyHook := ""

    __New() {
        this.Dir := A_ScriptDir
        ; studio\data, beside the studio (AxStudioPaths.Data); the probe keeps
        ; a store of its own
        this.Store := AxStudio.Probing ? A_Temp "\axstudio_probe" : AxStudioPaths.Data()
        if !DirExist(this.Store)
            try DirCreate(this.Store)
        if !AxStudio.Probing
            AxStudioPaths.Adopt(this.Store)
        this.SettingsPath := this.Store "\studio.ini"
        this.AutoPath := this.Store "\autosave.axs.json"
        this.LogPath := this.Store "\studio.log"
        this.TrimLog()

        ; Component packs before anything reads the catalogue: they add
        ; toolbox entries, and the toolbox is drawn on the first refresh.
        AxComp.Scan(AxStudioPaths.Lib)
        ; and keep components\_all.ahk in step, so "drop a folder in" really is
        ; all there is to it -- #Include takes a path, not a glob
        if DirExist(AxStudioPaths.Lib "\components")
            AxComp.WriteAll(AxStudioPaths.Lib "\components\_all.ahk",
                            AxStudioPaths.Lib "\components")
        this.P := AxTpl.Build("settings")
        this.Ce := ""            ; the code editor, once the page is up (Wire)
        this._ceTarget := ""     ; the piece of code the editor was loaded with
        this._ceLoaded := ""     ; and its text then (or when it was last kept)
        this._cleanSig := ""     ; the project as it was built or opened (ConfirmDiscard)
        this.Undo := AxUndo()
        this.SelIds := []
        this.PageId := ""
        this.Issues := []        ; what AxLint found on the last refresh
        this._skin := ""         ; the look the canvas is currently dressed for
        this.Out := []           ; what the running preview has said
        this.LogPos := 0
        this.RunX := 0, this.RunY := 0, this.RunW := 0, this.RunH := 0, this.RunPage := ""
        this._tailFn := ObjBindMethod(this, "TailLog")   ; _Tail() is the method
        this.Testing := false     ; the canvas left alone, so the design can be tried
        this.PackShown := ""      ; the control the Component viewer is showing
        this.RightTab := "props"
        this.ToolFilter := ""
        this.PropFind := ""                 ; what the inspector's find box holds
        this.PropTab := "props"             ; its tab: props | layout | events
        this.PropSort := "cat"              ; its rows by category, or "az"
        this.PropHints := 0                 ; the sentences under the rows, shown
        this.RawOpen := 0                   ; a table's data as text, open under its editor
        this.LastBuild := ""                ; {Ok, Msg, Exe, When} of this session's last compile
        this.RunBlock := ""                 ; {Msg, Fn, Line, When}: why the last run did not start
        this.CodeFind := ""                 ; and the Code list's
        this.CodeTarget := ""
        this.PieceView := "steps"           ; how a piece of code opens: steps | code (the last used)
        this._flip := false                 ; going between Steps and Code by hand
        this.NavList := []                  ; the places been, for Back and Forward
        this.NavAt := 0
        this._navGoing := false
        ; Which workspace is in front: design (the canvas, with the side
        ; panes), logic, code or app -- each with the whole middle to itself.
        this.Ws := "design"
        ; The panel along the bottom: Problems or Output, under every
        ; workspace. Folded, it is a strip of tabs that still shows the counts.
        this.PanelTab := "lint"
        this.PanelOpen := 0
        this.PanelH := 200
        ; A side pane that is put away keeps the width it had, so bringing it
        ; back does not guess.
        this.LeftShown := 1
        this.RightShown := 1
        this.LeftW := 240
        this.RightW := 312
        this.Grid := 8
        this.AutoSecs := 15         ; how often the spare copy is written, 0 = never
        this.LiveDelay := 900       ; how long typing stops before Live re-runs
        ; How the preview opens: "design" exactly as the program will (its size,
        ; where it starts, maximised or not), "place" the same but where the
        ; last run was, "last" where and as big as the last run was
        this.PreviewOpens := "design"
        this.AutoToFile := 0        ; autosave writes your file, not only a spare copy
        this.ShowWelcome := 1       ; the start screen
        this.AskWhereFirst := 1     ; offer a file to save into when starting something new
        ; Where Ahk2Exe was found, or where you said it is. Remembered so a
        ; portable copy is not lost to a search that finds the installed one.
        this.Ahk2Exe := ""
        this._autoFn := ""
        this.Snap := 1
        this.Guides := 1
        this.ShowGrid := 1
        this.Live := 0
        this.PreviewPid := 0
        this.Recent := []
        ; Property groups folded away. Seeded rather than empty: the Window tab
        ; is twelve groups, and all of them open is a pane you scroll instead
        ; of read. Whatever you fold or unfold is saved over this.
        this.Shut := Map()
        for k in ["themeeditor", "behaviour", "frame", "advanced", "menubar",
                  "statusbar", "titlebaritems", "barswrittenasautohotkeyinstead", "code", "popover"]
            this.Shut[k] := 1
        this.Compact := 0                   ; toolbox: icons only
        this.Dense := 0                     ; inspector rows packed tight, as they used to be
        this.AutoHideBar := 0               ; the bottom bar out of the way until the pointer is near
        this.LeftTab := "tools"             ; the left pane shows the Toolbox, or the Outline
        this.LogicSec := "values"           ; the section Logic shows
        this.MacroSel := ""                 ; the macro open under Macros
        this.LookSel := "design"            ; what the Look workspace shows
        this.TabMode := false               ; setting the tab order on the canvas
        this.Zoom := 1                      ; the canvas, scaled
        this.AlAnchor := "each"             ; lining up: to each other | the last selected | the page
        this.TabSeq := []                   ; the controls clicked so far, in order
        this.OpenMax := false
        this.LookMode := "dark"             ; and how it shows a built-in look
        this.SheetOpen := false             ; the data sheet is over everything
        this.SheetNode := ""                ; and this is the control it edits
        this.AppSec := "windows"            ; and App
        this.UiTheme := "dark"              ; the studio's own look, not the design's
        this.Busy := false
        this._inbox := []
        this._fields := []
        this._markedId := ""
        this._liveTimer := ""
        this._ranCode := ""        ; the script the running process was built from
        this._saveText := ""
        this.IconTarget := ""               ; the field the icon picker will write to
        this.IconFind := ""
        this._drain := (*) => this.Drain()

        this.LoadSettings()
        super.__New({Title: AxStudio.Probing ? "AxStudio (probe)" : "AxStudio",
                     Width: 1440, Height: 900, MinWidth: 1000, MinHeight: 620,
                     Theme: this.UiTheme, Nav: false, Shell: false, Css: AxStudio.Asset("AxStudio.css"),
                     NoActivate: AxStudio.Probing,
                     Maximized: !AxStudio.Probing,      ; up maximised, so the start screen opens over the full window
                     X: AxStudio.Probing ? SysGet(76) + SysGet(78) + 60 : "",
                     Y: AxStudio.Probing ? 0 : ""})
        ; the menus live in the title bar (AxStudio.Titlebar.ahk); Alt still
        ; brings the classic bar back, for the keyboard
        this.AddMenuBar(this.Menus(), {Reveal: "alt"})
        this.AddTitleBar(AxTitle.Items(this), {ShowTitle: false})
        this.AddStatusBar([{Id: "msg", Text: "Ready", Icon: "E930", Grow: true},
                           {Id: "sel", Text: "", Width: 230},
                           {Id: "save", Text: "No changes", Width: 150},
                           {Id: "path", Text: "Untitled", Width: 270, Align: "right"}])
        this.AddHtml("vaxdShell", AxStudio.Layout())
        this.OnReady((*) => this.Wire())
        this.OnClose((*) => this.OnQuit())
    }

    ; ------------------------------------------------------------- assets
    static Asset(name) {
        try return FileRead(A_ScriptDir "\" name, "UTF-8")
        return ""
    }
    ; The regions are placed by AXD.shell in AxStudio.js, from the numbers
    ; SendShell hands it; the CSS only gives them somewhere to start.
    static Layout() {
        return '<div id="axdTop"></div>'
            .  '<div id="axdLeft"><div class="axd-pane">'
            .  '<div id="axdLeftTabs"></div>'
            .  '<div class="axd-body" id="axdLeftBody"></div>'
            .  '<div id="axdTreeHead"></div>'
            .  '<div class="axd-body" id="axdTreeBody"></div></div></div>'
            .  '<div class="axd-split" id="axdSplitL"></div>'
            .  '<div id="axdMid">'
            .    '<div class="axd-ws" id="axdWsDesign">'
            .      '<div id="axdBar"></div>'
            .      '<div id="axdWinStrip"></div>'
            .      '<div id="axdCanvasWrap"><div id="axdPaper">'
            .        '<div id="axdFrame"></div><div id="axdHud"></div>'
            .        '<div id="axdSizeGrip" data-tip="Drag to resize the window"></div>'
            .      '</div></div>'
            .    '</div>'
            .    '<div class="axd-ws" id="axdWsLogic"><div class="axd-wsbody" id="axdLogic"></div></div>'
            .    '<div class="axd-ws" id="axdWsApp"><div class="axd-wsbody" id="axdApp"></div></div>'
            .    '<div class="axd-ws" id="axdWsLook"><div class="axd-wsbody" id="axdLook"></div></div>'
            .    '<div class="axd-ws" id="axdWsMap"><div class="axd-wsbody" id="axdMap"></div></div>'
            .    '<div class="axd-ws" id="axdWsSteps"><div class="axd-wsbody axs-ws" id="axdSteps">'
            .      '<div id="axsHead" class="axd-piecebar"></div>' AxStepsUi.Html() '</div></div>'
            .    '<div class="axd-ws" id="axdCode"><div id="axdCodeNav">'
            .      '<div class="axd-cnfind"><input id="axdCodeFind" class="axd-rfindbox" autocomplete="off"'
            .        ' placeholder="Filter -- a control, an event"></div>'
            .      '<div id="axdCodeList"></div></div><div id="axdCodeHdr">'
            .      '<span id="axdCodeTitle">Code</span><span class="axd-sig" id="axdCodeSig"></span>'
            .      '<span id="axdCodeMsg"></span>'
            .      '<div class="axd-viewseg" id="axdCodeSteps" title="The same piece as a flowchart you can change without typing    Ctrl+3">'
            .        '<span><span class="ico">&#xE8FD;</span>Steps</span><span class="on"><span class="ico">&#xE943;</span>Code</span></div>'
            .      '<div class="axd-hbtn" id="axdCodeCheck">Check syntax</div>'
            .      '<div class="axd-hbtn" id="axdCodeSnip">Insert a snippet</div></div>'
            .      '<div id="axdCodeBody">' AxCodeEditor.Html("axdCe", AxStudio.CeCfg(), "") '</div>'
            .    '</div>'
            .  '</div>'
            .  '<div class="axd-split" id="axdSplitR"></div>'
            .  '<div id="axdRight"><div class="axd-pane">'
            .  '<div class="axd-rhead" id="axdRightTabs"></div>'
            .  '<div class="axd-rfind"><input id="axdPropFind" class="axd-rfindbox" autocomplete="off"'
            .    ' placeholder="Find a property -- width, tip, colour...">'
            .    '<span class="axd-ptools" id="axdPropTools"></span></div>'
            .  '<div class="axd-ptabs" id="axdPropTabs"></div>'
            .  '<div class="axd-body" id="axdRightBody"></div></div></div>'
            .  '<div class="axd-split" id="axdSplitB"></div>'
            .  '<div id="axdPanel"><div class="axd-tabsrow" id="axdPanelTabs"></div>'
            .    '<div class="axd-pbody" id="axdIssues"></div>'
            .    '<div class="axd-pbody" id="axdOut"></div></div>'
            .  '<div id="axdGal"></div>'
            .  '<div id="axdBridge"><textarea id="axdIn"></textarea><textarea id="axdBridgeData"></textarea>'
            .    '<div id="axdPrerender"></div></div>'
            .  AxForm.Markup()
    }

    ; ---------------------------------------------------------------- run
    Run() {
        AxStudio.CodeAt := AxStudio.NewestCode().At
        this.OpenMax := !AxStudio.Probing
        v := AxStudio.CodeVersion()
        this.WriteLog("start  AxStudio " AxStudio.Ver (v.Hash != "" ? ", code " v.Hash : "")
               . (AxStudio.Probing ? " (probe)" : ""))
        this.Show()
        ; A probe keeps out of the way: shown without taking focus, then put
        ; under every other window, where it still renders for its photographs.
        ; HWND_BOTTOM, and SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE.
        if AxStudio.Probing
            try DllCall("SetWindowPos", "Ptr", this.Hwnd, "Ptr", 1, "Int", 0, "Int", 0,
                        "Int", 0, "Int", 0, "UInt", 0x13)
        ; the studio takes the whole screen; the probe keeps to its corner
        if this.OpenMax
            try this.Maximize()
        return this
    }
    Wire() {
        this.FitShell()
        for name in AxRich.Components
            try AxRich.Use(this, name)
        js := AxStudio.Asset("AxStudio.js")
        if (js != "")
            this.Js(js)
        js := AxStudio.Asset("AxStudio.Grid.js")
        if (js != "")
            this.Js(js)
        js := AxStudio.Asset("AxStudio.Map.js")
        if (js != "")
            this.Js(js)
        js := AxStudio.Asset("AxStudio.Steps.js")
        if (js != "")
            this.Js(js)
        this.Js("AXD.init();")
        ; The Code workspace is the library's code editor (lib\components\
        ; CodeEditor): AutoHotkey's words and the project's own ranked as you
        ; type, the parameters of what you call, AutoHotkey's own check of the
        ; piece being edited as you pause, find and replace, folding, the map.
        this.Ce := AxCodeEditor(this, "axdCe", AxStudio.CeCfg())
        this.Ce.UseAhk({Lint: true, Warn: false, Wrap: (t) => this.CodeWrap()})
        this.Ce.OnChange((text, *) => this.CodeTyped())
        this.Ce.OnSave((*) => (this.CodeTyped(), this.Save()))
        ; the canvas draws a data grid's own rows, read by the page
        AxGen.ReadRows := (t) => this.Doc.parentWindow.AXG.rowsJson(t)
        this.PushCompletions()
        this.SendShell()
        this.On("click", "axdBridge", (*) => this.Bridge())
        AxForm.Wire(this)
        this.On("click", "axdTop", (el, ev) => this.BarClick(ev))
        this.On("click", "axdWinStrip", (el, ev) => this.StripClick(ev))
        this.On("dblclick", "axdWinStrip", (el, ev) => this.StripDbl(ev))
        this.On("contextmenu", "axdWinStrip", (el, ev) => this.StripMenu(ev))
        this.On("click", "axdPanelTabs", (el, ev) => this.PanelClick(ev))
        this.On("click", "axdGal", (el, ev) => AxGallery.Click(this, ev))
        this.On("keyup", "axdGalFind", (el, ev) => AxGallery.KeyUp(this, ev))
        this.On("click", "axdIssues", (el, ev) => AxPanes.RightClick(this, ev))
        this.On("click", "axdOut", (el, ev) => AxPanes.RightClick(this, ev))
        this.On("click", "axdRightTabs", (el, ev) => this.RightHeadClick(ev))
        this.On("keyup", "axdPropFind", (el, ev) => AxPanes.FindKey(this, ev))
        this.On("click", "axdPropTools", (el, ev) => AxPanes.ToolClick(this, ev))
        this.On("click", "axdPropTabs", (el, ev) => AxPanes.ToolClick(this, ev))
        this.On("click", "axdLogic", (el, ev) => AxPanes.WsClick(this, ev))
        this.On("click", "axdApp", (el, ev) => AxPanes.WsClick(this, ev))
        this.On("click", "axdLook", (el, ev) => AxPanes.WsClick(this, ev))
        this.On("click", "axdSteps", (el, ev) => AxPanes.WsClick(this, ev))
        AxTitle.Wire(this)
        this.On("dblclick", "axdApp", (el, ev) => this.AppDbl(ev))
        this.On("click", "axdLeftBody", (el, ev) => AxPanes.LeftClick(this, ev))
        this.On("click", "axdTreeBody", (el, ev) => AxPanes.LeftClick(this, ev))
        this.On("click", "axdLeftTabs", (el, ev) => this.LeftTabClick(ev))
        this.On("click", "axdRightBody", (el, ev) => AxPanes.RightClick(this, ev))
        this.On("click", "axdBar", (el, ev) => this.BarClick(ev))
        this.On("click", "axdCodeNav", (el, ev) => this.CodeNavClick(ev))
        this.On("keyup", "axdCodeFind", (el, ev) => this.CodeFindKey(ev))
        this.On("click", "axdCodeCheck", (*) => this.CheckSyntax())
        this.On("click", "axdCodeSteps", (*) => this.CodeAsSteps())
        this.On("click", "axdCodeSnip", (*) => this.SnippetMenu())
        this.On("keyup", "axdToolFilter", (*) => this.FilterTools())
        this.On("keyup", "axdIconFind", (*) => this.FilterIcons())
        this.On("keyup", "axdPkgFind", (el, ev) => AxPkgUi.FindKey(this, ev))
        this.On("keyup", "axnFind", (el, ev) => AxNetUi.Key(this, "axnFind", ev))
        this.On("keyup", "axnType", (el, ev) => AxNetUi.Key(this, "axnType", ev))
        this.On("change", "axdIconFind", (*) => this.FilterIcons())
        this.On("change", "axdToolFilter", (*) => this.FilterTools())
        this.On("keydown", "*", (el, ev) => this.Key(el, ev))
        this.On("contextmenu", "axdTreeBody", (el, ev) => this.DeferMenu(this.TreeMenu(), ev))
        this.ApplyDensity()
        this.SkinCanvas()
        this.ShowWs()
        this.PageId := this.P.Pages().Length ? this.P.Pages()[1].Id : ""
        this.Refresh()
        this.ArmAutoSave()
        this.MarkCleanSoon()                      ; the starting project: nothing of yours in it yet
        this.Status("msg", "Drag from the Toolbox onto the canvas. F5 runs it.")
        ; After the first paint, not during it: the welcome blocks, and a modal
        ; put up inside OnReady would sit on top of a half-drawn window.
        if (AxStudio.OnReadyHook != "")
            SetTimer((*) => AxStudio.OnReadyHook.Call(this), -1500)
        if (this.ShowWelcome && !AxStudio.Probing)
            SetTimer((*) => AxWiz.Welcome(this), -60)
    }
    ; #content and the status bar are placed by hand, because a page with no
    ; nav never gets the #shell box that would otherwise size them.
    FitShell() {
        top := 0, bot := 0
        try top += this.El("titlebar").offsetHeight
        try {
            mb := this.El("axMenuBar")
            if IsObject(mb)
                top += mb.offsetHeight
        }
        try {
            sb := this.El("axStatusBar")
            if IsObject(sb) {
                bot := (this.AutoHideBar && !this.PanelOpen) ? 0 : sb.offsetHeight
                sb.style.position := "absolute"
                sb.style.left := "0", sb.style.right := "0", sb.style.bottom := "0"
                sb.style.zIndex := "5"
            }
        }
        try {
            c := this.El("content")
            c.style.position := "absolute"
            c.style.left := "0", c.style.right := "0"
            c.style.top := top "px", c.style.bottom := bot "px"
            c.style.margin := "0", c.style.padding := "0"
            c.style.overflow := "hidden"
        }
    }
    ; The studio's own theme. The design keeps whatever it asks for, and the
    ; canvas is skinned separately -- that is the whole point of the split.
    SetUi(theme) {
        this.UiTheme := theme
        this.SetTheme(theme)
        this.SaveSettings()
        this.AfterLook()
    }
    ; The look changed and the pane it was changed FROM must stay put. This
    ; is AfterLook without the Refresh, for the fields you type into.
    AfterLookCanvas() {
        this._skin := ""                  ; force it: the look is what changed
        this.SkinIfNeeded()
        this.RefreshCanvas()
        this.P.Dirty := true
        this.SaveState()
        this.QueueLive()
    }
    AfterLook() {
        this.FitShell()
        this._skin := ""                  ; force it: the look is what changed
        this.SkinIfNeeded()
        this.Refresh()
    }
    ; The paper is dressed for one window's stylesheet and theme. Each window
    ; may ask for its own, so this runs on every canvas draw and does nothing
    ; at all unless what the design wants has moved away from what it wears.
    SkinIfNeeded() {
        want := AxGui.SheetName(this.P.Stylesheet) "|" this.PreviewTheme() "|" this.Theme
             . "|" this.P.W.Look "|" this.P.W.Css "|" this.P.Accent
        if (want = this._skin)
            return
        this._skin := want
        this.SkinCanvas()
    }

    ; ----------------------------------------------------------- save state
    ; Autosaving is only reassuring if you can see it happening. The part says
    ; which of the three states the project is in, and never leaves a stale
    ; "autosaved" sitting there once the work has actually been saved.
    SaveState(text := "") {
        if (text != "")
            this._saveText := text
        else if this.P.Dirty
            this._saveText := "Unsaved changes"
        else if (this.P.Path != "")
            this._saveText := "Saved"
        else
            this._saveText := "No changes"
        try {
            this.Status("save", this._saveText)
            this.StatusIcon("save", this.P.Dirty ? "E7BA" : "E73E")
        }
        try AxTitle.Sync(this)
    }
    ; The autosave interval is a setting, so the timer is set up rather than
    ; started once and forgotten. Zero seconds turns it off entirely.
    ArmAutoSave() {
        if this._autoFn
            SetTimer(this._autoFn, 0)
        this._autoFn := ""
        if (this.AutoSecs <= 0)
            return
        this._autoFn := (*) => this.AutoSave()
        SetTimer(this._autoFn, this.AutoSecs * 1000)
    }
    ClearAutoSave() {
        try {
            if FileExist(this.AutoPath)
                FileDelete(this.AutoPath)
        }
    }

    ; ------------------------------------------------------------ logging
    TrimLog() {
        try {
            if (FileExist(this.LogPath) && FileGetSize(this.LogPath) > 400000)
                FileDelete(this.LogPath)
        }
    }
    WriteLog(msg) {
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " msg "`n", this.LogPath, "UTF-8")
    }
    ; Everything a person asks for goes through here. Without it a command
    ; that raises is simply nothing happening -- the hardest fault there is to
    ; report and the easiest to ship, because it looks like a dead button.
    ;
    ; The name goes into studio.log on the way IN, before the work. If the
    ; studio then hangs or vanishes, the log still says what was asked for.
    Try(what, fn) {
        this.WriteLog("do  " what)
        try
            return fn()
        catch as e {
            this.Problem(what " failed: " e.Message)
            this.Say("error", what " failed: " e.Message)
            if (e.HasOwnProp("File") && e.File != "")
                this.Say("error", "    " e.File " line " e.Line)
            if (e.HasOwnProp("Extra") && e.Extra != "")
                this.Say("error", "    " e.Extra)
            try {
                for line in StrSplit(StrReplace(e.Stack, "`r", ""), "`n")
                    if (Trim(line) != "")
                        this.Say("error", "    " Trim(line))
            }
            this.WriteLog("    " e.File " line " e.Line)
            this.SetMid("out")
        }
    }
    Problem(msg) {
        this.WriteLog("PROBLEM  " msg)
        this.Status("msg", msg)
        this.CodeMsg(msg, "err")
    }

    ; ------------------------------------------------------------- bridge
    Js(code) {
        try {
            d := this.Doc
            s := d.createElement("script")
            s.text := code
            head := d.getElementsByTagName("head").item(0)
            head.appendChild(s)
            head.removeChild(s)
        } catch as e
            this.WriteLog("Js failed: " e.Message)
    }
    Send(obj) {
        try this.El("axdIn").value := AxJson.Stringify(obj, "")
        this.Js("AXD.pump();")
    }
    ; Put a value where JavaScript can read it, then run an expression that does.
    SendTo(json, call) {
        try this.El("axdIn").value := json
        this.Js(call)
    }
    PushCompletions() {
        if IsObject(this.Ce)
            try this.Ce.SetWordSet("studio", AxComplete.Words(this.P), "ahk")
            catch as e
                this.WriteLog("completions: " e.Message " (" e.What ", line " e.Line ")")
    }
    ; the code editor's settings: the whole of the Code workspace's body
    static CeCfg() => {lang: "ahk", theme: "auto", gutter: true, fold: true, suggest: true, status: true,
        minimap: true, style: "height:100%;border:0;border-radius:0;", class: "fill"}
    ; What the piece being edited sits between when AutoHotkey checks it: a
    ; handler's body inside its function. The whole generated script is not
    ; checked as you look at it (its #Include is relative to where it will be).
    CodeWrap() {
        t := this.CodeTarget
        if !IsObject(t) || t.Kind = "readonly"
            return ""
        if (t.Kind = "event") {
            n := this.P.Find(t.Id)
            if !IsObject(n) || t.Index > n.Ev.Length
                return ""
            e := n.Ev[t.Index]
            return [AxGen.HandlerName(n, e["name"]) "(" AxCat.Sig(e["name"]) ") {`n", "`n}"]
        }
        return ["", ""]
    }
    ; The canvas posts by clicking a hidden element. That click arrives while
    ; the posting JavaScript is still running, so the payload is only taken
    ; here; the work happens on a new thread once that stack has unwound.
    Bridge() {
        try raw := this.El("axdBridgeData").value
        catch
            return
        if (raw = "")
            return
        this._inbox.Push(raw)
        SetTimer(this._drain, -1)
    }
    Drain() {
        if this.Busy
            return
        this.Busy := true
        try {
            while this._inbox.Length {
                raw := this._inbox.RemoveAt(1)
                try {
                    m := AxJson.Parse(raw)
                    this.Message(AxJson.Get(m, "t", ""), AxJson.Get(m, "p", Map()))
                } catch as e
                    this.Problem(SubStr(raw, 1, 60) " -> " e.Message " (" e.File ":" e.Line ")")
            }
        }
        this.Busy := false
    }
    Message(t, p) {
        ; Anything done on the canvas dismisses what is open over it. The
        ; studio's own JavaScript stops the click before it reaches the
        ; library's document handler, so this has to be said rather than
        ; assumed -- and it is said here, once, rather than in each case.
        try this.CloseContextMenu()
        G := (k, d := "") => AxJson.Get(p, k, d)
        switch t {
        case "map":
            if (G("act") = "go")
                return AxMap.Open(this, G("id"))
            if (G("act") = "rebuild")
                return AxMap.Paint(this, true)
            if (G("act") = "rule")
                return AxMap.Rule(this, G("id"))
            if (G("act") = "mode")
                return AxMap.SetMode(this, G("v"))
            if (G("act") = "connect")
                return this.Try("connect", (*) => AxMap.Connect(this, G("a"), G("b")))
            if (G("act") = "steps")
                return (AxSteps.Pc := AxSteps.FromKey(G("key")), AxSteps.Sel := "", AxMap.SetMode(this, "steps"))
            if (G("act") = "addstep")
                return this.Try("add a step", (*) => AxMap.AddStep(this, G("key")))
            return
        case "steps":
            return this.Try("steps", (*) => AxStepsUi.Msg(this, p))
        case "tabpick":
            return this.TabPick(G("id"))
        case "zoom":
            return this.ZoomStep(G("d", 1) > 0 ? 1 : -1)
        case "align":
            return this.ApplyAlign(G("op"), G("items", []))
        case "sheetcsv":
            return this.SheetCsv()
        case "led":
            ; a list editor in the inspector: the rows, as the text they are
            if G("first", 0)
                this.Mark()
            AxPanes.Apply(this, G("field", "p_arg"), G("text", ""))
            return
        case "sheet":
            this.SheetOpen := false
            if G("cancel", 0)
                return this.Status("msg", "The data is as it was.")
            n := this.P.Find(this.SheetNode)
            if !IsObject(n)
                return
            this.Mark()
            n.Arg := G("text", "")
            this.Refresh()
            return this.Status("msg", "Kept the data for " n.Name ".")
        case "select":
            ids := G("sel", "")
            this.SelIds := (ids is Array) ? ids : []
            this.Reflect(false)
        case "open":
            this.SelIds := [G("id")]
            this.Reflect(false)
            this.OpenPrimaryEvent()
        case "page":
            this.PageId := G("id")
            this.SelIds := []
            this.Refresh()
        case "tab":
            n := this.P.Find(G("id"))
            if IsObject(n)
                n.L["activetab"] := G("tab", 1)
        case "ctx":
            this.NodeMenu(G("id"), G("x", 0), G("y", 0))
        case "hud":
            this.HudAction(G("act"), G("id"), G("x", 0), G("y", 0))
        case "panes":
            ; Zero is a pane put away, not a pane nought pixels wide: the
            ; width it had is kept so bringing it back does not guess.
            k := G("kind"), v := G("v", 0)
            if (k = "L") {
                this.LeftShown := (v > 0) ? 1 : 0
                if (v > 0)
                    this.LeftW := v
            } else if (k = "R") {
                this.RightShown := (v > 0) ? 1 : 0
                if (v > 0)
                    this.RightW := v
            } else if (k = "B") {
                ; the panel's splitter: a height is a panel wanted open at it,
                ; and a double-click on it is the panel put away
                this.PanelOpen := (v > 0) ? 1 : 0
                if (v > 0)
                    this.PanelH := v
                this.SendShell()
                this.ShowWs()
                this.RenderPanel()
            }
            this.SaveSettings()
            this.Bar()
        case "create":
            if (G("to") = "")
                this.Insert(G("type"))
            else
                this.DoCreate(G("type"), G("to"), G("tab", 0), G("index", 1), G("place", "flow"), G("x", 0), G("y", 0))
        case "move":
            ids := G("ids", "")
            this.DoMove((ids is Array) ? ids : [], G("to"), G("tab", 0), G("index", 1),
                        G("place", "flow"), G("x", 0), G("y", 0), G("copy", 0))
        case "resize":
            this.DoResize(G("id"), G("w", ""), G("h", ""), G("x", ""), G("y", ""))
        case "size":
            this.SetWindowSize(G("w", 0), G("h", 0))
        case "cmd":
            this.RunCommand(G("id"))
        case "jserr":
            this.Problem("Canvas: " G("msg"))
        default:
            this.WriteLog("unknown message: " t)
        }
    }

    ; -------------------------------------------------------- selection
    Sel => this.SelIds.Length ? this.SelIds[this.SelIds.Length] : ""
    IsSel(id) {
        for x in this.SelIds
            if (x = id)
                return true
        return false
    }
    SetSel(id, add := false) {
        if (id = "")
            this.SelIds := []
        else if add {
            if this.IsSel(id) {
                out := []
                for x in this.SelIds
                    if (x != id)
                        out.Push(x)
                this.SelIds := out
            } else
                this.SelIds.Push(id)
        } else
            this.SelIds := [id]
        this.Reflect()
    }
    SelNodes() {
        out := []
        for id in this.SelIds {
            n := this.P.Find(id)
            if IsObject(n)
                out.Push(n)
        }
        return out
    }
    Primary() {
        n := this.P.Find(this.Sel)
        return IsObject(n) ? n : ""
    }

    ; ------------------------------------------------------- more wizards
    ; A popover is markup, and markup is easier to start from than to invent.
    PopShapeMenu() {
        this.ShowMenu([{Label: "A card with a heading", Click: this.PopShapeFn("card")},
                       {Label: "A profile card", Click: this.PopShapeFn("profile")},
                       {Label: "A short menu of links", Click: this.PopShapeFn("list")},
                       {Label: "A little form", Click: this.PopShapeFn("form")}])
    }
    PopShapeFn(kind) => (*) => this.PopShape(kind)
    PopShape(kind) {
        n := this.Primary()
        if !IsObject(n)
            return
        nl := Chr(10)
        switch kind {
        case "profile":
            m := '<div style="padding:12px 14px;min-width:210px">' nl
               . '  <div style="font-weight:600">Jane Doe</div>' nl
               . '  <div style="opacity:.65;font-size:11px">jane@example.com</div>' nl
               . '  <hr style="border:none;border-top:1px solid rgba(128,128,128,.3);margin:10px 0">' nl
               . '  <ax-link id="popSignOut">Sign out</ax-link>' nl
               . "</div>"
        case "list":
            m := '<div style="padding:6px;min-width:180px">' nl
               . '  <div class="dd-item" id="popNew">New</div>' nl
               . '  <div class="dd-item" id="popOpen">Open...</div>' nl
               . '  <div class="dd-item" id="popPrefs">Preferences</div>' nl
               . "</div>"
        case "form":
            m := '<div style="padding:12px 14px;width:240px">' nl
               . '  <div style="margin-bottom:6px">Rename</div>' nl
               . '  <ax-text id="popName" value="" placeholder="New name"></ax-text>' nl
               . '  <div style="margin-top:10px"><ax-button id="popOk" kind="accent">Rename</ax-button></div>' nl
               . "</div>"
        default:
            m := '<div style="padding:12px 14px;min-width:200px">' nl
               . '  <div style="font-weight:600;margin-bottom:4px">Heading</div>' nl
               . "  <div>Anything here is ordinary page markup.</div>" nl
               . "</div>"
        }
        this.Mark()
        n.L["pop"] := m
        if (n.Lay("popw", "") = "")
            n.L["popw"] := 240
        this.RightTab := "props"
        this.Refresh()
        this.Status("msg", "Popover markup added. Controls inside it work with On() and Value() as usual.")
    }

    ; A dialog is a call, not a layout, so the wizard writes the call. Both
    ; of these live in AxStudio.Wizards.ahk now, as one form each.
    DialogWizard() => AxWiz.Dialog(this)
    MenuWizard() => AxWiz.Menu(this)
    ; Both of the above land in the init code, which is where a call that runs
    ; once when the window opens belongs.
    InsertCode(code, what) {
        this.Mark()
        this.InsertInit(code)
        this.EditScript("init")
        this.Refresh()
        this.Status("msg", what " added to the init code.")
    }
    ; Append to the startup code without marking undo or redrawing: the
    ; wizards do both themselves, and often have more to write first.
    InsertInit(code) {
        if (Trim(code) = "")
            return
        cur := RTrim(String(this.P.Init), "`r`n")
        this.P.Init := (Trim(cur) = "") ? code : cur "`n`n" code
    }

    ; ---------------------------------------------------------- icon picker
    ; The picker takes over the right-hand pane rather than opening a window:
    ; you are choosing an icon *for* something, and a modal over the top would
    ; cover the thing you are choosing it for.
    OpenIcons(fieldId) {
        this.IconTarget := fieldId
        this.RightTab := "icons"
        this.Reflect(false)
        try this.El("axdIconFind").focus()
    }
    FilterIcons() {
        try this.IconFind := this.El("axdIconFind").value
        try this.Html("axdIconGrid", AxIcons.Grid(this.IconFind))
    }
    PickGlyph(code) {
        this.WriteIcon(code)
        this.RightTab := (this.IconTarget = "w_icon") ? "page" : "props"
        this.Reflect(false)
    }
    ; The picker knows which box it was opened from, so it writes there and the
    ; ordinary property machinery does the rest.
    WriteIcon(value) {
        id := this.IconTarget
        if (id = "")
            return
        this.RightTab := (id = "w_icon") ? "page" : "props"
        this.Reflect(false)
        try this.El(id).value := value
        AxPanes.Commit(this, id)
    }
    IconFromFile() {
        f := FileSelect(3, , "Pick an icon", "Images (*.ico;*.png;*.jpg;*.gif;*.svg)")
        if (f != "")
            this.WriteIcon(f)
    }
    ; shell32.dll,13 and friends: the file, then which one inside it.
    IconFromDll() {
        f := FileSelect(3, A_WinDir "\System32\shell32.dll", "Pick a DLL or EXE", "Programs (*.dll;*.exe)")
        if (f = "")
            return
        v := AxWiz.IconIndex(this, f)
        if (v != "")
            this.WriteIcon(v)
    }

    ; ---------------------------------------------------------- mutations
    Mark() {
        this.Undo.Push(this.P)
        this.P.Dirty := true
    }
    DoCreate(type, toId, tab, index, place, x, y) {
        if !AxCat.Has(type)
            return
        parent := this.BoxNode(toId)
        if !IsObject(parent)
            return
        this.Mark()
        n := this.P.NewNode(type)
        AxPanes.PlaceOne(n, place)
        if (place = "abs")
            n.L["x"] := x, n.L["y"] := y
        if (tab > 0)
            n.L["tab"] := tab
        this.P.Insert(parent, n, index)
        this.SelIds := [n.Id]
        this.Refresh()
        this.Status("msg", "Added " AxCat.Get(type).Label ".")
    }
    DoMove(ids, toId, tab, index, place, x, y, copy) {
        parent := this.BoxNode(toId)
        if !IsObject(parent) || !ids.Length
            return
        nodes := []
        for id in ids {
            n := this.P.Find(id)
            if (IsObject(n) && n.Type != "Page")
                nodes.Push(n)
        }
        if !nodes.Length
            return
        for n in nodes {
            if AxProject.IsAncestor(n, parent) {
                this.Status("msg", "A container cannot be dropped inside itself.")
                return
            }
        }
        this.Mark()
        moved := []
        dx := 0, dy := 0
        ; A group dropped at free positions keeps its shape: each moves by
        ; what the first (the one under the mouse) moved. One that had no
        ; place of its own yet is set down a step below the one before.
        shift := ""
        if (place = "abs" && nodes.Length > 1 && nodes[1].Lay("place", "flow") = "abs"
            && AxProject.Same(nodes[1].Parent, parent))
            shift := {X: x - nodes[1].Lay("x", 0), Y: y - nodes[1].Lay("y", 0)}
        for i, n in nodes {
            if copy {
                m := AxNode.FromMap(n.ToMap())
                this.P.Renumber(m)
                n := m
            } else {
                ; the index the canvas measured counts the list without this node
                if (AxProject.Same(n.Parent, parent) && this.P.IndexOf(n) < index)
                    index--
                this.P.Remove(n)
            }
            ; dragging something that is docked re-docks it to whichever edge
            ; you let go nearest, rather than quietly making it absolute
            if (n.Lay("place") = "dock" && place = "abs") {
                n.L["dock"] := AxStudio.NearestEdge(x, y, this.P.Width, this.P.Height)
            } else {
                wasAbs := (n.Lay("place", "flow") = "abs"), ox := n.Lay("x", 0), oy := n.Lay("y", 0)
                AxPanes.PlaceOne(n, place)
                if (place = "abs") {
                    if (IsObject(shift) && wasAbs)
                        n.L["x"] := Max(0, ox + shift.X), n.L["y"] := Max(0, oy + shift.Y)
                    else {
                        n.L["x"] := Max(0, x + dx), n.L["y"] := Max(0, y + dy)
                        dx += 12, dy += 12
                    }
                }
            }
            n.L["tab"] := (tab > 0) ? tab : ""
            this.P.Insert(parent, n, index)
            index++
            moved.Push(n.Id)
        }
        this.SelIds := moved
        this.Refresh()
    }
    DoResize(id, w, h, x := "", y := "") {
        n := this.P.Find(id)
        if !IsObject(n)
            return
        this.Mark()
        if (w != "")
            n.L["w"] := Round(w)
        if (h != "")
            n.L["h"] := Round(h)
        if (x != "" && n.Lay("place") = "abs")
            n.L["x"] := Max(0, Round(x)), n.L["y"] := Max(0, Round(y))
        this.Refresh()
    }
    static NearestEdge(x, y, w, h) {
        best := "top", d := y
        if (h - y < d)
            best := "bottom", d := h - y
        if (x < d)
            best := "left", d := x
        if (w - x < d)
            best := "right"
        return best
    }
    ; Dragging the corner of the canvas is the same edit as typing in the
    ; Width and Height boxes, so it goes through the model and comes back.
    SetWindowSize(w, h) {
        if (w < 200 || h < 120)
            return
        this.Mark()
        this.P.Width := Round(w), this.P.Height := Round(h)
        this.Refresh()
        this.Status("msg", "Window " Round(w) " x " Round(h))
    }
    BoxNode(id) {
        if (id = "" || id = "root")
            return this.CurPage() ? this.CurPage() : this.P.Root
        n := this.P.Find(id)
        return IsObject(n) ? n : (this.CurPage() ? this.CurPage() : this.P.Root)
    }
    CurPage() {
        if (this.PageId != "") {
            n := this.P.Find(this.PageId)
            if (IsObject(n) && n.Type = "Page")
                return n
        }
        pages := this.P.Pages()
        if pages.Length {
            this.PageId := pages[1].Id
            return pages[1]
        }
        this.PageId := ""
        return ""
    }

    ; ------------------------------------------------------------ drawing
    ; The last run's refusal is about a script that has changed since. While
    ; it is up, every change asks AutoHotkey again, a moment later: it goes
    ; the moment the script parses, and says the new reason when it does not.
    RecheckRun(quiet := true) {
        if !IsObject(this.RunBlock)
            return
        code := AxGen.Script(this.P, this.ScriptPath(), "", this.PreBody())
        r := AxStudio.Validate(code, this.ScriptPath())
        this.RunBlock := r.Ok ? "" : AxStudio.BlockOf(r.Msg, code)
        this.RenderPanel()
        if !quiet
            this.Status("msg", r.Ok ? "It parses now -- nothing stops it running." : "It still will not run: " this.RunBlock.Msg)
    }
    ; A handler with nothing in it that is what stops the run: take it away.
    DropEmptyHandler() {
        b := this.RunBlock
        if (!IsObject(b) || b.Fn = "")
            return
        this.Mark()
        tally := {N: 0}
        for w in this.P.Wins
            this.P.Walk(w.Root, AxStudio.DropEmptyFn(b.Fn, tally))
        if !tally.N
            return this.Status("msg", b.Fn "() has code in it, so it stays -- open it to see the line.")
        this.Refresh()
        this.RecheckRun(false)
    }
    static DropEmptyFn(fn, tally) => (n) => AxStudio.DropEmptyOn(n, fn, tally)
    static DropEmptyOn(n, fn, tally) {
        i := n.Ev.Length
        while (i >= 1) {
            e := n.Ev[i]
            if (AxGen.HandlerName(n, e["name"]) = fn && Trim(RegExReplace(e["code"], "m)^\s*;.*$"), " `t`r`n") = "")
                n.Ev.RemoveAt(i), tally.N++
            i--
        }
        return false
    }
    Refresh() {
        if IsObject(this.RunBlock) {
            if !this.HasOwnProp("_recheckFn")
                this._recheckFn := ObjBindMethod(this, "RecheckRun", true)
            SetTimer(this._recheckFn, -1200)
        }
        this.RefreshCanvas()
        this.Bar()
        this.Reflect(false)
        this.PushPalette()
        this.QueueLive()
        this.SaveState()
    }
    RefreshCanvas() {
        if (this.Ws != "design")
            return
        this.SkinIfNeeded()
        try this.DrawCanvas(this.CurPage())
        catch as e
            this.Problem("Canvas: " e.Message " (" e.File ":" e.Line ")")
        this.Send({cmd: "opts", grid: this.Grid, snap: this.Snap, guides: this.Guides})
        this.Send({cmd: "after", sel: this.SelIds})
        if this.TabMode
            this.SendTab()
    }
    ; The whole window, not just its content: title bar, menu bar, the page
    ; rail and the status bar, in the order and the markup the library itself
    ; uses. MirrorCss below points the sheet's own frame rules at these, so the
    ; canvas is the window rather than an impression of it.
    DrawCanvas(page) {
        P := this.P
        paper := this.El("axdPaper")
        Z := this.Zoom
        paper.style.width := Round(P.Width * Z) "px"
        paper.style.height := Round(P.Height * Z) "px"
        try {
            fr := this.El("axdFrame")
            fr.style.width := P.Width "px", fr.style.height := P.Height "px"
            fr.style.transform := (Z = 1) ? "none" : "scale(" Z ")"
            fr.style.transformOrigin := "0 0"
        }
        paper.style.backgroundColor := "#" this.ThemeBack(P.Theme = "light" ? "light" : "dark")
        nav := AxGen.NavHtml(P, page ? page.Id : "")
        menu := (Trim(P.MenuBar) != "" && Trim(P.Menus) = "") ? AxChrome.MenuHtml("&Menu") : AxChrome.MenuHtml(P.Menus)
        status := (Trim(P.StatusBar) != "" && Trim(P.Status) = "")
                ? AxChrome.StatusHtml("msg | (set by the AddStatusBar expression) | grow", P.Resizable ? true : false)
                : AxChrome.StatusHtml(P.Status, P.Resizable ? true : false)
        ; the paper wears the body's classes, so the mirrored rules -- which are
        ; the sheet's own, rewritten to point here -- match exactly as they do
        ; on a real window. Its corners are round as Windows 11 draws them,
        ; unless the design says not, or its sheet never was (9x, XP).
        paper.className := AxStudio.PaperClass(this) (menu != "" ? " has-menubar" : "")
                        . (status != "" ? " has-statusbar" : "") (P.Frame ? "" : " axd-noframe")
                        . (P.PageScroll = "never" ? " axd-noscroll" : "")
                        . ((P.RoundCorners && AxGui.SheetRound(P.Stylesheet = "" ? "win11" : P.Stylesheet)) ? "" : " axd-square")

        head := ""
        heads := (P.Headings != "") ? P.Headings : (nav = "")
        if (IsObject(page) && heads && page.Prop("title", "") != "")
            head := "<h1>" AxTags.E(page.Prop("title")) "</h1>"
        pid := IsObject(page) ? page.Id : "root"
        h := AxStudio.TitlebarHtml(P) menu
          .  '<div class="axd-shell">'
          .    (nav != "" ? '<div class="axd-sidebar">' nav "</div>" : "")
          .    '<div class="axd-content" id="axdContent">'
          .      '<div id="axdPage" class="page visible axd axd-box axd-pagebox ax-limit axd-id-' pid '">'
          .      head AxGen.Canvas(P, page) '</div></div></div>' status
        this.El("axdFrame").innerHTML := h
        AxTags.Expand(this.Doc)
        this.CanvasEditors()
        ; a burger first in a bar with no icon lines up over the rail, as it
        ; will in the window (AxWindow.Titlebar's TitleAlign)
        try {
            tb := this.Doc.querySelector("#axdPaper .axd-titlebar .axtb-slot .axtb-item")
            if (IsObject(tb) && InStr(" " tb.className " ", " kind-burger "))
                AxWindowTitlebar.AlignBurger(tb, this.Doc.querySelector("#axdPaper .axd-titlebar .app-icon"),
                    this.Doc.querySelector("#axdPaper .axd-sidebar .nav-item .ico"))
        }
        ; a control set to fill the height fills it here as it will in the
        ; window, by the same script (AxGui.FitJs) measuring the same way.
        ; The page box is its limit (ax-limit): it is drawn at least as tall
        ; as the window, to take drops, so it is the window's height here.
        try {
            if IsObject(this.El("axdPaper").querySelector(".ax-growy")) && AxGui.UseFit(this.Doc)
                this.Doc.parentWindow.axFit(this.El("axdPaper"))
        }
        ; the grid: dots where the lines cross, faint while you look and
        ; stronger while something is being placed on it -- lines on every
        ; cell drew over the design, and it never looked like the window
        try this.El("axdContent").style.backgroundImage := ""
        try AxWindow._SetClass(this.El("axdContent"), "axd-gridon", this.ShowGrid && this.Grid >= 2)
        try this.SetExtraCss("axdgrid", AxStudio.GridCss(this.Grid))
        this.LabelNodes(page)
        this.RestoreTabs()
        this._MakeFocusable()
    }
    ; The window sized to what it holds: as tall as the page needs, with the
    ; room the stylesheet leaves round the content, and wider only if
    ; something does not fit sideways. Measured on the canvas, which is the
    ; window, with anything set to fill the height at its least -- so a list
    ; that grows comes out at the height it was given, not at whatever the
    ; window happened to be.
    FitWindow() {
        if (this.Ws != "design")
            this.SetWs("design")
        P := this.P
        try m := this.FitMeasure()
        catch as e
            return this.Problem("Fit the window: " e.Message)
        if (m.H = 0 && m.W <= 0)
            return this.Status("msg", "The window already fits what it holds.")
        this.Mark()
        P.Height := Max(120, Round(P.Height + m.H))
        if (m.W > 0)
            P.Width := Round(P.Width + m.W)
        if (P.MinHeight > P.Height)
            P.MinHeight := P.Height
        this.Refresh()
        this.Status("msg", "The window is now " P.Width " x " P.Height ", to fit what it holds.")
    }
    ; How much taller (H, negative for shorter) and wider (W) the window has
    ; to be for its page to fit exactly -- measured on the canvas, with
    ; anything that fills the height put back to its least first.
    FitMeasure() {
        c := this.El("axdContent")
        if !IsObject(c)
            throw Error("there is no canvas to measure")
        Px(v) => RegExMatch(String(v), "-?[\d.]+", &m) ? Number(m[0]) : 0
        grow := c.querySelectorAll(".ax-growy")
        loop grow.length {
            el := grow.item(A_Index - 1)
            mh := ""
            try mh := el.currentStyle.minHeight
            el.style.height := (mh != "" && mh != "auto" && mh != "0px") ? mh : ""
        }
        sc := c.offsetHeight ? (c.getBoundingClientRect().height / c.offsetHeight) : 1
        ; the end of what the page holds, not of the page: the canvas's page
        ; box is drawn at least as tall as the window, to take drops
        pg := this.El("axdPage")
        box := IsObject(pg) ? pg : c
        s := this.Doc.createElement("div")
        s.style.cssText := "height:0;margin:0;padding:0;border:0;clear:both;display:block"
        box.appendChild(s)
        y := (s.getBoundingClientRect().top - c.getBoundingClientRect().top) / (sc ? sc : 1) - c.clientTop + c.scrollTop
        box.removeChild(s)
        if IsObject(pg)
            y += Px(pg.currentStyle.paddingBottom) + Px(pg.currentStyle.borderBottomWidth)
        dh := Ceil(y + Px(c.currentStyle.paddingBottom) - c.clientHeight)
        dw := c.scrollWidth - c.clientWidth
        ; and let them grow again, as they were
        try this.Doc.parentWindow.axFit(this.El("axdPaper"))
        return {H: dh, W: dw}
    }    ; A code editor on the canvas is coloured by its own script, as it will be
    ; when it runs -- read-only, and deaf to the mouse, so the canvas's own
    ; picking and dragging are untouched.
    CanvasEditors() {
        try {
            ; the canvas's own, not the Code workspace's editor
            list := this.Doc.querySelectorAll("#axdPaper .axce[data-lang]")
            if !list.length || !AxRich.UseJs(this, AxCodeEditor.JsPath)
                return
            W := this.Doc.parentWindow
            loop list.length {
                el := list.item(A_Index - 1)
                W.AXCE.make(el.id, AxJson.Stringify(Map("lang", el.getAttribute("data-lang"),
                    "theme", el.getAttribute("data-theme"), "design", 1, "status", 0), ""))
            }
        }
    }
    ; The paper wears the look the *project* asks for, not the studio's, which
    ; is what lets you design a light win98 window inside a dark win11 editor.
    ; It must never inherit the studio's has-menubar / has-statusbar either:
    ; the studio has both, and the canvas would then subtract the height of
    ; bars the designed window does not have.
    static PaperClass(s) {
        return "theme-" s.PreviewTheme() " sheet-" AxGui.SheetName(s.P.Stylesheet)
    }
    PreviewTheme() {
        t := this.P.Theme
        return (t = "system") ? AxWindow.SystemTheme() : (t = "light" ? "light" : "dark")
    }
    ; The markup lib/ui/frame.html injects, with the ids left off -- the
    ; studio's own frame owns those. Everything here is styled by class except
    ; #titlebar and #titleText, which MirrorCss covers.
    static TitlebarHtml(P) {
        if !P.Frame
            return ""                       ; a bare page: no title bar to draw
        cap := P.TitleShow ? AxTags.E(P.Title) : ""
        ; the buttons the window will really have: a dialog with neither box
        ; shows only its close button, as it does when it runs
        return '<div class="axd-titlebar">' AxStudio.FrameIcon(P.Icon)
             . '<div class="axtb-slot">' AxChrome.ItemsHtml(P.TitleItems, "left") '</div>'
             . '<div class="axd-titletext"' (P.TitleCenter ? ' style="text-align:center"' : "") '>'
             . cap '</div>'
             . '<div class="axtb-slot">' AxChrome.ItemsHtml(P.TitleItems, "right") '</div>'
             . (P.MinimizeBox ? '<div class="winbtn ico">&#xE921;</div>' : "")
             . (P.MaximizeBox ? '<div class="winbtn ico">&#xE922;</div>' : "")
             . '<div class="winbtn ico">&#xE8BB;</div></div>'
    }
    ; The icon in the canvas's title bar, as the window will show it: none for
    ; "none", the glyph for a glyph, the picture for a file, and for "auto"
    ; the one AutoHotkey gives a script.
    static FrameIcon(spec) {
        v := Trim(String(spec))
        if (v = "" || v = "none" || v = "0")
            return ""
        if RegExMatch(v, "^[0-9A-Fa-f]{4,5}$")
            return '<span class="app-icon ico">&#x' v ';</span>'
        static seen := Map()                ; the canvas is redrawn on every edit
        if seen.Has(v)
            return seen[v]
        src := ""
        try {
            if (v = "auto")
                src := AxSys.IconDataUri(A_AhkPath, 32)
            else if (SubStr(v, 1, 5) = "data:")
                src := v
            else if RegExMatch(v, "i)\.(png|jpe?g|gif|bmp|svg)$")
                src := AxWindow.FileUrl(v)
            else
                src := AxSys.IconDataUri(v, 32)
        }
        return seen[v] := (src != "") ? '<span class="app-icon"><img alt="" src="' AxTags.E(src) '"></span>'
                                      : '<span class="app-icon ico">&#xE737;</span>'
    }
    ; The sheet styles the window frame by id -- #titlebar, #titleText, #shell,
    ; #sidebar, #content -- and those ids belong to the studio's own window.
    ; Rather than copy the rules by hand for eight stylesheets and every one
    ; written after this, the live sheets are walked and every rule mentioning
    ; one of them is re-emitted against the canvas's classes. A theme, an accent
    ; or a brand new stylesheet reaches the preview with no work at all.
    static IdMap := [["#titlebar", ".axd-titlebar"], ["#titleText", ".axd-titletext"],
                     ["#shell", ".axd-shell"], ["#sidebar", ".axd-sidebar"],
                     ["#content", ".axd-content"]]
    ; One selector, pointed at the canvas: body becomes the paper, the frame's
    ; ids become the canvas's classes, and anything else is scoped under the
    ; paper so it cannot reach the studio around it.
    static Rescope(sel, root := "#axdPaper") {
        out := ""
        for part in StrSplit(sel, ",") {
            q := Trim(part)
            if (q = "")
                continue
            ; the elements html and body only: "\bbody\b" also took the body
            ; out of a class -- .exp-body became .exp-#axdPaper, so an
            ; expander's (and every *-body's) rules never reached the canvas
            q := RegExReplace(q, "(?<![\w.#-])(html|body)(?![\w-])", root)
            for pair in AxStudio.IdMap
                q := StrReplace(q, pair[1], pair[2])
            if (InStr(q, root) != 1)
                q := root " " q
            out .= (out = "" ? "" : ",") q
        }
        return out
    }
    ; Walk one live stylesheet and return a copy of it aimed at the canvas.
    ; `only` limits it to the rules that mention the window frame.
    Rewrite(sheet, only := false, root := "#axdPaper", pick := "") {
        css := ""
        rules := ""
        try rules := sheet.rules
        if !IsObject(rules)
            return ""
        loop rules.length {
            sel := "", body := ""
            try {
                r := rules.item(A_Index - 1)
                sel := r.selectorText
                body := r.style.cssText
            }
            if (sel = "" || body = "")
                continue
            if (only && !RegExMatch(sel, "#(shell|sidebar|content|titlebar|titleText)\b"))
                continue
            if (pick != "" && !RegExMatch(sel, pick))
                continue
            out := AxStudio.Rescope(sel, root)
            if (out = "")
                continue
            ; A rule written for the document as a whole has just become a rule
            ; about the paper, and the paper's box belongs to the studio: the
            ; margin is what centres it in the canvas. A sheet saying
            ; "body { margin: 0 }" used to shove the preview into the corner
            ; the moment the two looks stopped matching.
            if RegExMatch(sel, "i)^\s*(html|body)\s*(,|$)")
                body := AxStudio.PaintOnly(body)
            if (Trim(body) = "")
                continue
            css .= out "{" body "}`n"
        }
        return css
    }
    ; What a design may say about the paper: what it paints and writes with,
    ; and nothing that would move or resize it.
    static PaintOnly(decls) {
        static drop := "margin|margin-[a-z]+|padding|padding-[a-z]+|position|top|left|right|bottom"
                     . "|width|height|min-width|min-height|max-width|max-height"
                     . "|overflow|overflow-[xy]|display|float|clear|box-shadow"
                     . "|border|border-[a-z-]+|transform|z-index|zoom"
        ; by removal rather than by keeping a list: a declaration that survives
        ; is left byte for byte, which matters for a background carrying a data
        ; URI (they contain semicolons, and splitting on those wrecks them)
        out := RegExReplace(decls, "i)(^|;)\s*(" drop ")\s*:[^;]*", "$1")
        return Trim(RegExReplace(out, ";\s*(;|$)", "$1"), " `t;")
    }

    ; Read a stylesheet's rules without letting it touch the studio.
    ;
    ; The design's sheet used to be injected into the live document to be read
    ; through the CSSOM, which put it after the studio's own sheet and restyled
    ; the editor for as long as it was there -- and for good if anything threw
    ; in between. A <style media="not all"> is parsed and readable exactly the
    ; same way, and never applies to anything.
    ReadSheet(css, holder := "axdSrcRead", root := "#axdPaper", pick := "") {
        st := ""
        try {
            doc := this.Doc
            st := doc.getElementById(holder)
            if !IsObject(st) {
                st := doc.createElement("style")
                st.id := holder, st.type := "text/css"
                st.media := "not all"
                doc.getElementsByTagName("head").item(0).appendChild(st)
            }
            AxWindow._SetStyleText(st, css)
        }
        if !IsObject(st)
            return ""
        out := ""
        try out := this.Rewrite(st.styleSheet, false, root, pick)
        if (out = "")
            try out := this.Rewrite(st.sheet, false, root, pick)
        return out
    }

    ; The canvas is skinned one way, whatever the studio happens to be wearing.
    ; There used to be two routes -- mirror only the frame when the looks
    ; matched, rewrite the whole sheet when they did not -- and they did not
    ; come out the same, so changing the *studio's* theme moved and recoloured
    ; the *design*. Now the design's own sheet is always what dresses the paper.
    SkinCanvas() {
        P := this.P
        css := ""
        ; The design wears its own theme and nothing of the studio's. Every
        ; sheet the studio has loaded for itself -- the components', its own
        ; look -- is keyed on the STUDIO's body (body.theme-light .axcbtn),
        ; and reached into the canvas: in a light studio a dark design's
        ; colour button went white and a range slider's labels black; in a
        ; dark one, the other way round. So, on the paper:
        ;  - every component's sheet, the whole of it (CompCanvasCss), which
        ;    outranks the studio's copy as the sheets rank against each other
        ;    in a real window -- ahead of the theme, which has the last word;
        ;  - the design's own sheet, the whole of it;
        ;  - and first, whatever a keyed rule sets that the same selector
        ;    unkeyed does not, put back to what a window without that class
        ;    has (AxStudio.Unleak).
        comp := this.CompCanvasCss()
        src := ""
        try src := AxGui.ThemeCss(P.Stylesheet)
        if (src = "")
            try src := AxGui.ThemeCss("win11")
        design := (src != "") ? this.ReadSheet(src) : ""
        ; the studio's own sheet, when it is another: only what its keyed
        ; rules would bring in is wanted from it
        own := ""
        if (AxGui.SheetName(P.Stylesheet) != AxGui.SheetName(this.Stylesheet))
            try own := this.ReadSheet(AxGui.ThemeCss(this.Stylesheet))
        css .= AxStudio.Unleak(comp design own, comp design) comp design
        ; The accent, where a window paints it once it is up (SetAccent): an
        ; accent button, a ticked box, the page rail's marker. A canvas has
        ; no SetAccent of its own, so an Accent button used to come out grey.
        mode := this.PreviewTheme()
        hex := RegExMatch(P.Accent, "^#[0-9A-Fa-f]{6}$") ? P.Accent : this.DefaultAccentOf(P.Stylesheet, mode)
        ; .accent twice: one class more than the sheet's "body.theme-light .btn",
        ; which left a light design's accent button white, and still one fewer
        ; than a sheet's own "body.sheet-x .btn.accent"
        css .= this.ReadSheet(".btn.accent.accent{background:" hex ";border-color:" hex ";color:" (AxWindow._Luma(hex) > 0.45 ? "#000" : "#fff") "}"
             . ".switch input:checked+.sw-track.sw-track,.check input:checked+.box.box{background:" hex ";border-color:" hex "}"
             . ".segmented .seg.active.active,.progress .bar.bar,.nav-item.active.active:before,"
             . ".tab.active.active:after{background:" hex "}"
             . ".link.link,.hyperlink.hyperlink{color:" hex "}", "axdAccRead")
        ; the design's own small stylesheet, on top of the one it picked
        look := AxTheme.Css(P.W)
        if (Trim(look) != "")
            css .= this.ReadSheet(look, "axdLookRead")
        ; The live sheets carry any accent or tint the studio has already mixed
        ; in, so their frame rules are worth having on top -- but only when the
        ; design wears the same look, or they would overrule the sheet above.
        same := (AxGui.SheetName(P.Stylesheet) = AxGui.SheetName(this.Stylesheet))
             && (this.PreviewTheme() = this.Theme)
        if same {
            sheets := ""
            try sheets := this.Doc.styleSheets
            if IsObject(sheets) {
                loop sheets.length {
                    sh := sheets.item(A_Index - 1)
                    id := ""
                    try id := sh.owningElement.id
                    ; id "" is the studio's own stylesheet (AxGui's Css option), whose
                    ; #content { padding: 0 !important } is for the studio's window:
                    ; mirrored, it took every design's page edge to edge
                    if (id = "" || id = "axExtra_axdMirror" || id = "axdSrcRead" || id = "axdLookRead" || id = "axdCompRead" || id = "axdAccRead"
                        || id = "axdSpecRead" || id = "axExtra_axdSpecCss")
                        continue
                    css .= this.Rewrite(sh, true)
                }
            }
        }
        this.SetExtraCss("axdMirror", css)
    }
    ; Every component's sheet (and the packs' shared one) pointed at the
    ; paper. They do not change while the studio runs, so this is read once
    ; -- again only when a pack is installed.
    ; `root` is the box they are pointed at: the canvas, or Look's preview.
    static _compCss := Map()
    CompCanvasCss(root := "#axdPaper") {
        n := AxRich.Components.Count
        if (AxStudio._compCss.Has(root) && AxStudio._compCss[root][1] = n)
            return AxStudio._compCss[root][2]
        src := ""
        try src .= AxRich.CoreCss() "`n"
        for name in AxRich.Components
            src .= AxRich.CssText(name) "`n"
        css := this.ReadSheet(src, "axdCompRead", root)
        AxStudio._compCss[root] := [n, css]
        return css
    }
    ; What a sheet's keyed rules (body.theme-light X, body.sheet-win98 X --
    ; on the canvas #axdPaper.theme-light X) set that X alone does not, put
    ; back on the paper to what a window without the class has: text
    ; inherited, paint none. `keyed` is where the keyed rules come from;
    ; `base` what the paper already has for X, unkeyed. One rule per
    ; selector, #axdPaper X, so the design's keyed rules still outrank it.
    static Unleak(keyed, base, root := "#axdPaper") {
        static inh := "i)^(color|fill|stroke|font(-[a-z-]+)?|text-shadow|visibility|cursor|letter-spacing|line-height|text-decoration)$"
        have := Map(), want := Map(), order := []
        r := "\Q" root "\E"
        for line in StrSplit(base, "`n")
            if RegExMatch(line, "^(.*?)\{(.*)\}\s*$", &m)
                for q in StrSplit(m[1], ",")
                    if RegExMatch(Trim(q), "^" r "\s+(.+)$", &b)
                        AxStudio._Props(m[2], have, Trim(b[1]))
        for line in StrSplit(keyed, "`n") {
            if !RegExMatch(line, "^(.*?)\{(.*)\}\s*$", &m)
                continue
            for q in StrSplit(m[1], ",") {
                if !RegExMatch(Trim(q), "^" r "(?:\.(?:theme|sheet)-[\w-]+)+\s+(.+)$", &k)
                    continue
                sel := Trim(k[1])
                if !want.Has(sel)
                    order.Push(sel)
                AxStudio._Props(m[2], want, sel)
            }
        }
        out := ""
        for sel in order {
            got := have.Has(sel) ? have[sel] : Map()
            decl := ""
            for p in want[sel] {
                fam := RegExReplace(p, "-.*$")
                covered := got.Has(p) || got.Has(fam)
                if !covered
                    for g in got
                        if (SubStr(g, 1, StrLen(fam) + 1) = fam "-") {
                            covered := true
                            break
                        }
                if covered
                    continue
                if RegExMatch(p, inh)
                    decl .= p ":inherit;"
                else if (fam = "background")
                    decl .= "background-color:transparent;background-image:none;"
                else if (p = "box-shadow")
                    decl .= "box-shadow:none;"
                else if (p = "opacity")
                    decl .= "opacity:1;"
                else if (fam = "border" && InStr(p, "color"))
                    decl .= p ":currentColor;"
            }
            if (decl != "")
                out .= root " " sel "{" decl "}`n"
        }
        return out
    }
    ; the property names a rule's declarations set, into into[sel]
    static _Props(decls, into, sel) {
        if !into.Has(sel)
            into[sel] := Map()
        for d in StrSplit(decls, ";")
            if RegExMatch(Trim(d), "^([A-Za-z-]+)\s*:", &pm)
                into[sel][StrLower(pm[1])] := 1
    }
    ; The accent a stylesheet paints with when none is chosen.
    DefaultAccentOf(sheet, mode) {
        n := AxGui.SheetName(sheet)
        try {
            pair := AxGui.SheetAccent.Has(n) ? AxGui.SheetAccent[n] : AxGui.SheetAccent["win11"]
            return (mode = "light") ? pair[1] : pair[2]
        }
        return (mode = "light") ? "#005fb8" : "#60cdff"
    }
    ; The canvas needs a readable name for each element so the drag hint can
    ; say "into Card" rather than "into box n4". Option strings carry no
    ; data-* attribute, so the names go on afterwards.
    LabelNodes(page) {
        kids := IsObject(page) ? page.Kids : AxGen._Loose(this.P)
        for k in kids
            this.LabelOne(k)
        try this.El("axdPage").setAttribute("data-axd-label", IsObject(page) ? page.Prop("title", "the page") : "the window")
    }
    ; the controls that are nothing until something is written in them: on
    ; the canvas they say so, rather than being a box you cannot see
    static EmptySay := Map("Html", "Raw HTML -- nothing in it yet; write it under Content",
                           "Svg", "SVG -- nothing drawn yet",
                           "Text", "A label with no text")
    LabelOne(n) {
        try {
            el := this.El("d_" n.Id)
            if IsObject(el) {
                el.setAttribute("data-axd-label", n.Label)
                if (AxStudio.EmptySay.Has(n.Type) && Trim(String(n.Arg)) = "" && el.innerHTML = "")
                    el.setAttribute("data-axd-hint", AxStudio.EmptySay[n.Type])
            }
        }
        for k in n.Kids
            this.LabelOne(k)
    }
    ; A tabs control comes back showing panel 1; the canvas remembers which
    ; panel you were working in, so put it back.
    RestoreTabs() {
        this.P.Walk(this.P.Root, (n) => (n.Type = "Tab" ? this.ShowTabPanel(n) : false, false))
    }
    ShowTabPanel(n) {
        want := n.Lay("activetab", 1)
        if (want = "" || want = 1)
            return false
        try {
            strip := this.El("d_" n.Id)
            if !IsObject(strip)
                return false
            ; a placed tabs control is a frame round its strip and pages: the
            ; tabs are the strip's own children, not every div on every page
            if AxWindow._HasClass(strip, "tabs-frame")
                strip := strip.querySelector(".tabs")
            tabs := strip.children
            loop tabs.length {
                t := tabs.item(A_Index - 1)
                AxWindow._SetClass(t, "active", A_Index = want)
            }
            i := 1
            loop 40 {
                pn := this.El("d_" n.Id "_" i)
                if !IsObject(pn)
                    break
                AxWindow._SetClass(pn, "visible", i = want)
                i++
            }
        }
        return false
    }
    ; The design grid, as an SVG the sheet can scale. Colours are rgb() and the
    ; URI carries no "#", which would end the url() at a fragment.
    static GridUri(size) {
        if (size < 2)
            return "none"
        s := size
        return "url(`"data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20width='" s "'%20height='" s "'%3E"
            .  "%3Cpath%20d='M0%20" (s - 0.5) "H" s "M" (s - 0.5) "%200V" s "'%20fill='none'%20stroke='rgb(128,140,160)'%20stroke-opacity='.20'/%3E%3C/svg%3E`")"
    }
    ; The grid as dots, one at each crossing (GridUri's lines were a stroke on
    ; every edge of every cell). Two strengths: at rest, and while moving.
    static GridCss(size) {
        if (size < 2)
            return ""
        dot := (op) => "url(`"data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20width='" size "'%20height='" size "'%3E"
            . "%3Crect%20x='" (size - 1) "'%20y='" (size - 1) "'%20width='1'%20height='1'%20fill='rgb(128,140,160)'%20fill-opacity='" op "'/%3E%3C/svg%3E`")"
        return "#axdContent.axd-gridon { background-image: " dot(".45") "; }"
             . "#axdPaper.axd-moving #axdContent.axd-gridon { background-image: " dot(".9") "; }"
             . "body.axd-testing #axdContent.axd-gridon { background-image: none; }"
    }
    Reflect(tellCanvas := true) {
        this._markedId := ""
        ; A pane is rebuilt from a timer and from the canvas bridge, so an
        ; error in one used to arrive as a modal dialog with no context. It
        ; goes where every other one goes instead.
        ; The side panes belong to Design, so only Design builds them; Logic
        ; and App build their own page instead.
        if (this.Ws = "design") {
            try AxPanes.Left(this)
            catch as e
                this.Problem("Left pane: " e.Message " (" e.File ":" e.Line ")")
            try AxPanes.Right(this)
            catch as e
                this.Problem("Right pane: " e.Message " (" e.File ":" e.Line ")")
            try this.WinStrip()
            catch as e
                this.Problem("Window tabs: " e.Message " (" e.File ":" e.Line ")")
        } else {
            this.Issues := AxLint.Run(this.P)          ; Right() does this in Design
            this._fields := []
            try AxPanes.WsPage(this)
            catch as e
                this.Problem(this.Ws ": " e.Message " (" e.File ":" e.Line ")")
        }
        nodes := this.SelNodes()
        if (nodes.Length > 1)
            this.Status("sel", nodes.Length " controls selected")
        else if nodes.Length {
            n := nodes[1]
            this.Status("sel", n.Type (n.Name != "" ? "  " n.Name : "") "  [" n.Id "]")
        } else
            this.Status("sel", "")
        this.RenderPanel()
        try this.TopBar()
        if tellCanvas
            this.Send({cmd: "select", sel: this.SelIds})
    }
    Bar() {
        ; b: a button.  ico: the glyph form, for the ones whose picture is
        ; unmistakable -- undo, redo, run.  A caret means it opens a menu.
        b := (id, label, on := 0, tip := "", cls := "") =>
            '<div class="axd-hbtn' (on ? " on" : "") (cls != "" ? " " cls : "")
            . '" data-bar="' id '"'
            . (tip != "" ? ' data-tip="' AxTags.E(tip) '"' : "") '>' label '</div>'
        ico := (g, text := "") => '<span class="ico">&#x' g ';</span>'
                                . (text != "" ? " " text : "")
        caret := ' <span class="axd-ddarrow">&#xE70D;</span>'
        snapping := this.ShowGrid || this.Snap || this.Guides
        ; Design's own tools, and nothing else. The code button, the window
        ; picker, Try it and Run used to share this row: the code is a
        ; workspace now, the windows are tabs just below, and running belongs
        ; to the whole studio, so it is in the bar across the top.
        h := b("undo", ico("E7A7"), 0, "Undo    Ctrl+Z")
          .  b("redo", ico("E7A6"), 0, "Redo    Ctrl+Y")
          .  '<span class="axd-sep"></span>'
          .  b("wizard", ico("E710", "Add"), 0, "Add anything: a control, a value, a hotkey, "
                                             . "a window, a file...    Ctrl+I")
          .  b("group", ico("E8B0", "Group") caret, 0, "Wrap the selection in a container")
          .  b("align", ico("E8E4", "Align") caret, 0, "Align and distribute the selection")
          .  '<span class="axd-sep"></span>'
          .  b("zoom.out", ico("E71F"), 0, "Zoom out    Ctrl+-  or Ctrl and the wheel")
          .  b("zoom", Round(this.Zoom * 100) "%" caret, this.Zoom != 1, "Zoom: a size, or fit the window    Ctrl+0 is 100%")
          .  b("zoom.in", ico("E8A3"), 0, "Zoom in    Ctrl+=")
          .  '<span class="axd-sep"></span>'
          .  b("tab", ico("E8CB", "Tab order"), this.TabMode,
               "Click the controls in the order Tab should visit them -- Escape when done")
          .  '<span class="axd-sep"></span>'
          .  b("grid", ico("E80A", this.Grid "px") caret, snapping,
               "The design grid, snapping and guides")
          .  '<span class="axd-barright">'
          .    b("fold.L", ico("E8A1"), !this.LeftShown,
                 "Hide or show the Toolbox and the Outline    Ctrl+B")
          .    b("fold.R", ico("E89F"), !this.RightShown,
                 "Hide or show the inspector    Ctrl+Shift+B")
          .  '</span>'
        this.Html("axdBar", h)
        this.TopBar()
    }
    ; Across the top, for the whole studio: which workspace is in front, a
    ; way to find anything, and running it -- the same three things wherever
    ; you are.
    TopBar() {
        b := (id, label, on := 0, tip := "", cls := "") =>
            '<div class="axd-hbtn' (on ? " on" : "") (cls != "" ? " " cls : "")
            . '" data-bar="' id '"'
            . (tip != "" ? ' data-tip="' AxTags.E(tip) '"' : "") '>' label '</div>'
        ico := (g, text := "") => '<span class="ico">&#x' g ';</span>'
                                . (text != "" ? " " text : "")
        h := '<div class="axd-wstabs">'
        for t in AxStudio.WsTabs
            h .= '<div class="axd-wstab' (this.Ws = t[1] ? " on" : "") '" data-bar="ws.' t[1] '"'
              .  ' data-tip="' AxTags.E(t[4]) '"><span class="ico">&#x' t[3] ';</span>'
              .  t[2] '</div>'
        h .= '</div>'
        ; the search, running it and the project are in the title bar now
        try this.Html("axdTop", h)
        try AxTitle.Sync(this)
    }
    static WsTabs := [
        ["design", "Design", "E7C4", "The canvas, the Toolbox and the inspector    Ctrl+1"],
        ["logic", "Logic", "E945", "Lists of what the program does: values, rules, hotkeys, timers    Ctrl+2"],
        ["steps", "Steps", "E8FD", "One piece of code as a flowchart you change without typing    Ctrl+3"],
        ["code", "Code", "E943", "The same piece, as the code it is    Ctrl+4"],
        ["map", "Map", "E81E", "The whole program at once: what starts things, what they do, what they touch    Ctrl+5"],
        ["app", "App", "E7B8", "The windows, the program, its files, its libraries and how it is built    Ctrl+6"],
        ["look", "Look", "E790", "Themes: the look of this design, the built-in looks, your own    Ctrl+7"]]
    BarClick(ev) {
        id := this.UpAttr(ev.srcElement, "data-bar")
        if (id != "")
            this.Try(id, (*) => this.BarDo(id))
    }
    BarDo(id) {
        if (SubStr(id, 1, 3) = "ws.") {
            ; picking Steps or Code by hand is also how pieces open from now on
            if (id = "ws.steps" || id = "ws.code")
                this.PieceView := SubStr(id, 4), this.SaveSettings()
            return this.SetWs(SubStr(id, 4))
        }
        if (id = "search")
            return this.Js("AXD.palOpen('cmd');")
        if (id = "back" || id = "forward")
            return this.NavStep(id = "back" ? -1 : 1)
        if (id = "fold.L" || id = "fold.R")
            return this.TogglePane(SubStr(id, 6))
        switch id {
        case "undo":     this.DoUndo()
        case "redo":     this.DoRedo()
        case "grid":     this.GridMenu()
        case "group":    this.GroupMenu()
        case "align":    this.AlignMenu()
        case "tab":      this.ToggleTabOrder()
        case "zoom.in":  this.ZoomStep(1)
        case "zoom.out": this.ZoomStep(-1)
        case "zoom":     this.ZoomMenu()
        case "wizard":   this.WizardMenu()
        case "code":     this.ShowMenu(this.CodeMenu())
        case "wins":     this.ShowMenu(this.WindowMenu())
        case "test":     this.ToggleTest()
        case "preview":  this.Preview()
        case "live":     this.Live := !this.Live, this.Bar(),
                         (this.Live ? this.Preview() : this.StopPreview())
        }
    }
    ; The code button opens what there is to edit, rather than only toggling
    ; the pane -- which left "Init" and "Whole script" reachable from a header
    ; button inside a pane you had to open first.
    CodeMenu() {
        return [{Label: "Show the editor", Icon: "E943", Radio: true,
                 Checked: this.CodeShown, Click: (*) => this.SetMid("code")},
                {Label: "Back to the canvas", Radio: true,
                 Checked: this.Ws = "design", Click: (*) => this.SetMid("canvas")},
                "-",
                {Label: "Startup code", Click: (*) => this.EditScript("init")},
                {Label: "Your own functions", Click: (*) => this.EditScript("script")},
                {Label: "The whole generated script", Click: (*) => this.ShowGenerated()},
                "-",
                {Label: "Add a script helper...", Icon: "E943", Click: (*) => AxHelp.Pick(this)},
                {Label: "Insert a snippet...", Click: (*) => this.SnippetMenu()}]
    }
    ; Every menu this studio opens, wrapped on the way past. A menu item's
    ; Click is called from the COM event sink, so one that raises there is
    ; nothing at all -- and "Compile..." is a menu item.
    ShowMenu(items, x := "", y := "", target := "") {
        return super.ShowMenu(this.WrapItems(items), x, y, target)
    }
    ContextMenu(id, items) {
        return super.ContextMenu(id, this.WrapItems(items))
    }
    WrapItems(items) {
        if !(items is Array)
            return items                      ; a real Menu, not ours to touch
        out := []
        for it in items {
            if !IsObject(it) {                ; "-", a separator
                out.Push(it)
                continue
            }
            if (it is Array) {                ; ["Label", fn]
                out.Push((it.Length >= 2 && it[2])
                    ? [it[1], this.Wrapped(it[1], it[2])] : it)
                continue
            }
            c := {}
            for k, v in it.OwnProps()
                c.%k% := v
            if (c.HasOwnProp("Items") && IsObject(c.Items))
                c.Items := this.WrapItems(c.Items)
            if (c.HasOwnProp("Click") && c.Click)
                c.Click := this.Wrapped(c.HasOwnProp("Label") ? c.Label : "menu item",
                                        c.Click)
            out.Push(c)
        }
        return out
    }
    Wrapped(label, fn) {
        name := StrReplace(RTrim(String(label), "."), "&")
        return (a*) => this.Try(name, (*) => fn(a*))
    }
    PushOpts() => this.Send({cmd: "opts", grid: this.Grid, snap: this.Snap, guides: this.Guides,
                             zoom: this.Zoom, anchor: this.AlAnchor})
    GroupMenu() {
        this.ShowMenu(this.GroupItems())
    }
    GroupItems() {
        items := []
        for t in ["Card", "GroupBox", "Row", "Expander", "Tab", "Grid"]
            items.Push({Label: "Into a " AxCat.Get(t).Label, Icon: AxCat.Get(t).Icon,
                        Click: this.GroupFn(t)})
        items.Push("-")
        items.Push({Label: "Ungroup the selected container", Click: (*) => this.Ungroup()})
        return items
    }
    GroupFn(t) => (*) => this.GroupInto(t)
    AlignMenu() {
        this.ShowMenu(this.AlignItems())
    }
    AlignItems() {
        A := (k, l) => {Label: l, Click: this.AlignFn(k)}
        R := (v, l) => {Label: l, Radio: true, Checked: this.AlAnchor = v, Click: this.AnchorFn(v)}
        return [R("each", "Line up with &each other"), R("last", "Align with the &last selected"),
                R("page", "Line up with the &page"), "-",
                A("left", "Left edges"), A("hcenter", "Centres, across"),
                A("right", "Right edges"), "-",
                A("top", "Top edges"), A("vcenter", "Middles"), A("bottom", "Bottom edges"), "-",
                A("samew", "Same width as the last selected"), A("sameh", "Same height as the last selected"), "-",
                A("distx", "Even out the space across"), A("disty", "Even out the space down"),
                A("gapx", "The same gap across (the Line them up box, or 8)"),
                A("gapy", "The same gap down (the Line them up box, or 8)")]
    }
    ; the plan is AXD's, so the menu and the inspector do exactly the same
    AlignFn(k) => (*) => this.Js("AXD.alDo('" k "');")
    AnchorFn(v) => (*) => this.SetAnchor(v)
    ; The toolbar's Add button opens the Insert menu rather than a list of its
    ; own. There was one of each, and they disagreed.
    WizardMenu() => AxGallery.Open(this)
    GridMenu() {
        items := [{Label: "Show the design grid", Checked: this.ShowGrid ? true : false,
                   Click: (*) => (this.ShowGrid := !this.ShowGrid, this.SaveSettings(),
                                  this.Refresh())},
                  {Label: "Snap to it, and to other controls", Checked: this.Snap ? true : false,
                   Click: (*) => (this.Snap := !this.Snap, this.SaveSettings(), this.Bar(),
                                  this.PushOpts())},
                  {Label: "Alignment guides", Checked: this.Guides ? true : false,
                   Click: (*) => (this.Guides := !this.Guides, this.SaveSettings(), this.Bar(),
                                  this.PushOpts())},
                  "-"]
        for n in [2, 4, 8, 12, 16, 24, 32]
            items.Push({Label: String(n) " px", Radio: true, Checked: this.Grid = n,
                        Click: this.SetGridFn(n)})
        this.ShowMenu(items)
    }
    SetGridFn(n) => (*) => (this.Grid := n, this.SaveSettings(), this.Refresh())
    FilterTools() {
        try this.ToolFilter := this.El("axdToolFilter").value
        try this.Html("axdToolList", AxPanes.ToolItems(this))
    }

    ToggleGroup(key) {
        if this.Shut.Has(key)
            this.Shut.Delete(key)
        else
            this.Shut[key] := 1
        try AxWindow._SetClass(this.El("grp_" key), "shut", this.Shut.Has(key))
        this.SaveSettings()
    }

    ; ------------------------------------------------------------ grouping
    ; Wrapping a selection is the edit a designer reaches for constantly and
    ; the one that is most tedious by hand: the children have to come out in
    ; order, the container has to go where the first of them was, and the
    ; selection has to end up on the container.
    GroupInto(type) {
        nodes := this.SelNodes()
        if !nodes.Length
            return this.Status("msg", "Select the controls to group first.")
        parent := nodes[1].Parent
        at := this.P.IndexOf(nodes[1])
        for n in nodes {
            if (n.Type = "Page" || !AxProject.Same(n.Parent, parent))
                return this.Status("msg", "Group controls that sit side by side, in the same container.")
        }
        this.Mark()
        box := this.P.NewNode(type)
        for n in nodes {
            if (this.P.IndexOf(n) < at)
                at--
            this.P.Remove(n)
        }
        this.P.Insert(parent, box, at)
        for n in nodes {
            n.L["place"] := (n.Lay("place") = "same") ? "same" : "flow"
            this.P.Insert(box, n)
        }
        this.SelIds := [box.Id]
        this.Refresh()
        this.Status("msg", nodes.Length " controls grouped into a " AxCat.Get(type).Label ".")
    }
    Ungroup() {
        n := this.Primary()
        if (!IsObject(n) || !n.Box || n.Type = "Page")
            return this.Status("msg", "Select a container to take apart.")
        parent := n.Parent
        if !IsObject(parent)
            return
        this.Mark()
        at := this.P.IndexOf(n)
        kids := n.Kids.Clone()
        ids := []
        for k in kids {
            this.P.Remove(k)
            this.P.Insert(parent, k, at++)
            ids.Push(k.Id)
        }
        this.P.Remove(n)
        this.SelIds := ids
        this.Refresh()
        this.Status("msg", "Ungrouped.")
    }

    ; A popover starts with markup in it rather than an empty box: the point
    ; of the panel is that it is ordinary page markup, and that is easier to
    ; see than to be told.
    AddPopover(n) {
        if (Trim(n.Lay("pop", "")) = "") {
            this.Mark()
            n.L["pop"] := '<div style="padding:10px 12px">' . Chr(10)
                        . '  <b>' . AxTags.E(n.Label) . '</b><br>' . Chr(10)
                        . '  Anything here is ordinary page markup.' . Chr(10)
                        . "</div>"
            n.L["popw"] := 240
        }
        this.SelIds := [n.Id]
        this.RightTab := "props"
        this.Refresh()
        try this.El("p_pop").focus()
    }

    ; ------------------------------------------------------------- wizards
    ; The three shapes that otherwise mean twenty clicks each.
    ; The three shape wizards. Each is one form now (AxStudio.Wizards.ahk):
    ; the old ones asked for "3 x 2 Button" in a text box and then compared the
    ; label of the button you pressed against the number 1, so none of them
    ; ever ran.
    RowWizard() => AxWiz.Row(this)
    GridWizard() => AxWiz.Grid(this)
    SpacingWizard() => AxWiz.Spacing(this)
    InsertParent() {
        t := this.Primary()
        p := IsObject(t) ? (t.Box ? t : t.Parent) : ""
        return IsObject(p) ? p : (this.CurPage() ? this.CurPage() : this.P.Root)
    }
    static MatchType(word) {
        for t in AxCat.Order
            if (StrLower(t) = StrLower(word) || StrLower(AxCat.Get(t).Label) = StrLower(word))
                return t
        for t in AxCat.Order
            if InStr(StrLower(AxCat.Get(t).Label), StrLower(word))
                return t
        return ""
    }

    ; ------------------------------------------------- quick actions
    ; The thing this control most often needs next, on a button beside it.
    QuickAction(what) {
        n := this.Primary()
        ; The per-control ones live in AxStudio.Acts.ahk, which answers true
        ; when it dealt with it. The rest are the studio's own.
        if AxActs.Run(this, what)
            return
        ; the Logic pane's per-group "Edit as text"
        if (SubStr(what, 1, 10) = "logic.raw.")
            return AxLogic.ToggleRaw(this, SubStr(what, 11))
        ; a link to where something else is set: data-do="go.<place>"
        if (SubStr(what, 1, 3) = "go.")
            return this.GoTo(SubStr(what, 4))
        ; the ribbon tree. Every row carries its path on the action --
        ; "rib.up.2-1-3" -- so this cannot be a case in the switch below.
        if (SubStr(what, 1, 4) = "rib.")
            return AxRibUi.Do(this, what)
        switch what {
        case "arrange":
            return AxArrange.Form(this, this.Primary())
        case "arrange.page":
            return AxArrange.Form(this, this.CurPage() ? this.CurPage() : this.P.Root)
        case "steps.show":
            ; the first piece that is rules, else whatever was on show
            for x in AxSteps.Pieces(this.P)
                if (x.Pc.Kind = "rules" || x.Pc.Kind = "event") && x.Win = this.P.Cur {
                    AxSteps.Pc := x.Pc, AxSteps.Sel := ""
                    break
                }
            return AxMap.SetMode(this, "steps")
        case "dup":         return this.DuplicateSel()
        case "del":         return this.DeleteSel()
        case "page.add":    return this.AddNewPage()
        case "out.clear":   return this.ClearOut()
        case "lint.recheck": return this.Refresh()
        case "run.stop":    return this.StopPreview()
        case "run.again":   return this.Preview()
        case "run.dismiss": return (this.RunBlock := "", this.RenderPanel(), this.Status("msg", "Cleared. The next run checks again."))
        case "run.recheck": return this.RecheckRun(false)
        case "run.dropempty": return this.DropEmptyHandler()
        case "bind.add":    return this.BindWizard()
        case "bind.see":    return this.GoSec("bindings", "logic")
        case "bind.all":    return AxPanes.BindAll(this)
        case "value.add":   return this.ValueWizard()
        case "help.add":    return AxHelp.Pick(this)
        case "file.add":    return AxWiz.AddFile(this)
        case "include.add": return AxWiz.AddInclude(this)
        case "arg.add":     return AxWiz.AddArg(this)
        case "mode.add":    return AxWiz.AddMode(this)
        case "tray.edit":   return AxWiz.Tray(this)
        case "flow.add":    return this.FlowWizard()
        case "state.add":   return this.StateWizard()
        case "hotkey.add":  return this.HotkeyWizard()
        case "look.seed":   return this.SeedLook()
        case "look.clear":  return this.ClearLook()
        case "kid.row":     return this.RowWizard()
        case "kid.one":     return this.InsertMenu2()
        case "pop.shape":   return this.PopShapeMenu()
        case "win.fit":     return this.FitWindow()
        case "icon.file":   return this.IconFromFile()
        case "icon.dll":    return this.IconFromDll()
        case "icon.auto":   return (this.IconTarget := "w_icon", this.WriteIcon("auto"))
        case "icon.none":   return this.WriteIcon("")
        case "icon.hide":   return (this.IconTarget := "w_icon", this.WriteIcon("none"))
        case "icon.back":   return (this.RightTab := (this.IconTarget = "w_icon") ? "page" : "props", this.Reflect(false))
        case "app.compile": return AxWiz.Compile(this)
        case "app.build":   return AxWiz.Build(this)
        case "grid.open":   return this.OpenSheet()
        case "tab.mode":    return this.ToggleTabOrder(true)
        case "cond.add":    return AxAutoUi.Cond(this)
        case "hs.add":      return AxAutoUi.Hotstring(this)
        case "timer.add":   return AxAutoUi.Timer(this)
        case "set.add":     return AxAuto2Ui.Setting(this)
        case "set.page":    return this.Try("settings rows", (*) => AxAuto2Ui.ToPage(this))
        case "ev.add":      return AxAuto2Ui.Event(this)
        case "watch.add":   return AxAuto2Ui.Watcher(this)
        case "mac.add":     return AxAuto2Ui.AddMacro(this)
        case "mac.record":  return AxRecorder.Start(this)
        case "rg.more":     return this.RadioMore()
        case "rg.leave":    return (this.Mark(), this.Primary().P["group"] := "", this.Refresh())
        case "tab.reset":   return (this.Mark(), this.P.W.TabOrder := "", this.Refresh(), this.SendTab())
        case "app.showexe": return this.Try("show the exe", (*) => Run('explorer.exe /select,"' this.LastBuild.Exe '"'))
        case "app.runexe":  return this.Try("run the exe", (*) => Run('"' this.LastBuild.Exe '"'))
        case "app.buildlog": return this.SetMid("out")
        case "app.export":  return this.Export(true)
        case "app.tray":    return AxWiz.Tray(this)
        case "pack.back":   return (this.RightTab := "props", this.Reflect(false))
        case "menu.add":    return this.AppendLine("Menus", "&Menu")
        case "menu.item":   return this.AppendLine("Menus", "    &Item | | g.Toast(" Chr(34) "Item" Chr(34) ")")
        case "status.add":  return this.AppendLine("Status", "part | Text | w=120")
        case "title.item":  return this.AppendLine("TitleItems", "item | glyph | E710 | tip=" Chr(34) "New" Chr(34))
        case "title.burger": return this.AppendLine("TitleItems", "menu | burger | | tip=" Chr(34) "Menu" Chr(34) " class=morph toggle")
        }
        if !IsObject(n)
            return
        switch what {
        case "tab.add":
            this.Mark()
            n.Arg := RTrim(n.Arg, " `t`r`n") "`nTab " (AxGen.TabCount(n) + 1)
            this.Refresh()
        case "tab.del":
            cnt := AxGen.TabCount(n)
            if (cnt < 2)
                return this.Status("msg", "A tab strip needs at least one tab.")
            this.Mark()
            lines := []
            for line in StrSplit(StrReplace(n.Arg, "`r", ""), "`n")
                if (Trim(line) != "")
                    lines.Push(line)
            lines.Pop()
            n.Arg := AxStudio.Join(lines, "`n")
            ; whatever lived on the tab that went moves back one panel
            for k in n.Kids
                if (AxGen.TabOf(k) >= cnt)
                    k.L["tab"] := cnt - 1
            this.Refresh()
        case "tile.add":
            this.Mark()
            t := this.P.NewNode("Tile")
            this.P.Insert(n, t)
            this.SelIds := [t.Id]
            this.Refresh()
        case "opt.add":
            this.Mark()
            n.Arg := RTrim(n.Arg, " `t`r`n") "`nnew:New option"
            this.Refresh()
        case "page.dup":
            this.Mark()
            c := this.P.Duplicate(n)
            c.P["title"] := n.Prop("title") " copy"
            this.PageId := c.Id
            this.SelIds := [c.Id]
            this.Refresh()
        }
    }
    static Join(arr, sep) {
        s := ""
        for x in arr
            s .= (s = "" ? "" : sep) x
        return s
    }
    AppendLine(field, line) {
        this.Mark()
        cur := RTrim(this.P.%field%, " `t`r`n")
        this.P.%field% := (cur = "") ? line : cur "`n" line
        this.Refresh()
    }
    ; A row in Logic or App stands for one line of a project field. This
    ; replaces it (old and new), takes it out (new blank) or adds one (old
    ; blank). The row carries the line's own text, so it is found by what it
    ; says rather than by a position the last edit may have moved.
    PutLine(field, old, new, mark := true) {
        if mark
            this.Mark()
        out := [], found := false
        for raw in StrSplit(StrReplace(String(this.P.%field%), "`r", ""), "`n") {
            if (old != "" && !found && Trim(raw) = Trim(old)) {
                found := true
                if (new != "")
                    out.Push(new)
                continue
            }
            out.Push(raw)
        }
        if (old = "" && new != "")
            out.Push(new)
        text := ""
        for x in out
            text .= (A_Index = 1 ? "" : "`n") x
        this.P.%field% := Trim(text, "`r`n")
        return found || old = ""
    }
    ; Edit and Remove on a row. The row says what it is and carries its line:
    ; "edit|rules|saveBtn Click -> toast Saved". Values, bindings, rules and
    ; hotkeys open their form with the row filled in; the rest open the text
    ; they are written in, at that line.
    static RowFields := Map("values", "Vars", "bindings", "Binds", "rules", "Flows",
        "conditions", "Conds", "hotstrings", "Strings", "timers", "Timers",
        "states", "States", "hotkeys", "Hotkeys", "files", "Files", "includes", "Includes",
        "arguments", "Args", "modes", "Modes", "settings", "Settings", "events", "Events",
        "watchers", "Watchers")
    RowAction(v) {
        p1 := InStr(v, "|")
        p2 := p1 ? InStr(v, "|", , p1 + 1) : 0
        if !p2
            return
        act := SubStr(v, 1, p1 - 1), kind := SubStr(v, p1 + 1, p2 - p1 - 1)
        line := SubStr(v, p2 + 1)
        if !AxStudio.RowFields.Has(kind)
            return
        if (act = "del") {
            if (kind = "states")
                this.DropState(line)                 ; a state is every line with its name
            else
                this.PutLine(AxStudio.RowFields[kind], line, "")
            this.Refresh()
            return this.Status("msg", "Removed. Ctrl+Z brings it back.")
        }
        switch kind {
        case "values":
            for x in AxBind.Vars(this.P)
                if (x.Line = line)
                    return AxWiz.Value(this, x)
        case "bindings":
            for x in AxBind.Binds(this.P.W)
                if (x.Line = line)
                    return AxWiz.Bind(this, x)
        case "rules":
            for x in AxFlow.Parse(this.P.W)
                if (x.Line = line)
                    return AxWiz.Flow(this, x)
        case "hotkeys":
            for x in AxAsset.Hotkeys(this.P.W)
                if (x["line"] = line)
                    return AxWiz.Hotkey(this, x)
        case "conditions":
            for x in AxAuto.Conds(this.P)
                if (x.Line = line)
                    return AxAutoUi.Cond(this, x)
        case "hotstrings":
            for x in AxAuto.Strings(this.P)
                if (x.Line = line)
                    return AxAutoUi.Hotstring(this, x)
        case "timers":
            for x in AxAuto.Timers(this.P)
                if (x.Line = line)
                    return AxAutoUi.Timer(this, x)
        case "settings":
            for x in AxAuto2.Settings(this.P)
                if (x.Line = line)
                    return AxAuto2Ui.Setting(this, x)
        case "events":
            for x in AxAuto2.Events(this.P)
                if (x.Line = line)
                    return AxAuto2Ui.Event(this, x)
        case "watchers":
            for x in AxAuto2.Watchers(this.P)
                if (x.Line = line)
                    return AxAuto2Ui.Watcher(this, x)
        case "files":
            for x in AxAsset.Files(this.P)
                if (x.Line = line)
                    return AxWiz.AddFile(this, x)
        case "includes":
            for x in AxAsset.Includes(this.P)
                if (x.Line = line)
                    return AxWiz.AddInclude(this, x)
        case "arguments":
            for x in AxAsset.Args(this.P)
                if (x.Line = line)
                    return AxWiz.AddArg(this, x)
        case "modes":
            ; the form holds one step; a mode with several stays in its text
            for x in AxAsset.Modes(this.P)
                if (x.Line = line && x.Steps.Length = 1)
                    return AxWiz.AddMode(this, x)
        }
        AxLogic.Raw[kind] := 1
        this.Reflect(false)
        this.Status("msg", "This one is changed in its text, which is open now.")
    }
    DropState(name) {
        this.Mark()
        out := []
        for raw in StrSplit(StrReplace(String(this.P.States), "`r", ""), "`n") {
            p := InStr(raw, ":")
            if (p && Trim(SubStr(raw, 1, p - 1)) = name)
                continue
            out.Push(raw)
        }
        text := ""
        for x in out
            text .= (A_Index = 1 ? "" : "`n") x
        this.P.States := Trim(text, "`r`n")
    }
    ; Append a line to one of the PROJECT's own fields -- files, includes,
    ; arguments, modes. AppendLine writes to the window being edited, which is
    ; the wrong place for anything that belongs to the whole script.
    AppendProject(field, line) {
        if (Trim(line) = "")
            return
        cur := RTrim(String(this.P.%field%), " `t`r`n")
        this.P.%field% := (Trim(cur) = "") ? line : cur "`n" line
        this.GoWs("app")                  ; files, includes, arguments and modes live there
        this.Refresh()
    }
    InsertMenu2() {
        this.ShowMenu(this.ControlsMenu())
    }

    ; ------------------------------------------------------------- snippets
    ; The AutoHotkey a GUI script keeps needing and nobody enjoys typing.
    ; Each one is inserted where the caret is, so they compose.
    static Snips := ""
    static SnipList() {
        if IsObject(AxStudio.Snips)
            return AxStudio.Snips
        q := Chr(34), nl := "`n"
        AxStudio.Snips := [
        {N: "Hotkey, only while this window is active", C:
            "HotIfWinActive(" q "ahk_id " q " g.Hwnd)" nl
          . "Hotkey(" q "^!h" q ", (*) => g.Toast(" q "Pressed" q "))" nl
          . "HotIfWinActive()"},
        {N: "Hotkey, everywhere", C:
            "Hotkey(" q "^!h" q ", (*) => (g.Show(), WinActivate(" q "ahk_id " q " g.Hwnd)))"},
        {N: "Hotkey, while a named window is up", C:
            "HotIfWinActive(" q "ahk_class Notepad" q ")" nl
          . "Hotkey(" q "F1" q ", (*) => g.Toast(" q "Notepad is in front" q "))" nl
          . "HotIfWinActive()"},
        {N: "Repeating timer", C:
            "SetTimer(Tick, 1000)" nl nl
          . "Tick() {" nl "    global g" nl "    g.Status(" q "msg" q ", FormatTime(, " q "HH:mm:ss" q "))" nl "}"},
        {N: "Run once, after a moment", C: "SetTimer(() => g.Toast(" q "Ready" q "), -400)"},
        {N: "Read and write an ini beside the script", C:
            "SettingsFile := A_ScriptDir " q "\settings.ini" q nl
          . "LoadSettings() {" nl "    global g, SettingsFile" nl
          . "    g.Value(" q "name" q ", IniRead(SettingsFile, " q "main" q ", " q "name" q ", " q q "))" nl "}" nl
          . "SaveSettings() {" nl "    global g, SettingsFile" nl
          . "    IniWrite(g.Value(" q "name" q "), SettingsFile, " q "main" q ", " q "name" q ")" nl "}"},
        {N: "Save on close", C:
            "g.OnClose((*) => SaveSettings())"},
        {N: "Remember where the window was", C:
            "g.OnClose((*) => (WinGetPos(&x, &y, , , " q "ahk_id " q " g.Hwnd)," nl
          . "                 IniWrite(x " q "," q " y, SettingsFile, " q "main" q ", " q "pos" q ")))"},
        {N: "A tray menu", C:
            "A_TrayMenu.Delete()" nl
          . "A_TrayMenu.Add(" q "Show" q ", (*) => g.Show())" nl
          . "A_TrayMenu.Add(" q "Exit" q ", (*) => ExitApp())" nl
          . "A_TrayMenu.Default := " q "Show" q},
        {N: "Run a program and wait for it", C:
            "code := RunWait(A_ComSpec " q " /c dir" q ", , " q "Hide" q ")" nl
          . "g.Toast(" q "exit " q " code)"},
        {N: "Read a file into a control", C:
            "f := FileSelect(3, , " q "Open" q ", " q "Text (*.txt)" q ")" nl
          . "if (f != " q q ")" nl "    g.Value(" q "editor" q ", FileRead(f, " q "UTF-8" q "))"},
        {N: "Write a control to a file", C:
            "f := FileSelect(" q "S18" q ", , " q "Save" q ", " q "Text (*.txt)" q ")" nl
          . "if (f != " q q ") {" nl "    if FileExist(f)" nl "        FileDelete(f)" nl
          . "    FileAppend(g.Value(" q "editor" q "), f, " q "UTF-8" q ")" nl "}"},
        {N: "Loop over the files in a folder", C:
            "loop files, A_MyDocuments " q "\*.txt" q nl
          . "    g.Html(" q "log" q ", g.Html(" q "log" q ") . A_LoopFileName . " q "<br>" q ")"},
        {N: "A confirm before something destructive", C:
            "if !g.Confirm(" q "Delete everything?" q ", " q "Careful" q ")" nl "    return"},
        {N: "Ask for a line of text", C:
            "name := g.Prompt(" q "What shall I call it?" q ", " q "Name" q ", " q "Untitled" q ")" nl
          . "if (name != " q q ")" nl "    g.Toast(name)"},
        {N: "A Windows notification", C:
            "g.Notify(" q "Done" q ", " q "The job finished." q ", " q "info" q ")"},
        {N: "A context menu on a control", C:
            "g.ContextMenu(" q "list" q ", [[" q "Refresh" q ", (*) => Reload()], " q "-" q ","
          . " [" q "Remove" q ", (*) => g.Toast(" q "gone" q ")]])"},
        {N: "Fill an autocomplete from an array", C:
            "items := [" q "one" q ", " q "two" q ", " q "three" q "]" nl
          . "out := " q q nl
          . "for it in items" nl
          . "    out .= (out = " q q " ? " q q " : " q "|" q ") it " q ":" q " it" nl
          . "g.SetOptions(" q "ac1" q ", out)"},
        {N: "Download a file", C:
            "Download(" q "https://example.com/file.zip" q ", A_Temp " q "\file.zip" q ")" nl
          . "g.Toast(" q "Downloaded" q ")"},
        {N: "Fetch a URL as text", C:
            "req := ComObject(" q "WinHttp.WinHttpRequest.5.1" q ")" nl
          . "req.Open(" q "GET" q ", " q "https://example.com/" q ", false)" nl
          . "req.Send()" nl
          . "g.Value(" q "editor" q ", req.ResponseText)"},
        {N: "Always on top, on a switch", C:
            "g.AlwaysOnTop(value ? true : false)"},
        {N: "Fade the window", C:
            "WinSetTransparent(200, " q "ahk_id " q " g.Hwnd)"},
        {N: "Watch a folder for changes", C:
            "SetTimer(Watch, 2000)" nl nl
          . "Watch() {" nl "    global g, seen" nl
          . "    n := 0" nl
          . "    loop files A_MyDocuments " q "\*.*" q nl
          . "        n++" nl
          . "    if (n != seen) {" nl "        seen := n" nl
          . '        g.Status("msg", n " files")' nl "    }" nl "}"},
        {N: "Clipboard in and out", C:
            "old := A_Clipboard" nl "A_Clipboard := g.Value(" q "editor" q ")" nl
          . "g.Toast(" q "Copied" q ")"}]
        return AxStudio.Snips
    }
    SnippetMenu() {
        items := []
        ; Yours first, and in their groups. They are the ones you wrote, so
        ; they are the ones you are looking for.
        for grp in AxSnips.Grouped() {
            if (grp.G = "") {
                for sn in grp.Items
                    items.Push({Label: sn.N, Click: this.MySnipFn(sn.N)})
                continue
            }
            sub := []
            for sn in grp.Items
                sub.Push({Label: sn.N, Click: this.MySnipFn(sn.N)})
            items.Push({Label: grp.G, Items: sub})
        }
        if items.Length
            items.Push("-")
        for i, sn in AxStudio.SnipList()
            items.Push({Label: sn.N, Click: this.SnipFn(i)})
        ; the snippets of the libraries this project has, under each library
        have := AxPkg.Have(this.P)
        for name, v in have {
            e := AxPkg.Find(name)
            if !IsObject(e) || !e.Snippets.Length
                continue
            sub := []
            for j, sn in e.Snippets
                sub.Push({Label: sn.Name, Click: AxGallery.PkgSnipFn(this, name, j)})
            items.Push("-"), items.Push({Label: e.Short, Items: sub})
        }
        items.Push("-")
        items.Push({Label: "Keep what is being edited as a snippet...", Click: (*) => AxSnips.FromEditor(this)})
        items.Push({Label: "Your snippets...", Click: (*) => AxSnips.Manage(this)})
        items.Push({Label: "Find ready code and libraries...    Ctrl+I", Click: (*) => AxGallery.Open(this)})
        this.ShowMenu(items)
    }
    SnipFn(i) => (*) => this.InsertSnippet(i)
    MySnipFn(name) => (*) => this.InsertHere(AxSnips.CodeOf(name), name)
    InsertSnippet(i) {
        list := AxStudio.SnipList()
        if (i < 1 || i > list.Length)
            return
        this.InsertHere(list[i].C, list[i].N)
    }
    ; Any code, into whatever is being edited -- the studio's snippets,
    ; yours, and anything else that wants to hand the editor some lines.
    ; There was one of these per caller before, each with its own idea of
    ; what to do when nothing was open.
    InsertHere(add, say := "") {
        if (Trim(String(add)) = "")
            return
        if (!IsObject(this.CodeTarget) || this.CodeTarget.Kind = "readonly")
            this.EditScript("script")
        cur := this.EditorText()
        next := (Trim(cur) = "") ? add : RTrim(cur, "`r`n") "`n`n" add
        this.SetEditor(next, false)
        this.CodeTyped(true)
        this.Status("msg", say != "" ? "Inserted: " say : "Inserted.")
    }
    ; A hotkey is the one thing people reach for that has nothing to do with
    ; the page, so it gets a wizard of its own rather than a snippet.
    HotkeyWizard() => (this.LogicSec := "hotkeys", AxWiz.Hotkey(this))

    ; --------------------------------------------------------------- tabs
    UpAttr(el, attr) {
        n := 0
        while (IsObject(el) && n++ < 24) {
            try {
                v := el.getAttribute(attr)
                if (!IsObject(v) && v != "" && v != "null")
                    return v
            }
            try el := el.parentNode
            catch
                return ""
        }
        return ""
    }
    UpId(el, prefix) {
        n := 0
        while (IsObject(el) && n++ < 24) {
            try id := el.id
            catch
                id := ""
            if (id != "" && SubStr(id, 1, StrLen(prefix)) = prefix)
                return id
            try el := el.parentNode
            catch
                return ""
        }
        return ""
    }

    ; ------------------------------------------------------ workspaces
    ; Four workspaces, one in front, each with the whole middle: Design (the
    ; canvas, with the Toolbox and the inspector either side), Logic, Code and
    ; App. They are split by what you are doing rather than by where there was
    ; room -- the program's values and rules used to be the fourth tab of a
    ; 312-pixel column beside the canvas, and its windows were in five places.
    ; Steps and Code are two views of ONE piece of code -- the flowchart and
    ; the text -- so going from one to the other keeps the piece, and the one
    ; last used is how the next piece opens (PieceView).
    static Workspaces := ["design", "logic", "steps", "code", "map", "app", "look"]
    static IsWs(ws) {
        for w in AxStudio.Workspaces
            if (w = ws)
                return true
        return false
    }
    SetWs(ws) {
        if !AxStudio.IsWs(ws)
            return
        was := this.Ws
        if (!this._flip && ((was = "code" && ws = "steps") || (was = "steps" && ws = "code")))
            return this.FlipTo(ws)
        this.NavNote()
        this.GoWs(ws)
        if (ws = "code" && !IsObject(this.CodeTarget))
            return this.EditScript("init")
        ; the canvas measures itself, and a hidden one measures as nothing, so
        ; coming back to it is a redraw rather than an unhide
        if (ws = "design" && was != "design")
            this.RefreshCanvas()
        this.Bar()
        this.Reflect(false)
        try (ws = "code") ? this.Ce.Focus() : (ws = "steps") ? this.El("axsWrap").focus() : this.El("axdTop").focus()
        this.NavNote()
    }
    ; From the flowchart to the code of the same piece, or back.
    FlipTo(ws) {
        this._flip := true
        try {
            this.PieceView := ws
            if (ws = "steps") {
                pc := this.PcFromCode()
                if IsObject(pc)
                    AxSteps.Pc := pc, AxSteps.Sel := ""
                this.SetWs("steps")
            } else
                AxStepsUi.ShowCode(this)
        } finally
            this._flip := false
        this.NavNote()
    }
    ; A piece just put in the editor, shown the way pieces open: in the view
    ; that is in front when it is Steps or Code, else the one last used.
    ; view "code" or "steps" says which.
    ShowPiece(view := "") {
        if (view = "")
            view := (this.Ws = "code" || this.Ws = "steps") ? this.Ws : this.PieceView
        this._flip := true
        try {
            if (view = "steps") {
                pc := this.PcFromCode()
                if IsObject(pc)
                    AxSteps.Pc := pc, AxSteps.Sel := ""
                if (this.Ws = "steps")
                    AxStepsUi.Paint(this)
                else
                    this.SetWs("steps")
            } else
                this.SetMid("code")
        } finally
            this._flip := false
        this.NavNote()
    }

    ; ------------------------------------------------------ back and forward
    ; Every place you have been -- a workspace, and in Steps and Code the
    ; piece, in Logic and App the section -- so Alt+Left goes back the way
    ; you came, wherever a link took you.
    NavPlace() {
        pl := {Ws: this.Ws, Pc: "", Sec: ""}
        if (this.Ws = "steps" || this.Ws = "code") {
            pc := (this.Ws = "steps") ? AxSteps.Pc : this.PcFromCode(false)
            pl.Pc := IsObject(pc) ? AxSteps.Key(pc) : ""
            if (this.Ws = "code" && IsObject(this.CodeTarget) && this.CodeTarget.Kind = "readonly")
                pl.Pc := "gen"
        } else if (this.Ws = "logic")
            pl.Sec := this.LogicSec
        else if (this.Ws = "app")
            pl.Sec := this.AppSec
        return pl
    }
    static NavSame(a, b) => IsObject(a) && IsObject(b) && a.Ws = b.Ws && a.Pc = b.Pc && a.Sec = b.Sec
    NavNote() {
        if (this._navGoing || !this.HasOwnProp("NavList"))
            return
        pl := ""
        try pl := this.NavPlace()
        if !IsObject(pl)
            return
        if (this.NavAt >= 1 && AxStudio.NavSame(this.NavList[this.NavAt], pl))
            return
        ; a new place drops whatever was ahead of this one
        while (this.NavList.Length > this.NavAt)
            this.NavList.Pop()
        this.NavList.Push(pl)
        if (this.NavList.Length > 60)
            this.NavList.RemoveAt(1)
        this.NavAt := this.NavList.Length
        try this.NavButtons()
    }
    NavStep(d) {
        this.NavNote()
        j := this.NavAt + d
        if (j < 1 || j > this.NavList.Length)
            return this.Status("msg", d < 0 ? "Nowhere further back." : "Nowhere further on.")
        this.NavAt := j
        pl := this.NavList[j]
        this._navGoing := true
        try {
            if (pl.Ws = "steps" || pl.Ws = "code") && (pl.Pc != "") {
                if (pl.Pc = "gen" && pl.Ws = "code")
                    this.ShowGenerated()
                else {
                    pc := AxSteps.FromKey(pl.Pc)
                    if IsObject(pc) {
                        AxSteps.Pc := pc, AxSteps.Sel := ""
                        this._flip := true
                        try (pl.Ws = "steps") ? (this.Ws = "steps" ? AxStepsUi.Paint(this) : this.SetWs("steps")) : AxStepsUi.ShowCode(this)
                        finally this._flip := false
                    } else
                        this.SetWs(pl.Ws)
                }
            } else if (pl.Sec != "")
                this.GoSec(pl.Sec, pl.Ws)
            else
                this.SetWs(pl.Ws)
        } finally
            this._navGoing := false
        this.NavButtons()
    }
    NavButtons() => AxTitle.Sync(this)
    ; The workspace in front, without drawing anything: for callers that are
    ; about to Refresh anyway. Going to Design still redraws the canvas.
    GoWs(ws) {
        if (this.Ws = ws || !AxStudio.IsWs(ws))
            return
        if (this.TabMode && ws != "design")
            this.TabMode := false, this.SendTab()
        this.Ws := ws
        this.ShowWs()
        this.SendShell()
        this.SaveSettings()
    }
    ShowWs() {
        static ids := Map("design", "axdWsDesign", "logic", "axdWsLogic", "steps", "axdWsSteps",
                          "code", "axdCode", "app", "axdWsApp", "look", "axdWsLook", "map", "axdWsMap")
        for ws, id in ids
            try this.El(id).style.display := (this.Ws = ws) ? "block" : "none"
        try this.El("axdIssues").style.display := (this.PanelOpen && this.PanelTab = "lint") ? "block" : "none"
        try this.El("axdOut").style.display := (this.PanelOpen && this.PanelTab = "out") ? "block" : "none"
    }
    ; Kept, because half the studio asks for a view by the name it had when
    ; the middle was four tabs: the canvas and the code are workspaces now,
    ; and Problems and Output are the panel along the bottom.
    SetMid(tab) {
        switch tab {
        case "canvas":      return this.SetWs("design")
        case "code":        return this.SetWs("code")
        case "lint", "out": return this.ShowPanel(tab)
        }
    }
    ; Everything the layout depends on, to the one function in the page that
    ; places the regions -- AXD.shell.
    SendShell() {
        try this.FitShell()
        this.Send({cmd: "shell", ws: this.Ws,
                   left: this.LeftShown ? this.LeftW : 0,
                   right: this.RightShown ? this.RightW : 0,
                   panel: this.PanelOpen ? this.PanelH : AxStudio.PanelShut,
                   ah: (this.AutoHideBar && !this.PanelOpen) ? 1 : 0})
    }
    SetAutoHide(on) {
        this.AutoHideBar := on ? 1 : 0
        this.SaveSettings()
        this.SendShell()
        this.Status("msg", on ? "The bottom bar hides until the pointer is at the bottom edge."
                              : "The bottom bar stays.")
    }
    static PanelShut := 31                 ; folded: just its row of tabs

    ; -------------------------------------------------- the bottom panel
    ; Problems and Output are about the run and the whole program, not one
    ; workspace, so they sit under all of them. An error opens it by itself.
    ShowPanel(tab, open := true) {
        this.PanelTab := (tab = "out") ? "out" : "lint"
        this.PanelOpen := open ? 1 : 0
        this.SaveSettings()
        this.ShowWs()
        this.SendShell()
        this.RenderPanel()
    }
    TogglePanel() => this.ShowPanel(this.PanelTab, !this.PanelOpen)
    PanelClick(ev) {
        v := this.UpAttr(ev.srcElement, "data-ptab")
        if (v = "")
            return
        if (v = "fold")
            return this.TogglePanel()
        ; the tab that is showing folds the panel; the other one shows itself
        if (this.PanelOpen && v = this.PanelTab)
            return this.ShowPanel(v, false)
        this.ShowPanel(v)
    }
    RenderPanel() {
        bad := AxLint.Count(this.Issues, "error") + (IsObject(this.RunBlock) ? 1 : 0)
        n := bad + AxLint.Count(this.Issues, "warn")
        tabs := [["lint", "Problems" (n ? " (" n ")" : ""), "E7BA"],
                 ["out", "Output" (this.Out.Length ? " (" this.Out.Length ")" : ""), "E756"]]
        h := ""
        for t in tabs
            h .= '<div class="' ((this.PanelOpen && this.PanelTab = t[1]) ? "on" : "")
              .  ((t[1] = "lint" && bad) ? " axd-tab-bad" : "") '" data-ptab="' t[1] '">'
              .  '<span class="ico">&#x' t[3] ';</span> ' t[2] '</div>'
        h .= '<span class="axd-midright"><span class="axd-hbtn" data-ptab="fold"'
          .  ' data-tip="Show or hide this panel    Ctrl+J">&#x'
          .  (this.PanelOpen ? "E70D" : "E70E") ';</span></span>'
        try this.Html("axdPanelTabs", h)
        try AxTitle.Sync(this)
        ; Only the list on screen is built. The counts come from the lists
        ; themselves, so a folded Output of four hundred lines costs nothing.
        if !this.PanelOpen
            return
        if (this.PanelTab = "lint") {
            try this.Html("axdIssues", '<div class="axd-midbody">' AxPanes.LintHtml(this) '</div>')
            catch as e
                this.WriteLog("Problems: " e.Message)
        } else {
            try this.Html("axdOut", '<div class="axd-midbody">' AxPanes.OutHtml(this) '</div>')
            catch as e
                this.WriteLog("Output: " e.Message)
        }
    }
    ; Either side pane can be put away. With both gone the canvas -- or the
    ; code -- has the whole window, which is the point of the middle holding
    ; everything.
    TogglePane(side) {
        if (side = "L")
            this.LeftShown := !this.LeftShown
        else
            this.RightShown := !this.RightShown
        this.SaveSettings()
        this.SendShell()
        this.Bar()
    }
    ; Kept because half the studio says "show me the code": it is a tab now.
    ShowCode(h := 1) {
        if (h > 0)
            this.SetMid("code")
        else
            this.SetMid("canvas")
    }
    CodeShown => this.Ws = "code"
    OpenPrimaryEvent() {
        n := this.Primary()
        if !IsObject(n) || !AxCat.Has(n.Type)
            return
        if n.Ev.Length
            return this.EditEvent(n, 1)
        names := AxCat.Get(n.Type).Events
        if names.Length
            this.AddEvent(n, names[1])
    }
    AddEvent(n, name) {
        for i, e in n.Ev
            if (e["name"] = name)
                return this.EditEvent(n, i)
        this.Mark()
        if (Trim(n.Name) = "") {
            e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
            n.Name := this.P.NewName(IsObject(e) ? e.Prefix : "ctl")
        }
        ; a click inside a popover mostly means "done with it": it starts by
        ; putting it away, which is one line to take out when it should stay
        code := ""
        if AxCat.IsPart(name)
            code := (this.P.W.Kind = "main" ? "g" : this.P.W.Var) ".ClosePopover()`n"
        n.Ev.Push(Map("name", name, "code", code))
        this.RightTab := "props"
        this.Reflect(false)
        this.EditEvent(n, n.Ev.Length)
        this.QueueLive()
    }
    RemoveEvent(n, i) {
        if (i < 1 || i > n.Ev.Length)
            return
        this.Mark()
        n.Ev.RemoveAt(i)
        if (IsObject(this.CodeTarget) && this.CodeTarget.Kind = "event")
            this.CodeTarget := ""
        this.Reflect(false)
        this.QueueLive()
    }
    ; view: "code" or "steps"; empty opens it the way pieces open (ShowPiece)
    EditEvent(n, i, view := "") {
        if (i < 1 || i > n.Ev.Length)
            return
        e := n.Ev[i]
        this.CodeTarget := {Kind: "event", Id: n.Id, Index: i}
        this.Text("axdCodeTitle", AxGen.HandlerName(n, e["name"]))
        this.Text("axdCodeSig", "(" AxCat.Sig(e["name"]) ")   " n.Type " " n.Name)
        this.SetEditor(e["code"], false)
        this.ShowPiece(view)
        this.CodeMsg("", "")
        this.PushCompletions()
        try this.Ce.Focus()
        this.RightTab := "props"
        this.Reflect(false)
    }
    EditScript(kind, view := "code") {
        this.CodeTarget := {Kind: kind}
        this.Text("axdCodeTitle", kind = "init" ? "Startup code" : "Your own functions")
        this.Text("axdCodeSig", kind = "init"
            ? "runs after the controls are built, just before g.Show()"
            : "appended to the file: your own functions and classes")
        this.SetEditor(kind = "init" ? this.P.Init : this.P.Script, false)
        this.ShowPiece(view)
        this.CodeMsg("", "")
        this.PushCompletions()
        try this.Ce.Focus()
    }
    ; ------------------------------------------------ the code navigator
    ; Every piece of code in the program, by window: its startup code, your
    ; own functions, every handler on every control, and the whole script as
    ; it will be written. The one being edited is lit.
    CodeNav() {
        t := this.CodeTarget
        tk := IsObject(t) ? t.Kind : ""
        item := (cn, icon, label, note, on) => '<div class="axd-cnitem' (on ? " on" : "") '" data-cn="' cn '">'
            . '<span class="ico">&#x' icon ';</span>' label
            . (note != "" ? '<span class="axd-dim">' note '</span>' : "") '</div>'
        h := ""
        for i, w in this.P.Wins {
            cur := (i = this.P.Cur)
            h .= '<div class="axd-cnwin"><span class="ico">&#x' AxPanes.WinIcon(w.Kind) ';</span>'
              .  AxTags.E(w.Name) '</div>'
              .  item("init." i, "E7C4", "Startup code", AxStudio.LinesNote(w.Init), cur && tk = "init")
              .  item("script." i, "E943", "Your own functions", AxStudio.LinesNote(w.Script), cur && tk = "script")
            ; and what is IN them. A program with six functions in it showed
            ; one row saying "44 lines", so the only way to find anything was
            ; to open it and scroll -- which is what made a template's code
            ; feel like a locked blob rather than something you could read.
            ; The parser already knows them (bin\AstHost.exe); this is the
            ; same list the Steps tab has, in the place people look for code.
            try {
                for d in AxSteps.Defs(w.Script)
                    h .= '<div class="axd-cnsub">'
                      .  item("fn." i "." d.Name, d.Icon, AxTags.E(d.Label),
                              d.Lines " line" (d.Lines = 1 ? "" : "s"), false)
                      .  '</div>'
            }
            nodes := []
            this.P.Walk(w.Root, AxStudio.HasEvFn(nodes))
            for n in nodes {
                e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
                for j, ev in n.Ev
                    h .= item("ev." i "." n.Id "." j, IsObject(e) ? e.Icon : "E7C3",
                              AxTags.E(n.Label), AxTags.E(ev["name"]),
                              cur && tk = "event" && t.Id = n.Id && t.Index = j)
            }
            if !nodes.Length
                h .= '<div class="axd-cnnone">No handlers yet.</div>'
            h .= item("add." i, "E710", "Add a handler...", "", false)
            ; The adaptors, where anyone would look for them.
            ;
            ; They ARE functions of this program -- every rule and flowchart
            ; offers them by name -- and until now they appeared nowhere in
            ; the Code tab at all, which listed "Your own functions: empty"
            ; over a program with four of them. They are not editable here
            ; (they are one line each, written from what App > Libraries
            ; knows), so they are shown for what they are and a click goes to
            ; where they are made.
            if (i = 1) {
                ad := AxNet.List(this.P)
                if ad.Length {
                    h .= '<div class="axd-cnwin"><span class="ico">&#xE8F4;</span>From libraries</div>'
                    for a in ad
                        h .= '<div class="axd-cnitem" data-cn="net.' AxTags.E(a.Name) '" title="'
                           . AxTags.E(a.Name "(" AxNet.Words(a.Params) ")"
                                      (a.Doc != "" ? "`n`n" a.Doc : "")) '">'
                           . '<span class="ico">&#x' (AxNet.IsAsync(a) ? "E916" : "E8F4") ';</span>'
                           . AxTags.E(a.Name) '()'
                           . '<span class="axd-dim">' AxTags.E(a.Doc != "" ? a.Doc : a.Target) '</span></div>'
                }
            }
        }
        h .= AxPkgUi.CodeNavHtml(this)
        h .= '<div class="axd-cnwin"><span class="ico">&#xE8A7;</span>Read only</div>'
          .  item("gen", "E7C3", "The whole script", "as exported", tk = "readonly")
        try this.Html("axdCodeList", h)
        this.ApplyCodeFind()
    }
    CodeFindKey(ev) {
        k := 0
        try k := ev.keyCode
        if (k = 27)
            try this.El("axdCodeFind").value := ""
        v := ""
        try v := this.El("axdCodeFind").value
        this.CodeFind := StrLower(Trim(v))
        this.ApplyCodeFind()
    }
    ; Rows that do not say it are hidden, and so are the "add" rows and the
    ; notes -- while filtering you are looking for code that exists.
    ApplyCodeFind() {
        q := this.CodeFind
        list := ""
        try list := this.El("axdCodeList")
        if !IsObject(list)
            return
        rows := list.querySelectorAll(".axd-cnitem, .axd-cnnone")
        loop rows.length {
            r := rows.item(A_Index - 1)
            t := ""
            try t := StrLower(r.innerText)
            cn := ""
            try cn := r.getAttribute("data-cn")
            keep := (q = "") || (InStr(t, q) && SubStr(cn, 1, 4) != "add.")
            try r.style.display := keep ? "" : "none"
        }
    }
    static HasEvFn(list) => (n) => (n.Ev.Length ? list.Push(n) : 0, false)
    static LinesNote(text) {
        n := AxLogic.CountLines(text)
        return n ? n " line" (n = 1 ? "" : "s") : "empty"
    }
    ; An adaptor in the navigator: it is made on App > Libraries, so that is
    ; where a click on it goes, with that one picked.
    GoToAdaptor(name) {
        AxPkgUi.Tab := "mine"
        this.GoSec("libraries", "app")
        this.Status("msg", name "() is made here: it is one .NET method, written as one of your functions.")
    }
    CodeNavClick(ev) {
        v := this.UpAttr(ev.srcElement, "data-cn")
        if (v = "")
            return
        if (v = "gen")
            return this.ShowGenerated()
        if (SubStr(v, 1, 4) = "pkg.")
            return AxPkgUi.CodeNavClick(this, v)
        if (SubStr(v, 1, 4) = "net.")
            return this.GoToAdaptor(SubStr(v, 5))
        p := StrSplit(v, ".")
        i := Integer(p[2])
        if (i != this.P.Cur)
            this.SwitchWin(i)
        if (p[1] = "add")
            return AxWiz.AddHandler(this)
        if (p[1] = "init" || p[1] = "script")
            return this.EditScript(p[1])
        ; one function of the script, by name: open the script and put the
        ; caret on it
        if (p[1] = "fn") {
            name := SubStr(v, InStr(v, ".", , , 2) + 1)
            this.EditScript("script")
            for d in AxSteps.Defs(this.P.W.Script)
                if (d.Name = name && d.HasOwnProp("Line")) {
                    try this.Ce.GoTo(d.Line, 1)
                    try this.Ce.Focus()
                    return this.Status("msg", d.Label " -- line " d.Line " of your own functions.")
                }
            return
        }
        n := this.P.Find(p[3])
        if IsObject(n)
            this.EditEvent(n, Integer(p[4]))
    }
    ; The piece in the editor as steps (the Steps workspace). Your own
    ; functions are a file of several: the one the caret is in, else the first.
    CodeAsSteps() {
        this.FlipTo("steps")
    }
    ; The piece the editor holds, as Steps names pieces.
    ; flush: take what was typed first -- not when only asking where we are
    PcFromCode(flush := true) {
        if flush
            this.CodeTyped(true)
        t := this.CodeTarget
        pc := ""
        if IsObject(t) {
            switch t.Kind {
            case "event":    pc := {Kind: "event", Win: this.P.Cur, Id: t.Id, Index: t.Index}
            case "init":     pc := {Kind: "init", Win: this.P.Cur}
            case "readonly": pc := {Kind: "gen"}
            case "script":
                defs := AxSteps.Defs(this.P.Script)
                at := 0
                try at := this.Ce.Caret()["b"]         ; a Map: line, col, a, b
                pick := defs.Length ? defs[1].Name : ""
                try {
                    tr := AxHost.TreeText(StrReplace(this.P.Script, "`r"))
                    for d in defs
                        for i in tr.Children(0)
                            if (tr.Start(i) <= at && at <= tr.End(i) && (tr.Value(i) = d.Name || "hk:" tr.Value(i) = d.Name))
                                pick := d.Name
                }
                if (pick != "")
                    pc := {Kind: "fn", Win: this.P.Cur, Fn: pick}
            }
        }
        return pc
    }
    ShowGenerated() {
        this.CodeTarget := {Kind: "readonly"}
        this.Text("axdCodeTitle", "Generated script")
        this.Text("axdCodeSig", "read only  -  File > Export writes exactly this")
        this.SetEditor(AxGen.Script(this.P, this.P.Path != "" ? this.P.Path : this.ScriptPath(),
                            "", this.PreBody()), true)
        this.SetMid("code")
        this.CodeMsg("", "")
    }
    ; A new piece of code in the editor. What was typed into the one before
    ; is kept first: the editor tells of a change when the typing pauses, and
    ; a click on the next handler can come sooner than that.
    SetEditor(text, readonly) {
        if !IsObject(this.Ce)
            return
        this.CodeTyped()
        this._ceTarget := IsObject(this.CodeTarget) ? {T: this.CodeTarget, P: this.P, W: this.P.W} : ""
        this._ceLoaded := text
        try {
            this.Ce.SetOption("readonly", readonly ? 1 : 0)
            this.Ce.Load(text)
        }
    }
    EditorText() {
        try return IsObject(this.Ce) ? this.Ce.Value : ""
        return ""
    }
    ; the editor's text into the piece of the project it came from -- the one
    ; it was loaded for, even when CodeTarget has already moved on. Only what
    ; was typed: code the studio itself changed underneath (a wizard, a merge)
    ; is not put back from an editor that still shows the old version.
    CodeTyped(force := false) {
        ct := this._ceTarget
        if !IsObject(ct) || ct.P != this.P          ; a project since opened in its place
            return
        t := ct.T, w := ct.W
        if !IsObject(t) || t.Kind = "readonly"
            return
        code := this.EditorText()
        if (!force && code == this._ceLoaded)
            return
        this._ceLoaded := code
        if (t.Kind = "event") {
            n := this.P.Find(t.Id)
            if !(IsObject(n) && t.Index <= n.Ev.Length) || n.Ev[t.Index]["code"] == code
                return
            n.Ev[t.Index]["code"] := code
        } else if (t.Kind = "init") {
            if (w.Init == code)
                return
            w.Init := code
        } else {
            if (w.Script == code)
                return
            w.Script := code
        }
        this.P.Dirty := true
        this.QueueLive()
    }
    CodeMsg(text, kind := "") {
        try {
            el := this.El("axdCodeMsg")
            el.innerText := text
            el.className := "axd-" (kind = "" ? "none" : kind)
        }
    }
    ; The user's handler, on its own, through the interpreter's own parser.
    ; Warnings are off because the rest of the script is not here -- the
    ; question is whether the code parses, not whether g is in scope.
    CheckSyntax() {
        t := this.CodeTarget
        if !IsObject(t)
            return
        code := this.EditorText()
        head := "#Requires AutoHotkey v2.0`n#Warn All, Off`n"
        if (t.Kind = "event") {
            n := this.P.Find(t.Id)
            if !IsObject(n)
                return
            e := n.Ev[t.Index]
            body := head AxGen.HandlerName(n, e["name"]) "(" AxCat.Sig(e["name"]) ") {`n"
                  . AxGen.Block(code, "    ") "`n}`n"
        } else if (t.Kind = "readonly")
            body := code
        else
            body := head code "`n"
        r := AxStudio.Validate(body, t.Kind = "readonly" ? this.ScriptPath() : "")
        this.CodeMsg(r.Ok ? "Parses cleanly." : r.Msg, r.Ok ? "ok" : "err")
    }
    ; `near` is the path the script is really meant to live at. A generated file
    ; opens with a relative #Include, and AutoHotkey resolves that against the
    ; directory of the file it is loading -- so checking a copy parked in %TEMP%
    ; would fail on the include every time and report every export as broken.
    ; What the check said, as something to act on: the message without the
    ; temporary file's name, and the function in the script the line is in --
    ; which is the handler the design wrote, when it is one. The check adds
    ; two #Warn lines above the script, so its line numbers are two ahead.
    static BlockOf(msg, code) {
        msg := Trim(RegExReplace(msg, "\s+", " "))
        b := {Msg: msg, What: "", Fn: "", Line: 0, When: FormatTime(, "HH:mm")}
        if RegExMatch(msg, "line \((\d+)\) : ==> (.*)$", &m) {
            b.Line := Integer(m[1]) - 2
            b.Msg := Trim(m[2])
            b.Fn := AxDbg.Locate(code, b.Line)
        }
        ; "Specifically:" is the line itself, which reads better on its own
        if (i := InStr(b.Msg, "Specifically:"))
            b.What := Trim(SubStr(b.Msg, i + 13)), b.Msg := Trim(SubStr(b.Msg, 1, i - 1))
        return b
    }
    static Validate(text, near := "") {
        dir := A_Temp
        if (near != "") {
            SplitPath(near, , &d)
            if (d != "" && DirExist(d))
                dir := d
        }
        tmp := dir "\.axstudio_check_" A_TickCount ".ahk"
        ; Every warning as text, never as a dialog. /ErrorStdOut sends errors to
        ; standard output but not warnings, and AutoHotkey v2 warns about some
        ; things by default in a message box -- which put a dialog in front of
        ; whoever was working when a check ran. A #Warn of the design's own is
        ; turned off in this copy only; the exported script keeps it.
        ; LocalSameAsGlobal stays off, as it is by default: a value called
        ; theme or total meets the library's own locals of that name, which is
        ; harmless and would drown the warnings that matter.
        text := "#Warn All, StdOut`n#Warn LocalSameAsGlobal, Off`n"
              . RegExReplace(text, "im)^[ \t]*#Warn\b[^\r\n]*", "; (#Warn -- read as text by the check)")
        ; Both streams go to a file, and the check is given a time limit: a
        ; pipe read waits for ever, and AutoHotkey itself can hang on a script
        ; it cannot make sense of -- which froze the studio (and the probe)
        ; until something outside stopped it. /ErrorStdOut is a misleading
        ; name, too: an error that stops the script goes to the ERROR stream.
        outFile := tmp ".out", codeFile := tmp ".code"
        try {
            FileAppend(text, tmp, "UTF-8-RAW")
            if InStr(tmp, "!")                  ; delayed expansion below would eat it
                throw Error("a ! in the folder's path")
            Run(A_ComSpec ' /v:on /c ""' A_AhkPath '" /ErrorStdOut=UTF-8 /validate "' tmp '" > "' outFile '" 2>&1 & echo !errorlevel!> "' codeFile '""',
                , "Hide", &pid)
            if ProcessWaitClose(pid, 20) {      ; the PID back means it is still running
                ; stop what this started, and only that: the interpreter under
                ; this one shell, then the shell
                for p in ComObjGet("winmgmts:").ExecQuery("SELECT ProcessId FROM Win32_Process WHERE ParentProcessId=" pid)
                    try ProcessClose(p.ProcessId)
                try ProcessClose(pid)
                for f in [tmp, outFile, codeFile]
                    try FileDelete(f)
                return {Ok: false, Msg: "AutoHotkey was still reading the script after 20 seconds, so the check was stopped.", Warn: ""}
            }
            out := "", code := 2
            try out := FileRead(outFile, "UTF-8")
            try code := Integer(Trim(FileRead(codeFile), " `t`r`n"))
        } catch as err {
            for f in [tmp, outFile, codeFile]
                try FileDelete(f)
            return {Ok: false, Msg: "Could not run the interpreter: " err.Message, Warn: ""}
        }
        for f in [tmp, outFile, codeFile]
            try FileDelete(f)
        out := Trim(StrReplace(StrReplace(out, "`r", ""), tmp, "line"))
        out := RegExReplace(out, "\n+", "  ")
        return {Ok: code = 0, Msg: (out != "" ? out : "Exit code " code),
                Warn: InStr(out, "Warning:") ? out : ""}
    }

    ; ------------------------------------------------------------ keyboard
    Key(el, ev) {
        try {
            tag := ev.srcElement.tagName
        } catch
            return
        ; A modal owns the keyboard while it is up: Escape leaves it and Enter
        ; commits it, and none of the studio's own shortcuts fire behind it.
        if AxForm.Cur {
            try {
                if AxForm.Key(this, ev.keyCode, ev.ctrlKey)
                    ev.returnValue := false
            }
            return
        }
        if this.SheetOpen
            return
        if AxGallery.IsOpen {
            k := 0
            try k := ev.keyCode
            if (k = 27)
                AxGallery.Close(this)
            return
        }
        if (tag = "INPUT" || tag = "TEXTAREA")
            return
        ; The code editor rebuilds itself as you type, so by the time this runs
        ; the element the key was pressed on may already be detached and the
        ; hook that should have caught it missed. Ask the document who has the
        ; caret instead of trusting the event's source.
        ; The code editor keeps its keys, all but F5 (run it) and Ctrl+1-5
        ; (the workspaces), which it has no use for.
        try {
            ae := this.Doc.activeElement
            if (IsObject(ae) && this.UpId(ae, "axdCe") != "") {
                k := ev.keyCode
                if !(k = 116 || (ev.ctrlKey && !ev.shiftKey && !ev.altKey && k >= 49 && k <= 55)
                     || (ev.altKey && !ev.ctrlKey && (k = 37 || k = 39)))
                    return
            }
        }
        try key := ev.keyCode
        catch
            return
        ctrl := ev.ctrlKey, shift := ev.shiftKey
        ; What acts on the selection only acts where you can see it: Delete in
        ; the Logic workspace must not take out a control on a hidden canvas.
        design := (this.Ws = "design")
        handled := true
        if (design && ctrl && (key = 187 || key = 107))
            this.ZoomStep(1)
        else if (design && ctrl && (key = 189 || key = 109))
            this.ZoomStep(-1)
        else if (design && ctrl && (key = 48 || key = 96))
            this.SetZoom(1)
        else if (ctrl && key >= 49 && key <= 55)
            this.SetWs(AxStudio.Workspaces[key - 48])
        else if (ev.altKey && !ctrl && (key = 37 || key = 39))
            this.NavStep(key = 37 ? -1 : 1)
        else if (ctrl && key = 74)
            this.TogglePanel()
        else if (ctrl && key = 73)
            AxGallery.Open(this)
        else if (key = 112)
            this.HelpDialog()
        else if (ctrl && key = 90)
            this.DoUndo()
        else if (ctrl && key = 89)
            this.DoRedo()
        else if (ctrl && key = 83)
            this.Save()
        else if (ctrl && key = 69)
            this.Export()
        else if (design && ctrl && key = 67)
            this.Copy()
        else if (design && ctrl && key = 88)
            this.Cut()
        else if (design && ctrl && key = 86)
            this.Paste()
        else if (design && ctrl && key = 68)
            this.DuplicateSel()
        else if (design && ctrl && key = 65)
            this.SelectAll()
        else if (ctrl && key = 66)
            this.TogglePane(shift ? "R" : "L")
        else if (design && key = 46)
            this.DeleteSel()
        else if (key = 116)
            this.Preview()
        else if (key = 117)
            this.ToggleTest()
        else if (this.TabMode && key = 27)
            this.ToggleTabOrder(false)
        else if (design && key = 27)
            this.EscapeUp()
        else if (design && (key = 93 || (shift && key = 121)))
            this.MenuAtSel()
        else if (design && key = 113)
            this.RenameSel()
        else if (design && key = 13)
            this.OpenPrimaryEvent()
        else if (design && key >= 37 && key <= 40)
            this.Nudge(key, shift ? 1 : this.Grid)
        else if ((this.Ws = "logic" || this.Ws = "app") && !ctrl && (key = 38 || key = 40))
            this.StepSec(key = 40 ? 1 : -1)
        else
            handled := false
        if handled
            ev.returnValue := false
    }
    ; F2 on the canvas. The name is the one property that is worth changing
    ; without moving your hand to the mouse: it is what the generated code
    ; calls the control, and it is wrong far more often than anything else.
    RenameSel() {
        n := this.Primary()
        if !IsObject(n) || n.Type = "Root"
            return
        v := AxWiz.Rename(this, n)
        if (v = "" || v = n.Name)
            return
        this.Mark()
        want := AxProject.CleanName(v)
        if (want = "")
            return
        if this.P.FindByName(want, n)
            want := this.P.NewName(RegExReplace(want, "\d+$"))
        n.Name := want
        this.Refresh()
        this.PushCompletions()
        this.Status("msg", "Renamed to " want ".")
    }
    Nudge(key, step) {
        nodes := this.SelNodes()
        if !nodes.Length
            return
        n := nodes[1]
        if (nodes.Length = 1 && n.Lay("place", "flow") != "abs") {
            ; in the flow, the arrows move a control among its siblings, or
            ; change whether it starts a line
            if (key = 38 || key = 40) {
                i := this.P.IndexOf(n)
                j := i + (key = 40 ? 1 : -1)
                if (j >= 1 && j <= n.Parent.Kids.Length) {
                    this.Mark()
                    parent := n.Parent
                    this.P.Remove(n)
                    this.P.Insert(parent, n, j)
                    this.Refresh()
                }
            } else {
                this.Mark()
                n.L["place"] := (key = 39) ? "same" : "flow"
                this.Refresh()
            }
            return
        }
        this.Mark()
        for m in nodes {
            if (m.Lay("place", "flow") != "abs")
                continue
            x := Integer(m.Lay("x", 0)), y := Integer(m.Lay("y", 0))
            if (key = 37)
                x -= step
            else if (key = 39)
                x += step
            else if (key = 38)
                y -= step
            else
                y += step
            m.L["x"] := Max(0, x), m.L["y"] := Max(0, y)
        }
        this.Refresh()
    }

    ; ----------------------------------------------------------- commands
    DoUndo() {
        p := this.Undo.Undo(this.P)
        if !IsObject(p)
            return this.Status("msg", "Nothing to undo.")
        this.P := p
        this.AfterTreeSwap()
    }
    DoRedo() {
        p := this.Undo.Redo(this.P)
        if !IsObject(p)
            return this.Status("msg", "Nothing to redo.")
        this.P := p
        this.AfterTreeSwap()
    }
    AfterTreeSwap() {
        keep := []
        for id in this.SelIds
            if IsObject(this.P.Find(id))
                keep.Push(id)
        this.SelIds := keep
        if !IsObject(this.P.Find(this.PageId))
            this.PageId := ""
        this.CodeTarget := ""
        this.Refresh()
        this.PushCompletions()
    }
    DuplicateSel() {
        nodes := this.SelNodes()
        if !nodes.Length
            return
        this.Mark()
        made := []
        for n in nodes {
            if (n.Type = "Root")
                continue
            made.Push(this.P.Duplicate(n).Id)
        }
        this.SelIds := made
        this.Refresh()
        this.PushCompletions()
    }
    DeleteSel() {
        nodes := this.SelNodes()
        if !nodes.Length
            return
        for n in nodes {
            if (n.Type = "Page" && n.Kids.Length) {
                cnt := 0, pageId := n.Id
                this.P.Walk(n, (k) => (k.Id != pageId ? cnt++ : 0, false))
                r := AxForm.Show(this, {Title: "Delete a whole page?", Icon: "E74D", Width: 460,
                    Intro: "The page " AxTags.E(n.Prop("title", n.Name)) " is selected, with " cnt " control"
                         . (cnt = 1 ? "" : "s") " on it. Delete the page and all of them?",
                    Fields: [{Id: "n", Kind: "note", L: "To delete one control, click it first -- it is outlined when it is the one selected. Ctrl+Z brings anything back."}],
                    Buttons: ["Delete the page", "Keep it"]})
                if !r.Ok
                    return this.Status("msg", "Kept the page.")
                break
            }
        }
        this.Mark()
        pageGone := false
        for n in nodes {
            if (n.Type = "Root")
                continue
            if (n.Type = "Page")
                pageGone := true
            this.P.Remove(n)
        }
        this.SelIds := []
        if pageGone
            this.PageId := ""
        this.CodeTarget := ""
        this.Refresh()
        this.PushCompletions()
        this.Status("msg", "Deleted.")
    }
    SelectAll() {
        page := this.CurPage()
        kids := IsObject(page) ? page.Kids : AxGen._Loose(this.P)
        ids := []
        for k in kids
            ids.Push(k.Id)
        this.SelIds := ids
        this.Reflect()
    }
    ; Copy and paste go through the real clipboard, so a control can be moved
    ; between two running copies of the studio, or kept in a scratch file.
    Copy() {
        nodes := this.SelNodes()
        if !nodes.Length
            return this.Status("msg", "Nothing selected.")
        arr := []
        for n in nodes
            if (n.Type != "Root")
                arr.Push(n.ToMap())
        m := Map("format", "axstudio/nodes", "nodes", arr)
        A_Clipboard := AxJson.Stringify(m, "  ")
        this.Status("msg", arr.Length " copied.")
    }
    Cut() {
        this.Copy()
        this.DeleteSel()
    }
    Paste() {
        raw := A_Clipboard
        if (Trim(raw) = "")
            return
        try m := AxJson.Parse(raw)
        catch {
            this.Status("msg", "The clipboard does not hold any controls.")
            return
        }
        if (AxJson.Get(m, "format", "") != "axstudio/nodes")
            return this.Status("msg", "The clipboard does not hold any controls.")
        arr := AxJson.Get(m, "nodes", "")
        if !(arr is Array) || !arr.Length
            return
        target := this.Primary()
        parent := IsObject(target) ? (target.Box ? target : target.Parent) : ""
        if !IsObject(parent)
            parent := this.CurPage() ? this.CurPage() : this.P.Root
        this.Mark()
        made := []
        for raw2 in arr {
            n := AxNode.FromMap(raw2)
            this.P.Renumber(n)
            this.P.Insert(parent, n)
            made.Push(n.Id)
        }
        this.SelIds := made
        this.Refresh()
        this.PushCompletions()
        this.Status("msg", made.Length " pasted.")
    }
    Insert(type) {
        if !AxCat.Has(type)
            return
        target := this.Primary()
        parent := ""
        if IsObject(target)
            parent := target.Box ? target : target.Parent
        if !IsObject(parent)
            parent := this.CurPage() ? this.CurPage() : this.P.Root
        this.Mark()
        node := this.P.NewNode(type)
        if (parent.Type = "Tab")
            node.L["tab"] := parent.Lay("activetab", 1)
        idx := (IsObject(target) && !target.Box && AxProject.Same(target.Parent, parent))
             ? this.P.IndexOf(target) + 1 : 0
        this.P.Insert(parent, node, idx)
        this.SelIds := [node.Id]
        this.Refresh()
        this.PushCompletions()
    }
    AddNewPage() {
        this.Mark()
        p := this.P.NewPage()
        this.P.Insert(this.P.Root, p)
        this.PageId := p.Id
        this.SelIds := [p.Id]
        this.Refresh()
    }
    ; Alignment works off the rendered canvas rather than the model, because
    ; only the canvas knows how wide a button with that text actually is.
    Align(what) {
        nodes := this.SelNodes()
        if (nodes.Length < 2)
            return this.Status("msg", "Select two or more controls first.")
        boxes := []
        try {
            page := this.El("axdPage")
            pr := page.getBoundingClientRect()
            for n in nodes {
                el := this.El("d_" n.Id)
                if !IsObject(el)
                    continue
                r := el.getBoundingClientRect()
                boxes.Push({N: n, X: r.left - pr.left, Y: r.top - pr.top,
                            W: r.right - r.left, H: r.bottom - r.top})
            }
        } catch as e
            return this.Problem("Align: " e.Message)
        if (boxes.Length < 2)
            return
        this.Mark()
        if (what = "samew" || what = "sameh") {
            v := (what = "samew") ? boxes[boxes.Length].W : boxes[boxes.Length].H
            for b in boxes
                b.N.L[what = "samew" ? "w" : "h"] := Round(v)
            this.Refresh()
            return
        }
        free := []
        for b in boxes
            if (b.N.Lay("place", "flow") = "abs")
                free.Push(b)
        if (free.Length < 2) {
            this.Status("msg", "Aligning moves freely placed controls. Set Placement to Free position first.")
            this.Refresh()
            return
        }
        lo := free[1].X, hi := free[1].X + free[1].W, loy := free[1].Y, hiy := free[1].Y + free[1].H
        for b in free {
            lo := Min(lo, b.X), hi := Max(hi, b.X + b.W)
            loy := Min(loy, b.Y), hiy := Max(hiy, b.Y + b.H)
        }
        if (what = "distx" || what = "disty") {
            AxStudio.SortBoxes(free, what = "distx" ? "X" : "Y")
            span := (what = "distx") ? (hi - lo) : (hiy - loy)
            total := 0
            for b in free
                total += (what = "distx") ? b.W : b.H
            gap := (free.Length > 1) ? (span - total) / (free.Length - 1) : 0
            at := (what = "distx") ? lo : loy
            for b in free {
                b.N.L[what = "distx" ? "x" : "y"] := Round(at)
                at += ((what = "distx") ? b.W : b.H) + gap
            }
            this.Refresh()
            return
        }
        for b in free {
            switch what {
            case "left":    b.N.L["x"] := Round(lo)
            case "right":   b.N.L["x"] := Round(hi - b.W)
            case "hcenter": b.N.L["x"] := Round((lo + hi) / 2 - b.W / 2)
            case "top":     b.N.L["y"] := Round(loy)
            case "bottom":  b.N.L["y"] := Round(hiy - b.H)
            case "vcenter": b.N.L["y"] := Round((loy + hiy) / 2 - b.H / 2)
            }
        }
        this.Refresh()
    }
    static SortBoxes(arr, key) {
        loop arr.Length - 1 {
            i := A_Index
            loop arr.Length - i {
                j := A_Index
                if (arr[j].%key% > arr[j + 1].%key%) {
                    t := arr[j], arr[j] := arr[j + 1], arr[j + 1] := t
                }
            }
        }
    }

    ; ------------------------------------------------------- context menus
    ; The bar on the selected control. See AXD.actbar.
    HudAction(act, id, x, y) {
        n := this.Primary()
        switch act {
        case "code":
            return this.OpenPrimaryEvent()
        case "dup":
            return this.DuplicateSel()
        case "del":
            return this.DeleteSel()
        case "parent":
            if (IsObject(n) && IsObject(n.Parent) && n.Parent.Type != "Root")
                return this.SetSel(n.Parent.Id)
            return this.Status("msg", "Nothing holds it but the page.")
        case "more":
            return this.NodeMenu(id, x, y)
        case "group":
            return this.ShowMenu(this.GroupItems(), x, y)
        case "align":
            return this.ShowMenu(this.AlignItems(), x, y)
        }
    }
    ; Escape walks up: from a control to what holds it, and from the top of
    ; a page to nothing -- the way out of a deep nest without the mouse.
    EscapeUp() {
        n := this.Primary()
        if (this.SelNodes().Length = 1 && IsObject(n) && IsObject(n.Parent)
            && n.Parent.Type != "Root" && n.Parent.Type != "Page")
            return this.SetSel(n.Parent.Id)
        this.SetSel("")
    }
    ; A control's menu from the keyboard: Shift+F10 or the menu key, opened
    ; just under the control rather than wherever the pointer happens to be.
    MenuAtSel() {
        n := this.Primary()
        x := 300, y := 200
        if IsObject(n) {
            try {
                r := this.El("d_" n.Id).getBoundingClientRect()
                x := r.left + 8, y := r.bottom + 4
            }
        }
        this.NodeMenu(IsObject(n) ? n.Id : "", x, y)
    }
    ; What a right-click on the canvas offers: the control's code and popover,
    ; the clipboard, its layout in one submenu, and a way to add something
    ; there. Adding used to be a tree of seven categories of controls hanging
    ; off this menu; the gallery finds any of them by typing.
    NodeMenu(id, x, y) {
        if (id != "" && !this.IsSel(id)) {
            this.SelIds := [id]
            this.Reflect(false)
        }
        n := this.Primary()
        items := []
        if IsObject(n) {
            items.Push({Label: "Its &code", Shortcut: "Enter", Icon: "E943",
                        Click: (*) => this.OpenPrimaryEvent()})
            items.Push({Label: (Trim(n.Lay("pop", "")) != "" ? "Edit the &popover" : "Give it a &popover"),
                        Icon: "E8BD", Click: (*) => this.AddPopover(n)})
            items.Push("-")
            items.Push({Label: "Cu&t", Shortcut: "Ctrl+X", Click: (*) => this.Cut()})
            items.Push({Label: "&Copy", Shortcut: "Ctrl+C", Click: (*) => this.Copy()})
            items.Push({Label: "&Paste", Shortcut: "Ctrl+V", Click: (*) => this.Paste()})
            items.Push({Label: "D&uplicate", Shortcut: "Ctrl+D", Click: (*) => this.DuplicateSel()})
            items.Push({Label: "&Delete", Shortcut: "Del", Click: (*) => this.DeleteSel()})
            items.Push("-")
            items.Push({Label: "&Layout", Icon: "E8A1", Items: [
                {Label: "On a new line", Radio: true, Checked: n.Lay("place", "flow") = "flow",
                 Click: (*) => this.SetPlaceSel("flow")},
                {Label: "Free position", Radio: true, Checked: n.Lay("place") = "abs",
                 Click: (*) => this.SetPlaceSel("abs")},
                {Label: "On the same line as the one before", Radio: true,
                 Checked: n.Lay("place") = "same", Click: (*) => this.SetPlaceSel("same")},
                "-",
                {Label: "Fill the line", Checked: n.Lay("fill", 0) ? true : false,
                 Click: (*) => this.ToggleLay("fill")},
                {Label: "Fill the height", Checked: n.Lay("grow", 0) ? true : false,
                 Click: (*) => this.ToggleLay("grow")},
                {Label: "Hidden at start-up", Checked: n.Lay("hidden", 0) ? true : false,
                 Click: (*) => this.ToggleLay("hidden")}]})
            if (IsObject(n.Parent) && n.Parent.Type != "Root")
                items.Push({Label: "Select what &holds it", Icon: "E74A",
                            Click: (*) => this.SetSel(n.Parent.Id)})
            items.Push("-")
        } else {
            items.Push({Label: "&Paste", Shortcut: "Ctrl+V", Click: (*) => this.Paste()})
            items.Push({Label: "&Fit the window to what it holds", Icon: "E740", Click: (*) => this.FitWindow()})
            items.Push("-")
        }
        items.Push({Label: "&Add something here...", Shortcut: "Ctrl+I", Icon: "E710",
                    Click: (*) => AxGallery.Open(this)})
        if !IsObject(n)
            items.Push({Label: "Add a p&age", Icon: "E7C4", Click: (*) => this.AddNewPage()})
        this.ShowMenu(items, x, y)
    }
    TreeMenu() {
        items := []
        if IsObject(this.Primary()) {
            items.Push({Label: "&Copy", Click: (*) => this.Copy()})
            items.Push({Label: "D&uplicate", Click: (*) => this.DuplicateSel()})
            items.Push({Label: "&Delete", Click: (*) => this.DeleteSel()})
            items.Push("-")
        }
        items.Push({Label: "&Paste", Click: (*) => this.Paste()})
        items.Push({Label: "&Add something here...", Shortcut: "Ctrl+I", Icon: "E710",
                    Click: (*) => AxGallery.Open(this)})
        items.Push({Label: "Add a p&age", Click: (*) => this.AddNewPage()})
        return items
    }
    ; Just the controls, grouped the way the toolbox groups them. This is what
    ; a right-click on the canvas wants; the Insert menu is the bigger list.
    ; Built when the menu opens, not when it is declared: forty items across
    ; seven submenus is enough to be felt on every right-click otherwise.
    ControlsMenu() {
        out := []
        for cat in AxCat.Cats {
            sub := []
            for e in AxCat.InCat(cat)
                sub.Push({Label: e.Label, Icon: e.Icon, Click: this.InsertFn(e.T)})
            out.Push({Label: cat, Items: sub})
        }
        return out
    }
    InsertFn(type) => (*) => this.Insert(type)
    DeferMenu(items, ev) {
        x := 0, y := 0
        try x := ev.clientX, y := ev.clientY
        SetTimer(() => this.ShowMenu(items, x, y), -1)
    }
    SetPlaceSel(mode) {
        this.Mark()
        for n in this.SelNodes()
            AxPanes.PlaceOne(n, n.Lay("place", "flow") = mode ? "flow" : mode)
        this.Refresh()
    }
    ToggleLay(key) {
        this.Mark()
        for n in this.SelNodes()
            n.L[key] := n.Lay(key, 0) ? 0 : 1
        this.Refresh()
    }

    ; -------------------------------------------------------------- menus
    Menus() {
        return [
        {Title: "&File", Items: () => this.FileMenu()},
        {Title: "&Edit", Items: () => this.EditMenu()},
        {Title: "&Add", Items: () => this.InsertMenu()},
        {Title: "&View", Items: () => this.ViewMenu()},
        {Title: "&Run", Items: () => this.RunMenu()},
        {Title: "&Help", Items: [
            {Label: "&Keys and gestures", Shortcut: "F1", Icon: "E765", Click: (*) => this.HelpDialog()},
            {Label: "&Command palette", Shortcut: "Ctrl+Shift+P",
             Click: (*) => this.Js("AXD.palOpen('cmd');")},
            {Label: "Open the studio lo&g", Icon: "E7C3",
             Click: (*) => Run('notepad.exe "' this.LogPath '"')},
            "-",
            {Label: "Check for &updates...", Icon: "E895", Click: (*) => AxUpdate.Show(this)},
            {Label: "&About AxStudio", Icon: "E946", Click: (*) => this.AboutDialog()}]}]
    }
    ; ------------------------------------------------------------ about
    ; What About is opened for: is this the code I think it is, and where is
    ; everything. Read from the files, never from a number someone has to
    ; remember to change.
    AboutDialog() {
        v := AxStudio.CodeVersion()
        now := AxStudio.NewestCode()
        T := (t) => (t = "" ? "" : FormatTime(t, "d MMM, HH:mm"))
        row := (k, val) => '<div class="axd-kv"><span>' k '</span>' AxTags.E(val) '</div>'
        stale := (AxStudio.CodeAt != "" && StrCompare(now.At, AxStudio.CodeAt) > 0)
        h := ""
        if stale
            h .= '<div class="axd-bres bad"><span class="ico">&#xE7BA;</span><b>Changed since this window '
               . 'opened.</b> ' AxTags.E(now.Name) ' was saved at ' T(now.At) '. Close the studio and '
               . 'open it again to use the new code' (this.P.Dirty ? " -- save first." : ".") '</div>'
        else
            h .= '<div class="axd-bres ok"><span class="ico">&#xE73E;</span>This window is running '
               . 'the code on disk: nothing has changed since it opened.</div>'
        h .= row("Code", v.Hash != "" ? "commit " v.Hash (v.At != "" ? ", " T(v.At) : "")
                                     : "not in a git repository")
           . row("Started", T(AxStudio.StartedAt))
           . row("Newest file", now.Name " -- " T(now.At))
           . row("Versions", "AxStudio " AxStudio.Ver ", AxGui " AxGui.Version " (github.com/" AxUpdate.Repo ")")
           . row("AutoHotkey", A_AhkVersion (A_PtrSize = 8 ? ", 64-bit" : ", 32-bit"))
           . row("Ahk2Exe", (e := AxBuild.Exe(this.Ahk2Exe)) != "" ? e : "not found on this machine")
           . row("Project", this.P.Path != "" ? this.P.Path : "not saved yet")
           . row("Studio folder", this.Store)
           . row("Library", AxStudioPaths.Lib)
        r := AxForm.Show(this, {Title: "About AxStudio", Icon: "E946", Width: 620,
            Intro: "AxStudio " AxStudio.Ver " -- a designer for AxGui windows, built with AxGui.",
            Fields: [{Id: "about", Kind: "note", Html: true, L: h}],
            Buttons: ["Check for updates", "Open the log", "Open the studio folder", "Close"], CancelIndex: 4})
        if (r.Label = "Check for updates") {
            AxUpdate.Show(this)
        } else if (r.Label = "Open the log") {
            try Run('notepad.exe "' this.LogPath '"')
        } else if (r.Label = "Open the studio folder") {
            try Run('explorer.exe "' this.Store '"')
        }
    }
    ; The commit the studio's folder is at, read out of .git rather than by
    ; running git: a hash and when the branch last moved.
    static CodeVersion() {
        out := {Hash: "", At: ""}
        g := AxStudioPaths.Root "\.git"
        try {
            head := Trim(FileRead(g "\HEAD"), " `r`n`t")
            if (SubStr(head, 1, 5) != "ref: ")
                return (out.Hash := SubStr(head, 1, 7), out)
            ref := SubStr(head, 6)
            f := g "\" StrReplace(ref, "/", "\")
            if FileExist(f)
                return (out.Hash := SubStr(Trim(FileRead(f), " `r`n`t"), 1, 7),
                        out.At := FileGetTime(f, "M"), out)
            for line in StrSplit(FileRead(g "\packed-refs"), "`n", "`r")
                if (SubStr(line, 1, 1) != "#" && SubStr(line, 42) = ref)
                    return (out.Hash := SubStr(line, 1, 7), out)
        }
        return out
    }
    ; The newest of the studio's own files and the library's.
    static NewestCode() {
        best := {At: "", Name: ""}
        for pat in [A_ScriptDir "\AxStudio*.*", AxStudioPaths.Lib "\*.ahk"] {
            loop files pat, (InStr(pat, "\lib\") ? "FR" : "F") {
                ; as text: both are 14 digits, and "" is not a number to compare with
                ; _all.ahk and the like are written by the studio itself as it starts
                if (SubStr(A_LoopFileName, 1, 1) != "_" && StrCompare(A_LoopFileTimeModified, best.At) > 0)
                    best.At := A_LoopFileTimeModified, best.Name := A_LoopFileName
            }
        }
        return best
    }
    EditMenu() {
        return [
            {Label: "&Undo", Shortcut: "Ctrl+Z", Icon: "E7A7", Click: (*) => this.DoUndo()},
            {Label: "&Redo", Shortcut: "Ctrl+Y", Icon: "E7A6", Click: (*) => this.DoRedo()},
            "-",
            {Label: "Cu&t", Shortcut: "Ctrl+X", Click: (*) => this.Cut()},
            {Label: "&Copy", Shortcut: "Ctrl+C", Click: (*) => this.Copy()},
            {Label: "&Paste", Shortcut: "Ctrl+V", Click: (*) => this.Paste()},
            {Label: "&Duplicate", Shortcut: "Ctrl+D", Click: (*) => this.DuplicateSel()},
            {Label: "De&lete", Shortcut: "Del", Click: (*) => this.DeleteSel()},
            "-",
            {Label: "&Rename it...", Shortcut: "F2", Click: (*) => this.RenameSel()},
            {Label: "Select &all on this page", Shortcut: "Ctrl+A", Click: (*) => this.SelectAll()},
            "-",
            {Label: "&Group the selection", Items: this.GroupItems()},
            {Label: "A&lign the selection", Items: this.AlignItems()},
            {Label: "&Spacing...", Icon: "E799", Click: (*) => this.SpacingWizard()}]
    }
    ; The whole of "add something" is the gallery now -- cards that say what
    ; each thing is and where it lives, found by typing. This menu is the way
    ; to it, and the few things added most often.
    InsertMenu() {
        return [{Label: "&Anything...", Shortcut: "Ctrl+I", Icon: "E710",
                 Click: (*) => AxGallery.Open(this)},
                "-",
                {Label: "A &page", Icon: "E7C4", Click: (*) => (this.GoWs("design"), this.AddNewPage())},
                {Label: "A &window...", Icon: "E7C4", Click: (*) => this.NewWindow("window")},
                {Label: "A &value...", Icon: "E8EF", Click: (*) => (this.SetWs("logic"), this.ValueWizard())},
                {Label: "A &binding...", Icon: "E8C8", Click: (*) => (this.SetWs("logic"), this.BindWizard())},
                {Label: "A &rule...", Icon: "E945", Click: (*) => (this.SetWs("logic"), this.FlowWizard())},
                {Label: "A &hotkey...", Icon: "E765", Click: (*) => (this.SetWs("logic"), this.HotkeyWizard())},
                {Label: "A hot&string...", Icon: "E8D2", Click: (*) => (this.GoSec("hotstrings", "logic"), AxAutoUi.Hotstring(this))},
                {Label: "A t&imer...", Icon: "E916", Click: (*) => (this.GoSec("timers", "logic"), AxAutoUi.Timer(this))},
                {Label: "A &condition...", Icon: "E9D5", Click: (*) => (this.GoSec("conditions", "logic"), AxAutoUi.Cond(this))},
                {Label: "A &macro", Icon: "E768", Click: (*) => AxAuto2Ui.AddMacro(this)},
                {Label: "A setti&ng...", Icon: "E713", Click: (*) => (this.GoSec("settings", "logic"), AxAuto2Ui.Setting(this))},
                {Label: "An &event...", Icon: "E7C1", Click: (*) => (this.GoSec("events", "logic"), AxAuto2Ui.Event(this))},
                {Label: "A &folder watcher...", Icon: "E8B7", Click: (*) => (this.GoSec("watchers", "logic"), AxAuto2Ui.Watcher(this))},
                "-",
                {Label: "Files the program needs...", Icon: "E8A5", Click: (*) => (this.GoSec("files", "app"), AxFilesUi.AddFiles(this))},
                {Label: "A library...", Icon: "E82D", Click: (*) => this.GoSec("libraries", "app")},
                {Label: "A step, step by step...", Icon: "E8FD", Click: (*) => AxMap.SetMode(this, "steps")}]
    }
    ViewMenu() {
        ; a tick, not a radio dot: the dot is a text character, and beside the
        ; icon glyphs of the other rows it pushed its label out of line
        W := (id, label, ico) => {Label: label, Checked: this.Ws = id, Icon: ico,
                                   Shortcut: "Ctrl+" AxStudio.WsIndex(id),
                                   Click: (*) => this.SetWs(id)}
        return [
            W("design", "&Design: the canvas", "E7C4"),
            W("logic", "&Logic: values, bindings, rules, states", "E945"),
            W("code", "&Code", "E943"),
            W("app", "&App: windows, files, how it is built", "E7B8"),
            W("look", "Loo&k: colours, shapes, type", "E790"),
            W("map", "&Map: the program, and each piece step by step", "E81E"),
            "-",
            {Label: "The bottom &panel", Checked: this.PanelOpen ? true : false,
             Shortcut: "Ctrl+J", Click: (*) => this.TogglePanel()},
            {Label: "Pro&blems", Icon: "E7BA", Click: (*) => this.ShowPanel("lint")},
            {Label: "Out&put", Icon: "E756", Click: (*) => this.ShowPanel("out")},
            "-",
            {Label: "The &Toolbox and Outline", Checked: this.LeftShown ? true : false,
             Shortcut: "Ctrl+B", Click: (*) => this.TogglePane("L")},
            {Label: "The &inspector", Checked: this.RightShown ? true : false,
             Shortcut: "Ctrl+Shift+B", Click: (*) => this.TogglePane("R")},
            "-",
            {Label: "The whole generated &script", Click: (*) => this.ShowGenerated()},
            "-",
            {Label: "&Grid and guides", Icon: "E80A", Items: [
                {Label: "Show the design &grid", Checked: this.ShowGrid ? true : false,
                 Click: (*) => (this.ShowGrid := !this.ShowGrid, this.SaveSettings(), this.Refresh())},
                {Label: "&Snap to it", Checked: this.Snap ? true : false,
                 Click: (*) => (this.Snap := !this.Snap, this.SaveSettings(), this.Bar(), this.PushOpts())},
                {Label: "Alignment g&uides", Checked: this.Guides ? true : false,
                 Click: (*) => (this.Guides := !this.Guides, this.SaveSettings(), this.Bar(), this.PushOpts())}]},
            {Label: "The studio's &look", Icon: "E790", Items: [
                {Label: "&Dark", Radio: true, Checked: this.UiTheme = "dark",
                 Click: (*) => this.SetUi("dark")},
                {Label: "&Light", Radio: true, Checked: this.UiTheme = "light",
                 Click: (*) => this.SetUi("light")},
                "-",
                {Label: "&Hide the bottom bar until the pointer is near it", Checked: this.AutoHideBar ? true : false,
                 Click: (*) => this.SetAutoHide(!this.AutoHideBar)},
                "-",
                {Label: "&Roomy panels", Radio: true, Checked: !this.Dense,
                 Click: (*) => this.SetDense(0)},
                {Label: "&Compact panels", Radio: true, Checked: this.Dense ? true : false,
                 Click: (*) => this.SetDense(1)}]}]
    }
    ; A section of Logic or App, from its rail -- or from anywhere that wants
    ; to show one (a wizard, a problem, "list them all").
    GoSec(sec, ws := "") {
        ws := (ws != "") ? ws : (this.Ws = "app" || this.Ws = "look") ? this.Ws : "logic"
        if (ws = "app")
            this.AppSec := sec
        else if (ws = "look")
            this.LookSel := sec
        else
            this.LogicSec := sec
        if (this.Ws != ws)
            return this.SetWs(ws)
        this.Reflect(false)
        this.NavNote()
    }
    ; Where a "see also" link goes. Every setting lives in one place, and the
    ; places that touch it link there rather than repeating it:
    ;   a workspace       go.design  go.logic  go.code  go.app  go.look  go.map
    ;   a section         go.rules  go.files  go.script  go.tray ...  (either rail)
    ;   the window        go.window, or go.window.<group> -- the window's own
    ;                     properties on the Design tab, that group opened
    GoTo(where) {
        static ws := Map("design", 1, "logic", 1, "steps", 1, "code", 1, "app", 1, "look", 1, "map", 1)
        if ws.Has(where)
            return this.SetWs(where)
        if (SubStr(where, 1, 6) = "window") {
            grp := SubStr(where, 8)
            this.SelIds := []
            this.RightTab := "props"
            if (grp != "" && this.Shut is Map && this.Shut.Has(grp))
                this.Shut.Delete(grp)
            if (this.Ws != "design")
                this.SetWs("design")
            else
                this.Refresh()
            if (grp != "")
                try this.El("grp_" grp).scrollIntoView()
            return
        }
        for w, list in AxStudio.Sections
            for k in list
                if (k = where)
                    return this.GoSec(where, w)
        this.Status("msg", "Nothing called " where " to go to.")
    }
    ; Up and Down on Logic and App: the section above or below, in rail order.
    static Sections := Map("logic", ["values", "conditions", "hotstrings", "timers", "macros", "settings",
                                     "events", "watchers", "bindings", "rules", "states", "hotkeys", "menus", "code"],
                           "app", ["windows", "details", "build", "files", "includes", "libraries", "packs",
                                   "arguments", "modes", "tray", "script"])
    StepSec(d) {
        list := AxStudio.Sections[this.Ws]
        cur := (this.Ws = "app") ? this.AppSec : this.LogicSec
        i := 1
        for j, k in list
            if (k = cur)
                i := j
        i := Max(1, Min(list.Length, i + d))
        this.GoSec(list[i])
    }
    ; A data grid's columns and rows, as a spreadsheet over the studio.
    OpenSheet() {
        n := this.Primary()
        if !IsObject(n)
            return
        this.SheetNode := n.Id
        this.SheetOpen := true
        if (n.Type = "ListView")                ; its text, as the grid's columns and rows
            return this.SendTo(AxJson.Stringify({text: AxStudio.ListViewExpr(n.Arg), title: "Data -- " n.Name, lv: 1}, ""),
                "AXG.sheet(JSON.parse(document.getElementById('axdIn').value));")
        this.SendTo(AxJson.Stringify({text: String(n.Arg), title: "Data -- " n.Name}, ""),
            "AXG.sheet(JSON.parse(document.getElementById('axdIn').value));")
    }
    ; A list view's text ("Name | Size" then a row a line, "[x] " ticked) as
    ; the {Columns, Rows} the spreadsheet edits; AXG.lvText turns it back.
    static ListViewExpr(text) {
        lines := []
        for one in StrSplit(StrReplace(String(text), "`r"), "`n")
            if (Trim(one) != "")
                lines.Push(one)
        if !lines.Length
            return "{Columns: [{Key: " AxLit.S("c1") ", Title: " AxLit.S("Name") "}], Rows: []}"
        cols := "", keys := []
        for i, t in StrSplit(lines.RemoveAt(1), "|") {
            keys.Push("c" i)
            cols .= (i = 1 ? "" : ", ") "{Key: " AxLit.S("c" i) ", Title: " AxLit.S(Trim(t)) "}"
        }
        rows := ""
        for r, one in lines {
            tick := RegExMatch(one, "i)^\s*\[x\+?\]\s?", &m)
            if tick
                one := SubStr(one, m.Len + 1)
            row := "{Key: " AxLit.S("r" r) (tick ? ", Checked: 1" : "")
            for i, v in StrSplit(one, "|")
                if (i <= keys.Length)
                    row .= ", " keys[i] ": " AxLit.S(Trim(v))
            rows .= (r = 1 ? "" : ",`n    ") row "}"
        }
        return "{Columns: [" cols "],`n Rows: [" rows "]}"
    }
    ; Another radio group in this one's group, just after it: its options act
    ; as more of the same choice.
    RadioMore() {
        n := this.Primary()
        if (!IsObject(n) || n.Type != "Radio")
            return
        this.Mark()
        if (Trim(n.Prop("group", "")) = "")
            n.P["group"] := n.Name
        m := this.P.NewNode("Radio")
        m.P["group"] := n.P["group"]
        m.Arg := "more:Another option"
        this.P.Insert(n.Parent, m, this.P.IndexOf(n) + 1)
        this.SelIds := [m.Id]
        this.Refresh()
        this.PushCompletions()
        this.Status("msg", m.Name " is in the group " n.P["group"] " with " n.Name ".")
    }
    ; ------------------------------------------------------------ zoom
    static Zooms := [0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    SetZoom(z) {
        z := Round(Min(3, Max(0.25, z)), 2)
        if (z = this.Zoom)
            return
        this.Zoom := z
        this.SaveSettings()
        this.PushOpts()
        this.RefreshCanvas()
        this.Bar()
        this.Status("msg", "Zoom " Round(z * 100) "%. Ctrl+0 is 100%.")
    }
    ZoomStep(d) {
        list := AxStudio.Zooms
        if (d > 0) {
            for z in list
                if (z > this.Zoom + 0.001)
                    return this.SetZoom(z)
        } else {
            i := list.Length
            while (i >= 1) {
                if (list[i] < this.Zoom - 0.001)
                    return this.SetZoom(list[i])
                i--
            }
        }
    }
    ; the whole window in the canvas, with a margin round it
    ZoomFit() {
        w := 0, h := 0
        try {
            wr := this.El("axdCanvasWrap")
            w := wr.clientWidth, h := wr.clientHeight
        }
        if (w < 100 || h < 100)
            return
        this.SetZoom(Min((w - 60) / this.P.Width, (h - 60) / this.P.Height))
    }
    ZoomMenu() {
        items := []
        for z in [0.5, 0.75, 1, 1.25, 1.5, 2]
            items.Push({Label: Round(z * 100) "%", Radio: true, Checked: Abs(this.Zoom - z) < 0.001,
                        Click: this.ZoomFn(z)})
        items.Push("-", {Label: "&Fit the window", Click: (*) => this.ZoomFit()},
                   {Label: "Zoom &in", Shortcut: "Ctrl+=", Click: (*) => this.ZoomStep(1)},
                   {Label: "Zoom &out", Shortcut: "Ctrl+-", Click: (*) => this.ZoomStep(-1)})
        this.ShowMenu(items)
    }
    ZoomFn(z) => (*) => this.SetZoom(z)

    ; ------------------------------------------------------ lining up
    ; AXD.alPlan works out, from where things really are on the canvas, where
    ; each control goes and which cannot move; this carries the plan out.
    ; A freely placed control gets its x and y, one in the flow its margin (the
    ; space before it, or beside it on the same line), and a resize its size.
    ApplyAlign(op, items) {
        moved := 0, flow := [], stays := ""
        for it in items {
            n := this.P.Find(AxStudio.J(it, "id"))
            if !IsObject(n)
                continue
            fate := AxStudio.J(it, "fate")
            if (fate = "stays")
                stays := n.Label
            if (fate = "flow")
                flow.Push(n.Label)
            if (fate != "moves" && fate != "resized")
                continue
            if !moved
                this.Mark()
            moved++
            for k in ["x", "y", "w", "h"]
                if (AxStudio.J(it, k, "") != "")
                    n.L[k] := AxStudio.J(it, k)
            if (AxStudio.J(it, "dtop", "") != "")
                n.L["top"] := Round(n.Lay("top", 0) + AxStudio.J(it, "dtop"))
            if (AxStudio.J(it, "dgap", "") != "") {
                cur := n.Lay("gap", "")
                n.L["gap"] := Max(0, Round((cur = "" ? 8 : cur) + AxStudio.J(it, "dgap")))
            }
        }
        if moved
            this.Refresh()
        msg := moved ? (moved = 1 ? "Moved one." : "Moved " moved ".") : "Nothing needed to move."
        if (stays != "")
            msg .= " " stays " stayed put."
        if flow.Length
            msg .= " " (flow.Length = 1 ? flow[1] " is" : flow.Length " are") " in the flow and cannot be "
                 . "moved sideways -- set Placement to Free position, or use spacing."
        this.Status("msg", msg)
    }
    static J(m, k, d := "") => AxJson.Get(m, k, d)
    SetAnchor(v) {
        this.AlAnchor := (v = "last" || v = "page") ? v : "each"
        this.SaveSettings()
        this.PushOpts()
        this.Reflect(false)
    }

    ; -------------------------------------------------- data from a file
    ; A CSV (or a TSV, or a table copied out of Excel and saved) into the data
    ; sheet: its first line as the column names or not, and its rows in
    ; place of what is there or after it. AXG.importCsv does the reading.
    SheetCsv() {
        f := FileSelect(3, , "A table for the data grid", "Tables (*.csv; *.tsv; *.txt)")
        if (f = "")
            return
        text := ""
        try text := FileRead(f, "UTF-8")
        ; a file Excel saved as ANSI reads with question marks as UTF-8
        if InStr(text, Chr(0xFFFD))
            try text := FileRead(f, "CP0")
        SplitPath(f, &nm)
        r := AxForm.Show(this, {Title: "Import " nm, Icon: "E8A5", Width: 460,
            Intro: "Commas, semicolons or tabs between the values; quotes round any that hold one.",
            Fields: [{Id: "head", L: "The first line is the column names", Kind: "flag", V: 1},
                     {Id: "how", L: "The rows", Kind: "choice", V: "replace",
                      Opts: "replace:In place of what is there|append:After what is there"}],
            Buttons: ["Import", "Cancel"]})
        if !r.Ok
            return
        this.SendTo(AxJson.Stringify({text: text, head: r.V["head"] ? 1 : 0, how: r.V["how"], name: nm}, ""),
            "AXG.importCsv(JSON.parse(document.getElementById('axdIn').value));")
    }

    ; ------------------------------------------------------ the tab order
    ; A number on every control that takes the keyboard, and each click makes
    ; the one clicked the next in line. The order is kept as names in the
    ; window's TabOrder; the rest follow as they are laid out.
    ToggleTabOrder(on := "") {
        on := (on = "") ? !this.TabMode : on
        if (on && this.Ws != "design")
            this.SetWs("design")
        this.TabMode := on ? true : false
        this.TabSeq := []
        if this.TabMode {
            this.Mark()
            this.SelIds := []
            this.Send({cmd: "select", sel: []})
        }
        this.SendTab()
        this.Bar()
        this.Reflect(false)
        this.Status("msg", this.TabMode
            ? "Tab order: click the controls in the order Tab should visit them. Escape when done."
            : "Tab order kept.")
    }
    SendTab() {
        items := []
        if this.TabMode {
            set := Map()
            for nm in this.TabSeq
                set[nm] := true
            for i, n in AxKeyOrder.Order(this.P, this.P.W)
                items.Push({id: n.Id, n: i, set: set.Has(n.Name) ? 1 : 0})
        }
        this.Send({cmd: "taborder", on: this.TabMode ? 1 : 0, items: items})
    }
    TabPick(id) {
        n := this.P.Find(id)
        if !IsObject(n)
            return
        if !AxKeyOrder.Takes(n)
            return this.Status("msg", (n.Name = "" && AxCat.Has(n.Type) && !AxCat.Get(n.Type).Box)
                ? "Give it a name first (F2): the order is kept by name." : "That one does not take the keyboard.")
        seq := []
        for nm in this.TabSeq
            if (nm != n.Name)
                seq.Push(nm)
        seq.Push(n.Name)
        this.TabSeq := seq
        txt := ""
        for nm in seq
            txt .= (txt = "" ? "" : "`n") nm
        for m in AxKeyOrder.Order(this.P, this.P.W) {
            had := false
            for nm in seq
                had := had || (nm = m.Name)
            if !had
                txt .= "`n" m.Name
        }
        this.P.W.TabOrder := txt
        this.P.Dirty := true
        this.SendTab()
        this.Status("msg", n.Name " is number " seq.Length ". Click the next one, or Escape when done.")
    }
    ; Toolbox or Outline: the switch at the top of the left pane.
    LeftTabClick(ev) {
        t := this.UpAttr(ev.srcElement, "data-ltab")
        if (t != "")
            this.SetLeftTab(t)
    }
    SetLeftTab(t) {
        this.LeftTab := (t = "tree") ? "tree" : "tools"
        this.SaveSettings()
        AxPanes.LeftTabs(this)
    }
    ; How tightly the side panels pack their rows. A class on the page, so
    ; nothing is rebuilt.
    SetDense(on) {
        this.Dense := on ? 1 : 0
        this.SaveSettings()
        this.ApplyDensity()
        this.Status("msg", on ? "Compact panels." : "Roomy panels.")
    }
    ApplyDensity() {
        try AxWindow._SetClass(this.Doc.body, "axd-dense", this.Dense ? true : false)
    }
    static WsIndex(ws) {
        for i, w in AxStudio.Workspaces
            if (w = ws)
                return i
        return 1
    }
    RunMenu() {
        return [
            {Label: "&Run it", Shortcut: "F5", Icon: "E768", Click: (*) => this.Preview()},
            {Label: "&Try it here, on the canvas", Shortcut: "F6", Icon: "E7C4",
             Checked: this.Testing ? true : false, Click: (*) => this.ToggleTest()},
            "-",
            {Label: "&Live: re-run after every change", Checked: this.Live ? true : false,
             Click: (*) => (this.Live := !this.Live, this.Bar(),
                            this.Live ? this.Preview() : this.StopPreview())},
            {Label: "S&top it", Icon: "E71A", Click: (*) => this.StopPreview()},
            "-",
            {Label: "&Check every handler", Icon: "E930", Click: (*) => this.CheckAll()}]
    }
    WindowMenu() {
        items := []
        for i, w in this.P.Wins
            items.Push({Label: w.Name (w.Kind = "main" ? "" : "   " AxGen.Fn(w) "()"),
                        Icon: AxPanes.WinIcon(w.Kind), Radio: true, Checked: (i = this.P.Cur),
                        Click: this.SwitchWinFn(i)})
        items.Push("-")
        items.Push({Label: "&Add a window...", Icon: "E7C4", Click: (*) => this.NewWindow()})
        items.Push({Label: "&Open it from...", Icon: "E71B", Click: (*) => this.LinkWizard()})
        items.Push("-")
        items.Push({Label: "&Rename this window...", Click: (*) => this.RenameWin()})
        items.Push({Label: "D&uplicate this window", Click: (*) => this.DuplicateWin()})
        items.Push({Label: "De&lete this window", Click: (*) => this.DeleteWin()})
        items.Push("-")
        items.Push({Label: "&List them all", Click: (*) => this.GoSec("windows", "app")})
        return items
    }
    FileMenu() {
        ; New is a blank project. The templates were a submenu here as well as
        ; a picker one line down; the picker says what each one is for.
        items := [{Label: "&Start screen...", Icon: "E80F", Click: (*) => AxWiz.Welcome(this)},
                  {Label: "&New", Icon: "E710", Click: this.NewFn("blank")},
                  {Label: "New from a &template...", Icon: "E710",
                   Click: (*) => (this.ConfirmDiscard() ? AxWiz.Template(this) : "")},
                  {Label: "&Open...", Shortcut: "Ctrl+O", Click: (*) => this.Open()},
                  {Label: "&Import a script...", Icon: "E8B5", Click: (*) => this.ImportScript()}]
        if this.Recent.Length {
            sub := []
            for f in this.Recent
                sub.Push({Label: AxStudio.Short(f), Click: this.OpenFn(f)})
            sub.Push("-")
            sub.Push({Label: "Clear the list", Click: (*) => (this.Recent := [], this.SaveSettings())})
            items.Push({Label: "Open &recent", Items: sub})
        }
        items.Push("-")
        items.Push({Label: "&Save", Shortcut: "Ctrl+S", Click: (*) => this.Save()})
        items.Push({Label: "Save &as...", Click: (*) => this.SaveAs()})
        items.Push("-")
        tgt := this.ExportTarget()
        items.Push({Label: tgt != "" ? "&Export to " AxStudio.Short(tgt) : "&Export script...",
                    Shortcut: "Ctrl+E", Click: (*) => this.Export()})
        items.Push({Label: "Export script &as...", Click: (*) => this.Export(true)})
        items.Push("-")
        ; only there when there is something to recover -- a dead line otherwise
        if FileExist(this.AutoPath) {
            items.Push({Label: "Recover the last autosave", Icon: "E777",
                        Click: (*) => this.LoadFile(this.AutoPath)})
            items.Push("-")
        }
        items.Push({Label: "&Compile...", Icon: "E7B8", Click: (*) => AxWiz.Compile(this)})
        items.Push({Label: "Compile it &now", Icon: "E7B8", Click: (*) => AxWiz.Build(this)})
        items.Push("-")
        items.Push({Label: "Se&ttings...", Icon: "E713", Click: (*) => AxWiz.Settings(this)})
        items.Push("-")
        items.Push({Label: "E&xit", Shortcut: "Alt+F4", Click: (*) => this.Close()})
        return items
    }
    NewFn(id) => (*) => this.NewProject(id)
    OpenFn(path) => (*) => (this.ConfirmDiscard() ? this.LoadFile(path) : "")
    static Short(p) {
        SplitPath(p, &name, &dir)
        SplitPath(dir, &parent)
        return (parent != "" ? parent "\" : "") name
    }

    ; -------------------------------------------------------------- files
    NewProject(id := "blank") {
        if !this.ConfirmDiscard()
            return
        this.P := AxTpl.Build(id)
        this.P.ExportedTo := ""
        this.Undo.Reset()
        this.SelIds := [], this.PageId := "", this.CodeTarget := ""
        this.SetEditor("", false)
        this.Refresh()
        this.PushCompletions()
        this.ClearAutoSave()
        this.Status("path", "Untitled")
        this.SaveState()
        this.Status("msg", "New project from the " AxTpl.Get(id).Name " template.")
        this.MarkCleanSoon()
    }
    ; Only a project that differs from how it was made, opened or saved asks.
    ; Starting up, drawing the canvas or switching a tab can set Dirty with
    ; nothing of yours in it, and then every template picked asked to discard.
    ConfirmDiscard() {
        if !this.P.Dirty
            return true
        if (this._cleanSig != "")
            try if (AxJson.Stringify(this.P.ToMap(), "") == this._cleanSig)
                return true
        return this.Confirm("This project has unsaved changes. Discard them?", "AxStudio")
    }
    ; the project as it stands is the one there is nothing to lose from
    MarkClean() {
        this.P.Dirty := false
        try this._cleanSig := AxJson.Stringify(this.P.ToMap(), "")
    }
    ; ...once what a load or a new project sets off has finished
    MarkCleanSoon() {
        if !this.HasOwnProp("_markCleanFn")
            this._markCleanFn := (*) => this.MarkClean()
        SetTimer(this._markCleanFn, -400)
    }
    ; A script that builds an AxGui window, as a new design (AxStudio.Import.ahk).
    ImportScript(path := "", asked := false) {
        if (!asked && !this.ConfirmDiscard())
            return
        if (path = "") {
            start := this.Recent.Length ? this.Recent[1] : A_MyDocuments
            path := FileSelect(3, start, "Import an AutoHotkey script -- a window, hotkeys, or both", "AutoHotkey script (*.ahk)")
            if (path = "")
                return
        }
        SplitPath(path, &name)
        this.Status("msg", "Reading " name "...")
        try r := AxImportGui.FromFile(path)
        catch as e
            return this.Alert("That script could not be brought in.`n`n" e.Message, "Import")
        ; then what it does: hotkeys, hotstrings, timers, values, settings...
        ; -- the ones ticked become the studio's lists instead of code
        r.Logic := Map()
        try {
            found := AxImportLogic.Scan(r.Project)
            kinds := AxImportLogic.Wizard(this, found, name)
            if kinds.Length
                r.Logic := AxImportLogic.Apply(r.Project, found, kinds)
        } catch as e
            r.Notes.Push("What the script does was left as code: " e.Message)
        this.Adopt(r, path)
        this.Alert(AxStudio.ImportReport(r, name), "Imported " name)
    }
    Adopt(r, path) {
        SplitPath(path, &name)
        this.P := r.Project
        this.P.Path := "", this.P.ExportedTo := ""
        this.Undo.Reset()
        this.SelIds := [], this.PageId := "", this.CodeTarget := ""
        this.SetEditor("", false)
        this.Refresh()
        this.PushCompletions()
        this.Status("path", "Untitled (from " name ")")
        this.SaveState()
        this.Status("msg", "Imported " name ": " r.N.Controls " controls, " r.N.Events " handlers.")
    }
    static ImportReport(r, name) {
        n := r.N, nl := "`n"
        s := (n.HasOwnProp("Plain") && n.Plain) ? "It has no window of its own." nl
           : "Brought in " n.Controls " control" (n.Controls = 1 ? "" : "s")
           . (n.Pages ? " on " n.Pages " page" (n.Pages = 1 ? "" : "s") : "")
           . ", with " n.Events " handler" (n.Events = 1 ? "" : "s") "." nl
        if (r.HasOwnProp("Logic") && r.Logic.Count) {
            s .= nl "Brought in without code:" nl
            for k in AxImportLogic.Kinds
                if r.Logic.Has(k[1]) && r.Logic[k[1]]
                    s .= "  " r.Logic[k[1]] " " StrLower(k[2]) " -- " k[3] nl
        }
        if (n.HasOwnProp("Windows") && n.Windows > 1)
            s .= nl n.Windows " windows: one window of the design each." nl
        if (n.HasOwnProp("Rules") && n.Rules)
            s .= nl n.Rules " handler" (n.Rules = 1 ? " was" : "s were") " simple enough to become rules -- no code:"
               . " Logic > Rules." nl
        if n.Code
            s .= nl n.Code " piece" (n.Code = 1 ? " of code runs" : "s of code run") " while the window is built, "
               . "where " (n.Code = 1 ? "it" : "they") " did: the Code blocks in the Outline." nl
        if n.Script
            s .= nl n.Script " function" (n.Script = 1 ? ", hotkey or line" : "s, hotkeys and lines")
               . " went to the window's script, as written." nl
        if r.Notes.Length {
            s .= nl "Worth a look:" nl
            for i, t in r.Notes {
                if (i > 12) {
                    s .= "  ... and " (r.Notes.Length - 12) " more" nl
                    break
                }
                s .= "  " t nl
            }
        }
        fixed := false
        for w in r.Project.Wins
            if (w.ImportLayout != "")
                fixed := true
        if fixed
            s .= nl "Every control is where the script put it. To have the window resize, pick"
               . " Controls sit > In rows that resize (window settings, Layout from the script) --"
               . " and back again whenever you like: the places are kept." nl
        s .= nl "Save it to keep it. The script itself is not changed."
        return s
    }
    Open() {
        if !this.ConfirmDiscard()
            return
        start := this.P.Path != "" ? this.P.Path : (this.Recent.Length ? this.Recent[1] : A_MyDocuments)
        f := FileSelect(3, start, "Open a project, or a script it exported",
                        "AxStudio project or script (*.axs.json;*.json;*.ahk)")
        if (f != "")
            this.LoadFile(f)
    }
    LoadFile(path) {
        if !FileExist(path)
            return this.Alert("Nothing saved there yet.", "Open")
        script := ""
        if RegExMatch(path, "i)\.ahk$") {
            ; An exported script names its project rather than carrying a copy
            ; of the design, so opening one is a matter of following the line.
            try text := FileRead(path, "UTF-8")
            catch as e
                return this.Alert("That file would not read:`n" e.Message, "Open")
            ref := AxMerge.RefPath(path, text)
            ; a script the studio did not write: brought in -- a window, or
            ; only hotkeys and timers, either way
            if (ref = "")
                return this.ImportScript(path, true)
            if !FileExist(ref)
                return this.Alert("The script points at`n`n    " ref "`n`nand there is nothing there."
                    . "`n`nPut the project back beside the script, or open it from wherever it is now.", "Open")
            script := path, path := ref
        }
        try p := AxProject.FromJson(FileRead(path, "UTF-8"))
        catch as e
            return this.Alert("That file did not read as an AxStudio project.`n`n" e.Message, "Open")
        this.P := p
        this.P.Path := (path = this.AutoPath) ? "" : path
        this.P.ExportedTo := script
        this.P.Dirty := false
        this._cleanSig := ""
        if (path != this.AutoPath)                 ; a recovered autosave is unsaved work
            this.MarkCleanSoon()
        this.Undo.Reset()
        this.SelIds := [], this.PageId := "", this.CodeTarget := ""
        this.SetEditor("", false)
        this.Refresh()
        this.PushCompletions()
        if (this.P.Path != "")
            this.Remember(this.P.Path)
        this.Status("path", this.P.Path != "" ? this.P.Path : "Recovered autosave")
        this.SaveState()
        this.Status("msg", "Opened.")
        ; Opened through a script: it may have picked up edits since the
        ; export, and those are worth more than the copy in the project.
        if (script != "")
            this.PullBack(FileRead(script, "UTF-8"), script, true)
    }
    Remember(path) {
        out := [path]
        for f in this.Recent
            if (f != path && out.Length < 8)
                out.Push(f)
        this.Recent := out
        this.SaveSettings()
    }
    Save() {
        this.CodeTyped()                   ; what is in the editor, kept first
        if (this.P.Path = "")
            return this.SaveAs()
        return this.SaveTo(this.P.Path)
    }
    SaveAs() {
        def := this.P.Path != "" ? this.P.Path
             : A_MyDocuments "\" AxStudio.SafeName(this.P.Title) ".axs.json"
        f := FileSelect("S18", def, "Save the project", "AxStudio project (*.axs.json)")
        if (f = "")
            return false
        if !InStr(f, ".")
            f .= ".axs.json"
        return this.SaveTo(f)
    }
    SaveTo(path) {
        try AxJson.Save(path, this.P.ToMap())
        catch as e {
            this.Alert("Could not save:`n" e.Message, "Save")
            return false
        }
        this.P.Path := path
        this.MarkClean()
        this.Remember(path)
        this.ClearAutoSave()
        this.Status("path", path)
        this.Status("msg", "Saved " FormatTime(, "HH:mm:ss"))
        this.SaveState("Saved " FormatTime(, "HH:mm"))
        return true
    }
    AutoSave() {
        if (this.Closing)
            return
        if !this.P.Dirty {
            ; nothing outstanding: the recovery file would only be a stale copy
            this.ClearAutoSave()
            this.SaveState()
            return
        }
        ; Straight to the file, if that is what the settings say and there is
        ; a file. Otherwise a spare copy in AppData and a .bak beside the real
        ; one, which is the safe default: nothing of yours is written over by
        ; a timer you did not think about.
        if (this.AutoToFile && this.P.Path != "") {
            try {
                AxJson.Save(this.P.Path, this.P.ToMap())
                this.P.Dirty := false
                this.ClearAutoSave()
                return this.SaveState("Saved " FormatTime(, "HH:mm"))
            }
        }
        try AxJson.Save(this.AutoPath, this.P.ToMap())
        if (this.P.Path != "")
            try AxJson.Save(this.P.Path ".bak", this.P.ToMap())
        this.SaveState("Autosaved " FormatTime(, "HH:mm"))
    }
    ; Export is a merge, not an overwrite. The blocks marked #region axstudio
    ; are replaced; every other line in the file stays exactly where it was,
    ; so hand-added includes, hotkeys and helpers survive. See AxStudio.Merge.
    Export(ask := false) {
        this.CodeTyped()
        f := ask ? "" : this.ExportTarget()
        if (f = "") {
            def := this.P.Path != "" ? RegExReplace(this.P.Path, "\.axs\.json$|\.json$", ".ahk")
                                     : A_MyDocuments "\" AxStudio.SafeName(this.P.Title) ".ahk"
            f := FileSelect("S18", def, "Export the AutoHotkey script", "AutoHotkey v2 (*.ahk)")
            if (f = "")
                return
            if !InStr(f, ".")
                f .= ".ahk"
        }
        ; The script points at the project rather than carrying a copy of the
        ; design, so there has to be a project file for it to point at.
        if (this.P.Path = "" && !this.SaveBeside(f))
            return
        if !this.LintGate()
            return
        old := ""
        if FileExist(f) {
            try old := FileRead(f, "UTF-8")
            if (Trim(old) != "" && !AxMerge.IsOurs(old)) {
                if !this.Confirm("There is already a script at`n`n    " AxStudio.Short(f)
                               . "`n`nand AxStudio did not write it. Overwrite it?",
                                 "Export", "Overwrite", "Cancel", "warning")
                    return
                old := ""
            } else if !this.PullBack(old, f)
                return
        }
        code := AxGen.Script(this.P, f, "", this.PreBody())
        kept := (Trim(old) != "" && AxMerge.IsOurs(old))
        if kept
            code := AxMerge.Merge(old, code)
        try {
            if FileExist(f)
                FileDelete(f)
            FileAppend(code, f, "UTF-8-RAW")
        } catch as e
            return this.Alert("Could not write the script:`n" e.Message, "Export")
        this.P.ExportedTo := f
        r := AxStudio.Validate(code, f)
        this.Status("msg", (r.Ok ? "Exported" : "Exported, but it does not parse")
                         . (kept ? " (your own lines kept): " : ": ") f)
        if !r.Ok
            this.Alert("The script was written, but the interpreter rejects it:`n`n" r.Msg, "Export")
    }

    ; =====================================================================
    ;  The command palette
    ; =====================================================================
    ; Every command, every control the toolbox can add, and every window,
    ; page and control in the project -- one list, sent to the canvas after
    ; each refresh so that typing in it costs nothing. Ctrl+Shift+P opens the
    ; commands, Ctrl+P the places. See palRender in AxStudio.js.
    PushPalette() {
        try this.SendTo(AxJson.Stringify(this.PaletteItems(), ""),
            "AXD.pal.items = JSON.parse(document.getElementById('axdIn').value);")
    }
    PaletteItems() {
        out := []
        A := (id, label, group, icon := "", key := "") =>
             out.Push(Map("id", id, "label", label, "group", group, "icon", icon, "key", key, "go", 0))
        A("cmd:save", "Save the project", "File", "E74E", "Ctrl+S")
        A("cmd:saveas", "Save as...", "File", "E792")
        A("cmd:open", "Open a project or script...", "File", "E8E5", "Ctrl+O")
        A("cmd:import", "Import a script that builds a window (AxGui or Gui)...", "File", "E8B5")
        if AxLayout.Has(this.P.W) {
            A("cmd:layrows", "Imported layout: rows that resize", "Window", "E8A1")
            A("cmd:layfixed", "Imported layout: where the script put everything", "Window", "E8A1")
        }
        A("cmd:welcome", "The start screen", "File", "E70F")
        A("cmd:template", "New from a template...", "File", "E710")
        A("cmd:settings", "Settings...", "File", "E713")
        A("cmd:helper", "Add a script helper...", "Wizards", "E943")
        A("cmd:data", "Fill a list with data...", "Wizards", "E9D5")
        A("cmd:file", "Add a file the script needs...", "Wizards", "E8E5")
        A("cmd:include", "Add an include...", "Wizards", "E943")
        A("cmd:arg", "Add a command-line argument...", "Wizards", "E756")
        A("cmd:mode", "Add a start-up mode...", "Wizards", "E7C4")
        A("cmd:tray", "The tray icon and its menu...", "File", "E8B7")
        A("cmd:compile", "Compile...", "File", "E7B8")
        A("cmd:build", "Compile it now", "File", "E7B8")
        A("cmd:value", "Add a value...", "Wizards", "E8EF")
        A("cmd:logic", "Logic: values, bindings, rules, states", "View", "E945", "Ctrl+2")
        A("cmd:steps", "Steps: a piece of code as a flowchart", "View", "E8FD", "Ctrl+3")
        A("cmd:app", "App: the windows, the files, how it starts and is built", "View", "E7B8", "Ctrl+6")
        A("cmd:look", "Look: themes -- this design's, the built-in ones, your own", "View", "E790", "Ctrl+7")
        A("cmd:map", "Map: the whole program -- what starts things, what they do, what they touch", "View", "E81E", "Ctrl+5")
        A("cmd:back", "Go back", "View", "E72B", "Alt+Left")
        A("cmd:forward", "Go forward", "View", "E72A", "Alt+Right")
        A("cmd:taborder", "Tab order: set it on the canvas", "Design", "E8CB")
        A("cmd:design", "Design: the canvas", "View", "E7C4", "Ctrl+1")
        A("cmd:panel", "Show or hide the bottom panel", "View", "E8A0", "Ctrl+J")
        A("cmd:add", "Add anything...", "Add", "E710", "Ctrl+I")
        A("cmd:export", "Export the script", "File", "E7C3", "Ctrl+E")
        A("cmd:exportas", "Export the script as...", "File", "E7C3")
        A("cmd:tsv", "Export the node table", "File", "E9D9")
        A("cmd:undo", "Undo", "Edit", "E7A7", "Ctrl+Z")
        A("cmd:redo", "Redo", "Edit", "E7A6", "Ctrl+Y")
        A("cmd:dup", "Duplicate the selection", "Edit", "E8C8", "Ctrl+D")
        A("cmd:del", "Delete the selection", "Edit", "E74D", "Del")
        A("cmd:selall", "Select everything on this page", "Edit", "E8B3", "Ctrl+A")
        A("cmd:group", "Put the selection in a box...", "Arrange", "E8B0")
        A("cmd:align", "Align the selection...", "Arrange", "E8E4")
        A("cmd:row", "A row of controls...", "Wizards", "E8FD")
        A("cmd:grid", "A grid of controls...", "Wizards", "F0E2")
        A("cmd:spacing", "Spacing, margins and padding...", "Wizards", "E799")
        A("cmd:hotkey", "Add a hotkey...", "Wizards", "E765")
        A("cmd:dialog", "Add a dialog...", "Wizards", "E946")
        A("cmd:menu", "Add a menu...", "Wizards", "E700")
        A("cmd:bind", "Bind a control to a value...", "Wizards", "E8C8")
        A("cmd:flow", "Add a rule, without writing code...", "Wizards", "E945")
        A("cmd:state", "Add a state...", "Wizards", "E81E")
        A("cmd:snip", "Insert a snippet...", "Wizards", "E943")
        A("cmd:mysnips", "Your snippets...", "Wizards", "E8A5")
        A("cmd:keepsnip", "Keep what is being edited as a snippet...", "Wizards", "E8A5")
        A("cmd:test", "Try the design out, here", "Run", "E7C4", "F6")
        A("cmd:run", "Run it", "Run", "E768", "F5")
        A("cmd:stop", "Stop it", "Run", "E71A")
        A("cmd:live", "Re-run after every change", "Run", "E895")
        A("cmd:check", "Check every handler", "Run", "E930")
        A("cmd:code", "Code: the code editor", "View", "E943", "Ctrl+4")
        A("cmd:foldleft", "Hide or show the Toolbox and Outline", "View", "E8A1", "Ctrl+B")
        A("cmd:foldright", "Hide or show the inspector", "View", "E89F", "Ctrl+Shift+B")
        A("cmd:init", "Edit the startup code", "View", "E943")
        A("cmd:script", "Edit your own functions", "View", "E943")
        A("cmd:gen", "Show the whole generated script", "View", "E943")
        A("cmd:lint", "Show the problems", "View", "E7BA")
        A("cmd:packs", "Show the component packs", "View", "E8F1")
        A("cmd:install", "Install a component...", "File", "E896")
        A("cmd:out", "Show what the preview said", "View", "E756")
        A("cmd:designgrid", "Show or hide the design grid", "View", "E80A")
        A("cmd:snapopt", "Snap to the grid", "View", "E8B0")
        A("cmd:guides", "Alignment guides", "View", "E809")
        A("cmd:ui.dark", "The studio in dark", "View", "E708")
        A("cmd:ui.light", "The studio in light", "View", "E706")
        A("cmd:win.window", "Add a window", "Windows", "E7C4")
        A("cmd:win.dialog", "Add a dialog window", "Windows", "E8BD")
        A("cmd:win.tool", "Add a tool window", "Windows", "E90F")
        A("cmd:win.rename", "Rename this window...", "Windows", "E8AC")
        A("cmd:win.dup", "Duplicate this window", "Windows", "E8C8")
        A("cmd:win.del", "Delete this window", "Windows", "E74D")
        A("cmd:win.link", "Open this window from...", "Windows", "E71B")
        A("cmd:page.add", "Add a page", "Pages", "E710")
        for cat in AxCat.Cats
            for e in AxCat.InCat(cat)
                A("new:" e.T, "Add " (RegExMatch(e.Label, "i)^[aeiou]") ? "an " : "a ") e.Label,
                  "Insert " cat, e.Icon)
        ; ---- the places, which Ctrl+P alone searches
        P := (id, label, group, icon) => (
            out.Push(Map("id", id, "label", label, "group", group, "icon", icon, "key", "", "go", 1)))
        for t in AxTpl.All
            A("tpl:" t.Id, "New project from " t.Name, "File", "E710")
        for i, path in this.Recent
            A("recent:" i, "Open " AxStudio.Short(path), "Open recent", "E8E5")
        for i, w in this.P.Wins {
            P("win:" i, w.Name, w.Kind = "main" ? "window" : w.Kind, AxPanes.WinIcon(w.Kind))
            this.P.Walk(w.Root, this.PalFn(P, w))
        }
        return out
    }
    ; The window is bound as a parameter rather than captured from the loop:
    ; a closure in AutoHotkey v2 does not see a for-loop control variable.
    PalFn(P, w) => (n) => (this.PalNode(P, w, n), false)
    PalNode(P, w, n) {
        e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
        ico := (n.Type = "Page") ? (n.Prop("icon") != "" ? n.Prop("icon") : "E80F")
             : (IsObject(e) ? e.Icon : "E7C3")
        P("node:" n.Id, n.Label, w.Name " . " n.Type, ico)
    }
    RunCommand(id) {
        return this.Try(id, (*) => this.RunCommandDo(id))
    }
    RunCommandDo(id) {
        kind := SubStr(id, 1, InStr(id, ":") - 1)
        arg := SubStr(id, InStr(id, ":") + 1)
        if (kind = "new")
            return this.Insert(arg)
        if (kind = "win")
            return this.SwitchWin(Integer(arg))
        if (kind = "node")
            return this.GoToNode(arg)
        if (kind = "tpl")
            return this.NewProject(arg)
        if (kind = "recent") {
            i := Integer(arg)
            if (i >= 1 && i <= this.Recent.Length && this.ConfirmDiscard())
                this.LoadFile(this.Recent[i])
            return
        }
        switch arg {
        case "save":       return this.Save()
        case "saveas":     return this.SaveAs()
        case "open":       return this.Open()
        case "import":     return this.ImportScript()
        case "layrows", "layfixed":
            if !AxLayout.Has(this.P.W)
                return
            this.Mark()
            AxLayout.Switch(this.P.W, arg = "layrows" ? "rows" : "fixed")
            this.Refresh()
            return this.Status("msg", arg = "layrows" ? "In rows that resize with the window." : "Back where the script put everything.")
        case "welcome":    return AxWiz.Welcome(this)
        case "template":   return (this.ConfirmDiscard() ? AxWiz.Template(this) : "")
        case "settings":   return AxWiz.Settings(this)
        case "helper":     return AxHelp.Pick(this)
        case "data":       return AxData.Wizard(this, this.Primary())
        case "file":       return AxWiz.AddFile(this)
        case "include":    return AxWiz.AddInclude(this)
        case "arg":        return AxWiz.AddArg(this)
        case "mode":       return AxWiz.AddMode(this)
        case "tray":       return AxWiz.Tray(this)
        case "compile":    return AxWiz.Compile(this)
        case "build":      return AxWiz.Build(this)
        case "value":      return this.ValueWizard()
        case "logic":      return this.SetWs("logic")
        case "app":        return this.SetWs("app")
        case "look":       return this.SetWs("look")
        case "map":        return this.SetWs("map")
        case "steps":      return this.SetWs("steps")
        case "back":       return this.NavStep(-1)
        case "forward":    return this.NavStep(1)
        case "taborder":   return this.ToggleTabOrder(true)
        case "design":     return this.SetWs("design")
        case "panel":      return this.TogglePanel()
        case "add":        return AxGallery.Open(this)
        case "export":     return this.Export()
        case "exportas":   return this.Export(true)
        case "tsv":        return this.ExportTsv()
        case "undo":       return this.DoUndo()
        case "redo":       return this.DoRedo()
        case "dup":        return this.DuplicateSel()
        case "del":        return this.DeleteSel()
        case "selall":     return this.SelectAll()
        case "group":      return this.GroupMenu()
        case "align":      return this.AlignMenu()
        case "row":        return this.RowWizard()
        case "grid":       return this.GridWizard()
        case "spacing":    return this.SpacingWizard()
        case "hotkey":     return this.HotkeyWizard()
        case "dialog":     return this.DialogWizard()
        case "menu":       return this.MenuWizard()
        case "bind":       return this.BindWizard()
        case "flow":       return this.FlowWizard()
        case "state":      return this.StateWizard()
        case "snip":       return this.SnippetMenu()
        case "mysnips":    return AxSnips.Manage(this)
        case "keepsnip":   return AxSnips.FromEditor(this)
        case "test":       return this.ToggleTest()
        case "run":        return this.Preview()
        case "stop":       return this.StopPreview()
        case "live":       return (this.Live := !this.Live, this.Bar(),
                                   this.Live ? this.Preview() : this.StopPreview())
        case "check":      return this.CheckAll()
        case "code":       return this.SetMid("code")
        case "canvas":     return this.SetMid("canvas")
        case "foldleft":   return this.TogglePane("L")
        case "foldright":  return this.TogglePane("R")
        case "init":       return this.EditScript("init")
        case "script":     return this.EditScript("script")
        case "gen":        return this.ShowGenerated()
        case "lint":       return this.SetMid("lint")
        case "packs":      return this.GoSec("packs", "app")
        case "install":    return this.InstallPack()
        case "out":        return this.SetMid("out")
        case "designgrid": return (this.ShowGrid := !this.ShowGrid, this.SaveSettings(), this.Refresh())
        case "snapopt":    return (this.Snap := !this.Snap, this.SaveSettings(), this.Bar(), this.PushOpts())
        case "guides":     return (this.Guides := !this.Guides, this.SaveSettings(), this.Bar(), this.PushOpts())
        case "ui.dark":    return this.SetUi("dark")
        case "ui.light":   return this.SetUi("light")
        case "win.window": return this.NewWindow("window")
        case "win.dialog": return this.NewWindow("dialog")
        case "win.tool":   return this.NewWindow("tool")
        case "win.rename": return this.RenameWin()
        case "win.dup":    return this.DuplicateWin()
        case "win.del":    return this.DeleteWin()
        case "win.link":   return this.LinkWizard()
        case "page.add":   return this.AddNewPage()
        }
        this.WriteLog("palette: nothing does " id)
    }
    ; The prerendered body, when the project asks for one. Off unless the
    ; compile settings say otherwise, because it is a copy of the markup and a
    ; copy that goes stale is worse than a build that takes a moment.
    PreBody() {
        cfg := AxAsset.Compile(this.P)
        if !(cfg.Has("prerender") && AxAsset.Truthy(cfg["prerender"]))
            return ""
        return AxPre.Region(this, this.P)
    }

    ; The script that is on disk for the running process. Read rather than
    ; regenerated: the design may well have moved on since it started, and the
    ; line number in an error belongs to the file that threw it.
    LastCode() {
        try return FileRead(this.ScriptPath(), "UTF-8")
        return ""
    }
    ; A function in the generated script -> the thing in the design that wrote
    ; it. Handlers are <control>_<Event>, rules are Flow_<control>_<Event>,
    ; startup code is <window>Init, and a state is <window>State.
    GoToHandler(fn) {
        if (fn = "")
            return this.ShowGenerated()
        for w in this.P.Wins {
            if (fn = AxGen.InitFn(w)) {
                this.SwitchWin(this.P.WinIndex(w))
                return this.EditScript("init")
            }
            if (fn = AxFlow.StateFn(w)) {
                this.SwitchWin(this.P.WinIndex(w))
                return this.GoSec("states", "logic")
            }
        }
        ; Flow_<control>_<Event>[_<which>]: a control's name can hold an
        ; underscore too, so each place one could end is tried
        if (SubStr(fn, 1, 5) = "Flow_") {
            rest := SubStr(fn, 6), pos := 0
            while (pos := InStr(rest, "_", , pos + 1)) {
                n := this.P.FindByName(SubStr(rest, 1, pos - 1))
                if IsObject(n) {
                    this.GoToNode(n.Id)
                    return this.GoSec("rules", "logic")
                }
            }
        }
        found := {N: "", I: 0}
        for w in this.P.Wins
            this.P.Walk(w.Root, this.HandlerFn(fn, found))
        if IsObject(found.N) {
            this.GoToNode(found.N.Id)
            return this.EditEvent(found.N, found.I, "code")
        }
        this.ShowGenerated()
        this.Status("msg", "That came from " fn "(), which is in the generated script.")
    }
    HandlerFn(fn, found) => (n) => this.MatchHandler(n, fn, found)
    MatchHandler(n, fn, found) {
        for i, e in n.Ev
            if (AxGen.HandlerName(n, e["name"]) = fn) {
                found.N := n, found.I := i
                return true
            }
        return false
    }

    ; Go to a control wherever it is, including in another window.
    GoToNode(id) {
        n := this.P.Find(id)
        if !IsObject(n)
            return
        w := this.P.WinOf(n)
        if IsObject(w) {
            wi := this.P.WinIndex(w)
            if (wi && wi != this.P.Cur)
                this.P.Cur := wi, this.PageId := ""
        }
        pg := this.P.PageOf(n)
        if IsObject(pg)
            this.PageId := pg.Id
        this.SelIds := [(n.Type = "Page") ? "" : n.Id]
        if (n.Type = "Page")
            this.PageId := n.Id, this.SelIds := []
        this.RightTab := (n.Type = "Page") ? "page" : "props"
        this.GoWs("design")
        this.Refresh()
        this.Status("msg", "Went to " n.Label ".")
    }

    ; A finding names a window and usually a control. Clicking it goes there:
    ; switching windows if it has to, then selecting the control and putting
    ; the properties back in front, which is where the fix is made.
    GoToIssue(i) {
        if (i < 1 || i > this.Issues.Length)
            return
        f := this.Issues[i]
        if IsObject(f.Win) {
            wi := this.P.WinIndex(f.Win)
            if (wi && wi != this.P.Cur) {
                this.P.Cur := wi
                this.SelIds := [], this.PageId := ""
            }
        }
        if IsObject(f.Node) {
            pg := this.P.PageOf(f.Node)
            if IsObject(pg)
                this.PageId := pg.Id
            this.SelIds := [f.Node.Id]
            this.RightTab := "props"
        } else
            this.SelIds := [], this.RightTab := "page"
        this.GoWs("design")
        this.Refresh()
        this.Status("msg", f.Msg)
    }

    ; =====================================================================
    ;  Windows
    ; =====================================================================
    ; The canvas shows one window at a time, so switching is a whole reload of
    ; the surface: the selection and the current page belong to the window
    ; that was on screen and mean nothing in the next one.
    SwitchWin(i) {
        if (i < 1 || i > this.P.Wins.Length || i = this.P.Cur)
            return
        this.P.Cur := i
        this.SelIds := [], this.PageId := "", this.CodeTarget := ""
        this.SetEditor("", false)
        this.Refresh()
        this.PushCompletions()
        this.Status("msg", "Editing " this.P.W.Name ".")
    }
    SwitchWinFn(i) => (*) => this.SwitchWin(i)

    ; ------------------------------------------------ the window strip
    ; Every window in the project as a tab above the canvas: the one being
    ; edited in front, and a tab at the end that adds another. It replaces the
    ; Windows tab, the picker on the toolbar and most of the Window menu --
    ; three ways to do one thing, none of them where you were looking.
    WinStrip() {
        h := ""
        for i, w in this.P.Wins {
            kind := (w.Kind = "main") ? "the main window" : (w.Kind = "dialog") ? "a dialog"
                  : (w.Kind = "tool") ? "a tool window" : "a window"
            h .= '<div class="axd-wtab' (i = this.P.Cur ? " on" : "") '" data-wtab="' i '"'
              .  ' data-tip="' AxTags.E(w.Name ", " kind ". Double-click to rename, "
                                       . "right-click for more.") '">'
              .  '<span class="ico">&#x' AxPanes.WinIcon(w.Kind) ';</span>' AxTags.E(w.Name) '</div>'
        }
        h .= '<div class="axd-wtab axd-wadd" data-wtab="add"'
          .  ' data-tip="Add a window, a dialog or a tool window">'
          .  '<span class="ico">&#xE710;</span>Window</div>'
        this.Html("axdWinStrip", h)
    }
    StripClick(ev) {
        v := this.UpAttr(ev.srcElement, "data-wtab")
        if (v = "add")
            return this.ShowMenu(this.AddWindowItems())
        if (v != "")
            this.SwitchWin(Integer(v))
    }
    StripDbl(ev) {
        v := this.UpAttr(ev.srcElement, "data-wtab")
        if (v = "" || v = "add")
            return
        this.SwitchWin(Integer(v))
        this.RenameWin()
    }
    StripMenu(ev) {
        v := this.UpAttr(ev.srcElement, "data-wtab")
        if (v = "")
            return
        if (v = "add")
            return this.DeferMenu(this.AddWindowItems(), ev)
        this.SwitchWin(Integer(v))
        this.DeferMenu(this.WinActionItems(), ev)
    }
    AddWindowItems() {
        return [{Label: "A &window", Icon: "E7C4", Click: (*) => this.NewWindow("window")},
                {Label: "A &dialog", Icon: "E8BD", Click: (*) => this.NewWindow("dialog")},
                {Label: "A &tool window", Icon: "E90F", Click: (*) => this.NewWindow("tool")}]
    }
    WinActionItems() {
        return [{Label: "&Rename...", Click: (*) => this.RenameWin()},
                {Label: "D&uplicate", Click: (*) => this.DuplicateWin()},
                {Label: "&Open it from...", Click: (*) => this.LinkWizard()},
                {Label: "Its &settings", Click: (*) => this.ShowWinSettings()},
                "-",
                {Label: "&Delete", Click: (*) => this.DeleteWin()}]
    }
    ; A window's card, double-clicked: go and design it.
    AppDbl(ev) {
        v := this.UpAttr(ev.srcElement, "data-win")
        if (v = "")
            return
        this.SwitchWin(Integer(v))
        this.SetWs("design")
    }
    ShowWinSettings() {
        this.SelIds := []
        this.RightTab := "page"
        this.GoWs("design")
        this.Reflect(true)
    }

    ; ------------------------------------------------ the inspector's header
    ; What the inspector is showing, as a path you can walk back up: the
    ; window, each container, then the control. With nothing selected it is
    ; the window itself -- whose settings are what the Window tab held.
    RightHead() {
        if (this.RightTab = "icons" || this.RightTab = "pack")
            return '<span class="axd-rcrumb" data-crumb="back"><span class="ico">&#xE72B;</span>Back</span>'
                 . '<span class="axd-rnote">' (this.RightTab = "icons" ? "choosing an icon"
                                                                       : "a component") '</span>'
        w := this.P.W
        nodes := this.SelNodes()
        n := nodes.Length ? nodes[nodes.Length] : ""
        h := '<span class="axd-rcrumb' (IsObject(n) ? "" : " on") '" data-crumb="win"'
           . ' data-tip="The window: its title, size, look and bars">'
           . '<span class="ico">&#x' AxPanes.WinIcon(w.Kind) ';</span>' AxTags.E(w.Name) '</span>'
        if !IsObject(n)
            return h '<span class="axd-rnote">window settings</span>'
        sep := '<span class="ico axd-rsep">&#xE76C;</span>'
        if (nodes.Length > 1)
            return h sep '<b>' nodes.Length ' controls</b>'
        path := []
        p := n.Parent
        while (IsObject(p) && p.Type != "Root") {
            path.InsertAt(1, p)
            p := p.Parent
        }
        for x in path
            h .= sep '<span class="axd-rcrumb" data-crumb="' x.Id '">' AxTags.E(x.Label) '</span>'
        return h sep '<b>' AxTags.E(n.Label) '</b>'
    }
    RightHeadClick(ev) {
        v := this.UpAttr(ev.srcElement, "data-crumb")
        if (v = "")
            return
        if (v = "back")
            return this.QuickAction(this.RightTab = "icons" ? "icon.back" : "pack.back")
        if (v = "win")
            return this.ShowWinSettings()
        n := this.P.Find(v)
        if !IsObject(n)
            return
        if (n.Type = "Page")
            return this.GoToNode(v)
        this.SetSel(v)
    }
    WinAction(act) {
        if (SubStr(act, 1, 7) = "design.") {
            this.SwitchWin(Integer(SubStr(act, 8)))
            return this.SetWs("design")
        }
        switch act {
        case "pack.install": return this.InstallPack()
        case "pack.folder":  return this.OpenPackFolder()
        case "add.window": return this.NewWindow("window")
        case "add.dialog": return this.NewWindow("dialog")
        case "add.tool":   return this.NewWindow("tool")
        case "rename":     return this.RenameWin()
        case "dup":        return this.DuplicateWin()
        case "del":        return this.DeleteWin()
        case "link":       return this.LinkWizard()
        case "design":     return this.SetWs("design")
        }
    }
    ; ------------------------------------------------------- components
    ShowComponent(type) {
        this.PackShown := type
        this.RightTab := "pack"
        if (this.Ws != "design")
            return this.SetWs("design")
        this.Reflect(false)
    }
    ; A pack is a folder with a manifest in it, so a .zip of one is the whole
    ; distribution format. Nothing in it is run -- it is unpacked, checked and
    ; copied, and only then read.
    InstallPack() {
        f := FileSelect(3, , "Choose a component pack", "Component pack (*.zip)")
        if (f = "")
            return
        r := AxStore.Install(f, AxStudioPaths.Lib "\components")
        if !r.Ok
            return this.Alert(r.Msg, "Install a component")
        AxComp.Scan(AxStudioPaths.Lib)
        AxComp.WriteAll(AxStudioPaths.Lib "\components\_all.ahk",
                        AxStudioPaths.Lib "\components")
        this.GoWs("app")
        this.Refresh()
        this.Alert(r.Msg, "Installed")
    }
    OpenPackFolder() {
        d := AxStudioPaths.Lib "\components"
        try DirCreate(d)
        try Run('explorer.exe "' d '"')
    }

    ; Adding a window asks what kind, how big, and -- the part that used to be
    ; forgotten every time -- what opens it. See AxWiz.NewWindow.
    NewWindow(kind := "") {
        this.SetEditor("", false)
        AxWiz.NewWindow(this, kind)
    }
    RenameWin() {
        w := this.P.W
        v := AxForm.Ask(this, "Rename this window", "Called", w.Name,
            {Icon: "E8AC",
             Intro: "The name becomes part of a function name in the generated script: "
                  . "Show<name>() is what builds and shows it.",
             Hint: "Letters, digits and underscores. Anything else is dropped.",
             Check: (V) => (Trim(V["a"]) != "" && AxProject.CleanName(V["a"]) = "")
                         ? "That leaves nothing usable." : ""})
        if (v = "" || v = w.Name)
            return
        this.Mark()
        AxPanes.SetWinName(this, v)
        this.Refresh()
        this.PushCompletions()
    }
    DuplicateWin() {
        this.Mark()
        src := this.P.W
        copy := AxWin.FromMap(src.ToMap())
        copy.Name := this.P.UniqueWinName(src.Name)
        copy.Kind := (src.Kind = "main") ? "window" : src.Kind
        copy.Root.Id := "root"
        this.P.Wins.Push(copy)
        ; the copy's controls carry the originals' ids and names, and both are
        ; unique project-wide -- so every one of them is renumbered
        for k in copy.Root.Kids
            this.P.Renumber(k)
        this.P.Cur := this.P.Wins.Length
        this.SelIds := [], this.PageId := "", this.CodeTarget := ""
        this.SetEditor("", false)
        this.Refresh()
        this.PushCompletions()
        this.Status("msg", "Copied to " copy.Name ".")
    }
    DeleteWin() {
        w := this.P.W
        if (this.P.Wins.Length < 2)
            return this.Alert("A project needs at least one window.", "Delete window")
        if (w.Kind = "main")
            return this.Alert("This is the main window -- the one the script opens with."
                            . "`n`nMake another window the main one first, under This window"
                            . " on the Window tab.", "Delete window")
        who := ""
        for l in this.P.Links()
            if (l.To = w.Name)
                who .= (who = "" ? "" : ", ") l.From
        if !this.Confirm("Delete " w.Name " and everything in it?"
                       . (who != "" ? "`n`n" who " still calls " AxGen.Fn(w) "()." : ""),
                         "Delete window", "Delete", "Keep it", "warning")
            return
        this.Mark()
        this.P.RemoveWin(w)
        this.SelIds := [], this.PageId := "", this.CodeTarget := ""
        this.SetEditor("", false)
        this.Refresh()
        this.PushCompletions()
        this.Status("msg", "Deleted " w.Name ".")
    }
    ; Renaming a window renames the function every other window calls to open
    ; it, so the calls are rewritten too rather than quietly going stale.
    RenameWinRefs(old, new) {
        if (old = "" || old = new)
            return
        a := "Show" AxProject.CleanName(old), b := "Show" AxProject.CleanName(new)
        oldOut := AxProject.CleanName(old) "Result", newOut := AxProject.CleanName(new) "Result"
        fix := (t) => RegExReplace(RegExReplace(String(t), "i)\b" a "\b", b), "i)\b" oldOut "\b", newOut)
        walk := this.FixFn(fix)
        for w in this.P.Wins {
            w.Init := fix(w.Init), w.Script := fix(w.Script)
            this.P.Walk(w.Root, walk)
        }
    }
    FixFn(fix) => (n) => (this.FixEvRefs(n, fix), false)
    FixEvRefs(n, fix) {
        for e in n.Ev
            e["code"] := fix(e["code"])
    }

    ; One control opens one window. Offered from the Windows pane because that
    ; is where you notice a window nothing reaches -- see AxWiz.Link, which
    ; asks in one form and can write it either as a rule or as real code.
    LinkWizard() => AxWiz.Link(this)

    ; Errors found by AxLint mean the script will not run, or will not do what
    ; the design says. Better to be told here, by name, than by the interpreter
    ; after the file has already been written.
    LintGate() {
        bad := []
        for f in AxLint.Run(this.P)
            if (f.Sev = "error")
                bad.Push(f)
        if !bad.Length
            return true
        list := ""
        for i, f in bad {
            if (i > 5) {
                list .= "`n    ... and " (bad.Length - 5) " more"
                break
            }
            list .= "`n    " f.Msg
        }
        r := this.Dialog((bad.Length = 1 ? "One thing" : bad.Length " things")
            . " in this design will stop the script working:`n" list
            . "`n`nThe Problems tab has all of them, and clicking one goes there.",
            "Before exporting", ["Show me", "Export anyway", "Cancel"],
            {Kind: "warning", Cancel: 3})
        if (r.Button = "Show me") {
            this.SetMid("lint")
            return false
        }
        return r.Button = "Export anyway"
    }

    ; Where a re-export goes without asking: the script this project was last
    ; written to, or the one beside it that names it.
    ExportTarget() {
        if (this.P.ExportedTo != "")
            return this.P.ExportedTo
        if (this.P.Path = "")
            return ""
        cand := RegExReplace(this.P.Path, "i)\.axs\.json$|\.json$", "") ".ahk"
        if (FileExist(cand) && AxMerge.RefPath(cand) = this.P.Path)
            return cand
        return ""
    }

    ; A script with nothing beside it is a script that cannot be reopened, so
    ; an unsaved project is saved next to the one being written.
    SaveBeside(scriptPath) {
        proj := RegExReplace(scriptPath, "i)\.ahk$", "") ".axs.json"
        if FileExist(proj) {
            if !this.Confirm("The project has not been saved, and the script needs one to point at."
                           . "`n`nThere is already a file at`n`n    " AxStudio.Short(proj)
                           . "`n`nOverwrite it with this project?",
                             "Export", "Overwrite", "Choose another...", "warning")
                return this.SaveAs()
        }
        return this.SaveTo(proj)
    }

    ; Code the .ahk has that the project has not: someone edited a generated
    ; block. Offer to take it back rather than quietly writing over it, which
    ; is the whole difference between a designer you can keep using and one
    ; you abandon the first time you touch the output.
    PullBack(text, path, onOpen := false) {
        ch := AxMerge.Diff(this.P, text)
        if !ch.Length
            return true
        list := ""
        for i, c in ch {
            if (i > 6) {
                list .= "`n    ... and " (ch.Length - 6) " more"
                break
            }
            list .= "`n    " c.Label
        }
        many := ch.Length > 1
        msg := (many ? ch.Length " blocks of code in" : "A block of code in")
             . "`n`n    " AxStudio.Short(path)
             . "`n`n" (many ? "differ" : "differs") " from the project:`n" list
             . "`n`n" (onOpen ? "Take the file's version?"
                              : "Take " (many ? "them" : "it") " into the project, or write over "
                                (many ? "them" : "it") "?")
        b := onOpen ? ["Take them", "Leave them"] : ["Take them", "Write over them", "Cancel"]
        r := this.Dialog(msg, "The script has been edited", b, {Kind: "question", Cancel: b.Length})
        if (r.Button = "Cancel" || r.Button = "")
            return false
        if (r.Button = "Take them") {
            AxMerge.Apply(this.P, ch)
            this.P.Dirty := true
            this.Refresh()
            this.PushCompletions()
            this.SaveState("Took " ch.Length " edit" (many ? "s" : "") " from the script")
            this.Status("msg", "Took " ch.Length " edit" (many ? "s" : "") " back from " AxStudio.Short(path))
        }
        return true
    }
    ExportTsv() {
        def := this.P.Path != "" ? RegExReplace(this.P.Path, "\.axs\.json$|\.json$", ".tsv")
                                 : A_MyDocuments "\" AxStudio.SafeName(this.P.Title) ".tsv"
        f := FileSelect("S18", def, "Export the node table", "Tab separated (*.tsv)")
        if (f = "")
            return
        try {
            if FileExist(f)
                FileDelete(f)
            FileAppend(AxGen.Tsv(this.P), f, "UTF-8-RAW")
            this.Status("msg", "Wrote " f)
        } catch as e
            this.Alert("Could not write the table:`n" e.Message, "Export")
    }
    static SafeName(s) {
        s := Trim(RegExReplace(String(s), "[^A-Za-z0-9 _\-]"))
        return s != "" ? s : "Untitled"
    }

    ; ------------------------------------------------------------ preview
    ScriptPath() => this.Store "\preview.ahk"
    Preview(live := false) {
        this.CodeTyped()
        ; It opens the way the program itself will -- its own size, its own
        ; start (maximised, minimised, where it says) -- unless Settings asks
        ; for where the last run was. A Live re-run replaces a window that is
        ; already up, so it keeps that window's place, never its size. A
        ; design that starts maximised or minimised is never moved at all.
        how := this.PreviewOpens
        if (live && how = "design")
            how := "place"
        st := this.P.Main().StartState
        if (st = "max" || st = "min" || !(this.RunW > 0))
            how := "design"
        dbg := {Log: this.Store "\preview.log",
                X: (how != "design") ? this.RunX : 0, Y: (how != "design") ? this.RunY : 0,
                W: (how = "last") ? this.RunW : 0, H: (how = "last") ? this.RunH : 0,
                At: (how = "place"), Page: (how = "last") ? this.RunPage : ""}
        code := AxGen.Script(this.P, this.ScriptPath(), dbg, this.PreBody())
        ; Is this the same script that is already running? Only Live asks.
        ; Live fires on its own and should not take down the window you are
        ; using because of a change that did not reach the script. Pressing Run
        ; is different: Run means run. Refusing there is indistinguishable from
        ; being broken, especially since a preview process can outlive its
        ; window -- close a window whose script never calls ExitApp and the
        ; process is still there, and the guard holds for the rest of the
        ; session.
        ;
        ; The debug block carries the last window position, which changes every
        ; time, so the comparison is against the script WITHOUT it -- the part
        ; that decides what the program does.
        bare := AxGen.Script(this.P, this.ScriptPath(), "", this.PreBody())
        if (live && bare = this._ranCode && this.PreviewPid
            && ProcessExist(this.PreviewPid)) {
            this.Status("msg", "Live: the script has not changed.")
            return
        }
        r := AxStudio.Validate(code, this.ScriptPath())
        if (r.Ok && r.Warn != "")
            this.Say("error", "It runs, but AutoHotkey warns: " r.Warn)
        if !r.Ok {
            ; Problems is a full-size view now, so the message has somewhere
            ; to be read rather than needing a dialog to carry it.
            b := this.RunBlock := AxStudio.BlockOf(r.Msg, code)
            this.WriteLog("check said: " r.Msg)
            this.Problem("Will not run: " b.Msg (b.Fn != "" ? "  -- in " b.Fn "(), see Problems" : "  -- see Problems"))
            this.SetMid("lint")
            return
        }
        this.RunBlock := ""
        ; the probe is one window that closes itself: it checks, never starts
        if AxStudio.Probing
            return this.Status("msg", "It would run (the probe starts nothing).")
        this.StopPreview()
        p := this.ScriptPath()
        try {
            if FileExist(p)
                FileDelete(p)
            FileAppend(code, p, "UTF-8-RAW")
            ; the files on App > Files beside it, as they will be beside the exe
            try AxFilesUi.Stage(this, this.Store)
            ; a fresh log, so what is read back belongs to this run
            try FileDelete(dbg.Log)
            this.LogPos := 0
            this.Out := []
            Run('"' A_AhkPath '" "' p '"', this.Store, , &pid)
            this.PreviewPid := pid
            this._ranCode := bare
            SetTimer(this._tailFn, 250)
            this.Status("msg", "Running (pid " pid ").")
        } catch as e
            this.Problem("Could not start it: " e.Message)
    }
    ; The canvas is not a picture of the design: it is the design, built by the
    ; library, in the control the app will use. So there is a third thing
    ; between editing and running it -- stop intercepting the pointer, and the
    ; controls on the canvas are just controls. No process, no export, no wait.
    ToggleTest(on := "") {
        if (this.Ws != "design")
            this.SetWs("design")
        this.Testing := (on = "") ? !this.Testing : (on ? true : false)
        if this.Testing
            this.SelIds := []
        this.Send({cmd: "test", on: this.Testing ? 1 : 0})
        this.Bar()
        this.Reflect(false)
        this.Status("msg", this.Testing
            ? "Trying it out. The canvas is live -- F6 to go back to editing."
            : "Back to editing.")
    }

    ; Only ever the process this studio started: nothing here goes looking for
    ; AutoHotkey windows to close.
    ; ------------------------------------------------------------ the log
    ; What the running preview has said since the last tick. See
    ; AxStudio.Debug.ahk for what it says and why it is a file.
    ; Runs on a timer, so nothing in here may raise: an unhandled error on a
    ; timer thread is a dialog the user did not ask for, over and over.
    TailLog() {
        if this.Closing
            return
        try this._Tail()
        catch as e
            this.Problem("Reading the preview log: " e.Message)
    }
    _Tail() {
        r := AxDbg.Read(this.Store "\preview.log", this.LogPos)
        this.LogPos := r.At
        touched := false
        for line in r.Lines
            touched := this.LogLine(line) || touched
        if touched
            this.RenderPanel()
        if (this.PreviewPid && !ProcessExist(this.PreviewPid))
            SetTimer(this._tailFn, 0), this.PreviewPid := 0
    }
    LogLine(line) {
        switch line.Kind {
        case "pick":
            ; you clicked a control in the running window: go to it here
            n := this.P.FindByName(line.Text)
            if IsObject(n) {
                this.GoToNode(n.Id)
                return false
            }
        case "pos":
            p := StrSplit(Trim(line.Text), " ")
            if (p.Length >= 4) {
                this.RunX := p[1], this.RunY := p[2], this.RunW := p[3], this.RunH := p[4]
                this.RunPage := (p.Length >= 5) ? p[5] : ""
                this.SaveSettings()
            }
            return false
        case "error":
            ; where in the generated script, and therefore whose handler
            line.Fn := AxDbg.Locate(this.LastCode(), AxDbg.LineOf(line.Text))
            this.Problem("In the preview: " line.Text)
            this.SetMid("out")
        }
        this.Out.Push(line)
        if (this.Out.Length > 400)
            this.Out.RemoveAt(1)
        return true                        ; the count on the tab changed, at least
    }
    ; --------------------------------------- bindings, rules and states
    ; All three used to be a menu of controls, then a menu of events, then a
    ; menu of verbs, then a prompt reading "One of: a, b, c" -- four windows
    ; deep before the first thing you typed. They are one form each now, in
    ; AxStudio.Wizards.ahk, with the answers alongside each other and the line
    ; they will write shown underneath as you fill them in.
    ; each shows the section it adds to, wherever it was started from
    ValueWizard() => (this.LogicSec := "values", AxWiz.Value(this))
    BindWizard() => (this.LogicSec := "bindings", AxWiz.Bind(this))
    FlowWizard() => (this.LogicSec := "rules", AxWiz.Flow(this))
    StateWizard() => (this.LogicSec := "states", AxWiz.State(this))

    NamedIn(w) {
        out := []
        this.P.Walk(w.Root, AxStudio.NamedFn(out))
        return out
    }
    static NamedFn(out) => (n) => (n.Type != "Page" && Trim(n.Name) != "" ? out.Push(n) : "", false)
    CtlNames() {
        out := []
        for n in this.NamedIn(this.P.W)
            out.Push(n.Name)
        return out
    }
    WinNames() {
        out := []
        for w in this.P.Wins
            if (w.Kind != "main")
                out.Push(w.Name)
        return out
    }
    PageNames() {
        out := []
        for p in this.P.Pages()
            out.Push(p.Name)
        return out
    }

    ; Fills the tokens from what the chosen sheet already looks like, so the
    ; first colour you change does not drag every other one off with it.
    SeedLook() {
        this.Mark()
        w := this.P.W
        for k, v in AxTheme.Suggest(w)
            AxTheme.Set(w, k, v)
        this.AfterLook()
        this.Status("msg", "Filled the tokens from the current look.")
    }
    ClearLook() {
        this.Mark()
        this.P.W.Look := "", this.P.W.Css := ""
        this.AfterLook()
        this.Status("msg", "Back to the stylesheet on its own.")
    }
    ; A line for the Output tab from the studio itself rather than from a
    ; running preview -- what the compiler said, mostly. Straight into the
    ; list: LogLine is the debug agent's path and does other things on the way.
    Say(kind, text) {
        this.Out.Push({Kind: kind, Text: text})
        if (this.Out.Length > 400)
            this.Out.RemoveAt(1)
        this.RenderPanel()
    }
    ClearOut() {
        this.Out := []
        this.Reflect(false)
    }
    StopPreview() {
        SetTimer(this._tailFn, 0)
        this._ranCode := ""            ; nothing is running it now
        if !this.PreviewPid
            return
        try if ProcessExist(this.PreviewPid)
            ProcessClose(this.PreviewPid)
        this.PreviewPid := 0
    }
    QueueLive() {
        this.P.Dirty := true
        if !this.Live
            return
        if this._liveTimer
            SetTimer(this._liveTimer, 0)
        this._liveTimer := (*) => this.Try("live run", (*) => this.Preview(true))
        SetTimer(this._liveTimer, -this.LiveDelay)
    }
    CheckAll() {
        st := {Bad: 0, First: ""}
        this.P.Walk(this.P.Root, (n) => (this.CheckNode(n, st), false))
        r := AxStudio.Validate(AxGen.Script(this.P, this.ScriptPath()), this.ScriptPath())
        msg := st.Bad ? st.Bad " handler(s) do not parse. First: " st.First : "Every handler parses."
        msg .= r.Ok ? "`n`nThe whole script parses too." : "`n`nThe whole script does not:`n" r.Msg
        this.Alert(msg, "Syntax check")
    }
    CheckNode(n, st) {
        for e in n.Ev {
            if (Trim(e["code"]) = "")
                continue
            t := "#Requires AutoHotkey v2.0`n#Warn All, Off`n" AxGen.HandlerName(n, e["name"])
               . "(" AxCat.Sig(e["name"]) ") {`n" AxGen.Block(e["code"], "    ") "`n}`n"
            r := AxStudio.Validate(t)
            if !r.Ok {
                st.Bad++
                if (st.First = "")
                    st.First := AxGen.HandlerName(n, e["name"]) ": " r.Msg
            }
        }
    }
    ; Every key the studio answers to, grouped by where you are. Kept in step
    ; with Key() -- a sheet that lists keys that no longer do anything, and
    ; misses the ones that do, is worse than none.
    HelpDialog() {
        K := (title, rows) => AxStudio.KeyTable(title, rows)
        keys := '<div class="axd-keycols"><div class="axd-keycol">'
             . K("Moving around", [["Ctrl+1 ... Ctrl+7", "Design, Logic, Steps, Code, Map, App, Look"],
                                   ["Alt+Left  Alt+Right", "back and forward, the way you came"],
                                   ["Ctrl+I", "add anything"],
                                   ["Ctrl+Shift+P", "every command"],
                                   ["Ctrl+P", "go to a window, page or control"],
                                   ["Ctrl+J", "Problems and Output"],
                                   ["Up  Down", "Logic and App: the next section"],
                                   ["Ctrl+B", "the Toolbox and Outline"],
                                   ["Ctrl+Shift+B", "the inspector"],
                                   ["F1", "this sheet"]])
             . K("Running and saving", [["F5", "run it"], ["F6", "try it here, on the canvas"],
                                        ["Ctrl+S", "save"], ["Ctrl+E", "export the script"],
                                        ["Ctrl+Z  Ctrl+Y", "undo, redo"]])
             . '</div><div class="axd-keycol">'
             . K("On the canvas", [["Delete", "remove"], ["Ctrl+C  X  V", "copy, cut, paste"],
                                   ["Ctrl+D", "duplicate"], ["Ctrl+A", "everything on the page"],
                                   ["Arrows", "nudge, or reorder in the flow"],
                                   ["F2", "rename it"], ["Enter", "open its code"],
                                   ["Escape", "up to what holds it, then nothing"],
                                   ["Shift+F10", "its menu"]])
             . K("In the gallery", [["type", "find it"], ["Up  Down", "choose"],
                                    ["Enter", "add it"], ["Escape", "close"]])
             . K("In the code", [["Tab", "indent"], ["Ctrl+/", "comment"],
                                 ["Ctrl+Space", "complete"]])
             . '</div></div>'
        AxForm.Show(this, {Title: "Keys and gestures", Icon: "E765", Width: 720,
            Intro: "The canvas is the design itself, built by the library, so everything on it "
                 . "behaves the way it will when the script runs.",
            Fields: [
                {Id: "keys", Kind: "note", Html: true, L: keys},
                {Id: "h1", Kind: "heading", L: "On the canvas, with the mouse"},
                {Id: "n1", Kind: "note", L:
                    "Drag from the Toolbox to add a control. Drag a control to move it -- the "
                  . "caret says where it will land. Alt while dragging places it freely, Ctrl "
                  . "drops a copy, Shift puts a free one back in the flow. Drag on empty space "
                  . "to select several; Ctrl+click adds one at a time. The bar on the selected "
                  . "control has its code, duplicate, what holds it, delete, and the rest. Hold "
                  . "Alt and point at a control to measure it."},
                {Id: "h2", Kind: "heading", L: "Where things are"},
                {Id: "n2", Kind: "note", L:
                    "Design is the canvas, with the Toolbox and Outline on the left and the "
                  . "inspector -- the selection, or the window when nothing is selected -- on "
                  . "the right. Logic is values, bindings, rules, states and hotkeys. Code is "
                  . "every piece of code. App is the windows, the files and the build. Problems "
                  . "and Output are along the bottom of all four."}],
            Buttons: ["OK"], CancelIndex: 0})
    }
    static KeyTable(title, rows) {
        h := '<div class="axd-keyh">' title '</div><table class="axd-keys">'
        for r in rows
            h .= '<tr><td class="axd-kk">' AxTags.E(r[1]) '</td><td>' AxTags.E(r[2]) '</td></tr>'
        return h '</table>'
    }

    ; ----------------------------------------------------------- settings
    LoadSettings() {
        f := this.SettingsPath
        if !FileExist(f)
            return
        get := (k, d) => IniRead(f, "studio", k, d)
        try {
            this.LeftW := Integer(get("leftw", this.LeftW))
            this.RightW := Integer(get("rightw", this.RightW))
            this.Ws := get("workspace", this.Ws)
            if !AxStudio.IsWs(this.Ws)
                this.Ws := "design"
            this.PieceView := (get("pieceview", this.PieceView) = "code") ? "code" : "steps"
            this.PanelTab := get("paneltab", this.PanelTab)
            this.PanelOpen := Integer(get("panelopen", this.PanelOpen))
            this.PanelH := Integer(get("panelh", this.PanelH))
            this.LeftShown := Integer(get("leftshown", this.LeftShown))
            this.RightShown := Integer(get("rightshown", this.RightShown))
            this.Grid := Integer(get("grid", this.Grid))
            this.AutoSecs := Integer(get("autosecs", this.AutoSecs))
            this.LiveDelay := Integer(get("livedelay", this.LiveDelay))
            this.PreviewOpens := get("previewopens", this.PreviewOpens)
            if !RegExMatch(this.PreviewOpens, "^(design|place|last)$")
                this.PreviewOpens := "design"
            this.AutoToFile := Integer(get("autotofile", this.AutoToFile))
            this.ShowWelcome := Integer(get("showwelcome", this.ShowWelcome))
            this.AskWhereFirst := Integer(get("askwherefirst", this.AskWhereFirst))
            this.Ahk2Exe := get("ahk2exe", "")
            this.Snap := Integer(get("snap", this.Snap))
            this.Guides := Integer(get("guides", this.Guides))
            this.ShowGrid := Integer(get("showgrid", this.ShowGrid))
            this.Compact := Integer(get("compact", this.Compact))
            this.Dense := Integer(get("dense", this.Dense))
            this.AutoHideBar := Integer(get("autohidebar", this.AutoHideBar))
            try this.Zoom := Min(3, Max(0.25, Float(get("zoom", 1))))
            this.AlAnchor := get("alanchor", "each")
            this.LeftTab := (get("lefttab", this.LeftTab) = "tree") ? "tree" : "tools"
            pt := get("proptab", "props")
            this.PropTab := (pt = "layout" || pt = "events") ? pt : "props"
            this.PropSort := (get("propsort", "cat") = "az") ? "az" : "cat"
            this.PropHints := (get("prophints", 0) = 1) ? 1 : 0
            this.UiTheme := get("uitheme", this.UiTheme)
            this.RunX := Integer(get("runx", 0)), this.RunY := Integer(get("runy", 0))
            this.RunW := Integer(get("runw", 0)), this.RunH := Integer(get("runh", 0))
            this.RunPage := get("runpage", "")
            ; A saved list REPLACES the seed -- otherwise a group you opened on
            ; purpose would fold itself again on the next start.
            saved := get("shut", "@unset")
            if (saved != "@unset") {
                this.Shut := Map()
                for k in StrSplit(saved, ",")
                    if (Trim(k) != "")
                        this.Shut[Trim(k)] := 1
                ; saved before the inspector became a grid: its advanced
                ; group (a control's pop-up panel) starts folded, once
                if (Integer(get("shutv", 1)) < 2)
                    this.Shut["popover"] := 1
            }
        }
        loop 8 {
            v := ""
            try v := IniRead(f, "recent", "f" A_Index, "")
            if (v != "" && FileExist(v))
                this.Recent.Push(v)
        }
    }
    SaveSettings() {
        f := this.SettingsPath
        try {
            IniWrite(this.LeftW, f, "studio", "leftw")
            IniWrite(this.RightW, f, "studio", "rightw")
            IniWrite(this.Ws, f, "studio", "workspace")
            IniWrite(this.PieceView, f, "studio", "pieceview")
            IniWrite(this.PanelTab, f, "studio", "paneltab")
            IniWrite(this.PanelOpen, f, "studio", "panelopen")
            IniWrite(this.PanelH, f, "studio", "panelh")
            IniWrite(this.LeftShown, f, "studio", "leftshown")
            IniWrite(this.RightShown, f, "studio", "rightshown")
            IniWrite(this.Grid, f, "studio", "grid")
            IniWrite(this.AutoSecs, f, "studio", "autosecs")
            IniWrite(this.LiveDelay, f, "studio", "livedelay")
            IniWrite(this.PreviewOpens, f, "studio", "previewopens")
            IniWrite(this.AutoToFile, f, "studio", "autotofile")
            IniWrite(this.ShowWelcome, f, "studio", "showwelcome")
            IniWrite(this.AskWhereFirst, f, "studio", "askwherefirst")
            IniWrite(this.Ahk2Exe, f, "studio", "ahk2exe")
            IniWrite(this.Snap, f, "studio", "snap")
            IniWrite(this.Guides, f, "studio", "guides")
            IniWrite(this.ShowGrid, f, "studio", "showgrid")
            IniWrite(this.Compact, f, "studio", "compact")
            IniWrite(this.Dense, f, "studio", "dense")
            IniWrite(this.AutoHideBar, f, "studio", "autohidebar")
            IniWrite(this.Zoom, f, "studio", "zoom")
            IniWrite(this.AlAnchor, f, "studio", "alanchor")
            IniWrite(this.LeftTab, f, "studio", "lefttab")
            IniWrite(this.PropTab, f, "studio", "proptab")
            IniWrite(this.PropSort, f, "studio", "propsort")
            IniWrite(this.PropHints ? 1 : 0, f, "studio", "prophints")
            IniWrite(this.UiTheme, f, "studio", "uitheme")
            ; where the last debug run left its window, so the next one comes
            ; back the same size in the same place
            IniWrite(this.RunX, f, "studio", "runx")
            IniWrite(this.RunY, f, "studio", "runy")
            IniWrite(this.RunW, f, "studio", "runw")
            IniWrite(this.RunH, f, "studio", "runh")
            IniWrite(this.RunPage, f, "studio", "runpage")
            shut := ""
            for k in this.Shut
                shut .= (shut = "" ? "" : ",") k
            IniWrite(shut, f, "studio", "shut")
            IniWrite(2, f, "studio", "shutv")
            try IniDelete(f, "recent")
            for i, p in this.Recent
                IniWrite(p, f, "recent", "f" i)
        }
    }
    OnQuit() {
        this.StopPreview()
        this.SaveSettings()
        if this.P.Dirty
            try AxJson.Save(this.AutoPath, this.P.ToMap())
    }
}
