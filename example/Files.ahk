#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes, icons and the component's styles
#Include ..\lib\AxGui.ahk
#Include ..\lib\AxAssets.ahk

; =============================================================================
;  Files.ahk — the file view, in every shape it takes.
;
;  One idea runs through the whole of this: a *state* knows where you are and
;  what you are looking at, and the *parts* draw it. Nothing here writes HTML
;  and nothing here knows whether the files are real.
;
;    Explorer      the whole thing in one line, over your Documents folder
;    In parts      the same state, six parts, laid out your way
;    Rich columns  bars, stars, chips, swatches, sparklines — and cells you
;                  can type into
;    Five views    details, list, tiles, icons and thumbnails, with tick
;                  boxes, hidden items and grouping
;    This PC       the real drives, with a free-space bar that is real too
;    Registry      HKCU and its friends, as folders and files
;    Archive       inside a .zip, through the shell's own reader
;    Your own      a source and a preview renderer written here, in this file
;
;  The pieces:  lib\components\FileSource\  where the files come from
;               lib\components\FileView\    the state and the six parts
; =============================================================================


; ─────────────────────────────────────────────────────────────────────────────
;  Window
; ─────────────────────────────────────────────────────────────────────────────

g := AxGui({
    Title:     "AxAHK Files",
    AppName:   "AxAHK Files",
    Width:     1120,
    Height:    800,
    MinWidth:  760,
    MinHeight: 480,
    BackColor: "202020",
    Theme:     "dark"
})

LogText := ""

; The lines are kept in AutoHotkey and the box is written from them. Reading
; the box back to prepend to it is a round trip through the document that can
; fail quietly, and then nothing ever appears.
; The box is named logBox, not log: this page is g.AddPage("log", ...) and two
; elements cannot share an id -- El("log") would find the page and the writes
; would land on a <div> and vanish.
LogLine(msg) {
    global logBox, LogText
    LogText := FormatTime(, "HH:mm:ss") "  " msg "`n" LogText
    if IsSet(logBox) && IsObject(logBox)
        try logBox.Value := LogText
}
ClearLog() {
    global logBox, LogText
    LogText := ""
    try logBox.Value := ""
}
Section(title, about := "") {
    c := g.AddCard("y+6", title)
    if (about != "")
        g.AddText("Caption Fill", about)
    return c
}
Lead(text) => g.AddText("Fill", text)
Join(list) {
    s := ""
    for x in list
        s .= (s = "" ? "" : ", ") String(x)
    return (s = "") ? "(none)" : s
}
Names(items) {
    s := ""
    for it in items
        s .= (s = "" ? "" : ", ") it.Name
    return (s = "") ? "(none)" : s
}


; ─────────────────────────────────────────────────────────────────────────────
;  Page 1 — the whole thing, in one line
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("explorer", "Explorer", "EC50")

Lead("AddFileExplorer builds a state, a toolbar, a path bar, a folder tree, the view, a preview pane and a "
   . "status strip, and wires the seven together. It is a convenience over the six Add* methods on the next "
   . "page, and nothing more — the state it made is on .State, and everything below drives that.")

Section("This PC, with the usual places", "The list down the left is Quick access: the folders Windows gives "
    . "everyone a name for, the drives, and whatever is pinned. Hover a row for its pin, or right-click a folder "
    . "in the view and pin it from there — this one starts with the example's own folder pinned.`n`n"
    . "Double-click a folder to go in; Backspace or the up arrow to come out. Drag the edges between the panes. "
    . "Click a column heading to sort, drag the edge between two headings to resize, right-click a heading to "
    . "hide one. F5 refreshes, F2 renames, and typing a few letters jumps — in the view, the tree and the "
    . "places list alike.")

home := g.AddFileExplorer("Fill h420 Preview=300 Places=230", {
    Source: AxFileLocal(),
    Name:   "home",
    Path:   A_MyDocuments,
    Pinned: [A_ScriptDir],
    Sort:   {Key: "modified", Dir: -1}})

