#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\AxStudio.DotNet.ahk
#Include %A_LineFile%\..\AxStudio.Form.ahk
#Include %A_LineFile%\..\AxStudio.Panes.ahk

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
;  AxStudio.DotNetUi.ahk -- Libraries > .NET, and "In this program".
;
;  Down the left, what Windows already has (speech, zip files, the web, the
;  clipboard...) a shelf each, then NuGet, then any .NET type by name. In the
;  middle, what the shelf offers, one method a row said in words; on the
;  right, what is picked -- and "Add it as a function", the wizard
;  that writes the adaptor. From then it is a step anywhere: Do one of your
;  functions, in a rule, a timer, a hotkey or a flowchart.
;
;  Clicks come as data-pkg="net.verb|arg" through AxPkgUi.Act.
; =============================================================================
class AxNetUi {
    static Shelf := "b1"          ; b<n> a built-in shelf | nuget | type
    static Q := ""                ; the NuGet search
    static Hits := []             ; its results
    static Pkg := ""              ; the package picked: {Id, Version, Desc, ...}
    static Fits := ""             ; yes | no | "" for it
    static Types := []            ; what the middle lists
    static TypeQ := ""            ; a type typed by name
    static Sel := ""              ; the method picked: "type|index"
    static Busy := ""

    ; ------------------------------------------------------------ the page
    static Section(s) {
        h := '<div id="axnState">' AxNetUi.StateHtml(s) '</div>'
           . '<div class="axn-cols"><div class="axd-pkside" id="axnSide">' AxNetUi.SideHtml(s) '</div>'
           . '<div class="axd-pklist" id="axnList">' AxNetUi.ListHtml(s) '</div>'
           . '<div class="axd-pkinfo" id="axnInfo">' AxNetUi.InfoHtml(s) '</div></div>'
        h .= '<div class="axd-note axd-dim">AHK# runs .NET Framework 4 inside the program (Windows 10 and 11 have it): packages built for '
           . '.NET Framework 4.x or .NET Standard 2.0 work, ones only for .NET 5 and later do not. What a package offers is read '
           . 'here from its files without running any of it (tools\AxNetScan.ps1).</div>'
        return h
    }
    ; Where this program stands with AHK#, and the three steps to a .NET
    ; method being a step of your own -- each one ticked when it is done.
    static State(s) {
        ; Wherever it is: installed once for everything, or into this project.
        ; An unsaved project has no folder of its own and can still use it.
        return {Dir: AxPkg.ProjDir(s.P), Have: AxPkg.Have(s.P).Has(AxNet.Lib),
                Where: AxPkg.Where(s.P, AxNet.Lib),
                Used: AxPkg.IsUsed(s.P, AxNet.Lib), N: AxNet.List(s.P).Length, Busy: AxPkg.Busy()}
    }
    static StateHtml(s) {
        st := AxNetUi.State(s)
        n := 0
        for a in AxNet.List(s.P)
            n += (a.Kind != "ahk")
        stepH := (num, done, now, title, body) => '<div class="axn-step' (done ? " done" : now ? " now" : "") '">'
            . '<span class="axn-num">' (done ? "&#xE73E;" : num) '</span><div><b>' title '</b><span>' body '</span></div></div>'
        ; the first step says what is needed to take it
        act := ""
        ; One button from any state. It installs AHK# once, for every project,
        ; so an unsaved project is no longer a reason it cannot be pressed --
        ; and it fetches Aris on the way if that is missing too.
        if (st.Busy != "")
            act := '<span class="axd-dim">Aris is busy with ' AxTags.E(st.Busy) '...</span>'
        else if !st.Have
            act := '<span class="axd-hbtn axd-go" data-pkg="net.get">Get AHK#</span>'
               . (AxPkg.HasAris() ? "" : '<span class="axd-dim">  (it fetches Aris first)</span>')
        where := (st.Where = "project") ? "In this project's Lib folder, carried with it"
                                        : "Installed once, for every project"
        one := st.Have
             ? where (st.Used ? ", and the script includes it."
                              : ". The script includes it with your first adaptor.")
             : "Not here yet. It is a library, not part of AutoHotkey: about 60 KB (ahk#.ahk and its bridge DLL) "
             . "from github.com/owhs/ahksharp, fetched through Aris. Installed once, it is there for every "
             . "project, saved or not."
        h := '<div class="axn-state' (st.Have ? " ok" : "") '">'
           . '<div class="axn-sthead"><span class="ico">&#x' (st.Have ? "E73E" : "E946") ';</span><b>'
           . (st.Have ? (n ? "AHK# is ready: " n " .NET adaptor" (n = 1 ? "" : "s") " in this program" : "AHK# is ready")
              : "AHK# is not here yet" (n ? " -- " n " adaptor" (n = 1 ? " is" : "s are") " waiting for it" : "")) '</b>' act
           . '<span class="axd-hbtn" data-pkg="web|https://github.com/owhs/ahksharp">What is it?</span></div>'
           . '<div class="axn-steps">'
           . stepH(1, st.Have, !st.Have, "Get AHK#", one)
           . stepH(2, n > 0 || IsObject(AxNetUi.Picked(&t)), st.Have && !n, "Find what you need",
                   "A shelf of what Windows has, a NuGet package, or any .NET type by name.")
           . stepH(3, n > 0, st.Have && IsObject(AxNetUi.Picked(&t)), "Add it as a function",
                   "Then it is a step anywhere: Call one of your functions, in a flowchart, a rule, a timer or a hotkey.")
           . '</div>'
        if (n && st.Have)
            h .= '<div class="axn-stnote">NuGet packages are downloaded by AHK# the first time the program runs '
               . '(to %LocalAppData%\AhkSharp\Packages), so that first run needs the internet. A compiled program needs '
               . 'ahk#.bridge.dll beside it: <a class="axd-link" data-pkg="net.carry">carry it with the program</a>.</div>'
        return h '</div>'
    }
    static SideHtml(s) {
        it := (key, ico, label, n := "") => '<div class="axd-pkshelf' (AxNetUi.Shelf = key ? " on" : "") '" data-pkg="net.shelf|' key '">'
            . '<span class="ico">&#x' ico ';</span><span class="axd-pkst">' label '</span>' (n != "" ? '<i>' n '</i>' : "") '</div>'
        h := '<div class="axd-pkhead">Built into Windows</div>'
        for i, b in AxNet.Builtin
            h .= it("b" i, b[2], b[1])
        h .= '<div class="axd-pkhead">More</div>'
           . it("nuget", "E719", "NuGet packages")
           . it("type", "E721", "Any .NET type...")
        return h
    }

