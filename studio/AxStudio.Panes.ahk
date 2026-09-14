#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Layout.ahk
#Include %A_LineFile%\..\AxStudio.Map.ahk
#Include %A_LineFile%\..\AxStudio.Icons.ahk
#Include %A_LineFile%\..\AxStudio.Gen.ahk
#Include %A_LineFile%\..\AxStudio.Lint.ahk
#Include %A_LineFile%\..\AxStudio.Acts.ahk
#Include %A_LineFile%\..\AxStudio.Theme.ahk
#Include %A_LineFile%\..\AxStudio.Flow.ahk
#Include %A_LineFile%\..\AxStudio.Bind.ahk
#Include %A_LineFile%\..\AxStudio.Store.ahk
#Include %A_LineFile%\..\AxStudio.Look.ahk
#Include %A_LineFile%\..\AxStudio.Auto.ahk
#Include %A_LineFile%\..\AxStudio.Auto2.ahk
#Include %A_LineFile%\..\AxStudio.Logic.ahk
#Include %A_LineFile%\..\AxStudio.PkgUi.ahk

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
;  AxStudio.Panes.ahk -- toolbox, outline, property sheet, event list and
;  window settings.
;
;  Every editor in the right-hand pane is described once, as
;  {Id, Kind, Get, Set, Each}, and the same list both renders the markup and
;  wires the callbacks. A property cannot end up shown but not saved, and a new
;  property in the catalog needs nothing here.
;
;  `Each` is what makes a multiple selection work: a field that carries one
;  applies to every selected node rather than only the one whose value is on
;  screen. Fields without it (a name, the text of a control) stay single.
;
;  A property edit refreshes the canvas but NOT this pane -- rebuilding the
;  pane under a caret that is still in it would drop every other keystroke.
; =============================================================================
class AxPanes {
    static NONE := "-"                    ; the value a "(default)" choice carries

    ; ================================================================ left
    ; Toolbox or Outline, by the switch at the top of the pane, and whichever
    ; it is has the whole height. Both at once left the Outline a strip at the
    ; bottom, too short to show a real window's tree. The Windows and
    ; Components tabs that used to sit here are the strip of tabs over the
    ; canvas and the App workspace now.
    static LeftTabs(s) {
        tree := (s.LeftTab = "tree")
        c := {N: 0}
        s.P.Walk(s.P.W.Root, AxPanes.CountFn(c))
        n := c.N
        s.Html("axdLeftTabs", '<div class="axd-lseg">'
             . '<span data-ltab="tools"' (tree ? "" : ' class="on"') ' data-tip="What you can add -- drag it onto the canvas">'
             .   '<span class="ico">&#xE710;</span><span class="lbl">Toolbox</span></span>'
             . '<span data-ltab="tree"' (tree ? ' class="on"' : "") ' data-tip="Everything in ' AxTags.E(s.P.W.Name) ', as a tree">'
             .   '<span class="ico">&#xE71D;</span><span class="lbl">Outline</span>'
             .   '<span class="axd-lsegn">' n '</span></span></div>')
        try AxWindow._SetClass(s.El("axdLeft"), "axd-lt-tree", tree)
    }
    static CountFn(c) => (node) => (node.Type != "Root" && node.Type != "Page" ? c.N++ : 0, false)
    static Left(s) {
        AxPanes.LeftTabs(s)
        s.Html("axdLeftBody", AxPanes.Toolbox(s))
        try AxTags.Expand(s.Doc)
        s.Html("axdTreeHead", '<span class="ico">&#xE71D;</span>Outline'
             . '<span class="axd-dim">' AxTags.E(s.P.W.Name) '</span>')
        s.Html("axdTreeBody", AxPanes.Tree(s))
    }

    ; The windows as a board: a card each, with what kind it is, how big, and
    ; -- the part a list of names never showed -- which window opens it and
    ; which it opens. A window nothing opens says so, because nothing will.
    ; A project is one script, so the name of each is also a function in it.
    static WinBoard(s) {
        links := s.P.Links()
        h := '<div class="axd-wboard">'
        for i, w in s.P.Wins {
            opens := "", by := ""
            for l in links {
                if (l.From = w.Name && l.To != w.Name)
                    opens .= AxPanes.WinChip(s, l.To)
                if (l.To = w.Name && l.From != w.Name)
                    by .= AxPanes.WinChip(s, l.From)
            }
            kind := (w.Kind = "main") ? "The main window, built when the script starts"
                  : (w.Kind = "dialog") ? "A dialog: " AxGen.Fn(w) "() waits for it"
                  : (w.Kind = "tool") ? "A tool window: " AxGen.Fn(w) "()"
                  : "A window, on demand: " AxGen.Fn(w) "()"
            n := AxPanes.CountIn(w.Root)
            h .= '<div class="axd-wcard' (i = s.P.Cur ? " on" : "") '" data-win="' i '"'
              .  ' data-tip="Click to pick it, double-click to design it">'
              .  '<div class="axd-wchead"><span class="ico">&#x' AxPanes.WinIcon(w.Kind) ';</span>'
              .  AxTags.E(w.Name) '</div>'
              .  '<div class="axd-wcline">' AxTags.E(kind) '</div>'
              .  '<div class="axd-wcline axd-dim">' w.Width ' x ' w.Height ', '
              .  n ' control' (n = 1 ? "" : "s") '</div>'
            if (by != "")
                h .= '<div class="axd-wcline"><span class="axd-dim">Opened from </span>' by '</div>'
            else if (w.Kind != "main")
                h .= '<div class="axd-wcline axd-lgwarn">Nothing opens it yet</div>'
            if (opens != "")
                h .= '<div class="axd-wcline"><span class="axd-dim">Opens </span>' opens '</div>'
            h .= '<div class="axd-wcacts"><span class="axd-hbtn" data-winact="design.' i '">'
              .  'Design it</span></div></div>'
        }
        h .= '<div class="axd-wcard axd-wcadd">'
          .  '<div class="axd-wchead"><span class="ico">&#xE710;</span>Add one</div>'
          .  '<div class="axd-wcline axd-dim">Another window, a dialog that hands back what it '
          .  'was asked for, or a tool window.</div>'
          .  '<div class="axd-wcacts"><span class="axd-hbtn" data-winact="add.window">Window</span> '
          .  '<span class="axd-hbtn" data-winact="add.dialog">Dialog</span> '
          .  '<span class="axd-hbtn" data-winact="add.tool">Tool</span></div></div></div>'
          .  '<div class="axd-note"><b>' AxTags.E(s.P.W.Name) '</b>:  '
          .  '<span class="axd-hbtn" data-winact="rename">Rename</span> '
          .  '<span class="axd-hbtn" data-winact="dup">Duplicate</span> '
          .  '<span class="axd-hbtn" data-winact="link">Open it from...</span> '
          .  '<span class="axd-hbtn" data-winact="del">Delete</span></div>'
        return h
    }
    ; A window named in a card, as a chip that picks that window.
    static WinChip(s, name) {
        w := s.P.WinByName(name)
        i := IsObject(w) ? s.P.WinIndex(w) : 0
        return '<span class="axd-chip"' (i ? ' data-win="' i '"' : "") '>' AxTags.E(name) '</span>'
    }
    ; A window name is an identifier in the generated script, so it is cleaned
    ; and made unique here rather than being allowed to break the export.
    static SetWinName(s, v) {
        w := s.P.W
        want := AxProject.CleanName(v)
        if (want = "")
            return
        other := s.P.WinByName(want)
        if (IsObject(other) && !AxProject.Same(other, w))
            want := s.P.UniqueWinName(want)
        old := w.Name
        w.Name := want
        if (old != want)
            s.RenameWinRefs(old, want)
    }
    static SetWinKind(s, v) {
        w := s.P.W
        if (v = "main") {
            for x in s.P.Wins
                if (x.Kind = "main")
                    x.Kind := "window"
        } else if (w.Kind = "main" && s.P.Wins.Length > 1) {
            ; something has to start the script
            for x in s.P.Wins
                if !AxProject.Same(x, w) {
                    x.Kind := "main"
                    break
                }
        }
        w.Kind := v
    }
    ; Plain recursion rather than a walk with a callback: a closure made inside
    ; the loop above cannot see the loop variable in AutoHotkey v2.
    static CountIn(node) {
        n := node.Kids.Length
        for k in node.Kids
            n += AxPanes.CountIn(k)
        return n
    }
    ; Every pack, and what is in it. Clicking a control opens the viewer on
    ; the right, which is where the "how do I use this" lives.
    static PackList(s) {
        h := '<div class="axd-note">'
          .  '<span class="axd-hbtn" data-winact="pack.install">Install a component...</span> '
          .  '<span class="axd-hbtn" data-winact="pack.folder">Open the folder</span></div>'
        if !AxComp.Packs.Count
            return h '<div class="axd-empty-pane">No packs found.</div>'
        used := Map()
        for p in AxComp.Used(s.P)
            used[p.Name] := true
        rows := "", rest := "", mine := 0
        for name, p in AxComp.Packs {
            yours := InStr(p.Dir, AxStudioPaths.Lib) != 1
            mine += yours
            ctl := "", first := "", tip := ""
            for t in p.Types {
                if !AxCat.Has(t)
                    continue
                e := AxCat.Get(t)
                first := (first = "") ? t : first
                tip .= (tip = "" ? "" : ", ") e.Label
                ctl .= '<span class="axd-chip" data-showpack="' t '"><span class="ico">&#x' e.Icon
                    .  ';</span>' AxTags.E(e.Label) '</span>'
            }
            ; the ones that matter here get a row; the rest are a chip each
            if (used.Has(name) || yours) {
                what := used.Has(name) ? "used here" : ""
                if yours
                    what .= (what = "" ? "" : ", ") "yours"
                rows .= '<tr><td class="axd-lgname"><span class="ico">&#xE8F1;</span>' AxTags.E(name) '</td>'
                     .  '<td>' (ctl != "" ? ctl : '<span class="axd-dim">code only</span>') '</td>'
                     .  '<td class="axd-narrow"><span class="axd-dim">' what '</span></td></tr>'
            } else
                rest .= '<span class="axd-chip"' (first != "" ? ' data-showpack="' first '"' : "")
                     .  ' data-tip="' AxTags.E(tip != "" ? tip : "code only") '">' AxTags.E(name) '</span>'
        }
        h .= '<div class="axd-lglead" style="margin-left:0">' AxComp.Packs.Count ' packs, '
          .  used.Count ' used by this design' (mine ? ", " mine " of them yours" : "")
          .  '. The export includes only the ones it uses.</div>'
        if (rows != "")
            h .= AxLogic.Table(["Pack", "Controls", ""], rows)
        if (rest != "")
            h .= '<div class="axd-packrest"><span class="axd-dim">Not used here</span> ' rest '</div>'
        return h
    }
    static WinIcon(kind) {
        switch kind {
        case "dialog": return "E8BD"
        case "tool":   return "E90F"
        case "main":   return "E737"
        }
        return "E7C4"
    }
    ; The filter box and the list are drawn separately, so typing in the box
    ; only replaces the list. Redrawing the box under the caret would send it
    ; back to the start of the field on every keystroke.
    static Toolbox(s) {
        return '<div class="axd-search"><ax-search id="axdToolFilter" value="' AxTags.E(s.ToolFilter) '" placeholder="Filter controls"></ax-search></div>'
             . '<div id="axdToolList"' (s.Compact ? ' class="axd-compact"' : "") '>' AxPanes.ToolItems(s) '</div>'
    }
    static ToolItems(s) {
        q := StrLower(Trim(s.ToolFilter))
        h := ""
        hits := 0
        for cat in AxCat.Cats {
            body := ""
            for e in AxCat.InCat(cat) {
                if (q != "" && !InStr(StrLower(e.Label " " e.T " " cat), q))
                    continue
                hits++
                body .= '<div class="axd-tool' (e.Box ? " axd-box-tool" : "") '"'
                     .  ' data-newtype="' e.T '" data-newlabel="' AxTags.E(e.Label) '"'
                     .  ' data-tip="' AxTags.E(e.T (e.Needs != "" ? "  (adds #Include " e.Needs ")" : "")) '">'
                     .  '<span class="ico">&#x' e.Icon ';</span>' AxTags.E(e.Label) '</div>'
            }
            if (body != "")
                h .= '<div class="axd-cat">' AxTags.E(cat) '</div>' body
        }
        if !hits
            h .= '<div class="axd-empty-pane">Nothing matches.</div>'
        return h
    }
    ; The outline shows the whole project, pages included, and every row is a
    ; drag source -- moving a control between pages is only possible here,
    ; because the canvas shows one page at a time.
    static Tree(s) {
        h := ""
        for k in s.P.Root.Kids
            h .= AxPanes.TreeRow(s, k, 0)
        return h != "" ? h : '<div class="axd-empty-pane">Nothing here yet.<br><br>Drag a control from the Toolbox.</div>'
    }
    static TreeRow(s, n, depth) {
        e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
        ico := (n.Type = "Page") ? (n.Prop("icon") != "" ? n.Prop("icon") : "E80F")
             : (IsObject(e) ? e.Icon : "E7C3")
        note := (n.Ev.Length ? "  &#xE943;" : "") (n.Lay("hidden", 0) ? "  &#xED1A;" : "")
        hid := n.Lay("dhide", 0), lock := n.Lay("dlock", 0)
        ; hide it on the canvas, lock it against clicks: the designer's own,
        ; and never in the exported window
        tools := (n.Type = "Page") ? "" : '<span class="axd-trtools">'
               . '<span class="axd-trt' (hid ? " on" : "") '" data-trt="hide|' n.Id '" data-tip="'
               . (hid ? "Show it on the canvas again" : "Hide it on the canvas -- the window still shows it") '">&#x'
               . (hid ? "ED1A" : "E7B3") ';</span>'
               . '<span class="axd-trt' (lock ? " on" : "") '" data-trt="lock|' n.Id '" data-tip="'
               . (lock ? "Unlock it" : "Lock it: clicks on the canvas go to what holds it") '">&#x'
               . (lock ? "E72E" : "E785") ';</span></span>'
        h := '<div class="axd-row' (s.IsSel(n.Id) ? " on" : "") (n.Type = "Page" ? " axd-pagerow" : "")
          .  (hid ? " axd-rowhid" : "") '"'
          .  ' id="tr_' n.Id '"' (n.Type = "Page" ? "" : ' data-dragid="' n.Id '" data-draglabel="' AxTags.E(n.Label) '"')
          .  ' style="padding-left:' (6 + depth * 14) 'px">' tools
          .  '<span class="ico">&#x' ico ';</span>' AxTags.E(n.Label)
          .  '<span class="axd-dim">' AxTags.E(n.Type) note '</span></div>'
        for k in n.Kids
            h .= AxPanes.TreeRow(s, k, depth + 1)
        return h
    }
    static LeftClick(s, ev) {
        src := ev.srcElement
        act := s.UpAttr(src, "data-winact")
        if (act != "")
            return s.WinAction(act)
        wi := s.UpAttr(src, "data-win")
        if (wi != "")
            return s.SwitchWin(Integer(wi))
        sp := s.UpAttr(src, "data-showpack")
        if (sp != "")
            return s.ShowComponent(sp)
        trt := s.UpAttr(src, "data-trt")
        if (trt != "") {
            p := StrSplit(trt, "|")
            n := s.P.Find(p[2])
            if IsObject(n) {
                s.Mark()
                key := (p[1] = "hide") ? "dhide" : "dlock"
                n.L[key] := n.Lay(key, 0) ? 0 : 1
                if (n.L[key] && p[1] = "hide")
                    s.SelIds := []
                s.Refresh()
                s.Status("msg", n.Label (p[1] = "hide" ? (n.L[key] ? " is hidden on the canvas." : " is back on the canvas.")
                                                        : (n.L[key] ? " is locked." : " is unlocked.")))
            }
            return
        }
        ; a click on the toolbox adds at the selection; dragging is the other way
        newType := s.UpAttr(src, "data-newtype")
        if (newType != "")
            return
        id := s.UpId(src, "tr_")
        if (id = "")
            return
        nid := SubStr(id, 4)
        n := s.P.Find(nid)
        if !IsObject(n)
            return
        ow := s.P.WinOf(n)
        if (IsObject(ow) && !AxProject.Same(ow, s.P.W))
            return s.GoToNode(nid)
        add := false
        try add := ev.ctrlKey ? true : false
        pg := s.P.PageOf(n)
        want := IsObject(pg) ? pg.Id : (n.Type = "Page" ? n.Id : "")
        if (want != "" && want != s.PageId) {
            s.PageId := want
            s.SelIds := [nid]
            s.Refresh()
            return
        }
        s.SetSel(nid, add)
    }

