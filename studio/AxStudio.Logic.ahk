#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Bind.ahk
#Include %A_LineFile%\..\AxStudio.Flow.ahk
#Include %A_LineFile%\..\AxStudio.Catalog.ahk
#Include %A_LineFile%\..\AxStudio.Helpers.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk
#Include %A_LineFile%\..\AxStudio.Wizards.ahk
#Include %A_LineFile%\..\AxStudio.Panes.ahk

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
;  AxStudio.Logic.ahk -- what the design DOES, in one place.
;
;  Values, bindings, rules, states and code used to be four text boxes tucked
;  under the window's own settings, in among its title bar and its minimum
;  height. They are not settings. They are the behaviour of the program, and
;  they refer to each other constantly: a rule names a control and a state, a
;  binding names a control and a value, a state names controls.
;
;  So each one is listed as what it is, in plain words, with two things beside
;  it that the text boxes could never show:
;
;      where it is used   the count, and a click that takes you there
;      whether it works   a name that resolves to nothing is called out red,
;                         here, rather than in the exported script
;
;  The text is still the truth. Every group has "Edit as text" and the box is
;  the same one it always was -- this is a reading of it, kept honest by being
;  parsed from it every time.
; =============================================================================
class AxLogic {
    ; What the pane shows in expanded form, by group key. A group opened here
    ; shows its raw text box; otherwise it shows the readable list.
    static Raw := Map()
    ; True while a section is drawn as the one panel of a rail page, rather
    ; than as a group among others.
    static Panel := false

    ; A group header with a toggle between the readable list and the text.
    ; `lead` is one sentence saying what the section is for, which a page has
    ; room for and a pane never did.
    ; With several windows the page scrolls past its window picker, so the
    ; sections that belong to one window say which in their own heading.
    static OfWin(s) => s.P.Wins.Length > 1 ? " for " s.P.W.Name : ""
    static Wrap(s, key, title, tools, listHtml, rawHtml, lead := "") {
        raw := AxLogic.Raw.Has(key)
        if AxLogic.Panel {
            alt := '<span class="axd-hbtn' (raw ? " on" : "") '" data-do="logic.raw.' key '">'
                 . (raw ? "Back to the list" : "Edit as text") '</span>'
            ; nothing there yet: the one thing to do, large, in the middle
            if (!raw && listHtml = "")
                return AxPanes.PanelHead(title, lead)
                     . '<div class="axd-rpempty"><span class="ico axd-rpbig">&#x' AxLogic.SecIcon(key) ';</span>'
                     . '<div class="axd-rpemptyt">Nothing here yet</div>'
                     . '<div class="axd-rpemptyb">' tools '</div>'
                     . '<span class="axd-lgalt" data-do="logic.raw.' key '">or write it as text</span></div>'
            return AxPanes.PanelHead(title, lead, tools " " alt)
                 . '<div class="axd-rpcontent">' (raw ? rawHtml : listHtml) '</div>'
        }
        body := (lead != "" ? '<div class="axd-lglead">' lead '</div>' : "")
        ; Nothing there yet: the one thing to do, instead of an empty table, a
        ; sentence repeating the lead, and a button for text that is not there.
        if (!raw && listHtml = "")
            return AxPanes.Group(s, title, body '<div class="axd-lgnone">' tools
                 . ' <span class="axd-lgalt" data-do="logic.raw.' key '">or write it as text</span>'
                 . '</div>', "lg" key)
        body .= (raw ? rawHtml : listHtml)
             .  '<div class="axd-note"><span class="axd-hbtn' (raw ? " on" : "") '"'
             .  ' data-do="logic.raw.' key '">' (raw ? "Back to the list" : "Edit as text")
             .  '</span> ' tools '</div>'
        return AxPanes.Group(s, title, body, "lg" key)
    }

