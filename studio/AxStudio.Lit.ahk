#Requires AutoHotkey v2.0

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
;  AxStudio.Lit.ahk -- writing AutoHotkey out as text.
;
;  Small enough to sit on its own, and it has to: both the control generator
;  and the chrome generator need it, and each of those needs the other's
;  output, so the shared piece cannot live in either.
; =============================================================================
class AxLit {
    ; An AHK double-quoted literal.
    static S(v) {
        s := String(v)
        s := StrReplace(s, "``", "````")
        s := StrReplace(s, '"', '``"')
        s := StrReplace(s, "`r", "``r")
        s := StrReplace(s, "`n", "``n")
        s := StrReplace(s, "`t", "``t")
        ; A semicolon that follows a space starts a comment even inside a
        ; quoted string, so every one of them is escaped rather than counted on.
        s := StrReplace(s, ";", "``;")
        return '"' s '"'
    }
    ; Text of several lines -- a stylesheet, a block of markup -- as a quoted
    ; continuation section, so the script shows it as the lines it is. What
    ; AutoHotkey 2.0 does with one: the lines join with a line feed, the first
    ; line's indentation comes off every line (so every line gets `pad`),
    ; trailing blanks come off unless RTrim0, backticks escape, and a line
    ; starting with ) would end it -- that one case stays a one-line literal.
    static Section(v, pad := "") {
        s := StrReplace(String(v), "`r", "")
        if (!InStr(s, "`n") || RegExMatch(s, "m)^[ \t]*\)"))
            return AxLit.S(v)
        s := StrReplace(s, "``", "````")
        s := StrReplace(s, '"', '``"')
        opts := RegExMatch(s, "m)[ \t]$") ? " RTrim0" : ""
        ; an indented first line would lose its indentation, and every other
        ; line that much: LTrim0 keeps each line exactly, with none added
        if RegExMatch(s, "^[ \t]")
            opts .= " LTrim0", pad := ""
        body := ""
        for line in StrSplit(s, "`n")
            body .= "`n" (line = "" ? "" : pad line)
        return '"`n' pad '(' opts body "`n" pad ')"'
    }
    ; A number as written, not as AHK would print it after a round trip.
    static N(v) {
        if (v = "")
            return ""
        if IsNumber(v)
            return (v = Round(v)) ? String(Integer(v)) : String(v)
        return String(v)
    }
    ; Option values live inside a space separated string, so anything with a
    ; space is quoted. A literal double quote has no spelling there at all, so
    ; it becomes a single one rather than breaking the parse silently.
    static Q(v) {
        v := StrReplace(StrReplace(String(v), '"', "'"), "`n", " ")
        return (v = "" || InStr(v, " ") || InStr(v, "=")) ? '"' v '"' : v
    }
    ; A user-supplied expression squeezed onto one line, where it has to be an
    ; argument rather than a statement.
    static Inline(v) => Trim(StrReplace(StrReplace(String(v), "`r", ""), "`n", " "), " `t")
    ; A block of the user's own code, re-indented under `pad`.
    static Block(code, pad) {
        out := ""
        for line in StrSplit(StrReplace(String(code), "`r", ""), "`n")
            out .= (out = "" ? "" : "`n") (Trim(line) = "" ? "" : pad line)
        return out
    }
    static Pad(depth) {
        s := ""
        loop depth
            s .= "    "
        return s
    }
}
