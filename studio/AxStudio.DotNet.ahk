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
        ["Sounds", "E8D6", "Windows' own sounds, and playing a .wav.", "System.Media.SystemSounds,System.Media.SoundPlayer"],
        ; The shelves below are the ones worth running in the background: each
        ; is work that takes long enough to freeze a window, and .NET does all
        ; of it on a thread pool for the price of one word.
        ["Fingerprints", "E72E", "SHA-256 and MD5 of a file or of text -- how two files are told apart.",
         "System.Security.Cryptography.SHA256,System.Security.Cryptography.MD5,System.BitConverter"],
        ["Compressing", "F012", "Squeeze and unsqueeze a stream: gzip and deflate, without a temporary file.",
         "System.IO.Compression.GZipStream,System.IO.Compression.DeflateStream"],
        ["Inside an archive", "E8B7", "Open a .zip and read what is in it, entry by entry, without unpacking it.",
         "System.IO.Compression.ZipFile,System.IO.Compression.ZipArchive,System.IO.Compression.ZipFileExtensions"],
        ["Downloading", "E896", "Fetch a page, a file or an API's answer -- in the background, with headers.",
         "System.Net.Http.HttpClient,System.Net.WebClient"],
        ["Serving", "E968", "A little web server of your own: answer requests on a port, from this program.",
         "System.Net.HttpListener,System.Net.HttpListenerContext"],
        ["Pictures", "EB9F", "Open, resize, convert and save images -- png, jpg, bmp, gif, tiff.",
         "System.Drawing.Image,System.Drawing.Bitmap,System.Drawing.Graphics"],
        ["Programs", "E7B8", "Start one, wait for it, read what it printed, list what is running.",
         "System.Diagnostics.Process,System.Diagnostics.ProcessStartInfo"],
        ["Watching a folder", "E8B7", "Be told the moment a file appears, changes, is renamed or goes.",
         "System.IO.FileSystemWatcher"],
        ["The network", "E968", "Ping, look up a name, list this machine's addresses.",
         "System.Net.NetworkInformation.Ping,System.Net.Dns"],
        ["Many at once", "E91B", "The thread pool itself: run a batch of work in parallel and wait for the lot.",
         "System.Threading.Tasks.Task,System.Threading.Tasks.Parallel"]]

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
    ; ------------------------------------------------- looking one up
    ; The name of a method, and everything else about it.
    ;
    ; Writing an adaptor by hand meant knowing what the method takes and what
    ; it gives back, in the studio's own notation, before you could write a
    ; line of it -- so "I want System.IO.File.ReadAllText" was three more
    ; questions you had to already know the answers to. The scanner has known
    ; all three all along; it was only ever asked about a whole shelf.
    ;
    ; Gives back every overload: [{Params, Returns, Static, Kind, Type, Name}].
    static Lookup(target) {
        target := Trim(target)
        i := InStr(target, ".", , -1)
        if (i < 2)
            return []
        tn := SubStr(target, 1, i - 1), mn := SubStr(target, i + 1)
        out := []
        for t in AxNet.Scan(tn) {
            if (AxNet.G(t, "t") != tn && AxNet.G(t, "n") != tn)
                continue
            ms := AxNet.G(t, "m", [])
            if !(ms is Array)
                ms := [ms]
            for m in ms
                if (AxNet.G(m, "n") = mn)
                    out.Push({Params: AxNet.Params(m), Returns: AxNet.G(m, "r", "object"),
                              Static: AxNet.G(m, "s") ? true : false, Kind: AxNet.G(m, "s") ? "static" : "new",
                              Type: AxNet.G(t, "t"), Name: mn, Doc: AxNet.Title(mn) " (" AxNet.G(t, "n") ")"})
            ps := AxNet.G(t, "pr", [])
            if !(ps is Array)
                ps := [ps]
            for pr in ps
                if (AxNet.G(pr, "n") = mn)
                    out.Push({Params: "", Returns: AxNet.G(pr, "r", "object"), Static: true, Kind: "prop",
                              Type: AxNet.G(t, "t"), Name: mn, Doc: AxNet.Title(mn) " (" AxNet.G(t, "n") ")"})
        }
        return out
    }
    ; Was there a type of that name at all? Said apart from "no such method",
    ; because the two are different mistakes with different fixes.
    static TypeExists(tn) {
        for t in AxNet.Scan(Trim(tn))
            if (AxNet.G(t, "t") = Trim(tn))
                return true
        return false
    }

    ; ------------------------------------------------ a pasted signature
    ; What is on the clipboard after reading any documentation page:
    ;
    ;     public static string ReadAllText(string path)
    ;     System.IO.File.ReadAllText(string path)
    ;     string File.ReadAllText(String path, Encoding encoding)
    ;     Regex.Replace(input, pattern, replacement)
    ;
    ; Gives back {Target, Params, Returns} -- "" for anything it cannot see.
    ; Whatever it works out is a starting point, not an answer: Look it up
    ; checks it against the real .NET.
    static FromSig(text) {
        out := {Target: "", Params: "", Returns: ""}
        t := Trim(RegExReplace(String(text), "[`r`n]+", " "))
        t := RegExReplace(t, ";\s*$")
        ; the last bracketed group is the parameter list
        open := InStr(t, "(", , -1), close := InStr(t, ")", , -1)
        inner := ""
        if (open && close > open) {
            inner := SubStr(t, open + 1, close - open - 1)
            t := Trim(SubStr(t, 1, open - 1))
        }
        ; words in front: modifiers, then maybe a return type, then the name
        words := []
        for w in StrSplit(t, [" ", "`t"]) {
            w := Trim(w)
            if (w = "" || AxNet.Modifier(w))
                continue
            words.Push(w)
        }
        if !words.Length
            return out
        out.Target := RegExReplace(words[words.Length], "^CS\.")
        if (words.Length >= 2)
            out.Returns := AxNet.CsType(words[words.Length - 1])
        parts := ""
        for one in AxNet.SplitArgs(inner) {
            one := Trim(RegExReplace(one, "\s*=.*$"))         ; a default value
            if (one = "")
                continue
            ; name:type (ours), "type name" (C#), or a bare name
            if InStr(one, ":") {
                nm := Trim(StrSplit(one, ":")[1]), ty := AxNet.CsType(Trim(StrSplit(one, ":", , 2)[2]))
            } else {
                ws := []
                for w in StrSplit(one, [" ", "`t"])
                    if (Trim(w) != "" && !AxNet.Modifier(Trim(w)))
                        ws.Push(Trim(w))
                if !ws.Length
                    continue
                if (ws.Length >= 2)
                    nm := ws[ws.Length], ty := AxNet.CsType(ws[ws.Length - 1])
                else
                    nm := ws[1], ty := "string"
            }
            nm := RegExReplace(nm, "[^A-Za-z0-9_]")
            if (nm = "")
                continue
            parts .= (parts = "" ? "" : ", ") nm ":" ty
        }
        out.Params := parts
        return out
    }
    static Modifier(w) {
        static mods := "|public|private|protected|internal|static|virtual|override|abstract|sealed|extern|"
                     . "unsafe|readonly|async|new|ref|out|in|params|this|const|"
        return InStr(mods, "|" StrLower(w) "|") > 0
    }
    ; Commas that are not inside brackets.
    static SplitArgs(text) {
        out := [], depth := 0, cur := ""
        loop parse text {
            c := A_LoopField
            if (c = "(" || c = "[" || c = "<")
                depth++
            else if (c = ")" || c = "]" || c = ">")
                depth--
            if (c = "," && depth <= 0) {
                out.Push(cur), cur := ""
                continue
            }
            cur .= c
        }
        if (Trim(cur) != "")
            out.Push(cur)
        return out
    }
    ; String -> string, Int32 -> int: what the studio writes, from what a
    ; documentation page says.
    static CsType(t) {
        static m := Map("String", "string", "Int32", "int", "Int64", "long", "Double", "double",
            "Single", "float", "Boolean", "bool", "Object", "object", "Void", "void", "Decimal", "decimal",
            "Byte", "byte", "Int16", "short", "UInt32", "uint", "Char", "char")
        t := Trim(RegExReplace(String(t), "^System\."))
        t := RegExReplace(t, "\?$")                     ; int? -- a number that may be missing
        return m.Has(t) ? m[t] : t
    }

    ; --------------------------------------------------------- try it now
    ; The method, run, with the values typed in -- before a line of it is in
    ; anyone's program. tools\AxNetTry.ps1 does it in Windows PowerShell,
    ; which is the .NET Framework 4 runtime AHK# hosts: what runs there runs
    ; in the program.
    ;
    ; IT RUNS THE METHOD. The caller asks first.
    static Tryer => RegExReplace(A_LineFile, "\\[^\\]+$") "\tools\AxNetTry.ps1"
    static Try(target, kind, args, dlls := "", timeoutMs := 20000) {
        if !FileExist(AxNet.Tryer)
            return {Ok: false, Error: "The runner is missing: " AxNet.Tryer " is not there.", Value: "", Type: ""}
        af := A_Temp "\axnettry_a_" A_TickCount ".json"
        of := A_Temp "\axnettry_o_" A_TickCount ".json"
        try FileDelete(of)
        FileAppend(AxJson.Stringify(args is Array ? args : [], ""), af, "UTF-8")
        cmd := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' AxNet.Tryer '"'
             . ' -Target "' target '" -Kind ' (kind = "" ? "static" : kind)
             . ' -Args "' af '" -Out "' of '"'
             . (dlls != "" ? ' -Dll "' dlls '"' : "")
        try RunWait(cmd, , "Hide")
        r := ""
        try r := AxJson.Parse(FileRead(of, "UTF-8"))
        try FileDelete(af)
        try FileDelete(of)
        if !(r is Map)
            return {Ok: false, Error: "It did not answer -- the method may have stopped, or asked something of its own.",
                    Value: "", Type: ""}
        return {Ok: AxNet.G(r, "ok", 0) ? true : false, Error: AxNet.G(r, "error", ""),
                Value: AxNet.G(r, "value", ""), Type: AxNet.G(r, "type", "")}
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

    ; ---------------------------------------------------- the assembly it needs
    ; .NET does not have all of itself loaded.
    ;
    ; The runtime starts with mscorlib and System, and everything else -- the
    ; speech engine, zip files, bitmaps, the clipboard -- sits in an assembly
    ; of its own that has to be asked for first. Until it is, the type does not
    ; exist as far as AHK# is concerned: CS.System.Speech.Synthesis.
    ; SpeechSynthesizer() is "no such .NET type", which as a button on a window
    ; looks exactly like a button that does nothing.
    ;
    ; Two of the shelves on the .NET tab -- Speech and Zip files -- are in that
    ; position, so this is not an edge case; it is the first thing most people
    ; would pick. The adaptor writes the load itself.
    static Assemblies := Map(
        "System.Speech",              "System.Speech",
        "System.IO.Compression",      "System.IO.Compression.FileSystem",
        "System.Windows.Forms",       "System.Windows.Forms",
        "System.Drawing",             "System.Drawing",
        "System.Net.Http",            "System.Net.Http",
        "System.Web",                 "System.Web",
        "System.Xml.Linq",            "System.Xml.Linq",
        "System.Linq",                "System.Core",
        "System.Data",                "System.Data",
        "System.Configuration",       "System.Configuration",
        "System.Management",          "System.Management",
        "System.ServiceProcess",      "System.ServiceProcess",
        "System.Printing",            "System.Printing",
        "System.Transactions",        "System.Transactions",
        "System.Runtime.Serialization", "System.Runtime.Serialization",
        "System.Windows.Media",       "PresentationCore",
        "Microsoft.VisualBasic",      "Microsoft.VisualBasic")
    ; The longest namespace that matches, so System.Net.Http wins over nothing
    ; and System.IO.Compression does not catch plain System.IO.
    static Assembly(target) {
        ns := RegExReplace(String(target), "\.[^.]+$")     ; drop the method
        best := "", len := 0
        for prefix, asm in AxNet.Assemblies {
            if (SubStr(ns "." , 1, StrLen(prefix) + 1) = prefix "." || ns = prefix) {
                if (StrLen(prefix) > len)
                    len := StrLen(prefix), best := asm
            }
        }
        return best
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
    ; Whether this one runs in the background. It rides on Returns, beside
    ; @new, so the seven columns an adaptor has stay seven -- a project file
    ; written by an older studio still reads, and one written here still
    ; opens in an older one (it just runs the call in the foreground).
    static IsAsync(a) => InStr(a.Returns, "@async") > 0
    ; Does it say it gives text? The type is written as .NET spells it, or as
    ; the wizard offers it.
    static WantsText(a) {
        r := StrLower(RegExReplace(String(a.Returns), "@.*$"))
        return (r = "string" || r = "text")
    }
    static SetAsync(rets, on) {
        rets := RegExReplace(String(rets), "@async")
        return on ? rets "@async" : rets
    }
    ; An adaptor that hands back a promise is not one you can put a value from
    ; straight into a box, and saying so once here keeps every place that
    ; offers one honest.
    static Says(a) => AxNet.IsAsync(a)
        ? "starts it in the background and hands back the work"
        : "" 
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
        ; the assemblies these types live in, asked for once, before anything
        ; can call one of them
        asms := Map()
        asms.CaseSense := false
        for a in list
            if (a.Kind != "ahk" && (asm := AxNet.Assembly(a.Target)) != "")
                asms[asm] := true
        if asms.Count {
            s .= "`; .NET keeps these in assemblies of their own, and does not load one until it is"
              .  nl "`; asked for. Without this the type is simply not there, and the call that needs"
              .  nl "`; it fails with an error about no such .NET type." nl
            for asm in asms
                s .= "CS.LoadAssembly(" AxLit.S(asm) ")" nl
            s .= nl
        }
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
        any := false
        for a in list {
            args := ""
            for x in AxNet.Split(a.Params)
                args .= (args = "" ? "" : ", ") AxNet.Arg(x.N)
            call := AxNet.Call(a, args)
            note := AxNet.IsAsync(a) ? "  -- in the background: hands back the work, not the answer" : ""
            any := any || AxNet.IsAsync(a)
            s .= "; " a.Name "(" args ") -- " (a.Doc != "" ? a.Doc : a.Target) note nl
               . a.Name "(" AxNet.Opt(args) ") => " call nl
        }
        if any
            s .= nl AxNet.Helpers()
        return RTrim(s, "`n")
    }

    ; ------------------------------------------------------- background work
    ; Written out whenever anything runs in the background, and not otherwise.
    ;
    ; A promise is the right thing for AHK# to hand back and the wrong thing to
    ; put in front of someone who does not write code: .Then(...).Catch(...) is
    ; a syntax before it is an idea. These are the same five things as plain
    ; functions, which is what a step, a rule, a timer and a hotkey can all
    ; already call -- so "do this in the background, and when it is done, do
    ; that" is two steps rather than a chain nobody can type.
    static Helpers() {
        nl := "`n"
        return "`; Background work: these come with any adaptor set to run in the background." nl
             . "`; WhenDone is how a step says what happens afterwards -- the answer arrives" nl
             . "`; as the handler's first parameter, and the window never freezes waiting." nl
             . "WhenDone(work, then, ifItFails := " '""' ") {" nl
             . "    if !IsObject(work)" nl
             . "        return work" nl
             . "    p := work.Then(then)" nl
             . "    return (ifItFails != " '""' ") ? p.Catch(ifItFails) : p" nl
             . "}" nl
             . "`; Wait here for it instead. AutoHotkey keeps running while it waits -- timers," nl
             . "`; hotkeys and the window all still work -- so this is safe to use in a step." nl
             . "`; 0 waits for as long as it takes; anything else is a limit in milliseconds." nl
             . "WaitFor(work, timeoutMs := 0) => IsObject(work) ? work.Await(timeoutMs) : work" nl
             . "`; Has it finished? True or false, without waiting for it." nl
             . "IsDone(work) => IsObject(work) ? work.IsComplete : true" nl
             . "`; Why it failed, or blank while it is still going and when it worked." nl
             . "WhyItFailed(work) => IsObject(work) ? work.Error : " '""' nl
             . "`; Several at once: AllOf waits for every one and hands back a list of the" nl
             . "`; answers in order; AnyOf hands back the first one to finish." nl
             . "AllOf(work*) => CS.Promise.AwaitAll(work*)" nl
             . "AnyOf(work*) => CS.Promise.AwaitAny(work*)" nl
             . "`; Give up after a while: the work fails with a TimeoutError instead of hanging." nl
             . "GiveUpAfter(work, ms) => IsObject(work) ? work.Timeout(ms) : work" nl
             . "`; Do it later, without a timer of your own." nl
             . "AfterAWhile(ms, then) => CS.Promise.Delay(ms).Then(then)" 
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
        ; .Async is AHK#'s own: the same call, put on the thread pool, handing
        ; back a promise instead of a value. It goes in front of the method on
        ; a type, on an object or on a C# module, which is every kind we emit
        ; except "ahk" -- an AutoHotkey function is not .NET and cannot leave
        ; the AHK thread, so that one is never offered it.
        dot := AxNet.IsAsync(a) && a.Kind != "ahk" && a.Kind != "prop" ? ".Async." : "."
        call := ""
        switch a.Kind {
        case "static": call := "CS." type dot meth "(" pass ")"
        case "new":    call := "CS." type "()" dot meth "(" pass ")"
        case "prop":   call := "CS." t
        case "nuget":  call := AxNet.PkgClass(a.Source) dot a.Name "(" pass ")"
        case "ahk":    call := t "(" pass ")"
        }
        if (call = "")
            return '""'
        ; "It gives back: text" means text, not a .NET object that happens to
        ; have a ToString on it. A rule or a step deals in text and numbers, so
        ; an adaptor that hands back an object is no use to either -- and the
        ; failure is a long way from the cause: StrLen() further down the page
        ; complaining about a _CSProxy. String() asks .NET for its own text.
        ; Only for the ones that run here and then: a background one hands back
        ; the work, and what it settles to is converted where it is awaited.
        if (!AxNet.IsAsync(a) && AxNet.WantsText(a))
            return "String(" call ")"
        return call
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