    ; =============================================================== right
    static Right(s) {
        ; Checked here because this runs on every change, and the count is
        ; what the Problems tab in the middle wears. The "worth knowing" ones
        ; are still in the list, but a badge that always reads (3) is a badge
        ; you stop looking at.
        s.Issues := AxLint.Run(s.P)
        ; One inspector. It shows the selection -- what it is, then what it
        ; does -- and with nothing selected, the window itself. Properties,
        ; Events and Window were three tabs over this one column, and Logic a
        ; fourth; Logic is a workspace of its own now, with the room it needs.
        if (s.RightTab = "events" || s.RightTab = "logic")
            s.RightTab := "props"
        ; a selection always wins over the window: clicking a control is
        ; asking about that control
        if (s.RightTab = "page" && s.SelNodes().Length)
            s.RightTab := "props"
        s.Html("axdRightTabs", s.RightHead())
        s._fields := []
        if (s.RightTab = "icons")
            html := AxPanes.IconsHtml(s)
        else if (s.RightTab = "pack")
            html := AxPanes.PackHtml(s)
        else if s.SelNodes().Length
            html := AxPanes.PropsHtml(s)
        else
            html := AxPanes.WindowHtml(s)
        s.Html("axdRightBody", html)
        ; the tools and the tabs over it, and the rows sorted A to Z or left
        ; in their groups, the hints marked -- before the tags are expanded
        try s.Html("axdPropTools", AxPanes.ToolsHtml(s))
        try s.Html("axdPropTabs", AxPanes.TabsHtml(s))
        try s.Js("AXP.arrange(" (s.PropSort = "az" ? 1 : 0) ");")
        try AxTags.Expand(s.Doc)
        try s._MakeFocusable()
        AxPanes.Wire(s)
        try s.Js("AXG.mountAll();")
        ; the find box is for properties; the icon picker and the component
        ; viewer have their own search, or none
        try AxWindow._SetClass(s.El("axdRight"), "axd-nofind",
                               s.RightTab = "icons" || s.RightTab = "pack")
        AxPanes.ApplyFind(s)
    }
    ; ---------------------------------------------------- find a property
    static FindKey(s, ev) {
        k := 0
        try k := ev.keyCode
        if (k = 27)
            try s.El("axdPropFind").value := ""
        v := ""
        try v := s.El("axdPropFind").value
        s.PropFind := StrLower(Trim(v))
        AxPanes.ApplyFind(s)
    }
    ; Rows whose label does not say it are hidden, groups left with none are
    ; hidden, and a folded group that matches is opened while it does. A
    ; group's own title matching keeps the whole group.
    static ApplyFind(s) {
        q := s.PropFind
        body := ""
        try body := s.El("axdRightBody")
        if !IsObject(body)
            return
        shown := 0
        grps := body.querySelectorAll(".axd-grp")
        loop grps.length {
            g := grps.item(A_Index - 1)
            title := ""
            try title := StrLower(g.querySelector(".axd-glabel").innerText)
            whole := (q = "" || InStr(title, q))
            any := whole
            rows := g.querySelectorAll(".axd-p")
            loop rows.length {
                r := rows.item(A_Index - 1)
                lbl := ""
                try lbl := StrLower(r.querySelector("label").innerText)
                show := whole || InStr(lbl, q)
                try r.style.display := show ? "" : "none"
                if show
                    any := true
            }
            try g.style.display := any ? "" : "none"
            AxWindow._SetClass(g, "axd-found", q != "" && any)
            shown += any ? 1 : 0
        }
        miss := ""
        try miss := s.El("axdFindNone")
        if IsObject(miss)
            try miss.parentNode.removeChild(miss)
        if (q != "" && !shown)
            try body.insertAdjacentHTML("beforeend", '<div class="axd-empty-pane" id="axdFindNone">'
                . 'Nothing here is called that. Escape clears it.</div>')
        AxPanes.View(s)
    }

    ; ------------------------------------------- the inspector's toolbar
    ; Like any property grid: by category or A to Z; the hints -- the plain
    ; sentences under the rows -- shown or tucked away behind each group's
    ; (i); every group folded or opened at once. And three tabs, so what a
    ; control is, where it sits and what it does are not one long scroll.
    ; A find searches all three.
    static ToolsHtml(s) {
        b := (k, glyph, tip, on) => '<span class="axd-ptool' (on ? " on" : "") '" data-pt="' k '" data-tip="' tip '">'
                                  . '<span class="ico">&#x' glyph ';</span></span>'
        return b("sort.cat", "E8FD", "By category", s.PropSort != "az")
             . b("sort.az", "E8CB", "A to Z", s.PropSort = "az")
             . '<span class="axd-ptsep"></span>'
             . b("hints", "E946", "Hints: what each setting is for", s.PropHints)
             . b("fold", "E70E", "Fold every group", false)
             . b("unfold", "E70D", "Open every group", false)
    }
    static TabsHtml(s) {
        t := (k, label) => '<span class="axd-ptab' (s.PropTab = k ? " on" : "") '" id="axdPt_' k '" data-pt="tab.' k '">'
                         . label '<span class="axd-ptn" id="axdPtn_' k '"></span></span>'
        return t("props", "Properties") t("layout", "Layout") t("events", "Events")
    }
    ; the page script shows the tab, the hints and the counts (AXP.view)
    static View(s) {
        try s.Js("AXP.view('" s.PropTab "', " (s.PropHints ? 1 : 0) ", " (s.PropFind != "" ? 1 : 0) ");")
    }
    static ToolClick(s, ev) {
        v := s.UpAttr(ev.srcElement, "data-pt")
        if (v = "")
            return
        switch v {
        case "sort.cat", "sort.az":
            s.PropSort := SubStr(v, 6)
            return AxPanes.Right(s)                     ; A to Z moves the rows: drawn again
        case "hints":
            s.PropHints := !s.PropHints
        case "fold", "unfold":
            ; the groups of the tab in view, not the ones behind the others
            ; (the one in view: an empty tab falls back to another)
            tab := s.PropTab
            try tab := s.Doc.parentWindow.AXP.tab
            try {
                grps := s.Doc.querySelectorAll("#axdRightBody .axd-grp")
                loop grps.length {
                    g := grps.item(A_Index - 1)
                    if (SubStr(g.id, 1, 4) != "grp_" || AxWindow._Attr(g, "data-tab") != tab)
                        continue
                    key := SubStr(g.id, 5)
                    if (v = "fold")
                        s.Shut[key] := 1
                    else if s.Shut.Has(key)
                        s.Shut.Delete(key)
                    AxWindow._SetClass(g, "shut", v = "fold")
                }
            }
        default:
            if (SubStr(v, 1, 4) = "tab.")
                s.PropTab := SubStr(v, 5)
        }
        try s.Html("axdPropTools", AxPanes.ToolsHtml(s))
        AxPanes.View(s)
    }


    ; Every finding is a row you can click: it switches to the window the
    ; problem is in and selects the control, because a list of complaints you
    ; then have to go and find is a list nobody reads twice.
    static LintHtml(s) {
        list := s.Issues
        blk := AxPanes.RunBlockHtml(s)
        k := list.Length + (blk != "" ? 1 : 0)
        head := '<div class="axd-midhead"><span class="ico">&#xE7BA;</span><span class="axd-midtitle"> Problems</span>'
              . '<span class="axd-midcount">' (k ? k " found" : "nothing to report") '</span>'
              . (blk != "" ? '<span class="axd-hbtn" data-do="run.again">Run it again</span> ' : "")
              . '<span class="axd-hbtn" data-do="lint.recheck">Check again</span></div>'
        head .= blk
        if (!list.Length && blk != "")
            return head
        if !list.Length
            return head '<div class="axd-empty-pane">Nothing to report.<br><br>'
                 . 'Names, handlers, placement, the menus, the files, the arguments and the'
                 . ' modes are all checked every time the design changes.</div>'
        order := ["error", "warn", "info"]
        h := ""
        for sev in order {
            body := ""
            for i, f in list {
                if (f.Sev != sev)
                    continue
                body .= '<div class="axd-lint axd-lint-' sev '" data-lint="' i '">'
                     .  '<span class="ico">&#x' AxPanes.LintIcon(sev) ';</span>'
                     .  '<span class="axd-lintmsg">' AxTags.E(f.Msg) '</span>'
                     .  (f.Hint != "" ? '<div class="axd-linthint">' AxTags.E(f.Hint) '</div>' : "")
                     .  (IsObject(f.Win) && s.P.Wins.Length > 1
                         ? '<div class="axd-linthint">in ' AxTags.E(f.Win.Name) '</div>' : "")
                     .  '</div>'
            }
            if (body != "")
                h .= '<div class="axd-cat">' AxPanes.LintWord(sev) '</div>' body
        }
        return head h
    }
    ; Why the last run did not start, first and apart from the design's own
    ; checks: it is AutoHotkey's answer, not the studio's. A row you click, to
    ; the handler the line is in, or to the whole script when it is in none.
    ; is `fn` a handler the design holds with nothing written in it?
    static EmptyHandler(s, fn) {
        if (fn = "")
            return false
        for w in s.P.Wins
            for n in s.NamedIn(w)
                for e in n.Ev
                    if (AxGen.HandlerName(n, e["name"]) = fn && Trim(e["code"]) = "")
                        return true
        found := false
        for w in s.P.Wins
            s.P.Walk(w.Root, (n) => (n.Name = "" && AxPanes.HasEmpty(n, fn) ? (found := true) : 0, false))
        return found
    }
    static HasEmpty(n, fn) {
        for e in n.Ev
            if (AxGen.HandlerName(n, e["name"]) = fn && Trim(e["code"]) = "")
                return true
        return false
    }
    static RunBlockHtml(s) {
        b := s.RunBlock
        if !IsObject(b)
            return ""
        where := (b.Fn != "") ? "In " AxTags.E(b.Fn) "() -- click to open it."
               : (b.Line > 0) ? "Line " b.Line " of the whole script -- click to see it."
               : "Found when it was checked at " b.When "."
        return '<div class="axd-cat">Will not run</div>'
             . '<div class="axd-lint axd-lint-error axd-runblock"'
             . (b.Fn != "" ? ' data-goto="' AxTags.E(b.Fn) '"' : (b.Line > 0 ? ' data-code="show"' : "")) '>'
             . '<span class="ico">&#x' AxPanes.LintIcon("error") ';</span>'
             . '<span class="axd-lintmsg">' AxTags.E(b.Msg) '</span>'
             . (b.What != "" ? '<div class="axd-linthint axd-runwhat">' AxTags.E(b.What) '</div>' : "")
             . '<div class="axd-linthint">' where ' It clears itself once the script parses again.</div>'
             . '<div class="axd-runacts">'
             . (AxPanes.EmptyHandler(s, b.Fn) ? '<span class="axd-hbtn axd-go" data-do="run.dropempty">Remove the empty ' AxTags.E(b.Fn) '()</span> ' : "")
             . '<span class="axd-hbtn" data-do="run.recheck">Check again</span> '
             . '<span class="axd-hbtn" data-do="run.dismiss">Dismiss</span></div></div>'
    }
    ; What the running preview has said. AxLog() from your own code, the
    ; controls you clicked in it, and any error that went unhandled -- the
    ; three things you would otherwise have put a MsgBox in to find out.
    static OutHtml(s) {
        head := '<div class="axd-midhead"><span class="ico">&#xE756;</span><span class="axd-midtitle"> Output</span>'
              . '<span class="axd-midcount">'
              . (s.PreviewPid ? "running, pid " s.PreviewPid : "not running") '</span>'
              . '<span class="axd-hbtn" data-do="run.again">Run it</span> '
              . '<span class="axd-hbtn" data-do="run.stop">Stop</span> '
              . '<span class="axd-hbtn" data-do="out.clear">Clear</span></div>'
        if !s.Out.Length
            return head '<div class="axd-empty-pane">Nothing yet.<br><br>'
                 . 'Run it (F5) and this fills with whatever the script says: '
                 . 'call <b>AxLog(anything)</b> from a handler, click a control '
                 . 'in the running window to select it here, and any unhandled '
                 . 'error turns up with its file and line -- and clicking it opens '
                 . 'the handler it came from.</div>'
        h := head
        for line in s.Out {
            ; An error knows which function in the generated script threw it,
            ; and therefore which handler in the design wrote that function --
            ; so it is a row you click, not a line you read and then go hunting.
            fn := line.HasOwnProp("Fn") ? line.Fn : ""
            h .= '<div class="axd-out axd-out-' AxTags.E(line.Kind) '"'
              .  (fn != "" ? ' data-goto="' AxTags.E(fn) '"' : "") '>'
              .  '<span class="axd-outkind">' AxTags.E(line.Kind) '</span>'
              .  AxTags.E(line.Text)
              .  (fn != "" ? '<div class="axd-outgo"><span class="ico">&#xE72A;</span> go to ' AxTags.E(fn) '</div>' : "")
              .  '</div>'
        }
        return h
    }
    ; One control, as the library renders it, and every form it comes in.
    static PackHtml(s) {
        t := s.PackShown
        if (t = "" || !AxCat.Has(t))
            return '<div class="axd-empty-pane">Pick a control in the Components list.</div>'
        e := AxCat.Get(t)
        pack := AxComp.Get(e.Pack)
        h := '<div class="axd-head"><span class="axd-hid">' AxTags.E(t) '</span>'
          .  '<span class="ico" style="margin-right:7px">&#x' e.Icon ';</span>'
          .  '<span class="axd-htype">' AxTags.E(e.Label) '</span></div>'
        h .= AxPanes.Group(s, "How it looks",
             '<div class="axd-prev">' AxStore.Preview(s.P, t) '</div>')
        h .= AxPanes.Group(s, "How you write it",
             '<div class="axd-code">' AxTags.E(AxStore.Call(t)) '</div>'
           . '<div class="axd-note">Dragging it in writes exactly this.</div>')
        if IsObject(pack) {
            extra := ""
            for x in AxStore.Extras(pack)
                extra .= '<div class="axd-code">' AxTags.E(x.Sig) '</div>'
                      .  '<div class="axd-note" style="margin-top:-2px">' x.Kind '</div>'
            if (extra != "")
                h .= AxPanes.Group(s, "Also available as", extra)
        }
        if e.Props.Length {
            body := ""
            for p in e.Props
                body .= '<div class="axd-p"><label>' AxTags.E(p.L) '</label>'
                     .  '<div class="axd-static">' AxTags.E(p.Kind) '</div></div>'
            h .= AxPanes.Group(s, "Properties", body)
        }
        if e.Events.Length {
            ev := ""
            for x in e.Events
                ev .= '<span class="axd-hbtn">' AxTags.E(x) '</span> '
            h .= AxPanes.Group(s, "Events", '<div class="axd-align">' ev '</div>')
        }
        if IsObject(pack) {
            info := '<div class="axd-p"><label>Pack</label><div class="axd-static">'
                  . AxTags.E(pack.Name) '</div></div>'
            req := ""
            for x in pack.Requires
                req .= (req = "" ? "" : ", ") x
            if (req != "")
                info .= '<div class="axd-p"><label>Needs</label><div class="axd-static">'
                      . AxTags.E(req) '</div></div>'
            info .= '<div class="axd-note">' AxTags.E(pack.Include) '</div>'
            h .= AxPanes.Group(s, "Where it comes from", info)
        }
        return h
    }
    static LintIcon(sev) => (sev = "error") ? "EA39" : (sev = "warn") ? "E7BA" : "E946"
    static LintWord(sev) => (sev = "error") ? "Will not work" : (sev = "warn") ? "Probably wrong" : "Worth knowing"

