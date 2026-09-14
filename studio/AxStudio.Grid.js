/* =========================================================================
   AxStudio.Grid.js -- editing data as data.

   Two editors, both run here in the page, where a keystroke costs nothing,
   and hand AutoHotkey the finished text:

   AXG.mountAll()   every <div class="axd-led"> in the inspector becomes a
                    list of rows -- the options of a drop-down, the names of
                    tabs, the colours of a palette -- in place of a text box of
                    "value:Label" lines. Rows are added with Enter, removed
                    with Backspace on an empty row, dragged by their grip,
                    and a block of lines pasted into a cell becomes rows.

   AXG.sheet(o)     a spreadsheet over the studio for a data grid's
                    {Columns: [...], Rows: [...]}: columns with a title, a
                    key, a width, an alignment and a sort; rows with a cell
                    for each. Arrows, Tab and Enter move; a block copied
                    from Excel pastes as cells; Ctrl+Enter keeps it.

   The text is still the truth. Both read it, both write it back, and both
   have "Edit as text" for what they cannot show.
   ========================================================================= */

var AXG = {
    /* ================================================================ lists */
    /* A shape says what a line holds:
         vl   value:Label      (value optional -- blank means the label)
         vlg  value:Label:Glyph
         lg   Label:Glyph
         c    a colour         */
    SHAPES: {
        vl:  { cols: [["l", "Shown as"], ["v", "Value"]], noun: "option" },
        vlg: { cols: [["l", "Shown as"], ["v", "Value"], ["g", "Icon"]], noun: "option" },
        lg:  { cols: [["l", "Name"], ["g", "Icon"]], noun: "tab" },
        c:   { cols: [["c", "Colour"]], noun: "colour" },
        n:   { cols: [["l", "Control"]], noun: "control" },
        st:  { cols: [["l", "Step"]], noun: "step" },
        ld:  { cols: [["l", "Step"], ["v", "A line under it"]], noun: "step" }
    },
    /* a macro step's glyph, from its first word */
    STEPGLYPH: { key: "E765", down: "E74B", up: "E74A", text: "E8D2", wait: "E916", click: "E8B0", dblclick: "E8B0",
                 move: "E7C2", drag: "E7C2", scroll: "EC8F", activate: "E8A7", waitwin: "E823", run: "E768",
                 toast: "E7E7", play: "E768", beep: "E767",
                 "if": "E8AB", "else": "E8AB", otherwise: "E8AB", end: "E73E", stop: "E71A",
                 uiclick: "E8B0", uitype: "E8D2", uiwait: "E823", uiread: "E8C8" },
    stepGlyph: function (line) {
        var w = String(line || "").replace(/^\s+/, "").split(/\s+/)[0].toLowerCase();
        return this.STEPGLYPH[w] || "E76C";
    },
    lists: {},

    mountAll: function () {
        var els = document.querySelectorAll(".axd-led"), i;
        for (i = 0; i < els.length; i++) { this.mount(els[i]); }
        els = document.querySelectorAll(".axd-gridsum");
        for (i = 0; i < els.length; i++) { this.summary(els[i]); }
    },
    summary: function (el) {
        var src = document.getElementById(el.getAttribute("data-field")), say = "", root;
        if (el.getAttribute("data-lv")) {
            /* a list view's text: titles on the first line, a row a line after */
            var lines = (src ? src.value : "").split(/\r?\n/), k, rows = 0, cols = 0;
            for (k = 0; k < lines.length; k++) {
                if (!/\S/.test(lines[k])) { continue; }
                if (!cols) { cols = lines[k].split("|").length; } else { rows++; }
            }
            el.querySelector(".axd-gridsay").innerHTML = "<b>" + cols + " column" + (cols === 1 ? "" : "s") + ", "
                + rows + " row" + (rows === 1 ? "" : "s") + "</b>";
            return;
        }
        try {
            root = this.parse(src ? src.value : "");
            var c = this.get(root, "Columns"), r = this.get(root, "Rows");
            var nc = c instanceof Array ? c.length : 0, nr = r instanceof Array ? r.length : 0;
            say = "<b>" + nc + " column" + (nc === 1 ? "" : "s") + ", " + nr + " row" + (nr === 1 ? "" : "s") + "</b>";
        } catch (e) {
            say = "<b>Code, not a table</b><br><span class=\"axd-dim\">" + this.esc(e.message) + "</span>";
        }
        el.querySelector(".axd-gridsay").innerHTML = say;
    },
    mount: function (host) {
        if (host.getAttribute("data-wired")) { return; }
        var id = host.getAttribute("data-field");
        var src = document.getElementById(id);
        var st = {
            host: host, field: id, shape: host.getAttribute("data-shape") || "vl",
            rows: this.parseLines(src ? src.value : "", host.getAttribute("data-shape") || "vl"),
            text: false, first: true, drag: null
        };
        this.lists[id] = st;
        this.draw(st);
    },
    parseLines: function (text, shape) {
        var out = [], lines = String(text || "").replace(/\r/g, "").split("\n"), i;
        for (i = 0; i < lines.length; i++) {
            if (lines[i].replace(/\s+/g, "") === "") { continue; }
            out.push(this.parseLine(lines[i], shape));
        }
        return out;
    },
    parseLine: function (line, shape) {
        var p = String(line).split(":");
        var r = { v: "", l: "", g: "", c: "" };
        if (shape === "c") { r.c = String(line).replace(/^\s+|\s+$/g, ""); return r; }
        if (shape === "n" || shape === "st") { r.l = String(line).replace(/^\s+|\s+$/g, ""); return r; }
        if (shape === "lg") { r.l = p[0]; r.g = p.length > 1 ? p[1] : ""; return r; }
        if (shape === "ld") { r.l = p[0]; r.v = p.length > 1 ? p.slice(1).join(":") : ""; return r; }
        if (p.length === 1) { r.l = p[0]; return r; }
        r.v = p[0]; r.l = p[1];
        if (shape === "vlg" && p.length > 2) { r.g = p[2]; }
        else if (p.length > 2) { r.l = p.slice(1).join(":"); }
        return r;
    },
    lineOf: function (r, shape) {
        var t = function (s) { return String(s == null ? "" : s).replace(/^\s+|\s+$/g, ""); };
        if (shape === "c") { return t(r.c); }
        if (shape === "n" || shape === "st") { return t(r.l); }
        if (shape === "lg") { return t(r.l) + (t(r.g) ? ":" + t(r.g) : ""); }
        if (shape === "ld") { return t(r.l) + (t(r.v) ? ":" + t(r.v) : ""); }
        var v = t(r.v), l = t(r.l), g = t(r.g);
        if (shape === "vlg") { return (v || l) + ":" + l + (g ? ":" + g : ""); }
        return (v && v !== l) ? v + ":" + l : l;
    },
    textOf: function (st) {
        var out = [], i, line;
        for (i = 0; i < st.rows.length; i++) {
            line = this.lineOf(st.rows[i], st.shape);
            if (line !== "" && line !== ":") { out.push(line); }
        }
        return out.join("\n");
    },
    esc: function (s) {
        return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
            .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    },
    okColour: function (c) { return /^#[0-9a-f]{3}([0-9a-f]{3})?$/i.test(c) || /^[a-z]{3,20}$/i.test(c); },
    okGlyph: function (g) { return /^[0-9a-f]{4,5}$/i.test(g); },

    draw: function (st) {
        var sh = this.SHAPES[st.shape] || this.SHAPES.vl, h = "", i, j, r, k;
        if (st.text) {
            h = '<textarea class="axd-ledtext" data-led-text="1" rows="6" spellcheck="false">'
              + this.esc(this.textOf(st)) + '</textarea>'
              + '<div class="axd-ledfoot"><span class="axd-ledbtn" data-led="list">Back to the list</span></div>';
            st.host.innerHTML = h;
            this.wire(st);
            return;
        }
        h += '<div class="axd-ledhead"><span class="axd-ledgrip"></span>';
        for (j = 0; j < sh.cols.length; j++) {
            h += '<span class="axd-ledc axd-ledc-' + sh.cols[j][0] + '">' + sh.cols[j][1] + '</span>';
        }
        h += '<span class="axd-ledx"></span></div>';
        // a macro's steps: what sits inside an if ... end is drawn in from it
        var depth = 0, w, at;
        for (i = 0; i < st.rows.length; i++) {
            r = st.rows[i];
            w = st.shape === "st" ? String(r.l || "").replace(/^\s+/, "").split(/\s+/)[0].toLowerCase() : "";
            at = (w === "else" || w === "otherwise" || w === "end") ? Math.max(0, depth - 1) : depth;
            h += '<div class="axd-ledrow" data-i="' + i + '"><span class="axd-ledgrip" data-led-grip="' + i
               + '" title="Drag to move it -- or Alt+Up, Alt+Down">&#xE76F;</span>';
            for (j = 0; j < sh.cols.length; j++) {
                k = sh.cols[j][0];
                h += '<span class="axd-ledc axd-ledc-' + k + '">';
                if (k === "c") {
                    h += '<span class="axd-ledsw" style="background:' + (this.okColour(r.c) ? this.esc(r.c) : "transparent") + '"></span>';
                }
                if (k === "g") {
                    h += '<span class="axd-ledglyph">' + (this.okGlyph(r.g) ? "&#x" + r.g + ";" : "") + '</span>';
                }
                if (st.shape === "st") {
                    h += '<span class="axd-ledglyph"' + (at ? ' style="margin-left:' + (at * 18) + 'px"' : '') + '>&#x' + this.stepGlyph(r.l) + ';</span>';
                }
                h += '<input class="axd-ledin" data-i="' + i + '" data-k="' + k + '" value="' + this.esc(r[k])
                   + '" placeholder="' + (k === "v" ? (st.shape === "ld" ? "" : "same") : k === "g" ? "E713" : k === "c" ? "#0078d4" : "")
                   + '" spellcheck="false" autocomplete="off"></span>';
            }
            h += '<span class="axd-ledx" data-led-del="' + i + '" title="Remove it">&#xE711;</span></div>';
            if (w === "if") { depth++; } else if (w === "end" && depth) { depth--; }
        }
        if (!st.rows.length) {
            h += '<div class="axd-ledempty">No ' + sh.noun + 's yet.</div>';
        }
        h += '<div class="axd-ledfoot"><span class="axd-ledbtn axd-ledadd" data-led="add"><span class="ico">&#xE710;</span> Add '
           + (st.rows.length ? "another" : "one") + '</span>'
           + '<span class="axd-ledcount">' + st.rows.length + " " + sh.noun + (st.rows.length === 1 ? "" : "s") + '</span>'
           + (st.shape !== "c" && st.shape !== "n" && st.shape !== "st" && st.shape !== "ld" && st.rows.length > 1 ? '<span class="axd-ledbtn" data-led="sort">Sort</span>' : "")
           + '<span class="axd-ledbtn" data-led="text">Edit as text</span></div>';
        st.host.innerHTML = h;
        this.wire(st);
    },
    wire: function (st) {
        var self = this, host = st.host;
        if (host.getAttribute("data-wired")) { return; }
        host.setAttribute("data-wired", "1");
        host.addEventListener("keydown", function (e) { self.listKey(st, e); }, false);
        host.addEventListener("keyup", function (e) { self.listKeyUp(st, e); }, false);
        host.addEventListener("click", function (e) { self.listClick(st, e); }, false);
        host.addEventListener("paste", function (e) { self.listPaste(st, e); }, false);
        host.addEventListener("mousedown", function (e) { self.listDown(st, e); }, false);
        host.addEventListener("focusout", function () { st.first = true; }, false);
    },
    /* What the rows say now goes to AutoHotkey, which keeps it in the design.
       The first change after the list is drawn, or after it lost the caret,
       is a new step for Undo. */
    commit: function (st) {
        AXD.post("led", { field: st.field, text: this.textOf(st), first: st.first ? 1 : 0 });
        st.first = false;
    },
    focusCell: function (st, i, k, atEnd) {
        var el = st.host.querySelector('input[data-i="' + i + '"][data-k="' + k + '"]');
        if (!el) { return; }
        el.focus();
        try {
            var n = atEnd === false ? 0 : el.value.length;
            el.setSelectionRange(n, n);
        } catch (e) { }
    },
    firstKey: function (st) { return (this.SHAPES[st.shape] || this.SHAPES.vl).cols[0][0]; },
    addRow: function (st, at) {
        var r = { v: "", l: "", g: "", c: "" };
        if (at == null || at > st.rows.length) { at = st.rows.length; }
        st.rows.splice(at, 0, r);
        this.draw(st);
        this.focusCell(st, at, this.firstKey(st));
        this.commit(st);
    },
    delRow: function (st, i, focusPrev) {
        if (i < 0 || i >= st.rows.length) { return; }
        st.rows.splice(i, 1);
        this.draw(st);
        if (focusPrev && st.rows.length) { this.focusCell(st, Math.max(0, i - 1), this.firstKey(st)); }
        this.commit(st);
    },
    moveRow: function (st, i, to) {
        if (to < 0 || to >= st.rows.length || to === i) { return; }
        var r = st.rows.splice(i, 1)[0];
        st.rows.splice(to, 0, r);
        this.draw(st);
        this.commit(st);
    },
    listKey: function (st, e) {
        var t = e.target || e.srcElement, k = e.keyCode;
        if (!t || !t.getAttribute || t.getAttribute("data-i") == null) { return; }
        var i = parseInt(t.getAttribute("data-i"), 10), key = t.getAttribute("data-k");
        var stop = function () { if (e.preventDefault) { e.preventDefault(); } e.returnValue = false; };
        if (e.altKey && (k === 38 || k === 40)) {
            this.moveRow(st, i, i + (k === 40 ? 1 : -1));
            this.focusCell(st, i + (k === 40 ? 1 : -1), key);
            return stop();
        }
        if (k === 13) { this.addRow(st, i + 1); return stop(); }
        if (k === 38 && i > 0) { this.focusCell(st, i - 1, key); return stop(); }
        if (k === 40 && i < st.rows.length - 1) { this.focusCell(st, i + 1, key); return stop(); }
        if (k === 8 && key === this.firstKey(st)) {
            var r = st.rows[i], empty = !r.l && !r.v && !r.g && !r.c;
            if (empty && t.value === "") { this.delRow(st, i, true); return stop(); }
        }
    },
    listKeyUp: function (st, e) {
        var t = e.target || e.srcElement;
        if (t && t.getAttribute && t.getAttribute("data-led-text")) {
            st.rows = this.parseLines(t.value, st.shape);
            this.commit(st);
            return;
        }
        if (!t || !t.getAttribute || t.getAttribute("data-i") == null) { return; }
        var i = parseInt(t.getAttribute("data-i"), 10), key = t.getAttribute("data-k");
        if (!st.rows[i] || st.rows[i][key] === t.value) { return; }
        st.rows[i][key] = t.value;
        /* the swatch and the glyph follow the text, without redrawing the
           row the caret is in */
        var cell = t.parentNode;
        if (key === "c") {
            var sw = cell.querySelector(".axd-ledsw");
            if (sw) { sw.style.background = this.okColour(t.value) ? t.value : "transparent"; }
        }
        if (key === "g") {
            var gl = cell.querySelector(".axd-ledglyph");
            if (gl) { gl.innerHTML = this.okGlyph(t.value) ? "&#x" + t.value + ";" : ""; }
        }
        this.commit(st);
    },
    listClick: function (st, e) {
        var t = e.target || e.srcElement;
        while (t && t !== st.host) {
            if (t.getAttribute) {
                if (t.getAttribute("data-led-del") != null) {
                    return this.delRow(st, parseInt(t.getAttribute("data-led-del"), 10), false);
                }
                var a = t.getAttribute("data-led");
                if (a === "add") { return this.addRow(st); }
                if (a === "text") { st.text = true; return this.draw(st); }
                if (a === "list") { st.text = false; return this.draw(st); }
                if (a === "sort") {
                    st.rows.sort(function (x, y) {
                        var a1 = String(x.l).toLowerCase(), b1 = String(y.l).toLowerCase();
                        return a1 < b1 ? -1 : a1 > b1 ? 1 : 0;
                    });
                    this.draw(st);
                    return this.commit(st);
                }
            }
            t = t.parentNode;
        }
    },
    /* several lines pasted into one cell are several rows */
    listPaste: function (st, e) {
        var t = e.target || e.srcElement, text = "";
        if (!t || !t.getAttribute || t.getAttribute("data-i") == null) { return; }
        try { text = (window.clipboardData || e.clipboardData).getData("Text"); } catch (x) { return; }
        if (!/[\r\n]/.test(text)) { return; }
        if (e.preventDefault) { e.preventDefault(); }
        e.returnValue = false;
        var i = parseInt(t.getAttribute("data-i"), 10), add = this.parseLines(text, st.shape), n;
        var cur = st.rows[i], empty = cur && !cur.l && !cur.v && !cur.g && !cur.c;
        st.rows.splice.apply(st.rows, [empty ? i : i + 1, empty ? 1 : 0].concat(add));
        this.draw(st);
        n = (empty ? i : i + 1) + add.length - 1;
        this.focusCell(st, n, this.firstKey(st));
        this.commit(st);
    },
    /* dragging a row by its grip */
    listDown: function (st, e) {
        var t = e.target || e.srcElement;
        if (!t || !t.getAttribute || t.getAttribute("data-led-grip") == null) { return; }
        var self = this, from = parseInt(t.getAttribute("data-led-grip"), 10), to = from;
        var rows = st.host.querySelectorAll(".axd-ledrow");
        var row = rows[from];
        if (row) { row.className += " axd-leddrag"; }
        var move = function (ev) {
            var y = ev.clientY, j, rc;
            for (j = 0; j < rows.length; j++) {
                rc = rows[j].getBoundingClientRect();
                if (y >= rc.top && y < rc.bottom) { to = j; }
            }
            for (j = 0; j < rows.length; j++) {
                rows[j].className = rows[j].className.replace(/ axd-ledover/g, "")
                    + (j === to && j !== from ? " axd-ledover" : "");
            }
        };
        var up = function () {
            document.removeEventListener("mousemove", move, true);
            document.removeEventListener("mouseup", up, true);
            if (to !== from) { self.moveRow(st, from, to); }
            else { self.draw(st); }
        };
        document.addEventListener("mousemove", move, true);
        document.addEventListener("mouseup", up, true);
        if (e.preventDefault) { e.preventDefault(); }
        e.returnValue = false;
    },

    /* ================================================================ sheet */
    sh: null,

    /* --- AutoHotkey's object literals, the part of them data is written in:
       { Key: value }, [ a, b ], "text" with backtick escapes, numbers, true,
       false. Anything else -- a function call, a variable -- is code, and
       the sheet says so rather than guessing. */
    parse: function (src) {
        var s = String(src), i = 0;
        var fail = function (why) { throw new Error(why + " at character " + (i + 1)); };
        var ws = function () {
            while (i < s.length) {
                var c = s.charAt(i);
                if (c === " " || c === "\t" || c === "\r" || c === "\n") { i++; }
                else if (c === ";" && (i === 0 || /\s/.test(s.charAt(i - 1)))) {
                    while (i < s.length && s.charAt(i) !== "\n") { i++; }
                } else { break; }
            }
        };
        var str = function (q) {
            var out = "";
            i++;
            while (i < s.length) {
                var c = s.charAt(i);
                if (c === "`") {
                    var n = s.charAt(i + 1);
                    out += n === "n" ? "\n" : n === "t" ? "\t" : n === "r" ? "\r" : n;
                    i += 2;
                } else if (c === q) {
                    if (s.charAt(i + 1) === q) { out += q; i += 2; }  /* '' inside '' */
                    else { i++; return out; }
                } else { out += c; i++; }
            }
            fail("a string that does not end");
        };
        var val = function () {
            ws();
            var c = s.charAt(i), m;
            if (c === "{") {
                var o = {}, keys = [];
                i++; ws();
                if (s.charAt(i) === "}") { i++; return { $o: o, $k: keys }; }
                while (true) {
                    ws();
                    m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(s.substr(i));
                    if (!m) { fail("a name was expected"); }
                    i += m[0].length; ws();
                    if (s.charAt(i) !== ":") { fail("a colon was expected"); }
                    i++;
                    o[m[0]] = val(); keys.push(m[0]);
                    ws();
                    if (s.charAt(i) === ",") { i++; continue; }
                    if (s.charAt(i) === "}") { i++; return { $o: o, $k: keys }; }
                    fail("a comma or } was expected");
                }
            }
            if (c === "[") {
                var a = [];
                i++; ws();
                if (s.charAt(i) === "]") { i++; return a; }
                while (true) {
                    a.push(val()); ws();
                    if (s.charAt(i) === ",") { i++; continue; }
                    if (s.charAt(i) === "]") { i++; return a; }
                    fail("a comma or ] was expected");
                }
            }
            if (c === '"' || c === "'") { return str(c); }
            m = /^-?\d+(\.\d+)?/.exec(s.substr(i));
            if (m) { i += m[0].length; return { $n: m[0] }; }
            m = /^(true|false)\b/i.exec(s.substr(i));
            if (m) { i += m[0].length; return { $b: m[0].toLowerCase() === "true" }; }
            fail("this is code, not data");
        };
        var v = val();
        ws();
        if (i < s.length) { fail("more follows the data"); }
        return v;
    },
    /* back to AutoHotkey */
    lit: function (v, pad) {
        var self = this, i, out;
        if (typeof v === "string") {
            return '"' + v.replace(/`/g, "``").replace(/"/g, '`"').replace(/\r?\n/g, "`n").replace(/\t/g, "`t") + '"';
        }
        if (v && v.$n != null) { return v.$n; }
        if (v && v.$b != null) { return v.$b ? "true" : "false"; }
        if (v && v.$o) {
            out = [];
            for (i = 0; i < v.$k.length; i++) { out.push(v.$k[i] + ": " + self.lit(v.$o[v.$k[i]], pad)); }
            return "{" + out.join(", ") + "}";
        }
        if (v instanceof Array) {
            out = [];
            for (i = 0; i < v.length; i++) { out.push(self.lit(v[i], pad)); }
            return "[" + out.join(", ") + "]";
        }
        return '""';
    },
    obj: function () { return { $o: {}, $k: [] }; },
    get: function (o, k) { return (o && o.$o && o.$o.hasOwnProperty(k)) ? o.$o[k] : undefined; },
    set: function (o, k, v) {
        if (!o.$o.hasOwnProperty(k)) { o.$k.push(k); }
        o.$o[k] = v;
    },
    drop: function (o, k) {
        if (!o.$o.hasOwnProperty(k)) { return; }
        delete o.$o[k];
        for (var i = 0; i < o.$k.length; i++) { if (o.$k[i] === k) { o.$k.splice(i, 1); break; } }
    },
    plain: function (v) {
        if (v == null) { return ""; }
        if (typeof v === "string") { return v; }
        if (v.$n != null) { return v.$n; }
        if (v.$b != null) { return v.$b ? "true" : "false"; }
        return this.lit(v, "");
    },
    /* a cell as typed: a number stays a number, anything else is text */
    typed: function (text, was) {
        if (was && was.$n != null && /^-?\d+(\.\d+)?$/.test(text)) { return { $n: text }; }
        if (typeof was !== "string" && /^-?(0|[1-9]\d*)(\.\d+)?$/.test(text)) { return { $n: text }; }
        return text;
    },

    sheet: function (o) {
        var root, why = "";
        try { root = this.parse(o.text || ""); } catch (e) { why = e.message; }
        if (!why && !(root && root.$o)) { why = "the data is not {Columns: [...], Rows: [...]}"; }
        var cols = [], rows = [];
        if (!why) {
            var c = this.get(root, "Columns"), r = this.get(root, "Rows");
            if (c !== undefined && !(c instanceof Array)) { why = "Columns is not a list"; }
            if (r !== undefined && !(r instanceof Array)) { why = "Rows is not a list"; }
            if (!why) {
                cols = c || [];
                rows = r || [];
                for (var i = 0; i < cols.length && !why; i++) { if (!cols[i].$o) { why = "a column is not {Key: ...}"; } }
                for (i = 0; i < rows.length && !why; i++) { if (!rows[i].$o) { why = "a row is not {Key: ...}"; } }
            }
        }
        this.sh = { title: o.title || "Data", text: o.text || "", root: root, cols: cols, rows: rows,
                    why: why, asText: !!why, pop: -1, dirty: false, lv: !!o.lv };
        this.openSheet();
    },
    openSheet: function () {
        var ov = document.getElementById("axgSheet");
        if (!ov) {
            ov = document.createElement("div");
            ov.id = "axgSheet";
            document.body.appendChild(ov);
            var self = this;
            ov.addEventListener("click", function (e) { self.sheetClick(e); }, false);
            ov.addEventListener("keydown", function (e) { self.sheetKey(e); }, false);
            ov.addEventListener("keyup", function (e) { self.sheetKeyUp(e); }, false);
            ov.addEventListener("paste", function (e) { self.sheetPaste(e); }, false);
        }
        ov.style.display = "block";
        this.drawSheet();
        var first = ov.querySelector(".axg-in") || ov.querySelector("textarea");
        if (first) { first.focus(); }
    },
    keyOf: function (c) { var k = this.get(c, "Key"); return k == null ? "" : this.plain(k); },
    drawSheet: function () {
        var S = this.sh, E = this.esc, h = "", i, j, c, r, w, total = 44;
        var ov = document.getElementById("axgSheet");
        var nc = S.cols.length, nr = S.rows.length;
        h += '<div class="axg-card"><div class="axg-head"><span class="axg-title">' + E(S.title) + '</span>'
           + '<span class="axg-sub">' + (S.asText ? "as text" : nc + " column" + (nc === 1 ? "" : "s") + ", "
           + nr + " row" + (nr === 1 ? "" : "s")) + (S.note ? " &#183; " + E(S.note) : "")
           + '</span><span class="axg-sp"></span>';
        if (!S.asText) {
            h += '<span class="axg-btn" data-g="addrow"><span class="ico">&#xE710;</span> Row</span>'
               + '<span class="axg-btn" data-g="addcol"><span class="ico">&#xE710;</span> Column</span>'
               + '<span class="axg-btn" data-g="csv"><span class="ico">&#xE8E5;</span> Import CSV...</span>';
        }
        h += '<span class="axg-btn" data-g="' + (S.asText ? "list" : "text") + '">'
           + (S.asText ? "Back to the table" : "Edit as text") + '</span>'
           + '<span class="axg-btn" data-g="cancel">Cancel</span>'
           + '<span class="axg-btn axg-go" data-g="save">Keep it</span></div>';
        if (S.asText) {
            h += (S.why ? '<div class="axg-why">The table cannot show this: ' + E(S.why)
                 + '. It stays exactly as written; edit it here.</div>' : "")
               + '<textarea class="axg-text" spellcheck="false">' + E(S.text) + '</textarea>';
        } else {
            h += '<div class="axg-gridwrap"><table class="axg-grid"><colgroup><col style="width:44px">';
            for (j = 0; j < nc; j++) {
                w = parseInt(this.plain(this.get(S.cols[j], "Width")), 10);
                w = isNaN(w) ? 140 : Math.max(60, Math.min(420, w));
                total += w;
                h += '<col style="width:' + w + 'px">';
            }
            h += '<col style="width:56px"></colgroup><thead><tr><th class="axg-rn">#</th>';
            for (j = 0; j < nc; j++) {
                c = S.cols[j];
                var al = this.plain(this.get(c, "Align"));
                h += '<th class="axg-th' + (S.pop === j ? " on" : "") + '" data-col="' + j + '">'
                   + '<span class="axg-tht">' + E(this.plain(this.get(c, "Title")) || this.keyOf(c)) + '</span>'
                   + '<span class="axg-thk">' + E(this.keyOf(c)) + (al && al !== "left" ? " &middot; " + E(al) : "") + '</span>'
                   + '<span class="axg-thm" data-g="colmenu" data-col="' + j + '" title="This column">&#xE712;</span></th>';
            }
            h += '<th class="axg-thadd"><span class="axg-btn axg-mini" data-g="addcol" title="Add a column"><span class="ico">&#xE710;</span></span></th></tr></thead><tbody>';
            for (i = 0; i < nr; i++) {
                r = S.rows[i];
                var kids = this.get(r, "Kids");
                h += '<tr><td class="axg-rn" title="Row key: ' + E(this.keyOf(r)) + '">' + (i + 1)
                   + (kids instanceof Array && kids.length ? '<span class="axg-kids" title="' + kids.length
                      + ' rows under it, kept as they are">&#x25B8;' + kids.length + '</span>' : "") + '</td>';
                for (j = 0; j < nc; j++) {
                    var k = this.keyOf(S.cols[j]);
                    var al2 = this.plain(this.get(S.cols[j], "Align"));
                    h += '<td><input class="axg-in' + (al2 === "right" ? " axg-r" : al2 === "center" ? " axg-cen" : "")
                       + '" data-r="' + i + '" data-c="' + j + '" value="' + E(this.plain(this.get(r, k)))
                       + '" spellcheck="false" autocomplete="off"></td>';
                }
                h += '<td class="axg-rowx"><span data-g="delrow" data-r="' + i + '" title="Remove the row">&#xE711;</span></td></tr>';
            }
            h += '</tbody></table>';
            if (!nr) {
                h += '<div class="axg-empty">No rows yet. <span class="axg-btn" data-g="addrow"><span class="ico">&#xE710;</span> Add the first</span>'
                   + ' or paste a block copied from a spreadsheet into the first cell.</div>';
            }
            h += '</div>';
            if (S.pop >= 0 && S.cols[S.pop]) { h += this.colPop(S.pop); }
            h += '<div class="axg-foot">Arrows, Tab and Enter move between cells. Enter on the last row adds one. '
               + 'Paste a block from Excel into a cell. Alt+Up or Down moves a row. Ctrl+Enter keeps it, Escape leaves.</div>';
        }
        h += '</div>';
        ov.innerHTML = h;
    },
    colPop: function (j) {
        var S = this.sh, c = S.cols[j], E = this.esc;
        var al = this.plain(this.get(c, "Align")) || "left", so = this.plain(this.get(c, "Sort"));
        var opt = function (list, cur) {
            var h = "", i;
            for (i = 0; i < list.length; i++) {
                h += '<option value="' + list[i][0] + '"' + (list[i][0] === cur ? " selected" : "") + '>' + list[i][1] + '</option>';
            }
            return h;
        };
        return '<div class="axg-pop"><div class="axg-poptitle">Column ' + (j + 1) + '</div>'
             + '<label>Title</label><input class="axg-pin" data-p="Title" value="' + E(this.plain(this.get(c, "Title"))) + '">'
             + '<label>Key <span class="axg-dim">-- the name each row gives its value under</span></label>'
             + '<input class="axg-pin" data-p="Key" value="' + E(this.keyOf(c)) + '">'
             + '<label>Width</label><input class="axg-pin" data-p="Width" value="' + E(this.plain(this.get(c, "Width"))) + '" placeholder="140">'
             + '<label>Align</label><select class="axg-pin" data-p="Align">'
             + opt([["left", "Left"], ["center", "Centre"], ["right", "Right"]], al) + '</select>'
             + '<label>Sorts as</label><select class="axg-pin" data-p="Sort">'
             + opt([["", "Automatic"], ["text", "Text"], ["number", "Numbers"], ["date", "Dates"], ["false", "Not sortable"]], so) + '</select>'
             + '<div class="axg-popbtns"><span class="axg-btn" data-g="colleft"><span class="ico">&#xE72B;</span></span>'
             + '<span class="axg-btn" data-g="colright"><span class="ico">&#xE72A;</span></span>'
             + '<span class="axg-btn axg-danger" data-g="delcol">Remove the column</span>'
             + '<span class="axg-btn" data-g="popclose">Done</span></div></div>';
    },
    /* keep what is typed in cells before anything redraws */
    readCells: function () {
        var S = this.sh, ov = document.getElementById("axgSheet"), ins, i, el, r, c, k;
        if (!S || S.asText) { return; }
        ins = ov.querySelectorAll(".axg-in");
        for (i = 0; i < ins.length; i++) {
            el = ins[i];
            r = S.rows[parseInt(el.getAttribute("data-r"), 10)];
            c = S.cols[parseInt(el.getAttribute("data-c"), 10)];
            if (!r || !c) { continue; }
            k = this.keyOf(c);
            if (!k) { continue; }
            if (this.plain(this.get(r, k)) !== el.value) {
                this.set(r, k, this.typed(el.value, this.get(r, k)));
            }
        }
    },
    focusGrid: function (r, c) {
        var el = document.querySelector('#axgSheet .axg-in[data-r="' + r + '"][data-c="' + c + '"]');
        if (el) { el.focus(); try { el.select(); } catch (e) { } }
    },
    newKey: function (base) {
        var S = this.sh, n = 1, used = {}, i;
        for (i = 0; i < S.cols.length; i++) { used[this.keyOf(S.cols[i]).toLowerCase()] = true; }
        while (used[(base + n).toLowerCase()]) { n++; }
        return base + n;
    },
    rowKey: function () {
        var S = this.sh, n = S.rows.length + 1, used = {}, i;
        for (i = 0; i < S.rows.length; i++) { used[this.keyOf(S.rows[i])] = true; }
        while (used["r" + n]) { n++; }
        return "r" + n;
    },
    addSheetRow: function (at) {
        var S = this.sh, r = this.obj();
        this.set(r, "Key", this.rowKey());
        S.rows.splice(at == null ? S.rows.length : at, 0, r);
        S.dirty = true;
    },
    sheetClick: function (e) {
        var t = e.target || e.srcElement, S = this.sh, g = "", col = -1, row = -1;
        while (t && t.id !== "axgSheet") {
            if (t.getAttribute && t.getAttribute("data-g")) {
                g = t.getAttribute("data-g");
                if (t.getAttribute("data-col") != null) { col = parseInt(t.getAttribute("data-col"), 10); }
                if (t.getAttribute("data-r") != null) { row = parseInt(t.getAttribute("data-r"), 10); }
                break;
            }
            if (t.getAttribute && t.getAttribute("data-col") != null && !g) {
                col = parseInt(t.getAttribute("data-col"), 10);
                g = "colmenu";
                break;
            }
            t = t.parentNode;
        }
        if (!g) { return; }
        this.readCells();
        switch (g) {
        case "save": return this.save();
        case "csv": return AXD.post("sheetcsv", {});
        case "cancel": return this.close();
        case "text":
            S.text = this.build();
            S.asText = true; S.why = "";
            break;
        case "list":
            var ta = document.querySelector("#axgSheet .axg-text");
            this.sheet({ text: ta ? ta.value : S.text, title: S.title });
            return;
        case "addrow":
            this.addSheetRow();
            this.drawSheet();
            return this.focusGrid(S.rows.length - 1, 0);
        case "delrow":
            S.rows.splice(row, 1); S.dirty = true;
            break;
        case "addcol":
            var c = this.obj(), k = this.newKey("col");
            this.set(c, "Key", k);
            this.set(c, "Title", "Column " + (S.cols.length + 1));
            this.set(c, "Width", { $n: "140" });
            S.cols.push(c); S.pop = S.cols.length - 1; S.dirty = true;
            break;
        case "colmenu":
            S.pop = (S.pop === col) ? -1 : col;
            break;
        case "popclose":
            S.pop = -1;
            break;
        case "delcol":
            S.cols.splice(S.pop, 1); S.pop = -1; S.dirty = true;
            break;
        case "colleft":
        case "colright":
            var to = S.pop + (g === "colleft" ? -1 : 1);
            if (to >= 0 && to < S.cols.length) {
                var moved = S.cols.splice(S.pop, 1)[0];
                S.cols.splice(to, 0, moved); S.pop = to; S.dirty = true;
            }
            break;
        default:
            return;
        }
        this.drawSheet();
    },
    /* the column's own settings, as they are typed */
    sheetKeyUp: function (e) {
        var t = e.target || e.srcElement, S = this.sh;
        if (!t || !t.getAttribute || t.getAttribute("data-p") == null || S.pop < 0) { return; }
        this.popSet(t);
    },
    popSet: function (t) {
        var S = this.sh, c = S.cols[S.pop], p = t.getAttribute("data-p"), v = t.value, i, old, nk;
        if (!c) { return; }
        S.dirty = true;
        if (p === "Key") {
            nk = v.replace(/[^A-Za-z0-9_]/g, "");
            if (/^[0-9]/.test(nk)) { nk = "_" + nk; }
            old = this.keyOf(c);
            if (!nk || nk === old) { return; }
            /* the rows keep their values under the new name */
            for (i = 0; i < S.rows.length; i++) {
                var had = this.get(S.rows[i], old);
                if (had !== undefined) { this.drop(S.rows[i], old); this.set(S.rows[i], nk, had); }
            }
            this.set(c, "Key", nk);
        } else if (p === "Width") {
            if (/^\d+$/.test(v)) { this.set(c, "Width", { $n: v }); } else if (v === "") { this.drop(c, "Width"); }
        } else if (p === "Align") {
            if (v === "left") { this.drop(c, "Align"); } else { this.set(c, "Align", v); }
        } else if (p === "Sort") {
            if (v === "") { this.drop(c, "Sort"); }
            else if (v === "false") { this.set(c, "Sort", { $b: false }); }
            else { this.set(c, "Sort", v); }
        } else {
            this.set(c, p, v);
        }
        /* the header shows it, without taking the caret out of the box */
        var th = document.querySelector('#axgSheet .axg-th[data-col="' + S.pop + '"]');
        if (th) {
            th.querySelector(".axg-tht").innerHTML = this.esc(this.plain(this.get(c, "Title")) || this.keyOf(c));
            th.querySelector(".axg-thk").innerHTML = this.esc(this.keyOf(c));
        }
    },
    sheetKey: function (e) {
        var t = e.target || e.srcElement, k = e.keyCode, S = this.sh;
        var stop = function () {
            if (e.preventDefault) { e.preventDefault(); }
            e.returnValue = false;
            e.cancelBubble = true;
        };
        if (k === 27) { if (S.pop >= 0) { this.readCells(); S.pop = -1; this.drawSheet(); } else { this.close(); } return stop(); }
        if (k === 13 && e.ctrlKey) { this.readCells(); this.save(); return stop(); }
        if (t && t.tagName === "SELECT") { window.setTimeout(function () { AXG.popSet(t); }, 0); return; }
        if (!t || !t.getAttribute || t.getAttribute("data-r") == null) { return; }
        var r = parseInt(t.getAttribute("data-r"), 10), c = parseInt(t.getAttribute("data-c"), 10);
        var nr = S.rows.length, nc = S.cols.length, caret = -1, len = t.value.length;
        try { caret = t.selectionStart; if (t.selectionEnd !== caret) { caret = -1; } } catch (x) { }
        var go = function (rr, cc) { AXG.readCells(); AXG.focusGrid(rr, cc); };
        if (e.altKey && (k === 38 || k === 40)) {
            var to = r + (k === 40 ? 1 : -1);
            if (to >= 0 && to < nr) {
                this.readCells();
                var moved = S.rows.splice(r, 1)[0];
                S.rows.splice(to, 0, moved); S.dirty = true;
                this.drawSheet(); this.focusGrid(to, c);
            }
            return stop();
        }
        if (k === 38) { if (r > 0) { go(r - 1, c); } return stop(); }
        if (k === 40 || k === 13) {
            if (r < nr - 1) { go(r + 1, c); }
            else if (k === 13) { this.readCells(); this.addSheetRow(); this.drawSheet(); this.focusGrid(nr, c); }
            return stop();
        }
        if (k === 9) {
            var cc = c + (e.shiftKey ? -1 : 1), rr = r;
            if (cc >= nc) { cc = 0; rr++; }
            if (cc < 0) { cc = nc - 1; rr--; }
            if (rr >= nr) { this.readCells(); this.addSheetRow(); this.drawSheet(); }
            if (rr >= 0) { this.focusGrid(rr, cc); }
            return stop();
        }
        if (k === 37 && caret === 0 && c > 0) { go(r, c - 1); return stop(); }
        if (k === 39 && caret === len && c < nc - 1) { go(r, c + 1); return stop(); }
        S.dirty = true;
    },
    /* a block copied from a spreadsheet: tabs between cells, lines between rows */
    sheetPaste: function (e) {
        var t = e.target || e.srcElement, S = this.sh, text = "";
        if (!t || !t.getAttribute || t.getAttribute("data-r") == null) { return; }
        try { text = (window.clipboardData || e.clipboardData).getData("Text"); } catch (x) { return; }
        if (!/[\t\r\n]/.test(text)) { return; }
        if (e.preventDefault) { e.preventDefault(); }
        e.returnValue = false;
        this.readCells();
        var r0 = parseInt(t.getAttribute("data-r"), 10), c0 = parseInt(t.getAttribute("data-c"), 10);
        var lines = text.replace(/\r/g, "").replace(/\n+$/, "").split("\n"), i, j, cells, col, k;
        for (i = 0; i < lines.length; i++) {
            cells = lines[i].split("\t");
            while (r0 + i >= S.rows.length) { this.addSheetRow(); }
            for (j = 0; j < cells.length; j++) {
                while (c0 + j >= S.cols.length) {
                    col = this.obj(); k = this.newKey("col");
                    this.set(col, "Key", k); this.set(col, "Title", "Column " + (S.cols.length + 1));
                    S.cols.push(col);
                }
                k = this.keyOf(S.cols[c0 + j]);
                this.set(S.rows[r0 + i], k, this.typed(cells[j], this.get(S.rows[r0 + i], k)));
            }
        }
        S.dirty = true;
        this.drawSheet();
        this.focusGrid(r0 + lines.length - 1, c0);
    },
    /* The rows a data grid's text holds, for the canvas to draw: up to forty,
       each as plain values, as JSON -- or "" when the text is code. */
    rowsJson: function (text) {
        try {
            var root = this.parse(text), r = this.get(root, "Rows"), out = [], i, j, row, o, k;
            if (!(r instanceof Array)) { return ""; }
            for (i = 0; i < r.length && i < 40; i++) {
                row = r[i];
                if (!row || !row.$o) { continue; }
                o = {};
                for (j = 0; j < row.$k.length; j++) {
                    k = row.$k[j];
                    if (k !== "Kids") { o[k] = this.plain(row.$o[k]); }
                }
                out.push(o);
            }
            return JSON.stringify(out);
        } catch (e) { return ""; }
    },
    /* ------------------------------------------------------------ CSV */
    /* Commas, semicolons or tabs -- whichever the first line has most of,
       outside quotes -- and quotes round a value that holds one, with "" for
       a quote inside. A line break inside quotes stays in the value. */
    parseCsv: function (text) {
        var s = String(text).replace(/^\uFEFF/, ""), first = s.split(/\r?\n/)[0] || "", q = false, cnt = { ",": 0, ";": 0, "\t": 0 }, i, c;
        for (i = 0; i < first.length; i++) {
            c = first.charAt(i);
            if (c === '"') { q = !q; } else if (!q && cnt.hasOwnProperty(c)) { cnt[c]++; }
        }
        var sep = cnt["\t"] >= cnt[","] && cnt["\t"] >= cnt[";"] && cnt["\t"] > 0 ? "\t" : (cnt[";"] > cnt[","] ? ";" : ",");
        var rows = [], row = [], cell = "", inq = false;
        for (i = 0; i < s.length; i++) {
            c = s.charAt(i);
            if (inq) {
                if (c === '"') {
                    if (s.charAt(i + 1) === '"') { cell += '"'; i++; } else { inq = false; }
                } else { cell += c; }
            } else if (c === '"') { inq = true; }
            else if (c === sep) { row.push(cell); cell = ""; }
            else if (c === "\n" || c === "\r") {
                if (c === "\r" && s.charAt(i + 1) === "\n") { i++; }
                row.push(cell); cell = "";
                rows.push(row); row = [];
            } else { cell += c; }
        }
        if (cell !== "" || row.length) { row.push(cell); rows.push(row); }
        while (rows.length && rows[rows.length - 1].join("") === "") { rows.pop(); }
        return rows;
    },
    /* a heading as a key a row can carry: letters, digits and _, not first a digit */
    keyFor: function (t, used) {
        var k = String(t).replace(/[^A-Za-z0-9_]+/g, "_").replace(/^_+|_+$/g, "");
        if (!k) { k = "col"; }
        if (/^[0-9]/.test(k)) { k = "c" + k; }
        k = k.charAt(0).toLowerCase() + k.substring(1);
        var base = k, n = 2;
        while (used[k.toLowerCase()]) { k = base + n++; }
        used[k.toLowerCase()] = true;
        return k;
    },
    importCsv: function (o) {
        var S = this.sh, rows = this.parseCsv(o.text || ""), i, j, head, keys = [], used = {}, c, r, k;
        if (!S) { return; }
        if (!rows.length) { S.note = "nothing in " + o.name; return this.drawSheet(); }
        this.readCells();
        if (S.asText || o.how !== "append") { S.cols = []; S.rows = []; S.asText = false; S.why = ""; }
        if (!S.root || !S.root.$o) { S.root = this.obj(); }
        for (i = 0; i < S.cols.length; i++) { used[this.keyOf(S.cols[i]).toLowerCase()] = true; }
        var width = 0;
        for (i = 0; i < rows.length; i++) { width = Math.max(width, rows[i].length); }
        head = o.head ? rows.shift() : [];
        for (j = 0; j < width; j++) {
            var title = (head[j] != null && head[j] !== "") ? head[j] : "Column " + (j + 1), found = -1;
            /* after what is there: a heading that matches a column goes into it */
            for (i = 0; i < S.cols.length && o.how === "append"; i++) {
                var ct = String(this.plain(this.get(S.cols[i], "Title"))).toLowerCase();
                if (ct === String(title).toLowerCase() || this.keyOf(S.cols[i]).toLowerCase() === String(title).toLowerCase()) { found = i; }
            }
            if (found >= 0) { keys.push(this.keyOf(S.cols[found])); continue; }
            k = this.keyFor(title, used);
            c = this.obj();
            this.set(c, "Key", k);
            this.set(c, "Title", String(title));
            this.set(c, "Width", { $n: "140" });
            S.cols.push(c);
            keys.push(k);
        }
        for (i = 0; i < rows.length; i++) {
            r = this.obj();
            this.set(r, "Key", this.rowKey());
            for (j = 0; j < keys.length; j++) { this.set(r, keys[j], this.typed(rows[i][j] != null ? rows[i][j] : "", undefined)); }
            S.rows.push(r);
        }
        S.dirty = true;
        S.note = "imported " + rows.length + " row" + (rows.length === 1 ? "" : "s") + " from " + o.name;
        this.drawSheet();
    },
    build: function () {
        var S = this.sh, root = S.root && S.root.$o ? S.root : this.obj(), i, parts = [], k;
        for (i = 0; i < S.rows.length; i++) {
            if (!this.keyOf(S.rows[i])) {
                /* a row needs a key to be found again; it goes first */
                S.rows[i].$k.unshift("Key");
                S.rows[i].$o.Key = this.rowKey();
            }
        }
        this.set(root, "Columns", S.cols);
        this.set(root, "Rows", S.rows);
        /* Columns and Rows one item to a line, so the script reads as a table */
        for (i = 0; i < root.$k.length; i++) {
            k = root.$k[i];
            var v = root.$o[k];
            if ((k === "Columns" || k === "Rows") && v instanceof Array) {
                var items = [], j;
                for (j = 0; j < v.length; j++) { items.push("    " + this.lit(v[j], "")); }
                parts.push(k + ": [" + (items.length ? "\n" + items.join(",\n") : "") + "]");
            } else {
                parts.push(k + ": " + this.lit(v, ""));
            }
        }
        return "{" + parts.join(",\n  ") + "}";
    },
    save: function () {
        var S = this.sh, text;
        if (S.asText) {
            var ta = document.querySelector("#axgSheet .axg-text");
            text = ta ? ta.value : S.text;
        } else {
            this.readCells();
            text = S.lv ? this.lvText() : this.build();
        }
        AXD.post("sheet", { text: text });
        this.hide();
    },
    /* a list view's own text: the titles, then a row a line, "[x] " ticked */
    lvText: function () {
        var S = this.sh, self = this, lines = [], i, j, cells, t;
        var cell = function (v) { return String(v == null ? "" : self.plain(v)).replace(/\|/g, "/").replace(/[\r\n]+/g, " "); };
        cells = [];
        for (j = 0; j < S.cols.length; j++) {
            t = this.get(S.cols[j], "Title");
            cells.push(cell(t == null ? this.keyOf(S.cols[j]) : t));
        }
        lines.push(cells.join(" | "));
        for (i = 0; i < S.rows.length; i++) {
            cells = [];
            for (j = 0; j < S.cols.length; j++) { cells.push(cell(this.get(S.rows[i], this.keyOf(S.cols[j])))); }
            t = this.get(S.rows[i], "Checked");
            lines.push((t && this.plain(t) !== "0" ? "[x] " : "") + cells.join(" | "));
        }
        return lines.join("\n");
    },
    close: function () {
        AXD.post("sheet", { cancel: 1 });
        this.hide();
    },
    hide: function () {
        var ov = document.getElementById("axgSheet");
        if (ov) { ov.style.display = "none"; ov.innerHTML = ""; }
        this.sh = null;
    }
};
