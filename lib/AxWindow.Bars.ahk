#Requires AutoHotkey v2.0
; =============================================================================
;  AxWindow.Bars.ahk — the two standard window bars: the application menu bar
;  under the title bar, and the status bar along the bottom.
;
;      win.MenuBar("mb", [
;          {Title: "&File", Items: [["&New", fn], ["&Open…", fn], "-", ["E&xit", fn]]},
;          {Title: "&View", Items: [{Label: "Zoom in", Shortcut: "Ctrl++", Click: fn}]}],
;          {Reveal: "alt"})
;      win.StatusBar("sb", [{Id: "msg", Text: "Ready", Grow: true},
;                           {Id: "rows", Text: "0 rows", Width: 90},
;                           {Id: "pos",  Text: "Ln 1, Col 1"}])
;      win.Status("msg", "Saved")            ; update one part by id
;
;  Menu items are the same shape the context menus take, so a menu can be
;  shared between the bar and a right-click, and the drop-downs are the very
;  same overlay — one look for every menu in the window:
;
;      ["Label", fn]  |  "-"  |  {Label, Click, Shortcut, Disabled,
;                                 Checked, Radio, Icon, Items}
;
;  Checked draws a tick, Checked with Radio draws a bullet (so a menu can show
;  which option is current), Icon puts a glyph in the same gutter, and Items
;  makes the entry a submenu. A menu built by a function is re-read every time
;  it opens, which is how a "current" mark stays honest:
;
;      {Title: "&Theme", Items: () => [
;          {Label: "&Dark",  Radio: true, Checked: g.Theme = "dark",  Click: ...},
;          {Label: "&Light", Radio: true, Checked: g.Theme = "light", Click: ...}]}
;
;  Reveal: "always" (default) keeps the bar visible; "alt" collapses it until
;  Alt is tapped, the way Explorer does — the page really does take the space
;  back, and gives it up again while the bar is up. Leaving menu mode (Escape,
;  choosing an item, or the window losing focus) collapses it again.
;  ShowMenuBar(false) is the same thing spelled as a switch, so a "Show the
;  menu bar" menu item and Alt agree with each other.
;
;  Keyboard: Alt or F10 activates the bar and underlines the access keys
;  (the letter after & in a title), Alt+letter opens that menu directly,
;  Left/Right walk the titles, Down or Enter opens one, Escape leaves.
; =============================================================================
class AxWindowBars {
    ; ------------------------------------------------------------- menu bar
    ; MenuBar(id, menus, opts) binds an <ax-menubar> (or any empty element).
    ; menus: [{Title: "&File", Items: [...], Disabled: false}, ...]
    MenuBar(id, menus, opts := "") {
        o := (n, d := "") => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        this._mb := {Id: id, Menus: menus, Reveal: StrLower(String(o("Reveal", "always"))),
                     Open: 0, Cursor: 0, Active: false, Keys: false, Switching: false,
                     AutoHide: o("AutoHide", true)}
        this._mb.Shown := (this._mb.Reveal != "alt")
        this._RenderMenuBar()
        this._MbSync()
        if !this.HasOwnProp("_mbWired") {
            this._mbWired := true
            this.On("mousedown", id, (el, ev) => this._MbDown(ev))
            this.On("mouseover", id, (el, ev) => this._MbOver(ev))
        }
        return this
    }
    ; Replace the menus (or one of them) and redraw.
    SetMenus(menus) {
        if !this.HasOwnProp("_mb")
            return this
        this._mb.Menus := menus
        this._RenderMenuBar()
        return this
    }
    ; The "Show the menu bar" switch. Off collapses the bar out of the layout
    ; (the page grows into the space) and puts it in Alt-to-reveal mode; on
    ; brings it back for good. Alt uses _MbReveal for the temporary version.
    ShowMenuBar(on := true) {
        if !this.HasOwnProp("_mb")
            return this
        this._mb.Reveal := on ? "always" : "alt"
        this._MbReveal(on)
        return this
    }
    ; Put the bar in or out of the layout without changing what Reveal wants.
    _MbReveal(on) {
        mb := this._mb
        mb.Shown := on
        if !on {                                   ; step out in place: _MbActivate
            mb.Active := false                     ; would come straight back here
            mb.Keys := false
            mb.Open := 0
            this.BodyClass("axmb-keys", false)
            this._MbMark(0)
        }
        this._MbSync()
        return this
    }
    ; the bar's box, and the height #shell is allowed
    _MbSync() {
        mb := this._mb
        try AxWindow._SetClass(this.El(mb.Id), "collapsed", !mb.Shown)
        this.BodyClass("has-menubar", mb.Shown)
    }
    ; Shown is "on screen right now" (Alt may be holding it up); Pinned is the
    ; resting state, which is what a "Show the menu bar" tick should follow.
    MenuBarShown => this.HasOwnProp("_mb") && this._mb.Shown
    MenuBarPinned => this.HasOwnProp("_mb") && this._mb.Reveal = "always"
    _RenderMenuBar() {
        mb := this._mb
        h := ""
        for i, m in mb.Menus {
            title := IsObject(m) ? (m.HasOwnProp("Title") ? m.Title : "") : String(m)
            dis := IsObject(m) && m.HasOwnProp("Disabled") && m.Disabled
            h .= '<div class="axmb-item' (dis ? " disabled" : "") '" data-i="' i '" tabindex="-1">'
              .  AxWindowBars.AccessHtml(title) '</div>'
        }
        try {
            el := this.El(mb.Id)
            el.innerHTML := h
            AxWindow._SetClass(el, "collapsed", !mb.Shown)
        }
    }
    ; "&File" -> F underlined once the access keys are showing
    static AccessHtml(title) {
        s := "", i := 1
        while (i <= StrLen(title)) {
            c := SubStr(title, i, 1)
            if (c = "&" && i < StrLen(title)) {
                n := SubStr(title, i + 1, 1)
                if (n = "&")
                    s .= "&amp;", i += 2
                else
                    s .= '<span class="axmb-key">' AxWindow._Esc(n) '</span>', i += 2
                continue
            }
            s .= AxWindow._Esc(c), i++
        }
        return s
    }
    static AccessKey(title) {
        if RegExMatch(title, "&(?!&)(.)", &m)
            return StrLower(m[1])
        return ""
    }
    ; --- pointer
    _MbDown(ev) {
        it := this._MbItem(ev)
        if !it
            return
        i := Integer(AxWindow._Attr(it, "data-i"))
        if AxWindow._HasClass(it, "disabled")
            return
        if (this._mb.Open = i)
            return this._MbClose()
        this._MbOpen(i)
    }
    _MbOver(ev) {
        if !this._mb.Open
            return
        it := this._MbItem(ev)
        if !it
            return
        i := Integer(AxWindow._Attr(it, "data-i"))
        if (i != this._mb.Open && !AxWindow._HasClass(it, "disabled"))
            this._MbOpen(i)                       ; classic hover-to-switch
    }
    _MbItem(ev) {
        try el := ev.srcElement
        catch
            return ""
        return this._ClosestClass(el, "axmb-item")
    }
    _MbOpen(i) {
        mb := this._mb
        if (!mb.Menus.Has(i))
            return
        m := mb.Menus[i]
        items := IsObject(m) && m.HasOwnProp("Items") ? m.Items : []
        if (IsObject(items) && HasMethod(items, "Call"))   ; rebuilt on every open
            items := items()
        ; ShowMenu closes whatever was open first; that must not be read as the
        ; user leaving menu mode, so the swap is flagged while it happens
        mb.Switching := true
        try {
            r := this.Doc.querySelector("#" mb.Id " .axmb-item[data-i='" i "']").getBoundingClientRect()
            this.ShowMenu(items, r.left, r.bottom)
        } catch
            this.ShowMenu(items)
        mb.Switching := false
        mb.Open := i, mb.Cursor := i
        this._MbMark(i)
        this._MbActivate(true)
    }
    _MbClose() {
        if !this.HasOwnProp("_mb")
            return
        this._mb.Open := 0
        this._MbMark(0)
        this.CloseContextMenu()
    }
    _MbMark(i) {
        try {
            els := this.Doc.querySelectorAll("#" this._mb.Id " .axmb-item")
            loop els.length {
                AxWindow._SetClass(els.item(A_Index - 1), "open", A_Index = i)
                AxWindow._SetClass(els.item(A_Index - 1), "kb",
                    this._mb.Active && !this._mb.Open && A_Index = this._mb.Cursor)
            }
        }
    }
    ; the index of the menu whose access key is `ch`, or 0
    _MbByKey(ch) {
        for i, m in this._mb.Menus {
            t := IsObject(m) && m.HasOwnProp("Title") ? m.Title : String(m)
            dis := IsObject(m) && m.HasOwnProp("Disabled") && m.Disabled
            if (!dis && AxWindow.AccessKey(t) = ch)
                return i
        }
        return 0
    }
    ; the window lost focus: leave menu mode, and hide an Alt-revealed bar
    _MbBlur() {
        if !this.HasOwnProp("_mb")
            return
        if (this._mb.Reveal = "alt" && this._mb.AutoHide)
            this._MbReveal(false)
        else if this._mb.Active
            this._MbActivate(false)
    }
    ; --- keyboard
    ; Alt (or F10) turns the bar on, shows the access-key underlines and takes
    ; the arrow keys; Alt+letter jumps straight into a menu.
    _MbActivate(on) {
        if !this.HasOwnProp("_mb")
            return
        this._mb.Active := on
        this._mb.Keys := on
        this.BodyClass("axmb-keys", on)
        if on {
            if !this._mb.Cursor
                this._mb.Cursor := 1
            this._MbMark(this._mb.Open)
        } else {
            this._mb.Cursor := 0
            this._MbMark(0)
            if (this._mb.Reveal = "alt")             ; borrowed for the moment only
                this._MbReveal(false)
        }
    }
    ; called from the window subclass for WM_SYSKEYDOWN / WM_SYSKEYUP / F10
    _MenuKey(msg, vk) {
        if !this.HasOwnProp("_mb")
            return false
        mb := this._mb
        if !this.HasOwnProp("_altUsed")
            this._altUsed := false
        if (msg = 0x104) {                                   ; WM_SYSKEYDOWN
            if (vk = 18) {
                this._altUsed := false
                return true                                  ; swallow: no system-menu beep
            }
            key := StrLower(Chr(vk))
            this._altUsed := true
            i := this._MbByKey(key)
            if i {
                this._MbReveal(true)                         ; Alt+letter reveals and opens
                this._MbOpen(i)
                return true
            }
            return false
        }
        if (msg = 0x105 && vk = 18) {                        ; WM_SYSKEYUP: a bare Alt tap
            if this._altUsed
                return true
            if mb.Open {                                     ; a menu is up: put it away
                this._MbClose()
                this._MbActivate(false)
            } else if !mb.Shown {                            ; collapsed: borrow the space
                this._MbReveal(true)
                this._MbActivate(true)
            } else if mb.Active
                this._MbActivate(false)
            else
                this._MbActivate(true)
            return true
        }
        ; Once menu mode is up, the menu owns the keyboard: the keys are taken
        ; here rather than waiting for Trident to deliver a DOM keydown, which
        ; depends on where focus happens to be sitting.
        if (msg = 0x100 && vk != 121 && (mb.Active || this._ctxOpen)) {
            ev := {keyCode: vk}
            if (this._ctxOpen && this._CtxKey(ev))
                return true
            if this._MbKeyDown(ev)
                return true
            ; anything else menu mode would swallow anyway
            if (vk = 13 || vk = 27 || vk = 32 || (vk >= 33 && vk <= 40) || (vk >= 65 && vk <= 90))
                return true
            return false
        }
        if (msg = 0x100 && vk = 121) {                       ; F10, same as a bare Alt
            if mb.Active {
                this._MbClose()
                this._MbActivate(false)
            } else {
                this._MbReveal(true)
                this._MbActivate(true)
            }
            return true
        }
        return false
    }
    ; The keyboard while the bar is active. A menu that is open takes Up/Down,
    ; Enter and the item access keys first (see _CtxKey); what reaches here is
    ; the bar's own business: Left/Right between titles, Down to open, letters
    ; to pick a menu, Escape to leave.
    _MbKeyDown(ev) {
        if (!this.HasOwnProp("_mb") || !this._mb.Active)
            return false
        mb := this._mb, k := ev.keyCode, n := mb.Menus.Length
        if !n
            return false
        if !mb.Cursor
            mb.Cursor := 1
        if (k = 27) {                                        ; Escape
            if mb.Open
                this._MbClose()
            else
                this._MbActivate(false)
            return true
        }
        if (k = 37 || k = 39) {                              ; Left / Right
            at := mb.Cursor + ((k = 39) ? 1 : -1)
            at := (at < 1) ? n : (at > n) ? 1 : at
            mb.Cursor := at
            if mb.Open
                this._MbOpen(at)
            else
                this._MbMark(0)
            return true
        }
        if (k = 40 || k = 13 || k = 32) {                    ; Down / Enter / Space
            this._MbOpen(mb.Open ? mb.Open : mb.Cursor)
            return true
        }
        if (k >= 65 && k <= 90) {                            ; a letter picks a menu
            i := this._MbByKey(StrLower(Chr(k)))
            if i {
                this._MbOpen(i)
                return true
            }
            return true                                      ; swallow: menu mode owns letters
        }
        return false
    }

