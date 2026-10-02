#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes/icons (single-file exe)
#Include ..\lib\AxGui.ahk

; =============================================================================
;  Wordmark.ahk — Windows 11's "About Windows" window, made with AxGui.
;  ---------------------------------------------------------------------------
;  What this exercises:
;
;   • A really tall title bar: win.Header(). The caption, the glowing wordmark,
;     the lit line and the tab strip are one band that drags the window and
;     double-clicks to maximise; only the tab's page scrolls under it. The
;     greeting bar with OK is win.Footer(). No layout code: the window is a
;     column and the page takes what the band and the footer leave.
;   • Inline SVG: the logo + "Windows 11" is ONE path drawn four times with
;     SVG filters -- a wide blurred halo, a tight rim light, the face on a
;     gradient and a sheen clipped to the letters. Behind it, a soft radial
;     bloom; under it, a line lit from the middle.
;   • win.ThemedCss(): every colour, the SVG's included, is a token ({tint},
;     {back}, {tint|alpha:.3} ...) worked out again on every theme, accent or
;     tint change -- nothing is rebuilt by hand.
;   • Header actions (AxWindow.Actions.ahk): the Copy split button and the
;     copy icon at the end of each section's header.
;   • Visuals tab: glow strength, a pulse, and "Classic header" -- the flatter
;     band this example had before it was matched to the real window.
; =============================================================================

W := AxGui({
    Title:     "About Windows",
    Width:     800,
    Height:    900,
    MinWidth:  560,
    MinHeight: 480,
    Theme:     "dark",
    Nav:       false,                  ; no nav rail: the header, then the page
    Css:       ".kv{display:flex;margin:0 0 10px}"
             . ".kv .k{width:140px;flex:none;opacity:.6;font-size:13px}"
             . ".kv .v{font-size:13px}"
             . ".heroCard{padding:20px 0 6px;margin:10px 0}"
             . ".labNote{font-size:14px;max-width:640px;line-height:21px}"
})
LOOK := {Glow: 0.85}                   ; 0..1, scales every glow layer ({k} below)


; ─────────────────────────────────────────────────────────────────────────────
;  The look: one stylesheet of tokens
; ─────────────────────────────────────────────────────────────────────────────

; the colours, named once (vars below): the band behind the caption, the
; deeper band under the specs and the greeting, the line's bright middle,
; the colour as text on the page, and the letters' face
COLS := Map(
    "band",  "{back|darken:{dark?.26:.06}|mix:{tint}:{dark?.08:.10}}",
    "deep",  "{back|darken:{dark?.16:.04}|mix:{tint}:.06}",
    "lit",   "{tint|lighten:{dark?.35:0}}",
    "ink",   "{tint|readable:{dark?{back}:{back|mix:{tint}:.12}}}",
    "face",  "{dark?{tint}:{tint|readable:#f3f3f3:3}}")       ; on a light band, deepened until it reads
VARS := {k: () => LOOK.Glow}
for name, expr in COLS
    VARS.%name% := ((e) => () => W.ResolveCss(e, VARS)).Call(expr)

