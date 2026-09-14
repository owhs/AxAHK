#Requires AutoHotkey v2.0

; =============================================================================
;  AxGui.Compat.ahk -- the parts of AutoHotkey's own Gui a script reaches for,
;  on an AxGui window, so code written for Gui() keeps working on one.
;
;      g["name"]            the control with that id (Gui's __Item)
;      g.Submit(hide?)      {name: value, ...} for every control, and hides
;      g.Destroy()          closes the window
;      g.Opt("+AlwaysOnTop") the window's own options, applied to its window
;      g.Show("x10 y20 w300 NoActivate")   Gui's options, as well as Show(false)
;      g.Move / GetPos / GetClientPos      the window itself
;      g.OnEvent("Close"|"Size"|"Escape"|"DropFiles"|"ContextMenu", fn)
;      g.SetText(text, part)   a status bar's, for code that kept one
;      SB := g.AsStatusBar()   SB.SetText / SetParts / SetIcon, on the window's bar
;      g.Flash()            the taskbar button, as Gui's
;      ctl.Redraw()         nothing to do: the page draws itself
;      AxGuiCompat.Init(ctl, v)   what Gui's Add gave a control as its text,
;                           when that is only known as the script runs
;      ctl.Opt("+Disabled") Disabled / Hidden, on or off
;      ctl.SetFont("s10 Bold cRed", "Segoe UI")   as page styles
;      ctl.OnEvent with Gui's names (LoseFocus is Blur)
;      ctl.Name, ctl.Gui, ctl.Hwnd, ctl.UseTab()
;
;      ctl.Move(x, y, w, h)  its size, and a place makes it placed
;      ddl.Add(["a", "b"]) / ddl.Delete(2) / ddl.Delete() / ddl.Choose(2)
;                           a drop-down's and a list box's items, as Gui has
;                           them (anything else hands them to its component)
;      g.EventSink(obj)     Gui(opts, title, obj): a handler given by name is
;                           that object's method (without one, a function)
;
;  A handler is handed what Gui would hand it: one written (ctl, info) is not
;  given the (ctl, value, el) an AxGui handler takes, and a bound one that
;  says no to a third argument is asked again with two.
;
;  A font set on the window is left to the page's own styles.
; =============================================================================
class AxGuiCompat {
    ; Every word below is a closure that calls the static method: a static
    ; method taken as a value still wants its class as the hidden first
    ; argument, so handed to DefineProp as it is, it would take the window
    ; for the class and everything after it one place out.
    static _set := AxGuiCompat._Setup()
    static _Setup() {
        g := AxGui.Prototype, c := AxGui.Control.Prototype
        g.DefineProp("__Item", {Get: (self, id) => self.Ctl(id)})
        g.DefineProp("Submit", {Call: (self, a*) => AxGuiCompat.Submit(self, a*)})
        g.DefineProp("Destroy", {Call: (self) => self.Close()})
        g.DefineProp("Opt", {Call: (self, opts) => (self.Gui.Opt(opts), self)})
        g.DefineProp("Move", {Call: (self, x?, y?, w?, h?) => (self.Gui.Move(x?, y?, w?, h?), self)})
        g.DefineProp("GetPos", {Call: (self, &x?, &y?, &w?, &h?) => AxGuiCompat.GetPos(self, &x, &y, &w, &h)})
        g.DefineProp("GetClientPos", {Call: (self, &x?, &y?, &w?, &h?) => AxGuiCompat.GetClientPos(self, &x, &y, &w, &h)})
        g.DefineProp("SetFont", {Call: (self, *) => self})          ; the page's own styles do fonts
        g.DefineProp("OnEvent", {Call: (self, a*) => AxGuiCompat.WinEvent(self, a*)})
        g.DefineProp("SetText", {Call: (self, text, part := 1) => self.Status(part, text)})   ; a status bar's
        g.DefineProp("EventSink", {Call: (self, obj) => (self.DefineProp("_axSink", {Value: obj}), self)})
        g.DefineProp("AsStatusBar", {Call: (self) => AxGuiCompat.StatusBar(self)})
        g.DefineProp("Flash", {Call: (self, blink := true) => (DllCall("FlashWindow", "Ptr", self.Hwnd, "Int", !!blink), self)})
        c.DefineProp("Redraw", {Call: (self) => self})
        ; Show("x10 y20 w300 h200 NoActivate") as Gui has it; Show() / Show(false) as AxGui has it
        show := AxGui.Prototype.GetOwnPropDesc("Show").Call
        g.DefineProp("Show", {Call: (self, opts := true) => AxGuiCompat.Show(self, show, opts)})
        c.DefineProp("Opt", {Call: (self, a*) => AxGuiCompat.CtlOpt(self, a*)})
        c.DefineProp("Hwnd", {Get: (self) => AxGuiCompat.CtlHwnd(self)})
        c.DefineProp("UseTab", {Call: (self, *) => self})           ; the design put everything on its tab
        c.DefineProp("Move", {Call: (self, a*) => AxGuiCompat.CtlMove(self, a*)})
        ; Gui's event names too (LoseFocus is Blur), and one AxGui has no word for is ignored, not an error
        on := AxGui.Control.Prototype.GetOwnPropDesc("OnEvent").Call
        c.DefineProp("OnEvent", {Call: (self, name, fn, *) => AxGuiCompat.CtlEvent(self, on, name, fn)})
        c.DefineProp("SetFont", {Call: (self, a*) => AxGuiCompat.CtlFont(self, a*)})
        c.DefineProp("Name", {Get: (self) => self.Id})
        for w in ["Add", "Delete", "Choose"]
            c.DefineProp(w, {Call: AxGuiCompat.ListFn(w)})
        c.DefineProp("Gui", {Get: (self) => self.G})
        return true
    }

    static Submit(self, hide := true) {
        out := {}
        for id, ctl in self._controls {
            v := ""
            try v := ctl.Value
            catch
                continue
            out.%id% := v
        }
        if hide
            self.Hide()
        return out
    }

    static GetPos(self, &x?, &y?, &w?, &h?) {
        self.Gui.GetPos(&x, &y, &w, &h)
    }
    static GetClientPos(self, &x?, &y?, &w?, &h?) {
        self.Gui.GetClientPos(&x, &y, &w, &h)
    }
    ; Close runs as the window's own close; the rest are the window's own
    ; Windows events (Size, DropFiles, Escape, ContextMenu), with the AxGui
    ; window handed over where Gui would hand over itself
    static WinEvent(self, name, fn, add := 1) {
        if (fn is String)
            fn := AxGuiCompat.Named(self, fn)
        if (StrLower(name) = "close")
            return self.OnClose((w) => fn(w))
        self.Gui.OnEvent(name, (gg, args*) => fn(self, args*), add)
        return self
    }
    static Show(self, show, opts) {
        if !(opts is String) || IsNumber(opts)
            return show(self, opts)
        hide := RegExMatch(opts, "i)(^|\s)Hide(\s|$)")
        pos := ""
        for k, p in Map("x", "X", "y", "Y", "w", "Width", "h", "Height")
            if RegExMatch(opts, "i)(^|\s)" k "(-?\d+)", &m)
                self.%p% := m[2] + 0, pos .= " " k m[2]
        if RegExMatch(opts, "i)(^|\s)(NoActivate|NA)(\s|$)")
            self.NoActivate := true
        built := self._built
        r := show(self, !hide)
        ; up already: Gui moves it where it is asked to go
        if (built && pos != "")
            try self.Gui.Show(Trim(pos) (self.NoActivate ? " NoActivate" : "") (hide ? " Hide" : ""))
        return r
    }
    ; The page is one window; a control of it has none of its own, so the
    ; page's is the one it answers with (a click "on it" is a click there)
    static CtlHwnd(self) {
        try return ControlGetHwnd("Internet Explorer_Server1", "ahk_id " self.G.Hwnd)
        return self.G.Hwnd
    }
    static CtlEvent(self, on, name, fn) {
        static words := Map("losefocus", "Blur", "focus", "Focus", "click", "Click", "doubleclick", "DoubleClick",
            "change", "Change", "contextmenu", "ContextMenu")
        k := StrLower(name)
        fn := AxGuiCompat.Fit(fn, self.G)
        if words.Has(k)
            return on(self, words[k], fn)
        try return on(self, name, fn)
        return self
    }
    ; A handler by name: the event object's method, or a function of that name.
    ; Looked up when it runs, so the object can be given after the handler.
    static Named(g, name) => (args*) => AxGuiCompat._Named(g, name, args)
    static _Named(g, name, args) {
        sink := g.HasOwnProp("_axSink") ? g._axSink : ""
        if IsObject(sink)
            return AxGuiCompat.CallFit(ObjBindMethod(sink, name), args)
        f := %name%
        return AxGuiCompat.CallFit(f, args)
    }
    ; fn, made to take what it is given: as it is when it takes all of it
    static Fit(fn, g := "") {
        if (fn is String)
            return AxGuiCompat.Named(g, fn)
        try {
            if (fn is Func && !(fn is BoundFunc) && (fn.IsVariadic || fn.MaxParams >= 3))
                return fn
        }
        return (args*) => AxGuiCompat.CallFit(fn, args)
    }
    ; A function says how many it takes; a bound one does not, so it is asked
    ; with fewer when it refuses the lot.
    static CallFit(fn, args) {
        if (fn is Func && !(fn is BoundFunc)) {
            try {
                if (!fn.IsVariadic && args.Length > fn.MaxParams)
                    args.Length := fn.MaxParams
                while (args.Length < fn.MinParams)
                    args.Push("")
            }
            return fn(args*)
        }
        ; Only a refusal of THIS call is asked again: the same words from a
        ; call inside the handler come from somewhere else, and asking again
        ; would run what the handler had already done a second time.
        loop {
            try return (at := A_LineNumber, fn(args*))
            catch Error as e {
                if (args.Length <= 1 || !InStr(e.Message, "Too many parameters")
                    || e.File != A_LineFile || e.Line != at)
                    throw e
                args.Length := args.Length - 1
            }
        }
    }
    ; Move(x, y, w, h): a size is a size; a place makes it placed, as the
    ; design's fixed places are
    static CtlMove(self, x := "", y := "", w := "", h := "") {
        st := Map()
        if (w != "")
            st["width"] := Round(w) "px"
        if (h != "")
            st["height"] := Round(h) "px"
        if (x != "" || y != "") {
            st["position"] := "absolute"
            if (x != "")
                st["left"] := Round(x) "px"
            if (y != "")
                st["top"] := Round(y) "px"
        }
        apply := (*) => AxGuiCompat._Style(self, st)
        if self.G.Ready
            apply()
        else
            self.G.OnReady(apply)
        return self
    }
    static _Style(self, st) {
        el := self.El
        if !IsObject(el)
            return
        for k, v in st
            el.style.%k% := v
    }
    ; A status bar control's words, on the window's own status bar. Its parts
    ; and icons are the design's, so those two are taken and let be.
    class StatusBar {
        __New(g) => this.G := g
        SetText(text, part := 1, *) => (this.G.Status(part, text), 1)
        SetParts(*) => 1
        SetIcon(*) => 1
        Gui => this.G
        Visible {
            get => 1
            set => ""
        }
    }
    ; The text Gui's Add gave, set on the design's control: a label's or a
    ; button's words, a box's or a slider's value, a list's items -- once the
    ; page is there to take it
    static Init(ctl, v) {
        set := (*) => AxGuiCompat._Init(ctl, v)
        if (ctl.G.Ready || ctl.Type = "ListView")      ; its columns are wanted by the rows added next
            set()
        else
            ctl.G.OnReady(set)
        return ctl
    }
    static _Init(ctl, v) {
        switch ctl.Type {
        case "ListView":                                 ; its column titles
            if !ctl.GetCount("Col")
                for t in ((v is Array) ? v : StrSplit(String(v), "|"))
                    ctl.InsertCol(A_Index, , t)
        case "DDL", "ListBox":
            AxGuiCompat._List(ctl, "Delete", [])
            AxGuiCompat._List(ctl, "Add", [(v is Array) ? v : StrSplit(String(v), "|")], true)
        case "Text", "Button", "Link", "CheckBox", "GroupBox", "Radio", "Switch":
            try ctl.Text := v
        default:
            try ctl.Value := v
        }
    }
    ; ---------------------------------------------- a list's items, as Gui's
    static ListFn(name) => (self, args*) => AxGuiCompat.List(self, name, args)
    static List(self, name, args) {
        if !(self.Type = "DDL" || self.Type = "ListBox")
            return AxRich._Fwd(self, name, args)            ; the component's own Add, say
        do := (*) => AxGuiCompat._List(self, name, args)
        if self.G.Ready
            do()
        else
            self.G.OnReady(do)
        return (name = "Delete") ? 1 : self
    }
    static _List(self, name, args, numbered := "") {
        el := self.El
        if !IsObject(el)
            return
        box := el, cls := "list-item"
        try {
            m := el.querySelector(".dd-menu")
            if IsObject(m)
                box := m, cls := "dd-item"
        }
        items := box.querySelectorAll("." cls)
        switch name {
        case "Add":
            list := (args.Length = 1 && args[1] is Array) ? args[1] : args
            ; a list whose values are its items' numbers (one brought over from
            ; a Gui() script) goes on numbering them
            num := (numbered != "") ? numbered : items.length > 0
            look := (numbered != "") ? 0 : items.length
            loop look
                if (AxWindow._Attr(items.item(A_Index - 1), "data-value") != String(A_Index)) {
                    num := false
                    break
                }
            h := ""
            for v in list
                h .= '<div class="' cls '" data-value="' AxTags.E(num ? String(items.length + A_Index) : String(v)) '">'
                  .  AxTags.E(String(v)) '</div>'
            box.insertAdjacentHTML("beforeend", h)
        case "Delete":
            if (args.Length && IsInteger(args[1])) {
                if (args[1] >= 1 && args[1] <= items.length) {
                    it := items.item(args[1] - 1)
                    was := AxWindow._HasClass(it, "selected")
                    it.parentNode.removeChild(it)
                    if was
                        self.Value := ""
                }
            } else {
                loop items.length
                    items.item(items.length - A_Index).parentNode.removeChild(items.item(items.length - A_Index))
                self.Value := ""
                try el.querySelector(".dd-value").innerText := ""
            }
        case "Choose":
            v := args.Length ? args[1] : 0
            if IsInteger(v) {
                self.Value := (v >= 1 && v <= items.length) ? AxWindow._Attr(items.item(v - 1), "data-value") : ""
                return
            }
            loop items.length                              ; Gui's is the first item that starts so
                if (InStr(items.item(A_Index - 1).innerText, v) = 1) {
                    self.Value := AxWindow._Attr(items.item(A_Index - 1), "data-value")
                    return
                }
        }
    }
    static CtlOpt(self, opts) {
        for word in StrSplit(Trim(opts), " ") {
            on := SubStr(word, 1, 1) != "-"
            switch LTrim(word, "+-"), false {
            case "Disabled": self.Enabled := !on
            case "Hidden":   self.Visible := !on
            }
        }
        return self
    }

    ; s12 Bold Italic Underline Strike Norm cRed / c00FF00, and a face name
    static CtlFont(self, opts := "", name := "") {
        apply := (*) => AxGuiCompat._Font(self, opts, name)
        if self.G.Ready
            apply()
        else
            self.G.OnReady(apply)
        return self
    }
    static _Font(self, opts, name) {
        el := self.El
        if !IsObject(el)
            return
        st := el.style
        for word in StrSplit(Trim(opts), " ") {
            if RegExMatch(word, "i)^s(\d+(?:\.\d+)?)$", &m)
                st.fontSize := m[1] "pt"
            else if RegExMatch(word, "i)^c(.+)$", &m)
                st.color := AxGuiCompat.Color(m[1])
            else if (word = "Bold")
                st.fontWeight := "bold"
            else if (word = "Italic")
                st.fontStyle := "italic"
            else if (word = "Underline")
                st.textDecoration := "underline"
            else if (word = "Strike")
                st.textDecoration := "line-through"
            else if (word = "Norm")
                st.fontWeight := "normal", st.fontStyle := "normal", st.textDecoration := "none"
        }
        if (name != "")
            st.fontFamily := "'" name "'"
    }
    ; Gui's colour words and hex, as CSS
    static Color(c) {
        static named := Map("black", "#000000", "silver", "#C0C0C0", "gray", "#808080", "white", "#FFFFFF",
            "maroon", "#800000", "red", "#FF0000", "purple", "#800080", "fuchsia", "#FF00FF", "green", "#008000",
            "lime", "#00FF00", "olive", "#808000", "yellow", "#FFFF00", "navy", "#000080", "blue", "#0000FF",
            "teal", "#008080", "aqua", "#00FFFF")
        k := StrLower(c)
        if named.Has(k)
            return named[k]
        if (k = "default")
            return ""
        return RegExMatch(c, "^(0x)?[0-9A-Fa-f]{6}$") ? "#" RegExReplace(c, "^0x") : c
    }
}