    ; ----------------------------------------------------------- status bar
    ; StatusBar(id, parts, opts) binds an <ax-status>.
    ; parts: [{Id, Text, Icon, Width, Grow, Align, Tip, Dim, Progress}]
    StatusBar(id, parts, opts := "") {
        o := (n, d := "") => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        this._sb := {Id: id, Parts: [], Grip: o("Grip", true)}
        this.SetStatusParts(parts)
        this.BodyClass("has-statusbar", true)
        if !this.HasOwnProp("_sbWired") {
            this._sbWired := true
            this.On("mousedown", id, (el, ev) => this._SbDown(ev))
            this.On("click", id, (el, ev) => this._SbClick(ev))
        }
        return this
    }
    SetStatusParts(parts) {
        if !this.HasOwnProp("_sb")
            return this
        sb := this._sb, sb.Parts := [], h := ""
        for i, p in parts {
            d := {Id: "", Text: "", Icon: "", Width: "", Grow: false, Align: "",
                  Tip: "", Dim: false, Click: "", Progress: ""}
            if IsObject(p)
                for k, v in (p is Map ? p : p.OwnProps())
                    d.%k% := v
            else
                d.Text := String(p)
            if (d.Id = "")
                d.Id := "p" i
            sb.Parts.Push(d)
            h .= '<div class="axsb-part' (d.Grow ? " grow" : "") (d.Align = "right" ? " right" : "")
              .  (d.Dim ? " dim" : "") (d.Click ? " action" : "") '" id="' AxWindow._Esc(sb.Id "_" d.Id) '"'
              .  ' data-p="' AxWindow._Esc(d.Id) '"'
              .  (d.Width != "" ? ' style="width:' d.Width 'px;flex:none"' : "")
              .  (d.Tip != "" ? ' data-tip="' AxWindow._Esc(d.Tip) '"' : "") '>'
              .  this._SbInner(d) '</div>'
        }
        if sb.Grip
            h .= '<div class="axsb-grip ico" id="' AxWindow._Esc(sb.Id "_grip") '">&#xE76F;</div>'
        try this.El(sb.Id).innerHTML := h
        return this
    }
    _SbInner(d) {
        s := (d.Icon != "") ? '<span class="ico">&#x' AxWindow._Esc(d.Icon) ';</span>' : ""
        if (d.Progress != "")
            return s '<span class="axsb-bar"><i style="width:' Round(d.Progress) '%"></i></span>'
        return s AxWindow._Esc(d.Text)
    }
    ; Status("msg", "Saved") — set one part's text by its id (or its index).
    Status(part, text := unset) {
        p := this._SbPart(part)
        if !p
            return this
        if !IsSet(text)
            return p.Text
        p.Text := text, p.Progress := ""
        try this.El(this._sb.Id "_" p.Id).innerHTML := this._SbInner(p)
        return this
    }
    ; StatusIcon("msg", "E930") — the glyph in front of the text ("" removes it)
    StatusIcon(part, glyph) {
        p := this._SbPart(part)
        if !p
            return this
        p.Icon := glyph
        try this.El(this._sb.Id "_" p.Id).innerHTML := this._SbInner(p)
        return this
    }
    ; StatusProgress("job", 45) — a slim bar inside the part; "" restores text
    StatusProgress(part, percent) {
        p := this._SbPart(part)
        if !p
            return this
        p.Progress := (percent = "") ? "" : Min(100, Max(0, percent))
        try this.El(this._sb.Id "_" p.Id).innerHTML := this._SbInner(p)
        return this
    }
    ShowStatusBar(on := true) {
        try this.El(this._sb.Id).style.display := on ? "flex" : "none"
        this.BodyClass("has-statusbar", on)
        return this
    }
    _SbPart(part) {
        if !this.HasOwnProp("_sb")
            return ""
        if (IsNumber(part) && this._sb.Parts.Has(Integer(part)))
            return this._sb.Parts[Integer(part)]
        for p in this._sb.Parts
            if (p.Id = part)
                return p
        return ""
    }
    _SbDown(ev) {
        try el := ev.srcElement
        catch
            return
        if (this._ClosestClass(el, "axsb-grip") && this.Resizable)
            this.Drag("SE")                        ; the grip is the SE resize handle
    }
    _SbClick(ev) {
        try el := ev.srcElement
        catch
            return
        hit := this._ClosestClass(el, "axsb-part")
        if !hit
            return
        p := this._SbPart(AxWindow._Attr(hit, "data-p"))
        if (p && p.Click) {
            fn := p.Click
            try fn(p.Id, this)
        }
    }
}
