#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\AxStudio.Gen.ahk
#Include %A_LineFile%\..\AxStudio.Data.ahk

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
;  AxStudio.Acts.ahk -- the Actions row: what this control needs next.
;
;  A property sheet tells you what a control *is*. This is the other half:
;  the two or three things you are actually about to do to it. A tab strip
;  wants another tab. A text box wants a label above it and to be remembered
;  between runs. A button wants to be the accent one, or to close the window.
;  None of that is a property, and all of it is three fiddly steps by hand.
;
;  For(node) says which apply, Run(studio, id) does one. They are kept apart
;  from the property sheet because these *write code and controls*, not values
;  -- every one of them goes through Mark() and is a single undo.
;
;  Anything generated here calls only what the library actually has: Close,
;  Toast, Status, SetOptions, and the Text / Value / Checked / Enabled
;  accessors on a control. Nothing invented, because a helper that writes code
;  which does not run is worse than no helper.
; =============================================================================

class AxActs {
    ; --- what applies -------------------------------------------------
    static For(n) {
        out := []
        if !IsObject(n)
            return out
        t := n.Type
        e := AxCat.Has(t) ? AxCat.Get(t) : ""
        box := (t = "Page") || (IsObject(e) && e.Box)

        if (t = "Page") {
            AxActs._A(out, "page.add", "Add a page")
            AxActs._A(out, "page.dup", "Duplicate this page")
            AxActs._A(out, "page.icon", "Choose its nav icon...")
        } else if (t = "Tab") {
            AxActs._A(out, "tab.add", "Add a tab")
            AxActs._A(out, "tab.del", "Remove the last tab")
        } else if (t = "Grid") {
            AxActs._A(out, "tile.add", "Add a tile")
        }
        if box {
            AxActs._A(out, "kid.row", "A row of controls...")
            AxActs._A(out, "kid.one", "Add a control...")
            AxActs._A(out, "box.head", "Add a heading")
            AxActs._A(out, "box.bar", "Add an OK / Cancel bar")
        }
        if AxActs.HasOptions(n) {
            AxActs._A(out, "opt.add", "Add an option")
            AxActs._A(out, "opt.sort", "Sort them")
        }
        ; anything that holds a list can be filled from somewhere rather than
        ; typed out by hand
        if (AxData.Kind(t) != "")
            AxActs._A(out, "data.fill", "Fill it with data...")

        switch t {
        case "Button":
            AxActs._A(out, "btn.accent", n.Prop("kind", "") = "Accent" ? "Make it ordinary" : "Make it the accent one")
            AxActs._A(out, "btn.pair", "Add a Cancel beside it")
            AxActs._A(out, "btn.close", "Close the window when clicked")
        case "Link":
            AxActs._A(out, "link.url", "Open a web page when clicked...")
        case "Text":
            AxActs._A(out, "txt.caption", n.Prop("caption", "") ? "Back to ordinary text" : "Make it a heading")
            AxActs._A(out, "txt.hint", "Make it a hint")
        case "CheckBox", "Switch":
            AxActs._A(out, "chk.gate", "Turn another control on and off with it...")
        case "Slider":
            AxActs._A(out, "sld.echo", "Show its value in a label")
        case "Progress":
            AxActs._A(out, "prg.drive", "Drive it from a timer")
        case "Console":
            AxActs._A(out, "log.fn", "Add a Logger() helper that writes to it")
        case "AutoComplete":
            AxActs._A(out, "opt.fill", "Fill its suggestions from code")
        case "Image", "Picture":
            AxActs._A(out, "img.file", "Choose a picture...")
        case "Splitter":
            AxActs._A(out, "split.target", "Which control it resizes...")
        case "DropZone":
            AxActs._A(out, "drop.handle", "Handle what gets dropped on it")
        case "InfoBar":
            AxActs._A(out, "bar.close", n.Prop("noclose", "") ? "Give it a close button" : "Take its close button away")
        }

        if AxActs.IsInput(t) {
            AxActs._A(out, "in.label", "Put a label above it")
            AxActs._A(out, "in.ini", "Remember it between runs")
        }
        ; Duplicate, Delete and "Write its handler" were here too. They are on
        ; the bar on the selected control, in its right-click menu and on the
        ; keyboard, and its events are right below -- so only a page, which
        ; has no bar, keeps the first two.
        if (t != "Page")
            AxActs._A(out, "act.wrap", "Wrap it in a card")
        else {
            AxActs._A(out, "dup", "Duplicate")
            AxActs._A(out, "del", "Delete")
        }
        return out
    }
    static _A(out, id, label) => out.Push({Id: id, L: label})

