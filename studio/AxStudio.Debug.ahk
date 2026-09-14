#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\AxStudio.Lit.ahk
; Region() writes numbers with the generator's own formatter. Gen includes
; this file in turn; #Include loads a file once, so the pair resolves.
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
;  AxStudio.Debug.ahk -- Run as a debugger rather than a launcher.
;
;  F5 starts a separate AutoHotkey process, which is the right way to see the
;  real thing: a real window, its own thread, full fidelity. The cost used to
;  be that it was a one-way trip. Nothing came back.
;
;  So a debug build carries a small agent, in a region of its own that Export
;  never writes. The agent appends lines to a log file the studio named when it
;  generated the script, and the studio tails that file:
;
;      up    <window>          it is running
;      pick  <control>         you clicked that control -- the studio selects it
;      log   <text>            your own AxLog() calls
;      error <message>         an unhandled error, with file and line
;      pos   <x y w h page>    where it was when it closed
;      closed <window>
;
;  A file rather than OutputDebug on purpose: only one process on a machine can
;  be the debug monitor, and taking that from the user's own DebugView would be
;  rude. A file has no such rule, survives the process dying, and can be opened
;  afterwards.
;
;  `pos` is what stops Live feeling like a restart -- the next run comes back
;  the same size, in the same place, on the same page.
; =============================================================================

class AxDbg {
    ; --- what goes into the script ------------------------------------
    ; `d` is {Log, X, Y, W, H, Page}: where to write, and where the last run
    ; left the window. Only Run passes one, so an exported script has none of
    ; this in it.
    static Region(project, d) {
        nl := "`n"
        q := (v) => AxLit.S(String(v))
        s := "; AxStudio wrote this block for Run (F5). Export never does." nl
        s .= "; Delete it and the script is exactly what Export would have written." nl
        s .= "AxDbgFile := " q(d.Log) nl
        s .= nl
        s .= "AxDbgSay(kind, text := " q("") ") {" nl
        s .= "    global AxDbgFile" nl
        s .= "    try FileAppend(kind " q("`t") " text " q("`n") ", AxDbgFile, " q("UTF-8") ")" nl
        s .= "}" nl
        s .= "; AxLog(anything, ...) turns up in the studio's Output tab." nl
        s .= "AxLog(parts*) {" nl
        s .= "    line := " q("") nl
        s .= "    for v in parts" nl
        s .= "        line .= (line = " q("") " ? " q("") " : " q(" ") ") String(v)" nl
        s .= "    AxDbgSay(" q("log") ", line)" nl
        s .= "}" nl
        s .= nl
        ; A mousedown wildcard rather than a click one: a control with its own
        ; Click handler owns "click", and those are exactly the controls you
        ; most want to be able to point at.
        s .= "AxDbgWire(w, name) {" nl
        s .= "    w.On(" q("mousedown") ", " q("*") ", (el, ev) => AxDbgPick(el))" nl
        s .= "    w.OnClose((*) => AxDbgBye(w, name))" nl
        s .= "    AxDbgSay(" q("up") ", name)" nl
        s .= "}" nl
        s .= "AxDbgPick(el) {" nl
        s .= "    n := el" nl
        s .= "    loop 10 {" nl
        s .= "        if !IsObject(n)" nl
        s .= "            return" nl
        s .= "        id := " q("") nl
        s .= "        try id := n.id" nl
        s .= "        if (id != " q("") " && SubStr(id, 1, 2) != " q("ax") ") {" nl
        s .= "            AxDbgSay(" q("pick") ", id)" nl
        s .= "            return" nl
        s .= "        }" nl
        s .= "        try n := n.parentNode" nl
        s .= "        catch" nl
        s .= "            return" nl
        s .= "    }" nl
        s .= "}" nl
        ; Read on the way out, while the window is still standing.
        s .= "AxDbgBye(w, name) {" nl
        s .= "    page := " q("") nl
        s .= "    try page := w.Doc.querySelector(" q(".page.visible") ").id" nl
        s .= "    try {" nl
        s .= "        if WinGetMinMax(" q("ahk_id ") " w.Hwnd)" nl
        s .= "            throw Error()" nl
        s .= "        WinGetPos(&x, &y, &cw, &ch, " q("ahk_id ") " w.Hwnd)" nl
        s .= "        AxDbgSay(" q("pos") ", x " q(" ") " y " q(" ") " cw " q(" ") " ch " q(" ") " page)" nl
        s .= "    }" nl
        s .= "    AxDbgSay(" q("closed") ", name)" nl
        s .= "}" nl
        s .= "AxDbgErr(e, mode) {" nl
        s .= "    AxDbgSay(" q("error") ", e.Message " q(" (") " e.File " q(":") " e.Line " q(")") ")" nl
        s .= "    return 0" nl
        s .= "}" nl
        s .= "OnError(AxDbgErr)" nl
        s .= nl
        s .= "AxDbgWire(g, " q(project.Main().Name) ")" nl
        ; back where you left it, which is what stops Live feeling like a restart
        if (d.W > 0 && d.H > 0)
            s .= "try WinMove(" AxGen.N(d.X) ", " AxGen.N(d.Y) ", " AxGen.N(d.W) ", "
               . AxGen.N(d.H) ", " q("ahk_id ") " g.Hwnd)" nl
        else if (d.HasOwnProp("At") && d.At)
            s .= "try WinMove(" AxGen.N(d.X) ", " AxGen.N(d.Y) ", , , " q("ahk_id ") " g.Hwnd)" nl
        if (Trim(d.Page) != "")
            s .= "try g.ShowPage(" q(d.Page) ")" nl
        return s
    }
    ; The names the debug block puts in the script, so AxLint can say when a
    ; control has taken one of them.
    static Names := ["AxDbgFile", "AxDbgSay", "AxLog", "AxDbgWire", "AxDbgPick",
                     "AxDbgBye", "AxDbgErr"]

