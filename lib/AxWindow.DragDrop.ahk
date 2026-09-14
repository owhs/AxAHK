#Requires AutoHotkey v2.0
; =============================================================================
;  AxWindow.DragDrop.ahk — files and folders dragged onto the page.
;
;      win.DropZone("photos", (files, id) => win.Toast(files.Length " image(s)"),
;                   {Accept: "images", Browse: true})
;      win.DropZone("*", (files, id) => ...)        ; anywhere in the window
;
;  A real OLE IDropTarget is registered on the window and on Trident's inner
;  windows (whose own drop target is revoked first, otherwise Internet
;  Explorer swallows the drop and navigates to the file). That buys live
;  feedback the shell's WM_DROPFILES cannot give: while the cursor moves, the
;  element under it is hit-tested in the DOM, the matching zone gets the
;  "dragover" class (or "reject" when the files do not pass its filter) and
;  the drop cursor shows copy or no-entry accordingly. WM_DROPFILES stays
;  hooked as a fallback for the case where registration fails.
;
;  Nothing is registered until the first DropZone() call, so a window that
;  wants no drops keeps Trident's own behaviour (text dropped into inputs).
;
;  Zone options (all optional):
;      Accept    "*" (default) | "files" | "folders" | "images" | "media" |
;                "docs" | "text" | "*.png;*.jpg" | a callback fn(path)->bool
;      Multi     true (default); false rejects a drop of more than one item
;      Expand    true: folders are replaced by the files inside them
;      Recurse   with Expand, walk sub-folders too
;      Browse    true: clicking the zone opens the file/folder picker
;                (folders use the modern picker, see SelectFolder below)
;      Hover     class applied while a valid drag is over it ("dragover")
;      OnEnter   fn(files, id)   once, when a valid drag arrives
;      OnLeave   fn(id)          when it leaves again, and after a drop
;
;  The drop callback is fn(files, id, info); files is an Array of full paths,
;  info carries {X, Y, Zone, Ctrl, Shift, Alt}. It runs on its own thread
;  (SetTimer -1) so it may open dialogs without stalling the drag loop.
; =============================================================================
class AxWindowDragDrop {
    static _dt := Map()          ; instance id -> AxWindow (the vtable is shared)
    static _dtNext := 0
    static _dtVtCbs := []        ; keeps the vtable's callbacks alive

    ; ----------------------------------------------------------------- public
    ; Register (or update) a drop zone. id is an element id, or "*" for the
    ; whole window. Calling it again with a new fn or new options merges.
    DropZone(id, fn := "", opts := "") {
        this._EnsureDrop()
        z := this._dropZones.Has(id) ? this._dropZones[id] : this._DefaultZone()
        if (fn != "")
            z.Fn := fn
        if IsObject(opts)
            for k, v in opts.OwnProps()
                z.%k% := v
        this._dropZones[id] := z
        if this.Ready
            this._InstallDropTarget()
        return this
    }
    OnDrop(id, fn, opts := "") => this.DropZone(id, fn, opts)
    ; The modern folder picker (the file dialog restricted to folders, not the
    ; old SHBrowseForFolder tree), owned by this window so it opens modal to it.
    ; Returns "" when cancelled, a path, or an Array of paths with Multi.
    SelectFolder(prompt := "Choose a folder", startDir := "", opts := "") {
        o := {Owner: this.Gui.Hwnd}
        if IsObject(opts)
            for k, v in opts.OwnProps()
                o.%k% := v
        return AxSys.SelectFolder(prompt, startDir, o)
    }
    RemoveDropZone(id) {
        this._EnsureDrop()
        if this._dropZones.Has(id)               ; Map.Delete throws on a missing key
            this._dropZones.Delete(id)
        return this
    }
    ; true once an OLE drop target is live on this window
    DropEnabled => this.HasOwnProp("_dtHwnds") && this._dtHwnds.Length > 0

