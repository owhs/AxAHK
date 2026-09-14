#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Tags\AxTagBox.css, AX_COMPONENTS_TAGS_AXTAGBOX_CSS

; =============================================================================
;  AxTagBox -- tags typed into a box: each becomes a chip with its own x.
;
;    t := g.AddTags('vLabels Suggest="bug|feature|docs|urgent" Clear', "bug|urgent")
;    t.OnChange((ctl, v, *) => Save(v))        ; v is "bug|urgent"
;    t.Add("docs")   t.Remove("bug")   t.Items   t.Value := "a|b"   t.Clear()
;
;  Enter or Tab makes a tag of what was typed, and so does any of the Split
;  characters (a comma unless told otherwise); Backspace in an empty box takes
;  the last one off. The same tag twice is one tag.
;
;    Split=", ;"          the characters that end a tag as you type. Words work
;    Split="comma space"  too: comma, space, semicolon, tab, pipe -- and
;                         Split=enter leaves Enter and Tab alone doing it.
;    PasteSplit="..."     what pasted text is cut at. By default the Split
;                         characters, commas, semicolons, tabs and new lines,
;                         so a pasted list, a column or a CSV line becomes one
;                         chip each. Text with none of them pastes as text.
;    Clear                a clear-all x at the end of the box
;    Suggest="a|b|c"      matches offered in a popover as you type (Down and
;                         Enter pick one); Strict takes only those
;    Max=N  Placeholder="..."
;
;  Double-click a chip to edit it in place: Enter or clicking away keeps the
;  change, Escape puts it back, and emptying it removes the tag. Ctrl+A in the
;  empty box selects every chip; then Ctrl+C copies them as "a, b, c", Ctrl+X
;  cuts them, and Delete or Backspace removes them all.
; =============================================================================
class AxTagBox {
    static _reg := AxRich.Register("Tags", "components\Tags\AxTagBox.css",
                                   (*) => AxTagBox._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddTags", (c, o := "", v := "") => AxTagBox._Add(c, o, v))
        AxWindow.RegisterValue("tagbox",
            (w, el) => AxWindow._Attr(el, "data-value"),
            (w, el, v) => AxTagBox._SetVia(w, el, v))
        return true
    }
    static _SetVia(win, el, v) {
        c := AxRich.At(win, el.id)
        if IsObject(c)
            c.Value := v
        else
            el.setAttribute("data-value", v)
    }
    static _Add(c, opts, value) {
        o := c._Opt(opts, "tags")
        F := (k) => (o.Flags.Has(k) && o.Flags[k])
        split := AxTagBox.Chars(c._Kv(o, "split", ","))
        cfg := {Placeholder: c._Kv(o, "placeholder", "Add a tag"), Max: Integer(c._Kv(o, "max", 0)),
                Suggest: AxTagBox.Split(c._Kv(o, "suggest", "")), Strict: F("strict"), ClearAll: F("clear"),
                Split: split,
                PasteSplit: o.KV.Has("pastesplit") ? AxTagBox.Chars(o.KV["pastesplit"]) : split ",;`t`r`n"}
        tags := AxTagBox.Split(value)
        if (o.W = "" && !o.Flags.Has("fill"))
            o.W := 320
        ctl := c._Reg(o, "Tags", AxTagBox.Html(o.Id, tags, cfg, c._Common(o, "")))
        c.G.OnReady((w) => AxTagBox(w, o.Id, tags, cfg))
        return ctl
    }
    ; "comma space" / ", ;" / "" -> the characters themselves
    static Chars(spec) {
        spec := String(spec)
        static words := Map("comma", ",", "space", " ", "semicolon", ";", "tab", "`t", "pipe", "|",
                            "newline", "`n", "enter", "")
        if RegExMatch(spec, "i)^\s*[a-z]+(?:[\s+,|]+[a-z]+)*\s*$") {
            out := ""
            for w in StrSplit(Trim(spec), [" ", "+", ",", "|"])
                if words.Has(StrLower(w))
                    out .= words[StrLower(w)]
            return out
        }
        return spec
    }
    ; a value: "a|b" is cut at the bars alone, so a tag may hold a comma; "a, b"
    ; (no bar in it) at the commas
    static Split(v) {
        out := [], seen := Map()
        seen.CaseSense := false
        v := IsObject(v) ? v : StrReplace(StrReplace(String(v), "`r"), "`n", "|")
        src := IsObject(v) ? v : StrSplit(v, InStr(v, "|") ? "|" : ",")
        for t in src {
            t := Trim(t)
            if (t != "" && !seen.Has(t))
                out.Push(t), seen[t] := true
        }
        return out
    }
    static Join(list) {
        s := ""
        for t in list
            s .= (s = "" ? "" : "|") t
        return s
    }
    static Html(id, tags, cfg, attrs := "") {
        E := (x) => AxWindow._Esc(x)
        cls := "axtags"
        if (attrs != "") {
            n := 0
            a := RegExReplace(attrs, 'S)class="([^"]*)"', 'class="' cls ' $1"', &n)
            if !n
                a .= ' class="' cls '"'
        } else
            a := ' id="' E(id) '" class="' cls '"'
        a := RegExReplace(a, 'S)class="axtags', 'class="axtags' (tags.Length ? " has" : ""), , 1)
        return '<div' a ' data-role="tagbox" data-value="' E(AxTagBox.Join(tags)) '">'
             . '<div class="axtags-w" id="' E(id) '_w"><span class="axtags-r" id="' E(id) '_r">' AxTagBox.Chips(id, tags) '</span>'
             . '<input type="text" class="axtags-in" id="' E(id) '_in" placeholder="' E(tags.Length ? "" : cfg.Placeholder) '" autocomplete="off" spellcheck="false">'
             . (IsObject(cfg) && cfg.HasOwnProp("ClearAll") && cfg.ClearAll
                ? '<span class="axtags-clr ico" id="' E(id) '_clr" data-tip="Clear all">&#xE711;</span>' : "")
             . '</div></div>'
    }
    ; the chips; the one at `edit` is drawn as a box to type in instead
    static Chips(id, tags, edit := 0) {
        E := (x) => AxWindow._Esc(x)
        h := ""
        for i, t in tags {
            if (i = edit) {
                h .= '<input type="text" class="axtags-ed" id="' E(id) '_ed" value="' E(t) '" style="width:'
                  .  AxTagBox.EdWidth(t) 'px" autocomplete="off" spellcheck="false">'
                continue
            }
            h .= '<span class="axtags-c" data-i="' i '">' E(t)
              .  '<span class="axtags-x ico" data-x="' E(t) '" data-tip="Remove">&#xE711;</span></span>'
        }
        return h
    }
    static EdWidth(t) => Max(56, Min(320, StrLen(t) * 7.5 + 26))

