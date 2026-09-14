# Reference

Everything in one place, kept short. The [guide](guide.md) explains how the
pieces fit; the big controls have their own page, [components](components.md).

`AxGui` (what you include) builds pages from `Add*` calls and is an
`AxWindow` underneath, so every `AxWindow` method below works on it too.

- [Window options](#window-options)
- [Window methods](#window-methods)
- [Controls](#controls)
- [Option strings](#option-strings)
- [Events](#events)
- [Tags](#tags)

## Window options

`AxGui({...})` or `AxWindow(htmlFile, {...})`.

| Option | Default | |
|---|---|---|
| `Title` | the page's `<title>` | Window title |
| `Width`, `Height` | 800, 540 | Size in pixels |
| `MinWidth`, `MinHeight` | 320, 200 | Smallest size when resizing |
| `X`, `Y` | Windows decides | Position |
| `Theme` | dark | `"dark"`, `"light"` or `"system"` (follows Windows) |
| `Stylesheet` | `"win11"` | The look, see [themes](themes.md), or a path to a `.css` file |
| `Accent` | the look's own | `"#rrggbb"` or `"system"` |
| `Tint`, `TintStrength` | none | A colour washed into the surfaces, or `"accent"` |
| `Icon` | `"auto"` | Icon code (`"E790"`), `"shell32.dll,13"`, `.ico`/`.exe`/`.png` path, `data:` URI, `""` |
| `Resizable`, `MaximizeBox`, `MinimizeBox` | `true` | Real window styles |
| `Maximized` | `false` | Open maximised |
| `NoActivate` | `false` | Come up without taking focus |
| `EscapeCloses` | `false` | Escape closes the window |
| `ExitOnClose` | `true` | The script exits when the window closes |
| `Frame` | `true` | `false`: no title bar is added, the page brings its own `#titlebar` |
| `Headings` | automatic | Show each page's name as a heading |
| `AppName` | | Notifications carry this app name and icon |
| `BorderColor`, `SnapBorder` | `"default"`, `"none"` | The window edge colour, floating and snapped |
| `FocusRing` | `"accent"` | `"accent"`, `"contrast"`, `"none"` or `"#rrggbb"` |
| `RoundCorners` | the look's | Windows 11 rounded corners |
| `SnapLayouts` | `true` | The Snap Layouts flyout on the maximise button |
| `NativeContextMenu` | `false` | Keep Internet Explorer's own right-click menu |
| `AllowZoom` | `false` | Allow Ctrl+wheel zoom |
| `TooltipDelay` | 450 | Milliseconds before a `Tip` shows |
| `GpuRendering` | not set | `false` starts about 150 ms sooner (shared by every script under `AutoHotkey64.exe`) |
| `BrowserEmulation`, `AutoRestart` | | IE11 mode registry handling |
| `UseAccent` | `true` | `false` leaves the look's colours alone |
| `BackColor` | | The colour behind the page while it loads |
| `Css`, `Html` | | Extra CSS; a whole page as a string |

## Window methods

**Window** `Show`, `Hide`, `Close`, `Minimize`, `Maximize`, `Restore`,
`ToggleMaximize`, `IsMaximized`, `AlwaysOnTop(on)`, `SetTitle(text)`,
`SetIcon(file, index)`, `SetFrameIcon(spec)`, `Drag`, `OnReady(fn)`,
`OnClose(fn)`, `WaitReady`.

**Closing** `Close(force := false)`; `OnBeforeClose(fn(win, why))`, where
true keeps it open and `why` is `button`, `icon`, `system`, `escape`, `exit`
or `code`; `Dirty` (unsaved changes: a dot in the title);
`AskBeforeClose(save, {Text, Title, Always})`.

**Pages** `ShowPage(id)`, `OnPage(fn)`, `CurrentPage`, `NavMode("toggle")`.

**Look** `SetTheme(mode)`, `SetAccent(hex)`, `SetTint(hex, strength)`,
`SetStylesheet(name)`, `SetExtraCss(id, css)` (your own named stylesheet on
top; `""` removes it), `AxWindow.SystemTheme()`, `AxWindow.SystemAccent()`.

**Values** `Value(id [, value])`, `OnValue(id, fn)`, `Hotkey(id, fn)`,
`SetOptions(id, list)`.

**The page** `El(id)`, `Text(id [, text])`, `Html(id [, html])`,
`Checked(id)`, `Attr(id, name [, value])`, `Style(id, prop, value)`,
`ShowEl(id)`, `HideEl(id)`, `Focus(id)`, `HasClass`, `AddClass`,
`RemoveClass`, `ToggleClass`, `Append(id, html)`, `BodyClass(name, on)`,
`Tooltip(id, text)`, `SortOrder(id)`, `RemoveItem(id)`.

**Events** `On(type, id, fn)`, `Off(type, id)`. Types: `click`, `dblclick`,
`mousedown`, `mouseup`, `mouseover`, `mouseout`, `change`, `keyup`,
`keydown`, `focusin`, `focusout`, `contextmenu`. `id` can be `"*"` for
anything not handled more specifically.

**Menu bar** `AddMenuBar(menus, opts)`, `MenuBar(id, menus, opts)`,
`SetMenus(menus)`, `ShowMenuBar(on)`, `MenuBarShown`. `opts`: `Reveal`
(`"always"` or `"alt"`), `AutoHide`.

**Status bar** `AddStatusBar(parts)`, `StatusBar(id, parts)`,
`SetStatusParts(parts)`, `Status(part, text)`, `StatusIcon(part, icon)`,
`StatusProgress(part, percent)`, `ShowStatusBar(on)`. A part:
`{Id, Text, Icon, Width, Grow, Align, Tip, Dim, Click, Progress}`.

**Menu items** (menu bar, right-click, title bar): `["Label", fn]`, `"-"`, or
`{Label, Click, Shortcut, Disabled, Checked, Radio, Icon, Items}`. `Items` can
be a function, rebuilt on every open.

**Title bar** `AddTitleBar(items, opts)` / `TitleBar(items, opts)`,
`TitleItem(id, patch)`, `TitleOn(id)`, `ShowTitleItems(on)`, `TitleAlign()`.
An item:

| Field | |
|---|---|
| `Id` | Element id (made up if left out) |
| `Kind` | `burger`, `glyph`, `text`, `html`, `svg`, `img`, `sep`, `spacer` (worked out from the content if left out) |
| `Side` | `"left"` (after the icon) or `"right"` (before the caption buttons) |
| `Glyph`, `Text`, `Html`, `Svg`, `Src` | The content |
| `Tip`, `Class`, `Width` | Tooltip, extra classes, width in px |
| `Click` | `fn(id, win)` |
| `Menu` | Menu items, or a function returning them |
| `Popover` | A pop-over spec |
| `Toggle` | A click flips the `on` class first |
| `On`, `Disabled`, `Hidden` | State |

`opts`: `ShowTitle`, `CenterTitle`.

**Pop-overs** `Popover(anchorId, spec)`, `ShowPopover(id)`,
`TogglePopover(id)`, `ClosePopover()`, `PopoverOpen`. Spec: `Html` or `Build`
(a function run on every open), `On` (`"click"`, `"hover"`, `"none"`),
`Align` (`"left"`, `"center"`, `"right"`), `Gap`, `Width`, `Class`, `Delay`,
`OnOpen`, `OnClose`.

**Dialogs** `Alert(text, title)`, `Confirm(text, title)` (true or false),
`Prompt(text, title, default)` (the text, or `""` on Cancel),
`Dialog(text, title, buttons, opts)` (returns `{Button, Value}`),
`Toast(text, ms, kind)`, `Notify(title, text, kind, opts)`.
`Notify` opts: `Buttons`, `OnClick(arg, label)`, `OnDismiss(reason)`.
Kinds: `info`, `success`, `warning`, `error`.

**Right-click** `ContextMenu(id | "*", items)`, `ShowMenu(items, x, y)`.

**Pictures** `SetImage(id, src, opts)` with `OnLoad`, `OnError`, `Timeout`,
`Alt`, `Fail`; `ImageState(id)`, `ClearImage(id)`, `SetThumbs(id, paths)`,
`AxWindow.FileUrl(path)`, `AxWindow.ImageDataUri(path)`.

**SVG** `SvgSet(id, attr, value)`, `SvgGet(id, attr)`, `SvgText(id, text)`.

**Drag and drop** `DropZone(id | "*", fn, opts)`, `RemoveDropZone(id)`,
`SelectFolder(prompt, startDir, opts)`, `SetFileList(id, paths, opts)`.
`fn(files, id, info)`; opts: `Accept`, `Multi`, `Expand`, `Recurse`,
`Browse`, `Hover`, `OnEnter`, `OnLeave`.

**Sound** `PlaySound(file, volume)`: a sound effect with no player (see [audio](components.md#audio)).

**Native controls** `Embed(id, progId, opts)`, `EmbedObj(id)`, `ShowEmbed(id, on)`,
`RemoveEmbed(id)`, `AxWindow.HasControl(progId)`.

## Controls

Every `Add*` returns a control:

| | |
|---|---|
| `ctl.Value`, `ctl.Text` | Read or set (setting fires no `Change`) |
| `ctl.Checked`, `ctl.Enabled`, `ctl.Visible` | State |
| `ctl.Name`, `ctl.Id`, `ctl.El` | The `v` name, the element id, the element |
| `ctl.OnEvent(event, fn)` | See [events](#events) |
| `ctl.OnClick(fn)`, `ctl.OnChange(fn)` | Shorthands |
| `ctl.OnDoubleClick`, `OnMiddleClick`, `OnTripleClick`, `OnMultiClick(n, fn)` | More clicks |
| `ctl.ContextMenu(items)` | A right-click menu for it |
| `ctl.Use()` | Go back into a box (card, row, group) |
| `ctl.Component` | The object behind a big control ([components](components.md)) |

The `Add*` methods: `AddText`, `AddLink`, `AddEdit`, `AddPassword`,
`AddSearch`, `AddAutoComplete`, `AddNumber`, `AddButton`, `AddCheckBox`,
`AddSwitch`, `AddRadio`, `AddDDL` (`AddDropDownList`, `AddComboBox`),
`AddListBox`, `AddSegmented`, `AddSlider`, `AddRangeSlider`, `AddRating`,
`AddPalette`, `AddHotkey`, `AddDate`, `AddDateRange`, `AddTime`,
`AddCalendar`, `AddTags`, `AddChip`, `AddBadge`, `AddAvatar`, `AddProgress`,
`AddInfoBar`, `AddStat`, `AddGauge`, `AddChart`, `AddStepper`,
`AddBreadcrumb`, `AddConsole`, `AddSeparator`, `AddImage`, `AddImageButton`,
`AddPicture`, `AddSvg`, `AddHtml`, `AddThumbs`, `AddFileList`,
`AddDropZone`; the boxes `AddPage`, `AddRow`, `AddCard`, `AddGroupBox`,
`AddExpander`, `AddGrid` + `AddTile`, `AddTab`, `AddSplitter`; the big ones
`AddDataView`, `AddListView`, `AddTreeView`, `AddCodeEditor`, `AddRichText`,
`AddColorButton`, `AddColorPicker`, `AddCanvas`, `AddAudio`, `AddGame`, `AddActiveX`; the bars `AddMenuBar`,
`AddStatusBar`, `AddTitleBar`.

## Option strings

| | |
|---|---|
| `vName` | Name |
| `wN`, `hN` | Size |
| `x+N`, `y+N`, `xN yN` | Same line; next line; exact position |
| `Fill` | Stretch across the line |
| `Grow` | Take the height that's left |
| `Checked`, `Disabled`, `Hidden`, `ReadOnly`, `ChooseN` | State |
| `Accent`, `Subtle`, `Danger`, `Icon` | Button kinds |
| `Multi`, `Checklist` | List box that picks several (`Value` is an array) |
| `Vertical` | Radios one under another |
| `Icon=E713` | An icon code |
| `Tip="..."` | Tooltip |
| `Min= Max= Step= BigStep= SmallStep=` | Numbers and sliders |
| `Suffix="%"`, `Placeholder="..."`, `Rows=3` | Text and numbers |
| `Kind=success` | Info bars and badges |
| `Desc="..."`, `Caption="..."` | Second lines and captions |
| `Fit=cover\|contain`, `Accept=images` | Pictures and drop zones |
| `Style=...` | Your own CSS on the control |

## Events

| Event | Handler gets | |
|---|---|---|
| `Click` | `ctl, info` | |
| `DoubleClick` | `ctl, info` | |
| `Change` | `ctl, value, el` | The user changed the value |
| `Focus`, `Blur` | `ctl` | |
| `KeyDown`, `KeyUp` | `ctl, event, el` | `el.value` is the text so far |
| `ContextMenu` | `ctl, info` | |
| `Hotkey` | `ctl` | A hotkey box's combination was pressed |

A list view and a tree view also have AutoHotkey's own events
(`ItemSelect`, `ItemCheck`, `ColClick` ...): see [components](components.md).

## Tags

For pages written by hand. Every tag takes `id`, `class`, `style` and `tip`.
Option lists are `value:Label,value:Label`; icons are icon codes.

| Tag | Attributes | Value |
|---|---|---|
| `ax-nav` | `pages="id:Label:Icon,..."` | The page shown (`OnPage`) |
| `ax-content`, `ax-page` | page: `id`, `title`, `active`, `noheading` | |
| `ax-row` | `icon`, `title`, `desc`, `nocard`; content: the controls | |
| `ax-card`, `ax-group` | `title` / `legend` | |
| `ax-tabs` + `ax-tab` | tab: `label`, `icon` | The tab showing |
| `ax-expander` | `title`, `desc`, `icon`, `open` | |
| `ax-grid` + `ax-tile` | tile: `value`, `icon`, `name`, `desc`, `removable` | The order, after a drag |
| `ax-button` | `kind` (`accent`, `subtle`, `danger`, `icon`), `icon`, `disabled` | |
| `ax-link`, `ax-chip`, `ax-badge` | chip `on`; badge `kind` | |
| `ax-switch` | `checked`, `on`, `off`, `nolabel` | 1 or 0 |
| `ax-check` | `checked`; content: the label | 1 or 0 |
| `ax-radio` | `options`, `value`, `inline` | The chosen value |
| `ax-text`, `ax-textarea`, `ax-password`, `ax-search` | `value`, `placeholder`, `rows` | The text |
| `ax-autocomplete` | `options`, `value`, `placeholder`, `strict`, `width` | The text |
| `ax-number` | `value`, `min`, `max`, `step`, `suffix` | The number |
| `ax-slider` | `min`, `max`, `step`, `value`, `suffix`, `novalue` | The number |
| `ax-dropdown`, `ax-list` | `options`, `value`, `width`, `height`; list: `multi="ctrl"` or `multi="check"` | The chosen value (an array when `multi`) |
| `ax-palette` | `colors`, `value`, `showhex`, `small` | The colour |
| `ax-rating` | `max`, `value` | 1 to max |
| `ax-segmented` | `options="value:Label:Icon,..."`, `value` | The chosen value |
| `ax-hotkey` | `value` (like `^+k`), `placeholder` | The hotkey |
| `ax-progress` | `value`, `indeterminate` | |
| `ax-infobar` | `kind`, `title`, `noclose` | The message |
| `ax-console` | | |
| `ax-image` | `src`, `w`, `h`, `fit`, `caption`, `alt`, `fail`, `icon`, `button`, `round` | |
| `ax-drop` | `accept`, `title`, `desc`, `icon`, `compact` | |
| `ax-files`, `ax-thumbs` | `height`, `empty` | The paths left |
| `ax-menubar`, `ax-status` | empty; filled from AutoHotkey | |
