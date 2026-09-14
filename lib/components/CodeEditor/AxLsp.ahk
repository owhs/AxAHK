#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxJson.ahk

; =============================================================================
;  AxLsp -- a Language Server Protocol client: any server that speaks LSP over
;  its standard input and output, started as a hidden process.
;
;      lsp := AxLsp('"C:\Program Files\nodejs\node.exe" "...\server.js" --stdio')
;      lsp.Start(A_ScriptDir)                  ; initialize, with this as the root
;      ed.UseLsp(lsp)                          ; completion, hovers, problems
;
;  AxLsp.FindAhk2() finds thqby's AutoHotkey v2 server where VS Code keeps it
;  and hands back the command line, or "".
;
;  The wire: JSON-RPC, each message a "Content-Length: N" header and N bytes of
;  UTF-8. Reading is a timer that asks the pipe how much is waiting and never
;  blocks, so a slow server cannot freeze the window.
;
;    Request(method, params, fn)   fn(result, error) when the answer comes
;    Notify(method, params)        no answer
;    On(method, fn)                a notification from the server: fn(params)
;    Open(uri, langId, text) / Change(uri, text) / Close(uri)
;    Complete(uri, line, col, fn) / Hover(uri, line, col, fn)    0-based
;    Stop()
;    Log                           the last 200 lines in and out, for a look
; =============================================================================
class AxLsp {
    __New(cmd, name := "lsp") {
        this.Cmd := cmd, this.Name := name
        this.Pid := 0, this.hIn := 0, this.hOut := 0, this.hProc := 0
        this.NextId := 0, this.Waiting := Map(), this.Handlers := Map(), this.Versions := Map()
        this.Ready := false, this.Caps := "", this.Log := []
        this._buf := Buffer(65536), this._len := 0
        this._tick := ObjBindMethod(this, "_Poll")
        this._queue := []
    }
    ; thqby's vscode-autohotkey2-lsp, if VS Code has it
    static FindAhk2() {
        node := ""
        for p in [A_ProgramFiles "\nodejs\node.exe", EnvGet("LOCALAPPDATA") "\Programs\nodejs\node.exe"]
            if FileExist(p) {
                node := p
                break
            }
        if (node = "")
            return ""
        best := ""
        loop files EnvGet("USERPROFILE") "\.vscode\extensions\thqby.vscode-autohotkey2-lsp-*", "D"
            if FileExist(A_LoopFileFullPath "\server\dist\server.js")
                best := A_LoopFileFullPath "\server\dist\server.js"
        return (best = "") ? "" : '"' node '" "' best '" --stdio'
    }

