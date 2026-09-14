#Requires AutoHotkey v2.0
; AxAssets.ahk — single-file executables.
;
; Include this file (in addition to AxGui.ahk / AxWindow.ahk) and Ahk2Exe
; embeds every theme, frame template and icon into the .exe as RCDATA
; resources. At run time AxWindow.ReadLib / AxSys.KindIconFile look in the
; executable first and fall back to the lib folder, so the same script works
; uncompiled and compiled. Nothing is written to disk except the notification
; icons, which Windows needs as files (they go to %TEMP%\AxGui\icons).
;
; Ahk2Exe resolves the paths below relative to the MAIN script, so tell it
; where lib is with a Let directive BEFORE the #Include lines, for example:
;
;     ;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib      ; script sits beside lib
;     #Include ..\lib\AxGui.ahk
;     #Include ..\lib\AxAssets.ahk
;
; Uncompiled, this file is only comments. Ahk2Exe files .html as RT_HTML and
; everything else as RCDATA; AxSys.Resource looks in both. Resource names are
; AxSys.ResName(relativePath): "themes\win11.css" -> AX_THEMES_WIN11_CSS.
;
; Rich components (lib\rich) are not listed here: each one carries its own
; AddResource line next to its class, so including the component embeds its
; stylesheet and including nothing embeds nothing.
;
;@Ahk2Exe-AddResource %U_AxLib%\themes\base.css, AX_THEMES_BASE_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\builder.css, AX_THEMES_BUILDER_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\win11.css, AX_THEMES_WIN11_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\win98.css, AX_THEMES_WIN98_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\winxp.css, AX_THEMES_WINXP_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\win365.css, AX_THEMES_WIN365_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\cyber.css, AX_THEMES_CYBER_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\rpg.css, AX_THEMES_RPG_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\cozy.css, AX_THEMES_COZY_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\aurora.css, AX_THEMES_AURORA_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\instrument.css, AX_THEMES_INSTRUMENT_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\precision.css, AX_THEMES_PRECISION_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\inset.css, AX_THEMES_INSET_CSS
;@Ahk2Exe-AddResource %U_AxLib%\themes\brutalist.css, AX_THEMES_BRUTALIST_CSS
;@Ahk2Exe-AddResource %U_AxLib%\ui\frame.html, AX_UI_FRAME_HTML
;@Ahk2Exe-AddResource %U_AxLib%\ui\resize.html, AX_UI_RESIZE_HTML
;@Ahk2Exe-AddResource %U_AxLib%\ui\overlays.html, AX_UI_OVERLAYS_HTML
;@Ahk2Exe-AddResource %U_AxLib%\icons\info.png, AX_ICONS_INFO_PNG
;@Ahk2Exe-AddResource %U_AxLib%\icons\warning.png, AX_ICONS_WARNING_PNG
;@Ahk2Exe-AddResource %U_AxLib%\icons\error.png, AX_ICONS_ERROR_PNG
