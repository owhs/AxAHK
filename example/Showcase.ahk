#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes/icons (single-file exe)
#Include ..\lib\AxRichAll.ahk
#Include ..\lib\AxAssets.ahk

; ==============================================================================
;  Showcase.ahk — every component, built from AutoHotkey alone.
;  No HTML, CSS or JS written here; the page is generated in memory and
;  loaded from a string (see lib/AxGui.ahk). Same shape as the native Gui.
;
;  Every page has the same shape: one line on what it is about, then one
;  titled card per thing it shows -- a heading, a line on what to try, the
;  control itself, and a hint where there is more to know. Section() opens
;  such a card and g.Use() closes it.
;
;    Home               the pages, and this window's own settings
;    Buttons & choices  buttons, toggles, segmented, rating, chips, lists
;    Text & forms       a form, numbers and sliders, tags, hotkeys
;    Dates & time       date, time, month and range boxes; the calendar
;    Lists & trees      the data view as a list, a tree and groups; Gui's own
;    Layout             cards, rows, group boxes, expanders, tabs, splitters
;    Status             stat cards, gauges, progress, info bars, avatars
;    Images & media     images, pictures, SVG, thumbnails, an ActiveX control
;    Drag & drop        drop zones, file lists, things dragged into order
;    Menus & dialogs    dialogs, notifications, toasts, context menus, clicks
;    Personalization    theme, stylesheet, accent, tint, colour pickers
;    Editors            a code editor and a rich text editor
;    Console            everything that happened
; ==============================================================================

; ------------------------------------------------------------------------------
; Window
; ------------------------------------------------------------------------------

g := AxGui({
    Title:     "AxAHK Showcase",
    AppName:   "AxAHK Showcase",
    Width:     1040,
    Height:    760,
    MinWidth:  640,
    MinHeight: 420,
    BackColor: "202020",
    Theme:     "dark"
})

; Nothing to call: including AxInspector registers F12 / Ctrl+Shift+I for
; every AxWindow in the script. Attach(g) still works if a window should be
; inspected from the moment it opens.

; ------------------------------------------------------------------------------
; State & helpers
; ------------------------------------------------------------------------------

LogLines := 0

Log(msg) {
    global logBox, LogLines
    if (!g.Ready)
        return
    g.Append(logBox.Id, '<div>[' FormatTime(, "HH:mm:ss") '] ' AxWindow._Esc(msg) '</div>')
    logBox.El.scrollTop := logBox.El.scrollHeight
    g.Text("logCount", ++LogLines)
}

Join(arr, sep := ", ") {
    s := ""
    for v in arr
        s .= (s = "" ? "" : sep) v
    return s
}

Names(rows) {
    out := []
    for r in rows
        out.Push(r.name)
    return out
}

; One titled card per demo: its heading, a line on what to try, then whatever
; is added next. g.Use() closes it; the card is handed back so a demo that
; opens boxes of its own can step back into it with sec.Use().
Section(title, about := "") {
    c := g.AddCard("y+6", title)
    if (about != "")
        g.AddText("Caption Fill", about)
    return c
}

; the thin rule between setting rows that share one card
Rule() => g.AddSeparator('Style="margin:10px 0 0"')

; the line under a page's title
Lead(text) => g.AddText("Fill", text)

ShowNotifyResult(arg, label) {
    if (arg = "body" || arg = "") {
        g.Dialog("You clicked the notification body.`nNo button was pressed.",
            "Notification clicked", ["OK"], {Kind: "info"})
    } else {
        kind := (arg = "delete" ? "warning" : arg = "keep" ? "info" : "success")
        g.Dialog("You clicked `'" label "'` (argument: " arg ").`n`n"
            . "This rich dialog is the in-UI result that follows the Windows toast.",
            "Notification result: " label, ["OK"], {Kind: kind})
    }
    Log("Notify click -> " arg " / " label)
}

ShowNotifyDismiss(reason) {
    g.Dialog("The notification was dismissed.`nReason: " reason ".`n(no button was pressed)",
        "Notification dismissed", ["OK"], {Kind: "info"})
    Log("Notify dismiss -> " reason)
}

; ------------------------------------------------------------------------------
; Window bars — standard chrome, so they are declared on the Gui rather than
; on a page: the menu bar sits under the title bar and the status bar along
; the bottom, and #shell gives up exactly their height.
; ------------------------------------------------------------------------------

Sheets := [["win11", "Windows 11"], ["win98", "Windows 98"], ["winxp", "Windows XP"],
           ["win365", "Windows 365"], ["cyber", "Cyber"], ["rpg", "RPG"], ["cozy", "Cozy"],
           ["aurora", "Aurora"], ["instrument", "Instrument"], ["precision", "Precision"],
           ["inset", "Modern Inset"], ["brutalist", "Brutalist"]]

g.AddMenuBar([
    {Title: "&File", Items: [
        ["&New window", (*) => g.Toast("Pretend a new window opened", 2000)],
        ["&Open…", (*) => g.Toast("Nothing to open in a demo", 2000)],
        "-",
        {Label: "&Launch Notepad", Shortcut: "Ctrl+N", Click: (*) => Run("notepad.exe")},
        "-",
        {Label: "E&xit", Shortcut: "Alt+F4", Click: (*) => g.Close()}]},
    {Title: "&View", Items: () => [
        {Label: "&Go to page", Icon: "E8A5", Items: PageMenu()},
        "-",
        {Label: "&Always on top", Checked: g.HasOwnProp("_onTop") && g._onTop,
            Click: (*) => ToggleOnTop()},
        {Label: "&Toggle maximize", Shortcut: "F11", Click: (*) => g.ToggleMaximize()}]},
    ; Items given as a function are rebuilt every time the menu opens, so the
    ; ticks always show what is actually current
    {Title: "&Theme", Items: () => [
        {Label: "&Dark",   Radio: true, Checked: g.Theme = "dark",  Click: (*) => g.SetTheme("dark")},
        {Label: "&Light",  Radio: true, Checked: g.Theme = "light", Click: (*) => g.SetTheme("light")},
        {Label: "&System", Radio: true, Checked: false,             Click: (*) => g.SetTheme("system")},
        "-",
        {Label: "&Stylesheet", Icon: "E790", Items: SheetMenu},
        "-",
        {Label: "Show the &menu bar", Checked: g.MenuBarPinned,
            Click: (*) => SetReveal(g.MenuBarPinned ? "alt" : "always")}]},
    {Title: "&Help", Items: [
        ["&About", (*) => g.Alert("AHK2 ActiveX GUI`n`nA borderless window whose look is HTML "
            . "and CSS, and whose behaviour is AutoHotkey.", "About")]]}])

g.AddStatusBar([
    {Id: "msg",   Text: "Ready", Icon: "E930", Grow: true},
    {Id: "job",   Text: "", Width: 150},
    {Id: "page",  Text: "home", Width: 110, Dim: true},
    {Id: "clock", Text: "--:--:--", Width: 78, Tip: "The same timer that drives the Home clock"},
    {Id: "hint",  Text: "Tap Alt", Width: 90, Dim: true,
        Click: (part, w) => w.Toast("Tap Alt to hide or show the menu bar", 2600)}])

; the pages, in the sidebar's order, for the View menu and the Home tiles
Pages := [
    ["controls", "Buttons & choices", "E771", "Buttons, toggles, chips, lists"],
    ["forms",    "Text & forms",      "E8A5", "Fields, tags, sliders, keys"],
    ["dates",    "Dates & time",      "E787", "Boxes, a calendar, ranges"],
    ["data",     "Lists & trees",     "E9D5", "Sort, filter, tick, group"],
    ["layout",   "Layout",            "E8A9", "Cards, tabs, splitters"],
    ["status",   "Status",            "EB05", "Stats, dials, progress, people"],
    ["media",    "Images & media",    "EB9F", "Pictures, SVG, ActiveX"],
    ["drop",     "Drag & drop",       "E896", "Files in, items into order"],
    ["dialogs",  "Menus & dialogs",   "E8BD", "Dialogs, toasts, menus"],
    ["theme",    "Personalization",   "E790", "Theme, accent, colours"],
    ["editors",  "Editors",           "E943", "Code and rich text"],
    ["console",  "Console",           "E756", "Everything that happened"]]

PageMenu() {
    items := [{Label: "&Home", Radio: true, Checked: g.CurrentPage = "home", Click: GoPage("home")}]
    for p in Pages
        items.Push({Label: StrReplace(p[2], "&", "&&"), Radio: true, Checked: g.CurrentPage = p[1],
                    Click: GoPage(p[1])})
    return items
}
GoPage(id) => (*) => g.ShowPage(id)

SheetMenu() {
    items := []
    for s in Sheets
        items.Push({Label: s[2], Radio: true, Checked: SheetIs(s[1]), Click: SheetFn(s[1])})
    return items
}
SheetFn(name) => (*) => SetSheet(name)

ToggleOnTop() {
    g._onTop := !(g.HasOwnProp("_onTop") && g._onTop)
    g.AlwaysOnTop(g._onTop)
    try g.Value("swAOT", g._onTop)
    g.Status("msg", g._onTop ? "Always on top" : "Ready")
    Log("Always on top: " (g._onTop ? "ON" : "OFF"))
}

SheetIs(name) => AxGui.SheetName(g.HasOwnProp("Stylesheet") ? g.Stylesheet : "win11") = name

CurrentSheet := "win11"
SetSheet(name) {
    global CurrentSheet
    if (name = CurrentSheet)
        return
    CurrentSheet := name
    g.SetStylesheet(name)
    try g.Value("ddSheet", name)             ; the menu and the dropdown stay in step
    SyncSchemes()
    Log("Stylesheet -> " name)
}
; the classic schemes are only meaningful on win98, so the picker follows the
; stylesheet: live there, greyed out everywhere else, and the layer is dropped
; so it cannot leak onto another sheet
SyncSchemes() {
    on := (AxGui.SheetName(g.Stylesheet) = "win98")
    try g.Ctl("scheme").Enabled := on
    try g.Text("schemeHint", on ? "Pick a scheme to repaint the Classic chrome."
                                : "Only on the Windows 98 stylesheet.")
    if on
        SetScheme(g.Value("scheme"))
    else
        g.SetExtraCss("scheme", "")
}

SetReveal(mode) {
    g.ShowMenuBar(mode = "always")
    g.Value("rgMenuBar", mode)
    g.Status("hint", mode = "alt" ? "Tap Alt" : "")
    Log("Menu bar -> " (mode = "always" ? "always visible" : "hidden until Alt"))
}


; ==============================================================================
; Home
; ==============================================================================

g.AddPage("home", "Home", "E80F")

Lead("A borderless window whose look is HTML and CSS and whose behaviour is AutoHotkey. "
    . "Every control in it was made from AutoHotkey with AxGui.Add*(), the way a Gui is built.")

Section("Explore", "Click a tile to open its page — or drag one to put it somewhere else.")
g.AddGrid("vgridHome")
for p in Pages
    g.AddTile('vgo_' p[1] ' w170 Value=' p[1] ' Icon=' p[3] ' Desc="' p[4] '"', p[2])
        .OnClick(GoPage(p[1]))
g.Use()

sec := Section("This window")
g.AddRow("NoCard Icon=E718", "Always on top", "WinSetAlwaysOnTop, from a toggle switch")
g.AddSwitch("vswAOT")
    .OnChange((c, v, *) => (g._onTop := v, g.AlwaysOnTop(v), Log("Always on top: " (v ? "ON" : "OFF"))))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E700", "Menu bar", "Always there, or tucked away until Alt is tapped")
g.AddRadio("vrgMenuBar Choose1", "always:Always|alt:After Alt")
    .OnChange((c, v, *) => SetReveal(v))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E823", "Live clock", "Pushed from an AHK SetTimer every second")
clock := g.AddText("vlblClock", "--:--:--")
sec.Use()
Rule()
g.AddRow("NoCard Icon=E8EF", "Counter", "The number lives in AHK; the page only shows it")
g.AddButton("Icon", "−")
    .OnClick((*) => SetCounter(-1))
counterText := g.AddText("vcounterValue x+8 w48 Center", "0")
g.AddButton("Icon x+8", "+")
    .OnClick((*) => SetCounter(1))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E756", "Launch Notepad", "Run(), from a button on the page")
g.AddButton('vbtnNotepad Accent Tip="Runs notepad.exe"', "Launch")
    .OnClick((*) => (Run("notepad.exe"), g.Toast("Notepad launched.", 2000, "success")))
sec.Use()
g.AddText("Hint", "Hover the maximize button for Snap Layouts, double-click the title bar to maximize, "
    . "and drag any edge to resize — the status bar's grip is the bottom-right corner.")
g.Use()

Counter := 0
SetCounter(delta) {
    global Counter += delta
    counterText.Text := Counter
}


; ==============================================================================
; Buttons & choices
; ==============================================================================

g.AddPage("controls", "Buttons & choices", "E771")

Lead("The controls you click and pick with. Every handler below is an AutoHotkey function, "
    . "and what each one did is written to the Console.")

Section("Buttons", "Five kinds, an icon button and a hyperlink; each click is an OnClick in AHK.")
g.AddButton("", "Standard")
    .OnClick((*) => g.Toast("Standard button"))
g.AddButton("x+8 Accent", "Accent")
    .OnClick((*) => g.Toast("Accent button", 2000, "success"))
