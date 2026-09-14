#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\..\lib\AxGui.ahk
#Include %A_LineFile%\..\AxStudio.Model.ahk
#Include %A_LineFile%\..\AxStudio.Assets.ahk
#Include %A_LineFile%\..\AxStudio.Bind.ahk
#Include %A_LineFile%\..\AxStudio.Gen.ahk

; =============================================================================
;  AxStudio.Complete.ahk -- what the editor offers when you type.
;
;  The member lists are read off the live classes rather than typed out here,
;  so `g.` offers exactly what this copy of the library actually has. A list
;  written by hand goes stale the first time somebody adds a method; this one
;  cannot.
;
;  Handed to the editor as JSON once, at start-up.
; =============================================================================
class AxComplete {

    ; Every public method and property on a class and its bases.
    static Members(cls) {
        seen := Map(), out := []
        proto := cls.Prototype
        while IsObject(proto) {
            for name in proto.OwnProps() {
                if (SubStr(name, 1, 1) = "_" || name = "__Class" || name = "__Init" || seen.Has(name))
                    continue
                seen[name] := true
                out.Push(name)
            }
            proto := proto.Base
            if (IsObject(proto) && proto.HasOwnProp("__Class") && proto.__Class = "Object")
                break
        }
        return AxComplete.Sort(out)
    }
    static Statics(cls) {
        seen := Map(), out := []
        for name in cls.OwnProps() {
            if (SubStr(name, 1, 1) = "_" || name = "Prototype" || name = "__Class" || name = "__Init" || seen.Has(name))
                continue
            seen[name] := true
            out.Push(name)
        }
        return AxComplete.Sort(out)
    }
    static Sort(arr) {
        s := ""
        for x in arr
            s .= x "`n"
        s := Sort(RTrim(s, "`n"), "C")
        return StrSplit(s, "`n")
    }

    ; AHK v2's own vocabulary. This part cannot be introspected -- built-in
    ; functions are not enumerable -- so it is a list, kept to the ones a GUI
    ; handler actually reaches for.
    static Builtins := ["Abs", "Array", "Buffer", "Ceil", "Chr", "ClipWait", "ComObject", "ComObjGet",
        "ControlSend", "CoordMode", "DirCreate", "DirExist", "DirSelect", "DllCall", "Download", "Edit",
        "Exp", "FileAppend", "FileCopy", "FileDelete", "FileExist", "FileGetSize", "FileGetTime", "FileMove",
        "FileOpen", "FileRead", "FileRecycle", "FileSelect", "Floor", "Format", "FormatTime", "Func",
        "GetKeyState", "HasMethod", "HasProp", "Hotkey", "IniDelete", "IniRead", "IniWrite", "InputBox",
        "InStr", "Integer", "IsAlpha", "IsDigit", "IsNumber", "IsObject", "IsSet", "KeyWait", "Log", "LTrim",
        "Map", "Max", "Min", "Mod", "MouseGetPos", "MsgBox", "Number", "ObjBindMethod", "ObjOwnPropCount",
        "OnError", "OnExit", "ProcessClose", "ProcessExist", "ProcessWait", "Random", "RegDelete", "RegExMatch",
        "RegExReplace", "RegRead", "RegWrite", "Round", "RTrim", "Run", "RunWait", "Send", "SendInput",
        "SetTimer", "Sleep", "Sort", "SplitPath", "Sqrt", "StrGet", "StrLen", "StrLower", "StrPut",
        "StrReplace", "StrSplit", "StrTitle", "StrUpper", "SubStr", "SysGet", "Trim", "Type", "VarSetStrCapacity",
        "WinActivate", "WinClose", "WinExist", "WinGetPos", "WinGetTitle", "WinMove", "WinSetAlwaysOnTop",
        "WinWait", "WinWaitClose"]

    static Vars := ["A_AhkPath", "A_AppData", "A_ComputerName", "A_Desktop", "A_Index", "A_LineNumber",
        "A_LoopField", "A_LoopFileFullPath", "A_LoopFileName", "A_MyDocuments", "A_Now", "A_ProgramFiles",
        "A_ScreenHeight", "A_ScreenWidth", "A_ScriptDir", "A_ScriptFullPath", "A_ScriptName", "A_Space",
        "A_Tab", "A_Temp", "A_TickCount", "A_UserName", "A_WorkingDir", "A_YYYY", "A_MM", "A_DD", "A_Hour", "A_Min", "A_Sec"]

    static Keywords := ["and", "as", "break", "catch", "class", "continue", "else", "extends", "false",
        "finally", "for", "get", "global", "goto", "if", "in", "is", "local", "loop", "not", "or", "return",
        "set", "static", "super", "switch", "this", "throw", "true", "try", "unset", "until", "while"]

