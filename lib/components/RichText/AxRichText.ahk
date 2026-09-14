#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
#Include %A_LineFile%\..\..\..\AxJson.ahk
; single-file exe: this component's stylesheet and script travel inside it
;@Ahk2Exe-AddResource %U_AxLib%\components\RichText\AxRichText.css, AX_COMPONENTS_RICHTEXT_AXRICHTEXT_CSS
;@Ahk2Exe-AddResource %U_AxLib%\components\RichText\AxRichText.js, AX_COMPONENTS_RICHTEXT_AXRICHTEXT_JS

; =============================================================================
;  AxRichText -- a rich text editor: bold, italic, headings, lists, alignment,
;  links, pictures, tables, colours -- what you see is what you get -- that
;  hands its text back as HTML, Markdown or plain text.
;
;      doc := g.AddRichText("vnotes h360 Tools=standard Format=md", "# Notes`n`nStart **here**.")
;      doc.OnEvent("Change", (ctl, value, *) => FileAppend(value, "notes.md"))
;
;  The text to begin with is HTML when it starts with "<", Markdown otherwise.
;
;  ---------------------------------------------------------------- options
;    Tools=minimal|standard|full|none, or a list: "bold,italic,|,ul,ol,|,table"
;    Format=html|md|text     what Value and Change give (html)
;    Paper                   a white page, whatever the window wears
;    ReadOnly  PastePlain  NoStatus  Placeholder="..."
;
;  The tools: bold italic underline strike code sub sup | h1 h2 h3 p pre quote |
;  ul ol indent outdent | left center right justify | link unlink image table hr |
;  color mark | clear | undo redo | find | source (the HTML itself) | save
;  In a table a small bar comes up over it (rowabove rowadd colleft coladd
;  rowdel coldel out tabledel -- Exec takes those names too); on a link, Edit
;  and Remove. As you type: "# " "- " "1. " "> " make headings, lists and
;  quotes, **bold** *italic* `code` ~~strike~~ what they say, "/" on an empty
;  line a menu of blocks, Ctrl+Enter out of a table or block, Ctrl+F find.
;
;  ------------------------------------------------------------- the words
;    ctl.Value            as Format says; setting it takes HTML or Markdown
;    GetHtml() / SetHtml(h)  GetMarkdown() / SetMarkdown(md)  GetText()
;                         (or Html / Markdown / Text on ctl.Component)
;    Insert(html)  InsertText(text)  InsertTable(rows, cols)
;    Exec(tool)           any tool above by its name ("bold", "h2", "table" ...)
;    Find(text?, replace?)  the find bar open, with that text
;    Clear()  Focus()  WordCount()  SetReadOnly(on)
;    LoadFile(path)       .md, .html or .txt       SaveHtml(path, title?)
;    SaveMarkdown(path)   OnSave(fn)  -- Ctrl+S, or the save tool
;    static MdToHtml(md)  the Markdown the editor reads, as HTML
; =============================================================================
class AxRichText {
    static _reg := AxRich.Register("RichText", "components\RichText\AxRichText.css", (*) => (
        AxRich.AddMethod("AddRichText", (c, o := "", t := "") => AxRichText._Add(c, o, t)),
        AxWindow.RegisterValue("richtext",
            (w, el) => AxRichText._Val(w, el, unset),
            (w, el, v) => AxRichText._Val(w, el, v))))
    static JsPath := "components\RichText\AxRichText.js"
    ; tool -> [face, title, class?]. A face is a letter or two, or a drawing:
    ; "svg:" and SVG path data on a 16x16 grid, drawn as a line in the text's
    ; colour ("|f" before a path fills it, "|b" is the colour bar under it).
    static Tools := Map(
        "bold", ["B", "Bold (Ctrl+B)", "t b"], "italic", ["I", "Italic (Ctrl+I)", "t it"], "underline", ["U", "Underline (Ctrl+U)", "t u"],
        "strike", ["S", "Strikethrough (Ctrl+Shift+X)", "t s"],
        "code", ["svg:M5.5 4.5 2 8l3.5 3.5M10.5 4.5 14 8l-3.5 3.5", "Code (Ctrl+``)"],
        "sub", ["x<sub>2</sub>", "Subscript", "t"], "sup", ["x<sup>2</sup>", "Superscript", "t"],
        "h1", ["H1", "Heading 1 (Ctrl+1, or # and a space)", "t h"], "h2", ["H2", "Heading 2 (Ctrl+2, or ##)", "t h"],
        "h3", ["H3", "Heading 3 (Ctrl+3, or ###)", "t h"],
        "p", ["svg:M8 13V3h4.5M11 3v10M8 3.2a2.6 2.6 0 0 0 0 5.2", "Plain text (Ctrl+0)"],
        "pre", ["svg:M1.5 3.5h13v9h-13zM5 6.5 3.5 8 5 9.5M7.5 10h3", "Code block (`````` and a space)"],
        "quote", ["svg:|fM3 12.5c0-3.6 1.2-6 3.8-7.3l.7 1.1C5.9 7.3 5.3 8.5 5.2 9.5H7v3zM9 12.5c0-3.6 1.2-6 3.8-7.3l.7 1.1c-1.6 1-2.2 2.2-2.3 3.2H13v3z", "Quote (> and a space)"],
        "ul", ["svg:M6 4h8.5M6 8h8.5M6 12h8.5|fM2.6 3.1a.9.9 0 1 1 0 1.8.9.9 0 1 1 0-1.8zM2.6 7.1a.9.9 0 1 1 0 1.8.9.9 0 1 1 0-1.8zM2.6 11.1a.9.9 0 1 1 0 1.8.9.9 0 1 1 0-1.8z", "Bulleted list (- and a space)"],
        "ol", ["svg:M6.5 4h8M6.5 8h8M6.5 12h8M2 2.8l1-.6V5.6M1.8 7c.3-.5 1.8-.5 1.8.4 0 .7-1.8 1.4-1.8 2.1h1.9M1.8 11h1.7l-.9 1c.8 0 1.2.3 1.2.9 0 .7-.9 1-1.9.7", "Numbered list (1. and a space)"],
        "indent", ["svg:M2 3h12M7 6.5h7M7 9.5h7M2 13h12M2 5.8 4.4 8 2 10.2", "Indent (Tab)"],
        "outdent", ["svg:M2 3h12M7 6.5h7M7 9.5h7M2 13h12M4.4 5.8 2 8l2.4 2.2", "Outdent (Shift+Tab)"],
        "left", ["svg:M2 3.5h12M2 6.5h8M2 9.5h12M2 12.5h8", "Align left (Ctrl+L)"],
        "center", ["svg:M2 3.5h12M4 6.5h8M2 9.5h12M4 12.5h8", "Centre (Ctrl+E)"],
        "right", ["svg:M2 3.5h12M6 6.5h8M2 9.5h12M6 12.5h8", "Align right (Ctrl+R)"],
        "justify", ["svg:M2 3.5h12M2 6.5h12M2 9.5h12M2 12.5h12", "Justify (Ctrl+J)"],
        "link", ["svg:M6.8 9.2l2.4-2.4M8.6 4.6l1.1-1.1a2.6 2.6 0 0 1 3.7 3.7l-1.1 1.1M7.4 11.4l-1.1 1.1a2.6 2.6 0 0 1-3.7-3.7l1.1-1.1", "Link (Ctrl+K)"],
        "unlink", ["svg:M8.6 4.6l1.1-1.1a2.6 2.6 0 0 1 3.7 3.7l-1.1 1.1M7.4 11.4l-1.1 1.1a2.6 2.6 0 0 1-3.7-3.7l1.1-1.1M2.5 2.5l11 11", "Remove the link"],
        "image", ["svg:M2 3h12v10H2zM2 11.2l3.5-3.4 3 2.9 2-1.9 3.5 3.2M10.6 5.4a.9.9 0 1 0 .01 0", "Picture"],
        "table", ["svg:M2 3h12v10H2zM2 6.5h12M2 9.8h12M6 3v10M10 3v10", "Table"],
        "hr", ["svg:M1.5 8h13M4.5 4.5h7M4.5 11.5h7", "Line (--- and Enter)"],
        "color", ["svg:M4.5 11 8 3l3.5 8M5.8 8.2h4.4|b", "Text colour"],
        "mark", ["svg:M9.8 2.8l3.4 3.4-5.6 5.6H4.2V8.4z|b", "Highlight"],
        "clear", ["svg:M3 3.5h8M7 3.5v7M9.8 9.8l3.7 3.7M13.5 9.8l-3.7 3.7", "Clear the formatting"],
        "undo", ["svg:M5.5 3.5 2.5 6.5l3 3M3 6.5h6.5a3.5 3.5 0 0 1 0 7H7", "Undo (Ctrl+Z)"],
        "redo", ["svg:M10.5 3.5l3 3-3 3M13 6.5H6.5a3.5 3.5 0 0 0 0 7H9", "Redo (Ctrl+Y)"],
        "find", ["svg:M6.8 2.5a4.3 4.3 0 1 1 0 8.6 4.3 4.3 0 1 1 0-8.6zM10 10l4 4", "Find and replace (Ctrl+F / Ctrl+H)"],
        "source", ["HTML", "The HTML itself", "t sm"],
        "save", ["svg:M2.5 2.5h9l2 2v9h-11zM5 2.5V6h5.5V2.5M4.5 13.5v-4h7v4", "Save (Ctrl+S)"],
        "rowadd", ["&#x2193; Row", "A row below"], "rowabove", ["&#x2191; Row", "A row above"],
        "coladd", ["&#x2192; Column", "A column to the right"], "colleft", ["&#x2190; Column", "A column to the left"],
        "rowdel", ["&#8722; Row", "This row gone"], "coldel", ["&#8722; Column", "This column gone"],
        "tabledel", ["Delete table", "This table gone"], "out", ["Text after", "Carry on under it (Ctrl+Enter)"])
    static Presets := Map(
        "minimal",  "bold,italic,underline,|,ul,ol,|,link",
        "standard", "bold,italic,underline,strike,|,h1,h2,h3,p,quote,|,ul,ol,|,left,center,right,|,link,table,|,clear,|,undo,redo,|,find",
        "full",     "bold,italic,underline,strike,code,sub,sup,|,h1,h2,h3,p,pre,quote,|,ul,ol,indent,outdent,|,left,center,right,justify,|,link,unlink,image,table,hr,|,color,mark,clear,|,undo,redo,|,find,source,save",
        "none",     "")
    ; a tool's face as markup
    static Face(d) {
        f := d[1]
        if (SubStr(f, 1, 4) != "svg:")
            return f
        out := "", bar := false
        for part in StrSplit(SubStr(f, 5), "|") {
            if (part = "")
                continue
            if (part = "b") {
                bar := true
                continue
            }
            fill := (SubStr(part, 1, 1) = "f")
            out .= '<path' (fill ? ' class="f"' : "") ' d="' (fill ? SubStr(part, 2) : part) '"/>'
        }
        if bar
            out .= '<rect class="bar" x="2" y="12.9" width="12" height="2.1" rx=".6"/>'
        return '<svg viewBox="0 0 16 16" width="16" height="16" focusable="false">' out '</svg>'
    }