    ; the middle: a shelf's methods, NuGet's results, or a package's insides
    static ListHtml(s) {
        sh := AxNetUi.Shelf
        if (sh = "nuget") {
            h := '<div class="axd-pkbar"><span class="ico axd-pkq">&#xE721;</span><input id="axnFind" class="axd-rfindbox" '
               . 'autocomplete="off" placeholder="Search NuGet -- pdf, excel, qr code, markdown, speech..." value="' AxTags.E(AxNetUi.Q) '"></div>'
            if IsObject(AxNetUi.Pkg) && AxNetUi.Types.Length
                return h AxNetUi.MethodsHtml(s, AxNetUi.Types, "Inside " AxNetUi.Pkg.Id)
            if !AxNetUi.Hits.Length
                return h '<div class="axd-empty-pane">Type what it should do and press Enter. Packages come from nuget.org.</div>'
            for i, x in AxNetUi.Hits
                h .= '<div class="axd-pkrow' (IsObject(AxNetUi.Pkg) && AxNetUi.Pkg.Id = x.Id ? " on" : "") '" data-pkg="net.pkg|' i '">'
                   . '<div class="axd-pkname"><b>' AxTags.E(x.Id) '</b><span>' AxTags.E(x.Version) '</span>'
                   . (x.Verified ? '<span class="ico axn-ver" title="The owner is verified by nuget.org">&#xE930;</span>' : "")
                   . '<span class="axn-dl">' AxNetUi.Many(x.Downloads) '</span></div>'
                   . '<div class="axd-pkdesc">' AxTags.E(x.Desc) '</div></div>'
            return h
        }
        if (sh = "type") {
            h := '<div class="axd-pkbar"><span class="ico axd-pkq">&#xE943;</span><input id="axnType" class="axd-rfindbox" '
               . 'autocomplete="off" placeholder="A .NET type by its full name -- System.Drawing.Image, then Enter" value="' AxTags.E(AxNetUi.TypeQ) '"></div>'
            return h (AxNetUi.Types.Length ? AxNetUi.MethodsHtml(s, AxNetUi.Types, "")
                     : '<div class="axd-empty-pane">Any public type in .NET Framework 4: its static methods, and the methods of a new one.</div>')
        }
        i := Integer(SubStr(sh, 2))
        b := AxNet.Builtin[i]
        return '<div class="axn-lead"><span class="ico">&#x' b[2] ';</span><b>' AxTags.E(b[1]) '</b> ' AxTags.E(b[3]) '</div>'
             . AxNetUi.MethodsHtml(s, AxNetUi.Types, "")
    }
    static Many(n) => (n >= 1000000) ? Round(n / 1000000) "M" : (n >= 1000) ? Round(n / 1000) "k" : n
    ; each method a row, in words: "Speak -- text to speak (text)"
    static MethodsHtml(s, types, head) {
        h := (head != "") ? '<div class="axd-pkhead axd-pklh">' AxTags.E(head) '</div>' : ""
        n := 0
        for ti, t in types {
            ms := AxNet.G(t, "m", [])
            if !(ms is Array)
                ms := [ms]
            if !ms.Length
                continue
            h .= '<div class="axn-type"><span class="ico">&#xE8F4;</span>' AxTags.E(AxNet.G(t, "n")) '<span>' AxTags.E(AxNet.G(t, "ns")) '</span></div>'
            for mi, m in ms {
                if (++n > 400)
                    return h '<div class="axd-note axd-dim">... and more: a narrower search, or a type by name.</div>'
                key := ti "|" mi
                ; Make it, from the row. Picking a method used to select it
                ; here and put the button that acts on it in the other pane,
                ; so every adaptor was a trip across the window and back.
                h .= '<div class="axn-m' (AxNetUi.Sel = key ? " on" : "") '" data-pkg="net.m|' key '">'
                   . '<b>' AxTags.E(AxNet.Title(AxNet.G(m, "n"))) '</b>'
                   . '<span class="axn-sig">' AxTags.E(AxNet.Words(AxNet.Params(m))) '</span>'
                   . (AxNet.G(m, "s") ? "" : '<span class="axn-inst" title="Done on a new one each time">new</span>')
                   . '<span class="axn-ret">' AxTags.E(AxNetUi.Gives(AxNet.G(m, "r"))) '</span>'
                   . '<span class="axn-make" data-pkg="net.make|' key '" title="Make it one of your '
                   . 'functions">Use this</span></div>'
            }
        }
        return n ? h : h '<div class="axd-empty-pane">Nothing here a step can call plainly.</div>'
    }
    static Gives(r) => (r = "void") ? "" : "gives " (r = "string" ? "text" : r = "bool" ? "yes/no" : RegExMatch(r, "^(int|long|double|float|decimal)$") ? "a number" : RegExReplace(r, ".*\."))

