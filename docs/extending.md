# Extending the library and the studio

Each change below is one edit in one place. For how the pieces fit together,
see [architecture.md](architecture.md).

---

## Add a component

A control is a folder in `lib/components/`. It registers itself with the
library and carries a manifest for the studio, so one folder gives you
`g.AddGauge(...)`, a toolbox entry, a property sheet, generated code, and an
`#Include` in exports that use it.

```
lib/components/Gauge/
  AxGauge.ahk        the code, the markup and the behaviour
  AxGauge.css        its shape; the theme decides the look
  Gauge.axc.json     the manifest
```

`Gauge/` is the worked example; `Splitter/` is the smallest one to copy.

### The code

```ahk
class AxGauge {
    static _reg := AxRich.Register("Gauge", "components\Gauge\AxGauge.css",
        (*) => AxRich.AddMethod("AddGauge", (c, a*) => AxGauge._Add(c, a*)))

    static _Add(container, opts := "", value := "") {
        o := container._Opt(opts, "gauge")
        AxRich.Use(container.G, "Gauge")
        return container._Reg(o, "Gauge", AxGauge.Html(o.Id, {Value: value}))
    }
}
```

Three traps:

- **The stylesheet path is relative to `lib/`.** A pack in a project's own
  `components` folder needs a path that climbs out, such as
  `..\components\Gauge\AxGauge.css`. A wrong path fails silently: `ReadLib`
  returns `""` and the control renders unstyled.
- **Wrap the method in a fat arrow.** `AddMethod` stores it on
  `AxGui.Container`. Pass `AxGauge._Add` directly and its hidden `this`
  parameter takes the container, so every argument arrives one place off.
- **Do not edit `_all.ahk`.** It is generated.

Your stylesheet loads before the theme. It says what the control *is* (a row,
a flex child, clipped, absolutely placed) and leaves colour, size and font to
the theme. `AxRich.Use(g, "Gauge")` injects it the first time a window builds
one. For an everyday control whose shape must be in the first paint, pass
`true` as `AxRich.Register`'s fourth argument.

### The manifest

```json
{
  "name": "Gauge",
  "order": 7400,
  "css": "AxGauge.css",
  "include": "lib\\components\\Gauge\\AxGauge.ahk",
  "requires": [],
  "controls": [{ "type": "Gauge", "label": "Gauge", "icon": "E9D9",
                 "category": "Rich", "prefix": "gauge",
                 "arg": {"key": "value", "label": "Value", "kind": "num", "default": "50"},
                 "props": [{"key": "max", "label": "Maximum", "kind": "num", "emit": "kv"},
                           {"key": "ticks", "label": "Show ticks", "kind": "flag"}],
                 "events": ["Change", "Click"] }]
}
```

`type` must match the method: `"Gauge"` generates `g.AddGauge(...)`. Key
reference: [lib/components/README.md](../lib/components/README.md). The studio
scans `lib/components` and a `components` folder beside the project at start.

### More a component can register

Beyond an `Add*` method:

```ahk
AxTags.Register("ax-gauge", 40, (el, inner, id) => AxGauge._Tag(el, inner, id))
AxWindow.RegisterClick("gauge-tick", (w, el, ev) => AxGauge._Click(w, el, ev), true)
AxWindow.RegisterBox("gauge")                    ; the role is the control, not a part
AxWindow.RegisterValue("gauge", get, set)        ; ctl.Value and OnChange
AxRich.WindowMethod("GaugeValue", (w, a*) => AxGauge._Val(w, a*))  ; g.GaugeValue(id)
```

- `AxTags.Register`'s middle argument is the expansion order. It only matters
  for a tag that consumes its children: `<ax-tabs>` eats its `<ax-tab>`s, so it
  must expand first.
- `RegisterClick`'s third argument means the role is found by class rather
  than by a `data-role` attribute.

Inside the studio, `AxComp` turns each `controls` entry into an `AxCat`
entry (`studio/AxStudio.Catalog.ahk`). You never edit that table by hand.

---

## Add a theme

Add a stylesheet to `lib/themes/`. Themes share one class contract (`.btn`,
`.card`, `.nav-item`, `#titlebar`, `#shell`, `#sidebar`, `#content`), so a new
theme is a restyle, not a rewrite.

A theme only carries the **look**: each control's shape is already in its
pack's sheet, which loads first. The theme loads second, so it can still
override anything. To build on an existing theme, start the file with:

```css
/* @extends win11 */
```

