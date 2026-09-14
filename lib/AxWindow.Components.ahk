#Requires AutoHotkey v2.0
; =============================================================================
;  AxWindow.Components.ahk — component behaviour mixed into AxWindow:
;  data-role dispatch (dropdown, list, tabs, number box, slider, palette,
;  rating, segmented, expander, password reveal, info bar), drag-reorder,
;  hotkey recording, keyboard navigation and multi-select lists.
;  Methods here run with `this` = the AxWindow instance.
; =============================================================================
class AxWindowComponents {
    ; Hotkey(id, fn): bind the value of an <ax-hotkey> to an AHK Hotkey, and
    ; rebind whenever the user records a new combination.
    Hotkey(id, fn) {
        bind := (v, el) => this._BindHotkey(id, v, fn)
        this.OnValue(id, bind)
        bind(this.Value(id), "")
        return this
    }
    _BindHotkey(id, v, fn) {
        static bound := Map()
        if bound.Has(id) {
            try Hotkey(bound[id], "Off")
            bound.Delete(id)
        }
        if (v = "")
            return
        try {
            Hotkey(v, fn, "On")
            bound[id] := v
        } catch as e {
            this.Toast("Hotkey '" v "' failed: " e.Message, 4000, "error")
        }
    }
    ; --- pointer capture ---------------------------------------------------
    ; PointerCapture(onMove, onUp): follow the mouse until the left button is
    ; released, even while the cursor is outside the window. onMove(x, y) and
    ; onUp(x, y) get document CSS pixels (the same space getBoundingClientRect
    ; reports), so a knob keeps tracking when the drag leaves its track.
    ; The cursor is polled rather than read from DOM mousemove because Trident
    ; stops delivering those the moment the pointer leaves the page.
    PointerCapture(onMove, onUp := "") {
        if !this.HasOwnProp("_ptrFn")
            this._ptrFn := ObjBindMethod(this, "_PointerTick")
        this._ptr := {Move: onMove, Up: onUp}
        this._PointerTick()
        if this.HasOwnProp("_ptr") && IsObject(this._ptr)
            SetTimer(this._ptrFn, 15)
        return this
    }
    ReleasePointer() {
        if this.HasOwnProp("_ptrFn")
            SetTimer(this._ptrFn, 0)
        this._ptr := ""
        return this
    }
    _PointerTick(*) {
        p := (this.HasOwnProp("_ptr") ? this._ptr : "")
        if (!IsObject(p) || this.Closing) {
            this.ReleasePointer()
            return
        }
        pt := Buffer(8, 0)
        DllCall("GetCursorPos", "Ptr", pt)
        d := this._DocPoint(NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int"))
        ; the callbacks must go through local variables: obj.Prop(a, b) is a
        ; METHOD call in v2, which would hand the holder object in as the
        ; first parameter and fail with "too many parameters"
        mv := p.Move, up := p.Up
        if mv
            mv(d.X, d.Y)
        if !GetKeyState("LButton", "P") {
            this.ReleasePointer()
            if up
                up(d.X, d.Y)
        }
    }

    ; SortOrder(id): array of data-value (or text) of a sortable's .drag-item
    ; children, in their current order.
    SortOrder(id) {
        out := []
        try {
            items := this.El(id).querySelectorAll(".drag-item")
            loop items.length {
                it := items.item(A_Index - 1)
                v := AxWindow._Attr(it, "data-value")
                out.Push(v != "" ? v : it.innerText)
            }
        }
        return out
    }
    ; RemoveItem(id, value): remove the .drag-item with that data-value
    RemoveItem(id, value) {
        try {
            items := this.El(id).querySelectorAll(".drag-item")
            loop items.length {
                it := items.item(A_Index - 1)
                if (AxWindow._Attr(it, "data-value") = value) {
                    it.parentNode.removeChild(it)
                    break
                }
            }
        }
        return this
    }
    ; custom controls take part in Tab navigation (tabindex) and keyboard
    ; handling lives in _KeyNav. root: only what is inside it (a page just
    ; put back by _FillPages), else the whole document
    _MakeFocusable(root := "") {
        try {
            els := (IsObject(root) ? root : this.Doc).querySelectorAll(".btn, .dropdown, .list, .tab, .seg, .chip, .link, .rating, .swatch, .imgbox.button, .dropzone")
            loop els.length {
                e := els.item(A_Index - 1)
                if (AxWindow._Attr(e, "tabindex") = "" && !AxWindow._HasClass(e, "disabled"))
                    e.setAttribute("tabindex", "0")
            }
        }
    }
    ; keyboard on focused custom controls; returns true when handled
    _KeyNav(el, ev) {
        k := ev.keyCode
        try tag := el.tagName
        catch
            return false
        if (tag = "INPUT" || tag = "TEXTAREA")
            return false
        ; buttons / links / chips / tabs / segments / swatches: Enter or Space = click
        if (k = 13 || k = 32) {
            for c in ["btn", "link", "chip", "tab", "seg", "swatch", "axdlg-btn", "axctx-item", "imgbox", "dropzone"]
                if AxWindow._HasClass(el, c) {
                    this._SyntheticClick(el, ev)
                    return true
                }
        }
        role := AxWindow._Attr(el, "data-role")
        if (role = "dropdown") {
            if AxWindow._HasClass(el, "disabled")
                return false
            if (k = 38 || k = 40) {                       ; Up / Down: previous / next option
                this._StepItems(el, ".dd-item", "dropdown", k = 40 ? 1 : -1)
                return true
            }
            if (k = 13 || k = 32) {                       ; Enter / Space: open / close
                this._Components("click", el, ev)
                return true
            }
            if (k = 27 && IsObject(this._ddOpen)) {
                this._CloseDropdown()
                return true
            }
            return false
        }
        if (role = "list") {
            multi := AxWindow._Attr(el, "data-multi")
            if (k = 38 || k = 40) {
                if (multi = "")
                    this._StepItems(el, ".list-item", "list", k = 40 ? 1 : -1)
                else
                    this._MoveCursor(el, k = 40 ? 1 : -1)
                return true
            }
            if (multi != "" && (k = 32 || k = 13)) {      ; Space toggles the cursor item
                cur := el.querySelector(".list-item.kb")
                if IsObject(cur) {
                    AxWindow._SetClass(cur, "selected", !AxWindow._HasClass(cur, "selected"))
                    this._CommitMulti(el)
                }
                return true
            }
            return false
        }
        if (AxWindow._HasClass(el, "tab") || AxWindow._HasClass(el, "seg")) && (k = 37 || k = 39) {
            sib := (k = 39) ? el.nextSibling : el.previousSibling
            while IsObject(sib) && !(AxWindow._HasClass(sib, "tab") || AxWindow._HasClass(sib, "seg"))
                sib := (k = 39) ? sib.nextSibling : sib.previousSibling
            if IsObject(sib) {
                this._SyntheticClick(sib, ev), sib.focus()
                return true
            }
        }
        if (role = "rating" && (k = 37 || k = 39)) {
            v := AxWindow._Attr(el, "data-value"), v := (v = "" ? 0 : Integer(v)) + (k = 39 ? 1 : -1)
            stars := el.querySelectorAll(".star").length   ; not "max": that IS Max()
            this.Value(el.id, Max(0, Min(stars, v)))
            return true
        }
        return false
    }
    ; a click raised from the keyboard: Trident's element.click() does not reach
    ; the document sink, so run the library's own click path directly
    _SyntheticClick(el, ev) {
        if this._dlg {
            hit := this._Closest(el, (id) => InStr(id, "axDlgBtn") = 1)
            if hit
                this._EndDialog(Integer(SubStr(hit.id, 9)))
            else if this._Closest(el, (id) => id = "axDlgClose")
                this._EndDialog(this._dlg.Cancel)
            return
        }
        if (this._ctxOpen && this._ctxItems.Has(el.id)) {
            fn := this._ctxItems[el.id], tgt := this._ctxTarget
            this.CloseContextMenu()
            if fn
                fn(tgt, ev)
            return
        }
        this._Components("click", el, ev)
        if this.Hooks.Has("click") {
            hooks := this.Hooks["click"]
            hit := this._Closest(el, (id) => hooks.Has(id))
            if hit
                hooks[hit.id].Call(hit, ev)
        }
    }
    ; select the previous/next item of a dropdown or single-select list
    _StepItems(cont, sel, role, dir) {
        items := cont.querySelectorAll(sel)
        if !items.length
            return
        idx := 0
        loop items.length
            if AxWindow._HasClass(items.item(A_Index - 1), "selected")
                idx := A_Index
        idx := Max(1, Min(items.length, idx + dir))
        it := items.item(idx - 1)
        this._SelectItem(cont, role, AxWindow._Attr(it, "data-value"), it)
        try it.scrollIntoView(false)
    }
    ; multi-select lists: a keyboard cursor (class "kb") separate from selection
    _MoveCursor(lst, dir) {
        items := lst.querySelectorAll(".list-item")
        if !items.length
            return
        idx := 0
        loop items.length {
            it := items.item(A_Index - 1)
            if AxWindow._HasClass(it, "kb")
                idx := A_Index
            AxWindow._SetClass(it, "kb", false)
        }
        idx := Max(1, Min(items.length, idx + dir))
        it := items.item(idx - 1)
        AxWindow._SetClass(it, "kb", true)
        try it.scrollIntoView(false)
    }
    ; "^+k" -> "Ctrl + Shift + K"
    static HotkeyDisplay(v) => AxSys.HotkeyDisplay(v)
    ; --- data-role components ---------------------------------------------
    ; Markup contract (see lib/themes/win11.css and example/gui.html):
    ;   dropdown : <div data-role="dropdown"><div class="dd-value">..</div><div class="dd-menu"><div class="dd-item" data-value="x">..</div></div></div>
    ;   list     : <div data-role="list"><div class="list-item" data-value="x">..</div></div>
    ;   tabs     : <div data-role="tabs"><div class="tab" data-target="panelId">..</div></div>
    ;   numberbox: <div data-role="numberbox"><input type="text" value="1" data-min="0" data-max="9" data-step="1"><div class="spin" data-role="spin-up">..</div><div class="spin" data-role="spin-down">..</div></div>
    ;   slider   : <div data-role="slider" data-out="labelId" data-suffix="%"><input type="range" ...></div>
    ;   palette  : <div data-role="palette" data-out="hexId"><div class="swatch" data-value="#ff0000"></div>..</div>
    ;   expander : <div data-role="expander"><div class="exp-header" data-role="expander-header">..</div><div class="exp-body">..</div></div>
    ;   password : <div data-role="passwordbox"><input type="password"><div data-role="reveal">..</div></div>
    ;   infobar  : <div data-role="infobar">..<div data-role="infobar-close">..</div></div>
    ;   switch   : <label class="switch" data-role="switch" data-on="On" data-off="Off"><input type="checkbox"><span class="sw-track"></span><span class="sw-label"></span></label>
    _Components(type, el, ev) {
        if (type = "focusin" || type = "focusout") {
            if (ac := this._RoleAncestor(el, "autocomplete")) && el.tagName = "INPUT" {   ; the list itself can take focus (scrollbar press): ignore that
                if (type = "focusin") {
                    ; keyup is not delivered reliably by Trident: poll the text while focused
                    if !this.HasOwnProp("_acPollFn")
                        this._acPollFn := ObjBindMethod(this, "_AcPoll")
                    this._acFocus := ac, this._acLast := el.value
                    SetTimer(this._acPollFn, 80)
                    this._AcFilter(ac, el.value)
                } else {
                    this._acFocus := ""
                    SetTimer(this._acPollFn, 0)
                    SetTimer(ObjBindMethod(this, "_AcCommit", ac), -150)   ; after a click on an item lands
                }
                return
            }
            nb := this._RoleAncestor(el, "numberbox")
            if nb
                AxWindow._SetClass(nb, "focus", type = "focusin")
            hk := this._RoleAncestor(el, "hotkey")
            if hk
                this._HotkeyCapture(type = "focusin" ? hk : "")
            return
        }
        if (type = "keydown" || type = "keyup") {
            if hk := this._RoleAncestor(el, "hotkey") {
                if (type = "keydown")
                    this._HotkeyKeyDown(hk, el, ev)
                ev.returnValue := false
                return
            }
            if ac := this._RoleAncestor(el, "autocomplete") {
                k := ev.keyCode
                if (k = 13 || k = 27 || k = 38 || k = 40 || k = 9) {
                    ; Trident may deliver only keydown or only keyup for these
                    ; in a text input: act on whichever arrives first per press
                    if (type = "keydown")
                        this._acHandled := true, this._AcKey(ac, el, ev)
                    else if this._acHandled
                        this._acHandled := false
                    else
                        this._AcKey(ac, el, ev)
                }
                return
            }
            nb := this._RoleAncestor(el, "numberbox")
            if !nb {
                if (type = "keydown" && this._KeyNav(el, ev))
                    ev.returnValue := false
                ; a text box says it changed as it is typed in, not only when
                ; it is left: OnChange, and a binding on it, follow the typing
                if (type = "keyup")
                    this._TypedIn(el)
                return
            }
            k := ev.keyCode
            if (k = 38 || k = 40) {                          ; Up / Down arrow
                ; Trident does not reliably deliver keydown to the document, so
                ; step on whichever of keydown/keyup arrives first for a press
                if (type = "keydown")
                    this._nbStepped := true
                else if this._nbStepped {
                    this._nbStepped := false
                    return
                }
                this._NumberStep(nb, k = 38 ? 1 : -1, ev)
                ev.returnValue := false
                return
            }
            if (type = "keyup") {
                v := el.value
                clean := RegExReplace(v, "[^0-9.\-]")        ; digits only
                if (clean != v)
                    el.value := clean
            }
            return
        }
        if (type = "change") {
            this._TypedIn(el)                    ; pasted or cut with the mouse
            if sl := this._RoleAncestor(el, "slider") {
                this._UpdateOut(sl, el.value)
                this._FireValue(sl, el.value)
            } else if nb := this._RoleAncestor(el, "numberbox") {
                this._SetInput(nb, el.value)
            }
            return
        }
        ; click
        ; checkbox / radio state is read from the input's own click (the
        ; label's click is re-dispatched to it by Trident); "change" is not
        ; reliably delivered to the document for these input types.
        try tag := el.tagName
        catch
            tag := ""
        if (tag = "INPUT") {
            if sw := this._RoleAncestor(el, "switch") {
                lbl := sw.querySelector(".sw-label")
                if IsObject(lbl)
                    lbl.innerText := AxWindow._Attr(sw, el.checked ? "data-on" : "data-off")
                this._FireValue(sw, el.checked ? 1 : 0)
            } else if chk := this._RoleAncestor(el, "check") {
                this._FireValue(chk, el.checked ? 1 : 0)
            } else if rd := this._RoleAncestor(el, "radio") {
                if el.checked {
                    grp := this._RoleAncestor(rd, "radiogroup")
                    dv := AxWindow._Attr(rd, "data-value")
                    this._FireValue(grp ? grp : rd, dv != "" ? dv : el.value)
                }
            }
            return
        }
        r := this._ClosestRole(el)
        ; clicking anywhere in a hotkey box (except its clear button) starts
        ; recording, without depending on focusin being delivered
        if (hkBox := this._RoleAncestor(el, "hotkey")) && !(r && r.role = "hotkey-clear") {
            try hkBox.querySelector("input").focus()
            this._HotkeyCapture(hkBox)
            return
        }
        if !r
            return
        role := r.role, t := r.el
        ; whichever component registered this role answers for it -- including
        ; the page rail, which is the window's own and registered by AxWindow
        if AxWindow.ClickHandlers.Has(role)
            AxWindow.ClickHandlers[role].Call(this, el, t, ev)
    }
    ; the page rail: a click on a nav item shows that page
    _NavClick(el) {
        pg := AxWindow._Attr(el, "data-page")
        if (pg != "")
            this.ShowPage(pg)
    }
    ; --- drag to reorder ---------------------------------------------------
    ; <div data-role="sortable" [data-axis="x|y"] [data-handle="1"] [data-hold="600"]>
    ;   <div class="drag-item" data-value="a"> ... [<span class="drag-handle">] ... </div>
    ; A floating ghost follows the cursor; the real item is re-inserted live
    ; as the cursor crosses other items. OnValue fires with the new order.
    ;
    ; data-hold arms the drag on a press and hold instead of straight away, the
    ; way a phone's home screen does: nothing moves until the button has been
    ; down that many milliseconds, and moving before then cancels it, so a
    ; click stays a click and a stray twitch does not shuffle the list. While
    ; it is armed the container carries "sort-armed" and the item "drag-hold",
    ; which is enough for a stylesheet to show reorder mode without any help
    ; from here.
    _DragDown(el, ev) {
        if !AxWindow._IsLeft(ev) || this._dlg
            return
        try tag := el.tagName
        catch
            tag := ""
        if (tag = "INPUT" || tag = "TEXTAREA" || this._ClosestRole(el))
            return                                  ; leave real controls alone
        item := this._ClosestClass(el, "drag-item")
        if !item
            return
        cont := this._RoleAncestor(item, "sortable")
        if !cont
            return
        if (AxWindow._Attr(cont, "data-handle") != "" && !this._ClosestClass(el, "drag-handle"))
            return
        hold := AxWindow._Attr(cont, "data-hold")
        this._drag := {item: item, cont: cont, x: ev.clientX, y: ev.clientY, active: false,
                       ghost: "", offX: 0, offY: 0, armed: (hold = "")}
        if (hold != "")
            SetTimer(this._dragArmFn, -Max(1, Integer(hold)))
    }
    ; the hold elapsed with the button still down and the pointer still still
    _DragArm() {
        d := this._drag
        if (!d || d.armed)
            return
        d.armed := true
        this._HideTip(true)
        try AxWindow._SetClass(d.cont, "sort-armed", true)
        try AxWindow._SetClass(d.item, "drag-hold", true)
    }
    _DragDisarm(d) {
        SetTimer(this._dragArmFn, 0)
        if !IsObject(d)
            return
        try AxWindow._SetClass(d.cont, "sort-armed", false)
        try AxWindow._SetClass(d.item, "drag-hold", false)
    }
    _DragMove(ev) {
        d := this._drag
        if !d
            return
        x := ev.clientX, y := ev.clientY
        if !d.armed {
            ; moving before the hold is up cancels it: a press that turns into
            ; a scroll, or a click with a shaky hand, must not start a reorder
            if (Abs(x - d.x) > 4 || Abs(y - d.y) > 4) {
                this._DragDisarm(d)
                this._drag := ""
            }
            return
        }
        if !d.active {
            if (Abs(x - d.x) < 4 && Abs(y - d.y) < 4)
                return
            d.active := true
            r := d.item.getBoundingClientRect()
            d.offX := d.x - r.left, d.offY := d.y - r.top
            g := d.item.cloneNode(true)
            g.removeAttribute("id")
            g.className := d.item.className " drag-ghost"
            s := g.style
            s.position := "fixed", s.left := r.left "px", s.top := r.top "px"
            s.width := (r.right - r.left) "px", s.height := (r.bottom - r.top) "px"
            s.margin := "0", s.zIndex := 100010, s.pointerEvents := "none"   ; above every overlay
            this.Doc.body.appendChild(g)
            d.ghost := g
            AxWindow._SetClass(d.item, "drag-placeholder", true)
            this.BodyClass("dragging", true)
            this._HideTip(true)
        }
        d.ghost.style.left := (x - d.offX) "px", d.ghost.style.top := (y - d.offY) "px"
        try under := this.Doc.elementFromPoint(x, y)
        catch
            return
        tgt := this._ClosestClass(under, "drag-item")
        if !tgt || (tgt.uniqueID = d.item.uniqueID) || !this._HasAncestorUid(tgt, d.cont.uniqueID)
            return
        r := tgt.getBoundingClientRect()
        axis := AxWindow._Attr(d.cont, "data-axis")
        if (axis = "")
            axis := ((r.right - r.left) >= d.cont.clientWidth - 8) ? "y" : "x"
        before := (axis = "y") ? (y < (r.top + r.bottom) / 2) : (x < (r.left + r.right) / 2)
        if before
            d.cont.insertBefore(d.item, tgt)
        else {
            ns := tgt.nextSibling
            if IsObject(ns)
                d.cont.insertBefore(d.item, ns)
            else
                d.cont.appendChild(d.item)
        }
    }
    _DragUp(ev) {
        d := this._drag
        if !d
            return
        this._drag := ""
        this._DragDisarm(d)
        if !d.active
            return
        try d.ghost.parentNode.removeChild(d.ghost)
        AxWindow._SetClass(d.item, "drag-placeholder", false)
        this.BodyClass("dragging", false)
        this._FireValue(d.cont, this.SortOrder(d.cont.id))
    }
    _ClosestClass(el, cls) {
        loop 16 {
            if !IsObject(el)
                return ""
            if AxWindow._HasClass(el, cls)
                return el
            el := AxWindow._ParentEl(el)
        }
        return ""
    }
    _SliderPoll() {
        sl := this._slActive
        if !IsObject(sl)
            return
        try v := sl.querySelector("input").value
        catch
            return
        if (v = this._slLast)
            return
        this._slLast := v
        this._UpdateOut(sl, v)
        this._FireValue(sl, v)
    }
    ; --- hotkey catcher ----------------------------------------------------
    ; <div data-role="hotkey"><input readonly><div data-role="hotkey-clear"></div></div>
    ; data-value = AHK hotkey string (e.g. "^+k"); input shows "Ctrl + Shift + K"
    _HotkeyKeyDown(hk, inp, ev) {
        static names := Map(8, "Backspace", 9, "Tab", 13, "Enter", 19, "Pause", 20, "CapsLock", 27, "Escape", 32, "Space",
            33, "PgUp", 34, "PgDn", 35, "End", 36, "Home", 37, "Left", 38, "Up", 39, "Right", 40, "Down", 45, "Insert", 46, "Delete",
            106, "NumpadMult", 107, "NumpadAdd", 109, "NumpadSub", 110, "NumpadDot", 111, "NumpadDiv", 144, "NumLock", 145, "ScrollLock",
            186, ";", 187, "=", 188, ",", 189, "-", 190, ".", 191, "/", 192, "``", 219, "[", 220, "\", 221, "]", 222, "'", 93, "AppsKey")
        k := ev.keyCode
        mods := "", disp := ""
        if GetKeyState("Ctrl", "P")
            mods .= "^", disp .= "Ctrl + "
        if GetKeyState("Alt", "P")
            mods .= "!", disp .= "Alt + "
        if GetKeyState("Shift", "P")
            mods .= "+", disp .= "Shift + "
        if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
            mods .= "#", disp .= "Win + "
        if (k = 16 || k = 17 || k = 18 || k = 91 || k = 92) {      ; modifier alone: preview only
            inp.value := disp = "" ? "" : disp "…"
            return
        }
        if (k = 8 && mods = "") {                                   ; Backspace clears
            this._SetHotkeyValue(hk, "", "")
            return
        }
        if (k >= 48 && k <= 57)
            key := Chr(k), name := Chr(k)
        else if (k >= 65 && k <= 90)
            key := StrLower(Chr(k)), name := Chr(k)
        else if (k >= 96 && k <= 105)
            key := "Numpad" (k - 96), name := "Numpad " (k - 96)
        else if (k >= 112 && k <= 123)
            key := "F" (k - 111), name := "F" (k - 111)
        else if names.Has(k)
            key := names[k], name := names[k]
        else
            return
        this._SetHotkeyValue(hk, mods key, disp name)
    }
    ; While a hotkey box is focused an InputHook records the combination at
    ; the keyboard-hook level (independent of Trident's key routing) and
    ; blocks the keys from reaching the page.
    _HotkeyCapture(hk) {
        if IsObject(this._ihk) {
            try this._ihk.Stop()
            this._ihk := ""
            try AxWindow._SetClass(this._ihkBox, "recording", false)
            this._ihkBox := ""
        }
        if !IsObject(hk)
            return
        this._ihkBox := hk
        ih := InputHook("")
        ih.KeyOpt("{All}", "N S")
        ih.OnKeyDown := (ihk, vk, sc) => this._HotkeyVK(hk, vk, sc)
        ih.OnKeyUp   := (ihk, vk, sc) => this._HotkeyVKUp(hk, vk)
        ih.Start()
        this._ihk := ih
        AxWindow._SetClass(hk, "recording", true)
    }
    static _IsModVK(vk) => (vk = 16 || vk = 17 || vk = 18 || vk = 91 || vk = 92 || (vk >= 160 && vk <= 165))
    _ModPrefix(&disp) {
        mods := "", disp := ""
        if GetKeyState("Ctrl", "P")
            mods .= "^", disp .= "Ctrl + "
        if GetKeyState("Alt", "P")
            mods .= "!", disp .= "Alt + "
        if GetKeyState("Shift", "P")
            mods .= "+", disp .= "Shift + "
        if (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
            mods .= "#", disp .= "Win + "
        return mods
    }
    _HotkeyVK(hk, vk, sc) {
        mods := this._ModPrefix(&disp)
        inp := hk.querySelector("input")
        if AxWindow._IsModVK(vk) {                       ; modifier alone: preview
            inp.value := disp "…"
            return
        }
        if (vk = 8 && mods = "") {                         ; Backspace clears
            this._SetHotkeyValue(hk, "", "")
            return
        }
        if (vk = 9 || (vk = 27 && mods = "")) {            ; Tab / Escape: leave the box alone
            inp.value := AxWindow.HotkeyDisplay(AxWindow._Attr(hk, "data-value"))
            return
        }
        name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
        if (name = "")
            name := GetKeyName(Format("vk{:x}", vk))
        if (name = "")
            return
        key := (StrLen(name) = 1) ? StrLower(name) : name
        this._SetHotkeyValue(hk, mods key, disp (StrLen(name) = 1 ? StrUpper(name) : name))
    }
    _HotkeyVKUp(hk, vk) {
        ; modifiers released without a key: restore the stored value
        if AxWindow._IsModVK(vk) && !GetKeyState("Ctrl", "P") && !GetKeyState("Alt", "P") && !GetKeyState("Shift", "P") && !GetKeyState("LWin", "P") && !GetKeyState("RWin", "P")
            try hk.querySelector("input").value := AxWindow.HotkeyDisplay(AxWindow._Attr(hk, "data-value"))
    }
    _SetHotkeyValue(hk, value, display) {
        inp := hk.querySelector("input")
        inp.value := display
        hk.setAttribute("data-value", value)
        AxWindow._SetClass(hk, "has-value", value != "")
        this._FireValue(hk, value)
    }
    ; Trident's scrollbars are child windows and paint above positioned
    ; content. While a dropdown is open, hide the scrollbar of every
    ; scroller its menu overlaps (-ms-overflow-style keeps the scroll position).
    _ShieldScrollers(dd) {
        this._UnshieldScrollers()
        try {
            menu := dd.querySelector(".dd-menu")
            m := menu.getBoundingClientRect()
            win := this.Doc.parentWindow
            els := this.Doc.querySelectorAll(".list, .console, .tab-panel, .exp-body, #content, .card, .sort-list")
            loop els.length {
                e := els.item(A_Index - 1)
                ov := win.getComputedStyle(e).overflowY
                if (ov != "auto" && ov != "scroll")
                    continue
                if (e.scrollHeight <= e.clientHeight)
                    continue
                r := e.getBoundingClientRect()
                if (r.right < m.left || r.left > m.right || r.bottom < m.top || r.top > m.bottom)
                    continue
                if this._HasAncestorUid(dd, e.uniqueID)   ; the dropdown lives inside this scroller: leave it
                    continue
                e.style.msOverflowStyle := "none"
                this._shielded.Push(e)
            }
        }
    }
    _UnshieldScrollers() {
        for e in this._shielded
            try e.style.msOverflowStyle := ""
        this._shielded := []
    }
    _Unpress() {
        if IsObject(this._pressed) {
            try AxWindow._SetClass(this._pressed, "pressed", false)
            this._pressed := ""
        }
    }
    ; --- autocomplete --------------------------------------------------
    ; <div data-role="autocomplete" data-strict="1"><input><div class="dd-menu ac-menu"><div class="dd-item" data-value>..</div></div></div>
    _AcItems(ac) => ac.querySelectorAll(".dd-item")
    ; is the mouse cursor over this element (CSS px, DPI-aware)?
    _MouseInEl(el) {
        if !IsObject(el)
            return false
        try {
            pt := Buffer(8)
            DllCall("GetCursorPos", "Ptr", pt)
            DllCall("ScreenToClient", "Ptr", this.Gui.Hwnd, "Ptr", pt)
            scale := A_ScreenDPI / 96
            return this._PointIn(el, NumGet(pt, 0, "Int") / scale, NumGet(pt, 4, "Int") / scale)
        }
        return false
    }
    _AcPoll() {
        ac := this._acFocus
        if !IsObject(ac)
            return
        try v := ac.querySelector("input").value
        catch
            return
        if (v = this._acLast)
            return
        this._acLast := v
        this._AcFilter(ac, v)
    }
    _AcFilter(ac, text) {
        items := this._AcItems(ac), shown := 0, exact := false
        loop items.length {
            it := items.item(A_Index - 1)
            hit := (text = "" || InStr(it.innerText, text))
            AxWindow._SetClass(it, "hide", !hit)
            AxWindow._SetClass(it, "hl", false)
            shown += hit
            if (hit && it.innerText = text)
                exact := true
        }
        if (shown = 1 && exact)                 ; the text already is the only match: nothing to suggest
            shown := 0
        if shown {
            if !(IsObject(this._ddOpen) && this._ddOpen.uniqueID = ac.uniqueID) {
                this._CloseDropdown()
                AxWindow._SetClass(ac, "open", true)
                this._ddOpen := ac
                this._ShieldScrollers(ac)
                ; Trident can paint a freshly shown scrollable popup before its
                ; layout settles (looks translucent, hit-tests wrong): settle it now
                try {
                    menu := ac.querySelector(".dd-menu")
                    h := menu.offsetHeight, menu.scrollTop := 0
                    menu.style.display := "block"
                }
            }
        } else if (IsObject(this._ddOpen) && this._ddOpen.uniqueID = ac.uniqueID)
            this._CloseDropdown()
    }
    _AcKey(ac, inp, ev) {
        k := ev.keyCode
        if (k = 38 || k = 40) {
            if !(IsObject(this._ddOpen) && this._ddOpen.uniqueID = ac.uniqueID)
                this._AcFilter(ac, inp.value)
            items := this._AcItems(ac), vis := [], cur := 0
            loop items.length {
                it := items.item(A_Index - 1)
                if !AxWindow._HasClass(it, "hide") {
                    vis.Push(it)
                    if AxWindow._HasClass(it, "hl")
                        cur := vis.Length
                }
            }
            if vis.Length {
                nxt := Max(1, Min(vis.Length, cur + (k = 40 ? 1 : -1)))
                for i, it in vis
                    AxWindow._SetClass(it, "hl", i = nxt)
                try vis[nxt].scrollIntoView(false)
            }
            ev.returnValue := false
        } else if (k = 13) {
            hl := ac.querySelector(".dd-item.hl")
            if IsObject(hl)
                this._AcPick(ac, hl)
            else {
                first := ""
                if (AxWindow._Attr(ac, "data-strict") != "") {   ; strict: Enter takes the first match
                    items := this._AcItems(ac)
                    loop items.length
                        if !AxWindow._HasClass(items.item(A_Index - 1), "hide") {
                            first := items.item(A_Index - 1)
                            break
                        }
                }
                if IsObject(first)
                    this._AcPick(ac, first)
                else
                    this._AcCommit(ac)
            }
            ev.returnValue := false
        } else if (k = 27) {
            this._CloseDropdown()
            ev.returnValue := false
        } else if (k = 9)
            this._CloseDropdown()                                ; Tab away: normal commit on focusout
    }
    _AcPick(ac, it) {
        inp := ac.querySelector("input")
        inp.value := it.innerText, this._acLast := it.innerText     ; the poll must not re-filter on this
        this._AcSet(ac, AxWindow._Attr(it, "data-value"))
        this._CloseDropdown()
        try inp.focus()
    }
    ; focus left / Enter: strict keeps only an exact label, free text is the value
    _AcCommit(ac) {
        isOpen := IsObject(this._ddOpen) && this._ddOpen.uniqueID = ac.uniqueID
        if isOpen {
            ; the list is still open, so nothing outside was pressed (that
            ; closes it at once): focus went to the list itself (scrollbar)
            inside := false
            try inside := this._HasAncestorUid(this._acHover, ac.uniqueID)
            if !inside
                inside := this._MouseInEl(ac) || this._MouseInEl(ac.querySelector(".dd-menu"))
            r := this._ClosestRole(this._acHover)
            if (inside && this._acDown && r && r.role = "dd-item" && !AxWindow._HasClass(r.el, "hide")) {
                this._acDown := false
                this._AcPick(ac, r.el)
                return
            }
            if GetKeyState("LButton", "P") {                     ; still dragging the scrollbar
                SetTimer(ObjBindMethod(this, "_AcCommit", ac), -150)
                return
            }
            if !this._dlg {                                      ; give the caret back to the box, list stays open
                this._acDown := false
                try ac.querySelector("input").focus()
                return
            }
            this._CloseDropdown()
        }
        this._acDown := false
        inp := ac.querySelector("input"), text := inp.value, match := ""
        items := this._AcItems(ac)
        loop items.length {
            it := items.item(A_Index - 1)
            if (it.innerText = text) {
                match := AxWindow._Attr(it, "data-value")
                break
            }
        }
        if (match != "")
            this._AcSet(ac, match)
        else if (AxWindow._Attr(ac, "data-strict") != "")
            inp.value := "", this._AcSet(ac, "")
        else
            this._AcSet(ac, text)
    }
    _AcSet(ac, value) {
        if (AxWindow._Attr(ac, "data-value") = value)
            return
        ac.setAttribute("data-value", value)
        this._FireValue(ac, value)
    }
    ; SetOptions(id, "a:A|b:B" or Array): the options of an autocomplete, a
    ; drop-down or a list box, replaced
    SetOptions(id, options) {
        el := this.El(id), items := ""
        box := "", cls := "dd-item"
        try box := el.querySelector(".ac-menu")
        if !IsObject(box)
            try box := el.querySelector(".dd-menu")
        if !IsObject(box)
            box := el, cls := "list-item"                ; a list box holds its items itself
        for o in AxTags.Options(IsObject(options) ? AxTags.JoinOptions(options) : options)
            items .= '<div class="' cls '" data-value="' AxTags.E(o[1]) '">' AxTags.E(o[2]) '</div>'
        box.innerHTML := items
        return this
    }
    _CloseDropdown() {
        if IsObject(this._ddOpen) {
            try this._ddOpen.querySelector(".dd-menu").style.display := ""
            try AxWindow._SetClass(this._ddOpen, "open", false)
        }
        this._ddOpen := ""
        this._UnshieldScrollers()
    }
    ; select an item by value in a dropdown / list / palette container
    _SelectItem(cont, role, value, itemEl := "") {
        cls := (role = "dropdown") ? ".dd-item" : (role = "list") ? ".list-item" : ".swatch"
        items := cont.querySelectorAll(cls)
        label := ""
        loop items.length {
            it := items.item(A_Index - 1)
            on := (AxWindow._Attr(it, "data-value") = value)
            AxWindow._SetClass(it, "selected", on)
            if on
                label := it.innerText
        }
        cont.setAttribute("data-value", value)
        if (role = "dropdown") {
            v := cont.querySelector(".dd-value")
            if IsObject(v)
                v.innerText := label
        }
        this._UpdateOut(cont, value)
        this._FireValue(cont, value)
    }
    ; multi-select list: data-value = values joined with "|", callbacks get an Array
    _CommitMulti(lst) {
        vals := [], joined := ""
        items := lst.querySelectorAll(".list-item")
        loop items.length {
            it := items.item(A_Index - 1)
            if AxWindow._HasClass(it, "selected") {
                v := AxWindow._Attr(it, "data-value")
                vals.Push(v), joined .= (joined = "" ? "" : "|") v
            }
        }
        lst.setAttribute("data-value", joined)
        this._FireValue(lst, vals)
    }
    ; numberbox: one step up (dir 1) or down (-1), from an arrow key or a spin
    ; button. Shift takes the BigStep and Ctrl the SmallStep, each falling back
    ; to Step when the box was not given one. The sum is rounded to the step's
    ; own decimals, so 0.1 + 0.2 shows 0.3 rather than 0.30000000000000004.
    _NumberStep(nb, dir, ev := "") {
        inp := nb.querySelector("input")
        step := AxWindow._Attr(inp, "data-step")
        shift := false, ctrl := false
        try shift := ev.shiftKey
        try ctrl := ev.ctrlKey
        alt := shift ? AxWindow._Attr(inp, "data-bigstep") : ctrl ? AxWindow._Attr(inp, "data-smallstep") : ""
        if (alt != "" && IsNumber(alt))
            step := alt
        if (step = "" || !IsNumber(step))
            step := 1
        cur := inp.value, cur := (cur = "" || !IsNumber(cur)) ? 0 : cur
        Decimals(x) => (p := InStr(x, ".")) ? StrLen(x) - p : 0
        dp := Max(Decimals(String(step)), Decimals(String(cur)))
        v := Number(cur) + dir * Number(step)
        this._SetInput(nb, dp ? Round(v, dp) : Round(v))
    }
    ; numberbox / slider: set, clamp, reflect
    _SetInput(cont, value) {
        inp := cont.querySelector("input")
        mn := AxWindow._Attr(inp, "data-min"), mx := AxWindow._Attr(inp, "data-max")
        if (mn = "")
            mn := AxWindow._Attr(inp, "min")
        if (mx = "")
            mx := AxWindow._Attr(inp, "max")
        value := RegExReplace(value, "[^0-9.\-]")
        v := (value = "" || !IsNumber(value)) ? 0 : Number(value)
        if (mn != "" && v < Number(mn))
            v := Number(mn)
        if (mx != "" && v > Number(mx))
            v := Number(mx)
        inp.value := v
        this._UpdateOut(cont, v)
        this._FireValue(cont, v)
    }
    _UpdateOut(cont, value) {
        out := AxWindow._Attr(cont, "data-out")
        if (out = "")
            return
        ; fires on every step of a slider drag, so it takes the fast text path
        try AxWindow._SetText(this.Doc.getElementById(out), value AxWindow._Attr(cont, "data-suffix"))
    }
    ; A text box's value, when it is not what it was the last time it said
    _TypedIn(el) {
        if !AxWindow._IsTextBox(el)
            return
        id := ""
        try id := el.id
        if (id = "" || !this._valueCbs.Has(id))
            return
        if !this.HasOwnProp("_typed")
            this._typed := Map()
        v := el.value
        if (this._typed.Has(id) && this._typed[id] == v)
            return
        this._typed[id] := v
        this._FireValue(el, v)
    }
    _FireValue(cont, value) {
        try id := cont.id
        catch
            return
        if (id != "" && this._valueCbs.Has(id))
            for fn in this._valueCbs[id].Clone()
                fn(value, cont)
    }
    ; nearest clickable component part: explicit data-role, or one of the
    ; class-named item types (dd-item, list-item, tab, swatch)
    _ClosestRole(el) {
        loop 16 {
            if !IsObject(el)
                return ""
            for c in AxWindow.ClickParts
                if AxWindow._HasClass(el, c)
                    return {role: c, el: el}
            r := AxWindow._Attr(el, "data-role")
            if (r != "" && !AxWindow.ClickBoxes.Has(r))
                return {role: r, el: el}
            el := AxWindow._ParentEl(el)
        }
        return ""
    }
    _RoleAncestor(el, role) {
        loop 16 {
            if !IsObject(el)
                return ""
            if (AxWindow._Attr(el, "data-role") = role)
                return el
            el := AxWindow._ParentEl(el)
        }
        return ""
    }
    _HasAncestorUid(el, uid) {
        loop 16 {
            if !IsObject(el)
                return false
            try {
                if (el.uniqueID = uid)
                    return true
            } catch
                return false
            el := AxWindow._ParentEl(el)
        }
        return false
    }
}