    static HasOptions(n) {
        e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
        return IsObject(e) && IsObject(e.Arg) && e.Arg.Kind = "options"
    }
    ; A control the user types or picks a value in, which is the set that wants
    ; a label and is worth remembering between runs.
    static IsInput(t) {
        static set := "Edit|Password|Search|AutoComplete|Number|Hotkey|Slider|DDL|ListBox"
                    . "|CheckBox|Switch|Radio|Segmented|Rating|Palette|ColorButton"
                    . "|Date|Calendar|Tags|RangeSlider|ColorPicker"
        return RegExMatch(t, "i)^(" set ")$") ? true : false
    }
    ; How you read and write this one from code.
    static ValueProp(t) {
        if RegExMatch(t, "i)^(CheckBox|Switch)$")
            return "Checked"
        ; Text only where the element carrying the id is the box itself (an
        ; input) or plain words. A number box, an auto-complete and a hotkey
        ; box carry it on the frame round the input, and Text there would
        ; write over the frame -- the box turned into a bare number.
        if RegExMatch(t, "i)^(Edit|Password|Search|Text|Badge|Link)$")
            return "Text"
        return "Value"
    }
    ; What a control holds, in words -- for the binding pickers. "" for a
    ; control nothing can be bound to.
    static Holds(t) {
        static m := Map("Edit", "text", "Password", "text", "Search", "text", "AutoComplete", "text",
            "Number", "a number", "Slider", "a number", "Rating", "a number", "Progress", "a number", "Gauge", "a number",
            "CheckBox", "on or off", "Switch", "on or off",
            "DDL", "one of its options", "ListBox", "one of its options", "Radio", "one of its options",
            "Segmented", "one of its options", "Palette", "a colour", "ColorButton", "a colour", "ColorPicker", "a colour",
            "Hotkey", "a hotkey", "Date", "a date", "Calendar", "a date", "RangeSlider", "a range (lo,hi)",
            "Tags", "tags (a|b)", "Stepper", "the step it is on", "Breadcrumb", "where it is",
            "Text", "its words", "Badge", "its words", "Link", "its words", "InfoBar", "its words",
            "Stat", "its number", "Avatar", "a name", "CodeEditor", "its text", "RichText", "its text",
            "Chart", "its numbers (Name: 1,2,3)")
        return m.Has(t) ? m[t] : ""
    }
    ; A control that shows a value but cannot change it follows one way only.
    static Shows(t) => RegExMatch(t, "i)^(Text|Badge|Link|InfoBar|Stat|Avatar|Progress|Gauge|Chart)$") ? true : false

    ; --- doing one ----------------------------------------------------
    ; Returns true when it handled the id, so the caller can fall through to
    ; the actions that were here before this file was.
    static Run(s, id) {
        n := s.Primary()
        switch id {
        case "data.fill":    return (AxData.Wizard(s, n), true)
        case "box.head":     return AxActs.Head(s, n)
        case "box.bar":      return AxActs.ButtonBar(s, n)
        case "page.icon":    return (s.OpenIcons("p_icon"), true)
        case "opt.sort":     return AxActs.SortOptions(s, n)
        case "opt.fill":     return AxActs.FillOptions(s, n)
        case "btn.accent":   return AxActs.Flip(s, n, "kind", "Accent")
        case "txt.caption":  return AxActs.Flip(s, n, "caption", 1)
        case "txt.hint":     return AxActs.Flip(s, n, "hint", 1)
        case "btn.pair":     return AxActs.Cancel(s, n)
        case "btn.close":    return AxActs.CloseOnClick(s, n)
        case "link.url":     return AxActs.LinkUrl(s, n)
        case "chk.gate":     return AxActs.Gate(s, n)
        case "sld.echo":     return AxActs.Echo(s, n)
        case "prg.drive":    return AxActs.Drive(s, n)
        case "log.fn":       return AxActs.LogFn(s, n)
        case "img.file":     return AxActs.PickImage(s, n)
        case "split.target": return AxActs.SplitTarget(s, n)
        case "drop.handle":  return AxActs.DropHandler(s, n)
        case "bar.close":    return AxActs.Flip(s, n, "noclose", 1)
        case "in.label":     return AxActs.LabelAbove(s, n)
        case "in.ini":       return AxActs.Remember(s, n)
        case "act.handler":  return (s.OpenPrimaryEvent(), true)
        case "act.wrap":     return (s.GroupInto("Card"), true)
        }
        return false
    }