    ; ---------------------------------------------------------------- filters
    ; FilterFiles(files, accept) -> the subset that passes. accept is one of
    ; the words listed above, an extension list, or a callback.
    static FilterFiles(files, accept := "*") {
        static groups := Map(
            "images", "png jpg jpeg gif bmp ico svg",
            "media",  "mp4 mkv avi mov wmv webm mp3 wav flac m4a ogg",
            "docs",   "pdf doc docx xls xlsx ppt pptx odt rtf",
            "text",   "txt log md csv ini json xml html htm css js ahk ahk2 ps1 bat")
        if (accept = "" || accept = "*" || accept = "all")
            return files
        if (IsObject(accept) && HasMethod(accept, "Call")) {
            out := []
            for f in files
                try (accept(f) ? out.Push(f) : "")
            return out
        }
        a := StrLower(Trim(String(accept)))
        exts := ""
        if (a != "files" && a != "folders" && a != "dirs")
            exts := " " Trim(RegExReplace(groups.Has(a) ? groups[a] : RegExReplace(a, "[*.,;|]", " "), "\s+", " ")) " "
        out := []
        for f in files {
            isDir := DirExist(f) ? true : false
            if (a = "folders" || a = "dirs") {
                if isDir
                    out.Push(f)
                continue
            }
            if (a = "files") {
                if !isDir
                    out.Push(f)
                continue
            }
            if isDir                                  ; an extension filter never matches a folder
                continue
            SplitPath(f, , , &ext)
            if InStr(exts, " " StrLower(ext) " ")
                out.Push(f)
        }
        return out
    }
    ; Replace every folder in the list with the files it contains.
    static ExpandFolders(files, recurse := false) {
        out := []
        for f in files {
            if DirExist(f) {
                for p in AxWindow.FolderFiles(f, recurse)
                    out.Push(p)
            } else
                out.Push(f)
        }
        return out
    }
    ; Full paths of the files inside dir (sub-folders themselves are skipped).
    static FolderFiles(dir, recurse := false, pattern := "*.*") {
        out := []
        try {
            loop files RTrim(dir, "\") "\" pattern, recurse ? "FR" : "F"
                out.Push(A_LoopFileFullPath)
        }
        return out
    }

    ; ------------------------------------------------------------- file lists
    ; A Segoe Fluent Icons glyph that suits the file (folders included).
    static FileGlyph(path) {
        static byExt := Map(
            "png,jpg,jpeg,gif,bmp,ico,svg,webp",               "EB9F",   ; picture
            "mp4,mkv,avi,mov,wmv,webm,mpg",                    "E714",   ; video
            "mp3,wav,flac,m4a,ogg,wma",                        "E8D6",   ; music
            "zip,7z,rar,cab,tar,gz,iso",                       "F012",   ; archive
            "pdf",                                             "EA90",
            "doc,docx,odt,rtf,txt,md,log",                     "E8A5",   ; document
            "xls,xlsx,csv",                                    "E9F9",   ; grid
            "ppt,pptx",                                        "E786",
            "exe,msi,dll,com,bat,cmd",                         "ECAA",   ; app
            "ahk,ahk2,ps1,js,py,cs,cpp,c,h,json,xml,html,css", "E943")   ; code
        if DirExist(path)
            return "E8B7"
        SplitPath(path, , , &ext)
        ext := StrLower(ext)
        for list, glyph in byExt
            if InStr("," list ",", "," ext ",")
                return glyph
        return "E7C3"
    }
    ; 1.2 MB / 940 KB / 12 bytes
    static FileSize(bytes) {
        if (!IsNumber(bytes) || bytes < 0)
            return ""
        if (bytes < 1024)
            return bytes " bytes"
        for unit in ["KB", "MB", "GB", "TB"] {
            bytes /= 1024
            if (bytes < 1024 || unit = "TB")
                return Round(bytes, bytes < 10 ? 1 : 0) " " unit
        }
    }
    ; Markup for a list of paths, styled by the theme's .filelist rules.
    ; opts: {Removable, Sizes: true, Empty: "shown for an empty list",
    ;        Relative: "base folder stripped from the names"}
    FileListHtml(files, opts := "") {
        o := (n, d := "") => (IsObject(opts) && opts.HasOwnProp(n)) ? opts.%n% : d
        if !files.Length
            return '<div class="fl-empty">' AxWindow._Esc(o("Empty", "Nothing here yet.")) '</div>'
        base := RTrim(o("Relative", ""), "\"), rows := ""
        for f in files {
            isDir := DirExist(f) ? true : false
            name := ""
            if (base != "" && InStr(f, base) = 1)
                name := LTrim(SubStr(f, StrLen(base) + 1), "\")
            if (name = "")                            ; the base folder itself, or not below it
                SplitPath(f, &name)
            meta := isDir ? "Folder" : ""
            if (!isDir && o("Sizes", true)) {
                try meta := AxWindow.FileSize(FileGetSize(f))
                catch
                    meta := ""
            }
            rows .= '<div class="fl-row drag-item" data-value="' AxWindow._Esc(f) '" data-tip="' AxWindow._Esc(f) '">'
                . '<span class="ico fl-ico">&#x' AxWindow.FileGlyph(f) ';</span>'
                . '<span class="fl-name">' AxWindow._Esc(name) '</span>'
                . '<span class="fl-meta">' AxWindow._Esc(meta) '</span>'
                . (o("Removable", false) ? '<span class="remove ico" data-role="remove-item">&#xE8BB;</span>' : "")
                . '</div>'
        }
        return rows
    }
    ; Fill an element (e.g. AxGui's AddFileList) with that markup.
    SetFileList(id, files, opts := "") {
        try this.Html(id, this.FileListHtml(files, opts))
        return this
    }

    ; ---------------------------------------------------------------- private
    _EnsureDrop() {
        if !this.HasOwnProp("_dropZones") {
            this._dropZones := Map()
            this._dtObj := "", this._dtHwnds := [], this._dtFiles := []
            this._dtOver := "", this._dtOverEl := "", this._dtOverCls := "", this._dtBusy := false
        }
    }
    _DefaultZone() => {Fn: "", Accept: "*", Multi: true, Expand: false, Recurse: false,
        Browse: false, Hover: "dragover", OnEnter: "", OnLeave: ""}

    ; Called from _OnDocComplete and from DropZone() after the page is up.
    _InstallDropTarget() {
        this._EnsureDrop()
        if (this._dtObj || this.Closing || !this._dropZones.Count || !IsObject(this.Doc))
            return
        DllCall("ole32\OleInitialize", "Ptr", 0)        ; S_FALSE when COM is already up: harmless
        id := ++AxWindowDragDrop._dtNext
        AxWindowDragDrop._dt[id] := this
        this._dtId := id
        this._dtObj := AxWindowDragDrop._DtObject(id)
        hwnds := [this.Gui.Hwnd, this.Ax.Hwnd]
        cb := CallbackCreate((h, l) => (hwnds.Push(h), 1), "F", 2)
        DllCall("EnumChildWindows", "Ptr", this.Gui.Hwnd, "Ptr", cb, "Ptr", 0)
        CallbackFree(cb)
        for h in hwnds {
            DllCall("ole32\RevokeDragDrop", "Ptr", h)   ; Trident registers its own on the inner windows
            if !DllCall("ole32\RegisterDragDrop", "Ptr", h, "Ptr", this._dtObj.Ptr, "UInt")
                this._dtHwnds.Push(h)
        }
        DllCall("shell32\DragAcceptFiles", "Ptr", this.Gui.Hwnd, "Int", 1)   ; WM_DROPFILES fallback
    }
    _RemoveDropTarget() {
        if !this.HasOwnProp("_dtHwnds")
            return
        for h in this._dtHwnds
            try DllCall("ole32\RevokeDragDrop", "Ptr", h)
        this._dtHwnds := [], this._dtObj := ""
        if (this.HasOwnProp("_dtId") && AxWindowDragDrop._dt.Has(this._dtId))
            AxWindowDragDrop._dt.Delete(this._dtId)
    }

    ; --- hit testing -------------------------------------------------------
    ; device px inside the browser host -> CSS px inside the document
    _DocScale(x, y) {
        k := 1
        try {
            rc := Buffer(16, 0)
            DllCall("GetClientRect", "Ptr", this.Ax.Hwnd, "Ptr", rc)
            cw := this.Doc.documentElement.clientWidth
            if (cw > 0 && NumGet(rc, 8, "Int") > 0)
                k := NumGet(rc, 8, "Int") / cw
        }
        return {X: x / k, Y: y / k}
    }
    _DocPoint(screenX, screenY) {
        pt := Buffer(8, 0)
        NumPut("Int", screenX, pt, 0), NumPut("Int", screenY, pt, 4)
        DllCall("ScreenToClient", "Ptr", this.Ax.Hwnd, "Ptr", pt)
        return this._DocScale(NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int"))
    }
    ; The zone under a document point: the nearest registered id, else the
    ; nearest <ax-drop> element (which carries its filter in data-accept),
    ; else the window-wide "*" zone.
    _DropHit(x, y) {
        this._EnsureDrop()
        zones := this._dropZones
        try el := this.Doc.elementFromPoint(x, y)
        catch
            el := ""
        node := el
        loop 16 {
            if !IsObject(node)
                break
            try id := node.id
            catch
                id := ""
            if (id != "" && zones.Has(id))
                return {Id: id, El: node, Z: zones[id]}
            if (AxWindow._Attr(node, "data-role") = "dropzone") {
                z := this._DefaultZone()
                z.Accept := AxWindow._Attr(node, "data-accept")
                return {Id: id, El: node, Z: z}
            }
            node := AxWindow._ParentEl(node)
        }
        if zones.Has("*")
            return {Id: "*", El: "", Z: zones["*"]}
        return ""
    }
    ; What a zone would take from this drag ("" = it refuses the drop)
    _ZoneFiles(hit, files) {
        if (!hit || !IsObject(files) || !files.Length)
            return ""
        z := hit.Z
        src := z.Expand ? AxWindow.ExpandFolders(files, z.Recurse) : files
        got := AxWindow.FilterFiles(src, z.Accept)
        if (!got.Length || (!z.Multi && got.Length > 1))
            return ""
        return got
    }
    ; --- drag feedback -----------------------------------------------------
    _DropOver(hit, ok, files) {
        id := hit ? hit.Id : ""
        state := id "|" (ok ? 1 : 0)
        if (this._dtOver = state)
            return
        prev := (this._dtOver = "") ? "" : StrSplit(this._dtOver, "|")[1]
        this._DropUnpaint()
        this._dtOver := state
        if (IsObject(hit) && IsObject(hit.El)) {
            AxWindow._SetClass(hit.El, hit.Z.Hover, ok)
            AxWindow._SetClass(hit.El, "reject", !ok)
            this._dtOverEl := hit.El, this._dtOverCls := hit.Z.Hover
        }
        this.BodyClass("ax-dragging", true)
        if (prev = id)
            return
        this._DropLeaveCb(prev)
        if (ok && hit && hit.Z.OnEnter)
            SetTimer(this._DropLater(hit.Z.OnEnter, [files, id]), -1)
    }
    _DropUnpaint() {
        if IsObject(this._dtOverEl) {
            try {
                AxWindow._SetClass(this._dtOverEl, this._dtOverCls, false)
                AxWindow._SetClass(this._dtOverEl, "reject", false)
            }
        }
        this._dtOverEl := "", this._dtOverCls := ""
    }
    _DropLeaveCb(id) {
        if (id != "" && this._dropZones.Has(id) && this._dropZones[id].OnLeave)
            SetTimer(this._DropLater(this._dropZones[id].OnLeave, [id]), -1)
    }
    ; the drag ended (left the window, or dropped): forget every hover state
    _DropClear() {
        prev := (this._dtOver = "") ? "" : StrSplit(this._dtOver, "|")[1]
        this._DropUnpaint()
        this._dtOver := ""
        this.BodyClass("ax-dragging", false)
        this._DropLeaveCb(prev)
    }
    ; user callbacks never run inside the OLE drag loop
    _DropLater(fn, args) => () => this._SafeCall(fn, args)
    _SafeCall(fn, args) {
        try fn(args*)
        catch as e
            try this.Toast("Drop handler failed: " e.Message, 4000, "error")
    }
    ; The one place a completed drop turns into a callback (the OLE target,
    ; the WM_DROPFILES fallback and click-to-browse all land here).
    _DropCommit(files, x, y, keys := 0) {
        hit := this._DropHit(x, y)
        got := this._ZoneFiles(hit, files)
        this._DropClear()
        if (!hit || got = "" || !hit.Z.Fn)
            return false
        info := {X: x, Y: y, Zone: hit.Id, Ctrl: (keys & 0x8) ? 1 : 0,
                 Shift: (keys & 0x4) ? 1 : 0, Alt: GetKeyState("Alt", "P") ? 1 : 0}
        SetTimer(this._DropLater(hit.Z.Fn, [got, hit.Id, info]), -1)
        return true
    }
    ; --- click to browse ---------------------------------------------------
    ; A zone with Browse: true opens the matching picker on click and feeds
    ; the result through the same callback as a real drop.
    _DropBrowse(el) {
        this._EnsureDrop()
        id := ""
        try id := el.id
        if (id = "" || !this._dropZones.Has(id))
            return
        z := this._dropZones[id]
        if !z.Browse
            return
        files := []
        a := StrLower(String(z.Accept))
        if (a = "folders" || a = "dirs") {
            sel := this.SelectFolder(z.Multi ? "Choose folders" : "Choose a folder", , {Multi: z.Multi})
            if IsObject(sel) {
                for d in sel
                    files.Push(d)
            } else if (sel != "")
                files.Push(sel)
        } else {
            sel := FileSelect(z.Multi ? "M3" : 3, , "Choose a file", AxWindow._BrowseFilter(z.Accept))
            if !IsObject(sel) {
                if (sel != "")
                    files.Push(sel)
            } else if (sel.Length > 1 && InStr(FileExist(sel[1]), "D")) {
                dir := RTrim(sel[1], "\")             ; multi-select: [folder, name, name, ...]
                loop sel.Length - 1
                    files.Push(dir "\" sel[A_Index + 1])
            } else {
                for f in sel
                    files.Push(f)
            }
        }
        if !files.Length
            return
        if z.Expand
            files := AxWindow.ExpandFolders(files, z.Recurse)
        got := AxWindow.FilterFiles(files, z.Accept)
        if (got.Length && z.Fn)
            SetTimer(this._DropLater(z.Fn, [got, id, {X: 0, Y: 0, Zone: id, Ctrl: 0, Shift: 0, Alt: 0}]), -1)
    }
    static _BrowseFilter(accept) {
        static named := Map("images", "Images (*.png; *.jpg; *.jpeg; *.gif; *.bmp; *.ico; *.svg)",
            "media", "Media (*.mp4; *.mkv; *.avi; *.mov; *.mp3; *.wav; *.flac)",
            "docs",  "Documents (*.pdf; *.doc; *.docx; *.xls; *.xlsx; *.ppt; *.pptx)",
            "text",  "Text (*.txt; *.log; *.md; *.csv; *.ini; *.json; *.xml; *.ahk)")
        if IsObject(accept)
            return ""
        a := StrLower(Trim(String(accept)))
        if named.Has(a)
            return named[a]
        if (a = "" || a = "*" || a = "all" || a = "files")
            return ""
        list := ""
        for e in StrSplit(RegExReplace(a, "[*.,;|]", " "), " ")
            if (Trim(e) != "")
                list .= (list = "" ? "" : "; ") "*." Trim(e)
        return list = "" ? "" : "Selected types (" list ")"
    }

    ; --- WM_DROPFILES fallback --------------------------------------------
    ; Only reached when RegisterDragDrop failed; no hover feedback, drop only.
    _OnDropFiles(hDrop) {
        files := AxWindowDragDrop._QueryDrop(hDrop)
        pt := Buffer(8, 0)
        DllCall("shell32\DragQueryPoint", "Ptr", hDrop, "Ptr", pt)
        p := this._DocScale(NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int"))
        DllCall("shell32\DragFinish", "Ptr", hDrop)
        this._DropCommit(files, p.X, p.Y)
        return 0
    }
    static _QueryDrop(hDrop) {
        files := []
        n := DllCall("shell32\DragQueryFileW", "Ptr", hDrop, "UInt", 0xFFFFFFFF, "Ptr", 0, "UInt", 0, "UInt")
        loop n {
            len := DllCall("shell32\DragQueryFileW", "Ptr", hDrop, "UInt", A_Index - 1, "Ptr", 0, "UInt", 0, "UInt")
            buf := Buffer((len + 1) * 2, 0)
            DllCall("shell32\DragQueryFileW", "Ptr", hDrop, "UInt", A_Index - 1, "Ptr", buf, "UInt", len + 1)
            files.Push(StrGet(buf, "UTF-16"))
        }
        return files
    }

    ; =====================================================================
    ;  IDropTarget by hand: one shared vtable plus a small object per window
    ;  holding [vtable, instance id] — the same shape as the WinRT toast
    ;  event handler in AxSys.ahk.
    ; =====================================================================
    static _DtObject(id) {
        static vt := 0
        if !vt {
            x64 := (A_PtrSize = 8)
            vt := Buffer(7 * A_PtrSize, 0)
            cbs := [CallbackCreate(ObjBindMethod(AxWindowDragDrop, "_Dt_QI"), , 3),
                    CallbackCreate(ObjBindMethod(AxWindowDragDrop, "_Dt_AddRef"), , 1),
                    CallbackCreate(ObjBindMethod(AxWindowDragDrop, "_Dt_Release"), , 1),
                    CallbackCreate(ObjBindMethod(AxWindowDragDrop, "_Dt_Enter"), , x64 ? 5 : 6),
                    CallbackCreate(ObjBindMethod(AxWindowDragDrop, "_Dt_Over"), , x64 ? 4 : 5),
                    CallbackCreate(ObjBindMethod(AxWindowDragDrop, "_Dt_Leave"), , 1),
                    CallbackCreate(ObjBindMethod(AxWindowDragDrop, "_Dt_Drop"), , x64 ? 5 : 6)]
            loop 7
                NumPut("Ptr", cbs[A_Index], vt, (A_Index - 1) * A_PtrSize)
            AxWindowDragDrop._dtVtCbs := cbs
        }
        obj := Buffer(2 * A_PtrSize, 0)
        NumPut("Ptr", vt.Ptr, obj, 0), NumPut("Ptr", id, obj, A_PtrSize)
        return obj
    }
    static _DtWin(pThis) {
        id := NumGet(pThis, A_PtrSize, "Ptr")
        if !AxWindowDragDrop._dt.Has(id)
            return ""
        w := AxWindowDragDrop._dt[id]
        return (IsObject(w) && !w.Closing && IsObject(w.Doc)) ? w : ""
    }
    static _Dt_QI(pThis, riid, ppv) {
        static ok := ["{00000000-0000-0000-C000-000000000046}",      ; IUnknown
                      "{00000122-0000-0000-C000-000000000046}"]      ; IDropTarget
        s := Buffer(80, 0)
        DllCall("ole32\StringFromGUID2", "Ptr", riid, "Ptr", s, "Int", 40)
        g := StrGet(s, "UTF-16")
        for i in ok
            if (i = g) {
                NumPut("Ptr", pThis, ppv)
                return 0
            }
        NumPut("Ptr", 0, ppv)
        return 0x80004002                                            ; E_NOINTERFACE
    }
    static _Dt_AddRef(pThis) => 2
    static _Dt_Release(pThis) => 1
    ; POINTL comes by value: one 8-byte register on x64, two stack slots on x86
    static _Dt_Enter(pThis, pDataObj, keys, a, b, c := 0) {
        pt := AxWindowDragDrop._Pt(a, b, &pEff, c)
        w := AxWindowDragDrop._DtWin(pThis)
        if !w
            return AxWindowDragDrop._SetEffect(pEff, false)
        w._dtFiles := AxWindowDragDrop._FilesFrom(pDataObj)
        return AxWindowDragDrop._Feedback(w, pt.X, pt.Y, pEff)
    }
    static _Dt_Over(pThis, keys, a, b, c := 0) {
        pt := AxWindowDragDrop._Pt(a, b, &pEff, c)
        w := AxWindowDragDrop._DtWin(pThis)
        if !w
            return AxWindowDragDrop._SetEffect(pEff, false)
        return AxWindowDragDrop._Feedback(w, pt.X, pt.Y, pEff)
    }
    static _Dt_Leave(pThis) {
        w := AxWindowDragDrop._DtWin(pThis)
        if w {
            try w._DropClear()
            w._dtFiles := []
        }
        return 0
    }
    static _Dt_Drop(pThis, pDataObj, keys, a, b, c := 0) {
        pt := AxWindowDragDrop._Pt(a, b, &pEff, c)
        w := AxWindowDragDrop._DtWin(pThis)
        if !w
            return AxWindowDragDrop._SetEffect(pEff, false)
        files := AxWindowDragDrop._FilesFrom(pDataObj)
        if !files.Length
            files := w._dtFiles
        w._dtFiles := []
        took := false
        try {
            p := w._DocPoint(pt.X, pt.Y)
            took := w._DropCommit(files, p.X, p.Y, keys)
        }
        return AxWindowDragDrop._SetEffect(pEff, took)
    }
    ; unpack the POINTL arguments and hand back the pdwEffect pointer
    static _Pt(a, b, &pEff, c) {
        if (A_PtrSize = 8) {
            pEff := b
            return {X: AxWindowDragDrop._Signed(a & 0xFFFFFFFF), Y: AxWindowDragDrop._Signed((a >> 32) & 0xFFFFFFFF)}
        }
        pEff := c
        return {X: AxWindowDragDrop._Signed(a & 0xFFFFFFFF), Y: AxWindowDragDrop._Signed(b & 0xFFFFFFFF)}
    }
    static _Signed(v) => (v & 0x80000000) ? v - 0x100000000 : v
    ; Hit-test, paint the hover state and answer with a drop effect.
    static _Feedback(w, sx, sy, pEff) {
        ok := false
        if !w._dtBusy {
            w._dtBusy := true
            try {
                p := w._DocPoint(sx, sy)
                hit := w._DropHit(p.X, p.Y)
                got := w._ZoneFiles(hit, w._dtFiles)
                ok := (hit && got != "" && (hit.Z.Fn || hit.Z.OnEnter)) ? true : false
                w._DropOver(hit, ok, ok ? got : [])
            }
            w._dtBusy := false
        }
        return AxWindowDragDrop._SetEffect(pEff, ok)
    }
    ; DROPEFFECT_COPY (1) or _LINK (4) only: answering _MOVE (2) would tell
    ; the source to delete what the user dragged.
    static _SetEffect(pEff, accept) {
        if !pEff
            return 0
        allowed := NumGet(pEff, "UInt")
        NumPut("UInt", !accept ? 0 : (allowed & 1) ? 1 : (allowed & 4) ? 4 : 0, pEff)
        return 0
    }
    ; CF_HDROP out of the dragged IDataObject
    static _FilesFrom(pDataObj) {
        files := []
        if !pDataObj
            return files
        fe := Buffer(A_PtrSize = 8 ? 32 : 20, 0)          ; FORMATETC
        NumPut("UShort", 15, fe, 0)                       ; cfFormat = CF_HDROP
        NumPut("Ptr", 0, fe, A_PtrSize)                   ; ptd
        off := 2 * A_PtrSize
        NumPut("UInt", 1, fe, off)                        ; dwAspect = DVASPECT_CONTENT
        NumPut("Int", -1, fe, off + 4)                    ; lindex
        NumPut("UInt", 1, fe, off + 8)                    ; tymed = TYMED_HGLOBAL
        stg := Buffer(A_PtrSize = 8 ? 24 : 12, 0)         ; STGMEDIUM
        try {
            if ComCall(3, pDataObj, "Ptr", fe, "Ptr", stg, "Int")      ; IDataObject::GetData
                return files
        } catch
            return files
        hDrop := NumGet(stg, A_PtrSize, "Ptr")
        if hDrop
            files := AxWindowDragDrop._QueryDrop(hDrop)
        try DllCall("ole32\ReleaseStgMedium", "Ptr", stg)
        return files
    }
}
