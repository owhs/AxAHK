#Requires AutoHotkey v2.0

; What this file needs. #Include loads a file once, so naming them here
; costs nothing when the whole studio is loaded, and makes each part stand
; on its own -- which is what stops a stray run of one of them reporting
; half the library as undefined.
#Include %A_LineFile%\..\AxStudio.Lit.ahk
#Include %A_LineFile%\..\AxStudio.Model.ahk
#Include %A_LineFile%\..\AxStudio.Gen.ahk

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
;  AxStudio.RibbonUi.ahk -- building a ribbon by pointing at it.
;
;  A ribbon is three levels deep -- tabs hold groups hold items -- and it was
;  configured by typing that whole tree into one box as an AutoHotkey
;  expression. That is fine as a FORMAT and hopeless as an INTERFACE: you had
;  to know the shape before you could make one, there was no list of what a
;  kind could be, and one missing brace took the whole thing out.
;
;  So the tree is shown as a tree. Every tab, group and item is a row you can
;  select, rename, move, copy or delete, and the one that is selected puts its
;  own properties in the pane underneath -- the same field editors as the rest
;  of the studio, so a glyph is chosen from the glyph picker and a colour from
;  the colour picker.
;
;  Three things are worth knowing about how it works:
;
;  1. The expression stays the truth. It is read with AxLit (which parses a
;     literal without evaluating it), changed as a Map, and written straight
;     back out. Nothing is stored twice, so "Edit as text" is never out of step
;     with the tree, and a ribbon built here is the same ribbon someone else
;     typed by hand.
;
;  2. Anything that is not a literal survives. A Click written as a fat arrow
;     comes back as {Raw: "..."} and goes out again exactly as it was. When the
;     whole expression is code -- MakeTabs() -- the tree says so and offers the
;     text box instead of quietly throwing the code away.
;
;  3. What an item does is an event, not a field. "When it is clicked" adds a
;     Command:<id> handler to the control, which the generator turns into one
;     OnCommand that dispatches by id. So a ribbon button gets the same code
;     editor, the same Steps view and the same rules as a plain button does.
; =============================================================================
class AxRibUi {
    ; The order the fields are written in. A Map has none of its own, and
    ; {Label: "Paste", Id: "paste"} reads like a shuffle.
    static ORDER := "Mode|Style|Density|Color|Collapsed|Flush|File|QuickAccess|QuickAccessIn"
                  . "|FollowContext|Tabs|Id|Title|Label|Icon|Kind|Size|Key|Tip|Value|Width"
                  . "|Contextual|Set|Launcher|Checked|Disabled|Hidden|Menu|Items|Groups"

    static KINDS := "button:Button|toggle:Toggle (stays pressed)|check:Tick box|split:Button with a menu"
                  . "|menu:Menu|color:Colour|gallery:Gallery|input:Text box|label:Label"
                  . "|sep:Separator|spacer:Space"

    ; ------------------------------------------------------------- the data
    ; The expression as a Map, or "" when it is code rather than a literal.
    static Cfg(n) {
        v := AxLit.Read(n.Arg)
        return (v is Map) ? v : ""
    }
    static Put(s, n, cfg) {
        n.Arg := AxLit.Write(cfg, 0, AxRibUi.ORDER)
        s.P.Dirty := true
    }
    ; A list that is there whether or not it was written.
    static List(holder, key) {
        if !(holder.Has(key) && holder[key] is Array)
            holder[key] := []
        return holder[key]
    }
    static Obj(pairs*) {
        m := Map()
        m.CaseSense := false
        i := 1
        while (i < pairs.Length) {
            m[pairs[i]] := pairs[i + 1]
            i += 2
        }
        return m
    }
    static Get(m, key, def := "") => (IsObject(m) && m is Map && m.Has(key)) ? m[key] : def

