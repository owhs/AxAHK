#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Lint.ahk
#Include %A_LineFile%\..\AxStudio.Panes.ahk
#Include %A_LineFile%\..\AxStudio.Wizards.ahk

; Part of AxStudio, not a program on its own.
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
;  AxStudio.Titlebar.ahk -- the studio's own title bar.
;
;  One row where a window usually spends two: the menus sit in the title bar
;  (Alt still brings the classic menu bar back for the keyboard), then back
;  and forward, the project, the one search box for everything, and on the
;  right what is wrong, running it, and the studio's own settings.
;
;  Every item is the library's own title bar item (AxWindow.Titlebar.ahk);
;  the rich parts are popovers built when they open, so they always say what
;  is true now: the project card (where it is, whether it is saved, the
;  recent ones), the problems, the ways to run it, and the keys.
;
;  Clicks inside a popover arrive as data-tbp="verb|arg" (the "axPop" hook,
;  wired once in AxTitle.Wire).
;
;  Sync(s) brings the items up to date -- the project's name and whether it
;  is saved, the problem count, Live and Try it, back and forward -- and
;  does nothing when nothing it shows has changed.
; =============================================================================
class AxTitle {
    static Sig := ""

    static Items(s) {
        items := []
        for i, m in s.Menus()
            items.Push({Id: "tbm" i, Kind: "text", Text: StrReplace(m.Title, "&"), Class: "axd-tbmenu", Menu: m.Items})
        items.Push({Kind: "sep"})
        items.Push({Id: "tbBack", Glyph: "E72B", Tip: "Back    Alt+Left", Disabled: true,
                    Click: (*) => s.Try("back", (*) => s.NavStep(-1))})
        items.Push({Id: "tbFwd", Glyph: "E72A", Tip: "Forward    Alt+Right", Disabled: true,
                    Click: (*) => s.Try("forward", (*) => s.NavStep(1))})
        items.Push({Kind: "spacer", Class: "axd-tbgrow"})
        ; the project: its name and whether it is saved, and a card of it
        items.Push({Id: "tbProj", Kind: "html", Class: "axd-tbproj", Html: AxTitle.ProjHtml(s),
                    Tip: "The project: where it is, whether it is saved, the recent ones",
                    Popover: {Build: () => AxTitle.ProjCard(s), Width: 340, Align: "center"}})
        ; the one search for everything
        items.Push({Id: "tbCmd", Kind: "html", Class: "axd-tbcmd",
                    Html: '<span class="ico">&#xE721;</span><span class="axd-tbcmdt">Search commands, controls and places</span>'
                        . '<span class="axd-kbd">Ctrl+Shift+P</span>',
                    Click: (*) => s.Js("AXD.palOpen('cmd');")})
        items.Push({Kind: "spacer", Class: "axd-tbgrow"})
        ; the right: what is wrong, running it, the studio itself
        items.Push({Id: "tbProblems", Side: "right", Kind: "html", Class: "axd-tbprob", Hidden: true, Html: "",
                    Tip: "What is wrong with the design", Popover: {Build: () => AxTitle.ProblemsCard(s), Width: 380}})
        items.Push({Id: "tbTry", Side: "right", Kind: "html", Class: "axd-tbbtn",
                    Html: '<span class="ico">&#xE7C4;</span>Try it', Tip: "F6 -- the canvas goes live, here, without running anything",
                    Click: (*) => s.Try("test", (*) => s.ToggleTest())})
        items.Push({Id: "tbLive", Side: "right", Kind: "html", Class: "axd-tbbtn",
                    Html: '<span class="ico">&#xE895;</span>Live', Tip: "Run it again a moment after every change",
                    Click: (*) => s.Try("live", (*) => s.BarDo("live"))})
        items.Push({Id: "tbRun", Side: "right", Kind: "html", Class: "axd-tbbtn axd-tbrun",
                    Html: '<span class="ico">&#xE768;</span>Run', Tip: "F5 -- run the real script",
                    Click: (*) => s.Try("preview", (*) => s.Preview())})
        items.Push({Id: "tbRunMore", Side: "right", Glyph: "E70D", Class: "axd-tbrunmore", Tip: "More ways to run and build it",
                    Popover: {Build: () => AxTitle.RunCard(s), Width: 290}})
        items.Push({Side: "right", Kind: "sep"})
        items.Push({Id: "tbTheme", Side: "right", Glyph: s.UiTheme = "dark" ? "E706" : "E708",
                    Tip: "The studio light or dark (the design keeps its own)",
                    Click: (*) => s.Try("theme", (*) => AxTitle.FlipTheme(s))})
        items.Push({Id: "tbSettings", Side: "right", Glyph: "E713", Tip: "Settings",
                    Click: (*) => s.Try("settings", (*) => AxWiz.Settings(s))})
        items.Push({Id: "tbHelp", Side: "right", Glyph: "E897", Tip: "Help and keys    F1",
                    Popover: {Build: () => AxTitle.HelpCard(s), Width: 330}})
        return items
    }
    ; once the page is there: clicks inside the popovers
    static Wire(s) {
        s.On("click", "axPop", (el, ev) => AxTitle.PopClick(s, ev))
        AxTitle.Sync(s, true)
    }
    static FlipTheme(s) {
        s.SetUi(s.UiTheme = "dark" ? "light" : "dark")
        s.TitleItem("tbTheme", {Glyph: s.UiTheme = "dark" ? "E706" : "E708"})
    }