W.ThemedCss("hero", ""
    ; ---- the tall title bar: caption, wordmark, line, tabs ----
    . "#titlebar #titleText,#titlebar .winbtn{color:{text} !important}"
    . "body.inactive #titlebar #titleText,body.inactive #titlebar .winbtn{opacity:.6}"
    . "#axHeader{background:linear-gradient(180deg,{band|mix:{tint}:.16} 0%,{band} 70%,{band} 100%)}"
    . ".hero{position:relative;padding:4px 0 26px;overflow:hidden}"
    ; a bloom inside the band, fading to nothing before any of its edges
    . ".heroBloom{position:absolute;left:8%;right:8%;top:0;bottom:0;"
    . "background:radial-gradient(closest-side at 50% 55%,{tint|alpha:{dark?{=.26*k}:.16}} 0%,{tint|alpha:{=.10*k}} 55%,{tint|alpha:0} 100%)}"
    . ".heroMid{position:relative;width:52%;max-width:560px;margin:0 auto}"
    ; the svg overhangs the stage by its 150-unit margin (7.3% across, 30.24%
    ; down); the stage is moved down by that much, so the glow's faded edge
    ; stays out of the caption
    . ".heroStage{position:relative;width:100%;padding-top:24.14%;margin:7.3% 0 4%}"
    . ".heroStage svg{position:absolute;left:-7.3%;top:-30.24%;width:114.6%;height:160.48%;display:block;overflow:hidden}"
    ; the wordmark's colours -- CSS reaches into the SVG
    . ".hw-halo{fill:{face};opacity:{=.55*k}}"
    . ".hw-rim{fill:{dark?{tint|lighten:.7}:{face}};opacity:{dark?{=.45*k}:0}}"
    . ".hwF0{stop-color:{dark?{tint|lighten:.45}:{face|lighten:.15}}}.hwF1{stop-color:{face}}"
    . ".hw-sheen{opacity:{dark?.8:.45}}"
    . "body.theme-light .hw-halo{opacity:{=.30*k}}"
    . "body.hw-pulse .hw-halo{animation:hwPulse 3.6s ease-in-out infinite}"
    . "@keyframes hwPulse{0%,100%{opacity:{=.25*k}}50%{opacity:{=.70*k}}}"
    . ".heroLine{height:2px;background:linear-gradient(90deg,{tint|alpha:.35} 0%,{lit} 50%,{tint|alpha:.35} 100%);"
    . "box-shadow:0 0 {=14*k}px {tint|alpha:{=.55*k}},0 0 3px {tint|alpha:{=.8*k}}}"
    ; the tabs, on the band: no boxes, a short lit pill under the one showing
    . "#axHeader .tabs{display:flex;align-items:center;margin:0;padding:8px 16px 4px;border:0;background:transparent}"
    . "#axHeader .tab{background:transparent !important;margin-right:6px;padding:9px 10px 13px;color:{text};opacity:.86;border-radius:4px}"
    . "#axHeader .tab:hover{background:{text|alpha:.06} !important;opacity:1}"
    . "#axHeader .tab.active{opacity:1}"
    . "#axHeader .tab.active:after{left:50%;right:auto;width:16px;margin-left:-8px;bottom:3px;height:3px;border-radius:2px;background:{lit}}"
    . "#aboutMore{position:absolute;right:16px;bottom:9px;z-index:1;display:flex;align-items:center;padding:7px 10px;border-radius:4px;font-size:14px;color:{text}}"
    . "#aboutMore:hover{background:{text|alpha:.06}}"
    . "#aboutMore .ico{font-family:'Segoe Fluent Icons','Segoe MDL2 Assets';margin-right:9px;font-size:15px}"
    ; ---- the page under it: sections split by hairlines ----
    . "#content{padding:0 !important}"
    . "#content .tab-panel{padding:18px 26px}"
    . "#content #Tabs_1{padding:0}"
    . ".abSec{position:relative;padding:18px 26px 22px}"
    . ".abSec > .ax-acts.corner{top:13px;right:18px}"
    . ".abHead{display:flex;align-items:center;font-size:15px;font-weight:600;margin-bottom:14px}"
    . ".abIco{width:18px;height:18px;line-height:18px;border-radius:50%;margin:0 18px 0 2px;text-align:center;"
    . "font:900 11px 'Segoe UI',sans-serif;background:{ink};color:{ink|on}}"
    . ".abRows{padding-left:38px}"
    . ".abRow{display:flex;font-size:14px;line-height:27px}"
    . ".abRow .k{width:137px;flex:none}"
    . ".abRow .v{opacity:.72}"
    . ".abText{padding-left:38px;font-size:14px;line-height:21px}"
    . ".abText p{margin:0 0 12px}"
    . ".abLink{color:{ink};cursor:default}.abLink:hover{text-decoration:underline}"
    . ".abSpecs{display:flex;background:{deep};border-top:1px solid rgba(128,128,128,.14);border-bottom:1px solid rgba(128,128,128,.14);padding:18px 0}"
    . ".abSpec{width:33.333%;min-width:0;text-align:center;padding:4px 14px 6px;border-left:1px solid rgba(128,128,128,.25);word-wrap:break-word}"
    . ".abSpec:first-child{border-left:0}"
    . ".abSpec .t{font-size:15px;font-weight:600;margin-bottom:18px}"
    . ".abSpec .t .ico{font-family:'Segoe Fluent Icons','Segoe MDL2 Assets';font-weight:normal;margin-right:9px;font-size:16px;vertical-align:-2px}"
    . ".abSpec .v{font-size:14px;font-weight:600}"
    . ".abPair{display:flex;justify-content:center}.abPair div{margin:0 14px}"
    . ".abPair small{display:block;font-size:12px;font-weight:normal;opacity:.75;margin-top:3px}"
    . ".ax-act.boxed{border:1px solid rgba(128,128,128,.32);background:rgba(128,128,128,.08)}"
    ; ---- the greeting bar ----
    . "#axFooter{display:flex;align-items:center;padding:14px 26px;background:{deep};border-top:1px solid rgba(128,128,128,.14);font-size:14px}"
    . ".abAvatar{width:34px;height:34px;border-radius:50%;margin-right:16px;text-align:center;line-height:34px;font-weight:600;color:#fff;"
    . "background:linear-gradient(135deg,{tint},{tint|darken:.45})}"
    . ".abOk{margin-left:auto;min-width:118px;padding:7px 0;text-align:center;border-radius:4px;cursor:default;background:{tint};color:{tint|on}}"
    . ".abOk:hover{background:{tint|lighten:.12}}"
    ; ---- the classic header: the flatter band from before ----
    . "body.hw-classic .heroBloom,body.hw-classic .heroLine{display:none}"
    . "body.hw-classic #axHeader{background:linear-gradient(170deg,{band|mix:{tint}:.22} 0%,{band} 55%)}"
    . "body.hw-classic .hero{border-bottom:1px solid rgba(128,128,128,.16)}"
    . "body.hw-classic #axHeader .tab.active{background:rgba(128,128,128,.14) !important}"
    . "body.hw-classic #axHeader .tab.active:after{left:12px;right:12px;width:auto;margin:0;bottom:0;background:{tint}}"
    , VARS)

