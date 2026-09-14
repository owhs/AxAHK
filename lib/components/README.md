# components

Every control lives here, one folder each, named after the control. Shipped
controls and yours have the same shape; drop a folder in and the studio picks
it up on its next start.

```
lib/components/
  _all.ahk              generated: one #Include each, in dependency order
  Gauge/
    AxGauge.ahk         g.AddGauge(), the markup it becomes, what a click does
    AxGauge.css         its shape; the theme decides the look
    Gauge.axc.json      the manifest
```

The studio also scans a `components` folder beside the project. Walkthrough:
[docs/extending.md](../../docs/extending.md#add-a-component).

## Where a control's parts are

To make the text box multi-line, open `Edit/`:

| In `Ax<Name>.ahk` | |
|---|---|
| `_Add` | what `g.AddEdit(...)` writes into the page |
| `_Tag` | the markup its `<ax-text>` / `<ax-textarea>` becomes |
| `_Click` | what a click on a part of it does |
| `_Install` | the few lines that register all of the above |

`Ax<Name>.css` holds the **shape** only and loads before the theme, which sets
the look (see
[the layering](../../docs/architecture.md#two-stylesheets-and-which-one-wins)).
Pointer capture, drag to reorder and keyboard navigation serve every control,
so they stay in `lib/AxWindow.Components.ahk`.

## The code

A component registers itself when its file is included:

```ahk
class AxGauge {
    static _reg := AxRich.Register("Gauge", "components\Gauge\AxGauge.css",
        (*) => AxRich.AddMethod("AddGauge", (c, a*) => AxGauge._Add(c, a*)))
    ...
}
```

Two traps:

- **The stylesheet path is relative to `lib/`.** A pack in a project's
  `components` folder needs a path that climbs out, such as
  `..\components\Gauge\AxGauge.css`. A wrong path fails silently and the
  control renders unstyled.
- **Wrap the method in a fat arrow.** Passing `AxGauge._Add` directly lets its
  hidden `this` parameter take the container, so every argument arrives one
  place off.

For a single-file exe, add an
`;@Ahk2Exe-AddResource %U_AxLib%\components\<Name>\Ax<Name>.css, ...` line
next to the class. `Splitter/` is the smallest complete component; the notes
at the top of `lib/AxRich.ahk` describe the layer.

## The manifest

`<Name>.axc.json`, beside the code:

```json
{
  "name": "Gauge",
  "description": "A dial that shows one number.",
  "order": 7400,
  "css": "AxGauge.css",
  "include": "lib\\components\\Gauge\\AxGauge.ahk",
  "requires": [],
  "controls": [
    {
      "type": "Gauge",
      "label": "Gauge",
      "icon": "E9D9",
      "category": "Rich",
      "prefix": "gauge",
      "arg": { "key": "value", "label": "Value", "kind": "num", "default": "50" },
      "props": [
        { "key": "max",   "label": "Maximum",    "kind": "num", "emit": "kv", "default": "100" },
        { "key": "ticks", "label": "Show ticks", "kind": "flag" }
      ],
      "events": ["Change", "Click"]
    }
  ]
}
```

| Pack key | |
|---|---|
| `name` | the pack's name, used in other packs' `requires` |
| `description` | one line saying what it is, for people reading the manifest |
| `order` | where its controls sit in the toolbox (default 500). Folders are read alphabetically, which is rarely the order you want |
| `include` | the `.ahk` to include, relative to the folder `lib` sits in (then to the pack folder); a missing file drops the pack |
| `css` | the pack's stylesheet, relative to the pack folder. Informational: the sheet that loads is the one named in `AxRich.Register` |
| `requires` | other packs this one needs loaded first |
| `controls` | zero or more toolbox entries; a pack may be code only |

Each `controls` entry becomes an `AxCat` entry in the studio:

| Control key | |
|---|---|
| `type` | required: the `Add*` method and node type. `"Gauge"` generates `g.AddGauge(...)` |
| `label` `icon` `category` `prefix` | how it appears, and what new ones are named (`gauge1`, `gauge2`) |
| `box` | `true` if other controls go inside it |
| `arg` | the second argument to `Add*`: `key`, `label`, `kind`, `default`, and `raw` if it is an AHK expression rather than a string |
| `props` | the property sheet: `key`, `label`, `kind`, `emit`, `word`, `options`, `default` |
| `events` | what the Events tab offers: a name the studio knows (`"Click"`), or an event of the pack's own (below) |

A pack's own event is an object:

```json
{ "name": "Hit", "sig": "eng, a, b, tag", "wire": "OnHit", "filter": "tag",
  "word": "has two things touch", "help": "Two things touched: a hit b, whose tag is tag" }
```

`sig` is the generated handler's parameters and `wire` the method that
attaches it (`world.OnHit(world_Hit)`). A control forwards any method it
doesn't have to its component, so the wiring can run before the window is up.
`filter` names the parameter a rule can narrow on: `world Hit:coin -> ...`
runs only when `tag` is `coin`. `word` is how the event reads in the rule form
("when world has two things touch"), and `help` is its tip.

`kind` is the editor the property sheet draws: `text`, `multiline`, `num`,
`int`, `flag`, `choice`, `icon`, `color`, `options`.

`emit` is how a property reaches the option string:

| `emit` | Writes |
|---|---|
| `kv` (default) | `Word=Value` |
| `flag` (default for `kind: flag`) | the bare `word` when on |
| `flagset` | the chosen value as a bare word, for mutually exclusive looks |

`word` defaults to the key with its first letter capitalised (`max` → `Max`).

## What you get

- **A toolbox entry** in the named category, with properties and events, and
  no studio code changes.
- **Lean exports:** one `#Include` per pack the design uses, plus what those
  require, dependencies first.
- **Quiet failures.** The studio skips a required pack that is not installed
  and collects broken manifests in `AxComp.Problems` without showing them. The
  manifest schema check in
  [the check suite](../../docs/architecture.md#checking-a-change) catches both.

`_all.ahk` is generated because `#Include` takes a path, not a glob; the
studio rewrites it when it scans.
