#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: this control's own stylesheet
;@Ahk2Exe-AddResource %U_AxLib%\components\Stepper\AxStepper.css, AX_COMPONENTS_STEPPER_AXSTEPPER_CSS

; =============================================================================
;  AxStepper -- the steps of a wizard: which are done, which is now, which
;  are still to come.
;
;    st := g.AddStepper("vSteps", "Account`nProfile:Your name and picture`nConfirm")
;    st.Next()   st.Back()   st.Value := 2   st.Finish()
;    st.OnChange((ctl, n, *) => ShowPage("step" n))
;
;  One step per line (or | between them): Label, or Label:a line under it.
;  ctl.Value is the step you are on, counting from 1; Finish() ticks the last
;  one too. A step already done can be clicked to go back to it -- Free lets
;  any step be clicked. Vertical stacks them.
; =============================================================================
class AxStepper {
    static _reg := AxRich.Register("Stepper", "components\Stepper\AxStepper.css",
                                   (*) => AxStepper._Install(), true)
    static _Install() {
        AxRich.AddMethod("AddStepper", (c, o := "", items := "") => AxStepper._Add(c, o, items))
        AxWindow.RegisterValue("stepper",
            (w, el) => AxWindow._Attr(el, "data-value"),
            (w, el, v) => AxStepper._SetVia(w, el, v))
        return true
    }
    static _SetVia(win, el, v) {
        c := AxRich.At(win, el.id)
        if IsObject(c)
            c.Value := v
    }
    static _Add(c, opts, items) {
        o := c._Opt(opts, "stp")
        F := (k) => (o.Flags.Has(k) && o.Flags[k])
        cfg := {Vertical: F("vertical"), Free: F("free"), Cur: Max(1, Integer(c._Kv(o, "value", 1)))}
        list := AxStepper.Parse(items)
        ctl := c._Reg(o, "Stepper", AxStepper.Html(o.Id, list, cfg, c._Common(o, "")))
        c.G.OnReady((w) => AxStepper(w, o.Id, list, cfg))
        return ctl
    }
    static Parse(items) {
        out := []
        t := IsObject(items) ? "" : StrReplace(String(items), "`r", "")
        src := IsObject(items) ? items : StrSplit(t, InStr(t, "`n") ? "`n" : "|")
        for line in src {
            line := Trim(line)
            if (line = "")
                continue
            p := InStr(line, ":")
            out.Push(p ? {L: Trim(SubStr(line, 1, p - 1)), D: Trim(SubStr(line, p + 1))} : {L: line, D: ""})
        }
        return out
    }
    static Html(id, list, cfg, attrs := "") {
        cls := "axstep" (cfg.Vertical ? " vertical" : "")
        if (attrs != "") {
            n := 0
            a := RegExReplace(attrs, 'S)class="([^"]*)"', 'class="' cls ' $1"', &n)
            if !n
                a .= ' class="' cls '"'
        } else
            a := ' id="' AxWindow._Esc(id) '" class="' cls '"'
        return '<div' a ' data-role="stepper" data-value="' cfg.Cur '">'
             . '<div class="axstep-r" id="' AxWindow._Esc(id) '_r">' AxStepper.Inner(list, cfg) '</div></div>'
    }
    static Inner(list, cfg) {
        E := (x) => AxWindow._Esc(x)
        h := "", n := list.Length, cur := cfg.Cur
        for i, it in list {
            state := (i < cur) ? "done" : (i = cur) ? "cur" : "todo"
            can := (cfg.Free && i != cur) || (i < cur)
            h .= '<div class="axstep-s ' state (can ? " can" : "") '"' (can ? ' data-i="' i '"' : "") '>'
              .  '<span class="axstep-dot">' (state = "done" ? '<span class="ico">&#xE73E;</span>' : i) '</span>'
              .  '<span class="axstep-t"><b>' E(it.L) '</b>' (it.D != "" ? '<small>' E(it.D) '</small>' : "") '</span></div>'
            if (i < n)
                h .= '<div class="axstep-line' (i < cur ? " done" : "") '"></div>'
        }
        return h
    }

    __New(win, id, list, cfg) {
        this.W := win, this.Id := id, this.List := list, this.Cfg := cfg
        this._cbs := []
        AxRich.Bind(win, id, this)
        win.On("click", id "_r", (el, ev) => this._Click(ev))
    }
    Count => this.List.Length
    Value {
        get => this.Cfg.Cur
        set => this.Go(Integer(value), false)
    }
    Next() => this.Go(this.Cfg.Cur + 1)
    Back() => this.Go(this.Cfg.Cur - 1)
    Finish() => this.Go(this.List.Length + 1)
    IsDone => this.Cfg.Cur > this.List.Length
    OnChange(fn) {
        this._cbs.Push(fn)
        return this
    }
    ; go to step n (n past the last means every step is done)
    Go(n, fire := true) {
        n := Max(1, Min(this.List.Length + 1, n))
        if (n = this.Cfg.Cur)
            return this
        this.Cfg.Cur := n
        try {
            this.W.El(this.Id "_r").innerHTML := AxStepper.Inner(this.List, this.Cfg)
            this.W.El(this.Id).setAttribute("data-value", n)
        }
        if fire {
            for fn in this._cbs.Clone()
                try fn(n, this)
            try this.W._FireValue(this.W.El(this.Id), n)
        }
        return this
    }
    _Click(ev) {
        try el := ev.srcElement
        catch
            return
        loop 5 {
            if !IsObject(el)
                return
            i := AxWindow._Attr(el, "data-i")
            if (i != "")
                return this.Go(Integer(i))
            el := AxWindow._ParentEl(el)
        }
    }
}
