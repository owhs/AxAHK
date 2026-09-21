#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk

; =============================================================================
;  AxFileSource.ahk — where a file view gets its files.
;
;  A source answers a handful of questions about a tree of things that have
;  names, and the view never asks anything else. That is the whole contract,
;  and it is why the same view draws your disk, a made-up drive, the registry
;  and the inside of a .zip without knowing which it is looking at.
;
;      src := AxFileLocal(A_MyDocuments)       ; the real thing
;      src := AxFileVirtual(tree)              ; invented, or fetched, or cached
;      src := AxFileReg()                      ; HKCU and its friends
;      src := AxFileZip("backup.zip")          ; inside an archive
;
;  --------------------------------------------------------------- the contract
;  A source is any object with these. Subclass AxFileSource and you inherit
;  sensible versions of all but List.
;
;    Scheme      "file" | "vfs" | "reg" | "zip" | your own
;    Label       what the root is called ("This PC", "Backup.zip")
;    Icon        a Segoe Fluent glyph for the root
;    Sep         the separator between path segments ("\", "/")
;    Caps        {Rename, Delete, NewFolder, Drop, Write, Thumbs} — what the
;                view may offer. Nothing here is enforced; it decides which
;                menu items and gestures appear.
;    RootPath    the path of the root, often ""
;
;    List(path)          -> Array of items in that folder
;    Item(path)          -> the one item at that path, or ""
;    Parent(path)        -> the path above, "" at the root
;    Join(path, name)    -> a child's path
;    Name(path)          -> the last segment
;    Crumbs(path)        -> [{Path, Label, Icon}], root first
;    Exists(path)        -> is there anything there
;    Read(path, max)     -> text for the preview, "" if it is not text
;    Thumb(item)         -> a URL the page can put in <img>, or ""
;    Refresh(path)       -> drop whatever is cached for that folder
;
;  ------------------------------------------------------------------ an item
;  Whatever a source lists, it lists as one of these. Only Name is required;
;  AxFileSource.Make fills the rest in.
;
;    Key       identity inside its folder (defaults to Name)
;    Name      what to show
;    Path      the full path, as this source spells it
;    Kind      "folder" | "file" | "drive" | "key" | "value" | anything else;
;              "folder", "drive" and "key" are the ones you can go into
;    Icon      a glyph; blank lets the view pick one from the name
;    Size      bytes, or "" where size means nothing
;    Modified  a timestamp (YYYYMMDDHHMISS), or ""
;    Type      "Folder", "PNG image", "REG_SZ" ... shown in the Type column
;    Hidden    true to grey it out and hide it unless hidden items are shown
;    Kids      1 it has children, 0 it has none, -1 nobody has looked yet
;    Data      the source's own payload, untouched
;
;  Any other property rides along and a column can show it, so a source that
;  knows about ratings, owners or play counts just puts them on the item.
; =============================================================================
class AxFileSource {
    static _reg := AxRich.Register("FileSource")

    Scheme := "vfs"
    Label  := "Files"
    Icon   := "E8B7"
    Sep    := "\"
    RootPath := ""
    Caps := {Rename: false, Delete: false, NewFolder: false, Drop: false, Write: false, Thumbs: false}

    ; --------------------------------------------------------------- an item
    ; Make({Name: "notes.txt", Size: 2100}) -> a complete item. Extra
    ; properties are kept, so a source can carry anything a column wants.
    static Make(o) {
        it := {Key: "", Name: "", Path: "", Kind: "file", Icon: "", Size: "",
               Modified: "", Type: "", Hidden: false, Kids: -1, Data: ""}
        if IsObject(o) {
            for k, v in (o is Map ? o : o.OwnProps())
                it.%k% := v
        } else
            it.Name := String(o)
        if (it.Key = "")
            it.Key := it.Name
        if (it.Type = "")
            it.Type := AxFileSource.TypeOf(it)
        if (it.Icon = "")
            it.Icon := AxFileSource.GlyphOf(it)
        return it
    }
    ; A folder holds things; a file does not. Every view asks this rather than
    ; comparing Kind itself, so a source can invent a kind that opens.
    static IsBranch(it) {
        k := IsObject(it) ? StrLower(String(it.Kind)) : StrLower(String(it))
        return (k = "folder" || k = "drive" || k = "key" || k = "root")
    }
    static GlyphOf(it) {
        switch StrLower(String(it.Kind)) {
        case "folder": return "E8B7"
        case "drive":  return "EDA2"
        case "key":    return "E8F1"
        case "value":  return "E8EC"
        case "root":   return "E80F"
        }
        return AxWindow.FileGlyph(it.Name)
    }
    static Exts := Map(
        "png,jpg,jpeg,gif,bmp,ico,webp,tif,tiff", "image",
        "svg",                                    "vector",
        "mp4,mkv,avi,mov,wmv,webm,mpg,m4v",       "video",
        "mp3,wav,flac,m4a,ogg,wma,aac",           "audio",
        "zip,7z,rar,cab,tar,gz,iso",              "archive",
        "pdf",                                    "pdf",
        "txt,md,log,ini,csv,nfo,rst",             "text",
        "ahk,ahk2,js,ts,py,cs,cpp,c,h,json,xml,html,htm,css,ps1,bat,cmd,rb,go,rs,lua,sql,yml,yaml", "code",
        "doc,docx,odt,rtf",                       "document",
        "xls,xlsx,ods",                           "sheet",
        "ppt,pptx,odp",                           "slides",
        "exe,msi,dll,com,sys",                    "program",
        "ttf,otf,woff,woff2",                     "font")
    ; "PNG image", "AutoHotkey script", "Folder" — what the Type column says.
    static TypeOf(it) {
        if AxFileSource.IsBranch(it)
            return (StrLower(String(it.Kind)) = "drive") ? "Drive"
                 : (StrLower(String(it.Kind)) = "key") ? "Registry key" : "Folder"
        SplitPath(it.Name, , , &ext)
        if (ext = "")
            return "File"
        return StrUpper(ext) " file"
    }
    ; The broad family a name belongs to: "image", "code", "audio"... The
    ; preview pane picks a renderer with this, and the view groups by it.
    static Family(name) {
        if AxFileSource.IsBranch({Kind: "file", Name: name})
            return "folder"
        SplitPath(String(name), , , &ext)
        ext := StrLower(ext)
        if (ext = "")
            return "other"
        for list, fam in AxFileSource.Exts
            if InStr("," list ",", "," ext ",")
                return fam
        return "other"
    }
    static Ext(name) {
        SplitPath(String(name), , , &ext)
        return StrLower(ext)
    }

    ; ------------------------------------------------------------- defaults
    ; Everything below works off Sep and List, so a new source is usually
    ; List() and nothing else.
    List(path) => []
    Item(path) {
        p := this.Parent(path)
        if (p = "" && path = this.RootPath)
            return AxFileSource.Make({Name: this.Label, Path: this.RootPath, Kind: "root", Icon: this.Icon})
        for it in this.List(p)
            if (it.Path = path)
                return it
        return ""
    }
    Parent(path) {
        p := RTrim(String(path), this.Sep)
        if (p = "" || p = this.RootPath)
            return ""
        i := InStr(p, this.Sep, , -1)
        return i ? SubStr(p, 1, i - 1) : this.RootPath
    }
    Join(path, name) {
        p := String(path)
        if (p = "")
            return String(name)
        return RTrim(p, this.Sep) this.Sep name
    }
    Name(path) {
        p := RTrim(String(path), this.Sep)
        i := InStr(p, this.Sep, , -1)
        return i ? SubStr(p, i + 1) : p
    }
    Exists(path) => IsObject(this.Item(path))
    Read(path, max := 262144) => ""
    Thumb(it) => ""
    Refresh(path := "") => this
    ; The trail from the root down to here. The root always leads, so the
    ; breadcrumb has somewhere to go home to.
    Crumbs(path) {
        out := [{Path: this.RootPath, Label: this.Label, Icon: this.Icon}]
        p := String(path)
        if (p = "" || p = this.RootPath)
            return out
        rest := (this.RootPath != "" && InStr(p, this.RootPath) = 1)
              ? LTrim(SubStr(p, StrLen(this.RootPath) + 1), this.Sep) : p
        at := this.RootPath
        for seg in StrSplit(rest, this.Sep) {
            if (seg = "")
                continue
            at := this.Join(at, seg)
            out.Push({Path: at, Label: seg, Icon: ""})
        }
        return out
    }
    ; The folders directly under a path — what the tree pane asks for, and
    ; what tells it whether to draw a twisty.
    Branches(path) {
        out := []
        for it in this.List(path)
            if AxFileSource.IsBranch(it)
                out.Push(it)
        return out
    }
    ; Sources that cache say so, so Refresh knows there is work to do.
    Cached => false
}

; =============================================================================
;  AxFileLocal — the disk.
;
;      AxFileLocal()                 ; This PC: every drive
;      AxFileLocal(A_MyDocuments)    ; rooted there, and no way above it
;
;  Rooted at "" the first level is the drives, which are items with Kind
;  "drive" and a free-space bar the view can show as a column.
; =============================================================================
class AxFileLocal extends AxFileSource {
    __New(root := "", label := "") {
        this.Scheme := "file"
        this.Sep := "\"
        this.RootPath := RTrim(String(root), "\")
        if (this.RootPath != "" && StrLen(this.RootPath) = 2 && SubStr(this.RootPath, 2, 1) = ":")
            this.RootPath .= "\"                 ; "C:" is the current directory; "C:\" is the drive
        this.Label := (label != "") ? label
            : (this.RootPath = "") ? "This PC" : (this.Name(this.RootPath) != "" ? this.Name(this.RootPath) : this.RootPath)
        this.Icon := (this.RootPath = "") ? "E977" : "E8B7"
        this.Caps := {Rename: true, Delete: true, NewFolder: true, Drop: true, Write: true, Thumbs: true}
    }
    List(path) {
        p := String(path)
        if (p = "" && this.RootPath = "")
            return this._Drives()
        if (p = "")
            p := this.RootPath
        out := []
        ; A folder that is gone, or that we may not read, is an empty folder
        ; rather than an exception: the view shows its empty message and the
        ; status line says what happened.
        try {
            Loop Files, RTrim(p, "\") "\*", "FD" {
                hidden := InStr(A_LoopFileAttrib, "H") || InStr(A_LoopFileAttrib, "S")
                dir := InStr(A_LoopFileAttrib, "D")
                out.Push(AxFileSource.Make({Name: A_LoopFileName, Path: A_LoopFileFullPath,
                    Kind: dir ? "folder" : "file", Size: dir ? "" : A_LoopFileSize,
                    Modified: A_LoopFileTimeModified, Hidden: hidden ? true : false,
                    Kids: dir ? -1 : 0, Attrib: A_LoopFileAttrib}))
            }
        }
        return out
    }
    _Drives() {
        out := []
        for letter in StrSplit(DriveGetList(), "") {
            root := letter ":\"
            label := "", total := 0, free := 0, kind := ""
            try label := DriveGetLabel(root)
            try kind := DriveGetType(root)
            try total := DriveGetCapacity(root) * 1048576
            try free := DriveGetSpaceFree(root) * 1048576
            out.Push(AxFileSource.Make({Name: root, Key: root, Path: root, Kind: "drive",
                Type: (kind != "" ? kind " drive" : "Drive"), Kids: 1,
                Label: (label != "" ? label : (kind = "CDROM" ? "Disc" : "Local disk")),
                Size: "", Total: total, Free: free,
                Used: total ? Round((total - free) / total * 100) : 0}))
        }
        return out
    }
    Item(path) {
        p := String(path)
        if (p = "" || p = this.RootPath)
            return AxFileSource.Make({Name: this.Label, Path: this.RootPath, Kind: "root", Icon: this.Icon})
        if DirExist(p) {
            it := AxFileSource.Make({Name: this.Name(p), Path: p, Kind: "folder", Kids: -1})
            try it.Modified := FileGetTime(p, "M")
            return it
        }
        if FileExist(p) {
            it := AxFileSource.Make({Name: this.Name(p), Path: p, Kind: "file", Kids: 0})
            try it.Size := FileGetSize(p)
            try it.Modified := FileGetTime(p, "M")
            try it.Hidden := InStr(FileGetAttrib(p), "H") ? true : false
            return it
        }
        return ""
    }
    Parent(path) {
        p := RTrim(String(path), "\")
        if (p = "" || p = RTrim(this.RootPath, "\"))
            return ""
        if (StrLen(p) = 2 && SubStr(p, 2, 1) = ":")      ; a drive's parent is This PC
            return this.RootPath
        i := InStr(p, "\", , -1)
        if !i
            return this.RootPath
        up := SubStr(p, 1, i - 1)
        return (StrLen(up) = 2 && SubStr(up, 2, 1) = ":") ? up "\" : up
    }
    Exists(path) => (DirExist(path) || FileExist(path)) ? true : false
    ; Only what is plausibly text, and only the first stretch of it: the
    ; preview is a look, not an editor.
    Read(path, max := 262144) {
        fam := AxFileSource.Family(path)
        if (fam != "text" && fam != "code" && fam != "other")
            return ""
        try {
            if (FileGetSize(path) > max * 4)
                return SubStr(FileRead(path, "UTF-8"), 1, max)
            return FileRead(path, "UTF-8")
        }
        return ""
    }
    Thumb(it) {
        if (!IsObject(it) || AxFileSource.IsBranch(it))
            return ""
        return (AxFileSource.Family(it.Name) = "image" || AxFileSource.Family(it.Name) = "vector")
             ? AxSys.FileUrl(it.Path) : ""
    }
    ; ------------------------------------------------------------- places
    ; The folders Windows gives everyone a name for. Each is {Label, Path,
    ; Icon, Group}, and a folder that is not on this machine is left out, so
    ; the list is always somewhere you can actually go.
    static Known() {
        out := []
        Add(label, path, icon, group) {
            if (path != "" && DirExist(path))
                out.Push({Label: label, Path: RTrim(path, "\"), Icon: icon, Group: group})
        }
        home := EnvGet("USERPROFILE")
        Add("Home",      home,                    "E80F", "Quick access")
        Add("Desktop",   home "\Desktop",         "E7F4", "Quick access")
        Add("Documents", A_MyDocuments,           "E8A5", "Quick access")
        Add("Downloads", home "\Downloads",       "E896", "Quick access")
        Add("Pictures",  home "\Pictures",        "EB9F", "Quick access")
        Add("Music",     home "\Music",           "E8D6", "Quick access")
        Add("Videos",    home "\Videos",          "E714", "Quick access")
        Add("OneDrive",  EnvGet("OneDrive"),      "E753", "Quick access")
        Add("AppData",   EnvGet("APPDATA"),       "E713", "System")
        Add("Temp",      A_Temp,                  "E74D", "System")
        Add("Program Files", EnvGet("ProgramFiles"), "E770", "System")
        Add("Windows",   A_WinDir,                "E770", "System")
        return out
    }
    ; Every drive, as a place, so a places list can end the way This PC does.
    static Drives() {
        out := []
        for letter in StrSplit(DriveGetList(), "") {
            root := letter ":\"
            label := ""
            try label := DriveGetLabel(root)
            out.Push({Label: (label != "" ? label " (" letter ":)" : root), Path: root,
                      Icon: "EDA2", Group: "This PC"})
        }
        return out
    }

    ; The real shell icon, as a data URI, for a program or a document type.
    ; Costs a GDI+ round trip each, so the view only asks for the ones on
    ; screen and remembers the answers.
    ShellIcon(it, size := 32) {
        if (!IsObject(it) || AxFileSource.IsBranch(it))
            return ""
        try return AxSys.IconDataUri(it.Path ",0", size)
        return ""
    }
    Crumbs(path) {
        out := [{Path: this.RootPath, Label: this.Label, Icon: this.Icon}]
        p := RTrim(String(path), "\")
        if (p = "" || p = RTrim(this.RootPath, "\"))
            return out
        if (this.RootPath = "") {
            segs := StrSplit(p, "\")
            at := segs[1] "\"
            out.Push({Path: at, Label: segs[1], Icon: "EDA2"})
            loop segs.Length - 1 {
                s := segs[A_Index + 1]
                if (s = "")
                    continue
                at := RTrim(at, "\") "\" s
                out.Push({Path: at, Label: s, Icon: ""})
            }
            return out
        }
        rest := LTrim(SubStr(p, StrLen(RTrim(this.RootPath, "\")) + 1), "\")
        at := RTrim(this.RootPath, "\")
        for s in StrSplit(rest, "\") {
            if (s = "")
                continue
            at .= "\" s
            out.Push({Path: at, Label: s, Icon: ""})
        }
        return out
    }
}

; =============================================================================
;  AxFileVirtual — a tree you hand it.
;
;      AxFileVirtual([{Name: "Photos", Kind: "folder", Children: [
;                        {Name: "beach.jpg", Size: 2400000, Rating: 4}]},
;                     {Name: "notes.txt", Size: 812, Text: "..."}],
;                    {Label: "My Drive", Icon: "E753", Sep: "/"})
;
;  Nodes are plain objects: Name and whatever else you want an item to carry.
;  Children makes a folder. Text is what the preview shows; Image is a URL it
;  shows instead. Nothing is read from disk, so this is how a source that is
;  really an API, a database or somebody's imagination arrives.
; =============================================================================
class AxFileVirtual extends AxFileSource {
    __New(tree := "", opts := "") {
        o := (n, d) => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        this.Scheme := o("Scheme", "vfs")
        this.Sep    := o("Sep", "/")
        this.Label  := o("Label", "Files")
        this.Icon   := o("Icon", "E8B7")
        this.RootPath := o("Root", "")
        this.Caps := o("Caps", {Rename: false, Delete: false, NewFolder: false,
                                Drop: false, Write: false, Thumbs: true})
        this._index := Map()                  ; path -> {Node, Item, Kids}
        this.SetTree(tree is Array ? tree : [])
    }
    SetTree(tree) {
        this.Tree := tree
        this._index := Map()
        this._Scan(tree, this.RootPath)
        return this
    }
    ; not _Index: AHK property names are case-insensitive, so a method of
    ; that name and the _index map below are one name, and the map would
    ; be read-only
    _Scan(list, at) {
        kids := []
        for node in list {
            name := this._Prop(node, "Name", "")
            if (name = "")
                continue
            path := this.Join(at, name)
            children := this._Prop(node, "Children", "")
            isDir := (children is Array) || (StrLower(String(this._Prop(node, "Kind", ""))) = "folder")
            src := {}
            for k, v in (node is Map ? node : node.OwnProps())
                if (k != "Children")
                    src.%k% := v
            src.Path := path
            src.Name := name
            if !src.HasOwnProp("Kind")
                src.Kind := isDir ? "folder" : "file"
            src.Kids := isDir ? ((children is Array) ? (children.Length ? 1 : 0) : -1) : 0
            it := AxFileSource.Make(src)
            this._index[path] := {Item: it, Kids: (children is Array) ? children : []}
            kids.Push(it)
            if (children is Array)
                this._Scan(children, path)
        }
        this._index[at] := {Item: (this._index.Has(at) ? this._index[at].Item
            : AxFileSource.Make({Name: this.Label, Path: at, Kind: "root", Icon: this.Icon})), Kids: list}
        ; the folder's own listing, already built
        this._index[at].List := kids
        return kids
    }
    _Prop(o, n, d := "") {
        if !IsObject(o)
            return d
        if (o is Map)
            return o.Has(n) ? o[n] : d
        return o.HasOwnProp(n) ? o.%n% : d
    }
    ; A tree rooted at "" spells its top level "Rolls", not "/Rolls", because
    ; Join has nothing to join to. Writing the leading separator anyway is the
    ; natural thing to do, so it is accepted rather than silently empty.
    _At(path) {
        p := String(path)
        if (this._index.Has(p) || this.RootPath != "" || this.Sep = "")
            return p
        t := LTrim(p, this.Sep)
        return this._index.Has(t) ? t : p
    }
    List(path) {
        p := this._At(path)
        if !this._index.Has(p)
            return []
        rec := this._index[p]
        if rec.HasOwnProp("List")
            return rec.List
        out := []
        for it in rec.Kids
            out.Push(this._index[this.Join(p, this._Prop(it, "Name", ""))].Item)
        return out
    }
    Item(path) {
        p := this._At(path)
        return this._index.Has(p) ? this._index[p].Item : ""
    }
    Exists(path) => this._index.Has(this._At(path))
    ; A node's Text is its preview. Anything else is not text and says so.
    Read(path, max := 262144) {
        it := this.Item(path)
        if !IsObject(it)
            return ""
        t := it.HasOwnProp("Text") ? it.Text : ""
        return (t != "") ? SubStr(String(t), 1, max) : ""
    }
    Thumb(it) => (IsObject(it) && it.HasOwnProp("Image")) ? it.Image : ""
}

; =============================================================================
;  AxFileReg — the registry as folders and files.
;
;      AxFileReg()              ; the five hives
;      AxFileReg("HKCU\Software\Microsoft\Windows\CurrentVersion")
;
;  Keys list as folders; values list as files whose Type is REG_SZ, REG_DWORD
;  and so on and whose Data is what is in them. The default value shows as
;  "(Default)". Nothing is written — this browses.
; =============================================================================
class AxFileReg extends AxFileSource {
    static Hives := ["HKEY_LOCAL_MACHINE", "HKEY_CURRENT_USER", "HKEY_CLASSES_ROOT",
                     "HKEY_USERS", "HKEY_CURRENT_CONFIG"]
    static Short := Map("HKEY_LOCAL_MACHINE", "HKLM", "HKEY_CURRENT_USER", "HKCU",
                        "HKEY_CLASSES_ROOT", "HKCR", "HKEY_USERS", "HKU",
                        "HKEY_CURRENT_CONFIG", "HKCC")
    __New(root := "") {
        this.Scheme := "reg"
        this.Sep := "\"
        this.RootPath := RTrim(String(root), "\")
        this.Label := (this.RootPath = "") ? "Registry" : this.Name(this.RootPath)
        this.Icon := "E713"
        this.Caps := {Rename: false, Delete: false, NewFolder: false, Drop: false,
                      Write: false, Thumbs: false}
    }
    List(path) {
        p := RTrim(String(path), "\")
        if (p = "" && this.RootPath = "")
            return this._Hives()
        if (p = "")
            p := this.RootPath
        out := []
        try {
            Loop Reg, p, "K" {
                out.Push(AxFileSource.Make({Name: A_LoopRegName, Path: p "\" A_LoopRegName,
                    Kind: "key", Type: "Registry key", Kids: -1,
                    Modified: A_LoopRegTimeModified}))
            }
        }
        try {
            Loop Reg, p, "V" {
                name := (A_LoopRegName = "") ? "(Default)" : A_LoopRegName
                data := ""
                try data := RegRead(p, A_LoopRegName)
                out.Push(AxFileSource.Make({Name: name, Key: "v:" name, Path: p "\\" name,
                    Kind: "value", Type: A_LoopRegType, Kids: 0, Icon: "E8EC",
                    Data: data, Size: StrLen(String(data)),
                    ValueName: A_LoopRegName, KeyPath: p}))
            }
        }
        return out
    }
    _Hives() {
        out := []
        for h in AxFileReg.Hives
            out.Push(AxFileSource.Make({Name: AxFileReg.Short[h], Path: h, Kind: "key",
                Type: "Hive", Icon: "E8F1", Kids: 1, Full: h}))
        return out
    }
    ; A value's path carries a doubled separator before its name, so a key
    ; called Run and a value called Run under the same parent stay apart.
    Item(path) {
        p := String(path)
        if (p = "" || p = this.RootPath)
            return AxFileSource.Make({Name: this.Label, Path: this.RootPath, Kind: "root", Icon: this.Icon})
        if InStr(p, "\\") {
            for it in this.List(SubStr(p, 1, InStr(p, "\\", , -1) - 1))
                if (it.Path = p)
                    return it
            return ""
        }
        return AxFileSource.Make({Name: this.Name(p), Path: p, Kind: "key", Kids: -1})
    }
    Parent(path) {
        p := RTrim(String(path), "\")
        if (p = "" || p = this.RootPath)
            return ""
        if (i := InStr(p, "\\", , -1))
            return SubStr(p, 1, i - 1)
        i := InStr(p, "\", , -1)
        return i ? SubStr(p, 1, i - 1) : this.RootPath
    }
    Read(path, max := 262144) {
        it := this.Item(path)
        return (IsObject(it) && it.Kind = "value") ? SubStr(String(it.Data), 1, max) : ""
    }
    Branches(path) {
        out := []
        for it in this.List(path)
            if (it.Kind = "key")
                out.Push(it)
        return out
    }
}

; =============================================================================
;  AxFileZip — inside a .zip, through the shell's own reader.
;
;      AxFileZip("C:\downloads\theme.zip")
;
;  The archive is walked once, on the first listing, and kept as a map of
;  paths. Reading a file copies that one entry to a temp folder — the shell
;  has no other way in — so Read is for the preview pane and small files.
; =============================================================================
class AxFileZip extends AxFileSource {
    __New(zipPath, label := "") {
        this.Scheme := "zip"
        this.Sep := "\"
        this.Zip := String(zipPath)
        this.RootPath := ""
        SplitPath(this.Zip, &base)
        this.Label := (label != "") ? label : (base != "" ? base : "Archive")
        this.Icon := "F012"
        this.Caps := {Rename: false, Delete: false, NewFolder: false, Drop: false,
                      Write: false, Thumbs: false}
        this._index := ""
        this._temp := ""
    }
    Cached => true
    Refresh(path := "") {
        this._index := ""
        return this
    }
    _Build() {
        if IsObject(this._index)
            return this._index
        idx := Map()
        idx[""] := []
        try {
            sh := ComObject("Shell.Application")
            folder := sh.NameSpace(this.Zip)
            if IsObject(folder)
                this._Walk(sh, folder, "", idx)
        }
        this._index := idx
        return idx
    }
    ; Shell folders are enumerated by index; a nested one is reached by asking
    ; the shell for the item's own folder rather than by building a path.
    _Walk(sh, folder, at, idx) {
        items := folder.Items()
        loop items.Count {
            fi := items.Item(A_Index - 1)
            name := ""
            try name := fi.Name
            if (name = "")
                continue
            path := (at = "") ? name : at "\" name
            isDir := false
            try isDir := fi.IsFolder
            size := "", modified := ""
            try size := isDir ? "" : fi.Size
            try modified := FormatTime(fi.ModifyDate, "yyyyMMddHHmmss")
            it := AxFileSource.Make({Name: name, Path: path, Kind: isDir ? "folder" : "file",
                Size: size, Modified: modified, Kids: isDir ? -1 : 0})
            if !idx.Has(at)
                idx[at] := []
            idx[at].Push(it)
            if isDir {
                idx[path] := []
                try this._Walk(sh, fi.GetFolder, path, idx)
                it.Kids := idx[path].Length ? 1 : 0
            }
        }
    }
    List(path) {
        idx := this._Build()
        p := String(path)
        return idx.Has(p) ? idx[p] : []
    }
    Exists(path) => this._Build().Has(String(path)) || IsObject(this.Item(path))
    ; One entry, extracted to a temp folder the first time it is asked for.
    Extract(path) {
        if (this._temp = "") {
            this._temp := A_Temp "\AxGui\zip_" Format("{:08x}", Random(0, 0x7FFFFFFF))
            try DirCreate(this._temp)
        }
        out := this._temp "\" this.Name(path)
        if FileExist(out)
            return out
        try {
            sh := ComObject("Shell.Application")
            src := sh.NameSpace(this.Zip "\" path)
            if !IsObject(src) {
                item := sh.NameSpace(this.Zip).ParseName(StrReplace(path, "/", "\"))
                if !IsObject(item)
                    return ""
                sh.NameSpace(this._temp).CopyHere(item, 20)         ; 4 no progress, 16 yes to all
            }
        }
        catch
            return ""
        loop 60 {                      ; CopyHere is asynchronous and says nothing
            if FileExist(out)
                return out
            Sleep 50
        }
        return FileExist(out) ? out : ""
    }
    Read(path, max := 262144) {
        fam := AxFileSource.Family(path)
        if (fam != "text" && fam != "code" && fam != "other")
            return ""
        f := this.Extract(path)
        if (f = "")
            return ""
        try return SubStr(FileRead(f, "UTF-8"), 1, max)
        return ""
    }
    Thumb(it) {
        if (!IsObject(it) || AxFileSource.IsBranch(it))
            return ""
        if (AxFileSource.Family(it.Name) != "image")
            return ""
        f := this.Extract(it.Path)
        return (f != "") ? AxSys.FileUrl(f) : ""
    }
}
