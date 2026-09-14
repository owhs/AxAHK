#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Model.ahk
#Include %A_LineFile%\..\AxStudio.Lit.ahk
#Include %A_LineFile%\..\AxStudio.Form.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk

; Part of AxStudio, not a program on its own. Running this file directly would
; only load a class and stop, so it hands over to the entry point instead.
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
;  AxStudio.Data.ahk -- where a list gets its contents.
;
;  A data view's Data field is an AutoHotkey expression, written into the
;  script exactly as typed. That is the right design -- anything else would be
;  a second, worse language -- and it is a terrible first experience: an empty
;  box, and a grid on the canvas with nothing in it.
;
;  So this builds the expression. Five sources, because between them they
;  cover nearly everything a small program shows a list of:
;
;      typed      columns and rows you fill in here, written out as a literal
;      paste      copied out of a spreadsheet: tab or comma separated, the
;                 first row being the headings
;      json       an array of objects, the way a web API hands them over
;      csv        a FILE, read when the script starts, so the data can change
;                 without rebuilding anything
;      folder     a directory listing -- name, size, modified
;
;  The first three write a literal into the control. The last two write a
;  function into your own code and call it, because the work happens at run
;  time and has to be somewhere you can change.
;
;  A drop-down, a list box and an autocomplete take a plainer shape -- one
;  value per line -- so the same sources feed those too.
; =============================================================================
class AxData {
    static Q := Chr(34)
    static NL := Chr(10)

    ; Which controls have contents worth building. A data view takes columns
    ; and rows; the rest take a list of values.
    static Kind(type) {
        static grid := "|DataView|"
        static list := "|DDL|ListBox|AutoComplete|Palette|Segmented|Radio|"
        if InStr(grid, "|" type "|")
            return "grid"
        if (type = "ListView")                 ; titles, then rows, as text
            return "table"
        if InStr(list, "|" type "|")
            return "list"
        return ""
    }

    ; ---------------------------------------------------------------- parse
    ; A table out of pasted text. The separator is whatever the first line has
    ; most of, because a spreadsheet gives tabs and a saved file gives commas
    ; and nobody should have to say which.
    static Table(text, hasHead := true) {
        rows := [], sep := ""
        lines := []
        for raw in StrSplit(StrReplace(String(text), "`r", ""), "`n")
            if (Trim(raw) != "")
                lines.Push(raw)
        if !lines.Length
            return {Cols: [], Rows: []}
        sep := AxData.Separator(lines[1])
        for line in lines
            rows.Push(AxData.Split(line, sep))
        cols := []
        if (hasHead && rows.Length) {
            head := rows.RemoveAt(1)
            for i, h in head
                cols.Push({Key: AxData.KeyFor(h, i), Title: h})
        } else {
            loop rows.Length ? rows[1].Length : 0
                cols.Push({Key: "c" A_Index, Title: "Column " A_Index})
        }
        return {Cols: cols, Rows: rows}
    }
    static Separator(line) {
        tabs := StrLen(line) - StrLen(StrReplace(line, "`t"))
        semis := StrLen(line) - StrLen(StrReplace(line, ";"))
        commas := StrLen(line) - StrLen(StrReplace(line, ","))
        if (tabs >= commas && tabs >= semis && tabs > 0)
            return "`t"
        if (semis > commas && semis > 0)
            return ";"
        return (commas > 0) ? "," : "`t"
    }
    ; Splitting a line, minding quotes: a spreadsheet quotes any cell with the
    ; separator in it, and dropping that is how a column silently shifts.
    static Split(line, sep) {
        out := [], cur := "", i := 1, inq := false
        while (i <= StrLen(line)) {
            c := SubStr(line, i, 1)
            if (c = AxData.Q) {
                if (inq && SubStr(line, i + 1, 1) = AxData.Q) {
                    cur .= AxData.Q
                    i += 2
                    continue
                }
                inq := !inq
                i++
                continue
            }
            if (!inq && c = sep) {
                out.Push(Trim(cur))
                cur := ""
                i++
                continue
            }
            cur .= c
            i++
        }
        out.Push(Trim(cur))
        return out
    }
    static KeyFor(title, i) {
        k := AxProject.CleanName(title)
        if (k = "")
            k := "c" i
        return StrLower(SubStr(k, 1, 1)) SubStr(k, 2)
    }
    ; An array of objects, written as JSON. Not a full parser -- the columns
    ; are the property names of the first object, and the values are read as
    ; text, which is what a list shows anyway.
    static Json(text) {
        m := ""
        try m := AxJson.Parse(Trim(String(text)))
        if !(m is Array) || !m.Length
            return {Cols: [], Rows: []}
        cols := []
        first := m[1]
        if (first is Map) {
            for k, v in first
                cols.Push({Key: k, Title: AxData.Nice(k)})
        } else
            cols.Push({Key: "value", Title: "Value"})
        rows := []
        for item in m {
            r := []
            for c in cols
                r.Push((item is Map) && item.Has(c.Key) ? String(item[c.Key]) : String(item))
            rows.Push(r)
        }
        return {Cols: cols, Rows: rows}
    }
    static Nice(k) => StrUpper(SubStr(k, 1, 1)) SubStr(k, 2)

