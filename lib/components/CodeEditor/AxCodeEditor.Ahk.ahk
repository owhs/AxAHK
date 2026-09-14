#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; =============================================================================
;  AxCodeEditor.Ahk.ahk -- the built-in AutoHotkey language service.
;
;      ed.UseAhk()                       ; suggestions and hovers
;      ed.UseAhk({Lint: true})           ; and AutoHotkey's own /validate as the problems
;
;  What it knows: AutoHotkey v2's functions with their parameters, the members
;  of its common objects, and whatever the text itself defines -- functions,
;  classes with their methods, variables, hotkeys. After "Name." it offers that
;  class's own members when the text defines it, and the common ones when it
;  does not. A hover shows a function's parameters, or the line that defines
;  a name of the text's own and the comment above it.
;
;  Its function list goes to the page once, as words with their parameters,
;  so the page ranks them itself while you type and shows the parameters card
;  after "(" -- AutoHotkey is only asked after a "." (the members of a class).
;  It answers only while the editor's language is AutoHotkey.
;
;  Lint runs the AutoHotkey that is running this script (A_AhkPath) with
;  /validate on a copy of the text -- nothing in it runs -- and turns what it
;  reports into problems under the text. It is started straight (no console,
;  so no window), in the background, one at a time: the window never waits
;  for it, and a check still running when the text changes again is followed
;  by one more when it ends.
; =============================================================================
class AxCodeEditorAhk {
    ; Name(parameters) -- ? marks the ones that may be left out
    static Funcs := "
    (
Abs(Number)
ASin(Number)
ACos(Number)
ATan(Number)
BlockInput(Option)
Buffer(ByteCount?, FillByte?)
CallbackCreate(Function, Options?, ParamCount?)
CallbackFree(Address)
CaretGetPos(&OutputVarX?, &OutputVarY?)
Ceil(Number)
Chr(Number)
Click(Options*)
ClipboardAll(Data?, Size?)
ClipWait(Timeout?, WaitFor?)
ComCall(Index, ComObj, Params*)
ComObjActive(CLSID)
ComObjConnect(ComObj, PrefixOrSink?)
ComObject(CLSID, IID?)
ComObjFromPtr(DispPtr)
ComObjGet(Name)
ComObjQuery(ComObj, SID?, IID)
ComObjType(ComObj, InfoType?)
ComObjValue(ComObj)
ControlClick(ControlOrPos?, WinTitle?, WinText?, WhichButton?, ClickCount?, Options?)
ControlFocus(Control, WinTitle?, WinText?)
ControlGetHwnd(Control, WinTitle?, WinText?)
ControlGetText(Control, WinTitle?, WinText?)
ControlSend(Keys, Control?, WinTitle?, WinText?)
ControlSetText(NewText, Control, WinTitle?, WinText?)
CoordMode(TargetType, RelativeTo?)
Cos(Number)
Critical(OnOffNumeric?)
DateAdd(DateTime, Time, TimeUnits)
DateDiff(DateTime1, DateTime2, TimeUnits)
DetectHiddenWindows(Mode)
DirCopy(Source, Dest, Overwrite?)
DirCreate(DirName)
DirDelete(DirName, Recurse?)
DirExist(FilePattern)
DirMove(Source, Dest, OverwriteOrRename?)
DirSelect(StartingFolder?, Options?, Prompt?)
DllCall(DllFile_Function, Type1?, Arg1?, ReturnType?)
Download(URL, Filename)
DriveGetList(Type?)
Edit()
EnvGet(EnvVar)
EnvSet(EnvVar, Value?)
Exit(ExitCode?)
ExitApp(ExitCode?)
Exp(N)
FileAppend(Text, Filename?, Options?)
FileCopy(SourcePattern, DestPattern, Overwrite?)
FileCreateShortcut(Target, LinkFile, WorkingDir?, Args?, Description?, IconFile?, ShortcutKey?, IconNumber?, RunState?)
FileDelete(FilePattern)
FileEncoding(Encoding?)
FileExist(FilePattern)
FileGetAttrib(Filename?)
FileGetSize(Filename?, Units?)
FileGetTime(Filename?, WhichTime?)
FileGetVersion(Filename?)
FileMove(SourcePattern, DestPattern, Overwrite?)
FileOpen(Filename, Flags, Encoding?)
FileRead(Filename, Options?)
FileRecycle(FilePattern)
FileSelect(Options?, RootDir_Filename?, Title?, Filter?)
FileSetAttrib(Attributes, FilePattern?, Mode?)
FileSetTime(YYYYMMDDHH24MISS?, FilePattern?, WhichTime?, Mode?)
Float(Value)
Floor(Number)
Format(FormatStr, Values*)
FormatTime(YYYYMMDDHH24MISS?, Format?)
GetKeyName(KeyName)
GetKeySC(KeyName)
GetKeyState(KeyName, Mode?)
GetKeyVK(KeyName)
GroupAdd(GroupName, WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
Gui(Options?, Title?, EventObj?)
GuiCtrlFromHwnd(Hwnd)
GuiFromHwnd(Hwnd, RecurseParent?)
HasBase(Value, BaseObj)
HasMethod(Value, Name?, ParamCount?)
HasProp(Value, Name)
Hotkey(KeyName, Callback?, Options?)
Hotstring(String, Replacement?, OnOffToggle?)
IL_Add(ImageListID, Filename, IconNumber?, ResizeNonIcon?)
IL_Create(InitialCount?, GrowCount?, LargeIcons?)
ImageSearch(&OutputVarX, &OutputVarY, X1, Y1, X2, Y2, ImageFile)
IniDelete(Filename, Section, Key?)
IniRead(Filename, Section?, Key?, Default?)
IniWrite(Value, Filename, Section, Key?)
InputBox(Prompt?, Title?, Options?, Default?)
InputHook(Options?, EndKeys?, MatchList?)
InStr(Haystack, Needle, CaseSense?, StartingPos?, Occurrence?)
Integer(Value)
IsAlnum(Value, Mode?)
IsAlpha(Value, Mode?)
IsDigit(Value)
IsFloat(Value)
IsInteger(Value)
IsLabel(LabelName)
IsNumber(Value)
IsObject(Value)
IsSet(Var)
IsSpace(Value)
IsXDigit(Value)
KeyHistory(MaxEvents?)
KeyWait(KeyName, Options?)
ListLines(Mode?)
ListVars()
Ln(Number)
LoadPicture(Filename, Options?, &OutImageType?)
Log(Number)
LTrim(String, OmitChars?)
Map(Key1?, Value1?)
Max(Numbers*)
Menu()
MenuBar()
MenuFromHandle(Handle)
Min(Numbers*)
Mod(Dividend, Divisor)
MonitorGet(N?, &Left?, &Top?, &Right?, &Bottom?)
MonitorGetCount()
MonitorGetPrimary()
MonitorGetWorkArea(N?, &Left?, &Top?, &Right?, &Bottom?)
MouseClick(WhichButton?, X?, Y?, ClickCount?, Speed?, DownOrUp?, Relative?)
MouseClickDrag(WhichButton, X1, Y1, X2, Y2, Speed?, Relative?)
MouseGetPos(&OutputVarX?, &OutputVarY?, &OutputVarWin?, &OutputVarControl?, Flag?)
MouseMove(X, Y, Speed?, Relative?)
MsgBox(Text?, Title?, Options?)
Number(Value)
NumGet(Source, Offset?, Type)
NumPut(Type, Number, Target, Offset?)
ObjAddRef(Ptr)
ObjBindMethod(Obj, Method?, Params*)
ObjGetBase(Value)
ObjHasOwnProp(Obj, Name)
ObjOwnPropCount(Obj)
ObjPtr(Obj)
ObjRelease(Ptr)
ObjSetBase(Obj, BaseObj)
OnClipboardChange(Callback, AddRemove?)
OnError(Callback, AddRemove?)
OnExit(Callback, AddRemove?)
OnMessage(MsgNumber, Callback?, MaxThreads?)
Ord(String)
OutputDebug(Text)
Pause(NewState?)
Persistent(Persist?)
PixelGetColor(X, Y, Mode?)
PixelSearch(&OutputVarX, &OutputVarY, X1, Y1, X2, Y2, ColorID, Variation?)
PostMessage(Msg, wParam?, lParam?, Control?, WinTitle?, WinText?)
ProcessClose(PIDOrName)
ProcessExist(PIDOrName?)
ProcessGetName(PIDOrName?)
ProcessGetPath(PIDOrName?)
ProcessSetPriority(Level, PIDOrName?)
ProcessWait(PIDOrName, Timeout?)
ProcessWaitClose(PIDOrName, Timeout?)
Random(A?, B?)
RegCreateKey(KeyName?)
RegDelete(KeyName?, ValueName?)
RegExMatch(Haystack, NeedleRegEx, &OutputVar?, StartingPos?)
RegExReplace(Haystack, NeedleRegEx, Replacement?, &OutputVarCount?, Limit?, StartingPos?)
RegRead(KeyName?, ValueName?, Default?)
RegWrite(Value, ValueType, KeyName?, ValueName?)
Reload()
Round(Number, N?)
RTrim(String, OmitChars?)
Run(Target, WorkingDir?, Options?, &OutputVarPID?)
RunAs(User?, Password?, Domain?)
RunWait(Target, WorkingDir?, Options?, &OutputVarPID?)
Send(Keys)
SendEvent(Keys)
SendInput(Keys)
SendLevel(Level)
SendMessage(Msg, wParam?, lParam?, Control?, WinTitle?, WinText?, ExcludeTitle?, ExcludeText?, Timeout?)
SendMode(Mode)
SendPlay(Keys)
SendText(Keys)
SetCapsLockState(State?)
SetControlDelay(Delay)
SetKeyDelay(Delay?, PressDuration?, Play?)
SetMouseDelay(Delay, Play?)
SetNumLockState(State?)
SetRegView(RegView)
SetScrollLockState(State?)
SetStoreCapsLockMode(Mode)
SetTimer(Function?, Period?, Priority?)
SetTitleMatchMode(MatchMode)
SetWinDelay(Delay)
SetWorkingDir(DirName)
Shutdown(Flag)
Sin(Number)
Sleep(Delay)
Sort(String, Options?, Function?)
SoundBeep(Frequency?, Duration?)
SoundGetVolume(Component?, Device?)
SoundPlay(Filename, Wait?)
SoundSetVolume(NewSetting, Component?, Device?)
SplitPath(Path, &OutFileName?, &OutDir?, &OutExtension?, &OutNameNoExt?, &OutDrive?)
Sqrt(Number)
StatusBarGetText(Part#?, WinTitle?, WinText?)
StrCompare(String1, String2, CaseSense?)
StrGet(Source, Length?, Encoding?)
String(Value)
StrLen(String)
StrLower(String)
StrPtr(Value)
StrPut(String, Target?, Length?, Encoding?)
StrReplace(Haystack, Needle, ReplaceText?, CaseSense?, &OutputVarCount?, Limit?)
StrSplit(String, Delimiters?, OmitChars?, MaxParts?)
StrTitle(String)
StrUpper(String)
SubStr(String, StartingPos, Length?)
Suspend(NewState?)
SysGet(Property)
SysGetIPAddresses()
Tan(Number)
Thread(SubFunction, Value1?, Value2?)
ToolTip(Text?, X?, Y?, WhichToolTip?)
TraySetIcon(FileName?, IconNumber?, Freeze?)
TrayTip(Text?, Title?, Options?)
Trim(String, OmitChars?)
Type(Value)
VarSetStrCapacity(&TargetVar, RequestedCapacity?)
VerCompare(VersionA, VersionB)
WinActivate(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinActive(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinClose(WinTitle?, WinText?, SecondsToWait?, ExcludeTitle?, ExcludeText?)
WinExist(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinGetClass(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinGetID(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinGetList(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinGetMinMax(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinGetPID(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinGetPos(&OutX?, &OutY?, &OutWidth?, &OutHeight?, WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinGetProcessName(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinGetText(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinGetTitle(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinHide(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinKill(WinTitle?, WinText?, SecondsToWait?, ExcludeTitle?, ExcludeText?)
WinMaximize(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinMinimize(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinMove(X?, Y?, Width?, Height?, WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinRestore(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinSetAlwaysOnTop(Value?, WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinSetTitle(NewTitle, WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinSetTransparent(N, WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinShow(WinTitle?, WinText?, ExcludeTitle?, ExcludeText?)
WinWait(WinTitle?, WinText?, Timeout?, ExcludeTitle?, ExcludeText?)
WinWaitActive(WinTitle?, WinText?, Timeout?, ExcludeTitle?, ExcludeText?)
WinWaitClose(WinTitle?, WinText?, Timeout?, ExcludeTitle?, ExcludeText?)
    )"
    ; the members of the objects a script most often has in hand
    static Members := "
    (
Push(Values*)|Array
Pop()|Array
InsertAt(Index, Values*)|Array
RemoveAt(Index, Length?)|Array
Has(Index_Key)|Array, Map
Get(Index_Key, Default?)|Array, Map
Set(Key, Value)|Map
Delete(Key)|Map
Clear()|Map
Clone()|Array, Map, Object
Length|Array
Count|Map
Capacity|Array, Map
CaseSense|Map
Default|Array, Map
__Enum(NumberOfVars)|Array, Map
DefineProp(Name, Desc)|Object
DeleteProp(Name)|Object
GetOwnPropDesc(Name)|Object
HasOwnProp(Name)|Object
OwnProps()|Object
HasMethod(Name)|Any
HasProp(Name)|Any
Call(Params*)|Func
Bind(Params*)|Func
Name|Func, Gui control
MinParams|Func
MaxParams|Func
Add(ControlType, Options?, Text?)|Gui
AddText(Options?, Text?)|Gui
AddEdit(Options?, Text?)|Gui
AddButton(Options?, Text?)|Gui
AddCheckbox(Options?, Text?)|Gui
AddRadio(Options?, Text?)|Gui
AddDropDownList(Options?, Items?)|Gui
AddComboBox(Options?, Items?)|Gui
AddListBox(Options?, Items?)|Gui
AddListView(Options?, Titles?)|Gui
AddTreeView(Options?)|Gui
AddPicture(Options?, Filename?)|Gui
AddSlider(Options?, Value?)|Gui
AddProgress(Options?, Value?)|Gui
AddTab3(Options?, Pages?)|Gui
Show(Options?)|Gui
Hide()|Gui
Destroy()|Gui
Submit(Hide?)|Gui
OnEvent(EventName, Callback, AddRemove?)|Gui, Gui control
SetFont(Options?, FontName?)|Gui, Gui control
Opt(Options)|Gui, Gui control
Move(X?, Y?, Width?, Height?)|Gui, Gui control
GetPos(&X?, &Y?, &Width?, &Height?)|Gui, Gui control
Title|Gui
BackColor|Gui
MarginX|Gui
MarginY|Gui
MenuBar|Gui
Hwnd|Gui, Gui control
Value|Gui control
Text|Gui control
Enabled|Gui control
Visible|Gui control
Focus()|Gui control
Choose(Value)|Gui control
UseTab(Value?, ExactMatch?)|Gui control
Read(Characters?)|File
Write(String)|File
ReadLine()|File
WriteLine(String?)|File
Close()|File
AtEOF|File
Pos|File
Size|File
Pos[N]|RegExMatchInfo
Len[N]|RegExMatchInfo
Count|RegExMatchInfo
Message|Error
What|Error
Extra|Error
File|Error
Line|Error
Stack|Error
    )"

    ; ------------------------------------------------------------- wiring
    static Attach(ed, opts := "") {
        o := (n, d) => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        ed.SetWordSet("ahk", AxCodeEditorAhk.Words(), "ahk")
        ed.OnComplete((req, e) => AxCodeEditorAhk.Complete(req, e))
        ed.SetOption("remote", "scope")
        ed.OnHover((word, e, q) => AxCodeEditorAhk.Hover(word, e))
        if o("Lint", false)
            ed.OnLint((text, e) => AxCodeEditorAhk.LintLater(text, e, opts))
        return ed
    }
    ;  UseAhk({Lint: true, Warn: false, Wrap: fn})  -- Warn: false checks the
    ;  syntax only (a piece of a script, whose globals are elsewhere); Wrap:
    ;  fn(text) -> [before, after], what the text sits between when it is
    ;  checked (a handler's body inside its function), or "" not to check it
    ;  now. The lines the problems are on stay the text's own.
    static IsAhk(ed) => !(ed.Cfg.HasOwnProp("lang") && ed.Cfg.lang != "ahk")
    ; the functions, as the page's words: {label, kind, detail}
    static Words() {
        static list := ""
        if IsObject(list)
            return list
        list := []
        for line in StrSplit(AxCodeEditorAhk.Funcs, "`n", "`r")
            if (line != "")
                list.Push(Map("label", RegExReplace(line, "\(.*$"), "kind", "fn", "detail", SubStr(line, InStr(line, "("))))
        return list
    }

    ; ---------------------------------------------------------- suggestions
    static Complete(req, ed) {
        if !AxCodeEditorAhk.IsAhk(ed)
            return []
        text := req.text, scope := req.scope, out := []
        if (scope != "") {
            own := AxCodeEditorAhk.ClassMembers(text, scope)
            for it in own
                out.Push(it)
            if !own.Length
                for line in StrSplit(AxCodeEditorAhk.Members, "`n", "`r") {
                    parts := StrSplit(line, "|")
                    sig := parts[1]
                    name := RegExReplace(sig, "\(.*$")
                    out.Push({label: name, kind: InStr(sig, "(") ? "method" : "prop", detail: parts.Length > 1 ? parts[2] : "",
                              insert: name (InStr(sig, "()") ? "()" : "")})
                }
            return out
        }
        ; only what begins with what was typed: the page does not need the lot
        w := req.word
        Starts(name) => (w = "" || SubStr(name, 1, StrLen(w)) = w)
        for sym in AxCodeEditorAhk.Defined(text)
            if Starts(sym.Name)
                out.Push({label: sym.Name, kind: sym.Kind, detail: sym.Detail})
        for line in StrSplit(AxCodeEditorAhk.Funcs, "`n", "`r")
            if (line != "" && Starts(line) && out.Length < 200)
                out.Push({label: RegExReplace(line, "\(.*$"), kind: "fn", detail: SubStr(line, InStr(line, "("))})
        return out
    }
    ; what the text defines: functions, classes, hotkeys, the variables it assigns
    static Defined(text) {
        out := [], seen := Map()
        seen.CaseSense := false
        Add(name, kind, detail) {
            if (name = "" || seen.Has(name))
                return
            seen[name] := true
            out.Push({Name: name, Kind: kind, Detail: detail})
        }
        for line in StrSplit(text, "`n", "`r") {
            if RegExMatch(line, "i)^\s*class\s+([A-Za-z_]\w*)(?:\s+extends\s+([\w.]+))?", &m)
                Add(m[1], "class", m[2] != "" ? "extends " m[2] : "class")
            else if RegExMatch(line, "^\s*(?:static\s+)?([A-Za-z_]\w*)\(([^)]*)\)\s*(?:\{|=>)", &m)
                && !RegExMatch(m[1], "i)^(if|while|for|switch|loop|catch|return)$")
                Add(m[1], "fn", "(" m[2] ")")
            else if RegExMatch(line, "^\s*([A-Za-z_]\w*)\s*:=", &m)
                Add(m[1], "var", "variable")
        }
        return out
    }
    ; the methods and properties of a class the text defines
    static ClassMembers(text, cls) {
        out := []
        if !RegExMatch(text, "im)^\s*class\s+\Q" cls "\E\b[^\n]*\{", &m)
            return out
        depth := 0, started := false
        for line in StrSplit(SubStr(text, m.Pos), "`n", "`r") {
            if started && depth = 1 {
                if RegExMatch(line, "^\s*(?:static\s+)?([A-Za-z_]\w*)\(([^)]*)\)\s*(?:\{|=>)", &f) && f[1] != "__New"
                    out.Push({label: f[1], kind: "method", detail: "(" f[2] ")", insert: f[1] "()"})
                else if RegExMatch(line, "^\s*(?:static\s+)?([A-Za-z_]\w*)\s*(?::=|=>|\{)", &f)
                    out.Push({label: f[1], kind: "prop", detail: cls})
            }
            depth += StrLen(RegExReplace(line, "[^{]")) - StrLen(RegExReplace(line, "[^}]"))
            if (depth >= 1)
                started := true
            else if started
                break
        }
        return out
    }

    ; --------------------------------------------------------------- hovers
    static Hover(word, ed) {
        if !AxCodeEditorAhk.IsAhk(ed)
            return ""
        for line in StrSplit(AxCodeEditorAhk.Funcs, "`n", "`r")
            if (RegExReplace(line, "\(.*$") = word)
                return "<code>" AxWindow._Esc(line) "</code><br><span style='opacity:.7'>AutoHotkey</span>"
        text := ed.Value, lines := StrSplit(text, "`n", "`r")
        for i, line in lines {
            if RegExMatch(line, "i)^\s*(?:static\s+)?(?:class\s+)?\Q" word "\E\b\s*(\(|extends|\{|:=)") {
                note := ""
                j := i - 1
                while (j >= 1 && RegExMatch(lines[j], "^\s*;\s?(.*)$", &c))
                    note := c[1] (note = "" ? "" : "<br>") note, j--
                return "<code>" AxWindow._Esc(Trim(line)) "</code><br><span style='opacity:.7'>line " i "</span>"
                    . (note != "" ? "<br>" AxWindow._Esc(note) : "")
            }
        }
        return ""
    }

    ; ----------------------------------------------------------------- lint
    ; AutoHotkey's own opinion: /validate, warnings on, nothing run. This one
    ; waits for the answer; the editor uses LintLater, which does not.
    static Lint(text) {
        job := AxCodeEditorAhk._Spawn(text, "code")
        if !job
            return []
        DllCall("WaitForSingleObject", "Ptr", job.Proc, "UInt", 10000)
        return AxCodeEditorAhk._Done(job)
    }
    ; in the background: the problems arrive when AutoHotkey has looked
    static LintLater(text, ed, opts := "") {
        if !AxCodeEditorAhk.IsAhk(ed)
            return []
        wrap := ["", ""]
        if (IsObject(opts) && opts.HasOwnProp("Wrap") && HasMethod(opts.Wrap)) {
            wrap := opts.Wrap.Call(text)
            if !IsObject(wrap)
                return []                           ; not to be checked just now
        }
        ed._lintWrap := wrap
        ed._lintWarn := !(IsObject(opts) && opts.HasOwnProp("Warn") && !opts.Warn)
        ed._lintText := text
        if !ed.HasOwnProp("_lintFn")
            ed._lintFn := AxCodeEditorAhk._LintStart.Bind(AxCodeEditorAhk, ed), ed._lintJob := ""
        SetTimer(ed._lintFn, -200)
        return ""
    }
    static _LintStart(ed) {
        if IsObject(ed._lintJob)                    ; one at a time: again when this one ends
            return ed._lintAgain := true
        job := AxCodeEditorAhk._Spawn(ed._lintText, "code_" ObjPtr(ed), ed._lintWarn, ed._lintWrap[1], ed._lintWrap[2])
        if !job
            return
        ed._lintJob := job, ed._lintAgain := false
        ed._lintPoll := AxCodeEditorAhk._LintPoll.Bind(AxCodeEditorAhk, ed)
        SetTimer(ed._lintPoll, 40)
    }
    static _LintPoll(ed) {
        job := ed._lintJob
        if !IsObject(job)
            return SetTimer(ed._lintPoll, 0)
        if (DllCall("WaitForSingleObject", "Ptr", job.Proc, "UInt", 0) = 0x102) {     ; still looking
            if (A_TickCount - job.At < 10000)
                return
            DllCall("TerminateProcess", "Ptr", job.Proc, "UInt", 1)                  ; only the one it started
        }
        SetTimer(ed._lintPoll, 0)
        ed._lintJob := ""
        marks := AxCodeEditorAhk._Done(job)
        if AxCodeEditorAhk.IsAhk(ed)
            try ed.SetMarks(marks)
        if ed._lintAgain
            SetTimer(ed._lintFn, -1)
    }
    ; AutoHotkey started straight, with its output going to a file: no
    ; console between, so nothing shows and nothing takes the focus
    static _Spawn(text, name, warn := true, before := "", after := "") {
        dir := A_Temp "\axce_lint"
        if !DirExist(dir)
            DirCreate(dir)
        src := dir "\" name ".ahk", wrap := dir "\" name "_wrap.ahk", out := dir "\" name ".txt"
        ; The text's own #Warn is put out of the way (a comment, so the lines
        ; keep their numbers): a plain "#Warn" means warnings in a message box,
        ; and it came after ours, so a script with one put a warning dialog on
        ; the screen every time it was checked. Ours is said again after it too.
        text := RegExReplace(text, "im)^([ \t]*)#Warn\b", "$1;#Warn")
        before := RegExReplace(before, "im)^([ \t]*)#Warn\b", "$1;#Warn")
        after := RegExReplace(after, "im)^([ \t]*)#Warn\b", "$1;#Warn")
        try FileDelete(src)
        FileAppend(before text after, src, "UTF-8")
        try FileDelete(wrap)
        w := "#Warn All, " (warn ? "StdOut" : "Off") "`n"
        FileAppend("#Requires AutoHotkey v2.0`n#NoTrayIcon`n" w "#Include " src "`n" w, wrap, "UTF-8")
        sa := Buffer(A_PtrSize = 8 ? 24 : 12, 0)
        NumPut("UInt", sa.Size, sa, 0), NumPut("Int", 1, sa, A_PtrSize = 8 ? 16 : 8)        ; inheritable
        h := DllCall("CreateFileW", "WStr", out, "UInt", 0x40000000, "UInt", 3, "Ptr", sa, "UInt", 2, "UInt", 0x80, "Ptr", 0, "Ptr")
        if (h = -1 || !h)
            return ""
        si := Buffer(A_PtrSize = 8 ? 104 : 68, 0)
        NumPut("UInt", si.Size, si, 0)
        NumPut("UInt", 0x100, si, A_PtrSize = 8 ? 60 : 44)                                 ; STARTF_USESTDHANDLES
        NumPut("Ptr", h, si, A_PtrSize = 8 ? 88 : 60)
        NumPut("Ptr", h, si, A_PtrSize = 8 ? 96 : 64)
        pi := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
        cmd := '"' A_AhkPath '" /ErrorStdOut=UTF-8 /validate "' wrap '"'
        ok := DllCall("CreateProcessW", "Ptr", 0, "Str", cmd, "Ptr", 0, "Ptr", 0, "Int", 1,
                      "UInt", 0x08000000, "Ptr", 0, "Str", dir, "Ptr", si, "Ptr", pi)          ; CREATE_NO_WINDOW
        DllCall("CloseHandle", "Ptr", h)
        if !ok
            return ""
        DllCall("CloseHandle", "Ptr", NumGet(pi, A_PtrSize, "Ptr"))
        shift := StrLen(before) - StrLen(StrReplace(before, "`n"))
        lines := StrLen(text) - StrLen(StrReplace(text, "`n")) + 1
        return {Proc: NumGet(pi, 0, "Ptr"), Out: out, Src: name ".ahk", At: A_TickCount, Shift: shift, Lines: lines}
    }
    static _Done(job) {
        DllCall("CloseHandle", "Ptr", job.Proc)
        report := ""
        try report := FileRead(job.Out, "UTF-8")
        marks := []
        pos := 1
        while (pos := RegExMatch(report, "m)^(.*?) \((\d+)\) : ==> (.*)$", &m, pos)) {
            pos += m.Len
            if !InStr(m[1], job.Src)
                continue
            msg := Trim(m[3])
            if RegExMatch(SubStr(report, pos, 300), "^\R\s*Specifically: (.*)", &sp)
                msg .= ": " Trim(sp[1])
            ; back to the text's own lines, when it was checked inside something
            ln := Integer(m[2]) - (job.HasOwnProp("Shift") ? job.Shift : 0)
            if job.HasOwnProp("Lines")
                ln := Max(1, Min(ln, job.Lines))
            marks.Push({line: ln, col: 1, sev: InStr(msg, "Warning") ? "warn" : "error", msg: msg})
        }
        return marks
    }
}
