#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Gen.ahk
#Include %A_LineFile%\..\AxStudio.Chrome.ahk

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
;  AxStudio.Pre.ahk -- prerendering.
;
;  Where the time goes when an AxGui window opens: creating the Trident control
;  and navigating to it, writing the page in, and then AxTags.Expand -- which
;  walks the document doing
;
;      el.outerHTML := AxTags.Render(tag, el)
;
;  once per custom tag. Each of those is a reparse of that subtree, so fifty
;  controls is fifty reparses before anything is on screen.
;
;  Measured, on the Showcase example -- 187 tags, 64-bit 2.0.19:
;
;      AxGui.Show                      422.6 ms
;        AxWindow.__New                377.9
;          AxWindow._OnDocComplete     263.7
;            AxTags.Expand             144.3      <- of which
;              AxTags.Render            41.8         187 calls
;              (the outerHTML writes)  102.6
;
;  A third of the whole window opening, and all of it work the studio has
;  already done: the canvas IS the expanded markup. That is what this removes.
;
;  So: build the window's body at export time, expand it here, and write it
;  into the script as a literal. AxGui.Prebuilt takes it and Expand then finds
;  nothing to do.
;
;  Two things this deliberately does NOT do.
;
;  It does not stop the Add* calls running. They are string concatenation --
;  microseconds -- and they are what registers your controls, queues the
;  component instances and wires the events. Skipping them would mean
;  reimplementing all of that in the generated file, which is a great deal of
;  new surface to save nothing measurable.
;
;  It does not expand in the studio's own document. AxTags.Expand ends by
;  looking for #sidebar and #content and wrapping them in a #shell -- and the
;  studio has a #content of its own. Run against the live document it would
;  find the studio's and rearrange the studio. ExpandIn is scoped to one
;  element, which is why it exists.
; =============================================================================
class AxPre {
    ; The <body> of one window, fully expanded, exactly as the finished script
    ; will hold it. "" when it cannot be built, which is not an error -- it
    ; means the export writes an ordinary script.
    static Body(s, project, w) {
        html := ""
        try html := AxPre.Assemble(project, w)
        if (Trim(html) = "")
            return ""
        try return AxPre.Expand(s, html)
        return ""
    }
    ; The same builders the export writes calls to, run here instead, with the
    ; ids the export uses rather than the canvas's own.
    static Assemble(project, w) {
        o := {Nav: w.Nav ? true : false}
        if (w.Headings != "")
            o.Headings := w.Headings
        g := AxDesignGui(o)
        ; the bars are declared, not built: <ax-menubar> and <ax-status> are
        ; what the markup carries, and the items are bound when the DOM exists
        if (Trim(w.Menus) != "" || Trim(w.MenuBar) != "")
            g.AddMenuBar([])
        if (Trim(w.Status) != "" || Trim(w.StatusBar) != "")
            g.AddStatusBar([])
        pages := []
        for k in w.Root.Kids
            if (k.Type = "Page")
                pages.Push(k)
        ; anything above the pages belongs to the root, in the order AxGui
        ; renders it
        loose := []
        for k in w.Root.Kids
            if (k.Type != "Page")
                loose.Push(k)
        root := g._root
        if loose.Length
            AxGen.Emit(g, loose, (*) => g.Use(root), false)
        for p in pages {
            c := g.AddPage(p.Name, p.Prop("title", p.Name), p.Prop("icon", ""))
            AxGen.Emit(g, p.Kids, (*) => g.Use(c), false)
        }
        return g.BodyHtml()
    }
    ; Expanded in a corner of the studio's own page rather than in a detached
    ; node: setting innerHTML on a live element is the path Trident is happiest
    ; with, and it is the one the canvas already uses. ExpandIn keeps the work
    ; inside that corner.
    static Expand(s, html) {
        box := s.El("axdPrerender")
        if !IsObject(box)
            return ""
        out := ""
        try {
            box.innerHTML := html
            AxTags.ExpandIn(box)
            out := box.innerHTML
        }
        try box.innerHTML := ""
        return out
    }

    ; ------------------------------------------------------- into the script
    ; A continuation section, because the markup is full of quotes and a
    ; quoted literal would be unreadable and easy to get wrong. Three options
    ; hold it together, and all three matter:
    ;
    ;   Join    with nothing after it, so the lines rejoin with NO separator.
    ;           Without this every line break would put a newline into the
    ;           markup -- insignificant whitespace between two tags, a visible
    ;           blank line inside anything the stylesheet sets to pre-wrap.
    ;           With it the wrapping is cosmetic and cannot change a thing.
    ;   `       the backtick option, so a backtick in the markup stays one
    ;           rather than escaping whatever follows it.
    ;   and a line may never START with ) -- that would end the section early.
    static Literal(html, indent := "") {
        nl := "`n"
        s := indent Chr(34) nl indent "(Join ``" nl
        for line in AxPre.Wrap(html)
            s .= (SubStr(line, 1, 1) = ")" ? " " : "") line nl
        return s indent ")" Chr(34)
    }
    ; Broken after a > , only for the look of the file: Join means the breaks
    ; are not in the string at all. One 40KB line would work and be unreadable.
    static Wrap(html, width := 110) {
        out := [], cur := ""
        for part in StrSplit(StrReplace(String(html), "`r", ""), ">") {
            if (part = "")
                continue
            cur .= part ">"
            if (StrLen(cur) >= width) {
                out.Push(cur)
                cur := ""
            }
        }
        if (cur != "")
            out.Push(cur)
        if !out.Length
            out.Push("")
        return out
    }
    ; The region the generated script carries.
    static Region(s, project) {
        main := project.Main()
        body := AxPre.Body(s, project, main)
        if (body = "")
            return ""
        nl := "`n"
        return "; The window's markup, built when this was exported and already"  nl
             . "; expanded -- so opening it is one parse rather than one per control."  nl
             . "; Re-export after changing the design: nothing checks that this still" nl
             . "; matches it, and nothing can. Turn it off under File > Compile."  nl
             . "g.Prebuilt("  nl
             . AxPre.Literal(body, "    ") ")"  nl
    }
    ; What it costs and what it saves, for the compile form. Counting the tags
    ; is counting the reparses that will not happen.
    static Report(s, project) {
        body := AxPre.Body(s, project, project.Main())
        if (body = "")
            return "Nothing to prerender yet."
        raw := ""
        try raw := AxPre.Assemble(project, project.Main())
        n := 0
        for tag in AxTags.Order()
            n += AxPre.Count(raw, "<" tag)
        return Round(StrLen(body) / 1024, 1) " KB of markup goes into the script, and "
             . n " tag" (n = 1 ? "" : "s") " will not have to be expanded when it opens."
    }
    static Count(text, needle) {
        n := 0, pos := 1
        while (pos := InStr(text, needle, false, pos)) {
            n++
            pos += StrLen(needle)
        }
        return n
    }
}
