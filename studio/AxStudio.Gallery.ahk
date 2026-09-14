#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Catalog.ahk
#Include %A_LineFile%\..\AxStudio.Wizards.ahk
#Include %A_LineFile%\..\AxStudio.Helpers.ahk
#Include %A_LineFile%\..\AxStudio.Data.ahk
#Include %A_LineFile%\..\AxStudio.PkgUi.ahk
#Include %A_LineFile%\..\AxStudio.App.ahk

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
;  AxStudio.Gallery.ahk -- one place to add anything.
;
;  Adding used to be a menu: Insert, then a category, then a control, or
;  further down a value, a binding, a hotkey, a file, an argument -- thirty-
;  odd entries in one tree, each a one-line label, and nothing to say what
;  any of them was for or where the thing would end up.
;
;  So it is a page of cards instead, grouped by what the thing is. Each card
;  says in a sentence what it is for and which workspace it lives in, the box
;  at the top finds any of them by what you type -- "slider", "key", "ini" --
;  and choosing one takes you to where it lives before the form comes up, so
;  you watch it arrive in its list.
;
;      AxGallery.Open(s)        Ctrl+I, the Add button, Add > Anything
; =============================================================================
class AxGallery {
    static IsOpen := false
    static Find := ""
    static Cur := []                          ; what the cards on screen stand for
    static Sel := 1                           ; the lit card: what Enter adds

    static Cats := [["canvas", "On the canvas"], ["logic", "Behaviour"],
                    ["windows", "Windows"], ["code", "Code"], ["app", "The program"],
                    ["controls", "Controls"], ["snippets", "Ready code"], ["libraries", "Libraries"]]
    ; shown only once something is typed: there are hundreds of them
    static OnSearch := Map("snippets", true, "libraries", true)