g.AddButton("x+8 Subtle", "Subtle")
    .OnClick((*) => g.Toast("Subtle button"))
g.AddButton("x+8 Danger", "Danger")
    .OnClick((*) => g.Toast("Danger button", 2000, "error"))
g.AddButton("x+8 Disabled", "Disabled")
g.AddButton('x+8 Icon Icon=E713 Tip="An icon button"', "")
    .OnClick((*) => g.Toast("Icon button"))
g.AddLink("x+16", "Hyperlink button")
    .OnClick((*) => Log("Hyperlink clicked"))
g.Use()

Section("Toggles", "A switch, check boxes and a radio group; Change hands AHK the new value.")
g.AddSwitch("vswDemo Checked")
    .OnChange((c, v, *) => Log("Switch -> " (v ? "On" : "Off")))
g.AddCheckBox("x+24 vchkDemo Checked", "Enable notifications")
    .OnChange((c, v, *) => Log("Checkbox -> " v))
g.AddCheckBox("x+16", "Use system sound")
g.AddRadio("vrgSize Choose2", "small:Small|default:Default|large:Large")
    .OnChange((c, v, *) => Log("Radio -> " v))
g.Use()

Section("Segmented control and rating", "One of a few, as a strip of buttons; and stars, with the value beside them.")
g.AddSegmented("vsegView Choose1", "grid:Grid:E80A|list:List:E8FD|details:Details:E9D5")
    .OnChange((c, v, *) => Log("View -> " v))
g.AddRating("x+32 vrateDemo out=rateOut", 3)
    .OnChange((c, v, *) => Log("Rating -> " v))
g.AddText("vrateOut x+8 Caption", "3")
g.Use()

Section("Chips", "Click one to switch it on or off — a filter bar is a row of these.")
for i, n in ["Documents", "Pictures", "Music", "Video", "Archives"]
    g.AddChip((i = 1 ? "On" : "x+8"), n)
        .OnClick((c, *) => (g.ToggleClass(c.Id, "on"), Log("Chip -> " c.Text)))
g.Use()

Section("Pick from a list", "A dropdown (AddDDL — or AddDropDownList and AddComboBox, Gui's own names) and a list box.")
g.AddText("w90", "User role")
g.AddDDL("vddRole x+8 w180 Choose1", "admin:Administrator|editor:Editor|viewer:Viewer")
    .OnChange((c, v, *) => Log("Role -> " v))
g.AddText("x+32 w70", "Text size")
g.AddDropDownList("vddSize x+8 w150 Choose1", "auto:Auto|small:Small|default:Default|large:Large|125:Custom 125%")
    .OnChange((c, v, *) => Log("Text size -> " v))
lst := g.AddListBox("vlstLang w300 Choose1",
    "en-US:English (US)|en-GB:English (UK)|es:Español|de:Deutsch|fr:Français")
lstOut := g.AddText("x+24 Hint", "Selected: en-US")
lst.OnChange((c, v, *) => (lstOut.Text := "Selected: " v, Log("Language -> " v)))
g.Use()


; ==============================================================================
; Text & forms
; ==============================================================================

g.AddPage("forms", "Text & forms", "E8A5")

Lead("Boxes to type into: a whole settings form, numbers and sliders, tags, and a box that records a hotkey.")

form := Section("A settings form", "Group boxes around labelled fields: text, a password, suggestions, a date, "
    . "a number, radio buttons and switches — and Apply at the end.")
g.AddGroupBox("", "Profile")
g.AddText("w140", "Name")
profile := g.AddEdit("vtxtProfile x+8 Fill", "Jane Doe")
g.AddText("w140", "Password")
g.AddPassword("vtxtPass x+8 Fill", "hunter2hunter2")
g.AddText("w140", "Search")
g.AddSearch('vtxtSearch x+8 Fill Placeholder="Search your files"')
g.AddText("w140", "City")
g.AddAutoComplete('vacCity x+8 Fill placeholder="Suggestions as you type; any text is fine"',
    "London|Paris|Berlin|Madrid|Rome|Lisbon|Vienna|Prague|Dublin|Oslo")
    .OnChange((c, v, *) => Log("City -> " v))
g.AddText("w140", "Country")
g.AddAutoComplete('vacCountry x+8 Fill Strict placeholder="Strict: only a listed country sticks"',
    "gb:United Kingdom|fr:France|de:Germany|es:Spain|it:Italy|pt:Portugal|at:Austria|cz:Czechia|ie:Ireland|no:Norway")
    .OnChange((c, v, *) => Log("Country -> " (v = "" ? "(cleared)" : v)))
g.AddText("w140", "Start date")
g.AddDate('vdtStart x+8 Placeholder="Type a date or pick one"', "today")
    .OnChange((c, v, *) => Log("Start date -> " (v = "" ? "(cleared)" : v)))
g.AddText("x+12 Hint", "try “next mon” or “+2w”")
g.AddText("w140", "Notes")
notes := g.AddEdit("vtxtNotes x+8 Fill Rows=3", "Type here — AHK reads every keystroke.")
g.AddText("w140", "")
preview := g.AddText("vpreviewLabel x+8 Hint", "")
notes.OnEvent("KeyUp", (c, ev, el) => preview.Text := StrLen(el.value) " characters")
profile.OnEvent("KeyUp", (c, ev, el) => preview.Text := "Profile: " el.value)
form.Use()                                  ; out of the group box, still in the card
g.AddGroupBox("", "Region")
region := g.AddRadio("vrgRegion Vertical Choose1",
    "en-US:English (US)|en-GB:English (UK)|es-ES:Español (ES)")
region.OnChange((c, v, *) => Log("Region -> " v))
form.Use()
g.AddGroupBox("", "Display")
g.AddText("w140", "Scale")
scale := g.AddNumber('vnbScale x+8 Min=100 Max=300 Step=25 BigStep=50 SmallStep=5 Suffix="%"', 150)
g.AddText("w140", "Window shadows")
g.AddSwitch("x+8 Checked")
g.AddText("w140", "Animations")
g.AddSwitch("x+8 Checked")
form.Use()
g.AddButton("Accent", "Apply")
    .OnClick((*) => (
        Log("Apply: profile=" profile.Value " scale=" scale.Value " region=" region.Value
            . " start=" g.Value("dtStart")),
        g.Toast("Settings applied", 2000, "success")))
g.AddButton("x+8", "Restore defaults")
    .OnClick((*) => (profile.Value := "Jane Doe", scale.Value := 150, g.Toast("Defaults restored")))
g.AddButton("x+8 Subtle", "Cancel")
    .OnClick((*) => g.Toast("Cancelled"))
g.Use()

sec := Section("Numbers and ranges")
g.AddRow("NoCard Icon=E81C", "Refresh every", "Up and Down step 5; with Shift 30, with Ctrl 1 — or type it")
g.AddNumber('vnbInterval Min=1 Max=120 Step=5 BigStep=30 SmallStep=1 Suffix=" min"', 15)
    .OnChange((c, v, *) => Log("Interval -> " v " min"))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E767", "Volume", "A slider, with its value beside it")
g.AddSlider('vslVolume w240 Suffix="%"', 75)
    .OnChange((c, v, *) => Log("Volume -> " v "%"))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E9E9", "Price range", "Two thumbs: drag either, or press the track and the nearer one jumps")
g.AddRangeSlider("vrsPrice w240 Min=0 Max=1000 Step=10 Prefix=$", "200,750")
    .OnChange((c, v, *) => Log("Price range -> $" StrReplace(v, ",", " to $")))
g.Use()

Section("Tags", "Each tag is a chip. Double-click one to edit it; paste a list and every item becomes a chip; "
    . "Ctrl+A in the empty box takes them all, then Ctrl+C copies them as a comma list.")
g.AddText("w100", "Labels")
g.AddTags('vtagsDemo x+8 Fill Clear Placeholder="Add a label" '
    . 'Suggest="bug|feature|docs|design|urgent|question|help wanted"', "feature|design")
    .OnChange((c, v, *) => TagsSay("Labels", v))
g.AddText("w100", "Keywords")
g.AddTags('vtagsWords x+8 Fill Clear Split="comma space" Placeholder="A space or a comma ends each one"',
    "fast|small|native")
    .OnChange((c, v, *) => TagsSay("Keywords", v))
g.AddText("w100", "")
g.AddButton("x+8 Icon=E8C8", "Put a list on the clipboard")
    .OnClick((*) => (A_Clipboard := "apples, pears`nplums; cherries`tfigs",
        g.Toast("On the clipboard — now paste it into either box", 2600)))
g.AddButton("x+8", "Copy the labels")
    .OnClick((*) => (A_Clipboard := g.Ctl("tagsDemo").Component.ToText(),
        g.Toast("Copied: " A_Clipboard, 2600, "success")))
g.AddText("Hint", "Split= says what ends a tag as you type (Split=" Chr(34) "comma space" Chr(34)
    . " on the second box); pasted text is cut at those, commas, semicolons, tabs and new lines. "
    . "Clear adds the x at the end of the box. The value is one string, the tags joined by |.")
g.Use()

TagsSay(what, v) => Log(what " -> " (v = "" ? "(none)" : StrReplace(v, "|", ", ")))

Section("Hotkey box", "Click it and press a combination; AHK binds it at once, and pressing it anywhere shows a toast.")
hk := g.AddHotkey("vhkDemo", "^!h")
hk.OnEvent("Hotkey", (c) => g.Toast("Hotkey " AxWindow.HotkeyDisplay(c.Value) " pressed", 2000, "success"))
hk.OnChange((c, v, *) => Log("Hotkey -> " (v = "" ? "(none)" : v)))
g.AddText("x+16 Hint", "Backspace or the x clears it, which unbinds it too.")
g.Use()


; ==============================================================================
; Dates & time
; ==============================================================================

g.AddPage("dates", "Dates & time", "E787")

Lead("One component in every shape a date takes. Values are ISO text (2026-09-12, 14:30, "
    . "2026-09-01/2026-09-12), so they sort, compare and save as they are.")

sec := Section("Date and time boxes", "Type into any of them — 12/9, 12 Sep, tomorrow, next fri, +3, -2w, 3pm — "
    . "or press Alt+Down for the calendar.")
g.AddRow("NoCard Icon=E787", "Due date", "A date")
g.AddDate("vdtDue", "+3")
    .OnChange((c, v, *) => DateSays("Due date", v))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E823", "Meeting", "A date and a time together")
g.AddDate("vdtMeet Mode=datetime", FormatTime(DateAdd(A_Now, 1, "Days"), "yyyy-MM-dd") " 14:30")
    .OnChange((c, v, *) => DateSays("Meeting", v))
sec.Use()
Rule()
g.AddRow("NoCard Icon=EF3C", "Alarm", "A time alone, in 15-minute steps, on a 12-hour clock")
g.AddTime("vdtAlarm Step=15 Hour12", "07:30")
    .OnChange((c, v, *) => DateSays("Alarm", v))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E8EF", "Billing month", "Mode=month: the calendar offers months, not days")
g.AddDate("vdtMonth Mode=month", FormatTime(, "yyyy-MM"))
    .OnChange((c, v, *) => DateSays("Billing month", v))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E8FB", "Booking", "Min and Max: nothing before today, nothing past 90 days")
g.AddDate('vdtBook Min=today Max=+90 Placeholder="Pick a day"')
    .OnChange((c, v, *) => DateSays("Booking", v))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E909", "Holiday", "A range: two months side by side, with Today, Last 7 days and the rest")
g.AddDateRange("vdtStay")
    .OnChange((c, v, *) => StaySays(v))
sec.Use()
stayOut := g.AddText("vstayOut Hint", "Pick a first and a last day; the count comes from ctl.Component.Days.")
g.Use()

Section("The calendar on the page", "AddCalendar is the same calendar the boxes open, as a control of its own; "
    . "Weeks puts the ISO week numbers down the side.")
g.AddCalendar("vcalDay Weeks", "today")
    .OnChange((c, v, *) => CalendarSays(v))
calOut := g.AddText("vcalOut x+32 w260", FormatTime(, "dddd, d MMMM yyyy") " — today")
g.Use()

Section("As a dialog", "When a window is wanted: g.PickDate() hands back the value, or nothing if it was cancelled.")
g.AddButton("Icon=E787", "Pick a date…")
    .OnClick((*) => PickDateSays({Mode: "date"}))
g.AddButton("x+8", "Pick a range…")
    .OnClick((*) => PickDateSays({Mode: "range"}))
g.AddButton("x+8", "Pick a time…")
    .OnClick((*) => PickDateSays({Mode: "time", Step: 30}))
pickOut := g.AddText("vpickOut x+16 Hint", "Nothing picked yet.")
g.Use()

; ISO text back to an AutoHotkey timestamp: 2026-09-12 -> 20260912000000
IsoStamp(v) => SubStr(RegExReplace(v, "\D") "00000000000000", 1, 14)