    static _Val(win, el, value?) {
        c := AxRich.At(win, el.id)
        if !IsObject(c)
            return ""
        if IsSet(value)
            return c.SetValue(value)
        return c.Value
    }

    ; ------------------------------------------------------------- markup
    static Markup(id, cfg, content := "") {
        E := (x) => AxWindow._Esc(x)
        o := (n, d := "") => cfg.HasOwnProp(n) ? cfg.%n% : d
        list := o("tools", "standard")
        if AxRichText.Presets.Has(StrLower(list))
            list := AxRichText.Presets[StrLower(list)]
        bar := ""
        for t in StrSplit(list, ",", " ") {
            t := StrLower(t)
            if (t = "|") {
                bar .= "<i></i>"
                continue
            }
            if !AxRichText.Tools.Has(t)
                continue
            d := AxRichText.Tools[t]
            cls := (d.Length >= 3) ? d[3] : ""
            bar .= '<span data-cmd="' t '" title="' E(d[2]) '"' (cls != "" ? ' class="' cls '"' : "") '>' AxRichText.Face(d) '</span>'
        }
        html := AxRichText.ToHtml(content)
        cls := "axrt" (o("paper", false) ? " axrt-paper" : "") (o("status", true) ? "" : " axrt-nostat")
             . (o("class", "") != "" ? " " E(o("class")) : "")
        return '<div class="' cls '" id="' E(id) '" data-role="richtext" style="' E(o("style", "")) '">'
            . (bar != "" ? '<div class="axrt-bar" id="' E(id) '_bar">' bar '</div>' : "")
            . '<div class="axrt-doc" id="' E(id) '_doc" contenteditable="' (o("readonly", false) ? "false" : "true") '"'
            . ' spellcheck="' (o("spell", true) ? "true" : "false") '" data-ph="' E(o("placeholder", "")) '">' html '</div>'
            . '<textarea class="axrt-src" id="' E(id) '_src" spellcheck="false"></textarea>'
            . '<div class="axrt-stat" id="' E(id) '_stat"></div>'
            . '<div class="axrt-ask" id="' E(id) '_ask"><label></label><input type="text"><span data-ask="ok">OK</span><span data-ask="no">Cancel</span></div>'
            . '<div class="axrt-pal" id="' E(id) '_pal"></div>'
            . '<textarea class="axrt-val" id="' E(id) '_val"></textarea><textarea class="axrt-q" id="' E(id) '_q"></textarea>'
            . '<span class="axrt-req" id="' E(id) '_req"></span></div>'
    }
    ; HTML stays HTML; anything else is read as Markdown
    static ToHtml(content) {
        c := String(content)
        return RegExMatch(c, "^\s*<") ? c : AxRichText.MdToHtml(c)
    }

