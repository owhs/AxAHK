#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\AxJson.ahk
#Include %A_LineFile%\..\AxStudio.Model.ahk
#Include %A_LineFile%\..\AxStudio.Host.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk
#Include %A_LineFile%\..\AxStudio.Flow.ahk
#Include %A_LineFile%\..\AxStudio.Auto2.ahk

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
;  AxStudio.Pkg.ahk -- other people's libraries, through Aris.
;
;  The studio does not keep a package manager of its own. Aris
;  (github.com/Descolada/Aris) already knows where a library goes and how a
;  script finds it, so the studio fetches it the first time it is wanted and
;  asks it to do the installing:
;
;      <project folder>\package.json              what is installed, which version
;      <project folder>\Lib\Aris\Author\Name.ahk  one line, #include-ing the real file
;      <project folder>\Lib\Aris\Author\Name@ver\ the library itself
;
;  A_ScriptDir\Lib is the first place #Include <...> looks, so a script
;  exported beside its project writes #Include <Aris/Author/Name>, and the
;  folder copied anywhere still runs and still compiles.
;
;  Aris's list (assets/index.json) says what each library is; ours
;  (packages\patch.json) is merged over it and never written into it: our own
;  categories, keywords it lacks, cautions, ready snippets, and libraries it
;  does not list. The project keeps which libraries its script uses in
;  Packages, one "Author/Name" per line.
;
;  What a library offers is read out of its own files by the parser
;  (AxHost outline): classes, methods, functions, their parameters and the
;  comment above each. That is what the Code workspace lists and completes.
;
;  Nothing here runs a library's code. Aris itself runs as a process of its
;  own, hidden, one at a time, and writes what it did to a log.
; =============================================================================
class AxPkg {
    static Home := ""                ; where Aris lives; "" = studio\data\aris
    static IndexOverride := ""       ; a list to read instead of Aris's own (the probe)
    static ZipUrl := "https://codeload.github.com/Descolada/Aris/zip/refs/heads/main"
    static IndexUrl := "https://raw.githubusercontent.com/Descolada/Aris/main/assets/index.json"
    static _list := ""
    static _cats := ""
    static HiddenWhy := ""                   ; why the patch leaves some out
    static _api := Map()
    static Job := ""
    static UiaLib := "Descolada/UIA"          ; what macros' ui steps and the element picker use
    static WatchFn := ObjBindMethod(AxPkg, "_Watch")   ; a timer takes a function, not a method

    static Dir() => AxPkg.Home != "" ? AxPkg.Home : AxStudioPaths.Data() "\aris"
    static ArisPath() => AxPkg.Dir() "\aris.ahk"
    static HasAris() => FileExist(AxPkg.ArisPath()) != ""
    static IndexFile() => AxPkg.IndexOverride != "" ? AxPkg.IndexOverride : AxPkg.Dir() "\assets\index.json"
    static PatchFile() => RegExReplace(A_LineFile, "\\[^\\]+$") "\packages\patch.json"

