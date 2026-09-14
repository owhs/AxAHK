#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\AxStudio.Model.ahk

; Part of AxStudio, not a program on its own. Running this file directly would
; only load a class and stop, so it hands over to the entry point instead.
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
;  AxStudio.Templates.ahk -- the starting points, which are files rather than
;  code.
;
;  studio\templates\*.axs.json are ordinary project files: exactly what Save
;  writes. So a template is something you can open, change and save back, and
;  adding one of your own is dropping a file in the folder. Two keys the studio
;  reads and a project ignores carry the name and the one-line description; the
;  numeric prefix on the filename is only the order they appear in.
;
;  Each one is a finished little application rather than a sketch: the controls
;  are named and the events carry code that runs, because a blank page teaches
;  nothing about how the library is meant to be used.
; =============================================================================
class AxTpl {
    static All := []
    static Dir := ""

    static __New() {
        SplitPath(A_LineFile, , &d)
        AxTpl.Dir := d "\templates"
        AxTpl.Load()
    }

    static Load() {
        AxTpl.All := []
        names := ""
        if DirExist(AxTpl.Dir) {
            loop files AxTpl.Dir "\*.json"
                names .= A_LoopFileName "`n"
        }
        for file in StrSplit(Sort(RTrim(names, "`n"), "C"), "`n") {
            if (Trim(file) = "")
                continue
            m := ""
            try m := AxJson.Parse(FileRead(AxTpl.Dir "\" file, "UTF-8"))
            if !(m is Map)
                continue
            id := RegExReplace(file, "^\d+[-_]?|\.axs\.json$|\.json$")
            ; a picture of it running, beside it with the same name, is what
            ; the start screen shows; without one it draws the layout instead
            pic := AxTpl.Dir "\" RegExReplace(file, "i)\.axs\.json$|\.json$") ".png"
            AxTpl.All.Push({Id: id, Path: AxTpl.Dir "\" file, Map: m,
                            Name: AxJson.Get(m, "name", id),
                            Desc: AxJson.Get(m, "desc", ""),
                            Pic: FileExist(pic) ? pic : ""})
        }
        if !AxTpl.All.Length
            AxTpl.All.Push({Id: "blank", Path: "", Map: "", Name: "Blank",
                            Desc: "One page, nothing on it.", Pic: ""})
    }

    static Get(id) {
        for t in AxTpl.All
            if (t.Id = id)
                return t
        return AxTpl.All[1]
    }
    ; A template is only a project file, so building one is reading it. The
    ; fallback is for the case where the folder has gone missing entirely: the
    ; studio should still open on something.
    static Build(id) {
        t := AxTpl.Get(id)
        p := ""
        if (t.Map is Map)
            try p := AxProject.FromMap(t.Map)
        if !IsObject(p)
            p := AxTpl.Blank()
        p.Path := ""
        p.Dirty := false
        return p
    }
    static Blank() {
        p := AxProject()
        p.Title := "My app"
        p.Width := 760, p.Height := 520
        pg := p.NewPage("Home")
        pg.P["icon"] := "E80F"
        p.Insert(p.Root, pg)
        return p
    }
}
