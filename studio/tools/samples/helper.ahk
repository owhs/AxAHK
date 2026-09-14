#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
SendMode("Input")
SetTitleMatchMode(2)
DetectHiddenWindows(true)
SetWorkingDir(A_ScriptDir)
Persistent()
TraySetIcon("shell32.dll")
A_IconTip := "My helper"
A_TrayMenu.Add("Say hi", SayHi)
count := 0
greeting := "Hello"
SetTimer(Tick, 60000)
SetTimer(Remind, -5000)
OnClipboardChange(ClipChanged)

^!n::Run("notepad.exe")
^!h::SayHi()
F9:: {
    Send("^c")
    Sleep(100)
    MsgBox("Copied")
}
F10::count += 1
CapsLock::Ctrl

#HotIf WinActive("ahk_exe notepad.exe")
^s::Send("^s")
F2::SendText("signed")
#HotIf

#HotIf GetKeyState("CapsLock", "T")
F3::SoundBeep()
#HotIf

::btw::by the way
:*:sig::Kind regards
::now:: {
    SendText("today")
}

SayHi(*) {
    MsgBox(greeting)
}
Tick() {
    SoundBeep()
}
Remind() {
    global count
    ToolTip("count " count)
}
ClipChanged(kind) {
    ToolTip("clip")
}