    ; --------------------------------------------------------- getting Aris
    ; Downloaded, unpacked with tar (in Windows since 10 1803) and moved into
    ; place. Its first-run question -- whether to add itself to the PATH and
    ; Explorer's menu -- is answered "no" by a config written before it ever
    ; runs; it only asks when started with no arguments anyway.
    static GetAris() {
        dir := AxPkg.Dir()
        tmp := A_Temp "\axaris_" A_TickCount
        zip := tmp ".zip"
        try {
            DirCreate(tmp)
            Download(AxPkg.ZipUrl, zip)
            RunWait('tar.exe -xf "' zip '" -C "' tmp '"', , "Hide")
            src := ""
            loop files tmp "\*", "D"
                if FileExist(A_LoopFileFullPath "\aris.ahk") {
                    src := A_LoopFileFullPath
                    break
                }
            if (src = "")
                throw Error("the download has no aris.ahk in it")
            if DirExist(dir)
                DirDelete(dir, true)
            SplitPath(dir, , &parent)
            DirCreate(parent)
            DirMove(src, dir)
            cfg := dir "\assets\config.json"
            if !FileExist(cfg)
                FileAppend('{"first_run": false}', cfg, "UTF-8-RAW")
        } catch as e {
            AxPkg._Clean(tmp, zip)
            return "Could not get Aris: " e.Message
        }
        AxPkg._Clean(tmp, zip)
        AxPkg._list := ""
        return ""
    }
    static _Clean(tmp, zip) {
        try DirDelete(tmp, true)
        try FileDelete(zip)
    }
    ; Aris's list, fetched again. Aris does this itself once a day when it
    ; runs; this is for looking before it has.
    static RefreshIndex() {
        if AxPkg.IndexOverride != ""
            return ""
        f := AxPkg.IndexFile(), tmp := f ".~ax"
        try {
            Download(AxPkg.IndexUrl, tmp)
            m := AxJson.Parse(AxPkg._Read(tmp))
            if !(m is Map) || !m.Has("v2.0")
                throw Error("it is not a package list")
            FileMove(tmp, f, true)
        } catch as e {
            try FileDelete(tmp)
            return "Could not fetch the list: " e.Message
        }
        AxPkg._list := ""
        return ""
    }
    static _Read(f) => RegExReplace(FileRead(f, "UTF-8"), "^\x{FEFF}")
    static IndexAge() {
        try return DateDiff(A_Now, FileGetTime(AxPkg.IndexFile(), "M"), "Hours")
        return -1
    }

