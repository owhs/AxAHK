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
            .      '<span class="ico" id="axdFormIcon"></span>'
            .      '<span class="axd-ftitle" id="axdFormTitle"></span>'
            .      '<span class="axd-fx ico" id="axdFormX">&#xE8BB;</span>'
            .    '</div>'
            .    '<div class="axd-fintro" id="axdFormIntro"></div>'
            .    '<div class="axd-fbody" id="axdFormBody"></div>'
            .    '<div class="axd-fprev" id="axdFormPrev"></div>'
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
        blank := {Ok: false, Btn: 0, Label: "", V: Map()}
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
        O := (n, d) => spec.HasOwnProp(n) ? spec.%n% : d
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
                s.El("axdFormIcon").style.display := (ico != "" ? "inline-block" : "none")
            }
            intro := O("Intro", "")
            try {
                s.Html("axdFormIntro", AxTags.E(intro))
                s.El("axdFormIntro").style.display := (intro != "" ? "block" : "none")
            }
            try s.El("axdForm").style.width := O("Width", 460) "px"

            body := ""
            for f in fields
                body .= AxForm.Row(f)
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
            Check: (V) => (V["c"] = "") ? "Pick one." : ""})
        return r.Ok ? r.V["c"] : ""
    }

    ; ---------------------------------------------------------- the fields
    ; The element id a field gets in the page. Prefixed, because the canvas
    ; names its elements after the controls in the design, and a field called
    ; "name" would otherwise be the second element in the document called that.
    static Eid(id) => "axf_" id
    static Rid(id) => "axfr_" id

    static Wide(kind) {
        static w := "|multiline|code|pick|note|heading|divider|list|flag|radio|"
        return InStr(w, "|" kind "|") > 0
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
            return '<div class="axd-fnote' (Fv("Mono") ? ' axd-fmono' : '') '" id="' row '">'
                 . (Fv("Html") ? Fv("L") : E(Fv("L"))) '</div>'
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
        default:
            body := '<ax-text id="' id '" value="' E(v) '"></ax-text>'
        }
        wide := AxForm.Wide(kind) || Fv("Wide", false)
        ; The class matters: a check box and a radio ARE labels, so a rule
        ; written as ".axd-f > label" catches the control itself and turns a
        ; 20px tick box into a 2px sliver.
        lbl := (Fv("L") != "") ? '<label class="axd-flab" for="' id '">' E(Fv("L")) '</label>' : ""
        return '<div class="axd-f' (wide ? " axd-f-wide" : "") ' axd-f-' kind '" id="' row '">'
             . lbl '<div class="axd-fctl">' body
             . (hint != "" ? '<div class="axd-fhint">' E(hint) '</div>' : "")
             . '</div></div>'
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
        if (kind = "heading" || kind = "note" || kind = "divider")
            return ""
        try {
            if (kind = "pick")
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
            if (kind = "heading" || kind = "note" || kind = "divider" || kind = "static")
                continue
            eid := AxForm.Eid(f.Id)
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
    static BodyClick(s, ev) {
        if !AxForm.Cur
            return
        go := s.UpAttr(ev.srcElement, "data-fgo")
        if (go != "") {
            AxForm.Cur.Go := go
            return AxForm.End(s, 0)
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
        for f in st.Fields {
            if !f.HasOwnProp("When") || !f.HasOwnProp("Id")
                continue
            try {
                w := f.When
                s.El(AxForm.Rid(f.Id)).style.display := w(V) ? "" : "none"
            }
        }
        ; A field whose choices depend on another answer -- which events this
        ; control has, which pages that window contains. Refilled in place
        ; rather than by rebuilding the form, so nothing under a caret moves.
        if (!st.Filling && AxForm.Refill(s, st, V)) {
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
            s.El("axdFormPrev").style.display := (prev != "" ? "block" : "none")
        }
    }
}
