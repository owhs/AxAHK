#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\AxStudio.Steps.ahk
#Include %A_LineFile%\..\AxStudio.Form.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk

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
;  AxStudio.StepsUi.ahk -- the Steps workspace: the list of pieces, the
;  flowchart (AXS in AxStudio.Steps.js) and the panel beside it, and the one
;  form every step is added or changed through. Steps and Code are two views
;  of the same piece; the bar along the top says which piece, what starts
;  it, and flips between them (AxStudio.FlipTo).
;
;  Adding is where the eye already is: every join in the chart has its +,
;  an empty piece offers the commonest steps as tiles, a step is dragged
;  onto a + to move it, and a right-click on a step has the rest.
;
;  The form is a wizard in the plain sense: first what kind of step
;  ("Show a message", "Only if...", "Read or write a file"), then only the
;  questions that kind needs, with the line of AutoHotkey it will write shown
;  underneath as you answer. A step already there opens the same form with
;  its answers filled in from its code; one the form cannot read opens as
;  code, so nothing is ever out of reach.
;
;  A file read can ship with the program (Files, App > Files): "build it in"
;  adds the file as a resource or a FileInstall and the step reads it through
;  File_<name>(), which resolves the same way compiled or loose.
; =============================================================================
class AxStepsUi {
    static SelAt := -1        ; after a change: pick the step that starts here

    ; ------------------------------------------------------------- the page
    static Html() => '<div id="axsWrap" class="axs-wrap" tabindex="0">'
        . '<div id="axsList" class="axs-pieces"></div>'
        . '<div id="axsView"></div>'
        . '<div id="axsInfo" class="axs-info"></div></div>'

    static Paint(s) {
        try s.CodeTyped()
        pcs := AxSteps.Pieces(s.P)
        pc := AxSteps.Pc
        ; the piece on show must still be there; else the one being edited in
        ; Code, else the first with anything in it
        if !AxStepsUi.Exists(s, pc) {
            pc := AxStepsUi.FromCode(s)
            if !IsObject(pc) {
                pc := pcs.Length ? pcs[1].Pc : ""
                for x in pcs
                    if x.Lines {
                        pc := x.Pc
                        break
                    }
            }
            AxSteps.Pc := pc, AxSteps.Sel := ""
        }
        s.Html("axsList", AxStepsUi.ListHtml(s, pcs))
        try s.Html("axsHead", AxStepsUi.HeadHtml(s, pc))
        if !IsObject(pc)
            return s.Html("axsView", '<div class="axs-empty">This program has no code yet. Give a control something to '
                 . 'do: pick it on the Design tab and add an event, or add a <a class="axd-link" data-do="go.rules">rule</a>.</div>')
        M := AxSteps.Read(s, pc)
        if !IsObject(M) {
            s.Html("axsView", '<div class="axs-empty">This piece does not read as AutoHotkey yet: '
                 . AxTags.E(AxSteps.Problem) '<br><br><a class="axd-link" data-sdo="code">Open it in the code</a></div>')
            return s.Html("axsInfo", "")
        }
        if (AxStepsUi.SelAt >= 0) {
            best := ""
            for id, st in M.Steps
                if (st.S >= AxStepsUi.SelAt && (best = "" || st.S < M.Steps[best].S))
                    best := id
            AxSteps.Sel := best, AxStepsUi.SelAt := -1
        }
        if (AxSteps.Sel != "" && !M.Steps.Has(AxSteps.Sel))
            AxSteps.Sel := ""
        json := M.Json()
        json := SubStr(json, 1, -1) ',"title":' AxJson.Stringify(AxSteps.Title(s, pc), "")
              . ',"when":' AxJson.Stringify(AxStepsUi.When(s, pc), "")
              . ',"rules":' AxJson.Stringify(AxStepsUi.RulesFirst(s, pc), "") '}'
        try s.Js("AXS.sel = " AxJson.Stringify(AxSteps.Sel, "") "; AXS.load(" json ");")
        s.Html("axsInfo", AxStepsUi.InfoHtml(s))
    }
    ; A handler's rules run before its code (AxStudio.Flow.ahk): shown at its
    ; top, in the words the rule is written in, so the chart is the whole story.
    static RulesFirst(s, pc) {
        out := []
        if IsObject(pc) && pc.Kind = "rules" {
            try for f in AxFlow.For(s.P.Wins[pc.Win], pc.Ctl, pc.Ev)
                out.Push(AxStepsUi.RuleWords(f))
            return out
        }
        if !IsObject(pc) || pc.Kind != "event"
            return out
        n := s.P.Find(pc.Id)
        if !IsObject(n) || n.Name = "" || pc.Index > n.Ev.Length
            return out
        try for f in AxFlow.For(s.P.Wins[pc.Win], n.Name, n.Ev[pc.Index]["name"])
            out.Push(AxStepsUi.RuleWords(f))
        return out
    }
    ; a rule in the words its wizard uses: "show a message: Saved"
    static RuleWords(f) {
        x := ""
        try x := AxWiz.Verb(f.Verb)
        say := IsObject(x) ? RegExReplace(x.L, "\s*\(.*$") : f.Verb
        return say (f.Arg != "" ? ": " f.Arg : "")
    }
    static Exists(s, pc) {
        if !IsObject(pc)
            return false
        if (pc.Kind = "gen")
            return true
        for x in AxSteps.Pieces(s.P)
            if (x.Key = AxSteps.Key(pc))
                return true
        return false
    }
    ; What starts a piece, as the chart's first line: "When saveBtn is clicked".
    static When(s, pc) {
        if !IsObject(pc)
            return ""
        switch pc.Kind {
        case "gen":   return "The whole script"
        case "rules": return "When " pc.Ctl " " AxStepsUi.EvWords(pc.Ev)
        case "init":
            w := (pc.Win >= 1 && pc.Win <= s.P.Wins.Length) ? s.P.Wins[pc.Win] : ""
            return "When " (IsObject(w) ? w.Name : "the window") " starts"
        case "fn":
            return SubStr(pc.Fn, 1, 3) = "hk:" ? "When " SubStr(pc.Fn, 4) " is pressed" : "When " pc.Fn "() is called"
        case "event":
            n := s.P.Find(pc.Id)
            if !IsObject(n) || pc.Index > n.Ev.Length
                return ""
            return "When " (n.Name != "" ? n.Name : n.Type) " " AxStepsUi.EvWords(n.Ev[pc.Index]["name"])
        }
        return ""
    }
    static EvWords(ev) {
        static m := Map("click", "is clicked", "doubleclick", "is double-clicked", "change", "changes",
            "focus", "gets the keyboard", "losefocus", "loses the keyboard", "blur", "loses the keyboard",
            "contextmenu", "is right-clicked", "close", "closes", "size", "is resized", "input", "is typed in",
            "select", "is picked", "toggle", "is switched", "submit", "is sent", "open", "opens", "keydown", "gets a key")
        k := StrLower(ev)
        return m.Has(k) ? m[k] : "-- " ev
    }
    ; The bar over the chart: which piece, what starts it, Steps or Code.
    static HeadHtml(s, pc) {
        E := (x) => AxTags.E(x)
        if !IsObject(pc)
            return '<span class="axd-pbt">Steps</span>'
        crumbs := []
        if (pc.Kind != "gen" && s.P.Wins.Length > 1 && pc.Win >= 1 && pc.Win <= s.P.Wins.Length)
            crumbs.Push(s.P.Wins[pc.Win].Name)
        switch pc.Kind {
        case "event":
            n := s.P.Find(pc.Id)
            if IsObject(n) && pc.Index <= n.Ev.Length
                crumbs.Push(n.Name != "" ? n.Name : n.Type), crumbs.Push(n.Ev[pc.Index]["name"])
        case "rules": crumbs.Push(pc.Ctl), crumbs.Push(pc.Ev)
        case "init":  crumbs.Push("When it starts")
        case "fn":    crumbs.Push("Your functions"), crumbs.Push(SubStr(pc.Fn, 1, 3) = "hk:" ? SubStr(pc.Fn, 4) : pc.Fn "()")
        case "gen":   crumbs.Push("The whole script")
        }
        h := '<span class="axd-pbcrumbs"><span class="ico">&#xE8FD;</span>'
        for i, c in crumbs
            h .= (i > 1 ? '<span class="axd-pbsep">&#x203A;</span>' : "") (i = crumbs.Length ? "<b>" E(c) "</b>" : E(c))
        h .= '</span><span class="axd-pbwhen">' E(AxStepsUi.When(s, pc)) '</span>'
        h .= '<span class="axd-pbright">'
        if (pc.Kind = "event" || pc.Kind = "rules")
            h .= '<span class="axd-hbtn" data-sdo="addrule" title="A rule: when this happens, do that -- no code, runs before the steps">'
               . '<span class="ico">&#xE945;</span> Add a rule</span>'
        if !AxSteps.ReadOnly(pc)
            h .= '<span class="axd-hbtn" data-sdo="add"><span class="ico">&#xE710;</span> Add a step</span>'
        h .= '<span class="axd-viewseg" data-sdo="code" title="The same piece, as the code it is    Ctrl+4">'
           . '<span class="on"><span class="ico">&#xE8FD;</span>Steps</span><span><span class="ico">&#xE943;</span>Code</span></span>'
        return h '</span>'
    }
    ; the piece the Code workspace has open, if it is one
    static FromCode(s) {
        t := s.CodeTarget
        if !IsObject(t)
            return ""
        switch t.Kind {
        case "event": return {Kind: "event", Win: s.P.Cur, Id: t.Id, Index: t.Index}
        case "init":  return {Kind: "init", Win: s.P.Cur}
        }
        return ""
    }
    static ListHtml(s, pcs) {
        key := AxSteps.Key(AxSteps.Pc)
        h := '<div class="axs-lh">Pieces of code</div>', was := 0
        for x in pcs {
            if (x.Win != was && s.P.Wins.Length > 1)
                h .= '<div class="axs-lw">' AxTags.E(s.P.Wins[x.Win].Name) '</div>'
            was := x.Win
            h .= '<div class="axs-pc' (x.Key = key ? " on" : "") (x.Lines ? "" : " empty") '" data-spiece="' AxTags.E(x.Key) '">'
               . '<span class="ico">&#x' x.Icon ';</span><span class="axs-pcl">' AxTags.E(x.Label) '</span>'
               . '<i>' (x.Lines ? x.Lines : "") '</i></div>'
        }
        h .= '<div class="axs-lh">Read only</div>'
           . '<div class="axs-pc' (key = "gen" ? " on" : "") '" data-spiece="gen"><span class="ico">&#xE8A7;</span>'
           . '<span class="axs-pcl">The whole script</span></div>'
        return h
    }

