#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; ============================================================================
;  AxEdit.ahk -- Text box.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxEdit.ahk     what g.AddEdit() writes and the markup that becomes
;      Edit.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxEdit {
    static _reg := AxRich.Register("Edit", "",
                                   (*) => AxEdit._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddEdit", (c, a*) => AxEdit._Edit(c, a*))
        AxTags.Register("ax-text", 16, (el, inner, id) => AxEdit._Tag("ax-text", el, inner, id))
        AxTags.Register("ax-textarea", 17, (el, inner, id) => AxEdit._Tag("ax-textarea", el, inner, id))
        return true
    }

    static _Edit(c, opts := "", text := "") {
        o := c._Opt(opts, "edit")
        if (o.KV.Has("rows") || o.Flags.Has("multi"))
            return c._Reg(o, "Edit", '<ax-textarea' c._Common(o) ' rows="' c._Kv(o, "rows", 3) '" placeholder="' AxTags.E(c._Kv(o, "placeholder")) '"'
                 . (o.Flags.Has("readonly") ? " readonly" : "") '>' AxTags.E(text) '</ax-textarea>')
        return c._Reg(o, "Edit", '<ax-text' c._Common(o) ' value="' AxTags.E(text) '" placeholder="' AxTags.E(c._Kv(o, "placeholder")) '"' (o.Flags.Has("readonly") ? " readonly" : "") '></ax-text>')
        }

    ; ---- the markup <ax-text> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-text":
            return '<div' Root(el, "textbox", false) '><input type="text"' (id != "" ? ' id="' E(id) '"' : "") ' value="' E(A(el, "value")) '"'
                . ' placeholder="' E(A(el, "placeholder")) '"' (Has(el, "readonly") ? " readonly" : "") '></div>'
        case "ax-textarea":
            return '<div' Root(el, "textbox", false) '><textarea' (id != "" ? ' id="' E(id) '"' : "") ' rows="' E(A(el, "rows", "3")) '"'
                . ' placeholder="' E(A(el, "placeholder")) '"' (Has(el, "readonly") ? " readonly" : "") '>' inner '</textarea></div>'
        }
        return inner
    }
}
