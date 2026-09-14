#Requires AutoHotkey v2.0

; =============================================================================
;  AxTags.ahk -- the <ax-*> shorthand: markup generation only.
;
;  At load, AxWindow calls AxTags.ExpandHtml(html) on the page's text before
;  it is written, which replaces every <ax-*> element with the real markup a
;  theme styles and AxWindow's data-role behaviour drives -- the page is
;  parsed once, whole. AxTags.Expand(doc) does the same on a live document
;  (a page from a file, a designer's canvas), and is what ExpandHtml falls
;  back to when anything in the text is not as it expects. Hand-written
;  markup keeps working; the tags are shorthand.
;
;  This file owns the window's own furniture and nothing else:
;
;    <ax-nav pages="home:Home:E80F,settings:Settings:E713"></ax-nav>
;    <ax-content>
;      <ax-page id="home" title="Home"> ... </ax-page>
;    </ax-content>
;    <ax-menubar id="mb"></ax-menubar>   (fill it with win.MenuBar(id, menus))
;    <ax-status id="sb"></ax-status>     (fill it with win.StatusBar(id, parts))
;
;  Every control's tag belongs to the control. <ax-button> is rendered by
;  lib\components\Button\AxButton.ahk, which registers itself here:
;
;      AxTags.Register("ax-button", 11, (el, inner, id) => AxButton._Tag(...))
;
;  so this file does not know what controls exist, and adding one is adding a
;  folder. `order` only matters for a tag that consumes its own children --
;  <ax-tabs> eats its <ax-tab>s, so it has to go first.
;
;  Shared attributes: id, class (added to the root), style, tip (tooltip).
;  "options" attributes use  value:Label,value:Label  (or | as separator).
; =============================================================================
class AxTags {
    static Tags := ["ax-nav", "ax-content", "ax-page", "ax-menubar", "ax-status"]

    ; A component owns the markup of its own tag: it registers a renderer here
    ; and AxTags stops needing to know the control exists. `order` decides when
    ; the tag is expanded, which matters in exactly one place -- a tag that
    ; consumes its own children (<ax-tabs> eats its <ax-tab>s) has to go first.
    static Renderers := Map()            ; tag -> {Order, Fn}
    static Register(tag, order, fn) {
        AxTags.Renderers[StrLower(tag)] := {Order: order, Fn: fn}
        AxTags._order := ""              ; the expansion order is stale now
    }
    static _order := ""
    ; Every tag, window furniture and components together, in expansion order.
    static Order() {
        if IsObject(AxTags._order)
            return AxTags._order
        all := []
        for i, t in AxTags.Tags
            all.Push({T: t, O: i})
        for t, rec in AxTags.Renderers
            all.Push({T: t, O: 1000 + rec.Order})
        ; a plain insertion sort: this runs once, over a few dozen entries
        loop all.Length - 1 {
            i := A_Index + 1
            while (i > 1 && all[i - 1].O > all[i].O) {
                tmp := all[i - 1], all[i - 1] := all[i], all[i] := tmp
                i--
            }
        }
        out := []
        for x in all
            out.Push(x.T)
        return AxTags._order := out
    }

    ; The whole document. Everything happens in ExpandIn: a document and an
    ; element both answer getElementsByTagName and querySelector, so one
    ; implementation serves both -- and scoping it is what lets a designer
    ; expand markup in a corner of its own page without the #shell step below
    ; reaching out and rearranging the page it is running in.
    static Expand(doc) {
        root := doc
        try if IsObject(doc.body)
            root := doc.body
        return AxTags.ExpandIn(root)
    }
    static ExpandIn(root) {
        for tag in AxTags.Order() {
            coll := root.getElementsByTagName(tag)
            guard := 0
            while (coll.length > 0 && guard++ < 5000) {
                el := coll.item(0)
                try html := AxTags.Render(tag, el)
                catch as e
                    html := '<div style="color:#ff99a4">&lt;' tag '&gt;: ' AxTags.E(e.Message) '</div>'
                el.outerHTML := html
            }
        }
        AxTags.Shell(root)
    }

    ; ---------------------------------------------------- the page's text
    ; The same expansion, done on the markup before it is written, so the
    ; page is parsed once. Replacing each element in a live document made
    ; Trident parse and lay the page out again for every one of them: a
    ; window of three hundred controls spent most of two seconds doing it.
    ;
    ; Tag by tag in Expand's order, the first one each time, exactly as the
    ; live walk takes them; a renderer is handed an AxTagEl -- the element's
    ; attributes, its inner markup and text -- in place of the DOM's. It
    ; gives back "" when it meets anything it does not expect (a tag with no
    ; end, a renderer that asks for more than an AxTagEl has), and the page
    ; is then written as it was and expanded live instead.
    static ExpandHtml(html, inBody := false) {
        if !InStr(html, "<ax-")
            return html
        ; the body only, as the live walk takes it: nothing in the head
        if !inBody && (b := RegExMatch(html, "i)<body[\s>]")) {
            body := AxTags.ExpandHtml(SubStr(html, b), true)
            return (body = "") ? "" : SubStr(html, 1, b - 1) body
        }
        ; One sweep of the text per tag, what each became written after what
        ; came before it -- a splice into the whole text for every element
        ; copied the page three hundred times. A tag inside one of its own
        ; kind, or in what one became, is still there after the sweep, and
        ; the next sweep takes it: the outer first, as the live walk does.
        try {
            for tag in AxTags.Order() {
                sweeps := 0
                while InStr(html, "<" tag) && (sweeps++ < 50) {
                    out := "", at := 1, took := 0
                    loop {
                        f := AxTags._FindTag(&html, tag, at)
                        if !IsObject(f)
                            break
                        if (f = "bad")
                            return ""
                        out .= SubStr(html, at, f.S - at) AxTags.Render(tag, AxTagEl(tag, f.Attrs, f.Inner))
                        at := f.E, took++
                    }
                    if !took                   ; only <ax-tabs where <ax-tab was looked for
                        break
                    html := out SubStr(html, at)
                }
            }
        } catch
            return ""
        return html
    }
    ; The same, remembered: a page is the same text every time a program
    ; starts, so what it expanded to is kept in %TEMP%\AxGui and read back the
    ; next time instead of expanded again. The name is the page's own
    ; checksum (two CRC-32s and its length, taken in place -- no copy) and the
    ; library's: which tags are registered, and the newest file under lib (or
    ; the exe), so a change to any renderer is a new name. AxTags.Cache := false
    ; turns it off.
    static Cache := true
    static ExpandHtmlCached(html) {
        if !AxTags.Cache || !InStr(html, "<ax-")
            return AxTags.ExpandHtml(html)
        n := StrLen(html) * 2
        dir := A_Temp "\AxGui"
        f := dir "\tags_" Format("{:08x}{:08x}_{:x}_", AxTags._Crc(StrPtr(html), n, 0), AxTags._Crc(StrPtr(html), n, 0x9E3779B9), n)
           . AxTags.Version() ".html"
        if FileExist(f)
            try return FileRead(f, "UTF-8")
        out := AxTags.ExpandHtml(html)
        if (out != "") {
            try {
                DirCreate(dir)
                FileAppend(out, f ".tmp", "UTF-8-RAW")
                FileMove(f ".tmp", f, true)
                AxTags._Trim(dir, 40)
            }
        }
        return out
    }
    static _Crc(ptr, bytes, seed) => DllCall("ntdll\RtlComputeCrc32", "UInt", seed, "Ptr", ptr, "UInt", bytes, "UInt")
    ; what the library is, for the cache's names: worked out once per run
    static Version() {
        static v := ""
        if (v != "")
            return v
        newest := "0"
        if A_IsCompiled {
            try newest := FileGetTime(A_ScriptFullPath, "M")
        } else {
            loop files AxWindow.LibDir "*.ahk", "FR"
                if (A_LoopFileTimeModified > newest)
                    newest := A_LoopFileTimeModified
        }
        tags := ""
        for t in AxTags.Order()
            tags .= t "|"
        return v := newest "_" Format("{:08x}", AxTags._Crc(StrPtr(tags), StrLen(tags) * 2, 0))
    }
    ; the newest `keep` kept, the rest gone
    static _Trim(dir, keep) {
        list := []
        loop files dir "\tags_*.html"
            list.Push({P: A_LoopFileFullPath, T: A_LoopFileTimeModified})
        if (list.Length <= keep)
            return
        ; oldest first: a plain selection of the ones to drop
        loop list.Length - keep {
            oi := 1
            for i, x in list
                if (x.T < list[oi].T)
                    oi := i
            try FileDelete(list.RemoveAt(oi).P)
        }
    }
    ; The next <tag ...>...</tag> at or after `at`: {S, E, Attrs, Inner}, with
    ; E just past its end; "" when there is none, "bad" when its end is not
    ; there to be found.
    static _FindTag(&html, tag, at) {
        static openEnd := "SA)(?:[^>`"']++|`"[^`"]*+`"|'[^']*+')*+>"
        n := StrLen(tag)
        loop {
            p := InStr(html, "<" tag, false, at)
            if !p
                return ""
            c := SubStr(html, p + n + 1, 1)
            if (c = ">" || c = " " || c = "`t" || c = "`n" || c = "`r" || c = "/")
                break
            at := p + n + 1                    ; <ax-tabs when looking for <ax-tab
        }
        if !RegExMatch(html, openEnd, &m, p + n + 1)
            return "bad"
        head := SubStr(html, p + n + 1, m.Len - 1)
        innerS := p + n + 1 + m.Len
        ; its own end, past any of the same tag inside it
        depth := 1, q := innerS
        loop {
            c1 := InStr(html, "</" tag ">", false, q)
            if !c1
                return "bad"
            o1 := InStr(html, "<" tag, false, q)
            while (o1 && o1 < c1) {
                cc := SubStr(html, o1 + n + 1, 1)
                if (cc = ">" || cc = " " || cc = "`t" || cc = "`n" || cc = "`r" || cc = "/")
                    break
                o1 := InStr(html, "<" tag, false, o1 + n + 1)
            }
            if (o1 && o1 < c1) {
                depth++, q := o1 + n + 1
                continue
            }
            depth--
            if !depth
                return {S: p, E: c1 + n + 3, Attrs: AxTags._Attrs(head), Inner: SubStr(html, innerS, c1 - innerS)}
            q := c1 + n + 3
        }
    }
    ; ' id="a" class="b c" disabled' -> Map, names lower case, values as the
    ; DOM hands them back (entities undone)
    static _Attrs(head) {
        static re := "S)([^\s=/>`"']++)(?:\s*+=\s*+(?:`"([^`"]*+)`"|'([^']*+)'|([^\s>]++)))?"
        m := Map(), pos := 1
        while RegExMatch(head, re, &r, pos) {
            pos := r.Pos + r.Len
            v := (r.Len[2] || SubStr(r[0], -1) = '"') ? r[2] : (r.Len[3] || SubStr(r[0], -1) = "'") ? r[3] : r[4]
            name := StrLower(r[1])
            if !m.Has(name)
                m[name] := AxTags.Unent(v)
        }
        return m
    }
    static Unent(s) {
        if !InStr(s, "&")
            return s
        s := StrReplace(StrReplace(StrReplace(StrReplace(s, "&quot;", '"'), "&lt;", "<"), "&gt;", ">"), "&#39;", "'")
        s := StrReplace(s, "&apos;", "'"), s := StrReplace(s, "&nbsp;", Chr(160))
        while RegExMatch(s, "&#(x?)([0-9A-Fa-f]+);", &m)
            s := StrReplace(s, m[0], Chr(m[1] != "" ? Integer("0x" m[2]) : Integer(m[2])))
        return StrReplace(s, "&amp;", "&")
    }
    static Shell(root) {
        ; sidebar + content siblings -> wrap in #shell (win11.css layout). A
        ; page with no sidebar is wrapped too when its content asks (AxGui's
        ; windows do): #shell is what gives #content the window's height, so
        ; without it the status bar sat under the last control rather than at
        ; the bottom, and nothing could fill or scroll the height left.
        try {
            sb := root.querySelector("#sidebar"), ct := root.querySelector("#content")
            if (IsObject(ct) && !IsObject(root.querySelector("#shell"))
                && (IsObject(sb) || AxTags.A(ct, "data-shell") != "")) {
                first := IsObject(sb) ? sb : ct
                shell := first.ownerDocument.createElement("div")
                shell.id := "shell"
                first.parentNode.insertBefore(shell, first)
                if IsObject(sb)
                    shell.appendChild(sb)
                shell.appendChild(ct)
            }
        }
    }

    ; ------------------------------------------------------------ helpers
    static A(el, name, def := "") {
        try {
            v := el.getAttribute(name)
            if IsObject(v) || (v = "") || (v = "null")   ; Trident hands back "" for a missing attribute
                return def
            return v
        }
        return def
    }
    static Has(el, name) {
        try return el.hasAttribute(name) ? true : false
        return false
    }
    static E(s) => StrReplace(StrReplace(StrReplace(StrReplace(String(s), "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), '"', "&quot;")
    static Ico(glyph, cls := "ico") => (glyph != "" ? '<span class="' cls '">&#x' glyph ';</span>' : "")
    ; common attributes for the root element: id/class/style/tip (+ extra)
    ; JoinOptions(["a", ["b", "Bee"]]) -> "a:a|b:Bee"
    static JoinOptions(arr) {
        list := ""
        for it in arr {
            v := IsObject(it) ? it[1] : it, l := IsObject(it) ? it[2] : it
            list .= (list = "" ? "" : "|") StrReplace(v, "|", " ") ":" StrReplace(l, "|", " ")
        }
        return list
    }
    ; Runs for every component on the page, and each A() is a getAttribute --
    ; a COM round trip -- so every attribute is read exactly once here. It used
    ; to read each one twice: once to test it, once to use it.
    static Root(el, baseClass, withId := true, extra := "") {
        v := AxTags.A(el, "class")
        s := ' class="' baseClass (v != "" ? " " AxTags.E(v) : "") '"'
        if withId {
            v := AxTags.A(el, "id")
            if (v != "")
                s .= ' id="' AxTags.E(v) '"'
        }
        v := AxTags.A(el, "style")
        if (v != "")
            s .= ' style="' AxTags.E(v) '"'
        v := AxTags.A(el, "tip")
        if (v != "")
            s .= ' data-tip="' AxTags.E(v) '"'
        return s extra
    }
    ; "a:Alpha,b:Beta" -> [[value,label],...]   (| also accepted as separator)
    static Options(str) {
        out := []
        for part in StrSplit(str, InStr(str, "|") ? "|" : ",") {
            part := Trim(part)
            if (part = "")
                continue
            p := InStr(part, ":")
            out.Push(p ? [Trim(SubStr(part, 1, p - 1)), Trim(SubStr(part, p + 1))] : [part, part])
        }
        return out
    }
    static Inner(el) {
        try return el.innerHTML
        return ""
    }
    static Text(el) {
        try return Trim(el.innerText)
        return ""
    }

    ; ------------------------------------------------------------ renderer
    static Render(tag, el) {
        ; local shorthands (bound: a bare static method reference has no "this")
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        id := A(el, "id"), inner := AxTags.Inner(el)
        if AxTags.Renderers.Has(tag)
            return AxTags.Renderers[tag].Fn.Call(el, inner, id)
        switch tag {
        ; ---------------------------------------------------------- layout
        case "ax-nav":
            h := '<div id="sidebar"' (A(el, "style") != "" ? ' style="' E(A(el, "style")) '"' : "") '>'
            for o in AxTags.Options(A(el, "pages")) {
                ; value = pageId:Label:Glyph  (Options already split on the first colon)
                lab := o[2], glyph := ""
                p := InStr(lab, ":")
                if p
                    glyph := SubStr(lab, p + 1), lab := SubStr(lab, 1, p - 1)
                h .= '<div class="nav-item" data-page="' E(o[1]) '" id="nav_' E(o[1]) '">' Ico(glyph) E(lab) '</div>'
            }
            return h inner '</div>'
        case "ax-content":
            return '<div id="content"' (A(el, "style") != "" ? ' style="' E(A(el, "style")) '"' : "")
                 . (Has(el, "shell") ? ' data-shell="1"' : "") '>' inner '</div>'
        case "ax-page":
            ; "noheading" suppresses the <h1>. A page sitting under a nav does
            ; not caption itself with its own name -- the highlighted nav item
            ; already says it, and Windows does not put the name of the tab you
            ; just clicked at the top of the tab. AxGui adds the flag whenever
            ; there is a nav to carry the name; a page with no nav (a dialog,
            ; a single-page window) keeps its heading, because there is nothing
            ; else to name it.
            return '<div' Root(el, "page" (Has(el, "active") ? " visible" : "")
                              (Has(el, "noheading") ? " noheading" : "")) '>'
                . ((A(el, "title") != "" && !Has(el, "noheading"))
                   ? '<h1>' E(A(el, "title")) '</h1>' : "") inner '</div>'
        case "ax-menubar":
            ; "alt" starts it collapsed; MenuBar() takes it from there
            return '<div' Root(el, "axmb" (Has(el, "alt") ? " collapsed" : ""), true,
                    ' data-role="menubar"') '>' inner '</div>'
        case "ax-status":
            return '<div' Root(el, "axsb", true, ' data-role="statusbar"') '>' inner '</div>'
        }
        return inner
    }
}

; An element as a renderer sees it, for the page's text (AxTags.ExpandHtml):
; its attributes, its inner markup and text, and the few DOM calls a
; renderer makes. Anything else is not here, and asking for it throws --
; which sends the page back to the live expansion.
class AxTagEl {
    static _n := 0
    __New(tag, attrs, inner, parent := "") {
        this._tag := tag, this._a := attrs, this._inner := inner
        this.uniqueID := "axtagel" (++AxTagEl._n)
        this.parentNode := IsObject(parent) ? parent : {uniqueID: "axtagroot"}
    }
    getAttribute(name) => this._a.Has(StrLower(name)) ? this._a[StrLower(name)] : ""
    hasAttribute(name) => this._a.Has(StrLower(name))
    id => this.getAttribute("id")
    className => this.getAttribute("class")
    tagName => StrUpper(this._tag)
    innerHTML => this._inner
    innerText => AxTags.Unent(RegExReplace(RegExReplace(this._inner, "is)<(script|style)\b.*?</\1>"), "<[^>]*>"))
    ; <ax-tab>s: a tab of a tabs control inside this one belongs to that one
    getElementsByTagName(t) {
        t := StrLower(t), out := [], at := 1, html := this._inner
        while IsObject(f := AxTags._FindTag(&html, t, at)) {
            ; how many of this element's own kind are open before it
            before := SubStr(html, 1, f.S - 1), opens := 0, pos := 1
            while (pos := InStr(before, "<" this._tag, false, pos)) {
                c := SubStr(before, pos + StrLen(this._tag) + 1, 1)
                if (c = ">" || c = " " || c = "`t" || c = "`n" || c = "`r" || c = "/")
                    opens++
                pos += StrLen(this._tag) + 1
            }
            StrReplace(before, "</" this._tag ">", , false, &closes)
            out.Push(AxTagEl(t, f.Attrs, f.Inner, (opens - closes) ? "" : this))
            at := f.S + StrLen(t) + 1
        }
        return AxTagList(out)
    }
}
class AxTagList {
    __New(items) => this._i := items
    length => this._i.Length
    item(i) => this._i[i + 1]
}