    ; ===================================================================
    static Values(s, add) {
        vars := AxBind.Vars(s.P)
        rows := ""
        for v in vars {
            if v.HasOwnProp("Setting")
                continue                            ; under Settings, with its own table
            used := AxLogic.VarUses(s, v.Name)
            rows .= '<tr' (used.Length ? "" : ' class="axd-warnrow"') '>'
                 .  '<td class="axd-lgname" data-row="edit|' AxTags.E("values|" v.Line) '">'
                 .  '<span class="ico">&#x' (v.Derived ? "E9D5" : "E8EF") ';</span>'
                 .  AxTags.E(v.Name) '</td>'
                 .  '<td class="axd-mono">' (v.Derived ? '<span class="axd-dim">worked out from </span>' : "")
                 .  AxLogic.StartsAs(v) '</td>'
                 .  '<td>' AxLogic.UseChips(s, used) '</td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("values", v.Line) '</td></tr>'
        }
        if (rows = "")
            list := ""
        else
            list := AxLogic.Table(["Value", "Starts as", "Used by", ""], rows)
        raw := add({Id: "lg_vars", L: "One per line", Kind: "multiline", Rows: 6,
                    Get: (*) => s.P.Vars, Set: (v) => (s.P.Vars := v, s.QueueLive())})
             . '<div class="axd-note"><b>name = value</b>, or <b>name &lt;- expression</b> for one '
             . 'worked out from the others.</div>'
        tools := '<span class="axd-hbtn" data-do="value.add">Add a value...</span>'
        return AxLogic.Wrap(s, "values", "Values (" vars.Length ")", tools, list, raw,
            "Variables the whole program shares. Bind one to a control and the two stay the "
            . "same; a rule can set one; your own code reads it by name.")
    }
    ; What a value starts as; a thing with fields, one chip a field
    static StartsAs(v) {
        f := v.Derived ? [] : AxBind.FieldPairs(v.Expr)
        if !f.Length
            return AxTags.E(v.Expr = "" ? '""' : v.Expr)
        h := '<span class="axd-dim">a thing with </span>'
        for x in f
            h .= '<span class="axd-chip axd-chip-plain">' AxTags.E(x.K " " x.V) '</span>'
        return h
    }
    ; Where a value is used, as chips. One that names a control goes to it,
    ; in whichever window it is in.
    static UseChips(s, used) {
        if !used.Length
            return '<span class="axd-lgwarn">not used anywhere</span>'
        h := ""
        for u in used {
            text := ((IsObject(u.W) && !AxProject.Same(u.W, s.P.W)) ? u.W.Name " > " : "") u.What
            if (u.HasOwnProp("Bad") && u.Bad)
                h .= '<span class="axd-chip axd-chip-bad" data-tip="There is no control called '
                  .  AxTags.E(u.Go) '">' AxTags.E(text) '</span>'
            else if (u.Go != "")
                h .= '<span class="axd-chip" data-logic="ctl|' AxTags.E(u.Go) '">' AxTags.E(text) '</span>'
            else
                h .= '<span class="axd-chip axd-chip-plain">' AxTags.E(text) '</span>'
        }
        return h
    }
    ; Edit and Remove at the end of a row. The row carries the line it stands
    ; for, so it can be found again by what it says.
    static Acts(kind, line, what := "Edit") {
        v := AxTags.E(kind "|" line)
        return '<span class="axd-racts">'
             . '<span class="axd-ract" data-row="edit|' v '">' what '</span>'
             . '<span class="axd-ract axd-ractdel" data-row="del|' v '"'
             . ' data-tip="Remove it. Ctrl+Z brings it back.">&#xE711;</span></span>'
    }
    static CtlChip(name, extra := "") => '<span class="axd-chip" data-logic="ctl|' AxTags.E(name) '">'
                                       . AxTags.E(name extra) '</span>'
    static Table(heads, rows) {
        h := '<table class="axd-lgt"><tr>'
        for x in heads
            h .= '<th>' x '</th>'
        return h '</tr>' rows '</table>'
    }
    ; What the page says along its top: every section and how many it holds,
    ; each one a link down to it -- five tables is a long page.
    static SecIcon(key) {
        static m := Map("values", "E8EF", "conditions", "E9D5", "hotstrings", "E8D2", "timers", "E916",
                        "bindings", "E8C8", "rules", "E945", "states", "E81E",
                        "hotkeys", "E765", "files", "E8A5", "includes", "E943", "arguments", "E756",
                        "modes", "E7E8", "tray", "E8B7", "settings", "E713", "events", "E7C1",
                        "watchers", "E8B7", "macros", "E768", "menus", "E700")
        return m.Has(key) ? m[key] : "E8A5"
    }
    ; How many of each are broken, for the red marks on the rail.
    static BadCounts(s) {
        W := s.P.W
        out := {B: 0, R: 0, H: 0}
        for b in AxBind.Binds(W)
            out.B += (AxLogic.BindWhy(s, b) != "")
        for r in AxFlow.Parse(W)
            out.R += (AxLogic.RuleWhy(s, r) != "")
        for hk in AxAsset.Hotkeys(W)
            out.H += (AxLogic.HotkeyWhy(s, hk) != "")
        return out
    }
    static Jumps(s) {
        W := s.P.W
        bad := 0
        for b in AxBind.Binds(W)
            bad += (AxLogic.BindWhy(s, b) != "")
        for r in AxFlow.Parse(W)
            bad += (AxLogic.RuleWhy(s, r) != "")
        for hk in AxAsset.Hotkeys(W)
            bad += (AxLogic.HotkeyWhy(s, hk) != "")
        J := (key, label, n) => '<span class="axd-chip" data-lgjump="' key '">' label
                              . (n != "" ? ' <span class="axd-dim">' n '</span>' : "") '</span>'
        return '<div class="axd-wspick">'
             . J("values", "Values", AxBind.Vars(s.P).Length)
             . J("bindings", "Bindings", AxBind.Binds(W).Length)
             . J("rules", "Rules", AxFlow.Parse(W).Length)
             . J("states", "States", AxFlow.States(W).Length)
             . J("hotkeys", "Hotkeys", AxAsset.Hotkeys(W).Length)
             . J("code", "Code", "")
             . (bad ? '<span class="axd-lgerr" style="margin-left:6px">' bad ' not working</span>' : "")
             . '</div>'
    }
    ; Every place a value is named: a binding, a rule, or code.
    static VarUses(s, name) {
        out := []
        for w in s.P.Wins {
            for b in AxBind.Binds(w)                   ; the value, or a field of it (Hero.HP)
                if (b.Var = name || InStr(b.Var, name ".") = 1)
                    out.Push({W: w, What: "bound to " b.Ctl (b.Var != name ? " (" SubStr(b.Var, StrLen(name) + 2) ")" : ""),
                              Go: b.Ctl, Bad: !IsObject(s.P.FindByName(b.Ctl))})
            for fl in AxFlow.Parse(w) {
                who := AxLogic.FirstWord(fl.Arg)
                if (InStr("|assign|add|take|", "|" fl.Verb "|") && (who = name || InStr(who, name ".") = 1))
                    out.Push({W: w, What: (fl.Verb = "assign" ? "set" : fl.Verb = "add" ? "added to" : "taken from")
                                        . " by " fl.Ctl " " fl.Ev, Go: fl.Ctl})
            }
        }
        n := AxLogic.CodeHits(s, name)
        if n
            out.Push({W: "", What: n " mention" (n = 1 ? "" : "s") " in code", Go: ""})
        return out
    }

