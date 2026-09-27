# TODO

Found during the WinShell review (2026-09-23). Nothing here has been changed yet.

## DPI

- [ ] **The "dpi fix" squares the scale.** `lib/AxWindow.ahk:1141-1142`:
  ```ahk
  DPI := A_ScreenDPI / 96 * 100
  this.WB.ExecWB(63, 2, Round(A_ScreenDPI / 96 * DPI), 0)
  ```
  At 144 DPI (150%) this asks for 225% zoom; at 96 DPI it is 100%, so it only
  shows on scaled displays. The comment says `-> 100%`. Check on a 125% and a
  150% display which value Trident actually wants (100, or `DPI`), since it
  came from outside reports ("thanks skan and bobak").
- [ ] **Per-monitor DPI.** Everything reads `A_ScreenDPI`
  (`AxWindow.ahk:1141`, `:1724`, `:1912`), the system DPI. Handle
  `WM_DPICHANGED` (0x02E0): re-zoom the page, resize to the suggested rect.
- [ ] `IsSnapped()` (`AxWindow.ahk:1815`) only checks the primary monitor.
- [ ] Surface `WM_DISPLAYCHANGE` / `WM_SETTINGCHANGE` as window events
  (monitor layout, theme, work area changes).

## Window options for shell use (WinShell needs these)

- [ ] `ToolWindow: true` (no taskbar button, no Alt+Tab).
- [ ] `Owner: hwnd`.
- [ ] `ClickThrough: true` (`WS_EX_TRANSPARENT | WS_EX_LAYERED`).
- [ ] `ColorKey` / `Region` helpers, lifted from `example/Transparent.ahk`.
- [ ] `Backdrop: "mica" | "acrylic"`, lifted from `example/Glass.ahk`.
- [ ] **Per-pixel alpha** with difference matting: draw the page twice, on
  black and on white, and get alpha = 255 − (white − black). Being proven in
  `projects/winshell/ui/lib/AlphaSurface.ahk`. If it holds up, move it into an
  `AxWindow.Alpha.ahk` mixin, and fix the header of `example/Transparent.ahk`,
  which says per-pixel alpha is impossible.

## Studio

- [ ] `studio/AxStudio.Host.ahk:65`: `AxHost.Exec.StdOut.ReadLine()` blocks the
  UI for as long as AstHost takes. Make it async (poll `AtEndOfStream`/peek on a
  timer, or a pipe with a callback).

## Stale

- [ ] `lib/AxWindow.ahk:28` mentions `<script type="text/ahk">` page scripts;
  nothing implements them. Implement or drop the line.