; The Windows 11 logo + wordmark as one path (viewBox 0 0 2055 496)
WORD_PATH := 'M121 112q11-11 26-11h120v149H113V136q0-13 8-24ZM282 101h120q13 0 23 8 11 10 11 25v116H282zM1126 238v-79h33v201h-33v-20q-11 19-33 23-20 3-39-7-20-11-26-33-8-27-2-54 6-22 23-36 18-14 40-13c14 0 29 6 37 18m-40 9q-19 5-26 24-5 17-2 36 3 16 16 26c14 8 32 5 42-7q12-16 11-36 1-19-10-33c-7-9-20-12-31-10ZM824 162q12-2 20 6c6 7 6 19-1 25-8 9-25 8-32-2q-7-12 1-22 5-6 12-7ZM1800 165h19v195h-33V205q-18 13-40 18l-4-26q32-10 58-32ZM1912 165h20v195h-33V205q-18 14-41 18l-4-26q32-10 58-32ZM538 169h36l33 131 4 18q5-24 13-48l27-101h33q8 27 15 55l19 70 5 24q5-27 12-53l25-96h34l-53 191h-36l-34-125q-3-11-4-21l-12 48q-12 50-27 98h-36l-35-121zM908 244q12-20 34-23 19-3 34 5t20 26 3 38v70h-33v-58q1-17-1-33-2-11-10-18-14-8-29-2-11 7-14 19-4 11-3 24v68h-33V223h32zM1245 221c20-2 42 1 58 13 15 11 22 30 24 48q3 29-13 54a69 69 0 0 1-47 27q-30 4-56-13-19-15-24-39-6-30 7-57c10-19 31-31 51-33m1 27q-14 3-21 16-8 16-6 33 0 15 8 26 10 12 25 14 17 2 29-9 9-10 12-22 3-18-2-36-5-13-17-20-12-5-28-2ZM1613 221q18-2 37 3 10 2 16 9l-7 23q-16-12-36-11-11 0-19 7c-5 5-3 15 3 18q11 6 24 10 16 6 29 16 9 10 9 24 1 13-8 24-8 12-22 15a92 92 0 0 1-75-9l8-25q21 16 47 13 8 0 13-6c5-4 5-13 0-18q-9-6-19-9-14-5-27-12-13-8-16-20-5-16 4-30c8-13 24-20 39-22ZM811 223h33v137h-33zM1337 223h35l29 104q15-52 31-104h33l21 70 9 35q2-15 7-28l21-77h33l-45 137h-34l-20-65-10-36-18 60-12 41h-35q-11-32-21-65zM113 266h154v149H156q-10 1-21-1-14-5-20-21-3-8-2-16zM282 265h154v119q-1 21-21 29-7 3-15 2H282z'