    ; Home is the workspace the thing lives in; it is put in front before the
    ; form opens, so the new thing appears where it will be looked for.
    static Items(s) {
        I := (cat, icon, t, d, home, fn) => {Cat: cat, Icon: icon, T: t, D: d, Home: home, Fn: fn}
        out := [
            I("canvas", "E8FD", "A row of controls", "Several controls side by side, spaced and "
                . "aligned, in one go.", "design", (*) => s.RowWizard()),
            I("canvas", "F0E2", "A grid of controls", "Rows and columns of the same control -- "
                . "a keypad, a board of switches.", "design", (*) => s.GridWizard()),
            I("canvas", "E7C4", "A page", "Another page in this window, with its own entry in "
                . "the page rail.", "design", (*) => s.AddNewPage()),
            I("canvas", "E9D5", "Data for a list", "Fill the selected list, table or drop-down "
                . "from a CSV file, a folder or typed rows.", "design",
                (*) => AxData.Wizard(s, s.Primary())),

            I("logic", "E8EF", "A value", "A variable the whole program shares. Controls bind "
                . "to it, rules set it, your code reads it.", "logic", (*) => s.ValueWizard()),
            I("logic", "E8C8", "A binding", "Keep a control and a value the same, both ways or "
                . "one way, without copying by hand.", "logic", (*) => s.BindWizard()),
            I("logic", "E945", "A rule", "When this control does that, do this -- behaviour "
                . "without writing code.", "logic", (*) => s.FlowWizard()),
            I("logic", "E81E", "A state", "A named set of changes -- busy, signed in -- that a "
                . "rule applies in one go.", "logic", (*) => s.StateWizard()),
            I("logic", "E765", "A hotkey", "A key combination that does something, in this "
                . "window or everywhere.", "logic", (*) => s.HotkeyWizard()),
            I("logic", "E8FD", "A step, in any piece of code", "Read what a handler or a function does "
                . "as a flowchart, and add, change or move its steps without writing code.", "steps",
                (*) => AxMap.SetMode(s, "steps")),
            I("logic", "E8D2", "A typed shortcut", "Type a few letters anywhere and they become "
                . "something longer -- or do some steps. (A hotstring.)", "logic",
                (*) => (s.GoSec("hotstrings", "logic"), AxAutoUi.Hotstring(s))),
            I("logic", "E916", "A timer", "Something that happens by itself, every so often or "
                . "once after a while.", "logic", (*) => (s.GoSec("timers", "logic"), AxAutoUi.Timer(s))),
            I("logic", "E9D5", "A condition", "A named yes or no -- a program in front, working "
                . "hours, CapsLock on -- for hotkeys and timers to wait for.", "logic",
                (*) => (s.GoSec("conditions", "logic"), AxAutoUi.Cond(s))),

            I("windows", "E7C4", "A window", "Another window, opened on demand from this one.",
                "app", (*) => s.NewWindow("window")),
            I("windows", "E8BD", "A dialog", "A modal window that is asked something and hands "
                . "back the answer.", "app", (*) => s.NewWindow("dialog")),
            I("windows", "E90F", "A tool window", "A small window that floats beside the main "
                . "one.", "app", (*) => s.NewWindow("tool")),

            I("code", "E943", "A script helper", "Hotkeys, listeners, timers, a settings file, "
                . "restarting elevated -- " AxHelp.All().Length " of them, written for you.",
                "code", (*) => AxHelp.Pick(s)),
            I("code", "E946", "A dialog call", "The line that shows a message, asks a question "
                . "or picks a file, written into a handler.", "", (*) => s.DialogWizard()),
            I("code", "E700", "A menu", "A menu bar, a right-click menu or a tray menu, one item "
                . "per line.", "", (*) => s.MenuWizard()),
            I("code", "E8A5", "A snippet", "A few ready lines dropped into the code being "
                . "edited.", "code", (*) => s.SnippetMenu()),

            I("app", "E8E5", "Files the program needs", "Pictures, data, sounds -- carried inside the exe, "
                . "or read from beside it.", "app", (*) => (s.GoSec("files", "app"), AxFilesUi.AddFiles(s))),
            I("app", "E943", "A code file", "Another .ahk file the program uses -- functions of your "
                . "own you keep in a file.", "app", (*) => AxWiz.AddInclude(s)),
            I("app", "E756", "A command-line option", "Something the program can be started "
                . "with: --debug, --page settings.", "app", (*) => AxWiz.AddArg(s)),
            I("app", "E7C4", "A way to start", "A named way of starting -- setup, quiet -- that opens "
                . "a page or applies a state.", "app", (*) => AxWiz.AddMode(s)),
            I("app", "E8B7", "A tray icon", "An icon by the clock, and the menu it opens.",
                "app", (*) => AxWiz.Tray(s)),
            I("app", "E82D", "A library", "Someone else's AutoHotkey library -- JSON, UI automation, "
                . "OCR, SQLite and " AxPkg.List().Length " more -- installed with Aris.", "app",
                (*) => s.GoSec("libraries", "app")),
            I("app", "E896", "More controls, from a pack", "Install extra controls from a .zip.",
                "app", (*) => s.InstallPack())]
        for cat in AxCat.Cats
            for e in AxCat.InCat(cat)
                out.Push(I("controls", e.Icon, e.Label, cat ": " e.T, "design", s.InsertFn(e.T)))
        ; every ready piece of code there is, one card each, so typing "json"
        ; or "hotkey" finds it wherever it came from: the studio's snippets,
        ; the script helpers, and the libraries' own (studio\packages\patch.json)
        for k, sn in AxStudio.SnipList()
            out.Push(I("snippets", "E8A5", sn.N, "A snippet: " AxGallery.Brief(sn.C), "code", AxGallery.SnipFn(s, k)))
        for h in AxHelp.All()
            out.Push(I("snippets", h.Icon, h.Name, "A script helper (" h.Cat "): " h.Desc, "code",
                       AxGallery.HelperFn(s, h.Id)))
        for e in AxPkg.List() {
            if e.Hidden
                continue                    ; builds windows: the studio's job
            for j, sn in e.Snippets
                out.Push(I("snippets", "E82D", sn.Name " -- " e.Short, e.Name ": " AxGallery.Brief(sn.Code), "",
                           AxGallery.PkgSnipFn(s, e.Name, j)))
            out.Push(I("libraries", "E82D", e.Short, e.Name ": " e.Desc, "app", AxGallery.PkgFn(s, e.Name)))
        }
        return out
    }
    static Brief(code) => SubStr(RegExReplace(Trim(code), "\s+", " "), 1, 90)
    static SnipFn(s, i) => (*) => s.InsertSnippet(i)
    static HelperFn(s, id) => (*) => AxHelp.Configure(s, id)
    static PkgFn(s, name) => (*) => (AxPkgUi.Sel := name, s.GoSec("libraries", "app"))
    ; a library's snippet: written in when the library is here; otherwise
    ; the library is shown, to install first
    static PkgSnipFn(s, name, j) => (*) => AxGallery.PkgSnip(s, name, j)
    static PkgSnip(s, name, j) {
        e := AxPkg.Find(name)
        if !IsObject(e) || j > e.Snippets.Length
            return
        if AxPkg.Installed(AxPkg.ProjDir(s.P)).Has(name)
            return AxPkgUi.Write(s, e.Snippets[j].Code, e)
        AxPkgUi.Sel := name
        s.GoSec("libraries", "app")
        s.Status("msg", name " is not installed in this project yet: install it, then its snippets write themselves in.")
    }

