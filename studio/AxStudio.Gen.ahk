#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Lit.ahk
#Include %A_LineFile%\..\AxStudio.Model.ahk
#Include %A_LineFile%\..\AxStudio.Chrome.ahk
#Include %A_LineFile%\..\AxStudio.Merge.ahk
#Include %A_LineFile%\..\AxStudio.Debug.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk
#Include %A_LineFile%\..\AxStudio.Pkg.ahk
#Include %A_LineFile%\..\AxStudio.Theme.ahk
#Include %A_LineFile%\..\AxStudio.Flow.ahk
#Include %A_LineFile%\..\AxStudio.Bind.ahk
#Include %A_LineFile%\..\AxStudio.Comp.ahk
#Include %A_LineFile%\..\AxStudio.Auto.ahk
#Include %A_LineFile%\..\AxStudio.Auto2.ahk
#Include %A_LineFile%\..\AxStudio.DotNet.ahk

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
;  AxStudio.Gen.ahk -- the tree becomes markup, and the tree becomes AutoHotkey.
;
;  Both come out of the same walk over the same option strings, so what the
;  canvas shows is what the exported script builds. The canvas does not draw an
;  impression of a button: it asks AxGui for the markup of that button and puts
;  it on the page, which is why a theme change or a library fix reaches the
;  designer for free.
;
;      AxGen.Canvas(project, page)   -> HTML for the design surface
;      AxGen.Script(project, path)   -> the .ahk file
;      AxGen.OptString(node, canvas) -> "vbtn1 w120 Accent Icon=E768"
; =============================================================================

; AxGui with the two things that need a real window taken out: a design-time
; build never opens one, and AddDropZone / AddActiveX would otherwise reach for
; a HWND that does not exist.
class AxDesignGui extends AxGui {
    DropZone(id, fn := "", opts := "") => this
    RemoveDropZone(id) => this
    Embed(id, progId, opts := "") => ""
}

