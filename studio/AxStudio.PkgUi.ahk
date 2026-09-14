#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Pkg.ahk
#Include %A_LineFile%\..\AxStudio.Panes.ahk
#Include %A_LineFile%\..\AxStudio.Form.ahk
#Include %A_LineFile%\..\AxStudio.App.ahk
#Include %A_LineFile%\..\AxStudio.Update.ahk

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
;  AxStudio.PkgUi.ahk -- App > Libraries, and the libraries in the Code
;  workspace.
;
;  Libraries is a search over every library Aris lists, and ours: typed
;  words, a category, or only the ones this project has. Picking one shows
;  what it is, what to be careful of, its ready snippets, and -- once it is
;  installed -- what it offers, read out of its own files. Install, remove
;  and update go through Aris (AxStudio.Pkg.ahk); a library installed is a
;  library the script includes.
;
;  In the Code workspace the navigator lists the libraries the script uses;
;  opened, one lists its classes, methods and functions, and a click writes
;  the call where the cursor is.
;
;  Every click here arrives as data-pkg="verb|argument" (Panes.WsClick and
;  App.CodeNavClick hand it on), and only the list and the details are
;  redrawn while searching, so the box keeps its focus and its caret.
; =============================================================================
class AxPkgUi {
    static Q := ""                 ; the words typed
    static Cat := ""               ; a category id, or "" for all
    static Mine := false           ; only this project's
    static Show := "all"           ; all | rec | nocode | code -- the shelf picked
    static Sort := "best"          ; best (recommended first) | az
    static Hidden := false         ; show the ones the patch leaves out
    static Sel := ""               ; the library shown
    static Open := Map()           ; libraries opened in the Code navigator
    static Max := 120              ; rows drawn at once

