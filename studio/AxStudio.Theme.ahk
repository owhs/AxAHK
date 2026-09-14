#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\AxStudio.Lit.ahk

; Part of AxStudio, not a program on its own.
if (A_LineFile = A_ScriptFullPath) {
    SplitPath(A_LineFile, , &axDir)
    axEntry := axDir "\AxStudio.ahk"
    if FileExist(axEntry)
        Run('"' A_AhkPath '" "' axEntry '"')
    else
        MsgBox("Run studio\AxStudio.ahk -- this file is only one part of it.", "AxStudio")
    ExitApp()
}

; =============================================================================
;  AxStudio.Theme.ahk -- restyling a design without writing CSS.
;
;  A stylesheet is a whole look, chosen from a list. This is the layer above
;  it: the eight or nine things people actually want to change about the look
;  they picked -- the window's background, the colour of text, what a card
;  looks like, how round the corners are, the font, how much room the content
;  gets -- without leaving the studio and without forking a .css file.
;
;  Each token is one line of `Look`, authored the same way the menu bar and
;  the status bar are:
;
;      bg = #101418
;      radius = 10
;
;  and it becomes one CSS rule. `Css` beside it is free-form, for anything the
;  list does not cover. Together they are one small stylesheet that is layered
;  over the chosen one -- on the canvas, rescoped to the paper, and in the
;  exported script as a single SetExtraCss call.
;
;  Deliberately a layer and not an edit: the sheet underneath stays whichever
;  one you picked, so a fix to it still reaches the design, and turning the
;  whole thing off is clearing two fields.
; =============================================================================

class AxTheme {
    ; K   the key written into Look
    ; Sel the selector(s) it writes, Prop the property, Unit appended to a number
    static Inputs := ".textbox input, .textbox textarea, .dd-value, .numberbox input, .searchbox input, "
                   . ".hotkeybox input, .passwordbox input"
    static Fonts := "Segoe UI Variable Text:Segoe UI Variable|Segoe UI:Segoe UI|Tahoma:Tahoma|"
                  . "Verdana:Verdana|Arial:Arial|Calibri:Calibri|Georgia:Georgia|Cambria:Cambria|"
                  . "Consolas:Consolas|Cascadia Code:Cascadia Code|MS Sans Serif:MS Sans Serif (Windows 98)"
    ; G the group it is shown in on the Look page
    ; K the key written into Look, Sel the selector(s), Prop the property,
    ;   Unit appended to a number, Map a word to a value (shadows)
    static Fields := [
        {G: "Colours", K: "bg",     L: "Window background", Kind: "color", Sel: "body, #content", Prop: "background"},
        {G: "Colours", K: "fg",     L: "Text",              Kind: "color", Sel: "body",       Prop: "color"},
        {G: "Colours", K: "card",   L: "Cards and panels",  Kind: "color", Sel: ".card, .tile, .expander", Prop: "background"},
        {G: "Colours", K: "line",   L: "Their border",      Kind: "color", Sel: ".card, .tile, .expander", Prop: "border-color"},
        {G: "Colours", K: "input",  L: "Boxes you type in", Kind: "color", Sel: "@inputs",    Prop: "background"},
        {G: "Colours", K: "inline", L: "Their border",      Kind: "color", Sel: "@inputs",    Prop: "border-color"},
        {G: "Colours", K: "btn",    L: "Buttons",           Kind: "color", Sel: ".btn",       Prop: "background"},
        {G: "Colours", K: "btnfg",  L: "Button text",       Kind: "color", Sel: ".btn",       Prop: "color"},
        {G: "Colours", K: "sel",    L: "What is selected",  Kind: "color",
                       Sel: ".nav-item.active, .list-item.selected, .dd-item.selected, .tab.active", Prop: "background"},
        {G: "Colours", K: "rail",   L: "Page rail",         Kind: "color", Sel: "#sidebar",   Prop: "background"},
        {G: "Colours", K: "bar",    L: "Title bar",         Kind: "color", Sel: "#titlebar",  Prop: "background"},
        {G: "Colours", K: "barfg",  L: "Title bar text",    Kind: "color", Sel: "#titlebar, #titleText", Prop: "color"},
        {G: "Shape",   K: "radius", L: "Corner radius",     Kind: "num",
                       Sel: ".card, .btn, .dd-value, .tile, .expander, .textbox input, .numberbox input, .searchbox input",
                       Prop: "border-radius", Unit: "px"},
        {G: "Shape",   K: "bw",     L: "Border width",      Kind: "num",   Sel: ".card, .tile, .btn, .dd-value, .textbox input",
                       Prop: "border-width", Unit: "px"},
        {G: "Shape",   K: "shadow", L: "Card shadow",       Kind: "choice", Sel: ".card, .tile", Prop: "box-shadow",
                       Opts: "none:None|soft:Soft|lifted:Lifted|deep:Deep",
                       Map: Map("none", "none", "soft", "0 1px 3px rgba(0,0,0,.18)",
                                "lifted", "0 4px 12px rgba(0,0,0,.24)", "deep", "0 10px 28px rgba(0,0,0,.36)")},
        {G: "Type",    K: "font",   L: "Font",              Kind: "choice", Sel: "body",      Prop: "font-family",
                       Opts: "@fonts", Quote: true},
        {G: "Type",    K: "size",   L: "Text size",         Kind: "num",   Sel: "body",       Prop: "font-size", Unit: "px"},
        {G: "Space",   K: "pad",    L: "Room around the content", Kind: "num", Sel: "#content", Prop: "padding", Unit: "px"},
        {G: "Space",   K: "gap",    L: "Space between cards", Kind: "num", Sel: ".card",      Prop: "margin-bottom", Unit: "px"},
        {G: "Space",   K: "railw",  L: "Page rail width",   Kind: "num",   Sel: "#sidebar",   Prop: "width", Unit: "px"}]