    ; --------------------------------------------------------------- process
    Start(root := "", initOptions := "") {
        if this.Pid
            return this
        sa := Buffer(24, 0)
        NumPut("UInt", 24, sa, 0), NumPut("Int", 1, sa, 16)            ; inheritable
        DllCall("CreatePipe", "Ptr*", &outR := 0, "Ptr*", &outW := 0, "Ptr", sa, "UInt", 0)
        DllCall("CreatePipe", "Ptr*", &inR := 0, "Ptr*", &inW := 0, "Ptr", sa, "UInt", 0)
        DllCall("SetHandleInformation", "Ptr", outR, "UInt", 1, "UInt", 0)   ; our ends are ours alone
        DllCall("SetHandleInformation", "Ptr", inW, "UInt", 1, "UInt", 0)
        si := Buffer(A_PtrSize = 8 ? 104 : 68, 0)
        NumPut("UInt", si.Size, si, 0)
        NumPut("UInt", 0x100, si, A_PtrSize = 8 ? 60 : 44)               ; STARTF_USESTDHANDLES
        NumPut("Ptr", inR, si, A_PtrSize = 8 ? 80 : 56)
        NumPut("Ptr", outW, si, A_PtrSize = 8 ? 88 : 60)
        NumPut("Ptr", outW, si, A_PtrSize = 8 ? 96 : 64)
        pi := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
        ok := DllCall("CreateProcessW", "Ptr", 0, "Str", this.Cmd, "Ptr", 0, "Ptr", 0, "Int", 1,
                      "UInt", 0x08000000, "Ptr", 0, "Ptr", 0, "Ptr", si, "Ptr", pi)      ; CREATE_NO_WINDOW
        DllCall("CloseHandle", "Ptr", inR), DllCall("CloseHandle", "Ptr", outW)
        if !ok {
            DllCall("CloseHandle", "Ptr", outR), DllCall("CloseHandle", "Ptr", inW)
            throw Error("The language server did not start: " this.Cmd)
        }
        this.hProc := NumGet(pi, 0, "Ptr")
        DllCall("CloseHandle", "Ptr", NumGet(pi, A_PtrSize, "Ptr"))
        this.Pid := NumGet(pi, A_PtrSize * 2, "UInt")
        this.hOut := outR, this.hIn := inW
        SetTimer(this._tick, 30)
        root := (root = "") ? A_WorkingDir : root
        params := Map("processId", DllCall("GetCurrentProcessId", "UInt"), "rootUri", AxLsp.Uri(root),
            "rootPath", root, "workspaceFolders", [Map("uri", AxLsp.Uri(root), "name", "root")],
            "capabilities", Map("textDocument", Map(
                "completion", Map("completionItem", Map("snippetSupport", 0, "documentationFormat", ["plaintext", "markdown"])),
                "hover", Map("contentFormat", ["markdown", "plaintext"]),
                "publishDiagnostics", Map("relatedInformation", 0),
                "synchronization", Map("didSave", 1))))
        if IsObject(initOptions)
            params["initializationOptions"] := initOptions
        this.Request("initialize", params, (res, err) => this._Initialized(res))
        return this
    }
    _Initialized(res) {
        this.Caps := (res is Map) ? res.Get("capabilities", "") : ""
        this.Notify("initialized", Map())
        this.Ready := true
        for m in this._queue
            this._Write(m)
        this._queue := []
    }
    Stop() {
        if !this.Pid
            return
        try this.Request("shutdown", "", (*) => this.Notify("exit", ""))
        SetTimer(ObjBindMethod(this, "_Kill"), -1500)
    }
    _Kill() {
        SetTimer(this._tick, 0)
        if (this.hProc && DllCall("WaitForSingleObject", "Ptr", this.hProc, "UInt", 0) != 0)
            DllCall("TerminateProcess", "Ptr", this.hProc, "UInt", 0)       ; only the one it started
        for h in [this.hIn, this.hOut, this.hProc]
            if h
                DllCall("CloseHandle", "Ptr", h)
        this.hIn := this.hOut := this.hProc := this.Pid := 0
        this.Ready := false
    }
    __Delete() => this._Kill()