DateSays(what, v) {
    Log(what " -> " (v = "" ? "(cleared)" : v))
    g.Status("msg", what ": " (v = "" ? "none" : v))
}
StaySays(v) {
    days := g.Ctl("dtStay").Component.Days
    stayOut.Text := (v = "" || !days) ? "No range yet."
        : StrReplace(v, "/", " to ") "  ·  " days " day" (days = 1 ? "" : "s")
    Log("Holiday -> " (v = "" ? "(cleared)" : v))
}
CalendarSays(v) {
    if (v = "")
        return calOut.Text := "No day picked."
    ts := IsoStamp(v)
    n := DateDiff(ts, FormatTime(, "yyyyMMdd"), "Days")
    calOut.Text := FormatTime(ts, "dddd, d MMMM yyyy") " — "
        . (n = 0 ? "today" : n = 1 ? "tomorrow" : n = -1 ? "yesterday" : n > 0 ? "in " n " days" : -n " days ago")
    Log("Calendar -> " v)
}
PickDateSays(opts) {
    v := g.PickDate(opts)
    pickOut.Text := (v = "") ? "Cancelled." : "Picked " StrReplace(v, "/", " to ")
    Log("PickDate(" opts.Mode ") -> " (v = "" ? "(cancelled)" : v))
}


; ==============================================================================
; Lists & trees
; ==============================================================================

g.AddPage("data", "Lists & trees", "E9D5")

Lead("A flat list, a tree and a grouped list are one component, the data view, running one pipeline: "
    . "filter, sort, group, flatten, page, draw. Gui's own ListView and TreeView are drawn by it too.")

; One table of sample data drives the list and the grouped view.
FileRows := []
for r in [
    ["Quarterly report.docx", 184320, "Document", "2026-08-14"],
    ["Budget 2026.xlsx",      92160,  "Spreadsheet", "2026-09-01"],
    ["Roadmap.pptx",          2411724, "Slides",    "2026-07-30"],
    ["readme.md",             1240,   "Document",   "2026-09-06"],
    ["changelog.md",          8890,   "Document",   "2026-09-05"],
    ["notes.txt",             88,     "Document",   "2026-04-19"],
    ["contacts.csv",          15000,  "Spreadsheet", "2026-06-02"],
    ["photo-sunset.jpg",      2405000, "Picture",   "2026-08-22"],
    ["logo.png",              6537,   "Picture",    "2026-09-07"],
    ["banner.png",            140233, "Picture",    "2026-05-11"],
    ["icon.ico",              900,    "Picture",    "2026-01-08"],
    ["screencast.mp4",        99000000, "Video",    "2026-08-30"],
    ["interview.mp4",         51200000, "Video",    "2026-03-17"],
    ["theme.mp3",             4200000, "Audio",     "2026-02-25"],
    ["chime.wav",             120400, "Audio",      "2026-02-25"],
    ["Showcase.ahk",          33800,  "Script",     "2026-09-07"],
    ["AxWindow.ahk",          65180,  "Script",     "2026-09-07"],
    ["build.ps1",             3300,   "Script",     "2026-07-04"],
    ["deploy.bat",            120,    "Script",     "2026-07-04"],
    ["backup.7z",             734003200, "Archive",  "2026-06-28"],
    ["assets.zip",            18400000, "Archive",  "2026-05-30"],
    ["manual.pdf",            920000, "Document",   "2026-04-02"],
    ["licence.pdf",           41000,  "Document",   "2026-01-15"],
    ["config.json",           2100,   "Script",     "2026-09-03"]]
    FileRows.Push({Key: r[1], name: r[1], size: r[2], kind: r[3], date: r[4],
                   path: "C:\Work\\" r[3], Icon: AxWindow.FileGlyph(r[1])})

; the three views are all 680 wide, so their right edges line up
FileCols := [
    {Key: "name", Title: "Name", Width: 280, Icon: true, Hideable: false},
    {Key: "size", Title: "Size", Width: 100, Align: "right", Sort: "number",
        Format: (v, row) => AxWindow.FileSize(v)},
    {Key: "kind", Title: "Kind", Width: 140},
    {Key: "date", Title: "Modified", Width: 160},
    {Key: "path", Title: "Folder", Width: 150, Hidden: true}]      ; starts hidden

Section("List", "Click a header to sort; drag the edge between two headers to resize it, or double-click the edge "
    . "to fit; right-click the header (or Columns) to hide and show columns; Ctrl and Shift build a selection.")
files := g.AddDataView("vdvFiles h300 Checkboxes PageSize=8", {
    Columns: FileCols, Rows: FileRows, Sort: {Key: "name"},
    Empty: "No file matches that filter."})
dvOut := g.AddText("vdvOut Hint", "Nothing selected.")
g.AddButton("", "Tick all")
    .OnClick((*) => g.Ctl("dvFiles").Component.CheckAll(true))
g.AddButton("x+8", "Clear ticks")
    .OnClick((*) => g.Ctl("dvFiles").Component.CheckAll(false))
g.AddButton("x+8", "Ticked to console")
    .OnClick((*) => Log("Ticked: " (Join(g.Ctl("dvFiles").Component.CheckedKeys()) || "(none)")))
g.AddButton("x+8", "Select the pictures")
    .OnClick((*) => SelectPictures())
g.AddButton("", "Sort by size")
    .OnClick((*) => g.Ctl("dvFiles").Component.SortBy("size"))
g.AddButton("x+8", "Size columns to fit")
    .OnClick((*) => g.Ctl("dvFiles").Component.AutoSizeAll())
g.AddButton("x+8", "Toggle the Folder column")
    .OnClick((*) => g.Ctl("dvFiles").Component.ToggleColumn("path"))
g.AddText("Hint", "Click a row and the grid takes the keyboard: arrows and Home/End/PageUp/PageDown move, "
    . "Space ticks, Enter activates, Ctrl+A takes the page — or just start typing a name.")
g.Use()

SelectPictures() {
    keys := []
    for r in FileRows
        if (r.kind = "Picture")
            keys.Push(r.Key)
    g.Value("dvFiles", keys)
    Log("Selected " keys.Length " pictures through Value()")
}

Section("Tree", "A row with Children is a branch, and filtering opens the path to a hit. CheckTree makes a branch "
    . "tick everything under it; a part-ticked branch shows a dash.")
TreeRows := [
    {Key: "t_lib", name: "lib", kind: "Folder", Icon: "E8B7", Children: [
        {Key: "t_ax", name: "AxWindow.ahk", size: 65180, kind: "Script", date: "2026-09-07", Icon: "E943"},
        {Key: "t_gui", name: "AxGui.ahk", size: 34100, kind: "Script", date: "2026-09-07", Icon: "E943"},
        {Key: "t_themes", name: "themes", kind: "Folder", Icon: "E8B7", Children: [
            {Key: "t_w11", name: "win11.css", size: 30800, kind: "Stylesheet", date: "2026-09-07", Icon: "E943"},
            {Key: "t_w98", name: "win98.css", size: 24295, kind: "Stylesheet", date: "2026-09-07", Icon: "E943"},
            {Key: "t_wxp", name: "winxp.css", size: 24201, kind: "Stylesheet", date: "2026-09-07", Icon: "E943"}]},
        {Key: "t_rich", name: "rich", kind: "Folder", Icon: "E8B7", Children: [
            {Key: "t_cp", name: "AxColorPicker.ahk", size: 28900, kind: "Script", date: "2026-09-07", Icon: "E943"},
            {Key: "t_dv", name: "AxDataView.ahk", size: 26400, kind: "Script", date: "2026-09-07", Icon: "E943"}]}]},
    {Key: "t_example", name: "example", kind: "Folder", Icon: "E8B7", Children: [
        {Key: "t_show", name: "Showcase.ahk", size: 33800, kind: "Script", date: "2026-09-07", Icon: "E943"},
        {Key: "t_todo", name: "Todo.ahk", size: 41200, kind: "Script", date: "2026-09-06", Icon: "E943"},
        {Key: "t_assets", name: "assets", kind: "Folder", Icon: "E8B7", Children: [
            {Key: "t_photo", name: "photo.jpg", size: 9712, kind: "Picture", date: "2026-09-07", Icon: "EB9F"},
            {Key: "t_spin", name: "spinner.gif", size: 28665, kind: "Picture", date: "2026-09-07", Icon: "EB9F"}]}]},
    {Key: "t_readme", name: "README.md", size: 24100, kind: "Document", date: "2026-09-07", Icon: "E8A5"}]

tree := g.AddDataView("vdvTree h280 Checkboxes CheckTree", {
    Columns: [{Key: "name", Title: "Name", Width: 430, Icon: true},
              {Key: "size", Title: "Size", Width: 100, Align: "right", Sort: "number",
                  Format: (v, row) => v = "" ? "" : AxWindow.FileSize(v)},
              {Key: "kind", Title: "Kind", Width: 150}],
    Rows: TreeRows, Empty: "Nothing in the tree matches."})
treeOut := g.AddText("vdvTreeOut Hint", "Double-click a branch to open it, or use the keyboard: Right opens a "
    . "branch and steps into it, Left closes it and steps back out.")
g.Use()

Section("Grouped", "Set Group to a column's key and the rows gather under headers that collapse, with counts.")
g.AddDataView("vdvGroup h260 NoSearch NoColumnMenu Group=kind Single", {
    Columns: [{Key: "name", Title: "Name", Width: 380, Icon: true},
              {Key: "size", Title: "Size", Width: 110, Align: "right", Sort: "number",
                  Format: (v, row) => AxWindow.FileSize(v)},
              {Key: "date", Title: "Modified", Width: 190}],
    Rows: FileRows})
g.AddText("Hint", "The rows are AHK objects, the comparators and formatters AHK functions, and the selection, "
    . "the ticks and what is open are AHK state.")
g.Use()

Section("Gui's own ListView and TreeView", "With their own words — LV.Add, LV.GetNext, LV.ModifyCol, TV.Add, "
    . "TV.GetParent — so a script written for Gui() fills them unchanged; underneath they are data views.")
; the list takes what the tree leaves, and drops the tree under it on a narrow window
lvNative := g.AddListView("vlvNative h250 Checked Grid Style=min-width:360px", ["Name", "Size", "Kind"])
for r in FileRows
    if (A_Index <= 12)
        lvNative.Add(r.kind = "Picture" ? "Check" : "", r.name, r.size, r.kind)
lvNative.ModifyCol()                        ; every column fitted to what is in it, as on Gui
lvNative.ModifyCol(2, "Integer")
lvNative.ModifyCol(1, "Sort")
lvNative.OnEvent("DoubleClick", (lv, row) => row ? Log("Row " row ": " lv.GetText(row)) : "")
lvNative.OnEvent("ItemCheck", (lv, row, on) => Log(lv.GetText(row) (on ? " ticked" : " unticked")))
lvNative.OnEvent("ColClick", (lv, col) => Log("Sorted by " lv.GetText(0, col)))

tvNative := g.AddTreeView("vtvNative x+16 w240 h250 Checked")
libItem := tvNative.Add("lib", 0, "Expand")
tvNative.Add("AxWindow.ahk", libItem)
tvNative.Add("AxGui.ahk", libItem)
themesItem := tvNative.Add("themes", libItem)
for f in ["win11.css", "win98.css", "winxp.css"]
    tvNative.Add(f, themesItem)
exampleItem := tvNative.Add("example")
tvNative.Add("Showcase.ahk", exampleItem, "Select")
tvNative.Add("Todo.ahk", exampleItem)
tvNative.OnEvent("ItemSelect", (tv, id) => Log("Tree: " TreePath(tv, id)))
tvNative.OnEvent("ItemCheck", (tv, id, on) => Log(TreePath(tv, id) (on ? " ticked" : " unticked")))

g.AddButton("", "Ticked to console").OnClick((*) => LogTicked(lvNative))
g.AddButton("x+8", "Add a row").OnClick((*) => lvNative.Add("Select Vis", "new-" A_TickCount ".txt", 0, "Document"))
g.AddButton("x+8", "Delete selected").OnClick((*) => DeleteSelected(lvNative))
g.AddButton("x+8", "Open the whole tree").OnClick((*) => OpenTree(tvNative))
g.Use()

; the path of a tree item, from GetParent
TreePath(tv, id) {
    path := tv.GetText(id)
    while (id := tv.GetParent(id))
        path := tv.GetText(id) "\" path
    return path
}
; the ticked rows, with GetNext's "C", as it is done on Gui
LogTicked(lv) {
    out := "", row := 0
    while (row := lv.GetNext(row, "C"))
        out .= (out = "" ? "" : ", ") lv.GetText(row)
    Log("Ticked: " (out != "" ? out : "(none)"))
}
DeleteSelected(lv) {
    n := 0
    while (row := lv.GetNext(0))
        lv.Delete(row), n++
    Log("Deleted " n " row" (n = 1 ? "" : "s"))
}
OpenTree(tv) {
    id := 0
    while (id := tv.GetNext(id, "Full"))
        tv.Modify(id, "Expand")
}


; ==============================================================================
; Layout
; ==============================================================================

g.AddPage("layout", "Layout", "E8A9")

Lead("Boxes that hold controls. AddCard, AddGroupBox, AddExpander, AddRow and AddTab each open one, and the "
    . "Add* calls after it go inside; box.Use() goes back into a box and g.Use() back to the page.")

outerCard := Section("Cards", "This whole card is one: a title, this line, a row of buttons — and another card inside it.")
g.AddButton("", "One").OnClick((*) => g.Toast("One"))
g.AddButton("x+8", "Two").OnClick((*) => g.Toast("Two"))
g.AddButton("x+8 Accent", "Three").OnClick((*) => g.Toast("Three", 2000, "success"))
g.AddCard("", "A card inside a card")
g.AddText("Hint", "outerCard.Use() steps back out of this one…")
outerCard.Use()
g.AddText("Hint", "…and this line is back in the outer card, after the inner one.")
g.Use()