    ; ------------------------------------------------------------ the panel
    static InfoHtml(s) {
        M := AxSteps.M, pc := AxSteps.Pc
        if !IsObject(M)
            return ""
        E := (x) => AxTags.E(x)
        ro := AxSteps.ReadOnly(pc)
        btn := (v, label, key := "", cls := "") => '<span class="axd-hbtn' (cls != "" ? " " cls : "") '" data-sdo="' v '">'
            . label (key != "" ? '<i>' key '</i>' : "") '</span>'
        if (AxSteps.Sel = "" || !M.Steps.Has(AxSteps.Sel)) {
            n := M.Steps.Count
            return '<div class="axs-ih"><b>' E(AxSteps.Title(s, pc)) '</b><small>' n ' step' (n = 1 ? "" : "s") '</small></div>'
                 . '<div class="axd-note">' (ro ? "The script exactly as File &gt; Export writes it: read it here, change "
                   . "the pieces it is made from." : "The <b>+</b> on any line adds a step there. Double-click a step to "
                   . "change it, drag it onto another <b>+</b> to move it, right-click it for everything else.") '</div>'
                 . '<div class="axs-btns">' (ro ? "" : btn("add", "Add a step at the end", "", "axd-go")
                    . btn("uiapick", "Pick something in another program...")) btn("code", "Open it in the code") '</div>'
                 . (ro ? "" : '<div class="axd-rpsub">Keys</div><div class="axd-note">Delete takes the picked step out, F2 or Enter changes it, '
                 . 'Alt+Up and Alt+Down move it. Ctrl+Z puts back whatever was done.</div>')
        }
        rec := M.Steps[AxSteps.Sel]
        txt := SubStr(M.Text, rec.S + 1, rec.E - rec.S)
        kinds := Map("act", "Does", "set", "Changes a value", "if", "Decides", "loop", "Repeats", "try", "Tries",
                     "end", "Stops", "note", "A note", "code", "Code")
        h := '<div class="axs-ih k-' rec.Kind '"><b>' E(kinds.Has(rec.Kind) ? kinds[rec.Kind] : "Step") '</b></div>'
           . '<pre class="axm-code">' E(StrLen(txt) > 600 ? SubStr(txt, 1, 600) "..." : txt) '</pre>'
        if !ro {
            h .= '<div class="axs-btns">'
               . btn("change", rec.Kind = "if" ? "Change the test..." : rec.Kind = "loop" ? "Change how it repeats..." : "Change it...", "F2", "axd-go")
               . btn("after", "Add a step after")
               . btn("before", "Add a step before")
               . btn("dup", "Do it twice (a copy after it)")
               . btn("wrap", "Only do it if...")
               . btn("uiapick", "After it: pick something in another program...")
               . btn("up", "Move up", "Alt+Up") btn("down", "Move down", "Alt+Down")
               . btn("delete", "Take it out", "Del", "axd-danger") '</div>'
        }
        h .= '<div class="axs-btns">' btn("code", "Show it in the code") '</div>'
        return h
    }

