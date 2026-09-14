#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; ============================================================================
;  AxActiveX.ahk -- ActiveX host.
;
;  Everything about this control is in this folder, and nowhere else:
;
;      AxActiveX.ahk     what g.AddActiveX() writes
;      ActiveX.axc.json  what the studio puts in the toolbox
; ============================================================================

class AxActiveX {
    static _reg := AxRich.Register("ActiveX", "",
                                   (*) => AxActiveX._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddActiveX", (c, a*) => AxActiveX._ActiveX(c, a*))
        return true
    }

    static _ActiveX(c, opts := "", progId := "Shell.Explorer.2") {
        o := c._Opt(opts, "ax")
        if (o.H = "" && !o.Flags.Has("stretch"))
            o.H := 240
        c := c._Reg(o, "ActiveX", '<div' c._Common(o, "ax-dock" (o.W = "" ? " fill" : "") (o.Flags.Has("stretch") ? " stretch" : "")) '></div>')
        if c.G.Ready
            c.G.Embed(o.Id, progId)
        else
            c.G._embedPending.Push([o.Id, progId])
        return c
        }
}
