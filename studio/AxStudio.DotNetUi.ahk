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
;  right, what is picked -- and "Make it one of your functions", the wizard
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
        dir := AxPkg.ProjDir(s.P)
        have := dir != "" && AxPkg.Installed(dir).Has(AxNet.Lib)
        return {Dir: dir, Have: have, Used: AxPkg.IsUsed(s.P, AxNet.Lib), N: AxNet.List(s.P).Length, Busy: AxPkg.Busy()}
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
        if (st.Busy != "")
            act := '<span class="axd-dim">Aris is busy with ' AxTags.E(st.Busy) '...</span>'
        else if (st.Dir = "")
            act := '<span class="axd-hbtn axd-go" data-pkg="save">Save the project</span>'
        else if !AxPkg.HasAris()
            act := '<span class="axd-hbtn axd-go" data-pkg="getaris">Get Aris first</span>'
        else if !st.Have
            act := '<span class="axd-hbtn axd-go" data-pkg="net.get">Get AHK#</span>'
        one := st.Have ? "In this project's Lib folder" (st.Used ? ", and the script includes it." : ". The script includes it with your first adaptor.")
             : "Not in this project yet. It is a library, not part of AutoHotkey: about 60 KB (ahk#.ahk and its bridge DLL) "
             . "from github.com/owhs/ahksharp, installed through Aris into this project only."
        h := '<div class="axn-state' (st.Have ? " ok" : "") '">'
           . '<div class="axn-sthead"><span class="ico">&#x' (st.Have ? "E73E" : "E946") ';</span><b>'
           . (st.Have ? (n ? "AHK# is ready: " n " .NET adaptor" (n = 1 ? "" : "s") " in this program" : "AHK# is ready")
              : "AHK# is not in this project yet" (n ? " -- " n " adaptor" (n = 1 ? " is" : "s are") " waiting for it" : "")) '</b>' act
           . '<span class="axd-hbtn" data-pkg="web|https://github.com/owhs/ahksharp">What is it?</span></div>'
           . '<div class="axn-steps">'
           . stepH(1, st.Have, !st.Have, "Get AHK#", one)
           . stepH(2, n > 0 || IsObject(AxNetUi.Picked(&t)), st.Have && !n, "Find what you need",
                   "A shelf of what Windows has, a NuGet package, or any .NET type by name.")
           . stepH(3, n > 0, st.Have && IsObject(AxNetUi.Picked(&t)), "Make it one of your functions",
                   "Then it is a step anywhere: Do one of your functions, in a flowchart, a rule, a timer or a hotkey.")
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
                h .= '<div class="axn-m' (AxNetUi.Sel = key ? " on" : "") '" data-pkg="net.m|' key '">'
                   . '<b>' AxTags.E(AxNet.Title(AxNet.G(m, "n"))) '</b>'
                   . '<span class="axn-sig">' AxTags.E(AxNet.Words(AxNet.Params(m))) '</span>'
                   . (AxNet.G(m, "s") ? "" : '<span class="axn-inst" title="Done on a new one each time">new</span>')
                   . '<span class="axn-ret">' AxTags.E(AxNetUi.Gives(AxNet.G(m, "r"))) '</span></div>'
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
               . '<div class="axd-pkbtns"><span class="axd-hbtn axd-go" data-pkg="net.make|">Make it one of your functions...</span></div>'
               . '<div class="axd-note">Then it is a step anywhere: <b>Do one of your functions</b> in a flowchart (Steps), '
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
        return '<div class="axd-pkhint"><span class="ico">&#xE8F4;</span>Pick something it can do to make it one of your functions -- '
             . 'then a step in any rule, timer, hotkey or flowchart.</div>' AxNetUi.MineHtml(s)
    }
    static MineHtml(s) {
        list := AxNet.List(s.P)
        if !list.Length
            return ""
        h := '<div class="axd-rpsub">Your adaptors (' list.Length ')</div>'
        for a in list
            h .= '<div class="axd-pkstep"><span class="ico">&#xE8F4;</span><b>' AxTags.E(a.Name) '()</b> '
               . '<span class="axd-dim">' AxTags.E(a.Doc) '</span>'
               . '<span class="axd-ract axd-ractdel" data-pkg="net.del|' AxTags.E(a.Name) '" title="Take it out">&#xE711;</span></div>'
        return h
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
            return AxPkgUi.RunAris(s, "install", AxNet.Lib, AxNetUi.GotFn(s))
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

    ; ------------------------------------------------------------ the wizard
    ; One method made into one of your functions: its name and what it is
    ; for, the line it writes shown as you type.
    static Make(s) {
        m := AxNetUi.Picked(&t)
        if !IsObject(m)
            return
        kind := AxNetUi.Kind(t, m)
        full := AxNet.G(t, "t") "." AxNet.G(m, "n")
        params := AxNet.Params(m)
        base := AxProject.CleanName(RegExReplace(AxNet.Human(AxNet.G(m, "n")), " (\w)", "$U1"))
        name := base, i := 2
        while IsObject(AxNet.Find(s.P, name))
            name := base i++
        src := (kind = "nuget") ? AxNetUi.Pkg.Id "@" AxNetUi.Pkg.Version : ""
        rets := AxNet.G(m, "r") (kind = "nuget" && !AxNet.G(m, "s") ? "@new" : "")
        r := AxForm.Show(s, {Title: "Make it one of your functions", Icon: "E8F4", Width: 560,
            Intro: full " -- it takes " AxNet.Words(params) (AxNet.G(m, "r") = "void" ? "." : ", and gives back " AxNet.G(m, "r") "."),
            Fields: [
                {Id: "name", L: "Called", Kind: "text", V: name, Hint: "What steps and rules will call it."},
                {Id: "doc", L: "What it does", Kind: "text", V: AxNet.Human(AxNet.G(m, "n")) " (" AxNet.G(t, "n") ")",
                 Hint: "Said beside it wherever it is offered."}],
            Buttons: ["Make it", "Cancel"],
            Check: (V) => AxProject.CleanName(V["name"]) = "" ? "Give it a name."
                        : IsObject(AxNet.Find(s.P, AxProject.CleanName(V["name"]))) ? "There is one called that already." : "",
            Preview: (V) => AxNet.Code({Adaptors: AxNet.Line({Name: AxProject.CleanName(V["name"]), Kind: kind, Source: src,
                Target: full, Params: params, Returns: rets, Doc: Trim(V["doc"])})})})
        if !r.Ok
            return
        s.Mark()
        AxNet.Add(s.P, {Name: AxProject.CleanName(r.V["name"]), Kind: kind, Source: src, Target: full,
                        Params: params, Returns: rets, Doc: Trim(r.V["doc"])})
        s.PushCompletions()
        s.QueueLive()
        AxNetUi.Redraw(s)
        s.Status("msg", AxProject.CleanName(r.V["name"]) "() is one of your functions -- a step anywhere: Do one of your functions.")
        ; it needs AHK# to run: offered now, not found out at the first run
        e := AxPkg.Find(AxNet.Lib)
        if IsObject(e) && !AxNetUi.State(s).Have
            AxPkgUi.NeedLib(s, e, AxNetUi.GotFn(s))
    }
    static GotFn(s) => (ok) => (AxNetUi.Redraw(s), s.Status("msg", ok ? "AHK# is in this project: every .NET adaptor is ready to use."
                                                              : "The adaptor is written; the script needs AHK# before it runs."))
    ; the bridge DLL, on App > Files as a file the compiled program writes
    ; out beside itself -- where AHK# looks for it
    static Carry(s) {
        dir := AxPkg.ProjDir(s.P)
        found := ""
        if (dir != "")
            loop files dir "\Lib\Aris\owhs\*.dll", "R"
                if (A_LoopFileName = "ahk#.bridge.dll")
                    found := A_LoopFileFullPath
        if (found = "")
            return s.Alert("ahk#.bridge.dll is not in this project's Lib folder. Get AHK# first.", "AHK#")
        rel := SubStr(found, StrLen(dir) + 2)
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
        full := (it.Owner != "" ? it.Owner "." : "") it.Name
        r := AxForm.Show(s, {Title: "Make it one of your functions", Icon: "E8F4", Width: 520,
            Intro: full "(" it.Params ") from " lib ".",
            Fields: [{Id: "name", L: "Called", Kind: "text", V: AxProject.CleanName(it.Owner it.Name)},
                     {Id: "doc", L: "What it does", Kind: "text", V: it.Doc != "" ? SubStr(it.Doc, 1, 80) : it.Name " (" lib ")"}],
            Buttons: ["Make it", "Cancel"],
            Check: (V) => AxProject.CleanName(V["name"]) = "" ? "Give it a name."
                        : IsObject(AxNet.Find(s.P, AxProject.CleanName(V["name"]))) ? "There is one called that already." : ""})
        if !r.Ok
            return
        s.Mark()
        AxNet.Add(s.P, {Name: AxProject.CleanName(r.V["name"]), Kind: "ahk", Source: lib, Target: full,
                        Params: params, Returns: "object", Doc: Trim(r.V["doc"])})
        s.QueueLive()
        s.Status("msg", AxProject.CleanName(r.V["name"]) "() is one of your functions -- a step anywhere.")
    }
}
