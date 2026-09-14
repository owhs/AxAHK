#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Form.ahk
#Include %A_LineFile%\..\AxStudio.Catalog.ahk
#Include %A_LineFile%\..\AxStudio.Bind.ahk
#Include %A_LineFile%\..\AxStudio.Gen.ahk
#Include %A_LineFile%\..\AxStudio.Templates.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk
#Include %A_LineFile%\..\AxStudio.Pre.ahk
#Include %A_LineFile%\..\AxStudio.Build.ahk

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
;  AxStudio.Wizards.ahk -- every "add a ..." in one place, and each one a
;  single form.
;
;  What was here before was a chain: a menu, then another menu, then a text box
;  you had to type "3 x 2 Button" into so a regex could pull it apart. Three of
;  those chains compared the *label* of the button that was pressed against the
;  *number* 1, so they were dead -- Add did nothing, and Cancel did the same
;  thing Add was supposed to. Nobody could tell, because a wizard that quietly
;  does nothing looks exactly like one you cancelled.
;
;  Every wizard here is one AxForm: all of the questions at once, a live
;  preview of the line it is about to write, and a button that says why it is
;  greyed out. Nothing is typed in a syntax you have to know first.
; =============================================================================
class AxWiz {
    ; ------------------------------------------------------------- helpers
    ; "Button:Button|Edit:Text box|..." -- every control the toolbox offers,
    ; in toolbox order, for a dropdown.
    static TypeOpts(boxes := "") {
        out := ""
        for t in AxCat.Order {
            e := AxCat.Get(t)
            if (boxes = "box" && !e.Box)
                continue
            if (boxes = "leaf" && e.Box)
                continue
            out .= (out = "" ? "" : "|") t ":" e.Label
        }
        return out
    }
    static NameOpts(list, none := "") {
        out := (none != "") ? ":" none : ""
        for v in list
            out .= (out = "" ? "" : "|") v ":" v
        return out
    }
    static CtlOpts(s, w := "") {
        out := ""
        for n in s.NamedIn(IsObject(w) ? w : s.P.W)
            out .= (out = "" ? "" : "|") n.Name ":" n.Name
              . " (" (AxCat.Has(n.Type) ? AxCat.Get(n.Type).Label : n.Type) ")"
        return out
    }
    ; the controls a rule can manage as a list
    static ListOpts(s) {
        out := ""
        for n in s.NamedIn(s.P.W)
            if RegExMatch(n.Type, "^(ListView|TreeView|DDL|ListBox)$")
                out .= (out = "" ? "" : "|") n.Name ":" n.Name " (" AxCat.Get(n.Type).Label ")"
        return out
    }
    static EventOpts(s, ctl) {
        n := s.P.FindByName(ctl)
        names := (IsObject(n) && AxCat.Has(n.Type)) ? AxCat.Get(n.Type).Events : ["Click"]
        out := ""
        for e in names
            out .= (out = "" ? "" : "|") e ":" AxWiz.EventWord(e)
        return out
    }
    ; A handler, started from the Code workspace rather than from the canvas:
    ; which control, which event, and the function it will be.
    static AddHandler(s) {
        ctls := AxWiz.CtlOpts(s)
        if (ctls = "")
            return s.Status("msg", "Nothing in " s.P.W.Name " has a name yet -- select a control "
                                 . "on the canvas and press F2.")
        sel := s.Primary()
        want := (IsObject(sel) && sel.Name != "") ? sel.Name : AxForm.FirstOpt(ctls)
        r := AxForm.Show(s, {Title: "Add a handler", Icon: "E943", Width: 480,
            Intro: "The code that runs when a control in " s.P.W.Name " does something.",
            Fields: [
                {Id: "ctl", L: "Control", Kind: "choice", V: want, Opts: ctls},
                {Id: "ev",  L: "When it", Kind: "choice", V: "",
                 Fill: (V) => AxWiz.EventOpts(s, V["ctl"])}],
            Buttons: ["Write it", "Cancel"],
            Check: (V) => (Trim(V["ctl"]) = "" || Trim(V["ev"]) = "") ? "Pick the control and the event." : "",
            Preview: (V) => AxWiz.HandlerSig(s, V)})
        if !r.Ok
            return
        n := s.P.FindByName(r.V["ctl"])
        if IsObject(n)
            s.AddEvent(n, r.V["ev"])
    }
    static HandlerSig(s, V) {
        n := s.P.FindByName(V["ctl"])
        if (!IsObject(n) || Trim(V["ev"]) = "")
            return ""
        return AxGen.HandlerName(n, V["ev"]) "(" AxCat.Sig(V["ev"]) ") {"
    }
    static EventWord(e) {
        static w := Map("Click", "is clicked", "DoubleClick", "is double-clicked",
                        "Change", "changes", "ContextMenu", "is right-clicked",
                        "Focus", "takes focus", "Blur", "loses focus",
                        "KeyDown", "gets a key down", "KeyUp", "gets a key up",
                        "MouseDown", "is pressed", "MouseUp", "is released",
                        "MouseOver", "is hovered", "MouseOut", "is left",
                        "Hotkey", "fires its hotkey", "Drop", "has files dropped on it",
                        "Select", "has a row selected", "Check", "has a row ticked",
                        "Activate", "has a row opened", "Preview", "previews a colour")
        if w.Has(e)
            return w[e]
        ; a pack's own event says how it reads
        return (AxCat.Events.Has(e) && AxCat.Events[e].HasOwnProp("Word") && AxCat.Events[e].Word != "") ? AxCat.Events[e].Word : e
    }
    static Q := Chr(34)
    static NL := Chr(10)
    static Int(v, d := 0) {
        v := RegExReplace(Trim(String(v)), "[^0-9\-]")
        return (v = "" || v = "-") ? d : Integer(v)
    }

    ; ============================================================ a row
    static Row(s) {
        sel := s.Primary()
        want := (IsObject(sel) && AxCat.Has(sel.Type)) ? sel.Type : "Button"
        r := AxForm.Show(s, {Title: "A row of controls", Icon: "E8FD", Width: 470,
            Intro: "Several copies of one control, side by side on one line.",
            Fields: [
                {Id: "n",    L: "How many",  Kind: "int", V: 3, Min: 1, Max: 24},
                {Id: "type", L: "Of what",   Kind: "choice", V: want, Opts: AxWiz.TypeOpts()},
                {Id: "gap",  L: "Gap",       Kind: "int", V: 8, Min: 0, Max: 200, Suffix: "px",
                 Hint: "The space between one and the next."},
                {Id: "wrap", L: "Put them in a Row container", Kind: "flag", V: 1,
                 Hint: "A Row keeps them together, so moving one moves the lot."}],
            Buttons: ["Add the row", "Cancel"],
            Check: (V) => (AxWiz.Int(V["n"]) < 1) ? "One at the very least." : "",
            Preview: (V) => AxWiz.Int(V["n"]) " x " AxWiz.Label(V["type"])
                          . ", " AxWiz.Int(V["gap"]) "px apart"
                          . (V["wrap"] ? ", inside a Row" : "")})
        if !r.Ok
            return
        n := Min(24, Max(1, AxWiz.Int(r.V["n"], 3)))
        type := r.V["type"], gap := AxWiz.Int(r.V["gap"], 8)
        if !AxCat.Has(type)
            return
        s.Mark()
        parent := s.InsertParent()
        if r.V["wrap"] {
            box := s.P.NewNode("Row")
            s.P.Insert(parent, box)
            parent := box
        }
        made := []
        loop n {
            c := s.P.NewNode(type)
            c.L["place"] := (A_Index = 1) ? "flow" : "same"
            if (A_Index > 1 && gap != 8)
                c.L["gap"] := gap
            s.P.Insert(parent, c)
            made.Push(c.Id)
        }
        s.SelIds := made
        s.Refresh()
        s.PushCompletions()
        s.Status("msg", "Added " n " " AxWiz.Label(type) (n = 1 ? "" : "s") ".")
    }
    static Label(type) => AxCat.Has(type) ? AxCat.Get(type).Label : type

    ; =========================================================== a grid
    static Grid(s) {
        sel := s.Primary()
        want := (IsObject(sel) && AxCat.Has(sel.Type)) ? sel.Type : "Button"
        r := AxForm.Show(s, {Title: "A grid of controls", Icon: "F0E2", Width: 470,
            Intro: "The same control, repeated across and down.",
            Fields: [
                {Id: "cols", L: "Across",  Kind: "int", V: 3, Min: 1, Max: 12},
                {Id: "rows", L: "Down",    Kind: "int", V: 2, Min: 1, Max: 12},
                {Id: "type", L: "Of what", Kind: "choice", V: want, Opts: AxWiz.TypeOpts()},
                {Id: "wrap", L: "Put each row in a Row container", Kind: "flag", V: 1,
                 Hint: "Without this they all land in one long line that wraps where it happens to."}],
            Buttons: ["Add the grid", "Cancel"],
            Check: (V) => (AxWiz.Int(V["cols"]) * AxWiz.Int(V["rows"]) > 144)
                        ? "That is more than 144 controls." : "",
            Preview: (V) => AxWiz.Int(V["cols"]) " across x " AxWiz.Int(V["rows"]) " down = "
                          . AxWiz.Int(V["cols"]) * AxWiz.Int(V["rows"]) " " AxWiz.Label(V["type"]) "s"})
        if !r.Ok
            return
        cols := Min(12, Max(1, AxWiz.Int(r.V["cols"], 3)))
        rows := Min(12, Max(1, AxWiz.Int(r.V["rows"], 2)))
        type := r.V["type"]
        if !AxCat.Has(type)
            return
        s.Mark()
        top := s.InsertParent()
        made := []
        loop rows {
            parent := top
            if r.V["wrap"] {
                box := s.P.NewNode("Row")
                s.P.Insert(top, box)
                parent := box
            }
            loop cols {
                c := s.P.NewNode(type)
                c.L["place"] := (A_Index = 1) ? "flow" : "same"
                s.P.Insert(parent, c)
                made.Push(c.Id)
            }
        }
        s.SelIds := made
        s.Refresh()
        s.PushCompletions()
        s.Status("msg", "Added a " cols " x " rows " grid of " AxWiz.Label(type) "s.")
    }

    ; ======================================================== spacing
    static Spacing(s) {
        nodes := s.SelNodes()
        if !nodes.Length
            return s.Status("msg", "Select the controls to space first.")
        r := AxForm.Show(s, {Title: "Spacing", Icon: "E799", Width: 450,
            Intro: nodes.Length " control" (nodes.Length = 1 ? "" : "s") " selected.",
            Fields: [
                {Id: "gap", L: "Beside",  Kind: "int", V: 8, Min: 0, Max: 200, Suffix: "px",
                 Hint: "Only applies to controls that sit on the same line as the one before."},
                {Id: "top", L: "Above",   Kind: "int", V: 0, Min: 0, Max: 200, Suffix: "px",
                 Hint: "Zero clears it, so the stylesheet's own spacing comes back."},
                {Id: "dogap", L: "Set the space beside", Kind: "flag", V: 1},
                {Id: "dotop", L: "Set the space above",  Kind: "flag", V: 1}],
            Buttons: ["Apply", "Cancel"],
            Check: (V) => (!V["dogap"] && !V["dotop"]) ? "Nothing to change." : "",
            Preview: (V) => (V["dogap"] ? "gap " AxWiz.Int(V["gap"]) "px" : "")
                          . (V["dogap"] && V["dotop"] ? ",  " : "")
                          . (V["dotop"] ? "top " AxWiz.Int(V["top"]) "px" : "")})
        if !r.Ok
            return
        s.Mark()
        gap := AxWiz.Int(r.V["gap"], 8), top := AxWiz.Int(r.V["top"], 0)
        for n in nodes {
            if (r.V["dogap"] && n.Lay("place") = "same")
                n.L["gap"] := gap
            if r.V["dotop"]
                n.L["top"] := (top = 0) ? "" : top
        }
        s.Refresh()
        s.Status("msg", "Spacing applied to " nodes.Length " control"
                      . (nodes.Length = 1 ? "" : "s") ".")
    }