    ; The icon browser, which takes over the right-hand pane rather than
    ; opening a window: it is a choice about the thing you are already editing,
    ; and a modal over the top of it would hide what you are choosing for.
    static IconsHtml(s) {
        return '<div class="axd-p"><ax-search id="axdIconFind" value="' AxTags.E(s.IconFind)
             . '" placeholder="Search the glyphs"></ax-search></div>'
             . '<div class="axd-p"><span class="axd-hbtn" data-do="icon.back">Back to the properties</span> '
             . '<span class="axd-hbtn" data-do="icon.none">No icon</span></div>'
             . '<div id="axdIconGrid">' AxIcons.Grid(s.IconFind) '</div>'
    }

    ; ------------------------------------------------------------ editors
    ; One row per property: the label in a fixed column, the editor beside it.
    ; `tall` is the exception -- a textarea, or a field with a row of buttons
    ; under it -- which takes the whole width with its label above.
    static Editor(f) {
        id := f.Id, v := f.Get.Call()
        lbl := '<label for="' id '" title="' AxTags.E(f.L) '">' AxTags.E(f.L) '</label>'
        ; A field with a Desc is a setting that needs saying what it does: its
        ; name and the plain sentence go on the left, the switch on the right,
        ; and neither is cut short by the fixed label column.
        if f.HasOwnProp("Desc") && f.Desc != ""
            lbl := '<div class="axd-pdt"><label for="' id '">' AxTags.E(f.L) '</label>'
                 . '<div class="axd-pdesc">' f.Desc '</div></div>'
        row := (body, tall := false) =>
            '<div class="axd-p' (tall ? " axd-tall" : "") (f.HasOwnProp("Desc") && f.Desc != "" ? " axd-pd" : "")
            . '">' lbl body '</div>'
        switch f.Kind {
        case "text":
            return row('<ax-text id="' id '" value="' AxTags.E(v) '" placeholder="'
                     . AxTags.E(f.HasOwnProp("Hint") ? f.Hint : "") '"></ax-text>')
        case "options":
            ; a list of rows, drawn and edited by AXG in AxStudio.Grid.js; the
            ; text it stands for rides along, hidden, for it to read
            return row('<div class="axd-led" data-field="' id '" data-shape="'
                     . (f.HasOwnProp("Shape") ? f.Shape : "vl") '"></div>'
                     . '<textarea id="' id '" class="axd-ledsrc">' AxTags.E(v) '</textarea>', true)
        case "multiline":
            rows := f.HasOwnProp("Rows") ? f.Rows : 4
            return row('<ax-textarea id="' id '" rows="' rows '">' AxTags.E(v) '</ax-textarea>', true)
        case "num":
            ; a plain box, because blank is a real answer: "no width given" is
            ; not a width of zero, and a spinner cannot say it
            return row('<ax-text id="' id '" value="' AxTags.E(v) '" placeholder="auto"></ax-text>')
        case "int":
            return row('<ax-number id="' id '" value="' (v = "" ? 0 : v) '" min="" max="" step="1"></ax-number>')
        case "flag":
            ; the same row as everything else, so the column of labels does not
            ; break wherever there happens to be a switch
            return row('<ax-switch id="' id '" on="On" off="Off" nolabel' (v ? " checked" : "") '></ax-switch>')
        case "choice":
            if (f.Opts = "@fonts")
                f.Opts := AxTheme.Fonts
            return row('<ax-dropdown id="' id '" options="' AxTags.E(f.Opts) '" value="'
                     . AxTags.E(v = "" ? AxPanes.NONE : v) '"></ax-dropdown>')
        case "icon":
            ; Beside the field, not under it. The glyph itself is the preview,
            ; so there is nothing to read to know whether it worked.
            return row('<ax-text id="' id '" value="' AxTags.E(v) '" placeholder="E713"></ax-text>'
                 . '<span class="axd-pmore">'
                 . '<span class="ico axd-pglyph">&#x' (v != "" ? AxTags.E(v) : "E7C3") ';</span>'
                 . '<span class="axd-hbtn" data-icon="' id '">Choose</span></span>')
        case "color":
            ; The swatch IS the button, and it wears the colour it holds.
            return row('<ax-text id="' id '" value="' AxTags.E(v) '" placeholder="'
                     . AxTags.E((f.HasOwnProp("Hint") && f.Hint != "") ? f.Hint : "#0078d4") '"></ax-text>'
                 . '<span class="axd-pmore"><span class="axd-pswatch' (v = "" ? " none" : "") '"'
                 . (AxPanes.IsColour(v) ? ' style="background:' AxTags.E(v) '"' : "")
                 . ' data-pick="' id '" data-tip="Pick a colour"></span></span>')
        case "static":
            return row('<div class="axd-static">' AxTags.E(v) '</div>')
        }
        return ""
    }

    ; Safe to put in a style attribute: a hex colour, an rgb()/rgba() call, or
    ; a plain colour word. Anything else is left to the text box.
    static IsColour(v) {
        v := Trim(String(v))
        if (v = "")
            return false
        if RegExMatch(v, "^#[0-9A-Fa-f]{3,8}$")
            return true
        if RegExMatch(v, "i)^rgba?\([0-9., ]+\)$")
            return true
        return RegExMatch(v, "^[A-Za-z]{3,20}$") ? true : false
    }

    ; Which of the inspector's tabs a group is on: what it is, where it sits,
    ; what it does. Anything not named here is a property.
    static Tabs := Map("layout", "layout", "lineup", "layout", "wsize", "layout", "wpages", "layout",
        "layoutfromthescript", "layout", "wtab", "layout",
        "events", "events", "wstart", "events", "wkeys", "events", "wcode", "events")
    static TabOf(key) => AxPanes.Tabs.Has(key) ? AxPanes.Tabs[key] : "props"

    ; A group remembers whether it is open, because a property sheet with
    ; nine sections is a scroll bar unless you can put the ones you are not
    ; using away.
    static Group(s, title, body, key := "") {
        if (body = "")
            return ""
        ; The key is what remembers whether the group is folded away, so a
        ; title carrying a count -- "Values (3)" -- has to say what its key is.
        ; Deriving it from the title would give the group a new identity every
        ; time the count changed, and unfold it under you.
        if (key = "")
            key := RegExReplace(StrLower(title), "[^a-z0-9]")
        shut := (s.Shut is Map) && s.Shut.Has(key)
        return '<div class="axd-grp' (shut ? " shut" : "") '" id="grp_' key '" data-tab="' AxPanes.TabOf(key) '">'
             . '<span class="axd-glabel" data-grp="' key '">' AxTags.E(title) '</span>'
             . '<div class="axd-gbody">' body '</div></div>'
    }