    ; the right: what is picked, and what to do with it
    static InfoHtml(s) {
        E := (x) => AxTags.E(x)
        m := AxNetUi.Picked(&t)
        if IsObject(m) {
            kind := AxNetUi.Kind(t, m)
            h := '<div class="axd-pkhd"><b>' E(AxNet.Title(AxNet.G(m, "n"))) '</b><span>' E(AxNet.G(t, "t")) '</span></div>'
               . '<div class="axd-kv"><span>It takes</span>' E(AxNet.Words(AxNet.Params(m))) '</div>'
               . '<div class="axd-kv"><span>It gives back</span>' E(AxNet.G(m, "r") = "void" ? "nothing" : AxNet.G(m, "r")) '</div>'
               . '<div class="axd-kv"><span>How</span>' (kind = "new" ? "on a new " E(AxNet.G(t, "n")) " each time" : kind = "nuget" ? "from the package, through a small C# module" : "straight from .NET") '</div>'
               . '<div class="axd-pkbtns"><span class="axd-hbtn axd-go" data-pkg="net.make|">Add it as a function...</span></div>'
               . '<div class="axd-note">Then it is a step anywhere: <b>Call one of your functions</b> in a flowchart (Steps), '
               . 'or <b>call</b> in a rule, a timer or a hotkey.</div>'
            return h AxNetUi.MineHtml(s)
        }
        if (AxNetUi.Shelf = "nuget" && IsObject(AxNetUi.Pkg)) {
            x := AxNetUi.Pkg
            fit := AxNetUi.Fits
            h := '<div class="axd-pkhd"><b>' E(x.Id) '</b><span>' E(x.Version) ' by ' E(x.Authors) '</span></div>'
               . '<div class="axd-pktext">' E(x.Desc) '</div>'
               . '<div class="axd-pknote' (fit = "no" ? " axd-pkwarn" : fit = "yes" ? " axn-fit" : "") '"><span class="ico">&#x'
               . (fit = "yes" ? "E73E" : fit = "no" ? "E7BA" : "E946") ';</span>'
               . (fit = "yes" ? "Works with AHK#: it is built for .NET Framework 4 or .NET Standard."
                 : fit = "no" ? "Only for .NET 5 and later, which AHK# cannot load. Look for another, or an older version."
                 : "Whether AHK# can load it shows once it is opened.") '</div>'
               . '<div class="axd-pkbtns">' (fit != "no" ? '<span class="axd-hbtn axd-go" data-pkg="net.open|">See what it offers</span> ' : "")
               . '<span class="axd-hbtn" data-pkg="web|https://www.nuget.org/packages/' E(x.Id) '">Its page on nuget.org</span></div>'
               . '<div class="axd-kv"><span>Downloads</span>' AxNetUi.Many(x.Downloads) '</div>'
            return h AxNetUi.MineHtml(s)
        }
        return '<div class="axd-pkhint"><span class="ico">&#xE8F4;</span>Pick something it can do to add it as a function -- '
             . 'then a step in any rule, timer, hotkey or flowchart.</div>' AxNetUi.MineHtml(s)
    }
    ; One adaptor, as a card. Drawn here and nowhere else.
    ;
    ; There were two of these -- a cramped row with two unlabelled icons on
    ; the .NET tab, and a proper card on "In this program" -- so the same four
    ; things had different names, different shapes and different buttons
    ; depending on which tab you happened to be looking at. One card, one set
    ; of words, both places.
    static Card(a) {
        E := (x) => AxTags.E(x)
        bg := AxNet.IsAsync(a)
        act := (verb, label, go := false) => '<span class="axd-ract' (go ? " axd-go" : "") '" data-pkg="net.'
             . verb '|' E(a.Name) '">' label '</span>'
        return '<div class="axd-lbmine"><div class="axd-pkname"><b>' E(a.Name) '()</b>'
             . '<span>' E(a.Kind = "ahk" ? a.Source : a.Kind = "nuget" ? "NuGet " a.Source : ".NET") '</span>'
             . (bg ? '<span class="axd-pkbg">&#xE916; in the background</span>' : "") '</div>'
             . '<div class="axd-pkdesc">' E(a.Doc) ' -- takes ' E(AxNet.Words(a.Params)) '</div>'
             . '<div class="axd-pkwhat">' E(a.Target) '</div>'
             . '<div class="axd-lbacts">' act("edit", "Edit", true)
             . (a.Kind = "ahk" ? "" : act("bg", bg ? "Run it now instead" : "Run it in the background"))
             . act("dup", "Duplicate") act("del", "Remove") '</div></div>'
    }
    static MineHtml(s) {
        list := AxNet.List(s.P)
        h := '<div class="axd-rpsub">Your adaptors (' list.Length ')'
           . '<span class="axd-ract axd-go" data-pkg="net.new">New one...</span></div>'
        if !list.Length
            return h '<div class="axd-note">None yet. Pick a method on the left, or write one '
                 . 'yourself if you already know which .NET method you want.</div>'
        for a in list
            h .= AxNetUi.Card(a)
        if AxNetUi.BgAny(list)
            h .= '<div class="axd-note">The ones marked &#xE916; hand back the <b>work</b>, not the answer. '
               . 'Five functions come with them: <b>WhenDone</b>(work, then), <b>WaitFor</b>(work), '
               . '<b>IsDone</b>(work), <b>AllOf</b>(work...) and <b>GiveUpAfter</b>(work, ms) -- each one a step '
               . 'like any other.</div>'
        return h
    }
    static BgAny(list) {
        for a in list
            if AxNet.IsAsync(a)
                return true
        return false
    }
    static Picked(&t) {
        t := ""
        if (AxNetUi.Sel = "")
            return ""
        p := StrSplit(AxNetUi.Sel, "|")
        ti := Integer(p[1]), mi := Integer(p[2])
        if (ti < 1 || ti > AxNetUi.Types.Length)
            return ""
        t := AxNetUi.Types[ti]
        ms := AxNet.G(t, "m", [])
        if !(ms is Array)
            ms := [ms]
        return (mi >= 1 && mi <= ms.Length) ? ms[mi] : ""
    }
    static Kind(t, m) => (AxNetUi.Shelf = "nuget") ? "nuget" : AxNet.G(m, "s") ? "static" : "new"