    ; A path is the 1-based indices of tab, group and item, joined: "2-1-3".
    ; Walk returns the Map at the end of it, and "" when it is not there any
    ; more -- which happens the moment something before it is deleted.
    static Walk(cfg, path) {
        parts := StrSplit(String(path), "-")
        list := AxRibUi.List(cfg, "Tabs")
        node := ""
        for i, one in parts {
            if (!IsInteger(one) || !list.Length)
                return ""
            k := Integer(one)
            if (k < 1 || k > list.Length)
                return ""
            node := list[k]
            if !(node is Map)
                return ""
            if (i < parts.Length)
                list := AxRibUi.List(node, (i = 1) ? "Groups" : "Items")
        }
        return node
    }
    ; The list the thing at `path` lives in, and its index in it.
    static Slot(cfg, path, &list, &idx) {
        parts := StrSplit(String(path), "-")
        list := AxRibUi.List(cfg, "Tabs")
        loop parts.Length - 1 {
            k := Integer(parts[A_Index])
            if (k < 1 || k > list.Length)
                return false
            list := AxRibUi.List(list[k], (A_Index = 1) ? "Groups" : "Items")
        }
        idx := Integer(parts[parts.Length])
        return (idx >= 1 && idx <= list.Length)
    }
    static Depth(path) => StrSplit(String(path), "-").Length

    ; What to call a row. A separator has no name and should not be given one.
    static Name(node, depth) {
        if !(node is Map)
            return "?"
        kind := StrLower(String(AxRibUi.Get(node, "Kind")))
        if (kind = "sep")
            return Chr(0x2502) " separator"
        if (kind = "spacer")
            return Chr(0x00B7) " space"
        for k in ["Title", "Label", "Id"]
            if (AxRibUi.Get(node, k) != "")
                return AxRibUi.Get(node, k)
        return (depth = 1) ? "Tab" : (depth = 2) ? "Group" : "Item"
    }
    static Counts(cfg) {
        t := 0, g := 0, i := 0
        for tab in AxRibUi.List(cfg, "Tabs") {
            if !(tab is Map)
                continue
            t++
            for grp in AxRibUi.List(tab, "Groups") {
                if !(grp is Map)
                    continue
                g++
                for it in AxRibUi.List(grp, "Items")
                    i++
            }
        }
        return {Tabs: t, Groups: g, Items: i}
    }
    static Says(c) => c.Tabs " tab" (c.Tabs = 1 ? "" : "s") ", " c.Groups " group"
                    . (c.Groups = 1 ? "" : "s") ", " c.Items " item" (c.Items = 1 ? "" : "s")

    ; An id nothing else in the ribbon has. Ids are what the item's handler is
    ; named after and what OnCommand dispatches on, so a duplicate is not a
    ; cosmetic problem -- two buttons would run the same code.
    static NewId(cfg, stem) {
        taken := Map()
        taken.CaseSense := false
        for tab in AxRibUi.List(cfg, "Tabs") {
            if !(tab is Map)
                continue
            taken[AxRibUi.Get(tab, "Id")] := true
            for grp in AxRibUi.List(tab, "Groups") {
                if !(grp is Map)
                    continue
                taken[AxRibUi.Get(grp, "Id")] := true
                for it in AxRibUi.List(grp, "Items")
                    if (it is Map)
                        taken[AxRibUi.Get(it, "Id")] := true
            }
        }
        if !taken.Has(stem)
            return stem
        i := 2
        while taken.Has(stem i)
            i++
        return stem i
    }

    ; What the Content row says instead of showing the expression.
    static Said(n) {
        cfg := AxRibUi.Cfg(n)
        if !IsObject(cfg)
            return "An expression, built when the program runs"
        return AxRibUi.Says(AxRibUi.Counts(cfg))
    }
    ; The heading over the selected row's properties, so it is never a mystery
    ; which of the three levels is being edited.
    static SelTitle(s, n) {
        cfg := AxRibUi.Cfg(n)
        if !IsObject(cfg)
            return "Selected"
        path := AxRibUi.Sel(s, cfg)
        if (path = "")
            return "Selected"
        depth := AxRibUi.Depth(path)
        what := (depth = 1) ? "tab" : (depth = 2) ? "group" : "item"
        return "The " what ": " AxRibUi.Name(AxRibUi.Walk(cfg, path), depth)
    }

