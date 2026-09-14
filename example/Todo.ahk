#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes/icons (single-file exe)
#Include ..\lib\AxGui.ahk
#Include ..\lib\AxAssets.ahk

; =============================================================================
;  Todo.ahk — folders, tags, priorities, due dates, search and filters, all
;  persisted to Todo.ini next to the script (tasks, order, folders, view,
;  theme, window position). Saved as it changes, restored on start.
;
;  Quick entry syntax in the composer:
;     Buy milk #shopping #errand !high @2026-09-12
;     #tag  adds a tag      !high / !low  sets priority      @YYYY-MM-DD  due date
;  Sidebar: click a folder, double-click to rename, right-click for more.
;  Tasks: double-click or the pencil to edit, right-click for move / remind.
;  Windows notifications (Notify) summarise what is due when the app opens.
; =============================================================================


; ─────────────────────────────────────────────────────────────────────────────
;  State & config
; ─────────────────────────────────────────────────────────────────────────────

IniFile       := A_ScriptDir "\Todo.ini"
Tasks         := []
Folders       := []
NextId        := 1

Filter        := IniRead(IniFile, "View", "Filter",  "all")
Folder        := IniRead(IniFile, "View", "Folder",  "Inbox")
TagSel        := ""
Query         := ""
Theme         := IniRead(IniFile, "View", "Theme",   "dark")
SideCollapsed := IniRead(IniFile, "View", "Sidebar", "0") = "1"


; ─────────────────────────────────────────────────────────────────────────────
;  Styles
; ─────────────────────────────────────────────────────────────────────────────

Css := "
(
/* ── two-column app layout: sidebar | main ─────────────────────────────── */
/* the two columns are pinned absolutely: IE11 mis-sizes flex bases here    */
#content {
    position: relative;
    width: 100%;
    height: calc(100vh - 32px);
    padding: 0;
    margin: 0;
    overflow: hidden;
}
#content > .ax-line { display: block; margin: 0; }

#side {
    position: absolute;
    left: 0; top: 0; bottom: 0;
    width: 216px;
    display: flex;
    flex-direction: column;
    padding: 10px 8px;
    margin: 0 !important;
    background: rgba(255,255,255,.03);
    border-right: 1px solid rgba(255,255,255,.06);
    overflow: hidden;
    transition: width 0.32s cubic-bezier(0.4,0,0.2,1),
                padding 0.32s cubic-bezier(0.4,0,0.2,1);
    will-change: width;
}
body.theme-light #side {
    background: rgba(0,0,0,.025);
    border-right-color: rgba(0,0,0,.06);
}

.main {
    position: absolute;
    left: 216px; right: 0; top: 0; bottom: 0;
    width: auto;
    display: flex;
    flex-direction: column;
    background: transparent;
    border: none;
    padding: 18px 24px 16px;
    margin: 0 !important;
    border-radius: 0;
    overflow: hidden;
    transition: left 0.32s cubic-bezier(0.4,0,0.2,1);
    will-change: left;
}
.main > .ax-line            { flex: none; margin-bottom: 12px; }
.main > .ax-line:last-child { flex: 1 1 auto; margin-bottom: 0; overflow-y: auto; align-items: flex-start; }
.main > .ax-line > .fill    { flex: 1 1 0px; }


/* ── sidebar ─────────────────────────────────────────────────────────────── */