    ; ======================================================== a hotkey
    ; old: one of AxAsset.Hotkeys, to change it rather than add one.
    static Hotkey(s, old := "") {
        wins := AxWiz.NameOpts(s.WinNames())
        O := (k, d) => (IsObject(old) && old.Has(k) && old[k] != "") ? old[k] : d
        conds := AxAutoUi.CondOpts(s.P, false)
        ; the prefixes and the " up" are the keys' own, shown as choices
        k0 := O("hk", "^!h")
        up := (SubStr(k0, -3) = " up")
        if up
            k0 := SubStr(k0, 1, -3)
        pre := RegExMatch(k0, "^[~*$]+", &pm) ? pm[0] : ""
        k0 := SubStr(k0, StrLen(pre) + 1)
        scopes := [{V: "active", L: "Only while this window is in front", Icon: "E7C4",
                    Desc: "The usual choice for a shortcut that belongs to your window."},
                   {V: "always", L: "Everywhere, all the time", Icon: "E80F",
                    Desc: "A system-wide hotkey. Careful -- it takes the key off every other program."},
                   {V: "other",  L: "Only while another program is in front", Icon: "E737",
                    Desc: "Give the window's title, class or process below."},
                   {V: "not",    L: "Everywhere but one program", Icon: "E711",
                    Desc: "Say which program below; there the key does what it always did."}]
        if (conds != "")
            scopes.Push({V: "cond", L: "Only when a condition holds", Icon: "E9D5",
                         Desc: "One of Logic's conditions -- working hours, CapsLock on, a program in front."})
        r := AxForm.Show(s, {Title: IsObject(old) ? "Change a hotkey" : "Add a hotkey",
            Icon: "E765", Width: 500,
            Intro: "Press the combination you want in the box -- it records what you press.",
            Fields: [
                {Id: "hk",  L: "The keys", Kind: "hotkey", V: k0},
                {Id: "pass", L: "Let the keys through to the program too (~)", Kind: "flag", V: InStr(pre, "~") ? 1 : 0},
                {Id: "any",  L: "Whatever else is held down (*)", Kind: "flag", V: InStr(pre, "*") ? 1 : 0},
                {Id: "hook", L: "Not set off by its own Send ($)", Kind: "flag", V: InStr(pre, "$") ? 1 : 0},
                {Id: "up",   L: "When the key comes back up", Kind: "flag", V: up ? 1 : 0},
                {Id: "s1",  L: "When it works", Kind: "heading"},
                {Id: "scope", Kind: "pick", L: "", V: O("scope", "active"), Items: scopes},
                {Id: "cond", L: "Condition", Kind: "choice", V: O("cond", ""), Opts: conds != "" ? conds : "-:(none)",
                 When: (V) => V["scope"] = "cond"},
                {Id: "other", L: "That window", Kind: "text", V: O("other", "ahk_exe notepad.exe"),
                 Hint: "A WinTitle: some text from the title, ahk_class Notepad, ahk_exe notepad.exe.",
                 When: (V) => V["scope"] = "other" || V["scope"] = "not"},
                {Id: "s2",  L: "What it does", Kind: "heading"},
                {Id: "act", Kind: "pick", L: "", V: O("act", "toast"), Items: [
                    {V: "toast",  L: "Show a message in the window", Icon: "E789", Desc: "g.Toast(...)"},
                    {V: "front",  L: "Bring the window to the front", Icon: "E8A7",
                     Desc: "Show it and activate it -- the usual pair for a global hotkey."},
                    {V: "toggle", L: "Show it, or hide it if it is already up", Icon: "E7E8",
                     Desc: "The one most tray utilities want."},
                    {V: "open",   L: "Open another window", Icon: "E8BD", Desc: "Calls its builder."},
                    {V: "own",    L: "Call a function you write", Icon: "E943",
                     Desc: "Writes an empty function for you and calls it."},
                    {V: "steps",  L: "Do some steps", Icon: "E945",
                     Desc: "The rule words, with commas: run notepad.exe, wait 500, type Hello."},
                    {V: "send",   L: "Send other keys", Icon: "E765", Desc: "In Send's own terms: ^c, {Enter}, !{Tab}."},
                    {V: "type",   L: "Type some text", Icon: "E8D2", Desc: "Exactly as written, braces and all."},
                    {V: "run",    L: "Run a program, a file or a web page", Icon: "E8A7", Desc: "Anything Run() opens."},
                    {V: "remap",  L: "Be another key", Icon: "E8AB",
                     Desc: "Held down as long as this one is: CapsLock as Ctrl, a mouse button as Enter."}]},
                {Id: "what", L: "Which", Kind: "text", V: O("what", ""),
                 Hint: "Steps: toast Hi, run notepad.exe, send ^v, set count 5, start clock.  Keys: ^c.  Another key: Ctrl.",
                 When: (V) => InStr("|steps|send|type|run|remap|", "|" V["act"] "|")},
                {Id: "win", L: "Which window", Kind: "choice", V: O("win", ""), Opts: wins,
                 When: (V) => V["act"] = "open"},
                {Id: "fn",  L: "Function name", Kind: "text", V: O("fn", "OnHotkey"),
                 When: (V) => V["act"] = "own"},
                {Id: "msg", L: "Message", Kind: "text", V: O("msg", "Pressed"),
                 When: (V) => V["act"] = "toast"}],
            Buttons: [IsObject(old) ? "Save" : "Add it", "Cancel"],
            Check: (V) => AxWiz.HotkeyWhy(V, wins),
            Preview: (V) => AxWiz.HotkeyCode(AxWiz.HotkeyKeys(V))})
        if !r.Ok
            return
        AxWiz.HotkeyKeys(r.V)
        ; Kept as a line in Logic > Hotkeys, not pasted into the startup code:
        ; there it can be seen, changed and taken out again.
        s.PutLine("Hotkeys", IsObject(old) ? old["line"] : "", AxAsset.HotkeyLine(r.V))
        if (r.V["act"] = "own")
            AxWiz.EnsureFn(s, AxProject.CleanName(r.V["fn"]))
        s.Refresh()
        s.Status("msg", IsObject(old) ? "Hotkey " r.V["hk"] " changed."
                                      : "Hotkey " r.V["hk"] " added. It is in Logic, under Hotkeys.")
    }
    ; The keys as AutoHotkey writes them: the choices become ~ * $ and " up".
    static HotkeyKeys(V) {
        k := RegExReplace(Trim(V["hk"]), "^[~*$]+"), k := RegExReplace(k, "i)\s+up$")
        if (k = "")
            return V
        V["hk"] := (V["pass"] ? "~" : "") (V["any"] ? "*" : "") (V["hook"] ? "$" : "") k (V["up"] ? " up" : "")
        return V
    }
    static HotkeyWhy(V, wins) {
        if (Trim(V["hk"]) = "")
            return "Press the key combination you want."
        if (V["scope"] = "cond" && (Trim(V["cond"]) = "" || V["cond"] = "-"))
            return "Pick the condition -- add one in Logic > Conditions first."
        if (InStr("|steps|send|type|run|remap|", "|" V["act"] "|") && Trim(V["what"]) = "")
            return "Say what it should do."
        if (V["scope"] = "other" && Trim(V["other"]) = "")
            return "Say which window it should work in."
        if (V["act"] = "open" && Trim(V["win"]) = "")
            return (wins = "") ? "This project has only one window, so there is nothing to open."
                               : "Pick the window to open."
        if (V["act"] = "own" && AxProject.CleanName(V["fn"]) = "")
            return "Give the function a name."
        return ""
    }
    static HotkeyCode(V) => AxAsset.HotkeyCode(V)
    ; A quoted AutoHotkey string: the quote is doubled, and nothing else needs
    ; touching -- backslash is not an escape character in v2.
    ; What goes between the quotes of a string literal. Not "" for a quote:
    ; that is v1. The escape is the backtick, and AxLit.S also escapes the
    ; backtick itself, line breaks, and the " ;" that would start a comment.
    static Esc(t) => SubStr(AxLit.S(t), 2, -1)

    ; ======================================================== a dialog
    static Dialog(s) {
        r := AxForm.Show(s, {Title: "Add a dialog", Icon: "E946", Width: 500,
            Intro: "A dialog is a call, not a layout, so this writes the line that opens one.",
            Fields: [
                {Id: "kind", Kind: "pick", L: "", V: "alert", Items: [
                    {V: "alert",   L: "Tell them something", Icon: "E946",
                     Desc: "One message and an OK button."},
                    {V: "confirm", L: "Ask yes or no", Icon: "E9CE",
                     Desc: "Returns true when they say yes."},
                    {V: "prompt",  L: "Ask for some text", Icon: "E70F",
                     Desc: "Returns what they typed, or an empty string if they cancelled."},
                    {V: "file",    L: "Ask for a file", Icon: "E8E5",
                     Desc: "The ordinary Windows file picker."},
                    {V: "folder",  L: "Ask for a folder", Icon: "E8B7",
                     Desc: "The ordinary Windows folder picker."},
                    {V: "toast",   L: "A message that fades by itself", Icon: "E789",
                     Desc: "No buttons, nothing to dismiss. Best for 'saved' and 'copied'."}],
                 Scroll: true},
                {Id: "title", L: "Title",   Kind: "text", V: "Heads up",
                 When: (V) => AxWiz.DlgHas(V["kind"], "title")},
                {Id: "text",  L: "Message", Kind: "text", V: "Something happened.",
                 When: (V) => AxWiz.DlgHas(V["kind"], "text")},
                {Id: "def",   L: "Starts as", Kind: "text", V: "Untitled",
                 When: (V) => V["kind"] = "prompt"},
                {Id: "var",   L: "Keep it in", Kind: "text", V: "answer",
                 Hint: "The variable the answer lands in.",
                 When: (V) => AxWiz.DlgHas(V["kind"], "var")},
                {Id: "where", L: "Put it in", Kind: "seg", V: "init",
                 Opts: "init:The startup code|sel:The selected control's Click",
                 Hint: "A dialog usually belongs to a button, not to startup."}],
            Buttons: ["Add it", "Cancel"],
            Check: (V) => AxWiz.DlgWhy(s, V),
            Preview: (V) => AxWiz.DlgCode(V)})
        if !r.Ok
            return
        AxWiz.Place(s, r.V["where"], AxWiz.DlgCode(r.V), "The dialog")
    }
    static DlgHas(kind, what) {
        static has := Map("alert",   "title,text",
                          "confirm", "title,text",
                          "prompt",  "title,text,var",
                          "file",    "title,var",
                          "folder",  "title,var",
                          "toast",   "text")
        return InStr("," (has.Has(kind) ? has[kind] : "") ",", "," what ",") > 0
    }
    static DlgWhy(s, V) {
        if (AxWiz.DlgHas(V["kind"], "var") && AxProject.CleanName(V["var"]) = "")
            return "Give the answer a variable to live in."
        if (V["where"] = "sel" && !IsObject(s.Primary()))
            return "Nothing is selected, so there is no Click to put it in."
        return ""
    }
    static DlgCode(V) {
        q := AxWiz.Q, nl := AxWiz.NL
        E := (k) => AxWiz.Esc(V[k])
        vn := AxProject.CleanName(V["var"])
        switch V["kind"] {
        case "confirm":
            return "if g.Confirm(" q E("text") q ", " q E("title") q ") {" nl
                 . "    g.Toast(" q "Yes" q ")" nl "}"
        case "prompt":
            return vn " := g.Prompt(" q E("text") q ", " q E("title") q ", " q E("def") q ")" nl
                 . "if (" vn " != " q q ")" nl "    g.Toast(" vn ")"
        case "file":
            return vn " := FileSelect(3, , " q E("title") q ")" nl
                 . "if (" vn " != " q q ")" nl "    g.Toast(" vn ")"
        case "folder":
            return vn " := DirSelect(, 3, " q E("title") q ")" nl
                 . "if (" vn " != " q q ")" nl "    g.Toast(" vn ")"
        case "toast":
            return "g.Toast(" q E("text") q ")"
        }
        return "g.Alert(" q E("text") q ", " q E("title") q ")"
    }

    ; ========================================================== a menu
    static Menu(s) {
        n := s.Primary()
        who := (IsObject(n) && n.Name != "") ? n.Name : ""
        r := AxForm.Show(s, {Title: "Add a menu", Icon: "E700", Width: 510,
            Intro: "One item per line. Put a hyphen on a line of its own for a separator.",
            Fields: [
                {Id: "where", Kind: "pick", L: "", V: (who != "" ? "ctl" : "page"), Items: [
                    {V: "ctl",  L: "Right-click on one control", Icon: "E7C3",
                     Desc: "The menu belongs to that control and nothing else."},
                    {V: "page", L: "Right-click anywhere in the window", Icon: "E7C4",
                     Desc: "The fallback, for clicks that hit nothing with a menu of its own."},
                    {V: "tray", L: "The tray icon", Icon: "E8B7",
                     Desc: "Replaces AutoHotkey's own tray menu."},
                    {V: "bar",  L: "The window's menu bar", Icon: "E700",
                     Desc: "Goes to the Window tab, where the bar is authored -- not to code."}]},
                {Id: "ctl", L: "Which control", Kind: "choice", V: who,
                 Fill: (V) => AxWiz.CtlOpts(s), When: (V) => V["where"] = "ctl"},
                {Id: "items", L: "The items", Kind: "code", Rows: 6,
                 V: "Refresh" AxWiz.NL "Rename" AxWiz.NL "-" AxWiz.NL "Remove",
                 When: (V) => V["where"] != "bar",
                 Hint: "Each becomes an item that shows a toast, so you have somewhere to start."}],
            Buttons: ["Add it", "Cancel"],
            Check: (V) => (V["where"] = "ctl" && Trim(V["ctl"]) = "")
                        ? "Nothing in this window is named yet -- name a control first." : "",
            Preview: (V) => (V["where"] = "bar") ? "Opens the Window tab, where the menu bar lives."
                                                 : AxWiz.MenuCode(V)})
        if !r.Ok
            return
        if (r.V["where"] = "bar") {
            s.RightTab := "page"
            s.Reflect(false)
            return s.Status("msg", "The menu bar is authored in the Window tab, under Menu bar.")
        }
        s.Mark()
        s.InsertInit(AxWiz.MenuCode(r.V))
        s.EditScript("init")
        s.Refresh()
        s.Status("msg", "Menu added to the startup code.")
    }
    static MenuCode(V) {
        q := AxWiz.Q, nl := AxWiz.NL
        lines := []
        for raw in StrSplit(String(V["items"]), "`n", "`r") {
            t := Trim(raw)
            if (t != "")
                lines.Push(t)
        }
        if !lines.Length
            lines := ["Refresh"]
        if (V["where"] = "tray") {
            out := "A_TrayMenu.Delete()" nl
            for t in lines
                out .= (t = "-")
                    ? "A_TrayMenu.Add()" nl
                    : "A_TrayMenu.Add(" q AxWiz.Esc(t) q ", (*) => g.Toast(" q AxWiz.Esc(t) q "))" nl
            out .= "A_TrayMenu.Add(" q "-" q ")" nl
                .  "A_TrayMenu.Add(" q "Exit" q ", (*) => ExitApp())"
            return out
        }
        target := (V["where"] = "ctl") ? q AxWiz.Esc(V["ctl"]) q : q "*" q
        body := ""
        for t in lines
            body .= (body = "" ? "" : "," nl)
                 .  ((t = "-") ? "    " q "-" q
                               : "    [" q AxWiz.Esc(t) q ", (*) => g.Toast(" q AxWiz.Esc(t) q ")]")
        return "g.ContextMenu(" target ", [" nl body "])"
    }

