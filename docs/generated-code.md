# The generated script

AxStudio exports a standalone `.ahk` file. This page covers what is in it and
the contract that lets you edit both the script and the design. The generator
is `studio/AxStudio.Gen.ahk`; the read-back is `studio/AxStudio.Merge.ahk`.

## Regions

Everything the studio writes sits between markers:

```ahk
;#region axstudio ui
g := AxGui({Title: "Demo", Width: 480, Height: 320})
;#endregion axstudio ui
```

Re-exporting refills those blocks and leaves every other line alone, so your
own `#Include`s, hotkeys, functions and comments survive. The markers follow
the VS Code convention, so the blocks fold there. In file order:

| Region | Contents | Written when |
|---|---|---|
| `compile` | Ahk2Exe directives (they must precede any real code) | the project has compile settings |
| `head` | `#Requires`, `#SingleInstance`, script settings, the project reference, `;@Ahk2Exe-Let U_AxLib`, `#Include`s | always |
| `ui` | the main window: `AxGui(...)`, its controls, its bars | always (`g := ""` if there is no main window) |
| `events` | wiring: `btn.OnEvent("Click", btn_Click)` | a main-window control has an event |
| `show` | start-up: binding init and sync, `g.Show()`, placement, hotstrings, timers, tray | always |
| `windows` | one builder function per other window | more than one window |
| `debug` | the agent that talks to the studio | **Run (F5) only, never Export** |
| `bindings` | `AxBindInit`, `AxBindSync`, `AxBindPull` | any variable or binding |
| `flows` | `Flow_*` functions and `<Window>State` | any rule or state |
| `args` `modes` `files` `adaptors` `conditions` `hotstrings` `timers` `hotkeys` `settings` `progevents` `watchers` `macros` `startup` | one region per feature: command-line arguments, modes, files, .NET and library adaptors, automation, settings, program events, folder watchers, macros, start with Windows | each when used |
| `start` | the placement, tab-order and default-key helpers the windows call | any window uses one |
| `handlers` | one function per event, plus one `<Window>Init` per window | always |
| `script.<window>` | your own functions, one block per window | always, even when empty |
| `opened` | `g.OnReady(...)` that runs `MainInit` | the main window has start-up code |

## An example

A main window, a modal Settings dialog, one two-way binding and one rule.
The `global` lines and the bindings region are shortened:

```ahk
;#region axstudio head
#Requires AutoHotkey v2.0
#SingleInstance Force
; Designed with AxStudio. The blocks marked #region axstudio are
; rewritten on every export. Anything outside them is left alone.
; @axstudio project="Demo.axs.json" v=1
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib
#Include ..\lib\AxGui.ahk
#Include ..\lib\AxAssets.ahk
#Include ..\lib\AxRich.ahk
#Include ..\lib\components\Button\AxButton.ahk
#Include ..\lib\components\Edit\AxEdit.ahk
#Include ..\lib\components\Text\AxText.ahk
;#endregion axstudio head

;#region axstudio ui
g := AxGui({Title: "Demo", Width: 520, Height: 340, Theme: "dark", Nav: false})
txt1 := g.AddText("vtxt1 Caption", "Who shall I greet?")
nameBox := g.AddEdit("vnameBox w260 y+12", "World")
greetBtn := g.AddButton("vgreetBtn y+12 Accent", "Greet")
settingsBtn := g.AddButton("vsettingsBtn x+", "Settings...")
g.AddStatusBar([{Id: "msg", Text: "Ready", Grow: true}])
;#endregion axstudio ui

;#region axstudio events
nameBox.OnEvent("Change", nameBox_Change)
greetBtn.OnEvent("Click", greetBtn_Click)
settingsBtn.OnEvent("Click", settingsBtn_Click)
;#endregion axstudio events

;#region axstudio show
AxBindBusy := false
AxBindInit()
AxBindSync()
g.Show()
;#endregion axstudio show

;#region axstudio windows
; ------------------------------------------------ Settings
gSettings := ""
SettingsResult := ""
; Modal. r := ShowSettings(seed) returns a Map of its outputs, or "" if it was closed.
ShowSettings(seed := "World") {
    global gSettings, SettingsResult, whoBox
    SettingsResult := ""
    gSettings := AxGui({Title: "Settings", Width: 380, Height: 220, Nav: false,
                        Resizable: false, EscapeCloses: true, ExitOnClose: false})
    whoBox := gSettings.AddEdit("vwhoBox w240", "")
    gSettings.OnClose((*) => SettingsResult := Map("who", whoBox.Text))
    AxBindSync()
    gSettings.OnReady((*) => SetTimer(() => (SettingsInit(seed), AxBindSync()), -1))
    gSettings.Show()
    while IsObject(gSettings) && !gSettings.Closing
        Sleep 20
    gSettings := ""
    return SettingsResult
}
;#endregion axstudio windows

;#region axstudio bindings
AxBindInit() {                    ; starting values
    global g, nameBox, whoBox, who, greeting, ...
    who := "World"
}

AxBindSync() {                    ; recompute, then push into controls
    global g, nameBox, whoBox, who, greeting, ...
    global AxBindBusy
    if AxBindBusy
        return
    AxBindBusy := true
    greeting := "Hello " who
    nameBox.Text := who
    if (IsObject(gSettings) && !gSettings.Closing)
        whoBox.Text := who
    AxBindBusy := false
}

AxBindPull(axWhich) {             ; read a control back, then AxBindSync()
    ...
}
;#endregion axstudio bindings

;#region axstudio flows
Flow_greetBtn_Click() {
    global g, nameBox, whoBox, who, greeting, ...
    g.Toast(greeting)
}
;#endregion axstudio flows

;#region axstudio handlers
nameBox_Change(ctl, value, el) {
    global g, nameBox, whoBox, who, greeting, ...
    AxBindPull("nameBox")
    ; nothing here yet
}

greetBtn_Click(ctl, ev, el) {
    global g, nameBox, whoBox, who, greeting, ...
    Flow_greetBtn_Click()
    ; nothing here yet
}

settingsBtn_Click(ctl, ev, el) {
    global g, nameBox, whoBox, who, greeting, ...
    r := ShowSettings(who)
}

MainInit() {
    global g, nameBox, whoBox, who, greeting, ...
    ; nothing here yet
}

SettingsInit(seed := "World") {
    global g, nameBox, whoBox, who, greeting, ...
    whoBox.Text := seed
}
;#endregion axstudio handlers

;#region axstudio script.main
;#endregion axstudio script.main

;#region axstudio script.settings
;#endregion axstudio script.settings
```

