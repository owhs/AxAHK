#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own.
#Include %A_LineFile%\..\AxStudio.Lit.ahk
; Diff() asks the generator what a handler would be called. Gen includes this
; file in turn; #Include loads a file once, so the pair resolves either way in.
#Include %A_LineFile%\..\AxStudio.Gen.ahk

; Part of AxStudio, not a program on its own.
if (A_LineFile = A_ScriptFullPath) {
    SplitPath(A_LineFile, , &axDir)
    axEntry := axDir "\AxStudio.ahk"
    if FileExist(axEntry)
        Run('"' A_AhkPath '" "' axEntry '"')
    else
        MsgBox("Run studio\AxStudio.ahk -- this file is only one part of it.", "AxStudio")
    ExitApp()
}

; =============================================================================
;  AxStudio.Merge.ahk -- the round trip.
;
;  An exported script used to be a dead end: the studio wrote it, and the
;  first hand edit made it un-re-exportable. Two things fix that.
;
;  A reference line near the top --
;
;      ; @axstudio project="Thing.axs.json"
;
;  -- names the project file sitting beside the script. A reference, not a
;  copy: embedding the whole design in the .ahk would give you two truths to
;  keep in step, and the one in the comment would always be the stale one.
;  File > Open takes a .ahk, follows the line, and opens the project.
;
;  Regions do the rest. Everything the studio writes lives between
;
;      ;#region axstudio NAME
;      ;#endregion axstudio NAME
;
;  and Merge() refills exactly those, leaving every line outside them where
;  it was. A hand-added #Include, a hotkey, a helper function, a comment --
;  all survive being re-generated. (The markers are the VS Code convention,
;  so the blocks fold there too.)
;
;  Harvest() is the other direction. It reads the code back out of a script,
;  so an edit made inside a generated block can be taken *into* the project
;  rather than silently overwritten by the next export. That is why the
;  generator indents handler bodies: a closing brace in the first column is
;  what tells this file where a function ended.
; =============================================================================

class AxMerge {
    static Ver := "1"

    ; --- markers ------------------------------------------------------
    static Open(name) => ";#region axstudio " name
    static Shut(name) => ";#endregion axstudio " name

    ; An empty region is still written out. It is the labelled place your own
    ; code goes, and the next Open reads it back into the project.
    static Region(name, body) {
        b := Trim(StrReplace(String(body), "`r`n", "`n"), "`n")
        return AxMerge.Open(name) "`n" (b != "" ? b "`n" : "") AxMerge.Shut(name) "`n"
    }

    ; --- the reference line -------------------------------------------
    static RefLine(rel) => '; @axstudio project="' rel '" v=' AxMerge.Ver

    ; What project a script claims to have come from, as written.
    static Ref(text) {
        if RegExMatch(text, 'im)^[ \t]*;[ \t]*@axstudio[ \t]+project[ \t]*=[ \t]*"([^"]*)"', &m)
            return m[1]
        return ""
    }

