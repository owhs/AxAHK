#Requires AutoHotkey v2.0

; =============================================================================
;  AxSys.ahk — Windows system helpers used by AxWindow (no page/DOM knowledge):
;    DWM        corners, shadow, border colour, caption colour / dark mode
;    Icons      window icon -> PNG data URI, stock icons -> PNG files
;    Identity   AppUserModelID + Start Menu shortcut (RegisterApp)
;    Toasts     WinRT notifications with lines, buttons and click callbacks
;    System     app theme, accent colour, IE11 emulation registry value
;  Everything is static; AxWindow delegates to it.
; =============================================================================
class AxSys {
    static LibDir := SubStr(A_LineFile, 1, InStr(A_LineFile, "\", , -1))
    static Aumid := ""
    static _toasts := Map()      ; id -> live toast record (kept until dismissed)

    ; ------------------------------------------------------------------ DWM
    static RoundCorners(hwnd, on := true) {
        try {
            pref := Buffer(4, 0), NumPut("Int", on ? 2 : 1, pref)          ; DWMWCP_ROUND / DWMWCP_DONOTROUND
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 33, "Ptr", pref, "Int", 4)
        }
    }
    ; 1px extended frame: keeps the DWM drop shadow on a frameless window
    static Shadow(hwnd) {
        try {
            m := Buffer(16, 0)
            loop 4
                NumPut("Int", 1, m, (A_Index - 1) * 4)
            DllCall("dwmapi\DwmExtendFrameIntoClientArea", "Ptr", hwnd, "Ptr", m)
        }
    }
    ; "default" | "none" | "#rrggbb"   (DWMWA_BORDER_COLOR)
    static Border(hwnd, color) {
        try {
            v := (color = "default") ? 0xFFFFFFFF : (color = "" || color = "none") ? 0xFFFFFFFE : AxSys.ColorRef(color)
            buf := Buffer(4, 0), NumPut("UInt", v, buf)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 34, "Ptr", buf, "Int", 4)
        }
    }
    ; caption colour + immersive dark mode: what DWM paints where the app has
    ; not painted yet (live resize)
    static Backdrop(hwnd, hex) {
        try {
            buf := Buffer(4, 0)
            NumPut("UInt", AxSys.ColorRef(hex), buf)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 35, "Ptr", buf, "Int", 4)      ; DWMWA_CAPTION_COLOR
            NumPut("Int", AxSys.Luma(hex) < 0.5 ? 1 : 0, buf)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 20, "Ptr", buf, "Int", 4)      ; DWMWA_USE_IMMERSIVE_DARK_MODE
        }
    }
    ; Popup menus -- the tray menu, the system menu, any Menu.Show() -- dark or
    ; light for the whole process, to match the window: uxtheme's unnamed
    ; SetPreferredAppMode (ordinal 135: 2 force dark, 3 force light),
    ; AllowDarkModeForWindow (133) for the menus' owners, and FlushMenuThemes
    ; (136) so a menu already made redraws. Windows 10 1903 and later; false
    ; on anything older, where menus stay as Windows draws them.
    static MenuTheme(dark, hwnd := 0) {
        static fns := ""
        if (fns = "") {
            fns := false
            if (VerCompare(A_OSVersion, "10.0.18362") >= 0)
                && (mod := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr"))
                fns := {Mode: DllCall("GetProcAddress", "Ptr", mod, "Ptr", 135, "Ptr"),
                        Win: DllCall("GetProcAddress", "Ptr", mod, "Ptr", 133, "Ptr"),
                        Flush: DllCall("GetProcAddress", "Ptr", mod, "Ptr", 136, "Ptr")}
        }
        if (!IsObject(fns) || !fns.Mode)
            return false
        DllCall(fns.Mode, "Int", dark ? 2 : 3)
        if fns.Win
            for h in [A_ScriptHwnd, hwnd]               ; the tray's owner, and the window's own
                if h
                    DllCall(fns.Win, "Ptr", h, "Int", dark ? 1 : 0)
        if fns.Flush
            DllCall(fns.Flush)
        return true
    }
    ; ---- per-app audio ----------------------------------------------------
    ; AppVolume(level 0..100, mute := "") sets this process's audio session in
    ; the Windows mixer (what the Volume Mixer shows per app). Independent of
    ; the player in use, and safe to call at any time: returns false until the
    ; process has an audio session (it appears once something has played).
    static AppVolume(level := "", mute := "") {
        vol := AxSys._SessionVolume()
        if !vol
            return false
        if (level != "")
            ComCall(3, vol, "Float", Max(0, Min(100, level)) / 100, "Ptr", 0)   ; SetMasterVolume
        if (mute != "")
            ComCall(5, vol, "Int", mute ? 1 : 0, "Ptr", 0)                       ; SetMute
        return true
    }
    static _SessionVolume() {
        static CLSID_Enum := "{BCDE0395-E52F-467C-8E3D-C4579291692E}", IID_Enum := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
        static IID_Mgr2 := "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}", IID_Ctl2 := "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}", IID_Vol := "{87CE5498-68D6-44E5-9215-6DA47EF883D8}"
        try {
            enum := ComObject(CLSID_Enum, IID_Enum)
            ComCall(4, enum, "Int", 0, "Int", 0, "Ptr*", &dev := 0)               ; GetDefaultAudioEndpoint(eRender, eConsole)
            iid := Buffer(16), DllCall("ole32\CLSIDFromString", "WStr", IID_Mgr2, "Ptr", iid)
            ComCall(3, dev, "Ptr", iid, "UInt", 23, "Ptr", 0, "Ptr*", &mgr := 0)  ; Activate(IAudioSessionManager2)
            ObjRelease(dev)
            ComCall(5, mgr, "Ptr*", &list := 0)                                   ; GetSessionEnumerator
            ComCall(3, list, "Int*", &n := 0)                                     ; GetCount
            found := 0
            loop n {
                ComCall(4, list, "Int", A_Index - 1, "Ptr*", &ctl := 0)           ; GetSession
                ctl2 := ComObjQuery(ctl, IID_Ctl2), ObjRelease(ctl)
                ComCall(14, ctl2, "UInt*", &pid := 0)                             ; GetProcessId
                if (pid = DllCall("GetCurrentProcessId")) {
                    found := ComObjQuery(ctl2, IID_Vol)
                    break
                }
            }
            ObjRelease(list), ObjRelease(mgr)
            return found
        }
        return 0
    }
    ; ---- embedded resources (see AxAssets.ahk) ---------------------------
    ; ResName("themes\win11.css") -> "AX_THEMES_WIN11_CSS"
    static ResName(rel) => "AX_" StrUpper(RegExReplace(rel, "[\\/.\-]", "_"))
    ; Resource(name) -> Buffer with the RCDATA bytes, or "" when not compiled / absent
    static Resource(name) {
        if !A_IsCompiled
            return ""
        hMod := DllCall("GetModuleHandle", "Ptr", 0, "Ptr"), hRes := 0
        for type in [10, 23]                                                            ; RT_RCDATA, RT_HTML (Ahk2Exe files .html there)
            if (hRes := DllCall("FindResourceW", "Ptr", hMod, "WStr", name, "Ptr", type, "Ptr"))
                break
        if !hRes
            return ""
        size := DllCall("SizeofResource", "Ptr", hMod, "Ptr", hRes, "UInt")
        p := DllCall("LockResource", "Ptr", DllCall("LoadResource", "Ptr", hMod, "Ptr", hRes, "Ptr"), "Ptr")
        if (!p || !size)
            return ""
        buf := Buffer(size)
        DllCall("RtlMoveMemory", "Ptr", buf, "Ptr", p, "UPtr", size)
        return buf
    }
    static ResourceText(name) {
        buf := AxSys.Resource(name)
        return buf ? StrGet(buf, buf.Size, "UTF-8") : ""
    }
    ; ResourceFile(name, file): write an embedded resource to disk once
    ; (for APIs that need a path); returns the path or ""
    static ResourceFile(name, file) {
        if FileExist(file)
            return file
        buf := AxSys.Resource(name)
        if !buf
            return ""
        try {
            SplitPath(file, , &dir)
            DirCreate(dir)
            fh := FileOpen(file, "w"), fh.RawWrite(buf), fh.Close()
            return file
        }
        return ""
    }
    static IsArranged(hwnd) {
        try return DllCall("user32\IsWindowArranged", "Ptr", hwnd, "Int") != 0
        return false
    }

    ; ---------------------------------------------------------- folder picker
    ; SelectFolder(prompt, startDir, opts) — the Vista+ common item dialog with
    ; FOS_PICKFOLDERS: the same window FileSelect shows, restricted to folders,
    ; with the navigation pane, the address bar, search and typing a path.
    ; (DirSelect still shows the small SHBrowseForFolder tree.)
    ; opts: {Owner: hwnd, Multi: false, OkLabel: "Select folder"}
    ; Returns "" when cancelled, a path, or an Array of paths with Multi.
    static SelectFolder(prompt := "", startDir := "", opts := "") {
        o := (n, d) => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        multi := o("Multi", false) ? true : false
        try
            return AxSys._PickFolder(prompt, startDir, multi, o("Owner", 0), o("OkLabel", ""))
        catch {                                   ; pre-Vista, or COM refused: old tree dialog
            d := DirSelect(startDir != "" ? "*" startDir : "", 3, prompt)
            return multi ? (d != "" ? [d] : []) : d
        }
    }
    static _PickFolder(prompt, startDir, multi, owner, okLabel) {
        static FOS := 0x20 | 0x40 | 0x800         ; PICKFOLDERS | FORCEFILESYSTEM | PATHMUSTEXIST
        dlg := ComObject("{DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7}",     ; CLSID_FileOpenDialog
                         "{D57C7288-D4AD-4768-BE02-9D969532D960}")     ; IID_IFileOpenDialog
        flags := 0
        ComCall(10, dlg, "UInt*", &flags)                              ; GetOptions
        ComCall(9, dlg, "UInt", flags | FOS | (multi ? 0x200 : 0))     ; SetOptions
        if (prompt != "")
            ComCall(17, dlg, "WStr", prompt)                           ; SetTitle
        if (okLabel != "")
            ComCall(18, dlg, "WStr", okLabel)                          ; SetOkButtonLabel
        if (startDir != "" && DirExist(startDir)) {
            iid := AxSys.Guid("{43826D1E-E718-42EE-BC55-A1E261C37BFE}")   ; IID_IShellItem
            psi := 0
            if (!DllCall("shell32\SHCreateItemFromParsingName", "WStr", startDir, "Ptr", 0,
                         "Ptr", iid, "Ptr*", &psi, "Int") && psi) {
                ComCall(12, dlg, "Ptr", psi)                           ; SetFolder
                ObjRelease(psi)
            }
        }
        if ComCall(3, dlg, "Ptr", owner, "Int")                        ; Show: non-zero = cancelled
            return multi ? [] : ""
        if !multi {
            item := 0
            ComCall(20, dlg, "Ptr*", &item)                            ; GetResult
            path := AxSys._ShellItemPath(item)
            ObjRelease(item)
            return path
        }
        arr := 0, out := [], count := 0
        ComCall(27, dlg, "Ptr*", &arr)                                 ; GetResults
        ComCall(7, arr, "UInt*", &count)                               ; IShellItemArray::GetCount
        loop count {
            item := 0
            ComCall(8, arr, "UInt", A_Index - 1, "Ptr*", &item)         ; GetItemAt
            p := AxSys._ShellItemPath(item)
            ObjRelease(item)
            if (p != "")
                out.Push(p)
        }
        ObjRelease(arr)
        return out
    }
    static _ShellItemPath(psi) {
        p := 0
        if (!psi || ComCall(5, psi, "UInt", 0x80058000, "Ptr*", &p, "Int"))   ; SIGDN_FILESYSPATH
            return ""
        s := StrGet(p, "UTF-16")
        DllCall("ole32\CoTaskMemFree", "Ptr", p)
        return s
    }
    static Guid(str) {
        b := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "WStr", str, "Ptr", b)
        return b
    }

    ; --------------------------------------------------------------- colours
    static ColorRef(hex) {
        hex := LTrim(hex, "#"), rgb := Integer("0x" hex)
        return ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | (rgb >> 16)
    }
    static Luma(hex) {
        hex := LTrim(hex, "#")
        r := Integer("0x" SubStr(hex, 1, 2)), g := Integer("0x" SubStr(hex, 3, 2)), b := Integer("0x" SubStr(hex, 5, 2))
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    }
    static Mix(a, b, t) {
        a := LTrim(a, "#"), b := LTrim(b, "#"), out := "#"
        loop 3 {
            ca := Integer("0x" SubStr(a, 1 + (A_Index - 1) * 2, 2)), cb := Integer("0x" SubStr(b, 1 + (A_Index - 1) * 2, 2))
            out .= Format("{:02x}", Round(ca + (cb - ca) * t))
        }
        return out
    }
    static Rgba(hex, alpha) {
        hex := LTrim(hex, "#")
        return "rgba(" Integer("0x" SubStr(hex, 1, 2)) "," Integer("0x" SubStr(hex, 3, 2)) "," Integer("0x" SubStr(hex, 5, 2)) "," alpha ")"
    }
    ; "#abc" / "abcdef" / "#AABBCC" -> {R, G, B, Ok}; Ok is false for junk
    ; ------------------------------------------------------- markup helpers
    ; These two live here rather than on AxWindow because AxTags needs them and
    ; AxSys is loaded before everything: a file that reaches forward to a class
    ; declared later reads that name as an unassigned local, which is what
    ; #Warn VarUnset reports. AxWindow.HotkeyDisplay and AxWindow.FileUrl are
    ; kept as the public spelling and forward here.
    ;
    ; "^!k" -> "Ctrl + Alt + K", for showing a hotkey rather than sending it
    static HotkeyDisplay(v) {
        if (v = "")
            return ""
        d := ""
        while (v != "" && InStr("^!+#", SubStr(v, 1, 1))) {
            c := SubStr(v, 1, 1), v := SubStr(v, 2)
            d .= (c = "^" ? "Ctrl" : c = "!" ? "Alt" : c = "+" ? "Shift" : "Win") " + "
        }
        return d (StrLen(v) = 1 ? StrUpper(v) : v)
    }
    ; a local path as a file:/// URL the page can load; anything already a URL,
    ; a data: URI or a relative path is handed back untouched
    static FileUrl(path) {
        p := String(path)
        if (p = "" || InStr(p, "://") = 1 || RegExMatch(p, "i)^(https?|file|data|res|about):"))
            return p
        if !RegExMatch(p, "^([A-Za-z]:[\\/]|\\\\)")
            return p                                    ; relative: the page's <base> resolves it
        p := StrReplace(p, "\", "/")
        p := StrReplace(StrReplace(StrReplace(p, "%", "%25"), "#", "%23"), "?", "%3F")
        return (SubStr(p, 1, 2) = "//") ? "file:" p : "file:///" p
    }

    ; ------------------------------------------------------------- recolour
    ; Every stylesheet here paints its chrome in a fixed blue -- Luna's title
    ; bar, 9x navy, Fluent's #60cdff. Chasing those with per-selector overrides
    ; means a list that is never finished, so instead the sheet itself is
    ; rewritten: every colour literal whose hue sits in the blue band is turned
    ; to the accent's hue, keeping its own lightness and saturation so the
    ; gradients, bevels and borders keep their shape.
    static BlueLo := 185, BlueHi := 258, BlueMinS := 0.22
    ; A sheet whose accent material is not blue says so at the top of the file:
    ;
    ;     /* @accent-hue 38 16 */      hue 38, give or take 16
    ;
    ; Without it only the blue band moves, which would leave a brass or green
    ; sheet untouched by SetAccent. The declared band is remapped IN ADDITION
    ; to the blue one, because a sheet that extends another inherits its blues.
    static AccentBand(css) {
        if RegExMatch(css, "i)/\*\s*@accent-hue\s+([0-9.]+)(?:\s+([0-9.]+))?\s*\*/", &m) {
            h := Number(m[1]), tol := (m[2] != "") ? Number(m[2]) : 14
            return {Lo: h - tol, Hi: h + tol}
        }
        return ""
    }
    ; The component packs are written in the Fluent accent: #60cdff on dark,
    ; #005fb8 on light, #4cc2ff for a hover. AccentCss puts the window's real
    ; accent -- the stylesheet's own, or the one chosen -- in their place, and
    ; where a rule fills something with it, turns that rule's black or white
    ; text to whichever reads on the new colour. Other blues are RecolourCss's.
    static FluentAccents := "i)#(?:60cdff|005fb8|4cc2ff)(?![0-9a-z_-])"
    static AccentCss(css, hex) {
        c := AxSys.HexToRgb(hex)
        if (css = "" || !c.Ok)
            return css
        onA := (0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B) / 255 > 0.45 ? "#000000" : "#ffffff"
        out := "", pos := 1
        while RegExMatch(css, "\{[^{}]*\}", &m, pos) {
            blk := m[0]
            if RegExMatch(blk, AxSys.FluentAccents) {
                filled := RegExMatch(blk, "i)background(?:-color)?\s*:\s*#(?:60cdff|005fb8|4cc2ff)(?![0-9a-z])")
                blk := RegExReplace(blk, AxSys.FluentAccents, hex)
                if filled
                    blk := RegExReplace(blk, "i)(?<![\w-])color\s*:\s*#(?:000000|000|ffffff|fff|1b1b1b)(?![0-9a-z])", "color: " onA)
            }
            out .= SubStr(css, pos, m.Pos - pos) blk
            pos := m.Pos + m.Len
        }
        return out SubStr(css, pos)
    }
    static RecolourCss(css, hex, band := "") {
        if (css = "" || hex = "")
            return css
        c := AxSys.HexToRgb(hex)
        if !c.Ok
            return css
        acc := AxSys.RgbToHsv(c.R, c.G, c.B)
        if !IsObject(band)
            band := AxSys.AccentBand(css)
        out := "", pos := 1
        while (p := InStr(css, "#", , pos)) {
            out .= SubStr(css, pos, p - pos)
            lit := AxSys._ColorTok(css, p)
            if (lit = "") {
                out .= "#"
                pos := p + 1
                continue
            }
            out .= AxSys._ToAccentHue(lit, acc, band)
            pos := p + StrLen(lit)
        }
        return out . SubStr(css, pos)
    }
    ; "#rrggbb" or "#rgb" starting at p, but only when it really is a colour:
    ; an id selector like #axDlgTitle or #sidebar must be left alone, so the
    ; digits have to be hex AND the token must not run on into a name.
    static _ColorTok(css, p) {
        for n in [6, 3] {
            t := SubStr(css, p + 1, n)
            if (StrLen(t) < n)
                continue
            ok := true
            loop n
                if !InStr("0123456789abcdefABCDEF", SubStr(t, A_Index, 1)) {
                    ok := false
                    break
                }
            if !ok
                continue
            nxt := SubStr(css, p + 1 + n, 1)
            if (nxt != "" && InStr("0123456789abcdefghijklmnopqrstuvwxyz"
                                 . "ABCDEFGHIJKLMNOPQRSTUVWXYZ_-", nxt))
                continue                       ; part of a longer name
            return "#" t
        }
        return ""
    }
    static _ToAccentHue(lit, acc, band := "") {
        c := AxSys.HexToRgb(lit)
        if !c.Ok
            return lit
        h := AxSys.RgbToHsv(c.R, c.G, c.B)
        if (h.S < AxSys.BlueMinS)
            return lit
        inBlue := (h.H >= AxSys.BlueLo && h.H <= AxSys.BlueHi)
        inOwn  := IsObject(band) && (h.H >= band.Lo && h.H <= band.Hi)
        if (!inBlue && !inOwn)
            return lit                          ; not a colour this sheet drives
        ; A muted accent should give muted chrome, not a fully saturated version
        ; of itself, and a near-grey one should drain the colour away entirely.
        sf := 0.55 + 0.45 * acc.S
        if (acc.S < 0.2)
            sf := Min(sf, acc.S / 0.2)
        s := h.S * sf
        ; And the accent's lightness has to count for something. Turning the hue
        ; alone meant picking a near-black green still produced Luna's brilliant
        ; blue in green -- the chrome came out dazzling whatever was chosen.
        ; Scaling by the accent's own value darkens it in proportion while
        ; leaving a bright accent (the usual case) essentially untouched.
        v := h.V * (0.40 + 0.60 * acc.V)
        return AxSys.HsvHex(acc.H, s, v)
    }
    static HexToRgb(hex) {
        h := LTrim(Trim(String(hex)), "#")
        if (StrLen(h) = 3)
            h := SubStr(h, 1, 1) SubStr(h, 1, 1) SubStr(h, 2, 1) SubStr(h, 2, 1) SubStr(h, 3, 1) SubStr(h, 3, 1)
        if !RegExMatch(h, "^[0-9A-Fa-f]{6}$")
            return {R: 0, G: 0, B: 0, Ok: false}
        n := Integer("0x" h)
        return {R: (n >> 16) & 0xFF, G: (n >> 8) & 0xFF, B: n & 0xFF, Ok: true}
    }
    static RgbToHex(r, g, b) => Format("#{:02X}{:02X}{:02X}",
        Min(255, Max(0, Round(r))), Min(255, Max(0, Round(g))), Min(255, Max(0, Round(b))))
    ; {H: 0..360, S: 0..1, V: 0..1}
    static RgbToHsv(r, g, b) {
        r /= 255, g /= 255, b /= 255
        mx := Max(r, g, b), mn := Min(r, g, b), d := mx - mn, h := 0
        if (d > 0) {
            if (mx = r)
                h := 60 * Mod((g - b) / d + 6, 6)
            else if (mx = g)
                h := 60 * ((b - r) / d + 2)
            else
                h := 60 * ((r - g) / d + 4)
        }
        return {H: h, S: (mx = 0 ? 0 : d / mx), V: mx}
    }
    static HsvToRgb(h, s, v) {
        h := Mod(Mod(h, 360) + 360, 360), s := Min(1, Max(0, s)), v := Min(1, Max(0, v))
        c := v * s, x := c * (1 - Abs(Mod(h / 60, 2) - 1)), m := v - c
        if (h < 60)
            r := c, g := x, b := 0
        else if (h < 120)
            r := x, g := c, b := 0
        else if (h < 180)
            r := 0, g := c, b := x
        else if (h < 240)
            r := 0, g := x, b := c
        else if (h < 300)
            r := x, g := 0, b := c
        else
            r := c, g := 0, b := x
        return {R: Round((r + m) * 255), G: Round((g + m) * 255), B: Round((b + m) * 255)}
    }
    static HsvHex(h, s, v) {
        c := AxSys.HsvToRgb(h, s, v)
        return AxSys.RgbToHex(c.R, c.G, c.B)
    }
    ; a COLORREF (what GetPixel returns) -> "#RRGGBB"
    static ColorRefToHex(bgr) => Format("#{:02X}{:02X}{:02X}", bgr & 0xFF, (bgr >> 8) & 0xFF, (bgr >> 16) & 0xFF)
    static Atan2(y, x) {
        static pi := 3.141592653589793
        if (x > 0)
            return ATan(y / x)
        if (x < 0)
            return ATan(y / x) + (y >= 0 ? pi : -pi)
        return y > 0 ? pi / 2 : (y < 0 ? -pi / 2 : 0)
    }

    ; ---------------------------------------------------------------- system
    static SystemTheme() {
        try return RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme") ? "light" : "dark"
        return "dark"
    }
    static SystemAccent() {
        try {
            abgr := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent", "AccentColorMenu")
            return Format("#{:02x}{:02x}{:02x}", abgr & 0xFF, (abgr >> 8) & 0xFF, (abgr >> 16) & 0xFF)
        }
        try return Format("#{:06x}", RegRead("HKCU\Software\Microsoft\Windows\DWM", "ColorizationColor") & 0xFFFFFF)
        return "#0078d4"
    }
    ; FEATURE_BROWSER_EMULATION for the host exe (HKCU, only when different)
    static BrowserEmulation(value) {
        static done := false
        if done
            return
        done := true
        AxSys._Feature("FEATURE_BROWSER_EMULATION", value)
    }
    ; GpuRendering(on): FEATURE_GPU_RENDERING -- whether pages are drawn on the
    ; GPU (true) or the CPU (false). Off, a window is up ~150 ms sooner: the
    ; browser does not start the graphics driver for its first paint
    ; (Showcase 0.53 s -> 0.40 s, measured 2026-09-14 on an Intel GPU).
    ; Unset, a hosted browser draws with the CPU. Under AutoHotkey the switch
    ; belongs to AutoHotkey64.exe, so every script it runs shares it; a
    ; compiled script has its own.
    static GpuRendering(on) {
        static done := false
        if done
            return
        done := true
        AxSys._Feature("FEATURE_GPU_RENDERING", on ? 1 : 0)
    }
    ; An Internet Explorer feature switch for this program, in HKCU, written
    ; only when it differs. The browser looks it up by the name of the program
    ; running -- the compiled script's exe, or AutoHotkey itself; a .ahk name
    ; is never looked up, so none is written.
    static _Feature(feature, value) {
        regPath := "HKCU\Software\Microsoft\Internet Explorer\Main\FeatureControl\" feature
        exe := StrSplit(A_IsCompiled ? A_ScriptFullPath : A_AhkPath, "\")[-1]
        try cur := RegRead(regPath, exe)
        catch
            cur := ""
        if (cur != value)
            try RegWrite(value, "REG_DWORD", regPath, exe)
    }

    ; ----------------------------------------------------------------- icons
    static _Gdip() {
        static token := 0
        if !token {
            si := Buffer(A_PtrSize = 8 ? 24 : 16, 0), NumPut("UInt", 1, si)
            DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si, "Ptr", 0)
        }
    }
    static IconToPngFile(hIcon, outPath) {
        try {
            AxSys._Gdip()
            pBmp := 0
            if DllCall("gdiplus\GdipCreateBitmapFromHICON", "Ptr", hIcon, "Ptr*", &pBmp) || !pBmp
                return false
            clsid := Buffer(16, 0)
            DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)
            hr := DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBmp, "WStr", outPath, "Ptr", clsid, "Ptr", 0)
            DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)
            return (hr = 0)
        }
        return false
    }
    ; IconDataUri("shell32.dll,13" | "app.exe" | "thing.ico" | "imageres.dll,-109")
    ; -> a PNG data URI at the requested size. A negative index is a resource
    ; id, as it is everywhere else in Windows.
    static IconDataUri(spec, size := 32) {
        file := Trim(String(spec)), idx := 0
        if RegExMatch(file, "^(.*),\s*(-?\d+)$", &m)
            file := Trim(m[1]), idx := Integer(m[2])
        if (file = "")
            return ""
        hIcon := 0
        n := DllCall("user32\PrivateExtractIconsW", "Str", file, "Int", idx, "Int", size, "Int", size,
                     "Ptr*", &hIcon, "UInt*", 0, "UInt", 1, "UInt", 0, "UInt")
        if (!n || n = 0xFFFFFFFF || !hIcon)
            return ""
        uri := AxSys.HIconDataUri(hIcon)
        DllCall("DestroyIcon", "Ptr", hIcon)
        return uri
    }
    ; an HICON as a PNG data URI (the caller still owns the icon)
    static HIconDataUri(hIcon) {
        ; A window's icon is the same at every start, and GDI+ -- starting it,
        ; and the PNG encoder -- is up to a few tens of milliseconds of a
        ; window coming up. The result is kept, found again by the pixels.
        f := ""
        try {
            key := AxSys._IconKey(hIcon)
            if (key != "") {
                f := A_Temp "\AxGui\icon_" key ".txt"
                if FileExist(f)
                    return FileRead(f, "UTF-8")
            }
        }
        uri := ""
        try {
            AxSys._Gdip()
            pBmp := 0
            if DllCall("gdiplus\GdipCreateBitmapFromHICON", "Ptr", hIcon, "Ptr*", &pBmp) || !pBmp
                return ""
            uri := AxSys.BitmapDataUri(pBmp)
            DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)
        }
        if (uri != "" && f != "") {
            try {
                DirCreate(A_Temp "\AxGui")
                FileAppend(uri, f ".tmp", "UTF-8-RAW")
                FileMove(f ".tmp", f, true)
            }
        }
        return uri
    }
    ; An icon's pixels as a name: the CRC of its colour and mask bitmaps, with
    ; their sizes. "" when the icon cannot be read.
    static _IconKey(hIcon) {
        ii := Buffer(A_PtrSize = 8 ? 32 : 20, 0)
        if !DllCall("GetIconInfo", "Ptr", hIcon, "Ptr", ii)
            return ""
        mask := NumGet(ii, A_PtrSize = 8 ? 16 : 12, "Ptr"), color := NumGet(ii, A_PtrSize = 8 ? 24 : 16, "Ptr")
        key := ""
        try {
            for hbm in [color, mask] {
                if !hbm
                    continue
                bm := Buffer(A_PtrSize = 8 ? 32 : 24, 0)
                DllCall("GetObject", "Ptr", hbm, "Int", bm.Size, "Ptr", bm)
                n := NumGet(bm, 8, "Int") * NumGet(bm, 12, "Int")         ; height * bytes per row
                if (n <= 0 || n > 0x1000000) {
                    key := ""
                    break
                }
                bits := Buffer(n, 0)
                DllCall("GetBitmapBits", "Ptr", hbm, "Int", n, "Ptr", bits)
                key .= Format("{:08x}{}x{}", DllCall("ntdll\RtlComputeCrc32", "UInt", 0, "Ptr", bits, "UInt", n, "UInt"),
                              NumGet(bm, 4, "Int"), NumGet(bm, 8, "Int"))
            }
        } finally {
            if color
                DllCall("DeleteObject", "Ptr", color)
            if mask
                DllCall("DeleteObject", "Ptr", mask)
        }
        return key
    }
    ; A GDI+ bitmap as a data URI, entirely in memory.
    ;
    ; format "png" keeps alpha and is exact, which is what icons need. "jpeg"
    ; is for photographs, where PNG has nothing to compress -- every pixel
    ; differs slightly from its neighbour -- and comes out tens of times larger.
    static BitmapDataUri(pBitmap, format := "png", quality := 0) {
        try {
            jpeg := (StrLower(format) = "jpeg" || StrLower(format) = "jpg")
            clsid := Buffer(16, 0)
            DllCall("ole32\CLSIDFromString", "WStr",
                    jpeg ? "{557CF401-1A04-11D3-9A73-0000F81EF32E}"
                         : "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)
            pars := 0
            if (jpeg && quality > 0) {
                ; EncoderParameters { UInt count; EncoderParameter[1] } -- the
                ; parameter is aligned to a pointer, hence the gap after count
                q := Buffer(4, 0)
                NumPut("UInt", quality, q)
                pars := Buffer(8 + 16 + 4 + 4 + 8, 0)
                NumPut("UInt", 1, pars, 0)
                DllCall("ole32\CLSIDFromString", "WStr", "{1D5BE4B5-FA4A-452D-9CDD-5DB35105E7EB}",
                        "Ptr", pars.Ptr + 8)                       ; EncoderQuality
                NumPut("UInt", 1, pars, 8 + 16)                    ; one value
                NumPut("UInt", 4, pars, 8 + 20)                    ; ValueTypeLong
                NumPut("Ptr", q.Ptr, pars, 8 + 24)
            }
            pStream := 0
            DllCall("ole32\CreateStreamOnHGlobal", "Ptr", 0, "Int", 1, "Ptr*", &pStream)
            DllCall("gdiplus\GdipSaveImageToStream", "Ptr", pBitmap, "Ptr", pStream, "Ptr", clsid,
                    "Ptr", pars ? pars.Ptr : 0)
            size := 0
            DllCall("shlwapi\IStream_Size", "Ptr", pStream, "UInt64*", &size)
            DllCall("shlwapi\IStream_Reset", "Ptr", pStream)
            data := Buffer(size, 0)
            DllCall("shlwapi\IStream_Read", "Ptr", pStream, "Ptr", data, "UInt", size)
            ObjRelease(pStream)
            len := 0
            DllCall("crypt32\CryptBinaryToStringW", "Ptr", data, "UInt", size, "UInt", 0x40000001, "Ptr", 0, "UInt*", &len)
            out := Buffer(len * 2, 0)
            DllCall("crypt32\CryptBinaryToStringW", "Ptr", data, "UInt", size, "UInt", 0x40000001, "Ptr", out, "UInt*", &len)
            return (jpeg ? "data:image/jpeg;base64," : "data:image/png;base64,")
                 . StrGet(out, "UTF-16")
        }
        return ""
    }
    ; the window's icon (what the taskbar shows) as a PNG data URI
    static WindowIconDataUri(hwnd) {
        h := 0
        for w in [1, 0, 2]
            if (h := DllCall("SendMessageW", "Ptr", hwnd, "UInt", 0x7F, "Ptr", w, "Ptr", 0, "Ptr"))
                break
        if !h
            h := DllCall("GetClassLongPtr", "Ptr", hwnd, "Int", -14, "Ptr")
        if !h
            h := DllCall("GetClassLongPtr", "Ptr", hwnd, "Int", -34, "Ptr")
        if (!h && A_IconFile != "")
            h := DllCall("shell32\ExtractIconW", "Ptr", 0, "Str", A_IconFile, "UInt", A_IconNumber - 1, "Ptr")
        if (!h || h = 1)
            h := DllCall("shell32\ExtractIconW", "Ptr", 0, "Str", A_IsCompiled ? A_ScriptFullPath : A_AhkPath, "UInt", 0, "Ptr")
        if (!h || h = 1)
            return ""
        return AxSys.HIconDataUri(h)
    }
    ; notification image for a kind: lib\icons\<kind>.png, a full path, or a
    ; stock icon extracted at 128px when a bundled file is missing
    static KindIconFile(kind) {
        static siid := Map("info", 79, "warning", 78, "error", 80)
        if (kind = "" || kind = "none" || kind = "silent")
            return ""
        if FileExist(kind)
            return kind
        if A_IsCompiled {                                                  ; embedded via AxAssets.ahk
            f := AxSys.ResourceFile(AxSys.ResName("icons\" kind ".png"), A_Temp "\AxGui\icons\" kind ".png")
            if (f != "")
                return f
        }
        dir := AxSys.LibDir "icons"
        png := dir "\" kind ".png"
        if FileExist(png)
            return png
        if !siid.Has(kind)
            return ""
        try DirCreate(dir)
        h := 0
        try {
            off := A_PtrSize = 8 ? 8 : 4                                  ; SHSTOCKICONINFO
            info := Buffer(off + A_PtrSize + 8 + 520, 0), NumPut("UInt", info.Size, info)
            if !DllCall("shell32\SHGetStockIconInfo", "Int", siid[kind], "UInt", 0x4, "Ptr", info) {
                path := StrGet(info.Ptr + off + A_PtrSize + 8, 260, "UTF-16"), idx := NumGet(info, off + A_PtrSize + 4, "Int")
                DllCall("shell32\SHDefExtractIconW", "WStr", path, "Int", idx, "UInt", 0, "Ptr*", &h, "Ptr", 0, "UInt", 128)
            }
        }
        if !h
            h := DllCall("LoadImageW", "Ptr", 0, "Ptr", kind = "info" ? 32516 : kind = "warning" ? 32515 : 32513, "UInt", 1, "Int", 64, "Int", 64, "UInt", 0x8000, "Ptr")
        ok := h && AxSys.IconToPngFile(h, png)
        try DllCall("DestroyIcon", "Ptr", h)
        return ok ? png : ""
    }

    ; -------------------------------------------------------------- identity
    ; AppUserModelID + Start Menu shortcut: what Windows uses to name and
    ; iconify notifications and to group the taskbar button.
    static RegisterApp(name, aumid := "", icon := "", iconIndex := 0) {
        if (aumid = "")
            aumid := "AxGui." RegExReplace(name, "[^\w.]", "")
        DllCall("shell32\SetCurrentProcessExplicitAppUserModelID", "WStr", aumid)
        AxSys.Aumid := aumid
        ; The Start-menu shortcut notifications need, written a moment after
        ; the program is up rather than before its window -- and only when it
        ; is not there already, as this script and this id: it cost every
        ; start a tenth of a second writing the same file again.
        SetTimer(AxSys._LnkFn(name, aumid, icon, iconIndex), -1500)
        return aumid
    }
    static _LnkFn(name, aumid, icon, iconIndex) => (*) => AxSys._WriteLnk(name, aumid, icon, iconIndex)
    static _WriteLnk(name, aumid, icon, iconIndex) {
        lnk := A_AppData "\Microsoft\Windows\Start Menu\Programs\" RegExReplace(name, '[\\/:*?"<>|]', "") ".lnk"
        exe := A_IsCompiled ? A_ScriptFullPath : A_AhkPath
        sig := aumid "|" exe "|" A_ScriptFullPath "|" icon "|" iconIndex "|" A_IconFile "|" A_IconNumber
        ini := A_AppData "\AxGui\apps.ini"
        if FileExist(lnk) {
            was := ""
            try was := IniRead(ini, "lnk", lnk, "")
            if (was == sig)
                return
        }
        try {
            sl := ComObject("{00021401-0000-0000-C000-000000000046}", "{000214F9-0000-0000-C000-000000000046}")   ; IShellLinkW
            ComCall(20, sl, "WStr", exe)
            if !A_IsCompiled
                ComCall(11, sl, "WStr", '"' A_ScriptFullPath '"')
            ComCall(9, sl, "WStr", A_ScriptDir)
            ComCall(17, sl, "WStr", icon != "" ? icon : (A_IconFile != "" ? A_IconFile : exe), "Int", icon != "" ? iconIndex : (A_IconFile != "" ? A_IconNumber - 1 : 0))
            ps := ComObjQuery(sl, "{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}")     ; IPropertyStore
            key := Buffer(20, 0)
            DllCall("ole32\CLSIDFromString", "WStr", "{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}", "Ptr", key)
            NumPut("UInt", 5, key, 16)                                           ; System.AppUserModel.ID
            pv := Buffer(24, 0)
            pstr := DllCall("ole32\CoTaskMemAlloc", "UPtr", (StrLen(aumid) + 1) * 2, "Ptr")
            StrPut(aumid, pstr, "UTF-16")
            NumPut("UShort", 31, pv, 0), NumPut("Ptr", pstr, pv, 8)              ; VT_LPWSTR
            ComCall(6, ps, "Ptr", key, "Ptr", pv), ComCall(7, ps)
            DllCall("ole32\PropVariantClear", "Ptr", pv)
            pf := ComObjQuery(sl, "{0000010B-0000-0000-C000-000000000046}")     ; IPersistFile
            ComCall(6, pf, "WStr", lnk, "Int", 1)
            DirCreate(A_AppData "\AxGui")
            IniWrite(sig, ini, "lnk", lnk)
        }
    }

    ; ---------------------------------------------------------------- toasts
    ; Toast(opts) — a WinRT notification. opts (object or plain title string):
    ;   Title, Text ("`n" = new line), Image (png path), Silent (bool),
    ;   Buttons: ["Open", "Later"]           labels; or [[label, argument], ...]
    ;   OnClick: fn(argument, label)          button pressed, or body clicked ("" / "body")
    ;   OnDismiss: fn(reason)                 "user" | "timeout" | "app"
    ;   Aumid: override the registered id     Scenario: "reminder" | "alarm" | "urgent"
    ; Returns the toast id, or 0 when notifications are unavailable.
    static Toast(opts, text := "", image := "", silent := false) {
        static inited := false, nextId := 0
        if !IsObject(opts)
            opts := {Title: String(opts), Text: text, Image: image, Silent: silent}
        o := (n, d) => opts.HasOwnProp(n) ? opts.%n% : d
        aumid := o("Aumid", AxSys.Aumid)
        if (aumid = "")
            return 0
        try {
            if !inited {
                DllCall("combase\RoInitialize", "Int", 0)
                inited := true
            }
            hs := (str) => (h := 0, DllCall("combase\WindowsCreateString", "WStr", str, "UInt", StrLen(str), "Ptr*", &h), h)
            esc := (t) => StrReplace(StrReplace(StrReplace(StrReplace(String(t), "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), '"', "&quot;")
            ; --- xml
            xml := '<toast' (o("Scenario", "") != "" ? ' scenario="' esc(o("Scenario", "")) '"' : "") ' launch="body" activationType="foreground">'
                . '<visual><binding template="ToastGeneric">'
                . (o("Image", "") != "" ? '<image placement="appLogoOverride" src="' esc(o("Image", "")) '"/>' : "")
                . '<text>' esc(o("Title", "")) '</text>'
            lines := StrSplit(o("Text", ""), "`n", "`r")
            if (lines.Length <= 2) {
                for l in lines
                    if (l != "")
                        xml .= '<text>' esc(l) '</text>'
            } else {                                              ; many lines: an adaptive subgroup wraps them all
                xml .= '<group><subgroup>'
                for l in lines
                    xml .= '<text hint-wrap="true">' esc(l) '</text>'
                xml .= '</subgroup></group>'
            }
            xml .= '</binding></visual>'
            btns := o("Buttons", ""), labels := Map()
            if (IsObject(btns) && btns.Length) {
                xml .= '<actions>'
                for i, b in btns {
                    label := IsObject(b) ? b[1] : b, arg := IsObject(b) ? b[2] : "btn" i
                    labels[arg] := label
                    xml .= '<action content="' esc(label) '" arguments="' esc(arg) '" activationType="foreground"/>'
                }
                xml .= '</actions>'
            }
            if o("Silent", false)
                xml .= '<audio silent="true"/>'
            xml .= '</toast>'
            ; --- WinRT objects
            iid := Buffer(16)
            DllCall("ole32\CLSIDFromString", "WStr", "{6CD0E74E-EE65-4489-9EBF-CA43E87BA637}", "Ptr", iid)   ; IXmlDocumentIO
            hcls := hs("Windows.Data.Xml.Dom.XmlDocument"), pDoc := 0
            if DllCall("combase\RoActivateInstance", "Ptr", hcls, "Ptr*", &pDoc)
                throw Error("XmlDocument")
            pIO := 0
            ComCall(0, pDoc, "Ptr", iid, "Ptr*", &pIO)
            hxml := hs(xml)
            ComCall(6, pIO, "Ptr", hxml)                                          ; LoadXml
            DllCall("ole32\CLSIDFromString", "WStr", "{04124B20-82C6-4229-B109-FD9ED4662B53}", "Ptr", iid)   ; IToastNotificationFactory
            hcls2 := hs("Windows.UI.Notifications.ToastNotification"), pFac := 0
            if DllCall("combase\RoGetActivationFactory", "Ptr", hcls2, "Ptr", iid, "Ptr*", &pFac)
                throw Error("ToastNotificationFactory")
            pToast := 0
            ComCall(6, pFac, "Ptr", pDoc, "Ptr*", &pToast)                        ; CreateToastNotification
            DllCall("ole32\CLSIDFromString", "WStr", "{50AC103F-D235-4598-BBEF-98FE4D1A3AD4}", "Ptr", iid)   ; IToastNotificationManagerStatics
            hcls3 := hs("Windows.UI.Notifications.ToastNotificationManager"), pMgr := 0
            if DllCall("combase\RoGetActivationFactory", "Ptr", hcls3, "Ptr", iid, "Ptr*", &pMgr)
                throw Error("ToastNotificationManager")
            hid := hs(aumid), pNotifier := 0
            ComCall(7, pMgr, "Ptr", hid, "Ptr*", &pNotifier)                      ; CreateToastNotifierWithId
            ; --- events (Activated / Dismissed): COM handler objects built by hand
            id := ++nextId
            rec := {Id: id, Toast: pToast, OnClick: o("OnClick", ""), OnDismiss: o("OnDismiss", ""), Labels: labels, Handlers: []}
            AxSys._toasts[id] := rec
            ObjAddRef(pToast)
            tok := Buffer(8, 0)
            hAct := AxSys._ToastHandler(id, "activated"), hDis := AxSys._ToastHandler(id, "dismissed")
            rec.Handlers.Push(hAct, hDis)
            ComCall(11, pToast, "Ptr", hAct.Ptr, "Ptr", tok)                     ; add_Activated
            ComCall(9, pToast, "Ptr", hDis.Ptr, "Ptr", tok)                      ; add_Dismissed
            ComCall(6, pNotifier, "Ptr", pToast)                                  ; Show
            for h in [hcls, hxml, hcls2, hcls3, hid]
                DllCall("combase\WindowsDeleteString", "Ptr", h)
            for pp in [pNotifier, pMgr, pToast, pFac, pIO, pDoc]
                ObjRelease(pp)
            return id
        } catch {
            return 0
        }
    }
    ; TypedEventHandler<ToastNotification, T> implemented as a raw COM object:
    ; [vtable, refcount, toastId, kind] with QI / AddRef / Release / Invoke.
    static _ToastHandler(id, kind) {
        static vt := 0, cbs := []
        if !vt {
            vt := Buffer(4 * A_PtrSize, 0)
            cbs := [CallbackCreate(ObjBindMethod(AxSys, "_H_QI"), , 3), CallbackCreate(ObjBindMethod(AxSys, "_H_AddRef"), , 1),
                    CallbackCreate(ObjBindMethod(AxSys, "_H_Release"), , 1), CallbackCreate(ObjBindMethod(AxSys, "_H_Invoke"), , 3)]
            loop 4
                NumPut("Ptr", cbs[A_Index], vt, (A_Index - 1) * A_PtrSize)
        }
        obj := Buffer(4 * A_PtrSize, 0)
        NumPut("Ptr", vt.Ptr, obj, 0), NumPut("Ptr", 1, obj, A_PtrSize), NumPut("Ptr", id, obj, 2 * A_PtrSize), NumPut("Ptr", kind = "activated" ? 1 : 2, obj, 3 * A_PtrSize)
        return obj
    }
    static _H_QI(pThis, riid, ppv) {
        ; accept IUnknown, IAgileObject and both TypedEventHandler instantiations
        static ok := ["{00000000-0000-0000-C000-000000000046}", "{94EA2B94-E9CC-49E0-C0FF-EE64CA8F5B90}",
                      "{AB54DE2D-97D9-5528-B6AD-105AFE156530}", "{61C2402F-0ED0-5A18-AB69-59F4AA99A368}"]
        s := Buffer(80, 0)
        DllCall("ole32\StringFromGUID2", "Ptr", riid, "Ptr", s, "Int", 40)
        g := StrGet(s, "UTF-16")
        for i in ok
            if (i = g) {
                NumPut("Ptr", pThis, ppv)
                return 0
            }
        NumPut("Ptr", 0, ppv)
        return 0x80004002                                                        ; E_NOINTERFACE
    }
    static _H_AddRef(pThis) => 2
    static _H_Release(pThis) => 1
    static _H_Invoke(pThis, sender, args) {
        id := NumGet(pThis, 2 * A_PtrSize, "Ptr"), kind := NumGet(pThis, 3 * A_PtrSize, "Ptr")
        arg := ""
        try {
            if (kind = 1) {                                                      ; IToastActivatedEventArgs.Arguments
                iid := Buffer(16), DllCall("ole32\CLSIDFromString", "WStr", "{E3BF92F3-C197-436F-8265-0625824F8DAC}", "Ptr", iid)
                p := 0
                if (args && !ComCall(0, args, "Ptr", iid, "Ptr*", &p) && p) {
                    h := 0
                    ComCall(6, p, "Ptr*", &h)
                    if h {
                        len := 0, raw := DllCall("combase\WindowsGetStringRawBuffer", "Ptr", h, "UInt*", &len, "Ptr")
                        arg := StrGet(raw, len, "UTF-16")
                        DllCall("combase\WindowsDeleteString", "Ptr", h)
                    }
                    ObjRelease(p)
                }
            } else {                                                             ; IToastDismissedEventArgs.Reason
                iid := Buffer(16), DllCall("ole32\CLSIDFromString", "WStr", "{3F89D935-D9CB-4538-A0F0-FFE7659938F8}", "Ptr", iid)
                p := 0
                if (args && !ComCall(0, args, "Ptr", iid, "Ptr*", &p) && p) {
                    r := 0
                    ComCall(6, p, "Int*", &r)
                    arg := r = 0 ? "user" : r = 1 ? "app" : "timeout"
                    ObjRelease(p)
                }
            }
        }
        SetTimer(ObjBindMethod(AxSys, "_ToastEvent", id, kind, arg), -1)        ; back onto the script thread
        return 0
    }
    static _ToastEvent(id, kind, arg) {
        if !AxSys._toasts.Has(id)
            return
        rec := AxSys._toasts[id]
        if (kind = 1) {
            if rec.OnClick
                try rec.OnClick.Call(arg = "body" ? "" : arg, rec.Labels.Has(arg) ? rec.Labels[arg] : "")
        } else {
            if rec.OnDismiss
                try rec.OnDismiss.Call(arg)
            try ObjRelease(rec.Toast)
            AxSys._toasts.Delete(id)
        }
    }
}
