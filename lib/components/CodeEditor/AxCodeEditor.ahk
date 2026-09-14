#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
#Include %A_LineFile%\..\..\..\AxJson.ahk
#Include %A_LineFile%\..\AxCodeEditor.Ahk.ahk
#Include %A_LineFile%\..\AxLsp.ahk
; single-file exe: this component's stylesheet and script travel inside it
;@Ahk2Exe-AddResource %U_AxLib%\components\CodeEditor\AxCodeEditor.css, AX_COMPONENTS_CODEEDITOR_AXCODEEDITOR_CSS
;@Ahk2Exe-AddResource %U_AxLib%\components\CodeEditor\AxCodeEditor.js, AX_COMPONENTS_CODEEDITOR_AXCODEEDITOR_JS

; =============================================================================
;  AxCodeEditor -- a code editor: colours, line numbers, folding, suggestions,
;  find and replace, undo, problems under the text, and a language service
;  behind it that you choose -- the built-in AutoHotkey one, a real language
;  server, or your own functions.
;
;      ed := g.AddCodeEditor("vcode h420 Lang=ahk Theme=dark", "MsgBox(`"hi`")")
;      ed.UseAhk()                                ; AutoHotkey's words and hovers (waits for Show)
;      ed.OnEvent("Change", (ctl, text, *) => ...)
;
;  ---------------------------------------------------------------- options
;    Lang=ahk|js|json|css|html|xml|ini|md|ps1|py|sql|plain    (or your own)
;    Theme=auto|dark|light|monokai|solarized|dracula|contrast
;    Preset=ide|notes|log|config|snippet   a set of the flags below at once
;    FontSize=13  Font="Consolas"  Placeholder="..."
;    Wrap  NoGutter  NoFold  NoSuggest  NoStatus  ReadOnly  NoCurrentLine
;    Minimap / NoMinimap (the map of the text on the right; ide has it)  NoGuides
;
;  ------------------------------------------------------------- the words
;    ctl.Value / Text        the text; setting it keeps the caret where it can
;    Load(text)              a fresh text: no undo back past it
;    Insert(text)  Append(text, scroll := true)  Selected()  Select(a, b)
;    Caret()  -> {line, col, a, b}      GoTo(line, col)       Focus()
;    SetLanguage(lang)  SetTheme(name)  SetOption(name, value)
;    FoldAll(on := true)  Undo()  Redo()  Find(text, replace := false)
;    ReplaceAll(find, with, flags := "")  -> how many; flags: c (case) w (whole word)
;                        r (a regular expression: $1 in `with` is its first group)
;    SetWords(list)      more to suggest: "name" or {label, kind, detail, insert, scope}
;                        (a detail of "(a, b?)" on a fn shows as its parameters card)
;    SetWordSet(name, list, lang?)   a named list of them, only for that language
;    AddSnippets(list)   {label, body} -- $0 is where the caret lands
;    SetMarks(list) / ClearMarks()    problems: {line, col, len, sev, msg}
;    AddLanguage(name, def)           a language of your own, as data
;    Symbols()           what the text defines: [{name, kind, line}]
;    LoadFile(path) / SaveFile(path)
;    UseScript(path)     your own JavaScript in the page, embedded when compiled
;
;  --------------------------------------------------------- the services
;    OnComplete(fn)      fn(req, ed) -> items, or "" and ed.Items(req.q, items) later
;                        req: {q, word, scope, line, col, text}
;    OnHover(fn)         fn(word, ed) -> text shown by the word under the mouse
;    OnLint(fn)          fn(text, ed) -> problems, after each pause in the typing
;    OnSave(fn)          fn(text, ed) on Ctrl+S
;    OnChange(fn)        fn(text, ed) when the user has changed it
;    OnCaret(fn)         fn(line, col, ed) when the caret moves
;    UseAhk(opts?)       the built-in AutoHotkey service: its functions and
;                        variables, what the text defines, hovers with the
;                        signature, and -- {Lint: true} -- AutoHotkey's own
;                        /validate as the problems
;    UseLsp(lsp, uri?, langId?)   a language server (AxLsp): its completion,
;                        hovers and problems
;
;  Keys: Ctrl+Space suggest (Ctrl+Shift+Space the parameters), Ctrl+F / Ctrl+H
;  find / replace (Alt+C case, Alt+W word, Alt+R pattern), F3 next, Ctrl+G go to
;  line, Ctrl+Shift+O go to what the text defines, F8 the next problem, Ctrl+/
;  comment, Ctrl+D / Shift+Alt+Down duplicate, Alt+Up/Down move the line,
;  Ctrl+Shift+K delete it, Ctrl+L pick it, Ctrl+Enter a line below, Tab /
;  Shift+Tab indent, Ctrl+Shift+[ / ] fold, Ctrl+Alt+[ / ] all, Ctrl+Shift+\
;  the matching bracket, Alt+Z wrap, Ctrl+wheel or Ctrl+= / - size, Ctrl+Z /
;  Ctrl+Y undo, Ctrl+S save.
; =============================================================================
class AxCodeEditor {
    static _reg := AxRich.Register("CodeEditor", "components\CodeEditor\AxCodeEditor.css", (*) => (
        AxRich.AddMethod("AddCodeEditor", (c, o := "", t := "") => AxCodeEditor._Add(c, o, t)),
        AxWindow.RegisterValue("codeeditor",
            (w, el) => AxCodeEditor._Val(w, el, unset),
            (w, el, v) => AxCodeEditor._Val(w, el, v))))
    static JsPath := "components\CodeEditor\AxCodeEditor.js"
    static Presets := Map(
        "ide",     {gutter: true, fold: true, suggest: true, status: true, minimap: true},
        "notes",   {lang: "md", wrap: true, gutter: false, status: false, suggest: false, currentLine: false},
        "log",     {readonly: true, gutter: true, fold: false, suggest: false, status: false, currentLine: false},
        "config",  {lang: "ini", suggest: false},
        "snippet", {status: false, fold: false})

    static _Val(win, el, value?) {
        c := AxRich.At(win, el.id)
        if !IsObject(c)
            return ""
        if IsSet(value)
            return c.Set(value)
        return c.Value
    }

    ; ------------------------------------------------------------- markup
    ; Before the page runs its script (and on the studio's canvas, where it
    ; never does) the editor shows its text plainly, with its line numbers.
    static Html(id, cfg, text := "") {
        E := (x) => AxWindow._Esc(x)
        text := StrReplace(StrReplace(String(text), "`r`n", "`n"), "`r", "`n")
        lines := "", nums := ""
        for i, one in StrSplit(text, "`n") {
            lines .= "<div>" (one = "" ? "<br>" : E(one)) "</div>"
            nums .= '<div class="axce-ln">' i "</div>"
        }
        o := (n, d := "") => cfg.HasOwnProp(n) ? cfg.%n% : d
        cls := "axce axce-t-" E(o("theme", "auto")) (o("wrap", false) ? " axce-wrap" : "")
             . (o("gutter", true) ? "" : " axce-nogut") (o("status", true) ? "" : " axce-nostat")
             . (o("class", "") != "" ? " " E(o("class")) : "")
        return '<div class="' cls '" id="' E(id) '" data-role="codeeditor" data-lang="' E(o("lang", "plain")) '"'
            . ' data-theme="' E(o("theme", "auto")) '" style="' E(o("style", "")) '">'
            . '<div class="axce-main"><div class="axce-gut" id="' E(id) '_gut">' nums '</div>'
            . '<div class="axce-scroll" id="' E(id) '_scroll"><div class="axce-under" id="' E(id) '_under"></div>'
            . '<div class="axce-ed" id="' E(id) '_ed" spellcheck="false"'
            . ' style="font-size:' o("fontSize", 13) 'px;line-height:' Round(o("fontSize", 13) * 1.5) 'px">' lines '</div></div></div>'
            . '<div class="axce-find" id="' E(id) '_find"><div class="axce-frow"><input id="' E(id) '_fq" placeholder="Find, or :line">'
            . '<span data-f="case" title="Match case">Aa</span><span data-f="prev" title="Previous">&#x2191;</span>'
            . '<span data-f="next" title="Next">&#x2193;</span><span class="axce-fn" id="' E(id) '_fn"></span>'
            . '<span data-f="x" title="Close">&#x2715;</span></div>'
            . '<div class="axce-frep"><input id="' E(id) '_fr" placeholder="Replace with">'
            . '<span data-f="one">Replace</span><span data-f="all">All</span></div></div>'
            . '<div class="axce-ac" id="' E(id) '_ac"></div><div class="axce-tip" id="' E(id) '_tip"></div>'
            . '<div class="axce-stat" id="' E(id) '_stat"></div>'
            . '<textarea class="axce-val" id="' E(id) '_val">' E(text) '</textarea>'
            . '<textarea class="axce-q" id="' E(id) '_q"></textarea><span class="axce-req" id="' E(id) '_req"></span></div>'
    }

    ; ----------------------------------------------------------- AxGui
    static _Add(container, opts, text) {
        o := container._Opt(opts, "code")
        f := o.Flags, kv := o.KV
        cfg := {}
        preset := kv.Has("preset") ? StrLower(kv["preset"]) : "ide"
        if AxCodeEditor.Presets.Has(preset)
            for k, v in AxCodeEditor.Presets[preset].OwnProps()
                cfg.%k% := v
        On(name) => f.Has(name) && f[name]
        for k, prop in Map("lang", "lang", "theme", "theme", "font", "font", "placeholder", "placeholder")
            if kv.Has(k)
                cfg.%prop% := kv[k]
        if kv.Has("fontsize")
            cfg.fontSize := Integer(kv["fontsize"])
        if On("wrap")
            cfg.wrap := true
        for word, prop in Map("nogutter", "gutter", "nofold", "fold", "nosuggest", "suggest", "nostatus", "status",
                              "nocurrentline", "currentLine", "nominimap", "minimap", "noguides", "guides")
            if On(word)
                cfg.%prop% := false
        if On("minimap")
            cfg.minimap := true
        if On("readonly")
            cfg.readonly := true
        if !cfg.HasOwnProp("lang")
            cfg.lang := "plain"
        h := (o.H != "") ? Integer(o.H) : 300
        cfg.style := "height:" h "px;" (o.W != "" ? "width:" o.W "px;" : "") (kv.Has("style") ? kv["style"] : "")
        cfg.class := ((o.W = "" || f.Has("fill")) ? "fill" : "") (kv.Has("class") ? " " kv["class"] : "")
        c := container._Reg(o, "CodeEditor", AxCodeEditor.Html(o.Id, cfg, text))
        container.G.OnReady((w) => AxCodeEditor(w, o.Id, cfg))
        return c
    }

    ; ======================================================== an editor
    __New(win, id, cfg) {
        this.W := win, this.Id := id, this.Cfg := cfg
        this._complete := [], this._hover := [], this._lint := [], this._save := [], this._caret := [], this._change := []
        this._ready := false
        AxRich.Use(win, "CodeEditor")
        AxRich.Bind(win, id, this)
        if !AxRich.UseJs(win, AxCodeEditor.JsPath)
            return
        try this.JS.make(id, AxJson.Stringify(cfg, ""))
        this._ready := true
        win.On("click", id "_req", (el, ev) => this._Ask())
    }
    JS => this.W.Doc.parentWindow.AXCE
    ; one call into the editor's page script; its answer as a string
    _Call(name, args*) {
        if !this._ready
            return ""
        try return this.JS.call(this.Id, name, AxJson.Stringify(args, ""))
        return ""
    }
    _Send(msg) {
        if this._ready
            try this.JS.recv(this.Id, AxJson.Stringify(msg, ""))
    }

    ; ------------------------------------------------------------- text
    Value {
        get => this._ready ? this._Call("value") : this.W.El(this.Id "_val").value
        set => this.Set(value)
    }
    Text => this.Value
    Set(text) => (this._Call("set", String(text)), this)
    Load(text) => (this._Call("load", String(text)), this)
    Insert(text) => (this._Call("insert", String(text)), this)
    Append(text, scroll := true) => (this._Call("append", String(text), scroll ? 1 : 0), this)
    Selected() => this._Call("selected")
    Select(a, b := "") => (this._Call("select", a, b = "" ? a : b), this)
    Caret() {
        r := this._Call("caret")
        return (r != "") ? AxJson.Parse(r) : Map("line", 1, "col", 1, "a", 0, "b", 0)
    }
    GoTo(line, col := 1) => (this._Call("goto", line, col), this)
    Focus() => (this._Call("focus"), this)
    Flush() => (this._Call("flush"), this)          ; what was typed, told now (OnChange)
    ; the services hear of it: the problems of the old language go, and the
    ; new one's are asked for
    SetLanguage(lang) {
        this.Cfg.lang := lang
        this._Call("option", "lang", lang)
        this._Call("marks", [])
        this._Call("touch")
        return this
    }
    SetTheme(name) => (this._Call("option", "theme", name), this)
    SetOption(name, value) => (this._Call("option", name, value), this)
    FoldAll(on := true) => (this._Call("fold", on ? 1 : 0), this)
    Undo() => (this._Call("undo"), this)
    Redo() => (this._Call("redo"), this)
    Find(text := "", replace := false) => (this._Call("find", text, replace ? 1 : 0), this)
    ReplaceAll(find, with := "", flags := "") => Integer(this._Call("replaceall", String(find), String(with), String(flags)) || 0)
    SetWords(list) => (this._Call("words", list), this)
    SetWordSet(name, list, lang := "") => (this._Call("wordset", name, list, lang), this)
    AddSnippets(list) => (this._Call("snippets", list), this)
    SetMarks(list) => (this._Call("marks", list), this)
    ClearMarks() => this.SetMarks([])
    AddLanguage(name, def) => (this._Call("lang", name, def), this)
    Symbols() {
        r := this._Call("symbols")
        return (r != "") ? AxJson.Parse(r) : []
    }
    LoadFile(path) {
        this.Load(FileRead(path, "UTF-8"))
        SplitPath(path, , , &ext)
        static byExt := Map("ahk", "ahk", "ah2", "ahk", "js", "js", "json", "json", "css", "css", "html", "html", "htm", "html",
            "xml", "xml", "ini", "ini", "md", "md", "ps1", "ps1", "py", "py", "sql", "sql", "txt", "plain")
        if byExt.Has(StrLower(ext))
            this.SetLanguage(byExt[StrLower(ext)])
        return this
    }
    SaveFile(path) {
        f := FileOpen(path, "w", "UTF-8")
        f.Write(this.Value)
        f.Close()
        return this
    }
    UseScript(path) => AxRich.UseJsFile(this.W, path)

    ; -------------------------------------------------------- services
    OnComplete(fn) => (this._complete.Push(fn), this.SetOption("remote", true), this)
    OnHover(fn) => (this._hover.Push(fn), this.SetOption("hover", true), this)
    ; a problem-finder is asked about the text as it is now, not only after
    ; the next change
    OnLint(fn) => (this._lint.Push(fn), this._Call("touch"), this)
    OnSave(fn) => (this._save.Push(fn), this)
    ; fn(text, ed) after the user changed the text: once the typing pauses, or
    ; at once when the editor loses the keyboard (not when code sets it)
    OnChange(fn) => (this._change.Push(fn), this)
    OnCaret(fn) => (this._caret.Push(fn), this.SetOption("caret", true), this)
    ; items for the request q, from a service that answers later
    Items(q, items) => this._Send(Map("kind", "items", "q", q, "items", AxCodeEditor._Items(items)))
    Hovered(q, text, html := false) => this._Send(Map("kind", "hover", "q", q, html ? "html" : "text", String(text)))
    UseAhk(opts := "") => AxCodeEditorAhk.Attach(this, opts)
    UseLsp(lsp, uri := "", langId := "") => AxLsp.Attach(lsp, this, uri, langId)

    ; strings or objects, as the page wants them
    static _Items(items) {
        out := []
        if !IsObject(items)
            return out
        for it in items {
            if !IsObject(it) {
                out.Push(Map("label", String(it)))
                continue
            }
            m := Map()
            for k, v in (it is Map ? it : it.OwnProps())
                m[StrLower(k)] := v
            out.Push(m)
        }
        return out
    }

    ; a request from the page: what it is, and who answers it
    _Ask() {
        raw := ""
        try raw := this.W.El(this.Id "_q").value
        if (raw = "")
            return
        m := ""
        try m := AxJson.Parse(raw)
        if !(m is Map)
            return
        kind := m.Get("kind", "")
        switch kind {
        case "change":
            ; set from here (Value :=, Load) the services hear of it, but not
            ; the Change handlers: a Gui's Edit does not fire when code sets it
            text := this.Value
            if !m.Get("quiet", 0) {
                try this.W._FireValue(this.W.El(this.Id), text)
                for fn in this._change.Clone()
                    try AxGuiCompat.CallFit(fn, [text, this])
            }
            for fn in this._lint.Clone() {
                r := ""
                try r := AxGuiCompat.CallFit(fn, [text, this])
                if IsObject(r)
                    this.SetMarks(r)
            }
        case "complete":
            ; the text only when a service asks for it: it is not sent each time
            req := {q: m.Get("q", 0), word: m.Get("word", ""), scope: m.Get("scope", ""),
                    line: m.Get("line", 1), col: m.Get("col", 1)}
            req.DefineProp("text", {get: (*) => this.Value})
            all := []
            for fn in this._complete.Clone() {
                r := ""
                try r := AxGuiCompat.CallFit(fn, [req, this])
                if IsObject(r)
                    for x in r
                        all.Push(x)
            }
            if all.Length
                this.Items(req.q, all)
        case "hover":
            for fn in this._hover.Clone() {
                r := ""
                try r := AxGuiCompat.CallFit(fn, [m.Get("word", ""), this, m.Get("q", 0), m.Get("line", 0), m.Get("col", 0)])
                if (r != "") {
                    this.Hovered(m.Get("q", 0), r, InStr(r, "<") && InStr(r, ">"))
                    break
                }
            }
        case "save":
            for fn in this._save.Clone()
                try AxGuiCompat.CallFit(fn, [this.Value, this])
        case "caret":
            for fn in this._caret.Clone()
                try AxGuiCompat.CallFit(fn, [m.Get("line", 1), m.Get("col", 1), this])
        }
    }
}