    ; ---------------------------------------------------------- expressions
    ; {Columns: [...], Rows: [...]} written out, wrapped so it stays readable
    ; in the field it lands in.
    static GridExpr(t, limit := 200) {
        if !t.Cols.Length
            return ""
        nl := AxData.NL
        s := "{Columns: ["
        for i, c in t.Cols
            s .= (i = 1 ? "" : "," nl "            ")
              .  "{Key: " AxLit.S(c.Key) ", Title: " AxLit.S(c.Title)
              .  ", Width: " AxData.WidthFor(c.Title) "}"
        s .= "]," nl " Rows: ["
        n := 0
        for r in t.Rows {
            if (++n > limit)
                break
            s .= (n = 1 ? "" : "," nl "         ") "{"
            for i, c in t.Cols
                s .= (i = 1 ? "" : ", ") c.Key ": " AxLit.S(i <= r.Length ? r[i] : "")
            s .= "}"
        }
        return s "]}"
    }
    ; Wide enough for the heading, and wider for the ones that are usually
    ; long. A column you have to drag on first use is a column that was wrong.
    static WidthFor(title) {
        w := 40 + StrLen(title) * 8
        static wide := "|name|title|description|path|file|address|email|comment|"
        if InStr(wide, "|" StrLower(title) "|")
            w := Max(w, 220)
        return Min(400, Max(80, w))
    }
    ; A list view's text: the titles, then a row a line, cells split by |.
    static TableText(t) {
        Cell := (v) => StrReplace(StrReplace(String(v), "|", "/"), "`n", " ")
        out := ""
        for i, c in t.Cols
            out .= (i = 1 ? "" : " | ") Cell(c.Title)
        for r in t.Rows {
            line := ""
            for i, c in t.Cols
                line .= (i = 1 ? "" : " | ") Cell(i <= r.Length ? r[i] : "")
            out .= AxData.NL line
        }
        return out
    }
    ; One value per line, which is what every list-shaped control takes.
    static ListExpr(t, col := 1) {
        out := ""
        for r in t.Rows
            out .= (out = "" ? "" : AxData.NL) (col <= r.Length ? r[col] : "")
        return out
    }

    ; ------------------------------------------------------- run-time loaders
    ; A CSV read when the script starts. Written into your own code rather than
    ; into the control, because it is work that happens at run time and you
    ; will want to change it.
    static CsvLoader(fn, path, head) {
        q := AxData.Q, nl := AxData.NL
        return "; Reads " path " when it is called. The first row is the headings." nl
             . fn "() {" nl
             . "    text := " q q nl
             . "    try text := FileRead(" AxAsset.PathExpr(path) ", " q "UTF-8" q ")" nl
             . "    if (text = " q q ")" nl
             . "        return {Columns: [], Rows: []}" nl
             . "    lines := StrSplit(StrReplace(text, " q "`r" q ", " q q "), " q "`n" q ")" nl
             . "    cols := [], rows := [], keys := []" nl
             . "    for i, line in lines {" nl
             . "        if (Trim(line) = " q q ")" nl
             . "            continue" nl
             . "        cells := StrSplit(line, " q "," q ", " q " " q ")" nl
             . (head
                ? "        if !cols.Length {" nl
                . "            for j, h in cells {" nl
                . "                keys.Push(" q "c" q " j)" nl
                . "                cols.Push({Key: " q "c" q " j, Title: h, Width: 160})" nl
                . "            }" nl
                . "            continue" nl
                . "        }" nl
                : "        if !cols.Length" nl
                . "            for j, h in cells {" nl
                . "                keys.Push(" q "c" q " j)" nl
                . "                cols.Push({Key: " q "c" q " j, Title: " q "Column " q " j, Width: 160})" nl
                . "            }" nl)
             . "        r := {}" nl
             . "        for j, v in cells" nl
             . "            if (j <= keys.Length)" nl
             . "                r.%keys[j]% := v" nl
             . "        rows.Push(r)" nl
             . "    }" nl
             . "    return {Columns: cols, Rows: rows}" nl
             . "}"
    }
    ; A folder listing. The three columns everyone wants, and a pattern you
    ; can change.
    static FolderLoader(fn, dir, pattern) {
        q := AxData.Q, nl := AxData.NL
        return "; Everything in " dir " matching " pattern "." nl
             . fn "() {" nl
             . "    rows := []" nl
             . "    loop files " AxAsset.PathExpr(dir) " " q "\" pattern q ", " q "F" q nl
             . "        rows.Push({name: A_LoopFileName," nl
             . "                   size: A_LoopFileSizeKB " q " KB" q "," nl
             . "                   at: A_LoopFileTimeModified})" nl
             . "    return {Columns: [{Key: " q "name" q ", Title: " q "Name" q ", Width: 260}," nl
             . "                      {Key: " q "size" q ", Title: " q "Size" q ", Width: 110,"
             . " Align: " q "right" q "}," nl
             . "                      {Key: " q "at" q ", Title: " q "Modified" q ", Width: 150}]," nl
             . "            Rows: rows}" nl
             . "}"
    }
    static LoaderName(n) => "Data_" AxProject.CleanName(n.Name != "" ? n.Name : "list")

