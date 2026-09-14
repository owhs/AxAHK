#Requires AutoHotkey v2.0

; Part of AxStudio, not a program on its own. Running this file directly would
; only load a class and stop, so it hands over to the entry point instead.
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
;  AxStudio.Catalog.ahk -- what the studio knows about a control.
;
;  This is the SHAPE of that knowledge and the registry that holds it. The
;  entries themselves are not here any more: every control ships as a pack --
;  a folder with its code, a manifest, and any CSS of its own -- and
;  AxStudio.Comp.ahk reads those into this table at start-up.
;
;  One entry drives four things, so they cannot drift apart: the toolbox on the
;  left, the property sheet on the right, the markup the canvas draws, and the
;  AutoHotkey the exporter writes. Adding a control is adding a folder; see
;  components/README.md.
;
;  Entry fields
;      T        AxGui type: the method called is "Add" T
;      Label    toolbox caption          Icon   Segoe Fluent glyph
;      Cat      toolbox group            Prefix default name stem ("btn" -> btn1)
;      Box      true for a container (children are allowed)
;      Arg      the second argument to Add*: {K, L, Kind, Def, Raw}
;               Raw = it is an AHK expression, not a quoted string (ActiveX, DataView)
;      Props    [{K, L, Kind, Emit, W, Opts, Def}]
;               Emit "flag"    -> the bare word W when truthy
;                    "flagset" -> the chosen value as a bare word
;                    "kv"      -> W=Value
;      Events   names from AxCat.Events
;      Needs    an extra #Include the generated script requires
;
;  Property kinds (the property sheet renders one editor per kind)
;      text multiline num flag choice options icon color
; =============================================================================
class AxCat {
    static Items := Map()          ; type -> entry
    static Order := []             ; types in toolbox order
    static Cats  := []             ; category names in toolbox order

    static Add(e) {
        if !e.HasOwnProp("Box")
            e.Box := false
        if !e.HasOwnProp("Props")
            e.Props := []
        if !e.HasOwnProp("Events")
            e.Events := ["Click", "DoubleClick", "ContextMenu"]
        if !e.HasOwnProp("Arg")
            e.Arg := ""
        if !e.HasOwnProp("Needs")
            e.Needs := ""
        if !e.HasOwnProp("Pack")
            e.Pack := ""                 ; which component folder it came from
        AxCat.Items[e.T] := e
        AxCat.Order.Push(e.T)
        found := false
        for c in AxCat.Cats
            if (c = e.Cat)
                found := true
        if !found
            AxCat.Cats.Push(e.Cat)
        return e
    }
    static Has(type) => AxCat.Items.Has(type)
    static Get(type) {
        if AxCat.Items.Has(type)
            return AxCat.Items[type]
        throw ValueError("Unknown control type: " type, -1)
    }
    static InCat(cat) {
        out := []
        for t in AxCat.Order
            if (AxCat.Items[t].Cat = cat)
                out.Push(AxCat.Items[t])
        return out
    }

    ; ------------------------------------------------------------- events
    ; Sig is the generated handler's parameter list; Wire is the method that
    ; attaches it. Anything with an empty Wire goes through OnEvent(name, fn).
    static Events := Map(
        "Click",        {Sig: "ctl, ev, el",      Wire: ""},
        "DoubleClick",  {Sig: "ctl, ev, el",      Wire: ""},
        "Change",       {Sig: "ctl, value, el",   Wire: ""},
        "ContextMenu",  {Sig: "ctl, ev, el",      Wire: ""},
        "Focus",        {Sig: "ctl, ev, el",      Wire: ""},
        "Blur",         {Sig: "ctl, ev, el",      Wire: ""},
        "KeyDown",      {Sig: "ctl, ev, el",      Wire: ""},
        "KeyUp",        {Sig: "ctl, ev, el",      Wire: ""},
        "MouseDown",    {Sig: "ctl, ev, el",      Wire: ""},
        "MouseUp",      {Sig: "ctl, ev, el",      Wire: ""},
        "MouseOver",    {Sig: "ctl, ev, el",      Wire: ""},
        "MouseOut",     {Sig: "ctl, ev, el",      Wire: ""},
        "Hotkey",       {Sig: "ctl",              Wire: ""},
        "Drop",         {Sig: "files, id, info",  Wire: "OnDrop"},
        "Preview",      {Sig: "hex, ctl",         Wire: "OnPreview"},
        "Select",       {Sig: "rows, dv",         Wire: "OnSelect"},
        "Check",        {Sig: "rows, dv",         Wire: "OnCheck"},
        "Activate",     {Sig: "row, dv",          Wire: "OnActivate"},
        ; a list view's and a tree view's, as Gui has them
        "ItemSelect",   {Sig: "ctl, item, selected", Wire: ""},
        "ItemCheck",    {Sig: "ctl, item, checked",  Wire: ""},
        "ItemExpand",   {Sig: "ctl, item, expanded", Wire: ""},
        "ItemFocus",    {Sig: "ctl, item",           Wire: ""},
        "ColClick",     {Sig: "ctl, column",         Wire: ""})

