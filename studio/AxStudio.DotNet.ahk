#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded.
#Include %A_LineFile%\..\AxJson.ahk
#Include %A_LineFile%\..\AxStudio.Pkg.ahk
#Include %A_LineFile%\..\AxStudio.Lit.ahk

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
;  AxStudio.DotNet.ahk -- all of .NET, as steps: adaptors over AHK#.
;
;  AHK# (owhs/ahksharp) hosts the .NET Framework 4 runtime inside the script
;  -- CS.System.IO.Path.Combine(a, b) is a call into .NET -- and fetches
;  NuGet packages built for .NET Framework 4.x or .NET Standard 2.0 as it
;  runs (CS.NuGet.Require). That is hundreds of thousands of libraries, and
;  none of them is any use to someone who does not write code. An ADAPTOR
;  is one method of one of them made into one of your functions, with a
;  plain name and a sentence -- and a function is something every rule,
;  timer, hotkey and step-by-step flowchart can already do:
;
;      Adaptors   name | kind | source | target | params | returns | doc
;                 Speak | new | | System.Speech.Synthesis.SpeechSynthesizer.Speak | textToSpeak:string | void | Say it out loud
;                 Pretty | nuget | Newtonsoft.Json@13.0.3 | Newtonsoft.Json.Linq.JToken.Parse | json:string | object | ...
;
;      kind   static  CS.Type.Method(args)           a static method of .NET itself
;             new     CS.Type().Method(args)         one on a fresh object of it
;             nuget   Net_Pkg.Name(args)             either, from a package: a
;                     small C# module (_CSModule) is written round the call,
;                     with the package as its reference, because a package's
;                     types are only there once AHK# has loaded it for that
;             ahk     Owner.Name(args)               an AutoHotkey library's own
;
;  What a type or a package offers is read by tools\AxNetScan.ps1 in Windows
;  PowerShell -- .NET Framework 4, the runtime AHK# hosts -- loading the
;  assembly REFLECTION-ONLY: its metadata is read, and not a line of it runs.
;  A package is downloaded (nuget.org) only when you ask to see inside it.
; =============================================================================
class AxNet {
    static Lib := "owhs/ahksharp"
    static SearchUrl := "https://azuresearch-usnc.nuget.org/query?prerelease=false&semVerLevel=2.0.0&take=30&q="
    static FlatUrl := "https://api.nuget.org/v3-flatcontainer/"
    static Override := ""          ; a folder standing in for nuget.org (the probe): search.json, id\ver\...
    static _scans := Map()

    static Dir() => AxStudioPaths.Data() "\nuget"
    static Scanner => RegExReplace(A_LineFile, "\\[^\\]+$") "\tools\AxNetScan.ps1"

    ; ----------------------------------------------------- built into Windows
    ; What a program with no code most wants from .NET, a shelf each. Any
    ; other type can be typed by its full name.
    static Builtin := [
        ["Speech", "E767", "Say things out loud, in Windows' own voices.", "System.Speech.Synthesis.SpeechSynthesizer"],
        ["Files and folders", "E8B7", "Copy, move, read and write whole files; paths and their parts.", "System.IO.File,System.IO.Directory,System.IO.Path"],
        ["Zip files", "F012", "Pack a folder into a .zip, or unpack one.", "System.IO.Compression.ZipFile"],
        ["The web", "E774", "Download a page or a file, and take addresses apart.", "System.Net.WebClient,System.Uri"],
        ["Text and patterns", "E8D2", "Find and replace by pattern, split, join.", "System.Text.RegularExpressions.Regex,System.String"],
        ["The computer", "E7F8", "Its name, the user, the folders Windows keeps, how long it has been on.", "System.Environment"],
        ["Dates and times", "E787", "Now, time zones, days between.", "System.DateTime,System.TimeZoneInfo"],
        ["Numbers", "E8EF", "Rounding, powers, roots, random numbers.", "System.Math,System.Random"],
        ["IDs", "E8EC", "Unique ids that never repeat.", "System.Guid"],
        ["The clipboard", "E8C8", "Text, pictures and files on the clipboard.", "System.Windows.Forms.Clipboard"],
        ["Sounds", "E8D6", "Windows' own sounds, and playing a .wav.", "System.Media.SystemSounds,System.Media.SoundPlayer"]]