    ; ----------------------------------------------------------- AxGui
    static _Add(container, opts, content) {
        o := container._Opt(opts, "doc")
        f := o.Flags, kv := o.KV
        On(name) => f.Has(name) && f[name]
        cfg := {tools: kv.Has("tools") ? kv["tools"] : "standard", format: kv.Has("format") ? StrLower(kv["format"]) : "html"}
        if On("paper")
            cfg.paper := true
        if On("readonly")
            cfg.readonly := true
        if On("pasteplain")
            cfg.pastePlain := true
        if On("nostatus")
            cfg.status := false
        if On("nospell")
            cfg.spell := false
        if kv.Has("placeholder")
            cfg.placeholder := kv["placeholder"]
        h := (o.H != "") ? Integer(o.H) : 320
        cfg.style := "height:" h "px;" (o.W != "" ? "width:" o.W "px;" : "") (kv.Has("style") ? kv["style"] : "")
        cfg.class := ((o.W = "" || f.Has("fill")) ? "fill" : "") (kv.Has("class") ? " " kv["class"] : "")
        c := container._Reg(o, "RichText", AxRichText.Markup(o.Id, cfg, content))
        container.G.OnReady((w) => AxRichText(w, o.Id, cfg))
        return c
    }

    ; ========================================================= an editor
    __New(win, id, cfg) {
        this.W := win, this.Id := id, this.Cfg := cfg, this._save := [], this._ready := false
        AxRich.Use(win, "RichText")
        AxRich.Bind(win, id, this)
        if !AxRich.UseJs(win, AxRichText.JsPath)
            return
        try this.JS.make(id, AxJson.Stringify(cfg, ""))
        this._ready := true
        win.On("click", id "_req", (el, ev) => this._Ask())
    }
    JS => this.W.Doc.parentWindow.AXRT
    _Call(name, args*) {
        if !this._ready
            return ""
        try return this.JS.call(this.Id, name, AxJson.Stringify(args, ""))
        return ""
    }

