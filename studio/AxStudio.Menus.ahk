#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Chrome.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk
#Include %A_LineFile%\..\AxStudio.Form.ahk

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
;  AxStudio.Menus.ahk -- every menu the program has, made by pointing: its
;  right-click menus (Logic > Menus), its menu bar (the same place), and the
;  tray icon's (App > Tray icon).
;
;  One editor for all three. A menu is drawn as the menu it will be -- each
;  item with its picture, its tick, its shortcut, greyed out or bold -- and
;  under each item, in plain words, what it does. A click on an item opens
;  its form; the small buttons on the right move it up and down, into the
;  submenu above it or back out, and remove it.
;
;  The text is still the truth (AxStudio.Chrome.ahk for right-click menus
;  and the menu bar, AxStudio.Assets.ahk for the tray): the tree is read
;  from it each time and written back after every change, so "Edit as text"
;  and this can never disagree.
;
;  Clicks arrive as data-mnu="verb|kind|key|path": kind is ctx, bar or tray;
;  key names the right-click menu; path is the item, "2.1" being the first
;  item of the second one's submenu.
; =============================================================================
class AxMenuUi {

    ; ================================================================ data
    static Tree(s, kind, key := "") {
        switch kind {
        case "tray": return AxAsset.Tray(s.P).Tree
        case "bar":  return AxChrome.Menus(s.P.W.Menus)
        case "ctx":
            for m in AxChrome.Menus(s.P.W.Ctx)
                if (AxProject.CleanName(m.Label) = key)
                    return m.Items
        }
        return []
    }
    static Save(s, kind, key, tree) {
        s.Mark()
        switch kind {
        case "tray":
            cfg := AxAsset.Tray(s.P), cfg.Tree := tree
            s.P.Tray := AxAsset.TrayText(cfg)
        case "bar":
            s.P.W.Menus := RTrim(AxChrome.MenusText(tree), "`n")
        case "ctx":
            tops := AxChrome.Menus(s.P.W.Ctx)
            for m in tops
                if (AxProject.CleanName(m.Label) = key)
                    m.Items := tree
            s.P.W.Ctx := AxMenuUi.CtxText(tops)
        }
        s.QueueLive()
        s.Reflect(false)
    }
    static CtxText(tops) {
        out := ""
        for m in tops
            out .= m.Label (m.Shortcut != "" ? " | " m.Shortcut : "") "`n" AxChrome.MenusText(m.Items, 1)
        return RTrim(out, "`n")
    }
    static At(tree, path) {
        parts := StrSplit(path, ".")
        list := tree
        loop parts.Length - 1
            list := list[Integer(parts[A_Index])].Items
        i := Integer(parts[parts.Length])
        return {List: list, I: i, It: (i >= 1 && i <= list.Length) ? list[i] : ""}
    }
    static Blank(label := "") => {Label: label, Shortcut: "", Code: "", Sep: false, Items: [], Icon: "", Check: "",
                                   Pick: "", Off: false, Default: false}

