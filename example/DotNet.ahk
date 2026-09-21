#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes, icons and the components' styles
#Include ..\lib\AxGui.ahk
#Include ..\lib\AxAssets.ahk
#Include ..\lib\AxJson.ahk

; =============================================================================
;  DotNet.ahk — the whole .NET Framework, from AutoHotkey, in a window.
;
;  This one needs a library that is NOT part of AxGui: AHK# (github.com/owhs/
;  ahksharp), which hosts the .NET runtime inside the script and lets you call
;  it as if it were AutoHotkey — Net.System.Math.Pow(5, 3).
;
;  It is optional on purpose. An example that refuses to start is a bad
;  example, so this one runs either way: without AHK# it opens on a page that
;  says what is missing, where it looked, and what to do; with it, on five
;  pages of what that buys you.
;
;    Ready      what was found: version, runtime, bridge, and what it costs
;    Background work that does not freeze the window, and the same work on
;               every core at once
;    Archives   a .zip read entry by entry, unpacked and made, without a
;               temporary folder and without shelling out to anything
;    NuGet      search nuget.org, fetch a package as the program runs, use it
;    A server   a real web server, in this program, answering on a port
;    C#         a box you type C# into, compiled and run as you watch
;
;  --------------------------------------------------------------- finding it
;  #Include is resolved before a line of this runs, so it cannot be decided at
;  run time. *i makes an include OPTIONAL — a path that is not there is passed
;  over rather than being an error — so all the likely places are named, and
;  whether any of them answered is a question about a variable afterwards.
; =============================================================================

#Include *i %A_ScriptDir%\..\..\AHKSharp\lib\ahk#.ahk
#Include *i %A_ScriptDir%\..\lib\ahksharp\ahk#.ahk
#Include *i %A_ScriptDir%\Lib\Aris\owhs\ahksharp\lib\ahk#.ahk
#Include *i %A_ScriptDir%\..\Lib\Aris\owhs\ahksharp\lib\ahk#.ahk
#Include *i %A_MyDocuments%\AutoHotkey\Lib\Aris\owhs\ahksharp\lib\ahk#.ahk

; Where we looked, in the order above, so the page can show it as a list.
Places := [A_ScriptDir "\..\..\AHKSharp\lib\ahk#.ahk",
           A_ScriptDir "\..\lib\ahksharp\ahk#.ahk",
           A_ScriptDir "\Lib\Aris\owhs\ahksharp\lib\ahk#.ahk",
           A_ScriptDir "\..\Lib\Aris\owhs\ahksharp\lib\ahk#.ahk",
           A_MyDocuments "\AutoHotkey\Lib\Aris\owhs\ahksharp\lib\ahk#.ahk"]
Have := IsSet(AHK_SHARP_VERSION)
; And everything below goes through these two rather than through CS and
; Ver directly.
;
; Without AHK#, those are names nothing in this script ever assigns -- and
; AutoHotkey says so at load time, once for every place they are mentioned.
; That was seventeen warning dialogs before the window even appeared, for code
; that never runs. Assigning them instead is not allowed either: with AHK#
; loaded, CS is a class, and a class is not something you can assign to.
;
; IsSet is the one way to ask about a name without reading it, so it is asked
; once, here, and the answer is what the rest of the file uses.
Net := IsSet(CS) ? CS : ""
Ver := Have ? AHK_SHARP_VERSION : ""


; The page you see when AHK# is not here is not a happy page, and it should
; not be dressed like one: a dark edge rather than Windows' blue accent one,
; and a grey primary button instead of a blue "go on then". With AHK# loaded
; the window wears the accent it should.
g := AxGui({
    Title:     Have ? "DotNet — AxGui and AHK#" : "DotNet — AHK# is missing",
    AppName:   "AxAHK .NET",
    Width:     Have ? 1120 : 900,
    Height:    Have ? 760 : 700,
    MinWidth:  560,
    MinHeight: 420,
    BackColor: "202020",
    Theme:     "dark",
    ; the Windows 11 border the compositor draws round a floating window
    BorderColor: Have ? "default" : "#2b2b2b",
    SnapBorder:  Have ? "default" : "#2b2b2b",
    Accent:      Have ? "" : "#5a5a5a"})

if !Have
    Missing()
else
    Everything()
g.Show()


