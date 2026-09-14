#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\AxJson.ahk
#Include %A_LineFile%\..\AxStudio.Pkg.ahk
#Include %A_LineFile%\..\AxStudio.Form.ahk
#Include %A_LineFile%\..\AxStudio.PkgUi.ahk

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
;  AxStudio.Update.ahk -- is there anything newer: the library and the studio,
;  Aris, its list of libraries, and the libraries this project has installed
;  (AHK# among them, when it is one of them).
;
;  Nothing is downloaded or run to find out, only read:
;
;      AxGui and AxStudio   version.json at the top of github.com/owhs/axahk
;                           {"axahk": "1.0", "axstudio": "0.9", "notes": ...};
;                           failing that, the repository's latest release
;      Aris                 the "version" in its own package.json, here and on
;                           GitHub
;      Aris's list          fetched again (AxPkg.RefreshIndex)
;      a library            its repository's latest release on GitHub, or its
;                           newest version-like tag, against the version this
;                           project's package.json says is installed
;
;  All the requests go out at once and are waited for together, a few seconds
;  at most. What was found is kept (AxUpdate.Libs) so App > Libraries can mark
;  a library with a newer version. Updating is then one button: Aris again,
;  `aris update` for each library, or the release page for the studio.
; =============================================================================
class AxUpdate {
    static Repo := "owhs/axahk"
    static Page := "https://github.com/owhs/axahk"
    static VersionUrl := "https://raw.githubusercontent.com/owhs/axahk/main/version.json"
    static ReleaseUrl := "https://api.github.com/repos/owhs/axahk/releases/latest"
    static ArisUrl := "https://raw.githubusercontent.com/Descolada/Aris/main/package.json"
    static Last := ""                   ; the last check: {At, Items, Libs}
    static Libs := Map()                ; "Author/Name" -> {Have, Latest, State}

    ; ------------------------------------------------------------ fetching
    ; Several GETs at once; each comes back as {Url, Status, Text}. Status 0
    ; is "no answer" -- offline, blocked, or too slow.
    static Fetch(urls, timeout := 8000) {
        reqs := []
        for u in urls {
            r := {Url: u, Status: 0, Text: "", Req: ""}
            try {
                q := ComObject("WinHttp.WinHttpRequest.5.1")
                q.Open("GET", u, true)
                q.SetRequestHeader("User-Agent", "AxStudio/" AxStudio.Ver)
                if InStr(u, "api.github.com")
                    q.SetRequestHeader("Accept", "application/vnd.github+json")
                q.Send()
                r.Req := q
            } catch as e
                r.Text := e.Message
            reqs.Push(r)
        }
        t0 := A_TickCount
        loop {
            left := 0
            for r in reqs {
                if !IsObject(r.Req)
                    continue
                done := false
                try done := r.Req.WaitForResponse(0)
                if done {
                    try r.Status := r.Req.Status
                    try r.Text := r.Req.ResponseText
                    r.Req := ""
                } else
                    left += 1
            }
            if (!left || A_TickCount - t0 > timeout)
                break
            Sleep(40)                       ; the window stays responsive meanwhile
        }
        for r in reqs
            if IsObject(r.Req) {
                try r.Req.Abort()
                r.Req := "", r.Text := "no answer in " Round(timeout / 1000) " seconds"
            }
        return reqs
    }
    ; "^1.2.3", "v1.2", "=1.0+build" -> "1.2.3"; "" when it is not a version
    ; at all (a branch, a commit)
    static Plain(v) {
        v := RegExReplace(Trim(String(v)), "^[\^~=v><\s]+")
        v := RegExReplace(v, "\+.*$")
        return RegExMatch(v, "^\d+(\.\d+)*(-[0-9A-Za-z.-]+)?$") ? v : ""
    }
    ; 1 when b is newer than a, 0 when not, "" when either is not a version
    static Newer(a, b) {
        a := AxUpdate.Plain(a), b := AxUpdate.Plain(b)
        if (a = "" || b = "")
            return ""
        try return VerCompare(b, a) > 0 ? 1 : 0
        return ""
    }
    ; The GitHub "owner/repo" a library comes from: the list's repository
    ; ("Author/Name/branch", or a URL), else its own name, which is where
    ; Aris goes for a library it has no entry for.
    static RepoOf(name) {
        pk := AxPkg.Find(name)
        r := IsObject(pk) ? String(pk.Repo) : ""
        if RegExMatch(r, "i)github\.com[/:]([\w.-]+)/([\w.-]+?)(?:\.git)?(?:[/#?]|$)", &m)
            return m[1] "/" m[2]
        if RegExMatch(r, "^([\w.-]+)/([\w.-]+)", &m)
            return m[1] "/" m[2]
        return RegExMatch(name, "^[\w.-]+/[\w.-]+$") ? name : ""
    }
    static _J(text) {
        m := ""
        try m := AxJson.Parse(RegExReplace(text, "^\x{FEFF}"))      ; Aris's package.json starts with one
        return m
    }
    static _G(m, k, d := "") => (m is Map && m.Has(k)) ? m[k] : d

    ; ------------------------------------------------------------ checking
    ; Everything, for the project open in s. Items are rows for the form:
    ;   {What, Have, Latest, State ok|new|unknown|offline|none|absent, Note, Act}
    static Check(s) {
        dir := AxPkg.ProjDir(s.P), have := AxPkg.Installed(dir)
        urls := [AxUpdate.VersionUrl, AxUpdate.ReleaseUrl]
        if AxPkg.HasAris()
            urls.Push(AxUpdate.ArisUrl)
        libs := []
        for name, ver in have {
            repo := AxUpdate.RepoOf(name)
            if (repo = "")
                continue
            l := {Name: name, Have: ver, Repo: repo,
                  Rel: "https://api.github.com/repos/" repo "/releases/latest",
                  Tags: "https://api.github.com/repos/" repo "/tags?per_page=40"}
            libs.Push(l)
            urls.Push(l.Rel), urls.Push(l.Tags)
        }
        got := Map()
        for r in AxUpdate.Fetch(urls)
            got[r.Url] := r
        items := []

        ; the library and the studio
        v := got[AxUpdate.VersionUrl], rel := got[AxUpdate.ReleaseUrl]
        lib := "", std := "", note := "", page := AxUpdate.Page
        if (v.Status = 200 && (m := AxUpdate._J(v.Text)) is Map) {
            lib := AxUpdate._G(m, "axahk"), std := AxUpdate._G(m, "axstudio")
            note := AxUpdate._G(m, "notes"), page := AxUpdate._G(m, "page", page)
        } else if (rel.Status = 200 && (m := AxUpdate._J(rel.Text)) is Map) {
            lib := AxUpdate.Plain(AxUpdate._G(m, "tag_name")), note := AxUpdate._G(m, "name")
            page := AxUpdate._G(m, "html_url", page)
        }
        gone := (v.Status = 404 && (rel.Status = 404 || rel.Status = 0))
        for x in [["AxGui", AxGui.Version, lib], ["AxStudio", AxStudio.Ver, std]] {
            st := (x[3] != "") ? (AxUpdate.Newer(x[2], x[3]) ? "new" : "ok")
                : gone ? "none" : (v.Status = 0 && rel.Status = 0) ? "offline" : "unknown"
            items.Push({What: x[1], Have: x[2], Latest: x[3], State: st, Act: "page", Page: page,
                        Note: st = "none" ? AxUpdate.Repo " has not published a version yet"
                            : st = "offline" ? "GitHub did not answer" : (st = "new" && note != "") ? note : ""})
        }

        ; Aris, and its list
        if AxPkg.HasAris() {
            here := ""
            try here := AxUpdate._G(AxUpdate._J(AxPkg._Read(AxPkg.Dir() "\package.json")), "version")
            a := got[AxUpdate.ArisUrl], there := ""
            if (a.Status = 200)
                there := AxUpdate._G(AxUpdate._J(a.Text), "version")
            st := (there = "") ? (a.Status = 0 ? "offline" : "unknown")
                : (here = "" || AxUpdate.Newer(here, there)) ? "new" : "ok"
            items.Push({What: "Aris", Have: here != "" ? here : "unknown", Latest: there, State: st, Act: "aris",
                        Note: st = "new" && here = "" ? "this copy does not say which version it is" : ""})
            msg := AxPkg.RefreshIndex()
            n := AxPkg.List().Length
            items.Push({What: "Aris's list of libraries", Have: "", Latest: "", State: msg = "" ? "ok" : "offline",
                        Act: "", Note: msg = "" ? "fetched just now: " n " libraries" : msg})
        } else
            items.Push({What: "Aris", Have: "", Latest: "", State: "absent", Act: "",
                        Note: "downloaded the first time a library is wanted (App > Libraries)"})

        ; this project's libraries
        out := []
        for l in libs {
            latest := "", r := got[l.Rel]
            if (r.Status = 200)
                latest := AxUpdate.Plain(AxUpdate._G(AxUpdate._J(r.Text), "tag_name"))
            if (latest = "" && got[l.Tags].Status = 200 && (t := AxUpdate._J(got[l.Tags].Text)) is Array)
                for tg in t {
                    pv := AxUpdate.Plain(AxUpdate._G(tg, "name"))
                    if (pv != "" && (latest = "" || AxUpdate.Newer(latest, pv)))
                        latest := pv
                }
            limit := (r.Status = 403 || got[l.Tags].Status = 403)
            st := (latest = "") ? (r.Status = 0 ? "offline" : "unknown")
                : AxUpdate.Newer(l.Have, latest) = 1 ? "new"
                : AxUpdate.Newer(l.Have, latest) = 0 ? "ok" : "unknown"
            one := {What: l.Name, Have: l.Have, Latest: latest, State: st, Act: "lib", Repo: l.Repo,
                    Note: limit ? "GitHub asks to wait a while before more questions (an hourly limit)"
                        : (latest = "" && st = "unknown") ? "no released versions to compare with" : ""}
            out.Push(one)
            AxUpdate.Libs[l.Name] := {Have: l.Have, Latest: latest, State: st}
        }
        AxUpdate.Last := {At: A_Now, Items: items, Libs: out, Dir: dir}
        return AxUpdate.Last
    }
    ; libraries of this project with a newer version
    static Outdated(s) {
        out := []
        for name, v in AxPkg.Installed(AxPkg.ProjDir(s.P))
            if (AxUpdate.Libs.Has(name) && AxUpdate.Libs[name].State = "new")
                out.Push(name)
        return out
    }
    static Latest(name) => (AxUpdate.Libs.Has(name) && AxUpdate.Libs[name].State = "new") ? AxUpdate.Libs[name].Latest : ""

    ; ---------------------------------------------------------------- form
    static Show(s) {
        s.Status("msg", "Checking for updates...")
        c := AxUpdate.Check(s)
        E := (t) => AxTags.E(t)
        ico := Map("ok", "E73E", "new", "E896", "unknown", "E9CE", "offline", "E7BA", "none", "E946", "absent", "E946")
        word := Map("ok", "up to date", "new", "newer version", "unknown", "can't tell", "offline", "no answer", "none", "not published", "absent", "not here yet")
        Row(x) => '<tr class="axd-up-' x.State '"><td><span class="ico">&#x' ico[x.State] ';</span> <b>' E(x.What) '</b></td>'
            . '<td class="axd-mono">' E(x.Have) '</td><td class="axd-mono">' E(x.Latest) '</td>'
            . '<td>' E(word[x.State]) (x.Note != "" ? '<div class="axd-dim">' E(x.Note) '</div>' : "") '</td></tr>'
        head := '<tr><th></th><th>Here</th><th>Newest</th><th></th></tr>'
        h := '<table class="axd-lgt">' head
        for x in c.Items
            h .= Row(x)
        h .= '</table>'
        if c.Libs.Length {
            h .= '<div class="axd-rpsub">This project&#39;s libraries (' c.Libs.Length ')</div><table class="axd-lgt">' head
            for x in c.Libs
                h .= Row(x)
            h .= '</table>'
        } else
            h .= '<div class="axd-note axd-dim">' (c.Dir = "" ? "Save the project to see its libraries here."
                : "This project has no libraries installed.") '</div>'
        ; what can be done about it
        btns := [], newLib := AxUpdate.Outdated(s), newAris := false, newUs := false
        for x in c.Items {
            if (x.Act = "aris" && x.State = "new")
                newAris := true
            if (x.Act = "page" && x.State = "new")
                newUs := true
        }
        if newLib.Length
            btns.Push("Update " (newLib.Length = 1 ? newLib[1] : "the " newLib.Length " libraries"))
        if newAris
            btns.Push("Get the new Aris")
        btns.Push(newUs ? "Open the release page" : "Open the project page")
        btns.Push("Close")
        s.Status("msg", "Checked for updates.")
        r := AxForm.Show(s, {Title: "Updates", Icon: "E895", Width: 640,
            Intro: "What is here, and the newest there is. Nothing is changed until you pick a button.",
            Fields: [{Id: "up", Kind: "note", Html: true, L: h}],
            Buttons: btns, CancelIndex: btns.Length})
        if !r.Ok && r.Label = ""
            return
        if InStr(r.Label, "Update ") = 1
            AxUpdate.UpdateLibs(s, newLib)
        else if (r.Label = "Get the new Aris") {
            s.Status("msg", "Getting Aris from github.com/Descolada/Aris...")
            msg := AxPkg.GetAris()
            if (msg != "")
                return s.Alert(msg, "Updates")
            s.Status("msg", "Aris is up to date.")
            s.Reflect(false)
        } else if InStr(r.Label, "Open the") = 1 {
            pg := AxUpdate.Page
            for x in c.Items
                if (x.Act = "page" && x.HasOwnProp("Page") && RegExMatch(x.Page, "i)^https://"))
                    pg := x.Page
            try Run(pg)
        }
    }
    ; one after another: Aris does one thing at a time
    static UpdateLibs(s, names) {
        if !names.Length {
            s.Status("msg", "The libraries are up to date.")
            return
        }
        name := names.RemoveAt(1)
        if AxUpdate.Libs.Has(name)
            AxUpdate.Libs[name].State := "ok"
        AxPkgUi.RunAris(s, "update", name, AxUpdate.NextFn(s, names))
    }
    static NextFn(s, names) => (ok) => AxUpdate.UpdateLibs(s, names)
}