    __New(win, id, tags, cfg) {
        this.W := win, this.Id := id, this.Tags := tags, this.Cfg := cfg
        this._cbs := [], this._matches := [], this._hi := 0
        this._edit := 0, this._all := false
        AxRich.Bind(win, id, this)
        win.On("click", id "_w", (el, ev) => this._Click(ev))
        win.On("dblclick", id "_w", (el, ev) => this._DblClick(ev))
        win.On("keydown", id "_in", (el, ev) => this._Key(ev))
        win.On("keyup", id "_in", (el, ev) => this._Typed(ev))
        win.On("focusout", id "_in", (el, ev) => this._Blur())
        win.On("keydown", id "_ed", (el, ev) => this._EdKey(ev))
        win.On("keyup", id "_ed", (el, ev) => this._EdSize())
        win.On("focusout", id "_ed", (el, ev) => this._EdDone(true))
        ; typed characters and pastes are caught on the box itself: keypress
        ; carries the character (not the key), so a split character is found
        ; whatever the keyboard layout, and onpaste sees a paste from the menu
        ; as well as from Ctrl+V. Both answer Trident with a real VARIANT_BOOL.
        this._pressFn := (*) => this._Press()
        this._pasteFn := (*) => this._Paste()
        try {
            inp := win.El(id "_in")
            inp.attachEvent("onkeypress", this._pressFn)
            inp.attachEvent("onpaste", this._pasteFn)
        }
        if this.Cfg.Suggest.Length {
            win.Popover(id, {On: "none", Build: (*) => this._SuggestHtml(), Class: "axtags-pop", Align: "left", Gap: 4})
            win.On("mousedown", id "_sg", (el, ev) => this._Pick(ev))
        }
    }
    Items => this.Tags
    Value {
        get => AxTagBox.Join(this.Tags)
        set {
            this.Tags := AxTagBox.Split(value)
            this._Sync(false)
        }
    }
    OnChange(fn) {
        this._cbs.Push(fn)
        return this
    }
    Has(t) {
        for x in this.Tags
            if (x = Trim(t))
                return true
        return false
    }
    Add(t, fire := true) {
        t := this._Clean(t)
        if !this._Ok(&t)
            return false
        this.Tags.Push(t)
        this._Sync(fire)
        return true
    }
    ; several at once -- a paste, an edit that became two -- with one Change
    AddMany(list, at := 0, fire := true) {
        n := 0
        for t in list {
            t := this._Clean(t)
            if !this._Ok(&t)
                continue
            if at
                this.Tags.InsertAt(at + n, t)
            else
                this.Tags.Push(t)
            n++
        }
        if n
            this._Sync(fire)
        return n
    }
    ; a bar would split the value, and a split character could never be typed
    _Clean(t) {
        t := StrReplace(String(t), "|")
        loop parse this.Cfg.Split
            if (A_LoopField != " ")                 ; a space inside a tag is fine to keep
                t := StrReplace(t, A_LoopField)
        return Trim(t, " `t`r`n")
    }
    _Ok(&t) {
        if (t = "" || this.Has(t))
            return false
        if (this.Cfg.Max && this.Tags.Length >= this.Cfg.Max)
            return false
        if this.Cfg.Strict {
            ok := false
            for s in this.Cfg.Suggest
                if (s = t)
                    ok := true, t := s
            return ok
        }
        return true
    }
    ; text cut at the paste characters, in pieces worth keeping
    _Pieces(text) {
        out := []
        if (this.Cfg.PasteSplit = "")
            return (Trim(text, " `t`r`n") != "") ? [text] : out
        for p in StrSplit(text, StrSplit(this.Cfg.PasteSplit))
            if (Trim(p, " `t`r`n") != "")
                out.Push(p)
        return out
    }
    Remove(t, fire := true) {
        for i, x in this.Tags
            if (x = t) {
                this.Tags.RemoveAt(i)
                this._Sync(fire)
                return true
            }
        return false
    }
    Clear() {
        this.Tags := [], this._edit := 0, this._all := false
        return this._Sync(true)
    }
    ; every tag as one line of text, the way Ctrl+C copies them
    ToText(sep := ", ") {
        s := ""
        for t in this.Tags
            s .= (s = "" ? "" : sep) t
        return s
    }
    _Sync(fire) {
        w := this.W, id := this.Id
        if (this._edit > this.Tags.Length)
            this._edit := 0
        try {
            w.El(id "_r").innerHTML := AxTagBox.Chips(id, this.Tags, this._edit)
            w.El(id).setAttribute("data-value", this.Value)
            w.El(id "_in").placeholder := this.Tags.Length ? "" : this.Cfg.Placeholder
            AxWindow._SetClass(w.El(id), "full", this.Cfg.Max && this.Tags.Length >= this.Cfg.Max)
            AxWindow._SetClass(w.El(id), "has", this.Tags.Length > 0)
            AxWindow._SetClass(w.El(id), "allsel", this._all && this.Tags.Length > 0)
        }
        if fire {
            v := this.Value
            for fn in this._cbs.Clone()
                try fn(v, this)
            try w._FireValue(w.El(id), v)
        }
        return this
    }
    _Input() => this.W.El(this.Id "_in")
    _Click(ev) {
        try el := ev.srcElement
        catch
            return
        try {
            if (el.id = this.Id "_ed")                  ; a click inside the chip being edited
                return
            if (el.id = this.Id "_clr") {
                if this.Tags.Length
                    this.Clear()
                return this._Input().focus()
            }
        }
        this._SelectAll(false)
        x := AxWindow._Attr(el, "data-x")
        if (x = "")
            try x := AxWindow._Attr(AxWindow._ParentEl(el), "data-x")
        if (x != "")
            this.Remove(x)
        if !this._edit
            try this._Input().focus()
    }
    ; ------------------------------------------------ select every chip
    _SelectAll(on) {
        on := on && this.Tags.Length > 0
        if (on = this._all)
            return
        this._all := on
        try AxWindow._SetClass(this.W.El(this.Id), "allsel", on)
    }
    ; ----------------------------------------------- a chip edited in place
    _DblClick(ev) {
        try el := ev.srcElement
        catch
            return
        loop 3 {
            if !IsObject(el)
                return
            if (AxWindow._Attr(el, "data-x") != "")      ; the chip's own x
                return
            i := AxWindow._Attr(el, "data-i")
            if (i != "")
                return this.Edit(Integer(i))
            el := AxWindow._ParentEl(el)
        }
    }
    ; Edit(n) opens the n-th tag for typing, as a double-click does
    Edit(n) {
        if (n < 1 || n > this.Tags.Length)
            return this
        if this._edit
            this._EdDone(false)
        this._SelectAll(false)
        this._edit := n
        try this.W.ClosePopover()
        this._Sync(false)
        try {
            ed := this.W.El(this.Id "_ed")
            ed.focus()
            ed.select()
        }
        return this
    }
    _EdKey(ev) {
        try k := ev.keyCode
        catch
            return
        if (k = 13 || k = 9) {
            this._EdDone(true, true)
            try ev.returnValue := false
        } else if (k = 27) {
            this._EdDone(false, true)
            try ev.returnValue := false
            try ev.cancelBubble := true
        }
    }
    _EdSize() {
        try {
            ed := this.W.El(this.Id "_ed")
            ed.style.width := AxTagBox.EdWidth(ed.value) "px"
        }
    }
    ; keep (or throw away) what was typed into the chip; emptied, it goes
    _EdDone(keep, refocus := false) {
        n := this._edit
        if !n
            return
        text := ""
        try text := this.W.El(this.Id "_ed").value
        this._edit := 0
        old := this.Tags[n]
        if (!keep || Trim(text) = old) {
            this._Sync(false)
        } else {
            this.Tags.RemoveAt(n)
            pieces := this._Pieces(text)
            if !this.AddMany(pieces, n, true)
                this._Sync(true)                        ; emptied, or nothing in it would do
        }
        if refocus
            try this._Input().focus()
    }
    ; ------------------------------------------------- typing and pasting
    ; onkeypress: a split character ends the tag, and never reaches the box
    _Press() {
        allow := true
        try {
            ev := this.W.Doc.parentWindow.event
            ch := Chr(ev.keyCode)
            if (ev.keyCode >= 32)
                this._SelectAll(false)
            if (ev.keyCode >= 32 && this.Cfg.Split != "" && InStr(this.Cfg.Split, ch, true)) {
                inp := this._Input()
                if this.Add(inp.value)
                    inp.value := ""
                try this.W.ClosePopover()
                allow := false, ev.returnValue := false
            }
        }
        return ComValue(0xB, allow ? -1 : 0)
    }
    ; onpaste: text with a separator in it becomes chips; anything else is
    ; left for the box to paste as text
    _Paste() {
        allow := true
        try {
            clip := A_Clipboard
            cut := false
            loop parse this.Cfg.PasteSplit
                if InStr(clip, A_LoopField, true)
                    cut := true
            inp := this._Input()
            pieces := this._Pieces(inp.value clip)      ; what was typed runs on into the paste
            if (cut && pieces.Length) {
                this._SelectAll(false)
                this.AddMany(pieces)
                inp.value := ""
                try this.W.ClosePopover()
                allow := false
                try this.W.Doc.parentWindow.event.returnValue := false
            }
        }
        return ComValue(0xB, allow ? -1 : 0)
    }
    _Key(ev) {
        try k := ev.keyCode
        catch
            return
        inp := this._Input()
        t := inp.value
        ctrl := false
        try ctrl := ev.ctrlKey
        ; Ctrl+A in the empty box takes every chip; Ctrl+C / Ctrl+X copy them
        if (ctrl && k = 65 && t = "" && this.Tags.Length) {
            this._SelectAll(true)
            try ev.returnValue := false
            return
        }
        if this._all {
            if (ctrl && (k = 67 || k = 88)) {
                A_Clipboard := this.ToText()
                if (k = 88)
                    this.Clear()
                try ev.returnValue := false
                return
            }
            if (k = 8 || k = 46) {
                this.Clear()
                try ev.returnValue := false
                return
            }
            if (k = 27) {
                this._SelectAll(false)
                try ev.returnValue := false
                return
            }
            if !(k = 16 || k = 17 || k = 18)        ; a modifier on its own changes nothing
                this._SelectAll(false)
        }
        open := (this.W.PopoverOpen = this.Id)
        if (open && (k = 40 || k = 38) && this._matches.Length) {
            this._hi := Mod(this._hi - 1 + (k = 40 ? 1 : -1) + this._matches.Length, this._matches.Length) + 1
            this._Repaint()
            try ev.returnValue := false
            return
        }
        if (k = 13 || (k = 9 && Trim(t) != "")) {       ; the Split characters arrive in _Press
            pick := (open && this._hi) ? this._matches[this._hi] : t
            if (Trim(pick) != "") {
                if this.Add(pick)
                    inp.value := ""
                this.W.ClosePopover()
                try ev.returnValue := false
            }
        } else if (k = 8 && t = "" && this.Tags.Length) {
            this.Remove(this.Tags[this.Tags.Length])
        }
    }
    _Typed(ev) {
        try k := ev.keyCode
        catch
            return
        if (k = 13 || k = 188 || k = 38 || k = 40 || k = 27 || !this.Cfg.Suggest.Length)
            return
        t := Trim(this._Input().value)
        this._matches := []
        if (t != "")
            for s in this.Cfg.Suggest
                if (InStr(s, t) && !this.Has(s) && this._matches.Length < 8)
                    this._matches.Push(s)
        this._hi := this._matches.Length ? 1 : 0
        if this._matches.Length {
            if (this.W.PopoverOpen = this.Id)
                this._Repaint()
            else
                this.W.ShowPopover(this.Id)
        } else if (this.W.PopoverOpen = this.Id)
            this.W.ClosePopover()
    }
    _SuggestHtml() {
        E := (x) => AxWindow._Esc(x)
        h := '<div class="axtags-sg" id="' E(this.Id) '_sg">'
        for i, s in this._matches
            h .= '<div class="axtags-si' (i = this._hi ? " hi" : "") '" data-s="' E(s) '">' E(s) '</div>'
        return h '</div>'
    }
    _Repaint() {
        try this.W.El(this.Id "_sg").outerHTML := this._SuggestHtml()
    }
    _Pick(ev) {
        try el := ev.srcElement
        catch
            return
        s := AxWindow._Attr(el, "data-s")
        if (s = "")
            return
        if this.Add(s)
            this._Input().value := ""
        this.W.ClosePopover()
        try ev.returnValue := false
    }
    _Blur() {
        ; what was left typed becomes a tag, as a comma would have made it
        try t := Trim(this._Input().value)
        catch
            return
        this._SelectAll(false)
        if (t != "" && !this.Cfg.Strict && this.AddMany(this._Pieces(t)))
            this._Input().value := ""
    }
}