    ; The same thing resolved against the script's own folder.
    static RefPath(scriptPath, text := "") {
        if (text = "") {
            if !FileExist(scriptPath)
                return ""
            try text := FileRead(scriptPath, "UTF-8")
            catch
                return ""
        }
        r := AxMerge.Ref(text)
        if (r = "")
            return ""
        if RegExMatch(r, "^[A-Za-z]:[\\/]|^\\\\")
            return r
        SplitPath(scriptPath, , &dir)
        full := dir "\" r
        loop {                      ; fold away any ..\ so FileExist agrees
            was := full
            full := RegExReplace(full, "\\[^\\]+\\\.\.(\\|$)", "\")
        } until (full = was)
        return full
    }

    ; Does this file look like something the studio wrote?
    static IsOurs(text) => (AxMerge.Ref(text) != "") || InStr(text, ";#region axstudio ")

    ; --- taking a file apart ------------------------------------------
    ; A script is a list of segments: free text, and named regions. Order is
    ; preserved, because that order is the user's -- they may have moved a
    ; block, and a merge that reorders their file is a merge they stop using.
    static Split(text) {
        segs := [], free := "", cur := "", body := ""
        lines := StrSplit(StrReplace(String(text), "`r`n", "`n"), "`n")
        ; A text ending in a newline splits into a final empty piece. Treating
        ; it as a line would put a fresh blank one at the end of the file on
        ; every single export.
        if (lines.Length && lines[lines.Length] = "")
            lines.Pop()
        for line in lines {
            if (cur = "") {
                if RegExMatch(line, "i)^[ \t]*;[ \t]*#region[ \t]+axstudio[ \t]+(\S+)", &m) {
                    if (free != "")
                        segs.Push({Kind: "free", Text: free}), free := ""
                    cur := m[1], body := ""
                    continue
                }
                free .= line "`n"
            } else {
                if RegExMatch(line, "i)^[ \t]*;[ \t]*#endregion[ \t]+axstudio") {
                    segs.Push({Kind: "region", Name: cur, Body: Trim(body, "`n")})
                    cur := ""
                    continue
                }
                body .= line "`n"
            }
        }
        ; an unterminated region: everything after the marker belongs to it
        if (cur != "")
            segs.Push({Kind: "region", Name: cur, Body: Trim(body, "`n")})
        else if (free != "")
            segs.Push({Kind: "free", Text: free})
        return segs
    }

    static Names(text) {
        out := []
        for s in AxMerge.Split(text)
            if (s.Kind = "region")
                out.Push(s.Name)
        return out
    }

    ; --- putting one back together ------------------------------------
    ; The old file's shape wins. Its free text stays exactly where it is and
    ; each region it already has is refilled from the new export. A region the
    ; old file has not got is inserted straight after whichever one precedes
    ; it in the generated order, so a file that was rearranged by hand still
    ; gets new blocks somewhere sensible instead of all of them at the end.
    static Merge(oldText, newText) {
        fresh := Map(), order := []
        for s in AxMerge.Split(newText) {
            if (s.Kind != "region")
                continue
            k := StrLower(s.Name)
            fresh[k] := s.Body
            order.Push(k)
        }
        old := AxMerge.Split(oldText)
        have := Map()
        for s in old
            if (s.Kind = "region")
                have[StrLower(s.Name)] := true

        out := "", filled := false
        for s in old {
            if (s.Kind = "free") {
                out .= s.Text
                continue
            }
            k := StrLower(s.Name)
            if !fresh.Has(k)
                continue                      ; the design no longer emits one
            out .= AxMerge.Region(k, fresh[k]), filled := true
            i := AxMerge._At(order, k)
            while (i > 0 && i < order.Length && !have.Has(order[i + 1])) {
                i++
                out .= "`n" AxMerge.Region(order[i], fresh[order[i]])
                have[order[i]] := true
            }
        }
        if !filled                                ; nothing of ours in there
            return newText
        for k in order {
            if have.Has(k)
                continue
            out .= "`n" AxMerge.Region(k, fresh[k])
        }
        return out
    }
    static _At(arr, v) {
        for i, x in arr
            if (x = v)
                return i
        return 0
    }

    ; --- reading a script back ----------------------------------------
    ; Keyed the way the generator names things: "fn:Name" for one function
    ; body (handlers and the per-window startup functions alike), and
    ; "script:window" for a window's own block of functions.
    static Harvest(text) {
        out := Map()
        for s in AxMerge.Split(text) {
            if (s.Kind != "region")
                continue
            k := StrLower(s.Name)
            if (k = "handlers") {
                for name, body in AxMerge._Fns(s.Body)
                    out["fn:" name] := body
            } else if (SubStr(k, 1, 7) = "script.")
                out["script:" SubStr(k, 8)] := AxMerge.Dedent(s.Body)
        }
        return out
    }

    ; Function bodies out of the handlers block. A brace in the first column
    ; ends one -- which holds because every generated line inside is indented,
    ; and is why a hand edit should stay indented too.
    static _Fns(body) {
        out := Map(), name := "", buf := ""
        for line in StrSplit(StrReplace(String(body), "`r`n", "`n"), "`n") {
            if (name = "") {
                if RegExMatch(line, "^([A-Za-z_][A-Za-z0-9_]*)\((.*)\)[ \t]*\{[ \t]*$", &m)
                    name := m[1], buf := ""
                continue
            }
            if RegExMatch(line, "^\}[ \t]*$") {
                out[name] := AxMerge._Clean(buf)
                name := ""
                continue
            }
            buf .= line "`n"
        }
        if (name != "")
            out[name] := AxMerge._Clean(buf)
        return out
    }
    static _Clean(buf) {
        s := AxMerge.Dedent(buf)
        ; the generator opens every handler with the globals it needs; they
        ; are not the user's code and must not come back into the project
        while RegExMatch(s, "i)^[ \t]*global[ \t][^\n]*(\n|$)", &m)
            s := SubStr(s, StrLen(m[0]) + 1)
        ; the handler opens by running its rules (see AxStudio.Flow.ahk); that
        ; line is generated from the Flows field and must not come back as if
        ; someone had typed it
        ; -- all of them: a pack's event hands its parameters on
        ; (Flow_world_Hit_coin(eng, a, b, tag)), and a two-way binding's
        ; read-back comes first of all
        while RegExMatch(s, "^[ \t]*(?:Flow_[A-Za-z0-9_]+|AxBindPull)\([^\n]*\)[ \t]*(\n|$)", &f)
            s := SubStr(s, StrLen(f[0]) + 1)
        s := Trim(s, "`n")
        return (Trim(s) = "; nothing here yet") ? "" : s
    }

    ; Strip the shallowest indent shared by every non-blank line.
    static Dedent(s) {
        lines := StrSplit(Trim(StrReplace(String(s), "`r`n", "`n"), "`n"), "`n")
        least := -1
        for l in lines {
            if (Trim(l) = "")
                continue
            RegExMatch(l, "^[ \t]*", &m)
            n := StrLen(m[0])
            if (least < 0 || n < least)
                least := n
        }
        if (least <= 0)
            return Trim(StrReplace(String(s), "`r`n", "`n"), "`n")
        out := ""
        for l in lines
            out .= (Trim(l) = "" ? "" : SubStr(l, least + 1)) "`n"
        return Trim(out, "`n")
    }

    ; --- what the file has that the project has not --------------------
    ; Returns a list of {Kind, Label, New, Old} so the caller can name them
    ; before committing. Nothing is changed here.
    static Diff(project, text) {
        h := AxMerge.Harvest(text)
        out := []
        ev := AxMerge._EvFn(h, out)
        for w in project.Wins {
            k := "fn:" AxGen.InitFn(w)
            if h.Has(k) && AxMerge.Differs(h[k], w.Init)
                out.Push({Kind: "init", Win: w, Label: w.Name " startup code",
                          New: h[k], Old: w.Init})
            k := "script:" StrLower(AxProject.CleanName(w.Name))
            if h.Has(k) && AxMerge.Differs(h[k], w.Script)
                out.Push({Kind: "script", Win: w, Label: w.Name " own functions",
                          New: h[k], Old: w.Script})
            project.Walk(w.Root, ev)
        }
        return out
    }
    static _EvFn(h, out) => (n) => (AxMerge._Ev(n, h, out), false)
    static _Ev(n, h, out) {
        for e in n.Ev {
            k := "fn:" AxGen.HandlerName(n, e["name"])
            if h.Has(k) && AxMerge.Differs(h[k], e["code"])
                out.Push({Kind: "event", Label: n.Label " - " e["name"], Node: n, Ev: e,
                          New: h[k], Old: e["code"]})
        }
    }
    static Apply(project, changes) {
        for c in changes {
            if (c.Kind = "init")
                c.Win.Init := c.New
            else if (c.Kind = "script")
                c.Win.Script := c.New
            else
                c.Ev["code"] := c.New
        }
        return changes.Length
    }
    ; Trailing spaces and line endings are not a change anyone meant.
    static Differs(a, b) {
        return AxMerge._Norm(a) != AxMerge._Norm(b)
    }
    static _Norm(s) {
        t := RegExReplace(StrReplace(String(s), "`r`n", "`n"), "[ \t]+(?=\n|$)", "")
        return Trim(t, " `t`n")
    }
}
