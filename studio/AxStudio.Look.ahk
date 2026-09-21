#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxJson.ahk
#Include %A_LineFile%\..\AxStudio.Theme.ahk
#Include %A_LineFile%\..\AxStudio.Panes.ahk
#Include %A_LineFile%\..\AxStudio.Form.ahk

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
;  AxStudio.Look.ahk -- the Look workspace: themes, seen and made.
;
;  A theme here is a built-in look (win11, win98, winxp, aurora...) and the
;  changes made to it -- colours, corners, the font, the room things get, and
;  any CSS of your own. That is exactly what a design already carries (its
;  Stylesheet, Theme, Accent, Look and Css), so a theme can be put on a design
;  and taken off again, and the exported script needs nothing new: the look is
;  the sheet it names plus one SetExtraCss.
;
;  The workspace is three things side by side. The rail: this design's own
;  look, the themes you have made (files in the studio's folder, themes\), and
;  the built-in looks. The middle: a window in the look -- title bar, page
;  list, cards, every kind of field and button -- drawn by the library in a
;  frame of its own, so what you see is the sheet itself, not an imitation of
;  it. The right: everything you can change, and it changes as you type.
;
;  A built-in look is not edited in place: "Make a theme from it" copies it
;  into one of yours, and that is what changes.
; =============================================================================

class AxThemes {
    ; label, and what it looks like, for the rail
    static Builtins := [["win11", "Windows 11"], ["win365", "Office"], ["win98", "Windows 98"],
                        ["winxp", "Windows XP"], ["aurora", "Aurora"], ["cyber", "Cyber"],
                        ["cozy", "Cozy"], ["rpg", "Parchment"], ["instrument", "Instrument"],
                        ["precision", "Precision"], ["inset", "Inset"], ["brutalist", "Brutalist"]]
    static Label(base) {
        for b in AxThemes.Builtins
            if (b[1] = base)
                return b[2]
        return base
    }
    static Back(base, mode) {
        n := AxGui.SheetName(base)
        c := AxGui.SheetBack.Has(n) ? AxGui.SheetBack[n] : AxGui.SheetBack["win11"]
        return "#" ((mode = "light") ? c[1] : c[2])
    }
    ; for the rail: the light colour and the dark one, corner to corner
    static Swatch(base) => "#" "linear-gradient(135deg, " AxThemes.Back(base, "light") " 50%, " AxThemes.Back(base, "dark") " 50%)"

    static Dir(s) => s.Store "\themes"
    static List(s) {
        out := []
        d := AxThemes.Dir(s)
        if !DirExist(d)
            return out
        names := ""
        loop files d "\*.axtheme.json"
            names .= A_LoopFileFullPath "`n"
        for f in StrSplit(Sort(RTrim(names, "`n")), "`n") {
            if (f = "")
                continue
            m := ""
            try m := AxJson.Parse(FileRead(f, "UTF-8"))
            if (m is Map)
                out.Push(AxThemes.FromMap(m, f))
        }
        return out
    }
    static FromMap(m, file) {
        G := (k, d := "") => AxJson.Get(m, k, d)
        return {Name: G("name", "Untitled"), File: file, Sheet: G("base", "win11"),
                Mode: G("mode", "dark"), Accent: G("accent", ""), Look: G("look", ""), Css: G("css", "")}
    }
    static Save(s, t) {
        d := AxThemes.Dir(s)
        try DirCreate(d)
        if (t.File = "") {
            stem := RegExReplace(t.Name, "[^A-Za-z0-9 _-]"), stem := Trim(stem) != "" ? Trim(stem) : "theme"
            f := d "\" stem ".axtheme.json", n := 2
            while FileExist(f)
                f := d "\" stem " " n++ ".axtheme.json"
            t.File := f
        }
        m := Map("format", 1, "name", t.Name, "base", t.Sheet, "mode", t.Mode,
                 "accent", t.Accent, "look", t.Look, "css", t.Css)
        try FileDelete(t.File)
        FileAppend(AxJson.Stringify(m, "  "), t.File, "UTF-8-RAW")
    }
    static Find(s, file) {
        for t in AxThemes.List(s)
            if (t.File = file)
                return t
        return ""
    }
}

class AxLook {
    ; ------------------------------------------------------------- the page
    ; What is selected: "design", "b:<sheet>" for a built-in look, or
    ; "u:<file>" for one of yours.
    static Page(s) {
        f := s._fields
        add := (d) => (f.Push(d), AxPanes.Editor(d))
        sel := s.LookSel
        yours := AxThemes.List(s)
        R := (key, icon, label, n := "") => AxPanes.RailItem(key, icon, label, n, 0, key = sel)
        rail := AxPanes.RailHead("This design")
        for i, w in s.P.Wins
            rail .= '<div class="axd-rpitem axd-rpwin' ((sel = "design" && i = s.P.Cur) ? " on" : "") '"'
                 .  ' data-lkwin="' i '"><span class="axd-rpsw" style="background:'
                 .  SubStr(AxThemes.Swatch(w.Stylesheet), 2) '"></span>'
                 .  '<span class="axd-rplab">' AxTags.E(w.Name) '</span>'
                 .  '<span class="axd-rpn">' AxTags.E(AxThemes.Label(w.Stylesheet)) '</span></div>'
        rail .= AxPanes.RailHead("Yours")
        for t in yours
            rail .= R("u:" t.File, AxThemes.Swatch(t.Sheet), t.Name, AxThemes.Label(t.Sheet))
        rail .= '<div class="axd-rpitem axd-rpadd" data-lkact="new"><span class="ico">&#xE710;</span>'
              . '<span class="axd-rplab">New theme...</span></div>'
              . AxPanes.RailHead("Built in")
        for b in AxThemes.Builtins
            rail .= R("b:" b[1], AxThemes.Swatch(b[1]), b[2])
        rail .= '<div class="axd-rpfoot">A theme is a built-in look and your changes to it. Put '
              . 'one on this design and the exported script carries it.</div>'
        t := AxLook.Target(s)
        body := AxLook.Head(s, t)
              . '<div class="axd-lkwrap"><div class="axd-lkprev">'
              . '<div id="axdSpec"></div></div>'
              . '<div class="axd-lked">' AxLook.Editor(s, t, add) '</div></div>'
        ; the whole width: the window in the middle grows with it
        return StrReplace(AxPanes.RailPage(sel, rail, body), '<div class="axd-rpinner', '<div class="axd-rpinner axd-rpwide axd-lkinner', , , 1)
    }
    ; What is being looked at, as one shape whatever it is:
    ; {Kind: design|mine|builtin, Obj, Name, Base, Mode, Accent}
    static Target(s) {
        sel := s.LookSel
        if (SubStr(sel, 1, 2) = "u:") {
            t := AxThemes.Find(s, SubStr(sel, 3))
            if IsObject(t)
                return {Kind: "mine", Obj: t, Name: t.Name, Sheet: t.Sheet, Mode: t.Mode, Accent: t.Accent}
            s.LookSel := sel := "design"
        }
        if (SubStr(sel, 1, 2) = "b:") {
            b := SubStr(sel, 3)
            return {Kind: "builtin", Obj: "", Name: AxThemes.Label(b), Sheet: b, Mode: s.LookMode, Accent: ""}
        }
        W := s.P.W
        return {Kind: "design", Obj: W, Name: W.Name, Sheet: W.Stylesheet,
                Mode: (W.Theme = "light") ? "light" : (W.Theme = "system" ? AxWindow.SystemTheme() : "dark"),
                Accent: W.Accent}
    }
    static Head(s, t) {
        seg := '<span class="axd-lkseg"><span class="axd-hbtn' (t.Mode != "light" ? " on" : "")
             . '" data-lkact="mode.dark">Dark</span><span class="axd-hbtn' (t.Mode = "light" ? " on" : "")
             . '" data-lkact="mode.light">Light</span></span> '
        switch t.Kind {
        case "mine":
            return AxPanes.PanelHead(t.Name, "Your theme, built on " AxThemes.Label(t.Sheet)
                     . ". It changes as you type, and is saved as you go.",
                     '<span class="axd-hbtn" data-lkact="use">Use it in this design</span> ' seg
                     . '<span class="axd-hbtn" data-lkact="rename">Rename...</span> '
                     . '<span class="axd-hbtn" data-lkact="delete">Delete</span>')
        case "builtin":
            return AxPanes.PanelHead(t.Name, "A built-in look. Make a theme from it to change it; "
                     . "the original stays as it is.",
                     '<span class="axd-hbtn" data-lkact="copy">Make a theme from it</span> '
                     . '<span class="axd-hbtn" data-lkact="use">Use it in this design</span> ' seg)
        }
        return AxPanes.PanelHead(t.Name "'s look", "The look this window has now: "
                 . AxThemes.Label(t.Sheet) " and the changes on the right. The canvas follows as you type.",
                 '<span class="axd-hbtn" data-lkact="save">Save it as a theme...</span> ' seg
                 . (s.P.Wins.Length > 1 ? '<span class="axd-hbtn" data-lkact="spread">Give every window this look</span>' : ""))
    }
    ; ------------------------------------------------------------ editing
    static Editor(s, t, add) {
        if (t.Kind = "builtin")
            return '<div class="axd-lknote"><span class="ico">&#xE72E;</span>'
                 . 'The built-in looks are not changed here, so a fix to one still reaches every design '
                 . 'that uses it. <b>Make a theme from it</b> and change that instead.</div>'
                 . '<div class="axd-kv"><span>Window colour</span>' AxThemes.Back(t.Sheet, "dark")
                 . ' dark, ' AxThemes.Back(t.Sheet, "light") ' light</div>'
                 . '<div class="axd-kv"><span>Corners</span>' (AxGui.SheetRound(t.Sheet) ? "rounded" : "square") '</div>'
        o := t.Obj
        base := ""
        for b in AxThemes.Builtins
            base .= (base = "" ? "" : "|") b[1] ":" b[2]
        h := AxPanes.Group(s, "Built on",
                 add({Id: "lp_base", L: "Look", Kind: "choice", Opts: base,
                      Get: (*) => AxLook.BaseOf(o), Set: AxLook.BaseFn(s, o), Rebuild: true})
               . add({Id: "lp_accent", L: "Accent", Kind: "color", Get: (*) => o.Accent,
                      Hint: "the look's own: " s.DefaultAccentOf(AxLook.BaseOf(o), t.Mode),
                      Set: AxLook.PropFn(s, o, "Accent")}), "lkbase")
        groups := Map()
        order := []
        for fd in AxTheme.Fields {
            if !groups.Has(fd.G)
                groups[fd.G] := "", order.Push(fd.G)
            groups[fd.G] .= add({Id: "lp_" fd.K, L: fd.L, Kind: fd.Kind,
                                 Opts: fd.HasOwnProp("Opts") ? fd.Opts : "",
                                 Hint: fd.HasOwnProp("Hint") ? fd.Hint : (fd.Kind = "num" ? "as the look has it" : "from the look"),
                                 Get: AxLook.TokGet(o, fd.K), Set: AxLook.TokFn(s, o, fd.K)})
        }
        for g in order
            h .= AxPanes.Group(s, g, groups[g], "lk" RegExReplace(StrLower(g), "[^a-z]"))
        h .= AxPanes.Group(s, "Your own CSS",
                 add({Id: "lp_css", L: "Rules", Kind: "multiline", Rows: 6, Get: (*) => o.Css,
                      Set: AxLook.PropFn(s, o, "Css")})
               . '<div class="axd-note">Plain CSS, laid over everything above. Write <b>body</b> for the '
               . 'window and the library&#39;s classes -- <b>.card</b>, <b>.btn</b>, <b>#sidebar</b> -- '
               . 'for its parts.</div>', "lkcss")
        h .= '<div class="axd-note"><span class="axd-hbtn" data-lkact="clear">Clear every change</span></div>'
        return h
    }
    static BaseOf(o) => o.HasOwnProp("Sheet") ? o.Sheet : o.Stylesheet
    static TokGet(o, key) => (*) => AxTheme.Get(o, key)
    static TokFn(s, o, key) => (v) => (AxTheme.Set(o, key, v), AxLook.Changed(s, o))
    static PropFn(s, o, prop) => (v) => (o.%prop% := v, AxLook.Changed(s, o))
    static BaseFn(s, o, *) => (v) => (o.HasOwnProp("Sheet") ? o.Sheet := v : o.Stylesheet := v, AxLook.Changed(s, o))
    ; One change: a theme of yours is saved, this design's canvas follows,
    ; and the window in the middle is drawn again.
    static Changed(s, o) {
        ; braced: a bare try as an if's body swallows the else
        if o.HasOwnProp("File") {
            try AxThemes.Save(s, o)
        } else
            s.AfterLookCanvas()
        AxLook.Paint(s)
    }

    ; ------------------------------------------------------------ actions
    static Act(s, act) {
        t := AxLook.Target(s)
        switch act {
        case "mode.dark", "mode.light":
            m := SubStr(act, 6)
            if (t.Kind = "mine") {
                t.Obj.Mode := m
                AxThemes.Save(s, t.Obj)
            } else if (t.Kind = "design") {
                s.Mark()
                s.P.W.Theme := m
                s.AfterLook()
                return
            } else
                s.LookMode := m
            return s.Reflect(false)
        case "copy":
            return AxLook.NewTheme(s, t.Sheet, "My " t.Name, t.Mode)
        case "new":
            base := ""
            for b in AxThemes.Builtins
                base .= (base = "" ? "" : "|") b[1] ":" b[2]
            r := AxForm.Show(s, {Title: "A new theme", Icon: "E790", Width: 460,
                Intro: "A theme starts as one of the built-in looks. Everything about it can be changed after.",
                Fields: [{Id: "name", L: "Called", Kind: "text", V: "My theme"},
                         {Id: "base", L: "Built on", Kind: "choice", V: "win11", Opts: base}],
                Buttons: ["Make it", "Cancel"],
                Check: (V) => Trim(V["name"]) = "" ? "It needs a name." : ""})
            if r.Ok
                AxLook.NewTheme(s, r.V["base"], Trim(r.V["name"]), s.LookMode)
            return
        case "save":
            W := s.P.W
            r := AxForm.Show(s, {Title: "Save it as a theme", Icon: "E790", Width: 460,
                Intro: "This window's look -- " AxThemes.Label(W.Stylesheet) " and its changes -- as a "
                     . "theme you can put on any design.",
                Fields: [{Id: "name", L: "Called", Kind: "text", V: W.Name " look"}],
                Buttons: ["Save it", "Cancel"],
                Check: (V) => Trim(V["name"]) = "" ? "It needs a name." : ""})
            if !r.Ok
                return
            th := {Name: Trim(r.V["name"]), File: "", Sheet: W.Stylesheet, Mode: t.Mode,
                   Accent: W.Accent, Look: W.Look, Css: W.Css}
            AxThemes.Save(s, th)
            s.LookSel := "u:" th.File
            s.Status("msg", "Saved " th.Name " -- it is under Yours.")
            return s.Reflect(false)
        case "use":
            s.Mark()
            for w in s.P.Wins {
                w.Stylesheet := t.Sheet
                w.Theme := t.Mode
                if (t.Kind = "mine")
                    w.Accent := t.Accent, w.Look := t.Obj.Look, w.Css := t.Obj.Css
                else
                    w.Look := "", w.Css := ""
            }
            s.AfterLook()
            s.Status("msg", "Every window wears " t.Name " now. Undo takes it off again.")
            return
        case "spread":
            s.Mark()
            W := s.P.W
            for w in s.P.Wins {
                if AxProject.Same(w, W)
                    continue
                w.Stylesheet := W.Stylesheet, w.Theme := W.Theme, w.Accent := W.Accent
                w.Look := W.Look, w.Css := W.Css
            }
            s.AfterLook()
            return s.Status("msg", "Every window has " W.Name "'s look.")
        case "rename":
            v := AxForm.Ask(s, "Rename the theme", "Called", t.Name, {Icon: "E8AC"})
            if (Trim(v) = "")
                return
            t.Obj.Name := Trim(v)
            AxThemes.Save(s, t.Obj)
            return s.Reflect(false)
        case "delete":
            r := AxForm.Show(s, {Title: "Delete " t.Name "?", Icon: "E74D", Width: 420,
                Intro: "The theme's file goes. A design wearing it keeps the look -- it was copied in.",
                Fields: [], Buttons: ["Delete it", "Keep it"], Danger: 1})
            if !r.Ok
                return
            try FileDelete(t.Obj.File)
            s.LookSel := "design"
            return s.Reflect(false)
        case "clear":
            if (t.Kind = "design")
                s.Mark()
            o := t.Obj
            o.Look := "", o.Css := "", o.Accent := ""
            AxLook.Changed(s, o)
            return s.Reflect(false)
        }
    }
    static NewTheme(s, base, name, mode) {
        th := {Name: name, File: "", Sheet: base, Mode: mode, Accent: "", Look: "", Css: ""}
        AxThemes.Save(s, th)
        s.LookSel := "u:" th.File
        s.Reflect(false)
        s.Status("msg", "Made " name ". Change anything on the right; it is saved as you go.")
        return th
    }

    ; ------------------------------------------------------------ the window
    ; Drawn in the page the way the canvas is: the sheet, the base rules every
    ; window has, the accent and the changes are read without being applied,
    ; and every rule is pointed at the preview's own box -- which wears the
    ; sheet's body classes, so each rule matches as it does in a real window.
    static Paint(s) {
        el := ""
        try el := s.El("axdSpec")
        if !IsObject(el)
            return
        t := AxLook.Target(s)
        css := ""
        try css := AxGui.ThemeCss(t.Sheet)
        if (t.Accent != "" && RegExMatch(t.Accent, "^#[0-9A-Fa-f]{6}$"))
            try css := AxSys.RecolourCss(css, t.Accent)
        base := ""
        try base := AxWindow.ReadLib("themes\base.css")
        o := t.Obj
        mine := IsObject(o) ? AxTheme.Css(o) : ""
        ; the accent the window will have: its own, or the look's default for the mode
        acc := AxLook.AccentCss(RegExMatch(t.Accent, "^#[0-9A-Fa-f]{6}$") ? t.Accent : s.DefaultAccentOf(t.Sheet, t.Mode))
        try {
            el.className := "theme-" t.Mode " sheet-" AxGui.SheetName(t.Sheet)
            el.style.backgroundColor := AxThemes.Back(t.Sheet, t.Mode)
            el.innerHTML := AxLook.Specimen()
            AxTags.ExpandIn(el)
            ; and, as on the canvas, what the studio's own look would bring in
            ; through its body classes put back (AxStudio.Unleak)
            ; the components' sheets too (an expander is one), under the theme
            comp := s.CompCanvasCss("#axdSpec")
            spec := s.ReadSheet(base "`n" css "`n" acc "`n" mine, "axdSpecRead", "#axdSpec")
            own := ""
            if (AxGui.SheetName(t.Sheet) != AxGui.SheetName(s.Stylesheet))
                try own := s.ReadSheet(AxGui.ThemeCss(s.Stylesheet), "axdSpecRead", "#axdSpec")
            s.SetExtraCss("axdSpecCss", AxStudio.Unleak(comp spec own, comp spec, "#axdSpec") comp spec)
            AxLook.ShowLooks(s, el, o)
        } catch as e
            s.WriteLog("Look preview: " e.Message)
    }
    ; A colour left to the look shows the look's colour, read off the window in
    ; the middle, instead of an empty hatch: the swatch and, faintly, its hex.
    static ShowLooks(s, spec, o) {
        static alias := Map("body", "", "#content", ".axd-content", "#sidebar", ".axd-sidebar",
                            "#titlebar", ".axd-titlebar", "#titleText", ".axd-titletext")
        for fd in AxTheme.Fields {
            if (fd.Kind != "color" || (IsObject(o) && AxTheme.Get(o, fd.K) != ""))
                continue
            sw := box := ""
            try sw := s.Doc.querySelector('[data-pick="lp_' fd.K '"]')
            try box := s.El("lp_" fd.K)
            if !IsObject(sw)
                continue
            sel := Trim(StrSplit(fd.Sel = "@inputs" ? AxTheme.Inputs : fd.Sel, ",")[1])
            if alias.Has(sel)
                sel := alias[sel]
            if (sel = ".btn")
                sel := ".btn:not(.accent)"                  ; the plain one, not Save
            el := ""
            try el := (sel = "") ? spec : spec.querySelector(sel)
            if !IsObject(el)
                continue
            cs := el.currentStyle
            v := ""
            try v := (fd.Prop = "color") ? cs.color : (fd.Prop = "border-color") ? cs.borderTopColor : cs.backgroundColor
            ; see-through is the window's colour showing; a wash is that colour
            ; with the wash laid on it
            hex := AxLook.Hex(v, AxLook.Hex(spec.currentStyle.backgroundColor))
            if (hex = "")
                continue
            try sw.style.background := hex
            try sw.className := "axd-pswatch"
            if IsObject(box)
                try box.placeholder := "from the look: " hex
        }
        if (IsObject(o) && !RegExMatch(o.Accent, "^#[0-9A-Fa-f]{6}$")) {
            try s.Doc.querySelector('[data-pick="lp_accent"]').style.background := s.DefaultAccentOf(AxLook.BaseOf(o), AxLook.Target(s).Mode)
            try s.Doc.querySelector('[data-pick="lp_accent"]').className := "axd-pswatch"
        }
    }
    ; A computed colour as #rrggbb, laid over `under` (#rrggbb) when it is
    ; partly or wholly see-through; "" when there is nothing to show.
    static Hex(v, under := "") {
        if RegExMatch(v, "i)^#[0-9a-f]{6}$")
            return StrLower(v)
        if RegExMatch(v, "i)^#([0-9a-f])([0-9a-f])([0-9a-f])$", &m)
            return StrLower("#" m[1] m[1] m[2] m[2] m[3] m[3])
        if (v = "transparent")
            v := "rgba(0, 0, 0, 0)"
        if !RegExMatch(v, "rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+))?", &m)
            return ""
        a := (m[4] = "") ? 1 : Number(m[4])
        rgb := [Number(m[1]), Number(m[2]), Number(m[3])]
        if (a < 1) {
            if !RegExMatch(under, "i)^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$", &u)
                return ""
            loop 3
                rgb[A_Index] := Round(rgb[A_Index] * a + Integer("0x" u[A_Index]) * (1 - a))
        }
        return Format("#{:02x}{:02x}{:02x}", rgb[1], rgb[2], rgb[3])
    }
    ; The accent, where the library puts it, for a window that is not a real
    ; one and so never has SetAccent called on it.
    static AccentCss(hex) {
        ; .accent twice: see AxStudio's canvas accent
        return ".btn.accent.accent{background:" hex ";border-color:" hex ";color:" (AxWindow._Luma(hex) > 0.45 ? "#000" : "#fff") "}"
             ; each selector carries its own class twice for the same reason:
             ; the studio's live sheet names these through a body class, and
             ; that beats a bare one
             . ".switch input:checked+.sw-track.sw-track{background:" hex ";border-color:" hex "}"
             . ".check input:checked+.box.box{background:" hex ";border-color:" hex "}"
             . ".radio input:checked+.ring.ring{border-color:" hex "}"
             . ".segmented .seg.active.active{background:" hex "}"
             . ".progress .bar.bar,.nav-item.active.active:before,.tab.active.active:after,"
             . ".dd-item.selected.selected:before,.list-item.selected.selected:before{background:" hex "}"
             . ".link.link,.hyperlink.hyperlink{color:" hex "}"
             . ".textbox input:focus{border-bottom-color:" hex "}"
    }
    ; A window's worth of everything a sheet styles.
    ; The frame by class, as the canvas draws it (the ids are the studio's own
    ; window's); the controls as the library expands them.
    static Specimen() {
        return '<div class="axd-titlebar"><span class="app-icon ico">&#xE737;</span>'
             . '<div class="axd-titletext">A window in this look</div>'
             . '<div class="winbtn ico">&#xE921;</div><div class="winbtn ico">&#xE922;</div>'
             . '<div class="winbtn ico">&#xE8BB;</div></div>'
             . '<div class="axd-shell"><div class="axd-sidebar">'
             . '<div class="nav-item active"><span class="ico">&#xE80F;</span>Overview</div>'
             . '<div class="nav-item"><span class="ico">&#xE8A5;</span>Data</div>'
             . '<div class="nav-item"><span class="ico">&#xE713;</span>Settings</div></div>'
             . '<div class="axd-content"><div class="page visible"><h1>Overview</h1>'
             . '<ax-infobar kind="info" title="Heads up">An info bar, for news that matters.</ax-infobar>'
             . '<ax-card title="Settings">'
             .   '<ax-row title="Start with Windows" desc="A switch in a setting row" icon="E7E8"><ax-switch checked></ax-switch></ax-row>'
             .   '<ax-row title="Theme" desc="A drop-down" icon="E790"><ax-dropdown options="dark:Dark,light:Light,system:System" value="dark" width="112"></ax-dropdown></ax-row>'
             . '</ax-card>'
             . '<ax-card title="Typing">'
             .   '<ax-text value="Some text"></ax-text><br>'
             .   '<ax-search placeholder="Search"></ax-search><br>'
             .   '<ax-number value="42"></ax-number>'
             . '</ax-card>'
             . '<ax-card title="Choosing">'
             .   '<ax-check checked>A check box</ax-check> <ax-check>Another</ax-check><br>'
             .   '<ax-radio options="a:One,b:Two,c:Three" value="a"></ax-radio><br>'
             .   '<ax-segmented options="d:Day,w:Week,m:Month" value="w"></ax-segmented><br>'
             .   '<ax-slider value="60"></ax-slider>'
             .   '<ax-progress value="45"></ax-progress>'
             . '</ax-card>'
             . '<p><ax-button kind="accent">Save</ax-button> <ax-button>Cancel</ax-button> '
             . '<ax-badge kind="accent">3</ax-badge> <ax-chip>A chip</ax-chip> <ax-link>A link</ax-link></p>'
             . '<ax-tabs><ax-tab label="First"><p>The first tab.</p></ax-tab><ax-tab label="Second"><p>The second.</p></ax-tab></ax-tabs>'
             . '<ax-list options="a:First item,b:Second item,c:Third item" value="b" height="96"></ax-list>'
             . '<ax-expander title="An expander" desc="Opens to show more" icon="E946"><p>Inside it.</p></ax-expander>'
             . '</div></div></div>'
    }
}
