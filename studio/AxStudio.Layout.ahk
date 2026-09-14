#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\AxStudio.Catalog.ahk
#Include %A_LineFile%\..\AxStudio.Model.ahk

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
;  AxStudio.Layout.ahk -- a window of fixed places, as rows that resize.
;
;  A script written for Gui() puts every control at a point: x34 y120 w245.
;  Brought in as it is, it looks exactly as it did, and does not resize.
;  ToRows reads the same places as a page: controls that share a band of
;  height are a row, left to right; a control inside a group box's frame
;  goes into the group box; the gaps between them become the gaps AxGui
;  keeps; and the last thing in a row that reached the right-hand edge
;  stretches with the window. ToFixed puts every one back where the script
;  had it -- the places are kept on each control (ax ay aw ah), so the two
;  are one design seen two ways and switching is never lossy.
; =============================================================================
class AxLayout {
    ; AxGui's controls are the Windows 11 ones, a size up from the classic
    ; Win32 controls a Gui() script was laid out for (a button is 32px, not
    ; 23). Fixed places are the script's own, given this much more room, so
    ; the arrangement is the same and nothing sits on top of anything.
    static SX := 1.1
    static SY := 1.35

    ; the places as imported, kept beside whatever the design does with them
    static MarkFixed(win) {
        win.ImportLayout := "fixed"
        win.ImportResize := win.Resizable
        seq := 0
        for n in AxLayout.All(win.Root) {
            seq++
            n.L["aord"] := seq
            n.L["apar"] := IsObject(n.Parent) ? n.Parent.Id : "root"
            n.L["astyle"] := n.Lay("style", "")
            n.L["atab"] := n.Lay("tab", "")
            if (n.Lay("place", "") != "abs")
                continue
            n.L["ax"] := n.Lay("x", 0), n.L["ay"] := n.Lay("y", 0)
            n.L["aw"] := n.Lay("w", ""), n.L["ah"] := n.Lay("h", "")
        }
    }
    static Has(win) => win.ImportLayout != ""
    static Mode(win) => (win.ImportLayout = "rows") ? "rows" : "fixed"
    static Switch(win, mode) => (mode = "rows") ? AxLayout.ToRows(win) : AxLayout.ToFixed(win)

    ; What keeps the height the script gave it: things whose height is their
    ; content's room, not a line of text.
    static KeepsHeight(n) {
        switch n.Type {
        case "ListBox", "DataView", "ListView", "TreeView", "GroupBox", "Tab", "Picture", "Image", "Html", "Svg", "Console",
             "Calendar", "ActiveX", "Card", "Grid", "Code":
            return true
        case "Edit":
            return n.Prop("rows", "") != ""
        case "Radio":
            return n.Prop("vertical", 0) ? true : false
        }
        return false
    }
    ; things that can stretch across the room they are given
    static Stretches(n) {
        switch n.Type {
        case "Edit", "Password", "Text", "Slider", "Progress", "ListBox", "DataView", "ListView", "TreeView", "DDL", "Separator",
             "GroupBox", "Tab", "Search", "AutoComplete", "Date", "Html", "Console", "Code":
            return true
        }
        return false
    }