    ; ---------------------------------------------------------- scanning
    ; {types: [{t, n, ns, st, ctor, m: [{n, s, p: [{n, t, cs}], r}], pr}]}
    static Scan(types := "", dlls := "") {
        key := types "|" dlls
        if AxNet._scans.Has(key)
            return AxNet._scans[key]
        out := A_Temp "\axnetscan_" A_TickCount ".json"
        args := (dlls != "") ? '-Dll "' dlls '"' : '-Type "' types '"'
        try RunWait('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' AxNet.Scanner '" ' args ' -Out "' out '"', , "Hide")
        r := ""
        try r := AxJson.Parse(FileRead(out, "UTF-8"))
        try FileDelete(out)
        list := (r is Map && r.Has("types")) ? r["types"] : []
        if !(list is Array)
            list := [list]
        return AxNet._scans[key] := list
    }
    static G(m, k, d := "") => (m is Map && m.Has(k)) ? m[k] : d
    ; a method's parameters as "a:string, b:int"
    static Params(m) {
        s := ""
        ps := AxNet.G(m, "p", [])
        if !(ps is Array)
            ps := [ps]
        for p in ps
            s .= (s = "" ? "" : ", ") AxNet.G(p, "n") ":" AxNet.G(p, "cs")
        return s
    }
    ; ...said: "text to speak (text), rate (a whole number)"
    static Words(params) {
        static kinds := Map("string", "text", "int", "a whole number", "long", "a whole number", "double", "a number",
            "float", "a number", "decimal", "a number", "bool", "yes or no", "object", "anything", "char", "a letter")
        s := ""
        for p in AxNet.Split(params)
            s .= (s = "" ? "" : ", ") AxNet.Human(p.N) (kinds.Has(p.T) ? " (" kinds[p.T] ")" : " (" RegExReplace(p.T, ".*\.") ")")
        return s = "" ? "nothing" : s
    }
    static Split(params) {
        out := []
        for x in StrSplit(params, ",", " ")
            if (x != "")
                out.Push({N: StrSplit(x, ":")[1], T: StrSplit(x, ":", , 2).Length > 1 ? StrSplit(x, ":", , 2)[2] : "object"})
        return out
    }
    ; textToSpeak -> text to speak
    static Title(name) => (h := AxNet.Human(name)) = "" ? "" : StrUpper(SubStr(h, 1, 1)) SubStr(h, 2)
    static Human(name) => StrLower(Trim(RegExReplace(RegExReplace(name, "([a-z])([A-Z])", "$1 $2"), "_", " ")))