    ; =========================================================== drawing it
    ; The menu as it will open, with the tools to change it.
    static Editor(s, kind, key, tree) {
        tag := kind "|" key
        h := '<div class="axd-menued axctx hasmarks">'
        h .= tree.Length ? AxMenuUi.Rows(s, tree, "", 0, kind, key)
            : '<div class="axd-mempty">Nothing in it yet -- add the first item below.</div>'
        h .= '</div><div class="axd-madd">'
           . '<span class="axd-hbtn" data-mnu="add|' tag '|"><span class="ico">&#xE710;</span> An item</span>'
           . '<span class="axd-hbtn" data-mnu="subm|' tag '|"><span class="ico">&#xE8A4;</span> A submenu</span>'
           . '<span class="axd-hbtn" data-mnu="sep|' tag '|"><span class="ico">&#xE738;</span> A line</span>'
           . '</div>'
        return h
    }
    static Rows(s, items, pre, depth, kind, key) {
        h := ""
        for i, it in items {
            path := pre (pre = "" ? "" : ".") i
            tag := kind "|" key "|" path
            T := (verb, ico, tip) => '<span class="axd-mtool" data-mnu="' verb '|' tag '" title="' tip '">&#x' ico ';</span>'
            tools := (i > 1 ? T("up", "E74A", "Move it up") : "") (i < items.Length ? T("down", "E74B", "Move it down") : "")
                   . ((i > 1 && !items[i - 1].Sep && !it.Sep) ? T("in", "E72A", "Into the submenu above it") : "")
                   . (depth ? T("out", "E72B", "Out of this submenu") : "")
                   . (it.Items.Length ? T("addin", "E710", "Add an item to this submenu") : "")
                   . T("del", "E74D", "Remove")
            pad := ' style="padding-left:' (8 + depth * 22) 'px"'
            if it.Sep {
                h .= '<div class="axd-mrow sep"' pad '><span class="axd-mline"></span><span class="axd-mtools">' tools '</span></div>'
                continue
            }
            h .= '<div class="axctx-item axd-mrow' (it.Off ? " disabled" : "") (it.Default ? " axd-mdef" : "") '"' pad
               . ' data-mnu="edit|' tag '" title="Click to change it">'
               . '<span class="axctx-mark">' AxMenuUi.Mark(it, kind) '</span>'
               . '<span class="axctx-label">' AxChrome.Amp(it.Label) '</span>'
               . (it.Items.Length ? '<span class="axctx-sub">&#xE76C;</span>'
                  : it.Shortcut != "" ? '<span class="axctx-kbd">' AxTags.E(it.Shortcut) '</span>' : "")
               . '<span class="axd-mdoes">' AxTags.E(AxMenuUi.Does(s, it, kind)) '</span>'
               . '<span class="axd-mtools">' tools '</span></div>'
            if it.Items.Length
                h .= AxMenuUi.Rows(s, it.Items, path, depth + 1, kind, key)
        }
        return h
    }
    ; its picture: a tick when it follows a value, else its glyph or icon
    static Mark(it, kind) {
        if (it.Check != "" || it.Pick != "")
            return (it.Pick != "") ? "&#x25CF;" : "&#xE73E;"
        if (it.Icon = "")
            return ""
        if RegExMatch(it.Icon, "^[0-9A-Fa-f]{4}$")
            return "&#x" it.Icon ";"
        uri := AxMenuUi.IconUri(it.Icon)
        return uri != "" ? '<img class="axd-mimg" src="' uri '">' : ""
    }
    static IconUri(spec) {
        static cache := Map()
        if !cache.Has(spec)
            try cache[spec] := AxSys.IconDataUri(spec, 16)
            catch
                cache[spec] := ""
        return cache[spec]
    }
    ; what it does, in words
    static Does(s, it, kind) {
        if it.Items.Length
            return "opens " it.Items.Length " more"
        if (it.Check != "")
            return "tick: flips " it.Check (it.Code != "" ? ", then does its code" : "")
        if (it.Pick != "")
            return "sets " StrReplace(it.Pick, ":", " to ")
        c := Trim(it.Code)
        if (c = "")
            return (kind = "tray") ? AxMenuUi.AutoWords(it.Label) : "does nothing yet"
        for o in AxMenuUi.Actions(s, kind)
            if (o.Code != "" && o.Code == c)
                return StrLower(o.L)
        return SubStr(c, 1, 60) (StrLen(c) > 60 ? "..." : "")
    }
    static AutoWords(label) {
        switch StrLower(RegExReplace(label, "&")) {
        case "show", "open":   return "shows the window"
        case "hide":           return "hides the window"
        case "toggle", "show or hide", "show/hide": return "shows or hides the window"
        case "exit", "quit":   return "quits the program"
        case "reload", "restart": return "starts it again"
        case "suspend hotkeys", "suspend": return "suspends the hotkeys (ticked while they are)"
        case "pause":          return "pauses the program"
        case "open the folder", "open folder": return "opens the program's folder"
        }
        return "does nothing yet (says its name)"
    }

