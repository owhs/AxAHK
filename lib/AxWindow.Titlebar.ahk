#Requires AutoHotkey v2.0
; =============================================================================
;  AxWindow.Titlebar.ahk — things of your own in the window's title bar.
;
;  The injected frame keeps two empty slots, one after the app icon and one
;  before the caption buttons. TitleBar() fills them with items: a burger, a
;  glyph, a word, an SVG, a picture, a separator, a gap — anything. An item can
;  run a function, drop the window's own menu, or open a popover.
;
;      win.TitleBar([
;          {Id: "menu",  Kind: "burger", Tip: "Menu (Ctrl+B)", Click: (*) => Toggle()},
;          {Id: "brand", Kind: "text",   Text: "Notes"},
;          {Kind: "sep"},
;          {Id: "new",   Glyph: "E710",  Tip: "New note", Click: (*) => New()},
;          {Id: "acct",  Side: "right",  Svg: Avatar(), Popover: {Build: Card}}
;      ], {ShowTitle: false})
;
;  That is the whole idea: a window whose chrome is a burger, a name and an
;  avatar -- no icon, no caption text -- is a couple of lines, and so is a
;  conventional one with a single extra button.
;
;  ------------------------------------------------------------------- items
;  Every field is optional; Kind is worked out from whichever of Glyph, Svg,
;  Src, Html or Text is given.
;
;    Id        element id (generated when omitted)
;    Kind      "burger" | "glyph" | "text" | "html" | "svg" | "img" | "sep" | "spacer"
;    Side      "left" (default, after the icon) | "right" (before the buttons)
;    Glyph     Segoe Fluent Icons codepoint, e.g. "E700"
;    Text      plain text          Html/Svg   markup of your own
;    Src       image url or data: URI          Width  px
;    Tip       tooltip text        Class      extra classes on the item
;    Click     fn(id, win)         Menu       menu items, or fn() -> items
;    Popover   a Popover() spec (see AxWindow.Overlays.ahk)
;    Toggle    true: a click flips the item's "on" class before Click runs
;    Disabled / Hidden / On        state, all changeable later
;
;  Add "morph" to Class and a burger turns into a cross while it is on, which
;  is what a menu button should do and what a pane toggle should not.
;
;  ----------------------------------------------------------------- changing
;      win.TitleItem("menu", {On: true})           ; state, live
;      win.TitleItem("count", {Text: "3 open"})    ; content, live
;      win.TitleItem("find", {Kind: "html", Class: "axtb-search", Html: box})
;      win.TitleItem("menu")                       ; -> the item, to read it
;
;  Kind and Class can be patched too, so an item is free to change what it is
;  rather than only what it says -- a search button that opens into a search
;  box is the same item, told to become one.
;
;  A patch is applied to the element that is already there rather than by
;  rebuilding the bar, so a burger animates into its cross instead of jumping.
;
;  ------------------------------------------------------------------- layout
;  opts: ShowTitle (false hides the caption text -- a window whose name lives
;  somewhere else) and CenterTitle (true centres it across the whole bar
;  instead of leaving it beside the icon). Both are body classes, so a
;  stylesheet can honour them however it likes.
; =============================================================================
class AxWindowTitlebar {
    ; ----------------------------------------------------------------- build
    TitleBar(items := "", opts := "") {
        o := (n, d) => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        if IsObject(items) {
            this._tb := []
            for it in items
                this._tb.Push(this._TbNorm(it))
        }
        if IsObject(opts) {
            this._tbOpts := {ShowTitle: o("ShowTitle", true), CenterTitle: o("CenterTitle", false)}
            this.BodyClass("axtb-notitle", !this._tbOpts.ShowTitle)
            this.BodyClass("axtb-center", this._tbOpts.CenterTitle)
        }
        if IsObject(this.Doc)
            this._TbRender()
        return this
    }
    ; TitleItem(id) reads an item; TitleItem(id, patch) changes one in place.
    TitleItem(id, patch := "") {
        it := this._TbFind(id)
        if !it
            return (patch = "") ? "" : this
        if (patch = "")
            return it
        has := (k) => (patch is Map) ? patch.Has(k) : patch.HasOwnProp(k)
        wasCls := it.Class, wasKind := it.Kind
        for k, v in (patch is Map ? patch : patch.OwnProps())
            it.%k% := v
        try {
            el := this.El(it.Id)
            if !IsObject(el)
                return this
            AxWindow._SetClass(el, "on", it.On)
            AxWindow._SetClass(el, "disabled", it.Disabled)
            ; the classes are edited rather than rewritten wholesale: an item
            ; also carries state put there by the rest of the library (open,
            ; pop-open, pressed), and a fresh className would wipe it
            if (has("Kind") && it.Kind != wasKind) {
                AxWindow._SetClass(el, "kind-" wasKind, false)
                AxWindow._SetClass(el, "kind-" it.Kind, true)
            }
            if (has("Class") && it.Class != wasCls) {
                for c in StrSplit(Trim(wasCls), " ")
                    if (c != "")
                        AxWindow._SetClass(el, c, false)
                for c in StrSplit(Trim(it.Class), " ")
                    if (c != "")
                        AxWindow._SetClass(el, c, true)
            }
            el.style.display := it.Hidden ? "none" : ""
            if (has("Text") || has("Glyph") || has("Html") || has("Svg")
                || has("Src") || has("Kind"))
                el.innerHTML := this._TbInner(it)
            if has("Tip")
                (it.Tip = "") ? el.removeAttribute("data-tip") : el.setAttribute("data-tip", it.Tip)
            if has("Width")
                el.style.width := (it.Width = "") ? "" : it.Width "px"
        }
        return this
    }
    ; TitleOn("menu") — the toggle state of an item
    TitleOn(id) => (it := this._TbFind(id)) ? it.On : false
    ; ShowTitleBar(false) hides every item without forgetting them
    ShowTitleItems(on := true) {
        this.BodyClass("axtb-off", !on)
        return this
    }
    ; ---------------------------------------------------------------- internals
    _TbNorm(spec) {
        static uid := 0
        d := {Id: "", Kind: "", Side: "left", Text: "", Glyph: "", Html: "", Svg: "", Src: "",
              Tip: "", Class: "", Width: "", Click: "", Menu: "", Popover: "",
              Toggle: false, On: false, Disabled: false, Hidden: false}
        if IsObject(spec)
            for k, v in (spec is Map ? spec : spec.OwnProps())
                d.%k% := v
        else
            d.Text := String(spec)
        if (d.Kind = "")
            d.Kind := (d.Glyph != "") ? "glyph" : (d.Svg != "") ? "svg"
                    : (d.Src != "") ? "img" : (d.Html != "") ? "html" : "text"
        d.Side := (StrLower(String(d.Side)) = "right") ? "right" : "left"
        if (d.Id = "")
            d.Id := "axtb" (++uid)
        return d
    }
    _TbFind(id) {
        for it in this._tb
            if (it.Id = id)
                return it
        return ""
    }
    _TbInner(it) {
        switch it.Kind {
            case "burger": return '<span class="axtb-burger"><i></i><i></i><i></i></span>'
            case "glyph":  return '<span class="ico">&#x' AxWindow._Esc(it.Glyph) ';</span>'
            case "svg":    return '<span class="ax-svg">' it.Svg '</span>'
            case "img":    return '<img alt="" src="' AxWindow._Esc(it.Src) '">'
            case "html":   return it.Html
            case "sep", "spacer": return ""
            default:       return '<span class="axtb-text">' AxWindow._Esc(it.Text) '</span>'
        }
    }
    _TbHtml(it) {
        cls := "axtb-item kind-" it.Kind
        if (it.Class != "")
            cls .= " " it.Class
        if it.On
            cls .= " on"
        if it.Disabled
            cls .= " disabled"
        st := (it.Width != "" ? "width:" it.Width "px;" : "") (it.Hidden ? "display:none;" : "")
        return '<div class="' cls '" id="' AxWindow._Esc(it.Id) '" data-tb="' AxWindow._Esc(it.Id) '"'
            . (it.Tip != "" ? ' data-tip="' AxWindow._Esc(it.Tip) '"' : "")
            . (st != "" ? ' style="' st '"' : "")
            . '>' this._TbInner(it) '</div>'
    }
    ; Called once the frame exists, and again whenever the item list changes.
    ; Popovers are (re-)registered here so a declarative TitleBar() needs no
    ; second call to hook them up.
    _TbRender() {
        if (!IsObject(this.Doc) || !this._tb.Length)
            return
        L := "", R := ""
        for it in this._tb {
            if (it.Side = "right")
                R .= this._TbHtml(it)
            else
                L .= this._TbHtml(it)
        }
        try {
            el := this.El("axTbLeft")
            el.innerHTML := L
            AxWindow._SetClass(el, "has-items", L != "")
        }
        try {
            el := this.El("axTbRight")
            el.innerHTML := R
            AxWindow._SetClass(el, "has-items", R != "")
        }
        for it in this._tb {
            if (it.Popover = "")
                continue
            sp := it.Popover
            if (IsObject(sp) && !sp.HasOwnProp("Align") && it.Side = "right")
                sp.Align := "right"                    ; a right-hand item drops leftwards
            this.Popover(it.Id, sp)
        }
        if !this.HasOwnProp("_tbWired") {
            this._tbWired := true
            for slot in ["axTbLeft", "axTbRight"] {
                this.On("mousedown", slot, (el, ev) => this._TbDown(ev))
                this.On("click", slot, (el, ev) => this._TbClick(ev))
                this.On("dblclick", slot, (*) => "")   ; _TitlebarDown counts its own
            }
        }
        this.TitleAlign()
    }
    ; A burger first in a bar with no icon sits over the page rail's icons,
    ; the way a hand-made app lines them up (example\Todo.ahk). Measured
    ; rather than written into each stylesheet, since every sheet pads the
    ; bar and the rail differently. AxGui.NavMode() calls this again, because
    ; folding the rail moves its icons.
    TitleAlign() {
        if (!IsObject(this.Doc) || !this.HasOwnProp("_tb"))
            return this
        for it in this._tb
            if (it.Side = "left" && !it.Hidden) {
                if (it.Kind = "burger")
                    try AxWindowTitlebar.AlignBurger(this.El(it.Id), this.Doc.getElementById("axAppIcon"),
                        this.Doc.querySelector("#sidebar .nav-item .ico"))
                break
            }
        return this
    }
    ; el: the burger item. icon: the bar's own icon, if any -- the burger
    ; comes after it then, and is left where the sheet put it. ico: the first
    ; icon in the rail. Also what AxStudio calls for its canvas.
    static AlignBurger(el, icon, ico) {
        if !IsObject(el)
            return
        el.style.marginLeft := ""
        if (IsObject(icon) && icon.offsetWidth > 0) || !IsObject(ico) || !ico.offsetWidth
            return
        lines := el.querySelector(".axtb-burger")
        a := (IsObject(lines) ? lines : el).getBoundingClientRect()
        b := ico.getBoundingClientRect()
        try {                                   ; the glyph, not its box: a box can be wider
            r := ico.ownerDocument.body.createTextRange()
            r.moveToElementText(ico)
            b := r.getBoundingClientRect()
        }
        sc := el.offsetWidth ? (el.getBoundingClientRect().width / el.offsetWidth) : 1
        d := ((b.left + b.right) - (a.left + a.right)) / 2 / (sc ? sc : 1)
        if (Abs(d) < 0.5)
            return
        ml := 0
        try ml := RegExMatch(String(el.currentStyle.marginLeft), "-?[\d.]+", &m) ? Number(m[0]) : 0
        el.style.marginLeft := Round(ml + d, 1) "px"
    }
    ; A slot is often stretched across the whole bar -- a centred caption or a
    ; hidden one leaves it holding all the space -- so its empty part IS title
    ; bar and has to drag like it. Only a press that lands on an item is
    ; swallowed, the way the caption buttons swallow theirs; anything else is
    ; handed to the title bar, which counts its own double-clicks.
    ; An item that does nothing when pressed -- a gap, a separator, a name or a
    ; picture with no Click, Menu, Popover or Toggle -- is title bar too: a
    ; spacer stretches across the bar, and swallowing it left nothing to drag.
    _TbOnItem(ev) {
        try el := ev.srcElement
        catch
            return false
        hit := this._ClosestClass(el, "axtb-item")
        if !hit
            return false
        it := this._TbFind(AxWindow._Attr(hit, "data-tb"))
        if !it
            return true
        if (it.Kind = "spacer" || it.Kind = "sep")
            return false
        if (it.Kind = "html" || it.Click != "" || it.Menu != "" || it.Popover != "" || it.Toggle)
            return true
        return false
    }
    _TbDown(ev) {
        if !this._TbOnItem(ev)
            this._TitlebarDown(ev)
    }
    _TbClick(ev) {
        try el := ev.srcElement
        catch
            return
        hit := this._ClosestClass(el, "axtb-item")
        if !hit
            return
        it := this._TbFind(AxWindow._Attr(hit, "data-tb"))
        if (!it || it.Disabled)
            return
        if it.Toggle
            this.TitleItem(it.Id, {On: !it.On})
        if (it.Menu != "") {
            items := it.Menu
            if (IsObject(items) && HasMethod(items, "Call"))
                items := items()                       ; rebuilt every time it opens
            this._tbOpen := it.Id
            try {
                r := hit.getBoundingClientRect()
                this.ShowMenu(items, r.left, r.bottom + 2)
            } catch
                this.ShowMenu(items)
            try AxWindow._SetClass(hit, "open", true)
        }
        if (it.Click != "") {
            f := it.Click
            try f(it.Id, this)
        }
    }
    ; A control inside an item took or lost the focus. On the way out every
    ; item is cleared rather than the one under `el`: by then the control may
    ; already be detached, and a detached node's parent chain no longer reaches
    ; the item that used to hold it.
    _TbFocusMark(el, on) {
        if (!this.HasOwnProp("_tb") || !this._tb.Length)
            return
        if !on {
            for it in this._tb
                try AxWindow._SetClass(this.El(it.Id), "focus", false)
            return
        }
        hit := this._ClosestClass(el, "axtb-item")
        if hit
            try AxWindow._SetClass(hit, "focus", true)
    }
    ; the window's menu overlay closed: drop the mark from whichever item
    ; opened it (CloseContextMenu calls this, as it does for the menu bar)
    _TbMenuClosed() {
        if (!this.HasOwnProp("_tbOpen") || this._tbOpen = "")
            return
        try AxWindow._SetClass(this.El(this._tbOpen), "open", false)
        this._tbOpen := ""
    }
}