sec := Section("Setting rows", "AddRow is an icon, a title, a line under it and a control on the right. "
    . "NoCard rows share one card, with a Separator between them — as here.")
g.AddRow("NoCard Icon=E7C1", "Notifications", "From apps and from Windows")
g.AddSwitch("vswNotify Checked")
    .OnChange((c, v, *) => Log("Notifications -> " (v ? "on" : "off")))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E706", "Brightness", "The built-in display")
g.AddSlider('w180 Suffix="%"', 60)
sec.Use()
Rule()
g.AddRow("NoCard Icon=E7E8", "Battery saver", "Turns itself on below")
g.AddDDL("w110 Choose2", "10:10%|20:20%|30:30%|never:Never")
g.Use()

Section("Group box", "A legend over a frame, as on Gui.")
g.AddGroupBox("", "Delivery")
g.AddRadio("vrgShip Choose1", "std:Standard (3–5 days)|fast:Express (next day)|pick:Collect in store")
    .OnChange((c, v, *) => Log("Delivery -> " v))
g.AddCheckBox("", "Leave it with a neighbour if nobody is in")
g.Use()
g.Use()

sec := Section("Expanders", "Click a header. Open starts one opened, and one can hold another.")
outerExp := g.AddExpander("vexpOuter Icon=E713 Open", "Opened to begin with", "Open, in the option string")
g.AddText("", "Anything goes in here:")
g.AddSegmented("x+12 Choose2", "s:Small|m:Medium|l:Large")
g.AddExpander("vexpInner Icon=E8B7", "An expander inside an expander", "Boxes nest as deep as you like")
g.AddText("Hint", "Two boxes down; each Use() steps back to the box you name.")
outerExp.Use()
g.AddText("Hint", "Back in the outer expander, after the inner one.")
sec.Use()
g.AddExpander("vexpClosed Icon=E946", "Closed to begin with", "A click on the header opens it")
g.AddText("", "Hidden until someone asks for it.")
g.Use()

Section("Tabs", "Every tab is a box of its own: UseTab(n) fills it, and OnChange tells AHK which one is showing.")
lt := g.AddTab("vtabsLayout", ["General:E713", "Sharing:E72D", "History:E81C"])
g.Ctl("tabsLayout").OnChange((c, v, *) => Log("Tab -> " v))
lt.UseTab(1)
g.AddText("", "Show this folder in Quick access")
g.AddSwitch("x+12 Checked")
lt.UseTab(2)
g.AddText("", "Share with")
g.AddDDL("x+12 w160 Choose1", "me:Only me|team:My team|all:Everyone")
lt.UseTab(3)
g.AddText("Hint", "Nothing here has changed in the last 30 days.")
lt.UseTab()

Section("Breadcrumb and splitter", "Pick a folder of this project in the tree: the list fills and the trail "
    . "follows; click a step of the trail to go back to it. Drag the bar between the panes to resize the tree.")
crumb := g.AddBreadcrumb("vcrumb Home", "root:AHK2-ActiveX-Gui")
crumb.OnChange((c, v, *) => CrumbBack(v))
spTree := g.AddTreeView("vspTree w240 h260")
g.AddSplitter('vspV x+4 Target=spTree Min=150 Max=460 Tip="Drag to resize the tree"')
    .OnChange((c, v, *) => Log("Tree pane -> " v "px"))
spList := g.AddListView("vspList x+4 h260 Style=min-width:200px", "Name|Size|Modified")
spOut := g.AddText("vspOut Hint", "The splitter sizes the pane before it; the list fills the line, so it takes the rest.")
g.Use()

SpRoot := RegExReplace(A_ScriptDir, "\\[^\\]+$")        ; the project: one up from example
SpPaths := Map()                                        ; tree item id -> its folder
spRootId := spTree.Add("AHK2-ActiveX-Gui", 0, "Expand")
SpPaths[spRootId] := SpRoot
SpFolders(spRootId, SpRoot, 3)
spTree.OnEvent("ItemSelect", (tv, id) => SpOpen(id))

SpFolders(parent, dir, depth) {
    loop files dir "\*", "D" {
        name := A_LoopFileName, path := A_LoopFileFullPath
        if (SubStr(name, 1, 1) = ".")                   ; .git, .claude ...
            continue
        id := spTree.Add(name, parent)
        SpPaths[id] := path
        if (depth > 1)
            SpFolders(id, path, depth - 1)
    }
}
SpOpen(id) {
    if !SpPaths.Has(id)
        return
    dir := SpPaths[id]
    spList.FillFolder(dir)
    trail := "", n := id
    while n
        trail := n ":" spTree.GetText(n) (trail = "" ? "" : "`n" trail), n := spTree.GetParent(n)
    crumb.Component.Path := trail
    spOut.Text := spList.GetCount() " file" (spList.GetCount() = 1 ? "" : "s") " in " dir
}
CrumbBack(v) {
    if !IsInteger(v)
        return
    spTree.Modify(Integer(v), "Select")
    SpOpen(Integer(v))
}

sec := Section("A splitter across", "Horizontal: it sets the height of the box above it. Drag the bar under "
    . "the top pane; Min and Max keep it between 60 and 320 pixels.")
g.AddCard('vspTop h110 Style="overflow:auto"', "Top pane")
g.AddText("Hint", "OnChange hands the new height to AHK once you let go, and g.SplitterSize(id) reads or sets it from code.")
sec.Use()
g.AddSplitter("vspH Horizontal Target=spTop Min=60 Max=320")
    .OnChange((c, v, *) => Log("Top pane -> " v "px"))
g.AddCard("", "Bottom pane")
g.AddButton("", "Top pane to 200px").OnClick((*) => g.SplitterSize("spH", 200))
g.AddButton("x+8", "Back to 110px").OnClick((*) => g.SplitterSize("spH", 110))
g.Use()

Section("Steps", "A wizard's progress: Back and Next walk it, and a finished step can be clicked to go back to.")
g.AddStepper("vsteps", "Account:Sign in`nProfile:Your name and picture`nPreferences:Theme and sounds`nDone:All set")
    .OnChange((c, n, *) => StepSays(n))
g.AddButton("", "Back").OnClick((*) => g.Ctl("steps").Component.Back())
g.AddButton("x+8 Accent", "Next").OnClick((*) => g.Ctl("steps").Component.Next())
g.AddButton("x+8", "Finish").OnClick((*) => g.Ctl("steps").Component.Finish())
g.AddButton("x+8 Subtle", "Start again").OnClick((*) => g.Ctl("steps").Component.Go(1))
stepOut := g.AddText("vstepOut x+16 Hint", "Step 1 of 4: Account")
g.Use()

StepSays(n) {
    st := g.Ctl("steps").Component
    stepOut.Text := st.IsDone ? "All four done." : "Step " n " of " st.Count ": " st.List[n].L
    Log("Steps -> " (st.IsDone ? "finished" : n))
}


; ==============================================================================
; Status
; ==============================================================================

g.AddPage("status", "Status", "EB05")

Lead("Things that report: this machine's readings as stat cards and dials (read from Windows once a second "
    . "while the page is open), progress, info bars, badges — and people.")

Section("Stat cards", "One number, where it is heading, and a sparkline of the last minute.")
g.AddStat('vstCpu Fill Icon=E9F5 Label="Processor" Good=down Note="all cores, this second" Spark="0,0"', "–")
g.AddStat('vstMem x+12 Fill Icon=E9D9 Label="Memory in use" Good=down Note="reading…" Spark="0,0"', "–")
g.AddStat('vstDisk Fill Icon=E74E Label="System drive" Note="reading…"', "–")
g.AddStat('vstUp x+12 Fill Icon=E7E8 Label="Windows has been up" Note="reading…"', "–")
g.AddText("Hint", "A trend is green going up and red going down; Good=down turns that round, as it is for a "
    . "processor and memory. Push(n) adds a point to the sparkline and lets the oldest go.")
g.Use()

Section("Gauges", "A dial for one number; ctl.Value moves it.")
g.AddGauge("vgCpu w120 Ticks")
g.AddGauge("vgMem x+56 w120 Ticks")
g.AddGauge("vgDisk x+56 w120 Ticks")
g.AddText("w120 Center Caption", "Processor %")
g.AddText("x+56 w120 Center Caption", "Memory %")
g.AddText("x+56 w120 Center Caption", "Drive full %")
g.Use()

Section("Progress", "Determinate, driven from AHK — it fills the status bar's slot too — and indeterminate.")
g.AddText("w120", "Determinate")
pb := g.AddProgress("vpbDemo x+8 Fill", 35)
g.AddText("w120", "Indeterminate")
g.AddProgress("x+8 Fill Indeterminate")
g.AddText("w120", "")
g.AddButton("x+8", "Simulate work")
    .OnClick((*) => StartProgress())
g.Use()

Progress := 0
StartProgress() {
    global Progress := 0
    SetTimer(ProgressTick, 60)
}
ProgressTick() {
    global Progress += 2
    g.Style("pbDemo_bar", "width", Progress "%")
    g.StatusProgress("job", Progress)
    if (Progress >= 100) {
        SetTimer(ProgressTick, 0), g.Toast("Work complete", 2000, "success")
        g.StatusProgress("job", ""), g.Status("job", ""), g.Status("msg", "Work complete")
    }
}

Section("Info bars", "A message that stays until it is dealt with — the kinds, each with a title.")
g.AddInfoBar('Title="Did you know?"', "Right-click almost anything in this window for a menu of its own.")
g.AddInfoBar('Kind=success Title="Saved."', "Your settings are stored.")
g.AddInfoBar('Kind=warning Title="Restart needed."', "The new display scale applies after a restart.")
g.AddInfoBar('Kind=error Title="Offline."', "Could not reach the update server.")
g.Use()

Section("Badges", "A count or a word, beside whatever it is about.")
g.AddText("", "Inbox")
g.AddBadge("x+8 Kind=accent", "12")
g.AddText("x+32", "Updates")
g.AddBadge("x+8 Kind=success", "OK")
g.AddText("x+32", "Warnings")
g.AddBadge("x+8 Kind=warning", "3")
g.AddText("x+32", "Errors")
g.AddBadge("x+8 Kind=error", "!")
g.AddText("x+32", "Plain")
g.AddBadge("x+8", "New")
g.Use()

Section("People", "AddAvatar: a picture or initials, on a colour that comes from the name — the same person is "
    . "always the same colour. Named makes it a persona card; hover a small one for the name.")
Team := [["Ada Lovelace", "online", "Analytical engines"], ["Grace Hopper", "busy", "Compilers"],
         ["Alan Turing", "away", "Computability"], ["Katherine Johnson", "offline", "Orbital mechanics"]]
for i, p in Team
    g.AddAvatar('vav' i (Mod(i, 2) = 0 ? " x+24" : "") ' w280 Named Size=40 Status=' p[2] ' Sub="' p[3] '"', p[1])
Rule()
for i, n in ["Edsger Dijkstra", "Barbara Liskov", "Donald Knuth", "Margaret Hamilton", "Ken Thompson",
             "Frances Allen", "Dennis Ritchie", "Radia Perlman", "Linus Torvalds"]
    g.AddAvatar((i = 1 ? "" : "x+6") " Size=32" (i <= 3 ? " Square" : ""), n)
g.AddButton("x+24 Subtle", "Change Ada's status")
    .OnClick((*) => CycleStatus())
g.Use()

AdaStatus := 1
CycleStatus() {
    global AdaStatus
    states := ["online", "away", "busy", "offline"]
    AdaStatus := Mod(AdaStatus, states.Length) + 1
    g.Ctl("av1").Component.SetStatus(states[AdaStatus])
    Log("Ada Lovelace is " states[AdaStatus])
}

; -- the readings --------------------------------------------------------------