; ─────────────────────────────────────────────────────────────────────────────
;  Without it
;
;  Not a message box saying "AHK# not found". Someone who meets this has three
;  questions -- what is it, why does this want it, and what do I do -- and all
;  three are answered on the page, with the paths that were tried spelled out
;  so "I installed it" and "it is still not found" can be told apart.
; ─────────────────────────────────────────────────────────────────────────────
Missing() {
    global g, Net, Ver, Places
    g.AddPage("get", "AHK# is not here yet", "E946")
    g.AddInfoBar('Kind=warning Title="This example needs AHK#."',
        "Everything else in AxGui works without it. This one is about calling .NET, "
        . "and .NET has to be reachable before there is anything to show.")

    c := g.AddCard("", "What it is")
    g.AddText("",
        "AHK# hosts the .NET Framework 4 runtime inside your script and gives it AutoHotkey's own "
        . "syntax: Net.System.Math.Pow(5, 3) is a real call into .NET. It is one .ahk file and one "
        . "small bridge DLL — about 60 KB — and it needs no installer, no registration and no "
        . "administrator.")
    g.Use()

    c := g.AddCard("", "Why this example wants it")
    g.AddText("", "The five pages behind this one are all things AutoHotkey cannot do on its own:")
    for row in [["E916", "Work in the background", "A long job on a thread pool, with the window still answering."],
                ["F012", "Archives", "Read, unpack and make .zip files without a temporary folder."],
                ["E896", "NuGet", "Fetch a library from nuget.org as the program runs, and use it."],
                ["E968", "A web server", "Answer HTTP requests on a port, from inside this program."],
                ["E943", "C#", "Compile and run C# typed into a box."]]
        g.AddRow("Icon=" row[1], row[2], row[3])
    g.Use()

    c := g.AddCard("", "Where this script looked")
    for one in Places
        g.AddRow("Icon=" (FileExist(one) ? "E73E" : "E711"),
                 FileExist(one) ? "Found" : "Nothing here", Pretty(one))
    g.AddText("Style=opacity:.75",
        "Put AHK# at any one of those and start this again. The first is the usual one if you keep "
        . "AxAHK and AHKSharp side by side; the last three are where Aris installs it.")
    g.Use()

    g.AddButton("Accent Icon=E8A7", "Open the AHK# page")
        .OnEvent("Click", (*) => Run("https://github.com/owhs/ahksharp"))
    g.AddButton("x+8 Icon=E8C8", "Copy the clone command")
        .OnEvent("Click", (*) => (A_Clipboard := "git clone https://github.com/owhs/ahksharp "
            . '"' RegExReplace(A_ScriptDir, "\\[^\\]+$") '\..\AHKSharp"',
            g.Toast("Copied. Run it, then start this example again.", "Clipboard")))
    g.AddButton("x+8 Icon=E72C", "Look again")
        .OnEvent("Click", (*) => Reload())
    g.AddStatusBar([{Id: "msg", Text: "AHK# was not found — this page is all there is until it is.",
                     Icon: "E946", Grow: true}])
    ; The constructor's Accent: sets what the window keeps; this is what
    ; re-hues the theme's own sheet, which is where most of the blue lives.
    g.OnReady((*) => g.SetAccent("#5a5a5a"))
}
; a long path shortened in the middle, so both ends stay readable
Pretty(p) {
    p := RegExReplace(p, "\\[^\\]+\\\.\.", "")
    return StrLen(p) < 74 ? p : SubStr(p, 1, 34) "  …  " SubStr(p, -34)
}


; ─────────────────────────────────────────────────────────────────────────────
;  With it
; ─────────────────────────────────────────────────────────────────────────────
Everything() {
    global g, Net, Ver
    Ready(), Background(), Archives(), Packages(), Server(), Lab()
    g.AddStatusBar([{Id: "msg", Text: "Ready", Icon: "E7C4", Grow: true},
                    {Id: "clr", Text: "", Width: 210},
                    {Id: "busy", Text: "", Width: 150}])
    g.OnReady((*) => Started())
}
Started() {
    global g, Net, Ver
    ; AHK# puts up a small window of its own while it fetches a package. It is
    ; a box with a clipped line of text in it and no progress, and it appears
    ; over whatever you were looking at. This window can say the same thing
    ; better, so that one is turned off.
    try Net.Config.NuGetGui := false
    g.Status("clr", ".NET " Net.System.Environment.Version.ToString())
    g.Status("msg", "AHK# " Ver " — " Net.System.Environment.ProcessorCount " cores available")
}
Say(text) {
    global g, Net, Ver
    try g.Status("msg", text)
}
; Every page that starts work says so in the status bar, and stops saying it
; when the work lands. A window that is busy and looks idle is a window people
; click twice.
Busy(what) {
    global g, Net, Ver
    try g.Status("busy", what)
}