    ; --------------------------------------------------------- properties
    static PropsHtml(s) {
        nodes := s.SelNodes()
        if !nodes.Length
            return '<div class="axd-empty-pane">Nothing selected.<br><br>Click a control on the canvas, drag one in from the Toolbox, or pick one in the Outline.</div>'
        n := nodes[nodes.Length]
        f := s._fields
        add := (d) => (f.Push(d), AxPanes.Editor(d))
        h := ""
        if (nodes.Length > 1)
            h .= '<div class="axd-multi">' nodes.Length ' controls selected. Layout and shared properties apply to all of them.</div>'
               . AxPanes.Group(s, "Line them up", AxPanes.AlignBar(s), "lineup")

        if (n.Type = "Page") {
            body := add({Id: "p_title", L: "Page title", Kind: "text", Get: (*) => n.Prop("title"),
                         Set: (v) => n.P["title"] := v})
                 .  add({Id: "p_icon", L: "Nav icon", Kind: "icon", Get: (*) => n.Prop("icon"),
                         Set: (v) => n.P["icon"] := v})
                 .  add({Id: "p_name", L: "Page id", Kind: "text", Get: (*) => n.Name,
                         Set: (v) => AxPanes.SetName(s, n, v)})
            h .= AxPanes.Group(s, "Page", body)
            acts := AxPanes.Actions(n)
            return (acts != "") ? h AxPanes.Group(s, "Actions", acts) : h
        }
        e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
        h .= '<div class="axd-head"><span class="axd-hid">' AxTags.E(n.Id) '</span>'
          .  '<span class="ico" style="margin-right:7px">&#x' (IsObject(e) ? e.Icon : "E7C3") ';</span>'
          .  '<span class="axd-htype">' AxTags.E(IsObject(e) ? e.Label : n.Type) '</span></div>'
        h .= AxPanes.Group(s, "Name", add({Id: "p_name", L: "Name",
                     Kind: "text", Get: (*) => n.Name, Set: (v) => AxPanes.SetName(s, n, v)}))

        if (IsObject(e) && IsObject(e.Arg)) {
            ; a list's label loses its "(value:Label per line)": the rows say it
            lbl := (e.Arg.Kind = "options") ? RegExReplace(e.Arg.L, "\s*\(.*\)\s*$") : e.Arg.L
            body := add({Id: "p_arg", L: lbl, Kind: e.Arg.Kind, Shape: AxPanes.ListShape(n.Type),
                         Rows: (n.Type = "DataView") ? 3 : (n.Type = "Code") ? 12 : (n.Type = "ListView" || n.Type = "TreeView") ? 7 : 4,
                         Get: (*) => n.Arg, Set: (v) => n.Arg := v})
            ; the table editor is the way in; the same data as text is there
            ; for whoever wants it, one click away rather than always open
            raw := s.HasOwnProp("RawOpen") && s.RawOpen
            if (n.Type = "DataView" || n.Type = "ListView")
                body := '<div class="axd-gridsum" data-field="p_arg"' (n.Type = "ListView" ? ' data-lv="1"' : "") '><span class="ico">&#xE80A;</span>'
                      . '<span class="axd-gridsay"></span>'
                      . '<span class="axd-hbtn axd-rawt' (raw ? " on" : "") '" data-rawt="1" data-tip="The same data, as text">As text</span>'
                      . '<span class="axd-hbtn axd-go" data-do="grid.open">Edit the data...</span></div>'
                      . '<div class="axd-rawbox' (raw ? " on" : "") '">' body '</div>'
            if (e.Arg.HasOwnProp("Raw") && e.Arg.Raw)
                body .= '<div class="axd-note">Written into the script exactly as typed, as code: text needs its own quotes '
                     . '("like this"), and a value of the program can be named as it is.</div>'
            if (n.Type = "Code")
                body .= '<div class="axd-note">AutoHotkey that runs at this point while the window is built, so anything it adds lands here, between the controls around it.</div>'
            h .= AxPanes.Group(s, "Content", body)
        }

        if (n.Type = "Radio" && nodes.Length = 1)
            h .= AxPanes.Group(s, "Group", AxPanes.RadioGroup(s, n, add), "rgroup")
        if (nodes.Length = 1 && AxActs.Holds(n.Type) != "")
            h .= AxPanes.Group(s, "Bound to a value", AxPanes.BindGroup(s, n, add), "bindto")
        acts := AxPanes.Actions(n)
        if (acts != "")
            h .= AxPanes.Group(s, "Actions", acts)
        ; What it does, right under what it is. Events were a tab of their own,
        ; a click away from the control they belong to.
        if (nodes.Length = 1 && IsObject(e))
            h .= AxPanes.Group(s, "Events", AxPanes.EventsHtml(s), "events")

        place := n.Lay("place", "flow")
        ; where it sits and how wide, said against the box it is in -- the
        ; page, a card, a group -- rather than as numbers
        box := IsObject(n.Parent) && n.Parent.Type != "Root" && n.Parent.Type != "Page"
            ? (n.Parent.Name != "" ? n.Parent.Name : StrLower(AxCat.Has(n.Parent.Type) ? AxCat.Get(n.Parent.Type).Label : n.Parent.Type)) : "the page"
        lay := add({Id: "p_place", L: "Sits", Kind: "choice",
                    Opts: "flow:Under the one before|same:Beside the one before|dock:Pinned to an edge of " box "|abs:At a fixed spot in " box,
                    Get: (*) => place, Set: (v) => "",
                    Each: (nn, v) => AxPanes.PlaceOne(nn, v), Rebuild: true})
        if (place = "flow" || place = "same")
            lay .= add({Id: "p_wrel", L: "Width", Kind: "choice", Rebuild: true,
                        Opts: "auto:As wide as it needs|line:The rest of the line|half:Half of " box "|third:A third of " box
                            . "|quarter:A quarter of " box "|twothirds:Two thirds of " box "|px:Exactly, in pixels",
                        Get: (*) => AxPanes.WRelOf(n), Set: (v) => "", Each: (nn, v) => AxPanes.WRel(nn, v)})
        if (n.Box && n.Kids.Length > 1)
            lay .= '<div class="axd-note"><span class="axd-hbtn axd-go" data-do="arrange">Arrange what is inside...</span> '
                 . 'one under another, side by side, or a grid -- all ' n.Kids.Length ' at once.</div>'
        if (place = "abs") {
            lay .= add({Id: "p_x", L: "X", Kind: "int", Get: (*) => n.Lay("x", 0),
                        Set: (v) => n.L["x"] := v, Each: (nn, v) => nn.L["x"] := v})
                .  add({Id: "p_y", L: "Y", Kind: "int", Get: (*) => n.Lay("y", 0),
                        Set: (v) => n.L["y"] := v, Each: (nn, v) => nn.L["y"] := v})
        } else if (place = "dock") {
            lay .= add({Id: "p_dock", L: "Docked to", Kind: "choice",
                        Opts: "top:Top|bottom:Bottom|left:Left|right:Right|fill:Fill the page",
                        Get: (*) => n.Lay("dock", "bottom"), Set: (v) => "",
                        Each: (nn, v) => nn.L["dock"] := v, Rebuild: true})
                .  add({Id: "p_docksize", L: "Thickness", Kind: "num",
                        Get: (*) => n.Lay("docksize", ""), Set: (v) => n.L["docksize"] := v,
                        Each: (nn, v) => nn.L["docksize"] := v})
                .  '<div class="axd-note">A docked control is positioned against the page, so it stays put while the rest scrolls. That is how a footer sticks to the bottom.</div>'
        } else if (place = "same")
            lay .= add({Id: "p_gap", L: "Gap before", Kind: "int",
                        Get: (*) => n.Lay("gap", 8), Set: (v) => n.L["gap"] := v, Each: (nn, v) => nn.L["gap"] := v})
        lay .= add({Id: "p_w", L: "Width (px)", Kind: "num", Get: (*) => n.Lay("w", ""),
                    Set: (v) => n.L["w"] := v, Each: (nn, v) => nn.L["w"] := v})
            .  add({Id: "p_h", L: "Height (px)", Kind: "num", Get: (*) => n.Lay("h", ""),
                    Set: (v) => n.L["h"] := v, Each: (nn, v) => nn.L["h"] := v})
            .  add({Id: "p_top", L: "Extra top margin", Kind: "num", Get: (*) => n.Lay("top", ""),
                    Set: (v) => n.L["top"] := v, Each: (nn, v) => nn.L["top"] := v})
            .  add({Id: "p_mb", L: "Extra bottom margin", Kind: "num", Get: (*) => n.Lay("mb", ""),
                    Set: (v) => n.L["mb"] := v, Each: (nn, v) => nn.L["mb"] := v})
            .  (place = "same" ? "" : add({Id: "p_ml", L: "Extra left margin", Kind: "num", Get: (*) => n.Lay("ml", ""),
                    Set: (v) => n.L["ml"] := v, Each: (nn, v) => nn.L["ml"] := v}))
            .  add({Id: "p_mr", L: "Extra right margin", Kind: "num", Get: (*) => n.Lay("mr", ""),
                    Set: (v) => n.L["mr"] := v, Each: (nn, v) => nn.L["mr"] := v})
            .  add({Id: "p_fill", L: "Fill the line", Kind: "flag", Get: (*) => n.Lay("fill", 0),
                    Set: (v) => n.L["fill"] := v, Each: (nn, v) => nn.L["fill"] := v})
            .  (place = "flow" || place = "same"
                ? add({Id: "p_grow", L: "Fill the height", Kind: "flag", Get: (*) => n.Lay("grow", 0),
                       Set: (v) => n.L["grow"] := v, Each: (nn, v) => nn.L["grow"] := v, Rebuild: true})
                . (n.Lay("grow", 0) ? '<div class="axd-note">It takes the height its page or box has left, and follows the window as it is resized. Height is the least it is given; below that the page scrolls. Several on one line grow together, and lines that grow share what is left.</div>' : "")
                : "")
            .  add({Id: "p_hidden", L: "Hidden at start", Kind: "flag", Get: (*) => n.Lay("hidden", 0),
                    Set: (v) => n.L["hidden"] := v, Each: (nn, v) => nn.L["hidden"] := v})
        ; something that holds other things can scroll what does not fit in it
        if n.Box
            lay .= add({Id: "p_scroll", L: "Scrolls", Kind: "choice",
                        Opts: AxPanes.NONE ":No -- it grows to fit|y:Up and down|x:Sideways|both:Both ways",
                        Get: (*) => (n.Lay("scroll", "") = "" ? AxPanes.NONE : n.Lay("scroll")),
                        Set: (v) => n.L["scroll"] := v, Each: (nn, v) => nn.L["scroll"] := v})
                .  ((n.Lay("scroll", "") != "" && n.Lay("h", "") = "" && n.Lay("place", "flow") != "dock")
                    ? '<div class="axd-note">Give it a height, or it grows to fit and never needs to scroll.</div>' : "")
        if (IsObject(n.Parent) && n.Parent.Type = "Tab")
            lay .= add({Id: "p_tab", L: "Tab panel", Kind: "int", Get: (*) => AxGen.TabOf(n),
                        Set: (v) => n.L["tab"] := v, Each: (nn, v) => nn.L["tab"] := v})
        h .= AxPanes.Group(s, "Layout", lay)

        if IsObject(e) {
            body := ""
            for pr in e.Props
                if !(n.Type = "Radio" && pr.K = "group")
                body .= add({Id: "p_c_" pr.K, L: pr.L, Kind: pr.Kind, Opts: AxPanes.ChoiceOpts(pr),
                             Get: AxPanes.PropGet(n, pr.K), Set: AxPanes.PropSet(n, pr.K),
                             Each: AxPanes.PropEach(pr.K), SameType: n.Type})
            if (body != "")
                h .= AxPanes.Group(s, e.Label, body)
        }

        pop := add({Id: "p_pop", L: "What pops up (HTML)", Kind: "multiline", Rows: 4,
                    Get: (*) => n.Lay("pop", ""), Set: (v) => n.L["pop"] := v})
        if (Trim(n.Lay("pop", "")) != "") {
            pop .= add({Id: "p_popon", L: "Opens on", Kind: "choice", Opts: "click:Click|hover:Hover|none:Only when you ask",
                        Get: (*) => n.Lay("popon", "click"), Set: (v) => n.L["popon"] := v})
                .  add({Id: "p_popalign", L: "Aligned", Kind: "choice", Opts: "left:Left|center:Centre|right:Right",
                        Get: (*) => n.Lay("popalign", "left"), Set: (v) => n.L["popalign"] := v})
                .  add({Id: "p_popw", L: "Width", Kind: "num", Get: (*) => n.Lay("popw", ""),
                        Set: (v) => n.L["popw"] := v})
        }
        pop := '<div class="axd-align"><span class="axd-hbtn" data-do="pop.shape">Start from a shape...</span></div>' pop
        ; Everything inside with an id, found in the markup as you write it:
        ; each can have its own click handler, written and wired like any event.
        parts := AxCat.PopParts(n.Lay("pop", ""))
        if parts.Length {
            cards := "", free := ""
            for id in parts {
                name := "Pop_" id, idx := 0
                for i, ev in n.Ev
                    if (ev["name"] = name)
                        idx := i
                if !idx {
                    free .= '<span class="axd-chip" data-ev="' AxTags.E(name) '" data-act="add"'
                         .  ' data-tip="' AxTags.E("Write " AxGen.HandlerName(n, name) "(el, ev) -- it runs when " id " is clicked") '">'
                         .  '+ Click on ' AxTags.E(id) '</span> '
                    continue
                }
                code := Trim(n.Ev[idx]["code"])
                cards .= '<div class="axd-ev on">'
                      .  '<span class="axd-evgo" data-ev="' AxTags.E(name) '" data-act="del">Remove</span>'
                      .  '<span class="axd-evgo" data-ev="' AxTags.E(name) '" data-act="code" data-tip="Open it as code">Code</span>'
                      .  '<span class="axd-evgo" data-ev="' AxTags.E(name) '" data-act="steps" data-tip="Open it as steps: a flowchart, no code">Steps</span>'
                      .  '<div class="axd-evname">Click on ' AxTags.E(id) '</div>'
                      .  '<div class="axd-evsig">' AxTags.E(AxGen.HandlerName(n, name) "(el, ev)") '</div>'
                      .  (code != "" ? '<div class="axd-evsig">' AxTags.E(AxPanes.Peek(code)) '</div>' : "")
                      .  '</div>'
            }
            pop .= '<div class="axd-note" style="margin-top:8px"><b>Inside it</b> -- what can be clicked, found by its id:</div>'
                 . cards (free != "" ? '<div class="axd-align">' free '</div>' : "")
        }
        pop .= '<div class="axd-note">A small panel that opens from this control -- a menu, a tip, a little form. It is written in HTML; '
             . '<b>Start from a shape</b> writes one for you. Anything in it with an id can have a click of its own, listed above. '
             . 'From code, g.ClosePopover() puts it away.</div>'
        h .= AxPanes.Group(s, "Pop-up panel", pop, "popover")

        style := add({Id: "p_tip", L: "Tooltip", Kind: "text", Get: (*) => n.Lay("tip", ""), Hint: "shown when the mouse rests on it",
                      Set: (v) => n.L["tip"] := v, Each: (nn, v) => nn.L["tip"] := v})
              .  add({Id: "p_class", L: "Style classes", Kind: "text", Get: (*) => n.Lay("class", ""), Hint: "CSS class names",
                      Set: (v) => n.L["class"] := v, Each: (nn, v) => nn.L["class"] := v})
              .  add({Id: "p_style", L: "Its own CSS", Kind: "text", Get: (*) => n.Lay("style", ""), Hint: "color: red; font-size: 14px",
                      Set: (v) => n.L["style"] := v, Each: (nn, v) => nn.L["style"] := v})
              .  add({Id: "p_opts", L: "More options", Kind: "text", Get: (*) => n.Lay("opts", ""), Hint: "as in code: Disabled w200",
                      Set: (v) => n.L["opts"] := v, Each: (nn, v) => nn.L["opts"] := v})
              .  '<div class="axd-note">For the rest of the look -- colours, corners, type -- for every control at once, '
              .  'use the <a class="axd-link" data-do="go.look">Look tab</a>. <b>More options</b> are AxGui&#39;s own, written '
              .  'as a script would write them, for the few this pane has no box for.</div>'
        h .= AxPanes.Group(s, "Tooltip and style", style, "style")
        return h
    }
    ; Lining several up: what to line them up with, then what to do. Point at
    ; a button and the canvas shows where each would go, which stays put and
    ; which cannot move; the plan shown is the plan carried out (AXD.alPlan).
    static AlignBar(s) {
        b := (k, t, tip) => '<span class="axd-albtn" data-align="' k '" data-tip="' tip '">' t '</span>'
        a := (v, t) => '<span class="axd-albtn' (s.AlAnchor = v ? " on" : "") '" data-alanchor="' v '">' t '</span>'
        last := s.Primary()
        return '<div class="axd-alrow"><span class="axd-allab">With</span><span class="axd-alseg">'
             . a("each", "Each other") a("last", "The last picked") a("page", "The page") '</span></div>'
             . '<div class="axd-alrow"><span class="axd-allab">Across</span><span class="axd-alseg">'
             . b("left", "Left", "Left edges in line") b("hcenter", "Centre", "Centres in line")
             . b("right", "Right", "Right edges in line") '</span></div>'
             . '<div class="axd-alrow"><span class="axd-allab">Down</span><span class="axd-alseg">'
             . b("top", "Top", "Tops in line") b("vcenter", "Middle", "Middles in line")
             . b("bottom", "Bottom", "Bottoms in line") '</span></div>'
             . '<div class="axd-alrow"><span class="axd-allab">Spacing</span><span class="axd-alseg">'
             . b("distx", "Even across", "The same space between each, the two ends kept where they are")
             . b("disty", "Even down", "The same space between each, top and bottom kept") '</span></div>'
             . '<div class="axd-alrow"><span class="axd-allab">Gap</span>'
             . '<input id="axdAlGap" class="axd-algap" value="8" autocomplete="off"> px '
             . '<span class="axd-alseg">' b("gapx", "Across", "Exactly this gap between each, from the first")
             . b("gapy", "Down", "Exactly this gap between each, from the top one") '</span></div>'
             . '<div class="axd-alrow"><span class="axd-allab">Size</span><span class="axd-alseg">'
             . b("samew", "Same width", "As wide as the last one picked")
             . b("sameh", "Same height", "As tall as the last one picked") '</span></div>'
             . '<div class="axd-note">Point at a button: the canvas shows where each goes, what <b>stays</b> '
             . '(with "The last picked" that is <b>' AxTags.E(IsObject(last) ? last.Label : "") '</b>), and '
             . 'what is <b>in the flow</b> -- a control in the flow cannot be moved sideways, but spacing '
             . 'changes the room before it.</div>'
    }
    ; What this particular control can be asked for, right where you are
    ; looking at it. A tab strip wants another tab far more often than it wants
    ; a CSS class, and hunting through a menu for that is the difference
    ; between a designer and a form.
    ; Which actions a control offers is AxActs's business -- see the header of
    ; AxStudio.Acts.ahk. This only draws them.
    static Actions(n) {
        h := ""
        for a in AxActs.For(n)
            h .= '<span class="axd-hbtn" data-do="' a.Id '">' AxTags.E(a.L) '</span> '
        return h != "" ? '<div class="axd-align">' h "</div>" : ""
    }
    ; Which radio groups pick together: those whose group (or, without one,
    ; whose name) is the same share the HTML name, so picking in one unpicks
    ; the rest -- options spread over rows and cards, and still one answer.
    static RadioGroup(s, n, add) {
        own := Trim(n.Prop("group", "")) != "" ? Trim(n.Prop("group")) : n.Name
        mates := []
        s.P.Walk(s.P.W.Root, AxPanes.RadioMateFn(n, own, mates))
        chips := ""
        for m in mates
            chips .= '<span class="axd-chip" data-logic="ctl|' AxTags.E(m.Name) '"><span class="ico">&#x'
                  .  AxCat.Get("Radio").Icon ';</span>' AxTags.E(m.Name) '</span> '
        return add({Id: "p_rgroup", L: "Group", Kind: "text", Hint: n.Name " -- a group of its own",
                    Get: (*) => n.Prop("group", ""), Set: (v) => n.P["group"] := Trim(v), Rebuild: true})
             . '<div class="axd-note">' (mates.Length
                 ? "Picked together with: " chips "<br>Picking an option in any of them unpicks the rest. "
                 . "Each still has its own value: the pick if it is in that one, blank if not."
                 : "A group of its own: its options pick against each other. Give another radio group "
                 . "the same group name and their options become one choice.") '</div>'
             . '<div class="axd-align"><span class="axd-hbtn" data-do="rg.more">Add another part to this group</span> '
             . (Trim(n.Prop("group", "")) != "" ? '<span class="axd-hbtn" data-do="rg.leave">Take it out of the group</span>' : "")
             . '</div>'
    }
    static RadioMateFn(n, own, mates) => (m) => ((m.Type = "Radio" && m.Id != n.Id
        && (Trim(m.Prop("group", "")) != "" ? Trim(m.Prop("group")) : m.Name) = own) ? mates.Push(m) : 0, false)
    ; What a line of a list property holds, for the list editor.
    ; ------------------------------------------------------------ binding
    ; Which value this control is kept in step with, picked right where the
    ; control is: an existing value, or a new one named after the control and
    ; started at what it shows now.
    static BindGroup(s, n, add) {
        if (Trim(n.Name) = "")
            return '<div class="axd-note">Give it a name, and it can be bound to a value.</div>'
        cur := AxPanes.BindOf(s, n)
        holds := AxActs.Holds(n.Type)
        opts := AxPanes.NONE ":Not bound"
        for v in AxBind.Vars(s.P)
            opts .= "|" v.Name ":" v.Name (v.HasOwnProp("Setting") ? "  (a setting)" : "")
        opts .= "|+new:A new value, " AxPanes.NewVarFor(s, n)
        h := add({Id: "p_bind", L: "Value", Kind: "choice", Opts: opts, Rebuild: true,
                  Get: (*) => IsObject(cur) ? cur.Var : AxPanes.NONE, Set: (v) => AxPanes.SetBind(s, n, v)})
        two := !AxActs.Shows(n.Type) && AxBind.PullEvent(s.P, {Ctl: n.Name, Prop: "", Var: "", Both: true}) != ""
        if (IsObject(cur) && two)
            h .= add({Id: "p_bindway", L: "Direction", Kind: "choice", Rebuild: true,
                      Opts: "two:Both ways -- either changes the other|one:It only shows the value",
                      Get: (*) => cur.Both ? "two" : "one", Set: (v) => AxPanes.SetBind(s, n, cur.Var, v)})
        say := IsObject(cur)
            ? "Kept in step with <b>" AxTags.E(cur.Var) "</b>" (cur.Both ? ": change either and the other follows." : ": it shows the value, and changes when it does.")
            : "It holds " AxTags.E(holds) ". Bound to a value, the two stay the same with no code."
        return h '<div class="axd-note">' say ' <span class="axd-hbtn" data-do="bind.see">All the bindings</span></div>'
    }
    static BindOf(s, n) {
        for b in AxBind.Binds(s.P.W)
            if (b.Ctl = n.Name)
                return b
        return ""
    }
    ; a value name for this control that nothing else has
    static NewVarFor(s, n) {
        ; a label-like text says what it is ("Your name" -> yourName); a
        ; control holding data says what kind ("200,800" -> range)
        static kind := Map("Date", "date", "Calendar", "day", "RangeSlider", "range", "Tags", "tags",
            "Number", "number", "Slider", "level", "Rating", "rating", "ColorButton", "colour", "ColorPicker", "colour",
            "Palette", "colour", "Hotkey", "hotkey", "DDL", "choice", "ListBox", "choice", "Radio", "choice",
            "Segmented", "choice", "CheckBox", "isOn", "Switch", "isOn", "Stepper", "step", "Breadcrumb", "place",
            "Progress", "progress", "Gauge", "level", "Stat", "stat", "Avatar", "person")
        a := Trim(String(n.Arg))
        if (RegExMatch(a, "^[A-Za-z][A-Za-z '-]{1,23}$") && !RegExMatch(n.Type, "i)^(Date|Calendar|Tags|Stat|Avatar)$"))
            base := AxWiz.VarFor(s, n.Name)
        else
            base := kind.Has(n.Type) ? kind[n.Type] : n.Name "Value"
        if (StrLower(base) = StrLower(n.Name))
            base .= "Value"
        name := base, i := 2
        while (AxBind.HasVar(s.P, name) || IsObject(s.P.FindByName(name)))
            name := base i, i++
        return name
    }
    ; bind n to `v` ("" unbinds it, "+new" makes the value first), both ways
    ; when it can change and way does not say otherwise
    static SetBind(s, n, v, way := "") {
        W := s.P.W
        keep := "", had := ""
        for line in StrSplit(StrReplace(String(W.Binds), "`r", ""), "`n") {
            t := Trim(line)
            if (t = "")
                continue
            if (RegExMatch(t, "^([A-Za-z_]\w*)(?:\.\w+)?\s*(<->|<-)", &m) && m[1] = n.Name) {
                had := m[2]
                continue
            }
            keep .= (keep = "" ? "" : "`n") t
        }
        name := v
        if (v = "+new") {
            name := AxPanes.NewVarFor(s, n)
            cur := RTrim(String(s.P.Vars), " `t`r`n")
            s.P.Vars := (cur = "" ? "" : cur "`n") name " = " AxBind.SeedFor(n)
        }
        if (name != "") {
            two := !AxActs.Shows(n.Type) && AxBind.PullEvent(s.P, {Ctl: n.Name, Prop: "", Var: "", Both: true}) != ""
            arrow := (way = "one" || !two) ? "<-" : (way = "two") ? "<->" : (had = "<-") ? "<-" : "<->"
            keep .= (keep = "" ? "" : "`n") n.Name " " arrow " " name
        }
        W.Binds := keep
        s.QueueLive()
        s.Status("msg", name = "" ? n.Name " is not bound any more." : n.Name " is bound to " name ".")
    }
    ; one click: a new value for each named control that holds one and is not bound
    static Unbound(s) {
        out := []
        for n in s.NamedIn(s.P.W)
            if (AxActs.Holds(n.Type) != "" && !AxActs.Shows(n.Type) && !IsObject(AxPanes.BindOf(s, n)))
                out.Push(n)
        return out
    }
    static QuickBind(s, name) {
        n := s.P.FindByName(name)
        if !IsObject(n)
            return
        s.Mark()
        AxPanes.SetBind(s, n, "+new")
        s.Refresh()
    }
    static BindAll(s) {
        list := AxPanes.Unbound(s)
        if !list.Length
            return
        s.Mark()
        for n in list
            AxPanes.SetBind(s, n, "+new")
        s.Refresh()
        s.Status("msg", list.Length " controls bound, each to a new value named after it.")
    }
    static ListShape(type) {
        static m := Map("Segmented", "vlg", "Tab", "lg", "Palette", "c", "Breadcrumb", "vlg", "Stepper", "ld")
        return m.Has(type) ? m[type] : "vl"
    }
    static HasOptions(n) {
        e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
        return IsObject(e) && IsObject(e.Arg) && e.Arg.Kind = "options"
    }
    static PropGet(n, key) => (*) => n.Prop(key, "")
    static PropSet(n, key) => (v) => n.P[key] := v
    static PropEach(key) => (nn, v) => nn.P[key] := v
    static ChoiceOpts(pr) {
        if (pr.Kind != "choice")
            return ""
        out := ""
        for part in StrSplit(pr.Opts, "|") {
            v := Trim(part)
            out .= (out = "" ? "" : "|") (v = "" ? AxPanes.NONE ":(default)" : v ":" v)
        }
        return out
    }
    ; A width against the box: the whole rest of the line is Fill; a share is
    ; a width in % of the box, kept in the control's own CSS where AxGui
    ; already takes it; exactly is the pixel box below.
    static Shares := Map("half", 50, "third", 33.33, "quarter", 25, "twothirds", 66.66)
    static WRelOf(n) {
        if n.Lay("fill", 0)
            return "line"
        if RegExMatch(n.Lay("style", ""), "i)(?:^|;)\s*width\s*:\s*([\d.]+)%", &m)
            for k, v in AxPanes.Shares
                if (Abs(v - m[1]) < 1)
                    return k
        return (n.Lay("w", "") != "") ? "px" : "auto"
    }
    static WRel(n, v) {
        st := Trim(RegExReplace(n.Lay("style", ""), "i)(?:^|;)\s*width\s*:\s*[\d.]+%\s*;?", ";"), "; ")
        n.L["fill"] := (v = "line") ? 1 : 0
        if AxPanes.Shares.Has(v)
            st := "width:" AxPanes.Shares[v] "%" (st != "" ? ";" st : "")
        if (v != "px")
            n.L["w"] := ""
        else if (n.Lay("w", "") = "")
            n.L["w"] := 200
        n.L["style"] := st
    }
    static PlaceOne(n, v) {
        n.L["place"] := v
        if (v = "abs" && n.Lay("x", "") = "")
            n.L["x"] := 24, n.L["y"] := 24
        if (v = "dock" && n.Lay("dock", "") = "")
            n.L["dock"] := "bottom"
        if (v != "abs") {
            ; Map.Delete raises when the key is not there, and a control that
            ; has never been placed by hand has neither of these
            if n.L.Has("x")
                n.L.Delete("x")
            if n.L.Has("y")
                n.L.Delete("y")
        }
    }
    static SetName(s, n, v) {
        v := AxProject.CleanName(v)
        if (v = "")
            return
        if s.P.FindByName(v, n)
            v := s.P.NewName(RegExReplace(v, "\d+$"))
        n.Name := v
    }