    ; ------------------------------------------------------------- keeping up
    static Sync(s, force := false) {
        bad := 0, warn := 0
        try bad := AxLint.Count(s.Issues, "error") + (IsObject(s.RunBlock) ? 1 : 0), warn := AxLint.Count(s.Issues, "warn")
        running := false
        try running := s.PreviewPid && ProcessExist(s.PreviewPid)
        sig := AxTitle.ProjHtml(s) "|" bad "|" warn "|" s.Testing "|" s.Live "|" running "|" s.NavAt "|" s.NavList.Length
        if (!force && sig == AxTitle.Sig)
            return
        AxTitle.Sig := sig
        try {
            s.TitleItem("tbProj", {Html: AxTitle.ProjHtml(s)})
            s.TitleItem("tbProblems", {Hidden: !(bad + warn),
                Html: (bad ? '<span class="axd-tbbad"><span class="ico">&#xEA39;</span>' bad '</span>' : "")
                    . (warn ? '<span class="axd-tbwarn"><span class="ico">&#xE7BA;</span>' warn '</span>' : "")})
            s.TitleItem("tbTry", {On: s.Testing})
            s.TitleItem("tbLive", {On: s.Live})
            s.TitleItem("tbRun", {Html: running ? '<span class="ico">&#xE72C;</span>Run again' : '<span class="ico">&#xE768;</span>Run'})
            s.TitleItem("tbBack", {Disabled: s.NavAt <= 1})
            s.TitleItem("tbFwd", {Disabled: s.NavAt >= s.NavList.Length})
        }
    }
    ; the same "unsaved" the status bar says (SaveState)
    static Dirty(s) {
        d := false
        try d := s.P.Dirty || s._saveText = "Unsaved changes"
        return d
    }
    static ProjHtml(s) {
        name := "Untitled"
        try name := (s.P.Path != "") ? RegExReplace(RegExReplace(s.P.Path, ".*\\"), "i)\.axs\.json$|\.json$") : "Untitled"
        dirty := AxTitle.Dirty(s)
        return '<span class="ico">&#xE8A5;</span><b>' AxTags.E(name) '</b>'
             . (dirty ? '<i class="axd-tbdirty" title="Unsaved changes"></i>' : "")
             . '<span class="axd-tbcaret">&#xE70D;</span>'
    }

