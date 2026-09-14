#Requires AutoHotkey v2.0
; =============================================================================
;  AxWindow.Overlays.ahk — in-page overlays mixed into AxWindow:
;  context menus, modal dialogs (Alert/Confirm/Prompt/Dialog), toasts,
;  tooltips, the overlay markup injection, and Notify (Windows notifications
;  via AxSys.Toast).
;  Methods here run with `this` = the AxWindow instance.
; =============================================================================
class AxWindowOverlays {
    ; Tooltips: any element with a data-tip="..." attribute gets a styled
    ; tooltip on hover (see #axTip css). Tooltip(id, text) sets/clears it.
    Tooltip(id, text) {
        el := this.El(id)
        if !IsObject(el)
            return this
        if (text = "")
            el.removeAttribute("data-tip")
        else
            el.setAttribute("data-tip", text)
        return this
    }
    HideTooltip() {
        this._HideTip(true)
        return this
    }
    ; ---------------------------------------------------------- context menu
    ; ContextMenu(id, items)  id = element id, or "*" for the whole page.
    ;   items: array of  [label, fn]  |  "-"  |
    ;          {Label, Click, Shortcut, Disabled, Checked, Radio, Icon, Items}
    ;          |  a native AHK Menu object  |  a function that returns the
    ;          array, called each time the menu opens (so ticks are current)
    ;   fn receives (targetElement, event). Pass "" to remove a menu.
    ; Right-clicks with no menu registered are simply suppressed (unless
    ; opts.NativeContextMenu is true) and still reach On("contextmenu", ...).
    ContextMenu(id, items) {
        if (items = "")
            this._ctx.Delete(id)
        else
            this._ctx[id] := items
        return this
    }
    ; ShowMenu(items, x, y): open the page's context menu at a point, without
    ; waiting for a right-click. Same item format as ContextMenu; x and y are
    ; document CSS pixels, and omitting them uses the cursor. Handy for a
    ; toolbar button that drops the same menu a right-click would.
    ShowMenu(items, x := "", y := "", target := "") {
        if (items is Menu) {
            SetTimer(() => items.Show(), -1)
            return this
        }
        if (x = "") {
            pt := Buffer(8, 0)
            DllCall("GetCursorPos", "Ptr", pt)
            d := this._DocPoint(NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int"))
            x := d.X, y := d.Y
        }
        this.CloseContextMenu()
        this._ctxTarget := target
        this._OpenHtmlMenu(items, x, y)
        return this
    }
    CloseContextMenu() {
        this._BarMenuClosed()
        this._TbMenuClosed()
        SetTimer(this._ctxCloseFn, 0)
        this._CtxSwitchLater("", 0)
        this._ctxPin := "", this._ctxCloseLevel := 0
        if !this._ctxOpen
            return
        this._ctxOpen := false
        this._ctxItems := Map()
        this._CloseFrom(1)
        try this.El("axCtx").style.display := "none"
    }
    ; --------------------------------------------------------------- dialogs
    ; Dialog(text, title, buttons, opts) -> {Button, Value}   (blocks, modal)
    ;   buttons: array of labels, first = default/primary, e.g. ["Save","Cancel"]
    ;   opts: Kind ("info"|"question"|"warning"|"error"|"success"), Input (bool),
    ;         Default (initial input text), Placeholder, Danger (index of a red
    ;         button), Cancel (index returned on Escape; default = last button)
    Dialog(text, title := "", buttons := "", opts := "") {
        if !IsObject(this.Doc) || this._dlg
            return {Button: "", Value: ""}
        if !IsObject(buttons)
            buttons := ["OK"]
        if !IsObject(opts)
            opts := {}
        o := (n, d) => opts.HasOwnProp(n) ? opts.%n% : d
        this.CloseContextMenu()
        this._Unpress()
        d := this._dlg := {Done: false, Button: "", Value: "", Buttons: buttons,
                           Cancel: o("Cancel", buttons.Length), Input: o("Input", false), Sel: 1, Prev: ""}
        try d.Prev := this.Doc.activeElement           ; the keyboard goes back there afterwards
        this.El("axDlg").className := "kind-" o("Kind", "info")
        this.El("axDlgTitle").innerText := title
        this.El("axDlgTitle").style.display := (title = "" ? "none" : "block")
        this.El("axDlgText").innerText := text
        inp := this.El("axDlgInput")
        inp.style.display := d.Input ? "block" : "none"
        inp.value := o("Default", "")
        inp.placeholder := o("Placeholder", "")
        html := "", danger := o("Danger", 0)
        for i, label in buttons {
            cls := "axdlg-btn" (i = 1 ? " primary" : "") (i = danger ? " danger" : "")
            html .= '<div class="' cls '" id="axDlgBtn' i '" tabindex="0">' AxWindow._Esc(label) '</div>'
        }
        this.El("axDlgBtns").innerHTML := html
        this.El("axDlgOverlay").style.display := "block"
        ; The dialog has the keyboard: its box, or its first button -- not the
        ; editor behind it, where the arrow keys would go on moving the caret.
        ; Left/Right (and Tab) move between buttons; Enter or Space press the
        ; one picked (_DlgKey)
        if d.Input {
            try inp.focus()
        } else
            this._DlgFocus(1)
        while !d.Done && !this.Closing
            Sleep 20
        this._dlg := ""
        try this.El("axDlgOverlay").style.display := "none"
        if (!this.Closing && IsObject(d.Prev))
            try d.Prev.focus()
        return {Button: d.Button, Value: d.Value}
    }
    ; the button the keyboard is on: wraps round, marked "kb", and focused
    _DlgFocus(i) {
        d := this._dlg
        if !d
            return
        n := d.Buttons.Length
        d.Sel := Mod(i - 1 + n * 2, n) + 1
        loop n
            try AxWindow._SetClass(this.El("axDlgBtn" A_Index), "kb", A_Index = d.Sel)
        try this.El("axDlgBtn" d.Sel).focus()
    }
    ; Keys while a dialog is open. True when the key was the dialog's; every
    ; key but the box's own typing stops here, so none reaches the page behind.
    _DlgKey(ev) {
        d := this._dlg, k := ev.keyCode
        inBox := false
        try inBox := d.Input && this.Doc.activeElement.id = "axDlgInput"
        switch k {
        case 37, 38:                                    ; Left, Up
            if inBox
                return false
            this._DlgFocus(d.Sel - 1)
        case 39, 40:                                    ; Right, Down
            if inBox
                return false
            this._DlgFocus(d.Sel + 1)
        case 9:                                         ; Tab: through the box and the buttons
            shift := false
            try shift := ev.shiftKey
            if (inBox)
                this._DlgFocus(shift ? d.Buttons.Length : 1)
            else if (d.Input && ((shift && d.Sel = 1) || (!shift && d.Sel = d.Buttons.Length))) {
                loop d.Buttons.Length
                    try AxWindow._SetClass(this.El("axDlgBtn" A_Index), "kb", false)
                try this.El("axDlgInput").focus()
            } else
                this._DlgFocus(d.Sel + (shift ? -1 : 1))
        case 13:                                        ; Enter: the one picked (in the box: the first)
            this._EndDialog(inBox ? 1 : d.Sel)
        case 32:                                        ; Space presses a button, types in the box
            if inBox
                return false
            this._EndDialog(d.Sel)
        default:
            if inBox
                return false
        }
        return true
    }
    Alert(text, title := "", kind := "info") => this.Dialog(text, title, ["OK"], {Kind: kind})
    Confirm(text, title := "", yes := "Yes", no := "No", kind := "question") {
        r := this.Dialog(text, title, [yes, no], {Kind: kind})
        return r.Button = yes
    }
    Prompt(text, title := "", default := "", placeholder := "") {
        r := this.Dialog(text, title, ["OK", "Cancel"], {Input: true, Default: default, Placeholder: placeholder})
        return r.Button = "OK" ? r.Value : ""
    }
    _EndDialog(i) {
        d := this._dlg
        if !d || d.Done
            return
        try d.Value := this.El("axDlgInput").value
        d.Button := (i >= 1 && i <= d.Buttons.Length) ? d.Buttons[i] : ""
        d.Done := true
    }
    ; ------------------------------------------------------ native notification
    ; Notify(title, text, kind := "info", opts := "") — a Windows notification.
    ;   kind: "info" | "warning" | "error" | any lib\icons\<kind>.png | a png path | "silent" | "none"
    ;   text: "`n" starts a new line
    ;   opts: {Buttons: ["Open", "Later"], OnClick: fn(arg, label), OnDismiss: fn(reason), Silent, Scenario}
    ; With an AppName registered this is a real WinRT toast (app name, icon,
    ; buttons); otherwise it falls back to the tray balloon (no buttons).
    Notify(title, text := "", kind := "info", opts := "") {
        if (AxSys.Aumid != "") {
            o := {Title: title, Text: text, Image: AxSys.KindIconFile(kind), Silent: (kind = "silent")}
            if IsObject(opts)
                for k, v in opts.OwnProps()
                    o.%k% := v
            if AxSys.Toast(o)
                return this
        }
        static icons := Map("info", 1, "warning", 2, "error", 3, "none", 0)
        TrayTip(text, title, (kind = "silent") ? 1 | 16 : (icons.Has(kind) ? icons[kind] : 1))
        return this
    }
    static KindIconFile(kind) => AxSys.KindIconFile(kind)
    static IconToPngFile(hIcon, outPath) => AxSys.IconToPngFile(hIcon, outPath)
    ; ---------------------------------------------------------------- toast
    Toast(msg, ms := 2500, kind := "info") {
        if !IsObject(this.Doc)
            return this
        t := this.El("axToast")
        t.className := "kind-" kind
        t.innerText := msg
        t.style.display := "block"
        SetTimer(this._toastFn, -ms)
        return this
    }
    _HideToast() {
        try this.El("axToast").style.display := "none"
    }
    _InjectUI() {
        static css := AxWindow.ReadLib("themes\base.css")
        static html := AxWindow.ReadLib("ui\overlays.html")
        doc := this.Doc
        if IsObject(doc.getElementById("axCtx"))
            return
        try {
            head := doc.getElementsByTagName("head").item(0)
            s := doc.createElement("style")
            s.type := "text/css"
            head.insertBefore(s, head.firstChild)   ; first in <head> so page CSS can override
            AxWindow._SetStyleText(s, css)
        }
        doc.body.insertAdjacentHTML("beforeend", html)
    }
    ; attachEvent callback: must return VT_BOOL false to suppress IE's menu
    _CtxHandler() {
        allow := true
        try {
            ev := this.Doc.parentWindow.event
            if IsObject(ev) && !this.Closing
                allow := this._OnContextMenu(ev, ev.srcElement)
        }
        return ComValue(0xB, allow ? -1 : 0)
    }
    _OnContextMenu(ev, el) {
        this.CloseContextMenu()
        this._HideTip(true)
        if this._dlg {
            ev.returnValue := false
            return false
        }
        hit := this._Closest(el, (id) => this._ctx.Has(id))
        items := hit ? this._ctx[hit.id] : (this._ctx.Has("*") ? this._ctx["*"] : "")
        target := hit ? hit : el
        if (items = "") {
            if this.Hooks.Has("contextmenu") {
                h := this._Closest(el, (id) => this.Hooks["contextmenu"].Has(id))
                if h
                    this.Hooks["contextmenu"][h.id].Call(h, ev)
            }
            if this.NativeContextMenu
                return true
            ev.returnValue := false
            return false
        }
        ev.returnValue := false
        if (items is Menu) {
            SetTimer(() => items.Show(), -1)        ; let the event finish first
            return false
        }
        this._ctxTarget := target
        this._OpenHtmlMenu(items, ev.clientX, ev.clientY)
        return false
    }
    ; Draw one menu panel. Level 1 is #axCtx (injected with the overlays);
    ; deeper levels get panels of their own, so a submenu is just this again
    ; one level down and every level looks identical.
    _OpenHtmlMenu(items, x, y, level := 1, parentId := "") {
        if !(items is Array) && HasMethod(items, "Call")
            items := items()                   ; built as it opens
        m := this._MenuPanel(level)
        this._CloseFrom(level + 1)
        ; A sibling's submenu replacing this level's panel reuses the panel, so
        ; the entry for what it replaces has to go too. It used to stay: two
        ; entries for one panel, and hovering an item in the new one read as
        ; "something deeper is open", whose close hid the panel under the
        ; pointer. Popped without _CloseFrom, which would hide the panel being
        ; reused and drop the pin of the click that is opening it.
        if (level > 1 && this.HasOwnProp("_ctxLevels"))
            while (this._ctxLevels.Length >= level)
                this._ctxLevels.Pop()
        if (level = 1) {
            this._ctxItems := Map()
            this._ctxLevels := []
            this._ctxSeq := 0
        }
        html := "", list := [], marks := false
        for it in items {
            if (it = "-") {
                html .= '<div class="axctx-sep"></div>'
                continue
            }
            if (it is Array) {
                label := it[1], fn := it.Length >= 2 ? it[2] : "", sc := "", dis := false
                checked := false, radio := false, icon := "", sub := ""
            } else {
                label := it.Label
                fn      := it.HasOwnProp("Click") ? it.Click : ""
                sc      := it.HasOwnProp("Shortcut") ? it.Shortcut : ""
                dis     := it.HasOwnProp("Disabled") ? it.Disabled : false
                checked := it.HasOwnProp("Checked") ? it.Checked : false
                radio   := it.HasOwnProp("Radio") ? it.Radio : false
                icon    := it.HasOwnProp("Icon") ? it.Icon : ""
                sub     := it.HasOwnProp("Items") ? it.Items : ""
            }
            id := "axCtxI" (++this._ctxSeq)
            rec := {Id: id, Fn: dis ? "" : fn, Disabled: dis, Sub: sub, Level: level,
                    Key: AxWindow.AccessKey(label), Index: list.Length + 1}
            list.Push(rec)
            this._ctxItems[id] := rec
            mark := ""
            if (checked && radio)
                mark := '<span class="axctx-mark radio">&#x25CF;</span>', marks := true
            else if checked
                mark := '<span class="axctx-mark">&#xE73E;</span>', marks := true
            else if (icon != "")
                mark := '<span class="axctx-mark">&#x' icon ';</span>', marks := true
            else
                mark := '<span class="axctx-mark"></span>'
            html .= '<div class="axctx-item' (dis ? " disabled" : "") (checked ? " checked" : "")
                  . (IsObject(sub) ? " hassub" : "") '" id="' id '">' mark
                  . '<span class="axctx-label">' AxWindow.AccessHtml(label) '</span>'
                  . (IsObject(sub) ? '<span class="axctx-sub">&#xE76C;</span>'
                     : sc != "" ? '<span class="axctx-kbd">' AxWindow._Esc(sc) '</span>' : "")
                  . '</div>'
        }
        m.className := "axctx" (marks ? " hasmarks" : "") (level > 1 ? " sub" : "")
        m.innerHTML := html
        m.style.left := "0px", m.style.top := "0px"
        m.style.display := "block"
        vw := this.Doc.documentElement.clientWidth, vh := this.Doc.documentElement.clientHeight
        mw := m.offsetWidth, mh := m.offsetHeight
        if (x + mw > vw - 4)
            x := (level > 1) ? Max(4, x - mw - this._ctxParentW) : Max(4, vw - mw - 4)
        if (y + mh > vh - 4)
            y := Max(4, vh - mh - 4)
        m.style.left := Round(x) "px", m.style.top := Round(y) "px"
        this._ctxLevels.Push({Id: m.id, List: list, Cursor: 0, ParentId: parentId})
        this._ctxOpen := true
    }
    _MenuPanel(level) {
        id := (level = 1) ? "axCtx" : "axCtx" level
        el := this.El(id)
        if !IsObject(el) {
            this.Doc.body.insertAdjacentHTML("beforeend", '<div id="' id '" class="axctx"></div>')
            el := this.El(id)
        }
        return el
    }
    ; hide every panel from `level` down
    _CloseFrom(level) {
        if !this.HasOwnProp("_ctxLevels")
            return
        ; a pin only means anything while the panel it pinned is up
        if (this._ctxPin != "" && level <= this._ctxPinLevel + 1)
            this._ctxPin := ""

        while (this._ctxLevels.Length >= level) {
            lv := this._ctxLevels.Pop()
            try this.El(lv.Id).style.display := "none"
        }
    }
    _InAnyMenu(el) {
        if !this.HasOwnProp("_ctxLevels")
            return this._IsInside(el, "axCtx")
        for lv in this._ctxLevels
            if this._IsInside(el, lv.Id)
                return true
        return false
    }
    ; a click on an item: open its submenu, or run it and close everything
    _CtxClick(id, ev) {
        if !this._ctxItems.Has(id)
            return
        rec := this._ctxItems[id]
        if rec.Disabled
            return
        if IsObject(rec.Sub) {
            ; A click on a parent pins its submenu: hovering away no longer
            ; takes it down, so it can be read at leisure or walked into from
            ; any direction. Clicking the same parent again puts it away.
            if (this._ctxPin = rec.Id) {
                this._ctxPin := ""
                this._CloseFrom(rec.Level + 1)
                return
            }
            this._ctxPin := rec.Id, this._ctxPinLevel := rec.Level
            this._CtxOpenSub(rec)
            return
        }
        fn := rec.Fn, tgt := this._ctxTarget
        this.CloseContextMenu()
        if fn
            fn(tgt, ev)
    }
    ; focus: true puts the keyboard cursor on the new level's first item, which
    ; is what Right or Enter should do; the mouse leaves it alone
    _CtxOpenSub(rec, focus := false) {
        if (this._ctxPin != "" && this._ctxPin != rec.Id)
            this._ctxPin := ""                       ; a different parent wins
        SetTimer(this._ctxCloseFn, 0)
        try {
            el := this.El(rec.Id)
            r := el.getBoundingClientRect()
            this._ctxParentW := r.right - r.left
            this._CtxCursorAt(rec.Level, rec.Index)
            sub := rec.Sub
            if HasMethod(sub, "Call")                    ; built fresh on every open
                sub := sub()
            this._OpenHtmlMenu(sub, r.right - 3, r.top - 4, rec.Level + 1, rec.Id)
            if focus
                this._CtxFirst(rec.Level + 1)
        }
    }
    _CtxFirst(level) {
        if !this._ctxLevels.Has(level)
            return
        for j, it in this._ctxLevels[level].List
            if !it.Disabled {
                this._CtxCursorAt(level, j)
                return
            }
    }
    ; Hovering moves the highlight and opens a submenu. Closing one, though,
    ; waits: the pointer on its way from a parent item to the panel that item
    ; opened crosses the rows in between, and closing on the first of those is
    ; what makes a menu feel like it is running away. So a sibling only
    ; schedules the close, and reaching the panel (or its grace strip) calls it
    ; off. No triangles, no geometry -- a timer and a few transparent pixels.
    _CtxHover(el) {
        if !this.HasOwnProp("_ctxLevels")
            return
        n := this._ctxLevels.Length
        if (n && this._IsInside(el, this._ctxLevels[n].Id)) {
            SetTimer(this._ctxCloseFn, 0)            ; made it: the panel stays
            this._CtxSwitchLater("", 0)
        }
        hit := this._Closest(el, (id) => this._ctxItems.Has(id))
        if !hit
            return
        rec := this._ctxItems[hit.id]
        this._CtxCursorAt(rec.Level, rec.Index)
        if (IsObject(rec.Sub) && !rec.Disabled) {
            SetTimer(this._ctxCloseFn, 0)
            ; already showing this one: leave it be. A menu item is made of
            ; several spans, so crossing them refires mouseover, and rebuilding
            ; the panel each time flickers it and loses the keyboard cursor.
            if (n > rec.Level && this._ctxLevels[rec.Level + 1].ParentId = rec.Id) {
                this._CtxSwitchLater("", 0)          ; back on it: no switch
                return
            }
            ; Nothing open beside it: open now. A sibling's panel open: the
            ; pointer is most likely crossing this row on its way THERE, so
            ; wait as Windows does, and let arriving call it off. Crossing
            ; this row's own spans must not restart the wait.
            if (n > rec.Level && this._MenuDelay() > 0) {
                if !(this.HasOwnProp("_ctxSwitchRec") && this._ctxSwitchRec = rec)
                    this._CtxSwitchLater(rec, this._MenuDelay())
            } else
                this._CtxOpenSub(rec)
            return
        }
        this._CtxSwitchLater("", 0)                  ; a plain row: no switch
        ; a plain row with something deeper still open: give the pointer a
        ; moment to be on its way somewhere, and never close a pinned panel
        if (n > rec.Level && this._ctxPin = "") {
            this._ctxCloseLevel := rec.Level + 1
            SetTimer(this._ctxCloseFn, -320)
        }
    }
    ; A submenu switch waiting to see whether the pointer is only passing.
    ; rec "" or ms 0 calls off whatever is pending.
    _CtxSwitchLater(rec, ms) {
        if !this.HasOwnProp("_ctxSwitchFn")
            this._ctxSwitchFn := ObjBindMethod(this, "_CtxSwitch")
        this._ctxSwitchRec := rec
        SetTimer(this._ctxSwitchFn, (IsObject(rec) && ms > 0) ? -ms : 0)
    }
    _CtxSwitch() {
        rec := this._ctxSwitchRec, this._ctxSwitchRec := ""
        if (!this._ctxOpen || !IsObject(rec) || !this._ctxItems.Has(rec.Id))
            return
        if (this._ctxItems[rec.Id] != rec)
            return                                   ; that menu was rebuilt since
        this._CtxOpenSub(rec)
    }
    ; Windows' own MenuShowDelay, which is what every native menu on this
    ; machine waits: 400 ms unless someone has changed it.
    _MenuDelay() {
        static ms := ""
        if (ms = "") {
            v := -1                              ; stays out of range if the call fails
            try DllCall("SystemParametersInfo", "UInt", 0x6A, "UInt", 0, "UInt*", &v, "UInt", 0)
            ms := (v >= 0 && v <= 2000) ? v : 400
        }
        return ms
    }
    _CtxCloseDeeper() {
        if (this._ctxOpen && this._ctxCloseLevel)
            this._CloseFrom(this._ctxCloseLevel)
        this._ctxCloseLevel := 0
    }

    ; --- menu keyboard ------------------------------------------------------
    ; Up/Down walk the items, Enter runs one, a letter picks it by access key
    ; (&New -> N), Escape closes. Works for a right-click menu and for one
    ; dropped from the menu bar alike.
    _CtxKey(ev) {
        if (!this._ctxOpen || !this.HasOwnProp("_ctxLevels") || !this._ctxLevels.Length)
            return false
        lv := this._ctxLevels[this._ctxLevels.Length]
        this._ctxList := lv.List, this._ctxAt := lv.Cursor
        k := ev.keyCode
        if (k = 39) {                                    ; Right opens a submenu
            if (this._ctxAt && IsObject(this._ctxList[this._ctxAt].Sub)) {
                this._CtxOpenSub(this._ctxList[this._ctxAt], true)
                return true
            }
            return false                                 ; else the menu bar moves along
        }
        if (k = 37) {                                    ; Left closes one level
            if (this._ctxLevels.Length > 1) {
                this._CloseFrom(this._ctxLevels.Length)
                return true
            }
            return false
        }
        if (k = 38 || k = 40) {
            this._CtxMove(k = 40 ? 1 : -1)
            return true
        }
        if (k = 36 || k = 35) {                          ; Home / End
            this._ctxAt := (k = 36) ? 0 : this._ctxList.Length + 1
            this._CtxMove(k = 36 ? 1 : -1)
            return true
        }
        if (k = 13 || k = 32) {
            if this._ctxAt
                this._CtxRun(this._ctxAt)
            return true
        }
        if (k = 27) {                                    ; Escape backs out one level
            if (this._ctxLevels.Length > 1) {
                this._CloseFrom(this._ctxLevels.Length)
                return true
            }
        }
        if (k = 27) {
            this.CloseContextMenu()
            return true
        }
        if (k >= 65 && k <= 90) {
            ch := StrLower(Chr(k)), hits := []
            for j, it in this._ctxList
                if (it.Key = ch && !it.Disabled)
                    hits.Push(j)
            if (hits.Length = 1) {
                this._CtxRun(hits[1])
                return true
            }
            if hits.Length {                              ; several: step through them
                pick := hits[1]
                for j in hits
                    if (j > this._ctxAt) {
                        pick := j
                        break
                    }
                this._CtxCursor(pick)
                return true
            }
        }
        return false
    }
    _CtxMove(delta) {
        n := this._ctxList.Length, i := this._ctxAt
        loop n {
            i += delta
            i := (i < 1) ? n : (i > n) ? 1 : i
            if !this._ctxList[i].Disabled
                break
        }
        this._CtxCursor(i)
    }
    _CtxCursor(i) {
        this._CtxCursorAt(this._ctxLevels.Length, i)
    }
    _CtxCursorAt(level, i) {
        if (!this._ctxLevels.Has(level))
            return
        lv := this._ctxLevels[level]
        for j, it in lv.List
            try AxWindow._SetClass(this.El(it.Id), "kb", j = i)
        lv.Cursor := i
        this._ctxAt := i
    }
    _CtxRun(i) {
        if (!this._ctxList.Has(i) || this._ctxList[i].Disabled)
            return
        rec := this._ctxList[i]
        if IsObject(rec.Sub) {                           ; Enter on a branch opens it
            this._CtxOpenSub(rec, true)
            return
        }
        fn := rec.Fn, tgt := this._ctxTarget
        this.CloseContextMenu()
        if fn
            try fn(tgt, "")
    }

    ; --- tooltips ----------------------------------------------------------
    _TipOver(el) {
        t := el
        loop 16 {
            if !IsObject(t)
                return
            try v := t.getAttribute("data-tip")
            catch
                v := ""
            if (v != "" && v != "null")
                break
            t := AxWindow._ParentEl(t)
        }
        try uid := t.uniqueID
        catch
            return
        if (uid = this._tipUid)
            return
        this._HideTip(true)
        this._tipUid := uid, this._tipEl := t
        SetTimer(this._tipShowFn, -this.TooltipDelay)
    }
    _TipOut(ev) {
        if (this._tipUid = "")
            return
        try to := ev.toElement
        catch
            to := ""
        loop 16 {                                  ; still inside the tip owner?
            if !IsObject(to)
                break
            try {
                if (to.uniqueID = this._tipUid)
                    return
                to := AxWindow._ParentEl(to)
            } catch
                break
        }
        this._HideTip(true)
    }
    _ShowTip() {
        el := this._tipEl
        if !IsObject(el) || this._dlg || this._ctxOpen
            return
        try {
            text := el.getAttribute("data-tip")
            if (text = "")
                return
            tip := this.El("axTip")
            tip.innerText := text
            tip.style.left := "0px", tip.style.top := "0px"
            tip.style.display := "block"
            r := el.getBoundingClientRect()
            vw := this.Doc.documentElement.clientWidth, vh := this.Doc.documentElement.clientHeight
            tw := tip.offsetWidth, th := tip.offsetHeight
            x := Round((r.left + r.right) / 2 - tw / 2)
            y := r.bottom + 8
            if (y + th > vh - 4)
                y := r.top - th - 8
            x := Max(4, Min(x, vw - tw - 4))
            tip.style.left := x "px", tip.style.top := y "px"
        }
    }
    _HideTip(forget) {
        SetTimer(this._tipShowFn, 0)
        if forget
            this._tipUid := "", this._tipEl := ""
        try this.El("axTip").style.display := "none"
    }

    ; ---------------------------------------------------------------- popover
    ; A popover is a panel of your own markup anchored to an element. It opens
    ; on a click or on hover, closes on Escape, on a click outside it, or when
    ; the pointer leaves both the anchor and the panel, and it arrives with a
    ; short transition rather than simply appearing.
    ;
    ;   win.Popover("acct", {Html: "<b>Signed in</b>", On: "hover"})
    ;   win.Popover("acct", {Build: () => Card(), Align: "right", Width: 280})
    ;   win.ShowPopover("acct")   win.TogglePopover("acct")   win.ClosePopover()
    ;   win.Popover("acct", "")                                    ; unregister
    ;
    ; spec:
    ;   Html    markup for the panel            Build  fn() -> markup, per open
    ;   On      "click" (default) | "hover" | "none" (only ShowPopover opens it)
    ;   Align   "left" (default) | "center" | "right", against the anchor
    ;   Width   px for the content, the sheet's padding round it; or "" to size
    ;           to the content                          Gap  px below the anchor
    ;   Class   extra class on the panel        Delay  ms before a hover opens
    ;   OnOpen  fn(win, id) once the panel is in the DOM -- wire its controls
    ;   OnClose fn(win, id)
    ;
    ; Build runs on every open, so a panel can show what is current; anything
    ; inside it is ordinary page markup, so On(), OnValue() and Value() work on
    ; its controls exactly as they do anywhere else.
    Popover(anchorId, spec := "") {
        if (spec = "") {
            this._pop.Delete(anchorId)
            if (this._popOpen = anchorId)
                this.ClosePopover(true)
            return this
        }
        o := (n, d) => (IsObject(spec) && spec.HasOwnProp(n)) ? spec.%n% : d
        this._pop[anchorId] := {Html: o("Html", ""), Build: o("Build", ""),
            On: StrLower(String(o("On", "click"))), Align: StrLower(String(o("Align", "left"))),
            Width: o("Width", ""), Gap: o("Gap", 6), Class: o("Class", ""),
            Delay: o("Delay", 130), OnOpen: o("OnOpen", ""), OnClose: o("OnClose", "")}
        return this
    }
    PopoverOpen => this._popOpen
    TogglePopover(anchorId) => (this._popOpen = anchorId) ? this.ClosePopover() : this.ShowPopover(anchorId)
    ShowPopover(anchorId) {
        if (!this._pop.Has(anchorId) || this._popOpen = anchorId || !IsObject(this.Doc))
            return this
        sp := this._pop[anchorId]
        el := this.El(anchorId)
        if !IsObject(el)
            return this
        this.ClosePopover(true)
        html := sp.Html
        if (sp.Build != "") {
            f := sp.Build
            html := f()
        }
        try {
            pop := this.El("axPop")
            pop.className := (sp.Class != "") ? sp.Class : ""
            pop.innerHTML := html
            pop.style.width := (sp.Width = "") ? "auto" : sp.Width "px"
            ; Width is the room for what it holds; the sheet's padding goes
            ; round it. Under the pages' border-box it was the outside size, so
            ; a sheet with more padding (cozy's 18px) left the content less room
            ; than it was given and it ran into the edge or out of the panel.
            pop.style.boxSizing := (sp.Width = "") ? "" : "content-box"
            ; place it off-screen first: it has to be laid out before it can be
            ; measured, and Trident lays out at the coordinates it is given
            pop.style.left := "0px", pop.style.top := "-4000px"
            pop.style.display := "block"
            r := el.getBoundingClientRect()
            vw := this.Doc.documentElement.clientWidth, vh := this.Doc.documentElement.clientHeight
            pw := pop.offsetWidth, ph := pop.offsetHeight
            switch sp.Align {
                case "right":  x := r.right - pw
                case "center": x := (r.left + r.right) / 2 - pw / 2
                default:       x := r.left
            }
            ; The room it may use: the window, 10px in from its edges -- or, for
            ; an anchor on a page, the page's visible box, which stops short of
            ; the page's own scrollbar. The document's width runs under that
            ; scrollbar and the window's resize edge, and a popover clamped to
            ; it sat right on top of them.
            lo := 10, hi := vw - 10, top := 10, bot := vh - 10
            try {
                c := this.El("content")
                if (IsObject(c) && c.contains(el)) {
                    cr := c.getBoundingClientRect()
                    lo := Max(lo, cr.left + 8)
                    hi := Min(hi, cr.left + c.clientLeft + c.clientWidth - 8)
                    bot := Min(bot, cr.top + c.clientTop + c.clientHeight - 8)
                }
            }
            y := r.bottom + sp.Gap
            if (y + ph > bot)                          ; no room below: flip above
                y := Max(top, r.top - ph - sp.Gap)
            x := (pw >= hi - lo) ? lo : Max(lo, Min(Round(x), hi - pw))
            pop.style.left := Round(x) "px", pop.style.top := Round(y) "px"
            this._popOpen := anchorId
            AxWindow._SetClass(el, "pop-open", true)
            reflow := pop.offsetHeight                 ; the transition needs a frame
            SetTimer(this._popShowFn, -1)
        }
        if (sp.OnOpen != "") {
            f := sp.OnOpen
            try f(this, anchorId)
        }
        return this
    }
    ClosePopover(immediate := false) {
        SetTimer(this._popShowFn, 0)
        SetTimer(this._popOpenFn, 0)
        SetTimer(this._popLeaveFn, 0)
        this._popPend := ""
        if (this._popOpen = "")
            return this
        id := this._popOpen, this._popOpen := ""
        sp := this._pop.Has(id) ? this._pop[id] : ""
        try AxWindow._SetClass(this.El(id), "pop-open", false)
        try {
            pop := this.El("axPop")
            AxWindow._SetClass(pop, "open", false)
            if immediate {
                SetTimer(this._popHideFn, 0)
                pop.style.display := "none"
            } else
                SetTimer(this._popHideFn, -200)        ; after the fade
        }
        if (IsObject(sp) && sp.OnClose != "") {
            f := sp.OnClose
            try f(this, id)
        }
        return this
    }
    _PopShow() {
        try AxWindow._SetClass(this.El("axPop"), "open", true)
    }
    _PopHide() {
        if (this._popOpen = "")
            try this.El("axPop").style.display := "none"
    }
    _PopOpenPending() {
        if (this._popPend != "")
            this.ShowPopover(this._popPend)
        this._popPend := ""
    }
    ; the registered anchor at or above `el`, or ""
    _PopAnchor(el) {
        hit := this._Closest(el, (id) => this._pop.Has(id))
        return hit ? hit.id : ""
    }
    _InPopover(el) => this._IsInside(el, "axPop")
    ; mouseover: open a hover popover, and hold an open one while the pointer
    ; is anywhere in it or back on its anchor
    _PopOver(el) {
        if (this._pop.Count = 0)
            return
        inPop := this._InPopover(el)
        id := inPop ? "" : this._PopAnchor(el)
        if (inPop || (id != "" && id = this._popOpen)) {
            SetTimer(this._popLeaveFn, 0)              ; stay open
            return
        }
        if (id = "" || this._pop[id].On != "hover")
            return
        SetTimer(this._popLeaveFn, 0)
        this._popPend := id
        SetTimer(this._popOpenFn, -Max(1, this._pop[id].Delay))
    }
    ; mouseout: give the pointer time to cross the gap into the panel
    _PopOut(el) {
        if (this._popOpen = "" && this._popPend = "")
            return
        if (this._popPend != "" && this._PopAnchor(el) = this._popPend) {
            SetTimer(this._popOpenFn, 0)               ; left before it opened
            this._popPend := ""
        }
        if (this._popOpen = "" || !this._pop.Has(this._popOpen)
            || this._pop[this._popOpen].On != "hover")
            return
        SetTimer(this._popLeaveFn, -190)
    }
    _PopLeave() {
        if (this._popOpen != "" && this._pop.Has(this._popOpen)
            && this._pop[this._popOpen].On = "hover")
            this.ClosePopover()
    }
}