    ; --------------------------------------------------------- the messages
    static Msg(s, p) {
        G := (k, d := "") => AxJson.Get(p, k, d)
        switch G("act") {
        case "pick":
            AxSteps.Sel := G("id")
            return s.Html("axsInfo", AxStepsUi.InfoHtml(s))
        case "piece":
            AxSteps.Pc := AxSteps.FromKey(G("key")), AxSteps.Sel := ""
            return AxStepsUi.Paint(s)
        case "open":
            return AxStepsUi.OpenFn(s, G("fn"))
        case "ins":
            at := StrSplit(G("at"), "|")
            return AxStepsUi.Add(s, at[1], Integer(at[2]))
        case "quick":
            ; the empty piece's tiles: the form, that kind already picked
            if !IsObject(AxSteps.M) || !AxSteps.M.Lists.Has("root")
                return
            return AxStepsUi.Add(s, "root", AxSteps.M.Lists["root"].Items.Length, G("kind"))
        case "move":
            at := StrSplit(G("at"), "|")
            id := G("id")
            if (at.Length < 2 || !IsObject(AxSteps.M) || !AxSteps.M.Steps.Has(id))
                return
            AxSteps.Sel := id
            return AxStepsUi.Apply(s, (M) => AxStepsEdit.MoveTo(M, id, at[1], Integer(at[2])), -3)
        case "menu":
            AxSteps.Sel := G("id")
            s.Html("axsInfo", AxStepsUi.InfoHtml(s))
            return AxStepsUi.Menu(s)
        case "rule":
            return AxStepsUi.EditRule(s, Integer(G("i", 0)) + 1)
        case "do":
            return AxStepsUi.Do(s, G("v"))
        }
    }
    static OpenFn(s, fn) {
        for wi, w in s.P.Wins
            for d in AxSteps.Defs(w.Script)
                if (d.Name = fn) {
                    AxSteps.Pc := {Kind: "fn", Win: wi, Fn: fn}, AxSteps.Sel := ""
                    return AxStepsUi.Paint(s)
                }
        s.Status("msg", fn " is not one of this program's own functions.")
    }
    static Do(s, v) {
        M := AxSteps.M, id := AxSteps.Sel
        if (v = "code")
            return s.FlipTo("code")
        if (v = "rules") {
            if IsObject(AxSteps.Pc) && AxSteps.Pc.HasOwnProp("Win") && AxSteps.Pc.Win != s.P.Cur
                s.SwitchWin(AxSteps.Pc.Win)
            return s.GoSec("rules", "logic")
        }
        if (v = "addrule")
            return AxStepsUi.EditRule(s, 0)
        if AxSteps.ReadOnly(AxSteps.Pc)
            return s.Status("msg", "The whole script is read only here: change the pieces it is made from.")
        if (v = "add")
            return AxStepsUi.Add(s, "root", M.Lists["root"].Items.Length)
        ; point at a button in another program: it comes back as a step here
        if (v = "uiapick")
            return AxUiaUi.Pick(s)
        if (id = "" || !IsObject(M) || !M.Steps.Has(id))
            return
        switch v {
        case "change": return AxStepsUi.Change(s, id)
        case "after", "before":
            st := M.Steps[id], L := M.Lists[st.List]
            for i, x in L.Items
                if (x = id)
                    return AxStepsUi.Add(s, st.List, v = "after" ? i : i - 1)
        case "dup":
            rec := M.Steps[id]
            code := AxStepsEdit.Plain(M, id)
            AxStepsUi.Apply(s, (M) => AxStepsEdit.After(M, id, code), AxStepsEdit.Span(M, id).B)
            s.Status("msg", "A copy of it is after it now.")
        case "wrap":
            r := AxStepsUi.CondForm(s, "Only do it if...", "The step runs only when this is true; otherwise it is skipped.")
            if (r != "")
                AxStepsUi.Apply(s, (M) => AxStepsEdit.Wrap(M, id, r), M.Steps[id].S)
        case "up", "down":
            AxStepsUi.Apply(s, (M) => AxStepsEdit.Move(M, id, v = "up" ? -1 : 1), -2, id, v = "up" ? -1 : 1)
        case "delete":
            AxStepsUi.Apply(s, (M) => AxStepsEdit.Delete(M, id), -1)
            AxSteps.Sel := ""
            AxStepsUi.Paint(s)
            s.Status("msg", "Taken out. Ctrl+Z puts it back.")
        }
    }
    ; A change: the new text from `fn`, put into the piece, the piece read
    ; again. at >= 0 picks the step starting there afterwards; -2 keeps the
    ; picked one, found again by where it moved.
    static Apply(s, fn, at := -1, movedId := "", d := 0) {
        s.CodeTyped()
        M := AxSteps.Read(s, AxSteps.Pc)
        if !IsObject(M)
            return s.Alert("The piece does not read as AutoHotkey, so it cannot be changed here: " AxSteps.Problem, "Step by step")
        try text := fn(M)
        catch as e
            return s.Alert(e.Message, "Step by step")
        if (text == M.Text)
            return
        s.Mark()
        AxSteps.Put(s, AxSteps.Pc, text)
        AxStepsUi.SyncEditor(s, text)
        s.QueueLive()
        if (at >= 0)
            AxStepsUi.SelAt := at
        else if (at = -3 && M.Steps.Has(AxSteps.Sel)) {
            ; moved anywhere: found again by where its text went
            st := M.Steps[AxSteps.Sel]
            want := Trim(SubStr(M.Text, st.S + 1, st.E - st.S))
            if (want != "" && (i := InStr(text, want)))
                AxStepsUi.SelAt := i - 1
        } else if (at = -2) {
            ; the moved step now starts where its neighbour did
            L := M.Lists[M.Steps[movedId].List]
            for i, x in L.Items
                if (x = movedId && i + d >= 1 && i + d <= L.Items.Length) {
                    AxStepsUi.SelAt := (d < 0) ? AxStepsEdit.Span(M, L.Items[i + d]).A
                                      : AxStepsEdit.Span(M, movedId).A + (AxStepsEdit.Span(M, L.Items[i + d]).B - AxStepsEdit.Span(M, L.Items[i + d]).A)
                }
        }
        AxStepsUi.Paint(s)
        try s.LintSoon()
    }
    ; the Code workspace showing the same piece gets the new text too
    static SyncEditor(s, text) {
        t := s.CodeTarget, pc := AxSteps.Pc
        if !IsObject(t) || pc.Win != s.P.Cur
            return
        if (t.Kind = "event" && pc.Kind = "event" && t.Id = pc.Id && t.Index = pc.Index)
         || (t.Kind = "init" && pc.Kind = "init") || (t.Kind = "script" && pc.Kind = "fn")
            s.SetEditor(text, false)
    }
    static ShowCode(s) {
        pc := AxSteps.Pc
        if !IsObject(pc)
            return
        at := -1
        M := AxSteps.M
        if (AxSteps.Sel != "" && IsObject(M) && M.Steps.Has(AxSteps.Sel))
            at := M.Steps[AxSteps.Sel].S
        ; a function opens where it starts, not at the top of the file
        else if (pc.Kind = "fn" && IsObject(M) && M.HasOwnProp("DefNode"))
            try at := M.T.Start(M.DefNode) - M.Off
        s.SetWs("code")
        if (pc.Kind = "gen")
            return s.ShowGenerated()
        if (pc.Win != s.P.Cur)
            s.SwitchWin(pc.Win)
        ; only rules, no code of its own yet: the code the rules are written
        ; as, in the script as it is exported
        if (pc.Kind = "rules") {
            s.ShowGenerated()
            try {
                fn := AxFlow.FnName(s.P.W, pc.Ctl, pc.Ev)
                fn := (fn != "" ? fn : "Flow_" pc.Ctl "_" pc.Ev) "("
                t := s.Ce.Value
                if (i := InStr(t, fn))
                    s.Ce.Select(i - 1)
            }
            return s.Status("msg", "Rules only, so far: this is the code they become. Add a step to give it code of its own.")
        }
        if (pc.Kind = "event") {
            n := s.P.Find(pc.Id)
            if IsObject(n)
                s.EditEvent(n, pc.Index, "code")
        } else
            s.EditScript(pc.Kind = "init" ? "init" : "script", "code")
        if (at >= 0)
            try s.Ce.Select(at)
    }

    ; Right-click on a step: everything the panel has, where the pointer is.
    static Menu(s) {
        M := AxSteps.M, id := AxSteps.Sel
        if !IsObject(M) || !M.Steps.Has(id)
            return
        rec := M.Steps[id]
        D := (v) => (*) => AxStepsUi.Do(s, v)
        s.ShowMenu([
            {Label: rec.Kind = "if" ? "Change the test..." : rec.Kind = "loop" ? "Change how it repeats..." : "Change it...", Icon: "E70F", Click: D("change")},
            "-",
            {Label: "Add a step before...", Icon: "E710", Click: D("before")},
            {Label: "Add a step after...", Icon: "E710", Click: D("after")},
            {Label: "Do it twice (a copy after it)", Icon: "E8C8", Click: D("dup")},
            {Label: "Only do it if...", Icon: "E8AB", Click: D("wrap")},
            "-",
            {Label: "Move up", Icon: "E74A", Click: D("up")},
            {Label: "Move down", Icon: "E74B", Click: D("down")},
            "-",
            {Label: "Show it in the code", Icon: "E943", Click: D("code")},
            {Label: "Take it out", Icon: "E74D", Click: D("delete")}])
    }
    ; A rule of the piece's event, changed where it is shown -- i is its
    ; place among them; 0 adds one.
    static EditRule(s, i) {
        pc := AxSteps.Pc
        if !IsObject(pc) || !(pc.Kind = "event" || pc.Kind = "rules")
            return s.Status("msg", "Rules belong to a control's event: open one of those.")
        if (pc.Win != s.P.Cur)
            s.SwitchWin(pc.Win)
        ctl := pc.Kind = "rules" ? pc.Ctl : "", ev := pc.Kind = "rules" ? pc.Ev : ""
        if (pc.Kind = "event") {
            n := s.P.Find(pc.Id)
            if !IsObject(n) || pc.Index > n.Ev.Length
                return
            if (n.Name = "")
                return s.Status("msg", "Name the control first (F2 on the Design tab): a rule refers to it by name.")
            ctl := n.Name, ev := n.Ev[pc.Index]["name"]
        }
        list := AxFlow.For(s.P.W, ctl, ev)
        if (i >= 1 && i <= list.Length)
            AxWiz.Flow(s, list[i])
        else
            AxWiz.Flow(s, "", {Ctl: ctl, Ev: ev})
        AxStepsUi.Paint(s)
    }