    ; ------------------------------------------------------------- messages
    Request(method, params, fn := "") {
        id := ++this.NextId
        if fn
            this.Waiting[id] := fn
        m := Map("jsonrpc", "2.0", "id", id, "method", method)
        if (params != "")
            m["params"] := params
        this._Send(m, method != "initialize")
        return id
    }
    Notify(method, params) {
        m := Map("jsonrpc", "2.0", "method", method)
        if (params != "")
            m["params"] := params
        this._Send(m, method != "initialized" && method != "exit")
    }
    On(method, fn) {
        if !this.Handlers.Has(method)
            this.Handlers[method] := []
        this.Handlers[method].Push(fn)
        return this
    }
    ; until the server has answered initialize, everything else waits
    _Send(m, afterInit := true) {
        if (afterInit && !this.Ready)
            return this._queue.Push(m)
        this._Write(m)
    }
    _Write(m) {
        if !this.hIn
            return
        body := AxJson.Stringify(m, "")
        this._Note(">> " SubStr(body, 1, 300))
        n := StrPut(body, "UTF-8") - 1
        head := "Content-Length: " n "`r`n`r`n"
        buf := Buffer(StrLen(head) + n + 1)
        StrPut(head, buf, "UTF-8")
        StrPut(body, buf.Ptr + StrLen(head), "UTF-8")
        DllCall("WriteFile", "Ptr", this.hIn, "Ptr", buf, "UInt", StrLen(head) + n, "UInt*", 0, "Ptr", 0)
    }
    _Poll() {
        if !this.hOut
            return
        loop 20 {
            avail := 0
            if !DllCall("PeekNamedPipe", "Ptr", this.hOut, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt*", &avail, "Ptr", 0) {
                this._Kill()                                  ; the server is gone
                return
            }
            if !avail
                break
            need := this._len + avail
            if (need > this._buf.Size) {
                nb := Buffer(Max(need, this._buf.Size * 2))
                DllCall("RtlMoveMemory", "Ptr", nb, "Ptr", this._buf, "UPtr", this._len)
                this._buf := nb
            }
            got := 0
            DllCall("ReadFile", "Ptr", this.hOut, "Ptr", this._buf.Ptr + this._len, "UInt", avail, "UInt*", &got, "Ptr", 0)
            this._len += got
        }
        while this._Frame()
            continue
    }
    ; one whole message off the front of what has arrived, if there is one
    _Frame() {
        if (this._len < 20)
            return false
        head := StrGet(this._buf, Min(this._len, 200), "UTF-8")
        sep := InStr(head, "`r`n`r`n")
        if !sep || !RegExMatch(SubStr(head, 1, sep), "i)Content-Length:\s*(\d+)", &m)
            return false
        hlen := StrPut(SubStr(head, 1, sep + 3), "UTF-8") - 1
        n := Integer(m[1])
        if (this._len < hlen + n)
            return false
        body := StrGet(this._buf.Ptr + hlen, n, "UTF-8")
        rest := this._len - hlen - n
        if rest
            DllCall("RtlMoveMemory", "Ptr", this._buf, "Ptr", this._buf.Ptr + hlen + n, "UPtr", rest)
        this._len := rest
        this._Note("<< " SubStr(body, 1, 300))
        msg := ""
        try msg := AxJson.Parse(body)
        if (msg is Map)
            this._Dispatch(msg)
        return true
    }
    _Dispatch(msg) {
        if (msg.Has("id") && !msg.Has("method")) {                   ; an answer
            id := msg["id"]
            if this.Waiting.Has(id) {
                fn := this.Waiting[id]
                this.Waiting.Delete(id)
                try fn(msg.Get("result", ""), msg.Get("error", ""))
            }
            return
        }
        method := msg.Get("method", "")
        if msg.Has("id") {                                           ; the server asks us: say we heard
            this._Write(Map("jsonrpc", "2.0", "id", msg["id"], "result", ""))
            return
        }
        if this.Handlers.Has(method)
            for fn in this.Handlers[method].Clone()
                try fn(msg.Get("params", ""))
    }
    _Note(s) {
        this.Log.Push(FormatTime(, "HH:mm:ss") " " s)
        if (this.Log.Length > 200)
            this.Log.RemoveAt(1)
    }