    ; ===================================================================
    static Bindings(s, add) {
        W := s.P.W
        binds := AxBind.Binds(W)
        rows := ""
        for b in binds {
            bad := AxLogic.BindWhy(s, b)
            rows .= '<tr' (bad != "" ? ' class="axd-badrow"' : "") '>'
                 .  '<td class="axd-narrow">' AxLogic.CtlChip(b.Ctl, b.Prop != "" ? "." b.Prop : "") '</td>'
                 .  '<td class="axd-mono axd-narrow">' (b.Both ? "&lt;-&gt;" : "&lt;-") '</td>'
                 .  '<td class="axd-lgname" data-lgjump="values">'
                 .  '<span class="ico">&#xE8EF;</span>' AxTags.E(b.Var) '</td>'
                 .  '<td>' (bad != "" ? '<span class="axd-lgerr">' AxTags.E(bad) '</span>'
                          : '<span class="axd-dim">' (b.Both ? "each follows the other"
                                                             : "the control follows the value") '</span>')
                 .  '</td><td class="axd-narrow">' AxLogic.Acts("bindings", b.Line) '</td></tr>'
        }
        if (rows = "")
            list := ""
        else
            list := AxLogic.Table(["Control", "", "Value", "", ""], rows)
        raw := add({Id: "lg_binds", L: "One per line", Kind: "multiline", Rows: 5,
                    Get: (*) => W.Binds, Set: (v) => (W.Binds := v, s.QueueLive())})
             . '<div class="axd-note"><b>control.Prop &lt;-&gt; value</b> keeps the two the same, '
             . '<b>&lt;-</b> only follows the value. Leave the property off and it uses whichever '
             . 'one holds that control&#39;s value.</div>'
        ; the controls that could be bound and are not: one click each
        free := AxPanes.Unbound(s)
        if free.Length {
            chips := ""
            for n in free {
                e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
                chips .= '<span class="axd-bindq" data-bindq="' AxTags.E(n.Name) '" data-tip="Bind it to a new value, '
                      .  AxTags.E(AxPanes.NewVarFor(s, n)) '">'
                      .  '<span class="ico">&#x' (IsObject(e) ? e.Icon : "E8C8") ';</span><b>' AxTags.E(n.Name) '</b>'
                      .  '<small>' AxTags.E(AxActs.Holds(n.Type)) '</small><span class="axd-bindplus ico">&#xE710;</span></span>'
            }
            list .= '<div class="axd-rpsub">Ready to bind (' free.Length ')</div>'
                 .  '<div class="axd-bindqs">' chips '</div>'
                 .  '<div class="axd-note">Click one to keep it in step with a new value of its own. '
                 .  '<span class="axd-hbtn" data-do="bind.all">Bind them all</span></div>'
        }
        tools := '<span class="axd-hbtn" data-do="bind.add">Bind a control...</span>'
        return AxLogic.Wrap(s, "bindings", "Bindings" AxLogic.OfWin(s) " (" binds.Length ")", tools, list, raw,
            "A control and a value kept the same, in this window. Nothing has to copy one into "
            . "the other.")
    }
    static BindWhy(s, b) {
        if !IsObject(s.P.FindByName(b.Ctl))
            return "there is no control called " b.Ctl
        if !AxBind.HasVar(s.P, b.Var)
            return "there is no value called " b.Var
        return ""
    }