    ; ============================================================ the forms
    ; Add a step to list `key` at `pos`: what kind, then its questions.
    static Add(s, key, pos, kind := "") {
        M := AxSteps.M
        if !IsObject(M) || !M.Lists.Has(key)
            return
        r := AxStepsUi.StepForm(s, "Add a step", kind != "" ? Map("kind", kind) : "")
        if !IsObject(r)
            return
        L := M.Lists[key]
        at := (pos < L.Items.Length) ? AxStepsEdit.Span(M, L.Items[pos + 1]).A
            : L.Items.Length ? AxStepsEdit.Span(M, L.Items[L.Items.Length]).B : Max(0, L.Open)
        AxStepsUi.Apply(s, (M) => AxStepsEdit.Insert(M, key, pos, r.Code), at)
        s.Status("msg", "Added: " r.Say)
    }
    static Change(s, id) {
        M := AxSteps.M
        rec := M.Steps[id]
        full := SubStr(M.Text, rec.S + 1, rec.E - rec.S)
        head := rec.HasOwnProp("HeadS") ? SubStr(M.Text, rec.HeadS + 1, rec.HeadE - rec.HeadS) : full
        pre := AxStepsUi.Guess(rec.Kind, head, full)
        r := AxStepsUi.StepForm(s, "Change the step", pre, rec.Kind = "if" ? "if" : rec.Kind = "loop" ? "repeat" : "")
        if !IsObject(r)
            return
        AxStepsUi.Apply(s, (M) => AxStepsEdit.Replace(M, id, r.Code), rec.S)
        s.Status("msg", "Changed: " r.Say)
    }
    static CondForm(s, title, intro) {
        r := AxStepsUi.StepForm(s, title, Map("kind", "if"), "if", intro)
        return IsObject(r) ? RegExReplace(r.Code, "^\((.*)\)$", "$1") : ""
    }

