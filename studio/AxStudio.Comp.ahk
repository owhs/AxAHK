#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\AxJson.ahk
#Include %A_LineFile%\..\AxStudio.Catalog.ahk

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
;  AxStudio.Comp.ahk -- components as packs you drop in a folder.
;
;  A component is a folder with an .ahk that registers itself, its own CSS, and
;  a manifest saying what the studio should do with it:
;
;      <Name>\
;          Ax<Name>.ahk        the code -- registers through AxRich
;          Ax<Name>.css        its own base styles, if it has any
;          <Name>.axc.json     the manifest below
;
;  Two folders are scanned and they hold the same thing in the same shape:
;  lib\components (everything that ships, controls included) and components
;  (yours, and anyone else's). A pack that turns up in either is in the toolbox
;  next time the studio starts.
;
;  ------------------------------------------------------------- the manifest
;      {
;        "name":    "Gauge",
;        "include": "components\\Gauge\\AxGauge.ahk",
;        "requires": ["Splitter"],
;        "controls": [ { ...exactly one catalogue entry... } ]
;      }
;
;  `controls` entries are the same shape as an AxCat.Add call, so a pack adds
;  toolbox items, property sheets and generated code without a line of studio
;  code changing. `requires` names other packs by name.
;
;  ------------------------------------------------------------- tree shaking
;  An export used to include the whole rich layer if one control needed any of
;  it. Now Used(project) walks the design, collects the packs it actually
;  touches, pulls in what those require, and the generated script has one
;  #Include per pack. A window with a splitter in it no longer carries a
;  colour picker and a data grid.
;
;  ------------------------------------------------------------- the built-ins
;  There are none. All forty-three controls ship as packs in lib\components,
;  in the same shape as anything you write. AxGui.ahk includes the generated
;  list at the end of itself, so including it still hands you every control.
; =============================================================================

class AxComp {
    static Packs := Map()               ; name -> {Name, Dir, Include, Requires, Types[]}
    static Roots := []                  ; where they were found
    static Problems := []               ; manifests that would not load

    ; --- finding them --------------------------------------------------
    static Scan(libDir, projDir := "") {
        AxComp.Packs := Map(), AxComp.Roots := [], AxComp.Problems := []
        for root in [libDir "\components",
                     (projDir != "" ? projDir "\components" : "")] {
            if (root = "" || !DirExist(root))
                continue
            AxComp.Roots.Push(root)
            loop files root "\*", "D" {
                loop files A_LoopFileFullPath "\*.axc.json"
                    AxComp._Load(A_LoopFileFullPath, libDir)
            }
        }
        AxComp._Register()
        return AxComp.Packs.Count
    }
    ; The catalogue is filled after every manifest has been read, in the order
    ; the manifests ask for. Folders arrive alphabetically, and alphabetical is
    ; not the order a toolbox wants -- Advanced would come first.
    static _Register() {
        list := []
        for name, p in AxComp.Packs
            list.Push(p)
        loop list.Length - 1 {                    ; small list, plain sort
            i := 1
            while (i < list.Length) {
                if (list[i].Order > list[i + 1].Order) {
                    t := list[i], list[i] := list[i + 1], list[i + 1] := t
                }
                i++
            }
        }
        for p in list {
            for c in p.Controls {
                e := AxComp._Entry(c, p.Name)
                if IsObject(e) {
                    p.Types.Push(e.T)
                    AxCat.Add(e)
                }
            }
        }
        if !AxCat.Has("Code")
            AxCat.Add(AxCat.CodeEntry())
    }
    static _Load(path, libDir) {
        m := ""
        try m := AxJson.Parse(FileRead(path, "UTF-8"))
        catch as e {
            AxComp.Problems.Push({Path: path, Msg: "will not parse: " e.Message})
            return
        }
        if !(m is Map) {
            AxComp.Problems.Push({Path: path, Msg: "is not an object"})
            return
        }
        name := AxJson.Get(m, "name", "")
        if (name = "") {
            AxComp.Problems.Push({Path: path, Msg: "has no name"})
            return
        }
        SplitPath(path, , &dir)
        inc := AxJson.Get(m, "include", "")
        if (inc = "") {
            AxComp.Problems.Push({Path: path, Msg: "has no include"})
            return
        }
        ; the include is written relative to the library, so a pack folder can
        ; be moved without every manifest in it being rewritten
        full := AxComp._Abs(inc, libDir, dir)
        if !FileExist(full) {
            AxComp.Problems.Push({Path: path, Msg: "points at " inc ", which is not there"})
            return
        }
        req := []
        for r in AxComp._Arr(AxJson.Get(m, "requires", ""))
            req.Push(String(r))
        pack := {Name: name, Dir: dir, Include: full, Requires: req, Types: [],
                 Order: Integer(AxJson.Get(m, "order", 500)),
                 Controls: AxComp._Arr(AxJson.Get(m, "controls", ""))}
        AxComp.Packs[name] := pack
    }
    static _Abs(rel, libDir, dir) {
        if RegExMatch(rel, "^[A-Za-z]:[\\/]|^\\\\")
            return rel
        rel := StrReplace(rel, "/", "\")
        ; "lib\components\X\Y.ahk" is relative to the folder lib sits in
        SplitPath(libDir, , &parent)
        for base in [parent, dir] {
            p := base "\" rel
            if FileExist(p)
                return p
        }
        return dir "\" rel
    }
    static _Arr(v) => (v is Array) ? v : []
    static _Map(v) => (v is Map) ? v : Map()

    ; --- one control, from JSON into the catalogue ---------------------
    ; The keys are the ones AxCat.Add already understands, so a manifest is a
    ; catalogue entry written down rather than a new thing to learn.
    static _Entry(c, packName) {
        if !(c is Map)
            return ""
        t := AxJson.Get(c, "type", "")
        if (t = "")
            return ""
        e := {T: t,
              Label: AxJson.Get(c, "label", t),
              Icon: AxJson.Get(c, "icon", "E7C3"),
              Cat: AxJson.Get(c, "category", "Rich"),
              Prefix: AxJson.Get(c, "prefix", "ctl"),
              Box: AxJson.Get(c, "box", false) ? true : false,
              Pack: packName,
              Needs: ""}                 ; the pack is what it needs -- see Used()
        a := AxJson.Get(c, "arg", "")
        if (a is Map) {
            arg := {K: AxJson.Get(a, "key", "text"), L: AxJson.Get(a, "label", "Value"),
                    Kind: AxJson.Get(a, "kind", "text"), Def: AxJson.Get(a, "default", "")}
            if AxJson.Get(a, "raw", false)
                arg.Raw := true
            if AxJson.Get(a, "always", false)
                arg.Always := true
            e.Arg := arg
        }
        props := []
        for p in AxComp._Arr(AxJson.Get(c, "props", "")) {
            if !(p is Map)
                continue
            kind := AxJson.Get(p, "kind", "text")
            emit := AxJson.Get(p, "emit", kind = "flag" ? "flag" : "kv")
            props.Push({K: AxJson.Get(p, "key", ""), L: AxJson.Get(p, "label", ""),
                        Kind: kind, Emit: emit,
                        W: AxJson.Get(p, "word", AxCat._Word(AxJson.Get(p, "key", ""))),
                        Opts: AxJson.Get(p, "options", ""), Def: AxJson.Get(p, "default", "")})
        }
        e.PropList := props
        ev := []
        ; An event is a name the catalogue knows ("Click"), or one the pack
        ; brings: {name, sig, wire, filter, help} -- sig is the handler's
        ; parameters, wire the method that attaches it (OnTick), filter the
        ; parameter a rule can pick on ("world Hit:coin -> ...").
        for x in AxComp._Arr(AxJson.Get(c, "events", "")) {
            if (x is Map) {
                name := AxJson.Get(x, "name", "")
                if !RegExMatch(name, "^[A-Za-z]\w*$")
                    continue
                if !AxCat.Events.Has(name)
                    AxCat.Events[name] := {Sig: AxJson.Get(x, "sig", "ctl, ev, el"), Wire: AxJson.Get(x, "wire", ""),
                                           Filter: AxJson.Get(x, "filter", ""), Help: AxJson.Get(x, "help", ""),
                                           Word: AxJson.Get(x, "word", "")}
                ev.Push(name)
            } else
                ev.Push(String(x))
        }
        if ev.Length
            e.Events := ev
        return e
    }

    ; --- what an export has to carry -----------------------------------
    ; The packs this project touches, plus everything they require, in an
    ; order where a pack comes after the ones it depends on.
    static Used(project) {
        want := Map()
        for w in project.Wins {
            project.Walk(w.Root, AxComp._SeenFn(want))
            AxComp._SeenText(w.Script, want)
        }
        out := [], done := Map()
        for name in want
            AxComp._Order(name, out, done, Map())
        return out
    }
    static _SeenFn(want) => (n) => (AxComp._Seen(n, want), false)
    static _Seen(n, want) {
        if (n.Type = "Code")
            return AxComp._SeenText(n.Arg, want)
        if !AxCat.Has(n.Type)
            return
        e := AxCat.Get(n.Type)
        if (e.HasOwnProp("Pack") && e.Pack != "")
            want[e.Pack] := true
    }
    ; Code the studio only carries -- a Code block, the window's script --
    ; can make controls too, and the export has to include what they need.
    static _SeenText(text, want) {
        pos := 1
        while (pos := RegExMatch(String(text), "\.Add(\w+)\(", &m, pos)) {
            pos += m.Len
            if AxCat.Has(m[1]) {
                e := AxCat.Get(m[1])
                if (e.HasOwnProp("Pack") && e.Pack != "")
                    want[e.Pack] := true
            }
        }
    }
    ; Depth first, with a guard: a manifest can name a pack that names it back,
    ; and that must be a report rather than a hang.
    static _Order(name, out, done, onStack) {
        if done.Has(name) || onStack.Has(name)
            return
        onStack[name] := true
        if AxComp.Packs.Has(name)
            for r in AxComp.Packs[name].Requires
                AxComp._Order(r, out, done, onStack)
        onStack.Delete(name)
        done[name] := true
        if AxComp.Packs.Has(name)
            out.Push(AxComp.Packs[name])
    }
    static Get(name) => AxComp.Packs.Has(name) ? AxComp.Packs[name] : ""

    ; --- the manifest file --------------------------------------------
    ; #Include takes a path, not a glob, so "drop a folder in and it works"
    ; needs a real file listing them. This writes it, in dependency order, so
    ; a project that wants everything can include one line.
    ; `under` limits it to the packs found beneath one root, because the
    ; library already has lib\AxRichAll.ahk and does not want a second list
    ; of itself.
    static WriteAll(path, under := "") {
        order := [], done := Map()
        for name in AxComp.Packs
            AxComp._Order(name, order, done, Map())
        s := "#Requires AutoHotkey v2.0`n"
        s .= "; Written by AxStudio from the .axc.json manifests it found.`n"
        s .= "; Edited by hand, it will be overwritten -- add a folder instead.`n"
        s .= "; #Include takes a path and not a glob, which is why this file exists.`n`n"
        ; the layer every component registers with. Worked out rather than
        ; hardcoded: this file used to live in <root>\components and now lives
        ; in <root>\lib\components, and the hardcoded form silently pointed at
        ; <root>\lib\lib\rich.
        SplitPath(path, , &axDir)
        SplitPath(axDir, , &axLib)
        s .= "#Include " AxComp._Q(AxComp._Rel(path, axLib "\AxRich.ahk")) "`n"
        for p in order {
            if (under != "" && SubStr(p.Dir, 1, StrLen(under)) != under)
                continue
            for r in p.Requires
                if !AxComp.Packs.Has(r)
                    s .= "; " p.Name " wants " r ", which is not installed`n"
            s .= "#Include " AxComp._Q(AxComp._Rel(path, p.Include)) "`n"
        }
        try {
            if FileExist(path)
                FileDelete(path)
            FileAppend(s, path, "UTF-8-RAW")
        } catch
            return false
        return true
    }
    static _Q(p) => InStr(p, " ") ? '"' p '"' : p
    ; Written relative to the manifest itself, through %A_LineFile%, because an
    ; absolute path in a generated file is a file that only works on the
    ; machine it was generated on.
    static _Rel(manifest, target) {
        ; Backslash is NOT an escape character in AutoHotkey v2 -- the backtick
        ; is -- so "\\" here would be a string of two backslashes, and
        ; splitting a path on it matches nothing.
        SplitPath(manifest, , &dir)
        a := StrSplit(RTrim(StrReplace(dir, "/", "\"), "\"), "\")
        b := StrSplit(StrReplace(target, "/", "\"), "\")
        if (!a.Length || !b.Length || StrLower(a[1]) != StrLower(b[1]))
            return target                     ; different drives: no relative form
        i := 1
        while (i <= a.Length && i < b.Length && StrLower(a[i]) = StrLower(b[i]))
            i++
        rel := "%A_LineFile%\.."
        loop (a.Length - i + 1)
            rel .= "\.."
        loop (b.Length - i + 1)
            rel .= "\" b[i + A_Index - 1]
        return rel
    }
}
