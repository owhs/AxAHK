#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\FileList\AxFileList.css, AX_COMPONENTS_FILELIST_AXFILELIST_CSS

; ============================================================================
;  AxFileList.ahk -- File list.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxFileList.ahk     what g.AddFileList() writes and the markup that becomes
;      AxFileList.css     its shape -- the theme says what it looks like
;      FileList.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxFileList {
    static _reg := AxRich.Register("FileList", "components\FileList\AxFileList.css",
                                   (*) => AxFileList._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddFileList", (c, a*) => AxFileList._FileList(c, a*))
        AxTags.Register("ax-files", 36, (el, inner, id) => AxFileList._Tag("ax-files", el, inner, id))
        return true
    }

    static _FileList(c, opts := "", empty := "") {
        o := c._Opt(opts, "fl")
        hh := o.H, o.H := ""            ; hN caps the scroll height, it is not a fixed box
        return c._Reg(o, "FileList", '<ax-files' c._Common(o, o.W = "" ? "fill" : "")
            . (hh != "" ? ' height="' hh '"' : "") ' empty="' AxTags.E(empty != "" ? empty : "Nothing here yet.") '"></ax-files>')
        }

    ; ---- the markup <ax-files> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-files":
            st := (A(el, "height") != "" ? "max-height:" A(el, "height") "px;" : "") E(A(el, "style"))
            return '<div class="filelist' (A(el, "class") != "" ? " " E(A(el, "class")) : "") '"'
                . (id != "" ? ' id="' E(id) '"' : "") ' data-list="1"' (st != "" ? ' style="' st '"' : "") '>'
                . (inner != "" ? inner : '<div class="fl-empty">' E(A(el, "empty", "Nothing here yet.")) '</div>') '</div>'
        ; the two window bars: empty shells that MenuBar()/StatusBar() fill,
        ; so the menus and parts are declared in AHK rather than in markup
        }
        return inner
    }
}