    ; ------------------------------------------------------------ showing
    static Open(s) {
        AxGallery.Find := ""
        AxGallery.Sel := 1
        AxGallery.IsOpen := true
        try s.CloseContextMenu()
        s.Html("axdGal", '<div class="axd-galbox">'
            . '<div class="axd-galhead"><span class="axd-galtitle">Add</span>'
            . '<input id="axdGalFind" class="axd-galfind" autocomplete="off" '
            . 'placeholder="What do you want to add?  A hotkey, a value, a slider, a file...">'
            . '<span class="axd-galx" data-galclose="1" data-tip="Close    Esc">&#xE711;</span></div>'
            . '<div class="axd-gallist" id="axdGalList">' AxGallery.ListHtml(s) '</div>'
            . '<div class="axd-galfoot">Up and Down choose  &#183;  Enter adds the lit one  &#183;  Esc closes'
            . '  &#183;  each goes where it lives, so it is there to change afterwards</div></div>')
        try s.El("axdGal").style.display := "block"
        try s.El("axdGalFind").focus()
    }
    static Close(s) {
        AxGallery.IsOpen := false
        try s.El("axdGal").style.display := "none"
        try s.Html("axdGal", "")
    }
    static ListHtml(s) {
        q := StrLower(Trim(AxGallery.Find))
        all := AxGallery.Items(s)
        AxGallery.Cur := []
        h := ""
        for c in AxGallery.Cats {
            body := ""
            if (q = "" && AxGallery.OnSearch.Has(c[1]))
                continue
            for it in all {
                if (it.Cat != c[1])
                    continue
                if (q != "" && !AxGallery.Says(it.T " " it.D " " c[2], q))
                    continue
                AxGallery.Cur.Push(it)
                i := AxGallery.Cur.Length
                lit := (i = AxGallery.Sel) ? " on" : ""
                if (c[1] = "controls")
                    body .= '<div class="axd-gtile' lit '" data-gal="' i '" data-tip="' AxTags.E(it.D) '">'
                         .  '<span class="ico">&#x' it.Icon ';</span>' AxTags.E(it.T) '</div>'
                else
                    body .= '<div class="axd-gcard' lit '" data-gal="' i '">'
                         .  '<div class="axd-gct"><span class="ico">&#x' it.Icon ';</span>'
                         .  AxTags.E(it.T) '</div>'
                         .  '<div class="axd-gcd">' AxTags.E(it.D) '</div>'
                         .  (it.Home != "" ? '<div class="axd-gcw">' AxGallery.WhereWord(it.Home) '</div>' : "")
                         .  '</div>'
            }
            if (body != "")
                h .= '<div class="axd-gsec">' AxTags.E(c[2])
                  .  (c[1] = "controls" ? '<span class="axd-dim">also in the Toolbox, to drag</span>' : "")
                  .  '</div><div class="axd-gbody">' body '</div>'
        }
        if (h = "")
            return '<div class="axd-empty-pane">Nothing called that. Try a shorter word.</div>'
        ; Trident hides a placeholder while its field has focus, and this one
        ; has it from the start -- so the hint is here, where it can be seen
        return (q = "") ? '<div class="axd-galhint">Type what you want to add -- a hotkey, a value, '
                        . 'a slider, a file -- or pick a card. Up and Down choose, Enter adds the '
                        . 'lit one.</div>' h : h
    }
    ; every word typed is somewhere in it, in any order
    static Says(text, q) {
        text := StrLower(text)
        for w in StrSplit(q, " ")
            if (w != "" && !InStr(text, w))
                return false
        return true
    }
    static WhereWord(home) {
        switch home {
        case "design": return "on the canvas"
        case "logic":  return "lives in Logic"
        case "code":   return "lives in Code"
        case "app":    return "lives in App"
        case "map":    return "in Map"
        case "steps":  return "in Steps"
        }
        return ""
    }

    ; ----------------------------------------------------------- choosing
    static Run(s, i) {
        if (i < 1 || i > AxGallery.Cur.Length)
            return
        it := AxGallery.Cur[i]
        AxGallery.Close(s)
        if (it.Home != "" && s.Ws != it.Home)
            s.SetWs(it.Home)
        s.Try(it.T, it.Fn)
    }
    static Click(s, ev) {
        src := ev.srcElement
        try {
            if (src.id = "axdGal")               ; the dimmed page around the box
                return AxGallery.Close(s)
        }
        if (s.UpAttr(src, "data-galclose") != "")
            return AxGallery.Close(s)
        v := s.UpAttr(src, "data-gal")
        if (v != "")
            AxGallery.Run(s, Integer(v))
    }
    ; The lit card moves with the arrows, round from the last to the first,
    ; and the list scrolls to keep it in sight.
    static Step(s, by) {
        n := AxGallery.Cur.Length
        if !n
            return
        AxGallery.Sel := Mod(AxGallery.Sel - 1 + by + n, n) + 1
        try s.Html("axdGalList", AxGallery.ListHtml(s))
        try s.El("axdGalList").querySelector(".on").scrollIntoView(false)
    }
    ; Typing filters; Up and Down move the lit card; Enter adds it; Esc closes.
    static KeyUp(s, ev) {
        k := 0
        try k := ev.keyCode
        if (k = 27)
            return AxGallery.Close(s)
        if (k = 13)
            return AxGallery.Run(s, AxGallery.Sel)
        if (k = 38 || k = 40)
            return AxGallery.Step(s, k = 40 ? 1 : -1)
        v := ""
        try v := s.El("axdGalFind").value
        if (v = AxGallery.Find)
            return
        AxGallery.Find := v
        AxGallery.Sel := 1
        try s.Html("axdGalList", AxGallery.ListHtml(s))
    }
}