    ; ===================================================================
    static Rules(s, add) {
        W := s.P.W
        rules := AxFlow.Parse(W)
        rows := ""
        for r in rules {
            bad := AxLogic.RuleWhy(s, r)
            rows .= '<tr' (bad != "" ? ' class="axd-badrow"' : "") '>'
                 .  '<td class="axd-narrow">' AxLogic.CtlChip(r.Ctl) ' <span class="axd-dim">'
                 .  AxTags.E(AxWiz.EventWord(AxFlow.EvBase(r.Ev)) (AxFlow.EvQual(r.Ev) != "" ? ": " AxFlow.EvQual(r.Ev) : "")) '</span></td>'
                 .  '<td class="axd-lgthen" data-row="edit|' AxTags.E("rules|" r.Line) '">'
                 .  '<span class="ico">&#xE72A;</span>' AxTags.E(AxLogic.RuleWords(r)) '</td>'
                 .  '<td>' (bad != "" ? '<span class="axd-lgerr">' AxTags.E(bad) '</span>' : "") '</td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("rules", r.Line) '</td></tr>'
        }
        if (rows = "")
            list := ""
        else
            list := AxLogic.Table(["When", "Then", "", ""], rows)
        raw := add({Id: "lg_flows", L: "One per line", Kind: "multiline", Rows: 6,
                    Get: (*) => W.Flows, Set: (v) => (W.Flows := v, s.QueueLive())})
             . '<div class="axd-note"><b>control Event -&gt; verb what</b>. ' AxLogic.VerbWords()
             . '</div>'
        tools := '<span class="axd-hbtn" data-do="flow.add">Add a rule...</span>'
               . (rules.Length ? ' <span class="axd-hbtn" data-do="steps.show">See them step by step</span>' : "")
        return AxLogic.Wrap(s, "rules", "Rules" AxLogic.OfWin(s) " (" rules.Length ")", tools, list, raw,
            "Behaviour without code: when this control does that, do this. Each one becomes a "
            . "few lines of the handler it belongs to -- and Steps shows them with any code "
            . "that runs after, where more steps can be added.")
    }
    static VerbWords() {
        out := ""
        for x in AxWiz.Verbs
            out .= (out = "" ? "Verbs: " : ", ") x.V
        return out "."
    }
    static RuleWords(r) {
        x := AxWiz.Verb(r.Verb)
        return (IsObject(x) ? x.L : r.Verb) (r.Arg != "" ? "  " r.Arg : "")
    }
    static RuleWhy(s, r) {
        if !IsObject(s.P.FindByName(r.Ctl))
            return "there is no control called " r.Ctl
        if !IsObject(AxWiz.Verb(r.Verb))
            return r.Verb " is not one of the verbs"
        who := AxLogic.FirstWord(r.Arg)
        x := AxWiz.Verb(r.Verb)
        if (x.Who = "ctl" && who != "" && !IsObject(s.P.FindByName(who)))
            return "there is no control called " who
        if (x.Who = "win" && who != "" && !IsObject(s.P.WinByName(who)))
            return "there is no window called " who
        if (x.Who = "var" && who != "" && !AxBind.HasVar(s.P, who))
            return "there is no value called " who
        if (x.Who = "state" && who != "" && !AxLogic.HasState(s.P.W, who))
            return "there is no state called " who
        if (x.Who != "" && who = "")
            return "it does not say which one"
        return ""
    }
    static HasState(w, name) {
        for st in AxFlow.States(w)
            if (st.Name = name)
                return true
        return false
    }