The base loads first and yours overrides it. Dark and light share one file:
write light rules under `body.theme-light`.

Nothing needs registering; the studio lists whatever is in the folder. More
in [themes.md](themes.md).

---

## Add a template

Save a project into `studio/templates/` (`File ▸ Save As` is enough).
Templates are ordinary project files. The studio reads two extra keys a
project ignores:

```json
{
  "format": "axstudio/2",
  "name": "Two windows",
  "desc": "A main window that opens a modal dialog.",
  "uid": 13,
  "cur": 1,
  "vars": "",
  "windows": [ ... ]
}
```

The numeric filename prefix only sets the order. A `.png` of the same name is
the thumbnail.

---

## Add an action to the Actions row

Two edits in `studio/AxStudio.Acts.ahk`: when it applies, and what it does.

```ahk
; in AxActs.For(n)
if (t = "Gauge")
    AxActs._A(out, "gauge.half", "Set it to halfway")

; in AxActs.Run(s, id), where n := s.Primary()
case "gauge.half":   return AxActs.Half(s, n)

; the action
static Half(s, n) {
    if !AxActs.Ok(s, n)
        return true
    s.Mark()                       ; one undo step
    n.Arg := "50"
    return AxActs.Done(s, "Set to halfway.")
}
```

- Call `s.Mark()` first so the action is a single undo.
- Guard with `AxActs.Ok(s, n)`; the selection can be empty.
- Reach the window through `AxActs.Win(s, n)`, never `WinOf` directly, which
  returns blank for a detached node.
- Only generate calls the library has. An action that writes code which does
  not run is worse than none.

---

## Add a rule verb

1. Add a `case` to `AxFlow.Code(project, w, f)` in
   `studio/AxStudio.Flow.ahk`:

   ```ahk
   case "flash":
       return (one = "") ? "" : one ".Visible := false, " one ".Visible := true"
   ```

   Return `""` when the arguments make no sense. The Problems tab reports that
   as *a rule does nothing*, with the line.
2. Add an entry to `AxWiz.Verbs` in `studio/AxStudio.Wizards.ahk` so the rule
   wizard offers it. `Who` says which list it picks from (`ctl`, `list`,
   `page`, `win`, `state`, `var`, or blank) and `Arg` whether it also needs a
   typed value:

   ```ahk
   {V: "flash", L: "flash a control", Who: "ctl", Arg: false},
   ```

   The list is an array, not a Map, because a Map would sort the verbs
   alphabetically.

---

## Add a theme token

Add one row to `AxTheme.Fields` in `studio/AxStudio.Theme.ahk`:

```ahk
{G: "Shape", K: "shadow", L: "Card shadow", Kind: "text", Sel: ".card", Prop: "box-shadow"}
```

`G` is the group it appears under (`Colours`, `Shape`, `Space`, `Type`). That
row gives you the editor field, saving with the project, the canvas preview
and the export.

---

## Add a Problems rule

Add a method to `studio/AxStudio.Lint.ahk` and call it from `AxLint.Run(p)`:

```ahk
static _Gauges(p, out) {
    for w in p.Wins
        p.Walk(w.Root, AxLint._GaugeFn(p, w, out))
}
static _GaugeFn(p, w, out) => (n) => (AxLint._Gauge(p, w, n, out), false)
static _Gauge(p, w, n, out) {
    if (n.Type = "Gauge" && n.Prop("max", "") = "0")
        out.Push({Sev: "warn", Win: w, Node: n,
                  Msg: n.Label " has a maximum of zero",
                  Hint: "It will always look empty."})
}
```

| `Sev` | When |
|---|---|
| `error` | the script will not run, or will not do what the design says. Only this stops an export |
| `warn` | probably a mistake |
| `info` | worth knowing |

The callback comes from a function that takes the window as a parameter
(`_GaugeFn`). **A closure does not capture a for-loop variable in AutoHotkey
v2**: it sees it unset and throws the first time it runs.

---

## Checking your change

```powershell
# every source, warnings on. /ErrorStdOut does not redirect warnings, and
# validating a part file directly pops a dialog, so go through a wrapper.
& $exe '/ErrorStdOut' '/validate' $wrapper

node --check studio\AxStudio.js     # and the other studio\*.js
node --check lib\components\CodeEditor\AxCodeEditor.js
```

Then run the static passes in
[architecture.md](architecture.md#checking-a-change): call resolution, the
closure scan, the template and manifest schemas, and a validated sample of
generated output.
