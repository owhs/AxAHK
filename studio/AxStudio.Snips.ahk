#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\AxJson.ahk
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
;  AxStudio.Snips.ahk -- your own snippets.
;
;  The studio has shipped a list of ready lines since the beginning, and it
;  was a list you could read and not add to: the one piece of code you paste
;  into every program you write was the one piece that was not there. Every
;  editor in the world lets you keep your own, and this one would not.
;
;  A snippet is a name, some code, and a group to keep it under. They live in
;  data\snippets.json beside the studio's other things, so they travel with
;  the folder and are yours across every project.
;
;      AxSnips.All()                 [{N, C, G}] -- name, code, group
;      AxSnips.Put(name, code, grp)  add or replace, by name
;      AxSnips.Remove(name)
;      AxSnips.Manage(s)             the tool window: write, change, organise
;      AxSnips.FromSelection(s)      what is selected in the editor, kept
;
;  Nothing here knows about the shipped list: the menu shows yours first and
;  then the studio's, and neither can overwrite the other.
; =============================================================================
class AxSnips {
    static _list := ""

    static File() => AxStudioPaths.Data() "\snippets.json"

    static All() {
        if IsObject(AxSnips._list)
            return AxSnips._list
        out := []
        try {
            if FileExist(AxSnips.File()) {
                r := AxJson.Parse(FileRead(AxSnips.File(), "UTF-8"))
                items := (r is Map && r.Has("snippets")) ? r["snippets"] : r
                if !(items is Array)
                    items := []
                for x in items
                    if (x is Map && Trim(AxJson.Get(x, "name", "")) != "")
                        out.Push({N: AxJson.Get(x, "name", ""), C: AxJson.Get(x, "code", ""),
                                  G: AxJson.Get(x, "group", "")})
            }
        }
        return AxSnips._list := out
    }
    static Save() {
        items := []
        for sn in AxSnips.All()
            items.Push(Map("name", sn.N, "code", sn.C, "group", sn.G))
        try {
            txt := AxJson.Stringify(Map("snippets", items), "  ")
            f := FileOpen(AxSnips.File(), "w", "UTF-8")
            f.Write(txt)
            f.Close()
            return true
        }
        return false
    }
    static Find(name) {
        for i, sn in AxSnips.All()
            if (sn.N = name)
                return i
        return 0
    }
    static Get(name) {
        i := AxSnips.Find(name)
        return i ? AxSnips.All()[i] : ""
    }
    ; Add or replace, by name. `was` renames rather than making a second one.
    static Put(name, code, group := "", was := "") {
        name := Trim(name)
        if (name = "")
            return false
        list := AxSnips.All()
        i := (was != "" && was != name) ? AxSnips.Find(was) : AxSnips.Find(name)
        if i
            list[i] := {N: name, C: code, G: Trim(group)}
        else
            list.Push({N: name, C: code, G: Trim(group)})
        return AxSnips.Save()
    }
    static Remove(name) {
        i := AxSnips.Find(name)
        if !i
            return false
        AxSnips.All().RemoveAt(i)
        return AxSnips.Save()
    }
    ; Yours, grouped -- the shape the menu wants: [{G, Items: [{N, C}]}]
    static Grouped() {
        order := [], by := Map()
        for sn in AxSnips.All() {
            g := (Trim(sn.G) = "") ? "" : Trim(sn.G)
            if !by.Has(g)
                by[g] := [], order.Push(g)
            by[g].Push(sn)
        }
        out := []
        for g in order
            out.Push({G: g, Items: by[g]})
        return out
    }
    static Groups() {
        out := "", seen := Map()
        seen.CaseSense := false
        for sn in AxSnips.All()
            if (Trim(sn.G) != "" && !seen.Has(Trim(sn.G)))
                seen[Trim(sn.G)] := 1, out .= (out = "" ? "" : "|") Trim(sn.G)
        return out
    }