HomeState := AxFileState.Named("home")
HomeState.OnActivate((it, st) => LogLine("Opened " it.Name))
HomeState.OnPath((p, st) => LogLine("Now in " (p = "" ? st.Source.Label : p)))
HomeState.OnSelect((items, st) => LogLine(items.Length " selected: " Names(items)))
HomeState.OnError((msg, st) => LogLine("! " msg))
HomeState.OnDrop((paths, target, st) => LogLine(paths.Length " dropped on " target.Name))

g.AddButton("", "Go to the script's folder").OnClick((*) => HomeState.Go(A_ScriptDir))
g.AddButton("x+8", "Go to Documents").OnClick((*) => HomeState.Go(A_MyDocuments))
g.AddButton("x+8", "Refresh").OnClick((*) => HomeState.Refresh())
g.AddButton("x+8", "Pin where I am").OnClick((*) => HomeState.Pin(HomeState.Path))
g.AddButton("x+8", "What is pinned?").OnClick((*) => LogLine("Pinned: " Join(HomeState.PinnedPaths())))
g.AddButton("x+8", "Only the pins").OnClick((*) => HomeState.SetPlaces([]))
g.AddButton("x+8", "The usual places").OnClick((*) => HomeState.SetPlaces(HomeState.DefaultPlaces()))
g.AddText("Hint", "Drop files on it from anywhere in Windows and OnDrop says what landed where. Nothing is "
    . "moved, copied or deleted by any of this: the handler decides, and this example only writes to the log.")
g.Use()


; ─────────────────────────────────────────────────────────────────────────────
;  Page 2 — the same state, six parts, your layout
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("parts", "In parts", "E8A9")

Lead("The parts do not talk to each other and none of them owns the state, so you can place them anywhere, "
   . "use one or all of them, or write a seventh. Here they are pulled apart: the status strip is at the top, "
   . "the path bar under the view, and the buttons are ordinary AddButtons calling ordinary state methods.")

Parts := AxFileState({Name: "parts", Source: AxFileLocal(A_ScriptDir), Mode: "tiles"})

Section("Six parts, one state", "Everything below is looking at one AxFileState. Click in the tree and the "
    . "view, the path bar, the preview and the status line all follow, because they are all drawing the "
    . "same thing.")

g.AddFileStatus("State=parts")
g.AddFilePlaces("w190 h260 State=parts")
g.AddFileTree("x+8 w190 h260 State=parts")
g.AddFileView("x+8 Fill h260 State=parts")
g.AddFilePath("State=parts Top=8")
g.Use()

Section("Driving it from AutoHotkey", "Every button on the toolbar is one of these calls. There is nothing "
    . "the toolbar can do that your own button cannot.")

g.AddButton("", "Back").OnClick((*) => Parts.Back())
g.AddButton("x+6", "Forward").OnClick((*) => Parts.Forward())
g.AddButton("x+6", "Up").OnClick((*) => Parts.Up())
g.AddButton("x+6", "Home").OnClick((*) => Parts.Home())
g.AddButton("x+12", "Select all").OnClick((*) => Parts.SelectAll())
g.AddButton("x+6", "Invert").OnClick((*) => Parts.Invert())
g.AddButton("x+6", "Tick boxes").OnClick((*) => Parts.Toggle("checks"))
g.AddButton("x+6", "Hidden items").OnClick((*) => Parts.Toggle("hidden"))
g.AddText("", "Show it as")
g.AddSegmented("x+8 vpartsMode Choose3", "details:Details|list:List|tiles:Tiles|icons:Icons|thumbs:Thumbs")
    .OnChange((c, v, *) => Parts.SetMode(v))
g.AddText("x+16", "Group by")
g.AddDDL("x+8 w150 Choose1", ":Nothing|type:Type|family:What it is")
    .OnChange((c, v, *) => Parts.SetGroup(v))
g.AddText("Hint", "Filter, sort, group. The state runs one pipeline and every part draws whatever comes out "
    . "of it, so a mode is a class on the frame rather than a fifth implementation of selection and ticking.")
g.Use()

Parts.OnSelect((items, st) => LogLine("Parts: " Names(items)))


; ─────────────────────────────────────────────────────────────────────────────
;  Page 3 — the rich columns
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("columns", "Rich columns", "E9D5")

Lead("A column says what to read and how to draw it. Render picks the shape — a filled bar, stars, chips, "
   . "a colour swatch, a toggle, a sparkline — Format picks the words, Value reads something that is not on "
   . "the item, and Html is the way out of all of that. Edit makes the cell take typing.")