    ; ------------------------------------------------------------ clicks
    static Act(s, verb, arg) {
        switch verb {
        case "net.bg":
            ; Flipping it is one word in the generated line, so it is one
            ; click here rather than "delete it and make it again".
            for a in AxNet.List(s.P) {
                if (a.Name != arg || a.Kind = "ahk")
                    continue
                s.Mark()
                was := AxNet.IsAsync(a)
                a.Returns := AxNet.SetAsync(a.Returns, !was)
                s.PutLine("Adaptors", a.Line, AxNet.Line(a), false)
                s.QueueLive()
                s.Status("msg", a.Name "() " (was ? "runs there and then again -- it hands back the answer."
                                                 : "runs in the background now -- WhenDone(" a.Name "(...), ...) says what happens next."))
                return AxNetUi.Redraw(s)
            }
            return
        case "net.make":
            ; pick it and make it, in one
            AxNetUi.Sel := arg
            return AxNetUi.Make(s)
        case "net.dup":
            for a in AxNet.List(s.P) {
                if (a.Name != arg)
                    continue
                base := RegExReplace(a.Name, "\d+$"), nm := base "2", i := 2
                while IsObject(AxNet.Find(s.P, nm))
                    nm := base (++i)
                s.Mark()
                AxNet.Add(s.P, {Name: nm, Kind: a.Kind, Source: a.Source, Target: a.Target,
                                Params: a.Params, Returns: a.Returns, Doc: a.Doc})
                s.PushCompletions()
                s.QueueLive()
                AxNetUi.Redraw(s)
                return AxNetUi.Write(s, nm)     ; opened, so it can be made different
            }
            return
        case "net.new":
            return AxNetUi.Write(s, "")
        case "net.edit":
            return AxNetUi.Write(s, arg)
        case "net.shelf":
            AxNetUi.Shelf := arg, AxNetUi.Sel := ""
            if (SubStr(arg, 1, 1) = "b") {
                s.Status("msg", "Reading what .NET offers...")
                AxNetUi.Types := AxNet.Scan(AxNet.Builtin[Integer(SubStr(arg, 2))][4])
                s.Status("msg", "")
            } else if (arg = "nuget")
                AxNetUi.Types := IsObject(AxNetUi.Pkg) && AxNetUi.Fits != "no" ? AxNetUi.Types : []
            else
                AxNetUi.Types := []
            return AxNetUi.Redraw(s, true)
        case "net.m":
            AxNetUi.Sel := arg
            return AxNetUi.Redraw(s)
        case "net.pkg":
            x := AxNetUi.Hits[Integer(arg)]
            AxNetUi.Pkg := x, AxNetUi.Types := [], AxNetUi.Sel := ""
            AxNetUi.Fits := AxNet.Compatible(AxNet.Frameworks(x.Id, x.Version))
            return AxNetUi.Redraw(s)
        case "net.open":
            x := AxNetUi.Pkg
            if !IsObject(x)
                return
            s.Status("msg", "Getting " x.Id " " x.Version " from nuget.org...")
            try f := AxNet.Fetch(x.Id, x.Version)
            catch as e
                return s.Alert("Could not get it: " e.Message, "NuGet")
            if (f.Tfm = "") {
                AxNetUi.Fits := "no"
                s.Status("msg", x.Id " has nothing built for .NET Framework 4 or .NET Standard.")
                return AxNetUi.Redraw(s)
            }
            AxNetUi.Fits := "yes"
            s.Status("msg", "Reading " x.Id " (" f.Tfm ")...")
            AxNetUi.Types := AxNet.Scan("", f.Dlls)
            s.Status("msg", x.Id ": " AxNetUi.Types.Length " types a step can use.")
            return AxNetUi.Redraw(s)
        case "net.make":
            return AxNetUi.Make(s)
        case "net.get":
            ; once, for everything: nothing has to be saved first
            if AxPkgUi.Ready(s, "AHK#")
                AxPkgUi.RunAris(s, "install", AxNet.Lib, AxNetUi.GotFn(s), true)
            return
        case "net.carry":
            return AxNetUi.Carry(s)
        case "net.del":
            for a in AxNet.List(s.P)
                if (a.Name = arg)
                    s.PutLine("Adaptors", a.Line, "")
            s.QueueLive()
            return AxNetUi.Redraw(s)
        }
    }
    static Redraw(s, side := false) {
        try s.Html("axnState", AxNetUi.StateHtml(s))
        try {
            if side
                s.Html("axnSide", AxNetUi.SideHtml(s))
            s.Html("axnList", AxNetUi.ListHtml(s))
            s.Html("axnInfo", AxNetUi.InfoHtml(s))
        }
    }
    ; Enter in either box: search NuGet, or read a type by name
    static Key(s, id, ev) {
        k := 0
        try k := ev.keyCode
        v := ""
        try v := Trim(s.El(id).value)
        if (k != 13 || v = "")
            return
        if (id = "axnFind") {
            AxNetUi.Q := v, AxNetUi.Pkg := "", AxNetUi.Types := [], AxNetUi.Sel := ""
            s.Status("msg", "Searching NuGet for " v "...")
            try AxNetUi.Hits := AxNet.Search(v)
            catch as e
                return s.Alert("NuGet did not answer: " e.Message, "NuGet")
            s.Status("msg", AxNetUi.Hits.Length " packages.")
        } else {
            AxNetUi.TypeQ := v, AxNetUi.Sel := ""
            AxNetUi.Types := AxNet.Scan(v)
            s.Status("msg", AxNetUi.Types.Length ? "" : "No public type called " v " in .NET Framework 4.")
        }
        AxNetUi.Redraw(s)
        try s.El(id).focus()
    }