    ; ===================================================================
    static States(s, add) {
        W := s.P.W
        states := AxFlow.States(W)
        rows := ""
        for st in states {
            n := AxLogic.StateUses(W, st.Name)
            what := ""
            for x in st.Sets
                what .= AxLogic.CtlChip(x.Ctl, "." x.Prop) '<span class="axd-mono"> = '
                     .  AxTags.E(x.Val) '</span> '
            rows .= '<tr' (n ? "" : ' class="axd-warnrow"') '>'
                 .  '<td class="axd-lgname" data-logic="state|' AxTags.E(st.Name) '">'
                 .  '<span class="ico">&#xE81E;</span>' AxTags.E(st.Name) '</td>'
                 .  '<td>' what '</td>'
                 .  '<td>' (n ? '<span class="axd-dim">' n (n = 1 ? " rule applies it" : " rules apply it") '</span>'
                             : '<span class="axd-lgwarn">nothing applies it</span>') '</td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("states", st.Name) '</td></tr>'
        }
        if (rows = "")
            list := ""
        else
            list := AxLogic.Table(["State", "What it changes", "Applied by", ""], rows)
        raw := add({Id: "lg_states", L: "One per line", Kind: "multiline", Rows: 5,
                    Get: (*) => W.States, Set: (v) => (W.States := v, s.QueueLive())})
             . '<div class="axd-note"><b>name: ctl.Prop = value, ctl.Prop = value</b>. Several '
             . 'lines may share a name.</div>'
        tools := '<span class="axd-hbtn" data-do="state.add">Add a state...</span>'
        return AxLogic.Wrap(s, "states", "States" AxLogic.OfWin(s) " (" states.Length ")", tools, list, raw,
            "A named set of changes -- busy, signed in, editing -- that a rule applies in one go.")
    }
    ; ===================================================================
    static HotkeyList(s, add) {
        W := s.P.W
        hks := AxAsset.Hotkeys(W)
        rows := ""
        for hk in hks {
            bad := AxLogic.HotkeyWhy(s, hk)
            rows .= '<tr' (bad != "" ? ' class="axd-badrow"' : "") '>'
                 .  '<td class="axd-lgname" data-row="edit|' AxTags.E("hotkeys|" hk["line"]) '">'
                 .  '<span class="ico">&#xE765;</span>' AxTags.E(AxLogic.KeyWords(hk["hk"])) '</td>'
                 .  '<td><span class="axd-dim">' AxTags.E(AxLogic.ScopeWords(hk)) '</span></td>'
                 .  '<td>' AxTags.E(AxLogic.HotkeyDoes(hk)) '</td>'
                 .  '<td>' (bad != "" ? '<span class="axd-lgerr">' AxTags.E(bad) '</span>' : "") '</td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("hotkeys", hk["line"]) '</td></tr>'
        }
        if (rows = "")
            list := ""
        else
            list := AxLogic.Table(["Keys", "Works", "Does", "", ""], rows)
        raw := add({Id: "lg_hks", L: "One per line", Kind: "multiline", Rows: 4,
                    Get: (*) => W.Hotkeys, Set: (v) => (W.Hotkeys := v, s.QueueLive())})
             . '<div class="axd-note"><b>keys | where | what | detail</b>. Where is <b>active</b>, '
             . '<b>always</b>, <b>other:</b>a window, <b>not:</b>a window or <b>cond:</b>a condition; what is '
             . 'toast, front, toggle, open, own, steps, send, type, run or remap.</div>'
        tools := '<span class="axd-hbtn" data-do="hotkey.add">Add a hotkey...</span>'
        return AxLogic.Wrap(s, "hotkeys", "Hotkeys" AxLogic.OfWin(s) " (" hks.Length ")", tools, list, raw,
            "Key combinations and what they do. Kept as a list, so each one can be changed or "
            . "taken out again; they are written into the window's startup code on export.")
    }
    ; ^!h -> Ctrl+Alt+H
    static KeyWords(keys) {
        static names := Map("^", "Ctrl", "!", "Alt", "+", "Shift", "#", "Win")
        mods := "", i := 1
        while (i <= StrLen(keys) && InStr("^!+#<>*~$", SubStr(keys, i, 1))) {
            c := SubStr(keys, i, 1)
            if names.Has(c)
                mods .= names[c] "+"
            i++
        }
        rest := SubStr(keys, i)
        return mods (StrLen(rest) = 1 ? StrUpper(rest) : rest)
    }
    static ScopeWords(hk) => (hk["scope"] = "always") ? "everywhere"
                           : (hk["scope"] = "other") ? "in " hk["other"]
                           : (hk["scope"] = "not") ? "anywhere but " hk["other"]
                           : (hk["scope"] = "cond") ? "only when " hk["cond"]
                           : "while this window is in front"
    static HotkeyDoes(hk) {
        w := hk.Has("what") ? hk["what"] : ""
        switch hk["act"] {
        case "steps":  return w
        case "send":   return "sends " w
        case "type":   return "types " Chr(34) w Chr(34)
        case "run":    return "runs " w
        case "remap":  return "acts as " w
        case "front":  return "brings the window to the front"
        case "toggle": return "shows the window, or hides it"
        case "open":   return "opens " hk["win"]
        case "own":    return "calls " hk["fn"] "()"
        }
        return "shows " Chr(34) hk["msg"] Chr(34)
    }
    static HotkeyWhy(s, hk) {
        if (hk["scope"] = "cond" && !AxAuto.HasCond(s.P, hk["cond"]))
            return "there is no condition called " hk["cond"]
        if (hk["act"] = "open" && !IsObject(s.P.WinByName(hk["win"])))
            return "there is no window called " hk["win"]
        if (hk["act"] = "own" && hk["fn"] = "")
            return "it does not say which function"
        if (hk["scope"] = "other" && hk["other"] = "")
            return "it does not say which window"
        return ""
    }
    static StateUses(w, name) {
        n := 0
        for f in AxFlow.Parse(w)
            if (f.Verb = "state" && AxLogic.FirstWord(f.Arg) = name)
                n++
        return n
    }

