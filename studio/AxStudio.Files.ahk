#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\AxStudio.Assets.ahk
#Include %A_LineFile%\..\AxStudio.Steps.ahk
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
;  AxStudio.Files.ahk -- App > Files: the files the program needs, as a
;  manager rather than a list of lines.
;
;  Every file says what it is (a picture shows itself), whether it is really
;  there and how big, how the finished program gets it -- the three ways,
;  switched right on the row -- and which pieces of code use it, each a link
;  to its steps. What the code names that is not listed ("prices.csv" in a
;  FileRead) is found and offered: add it, and optionally switch the code over
;  to File_<name>(), so it ships with the program and cannot go missing.
;
;  Paths are kept relative to the project's folder whenever the file is in
;  it, because that is where the exported script lives and what A_ScriptDir
;  is. A file picked from somewhere else can be copied in. Try and Run work
;  from the studio's own folder, so the listed files are copied there first
;  (Stage) -- a run sees the same files the exported program will.
;
;  The text is still the truth: name | path | how, one per line (AxAsset).
; =============================================================================
class AxFilesUi {
    static Kinds := Map(
        "png", "pic", "jpg", "pic", "jpeg", "pic", "gif", "pic", "bmp", "pic", "ico", "pic", "svg", "pic", "webp", "pic",
        "txt", "text", "csv", "text", "tsv", "text", "json", "text", "ini", "text", "xml", "text", "html", "text",
        "htm", "text", "css", "text", "md", "text", "log", "text", "yaml", "text", "yml", "text", "js", "text",
        "wav", "sound", "mp3", "sound", "ogg", "sound", "dll", "prog", "exe", "prog", "ahk", "prog")
    static KindOf(path) {
        SplitPath(path, , , &ext)
        ext := StrLower(ext)
        return AxFilesUi.Kinds.Has(ext) ? AxFilesUi.Kinds[ext] : "other"
    }
    static KindIcon(k) {
        static m := Map("pic", "EB9F", "text", "E8A5", "sound", "E8D6", "prog", "E756", "other", "E7C3")
        return m[k]
    }
    ; what a kind of file should do, in words, and which way suits it
    static Suits(k) => (k = "text") ? "resource" : "install"