    ; --------------------------------------------- the adaptor workbench
    ; One .NET method, as one of your functions -- written, changed, looked
    ; up and RUN, without leaving the dialog.
    ;
    ; What was here before was seven text boxes in a column. Every one of them
    ; wanted something you had to already know: the method's full name, its
    ; parameters as "name:type, name:type", the .NET name of what it gives
    ; back. Get one wrong and nothing said so -- the adaptor was written, the
    ; program was generated, and the mistake turned up as a run-time error in
    ; somebody's window. Three things fix that, and all three are here:
    ;
    ;   Look it up      the scanner already knows what the method takes and
    ;                   gives back. Type the name, press it, and the rest of
    ;                   the form fills itself in -- from real .NET, not a guess.
    ;   What it takes   a row each, with the type as a choice, instead of a
    ;                   notation in a text box.
    ;   Try it          run the method now, with values you type, and see what
    ;                   comes back -- before a line of it is in a program.
    ;
    ; The pages are AxForm's own (Kind: "tabs"), and so are the rows, the
    ; buttons and the panels: anything in the studio that asks a long question
    ; can be built the same way.
    ; name: an adaptor to change, or "" for a new one.
    ; seed: what a method picked from a shelf already says about itself --
    ;       {Name, Kind, Source, Target, Params, Returns, Doc} -- so "Use
    ;       this" opens the same workbench with the answers already in it
    ;       rather than a second, smaller wizard of its own.
    static Write(s, name, seed := "") {
        old := (name != "") ? AxNet.Find(s.P, name) : IsObject(seed) ? seed : ""
        ed := (name != "")
        kinds := "static:A static method -- CS.Type.Method(...)"
               . "|new:A method on a fresh object -- CS.Type().Method(...)"
               . "|prop:A property, read once -- CS.Type.Property"
               . "|nuget:From a NuGet package"
               . "|ahk:A function of an AutoHotkey library"
        has := IsObject(old)
        params0 := has ? old.Params : ""
        F := (V, id) => V.Has(id) ? V[id] : ""
        ; What the type of a parameter can be. The usual ones, plus whatever
        ; this adaptor already says -- so opening an old one never quietly
        ; changes what it takes.
        types := AxNetUi.TypeOpts(params0)
        r := AxForm.Show(s, {Title: ed ? "Change " name "()" : "Write an adaptor", Icon: "E8F4", Width: 700,
            Intro: ed ? "One .NET method, as one of your functions. Every part of it can change, and Try it runs it."
                : has ? old.Target ". Give it a name, say what it is for -- and Try it runs it before you "
                      . "put it in the program."
                      : "One method, as one of your functions. Type its name and press Look it up -- what it "
                      . "takes and what it gives back come from .NET itself.",
            Fields: [
                {Id: "tab", Kind: "tabs", V: "method", Items: [
                    {V: "method", L: "The method", Icon: "E8F4"},
                    {V: "takes",  L: "What it takes", Icon: "E8FD"},
                    {V: "try",    L: "Try it", Icon: "E768"}]},

                ; ---------------------------------------------- the method
                {Id: "target", L: "The method", Kind: "text", Tab: "method", V: has ? old.Target : "",
                 Ph: "System.IO.File.ReadAllText",
                 Hint: "Its full name, with dots. Author.Class.Method for an AutoHotkey library."},
                {Id: "find", Kind: "acts", Tab: "method", L: "",
                 Do: (V, which) => AxNetUi.Bench(s, V, which), Items: [
                    {V: "look",  L: "Look it up", Icon: "E721", Go: true,
                     Tip: "Ask .NET what this method takes and gives back, and fill the rest in"},
                    {V: "paste", L: "Read a signature off the clipboard", Icon: "E77F",
                     Tip: "Copy a line from any documentation page and press this"}],
                 Hint: "Nothing here has to be known in advance: Look it up fills in what it takes, "
                     . "what it gives back and how it is reached."},
                {Id: "found", Kind: "panel", Tab: "method", V: ""},
                {Id: "d1", Kind: "divider", Tab: "method"},
                {Id: "name", L: "Called", Kind: "text", Tab: "method", V: has ? old.Name : "",
                 Hint: "What steps and rules will call it."},
                {Id: "doc", L: "What it does", Kind: "text", Tab: "method", V: has ? old.Doc : "",
                 Hint: "Said beside it wherever it is offered."},
                {Id: "kind", L: "It is", Kind: "choice", Tab: "method", V: has ? old.Kind : "static", Opts: kinds},
                {Id: "src", L: "From", Kind: "text", Tab: "method", V: has ? old.Source : "",
                 When: (V) => F(V, "kind") = "nuget" || F(V, "kind") = "ahk",
                 Hint: "A package as Name@Version (Newtonsoft.Json@13.0.3), or a library as Author/Name."},
                {Id: "rets", L: "It gives back", Kind: "text", Tab: "method",
                 V: has ? RegExReplace(old.Returns, "@.*$") : "object",
                 Hint: "void when it gives nothing back, otherwise the type -- object is always safe."},
                {Id: "bg", L: "Run it in the background", Kind: "flag", Tab: "method",
                 V: has ? (AxNet.IsAsync(old) ? 1 : 0) : 0,
                 Hint: "The window keeps answering while it runs. It hands back the WORK rather than "
                     . "the answer -- WhenDone(work, ...) says what happens next, WaitFor(work) waits here."},

                ; ------------------------------------------- what it takes
                {Id: "params", Kind: "rows", Tab: "takes", L: "", V: AxNetUi.ToRows(params0),
                 Sep: ":", AddLabel: "One more it takes", Empty: "It takes nothing.",
                 Cols: [{Id: "n", L: "Called", W: "42%", Ph: "path"},
                        {Id: "t", L: "What sort of value", W: "42%", Kind: "choice", Opts: types}]},
                {Id: "pnote", Kind: "note", Tab: "takes",
                 L: "These are the values a step will be asked for, in this order. The names are what the "
                  . "step editor shows beside each box, so say what they are: path, contents, how many. "
                  . "Look it up on the first page fills this in from .NET itself."},

                ; --------------------------------------------------- try it
                {Id: "tryvals", Kind: "rows", Tab: "try", L: "", V: AxNetUi.TryRows(params0, ""),
                 Sep: Chr(1), AddLabel: "One more value", Empty: "It takes nothing -- press Run it now.",
                 Cols: [{Id: "n", L: "Which", W: "34%"},
                        {Id: "v", L: "A value to try it with", W: "56%"}]},
                {Id: "tryact", Kind: "acts", Tab: "try",
                 Do: (V, which) => AxNetUi.Bench(s, V, which), Items: [
                    {V: "run",  L: "Run it now", Icon: "E768", Go: true, Tip: "Really runs the method"},
                    {V: "seed", L: "Take the names from What it takes", Icon: "E72C"}]},
                {Id: "result", Kind: "panel", Tab: "try", V: ""},
                {Id: "trynote", Kind: "note", Tab: "try",
                 L: "This runs the method for real, here, now -- with the values above. Whatever it would do to "
                  . "this machine, it does. It runs in Windows PowerShell, which is the .NET Framework 4 the "
                  . "program itself will use, so what works here works there. An AutoHotkey library cannot be "
                  . "tried this way; everything else can."}],
            Buttons: [ed ? "Save" : "Write it", "Cancel"],
            Check: (V) => AxNetUi.WriteWhy(s, V, ed ? old.Name : ""),
            Focus: has && !ed ? "name" : "target",
            Preview: (V) => AxNet.Code({Adaptors: AxNetUi.WriteLine(V)})})
        if !r.Ok
            return
        s.Mark()
        line := AxNetUi.WriteLine(r.V)
        if ed
            s.PutLine("Adaptors", old.Line, line, false)
        else {
            a := AxNet.List({Adaptors: line})[1]
            AxNet.Add(s.P, a)
        }
        s.PushCompletions()
        s.QueueLive()
        AxNetUi.Redraw(s)
        s.Status("msg", AxProject.CleanName(r.V["name"]) "() " (ed ? "changed." : "is a function of this program now."))
        if (!ed && !AxNetUi.State(s).Have) {
            e := AxPkg.Find(AxNet.Lib)
            if IsObject(e)
                AxPkgUi.NeedLib(s, e, AxNetUi.GotFn(s))
        }
    }

