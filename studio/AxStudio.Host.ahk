#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\AxJson.ahk
#Include %A_LineFile%\..\bin\AxtReader.ahk

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
;  AxStudio.Host.ahk -- the AutoHotkey parser, as a program beside the studio.
;
;  bin\AstHost.exe is the AHK2 AST engine: it reads a script the way
;  AutoHotkey does and says what is in it. It runs as its own process, so a
;  script that sends the parser round in circles costs a timeout rather than
;  the studio and whatever was not saved. It has no window, and it goes when
;  the studio does: it exits as soon as its input closes.
;
;  One JSON object per line in, one per line back, in order. A whole syntax
;  tree does not come back as JSON -- that would be megabytes to pick apart a
;  character at a time -- but as a block of shared memory AxtTree reads
;  where it lies (see bin\AxtReader.ahk):
;
;      r := AxHost.Ask(Map("cmd", "outline", "path", file))
;      t := AxHost.Tree(file)          ; AxtTree, or throws with the reason
; =============================================================================
class AxHost {
    static Exec := ""
    static Seq := 0

    static Exe => RegExReplace(A_LineFile, "\\[^\\]+$") "\bin\AstHost.exe"
    static Ready => FileExist(AxHost.Exe) != ""

    ; Started on the first question, and kept: a warm parser answers in
    ; milliseconds where a cold one takes a quarter of a second.
    static Start() {
        if (IsObject(AxHost.Exec) && AxHost.Exec.Status = 0)
            return
        if !AxHost.Ready
            throw Error("The parser is missing: " AxHost.Exe " is not there.")
        AxHost.Exec := ComObject("WScript.Shell").Exec('"' AxHost.Exe '"')
    }

    ; A request (a Map) and its reply (a Map). Throws with the parser's own
    ; words when it says no.
    static Ask(req, timeoutMs := 30000) {
        AxHost.Start()
        req["id"] := ++AxHost.Seq
        req["timeoutMs"] := timeoutMs
        AxHost.Exec.StdIn.WriteLine(AxHost.Ascii(AxJson.Stringify(req, "")))
        loop {
            if AxHost.Exec.StdOut.AtEndOfStream {
                AxHost.Exec := ""
                throw Error("The parser stopped before it answered.")
            }
            r := AxJson.Parse(AxHost.Exec.StdOut.ReadLine())
            if (AxJson.Get(r, "id", "") != req["id"])
                continue                    ; the answer to an earlier question nobody waited for
            if !AxJson.Get(r, "ok", 0) {
                e := AxJson.Get(r, "error", Map())
                throw Error("The parser said: " AxJson.Get(e, "message", "no") , -1, AxJson.Get(e, "code", ""))
            }
            return r
        }
    }

    ; The whole syntax tree of a file, read in place. Problems the parser met
    ; are on the tree as .Problems (the same shape as the `errors` reply).
    static Tree(path) {
        r := AxHost.Ask(Map("cmd", "parse", "path", path, "format", "bin", "to", "shm"))
        name := r["shm"]
        t := AxtTree.FromShm(name, r["bytes"])
        ; mapped: the section can go now, and the tree stays readable
        try AxHost.Ask(Map("cmd", "release", "shm", name))
        t.Problems := AxJson.Get(r, "problems", [])
        return t
    }

    ; The same, for text that is not in a file (the export, unwritten).
    static TreeText(text) {
        r := AxHost.Ask(Map("cmd", "parse", "text", text, "format", "bin", "to", "shm"))
        name := r["shm"]
        t := AxtTree.FromShm(name, r["bytes"])
        try AxHost.Ask(Map("cmd", "release", "shm", name))
        t.Problems := AxJson.Get(r, "problems", [])
        return t
    }

    ; Closed by closing its input, which it takes as the end. Only this one
    ; process, the one the studio started, is ever stopped.
    static Stop() {
        if !IsObject(AxHost.Exec)
            return
        try AxHost.Exec.StdIn.Close()
        loop 20 {
            if (AxHost.Exec.Status != 0)
                break
            Sleep(25)
        }
        if (AxHost.Exec.Status = 0)
            try AxHost.Exec.Terminate()
        AxHost.Exec := ""
    }

    ; The pipe carries ASCII: anything past it goes as a \u escape, which
    ; every JSON reader takes back as the same character.
    static Ascii(s) {
        if !RegExMatch(s, "[^\x{00}-\x{7F}]")
            return s
        out := "", i := 1, n := StrLen(s)
        while (i <= n) {
            p := RegExMatch(s, "[^\x{00}-\x{7F}]", &m, i)
            if !p {
                out .= SubStr(s, i)
                break
            }
            out .= SubStr(s, i, p - i)
            c := Ord(m[0])
            if (c > 0xFFFF) {
                c -= 0x10000
                out .= Format("\u{:04x}\u{:04x}", 0xD800 + (c >> 10), 0xDC00 + (c & 0x3FF))
            } else
                out .= Format("\u{:04x}", c)
            i := p + StrLen(m[0])
        }
        return out
    }
}