    Value {
        get => this._Call("value")
        set => this.SetValue(value)
    }
    ; what the Format is: Markdown in a Markdown editor, HTML otherwise
    SetValue(v) {
        f := this.Cfg.HasOwnProp("format") ? this.Cfg.format : "html"
        if (f = "text")
            return this.SetHtml(StrReplace(StrReplace(AxWindow._Esc(String(v)), "`r", ""), "`n", "<br>"))
        this.SetHtml(AxRichText.ToHtml(v))
    }
    Html {
        get => this._Call("html")
        set => this._Call("sethtml", String(value))
    }
    Markdown {
        get => this._Call("md")
        set => this._Call("sethtml", AxRichText.MdToHtml(String(value)))
    }
    Text => this._Call("text")
    ; the same as methods: a property is not reached through the control
    ; (doc.GetMarkdown() works on it; doc.Markdown needs doc.Component)
    GetHtml() => this.Html
    SetHtml(h) => (this._Call("sethtml", String(h)), this)
    GetMarkdown() => this.Markdown
    SetMarkdown(md) => (this._Call("sethtml", AxRichText.MdToHtml(String(md))), this)
    GetText() => this.Text
    Insert(html) => (this._Call("insert", String(html)), this)
    InsertText(text) => this.Insert(StrReplace(AxWindow._Esc(String(text)), "`n", "<br>"))
    InsertTable(rows := 3, cols := 3) => (this._Call("table", rows, cols), this)
    Exec(tool) => (this._Call("exec", String(tool)), this)
    Find(text := "", replace := false) => (this._Call("find", String(text), replace ? 1 : 0), this)
    Native(cmd, value := "") => (this._Call("native", cmd, value), this)
    Clear() => (this.SetHtml(""), this)
    Focus() => (this._Call("focus"), this)
    WordCount() => Integer(this._Call("words") || 0)
    SetReadOnly(on := true) => (this._Call("readonly", on ? 1 : 0), this)
    OnSave(fn) => (this._save.Push(fn), this)
    LoadFile(path) {
        text := FileRead(path, "UTF-8")
        SplitPath(path, , , &ext)
        ext := StrLower(ext)
        if (ext = "html" || ext = "htm") {
            if RegExMatch(text, "is)<body[^>]*>(.*)</body>", &m)
                text := m[1]
            this.SetHtml(text)
        } else if (ext = "txt")
            this.SetHtml(StrReplace(AxWindow._Esc(text), "`n", "<br>"))
        else
            this.SetMarkdown(text)
        return this
    }
    SaveHtml(path, title := "") {
        f := FileOpen(path, "w", "UTF-8")
        f.Write('<!doctype html>`n<html><head><meta charset="utf-8"><title>' AxWindow._Esc(title) '</title>'
            . '<style>body{font:15px/1.6 "Segoe UI",sans-serif;max-width:820px;margin:32px auto;padding:0 16px}'
            . 'table{border-collapse:collapse}th,td{border:1px solid #bbb;padding:5px 9px}th{background:#f2f2f2}'
            . 'pre{background:#f4f4f4;padding:10px;border-radius:5px}code{background:#f0f0f0;padding:1px 4px;border-radius:3px}'
            . 'blockquote{border-left:3px solid #ccc;margin-left:0;padding-left:14px;color:#555}</style></head>`n<body>`n'
            . this.Html "`n</body></html>`n")
        f.Close()
        return this
    }
    SaveMarkdown(path) {
        f := FileOpen(path, "w", "UTF-8")
        f.Write(this.Markdown "`n")
        f.Close()
        return this
    }

