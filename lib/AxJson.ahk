#Requires AutoHotkey v2.0

; =============================================================================
;  AxJson.ahk -- JSON: AxStudio's project files, and the components that talk
;  to a page or a language server.
;
;  Parse(text)     -> Map / Array / String / Number  ("" for null, 1/0 for bools)
;  Stringify(v, indent)  -> text; AHK iterates a Map in sorted key order, so
;                           two saves of the same project are byte identical.
;
;  Only what a project file needs: objects, arrays, strings, numbers, the three
;  literals. Numbers come back as Integer or Float, so a width written as 120
;  is still 120 after a round trip rather than "120.0".
; =============================================================================
class AxJson {

    ; ------------------------------------------------------------- writing
    static Stringify(v, indent := "  ", level := 0) {
        pretty := (indent != "")
        nl := pretty ? "`n" : ""
        pad := pretty ? AxJson._Rep(indent, level + 1) : ""
        end := pretty ? AxJson._Rep(indent, level) : ""
        t := Type(v)
        if (t = "Map" || t = "Object")
            return AxJson._Obj(v, t, indent, level, nl, pad, end)
        if (t = "Array") {
            if (v.Length = 0)
                return "[]"
            s := "["
            for i, x in v
                s .= (i = 1 ? "" : ",") nl pad AxJson.Stringify(x, indent, level + 1)
            return s nl end "]"
        }
        if (t = "Integer" || t = "Float")
            return AxJson._Num(v)
        if (t = "String")
            return '"' AxJson.Escape(v) '"'
        return "null"                       ; unsupported types are dropped, not guessed
    }
    static _Obj(v, t, indent, level, nl, pad, end) {
        pairs := (t = "Map") ? v : v.OwnProps()
        s := "", n := 0
        for k, x in pairs
            s .= (n++ ? "," : "") nl pad '"' AxJson.Escape(String(k)) '":' (indent != "" ? " " : "") AxJson.Stringify(x, indent, level + 1)
        return n ? "{" s nl end "}" : "{}"
    }
    ; A float that happens to be whole is written without its ".0" so that a
    ; coordinate stays readable; everything else keeps full precision.
    static _Num(v) {
        if (Type(v) = "Integer")
            return String(v)
        if (v = Round(v) && Abs(v) < 1e15)
            return String(Integer(v))
        ; String(0.18) is "0.17999999999999999": true, and unreadable in a file
        ; a person edits. The shortest spelling that reads back as the same
        ; number is the one written.
        loop 12 {
            s := Format("{:." (A_Index + 5) "g}", v)
            if (Float(s) = v)
                return s
        }
        return String(v)
    }
    static _Rep(s, n) {
        out := ""
        loop n
            out .= s
        return out
    }
    static Escape(s) {
        ; most strings need nothing: one scan says so, instead of forty
        if !RegExMatch(s, 'S)[\x00-\x1F"\\]')
            return s
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`t", "\t")
        s := StrReplace(s, "`b", "\b")
        s := StrReplace(s, "`f", "\f")
        ; the remaining control characters have no short form
        loop 32 {
            c := Chr(A_Index - 1)
            if InStr(s, c)
                s := StrReplace(s, c, Format("\u{:04x}", A_Index - 1))
        }
        return s
    }

    ; ------------------------------------------------------------- reading
    ; One token at a time, each read whole by an anchored pattern at the
    ; place reached, and the text handed on by reference (&s) -- never as a
    ; value. Both matter: a string read out of an object property, or passed
    ; as a plain argument, is a copy, and the old reader took one of the
    ; whole text for every character it looked at. A 450 KB file took thirty
    ; seconds; it takes a fraction of one now.
    static Parse(text) {
        pos := 1
        v := AxJson._V(&text, &pos)
        if RegExMatch(text, "S)[^ \t\r\n]", &m, pos)
            throw Error("JSON: trailing text at " m.Pos, -1)
        return v
    }
    ; a string token (quotes included) -> its text
    static _S(q) {
        q := SubStr(q, 2, -1)
        if !InStr(q, "\")
            return q
        out := "", at := 1
        while (p := InStr(q, "\", true, at)) {
            out .= SubStr(q, at, p - at)
            e := SubStr(q, p + 1, 1), at := p + 2
            switch e, true {
            case '"': out .= '"'
            case "\": out .= "\"
            case "/": out .= "/"
            case "b": out .= "`b"
            case "f": out .= "`f"
            case "n": out .= "`n"
            case "r": out .= "`r"
            case "t": out .= "`t"
            case "u":
                out .= Chr(Integer("0x" SubStr(q, at, 4))), at += 4
            default:
                throw Error("JSON: bad escape \" e, -1)
            }
        }
        return out SubStr(q, at)
    }
    static _V(&s, &pos) {
        static re := 'SA)[ \t\r\n]*+(?:(\{)|(\[)|("[^"\\]*+(?:\\.[^"\\]*+)*+")|(-?\d++(?:\.\d++)?(?:[eE][+\-]?\d++)?)|(true)|(false)|(null))'
        if !RegExMatch(s, re, &m, pos)
            throw Error(pos > StrLen(s) ? "JSON: unexpected end" : "JSON: bad value at " pos, -1)
        pos += m.Len
        if (m[1] != "")
            return AxJson._O(&s, &pos)
        if (m[2] != "")
            return AxJson._A(&s, &pos)
        if (m[3] != "")
            return AxJson._S(m[3])
        if (m[4] != "")
            return RegExMatch(m[4], "[.eE]") ? Float(m[4]) : Integer(m[4])
        return (m[5] != "") ? 1 : (m[6] != "") ? 0 : ""
    }
    static _O(&s, &pos) {
        static key := 'SA)[ \t\r\n]*+(?:(\})|("[^"\\]*+(?:\\.[^"\\]*+)*+")[ \t\r\n]*+:)'
        static sep := 'SA)[ \t\r\n]*+([,}])'
        obj := Map()
        loop {
            if !RegExMatch(s, key, &m, pos)
                throw Error("JSON: expected a key at " pos, -1)
            pos += m.Len
            if (m[1] != "")
                return obj
            obj[AxJson._S(m[2])] := AxJson._V(&s, &pos)
            if !RegExMatch(s, sep, &m, pos)
                throw Error("JSON: expected ',' or '}' at " pos, -1)
            pos += m.Len
            if (m[1] = "}")
                return obj
        }
    }
    static _A(&s, &pos) {
        static close := 'SA)[ \t\r\n]*+\]'
        static sep := 'SA)[ \t\r\n]*+([,\]])'
        arr := []
        if RegExMatch(s, close, &m, pos)
            return (pos += m.Len, arr)
        loop {
            arr.Push(AxJson._V(&s, &pos))
            if !RegExMatch(s, sep, &m, pos)
                throw Error("JSON: expected ',' or ']' at " pos, -1)
            pos += m.Len
            if (m[1] = "]")
                return arr
        }
    }

    ; ------------------------------------------------------- small helpers
    ; Reading a value out of a parsed Map without a Has() dance at every site.
    static Get(m, key, def := "") {
        if (m is Map)
            return m.Has(key) ? m[key] : def
        return def
    }
    static Load(path) => AxJson.Parse(FileRead(path, "UTF-8"))
    static Save(path, v, indent := "  ") {
        s := AxJson.Stringify(v, indent)
        if FileExist(path)
            FileDelete(path)
        FileAppend(s, path, "UTF-8-RAW")
        return path
    }
}
