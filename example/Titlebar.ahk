#Requires AutoHotkey v2.0
#SingleInstance Force
#Include %A_LineFile%\..\..\lib\AxGui.ahk

; =============================================================================
;  Titlebar.ahk — the window's own chrome, built from AHK.
;
;  A title bar is normally an icon, a name and three buttons. TitleBar() opens
;  it up: two slots, one after the icon and one before the caption buttons, and
;  anything you like in them — a burger, a glyph, a word, an SVG, a picture, a
;  separator, a gap. An item can run a function, drop the window's own menu, or
;  open a popover of your markup.
;
;  This window wears the chromeless arrangement a modern editor uses: no icon,
;  no caption text, a burger that slides a pane out, a search field on the band
;  and an avatar at the right that opens a card on hover. Switch the stylesheet
;  from the Look page and the same items follow every sheet — they are chrome,
;  and each sheet dresses its own chrome.
; =============================================================================

Sheet := "win365", Collapsed := false, SearchOpen := false, TitleShown := false

; ── an avatar and a logo, drawn rather than loaded ───────────────────────────
Avatar() =>
    '<svg width="22" height="22" viewBox="0 0 22 22">'
  . '<defs><clipPath id="axAvClip"><circle cx="11" cy="11" r="11"/></clipPath></defs>'
  . '<circle cx="11" cy="11" r="11" fill="#ffffff" fill-opacity=".30"/>'
  . '<g clip-path="url(#axAvClip)" fill="#ffffff" fill-opacity=".92">'
  . '<circle cx="11" cy="8.6" r="3.7"/>'
  . '<path d="M2.6 22.5a8.4 8.4 0 0 1 16.8 0v4H2.6z"/></g></svg>'

Logo() =>
    '<svg width="17" height="17" viewBox="0 0 16 16">'
  . '<rect x="0" y="0" width="7" height="7" rx="1.4" fill="currentColor" opacity=".95"/>'
  . '<rect x="9" y="0" width="7" height="7" rx="1.4" fill="currentColor" opacity=".62"/>'
  . '<rect x="0" y="9" width="7" height="7" rx="1.4" fill="currentColor" opacity=".62"/>'
  . '<rect x="9" y="9" width="7" height="7" rx="1.4" fill="currentColor" opacity=".38"/></svg>'

; the pane the burger slides in and out, and the two lines of CSS that move it
Css := "
(
#shell { overflow: hidden; }
#sidebar {
    transition: width .26s cubic-bezier(.4,0,.2,1), padding .26s cubic-bezier(.4,0,.2,1);
    overflow: hidden; white-space: nowrap;
}
body.pane-out #sidebar { width: 0; padding-left: 0; padding-right: 0; }
body.pane-out .nav-item { opacity: 0; transition: opacity .1s ease; }
.nav-item { transition: opacity .2s ease .06s; }
.popcard { min-width: 210px; }
.popcard .who { font-weight: 600; margin-bottom: 2px; }
.popcard .sub { opacity: .65; font-size: 11px; }
.popcard hr { border: none; border-top: 1px solid rgba(128,128,128,.3); margin: 10px 0; }
.popcard .row { display: flex; align-items: center; margin-bottom: 6px; }
.popcard .row:last-child { margin-bottom: 0; }
.popcard .k { flex: 1; }
.popcard .v { opacity: .7; }