    ; --- putting an error back where it came from ---------------------
    ; An unhandled error comes back as "message (file:line)", and the line is
    ; a line of the GENERATED script -- a file the person never wrote and
    ; cannot usefully be shown. But the generator puts every handler in a
    ; function of its own at the top level, so the line is enough to say which
    ; one, and the studio can open the handler they DID write.
    static Locate(code, line) {
        n := 0, cur := ""
        for raw in StrSplit(StrReplace(String(code), "`r", ""), "`n") {
            n++
            ; a top-level definition: no indent, a name, brackets, and a brace
            if RegExMatch(raw, "^([A-Za-z_]\w*)\s*\([^)]*\)\s*\{\s*$", &m)
                cur := m[1]
            else if (raw = "}")
                cur := (n >= line) ? cur : ""
            if (n >= line)
                return cur
        }
        return ""
    }
    ; "... (C:\path\preview.ahk:412)" -> 412, or 0.
    static LineOf(text) {
        if RegExMatch(String(text), ":(\d+)\)\s*$", &m)
            return Integer(m[1])
        return 0
    }

    ; --- reading the log back -----------------------------------------
    ; Returns the lines written since `at`, and how far it has read now.
    static Read(path, at) {
        text := ""
        try text := FileRead(path, "UTF-8")
        catch
            return {Lines: [], At: at}
        if (StrLen(text) <= at)
            return {Lines: [], At: StrLen(text)}
        fresh := SubStr(text, at + 1)
        out := []
        for line in StrSplit(StrReplace(fresh, "`r", ""), "`n") {
            if (Trim(line) = "")
                continue
            i := InStr(line, "`t")
            out.Push({Kind: i ? SubStr(line, 1, i - 1) : line,
                      Text: i ? SubStr(line, i + 1) : ""})
        }
        return {Lines: out, At: StrLen(text)}
    }
}