    ; --- the small ones -----------------------------------------------
    static Ok(s, n) => IsObject(n) && n.Type != "Root"
    ; The window a node belongs to, or the one being edited. Never "": three
    ; of the actions below write into a window's own code, and a blank here
    ; would be a dialog rather than a helper.
    static Win(s, n) {
        w := IsObject(n) ? s.P.WinOf(n) : ""
        return IsObject(w) ? w : s.P.W
    }
    static GVar(s, n) => AxActs.Win(s, n).Var
    static Done(s, msg) {
        s.Refresh()
        s.PushCompletions()
        s.Status("msg", msg)
        return true
    }
    ; A flag that is worth one click rather than a trip to the property sheet.
    static Flip(s, n, key, on) {
        if !AxActs.Ok(s, n)
            return true
        s.Mark()
        cur := n.Prop(key, "")
        n.P[key] := (cur = on) ? "" : on
        return AxActs.Done(s, (n.P[key] = "" ? "Turned off " : "Turned on ") key ".")
    }
    static Head(s, n) {
        if !AxActs.Ok(s, n)
            return true
        s.Mark()
        t := s.P.NewNode("Text")
        t.Arg := "Heading", t.P["caption"] := 1
        s.P.Insert(n, t, 1)
        s.SelIds := [t.Id]
        return AxActs.Done(s, "Added a heading.")
    }
    ; Two buttons on one line at the end of the box, both closing the window
    ; they are in -- which is the shape of nearly every dialog ever written.
    static ButtonBar(s, n) {
        if !AxActs.Ok(s, n)
            return true
        s.Mark()
        shut := AxActs.CloseCode(s, n)
        ok := s.P.NewNode("Button")
        ok.Arg := "OK", ok.P["kind"] := "Accent", ok.L["top"] := 12
        ok.Ev.Push(Map("name", "Click", "code", shut))
        s.P.Insert(n, ok, 0)
        no := s.P.NewNode("Button")
        no.Arg := "Cancel", no.L["place"] := "same"
        no.Ev.Push(Map("name", "Click", "code", shut))
        s.P.Insert(n, no, 0)
        s.SelIds := [ok.Id]
        return AxActs.Done(s, "Added a button bar.")
    }
    static Cancel(s, n) {
        if !AxActs.Ok(s, n) || !IsObject(n.Parent)
            return true
        s.Mark()
        no := s.P.NewNode("Button")
        no.Arg := "Cancel", no.L["place"] := "same"
        no.Ev.Push(Map("name", "Click", "code", AxActs.CloseCode(s, n)))
        s.P.Insert(n.Parent, no, s.P.IndexOf(n) + 1)
        s.SelIds := [no.Id]
        return AxActs.Done(s, "Added a Cancel beside it.")
    }
    ; Which window this control is in decides how it closes: the main one ends
    ; the script, any other just goes away.
    static CloseCode(s, n) => AxActs.GVar(s, n) ".Close()"
    static CloseOnClick(s, n) {
        if !AxActs.Ok(s, n)
            return true
        s.Mark()
        AxActs.SetEvent(n, "Click", AxActs.CloseCode(s, n))
        return AxActs.Done(s, "It closes the window now.")
    }
    static LinkUrl(s, n) {
        if !AxActs.Ok(s, n)
            return true
        url := s.Prompt("Which page should it open?", "Open a web page", "https://")
        if (url = "" || url = "https://")
            return true
        s.Mark()
        AxActs.SetEvent(n, "Click", 'Run(' AxActs.Q(url) ')')
        return AxActs.Done(s, "It opens " url " now.")
    }
    ; Sets an event's code, keeping whatever was already written there.
    static SetEvent(n, name, code) {
        for e in n.Ev {
            if (e["name"] != name)
                continue
            e["code"] := (Trim(e["code"]) = "") ? code : RTrim(e["code"], "`n") "`n" code
            return
        }
        n.Ev.Push(Map("name", name, "code", code))
    }
    static Q(v) => '"' StrReplace(String(v), '"', '`"') '"'