## Why it looks like that

- **Every named control gets a variable**, handler or not, because another
  control's handler usually needs it.
- **Every handler, rule and binding function declares the same globals**
  (every window, control and binding variable, eight per line), so any handler
  can reach any control without hand editing.
- **A window's inputs go to its `<Window>Init`, not its handlers.** AutoHotkey
  does not allow a parameter and a global of the same name, so
  `SettingsInit(seed)` takes `seed` as a parameter and leaves it off its
  `global` line.
- **Start-up code runs when the page exists.** `<Window>Init` is hooked to
  `OnReady` (the main window's in the `opened` region at the end of the file),
  because it fills lists and boxes, and code you add below `Show()` must run
  first.
- **`AxBindBusy` is set in `show`**, before the first sync reads it. Top-level
  code runs top to bottom and the `bindings` region comes later.
- **Every non-main window is a function**, and calling it is how one window
  opens another:

  | Kind | Function | Behaviour |
  |---|---|---|
  | `dialog` | `Show<Name>(inputs)` | modal; returns a `Map` of its outputs, read in `OnClose` while the controls still exist, or `""` if closed |
  | `window`, `tool` | `Show<Name>(inputs)` | returns the window; brings it forward if already open |
  | `code` | `Make<Name>(inputs)` | builds and returns the window without showing it; your code shows it |

- **Handler bodies are indented.** The read-back finds the end of a function by
  a closing brace in the first column.

## The round trip

Near the top of an exported script is a reference to the project:

```ahk
; @axstudio project="Demo.axs.json" v=1
```

It is a reference, not a copy, so the project stays the single source of
truth. `File > Open` accepts a `.ahk`, follows that line and opens the
project.

Before exporting over a file it wrote, the studio reads back:

- the body of each handler and each `<Window>Init`,
- each `script.<window>` block.

If any differ from the project, it lists them by name and offers to take them
in, so you can keep using the studio after editing by hand. These generated
lines are stripped; everything else in a body comes home:

```ahk
    global g, nameBox, ...      ; the globals
    Flow_greetBtn_Click()       ; the rules for this control and event
    ; nothing here yet          ; the placeholder for an empty body
```

## Editing an export by hand

| Do | Don't |
|---|---|
| Edit anything outside the region markers | Delete the `; @axstudio` line; Open needs it |
| Edit a handler or `Init` body (it is read back) | Rename a generated function |
| Add `#Include`s, hotkeys, helper functions | Move a line out of its region |
| Delete the whole `debug` region | Edit inside `ui`, `events`, `show` or `bindings`; they are regenerated |

The studio never overwrites a file it did not write without asking first.