    ; The same, as the code editor's words (lib\components\CodeEditor): each
    ; member once, with every name it answers to after a dot as its scope --
    ; "g|this|settingsGui" for a window's, "ctl|()|btnOk|..." for a control's,
    ; "()" being what a call gives back (g.AddButton(...).). AutoHotkey's own
    ; functions and variables come from the editor's AutoHotkey service.
    static Words(project) {
        static kinds := Map()
        KindsOf(cls) {
            key := ObjPtr(cls)
            if kinds.Has(key)
                return kinds[key]
            res := [], seen := Map(), proto := cls.Prototype
            while IsObject(proto) {
                for pn in proto.OwnProps() {
                    if (SubStr(pn, 1, 1) = "_" || seen.Has(pn))
                        continue
                    seen[pn] := true
                    d := proto.GetOwnPropDesc(pn), m := d.HasOwnProp("Call")
                    args := m ? 1 : 0
                    try args := m ? d.Call.MaxParams - 1 : 0
                    res.Push({Name: pn, Kind: m ? "method" : "prop", Args: args})
                }
                proto := proto.Base
                if (IsObject(proto) && proto.HasOwnProp("__Class") && proto.__Class = "Object")
                    break
            }
            return kinds[key] := res
        }
        guiNames := ["g", "this"], ctlNames := ["ctl", "()"]
        globals := []
        project.WalkAll((n) => (n.Name != "" && n.Type != "Page" ? (ctlNames.Push(n.Name), globals.Push([n.Name, n.Type])) : "", false))
        for w in project.Wins {
            if (w.Kind = "main")
                continue
            guiNames.Push(w.Var)
            globals.Push([w.Var, "window"]), globals.Push([AxGen.Fn(w) , "opens the " w.Name " window"])
            if (w.Kind = "dialog")
                globals.Push([AxProject.CleanName(w.Name) "Result", "what the dialog gave back"])
        }
        for a in AxAsset.Args(project)
            globals.Push([a.Name, "argument"])
        for f in AxAsset.Files(project)
            globals.Push([AxAsset.FileFn(f.Name), "file"])
        if AxAsset.Modes(project).Length
            globals.Push(["Mode", "mode"])
        for v in AxBind.Vars(project)
            globals.Push([v.Name, "bound value"])
        out := [Map("label", "g", "kind", "var", "detail", "the window")]
        for x in globals
            out.Push(Map("label", x[1], "kind", InStr(x[2], "opens") ? "fn" : "var", "detail", x[2]))
        Join(a) {
            s := ""
            for x in a
                s .= (s = "" ? "" : "|") x
            return s
        }
        Add(list, scope, owner) {
            for it in list
                out.Push(Map("label", it.Name, "kind", it.Kind, "scope", scope, "detail", owner,
                             "insert", it.Kind = "method" ? it.Name (it.Args ? "($0)" : "()") : ""))
        }
        Add(KindsOf(AxGui), Join(guiNames), "AxGui")
        Add(KindsOf(AxGui.Control), Join(ctlNames), "control")
        for cls in [AxWindow, AxGui, AxSys, AxTags]
            for name in AxComplete.Statics(cls)
                out.Push(Map("label", name, "kind", "method", "scope", cls.Prototype.__Class, "detail", cls.Prototype.__Class))
        ; what the libraries the script uses offer, read out of their files
        try for w in AxPkg.Words(project)
            out.Push(w)
        return out
    }

    ; The whole completion table the editor works from. `scopes` is keyed by
    ; what sits before the dot; `globals` is what a bare word completes to.
    static Table(project) {
        scopes := Map()
        scopes["g"] := AxComplete.Members(AxGui)
        scopes["ctl"] := AxComplete.Members(AxGui.Control)
        scopes["this"] := AxComplete.Members(AxGui)
        scopes["AxWindow"] := AxComplete.Statics(AxWindow)
        scopes["AxGui"] := AxComplete.Statics(AxGui)
        scopes["AxSys"] := AxComplete.Statics(AxSys)
        scopes["AxTags"] := AxComplete.Statics(AxTags)
        ; every named control in this project answers to the same members a
        ; control does, so typing a control's own name works too. Every window,
        ; not just the one on screen: handlers reach across them, and the
        ; function that opens each of the others is offered as well.
        ctlMembers := scopes["ctl"]
        guiMembers := scopes["g"]
        names := []
        project.WalkAll((n) => (n.Name != "" && n.Type != "Page" ? (names.Push(n.Name), scopes[n.Name] := ctlMembers) : "", false))
        for w in project.Wins {
            if (w.Kind = "main")
                continue
            names.Push(AxGen.Fn(w))
            names.Push(w.Var)
            scopes[w.Var] := guiMembers
            if (w.Kind = "dialog")
                names.Push(AxProject.CleanName(w.Name) "Result")
        }

        ; The script's outside is code you can call: an argument is a global
        ; with that name, a file is File_<name>(), a mode is Mode("name"), and
        ; a binding value is a global too. All of them are things you would
        ; otherwise have to remember the spelling of.
        for a in AxAsset.Args(project)
            names.Push(a.Name)
        for f in AxAsset.Files(project)
            names.Push(AxAsset.FileFn(f.Name))
        if AxAsset.Modes(project).Length
            names.Push("Mode")
        for v in AxBind.Vars(project)
            names.Push(v.Name)

        globals := []
        for x in AxComplete.Builtins
            globals.Push(x)
        for x in AxComplete.Vars
            globals.Push(x)
        for x in AxComplete.Keywords
            globals.Push(x)
        for x in names
            globals.Push(x)
        globals.Push("g")

        out := Map()
        out["scopes"] := scopes
        out["globals"] := AxComplete.Sort(globals)
        return out
    }
}