    ; ------------------------------------------------------------ the cards
    static Btn(v, label, ico := "", cls := "") => '<span class="axd-tbpb' (cls != "" ? " " cls : "") '" data-tbp="' v '">'
        . (ico != "" ? '<span class="ico">&#x' ico ';</span>' : "") label '</span>'
    static ProjCard(s) {
        E := (x) => AxTags.E(x)
        p := s.P
        wins := p.Wins.Length, c := {N: 0}
        try for w in p.Wins
            p.Walk(w.Root, AxTitle.CountFn(c))
        ctls := c.N
        h := '<div class="axd-tbcard"><div class="axd-tbch"><span class="ico">&#xE8A5;</span><div><b>'
           . E(p.Path != "" ? RegExReplace(p.Path, ".*\\") : "Untitled") '</b><span>'
           . E(p.Path != "" ? RegExReplace(p.Path, "\\[^\\]*$") : "Not saved yet -- it lives in the autosave until it is.") '</span></div></div>'
           . '<div class="axd-tbfacts"><span><b>' wins '</b> window' (wins = 1 ? "" : "s") '</span><span><b>' ctls '</b> controls</span>'
           . '<span class="' (AxTitle.Dirty(s) ? "axd-tbfbad" : "axd-tbfok") '">' AxTags.E(s._saveText != "" ? s._saveText : "No changes") '</span></div>'
           . '<div class="axd-tbrow">' AxTitle.Btn("save", "Save", "E74E", "axd-go") AxTitle.Btn("saveas", "Save as...")
           . (p.Path != "" ? AxTitle.Btn("folder", "Show in its folder", "E838") : "") '</div>'
           . '<div class="axd-tbrow">' AxTitle.Btn("export", "Export the script", "EDE1") AxTitle.Btn("open", "Open...", "E8E5")
           . AxTitle.Btn("new", "New", "E710") '</div>'
        if s.Recent.Length {
            h .= '<div class="axd-tbsub">Recent</div>'
            for i, f in s.Recent {
                if (i > 6)
                    break
                h .= '<div class="axd-tbli" data-tbp="recent|' i '"><span class="ico">&#xE8A5;</span>' E(RegExReplace(f, ".*\\"))
                   . '<i>' E(RegExReplace(RegExReplace(f, "\\[^\\]*$"), "^.*(.{0,38})$", "$1")) '</i></div>'
            }
        }
        return h '</div>'
    }
    static CountFn(c) => (x) => (c.N++, false)
    static ProblemsCard(s) {
        E := (x) => AxTags.E(x)
        h := '<div class="axd-tbcard"><div class="axd-tbch"><span class="ico">&#xE7BA;</span><div><b>Problems</b><span>'
           . 'Checked every time the design changes. Click one to go to it.</span></div></div>'
        n := 0
        for sev in ["error", "warn", "info"]
            for i, f in s.Issues {
                if (f.Sev != sev)
                    continue
                if (++n > 8)
                    break
                h .= '<div class="axd-tbli axd-tbli-' sev '" data-tbp="issue|' i '"><span class="ico">&#x' AxPanes.LintIcon(sev) ';</span>'
                   . E(f.Msg) '</div>'
            }
        if !n
            h .= '<div class="axd-tbempty">Nothing to report.</div>'
        return h '<div class="axd-tbrow">' AxTitle.Btn("panel", "Open the Problems panel", "E8A0") AxTitle.Btn("recheck", "Check again", "E72C") '</div></div>'
    }
    static RunCard(s) {
        running := false
        try running := s.PreviewPid && ProcessExist(s.PreviewPid)
        li := (v, ico, label, key, sub := "") => '<div class="axd-tbli axd-tbrun2" data-tbp="' v '"><span class="ico">&#x' ico ';</span><div><b>'
            . label '</b>' (sub != "" ? '<span>' sub '</span>' : "") '</div>' (key != "" ? '<i>' key '</i>' : "") '</div>'
        return '<div class="axd-tbcard">'
             . li("run", "E768", running ? "Run it again" : "Run it", "F5", "The real script, in its own window")
             . li("test", "E7C4", s.Testing ? "Stop trying it" : "Try it here", "F6", "The canvas goes live; nothing is run")
             . li("live", "E895", s.Live ? "Stop re-running" : "Live", "", "Run it again a moment after every change")
             . (running ? li("stop", "E71A", "Stop it", "", "The running copy closes") : "")
             . '<div class="axd-tbsub">Building</div>'
             . li("build", "E7B8", "Make the exe", "", "Compile it with the settings in App > Build")
             . li("export", "EDE1", "Export the script", "Ctrl+E", "The .ahk file, merged with any hand edits")
             . li("buildset", "E713", "Build settings...", "", "Icon, version, what the exe carries")
             . '</div>'
    }
    static HelpCard(s) {
        k := (a, b) => '<div class="axd-tbkey"><span>' a '</span>' b '</div>'
        return '<div class="axd-tbcard"><div class="axd-tbch"><span class="ico">&#xE897;</span><div><b>Getting around</b>'
             . '<span>The seven tabs are seven ways to look at one program.</span></div></div>'
             . k("Ctrl+1 ... 7", "Design, Logic, Steps, Code, Map, App, Look")
             . k("Alt+Left / Right", "back and forward")
             . k("Ctrl+Shift+P", "any command")
             . k("Ctrl+I", "add anything")
             . k("F5 / F6", "run it / try it here")
             . '<div class="axd-tbrow">' AxTitle.Btn("keys", "All the keys", "E765") AxTitle.Btn("about", "About", "E946")
             . AxTitle.Btn("log", "The studio log", "E7C3") AxTitle.Btn("updates", "Check for updates", "E895") '</div></div>'
    }

    static UpdatesFn(s) => (*) => AxUpdate.Show(s)       ; after the card has closed
    ; ------------------------------------------------------------ the clicks
    static PopClick(s, ev) {
        el := ""
        try el := ev.srcElement
        v := ""
        while IsObject(el) {
            try v := el.getAttribute("data-tbp")
            if (v != "")
                break
            try el := el.parentNode
            catch
                break
        }
        if (v = "")
            return
        s.ClosePopover(true)
        p := StrSplit(v, "|", , 2), arg := p.Length > 1 ? p[2] : ""
        s.Try("title " p[1], (*) => AxTitle.Do(s, p[1], arg))
    }
    static Do(s, verb, arg) {
        switch verb {
        case "save":     s.Save()
        case "saveas":   s.SaveAs()
        case "open":     s.Open()
        case "new":
            if s.ConfirmDiscard()
                AxWiz.Template(s)
        case "export":   s.Export()
        case "folder":   Run('explorer.exe /select,"' s.P.Path '"')
        case "recent":
            i := Integer(arg)
            if (i >= 1 && i <= s.Recent.Length && s.ConfirmDiscard())
                s.LoadFile(s.Recent[i])
        case "issue":    s.GoToIssue(Integer(arg))
        case "panel":    s.ShowPanel("lint")
        case "recheck":  s.QuickAction("lint.recheck")
        case "run":      s.Preview()
        case "test":     s.ToggleTest()
        case "live":     s.BarDo("live")
        case "stop":     s.StopPreview()
        case "build":    AxWiz.Build(s)
        case "buildset": s.GoSec("build", "app")
        case "keys":     s.HelpDialog()
        case "about":    s.AboutDialog()
        case "updates":  SetTimer(AxTitle.UpdatesFn(s), -1)
        case "log":      Run('notepad.exe "' s.LogPath '"')
        }
        AxTitle.Sync(s, true)
    }
}