    ; ------------------------------------------------------------- as it was
    static ToFixed(win) {
        byId := Map()
        list := AxLayout.All(win.Root)
        for n in list
            byId[n.Id] := n
        ; everyone back under the parent they had, in the order they had
        AxLayout.Sort(list, (a, b) => a.Lay("aord", 0) - b.Lay("aord", 0))
        for n in list {
            if (n.Lay("apar", "") = "")
                continue
            p := (n.L["apar"] = "root") ? win.Root : (byId.Has(n.L["apar"]) ? byId[n.L["apar"]] : win.Root)
            AxLayout.Detach(n)
            n.Parent := p, p.Kids.Push(n)
            if (n.Lay("atab", "") != "")
                n.L["tab"] := n.L["atab"]
        }
        for n in list {
            if (n.Lay("ax", "") = "")
                continue
            n.L["place"] := "abs", n.L["x"] := Round(n.L["ax"] * AxLayout.SX), n.L["y"] := Round(n.L["ay"] * AxLayout.SY)
            for k in ["gap", "top", "fill"]
                if n.L.Has(k)
                    n.L.Delete(k)
            if (n.L["aw"] != "")
                n.L["w"] := Round(n.L["aw"] * AxLayout.SX)
            else if n.L.Has("w")
                n.L.Delete("w")
            if (n.L["ah"] != "")
                n.L["h"] := Round(n.L["ah"] * AxLayout.SY)
            else if n.L.Has("h")
                n.L.Delete("h")
            n.L["style"] := n.Lay("astyle", "")
        }
        win.Resizable := win.ImportResize
        win.ImportLayout := "fixed"
    }