    ; ------------------------------------------------ the buttons in it
    ; One handler for every button on every page: which one it was comes in
    ; as `which`. A panel can hold buttons too -- it is inside the form's own
    ; body, so data-fact in the HTML it is given reaches back here.
    static Bench(s, V, which) {
        if (which = "look" || SubStr(which, 1, 4) = "use|")
            return AxNetUi.LookUp(s, V, which)
        if (which = "paste")
            return AxNetUi.Paste(s, V)
        if (which = "seed")
            return AxForm.Put(s, "tryvals", AxNetUi.TryRows(AxNetUi.FromRows(V.Has("params") ? V["params"] : ""), ""))
        if (which = "run")
            return AxNetUi.RunIt(s, V)
        ; offered by the result panel when what came back is not what the
        ; adaptor says it gives back
        if (SubStr(which, 1, 5) = "rets|") {
            AxForm.Put(s, "rets", SubStr(which, 6))
            return AxForm.Panel(s, "result", "It gives back <b>" AxTags.E(SubStr(which, 6)) "</b> now.")
        }
    }
    ; Ask .NET what this method really is, and fill the form in from the
    ; answer. An overload each when there is more than one: pressing one of
    ; them comes back here as use|<n>.
    static LookUp(s, V, which) {
        tgt := Trim(V.Has("target") ? V["target"] : "")
        if (tgt = "")
            return AxForm.Panel(s, "found", '<span class="axd-fpbad">Type the method' "'" 's full name first -- System.IO.File.ReadAllText.</span>')
        if (V.Has("kind") && V["kind"] = "ahk")
            return AxForm.Panel(s, "found", "An AutoHotkey library's functions are not .NET, so there is nothing to look up. "
                . "Libraries &gt; In this program lists what each one offers.")
        s.Status("msg", "Asking .NET about " tgt "...")
        hits := AxNet.Lookup(tgt)
        s.Status("msg", "")
        if !hits.Length {
            tn := RegExReplace(tgt, "\.[^.]+$")
            AxNetUi.Chosen := []
            return AxForm.Panel(s, "found", '<span class="axd-fpbad">' (AxNet.TypeExists(tn)
                ? AxTags.E(tn) " is there, but it has nothing public called " AxTags.E(RegExReplace(tgt, "^.*\."))
                  . " that a step could call plainly. Check the spelling, or look at the shelf behind this dialog."
                : "No .NET type called " AxTags.E(tn) ". Check the spelling -- or, if it comes from a NuGet package, "
                  . "set It is to From a NuGet package and open the package first.") '</span>')
        }
        AxNetUi.Chosen := hits
        i := 1
        if (SubStr(which, 1, 4) = "use|")
            i := Integer(SubStr(which, 5))
        else {
            ; the overload that matches what is already typed, so looking up
            ; an adaptor that exists does not quietly change what it takes
            have := AxNet.Split(AxNetUi.FromRows(V.Has("params") ? V["params"] : "")).Length
            for j, h in hits
                if (AxNet.Split(h.Params).Length = have) {
                    i := j
                    break
                }
        }
        if (i < 1 || i > hits.Length)
            i := 1
        h := hits[i]
        AxForm.Put(s, "params", AxNetUi.ToRows(h.Params))
        AxForm.Put(s, "tryvals", AxNetUi.TryRows(h.Params, ""))
        AxForm.Put(s, "rets", h.Returns)
        if (V.Has("kind") && V["kind"] != "nuget")
            AxForm.Put(s, "kind", h.Kind)
        if (Trim(V.Has("name") ? V["name"] : "") = "")
            AxForm.Put(s, "name", AxNetUi.Suggest(s, h.Name))
        if (Trim(V.Has("doc") ? V["doc"] : "") = "")
            AxForm.Put(s, "doc", h.Doc)
        ; what was found, and the other ways it can be called
        body := '<b>' AxTags.E(h.Type "." h.Name) '</b> -- takes ' AxTags.E(AxNet.Words(h.Params))
              . ', gives back ' AxTags.E(h.Returns = "void" ? "nothing" : h.Returns)
              . ' -- ' (h.Kind = "prop" ? "a property, read once" : h.Kind = "new" ? "on a new one each time" : "straight from .NET")
        if (hits.Length > 1) {
            body .= '<div class="axd-fprow" style="margin-top:6px"><span>' (hits.Length - 1) ' other way'
                 .  (hits.Length = 2 ? "" : "s") ' to call it</span></div>'
            for j, o in hits {
                if (j = i)
                    continue
                body .= '<span class="axd-fact" data-fact="axf_find" data-fval="use|' j '">'
                     .  AxTags.E("(" (o.Params = "" ? "nothing" : AxNet.Words(o.Params)) ") -> " o.Returns) '</span>'
            }
        }
        AxForm.Panel(s, "found", body)
    }
    static Chosen := []
    ; A name nothing else has yet.
    static Suggest(s, name) {
        base := AxProject.CleanName(RegExReplace(AxNet.Human(name), " (\w)", "$U1"))
        if (base = "")
            base := "Call"
        base := StrUpper(SubStr(base, 1, 1)) SubStr(base, 2)
        nm := base, i := 2
        while IsObject(AxNet.Find(s.P, nm))
            nm := base i++
        return nm
    }
    ; A line copied off any documentation page, pulled apart into the fields.
    static Paste(s, V) {
        txt := ""
        try txt := A_Clipboard
        if (Trim(txt) = "")
            return AxForm.Panel(s, "found", '<span class="axd-fpbad">There is no text on the clipboard.</span>')
        g := AxNet.FromSig(txt)
        if (g.Target = "")
            return AxForm.Panel(s, "found", '<span class="axd-fpbad">That does not look like a method: '
                . AxTags.E(SubStr(Trim(txt), 1, 70)) '</span>')
        ; a bare name keeps whatever type is already typed in front of it
        tgt := g.Target
        if !InStr(tgt, ".") {
            cur := Trim(V.Has("target") ? V["target"] : "")
            if InStr(cur, ".")
                tgt := RegExReplace(cur, "\.[^.]+$") "." tgt
        }
        AxForm.Put(s, "target", tgt)
        if (g.Params != "") {
            AxForm.Put(s, "params", AxNetUi.ToRows(g.Params))
            AxForm.Put(s, "tryvals", AxNetUi.TryRows(g.Params, ""))
        }
        if (g.Returns != "")
            AxForm.Put(s, "rets", g.Returns)
        AxForm.Panel(s, "found", "Read off the clipboard: <b>" AxTags.E(tgt) "</b>"
            . (g.Params != "" ? ", taking " AxTags.E(AxNet.Words(g.Params)) : "")
            . (g.Returns != "" ? ", giving back " AxTags.E(g.Returns) : "")
            . ". <b>Look it up</b> now checks it against .NET itself.")
    }
    ; Run it, here, with what is typed on the Try it page.
    static RunIt(s, V) {
        tgt := Trim(V.Has("target") ? V["target"] : "")
        kind := V.Has("kind") ? V["kind"] : "static"
        if (tgt = "")
            return AxForm.Panel(s, "result", '<span class="axd-fpbad">Say which method it is first.</span>')
        if (kind = "ahk")
            return AxForm.Panel(s, "result", '<span class="axd-fpbad">This one is an AutoHotkey function, not .NET -- '
                . 'there is nothing here to run it in. Run the program instead (Test).</span>')
        args := []
        for line in StrSplit(StrReplace(String(V.Has("tryvals") ? V["tryvals"] : ""), "`r"), "`n") {
            if (Trim(line) = "")
                continue
            p := StrSplit(line, Chr(1))
            args.Push(p.Length >= 2 ? p[2] : "")
        }
        dlls := ""
        if (kind = "nuget") {
            src := Trim(V.Has("src") ? V["src"] : "")
            id := StrSplit(src, "@")[1], ver := StrSplit(src, "@").Length > 1 ? StrSplit(src, "@")[2] : ""
            if (id = "" || ver = "")
                return AxForm.Panel(s, "result", '<span class="axd-fpbad">From needs the package as Name@Version '
                    . 'before it can be run.</span>')
            AxForm.Panel(s, "result", "Getting " AxTags.E(id) " " AxTags.E(ver) " from nuget.org...")
            try {
                f := AxNet.Fetch(id, ver)
                dlls := f.Dlls
            } catch as e
                return AxForm.Panel(s, "result", '<span class="axd-fpbad">Could not get the package: ' AxTags.E(e.Message) '</span>')
        }
        AxForm.Panel(s, "result", "Running " AxTags.E(tgt) "...")
        s.Status("msg", "Running " tgt "...")
        t := AxNet.Try(tgt, kind, args, dlls)
        s.Status("msg", "")
        if !t.Ok
            return AxForm.Panel(s, "result", '<span class="axd-fpbad"><b>It did not run.</b></span>'
                . '<div class="axd-fprow" style="margin-top:4px">' AxTags.E(t.Error) '</div>'
                . '<div class="axd-fprow axd-fpmono" style="opacity:.5;margin-top:5px">' AxTags.E(tgt)
                . '(' AxTags.E(AxNetUi.Joined(args)) ')</div>')
        ; what came back, and what the adaptor should therefore say it gives
        rets := AxNetUi.RetOf(t.Type)
        h := '<span class="axd-fpok"><b>It ran.</b></span>'
           . '<div class="axd-fprow"><span>It gave back</span>' AxTags.E(t.Value = "" ? "(nothing)" : t.Value) '</div>'
           . '<div class="axd-fprow"><span>Which is a</span>' AxTags.E(t.Type) '</div>'
        if (rets != "" && rets != Trim(V.Has("rets") ? V["rets"] : ""))
            h .= '<span class="axd-fact" data-fact="axf_tryact" data-fval="rets|' AxTags.E(rets) '">'
              .  'Say it gives back ' AxTags.E(rets) '</span>'
        AxForm.Panel(s, "result", h)
    }
    static Joined(args) {
        out := ""
        for a in args
            out .= (out = "" ? "" : ", ") '"' a '"'
        return out
    }
    ; System.String -> string, so what the run found can be what the adaptor
    ; says. Anything the studio has no word for stays object, which is safe.
    static RetOf(t) {
        if (t = "" || t = "nothing" || t = "nothing came back")
            return "void"
        w := AxNet.CsType(t)
        return RegExMatch(w, "^(string|int|long|double|float|bool|decimal|byte|short|char)$") ? w : "object"
    }