/* the save light: no width at all until it has something to report */
.axtb-item.saveind {
    max-width: 0; padding: 0; margin: 0; opacity: 0; overflow: hidden; white-space: nowrap;
    transition: max-width .28s cubic-bezier(.2,.8,.3,1), opacity .24s ease, padding .28s ease;
}
.axtb-item.saveind.on { max-width: 120px; padding: 0 8px; margin: 0 1px; opacity: 1; }
.axtb-item.saveind, .axtb-item.saveind:hover, .axtb-item.saveind.on { background: transparent; }
.saveind .dot {
    display: inline-block; width: 7px; height: 7px; border-radius: 50%;
    background: #3fca6b; margin-right: 7px; vertical-align: 1px;
}
.saveind.busy .dot { background: #f0a92b; }
.saveind .t { font-size: 12px; }
/* the magnifier and the collapse/expand live in base.css, so every sheet
   gets the same behaviour and only the colours differ */

/* the app grid behind the squares: three tiles of 86 + 3 + 3 = 276, and the
   grid's -3px margins take 6 of that back out, so the panel holds 270 and the
   tiles sit the same distance from both of its edges */
.waffle { width: 270px; }
.waffle .hd { font-weight: 600; margin: 0 4px 8px; }
.wf { display: flex; flex-wrap: wrap; margin: -3px; }
.wf .app {
    width: 86px; padding: 9px 4px; margin: 3px; border-radius: 6px;
    text-align: center; cursor: default;
}
.wf .app:hover { background: rgba(128,128,128,.20); }

/* reorder mode: the core arms it after data-hold ms and puts "sort-armed" on
   the grid, so the jiggle, the cursor and the hint are all just CSS */
.wf.sort-armed .app { cursor: move; -ms-animation: wob .55s ease-in-out infinite; animation: wob .55s ease-in-out infinite; }
.wf.sort-armed .app:nth-child(2n) { -ms-animation-delay: .09s; animation-delay: .09s; }
@keyframes wob {
    0%   { -ms-transform: rotate(-1.1deg); transform: rotate(-1.1deg); }
    50%  { -ms-transform: rotate(1.1deg);  transform: rotate(1.1deg); }
    100% { -ms-transform: rotate(-1.1deg); transform: rotate(-1.1deg); }
}
.wf .app.drag-hold { background: rgba(128,128,128,.28); }
.wf-hint { margin: 8px 4px 0; font-size: 11px; opacity: .6; }
.wf-hint .b { display: none; }
.wf.sort-armed ~ .wf-hint .a { display: none; }
.wf.sort-armed ~ .wf-hint .b { display: inline; }
.wf .app .sq {
    display: block; width: 30px; height: 30px; line-height: 30px; margin: 0 auto 6px;
    border-radius: 7px; color: #fff; font-size: 15px;
    font-family: "Segoe Fluent Icons", "Segoe MDL2 Assets";
}
.wf .app .nm { display: block; font-size: 11px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

/* the workspace switcher */
.wsp { width: 240px; }
.wsp .cur { display: flex; align-items: center; margin: 0 4px 10px; }
.wsp .cur .av {
    width: 34px; height: 34px; line-height: 34px; flex: none; margin-right: 10px;
    border-radius: 8px; text-align: center; font-weight: 600; background: #0f6cbd; color: #fff;
}
.wsp .cur .t { font-weight: 600; }
.wsp .cur .s { font-size: 11px; opacity: .6; }
.wsp .item { display: flex; align-items: center; height: 30px; padding: 0 6px; border-radius: 4px; }
.wsp .item:hover { background: rgba(128,128,128,.20); }
.wsp .item .tick {
    width: 20px; flex: none; font-size: 11px; opacity: 0;
    font-family: "Segoe Fluent Icons", "Segoe MDL2 Assets";
}
.wsp .item.on .tick { opacity: 1; }
.wsp .meta { font-size: 11px; opacity: .6; margin: 10px 6px 4px; }
.wsp .bar { height: 4px; margin: 0 6px; border-radius: 2px; background: rgba(128,128,128,.32); overflow: hidden; }
.wsp .bar i { display: block; height: 100%; background: #0f6cbd; }
)"

g := AxGui({
    Title: "Title bar",  AppName: "AxTitlebar",
    Width: 940, Height: 620, MinWidth: 620, MinHeight: 420,
    Theme: "dark", Stylesheet: Sheet, Icon: "none", Css: Css
})

; ─────────────────────────────────────────────────────────────────────────────
;  The title bar
; ─────────────────────────────────────────────────────────────────────────────
;  Left of the caption: a burger, the app's mark, a menu, a divider and the
;  search field. Right of it: a status word and an avatar with a popover.
;  ShowTitle: false — this window's name is in the page, not in the caption.

g.AddTitleBar([
    {Id: "burger", Kind: "burger", Class: "morph", On: true,
     Tip: "Hide the pane  (Ctrl+B)", Click: (*) => TogglePane()},

    ; the squares open the app grid, the name opens the workspace switcher --
    ; both Build:, so both are rebuilt from the live state every time
    ; no Width on either panel: each is as wide as what it holds (.waffle and
    ; .wsp say how wide), and the sheet puts its own padding round that
    {Id: "mark",   Kind: "svg", Svg: Logo(), Width: 26, Tip: "Apps",
     Popover: {On: "click", Build: Waffle}},
    {Id: "name",   Kind: "text", Text: "Workspace", Tip: "Switch workspace",
     Popover: {On: "click", Build: WorkspaceCard}},

    ; Menu takes the same items a context menu does, and drops the window's own
    ; menu overlay under the item — one look for every menu in the window.
    {Id: "file",   Kind: "text", Text: "File", Menu: () => [
        {Label: "&New tab",  Shortcut: "Ctrl+T", Click: (*) => g.Toast("A new tab would open here")},
        {Label: "&Open…",    Shortcut: "Ctrl+O", Click: (*) => g.Toast("Open")},
        "-",
        {Label: "Hide the &pane", Checked: Collapsed, Click: (*) => TogglePane()},
        "-",
        {Label: "E&xit", Click: (*) => g.Close()}]},

    {Kind: "sep"},

    ; A button that opens into a box. The box is always here -- CSS keeps it
    ; collapsed to 30px until the item is turned on, and animates the width
    ; between the two, so opening it is one class change rather than a redraw.
    {Id: "find", Kind: "html", Class: "axtb-search", Tip: "Search  (Ctrl+F)",
     Click: (*) => OpenSearch(),
     Html: '<span class="ico sico">&#xE721;</span>'
         . '<input type="text" id="q" placeholder="Search this workspace">'},

    ; Right-hand side. The save light is collapsed to nothing until there is
    ; something to say, then it opens, holds for a moment and closes again.
    {Id: "save", Side: "right", Kind: "html", Class: "saveind",
     Html: '<i class="dot"></i><span class="t">Saved</span>'},
    {Id: "bell",  Side: "right", Glyph: "EA8F", Tip: "Notifications",
     Popover: {On: "click", Build: NotifyCard}},
    {Id: "me",    Side: "right", Kind: "svg", Svg: Avatar(), Tip: "Account",
     Popover: {On: "hover", Build: AccountCard}}
], {ShowTitle: false})

; ─────────────────────────────────────────────────────────────────────────────
;  Popover content
; ─────────────────────────────────────────────────────────────────────────────
;  Build runs every time the panel opens, so it shows what is current. Anything
;  inside is ordinary page markup: On(), Value() and OnValue() reach it exactly
;  as they reach the page, which is what OnOpen is for.

AccountCard() =>
    '<div class="popcard">'
  . '<div class="who">Sam Okonkwo</div>'
  . '<div class="sub">sam@example.org</div>'
  . '<hr>'
  . '<div class="row"><span class="k">Pane</span><span class="v" id="pvPane">'
  . (Collapsed ? "hidden" : "shown") '</span></div>'
  . '<div class="row"><span class="k">Sheet</span><span class="v">' Sheet '</span></div>'
  . '<div class="row"><span class="k">Theme</span><span class="v">' g.Theme '</span></div>'
  . '<hr>'
  . '<span class="btn" id="pvSign">Sign out</span>'
  . '</div>'

NotifyCard() =>
    '<div class="popcard">'
  . '<div class="who">3 notifications</div>'
  . '<hr>'
  . '<div class="row"><span class="k">Build finished</span><span class="v">2m</span></div>'
  . '<div class="row"><span class="k">Review requested</span><span class="v">1h</span></div>'
  . '<div class="row"><span class="k">Weekly digest</span><span class="v">Mon</span></div>'
  . '</div>'

Apps := [["E80F", "Home", "#0f6cbd"], ["E715", "Mail", "#0a7f5c"],
         ["E787", "Calendar", "#c50f1f"], ["E8B7", "Files", "#8764b8"],
         ["E70B", "Notes", "#ca5010"], ["E8BD", "Chat", "#038387"],
         ["E77B", "People", "#0f6cbd"], ["E73A", "Tasks", "#107c10"],
         ["E713", "Settings", "#605e5c"]]

Workspaces := ["Workspace", "Design system", "Q3 planning"]
Current := "Workspace"
JustDragged := false

Waffle() {
    ; data-role="sortable" + data-hold: the tiles reorder after a press and
    ; hold, and OnValue below is told the new order when one is dropped
    h := '<div class="waffle"><div class="hd">Apps</div>'
      .  '<div class="wf" id="wfGrid" data-role="sortable" data-axis="x" data-hold="500">'
    for i, a in Apps
        h .= '<div class="app drag-item" id="app' i '" data-value="' a[2] '">'
          .  '<span class="sq" style="background:' a[3] '">&#x' a[1] ';</span>'
          .  '<span class="nm">' a[2] '</span></div>'
    return h '</div>'
         .  '<div class="wf-hint"><span class="a">Hold an icon to reorder</span>'
         .  '<span class="b">Reorder mode &#8212; drag to move</span></div></div>'
}

WorkspaceCard() {
    h := '<div class="wsp"><div class="cur">'
      .  '<div class="av">' SubStr(Current, 1, 1) '</div>'
      .  '<div><div class="t">' Current '</div><div class="s">3 members</div></div></div>'
    for i, w in Workspaces
        h .= '<div class="item' (w = Current ? " on" : "") '" id="ws' i '">'
          .  '<span class="tick">&#xE73E;</span>' w '</div>'
    return h '<div class="meta">Storage &#183; 62% of 5 GB</div>'
         .  '<div class="bar"><i style="width:62%"></i></div></div>'
}

; The panels are rebuilt on every open, but their controls are bound once and
; by id, so a handler registered here works for every panel that ever carries
; that element -- which is the whole trick to wiring a popover.
; bound by id, but the name is read off the element, so a tile that has been
; dragged somewhere else still opens the app it is showing
for i, a in Apps
    g.On("click", "app" i, (el, ev) => LaunchApp(el.getAttribute("data-value")))
; the sortable reports the new order as its value; the array follows it, so the
; next time the panel is built the tiles come back where they were left
g.OnValue("wfGrid", (v, *) => ReorderApps(v))
for i, w in Workspaces
    g.On("click", "ws" i, SwitchWorkspace.Bind(w))
; ── the search box ───────────────────────────────────────────────────────────
; One item, two shapes. Ctrl+F reaches this even though Ctrl+F is also
; Trident's own Find: the library cancels the browser's meaning of the key but
; lets the event carry on to the page (see AxWindow._BlockBrowserKey).

OpenSearch() {
    global SearchOpen
    if SearchOpen
        return                                 ; clicking inside must not move the caret
    SearchOpen := true
    g.BodyClass("axtb-notitle", true)          ; the caption text steps aside
    g.TitleItem("find", {On: true, Tip: ""})   ; and the box opens on the class
    g.Focus("q")
    g.Status("msg", "Search open  --  Escape closes it")
}

CloseSearch() {
    global SearchOpen
    if !SearchOpen
        return
    SearchOpen := false
    try g.El("q").blur()                       ; or the caret blinks on in the button
    try g.Value("q", "")                       ; next open starts empty
    g.BodyClass("axtb-notitle", !TitleShown)   ; back to whatever the switch says
    g.TitleItem("find", {On: false, Tip: "Search  (Ctrl+F)"})
    g.Status("msg", "Ready")
}

; ── the save light ───────────────────────────────────────────────────────────
; An indicator, not a label: it opens, says one thing, and closes itself.

Saved(text := "Saved", busy := false) {
    g.TitleItem("save", {On: true, Class: busy ? "saveind busy" : "saveind",
        Html: '<i class="dot"></i><span class="t">' text '</span>'})
    SetTimer(HideSaved, -2600)                 ; a repeat call restarts the wait
}
HideSaved() => g.TitleItem("save", {On: false})

g.On("click", "pvSign", (*) => (g.ClosePopover(), g.Toast("Signed out")))

LaunchApp(name, *) {
    if JustDragged                         ; the mouseup that ended a reorder
        return
    g.ClosePopover()
    g.Status("msg", name)
    g.Toast(name " would open here")
}

ReorderApps(order) {
    global Apps, JustDragged
    JustDragged := true                          ; the click that follows a
    SetTimer(() => JustDragged := false, -250)   ; drop is not a click on a tile
    out := []
    for name in (IsObject(order) ? order : StrSplit(order, "|"))
        for a in Apps
            if (a[2] = name)
                out.Push(a)
    if (out.Length = Apps.Length)
        Apps := out
    g.Status("msg", "Apps reordered")
    Saved("Layout saved")
}

SwitchWorkspace(name, *) {
    global Current
    Current := name
    g.TitleItem("name", {Text: name})       ; the caption follows the choice
    g.ClosePopover()
    g.Status("msg", "Workspace: " name)
    Saved("Switched")
}

; ─────────────────────────────────────────────────────────────────────────────
;  The page
; ─────────────────────────────────────────────────────────────────────────────
g.AddPage("home", "Chrome", "E7C4")
g.AddText("", "The window's own chrome")
g.AddText("Caption", "Everything above this page is TitleBar() and nothing else")

g.AddCard()
g.AddRow("Icon=E700", "The burger", "Toggles the pane, and morphs into a cross while it is on")
g.AddButton("", "Toggle").OnClick((*) => TogglePane())
g.Use()
g.AddCard()
g.AddRow("Icon=E721", "The search field", "A button until Ctrl+F asks for it, then it opens into a box")
g.AddButton("", "Open").OnClick((*) => OpenSearch())
g.Use()
g.AddCard()
g.AddRow("Icon=E80A", "The squares", "App tiles, three across -- press and hold one to reorder the grid")
g.AddButton("", "Open").OnClick((*) => g.ShowPopover("mark"))
g.Use()
g.AddCard()
g.AddRow("Icon=E902", "The name", "A workspace switcher -- picking one rewrites the title-bar item")
g.AddButton("", "Open").OnClick((*) => g.ShowPopover("name"))
g.Use()
g.AddCard()
g.AddRow("Icon=E77B", "The avatar", "Opens a popover on hover; the bell opens one on click")
g.AddButton("", "Show it").OnClick((*) => g.ShowPopover("me"))
g.Use()
g.AddCard()
g.AddRow("Icon=E930", "The save light", "Opens, reports, and closes itself -- an indicator, not a label")
g.AddButton("", "Save").OnClick((*) => Saved())
g.Use()
g.AddCard()
g.AddRow("Icon=E8BC", "The caption text", "Hidden here (ShowTitle: false) — the name lives in the bar instead")
g.AddSwitch("vShowTitle", "Show it").OnChange((c, v, *) => ShowCaption(v))
g.Use()

g.AddPage("look", "Look", "E790")
g.AddText("", "Chrome is the stylesheet's")
g.AddText("Caption", "The same items, dressed by each sheet")
g.AddCard()
g.AddRow("Icon=E790", "Stylesheet", "Every sheet styles the title-bar items and the popover itself")
g.AddDDL("vSheet w190 Choose1",
    "win365:Windows 365|cyber:Cyber|rpg:RPG|cozy:Cozy|win11:Windows 11|precision:Precision|inset:Inset|brutalist:Brutalist"
  . "|aurora:Aurora|instrument:Instrument|winxp:Windows XP|win98:Windows 9x")
    .OnChange((c, v, *) => SetSheet(v))
g.Use()
g.AddCard()
g.AddRow("Icon=E793", "Theme", "Light and dark, on whichever sheet is up")
g.AddSegmented("vTheme Choose1", "dark:Dark|light:Light").OnChange((c, v, *) => SetTheme(v))
g.Use()
g.AddCard()
g.AddRow("Icon=E790", "Accent", "The sheet is re-hued, chrome and all")
g.AddPalette("vAccent Value=#0f6cbd",
    "#0f6cbd,#c50f1f,#107c10,#8764b8,#ca5010,#038387").OnChange((c, v, *) => g.SetAccent(v))
g.Use()

g.AddPage("api", "Items", "E8FD")
g.AddText("", "One call")
g.AddHtml("", '<div class="console" data-selectable>'
    . "g.AddTitleBar([`n"
    . "    {Id: &quot;burger&quot;, Kind: &quot;burger&quot;, Class: &quot;morph&quot;, Toggle: true,`n"
    . "     Click: (*) =&gt; TogglePane()},`n"
    . "    {Id: &quot;name&quot;, Text: &quot;Workspace&quot;},`n"
    . "    {Id: &quot;file&quot;, Text: &quot;File&quot;, Menu: () =&gt; [ ... ]},`n"
    . "    {Kind: &quot;sep&quot;},`n"
    . "    {Id: &quot;find&quot;, Kind: &quot;html&quot;, Class: &quot;axtb-search&quot;, Html: &quot;&lt;input ...&gt;&quot;},`n"
    . "    {Id: &quot;me&quot;, Side: &quot;right&quot;, Kind: &quot;svg&quot;, Svg: Avatar(),`n"
    . "     Popover: {On: &quot;hover&quot;, Build: AccountCard}}`n"
    . "], {ShowTitle: false})</div>")
g.AddText("Caption", "Changing one, later")
g.AddHtml("", '<div class="console" data-selectable>'
    . "g.TitleItem(&quot;find&quot;, {Kind: &quot;html&quot;, Html: box})`n"
    . "g.TitleItem(&quot;burger&quot;, {On: true})        &#8212; animates, does not redraw`n"
    . "g.TitleOn(&quot;burger&quot;)                      &#8212; true`n"
    . "g.ShowPopover(&quot;me&quot;)  g.ClosePopover()</div>")

g.AddStatusBar([{Id: "msg", Text: "Ready", Icon: "E930", Grow: true},
                {Id: "pane", Text: "pane shown", Width: 120, Dim: true}])

g.On("keydown", "*", (el, ev) => (ev.ctrlKey && ev.keyCode = 66) ? (TogglePane(), ev.returnValue := false)
                              : (ev.ctrlKey && ev.keyCode = 70) ? (OpenSearch(), g.Focus("q"), ev.returnValue := false)
                              : (ev.keyCode = 27 && SearchOpen) ? CloseSearch() : "")
; Enter searches and puts the box away again; leaving an empty box closes it
g.On("keydown", "q", (el, ev) => ev.keyCode = 13 ? RunSearch() : "")
g.On("focusin",  "q", (*) => OpenSearch())
g.On("focusout", "q", (*) => CloseIfEmpty())

g.Show()
return

; ─────────────────────────────────────────────────────────────────────────────
;  Behaviour
; ─────────────────────────────────────────────────────────────────────────────
; leaving an empty box puts it away again; a box with something in it stays
CloseIfEmpty() {
    if !SearchOpen
        return
    v := ""
    try v := g.Value("q")
    if (v = "")
        CloseSearch()
}

RunSearch() {
    q := g.Value("q")
    CloseSearch()
    if (q != "") {
        g.Toast('Searching for "' q '"')
        Saved("Indexed")
    }
}

TogglePane() {
    global Collapsed
    Collapsed := !Collapsed
    g.BodyClass("pane-out", Collapsed)
    ; On tracks the PANE, not the toggle: with the pane out there is something
    ; to close, so the burger is a cross; with it away the cross would be an X
    ; you press to bring something back, which reads backwards. Patched in
    ; place, so it animates between the two rather than being redrawn.
    g.TitleItem("burger", {On: !Collapsed, Tip: Collapsed ? "Show the pane  (Ctrl+B)"
                                                          : "Hide the pane  (Ctrl+B)"})
    g.Status("pane", Collapsed ? "pane hidden" : "pane shown")
}

ShowCaption(on) {
    global TitleShown
    TitleShown := on
    if !SearchOpen                             ; the search box is holding it
        g.BodyClass("axtb-notitle", !on)
    g.Status("msg", on ? "Caption text shown" : "Caption text hidden")
}

SetSheet(name) {
    global Sheet
    Sheet := name
    g.SetStylesheet(name)
    g.Status("msg", "Stylesheet: " name)
}

SetTheme(mode) {
    g.SetTheme(mode)
    g.Status("msg", "Theme: " mode)
}
