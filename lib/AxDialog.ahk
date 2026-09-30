#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\AxGui.ahk
; =============================================================================
;  AxDialog — the AxAHK dialog on its own, with no app window behind it.
;
;      r := AxDialog.Ask("Close “Report.docx”?", "Close it?", ["Close", "Keep it open"],
;                        {Kind: "warning", Cancel: 2})
;      if r.Button == "Close" ...
;
;  The same box as win.Dialog() (its title, text, buttons, a text box, a
;  "don't ask again" tick, markup under the text) in a small window of its
;  own: in the theme Windows uses, on top of everything, in the middle of the
;  screen the mouse is on, and gone when answered. It blocks, and returns
;  {Button, Value, Checked} -- Button "" when it's closed with Escape or its x.
;
;  opts: everything win.Dialog() takes (Kind, Input, Default, Placeholder,
;  Check, Html, Danger, Cancel), plus Theme ("light" | "dark"; default:
;  Windows'), Accent, Stylesheet, Width (460), Owner (a window to stay on).
; =============================================================================
class AxDialog {
    static Ask(text, title := "", buttons := "", opts := "") {
        o := IsObject(opts) ? opts : {}
        get := (k, d) => o.HasOwnProp(k) ? o.%k% : d
        light := 1
        try light := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme")
        W := get("Width", 460)
        ; the page is just the box: its overlay see-through, the box filling the window
        css := "#axDlgOverlay{background:transparent!important}"
            . "#axDlg{position:static!important;left:auto!important;top:auto!important;transform:none!important;width:auto!important;max-width:none!important;"
            . "margin:0!important;box-shadow:none!important;border:0!important;border-radius:0!important}"
            . "#axDlgText{max-height:60vh;overflow-y:auto;white-space:pre-wrap}"         ; a long list scrolls inside it
        g := AxGui({Title: title != "" ? title : "Question", Width: W, Height: 180, Resizable: false, MinimizeBox: false, MaximizeBox: false, Frame: false,
            Theme: get("Theme", light ? "light" : "dark"), Stylesheet: get("Stylesheet", "win11"), ExitOnClose: false, EscapeCloses: false, Nav: false, Css: css})
        if o.HasOwnProp("Accent")
            g.Accent := o.Accent
        g.Show(false)
        try g.Gui.Opt("+AlwaysOnTop" (get("Owner", 0) ? " +Owner" get("Owner", 0) : ""))
        ; once the box has its content: the window its size, centred where the mouse is, shown, and given the keyboard
        SetTimer(AxDialog._Fit.Bind(AxDialog, g, W), -30)
        r := g.Dialog(text, title, buttons, o)
        try g.Close(true)
        return r
    }
    static _Fit(g, W) {
        h := 160
        try h := g.El("axDlg").offsetHeight
        CoordMode "Mouse", "Screen"
        MouseGetPos &mx, &my
        mon := MonitorGetPrimary()
        loop MonitorGetCount() {
            MonitorGet(A_Index, &l, &t, &r, &b)
            if mx >= l && mx < r && my >= t && my < b
                mon := A_Index
        }
        MonitorGetWorkArea(mon, &l, &t, &r, &b)
        k := A_ScreenDPI / 96, ww := Round(W * k), hh := Min(Round(h * k), b - t - 40)
        g.Show()
        WinMove((l + r - ww) // 2, (t + b - hh) // 2 - Round(40 * k), ww, hh, g.Gui.Hwnd)
        try WinActivate(g.Gui.Hwnd)
    }
}