    ; ------------------------------------------------------------- events
    static EventsHtml(s) {
        n := s.Primary()
        if !IsObject(n) || !AxCat.Has(n.Type)
            return '<div class="axd-empty-pane">Select a control to see the events it can raise.</div>'
        e := AxCat.Get(n.Type)
        ; The handled ones as cards, with a peek at their code. The rest are
        ; one row of chips: a card each for events nobody has written was
        ; most of a pane saying "Add".
        h := "", free := ""
        for name in e.Events {
            idx := 0
            for i, ev in n.Ev
                if (ev["name"] = name)
                    idx := i
            if !idx {
                free .= '<span class="axd-chip" data-ev="' name '" data-act="add"'
                     .  ' data-tip="' AxTags.E("Write " AxGen.HandlerName(n, name) "(" AxCat.Sig(name) ")") '">'
                     .  '+ ' AxTags.E(name) '</span>'
                continue
            }
            code := Trim(n.Ev[idx]["code"])
            h .= '<div class="axd-ev on">'
              .  '<span class="axd-evgo" data-ev="' name '" data-act="del">Remove</span>'
              .  '<span class="axd-evgo" data-ev="' name '" data-act="code" data-tip="Open it as code">Code</span>'
              .  '<span class="axd-evgo" data-ev="' name '" data-act="steps" data-tip="Open it as steps: a flowchart, no code">Steps</span>'
              .  '<div class="axd-evname">' AxTags.E(name) '</div>'
              .  '<div class="axd-evsig">' AxTags.E(AxGen.HandlerName(n, name) "(" AxCat.Sig(name) ")") '</div>'
              .  (code != "" ? '<div class="axd-evsig">' AxTags.E(AxPanes.Peek(code)) '</div>' : "")
              .  '</div>'
        }
        if (h = "")
            h := '<div class="axd-note">Nothing happens yet when it is used. Pick what should '
              .  'have code -- double-clicking it on the canvas opens the first one.</div>'
        if (free != "")
            h .= '<div class="axd-evadd"><span class="axd-dim">Add a handler</span> ' free '</div>'
        return h
    }
    static Peek(code) {
        for line in StrSplit(StrReplace(code, "`r", ""), "`n")
            if (Trim(line) != "")
                return StrLen(line) > 46 ? SubStr(Trim(line), 1, 46) "..." : Trim(line)
        return ""
    }