CpuPrev := -1
StatusTick() {
    global CpuPrev
    if (g.CurrentPage != "status")
        return
    cpu := SysCpu(), mem := SysMemory(), disk := SysDisk()
    st := g.Ctl("stCpu").Component
    if IsObject(st) {
        st.Value := cpu "%"
        st.SetTrend(CpuPrev < 0 ? "" : cpu = CpuPrev ? "0%" : (cpu > CpuPrev ? "+" : "") (cpu - CpuPrev) "%")
        st.Push(cpu, 60)
    }
    CpuPrev := cpu
    st := g.Ctl("stMem").Component
    if IsObject(st) {
        st.Value := Round((mem.Total - mem.Free) / 1073741824, 1) " GB"
        st.SetNote(mem.Load "% of " Round(mem.Total / 1073741824) " GB")
        st.Push(mem.Load, 60)
    }
    st := g.Ctl("stDisk").Component
    if (IsObject(st) && disk.Total) {
        st.Value := Round(disk.Free / 1024) " GB free"
        st.SetNote(disk.Drive " — " Round(disk.Total / 1024) " GB in all")
    }
    st := g.Ctl("stUp").Component
    if IsObject(st) {
        s := A_TickCount // 1000
        st.Value := (s >= 86400 ? s // 86400 "d " : "") Mod(s // 3600, 24) "h " Format("{:02}", Mod(s // 60, 60)) "m"
        st.SetNote("since " FormatTime(DateAdd(A_Now, -s, "Seconds"), "ddd d MMM, HH:mm"))
    }
    g.Value("gCpu", cpu)
    g.Value("gMem", mem.Load)
    if disk.Total
        g.Value("gDisk", Round(100 - disk.Free * 100 / disk.Total))
}

; processor time since the last call, as a percentage of all cores
SysCpu() {
    static last := ""
    idle := Buffer(8), kern := Buffer(8), user := Buffer(8)
    DllCall("GetSystemTimes", "Ptr", idle, "Ptr", kern, "Ptr", user)
    now := [NumGet(idle, "Int64"), NumGet(kern, "Int64"), NumGet(user, "Int64")]
    pct := 0
    if IsObject(last) {
        busy := (now[2] - last[2]) + (now[3] - last[3])      ; kernel time includes idle time
        pct := busy > 0 ? Round(100 * (busy - (now[1] - last[1])) / busy) : 0
    }
    last := now
    return Max(0, Min(100, pct))
}
SysMemory() {
    ms := Buffer(64, 0)
    NumPut("UInt", 64, ms)
    DllCall("GlobalMemoryStatusEx", "Ptr", ms)
    return {Load: NumGet(ms, 4, "UInt"), Total: NumGet(ms, 8, "UInt64"), Free: NumGet(ms, 16, "UInt64")}
}
SysDisk() {
    drive := EnvGet("SystemDrive") "\"
    try return {Drive: drive, Total: DriveGetCapacity(drive), Free: DriveGetSpaceFree(drive)}
    return {Drive: drive, Total: 0, Free: 0}
}


; ==============================================================================
; Images & media
; ==============================================================================

g.AddPage("media", "Images & media", "EB9F")

BarNames  := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
BarValues := [42, 68, 31, 90, 55, 74]
BarPicked := 0
DroppedImages := []

Lead("Pictures and vectors, still without a line of JavaScript. Relative paths resolve through the page's "
    . "<base>; SetImage() watches a picture load and reports whether it arrived.")

Section("Local files", "A JPEG, a PNG with alpha, an animated GIF and an SVG, each an AddImage box with a caption.")
g.AddImage('vimgPhoto w260 h180 Caption="assets/photo.jpg"', "assets/photo.jpg")
g.AddImage('vimgLogo x+10 w150 h180 Fit=contain Caption="PNG with alpha"', "assets/logo.png")
g.AddImage('vimgGif x+10 w120 h180 Fit=contain Caption="animated GIF"', "assets/spinner.gif")
g.AddImage('vimgBadge x+10 w150 h180 Fit=contain Caption="badge.svg"', "assets/badge.svg")
g.AddText("Hint", "Round, contained or cropped: pass Round or Fit=contain; the default crops to fill.")
g.Use()

Section("Image buttons", "A picture is a control like any other — these three are clickable, and the last is "
    . "a plain button with an <svg> glyph in it, coloured by currentColor.")
g.AddImageButton('vbtnPic1 w72 h72 Fit=contain Tip="assets/logo.png"', "assets/logo.png")
    .OnClick((*) => (g.Toast("Logo button", 1600), Log("Image button -> logo.png")))
g.AddImageButton('vbtnPic2 x+8 w72 h72 Round Tip="assets/photo.jpg (round, cropped)"', "assets/photo.jpg")
    .OnClick((*) => (g.Toast("Round photo button", 1600), Log("Image button -> photo.jpg")))
g.AddImageButton('vbtnPic3 x+8 w72 h72 Fit=contain Tip="assets/badge.svg"', "assets/badge.svg")
    .OnClick((*) => (g.Toast("SVG button", 1600, "success"), Log("Image button -> badge.svg")))
g.AddHtml("x+24",
    '<span class="btn accent" id="btnSvgIcon" tabindex="0">'
    . '<svg width="14" height="14" viewBox="0 0 16 16" style="vertical-align:-2px">'
    . '<path d="M8 1l2.1 4.5 4.9.6-3.6 3.4.9 4.9L8 12.1 3.7 14.4l.9-4.9L1 6.1l4.9-.6z" fill="currentColor"/>'
    . '</svg><span style="margin-left:8px">Inline SVG icon</span></span>')
g.On("click", "btnSvgIcon", (*) => (g.Toast("An <svg> glyph inside an ordinary button", 2200),
    Log("Inline SVG button clicked")))
g.Use()

Section("A plain picture", "AddPicture, Gui's own name for it, writes an <img> and nothing more: give it a "
    . "height and the width follows. For a frame, a caption or load watching, AddImage.")
g.AddPicture("vpicPlain h90", "assets/logo.png")
g.AddPicture("vpicPlain2 x+16 h90", "assets/photo.jpg")
g.Use()

Section("From the web", "Load a picture by address — and see what happens when that fails.")
g.AddText("w90", "Image URL")
urlBox := g.AddEdit("vtxtUrl x+8 Fill", "https://www.gstatic.com/webp/gallery/1.jpg")
g.AddButton("x+8 Accent", "Load")
    .OnClick((*) => LoadImageUrl(urlBox.Value))
g.AddButton("", "A host that cannot resolve")
    .OnClick((*) => LoadImageUrl("https://no-such-host.invalid/missing.png"))
g.AddButton("x+8", "Missing local file")
    .OnClick((*) => LoadImageUrl(A_ScriptDir "\assets\not-here.png"))
g.AddButton("x+8", "Local file")
    .OnClick((*) => LoadImageUrl(A_ScriptDir "\assets\photo.jpg"))
g.AddButton("x+8 Subtle", "Clear")
    .OnClick((*) => (g.ClearImage("imgUrl", "Nothing loaded."), urlStatus.Text := "Idle."))
g.AddImage('vimgUrl w440 h240 Fit=contain Alt="Nothing loaded yet." '
    . 'Fail="Could not load that picture — offline, blocked, or a bad address."', "")
urlStatus := g.AddText("vurlStatus Hint",
    "Idle. The load is watched from AHK, so failure is a state the page can show, not a broken icon.")
g.Use()

LoadImageUrl(url) {
    url := Trim(url)
    if (url = "")
        return
    urlStatus.Text := "Loading " url " …"
    Log("Image request: " url)
    g.SetImage("imgUrl", url, {
        Timeout: 8000,
        OnLoad:  (id, src) => (urlStatus.Text := "Loaded: " src, Log("Image loaded: " src),
            g.Toast("Image loaded", 1800, "success")),
        OnError: (id, src) => (urlStatus.Text := "Failed: " src, Log("Image failed: " src),
            g.Toast("Could not load that image", 2800, "error"))
    })
}

Section("Inline SVG", "The chart is part of the document, and AHK drives its shapes directly: click a bar to "
    . "select it, hover one for a tooltip.")
g.AddSvg("vchart Fill", ChartSvg())
chartOut := g.AddText("vchartOut Hint", "No bar selected.")
g.AddText("w110", "Corner radius")
g.AddSlider("vslRound x+8 w200 Min=0 Max=16", 3)
    .OnChange((c, v, *) => SetBarRadius(v))
g.AddButton("x+16 Icon=E72C", "Shuffle")
    .OnClick((*) => ShuffleBars())
g.AddButton("x+8 Subtle", "Clear selection")
    .OnClick((*) => SelectBar(0))
g.Use()

loop BarValues.Length
    g.On("click", "bar" A_Index, BarClick(A_Index))

BarClick(i) => (el, ev) => SelectBar(i)

ChartSvg() {
    s := '<svg viewBox="0 0 440 200" width="100%" height="200" xmlns="http://www.w3.org/2000/svg">'
       . '<line x1="24" y1="174" x2="430" y2="174" stroke="#888888" stroke-opacity=".55" stroke-width="1"/>'
    for i, v in BarValues {
        x := 24 + (i - 1) * 68, bh := Round(v / 100 * 150)
        s .= '<rect id="bar' i '" x="' x '" y="' (174 - bh) '" width="46" height="' bh '" rx="3" ry="3"'
           . ' fill="#3a6ea5" data-tip="' BarNames[i] ': ' v '"/>'
           . '<text id="barval' i '" x="' (x + 23) '" y="' (174 - bh - 6) '" text-anchor="middle"'
           . ' font-size="11" fill="#b8c4d0">' v '</text>'
           . '<text x="' (x + 23) '" y="190" text-anchor="middle" font-size="11" fill="#8d949c">' BarNames[i] '</text>'
    }
    return s '</svg>'
}

UpdateBars() {
    for i, v in BarValues {
        bh := Round(v / 100 * 150)
        g.Attr("bar" i, "y", 174 - bh)
        g.Attr("bar" i, "height", bh)
        g.Attr("bar" i, "data-tip", BarNames[i] ": " v)
        g.Attr("barval" i, "y", 174 - bh - 6)
        g.SvgText("barval" i, v)
    }
}

ShuffleBars() {
    global BarValues
    fresh := []
    loop BarValues.Length
        fresh.Push(Random(12, 100))
    BarValues := fresh
    UpdateBars()
    SelectBar(BarPicked)
    Log("SVG chart shuffled -> " Join(BarValues))
}

SelectBar(n) {
    global BarPicked := n
    loop BarValues.Length
        g.Attr("bar" A_Index, "fill", A_Index = n ? "#60cdff" : "#3a6ea5")
    chartOut.Text := n ? (BarNames[n] " = " BarValues[n]) : "No bar selected."
    if n
        Log("SVG bar -> " BarNames[n] " = " BarValues[n])
}

SetBarRadius(r) {
    loop BarValues.Length
        g.Attr("bar" A_Index, "rx", r), g.Attr("bar" A_Index, "ry", r)
}

Section("Thumbnails", "Drag pictures in from Explorer, or click the zone to browse; each lands in the strip, "
    . "and the corner button drops it again.")
g.AddDropZone('vdzImages Accept=images Browse Icon=EB9F '
    . 'Desc="PNG, JPG, GIF, BMP, ICO or SVG. Anything else turns the zone red before you let go."',
    "Drop images here")
    .OnDrop(AddDroppedImages, {OnEnter: (files, id) => g.Text("dzImagesCount",
                                  files.Length " picture" (files.Length = 1 ? "" : "s") " ready — release to add"),
                               OnLeave: (id) => g.Text("dzImagesCount", "")})
g.AddText("vdzImagesCount Hint", "")
strip := g.AddThumbs("vimgStrip h240", "Dropped pictures land here.")
; through SetDropped: an assignment inside a fat arrow would only make a local
strip.OnChange((c, order, *) => (SetDropped(order), Log("Thumbnails -> " order.Length " left")))
shotCount := g.AddText("vshotCount Caption", "0 pictures")
g.AddButton("x+16 Subtle", "Clear all")
    .OnClick((*) => (SetDropped([]), strip.SetThumbs([])))
g.Use()

SetDropped(list) {
    global DroppedImages := list
    UpdateShotCount()
}

AddDroppedImages(files, id := "", info := "") {
    global DroppedImages
    for f in files
        DroppedImages.Push(f)
    strip.SetThumbs(DroppedImages, {Size: 108, Removable: true, IdPrefix: "shot"})
    UpdateShotCount()
    g.Text("dzImagesCount", "")
    Log("Images dropped: " files.Length " (" DroppedImages.Length " in the strip)")
    g.Toast(files.Length " picture" (files.Length = 1 ? "" : "s") " added", 2000, "success")
}

UpdateShotCount() {
    n := DroppedImages.Length
    shotCount.Text := n " picture" (n = 1 ? "" : "s")
}

Section("An ActiveX control", "Shell.Explorer.2 docked in the page, showing this example's assets folder.")
g.AddActiveX("vaxAssets h230", "Shell.Explorer.2")
g.AddButton("Icon=E8B7", "The assets folder")
    .OnClick((*) => AxNavigate(A_ScriptDir "\assets"))
g.AddButton("x+8", "The project")
    .OnClick((*) => AxNavigate(RegExReplace(A_ScriptDir, "\\[^\\]+$")))
g.AddButton("x+8 Icon=E72B", "Back")
    .OnClick((*) => AxBack())
g.AddText("Hint", "AddActiveX leaves a placeholder in the layout and keeps a native child window on it through "
    . "scrolling, resizing and page switches, hidden while a dialog is up. ctl.Object is the COM object — here, "
    . "told to Navigate to a folder. Embed.ahk has a web browser and a video player.")
g.Use()

AxNavigate(dir) {
    try g.Ctl("axAssets").Object.Navigate(dir)
    Log("ActiveX -> " dir)
}
; A folder view takes Explorer a quarter of a second to open -- as long as the
; rest of this window's start put together -- so it opens when its page is
; first looked at, not while the window is coming up.
MediaFirstShown(id, *) {
    static done := false
    if (id != "media" || done)
        return
    done := true
    AxNavigate(A_ScriptDir "\assets")
}
AxBack() {
    try g.Ctl("axAssets").Object.GoBack()        ; throws when there is nothing to go back to
}


; ==============================================================================
; Drag & drop
; ==============================================================================

g.AddPage("drop", "Drag & drop", "E896")

CurrentFolder := ""
FolderRecurse := false

Lead("Real OLE drop targets, not just WM_DROPFILES: the element under the cursor lights up while you are "
    . "still dragging, and every zone can refuse what it does not want. Things on the page drag into order too.")

Section("Drop a folder", "Its contents are listed live, rebuilt from AHK on every change.")
g.AddDropZone('vdzFolder Accept=folders Browse Single Icon=E8B7 '
    . 'Desc="One folder at a time — or click to pick one."', "Drop a folder here")
    .OnDrop(ShowFolder, {OnEnter: (files, id) => g.Text("folderInfo", "Release to list " files[1]),
                         OnLeave: (id) => RefreshFolder()})
g.AddText("w130", "Include sub-folders")
g.AddSwitch("vswRecurse x+8")
    .OnChange((c, v, *) => SetFolderRecurse(v))
g.AddText("x+24 w50", "Filter")
folderFilter := g.AddSearch('vtxtFolderFilter x+8 w220 Placeholder="Name contains…"')
folderFilter.OnEvent("KeyUp", (*) => RefreshFolder())
g.AddButton("x+16 Icon=E8B7", "Pick a folder…")
    .OnClick((*) => PickFolder())
folderInfo := g.AddText("vfolderInfo Caption", "No folder yet.")
folderList := g.AddFileList("vflFolder h280", "Drop a folder above to see what is inside it.")
folderList.OnChange((c, order, *) => g.Text("folderInfo", order.Length " item"
    . (order.Length = 1 ? "" : "s") " left in the list"))
g.Use()

ShowFolder(files, id := "", info := "") {
    global CurrentFolder := files[1]
    RefreshFolder()
    Log("Folder dropped: " CurrentFolder)
}

PickFolder() {
    d := g.SelectFolder("Choose a folder to list")      ; modern picker, not the old tree
    if (d != "")
        ShowFolder([d])
}

SetFolderRecurse(on) {
    global FolderRecurse := on ? true : false
    RefreshFolder()
}

RefreshFolder() {
    if (CurrentFolder = "") {
        folderList.SetFiles([], {Empty: "Drop a folder above to see what is inside it."})
        folderInfo.Text := "No folder yet."
        return
    }
    entries := []
    if !FolderRecurse                                   ; flat view: sub-folders first, then files
        loop files RTrim(CurrentFolder, "\") "\*.*", "D"
            entries.Push(A_LoopFileFullPath)
    for p in AxWindow.FolderFiles(CurrentFolder, FolderRecurse)
        entries.Push(p)
    needle := Trim(folderFilter.Value), shown := [], bytes := 0
    for p in entries {
        if (needle != "" && !InStr(p, needle))
            continue
        shown.Push(p)
        if !DirExist(p)
            try bytes += FileGetSize(p)
    }
    folderList.SetFiles(shown, {Removable: true, Relative: CurrentFolder,
        Empty: needle = "" ? "This folder is empty." : "Nothing here matches '" needle "'."})
    folderInfo.Text := shown.Length " of " entries.Length " item" (entries.Length = 1 ? "" : "s")
        . "  ·  " AxWindow.FileSize(bytes) "  ·  " CurrentFolder
}

Section("Zones that choose", "Each zone decides for itself what it will take, and turns red before you let go "
    . "of anything it will not.")
g.AddDropZone('vdzText Accept=text Compact Browse Icon=E8A5 '
    . 'Desc="txt, log, md, csv, json, xml, ini, ahk…"', "Text files only")
    .OnDrop((files, id, info) => (Log("Text zone <- " Join(files)),
        g.Toast(files.Length " text file" (files.Length = 1 ? "" : "s"), 2000, "success")))
g.AddDropZone('vdzOne Single Compact Icon=E7C3 '
    . 'Desc="Drop two or more and the zone turns red."', "Exactly one file")
    .OnDrop((files, id, info) => (Log("Single-file zone <- " files[1]),
        g.Alert("You dropped a single file:`n`n" files[1], "One file")))
g.AddDropZone('vdzScripts Accept="*.ahk;*.ahk2" Compact Browse Icon=E943 '
    . 'Desc="An explicit extension list instead of a named group."', "AutoHotkey scripts")
    .OnDrop((files, id, info) => (Log("Script zone <- " Join(files)),
        g.Toast(files.Length " script" (files.Length = 1 ? "" : "s") " accepted", 2000, "success")))
g.AddDropZone('vdzExpand Expand Recurse Compact Icon=E8B7 '
    . 'Desc="Folders are unpacked into their files before the callback runs."', "Files, folders unpacked")
    .OnDrop((files, id, info) => (Log("Expanding zone <- " files.Length " file(s)"),
        g.Toast(files.Length " file" (files.Length = 1 ? "" : "s") " after unpacking folders", 2600)))
g.Use()

sec := Section("Anywhere in the window")
g.AddRow("NoCard Icon=E7C4", "Accept drops anywhere",
    'Registers the "*" zone: a file dropped on any page reaches one callback')
g.AddSwitch("vswAnywhere")
    .OnChange((c, v, *) => ToggleAnywhereDrop(v))
sec.Use()
g.AddText("Hint", "Ctrl and Shift reach the callback in info.Ctrl / info.Shift, and the answer to Explorer is "
    . "always a copy: replying with a move would make it delete what you dragged.")
g.Use()

ToggleAnywhereDrop(on) {
    if on {
        g.DropZone("*", (files, id, info) => (Log("Window-wide drop (" files.Length "): " Join(files)),
            g.Toast(files.Length " file" (files.Length = 1 ? "" : "s") " dropped on page '" g.CurrentPage "'", 2600)))
        g.Toast("Any file dropped on this window now reaches the console", 2600)
    } else {
        g.RemoveDropZone("*")
        g.Toast("Window-wide drops off", 1800)
    }
}

Section("Tiles into order", "Drag a tile to reorder the grid; hover one for its remove button. OnChange hands AHK the new order.")
grid := g.AddGrid("vgridTiles")
for t in [
    ["files",    "E8B7", "Files",    "Browse folders"],
    ["mail",     "E715", "Mail",     "3 unread"],
    ["photos",   "EB9F", "Photos",   "1,204 items"],
    ["music",    "E8D6", "Music",    "Now playing"],
    ["calendar", "E787", "Calendar", "2 events today"],
    ["terminal", "E756", "Terminal", "PowerShell"]
]
    g.AddTile('Value=' t[1] ' Icon=' t[2] ' Desc="' t[4] '" Removable', t[3])
g.Use()
gridOrder := g.AddText("vgridOrder Hint", "")
g.Ctl("gridTiles").OnChange((c, order, *) => (gridOrder.Text := "Order: " Join(order),
    Log("Tiles -> " Join(order))))
g.AddButton("Icon=E710", "Add a tile")
    .OnClick((*) => AddTile())
g.Use()

TileCount := 0
AddTile() {
    global TileCount
    name := g.Prompt("Tile name:", "Add a tile", "Tile " (++TileCount))
    if (name != "")
        grid.AddTile('Icon=E8A5 Desc="Added at ' FormatTime(, "HH:mm:ss") '" Removable', name)
}

Section("A list into order", "Drag a task by its handle; tick it off, or remove it. Enter adds one.")
taskInput := g.AddEdit('vtxtTask w320 Placeholder="New task, then Enter or Add"')
g.AddButton("x+8 Accent", "Add")
    .OnClick((*) => AddTask())
tasks := g.AddHtml("vlistTasks Fill Class=sort-list", "")
g.Use()

TaskHtml(txt) {
    esc := AxWindow._Esc(txt)
    return '<div class="drag-item" data-value="' esc '">'
        . '<span class="drag-handle ico">&#xE700;</span>'
        . '<label class="check" data-role="check"><input type="checkbox"><span class="box"></span></label>'
        . '<span class="text">' esc '</span>'
        . '<span class="remove ico" data-role="remove-item">&#xE8BB;</span></div>'
}

AddTask() {
    txt := Trim(taskInput.Value)
    if (txt = "")
        return
    g.Append("listTasks", TaskHtml(txt))
    taskInput.Value := ""
    Log("Task added: " txt)
}

taskInput.OnEvent("KeyDown", (c, ev, *) => ev.keyCode = 13 ? AddTask() : "")


; ==============================================================================
; Menus & dialogs
; ==============================================================================

g.AddPage("dialogs", "Menus & dialogs", "E8BD")

Lead("Everything that pops up: dialogs drawn in the page, Windows' own notifications, toasts, "
    . "right-click menus — and every kind of click.")

sec := Section("Dialogs", "Drawn in the page and driven by AHK: the call waits for the answer, like MsgBox.")
g.AddRow("NoCard Icon=E946", "Alert", "One button")
g.AddButton("", "Show")
    .OnClick((*) => g.Alert("This dialog is plain HTML inside the page, driven by AHK.", "Hello"))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E897", "Confirm", "Yes or No; the answer goes to the Console")
g.AddButton("", "Show")
    .OnClick((*) => Log("Confirm -> " (g.Confirm("Do you like custom dialogs?", "Question") ? "Yes" : "No")))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E8AC", "Prompt", "A line of text — this one renames the window")
g.AddButton("", "Show")
    .OnClick((*) => (n := g.Prompt("Window title:", "Rename window", g.Title)) != "" ? g.SetTitle(n) : "")
sec.Use()
Rule()
g.AddRow("NoCard Icon=E74D", "Custom", "Three buttons, a destructive default, Escape for Cancel")
g.AddButton("Danger", "Delete…")
    .OnClick((*) => Log("Delete dialog -> " g.Dialog(
        "This will permanently remove 3 items.`nThere is no undo.",
        "Delete items?",
        ["Delete", "Keep", "Cancel"],
        {Kind: "warning", Danger: 1, Cancel: 3}
    ).Button))
g.Use()

sec := Section("Windows notifications", "Real Action Center toasts through the tray icon; a click or a dismissal "
    . "comes back to AHK.")
g.AddRow("NoCard Icon=E7C1", "Plain", "An info or a warning")
g.AddButton("", "Info")
    .OnClick((*) => g.Notify("AHK2 ActiveX GUI", "Hello from the notification centre.", "info"))
g.AddButton("x+8", "Warning")
    .OnClick((*) => g.Notify("Heads up", "Something needs your attention.", "warning"))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E896", "With an action", "One button — click it, or dismiss the toast, to see the result")
g.AddButton("", "Action toast")
    .OnClick((*) => g.Notify(
        "Updates available",
        "Version 2.1 is ready to install.`nClick Install to continue.",
        "info",
        {Buttons: [["Install", "install"]], OnClick: ShowNotifyResult, OnDismiss: ShowNotifyDismiss}))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E74D", "With a choice", "Two buttons, each opening a result dialog")
g.AddButton("", "Choice toast")
    .OnClick((*) => g.Notify(
        "Delete files?",
        "3 items will be permanently deleted.`nThis cannot be undone.",
        "warning",
        {Buttons: [["Keep", "keep"], ["Delete", "delete"]], OnClick: ShowNotifyResult,
            OnDismiss: ShowNotifyDismiss}))
g.Use()

Section("Toasts", "In the window, gone by themselves.")
g.AddButton("", "Info")
    .OnClick((*) => g.Toast("Just so you know."))
g.AddButton("x+8", "Success")
    .OnClick((*) => g.Toast("Saved successfully.", 2500, "success"))
g.AddButton("x+8", "Error")
    .OnClick((*) => g.Toast("Something went wrong.", 3000, "error"))
g.Use()

Section("Context menus", "Right-click the box for a menu of its own, and each chip for another — the last is "
    . "a native AHK Menu. Anywhere else, IE's menu is replaced by a page-wide one.")
area := g.AddHtml("vctxArea Fill",
    '<div style="border:1px dashed rgba(128,128,128,.4);border-radius:6px;padding:26px;text-align:center;">'
    . 'Right-click me for a custom menu</div>')
area.ContextMenu([
    ["Say hello",     (el, ev) => g.Toast("Hello from a context menu!")],
    "-",
    {Label: "Copy text", Shortcut: "Ctrl+C",
        Click: (el, ev) => (A_Clipboard := el.innerText, g.Toast("Copied.", 1500, "success"))},
    {Label: "Disabled item", Disabled: true},
    "-",
    ["Open console", (*) => g.ShowPage("console")]
])
for i, n in ["Alpha", "Beta"]
    g.AddChip(i = 1 ? "" : "x+8", n)
        .ContextMenu([
            ["Toggle",  (el, ev) => g.ToggleClass(el.id, "on")],
            ["Rename…", (el, ev) => (t := g.Prompt("New label:", "Rename", el.innerText)) != ""
                ? el.innerText := t : ""]
        ])
native := Menu()
native.Add("Native AHK menu item", (*) => g.Toast("Native menu clicked."))
gamma := g.AddChip("x+8", "Gamma (native)")
native.Add("Toggle Gamma", (*) => g.ToggleClass(gamma.Id, "on"))
gamma.ContextMenu(native)
g.Use()

; Double-click is a DOM event; middle-click is a mousedown with IE's button 4;
; a triple click is counted in AHK, because no such event exists.
Section("Every other click", "Single, double, triple and middle clicks, on a box and on real controls.")
clickTarget := g.AddHtml("vclickBox Fill",
    '<div id="clickBoxInner" style="border:1px dashed rgba(128,128,128,.45);border-radius:6px;'
    . 'padding:22px;text-align:center;">Single, double, triple or middle-click me</div>')
clickTarget.OnClick((c, *) => ClickSays("Single click"))
clickTarget.OnDoubleClick((c, *) => ClickSays("Double click"))
clickTarget.OnTripleClick((c, *) => ClickSays("Triple click"))
clickTarget.OnMiddleClick((c, *) => ClickSays("Middle click (the wheel)"))
g.AddButton("vclickBtn", "Button")
    .OnClick((*) => ClickSays("Button: single"))
    .OnDoubleClick((*) => ClickSays("Button: double"))
    .OnMiddleClick((*) => ClickSays("Button: middle"))
g.AddChip("vclickChip x+8", "Chip — four in a row")
    .OnMultiClick(4, (c, *) => ClickSays("Chip: four clicks in a row"))
g.AddText("vclickOut x+16 Caption", "Nothing yet.")
g.AddText("Hint", "A double click raises the single-click handler first — that is how the DOM works, and the "
    . "Console shows it. A triple click is counted from the click stream, so the gap between clicks "
    . "(400ms by default) is what separates one from the next.")
g.Use()

Section("Cursors", "Cursor= on any control sets the pointer over it: the names AutoHotkey uses (hand, no, "
    . "wait, ibeam, sizewe…) or CSS's own. Hover each one.")
for i, c in [["hand", "Hand"], ["no", "No"], ["wait", "Wait"], ["appstarting", "Busy in the background"],
             ["help", "Help"], ["ibeam", "Text"],
             ["cross", "Cross"], ["sizeall", "Move"], ["sizewe", "Size ↔"], ["sizens", "Size ↕"],
             ["sizenwse", "Size ⤡"], ["arrow", "Arrow"]]
    g.AddChip((i = 1 || i = 7 ? "" : "x+8") ' Cursor=' c[1] ' Tip="Cursor=' c[1] '"', c[2])
g.AddText("Hint", "At run time it is a style like any other: g.Style(id, " Chr(34) "cursor" Chr(34) ", "
    . Chr(34) "pointer" Chr(34) ").")
g.Use()

ClickSays(what) {
    g.Text("clickOut", what)
    g.Status("msg", what)
    Log(what)
}


; ==============================================================================
; Personalization
; ==============================================================================

g.AddPage("theme", "Personalization", "E790")

Lead("How the whole window looks: light or dark, one of twelve stylesheets, an accent colour and a tint — "
    . "each changed live, with the page left as it was.")

sec := Section("Theme")
g.AddRow("NoCard Icon=E793", "App mode", "Dark, light, or follow the Windows setting")
g.AddRadio("vrgTheme Choose2", "light:Light|dark:Dark|system:System")
    .OnChange((c, v, *) => (g.SetTheme(v), Log("Theme -> " v " (" g.Theme ")")))
sec.Use()
Rule()
sheetList := ""
for s in Sheets
    sheetList .= (sheetList = "" ? "" : "|") s[1] ":" s[2]
g.AddRow("NoCard Icon=E771", "Stylesheet", "The whole look at once; Theme > Stylesheet on the menu bar is the same")
g.AddDDL("vddSheet w180 Choose1", sheetList)
    .OnChange((c, v, *) => SetSheet(v))
sec.Use()
Rule()
; The Windows 9x colour schemes. They only mean anything on the Classic
; stylesheet -- the others paint their own chrome -- so the dropdown is
; disabled unless win98 is the current sheet, and re-enabled when it is.
g.AddRow("NoCard Icon=E7B3", "Classic colour scheme", "The Windows 9x schemes, layered over Windows 98 with SetExtraCss")
g.AddDDL("vscheme w180 Choose1",
    "std:Windows Standard|hc:High Contrast Black|rain:Rainy Day|brick:Brick"
    . "|eggplant:Eggplant|rose:Rose|slate:Slate")
    .OnChange((c, v, *) => SetScheme(v))
sec.Use()
g.AddText("vschemeHint Hint", "Only on the Windows 98 stylesheet.")
g.Use()

sec := Section("Accent colour", "On the retro stylesheets an accent repaints the title bar, every selection and "
    . "the bars — leave it at the default and the classic navy and Luna blue stand.")
g.AddRow("NoCard Icon=E771", "Swatches", "A palette of the Windows accents")
g.AddPalette("vpalAccent ShowHex Value=#60cdff",
    "#ffb900,#f7630c,#e74856,#e3008c,#b146c2,#8764b8,#0078d4,#60cdff,#00b7c3,#00cc6a,#10893e,#7a7574")
    .OnChange((c, v, *) => SetAccent(v))
sec.Use()
Rule()
; the rich picker as a swatch button — OnPreview repaints the window on every
; drag inside the dialog, OnChange commits, and cancelling puts it back
g.AddRow("NoCard Icon=E790", "Any colour", "A swatch button that opens the full picker")
g.AddColorButton("vcbAccent", "#60cdff")
    .OnPreview((hex, c) => g.SetAccent(hex))
    .OnChange((c, v, *) => SetAccent(v))
sec.Use()
g.AddButton("", "Use the Windows accent")
    .OnClick((*) => SetAccent(AxWindow.SystemAccent()))
g.AddButton("x+8 Subtle", "Back to the default")
    .OnClick((*) => (g.SetAccent(""), g.Text("palAccent_hex", "default"),
        Log("Accent -> the stylesheet's own")))
g.Use()

SetAccent(hex) {
    g.SetAccent(hex)
    g.Value("cbAccent", hex)
    try g.Text("palAccent_hex", hex)
    Log("Accent -> " hex)
}

Section("The whole colour picker", "The wheel the swatch buttons open, as a control of its own: drag the ring "
    . "for the hue and the square for the rest, or type into R, G, B and Hex.")
g.AddColorPicker("vcpInline Size=220", "#60cdff")
    .OnChange((c, v, *) => g.Text("cpInlineOut", "Picked " v))
g.AddText("vcpInlineOut Caption", "Picked #60cdff")
g.AddButton("x+16 Accent", "Make it the accent")
    .OnClick((*) => SetAccent(g.Ctl("cpInline").Component.Value))
g.AddButton("x+8 Icon=E790", "As a dialog…")
    .OnClick((*) => PickInto(g.PickColor({Current: g.Ctl("cpInline").Component.Value}), "dialog"))
g.AddButton("x+8", "From the screen…")
    .OnClick((*) => PickInto(g.PickScreenColor(), "screen"))
g.AddText("Hint", "g.PickColor() is the same wheel as a window; g.PickScreenColor() is the magnifier — "
    . "the mouse wheel zooms, a click takes the colour, Escape gives up.")
g.Use()

PickInto(hex, how) {
    if (hex = "")
        return Log("Colour from the " how " -> cancelled")
    g.Ctl("cpInline").Component.Value := hex
    g.Text("cpInlineOut", "Picked " hex)
    Log("Colour from the " how " -> " hex)
}

sec := Section("Surface tint", "Mixes a colour into every surface of the window.")
g.AddRow("NoCard Icon=E7E7", "Tint", "The first swatch means none")
g.AddPalette("vpalTint", "#4c4a48,#0078d4,#8764b8,#e3008c,#e74856,#f7630c,#10893e,#00b7c3,#ffb900")
    .OnChange((c, v, *) => SetTint(v = "#4c4a48" ? "" : v))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E9E9", "Strength", "How much of it")
g.AddSlider('vslTint w220 Min=0 Max=60 Suffix="%"', 12)
    .OnChange((c, v, *) => SetTintStrength(v))
sec.Use()
Rule()
g.AddRow("NoCard Icon=E790", "Any colour", "Or one of your own")
g.AddColorButton("vcbTint", "#4c4a48")
    .OnPreview((hex, c) => g.SetTint(hex, TintStrength))
    .OnChange((c, v, *) => SetTint(v))
sec.Use()
g.AddButton("", "Follow the accent")
    .OnClick((*) => (g.SetTint("accent", TintStrength), Log("Tint -> follows the accent")))
g.AddButton("x+8 Subtle", "No tint")
    .OnClick((*) => SetTint(""))
g.Use()

TintStrength := 0.12

; a fat arrow is a function of its own, so an assignment inside one would make
; a local and leave the global where it was -- the strength moves through here
SetTintStrength(pct) {
    global TintStrength := pct / 100
    g.SetTint(g.Tint = "" ? "accent" : g.Tint, TintStrength)
    Log("Tint strength -> " pct "%")
}

SetTint(hex) {
    g.SetTint(hex, TintStrength)
    if (hex != "")
        g.Value("cbTint", hex)
    Log("Tint -> " (hex = "" ? "none" : hex) " at " Round(TintStrength * 100) "%")
}

Schemes := Map(
    "std",      ["#c0c0c0", "#000080", "#1084d0", "#000080", "#000000", "#ffffff", "#ffffff", "#000000"],
    "hc",       ["#000000", "#800080", "#800080", "#008000", "#ffffff", "#ffffff", "#000000", "#ffffff"],
    "rain",     ["#8ba0b4", "#4a6b8a", "#7e9ab5", "#4a6b8a", "#000000", "#ffffff", "#ffffff", "#000000"],
    "brick",    ["#c0a890", "#800000", "#c86428", "#800000", "#000000", "#ffffff", "#ffffff", "#000000"],
    "eggplant", ["#c0c0c0", "#5c3d5c", "#9c7a9c", "#5c3d5c", "#000000", "#ffffff", "#ffffff", "#000000"],
    "rose",     ["#cfafb7", "#9f6070", "#e0b0c0", "#9f6070", "#000000", "#ffffff", "#ffffff", "#000000"],
    "slate",    ["#9db2c4", "#3c5b78", "#7a9bbd", "#3c5b78", "#000000", "#ffffff", "#ffffff", "#000000"]
)

SetScheme(name) {
    global Schemes

    if (!Schemes.Has(name))
        return
    c    := Schemes[name]
    face := c[1]
    hi   := c[4]
    txt  := c[5]
    win  := c[7]
    wtxt := c[8]
    hc   := (name = "hc")

    ; -- window face + text ------------------------------------------------
    ; -- "window" surfaces (list boxes, inputs, menus) + selection + title bar
    css := ""
    css .= "body, .card, .tab, .tab-panel, .group > .legend, .btn, .axdlg-btn, .segmented .seg, .numberbox .spin, .winbtn, .exp-header .chev, .exp-header, .chip, .tile, #axCtx, #axDlg, .dd-value:after, .sw-track:before, .passwordbox .reveal, .infobar .close, .hotkeybox .clear, .tile .remove, .sort-list .remove { background: " . face . "; color: " . txt . "; }"
    css .= " body, .card, .tab, .tab-panel, .btn, .axdlg-btn, .caption, .hint, .card-row .desc, .tile .desc, h1, h2, h3, .group > .legend, .exp-header, .exp-header .desc, .axctx-item, #axDlgText, .slider .out, .winbtn:before, .numberbox .spin:before, .dd-value:after, .exp-header .chev:before, .infobar .close:before, .hotkeybox .clear:before, .tile .remove:before, .sort-list .remove:before, .passwordbox .reveal { color: " . txt . "; }"
    css .= " #sidebar, .list, .dd-value, .dd-menu, .textbox input, .textbox textarea, .searchbox input, .numberbox input, .passwordbox input, .hotkeybox input, #axDlgInput, .check .box, .radio .ring, .sw-track, .hex, .infobar, .infobar.info, .infobar.success, .infobar.warning, .infobar.error, .sort-list .drag-item, .progress { background: " . win . "; color: " . wtxt . "; }"
    css .= " .nav-item, .dd-item, .list-item, .infobar .text, .infobar .ico, .check input:checked + .box, .radio input:checked + .ring:after, .sort-list .text, .sort-list .drag-handle, .hotkeybox .kb, .searchbox .ico { color: " . wtxt . "; }"
    css .= " .radio input:checked + .ring:after { background: " . wtxt . "; }"
    css .= " .nav-item.active, .dd-item.selected, .list-item.selected, .dd-item:hover, .list-item:hover, .axctx-item:hover, .chip.on, .switch input:checked + .sw-track, .badge.accent, .segmented .seg.active { background: " . hi . "; color: #ffffff; }"
    css .= " .progress .bar { background: repeating-linear-gradient(90deg, " . hi . " 0, " . hi . " 8px, " . win . " 8px, " . win . " 10px); }"
    css .= " .rating .star.on, .tile .ico, .link { color: " . (hc ? "#ffff00" : hi) . "; }"
    css .= " #titlebar, #axDlgTitle { background-color: " . c[2] . "; background-image: linear-gradient(90deg, " . c[2] . ", " . c[3] . "); color: " . c[6] . "; }"

    ; -- the window bars, and the components that arrived after this scheme ---
    css .= " .axmb, .axsb, .axsb-part { background: " . face . "; color: " . txt . "; }"
    css .= " .axmb-item, .axsb-part, .axsb-part.dim { color: " . txt . "; }"
    css .= " .axmb-item:hover, .axmb-item.open { background: " . hi . "; color: #ffffff; }"
    ; the colour button: only the frame and the lettering, never the chip --
    ; the chip IS the colour being shown
    css .= " .axcbtn { background: " . win . "; color: " . wtxt . "; }"
    css .= " .axcbtn-hex { color: " . wtxt . "; }"
    ; the grid
    css .= " .dv-frame, .dv-hcell, .dv-cell { background: " . win . "; color: " . wtxt . "; }"
    css .= " .dv-hcell, .dv-status, .dv-count, .dv-page { color: " . wtxt . "; }"
    css .= " .dv-row.selected > .dv-cell { background: " . hi . "; color: #ffffff; }"
    css .= " .dv-check { border-color: " . wtxt . "; color: " . wtxt . "; }"
    css .= " .dv-check.on, .dv-check.some { background: " . hi . "; color: #ffffff; }"
    ; drop zones, file lists and thumbnails
    css .= " .dropzone, .filelist, .imgbox, .thumb { background: " . win . "; color: " . wtxt . "; }"
    css .= " .fl-name, .fl-meta, .fl-ico, .thumb-cap { color: " . wtxt . "; }"
    css .= " .fl-row:hover { background: " . hi . "; color: #ffffff; }"
    ; the colour picker's own panels and fields
    css .= " .axcp, .axcp-fields, .axcp-swgroup { background: " . face . "; color: " . txt . "; }"
    css .= " .axcp-flbl, .axcp-hexlbl, .axcp-cap { color: " . txt . "; }"
    css .= " .axcp-fbox { background: " . win . "; color: " . wtxt . "; }"
    ; the slider is drawn by the browser, so its parts have to be named
    css .= " input[type=range]::-ms-track { background: " . win . "; }"
    css .= " input[type=range]::-ms-fill-lower { background: " . hi . "; }"
    css .= " input[type=range]::-ms-fill-upper { background: " . win . "; }"
    css .= " input[type=range]::-ms-thumb { background: " . face . "; }"

    if (hc) {
        ; High Contrast has one job: be legible. Every bevel becomes a plain
        ; white line, every surface gets an edge, focus is unmissable, and
        ; disabled text is green -- which is what Windows itself does.
        css .= " .btn, .axdlg-btn, .tab, .segmented .seg, .card, .group, .list, .dd-value, .textbox input, .numberbox input, .searchbox input, .passwordbox input, .hotkeybox input, .check .box, .radio .ring, .sw-track, .progress, #sidebar, .infobar, .sort-list .drag-item, .tile, .winbtn, .numberbox .spin, .dd-value:after { border-color: #ffffff; box-shadow: none; }"
        css .= " .btn:active, .winbtn:active { box-shadow: none; } .btn.disabled, .dropdown.disabled .dd-value { color: #00ff00; text-shadow: none; }"
        ; the same white edge on everything that arrived later
        css .= " .axcbtn, .dv-frame, .dv-hcell, .dropzone, .filelist, .imgbox, .thumb, .axmb, .axsb, .axsb-part, .hex, .axcp, .swatch { border: 1px solid #ffffff; box-shadow: none; }"
        ; a chip has to keep its own colour, so it is ringed rather than filled
        css .= " .axcbtn-chip, .swatch { outline: 1px solid #ffffff; }"
        ; focus you cannot miss, on anything that can take it
        css .= " .btn:focus, .axdlg-btn:focus, .dropdown:focus, .list:focus, .tab:focus, .seg:focus, .chip:focus, .link:focus, .swatch:focus, .rating:focus, .axcbtn:focus, .dv-bodywrap:focus { outline: 2px dotted #ffff00 !important; outline-offset: 1px; }"
        css .= " .textbox input:focus, .searchbox input:focus, .numberbox input:focus, .passwordbox input:focus, .hotkeybox input:focus, #axDlgInput:focus { outline: 2px dotted #ffff00; border-color: #ffff00; }"
        ; links and marks in yellow, the classic high-contrast signal
        css .= " .link, .hyperlink, a, .rating .star.on, .tile .ico, .card-row .ico, .searchbox .ico, .infobar .ico { color: #ffff00; }"
        ; hairline dividers are invisible at this contrast, so give them a body
        css .= " .dv-cell, .dv-hcell { border-color: #ffffff; }"
        css .= " .axctx-sep { background: #ffffff; border: none; height: 1px; }"
        ; selection has to read as selected, not as a slightly different black
        css .= " .nav-item.active, .dd-item.selected, .list-item.selected, .dv-row.selected > .dv-cell { outline: 1px solid #ffffff; }"
        ; and the disabled dropdown the classic schemes sit in
        css .= " .dropdown.disabled, .dropdown.disabled .dd-value, .btn.disabled { color: #00ff00; border-color: #00ff00; }"
    }

    g.SetExtraCss("scheme", g.Stylesheet = "win98" ? css : "")
    Log("Classic scheme -> " name)
}


; ==============================================================================
; Editors
; ==============================================================================

g.AddPage("editors", "Editors", "E943")

Lead("Two editors, each one control: code, coloured and suggested as you type, and rich text that "
    . "hands its words back as Markdown. example\Editors.ahk has more of both.")

Section("Code", "Type Ms and press Tab: MsgBox goes in with its parameters shown. Ctrl+F finds (with patterns), "
    . "Ctrl+G goes to a line, Ctrl+/ comments, Alt+Up/Down moves a line; AutoHotkey itself marks what does not parse.")
; a sample in every language the picker offers, so choosing one shows it off
CodeSamples := Map(
    "ahk", "; a class, a hotkey and a timer`nclass Greeter {`n    __New(name) {`n        this.Name := name`n    }`n"
        . "    Hello() {`n        MsgBox(`"Hello, `" this.Name)`n    }`n}`n`nhi := Greeter(`"World`")`n"
        . "^j:: hi.Hello()`nSetTimer(() => ToolTip(A_Now), 1000)`n",
    "js", "// a class, a template string and a chain`nclass Greeter {`n  constructor(name) {`n    this.name = name`n  }`n"
        . "  hello() {`n    return ``Hello, ${this.name}```n  }`n}`n`nconst hi = new Greeter('World')`n"
        . "console.log(hi.hello())`n[1, 2, 3].map(n => n * 2).filter(Boolean).forEach(n => console.log(n))`n",
    "json", '{`n  "name": "Showcase",`n  "version": "2.1.0",`n  "tags": ["ahk", "gui", "activex"],`n'
        . '  "window": { "width": 1040, "height": 760, "resizable": true },`n  "author": null`n}`n',
    "css", ".card {`n  padding: 14px 16px;`n  border-radius: 6px;`n  background: #2b2b2b;`n}`n`n"
        . ".btn.accent:hover {`n  background: #4cc2ff;`n}`n`n/* narrow windows */`n"
        . "@media (max-width: 640px) {`n  .card { padding: 10px; }`n}`n",
    "html", '<!doctype html>`n<html>`n  <head>`n    <title>Hello</title>`n  </head>`n  <body>`n'
        . '    <h1 class="title">Hello</h1>`n    <p>Written from <b>AutoHotkey</b>.</p>`n  </body>`n</html>`n',
    "py", "# a class, a comprehension and a context manager`nfrom pathlib import Path`n`nclass Greeter:`n"
        . "    def __init__(self, name):`n        self.name = name`n`n    def hello(self):`n"
        . "        return f`"Hello, {self.name}`"`n`nsquares = [n * n for n in range(10) if n % 2]`n"
        . "with open(`"notes.txt`") as f:`n    print(f.read())`n",
    "ps1", "# the ten biggest files under here`nGet-ChildItem -File -Recurse |`n    Sort-Object Length -Descending |`n"
        . "    Select-Object -First 10 Name, Length`n`n$total = (Get-ChildItem -File | Measure-Object Length -Sum).Sum`n"
        . "Write-Host `"Total: $total bytes`"`n",
    "sql", "-- the ten biggest files, by kind`nSELECT kind, name, size`nFROM files`nWHERE size > 1024 * 1024`n"
        . "ORDER BY size DESC`nLIMIT 10`n`nUPDATE files SET kind = 'Archive' WHERE name LIKE '%.7z'`n",
    "ini", "[Window]`nWidth=1040`nHeight=760`nTheme=dark`n`n[Recent]`nFile1=C:\Work\notes.txt`nFile2=C:\Work\plan.md`n",
    "md", "# Showcase`n`nEvery control, built from **AutoHotkey** alone.`n`n## Pages`n`n- Buttons & choices`n"
        . "- Text & forms`n- *Dates* and ``time```n`n> Press **F12** for the inspector.`n`n"
        . "| Page | Controls |`n| --- | --- |`n| Layout | 8 |`n")
scLang := g.AddDDL("vscLang w150 Choose1", "ahk:AutoHotkey|js:JavaScript|json:JSON|css:CSS|html:HTML|py:Python"
    . "|ps1:PowerShell|sql:SQL|ini:INI|md:Markdown")
scTheme := g.AddDDL("vscTheme x+8 w170 Choose1", "auto:Follow the window|dark:Dark|light:Light|monokai:Monokai"
    . "|solarized:Solarized|dracula:Dracula|contrast:High contrast")
g.AddButton("x+16", "Fold all").OnClick((*) => scCode.FoldAll(true))
g.AddButton("x+8", "Open all").OnClick((*) => scCode.FoldAll(false))
g.AddButton("x+8", "Find and replace").OnClick((*) => scCode.Find("", true))
scCode := g.AddCodeEditor("vscCode h300 Lang=ahk Theme=auto", CodeSamples["ahk"])
scCode.UseAhk({Lint: true})              ; AutoHotkey's service; it stands aside for the other languages
scLang.OnChange((c, v, *) => CodeLanguage(v))
scTheme.OnChange((c, v, *) => (scCode.SetTheme(v), Log("Code editor theme -> " v)))
scCode.OnEvent("Change", (c, text, *) => Log("Code: " StrLen(text) " characters"))
g.Use()

Section("Rich text", "The toolbar, or Markdown as you type: `"# `" a heading, `"- `" a list, **bold**. `"/`" on an empty "
    . "line offers every kind of block; in a table a small bar adds rows and columns, and Ctrl+Enter carries on under it.")
scNotes := g.AddRichText("vscNotes h300 Tools=full Format=md",
    "# Notes`n`nWrite **here** -- the Markdown comes out below as you go.`n`n- one`n- two`n`n"
    . "| Name | Done |`n| --- | --- |`n| Showcase | yes |")
scMd := g.AddCodeEditor("vscMd h120 Preset=notes ReadOnly", "")
scNotes.OnEvent("Change", (c, md, *) => (scMd.Value := md, Log("Rich text: " StrLen(md) " characters of Markdown")))
g.OnReady((*) => scMd.Value := scNotes.Value)
g.Use()

; a new language brings its own sample: Load() is a fresh text, so Undo does not
; step back into the last language's
CodeLanguage(lang) {
    scCode.SetLanguage(lang)
    if CodeSamples.Has(lang)
        scCode.Load(CodeSamples[lang])
    Log("Code editor language -> " lang)
}


; ==============================================================================
; Console
; ==============================================================================

g.AddPage("console", "Console", "E756")

Lead("Everything the other pages did, as it happened.")
logBox := g.AddConsole("vlogBox")

ClearLog() {
    global LogLines := 0
    logBox.Text := "", g.Text("logCount", 0)
}

g.AddButton('Tip="Empties the log"', "Clear")
    .OnClick((*) => ClearLog())


; ==============================================================================
; Run
; ==============================================================================

g.OnReady((app) => (
    app.Append("nav_console", '<span class="badge accent" id="logCount" style="margin-left:6px;">0</span>'),
    app.El("listTasks").setAttribute("data-role", "sortable"),
    app.El("listTasks").setAttribute("data-axis", "y"),
    app.El("listTasks").setAttribute("data-handle", "1"),
    app.Html("listTasks",
        TaskHtml("Review pull requests") TaskHtml("Write release notes") TaskHtml("Update dependencies")),
    app.OnValue("listTasks", (order, *) => Log("Tasks -> " Join(order))),
    app.ContextMenu("*", [
        ["Home",            (*) => app.ShowPage("home")],
        ["Console",         (*) => app.ShowPage("console")],
        "-",
        ["Toggle maximize", (*) => app.ToggleMaximize()],
        ["Exit",            (*) => app.Close()]
    ]),
    app.OnPage((id, *) => Log("Page -> " id)),
    app.OnPage((id, *) => app.Status("page", id)),
    app.OnPage((id, *) => id = "status" ? StatusTick() : ""),
    app.Status("page", app.CurrentPage),
    WireDataViews(app),
    app.OnPage(MediaFirstShown),
    SetTimer(() => (clock.Text := FormatTime(, "HH:mm:ss"),
        app.Status("clock", FormatTime(, "HH:mm:ss"))), 1000),
    SysCpu(),                                   ; the first reading only sets the baseline
    SetTimer(StatusTick, 1000),
    Log("Ready. Trident document mode: " app.DocMode)
))

WireDataViews(app) {
    lv := app.Ctl("dvFiles").Component
    lv.OnSelect((rows, dv) => dvOut.Text := rows.Length
        ? rows.Length " selected: " Join(Names(rows))
        : "Nothing selected.")
    lv.OnCheck((rows, dv) => Log("Ticked " rows.Length " file" (rows.Length = 1 ? "" : "s")))
    lv.OnActivate((row, dv) => (g.Toast("Opening " row.name, 2000), Log("Activated " row.name)))
    lv.OnSort((key, dir, dv) => Log("Sorted by " key " " (dir > 0 ? "ascending" : "descending")))
    lv.OnPage((n, dv) => Log("Page " n))
    tv := app.Ctl("dvTree").Component
    tv.OnSelect((rows, dv) => treeOut.Text := rows.Length ? "Selected: " rows[1].name : "Nothing selected.")
    tv.OnExpand((row, open, dv) => Log("Tree " (open ? "opened " : "closed ") row.name))
    Log("Data views ready: " lv.Count " files, " tv.Count " tree rows")
}

g.Show()
SyncSchemes()          ; the classic schemes follow the stylesheet