; --- Ready -------------------------------------------------------------------
Ready() {
    global g, Net, Ver
    g.AddPage("ready", "Ready", "E73E")
    g.AddInfoBar('Kind=success Title="AHK# is loaded."',
        "Every page in this window is calling the .NET Framework directly. Nothing here shells out "
        . "to another program, and nothing here is a wrapper someone wrote by hand.")

    g.AddStat('Icon=E943 Label="AHK#" w210', AHK_SHARP_VERSION)
    g.AddStat('x+8 Icon=E950 Label="The runtime it hosts" w250', ".NET " Net.System.Environment.Version.ToString())
    g.AddStat('x+8 Icon=E964 Label="Cores it can use" w190', Net.System.Environment.ProcessorCount)
    g.AddStat('x+8 Icon=E7F8 Label="Windows" w250', Net.System.Environment.OSVersion.ToString())

    c := g.AddCard("", "What it costs")
    g.AddText("",
        "The runtime is already on the machine — every Windows since 8 ships with .NET Framework 4. "
        . "What this script adds is one library file and one bridge DLL, loaded into this process. "
        . "There is no service, no registration and nothing left behind.")
    g.AddButton("Icon=E9D9", "What is in memory")
        .OnEvent("Click", (*) => ShowStats())
    g.AddButton("x+8 Icon=E8A7", "The AHK# documentation")
        .OnEvent("Click", (*) => Run("https://github.com/owhs/ahksharp"))
    g.AddEdit("vstats Fill Multi Rows=9 ReadOnly Style=font-family:Consolas,monospace;font-size:11px", "")
    g.Use()
}
ShowStats() {
    global g, Net, Ver
    out := ""
    try {
        for k, v in Net.Stats()
            out .= Format("{:-22}", k) v "`n"
    } catch as e
        out := "Could not read them: " e.Message
    g.Ctl("stats").Value := out
    Say("The .NET side of this process, as AHK# sees it.")
}


; --- Background --------------------------------------------------------------
;  The page this example exists for. Three buttons over the same work, so the
;  difference is something you watch rather than something you are told.
Background() {
    global g, Net, Ver
    g.AddPage("bg", "Background work", "E916")
    g.AddInfoBar('Title="The window must keep answering."',
        "Drag this window, or switch pages, while any of these is running. The first one will not "
        . "let you.")

    c := g.AddCard("", "Fingerprint every file in a folder")
    g.AddText("Style=opacity:.8",
        "SHA-256 of each file, which is how two files are told apart when their names are not "
        . "enough. It is deliberately real work: the bigger the folder, the clearer the three "
        . "buttons become.")
    g.AddEdit("vfolder w520", A_WinDir "\System32")
    g.AddButton("x+8 Icon=E8B7", "Browse")
        .OnEvent("Click", (*) => PickFolder())
    g.AddNumber("vlimit w150 Label=How many at most", 120)
    g.Use()

    g.AddButton("Icon=E768", "Here and now (it freezes)")
        .OnEvent("Click", (*) => HashHere())
    g.AddButton("x+8 Accent Icon=E916", "In the background")
        .OnEvent("Click", (*) => HashLater())
    g.AddButton("x+8 Icon=E964", "On every core at once")
        .OnEvent("Click", (*) => HashParallel())
    g.AddButton("x+8 Icon=E711", "Clear")
        .OnEvent("Click", (*) => (g.Ctl("hashes").Component.SetRows([]), g.Ctl("hprog").Value := 0, Busy("")))

    g.AddProgress("vhprog Fill", 0)
    g.AddDataView("vhashes Fill h300 PageSize=200", {
        Columns: [{Key: "name", Title: "File", Width: 300, Icon: true},
                  {Key: "size", Title: "Size", Width: 110, Align: "right", Sort: "number",
                   Format: (v, *) => AxWindow.FileSize(v)},
                  {Key: "hash", Title: "SHA-256", Width: 420},
                  {Key: "ms", Title: "ms", Width: 80, Align: "right", Sort: "number"}],
        Rows: [], Empty: "Pick a folder and choose one of the three buttons above."})
}
PickFolder() {
    global g, Net, Ver
    d := DirSelect("*" g.Ctl("folder").Value, 3, "Which folder?")
    if (d != "")
        g.Ctl("folder").Value := d
}
; The files to work on, as a plain array of paths.
Targets() {
    global g, Net, Ver
    dir := Trim(g.Ctl("folder").Value)
    max := Integer(g.Ctl("limit").Value)
    out := []
    if !DirExist(dir) {
        Say("There is no folder called that.")
        return out
    }
    loop files dir "\*.*" {
        if (A_LoopFileSize > 0)
            out.Push({Path: A_LoopFileFullPath, Name: A_LoopFileName, Size: A_LoopFileSize})
        if (out.Length >= max)
            break
    }
    if !out.Length
        Say("Nothing in that folder to read.")
    return out
}
Sha(path) => Net.System.BitConverter.ToString(
    Net.System.Security.Cryptography.SHA256.Create().ComputeHash(Net.System.IO.File.ReadAllBytes(path)))