    ; ------------------------------------------------------------- the pane
    ; The whole thing: a summary, the tree, and the selected row's properties.
    static Pane(s, n, add) {
        cfg := AxRibUi.Cfg(n)
        if !IsObject(cfg)
            return '<div class="axd-note">The tabs come from an expression the studio cannot read as a '
                 . 'literal -- most likely a function of your own that builds them when the program runs. '
                 . 'That works, and it is why the box below is still here; it just cannot be drawn as a tree. '
                 . '<span class="axd-hbtn" data-do="rib.literal">Start from an example instead</span> '
                 . '(your expression is put in a comment first).</div>'
        sel := AxRibUi.Sel(s, cfg)
        h := '<div class="axd-ribsum"><span class="ico">&#xE7C4;</span>'
           . '<span class="axd-ribsay">' AxTags.E(AxRibUi.Says(AxRibUi.Counts(cfg))) '</span>'
           . '<span class="axd-hbtn axd-go" data-do="rib.addtab">+ Tab</span></div>'
        h .= AxRibUi.Tree(cfg, sel)
        return h
    }
    ; The row the pane is showing the properties of, as a path. It is kept on
    ; the studio rather than in the project: which row you had open is not part
    ; of the design, and saving it would make the file change when nothing did.
    static Sel(s, cfg) {
        cur := s.HasOwnProp("RibSel") ? s.RibSel : ""
        if (cur != "" && IsObject(AxRibUi.Walk(cfg, cur))) {
            AxRibUi.Draw(s, cur)
            return cur
        }
        ; whatever is first, so the properties half is never empty
        if AxRibUi.List(cfg, "Tabs").Length {
            AxRibUi.Draw(s, "1")
            return s.RibSel := "1"
        }
        return s.RibSel := ""
    }
    ; Tell the canvas which tab to draw: whichever one the selected row is
    ; in, at any of the three levels.
    static Draw(s, path) {
        n := s.Primary()
        if (IsObject(n) && n.Type = "Ribbon")
            AxGen.RibTab[n.Id] := Integer(StrSplit(String(path), "-")[1])
    }
    static Tree(cfg, sel) {
        tabs := AxRibUi.List(cfg, "Tabs")
        if !tabs.Length
            return '<div class="axd-note">No tabs yet. <span class="axd-hbtn" data-do="rib.addtab">Add one</span></div>'
        h := '<div class="axd-ribtree">'
        for ti, tab in tabs {
            h .= AxRibUi.Row(tab, ti, 1, sel, "rib.addgroup." ti, "+ Group")
            if !(tab is Map)
                continue
            for gi, grp in AxRibUi.List(tab, "Groups") {
                h .= AxRibUi.Row(grp, ti "-" gi, 2, sel, "rib.additem." ti "-" gi, "+ Item")
                if !(grp is Map)
                    continue
                for ii, it in AxRibUi.List(grp, "Items")
                    h .= AxRibUi.Row(it, ti "-" gi "-" ii, 3, sel, "", "")
            }
        }
        return h "</div>"
    }
    static Row(node, path, depth, sel, addDo, addLabel) {
        E := (x) => AxTags.E(x)
        icon := (node is Map) ? AxRibUi.Get(node, "Icon") : ""
        b := (act, glyph, tip) => '<span class="axd-ribb" data-do="rib.' act "." path '" data-tip="' tip '">'
                                . '<span class="ico">&#x' glyph ';</span></span>'
        h := '<div class="axd-ribrow d' depth (path = sel ? " on" : "") '" data-do="rib.sel.' path '">'
           . '<span class="ico axd-ribico">&#x' (icon != "" ? E(icon) : (depth = 3 ? "E8B9" : "E8FD")) ';</span>'
           . '<span class="axd-ribname">' E(AxRibUi.Name(node, depth)) '</span>'
        if (addDo != "")
            h .= '<span class="axd-ribb wide" data-do="' addDo '" data-tip="Add one to this">' E(addLabel) '</span>'
        h .= b("up", "E74A", "Move it up") b("dn", "E74B", "Move it down")
           . b("dup", "E8C8", "Make a copy of it") b("del", "E74D", "Delete it")
           . '</div>'
        return h
    }