    ; ======================================================= a binding
    ; old: one of AxBind.Binds, to change it rather than add one.
    ; The controls a value can be bound to, each with what it holds and what
    ; it is bound to already -- so the list says which ones are worth picking.
    static BindCtlOpts(s) {
        out := ""
        for n in s.NamedIn(s.P.W) {
            holds := AxActs.Holds(n.Type)
            if (holds = "")
                continue
            b := AxPanes.BindOf(s, n)
            out .= (out = "" ? "" : "|") n.Name ":" n.Name "  " Chr(0x2014) " " holds
                .  (IsObject(b) ? ", bound to " b.Var : "")
        }
        return out
    }
    static Bind(s, old := "") {
        ed := IsObject(old)
        ctls := AxWiz.BindCtlOpts(s)
        if (ctls = "")
            return AxForm.Show(s, {Title: "Bind a control", Icon: "E8C8", Width: 420,
                Intro: "A binding names a control, and nothing in this window is named yet.",
                Fields: [{Id: "n", Kind: "note",
                          L: "Give a control a name first -- select it and press F2, or type one in the "
                           . "Properties tab. The name is what the generated code calls it."}],
                Buttons: ["Right you are"], CancelIndex: 0})
        sel := s.Primary()
        want := ed ? old.Ctl : (IsObject(sel) && sel.Name != "") ? sel.Name : AxForm.FirstOpt(ctls)
        vars := AxBind.Paths(s.P)                   ; a field of an object value too: Hero.HP
        ; a binding whose value has gone is offered the value back, as a new one
        have := ed ? AxBind.HasVar(s.P, old.Var) : vars.Length
        r := AxForm.Show(s, {Title: ed ? "Change a binding" : "Bind a control to a value",
            Icon: "E8C8", Width: 500,
            Intro: "A bound control and its variable stay in step: change one and the other follows.",
            Fields: [
                {Id: "ctl", L: "Control",  Kind: "choice", V: want, Opts: ctls},
                {Id: "mode", L: "Variable", Kind: "seg", V: have ? "old" : "new",
                 Opts: "old:One that exists|new:A new one"},
                {Id: "old", L: "Which",  Kind: "choice",
                 V: (ed && have) ? old.Var : vars.Length ? vars[1] : "",
                 Opts: AxWiz.NameOpts(vars), When: (V) => V["mode"] = "old"},
                {Id: "new", L: "Called", Kind: "text", V: ed ? old.Var : AxWiz.VarFor(s, want),
                 When: (V) => V["mode"] = "new",
                 Hint: "It is added to the project's values, seeded from what the control shows."},
                {Id: "way", L: "Direction", Kind: "seg",
                 V: !ed ? "auto" : old.Both ? "two" : "one",
                 Opts: "auto:Whichever fits|one:Variable to control|two:Both ways",
                 Hint: "Both ways needs a control that can change -- a text box, a switch, a slider."}],
            Buttons: [ed ? "Save" : "Bind it", "Cancel"],
            Check: (V) => AxWiz.BindWhy(s, V),
            Preview: (V) => AxWiz.BindLine(s, V)})
        if !r.Ok
            return
        s.Mark()
        name := AxWiz.BindVar(r.V)
        if !AxBind.HasVar(s.P, name) {
            n := s.P.FindByName(r.V["ctl"])
            seed := AxBind.SeedFor(n)
            cur := RTrim(String(s.P.Vars), " `t`r`n")
            s.P.Vars := (cur = "") ? name " = " seed : cur "`n" name " = " seed
        }
        line := AxWiz.BindLine(s, r.V)
        ; the form has no room for the member a binding names; keep it
        if (ed && old.Prop != "" && r.V["ctl"] = old.Ctl)
            line := RegExReplace(line, "^\Q" old.Ctl "\E", old.Ctl "." old.Prop)
        s.PutLine("Binds", ed ? old.Line : "", line, false)   ; marked above, before the value
        s.Refresh()
        s.Status("msg", r.V["ctl"] " is bound to " name ".")
    }
    static VarFor(s, ctlName) {
        n := s.P.FindByName(ctlName)
        if !IsObject(n)
            return "value"
        v := AxProject.CleanName(Trim(n.Arg) != "" ? n.Arg : n.Name)
        return (v = "") ? "value" : StrLower(SubStr(v, 1, 1)) SubStr(v, 2)
    }
    static BindVar(V) => (V["mode"] = "new") ? AxProject.CleanName(V["new"]) : V["old"]
    static BindWhy(s, V) {
        if (Trim(V["ctl"]) = "")
            return "Pick the control."
        if (AxWiz.BindVar(V) = "")
            return "Give the value a name."
        return ""
    }
    static BindLine(s, V) {
        name := AxWiz.BindVar(V)
        if (name = "" || Trim(V["ctl"]) = "")
            return ""
        if (V["way"] = "one")
            arrow := "<-"
        else if (V["way"] = "two")
            arrow := "<->"
        else
            arrow := (AxBind.PullEvent(s.P, {Ctl: V["ctl"], Prop: "", Var: name, Both: true}) != "")
                   ? "<->" : "<-"
        return V["ctl"] " " arrow " " name
    }

    ; ========================================================= a value
    ; A value is an ordinary global in the generated script. Controls bind to
    ; it, rules assign to it, and your own code reads it -- which is the whole
    ; point of having one rather than reading the control every time.
    ; old: one of AxBind.Vars, to change it rather than add one.
    static Value(s, old := "") {
        ed := IsObject(old)
        r := AxForm.Show(s, {Title: ed ? "Change the value " old.Name : "Add a value",
            Icon: "E8EF", Width: 490,
            Intro: "Shared by every window in the project. It becomes a global in the "
                 . "generated script, so your own code can read and write it too.",
            Fields: [
                {Id: "name", L: "Called", Kind: "text", V: ed ? old.Name : AxWiz.FreeVar(s),
                 Hint: "Letters, digits and underscores."},
                {Id: "how",  L: "It is",  Kind: "seg", V: (ed && old.Derived) ? "derived" : (ed && AxBind.Fields(old.Expr).Length) ? "object" : "plain",
                 Opts: "plain:A value|object:A thing with fields|derived:Worked out",
                 Hint: "A thing with fields is one value holding several: a character's Name, HP and Gold. "
                     . "Bind a control to one field (Hero.HP); a rule can add to it. "
                     . "A derived value is recomputed whenever anything it mentions changes."},
                {Id: "fields", L: "Its fields", Kind: "code", Rows: 6,
                 V: (ed && AxBind.Fields(old.Expr).Length) ? AxWiz.FieldLines(old.Expr) : 'Name = "Aria"' AxWiz.NL "HP = 20" AxWiz.NL "Gold = 0",
                 When: (V) => V["how"] = "object",
                 Hint: "One a line: a name, =, and what it starts as -- a number, a quoted string, [] for a list."},
                {Id: "val",  L: "Starts as", Kind: "text",
                 V: (ed && !old.Derived) ? old.Expr : Chr(34) Chr(34),
                 When: (V) => V["how"] = "plain",
                 Hint: "An AutoHotkey expression: a quoted string, a number, [] for a list, {A: 1, B: 2} for a thing with fields."},
                {Id: "expr", L: "Expression", Kind: "text", V: (ed && old.Derived) ? old.Expr : "",
                 When: (V) => V["how"] = "derived",
                 Hint: "An expression over the other values, like:  first "
                     . Chr(34) " " Chr(34) " last"}],
            Buttons: [ed ? "Save" : "Add it", "Cancel"],
            Check: (V) => AxWiz.ValueWhy(s, V, old),
            Preview: (V) => AxWiz.ValueLine(V)})
        if !r.Ok
            return
        s.PutLine("Vars", ed ? old.Line : "", AxWiz.ValueLine(r.V))
        s.Refresh()
        s.PushCompletions()
        s.Status("msg", (ed ? "Changed" : "Added") " the value " AxProject.CleanName(r.V["name"]) ".")
    }
    ; "Name = "Aria"" a line <-> {Name: "Aria", ...}
    static FieldsExpr(text) {
        out := ""
        for raw in StrSplit(String(text), "`n", "`r") {
            if !RegExMatch(Trim(raw), "^([A-Za-z_]\w*)\s*[=:]\s*(.*)$", &m)
                continue
            v := Trim(m[2])
            out .= (out = "" ? "" : ", ") m[1] ": " (v = "" ? Chr(34) Chr(34) : v)
        }
        return "{" out "}"
    }
    static FieldLines(expr) {
        out := ""
        for f in AxBind.FieldPairs(expr)
            out .= (out = "" ? "" : AxWiz.NL) f.K " = " f.V
        return out
    }
    static FreeVar(s) {
        n := 1
        while AxBind.HasVar(s.P, "value" (n = 1 ? "" : n))
            n++
        return "value" (n = 1 ? "" : n)
    }
    static ValueWhy(s, V, old := "") {
        name := AxProject.CleanName(V["name"])
        if (name = "")
            return "Give it a name."
        if (AxBind.HasVar(s.P, name) && !(IsObject(old) && old.Name = name))
            return "There is already a value called " name "."
        if (V["how"] = "derived" && Trim(V["expr"]) = "")
            return "Say how it is worked out."
        return ""
    }
    static ValueLine(V) {
        name := AxProject.CleanName(V["name"])
        if (name = "")
            return ""
        if (V["how"] = "derived")
            return name " <- " Trim(V["expr"])
        if (V["how"] = "object")
            return name " = " AxWiz.FieldsExpr(V["fields"])
        val := Trim(V["val"])
        return name " = " (val = "" ? Chr(34) Chr(34) : val)
    }