    ; The one form. pre: a Map of answers to start from (Guess). only: "if" or
    ; "repeat" when changing the head of one -- then only that kind, and the
    ; code is only the head.
    static StepForm(s, title, pre := "", only := "", intro := "") {
        P0 := (k, d := "") => (pre is Map && pre.Has(k)) ? pre[k] : d
        vals := AxStepsUi.ValueOpts(s), ctls := AxStepsUi.CtlOpts(s), fns := AxStepsUi.FnOpts(s)
        kinds := [
            {V: "msg",    L: "Show a message",            Icon: "E8BD", Desc: "A box with a message and an OK button."},
            {V: "note",   L: "Show a notification",       Icon: "EA8F", Desc: "The small note in the corner of the screen."},
            {V: "set",    L: "Change a value",            Icon: "E70F", Desc: "Set, add to, or switch one of the program's values."},
            {V: "ctl",    L: "Change a control",          Icon: "E71D", Desc: "Its text, its value, show it, hide it, grey it out."},
            {V: "menu",   L: "Show a menu",               Icon: "E700", Desc: "One of the window's menus (Logic > Menus), where the pointer is."},
            {V: "if",     L: "Only if...",                Icon: "E8AB", Desc: "A test: the steps inside run only when it is true."},
            {V: "repeat", L: "Repeat",                    Icon: "E8EE", Desc: "A number of times, while something is true, or once for each item."},
            {V: "wait",   L: "Wait",                      Icon: "E916", Desc: "Pause for a moment before the next step."},
            {V: "type",   L: "Type or press keys",        Icon: "E765", Desc: "Into whatever program is in front."},
            {V: "run",    L: "Open a program, file or page", Icon: "E8A7", Desc: "Anything you could double-click, or a web address."},
            {V: "file",   L: "Read or write a file",      Icon: "E8A5", Desc: "Into a value, onto the end of one, and whether it ships with the program."},
            {V: "win",    L: "Work another window",       Icon: "E737", Desc: "Bring it to the front, close it, wait for it."},
            {V: "uia",    L: "A button or box in another program", Icon: "E7C4", Desc: "Click it, type into it or read it -- found by what it is, not where."},
            {V: "lib",    L: "Use a library",             Icon: "E82D", Desc: "What other people's libraries do in one step: JSON files, screenshots, the volume, the web..."},
            {V: "call",   L: "Do one of your functions",  Icon: "E8F4", Desc: "Yours, or an adaptor from Libraries -- .NET and more."},
            {V: "stop",   L: "Stop",                      Icon: "E71A", Desc: "Stop here, or stop repeating."},
            {V: "code",   L: "Write the code myself",     Icon: "E943", Desc: "Any AutoHotkey, as it is typed."}]
        ; only is a kind's name, never a flag: false would compare unequal to ""
        ; and filter every kind away
        if (only != "" && only != 0) {
            keep := []
            for k in kinds
                if (k.V = only)
                    keep.Push(k)
            if keep.Length
                kinds := keep
        }
        Of := (V, want*) => AxStepsUi.In(V["kind"], want*)
        vk := "words:Words|value:A value or a sum"
        fields := [
            {Id: "kind", Kind: "pick", L: "", V: P0("kind", kinds[1].V), Items: kinds, Tiles: kinds.Length > 3},
            ; a message
            {Id: "m_text", L: "Says", Kind: "text", V: P0("m_text", "Saved."), When: (V) => Of(V, "msg")},
            {Id: "m_vk", L: "It is", Kind: "seg", V: P0("m_vk", "words"), Opts: vk, When: (V) => Of(V, "msg")},
            ; a notification
            {Id: "n_title", L: "Title", Kind: "text", V: P0("n_title", "Done"), When: (V) => Of(V, "note")},
            {Id: "n_text", L: "Says", Kind: "text", V: P0("n_text", "It is finished."), When: (V) => Of(V, "note")},
            ; a value
            {Id: "s_who", L: "Which value", Kind: "choice", V: P0("s_who", ""), Opts: vals "|new:A new one...", When: (V) => Of(V, "set")},
            {Id: "s_new", L: "Called", Kind: "text", V: P0("s_new", ""), Ph: "count", When: (V) => Of(V, "set") && V["s_who"] = "new"},
            {Id: "s_how", L: "Make it", Kind: "choice", V: P0("s_how", "set"), When: (V) => Of(V, "set"),
             Opts: "set:This|add:Bigger by|take:Smaller by|append:Longer, with this on the end|toggle:The other way (on/off)"},
            {Id: "s_val", L: "Value", Kind: "text", V: P0("s_val", ""), When: (V) => Of(V, "set") && V["s_how"] != "toggle"},
            {Id: "s_vk", L: "It is", Kind: "seg", V: P0("s_vk", "value"), Opts: vk, When: (V) => Of(V, "set") && V["s_how"] != "toggle"},
            ; a control
            {Id: "c_ctl", L: "Control", Kind: "choice", V: P0("c_ctl", ""), Opts: ctls != "" ? ctls : "-:(no named controls)", When: (V) => Of(V, "ctl")},
            {Id: "c_what", L: "Do", Kind: "choice", V: P0("c_what", "text"), When: (V) => Of(V, "ctl"),
             Opts: "text:Set its text|value:Set its value|show:Show it|hide:Hide it|enable:Let it be used|disable:Grey it out|focus:Put the keyboard in it"},
            {Id: "c_val", L: "To", Kind: "text", V: P0("c_val", ""), When: (V) => Of(V, "ctl") && (V["c_what"] = "text" || V["c_what"] = "value")},
            {Id: "c_vk", L: "It is", Kind: "seg", V: P0("c_vk", "words"), Opts: vk, When: (V) => Of(V, "ctl") && (V["c_what"] = "text" || V["c_what"] = "value")},
            ; a menu
            {Id: "mn_name", L: "Which menu", Kind: "choice", V: P0("mn_name", ""), Opts: AxStepsUi.MenuOpts(s), When: (V) => Of(V, "menu")},
            ; a test
            {Id: "i_left", L: "When", Kind: "choice", V: P0("i_left", ""), When: (V) => Of(V, "if"),
             Opts: vals "|" (ctls != "" ? AxStepsUi.CtlValOpts(s) "|" : "") "win:A window...|file:A file...|key:A key...|expr:Something else (write the test)"},
            {Id: "i_test", L: "Is", Kind: "choice", V: P0("i_test", ""), When: (V) => Of(V, "if") && V["i_left"] != "expr",
             Fill: (V) => AxStepsUi.TestOpts(V["i_left"])},
            {Id: "i_right", L: "This", Kind: "text", V: P0("i_right", ""), When: (V) => Of(V, "if") && V["i_left"] != "expr" && AxStepsUi.NeedsRight(V)},
            {Id: "i_vk", L: "It is", Kind: "seg", V: P0("i_vk", "words"), Opts: vk,
             When: (V) => Of(V, "if") && AxStepsUi.NeedsRight(V) && !AxStepsUi.In(V["i_left"], "win", "file", "key", "expr")},
            {Id: "i_expr", L: "Test", Kind: "text", V: P0("i_expr", ""), Ph: "count > 3 && name != `"`"", When: (V) => Of(V, "if") && V["i_left"] = "expr"},
            ; repeating
            {Id: "p_how", L: "Repeat", Kind: "choice", V: P0("p_how", "times"), When: (V) => Of(V, "repeat"),
             Opts: "times:A number of times|while:While something is true|each:Once for each item in a list|files:Once for each file in a folder|"
                 . "lines:Once for each line of a file|forever:Until a step stops it"},
            {Id: "p_n", L: "How many times", Kind: "text", V: P0("p_n", "3"), When: (V) => Of(V, "repeat") && V["p_how"] = "times"},
            {Id: "p_cond", L: "While", Kind: "text", V: P0("p_cond", ""), Ph: "count < 10", When: (V) => Of(V, "repeat") && V["p_how"] = "while"},
            {Id: "p_list", L: "The list", Kind: "text", V: P0("p_list", ""), Ph: "items", When: (V) => Of(V, "repeat") && V["p_how"] = "each"},
            {Id: "p_path", L: "Folder or file", Kind: "text", V: P0("p_path", ""), When: (V) => Of(V, "repeat") && AxStepsUi.In(V["p_how"], "files", "lines"),
             Hint: "A folder with a pattern (C:\Photos\*.jpg), or a file. Without a folder, beside the program."},
            ; waiting, keys, running
            {Id: "w_secs", L: "Seconds", Kind: "text", V: P0("w_secs", "1"), When: (V) => Of(V, "wait"), Hint: "0.5 is half a second."},
            {Id: "t_how", L: "How", Kind: "seg", V: P0("t_how", "text"), Opts: "text:Type this text|keys:Press these keys", When: (V) => Of(V, "type")},
            {Id: "t_text", L: "Keys", Kind: "text", V: P0("t_text", ""), When: (V) => Of(V, "type"),
             Hint: "Press keys: {Enter} {Tab} {Esc}, ^c is Ctrl+C, !f is Alt+F, +a is Shift+A."},
            {Id: "r_what", L: "Open", Kind: "text", V: P0("r_what", ""), Ph: "notepad.exe, C:\notes.txt or https://...", When: (V) => Of(V, "run")},
            ; a file
            {Id: "f_do", L: "Do", Kind: "choice", V: P0("f_do", "read"), When: (V) => Of(V, "file"),
             Opts: "read:Read it into a value|add:Add to the end of it|write:Write it, replacing what was there|delete:Delete it"},
            {Id: "f_path", L: "The file", Kind: "text", V: P0("f_path", "notes.txt"), When: (V) => Of(V, "file"),
             Hint: "Without a folder it is beside the program -- the same whether it is run as a script or as an exe."},
            {Id: "f_into", L: "Into", Kind: "choice", V: P0("f_into", ""), Opts: vals "|new:A new value...", When: (V) => Of(V, "file") && V["f_do"] = "read"},
            {Id: "f_new", L: "Called", Kind: "text", V: P0("f_new", "text"), When: (V) => Of(V, "file") && V["f_do"] = "read" && V["f_into"] = "new"},
            {Id: "f_text", L: "Text", Kind: "text", V: P0("f_text", ""), When: (V) => Of(V, "file") && AxStepsUi.In(V["f_do"], "add", "write")},
            {Id: "f_vk", L: "It is", Kind: "seg", V: P0("f_vk", "words"), Opts: vk, When: (V) => Of(V, "file") && AxStepsUi.In(V["f_do"], "add", "write")},
            {Id: "f_ship", L: "The finished program", Kind: "choice", V: P0("f_ship", "path"), When: (V) => Of(V, "file") && V["f_do"] = "read",
             Opts: "path:Looks for the file beside it|resource:Carries it inside (for a file it only reads)|install:Carries it, and writes it out beside itself",
             Hint: "Carried inside, the file cannot go missing: it is built into the exe (App > Files)."},
            ; a window
            {Id: "x_do", L: "Do", Kind: "choice", V: P0("x_do", "activate"), When: (V) => Of(V, "win"),
             Opts: "activate:Bring it to the front|wait:Wait for it to open|close:Close it|waitclose:Wait for it to close|min:Minimise it|max:Maximise it"},
            {Id: "x_win", L: "The window", Kind: "text", V: P0("x_win", "Notepad"), When: (V) => Of(V, "win"),
             Hint: "Part of its title (Notepad), or ahk_exe and its program (ahk_exe notepad.exe)."},
            ; another program's button or box, through UI Automation
            {Id: "u_win", L: "In the window", Kind: "text", V: P0("u_win", "ahk_exe notepad.exe"), When: (V) => Of(V, "uia"),
             Hint: "Part of its title, or ahk_exe and its program. The element picker (Logic > Macros) finds all of this for you."},
            {Id: "u_by", L: "Find it by", Kind: "choice", V: P0("u_by", "Name"), When: (V) => Of(V, "uia"),
             Opts: "Name:What it says (its name)|AutomationId:Its automation id|ClassName:Its class"},
            {Id: "u_what", L: "Which is", Kind: "text", V: P0("u_what", "Save"), When: (V) => Of(V, "uia")},
            {Id: "u_type", L: "And it is", Kind: "choice", V: P0("u_type", "-"), When: (V) => Of(V, "uia"),
             Opts: "-:Any kind of thing|Button:A button|Edit:A box you type in|MenuItem:A menu item|CheckBox:A tick box|"
                 . "ComboBox:A drop-down|ListItem:An item in a list|TabItem:A tab|Hyperlink:A link|Text:Some text"},
            {Id: "u_act", L: "Then", Kind: "choice", V: P0("u_act", "click"), When: (V) => Of(V, "uia"),
             Opts: "click:Click it|type:Put text in it|read:Read what it holds into a value|wait:Wait until it is there"},
            {Id: "u_text", L: "The text", Kind: "text", V: P0("u_text", ""), When: (V) => Of(V, "uia") && V["u_act"] = "type"},
            {Id: "u_into", L: "Into", Kind: "choice", V: P0("u_into", "new"), Opts: (vals != "" ? vals "|" : "") "new:A new value...",
             When: (V) => Of(V, "uia") && V["u_act"] = "read"},
            {Id: "u_new", L: "Called", Kind: "text", V: P0("u_new", "found"), When: (V) => Of(V, "uia") && V["u_act"] = "read" && V["u_into"] = "new"},
            ; a library's own steps (studio\packages\patch.json): the ones in
            ; this project first; the rest install when the step is added
            {Id: "l_step", L: "Do", Kind: "choice", V: P0("l_step", ""), Opts: AxStepsUi.LibOpts(s), When: (V) => Of(V, "lib")},
            {Id: "l_who", L: "Which", Kind: "choice", V: P0("l_who", ""), When: (V) => Of(V, "lib") && AxStepsUi.LibNeeds(V, "who"),
             Fill: (V) => AxStepsUi.LibWhoOpts(s, V)},
            {Id: "l_new", L: "Called", Kind: "text", V: P0("l_new", "result"), When: (V) => Of(V, "lib") && V["l_who"] = "new"},
            {Id: "l_arg", L: "With", Kind: "text", V: P0("l_arg", ""), When: (V) => Of(V, "lib") && AxStepsUi.LibNeeds(V, "arg"),
             Hint: "What the step needs, as the label says. A file without a folder is beside the program."},
            ; a function
            {Id: "k_fn", L: "Function", Kind: "choice", V: P0("k_fn", ""), Opts: fns != "" ? fns : "-:(this program has none yet)", When: (V) => Of(V, "call")},
            {Id: "k_args", L: "Give it", Kind: "text", V: P0("k_args", ""), Ph: "nothing, or values with commas between", When: (V) => Of(V, "call"),
             Hint: "Text in quotes (" Chr(34) "Hello" Chr(34) "), a number, or a value's name."},
            {Id: "k_into", L: "Keep what it gives in", Kind: "choice", V: P0("k_into", "-"), When: (V) => Of(V, "call"),
             Opts: "-:(nothing -- it just does it)" (vals != "" ? "|" vals : "") "|new:A new value..."},
            {Id: "k_new", L: "Called", Kind: "text", V: P0("k_new", "result"), When: (V) => Of(V, "call") && V["k_into"] = "new"},
            ; stopping
            {Id: "z_how", L: "Stop", Kind: "choice", V: P0("z_how", "return"), When: (V) => Of(V, "stop"),
             Opts: "return:Here -- the rest of this piece is skipped|break:Repeating -- carry on after the repeat|continue:This time round -- go straight to the next"},
            ; code
            {Id: "q_code", L: "Code", Kind: "code", V: P0("q_code", ""), Rows: 6, When: (V) => Of(V, "code")}]
        r := AxForm.Show(s, {Title: title, Icon: "E8FD", Width: 760,
            Intro: intro != "" ? intro : "What should happen? Pick a kind of step; the line it writes is shown underneath.",
            Fields: fields, Buttons: [InStr(title, "Add") ? "Add it" : "Save", "Cancel"],
            Check: (V) => AxStepsUi.Check(V),
            Preview: (V) => AxStepsUi.Code(s, V, only != "", true)})
        if !r.Ok
            return ""
        code := AxStepsUi.Code(s, r.V, only != "", false)
        ; a step that uses a library brings it with it -- installed first
        ; when it is not in the project yet
        lib := (r.V["kind"] = "uia") ? AxPkg.UiaLib : (r.V["kind"] = "lib" && IsObject(st := AxPkg.Step(r.V["l_step"]))) ? st.Lib : ""
        if (lib != "")
            AxStepsUi.BringLib(s, lib)
        return {Code: code, Say: AxStepsUi.KindName(kinds, r.V["kind"])}
    }
    ; the window the piece on show belongs to
    static PcWin(s) {
        pc := AxSteps.Pc
        return (IsObject(pc) && pc.HasOwnProp("Win") && pc.Win >= 1 && pc.Win <= s.P.Wins.Length) ? s.P.Wins[pc.Win] : s.P.W
    }
    static MenuOpts(s) {
        o := ""
        for m in AxChrome.Ctx(AxStepsUi.PcWin(s).Ctx)
            o .= (o = "" ? "" : "|") m.Name ":" m.Name
        return o != "" ? o : "-:(this window has no menus yet -- Logic > Menus)"
    }
    static BringLib(s, lib) {
        if AxPkg.Installed(AxPkg.ProjDir(s.P)).Has(lib)
            return AxPkg.Use(s.P, lib)
        e := AxPkg.Find(lib)
        if IsObject(e)
            AxPkgUi.NeedLib(s, e, AxStepsUi.UseFn(s, lib))
    }
    static UseFn(s, lib) => (ok) => (AxPkg.Use(s.P, lib), s.QueueLive())
    ; every library step: this project's libraries first, then the rest,
    ; each said as "Library: what it does"
    static LibOpts(s) {
        have := AxPkg.Installed(AxPkg.ProjDir(s.P))
        a := "", b := ""
        for st in AxPkg.Steps() {
            e := AxPkg.Find(st.Lib)
            if IsObject(e) && e.Hidden
                continue
            one := "|" st.V ":" StrSplit(st.Lib, "/")[-1] ": " StrReplace(RegExReplace(st.L, "\s*\(.*\)$"), "|", "/")
            if have.Has(st.Lib)
                a .= one
            else
                b .= one " (installs it)"
        }
        return SubStr(a b, 2)
    }
    static LibNeeds(V, what) {
        st := AxPkg.Step(V["l_step"])
        return IsObject(st) && (what = "arg" ? st.Arg : st.Who != "")
    }
    static LibWhoOpts(s, V) {
        st := AxPkg.Step(V["l_step"])
        if !IsObject(st)
            return ""
        if (st.Who = "ctl")
            return AxStepsUi.CtlOpts(s)
        vals := AxStepsUi.ValueOpts(s)
        return (vals != "" ? vals "|" : "") "new:A new value..."
    }
    static KindName(kinds, v) {
        for k in kinds
            if (k.V = v)
                return StrLower(k.L)
        return "a step"
    }
    static In(v, want*) {
        for w in want
            if (v = w)
                return true
        return false
    }
    ; ----------------------------------------------------- what to choose from
    static ValueOpts(s) {
        o := "", seen := Map()
        seen.CaseSense := false
        for v in AxBind.Vars(s.P)
            if !seen.Has(v.Name)
                o .= (o = "" ? "" : "|") v.Name ":" v.Name, seen[v.Name] := 1
        if IsObject(AxSteps.M)
            for n in AxSteps.M.Shared
                if !seen.Has(n)
                    o .= (o = "" ? "" : "|") n ":" n, seen[n] := 1
        return o
    }
    static CtlOpts(s) {
        o := ""
        for w in s.P.Wins
            for n in AxImport.Nodes(w.Root)
                if (n.Name != "")
                    o .= (o = "" ? "" : "|") AxProject.CleanName(n.Name) ":" n.Name " (" n.Type ")"
        return o
    }
    static CtlValOpts(s) {
        o := ""
        for w in s.P.Wins
            for n in AxImport.Nodes(w.Root)
                if (n.Name != "")
                    o .= (o = "" ? "" : "|") "ctl:" AxProject.CleanName(n.Name) ":What " n.Name " holds"
        return o
    }
    static FnOpts(s) {
        o := ""
        for w in s.P.Wins
            for d in AxSteps.Defs(w.Script)
                if (SubStr(d.Name, 1, 3) != "hk:")
                    o .= (o = "" ? "" : "|") d.Name ":" d.Label
        ; adaptors: .NET's and libraries' methods made functions (Libraries)
        for a in AxNet.List(s.P)
            o .= (o = "" ? "" : "|") a.Name ":" a.Name "() -- " a.Doc
        return o
    }
    static TestOpts(left) {
        switch left {
        case "win":  return "exists:Is open|active:Is in front|none:Is not open"
        case "file": return "exists:Exists|none:Does not exist"
        case "key":  return "down:Is held down|up:Is not held down"
        case "expr": return "-:-"
        }
        return "is:Is|isnot:Is not|empty:Is empty|full:Is not empty|more:Is more than|less:Is less than|has:Contains|starts:Starts with"
    }
    static NeedsRight(V) => !AxStepsUi.In(V["i_test"], "empty", "full")
    static Check(V) {
        switch V["kind"] {
        case "set":
            if (V["s_who"] = "" || V["s_who"] = "new" && AxProject.CleanName(V["s_new"]) = "")
                return "Say which value."
        case "ctl":
            if (V["c_ctl"] = "" || V["c_ctl"] = "-")
                return "Pick a control -- give one a name on the canvas first (F2)."
        case "if":
            if (V["i_left"] = "")
                return "Say what the test looks at."
            if (V["i_left"] = "expr" && Trim(V["i_expr"]) = "")
                return "Write the test."
        case "repeat":
            if (V["p_how"] = "times" && Trim(V["p_n"]) = "")
                return "Say how many times."
        case "call":
            if (V["k_fn"] = "" || V["k_fn"] = "-")
                return "This program has no functions of its own yet."
        case "menu":
            if (V["mn_name"] = "" || V["mn_name"] = "-")
                return "Make a menu first (Logic > Menus)."
        case "lib":
            st := AxPkg.Step(V["l_step"])
            if !IsObject(st)
                return "Pick what the library should do."
            if (st.Who != "" && (V["l_who"] = "" || V["l_who"] = "new" && AxProject.CleanName(V["l_new"]) = ""))
                return st.Who = "ctl" ? "Pick the control." : "Say which value."
            if (st.Arg && Trim(V["l_arg"]) = "")
                return "Fill in " st.ArgL "."
        case "code":
            if (Trim(V["q_code"]) = "")
                return "Write the code."
        case "uia":
            if (Trim(V["u_win"]) = "" || Trim(V["u_what"]) = "")
                return "Say which window, and what the thing in it says or is called."
        case "file":
            if (Trim(V["f_path"]) = "")
                return "Say which file."
        }
        return ""
    }

    ; ------------------------------------------------------ the code it writes
    ; head: only the test of an if, only the first line of a repeat.
    ; preview: for the form's last line -- nothing is added to App > Files.
    static Code(s, V, head, preview) {
        Lit := (x, kind) => (kind = "words") ? AxLit.S(x) : (Trim(x) = "" ? '""' : Trim(x))
        switch V["kind"] {
        case "msg":
            return "MsgBox(" Lit(V["m_text"], V["m_vk"]) ")"
        case "note":
            return "TrayTip(" AxLit.S(V["n_text"]) ", " AxLit.S(V["n_title"]) ")"
        case "set":
            ; (not v: V is the answers, and names are one whatever their case)
            who := V["s_who"] = "new" ? AxProject.CleanName(V["s_new"]) : V["s_who"]
            val := Lit(V["s_val"], V["s_vk"])
            switch V["s_how"] {
            case "add":    return who " += " val
            case "take":   return who " -= " val
            case "append": return who " .= " val
            case "toggle": return who " := !" who
            }
            return who " := " val
        case "ctl":
            c := V["c_ctl"], val := Lit(V["c_val"], V["c_vk"])
            switch V["c_what"] {
            case "value":   return c ".Value := " val
            case "show":    return c ".Visible := true"
            case "hide":    return c ".Visible := false"
            case "enable":  return c ".Enabled := true"
            case "disable": return c ".Enabled := false"
            case "focus":   return c ".Focus()"
            }
            return c ".Text := " val
        case "if":
            t := AxStepsUi.Test(V)
            return head ? "(" t ")" : "if (" t ") {`n}"
        case "repeat":
            h := AxStepsUi.LoopHead(V)
            return head ? h : h " {`n}"
        case "wait":
            n := StrReplace(Trim(V["w_secs"]), ",", ".")
            return "Sleep(" (IsNumber(n) ? Round(n * 1000) : "(" n ") * 1000") ")"
        case "type":
            return (V["t_how"] = "keys" ? "Send(" : "SendText(") AxLit.S(V["t_text"]) ")"
        case "run":
            return "Run(" AxLit.S(Trim(V["r_what"])) ")"
        case "file":
            return AxStepsUi.FileCode(s, V, preview)
        case "win":
            w := AxLit.S(Trim(V["x_win"]))
            static verbs := Map("activate", "WinActivate", "wait", "WinWait", "close", "WinClose", "waitclose", "WinWaitClose",
                                "min", "WinMinimize", "max", "WinMaximize")
            return verbs[V["x_do"]] "(" w ")"
        case "uia":
            ; Descolada's UIA: the element found again every time, by what it is
            cond := "{" V["u_by"] ": " AxLit.S(Trim(V["u_what"])) (V["u_type"] != "-" ? ", Type: " AxLit.S(V["u_type"]) : "") "}"
            el := "UIA.ElementFromHandle(WinExist(" AxLit.S(Trim(V["u_win"])) ")).WaitElement(" cond ", " (V["u_act"] = "wait" ? 10000 : 3000) ")"
            switch V["u_act"] {
            case "type": return el ".Value := " AxLit.S(V["u_text"])
            case "read": return (V["u_into"] = "new" ? AxProject.CleanName(V["u_new"]) : V["u_into"]) " := " el ".Value"
            case "wait": return el
            }
            return el ".Click()"
        case "menu":
            w := AxStepsUi.PcWin(s)
            return (V["mn_name"] = "" || V["mn_name"] = "-") ? "" : w.Var ".ShowMenu(" AxChrome.CtxFn(w, V["mn_name"]) "())"
        case "lib":
            st := AxPkg.Step(V["l_step"])
            if !IsObject(st)
                return ""
            who := (st.Who = "") ? "" : (V["l_who"] = "new") ? AxProject.CleanName(V["l_new"]) : V["l_who"]
            code := AxPkg.StepCode(s.P, s.P.W, {Verb: st.V, Arg: Trim((who != "" ? who " " : "") (st.Arg ? V["l_arg"] : ""))})
            ; a rule's step keeps a bound value in step; here it is a line of its own
            return RegExReplace(code, ", AxBindSync\(\)$")
        case "call":
            into := (V["k_into"] = "new") ? AxProject.CleanName(V["k_new"]) : (V["k_into"] = "-" ? "" : V["k_into"])
            return (into != "" ? into " := " : "") V["k_fn"] "(" Trim(V["k_args"]) ")"
        case "stop":
            return V["z_how"]
        case "code":
            return Trim(StrReplace(V["q_code"], "`r"), "`n")
        }
        return ""
    }
    static Test(V) {
        left := V["i_left"], r := V["i_right"], words := V["i_vk"] = "words"
        Q := (x) => words ? AxLit.S(x) : (Trim(x) = "" ? '""' : Trim(x))
        switch left {
        case "expr": return Trim(V["i_expr"])
        case "win":
            w := AxLit.S(Trim(r))
            return V["i_test"] = "active" ? "WinActive(" w ")" : V["i_test"] = "none" ? "!WinExist(" w ")" : "WinExist(" w ")"
        case "file":
            return (V["i_test"] = "none" ? "!" : "") "FileExist(" AxLit.S(Trim(r)) ")"
        case "key":
            return (V["i_test"] = "up" ? "!" : "") "GetKeyState(" AxLit.S(Trim(r)) ", " AxLit.S("P") ")"
        }
        x := (SubStr(left, 1, 4) = "ctl:") ? SubStr(left, 5) ".Value" : left
        switch V["i_test"] {
        case "isnot":  return x " != " Q(r)
        case "empty":  return x ' = ""'
        case "full":   return x ' != ""'
        case "more":   return x " > " Q(r)
        case "less":   return x " < " Q(r)
        case "has":    return "InStr(" x ", " Q(r) ")"
        case "starts": return "SubStr(" x ", 1, StrLen(" Q(r) ")) = " Q(r)
        }
        return x " = " Q(r)
    }
    static LoopHead(V) {
        P := (x) => AxAsset.PathExpr(Trim(x))
        switch V["p_how"] {
        case "while":   return "while (" Trim(V["p_cond"]) ")"
        case "each":    return "for item in " Trim(V["p_list"])
        case "files":   return "loop files, " P(V["p_path"])
        case "lines":   return "loop read, " P(V["p_path"])
        case "forever": return "loop"
        }
        return "loop " Trim(V["p_n"])
    }
    ; A file step. Reading a file the program ships with goes through
    ; File_<name>(): the file is added to App > Files, as a resource (the
    ; function hands back its text) or a FileInstall (it hands back the path).
    static FileCode(s, V, preview) {
        path := Trim(V["f_path"])
        pe := AxAsset.PathExpr(path)
        txt := (V["f_vk"] = "words") ? AxLit.S(V["f_text"]) : (Trim(V["f_text"]) = "" ? '""' : Trim(V["f_text"]))
        switch V["f_do"] {
        case "add":    return "FileAppend(" txt ", " pe ", " AxLit.S("UTF-8") ")"
        case "write":  return "FileOpen(" pe ", " AxLit.S("w") ", " AxLit.S("UTF-8") ").Write(" txt ")"
        case "delete": return "FileDelete(" pe ")"
        }
        into := V["f_into"] = "new" ? AxProject.CleanName(V["f_new"]) : V["f_into"]
        if (V["f_ship"] = "path")
            return into " := FileRead(" pe ", " AxLit.S("UTF-8") ")"
        SplitPath(path, &base)
        name := AxProject.CleanName(RegExReplace(base, "\.[^.]*$"))
        if (name = "")
            name := "file"
        if !preview
            AxStepsUi.ShipFile(s, name, path, V["f_ship"])
        fn := AxAsset.FileFn(name)
        return (V["f_ship"] = "resource") ? into " := " fn "()" : into " := FileRead(" fn "(), " AxLit.S("UTF-8") ")"
    }
    ; into App > Files, once
    static ShipFile(s, name, path, how) {
        for f in AxAsset.Files(s.P)
            if (AxAsset.FileFn(f.Name) = AxAsset.FileFn(name))
                return
        ; (not AppendProject: that goes to the App tab, and this is asked from Map)
        cur := RTrim(String(s.P.Files), " `t`r`n")
        s.P.Files := (Trim(cur) = "") ? AxAsset.FileLine(name, path, how) : cur "`n" AxAsset.FileLine(name, path, how)
        s.Status("msg", path " ships with the program: App > Files.")
    }

