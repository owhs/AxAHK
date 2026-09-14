; AxtReader.ahk — reads AstHost's AXT1 parse trees (PROTOCOL.md, "Binary parse output") lazily: nothing is parsed,
; every field is a NumGet/StrGet at a fixed offset. Nodes are 0-based indexes in pre-order (0 = Program).
;
;   t := AxtTree.FromShm(reply.shm, reply.bytes)   ; "to":"shm"    (no disk; send {"cmd":"release","shm":…} when done)
;   t := AxtTree.FromFile(reply.bin)               ; "to":"file"
;   t := AxtTree.FromBase64(reply.base64)          ; "to":"base64" (no disk)
;   loop t.count
;       i := A_Index - 1, MsgBox t.Type(i) " " t.Value(i) " " t.Start(i) ".." t.End(i)
;   for c in t.Children(0)                          ; direct children
;       ...

#Requires AutoHotkey v2.0

class AxtTree {
    static FromFile(path) {
        buf := FileRead(path, "RAW")
        return AxtTree(buf.Ptr, buf.Size, buf)
    }

    ; Maps the host's shared memory section read-only. The view stays valid until this object is released, even after
    ; the host's `release`.
    static FromShm(name, size) {
        h := DllCall("OpenFileMappingW", "UInt", 0x4, "Int", 0, "Str", name, "Ptr") ; FILE_MAP_READ
        if !h
            throw OSError(A_LastError, -1, name)
        p := DllCall("MapViewOfFile", "Ptr", h, "UInt", 0x4, "UInt", 0, "UInt", 0, "UPtr", 0, "Ptr")
        if !p {
            err := A_LastError
            DllCall("CloseHandle", "Ptr", h)
            throw OSError(err, -1, name)
        }
        t := AxtTree(p, size, "")
        t._map := h, t._view := p
        return t
    }

    static FromBase64(b64) {
        n := 0
        DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &n, "Ptr", 0, "Ptr", 0)
        buf := Buffer(n)
        DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &n, "Ptr", 0, "Ptr", 0)
        return AxtTree(buf.Ptr, n, buf)
    }

    __New(ptr, size, keep) {
        this.p := ptr, this.size := size, this._keep := keep, this._map := 0, this._view := 0
        if StrGet(ptr, 4, "CP0") != "AXT1"
            throw ValueError("not an AXT1 tree")
        this.count := NumGet(ptr, 8, "UInt")
        this.rs := NumGet(ptr, 12, "UInt")      ; record size (48)
        this.nodes := NumGet(ptr, 16, "UInt")
        this.strs := NumGet(ptr, 20, "UInt")
        this.types := this._Table(28)            ; type names
        this.flagNames := this._Table(36)        ; flag bit i = flagNames[i + 1]
        this.files := this._Table(44)            ; full paths ("" = the pasted text)
        this.flagBit := Map()
        this.flagBit.CaseSense := false
        for i, name in this.flagNames
            this.flagBit[name] := 1 << (i - 1)
    }

    __Delete() {
        if this._view {
            DllCall("UnmapViewOfFile", "Ptr", this._view)
            DllCall("CloseHandle", "Ptr", this._map)
        }
    }

    _Table(at) {
        n := NumGet(this.p, at, "UInt"), off := NumGet(this.p, at + 4, "UInt"), a := []
        loop n
            a.Push(this.Str(NumGet(this.p, off + (A_Index - 1) * 4, "UInt")))
        return a
    }

    ; a string ref: u32 length (UTF-16 units) then the text; 0xFFFFFFFF = none
    Str(ref) => ref = 0xFFFFFFFF ? "" : StrGet(this.p + this.strs + ref + 4, NumGet(this.p, this.strs + ref, "UInt"), "UTF-16")

    Rec(i) => this.nodes + i * this.rs
    Type(i) => this.types[NumGet(this.p, this.Rec(i), "UShort") + 1]
    File(i) => this.files[NumGet(this.p, this.Rec(i) + 2, "UShort") + 1]
    FileIndex(i) => NumGet(this.p, this.Rec(i) + 2, "UShort")
    Flags(i) => NumGet(this.p, this.Rec(i) + 4, "UInt")
    Has(i, flag) => this.flagBit.Has(flag) && (this.Flags(i) & this.flagBit[flag]) != 0
    Parent(i) => this._Idx(NumGet(this.p, this.Rec(i) + 8, "UInt"))
    Next(i) => this._Idx(NumGet(this.p, this.Rec(i) + 12, "UInt"))
    ChildCount(i) => NumGet(this.p, this.Rec(i) + 16, "UInt")
    FirstChild(i) => this.ChildCount(i) && !this.Has(i, "truncated") ? i + 1 : -1
    Start(i) => NumGet(this.p, this.Rec(i) + 20, "UInt")      ; UTF-16 offset in that file's text
    End(i) => NumGet(this.p, this.Rec(i) + 24, "UInt")        ; exclusive
    StartLine(i) => NumGet(this.p, this.Rec(i) + 28, "UInt")
    EndLine(i) => NumGet(this.p, this.Rec(i) + 32, "UInt")
    StartCol(i) => NumGet(this.p, this.Rec(i) + 44, "UInt")
    Value(i) => this.Str(NumGet(this.p, this.Rec(i) + 36, "UInt"))
    Meta(i) => this.Str(NumGet(this.p, this.Rec(i) + 40, "UInt"))
    ; the node's text, given that file's source: SubStr is 1-based
    Text(i, source) => SubStr(source, this.Start(i) + 1, this.End(i) - this.Start(i))
    ; index after node i's whole subtree (pre-order): skip a subtree in one step
    SubtreeEnd(i) => (n := this.Next(i)) >= 0 ? n : (p := this.Parent(i)) >= 0 ? this.SubtreeEnd(p) : this.count

    ; `for c in t.Children(i)`
    Children(i) {
        c := this.FirstChild(i)
        return Step
        Step(&out) {
            if c < 0
                return false
            out := c
            c := this.Next(c)
            return true
        }
    }

    _Idx(v) => v = 0xFFFFFFFF ? -1 : v
}