    ; --------------------------------------------- parameters, as rows
    ; "path:string, contents:string" <-> one row a line.
    static ToRows(params) {
        out := ""
        for x in AxNet.Split(params)
            out .= (out = "" ? "" : "`n") x.N ":" x.T
        return out
    }
    static FromRows(rows) {
        out := ""
        for line in StrSplit(StrReplace(String(rows), "`r"), "`n") {
            if (Trim(line) = "")
                continue
            n := Trim(StrSplit(line, ":")[1])
            t := (StrSplit(line, ":", , 2).Length > 1) ? Trim(StrSplit(line, ":", , 2)[2]) : ""
            n := RegExReplace(n, "[^A-Za-z0-9_]")
            if (n = "")
                continue
            out .= (out = "" ? "" : ", ") n ":" (t = "" ? "string" : t)
        }
        return out
    }
    ; The Try it page: a row per parameter, its name beside the box.
    static TryRows(params, keep) {
        had := Map()
        for line in StrSplit(StrReplace(String(keep), "`r"), "`n") {
            p := StrSplit(line, Chr(1))
            if (p.Length >= 2)
                had[Trim(p[1])] := p[2]
        }
        out := ""
        for x in AxNet.Split(params) {
            v := had.Has(x.N) ? had[x.N] : ""
            out .= (out = "" ? "" : "`n") x.N " (" AxNetUi.Sort(x.T) ")" Chr(1) v
        }
        return out
    }
    static Sort(t) {
        static w := Map("string", "text", "int", "a whole number", "long", "a whole number",
            "double", "a number", "float", "a number", "decimal", "a number", "bool", "true or false",
            "object", "anything", "char", "a letter")
        return w.Has(t) ? w[t] : t
    }
    ; The types a parameter can be: the usual ones, and any this adaptor
    ; already names, so nothing is lost by opening it.
    static TypeOpts(params) {
        opts := "string:text|int:a whole number|long:a whole number (big)|double:a number"
              . "|bool:true or false|object:anything|string[]:a list of text|char:a letter"
              . "|System.DateTime:a date and time"
        for x in AxNet.Split(params) {
            if !AxForm.HasOpt(opts, x.T)
                opts .= "|" x.T ":" x.T
        }
        return opts
    }

