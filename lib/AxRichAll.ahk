#Requires AutoHotkey v2.0
; AxRichAll.ahk -- every component that ships with the library.
;
; They all live in lib\components now, one folder each, in the same shape
; as anything you write yourself. This file is the one-line way to have the
; lot, and is what the examples include.
;
;     #Include lib\AxRichAll.ahk
;
; Including lib\AxGui.ahk already brings them in, so this is only needed
; when you are using AxWindow directly.
#Include %A_LineFile%\..\components\_all.ahk