    ; =============================================================== the form
    static Wizard(s, n) {
        if !IsObject(n)
            return s.Status("msg", "Select the list you want to fill first.")
        kind := AxData.Kind(n.Type)
        if (kind = "")
            return s.Status("msg", AxCat.Has(n.Type) ? AxCat.Get(n.Type).Label " does not hold a list."
                                                     : "That control does not hold a list.")
        grid := (kind = "grid" || kind = "table")
        table := (kind = "table")
        items := [
            {V: "paste", L: "Paste it from a spreadsheet", Icon: "E77F",
             Desc: "Copy the cells, paste them here. Tabs, commas or semicolons -- whichever "
                 . "your paste has most of -- and quoted cells are kept whole."},
            {V: "typed", L: "Type it out", Icon: "E70F",
             Desc: "One row per line, columns separated by a tab or a comma. The first line "
                 . "is the headings."},
            {V: "json",  L: "From JSON", Icon: "E943",
             Desc: "An array of objects, the way an API hands them over. The first object's "
                 . "properties become the columns."},
            {V: "csv",   L: "From a CSV file, at run time", Icon: "E8E5",
             Desc: "Nothing is built in. A function is written into your own code that reads "
                 . "the file when it is called, so the data can change without rebuilding."},
            {V: "folder", L: "From a folder listing", Icon: "E8B7",
             Desc: "Name, size and when it was last changed, for everything matching a "
                 . "pattern."}]
        if table                                ; its rows are text: nothing read at run time
            items.RemoveAt(4, 2)
        r := AxForm.Show(s, {Title: "Where the data comes from", Icon: "E9D5", Width: 600,
            Intro: (table ? "The list view" : grid ? "The data view" : AxCat.Get(n.Type).Label) " called " n.Label
                 . ". Whatever you pick is written into the field as an expression -- it is "
                 . "still yours to edit afterwards.",
            Fields: [
                {Id: "src", Kind: "pick", L: "", V: "paste", Items: items, Scroll: true},
                {Id: "text", L: "The data", Kind: "code", Rows: 8, V: AxData.Sample(grid),
                 When: (V) => (V["src"] = "paste" || V["src"] = "typed" || V["src"] = "json")},
                {Id: "head", L: "The first line is the headings", Kind: "flag", V: 1,
                 When: (V) => (V["src"] = "paste" || V["src"] = "typed" || V["src"] = "csv")},
                {Id: "file", L: "The file", Kind: "text", V: "data.csv",
                 When: (V) => V["src"] = "csv",
                 Hint: "Beside the script unless you give a full path."},
                {Id: "dir",  L: "The folder", Kind: "text", V: "%A_MyDocuments%",
                 When: (V) => V["src"] = "folder"},
                {Id: "pat",  L: "Matching", Kind: "text", V: "*.*",
                 When: (V) => V["src"] = "folder"},
                {Id: "col",  L: "Use column", Kind: "int", V: 1, Min: 1, Max: 40,
                 When: (V) => !grid && (V["src"] = "paste" || V["src"] = "typed"),
                 Hint: "A list shows one value per row, so this says which column that is."}],
            Buttons: ["Use it", "Cancel"],
            Check: (V) => AxData.Why(s, V, grid),
            Preview: (V) => AxData.Preview(s, n, V, grid, table)})
        if !r.Ok
            return
        AxData.Apply(s, n, r.V, grid, table)
    }
    static Sample(grid) {
        nl := AxData.NL
        if grid
            return "Name" Chr(9) "Size" Chr(9) "Kind" nl
                 . "Report.docx" Chr(9) "48 KB" Chr(9) "Document" nl
                 . "Photo.png" Chr(9) "1.2 MB" Chr(9) "Image"
        return "Small" nl "Medium" nl "Large"
    }
    static Why(s, V, grid) {
        switch V["src"] {
        case "csv":
            return (Trim(V["file"]) = "") ? "Say which file." : ""
        case "folder":
            return (Trim(V["dir"]) = "") ? "Say which folder." : ""
        case "json":
            t := AxData.Json(V["text"])
            return t.Cols.Length ? "" : "That is not an array of objects."
        }
        t := AxData.Table(V["text"], V["head"] ? true : false)
        if !t.Cols.Length
            return "Nothing to read yet."
        return (!grid && !t.Rows.Length) ? "No rows under the headings." : ""
    }
    static Preview(s, n, V, grid, table := false) {
        src := V["src"]
        if (src = "csv" || src = "folder") {
            fn := AxData.LoaderName(n)
            return fn "()" AxData.NL
                 . "...and " fn "() goes in with your own functions, reading "
                 . (src = "csv" ? Trim(V["file"]) : Trim(V["dir"]) "\" Trim(V["pat"]))
                 . " when it is called."
        }
        t := (src = "json") ? AxData.Json(V["text"])
                            : AxData.Table(V["text"], V["head"] ? true : false)
        if !t.Cols.Length
            return ""
        if table {
            e := AxData.TableText(t)
            return t.Cols.Length " column" (t.Cols.Length = 1 ? "" : "s") ", "
                 . t.Rows.Length " row" (t.Rows.Length = 1 ? "" : "s") ":" AxData.NL e
        }
        if grid {
            e := AxData.GridExpr(t, 3)
            more := (t.Rows.Length > 3) ? AxData.NL "... and " (t.Rows.Length - 3) " more row"
                                        . (t.Rows.Length - 3 = 1 ? "" : "s") : ""
            return t.Cols.Length " column" (t.Cols.Length = 1 ? "" : "s") ", "
                 . t.Rows.Length " row" (t.Rows.Length = 1 ? "" : "s") ":" AxData.NL e more
        }
        col := (src = "json") ? 1 : AxData.Int(V["col"], 1)
        list := AxData.ListExpr(t, col)
        return t.Rows.Length " item" (t.Rows.Length = 1 ? "" : "s") ":" AxData.NL list
    }
    static Int(v, d) {
        v := RegExReplace(Trim(String(v)), "[^0-9\-]")
        return (v = "" || v = "-") ? d : Integer(v)
    }

    static Apply(s, n, V, grid, table := false) {
        s.Mark()
        src := V["src"]
        if (src = "csv" || src = "folder") {
            fn := AxData.LoaderName(n)
            code := (src = "csv")
                  ? AxData.CsvLoader(fn, Trim(V["file"]), V["head"] ? true : false)
                  : AxData.FolderLoader(fn, Trim(V["dir"]), Trim(V["pat"]))
            cur := RTrim(String(s.P.Script), "`r`n")
            if !InStr(cur, fn "(")
                s.P.Script := (Trim(cur) = "") ? code : cur "`n`n" code
            n.Arg := fn "()"
            s.Refresh()
            s.EditScript("script")
            return s.Status("msg", n.Label " is filled by " fn "(), which is with your own "
                                 . "functions now.")
        }
        t := (src = "json") ? AxData.Json(V["text"])
                            : AxData.Table(V["text"], V["head"] ? true : false)
        if table
            n.Arg := AxData.TableText(t)
        else if grid
            n.Arg := AxData.GridExpr(t)
        else {
            col := (src = "json") ? 1 : AxData.Int(V["col"], 1)
            n.Arg := AxData.ListExpr(t, col)
        }
        s.Refresh()
        s.PushCompletions()
        s.Status("msg", n.Label " filled: " t.Rows.Length " row"
                      . (t.Rows.Length = 1 ? "" : "s") ".")
    }
}