    _Ask() {
        raw := ""
        try raw := this.W.El(this.Id "_q").value
        m := ""
        try m := AxJson.Parse(raw)
        if !(m is Map)
            return
        switch m.Get("kind", "") {
        case "change":
            try this.W._FireValue(this.W.El(this.Id), this.Value)
        case "save":
            for fn in this._save.Clone()
                try AxGuiCompat.CallFit(fn, [this.Value, this])
        }
    }

    ; ------------------------------------------------------- Markdown in
    ; What the editor reads: headings, bold, italic, strikes, code, links,
    ; pictures, lists (nested by two spaces), quotes, code blocks, lines,
    ; tables and paragraphs.
    static MdToHtml(md) {
        E := (x) => AxWindow._Esc(x)
        bt := Chr(96)
        Inline(s) {
            s := E(s)
            s := RegExReplace(s, bt "([^" bt "]+)" bt, "<code>$1</code>")
            s := RegExReplace(s, "!\[([^\]]*)\]\(([^)\s]+)\)", '<img src="$2" alt="$1">')
            s := RegExReplace(s, "\[([^\]]+)\]\(([^)\s]+)\)", '<a href="$2">$1</a>')
            s := RegExReplace(s, "\*\*([^*]+)\*\*", "<b>$1</b>")
            s := RegExReplace(s, "__([^_]+)__", "<b>$1</b>")
            s := RegExReplace(s, "(^|[^*])\*([^*]+)\*", "$1<i>$2</i>")
            s := RegExReplace(s, "~~([^~]+)~~", "<s>$1</s>")
            s := RegExReplace(s, "&lt;(/?u)&gt;", "<$1>")
            s := RegExReplace(s, " {2,}$", "<br>")
            return s
        }
        lines := StrSplit(StrReplace(String(md), "`r"), "`n")
        out := "", para := "", i := 0, n := lines.Length
        Flush() {
            if (para != "")
                out .= "<p>" Trim(para) "</p>"
            para := ""
        }
        while (++i <= n) {
            line := lines[i]
            if RegExMatch(line, "^\s*" bt bt bt) {                               ; a code block
                Flush()
                code := ""
                while (++i <= n && !RegExMatch(lines[i], "^\s*" bt bt bt))
                    code .= (code = "" ? "" : "`n") lines[i]
                out .= "<pre>" E(code) "</pre>"
                continue
            }
            if (Trim(line) = "") {
                Flush()
                continue
            }
            if RegExMatch(line, "^(#{1,6})\s+(.*?)\s*#*$", &m) {
                Flush()
                out .= "<h" StrLen(m[1]) ">" Inline(m[2]) "</h" StrLen(m[1]) ">"
                continue
            }
            if RegExMatch(line, "^\s*([-*_])(\s*\1){2,}\s*$") {
                Flush()
                out .= "<hr>"
                continue
            }
            if RegExMatch(line, "^\s*>\s?(.*)$", &m) {
                Flush()
                q := m[1]
                while (i < n && RegExMatch(lines[i + 1], "^\s*>\s?(.*)$", &m2))
                    q .= "`n" m2[1], i++
                out .= "<blockquote>" AxRichText.MdToHtml(q) "</blockquote>"
                continue
            }
            if (RegExMatch(line, "^\s*\|.*\|\s*$") && i < n && RegExMatch(lines[i + 1], "^\s*\|?\s*:?-{3,}")) {
                Flush()
                t := "<table><thead><tr>"
                for c in AxRichText._Cells(line)
                    t .= "<th>" Inline(c) "</th>"
                t .= "</tr></thead><tbody>"
                i++
                while (i < n && RegExMatch(lines[i + 1], "^\s*\|.*\|\s*$")) {
                    i++
                    t .= "<tr>"
                    for c in AxRichText._Cells(lines[i])
                        t .= "<td>" Inline(c) "</td>"
                    t .= "</tr>"
                }
                out .= t "</tbody></table>"
                continue
            }
            if RegExMatch(line, "^(\s*)([-*+]|\d+[.)])\s+", &m) {
                Flush()
                block := [line]
                while (i < n && (RegExMatch(lines[i + 1], "^\s*([-*+]|\d+[.)])\s+") || RegExMatch(lines[i + 1], "^\s{2,}\S")))
                    block.Push(lines[++i])
                out .= AxRichText._List(block, 1, Inline)
                continue
            }
            para .= (para = "" ? "" : " ") Inline(line)
        }
        Flush()
        return out
    }
    static _Cells(line) {
        out := []
        for c in StrSplit(Trim(Trim(line), "|"), "|")
            out.Push(Trim(c))
        return out
    }
    ; list lines, each "indent marker text", as nested lists
    static _List(block, from, Inline) {
        RegExMatch(block[from], "^(\s*)([-*+]|\d+[.)])", &m)
        base := StrLen(m[1]), tag := RegExMatch(m[2], "\d") ? "ol" : "ul"
        out := "<" tag ">", i := from
        while (i <= block.Length) {
            RegExMatch(block[i], "^(\s*)([-*+]|\d+[.)])?\s*(.*)$", &x)
            ind := StrLen(x[1])
            if (ind < base)
                break
            if (ind > base) {
                sub := [], j := i
                while (j <= block.Length && (RegExMatch(block[j], "^(\s*)", &y) && StrLen(y[1]) > base))
                    sub.Push(block[j]), j++
                out := RegExReplace(out, "</li>$", "") AxRichText._List(sub, 1, Inline) "</li>"
                i := j
                continue
            }
            out .= "<li>" Inline(x[3]) "</li>"
            i++
        }
        return out "</" tag ">"
    }
}
