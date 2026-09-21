#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk

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
;  AxStudio.Form.ahk -- one modal, with as many fields as the question needs.
;
;  Everything the studio used to ask by chaining menus and one-line prompts is
;  asked here instead. "3 x 2 Button", typed into a text box and pulled apart
;  with a regex, was not a question -- it was a syntax you had to know before
;  you could answer, and every one of those wizards was quietly broken because
;  nobody could tell the difference between it working and it doing nothing.
;
;  Three things make it worth having:
;
;  1. It blocks, like AxWindow.Dialog does, so the calling code reads top to
;     bottom: ask, then act. The message loop keeps running while it waits, so
;     the fields are live the whole time.
;
;  2. Every field is one entry in a list -- {Id, L, Kind, V} -- and the same
;     list renders the markup and reads the answers back. A field cannot end up
;     shown but not read.
;
;  3. Check and Preview run on every keystroke. Check says why the button is
;     greyed out; Preview shows the line the form is about to write, before it
;     writes it. Between them there is nothing left to guess at.
; =============================================================================
class AxForm {
    static Cur := ""                      ; the form on screen, or ""

    ; The overlay markup. Injected once, at the end of the shell.
    static Markup() {
        return '<div id="axdFormOv" class="axd-formov" style="display:none">'
            .  '<div class="axd-form" id="axdForm">'
            .    '<div class="axd-fhead">'
            .      '<span class="axd-ficon"><span class="ico" id="axdFormIcon"></span></span>'
            .      '<span class="axd-ftitle" id="axdFormTitle"></span>'
            .      '<span class="axd-fx ico" id="axdFormX">&#xE8BB;</span>'
            .    '</div>'
            .    '<div class="axd-fintro" id="axdFormIntro"></div>'
            .    '<div class="axd-fbody" id="axdFormBody"></div>'
            .    '<div class="axd-fprevwrap" id="axdFormPrevWrap" style="display:none">'
            .      '<span class="axd-fprevh">It writes</span>'
            .      '<div class="axd-fprev" id="axdFormPrev"></div></div>'
            .    '<div class="axd-ffoot">'
            .      '<span class="axd-ferr" id="axdFormErr"></span>'
            .      '<span id="axdFormBtns"></span>'
            .    '</div>'
            .  '</div></div>'
    }
    ; Hooks that live for the life of the studio: the buttons, the close cross
    ; and the card clicks. Per-field hooks are added and taken away with the
    ; form itself.
    static Wire(s) {
        s.On("click", "axdFormBtns", (el, ev) => AxForm.BtnClick(s, ev))
        s.On("click", "axdFormX", (*) => AxForm.End(s, 0))
        s.On("click", "axdFormBody", (el, ev) => AxForm.BodyClick(s, ev))
    }