; 1. The way it is usually written, and the reason people think AutoHotkey is
;    slow: the whole job on the one thread that also draws the window.
HashHere() {
    global g, Net, Ver
    files := Targets()
    if !files.Length
        return
    Busy("Frozen…")
    t := A_TickCount
    rows := []
    for f in files {
        one := A_TickCount
        try rows.Push({Key: f.Path, name: f.Name, size: f.Size, hash: Sha(f.Path), ms: A_TickCount - one})
    }
    g.Ctl("hashes").Component.SetRows(rows)
    g.Ctl("hprog").Value := 100
    Busy("")
    Say(rows.Length " files in " (A_TickCount - t) " ms — and the window was dead for all of it.")
}
; 2. .Async puts the same call on the thread pool and hands back a promise.
;    The handler runs back on the AHK thread when it lands, so the rows can be
;    added from it as if nothing unusual had happened.
HashLater() {
    global g, Net, Ver
    files := Targets()
    if !files.Length
        return
    rows := [], done := 0, t := A_TickCount
    g.Ctl("hashes").Component.SetRows([])
    g.Ctl("hprog").Value := 0
    Busy("Working… try dragging the window")
    for f in files {
        one := f
        started := A_TickCount
        work := Net.System.IO.File.Async.ReadAllBytes(one.Path)
        work.Then(Landed.Bind(one, started)).Catch(Failed.Bind(one))
    }
    Landed(f, started, bytes) {
        try rows.Push({Key: f.Path, name: f.Name, size: f.Size, ms: A_TickCount - started,
                       hash: Net.System.BitConverter.ToString(
                           Net.System.Security.Cryptography.SHA256.Create().ComputeHash(bytes))})
        Progress()
    }
    Failed(f, err) {
        rows.Push({Key: f.Path, name: f.Name, size: f.Size, hash: "— " err.Message, ms: 0})
        Progress()
    }
    Progress() {
        done++
        g.Ctl("hprog").Value := Round(done * 100 / files.Length)
        if (done < files.Length)
            return
        g.Ctl("hashes").Component.SetRows(rows)
        Busy("")
        Say(rows.Length " files in " (A_TickCount - t) " ms, and the window answered throughout.")
    }
}
; 3. Net.Fast.Map takes a C# EXPRESSION, not an AutoHotkey function, so the work
;    never comes back to this thread at all: .NET runs it across every core and
;    hands back the answers in order. It blocks here until the lot is done --
;    what it buys is throughput, not responsiveness, and on a big folder the
;    difference against the first button is the number of cores in the machine.
HashParallel() {
    global g, Net, Ver
    files := Targets()
    if !files.Length
        return
    paths := []
    for f in files
        paths.Push(f.Path)
    Busy("All " Net.System.Environment.ProcessorCount " cores…")
    t := A_TickCount
    rows := []
    try {
        hashes := Net.Fast.Map(paths,
            "System.BitConverter.ToString(System.Security.Cryptography.SHA256.Create()"
            . ".ComputeHash(System.IO.File.ReadAllBytes(x)))")
        for i, f in files
            rows.Push({Key: f.Path, name: f.Name, size: f.Size,
                       hash: i <= hashes.Length ? hashes[i] : "", ms: 0})
    } catch as e {
        Busy("")
        return Say("It would not run: " e.Message)
    }
    g.Ctl("hashes").Component.SetRows(rows)
    g.Ctl("hprog").Value := 100
    Busy("")
    Say(rows.Length " files in " (A_TickCount - t) " ms on "
        . Net.System.Environment.ProcessorCount " cores. The per-file times are blank because "
        . "none of it happened here.")
}