; A library that is not on any disk: the source is a tree handed over in AHK,
; and each track carries whatever a column might want to show.
Tracks := []
for t in [
    ; name                      plays  rating  tags                      colour     lossless  weeks
    ["Coastline.flac",          412,   5, "ambient, favourite",          "#4fc3f7", true,  [3,9,14,22,31,28,40]],
    ["Night Drive.mp3",         318,   4, "electronic",                  "#ab47bc", false, [12,18,11,26,19,24,21]],
    ["Paper Boats.mp3",         96,    3, "acoustic, demo",              "#66bb6a", false, [2,4,9,7,12,6,9]],
    ["Glasshouse.flac",         540,   5, "ambient, live",               "#4fc3f7", true,  [30,35,29,44,51,47,60]],
    ["Two Winters.mp3",         27,    2, "demo",                        "#ffa726", false, [1,3,2,5,4,2,3]],
    ["Radio Silence.wav",       8,     1, "unfinished",                  "#ef5350", true,  [0,1,1,0,2,1,1]],
    ["Harbour Lights.flac",     287,   4, "ambient",                     "#4fc3f7", true,  [14,19,23,20,27,31,29]],
    ["Cassette.mp3",            164,   3, "lo-fi, favourite",            "#8d6e63", false, [8,11,9,14,12,17,15]],
    ["Marigold.mp3",            233,   4, "acoustic",                    "#66bb6a", false, [10,14,16,13,21,18,24]],
    ["The Long Way.wav",        61,    2, "demo, unfinished",            "#ffa726", true,  [3,5,4,6,5,8,6]]]
    Tracks.Push({Name: t[1], Kind: "file", Size: t[2] * 9400 + 2200000,
                 Modified: FormatTime(DateAdd(A_Now, -t[2], "Days"), "yyyyMMddHHmmss"),
                 Plays: t[2], Rating: t[3], Tags: t[4], Colour: t[5], Lossless: t[6],
                 Weeks: t[7], Note: ""})

Media := AxFileState({
    Name: "media",
    Source: AxFileVirtual([{Name: "Library", Kind: "folder", Children: Tracks}],
                          {Label: "Music", Icon: "E8D6", Sep: "/"}),
    Path: "Library",
    Sort: {Key: "plays", Dir: -1},
    Columns: [
        {Key: "name",     Title: "Track",  Width: 190, Render: "name", Hideable: false},
        {Key: "plays",    Title: "Plays",  Width: 170, Render: "bar", Max: 560, Sort: "number",
         Format: (v, it, st) => v " plays",
         Color:  (v, it, st) => (v > 400) ? "#7bd88f" : (v < 50) ? "#e57373" : ""},
        {Key: "rating",   Title: "Rating", Width: 104, Render: "rating", Edit: true, Sort: "number"},
        {Key: "tags",     Title: "Tags",   Width: 190, Render: "chips"},
        {Key: "colour",   Title: "Mood",   Width: 110, Render: "swatch",
         Format: (v, it, st) => ""},
        {Key: "lossless", Title: "Lossless", Width: 84, Render: "toggle", Align: "center"},
        {Key: "weeks",    Title: "Last 7 weeks", Width: 130, Render: "spark", Sort: false},
        {Key: "note",     Title: "Note",   Width: 180, Edit: "text",
         Format: (v, it, st) => (v = "") ? "—" : v},
        {Key: "size",     Title: "Size",   Width: 90, Render: "size", Align: "right", Sort: "number"}]})

Media.OnEdit((it, key, v, st) => LogLine("Edited " it.Name ": " key " = " v))

Section("Ten renderers, one table", "Click a star to set a rating — an editable rating needs no text box and "
    . "nothing to confirm. Click a selected Note cell a second time, unhurriedly, and type; Enter keeps it and "
    . "Escape puts it back. OnEdit hands your code the item, the column and the new value.")

g.AddFileView("Fill h300 State=media")