    ; --------------------------------------------------------- the section
    ; Three columns, the way a store is laid out: what to show down the left
    ; (a shelf -- recommended, works without code, has ready code, this
    ; project's -- then a category), the libraries in the middle, the one
    ; picked on the right. The search box is over all three.
    static Tab := "ahk"            ; ahk | net | mine
    static Section(s) {
        E := (t) => AxTags.E(t)
        tools := AxPkg.HasAris() && AxPkg.IndexOverride = ""
            ? '<span class="axd-hbtn" data-pkg="refresh" title="Fetch Aris&#39;s list of libraries again">Refresh the list</span> '
            . '<span class="axd-hbtn" data-pkg="checkup" title="Newer versions of this project&#39;s libraries, of Aris, and of the studio">Check for updates</span> '
            . '<span class="axd-hbtn" data-pkg="folder">Open the Lib folder</span>' : ""
        h := AxPanes.PanelHead("Libraries", "What other people have already made, ready for your program -- and "
              . "any of it one of your functions, which is a step in every rule and flowchart.", tools)
        ; three ways in: AutoHotkey's own libraries, all of .NET, and what
        ; this program already uses of either
        mine := AxPkg.Used(s.P).Length + AxNet.List(s.P).Length
        tab := (key, ico, label, n := "") => '<span class="axd-lbtab' (AxPkgUi.Tab = key ? " on" : "") '" data-pkg="tab|' key '">'
            . '<span class="ico">&#x' ico ';</span>' label (n != "" ? '<i>' n '</i>' : "") '</span>'
        h .= '<div class="axd-lbtabs">' tab("ahk", "E82D", "AutoHotkey libraries", AxPkg.HasAris() ? AxPkg.Counts().All : "")
           . tab("net", "E943", ".NET, through AHK#", "new") tab("mine", "E73E", "In this program", mine) '</div>'
        if (AxPkgUi.Tab = "net")
            return h AxNetUi.Section(s)
        if (AxPkgUi.Tab = "mine")
            return h AxPkgUi.MineTab(s)
        if !AxPkg.HasAris() && AxPkg.IndexOverride = ""
            return h '<div class="axd-pkget"><span class="ico">&#xE896;</span><div>'
                 . '<b>Libraries come through Aris</b>, the AutoHotkey package manager by Descolada. '
                 . "It is not here yet: getting it downloads about 2 MB from github.com/Descolada/Aris "
                 . "into " E(AxPkg.Dir()) ". It changes nothing else on this machine."
                 . '<div class="axd-pkbtns"><span class="axd-hbtn axd-go" data-pkg="getaris">Get Aris</span> '
                 . '<span class="axd-hbtn" data-pkg="web|https://github.com/Descolada/Aris">What is it?</span>'
                 . '</div></div></div>'
        dir := AxPkg.ProjDir(s.P)
        if (dir = "")
            h .= '<div class="axd-note axd-pkwarn"><span class="ico">&#xE7BA;</span> Save the project to install one: '
               . "its libraries go in a Lib folder beside the project file.</div>"
        h .= '<div class="axd-pkbar"><span class="ico axd-pkq">&#xE721;</span>'
           . '<input id="axdPkgFind" class="axd-rfindbox" autocomplete="off" '
           . 'placeholder="What should it do? -- json, click a button in another program, screenshot, sqlite..." value="' E(AxPkgUi.Q) '">'
           . '</div>'
           . '<div class="axd-pkcols">'
           . '<div class="axd-pkside" id="axdPkgCats">' AxPkgUi.CatsHtml(s) '</div>'
           . '<div class="axd-pklist" id="axdPkgList">' AxPkgUi.ListHtml(s) '</div>'
           . '<div class="axd-pkinfo" id="axdPkgInfo">' AxPkgUi.InfoHtml(s) '</div></div>'
        age := AxPkg.IndexAge(), n := AxPkg.Counts()
        h .= '<div class="axd-note axd-dim">' n.All ' libraries from Aris&#39;s list'
           . (age >= 0 ? ", fetched " (age < 1 ? "within the hour" : age < 48 ? age " hours ago" : Round(age / 24) " days ago") : "")
           . (AxPkg.HasAris() && AxPkg.IndexOverride = "" ? ' -- <a class="axd-link" data-pkg="refresh">fetch it again</a>' : "")
           . '. Categories, recommendations and cautions are AxStudio&#39;s own (studio\packages\patch.json).'
           . (n.Hidden ? '<br>' n.Hidden ' that build windows are left out: ' E(AxPkg.HiddenWhy) ' <a class="axd-link" data-pkg="hidden">'
                . (AxPkgUi.Hidden ? "Leave them out" : "Show them anyway") '</a>' : "") '</div>'
        return h
    }
    ; What this program uses, in one place: its libraries, what each lets a
    ; rule do without code, and its adaptors -- each a way to use it now.
    static MineTab(s) {
        E := (t) => AxTags.E(t)
        dir := AxPkg.ProjDir(s.P), have := AxPkg.Installed(dir)
        used := AxPkg.Used(s.P), ad := AxNet.List(s.P)
        if (!used.Length && !ad.Length)
            return '<div class="axd-rpempty"><span class="ico axd-rpbig">&#xE82D;</span><div class="axd-rpemptyt">Nothing yet</div>'
                 . '<div class="axd-rpemptyb"><span class="axd-hbtn" data-pkg="tab|ahk">Find an AutoHotkey library</span> '
                 . '<span class="axd-hbtn" data-pkg="tab|net">Use something from .NET</span></div></div>'
        h := ""
        if used.Length {
            old := AxUpdate.Outdated(s)
            h .= '<div class="axd-rpsub">Libraries (' used.Length ')'
               . (old.Length ? ' <span class="axd-hbtn axd-go" data-pkg="updateall">Update ' (old.Length = 1 ? old[1] : "all " old.Length) '</span>' : "")
               . '</div>'
            for name in used {
                pk := AxPkg.Find(name)
                st := have.Has(name) ? AxPkgUi.HaveTag(name, "installed") : '<b class="axd-pkbad">not installed yet</b>'
                steps := ""
                if IsObject(pk)
                    for x in pk.Steps
                        steps .= (steps = "" ? "" : " &#183; ") E(x.L)
                h .= '<div class="axd-lbmine"><div class="axd-pkname">' st '<b>' E(IsObject(pk) ? pk.Short : name) '</b><span>' E(name) '</span></div>'
                   . (IsObject(pk) ? '<div class="axd-pkdesc">' E(pk.Desc) '</div>' : "")
                   . (steps != "" ? '<div class="axd-lbsteps"><span class="ico">&#xE945;</span>In a rule, without code: ' steps '</div>' : "")
                   . '<div class="axd-lbacts"><span class="axd-ract" data-pkg="goto|' E(name) '">Open it</span>'
                   . (name = AxPkg.UiaLib ? '<span class="axd-ract" data-pkg="uiapick">Pick an element on screen...</span>' : "")
                   . '<span class="axd-ract" data-pkg="unuse|' E(name) '">Stop using it</span></div></div>'
            }
        }
        if ad.Length {
            h .= '<div class="axd-rpsub">Your adaptors (' ad.Length ') -- each one of your functions</div>'
            for a in ad
                h .= '<div class="axd-lbmine"><div class="axd-pkname"><b>' E(a.Name) '()</b><span>' E(a.Kind = "ahk" ? a.Source
                   : a.Kind = "nuget" ? "NuGet " a.Source : ".NET") '</span></div>'
                   . '<div class="axd-pkdesc">' E(a.Doc) ' -- takes ' E(AxNet.Words(a.Params)) '</div>'
                   . '<div class="axd-lbacts"><span class="axd-ract" data-do="steps.show">Use it in a step</span>'
                   . '<span class="axd-ract" data-pkg="net.del|' E(a.Name) '">Take it out</span></div></div>'
        }
        return h
    }
    ; Down the left: the shelves, then the categories, then the order.
    static CatsHtml(s := "") {
        n := AxPkg.Counts()
        mine := 0
        if IsObject(s)
            mine := AxPkgUi.MineMap(s, AxPkg.Installed(AxPkg.ProjDir(s.P))).Count
        cur := AxPkgUi.Mine ? "mine" : AxPkgUi.Show
        it := (key, ico, label, cnt, tip) => '<div class="axd-pkshelf' (cur = key ? " on" : "") '" data-pkg="show|' key
            . '" title="' tip '"><span class="ico">&#x' ico ';</span><span class="axd-pkst">' label '</span><i>' cnt '</i></div>'
        h := '<div class="axd-pkhead">Show</div>'
           . it("all", "E8FD", "Everything", n.All, "Every library, the recommended ones first")
           . it("rec", "E734", "Recommended", n.Rec, "Work well and are easy to use -- a good place to start")
           . it("nocode", "E945", "Works without code", n.NoCode, "Adds steps you can pick in a rule or a macro")
           . it("code", "E943", "Has ready code", n.Code, "Comes with lines of code ready to drop in")
           . (IsObject(s) ? it("mine", "E73E", "In this project", mine, "Installed here, or used by the script") : "")
        h .= '<div class="axd-pkhead">Category</div>'
           . '<div class="axd-pkshelf' (AxPkgUi.Cat = "" ? " on" : "") '" data-pkg="cat|">'
           . '<span class="ico">&#xE71D;</span><span class="axd-pkst">Any</span></div>'
        for c in AxPkg.Cats()
            if c.N
                h .= '<div class="axd-pkshelf' (AxPkgUi.Cat = c.Id ? " on" : "") '" data-pkg="cat|' c.Id '">'
                   . '<span class="ico">&#x' c.Icon ';</span><span class="axd-pkst">' AxTags.E(c.Label) '</span><i>' c.N '</i></div>'
        h .= '<div class="axd-pkhead">Order</div><div class="axd-pksort">'
           . '<span class="' (AxPkgUi.Sort = "best" ? "on" : "") '" data-pkg="sort|best">Best first</span>'
           . '<span class="' (AxPkgUi.Sort = "az" ? "on" : "") '" data-pkg="sort|az">A to Z</span></div>'
        return h
    }
    static ListHtml(s) {
        dir := AxPkg.ProjDir(s.P)
        have := AxPkg.Installed(dir)
        list := AxPkg.Filter(AxPkgUi.Q, AxPkgUi.Cat, AxPkgUi.Mine ? AxPkgUi.MineMap(s, have) : "",
                             {Show: AxPkgUi.Mine ? "all" : AxPkgUi.Show, Sort: AxPkgUi.Sort, Hidden: AxPkgUi.Hidden})
        if !list.Length
            return '<div class="axd-empty-pane">' (AxPkgUi.Mine ? "This project has no libraries yet."
                   : "Nothing matches. Fewer words, or another shelf or category.") '</div>'
        ; with the best first and nothing narrowing it, the recommended ones
        ; get a heading of their own, so the split is plain to see
        heads := AxPkgUi.Sort = "best" && AxPkgUi.Show = "all" && !AxPkgUi.Mine
        h := "", was := -1
        for i, e in list {
            if (i > AxPkgUi.Max) {
                h .= '<div class="axd-note axd-dim">' (list.Length - AxPkgUi.Max) ' more -- a word or two narrows it.</div>'
                break
            }
            if heads && (e.Rank ? 1 : 0) != was {
                was := e.Rank ? 1 : 0
                h .= '<div class="axd-pkhead axd-pklh">' (was ? "Recommended" : "Everything else") '</div>'
            }
            h .= AxPkgUi.Row(s, e, have)
        }
        return h
    }
    static Row(s, pk, have) {
        Esc := (t) => AxTags.E(t)
        on := (pk.Name = AxPkgUi.Sel)
        tag := have.Has(pk.Name) ? AxPkgUi.HaveTag(pk.Name, AxPkg.IsUsed(s.P, pk.Name) ? "in use" : "installed")
             : AxPkg.IsUsed(s.P, pk.Name) ? '<b class="axd-pkbad">not installed</b>' : ""
        n := pk.Snippets.Length
        badges := (pk.Rank ? '<span class="axd-pkb axd-pkbrec"><span class="ico">&#xE734;</span>recommended</span>' : "")
                . (pk.Steps.Length ? '<span class="axd-pkb axd-pkbnc"><span class="ico">&#xE945;</span>works without code</span>' : "")
                . (n ? '<span class="axd-pkb">' n ' ready ' (n = 1 ? "snippet" : "snippets") '</span>' : "")
        return '<div class="axd-pkrow' (on ? " on" : "") (pk.Rank ? " rec" : "") '" data-pkg="sel|' Esc(pk.Name) '">'
             . '<div class="axd-pkname">' tag '<b>' Esc(pk.Short) '</b><span>' Esc(pk.Author) '</span>'
             . (pk.Warn ? '<span class="ico axd-pkcaut" title="' Esc(pk.Notes) '">&#xE7BA;</span>' : "")
             . (pk.Extra ? '<span class="axd-pkx">AxStudio&#39;s list</span>' : "") '</div>'
             . '<div class="axd-pkdesc">' Esc(pk.Why != "" ? pk.Why : pk.Desc) '</div>'
             . (badges != "" ? '<div class="axd-pkbs">' badges '</div>' : "") '</div>'
    }
    ; installed -- and a newer version, once Check for updates has found one
    static HaveTag(name, word) {
        v := AxUpdate.Latest(name)
        return (v != "") ? '<b class="axd-pkupd" title="Update it: ' AxTags.E(name) ' ' AxTags.E(v) ' is out">' AxTags.E(v) ' is out</b>'
                         : '<b class="axd-pkin">' word '</b>'
    }
    ; "In this project": installed here, or named by the script
    static MineMap(s, have) {
        m := Map()
        m.CaseSense := false
        for n, v in have
            m[n] := true
        for n in AxPkg.Used(s.P)
            m[n] := true
        return m
    }

    static InfoHtml(s) {
        Esc := (t) => AxTags.E(t)
        e := (AxPkgUi.Sel != "") ? AxPkg.Find(AxPkgUi.Sel) : ""
        if !IsObject(e)
            return '<div class="axd-pkhint"><span class="ico">&#xE82D;</span>Pick one to see what it is, '
                 . "what it offers and how to use it.</div>"
        dir := AxPkg.ProjDir(s.P)
        have := AxPkg.Installed(dir)
        inst := have.Has(e.Name), used := AxPkg.IsUsed(s.P, e.Name)
        busy := AxPkg.Busy()
        h := '<div class="axd-pkhd"><b>' Esc(e.Short) '</b><span>by ' Esc(e.Author) '</span></div>'
           . '<div class="axd-pktext">' Esc(e.Desc) '</div>'
        if (e.Why != "")
            h .= '<div class="axd-pknote axd-pkwhy"><span class="ico">&#xE734;</span><b>Recommended.</b> ' Esc(e.Why) '</div>'
        if e.Hidden
            h .= '<div class="axd-pknote axd-pkwarn"><span class="ico">&#xE7BA;</span>' Esc(e.HideWhy != "" ? e.HideWhy : AxPkg.HiddenWhy) '</div>'
        chips := ""
        for id in e.Cats
            chips .= '<span class="axd-pkchip" data-pkg="cat|' id '">' Esc(AxPkg.CatLabel(id)) '</span>'
        for k in e.Keywords
            chips .= '<span class="axd-pkchip axd-pkkw" data-pkg="q|' Esc(k) '">' Esc(k) '</span>'
        if (chips != "")
            h .= '<div class="axd-pkchips">' chips '</div>'
        if (e.Notes != "")
            h .= '<div class="axd-pknote' (e.Warn ? " axd-pkwarn" : "") '"><span class="ico">&#x'
               . (e.Warn ? "E7BA" : "E946") ';</span>' Esc(e.Notes) '</div>'
        if e.Script
            h .= '<div class="axd-pknote"><span class="ico">&#xE946;</span>Aris runs a short script of the '
               . "library's own after downloading it, to tidy its files. The clipboard is put back afterwards.</div>"
        ; what can be done with it
        b := ""
        if (busy != "")
            b .= '<span class="axd-dim">Aris is busy with ' Esc(busy) '...</span>'
        else if (dir = "")
            b .= '<span class="axd-hbtn axd-go" data-pkg="save">Save the project, then install</span>'
        else if !inst
            b .= '<span class="axd-hbtn axd-go" data-pkg="install|' Esc(e.Name) '">Install and use it</span>'
        else {
            b .= used ? '<span class="axd-hbtn" data-pkg="unuse|' Esc(e.Name) '">Stop including it</span> '
                      : '<span class="axd-hbtn axd-go" data-pkg="use|' Esc(e.Name) '">Include it in the script</span> '
            nv := AxUpdate.Latest(e.Name)
            b .= '<span class="axd-hbtn' (nv != "" ? " axd-go" : "") '" data-pkg="update|' Esc(e.Name) '">'
               . (nv != "" ? "Update to " Esc(nv) : "Update") '</span> '
               . '<span class="axd-hbtn" data-pkg="remove|' Esc(e.Name) '">Remove</span>'
        }
        if (e.Homepage != "")
            b .= ' <span class="axd-hbtn" data-pkg="web|' Esc(e.Homepage) '">Its page</span>'
        h .= '<div class="axd-pkbtns">' b '</div>'
        kv := (k, v) => (v = "") ? "" : '<div class="axd-kv"><span>' k '</span>' Esc(v) '</div>'
        deps := ""
        for d in e.Deps
            deps .= (deps = "" ? "" : ", ") d
        h .= kv("Licence", e.License != "" ? e.License : "not stated")
           . kv("Also brings", deps)
           . kv("Here", inst ? "version " have[e.Name] " in Lib\Aris" : "")
           . kv("The script", used ? "#Include <Aris/" e.Name ">" : "")
        ; what it lets a rule or a macro do, with no code: its steps, as they
        ; read in the "does" list
        if e.Steps.Length {
            h .= '<div class="axd-rpsub">Works without code</div>'
               . '<div class="axd-note">Once it is installed these are steps like any other: pick them in what a '
               . '<a class="axd-link" data-do="go.rules">rule</a> or a <a class="axd-link" data-do="go.macros">macro</a> does.</div>'
            for st in e.Steps
                h .= '<div class="axd-pkstep"><span class="ico">&#xE945;</span><b>' Esc(st.L) '</b>'
                   . '<code>' Esc(st.V (st.Arg ? " " st.ArgL : "")) '</code></div>'
        }
        if e.Snippets.Length {
            where := AxPkgUi.WhereWords(s)
            h .= '<div class="axd-rpsub">Ready to use</div>'
               . '<div class="axd-note">A click adds one to <b>' Esc(where) '</b>'
               . (inst ? "." : ", and offers to install " Esc(e.Short) " first -- the code needs it.") '</div>'
            for i, sn in e.Snippets
                h .= '<div class="axd-pksnip" data-pkg="snip|' i '" title="Add it to ' Esc(where) '">'
                   . '<div><span class="ico">&#xE710;</span>' Esc(sn.Name) '<span class="axd-pksnipgo">Add it</span></div><pre>' Esc(sn.Code) '</pre></div>'
        }
        ; what it can do, read from its source for AxStudio's list: each one
        ; written into the code with a click, or made a step of your own --
        ; before it is even installed (installing is offered as it is needed)
        if (e.Fn.Length && !inst) {
            h .= '<div class="axd-rpsub">What it can do (' e.Fn.Length ')</div>'
               . '<div class="axd-note">Click one to put it in the code, or make it a step you can pick in any rule or flowchart.</div>'
            for i, f in e.Fn
                h .= AxPkgUi.FnRow(e, f, i)
        }
        if inst {
            api := AxPkg.Api(dir, e.Name)
            h .= '<div class="axd-rpsub">What it offers (' api.Length ')</div>'
            if !api.Length
                h .= '<div class="axd-note axd-dim">' (AxHost.Ready ? "The parser found no classes or functions in it."
                     : "The parser (studio\bin\AstHost.exe) is not here, so what it offers cannot be read.") '</div>'
            for i, it in api {
                if (i > 80) {
                    h .= '<div class="axd-note axd-dim">and ' (api.Length - 80) ' more</div>'
                    break
                }
                h .= AxPkgUi.ApiRow(it, "api|" i)
            }
        }
        return h
    }
    static FnRow(pk, f, i) {
        E := (t) => AxTags.E(t)
        can := AxPkgUi.FnCan(pk, f)
        return '<div class="axd-pkapi axd-pk-function" data-pkg="fnwrite|' i '" title="' E(f.Name f.Sig) '">'
             . (can ? '<span class="axd-ract axd-pkmake" data-pkg="fnadapt|' i '" title="Make it one of your functions -- a step in any rule or flowchart">Make it a step</span>' : "")
             . '<span class="ico">&#xE943;</span><b>' E(f.Name) '</b><span class="axd-sig">' E(f.Sig) '</span>'
             . '<div>' E(f.Does) (f.Returns != "" ? " -- gives " E(f.Returns) : "") '</div></div>'
    }
    ; A function, or a method called on the class itself (UIA.ElementFromHandle)
    ; -- not one of something made first (Element.Click), which has nothing
    ; to be called on. The list names both the same way, so a method counts
    ; when it belongs to the library's own class or its examples call it so.
    static FnCan(e, f) {
        if (f.Sig = "" || !RegExMatch(f.Name, "^[A-Za-z_]\w*(\.[A-Za-z_]\w*)?$"))
            return false
        p := StrSplit(f.Name, ".")
        if (p.Length = 1)
            return true
        if (StrLower(p[1]) = StrLower(RegExReplace(e.Short, "[^A-Za-z0-9_]")))
            return true
        for sn in e.Snippets
            if InStr(sn.Code, f.Name "(")
                return true
        for st in e.Steps
            if InStr(st.Code, f.Name "(")
                return true
        return false
    }
    static FnItem(f) {
        p := StrSplit(f.Name, ".")
        return {Kind: p.Length > 1 ? "method" : "function", Name: p[p.Length], Owner: p.Length > 1 ? p[1] : "",
                Static: true, Params: RegExReplace(f.Sig, "^\(|\)$"), Doc: f.Does, Insert: f.Name f.Sig}
    }
    static ApiRow(it, act) {
        E := (t) => AxTags.E(t)
        ico := Map("class", "E8A5", "method", "E8F4", "prop", "E8EC", "function", "E943")
        sig := (it.Kind = "class") ? (it.Ext != "" ? "extends " it.Ext : "class")
             : (it.Kind = "prop") ? "property"
             : "(" it.Params ")"
        who := (it.Owner != "" ? it.Owner (it.Static ? "." : "  ") : "")
        ; a function, or a static method: one of your functions in a click
        can := (it.Kind = "function" || (it.Kind = "method" && it.Static)) && SubStr(act, 1, 4) = "api|"
        return '<div class="axd-pkapi axd-pk-' it.Kind '" data-pkg="' act '" title="' E(it.Insert) '">'
             . (can ? '<span class="axd-ract axd-pkmake" data-pkg="adapt|' SubStr(act, 5) '" title="Make it one of your functions -- a step in any rule or flowchart">Make it a step</span>' : "")
             . '<span class="ico">&#x' (ico.Has(it.Kind) ? ico[it.Kind] : "E943") ';</span>'
             . '<b>' E(who it.Name) '</b><span class="axd-sig">' E(sig) '</span>'
             . (it.Doc != "" ? '<div>' E(it.Doc) '</div>' : "") '</div>'
    }

    ; ------------------------------------------------------------ redraws
    static Redraw(s, list := true, info := true, cats := false) {
        try {
            if list
                s.Html("axdPkgList", AxPkgUi.ListHtml(s))
            if info
                s.Html("axdPkgInfo", AxPkgUi.InfoHtml(s))
            if cats
                s.Html("axdPkgCats", AxPkgUi.CatsHtml(s))
        }
    }
    static FindKey(s, ev) {
        k := 0
        try k := ev.keyCode
        v := ""
        try {
            if (k = 27)
                s.El("axdPkgFind").value := ""
            v := s.El("axdPkgFind").value
        }
        if (v == AxPkgUi.Q)
            return
        AxPkgUi.Q := v
        AxPkgUi.Redraw(s, true, false)
    }

    ; ------------------------------------------------------------ clicks
    static Act(s, v) {
        p := StrSplit(v, "|", , 2)
        verb := p[1], arg := p.Length > 1 ? p[2] : ""
        if (SubStr(verb, 1, 4) = "net.")
            return AxNetUi.Act(s, verb, arg)
        switch verb {
        case "tab":
            AxPkgUi.Tab := arg
            s.Reflect(false)
            ; the first shelf, read as the tab opens
            if (arg = "net" && !AxNetUi.Types.Length && SubStr(AxNetUi.Shelf, 1, 1) = "b")
                AxNetUi.Act(s, "net.shelf", AxNetUi.Shelf)
            return
        case "goto":
            AxPkgUi.Tab := "ahk", AxPkgUi.Sel := arg, AxPkgUi.Q := "", AxPkgUi.Cat := "", AxPkgUi.Show := "all", AxPkgUi.Mine := false
            return s.Reflect(false)
        case "adapt":
            e := AxPkg.Find(AxPkgUi.Sel)
            api := IsObject(e) ? AxPkg.Api(AxPkg.ProjDir(s.P), e.Name) : []
            i := Integer(arg)
            if (i >= 1 && i <= api.Length)
                AxNetUi.MakeAhk(s, e.Name, api[i])
            return s.Reflect(false)
        case "sel":
            AxPkgUi.Sel := arg
            AxPkgUi.Redraw(s, true, true)
        case "cat":
            AxPkgUi.Cat := arg
            AxPkgUi.Redraw(s, true, false, true)
        case "show":
            ; a shelf: "mine" is the old In this project switch
            AxPkgUi.Mine := (arg = "mine")
            AxPkgUi.Show := (arg = "mine") ? "all" : arg
            AxPkgUi.Redraw(s, true, false, true)
        case "sort":
            AxPkgUi.Sort := (arg = "az") ? "az" : "best"
            AxPkgUi.Redraw(s, true, false, true)
        case "hidden":
            AxPkgUi.Hidden := !AxPkgUi.Hidden
            s.Reflect(false)
        case "q":
            AxPkgUi.Q := arg, AxPkgUi.Cat := ""
            try s.El("axdPkgFind").value := arg
            AxPkgUi.Redraw(s, true, false, true)
        case "mine":
            AxPkgUi.Mine := !AxPkgUi.Mine
            s.Reflect(false)
        case "web":
            if RegExMatch(arg, "i)^https://")
                try Run(arg)
        case "folder":
            dir := AxPkg.ProjDir(s.P)
            if (dir != "" && DirExist(dir "\Lib\Aris")) {
                try Run('explorer.exe "' dir '\Lib\Aris"')
            } else
                s.Status("msg", "Nothing is installed for this project yet.")
        case "save":
            s.SaveAs()
            s.Reflect(false)
        case "getaris":
            s.Status("msg", "Getting Aris from github.com/Descolada/Aris...")
            msg := AxPkg.GetAris()
            if (msg != "")
                return s.Alert(msg, "Libraries")
            s.Status("msg", "Aris is here: " AxPkg.List().Length " libraries to choose from.")
            s.Reflect(false)
        case "refresh":
            s.Status("msg", "Fetching Aris's list...")
            msg := AxPkg.RefreshIndex()
            if (msg != "")
                return s.Alert(msg, "Libraries")
            s.Status("msg", "The list is up to date: " AxPkg.List().Length " libraries.")
            s.Reflect(false)
        case "install", "remove", "update":
            AxPkgUi.RunAris(s, verb, arg)
        case "checkup":
            AxUpdate.Show(s)
            s.Reflect(false)
        case "updateall":
            AxUpdate.UpdateLibs(s, AxUpdate.Outdated(s))
        case "uiapick":
            AxUiaUi.Pick(s)
        case "use", "unuse":
            s.Mark()
            AxPkg.Use(s.P, arg, verb = "use")
            s.PushCompletions()
            s.Reflect(false)
            s.QueueLive()
            s.Status("msg", (verb = "use" ? "The script includes " : "The script no longer includes ") arg ".")
        case "snip":
            e := AxPkg.Find(AxPkgUi.Sel)
            i := Integer(arg)
            if IsObject(e) && i >= 1 && i <= e.Snippets.Length
                AxPkgUi.Write(s, e.Snippets[i].Code, e)
        case "fnwrite", "fnadapt":
            e := AxPkg.Find(AxPkgUi.Sel)
            i := Integer(arg)
            if !IsObject(e) || i < 1 || i > e.Fn.Length
                return
            f := e.Fn[i]
            if (verb = "fnwrite")
                return AxPkgUi.Write(s, RegExReplace(f.Name f.Sig, "\?"), e)
            if !AxPkgUi.FnCan(e, f)
                return s.Alert(f.Name " is done on something the library makes first, so it cannot be a step by itself. "
                    . "Click it to put it in the code instead.", "Libraries")
            AxNetUi.MakeAhk(s, e.Name, AxPkgUi.FnItem(f))
            if !AxPkg.Installed(AxPkg.ProjDir(s.P)).Has(e.Name)
                AxPkgUi.NeedLib(s, e, AxPkgUi.RedrawFn(s))
            return s.Reflect(false)
        case "api":
            e := AxPkg.Find(AxPkgUi.Sel)
            api := IsObject(e) ? AxPkg.Api(AxPkg.ProjDir(s.P), e.Name) : []
            i := Integer(arg)
            if (i >= 1 && i <= api.Length)
                AxPkgUi.Write(s, api[i].Insert, e)
        }
    }
    static RunAris(s, verb, name, then := "") {
        e := AxPkg.Find(name)
        if !IsObject(e)
            return
        dir := AxPkg.ProjDir(s.P)
        if (verb = "remove" && !s.Confirm("Remove " name " from this project's Lib folder?"
                . (AxPkg.IsUsed(s.P, name) ? "`n`nThe script stops including it." : ""),
                "Libraries", "Remove", "Keep it", "warning"))
            return
        words := Map("install", "Installing", "remove", "Removing", "update", "Updating")
        msg := AxPkg.Run(verb, e, dir, AxPkgUi.DoneFn(s, then))
        if (msg != "")
            return s.Alert(msg, "Libraries")
        s.Status("msg", words[verb] " " name " with Aris...")
        AxPkgUi.Redraw(s, false, true)
    }
    static RedrawFn(s) => (ok) => s.Reflect(false)
    static DoneFn(s, then := "") => (r) => AxPkgUi.Done(s, r, then)
    static Done(s, r, then := "") {
        if r.Ok {
            if (r.Verb != "update") {
                s.Mark()
                AxPkg.Use(s.P, r.Name, r.Verb = "install")
                s.QueueLive()
            }
            s.PushCompletions()
            s.Status("msg", r.Name (r.Verb = "install" ? " is installed, and the script includes it."
                             : r.Verb = "remove" ? " is removed." : " is up to date."))
            ; what was waiting for it: a snippet to add, an adaptor to finish
            if IsObject(then)
                try then.Call(true)
        } else
            s.Alert("Aris did not " r.Verb " " r.Name ". What it said:`n`n"
                  . (r.Log != "" ? SubStr(r.Log, -3000) : "(nothing)"), "Libraries")
        if (s.Ws = "app" && s.AppSec = "libraries")
            s.Reflect(false)
        else if (s.Ws = "code")
            try s.CodeNav()
    }
    ; Where a snippet goes, in words: the piece open in Steps or Code, else
    ; the startup code.
    static WhereWords(s) {
        pc := AxPkgUi.Target(s)
        return IsObject(pc) ? AxSteps.Title(s, pc) : "the startup code (When it starts)"
    }
    static Target(s) {
        pc := ""
        if (s.PieceView = "steps" && IsObject(AxSteps.Pc) && !AxSteps.ReadOnly(AxSteps.Pc) && AxSteps.Pc.Kind != "rules")
            pc := AxSteps.Pc
        else
            try pc := s.PcFromCode()
        if IsObject(pc) && (pc.Kind = "gen" || pc.Kind = "rules")
            pc := ""
        return pc
    }
    ; A library's code, asked for while the library is not in the project:
    ; install it first (and then do what was asked), use the code as it is,
    ; or leave it. then(installed) does the rest.
    static NeedLib(s, e, then) {
        dir := AxPkg.ProjDir(s.P)
        why := dir = "" ? "Save the project first: libraries go in a Lib folder beside it, so installing one needs somewhere to go."
             : !AxPkg.HasAris() ? "Libraries come through Aris, which is not here yet (App > Libraries gets it)."
             : AxPkg.Busy() != "" ? "Aris is busy with " AxPkg.Busy() " -- try again in a moment." : ""
        r := AxForm.Show(s, {Title: "This needs " e.Short, Icon: "E896", Width: 540,
            Intro: e.Short " by " e.Author " is not in this project yet, and this code uses it.",
            Fields: [{Id: "n", Kind: "note", L: why != "" ? why
                : "Installing downloads it through Aris into this project's Lib folder, and the script includes it. "
                . "Nothing else on this machine changes. When it is in, this is added."}],
            Buttons: why = "" ? ["Install it, then add this", "Add the code anyway", "Cancel"] : ["Add the code anyway", "Cancel"],
            CancelIndex: why = "" ? 3 : 2})
        if !r.Ok || r.Label = "Cancel"
            return
        if (r.Label = "Add the code anyway")
            return then.Call(false)
        AxPkgUi.RunAris(s, "install", e.Name, then)
    }
    static WriteFn(s, code, e) => (ok) => AxPkgUi.Put(s, code, e)
    ; Code from a library: the library first, then into the piece being
    ; worked on -- as a step when Steps is how pieces are open, at the caret
    ; in Code otherwise, and into the startup code when nothing is open.
    static Write(s, code, e := "") {
        if IsObject(e) && !AxPkg.Installed(AxPkg.ProjDir(s.P)).Has(e.Name)
            return AxPkgUi.NeedLib(s, e, AxPkgUi.WriteFn(s, code, e))
        AxPkgUi.Put(s, code, e)
    }
    static Put(s, code, e := "") {
        s.Mark()
        inc := ""
        if (IsObject(e) && !AxPkg.IsUsed(s.P, e.Name) && AxPkg.Installed(AxPkg.ProjDir(s.P)).Has(e.Name)) {
            AxPkg.Use(s.P, e.Name)
            s.PushCompletions()
            inc := " The script includes " e.Name " now."
        }
        pc := AxPkgUi.Target(s)
        if (IsObject(pc) && s.PieceView = "steps") {
            AxSteps.Pc := pc
            M := AxSteps.Read(s, pc)
            if IsObject(M) && M.Lists.Has("root") {
                id := AxSteps.Sel
                s.SetWs("steps")
                AxStepsUi.Apply(s, (M) => (id != "" && M.Steps.Has(id)) ? AxStepsEdit.After(M, id, code)
                    : AxStepsEdit.Insert(M, "root", M.Lists["root"].Items.Length, code))
                return s.Status("msg", "Added to " AxSteps.Title(s, AxSteps.Pc) " as a step." inc " Ctrl+Z takes it back.")
            }
        }
        t := s.CodeTarget
        if !IsObject(t) || t.Kind = "readonly"
            s.EditScript("init", "code")
        else
            s.ShowPiece("code")
        try s.Ce.Insert(code "`n")
        s.CodeTyped(true)
        s.Status("msg", "Written into " (IsObject(s.CodeTarget) && s.CodeTarget.Kind = "init" ? "the startup code" : "the code")
            . (IsObject(e) ? " -- from " e.Name : "") "." inc)
    }

    ; ------------------------------------------------- the Code navigator
    static CodeNavHtml(s) {
        used := AxPkg.Used(s.P)
        h := '<div class="axd-cnwin"><span class="ico">&#xE82D;</span>Libraries</div>'
        if !used.Length
            return h '<div class="axd-cnitem" data-cn="pkg.browse"><span class="ico">&#xE710;</span>'
                 . 'Add a library...</div>'
        dir := AxPkg.ProjDir(s.P)
        for name in used {
            open := AxPkgUi.Open.Has(name)
            api := open ? AxPkg.Api(dir, name) : []
            h .= '<div class="axd-cnitem" data-cn="pkg.open.' AxTags.E(name) '"><span class="ico">&#x'
               . (open ? "E70D" : "E76C") ';</span>' AxTags.E(name)
               . (FileExist(AxPkg.Stub(dir, name)) ? "" : '<span class="axd-dim">not installed</span>') '</div>'
            for i, it in api
                if (it.Kind != "class")
                    h .= '<div class="axd-cnitem axd-cnapi" data-cn="pkg.api.' i '.' AxTags.E(name) '" title="'
                       . AxTags.E(it.Insert (it.Doc != "" ? "`n`n" it.Doc : "")) '">'
                       . '<span class="ico">&#x' (it.Kind = "function" ? "E943" : "E8F4") ';</span>'
                       . AxTags.E((it.Owner != "" ? it.Owner "." : "") it.Name) '</div>'
        }
        return h '<div class="axd-cnitem" data-cn="pkg.browse"><span class="ico">&#xE710;</span>Add a library...</div>'
    }
    static CodeNavClick(s, v) {
        p := StrSplit(v, ".", , 3)
        switch p.Length > 1 ? p[2] : "" {
        case "browse":
            s.GoSec("libraries", "app")
        case "open":
            name := p[3]
            if AxPkgUi.Open.Has(name)
                AxPkgUi.Open.Delete(name)
            else
                AxPkgUi.Open[name] := true
            s.CodeNav()
        case "api":
            q := StrSplit(p[3], ".", , 2)
            api := AxPkg.Api(AxPkg.ProjDir(s.P), q[2])
            i := Integer(q[1])
            if (i >= 1 && i <= api.Length)
                AxPkgUi.Write(s, api[i].Insert)
        }
    }
}

; =============================================================================
;  The element picker: tools\AxUiaPick.ahk, run as a process of its own with
;  the project's copy of Descolada's UIA library, and what it sends back made
;  into steps of the macro open in Logic > Macros -- the macro is the wizard:
;  one step after another, with "if element ..." / otherwise / end around
;  the ones that depend on what is on the screen.
; =============================================================================
class AxUiaUi {
    static Proc := 0, Out := "", S := ""
    static WatchFn := ObjBindMethod(AxUiaUi, "_Watch")