    ; ---------------------------------------------------------------- show
    ; spec: Title, Icon, Intro, Width, Fields, Buttons, Ok, Cancel, Danger,
    ;       Check(V), Preview(V), Focus
    ; returns {Ok, Btn, Label, V}   V is a Map of Id -> value
    ; The body scrolls only when it has to. A box that can scroll is also a box
    ; that clips, and a dropdown's list opens inside it -- so every list in
    ; every dialog was cut off at the dialog's edge, with a scrollbar beside
    ; it. Most forms fit; the few that do not scroll, as before.
    static FitBody(s) {
        try {
            b := s.El("axdFormBody")
            AxWindow._SetClass(b, "axd-fscroll", false)
            AxWindow._SetClass(b, "axd-fscroll", b.scrollHeight > s.Doc.documentElement.clientHeight * 0.68)
        }
    }
    static Show(s, spec) {
        O := (n, d) => spec.HasOwnProp(n) ? spec.%n% : d
        ; A form that does not open still has to answer for every field it
        ; would have had. It used to hand back an empty Map, and every caller
        ; reads its answers straight -- r.V["ask"] -- so "a dialog is already
        ; open" came out as "Item has no value" from somewhere else entirely.
        ; The answers are what the form was going to show.
        blank := {Ok: false, Btn: 0, Label: "", V: AxForm.Defaults(O("Fields", [])), Go: ""}
        if !IsObject(s.Doc)
            return blank
        ; One at a time -- a second form would orphan the first. Said out loud,
        ; because a dialog that does not open is a button that does nothing,
        ; and that is the hardest kind of fault for anyone to report.
        if (AxForm.Cur != "") {
            try s.Problem("A dialog is already open, so "
                . (spec.HasOwnProp("Title") ? spec.Title : "this one")
                . " did not open.")
            return blank
        }
        fields := O("Fields", [])
        buttons := O("Buttons", [O("Ok", "OK"), O("Cancel", "Cancel")])
        st := {Done: false, Btn: 0, Fields: fields, Buttons: buttons,
               Cancel: O("CancelIndex", buttons.Length),
               Check: O("Check", ""), Preview: O("Preview", ""),
               Danger: O("Danger", 0), Filling: false, S: s, Go: ""}
        AxForm.Cur := st
        ; Guarded from here to the teardown. A form that raised on the way up
        ; used to leave Cur set, and Show returns blank the moment Cur is set --
        ; so one throw, once, silently killed every dialog in the studio for
        ; the rest of the session, File > Compile included.
        try {

            try s.CloseContextMenu()
            s.Html("axdFormTitle", AxTags.E(O("Title", "")))
            ico := O("Icon", "")
            try {
                s.Html("axdFormIcon", ico != "" ? "&#x" ico ";" : "")
                s.El("axdFormIcon").parentElement.style.display := (ico != "" ? "inline-block" : "none")
            }
            intro := O("Intro", "")
            try {
                s.Html("axdFormIntro", AxTags.E(intro))
                s.El("axdFormIntro").style.display := (intro != "" ? "block" : "none")
            }
            try s.El("axdForm").style.width := O("Width", 460) "px"

            body := ""
            seen := Map()
            seen.CaseSense := false
            for f in fields {
                if (f.HasOwnProp("Id") && f.Id != "") {
                    ; The second one is left out rather than drawn: it could
                    ; never be shown, hidden or read anyway, and drawing it
                    ; put two boxes on screen with only the first obeying
                    ; When -- which is what "with" and "give it" both showing
                    ; on the rule dialog was. Said out loud, not swallowed.
                    if seen.Has(f.Id) {
                        try s.Problem('Two fields in "' O("Title", "this form") '" are both called "'
                            . f.Id '" -- only the first is shown.')
                        continue
                    }
                    seen[f.Id] := true
                }
                body .= AxForm.Row(f)
            }
            s.Html("axdFormBody", body)

            btns := ""
            for i, b in buttons
                btns .= '<div class="axd-fbtn' (i = 1 ? " primary" : "")
                     .  (i = st.Danger ? " danger" : "") '" data-fbtn="' i '">' AxTags.E(b) '</div>'
            s.Html("axdFormBtns", btns)

            try AxTags.Expand(s.Doc)
            try s._MakeFocusable()
            AxForm.Hook(s, fields, true)
            try s.El("axdFormOv").style.display := "block"
            AxForm.Sync(s)
            AxForm.FitBody(s)

            ; the first field that can take a caret, so the form is typeable the
            ; moment it appears
            want := O("Focus", "")
            if (want = "")
                for f in fields
                    if AxForm.Typeable(f) {
                        want := f.Id
                        break
                    }
            if (want != "")
                try s.Focus(AxForm.Eid(want))

            while (!st.Done && !s.Closing)
                Sleep 20

        } catch as e {
            AxForm.Cur := ""
            try AxForm.Hook(s, fields, false)
            try s.El("axdFormOv").style.display := "none"
            try s.Html("axdFormBody", "")
            throw e
        }
        ; Cur is cleared FIRST and everything after it is guarded: a teardown
        ; that raised would otherwise leave it set, with the same result.
        AxForm.Cur := ""
        v := Map()
        try AxForm.Hook(s, fields, false)
        try v := AxForm.Read(s, fields)
        try s.El("axdFormOv").style.display := "none"
        try s.Html("axdFormBody", "")
        i := st.Btn
        ok := (i >= 1 && i != st.Cancel)
        return {Ok: ok, Btn: i, Label: (i >= 1 && i <= buttons.Length) ? buttons[i] : "", V: v, Go: st.Go}
    }

    ; ------------------------------------------------------- the shortcuts
    ; One question, one answer. This is Prompt() with room for a hint, a
    ; placeholder and a reason the answer is not acceptable yet.
    static Ask(s, title, label, value := "", opts := "") {
        O := (n, d) => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        f := {Id: "a", L: label, Kind: O("Kind", "text"), V: value,
              Hint: O("Hint", ""), Wide: O("Wide", false)}
        if (O("Opts", "") != "")
            f.Opts := opts.Opts
        r := AxForm.Show(s, {Title: title, Icon: O("Icon", "E70F"), Intro: O("Intro", ""),
                             Width: O("Width", 420), Fields: [f],
                             Buttons: [O("Ok", "OK"), "Cancel"], Check: O("Check", "")})
        return r.Ok ? r.V["a"] : ""
    }
    ; One of a list, as cards rather than a four-deep menu. items are
    ; {V, L, Desc, Icon}; returns the chosen V, or "".
    static Choose(s, title, intro, items, opts := "") {
        O := (n, d) => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        if !items.Length
            return ""
        r := AxForm.Show(s, {Title: title, Icon: O("Icon", "E8FD"), Intro: intro,
            Width: O("Width", 470),
            Fields: [{Id: "c", Kind: "pick", L: "", V: O("V", items[1].V), Items: items,
                      Scroll: O("Scroll", items.Length > 8)}],
            Buttons: [O("Ok", "Choose"), "Cancel"],
            Check: (V) => (V["c"] = "") ? "Choose one." : ""})
        return r.Ok ? r.V["c"] : ""
    }