g.AddButton("", "Group by mood").OnClick((*) => Media.SetGroup("colour"))
g.AddButton("x+6", "Group by what it is").OnClick((*) => Media.SetGroup("family"))
g.AddButton("x+6", "Don't group").OnClick((*) => Media.SetGroup(""))
g.AddButton("x+12", "Hide the sparkline").OnClick((*) => Media.ToggleColumn("weeks"))
g.AddButton("x+6", "Hide the tags").OnClick((*) => Media.ToggleColumn("tags"))
g.AddButton("x+6", "Sort by rating").OnClick((*) => Media.SetSort("rating"))
g.AddText("Hint", "The bar's colour is a function of the value, so the quiet tracks turn red and the loud ones "
    . "green without anything watching them. Max may be a number, another column's key, or a function.")
g.Use()

Section("The same rows as tiles", "A rich column is not only for a table: Badges= names the columns a tile, "
    . "icon or thumbnail should carry under its name.")

Shelf := AxFileState({Name: "shelf", Source: Media.Source, Path: "Library", Mode: "tiles",
                      Columns: Media.Cols})
g.AddFileView("Fill h200 State=shelf Badges=rating,tags")
g.Use()


; ─────────────────────────────────────────────────────────────────────────────
;  Page 4 — the five views
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("views", "Five views", "E8FD")

Lead("Details, list, tiles, icons and thumbnails are one Render() and a class on the frame. A source that can "
   . "produce a picture for an item gets thumbnails; one that cannot gets its glyph, at whatever size the "
   . "icons are set to.")

; Photographs that are really the four pictures in example\assets, under
; invented names — the point being that the view neither knows nor cares.
Shots := []
for s in [
    ["Harbour at dusk.jpg",  "photo.jpg",   2410000, "Kodachrome", false],
    ["Studio logo.png",      "logo.png",       6537,  "Vector-ish", false],
    ["Badge concept.svg",    "badge.svg",        722,  "Drafts",     false],
    ["Loading test.gif",     "spinner.gif",   42662,  "Scratch",    true],
    ["Harbour at dawn.jpg",  "photo.jpg",   2380000, "Kodachrome", false],
    ["Logo on dark.png",     "logo.png",       6537,  "Vector-ish", false],
    ["Badge, second go.svg", "badge.svg",        722,  "Drafts",     false],
    [".thumbs cache.gif",    "spinner.gif",   42662,  "Scratch",    true],
    ["Jetty.jpg",            "photo.jpg",   2205000, "Kodachrome", false],
    ["Logo outline.png",     "logo.png",       6537,  "Drafts",     false]]
    Shots.Push({Name: s[1], Kind: "file", Size: s[3], Roll: s[4], Hidden: s[5],
                Image: A_ScriptDir "\assets\" s[2],
                Modified: FormatTime(DateAdd(A_Now, -A_Index * 3, "Days"), "yyyyMMddHHmmss")})

Photos := AxFileState({
    Name: "photos", Mode: "thumbs", IconSize: 96, Checkboxes: true,
    Source: AxFileVirtual([{Name: "Rolls", Kind: "folder", Children: Shots}],
                          {Label: "Pictures", Icon: "EB9F", Sep: "/"}),
    Path: "Rolls",
    Columns: [{Key: "name", Title: "Name", Width: 240, Render: "name", Hideable: false},
              {Key: "roll", Title: "Roll", Width: 140},
              {Key: "modified", Title: "Taken", Width: 150, Render: "date"},
              {Key: "size", Title: "Size", Width: 90, Render: "size", Align: "right", Sort: "number"}]})

Section("Pick a shape", "Tick boxes are on here: click the corner of a picture to tick it, or press space. "
    . "Ticking is not selecting — you tick a set to act on and you select to look at — and OnCheck and "
    . "OnSelect are two events.")

g.AddFileTools("Fill State=photos")
g.AddFileView("Fill h300 State=photos Top=8")
g.AddFileStatus("Fill State=photos Top=6")

g.AddText("", "Icon size")
g.AddSlider("x+10 w200 vphotoSize Range24-200", 96).OnChange((c, v, *) => Photos.IconSize(v))
g.AddButton("x+16", "Hidden items").OnClick((*) => Photos.Toggle("hidden"))
g.AddButton("x+6", "Group by roll").OnClick((*) => Photos.SetGroup(Photos.Group = "" ? "roll" : ""))
g.AddButton("x+6", "Tick them all").OnClick((*) => Photos.CheckAll(true))
g.AddButton("x+6", "What is ticked?").OnClick((*) => LogLine("Ticked: " Names(Photos.Checked())))
g.AddText("Hint", "Two of these are hidden. Turn hidden items on and they appear, greyed — the same flag the "
    . "disk sets, and here just a property on a made-up item.")