    ; --- options ------------------------------------------------------
    static SortOptions(s, n) {
        if !AxActs.Ok(s, n)
            return true
        lines := ""
        for line in StrSplit(StrReplace(String(n.Arg), "`r", ""), "`n")
            if (Trim(line) != "")
                lines .= (lines = "" ? "" : "`n") Trim(line)
        s.Mark()
        n.Arg := Sort(lines, "C")
        return AxActs.Done(s, "Sorted.")
    }
    static FillOptions(s, n) {
        if !AxActs.Ok(s, n) || Trim(n.Name) = ""
            return true
        gv := AxActs.GVar(s, n)
        code := "items := [" AxActs.Q("one") ", " AxActs.Q("two") ", " AxActs.Q("three") "]`n"
              . "out := " AxActs.Q("") "`n"
              . "for it in items`n"
              . "    out .= (out = " AxActs.Q("") " ? " AxActs.Q("") " : " AxActs.Q("|") ") it "
              . AxActs.Q(":") " it`n"
              . gv ".SetOptions(" AxActs.Q(n.Name) ", out)"
        return AxActs.ToInit(s, n, code, "Its suggestions are filled at startup now.")
    }

    ; --- inputs -------------------------------------------------------
    static LabelAbove(s, n) {
        if !AxActs.Ok(s, n) || !IsObject(n.Parent)
            return true
        s.Mark()
        t := s.P.NewNode("Text")
        t.Arg := AxActs.Nice(n)
        s.P.Insert(n.Parent, t, s.P.IndexOf(n))
        s.SelIds := [t.Id]
        return AxActs.Done(s, "Added a label above it.")
    }
    ; A readable starting label from whatever the control is called.
    static Nice(n) {
        v := RegExReplace(String(n.Name), "\d+$")
        v := RegExReplace(v, "([a-z])([A-Z])", "$1 $2")
        v := Trim(RegExReplace(v, "i)\b(box|edit|ctl|input|fld|field)\b", ""))
        if (v = "")
            v := "Label"
        return StrUpper(SubStr(v, 1, 1)) SubStr(v, 2)
    }
    ; Load it at startup, write it back when it changes. An ini beside the
    ; script, because that is where an AutoHotkey program keeps its settings
    ; and it needs no installer, no registry and no permissions.
    static Remember(s, n) {
        if !AxActs.Ok(s, n) || Trim(n.Name) = ""
            return true
        prop := AxActs.ValueProp(n.Type)
        key := AxActs.Q(n.Name)
        file := "A_ScriptDir " AxActs.Q("\settings.ini")
        sec := AxActs.Q("ui")
        s.Mark()
        AxActs.SetEvent(n, AxActs.ChangeEvent(n),
            "IniWrite(" n.Name "." prop ", " file ", " sec ", " key ")")
        load := "try " n.Name "." prop " := IniRead(" file ", " sec ", " key ", "
              . n.Name "." prop ")"
        return AxActs.ToInit(s, n, load, n.Name " is remembered between runs now.")
    }
    ; Whichever of the control's events means "the value moved".
    static ChangeEvent(n) {
        e := AxCat.Has(n.Type) ? AxCat.Get(n.Type) : ""
        if IsObject(e)
            for name in e.Events
                if (name = "Change")
                    return "Change"
        return "Click"
    }
    ; Append to the startup code of the window this control lives in -- not the
    ; project's, because there is one per window now.
    static ToInit(s, n, code, msg) {
        w := AxActs.Win(s, n)
        cur := RTrim(String(w.Init), " `t`r`n")
        w.Init := (cur = "") ? code : cur "`n" code
        return AxActs.Done(s, msg)
    }