; The wordmark: one path, four layers, its colours all in the CSS above.
; The canvas is the wordmark plus 150 units all round: the halo's blur fades
; out inside it. `suf` keeps the defs' ids unique for a second copy.
HeroSvg(suf := "") => '<svg viewBox="-150 -150 2355 796" aria-hidden="true"><defs>'
    . '<linearGradient id="hwFace' suf '" x1="0" y1="0" x2="0" y2="1"><stop class="hwF0" offset="0"/><stop class="hwF1" offset="1"/></linearGradient>'
    . '<linearGradient id="hwSheen' suf '" x1="0" y1="0" x2="1" y2="0.9">'
    . '<stop offset="0.08" stop-color="#ffffff" stop-opacity="0"/><stop offset="0.40" stop-color="#ffffff" stop-opacity="0.32"/>'
    . '<stop offset="0.56" stop-color="#ffffff" stop-opacity="0"/></linearGradient>'
    . '<filter id="hwBig' suf '" x="-8%" y="-40%" width="116%" height="180%"><feGaussianBlur stdDeviation="30"/></filter>'
    . '<filter id="hwSml' suf '" x="-4%" y="-60%" width="108%" height="220%"><feGaussianBlur stdDeviation="8"/></filter>'
    . '<clipPath id="hwClip' suf '"><path d="' WORD_PATH '"/></clipPath></defs>'
    . '<path class="hw-halo" d="' WORD_PATH '" filter="url(#hwBig' suf ')"/>'
    . '<path class="hw-rim" d="' WORD_PATH '" filter="url(#hwSml' suf ')"/>'
    . '<path d="' WORD_PATH '" fill="url(#hwFace' suf ')"/>'
    . '<rect class="hw-sheen" x="0" y="0" width="2055" height="496" clip-path="url(#hwClip' suf ')" fill="url(#hwSheen' suf ')"/></svg>'


; ─────────────────────────────────────────────────────────────────────────────
;  The header, the footer, the pages
; ─────────────────────────────────────────────────────────────────────────────

W.Header('<div class="hero"><div class="heroBloom"></div><div class="heroMid"><div class="heroStage">' HeroSvg() '</div></div></div>'
    . '<div class="heroLine"></div>'
    . '<span id="aboutMore"><span class="ico">&#xE8A7;</span>View more</span>', {Tabs: "Tabs"})