    ; ============================================================ the form
    ; What an item can do, with the code each writes. kind decides which
    ; make sense: a tray item has no text box under it to cut from.
    static Actions(s, kind) {
        mv := s.P.Main().Var, wv := s.P.W.Var
        out := []
        if (kind = "tray")
            out.Push({V: "auto", L: "What its name says (Show, Hide, Exit, Pause...)", Code: ""})
        out.Push({V: "show", L: "Show the window", Code: mv ".Show()"})
        out.Push({V: "hide", L: "Hide the window", Code: (kind = "tray" ? mv : wv) ".Hide()"})
        out.Push({V: "toggle", L: "Show or hide the window",
                  Code: 'DllCall("IsWindowVisible", "Ptr", ' mv '.Hwnd) ? ' mv '.Hide() : ' mv '.Show()'})
        for w in s.P.Wins
            if (w.Kind != "main")
                out.Push({V: "open." w.Name, L: "Open " w.Name, Code: "Show" AxProject.CleanName(w.Name) "()"})
        if (kind = "ctx")
            for x in [["cut", "Cut the text", '^x'], ["copy", "Copy the text", '^c'], ["paste", "Paste", '^v'],
                      ["all", "Select all the text", '^a']]
                out.Push({V: x[1], L: x[2], Code: 'Send("' x[3] '")'})
        out.Push({V: "flip", L: "A tick: flip a value on and off", Code: ""})
        out.Push({V: "pick", L: "One of a set: set a value to this", Code: ""})
        out.Push({V: "step", L: "A step... (chosen next, the way a flowchart's are)", Code: ""})
        out.Push({V: "code", L: "Code I write", Code: ""})
        out.Push({V: "exit", L: "Quit the program", Code: "ExitApp()"})
        out.Push({V: "reload", L: "Start the program again", Code: "Reload()"})
        out.Push({V: "suspend", L: "Suspend the hotkeys (and tick while they are)", Code: kind = "tray" ? "" : "Suspend(-1)"})
        out.Push({V: "folder", L: "Open the program's folder", Code: "Run(A_ScriptDir)"})
        out.Push({V: "none", L: "Nothing -- a heading, or a submenu", Code: ""})
        return out
    }
    static ActOpts(s, kind) {
        o := ""
        for a in AxMenuUi.Actions(s, kind)
            o .= (o = "" ? "" : "|") a.V ":" a.L
        return o
    }
    static Guess(s, it, kind) {
        if (it.Check != "")
            return "flip"
        if (it.Pick != "")
            return "pick"
        c := Trim(it.Code)
        if (c = "")
            return (kind = "tray") ? (RegExMatch(StrLower(it.Label), "^(suspend)") ? "suspend" : "auto") : "none"
        for a in AxMenuUi.Actions(s, kind)
            if (a.Code != "" && a.Code == c)
                return a.V
        return "code"
    }
    ; the glyphs an in-window menu item can wear
    static Glyphs := [["", "None"], ["E8C6", "Cut"], ["E8C8", "Copy"], ["E77F", "Paste"], ["E74D", "Delete"],
        ["E710", "Add"], ["E70F", "Edit"], ["E74E", "Save"], ["E8E5", "Open"], ["E838", "Folder"], ["E8A5", "Document"],
        ["E72C", "Refresh"], ["E713", "Settings"], ["E721", "Search"], ["E72D", "Share"], ["E749", "Print"],
        ["E7A7", "Undo"], ["E7A6", "Redo"], ["E80F", "Home"], ["E946", "Info"], ["E897", "Help"], ["E7BA", "Warning"],
        ["E734", "Star"], ["EB51", "Heart"], ["E718", "Pin"], ["E71B", "Link"], ["E715", "Mail"], ["E787", "Calendar"],
        ["E823", "Clock"], ["E768", "Play"], ["E769", "Pause"], ["E71A", "Stop"], ["E767", "Volume"], ["E74F", "Mute"],
        ["E722", "Camera"], ["E91B", "Picture"], ["E943", "Code"], ["E896", "Download"], ["E898", "Upload"],
        ["E72E", "Lock"], ["E785", "Unlock"], ["E77B", "Person"], ["E716", "People"], ["E774", "Web"],
        ["EA80", "Idea"], ["E7C1", "Flag"], ["E7B3", "Look"], ["E7E8", "Power"], ["E711", "Close"], ["E73E", "Tick"]]
    ; ... and the icons Windows' own menu can: from Windows' own files
    static SysIcons := [["", "None"], ["shell32.dll,3", "Folder"], ["shell32.dll,4", "Open folder"], ["shell32.dll,0", "File"],
        ["shell32.dll,70", "Text"], ["shell32.dll,15", "Computer"], ["shell32.dll,21", "Settings"], ["shell32.dll,22", "Search"],
        ["shell32.dll,23", "Help"], ["shell32.dll,24", "Run"], ["shell32.dll,27", "Power"], ["shell32.dll,43", "Star"],
        ["shell32.dll,46", "Up"], ["shell32.dll,131", "Delete"], ["shell32.dll,134", "Find"], ["shell32.dll,137", "Play"],
        ["shell32.dll,138", "Globe"], ["shell32.dll,165", "Info"], ["shell32.dll,167", "Clock"], ["shell32.dll,168", "Refresh"],
        ["shell32.dll,238", "Back"], ["shell32.dll,239", "Refresh 2"], ["shell32.dll,258", "Save"], ["shell32.dll,297", "Tick"],
        ["imageres.dll,77", "Warning"], ["imageres.dll,93", "Shield"], ["imageres.dll,98", "Error"], ["imageres.dll,101", "Info 2"],
        ["imageres.dll,109", "Notes"], ["imageres.dll,184", "Lock"]]
    static IconItems(kind) {
        out := []
        if (kind = "tray") {
            for x in AxMenuUi.SysIcons
                out.Push({V: x[1], L: x[2], Img: x[1] != "" ? AxMenuUi.IconUri(x[1]) : ""})
        } else
            for x in AxMenuUi.Glyphs
                out.Push({V: x[1], L: x[2], Icon: x[1]})
        return out
    }
    ; One item's form: what it says, its picture, what it does. Gives the
    ; item back changed, or "" when cancelled.
    static ItemForm(s, kind, it, title := "") {
        vals := AxStepsUi.ValueOpts(s)
        ck := (it.Check != "") ? it.Check : (it.Pick != "") ? StrSplit(it.Pick, ":")[1] : ""
        pv := (it.Pick != "") ? SubStr(it.Pick, InStr(it.Pick, ":") + 1) : ""
        fields := [
            {Id: "label", L: "It says", Kind: "text", V: it.Label, Hint: "An & marks the letter Alt picks it by: &Save."},
            {Id: "does", L: "Does", Kind: "choice", V: AxMenuUi.Guess(s, it, kind), Opts: AxMenuUi.ActOpts(s, kind)},
            {Id: "val", L: "The value", Kind: "choice", V: ck != "" ? ck : "new", Opts: (vals != "" ? vals "|" : "") "new:A new value...",
             When: (V) => V["does"] = "flip" || V["does"] = "pick"},
            {Id: "new", L: "Called", Kind: "text", V: ck != "" && !InStr("|" vals, "|" ck ":") ? ck : "darkMode",
             When: (V) => (V["does"] = "flip" || V["does"] = "pick") && V["val"] = "new"},
            {Id: "pv", L: "Set it to", Kind: "text", V: pv, When: (V) => V["does"] = "pick",
             Hint: "The items of one set share the value; the one ticked is the one it holds."},
            {Id: "code", L: "Code", Kind: "code", Rows: 3, V: it.Code, When: (V) => V["does"] = "code" || (V["does"] = "flip" && Trim(it.Code) != "")},
            {Id: "icon", L: "Picture", Kind: "pick", Icons: true, Scroll: true, V: it.Icon, Items: AxMenuUi.IconItems(kind)}]
        if (kind != "tray")
            fields.Push({Id: "key", L: "Shortcut shown", Kind: "text", V: it.Shortcut, Ph: "Ctrl+S",
                         Hint: "Written beside it. For the key itself to do it, add a hotkey (Logic > Hotkeys)."})
        fields.Push({Id: "off", L: "Greyed out", Kind: "flag", V: it.Off})
        if (kind = "tray")
            fields.Push({Id: "def", L: "The default: bold, and what a double-click on the icon does", Kind: "flag", V: it.Default})
        r := AxForm.Show(s, {Title: title != "" ? title : (it.Label != "" ? "Change the item" : "Add an item"), Icon: "E700", Width: 640,
            Intro: kind = "tray" ? "An item of the tray icon's menu (Windows' own menu, so its pictures come from Windows' files)."
                 : "An item of the menu, drawn in the program's own look.",
            Fields: fields, Buttons: [it.Label != "" ? "Save" : "Add it", "Cancel"],
            Check: (V) => Trim(V["label"]) = "" ? "Say what it says."
                 : ((V["does"] = "flip" || V["does"] = "pick") && V["val"] = "new" && AxProject.CleanName(V["new"]) = "") ? "Name the value."
                 : (V["does"] = "code" && Trim(V["code"]) = "") ? "Write the code, or pick something it does." : ""})
        if !r.Ok
            return ""
        V := r.V
        out := AxMenuUi.Blank(Trim(V["label"]))
        out.Items := it.Items
        out.Icon := V["icon"], out.Off := V["off"] ? true : false
        out.Shortcut := (kind != "tray") ? Trim(V["key"]) : ""
        out.Default := (kind = "tray" && V["def"]) ? true : false
        vn := (V["val"] = "new") ? AxProject.CleanName(V["new"]) : V["val"]
        switch V["does"] {
        case "flip":
            out.Check := vn, out.Code := Trim(V["code"])
            AxMenuUi.EnsureValue(s, vn, "false")
        case "pick":
            out.Pick := vn ":" Trim(V["pv"])
            AxMenuUi.EnsureValue(s, vn, AxLit.S(Trim(V["pv"])))
        case "code":
            out.Code := Trim(StrReplace(V["code"], "`r"), "`n")
        case "step":
            st := AxStepsUi.StepForm(s, "What it does", "", "", "What happens when this item is chosen.")
            if !IsObject(st)
                return ""
            out.Code := st.Code
        case "suspend":
            out.Code := (kind = "tray") ? "" : "Suspend(-1)"
            if (kind = "tray" && !RegExMatch(StrLower(out.Label), "^suspend"))
                out.Code := "Suspend(-1)"
        default:
            for a in AxMenuUi.Actions(s, kind)
                if (a.V = V["does"])
                    out.Code := a.Code
        }
        return out
    }
    ; a value a tick follows is one of the program's values (Logic > Values)
    static EnsureValue(s, name, init) {
        if (name = "")
            return
        for v in AxBind.Vars(s.P)
            if (v.Name = name)
                return
        try s.PutLine("Vars", "", name " = " init, false)
    }