    ; ------------------------------------------------------------ the list
    ; Every library, as one object each:
    ;   Name "Author/Name", Author, Short, Desc, Keywords [], Cats [ids],
    ;   License, Homepage, Repo, Deps [], Snippets [{Name, Code}], Notes, Warn,
    ;   Install (what Aris is given), Script (Aris runs one after download),
    ;   Extra (ours, not on Aris's list)
    static List() {
        if (AxPkg._list is Array)
            return AxPkg._list
        idx := Map(), patch := Map()
        try idx := AxJson.Parse(AxPkg._Read(AxPkg.IndexFile()))
        try patch := AxJson.Parse(AxPkg._Read(AxPkg.PatchFile()))
        G := (m, k, d := "") => (m is Map && m.Has(k)) ? m[k] : d
        cats := [], catOf := Map()
        for c in G(patch, "categories", []) {
            cats.Push({Id: G(c, "id"), Label: G(c, "label"), Icon: G(c, "icon", "E8F1"), N: 0})
            for n in G(c, "packages", [])
                (catOf.Has(n) ? catOf[n] : catOf[n] := []).Push(G(c, "id"))
        }
        extra := G(patch, "packages", Map())
        ; recommended ones come first, in the patch's order, each saying why;
        ; hidden ones build windows, which is the studio's job
        rec := Map(), hid := Map()
        for i, r in G(patch, "recommended", [])
            if (r is Map)
                rec[G(r, "name")] := {Rank: i, Why: G(r, "why")}
        why := G(G(patch, "hidden", Map()), "reasons", Map())
        for n in G(G(patch, "hidden", Map()), "packages", [])
            hid[n] := (why is Map && why.Has(n)) ? why[n] : true
        AxPkg.HiddenWhy := G(G(patch, "hidden", Map()), "why")
        out := [], seen := Map()
        Add(name, m, isExtra) {
            if seen.Has(name)
                return
            seen[name] := true
            x := G(extra, name, Map())
            p := StrSplit(name, "/", , 2)
            kw := []
            for k in AxPkg._Arr(G(m, "keywords", []))
                kw.Push(String(k))
            for k in AxPkg._Arr(G(x, "keywords", []))
                kw.Push(String(k))
            deps := []
            if (G(m, "dependencies", "") is Map)
                for d in G(m, "dependencies")
                    deps.Push(d)
            sn := []
            for s in AxPkg._Arr(G(x, "snippets", G(m, "snippets", [])))
                if (s is Map)
                    sn.Push({Name: G(s, "name"), Code: G(s, "code")})
            st := []
            for x2 in AxPkg._Arr(G(x, "steps", []))
                if (x2 is Map && G(x2, "verb") != "")
                    st.Push({V: StrLower(G(x2, "verb")), L: G(x2, "label"), Who: G(x2, "who"),
                             Arg: G(x2, "arg") != "", ArgL: G(x2, "arg"), Code: G(x2, "code"),
                             Sync: G(x2, "sync", false) ? true : false, Lib: name})
            ; what it offers, read from its source for the patch: offered as
            ; steps before it is installed (AxPkgUi, "What it can do")
            fns := []
            for f in AxPkg._Arr(G(x, "fn", []))
                if (f is Map && G(f, "name") != "")
                    fns.Push({Name: G(f, "name"), Sig: G(f, "sig"), Does: G(f, "does"), Returns: G(f, "returns")})
            scr := G(m, "scripts", "")
            out.Push({Name: name, Author: p[1], Short: p.Length > 1 ? p[2] : name,
                      Desc: G(x, "description", G(m, "description")),
                      Keywords: kw, Cats: catOf.Has(name) ? catOf[name] : [],
                      License: G(m, "license"), Homepage: AxPkg._Home(m),
                      Repo: G(m, "repository") is Map ? G(G(m, "repository"), "url") : G(m, "repository"),
                      Deps: deps, Snippets: sn, Steps: st, Notes: G(x, "notes", G(m, "notes")),
                      Warn: G(x, "warn", G(m, "warn", false)) ? true : false,
                      Install: G(m, "install", name),
                      Script: (scr is Map) && scr.Has("postdownload"),
                      Extra: isExtra, Hidden: hid.Has(name), HideWhy: (hid.Has(name) && hid[name] != true) ? hid[name] : "",
                      Fn: fns, Src: G(x, "src"),
                      Rank: rec.Has(name) ? rec[name].Rank : 0, Why: rec.Has(name) ? rec[name].Why : ""})
        }
        for ver in ["v2.0", "v2.1"] {
            if (ver = "v2.1" && VerCompare(A_AhkVersion, "2.1-alpha") < 0)
                continue
            if (G(idx, ver, "") is Map)
                for name, m in G(idx, ver)
                    if (m is Map)
                        Add(name, m, false)
        }
        if (G(patch, "extra", "") is Map)
            for name, m in G(patch, "extra")
                Add(name, m, true)
        AxPkg._SortByName(out)
        ; A library Aris lists that patch.json has not placed -- one added
        ; since -- is placed by what it says about itself; the rest go under
        ; "Everything else", so no library is only findable by searching.
        static guess := [["data", "json|xml|yaml|csv|sql|database|\bini\b|zip|archive|base64|serial"],
            ["web", "http|\bweb|url|download|socket|dns|network|request"],
            ["automate", "\buia\b|automat|\bacc\b|chrome|browser|listview|treeview|another program"],
            ["screen", "image|ocr|screen|pixel|gdi|capture|\bdraw|overlay"],
            ["notify", "notif|toast|tooltip|\bmenu|tray"],
            ["input", "\bkey|mouse|hotkey|hotstring|gamepad|midi|controller|gesture"],
            ["system", "process|\bcmd\b|registry|service|monitor|audio|volume|folder|director|clipboard"],
            ["lang", "array|string|\bmap\b|class|object|regex|math|hash|promise"],
            ["interop", "\bdll\b|\bcom\b|\.net|\bclr\b|winrt|win32|c\+\+|\blua\b|python"],
            ["dev", "\btest|\blog\b|logging|debug|trace"]]
        other := false
        for e in out {
            if (e.Cats.Length || e.Hidden)
                continue
            hay := StrLower(e.Name " " e.Desc)
            for k in e.Keywords
                hay .= " " StrLower(k)
            for g in guess
                if RegExMatch(hay, g[2]) {
                    e.Cats.Push(g[1])
                    break
                }
            if !e.Cats.Length
                e.Cats.Push("other"), other := true
        }
        if other
            cats.Push({Id: "other", Label: "Everything else", Icon: "E712", N: 0})
        for c in cats
            for e in out
                if !e.Hidden
                    for id in e.Cats
                        c.N += (id = c.Id)
        AxPkg._cats := cats
        return AxPkg._list := out
    }
    static Cats() => (AxPkg.List(), AxPkg._cats)
    static CatLabel(id) {
        for c in AxPkg.Cats()
            if (c.Id = id)
                return c.Label
        return id
    }
    static Find(name) {
        for e in AxPkg.List()
            if (e.Name = name)
                return e
        return ""
    }
    static _Arr(v) => (v is Array) ? v : (v = "" ? [] : [v])
    static _Home(m) {
        h := (m is Map && m.Has("homepage")) ? String(m["homepage"]) : ""
        if (h = "" && m is Map && m.Has("repository") && !(m["repository"] is Map)) {
            r := StrSplit(m["repository"], "/")
            if (r.Length >= 2)
                h := "https://github.com/" r[1] "/" r[2]
        }
        if (h != "" && !RegExMatch(h, "i)^https?://"))
            h := "https://" h
        return h
    }
    static _SortByName(a) {
        s := ""
        for i, e in a
            s .= StrLower(e.Name) "`t" i "`n"
        order := []
        for line in StrSplit(Sort(RTrim(s, "`n")), "`n")
            order.Push(a[Integer(StrSplit(line, "`t")[2])])
        for i, e in order
            a[i] := e
    }

    ; What matches a search: every word has to be somewhere in the name, the
    ; description, the keywords or the category. cat "" is every category;
    ; have is a Map of installed names, only those kept when given.
    ; opts: Show "all" | "rec" (recommended) | "nocode" (has rule steps) |
    ; "code" (has ready snippets); Hidden true keeps the ones the patch hides;
    ; Sort "best" puts the recommended first, then the ones that do most
    ; without code, then the rest by name -- "az" is by name only.
    static Filter(q, cat := "", have := "", opts := "") {
        O := (k, d) => (IsObject(opts) && opts.HasOwnProp(k)) ? opts.%k% : d
        show := O("Show", "all"), keepHidden := O("Hidden", false), order := O("Sort", "az")
        words := StrSplit(StrLower(Trim(q)), " ", " `t")
        out := []
        for e in AxPkg.List() {
            if e.Hidden && !keepHidden && !((have is Map) && have.Has(e.Name))
                continue
            if (show = "rec" && !e.Rank) || (show = "nocode" && !e.Steps.Length) || (show = "code" && !e.Snippets.Length)
                continue
            if (cat != "") {
                ok := false
                for id in e.Cats
                    ok := ok || (id = cat)
                if !ok
                    continue
            }
            if (have is Map) && !have.Has(e.Name)
                continue
            hay := ""
            for w in words {
                if (w = "")
                    continue
                if (hay = "") {
                    hay := StrLower(e.Name " " e.Desc)
                    for k in e.Keywords
                        hay .= " " StrLower(k)
                    for id in e.Cats
                        hay .= " " StrLower(AxPkg.CatLabel(id))
                }
                if !InStr(hay, w) {
                    hay := "-"
                    break
                }
            }
            if (hay != "-")
                out.Push(e)
        }
        return (order = "best") ? AxPkg.Best(out) : out
    }
    ; Recommended first in their own order, then by how much each does
    ; without code (rule steps, then ready snippets, then a note of ours),
    ; then by name -- the list is already by name, and Sort is stable on the
    ; index that breaks ties.
    static Best(list) {
        s := ""
        for i, e in list {
            k := e.Rank ? Format("0{:03}", e.Rank)
                 : Format("1{:03}", 999 - Min(999, e.Steps.Length * 100 + e.Snippets.Length * 10 + (e.Notes != "" ? 1 : 0)))
            s .= k Format("{:05}", i) "`t" i "`n"
        }
        out := []
        if (s != "")
            for line in StrSplit(Sort(RTrim(s, "`n")), "`n")
                out.Push(list[Integer(StrSplit(line, "`t")[2])])
        return out
    }
    static Counts(have := "") {
        n := {All: 0, Rec: 0, NoCode: 0, Code: 0, Hidden: 0}
        for e in AxPkg.List() {
            if e.Hidden {
                n.Hidden++
                continue
            }
            n.All++, n.Rec += e.Rank ? 1 : 0, n.NoCode += e.Steps.Length ? 1 : 0, n.Code += e.Snippets.Length ? 1 : 0
        }
        return n
    }

    ; ------------------------------------------------- one project's libraries
    ; The folder the project lives in, which is where Lib\ goes. "" until it
    ; has been saved.
    static ProjDir(P) {
        if (P.Path = "")
            return ""
        SplitPath(P.Path, , &d)
        return d
    }
    static Stub(dir, name) => dir "\Lib\Aris\" StrReplace(name, "/", "\") ".ahk"
    ; What Aris says is installed in a folder: name -> version.
    static Installed(dir) {
        out := Map()
        out.CaseSense := false
        if (dir = "" || !FileExist(dir "\package.json"))
            return out
        m := ""
        try m := AxJson.Parse(AxPkg._Read(dir "\package.json"))
        if !(m is Map) || !(AxJson.Get(m, "dependencies", "") is Map)
            return out
        for name, ver in m["dependencies"]
            if FileExist(AxPkg.Stub(dir, name))
                out[name] := String(ver)
        return out
    }
    ; What the script uses: the project's Packages, one Author/Name a line.
    static Used(P) {
        out := []
        for line in StrSplit(StrReplace(String(P.Packages), "`r"), "`n") {
            t := Trim(RegExReplace(line, "\s*;.*$"))
            if (t != "")
                out.Push(t)
        }
        return out
    }
    static IsUsed(P, name) {
        for n in AxPkg.Used(P)
            if (n = name)
                return true
        return false
    }
    static Use(P, name, on := true) {
        keep := ""
        for n in AxPkg.Used(P)
            if (n != name)
                keep .= n "`n"
        if on
            keep .= name "`n"
        P.Packages := RTrim(keep, "`n")
    }
    ; ------------------------------------------------- steps, for the rules
    ; What a rule can do with a library (Logic > Rules): "json.read data
    ; data.json" and the like, from patch.json. Verbs are one word, so a
    ; library's are named after it.
    static Steps() {
        out := []
        for e in AxPkg.List()
            for st in e.Steps
                out.Push(st)
        return out
    }
    static Step(verb) {
        for st in AxPkg.Steps()
            if (st.V = verb)
                return st
        return ""
    }
    ; One rule as code, or "" when its verb is nobody's step.
    static StepCode(project, w, f) {
        st := AxPkg.Step(f.Verb)
        if !IsObject(st)
            return ""
        a := Trim(f.Arg), who := ""
        if (st.Who != "") {
            who := RegExMatch(a, "^(\S+)", &m) ? m[1] : ""
            if (who = "")
                return ""
            a := Trim(SubStr(a, StrLen(who) + 1))
        }
        halves := StrSplit(a, "|", " `t", 2)
        path := RegExMatch(a, "^\{(\w+)\}$") ? AxFlow.Cell(project, a) : AxAsset.PathExpr(a, project)
        code := st.Code
        for k, v in Map("{who}", who, "{path}", path, "{arg1}", AxPkg._Val(project, halves[1]),
                        "{arg2}", AxPkg._Val(project, halves.Length > 1 ? halves[2] : ""),
                        "{arg}", AxPkg._Val(project, a), "{g}", w.Var)
            code := StrReplace(code, k, v)
        if (st.Sync && who != "" && AxBind.HasVar(project, who))
            code .= ", AxBindSync()"
        return code
    }
    ; a typed value, or {box} for what that control holds
    static _Val(project, t) => RegExMatch(Trim(t), "^\{(\w+)\}$") ? AxFlow.Cell(project, t) : AxFlow.V(t)
    ; The libraries the script needs: the ones it names, and the ones its
    ; rules use a step of.
    static Needed(P) {
        out := [], seen := Map()
        seen.CaseSense := false
        for n in AxPkg.Used(P)
            if !seen.Has(n)
                seen[n] := true, out.Push(n)
        for w in P.Wins
            for f in AxFlow.Parse(w)
                if IsObject(st := AxPkg.Step(f.Verb)) && !seen.Has(st.Lib)
                    seen[st.Lib] := true, out.Push(st.Lib)
        ; a macro that clicks, types into or waits for another window's elements
        if (!seen.Has(AxPkg.UiaLib) && AxAuto2.UsesUia(P))
            out.Push(AxPkg.UiaLib)
        return out
    }

    ; The #Include lines. Beside the project, the library path finds them --
    ; <Aris/Author/Name>, which is what a copied folder needs. Written anywhere
    ; else (the preview, an export elsewhere), the path to the project's Lib.
    static IncludesCode(P, outPath) {
        used := AxPkg.Needed(P)
        dir := AxPkg.ProjDir(P)
        if !used.Length || dir = ""
            return ""
        SplitPath(outPath, , &od)
        s := ""
        for name in used {
            if (od = dir)
                s .= "#Include <Aris/" name ">`n"
            else
                s .= "#Include " AxPkg._Rel(outPath, AxPkg.Stub(dir, name)) "`n"
        }
        return RTrim(s, "`n")
    }
    ; A path the way #Include takes it: relative when it can be, never quoted
    ; unless it has a space, never escaped.
    static _Rel(from, to) {
        SplitPath(from, , &fd)
        a := StrSplit(fd, "\"), b := StrSplit(to, "\")
        i := 0
        while (i < a.Length && i < b.Length && a[i + 1] = b[i + 1])
            i++
        if (i = 0)
            p := to
        else {
            p := ""
            loop a.Length - i
                p .= "..\"
            loop b.Length - i
                p .= b[i + A_Index] (A_Index < b.Length - i ? "\" : "")
        }
        return InStr(p, " ") ? '"' p '"' : p
    }

    ; ---------------------------------------------------------- running Aris
    ; verb: install | remove | update. Hidden, its output into a log, and
    ; watched rather than waited for, so the studio stays usable. done(r)
    ; gets {Ok, Log, Name, Verb}: Ok is what package.json says afterwards,
    ; not what Aris printed. One at a time.
    static Run(verb, e, dir, done) {
        if IsObject(AxPkg.Job)
            return "Aris is still busy with " AxPkg.Job.Name "."
        if !AxPkg.HasAris()
            return "Aris is not here yet."
        if (dir = "" || !DirExist(dir))
            return "Save the project first: its libraries go in a Lib folder beside it."
        log := A_Temp "\axaris_" A_TickCount ".log"
        what := (verb = "install") ? e.Install : e.Name
        cmd := A_ComSpec ' /c ""' A_AhkPath '" "' AxPkg.ArisPath() '" ' verb ' "' what '" --working-dir "'
             . dir '" > "' log '" 2>&1"'
        clip := ""
        if e.Script                        ; Aris puts the script it runs on the clipboard
            try clip := ClipboardAll()
        pid := 0
        try Run(cmd, dir, "Hide", &pid)
        catch as err
            return "Could not start Aris: " err.Message
        AxPkg.Job := {Pid: pid, Log: log, Name: e.Name, Verb: verb, Dir: dir, Done: done,
                      Clip: clip, T0: A_TickCount}
        SetTimer(AxPkg.WatchFn, 250)
        return ""
    }
    static _Watch() {
        j := AxPkg.Job
        if !IsObject(j) {
            SetTimer(AxPkg.WatchFn, 0)
            return
        }
        if (ProcessExist(j.Pid) && A_TickCount - j.T0 < 180000)
            return
        SetTimer(AxPkg.WatchFn, 0)
        if ProcessExist(j.Pid)              ; three minutes: the one started here, and only it
            try ProcessClose(j.Pid)
        text := ""
        try text := FileRead(j.Log, "UTF-8")
        try FileDelete(j.Log)
        if (j.Clip != "")
            try A_Clipboard := j.Clip
        have := AxPkg.Installed(j.Dir).Has(j.Name)
        AxPkg.Job := ""
        AxPkg._api := Map()                 ; a new version reads differently
        ok :=(j.Verb = "remove") ? !have : have
        try j.Done.Call({Ok: ok, Log: Trim(text, "`r`n "), Name: j.Name, Verb: j.Verb})
    }
    static Busy() => IsObject(AxPkg.Job) ? AxPkg.Job.Name : ""

    ; ----------------------------------------------------- what one offers
    ; Read by the parser from the files the stub includes. Each item:
    ;   {Kind "class"|"method"|"prop"|"function", Name, Owner, Static,
    ;    Params "a, b := 1", Doc, Insert}
    ; Names starting with _ are the library's own business and left out.
    static Api(dir, name) {
        key := dir "|" name
        if AxPkg._api.Has(key)
            return AxPkg._api[key]
        out := []
        main := AxPkg.MainFile(dir, name)
        if (main != "" && AxHost.Ready) {
            try {
                r := AxHost.Ask(Map("cmd", "outline", "path", main))
                files := AxJson.Get(r, "files", [])
                texts := Map()
                Doc(f, line) {
                    if !texts.Has(f)
                        try texts[f] := StrSplit(StrReplace(FileRead(files[f + 1], "UTF-8"), "`r"), "`n")
                        catch
                            texts[f] := []
                    return AxPkg._DocAbove(texts[f], line)
                }
                for c in AxJson.Get(r, "classes", []) {
                    cn := AxJson.Get(c, "name")
                    if (SubStr(cn, 1, 1) = "_")
                        continue
                    st := AxJson.Get(c, "start", Map())
                    out.Push({Kind: "class", Name: cn, Owner: "", Static: false, Params: "",
                              Doc: Doc(AxJson.Get(c, "file", 0), AxJson.Get(st, "line", 0)),
                              Insert: cn, Ext: AxJson.Get(c, "extends")})
                    for mb in AxJson.Get(c, "members", []) {
                        mn := AxJson.Get(mb, "name")
                        if (SubStr(mn, 1, 1) = "_" || mn = "")
                            continue
                        k := AxJson.Get(mb, "kind", "method")
                        ps := AxPkg._Params(AxJson.Get(mb, "params", []))
                        stat := AxJson.Get(mb, "static", 0) ? true : false
                        mst := AxJson.Get(mb, "start", Map())
                        ; a static one is called on the class, the rest on an
                        ; instance, named after the class where that reads well
                        inst := RegExMatch(cn, "^[A-Z][a-z]") ? StrLower(SubStr(cn, 1, 1)) SubStr(cn, 2) : "obj"
                        call := (stat ? cn : inst) "." mn
                        if (mn = "__New")
                            call := "x := " cn, mn := "__New"
                        out.Push({Kind: (k = "method" ? "method" : "prop"), Name: mn, Owner: cn,
                                  Static: stat, Params: ps,
                                  Doc: Doc(AxJson.Get(mb, "file", 0), AxJson.Get(mst, "line", 0)),
                                  Insert: call (k = "method" ? "(" ps ")" : "")})
                    }
                }
                for f in AxJson.Get(r, "functions", []) {
                    fn := AxJson.Get(f, "name")
                    if (SubStr(fn, 1, 1) = "_" || fn = "")
                        continue
                    ps := AxPkg._Params(AxJson.Get(f, "params", []))
                    fst := AxJson.Get(f, "start", Map())
                    out.Push({Kind: "function", Name: fn, Owner: "", Static: false, Params: ps,
                              Doc: Doc(AxJson.Get(f, "file", 0), AxJson.Get(fst, "line", 0)),
                              Insert: fn "(" ps ")"})
                }
            }
        }
        return AxPkg._api[key] := out
    }
    ; The file the stub points at, resolved the way #Include resolves it.
    static MainFile(dir, name) {
        stub := AxPkg.Stub(dir, name)
        if !FileExist(stub)
            return ""
        t := ""
        try t := FileRead(stub, "UTF-8")
        if !RegExMatch(t, "im)^\s*#include\s+(.+?)\s*(?:;.*)?$", &m)
            return ""
        p := Trim(m[1], ' "' "'")
        p := StrReplace(p, "%A_MyDocuments%", A_MyDocuments)
        SplitPath(stub, , &sd)
        if (SubStr(p, 1, 2) = ".\")
            p := sd SubStr(p, 2)
        else if !RegExMatch(p, "^[A-Za-z]:\\")
            p := sd "\" p
        return FileExist(p) ? p : ""
    }
    static _Params(list) {
        s := ""
        for p in list {
            n := AxJson.Get(p, "name")
            if AxJson.Get(p, "byref", 0)
                n := "&" n
            if AxJson.Get(p, "variadic", 0)
                n .= "*"
            else if AxJson.Get(p, "optional", 0)
                n .= AxJson.Get(p, "default", "") != "" ? " := " AxJson.Get(p, "default") : "?"
            s .= (s = "" ? "" : ", ") n
        }
        return s
    }
    ; The comment right above a line: ; lines, or a /* ... */ block, with
    ; the markers taken off. line is 1-based.
    static _DocAbove(lines, line) {
        if !(lines is Array) || line < 2
            return ""
        i := line - 1, out := []
        if (i >= 1 && RegExMatch(lines[i], "^\s*\*/\s*$")) {
            while (--i >= 1 && !RegExMatch(lines[i], "^\s*/\*"))
                out.InsertAt(1, RegExReplace(lines[i], "^\s*\*?\s?"))
        } else
            while (i >= 1 && RegExMatch(lines[i], "^\s*;\s?(.*)$", &m)) {
                out.InsertAt(1, m[1])
                i--
            }
        s := ""
        for l in out
            if !RegExMatch(l, "^[=\-*_#~ ]*$")      ; rules drawn with ;=====
                s .= (s = "" ? "" : " ") Trim(l)
        return SubStr(s, 1, 400)
    }

    ; The code editor's words for every library the script uses.
    static Words(P) {
        out := []
        dir := AxPkg.ProjDir(P)
        if (dir = "")
            return out
        for name in AxPkg.Used(P) {
            for it in AxPkg.Api(dir, name) {
                switch it.Kind {
                case "class":
                    out.Push(Map("label", it.Name, "kind", "class", "detail", name))
                case "function":
                    out.Push(Map("label", it.Name, "kind", "fn", "detail", "(" it.Params ")  " name,
                                 "insert", it.Name "($0)"))
                case "method", "prop":
                    if (it.Name = "__New")
                        continue
                    out.Push(Map("label", it.Name, "kind", it.Kind, "scope", it.Owner,
                                 "detail", it.Owner (it.Kind = "method" ? "(" it.Params ")" : ""),
                                 "insert", it.Kind = "method" ? it.Name "($0)" : ""))
                }
            }
        }
        return out
    }
}