    ; The selected row's own properties, as the studio's ordinary fields, so
    ; the glyph picker and the colour picker are the ones used everywhere else.
    static Props(s, n, add) {
        cfg := AxRibUi.Cfg(n)
        if !IsObject(cfg)
            return ""
        path := AxRibUi.Sel(s, cfg)
        if (path = "")
            return ""
        node := AxRibUi.Walk(cfg, path)
        if !(node is Map)
            return ""
        depth := AxRibUi.Depth(path)
        F(key, label, fkind, opts := "", hint := "") {
            d := {Id: "rib_" key, L: label, Kind: fkind,
                  Get: (*) => AxRibUi.Get(node, key),
                  Set: (v) => (AxRibUi.Set(node, key, v, fkind), AxRibUi.Put(s, n, cfg))}
            if (opts != "")
                d.Opts := opts
            if (hint != "")
                d.Hint := hint
            return add(d)
        }
        h := ""
        if (depth = 1) {
            h := F("Title", "Title", "text")
               . F("Icon", "Icon", "icon")
               . F("Key", "Key tip", "text", , "One letter, shown when Alt is held")
               . F("Id", "Id", "text", , "what the code calls it")
               . F("Contextual", "Only when it applies", "flag")
               . F("Color", "Band colour", "color")
               . F("Set", "Band it shares", "text", , "Contextual tabs with the same band get one heading")
               . F("Hidden", "Hidden", "flag")
        } else if (depth = 2) {
            h := F("Title", "Title", "text")
               . F("Icon", "Icon", "icon", , "Shown when the group is folded to fit")
               . F("Id", "Id", "text")
               . F("Launcher", "Corner arrow", "flag")
               . F("Hidden", "Hidden", "flag")
        } else {
            kind := StrLower(String(AxRibUi.Get(node, "Kind", "button")))
            h := F("Kind", "It is a", "choice", AxRibUi.KINDS)
            if (kind = "sep" || kind = "spacer")
                return h '<div class="axd-note">A separator has nothing to set: it is the gap itself.</div>'
            h .= F("Label", "Label", "text")
               . F("Icon", "Icon", "icon")
               . F("Size", "Size", "choice", "small:Small, three to a column|large:Large, one on its own")
               . F("Id", "Id", "text", , "what its handler is named after")
               . F("Key", "Key tip", "text")
               . F("Tip", "Tooltip", "text")
            if (kind = "input" || kind = "color" || kind = "toggle" || kind = "check")
                h .= F("Value", "Starts at", "text")
            if (kind = "input")
                h .= F("Width", "Width (px)", "num")
            if (kind = "menu" || kind = "split")
                h .= F("Menu", "Menu", "multiline", ,
                       "One entry a line. A line on its own is a label; nothing else is needed here.")
            if (kind = "gallery" || kind = "color")
                h .= F("Items", "Choices", "multiline", , "One a line")
            if (kind = "toggle" || kind = "check")
                h .= F("Checked", "Starts on", "flag")
            h .= F("Disabled", "Greyed out", "flag")
               . F("Hidden", "Hidden", "flag")
            h .= AxRibUi.Hook(s, n, node)
        }
        return h
    }
    ; What the item does. An event on the control, narrowed to this item, so it
    ; gets the code editor, the Steps view and the rules every other handler
    ; gets -- rather than a second, smaller idea of "an action" that only a
    ; ribbon would have.
    static Hook(s, n, item) {
        id := AxRibUi.Get(item, "Id")
        if (id = "")
            return '<div class="axd-note">Give it an id and it can be given something to do.</div>'
        kind := StrLower(String(AxRibUi.Get(item, "Kind", "button")))
        ev := (kind = "toggle" || kind = "check") ? ("Toggle:" id)
            : (kind = "input") ? ("Input:" id) : ("Command:" id)
        at := 0
        for i, e in n.Ev
            if (e["name"] = ev)
                at := i
        if !at
            return '<div class="axd-note axd-ribhook"><span class="axd-hbtn axd-go" data-do="rib.hook">'
                 . 'When it is used...</span> writes ' AxTags.E(AxGen.HandlerName(n, ev)) '(), which the '
                 . 'ribbon calls for this item alone.</div>'
        return '<div class="axd-note axd-ribhook"><span class="axd-hbtn axd-go" data-do="rib.hook">Edit what it does</span> '
             . '<span class="axd-hbtn" data-do="rib.unhook">Remove it</span><br>'
             . AxTags.E(AxGen.HandlerName(n, ev)) "()"
             . (Trim(n.Ev[at]["code"]) != "" ? "<br>" AxTags.E(AxPanes.Peek(n.Ev[at]["code"])) : "") '</div>'
    }
    ; Writing one field back. The kinds the pane gives back are text, so the
    ; ones that are not text are turned here -- and a field set back to nothing
    ; is REMOVED rather than written as "", because {Icon: ""} is noise in the
    ; expression and an empty flag is a flag that is off.
    static Set(node, key, v, kind) {
        if (kind = "flag") {
            if (v && v != "0")
                node[key] := true
            else if node.Has(key)
                node.Delete(key)
            return
        }
        if (kind = "multiline") {
            list := []
            for line in StrSplit(StrReplace(String(v), "`r", ""), "`n")
                if (Trim(line) != "")
                    list.Push(Trim(line))
            if list.Length
                node[key] := list
            else if node.Has(key)
                node.Delete(key)
            return
        }
        v := String(v)
        if (kind = "num" && Trim(v) != "" && IsNumber(v)) {
            node[key] := v + 0
            return
        }
        if (Trim(v) = "") {
            if node.Has(key)
                node.Delete(key)
            return
        }
        node[key] := v
    }