    ; --------------------------------------------- a step's code as answers
    ; Only what can be read back exactly; anything else opens as code.
    static Guess(kind, head, full) {
        m := Map()
        q := '"((?:[^"``]|``.)*)"'                    ; a quoted string, its text
        Un := (x) => StrReplace(StrReplace(x, '``"', '"'), "````", "``")
        if (kind = "if") {
            m["kind"] := "if", m["i_left"] := "expr", m["i_expr"] := RegExReplace(Trim(head), "^\((.*)\)$", "$1")
            return m
        }
        if (kind = "loop") {
            m["kind"] := "repeat"
            if RegExMatch(head, "i)^loop\s+(\d+)$", &x)
                m["p_how"] := "times", m["p_n"] := x[1]
            else if RegExMatch(head, "i)^while\s*\(?(.*?)\)?$", &x)
                m["p_how"] := "while", m["p_cond"] := x[1]
            else if RegExMatch(head, "i)^for\s+item\s+in\s+(.+)$", &x)
                m["p_how"] := "each", m["p_list"] := x[1]
            else if RegExMatch(head, "i)^loop$")
                m["p_how"] := "forever"
            else
                m["p_how"] := "while", m["p_cond"] := head
            return m
        }
        t := Trim(full)
        if RegExMatch(t, "^MsgBox\(" q "\)$", &x)
            return Map("kind", "msg", "m_text", Un(x[1]), "m_vk", "words")
        if RegExMatch(t, "^MsgBox\((.*)\)$", &x)
            return Map("kind", "msg", "m_text", x[1], "m_vk", "value")
        if RegExMatch(t, "^TrayTip\(" q ",\s*" q "\)$", &x)
            return Map("kind", "note", "n_text", Un(x[1]), "n_title", Un(x[2]))
        if RegExMatch(t, "^Sleep\((\d+)\)$", &x)
            return Map("kind", "wait", "w_secs", Integer(x[1]) / 1000 = Integer(x[1]) // 1000 ? Integer(x[1]) // 1000 : Integer(x[1]) / 1000)
        if RegExMatch(t, "^(Send|SendText)\(" q "\)$", &x)
            return Map("kind", "type", "t_how", x[1] = "Send" ? "keys" : "text", "t_text", Un(x[2]))
        if RegExMatch(t, "^Run\(" q "\)$", &x)
            return Map("kind", "run", "r_what", Un(x[1]))
        if RegExMatch(t, "^(WinActivate|WinWait|WinClose|WinWaitClose|WinMinimize|WinMaximize)\(" q "\)$", &x) {
            static back := Map("WinActivate", "activate", "WinWait", "wait", "WinClose", "close", "WinWaitClose", "waitclose",
                               "WinMinimize", "min", "WinMaximize", "max")
            return Map("kind", "win", "x_do", back[x[1]], "x_win", Un(x[2]))
        }
        if (t = "return" || t = "break" || t = "continue")
            return Map("kind", "stop", "z_how", t)
        if RegExMatch(t, "^(\w+)\.(Text|Value)\s*:=\s*" q "$", &x)
            return Map("kind", "ctl", "c_ctl", x[1], "c_what", StrLower(x[2]), "c_val", Un(x[3]), "c_vk", "words")
        if RegExMatch(t, "^(\w+)\.(Text|Value)\s*:=\s*(.+)$", &x)
            return Map("kind", "ctl", "c_ctl", x[1], "c_what", StrLower(x[2]), "c_val", x[3], "c_vk", "value")
        if RegExMatch(t, "^(\w+)\.(Visible|Enabled)\s*:=\s*(true|false)$", &x)
            return Map("kind", "ctl", "c_ctl", x[1], "c_what", x[2] = "Visible" ? (x[3] = "true" ? "show" : "hide") : (x[3] = "true" ? "enable" : "disable"))
        if RegExMatch(t, "^(\w+)\.Focus\(\)$", &x)
            return Map("kind", "ctl", "c_ctl", x[1], "c_what", "focus")
        if RegExMatch(t, "^(\w+)\s*:=\s*!\s*(\w+)$", &x) && x[1] = x[2]
            return Map("kind", "set", "s_who", x[1], "s_how", "toggle")
        if RegExMatch(t, "^(\w+)\s*(:=|\+=|-=|\.=)\s*(.+)$", &x) {
            static how := Map(":=", "set", "+=", "add", "-=", "take", ".=", "append")
            words := RegExMatch(x[3], "^" q "$", &y)
            return Map("kind", "set", "s_who", x[1], "s_how", how[x[2]], "s_val", words ? Un(y[1]) : x[3], "s_vk", words ? "words" : "value")
        }
        if RegExMatch(t, "^(\w+(?:\.\w+)?)\((.*)\)$", &x) && !RegExMatch(x[1], "i)^(MsgBox|Send|Run|Sleep|TrayTip)$")
            return Map("kind", "call", "k_fn", x[1], "k_args", x[2], "q_code", t)
        return Map("kind", "code", "q_code", full)
    }
}
