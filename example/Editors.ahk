#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes, the editors' scripts and styles
#Include ..\lib\AxGui.ahk
#Include ..\lib\AxAssets.ahk

; =============================================================================
;  Editors.ahk -- the two editors: code and rich text.
;
;  Code: coloured as you type, suggestions ranked as you type (Ctrl+Space
;  for all of them) with a parameters card after "(", hovers, AutoHotkey's
;  own /validate marking the problems (F8 goes to the next), folding, find
;  and replace with patterns (Ctrl+F / Ctrl+H), ":42" to a line and "@name"
;  to what the text defines (Ctrl+G / Ctrl+Shift+O), a map of the text on
;  the right, an outline under it -- and, when VS Code has thqby's
;  AutoHotkey v2 language server, that server behind it too. Pick another
;  language and its own example comes up; what you wrote in each is kept.
;
;  Rich text: a toolbar, Markdown as you type ("# ", "- ", **bold**), "/" on
;  an empty line for a menu of blocks, tables with their own bar, Ctrl+Enter
;  out of a table or a quote, find and replace; its text comes and goes as
;  Markdown, and saves as Markdown or as a web page.
;
;  Closing with unsaved notes asks first -- Save, Don't save or Cancel --
;  however the window is closed: its close button, a double-click on its
;  icon, Alt+F4, the taskbar, or the tray's Exit (g.OnBeforeClose, g.Dirty).
; =============================================================================

Samples := Map()
Samples["ahk"] := "
(
; Ctrl+Space suggests; type Ms and Tab, then the parameters show
class Greeter {
    __New(name) {
        this.Name := name
    }
    Hello() {
        MsgBox("Hello, " this.Name)
    }
}

hi := Greeter("World")
hi.Hello()

^j:: {
    Send("{Text}typed by a hotkey")
}
)"
Samples["js"] := "
(
// Ctrl+Space suggests; "console." offers its words
function greet(name) {
    const text = "Hello, " + name;
    console.log(text);
    return text.length;
}

class Counter {
    constructor() {
        this.n = 0;
    }
    add(by) {
        this.n += by;
        return this;
    }
}

greet("World");
)"
Samples["json"] := "
(
{
  "name": "Editors",
  "version": 2,
  "features": ["colours", "folding", "suggestions", "find and replace"],
  "window": { "width": 1100, "height": 760, "theme": "dark" },
  "ready": true
}
)"
Samples["css"] := "
(
/* a card */
.card {
    padding: 12px 16px;
    border-radius: 8px;
    background: #1e1e1e;
    color: #d4d4d4;
}

.card:hover {
    box-shadow: 0 4px 12px rgba(0, 0, 0, .35);
}

@media (max-width: 600px) {
    .card { padding: 8px; }
}
)"
Samples["html"] := "
(
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>A page</title>
</head>
<body>
  <!-- a heading and a list -->
  <h1 id="top">Hello</h1>
  <ul class="list">
    <li><a href="https://example.com">A link</a></li>
    <li>Two &amp; three</li>
  </ul>
</body>
</html>
)"
Samples["ini"] := "
(
; settings, a section each
[window]
width=1100
height=760
theme=dark

[editor]
lang=ahk
wrap=0
)"
Samples["md"] := "
(
# Notes

Headings fold, **bold** and *italic* show as they are, and a list goes on
by itself when you press Enter:

- one
- two

## Code

``````
MsgBox("hi")
``````
)"
Samples["ps1"] := "
(
# the biggest files here
function Get-Biggest {
    param([string]$Path = ".", [int]$Count = 10)
    Get-ChildItem $Path -File -Recurse |
        Sort-Object Length -Descending |
        Select-Object -First $Count Name, Length
}

Get-Biggest -Count 5
)"
Samples["py"] := "
(
# a small class and a loop
class Counter:
    def __init__(self):
        self.n = 0

    def add(self, by=1):
        self.n += by
        return self


def main():
    c = Counter()
    for i in range(10):
        c.add(i)
    print("total", c.n)


if __name__ == "__main__":
    main()
)"
Samples["sql"] := "
(
-- orders by customer
CREATE TABLE orders (id INT PRIMARY KEY, customer TEXT, total REAL);

SELECT customer, COUNT(*) AS n, SUM(total) AS spent
FROM orders
WHERE total > 10
GROUP BY customer
ORDER BY spent DESC
LIMIT 5;
)"
Samples["plain"] := "
(
Plain text: no colours, but everything else --
    folding by indent,
    find and replace (Ctrl+H),
    Alt+Up and Alt+Down to move a line,
    Ctrl+D to copy one.
)"
Notes := "
(
# Notes

The toolbar does **bold**, *italic*, lists, links and tables -- and so does
typing: "# " makes a heading, "- " a list, "/" on an empty line a menu.

- one thing
- another

| Tool | Does |
| --- | --- |
| Save | writes notes.md beside the script |
| Web page | writes notes.html |
)"

g := AxGui({Title: "Editors", Width: 1100, Height: 780, Theme: "dark"})