    ; ===================================================================
    ; The two code blocks, and the way in to the helper library. Not editors:
    ; the editor is the code pane, which is where there is room for one.
    static Code(s) {
        W := s.P.W
        init := AxLogic.CountLines(W.Init)
        own := AxLogic.CountLines(W.Script)
        card := (which, title, n, what) => '<div class="axd-lgcard" data-code="' which '">'
            . '<span class="ico">&#xE943;</span><b>' title '</b>'
            . '<span class="axd-dim">' (n ? n " line" (n = 1 ? "" : "s") : "empty") ' -- open in Code</span>'
            . '<div class="axd-lglead" style="margin:6px 0 0">' what '</div></div>'
        lead := "The code this window runs on its own terms, beside the handlers each control "
              . "carries. Both open in the Code workspace."
        if AxLogic.Panel
            return AxPanes.PanelHead("Code" AxLogic.OfWin(s), lead,
                     '<span class="axd-hbtn" data-code="show">See the whole script</span>')
                 . '<div class="axd-lgcards">'
                 . card("init", "Startup code", init,
                        "Runs once, after the controls are built and before the window is shown.")
                 . card("script", "Your own functions", own,
                        "Appended to the file, at the top level, where a function has to be.")
                 . '</div><div class="axd-rpsub">Script helpers</div>'
                 . '<div class="axd-rpnote">Hotkeys and hotstrings, listeners for devices, the clipboard '
                 . 'and the screen, timers that do not pile up, a settings file, a tray menu, restarting '
                 . 'elevated -- ' AxHelp.All().Length ' of them, written for you.</div>'
                 . '<span class="axd-hbtn axd-go" data-do="help.add">Add a script helper...</span>'
        body := '<div class="axd-lglead">' lead '</div>'
             .  card("init", "Startup code", init,
                     "Runs once, after the controls are built and before the window is shown.")
             .  card("script", "Your own functions", own,
                     "Appended to the file, at the top level, where a function has to be.")
             .  '<div class="axd-note">'
             .  '<span class="axd-hbtn axd-go" data-do="help.add">Add a script helper...</span> '
             .  '<span class="axd-hbtn" data-code="show">See the whole script</span> '
             .  'Hotkeys and hotstrings, listeners for devices, the clipboard and the screen, '
             .  'timers that do not pile up, a settings file, a tray menu, restarting elevated -- '
             .  AxHelp.All().Length ' of them, written for you.</div>'
        return AxPanes.Group(s, "Code", body, "lgcode")
    }
    static CountLines(t) {
        n := 0
        for line in StrSplit(StrReplace(String(t), "`r", ""), "`n")
            if (Trim(line) != "")
                n++
        return n
    }
    ; A rough count of how often a name turns up in code the project owns. Not
    ; a parser -- it is a "you would break this" warning, not a promise.
    static CodeHits(s, name) {
        ; The count goes in an object rather than a plain variable: the walk
        ; takes a callback, and a closure in AutoHotkey v2 cannot be handed a
        ; reference to a local it can add to.
        box := {N: 0}
        for w in s.P.Wins {
            box.N += AxLogic.Hits(w.Init, name) + AxLogic.Hits(w.Script, name)
            s.P.Walk(w.Root, AxLogic.HitFn(name, box))
        }
        return box.N
    }
    static HitFn(name, box) => (node) => (AxLogic.NodeHits(node, name, box), false)
    static NodeHits(node, name, box) {
        for e in node.Ev
            box.N += AxLogic.Hits(e["code"], name)
    }
    static Hits(text, name) {
        t := String(text)
        if (name = "" || t = "")
            return 0
        n := 0, pos := 1, len := StrLen(t)
        while (pos <= len && (pos := RegExMatch(t, "\b\Q" name "\E\b", , pos))) {
            n++
            pos += StrLen(name)
        }
        return n
    }
    static FirstWord(s) {
        t := Trim(String(s))
        p := InStr(t, " ")
        return p ? SubStr(t, 1, p - 1) : t
    }
    static Uses(list) {
        if !list.Length
            return '<div class="axd-lgsub"><span class="axd-lgerr">nothing uses it</span></div>'
        out := ""
        for u in list
            out .= (out = "" ? "" : ", ") u.What
        return '<div class="axd-lgsub">' AxTags.E(out) '</div>'
    }
    static Empty(text) => '<div class="axd-lgempty">' AxTags.E(text) '</div>'