; --- Archives ----------------------------------------------------------------
Archives() {
    global g, Net, Ver
    g.AddPage("zip", "Archives", "F012")
    g.AddInfoBar('Title="A .zip is a folder you can look inside."',
        "Read entry by entry without unpacking, unpack one or all of it, or make one — all of it "
        . "System.IO.Compression, which is part of Windows.")

    g.AddEdit("vzip w560", "")
    g.AddButton("x+8 Icon=E8E5", "Open a .zip")
        .OnEvent("Click", (*) => OpenZip())
    g.AddButton("x+8 Icon=E72C", "Read it again")
        .OnEvent("Click", (*) => ListZip())

    g.AddButton("Icon=E896", "Unpack all of it")
        .OnEvent("Click", (*) => Unpack())
    g.AddButton("x+8 Icon=E8B7", "Make one from a folder")
        .OnEvent("Click", (*) => MakeZip())

    g.AddDataView("ventries Fill h360 PageSize=300", {
        Columns: [{Key: "name", Title: "Inside the archive", Width: 360, Icon: true},
                  {Key: "size", Title: "Size", Width: 110, Align: "right", Sort: "number",
                   Format: (v, *) => AxWindow.FileSize(v)},
                  {Key: "packed", Title: "Packed", Width: 110, Align: "right", Sort: "number",
                   Format: (v, *) => AxWindow.FileSize(v)},
                  {Key: "saved", Title: "Saved", Width: 160, Sort: "number",
                   Format: (v, *) => Bar(v)},
                  {Key: "when", Title: "Changed", Width: 170}],
        Rows: [], Empty: "Open a .zip, or make one from a folder."})
}
; a filled bar drawn with characters: no image, no canvas, sorts as the number
; it is
Bar(pct) {
    n := Max(0, Min(10, Round(pct / 10)))
    return StrReplace(Format("{:" n "}", ""), " ", Chr(0x2588))
         . StrReplace(Format("{:" (10 - n) "}", ""), " ", Chr(0x2591)) "  " pct "%"
}
Zipped() {
    ; System.IO.Compression.FileSystem is a separate assembly -- ZipFile lives
    ; there rather than beside ZipArchive, which is the one thing about .NET's
    ; zip support that catches everybody out.
    static once := false
    if !once
        try Net.LoadAssembly("System.IO.Compression.FileSystem"), once := true
    return once
}
OpenZip() {
    global g, Net, Ver
    f := FileSelect(3, , "Which archive?", "Archives (*.zip;*.nupkg;*.docx;*.xlsx;*.jar)")
    if (f = "")
        return
    g.Ctl("zip").Value := f
    ListZip()
}
ListZip() {
    global g, Net, Ver
    path := Trim(g.Ctl("zip").Value)
    if !FileExist(path)
        return Say("Pick a .zip first.")
    Zipped()
    rows := []
    try
        z := Net.System.IO.Compression.ZipFile.OpenRead(path)
    catch as e
        return Say("It would not open: " e.Message)
    ; One try per entry, not one round the loop: an archive with a single odd
    ; entry in it is still an archive worth listing, and a list that empties
    ; itself because of one row is the worst way to say so.
    for e in z.Entries {
        try {
            size := e.Length + 0, packed := e.CompressedLength + 0
            rows.Push({Key: e.FullName, name: e.FullName, size: size, packed: packed,
                       saved: size > 0 ? Round((size - packed) * 100 / size) : 0,
                       when: When(e.LastWriteTime)})
        }
    }
    try z.Dispose()
    g.Ctl("entries").Component.SetRows(rows)
    Say(rows.Length " entr" (rows.Length = 1 ? "y" : "ies") " — nothing was unpacked to read them.")
}
; A zip entry's time is a DateTimeOffset, and AHK# hands one of those across as
; the string .NET printed -- not as an AHK timestamp, the way a plain DateTime
; comes back. So it is text on arrival: shown as it is, without its offset.
When(v) {
    s := Trim(String(v))
    return RegExReplace(s, "\s*[+-]\d\d:\d\d$")
}
Unpack() {
    global g, Net, Ver
    path := Trim(g.Ctl("zip").Value)
    if !FileExist(path)
        return Say("Pick a .zip first.")
    to := DirSelect(, 3, "Unpack it where?")
    if (to = "")
        return
    Zipped()
    Busy("Unpacking…")
    ; in the background, because a big archive takes long enough to matter
    Net.System.IO.Compression.ZipFile.Async.ExtractToDirectory(path, to)
        .Then((*) => (Busy(""), Say("Unpacked into " to), Run('explorer.exe "' to '"')))
        .Catch((e) => (Busy(""), Say("It would not unpack: " e.Message)))
}
MakeZip() {
    global g, Net, Ver
    from := DirSelect(, 3, "Which folder?")
    if (from = "")
        return
    to := FileSelect("S16", RegExReplace(from, "^.*\\") ".zip", "Save the archive as", "Archives (*.zip)")
    if (to = "")
        return
    Zipped()
    Busy("Packing…")
    t := A_TickCount
    Net.System.IO.Compression.ZipFile.Async.CreateFromDirectory(from, to)
        .Then((*) => (Busy(""), g.Ctl("zip").Value := to, ListZip(),
                      Say("Made in " (A_TickCount - t) " ms, in the background.")))
        .Catch((e) => (Busy(""), Say("It would not pack: " e.Message)))
}


