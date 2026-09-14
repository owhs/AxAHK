#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\AxStudio.Form.ahk
#Include %A_LineFile%\..\AxStudio.Panes.ahk

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
;  AxStudio.Arrange.ahk -- "Arrange what is inside": a box's controls laid out
;  together, against the box, in one go.
;
;  Laying out a card of six controls used to be six trips to the Layout
;  group. Here it is one question -- one under another, side by side, a grid
;  of so many across -- and how wide each is against the box and how far
;  apart they are. It only sets what the Layout group sets (Sits, Width,
;  the gap and the margins), so every control can still be changed on its
;  own afterwards, and Ctrl+Z puts the whole arrangement back.
; =============================================================================
class AxArrange {
    static Form(s, box) {
        if !IsObject(box) || !box.Kids.Length
            return s.Status("msg", "There is nothing in it to arrange.")
        kids := []
        for k in box.Kids
            if (k.Type != "Code")
                kids.Push(k)
        name := (box.Type = "Root" || box.Type = "Page") ? "the page" : (box.Name != "" ? box.Name : "the box")
        r := AxForm.Show(s, {Title: "Arrange what is inside " name, Icon: "E8A9", Width: 600,
            Intro: kids.Length " controls, laid out together. Each can still be changed on its own after; Ctrl+Z puts it all back.",
            Fields: [
                {Id: "how", Kind: "pick", L: "", V: "stack", Tiles: true, Items: [
                    {V: "stack", L: "One under another", Icon: "E8FD", Desc: "A column, top to bottom."},
                    {V: "row",   L: "Side by side",      Icon: "E8A9", Desc: "All on one line, left to right."},
                    {V: "grid",  L: "A grid",            Icon: "F0E2", Desc: "So many across, then the next row."},
                    {V: "pairs", L: "Label and box",     Icon: "E8BC", Desc: "Two across: a label, then what it names."}]},
                {Id: "cols", L: "Across", Kind: "int", V: 2, Min: 2, Max: 8, When: (V) => V["how"] = "grid"},
                {Id: "width", L: "Each is", Kind: "choice", V: "share",
                 Opts: "share:An equal share of " name "|full:The whole width (under one another)|own:As wide as it needs"},
                {Id: "gap", L: "Space between", Kind: "choice", V: "8", Opts: "0:None|4:A little|8:Normal|16:Roomy|24:Lots"}],
            Buttons: ["Arrange them", "Cancel"],
            Preview: (V) => AxArrange.Say(V, kids.Length)})
        if !r.Ok
            return
        s.Mark()
        AxArrange.Apply(kids, r.V)
        s.Refresh()
        s.QueueLive()
        s.Status("msg", "Arranged: " AxArrange.Say(r.V, kids.Length) ".")
    }
    static Say(V, n) {
        across := (V["how"] = "row") ? n : (V["how"] = "grid") ? Max(2, Integer(V["cols"] = "" ? 2 : V["cols"])) : (V["how"] = "pairs") ? 2 : 1
        rows := Ceil(n / across)
        return rows " row" (rows = 1 ? "" : "s") " of " across ", " (V["width"] = "share" ? "equal widths" : V["width"] = "full" ? "full width" : "their own widths")
             . ", " (V["gap"] = "0" ? "touching" : V["gap"] " px apart")
    }
    static Apply(kids, V) {
        n := kids.Length
        across := (V["how"] = "row") ? n : (V["how"] = "grid") ? Max(2, Integer(V["cols"] = "" ? 2 : V["cols"])) : (V["how"] = "pairs") ? 2 : 1
        gap := Integer(V["gap"])
        for i, k in kids {
            col := Mod(i - 1, across)
            AxPanes.PlaceOne(k, col = 0 ? "flow" : "same")
            k.L["gap"] := gap
            ; every one in a row after the first is the same way down, or the
            ; row's first stands lower than the rest of it
            k.L["top"] := (i > across && gap != 8) ? gap : ""
            if (V["how"] = "pairs")
                AxPanes.WRel(k, col = 0 ? "third" : "line")
            ; Fill on everything in a line is equal shares: AxGui gives each
            ; flex 1 1 0 (builder.css .ax-line>.fill)
            else if (V["width"] = "share" || V["width"] = "full")
                AxPanes.WRel(k, "line")
            else
                AxPanes.WRel(k, "auto")
        }
    }
}
