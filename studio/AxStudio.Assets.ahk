#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Model.ahk
#Include %A_LineFile%\..\AxStudio.Lit.ahk
#Include %A_LineFile%\..\AxStudio.Catalog.ahk
#Include %A_LineFile%\..\AxStudio.Comp.ahk
#Include %A_LineFile%\..\AxStudio.Bind.ahk
#Include %A_LineFile%\..\AxStudio.Flow.ahk
#Include %A_LineFile%\..\AxStudio.Auto.ahk
#Include %A_LineFile%\..\AxStudio.Auto2.ahk

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
;  AxStudio.Assets.ahk -- the script's outside.
;
;  A window is not a program. A program also has: files it needs at run time
;  and some way of getting them to whoever runs it, other code it includes,
;  arguments it accepts, named ways of starting, and a tray icon. None of that
;  belongs to any one window, and none of it was anywhere in the studio.
;
;  Each is text, one thing per line, for the same reason the menu bar is: text
;  is what you can read back, diff, paste and search, and a wizard is a way of
;  writing a line of it without learning the grammar first.
;
;  FILES              name | path | how
;      how = install    FileInstall() -- the file is built into the exe and
;                       written out beside the script the first time it runs.
;                       Compiled only; loose, FileInstall just copies.
;          = resource   ;@Ahk2Exe-AddResource -- built into the exe and read
;                       from memory, never written to disk. This is what the
;                       library itself uses for its stylesheets.
;          = path       an ordinary path worked out at run time. Nothing is
;                       carried; the file has to be there.
;
;  INCLUDES           a path, or <LibName> for a library include
;  ARGS               name | default | what it is for
;  MODES              name | verb what, verb what
;  TRAY               one  key = value  per line, then the menu items
;
;  Everything here generates plain AutoHotkey into its own region, so a
;  round trip keeps hand edits (see AxStudio.Merge.ahk).
; =============================================================================
class AxAsset {
    static Q := Chr(34)
    static NL := Chr(10)

    ; ------------------------------------------------------------ parsing
    ; The lines of a field, blank ones and comments dropped.
    static Lines(text) {
        out := []
        for raw in StrSplit(StrReplace(String(text), "`r", ""), "`n") {
            t := Trim(raw)
            if (t != "" && SubStr(t, 1, 1) != ";")
                out.Push(t)
        }
        return out
    }
    ; "a | b | c" -> ["a", "b", "c"], trimmed, short lines padded with "".
    static Parts(line, n) {
        out := []
        for p in StrSplit(line, "|")
            out.Push(Trim(p))
        while (out.Length < n)
            out.Push("")
        return out
    }

    ; =============================================================== files
    static Files(p) {
        out := []
        for line in AxAsset.Lines(p.Files) {
            f := AxAsset.Parts(line, 3)
            if (f[1] = "")
                continue
            how := StrLower(f[3])
            if (how != "install" && how != "resource" && how != "path")
                how := "install"
            out.Push({Name: f[1], Path: (f[2] != "" ? f[2] : f[1]), How: how, Line: line})
        }
        return out
    }
    static FileLine(name, path, how) => name " | " path " | " how
    ; What a file is called in the generated script: a function that hands back
    ; where it is, so the rest of the code never has to care how it got there.
    static FileFn(name) => "File_" AxProject.CleanName(name)
    static HowWords(how) {
        static w := Map("install", "built into the exe, written out beside it on first run",
                        "resource", "built into the exe, read straight from memory",
                        "path", "not carried -- it has to be there already")
        return w.Has(how) ? w[how] : how
    }

