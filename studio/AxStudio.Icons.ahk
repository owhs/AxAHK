#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming it here costs
; nothing when the whole studio is loaded and makes this part stand alone.
#Include %A_LineFile%\..\..\lib\AxGui.ahk

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
;  AxStudio.Icons.ahk -- the glyphs, and the picker that searches them.
;
;  Segoe Fluent Icons has a couple of thousand code points and no names you can
;  guess. Typing "E713" into a box is not choosing an icon, it is remembering
;  one -- so the studio carries a named subset, the ones a desktop application
;  actually reaches for, and searches them by what they are for.
;
;  The list is deliberately curated rather than complete: a grid of two
;  thousand unlabelled squares is worse than a hundred you can find.
; =============================================================================
class AxIcons {
    ; code, name, and the words you might search for it by
    static List := [
        ["E700", "Menu",            "hamburger burger nav"],
        ["E70D", "Chevron down",    "expand more arrow"],
        ["E70E", "Chevron up",      "collapse less arrow"],
        ["E70F", "Edit",            "pencil write rename"],
        ["E710", "Add",             "plus new create"],
        ["E711", "Cancel",          "close x remove"],
        ["E712", "More",            "ellipsis overflow dots"],
        ["E713", "Settings",        "gear options preferences"],
        ["E71B", "Link",            "url chain hyperlink"],
        ["E71C", "Filter",          "funnel"],
        ["E71D", "All apps",        "grid apps list"],
        ["E71E", "Zoom",            "magnify scale"],
        ["E721", "Search",          "find magnifier"],
        ["E72C", "Refresh",         "reload sync again"],
        ["E738", "Remove",          "minus subtract separator"],
        ["E739", "Checkbox",        "tick empty"],
        ["E73A", "Checkbox filled", "tick checked"],
        ["E73E", "Accept",          "tick check done ok"],
        ["E74D", "Delete",          "bin trash remove"],
        ["E74E", "Save",            "disk floppy store"],
        ["E750", "Attach",          "paperclip file"],
        ["E759", "Page left",       "previous back"],
        ["E75A", "Page right",      "next forward"],
        ["E765", "Keyboard",        "keys hotkey shortcut"],
        ["E767", "Volume",          "sound audio speaker"],
        ["E768", "Play",            "run start"],
        ["E769", "Pause",           "hold"],
        ["E71A", "Stop",            "halt"],
        ["E76B", "Chevron left",    "back previous"],
        ["E76C", "Chevron right",   "forward next expand"],
        ["E77B", "Contact",         "person user account avatar"],
        ["E77F", "People",          "users group team"],
        ["E786", "Chart",           "graph analytics"],
        ["E790", "Colour",          "palette paint theme"],
        ["E793", "Brightness",      "light theme sun"],
        ["E7C3", "Page",            "document file"],
        ["E7EE", "Slider",          "range"],
        ["E7E8", "Power",           "startup boot"],
        ["E7EF", "Undo",            "back revert"],
        ["E7F4", "Sync",            "refresh cloud"],
        ["E80F", "Home",            "house start"],
        ["E81C", "History",         "recent clock past"],
        ["E82D", "Read",            "book docs"],
        ["E838", "Folder open",     "directory"],
        ["E8A5", "Document",        "file text page"],
        ["E8AB", "Switch",          "toggle swap"],
        ["E8B7", "Folder",          "directory files"],
        ["E8B9", "Pictures",        "images photos gallery"],
        ["E8BB", "Close",           "x cancel dismiss"],
        ["E8BD", "Share",           "send"],
        ["E8C8", "Copy",            "duplicate clone"],
        ["E8C6", "Cut",             "scissors"],
        ["E8CB", "Sort",            "order arrange"],
        ["E8E5", "Attach camera",   "photo"],
        ["E8EF", "Calculator",      "number maths"],
        ["E8F1", "List",            "rows items"],
        ["E8FD", "Bulleted list",   "items tiles"],
        ["E896", "Download",        "save import drop"],
        ["E898", "Upload",          "export send"],
        ["E897", "Help",            "question support"],
        ["E8A7", "Back to window",  "restore"],
        ["E909", "World",           "globe web internet"],
        ["E90F", "Refresh circle",  "reload"],
        ["E915", "Radio",           "option bullet"],
        ["E91B", "Photo",           "image picture"],
        ["E921", "Minimise",        "chrome minimize"],
        ["E922", "Maximise",        "chrome maximize"],
        ["E923", "Restore",         "chrome"],
        ["E930", "Info",            "about status"],
        ["E946", "Information",     "info about help"],
        ["E943", "Code",            "script develop braces"],
        ["E9D9", "Diagnostic",      "debug"],
        ["E9F3", "Progress",        "loading bar"],
        ["E9F5", "Processing",      "work job spinner"],
        ["E9E9", "Equaliser",       "slider levels"],
        ["EA37", "Media",           "video play"],
        ["EB05", "Bar chart",       "analytics graph"],
        ["EBE7", "Package",         "box library module"],
        ["EC61", "Bug",             "debug issue"],
        ["ED1A", "Hide",            "eye off hidden"],
        ["E7B3", "View",            "eye show visible"],
        ["E734", "Star",            "favourite rating"],
        ["E735", "Star filled",     "favourite rating"],
        ["E72E", "Lock",            "password secure"],
        ["E785", "Unlock",          "open secure"],
        ["E77A", "Warning",         "alert caution"],
        ["E783", "Error",           "problem alert"],
        ["E74C", "Open in new",     "external window"],
        ["E7C1", "Flag",            "mark"],
        ["E706", "Brightness up",   "sun light"],
        ["E708", "Brightness down", "moon dark"],
        ["E72D", "Send",            "mail arrow"],
        ["E715", "Mail",            "email message"],
        ["E717", "Phone",           "call"],
        ["E77C", "Calendar",        "date schedule"],
        ["E787", "Calendar day",    "date"],
        ["E81D", "Location",        "map pin place"],
        ["E8AC", "Rename",          "edit label"],
        ["E8AD", "Find replace",    "search"],
        ["E8B3", "Select all",      "everything"],
        ["E8C1", "Show results",    "list"],
        ["E8EC", "Tag",             "label chip"],
        ["E8F4", "New folder",      "create directory"],
        ["E8FB", "Accept circle",   "done tick"],
        ["E904", "Zoom in",         "magnify"],
        ["E71F", "Zoom out",        "magnify"],
        ["E97C", "Badge",           "label count"],
        ["E9CE", "Unknown",         "question"],
        ["EA80", "Lightbulb",       "idea tip"],
        ["EA3A", "Money",           "cash payment"],
        ["E7EF", "Undo",            "revert"],
        ["E7A7", "Undo arrow",      "back"],
        ["E7A6", "Redo arrow",      "forward"],
        ["E756", "Command prompt",  "console terminal shell"],
        ["E7F8", "Clipboard",       "paste copy"],
        ["E784", "Split",           "divider splitter"],
        ["E76F", "Grip",            "resize corner"],
        ["E737", "Application",     "window app"],
        ["E8A9", "View all",        "grid"],
        ["E8EE", "Grid view",       "tiles"],
        ["E8FF", "List view",       "rows"],
        ["EF3C", "Timer",           "clock stopwatch"],
        ["E823", "Cloud",           "online sync"],
        ["E7BA", "Unsaved",         "warning pending"]]

    ; Everything whose name or keywords contain `q`.
    static Find(q) {
        q := StrLower(Trim(q))
        out := []
        for it in AxIcons.List {
            if (q = "" || InStr(StrLower(it[2] " " it[3] " " it[1]), q))
                out.Push(it)
        }
        return out
    }
    static Grid(q) {
        hits := AxIcons.Find(q)
        if !hits.Length
            return '<div class="axd-empty-pane">Nothing matches. You can still type a code point in the box.</div>'
        h := '<div class="axd-icons">'
        for it in hits
            h .= '<div class="axd-icon" data-glyph="' it[1] '" data-tip="' AxTags.E(it[2] "  (" it[1] ")") '">'
              .  '<span class="ico">&#x' it[1] ';</span></div>'
        return h '</div><div class="axd-note">' hits.Length ' of ' AxIcons.List.Length
             . ' &#x2014; the ones a desktop application actually reaches for. Any Segoe Fluent code point works in the box.</div>'
    }
}
