# Architecture

- **AxGui** (`lib/`) builds Windows apps in AutoHotkey v2: a borderless
  window whose contents are HTML and CSS rendered by an embedded Trident
  (IE11) control. AutoHotkey owns all behaviour and talks to the live DOM over
  COM; apps contain no JavaScript.
- **AxStudio** (`studio/`) is a WYSIWYG designer built with AxGui. It saves
  projects as JSON and exports standalone `.ahk` scripts. The library does not
  know it exists.

```
  your application  ──uses──▶  AxGui  ──renders with──▶  Trident (IE11)
                                 ▲
                                 │ builds with, and generates for
                             AxStudio
```

This page is for changing the library or the studio. To build windows with
it, read [guide.md](guide.md).

---

## Part 1: the library

### Layers

| Layer | Files | What it does |
|---|---|---|
| Window core | `lib/AxWindow.ahk` | Creates the borderless window, hosts the browser control, injects the frame, wires the COM event sinks, exposes a DOM API |
| Mixins | `lib/AxWindow.*.ahk` | Components, overlays, bars, title bar, embedding, media, drag and drop, folded into `AxWindow` at load time |
| Builder | `lib/AxGui.ahk` | Extends `AxWindow` with the container mechanics and `OnEvent` |
| Controls | `lib/components/**` | Every control, one folder each (`Button`, `Edit`, ...) |
| Markup | `lib/AxTags.ahk` | The window's own `<ax-*>` tags; each control renders its own |
| Component layer | `lib/AxRich.ahk` | What a component registers itself with |
| Look | `lib/themes/*.css` | One class contract, several complete looks |
| System | `lib/AxSys.ahk` | DWM, icons, toasts, folder picker, per-app volume, IE feature switches |

### Mixins

`AxWindow.Mixin(cls)` copies a class's members onto `AxWindow.Prototype` at
load time:

```ahk
AxWindow.Mixin(AxWindowComponents)
AxWindow.Mixin(AxWindowOverlays)
AxWindow.Mixin(AxWindowBars)
; ...
```

So `g.Dialog(...)` lives in `AxWindow.Overlays.ahk`. If a method is not on
`AxWindow`, look in the mixins.

### How a control reaches the screen

```ahk
g := AxGui({Title: "Demo", Width: 480, Height: 320})
btn := g.AddButton("vsave w120 Accent Icon=E74E", "Save")
btn.OnEvent("Click", (*) => g.Toast("Saved"))
g.Show()
```

1. `AddButton` parses the option string.
2. It produces HTML (`<div class="btn accent" id="save">…</div>`) and appends
   it to the current container.
3. `OnEvent("Click", fn)` registers `fn` under the element id `save`.
4. `Show()` writes the document, waits for `DocumentComplete` and connects the
   COM sinks. Its order keeps startup fast:
   - The `<ax-*>` tags are expanded in the page text (cached in
     `%TEMP%\AxGui`), and every page except the visible one is cut out
     (`AxWindow._SplitPages`), so the browser parses one page, not thirteen.
   - Stylesheets and overlay markup are already in that text. `_PutCss` skips
     a write of unchanged text, because every write restyles the whole page.
   - `_Wire`, the first ready callback, adds the bars and handlers, **shows and
     paints the window**, puts the other pages back (`_FillPages`), then adds
     tooltips, hotkeys and embedded ActiveX controls.
   - Component ready callbacks and your `OnReady` run next, with the window
     on screen. `Show()` returns when they finish.

   So set size, position or transparency in the options or before `Show()`,
   not in `OnReady`, or call `Show(false)`, change it, then `Show()`.
5. A click fires the sink. `AxWindow._Dispatch` walks up from the clicked
   element to the nearest one with a registered hook and calls it.

### Option strings

Every `Add*` uses the same grammar:

| Form | Meaning |
|---|---|
| `vName` | the element id, and the variable name the studio uses |
| `w120` `h40` | width and height in pixels |
| `x20` `y40` | absolute position |
| `x+8` `y+12` | offset from the previous control / new line with a gap |
| `Fill` | stretch to the width of the line |
| `Grow` | take the height left in its page or box and follow the window; `hN` is the minimum. Several growers share what is left |
| `Hidden` `Disabled` | state flags |
| `Accent` `Subtle` `Danger` | look flags a control declares |
| `Key=Value` | anything else: `Icon=E74E`, `Tip="Save it"`, `Class=my-thing` |

Per-control options are in [reference.md](reference.md).

### What the window does under the hood

**DOM events.** `ComObjConnect(WB.Document, sink)` receives document-level
events with no parameters; the handler reads `document.parentWindow.event`.
Events that never reach the document (`change` on checkboxes, radios and
ranges, `contextmenu` cancellation, `selectstart`, `keypress` filtering) are
covered by reading state on click, polling a slider on mouse move, and
`attachEvent` for the cancellable ones, so a real `VARIANT_BOOL` false can be
returned.

**Frameless window.** `-Caption +Resize`. `WM_NCCALCSIZE` makes the client
area the whole window, `WM_NCACTIVATE` returns TRUE to skip the frame repaint,
and `WM_GETMINMAXINFO` sets the maximised rectangle (the work area) and the
minimum size.

**Drag and resize.** `mousedown` on the title bar or a hotspot calls
`ReleaseCapture` and posts `WM_NCLBUTTONDOWN` with the matching `HT*` code.
Double-click is timed in AHK because the native move loop eats the second
click.

**Snap Layouts.** The ActiveX host and IE's inner windows are subclassed to
answer `HTTRANSPARENT` over the maximise button, so Windows 11 sees the
top-level window's `HTMAXBUTTON` reply to `WM_NCHITTEST`.

**No flicker.** The control stays hidden until `DocumentComplete`, and the
subclass swallows `WM_ERASEBKGND` so a resize never paints white.

**IE11 mode.** MSHTML reads `FEATURE_BROWSER_EMULATION` for the host process
name when it loads; there is no in-process API and the meta tag is ignored at
the default level. The library writes the HKCU value only when it differs
(`BrowserEmulation`, default `11001`; `false` skips it) and, with
`AutoRestart`, relaunches once if `DocMode` is still below 11.
`tools\RegisterBrowserEmulation.ahk` does HKLM.

**GPU rendering.** `GpuRendering: false` sets `FEATURE_GPU_RENDERING` to 0:
the CPU draws, the graphics driver is not started for the first paint, and
the window appears about 150 ms sooner. The switch is per program, so every
script run by `AutoHotkey64.exe` shares it; a compiled script has its own.
Omit the option and nothing is written.

**Compiled to one .exe.** `lib/AxAssets.ahk` and each component carry
`;@Ahk2Exe-AddResource` lines (resource names come from `AxSys.ResName`).
`AxWindow.ReadLib` and `AxSys.KindIconFile` look in the exe's resources first,
then the lib folder, so one script works both ways. Themes and templates are
read from memory; notification icons are written once to
`%TEMP%\AxGui\icons` because Windows needs a path. The emulation value is
written for the exe's own name on first start.

**Mica only through a colour key.** Windows 11 22H2+ accepts
`DWMWA_SYSTEMBACKDROP_TYPE`, but Trident writes every pixel it paints with
alpha 255, black included, whether it draws on the GPU or the CPU. So the usual
trick of painting black and extending the frame does nothing for a page. (It
works for plain Gui controls because GDI leaves alpha at 0.) A colour key does
work: on a layered window, DWM shows the backdrop in the keyed pixels and draws
everything else solid. The key can go on the browser's host window alone. That
is a child window, and its keyed pixels show the black top-level window behind
it, which DWM fills with the backdrop. A click on the glass then still lands in
the app. It is one bit deep: a pixel is glass or solid, and nothing is half
see-through. `example/Glass.ahk` tries every material, a tint and the stylesheets
this way, in dark only. The library's own surfaces stay flat Windows 11 colours
with an optional tint.