g.Use()

Photos.OnCheck((items, st) => LogLine(items.Length " ticked"))


; ─────────────────────────────────────────────────────────────────────────────
;  Page 5 — the real drives
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("drives", "This PC", "E977")

Lead("AxFileLocal with no root starts at the drives, and a drive item carries its label, its capacity and "
   . "how full it is. Those are properties like any others, so the free-space bar is a column and not a "
   . "special case.")

Drives := AxFileState({
    Name: "drives", Source: AxFileLocal(),
    Columns: [
        {Key: "name",  Title: "Drive", Width: 90, Render: "name", Hideable: false},
        {Key: "label", Title: "Name",  Width: 160},
        {Key: "type",  Title: "Kind",  Width: 130},
        {Key: "used",  Title: "Space used", Width: 240, Render: "bar", Max: 100, Sort: "number",
         Format: (v, it, st) => it.Total ? (AxWindow.FileSize(it.Total - it.Free) " of " AxWindow.FileSize(it.Total)) : "—",
         Color:  (v, it, st) => (v >= 90) ? "#e57373" : (v >= 75) ? "#ffb74d" : ""},
        {Key: "free",  Title: "Free", Width: 110, Render: "size", Align: "right", Sort: "number"}]})

Section("Every drive on this machine", "Real numbers, read once when the page was built. Double-click one to "
    . "go into it — the same view, the same state, now listing folders.")
g.AddFileView("Fill h240 State=drives")
g.AddButton("", "Read them again").OnClick((*) => Drives.Refresh())
g.AddButton("x+8", "Back to the drives").OnClick((*) => Drives.Home())
g.AddText("Hint", "A bar column over 90% turns red because Color is a function of the value. Nothing polls; "
    . "Refresh re-reads.")
g.Use()


; ─────────────────────────────────────────────────────────────────────────────
;  Page 6 — the registry
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("registry", "Registry", "E713")

Lead("The registry is a tree of things with names, which is all a source has to be. Keys list as folders and "
   . "values as files, with the value's type in the Type column and its data in the preview. This reads and "
   . "never writes.")

Reg := AxFileState({
    Name: "reg", Source: AxFileReg(),
    Columns: [
        {Key: "name", Title: "Name", Width: 260, Render: "name", Hideable: false},
        {Key: "type", Title: "Type", Width: 140},
        {Key: "data", Title: "Data", Width: 420,
         Format: (v, it, st) => (String(v) = "") ? "" : SubStr(StrReplace(String(v), "`n", " "), 1, 200)}]})

Section("Have a look round", "Start at HKCU and work down. The path bar's chevrons drop the keys beside the "
    . "one you are on, so you can step sideways from halfway along the trail; click the empty stretch after "
    . "the last step and type a path instead.")

g.AddFileExplorer("Fill h400 Preview=280", Reg)
g.AddButton("", "HKCU\\Software").OnClick((*) => Reg.Go("HKEY_CURRENT_USER\Software"))
g.AddButton("x+8", "Run at startup").OnClick((*) =>
    Reg.Go("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run"))
g.AddButton("x+8", "Back to the hives").OnClick((*) => Reg.Home())
g.AddText("Hint", "A value's path carries a doubled backslash before its name, so a key called Run and a "
    . "value called Run under the same parent stay apart.")
g.Use()


; ─────────────────────────────────────────────────────────────────────────────
;  Page 7 — inside an archive
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("archive", "Archive", "F012")

Lead("AxFileZip walks a .zip once through Shell.Application and keeps the result as a map of paths, so "
   . "listing a folder inside it is a lookup. Reading one entry copies it to a temp folder, because the shell "
   . "has no other way in — which is fine for a preview and not for a hundred files.")

Zip := AxFileState({Name: "zip", Source: AxFileVirtual([], {Label: "No archive open", Icon: "F012"}),
                    Empty: "Choose a .zip above and it will be listed here."})