    ; =================================================== the script's outside
    ; Files the finished program needs, and how each one reaches whoever runs
    ; it. This is the question every script that ships an icon, a sound or a
    ; template runs into, and there was nowhere to answer it.
    static Files(s, add) {
        files := AxAsset.Files(s.P)
        rows := ""
        for f in files {
            bad := (Trim(f.Path) = "") ? "no path" : ""
            rows .= '<tr' (bad != "" ? ' class="axd-badrow"' : "") '>'
                 .  '<td class="axd-lgname" data-row="edit|' AxTags.E("files|" f.Line) '">'
                 .  '<span class="ico">&#x' AxLogic.HowIcon(f.How) ';</span>' AxTags.E(f.Name) '</td>'
                 .  '<td class="axd-mono">' AxTags.E(f.Path) '</td>'
                 .  '<td>' AxTags.E(AxAsset.HowWords(f.How))
                 .  '<br><span class="axd-dim">' AxTags.E(AxAsset.FileFn(f.Name) "()") ' gives you '
                 .  (f.How = "resource" ? "the content" : "the path") '</span>'
                 .  (bad != "" ? '<br><span class="axd-lgerr">' AxTags.E(bad) '</span>' : "") '</td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("files", f.Line) '</td></tr>'
        }
        list := (rows = "") ? "" : AxLogic.Table(["File", "From", "How", ""], rows)
        raw := add({Id: "lg_files", L: "One per line", Kind: "multiline", Rows: 5,
                    Get: (*) => s.P.Files, Set: (v) => (s.P.Files := v, s.QueueLive())})
             . '<div class="axd-note"><b>name | path | how</b>, where how is <b>install</b>, '
             . '<b>resource</b> or <b>path</b>.</div>'
        tools := '<span class="axd-hbtn" data-do="file.add">Add a file...</span>'
        return AxLogic.Wrap(s, "files", "Files (" files.Length ")", tools, list, raw,
            "What the script carries: built into the exe and written out on first run, built in "
            . "and read from memory, or looked for beside the script.")
    }
    static HowIcon(how) {
        static m := Map("install", "E896", "resource", "E8F1", "path", "E8E5")
        return m.Has(how) ? m[how] : "E8A5"
    }

    static Includes(s, add) {
        incs := AxAsset.Includes(s.P)
        rows := ""
        for i in incs {
            bad := AxLogic.IncludeWhy(s, i)
            rows .= '<tr' (bad != "" ? ' class="axd-badrow"' : "") '>'
                 .  '<td class="axd-lgname" data-row="edit|' AxTags.E("includes|" i.Line) '">'
                 .  '<span class="ico">&#xE943;</span>' AxTags.E(i.Path) '</td>'
                 .  '<td>' (bad != "" ? '<span class="axd-lgerr">' AxTags.E(bad) '</span>'
                          : '<span class="axd-dim">' (i.Lib ? "found on the library path"
                                                          : "relative to the exported script") '</span>')
                 .  '</td><td class="axd-narrow">' AxLogic.Acts("includes", i.Line) '</td></tr>'
        }
        list := (rows = "") ? "" : AxLogic.Table(["File", "", ""], rows)
        raw := add({Id: "lg_incs", L: "One per line", Kind: "multiline", Rows: 4,
                    Get: (*) => s.P.Includes, Set: (v) => (s.P.Includes := v, s.QueueLive())})
             . '<div class="axd-note">A path, or <b>&lt;Name&gt;</b> for a file in a Lib folder -- AutoHotkey looks '
             . 'in the program&#39;s own Lib folder, then in Documents\AutoHotkey\Lib. They come after AxGui, so they can use it.</div>'
        tools := '<span class="axd-hbtn" data-do="include.add">Add a code file...</span>'
        return AxLogic.Wrap(s, "includes", "Code files (" incs.Length ")", tools, list, raw,
            "Your own .ahk files this program uses -- functions you keep in a file of their own, shared between "
            . "programs. AxGui, the libraries (App &gt; Libraries) and the extra controls the design uses are added for you.")
    }
    ; A relative include is relative to the EXPORTED script, which may not be
    ; anywhere near the project -- so this only says what it can be sure of.
    static IncludeWhy(s, i) {
        if i.Lib
            return ""
        if RegExMatch(i.Path, "^[A-Za-z]:\\") && !FileExist(i.Path)
            return "there is no file at " i.Path
        return ""
    }

    static Arguments(s, add) {
        args := AxAsset.Args(s.P)
        rows := ""
        for a in args
            rows .= '<tr><td class="axd-lgname" data-row="edit|' AxTags.E("arguments|" a.Line) '">'
                 .  '<span class="ico">&#xE756;</span>--' AxTags.E(a.Name) '</td>'
                 .  '<td class="axd-mono">' AxTags.E(a.Def = "" ? Chr(34) Chr(34) : a.Def) '</td>'
                 .  '<td><span class="axd-dim">' AxTags.E(a.Desc != "" ? a.Desc
                                                   : "a global your code can read anywhere") '</span></td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("arguments", a.Line) '</td></tr>'
        list := (rows = "") ? "" : AxLogic.Table(["Option", "When not given", "For", ""], rows)
        raw := add({Id: "lg_args", L: "One per line", Kind: "multiline", Rows: 4,
                    Get: (*) => s.P.Args, Set: (v) => (s.P.Args := v, s.QueueLive())})
             . '<div class="axd-note"><b>name | when not given | what it is for</b>. Given as '
             . '<b>--name value</b>, or <b>--name</b> on its own to turn something on.</div>'
        tools := '<span class="axd-hbtn" data-do="arg.add">Add an option...</span>'
        return AxLogic.Wrap(s, "arguments", "Command-line options (" args.Length ")", tools, list, raw,
            "What the program can be started with -- <b>MyApp.exe --user Sam</b>, from a shortcut or another script. "
            . "Each becomes a value of that name your code and rules can read, set before the window opens.")
    }

