#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Image\AxImage.css, AX_COMPONENTS_IMAGE_AXIMAGE_CSS

; ============================================================================
;  AxImage.ahk -- Image.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxImage.ahk     what g.AddImage() writes and the markup that becomes
;      AxImage.css     its shape -- the theme says what it looks like
;      Image.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxImage {
    static _reg := AxRich.Register("Image", "components\Image\AxImage.css",
                                   (*) => AxImage._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddImage", (c, a*) => AxImage._Image(c, a*))
        AxRich.AddMethod("AddImageButton", (c, a*) => AxImage._ImageButton(c, a*))
        AxTags.Register("ax-image", 34, (el, inner, id) => AxImage._Tag("ax-image", el, inner, id))
        return true
    }

    static _Image(c, opts := "", src := "") {
        o := c._Opt(opts, "img")
        return c._Reg(o, "Image", '<ax-image' c._Common(o) ' src="' AxTags.E(src) '"'
            . ' fit="' c._Kv(o, "fit", "cover") '" alt="' AxTags.E(c._Kv(o, "alt", "No image")) '"'
            . ' fail="' AxTags.E(c._Kv(o, "fail", "Could not load this image.")) '"'
            . (o.KV.Has("caption") ? ' caption="' AxTags.E(o.KV["caption"]) '"' : "")
            . (o.KV.Has("icon") ? ' icon="' o.KV["icon"] '"' : "")
            . (o.Flags.Has("button") ? " button" : "") (o.Flags.Has("round") ? " round" : "") '></ax-image>')
        }

    ; the same picture, clickable
    static _ImageButton(c, opts := "", src := "") => c.AddImage(opts " Button", src)

    ; ---- the markup <ax-image> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-image":
            ; the box owns the id, so On("click", id) works for image buttons
            ; and SetImage(id) finds both the <img> and the state classes
            src := AxSys.FileUrl(A(el, "src")), fit := A(el, "fit", "cover")
            st := (A(el, "w") != "" ? "width:" A(el, "w") "px;" : "")
                . (A(el, "h") != "" ? "height:" A(el, "h") "px;" : "") E(A(el, "style"))
            cls := "imgbox fit-" (fit = "contain" ? "contain" : "cover")
                . (Has(el, "button") ? " button" : "") (Has(el, "round") ? " round" : "")
                . (src != "" ? " loaded" : "")
                . (A(el, "class") != "" ? " " E(A(el, "class")) : "")
            return '<span class="' cls '"' (id != "" ? ' id="' E(id) '"' : "") ' data-role="image"'
                . (st != "" ? ' style="' st '"' : "") (A(el, "tip") != "" ? ' data-tip="' E(A(el, "tip")) '"' : "") '>'
                . '<img class="img" alt=""' (src != "" ? ' src="' E(src) '"' : "") '>'
                . '<span class="img-overlay"><span class="img-inner"><span class="ring-spinner"></span>'
                . '<span class="ico img-badge">&#x' A(el, "icon", "EB9F") ';</span>'
                . '<span class="img-alt">' E(A(el, "alt", "No image")) '</span>'
                . '<span class="img-fail">' E(A(el, "fail", "Could not load this image.")) '</span></span></span>'
                . (A(el, "caption") != "" ? '<span class="img-cap">' E(A(el, "caption")) '</span>' : "") inner '</span>'
        }
        return inner
    }
}