    ; ------------------------------------------------ window / project tab
    static WindowHtml(s) {
        f := s._fields
        P := s.P
        add := (d) => (f.Push(d), AxPanes.Editor(d))
        W := P.W
        h := ""
        ; Only worth the room once a project has more than one window. The name
        ; is an identifier, not a caption: it becomes the ShowThat() the other
        ; windows call.
        if (P.Wins.Length > 1 || W.Kind != "main") {
            extra := ""
            if (W.Kind != "main")
                extra .= add({Id: "w_in", L: "It is given", Kind: "multiline", Rows: 3, Get: (*) => W.Inputs, Set: (v) => W.Inputs := v})
            if (W.Kind = "dialog")
                extra .= add({Id: "w_out", L: "It hands back", Kind: "multiline", Rows: 3, Get: (*) => W.Outputs, Set: (v) => W.Outputs := v})
            note := (W.Kind = "main") ? "Made and shown when the program starts."
                  : "<b>It is given</b>: what whoever opens it passes in, one per line as <b>name = value if not given</b>. "
                  . "They are values of those names inside it. (" AxTags.E(AxGen.Fn(W)) "() is what opens it.)"
            if (W.Kind = "dialog")
                note .= " <b>It hands back</b>: one per line as <b>name = what</b>, read as it closes."
            h .= AxPanes.Group(s, "This window", ""
                . add({Id: "w_name", L: "Name", Kind: "text", Get: (*) => W.Name, Set: (v) => AxPanes.SetWinName(s, v)})
                . add({Id: "w_kind", L: "Opens as", Kind: "choice", Opts: "main:The main window, as the program starts|window:A window, when something opens it|dialog:A dialog -- the rest waits until it closes|tool:A small tool window|code:A window your own code makes when it wants one", Get: (*) => W.Kind, Set: (v) => AxPanes.SetWinKind(s, v)})
                . extra
                . '<div class="axd-note">' note '</div>')
        }
        ; Grouped by what a person is thinking about, not by how AxGui stores
        ; it: its size, its title bar, how it opens, the keys, its pages, how
        ; it looks. Everything about the title bar used to be in four groups;
        ; "Always on top" sat under Frame and "Escape closes" under Behaviour,
        ; a screen away from "Escape presses". What belongs to the whole
        ; program (the exe's name and icon, the tray, hotkeys) is a link.
        see := (label, where) => '<a class="axd-link" data-do="go.' where '">' label '</a>'
        h .= AxPanes.Group(s, "Size", ""
            . add({Id: "w_w", L: "Width", Kind: "num", Get: (*) => P.Width, Set: (v) => P.Width := (v = "" ? 800 : v)})
            . add({Id: "w_h", L: "Height", Kind: "num", Get: (*) => P.Height, Set: (v) => P.Height := (v = "" ? 520 : v)})
            . '<div class="axd-note"><span class="axd-hbtn axd-go" data-do="win.fit">Fit to what it holds</span> '
            . 'as tall as its page needs, with the stylesheet&#39;s own room round it.</div>'
            . add({Id: "w_resize", L: "Can be resized", Kind: "flag", Get: (*) => P.Resizable, Set: (v) => P.Resizable := v})
            . add({Id: "w_mw", L: "No narrower than", Kind: "num", Get: (*) => P.MinWidth, Set: (v) => P.MinWidth := (v = "" ? 0 : v)})
            . add({Id: "w_mh", L: "No shorter than", Kind: "num", Get: (*) => P.MinHeight, Set: (v) => P.MinHeight := (v = "" ? 0 : v)})
            . add({Id: "w_maxbox", L: "Maximise button", Kind: "flag", Get: (*) => P.MaximizeBox, Set: (v) => P.MaximizeBox := v})
            . add({Id: "w_minbox", L: "Minimise button", Kind: "flag", Get: (*) => P.MinimizeBox, Set: (v) => P.MinimizeBox := v})
            . add({Id: "w_snapl", L: "Snap layouts", Kind: "flag", Get: (*) => P.SnapLayouts, Set: (v) => P.SnapLayouts := v})
            . '<div class="axd-note">Snap layouts is the Windows 11 box of arrangements that appears when you point at the maximise button.</div>', "wsize")
        h .= AxPanes.Group(s, "Title bar", ""
            . add({Id: "w_frame", L: "Has a title bar", Kind: "flag", Get: (*) => P.Frame, Set: (v) => P.Frame := v, Rebuild: true})
            . (P.Frame ? ""
               : '<div class="axd-note">Without one the window is a bare page, with no edges -- for a splash, an overlay or a '
               . 'widget. Nothing moves it unless you give it a way to.</div>')
            . add({Id: "w_title", L: "Title", Kind: "text", Get: (*) => P.Title, Set: (v) => P.Title := v})
            . add({Id: "w_tshow", L: "Show the title", Kind: "flag", Get: (*) => P.TitleShow, Set: (v) => P.TitleShow := v})
            . add({Id: "w_tcenter", L: "Title in the middle", Kind: "flag", Get: (*) => P.TitleCenter, Set: (v) => P.TitleCenter := v})
            . add({Id: "w_icon", L: "Icon", Kind: "text", Get: (*) => P.Icon, Set: (v) => P.Icon := v})
            . '<div class="axd-note"><span class="axd-hbtn" data-icon="w_icon">Choose a glyph</span> '
            . '<span class="axd-hbtn" data-do="icon.file">From a file...</span> '
            . '<span class="axd-hbtn" data-do="icon.dll">From a DLL or EXE...</span> '
            . '<span class="axd-hbtn" data-do="icon.auto">The script&#39;s own</span> '
            . '<span class="axd-hbtn" data-do="icon.hide">No icon</span><br>'
            . 'The icon in the title bar and on the taskbar. The exe&#39;s own icon is in ' see("App &gt; Details", "details")
            . ', the tray&#39;s in ' see("App &gt; Tray icon", "tray") '.</div>'
            . add({Id: "w_titleitems", L: "Buttons on it", Kind: "multiline", Rows: 3,
                   Get: (*) => P.TitleItems, Set: (v) => P.TitleItems := v})
            . '<div class="axd-align"><span class="axd-hbtn" data-do="title.item">Add a button</span> '
            . '<span class="axd-hbtn" data-do="title.burger">Add a menu button (&#x2630;)</span></div>'
            . '<div class="axd-note">One button per line: <b>id | kind | content | flags | code</b>. Kinds: burger, glyph, text, '
            . 'svg, sep, spacer. Flags: right, toggle, on, tip=, class=. For example ' AxTags.E("new | glyph | E710 | tip=New") '</div>', "wtitle")
        h .= AxPanes.StartGroup(s, W, add)
        h .= AxPanes.KeysGroup(s, W, add)
        h .= AxPanes.TabGroup(s, W, add)
        ; a window brought in from a Gui() script: where the script put
        ; everything, or the same design as rows that resize
        if AxLayout.Has(P.W)
            h .= AxPanes.Group(s, "Layout from the script", ""
                . add({Id: "w_implay", L: "Controls sit", Kind: "choice", Rebuild: true,
                       Opts: "fixed:Where the script put them -- fixed, as it looked|rows:In rows that resize with the window",
                       Get: (*) => AxLayout.Mode(P.W), Set: (v) => AxLayout.Switch(P.W, v)})
                . '<div class="axd-note">One design seen two ways. Switching back puts every control exactly where the script had it.</div>')
        h .= AxPanes.Group(s, "Pages", ""
            . add({Id: "w_nav", L: "A rail of pages down the side", Kind: "flag", Get: (*) => P.Nav, Set: (v) => P.Nav := v})
            . add({Id: "w_head", L: "Each page shows its name", Kind: "choice", Opts: AxPanes.NONE ":When there are several pages|1:Always|0:Never",
                   Get: (*) => (P.Headings = "" ? AxPanes.NONE : String(P.Headings)),
                   Set: (v) => P.Headings := (v = AxPanes.NONE ? "" : Integer(v))})
            . add({Id: "w_scroll", L: "A page too long to fit", Kind: "choice", Rebuild: true,
                   Opts: AxPanes.NONE ":Scrolls, the bar showing when pointed at|always:Scrolls, with a bar always showing|never:Is cut off",
                   Get: (*) => (P.PageScroll = "" ? AxPanes.NONE : P.PageScroll),
                   Set: (v) => P.PageScroll := (v = AxPanes.NONE ? "" : v)})
            . '<div class="axd-note">Pages are added from the page strip over the canvas, or Add &gt; A page. '
            . '<span class="axd-hbtn" data-do="arrange.page">Arrange this page...</span></div>', "wpages")
        h .= AxPanes.Group(s, "Look", ""
            . add({Id: "w_sheet", L: "Style", Kind: "choice",
                   Opts: "win11:Windows 11|win98:Windows 9x|winxp:Windows XP|win365:Windows 365|cyber:Cyber|rpg:RPG|cozy:Cozy|aurora:Aurora|instrument:Instrument|precision:Precision|inset:Inset|brutalist:Brutalist",
                   Get: (*) => (P.Stylesheet = "" ? "win11" : P.Stylesheet), Set: (v) => AxPanes.SetSheet(s, v)})
            . add({Id: "w_theme", L: "Dark or light", Kind: "choice", Opts: "dark:Dark|light:Light|system:As Windows is set",
                   Get: (*) => P.Theme, Set: (v) => AxPanes.SetTheme(s, v)})
            . add({Id: "w_accent", L: "Accent colour", Kind: "color", Get: (*) => P.Accent, Set: (v) => AxPanes.SetAccent(s, v)})
            . add({Id: "w_useacc", L: "Coloured controls", Kind: "flag", Get: (*) => P.UseAccent, Set: (v) => P.UseAccent := v})
            . add({Id: "w_tint", L: "Tint the background", Kind: "color", Get: (*) => P.Tint, Set: (v) => P.Tint := v})
            . add({Id: "w_tints", L: "How much tint", Kind: "choice",
                   Opts: "0.06:Faint|0.12:Light|0.18:Medium|0.28:Strong|0.4:Very strong",
                   Get: (*) => (String(P.TintStrength) = "" ? "0.12" : String(P.TintStrength)), Set: (v) => P.TintStrength := v})
            . add({Id: "w_round", L: "Rounded corners", Kind: "flag", Get: (*) => P.RoundCorners, Set: (v) => P.RoundCorners := v})
            . add({Id: "w_border", L: "Edge colour", Kind: "color", Get: (*) => P.BorderColor, Set: (v) => P.BorderColor := v})
            . add({Id: "w_snapb", L: "Edge colour, snapped", Kind: "color", Get: (*) => P.SnapBorder, Set: (v) => P.SnapBorder := v})
            . add({Id: "w_opacity", L: "See-through", Kind: "num", Hint: "255 is solid, 0 invisible", Get: (*) => P.Opacity, Set: (v) => P.Opacity := v})
            . '<div class="axd-note">The canvas wears the window&#39;s own look, so a light Windows 9x window lays out fine inside a dark studio. '
            . 'Colours, shapes and type, one by one, are on the ' see("Look tab", "look") '.</div>', "look")
        h .= AxPanes.Group(s, "Menu bar", ""
            . add({Id: "w_menus", L: "Menus", Kind: "multiline", Rows: 6,
                   Get: (*) => P.Menus, Set: (v) => P.Menus := v})
            . '<div class="axd-align"><span class="axd-hbtn" data-do="menu.add">Add a menu</span> '
            . '<span class="axd-hbtn" data-do="menu.item">Add an item</span></div>'
            . '<div class="axd-note">A menu on its own line, its items under it, indented: <b>Label | Shortcut | code</b>. A line of <b>-</b> is a divider. '
            . '&amp; before a letter underlines it.<br>'
            . AxTags.E("&File") '<br>' AxTags.E("    &New | Ctrl+N | g.Toast(" Chr(34) "New" Chr(34) ")")
            . '<br>' AxTags.E("    -") '<br>' AxTags.E("    E&xit | Alt+F4 | g.Close()") '</div>')
        h .= AxPanes.Group(s, "Status bar", ""
            . add({Id: "w_statusparts", L: "Parts", Kind: "multiline", Rows: 3,
                   Get: (*) => P.Status, Set: (v) => P.Status := v})
            . '<div class="axd-align"><span class="axd-hbtn" data-do="status.add">Add a part</span></div>'
            . '<div class="axd-note">The strip along the bottom. One part per line: <b>id | text | flags</b>. Flags: grow (takes the room left), '
            . 'right, dim, w= (a width), icon= (a glyph).<br>'
            . AxTags.E("msg | Ready | grow icon=E930") '<br>' AxTags.E("pos | Ln 1, Col 1 | w=120 right") '</div>')
        h .= AxPanes.Group(s, "Its code", ''
            . '<div class="axd-p"><span class="axd-hbtn" data-code="init">What it does when it opens</span> '
            . '<span class="axd-hbtn" data-code="script">Your own functions</span></div>'
            . '<div class="axd-p"><span class="axd-hbtn" data-do="go.map">See it step by step</span> '
            . '<span class="axd-hbtn" data-code="show">The whole script, as exported</span></div>'
            . '<div class="axd-note">What it does when it opens runs once its controls are made, just before it is shown. '
            . 'What happens when things are clicked is on each control, and on ' see("Logic", "rules") '.</div>', "wcode")
        h .= AxPanes.Group(s, "Advanced", ""
            . add({Id: "w_appname", L: "Name for Windows", Kind: "text", Hint: "blank: the title",
                   Get: (*) => P.AppName, Set: (v) => P.AppName := v})
            . add({Id: "w_appid", L: "Taskbar group", Kind: "text", Hint: "Company.App -- blank: from the name",
                   Get: (*) => P.AppId, Set: (v) => P.AppId := v})
            . '<div class="axd-note">Windows groups taskbar buttons by this, and pins by it: two windows with the same one stack together.</div>'
            . add({Id: "w_back", L: "Colour before it draws", Kind: "text", Hint: "the colour shown for a moment as it opens",
                   Get: (*) => P.BackColor, Set: (v) => P.BackColor := v})
            . add({Id: "w_focus", L: "Keyboard outline", Kind: "choice",
                   Opts: AxPanes.NONE ":In the accent colour|contrast:High contrast|none:None",
                   Get: (*) => (P.FocusRing = "" ? AxPanes.NONE : P.FocusRing),
                   Set: (v) => P.FocusRing := (v = AxPanes.NONE ? "" : v)})
            . '<div class="axd-note">The outline round whatever the keyboard is in, when Tab moves it.</div>'
            . add({Id: "w_zoom", L: "Ctrl+wheel zooms", Kind: "flag", Get: (*) => P.AllowZoom, Set: (v) => P.AllowZoom := v})
            . add({Id: "w_ncm", L: "Right-click shows the web menu", Kind: "flag",
                   Get: (*) => P.NativeContextMenu, Set: (v) => P.NativeContextMenu := v})
            . add({Id: "w_comp", L: "Smoother redraw", Kind: "flag", Get: (*) => P.Composited, Set: (v) => P.Composited := v})
            . '<div class="axd-note">Smoother redraw paints the whole window at once, so resizing does not flicker; it can make a very big window slower.</div>'
            . add({Id: "w_tipdelay", L: "Tooltips after", Kind: "num", Hint: "450 ms",
                   Get: (*) => P.TooltipDelay, Set: (v) => P.TooltipDelay := v})
            . add({Id: "w_menu", L: "Menu bar, as code", Kind: "multiline", Rows: 2,
                   Get: (*) => P.MenuBar, Set: (v) => P.MenuBar := v})
            . add({Id: "w_status", L: "Status bar, as code", Kind: "multiline", Rows: 2,
                   Get: (*) => P.StatusBar, Set: (v) => P.StatusBar := v})
            . '<div class="axd-note">Code written here (g.AddMenuBar(...), g.AddStatusBar(...)) wins over the Menu bar and Status bar above, '
            . 'and the canvas can only sketch it.</div>', "wadv")
        return h
    }
    ; These change the design, not the studio: the canvas is skinned on its
    ; own, so you can lay out a light Windows 9x window in a dark editor.
    ; The data behind the design. The variables belong to the project and the
    ; bindings to the window, because a binding names a control and a control
    ; lives in one window -- while a variable is what two windows share.
    ; The theme editor: one field per token in AxTheme.Fields, each writing one
    ; line of Look and one CSS rule. Nothing here knows what the tokens mean --
    ; add one to that table and it appears, is saved, previews and exports.
    static ThemeGroup(s, add) {
        W := s.P.W
        body := ""
        for f in AxTheme.Fields
            body .= add({Id: "lk_" f.K, L: f.L, Kind: f.Kind, Opts: f.HasOwnProp("Opts") ? f.Opts : "",
                         Get: AxPanes.LookGet(W, f.K), Set: AxPanes.LookSet(s, f.K)})
        body .= add({Id: "lk_css", L: "Extra CSS", Kind: "multiline", Rows: 4,
                     Get: AxPanes.CssGet(W), Set: AxPanes.CssSet(s)})
        body .= '<div class="axd-note">'
             .  '<span class="axd-hbtn" data-do="look.seed">Fill from the current look</span> '
             .  '<span class="axd-hbtn" data-do="look.clear">Clear it all</span>'
             .  '<br>Layered over the stylesheet, not instead of it, so a fix to the'
             .  ' sheet still reaches the design. Exports as one SetExtraCss call.</div>'
        return AxPanes.Group(s, "Theme editor", body)
    }
    static LookGet(W, key) => (*) => AxTheme.Get(W, key)
    ; AfterLookCanvas, not AfterLook: the second rebuilds this pane, and
     ; rebuilding a pane under the caret that is typing into it drops every
     ; other keystroke -- which is why the theme editor felt dead.
    static LookSet(s, key) => (v) => (AxTheme.Set(s.P.W, key, v), s.AfterLookCanvas())
    static CssGet(W) => (*) => W.Css
    static CssSet(s) => (v) => (s.P.W.Css := v, s.AfterLookCanvas())

    static SetTheme(s, v) {
        s.P.Theme := v
        s.AfterLook()
    }
    static SetSheet(s, v) {
        s.P.Stylesheet := v
        s.AfterLook()
    }
    static SetAccent(s, v) {
        s.P.Accent := v
        try s.SetAccent(v = "" ? "system" : v)
        s.AfterLook()
    }

    ; ============================================================ workspaces
    ; Logic and App are pages rather than panes: the whole middle, two
    ; columns, and room for a list to be a list.
    static WsPage(s) {
        if (s.Ws = "code")
            return s.CodeNav()
        if (s.Ws = "steps")
            return AxStepsUi.Paint(s)
        ; the map is read from the program, and only again when it changes
        if (s.Ws = "map") {
            fresh := true
            try fresh := !IsObject(s.El("axmView"))
            if fresh
                s.Html("axdMap", AxMap.Page(s))
            return AxMap.Paint(s, false, fresh)
        }
        id := (s.Ws = "logic") ? "axdLogic" : (s.Ws = "app") ? "axdApp" : (s.Ws = "look") ? "axdLook" : ""
        if (id = "")
            return
        ; drawn again after every change: the section in view keeps its place
        was := "", top := 0
        try {
            m := s.El(id).querySelector(".axd-rpmain")
            was := m.getAttribute("data-sec"), top := m.scrollTop
        }
        s.Html(id, (id = "axdLogic") ? AxPanes.LogicPage(s) : (id = "axdLook") ? AxLook.Page(s) : AxPanes.AppPage(s))
        try {
            m := s.El(id).querySelector(".axd-rpmain")
            if (m.getAttribute("data-sec") = was)
                m.scrollTop := top
        }
        if (id = "axdLook") {
            try AxTags.Expand(s.Doc)
            try s._MakeFocusable()
            AxPanes.Wire(s)
            AxLook.Paint(s)
            return
        }
        try AxTags.Expand(s.Doc)
        try s._MakeFocusable()
        AxPanes.Wire(s)
        ; list editors -- a macro's steps -- are drawn by the page script
        try s.Js("AXG.mountAll();")
    }
    static WsHead(title, lead) => '<div class="axd-wstitle">' title '</div>'
                                . '<div class="axd-wslead">' lead '</div>'
    ; Bindings, rules and states belong to one window, so with more than one
    ; the page says which, and lets you change it without leaving.
    static WsWinPick(s) {
        if (s.P.Wins.Length < 2)
            return ""
        h := '<div class="axd-wspick">'
        for i, w in s.P.Wins
            h .= '<span class="axd-chip' (i = s.P.Cur ? " on" : "") '" data-win="' i '">'
              .  '<span class="ico">&#x' AxPanes.WinIcon(w.Kind) ';</span>' AxTags.E(w.Name) '</span>'
        return h '</div>'
    }
    ; Logic and App are laid out the way a program lays out its settings, not
    ; the way a web page does: the sections down a rail on the left, with how
    ; many each holds and whether any is broken, and the one picked filling
    ; the rest, with its own heading and its buttons along the top. A page
    ; that stacked every section meant scrolling past all of them to reach one.
    ; A section that is a browser -- a list beside the thing picked in it --
    ; takes the whole width rather than a column of reading width.
    static Wide := Map("libraries", 1, "files", 1)
    static RailPage(sec, rail, body) => '<div class="axd-rp"><div class="axd-rprail">' rail '</div>'
        . '<div class="axd-rpmain" data-sec="' sec '"><div class="axd-rpinner'
        . (AxPanes.Wide.Has(sec) ? " axd-rpwide" : "") '">' body '</div></div></div>'
    static RailHead(text) => '<div class="axd-rphead">' text '</div>'
    static RailItem(key, icon, label, n := "", bad := 0, on := false) =>
        '<div class="axd-rpitem' (on ? " on" : "") '" data-rpsec="' key '">'
         . (SubStr(icon, 1, 1) = "#" ? '<span class="axd-rpsw" style="background:'
                                        . (SubStr(icon, 2, 6) = "linear" ? SubStr(icon, 2) : icon) '"></span>'
                                     : '<span class="ico">&#x' icon ';</span>')
         . '<span class="axd-rplab">' label '</span>'
         . ((bad != 0 && bad != "") ? '<span class="axd-rpbad">' bad '</span>'
            : (n != "" ? '<span class="axd-rpn">' n '</span>' : "")) '</div>'
    ; A section's heading: its name, its buttons, and one line on what it is.
    static PanelHead(title, lead, tools := "") =>
        '<div class="axd-rphd"><div class="axd-rprow"><div class="axd-rpht">' AxTags.E(title) '</div>'
         . (tools != "" ? '<div class="axd-rptools">' tools '</div>' : "") '</div>'
         . (lead != "" ? '<div class="axd-rplead">' lead '</div>' : "") '</div>'
    static LogicPage(s) {
        f := s._fields
        add := (d) => (f.Push(d), AxPanes.Editor(d))
        W := s.P.W
        sec := s.LogicSec
        bad := AxLogic.BadCounts(s)
        R := (key, icon, label, n := "", b := 0) => AxPanes.RailItem(key, icon, label, n, b, key = sec)
        rail := ""
        ; bindings, rules, states and hotkeys belong to one window: with more
        ; than one, the rail starts with which
        if (s.P.Wins.Length > 1) {
            rail .= AxPanes.RailHead("Window")
            for i, w in s.P.Wins
                rail .= '<div class="axd-rpitem axd-rpwin' (i = s.P.Cur ? " on" : "") '" data-win="' i '">'
                     .  '<span class="ico">&#x' AxPanes.WinIcon(w.Kind) ';</span>'
                     .  '<span class="axd-rplab">' AxTags.E(w.Name) '</span></div>'
        }
        rail .= AxPanes.RailHead("The whole program")
             .  R("values", "E8EF", "Values", AxBind.Vars(s.P).Length)
             .  R("conditions", "E9D5", "Conditions", AxAuto.Conds(s.P).Length)
             .  R("hotstrings", "E8D2", "Typed shortcuts", AxAuto.Strings(s.P).Length)
             .  R("timers", "E916", "Timers", AxAuto.Timers(s.P).Length)
             .  R("macros", "E768", "Macros", AxAuto2.Macros(s.P).Length)
             .  R("settings", "E713", "Settings", AxAuto2.Settings(s.P).Length)
             .  AxPanes.RailHead("When things happen")
             .  R("events", "E7C1", "In Windows", AxAuto2.Events(s.P).Length)
             .  R("watchers", "E8B7", "In a folder", AxAuto2.Watchers(s.P).Length)
             .  AxPanes.RailHead(s.P.Wins.Length > 1 ? "In " AxTags.E(W.Name) : "This window")
             .  R("bindings", "E8C8", "Bindings", AxBind.Binds(W).Length, bad.B)
             .  R("rules", "E945", "Rules", AxFlow.Parse(W).Length, bad.R)
             .  R("states", "E81E", "States", AxFlow.States(W).Length)
             .  R("hotkeys", "E765", "Hotkeys", AxAsset.Hotkeys(W).Length, bad.H)
             .  R("menus", "E700", "Menus", AxChrome.Ctx(W.Ctx).Length + (Trim(W.Menus) != "" ? 1 : 0))
             .  R("code", "E943", "Code")
             .  '<div class="axd-rpfoot">What the program does: the values it keeps, what they are '
             .  'bound to, the rules that react, and the states a window can be in.'
             .  '<br><br>Up and Down move between sections.</div>'
        AxLogic.Panel := true
        try {
            switch sec {
            case "bindings": body := AxLogic.Bindings(s, add)
            case "rules":    body := AxLogic.Rules(s, add)
            case "states":   body := AxLogic.States(s, add)
            case "hotkeys":  body := AxLogic.HotkeyList(s, add)
            case "menus":    body := AxMenuUi.Section(s, add)
            case "code":     body := AxLogic.Code(s)
            case "conditions": body := AxAutoUi.Conds(s, add)
            case "hotstrings": body := AxAutoUi.Strings(s, add)
            case "timers":   body := AxAutoUi.Timers(s, add)
            case "macros":   body := AxAuto2Ui.Macros(s, add)
            case "settings": body := AxAuto2Ui.Settings(s, add)
            case "events":   body := AxAuto2Ui.Events(s, add)
            case "watchers": body := AxAuto2Ui.Watchers(s, add)
            default:         body := AxLogic.Values(s, add), sec := "values"
            }
        } finally
            AxLogic.Panel := false
        return AxPanes.RailPage(sec, rail, body)
    }
    static AppPage(s) {
        f := s._fields
        add := (d) => (f.Push(d), AxPanes.Editor(d))
        cfg := AxAsset.Compile(s.P)
        G := (k, d := "") => (cfg.Has(k) && cfg[k] != "") ? cfg[k] : d
        kv := (k, v) => '<div class="axd-kv"><span>' k '</span>' AxTags.E(v) '</div>'
        sec := s.AppSec
        R := (key, icon, label, n := "", b := 0) => AxPanes.RailItem(key, icon, label, n, b, key = sec)
        ; a window nothing opens is a window nobody will see
        opened := Map()
        for l in s.P.Links()
            opened[l.To] := true
        lost := 0
        for w in s.P.Wins
            lost += (w.Kind != "main" && !opened.Has(w.Name))
        lb := s.LastBuild
        tray := Trim(String(s.P.Tray)) != ""
        rail := AxPanes.RailHead("The program")
              . R("windows", "E7C4", "Windows", s.P.Wins.Length, lost)
              . R("details", "E946", "Details")
              . R("build", "E7B8", "Build", IsObject(lb) && lb.Ok ? "built" : "",
                  IsObject(lb) && !lb.Ok ? "failed" : 0)
              . AxPanes.RailHead("What it carries")
              . R("files", "E8A5", "Files", AxAsset.Files(s.P).Length)
              . R("libraries", "E82D", "Libraries", AxPkg.Used(s.P).Length)
              . R("includes", "E943", "Code files", AxAsset.Includes(s.P).Length)
              . R("packs", "E8F1", "Extra controls", AxComp.Used(s.P).Length)
              . AxPanes.RailHead("How it starts")
              . R("arguments", "E756", "Command-line options", AxAsset.Args(s.P).Length)
              . R("modes", "E7E8", "Ways to start", AxAsset.Modes(s.P).Length)
              . R("tray", "E8B7", "Tray icon", tray ? "set" : "")
              . R("script", "E713", "Script settings", AxAsset.Truthy(G("admin", 0)) ? "admin" : "")
              . '<div class="axd-rpfoot">The program as a whole: its windows, what it is called, '
              . 'what it carries, how it starts and how it is built.'
              . '<br><br>Up and Down move between sections.</div>'
        AxLogic.Panel := true
        try {
            switch sec {
            case "details":
                ; What Windows says the exe is. The same text the Compile form
                ; writes, one line changed at a time; each blank box says what
                ; blank means.
                body := AxPanes.PanelHead("Details", "What Windows shows on the exe&#39;s Details tab. "
                          . "Every box can stay blank.")
                     . '<div class="axd-rpform">'
                     . add({Id: "ap_name", L: "Name", Kind: "text", Get: (*) => G("name"),
                            Set: AxPanes.CompileFn(s, "name"), Hint: s.P.Main().Title " (the main window's title)"})
                     . add({Id: "ap_desc", L: "Description", Kind: "text", Get: (*) => G("description"),
                            Set: AxPanes.CompileFn(s, "description"), Hint: "what it is, in a few words"})
                     . add({Id: "ap_ver", L: "Version", Kind: "text", Get: (*) => G("version"),
                            Set: AxPanes.CompileFn(s, "version"), Hint: "1.0.0.0 -- four numbers"})
                     . add({Id: "ap_company", L: "Company", Kind: "text", Get: (*) => G("company"),
                            Set: AxPanes.CompileFn(s, "company"), Hint: "you, or your company"})
                     . add({Id: "ap_copy", L: "Copyright", Kind: "text", Get: (*) => G("copyright"),
                            Set: AxPanes.CompileFn(s, "copyright"), Hint: "(c) " A_YYYY})
                     . add({Id: "ap_icon", L: "Icon (.ico)", Kind: "text", Get: (*) => G("icon"),
                            Set: AxPanes.CompileFn(s, "icon"), Hint: "blank: the script's own icon"})
                     . add({Id: "ap_inst", L: "Opened twice", Kind: "choice",
                            Opts: "Force:The new one replaces the one running|Ignore:The one running stays, the new one closes|"
                                . "Prompt:It asks which to keep|Off:Both run side by side",
                            Get: (*) => G("instance", "Force"), Set: AxPanes.CompileFn(s, "instance")})
                     . '</div><div class="axd-note">What happens when someone starts the program while it is already running. '
                     . 'The window&#39;s own icon is in its ' '<a class="axd-link" data-do="go.window.wtitle">title bar settings</a>'
                     . ', the tray&#39;s under ' '<a class="axd-link" data-do="go.tray">Tray icon</a>.</div>'
            case "build":
                body := AxPanes.PanelHead("Build", "Making the program an .exe that runs on any Windows PC, with or "
                          . "without AutoHotkey, using Ahk2Exe (AutoHotkey&#39;s own compiler). The script is exported "
                          . "first, so what is built is what is on screen.",
                          '<span class="axd-hbtn axd-go" data-do="app.build">Compile it now</span> '
                          . '<span class="axd-hbtn" data-do="app.compile">Everything about the build...</span> '
                          . '<span class="axd-hbtn" data-do="app.export">Export the script as...</span>')
                     . AxPanes.BuildResult(s)
                     . '<div class="axd-rpsub">Where it goes</div>'
                     . kv("Goes to", (t := AxWiz.ExeTarget(s)) != "" ? t : "beside the script, once it is exported")
                     . kv("Compiler", AxBuild.Exe(s.Ahk2Exe) != "" ? "Ahk2Exe, found"
                                      : "Ahk2Exe is not on this machine -- Everything about the build... has Get it")
                     . '<div class="axd-rpsub">What goes in</div>'
                     . kv("Built on", G("base", "the AutoHotkey that runs the studio"))
                     . kv("AxGui's own files", StrLower(G("embed")) = "used" ? "only what the design uses" : "all of them")
                     . kv("Window made in advance", AxAsset.Truthy(G("prerender")) ? "yes -- it opens faster" : "no")
                     . kv("Inspector (Ctrl+Shift+I)", StrLower(G("devtools")) = "keep" ? "kept in the exe" : "left out of the exe")
                     . '<div class="axd-kv"><span>Your files</span>' ((n := AxAsset.Files(s.P).Length)
                        ? n ' -- see <a class="axd-link" data-do="go.files">Files</a>' : "none") '</div>'
            case "packs":
                body := AxPanes.PanelHead("Extra controls", "Controls beyond the built-in ones -- charts, gauges, date "
                          . "pickers -- one folder each. The export takes only the ones the design uses.")
                     . AxPanes.PackList(s)
            case "script":
                body := AxPanes.PanelHead("Script settings", "How the script behaves before it does anything "
                          . "else: as administrator or not, how it sends keys, how it matches window titles.")
                     . '<div class="axd-rpform">' AxAutoUi.Settings(s, add) '</div>'
            case "files":     body := AxFilesUi.Page(s, add)
            case "includes":  body := AxLogic.Includes(s, add)
            case "libraries": body := AxPkgUi.Section(s)
            case "arguments": body := AxLogic.Arguments(s, add)
            case "modes":     body := AxLogic.ModeList(s, add)
            case "tray":      body := AxMenuUi.TraySection(s, add)
            default:
                sec := "windows"
                body := AxPanes.PanelHead("Windows (" s.P.Wins.Length ")", "Every window in the program, and "
                          . "which one opens which. A window nothing opens is flagged: nothing will.")
                     . AxPanes.WinBoard(s)
            }
        } finally
            AxLogic.Panel := false
        return AxPanes.RailPage(sec, rail, body)
    }
    ; How the window starts: maximised, minimised or hidden, where on the
    ; screen, and the buttons Enter and Escape press.
    static StartGroup(s, W, add) {
        N := AxPanes.NONE
        states := "normal:As it is designed|max:Maximised|min:Minimised"
                . (W.Kind = "main" ? "|hidden:Hidden -- a tray icon or a hotkey brings it up" : "")
        pos := AxStart.PosOf(W)
        btns := N ":(none)"
        for b in AxKeyOrder.Buttons(s.P, W)
            btns .= "|" b.Name ":" b.Name
        h := add({Id: "w_start", L: "Starts", Kind: "choice", Opts: states,
                  Get: (*) => (W.StartState = "" ? "normal" : W.StartState),
                  Set: (v) => W.StartState := (v = "normal" ? "" : v)})
           . add({Id: "w_pos", L: "Where", Kind: "choice", Rebuild: true,
                  Opts: "auto:Centred on the main screen|mouse:Centred on the screen the mouse is on|"
                      . (W.Kind != "main" ? "main:Centred over the main window|" : "")
                      . "cursor:Beside the mouse pointer|"
                      . "tl:Top-left corner|tr:Top-right corner|bl:Bottom-left corner|br:Bottom-right corner|"
                      . "remember:Where it was last time|xy:At a place of its own",
                  Get: (*) => AxStart.PosOf(W), Set: (v) => W.StartPos := (v = "auto" ? "" : v)})
        if (pos = "xy")
            h .= add({Id: "w_x", L: "X on screen", Kind: "num", Get: (*) => W.WinX, Set: (v) => W.WinX := v})
               . add({Id: "w_y", L: "Y on screen", Kind: "num", Get: (*) => W.WinY, Set: (v) => W.WinY := v})
        h .= add({Id: "w_ontop", L: "Stays on top of others", Kind: "flag", Get: (*) => s.P.AlwaysOnTop, Set: (v) => s.P.AlwaysOnTop := v})
           . add({Id: "w_noact", L: "Opens without taking the keyboard", Kind: "flag", Get: (*) => s.P.NoActivate, Set: (v) => s.P.NoActivate := v})
           . '<div class="axd-note">' (pos = "remember"
                ? "Its place, its size and whether it was maximised are kept in a small .ini beside the "
                . "script; a place on a screen that is gone is not used. "
                : AxStart.AtPlaces.Has(pos) && pos != "cursor" && pos != "main"
                ? "A corner of the screen the mouse is on, a little way in. "
                : "") "It is put in its place before it is shown, so it never jumps."
           . (W.Kind = "main" && W.StartState = "hidden" ? ' Hidden, it needs a way to be shown: ' '<a class="axd-link" data-do="go.tray">a tray icon</a> or '
              . '<a class="axd-link" data-do="go.hotkeys">a hotkey</a>.' : "") '</div>'
        return AxPanes.Group(s, "When it opens", h, "wstart")
    }
    ; The keys the window answers by itself, and what closing it does. The
    ; window's own hotkeys are on Logic, with the rest of what it does.
    static KeysGroup(s, W, add) {
        N := AxPanes.NONE
        btns := N ":(none)"
        for b in AxKeyOrder.Buttons(s.P, W)
            btns .= "|" b.Name ":" b.Name
        h := add({Id: "w_defbtn", L: "Enter presses", Kind: "choice", Opts: btns,
                  Get: (*) => (W.DefaultBtn = "" ? N : W.DefaultBtn), Set: (v) => W.DefaultBtn := v})
           . add({Id: "w_canbtn", L: "Escape presses", Kind: "choice", Opts: btns,
                  Get: (*) => (W.CancelBtn = "" ? N : W.CancelBtn), Set: (v) => W.CancelBtn := v})
           . add({Id: "w_esc", L: "Escape closes it", Kind: "flag", Get: (*) => s.P.EscapeCloses, Set: (v) => s.P.EscapeCloses := v})
           . add({Id: "w_exit", L: "Closing it ends the program", Kind: "flag", Get: (*) => s.P.ExitOnClose, Set: (v) => s.P.ExitOnClose := v})
           . '<div class="axd-note">Enter is left alone in a box of several lines. Off, closing the window only hides it: the program '
           . 'goes on (in the tray, or on its hotkeys). Hotkeys of its own are on '
           . '<a class="axd-link" data-do="go.hotkeys">Logic &gt; Hotkeys</a>.</div>'
        ; before it closes: however it is closed, with a say in whether it does
        fns := AxPanes.ScriptFns(W)
        h .= add({Id: "w_askclose", L: "Before it closes", Kind: "choice",
                  Opts: N ":Just close|dirty:Ask to save unsaved changes|always:Always ask",
                  Get: (*) => (W.AskClose = "" ? N : W.AskClose), Set: (v) => W.AskClose := (v = N ? "" : v)})
           . add({Id: "w_savewith", L: "Saved by", Kind: "choice", Opts: fns,
                  Get: (*) => (W.SaveWith = "" ? N : W.SaveWith), Set: (v) => W.SaveWith := (v = N ? "" : v)})
           . add({Id: "w_beforeclose", L: "And asks", Kind: "choice", Opts: fns,
                  Get: (*) => (W.BeforeClose = "" ? N : W.BeforeClose), Set: (v) => W.BeforeClose := (v = N ? "" : v)})
           . '<div class="axd-note">However it is closed: its close button, a double-click on its icon, Alt+F4, the taskbar, '
           . 'the tray&#39;s Exit. <b>Unsaved changes</b> are what the rule verbs <b>dirty</b> and <b>clean</b> mark '
           . '(or <code>' W.Var '.Dirty := true</code> in code); the title shows a dot meanwhile. With a function that saves, '
           . 'the question is Save / Don&#39;t save / Cancel. <b>And asks</b> is a function of your own, '
           . '<code>Fn(win, why)</code>: return true to keep the window open.</div>'
        return AxPanes.Group(s, "Keys and closing", h, "wkeys")
    }
    ; The functions this window's script defines, as a choice list.
    static ScriptFns(W) {
        out := AxPanes.NONE ":(none)", seen := Map(), pos := 1, text := String(W.Script)
        seen.CaseSense := false
        while (pos := RegExMatch(text, "m)^[ \t]*([A-Za-z_]\w*)\([^)\r\n]*\)[ \t]*(?:\{|=>)", &m, pos)) {
            pos += m.Len
            if !seen.Has(m[1])
                seen[m[1]] := true, out .= "|" m[1] ":" m[1] "()"
        }
        return out
    }
    ; The order Tab goes in: the list, and the way to set it on the canvas.
    static TabGroup(s, W, add) {
        on := AxKeyOrder.Explicit(W)
        if (AxKeyOrder.Layout(s.P, W).Length = 0)
            return AxPanes.Group(s, "Tab order", '<div class="axd-note">Nothing here that takes the keyboard '
                 . 'has a name yet. Select a control and press F2.</div>', "wtab")
        h := add({Id: "w_taborder", L: on ? "Tab goes" : "Tab goes (as laid out)", Kind: "options", Shape: "n",
                  Get: (*) => AxKeyOrder.Text(s.P, W), Set: (v) => W.TabOrder := v})
           . '<div class="axd-note"><span class="axd-hbtn axd-go" data-do="tab.mode">Set it on the canvas</span> '
           . (on ? '<span class="axd-hbtn" data-do="tab.reset">Back to the layout order</span>' : "")
           . '<br>' (on ? "Tab visits them in this order, and the first has the keyboard when the window opens."
                        : "Tab follows the layout, top to bottom. Drag a row, or set it on the canvas, to change it.")
           . '</div>'
        return AxPanes.Group(s, "Tab order", h, "wtab")
    }
    static CompileFn(s, key) => (v) => AxAsset.SetCompile(s.P, key, v)
    ; How the last build went, first in its section: the dialog that said so
    ; is gone once dismissed, and Output scrolls.
    static BuildResult(s) {
        b := s.LastBuild
        if !IsObject(b)
            return '<div class="axd-bres">Not built yet in this session.</div>'
        h := '<div class="axd-bres ' (b.Ok ? "ok" : "bad") '"><span class="ico">&#x'
           . (b.Ok ? "E73E" : "E783") ';</span><b>' (b.Ok ? "Built" : "Did not build")
           . '</b> at ' b.When '. ' AxTags.E(b.Msg) '<div class="axd-bresacts">'
        if b.Ok
            h .= '<span class="axd-hbtn" data-do="app.showexe">Show it in Explorer</span> '
              .  '<span class="axd-hbtn" data-do="app.runexe">Run it</span>'
        else
            h .= '<span class="axd-hbtn" data-do="app.buildlog">What Ahk2Exe said</span>'
        return h '</div></div>'
    }
    ; A page holds the window list, the packs and the logic groups, so it
    ; answers to the clicks each of them used to get in its own pane.
    static WsClick(s, ev) {
        src := ev.srcElement
        pk := s.UpAttr(src, "data-pkg")
        if (pk != "")
            return s.Try("libraries: " pk, (*) => AxPkgUi.Act(s, pk))
        mn := s.UpAttr(src, "data-mnu")
        if (mn != "")
            return s.Try("menus: " mn, (*) => AxMenuUi.Act(s, mn))
        fl := s.UpAttr(src, "data-files")
        if (fl != "")
            return s.Try("files: " fl, (*) => AxFilesUi.Act(s, fl))
        act := s.UpAttr(src, "data-winact")
        if (act != "")
            return s.WinAction(act)
        wi := s.UpAttr(src, "data-win")
        if (wi != "")
            return s.SwitchWin(Integer(wi))
        sp := s.UpAttr(src, "data-showpack")
        if (sp != "")
            return s.ShowComponent(sp)
        row := s.UpAttr(src, "data-row")
        if (row != "")
            return s.RowAction(row)
        lk := s.UpAttr(src, "data-lkact")
        if (lk != "")
            return s.Try("look: " lk, (*) => AxLook.Act(s, lk))
        lw := s.UpAttr(src, "data-lkwin")
        if (lw != "") {
            s.LookSel := "design"
            return (Integer(lw) != s.P.Cur) ? s.SwitchWin(Integer(lw)) : s.Reflect(false)
        }
        bq := s.UpAttr(src, "data-bindq")
        if (bq != "")
            return AxPanes.QuickBind(s, bq)
        md := s.UpAttr(src, "data-macdel")
        if (md != "")
            return AxAuto2Ui.DropMacro(s, md)
        mc := s.UpAttr(src, "data-mac")
        if (mc != "")
            return (s.MacroSel := mc, s.Reflect(false))
        ms := s.UpAttr(src, "data-macstep")
        if (ms != "")
            return AxAuto2Ui.AddStep(s, ms)
        sec := s.UpAttr(src, "data-rpsec")
        if (sec != "")
            return s.GoSec(sec)
        j := s.UpAttr(src, "data-lgjump")
        if (j != "")
            return s.GoSec(j)
        AxPanes.RightClick(s, ev)
    }
    ; Down the page to a section, opening it first if it was folded away.
    static Jump(s, key) {
        if ((s.Shut is Map) && s.Shut.Has(key))
            s.ToggleGroup(key)
        try s.El("grp_" key).scrollIntoView()
    }

    ; -------------------------------------------------------------- wiring
    static Wire(s) {
        for f in s._fields {
            id := f.Id
            if (f.Kind = "static")
                continue
            if (f.Kind = "flag" || f.Kind = "choice" || f.Kind = "int") {
                s.OffValue(id)
                s.OnValue(id, AxPanes.ValueFn(s, id))
            } else {
                s.On("focusin", id, AxPanes.MarkFn(s, id))
                s.On("keyup", id, AxPanes.CommitFn(s, id))
                s.On("change", id, AxPanes.CommitFn(s, id))
            }
        }
    }
    static RightClick(s, ev) {
        src := ev.srcElement
        if AxLogic.Click(s, ev)
            return
        ; a group's (i): its hints, shown or put away -- before the header's
        ; own click, which folds the group
        gi := s.UpAttr(src, "data-ginfo")
        if (gi != "") {
            try {
                g := s.El("grp_" gi)
                AxWindow._SetClass(g, "hints-open", !AxWindow._HasClass(g, "hints-open"))
            }
            return
        }
        if (s.UpAttr(src, "data-rawt") != "") {
            s.RawOpen := !(s.HasOwnProp("RawOpen") && s.RawOpen)
            try AxWindow._SetClass(s.Doc.querySelector("#axdRightBody .axd-rawbox"), "on", s.RawOpen)
            try AxWindow._SetClass(s.Doc.querySelector("#axdRightBody .axd-rawt"), "on", s.RawOpen)
            return
        }
        grp := s.UpAttr(src, "data-grp")
        if (grp != "")
            return s.ToggleGroup(grp)
        go := s.UpAttr(src, "data-goto")
        if (go != "")
            return s.GoToHandler(go)
        li := s.UpAttr(src, "data-lint")
        if (li != "")
            return s.GoToIssue(Integer(li))
        which := s.UpAttr(src, "data-code")
        if (which = "show")
            return s.ShowGenerated()
        if (which != "")
            return s.EditScript(which)
        ic := s.UpAttr(src, "data-icon")
        if (ic != "")
            return s.OpenIcons(ic)
        gl := s.UpAttr(src, "data-glyph")
        if (gl != "")
            return s.PickGlyph(gl)
        act := s.UpAttr(src, "data-do")
        if (act != "")
            return s.QuickAction(act)
        anc := s.UpAttr(src, "data-alanchor")
        if (anc != "")
            return s.SetAnchor(anc)
        al := s.UpAttr(src, "data-align")
        if (al != "")
            return s.Align(al)
        pick := s.UpAttr(src, "data-pick")
        if (pick != "")
            return AxPanes.PickColour(s, pick)
        name := s.UpAttr(src, "data-ev")
        act := s.UpAttr(src, "data-act")
        if (name = "" || act = "")
            return
        n := s.Primary()
        if !IsObject(n)
            return
        if (act = "add")
            return s.AddEvent(n, name)
        idx := 0
        for i, e in n.Ev
            if (e["name"] = name)
                idx := i
        if (act = "edit" || act = "steps" || act = "code")
            s.EditEvent(n, idx, act = "edit" ? "" : act)
        else
            s.RemoveEvent(n, idx)
    }
    static PickColour(s, id) {
        cur := ""
        try cur := s.El(id).value
        hex := s.PickColor({Current: cur != "" ? cur : "#0078d4"})
        if (hex = "")
            return
        try s.El(id).value := hex
        AxPanes.Commit(s, id)
    }
    ; One undo entry per field you start editing, rather than one per keystroke.
    static MarkFn(s, id) => (*) => ((s._markedId = id) ? "" : (s.Mark(), s._markedId := id))
    static ValueFn(s, id) => (v, el) => (s.Mark(), s._markedId := "", AxPanes.Apply(s, id, v))
    static CommitFn(s, id) => (*) => AxPanes.Commit(s, id)
    static Commit(s, id) {
        v := ""
        try v := s.El(id).value
        AxPanes.Apply(s, id, v)
    }
    static Apply(s, id, v) {
        f := AxPanes.Field(s, id)
        if !IsObject(f)
            return
        if (f.Kind = "choice" && v = AxPanes.NONE)
            v := ""
        if (f.Kind = "flag")
            v := v ? 1 : 0
        if (f.Kind = "num")
            v := RegExReplace(Trim(String(v)), "[^0-9\-]")
        if f.HasOwnProp("Each") {
            same := f.HasOwnProp("SameType") ? f.SameType : ""
            for n in s.SelNodes()
                if (same = "" || n.Type = same)
                    f.Each.Call(n, v)
        } else
            f.Set.Call(v)
        s.P.Dirty := true
        ; a field that changes which other fields exist redraws the pane too
        if (f.HasOwnProp("Rebuild") && f.Rebuild)
            s.Refresh()
        else
            s.RefreshCanvas()
    }
    static Field(s, id) {
        for f in s._fields
            if (f.Id = id)
                return f
        return ""
    }
}