    ; ========================================================== a rule
    ; old: one of AxFlow.Parse, to change it rather than add one.
    static Flow(s, old := "", pre := "") {
        ed := IsObject(old)
        ctls := AxWiz.CtlOpts(s)
        if (ctls = "")
            return AxForm.Show(s, {Title: "Add a rule", Icon: "E945", Width: 420,
                Intro: "A rule starts with a control, and nothing in this window is named yet.",
                Fields: [{Id: "n", Kind: "note",
                          L: "Select a control and press F2 to name it, then come back. "
                           . "The name is how a rule refers to it."}],
                Buttons: ["Right you are"], CancelIndex: 0})
        sel := s.Primary()
        want := ed ? old.Ctl : IsObject(pre) ? pre.Ctl : (IsObject(sel) && sel.Name != "") ? sel.Name : AxForm.FirstOpt(ctls)
        was := ed ? AxWiz.FlowSplit(old.Verb, old.Arg) : {Who: "", Who2: "", Arg: ""}
        r := AxForm.Show(s, {Title: ed ? "Change a rule" : "Add a rule", Icon: "E945", Width: 520,
            Intro: "Behaviour without writing code: when this happens, do that.",
            Fields: [
                {Id: "ctl",  L: "When",      Kind: "choice", V: want, Opts: ctls},
                {Id: "ev",   L: "and it",    Kind: "choice", V: AxFlow.EvBase(ed ? old.Ev : IsObject(pre) ? pre.Ev : "Click"),
                 Fill: (V) => AxWiz.EventOpts(s, V["ctl"])},
                ; a pack's event can be narrowed: Hit, only for things tagged coin
                {Id: "qual", L: "only for",  Kind: "text", V: AxFlow.EvQual(ed ? old.Ev : IsObject(pre) ? pre.Ev : ""),
                 When: (V) => AxCat.Filter(V["ev"]) != "",
                 Hint: "Leave it empty for every one. Otherwise the rule runs only when the event's "
                     . "value is this -- a tag for Hit (coin), a key for Key (space)."},
                {Id: "d1", Kind: "divider", L: ""},
                {Id: "verb", L: "then",      Kind: "choice", V: ed ? old.Verb : "toast",
                 Opts: AxWiz.VerbOpts(s)},
                {Id: "who",  L: "which one", Kind: "choice", V: was.Who,
                 Fill: (V) => AxWiz.VerbList(s, V["verb"]),
                 When: (V) => AxWiz.VerbNeeds(V["verb"], "who")},
                {Id: "who2", L: "into",      Kind: "choice", V: was.Who2,
                 Fill: (V) => AxWiz.CtlOpts(s), When: (V) => V["verb"] = "copy"},
                {Id: "arg",  L: "value",     Kind: "text", V: was.Arg,
                 When: (V) => AxWiz.VerbNeeds(V["verb"], "arg"),
                 Hint: "Plain text. It is written into the rule exactly as typed. A file without a folder is beside the program."},
                ; a file the rule reads can travel with the program
                {Id: "ship", L: "The finished program", Kind: "choice",
                 V: (ed && AxWiz.Listed(s, was.Arg)) ? "carry" : "path",
                 Opts: "path:Looks for the file beside it|carry:Carries the file inside it (App > Files)",
                 When: (V) => AxWiz.ReadsFile(V["verb"]),
                 Hint: "Carried inside, it cannot go missing: it is built into the exe and written out beside it on the first run."}],
            Buttons: [ed ? "Save" : "Add the rule", "Cancel"],
            Check: (V) => AxWiz.FlowWhy(V),
            Preview: (V) => AxWiz.FlowLine(V)})
        if !r.Ok
            return
        s.PutLine("Flows", ed ? old.Line : "", AxWiz.FlowLine(r.V))
        if AxWiz.ReadsFile(r.V["verb"]) && r.V["ship"] = "carry" && Trim(r.V["arg"]) != ""
            AxWiz.Carry(s, Trim(r.V["arg"]))
        if IsObject(st := AxPkg.Step(r.V["verb"]))      ; a library's step: the script includes it
            AxPkg.Use(s.P, st.Lib)
        s.Refresh()
        s.Status("msg", (ed ? "Changed a rule in " : "Added a rule to ") s.P.W.Name ".")
    }
    ; A rule verb that reads a file named in its value: loadrows, and a
    ; library's step whose code reads {path} (json.read, ...)
    static ReadsFile(verb) {
        if (verb = "loadrows")
            return true
        st := AxPkg.Step(verb)
        return IsObject(st) && InStr(st.Code, "{path}") && (InStr(st.V, "read") || InStr(st.V, "load") || InStr(st.L, "read"))
    }
    static Listed(s, path) {
        for f in AxAsset.Files(s.P)
            if (f.Path = Trim(path))
                return true
        return false
    }
    ; onto App > Files as a file the program carries and writes out -- the way
    ; that hands back a path, which is what the rule's code reads
    static Carry(s, path) {
        if AxWiz.Listed(s, path) || RegExMatch(path, "^\{\w+\}$")
            return
        SplitPath(path, &fname)
        name := AxProject.CleanName(RegExReplace(fname, "\.[^.]*$"))
        if (name = "")
            return
        line := AxAsset.FileLine(name, path, "install")
        cur := RTrim(String(s.P.Files), " `t`r`n")
        s.P.Files := (Trim(cur) = "") ? line : cur "`n" line
        s.Status("msg", path " is carried with the program now (App > Files).")
    }
    ; A rule's argument back into the form's three boxes: the one it applies
    ; to, the one it copies into, and the typed value -- whichever the verb has.
    static FlowSplit(verb, arg) {
        x := AxWiz.Verb(verb)
        who := "", who2 := "", rest := Trim(arg)
        if (IsObject(x) && x.Who != "") {
            who := RegExMatch(rest, "^\S+", &m) ? m[0] : ""
            rest := Trim(SubStr(rest, StrLen(who) + 1))
        }
        if (verb = "copy") {
            who2 := RegExMatch(rest, "^\S+", &m2) ? m2[0] : ""
            rest := ""
        }
        if !(IsObject(x) && x.Arg)
            rest := ""
        return {Who: who, Who2: who2, Arg: rest}
    }
    ; What a rule can do. An array, not a Map: a Map in AutoHotkey v2 hands
    ; its keys back in alphabetical order, and a dropdown of verbs sorted by
    ; spelling is a dropdown nobody can find anything in.
    ;   {V: the word the rule uses, L: how it reads, Who: the list it picks
    ;    from, Arg: whether it also needs a typed value}
    static Verbs := [
        {V: "toast",   L: "show a message",              Who: "",      Arg: true},
        {V: "status",  L: "write to the status bar",     Who: "",      Arg: true},
        {V: "set",     L: "set a control's value",       Who: "ctl",   Arg: true},
        {V: "copy",    L: "copy one control into another", Who: "ctl", Arg: false},
        {V: "show",    L: "show a control",              Who: "ctl",   Arg: false},
        {V: "hide",    L: "hide a control",              Who: "ctl",   Arg: false},
        {V: "enable",  L: "enable a control",            Who: "ctl",   Arg: false},
        {V: "disable", L: "disable a control",           Who: "ctl",   Arg: false},
        {V: "addrow",  L: "add a row to a list  (cells: a | b, {box} for what a box holds)", Who: "list", Arg: true},
        {V: "removerow", L: "remove the picked rows from a list", Who: "list", Arg: false},
        {V: "clearlist", L: "empty a list",                Who: "list", Arg: false},
        {V: "tickall", L: "tick every row of a list",      Who: "list", Arg: false},
        {V: "untickall", L: "untick every row of a list",  Who: "list", Arg: false},
        {V: "saverows", L: "save a list to a file",        Who: "list", Arg: true},
        {V: "loadrows", L: "load a list from a file",      Who: "list", Arg: true},
        {V: "folderrows", L: "fill a list with a folder's files", Who: "list", Arg: true},
        {V: "page",    L: "go to a page",                Who: "page",  Arg: false},
        {V: "open",    L: "open another window",         Who: "win",   Arg: false},
        {V: "close",   L: "close this window",           Who: "",      Arg: false},
        {V: "dirty",   L: "mark it as having unsaved changes", Who: "", Arg: false},
        {V: "clean",   L: "mark it as saved",            Who: "",      Arg: false},
        {V: "state",   L: "apply a state",               Who: "state", Arg: false},
        {V: "assign",  L: "change a bound value",        Who: "var",   Arg: true},
        {V: "add",     L: "add to a value  (by 1, a number, or another value)", Who: "var", Arg: true},
        {V: "take",    L: "take from a value",           Who: "var",   Arg: true},
        {V: "do",      L: "run one line of code",        Who: "",      Arg: true},
        {V: "run",     L: "open a file or a web page",   Who: "",      Arg: true},
        {V: "send",    L: "press keys",                  Who: "",      Arg: true},
        {V: "type",    L: "type some text",              Who: "",      Arg: true},
        {V: "play",    L: "play a macro",                Who: "",      Arg: true},
        {V: "start",   L: "start a timer",               Who: "",      Arg: true},
        {V: "stop",    L: "stop a timer",                Who: "",      Arg: true},
        {V: "wait",    L: "wait (milliseconds)",         Who: "",      Arg: true},
        {V: "beep",    L: "beep",                        Who: "",      Arg: false},
        {V: "call",    L: "call a function",             Who: "",      Arg: true},
        {V: "startup", L: "start with Windows: on or off", Who: "",    Arg: true},
        {V: "save",    L: "save the settings",           Who: "",      Arg: false},
        {V: "load",    L: "put back the saved settings", Who: "",      Arg: false},
        {V: "reset",   L: "set the settings back to their first values", Who: "", Arg: false}]
    static Verb(v) {
        for x in AxWiz.Verbs
            if (x.V = v)
                return x
        return AxPkg.Step(v)                ; a library's step, or ""
    }
    ; the studio's own verbs, then the steps of the libraries installed here
    static VerbOpts(s := "") {
        out := ""
        for x in AxWiz.Verbs
            out .= (out = "" ? "" : "|") x.V ":" x.L
        if IsObject(s) {
            have := AxPkg.Installed(AxPkg.ProjDir(s.P))
            for st in AxPkg.Steps()
                if have.Has(st.Lib)
                    out .= "|" st.V ":" StrSplit(st.Lib, "/")[-1] ": " st.L
        }
        return out
    }
    static VerbNeeds(verb, what) {
        x := AxWiz.Verb(verb)
        if !IsObject(x)
            return false
        return (what = "arg") ? x.Arg : (x.Who != "")
    }
    static VerbList(s, verb) {
        x := AxWiz.Verb(verb)
        kind := IsObject(x) ? x.Who : ""
        switch kind {
        case "ctl":   return AxWiz.CtlOpts(s)
        case "list":  return AxWiz.ListOpts(s)
        case "win":   return AxWiz.NameOpts(s.WinNames())
        case "page":  return AxWiz.NameOpts(s.PageNames())
        case "var":   return AxWiz.NameOpts(AxBind.Paths(s.P))
        case "state": return AxWiz.NameOpts(AxWiz.StateNames(s))
        }
        return ""
    }
    static StateNames(s) {
        out := []
        for raw in StrSplit(String(s.P.States), "`n", "`r") {
            p := InStr(raw, ":")
            if (p && Trim(SubStr(raw, 1, p - 1)) != "")
                out.Push(Trim(SubStr(raw, 1, p - 1)))
        }
        return out
    }
    static FlowWhy(V) {
        if (Trim(V["ctl"]) = "" || Trim(V["ev"]) = "")
            return "Pick the control and what it does."
        if (AxWiz.VerbNeeds(V["verb"], "who") && Trim(V["who"]) = "")
            return "Pick the one it applies to."
        if (V["verb"] = "copy" && Trim(V["who2"]) = "")
            return "Pick the control to copy into."
        if (AxWiz.VerbNeeds(V["verb"], "arg") && Trim(V["arg"]) = "" && !InStr("|set|add|take|", "|" V["verb"] "|"))
            return "Say what it should be."
        return ""
    }
    static FlowLine(V) {
        if (Trim(V["ctl"]) = "")
            return ""
        tail := ""
        if AxWiz.VerbNeeds(V["verb"], "who")
            tail .= " " Trim(V["who"])
        if (V["verb"] = "copy")
            tail .= " " Trim(V["who2"])
        if AxWiz.VerbNeeds(V["verb"], "arg")
            tail .= " " Trim(V["arg"])
        ev := Trim(V["ev"])
        if (V.Has("qual") && Trim(V["qual"]) != "" && AxCat.Filter(ev) != "")
            ev .= ":" RegExReplace(Trim(V["qual"]), "\s+", "_")
        return Trim(V["ctl"]) " " ev " -> " V["verb"] RTrim(tail)
    }

    ; ========================================================= a state
    static State(s) {
        ctls := AxWiz.CtlOpts(s)
        if (ctls = "")
            return s.Status("msg", "Name a control first -- a state is a list of things to change.")
        r := AxForm.Show(s, {Title: "Add a state", Icon: "E81E", Width: 500,
            Intro: "A state is a named set of changes you can apply in one go -- 'busy', "
                 . "'loggedIn', 'empty'.",
            Fields: [
                {Id: "name", L: "Called",   Kind: "text", V: "busy",
                 Hint: "A rule can then apply it by this name."},
                {Id: "ctl",  L: "It changes", Kind: "choice", V: AxForm.FirstOpt(ctls), Opts: ctls},
                {Id: "prop", L: "Its",      Kind: "choice", V: "Enabled",
                 Opts: "Enabled:whether it can be used|Visible:whether it is on screen|"
                     . "Text:the text it shows|Value:the value it holds"},
                {Id: "to",   L: "To",       Kind: "text", V: "0",
                 Hint: "0 or 1 for the first two; anything for the others."}],
            Buttons: ["Add the state", "Cancel"],
            Check: (V) => (AxProject.CleanName(V["name"]) = "") ? "Give the state a name." : "",
            Preview: (V) => AxWiz.StateLine(V)})
        if !r.Ok
            return
        s.AppendLine("States", AxWiz.StateLine(r.V))
        s.Status("msg", "Added the state " AxProject.CleanName(r.V["name"])
                      . ". Add more lines under the same name to change more at once.")
    }
    static StateLine(V) {
        n := AxProject.CleanName(V["name"])
        if (n = "" || Trim(V["ctl"]) = "")
            return ""
        return n ": " Trim(V["ctl"]) "." V["prop"] " = " Trim(V["to"])
    }

    ; ================================================ open a window from
    ; A window nothing opens never appears -- it is the single most common way
    ; a two-window project comes out broken, and the Windows pane says so in
    ; red. This is the fix, in one form: which control, on which event, and
    ; whether to write it as a rule or as code in that control's handler.
    static Link(s) {
        wins := s.WinNames()
        if !wins.Length
            return AxForm.Show(s, {Title: "Open a window", Icon: "E71B", Width: 430,
                Intro: "There is only the main window so far.",
                Fields: [{Id: "n", Kind: "note",
                          L: "Add a dialog or a tool window first (Add > A window, or the + beside the window tabs), "
                           . "then come back and say what opens it."}],
                Buttons: ["Right you are"], CancelIndex: 0})
        ; the window being edited is the obvious target, unless it is the one
        ; the script starts with
        target := (s.P.W.Kind != "main") ? s.P.W.Name : wins[1]
        r := AxForm.Show(s, {Title: "Open a window from a control", Icon: "E71B", Width: 520,
            Intro: "Pick the control that opens it. Anything named, in any window, will do.",
            Fields: [
                {Id: "win", L: "Open",   Kind: "choice", V: target, Opts: AxWiz.NameOpts(wins)},
                {Id: "ctl", L: "When",   Kind: "choice", V: "",
                 Fill: (V) => AxWiz.LinkSources(s, V["win"])},
                {Id: "ev",  L: "and it", Kind: "choice", V: "Click",
                 Fill: (V) => AxWiz.EventOpts(s, V["ctl"])},
                {Id: "how", L: "Write it as", Kind: "seg", V: "rule",
                 Opts: "rule:A rule|code:Code in the handler",
                 Hint: "A rule needs no code at all. The handler version is written out in full, "
                     . "including reading back what a dialog returns."}],
            Buttons: ["Link it", "Cancel"],
            Check: (V) => AxWiz.LinkWhy(s, V),
            Preview: (V) => AxWiz.LinkPreview(s, V)})
        if !r.Ok
            return
        node := s.P.FindByName(r.V["ctl"])
        win := s.P.WinByName(r.V["win"])
        if (!IsObject(node) || !IsObject(win))
            return
        s.Mark()
        if (r.V["how"] = "code") {
            ev := AxWiz.EnsureEvent(node, r.V["ev"])
            ev["code"] := Trim(String(ev["code"]) "`n" AxWiz.OpenCall(win), "`n")
        } else {
            src := s.P.WinOf(node)
            cur := RTrim(String(src.Flows), " `t`r`n")
            line := node.Name " " r.V["ev"] " -> open " win.Name
            src.Flows := (cur = "") ? line : cur "`n" line
        }
        s.Refresh()
        s.Status("msg", node.Label " now opens " win.Name ".")
    }
    ; Every named control in the project except the ones inside the window
    ; being opened -- a window that opens itself is not a link.
    static LinkSources(s, winName) {
        out := ""
        for w in s.P.Wins {
            if (w.Name = winName)
                continue
            for n in s.NamedIn(w)
                out .= (out = "" ? "" : "|") n.Name ":" n.Name
                  . " -- " w.Name "  (" (AxCat.Has(n.Type) ? AxCat.Get(n.Type).Label : n.Type) ")"
        }
        return out
    }
    static LinkWhy(s, V) {
        if (Trim(V["win"]) = "")
            return "Pick the window to open."
        if (Trim(V["ctl"]) = "")
            return "Nothing outside " Trim(V["win"]) " is named yet. Name a control -- a button, "
                 . "usually -- and come back."
        return ""
    }
    static LinkPreview(s, V) {
        if (Trim(V["ctl"]) = "" || Trim(V["win"]) = "")
            return ""
        win := s.P.WinByName(V["win"])
        if (V["how"] = "code")
            return IsObject(win) ? AxWiz.OpenCall(win) : ""
        return Trim(V["ctl"]) " " Trim(V["ev"]) " -> open " Trim(V["win"])
    }
    ; A dialog hands values back, so the call that opens one is written with
    ; somewhere for them to land.
    static OpenCall(win) {
        nl := AxWiz.NL, q := AxWiz.Q
        if (win.Kind != "dialog")
            return AxGen.Fn(win) "()"
        return "r := " AxGen.Fn(win) "()" nl
             . "if IsObject(r)" nl
             . "    g.Toast(" q "got " q " r.Count " q " value(s) back" q ")"
    }

