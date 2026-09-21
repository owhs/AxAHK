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
    ; =====================================================================
    ;  Reading one back
    ; =====================================================================
    ;  A property written as a literal -- a ribbon's tabs, a grid's columns --
    ;  is AutoHotkey source, and that is the right call: anything else would be
    ;  a second, worse language, and it would stop you naming one of your own
    ;  functions in it.
    ;
    ;  But source is only half of it. A designer has to SHOW the thing, and an
    ;  editor has to take it apart and put it back, and neither can run the
    ;  script to find out what it says. So the literal part is read here
    ;  without evaluating anything: objects become Maps, arrays become Arrays,
    ;  strings and numbers become themselves.
    ;
    ;  Anything that is not a literal -- a variable, a call, a fat arrow -- is
    ;  kept exactly as written, wrapped so it can be told apart:
    ;
    ;      {Raw: "(*) => Save()"}
    ;
    ;  so a caller can write it straight back out, and an editor can say "this
    ;  one is code" instead of quietly turning it into the STRING "(*) =>
    ;  Save()" and breaking the script on the way past.
    ;
    ;  Read returns "" when the text is not a literal at all, which is also the
    ;  answer to "can this be edited as a form?".
    static Read(text) {
        s := Trim(StrReplace(String(text), "`r", ""), " `t`n")
        if (s = "")
            return ""
        pos := 1
        v := AxLit._Val(s, &pos)
        if (v == AxLit.FAIL)
            return ""
        AxLit._Skip(s, &pos)
        return (pos > StrLen(s)) ? v : ""      ; anything trailing means we misread it
    }
    static _fail := {Fail: 1}
    static FAIL => AxLit._fail
    static IsRaw(v) => IsObject(v) && !(v is Map) && !(v is Array) && v.HasOwnProp("Raw")

    ; whitespace, and the comments that can sit inside a multi-line literal
    static _Skip(s, &pos) {
        n := StrLen(s)
        while (pos <= n) {
            c := SubStr(s, pos, 1)
            if (c = " " || c = "`t" || c = "`n") {
                pos++
                continue
            }
            if (c = ";" && (pos = 1 || InStr(" `t`n", SubStr(s, pos - 1, 1)))) {
                e := InStr(s, "`n", , pos)
                pos := e ? e + 1 : n + 1
                continue
            }
            if (SubStr(s, pos, 2) = "/*") {
                e := InStr(s, "*/", , pos + 2)
                pos := e ? e + 2 : n + 1
                continue
            }
            break
        }
    }
    static _Val(s, &pos) {
        AxLit._Skip(s, &pos)
        c := SubStr(s, pos, 1)
        if (c = "{")
            return AxLit._Obj(s, &pos)
        if (c = "[")
            return AxLit._Arr(s, &pos)
        if (c = Chr(34) || c = "'")
            return AxLit._Str(s, &pos)
        return AxLit._Word(s, &pos)
    }
    static _Obj(s, &pos) {
        out := Map()
        out.CaseSense := false
        pos++                                     ; past {
        loop {
            AxLit._Skip(s, &pos)
            c := SubStr(s, pos, 1)
            if (c = "")
                return AxLit.FAIL
            if (c = "}") {
                pos++
                return out
            }
            if (c = ",") {
                pos++
                continue
            }
            if (c = Chr(34) || c = "'") {
                k := AxLit._Str(s, &pos)
                if (k == AxLit.FAIL)
                    return AxLit.FAIL
            } else if RegExMatch(SubStr(s, pos), "^([A-Za-z_]\w*)", &m) {
                k := m[1]
                pos += StrLen(m[1])
            } else
                return AxLit.FAIL
            AxLit._Skip(s, &pos)
            if (SubStr(s, pos, 1) != ":")
                return AxLit.FAIL
            pos++
            v := AxLit._Val(s, &pos)
            if (v == AxLit.FAIL)
                return AxLit.FAIL
            out[k] := v
        }
    }
    static _Arr(s, &pos) {
        out := []
        pos++                                     ; past [
        loop {
            AxLit._Skip(s, &pos)
            c := SubStr(s, pos, 1)
            if (c = "")
                return AxLit.FAIL
            if (c = "]") {
                pos++
                return out
            }
            if (c = ",") {
                pos++
                continue
            }
            v := AxLit._Val(s, &pos)
            if (v == AxLit.FAIL)
                return AxLit.FAIL
            out.Push(v)
        }
    }
    ; AutoHotkey's escapes are backtick ones, and a doubled quote is not an
    ; escape at all -- the backtick one is.
    static _Str(s, &pos) {
        q := SubStr(s, pos, 1)
        pos++
        out := "", n := StrLen(s)
        while (pos <= n) {
            c := SubStr(s, pos, 1)
            if (c = "``") {
                e := SubStr(s, pos + 1, 1)
                switch e {
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case "b": out .= Chr(8)
                case "s": out .= " "
                case "":  return AxLit.FAIL
                default:  out .= e
                }
                pos += 2
                continue
            }
            if (c = q) {
                pos++
                return out
            }
            if (c = "`n")
                return AxLit.FAIL                 ; a string does not cross a line
            out .= c
            pos++
        }
        return AxLit.FAIL
    }
    ; A number, true/false, or anything else -- which is code, and is kept as
    ; written. "Anything else" has to stop at the comma or bracket that ends
    ; it, and do that without being fooled by one inside a string or a nested
    ; call, so the brackets are counted and the strings are read past.
    static _Word(s, &pos) {
        n := StrLen(s), start := pos, depth := 0
        while (pos <= n) {
            c := SubStr(s, pos, 1)
            if (c = Chr(34) || c = "'") {
                if (AxLit._Str(s, &pos) == AxLit.FAIL)
                    return AxLit.FAIL
                continue
            }
            if (c = "(" || c = "[" || c = "{")
                depth++
            else if (c = ")" || c = "]" || c = "}") {
                if (depth = 0)
                    break
                depth--
            } else if (depth = 0 && (c = "," || c = "`n"))
                break
            pos++
        }
        raw := Trim(SubStr(s, start, pos - start), " `t`n")
        if (raw = "")
            return AxLit.FAIL
        if IsNumber(raw)
            return raw + 0
        if (raw = "true")
            return true
        if (raw = "false")
            return false
        if (raw = "unset")
            return ""
        return {Raw: raw}
    }

    ; =====================================================================
    ;  Writing one out
    ; =====================================================================
    ; The inverse of Read: Maps, Arrays, strings, numbers and {Raw: ...} back
    ; into AutoHotkey source, indented so a person can read it. `order` names
    ; the keys that come first, because a Map has no order of its own and
    ; {Label: "Paste", Id: "paste"} reads like a shuffle.
    static Write(v, depth := 0, order := "") {
        if (v is Array)
            return AxLit._WArr(v, depth, order)
        if (v is Map)
            return AxLit._WObj(v, depth, order)
        if AxLit.IsRaw(v)
            return String(v.Raw)
        if (v == true)
            return "true"
        if (v == false)
            return "false"
        if (!(v is String) && IsNumber(v))
            return AxLit.N(v)
        return AxLit.S(v)
    }
    static _WArr(a, depth, order) {
        if !a.Length
            return "[]"
        ; a list of plain values goes on one line; a list of objects does not
        flat := true
        for v in a
            flat := flat && !IsObject(v)
        if flat {
            out := ""
            for v in a
                out .= (out = "" ? "" : ", ") AxLit.Write(v, depth, order)
            return "[" out "]"
        }
        pad := AxLit.Pad(depth + 1)
        out := ""
        for v in a
            out .= (out = "" ? "" : ",`n") pad AxLit.Write(v, depth + 1, order)
        return "[`n" out "]"
    }
    static _WObj(m, depth, order) {
        keys := []
        for k in StrSplit(String(order), "|")
            if (k != "" && m.Has(k))
                keys.Push(k)
        for k in m {
            seen := false
            for x in keys
                seen := seen || (x = k)
            if !seen
                keys.Push(k)
        }
        if !keys.Length
            return "{}"
        ; an object holding another object is worth a line each; a flat one
        ; reads better as the one line it is
        deep := false
        for k in keys
            deep := deep || (IsObject(m[k]) && !AxLit.IsRaw(m[k]))
        sep := deep ? (",`n" AxLit.Pad(depth + 1)) : ", "
        out := ""
        for k in keys
            out .= (out = "" ? "" : sep) k ": " AxLit.Write(m[k], depth + 1, order)
        return "{" out "}"
    }

    static Pad(depth) {
        s := ""
        loop depth
            s .= "    "
        return s
    }
}