g.AddPage("pgCode", "Code", "E943")
g.AddText("Caption", "A code editor -- pick a language and its example comes up")
lang := g.AddDDL("vlang w150 Choose1", "ahk:AutoHotkey|js:JavaScript|json:JSON|css:CSS|html:HTML|ini:INI|md:Markdown|ps1:PowerShell|py:Python|sql:SQL|plain:Plain text")
theme := g.AddDDL("vtheme x+8 w150 Choose1", "auto:As the window|dark:Dark|light:Light|monokai:Monokai|solarized:Solarized|dracula:Dracula|contrast:High contrast")
g.AddButton("x+8", "Fold all").OnClick((*) => code.FoldAll(true))
g.AddButton("x+8", "Open all").OnClick((*) => code.FoldAll(false))
g.AddButton("x+8", "Find").OnClick((*) => code.Find(""))
g.AddButton("x+8", "Replace").OnClick((*) => code.Find("", true))
server := g.AddButton("x+8", "Use the language server")
code := g.AddCodeEditor("vcode h300 Grow Lang=ahk Theme=auto", Samples["ahk"])
tree := g.AddListView("voutline h150 -Multi NoSortHdr", ["What", "Kind", "Line"])
said := g.AddText("vsaid Hint", "Double-click an outline row to go there.")

g.AddPage("pgNotes", "Rich text", "E8D2")
g.AddText("Caption", "A rich text editor, in Markdown")
g.AddButton("", "Save").OnClick((*) => SaveNotes())
g.AddButton("x+8", "Web page").OnClick((*) => (notes.SaveHtml(A_ScriptDir "\notes.html", "Notes"), g.Toast("Written notes.html")))
g.AddButton("x+8", "Insert a table").OnClick((*) => notes.InsertTable(3, 3))
g.AddButton("x+8", "Paper").OnClick((*) => g.El("notes").classList.toggle("axrt-paper"))
askSw := g.AddSwitch("vaskSw x+16 Checked", "Ask before closing")
notes := g.AddRichText("vnotes h300 Grow Tools=full Format=md", FileExist(A_ScriptDir "\notes.md") ? FileRead(A_ScriptDir "\notes.md", "UTF-8") : Notes)
SavedNotes := ""                               ; the notes as last saved (or loaded)
md := g.AddCodeEditor("vmd h150 Preset=notes ReadOnly", "")

; --- the code editor's services
code.UseAhk({Lint: true})
code.OnEvent("Change", (*) => ShowOutline())
code.OnSave((text, *) => g.Toast("Ctrl+S: " StrLen(text) " characters"))
lang.OnChange((ctl, v, *) => SwitchTo(v))
theme.OnChange((ctl, v, *) => code.SetTheme(v))
tree.OnEvent("DoubleClick", (lv, row) => row ? code.GoTo(Integer(lv.GetText(row, 3))) : "")
server.OnClick((*) => UseServer())
notes.OnEvent("Change", (ctl, value, *) => NotesChanged(value))
notes.OnSave((*) => SaveNotes())

; once the page is there: the editors are made when it is
g.OnReady((*) => (tree.ModifyCol(1, 240), tree.ModifyCol(2, 110), tree.ModifyCol(3, 70), ShowOutline(),
                  md.Value := notes.Value, SetSaved()))
; Asked before the window closes, whichever way it is closed -- `why` says
; which: button, icon, system (Alt+F4, the taskbar), escape, exit (the tray),
; code. True keeps the window open. (g.AskBeforeClose(SaveNotes) is this
; question ready made; this one also listens to the switch.)
g.OnBeforeClose(BeforeClose)
g.Show()

BeforeClose(win, why) {
    if (!askSw.Value || !win.Dirty)
        return false
    r := win.Dialog("The notes have changes that are not saved yet. Save them before closing?", "Editors",
                    ["Save", "Don't save", "Cancel"], {Kind: "warning"})
    if (r.Button = "Save")
        SaveNotes()
    return (r.Button != "Save" && r.Button != "Don't save")        ; Cancel, or Escape: stay
}
; unsaved: the title shows a dot while the notes differ from what was saved
NotesChanged(value) {
    md.Value := value
    g.Dirty := (value != SavedNotes)
}
SetSaved() {
    global SavedNotes := notes.Value
    g.Dirty := false
}

; another language: its example (or what you wrote in it before), coloured
; and suggested as that language, with its own outline
SwitchTo(v) {
    static texts := Map(), was := "ahk"
    texts[was] := code.Value
    was := v
    code.SetLanguage(v)
    code.Load(texts.Has(v) ? texts[v] : Samples.Has(v) ? Samples[v] : "")
    ShowOutline()
    said.Text := (v = "ahk") ? "Double-click an outline row to go there." : "AutoHotkey's checks rest while it is " lang.Text "."
}
; what the code defines, in the list under it
ShowOutline() {
    tree.Opt("-Redraw")
    tree.Delete()
    for s in code.Symbols()
        tree.Add(, s["name"], s["kind"], s["line"])
    tree.Opt("+Redraw")
}
SaveNotes() {
    notes.SaveMarkdown(A_ScriptDir "\notes.md")
    SetSaved()
    g.Toast("Written notes.md")
}
; thqby's AutoHotkey v2 language server, if VS Code has it
UseServer() {
    static lsp := ""
    cmd := AxLsp.FindAhk2()
    if (cmd = "")
        return g.Toast("No AutoHotkey language server found -- the built-in one stays.")
    if IsObject(lsp)
        return g.Toast("The language server is already on.")
    lsp := AxLsp(cmd).Start(A_ScriptDir)
    code.UseLsp(lsp)
    said.Text := "Suggestions, hovers and problems now come from the language server too."
    OnExit((*) => lsp.Stop())
}