    ; -------------------------------------------------------------- NuGet
    static Get(url, file) {
        try FileDelete(file)
        Download(url, file)
        return FileRead(file, "UTF-8")
    }
    ; [{Id, Version, Desc, Downloads, Verified, Authors}]
    static Search(q) {
        if (AxNet.Override != "")
            txt := FileRead(AxNet.Override "\search.json", "UTF-8")
        else
            txt := AxNet.Get(AxNet.SearchUrl AxNet.Enc(q), A_Temp "\axnuget_search.json")
        r := AxJson.Parse(txt)
        out := []
        for d in AxNet.G(r, "data", []) {
            au := AxNet.G(d, "authors", [])
            out.Push({Id: AxNet.G(d, "id"), Version: AxNet.G(d, "version"), Desc: AxNet.G(d, "description"),
                      Downloads: AxNet.G(d, "totalDownloads", 0), Verified: AxNet.G(d, "verified", false) ? true : false,
                      Authors: (au is Array && au.Length) ? au[1] : String(au)})
        }
        return out
    }
    static Enc(s) {
        out := ""
        loop parse s
            out .= RegExMatch(A_LoopField, "[A-Za-z0-9._~-]") ? A_LoopField : Format("%{:02X}", Ord(A_LoopField) & 0xFF)
        return out
    }
    ; Can AHK# load it? Its lib folders say: .NET Framework 4.x or .NET
    ; Standard 1.x/2.0 yes; only .NET 5 and later, no -- AHK# hosts the
    ; Framework runtime. "" = not known until it is opened.
    static Frameworks(id, ver) {
        lid := StrLower(id), lv := StrLower(ver)
        try {
            txt := (AxNet.Override != "") ? FileRead(AxNet.Override "\" lid "\" lv "\" lid ".nuspec", "UTF-8")
                 : AxNet.Get(AxNet.FlatUrl lid "/" lv "/" lid ".nuspec", A_Temp "\axnuget.nuspec")
        } catch
            return ""
        list := [], p := 1
        while (p := RegExMatch(txt, 'i)targetFramework="([^"]+)"', &m, p))
            list.Push(m[1]), p += m.Len
        return list
    }
    static Fits(tfm) {
        t := StrLower(RegExReplace(tfm, "^\."))
        return RegExMatch(t, "^(net(framework)?4|net4|net[1-4]\d|netstandard[12]|net20|net35|portable)") > 0
    }
    ; "yes" | "no" | "" (not known)
    static Compatible(tfms) {
        if !(tfms is Array) || !tfms.Length
            return ""
        for t in tfms
            if AxNet.Fits(t)
                return "yes"
        return "no"
    }
    ; the package on this machine, and the dlls AHK# would load from it:
    ; {Dir, Tfm, Dlls} -- downloaded (about the package's own size) the
    ; first time it is looked inside
    static Fetch(id, ver) {
        lid := StrLower(id), lv := StrLower(ver)
        dir := (AxNet.Override != "") ? AxNet.Override "\" lid "\" lv : AxNet.Dir() "\" lid "\" lv
        if !DirExist(dir "\lib") {
            DirCreate(dir)
            pkg := dir "\" lid "." lv ".nupkg"
            if !FileExist(pkg)
                Download(AxNet.FlatUrl lid "/" lv "/" lid "." lv ".nupkg", pkg)
            RunWait('tar.exe -xf "' pkg '" -C "' dir '"', , "Hide")
        }
        best := "", rank := 999
        order := ["net48", "net472", "net471", "net47", "net462", "net461", "net46", "net452", "net451", "net45", "net40",
                  "netstandard2.0", "netstandard1.6", "netstandard1.3", "netstandard1.1", "netstandard1.0"]
        loop files dir "\lib\*", "D" {
            for i, o in order
                if (StrLower(A_LoopFileName) = o && i < rank)
                    rank := i, best := A_LoopFileName
        }
        dlls := ""
        if (best != "")
            loop files dir "\lib\" best "\*.dll"
                dlls .= (dlls = "" ? "" : ";") A_LoopFileFullPath
        return {Dir: dir, Tfm: best, Dlls: dlls}
    }

    ; ------------------------------------------------------------ adaptors
    ; the project's: [{Name, Kind, Source, Target, Params, Returns, Doc, Line}]
    static List(p) {
        out := []
        for line in AxAsset.Lines(p.HasProp("Adaptors") ? p.Adaptors : "") {
            f := AxAuto.Split(line, 7)
            if (AxProject.CleanName(f[1]) = "")
                continue
            out.Push({Name: AxProject.CleanName(f[1]), Kind: StrLower(f[2]), Source: f[3], Target: f[4],
                      Params: f[5], Returns: f[6], Doc: f[7], Line: line})
        }
        return out
    }
    static Find(p, name) {
        for a in AxNet.List(p)
            if (a.Name = name)
                return a
        return ""
    }
    static Line(a) => a.Name " | " a.Kind " | " a.Source " | " a.Target " | " a.Params " | " a.Returns " | " a.Doc
    static Add(p, a) {
        cur := RTrim(String(p.Adaptors), "`r`n")
        p.Adaptors := (Trim(cur) = "" ? "" : cur "`n") AxNet.Line(a)
        if (a.Kind != "ahk")
            AxPkg.Use(p, AxNet.Lib)
        else if (a.Source != "")
            AxPkg.Use(p, a.Source)
    }
    static UsesNet(p) {
        for a in AxNet.List(p)
            if (a.Kind != "ahk")
                return true
        return false
    }
    static PkgClass(src) => "Net_" AxProject.CleanName(RegExReplace(src, "@.*$"))

    ; The region: a C# module a package, then one function an adaptor.
    static Code(p) {
        list := AxNet.List(p)
        if !list.Length
            return ""
        nl := "`n", s := "; Adaptors (App > Libraries): methods of .NET and of libraries, each one of your functions.`n"
        mods := Map()
        for a in list
            if (a.Kind = "nuget") {
                if !mods.Has(a.Source)
                    mods[a.Source] := ""
                mods[a.Source] .= AxNet.CsMethod(a)
            }
        for src, body in mods {
            pk := StrSplit(src, "@")
            s .= "class " AxNet.PkgClass(src) " extends _CSModule {" nl
               . "    static References := CS.NuGet.Require(" AxLit.S(pk[1]) (pk.Length > 1 ? ", " AxLit.S(pk[2]) : "") ")" nl
               . "    static CSharp := `"" nl "    (" nl body "    )`"" nl "}" nl
        }
        for a in list {
            args := ""
            for x in AxNet.Split(a.Params)
                args .= (args = "" ? "" : ", ") AxNet.Arg(x.N)
            call := AxNet.Call(a, args)
            s .= "; " a.Name "(" args ") -- " (a.Doc != "" ? a.Doc : a.Target) nl
               . a.Name "(" AxNet.Opt(args) ") => " call nl
        }
        return RTrim(s, "`n")
    }
    ; a parameter name that is a plain AutoHotkey name
    static Arg(n) {
        n := AxProject.CleanName(n)
        return (n = "") ? "x" : n
    }
    ; every parameter optional in the function, so a rule's "call Name" with
    ; nothing still loads -- .NET says if something was needed
    static Opt(args) {
        if (args = "")
            return ""
        s := ""
        for x in StrSplit(args, ",", " ")
            s .= (s = "" ? "" : ", ") x "?"
        return s
    }
    static Call(a, args) {
        t := a.Target
        type := RegExReplace(t, "\.[^.]+$"), meth := RegExReplace(t, "^.*\.")
        pass := ""
        for x in StrSplit(args, ",", " ")
            if (x != "")
                pass .= (pass = "" ? "" : ", ") x "?"
        switch a.Kind {
        case "static": return "CS." type "." meth "(" pass ")"
        case "new":    return "CS." type "()." meth "(" pass ")"
        case "prop":   return "CS." t
        case "nuget":  return AxNet.PkgClass(a.Source) "." a.Name "(" pass ")"
        case "ahk":    return t "(" pass ")"
        }
        return '""'
    }
    ; public static object Name(string a, int b) { return Ns.Type.Method(a, b); }
    static CsMethod(a) {
        t := a.Target, type := RegExReplace(t, "\.[^.]+$"), meth := RegExReplace(t, "^.*\.")
        ps := "", pass := ""
        for x in AxNet.Split(a.Params)
            ps .= (ps = "" ? "" : ", ") x.T " " AxNet.Arg(x.N), pass .= (pass = "" ? "" : ", ") AxNet.Arg(x.N)
        inst := InStr(a.Returns, "@new")                ; an instance method: on a fresh object
        ret := RegExReplace(a.Returns, "@new$")
        target := (inst ? "new " type "()" : type) "." meth "(" pass ")"
        ; no " ;" anywhere: in AutoHotkey that starts a comment even here
        return "    public static " (ret = "void" ? "void" : "object") " " a.Name "(" ps ") { "
             . (ret = "void" ? target "; }" : "return " target "; }") "`n"
    }
}