    ; ======================================================= a window
    static NewWindow(s, kind := "") {
        ctls := AxWiz.CtlOpts(s)
        r := AxForm.Show(s, {Title: "Add a window", Icon: "E7C4", Width: 510,
            Intro: "A project is one script. Every window in it becomes a function that builds "
                 . "and shows that window.",
            Fields: [
                {Id: "kind", Kind: "pick", L: "", V: (kind != "" ? kind : "dialog"), Items: [
                    {V: "dialog", L: "A dialog", Icon: "E8BD",
                     Desc: "Small, fixed size, closes on Escape. For a question or a setting."},
                    {V: "window", L: "Another ordinary window", Icon: "E7C4",
                     Desc: "Resizable, with everything the main window has."},
                    {V: "tool",   L: "A tool window", Icon: "E90F",
                     Desc: "Stays on top, no taskbar button. For a palette or a HUD."}]},
                {Id: "name",  L: "Called", Kind: "text", V: "",
                 Hint: "Used in the code: Show<name>() builds it."},
                {Id: "title", L: "Title bar", Kind: "text", V: ""},
                {Id: "w", L: "Width",  Kind: "int", V: 420, Min: 120, Max: 4000, Suffix: "px"},
                {Id: "h", L: "Height", Kind: "int", V: 300, Min: 100, Max: 3000, Suffix: "px"},
                {Id: "d1", Kind: "divider", L: ""},
                {Id: "openit", L: "Have a control open it", Kind: "flag", V: (ctls != "") ? 1 : 0,
                 Hint: (ctls != "") ? "Otherwise nothing opens it and it never appears."
                                    : "Nothing in this window is named yet, so there is nothing to open it from."},
                {Id: "from", L: "Which control", Kind: "choice", V: AxForm.FirstOpt(ctls),
                 Opts: ctls, When: (V) => V["openit"] && ctls != ""}],
            Buttons: ["Add it", "Cancel"],
            Check: (V) => (Trim(V["name"]) != "" && AxProject.CleanName(V["name"]) = "")
                        ? "That name has nothing usable in it." : "",
            Preview: (V) => AxWiz.WinPreview(s, V)})
        if !r.Ok
            return
        s.Mark()
        ; AddWin sets what a dialog and a tool window are; this only overrides
        ; the four things the form actually asked about, plus the look, which
        ; should match the window you were just editing rather than the default
        w := s.P.AddWin(r.V["kind"], AxWiz.WinName(s, r.V))
        w.Title := (Trim(r.V["title"]) != "") ? Trim(r.V["title"]) : w.Name
        w.Width := AxWiz.Int(r.V["w"], 420), w.Height := AxWiz.Int(r.V["h"], 300)
        w.Theme := s.P.W.Theme, w.Stylesheet := s.P.W.Stylesheet, w.Accent := s.P.W.Accent
        if (r.V["openit"] && Trim(r.V["from"]) != "") {
            cur := RTrim(String(s.P.W.Flows), " `t`r`n")
            line := Trim(r.V["from"]) " Click -> open " w.Name
            s.P.W.Flows := (cur = "") ? line : cur "`n" line
        }
        s.P.Cur := s.P.Wins.Length
        s.SelIds := [], s.PageId := "", s.CodeTarget := ""
        s.Refresh()
        s.PushCompletions()
        s.Status("msg", "Added " w.Name ". It is built by " AxGen.Fn(w) "().")
    }
    static WinName(s, V) {
        want := AxProject.CleanName(V["name"])
        if (want = "")
            want := (V["kind"] = "dialog") ? "Dialog" : (V["kind"] = "tool") ? "Tools" : "Window"
        return s.P.UniqueWinName(want)
    }
    static WinPreview(s, V) {
        w := AxWin(AxWiz.WinName(s, V))
        w.Kind := V["kind"]
        line := AxGen.Fn(w) "()   " AxWiz.Int(V["w"], 420) " x " AxWiz.Int(V["h"], 300)
        if (V["openit"] && Trim(V["from"]) != "")
            line .= AxWiz.NL Trim(V["from"]) " Click -> open " w.Name
        return line
    }

    ; ============================================== an icon inside a dll
    static IconIndex(s, file) {
        v := AxForm.Ask(s, "Which icon inside it", "Index", "0",
            {Icon: "E8B9", Kind: "int",
             Intro: "shell32.dll holds hundreds. A number counts from the start; "
                  . "a negative number is a resource id.",
             Hint: "0 is the first icon in the file."})
        return (v = "") ? "" : file "," Trim(v)
    }

    ; ================================================== rename a control
    static Rename(s, n) {
        v := AxForm.Ask(s, "Rename", "Called", n.Name,
            {Icon: "E8AC",
             Intro: "This is the name the generated code uses -- g.Value(" Chr(34) "name" Chr(34) "), "
                  . "and the name a rule or a binding refers to.",
             Hint: "Letters, digits and underscores. Anything else is dropped.",
             Check: (V) => (Trim(V["a"]) != "" && AxProject.CleanName(V["a"]) = "")
                         ? "That leaves nothing usable." : ""})
        return v
    }