    ; ============================================================ the clicks
    static Act(s, v) {
        p := StrSplit(v, "|", , 4)
        while (p.Length < 4)
            p.Push("")
        verb := p[1], kind := p[2], key := p[3], path := p[4]
        switch verb {
        case "ctxnew":    return AxMenuUi.NewCtx(s, kind)
        case "ctxon":     return AxMenuUi.CtxOn(s, key)
        case "ctxren":    return AxMenuUi.CtxRename(s, key)
        case "ctxdel":    return AxMenuUi.CtxDelete(s, key)
        case "barnew":
            s.Mark()
            s.P.W.Menus := "&File`n    E&xit | | ExitApp() | icon=E711`n&Help`n    &About | | " s.P.W.Var '.Toast("' AxProject.CleanName(s.P.W.Title) '")'
            s.QueueLive(), s.Reflect(false)
            return s.Status("msg", "A menu bar with File and Help. Click an item to change it.")
        case "traynew":   return AxMenuUi.TrayStart(s)
        case "trayicon":  return AxMenuUi.TrayIcon(s)
        }
        tree := AxMenuUi.Tree(s, kind, key)
        switch verb {
        case "add", "subm", "sep", "addin":
            list := tree
            if (verb = "addin") {
                at := AxMenuUi.At(tree, path)
                if !IsObject(at.It)
                    return
                list := at.It.Items
            }
            if (verb = "sep") {
                it := AxMenuUi.Blank("-"), it.Sep := true
                list.Push(it)
                return AxMenuUi.Save(s, kind, key, tree)
            }
            it := AxMenuUi.ItemForm(s, kind, AxMenuUi.Blank(), verb = "subm" ? "Add a submenu" : "")
            if !IsObject(it)
                return
            if (verb = "subm" && !it.Items.Length)
                it.Items.Push(AxMenuUi.Blank("New item")), it.Code := ""
            list.Push(it)
            AxMenuUi.Save(s, kind, key, tree)
            return s.Status("msg", "Added " it.Label (verb = "subm" ? ", with an item in it to change" : "") ".")
        }
        at := AxMenuUi.At(tree, path)
        if !IsObject(at.It)
            return
        L := at.List, i := at.I
        switch verb {
        case "edit":
            if L[i].Sep
                return
            it := AxMenuUi.ItemForm(s, kind, L[i])
            if !IsObject(it)
                return
            L[i] := it
        case "up", "down":
            j := i + (verb = "up" ? -1 : 1)
            if (j < 1 || j > L.Length)
                return
            x := L[i], L[i] := L[j], L[j] := x
        case "in":
            if (i < 2 || L[i - 1].Sep)
                return
            L[i - 1].Items.Push(L.RemoveAt(i))
        case "out":
            parts := StrSplit(path, ".")
            if (parts.Length < 2)
                return
            parent := AxMenuUi.At(tree, SubStr(path, 1, InStr(path, ".", , -1) - 1))
            it := L.RemoveAt(i)
            parent.List.InsertAt(parent.I + 1, it)
        case "del":
            if (L[i].Items.Length && !s.Confirm("Take out " L[i].Label " and the " L[i].Items.Length " items in it?", "Menus", "Take them out", "Keep them"))
                return
            L.RemoveAt(i)
        default:
            return
        }
        AxMenuUi.Save(s, kind, key, tree)
    }