    static ModeList(s, add) {
        modes := AxAsset.Modes(s.P)
        rows := ""
        for m in modes {
            what := ""
            for step in m.Steps
                what .= (what = "" ? "" : ", ") step
            rows .= '<tr><td class="axd-lgname" data-row="edit|' AxTags.E("modes|" m.Line) '">'
                 .  '<span class="ico">&#xE7C4;</span>' AxTags.E(m.Name) '</td>'
                 .  '<td>' AxTags.E(what != "" ? what : "does nothing yet") '</td>'
                 .  '<td class="axd-mono axd-dim">--mode ' AxTags.E(m.Name) '</td>'
                 .  '<td class="axd-narrow">' AxLogic.Acts("modes", m.Line) '</td></tr>'
        }
        list := (rows = "") ? "" : AxLogic.Table(["Mode", "Does", "Started with", ""], rows)
        raw := add({Id: "lg_modes", L: "One per line", Kind: "multiline", Rows: 4,
                    Get: (*) => s.P.Modes, Set: (v) => (s.P.Modes := v, s.QueueLive())})
             . '<div class="axd-note"><b>name | verb what, verb what</b>. The verbs are the '
             . 'ones a rule uses: toast, page, state, show, hide, open, run, exit.</div>'
        tools := '<span class="axd-hbtn" data-do="mode.add">Add a way to start...</span>'
        return AxLogic.Wrap(s, "modes", "Ways to start (" modes.Length ")", tools, list, raw,
            "A named way of starting -- setup, quiet, kiosk -- that does its steps as the program opens. Picked with "
            . "<b>--mode setup</b> on the command line (a shortcut can carry it), or from code with Mode(" Chr(34) "setup" Chr(34) ").")
    }

    static TrayGroup(s, add) {
        set := Trim(String(s.P.Tray)) != ""
        cfg := AxAsset.Tray(s.P)
        list := ""
        if !set
            list := AxLogic.Empty("AutoHotkey's own tray icon and menu. Set this and the "
                                . "script gets yours instead -- or no icon at all.")
        else {
            list := '<div class="axd-lg" data-do="tray.edit">'
                 .  '<span class="ico">&#x' (cfg.Show ? "E8B7" : "ED1A") ';</span>'
                 .  '<span class="axd-lgname">' (cfg.Show ? "Shown" : "Hidden") '</span>'
                 .  '<span class="axd-lgval">' AxTags.E(cfg.Tip != "" ? cfg.Tip : "no tooltip") '</span>'
                 .  '<div class="axd-lgsub">'
                 .  (cfg.Show ? (cfg.Items.Length ? cfg.Items.Length " menu item"
                                                  . (cfg.Items.Length = 1 ? "" : "s")
                                                  : "AutoHotkey&#39;s own menu")
                              : "No tray icon, so no tray menu to quit it from: give it another way out (a button, a hotkey)")
                 .  (cfg.Icon != "" ? "<br>icon: " AxTags.E(cfg.Icon) : "")
                 .  '</div></div>'
        }
        raw := add({Id: "lg_tray", L: "One per line", Kind: "multiline", Rows: 5,
                    Get: (*) => s.P.Tray, Set: (v) => (s.P.Tray := v, s.QueueLive())})
             . '<div class="axd-note"><b>show</b>, <b>icon</b>, <b>tip</b> as '
             . '<b>name = value</b>; every other line is a menu item, as '
             . '<b>Label | code</b>.</div>'
        tools := '<span class="axd-hbtn" data-do="tray.edit">' (set ? "Change it..." : "Set it up...")
               . '</span>'
        return AxLogic.Wrap(s, "tray", "Tray icon", tools, list, raw,
            "The small icon by the clock, and the menu a right-click on it opens. A window that starts hidden "
            . "is brought up from here, or by a hotkey.")
    }

    ; ------------------------------------------------------------- clicks
    ; A row is a way in: clicking one takes you to the thing it names.
    static Click(s, ev) {
        v := s.UpAttr(ev.srcElement, "data-logic")
        if (v = "")
            return false
        p := InStr(v, "|")
        kind := SubStr(v, 1, p - 1), name := SubStr(v, p + 1)
        if (kind = "ctl") {
            n := s.P.FindByName(name)
            if IsObject(n)
                s.GoToNode(n.Id)
            else
                s.Status("msg", "There is no control called " name " any more.")
            return true
        }
        ; The rest have no control to go to, so they open the text they are
        ; written in, which is where they can be changed.
        static where := Map("var", "values", "state", "states", "file", "files",
                            "arg", "arguments", "mode", "modes")
        if where.Has(kind) {
            AxLogic.Raw[where[kind]] := 1
            s.Reflect(false)
            s.Status("msg", "Showing the text, so you can change " name " where it is written.")
            return true
        }
        return false
    }
    static ToggleRaw(s, key) {
        if AxLogic.Raw.Has(key)
            AxLogic.Raw.Delete(key)
        else
            AxLogic.Raw[key] := 1
        s.Reflect(false)
    }
}
