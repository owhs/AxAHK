#Requires AutoHotkey v2.0
; =============================================================================
;  RegisterBrowserEmulation.ahk
;  Writes FEATURE_BROWSER_EMULATION = 11001 (IE11 edge mode) for the
;  AutoHotkey host executables and, optionally, your compiled script name.
;
;  Usage:
;     RegisterBrowserEmulation.ahk                -> HKCU only (no admin needed)
;     RegisterBrowserEmulation.ahk /machine       -> also HKLM (asks for admin)
;     RegisterBrowserEmulation.ahk /remove        -> delete the HKCU values
;     RegisterBrowserEmulation.ahk MyApp.exe ...  -> extra exe names to register
;
;  The library already writes the HKCU value itself, so this is only needed
;  for machine-wide deployment or when a locked-down HKCU is ignored.
; =============================================================================

VALUE := 11001
KEY   := "Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION"
names := ["AutoHotkey.exe", "AutoHotkey32.exe", "AutoHotkey64.exe", "AutoHotkeyU64.exe", "AutoHotkeyU32.exe", "AutoHotkeyA32.exe"]
machine := false, remove := false
for a in A_Args {
    if (a = "/machine")
        machine := true
    else if (a = "/remove")
        remove := true
    else
        names.Push(a)
}

if machine && !A_IsAdmin {
    try {
        Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '" ' JoinArgs(A_Args))
    } catch {
        MsgBox("Administrator rights were declined; HKLM was not written.", "Browser emulation", "Icon!")
    }
    ExitApp()
}

done := "", failed := ""
for hive in (machine ? ["HKCU", "HKLM"] : ["HKCU"]) {
    for n in names {
        try {
            if remove
                RegDelete(hive "\" KEY, n)
            else
                RegWrite(VALUE, "REG_DWORD", hive "\" KEY, n)
            done .= hive "\" n "`n"
        } catch as e {
            failed .= hive "\" n " (" e.Message ")`n"
        }
    }
}
msg := (remove ? "Removed:`n" : "Set to " VALUE " (IE11 mode):`n") done
if failed
    msg .= "`nFailed:`n" failed
msg .= "`nRestart any running script for the change to take effect."
MsgBox(msg, "Browser emulation", failed ? "Icon!" : "Iconi")

JoinArgs(arr) {
    s := ""
    for a in arr
        s .= '"' a '" '
    return s
}