; --- NuGet -------------------------------------------------------------------
Packages() {
    global g, Net, Ver
    g.AddPage("nuget", "NuGet", "E896")
    g.AddInfoBar('Title="Four hundred thousand libraries, one line."',
        "Net.NuGet.Require downloads a package and its dependencies while the program runs, checks "
        . "it against the hash nuget.org publishes, and hands back the DLL to load.")

    g.AddSearch("vq w420", "json")
    g.AddButton("x+8 Accent Icon=E721", "Search nuget.org")
        .OnEvent("Click", (*) => FindPkg())
    g.AddProgress("vnuprog Fill h4 Indeterminate Hidden")
    g.AddDataView("vpkgs Fill h240 Single", {
        Columns: [{Key: "id", Title: "Package", Width: 280, Icon: true},
                  {Key: "ver", Title: "Version", Width: 110},
                  {Key: "dl", Title: "Downloads", Width: 130, Align: "right", Sort: "number",
                   Format: (v, *) => Thousands(v)},
                  {Key: "desc", Title: "What it is", Width: 460}],
        Rows: [], Empty: "Type something and search."})

    g.AddButton("Accent Icon=E896", "Get the one I picked, and use it")
        .OnEvent("Click", (*) => UsePkg())
    g.AddEdit("vnuout Fill Multi Rows=10 ReadOnly Style=font-family:Consolas,monospace;font-size:11px",
        "Nothing fetched yet.")
}
Thousands(n) {
    s := String(Round(n)), out := ""
    loop parse s
        out := A_LoopField ((StrLen(s) - A_Index) > 0 && Mod(StrLen(s) - A_Index, 3) = 0 ? "," : "") out
    return out
}
; nuget.org's own search, fetched the way everything else on this page is --
; on a thread pool, with the window still answering. CS.NuGet.Search would do
; the same thing and takes about two seconds ON THIS THREAD, so the window sat
; there frozen with nothing to look at; the reason this page exists is that
; .NET does not make you do that.
FindPkg() {
    global g, Net, Ver
    q := Trim(g.Ctl("q").Value)
    if (q = "")
        return Say("Type what to look for.")
    Working(true)
    Say("Asking nuget.org…")
    url := "https://azuresearch-usnc.nuget.org/query?prerelease=false&semVerLevel=2.0.0&take=30&q="
         . Escape(q)
    Net.System.Net.WebClient().Async.DownloadString(url)
        .Then((text) => Found(text))
        .Catch((e) => (Working(false), Say("nuget.org would not answer: " e.Message)))
}
Working(on) {
    global g
    try {
        g.Ctl("nuprog").Visible := on
        g.Ctl("pkgs").Component.SetRows([])
    }
    Busy(on ? "Searching…" : "")
}
Found(text) {
    global g
    Working(false)
    rows := []
    try {
        d := AxJson.Parse(text)
        list := (d is Map && d.Has("data")) ? d["data"] : []
        for one in (list is Array ? list : []) {
            ; the answer is a Map, and so is what CS.NuGet.Search hands back --
            ; reading it as one.Id gives nothing at all, silently, which is how
            ; this page came to say "0 packages" over a search that worked
            id := Get(one, "id"), ver := Get(one, "version")
            if (id = "")
                continue
            au := Get(one, "authors")
            rows.Push({Key: id, id: id, ver: ver,
                       dl: Get(one, "totalDownloads", 0),
                       desc: SubStr(String(Get(one, "description")), 1, 160)})
        }
    } catch as e
        return Say("That answer made no sense: " e.Message)
    g.Ctl("pkgs").Component.SetRows(rows)
    Say(rows.Length " package" (rows.Length = 1 ? "" : "s")
        . ". Getting one says whether this runtime can load it.")
}
Get(m, k, d := "") => (m is Map && m.Has(k)) ? m[k] : d
; what may go in a query string, and what has to be spelled out
Escape(t) {
    out := ""
    loop parse t
        out .= RegExMatch(A_LoopField, "[A-Za-z0-9._~-]") ? A_LoopField
             : Format("%{:02X}", Ord(A_LoopField) & 0xFF)
    return out
}
UsePkg() {
    global g, Net, Ver
    sel := g.Ctl("pkgs").Component.Selected()
    id := sel.Length ? sel[1].id : "Newtonsoft.Json"
    ver := sel.Length ? sel[1].ver : "13.0.3"
    Busy("Fetching " id "…")
    Say("Fetching " id " " ver " from nuget.org…")
    try g.Ctl("nuprog").Visible := true
    out := ""
    try {
        dll := Net.NuGet.Require(id, ver)
        out .= id " " ver "`n`n" dll "`n`n"
        Net.LoadAssembly(dll)
        out .= "Loaded. What it brought with it:`n`n"
        ; Types are read off the assembly rather than guessed, so this says
        ; something true about whichever package was picked.
        asm := Net.System.Reflection.Assembly.LoadFrom(dll)
        n := 0
        for t in asm.GetExportedTypes() {
            out .= "    " t.FullName "`n"
            if (++n >= 25)
                break
        }
        out .= (n >= 25) ? "    … and more`n" : ""
        ; and one thing actually done with it, when it is the one everybody has
        if InStr(id, "Newtonsoft.Json") {
            pretty := Net.Newtonsoft.Json.Linq.JToken.Parse(
                '{"from":"AutoHotkey","through":"AHK#","cores":' Net.System.Environment.ProcessorCount
                . ',"list":[1,2,3]}').ToString()
            out .= "`nAnd used, there and then:`n`n" pretty "`n"
        }
    } catch as e
        out .= "`nIt would not load: " e.Message
    Busy("")
    try g.Ctl("nuprog").Visible := false
    g.Ctl("nuout").Value := out
    Say(id " is in this process now.")
}