    ; ====================================================== right-click menus
    ; Logic > Menus: this window's right-click menus and its menu bar.
    static Section(s, add) {
        W := s.P.W
        tops := AxChrome.Ctx(W.Ctx)
        head := AxMenuUi.Head("menus", "Menus (" tops.Length ")", "The menus of " AxTags.E(W.Name) ": what a right-click on a control "
              . "-- or anywhere -- opens, and the menu bar. Drawn in the program's own look; the tray icon's menu is in "
              . '<a class="axd-link" data-do="go.tray">App &gt; Tray icon</a>.',
              '<span class="axd-hbtn axd-go" data-mnu="ctxnew|">A right-click menu...</span>'
              . (Trim(W.Menus) = "" ? ' <span class="axd-hbtn" data-mnu="barnew|">A menu bar</span>' : ""))
        h := ""
        if !tops.Length
            h .= '<div class="axd-mstart"><span class="ico">&#xE700;</span><div><b>No right-click menus yet.</b> '
               . "A right-click in the program does nothing until it has one. Start from one of these:"
               . '<div class="axd-mtpl"><span class="axd-hbtn" data-mnu="ctxnew|text">For a text box: Cut, Copy, Paste, Select all</span>'
               . '<span class="axd-hbtn" data-mnu="ctxnew|window">For the whole window: Settings, About, Quit</span>'
               . '<span class="axd-hbtn" data-mnu="ctxnew|blank">An empty one</span></div></div></div>'
        for m in tops {
            on := (m.On = "") ? "only when a step shows it" : (m.On = "*" || m.On = "window") ? "a right-click anywhere in the window"
                : "a right-click on " m.On
            bad := (m.On != "" && m.On != "*" && m.On != "window" && !IsObject(s.P.FindByName(m.On)))
            h .= '<div class="axd-mcard"><div class="axd-mhead"><span class="ico">&#xE700;</span><b>' AxTags.E(m.Name) '</b>'
               . '<span class="axd-mon' (bad ? " bad" : "") '" data-mnu="ctxon|ctx|' AxTags.E(m.Name) '" title="What it opens on">'
               . 'opens on ' AxTags.E(on) (bad ? " -- there is no control called that" : "") ' <span class="ico">&#xE70F;</span></span>'
               . '<span class="axd-mhtools"><span class="axd-ract" data-mnu="ctxren|ctx|' AxTags.E(m.Name) '">Rename</span>'
               . '<span class="axd-ract axd-mdel" data-mnu="ctxdel|ctx|' AxTags.E(m.Name) '">Remove</span></span></div>'
               . AxMenuUi.Editor(s, "ctx", m.Name, m.Items)
               . '<div class="axd-mcode">In code or a step: <code>' AxTags.E(AxChrome.CtxFn(W, m.Name)) '()</code> gives its items; '
               . '<code>' AxTags.E(W.Var) '.ShowMenu(' AxTags.E(AxChrome.CtxFn(W, m.Name)) '())</code> opens it where the pointer is.</div></div>'
        }
        if (Trim(W.Menus) != "")
            h .= '<div class="axd-mcard"><div class="axd-mhead"><span class="ico">&#xE700;</span><b>The menu bar</b>'
               . '<span class="axd-mon">along the top of the window; each top line is one of its menus</span></div>'
               . AxMenuUi.Editor(s, "bar", "", AxChrome.Menus(W.Menus)) '</div>'
        raw := add({Id: "lg_ctx", L: "Right-click menus, as text", Kind: "multiline", Rows: 6,
                    Get: (*) => W.Ctx, Set: (v) => (W.Ctx := v, s.QueueLive())})
             . '<div class="axd-note"><b>name | what it opens on</b> (a control, or * for the window), then its items indented: '
             . '<b>Label | shortcut | code | flags</b> -- flags: icon=E8C6 check=value pick=value:this off.</div>'
        return head '<div class="axd-rpcontent">' (AxLogic.Raw.Has("menus") ? raw : h) '</div>'
    }
    ; a section's heading, with the switch between it and its text
    static Head(key, title, lead, tools) {
        raw := AxLogic.Raw.Has(key)
        return AxPanes.PanelHead(title, lead, tools ' <span class="axd-hbtn' (raw ? " on" : "") '" data-do="logic.raw.' key '">'
             . (raw ? "Back to the menu" : "Edit as text") '</span>')
    }
    static NewCtx(s, how) {
        W := s.P.W
        ctls := AxWiz.CtlOpts(s)
        pick := "window:A right-click anywhere in the window" (ctls != "" ? "|" ctls : "") "|none:Only when a step shows it"
        sel := s.Primary()
        want := (how = "window") ? "window" : (IsObject(sel) && sel.Name != "") ? sel.Name
              : (how = "text" && ctls != "") ? AxForm.FirstOpt(ctls) : "window"
        base := (how = "text") ? "textMenu" : (how = "window") ? "windowMenu" : "menu"
        name := base, n := 2
        while AxMenuUi.HasCtx(W, name)
            name := base n++
        r := AxForm.Show(s, {Title: "A right-click menu", Icon: "E700", Width: 520,
            Intro: "Its items come next; they can be changed at any time.",
            Fields: [{Id: "name", L: "Called", Kind: "text", V: name, Hint: "For your code and steps: " W.Var "_Menu_<name>()"},
                     {Id: "on", L: "Opens on", Kind: "choice", V: want, Opts: pick}],
            Buttons: ["Make it", "Cancel"],
            Check: (V) => AxProject.CleanName(V["name"]) = "" ? "Name it."
                 : AxMenuUi.HasCtx(W, AxProject.CleanName(V["name"])) ? "There is one called that already." : ""})
        if !r.Ok
            return
        nm := AxProject.CleanName(r.V["name"])
        on := (r.V["on"] = "window") ? "*" : (r.V["on"] = "none") ? "" : r.V["on"]
        items := ""
        switch how {
        case "text":
            items := "`n    Cu&t | Ctrl+X | Send(" Chr(34) "^x" Chr(34) ") | icon=E8C6"
                   . "`n    &Copy | Ctrl+C | Send(" Chr(34) "^c" Chr(34) ") | icon=E8C8"
                   . "`n    &Paste | Ctrl+V | Send(" Chr(34) "^v" Chr(34) ") | icon=E77F"
                   . "`n    -`n    Select &all | Ctrl+A | Send(" Chr(34) "^a" Chr(34) ")"
        case "window":
            items := "`n    &Settings | | " W.Var ".Toast(" Chr(34) "Settings" Chr(34) ") | icon=E713"
                   . "`n    &About | | " W.Var ".Toast(" AxLit.S(W.Title != "" ? W.Title : W.Name) ") | icon=E946"
                   . "`n    -`n    &Quit | | ExitApp() | icon=E711"
        default:
            items := "`n    New item"
        }
        s.Mark()
        W.Ctx := RTrim(RTrim(String(W.Ctx), "`r`n") (Trim(W.Ctx) = "" ? "" : "`n") nm (on != "" ? " | " on : "") items, "`n")
        s.LogicSec := "menus"
        s.QueueLive()
        s.Reflect(false)
        s.Status("msg", "A right-click menu called " nm ". Click an item to change what it does.")
    }
    static HasCtx(W, name) {
        for m in AxChrome.Ctx(W.Ctx)
            if (m.Name = name)
                return true
        return false
    }
    static CtxOn(s, key) {
        W := s.P.W
        ctls := AxWiz.CtlOpts(s)
        cur := ""
        for m in AxChrome.Ctx(W.Ctx)
            if (m.Name = key)
                cur := (m.On = "*" || m.On = "window") ? "window" : (m.On = "") ? "none" : m.On
        r := AxForm.Show(s, {Title: "What " key " opens on", Icon: "E700", Width: 480,
            Fields: [{Id: "on", L: "Opens on", Kind: "choice", V: cur,
                      Opts: "window:A right-click anywhere in the window" (ctls != "" ? "|" ctls : "") "|none:Only when a step shows it"}],
            Buttons: ["Save", "Cancel"]})
        if !r.Ok
            return
        on := (r.V["on"] = "window") ? "*" : (r.V["on"] = "none") ? "" : r.V["on"]
        AxMenuUi.SetTop(s, key, key, on)
    }
    static CtxRename(s, key) {
        r := AxForm.Show(s, {Title: "Rename " key, Icon: "E700", Width: 420,
            Fields: [{Id: "name", L: "Called", Kind: "text", V: key}], Buttons: ["Rename", "Cancel"],
            Check: (V) => AxProject.CleanName(V["name"]) = "" ? "Name it." : ""})
        if r.Ok
            AxMenuUi.SetTop(s, key, AxProject.CleanName(r.V["name"]), "")
    }
    ; rename a right-click menu and/or change what it opens on (on "" keeps it,
    ; unless the name is unchanged -- then it is what it opens on)
    static SetTop(s, key, name, on) {
        W := s.P.W
        tops := AxChrome.Menus(W.Ctx)
        for m in tops
            if (AxProject.CleanName(m.Label) = key) {
                if (name != key)
                    m.Label := name
                else
                    m.Shortcut := on
            }
        s.Mark()
        W.Ctx := AxMenuUi.CtxText(tops)
        s.QueueLive()
        s.Reflect(false)
    }
    static CtxDelete(s, key) {
        if !s.Confirm("Remove the right-click menu " key "?", "Menus", "Remove", "Keep it")
            return
        W := s.P.W
        tops := AxChrome.Menus(W.Ctx)
        keep := []
        for m in tops
            if (AxProject.CleanName(m.Label) != key)
                keep.Push(m)
        s.Mark()
        W.Ctx := AxMenuUi.CtxText(keep)
        s.QueueLive()
        s.Reflect(false)
    }

