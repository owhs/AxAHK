#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Rating\AxRating.css, AX_COMPONENTS_RATING_AXRATING_CSS

; ============================================================================
;  AxRating.ahk -- Rating.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxRating.ahk     what g.AddRating() writes, the markup that becomes and
;                       what a click on it does
;      AxRating.css     its shape -- the theme says what it looks like
;      Rating.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxRating {
    static _reg := AxRich.Register("Rating", "components\Rating\AxRating.css",
                                   (*) => AxRating._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddRating", (c, a*) => AxRating._Rating(c, a*))
        AxTags.Register("ax-rating", 30, (el, inner, id) => AxRating._Tag("ax-rating", el, inner, id))
        AxWindow.RegisterClick("star", (w, el, t, ev) => AxRating._Click("star", w, el, t, ev), true)
        AxWindow.RegisterBox("rating")
        return true
    }

    static _Rating(c, opts := "", value := 0) {
        o := c._Opt(opts, "rate")
        return c._Reg(o, "Rating", '<ax-rating' c._Common(o) ' max="' c._Kv(o, "max", 5) '" value="' value '"' (o.KV.Has("out") ? ' out="' o.KV["out"] '"' : "") '></ax-rating>')
        }

    ; ---- the markup <ax-rating> becomes -------------------------------
    static _Tag(tag, el, inner, id) {
        A := (el, n, d := "") => AxTags.A(el, n, d)
        E := (x) => AxTags.E(x)
        Has := (el, n) => AxTags.Has(el, n)
        Root := (el, c, withId := true, extra := "") => AxTags.Root(el, c, withId, extra)
        Ico := (g, c := "ico") => AxTags.Ico(g, c)
        switch tag {
        case "ax-rating":
            max := Integer(A(el, "max", "5")), val := Integer(A(el, "value", "0")), stars := ""
            loop max
                stars .= '<span class="star' (A_Index <= val ? " on" : "") '"></span>'
            return '<div' Root(el, "rating", true, ' data-role="rating" data-value="' val '"' (A(el, "out") != "" ? ' data-out="' E(A(el, "out")) '"' : "")) '>' stars '</div>'
        }
        return inner
    }

    ; ---- what a click on it does ---------------------------------
    ; `win` is the AxWindow: these ran as its own methods before the
    ; control moved out here, and still reach everything they did.
    static _Click(role, win, el, t, ev) {
        switch role {
        case "star":
            rt := win._RoleAncestor(t, "rating")
            if !rt
                return
            stars := rt.querySelectorAll(".star"), val := 0
            loop stars.length
                if (stars.item(A_Index - 1).uniqueID = t.uniqueID)
                    val := A_Index
            loop stars.length
                AxWindow._SetClass(stars.item(A_Index - 1), "on", A_Index <= val)
            rt.setAttribute("data-value", val)
            win._UpdateOut(rt, val)
            win._FireValue(rt, val)
        }
    }
}
