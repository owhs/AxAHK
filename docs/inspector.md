# The inspector

A DevTools-style inspector for your window, while you build it. There's
nothing to set up: press **F12** (or **Ctrl+Shift+I**) over any window made
with the library, and press it again to close it. The hotkeys only apply to
those windows, so F12 works as normal everywhere else.

It comes with `lib\AxGui.ahk` whenever the script runs as a `.ahk`, and is
left out of a compiled `.exe` automatically. If you do want it in an exe,
include `lib\dev\AxInspector.ahk` yourself (the studio's compile options have
a switch for it).

`AxInspector.Attach(g)` opens it from the start, and
`AxInspector.Attach(g, {Maximized: true})` fills the screen.

## What it shows

The page tree on the left, and on the right:

| Tab | |
|---|---|
| **Element** | The element's tag, id, classes and attributes |
| **Styles** | Every CSS rule that matches, strongest first. Declarations that lost are struck through, so you can see which rule won and why |
| **Computed** | The final value of every CSS property |
| **Layout** | The box model: margin, border, padding and size |
| **Properties** | What the element is doing right now: its size, scroll position, whether it overflows, and what `g.Value(id)` returns |
| **AHK** | Which of your functions a click on this element reaches, and the file and line where you registered it. Also its control, its live value (which you can edit), and buttons to click, focus or highlight it |

Along the bottom is the path from the page down to the selected element.

## Why doesn't my handler run?

Press **Monitor** in the toolbar. Every click, key press, change and
right-click in your window is logged in the console, with the AutoHotkey
function it will reach, or "nothing" if no handler catches it.

## Trying out CSS

The **CSS** tab is a stylesheet laid over your window and applied as you
type. Click a rule in **Styles** to copy it there; clicking another property
of the same rule adds to it instead of repeating it. **From selection** starts
a rule for the selected element, scoped so it wins. **Save** writes it to a
`.css` file, which is how an experiment becomes a stylesheet.

The status line says how many rules were accepted, so a typo shows up as
"0 rules" instead of silently doing nothing. Your CSS goes in under the
accent colour; add `!important` to override the accent.

## The console

The console takes short commands rather than code: `sel`, `count`, `html`,
`text`, `attr`, `css`, `class`, `value`, `click`, `focus`, `toast`, `theme`,
`accent`, `tint`, `refresh`, `clear`. Type `help` for the list; Up and Down
recall earlier commands. **Esc** opens and closes it.

## Good to know

- The inspector runs in your script, so a busy script freezes it too.
- The tree is a snapshot. Press **Refresh** after the page changes.
- It opens with the tree four levels deep, so a big page appears quickly.
