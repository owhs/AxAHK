#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\AxStudio.Comp.ahk
#Include %A_LineFile%\..\AxStudio.Gen.ahk

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
;  AxStudio.Store.ahk -- the component viewer, and installing one.
;
;  THE VIEWER answers "what is in this thing, and how do I use it". Every pack,
;  every control in it, rendered by the library itself -- the same AxDesignGui
;  the canvas uses, so what you see is the control and not a picture of one --
;  and beside it every form that control is available in:
;
;      the builder call   g.AddSplitter("vsp1 Target=side Min=140")
;      the properties     Resizes, Drag vertically, Smallest, Largest
;      the events         Change, Click, ContextMenu
;      window methods     g.SplitterSize(id)
;      what it needs      ScreenPick
;
;  The forms are not written down twice. The builder call is generated from the
;  manifest exactly as the exporter would generate it, so a viewer entry that
;  is wrong means an export that is wrong.
;
;  INSTALLING is a folder copy. A pack is a folder with a manifest in it, so a
;  .zip of one, or the folder itself, is the whole distribution format. It is
;  unpacked with tar (present since Windows 10 1803), checked for a manifest,
;  copied into components\ and the studio rescans. Nothing is executed, and the
;  files are read only after they are in place.
; =============================================================================

class AxStore {
    ; --- what a control looks like -------------------------------------
    ; Built through the same design-time AxGui the canvas uses, so the preview
    ; is the real markup with the real stylesheet on it.
    static Preview(project, type) {
        if !AxCat.Has(type)
            return ""
        n := AxNode(type, "prev")
        e := AxCat.Get(type)
        if (IsObject(e.Arg) && e.Arg.HasOwnProp("Def"))
            n.Arg := e.Arg.Def
        for p in e.Props
            if (p.Def != "")
                n.P[p.K] := p.Def
        n.Name := ""
        html := ""
        try {
            g := AxDesignGui({Nav: false})
            AxGen.Emit(g, [n], (*) => g.Use(g._root), true)
            html := g._root.InnerHtml()
        }
        return html
    }

    ; --- how you use it ------------------------------------------------
    ; The same option string the exporter would write, so this cannot drift.
    static Call(type) {
        if !AxCat.Has(type)
            return ""
        e := AxCat.Get(type)
        n := AxNode(type, "x")
        n.Name := e.Prefix "1"
        for p in e.Props
            if (p.Def != "")
                n.P[p.K] := p.Def
        opts := AxGen.OptString(n, false)
        arg := ""
        if IsObject(e.Arg) {
            v := e.Arg.HasOwnProp("Def") ? e.Arg.Def : ""
            arg := ", " (AxGen.ArgIsRaw(n) ? (v != "" ? v : '""') : AxGen.S(v))
        }
        return "g.Add" type "(" AxGen.S(opts) arg ")"
    }
    ; Everything a pack adds beyond its controls, read out of its own source:
    ; the window methods it installs, and any dialog it offers.
    static Extras(pack) {
        out := []
        if !IsObject(pack)
            return out
        text := ""
        try text := FileRead(pack.Include, "UTF-8")
        pos := 1
        while (pos := RegExMatch(text, 'AxRich\.WindowMethod\(\s*"(\w+)"', &m, pos)) {
            pos += StrLen(m[0])
            out.Push({Kind: "window method", Sig: "g." m[1] "(...)"})
        }
        pos := 1
        while (pos := RegExMatch(text, 'm)^\s*static (Show|Pick|Choose)\w*\(', &m, pos)) {
            pos += StrLen(m[0])
            cls := RegExMatch(text, "m)^class (\w+)", &c) ? c[1] : pack.Name
            out.Push({Kind: "dialog", Sig: cls "." Trim(m[0], " `t") ")"})
        }
        return out
    }

    ; --- installing one ------------------------------------------------
    ; Returns {Ok, Msg, Name}. Nothing here runs anything from the pack.
    static Install(source, into) {
        SplitPath(source, , , &ext, &base)
        tmp := ""
        try {
            if (ext = "zip") {
                tmp := A_Temp "\axpack_" A_TickCount
                DirCreate(tmp)
                RunWait('tar.exe -xf "' source '" -C "' tmp '"', , "Hide")
                root := AxStore._FindManifest(tmp)
            } else if DirExist(source)
                root := AxStore._FindManifest(source)
            else
                return {Ok: false, Msg: "That is neither a folder nor a .zip.", Name: ""}
        } catch as e
            return {Ok: false, Msg: "Could not unpack it: " e.Message, Name: ""}

        if (root = "") {
            AxStore._Clean(tmp)
            return {Ok: false, Msg: "There is no .axc.json in there, so it is not a"
                                  . " component pack.", Name: ""}
        }
        name := "", inc := ""
        for f in AxStore._Manifests(root) {
            m := ""
            try m := AxJson.Parse(FileRead(f, "UTF-8"))
            if (m is Map) {
                name := AxJson.Get(m, "name", "")
                inc := AxJson.Get(m, "include", "")
            }
            break
        }
        if (name = "") {
            AxStore._Clean(tmp)
            return {Ok: false, Msg: "Its manifest has no name.", Name: ""}
        }
        dest := into "\" name
        if DirExist(dest) {
            AxStore._Clean(tmp)
            return {Ok: false, Msg: name " is already installed. Delete"
                                  . "`n`n    " dest "`n`nfirst if you mean to replace it.",
                    Name: name}
        }
        try {
            DirCreate(into)
            DirCopy(root, dest, false)
        } catch as e {
            AxStore._Clean(tmp)
            return {Ok: false, Msg: "Could not copy it in: " e.Message, Name: name}
        }
        AxStore._Clean(tmp)
        return {Ok: true, Name: name,
                Msg: name " is installed. It is in the toolbox now."
                   . (inc != "" ? "`n`nIts code: " inc : "")}
    }
    ; A pack may be zipped with its folder inside, or from inside its folder.
    static _FindManifest(dir) {
        if AxStore._Manifests(dir).Length
            return dir
        loop files dir "\*", "D"
            if AxStore._Manifests(A_LoopFileFullPath).Length
                return A_LoopFileFullPath
        return ""
    }
    static _Manifests(dir) {
        out := []
        loop files dir "\*.axc.json"
            out.Push(A_LoopFileFullPath)
        return out
    }
    static _Clean(tmp) {
        if (tmp != "" && DirExist(tmp))
            try DirDelete(tmp, true)
    }
}
