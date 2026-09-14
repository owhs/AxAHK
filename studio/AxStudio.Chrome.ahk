#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Lit.ahk
#Include %A_LineFile%\..\AxStudio.Model.ahk
#Include %A_LineFile%\..\AxStudio.Bind.ahk

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
;  AxStudio.Chrome.ahk -- the window's own furniture: title bar items, the menu
;  bar and the status bar.
;
;  All three are authored as plain text, one thing per line. That is a
;  deliberate choice over a tree editor: a menu is a shape you read faster than
;  you click, and a text field is the only editor that stays out of the way
;  while you rough one out. The text parses into a structure, and the structure
;  drives both the canvas preview and the AutoHotkey the exporter writes -- so
;  what the canvas shows is what AddMenuBar will build.
;
;      status     id | Text | grow right w=150 icon=E930
;      menus      &File                       (indent marks a submenu)
;                     &New | Ctrl+N | g.Toast("New") | icon=E710
;                     &Dark mode | | | check=dark
;                     -
;      ctx        notes | notesBox                (a right-click menu, and what
;                     Cut | Ctrl+X | Send("^x")    it opens on: a control's
;                                                  name, or * for the window)
;                 an item's last cell, when it is only these, says more:
;                 icon=E8C6  its glyph   check=var  a tick that follows (and
;                 flips) a value   pick=var:value  one of a set   off  greyed
;                 out   default  the one a double-click on the tray means
;      titlebar   id | kind | content | right tip="..." toggle class=morph
;                 kinds: burger glyph text svg sep spacer
; =============================================================================
class AxChrome {

    ; ---------------------------------------------------------- line parsing
    ; "a | b | c" -> ["a", "b", "c"], with the pieces trimmed.
    static Cells(line) {
        out := []
        for part in StrSplit(line, "|")
            out.Push(Trim(part))
        return out
    }
    ; "grow right w=150 icon=E930" -> Map, with bare words mapped to 1.
    static Flags(s) {
        m := Map()
        pos := 1
        while RegExMatch(s, 'S)\s*(?:([A-Za-z][\w\-]*)=("[^"]*"|\S*)|(\S+))', &r, pos) {
            pos := r.Pos + r.Len
            if (r[1] != "") {
                v := r[2]
                if (SubStr(v, 1, 1) = '"')
                    v := SubStr(v, 2, -1)
                m[StrLower(r[1])] := v
            } else if (r[3] != "")
                m[StrLower(r[3])] := 1
            else
                break
        }
        return m
    }
    static Lines(text) {
        out := []
        for line in StrSplit(StrReplace(String(text), "`r", ""), "`n")
            if (Trim(line) != "")
                out.Push(line)
        return out
    }

    ; ================================================================ status
    static Status(text) {
        parts := []
        for line in AxChrome.Lines(text) {
            c := AxChrome.Cells(line)
            f := AxChrome.Flags(c.Length >= 3 ? c[3] : "")
            parts.Push({Id: c[1], Text: c.Length >= 2 ? c[2] : "",
                        Grow: f.Has("grow"), Right: f.Has("right"),
                        Width: f.Has("w") ? f["w"] : "", Icon: f.Has("icon") ? f["icon"] : "",
                        Dim: f.Has("dim")})
        }
        return parts
    }
    static StatusHtml(text, resizable := true) {
        parts := AxChrome.Status(text)
        if !parts.Length
            return ""
        h := '<div class="axsb">'
        for p in parts {
            st := (p.Width != "" ? "width:" p.Width "px;" : "")
            h .= '<div class="axsb-part' (p.Grow ? " grow" : "") (p.Right ? " right" : "")
              .  (p.Dim ? " dim" : "") '"' (st != "" ? ' style="' st '"' : "") '>'
              .  (p.Icon != "" ? '<span class="ico">&#x' AxTags.E(p.Icon) ';</span>' : "")
              .  AxTags.E(p.Text) '</div>'
        }
        if resizable
            h .= '<div class="axsb-grip ico">&#xE76F;</div>'
        return h '</div>'
    }
    static StatusCode(text) {
        parts := AxChrome.Status(text)
        if !parts.Length
            return ""
        s := ""
        for p in parts {
            o := "Id: " AxLit.S(p.Id) ", Text: " AxLit.S(p.Text)
            if (p.Icon != "")
                o .= ", Icon: " AxLit.S(p.Icon)
            if (p.Width != "")
                o .= ", Width: " AxLit.N(p.Width)
            if p.Grow
                o .= ", Grow: true"
            if p.Right
                o .= ', Align: "right"'
            if p.Dim
                o .= ", Dim: true"
            s .= (s = "" ? "" : ",`n                 ") "{" o "}"
        }
        return "[" s "]"
    }