    ; The region: one accessor per file, and the directives that carry it.
    ;
    ;   ;@Ahk2Exe-AddResource lines have to be in the source for the compiler
    ;   to see them, and are a comment to the interpreter -- so they cost a
    ;   loose script nothing.
    static FilesCode(p) {
        files := AxAsset.Files(p)
        if !files.Length
            return ""
        q := AxAsset.Q, nl := AxAsset.NL
        s := ""
        for f in files {
            if (f.How = "resource")
                s .= ";@Ahk2Exe-AddResource " f.Path ", " f.Name nl
        }
        if (s != "")
            s .= nl
        for f in files {
            fn := AxAsset.FileFn(f.Name)
            s .= "; " f.Name " -- " AxAsset.HowWords(f.How) nl
            s .= "; " (f.How = "resource" ? "Hands back the CONTENT." : "Hands back the PATH.") nl
            s .= fn "() {" nl
            switch f.How {
            case "install":
                ; written out under the file's own name (prices.csv), not the
                ; name the code knows it by (prices)
                SplitPath(f.Path, &fname)
                s .= "    out := A_ScriptDir " q "\" (fname != "" ? fname : f.Name) q nl
                  .  "    if !FileExist(out)" nl
                  .  "        FileInstall(" q f.Path q ", out, false)" nl
                  .  "    return out" nl
            case "resource":
                ; A resource is CONTENT, not a path -- it never touches the
                ; disk. AxSys.ResourceText reads it out of the exe as text
                ; (Resource is the raw Buffer) and hands back "" when the
                ; script is loose, so the file beside it is the fallback and a
                ; loose run behaves the same.
                s .= "    t := AxSys.ResourceText(" q f.Name q ")" nl
                  .  "    if (t != " q q ")" nl
                  .  "        return t" nl
                  .  "    return FileRead(" AxAsset.PathExpr(f.Path) ", " q "UTF-8" q ")" nl
            default:
                s .= "    return " AxAsset.PathExpr(f.Path) nl
            }
            s .= "}" nl nl
        }
        return RTrim(s, "`n")
    }
    ; A path field may hold a built-in variable rather than a literal.
    ; With the project: "@prices", or a path that is on App > Files as a file
    ; the program carries and writes out (or looks for), is File_prices() --
    ; so a rule that loads a file loads the one the exe carries.
    static PathExpr(t, p := "") {
        t := Trim(String(t))
        if (SubStr(t, 1, 1) = "@")
            return AxAsset.FileFn(SubStr(t, 2)) "()"
        if IsObject(p)
            for f in AxAsset.Files(p)
                if (f.How != "resource" && (f.Path = t || f.Name = t && !InStr(t, ".")))
                    return AxAsset.FileFn(f.Name) "()"
        if RegExMatch(t, "^%(A_\w+)%\\?(.*)$", &m)
            return m[1] (m[2] != "" ? " " AxAsset.Q "\" m[2] AxAsset.Q : "")
        if (SubStr(t, 1, 1) = "\" || InStr(t, ":\") = 2)
            return AxAsset.Q t AxAsset.Q            ; already absolute
        return "A_ScriptDir " AxAsset.Q "\" t AxAsset.Q
    }

    ; ============================================================ includes
    static Includes(p) {
        out := []
        for line in AxAsset.Lines(p.Includes) {
            t := Trim(line)
            lib := (SubStr(t, 1, 1) = "<" && SubStr(t, -1) = ">")
            out.Push({Path: t, Lib: lib, Line: line})
        }
        return out
    }
    static IncludesCode(p) {
        s := ""
        for i in AxAsset.Includes(p)
            s .= "#Include " (i.Lib ? i.Path : AxAsset.IncQuote(i.Path)) AxAsset.NL
        return RTrim(s, "`n")
    }
    ; #Include takes a path, not a string: it is quoted only when it has a
    ; space in it, and never escaped.
    static IncQuote(path) => InStr(path, " ") ? AxAsset.Q path AxAsset.Q : path

    ; =========================================================== arguments
    static Args(p) {
        out := []
        for line in AxAsset.Lines(p.Args) {
            f := AxAsset.Parts(line, 3)
            name := AxProject.CleanName(f[1])
            if (name = "")
                continue
            out.Push({Name: name, Def: f[2], Desc: f[3], Line: line})
        }
        return out
    }
    static ArgLine(name, def, desc) => name " | " def " | " desc
    ; --name value, --flag, or a bare word in order. Written out in full
    ; rather than pulled from a library, because this is the part people most
    ; often want to change.
    static ArgsCode(p) {
        args := AxAsset.Args(p)
        if !args.Length
            return ""
        q := AxAsset.Q, nl := AxAsset.NL
        names := ""
        for a in args
            names .= (names = "" ? "" : ", ") a.Name
        s := "global " names nl nl
        s .= "; What the script accepts on the command line." nl
        for a in args
            s .= ";   --" a.Name (a.Desc != "" ? "   " a.Desc : "") nl
        ; the NAMES, not a bare  global : a bare one puts the function into
        ; assume-global mode, and then its loop counter is a global too
        s .= "ReadArgs() {" nl "    global " names nl
        for a in args
            s .= "    " a.Name " := " AxAsset.DefExpr(a.Def) nl
        s .= "    i := 1" nl
             . "    while (i <= A_Args.Length) {" nl
             . "        a := A_Args[i], v := (i < A_Args.Length) ? A_Args[i + 1] : " q q nl
             . "        switch a {" nl
        for a in args
            s .= "        case " q "--" a.Name q ", " q "-" SubStr(a.Name, 1, 1) q ": "
              .  a.Name " := (v != " q q " && SubStr(v, 1, 1) != " q "-" q ") ? (i++, v) : true" nl
        s .= "        }" nl
             . "        i++" nl
             . "    }" nl
             . "}" nl
        return s
    }

    ; A default is plain text, because that is what a command line carries.
    ; A number or true/false is written bare, so a flag really is a flag.
    static DefExpr(v) {
        t := Trim(String(v))
        if (t = "")
            return AxAsset.Q AxAsset.Q
        if (t = "true" || t = "false" || IsNumber(t))
            return t
        return AxLit.S(t)
    }

    ; =============================================================== modes
    ; A mode is a named way of starting: --mode setup, or the first bare
    ; argument. What it does is the same grammar a rule uses, so nothing new
    ; has to be learned to write one.
    static Modes(p) {
        out := []
        for line in AxAsset.Lines(p.Modes) {
            f := AxAsset.Parts(line, 2)
            name := AxProject.CleanName(f[1])
            if (name = "")
                continue
            steps := []
            for part in StrSplit(f[2], ",")
                if (Trim(part) != "")
                    steps.Push(Trim(part))
            out.Push({Name: name, Steps: steps, Line: line})
        }
        return out
    }
    static ModeLine(name, steps) => name " | " steps
    static ModesCode(p, project) {
        modes := AxAsset.Modes(p)
        if !modes.Length
            return ""
        q := AxAsset.Q, nl := AxAsset.NL
        s := "; Named ways of starting. Mode(" q "setup" q ") from anywhere, or" nl
           . "; pass --mode <name> on the command line." nl
           . "Mode(name) {" nl
           . "    global g" nl
           . "    switch name {" nl
        for m in modes {
            s .= "    case " q m.Name q ":" nl
            body := ""
            for step in m.Steps {
                line := AxAsset.StepCode(project, step)
                if (line != "")
                    body .= "        " line nl
            }
            s .= (body != "" ? body : "        `; nothing yet" nl)
        }
        s .= "    }" nl "}" nl
        return s
    }
    ; One step of a mode, in the rule grammar: "verb what".
    static StepCode(project, step) {
        q := AxAsset.Q
        t := Trim(step)
        p := InStr(t, " ")
        verb := StrLower(p ? SubStr(t, 1, p - 1) : t)
        arg := p ? Trim(SubStr(t, p + 1)) : ""
        switch verb {
        case "toast":   return "g.Toast(" AxLit.S(arg) ")"
        case "page":    return "g.ShowPage(" AxLit.S(arg) ")"
        ; the MAIN window: a mode belongs to the script, not to whichever
        ; window happened to be open in the designer when it was written
        case "state":   return AxProject.CleanName(project.Main().Name) "State(" AxLit.S(arg) ")"
        case "hide":    return "g.Hide()"
        case "show":    return "g.Show()"
        case "exit":    return "ExitApp()"
        case "run":     return "Run(" AxLit.S(arg) ")"
        case "open":    return "Show" AxProject.CleanName(arg) "()"
        case "send":    return "Send(" AxLit.S(arg) ")"
        case "type":
            ; "type the date" and "type the time" type them, as they are then
            if (StrLower(arg) = "the date")
                return "SendText(FormatTime(, " q "yyyy-MM-dd" q "))"
            if (StrLower(arg) = "the time")
                return "SendText(FormatTime(, " q "HH:mm" q "))"
            return "SendText(" AxLit.S(arg) ")"
        case "set", "assign":
            one := RegExMatch(arg, "^(\S+)", &m) ? m[1] : ""
            rest := Trim(SubStr(arg, StrLen(one) + 1))
            if (one = "")
                return "`; " t
            if AxBind.HasVar(project, one)
                return one " := " AxFlow.V(rest) (AxBind.Any(project) ? ", AxBindSync()" : "")
            return one "." AxFlow.PropOf(project, one) " := " AxFlow.V(rest)
        case "start":   return "TimerStart(" AxLit.S(arg) ")"
        case "stop":    return "TimerStop(" AxLit.S(arg) ")"
        case "wait":    return "Sleep(" (IsNumber(arg) ? arg : 500) ")"
        case "beep":    return "SoundBeep()"
        ; a box, a note by the clock, another window to the front -- what a
        ; hotkey or a timer of a script with no window of its own does most
        case "message": return "MsgBox(" AxLit.S(arg) ")"
        case "notify":  return "TrayTip(" AxLit.S(arg) ")"
        case "activate": return "WinActivate(" AxLit.S(arg) ")"
        case "call":    return AxProject.CleanName(arg) "()"
        case "front":   return "(g.Show(), WinActivate(" q "ahk_id " q " g.Hwnd))"
        case "toggle":  return "(g.Visible ? g.Hide() : (g.Show(), WinActivate(" q "ahk_id " q " g.Hwnd)))"
        case "reload":  return "Reload()"
        ; a macro, starting with Windows, and the program's own settings: each
        ; only where there is one, or the export would call what is not there
        case "play":
            m := AxProject.CleanName(arg)
            return IsObject(AxAuto2.FindMacro(project, m)) ? "Macro_" m "()" : "`; there is no macro called " m
        case "startup": return "AxStartup(" ((arg = "" || AxAsset.Truthy(arg)) ? 1 : 0) ")"
        case "save", "load", "reset":
            if (StrLower(arg) != "settings" || !AxAuto2.Settings(project).Length)
                return "`; " t
            sync := AxBind.Any(project) ? ", AxBindSync()" : ""
            switch verb {
            case "save": return "SettingsSave()"
            case "load": return "SettingsLoad()" sync
            default:     return "SettingsReset()" sync
            }
        }
        return "`; " t
    }

    ; ================================================================ tray
    ; key = value lines, then the menu. Kept as one field because the icon and
    ; the menu are the same thing to whoever is looking at the tray.
    ;
    ;     show = yes            tip = My program        icon = shell32.dll,13
    ;     click = Show          (what one click on the icon does: an item)
    ;     Show
    ;     Dark mode | | check=dark
    ;     Tools                 (indented under it: a submenu)
    ;         Open the folder | Run(A_ScriptDir) | icon=shell32.dll,3
    ;     -
    ;     Exit
    ;
    ; An item is  Label | code | flags  -- the flags as in AxStudio.Chrome.ahk
    ; (check=, pick=, off, default, icon=file,n). With no code, Show, Hide,
    ; Toggle, Exit, Reload, Suspend hotkeys, Pause and Open the folder are
    ; written for you.
    static Tray(p) {
        cfg := {Show: true, Icon: "", Tip: "", Single: false, Click: "", Items: [], Tree: []}
        patches := []
        for line in StrSplit(StrReplace(String(p.Tray), "`r"), "`n") {
            if (Trim(line) = "" || SubStr(Trim(line), 1, 1) = ";")
                continue
            if RegExMatch(line, "^\s*([A-Za-z]\w*)\s*=\s*(.*)$", &m) && !InStr(line, "|") {
                k := StrLower(m[1]), v := Trim(m[2])
                switch k {
                case "show":   cfg.Show := AxAsset.Truthy(v)
                case "icon":   cfg.Icon := v
                case "tip":    cfg.Tip := v
                case "single": cfg.Single := AxAsset.Truthy(v)
                case "click":  cfg.Click := v
                default:       cfg.Items.Push(line)
                }
                continue
            }
            if (SubStr(Trim(line), 1, 1) = "@") {
                patches.Push(SubStr(Trim(line), 2))
                continue
            }
            cfg.Items.Push(line)
        }
        cfg.Tree := AxAsset.TrayTree(cfg.Items)
        ; "@Label | flags": more said about an item written above (what an
        ; imported script said about it in later lines -- its icon, greyed
        ; out, the default); folded in, and gone the first time it is saved
        for pt in patches {
            c := AxChrome.Cells(pt)
            it := AxAsset.TrayFind(cfg.Tree, c[1])
            if !IsObject(it) || c.Length < 2
                continue
            fl := AxChrome.Flags(c[2])
            if fl.Has("icon")
                it.Icon := fl["icon"]
            if fl.Has("off")
                it.Off := true
            if fl.Has("default")
                it.Default := true
        }
        return cfg
    }
    static TrayFind(items, label) {
        for it in items {
            if (!it.Sep && it.Label = label)
                return it
            if it.Items.Length && IsObject(x := AxAsset.TrayFind(it.Items, label))
                return x
        }
        return ""
    }
    ; the menu lines as a tree: {Label, Code, Icon, Check, Pick, Off, Default, Sep, Items}
    static TrayTree(lines) {
        root := [], stack := [{Depth: -1, Items: root}]
        for line in lines {
            ind := StrLen(line) - StrLen(LTrim(line, " `t"))
            c := AxChrome.Cells(Trim(line))
            fl := AxChrome.ItemFlags(c)
            code := ""
            loop c.Length - 1
                code .= (A_Index > 1 ? "|" : "") c[A_Index + 1]
            it := {Label: c[1], Shortcut: "", Code: Trim(code), Sep: (c[1] = "-"), Items: [],
                   Icon: fl.Get("icon", ""), Check: fl.Get("check", ""), Pick: fl.Get("pick", ""),
                   Off: fl.Has("off"), Default: fl.Has("default")}
            while (stack.Length > 1 && ind <= stack[stack.Length].Depth)
                stack.Pop()
            stack[stack.Length].Items.Push(it)
            stack.Push({Depth: ind, Items: it.Items})
        }
        return root
    }
    ; one item back as its tray line
    static TrayLine(it, depth := 0) {
        pad := ""
        loop depth
            pad .= "    "
        if it.Sep
            return pad "-"
        fl := Trim((it.Icon != "" ? "icon=" it.Icon " " : "") (it.Check != "" ? "check=" it.Check " " : "")
                 . (it.Pick != "" ? "pick=" it.Pick " " : "") (it.Off ? "off " : "") (it.Default ? "default" : ""))
        return pad StrReplace(it.Label, "|", "/") (it.Code != "" || fl != "" ? " | " it.Code : "") (fl != "" ? " | " fl : "")
    }
    static TrayText(cfg) {
        out := "show = " (cfg.Show ? "yes" : "no")
        if (cfg.Tip != "")
            out .= "`ntip = " cfg.Tip
        if (cfg.Icon != "")
            out .= "`nicon = " cfg.Icon
        if (cfg.Click != "")
            out .= "`nclick = " cfg.Click
        out .= AxAsset._TrayLines(cfg.Tree, 0)
        return out
    }
    static _TrayLines(items, depth) {
        out := ""
        for it in items {
            out .= "`n" AxAsset.TrayLine(it, depth)
            if it.Items.Length
                out .= AxAsset._TrayLines(it.Items, depth + 1)
        }
        return out
    }
    static Truthy(v) {
        v := StrLower(Trim(String(v)))
        return (v = "1" || v = "yes" || v = "on" || v = "true")
    }
    ; Windows' own menu, made from the tree: each item's code in a function
    ; of its own (so it may set the program's values), a submenu a Menu() of
    ; its own, icons from files, ticks that follow values -- brought up to
    ; date each time the menu is opened (the icon's own message, 0x404).
    static TrayCode(p) {
        if (Trim(String(p.Tray)) = "")
            return ""
        cfg := AxAsset.Tray(p)
        nl := AxAsset.NL
        if !cfg.Show {
            ; nothing else is worth writing: with no icon there is no menu
            return "#NoTrayIcon"
        }
        s := ""
        if (cfg.Tip != "")
            s .= "A_IconTip := " AxLit.S(cfg.Tip) nl
        if (cfg.Icon != "")
            s .= "try TraySetIcon(" AxAsset.IconArgs(cfg.Icon) ")" nl
        if !cfg.Tree.Length
            return RTrim(s, "`n")
        st := {Fns: "", Ticks: "", N: 0, Default: "", Click: cfg.Click, Vars: Map(), P: p}
        s .= "A_TrayMenu.Delete()" nl
        s .= AxAsset._TrayMenu(cfg.Tree, "A_TrayMenu", st)
        if (st.Default = "")
            for it in cfg.Tree
                if (!it.Sep && !it.Items.Length) {
                    st.Default := it.Label
                    break
                }
        if (cfg.Click != "" && cfg.Click != "default")
            st.Default := cfg.Click
        if (st.Default != "")
            s .= "A_TrayMenu.Default := " AxLit.S(st.Default) nl
        if (cfg.Click != "")
            s .= "A_TrayMenu.ClickCount := 1" nl
        if (st.Ticks != "") {
            s .= "AxTrayTicks()" nl
               . "OnMessage(0x404, (w, l, *) => (l = 0x204 || l = 0x205) ? AxTrayTicks() : " '""' ")" nl
               . "AxTrayTicks() {" nl st.Ticks "}" nl
        }
        return RTrim(s st.Fns, "`n")
    }
    static _TrayMenu(items, mv, st) {
        nl := AxAsset.NL, s := ""
        for it in items {
            if it.Sep {
                s .= mv ".Add()" nl
                continue
            }
            lab := AxLit.S(it.Label)
            if it.Items.Length {
                sub := "AxTrayMenu" (++st.N)
                s .= sub " := Menu()" nl AxAsset._TrayMenu(it.Items, sub, st)
                s .= mv ".Add(" lab ", " sub ")" nl
            } else {
                fn := "AxTrayItem" (++st.N)
                body := AxAsset.TrayBody(it, st.P)
                st.Fns .= nl fn "(*) {" nl "    global" nl AxLit.Block(body, "    ") nl "}"
                s .= mv ".Add(" lab ", " fn ")" nl
            }
            ; icons from a file (a glyph cannot go in Windows' own menu)
            if (it.Icon != "" && !RegExMatch(it.Icon, "^[0-9A-Fa-f]{4}$"))
                s .= "try " mv ".SetIcon(" lab ", " AxAsset.IconArgs(it.Icon) ")" nl
            if it.Off
                s .= mv ".Disable(" lab ")" nl
            if (it.Default && mv = "A_TrayMenu")
                st.Default := it.Label
            if (it.Check != "" || it.Pick != "") {
                v := AxProject.CleanName(it.Check != "" ? it.Check : StrSplit(it.Pick, ":")[1])
                test := (it.Pick != "") ? "IsSet(" v ") && " v " = " AxLit.S(SubStr(it.Pick, InStr(it.Pick, ":") + 1)) : "IsSet(" v ") && " v
                if !st.Vars.Has(v)
                    st.Vars[v] := true, st.Ticks := "    global " v nl st.Ticks
                st.Ticks .= "    if (" test ")" nl "        " mv ".Check(" lab ")" nl "    else" nl "        " mv ".Uncheck(" lab ")" nl
            }
            if (StrLower(Trim(it.Code)) = "" && RegExMatch(StrLower(it.Label), "^(suspend|pause)"))
                st.Ticks .= "    if " (InStr(StrLower(it.Label), "suspend") ? "A_IsSuspended" : "A_IsPaused") nl "        " mv ".Check(" lab ")" nl "    else" nl "        " mv ".Uncheck(" lab ")" nl
        }
        return s
    }
    ; what an item runs: its code, a tick flipped, or what its label says
    static TrayBody(it, p := "") {
        flip := ""
        if (it.Check != "") {
            v := AxProject.CleanName(it.Check)
            flip := v " := !(IsSet(" v ") && " v ")"
        } else if (it.Pick != "") {
            v := AxProject.CleanName(StrSplit(it.Pick, ":")[1])
            flip := v " := " AxLit.S(SubStr(it.Pick, InStr(it.Pick, ":") + 1))
        }
        code := Trim(it.Code) != "" ? Trim(it.Code) : (flip != "" ? "" : AxAsset.TrayDefault(it.Label))
        body := flip (flip != "" && code != "" ? "`n" : "") code
        ; a line that opens with ( would start a continuation section
        body := RegExReplace(body, "m)^(\s*)\(", "$1try (")
        if (flip != "") {
            body .= "`nAxTrayTicks()"
            try if IsObject(p) && AxBind.HasVar(p, v)
                body .= "`nAxBindSync()"
        }
        return body
    }
    static TrayDefault(label) {
        q := AxAsset.Q
        switch StrLower(RegExReplace(label, "&")) {
        case "show", "open":   return "g.Show(), WinActivate(" q "ahk_id " q " g.Hwnd)"
        case "hide":           return "g.Hide()"
        case "toggle", "show or hide", "show/hide":
            return "DllCall(" q "IsWindowVisible" q ", " q "Ptr" q ", g.Hwnd) ? g.Hide() : (g.Show(), WinActivate(" q "ahk_id " q " g.Hwnd))"
        case "exit", "quit":   return "ExitApp()"
        case "reload", "restart": return "Reload()"
        case "suspend hotkeys", "suspend": return "Suspend(-1)`nAxTrayTicks()"
        case "pause":          return "Pause(-1)"
        case "open the folder", "open folder": return "Run(A_ScriptDir)"
        }
        return "g.Toast(" AxLit.S(label) ")"
    }
    ; "shell32.dll,13" -> "shell32.dll", 14   (TraySetIcon counts from 1)
    static IconArgs(icon) {
        if RegExMatch(icon, "^(.*),\s*(-?\d+)$", &m)
            return AxLit.S(Trim(m[1])) ", " (Integer(m[2]) >= 0 ? Integer(m[2]) + 1 : Integer(m[2]))
        return AxLit.S(icon)
    }

    ; ============================================================= compile
    ; Ahk2Exe reads directives out of the source, so this is comments -- which
    ; costs a loose script nothing and is the only way a compiled one can be
    ; told anything.
    static Compile(p) {
        cfg := Map()
        for line in AxAsset.Lines(p.Compile)
            if RegExMatch(line, "^([A-Za-z]\w*)\s*=\s*(.*)$", &m)
                cfg[StrLower(m[1])] := Trim(m[2])
        return cfg
    }
    ; One setting in the Compile text, changed in place: its line rewritten,
    ; added at the end, or taken out when the value is blank. Everything else
    ; in the text -- comments included -- is left exactly as it was, so the
    ; text stays the one truth the Compile form also writes.
    static SetCompile(p, key, value) {
        value := Trim(String(value))
        out := [], done := false
        for raw in StrSplit(StrReplace(String(p.Compile), "`r", ""), "`n") {
            if (RegExMatch(Trim(raw), "^([A-Za-z]\w*)\s*=", &m) && StrLower(m[1]) = StrLower(key)) {
                if (value != "" && !done)
                    out.Push(key " = " value)
                done := true
                continue
            }
            out.Push(raw)
        }
        if (!done && value != "")
            out.Push(key " = " value)
        text := ""
        for x in out
            text .= (A_Index = 1 ? "" : AxAsset.NL) x
        p.Compile := Trim(text, " `t`r`n")
    }
    ; ============================================================ hotkeys
    ; A hotkey is kept as a line on its window, like a rule, and becomes code
    ; only when the script is written -- so it can be listed, changed and
    ; taken out again, which code pasted into the startup script never could.
    ;
    ;     keys | where | what | detail
    ;     ^!h  | active | toast  | Pressed
    ;     #n   | always | toggle |
    ;     F1   | other:ahk_exe notepad.exe | own | OnHelp
    static Hotkeys(w) {
        out := []
        for line in AxAsset.Lines(w.Hotkeys) {
            p := StrSplit(line, "|", " `t", 4)
            if (p.Length < 3 || p[1] = "")
                continue
            hk := Map("hk", p[1], "scope", p[2], "other", "", "act", p[3],
                      "msg", "", "win", "", "fn", "", "line", line)
            if (SubStr(p[2], 1, 6) = "other:")
                hk["scope"] := "other", hk["other"] := Trim(SubStr(p[2], 7))
            else if (SubStr(p[2], 1, 4) = "not:")
                hk["scope"] := "not", hk["other"] := Trim(SubStr(p[2], 5))
            else if (SubStr(p[2], 1, 5) = "cond:")
                hk["scope"] := "cond", hk["cond"] := Trim(SubStr(p[2], 6))
            d := (p.Length >= 4) ? p[4] : ""
            hk["what"] := d
            if !hk.Has("cond")
                hk["cond"] := ""
            if (p[3] = "toast")
                hk["msg"] := d
            else if (p[3] = "open")
                hk["win"] := d
            else if (p[3] = "own")
                hk["fn"] := d
            out.Push(hk)
        }
        return out
    }
    static HotkeyLine(V) {
        keys := Trim(V["hk"])
        if (keys = "")
            return ""
        where := (V["scope"] = "other") ? "other:" Trim(V["other"])
               : (V["scope"] = "not") ? "not:" Trim(V["other"])
               : (V["scope"] = "cond") ? "cond:" Trim(V["cond"]) : V["scope"]
        detail := (V["act"] = "toast") ? Trim(V["msg"])
                : (V["act"] = "open") ? Trim(V["win"])
                : (V["act"] = "own") ? AxProject.CleanName(V["fn"])
                : InStr("|steps|send|type|run|remap|", "|" V["act"] "|") ? Trim(V["what"]) : ""
        return keys " | " where " | " V["act"] " | " detail
    }
    ; The code one hotkey becomes, at the top of its window's startup code.
    ; What you type -- the keys, a message, a window title -- goes through
    ; AxLit.S, so a quote or a " ;" in it cannot break the line.
    static HotkeyCode(V, fn := "HotkeySteps") {
        q := Chr(34), nl := AxAsset.NL
        keys := Trim(V["hk"])
        if (keys = "")
            return ""
        what := V.Has("what") ? V["what"] : ""
        ; another key: held down while this one is, as AutoHotkey's a::b does
        if (V["act"] = "remap") {
            k := RegExReplace(keys, "^[~*$]+")
            line := "Hotkey(" AxLit.S("*" k) ", (*) => Send(" AxLit.S("{Blind}{" Trim(what) " DownR}") "))" nl
                  . "Hotkey(" AxLit.S("*" k " up") ", (*) => Send(" AxLit.S("{Blind}{" Trim(what) " Up}") "))"
            return AxAsset.HotkeyWhere(V, line)
        }
        switch V["act"] {
        case "steps":
            body := fn "()"
        case "send":
            body := "Send(" AxLit.S(what) ")"
        case "type":
            body := "SendText(" AxLit.S(what) ")"
        case "run":
            body := "Run(" AxLit.S(what) ")"
        case "front":
            body := "(g.Show(), WinActivate(" q "ahk_id " q " g.Hwnd))"
        case "toggle":
            body := "g.Visible ? g.Hide() : (g.Show(), WinActivate(" q "ahk_id " q " g.Hwnd))"
        case "open":
            body := "Show" AxProject.CleanName(V["win"]) "()"
        case "own":
            body := AxProject.CleanName(V["fn"]) "()"
        default:
            body := "g.Toast(" AxLit.S(V["msg"]) ")"
        }
        line := "Hotkey(" AxLit.S(keys) ", (*) => " body ")"
        return AxAsset.HotkeyWhere(V, line)
    }
    static HotkeyWhere(V, line) {
        q := Chr(34), nl := AxAsset.NL
        if (V["scope"] = "active")
            return "HotIfWinActive(" q "ahk_id " q " g.Hwnd)" nl line nl "HotIfWinActive()"
        if (V["scope"] = "other")
            return "HotIfWinActive(" AxLit.S(V["other"]) ")" nl line nl "HotIfWinActive()"
        if (V["scope"] = "not")
            return "HotIfWinNotActive(" AxLit.S(V["other"]) ")" nl line nl "HotIfWinNotActive()"
        if (V["scope"] = "cond")
            return "HotIf((*) => Cond_" AxProject.CleanName(V["cond"]) "())" nl line nl "HotIf()"
        return line
    }
    static HotkeyFn(w, i) => "Hotkey_" AxProject.CleanName(w.Name) "_" i
    static HotkeysCode(w) {
        out := ""
        for i, hk in AxAsset.Hotkeys(w)
            out .= AxAsset.HotkeyCode(hk, AxAsset.HotkeyFn(w, i)) AxAsset.NL
        return out
    }
    ; the functions behind hotkeys that do steps, at the top level of the script
    static HotkeyStepFns(p) {
        s := ""
        for w in p.Wins
            for i, hk in AxAsset.Hotkeys(w)
                if (hk["act"] = "steps")
                    s .= AxAsset.HotkeyFn(w, i) "() {`n" AxAuto.Decl(p)
                       . AxAuto.StepsCode(p, AxAuto.Steps(hk["what"]), "    ") "}`n"
        return s
    }
    static CompileCode(p) {
        cfg := AxAsset.Compile(p)
        if !cfg.Count
            return ""
        nl := AxAsset.NL
        s := "; Read by Ahk2Exe when this is compiled. A comment otherwise." nl
        G := (k) => cfg.Has(k) ? cfg[k] : ""
        if (G("name") != "")
            s .= ";@Ahk2Exe-SetName " G("name") nl
        if (G("description") != "")
            s .= ";@Ahk2Exe-SetDescription " G("description") nl
        if (G("version") != "")
            s .= ";@Ahk2Exe-SetVersion " G("version") nl
        if (G("company") != "")
            s .= ";@Ahk2Exe-SetCompanyName " G("company") nl
        if (G("copyright") != "")
            s .= ";@Ahk2Exe-SetCopyright " G("copyright") nl
        if (G("icon") != "")
            s .= ";@Ahk2Exe-SetMainIcon " G("icon") nl
        if (G("exe") != "")
            s .= ";@Ahk2Exe-ExeName " G("exe") nl
        if (G("base") != "")
            s .= ";@Ahk2Exe-Base " G("base") nl
        if (G("compress") != "" && G("compress") != "0")
            s .= ";@Ahk2Exe-UseResourceLang 0x0409" nl
        if (G("admin") != "" && AxAsset.Truthy(G("admin")))
            s .= ";@Ahk2Exe-UpdateManifest 1" nl
        return RTrim(s, "`n")
    }
}