W.Footer('<span class="abAvatar">' SubStr(StrUpper(A_UserName), 1, 1) '</span>Hello, ' AxWindow._Esc(A_UserName) '!'
    . '<span class="abOk" id="aboutOk">OK</span>')
W.On("click", "aboutMore", (*) => W.Toast("View more"))
W.On("click", "aboutOk", (*) => W.Close())

tabs := W.AddTab("vTabs", ["Information:E946", "License:E8D2", "Tint:E790", "Visuals:E768"])

tabs.UseTab(1)
cpu := "Demo CPU"
try cpu := Trim(RegRead("HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0", "ProcessorNameString"))
msBuf := Buffer(64, 0), NumPut("UInt", 64, msBuf)
ram := DllCall("GlobalMemoryStatusEx", "Ptr", msBuf) ? Round(NumGet(msBuf, 8, "UInt64") / 1024**3, 1) : 0
ROWS := [["Version", A_OSVersion], ["Edition", "Windows 11 Pro"],
         ["Installed on", "Monday, 03.08.2026 4:02:30 PM"], ["Computer name", A_ComputerName]]
rowsHtml := "", summary := ""
for row in ROWS {
    rowsHtml .= '<div class="abRow"><span class="k">' row[1] '</span><span class="v">' AxWindow._Esc(row[2]) '</span></div>'
    summary .= row[1] "`t" row[2] "`r`n"
}
Spec(glyph, title, value) => '<div class="abSpec"><div class="t"><span class="ico">&#x' glyph ';</span>' title '</div>' value '</div>'
AHK_TEXT := "AutoHotkey " A_AhkVersion " drives this window. Every pixel above is HTML and SVG in the "
    . "Trident engine, styled to sit beside the real thing."
W.AddHtml("Fill", '<div class="abSec" id="secWin"><div class="abHead"><span class="abIco">i</span>Microsoft Windows</div>'
    . '<div class="abRows">' rowsHtml '</div></div>'
    . '<div class="abSpecs">'
    .   Spec("E950", "CPU", '<div class="v">' AxWindow._Esc(cpu) '</div>')
    .   Spec("E7F4", "GPU", '<div class="v">Demo Graphics</div>')
    .   Spec("EEA0", "RAM", '<div class="v abPair"><div>Physical<small>' ram ' GB</small></div><div>Usable<small>'
                          . Round(ram * 0.99, 1) ' GB</small></div></div>')
    . '</div>'
    . '<div class="abSec" id="secAhk"><div class="abHead"><span class="abIco">i</span>AutoHotkey</div>'
    . '<div class="abText"><p>v' A_AhkVersion ' &middot; AxGui</p><p>' AxWindow._Esc(AHK_TEXT) '</p>'
    . '<span class="abLink" id="ahkMore">More information</span></div></div>')
W.On("click", "ahkMore", (*) => W.Toast("Demo link"))

tabs.UseTab(2)
W.AddHtml("", '<div class="labNote"><p>License: demo text. The wordmark above is drawn by Trident '
    . 'from one SVG path, so it costs no image bytes and stays crisp at any window size.</p>'
    . '<p>Resize the window narrow and wide: the wordmark scales and the page scrolls under the header.</p></div>')
W.AddInfoBar('Kind=warning Title="Heads up."', "Everything on these tabs is demo filler.")

tabs.UseTab(3)
W.AddText("Caption", "Window tint")
W.AddSegmented("vTintP Choose1", "accent:Accent|#ff9a3c:Warm|#f4a49a:Salmon|#ff4f8b:Rose|#3cd08a:Green|#a78bfa:Violet")
    .OnChange((c, v, *) => W.SetTint(v))
W.AddText("Hint", "Or any colour: the band, the letters, the line and the glow all move with it.")
W.AddColorPicker("vTintCp Size=190", "#4C4A48")        ; #4C4A48 is the picker's "no colour"
    .OnChange((c, v, *) => W.SetTint(v = "#4C4A48" ? "" : v))