    ; How many times one thing is in another. Used by the studio's own checks.
    static CountOf(hay, needle) {
        n := 0, pos := 1
        while (pos := InStr(hay, needle, , pos)) {
            n++
            pos += StrLen(needle)
        }
        return n
    }

    ; ---------------------------------------------------------- the actions
    ; Every button in the tree comes back here as "rib.<what>.<path>".
    static Do(s, act) {
        n := s.Primary()
        if (!IsObject(n) || n.Type != "Ribbon")
            return
        what := SubStr(act, 5)
        path := ""
        if ((dot := InStr(what, ".")) > 0)
            path := SubStr(what, dot + 1), what := SubStr(what, 1, dot - 1)
        if (what = "literal")
            return AxRibUi.Literal(s, n)
        cfg := AxRibUi.Cfg(n)
        if !IsObject(cfg)
            return
        if (what = "sel") {
            s.RibSel := path
            ; the canvas draws one tab at a time, and it draws the one being
            ; edited -- so picking a row redraws it as well as the pane
            AxRibUi.Draw(s, path)
            s.Reflect(false)
            return s.RefreshCanvas()
        }
        if (what = "hook" || what = "unhook")
            return AxRibUi.DoHook(s, n, cfg, what = "unhook")
        s.Mark()
        switch what {
        case "addtab":
            id := AxRibUi.NewId(cfg, "tab")
            AxRibUi.List(cfg, "Tabs").Push(AxRibUi.Obj("Id", id, "Title", "Tab", "Groups", []))
            s.RibSel := AxRibUi.List(cfg, "Tabs").Length
        case "addgroup":
            tab := AxRibUi.Walk(cfg, path)
            if !(tab is Map)
                return
            id := AxRibUi.NewId(cfg, "group")
            AxRibUi.List(tab, "Groups").Push(AxRibUi.Obj("Id", id, "Title", "Group", "Items", []))
            s.RibSel := path "-" AxRibUi.List(tab, "Groups").Length
        case "additem":
            grp := AxRibUi.Walk(cfg, path)
            if !(grp is Map)
                return
            id := AxRibUi.NewId(cfg, "item")
            AxRibUi.List(grp, "Items").Push(AxRibUi.Obj("Id", id, "Label", "Item", "Icon", "E8B9"))
            s.RibSel := path "-" AxRibUi.List(grp, "Items").Length
        case "up", "dn":
            if !AxRibUi.Slot(cfg, path, &list, &idx)
                return
            to := idx + (what = "up" ? -1 : 1)
            if (to < 1 || to > list.Length)
                return
            one := list[idx]
            list.RemoveAt(idx)
            list.InsertAt(to, one)
            s.RibSel := AxRibUi.Repath(path, to)
        case "dup":
            if !AxRibUi.Slot(cfg, path, &list, &idx)
                return
            copy := AxRibUi.Clone(list[idx])
            ; a copy with the same id would run the same handler, silently
            AxRibUi.Rename(cfg, copy)
            list.InsertAt(idx + 1, copy)
            s.RibSel := AxRibUi.Repath(path, idx + 1)
        case "del":
            if !AxRibUi.Slot(cfg, path, &list, &idx)
                return
            list.RemoveAt(idx)
            s.RibSel := list.Length ? AxRibUi.Repath(path, Min(idx, list.Length))
                                    : AxRibUi.Up(path)
        default:
            return
        }
        AxRibUi.Put(s, n, cfg)
        s.Reflect(false)
        s.RefreshCanvas()
        s.QueueLive()
    }
    static Repath(path, last) {
        parts := StrSplit(String(path), "-")
        parts[parts.Length] := last
        out := ""
        for p in parts
            out .= (out = "" ? "" : "-") p
        return out
    }
    static Up(path) {
        parts := StrSplit(String(path), "-")
        if (parts.Length < 2)
            return ""
        out := ""
        loop parts.Length - 1
            out .= (out = "" ? "" : "-") parts[A_Index]
        return out
    }
    static Clone(v) {
        if (v is Array) {
            out := []
            for x in v
                out.Push(AxRibUi.Clone(x))
            return out
        }
        if (v is Map) {
            out := Map()
            out.CaseSense := false
            for k, x in v
                out[k] := AxRibUi.Clone(x)
            return out
        }
        return v
    }
    ; Give a copied branch ids of its own, all the way down.
    static Rename(cfg, node) {
        if !(node is Map)
            return
        if (AxRibUi.Get(node, "Id") != "")
            node["Id"] := AxRibUi.NewId(cfg, RegExReplace(AxRibUi.Get(node, "Id"), "\d+$"))
        for key in ["Groups", "Items"]
            if (node.Has(key) && node[key] is Array)
                for kid in node[key]
                    AxRibUi.Rename(cfg, kid)
    }
    static DoHook(s, n, cfg, remove) {
        path := AxRibUi.Sel(s, cfg)
        item := AxRibUi.Walk(cfg, path)
        if (!(item is Map) || AxRibUi.Depth(path) != 3)
            return
        id := AxRibUi.Get(item, "Id")
        if (id = "")
            return
        kind := StrLower(String(AxRibUi.Get(item, "Kind", "button")))
        ev := (kind = "toggle" || kind = "check") ? ("Toggle:" id)
            : (kind = "input") ? ("Input:" id) : ("Command:" id)
        if remove {
            for i, e in n.Ev
                if (e["name"] = ev)
                    return s.RemoveEvent(n, i)
            return
        }
        s.AddEvent(n, ev)
    }
    ; The way back when the expression is code: keep it, commented, and start
    ; from something the tree can show. Nothing is thrown away.
    static Literal(s, n) {
        s.Mark()
        old := Trim(String(n.Arg))
        keep := ""
        if (old != "")
            for line in StrSplit(StrReplace(old, "`r", ""), "`n")
                keep .= "`; " line "`n"
        cfg := Map()
        cfg.CaseSense := false
        cfg["Tabs"] := [AxRibUi.Obj("Id", "home", "Title", "Home", "Groups",
                          [AxRibUi.Obj("Id", "g1", "Title", "Group", "Items",
                            [AxRibUi.Obj("Id", "one", "Label", "One", "Icon", "E8B9", "Size", "large")])])]
        n.Arg := keep AxLit.Write(cfg, 0, AxRibUi.ORDER)
        s.RibSel := "1"
        s.P.Dirty := true
        s.Reflect(false)
        s.RefreshCanvas()
        s.QueueLive()
    }
}