    ; ---------------------------------------------------------- the fields
    ; The element id a field gets in the page. Prefixed, because the canvas
    ; names its elements after the controls in the design, and a field called
    ; "name" would otherwise be the second element in the document called that.
    static Eid(id) => "axf_" id
    static Rid(id) => "axfr_" id

    static Wide(kind) {
        static w := "|multiline|code|pick|note|heading|divider|list|flag|radio|rows|tabs|panel|acts|"
        return InStr(w, "|" kind "|") > 0
    }
    ; The tabs field of the form on screen, or "". A form with tabs shows only
    ; the fields of the tab that is open -- which is what turns a wizard with
    ; twenty questions from a scroll into a tool window.
    static TabsId(fields) {
        for f in fields
            if (f.HasOwnProp("Kind") && f.Kind = "tabs" && f.HasOwnProp("Id"))
                return f.Id
        return ""
    }
    static Typeable(f) {
        static t := "|text|multiline|code|num|search|color|"
        return InStr(t, "|" f.Kind "|") > 0
    }
    static Row(fld) {
        ; NOT a closure called F over a parameter called f. AutoHotkey names are
        ; case-insensitive, so F and f are ONE variable: assigning the closure
        ; overwrote the field with the closure itself, and a Func has
        ; HasOwnProp too -- so every lookup quietly returned its default and
        ; every field rendered as an empty text box with no id and no label.
        Fv := (n, d := "") => AxForm.It(fld, n, d)
        id := AxForm.Eid(Fv("Id")), row := AxForm.Rid(Fv("Id"))
        kind := Fv("Kind", "text"), v := String(Fv("V", ""))
        hint := Fv("Hint"), body := ""
        E := (x) => AxTags.E(x)
        switch kind {
        case "heading":
            return '<div class="axd-fsec" id="' row '">' E(Fv("L")) '</div>'
        case "note":
            ; Mono for anything laid out in columns with spaces -- a key list
            ; in a proportional font is not a list, it is a paragraph.
            ; A note says what it was given: L for one that never changes,
            ; V for one that follows another answer (Seed) -- what the event
            ; picked above hands its rule, for instance.
            nt := (String(v) != "") ? v : Fv("L")
            return '<div class="axd-fnote' (Fv("Mono") ? ' axd-fmono' : '') '" id="' row '">'
                 . (Fv("Html") ? nt : E(nt)) '</div>'
        case "divider":
            return '<div class="axd-fdiv" id="' row '"></div>'
        case "text":
            body := '<ax-text id="' id '" value="' E(v) '" placeholder="' E(Fv("Ph")) '"></ax-text>'
        case "search":
            body := '<ax-search id="' id '" value="' E(v) '" placeholder="' E(Fv("Ph")) '"></ax-search>'
        case "num":
            body := '<ax-text id="' id '" value="' E(v) '" placeholder="' E(Fv("Ph", "auto")) '"></ax-text>'
        case "int":
            body := '<ax-number id="' id '" value="' (v = "" ? "0" : E(v)) '" min="' E(Fv("Min"))
                 .  '" max="' E(Fv("Max")) '" step="' E(Fv("Step", 1)) '"'
                 .  (Fv("Suffix") != "" ? ' suffix="' E(Fv("Suffix")) '"' : "") '></ax-number>'
        case "multiline", "code":
            body := '<ax-textarea id="' id '" class="' (kind = "code" ? "axd-fcode" : "")
                 .  '" rows="' E(Fv("Rows", kind = "code" ? 7 : 4))
                 .  '" placeholder="' E(Fv("Ph")) '">' E(v) '</ax-textarea>'
        case "choice":
            body := '<ax-dropdown id="' id '" options="' E(Fv("Opts")) '" value="' E(v) '"></ax-dropdown>'
        case "seg":
            body := '<ax-segmented id="' id '" options="' E(Fv("Opts")) '" value="' E(v) '"></ax-segmented>'
        case "radio":
            body := '<ax-radio id="' id '" options="' E(Fv("Opts")) '" value="' E(v) '"'
                 .  (Fv("Inline", true) ? " inline" : "") '></ax-radio>'
        case "flag":
            return '<div class="axd-f axd-f-wide axd-f-flag" id="' row '">'
                 . '<ax-check id="' id '"' (v && v != "0" ? " checked" : "") '>' E(Fv("L")) '</ax-check>'
                 . (hint != "" ? '<div class="axd-fhint axd-fhint-in">' E(hint) '</div>' : "") '</div>'
        case "hotkey":
            body := '<ax-hotkey id="' id '" value="' E(v) '"></ax-hotkey>'
        case "color":
            body := '<ax-text id="' id '" value="' E(v) '" placeholder="#0078d4"></ax-text>'
                 .  '<span class="axd-fswatch" data-pick="' id '" data-tip="Pick a colour"></span>'
        case "list":
            body := '<ax-list id="' id '" options="' E(Fv("Opts")) '" value="' E(v) '" multi="check"'
                 .  ' height="' E(Fv("Height", 150)) '"></ax-list>'
        case "static":
            body := '<div class="axd-fstatic">' E(v) '</div>'
        case "pick":
            body := AxForm.Pick(fld, id, v)
        case "tabs":
            ; A strip, not a dropdown: every page is named and one click away.
            h := '<div class="axd-ftabs" id="' id '" data-value="' E(v) '">'
            for it in Fv("Items", []) {
                iv := AxForm.It(it, "V"), ic := AxForm.It(it, "Icon")
                h .= '<div class="axd-ftab' (iv = v ? " on" : "") '" data-ftab="' id '" data-fval="' E(iv) '">'
                  .  (ic != "" ? '<span class="ico">&#x' ic ';</span>' : "")
                  .  E(AxForm.It(it, "L")) '</div>'
            }
            return h '</div>'
        case "acts":
            ; Buttons that do something to the form itself -- look it up, paste
            ; a signature, try it -- rather than closing it.
            h := '<div class="axd-facts" id="' id '">'
            if (Fv("L") != "")
                h .= '<span class="axd-factlab">' E(Fv("L")) '</span>'
            for it in Fv("Items", []) {
                ic := AxForm.It(it, "Icon")
                h .= '<span class="axd-fact' (AxForm.It(it, "Go") ? " axd-go" : "") '" data-fact="' id
                  .  '" data-fval="' E(AxForm.It(it, "V")) '"'
                  .  (AxForm.It(it, "Tip") != "" ? ' title="' E(AxForm.It(it, "Tip")) '"' : "") '>'
                  .  (ic != "" ? '<span class="ico">&#x' ic ';</span>' : "") E(AxForm.It(it, "L")) '</span>'
            }
            h .= '</div>'
            return '<div class="axd-f axd-f-wide axd-f-acts" id="' row '">' h
                 . (hint != "" ? '<div class="axd-fhint">' E(hint) '</div>' : "") '</div>'
        case "panel":
            ; Somewhere for an answer to land: what a lookup found, what a try
            ; gave back. Written by the caller with AxForm.Panel, so nothing
            ; slow runs on a keystroke.
            return '<div class="axd-f axd-f-wide axd-f-panel" id="' row '"'
                 . (v = "" && !Fv("Keep") ? ' style="display:none"' : "") '>'
                 . (Fv("L") != "" ? '<label class="axd-flab">' E(Fv("L")) '</label>' : "")
                 . '<div class="axd-fpanel" id="' id '">' v '</div></div>'
        case "rows":
            body := AxForm.Rows(fld, id, v)
        default:
            body := '<ax-text id="' id '" value="' E(v) '"></ax-text>'
        }
        wide := AxForm.Wide(kind) || Fv("Wide", false)
        ; A dropdown holding "is clicked" does not need to be as wide as the
        ; dialog. W is what the control itself gets; Inline puts the field on
        ; the same line as the one before it, which is what turns four boxes
        ; stacked down the page into a sentence you can read across.
        wantW := Fv("W", "")
        inline := Fv("Inline", false)
        ; The class matters: a check box and a radio ARE labels, so a rule
        ; written as ".axd-f > label" catches the control itself and turns a
        ; 20px tick box into a 2px sliver.
        lbl := (Fv("L") != "") ? '<label class="axd-flab" for="' id '">' E(Fv("L")) '</label>' : ""
        return '<div class="axd-f' (wide ? " axd-f-wide" : "") (inline ? " axd-f-inline" : "")
             . ' axd-f-' kind '" id="' row '">'
             . lbl '<div class="axd-fctl"' (wantW != "" ? ' style="width:' wantW '"' : "") '>' body
             . (hint != "" ? '<div class="axd-fhint">' E(hint) '</div>' : "")
             . '</div></div>'
    }
    ; ------------------------------------------------------- a list of rows
    ; A question with as many answers as it needs: the parameters a method
    ; takes, the columns of a table, the headers of a request. Every wizard
    ; that wanted one of these asked for "name:type, name:type" in a text box
    ; instead -- a syntax you had to know before you could answer, which is
    ; the very thing this file was written to stop.
    ;
    ; The value is one row per line, the cells of a row joined by Sep.
    static RowVals(f) {
        out := []
        for line in StrSplit(StrReplace(String(AxForm.It(f, "V", "")), "`r"), "`n")
            if (Trim(line) != "")
                out.Push(StrSplit(line, AxForm.It(f, "Sep", "|")))
        return out
    }
    static Cell(row, i) => (i <= row.Length) ? row[i] : ""
    static Rows(f, id, v) {
        cols := AxForm.It(f, "Cols", [])
        rows := AxForm.RowVals(f)
        min := AxForm.It(f, "Min", 0)
        while (rows.Length < min)
            rows.Push([])
        E := (x) => AxTags.E(x)
        h := '<div class="axd-frows" id="' id '" data-rows="' rows.Length '">'
        if (rows.Length && AxForm.It(f, "Heads", true)) {
            h .= '<div class="axd-frhead">'
            for c in cols
                h .= '<span style="width:' AxForm.It(c, "W", "40%") '">' E(AxForm.It(c, "L")) '</span>'
            h .= '</div>'
        }
        for ri, row in rows {
            h .= '<div class="axd-frow">'
            for ci, c in cols {
                cid := id "_r" ri "_" AxForm.It(c, "Id", ci)
                cv := AxForm.Cell(row, ci)
                h .= '<span class="axd-frcell" style="width:' AxForm.It(c, "W", "40%") '">'
                if (AxForm.It(c, "Kind") = "label")
                    h .= '<span class="axd-frlab" id="' cid '">' E(cv) '</span>'
                else if (AxForm.It(c, "Kind", "text") = "choice")
                    h .= '<ax-dropdown id="' cid '" options="' E(AxForm.It(c, "Opts")) '" value="' E(cv) '"></ax-dropdown>'
                else if (AxForm.It(c, "Kind") = "flag")
                    h .= '<ax-check id="' cid '"' (cv && cv != "0" ? " checked" : "") '></ax-check>'
                else
                    h .= '<ax-text id="' cid '" value="' E(cv) '" placeholder="' E(AxForm.It(c, "Ph")) '"></ax-text>'
                h .= '</span>'
            }
            h .= '<span class="axd-frx ico" data-frow="up|' id '|' ri '" title="Move it up">&#xE70E;</span>'
              .  '<span class="axd-frx ico" data-frow="del|' id '|' ri '" title="Remove this one">&#xE711;</span></div>'
        }
        if !rows.Length
            h .= '<div class="axd-frempty">' E(AxForm.It(f, "Empty", "None.")) '</div>'
        h .= '<span class="axd-fact" data-frow="add|' id '|0">&#xE710; ' E(AxForm.It(f, "AddLabel", "Add one")) '</span>'
        return h '</div>'
    }
    ; What the rows hold now, straight from the page.
    static ReadRows(s, f) {
        id := AxForm.Eid(f.Id)
        n := 0
        try n := Integer(s.Attr(id, "data-rows"))
        cols := AxForm.It(f, "Cols", []), sep := AxForm.It(f, "Sep", "|")
        out := ""
        loop n {
            ri := A_Index, line := "", any := false
            for ci, c in cols {
                cid := id "_r" ri "_" AxForm.It(c, "Id", ci)
                cv := ""
                try cv := (AxForm.It(c, "Kind") = "label") ? s.El(cid).innerText
                        : (AxForm.It(c, "Kind", "text") = "text") ? s.El(cid).value : s.Value(cid)
                cv := StrReplace(StrReplace(String(cv), sep, " "), "`n", " ")
                if (Trim(cv) != "")
                    any := true
                line .= (ci = 1 ? "" : sep) cv
            }
            if any
                out .= (out = "" ? "" : "`n") line
        }
        return out
    }

