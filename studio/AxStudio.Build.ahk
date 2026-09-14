#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk

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
;  AxStudio.Build.ahk -- finding Ahk2Exe, and using it.
;
;  Writing the ;@Ahk2Exe- directives and then leaving you to go and find a
;  compiler is half an answer. Ahk2Exe ships with AutoHotkey and is nearly
;  always already on the machine; it is just never anywhere you would think to
;  look, because it sits beside the *installation* rather than beside the
;  interpreter that is running.
;
;  So: look in the six places it actually is, remember where it was found, and
;  run it. And when it genuinely is not there, say where to get it rather than
;  reaching out and fetching an executable off the internet on your behalf --
;  see the note on Missing() for why that line is where it is.
;
;  The base file matters as much as the compiler. Ahk2Exe stamps your script
;  onto a copy of an AutoHotkey interpreter, and *which* interpreter decides
;  whether the exe is 32- or 64-bit and whether it can drive elevated windows
;  (the _UIA ones can). Those are real files on disk, so they are offered as
;  the list they are rather than as a 32/64 guess.
; =============================================================================
class AxBuild {
    static _exe := ""                       ; found once, then remembered

    ; ------------------------------------------------------------ finding
    ; "" when it is not on this machine. `hint` is whatever the settings
    ; remember, which is tried first: someone who keeps a portable copy should
    ; not have it found again somewhere else every time.
    static Exe(hint := "") {
        if (hint != "" && FileExist(hint))
            return hint
        if (AxBuild._exe != "" && FileExist(AxBuild._exe))
            return AxBuild._exe
        for p in AxBuild.Places() {
            if FileExist(p) {
                AxBuild._exe := p
                return p
            }
        }
        return ""
    }
    static Places() {
        out := []
        ; beside the interpreter that is running -- and one level up, because
        ; a v2 install puts AutoHotkey64.exe in v2\ and the compiler beside it
        SplitPath(A_AhkPath, , &dir)
        out.Push(dir "\Compiler\Ahk2Exe.exe")
        SplitPath(dir, , &up)
        if (up != "")
            out.Push(up "\Compiler\Ahk2Exe.exe")
        ; where the installer says it put itself
        for key in ["HKLM\SOFTWARE\AutoHotkey", "HKCU\SOFTWARE\AutoHotkey"] {
            root := ""
            try root := RegRead(key, "InstallDir")
            if (root != "")
                out.Push(root "\Compiler\Ahk2Exe.exe")
        }
        ; and the ordinary places
        for root in [A_ProgramFiles "\AutoHotkey",
                     EnvGet("ProgramW6432") "\AutoHotkey",
                     EnvGet("ProgramFiles(x86)") "\AutoHotkey",
                     EnvGet("LOCALAPPDATA") "\Programs\AutoHotkey"] {
            if (SubStr(root, 1, 1) != "\")
                out.Push(root "\Compiler\Ahk2Exe.exe")
        }
        return out
    }
    ; The interpreters Ahk2Exe can stamp a script onto. A base is an ordinary
    ; AutoHotkey exe (or a .bin), so this is a directory listing rather than a
    ; list of names to keep in step with future releases.
    static Bases(exe := "") {
        out := [], seen := Map()
        dirs := []
        if (exe != "") {
            SplitPath(exe, , &cdir)
            dirs.Push(cdir)                                  ; Compiler\*.bin
            SplitPath(cdir, , &root)
            dirs.Push(root, root "\v2")                      ; the install itself
        }
        SplitPath(A_AhkPath, , &here)
        dirs.Push(here)
        for d in dirs {
            if (d = "" || !DirExist(d))
                continue
            loop files d "\*.exe" {
                if !AxBuild.IsBase(A_LoopFileFullPath)
                    continue
                key := StrLower(A_LoopFileName)
                if seen.Has(key)
                    continue
                seen[key] := true
                out.Push(AxBuild.Base(A_LoopFileFullPath))
            }
            loop files d "\*.bin" {
                key := StrLower(A_LoopFileName)
                if seen.Has(key)
                    continue
                seen[key] := true
                out.Push(AxBuild.Base(A_LoopFileFullPath))
            }
        }
        return out
    }
    ; A launcher stub is nought bytes and Ahk2Exe.exe is not something to stamp
    ; a script onto, so neither is offered.
    static IsBase(path) {
        SplitPath(path, &name)
        if (StrLower(name) = "ahk2exe.exe" || StrLower(name) = "windowspy.exe")
            return false
        size := 0
        try size := FileGetSize(path)
        return size > 100000
    }
    static Base(path) {
        SplitPath(path, &name)
        bits := InStr(name, "64") ? 64 : (InStr(name, "32") ? 32 : 0)
        v1 := InStr(name, "U64") || InStr(name, "U32") || InStr(name, "A32")
        return {Path: path, Name: name, Bits: bits,
                Uia: InStr(name, "_UIA") ? true : false, V1: v1 ? true : false,
                Label: AxBuild.BaseLabel(name, bits, InStr(name, "_UIA") ? true : false)}
    }
    static BaseLabel(name, bits, uia) {
        s := name
        if bits
            s .= "   " bits "-bit"
        if uia
            s .= ", drives elevated windows"
        return s
    }
    ; The one to start on: same bit width as the interpreter running the
    ; studio, not a _UIA build (which most scripts do not want), v2.
    static PickBase(bases) {
        want := (A_PtrSize = 8) ? 64 : 32
        for b in bases
            if (b.Bits = want && !b.Uia && !b.V1)
                return b.Path
        for b in bases
            if (!b.Uia && !b.V1)
                return b.Path
        return bases.Length ? bases[1].Path : ""
    }

    ; ---------------------------------------------------------- compiling
    ; Runs Ahk2Exe over a script that is already on disk. Everything it says
    ; is captured, because /silent means it says it to stdout instead of to a
    ; dialog -- and a dialog is the last thing wanted from something started
    ; by a button in another program.
    ;
    ; Through a .cmd FILE rather than  cmd /c "<command>" . cmd only strips
    ; the outer quotes of a /c string when it holds exactly one quoted token
    ; and no redirection; with three quoted paths and a > it keeps them, tries
    ; to run the whole line as a program name, and exits 1 having written
    ; nothing to the log it never opened. That is what "stopped with code 1 and
    ; said nothing" was. A file has no such rule.
    static Compile(exe, script, out, base := "", icon := "", compress := 0) {
        if (exe = "" || !FileExist(exe))
            return AxBuild.Fail("Ahk2Exe is not where it was: " exe, out)
        if !FileExist(script)
            return AxBuild.Fail("There is no script at " script, out)
        if (base != "" && !FileExist(base))
            return AxBuild.Fail("The interpreter to build on is not there: " base
                              . "  --  pick one under File > Compile.", out)
        if (icon != "" && !FileExist(icon))
            icon := ""                          ; a missing icon is not worth stopping for
        dir := A_Temp "\axstudio_build"
        try DirCreate(dir)
        log := dir "\ahk2exe.log", bat := dir "\ahk2exe.cmd"
        for f in [log, bat] {
            try if FileExist(f)
                FileDelete(f)
        }
        cmd := '"' exe '" /in "' script '"'
        if (out != "")
            cmd .= ' /out "' out '"'
        if (base != "")
            cmd .= ' /base "' base '"'
        if (icon != "")
            cmd .= ' /icon "' icon '"'
        if (compress != "" && compress != 0)
            cmd .= " /compress " compress
        cmd .= " /silent verbose"
        ; UTF-8 with no BOM and the console switched to match, so a path with
        ; anything but ASCII in it survives the trip through cmd
        nl := "`r`n"
        ; no echo of the command: it would not reach the log anyway (that line
        ; is not redirected) and a path with an & or a > in it would break the
        ; line after it. Compile returns the command with the log instead.
        try FileAppend("@echo off" nl "chcp 65001 >nul" nl
                     . cmd ' > "' log '" 2>&1' nl, bat, "UTF-8-RAW")
        catch as e
            return AxBuild.Fail("Could not write the build script: " e.Message, out)
        code := 1
        try code := RunWait('"' bat '"', dir, "Hide")
        catch as e
            return AxBuild.Fail("Could not start Ahk2Exe: " e.Message, out)
        text := ""
        try text := FileRead(log, "UTF-8")
        made := (out != "" && FileExist(out))
        size := 0
        if made
            try size := FileGetSize(out)
        if (made && code = 0)
            return {Ok: true, Exe: out, Log: cmd "`n" text,
                    Msg: "Compiled " AxBuild.Short(out) "  --  " Round(size / 1048576, 2) " MB"}
        return {Ok: false, Exe: out, Log: cmd "`n" text, Msg: AxBuild.Why(text, code)}
    }
    static Fail(msg, out) => {Ok: false, Msg: msg, Log: "", Exe: out}
    ; Ahk2Exe's own words when it has them, and something honest when it does
    ; not: an exit code on its own tells nobody anything.
    static Why(text, code) {
        t := Trim(String(text))
        if (t != "") {
            for line in StrSplit(StrReplace(t, "`r", ""), "`n")
                if (InStr(line, "rror") || InStr(line, "ailed"))
                    return Trim(line)
            return SubStr(t, 1, 200)
        }
        return "Ahk2Exe stopped with code " code " and wrote nothing. The command it was "
             . "given is the first line in Output."
    }
    static Short(p) {
        SplitPath(p, &name, &dir)
        SplitPath(dir, &parent)
        return (parent != "" ? parent "\" : "") name
    }
    ; A base that is not a file: an earlier version of the compile form stored
    ; "64" and "32" rather than a path, so a project saved then would hand
    ; /base 64 to the compiler. Read it as a bit width and find the real one.
    static ResolveBase(base, bases) {
        b := Trim(String(base))
        if (b = "" || FileExist(b)) {
            if (b != "")
                return b
            return AxBuild.PickBase(bases)
        }
        want := InStr(b, "32") ? 32 : (InStr(b, "64") ? 64 : 0)
        if want
            for x in bases
                if (x.Bits = want && !x.Uia && !x.V1)
                    return x.Path
        for x in bases
            if (StrLower(x.Name) = StrLower(b))
                return x.Path
        return AxBuild.PickBase(bases)
    }

    ; --------------------------------------------------------- what it holds
    ; Everything that ends up inside the exe, which is otherwise invisible
    ; until something is missing at run time. The library's own resources are
    ; read out of the ;@Ahk2Exe-AddResource lines in the files the script
    ; includes, rather than being a list here that would go stale.
    static Resources(project) {
        out := []
        ; the stylesheet the design wears, and the overlay furniture
        sheet := (project.Stylesheet != "") ? project.Stylesheet : "win11"
        out.Push({What: "themes\" sheet ".css", Why: "the window's stylesheet"})
        out.Push({What: "themes\base.css", Why: "menus, dialogs, toasts"})
        out.Push({What: "ui\overlays.html", Why: "the markup those need"})
        for p in AxComp.Used(project)
            for r in AxBuild.PackResources(p)
                out.Push({What: r, Why: p.Name})
        for f in AxAsset.Files(project)
            if (f.How = "resource")
                out.Push({What: f.Path, Why: "yours, as " f.Name})
        return out
    }
    static PackResources(pack) {
        out := []
        if (pack.Include = "" || !FileExist(pack.Include))
            return out
        raw := ""
        try raw := FileRead(pack.Include, "UTF-8")
        pos := 1
        while (pos := RegExMatch(raw, "@Ahk2Exe-AddResource %U_AxLib%\\([^,\r\n]+)", &m, pos)) {
            pos += m.Len
            if !InStr(m[1], "<")                    ; the worked example in the docs
                out.Push(Trim(m[1]))
        }
        return out
    }

    ; ------------------------------------------------------------- missing
    ; Deliberately not a download.
    ;
    ; Ahk2Exe is part of the AutoHotkey installer, so on nearly every machine
    ; the answer is "it is already here, in a folder you would not have looked
    ; in" -- which is what Exe() is for. When it really is absent, a designer
    ; reaching out to fetch and run an executable is a different kind of
    ; program to one that writes .ahk files, and not one this should quietly
    ; become. So it says where it comes from and opens the page; the decision
    ; and the download stay with you.
    static Page := "https://www.autohotkey.com/download/"
    static Repo := "https://github.com/AutoHotkey/Ahk2Exe/releases"
}