    ; ======================================================== welcome
    ; What the studio opens on: what you can start, on one screen. On the left
    ; the ways in -- a new window, a file, last time's unsaved work, the files
    ; you had open -- and on the right every template as a card with a
    ; drawing of its layout, which starts it in one click. It used to be a
    ; list of four choices, one of which opened a second list of templates by
    ; name only.
    static Welcome(s) {
        E := (t) => AxTags.E(t)
        left := '<div class="axd-homebrand">AxStudio<span>' s.StudioVer() '</span></div>'
              . '<div class="axd-homesub">Windows for AutoHotkey, built from real controls. What you '
              . 'make is a script that runs on its own, or an exe.</div>'
        if FileExist(s.AutoPath)
            left .= '<div class="axd-homeact axd-homehot" data-fgo="recover"><span class="ico">&#xE777;</span>'
                  . '<b>Pick up where you left off</b><small>unsaved work from ' E(AxWiz.When(s.AutoPath)) '</small></div>'
        left .= '<div class="axd-homeact" data-fgo="blank"><span class="ico">&#xE710;</span><b>New window</b>'
              . '<small>one empty page and the Toolbox</small></div>'
              . '<div class="axd-homeact" data-fgo="open"><span class="ico">&#xE8E5;</span><b>Open...</b>'
              . '<small>a project, or a script AxStudio wrote</small></div>'
              . '<div class="axd-homeact" data-fgo="import"><span class="ico">&#xE8B5;</span><b>Import a script...</b>'
              . '<small>any AutoHotkey window -- AxGui or Gui() -- as a design</small></div>'
              . '<div class="axd-homeh">Recent</div>'
        rec := ""
        for i, path in s.Recent {
            if (i > 6)
                break
            SplitPath(path, &name, &dir)
            rec .= '<div class="axd-homerec" data-fgo="recent' i '" title="' E(path) '">'
                .  '<b>' E(RegExReplace(name, "i)\.axs\.json$|\.json$")) '</b>'
                .  '<span>' E(AxWiz.When(path)) '</span><small>' E(dir) '</small></div>'
        }
        left .= (rec != "" ? rec : '<div class="axd-homenone">Nothing opened yet.</div>')
              . '<div class="axd-homekeys"><b>Ctrl+1</b>-<b>7</b> Design, Logic, Steps, Code, Map, App, Look<br>'
              . '<b>Ctrl+I</b> add anything &#183; <b>Ctrl+Shift+P</b> every command<br>'
              . '<b>F5</b> run it &#183; <b>F1</b> every key</div>'
        cards := ""
        for t in AxTpl.All
            cards .= '<div class="axd-tpl" data-fgo="tpl:' E(t.Id) '" title="' E(t.Desc) '">'
                  .  (t.Pic != "" ? '<div class="axd-thumb axd-shot"><img alt="" src="' E(AxWindow.FileUrl(t.Pic)) '"></div>'
                                  : AxWiz.Thumb(t.Map))
                  .  '<b>' E(t.Name) '</b><small>' E(t.Desc) '</small>'
                  .  AxWiz.UsesHtml(t.Map) '</div>'
        h := '<div class="axd-home"><div class="axd-homel">' left '</div>'
           . '<div class="axd-homer"><div class="axd-homein"><div class="axd-homeh axd-homeh1">Start from a template'
           . '<span>' AxTpl.All.Length ' finished little programs -- each one runs</span></div>'
           . '<div class="axd-tplgrid">' cards '</div></div></div></div>'
        r := AxForm.Show(s, {Title: "Welcome", Icon: "E80F", Width: 1100,
            Fields: [{Id: "home", Kind: "note", Html: true, L: h},
                     {Id: "ask", L: "Show this when AxStudio starts", Kind: "flag", V: s.ShowWelcome}],
            Buttons: ["Close"]})
        s.ShowWelcome := r.V["ask"] ? 1 : 0
        s.SaveSettings()
        what := r.Go
        if (what = "")
            return
        if (what = "recover")
            return s.LoadFile(s.AutoPath)
        if (SubStr(what, 1, 6) = "recent") {
            i := AxWiz.Int(SubStr(what, 7), 0)
            if (i >= 1 && i <= s.Recent.Length)
                return s.LoadFile(s.Recent[i])
            return
        }
        if (what = "open")
            return s.Open()
        if (what = "import")
            return s.ImportScript()
        if (what = "blank")
            return s.NewProject("blank")
        if (SubStr(what, 1, 4) = "tpl:") {
            s.NewProject(SubStr(what, 5))
            AxWiz.OfferSave(s)
        }
    }
    ; A template's main window as a small drawing: its title bar, its menu
    ; bar, the page list down the side when it has pages, and each thing on
    ; the first page as the shape it has -- a row, a box you type in, a
    ; button, a table, a set of tabs, tiles. Read from the template itself, so
    ; a template that changes draws itself differently.
    static Thumb(m) {
        if !(m is Map)
            return '<div class="axd-thumb"><i class="tb"></i></div>'
        w := m
        wins := AxJson.Get(m, "windows", "")
        if (wins is Array && wins.Length)
            w := wins[1]
        root := AxJson.Get(w, "root", "")
        kids := (root is Map) ? AxJson.Get(root, "kids", []) : []
        pages := [], items := kids
        for k in kids
            if (k is Map && AxJson.Get(k, "type", "") = "Page")
                pages.Push(k)
        if pages.Length
            items := AxJson.Get(pages[1], "kids", [])
        h := '<div class="axd-thumb"><i class="tb"></i>'
        if (Trim(String(AxJson.Get(w, "menubar", ""))) != "" || Trim(String(AxJson.Get(w, "menus", ""))) != "")
            h .= '<i class="mb"></i>'
        h .= '<div class="bd">'
        if (pages.Length > 1) {
            h .= '<div class="nv">'
            for i, p in pages
                if (i <= 5)
                    h .= '<i' (i = 1 ? ' class="on"' : "") '></i>'
            h .= '</div>'
        }
        n := 0
        h .= '<div class="pg">' AxWiz.ThumbItems(items, &n, 0) '</div></div></div>'
        return h
    }
    ; What a template is made with, as tags under its card: the parts of the
    ; studio that are not code -- bindings, rules, states, hotkeys, timers,
    ; remembered settings -- and "No code" when nothing in it was written by
    ; hand. Read from the file, so a template of your own gets tags too.
    static Uses(m) {
        out := []
        if !(m is Map)
            return out
        wins := AxJson.Get(m, "windows", "")
        if !(wins is Array && wins.Length)
            wins := [m]
        Set(o, k) => (o is Map) && Trim(String(AxJson.Get(o, k, ""))) != ""
        AnyWin(k) {
            for w in wins
                if Set(w, k)
                    return true
            return false
        }
        code := Set(m, "script"), pages := 0
        for w in wins {
            if (Set(w, "script") || Set(w, "init"))
                code := true
            root := AxJson.Get(w, "root", "")
            kids := (root is Map) ? AxJson.Get(root, "kids", "") : ""
            if (kids is Array)
                for k in kids
                    if (k is Map && AxJson.Get(k, "type", "") = "Page")
                        pages++
            if (!code && AxWiz._HasCode(root))
                code := true
        }
        if !code
            out.Push(["No code", "Nothing in it is written by hand: all of it is set up in the studio", "nc"])
        for x in [["binds", "Bindings", "Controls bound to values, keeping each other in step"],
                  ["flows", "Rules", "When this happens, do that -- on the Logic tab"],
                  ["states", "States", "Named sets of changes, switched in one go"],
                  ["hotkeys", "Hotkeys", "Keys that do something, in the window or anywhere"]]
            if AnyWin(x[1])
                out.Push([x[2], x[3], ""])
        for x in [["strings", "Hotstrings", "Abbreviations that type something longer"],
                  ["timers", "Timers", "Something done every so often"],
                  ["settings", "Settings", "Choices remembered for next time"],
                  ["conds", "Conditions", "Keys and strings only for one program"],
                  ["watchers", "Watchers", "A folder or a program watched for changes"],
                  ["macros", "Macros", "Recorded keys and clicks, played back"],
                  ["tray", "Tray", "An icon and a menu in the notification area"]]
            if Set(m, x[1])
                out.Push([x[2], x[3], ""])
        if (wins.Length > 1)
            out.Push([wins.Length " windows", "More than one window, sharing the same values", ""])
        if (pages > 1)
            out.Push([pages " pages", "Pages down the side, one shown at a time", ""])
        if (out.Length = 1 && out[1][3] = "nc")
            out := []                      ; an empty page has no code, and that says nothing
        return out
    }
    static _HasCode(n) {
        if !(n is Map)
            return false
        ev := AxJson.Get(n, "events", ""), kids := AxJson.Get(n, "kids", "")
        if (ev is Array)
            for e in ev
                if (e is Map && Trim(String(AxJson.Get(e, "code", ""))) != "")
                    return true
        if (kids is Array)
            for k in kids
                if AxWiz._HasCode(k)
                    return true
        return false
    }
    static UsesHtml(m) {
        h := ""
        for x in AxWiz.Uses(m)
            h .= '<span' (x[3] != "" ? ' class="' x[3] '"' : "") ' title="' AxTags.E(x[2]) '">' AxTags.E(x[1]) '</span>'
        return (h = "") ? "" : '<div class="axd-tpltags">' h '</div>'
    }
    static ThumbItems(items, &n, depth) {
        h := ""
        if !(items is Array)
            return ""
        for k in items {
            if (!(k is Map) || n >= 14)
                continue
            n++
            t := AxJson.Get(k, "type", "")
            kids := AxJson.Get(k, "kids", [])
            switch t {
            case "Row":
                h .= '<b class="row"><i class="t"></i><i class="c"></i></b>'
            case "Card", "Group", "Expander":
                h .= '<b class="card">' (depth < 1 ? AxWiz.ThumbItems(kids, &n, depth + 1) : "") '</b>'
            case "Grid":
                h .= '<b class="tiles">' AxWiz.ThumbItems(kids, &n, depth + 1) '</b>'
            case "Tile":
                h .= '<i class="tile"></i>'
            case "Text", "Label", "Link":
                h .= '<i class="txt"></i>'
            case "Edit", "Search", "DDL", "Hotkey", "AutoComplete", "Number", "Password":
                h .= '<i class="in"></i>'
            case "Button":
                h .= '<i class="btn"></i>'
            case "DataView", "ListView", "TreeView":
                h .= '<i class="tbl"><s></s><s></s><s></s><s></s></i>'
            case "ListBox", "Console", "ActiveX", "Svg", "Html", "Chart":
                h .= '<i class="box"></i>'
            case "Tab":
                h .= '<i class="tabs"><s></s><s></s><s></s></i>'
            case "Progress", "Slider":
                h .= '<i class="bar"></i>'
            case "InfoBar":
                h .= '<i class="info"></i>'
            case "Switch", "Check", "Radio", "Segmented":
                h .= '<i class="sw"></i>'
            case "Splitter":
                h .= ''
            default:
                h .= '<i class="txt"></i>'
            }
        }
        return h
    }
    ; The studio in five tiles and three keys -- the part nobody finds by
    ; poking about, on the one screen everybody sees.
    static Tour() {
        T := (ico, name, key, what) => '<div class="axd-touri"><span class="ico">&#x' ico ';</span>'
            . '<b>' name '</b><span class="axd-tourk">' key '</span><div>' what '</div></div>'
        return '<div class="axd-tour">'
             . T("E7C4", "Design", "Ctrl+1", "Canvas, Toolbox, inspector")
             . T("E945", "Logic", "Ctrl+2", "Values, rules and hotkeys")
             . T("E8FD", "Steps", "Ctrl+3", "What happens, as a flowchart")
             . T("E943", "Code", "Ctrl+4", "The same, as code")
             . T("E7B8", "App", "Ctrl+6", "Windows, files, the exe")
             . '</div><div class="axd-tourkeys"><b>Ctrl+I</b> adds anything  &#183;  '
             . '<b>Ctrl+Shift+P</b> finds any command  &#183;  <b>F5</b> runs it</div>'
    }
    ; The templates, with what each one is for. They are ordinary project
    ; files, so every one of them opens, changes and saves like any other.
    static Template(s) {
        items := []
        for t in AxTpl.All
            items.Push({V: t.Id, L: t.Name, Desc: t.Desc, Icon: "E7C4"})
        id := AxForm.Choose(s, "Start from a template",
            "Each is a finished little application, not a sketch: the controls are named and "
          . "the handlers have code in them that runs.",
            items, {Icon: "E710", Width: 560, Ok: "Use it", Scroll: true})
        if (id = "")
            return
        s.NewProject(id)
        AxWiz.OfferSave(s)
    }
    ; Somewhere to save it, straight away. Autosave then has a real file beside
    ; it to keep a copy in, and Ctrl+S stops being a question.
    static OfferSave(s) {
        if !s.AskWhereFirst
            return
        r := AxForm.Show(s, {Title: "Where should it live?", Icon: "E74E", Width: 470,
            Intro: "Choosing now means Ctrl+S never asks, and the autosave keeps its spare "
                 . "copy beside the real file rather than in AppData.",
            Fields: [{Id: "n", Kind: "note",
                      L: "You can always do this later with File > Save as."},
                     {Id: "ask", L: "Offer this every time I start something new", Kind: "flag",
                      V: s.AskWhereFirst}],
            Buttons: ["Choose a file...", "Later"]})
        s.AskWhereFirst := r.V["ask"] ? 1 : 0
        s.SaveSettings()
        if r.Ok
            s.SaveAs()
    }
    static When(path) {
        try {
            t := FileGetTime(path, "M")
            mins := DateDiff(A_Now, t, "Minutes")
            if (mins < 1)
                return "just now"
            if (mins < 60)
                return mins " minute" (mins = 1 ? "" : "s") " ago"
            if (mins < 1440)
                return (mins // 60) " hour" (mins // 60 = 1 ? "" : "s") " ago"
            return FormatTime(t, "d MMM")
        }
        return "some time ago"
    }

    ; ======================================================= settings
    ; Everything about how the studio behaves, in one place. These were seven
    ; toggles spread over the View menu, the toolbar and the "Add..." menu,
    ; which is how "Toolbox: icons only" ended up filed under wizards.
    static Settings(s) {
        r := AxForm.Show(s, {Title: "Settings", Icon: "E713", Width: 520,
            Intro: "The studio's own settings. Nothing here is saved with a project -- "
                 . "they follow you, not the file.",
            Fields: [
                {Id: "h1", Kind: "heading", L: "Look"},
                {Id: "ui", L: "The studio", Kind: "seg", V: s.UiTheme,
                 Opts: "dark:Dark|light:Light",
                 Hint: "The design keeps whatever look it asks for; this is the editor around it."},
                {Id: "compact", L: "Toolbox shows icons only", Kind: "flag", V: s.Compact,
                 Hint: "Fits about three times as many in, once you know the icons."},
                {Id: "h2", Kind: "heading", L: "The canvas"},
                {Id: "showgrid", L: "Show the design grid", Kind: "flag", V: s.ShowGrid},
                {Id: "grid", L: "Grid size", Kind: "int", V: s.Grid, Min: 2, Max: 64, Suffix: "px"},
                {Id: "snap",   L: "Snap to the grid and to other controls", Kind: "flag", V: s.Snap},
                {Id: "guides", L: "Show alignment guides while dragging", Kind: "flag", V: s.Guides},
                {Id: "h3", Kind: "heading", L: "Saving and running"},
                {Id: "auto", L: "Autosave every", Kind: "int", V: s.AutoSecs,
                 Min: 0, Max: 600, Suffix: "s",
                 Hint: "Zero turns it off. The autosave is a spare copy, not your file -- "
                     . "File > Recover the last autosave picks it up after a crash."},
                {Id: "live", L: "Live re-run waits", Kind: "int", V: s.LiveDelay,
                 Min: 200, Max: 5000, Suffix: "ms",
                 Hint: "How long typing has to stop before Live starts the script again."},
                {Id: "tofile", L: "Autosave writes your file, not just a spare copy",
                 Kind: "flag", V: s.AutoToFile,
                 Hint: "Off is the safe default: a copy goes to AppData and a .bak beside your "
                     . "file, and nothing of yours is written over by a timer."},
                {Id: "runpos", L: "The preview opens", Kind: "choice", V: s.PreviewOpens,
                 Opts: "design:As the program will -- its size, where and how it starts"
                     . "|place:As designed, but where the last run was"
                     . "|last:Where and as big as the last run was",
                 Hint: "Maximised or minimised in the design always opens that way. Live keeps the window where it is."},
                {Id: "h4", Kind: "heading", L: "Starting up"},
                {Id: "welcome", L: "Show the start screen", Kind: "flag", V: s.ShowWelcome},
                {Id: "askwhere", L: "Offer somewhere to save a new project", Kind: "flag",
                 V: s.AskWhereFirst},
                {Id: "d1", Kind: "divider", L: ""},
                {Id: "note", Kind: "note", L: "Kept in studio.ini beside the autosave, in your "
                                            . "AppData folder."}],
            Buttons: ["Save", "Cancel"],
            Preview: (V) => "grid " AxWiz.Int(V["grid"], 8) "px"
                          . (V["snap"] ? ", snapping" : ", free")
                          . (AxWiz.Int(V["auto"]) ? ", autosave every " AxWiz.Int(V["auto"]) "s"
                                                  : ", no autosave")})
        if !r.Ok
            return
        s.Compact := r.V["compact"] ? 1 : 0
        s.ShowGrid := r.V["showgrid"] ? 1 : 0
        s.Snap := r.V["snap"] ? 1 : 0
        s.Guides := r.V["guides"] ? 1 : 0
        s.Grid := Min(64, Max(2, AxWiz.Int(r.V["grid"], 8)))
        s.AutoSecs := Min(600, Max(0, AxWiz.Int(r.V["auto"], 15)))
        s.LiveDelay := Min(5000, Max(200, AxWiz.Int(r.V["live"], 900)))
        s.PreviewOpens := r.V["runpos"]
        s.AutoToFile := r.V["tofile"] ? 1 : 0
        s.ShowWelcome := r.V["welcome"] ? 1 : 0
        s.AskWhereFirst := r.V["askwhere"] ? 1 : 0
        s.SaveSettings()
        s.ArmAutoSave()
        s.PushOpts()
        if (r.V["ui"] != s.UiTheme)
            return s.SetUi(r.V["ui"])          ; redraws everything itself
        s.Bar()
        s.Refresh()
        s.Status("msg", "Settings saved.")
    }

    ; ========================================================== a file
    ; The question every program that ships an icon, a sound or a template
    ; runs into: how does that file reach whoever runs it? There are exactly
    ; three answers and each has a catch, so all three are said out loud.
    ; old: one of AxAsset.Files, to change it rather than add one.
    static AddFile(s, old := "") {
        ed := IsObject(old)
        if ed
            f := old.Path, base := old.Name
        else {
            f := FileSelect(3, , "Pick the file the script needs")
            if (f = "")
                return
            SplitPath(f, &base)
        }
        r := AxForm.Show(s, {Title: ed ? "Change a file" : "Add a file", Icon: "E8E5", Width: 560,
            Intro: base " -- how should it reach whoever runs the finished program?",
            Fields: [
                {Id: "how", Kind: "pick", L: "", V: ed ? old.How : "install", Items: [
                    {V: "install", L: "Carry it, and write it out on first run", Icon: "E896",
                     Desc: "FileInstall. The file is built into the exe and appears beside it "
                         . "the first time it starts. Anything that has to BE a file -- an "
                         . "icon, a dll, something another program opens."},
                    {V: "resource", L: "Carry it, and read it from memory", Icon: "E8F1",
                     Desc: "AddResource. Built into the exe and never written to disk. For "
                         . "anything you only read: a stylesheet, a template, some data. "
                         . "This is what the library does with its own themes."},
                    {V: "path",    L: "Do not carry it -- just find it", Icon: "E71B",
                     Desc: "Nothing is built in. The script works out the path at run time "
                         . "and the file has to be there. For anything big, or anything the "
                         . "person is meant to replace."}]},
                {Id: "name", L: "Called", Kind: "text", V: base,
                 Hint: "The name the code uses, and the name it is written out under."},
                {Id: "path", L: "Where it is now", Kind: "text", V: f,
                 Hint: "Where the compiler reads it from. Relative to the exported script "
                     . "is usually what you want."}],
            Buttons: [ed ? "Save" : "Add it", "Cancel"],
            Check: (V) => (AxProject.CleanName(V["name"]) = "") ? "Give it a usable name." : "",
            Preview: (V) => AxWiz.FilePreview(V)})
        if !r.Ok
            return
        line := AxAsset.FileLine(Trim(r.V["name"]), Trim(r.V["path"]), r.V["how"])
        if ed
            return (s.PutLine("Files", old.Line, line), s.Refresh(), s.Status("msg", "Changed " r.V["name"] "."))
        s.Mark()
        s.AppendProject("Files", line)
        s.Status("msg", "Added " r.V["name"] ". Call "
                      . AxAsset.FileFn(r.V["name"]) "() to get at it.")
    }
    static FilePreview(V) {
        name := Trim(V["name"])
        if (name = "")
            return ""
        fn := AxAsset.FileFn(name)
        if (V["how"] = "resource")
            return ";@Ahk2Exe-AddResource " Trim(V["path"]) ", " name AxWiz.NL
                 . fn "()   ->   the content, as text"
        if (V["how"] = "install")
            return "FileInstall(" AxWiz.Q Trim(V["path"]) AxWiz.Q ", A_ScriptDir "
                 . AxWiz.Q "\" name AxWiz.Q ", false)" AxWiz.NL
                 . fn "()   ->   the path it was written to"
        return fn "()   ->   " AxAsset.PathExpr(Trim(V["path"]))
    }