    ; the folder the paths are relative to: the project's, once it is saved
    static Base(s) {
        d := AxPkg.ProjDir(s.P)
        return d
    }
    static Abs(s, path) {
        path := Trim(path)
        if RegExMatch(path, "^%(A_\w+)%\\?(.*)$", &m) {
            try return %m[1]% (m[2] != "" ? "\" m[2] : "")
            return path
        }
        if (SubStr(path, 1, 2) = "\\" || InStr(path, ":\") = 2)
            return path
        b := AxFilesUi.Base(s)
        return (b != "" ? b "\" : A_WorkingDir "\") path
    }
    static Rel(s, path) {
        b := AxFilesUi.Base(s)
        if (b != "" && SubStr(StrLower(path), 1, StrLen(b) + 1) = StrLower(b) "\")
            return SubStr(path, StrLen(b) + 2)
        return path
    }
    static Size(n) => (n < 1024) ? n " bytes" : (n < 1048576) ? Round(n / 1024) " KB" : Round(n / 1048576, 1) " MB"

    ; ------------------------------------------------------------- the page
    static Page(s, add) {
        E := (t) => AxTags.E(t)
        files := AxAsset.Files(s.P)
        raw := AxLogic.Raw.Has("files")
        tools := '<span class="axd-hbtn" data-files="add">Add files...</span> '
               . '<span class="axd-hbtn' (raw ? " on" : "") '" data-do="logic.raw.files">' (raw ? "Back to the files" : "Edit as text") '</span>'
        h := AxPanes.PanelHead("Files", "Pictures, data, sounds -- files the program needs. For each one: where it is now, "
               . "and how the finished program gets it. The code reaches any of them the same way, compiled or not: "
               . "<b>File_</b><i>name</i><b>()</b>.", tools)
        if raw
            return h '<div class="axd-rpcontent">' add({Id: "lg_files", L: "One per line", Kind: "multiline", Rows: 8,
                        Get: (*) => s.P.Files, Set: (v) => (s.P.Files := v, s.QueueLive())})
                 . '<div class="axd-note"><b>name | path | how</b> -- how is <b>install</b> (carried and written out), '
                 . '<b>resource</b> (carried, read from memory) or <b>path</b> (looked for).</div></div>'
        base := AxFilesUi.Base(s)
        if (base = "")
            h .= '<div class="axd-note axd-pkwarn"><span class="ico">&#xE7BA;</span> Save the project first: file paths are '
               . 'kept relative to its folder, which is where the exported script goes.</div>'
        ; the summary
        inside := 0, bytes := 0, missing := 0
        for f in files {
            ab := AxFilesUi.Abs(s, f.Path)
            sz := FileExist(ab) ? FileGetSize(ab) : -1
            missing += (sz < 0)
            if (f.How != "path" && sz > 0)
                inside++, bytes += sz
        }
        if files.Length
            h .= '<div class="axf-sum"><b>' files.Length '</b> file' (files.Length = 1 ? "" : "s")
               . ' <span>&#183;</span> <b>' inside '</b> carried inside the exe' (bytes ? " (" AxFilesUi.Size(bytes) ")" : "")
               . (missing ? ' <span>&#183;</span> <b class="axf-bad">' missing ' not found</b>' : "") '</div>'
        uses := AxFilesUi.Uses(s)
        if !files.Length
            h .= '<div class="axd-rpempty"><span class="ico axd-rpbig">&#xE8A5;</span><div class="axd-rpemptyt">No files yet</div>'
               . '<div class="axd-rpemptyb"><span class="axd-hbtn" data-files="add">Add files...</span></div>'
               . '<div class="axd-note">Or pick <b>Read or write a file</b> in a step (Steps): a file it reads '
               . 'can be added here for you.</div></div>'
        for f in files
            h .= AxFilesUi.Row(s, f, uses)
        h .= AxFilesUi.Found(s, files)
        return h
    }
    static Row(s, f, uses) {
        E := (t) => AxTags.E(t)
        ab := AxFilesUi.Abs(s, f.Path)
        have := FileExist(ab) != "" && !InStr(FileExist(ab), "D")
        k := AxFilesUi.KindOf(f.Path)
        fn := AxAsset.FileFn(f.Name)
        nm := E(f.Name)
        pic := (k = "pic" && have) ? '<img src="file:///' E(StrReplace(ab, "\", "/")) '">' : '<span class="ico">&#x' AxFilesUi.KindIcon(k) ';</span>'
        h := '<div class="axf-row' (have ? "" : " bad") '"><div class="axf-pic">' pic '</div><div class="axf-main">'
           . '<div class="axf-name"><b>' nm '</b><code title="What the code calls to get it">' E(fn) '()</code>'
           . '<span class="axf-acts"><span class="axd-ract" data-files="rename|' nm '">Rename</span>'
           . '<span class="axd-ract" data-files="pick|' nm '">Another file...</span>'
           . (have ? '<span class="axd-ract" data-files="show|' nm '">Show in Explorer</span>' : "")
           . '<span class="axd-ract axd-ractdel" data-files="del|' nm '" data-tip="Take it off the list. Ctrl+Z brings it back.">&#xE711;</span></span></div>'
           . '<div class="axf-where">' E(f.Path) ' <span class="' (have ? 'axf-ok">' AxFilesUi.Size(FileGetSize(ab)) : 'axf-bad">not found') '</span>'
           . (have && AxFilesUi.Rel(s, ab) = ab && AxFilesUi.Base(s) != "" ? ' <span class="axd-ract" data-files="copyin|' nm '">Copy it into the project folder</span>' : "")
           . '</div>'
        ; how the program gets it, switched right here
        opts := [["path", "Look for it beside the program"], ["resource", "Carry it inside, read from memory"],
                 ["install", "Carry it inside, write it out beside the program"]]
        seg := ""
        for o in opts
            seg .= '<span class="' (f.How = o[1] ? "on" : "") '" data-files="how|' nm '|' o[1] '">' o[2] '</span>'
        h .= '<div class="axf-how">' seg '</div>'
        why := (f.How = "path") ? "Nothing is carried: the file has to be beside the program when it runs. Good for big files, or ones people are meant to change."
             : (f.How = "resource") ? "Built into the exe and never written to disk; the code gets its text. Only for text the program reads."
             : "Built into the exe and written out beside it the first time it runs; the code gets its path. For pictures, sounds, anything that has to be a real file."
        if (f.How = "resource" && k != "text")
            why := '<span class="axf-bad">A ' (k = "pic" ? "picture" : k = "sound" ? "sound" : "file like this") ' is not text: '
                 . 'carry it and write it out instead.</span>'
        h .= '<div class="axf-why">' why '</div>'
        ; who uses it
        u := uses.Has(StrLower(fn)) ? uses[StrLower(fn)] : []
        h .= '<div class="axf-uses">'
        if !u.Length
            h .= '<span class="axd-dim">No code uses it yet.</span> <span class="axd-ract" data-files="usein|' nm '">Read it in a step...</span>'
        else {
            h .= '<span class="axd-dim">Used by </span>'
            for x in u
                h .= '<span class="axd-chip" data-files="steps|' E(x.Key) '">' E(x.Label) '</span>'
        }
        return h '</div></div></div>'
    }

    ; ---------------------------------------------------- who uses what
    ; Every piece of code, and every File_x( in it: fn (lower) -> [{Key, Label}]
    static Uses(s) {
        out := Map()
        for x in AxFilesUi.Texts(s) {
            p := 1
            while (p := RegExMatch(x.Text, "i)\b(File_\w+)\(", &m, p)) {
                k := StrLower(m[1])
                if !out.Has(k)
                    out[k] := []
                dup := false
                for y in out[k]
                    dup := dup || (y.Key = x.Key)
                if !dup
                    out[k].Push({Key: x.Key, Label: x.Label})
                p += m.Len
            }
        }
        return out
    }
    static Texts(s) {
        out := []
        for pc in AxSteps.Pieces(s.P) {
            if (pc.Pc.Kind = "fn")
                continue                        ; the script as a whole, below
            t := AxSteps.Get(s, pc.Pc)
            if (t != "")
                out.Push({Key: pc.Key, Label: pc.Label, Text: t})
        }
        for wi, w in s.P.Wins
            if (Trim(w.Script) != "") {
                ; each function in it on its own, so a use names its function
                for d in AxSteps.Defs(w.Script)
                    out.Push({Key: "fn." wi "." d.Name, Label: d.Label, Text: AxFilesUi.DefText(w.Script, d.Name)})
            }
        return out
    }
    static DefText(script, name) {
        try {
            t := AxHost.TreeText(script)
            for i in t.Children(0) {
                if (t.Value(i) = name || "hk:" t.Value(i) = name)
                    return t.Text(i, script)
                if (t.Type(i) = "Class")
                    for c in t.Children(i)
                        if (t.Value(i) "." t.Value(c) = name)
                            return t.Text(c, script)
            }
        }
        return ""
    }

    ; ------------------------------------------- named in the code, not listed
    ; "prices.csv", A_ScriptDir "\prices.csv": a file the code opens by name
    static Found(s, files) {
        have := Map(), have.CaseSense := false
        for f in files
            have[f.Path] := 1, have[f.Name] := 1
        seen := Map(), seen.CaseSense := false
        rows := ""
        for x in AxFilesUi.Texts(s) {
            p := 1
            while (p := RegExMatch(x.Text, 'i)(?:A_ScriptDir\s*"\\)?"?([^"\r\n*?<>|]+\.(?:txt|csv|tsv|json|ini|xml|html?|css|md|png|jpe?g|gif|bmp|ico|svg|wav|mp3|dll))"', &m, p)) {
                path := m[1]
                p += m.Len
                if have.Has(path) || seen.Has(path) || InStr(path, "%")
                    continue
                seen[path] := 1
                ab := AxFilesUi.Abs(s, path)
                there := FileExist(ab) != ""
                rows .= '<div class="axf-found"><span class="ico">&#x' AxFilesUi.KindIcon(AxFilesUi.KindOf(path)) ';</span>'
                      . '<b>' AxTags.E(path) '</b> <span class="axd-dim">in ' AxTags.E(x.Label) '</span> '
                      . '<span class="' (there ? "axf-ok" : "axf-bad") '">' (there ? "found" : "not beside the project yet") '</span>'
                      . '<span class="axf-acts"><span class="axd-ract" data-files="adopt|' AxTags.E(path) '">Add it</span>'
                      . '<span class="axd-ract" data-files="adoptuse|' AxTags.E(path) '|' AxTags.E(x.Key) '">Add it, and have the code use File_()</span></span></div>'
            }
        }
        if (rows = "")
            return ""
        return '<div class="axd-rpsub">Named in the code, not on the list</div>'
             . '<div class="axd-note">The code opens these by name. On the list, the finished program can carry them, '
             . 'and a missing one is caught here rather than when it runs.</div>' rows
    }

    ; ------------------------------------------------------------- clicks
    static Act(s, v) {
        p := StrSplit(v, "|")
        verb := p[1], arg := p.Length > 1 ? p[2] : ""
        f := ""
        for x in AxAsset.Files(s.P)
            if (x.Name = arg)
                f := x
        switch verb {
        case "add":    return AxFilesUi.AddFiles(s)
        case "how":
            if IsObject(f)
                AxFilesUi.Put(s, f, f.Name, f.Path, p[3])
        case "del":
            if IsObject(f) {
                s.PutLine("Files", f.Line, "")
                s.Refresh()
                s.Status("msg", f.Name " is off the list. Ctrl+Z brings it back.")
            }
        case "rename":
            if !IsObject(f)
                return
            r := AxForm.Show(s, {Title: "Rename a file", Icon: "E8AC", Width: 460,
                Intro: "The name the code knows it by. Code that already calls " AxAsset.FileFn(f.Name) "() is changed to match.",
                Fields: [{Id: "name", L: "Called", Kind: "text", V: f.Name}],
                Buttons: ["Rename", "Cancel"],
                Check: (V) => AxProject.CleanName(V["name"]) = "" ? "Give it a usable name." : "",
                Preview: (V) => AxAsset.FileFn(V["name"]) "()"})
            if !r.Ok
                return
            nn := Trim(r.V["name"])
            s.Mark()
            AxFilesUi.RenameInCode(s, AxAsset.FileFn(f.Name), AxAsset.FileFn(nn))
            AxFilesUi.Put(s, f, nn, f.Path, f.How, false)
        case "pick":
            if !IsObject(f)
                return
            pth := FileSelect(3, AxFilesUi.Abs(s, f.Path), "Which file is " f.Name "?")
            if (pth != "")
                AxFilesUi.Put(s, f, f.Name, AxFilesUi.Rel(s, pth), f.How)
        case "show":
            if IsObject(f)
                try Run('explorer.exe /select,"' AxFilesUi.Abs(s, f.Path) '"')
        case "copyin":
            if !IsObject(f)
                return
            src := AxFilesUi.Abs(s, f.Path)
            SplitPath(src, &fname)
            dst := AxFilesUi.Base(s) "\" fname
            try FileCopy(src, dst, false)
            catch as e
                return s.Alert("Could not copy it: " e.Message, "Files")
            AxFilesUi.Put(s, f, f.Name, fname, f.How)
            s.Status("msg", fname " is in the project folder now.")
        case "steps":
            AxSteps.Pc := AxSteps.FromKey(arg), AxSteps.Sel := ""
            return AxMap.SetMode(s, "steps")
        case "usein":
            if !IsObject(f)
                return
            ; the startup code, as steps, with a step reading it at the end
            AxSteps.Pc := {Kind: "init", Win: s.P.Cur}, AxSteps.Sel := ""
            AxMap.SetMode(s, "steps")
            s.Status("msg", "Press the + where it should be read, and pick Read or write a file -- it is " AxAsset.FileFn(f.Name) "().")
        case "adopt", "adoptuse":
            path := arg
            SplitPath(path, &fname)
            name := AxProject.CleanName(RegExReplace(fname, "\.[^.]*$"))
            k := AxFilesUi.KindOf(path)
            ; a path-handing way, so File_x() can stand where the path stood
            how := (verb = "adoptuse") ? "install" : AxFilesUi.Suits(k)
            s.Mark()
            s.AppendProject("Files", AxAsset.FileLine(name, path, how))
            if (verb = "adoptuse")
                AxFilesUi.UseInCode(s, path, AxAsset.FileFn(name) "()", p.Length > 2 ? p[3] : "")
            s.Refresh()
            s.Status("msg", path " is on the list" (verb = "adoptuse" ? ", and the code gets it from " AxAsset.FileFn(name) "()." : "."))
        }
    }
    ; one file's line, changed
    static Put(s, f, name, path, how, mark := true) {
        s.PutLine("Files", f.Line, AxAsset.FileLine(name, path, how), mark)
        s.Refresh()
        s.QueueLive()
    }
    ; Add files: any number at once, relative to the project when inside it;
    ; picked from elsewhere, copied in if asked. Each goes the way that suits
    ; what it is.
    static AddFiles(s) {
        pick := FileSelect("M3", AxFilesUi.Base(s), "The files the program needs")
        if !IsObject(pick) || !pick.Length
            return
        base := AxFilesUi.Base(s)
        outside := 0
        for pth in pick
            outside += (base != "" && AxFilesUi.Rel(s, pth) = pth)
        copy := false
        if outside
            copy := s.Confirm(outside " of them " (outside = 1 ? "is" : "are") " not in the project's folder.`n`n"
                  . "Copy " (outside = 1 ? "it" : "them") " in? Then the project folder holds everything the program needs, "
                  . "and it can be moved or shared as one.", "Add files", "Copy them in", "Leave them where they are")
        s.Mark()
        have := Map(), have.CaseSense := false
        for f in AxAsset.Files(s.P)
            have[AxAsset.FileFn(f.Name)] := 1
        added := 0
        for pth in pick {
            SplitPath(pth, &fname)
            if (copy && base != "" && AxFilesUi.Rel(s, pth) = pth) {
                try FileCopy(pth, base "\" fname, false)
                pth := base "\" fname
            }
            name := AxProject.CleanName(RegExReplace(fname, "\.[^.]*$"))
            n := 2, nm := name
            while have.Has(AxAsset.FileFn(nm))
                nm := name n++
            have[AxAsset.FileFn(nm)] := 1
            s.AppendProject("Files", AxAsset.FileLine(nm, AxFilesUi.Rel(s, pth), AxFilesUi.Suits(AxFilesUi.KindOf(pth))))
            added++
        }
        s.Refresh()
        s.Status("msg", added " file" (added = 1 ? "" : "s") " added. Each is carried the way that suits it -- change it on its row.")
    }
    ; File_old( -> File_new( in every piece of code
    static RenameInCode(s, old, new) {
        for wi, w in s.P.Wins {
            w.Init := RegExReplace(w.Init, "i)\b" old "\(", new "(")
            w.Script := RegExReplace(w.Script, "i)\b" old "\(", new "(")
            for n in AxImport.Nodes(w.Root)
                for e in n.Ev
                    e["code"] := RegExReplace(e["code"], "i)\b" old "\(", new "(")
        }
    }
    ; the literal path, where the code names it, becomes the call
    static UseInCode(s, path, call, key) {
        pat := 'i)(?:A_ScriptDir\s*"\\)?"?' '\Q' path '\E' '"'
        for x in AxFilesUi.Texts(s) {
            if (key != "" && x.Key != key)
                continue
            pc := AxSteps.FromKey(x.Key)
            if (pc.Kind = "fn") {
                w := s.P.Wins[pc.Win]
                w.Script := RegExReplace(w.Script, pat, call)
            } else {
                t := AxSteps.Get(s, pc)
                if RegExMatch(t, pat)
                    AxSteps.Put(s, pc, RegExReplace(t, pat, call))
            }
        }
        s.P.Dirty := true
    }

    ; ------------------------------------------------------- Try and Run
    ; A run starts from the studio's own folder, so the files on the list are
    ; put beside it first: the run sees what the exported program will.
    static Stage(s, dir) {
        for f in AxAsset.Files(s.P) {
            src := AxFilesUi.Abs(s, f.Path)
            if !FileExist(src) || InStr(FileExist(src), "D")
                continue
            rel := AxFilesUi.Rel(s, src)
            if (rel = src)
                continue                          ; absolute: the program reads it where it is
            dst := dir "\" rel
            SplitPath(dst, , &dd)
            try DirCreate(dd)
            try {
                if !FileExist(dst) || FileGetTime(src) > FileGetTime(dst)
                    FileCopy(src, dst, true)
            }
        }
    }
}