    ; The cards. A radio group with room to say what each choice means, which
    ; is the difference between choosing and guessing.
    static Pick(f, id, v) {
        items := f.HasOwnProp("Items") ? f.Items : []
        scroll := f.HasOwnProp("Scroll") && f.Scroll
        tiles := f.HasOwnProp("Tiles") && f.Tiles          ; many short choices, three to a row
        icons := f.HasOwnProp("Icons") && f.Icons          ; pictures: a dense grid, the picture over its name
        h := '<div class="axd-pick' (scroll ? " axd-pickscroll" : "") (tiles ? " axd-picktiles" : "") (icons ? " axd-pickicons" : "") '" id="' id '" data-value="'
           . AxTags.E(v) '">'
        ; No lambda over `it`: a closure in AutoHotkey v2 does not get a for
        ; loop's own control variable, and one written here would read fine
        ; today and stop working the moment it was called a line later.
        for it in items {
            iv := AxForm.It(it, "V"), ic := AxForm.It(it, "Icon"), im := AxForm.It(it, "Img")
            h .= '<div class="axd-pickit' (iv = v ? " on" : "") '" data-fpick="' id
              .  '" data-fval="' AxTags.E(iv) '">'
              .  (im != "" ? '<img class="axd-pickimg" alt="" src="' AxTags.E(im) '">'
                 : ic != "" ? '<span class="ico">&#x' ic ';</span>' : "")
              .  '<span class="axd-picklab">' AxTags.E(AxForm.It(it, "L")) '</span>'
              .  (AxForm.It(it, "Desc") != ""
                  ? '<span class="axd-pickdesc">' AxTags.E(AxForm.It(it, "Desc")) '</span>' : "")
              .  '</div>'
        }
        return h '</div>'
    }
    static It(o, name, d := "") => o.HasOwnProp(name) ? o.%name% : d