W.AddText("Caption", "Tint strength")
W.AddSlider('vTintS Min=0 Max=100 Step=5 w240 Suffix="%"', 12)      ; AxWindow's default, 0.12
    .OnChange((c, v, *) => W.SetTint(W.HasOwnProp("Tint") ? W.Tint : "", v / 100))
W.AddText("Hint", "How much of it mixes into the surfaces and the header.")
W.AddText("Caption", "Mode")
W.AddSegmented("vTheme Choose2", "light:Light|dark:Dark").OnChange((c, v, *) => W.SetTheme(v))

tabs.UseTab(4)
W.AddText("Caption", "Header")
W.AddSwitch("vClassic", "Classic header").OnChange((c, v, *) => W.BodyClass("hw-classic", v))
W.AddText("Hint", "The flatter band this example had before: no bloom, no lit line, boxed tabs.")
W.AddText("Caption", "Glow strength")
W.AddSlider('vGlowK Min=0 Max=100 Step=5 w240 Suffix="%"', Round(LOOK.Glow * 100))
    .OnChange((c, v, *) => (LOOK.Glow := v / 100, W.RefreshThemedCss()))
W.AddText("Hint", "0% is the flat wordmark; 100% is the full halo, bloom and line.")
W.AddText("Caption", "Pulse")
W.AddSwitch("vPulse", "Breathe the halo").OnChange((c, v, *) => W.BodyClass("hw-pulse", v))
W.AddText("Caption", "Accent")
W.AddText("Hint", "With no tint chosen, the glow follows the accent.")
W.AddColorPicker("vAcc Size=190", W.DefaultAccent("dark")).OnChange((c, v, *) => W.SetAccent(v))
W.AddText("Caption", "Stylesheet")
W.AddDDL("vSheet w180 Choose1", "win11:Windows 11|win365:Microsoft 365|precision:Precision|aurora:Aurora|cozy:Cozy"
    . "|cyber:Cyber|inset:Inset|instrument:Instrument|brutalist:Brutalist|macos:macOS|riso:Riso Print|blueprint:Blueprint|aero:Aero|deco:Art Deco|crt:Terminal").OnChange((c, v, *) => W.SetStylesheet(v))
W.AddHtml("", '<div class="heroCard"><div class="heroMid"><div class="heroStage">' HeroSvg("2") '</div></div></div>')
tabs.UseTab()

; the Copy actions at the end of each section's header
W.Actions("secWin", [{Glyph: "E8C8", Tip: "Copy", Class: "boxed", Copy: () => summary, Split: true,
                      Menu: ["Copy as one line", "Copy with this PC's specs"]}],
          {OnAction: SecWinAction})
W.Actions("secAhk", [{Glyph: "E8C8", Tip: "Copy", Copy: AHK_TEXT}])
SecWinAction(name, win) {
    global summary, cpu, ram
    switch name {
        case "Copy as one line":
            A_Clipboard := RTrim(StrReplace(StrReplace(summary, "`t", ": "), "`r`n", " | "), " |")
        case "Copy with this PC's specs":
            A_Clipboard := summary "CPU`t" cpu "`r`nRAM`t" ram " GB"
        default:
            return
    }
    win.Toast("Copied")
}

W.Show()


; Test hook for the ahkh harness (headless drive):
;   ahkh call DemoSet '["tint","#ff9a3c"]'
DemoSet(mode, colour) {
    global W, LOOK
    try {
        switch mode {
            case "theme":   W.SetTheme(colour)
            case "tint":    W.SetTint(colour = "none" ? "" : colour)
            case "accent":  W.SetAccent(colour)
            case "glow":    LOOK.Glow := Integer(colour) / 100, W.RefreshThemedCss()
            case "classic": W.BodyClass("hw-classic", colour = "1")
            case "tab":     W.Value("Tabs", Integer(colour))
        }
    } catch as e
        return "ERR: " e.Message
    return W.LookTint()
}
