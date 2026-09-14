#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; ============================================================================
;  AxPicture.ahk -- Plain picture.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxPicture.ahk     what g.AddImageButton() writes
;      Picture.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxPicture {
    static _reg := AxRich.Register("Picture", "",
                                   (*) => AxPicture._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddPicture", (c, a*) => AxPicture._Picture(c, a*))
        return true
    }

    static _Picture(c, opts := "", src := "") {
        o := c._Opt(opts, "pic")
        return c._Reg(o, "Picture", '<img' c._Common(o, "ax-pic") ' src="' AxTags.E(src) '">')
        }
}
