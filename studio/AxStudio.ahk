#Requires AutoHotkey v2.0
#SingleInstance Force

; =============================================================================
;  AxStudio -- a WYSIWYG designer for AxGui, written with AxGui.
;
;      studio\AxStudio.ahk            this file: includes and start
;      studio\AxJson.ahk              JSON for the project file
;      studio\AxStudio.Catalog.ahk    every control the toolbox offers
;      studio\AxStudio.Comp.ahk       component packs, scanned from their folders
;      studio\AxStudio.Store.ahk      the component viewer, and installing one
;      studio\AxStudio.Model.ahk      the design tree, and undo
;      studio\AxStudio.Lit.ahk        writing AutoHotkey out as text
;      studio\AxStudio.Chrome.ahk     title bar items, menu bar, status bar
;      studio\AxStudio.Icons.ahk      the named glyphs, and the picker
;      studio\AxStudio.Merge.ahk      the round trip: regions, and reading one back
;      studio\AxStudio.Debug.ahk      the agent Run puts in the script, and the log
;      studio\AxStudio.Theme.ahk      restyling a design without writing CSS
;      studio\AxStudio.Lint.ahk       what is wrong with the design
;      studio\AxStudio.Acts.ahk       the Actions row: what a control needs next
;      studio\AxStudio.Flow.ahk       rules and states, without writing code
;      studio\AxStudio.Bind.ahk       data binding, and the engine it needs
;      studio\templates\*.axs.json    the starting points, as project files
;      studio\AxStudio.Gen.ahk        tree -> canvas markup, tree -> AutoHotkey
;      studio\AxStudio.RibbonUi.ahk   building a ribbon by pointing at it
;      studio\AxStudio.Panes.ahk      toolbox, outline, properties, events
;      studio\AxStudio.App.ahk        the window and its commands
;      studio\AxStudio.Pkg.ahk        libraries, through Aris (packages\patch.json over its list)
;      studio\AxStudio.PkgUi.ahk      App > Libraries, and the element picker (tools\AxUiaPick.ahk)
;      studio\AxStudio.Update.ahk     is there anything newer: AxGui, the studio, Aris, the libraries
;      studio\AxStudio.Map.ahk        Map: the whole program as a map (AxStudio.Map.js draws it)
;      studio\AxStudio.Steps.ahk      any piece of code as steps, read and changed as text
;      studio\AxStudio.StepsUi.ahk    the Steps workspace, and the one form steps are made in (AxStudio.Steps.js)
;      studio\AxStudio.Files.ahk      App > Files, the file manager
;      studio\AxStudio.ImportLogic.ahk  what an imported script does, as the studio's lists
;      studio\AxStudio.DotNet.ahk     .NET through AHK#: adaptors, NuGet, tools\AxNetScan.ps1
;      studio\AxStudio.DotNetUi.ahk   Libraries > .NET and In this program
;      studio\AxStudio.Arrange.ahk    Arrange what is inside a box
;      studio\AxStudio.Titlebar.ahk   the studio's own title bar: menus, search, run, cards
;      studio\AxStudio.Menus.ahk      right-click menus, the menu bar and the tray's, made by pointing
;      studio\AxStudio.js             pointer work: drag, snap, guides, HUD
;      studio\AxStudio.css            the studio's own chrome
;
;  Run this file. Everything else is loaded from beside it.
; =============================================================================

#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\..\lib\AxRichAll.ahk
#Include %A_LineFile%\..\AxJson.ahk
#Include %A_LineFile%\..\AxStudio.Lit.ahk
#Include %A_LineFile%\..\AxStudio.Icons.ahk
#Include %A_LineFile%\..\AxStudio.Catalog.ahk
#Include %A_LineFile%\..\AxStudio.Comp.ahk
#Include %A_LineFile%\..\AxStudio.Store.ahk
#Include %A_LineFile%\..\AxStudio.Model.ahk
#Include %A_LineFile%\..\AxStudio.Templates.ahk
#Include %A_LineFile%\..\AxStudio.Complete.ahk
#Include %A_LineFile%\..\AxStudio.Chrome.ahk
#Include %A_LineFile%\..\AxStudio.Merge.ahk
#Include %A_LineFile%\..\AxStudio.Debug.ahk
#Include %A_LineFile%\..\AxStudio.Theme.ahk
#Include %A_LineFile%\..\AxStudio.Gen.ahk
#Include %A_LineFile%\..\AxStudio.Lint.ahk
#Include %A_LineFile%\..\AxStudio.Acts.ahk
#Include %A_LineFile%\..\AxStudio.Flow.ahk
#Include %A_LineFile%\..\AxStudio.Bind.ahk
#Include %A_LineFile%\..\AxStudio.RibbonUi.ahk
#Include %A_LineFile%\..\AxStudio.Panes.ahk
#Include %A_LineFile%\..\AxStudio.Look.ahk
#Include %A_LineFile%\..\AxStudio.Auto.ahk
#Include %A_LineFile%\..\AxStudio.Auto2.ahk
#Include %A_LineFile%\..\AxStudio.Steps.ahk
#Include %A_LineFile%\..\AxStudio.StepsUi.ahk
#Include %A_LineFile%\..\AxStudio.Titlebar.ahk
#Include %A_LineFile%\..\AxStudio.App.ahk
#Include %A_LineFile%\..\AxStudio.Update.ahk

AxStudio().Run()