    static Pick(s) {
        dir := AxPkg.ProjDir(s.P)
        if (dir = "")
            return s.Alert("Save the project first: picking uses the UIA library installed beside it.", "Pick an element")
        if !AxPkg.Installed(dir).Has(AxPkg.UiaLib) {
            if s.Confirm("Picking an element uses Descolada's UIA library, and this project does not have "
                       . "it yet.`n`nInstall it now? When it is in, press Pick an element again.",
                         "Pick an element", "Install it", "Not now")
                AxPkgUi.RunAris(s, "install", AxPkg.UiaLib)
            return
        }
        if (AxUiaUi.Proc && ProcessExist(AxUiaUi.Proc))
            return s.Status("msg", "The picker is already open.")
        out := s.Store "\uiapick.json", run := s.Store "\uiapick_run.ahk"
        try FileDelete(out)
        code := AxUiaUi.Launcher(AxPkg.Stub(dir, AxPkg.UiaLib), out, s.UiTheme)
        r := AxStudio.Validate(code, run)
        if !r.Ok
            return s.Alert("The picker does not load:`n`n" r.Msg, "Pick an element")
        try FileDelete(run)
        FileAppend(code, run, "UTF-8")
        pid := 0
        try Run('"' A_AhkPath '" "' run '"', , , &pid)
        catch as e
            return s.Alert("Could not start the picker: " e.Message, "Pick an element")
        AxUiaUi.Proc := pid, AxUiaUi.Out := out, AxUiaUi.S := s
        SetTimer(AxUiaUi.WatchFn, 300)
        s.Status("msg", "Point at something in another program; F8 keeps it.")
    }
    ; the few lines the picker runs from: the library, UIA, the picker
    static Launcher(uia, out, theme) {
        q := Chr(34)
        return "#Requires AutoHotkey v2.0`n#SingleInstance Off`n#NoTrayIcon`n"
             . "#Include " AxStudioPaths.Lib "\AxGui.ahk`n"
             . "#Include " uia "`n"
             . "#Include " RegExReplace(A_LineFile, "\\[^\\]+$") "\tools\AxUiaPick.ahk`n"
             . "AxUiaPick.Run(" q out q ", " q theme q ")`n"
    }
    static _Watch() {
        if (AxUiaUi.Proc && ProcessExist(AxUiaUi.Proc))
            return
        SetTimer(AxUiaUi.WatchFn, 0)
        AxUiaUi.Proc := 0
        s := AxUiaUi.S
        if !FileExist(AxUiaUi.Out)
            return s.Status("msg", "Nothing was picked.")
        r := ""
        try r := AxJson.Parse(FileRead(AxUiaUi.Out, "UTF-8"))
        try FileDelete(AxUiaUi.Out)
        if (r is Map)
            AxUiaUi.Take(s, r)
    }
    ; what was picked, as a step of a flowchart: the same UIA call the step
    ; form's "A button or box in another program" writes
    static StepCode(r) {
        G := (k) => (r is Map && r.Has(k)) ? String(r[k]) : ""
        win := G("win"), cond := G("cond"), text := G("text")
        if (win = "" || cond = "")
            return ""
        el := "UIA.ElementFromHandle(WinExist(" AxLit.S(win) ")).WaitElement(" cond ", " (G("act") = "wait" ? 10000 : 3000) ")"
        switch G("act") {
        case "type": return el ".Value := " AxLit.S(text)
        case "read": return (AxProject.CleanName(text) != "" ? AxProject.CleanName(text) : "picked") " := " el ".Value"
        case "wait": return el
        case "if":   return "if " el " {`n}"
        }
        return el ".Click()"
    }
    static TakeStep(s, r) {
        code := AxUiaUi.StepCode(r)
        if (code = "")
            return s.Status("msg", "The picker sent nothing to use.")
        AxPkg.Use(s.P, AxPkg.UiaLib)
        M := AxSteps.M, id := AxSteps.Sel
        AxStepsUi.Apply(s, (M) => (id != "" && M.Steps.Has(id)) ? AxStepsEdit.After(M, id, code)
            : AxStepsEdit.Insert(M, "root", M.Lists["root"].Items.Length, code))
        try WinActivate("ahk_id " s.Hwnd)
        s.Status("msg", "Picked, and a step in " AxSteps.Title(s, AxSteps.Pc) ".")
    }
    ; what was picked, as macro steps
    static StepsFor(r) {
        G := (k) => (r is Map && r.Has(k)) ? String(r[k]) : ""
        win := G("win"), cond := G("cond"), text := G("text")
        if (win = "" || cond = "")
            return []
        at := win " | " cond
        switch G("act") {
        case "type": return ["uitype " at " | " text]
        case "wait": return ["uiwait " at " | 10"]
        case "read": return ["uiread " (AxProject.CleanName(text) != "" ? AxProject.CleanName(text) : "picked") " " at]
        case "if":   return ["if element " at, "end"]
        }
        return ["uiclick " at]
    }
    ; Into the flowchart that is open (Steps), after the step
    ; picked -- or the macro that is open, or a new one.
    static Take(s, r) {
        if (s.Ws = "steps" && IsObject(AxSteps.Pc) && !AxSteps.ReadOnly(AxSteps.Pc))
            return AxUiaUi.TakeStep(s, r)
        lines := AxUiaUi.StepsFor(r)
        if !lines.Length
            return s.Status("msg", "The picker sent nothing to use.")
        s.Mark()
        m := AxAuto2.FindMacro(s.P, s.MacroSel)
        if !IsObject(m) {
            n := 1
            while IsObject(AxAuto2.FindMacro(s.P, "picked" n))
                n++
            list := AxAuto2.Macros(s.P)
            list.Push({Name: "picked" n, Repeat: 1, Speed: 1, Hotkey: "", Steps: []})
            s.P.Macros := AxAuto2.MacroText(list)
            s.MacroSel := "picked" n
            m := AxAuto2.FindMacro(s.P, s.MacroSel)
        }
        add := ""
        for l in lines
            add .= "`n" l
        AxAuto2Ui.MacroSet(s, m.Name, "Steps", AxAuto2Ui.JoinSteps(m) add)
        s.GoSec("macros", "logic")
        try WinActivate("ahk_id " s.Hwnd)
        s.Status("msg", "Added to the macro " m.Name ": " lines[1])
    }
}