    ; ================================================================ the tray
    ; App > Tray icon: the icon itself (Windows' own files, or yours), what
    ; hovering says, what a click does, and its menu in the same editor.
    static TraySection(s, add) {
        set := Trim(String(s.P.Tray)) != ""
        cfg := AxAsset.Tray(s.P)
        tools := set ? '<span class="axd-hbtn" data-do="tray.edit">Everything at once...</span>' : ""
        lead := "The small icon by the clock, and the menu a right-click on it opens -- "
              . "Windows' own menu, so it looks like every other program's. A window that starts hidden is brought up from here."
        h := ""
        if !set {
            h := AxPanes.PanelHead("Tray icon", lead)
            h .= '<div class="axd-mstart"><span class="ico">&#xE8B7;</span><div><b>AutoHotkey&#39;s own icon and menu</b> '
               . "(the green H, with Pause and Exit). Give the program its own:"
               . '<div class="axd-mtpl"><span class="axd-hbtn axd-go" data-mnu="traynew|">Its own icon and menu</span>'
               . '<span class="axd-hbtn" data-do="tray.edit">No tray icon at all...</span></div></div></div>'
            return h
        }
        ico := (cfg.Icon != "") ? AxMenuUi.IconUri(cfg.Icon) : ""
        h .= '<div class="axd-trayhead"><div class="axd-trayicon" data-mnu="trayicon|" title="Change the icon">'
           . (ico != "" ? '<img src="' ico '">' : '<span class="ico">&#xE8B7;</span>') '</div><div class="axd-traywhat">'
           . '<b>' (cfg.Show ? (cfg.Tip != "" ? AxTags.E(cfg.Tip) : "No tooltip") : "No tray icon") '</b>'
           . '<span>' (cfg.Icon != "" ? AxTags.E(cfg.Icon) : "AutoHotkey&#39;s icon") ' -- <a class="axd-link" data-mnu="trayicon|">change it</a></span></div></div>'
        if !cfg.Show
            return AxPanes.PanelHead("Tray icon", lead, tools) h
                 . '<div class="axd-note">With no icon there is no tray menu, so nothing to quit it from: give it another '
                 . 'way out (a button, a hotkey). <a class="axd-link" data-do="tray.edit">Show one again</a></div>'
        opts := "menu:Opens the menu (a double-click does the bold one)|default:Does the bold one"
        for it in cfg.Tree
            if (!it.Sep && !it.Items.Length)
                opts .= "|" StrReplace(it.Label, "|", "/") ":Does " StrReplace(RegExReplace(it.Label, "&"), "|", "/")
        h .= '<div class="axd-rpform">'
           . add({Id: "tr_tip", L: "Hovering says", Kind: "text", Get: (*) => AxAsset.Tray(s.P).Tip,
                  Set: AxMenuUi.TraySetFn(s, "Tip")})
           . add({Id: "tr_click", L: "One click", Kind: "choice", Opts: opts,
                  Get: (*) => (AxAsset.Tray(s.P).Click = "" ? "menu" : AxAsset.Tray(s.P).Click),
                  Set: AxMenuUi.TraySetFn(s, "Click")})
           . '</div>'
        h .= '<div class="axd-rpsub">Its menu</div>' AxMenuUi.Editor(s, "tray", "", cfg.Tree)
           . '<div class="axd-note">With no code, <b>Show</b>, <b>Hide</b>, <b>Toggle</b>, <b>Exit</b>, <b>Reload</b>, '
           . '<b>Suspend hotkeys</b>, <b>Pause</b> and <b>Open the folder</b> do what they say.</div>'
        raw := add({Id: "lg_tray", L: "One per line", Kind: "multiline", Rows: 6,
                    Get: (*) => s.P.Tray, Set: (v) => (s.P.Tray := v, s.QueueLive())})
             . '<div class="axd-note"><b>show</b>, <b>icon</b>, <b>tip</b>, <b>click</b> as <b>name = value</b>; every other '
             . 'line is an item, <b>Label | code | flags</b>, indented under another for a submenu.</div>'
        return AxMenuUi.Head("tray", "Tray icon", lead, tools) '<div class="axd-rpcontent">' (AxLogic.Raw.Has("tray") ? raw : h) '</div>'
    }
    static TraySetFn(s, what) => (v) => AxMenuUi.TraySet(s, what, v)
    static TraySet(s, what, v) {
        cfg := AxAsset.Tray(s.P)
        v := Trim(String(v))
        cfg.%what% := (what = "Click" && v = "menu") ? "" : v
        s.P.Tray := AxAsset.TrayText(cfg)
        s.QueueLive()
    }
    static TrayStart(s) {
        s.Mark()
        t := s.P.Main().Title != "" ? s.P.Main().Title : "My program"
        s.P.Tray := "show = yes`ntip = " t "`nicon = shell32.dll,43`nclick = Show"
                  . "`nShow | | icon=shell32.dll,15`nSuspend hotkeys`n-`nOpen the folder | | icon=shell32.dll,3`nExit | | icon=shell32.dll,27"
        s.AppSec := "tray"
        s.QueueLive()
        s.Reflect(false)
        s.Status("msg", "The program has its own tray icon and menu now. Click an item to change it.")
    }
    static TrayIcon(s) {
        cfg := AxAsset.Tray(s.P)
        own := (cfg.Icon != "" && !InStr(cfg.Icon, ".dll,")) ? cfg.Icon : ""
        r := AxForm.Show(s, {Title: "The tray icon", Icon: "E8B7", Width: 640,
            Intro: "One of Windows' own, or a picture of yours (.ico, or a .exe or .dll with the icon's number).",
            Fields: [{Id: "pick", L: "Windows' own", Kind: "pick", Icons: true, Scroll: true, V: own = "" ? cfg.Icon : "",
                      Items: AxMenuUi.IconItems("tray")},
                     {Id: "file", L: "Or yours", Kind: "text", V: own, Ph: "app.ico, or myapp.exe,0",
                      Hint: "Without a folder it is beside the program. Carry it with the program in App > Files."}],
            Buttons: ["Use it", "Cancel"]})
        if !r.Ok
            return
        cfg.Icon := Trim(r.V["file"]) != "" ? Trim(r.V["file"]) : r.V["pick"]
        s.Mark()
        s.P.Tray := AxAsset.TrayText(cfg)
        s.QueueLive()
        s.Reflect(false)
    }
}
