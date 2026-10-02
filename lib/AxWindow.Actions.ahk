#Requires AutoHotkey v2.0
; =============================================================================
;  AxWindow.Actions.ahk — small buttons at the trailing end of a header.
;
;  Windows puts a section's own commands in one place: the right-hand end of
;  its header row. The About page's Copy button, a settings card's "..." menu,
;  a split button with a drop arrow, the copy button in the corner of a code
;  block -- every one of them is the same strip in the same spot, and only
;  what the buttons do changes. So the strip is the library's, and the buttons
;  are yours:
;
;      g.AddExpander("vspecs Icon=E7F4 Open", "Device specifications")
;      ...
;      win.Actions("specs", [
;          {Glyph: "E8C8", Text: "Copy", Copy: () => SpecsText()},
;          {Glyph: "E712", Tip: "More", Menu: [["Export...", Export], ["Refresh", Refresh]]}
;      ])
;
;  or chained on as the box is made: g.AddCard("vdisk", "Storage").Actions([...])
;  It may be called before Show(); the strip appears when the page does.
;
;  Where the strip goes is worked out from the host:
;    an expander     in its header, just before the chevron; a press on a
;                    button does not open or close the expander
;    a card / group  the top-right corner, level with the title
;    anything else   the top-right corner too (a code block, a picture)
;  opts.Place "inline" appends it to the host instead (a row of your own),
;  and opts.Reveal "hover" keeps it hidden until the pointer is over the host,
;  as a code block's copy button is.
;
;  ------------------------------------------------------------------- items
;  The title bar's item vocabulary (AxWindow.Titlebar.ahk), plus Copy:
;
;    Id        element id (generated when omitted)
;    Name      what OnAction is told (default: Text, else Tip, else Id)
;    Glyph     Segoe Fluent Icons codepoint        Text   a word beside it
;    Tip       tooltip                             Class  extra classes
;    Click     fn(id, win)
;    Menu      menu items (ContextMenu format), or fn() -> items. A plain
;              string entry ("As PDF") is reported to OnAction by that name.
;              With Click as well (or Split: true) it is a split button: the
;              face runs Click (or tells OnAction), the arrow opens the menu.
;    Popover   a Popover() spec: a panel of your own markup under the button
;    Copy      text, fn() -> text, or true for the box's own text: put on the
;              clipboard, and the button shows a tick for a moment
;    Toggle    a click flips On                    Primary  accent-coloured
;    On / Disabled / Hidden                        state, changeable later
;    "-"       a thin separator
;
;  One handler can answer for every button of a strip instead of a Click on
;  each -- which is what a designer generates, and what a rule listens to:
;
;      win.Actions("specs", items, {OnAction: (name, win) => ...})
;      g.AddCard("vdisk", "Storage").Actions(items).OnAction(fn)
;
;      win.Action("pin", {On: true})               ; change one, live
;      win.Action("pin")                           ; -> the item
;      win.Actions("specs", "")                    ; take the strip away
; =============================================================================
class AxWindowActions {
    static _reg := AxWindowActions._Seed()
    static _Seed() {
        AxWindow.RegisterClick("axact", (w, el, t, ev) => w._ActClick(el, t))
        return true
    }
    ; ----------------------------------------------------------------- build
    Actions(hostId, items := "", opts := "") {
        this._ActInit()
        if (items = "") {
            if this._acts.Has(hostId) {
                for it in this._acts[hostId].Items
                    this._ActForget(it)
                this._acts.Delete(hostId)
            }
            try (old := this._ActStrip(hostId)) && old.parentNode.removeChild(old)
            return this
        }
        o := (n, d) => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        if this._acts.Has(hostId)
            for it in this._acts[hostId].Items
                this._ActForget(it)
        list := []
        for spec in items {
            it := AxWindowActions.Norm(spec)
            it.Host := hostId
            list.Push(it)
            this._actItems[it.Id] := it
        }
        this._acts[hostId] := {Items: list, Place: StrLower(String(o("Place", "auto"))),
                               Reveal: StrLower(String(o("Reveal", "")))}
        if (o("OnAction", "") != "")
            this._actOn[hostId] := o("OnAction", "")
        this._ActRender()
        return this
    }
    ; OnAction(hostId, fn): fn(name, win) for every button of that strip, and
    ; for every plain-string entry of their menus
    OnAction(hostId, fn) {
        this._ActInit()
        this._actOn[hostId] := fn
        return this
    }
    ; Action(id) reads an item; Action(id, patch) changes it in place
    Action(id, patch := "") {
        if (!this.HasOwnProp("_actItems") || !this._actItems.Has(id))
            return (patch = "") ? "" : this
        it := this._actItems[id]
        if (patch = "")
            return it
        for k, v in (patch is Map ? patch : patch.OwnProps())
            it.%k% := v
        this._ActRedraw(it)
        this._ActPop(it)
        return this
    }
    ; --------------------------------------------- markup, with no window
    ; Also what a designer uses to draw a strip on a page it never shows.
    static Norm(spec) {
        static uid := 0
        d := {Id: "", Name: "", Glyph: "", Text: "", Tip: "", Class: "", Click: "", Menu: "", Popover: "",
              Copy: "", Split: false, Toggle: false, Primary: false, On: false, Disabled: false, Hidden: false,
              Sep: false, Host: ""}
        if IsObject(spec) {                             ; braces: a bare `for` would take the else as its own
            for k, v in (spec is Map ? spec : spec.OwnProps())
                d.%k% := v
        } else if (spec = "-")
            d.Sep := true
        else
            d.Text := String(spec)
        if (d.Id = "")
            d.Id := "axact" (++uid)
        if (d.Tip = "" && d.Text = "" && d.Copy != "")
            d.Tip := "Copy"
        if (d.Name = "")
            d.Name := d.Text != "" ? d.Text : d.Tip != "" ? d.Tip : d.Id
        return d
    }
    static ItemHtml(it) {
        E := (x) => AxWindow._Esc(x)
        if it.Sep
            return '<span class="ax-act-sep" id="' E(it.Id) '"></span>'
        split := it.Menu != "" && (it.Click != "" || it.Split)
        cls := "ax-act" (it.Text != "" ? " has-text" : "") (it.Glyph = "" ? " no-ico" : "")
             . (split ? " split" : it.Menu != "" ? " drop" : "") (it.Primary ? " primary" : "")
             . (it.On ? " on" : "") (it.Disabled ? " disabled" : "") (it.Class != "" ? " " it.Class : "")
        face := (it.Glyph != "" ? '<span class="ico ax-act-ico">&#x' E(it.Glyph) ';</span>' : "")
              . (it.Text != "" ? '<span class="ax-act-text">' E(it.Text) '</span>' : "")
        arrow := '<span class="ico ax-act-drop">&#xE70D;</span>'
        inner := split ? '<span class="ax-act-main">' face '</span><span class="ax-act-arrow">' arrow '</span>'
               : face (it.Menu != "" && it.Text != "" ? arrow : "")   ; a bare "..." needs no arrow
        return '<span class="' cls '" id="' E(it.Id) '" data-role="axact" data-act="' E(it.Id) '"'
             . (it.Tip != "" ? ' data-tip="' E(it.Tip) '"' : "")
             . (it.Hidden ? ' style="display:none"' : "") '>' inner '</span>'
    }
    ; Puts a strip of item markup into host, where Windows would put it
    static Place(host, hostId, itemsHtml, place := "auto", reveal := "") {
        strip := '<span class="ax-acts' (reveal = "hover" ? " reveal" : "") '" data-acts="' AxWindow._Esc(hostId) '">' itemsHtml '</span>'
        head := (place = "inline") ? "" : host.querySelector(".exp-header")
        if IsObject(head) {
            chev := head.querySelector(".chev")
            IsObject(chev) ? chev.insertAdjacentHTML("beforeBegin", strip) : head.insertAdjacentHTML("beforeEnd", strip)
        } else if (place = "inline") {
            host.insertAdjacentHTML("beforeEnd", strip)
        } else {
            host.insertAdjacentHTML("afterBegin", strip)
            AxWindow._SetClass(host.firstChild, "corner", true)
            AxWindow._SetClass(host, "has-acts", true)
        }
        if (reveal = "hover")
            AxWindow._SetClass(host, "acts-reveal", true)
    }
    ; ------------------------------------------------------------- internals
    _ActInit() {
        if !this.HasOwnProp("_acts")
            this._acts := Map(), this._actItems := Map(), this._actOn := Map(), this._actOpen := ""
    }
    _ActForget(it) {
        try this._actItems.Delete(it.Id)
        if (it.Popover != "")
            try this.Popover(it.Id, "")
    }
    _ActStrip(hostId) {
        host := this.El(hostId)
        if !IsObject(host)
            return ""
        all := host.getElementsByTagName("span")
        loop all.length {
            sp := all.item(A_Index - 1)
            if (AxWindow._Attr(sp, "data-acts") = hostId)
                return sp
        }
        return ""
    }
    ; Puts every strip whose host is in the page; a host on a page that is
    ; filled after the first paint gets its strip when that page arrives.
    _ActRender() {
        if !this.HasOwnProp("_acts")
            return
        try doc := this.Doc                             ; an AxGui has none until Show()
        catch
            return
        if !IsObject(doc)
            return
        for hostId, a in this._acts {
            hostEl := this.El(hostId)
            if !IsObject(hostEl)
                continue
            try (old := this._ActStrip(hostId)) && old.parentNode.removeChild(old)
            html := ""
            for it in a.Items
                html .= AxWindowActions.ItemHtml(it)
            try AxWindowActions.Place(hostEl, hostId, html, a.Place, a.Reveal)
            for it in a.Items
                this._ActPop(it)
        }
    }
    _ActPop(it) {
        if (it.Popover = "")
            return
        sp := it.Popover
        if (IsObject(sp) && !sp.HasOwnProp("Align"))
            sp.Align := "right"                         ; it sits on the right: drop leftwards
        this.Popover(it.Id, sp)
    }
    _ActRedraw(it) {
        if !this._actItems.Has(it.Id)
            return
        try {
            el := this.El(it.Id)
            if IsObject(el)
                el.outerHTML := AxWindowActions.ItemHtml(it)
        }
    }
    _ActClick(el, t) {
        id := AxWindow._Attr(t, "data-act")
        if (!this.HasOwnProp("_actItems") || !this._actItems.Has(id))
            return
        it := this._actItems[id]
        if (it.Disabled || it.Popover != "")            ; a popover opens itself (the dispatcher)
            return
        onArrow := !!this._ClosestClass(el, "ax-act-arrow")
        if it.Toggle
            this.Action(id, {On: !it.On}), t := this.El(id)
        if (it.Menu != "" && ((it.Click = "" && !it.Split) || onArrow)) {
            items := it.Menu
            if (IsObject(items) && HasMethod(items, "Call"))
                items := items()
            items := this._ActMenu(it, items)
            try {
                r := t.getBoundingClientRect()
                this.ShowMenu(items, r.left, r.bottom + 6)     ; clear of the button, as Windows' flyouts are
            } catch
                this.ShowMenu(items)
            this._actOpen := id
            try AxWindow._SetClass(t, "open", true)
            return
        }
        if (it.Copy != "") {
            text := it.Copy
            if (IsObject(text) && HasMethod(text, "Call"))
                text := text()
            else if (text = true)
                text := this._ActHostText(it.Host)
            try {                                       ; another program can be holding the clipboard
                A_Clipboard := String(text)
                this._ActFlash(it)
            }
        }
        if (it.Click != "") {
            f := it.Click
            try f(id, this)
        } else
            this._ActTell(it.Host, it.Name)
    }
    ; plain-string entries become items that report their own name
    _ActMenu(it, items) {
        if !(items is Array)
            return items
        out := []
        for x in items
            out.Push((!IsObject(x) && x != "-") ? [x, this._ActTeller(it.Host, x)] : x)
        return out
    }
    _ActTeller(hostId, name) => (*) => this._ActTell(hostId, name)
    _ActTell(hostId, name) {
        if !this._actOn.Has(hostId)
            return
        f := this._actOn[hostId]
        try f(name, this)
    }
    ; the box's own text, without the strip's: an expander's body, else the host
    _ActHostText(hostId) {
        try {
            hostEl := this.El(hostId)
            body := hostEl.querySelector(".exp-body")
            if IsObject(body)
                return Trim(body.innerText, " `t`r`n")
            text := hostEl.innerText
            strip := this._ActStrip(hostId)
            if IsObject(strip) && strip.innerText != ""
                text := StrReplace(text, strip.innerText, "", , , 1)
            return Trim(text, " `t`r`n")
        }
        return ""
    }
    ; the tick a copy button shows for a moment
    _ActFlash(it) {
        try {
            el := this.El(it.Id)
            ico := el.querySelector(".ax-act-ico")
            txt := el.querySelector(".ax-act-text")
            if IsObject(ico)
                ico.innerHTML := "&#xE73E;"
            if IsObject(txt)
                txt.innerText := "Copied"
            AxWindow._SetClass(el, "done", true)
        }
        SetTimer(() => this._ActRedraw(it), -1400)
    }
    ; the window's menu closed: drop the mark from the button that opened it
    _ActMenuClosed() {
        if (!this.HasOwnProp("_actOpen") || this._actOpen = "")
            return
        try AxWindow._SetClass(this.El(this._actOpen), "open", false)
        this._actOpen := ""
    }
}