; --- A server ----------------------------------------------------------------
Listener := "", Requests := 0
Server() {
    global g, Net, Ver
    g.AddPage("server", "A web server", "E968")
    g.AddInfoBar('Title="Not a toy."',
        "HttpListener is the HTTP stack Windows itself uses. Start it, and this program is a web "
        . "server — from a browser, from another machine on the network, from anything that speaks HTTP.")

    g.AddNumber("vport w160 Label=Port", 8731)
    g.AddButton("x+8 Accent Icon=E768", "Start it")
        .OnEvent("Click", (*) => StartServer())
    g.AddButton("x+8 Icon=E71A", "Stop it")
        .OnEvent("Click", (*) => StopServer())
    g.AddButton("x+8 Icon=E8A7", "Open it in a browser")
        .OnEvent("Click", (*) => Run("http://localhost:" g.Ctl("port").Value "/"))

    c := g.AddCard("", "What it answers with")
    g.AddText("Style=opacity:.8",
        "A page built here, in AutoHotkey, from whatever this program knows — so the browser is "
        . "looking at the live state of this window.")
    g.AddEdit("vsrvlog Fill Multi Rows=12 ReadOnly Style=font-family:Consolas,monospace;font-size:11px",
        "Not started.")
    g.Use()
}
Log(line) {
    global g, Net, Ver
    try {
        box := g.Ctl("srvlog")
        box.Value := FormatTime(, "HH:mm:ss") "  " line "`n" box.Value
    }
}
StartServer() {
    global g, Listener, Requests
    if IsObject(Listener)
        return Say("It is already running.")
    port := Integer(g.Ctl("port").Value)
    try {
        Listener := Net.System.Net.HttpListener()
        Listener.Prefixes.Add("http://localhost:" port "/")
        Listener.Start()
    } catch as e {
        Listener := ""
        return Say("It would not start: " e.Message)
    }
    Requests := 0
    Log("Listening on http://localhost:" port "/")
    Say("Serving on port " port ". Open it in a browser.")
    Busy("Serving")
    Wait()
}
; One request at a time, each waited for in the background: GetContextAsync
; hands back a Task, the promise fires on the AHK thread when a browser
; connects, and the next wait is started from inside the handler. So the window
; is never blocked and there is no polling timer.
Wait() {
    global Listener
    if !IsObject(Listener)
        return
    try {
        Listener.GetContextAsync().Then(Served).Catch((*) => 0)
    }
}
Served(ctx) {
    global Listener, Requests
    if !IsObject(Listener)
        return
    Requests++
    url := "/"
    try url := ctx.Request.Url.AbsolutePath
    Log("GET " url)
    body := PageFor(url)
    try {
        bytes := Net.System.Text.Encoding.UTF8.GetBytes(body)
        ctx.Response.ContentType := InStr(url, ".json") ? "application/json" : "text/html; charset=utf-8"
        ctx.Response.ContentLength64 := bytes.Length
        ctx.Response.OutputStream.Write(bytes, 0, bytes.Length)
        ctx.Response.OutputStream.Close()
    }
    Wait()
}
PageFor(url) {
    global g, Net, Ver, Requests
    if InStr(url, ".json")
        return '{"served":' Requests ',"script":"' StrReplace(A_ScriptName, '"', "") '","cores":'
             . Net.System.Environment.ProcessorCount ',"uptime":' Round(A_TickCount / 1000) "}"
    rows := ""
    for pair in [["Served so far", Requests], ["Script", A_ScriptName],
                 ["AHK#", Ver], [".NET", Net.System.Environment.Version.ToString()],
                 ["Cores", Net.System.Environment.ProcessorCount],
                 ["Running for", Round(A_TickCount / 1000) " seconds"]]
        rows .= "<tr><td>" pair[1] "</td><td><b>" pair[2] "</b></td></tr>"
    return "<!doctype html><meta charset=utf-8><title>AxGui</title>"
         . "<style>body{font:15px/1.6 system-ui,sans-serif;background:#181818;color:#eee;margin:60px auto;max-width:640px}"
         . "td{padding:6px 18px 6px 0;border-bottom:1px solid #333}h1{font-weight:600}a{color:#60cdff}</style>"
         . "<h1>Served by an AutoHotkey script</h1>"
         . "<p>This page was built in AutoHotkey and handed to Windows' own HTTP stack "
         . "through AHK#. <a href='/state.json'>The same as JSON</a>.</p><table>" rows "</table>"
}
StopServer() {
    global Listener
    if !IsObject(Listener)
        return Say("It is not running.")
    try Listener.Stop(), Listener.Close()
    Listener := ""
    Log("Stopped.")
    Busy("")
    Say("Stopped.")
}