    ; ====================================================== an include
    ; old: one of AxAsset.Includes, to change it rather than add one.
    static AddInclude(s, old := "") {
        ed := IsObject(old)
        lib := ed && old.Lib
        r := AxForm.Show(s, {Title: ed ? "Change an include" : "Add an include", Icon: "E943", Width: 500,
            Intro: "Other AutoHotkey the script needs. The library and the component packs "
                 . "your design uses are included for you -- these are yours.",
            Fields: [
                {Id: "how", L: "Kind", Kind: "seg", V: lib ? "lib" : "file",
                 Opts: "file:A file|lib:On the library path",
                 Hint: "A library include is <Name>, and AutoHotkey looks for it in Lib "
                     . "beside the script, in your documents, and beside AutoHotkey itself."},
                {Id: "path", L: "File", Kind: "text", V: (ed && !lib) ? old.Path : "",
                 When: (V) => V["how"] = "file",
                 Hint: "Relative to the script you export."},
                {Id: "name", L: "Library", Kind: "text", V: lib ? Trim(old.Path, "<> ") : "",
                 When: (V) => V["how"] = "lib"}],
            Buttons: [ed ? "Save" : "Add it", "Browse...", "Cancel"], CancelIndex: 3,
            Check: (V) => AxWiz.IncludeWhy(V),
            Preview: (V) => AxWiz.IncludeLine(V) != "" ? "#Include " AxWiz.IncludeLine(V) : ""})
        if (r.Btn = 2) {
            f := FileSelect(3, , "Pick a script to include", "AutoHotkey (*.ahk)")
            if (f = "")
                return
            if ed
                return (s.PutLine("Includes", old.Line, f), s.Refresh())
            return s.AppendProject("Includes", f)
        }
        if !r.Ok
            return
        if ed
            return (s.PutLine("Includes", old.Line, AxWiz.IncludeLine(r.V)), s.Refresh())
        s.Mark()
        s.AppendProject("Includes", AxWiz.IncludeLine(r.V))
    }
    static IncludeWhy(V) {
        if (V["how"] = "lib")
            return (AxProject.CleanName(V["name"]) = "") ? "Name the library." : ""
        return (Trim(V["path"]) = "") ? "Give the path, or browse for it." : ""
    }
    static IncludeLine(V) {
        if (V["how"] = "lib") {
            n := AxProject.CleanName(V["name"])
            return (n = "") ? "" : "<" n ">"
        }
        return Trim(V["path"])
    }

    ; ==================================================== an argument
    ; old: one of AxAsset.Args, to change it rather than add one.
    static AddArg(s, old := "") {
        ed := IsObject(old)
        r := AxForm.Show(s, {Title: ed ? "Change an argument" : "Add an argument", Icon: "E756", Width: 520,
            Intro: "What the script accepts on the command line. It becomes a global with "
                 . "that name, read before the window is shown, so anything can use it.",
            Fields: [
                {Id: "name", L: "Called", Kind: "text", V: ed ? old.Name : "path",
                 Hint: "Used as  --name value  and as the variable name."},
                {Id: "kind", L: "Takes",  Kind: "seg", V: "value",
                 Opts: "value:A value|flag:Nothing -- it is a switch"},
                {Id: "def",  L: "When absent", Kind: "text", V: ed ? old.Def : "",
                 When: (V) => V["kind"] = "value",
                 Hint: "Plain text, because that is what a command line carries. A number or "
                     . "true/false is written as one. Empty means an empty string."},
                {Id: "desc", L: "What it is for", Kind: "text", V: ed ? old.Desc : ""}],
            Buttons: [ed ? "Save" : "Add it", "Cancel"],
            Check: (V) => (AxProject.CleanName(V["name"]) = "") ? "Give it a usable name." : "",
            Preview: (V) => AxWiz.ArgPreview(V)})
        if !r.Ok
            return
        def := (r.V["kind"] = "flag") ? "0" : Trim(r.V["def"])
        line := AxAsset.ArgLine(AxProject.CleanName(r.V["name"]), def, Trim(r.V["desc"]))
        if ed
            return (s.PutLine("Args", old.Line, line), s.Refresh())
        s.Mark()
        s.AppendProject("Args", line)
    }
    static ArgPreview(V) {
        n := AxProject.CleanName(V["name"])
        if (n = "")
            return ""
        return (V["kind"] = "flag")
             ? "myscript.exe --" n "        " n " is 1" AxWiz.NL
             . "myscript.exe                " n " is 0"
             : "myscript.exe --" n " something" AxWiz.NL
             . n " is " (Trim(V["def"]) != "" ? Trim(V["def"]) : Chr(34) Chr(34)) " when it is not given"
    }

    ; ========================================================= a mode
    ; old: one of AxAsset.Modes with ONE step, to change it rather than add one.
    static AddMode(s, old := "") {
        ed := IsObject(old)
        verb := "hide", what := ""
        if ed {
            step := Trim(old.Steps[1])
            p := InStr(step, " ")
            verb := p ? SubStr(step, 1, p - 1) : step
            what := p ? Trim(SubStr(step, p + 1)) : ""
        }
        r := AxForm.Show(s, {Title: ed ? "Change a mode" : "Add a mode", Icon: "E7C4", Width: 530,
            Intro: "A named way of starting. Chosen with  --mode <name>  on the command "
                 . "line, or by calling Mode(name) from anywhere.",
            Fields: [
                {Id: "name", L: "Called", Kind: "text", V: ed ? old.Name : "quiet"},
                {Id: "verb", L: "It does", Kind: "choice", V: verb,
                 Opts: "hide:start hidden|show:show the window|page:go to a page|"
                     . "state:apply a state|toast:show a message|open:open another window|"
                     . "run:open a file or a web page|exit:do the work and quit"},
                {Id: "arg",  L: "What",   Kind: "text", V: what,
                 When: (V) => AxWiz.ModeNeeds(V["verb"]),
                 Hint: "The page, the state, the message, the window -- whichever the verb "
                     . "above needs."},
                {Id: "n", Kind: "note", L: "One step here to start with. Add more to the same "
                                         . "line, separated by commas, in the text."}],
            Buttons: [ed ? "Save" : "Add it", "Cancel"],
            Check: (V) => AxWiz.ModeWhy(V),
            Preview: (V) => AxWiz.ModePreview(V)})
        if !r.Ok
            return
        step := r.V["verb"] (AxWiz.ModeNeeds(r.V["verb"]) ? " " Trim(r.V["arg"]) : "")
        line := AxAsset.ModeLine(AxProject.CleanName(r.V["name"]), step)
        if ed
            return (s.PutLine("Modes", old.Line, line), s.Refresh())
        s.Mark()
        s.AppendProject("Modes", line)
    }
    static ModeNeeds(verb) {
        static none := "|hide|show|exit|"
        return !InStr(none, "|" verb "|")
    }
    static ModeWhy(V) {
        if (AxProject.CleanName(V["name"]) = "")
            return "Give the mode a name."
        if (AxWiz.ModeNeeds(V["verb"]) && Trim(V["arg"]) = "")
            return "Say what it applies to."
        return ""
    }
    static ModePreview(V) {
        n := AxProject.CleanName(V["name"])
        if (n = "")
            return ""
        step := V["verb"] (AxWiz.ModeNeeds(V["verb"]) ? " " Trim(V["arg"]) : "")
        return "myscript.exe --mode " n AxWiz.NL n " | " step
    }

    ; ===================================================== the tray icon
    static Tray(s) {
        cfg := AxAsset.Tray(s.P)
        items := ""
        for it in cfg.Items
            items .= (items = "" ? "" : AxWiz.NL) it
        if (items = "" && Trim(String(s.P.Tray)) = "")
            items := "Show" AxWiz.NL "-" AxWiz.NL "Exit"
        r := AxForm.Show(s, {Title: "Tray icon", Icon: "E8B7", Width: 540,
            Intro: "What the script puts in the notification area, and what right-clicking "
                 . "it offers.",
            Fields: [
                {Id: "show", L: "Show an icon in the tray", Kind: "flag", V: cfg.Show,
                 Hint: "Off writes #NoTrayIcon -- and then there is no way to quit it from "
                     . "the tray, so give it another one."},
                {Id: "tip",  L: "Tooltip", Kind: "text", V: cfg.Tip,
                 When: (V) => V["show"], Hint: "What hovering over it says."},
                {Id: "icon", L: "Icon",    Kind: "text", V: cfg.Icon,
                 When: (V) => V["show"],
                 Hint: "A .ico or .png, or shell32.dll,13 for one out of a library. "
                     . "Empty keeps AutoHotkey's."},
                {Id: "items", L: "Menu", Kind: "code", Rows: 6, V: items,
                 When: (V) => V["show"],
                 Hint: "One per line: a label, or  Label | code . A hyphen is a separator. "
                     . "Show, Hide, Exit and Reload are written for you."}],
            Buttons: ["Save", "Cancel"],
            Preview: (V) => AxWiz.TrayPreview(V)})
        if !r.Ok
            return
        s.Mark()
        out := "show = " (r.V["show"] ? "yes" : "no")
        if r.V["show"] {
            if (Trim(r.V["tip"]) != "")
                out .= AxWiz.NL "tip = " Trim(r.V["tip"])
            if (Trim(r.V["icon"]) != "")
                out .= AxWiz.NL "icon = " Trim(r.V["icon"])
            if (cfg.Click != "")
                out .= AxWiz.NL "click = " cfg.Click
            ; the lines as typed: indentation is a submenu
            for line in StrSplit(StrReplace(r.V["items"], "`r"), "`n")
                if (Trim(line) != "")
                    out .= AxWiz.NL RTrim(line)
        }
        s.P.Tray := out
        s.Refresh()
        s.Status("msg", r.V["show"] ? "Tray icon set." : "The script will have no tray icon.")
    }
    static TrayPreview(V) {
        if !V["show"]
            return "#NoTrayIcon"
        out := ""
        if (Trim(V["tip"]) != "")
            out .= "A_IconTip := " AxWiz.Q AxWiz.Esc(Trim(V["tip"])) AxWiz.Q AxWiz.NL
        if (Trim(V["icon"]) != "")
            out .= "TraySetIcon(" AxWiz.Q AxWiz.Esc(Trim(V["icon"])) AxWiz.Q ")" AxWiz.NL
        n := AxAsset.Lines(V["items"]).Length
        return out (n ? "A_TrayMenu.Delete(), then " n " item" (n = 1 ? "" : "s")
                      : "AutoHotkey's own menu")
    }