    ; ------------------------------------------------------ rows that resize
    static ToRows(win) {
        AxLayout.ToFixed(win)                       ; always from the places as imported
        AxLayout._Rows(win.Root, 0, 0, Round(win.Width / AxLayout.SX))     ; in the script's own numbers
        win.Resizable := 1
        win.MaximizeBox := 1
        if (win.MinWidth = 0 || win.MinWidth = "")
            win.MinWidth := Round(win.Width * 0.6)
        win.ImportLayout := "rows"
    }
    ; One container's children: into their group boxes, then into rows. A
    ; Tab's children are laid out a tab at a time.
    static _Rows(box, ox, oy, width) {
        if (box.Type = "Tab") {
            tabs := Map()
            for k in box.Kids
                tabs[Integer(k.Lay("tab", 1))] := true
            for i in tabs
                AxLayout._RowsOf(box, AxLayout._OnTab(box, i), ox, oy, width)
            return
        }
        AxLayout._RowsOf(box, box.Kids.Clone(), ox, oy, width)
    }
    static _OnTab(box, i) {
        out := []
        for k in box.Kids
            if (Integer(k.Lay("tab", 1)) = i)
                out.Push(k)
        return out
    }
    static _RowsOf(box, kids, ox, oy, width) {
        items := []
        for k in kids
            if (k.Lay("ax", "") != "")
                items.Push(k)
        if !items.Length
            return
        ; a group box takes what its frame encloses (the biggest first, so a
        ; box inside a box keeps its own)
        boxes := []
        for k in items
            if (k.Type = "GroupBox" && k.Lay("aw", "") != "" && k.Lay("ah", "") != "")
                boxes.Push(k)
        AxLayout.Sort(boxes, (a, b) => b.L["aw"] * b.L["ah"] - a.L["aw"] * a.L["ah"])
        inside := Map()
        for g in boxes {
            gx := g.L["ax"], gy := g.L["ay"], gw := g.L["aw"], gh := g.L["ah"]
            for k in items {
                if (k = g || inside.Has(k) || k.Type = "Tab")
                    continue
                cx := k.L["ax"] + (k.Lay("aw", "") != "" ? k.L["aw"] / 2 : 10)
                cy := k.L["ay"] + (k.Lay("ah", "") != "" ? k.L["ah"] / 2 : 8)
                if (cx > gx && cx < gx + gw && cy > gy + 8 && cy < gy + gh) {
                    inside[k] := g
                    AxLayout.Detach(k)
                    k.Parent := g, g.Kids.Push(k)
                    if k.L.Has("tab")
                        k.L.Delete("tab")
                }
            }
        }
        for g in boxes
            if g.Kids.Length {
                AxLayout.Sort(g.Kids, (a, b) => (a.L["ay"] - b.L["ay"]) || (a.L["ax"] - b.L["ax"]))
                AxLayout._RowsOf(g, g.Kids.Clone(), g.L["ax"] + 10, g.L["ay"] + 18, g.L["aw"] - 20)
                if g.L.Has("h")
                    g.L.Delete("h")                  ; it grows around its rows now
            }
        rest := []
        for k in items
            if !inside.Has(k)
                rest.Push(k)
        ; rows: what shares a band of height, top to bottom, left to right
        AxLayout.Sort(rest, (a, b) => (a.L["ay"] - b.L["ay"]) || (a.L["ax"] - b.L["ax"]))
        rows := [], row := [], top := 0, bottom := 0
        for k in rest {
            h := AxLayout._H(k)
            y := k.L["ay"]
            if (row.Length && y < bottom - Min(h, bottom - top) * 0.4) {
                row.Push(k), bottom := Max(bottom, y + h)
                continue
            }
            if row.Length
                rows.Push(row)
            row := [k], top := y, bottom := y + h
        }
        if row.Length
            rows.Push(row)
        ; and the order the page takes them in is the rows' order
        ordered := []
        for r in rows {
            AxLayout.Sort(r, (a, b) => a.L["ax"] - b.L["ax"])
            for k in r
                ordered.Push(k)
        }
        others := []
        for k in box.Kids
            if !AxLayout._In(ordered, k)
                others.Push(k)
        for k in ordered
            AxLayout.Detach(k)
        for k in ordered
            k.Parent := box, box.Kids.Push(k)
        prevBottom := oy
        for r in rows {
            right := ox
            rowTop := 1e9, rowBottom := 0
            for k in r
                rowTop := Min(rowTop, k.L["ay"]), rowBottom := Max(rowBottom, k.L["ay"] + AxLayout._H(k))
            for idx, k in r {
                for key in ["x", "y", "gap", "top", "fill"]
                    if k.L.Has(key)
                        k.L.Delete(key)
                k.L["style"] := k.Lay("astyle", "")
                if (idx = 1) {
                    k.L["place"] := "flow"
                    gapY := rowTop - prevBottom - 8
                    if (gapY > 4)
                        k.L["top"] := Round(gapY)
                    indent := k.L["ax"] - ox
                    if (indent > 12)
                        k.L["style"] := RTrim(k.L["style"], "; ") (k.L["style"] = "" ? "" : ";") "margin-left:" Round(indent) "px;"
                } else {
                    k.L["place"] := "same"
                    gap := Round(k.L["ax"] - right)
                    if (gap != 8)
                        k.L["gap"] := Max(0, gap)
                }
                if (k.Lay("aw", "") != "")
                    k.L["w"] := k.L["aw"]
                if (!AxLayout.KeepsHeight(k) && k.L.Has("h"))
                    k.L.Delete("h")
                right := k.L["ax"] + (k.Lay("aw", "") != "" ? k.L["aw"] : 60)
            }
            ; the last in the row, if it reached the right-hand edge, stretches
            last := r[-1]
            if (AxLayout.Stretches(last) && last.Lay("aw", "") != "" && last.L["ax"] + last.L["aw"] >= ox + width - 24) {
                last.L["fill"] := 1
                if last.L.Has("w")
                    last.L.Delete("w")
            }
            prevBottom := rowBottom
        }
    }
    static _H(k) => (k.Lay("ah", "") != "") ? k.L["ah"] : 24
    static _In(list, x) {
        for y in list
            if (y = x)
                return true
        return false
    }

    ; ----------------------------------------------------------------- tree
    static All(root) {
        out := []
        for k in root.Kids {
            out.Push(k)
            for x in AxLayout.All(k)
                out.Push(x)
        }
        return out
    }
    static Detach(n) {
        p := n.Parent
        if !IsObject(p)
            return
        for i, k in p.Kids
            if (k = n) {
                p.Kids.RemoveAt(i)
                break
            }
        n.Parent := ""
    }
    ; a small stable insertion sort: the lists are a window's controls
    static Sort(a, cmp) {
        i := 2
        while (i <= a.Length) {
            x := a[i], j := i - 1
            while (j >= 1 && cmp(a[j], x) > 0) {
                a[j + 1] := a[j], j--
            }
            a[j + 1] := x
            i++
        }
        return a
    }
}