    ; ------------------------------------------------------------ reading
    static Plain(kind) {
        static p := "|text|multiline|code|num|search|color|"
        return InStr(p, "|" kind "|") > 0
    }
    static One(s, f) {
        kind := f.HasOwnProp("Kind") ? f.Kind : "text"
        if (kind = "heading" || kind = "note" || kind = "divider" || kind = "acts" || kind = "panel")
            return ""
        if (kind = "rows") {
            try return AxForm.ReadRows(s, f)
            return f.HasOwnProp("V") ? f.V : ""
        }
        try {
            if (kind = "pick" || kind = "tabs")
                return s.Attr(AxForm.Eid(f.Id), "data-value")
            if (kind = "static")
                return f.HasOwnProp("V") ? f.V : ""
            if AxForm.Plain(kind)
                return s.El(AxForm.Eid(f.Id)).value
            v := s.Value(AxForm.Eid(f.Id))
            return (v is Array) ? AxForm.Join(v, "|") : v
        }
        return f.HasOwnProp("V") ? f.V : ""
    }
    ; What a form would hold before anyone touched it.
    static Defaults(fields) {
        m := Map()
        for f in fields
            if f.HasOwnProp("Id")
                m[f.Id] := f.HasOwnProp("V") ? f.V : ""
        return m
    }
    static Read(s, fields) {
        m := Map()
        for f in fields
            if f.HasOwnProp("Id")
                m[f.Id] := AxForm.One(s, f)
        return m
    }
    static Join(arr, sep) {
        out := ""
        for x in arr
            out .= (out = "" ? "" : sep) x
        return out
    }