**Trident limits:**

- **CSS is IE11's.** Flexbox, transitions, transforms, `rgba`, keyframes and
  SVG data-URI backgrounds work. CSS Grid, `gap`, CSS variables,
  `backdrop-filter` and `feTurbulence` do not.
- **No `pointer-events`.** A full-size transparent overlay would swallow every
  click, so overlays are positioned per element.
- **Native scrollbars paint above everything.** A menu that overlaps one must
  hide it while open.
- **The caret is painted in the text colour**, so the
  transparent-text-over-highlight trick for code editors hides the caret.
- **No `mousemove` reaches AutoHotkey**, which is why the studio's canvas does
  its pointer work in JavaScript (see Part 2).

### Component packs

A component is a folder with its code, its CSS and a manifest for the studio:

```
lib/components/Slider/
  AxSlider.ahk          g.AddSlider(), the markup it becomes, what a click does
  AxSlider.css          its shape; the theme decides the look
  Slider.axc.json       what the studio puts in the toolbox
lib/components/_all.ahk generated: one #Include per component
```

Every control, shipped or yours, lives only there: the text box is
`lib/components/Edit/`. The core does not know which controls exist; each
registers itself:

```ahk
class AxSlider {
    static _reg := AxRich.Register("Slider", "components\Slider\AxSlider.css",
                                   (*) => AxSlider._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddSlider", (c, a*) => AxSlider._Add(c, a*))
        AxTags.Register("ax-slider", 22, (el, inner, id) => AxSlider._Tag(...))
        AxWindow.RegisterBox("slider")
        return true
    }
}
```

| Registers with | For |
|---|---|
| `AxRich.AddMethod` | `g.AddSlider(...)` on any container |
| `AxRich.Register` | its stylesheet, in the layer under the theme |
| `AxTags.Register` | the markup its `<ax-*>` tag becomes |
| `AxWindow.RegisterClick` | what a click on a part of it does |
| `AxWindow.RegisterBox` | that a role is the whole control, not a clickable part |
| `AxWindow.RegisterValue` | how `ctl.Value` reads and writes it |

The core keeps only shared mechanisms (pointer capture, drag to reorder,
keyboard navigation, in `lib/AxWindow.Components.ahk`) and page furniture
(`<ax-nav>`, `<ax-page>`, menu and status bars). `AxGui.ahk` includes
`lib/components/_all.ahk` at its end, so `#Include lib\AxGui.ahk` gives you
every control.

- **`requires`** names other packs (the colour picker requires the screen
  picker for its eyedropper).
- **Exports include only what they use:** one `#Include` per pack the design
  touches, plus their `requires`.
- **`_all.ahk` is generated**, because `#Include` takes a path, not a glob. The
  studio rewrites it when it scans.