; --- C# ----------------------------------------------------------------------
Lab() {
    global g, Net, Ver
    g.AddPage("lab", "C#", "E943")
    g.AddInfoBar('Title="Typed here, compiled, run."',
        "One line is an expression and its value comes back. More than one is a body, and whatever "
        . "it returns comes back. Both are compiled by the C# compiler that ships with Windows.")
    g.AddCodeEditor("vcs Fill h260 Lang=cs Theme=auto",
        "var files = System.IO.Directory.GetFiles(System.Environment.SystemDirectory, `"*.dll`");`n"
        . "long total = 0;`n"
        . "foreach (var f in files) total += new System.IO.FileInfo(f).Length;`n"
        . "return files.Length + `" DLLs, `" + (total / 1024 / 1024) + `" MB`";")
    g.AddButton("Accent Icon=E768", "Run it")
        .OnEvent("Click", (*) => RunCs())
    g.AddButton("x+8 Icon=E8F4", "An expression instead")
        .OnEvent("Click", (*) => (g.Ctl("cs").Value := "System.Guid.NewGuid().ToString()", RunCs()))
    g.AddButton("x+8 Icon=E916", "Something slow")
        .OnEvent("Click", (*) => (g.Ctl("cs").Value :=
            "double sum = 0;`nfor (int i = 1; i < 40000000; i++) sum += System.Math.Sqrt(i);`nreturn sum;", RunCs()))
    g.AddEdit("vcsout Fill Multi Rows=8 ReadOnly Style=font-family:Consolas,monospace;font-size:11px", "")
}
RunCs() {
    global g, Net, Ver
    src := Trim(g.Ctl("cs").Value, " `t`r`n")
    if (src = "")
        return
    Busy("Compiling…")
    t := A_TickCount
    try {
        ; one line and no semicolon is an expression; anything else is a body
        r := (!InStr(src, "`n") && !InStr(src, ";")) ? Net.Eval(src) : Net.Run(src)
        g.Ctl("csout").Value := "= " (IsObject(r) ? Type(r) " " r.ToString() : r)
            . "`n`n" (A_TickCount - t) " ms, compile included."
        Say("It ran.")
    } catch as e {
        ; a .NET failure keeps its own type, which is what tells a mistake in
        ; the C# apart from a mistake in what it did
        g.Ctl("csout").Value := e.Message
            . (e.HasProp("NetType") && e.NetType != "" ? "`n`n.NET type: " e.NetType : "")
        Say("It would not run.")
    }
    Busy("")
}