.brand {
    display: flex;
    align-items: center;
    height: 26px;
    padding: 0 4px 0 12px;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: .5px;
    opacity: .55;
    margin-bottom: 2px;
    transition: padding 0.32s cubic-bezier(0.4,0,0.2,1);
}
.brand .ico  { font-size: 12px; margin-right: 8px; color: #60cdff; }
.brand .n    { flex: 1; white-space: nowrap; overflow: hidden; }
body.theme-light .brand .ico    { color: #005fb8; }


/* ── sidebar animation: fade text first, then collapse width ────────────── */

.brand .n,
.brand > .ico:first-child,
.side-h,
.fld .n,
.side-add span.t,
.sw-label {
    opacity: 1;
    transform: translateX(0);
    transition: opacity 0.14s ease,
                transform 0.20s cubic-bezier(0.4,0,0.2,1);
}

/* expand: JS waits for rail (340 ms) before removing sb-fade, so no extra CSS delay needed */
body:not(.sb-collapsed):not(.sb-fade) .brand .n,
body:not(.sb-collapsed):not(.sb-fade) .brand > .ico:first-child,
body:not(.sb-collapsed):not(.sb-fade) .side-h,
body:not(.sb-collapsed):not(.sb-fade) .fld .n,
body:not(.sb-collapsed):not(.sb-fade) .side-add span.t,
body:not(.sb-collapsed):not(.sb-fade) .sw-label {
    transition-delay: 0s;
}

/* fading: hide visually but keep layout for 160 ms until rail collapses */
body.sb-fade      .brand .n, body.sb-fade      .brand > .ico:first-child,
body.sb-fade      .side-h,   body.sb-fade      .fld .n,
body.sb-fade      .side-add span.t, body.sb-fade .sw-label,
body.sb-collapsed .brand .n, body.sb-collapsed .brand > .ico:first-child,
body.sb-collapsed .side-h,   body.sb-collapsed .fld .n,
body.sb-collapsed .side-add span.t, body.sb-collapsed .sw-label {
    opacity: 0;
    transform: translateX(-8px);
    pointer-events: none;
    transition-delay: 0s;
    transition-duration: 0.13s;
}

/* kill transitions on first paint and during theme switch */
body.no-anim #side, body.no-anim .main, body.no-anim .brand,
body.no-anim .fld,   body.no-anim .side-add,
body.no-anim .brand .n, body.no-anim .brand > .ico:first-child,
body.no-anim .side-h,   body.no-anim .fld .n,
body.no-anim .side-add span.t, body.no-anim .sw-label {
    transition: none !important;
}
body.theme-switching,
body.theme-switching * { transition: none !important; }


/* ── collapsed rail — width + layout collapse only on sb-collapsed ─────── */
/* sb-collapsed is added 160 ms AFTER fade starts, so the fade is already visible */

body.sb-collapsed #side  { width: 56px; padding: 10px 6px; }
body.sb-collapsed .main  { left: 56px; }
body.sb-collapsed .brand { padding: 0; justify-content: center; height: 26px; }

/* layout collapse — display:none is reliable in Trident */
body.sb-collapsed .brand > .ico:first-child,
body.sb-collapsed .brand .n,
body.sb-collapsed .side-h,
body.sb-collapsed .fld .n,
body.sb-collapsed .side-add span.t,
body.sb-collapsed .sw-label { display: none !important; }

body.sb-collapsed .fld       { padding: 0; justify-content: center; }
body.sb-collapsed .fld .ico  { margin: 0; width: auto; font-size: 16px; }
body.sb-collapsed .fld .cnt {
    position: absolute;
    right: 4px; top: 4px;
    min-width: 16px; height: 16px; line-height: 16px;
    padding: 0 4px;
    font-size: 10px;
    background: #60cdff; color: #000;
    opacity: 1;
}
body.theme-light.sb-collapsed .fld .cnt { background: #005fb8; color: #fff; }

body.sb-collapsed .side-add       { padding: 0; justify-content: center; }
body.sb-collapsed .side-add .ico  { margin: 0; width: auto; }
body.sb-collapsed .side-foot      { justify-content: center; padding-left: 0; padding-right: 0; }


/* ── folder rows ─────────────────────────────────────────────────────────── */

.side-h  { font-size: 11px; text-transform: uppercase; letter-spacing: .5px; opacity: .55; padding: 4px 12px 6px; }

.fld {
    position: relative;
    display: flex;
    align-items: center;
    height: 34px;
    padding: 0 12px;
    border-radius: 6px;
    margin-bottom: 2px;
    transition: background .1s;
}
.fld .ico { width: 20px; font-size: 14px; margin-right: 10px; opacity: .8; }
.fld .n   { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.fld .cnt {
    font-size: 11px;
    min-width: 20px; height: 18px; line-height: 18px;
    padding: 0 6px;
    border-radius: 9px;
    text-align: center;
    background: rgba(255,255,255,.08);
    opacity: .8;
}
body.theme-light .fld .cnt { background: rgba(0,0,0,.06); }

.fld:hover               { background: rgba(255,255,255,.06); }
body.theme-light .fld:hover { background: rgba(0,0,0,.04); }
.fld.active             { background: rgba(255,255,255,.09); }
body.theme-light .fld.active { background: rgba(0,0,0,.06); }

.fld.active:before {
    content: "";
    position: absolute;
    left: 0; top: 9px; bottom: 9px;
    width: 3px;
    border-radius: 2px;
    background: #60cdff;
}
body.theme-light .fld.active:before { background: #005fb8; }


/* ── sidebar footer / add-row ────────────────────────────────────────────── */

.side-add {
    display: flex;
    align-items: center;
    height: 32px;
    padding: 0 12px;
    border-radius: 6px;
    opacity: .7;
    margin-top: 4px;
}
.side-add:hover       { opacity: 1; background: rgba(255,255,255,.06); }
.side-add .ico        { width: 20px; font-size: 13px; margin-right: 10px; }

.side-foot {
    margin-top: auto;
    padding: 8px 4px 0;
    border-top: 1px solid rgba(255,255,255,.06);
    display: flex;
    align-items: center;
}
body.theme-light .side-foot { border-top-color: rgba(0,0,0,.06); }


/* ── header ──────────────────────────────────────────────────────────────── */

.hdr { display: flex; align-items: flex-end; width: 100%; }
.hdr h1 {
    flex: 1 1 auto;
    min-width: 0;
    margin: 0;
    font-size: 26px;
    line-height: 32px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.hdr .sub       { flex: none; margin: 0 12px 4px; opacity: .6; white-space: nowrap; }
.hdr .searchbox { flex: none; width: 220px; }


/* ── composer ────────────────────────────────────────────────────────────── */

.composer {
    display: flex;
    align-items: center;
    width: 100%;
    padding: 6px 6px 6px 14px;
    border-radius: 8px;
    background: rgba(255,255,255,.05);
    border: 1px solid rgba(255,255,255,.08);
}
body.theme-light .composer { background: #fff; border-color: rgba(0,0,0,.08); }
.composer .ico              { font-size: 16px; margin-right: 10px; opacity: .6; }
.composer .textbox          { flex: 1; }
.composer .textbox input {
    background: transparent;
    border: none;
    border-bottom: none;
    height: 34px;
    font-size: 14px;
}
.composer .textbox input:focus { background: transparent; border: none; }
.composer .btn                  { margin-left: 8px; }


/* ── filter bar ──────────────────────────────────────────────────────────── */

.bar               { display: flex; align-items: center; width: 100%; }
.bar > * + *       { margin-left: 10px; }
.bar .spacer       { flex: 1; }
.bar .segmented    { flex: none; }
.bar .seg          { white-space: nowrap; }
.bar .dropdown     { flex: none; }


/* ── task rows ───────────────────────────────────────────────────────────── */

#list { width: 100%; }

.sort-list .drag-item {
    min-height: 46px;
    padding: 6px 8px 6px 4px;
    margin-bottom: 6px;
    border-radius: 8px;
    border: 1px solid rgba(255,255,255,.06);
    background: rgba(255,255,255,.04);
    transition: background .1s, border-color .1s;
}
.sort-list .drag-item:hover { background: rgba(255,255,255,.07); border-color: rgba(255,255,255,.12); }
body.theme-light .sort-list .drag-item       { background: #fff; border-color: rgba(0,0,0,.07); }
body.theme-light .sort-list .drag-item:hover { background: #fafafa; border-color: rgba(0,0,0,.14); }

.sort-list .drag-handle { opacity: 0; transition: opacity .1s; }
.sort-list .drag-item:hover .drag-handle { opacity: .6; }

.task .check { margin: 0 10px 0 2px; }
.task .text {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 14px;
}
.task.done .text { text-decoration: line-through; opacity: .45; }

.task .meta { display: flex; align-items: center; flex: none; margin-left: 10px; }

.tag {
    display: inline-block;
    font-size: 11px;
    line-height: 18px;
    padding: 0 8px;
    border-radius: 9px;
    margin-left: 4px;
    background: rgba(96,205,255,.15);
    color: #9edcff;
}
body.theme-light .tag { background: rgba(0,95,184,.1); color: #005fb8; }
.tag:hover             { background: rgba(96,205,255,.3); }

.pri {
    display: inline-block;
    font-size: 10px;
    font-weight: 600;
    line-height: 18px;
    padding: 0 7px;
    border-radius: 4px;
    margin-left: 6px;
    text-transform: uppercase;
    letter-spacing: .3px;
}
.pri.high { background: rgba(255,153,164,.18); color: #ff99a4; }
.pri.low  { background: rgba(255,255,255,.08); opacity: .7; }
body.theme-light .pri.high { background: rgba(196,43,28,.1); color: #c42b1c; }

.due { display: inline-flex; align-items: center; font-size: 11px; margin-left: 8px; opacity: .7; }
.due .ico { font-size: 11px; margin-right: 4px; }
.due.late { color: #ff99a4; opacity: 1; }
.due.soon { color: #fce100; opacity: 1; }
body.theme-light .due.late { color: #c42b1c; }
body.theme-light .due.soon { color: #9d5d00; }

.task .act {
    display: flex;
    align-items: center;
    margin-left: 6px;
    opacity: 0;
    transition: opacity .1s;
}
.task:hover .act { opacity: 1; }
.task .act .ico {
    width: 26px; height: 26px; line-height: 26px;
    text-align: center;
    border-radius: 4px;
    font-size: 12px;
}
.task .act .ico:hover { background: rgba(255,255,255,.1); }
.task .act .del:hover { background: #c42b1c; color: #fff; }
.sort-list .remove    { display: none; }


/* ── empty state ─────────────────────────────────────────────────────────── */

.empty { width: 100%; text-align: center; padding: 60px 20px; opacity: .55; }
.empty .ico { font-size: 44px; display: block; margin-bottom: 12px; }
.empty b    { display: block; font-size: 15px; margin-bottom: 4px; }


/* ── the totals popover, dropped from the title bar ─────────────────── */

.popcard        { min-width: 190px; }
.popcard .who   { font-weight: 600; margin-bottom: 8px; }
.popcard .row   { display: flex; align-items: center; margin-bottom: 5px; }
.popcard .row:last-child { margin-bottom: 0; }
.popcard .k     { flex: 1; padding-right: 18px; }
.popcard .v     { opacity: .65; }
.popcard .none  { opacity: .55; }
)"


; ─────────────────────────────────────────────────────────────────────────────
;  Window & layout
; ─────────────────────────────────────────────────────────────────────────────

w := IniRead(IniFile, "Window", "W", 820)
h := IniRead(IniFile, "Window", "H", 600)

g := AxGui({
    Title:    "Tasks",
    AppName:  "Tasks",
    Width:    w,
    Height:   h,
    MinWidth: 620,
    MinHeight: 400,
    Theme:    Theme,
    Icon:     "none",
    Css:      Css
})

; The rail's collapse is on the title bar as well, so it can be put away
; without going looking for the control inside it. The two controls stay in
; step because both call ToggleSidebar, and TitleItem() patches the item where
; it stands rather than redrawing the bar.
;
; No "morph" class here: a burger that turns into a cross reads as a second
; close button, which is not what a pane toggle is. It just lights up instead.
g.AddTitleBar([
    {Id: "tbSide", Kind: "burger", Tip: "Collapse sidebar (Ctrl+B)",
     Click: (*) => ToggleSidebar()},
    {Id: "tbTotals", Side: "right", Glyph: "E9D5", Tip: "Open tasks by folder",
     Popover: {On: "hover", Align: "right", Build: TotalsCard}}
])

; Build runs on every open, so the tallies are always current.
TotalsCard() {
    h := '<div class="popcard"><div class="who">Open tasks</div>'
    any := false
    for f in Folders {
        n := FolderCount(f)
        if !n
            continue
        any := true
        h .= '<div class="row"><span class="k">' E(f) '</span>'
          .  '<span class="v">' n '</span></div>'
    }
    if !any
        h .= '<div class="none">Nothing open. All clear.</div>'
    return h '</div>'
}

; layout: sidebar | main  (main is a card that CSS turns into a column)
g.AddHtml("vside", "")
main := g.AddCard("x+0 vmain Class=main")
g.AddHtml("vhdr     Fill", "")
g.AddHtml("vcomposer Fill Class=composer",
    '<span class="ico">&#xE710;</span>'
    . '<div class="textbox"><input type="text" id="new" placeholder="Add a task…   #tag   !high   @2026-09-12"></div>'
    . '<span class="btn accent" id="btnAdd">Add</span>')
g.AddHtml("vbar  Fill Class=bar", "")
g.AddHtml("vlist Fill", "")


; ─────────────────────────────────────────────────────────────────────────────
;  Event wiring
; ─────────────────────────────────────────────────────────────────────────────

g.On("click",   "btnAdd", (*) => AddFromInput())
g.On("keydown", "new",    (el, ev) => ev.keyCode = 13 ? AddFromInput() : "")

g.On("keydown", "*", (el, ev) => (ev.ctrlKey && ev.keyCode = 70) ? (g.Focus("search"), ev.returnValue := false)
                                : (ev.ctrlKey && ev.keyCode = 78) ? (g.Focus("new"),    ev.returnValue := false)
                                : (ev.ctrlKey && ev.keyCode = 66) ? (ToggleSidebar(),   ev.returnValue := false) : "")

g.OnReady(Init)
g.OnClose((*) => SaveWindow())
g.Show()

try {
    x := IniRead(IniFile, "Window", "X", "")
    y := IniRead(IniFile, "Window", "Y", "")
    if (x != "" && y != "" && x > -2000 && y > -2000 && x < A_ScreenWidth && y < A_ScreenHeight)
        WinMove(x, y, , , g.Gui)
}


; ═════════════════════════════════════════════════════════════════════════════
;  Persistence
; ═════════════════════════════════════════════════════════════════════════════

Load() {
    global Tasks, Folders, NextId, Folder

    Folders := []
    n := IniRead(IniFile, "Folders", "Count", 0)
    loop n {
        f := IniRead(IniFile, "Folders", "F" A_Index, "")
        if (f != "")
            Folders.Push(f)
    }
    if !Folders.Length
        Folders := ["Inbox", "Work", "Home"]

    Tasks := []
    n := IniRead(IniFile, "Tasks", "Count", 0)
    loop n {
        line := IniRead(IniFile, "Tasks", "Task" A_Index, "")
        p := StrSplit(line, "|", , 6)
        if (p.Length < 6)
            continue
        Tasks.Push({
            Id:     NextId++,
            Done:   p[1] = "1",
            Folder: p[2],
            Pri:    p[3],
            Due:    p[4],
            Tags:   (p[5] = "" ? [] : StrSplit(p[5], ",")),
            Text:   p[6]
        })
    }

    if !HasFolder(Folder)
        Folder := Folders[1]
}

Save() {
    global Tasks, Folders

    IniDelete(IniFile, "Folders")
    IniDelete(IniFile, "Tasks")

    IniWrite(Folders.Length, IniFile, "Folders", "Count")
    for i, f in Folders
        IniWrite(f, IniFile, "Folders", "F" i)

    IniWrite(Tasks.Length, IniFile, "Tasks", "Count")
    for i, t in Tasks
        IniWrite((t.Done ? "1" : "0") "|" t.Folder "|" t.Pri "|" t.Due "|" Join(t.Tags, ",") "|" t.Text,
            IniFile, "Tasks", "Task" i)
}

SaveView() {
    global Filter, Folder
    IniWrite(Filter, IniFile, "View", "Filter")
    IniWrite(Folder, IniFile, "View", "Folder")
}

SaveWindow() {
    try {
        if !g.IsMaximized() {
            WinGetPos(&x, &y, &w, &h, g.Gui)
            IniWrite(x, IniFile, "Window", "X")
            IniWrite(y, IniFile, "Window", "Y")
            IniWrite(w, IniFile, "Window", "W")
            IniWrite(h, IniFile, "Window", "H")
        }
    }
}


; ═════════════════════════════════════════════════════════════════════════════
;  Helpers
; ═════════════════════════════════════════════════════════════════════════════

E(s) => AxWindow._Esc(s)

Join(arr, sep := ", ") {
    s := ""
    for v in arr
        s .= (s = "" ? "" : sep) v
    return s
}

HasFolder(name) {
    global Folders
    for f in Folders
        if (f = name)
            return true
    return false
}

Find(id) {
    global Tasks
    for i, t in Tasks
        if (t.Id = id)
            return i
    return 0
}

Parse(input) {
    t     := {Text: "", Pri: "", Due: "", Tags: []}
    words := []

    for w in StrSplit(Trim(input), " ") {
        if (w = "")
            continue
        if (SubStr(w, 1, 1) = "#" && StrLen(w) > 1)
            t.Tags.Push(StrLower(SubStr(w, 2)))
        else if (w = "!high" || w = "!low" || w = "!normal")
            t.Pri := (w = "!normal") ? "" : SubStr(w, 2)
        else if RegExMatch(w, "^@(\d{4}-\d{2}-\d{2})$", &m)
            t.Due := m[1]
        else
            words.Push(w)
    }

    t.Text := Join(words, " ")
    return t
}

Describe(t) => t.Text (t.Tags.Length ? " #" Join(t.Tags, " #") : "") (t.Pri != "" ? " !" t.Pri : "") (t.Due != "" ? " @" t.Due : "")

AllTags() {
    global Tasks, Folder
    seen := Map()
    out  := []

    for t in Tasks
        if (t.Folder = Folder)
            for tg in t.Tags
                if !seen.Has(tg)
                    seen[tg] := true, out.Push(tg)

    return out
}

Today()                      => FormatTime(, "yyyy-MM-dd")
AddDays(ymd, n)              => FormatTime(DateAdd(StrReplace(ymd, "-", ""), n, "days"), "yyyy-MM-dd")

DueInfo(due) {                          ; -> [class, label]
    if (due = "")
        return ["", ""]
    if (StrCompare(due, Today()) < 0)
        return ["late", "Overdue · " due]
    if (due = Today())
        return ["soon", "Today"]
    if (due = AddDays(Today(), 1))
        return ["soon", "Tomorrow"]
    return ["", due]
}

FolderCount(f) {
    global Tasks
    n := 0
    for t in Tasks
        if (t.Folder = f && !t.Done)
            n++
    return n
}


; ═════════════════════════════════════════════════════════════════════════════
;  View
; ═════════════════════════════════════════════════════════════════════════════

Init(app) {
    Load()

    list := app.El("list")
    list.className := "sort-list fill"
    list.setAttribute("data-role",   "sortable")
    list.setAttribute("data-axis",   "y")
    list.setAttribute("data-handle", "1")

    app.OnValue("list", (order, *) => Reorder(order))

    RenderSide()
    RenderHeader()
    RenderBar()
    Render()

    app.Focus("new")
    NotifyDue()
}

; Windows notification with what is overdue or due today, across all folders
NotifyDue() {
    global Tasks

    late  := 0
    due   := 0          ; not "today": that name is the Today() function
    first := ""

    for t in Tasks {
        if (t.Done || t.Due = "")
            continue
        if (StrCompare(t.Due, Today()) < 0)
            late++, first := (first = "" ? t.Text : first)
        else if (t.Due = Today())
            due++,  first := (first = "" ? t.Text : first)
    }

    if (late + due = 0)
        return

    msg := (late ? late " overdue"   : "")
         . (late && due ? ", "       : "")
         . (due ? due " due today"   : "")

    g.Notify("Tasks", msg (first != "" ? "`n" first : ""), late ? "warning" : "info")
}

RenderSide() {
    global Folders, Folder, Theme

    h := '<div class="side-h">Folders</div>'

    for i, f in Folders {
        n := FolderCount(f)
        h .= '<div class="fld' (f = Folder ? " active" : "") '"'
           . ' id="fld_' i '"'
           . ' data-folder="' E(f) '"'
           . ' data-tip="' E(f) (n ? " · " n " open" : "") '">'
           . '<span class="ico">&#x' (f = Folder ? "E838" : "E8B7") ';</span>'
           . '<span class="n">' E(f) '</span>'
           . (n ? '<span class="cnt">' n '</span>' : "")
           . '</div>'
    }

    h .= '<div class="side-add" id="fldNew" data-tip="New folder">'
       . '<span class="ico">&#xE710;</span><span class="t">New folder</span>'
       . '</div>'

    h .= '<div class="side-foot">'
       . '<label class="switch" data-role="switch" id="swDark" data-on="Dark" data-off="Light">'
       . '<input type="checkbox"' (Theme = "dark" ? " checked" : "") '>'
       . '<span class="sw-track"></span>'
       . '<span class="sw-label">' (Theme = "dark" ? "Dark" : "Light") '</span>'
       . '</label></div>'

    g.Html("side", h)

    for i, f in Folders {
        g.On("click",    "fld_" i, (el, ev) => SetFolder(el.getAttribute("data-folder")))
        g.On("dblclick", "fld_" i, (el, ev) => RenameFolder(el.getAttribute("data-folder")))
        g.ContextMenu("fld_" i, [
            ["Rename…",         (el, ev) => RenameFolder(el.getAttribute("data-folder"))],
            ["Clear completed", (el, ev) => ClearDone(el.getAttribute("data-folder"))],
            "-",
            ["Delete folder",   (el, ev) => DeleteFolder(el.getAttribute("data-folder"))]
        ])
    }

    g.On("click",  "fldNew",   (*) => NewFolder())
    g.OnValue("swDark", (v, *) => SetTheme(v ? "dark" : "light"))

    ; restore collapsed state without animating on first paint
    if (SideCollapsed) {
        g.BodyClass("no-anim",     true)
        g.BodyClass("sb-fade",     true)
        g.BodyClass("sb-collapsed", true)
        g.TitleItem("tbSide", {On: true, Tip: "Expand sidebar (Ctrl+B)"})
        SetTimer(() => g.BodyClass("no-anim", false), -80)
    }
}

; two-phase toggle: fade text out, then slide rail — reverse on expand
ToggleSidebar() {
    global SideCollapsed
    static Busy := false

    if (Busy)
        return
    Busy := true

    if (!SideCollapsed) {
        ; collapse: fade text (130 ms) then collapse rail (320 ms)
        SideCollapsed := true
        g.BodyClass("sb-fade", true)
        IniWrite("1", IniFile, "View", "Sidebar")
        g.TitleItem("tbSide", {On: true, Tip: "Expand sidebar (Ctrl+B)"})
        SetTimer(() => (g.BodyClass("sb-collapsed", true), Busy := false), -160)

    } else {
        ; expand: open rail (320 ms) then fade text in
        SideCollapsed := false
        g.BodyClass("sb-collapsed", false)
        IniWrite("0", IniFile, "View", "Sidebar")
        g.TitleItem("tbSide", {On: false, Tip: "Collapse sidebar (Ctrl+B)"})
        SetTimer(() => (g.BodyClass("sb-fade", false), Busy := false), -340)
    }
}

RenderHeader() {
    global Folder, Query
    open := FolderCount(Folder)

    g.Html("hdr",
        '<div class="hdr">'
        . '<h1 id="hTitle">' E(Folder) '</h1>'
        . '<span class="sub" id="hSub">' (open ? open " open" : "all clear") '</span>'
        . '<div class="searchbox">'
        . '<input type="text" id="search" placeholder="Search  (Ctrl+F)" value="' E(Query) '">'
        . '<span class="ico">&#xE721;</span>'
        . '</div></div>')

    g.On("keyup", "search", (el, ev) => SetQuery(el.value))
}

RenderBar() {
    global Filter, TagSel

    segs := ""
    for s in [["all", "All"], ["active", "Active"], ["done", "Done"], ["today", "Due soon"]]
        segs .= '<div class="seg' (s[1] = Filter ? " active" : "") '" data-value="' s[1] '">' s[2] '</div>'

    tags  := '<div class="dd-item' (TagSel = "" ? " selected" : "") '" data-value="">All tags</div>'
    label := "All tags"
    for tg in AllTags() {
        tags .= '<div class="dd-item' (tg = TagSel ? " selected" : "") '" data-value="' E(tg) '">#' E(tg) '</div>'
        if (tg = TagSel)
            label := "#" tg
    }

    g.Html("bar",
        '<div class="segmented" data-role="segmented" id="segFilter" data-value="' Filter '">' segs '</div>'
        . '<div class="dropdown" data-role="dropdown" id="ddTag" data-value="' E(TagSel) '" style="min-width:140px;">'
        . '<div class="dd-value">' label '</div><div class="dd-menu">' tags '</div></div>'
        . '<span class="spacer"></span>'
        . '<span class="btn subtle" id="btnClear"><span class="ico">&#xE74D;</span> Clear done</span>')

    g.OnValue("segFilter", (v, *) => SetFilter(v))
    g.OnValue("ddTag",     (v, *) => SetTag(v))
    g.On("click", "btnClear", (*) => ClearDone())
}

Visible(t) {
    global Filter, Folder, TagSel, Query

    if (t.Folder != Folder)
        return false
    if (Filter = "active" && t.Done) || (Filter = "done" && !t.Done)
        return false
    if (Filter = "today" && (t.Done || t.Due = "" || StrCompare(t.Due, AddDays(Today(), 7)) > 0))
        return false

    if (TagSel != "") {
        has := false
        for tg in t.Tags
            if (tg = TagSel)
                has := true
        if !has
            return false
    }

    if (Query != "" && !InStr(t.Text, Query) && !InStr("#" Join(t.Tags, " #"), Query))
        return false

    return true
}

Render() {
    global Tasks, Folders, Folder, Query, Filter

    html  := ""
    shown := 0

    for t in Tasks {
        if !Visible(t)
            continue
        shown++

        meta := ""
        for tg in t.Tags
            meta .= '<span class="tag" data-tag="' E(tg) '">#' E(tg) '</span>'
        if (t.Pri != "")
            meta .= '<span class="pri ' t.Pri '">' t.Pri '</span>'

        d := DueInfo(t.Due)
        if (d[2] != "")
            meta .= '<span class="due ' d[1] '"><span class="ico">&#xE787;</span>' d[2] '</span>'

        html .= '<div class="drag-item task' (t.Done ? " done" : "") '" data-value="' t.Id '">'
              . '<span class="drag-handle ico">&#xE700;</span>'
              . '<label class="check" data-role="check" id="chk_' t.Id '">'
              . '<input type="checkbox"' (t.Done ? " checked" : "") '><span class="box"></span></label>'
              . '<span class="text" id="txt_' t.Id '">' E(t.Text) '</span>'
              . '<span class="meta">' meta '</span>'
              . '<span class="act">'
              . '<span class="ico" id="ed_' t.Id '" data-tip="Edit">&#xE70F;</span>'
              . '<span class="ico del" id="rm_' t.Id '" data-tip="Delete" data-role="remove-item">&#xE74D;</span>'
              . '</span></div>'
    }

    if (shown = 0) {
        msg := Query != ""          ? ["E721", "No matches",              "Try another search."]
             : Filter = "done"      ? ["E73E", "Nothing completed yet",   "Tick a task to see it here."]
             : Filter = "today"     ? ["E787", "Nothing due soon",        "Tasks with a date in the next 7 days show here."]
             :                         ["E8FD", "All clear",               "Add a task above to get started."]

        html := '<div class="empty"><span class="ico">&#x' msg[1] ';</span><b>' msg[2] '</b>' msg[3] '</div>'
    }

    g.Html("list", html)

    for t in Tasks {
        g.OnValue("chk_" t.Id, ToggleDone.Bind(t.Id))
        g.On("dblclick", "txt_" t.Id, EditTask.Bind(t.Id))
        g.On("click",    "ed_"  t.Id, EditTask.Bind(t.Id))
        g.ContextMenu("txt_" t.Id, [
            ["Edit…",           EditTask.Bind(t.Id)],
            ["Move to folder…", MoveTask.Bind(t.Id)],
            ["Remind me now",   RemindTask.Bind(t.Id)],
            "-",
            ["Delete",          DeleteTask.Bind(t.Id)]
        ])
    }

    g.On("click", "list", (el, ev) => TagClick(ev))

    ; keep sidebar counts in sync
    for i, f in Folders {
        n := FolderCount(f)
        try {
            g.Html("fld_" i,
                '<span class="ico">&#x' (f = Folder ? "E838" : "E8B7") ';</span>'
                . '<span class="n">' E(f) '</span>'
                . (n ? '<span class="cnt">' n '</span>' : ""))
            g.Tooltip("fld_" i, f (n ? " · " n " open" : ""))
        }
    }

    open := FolderCount(Folder)
    try g.Text("hSub", open ? open " open" : "all clear")
}

TagClick(ev) {
    try {
        el := ev.srcElement
        if AxWindow._HasClass(el, "tag")
            SetTag(el.getAttribute("data-tag")), RenderBar()
    }
}


; ═════════════════════════════════════════════════════════════════════════════
;  Actions
; ═════════════════════════════════════════════════════════════════════════════

AddFromInput() {
    global Tasks, NextId, Folder
    p := Parse(g.Value("new"))
    if (p.Text = "")
        return

    Tasks.InsertAt(1, {Id: NextId++, Done: false, Folder: Folder, Pri: p.Pri, Due: p.Due, Tags: p.Tags, Text: p.Text})
    g.Value("new", "")
    g.Focus("new")
    Save()
    RenderBar()
    Render()
}

ToggleDone(id, v, *) {
    global Tasks
    if (i := Find(id))
        Tasks[i].Done := !!v, Save(), Render()
}

EditTask(id, *) {
    global Tasks
    if !(i := Find(id))
        return

    txt := g.Prompt("Edit task (use #tag, !high/!low, @date):", "Edit task", Describe(Tasks[i]))
    if (txt = "")
        return

    p := Parse(txt)
    Tasks[i].Text := p.Text
    Tasks[i].Pri  := p.Pri
    Tasks[i].Due  := p.Due
    Tasks[i].Tags := p.Tags
    Save()
    RenderBar()
    Render()
}

DeleteTask(id, *) {
    global Tasks
    if (i := Find(id))
        Tasks.RemoveAt(i), Save(), RenderBar(), Render()
}

MoveTask(id, *) {
    global Tasks, Folders
    if !(i := Find(id))
        return

    r := g.Dialog("Move `"" Tasks[i].Text "`" to:", "Move task", Folders, {Kind: "question"})
    if (r.Button != "" && HasFolder(r.Button))
        Tasks[i].Folder := r.Button, Save(), RenderSide(), Render()
}

RemindTask(id, *) {
    global Tasks
    if (i := Find(id))
        g.Notify("Reminder", Tasks[i].Text (Tasks[i].Due != "" ? "`nDue " Tasks[i].Due : ""), "info")
}

Reorder(order) {
    global Tasks

    ordered := []
    for id in order
        if (i := Find(Integer(id)))
            ordered.Push(Tasks[i])

    rebuilt := []
    done    := false
    for t in Tasks {
        if Visible(t) {
            if !done {
                for o in ordered
                    rebuilt.Push(o)
                done := true
            }
            continue
        }
        rebuilt.Push(t)
    }
    if !done
        for o in ordered
            rebuilt.Push(o)

    Tasks := rebuilt
    Save()
    RenderBar()
    Render()
}

SetFilter(v) {
    global Filter := v
    SaveView()
    Render()
}

SetTag(v) {
    global TagSel := v
    Render()
}

SetQuery(q) {
    global Query := Trim(q)
    Render()
}

SetFolder(v) {
    global Folder := v, TagSel := ""
    SaveView()
    RenderSide()
    RenderHeader()
    RenderBar()
    Render()
}

SetTheme(mode) {
    global Theme
    static Busy := false, Last := 0

    if (Busy || A_TickCount - Last < 450)
        return
    if (Theme = mode)
        return

    Busy := true
    Last := A_TickCount
    Theme := mode

    g.BodyClass("theme-switching", true)
    g.SetTheme(mode)
    IniWrite(mode, IniFile, "View", "Theme")

    ; Trident blanks when accent <style> + body class swap races — force sync reflow & host repaint
    try g.Eval("void(document.body.offsetHeight); document.body.className = document.body.className;")
    try DllCall("InvalidateRect", "Ptr", g.Gui.Hwnd, "Ptr", 0, "Int", 0)
    try DllCall("RedrawWindow",   "Ptr", g.Gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x85) ; RDW_INVALIDATE|UPDATENOW|ALLCHILDREN

    SetTimer(() => (g.BodyClass("theme-switching", false), Busy := false), -500)
}

ClearDone(which := "") {
    global Tasks, Folder
    f := which != "" ? which : Folder
    if !g.Confirm("Remove all completed tasks in " f "?", "Clear done")
        return

    kept := []
    for t in Tasks
        if !(t.Done && t.Folder = f)
            kept.Push(t)

    Tasks := kept
    Save()
    RenderBar()
    Render()
}

NewFolder() {
    global Folders
    name := Trim(g.Prompt("Folder name:", "New folder"))
    if (name = "" || HasFolder(name))
        return

    Folders.Push(name)
    Save()
    SetFolder(name)
}

RenameFolder(old := "") {
    global Folders, Folder, Tasks
    f    := old != "" ? old : Folder
    name := Trim(g.Prompt("Rename folder:", "Rename", f))
    if (name = "" || name = f || HasFolder(name))
        return

    for i, x in Folders
        if (x = f)
            Folders[i] := name

    for t in Tasks
        if (t.Folder = f)
            t.Folder := name

    Save()
    if (Folder = f)
        SetFolder(name)
    else
        RenderSide()
}

DeleteFolder(target := "") {
    global Folders, Folder, Tasks
    f := target != "" ? target : Folder
    if (Folders.Length <= 1)
        return g.Alert("You need at least one folder.", "Delete folder", "warning")

    n := 0
    for t in Tasks
        if (t.Folder = f)
            n++

    r := g.Dialog("Delete folder '" f "'" (n ? " and its " n " task(s)" : "") "?",
        "Delete folder", ["Delete", "Cancel"], {Kind: "warning", Danger: 1})
    if (r.Button != "Delete")
        return

    kept := []
    for t in Tasks
        if (t.Folder != f)
            kept.Push(t)
    Tasks := kept

    for i, x in Folders
        if (x = f) {
            Folders.RemoveAt(i)
            break
        }

    Save()
    SetFolder(Folder = f ? Folders[1] : Folder)
}