Manifest format: [lib/components/README.md](../lib/components/README.md).
Walkthrough: [extending.md](extending.md#add-a-component). Shipped
components: [components.md](components.md).

### Two stylesheets, and which one wins

- **Shape** is true under any theme (a switch is a row with a track and a
  knob). It lives in the pack's `Ax<Name>.css`.
- **Look** is colour, size, weight, radius, edge and spacing. It lives in
  `lib/themes/` (see [themes.md](themes.md)).

Load order:

```html
<head>
  <style id="axPackBase">   the packs: shape         </style>
  <style id="axBase">       the theme: look          </style>
  <style>                   builder.css: row layout  </style>
  <style id="axExtra_...">  SetExtraCss: the script's own
```

Pack sheets go **under** the theme so a theme can restyle any component; on
top, the theme would silently lose to a pack it has never heard of.

- `AxWindow.SetBaseCss(id, css)` puts a sheet in the lower layer, and
  `AxRich.Use(win, "Thing")` injects there on first use.
- `AxRich.Register(name, css, install, core := false)`: with `core := true`,
  `AxGui.CoreCss()` puts the sheet in the page at build time, so the shape is
  in the first paint.

Pack sheets hold no colours, sizes or fonts; `csslayer.py` in the check suite
requires every declaration to be structural. Something belongs in a pack sheet
only if `win11`, `win98` and `winxp` would all state it identically.

---

## Part 2: the studio

Using the studio: [studio.md](studio.md). What it exports:
[generated-code.md](generated-code.md).

### Module map

`Model` below means `studio/AxStudio.Model.ahk`, and so on.

| Area | Files | Responsibility |
|---|---|---|
| Core | `AxStudio.ahk`, `AxJson.ahk` | Entry point (`AxStudio().Run()`); JSON for project files |
| | `Model` | `AxNode`, `AxWin`, `AxProject`, `AxUndo`: the design tree |
| | `App`, `Titlebar`, `AxStudio.css`, `AxStudio.js` | The designer window, commands and message bridge; its chrome; canvas pointer work |
| Controls | `Catalog`, `Comp`, `Store` | Control entries; pack scanning, dependencies and tree shaking; the component viewer and .zip install |
| Editing | `Panes`, `Grid.js` | Toolbox, outline, properties, events, window settings; in-page list and grid editors |
| | `Gallery`, `Wizards`, `Form` | Every "add a ..."; the wizards; a generic modal form |
| | `Acts` | The Actions row |
| | `Arrange`, `Layout` | Laying out a box; turning fixed places into resizing rows |
| | `Chrome`, `Menus`, `Icons` | Title bar items, menu and status bars, menus; Segoe Fluent glyphs |
| | `Theme`, `Look` | Theme tokens; the Look workspace |
| Behaviour | `Flow`, `Bind`, `Data` | Rules and states; data binding; where a list gets its rows |
| | `Auto`, `Auto2` | Hotkeys, hotstrings, timers, conditions; program events, watchers, macros, settings |
| | `Assets`, `Files`, `Helpers` | Arguments, modes, tray, compile settings; files the program needs; helper functions for scripts |
| | `Logic`, `Map` + `.js`, `Steps`, `StepsUi`, `Steps.js` | What the design does, as a list, a map, and readable steps |
| | `Pkg`, `PkgUi`, `DotNet`, `DotNetUi` | Libraries through Aris; .NET through AHK# |
| Output | `Lit`, `Gen`, `Merge` | Escaping; tree → canvas markup, AutoHotkey, TSV; regions and read-back |
| | `Lint`, `Debug`, `Build` | The Problems tab; the Run agent and its log; Ahk2Exe |
| | `Pre` | Expands the window body at export time for `AxGui.Prebuilt` |
| Input | `Import`, `ImportGui`, `ImportLogic`, `Host` | AxGui scripts, `Gui()` scripts and script logic into designs; the AHK parser as a separate process |
| | `Complete`, `Templates` + `templates/` | Code completion; starting points (ordinary project files) |
| Other | `Probe` | The studio run to inspect itself |
| | `lib/components/CodeEditor` | The code editor |

### The data model

```
AxProject
├── Uid            next node id
├── Vars           binding variables, project-wide
└── Wins[]         AxWin
    ├── Name, Kind             main / window / dialog / tool / code
    ├── Title, Width, ...      everything AxWindow's constructor takes
    ├── Menus, Status, ...     window furniture, authored as text
    ├── Flows, States, Binds   behaviour without code
    ├── Init, Script           your own code
    └── Root                   AxNode
        └── Kids[]             AxNode
            ├── Id, Type, Name, Arg
            ├── L{}            layout: w h x y place gap top fill dock ...
            ├── P{}            properties, whatever the catalog declares
            ├── Ev[]           events: {name, code}
            └── Kids[]
```

The studio edits **one window at a time**; `AxProject` forwards every window
property to it:

```ahk
; AxProject.__Get / __Set
if AxWin.Owns(name)
    return this.W.%name%
```

So `P.Title` and `P.Root` always mean the window being edited.

### The three pipelines

**1. Tree → canvas.** The canvas is not a drawing: the studio asks `AxGui`
for each control's markup, so a canvas button is the real control:

```
AxNode ──AxGen.OptString──▶ "vd_n7 w120 Accent" ──AxDesignGui.AddButton──▶ HTML
```

A fix to `win11.css` or `AxTags.ahk` reaches the designer with no studio
change.

**2. Canvas → AHK (the bridge).** Pointer work is JavaScript, and one message
crosses per gesture:

```
JS:  data.value = JSON.stringify(msg); bridge.click()
AHK: Bridge()   queues the payload, SetTimer(drain, -1)
AHK: Drain()    on a FRESH THREAD: edits the model, redraws
```

The click arrives while the posting JavaScript is still on the stack. Editing
the DOM there leaves Trident dispatching into nodes that no longer exist, and
the designer freezes.

**3. Tree → script.** See [generated-code.md](generated-code.md).

### Invariants

Break one and an old bug comes back:

1. **The bridge drains on a fresh AHK thread.** Handling a canvas message
   inline freezes the designer.
2. **The canvas paper must not inherit the studio's `has-menubar` /
   `has-statusbar` body classes.** It would subtract the height of bars the
   designed window does not have.
3. **`AxStudio.Validate` writes its temp copy beside the real output path**,
   because a generated file uses a relative `#Include`.
4. **The code editor is a `contenteditable`, not a textarea**, because Trident
   paints the caret in the text colour.

### Two AutoHotkey v2 traps

`/validate` catches neither:

```ahk
; 1. A closure does NOT capture a for-loop control variable.
for w in windows
    p.Walk(w.Root, (n) => Use(w, n))     ; WRONG: w is unset when it runs

for w in windows
    p.Walk(w.Root, MakeFn(w))            ; right: bound as a parameter
MakeFn(w) => (n) => Use(w, n)

; 2. __Set fires for the FIRST assignment to a property too.
__Set(name, params, value) {
    if Known(name)
        return this.Other.%name% := value
    this.DefineProp(name, {Value: value})   ; not `throw`: the constructor
}                                           ; assigns its own fields through here
```

---

## Checking a change

Nothing here is verified by running it. The checks:

| Check | Catches |
|---|---|
| `/validate` with `#Warn All, StdOut`, one wrapper per file | syntax errors, unassigned variables |
| Static call resolution over `studio/` | calls to methods that do not exist |
| Closure scan over `studio/` | callbacks capturing a for-loop variable |
| `node --check` on every `.js` (`studio/*.js`, `AxCodeEditor.js`) | JS syntax errors, which are otherwise silent |
| Schema pass over `templates/*.json` | unknown keys, duplicate ids, unknown control types |
| `/validate` of a hand-written sample of generated output | the shape of what the generator writes |
| Field / method collision scan | `this._tail` beside `_Tail()`: names are case-insensitive and a method is read-only |
| Control-character scan | mangled escapes: `\b` as a backspace, a lone CR splitting a line |
| Manifest schema pass over `*.axc.json` | bad manifests, unresolved `requires`, two packs claiming one control type |
| Stylesheet path check over every `AxRich.Register` | a pack pointing at a moved sheet; `ReadLib` returns `""` silently and the control renders unstyled |
| Layer check (`csslayer.py`) over pack sheets | a colour or size in a pack sheet, or packs on the wrong side of the theme |
| `/validate` over every file in `example/` | the library still builds what it did |

`/ErrorStdOut` does not redirect *warnings*, and validating a part file
directly pops a dialog, so validate each file through a wrapper:

```ahk
#Requires AutoHotkey v2.0
#NoTrayIcon
#Warn All, StdOut
#Include C:\...\studio\AxStudio.Gen.ahk
```