Section("Open one and look inside", "Pick any .zip on this machine. The view, the tree, the crumbs and the "
    . "preview do not change at all — only what the state's source is.")

g.AddButton("", "Choose a .zip…").OnClick((*) => OpenZip())
g.AddButton("x+8", "Close it").OnClick((*) =>
    Zip.SetSource(AxFileVirtual([], {Label: "No archive open", Icon: "F012"})))
g.AddFileExplorer("Fill h360 Top=10 Preview=280", Zip)
g.AddText("Hint", "The same six parts, the same state, a different source. That is the whole trick.")
g.Use()

OpenZip() {
    f := ""
    try f := FileSelect(3, , "Choose an archive", "Archives (*.zip)")
    if (f = "")
        return
    Zip.SetSource(AxFileZip(f))
    LogLine("Opened " f)
}


; ─────────────────────────────────────────────────────────────────────────────
;  Page 8 — writing your own
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("own", "Your own", "E943")

Lead("Two extension points, both used below and both in this file. A source answers a handful of questions "
   . "about a tree of things that have names; a preview renderer says which items it will take and draws "
   . "them. Neither needs a line changed anywhere else.")

; A drive that is not on this machine, or on any other. Some of its files are
; "online only" -- a property the source invented, which a column draws and a
; preview renderer reacts to.
Cloud := AxFileVirtual([
    {Name: "Shared with me", Kind: "folder", Icon: "E902", Children: [
        {Name: "Q3 numbers.xlsx", Size: 88200, Owner: "Priya", Online: true,  Sync: 100},
        {Name: "Launch plan.docx", Size: 41900, Owner: "Sam",  Online: false, Sync: 100},
        {Name: "Budget draft.xlsx", Size: 22400, Owner: "Priya", Online: true, Sync: 40}]},
    {Name: "Photos", Kind: "folder", Children: [
        {Name: "Rooftop.jpg", Size: 3100000, Owner: "me", Online: false, Sync: 100,
         Image: A_ScriptDir "\assets\photo.jpg"},
        {Name: "Team.png", Size: 812000, Owner: "me", Online: true, Sync: 0,
         Image: A_ScriptDir "\assets\logo.png"}]},
    {Name: "Notes.md", Size: 1820, Owner: "me", Online: false, Sync: 100,
     Text: "# Notes`n`nThis file is not on any disk. Its text is a property of the item,`nand the built-in "
         . "text renderer shows it because the source answered`nRead() with something.`n`n- a source is a "
         . "tree of things with names`n- a preview renderer is a match and a draw`n"}],
    {Label: "Cloud drive", Icon: "E753", Sep: "/",
     Caps: {Rename: false, Delete: false, NewFolder: false, Drop: false, Write: false, Thumbs: true}})

; A preview renderer of our own. It is asked before the built-in ones because
; its order is lower, and it only takes the files that are online only.
AxFilePreview.Register("online",
    (it, st) => (it.HasOwnProp("Online") && it.Online),
    (it, st, w) => '<div class="fpv-big"><span class="ico">&#xE753;</span></div>'
                 . '<div class="fpv-sum">Online only — ' AxWindow._Esc(it.Name) ' is not on this machine.</div>'
                 . '<div class="fpv-sum">Owned by ' AxWindow._Esc(it.Owner) '</div>'
                 . AxFilePreview.Facts(it, st),
    20)

Sky := AxFileState({
    Name: "cloud", Source: Cloud,
    Columns: [
        {Key: "name",  Title: "Name", Width: 210, Render: "name", Hideable: false},
        {Key: "owner", Title: "Owner", Width: 110},
        {Key: "online", Title: "Where", Width: 130, Render: "icon",
         Value: (it, st) => (it.HasOwnProp("Online") && it.Online) ? "E753" : "E73E"},
        {Key: "sync",  Title: "Downloaded", Width: 160, Render: "progress", Max: 100, Sort: "number"},
        {Key: "size",  Title: "Size", Width: 90, Render: "size", Align: "right", Sort: "number"}]})

Section("A source written here", "Owner, Online and Sync are not things a file has — they are properties this "
    . "source put on its items, and columns read them like any other. Notes.md has Text, so the built-in text "
    . "renderer previews it without being told to.")

