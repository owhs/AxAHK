#Requires AutoHotkey v2.0
; AxWindow.Embed.ahk — dock native ActiveX controls inside the HTML page.
;
;   obj := win.Embed("dockId", "Shell.Explorer.2")   ; returns the COM object
;   obj.Navigate("https://example.com")
;
; The control is a real child window of the Gui, kept aligned with the page
; element whose id you pass (any block element; give it a size). It follows
; window resizes, page switches, scrolling and expander toggles, clips to the
; content area so it never covers the title bar, and hides while a dialog is
; open so the dialog stays on top. Anything you can host in Gui.Add("ActiveX")
; works: WMPlayer.OCX, another Shell.Explorer.2, third-party OCX controls...
class AxWindowEmbed {
    ; ----------------------------------------------------------------- public
    ; Is this ProgID / CLSID registered? The ActiveX host silently falls back
    ; to a web browser for unknown ids, so check before you pick a control.
    static HasControl(progId) {
        try {
            if (SubStr(progId, 1, 1) = "{")
                return RegRead("HKCR\CLSID\" progId "\InprocServer32") != ""
            return RegRead("HKCR\" progId "\CLSID") != ""
        }
        return false
    }
    ; opts.Sink: an object whose methods receive the control's COM events
    Embed(id, progId, opts := "") {
        this._EnsureEmbeds()
        if this._embeds.Has(id)
            this.RemoveEmbed(id)
        ctl := this.Gui.Add("ActiveX", "x0 y0 w16 h16 Hidden", progId)
        ; the page's browser must not paint over its new sibling: clip siblings
        ; on the host (and children on the Gui), then put the dock on top
        for h in [this.Ax.Hwnd, this.Gui.Hwnd] {
            st := DllCall("GetWindowLongPtr", "Ptr", h, "Int", -16, "Ptr")
            DllCall("SetWindowLongPtr", "Ptr", h, "Int", -16, "Ptr", st | 0x04000000 | 0x02000000)   ; WS_CLIPSIBLINGS | WS_CLIPCHILDREN
        }
        DllCall("SetWindowPos", "Ptr", ctl.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)   ; HWND_TOP, no move/size/activate
        e := {Id: id, Ctl: ctl, Obj: ctl.Value, Last: "", Visible: true, Sink: "", StretchH: 0}
        ; A web browser reports every script error on a page it shows as a
        ; dialog of its own ("An error has occurred in the script on this
        ; page... Do you want to continue?"), and most sites have one. The
        ; window's own browser is kept quiet the same way.
        try e.Obj.Silent := true
        if (IsObject(opts) && opts.HasOwnProp("Sink") && IsObject(opts.Sink)) {
            e.Sink := opts.Sink
            ComObjConnect(e.Obj, e.Sink)
        }
        this._embeds[id] := e
        this._LayoutEmbeds()
        SetTimer(this._embedFn, 60)
        return e.Obj
    }
    ; asked before anything was embedded: nothing, rather than an error
    EmbedObj(id)  => (this.HasOwnProp("_embeds") && this._embeds.Has(id)) ? this._embeds[id].Obj : ""
    EmbedCtl(id)  => (this.HasOwnProp("_embeds") && this._embeds.Has(id)) ? this._embeds[id].Ctl : ""
    EmbedHwnd(id) => (this.HasOwnProp("_embeds") && this._embeds.Has(id)) ? this._embeds[id].Ctl.Hwnd : 0
    ; ShowEmbed(id, false) hides the control without destroying it
    ShowEmbed(id, on := true) {
        if (this.HasOwnProp("_embeds") && this._embeds.Has(id)) {
            this._embeds[id].Visible := on
            this._embeds[id].Last := ""
            this._LayoutEmbeds()
        }
        return this
    }
    RemoveEmbed(id) {
        if (!this.HasOwnProp("_embeds") || !this._embeds.Has(id))
            return this
        e := this._embeds.Delete(id)
        if IsObject(e.Sink)
            try ComObjConnect(e.Obj)
        try DllCall("DestroyWindow", "Ptr", e.Ctl.Hwnd)
        if !this._embeds.Count
            SetTimer(this._embedFn, 0)
        return this
    }
    ; ---------------------------------------------------------------- private
    _EnsureEmbeds() {
        if !this.HasOwnProp("_embeds") {
            this._embeds := Map()
            this._embedFn := ObjBindMethod(this, "_LayoutEmbeds")
        }
    }
    ; Called on a short timer and directly from resize/page-change: moves each
    ; control onto its placeholder's current rectangle (CSS px == Gui logical
    ; px, both scale with the DPI), clipped to the #content viewport.
    _LayoutEmbeds(*) {
        if !this.HasOwnProp("_embeds") || !this._embeds.Count
            return
        if this.Closing {
            SetTimer(this._embedFn, 0)
            return
        }
        if !IsObject(this.Doc) || !this.Ready
            return
        cx1 := 0, cy1 := 0, cx2 := 1e9, cy2 := 1e9, c := ""
        try {
            c := this.Doc.getElementById("content")
            if IsObject(c) {
                cr := c.getBoundingClientRect()
                cx1 := cr.left, cy1 := cr.top, cx2 := cr.right, cy2 := cr.bottom
            }
        }
        covered := this._dlg ? true : false                 ; dialogs must stay on top
        for id, e in this._embeds {
            show := e.Visible && !covered
            x := 0, y := 0, w := 0, h := 0
            if show {
                try {
                    el := this.Doc.getElementById(id)
                    if (!IsObject(el) || !IsObject(el.offsetParent))
                        show := false
                    else {
                        r := el.getBoundingClientRect()
                        ; class "stretch": grow the placeholder to the bottom of the content area
                        if (IsObject(c) && AxWindow._HasClass(el, "stretch")) {
                            top := r.top - cy1 + c.scrollTop
                            below := 0                        ; whatever the page puts under the dock
                            try {
                                line := el.parentElement, pg := line.parentElement
                                below := pg.getBoundingClientRect().bottom - line.getBoundingClientRect().bottom
                            }
                            hh := Max(120, Round(c.clientHeight - top - below - 30))   ; 24px content padding + slack
                            if (hh != e.StretchH) {
                                e.StretchH := hh
                                el.style.height := hh "px"
                                r := el.getBoundingClientRect()
                            }
                        }
                        x := Max(r.left, cx1), y := Max(r.top, cy1)
                        w := Min(r.right, cx2) - x, h := Min(r.bottom, cy2) - y
                        if (w < 2 || h < 2)
                            show := false
                    }
                } catch
                    show := false
            }
            key := show ? Round(x) "," Round(y) "," Round(w) "," Round(h) : "hidden"
            if (key = e.Last)
                continue
            e.Last := key
            try {
                if show {
                    e.Ctl.Move(Round(x), Round(y), Round(w), Round(h))
                    e.Ctl.Visible := true
                } else
                    e.Ctl.Visible := false
            }
        }
    }
}