class AxGen {
    ; ------------------------------------------------------- option string
    static OptString(n, canvas := false) {
        p := []
        id := canvas ? ("d_" n.Id) : n.Name
        if (id != "")
            p.Push("v" id)
        place := n.Lay("place", "flow")
        if (place = "abs")
            p.Push("x" AxGen.N(n.Lay("x", 0)), "y" AxGen.N(n.Lay("y", 0)))
        else if (place = "dock")
            p.Push("Style=" AxGen.Q(AxGen.DockStyle(n)))
        else if (place = "same") {
            gap := n.Lay("gap", "")
            p.Push("x+" ((gap = "" || gap = 8) ? "" : AxGen.N(gap)))
        }
        if (n.Lay("w", "") != "")
            p.Push("w" AxGen.N(n.Lay("w")))
        if (n.Lay("h", "") != "")
            p.Push("h" AxGen.N(n.Lay("h")))
        if (n.Lay("top", "") != "")
            p.Push("y+" AxGen.N(n.Lay("top")))
        if n.Lay("fill", 0)
            p.Push("Fill")
        if (n.Lay("grow", 0) && (place = "flow" || place = "same"))
            p.Push("Grow")
        ; a hidden control still has to be visible and clickable on the canvas,
        ; so the flag is dropped there and a marker class takes its place
        if (n.Lay("hidden", 0) && !canvas)
            p.Push("Hidden")
        cls := Trim(n.Lay("class", ""))
        if canvas {
            cls := "axd axd-id-" n.Id (n.Box ? " axd-box" : "")
                 . (n.Type = "Grid" ? " axd-flat" : "") (n.Lay("hidden", 0) ? " axd-off" : "")
                 . ((place = "abs" || place = "dock") ? " axd-pos" : "")
                 . (place = "dock" ? " axd-dock" : "")
                 . (Trim(n.Lay("pop", "")) != "" ? " axd-haspop" : "")
                 . (n.Lay("dhide", 0) ? " axd-dhide" : "") (n.Lay("dlock", 0) ? " axd-locked" : "")
                 . (cls != "" ? " " cls : "")
        }
        if (cls != "")
            p.Push("Class=" AxGen.Q(cls))
        st := Trim(n.Lay("style", ""))
        ; the other three margins (the top one is AxGui's own y+N), as style
        mg := ""
        for k, css in Map("mb", "margin-bottom", "ml", "margin-left", "mr", "margin-right")
            if (n.Lay(k, "") != "" && !(k = "ml" && place = "same"))
                mg .= css ":" AxGen.N(n.Lay(k)) "px;"
        if (mg != "")
            st := mg (st = "" ? "" : RTrim(st, "; ") ";")
        sc := n.Lay("scroll", "")
        if (sc != "" && place != "dock")
            st := RTrim(st, "; ") (st = "" ? "" : ";")
                . ((sc = "both") ? "overflow:auto" : (sc = "x") ? "overflow-x:auto;overflow-y:hidden" : "overflow-y:auto;overflow-x:hidden")
        if (st != "" && place != "dock")
            p.Push("Style=" AxGen.Q(RTrim(st, ";") ";"))
        if (n.Lay("tip", "") != "")
            p.Push("Tip=" AxGen.Q(n.Lay("tip")))
        ; options the studio has no field for, kept as they were written
        if (Trim(n.Lay("opts", "")) != "")
            p.Push(Trim(n.Lay("opts")))

        e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
        if IsObject(e) {
            for pr in e.Props {
                v := n.Prop(pr.K, "")
                if (canvas && pr.HasOwnProp("NoCanvas") && pr.NoCanvas)
                    continue
                if (pr.Emit = "flag") {
                    if (v != "" && v != 0 && v != "0")
                        p.Push(pr.W)
                } else if (pr.Emit = "flagset") {
                    if (v != "")
                        p.Push(v)
                } else if (v != "")
                    p.Push(pr.W "=" AxGen.Q(v))
            }
        }
        s := ""
        for x in p
            s .= (s = "" ? "" : " ") x
        return s
    }
    ; Docking is absolute positioning against the page, which is the only box
    ; AxGui gives a position to. It is written as a style rather than a new
    ; option because that is exactly what it is, and it therefore works in the
    ; exported script with no library change at all.
    static DockStyle(n) {
        side := StrLower(n.Lay("dock", "bottom"))
        size := AxGen.N(n.Lay("docksize", ""))
        own := Trim(n.Lay("style", ""))
        st := "position:absolute;"
        switch side {
        case "top":    st .= "left:0;right:0;top:0;" (size != "" ? "height:" size "px;" : "")
        case "bottom": st .= "left:0;right:0;bottom:0;" (size != "" ? "height:" size "px;" : "")
        case "left":   st .= "left:0;top:0;bottom:0;" (size != "" ? "width:" size "px;" : "")
        case "right":  st .= "right:0;top:0;bottom:0;" (size != "" ? "width:" size "px;" : "")
        default:       st .= "left:0;top:0;right:0;bottom:0;"
        }
        return st (own != "" ? RTrim(own, ";") ";" : "")
    }
    ; --------------------------------------------------- the second argument
    ; Stored as the user typed it; handed to Add* in the shape that method wants.
    static ArgValue(n) {
        e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
        if !IsObject(e) || !IsObject(e.Arg)
            return ""
        v := n.Arg
        if (e.Arg.Kind = "options") {
            sep := (n.Type = "Palette") ? "," : "|"
            out := ""
            for line in StrSplit(StrReplace(v, "`r", ""), "`n") {
                line := Trim(line)
                if (line != "")
                    out .= (out = "" ? "" : sep) line
            }
            return out
        }
        return v
    }
    static ArgIsRaw(n) {
        e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
        return IsObject(e) && IsObject(e.Arg) && e.Arg.HasOwnProp("Raw") && e.Arg.Raw
    }

    ; =====================================================================
    ;  Canvas markup
    ; =====================================================================
    ; The content of one page (or of the root when the project has no pages),
    ; as the markup AxGui itself would generate for it.
    static Canvas(project, page) {
        g := AxDesignGui({Nav: false})
        kids := IsObject(page) ? page.Kids : AxGen._Loose(project)
        root := g._root
        AxGen.Emit(g, kids, (*) => g.Use(root), true)
        html := g._root.InnerHtml()
        if (html = "")
            html := '<div class="axd-blank">This page is empty. Drag a control here from the toolbox.</div>'
        return html
    }
    ; Controls that sit above every page (AxGui renders these before the pages).
    static _Loose(project) {
        out := []
        for k in project.Root.Kids
            if (k.Type != "Page")
                out.Push(k)
        return out
    }
    ; `back` puts g._cur where it was before this list was emitted. A tab panel
    ; cannot be reached with Use() -- only the tabs container can -- so the way
    ; back into one is another UseTab, which is why this is a callback rather
    ; than a container reference.
    ; canvas: the ids are the design's (d_n7), so the studio can find a
    ; control it drew. Otherwise they are the control's own name, which is what
    ; the exported script uses -- and what a prerendered body has to carry.
    static Emit(g, kids, back, canvas := true) {
        for n in kids {
            if (n.Type = "Page")
                continue
            c := AxGen._AddOne(g, n, canvas)
            if (n.Box && IsObject(c)) {
                if (n.Type = "Tab")
                    AxGen._EmitTabs(g, c, n, canvas)
                else {
                    AxGen.Emit(g, n.Kids, (*) => g.Use(c), canvas)
                    ; an imported frame is a frame: what it frames sits over it
                    if (!n.Kids.Length && n.Lay("ax", "") = "")
                        AxGen._Placeholder(g, n)
                }
                back()
            }
        }
    }
    static _EmitTabs(g, tabs, n, canvas := true) {
        loop AxGen.TabCount(n) {
            i := A_Index
            tabs.UseTab(i)
            group := []
            for k in n.Kids
                if (AxGen.TabOf(k) = i)
                    group.Push(k)
            AxGen.Emit(g, group, (*) => tabs.UseTab(i), canvas)
            if !group.Length
                AxGen._Placeholder(g, n)
        }
    }
    ; A Code block on the canvas: its first lines, and how many more.
    static CodeChip(n) {
        lines := StrSplit(Trim(StrReplace(n.Arg, "`r", ""), "`n"), "`n")
        show := ""
        loop Min(lines.Length, 3)
            show .= (A_Index > 1 ? "`n" : "") lines[A_Index]
        more := (lines.Length > 3) ? '<span class="axd-codemore">' (lines.Length - 3) ' more line' (lines.Length = 4 ? "" : "s") '</span>' : ""
        return '<div class="axd-code"><span class="ico">&#xE943;</span><pre>' AxTags.E(show != "" ? show : "(empty)") '</pre>' more '</div>'
    }
    static _Placeholder(g, n) {
        g.AddHtml("Fill Class=axd-empty", "Drop controls here")
    }
    static TabOf(k) {
        v := k.Lay("tab", 1)
        return (v = "" || !IsNumber(v)) ? 1 : Integer(v)
    }
    static TabCount(n) {
        c := 0
        for line in StrSplit(StrReplace(n.Arg, "`r", ""), "`n")
            if (Trim(line) != "")
                c++
        return c ? c : 1
    }
    static _AddOne(g, n, canvas := true) {
        opts := AxGen.OptString(n, canvas)
        if (n.Type = "Code")
            return g.AddHtml(opts, AxGen.CodeChip(n))
        arg := AxGen.ArgValue(n)
        if (n.Type = "ActiveX")
            return g.AddActiveX(opts, "Shell.Explorer.2")       ; never really docked at design time
        if (n.Type = "DataView")
            return AxGen._DesignDataView(g, opts, n)
        if (n.Type = "Tab")
            return g.AddTab(opts, arg)
        m := "Add" n.Type
        e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
        ; AddGrid, AddConsole and AddSeparator take the option string and
        ; nothing else. Handing them a second argument is "too many parameters",
        ; which used to come out as red text on the canvas.
        try return (IsObject(e) && !IsObject(e.Arg)) ? g.%m%(opts) : g.%m%(opts, arg)
        catch as err {
            ; The stand-in has to keep the same option string, or it loses the
            ; class carrying the design id and becomes a thing on the canvas
            ; that cannot be clicked, named or deleted.
            return g.AddHtml(opts, '<span class="axd-bad">&lt;' AxTags.E(n.Type) '&gt; ' AxTags.E(err.Message) '</span>')
        }
    }
    ; The data view wants a real object, and at design time the expression the
    ; user typed has not been evaluated -- it is text. So the columns are read
    ; out of that text and a few rows of plausible-looking data are put under
    ; them, because a grid with nothing in it reads as a broken grid rather
    ; than an unfilled one.
    ;
    ; Preview is what makes it appear at all: AddDataView normally builds an
    ; empty shell and fills it in from the instance it creates OnReady, and a
    ; designer never shows its window, so OnReady never runs.
    ; When the text is data rather than code, the rows in it are what is drawn;
    ; ReadRows is how the studio reads them (AXG.rowsJson, in the page).
    static ReadRows := ""
    static _DesignDataView(g, opts, n) {
        cols := AxGen.DataColumns(n.Arg)
        rows := AxGen.DataRows(n.Arg)
        if !IsObject(rows) {
            rows := []
            loop 4 {
                r := {}
                for i, c in cols
                    r.%c.Key% := AxGen._PreviewCell(c, i, A_Index)
                rows.Push(r)
            }
        }
        cfg := {Columns: cols, Rows: rows, Preview: true, NoSearch: false,
                Empty: "The rows come from the expression above, at run time."}
        try return g.AddDataView(opts, cfg)
        catch as err
            return g.AddHtml(opts, '<span class="axd-bad">&lt;DataView&gt; ' AxTags.E(err.Message)
                 . ' <span class="axd-dim">(' AxTags.E(RegExReplace(err.File, ".*\\") ":" err.Line) ')</span></span>')
    }
    ; The rows of a grid's data, as objects -- or "" when they cannot be read.
    static DataRows(text) {
        if !HasMethod(AxGen.ReadRows, "Call")
            return ""
        js := ""
        try js := AxGen.ReadRows.Call(String(text))
        if (js = "")
            return ""
        list := ""
        try list := AxJson.Parse(js)
        if !(list is Array)
            return ""
        out := []
        for m in list {
            o := {}
            if (m is Map)
                for k, v in m
                    o.%k% := v
            out.Push(o)
        }
        return out
    }
    ; The columns named in an AHK expression, without evaluating it.
    ;   {Columns: [{Key: "name", Title: "Name", Width: 260}, ...]}   the usual
    ;   [{name: "a", size: 1}, ...]                                  a plain list
    ; A column the studio cannot read is better than none: the fallback is one
    ; column called Column.
    static DataColumns(text) {
        out := []
        src := String(text)
        ; the Columns: [...] part, if there is one
        if RegExMatch(src, "i)\bColumns\s*:\s*\[", &cm) {
            tail := SubStr(src, cm.Pos + cm.Len)
            end := InStr(tail, "]")
            body := end ? SubStr(tail, 1, end - 1) : tail
            pos := 1
            while RegExMatch(body, "\{([^{}]*)\}", &om, pos) {
                pos := om.Pos + om.Len
                one := om[1]
                key := AxGen._Field(one, "Key"), title := AxGen._Field(one, "Title")
                if (key = "" && title = "")
                    continue
                w := AxGen._Field(one, "Width")
                out.Push({Key: (key != "" ? key : "c" out.Length),
                          Title: (title != "" ? title : key),
                          Width: (w != "" && IsInteger(w)) ? Integer(w) : 160,
                          Align: AxGen._Field(one, "Align")})
            }
        }
        ; no Columns: read the property names off the first object instead
        if (!out.Length && RegExMatch(src, "\{([^{}]*)\}", &om)) {
            pos := 1
            while RegExMatch(om[1], "([A-Za-z_]\w*)\s*:", &pm, pos) {
                pos := pm.Pos + pm.Len
                out.Push({Key: pm[1], Title: AxGen._Nice(pm[1]), Width: 160, Align: ""})
            }
        }
        if !out.Length
            out.Push({Key: "c0", Title: "Column", Width: 220, Align: ""})
        return out
    }
    ; One  Name: value  out of an object written as text. A quoted string comes
    ; back without its quotes; anything else comes back as it was written.
    static _Field(text, name) {
        if RegExMatch(text, 'i)\b' name '\s*:\s*"([^"]*)"', &m)
            return m[1]
        if RegExMatch(text, "i)\b" name "\s*:\s*([-\w.]+)", &m)
            return m[1]
        return ""
    }
    static _Nice(key) => StrUpper(SubStr(key, 1, 1)) SubStr(key, 2)
    ; Something that looks like what would be there. A column lined up on the
    ; right is a number nine times out of ten.
    static _PreviewCell(c, col, row) {
        if (col = 1)
            return "Row " row
        if (c.Align = "right")
            return String(row * 128)
        return "-"
    }

    ; The page rail, drawn from the project's pages. Written out here rather
    ; than through <ax-nav> because that tag claims the id #sidebar, which the
    ; studio's own window already owns.
    static NavHtml(project, activeId) {
        pages := project.Pages()
        if (!pages.Length || !project.Nav)
            return ""
        h := ""
        for p in pages {
            ico := p.Prop("icon", "")
            h .= '<div class="nav-item axd-navitem' (p.Id = activeId ? " active" : "") '" data-nav="' p.Id '">'
              .  (ico != "" ? '<span class="ico">&#x' AxTags.E(ico) ';</span>' : "")
              .  AxTags.E(p.Prop("title", p.Name)) '</div>'
        }
        return h
    }

    ; =====================================================================
    ;  AutoHotkey
    ; =====================================================================
    ; A project is one script. The main window is built at the top, as it
    ; always was; every other window becomes a function that builds and shows
    ; it on demand, so one window can open another by calling it.
    ; `pre` is the prerendered body, handed in by the studio -- expanding
    ; markup needs a document and the generator has none of its own.
    static Script(project, outPath := "", dbg := "", pre := "") {
        libDir := AxStudioPaths.Lib
        inc := AxGen.RelInclude(outPath, libDir "\AxGui.ahk")
        needRich := false
        ; made once, outside the loop: a callback built inside one is the shape
        ; that goes wrong in AutoHotkey v2, so the studio never writes one
        wantsRich := (n) => (AxCat.Has(n.Type) && AxCat.Get(n.Type).Needs != "") ? (needRich := true, false) : false
        for w in project.Wins
            project.Walk(w.Root, wantsRich)
        ; and the component packs it actually touches, with whatever those
        ; require. One #Include each: a window with a splitter in it no longer
        ; drags in a colour picker and a data grid.
        packs := AxComp.Used(project)

        nl := "`n"
        ; what happens when it is started while it is already running, as
        ; App > Details says: replace it (the default), keep it, ask, or allow two
        inst := AxAsset.Compile(project)
        inst := (inst.Has("instance") && inst["instance"] != "") ? inst["instance"] : "Force"
        head := "#Requires AutoHotkey v2.0" nl "#SingleInstance " inst nl
        ; App > Script settings: administrator, how keys are sent, ...
        head .= AxAuto.SettingsCode(project)
        head .= "; Designed with AxStudio. The blocks marked #region axstudio are" nl
        head .= "; rewritten on every export. Anything outside them is left alone." nl
        if (project.Path != "")
            head .= AxMerge.RefLine(AxGen.RelPath(outPath, project.Path)) nl
        ; Where lib is, for Ahk2Exe. Every ;@Ahk2Exe-AddResource line in the
        ; library is written against %U_AxLib%, and Ahk2Exe resolves those
        ; against the MAIN script -- so without this the compiler stops at the
        ; first one with "specified resource does not exist". It has to come
        ; before the includes that carry those lines, and uncompiled it is a
        ; comment, so it costs a loose script nothing. See lib\AxAssets.ahk.
        head .= ";@Ahk2Exe-Let U_AxLib = " AxGen.LetPath(outPath, libDir) nl
        head .= '#Include ' inc nl
        ; What a compiled exe carries of the library's own files. Without one
        ; of these a compiled window comes up unstyled anywhere lib\ is not
        ; sitting beside it. Uncompiled both are comments.
        ; NOT called trim: identifiers are case-insensitive, so a local named
        ; trim IS Trim, and the Trim() call further down this function was
        ; calling this Map. Which is what made Compile do nothing at all.
        cmp := AxAsset.Compile(project)
        if (cmp.Has("embed") && StrLower(cmp["embed"]) = "used")
            head .= AxGen.LibResources(project, libDir)
        else
            head .= '#Include ' AxGen.RelInclude(outPath, libDir "\AxAssets.ahk") nl
        if needRich
            head .= '#Include ' AxGen.RelInclude(outPath, libDir "\AxRichAll.ahk") nl
        if packs.Length {
            head .= '#Include ' AxGen.RelInclude(outPath, libDir "\AxRich.ahk") nl
            for p in packs
                head .= '#Include ' AxGen.RelInclude(outPath, p.Include) nl
        }
        ; AxGui brings the F12 inspector to a running .ahk and leaves it out of
        ; a compiled one. Kept on purpose, it is included here, outside that
        ; fence, so the exe has it too.
        if AxGen.KeepDevTools(project)
            head .= "; the F12 inspector, kept in the exe (File > Compile)" nl
                 .  '#Include ' AxGen.RelInclude(outPath, libDir "\dev\AxInspector.ahk") nl
        ; the project's own includes go last, so they can use the library
        incs := AxAsset.IncludesCode(project)
        if (Trim(incs) != "")
            head .= incs nl
        ; and the libraries Aris installed beside the project (App > Libraries)
        pk := AxPkg.IncludesCode(project, outPath)
        if (pk != "")
            head .= pk nl

        ; vars is the window being written, all is every window: a handler has
        ; to see the controls of the window it belongs to, and the builders of
        ; the others, so the two lists are kept apart and joined at the end.
        state := {vars: Map(), all: Map(), wiring: "", handlerList: [], popovers: [],
                  project: project, g: "g", win: "", dbg: IsObject(dbg)}
        ; Binding variables are globals in the finished script exactly like a
        ; control variable, so they go in the same list: that puts them in the
        ; globals of every handler, rule and startup function -- your own code
        ; can read and write them -- and stops a control being named after one.
        for v in AxBind.Vars(project)
            state.all[v.Name] := true
        main := project.Main()
        ; A design can have no window of its own to start with: every one is
        ; made by the script's own code, through Make<Name>(). g is still
        ; declared, so the handlers' global lists stay one shape.
        hasMain := (main.Kind = "main")
        if hasMain
            m := AxGen._WinCode(project, main, state)
        else {
            state.all["g"] := true
            m := {Ui: 'g := ""   `; no window of its own: the script makes them, with Make...()' nl, Events: "", Vars: Map()}
        }
        ; Every argument is a global, exactly like a binding variable, so a
        ; handler can read one without declaring anything.
        for a in AxAsset.Args(project)
            state.all[a.Name] := true

        show := ""
        if AxAsset.Args(project).Length
            show .= "ReadArgs()" nl
        if AxBind.Any(project)
            show .= "AxBindInit()" nl
        ; what the last run kept, over the first values, before anything shows them
        if AxAuto2.Settings(project).Length
            show .= "SettingsLoad()" nl
        if AxBind.Any(project)
            show .= "AxBindSync()" nl
        ; The window's start-up code runs when its page is there to work on --
        ; it fills lists, writes into boxes, and a page that does not exist yet
        ; has nothing to fill -- and after everything else at the top of the
        ; script, so what the script sets up below Show() (a file name, a
        ; list) is set. So it is hooked up at the very end of the file: by
        ; then the page is there, or it runs the moment it is.
        opened := ""
        if (hasMain && Trim(AxGen.InitText(main)) != "")
            opened := "g.OnReady((*) => (" AxGen.InitFn(main) "()" (AxBind.Any(project) ? ", AxBindSync()" : "") "))"
        ; before Show, because Show is what builds the page
        if (Trim(pre) != "")
            show := pre nl show
        ; The bindings' guard is read by the first sync, which is up here --
        ; so it is set up here too. Written with the functions, further down
        ; the file, it was still unset when they first ran: top-level code
        ; runs top to bottom, and the bindings region is below Show().
        if AxBind.Any(project)
            show := "AxBindBusy := false" nl show
        ; hotstrings made, and the timers that start with the program started
        show .= AxAuto.StartCode(project)
        ; hidden: built and ready, for a tray icon or a hotkey to bring up
        if hasMain {
            show .= AxStart.ShowLines(project, main, "g", "")
            show .= AxStart.After(project, main, "g", "")
        }
        ; events, folder watchers, macro hotkeys, starting with Windows: they
        ; need the window's handle, so after it exists
        show .= AxAuto2.StartCode(project)
        tray := AxAsset.TrayCode(project)
        if (Trim(tray) != "")
            show .= tray nl
        ; a mode is chosen after the window is up, because most of them do
        ; something to it
        if AxAsset.Modes(project).Length
            show .= "if (Mode0 := AxModeArg())" nl "    Mode(Mode0)" nl
        ; these two are not constructor options: they act on a window that is up
        if (hasMain && main.AlwaysOnTop)
            show .= "g.AlwaysOnTop(true)" nl
        if (hasMain && main.Opacity != "" && Integer(main.Opacity) < 255)
            show .= 'WinSetTransparent(' AxGen.N(main.Opacity) ', "ahk_id " g.Hwnd)' nl

        windows := ""
        for w in project.Wins {
            if (hasMain && AxProject.Same(w, main))
                continue
            windows .= (windows = "" ? "" : nl) AxGen._Builder(project, w, state)
        }

        ; Ahk2Exe reads its directives out of the source and stops at the
        ; first line of real code, so they go above everything.
        s := ""
        comp := AxAsset.CompileCode(project)
        if (Trim(comp) != "")
            s .= AxMerge.Region("compile", comp) nl
        s .= AxMerge.Region("head", head)
        s .= nl AxMerge.Region("ui", m.Ui)
        if (Trim(m.Events) != "")
            s .= nl AxMerge.Region("events", m.Events)
        s .= nl AxMerge.Region("show", show)
        if (windows != "")
            s .= nl AxMerge.Region("windows", windows)
        ; The debug block goes after the window is up, because it moves it
        ; back to where the last run left it. It is its own region, so a script
        ; that was run and then exported loses it cleanly on the next export.
        if IsObject(dbg)
            s .= nl AxMerge.Region("debug", AxDbg.Region(project, dbg))
        if AxBind.Any(project) {
            names := []
            for v in state.all
                names.Push(v)
            s .= nl AxMerge.Region("bindings", AxBind.Region(project, AxGen._Globals(names, "    ")))
        }
        flows := AxGen._Flows(project, state)
        if (Trim(flows) != "")
            s .= nl AxMerge.Region("flows", flows)
        args := AxAsset.ArgsCode(project)
        if (Trim(args) != "")
            s .= nl AxMerge.Region("args", args)
        modes := AxAsset.ModesCode(project, project)
        if (Trim(modes) != "")
            s .= nl AxMerge.Region("modes", modes AxGen._ModeArg())
        files := AxAsset.FilesCode(project)
        if (Trim(files) != "")
            s .= nl AxMerge.Region("files", files)
        ; methods of .NET (through AHK#) and of libraries, made functions
        net := AxNet.Code(project)
        if (Trim(net) != "")
            s .= nl AxMerge.Region("adaptors", net)
        for rg in [["conditions", AxAuto.CondCode(project)], ["hotstrings", AxAuto.StringCode(project)],
                   ["timers", AxAuto.TimerCode(project)], ["hotkeys", AxAsset.HotkeyStepFns(project)]]
            if (Trim(rg[2]) != "")
                s .= nl AxMerge.Region(rg[1], rg[2])
        for rg in AxAuto2.Regions(project)
            s .= nl AxMerge.Region(rg[1], rg[2])
        place := AxStart.Code(project)
        if (Trim(place) != "")
            s .= nl AxMerge.Region("start", place)
        s .= nl AxMerge.Region("handlers", AxGen._Handlers(state))
        ; A script block per window, always written even when empty: an empty
        ; one is the labelled place your own functions go, and opening the
        ; file reads whatever you put there back into the project.
        for w in project.Wins
            s .= nl AxMerge.Region("script." StrLower(AxProject.CleanName(w.Name)),
                                   AxGen.Block(w.Script, ""))
        if (opened != "")
            s .= nl AxMerge.Region("opened", opened)
        return s
    }

    ; The function that holds one window's startup code. Emitted whether or
    ; not there is any, because it is where a hand edit is read back from.
    static InitFn(w) => AxProject.CleanName(w.Name) "Init"
    ; A window's startup code as it is written out: its hotkeys first -- kept
    ; as lines, like rules, they only become code here -- then what was typed
    ; into its startup code.
    static InitText(w) {
        hk := AxAsset.HotkeysCode(w)
        return (hk = "") ? w.Init : hk w.Init
    }

    ; Everything inside one window: the AxGui call, its controls, its bars,
    ; and the wiring for them. Leaves state.vars holding just this window's
    ; variables, which is what its builder has to declare global.
    static _WinCode(project, w, state) {
        nl := "`n"
        state.vars := Map(), state.wiring := "", state.popovers := []
        state.g := w.Var, state.win := w
        gv := w.Var
        state.all[gv] := true

        ui := gv " := AxGui(" AxGen._WinOpts(w) ")" nl
        loose := []
        for k in w.Root.Kids
            if (k.Type != "Page")
                loose.Push(k)
        if loose.Length {
            ui .= nl "; --- above the pages" nl
            ui .= AxGen._Code(loose, gv ".Use()", 0, state)
        }
        for p in w.Root.Kids {
            if (p.Type != "Page")
                continue
            ui .= nl "; --- page: " p.Prop("title", p.Name) nl
            ui .= gv '.AddPage(' AxGen.S(p.Name) ", " AxGen.S(p.Prop("title", "")) ", " AxGen.S(p.Prop("icon", "")) ")" nl
            ui .= AxGen._Code(p.Kids, gv ".Use()", 0, state)
        }
        look := AxTheme.Css(w)
        if (Trim(look) != "")
            ui .= nl gv ".SetExtraCss(" AxGen.S("axLook") ", " AxLit.Section(look, "    ") ")" nl   ; CSS is text, not code
        ; no title bar: the sheets size the shell to leave room for one, so
        ; the page stacks its bars and lets the shell take what is left
        ; how the page scrolls when it is taller than the window
        if (w.PageScroll = "always")
            ui .= gv ".SetExtraCss(" AxGen.S("axScroll") ", " AxGen.S("#content{-ms-overflow-style:scrollbar}") ")" nl
        else if (w.PageScroll = "never")
            ui .= gv ".SetExtraCss(" AxGen.S("axScroll") ", " AxGen.S("#content{overflow:hidden !important}") ")" nl
        if !w.Frame
            ui .= gv ".SetExtraCss(" AxGen.S("axBare") ", " AxGen.S("body{display:flex;flex-direction:column}#shell{-ms-flex:1 1 0%;flex:1 1 0%;height:auto !important;min-height:0}") ")" nl
        menu := (Trim(w.MenuBar) != "") ? Trim(w.MenuBar) : AxChrome.MenuCode(w.Menus, state)
        if (menu != "")
            ui .= nl gv ".AddMenuBar(" menu ")" nl
        stat := (Trim(w.StatusBar) != "") ? Trim(w.StatusBar) : AxChrome.StatusCode(w.Status)
        if (stat != "")
            ui .= nl gv ".AddStatusBar(" stat ")" nl
        tb := AxChrome.TitleCode(w.TitleItems, state)
        if (tb != "") {
            o := ""
            if !w.TitleShow
                o .= "ShowTitle: false"
            if w.TitleCenter
                o .= (o = "" ? "" : ", ") "CenterTitle: true"
            ui .= nl gv ".AddTitleBar(" tb (o != "" ? ", {" o "}" : "") ")" nl
        }

        events := state.wiring
        ; right-click menus: each a function that builds it as it opens
        ctx := AxChrome.CtxCode(w, state)
        if (ctx != "")
            events .= nl "; --- right-click menus" nl ctx
        ; asked before it closes -- the close button, the icon, Alt+F4, the
        ; taskbar, the tray's Exit alike (Window tab, Keys and closing)
        cl := AxGen.CloseCode(w, state)
        if (cl != "")
            events .= nl "; --- before it closes" nl cl
        if state.popovers.Length {
            ; a popover is anchored to an element, so it is registered for the
            ; moment the document exists rather than before there is one
            events .= nl "; --- popovers" nl
            for n in state.popovers
                events .= gv ".OnReady((*) => " gv ".Popover(" AxLit.S(n.Name) ", " AxGen.PopSpec(n) "))" nl
        }
        return {Ui: ui, Events: events, Vars: state.vars}
    }

    ; AskClose / SaveWith / BeforeClose as the calls AxWindow has for them. A
    ; function the script does not define is left out with a comment, not
    ; written in to stop the script at start-up.
    static CloseCode(w, state) {
        gv := w.Var, out := "", nl := "`n"
        ask := String(w.AskClose), save := Trim(String(w.SaveWith)), own := Trim(String(w.BeforeClose))
        if (ask = "dirty" || ask = "always") {
            fn := ""
            if (save != "") {
                if AxGen._Taken(state, save)
                    fn := save
                else
                    out .= "; saving before it closes: " save " is not a function in the script" nl
            }
            if (ask = "always")
                out .= gv ".AskBeforeClose(" (fn != "" ? fn : '""') ", {Always: true})" nl
            else
                out .= gv ".AskBeforeClose(" fn ")" nl
        }
        if (own != "")
            out .= AxGen._Taken(state, own) ? gv ".OnBeforeClose(" own ")" nl
                 : "; before it closes: " own " is not a function in the script" nl
        return out
    }
    ; A window that is not the main one is a function. Calling it is how any
    ; other window opens it, which is the whole of the linking: the studio
    ; writes ShowSettings() into a handler and the two windows are connected.
    static _Builder(project, w, state) {
        nl := "`n"
        gv := w.Var
        m := AxGen._WinCode(project, w, state)
        modal := (w.Kind = "dialog")
        made := (w.Kind = "code")           ; built for the script's own code, which shows it
        outVar := AxProject.CleanName(w.Name) "Result"
        ins := AxGen.Inputs(w)
        sig := ""
        for i in ins
            sig .= (sig = "" ? "" : ", ") i.Name " := " (i.Def != "" ? i.Def : '""')

        ; the globals this function assigns: its own window, its controls, and
        ; where a modal one leaves what it was asked for
        names := [gv]
        if modal
            names.Push(outVar), state.all[outVar] := true
        for v in m.Vars
            names.Push(v)

        s := "; ------------------------------------------------ " w.Name nl
        s .= gv ' := ""' nl
        if modal
            s .= outVar ' := ""' nl
        s .= AxGen.WinDoc(w, ins)
        s .= AxGen.Fn(w) "(" sig ") {" nl
        s .= AxGen._Globals(names, "    ")
        if made {
        } else if !modal {
            ; already up: bring it forward rather than building a second one
            s .= "    if IsObject(" gv ") && !" gv ".Closing {" nl
            s .= '        WinActivate("ahk_id " ' gv ".Hwnd)" nl
            s .= "        return " gv nl
            s .= "    }" nl
        } else
            s .= "    " outVar ' := ""' nl
        s .= AxGen.Block(m.Ui, "    ") nl
        if (Trim(m.Events) != "")
            s .= AxGen.Block(m.Events, "    ") nl
        outs := AxGen.Outputs(w)
        if (modal && outs.Length) {
            ; read while the window is still standing: OnClose runs before the
            ; controls are destroyed, which is the only moment the values exist
            pairs := ""
            for o in outs
                pairs .= (pairs = "" ? "" : ", ") AxLit.S(o.Name) ", " o.Expr
            s .= "    " gv ".OnClose((*) => " outVar " := Map(" pairs "))" nl
        }
        if AxBind.Any(project)
            s .= "    AxBindSync()" nl
        if (Trim(AxGen.InitText(w)) != "") {                 ; when its page is there, as the main window's
            pass := ""
            for i in ins
                pass .= (pass = "" ? "" : ", ") i.Name
            s .= "    " gv ".OnReady((*) => SetTimer(() => (" AxGen.InitFn(w) "(" pass ")" (AxBind.Any(project) ? ", AxBindSync()" : "") "), -1))" nl
        }
        if state.dbg
            s .= "    AxDbgWire(" gv ", " AxLit.S(w.Name) ")" nl
        if !made {
            s .= AxStart.ShowLines(project, w, gv, "    ")
            s .= AxStart.After(project, w, gv, "    ")
        }
        if modal {
            s .= "    while IsObject(" gv ") && !" gv ".Closing" nl
            s .= "        Sleep 20" nl
            s .= "    " gv ' := ""' nl
            s .= "    return " outVar nl
        } else
            s .= "    return " gv nl
        s .= "}" nl
        return s
    }
    ; A line above each builder saying how to call it, because the name of an
    ; input is the only documentation there would otherwise be.
    static WinDoc(w, ins) {
        call := AxGen.Fn(w) "("
        for i, x in ins
            call .= (i > 1 ? ", " : "") x.Name
        call .= ")"
        s := "; " (w.Kind = "dialog" ? "Modal. r := " call " returns a Map of its outputs, or " '""' " if it was closed."
                 : w.Kind = "code"   ? call " builds it and hands it back, not yet shown: the code that calls it shows it."
                                     : call " opens it, and brings it forward if it is already up.") "`n"
        return s
    }
    static Fn(w) => (w.Kind = "code" ? "Make" : "Show") AxProject.CleanName(w.Name)
    ; name = default, one per line.
    static Inputs(w) {
        out := []
        for line in StrSplit(StrReplace(String(w.Inputs), "`r", ""), "`n") {
            if (Trim(line) = "" || SubStr(Trim(line), 1, 1) = ";")
                continue
            ; RegExMatch leaves the match variable unset when nothing matched,
            ; so what happened is read from the return value, not from &m
            if !RegExMatch(Trim(line), "^([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*(.*))?$", &m)
                continue
            out.Push({Name: m[1], Def: Trim(m[2])})
        }
        return out
    }
    ; name = expression, one per line.
    static Outputs(w) {
        out := []
        for line in StrSplit(StrReplace(String(w.Outputs), "`r", ""), "`n") {
            if (Trim(line) = "" || SubStr(Trim(line), 1, 1) = ";")
                continue
            if !RegExMatch(Trim(line), "^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$", &m)
                continue
            out.Push({Name: m[1], Expr: Trim(m[2])})
        }
        return out
    }
    ; A global declaration, wrapped so no single line runs away.
    static _Globals(names, pad) {
        decl := "", chunk := "", n := 0
        for v in names {
            chunk .= (chunk = "" ? "" : ", ") v
            if (++n >= 8)
                decl .= pad "global " chunk "`n", chunk := "", n := 0
        }
        if (chunk != "")
            decl .= pad "global " chunk "`n"
        return decl
    }

    static _WinOpts(p) {
        o := []
        o.Push("Title: " AxGen.S(p.Title))
        o.Push("Width: " AxGen.N(p.Width))
        o.Push("Height: " AxGen.N(p.Height))
        if (p.MinWidth > 0)
            o.Push("MinWidth: " AxGen.N(p.MinWidth))
        if (p.MinHeight > 0)
            o.Push("MinHeight: " AxGen.N(p.MinHeight))
        o.Push("Theme: " AxGen.S(p.Theme))
        if (p.Stylesheet != "" && p.Stylesheet != "win11")
            o.Push("Stylesheet: " AxGen.S(p.Stylesheet))
        if (p.Accent != "")
            o.Push("Accent: " AxGen.S(p.Accent))
        if (p.Tint != "") {
            o.Push("Tint: " AxGen.S(p.Tint))
            o.Push("TintStrength: " AxGen.N(p.TintStrength))
        }
        if !p.Nav
            o.Push("Nav: false")
        if (p.Headings != "")
            o.Push("Headings: " (p.Headings ? "true" : "false"))
        if p.EscapeCloses
            o.Push("EscapeCloses: true")
        if !p.Resizable
            o.Push("Resizable: false")
        ; a blank box is no icon, as the canvas draws it -- not the default
        if (p.Icon != "auto")
            o.Push("Icon: " AxGen.S(Trim(p.Icon) = "" ? "none" : p.Icon))
        ; everything else the constructor takes, emitted only where it differs
        ; from what AxWindow would have done anyway
        F := (name, on) => (on ? o.Push(name ": true") : o.Push(name ": false"))
        if !p.MaximizeBox
            F("MaximizeBox", false)
        if !p.MinimizeBox
            F("MinimizeBox", false)
        if !p.RoundCorners
            F("RoundCorners", false)
        if !p.SnapLayouts
            F("SnapLayouts", false)
        if p.NoActivate
            F("NoActivate", true)
        if !p.ExitOnClose
            F("ExitOnClose", false)
        if p.AllowZoom
            F("AllowZoom", true)
        if p.NativeContextMenu
            F("NativeContextMenu", true)
        if p.Composited
            F("Composited", true)
        if (p.BorderColor != "")
            o.Push("BorderColor: " AxGen.S(p.BorderColor))
        if (p.SnapBorder != "")
            o.Push("SnapBorder: " AxGen.S(p.SnapBorder))
        if (p.FocusRing != "")
            o.Push("FocusRing: " AxGen.S(p.FocusRing))
        if (p.AppName != "")
            o.Push("AppName: " AxGen.S(p.AppName))
        if (p.AppId != "")
            o.Push("AppId: " AxGen.S(p.AppId))
        if (p.TooltipDelay != "" && IsInteger(p.TooltipDelay))
            o.Push("TooltipDelay: " Integer(p.TooltipDelay))
        if !p.UseAccent
            F("UseAccent", false)
        if !p.Frame
            F("Frame", false)
        if (p.BackColor != "")
            o.Push("BackColor: " AxGen.S(p.BackColor))
        ; a place of its own only when that is where it was asked to open
        if (p.WinX != "" && AxStart.PosOf(p) = "xy")
            o.Push("X: " AxGen.N(p.WinX))
        if (p.WinY != "" && AxStart.PosOf(p) = "xy")
            o.Push("Y: " AxGen.N(p.WinY))
        s := ""
        for x in o
            s .= (s = "" ? "" : ", ") x
        return "{" s "}"
    }

    ; Walk a list of siblings into code. `back` is the statement that returns
    ; the builder to where this list started, which a container has to emit
    ; when it closes. A tab panel can only be re-entered with UseTab, so it is
    ; a statement rather than a container variable.
    static _Code(kids, back, depth, state) {
        nl := "`n"
        pad := AxGen.Pad(depth)
        out := ""
        for n in kids {
            if (n.Type = "Page")
                continue
            ; code that runs here, as it was written
            if (n.Type = "Code") {
                if (Trim(n.Arg) != "")
                    out .= AxGen.Block(n.Arg, pad) nl
                continue
            }
            opts := AxGen.OptString(n, false)
            call := state.g ".Add" n.Type "(" AxGen.S(opts) AxGen._ArgCode(n) ")"
            ; Every named control gets a variable, whether or not this one has
            ; a handler: a handler on some *other* control is the usual reason
            ; to reach for it, and a name that is only in the option string is
            ; not a name any AHK in the file can use.
            var := (Trim(n.Name) != "" || n.Box) ? AxGen._Var(n, state) : ""
            if (var != "")
                out .= pad var " := " call nl
            else
                out .= pad call nl
            for e in n.Ev
                AxGen._Event(state, n, var, e)
            ; rules can name an event the control has no handler for: that
            ; still has to be wired, or the rules never run
            AxGen._ExtraEvents(state, n, var)
            if (Trim(n.Lay("pop", "")) != "")
                state.popovers.Push(n)
            if n.Box {
                if (n.Type = "Tab")
                    out .= AxGen._TabCode(n, var, depth, state)
                else
                    out .= AxGen._Code(n.Kids, state.g ".Use(" var ")", depth + 1, state)
                out .= pad back nl
            }
        }
        return out
    }
    static _TabCode(n, var, depth, state) {
        nl := "`n"
        pad := AxGen.Pad(depth)
        out := ""
        loop AxGen.TabCount(n) {
            i := A_Index
            group := []
            for k in n.Kids
                if (AxGen.TabOf(k) = i)
                    group.Push(k)
            if !group.Length
                continue
            out .= pad var ".UseTab(" i ")" nl
            out .= AxGen._Code(group, var ".UseTab(" i ")", depth + 1, state)
        }
        return out
    }
    ; A variable name for a control: its own name where that is usable, never
    ; one that would shadow the window or a handler already written.
    static _Var(n, state) {
        static reserved := Map("g", 1, "true", 1, "false", 1, "this", 1, "super", 1, "global", 1, "local", 1, "static", 1)
        v := AxProject.CleanName(n.Name)
        if (v = "")
            v := "ctl" (state.vars.Count + 1)
        ; a function or class of the window's own script already has this name
        ; (a console called log beside Log()): AutoHotkey will not have both,
        ; so the control goes by its id alone, as the script it came from did
        if (!n.Box && AxGen._Taken(state, v))
            return ""
        ; clear of every other window's variables too: they all end up in the
        ; one script, so a clash there is a control quietly overwritten
        ; ... and never one of AutoHotkey's own functions or classes: a list
        ; box called log becomes `log := g.AddListBox(...)`, and Log is a
        ; function, which cannot be assigned to -- the script would not load
        while (state.all.Has(v) || reserved.Has(StrLower(v)) || AxGen.BuiltIn(v))
            v := v "_"
        state.vars[v] := true
        state.all[v] := true
        return v
    }
    ; A name AutoHotkey already has: Log, Sort, Format, Round, Map, Gui...
    ; Asked of the interpreter rather than kept as a list, so it is never
    ; out of date. The studio's own classes are Ax-prefixed, and so are left
    ; alone by the prefix test rather than the lookup.
    static BuiltIn(v) {
        if (v = "" || SubStr(v, 1, 2) = "Ax" || !RegExMatch(v, "^[A-Za-z_]\w*$"))
            return false
        try {
            x := %v%
            return (x is Func) || (x is Class)
        }
        return false
    }
    ; Names the windows' own code defines at the top: functions and classes.
    static _Taken(state, v) {
        if !state.HasOwnProp("fns") {
            m := Map()
            m.CaseSense := false
            for w in state.project.Wins
                for text in [w.Script, w.Init] {
                    pos := 1
                    while (pos := RegExMatch(String(text), "m)^[ \t]*(?:class[ \t]+)?([A-Za-z_]\w*)(?:\(.*\)[ \t]*(?:\{|=>|$)|[ \t]+(?:extends\b|\{))", &mm, pos))
                        pos += mm.Len, m[mm[1]] := true
                }
            state.fns := m
        }
        return state.fns.Has(v)
    }
    static _ArgCode(n) {
        e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
        if !IsObject(e) || !IsObject(e.Arg)
            return ""
        v := AxGen.ArgValue(n)
        if AxGen.ArgIsRaw(n)
            return ", " (Trim(v) != "" ? AxGen.Inline(v) : '""')
        if (n.Type = "Tab")
            return ", " AxGen.S(v)
        if (v = "" && !e.Arg.HasOwnProp("Always"))
            return ""
        return ", " AxGen.S(v)
    }
    ; Events this control needs wired that it has no handler of its own for:
    ; one a rule listens to, and the change event a two-way binding reads it
    ; back on. Without this the rule never runs and the binding is one-way by
    ; accident.
    static _ExtraEvents(state, n, var) {
        w := state.win
        if !IsObject(w) || Trim(n.Name) = ""
            return
        want := Map()
        for pair in AxFlow.Pairs(w)
            if (pair.Ctl = n.Name)
                want[AxFlow.EvBase(pair.Ev)] := true       ; "Hit:coin" needs the Hit handler
        for b in AxBind.PullsFor(state.project, w, n.Name)
            want[AxBind.PullEvent(state.project, b)] := true
        for ev in want {
            has := false
            for e in n.Ev
                if (e["name"] = ev)
                    has := true
            if !has
                AxGen._Event(state, n, var, Map("name", ev, "code", ""))
        }
    }
    static _Event(state, n, var, e) {
        name := e["name"], code := e["code"]
        fnName := AxGen.HandlerName(n, name, state)
        wire := AxCat.Wire(name)
        target := (var != "") ? var : (state.g '.Ctl(' AxGen.S(n.Name) ')')
        if AxCat.IsPart(name)                 ; a part of its popover, by its id there
            state.wiring .= state.g '.On("click", ' AxGen.S(AxCat.PartId(name)) ", " fnName ")`n"
        else if (wire != "")
            state.wiring .= target "." wire "(" fnName ")`n"
        else
            state.wiring .= target '.OnEvent(' AxGen.S(name) ", " fnName ")`n"
        sig := AxCat.Sig(name)
        body := Trim(code, " `t`r`n") != "" ? AxGen.Block(code, "    ") : "    `; nothing here yet"
        ; the rules first: the event's own, then each narrowed one (Hit:coin)
        calls := IsObject(state.win) ? AxFlow.CallsFor(state.win, n.Name, name) : []
        lead := ""
        for c in calls
            lead .= "    " c "`n"
        body := lead body
        ; a two-way binding reads the control back before anything else looks
        ; at the variable
        pulls := IsObject(state.win) ? AxBind.PullsFor(state.project, state.win, n.Name) : []
        if (pulls.Length && name = AxBind.PullEvent(state.project, pulls[1]))
            body := "    AxBindPull(" AxGen.S(n.Name) ")`n" body
        state.handlerList.Push({Name: fnName, Sig: sig, Body: body})
    }
    ; Handlers are assembled last, because only then is the full list of control
    ; variables known -- and a handler that cannot see the other controls on the
    ; page is a handler you have to hand-edit before it does anything.
    ; The rules and states of every window, as functions. They see the same
    ; globals a handler does, because they do the same kind of work.
    static _Flows(project, state) {
        names := []
        for v in state.all
            names.Push(v)
        decl := AxGen._Globals(names, "    ")
        out := ""
        for w in project.Wins
            out .= AxFlow.Funcs(project, w, decl)
        return out
    }
    static _Handlers(state) {
        names := []
        for v in state.all
            names.Push(v)
        decl := AxGen._Globals(names, "    ")
        out := ""
        for h in state.handlerList
            out .= h.Name "(" h.Sig ") {`n" decl h.Body "`n}`n`n"
        ; One startup function per window, written whether or not it has any
        ; code in it: it is the labelled place startup code goes, and the only
        ; way an edit made in the file finds its way back to the project.
        ;
        ; It takes the window's inputs, because the builder has them as
        ; parameters and startup code is the one place they are wanted. They
        ; are therefore left out of the global list -- AutoHotkey will not have
        ; a parameter and a global of one name.
        for w in state.project.Wins {
            ins := (w.Kind = "main") ? [] : AxGen.Inputs(w)
            sig := "", skip := Map()
            for i in ins {
                sig .= (sig = "" ? "" : ", ") i.Name " := " (i.Def != "" ? i.Def : '""')
                skip[i.Name] := true
            }
            mine := decl
            if skip.Count {
                keep := []
                for v in names
                    if !skip.Has(v)
                        keep.Push(v)
                mine := AxGen._Globals(keep, "    ")
            }
            init := AxGen.InitText(w)
            body := (Trim(init) != "") ? AxGen.Block(init, "    ") : "    `; nothing here yet"
            out .= AxGen.InitFn(w) "(" sig ") {`n" mine body "`n}`n`n"
        }
        return out
    }
    ; --mode <name>, or the first bare word. Written out rather than folded
    ; into ReadArgs so a project with modes and no arguments still gets it.
    static _ModeArg() {
        q := Chr(34), nl := "`n"
        return nl "AxModeArg() {" nl
             . "    i := 1" nl
             . "    while (i <= A_Args.Length) {" nl
             . "        if (A_Args[i] = " q "--mode" q " && i < A_Args.Length)" nl
             . "            return A_Args[i + 1]" nl
             . "        if (SubStr(A_Args[i], 1, 1) != " q "-" q ")" nl
             . "            return A_Args[i]" nl
             . "        i++" nl
             . "    }" nl
             . "    return " q q nl
             . "}" nl
    }
    static HandlerName(n, event, state := "") {
        base := AxProject.CleanName(n.Name)
        if (base = "")
            base := "ctl" AxProject.CleanName(n.Id)
        return base "_" RegExReplace(event, "[^\w]", "_")
    }


    ; A flat table of the tree: one row per node, tab separated. Not the save
    ; format -- a tree does not survive being flattened -- but it is the view
    ; that greps, diffs and pastes into a spreadsheet.
    static Tsv(project) {
        rows := "window`tid`tparent`tindex`tdepth`ttype`tname`targ`toptions`tevents`n"
        ; the window goes in the first column, because a project is several of
        ; them now and a flat table with no way to tell them apart is a table
        ; you cannot sort
        win := ""
        add := (n, depth) => ""
        add := (n, depth) => (
            rows .= win "`t" n.Id "`t" (IsObject(n.Parent) ? n.Parent.Id : "") "`t"
                 .  project.IndexOf(n) "`t" depth "`t"
                 .  n.Type "`t" n.Name "`t" AxGen._Cell(n.Arg) "`t"
                 .  AxGen._Cell(AxGen.OptString(n)) "`t" AxGen._Ev(n) "`n",
            AxGen._Each(n, (c) => add(c, depth + 1)))
        for w in project.Wins {
            win := w.Name
            for k in w.Root.Kids
                add(k, 0)
        }
        return rows
    }
    static _Each(node, fn) {
        for k in node.Kids
            fn(k)
    }
    ; A cell cannot hold a real line break or a tab, so both are spelled out.
    static _Cell(s) => StrReplace(StrReplace(StrReplace(String(s), "`r", ""), "`n", "\n"), "`t", " ")
    static _Ev(n) {
        s := ""
        for e in n.Ev
            s .= (s = "" ? "" : " ") e["name"]
        return s
    }

    ; ------------------------------------------------------------- helpers
    ; Writing AutoHotkey out as text lives in AxLit, because the chrome
    ; generator needs the same helpers and cannot depend on this file.
    static S(v)          => AxLit.S(v)
    static N(v)          => AxLit.N(v)
    static Q(v)          => AxLit.Q(v)
    static Inline(v)     => AxLit.Inline(v)
    static Block(c, pad) => AxLit.Block(c, pad)
    static Pad(depth)    => AxLit.Pad(depth)
    static PopSpec(n) {
        o := "Html: " AxLit.S(Trim(n.Lay("pop", "")))
        on := n.Lay("popon", "click")
        if (on != "" && on != "click")
            o .= ", On: " AxLit.S(on)
        al := n.Lay("popalign", "left")
        if (al != "" && al != "left")
            o .= ", Align: " AxLit.S(al)
        if (n.Lay("popw", "") != "")
            o .= ", Width: " AxLit.N(n.Lay("popw"))
        return "{" o "}"
    }
    ; A #Include path: relative when the export sits under the same root as the
    ; library (so the pair can be moved together), absolute when it does not.
    static RelInclude(outPath, target) => AxGen.IncQuote(AxGen.RelPath(outPath, target))
    ; The same path for an Ahk2Exe Let. Ahk2Exe has no notion of "relative to
    ; the script" on its own -- %A_ScriptDir% is how you say it -- and a target
    ; on another drive has no relative form at all, so that goes in whole.
    ; Only what this design actually reads: the sheet it wears and whatever
    ; that sheet extends, the overlay furniture every window injects, and the
    ; notification icons. The names are AxSys.ResName's, because that is what
    ; AxWindow.ReadLib will ask the exe for.
    static LibResources(project, libDir) {
        nl := "`n"
        rel := ["themes\base.css", "themes\builder.css",
                "ui\frame.html", "ui\resize.html", "ui\overlays.html",
                "icons\info.png", "icons\warning.png", "icons\error.png"]
        for name in AxGen.SheetChain(project.Stylesheet, libDir)
            rel.Push("themes\" name ".css")
        s := "; Only the library files this design reads. File > Compile can" nl
           . "; embed all of them instead, which is a little larger and cannot" nl
           . "; be wrong." nl
        for r in rel
            s .= ";@Ahk2Exe-AddResource %U_AxLib%\" r ", " AxGen.ResName(r) nl
        return s
    }
    ; The same rule AxSys.ResName uses, because the exe is asked for that name.
    static ResName(rel) => "AX_" StrUpper(RegExReplace(rel, "[\\/.\-]", "_"))
    ; A sheet may open with  /* @extends win11 */  -- AxGui.ThemeCss loads the
    ; base first and appends the sheet, so both have to be in the exe.
    static SheetChain(name, libDir) {
        out := [], seen := Map()
        cur := (name = "") ? "win11" : name
        loop 8 {
            if (cur = "" || InStr(cur, ".css") || InStr(cur, "\"))
                break                          ; a path of your own, not a lib sheet
            key := StrLower(cur)
            if seen.Has(key)
                break
            seen[key] := true
            out.Push(cur)
            css := ""
            try css := FileRead(libDir "\themes\" cur ".css", "UTF-8")
            if !RegExMatch(css, "i)^\s*/\*\s*@extends\s+([A-Za-z0-9_.\-]+)\s*\*/", &m)
                break
            cur := m[1]
        }
        return out
    }
    static KeepDevTools(project) {
        cmp := AxAsset.Compile(project)
        return cmp.Has("devtools") && StrLower(cmp["devtools"]) = "keep"
    }
    static LetPath(outPath, target) {
        rel := AxGen.RelPath(outPath, target)
        if (rel = target)
            return target
        return "%A_ScriptDir%\" rel
    }

    ; target, written relative to the folder outPath lives in. Falls back to
    ; the full path when they are on different drives -- there is no relative
    ; way to say that.
    static RelPath(outPath, target) {
        if (outPath = "")
            return target
        SplitPath(outPath, , &outDir)
        if (outDir = "")
            return target
        a := StrSplit(RTrim(StrReplace(outDir, "/", "\"), "\"), "\")
        b := StrSplit(StrReplace(target, "/", "\"), "\")
        if (a.Length = 0 || b.Length = 0 || StrLower(a[1]) != StrLower(b[1]))
            return target
        i := 1
        while (i <= a.Length && i < b.Length && StrLower(a[i]) = StrLower(b[i]))
            i++
        rel := ""
        loop (a.Length - i + 1)
            rel .= "..\"
        loop (b.Length - i + 1)
            rel .= b[i + A_Index - 1] (A_Index < b.Length - i + 1 ? "\" : "")
        return rel != "" ? rel : target
    }
    static IncQuote(p) => InStr(p, " ") ? '"' p '"' : p
}

; Where the studio found the library it is designing for.
class AxStudioPaths {
    static Root := ""
    static Lib := ""
    static __New() {
        d := A_ScriptDir
        loop 4 {
            if FileExist(d "\lib\AxGui.ahk") {
                AxStudioPaths.Root := d
                AxStudioPaths.Lib := d "\lib"
                return
            }
            SplitPath(d, , &up)
            if (up = "" || up = d)
                break
            d := up
        }
        AxStudioPaths.Root := A_ScriptDir
        AxStudioPaths.Lib := A_ScriptDir "\lib"
    }
    ; Where the studio keeps its own things -- settings, the autosave, the
    ; log, saved looks, the library and NuGet caches: studio\data, beside the
    ; studio, so it travels with the folder and nothing is left in the
    ; profile. Only a copy that cannot write there (one in Program Files)
    ; falls back to %AppData%\AxStudio.
    static _data := ""
    static Data() {
        if (AxStudioPaths._data != "")
            return AxStudioPaths._data
        SplitPath(A_LineFile, , &here)
        d := here "\data", ok := false
        try {
            if !DirExist(d)
                DirCreate(d)
            FileAppend("", d "\.write-test")
            FileDelete(d "\.write-test")
            ok := true
        }
        if !ok {
            d := A_AppData "\AxStudio"
            try DirCreate(d)
        }
        AxStudioPaths._data := d
        return d
    }
    ; Once, the first time the studio runs with a local folder: what an
    ; older copy kept in %AppData%\AxStudio is copied across, so the recent
    ; projects, the settings and an unsaved design are still there. The old
    ; folder is left alone -- delete it when you like.
    static Adopt(d) {
        old := A_AppData "\AxStudio"
        if (d = old || FileExist(d "\studio.ini") || !FileExist(old "\studio.ini"))
            return false
        for f in ["studio.ini", "autosave.axs.json", "preview.ini"]
            if FileExist(old "\" f)
                try FileCopy(old "\" f, d "\" f)
        for sub in ["themes", "aris", "nuget"]
            if (DirExist(old "\" sub) && !DirExist(d "\" sub))
                try DirCopy(old "\" sub, d "\" sub)
        return true
    }
}

; =============================================================================
;  How a window starts, and the keyboard in it: where it opens (where Windows
;  puts it, on the screen the mouse is on, where it was last time, or at a
;  place of its own), whether it opens maximised, minimised or hidden, the
;  order Tab visits its controls in, and the buttons Enter and Escape press.
;  AxKeyOrder says which controls take the keyboard and in what order; AxStart
;  writes the lines that do the rest after Show(), and the few functions
;  those lines call.
; =============================================================================
class AxKeyOrder {
    ; what never takes the keyboard, whatever its name
    static NoFocus := "|Text|Label|Separator|Progress|Image|Picture|Svg|Badge|Gauge|Html|Splitter|"
                    . "InfoBar|Thumbs|Console|"
    static Takes(n) {
        if (n.Name = "" || !AxCat.Has(n.Type))
            return false
        e := AxCat.Get(n.Type)
        return !e.Box && !InStr(AxKeyOrder.NoFocus, "|" n.Type "|")
    }
    ; the controls that take the keyboard, in the order they are laid out
    static Layout(p, w) {
        out := []
        p.Walk(w.Root, AxKeyOrder.CollectFn(out))
        return out
    }
    static CollectFn(out) => (n) => (AxKeyOrder.Takes(n) ? out.Push(n) : 0, false)
    static Explicit(w) => Trim(String(w.TabOrder)) != ""
    ; the order Tab goes in: the names written down, then the rest as laid out
    static Order(p, w) {
        all := AxKeyOrder.Layout(p, w), out := [], seen := Map()
        seen.CaseSense := false
        for line in StrSplit(StrReplace(String(w.TabOrder), "`r", ""), "`n") {
            nm := Trim(line)
            if (nm = "" || seen.Has(nm))
                continue
            for n in all {
                if (n.Name = nm) {
                    out.Push(n), seen[nm] := true
                    break
                }
            }
        }
        for n in all
            if !seen.Has(n.Name)
                out.Push(n)
        return out
    }
    static Text(p, w) {
        s := ""
        for n in AxKeyOrder.Order(p, w)
            s .= (s = "" ? "" : "`n") n.Name
        return s
    }
    ; the buttons in a window, for "Enter presses" and "Escape presses"
    static Buttons(p, w) {
        out := []
        p.Walk(w.Root, AxKeyOrder.ButtonFn(out))
        return out
    }
    static ButtonFn(out) => (n) => ((n.Type = "Button" && n.Name != "") ? out.Push(n) : 0, false)
}

class AxStart {
    ; "remember", "mouse", "xy" or "auto" -- a window from before there was a
    ; choice, with an X or a Y set, was at a place of its own
    static PosOf(w) => (w.StartPos != "") ? w.StartPos : ((w.WinX != "" || w.WinY != "") ? "xy" : "auto")
    ; The places AxPlaceAt knows: a corner of the screen the mouse is on,
    ; beside the pointer, or centred over the main window.
    static AtPlaces := Map("tl", 1, "tr", 1, "bl", 1, "br", 1, "cursor", 1, "main", 1)
    ; The window's Show(), and the placing that has to happen before it is
    ; seen: built hidden, put where it goes, then shown -- so it opens there
    ; rather than opening in the middle and jumping.
    static ShowLines(p, w, gv, pad) {
        nl := "`n"
        pos := AxStart.PosOf(w)
        place := (pos = "mouse") ? pad "AxPlaceMouse(" gv ")" nl
               : AxStart.AtPlaces.Has(pos) ? pad "AxPlaceAt(" gv ", " AxLit.S(pos) ")" nl : ""
        if (w.StartState = "hidden")
            return pad gv ".Show(false)" nl place
        return (place = "") ? pad gv ".Show()" nl : pad gv ".Show(false)" nl place pad gv ".Show()" nl
    }
    ; The lines after a window's Show().
    static After(p, w, gv, pad) {
        nl := "`n", s := ""
        pos := AxStart.PosOf(w)
        if (pos = "remember")
            s .= pad "AxPlaceRestore(" gv ", " AxLit.S(w.Name) ")" nl
               . pad gv ".OnClose((*) => AxPlaceSave(" gv ", " AxLit.S(w.Name) "))" nl
        if (w.StartState = "max")
            s .= pad gv ".Maximize()" nl
        else if (w.StartState = "min")
            s .= pad gv ".Minimize()" nl
        if AxKeyOrder.Explicit(w) {
            names := ""
            for n in AxKeyOrder.Order(p, w)
                names .= (names = "" ? "" : ", ") AxLit.S(n.Name)
            if (names != "")
                s .= pad "AxTabOrder(" gv ", [" names "])" nl
        }
        if (w.DefaultBtn != "" || w.CancelBtn != "")
            s .= pad "AxDefaultKeys(" gv ", " AxLit.S(w.DefaultBtn) ", " AxLit.S(w.CancelBtn) ")" nl
        return s
    }
    ; The functions those lines call, for the ones any window uses.
    static Code(p) {
        place := false, mouse := false, at := false, tabs := false, keys := false
        for w in p.Wins {
            pos := AxStart.PosOf(w)
            place := place || (pos = "remember")
            mouse := mouse || (pos = "mouse")
            at := at || AxStart.AtPlaces.Has(pos)
            tabs := tabs || AxKeyOrder.Explicit(w)
            keys := keys || (w.DefaultBtn != "" || w.CancelBtn != "")
        }
        s := ""
        if place
            s .= AxStart.PlaceFns
        if mouse
            s .= AxStart.MouseFn
        if at
            s .= AxStart.AtFn
        if tabs
            s .= AxStart.TabFn
        if keys
            s .= AxStart.KeysFn
        return s
    }
    static PlaceFns := "
(`
; Where each window was when it last closed -- its place, its size, and whether
; it was maximised -- in a small .ini beside the script. A place on a screen
; that is no longer plugged in is not used.
AxPlaceFile() => RegExReplace(A_ScriptFullPath, "\.[^.\\]*$") ".window.ini"
AxPlaceRestore(g, win) {
    f := AxPlaceFile()
    try {
        x := Integer(IniRead(f, win, "x")), y := Integer(IniRead(f, win, "y"))
        w := Integer(IniRead(f, win, "w")), h := Integer(IniRead(f, win, "h"))
        loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
            if (x + 60 >= l && x + 60 < r && y + 12 >= t && y + 12 < b) {
                WinMove(x, y, w, h, "ahk_id " g.Hwnd)
                break
            }
        }
    }
    try {
        if IniRead(f, win, "max", 0)
            g.Maximize()
    }
}
AxPlaceSave(g, win) {
    f := AxPlaceFile()
    try {
        if DllCall("IsIconic", "Ptr", g.Hwnd)
            return
        max := DllCall("IsZoomed", "Ptr", g.Hwnd)
        if !max {
            WinGetPos(&x, &y, &w, &h, "ahk_id " g.Hwnd)
            IniWrite(x, f, win, "x"), IniWrite(y, f, win, "y")
            IniWrite(w, f, win, "w"), IniWrite(h, f, win, "h")
        }
        IniWrite(max ? 1 : 0, f, win, "max")
    }
}

)"
    static MouseFn := "
(`
; In the middle of the screen the mouse is on.
AxPlaceMouse(g) {
    DetectHiddenWindows(true)          ; it may not be shown yet
    try {
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
            if (mx >= l && mx < r && my >= t && my < b) {
                WinGetPos(, , &w, &h, "ahk_id " g.Hwnd)
                WinMove(l + (r - l - w) // 2, t + (b - t - h) // 2, , , "ahk_id " g.Hwnd)
                break
            }
        }
    }
}

)"
    static AtFn := "
(`
; A corner of the screen the mouse is on (tl tr bl br), beside the mouse
; pointer (cursor), or centred over the main window (main). Called while the
; window is built but not yet shown, so it opens in its place.
AxPlaceAt(win, where) {
    global g
    DetectHiddenWindows(true)          ; it is not shown yet
    try {
        WinGetPos(, , &w, &h, "ahk_id " win.Hwnd)
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        l := 0, t := 0, r := A_ScreenWidth, b := A_ScreenHeight
        loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &l1, &t1, &r1, &b1)
            if (mx >= l1 && mx < r1 && my >= t1 && my < b1) {
                l := l1, t := t1, r := r1, b := b1
                break
            }
        }
        x := l + (r - l - w) // 2, y := t + (b - t - h) // 2, m := 12
        switch where {
        case "tl": x := l + m, y := t + m
        case "tr": x := r - w - m, y := t + m
        case "bl": x := l + m, y := b - h - m
        case "br": x := r - w - m, y := b - h - m
        case "cursor": x := mx + 16, y := my + 16
        case "main":
            if (IsSet(g) && IsObject(g) && g != win && DllCall("IsWindowVisible", "Ptr", g.Hwnd)) {
                WinGetPos(&px, &py, &pw, &ph, "ahk_id " g.Hwnd)
                x := px + (pw - w) // 2, y := py + (ph - h) // 2
            }
        }
        WinMove(Max(l, Min(x, r - w)), Max(t, Min(y, b - h)), , , "ahk_id " win.Hwnd)
    }
}

)"
    static TabFn := "
(`
; Tab visits these first, in this order, and the first has the keyboard when
; the window opens. Anything not named here comes after, as it is laid out.
AxTabOrder(g, names) {
    g.WaitReady()
    first := ""
    for i, n in names {
        try {
            el := g.El(n)
            f := el.querySelector("input, textarea, select, [tabindex]")
            f := IsObject(f) ? f : el
            f.tabIndex := i
            if !IsObject(first)
                first := f
        }
    }
    try first.focus()
}

)"
    static KeysFn := "
(`
; Enter presses the default button and Escape the cancel one. Enter in a box of
; several lines is left to the box.
AxDefaultKeys(g, ok, cancel) {
    g.On("keydown", "*", AxDefaultKey.Bind(g, ok, cancel))
}
AxDefaultKey(g, ok, cancel, el, ev) {
    try {
        k := ev.keyCode
        if (k = 13 && ok != "" && el.tagName != "TEXTAREA" && !ev.ctrlKey) {
            g.El(ok).click()
            ev.returnValue := false
        } else if (k = 27 && cancel != "") {
            g.El(cancel).click()
            ev.returnValue := false
        }
    }
}

)"
}