g.AddFileExplorer("Fill h340 Preview=300", Sky)
g.AddText("Hint", "Open one of the files marked with the cloud glyph: the preview renderer registered above "
    . "takes it, because it said it would and its order is lower than the built-in ones.")
g.Use()

Section("What the whole contract is", "A source needs List(path) and, if its paths are not separated the way "
    . "the default expects, Parent and Join. Everything else has a sensible version already.")
g.AddText("Caption Fill",
      "List(path) → items    ·    Item(path) → one    ·    Parent(path)    ·    Join(path, name)`n"
    . "Crumbs(path) → the trail    ·    Branches(path) → the folders, for the tree`n"
    . "Read(path, max) → text for the preview    ·    Thumb(item) → a URL for a picture`n"
    . "Exists(path)    ·    Refresh(path)    ·    Caps, Scheme, Label, Icon, Sep, RootPath`n`n"
    . "An item: Key, Name, Path, Kind, Icon, Size, Modified, Type, Hidden, Kids, Data — plus anything else "
    . "you want a column to show.")
g.Use()


; ─────────────────────────────────────────────────────────────────────────────
;  Page 9 — the log
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("log", "What happened", "E756")

Lead("Every event the pages above raised, as it happened. These are the state's events, and there is nothing "
   . "in them about HTML.")

Section("Events", "OnPath, OnItems, OnSelect, OnActivate, OnCheck, OnEdit, OnDrop, OnMenu and OnError.")
logBox := g.AddEdit("vlogBox Fill Multi Rows=18 ReadOnly Style=font-family:Consolas,monospace;font-size:12px", "")
g.AddButton("", "Clear").OnClick((*) => ClearLog())
g.Use()


; ─────────────────────────────────────────────────────────────────────────────

; ─────────────────────────────────────────────────────────────────────────────
;  Page 10 — the look
; ─────────────────────────────────────────────────────────────────────────────

g.AddPage("look", "Look", "E790")

Lead("The same nine pages under every stylesheet the library ships and both "
   . "themes. Change it here and go back to any page: the file view, the tree, "
   . "the breadcrumbs, the preview and the places list are all drawn by the "
   . "theme, so none of them needs to know which one is on.")

Section("Theme", "Dark, light, or whatever Windows is set to.")
g.AddSegmented("vtheme Choose1", "dark:Dark|light:Light|system:Follow Windows")
    .OnChange((c, v, *) => (g.SetTheme(v), LogLine("Theme: " v)))
g.Use()

Section("Stylesheet", "Twelve of them. Each one restyles every control on every "
    . "page; the components only say what shape they are.")
g.AddSegmented("vsheet1 Choose1", "win11:Windows 11|win365:365|winxp:XP|win98:98")
    .OnChange((c, v, *) => (g.SetStylesheet(v), LogLine("Stylesheet: " v)))
g.AddSegmented("vsheet2", "cozy:Cozy|cyber:Cyber|brutalist:Brutalist|aurora:Aurora")
    .OnChange((c, v, *) => (g.SetStylesheet(v), LogLine("Stylesheet: " v)))
g.AddSegmented("vsheet3", "inset:Inset|precision:Precision|instrument:Instrument|rpg:RPG")
    .OnChange((c, v, *) => (g.SetStylesheet(v), LogLine("Stylesheet: " v)))
g.Use()

Section("Accent", "One colour, everywhere it means something: the tick boxes, "
    . "the bars, the focus ring, the selected row.")
g.AddPalette("vaccent", "#60cdff|#e8b44a|#7bd88f|#c27bdb|#e57373|#4fc3f7|#ffb74d")
    .OnChange((c, v, *) => (g.SetAccent(v), LogLine("Accent: " v)))
g.AddButton("Top=10", "Back to the default").OnClick((*) => (g.SetAccent(""), LogLine("Accent: default")))
g.AddText("Hint", "Tick a few files on the Five views page, then come back here and "
    . "try light mode: a tick box has to read on both, and against a photograph.")
g.Use()

g.AddStatusBar([{Id: "where", Text: "Ten pages, one component", Icon: "EC50", Grow: true},
                {Id: "theme", Text: "Dark", Width: 90}])

g.OnReady((w) => (logBox.Value := LogText, LogLine("Ready.")))
g.Show()