    static WriteLine(V) {
        rets := Trim(V["rets"]) = "" ? "object" : Trim(V["rets"])
        ; an instance method of a package keeps the @new the wizard writes
        if (V["kind"] = "nuget" && InStr(V["target"], "()"))
            rets .= "@new"
        return AxNet.Line({Name: AxProject.CleanName(V["name"]), Kind: V["kind"],
                           Source: Trim(V["src"]), Target: Trim(V["target"]),
                           Params: AxNetUi.FromRows(V["params"]), Returns: AxNet.SetAsync(rets, V["bg"]),
                           Doc: Trim(V["doc"])})
    }
    static WriteWhy(s, V, was) {
        nm := AxProject.CleanName(V["name"])
        if (nm = "")
            return "Enter a name."
        if (nm != was && IsObject(AxNet.Find(s.P, nm)))
            return "There is one called that already."
        if (Trim(V["target"]) = "")
            return "Say which method it is."
        if (V["kind"] != "prop" && !InStr(V["target"], "."))
            return "The method's full name, with dots: System.IO.File.ReadAllText."
        if ((V["kind"] = "nuget" || V["kind"] = "ahk") && Trim(V["src"]) = "")
            return (V["kind"] = "nuget") ? "Which package? Name@Version." : "Which library? Author/Name."
        if (V["bg"] && V["kind"] = "ahk")
            return "An AutoHotkey function cannot leave the AutoHotkey thread."
        if (V["bg"] && V["kind"] = "prop")
            return "A property is read there and then; there is nothing to put on a thread."
        return ""
    }

    ; ---------------------------------------------- from a shelf or a package
    ; "Use this" on a method row. There is no second wizard: it works out
    ; what the method is and opens the workbench with it already filled in,
    ; so the same three pages -- what it is, what it takes, try it -- are
    ; what you get however you arrived.
    static Make(s) {
        m := AxNetUi.Picked(&t)
        if !IsObject(m)
            return
        kind := AxNetUi.Kind(t, m)
        full := AxNet.G(t, "t") "." AxNet.G(m, "n")
        rets := AxNet.G(m, "r") (kind = "nuget" && !AxNet.G(m, "s") ? "@new" : "")
        AxNetUi.Write(s, "", {Name: AxNetUi.Suggest(s, AxNet.G(m, "n")), Kind: kind,
            Source: (kind = "nuget") ? AxNetUi.Pkg.Id "@" AxNetUi.Pkg.Version : "",
            Target: full, Params: AxNet.Params(m), Returns: rets,
            Doc: AxNet.Title(AxNet.G(m, "n")) " (" AxNet.G(t, "n") ")", Line: ""})
    }
    static GotFn(s) => (ok) => (AxNetUi.Redraw(s), s.Status("msg", ok ? "AHK# is in this project: every .NET adaptor is ready to use."
                                                              : "The adaptor is written; the script needs AHK# before it runs."))
    ; the bridge DLL, on App > Files as a file the compiled program writes
    ; out beside itself -- where AHK# looks for it
    static Carry(s) {
        dir := AxPkg.ProjDir(s.P)
        found := ""
        ; wherever AHK# was installed: this project's Lib folder, or the one
        ; every project shares
        for root in [dir, AxPkg.SharedDir()]
            if (root != "" && found = "")
                loop files root "\Lib\Aris\owhs\*.dll", "R"
                    if (A_LoopFileName = "ahk#.bridge.dll")
                        found := A_LoopFileFullPath
        if (found = "")
            return s.Alert("ahk#.bridge.dll is not here. Get AHK# first (App > Libraries > .NET).", "AHK#")
        ; relative when it is inside the project, so the project folder can be
        ; moved; absolute when it is the shared copy, because FileInstall reads
        ; the file where it is when the exe is built
        rel := (dir != "" && InStr(found, dir "\") = 1) ? SubStr(found, StrLen(dir) + 2) : found
        for f in AxAsset.Files(s.P)
            if (f.Path = rel)
                return s.Status("msg", "It is carried already (App > Files).")
        s.Mark()
        line := AxAsset.FileLine("ahksharp_bridge", rel, "install")
        cur := RTrim(String(s.P.Files), " `t`r`n")
        s.P.Files := (Trim(cur) = "") ? line : cur "`n" line
        s.Status("msg", "ahk#.bridge.dll goes with the program now: written out beside it on its first run (App > Files).")
        AxNetUi.Redraw(s)
    }
    ; an AutoHotkey library's function or static method, the same way
    static MakeAhk(s, lib, it) {
        if (it.Kind = "class" || it.Kind = "prop" || (it.Owner != "" && !it.Static))
            return s.Alert("Only a function, or a class's static method, can be one of your functions by itself.", "Libraries")
        params := ""
        for x in StrSplit(it.Params, ",", " ") {
            pn := RegExReplace(Trim(x), "\s*:=.*$|[*?&]")
            if (pn != "")
                params .= (params = "" ? "" : ", ") pn ":object"
        }
        AxNetUi.Write(s, "", {Name: AxNetUi.Suggest(s, it.Owner it.Name), Kind: "ahk", Source: lib,
            Target: (it.Owner != "" ? it.Owner "." : "") it.Name, Params: params, Returns: "object",
            Doc: it.Doc != "" ? SubStr(it.Doc, 1, 80) : AxNet.Title(it.Name) " (" lib ")", Line: ""})
    }
}