    ; ------------------------------------------------------------ the tool
    ; One window for all of it: pick one on the left, its name, its group and
    ; its code on the right, and Save it. The code follows the one that is
    ; picked because the field is seeded from it -- so there is no "now press
    ; Load" step, and nothing has to be remembered between two dialogs.
    static Manage(s, pick := "") {
        AxSnips.All()
        r := AxForm.Show(s, {Title: "Your snippets", Icon: "E8A5", Width: 720,
            Intro: "Code of your own, kept in data\snippets.json and offered in Insert a snippet "
                 . "alongside the studio's. A group puts it in a submenu.",
            Fields: [
                {Id: "which", L: "", Kind: "choice", V: pick != "" ? pick : AxSnips.FirstName(),
                 Fill: (V) => AxSnips.PickOpts(),
                 Hint: "Pick one to change it, or (a new one) to write one."},
                {Id: "name", L: "Called", Kind: "text", V: AxSnips.NameOf(pick),
                 Seeded: AxSnips.NameOf(pick), Seed: (V) => AxSnips.NameOf(V["which"]),
                 Hint: "What it is called in the menu."},
                {Id: "group", L: "Under", Kind: "text", V: AxSnips.GroupOf(pick),
                 Seeded: AxSnips.GroupOf(pick), Seed: (V) => AxSnips.GroupOf(V["which"]),
                 Hint: "A submenu to keep it in. Leave it empty for the top."},
                {Id: "body", L: "", Kind: "code", Rows: 14, V: AxSnips.CodeOf(pick),
                 Seeded: AxSnips.CodeOf(pick), Seed: (V) => AxSnips.CodeOf(V["which"]),
                 Ph: "The lines to drop in where the caret is."},
                {Id: "acts", Kind: "acts", Do: (V, which) => AxSnips.Act(s, V, which), Items: [
                    {V: "save", L: "Save it", Icon: "E74E", Go: true},
                    {V: "insert", L: "Put it in the code", Icon: "E710"},
                    {V: "grab", L: "Take what is in the editor", Icon: "E8C8",
                     Tip: "Fill the code below from whatever is being edited"},
                    {V: "del", L: "Remove it", Icon: "E711"}]},
                {Id: "said", Kind: "panel", V: ""}],
            Buttons: ["Close"], CancelIndex: 1})
        return r
    }
    static FirstName() {
        list := AxSnips.All()
        return list.Length ? list[1].N : "-new-"
    }
    static PickOpts() {
        o := ""
        for sn in AxSnips.All()
            o .= (o = "" ? "" : "|") AxSnips.Esc(sn.N) ":" AxSnips.Esc((sn.G != "" ? sn.G " -- " : "") sn.N)
        return (o = "" ? "" : o "|") "-new-:(a new one)"
    }
    ; A name with a | or a : in it would split the options list in two.
    static Esc(x) => StrReplace(StrReplace(String(x), "|", "/"), ":", " -")
    static NameOf(which) {
        sn := (which = "" || which = "-new-") ? "" : AxSnips.Get(which)
        return IsObject(sn) ? sn.N : ""
    }
    static GroupOf(which) {
        sn := (which = "" || which = "-new-") ? "" : AxSnips.Get(which)
        return IsObject(sn) ? sn.G : ""
    }
    static CodeOf(which) {
        sn := (which = "" || which = "-new-") ? "" : AxSnips.Get(which)
        return IsObject(sn) ? sn.C : ""
    }
    static Act(s, V, which) {
        cur := V.Has("which") ? V["which"] : ""
        name := Trim(V.Has("name") ? V["name"] : "")
        body := V.Has("body") ? V["body"] : ""
        switch which {
        case "save":
            if (name = "")
                return AxForm.Panel(s, "said", '<span class="axd-fpbad">Give it a name first.</span>')
            if (Trim(body) = "")
                return AxForm.Panel(s, "said", '<span class="axd-fpbad">There is nothing in it yet.</span>')
            was := (cur = "-new-") ? "" : cur
            AxSnips.Put(name, body, V.Has("group") ? V["group"] : "", was)
            AxForm.Put(s, "which", name)
            AxForm.Panel(s, "said", '<span class="axd-fpok">Saved.</span> It is in Insert a snippet now'
                . (Trim(V["group"]) != "" ? ", under " AxTags.E(Trim(V["group"])) : "") ".")
            return
        case "del":
            if (cur = "" || cur = "-new-")
                return AxForm.Panel(s, "said", "Pick one to remove.")
            AxSnips.Remove(cur)
            AxForm.Put(s, "which", AxSnips.FirstName())
            return AxForm.Panel(s, "said", "Removed.")
        case "insert":
            if (Trim(body) = "")
                return AxForm.Panel(s, "said", '<span class="axd-fpbad">There is nothing in it yet.</span>')
            s.InsertHere(body, name != "" ? name : "your snippet")
            return AxForm.Panel(s, "said", "Put in where the caret was.")
        case "grab":
            txt := ""
            try txt := s.EditorText()
            if (Trim(txt) = "")
                return AxForm.Panel(s, "said", '<span class="axd-fpbad">Nothing is being edited.</span>')
            AxForm.Put(s, "body", txt)
            return AxForm.Panel(s, "said", "Taken from the editor. Give it a name and press Save it.")
        }
    }
    ; "Keep this as a snippet" from the code editor's own menu.
    static FromEditor(s) {
        txt := ""
        try txt := s.EditorText()
        if (Trim(txt) = "")
            return s.Status("msg", "Nothing is being edited, so there is nothing to keep.")
        r := AxForm.Show(s, {Title: "Keep this as a snippet", Icon: "E8A5", Width: 560,
            Intro: "It goes in Insert a snippet, in every project.",
            Fields: [
                {Id: "name", L: "Called", Kind: "text", V: "", Hint: "What it is called in the menu."},
                {Id: "group", L: "Under", Kind: "text", V: "", Fill: (V) => "",
                 Hint: "A submenu to keep it in. Leave it empty for the top."},
                {Id: "body", L: "", Kind: "code", Rows: 12, V: txt}],
            Buttons: ["Keep it", "Cancel"],
            Check: (V) => Trim(V["name"]) = "" ? "Enter a name." : "",
            Preview: (V) => AxSnips.Find(Trim(V["name"]))
                ? "There is one called that already -- keeping this replaces it." : ""})
        if !r.Ok
            return
        AxSnips.Put(r.V["name"], r.V["body"], r.V["group"])
        s.Status("msg", Trim(r.V["name"]) " is one of your snippets now (Insert a snippet).")
    }
}