    ; --- the type-specific ones ---------------------------------------
    ; A check box that greys something else out: the commonest two-control
    ; relationship there is, and four lines of hand-written wiring.
    static Gate(s, n) {
        if !AxActs.Ok(s, n) || Trim(n.Name) = ""
            return true
        items := []
        for x in AxActs.Siblings(s, n)
            items.Push({Label: x.Label, Click: AxActs.GateFn(s, n, x)})
        if !items.Length
            return (s.Alert("There is nothing else named in this window to turn on and off."
                          . "`n`nGive another control a name first.", "Turn on and off"), true)
        s.ShowMenu(items)
        return true
    }
    static GateFn(s, n, other) => (*) => AxActs.DoGate(s, n, other)
    static DoGate(s, n, other) {
        s.Mark()
        prop := AxActs.ValueProp(n.Type)
        AxActs.SetEvent(n, AxActs.ChangeEvent(n), other.Name ".Enabled := " n.Name "." prop)
        AxActs.ToInit(s, n, other.Name ".Enabled := " n.Name "." prop,
                      n.Name " now turns " other.Name " on and off.")
        return true
    }
    static Echo(s, n) {
        if !AxActs.Ok(s, n) || Trim(n.Name) = "" || !IsObject(n.Parent)
            return true
        s.Mark()
        t := s.P.NewNode("Text")
        t.Arg := "0", t.L["place"] := "same"
        s.P.Insert(n.Parent, t, s.P.IndexOf(n) + 1)
        AxActs.SetEvent(n, AxActs.ChangeEvent(n), t.Name ".Text := " n.Name ".Value")
        s.SelIds := [t.Id]
        return AxActs.Done(s, "Its value shows in " t.Name ".")
    }
    static Drive(s, n) {
        if !AxActs.Ok(s, n) || Trim(n.Name) = ""
            return true
        s.Mark()
        w := AxActs.Win(s, n)
        gv := w.Var
        fn := AxProject.CleanName(n.Name) "Tick"
        body := fn "() {`n"
              . "    global " gv ", " n.Name "`n"
              . "    v := " n.Name ".Value + 5`n"
              . "    " n.Name ".Value := (v > 100) ? 0 : v`n"
              . "}"
        cur := RTrim(String(w.Script), " `t`r`n")
        w.Script := (cur = "") ? body : cur "`n`n" body
        AxActs.ToInit(s, n, "SetTimer(" fn ", 200)", "A timer drives " n.Name " now.")
        return true
    }
    static LogFn(s, n) {
        if !AxActs.Ok(s, n) || Trim(n.Name) = ""
            return true
        s.Mark()
        w := AxActs.Win(s, n)
        body := "AppendLog(text) {`n"
              . "    global " n.Name "`n"
              . "    " n.Name ".Text := " n.Name ".Text FormatTime(, " AxActs.Q("HH:mm:ss")
              . ") " AxActs.Q("  ") " text " AxActs.Q("`n") "`n"
              . "}"
        cur := RTrim(String(w.Script), " `t`r`n")
        w.Script := (cur = "") ? body : cur "`n`n" body
        return AxActs.Done(s, "AppendLog(text) writes into " n.Name ".")
    }
    static PickImage(s, n) {
        if !AxActs.Ok(s, n)
            return true
        f := FileSelect(3, , "Choose a picture", "Images (*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.ico;*.svg)")
        if (f = "")
            return true
        s.Mark()
        n.Arg := f
        return AxActs.Done(s, "Picture set.")
    }
    ; A splitter needs to know which of its neighbours it is sizing.
    static SplitTarget(s, n) {
        if !AxActs.Ok(s, n)
            return true
        items := []
        for x in AxActs.Siblings(s, n)
            items.Push({Label: x.Label, Click: AxActs.TargetFn(s, n, x)})
        if !items.Length
            return (s.Alert("Give the control it should resize a name first.", "Splitter"), true)
        s.ShowMenu(items)
        return true
    }
    static TargetFn(s, n, other) => (*) => AxActs.DoTarget(s, n, other)
    static DoTarget(s, n, other) {
        s.Mark()
        n.P["target"] := other.Name
        return AxActs.Done(s, "It resizes " other.Name " now.")
    }
    static DropHandler(s, n) {
        if !AxActs.Ok(s, n)
            return true
        s.Mark()
        gv := AxActs.GVar(s, n)
        AxActs.SetEvent(n, "Drop",
            "for f in files`n"
            . "    " gv ".Toast(" AxActs.Q("Dropped ") " f)")
        return AxActs.Done(s, "It handles dropped files now.")
    }
    ; Every named control in the same window, apart from this one -- the list
    ; anything that points at another control has to choose from.
    static Siblings(s, n) {
        out := []
        s.P.Walk(AxActs.Win(s, n).Root, AxActs.PickFn(n, out))
        return out
    }
    static PickFn(n, out) =>
        (x) => (x.Type != "Page" && Trim(x.Name) != "" && !AxProject.Same(x, n)
                ? out.Push(x) : "", false)
}