    ; ------------------------------------------------------------ documents
    static Uri(path) {
        p := StrReplace(path, "\", "/")
        p := RegExReplace(p, "^([A-Za-z]):", "$1%3A")
        p := StrReplace(p, " ", "%20")
        return "file:///" LTrim(p, "/")
    }
    Open(uri, langId, text) {
        this.Versions[uri] := 1
        this.Notify("textDocument/didOpen", Map("textDocument", Map("uri", uri, "languageId", langId, "version", 1, "text", text)))
    }
    Change(uri, text) {
        v := this.Versions.Get(uri, 1) + 1
        this.Versions[uri] := v
        this.Notify("textDocument/didChange", Map("textDocument", Map("uri", uri, "version", v),
            "contentChanges", [Map("text", text)]))
    }
    Close(uri) => this.Notify("textDocument/didClose", Map("textDocument", Map("uri", uri)))
    Complete(uri, line, col, fn) => this.Request("textDocument/completion",
        Map("textDocument", Map("uri", uri), "position", Map("line", line, "character", col)), fn)
    Hover(uri, line, col, fn) => this.Request("textDocument/hover",
        Map("textDocument", Map("uri", uri), "position", Map("line", line, "character", col)), fn)

    ; -------------------------------------------------------- an editor on it
    ; The editor's text goes to the server as it changes; the server's
    ; problems come back as marks, its completion as suggestions, and its
    ; hover as the card by the word.
    static Kinds := Map(1, "word", 2, "method", 3, "fn", 4, "fn", 5, "prop", 6, "var", 7, "class", 8, "class", 9, "class",
        10, "prop", 12, "var", 13, "class", 14, "kw", 15, "snippet", 17, "file", 21, "var", 22, "class", 25, "class")
    static Attach(lsp, ed, uri := "", langId := "") {
        static n := 0
        if (uri = "")
            uri := AxLsp.Uri(A_Temp "\axce_" (++n) ".ahk")
        if (langId = "")
            langId := (ed.Cfg.HasOwnProp("lang") && ed.Cfg.lang != "ahk") ? ed.Cfg.lang : "ahk2"
        lsp.Open(uri, langId, ed.Value)
        sent := {text: ed.Value}
        Sync(text) {
            if (text != sent.text)
                lsp.Change(uri, text), sent.text := text
        }
        ed.OnLint((text, e) => (Sync(text), ""))
        lsp.On("textDocument/publishDiagnostics", (p) => AxLsp._Marks(p, uri, ed))
        ; the server has the text as it is now before it is asked about a place in it
        ed.OnComplete((req, e) => (Sync(e.Value), lsp.Complete(uri, req.line - 1, req.col - 1, (res, err) => e.Items(req.q, AxLsp._Items(res))), ""))
        ed.OnHover((word, e, q, line := 0, col := 0) => AxLsp._HoverAt(lsp, uri, e, word, q, line, col))
        return ed
    }
    static _Marks(p, uri, ed) {
        if !(p is Map) || p.Get("uri", "") != uri
            return
        marks := []
        for d in p.Get("diagnostics", []) {
            r := d.Get("range", Map()), s := r.Get("start", Map()), e := r.Get("end", Map())
            ln := s.Get("line", 0) + 1, col := s.Get("character", 0) + 1
            len := (e.Get("line", 0) = s.Get("line", 0)) ? e.Get("character", 0) - s.Get("character", 0) : 0
            sev := d.Get("severity", 1)
            marks.Push({line: ln, col: col, len: len, sev: sev = 1 ? "error" : sev = 2 ? "warn" : "info", msg: d.Get("message", "")})
        }
        ed.SetMarks(marks)
    }
    static _Items(res) {
        list := (res is Map) ? res.Get("items", []) : (res is Array ? res : [])
        out := []
        for it in list {
            if !(it is Map)
                continue
            label := it.Get("label", "")
            ins := it.Get("insertText", "")
            if (ins = "" && it.Has("textEdit") && it["textEdit"] is Map)
                ins := it["textEdit"].Get("newText", "")
            if (ins = "")
                ins := label
            ; snippet placeholders: the first stop is where the caret goes
            ins := RegExReplace(ins, "\$\{\d+:([^}]*)\}", "$1")
            ins := RegExReplace(ins, "\$\d+", Chr(1), , 1)
            ins := StrReplace(RegExReplace(ins, "\$\d+"), Chr(1), "$0")
            out.Push({label: label, kind: AxLsp.Kinds.Get(it.Get("kind", 1), "word"),
                      detail: SubStr(it.Get("detail", ""), 1, 60), insert: ins})
        }
        return out
    }
    static _HoverAt(lsp, uri, ed, word, q, line := 0, col := 0) {
        ; the server wants a place: the one under the mouse (1-based from the
        ; page), or else the word's first place in the text
        if (line > 0 && col > 0) {
            line -= 1, col -= 1
        } else {
            text := ed.Value
            if !RegExMatch(text, "\b\Q" word "\E\b", &m)
                return ""
            before := SubStr(text, 1, m.Pos - 1)
            line := StrLen(before) - StrLen(StrReplace(before, "`n"))
            col := m.Pos - 1 - (InStr(before, "`n", , -1) ? InStr(before, "`n", , -1) : 0)
        }
        lsp.Hover(uri, line, col, (res, err) => ed.Hovered(q, AxLsp._HoverHtml(res), true))
        return ""
    }
    static _HoverHtml(res) {
        if !(res is Map)
            return ""
        c := res.Get("contents", "")
        text := ""
        if (c is Map)
            text := c.Get("value", "")
        else if (c is Array) {
            for x in c
                text .= ((x is Map) ? x.Get("value", "") : String(x)) "`n"
        } else
            text := String(c)
        html := StrReplace(StrReplace(StrReplace(Trim(text, "`n"), "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
        bt := Chr(96)                                   ; a backtick, without escaping one
        html := RegExReplace(html, "s)" bt bt bt "\w*\n(.*?)" bt bt bt, "<code>$1</code>")
        html := RegExReplace(html, bt "([^" bt "]+)" bt, "<code>$1</code>")
        return StrReplace(html, "`n", "<br>")
    }
}