    ; ======================================================== compiling
    ; What the exe says it is, what goes into it, which interpreter it is
    ; stamped onto, where the compiler is -- and a button that builds it.
    ;
    ; AxStudio still does not BE a compiler: it writes the ;@Ahk2Exe- lines
    ; into the script, and Ahk2Exe reads them. What changed is that it now
    ; finds Ahk2Exe and runs it for you, because writing the directives and
    ; then leaving you to go hunting is half an answer.
    static Compile(s) {
        cfg := AxAsset.Compile(s.P)
        G := (k, d := "") => cfg.Has(k) ? cfg[k] : d
        exe := AxBuild.Exe(s.Ahk2Exe)
        bases := AxBuild.Bases(exe)
        used := AxComp.Used(s.P), all := 0
        for name, pack in AxComp.Packs
            all++
        r := AxForm.Show(s, {Title: "Compile", Icon: "E7B8", Width: 600,
            Intro: "Everything about making the program an .exe that runs without AutoHotkey installed. "
                 . "The first part is the same as App > Details. It is all written into the exported script, "
                 . "so compiling it any other way gives the same exe.",
            Fields: [
                {Id: "h1", Kind: "heading", L: "What the exe says it is"},
                {Id: "name", L: "Name",        Kind: "text", V: G("name", s.P.Main().Title)},
                {Id: "desc", L: "Description", Kind: "text", V: G("description")},
                {Id: "version", L: "Version",  Kind: "text", V: G("version", "1.0.0.0"),
                 Hint: "Four numbers. Windows shows it on the file's Details tab."},
                {Id: "company", L: "Company",  Kind: "text", V: G("company")},
                {Id: "copyright", L: "Copyright", Kind: "text", V: G("copyright")},
                {Id: "icon", L: "Icon",        Kind: "text", V: G("icon"),
                 Hint: "A .ico. This is the exe's own icon -- the tray's is under "
                     . "App > Tray icon, the window's in its title bar settings."},

                {Id: "h2", Kind: "heading", L: "The build"},
                {Id: "exeout",  L: "Output",  Kind: "text", V: G("exe"),
                 Hint: "Empty means the script's own name with .exe, beside it."},
                {Id: "base", L: "Built on",    Kind: "choice",
                 V: AxBuild.ResolveBase(G("base"), bases), Opts: AxWiz.BaseOpts(bases),
                 Hint: "Which AutoHotkey the exe is made from. It decides whether the exe is 32- or "
                     . "64-bit; the one that runs the studio is a safe choice."},
                {Id: "compress", L: "Compress", Kind: "choice", V: G("compress", "0"),
                 Opts: "0:No|1:With UPX, if it is installed|2:With MPRESS, if it is installed",
                 Hint: "Neither ships with AutoHotkey, and a compressed exe is more likely "
                     . "to be looked at twice by antivirus."},
                {Id: "admin", L: "Run as administrator", Kind: "flag",
                 V: AxAsset.Truthy(G("admin")),
                 Hint: "The same switch as App > Script settings. Windows asks before it starts; only if it "
                     . "genuinely needs it."},

                {Id: "h3", Kind: "heading", L: "What goes in"},
                {Id: "pre", L: "Prerender the window", Kind: "flag",
                 V: AxAsset.Truthy(G("prerender")),
                 Hint: "The markup goes into the script already built and already expanded, "
                     . "so opening the window is one parse instead of one per control. It is "
                     . "a copy of the design, so re-export after changing anything."},
                {Id: "prenote", Kind: "note", L: AxPre.Report(s, s.P),
                 When: (V) => V["pre"]},
                {Id: "embed", L: "The library's own files", Kind: "seg",
                 V: (StrLower(G("embed", "all")) = "used") ? "used" : "all",
                 Opts: "all:All of them|used:Only what this design reads",
                 Hint: "A compiled exe has to carry the stylesheet and the overlay markup, or "
                     . "it comes up unstyled anywhere lib is not sitting beside it. Measured on "
                     . "a one-button window: 1.22 MB with nothing, 2.06 MB with all of them, "
                     . "1.69 MB with only what the design reads. The smaller one would show as "
                     . "an unstyled window rather than a compile error if it ever missed one, "
                     . "which is why it is not the default."},
                {Id: "dev", L: "Keep the developer tools in the exe", Kind: "flag",
                 V: StrLower(G("devtools")) = "keep",
                 Hint: "The F12 inspector. Running the script as a .ahk always has it; a "
                     . "compiled exe leaves it out unless this is on. Keeping it also brings "
                     . "every component pack, because the inspector uses them, and lets "
                     . "anyone who presses F12 look inside the program."},
                {Id: "packs", Kind: "note", Mono: true, L: AxWiz.PackReport(s, used, all),
                 When: (V) => !V["dev"]},
                {Id: "packsall", Kind: "note", Mono: true,
                 L: "All " all " component packs -- the developer tools use every one of them.",
                 When: (V) => V["dev"]},
                {Id: "res", Kind: "note", Mono: true, L: AxWiz.ResourceReport(s)},
                {Id: "files", Kind: "note", L: AxWiz.FileReport(s)},

                {Id: "h4", Kind: "heading", L: "The compiler"},
                {Id: "where", Kind: "note", L: AxWiz.CompilerNote(exe, bases)},
                {Id: "path", L: "Ahk2Exe", Kind: "text", V: exe,
                 Hint: "Found for you. It ships with AutoHotkey and lives beside the "
                     . "installation rather than beside the interpreter, which is why it "
                     . "never turns up where you would look."}],
            Buttons: (exe != "") ? ["Save and compile", "Save", "Find it...", "Cancel"]
                                 : ["Save", "Find it...", "Get it...", "Cancel"],
            CancelIndex: (exe != "") ? 4 : 4,
            Preview: (V) => AxWiz.CompileLines(V)})
        if !r.Ok && r.Btn = 0
            return
        ; the two buttons that are not about saving
        if (r.Label = "Find it...")
            return AxWiz.FindCompiler(s)
        if (r.Label = "Get it...") {
            try Run(AxBuild.Page)
            return s.Status("msg", "Ahk2Exe comes with the AutoHotkey installer. "
                                 . "Install it, then open this again -- it will be found.")
        }
        if !r.Ok
            return
        AxWiz.SaveCompile(s, r.V)
        if (Trim(r.V["path"]) != "" && Trim(r.V["path"]) != s.Ahk2Exe) {
            s.Ahk2Exe := Trim(r.V["path"])
            s.SaveSettings()
        }
        if (r.Label = "Save and compile")
            AxWiz.Build(s)
        else
            s.Status("msg", "Compile settings saved. They go into the exported script.")
    }
    static SaveCompile(s, V) {
        s.Mark()
        out := ""
        A := (k, v) => (Trim(v) != "" ? out .= (out = "" ? "" : AxWiz.NL) k " = " Trim(v) : "")
        A("name", V["name"]), A("description", V["desc"]), A("version", V["version"])
        A("company", V["company"]), A("copyright", V["copyright"]), A("icon", V["icon"])
        A("exe", V["exeout"]), A("base", V["base"])
        if (V["compress"] != "" && V["compress"] != "0")
            A("compress", V["compress"])
        if V["admin"]
            A("admin", "yes")
        if V["pre"]
            A("prerender", "yes")
        if (V["embed"] = "used")
            A("embed", "used")
        if V["dev"]
            A("devtools", "keep")
        s.P.Compile := out
        s.Refresh()
    }
    static BaseOpts(bases) {
        out := ""
        for b in bases
            out .= (out = "" ? "" : "|") StrReplace(b.Path, "|", " ") ":"
                 . StrReplace(b.Label, "|", " ")
        return (out = "") ? ":none found" : out
    }
    static CompilerNote(exe, bases) {
        if (exe = "")
            return "Ahk2Exe is not on this machine, or not anywhere it usually is. It comes "
                 . "with the AutoHotkey installer -- Get it opens the download page -- or "
                 . "Find it if you keep a copy somewhere of your own."
        return "Found: " exe AxWiz.NL bases.Length " interpreter"
             . (bases.Length = 1 ? "" : "s") " to build on."
    }
    static FindCompiler(s) {
        f := FileSelect(3, "", "Where is Ahk2Exe.exe?", "Ahk2Exe (Ahk2Exe.exe)")
        if (f = "")
            return
        s.Ahk2Exe := f
        s.SaveSettings()
        s.Status("msg", "Ahk2Exe: " f)
        AxWiz.Compile(s)
    }

    ; Where the exe will be written: the name set under App (a bare name goes
    ; beside the script), or the script's own name with .exe. Blank while
    ; there is no script to put it beside.
    static ExeTarget(s, script := "") {
        if (script = "")
            script := s.ExportTarget()
        if (script = "")
            return ""
        cfg := AxAsset.Compile(s.P)
        out := cfg.Has("exe") ? Trim(cfg["exe"]) : ""
        SplitPath(script, , &dir, , &bare)
        if (out = "")
            return dir "\" bare ".exe"
        return InStr(out, "\") ? out : dir "\" out
    }

    ; Export first, then compile that. Compiling a script that is not the one
    ; on screen is the sort of thing that costs an afternoon.
    static Build(s) {
        exe := AxBuild.Exe(s.Ahk2Exe)
        if (exe = "")
            return s.Alert("Ahk2Exe is not on this machine. File > Compile has a Get it "
                         . "button.", "Compile")
        script := s.ExportTarget()
        if (script = "") {
            s.Status("msg", "Exporting first...")
            s.Export(true)
            script := s.ExportTarget()
        } else
            s.Export()
        if (script = "" || !FileExist(script))
            return s.Status("msg", "Nothing was exported, so there is nothing to compile.")
        cfg := AxAsset.Compile(s.P)
        G := (k, d := "") => cfg.Has(k) ? cfg[k] : d
        out := AxWiz.ExeTarget(s, script)
        icon := Trim(G("icon"))
        if (icon != "" && !InStr(icon, ":\")) {
            SplitPath(script, , &dir)
            icon := dir "\" icon
        }
        s.Status("msg", "Compiling...")
        base := AxBuild.ResolveBase(G("base"), AxBuild.Bases(exe))
        r := AxBuild.Compile(exe, script, out, base, icon, G("compress", 0))
        ; Ahk2Exe's own words go to Output, where there is room for them, rather
        ; than into a dialog that has to be dismissed a line at a time.
        s.Say(r.Ok ? "build" : "error", r.Msg)
        for line in StrSplit(StrReplace(String(r.Log), "`r", ""), "`n")
            if (Trim(line) != "")
                s.Say("build", Trim(line))
        s.SetMid("out")
        s.Status("msg", r.Msg)
        ; kept, so the App page can say how the last build went after the
        ; dialog and the Output lines are gone
        s.LastBuild := {Ok: r.Ok, Msg: r.Msg, Exe: r.Exe, When: FormatTime(, "HH:mm")}
        if (s.Ws = "app")
            s.Reflect(false)
        if !r.Ok
            return
        r2 := AxForm.Show(s, {Title: "Compiled", Icon: "E7B8", Width: 480, Intro: r.Msg,
            Fields: [{Id: "n", Kind: "note", Mono: true, L: r.Exe}],
            Buttons: ["Show it in Explorer", "Run it", "Done"], CancelIndex: 3})
        ; braced: a bare `try` as an if's body swallows the else
        if (r2.Label = "Show it in Explorer") {
            try Run('explorer.exe /select,"' r.Exe '"')
        } else if (r2.Label = "Run it") {
            try Run('"' r.Exe '"')
        }
    }

    ; Everything the exe carries, which is otherwise invisible until something
    ; is missing at run time.
    static ResourceReport(s) {
        res := AxBuild.Resources(s.P)
        if !res.Length
            return "Nothing is embedded."
        out := res.Length " file" (res.Length = 1 ? "" : "s") " embedded:" AxWiz.NL
        n := 0
        for r in res {
            if (++n > 6) {
                out .= "... and " (res.Length - 6) " more" AxWiz.NL
                break
            }
            out .= "  " r.What "   (" r.Why ")" AxWiz.NL
        }
        return RTrim(out, AxWiz.NL)
    }

    ; The only tree shaking that is safe here, and it is already done: the
    ; export includes the packs the design uses and no others.
    static PackReport(s, used, all) {
        names := ""
        for p in used
            names .= (names = "" ? "" : ", ") p.Name
        return used.Length " of " all " component packs:" AxWiz.NL
             . (names != "" ? names : "none -- the design uses only the core controls")
    }
    static FileReport(s) {
        files := AxAsset.Files(s.P)
        if !files.Length
            return "No files of your own are carried. Add one under App > Files."
        n := 0, r := 0
        for f in files {
            if (f.How = "install")
                n++
            else if (f.How = "resource")
                r++
        }
        return files.Length " file" (files.Length = 1 ? "" : "s") " of yours: " n
             . " written out on first run, " r " read from memory, "
             . (files.Length - n - r) " expected to be there already."
    }
    static CompileLines(V) {
        out := ""
        A := (d, v) => (Trim(v) != "" ? out .= (out = "" ? "" : AxWiz.NL) ";@Ahk2Exe-" d " "
                                              . Trim(v) : "")
        A("SetName", V["name"]), A("SetDescription", V["desc"])
        A("SetVersion", V["version"]), A("SetCompanyName", V["company"])
        A("SetCopyright", V["copyright"]), A("SetMainIcon", V["icon"])
        A("ExeName", V["exeout"]), A("Base", V["base"])
        if V["admin"]
            A("UpdateManifest", "1")
        out .= (out = "" ? "" : AxWiz.NL)
             . (V["dev"] ? "#Include ...\dev\AxInspector.ahk   (F12 kept)"
                         : "; no F12 inspector in the exe")
        return out
    }

    ; ------------------------------------------------------------ shared
    ; Where a generated line goes: startup, or the selected control's Click.
    static Place(s, where, code, what) {
        if (code = "")
            return
        s.Mark()
        if (where = "sel") {
            n := s.Primary()
            if IsObject(n) {
                ev := AxWiz.EnsureEvent(n, "Click")
                cur := RTrim(String(ev["code"]), "`r`n")
                ev["code"] := (Trim(cur) = "") ? code : cur "`n" code
                s.Refresh()
                s.OpenPrimaryEvent()
                return s.Status("msg", what " added to " n.Label "'s Click.")
            }
        }
        s.InsertInit(code)
        s.EditScript("init")
        s.Refresh()
        s.Status("msg", what " added to the startup code.")
    }
    static EnsureEvent(n, name) {
        for e in n.Ev
            if (e["name"] = name)
                return e
        e := Map("name", name, "code", "")
        n.Ev.Push(e)
        return e
    }
    ; An empty function, appended to the project's own code, so a hotkey that
    ; calls one does not fall over the first time it is pressed.
    static EnsureFn(s, name) {
        if (name = "" || InStr(s.P.Script, name "("))
            return
        nl := AxWiz.NL
        cur := RTrim(String(s.P.Script), "`r`n")
        body := name "() {" nl "    global g" nl "    g.Toast(" AxWiz.Q name AxWiz.Q ")" nl "}"
        s.P.Script := (Trim(cur) = "") ? body : cur nl nl body
    }
}