    ; ------------------------------------------------------------- events
    ; Per-field hooks, on while the form is up and off the moment it closes.
    ; A stale hook would fire against a form that is no longer there.
    static Hook(s, fields, on) {
        for f in fields {
            if !f.HasOwnProp("Id")
                continue
            kind := f.HasOwnProp("Kind") ? f.Kind : "text"
            if (kind = "heading" || kind = "note" || kind = "divider" || kind = "static"
                || kind = "acts" || kind = "panel" || kind = "tabs")
                continue
            eid := AxForm.Eid(f.Id)
            if (kind = "rows") {
                AxForm.HookRows(s, f, on)
                continue
            }
            if !on {
                s.Off("keyup", eid), s.Off("change", eid)
                s.OffValue(eid)
                continue
            }
            if AxForm.Plain(kind) {
                s.On("keyup", eid, (*) => AxForm.Sync(s))
                s.On("change", eid, (*) => AxForm.Sync(s))
            } else
                s.OnValue(eid, (*) => AxForm.Sync(s))
        }
    }
    ; Every cell of every row, one at a time: they come and go with the rows.
    static HookRows(s, f, on) {
        id := AxForm.Eid(f.Id)
        n := 0
        try n := Integer(s.Attr(id, "data-rows"))
        cols := AxForm.It(f, "Cols", [])
        loop n {
            ri := A_Index
            for ci, c in cols {
                cid := id "_r" ri "_" AxForm.It(c, "Id", ci)
                if !on {
                    s.Off("keyup", cid), s.Off("change", cid), s.OffValue(cid)
                    continue
                }
                if (AxForm.It(c, "Kind") = "label")
                    continue
                if (AxForm.It(c, "Kind", "text") = "text") {
                    s.On("keyup", cid, (*) => AxForm.Sync(s))
                    s.On("change", cid, (*) => AxForm.Sync(s))
                } else
                    s.OnValue(cid, (*) => AxForm.Sync(s))
            }
        }
    }
    ; One field drawn again where it stands, with its hooks renewed. Used by
    ; the rows editor and by anything that fills a field from outside.
    static Again(s, f) {
        if !AxForm.Cur
            return
        AxForm.Hook(s, [f], false)
        try {
            s.El(AxForm.Rid(f.Id)).outerHTML := AxForm.Row(f)
            AxTags.Expand(s.Doc)
            s._MakeFocusable()
        }
        AxForm.Hook(s, [f], true)
        AxForm.FitBody(s)
    }
    static Field(st, id) {
        if !IsObject(st)
            return ""
        for f in st.Fields
            if (f.HasOwnProp("Id") && f.Id = id)
                return f
        return ""
    }
    ; Write a value into a field from outside -- what a lookup found, what a
    ; pasted signature says. The one way anything but the user changes a form.
    static Put(s, id, value) {
        st := AxForm.Cur
        if !st
            return
        f := AxForm.Field(st, id)
        if !IsObject(f)
            return
        kind := f.HasOwnProp("Kind") ? f.Kind : "text"
        f.V := value
        if (kind = "rows" || kind = "pick" || kind = "tabs" || kind = "panel")
            return AxForm.Again(s, f)
        try {
            if AxForm.Plain(kind)
                s.El(AxForm.Eid(id)).value := value
            else
                s.Value(AxForm.Eid(id), value)
            return
        }
        AxForm.Again(s, f)
    }
    ; An answer into a panel: shown when there is one, gone when there is not.
    static Panel(s, id, html) {
        st := AxForm.Cur
        if !st
            return
        f := AxForm.Field(st, id)
        if IsObject(f)
            f.V := html
        try {
            s.Html(AxForm.Eid(id), html)
            s.El(AxForm.Rid(id)).style.display := (html != "" ? "block" : "none")
        }
        AxForm.FitBody(s)
    }
    static BodyClick(s, ev) {
        if !AxForm.Cur
            return
        go := s.UpAttr(ev.srcElement, "data-fgo")
        if (go != "") {
            AxForm.Cur.Go := go
            return AxForm.End(s, 0)
        }
        ; a tab strip: the fields of the other pages go, the ones of this
        ; page come back -- Sync does the showing, from Tab on each field
        tid := s.UpAttr(ev.srcElement, "data-ftab")
        if (tid != "") {
            v := s.UpAttr(ev.srcElement, "data-fval")
            try {
                s.Attr(tid, "data-value", v)
                items := s.El(tid).querySelectorAll(".axd-ftab")
                loop items.length {
                    it := items.item(A_Index - 1)
                    it.className := (it.getAttribute("data-fval") = v) ? "axd-ftab on" : "axd-ftab"
                }
            }
            AxForm.Sync(s)
            return
        }
        ; a button inside the form: it acts on the form and the form stays up
        aid := s.UpAttr(ev.srcElement, "data-fact")
        if (aid != "") {
            st := AxForm.Cur
            f := AxForm.Field(st, RegExReplace(aid, "^axf_"))
            if (IsObject(f) && f.HasOwnProp("Do")) {
                which := s.UpAttr(ev.srcElement, "data-fval")
                try {
                    fn := f.Do
                    fn(AxForm.Read(s, st.Fields), which)
                } catch as e
                    try s.Problem(e.Message)
                AxForm.Sync(s)
            }
            return
        }
        ; the rows editor: one more, one fewer, one further up
        rw := s.UpAttr(ev.srcElement, "data-frow")
        if (rw != "") {
            p := StrSplit(rw, "|")
            st := AxForm.Cur
            f := AxForm.Field(st, RegExReplace(p[2], "^axf_"))
            if IsObject(f) {
                f.V := AxForm.ReadRows(s, f)          ; whatever is typed stays typed
                rows := AxForm.RowVals(f)
                i := (p.Length >= 3) ? Integer(p[3]) : 0
                sep := AxForm.It(f, "Sep", "|")
                if (p[1] = "del" && i >= 1 && i <= rows.Length)
                    rows.RemoveAt(i)
                else if (p[1] = "up" && i >= 2 && i <= rows.Length) {
                    was := rows[i]
                    rows[i] := rows[i - 1], rows[i - 1] := was
                }
                ; A row with nothing typed in it yet still has to be drawn,
                ; or "Add one" would look like it did nothing -- so an empty
                ; row is written as its separators rather than as no line.
                blank := ""
                loop Max(AxForm.It(f, "Cols", []).Length - 1, 1)
                    blank .= sep
                out := ""
                for r in rows {
                    line := ""
                    for ci, c in r
                        line .= (ci = 1 ? "" : sep) c
                    out .= (out = "" ? "" : "`n") (Trim(line, sep " ") = "" ? blank : line)
                }
                if (p[1] = "add")
                    out .= (out = "" ? "" : "`n") blank
                f.V := out
                AxForm.Again(s, f)
                AxForm.Sync(s)
            }
            return
        }
        id := s.UpAttr(ev.srcElement, "data-fpick")
        if (id != "") {
            v := s.UpAttr(ev.srcElement, "data-fval")
            try {
                s.Attr(id, "data-value", v)
                items := s.El(id).querySelectorAll(".axd-pickit")
                loop items.length {
                    it := items.item(A_Index - 1)
                    on := (it.getAttribute("data-fval") = v)
                    it.className := on ? "axd-pickit on" : "axd-pickit"
                }
            }
            AxForm.Sync(s)
            return
        }
        pick := s.UpAttr(ev.srcElement, "data-pick")
        if (pick != "") {
            cur := ""
            try cur := s.El(pick).value
            hex := s.PickColor({Current: cur != "" ? cur : "#0078d4"})
            if (hex != "") {
                try s.El(pick).value := hex
                AxForm.Sync(s)
            }
        }
    }
    static BtnClick(s, ev) {
        i := s.UpAttr(ev.srcElement, "data-fbtn")
        if (i != "")
            AxForm.End(s, Integer(i))
    }
    ; Escape and Enter, handed over by the studio's own key hook.
    static Key(s, key, ctrl) {
        st := AxForm.Cur
        if !st
            return false
        if (key = 27) {
            AxForm.End(s, st.Cancel)
            return true
        }
        if (key = 13) {
            ; Enter in a textarea is a newline, not a commit -- unless Ctrl is
            ; held, which is the way out of a multi-line field everywhere else
            if !ctrl {
                try {
                    ae := s.Doc.activeElement
                    if (IsObject(ae) && ae.tagName = "TEXTAREA")
                        return false
                }
            }
            AxForm.End(s, 1)
            return true
        }
        return false
    }
    static End(s, i) {
        st := AxForm.Cur
        if (!st || st.Done)
            return
        if (i >= 1 && i != st.Cancel && AxForm.Why(s, st) != "")
            return                        ; the button is greyed for a reason
        st.Btn := i
        st.Done := true
    }
    static Why(s, st) {
        if !st.Check
            return ""
        try {
            f := st.Check
            return f(AxForm.Read(s, st.Fields))
        }
        return ""
    }
    ; Recomputes the options of every field that has a Fill, and redraws the
    ; ones that changed. Returns true if anything moved, so Sync can read the
    ; answers again -- refilling a dropdown can change what it holds.
    static Refill(s, st, V) {
        moved := false
        for f in st.Fields {
            if !f.HasOwnProp("Fill") || !f.HasOwnProp("Id")
                continue
            fn := f.Fill, opts := ""
            try opts := fn(V)
            was := f.HasOwnProp("_opts") ? f._opts : Chr(1)   ; never equal on the first pass
            if (opts = was)
                continue
            f._opts := opts
            f.Opts := opts
            cur := V.Has(f.Id) ? V[f.Id] : ""
            if !AxForm.HasOpt(opts, cur)
                cur := AxForm.FirstOpt(opts)
            f.V := cur
            eid := AxForm.Eid(f.Id)
            s.Off("keyup", eid), s.Off("change", eid), s.OffValue(eid)
            try {
                s.El(AxForm.Rid(f.Id)).outerHTML := AxForm.Row(f)
                AxTags.Expand(s.Doc)
                s._MakeFocusable()
            }
            AxForm.Hook(s, [f], true)
            moved := true
        }
        return moved
    }
    ; A field can belong to more than one page: Tab: "what|takes".
    static OnTab(tab, page) {
        for t in StrSplit(String(tab), "|")
            if (Trim(t) = page)
                return true
        return false
    }
    ; A field whose VALUE -- not only its choices -- follows another answer:
    ; the boxes a function's parameters need, once a function is picked. It is
    ; filled again only when what it would be changes, so what is typed into
    ; it stays typed until the answer it follows really moves.
    ;
    ; Seed(V) gives what the field should hold. A form that starts with a
    ; value of its own sets Seeded to what Seed WOULD have said, so the first
    ; pass leaves it alone.
    static Reseed(s, st, V) {
        moved := false
        for f in st.Fields {
            if !f.HasOwnProp("Seed") || !f.HasOwnProp("Id")
                continue
            fn := f.Seed, want := ""
            try want := fn(V)
            was := f.HasOwnProp("Seeded") ? f.Seeded : Chr(1)
            if (want = was)
                continue
            f.Seeded := want
            f.V := want
            AxForm.Again(s, f)
            moved := true
        }
        return moved
    }
    static HasOpt(opts, v) {
        if (v = "")
            return false
        for o in AxTags.Options(opts)
            if (o[1] = v)
                return true
        return false
    }
    static FirstOpt(opts) {
        for o in AxTags.Options(opts)
            return o[1]
        return ""
    }

