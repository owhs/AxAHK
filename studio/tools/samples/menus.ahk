#Requires AutoHotkey v2.0
#SingleInstance Force
; A sample for the importer (probe step 51): a window with a right-click
; menu on its text box and one for anywhere in it, and a tray icon with its
; own menu -- a submenu, pictures from Windows' files, a greyed-out item,
; the bold one and what one click does.

A_IconTip := "Notes"
TraySetIcon("shell32.dll", 71)

tools := Menu()
tools.Add("Open the folder", (*) => Run(A_ScriptDir))
tools.Add()
tools.Add("Reload", (*) => Reload())

A_TrayMenu.Delete()
A_TrayMenu.Add("Show", ShowMain)
A_TrayMenu.Add("Tools", tools)
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.SetIcon("Exit", "shell32.dll", 28)
A_TrayMenu.Default := "Show"
A_TrayMenu.ClickCount := 1

textMenu := Menu()
textMenu.Add("Cut`tCtrl+X", (*) => Send("^x"))
textMenu.Add("Copy`tCtrl+C", (*) => Send("^c"))
textMenu.Add("Paste`tCtrl+V", (*) => Send("^v"))

winMenu := Menu()
winMenu.Add("About", (*) => MsgBox("Notes, a sample"))
winMenu.Add("Quit", (*) => ExitApp())

g := Gui("+Resize", "Notes")
g.SetFont("s10", "Segoe UI")
notes := g.Add("Edit", "vNotes w400 h200")
notes.OnEvent("ContextMenu", (*) => textMenu.Show())
g.OnEvent("ContextMenu", (*) => winMenu.Show())
g.Add("Button", "vSave w80", "Save").OnEvent("Click", (*) => FileAppend(notes.Value, "notes.txt"))
g.Show()

ShowMain(*) {
    g.Show()
}