    ; --- reading and writing one token --------------------------------
    static Get(w, key) {
        for line in StrSplit(StrReplace(String(w.Look), "`r", ""), "`n") {
            if !RegExMatch(Trim(line), "^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$", &m)
                continue
            if (m[1] = key)
                return Trim(m[2])
        }
        return ""
    }
    ; Rewrites the line in place, so the order the user sees never shuffles.
    static Set(w, key, value) {
        out := "", found := false
        v := Trim(String(value))
        for line in StrSplit(StrReplace(String(w.Look), "`r", ""), "`n") {
            t := Trim(line)
            if RegExMatch(t, "^([A-Za-z_][A-Za-z0-9_]*)\s*=", &m) && (m[1] = key) {
                found := true
                if (v = "")
                    continue                      ; cleared: drop the line
                out .= (out = "" ? "" : "`n") key " = " v
                continue
            }
            if (t != "")
                out .= (out = "" ? "" : "`n") t
        }
        if (!found && v != "")
            out .= (out = "" ? "" : "`n") key " = " v
        w.Look := out
    }

    ; --- the stylesheet it adds up to ---------------------------------
    static Css(w) {
        css := ""
        for f in AxTheme.Fields {
            v := AxTheme.Get(w, f.K)
            if (v = "")
                continue
            if (f.Kind = "num") {
                if !RegExMatch(v, "^-?\d+(\.\d+)?$")
                    continue
                v .= f.HasOwnProp("Unit") ? f.Unit : ""
            }
            if f.HasOwnProp("Map")
                v := f.Map.Has(v) ? f.Map[v] : ""
            if (v = "")
                continue
            if (f.HasOwnProp("Quote") && f.Quote)
                v := "'" StrReplace(v, "'", "") "', sans-serif"
            sel := (f.Sel = "@inputs") ? AxTheme.Inputs : f.Sel
            ; !important: the retro sheets scope every rule to their own body
            ; class, and a token has to win over them to do anything at all
            css .= sel " { " f.Prop ": " v " !important }`n"
            if (f.K = "bw")
                css .= sel " { border-style: solid !important }`n"
        }
        extra := Trim(String(w.Css), " `t`r`n")
        if (extra != "")
            css .= extra "`n"
        return css
    }
    static Any(w) => Trim(AxTheme.Css(w)) != ""

    ; A starting point taken from the sheet already in use, so the first token
    ; you change does not drag every other colour off with it.
    static Suggest(w) {
        return (w.Theme = "light") ? Map("bg", "#f3f3f3", "fg", "#1b1b1b", "card", "#ffffff",
                                         "line", "#e5e5e5", "radius", "6")
                                   : Map("bg", "#202020", "fg", "#ffffff", "card", "#2b2b2b",
                                         "line", "#3a3a3a", "radius", "6")
    }
}