    ; Code that runs where it sits while the window is being built. Not a
    ; control: the export writes it out as it stands, and the canvas shows it
    ; as a chip. Importing a script puts its loops and set-up code in these.
    static CodeEntry() => {T: "Code", Label: "Code", Icon: "E943", Cat: "Advanced", Prefix: "code",
        Box: false, Pack: "", Needs: "", Props: [], Events: [],
        Arg: {K: "code", L: "Code", Kind: "multiline", Def: ""}}

    static Sig(name) => AxCat.IsPart(name) ? "el, ev" : AxCat.Events.Has(name) ? AxCat.Events[name].Sig : "ctl, ev, el"
    static Wire(name) => AxCat.Events.Has(name) ? AxCat.Events[name].Wire : ""
    ; A pack's own event can name the parameter a rule picks on: a rule for
    ; "Hit:coin" runs only when the handler's `tag` is "coin".
    static Filter(name) => (AxCat.Events.Has(name) && AxCat.Events[name].HasOwnProp("Filter")) ? AxCat.Events[name].Filter : ""
    static Help(name) => (AxCat.Events.Has(name) && AxCat.Events[name].HasOwnProp("Help")) ? AxCat.Events[name].Help : ""
    ; whether the rules of this event take the handler's own parameters --
    ; true for a pack's events, which is where a rule needs the thing it hit
    static FlowArgs(name) => (AxCat.Events.Has(name) && AxCat.Events[name].HasOwnProp("Filter")) ? AxCat.Events[name].Sig : ""
    ; A click on something inside a control's popover, by the id it has there:
    ; "Pop_popSignOut". Written as g.On("click", "popSignOut", handler).
    static IsPart(name) => SubStr(name, 1, 4) = "Pop_"
    static PartId(name) => SubStr(name, 5)
    ; the ids in a popover's markup, in order, each once
    static PopParts(markup) {
        out := [], seen := Map(), pos := 1
        while (pos := RegExMatch(markup, "i)\bid\s*=\s*[`"']([^`"']+)[`"']", &m, pos)) {
            pos += m.Len
            if !seen.Has(m[1])
                seen[m[1]] := true, out.Push(m[1])
        }
        return out
    }

    ; --------------------------------------------------- property helpers
    static P(k, l, kind, emit := "kv", w := "", opts := "", def := "") {
        return {K: k, L: l, Kind: kind, Emit: emit, W: (w != "" ? w : AxCat._Word(k)), Opts: opts, Def: def}
    }
    static _Word(k) => StrUpper(SubStr(k, 1, 1)) SubStr(k, 2)
    static Flag(k, l, w := "") => AxCat.P(k, l, "flag", "flag", w)
    ; A flag the canvas must not apply. <ax-row nocard> expands to markup that
    ; drops the id and the class, so a row wearing it could not be picked up
    ; again; the design surface shows it carded and the export does not.
    static FlagNoCanvas(k, l, w := "") {
        p := AxCat.P(k, l, "flag", "flag", w)
        p.NoCanvas := true
        return p
    }
    static Kv(k, l, kind := "text", def := "") => AxCat.P(k, l, kind, "kv", , , def)

    ; ---------------------------------------------------------- the table
    static __New() {
        P := (a*) => AxCat.P(a*)
        F := (a*) => AxCat.Flag(a*)
        K := (a*) => AxCat.Kv(a*)
        common := ["Click", "DoubleClick", "ContextMenu", "MouseDown", "MouseUp", "Focus", "Blur"]
        value  := ["Change", "Click", "DoubleClick", "ContextMenu", "Focus", "Blur"]
        nl := "`n"

        ; Nothing is registered here. Every control -- the forty-three that
        ; ship and any you add -- comes from a *.axc.json manifest beside its
        ; code, read by AxComp.Scan before the toolbox is first drawn.
        ;
        ; The helpers above are still used: a manifest is turned into exactly
        ; the same entry these would have built.
    }
}