    ; ================================================================= menus
    ; Indentation is the whole syntax: a line indented under another is one of
    ; its items, as deep as you like.
    static Menus(text) {
        root := [], stack := [{Depth: -1, Items: root}]
        for line in AxChrome.Lines(text) {
            ind := StrLen(line) - StrLen(LTrim(line, " `t"))
            body := Trim(line)
            while (stack.Length > 1 && ind <= stack[stack.Length].Depth)
                stack.Pop()
            c := AxChrome.Cells(body)
            fl := AxChrome.ItemFlags(c)
            code := ""
            loop c.Length - 2
                code .= (A_Index > 1 ? "|" : "") c[A_Index + 2]
            it := {Label: c[1], Shortcut: c.Length >= 2 ? c[2] : "", Code: Trim(code),
                   Sep: (c[1] = "-"), Items: [], Icon: fl.Get("icon", ""), Check: fl.Get("check", ""),
                   Pick: fl.Get("pick", ""), Off: fl.Has("off"), Default: fl.Has("default")}
            stack[stack.Length].Items.Push(it)
            stack.Push({Depth: ind, Items: it.Items})
        }
        return root
    }
    ; The last cell is flags when it holds nothing else (so code with || in
    ; it survives the split); it comes off the cells either way.
    static ItemFlags(c) {
        m := Map()
        if (c.Length >= 2 && RegExMatch(c[c.Length], "i)^(?:\s*(?:icon=\S+|check=\w+|pick=\w+:\S*|off|default)(?=\s|$))+\s*$")) {
            m := AxChrome.Flags(c.Pop())
        }
        return m
    }
    ; An item back as its line: label | shortcut | code | flags
    static ItemLine(it, depth := 0) {
        pad := ""
        loop depth
            pad .= "    "
        if it.Sep
            return pad "-"
        fl := Trim((it.Icon != "" ? "icon=" it.Icon " " : "") (it.Check != "" ? "check=" it.Check " " : "")
                 . (it.Pick != "" ? "pick=" it.Pick " " : "") (it.Off ? "off " : "") (it.Default ? "default" : ""))
        line := pad StrReplace(it.Label, "|", "/")
        if (it.Shortcut != "" || it.Code != "" || fl != "")
            line .= " | " it.Shortcut
        if (it.Code != "" || fl != "")
            line .= " | " it.Code
        if (fl != "")
            line .= " | " fl
        return line
    }
    static MenusText(items, depth := 0) {
        out := ""
        for it in items {
            out .= AxChrome.ItemLine(it, depth) "`n"
            if it.Items.Length
                out .= AxChrome.MenusText(it.Items, depth + 1)
        }
        return out
    }
    static MenuHtml(text) {
        menus := AxChrome.Menus(text)
        if !menus.Length
            return ""
        h := '<div class="axmb">'
        for m in menus
            h .= '<div class="axmb-item">' AxChrome.Amp(m.Label) '</div>'
        return h '</div>'
    }
    ; "&File" -> "File" with the access key underlined, which is what the bar
    ; shows once Alt has been pressed. "&&" is a literal ampersand.
    static Amp(s) {
        s := StrReplace(String(s), "&&", Chr(1))
        p := InStr(s, "&")
        if p {
            out := AxTags.E(SubStr(s, 1, p - 1))
                 . '<span class="axmb-key">' AxTags.E(SubStr(s, p + 1, 1)) '</span>'
                 . AxTags.E(SubStr(s, p + 2))
        } else
            out := AxTags.E(s)
        return StrReplace(out, Chr(1), "&amp;")
    }
    static MenuCode(text, state) {
        menus := AxChrome.Menus(text)
        if !menus.Length
            return ""
        s := ""
        for m in menus
            s .= (s = "" ? "" : ",`n             ") "{Title: " AxLit.S(m.Label)
              .  ", Items: " AxChrome.ItemsCode(m.Items, state, m.Label) "}"
        return "[" s "]"
    }
    static ItemsCode(items, state, path) {
        if !items.Length
            return "[]"
        s := ""
        for it in items {
            if it.Sep {
                s .= (s = "" ? "" : ", ") '"-"'
                continue
            }
            o := "Label: " AxLit.S(it.Label)
            if (it.Shortcut != "")
                o .= ", Shortcut: " AxLit.S(it.Shortcut)
            if (it.Icon != "")
                o .= ", Icon: " AxLit.S(it.Icon)
            if it.Off
                o .= ", Disabled: true"
            ; a tick that follows a value, and flips it when clicked (or, for
            ; one of a set, sets it to this one)
            flip := ""
            if (it.Check != "" || it.Pick != "") {
                v := AxProject.CleanName(it.Check != "" ? it.Check : StrSplit(it.Pick, ":")[1])
                pv := (it.Pick != "") ? AxLit.S(SubStr(it.Pick, InStr(it.Pick, ":") + 1)) : ""
                AxChrome.Global(state, v)
                o .= (it.Pick != "") ? ", Radio: true, Checked: (IsSet(" v ") && " v " = " pv ")" : ", Checked: (IsSet(" v ") && " v ")"
                flip := (it.Pick != "") ? v " := " pv : v " := !(IsSet(" v ") && " v ")"
                try if (IsObject(state.project) && AxBind.HasVar(state.project, v))
                    flip .= ", AxBindSync()"
            }
            if it.Items.Length
                o .= ", Items: " AxChrome.ItemsCode(it.Items, state, path "_" it.Label)
            else if (Trim(it.Code) != "" && flip != "" && !InStr(it.Code, "`n"))
                o .= ", Click: (*) => (" flip ", " Trim(it.Code) ")"
            else if (Trim(it.Code) != "")
                o .= ", Click: " AxChrome.Handler(it, state, path)
            else if (flip != "")
                o .= ", Click: (*) => (" flip ")"
            s .= (s = "" ? "" : ", ") "{" o "}"
        }
        return "[" s "]"
    }
    ; A value a menu flips is a global the builder and the handlers declare.
    static Global(state, v) {
        if (v = "" || !IsObject(state))
            return
        try state.all[v] := true
        try state.vars[v] := true
    }
    ; ====================================================== right-click menus
    ; A window's right-click menus: each top-level line is one ("name | on"),
    ; its items indented under it in the menu bar's own syntax. Each becomes
    ; a function that builds it -- called as it opens, so its ticks are true --
    ; registered on what it opens on: a control by name, or * for anywhere in
    ; the window. One with nothing to open on is still there for a step
    ; ("Show a menu") or your code: <window>_Menu_<name>().
    static Ctx(text) {
        out := []
        for m in AxChrome.Menus(text) {
            nm := AxProject.CleanName(m.Label)
            if (nm != "")
                out.Push({Name: nm, On: Trim(m.Shortcut), Items: m.Items})
        }
        return out
    }
    static CtxFn(w, name) => w.Var "_Menu_" AxProject.CleanName(name)
    static CtxCode(w, state) {
        reg := ""
        for m in AxChrome.Ctx(w.Ctx) {
            fn := AxChrome.CtxFn(w, m.Name)
            state.handlerList.Push({Name: fn, Sig: "", Body: "    return " AxChrome.ItemsCode(m.Items, state, fn)})
            if (m.On != "")
                reg .= w.Var ".ContextMenu(" AxLit.S((m.On = "window" || m.On = "*") ? "*" : m.On) ", " fn ")`n"
        }
        return reg
    }
    ; A one-liner goes inline; anything longer becomes a named function, so the
    ; menu declaration stays readable however much code hangs off it.
    static Handler(it, state, path) {
        code := Trim(it.Code, " `t`r`n")
        if !InStr(code, "`n")
            return "(*) => " code
        name := "menu_" AxProject.CleanName(path "_" it.Label)
        if (name = "menu_")
            name := "menu_item"
        while state.vars.Has(name)
            name := name "_"
        state.vars[name] := true
        state.handlerList.Push({Name: name, Sig: "*", Body: AxLit.Block(code, "    ")})
        return name
    }

