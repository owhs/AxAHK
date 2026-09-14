#Requires AutoHotkey v2.0
; =============================================================================
;  AxWindow.Media.ahk — pictures and vector graphics mixed into AxWindow.
;
;  Trident happily shows PNG, JPEG, animated GIF, BMP, ICO and (IE9+) SVG,
;  both inline and through <img src>. What it does not give a script-free
;  page is any idea of whether a picture arrived, so SetImage() tracks that
;  from AHK: it swaps the source, watches the element until it is complete
;  (or the timeout runs out) and moves the surrounding .imgbox between the
;  classes "loading", "loaded" and "failed" — which is all the CSS needs to
;  show a spinner, the picture, or a "could not load" placeholder.
;
;      win.SetImage("hero", "https://example.com/a.png",
;                   {OnLoad: (id, src) => ..., OnError: (id, src) => ...,
;                    Timeout: 8000, Fail: "Offline?"})
;      win.SetImage("hero", A_MyDocuments "\photo.jpg")     ; local paths too
;
;  Vector graphics need no helper of their own: inline <svg> is part of the
;  document, so El/Attr/Style/AddClass and On("click", id, fn) work on
;  individual shapes exactly as they do on HTML. AxGui's AddSvg() drops the
;  markup in; SvgSet() is a thin wrapper around setAttribute for readability.
; =============================================================================
class AxWindowMedia {
    ; ----------------------------------------------------------------- public
    ; Point an <ax-image> (or a bare <img>) at a new source and follow it.
    ; opts: {OnLoad: fn(id, src), OnError: fn(id, src), Timeout: 10000,
    ;        Fail: "message shown on failure", Alt: "message while loading"}
    SetImage(id, src, opts := "") {
        this._EnsureMedia()
        pair := this._ImgPair(id)
        if !pair
            return this
        o := (n, d := "") => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        url := AxWindow.FileUrl(src)
        this._ImgMsg(pair.Box, ".img-alt", o("Alt", "Loading…"))
        if (o("Fail", "") != "")                   ; else keep the tag's own wording
            this._ImgMsg(pair.Box, ".img-fail", o("Fail", ""))
        this._ImgState(pair.Box, "loading")
        try {
            pair.Img.removeAttribute("src")        ; force a reload even for the same url
            pair.Img.src := url
        }
        this._media[id] := {Img: pair.Img, Box: pair.Box, Src: url, Start: A_TickCount,
            Timeout: o("Timeout", 10000), OnLoad: o("OnLoad", ""), OnError: o("OnError", "")}
        SetTimer(this._mediaFn, 100)
        return this
    }
    ; "loading" | "loaded" | "failed" | "" (nothing set yet)
    ImageState(id) {
        pair := this._ImgPair(id)
        if !pair
            return ""
        for s in ["loading", "loaded", "failed"]
            if AxWindow._HasClass(pair.Box, s)
                return s
        return ""
    }
    ; Empty a picture and drop it back to the placeholder look.
    ClearImage(id, message := "") {
        this._EnsureMedia()
        pair := this._ImgPair(id)
        if !pair
            return this
        if this._media.Has(id)                   ; Map.Delete throws on a missing key
            this._media.Delete(id)
        try pair.Img.removeAttribute("src")
        if (message != "")
            this._ImgMsg(pair.Box, ".img-alt", message)
        this._ImgState(pair.Box, "")
        return this
    }
    ; A local path as a file:/// URL Trident accepts; anything that already
    ; looks like a URL (or a data: URI) is handed back unchanged.
    static FileUrl(path) => AxSys.FileUrl(path)
    ; A local image as a data: URI — handy when a file may be moved or
    ; deleted right after it was dropped (Trident keeps file URLs open).
    static ImageDataUri(path, maxBytes := 4194304) {
        static mime := Map("png", "image/png", "jpg", "image/jpeg", "jpeg", "image/jpeg", "gif", "image/gif",
            "bmp", "image/bmp", "ico", "image/x-icon", "svg", "image/svg+xml")
        try {
            if (!FileExist(path) || FileGetSize(path) > maxBytes)
                return ""
            SplitPath(path, , , &ext)
            ext := StrLower(ext)
            if !mime.Has(ext)
                return ""
            f := FileOpen(path, "r")
            buf := Buffer(f.Length, 0)
            f.RawRead(buf, f.Length)
            f.Close()
            len := 0
            DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size, "UInt", 0x40000001, "Ptr", 0, "UInt*", &len)
            out := Buffer(len * 2, 0)
            DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size, "UInt", 0x40000001, "Ptr", out, "UInt*", &len)
            return "data:" mime[ext] ";base64," StrGet(out, "UTF-16")
        }
        return ""
    }

    ; ---------------------------------------------------------------- vectors
    ; SvgSet("bar3", "fill", "#60cdff") — setAttribute, spelled for SVG.
    ; (SVG nodes have no writable className, so AxWindow's class helpers fall
    ; back to the class attribute; AddClass/RemoveClass work on them too.)
    SvgSet(id, name, value) {
        try this.El(id).setAttribute(name, value)
        return this
    }
    SvgGet(id, name) => AxWindow._Attr(this.El(id), name)
    ; The text of an SVG <text> node (innerText does not apply to SVG).
    SvgText(id, text) {
        el := this.El(id)
        try {
            el.textContent := text
            return this
        }
        try {
            while IsObject(el.firstChild)
                el.removeChild(el.firstChild)
            el.appendChild(el.ownerDocument.createTextNode(text))
        }
        return this
    }
    ; Replace the contents of an <svg> (or of any container holding one).
    Svg(id, markup) {
        el := this.El(id)
        try {
            if (el.tagName = "svg" || el.tagName = "SVG") {
                ; Trident refuses innerHTML on an <svg> node: rebuild the wrapper
                el.parentNode.innerHTML := markup
                return this
            }
            el.innerHTML := markup
        }
        return this
    }

    ; ------------------------------------------------------------- thumbnails
    ; Markup for a strip of picture thumbnails (theme class .thumbs/.thumb).
    ; opts: {Size: 96, Removable, Captions: true, IdPrefix: "th",
    ;        Empty: "shown when the list is empty"}
    ThumbsHtml(files, opts := "") {
        o := (n, d := "") => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        if !files.Length
            return '<div class="fl-empty">' AxWindow._Esc(o("Empty", "No pictures yet.")) '</div>'
        pre := o("IdPrefix", "thumb"), size := o("Size", 96), caps := o("Captions", true), h := ""
        for i, f in files {
            SplitPath(f, &name)
            h .= '<span class="thumb drag-item" id="' AxWindow._Esc(pre "_" i) '" data-value="' AxWindow._Esc(f) '"'
                . ' data-tip="' AxWindow._Esc(f) '" style="width:' size 'px">'
                . '<span class="thumb-img" style="height:' size 'px">'
                . '<img src="' AxWindow._Esc(AxWindow.FileUrl(f)) '" alt=""></span>'
                . (caps ? '<span class="thumb-cap">' AxWindow._Esc(name) '</span>' : "")
                . (o("Removable", false) ? '<span class="remove ico" data-role="remove-item">&#xE8BB;</span>' : "")
                . '</span>'
        }
        return h
    }
    SetThumbs(id, files, opts := "") {
        try this.Html(id, this.ThumbsHtml(files, opts))
        return this
    }

    ; ---------------------------------------------------------------- private
    _EnsureMedia() {
        if !this.HasOwnProp("_media") {
            this._media := Map()
            this._mediaFn := ObjBindMethod(this, "_MediaTick")
        }
    }
    ; id may name the <ax-image> box or the <img> itself
    _ImgPair(id) {
        try {
            el := this.El(id)
            if !IsObject(el)
                return ""
            if (StrUpper(el.tagName) = "IMG")
                return {Img: el, Box: this._ClosestClass(el, "imgbox") || el}
            img := el.querySelector("img")
            return IsObject(img) ? {Img: img, Box: el} : ""
        }
        return ""
    }
    _ImgState(box, state) {
        for s in ["loading", "loaded", "failed"]
            AxWindow._SetClass(box, s, s = state)
    }
    _ImgMsg(box, sel, text) {
        try {
            el := box.querySelector(sel)
            if IsObject(el)
                el.innerText := text
        }
    }
    ; Trident fires no reliable load/error event for an <img> that is written
    ; into the document from outside, so the state is polled: readyState turns
    ; "complete" either way and naturalWidth separates the two outcomes.
    _MediaTick() {
        if (!this.HasOwnProp("_media") || !this._media.Count || this.Closing) {
            SetTimer(this._mediaFn, 0)
            return
        }
        for id, m in this._media.Clone() {
            done := "", w := -1
            try {
                rs := ""
                try rs := m.Img.readyState
                try w := m.Img.naturalWidth
                if (w < 0)
                    try w := (m.Img.fileSize != -1) ? 1 : 0      ; IE's own "did it arrive" flag
                if (w < 0)
                    w := 1                                        ; neither is available: trust "complete"
                done := (m.Img.complete || rs = "complete") ? (w > 0 ? "loaded" : "failed") : ""
            } catch
                done := "failed"
            if (done = "" && A_TickCount - m.Start > m.Timeout)
                done := "failed"
            if (done = "")
                continue
            this._media.Delete(id)
            this._ImgState(m.Box, done)
            cb := (done = "loaded") ? m.OnLoad : m.OnError
            if cb
                try cb(id, m.Src)
        }
        if !this._media.Count
            SetTimer(this._mediaFn, 0)
    }
}