    ; Runs on every keystroke: the reason the button is off, the line the form
    ; is about to write, and any field that only matters given another answer.
    static Sync(s) {
        st := AxForm.Cur
        if (!st || st.Done)
            return
        V := AxForm.Read(s, st.Fields)
        ; which page is open, when the form has pages
        tabs := AxForm.TabsId(st.Fields)
        page := (tabs != "" && V.Has(tabs)) ? V[tabs] : ""
        for f in st.Fields {
            if !f.HasOwnProp("Id")
                continue
            onTab := (tabs != "" && f.HasOwnProp("Tab"))
            if (!f.HasOwnProp("When") && !onTab)
                continue
            show := onTab ? AxForm.OnTab(f.Tab, page) : true
            ; An empty panel is not a panel: showing the page it sits on must
            ; not turn an answer box that has no answer in it yet into a bar
            ; of grey nothing.
            if (show && f.HasOwnProp("Kind") && f.Kind = "panel")
                show := (String(f.HasOwnProp("V") ? f.V : "") != "" || AxForm.It(f, "Keep", false))
            if (show && f.HasOwnProp("When")) {
                try {
                    w := f.When
                    show := w(V) ? true : false
                }
            }
            try s.El(AxForm.Rid(f.Id)).style.display := show ? "" : "none"
        }
        ; A field whose choices depend on another answer -- which events this
        ; control has, which pages that window contains. Refilled in place
        ; rather than by rebuilding the form, so nothing under a caret moves.
        if (!st.Filling && (AxForm.Refill(s, st, V) | AxForm.Reseed(s, st, V))) {
            st.Filling := true
            AxForm.Sync(s)
            st.Filling := false
            return
        }
        why := ""
        if st.Check {
            try {
                c := st.Check
                why := c(V)
            }
        }
        try {
            s.Html("axdFormErr", AxTags.E(why))
            b := s.El("axdFormBtns").querySelectorAll(".axd-fbtn")
            loop b.length {
                el := b.item(A_Index - 1)
                if (Integer(el.getAttribute("data-fbtn")) != st.Cancel)
                    el.className := RegExReplace(el.className, "\s*off\b") (why != "" ? " off" : "")
            }
        }
        prev := ""
        if st.Preview {
            try {
                p := st.Preview
                prev := p(V)
            }
        }
        try {
            s.Html("axdFormPrev", prev != "" ? AxTags.E(prev) : "")
            s.El("axdFormPrevWrap").style.display := (prev != "" ? "block" : "none")
        }
    }
}