    ; ============================================================= title bar
    static Items(text) {
        out := []
        for line in AxChrome.Lines(text) {
            c := AxChrome.Cells(line)
            f := AxChrome.Flags(c.Length >= 4 ? c[4] : "")
            kind := StrLower(c.Length >= 2 ? c[2] : "")
            if (kind = "")
                kind := "text"
            out.Push({Id: c[1], Kind: kind, Content: c.Length >= 3 ? c[3] : "",
                      Side: f.Has("right") ? "right" : "left",
                      Tip: f.Has("tip") ? f["tip"] : "", Class: f.Has("class") ? f["class"] : "",
                      Toggle: f.Has("toggle"), On: f.Has("on"),
                      Code: c.Length >= 5 ? c[5] : ""})
        }
        return out
    }
    static ItemInner(it) {
        switch it.Kind {
        case "burger": return '<span class="axtb-burger"><i></i><i></i><i></i></span>'
        case "glyph":  return '<span class="ico">&#x' AxTags.E(it.Content) ';</span>'
        case "svg":    return '<span class="ax-svg">' it.Content '</span>'
        case "sep", "spacer": return ""
        default:       return '<span class="axtb-text">' AxTags.E(it.Content) '</span>'
        }
    }
    ; The same markup AxWindow.Titlebar builds, so the sheet paints it the same.
    static ItemsHtml(text, side) {
        h := ""
        for it in AxChrome.Items(text) {
            if (it.Side != side)
                continue
            cls := "axtb-item kind-" it.Kind (it.Class != "" ? " " it.Class : "") (it.On ? " on" : "")
            h .= '<div class="' cls '"' (it.Tip != "" ? ' data-tip="' AxTags.E(it.Tip) '"' : "") '>'
              .  AxChrome.ItemInner(it) '</div>'
        }
        return h
    }
    static TitleCode(text, state) {
        items := AxChrome.Items(text)
        if !items.Length
            return ""
        s := ""
        for it in items {
            o := "Id: " AxLit.S(it.Id) ", Kind: " AxLit.S(it.Kind)
            if (it.Kind = "glyph")
                o .= ", Glyph: " AxLit.S(it.Content)
            else if (it.Kind = "svg")
                o .= ", Svg: " AxLit.S(it.Content)
            else if (it.Kind != "sep" && it.Kind != "spacer" && it.Kind != "burger")
                o .= ", Text: " AxLit.S(it.Content)
            if (it.Side = "right")
                o .= ', Side: "right"'
            if (it.Tip != "")
                o .= ", Tip: " AxLit.S(it.Tip)
            if (it.Class != "")
                o .= ", Class: " AxLit.S(it.Class)
            if it.Toggle
                o .= ", Toggle: true"
            if it.On
                o .= ", On: true"
            if (Trim(it.Code) != "")
                o .= ", Click: " AxChrome.Handler({Code: it.Code, Label: it.Id}, state, "title")
            s .= (s = "" ? "" : ",`n             ") "{" o "}"
        }
        return "[" s "]"
    }
}
