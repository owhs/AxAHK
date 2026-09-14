/* =========================================================================
   AxRichText.js -- a rich text editor (what you see is what you get) for
   Trident (IE11): a contenteditable page with a toolbar over it.

   Beyond the toolbar:
     - Markdown as you type: "# " a heading (## ###), "- " or "* " a list,
       "1. " a numbered one, "> " a quote, "``` " code, "---" Enter a line;
       **bold**, *italic*, `code` and ~~strike~~ turn into what they say.
     - "/" on an empty line: a menu of what the line can become.
     - Out of a table, a quote, a code block or a list: Ctrl+Enter, or the
       arrow keys past its edge; the page always keeps a line to type on after
       the last of them, and a click under the text lands there.
     - In a table, a small bar over it: rows and columns either side, out of
       it, gone. On a link: change it, or take it off.
     - Ctrl+F / Ctrl+H: find and replace (match case, a pattern).
     - Ctrl+1/2/3 headings, Ctrl+0 a paragraph, Ctrl+Shift+7/8 lists,
       Ctrl+E/L/R/J alignment, Ctrl+` code, Ctrl+K a link, Tab a table's next cell.

   AutoHotkey talks to it through AXRT:
       AXRT.make(id, optionsJson)
       AXRT.call(id, "method", argsJson)   -> a string
   and it talks back by writing a request into #<id>_q and clicking #<id>_req,
   one a turn. The document keeps its own undo: nothing here re-renders it,
   so Trident's Ctrl+Z works as it does anywhere.
   ES5 only.
   ========================================================================= */
(function () {
    if (window.AXRT) { return; }
    function $(id) { return document.getElementById(id); }
    function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
    function stop(e) { if (e.preventDefault) { e.preventDefault(); } e.returnValue = false; e.cancelBubble = true; return false; }
    function up(el, stopAt, test) {
        while (el && el !== stopAt) { if (el.nodeType === 1 && test(el)) { return el; } el = el.parentNode; }
        return null;
    }
    function tag(el) { return el && el.nodeType === 1 ? el.tagName : ""; }
    var BLOCK_RE = /^(P|DIV|H1|H2|H3|H4|H5|H6|PRE|BLOCKQUOTE|LI|TD|TH|UL|OL|TABLE|HR)$/;
    var AXRT = window.AXRT = { inst: {} };
    var BLOCKS = { h1: "<h1>", h2: "<h2>", h3: "<h3>", p: "<p>", pre: "<pre>" };
    var NATIVE = { bold: "bold", italic: "italic", underline: "underline", strike: "strikeThrough", ul: "insertUnorderedList",
                   ol: "insertOrderedList", indent: "indent", outdent: "outdent", left: "justifyLeft", center: "justifyCenter",
                   right: "justifyRight", justify: "justifyFull", unlink: "unlink", hr: "insertHorizontalRule",
                   undo: "undo", redo: "redo", sub: "subscript", sup: "superscript" };
    var STATES = ["bold", "italic", "underline", "strike", "ul", "ol", "sub", "sup"];
    var COLOURS = ["#000000", "#5f6368", "#c00000", "#e36c09", "#b58900", "#2e7d32", "#0070c0", "#6a1b9a", "#ffffff",
                   "#ffe599", "#c9f0c8", "#cfe2f3", "#f4cccc"];
    /* what a line can become, from "/" */
    var SLASH = [
        { cmd: "p", label: "Text", hint: "a plain paragraph" }, { cmd: "h1", label: "Heading 1", hint: "#" },
        { cmd: "h2", label: "Heading 2", hint: "##" }, { cmd: "h3", label: "Heading 3", hint: "###" },
        { cmd: "ul", label: "Bulleted list", hint: "-" }, { cmd: "ol", label: "Numbered list", hint: "1." },
        { cmd: "quote", label: "Quote", hint: ">" }, { cmd: "pre", label: "Code block", hint: "```" },
        { cmd: "table", label: "Table", hint: "rows x columns" }, { cmd: "hr", label: "Line", hint: "---" },
        { cmd: "image", label: "Picture", hint: "a file or a web address" }, { cmd: "link", label: "Link", hint: "Ctrl+K" }];

    function Rt(id, o) {
        this.id = id; this.o = o || {};
        this.root = $(id); this.doc = $(id + "_doc"); this.bar = $(id + "_bar"); this.val = $(id + "_val");
        this.req = $(id + "_req"); this.qdata = $(id + "_q"); this.statEl = $(id + "_stat"); this.askEl = $(id + "_ask");
        this.srcEl = $(id + "_src");
        this.queue = []; this.qTimer = null; this.cTimer = null; this.saved = null; this.pending = null;
        this.hits = []; this.hitAt = -1; this.fo = { cs: false, re: false };
        this.build();
        this.wire();
        this.setReadonly(!!this.o.readonly);
        try { document.execCommand("AutoUrlDetect", false, false); } catch (e) { }
        this.ensureTail();
        this.refresh();
        this.status();
    }
    var P = Rt.prototype;

    P.build = function () {
        var r = this.root, d;
        d = this.ctxEl = document.createElement("div"); d.className = "axrt-ctx"; r.appendChild(d);
        d = this.slashEl = document.createElement("div"); d.className = "axrt-slash"; r.appendChild(d);
        d = this.hitsEl = document.createElement("div"); d.className = "axrt-hits"; r.appendChild(d);
        d = this.findEl = document.createElement("div"); d.className = "axrt-find";
        d.innerHTML = '<input class="axrt-fq" placeholder="Find" spellcheck="false">'
            + '<span data-f="cs" title="Match case">Aa</span><span data-f="re" title="A regular expression">.*</span>'
            + '<span class="axrt-fn"></span>'
            + '<span data-f="prev" title="Previous (Shift+Enter)">&#x2191;</span><span data-f="next" title="Next (Enter)">&#x2193;</span>'
            + '<span data-f="x" title="Close (Esc)">&#x2715;</span>'
            + '<div class="axrt-frep"><input class="axrt-fr" placeholder="Replace with" spellcheck="false">'
            + '<span data-f="one">Replace</span><span data-f="all">All</span></div>';
        r.appendChild(d);
        var ins = d.getElementsByTagName("input");
        this.fq = ins[0]; this.fr = ins[1];
        this.fn = d.getElementsByTagName("span")[2];
    };

    P.wire = function () {
        var self = this, d = this.doc;
        d.addEventListener("keydown", function (e) { self.onKey(e); }, false);
        d.addEventListener("keypress", function (e) { self.onPress(e); }, false);
        d.addEventListener("keyup", function (e) { self.onKeyUp(e); }, false);
        d.addEventListener("mouseup", function () { window.setTimeout(function () { self.refresh(); }, 0); }, false);
        d.addEventListener("mousedown", function (e) { self.hideSlash(); self.clickBelow(e); }, false);
        d.addEventListener("paste", function (e) { self.onPaste(e); }, false);
        d.addEventListener("blur", function () { self.keep(); self.changed(); window.setTimeout(function () { self.hideSlash(); }, 200); }, false);
        d.addEventListener("scroll", function () { self.placeCtx(); if (self.hits.length) { self.drawHits(); } }, false);
        var cmdAt = function (host, e) {
            var t = up(e.target || e.srcElement, host, function (el) { return el.getAttribute && el.getAttribute("data-cmd"); });
            if (!t) { return; }
            self.keep();
            stop(e);
            self.run(t.getAttribute("data-cmd"), t);
        };
        if (this.bar) { this.bar.addEventListener("mousedown", function (e) { cmdAt(self.bar, e); }, false); }
        this.ctxEl.addEventListener("mousedown", function (e) { cmdAt(self.ctxEl, e); }, false);
        this.slashEl.addEventListener("mousedown", function (e) {
            var t = up(e.target || e.srcElement, self.slashEl, function (el) { return el.getAttribute && el.getAttribute("data-i"); });
            if (t) { self.slashPick(parseInt(t.getAttribute("data-i"), 10)); }
            return stop(e);
        }, false);
        var pal = $(this.id + "_pal");
        if (pal) { pal.addEventListener("mousedown", function (e) { cmdAt(pal, e); }, false); }
        if (this.askEl) {
            this.askEl.addEventListener("keydown", function (e) {
                if (e.keyCode === 13) { self.answer(true); return stop(e); }
                if (e.keyCode === 27) { self.answer(false); return stop(e); }
            }, false);
            this.askEl.addEventListener("click", function (e) {
                var t = e.target || e.srcElement, a = t.getAttribute("data-ask");
                if (a === "ok") { self.answer(true); }
                if (a === "no") { self.answer(false); }
            }, false);
        }
        this.wireFind();
        var noFrame = function (e) { if (!self.o.images) { return stop(e); } };
        d.addEventListener("mscontrolselect", noFrame, false);
    };
    P.setReadonly = function (on) {
        this.o.readonly = !!on;
        this.doc.contentEditable = on ? "false" : "true";
        this.root.className = this.root.className.replace(/\s*axrt-ro\b/g, "") + (on ? " axrt-ro" : "");
    };

    /* ----------------------------------------------------------- selection */
    P.inDoc = function (node) { while (node) { if (node === this.doc) { return true; } node = node.parentNode; } return false; };
    P.keep = function () {
        try {
            var s = window.getSelection();
            if (s && s.rangeCount && this.inDoc(s.getRangeAt(0).startContainer)) { this.saved = s.getRangeAt(0).cloneRange(); }
        } catch (e) { }
    };
    P.restore = function () {
        try { this.doc.focus(); } catch (e) { }
        if (!this.saved) { return; }
        try { var s = window.getSelection(); s.removeAllRanges(); s.addRange(this.saved); } catch (e2) { }
    };
    P.range = function () {
        try {
            var s = window.getSelection();
            if (s && s.rangeCount && this.inDoc(s.getRangeAt(0).startContainer)) { return s.getRangeAt(0); }
        } catch (e) { }
        return null;
    };
    P.here = function () {
        var r = this.range();
        if (r) { return r.startContainer; }
        return this.saved ? this.saved.startContainer : null;
    };
    /* the block the caret is in, and the one straight under the page */
    P.block = function (n) {
        var d = this.doc;
        return up(n || this.here(), d, function (el) { return BLOCK_RE.test(el.tagName) && el.tagName !== "UL" && el.tagName !== "OL" && el.tagName !== "TABLE"; });
    };
    P.top = function (n) {
        var d = this.doc;
        n = n || this.here();
        while (n && n.parentNode !== d) { n = n.parentNode; }
        return n;
    };
    P.caretIn = function (el, atEnd) {
        try {
            var r = document.createRange(); r.selectNodeContents(el); r.collapse(!atEnd);
            var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
            this.keep();
        } catch (e) { }
    };
    P.insertHtml = function (html) {
        this.restore();
        var s = window.getSelection(), r;
        if (!s.rangeCount || !this.inDoc(s.getRangeAt(0).startContainer)) {
            r = document.createRange(); r.selectNodeContents(this.doc); r.collapse(false);
        } else { r = s.getRangeAt(0); }
        r.deleteContents();
        var box = document.createElement("div"), frag = document.createDocumentFragment(), last = null;
        box.innerHTML = html;
        while (box.firstChild) { last = frag.appendChild(box.firstChild); }
        r.insertNode(frag);
        if (last) {
            r = document.createRange(); r.setStartAfter(last); r.collapse(true);
            s.removeAllRanges(); s.addRange(r);
        }
        this.keep();
        this.ensureTail();
        this.changed();
    };
    /* the text of a block before and after the caret */
    P.around = function (blk) {
        var r = this.range();
        if (!r || !blk) { return null; }
        try {
            var a = document.createRange(); a.selectNodeContents(blk); a.setEnd(r.startContainer, r.startOffset);
            var b = document.createRange(); b.selectNodeContents(blk); b.setStart(r.endContainer, r.endOffset);
            return { before: a.toString().replace(/\u200B/g, ""), after: b.toString().replace(/\u200B/g, ""), a: a, r: r };
        } catch (e) { return null; }
    };

    /* ---------------------------------------------------- always a way out */
    /* a line to type on after the last table, quote, code block or list, and
       between two tables in a row */
    P.ensureTail = function () {
        var d = this.doc, last = d.lastChild, k, n;
        if (this.o.readonly) { return; }
        while (last && last.nodeType === 3 && !/\S/.test(last.nodeValue)) { last = last.previousSibling; }
        if (!last || /^(TABLE|PRE|BLOCKQUOTE|UL|OL|HR|IMG|H1|H2|H3|H4|H5|H6)$/.test(tag(last))) { this.para(null); }
        for (k = d.firstChild; k; k = k.nextSibling) {
            if (tag(k) !== "TABLE") { continue; }
            n = k.nextSibling;
            while (n && n.nodeType === 3 && !/\S/.test(n.nodeValue)) { n = n.nextSibling; }
            if (tag(n) === "TABLE") { this.para(n); }
        }
    };
    /* a new empty paragraph before `before` (null: at the end) */
    P.para = function (before) {
        var p = document.createElement("p");
        p.innerHTML = "<br>";
        this.doc.insertBefore(p, before);
        return p;
    };
    /* the empty paragraph after (or before) an element, made when there is none */
    P.paraBy = function (el, d) {
        var n = d > 0 ? el.nextSibling : el.previousSibling;
        while (n && n.nodeType === 3 && !/\S/.test(n.nodeValue)) { n = d > 0 ? n.nextSibling : n.previousSibling; }
        if (n && (tag(n) === "P" || tag(n) === "DIV" || /^H\d$/.test(tag(n)))) { return n; }
        return this.para(d > 0 ? el.nextSibling : el);
    };
    /* Ctrl+Enter: out of the table / quote / code / list the caret is in */
    P.exitBlock = function () {
        var t = this.top();
        if (!t) { return false; }
        var p = this.paraBy(t, 1);
        this.caretIn(p);
        this.changed();
        this.refresh();
        return true;
    };
    /* the arrows past a table's first or last row, or past the end of the page */
    P.arrowOut = function (d) {
        var c = this.cell(), t;
        if (c) {
            var tr = c.parentNode, tbl = up(tr, this.doc, function (el) { return el.tagName === "TABLE"; }), rows = tbl.rows;
            if (d > 0 && tr !== rows[rows.length - 1]) { return false; }
            if (d < 0 && tr !== rows[0]) { return false; }
            var ar = this.around(c);
            if (ar && (d > 0 ? /\S/.test(ar.after) && ar.after.indexOf("\n") >= 0 : /\n/.test(ar.before))) { return false; }
            t = this.top(tbl);
            this.caretIn(this.paraBy(t, d), d < 0);
            this.refresh();
            return true;
        }
        if (d > 0) {
            t = this.top();
            if (t && !t.nextSibling && /^(PRE|BLOCKQUOTE|UL|OL)$/.test(tag(t))) {
                var a2 = this.around(t);
                if (a2 && !/\S/.test(a2.after)) { this.caretIn(this.paraBy(t, 1)); this.refresh(); return true; }
            }
        }
        return false;
    };
    P.clickBelow = function (e) {
        var t = e.target || e.srcElement, d = this.doc;
        if (t !== d || this.o.readonly) { return; }
        this.ensureTail();
        var last = d.lastChild;
        while (last && last.nodeType === 3) { last = last.previousSibling; }
        if (!last) { return; }
        var r = last.getBoundingClientRect();
        if (e.clientY > r.bottom) {
            stop(e);
            try { d.focus(); } catch (x) { }
            this.caretIn(tag(last) === "P" && !/\S/.test(last.textContent) ? last : this.paraBy(last, 1));
            this.refresh();
        }
    };

    /* ------------------------------------------------------------- commands */
    P.run = function (cmd, btn) {
        if (this.o.readonly && cmd !== "source" && cmd !== "find") { return; }
        var self = this;
        this.hideSlash();
        if (NATIVE[cmd]) { this.restore(); this.exec(NATIVE[cmd]); }
        else if (BLOCKS[cmd]) { this.restore(); this.setBlock(cmd); }
        else if (cmd === "quote") { this.restore(); this.quote(); }
        else if (cmd === "code") { this.wrapInline("code"); }
        else if (cmd === "clear") { this.restore(); this.exec("removeFormat"); this.exec("unlink"); }
        else if (cmd === "link") {
            var a = this.linkAt();
            this.askFor("Link to", a ? a.getAttribute("href") : "https://", function (v) { if (v) { self.link(v); } });
        } else if (cmd === "image") {
            this.askFor("Picture (a web address or a file)", "", function (v) { if (v) { self.restore(); self.exec("insertImage", v); self.ensureTail(); } });
        } else if (cmd === "table") {
            this.askFor("Rows x columns", "3x3", function (v) {
                var m = /(\d+)\s*[x*, ]\s*(\d+)/i.exec(v || "");
                if (m) { self.table(parseInt(m[1], 10), parseInt(m[2], 10)); }
            });
        } else if (cmd === "color" || cmd === "mark") { this.palette(cmd, btn); }
        else if (/^(rowadd|rowabove|coladd|colleft|rowdel|coldel|tabledel)$/.test(cmd)) { this.tableOp(cmd); }
        else if (cmd === "out") { this.restore(); this.exitBlock(); }
        else if (cmd === "source") { this.toggleSource(); }
        else if (cmd === "find") { this.openFind(false); return; }
        else if (cmd === "replace") { this.openFind(true); return; }
        else if (cmd === "save") { this.post({ kind: "save" }); }
        else if (cmd.indexOf("pick:") === 0) { this.pickColour(cmd.substring(5)); }
        this.keep();
        this.refresh();
        this.changed();
    };
    P.exec = function (c, v) { try { document.execCommand(c, false, v == null ? null : v); } catch (e) { } };
    /* a heading, a paragraph or code for the line -- the same one again makes it a paragraph */
    P.setBlock = function (cmd) {
        var b = this.block(), want = cmd === "p" ? "P" : cmd.toUpperCase();
        if (b && b.parentNode && tag(b.parentNode) === "BLOCKQUOTE" && cmd === "p") { this.quote(); return; }
        if (b && tag(b) === want && cmd !== "p") { want = "P"; cmd = "p"; }
        this.exec("formatBlock", "<" + (cmd === "p" ? "p" : cmd) + ">");
        this.ensureTail();
    };
    /* a quote around the line, or the line out of its quote */
    P.quote = function () {
        this.keep();
        var q = up(this.here(), this.doc, function (el) { return el.tagName === "BLOCKQUOTE"; }), t;
        if (q) {
            while (q.firstChild) { q.parentNode.insertBefore(q.firstChild, q); }
            q.parentNode.removeChild(q);
        } else {
            t = this.top();
            if (!t) { return; }
            if (t.nodeType === 3) { var p = document.createElement("p"); t.parentNode.insertBefore(p, t); p.appendChild(t); t = p; }
            q = document.createElement("blockquote");
            t.parentNode.insertBefore(q, t);
            q.appendChild(t);
        }
        this.restore();
        this.ensureTail();
    };
    P.wrapInline = function (tg) {
        this.restore();
        var s = window.getSelection();
        if (!s.rangeCount) { return; }
        var r = s.getRangeAt(0), text = r.toString();
        var code = up(r.startContainer, this.doc, function (el) { return el.tagName && el.tagName.toLowerCase() === tg; });
        if (code) {                                     /* already in one: take it off */
            var t = document.createTextNode(code.textContent);
            code.parentNode.replaceChild(t, code);
            return;
        }
        this.insertHtml("<" + tg + ">" + esc(text || "code") + "</" + tg + ">&#8203;");
    };
    P.linkAt = function () { return up(this.here(), this.doc, function (el) { return el.tagName === "A"; }); };
    P.link = function (url) {
        var a = this.linkAt();
        if (a) { a.setAttribute("href", url); this.changed(); return; }
        this.restore();
        var s = window.getSelection();
        if (s.rangeCount && s.getRangeAt(0).toString()) { this.exec("createLink", url); }
        else { this.insertHtml('<a href="' + esc(url) + '">' + esc(url) + "</a>&nbsp;"); }
    };
    P.table = function (rows, cols) {
        rows = Math.max(1, Math.min(rows, 50)); cols = Math.max(1, Math.min(cols, 20));
        var h = '<table class="axrt-t" data-new="1"><thead><tr>', i, j;
        for (j = 0; j < cols; j++) { h += "<th>Heading " + (j + 1) + "</th>"; }
        h += "</tr></thead><tbody>";
        for (i = 1; i < rows; i++) {
            h += "<tr>";
            for (j = 0; j < cols; j++) { h += "<td><br></td>"; }
            h += "</tr>";
        }
        h += "</tbody></table><p><br></p>";
        this.insertHtml(h);
        /* the caret in its first cell, ready to type */
        var t = this.doc.querySelector("table[data-new]");
        if (t) {
            t.removeAttribute("data-new");
            if (t.rows[0] && t.rows[0].cells[0]) {
                var r = document.createRange(), s = window.getSelection();
                r.selectNodeContents(t.rows[0].cells[0]);
                s.removeAllRanges(); s.addRange(r);
                this.keep();
            }
        }
        this.refresh();
    };
    P.cell = function () {
        return up(this.here(), this.doc, function (el) { var t = el.tagName; return t === "TD" || t === "TH"; });
    };
    P.tableOp = function (op) {
        var c = this.cell();
        if (!c) { return; }
        var tr = c.parentNode, tbl = up(tr, this.doc, function (el) { return el.tagName === "TABLE"; }), i, idx = c.cellIndex, rows = tbl.rows, focus = null;
        var mk = function (like) {
            var n = document.createElement(like && like.tagName === "TH" ? "th" : "td");
            n.innerHTML = like && like.tagName === "TH" ? "Heading" : "<br>";
            return n;
        };
        if (op === "rowadd" || op === "rowabove") {
            var at = tr.rowIndex + (op === "rowadd" ? 1 : 0);
            var nr = (op === "rowadd" && tr.parentNode.tagName === "THEAD") ? (tbl.tBodies[0] || tbl).insertRow(0) : tbl.insertRow(at);
            for (i = 0; i < tr.cells.length; i++) { var cc = document.createElement(tr.parentNode.tagName === "THEAD" && op === "rowabove" ? "th" : "td"); cc.innerHTML = "<br>"; nr.appendChild(cc); }
            focus = nr.cells[Math.min(idx, nr.cells.length - 1)];
        } else if (op === "rowdel") {
            if (rows.length > 1) { var ri = tr.rowIndex; tbl.deleteRow(ri); var nx = tbl.rows[Math.min(ri, tbl.rows.length - 1)]; focus = nx && nx.cells[Math.min(idx, nx.cells.length - 1)]; }
            else { return this.tableOp("tabledel"); }
        } else if (op === "coladd" || op === "colleft") {
            for (i = 0; i < rows.length; i++) {
                var ref = rows[i].cells[idx], n = mk(ref);
                if (op === "colleft") { rows[i].insertBefore(n, ref || null); }
                else if (ref && ref.nextSibling) { rows[i].insertBefore(n, ref.nextSibling); } else { rows[i].appendChild(n); }
                if (rows[i] === tr) { focus = n; }
            }
        } else if (op === "coldel") {
            if (tr.cells.length > 1) {
                for (i = 0; i < rows.length; i++) { if (rows[i].cells[idx]) { rows[i].deleteCell(idx); } }
                focus = tr.cells[Math.min(idx, tr.cells.length - 1)];
            } else { return this.tableOp("tabledel"); }
        } else if (op === "tabledel") {
            var p = this.paraBy(tbl, 1);
            tbl.parentNode.removeChild(tbl);
            focus = p;
        }
        if (focus) { try { this.doc.focus(); } catch (e) { } this.caretIn(focus, true); }
        this.ensureTail();
        this.refresh();
        this.changed();
    };
    P.palette = function (cmd, btn) {
        var pal = $(this.id + "_pal"), h = "", i;
        if (!pal) { return; }
        if (pal.style.display === "block" && this.palFor === cmd) { pal.style.display = "none"; return; }
        this.palFor = cmd;
        for (i = 0; i < COLOURS.length; i++) {
            h += '<span data-cmd="pick:' + COLOURS[i] + '" style="background:' + COLOURS[i] + '"></span>';
        }
        h += '<span data-cmd="pick:" class="axrt-none" title="None">&#x2715;</span>';
        pal.innerHTML = h;
        pal.style.display = "block";
        var r = btn.getBoundingClientRect(), root = this.root.getBoundingClientRect();
        pal.style.left = Math.round(Math.min(r.left - root.left, root.width - 160)) + "px";
        pal.style.top = Math.round(r.bottom - root.top + 2) + "px";
    };
    P.pickColour = function (c) {
        var pal = $(this.id + "_pal");
        if (pal) { pal.style.display = "none"; }
        this.restore();
        if (this.palFor === "mark") { this.exec("BackColor", c || "transparent"); }
        else { this.exec("foreColor", c || "inherit"); }
        /* the button shows the colour it last gave */
        var b = this.bar && this.bar.querySelector('[data-cmd="' + this.palFor + '"] .bar');
        if (b) { b.style.fill = c || ""; }
    };
    P.toggleSource = function () {
        if (!this.srcEl) { return; }
        var on = this.srcEl.style.display !== "block";
        if (on) { this.srcEl.value = this.pretty(this.html()); this.srcEl.style.display = "block"; this.doc.style.display = "none"; }
        else { this.doc.innerHTML = this.srcEl.value; this.srcEl.style.display = "none"; this.doc.style.display = ""; this.ensureTail(); this.changed(); }
        this.root.className = this.root.className.replace(/\s*axrt-source\b/g, "") + (on ? " axrt-source" : "");
    };
    P.pretty = function (h) { return h.replace(/(<\/(p|h\d|li|tr|table|ul|ol|blockquote|pre)>)/gi, "$1\n"); };

    /* ------------------------------------------------------------ the ask bar */
    P.askFor = function (label, def, fn) {
        if (!this.askEl) { var v = window.prompt(label, def); fn(v); return; }
        this.pending = fn;
        this.askEl.querySelector("label").innerHTML = esc(label);
        var inp = this.askEl.querySelector("input");
        inp.value = def || "";
        this.askEl.style.display = "block";
        try { inp.focus(); inp.select(); } catch (e) { }
    };
    P.answer = function (ok) {
        var fn = this.pending, v = this.askEl.querySelector("input").value;
        this.pending = null;
        this.askEl.style.display = "none";
        this.restore();
        if (fn) { fn(ok ? v : ""); }
        this.refresh();
        this.changed();
    };

    /* ----------------------------------------------------------- the keyboard */
    P.onKey = function (e) {
        var k = e.keyCode, c = e.ctrlKey, sh = e.shiftKey, i;
        if (this.slashOn) {
            if (k === 40 || k === 38) { this.slashMove(k === 40 ? 1 : -1); return stop(e); }
            if (k === 13 || k === 9) { this.slashPick(this.slashAt); return stop(e); }
            if (k === 27) { this.hideSlash(); return stop(e); }
        }
        if (c && k === 83) { this.post({ kind: "save" }); return stop(e); }
        if (c && !sh && k === 70) { this.openFind(false); return stop(e); }
        if (c && !sh && k === 72) { this.openFind(true); return stop(e); }
        if (k === 114) { this.findStep(sh ? -1 : 1); return stop(e); }
        if (k === 27 && this.hits.length) { this.closeFind(); return stop(e); }
        if (this.o.readonly) { return; }
        if (c && !sh && k === 75) { this.keep(); this.run("link"); return stop(e); }
        if (c && !sh && k >= 49 && k <= 51) { this.run("h" + (k - 48)); return stop(e); }
        if (c && !sh && k === 48) { this.run("p"); return stop(e); }
        if (c && sh && k === 55) { this.run("ol"); return stop(e); }
        if (c && sh && k === 56) { this.run("ul"); return stop(e); }
        if (c && sh && k === 88) { this.run("strike"); return stop(e); }
        if (c && !sh && k === 192) { this.run("code"); return stop(e); }
        if (c && !sh && (k === 69 || k === 76 || k === 82 || k === 74)) { this.run(k === 69 ? "center" : k === 76 ? "left" : k === 82 ? "right" : "justify"); return stop(e); }
        if (c && k === 13) { this.exitBlock(); return stop(e); }
        if (k === 9) {                                  /* Tab: the next cell in a table, else indent */
            var cell = this.cell();
            if (cell) {
                var all = up(cell, this.doc, function (el) { return el.tagName === "TABLE"; }).getElementsByTagName("*"), list = [], at = -1;
                for (i = 0; i < all.length; i++) { if (all[i].tagName === "TD" || all[i].tagName === "TH") { list.push(all[i]); } }
                for (i = 0; i < list.length; i++) { if (list[i] === cell) { at = i; } }
                var next = list[at + (sh ? -1 : 1)];
                if (!next && !sh) { this.keep(); this.tableOp("rowadd"); var nr = cell.parentNode.nextSibling; if (nr && nr.cells && nr.cells[0]) { this.caretIn(nr.cells[0]); } return stop(e); }
                if (next) { this.caretIn(next, true); var r0 = this.range(); if (r0) { try { var r1 = document.createRange(); r1.selectNodeContents(next); var s0 = window.getSelection(); s0.removeAllRanges(); s0.addRange(r1); } catch (x) { } } }
                return stop(e);
            }
            this.exec(sh ? "outdent" : "indent");
            return stop(e);
        }
        if (k === 13 && !sh && this.enter()) { return stop(e); }
        if ((k === 40 || k === 38) && !sh && !c && this.arrowOut(k === 40 ? 1 : -1)) { return stop(e); }
    };
    /* Enter: "---" a line, "```" code, out of a heading into a paragraph, and
       an empty line at the end of a quote leaves it */
    P.enter = function () {
        var b = this.block(), ar = this.around(b), t, p;
        if (!b || !ar) { return false; }
        t = ar.before + ar.after;
        if (/^(P|DIV)$/.test(tag(b)) && /^\s*(---|\*\*\*|___)\s*$/.test(t)) {
            var hr = document.createElement("hr");
            b.parentNode.insertBefore(hr, b);
            b.innerHTML = "<br>";
            if (tag(b.parentNode) !== "BLOCKQUOTE" && b.parentNode !== this.doc) { this.doc.insertBefore(hr, this.top(b)); }
            this.caretIn(b);
            this.changed();
            return true;
        }
        if (/^(P|DIV)$/.test(tag(b)) && /^\s*```\w*\s*$/.test(t)) {
            b.innerHTML = "<br>";
            this.caretIn(b);
            this.exec("formatBlock", "<pre>");
            this.ensureTail();
            this.changed();
            return true;
        }
        if (/^H[1-6]$/.test(tag(b)) && !/\S/.test(ar.after)) {
            p = document.createElement("p"); p.innerHTML = "<br>";
            b.parentNode.insertBefore(p, b.nextSibling);
            this.caretIn(p);
            this.changed();
            this.refresh();
            return true;
        }
        var q = b.parentNode;
        if (tag(q) === "BLOCKQUOTE" && !/\S/.test(t) && b === q.lastChild && q.childNodes.length > 1) {
            q.parentNode.insertBefore(b, q.nextSibling);
            this.caretIn(b);
            this.changed();
            this.refresh();
            return true;
        }
        return false;
    };
    P.onPress = function (e) {
        if (this.o.readonly) { return; }
        var code = e.charCode || e.keyCode, ch = String.fromCharCode(code), self = this;
        if (e.ctrlKey && !e.altKey) { return; }
        if (ch === " " && this.autoBlock()) { return stop(e); }
        if (ch === "/") {
            var b = this.block(), ar = this.around(b);
            if (b && ar && !/\S/.test(ar.before + ar.after) && !this.cell() && tag(b) !== "PRE") {
                this.slashBlock = b;
                window.setTimeout(function () { self.slashShow(); }, 0);
            }
        }
        if (ch === "*" || ch === "`" || ch === "~" || ch === "_") { window.setTimeout(function () { self.autoInline(); }, 0); }
    };
    P.onKeyUp = function (e) {
        var k = e.keyCode;
        if (this.slashOn && k !== 38 && k !== 40 && k !== 13 && k !== 27) { this.slashFilter(); }
        this.refresh();
        if (!((k >= 33 && k <= 40) || k === 16 || k === 17 || k === 18)) { this.changed(); }
        if (k === 13 || k === 8 || k === 46) { this.ensureTail(); }
    };
    /* "# " "- " "1. " "> " "``` " at the start of a line */
    P.autoBlock = function () {
        var b = this.block(), ar = this.around(b), m, cmd = "";
        if (!b || !ar || /^(PRE|TD|TH)$/.test(tag(b))) { return false; }
        var s = ar.before;
        if ((m = /^(#{1,3})$/.exec(s))) { cmd = "h" + m[1].length; }
        else if (/^[-*+]$/.test(s) && tag(b) !== "LI") { cmd = "ul"; }
        else if (/^1[.)]$/.test(s) && tag(b) !== "LI") { cmd = "ol"; }
        else if (s === ">") { cmd = "quote"; }
        else if (s === "```") { cmd = "pre"; }
        if (!cmd) { return false; }
        try { ar.a.deleteContents(); } catch (e) { }
        if (!/\S/.test(b.textContent) && !b.getElementsByTagName("br").length) { b.innerHTML = "<br>"; this.caretIn(b); }
        if (cmd === "ul" || cmd === "ol") { this.exec(NATIVE[cmd]); }
        else if (cmd === "quote") { this.quote(); }
        else { this.exec("formatBlock", "<" + cmd + ">"); }
        this.ensureTail();
        this.refresh();
        this.changed();
        return true;
    };
    /* **bold** *italic* `code` ~~strike~~, just closed */
    P.autoInline = function () {
        var r = this.range();
        if (!r || !r.collapsed) { return; }
        var n = r.startContainer, off = r.startOffset;
        /* a caret between nodes: the text just before it */
        if (n.nodeType === 1 && off > 0 && n.childNodes[off - 1] && n.childNodes[off - 1].nodeType === 3) { n = n.childNodes[off - 1]; off = n.nodeValue.length; }
        if (n.nodeType !== 3) { return; }
        var text = n.nodeValue.substring(0, off), m, tg = "", start = 0, inner = "";
        if (up(n, this.doc, function (el) { return el.tagName === "CODE" || el.tagName === "PRE"; })) { return; }
        if ((m = /`([^`]+)`$/.exec(text))) { tg = "code"; start = m.index; inner = m[1]; }
        else if ((m = /(\*\*|__)([^*_]+)\1$/.exec(text))) { tg = "b"; start = m.index; inner = m[2]; }
        else if ((m = /~~([^~]+)~~$/.exec(text))) { tg = "s"; start = m.index; inner = m[1]; }
        else if ((m = /(^|[^*\w])\*([^*\s][^*]*)\*$/.exec(text)) || (m = /(^|[^_\w])_([^_\s][^_]*)_$/.exec(text))) { tg = "i"; start = m.index + m[1].length; inner = m[2]; }
        if (!tg || !/\S/.test(inner)) { return; }
        var after = n.nodeValue.substring(off);
        n.nodeValue = text.substring(0, start);
        var el = document.createElement(tg);
        el.appendChild(document.createTextNode(inner));
        var tail = document.createTextNode("\u200B" + after);
        n.parentNode.insertBefore(el, n.nextSibling);
        n.parentNode.insertBefore(tail, el.nextSibling);
        try {
            var r2 = document.createRange(); r2.setStart(tail, 1); r2.collapse(true);
            var s = window.getSelection(); s.removeAllRanges(); s.addRange(r2);
        } catch (e) { }
        this.keep();
        this.refresh();
        this.changed();
    };
    P.onPaste = function (e) {
        var self = this;
        if (!this.o.pastePlain) { window.setTimeout(function () { self.tidy(); self.ensureTail(); self.changed(); }, 0); return; }
        var t = "";
        try { t = window.clipboardData.getData("Text"); } catch (err) { }
        if (!t) { return; }
        stop(e);
        var paras = String(t).replace(/\r\n/g, "\n").split(/\n{2,}/), h = "", i;
        for (i = 0; i < paras.length; i++) { h += (paras.length > 1 ? "<p>" : "") + esc(paras[i]).replace(/\n/g, "<br>") + (paras.length > 1 ? "</p>" : ""); }
        this.insertHtml(h);
    };
    /* what a paste from Word or a web page brings along that the page does not want */
    P.tidy = function () {
        var d = this.doc, junk = d.querySelectorAll("style, meta, link, script, xml, title"), i, all, el, st;
        for (i = junk.length - 1; i >= 0; i--) { junk[i].parentNode.removeChild(junk[i]); }
        all = d.getElementsByTagName("*");
        for (i = all.length - 1; i >= 0; i--) {
            el = all[i];
            if (/^o:p$/i.test(el.tagName) || el.tagName.indexOf(":") > 0) { el.parentNode.removeChild(el); continue; }
            if (el.className && /\bMso|\bxl\d/.test(el.className)) { el.removeAttribute("class"); }
            el.removeAttribute("lang");
            st = el.getAttribute("style");
            if (st && /mso-|font-family|font-size|line-height|margin/i.test(st)) {
                st = st.split(";").filter(function (x) { return x && !/^\s*(mso-|font-family|font-size|line-height|margin|tab-stops|text-indent)/i.test(x); }).join(";");
                if (st) { el.setAttribute("style", st); } else { el.removeAttribute("style"); }
            }
        }
    };

    /* ------------------------------------------------------------ the "/" menu */
    P.slashShow = function () {
        this.slashOn = true;
        this.slashFilter();
    };
    P.slashFilter = function () {
        var b = this.slashBlock, t = b ? (b.textContent || "").replace(/\u200B/g, "") : "";
        if (!b || !this.inDoc(b) || t.charAt(0) !== "/" || /\s/.test(t) || t.length > 16) { return this.hideSlash(); }
        var q = t.substring(1).toLowerCase(), out = [], i, h = [];
        for (i = 0; i < SLASH.length; i++) {
            var l = SLASH[i].label.toLowerCase();
            if (!q || l.indexOf(q) >= 0 || SLASH[i].cmd.indexOf(q) === 0) { out.push(SLASH[i]); }
        }
        if (!out.length) { return this.hideSlash(); }
        this.slashItems = out;
        this.slashAt = 0;
        for (i = 0; i < out.length; i++) {
            h.push('<div data-i="' + i + '"' + (i === 0 ? ' class="on"' : "") + ">" + esc(out[i].label) + "<span>" + esc(out[i].hint) + "</span></div>");
        }
        var el = this.slashEl, r = b.getBoundingClientRect(), root = this.root.getBoundingClientRect();
        el.innerHTML = h.join("");
        el.style.display = "block";
        var y = r.bottom - root.top + 2;
        if (y + el.offsetHeight > root.height) { y = Math.max(0, r.top - root.top - el.offsetHeight - 2); }
        el.style.left = Math.round(Math.max(4, r.left - root.left)) + "px";
        el.style.top = Math.round(y) + "px";
    };
    P.slashMove = function (d) {
        var k = this.slashEl.childNodes, n = this.slashItems.length;
        if (k[this.slashAt]) { k[this.slashAt].className = ""; }
        this.slashAt = (this.slashAt + d + n) % n;
        if (k[this.slashAt]) { k[this.slashAt].className = "on"; }
    };
    P.slashPick = function (i) {
        var it = this.slashItems && this.slashItems[i], b = this.slashBlock;
        this.hideSlash();
        if (!it || !b) { return; }
        b.innerHTML = "<br>";
        try { this.doc.focus(); } catch (e) { }
        this.caretIn(b);
        this.run(it.cmd);
    };
    P.hideSlash = function () { this.slashOn = false; if (this.slashEl) { this.slashEl.style.display = "none"; } };

    /* ------------------------------------------------------------ the state */
    P.refresh = function () {
        this.keep();
        if (this.bar) {
            var i, b, on, blk = this.block(), bt = tag(blk), inQuote = !!up(blk, this.doc, function (el) { return el.tagName === "BLOCKQUOTE"; });
            var set = function (bar, name, v) {
                var el = bar.querySelector('[data-cmd="' + name + '"]');
                if (el) { el.className = el.className.replace(/\s*\bon\b/g, "") + (v ? " on" : ""); }
            };
            for (i = 0; i < STATES.length; i++) {
                on = false;
                try { on = document.queryCommandState(NATIVE[STATES[i]]); } catch (e) { }
                set(this.bar, STATES[i], on);
            }
            set(this.bar, "h1", bt === "H1"); set(this.bar, "h2", bt === "H2"); set(this.bar, "h3", bt === "H3");
            set(this.bar, "p", bt === "P" && !inQuote); set(this.bar, "pre", bt === "PRE"); set(this.bar, "quote", inQuote);
            set(this.bar, "code", !!up(this.here(), this.doc, function (el) { return el.tagName === "CODE"; }));
            set(this.bar, "link", !!this.linkAt());
            /* one alignment, from how the line is laid out */
            var al = "";
            try { if (blk) { al = (blk.currentStyle || window.getComputedStyle(blk)).textAlign; } } catch (e2) { }
            al = al === "center" ? "center" : al === "right" || al === "end" ? "right" : al === "justify" ? "justify" : "left";
            set(this.bar, "left", al === "left"); set(this.bar, "center", al === "center");
            set(this.bar, "right", al === "right"); set(this.bar, "justify", al === "justify");
        }
        var inTable = !!this.cell();
        this.root.className = this.root.className.replace(/\s*axrt-intable\b/g, "") + (inTable ? " axrt-intable" : "");
        this.showCtx();
    };
    /* the small bar by a table or a link the caret is in */
    P.showCtx = function () {
        if (this.o.readonly || !this.range()) { this.ctxEl.style.display = "none"; this.ctxFor = null; return; }
        var c = this.cell(), a = this.linkAt(), h = "";
        if (c) {
            this.ctxFor = up(c, this.doc, function (el) { return el.tagName === "TABLE"; });
            h = '<span data-cmd="rowabove" title="A row above">&#x2191; Row</span><span data-cmd="rowadd" title="A row below (Tab in the last cell)">&#x2193; Row</span>'
              + '<span data-cmd="colleft" title="A column to the left">&#x2190; Column</span><span data-cmd="coladd" title="A column to the right">&#x2192; Column</span>'
              + '<i></i><span data-cmd="rowdel" title="This row gone">&#x2212; Row</span><span data-cmd="coldel" title="This column gone">&#x2212; Column</span>'
              + '<i></i><span data-cmd="out" title="Carry on writing under the table (Ctrl+Enter)">&#x21B5; Text after</span>'
              + '<span data-cmd="tabledel" class="axrt-danger" title="The whole table gone">Delete table</span>';
        } else if (a) {
            this.ctxFor = a;
            var href = a.getAttribute("href") || "";
            h = '<b title="' + esc(href) + '">' + esc(href.length > 40 ? href.substring(0, 38) + "\u2026" : href) + "</b>"
              + '<span data-cmd="link" title="Change the address (Ctrl+K)">Edit</span><span data-cmd="unlink" title="Plain text again">Remove</span>';
        } else {
            var t = this.top();
            if (t && /^(PRE|BLOCKQUOTE)$/.test(tag(t))) {
                this.ctxFor = t;
                h = '<span data-cmd="out" title="Carry on writing under it (Ctrl+Enter)">&#x21B5; Text after</span>'
                  + (tag(t) === "BLOCKQUOTE" ? '<span data-cmd="quote" title="Take the quote off this line">Unquote</span>' : '<span data-cmd="p" title="Plain text again">Not code</span>');
            }
        }
        if (!h) { this.ctxEl.style.display = "none"; this.ctxFor = null; return; }
        if (h !== this.ctxHtml) { this.ctxEl.innerHTML = h; this.ctxHtml = h; }
        this.ctxEl.style.display = "block";
        this.placeCtx();
    };
    P.placeCtx = function () {
        var el = this.ctxFor;
        if (!el || this.ctxEl.style.display === "none") { return; }
        var r = el.getBoundingClientRect(), root = this.root.getBoundingClientRect(), dr = this.doc.getBoundingClientRect(), H = this.ctxEl.offsetHeight;
        var y = r.top - root.top - H - 4;
        if (r.top - H - 4 < dr.top) { y = r.bottom - root.top + 4; }
        if (y + H > dr.bottom - root.top || r.bottom < dr.top) { y = Math.max(dr.top - root.top + 2, Math.min(y, dr.bottom - root.top - H - 2)); }
        var x = Math.max(dr.left - root.left + 4, Math.min(r.left - root.left, root.width - this.ctxEl.offsetWidth - 6));
        this.ctxEl.style.left = Math.round(x) + "px";
        this.ctxEl.style.top = Math.round(y) + "px";
    };
    // The placeholder: shown while there are no words, no picture and no
    // table. :empty cannot say that -- the page always keeps a paragraph to
    // type into (ensureTail), so the document is never really empty.
    P.markBlank = function () {
        var d = this.doc;
        if (!d) { return; }
        var blank = !/\S/.test(d.innerText || "") && !d.querySelector("img,table,hr");
        var c = (" " + d.className + " ").replace(" axrt-blank ", " ").replace(/^\s+|\s+$/g, "");
        d.className = blank ? c + " axrt-blank" : c;
    };
    P.status = function () {
        this.markBlank();
        if (!this.statEl) { return; }
        var t = this.text(), words = (t.match(/\S+/g) || []).length;
        this.statEl.innerHTML = words + " word" + (words === 1 ? "" : "s") + " &middot; " + t.replace(/\s/g, "").length + " characters"
            + '<span class="axrt-keys">Ctrl+Enter out of a table or block &middot; "/" on an empty line &middot; Ctrl+F find</span>';
    };
    P.changed = function () {
        var self = this;
        this.markBlank();
        if (this.cTimer) { window.clearTimeout(this.cTimer); }
        this.cTimer = window.setTimeout(function () {
            self.cTimer = null;
            self.ensureTail();
            var v = self.value();
            self.status();
            if (self.hits.length || (self.findOn && self.fq.value)) { self.findRun(true); }
            if (v === self.sent) { return; }
            self.sent = v;
            self.val.value = v;
            self.post({ kind: "change" });
        }, this.o.changeDelay || 300);
    };

    /* ---------------------------------------------------------------- find */
    P.wireFind = function () {
        var self = this, f = this.findEl;
        f.addEventListener("mousedown", function (e) {
            var t = up(e.target || e.srcElement, f, function (el) { return el.getAttribute && el.getAttribute("data-f"); });
            if (!t) { return; }
            var a = t.getAttribute("data-f");
            if (a === "next") { self.findStep(1); } else if (a === "prev") { self.findStep(-1); }
            else if (a === "one") { self.replaceOne(); } else if (a === "all") { self.replaceAll(); }
            else if (a === "x") { self.closeFind(); }
            else { self.fo[a] = !self.fo[a]; t.className = self.fo[a] ? "on" : ""; self.findRun(); }
            return stop(e);
        }, false);
        var keys = function (e, rep) {
            var k = e.keyCode;
            if (k === 27) { self.closeFind(); return stop(e); }
            if (k === 13) { if (rep) { self.replaceOne(); } else { self.findStep(e.shiftKey ? -1 : 1); } return stop(e); }
            if (e.ctrlKey && k === 72) { self.root.className += " axrt-replacing"; try { self.fr.focus(); } catch (x) { } return stop(e); }
        };
        this.fq.addEventListener("keydown", function (e) { return keys(e, false); }, false);
        this.fr.addEventListener("keydown", function (e) { return keys(e, true); }, false);
        this.fq.addEventListener("keyup", function (e) { if (e.keyCode !== 13 && e.keyCode !== 27) { self.findRun(); } }, false);
    };
    P.openFind = function (rep) {
        this.keep();
        var r = this.range(), s = r ? r.toString() : "";
        this.findOn = true;
        this.root.className = this.root.className.replace(/\s*axrt-(finding|replacing)\b/g, "") + " axrt-finding" + (rep && !this.o.readonly ? " axrt-replacing" : "");
        if (s && s.length < 80 && s.indexOf("\n") < 0) { this.fq.value = s; }
        try { this.fq.focus(); this.fq.select(); } catch (e) { }
        this.hitAt = -1;
        this.findRun();
    };
    P.closeFind = function () {
        var h = this.hits[this.hitAt];
        this.findOn = false;
        this.root.className = this.root.className.replace(/\s*axrt-(finding|replacing)\b/g, "");
        this.hits = []; this.hitAt = -1;
        this.hitsEl.innerHTML = "";
        try { this.doc.focus(); } catch (e) { }
        if (h) { try { var s = window.getSelection(); s.removeAllRanges(); s.addRange(h.r); } catch (e2) { } }
        else { this.restore(); }
        this.refresh();
    };
    /* the page's text in order, with where each piece lives */
    P.flat = function () {
        var segs = [], text = "", d = this.doc;
        var walk = function (el) {
            var k = el.childNodes, i, c;
            for (i = 0; i < k.length; i++) {
                c = k[i];
                if (c.nodeType === 3) { segs.push({ n: c, s: text.length }); text += c.nodeValue; }
                else if (c.nodeType === 1) {
                    if (BLOCK_RE.test(c.tagName) || c.tagName === "BR" || c.tagName === "TR") { if (text && text.charAt(text.length - 1) !== "\n") { text += "\n"; } }
                    if (c.tagName !== "BR") { walk(c); }
                }
            }
        };
        walk(d);
        return { text: text, segs: segs };
    };
    P.placeOf = function (f, at, end) {
        var i, s, lo = 0, hi = f.segs.length - 1, best = 0;
        while (lo <= hi) { i = (lo + hi) >> 1; if (f.segs[i].s <= at) { best = i; lo = i + 1; } else { hi = i - 1; } }
        s = f.segs[best];
        if (!s) { return null; }
        var len = s.n.nodeValue.length;
        if (end && at - s.s === 0 && best > 0) { s = f.segs[best - 1]; return { n: s.n, o: s.n.nodeValue.length }; }
        return { n: s.n, o: Math.max(0, Math.min(len, at - s.s)) };
    };
    P.findRun = function (keep) {
        var q = this.fq.value, f, re, m, hits = [];
        this.hits = [];
        if (!keep) { this.hitAt = -1; }
        this.fn.className = "axrt-fn";
        if (!q) { this.fn.innerHTML = ""; this.hitsEl.innerHTML = ""; return; }
        try { re = new RegExp(this.fo.re ? q : q.replace(/[.*+?^${}()|[\]\\\/]/g, "\\$&"), "g" + (this.fo.cs ? "" : "i")); }
        catch (e) { this.fn.innerHTML = "not a pattern"; this.fn.className = "axrt-fn bad"; return; }
        f = this.flat();
        while ((m = re.exec(f.text)) && hits.length < 3000) {
            if (!m[0].length) { re.lastIndex++; continue; }
            var a = this.placeOf(f, m.index, false), b = this.placeOf(f, m.index + m[0].length, true);
            if (!a || !b) { continue; }
            try { var r = document.createRange(); r.setStart(a.n, a.o); r.setEnd(b.n, b.o); hits.push({ r: r, t: m[0], m: m }); } catch (x) { }
        }
        this.hits = hits;
        if (this.hitAt >= hits.length) { this.hitAt = hits.length - 1; }
        this.findCount();
        this.drawHits();
    };
    P.findCount = function () {
        var n = this.hits.length;
        this.fn.innerHTML = n ? (this.hitAt >= 0 ? (this.hitAt + 1) + " of " + n : n + " found") : "No results";
        this.fn.className = n ? "axrt-fn" : "axrt-fn none";
    };
    P.drawHits = function () {
        var h = [], i, j, rs, x, dr = this.doc.getBoundingClientRect(), root = this.root.getBoundingClientRect(), box = this.hitsEl;
        box.style.left = Math.round(dr.left - root.left) + "px"; box.style.top = Math.round(dr.top - root.top) + "px";
        box.style.width = Math.round(dr.width) + "px"; box.style.height = Math.round(dr.height) + "px";
        for (i = 0; i < this.hits.length && i < 600; i++) {
            try { rs = this.hits[i].r.getClientRects(); } catch (e) { continue; }
            for (j = 0; j < rs.length; j++) {
                x = rs[j];
                if (x.bottom < dr.top || x.top > dr.bottom) { continue; }
                h.push('<div class="' + (i === this.hitAt ? "on" : "") + '" style="left:' + Math.round(x.left - dr.left) + "px;top:" + Math.round(x.top - dr.top)
                    + "px;width:" + Math.max(3, Math.round(x.width)) + "px;height:" + Math.round(x.height) + 'px"></div>');
            }
        }
        box.innerHTML = h.join("");
    };
    P.findStep = function (d) {
        if (!this.hits.length) { this.findRun(); }
        var n = this.hits.length;
        if (!n) { return; }
        this.hitAt = this.hitAt < 0 ? (d > 0 ? 0 : n - 1) : (this.hitAt + d + n) % n;
        var r = this.hits[this.hitAt].r.getBoundingClientRect(), dr = this.doc.getBoundingClientRect();
        if (r.top < dr.top + 10 || r.bottom > dr.bottom - 10) { this.doc.scrollTop += r.top - dr.top - dr.height / 3; }
        this.findCount();
        this.drawHits();
    };
    P.replaceOne = function () {
        if (this.o.readonly) { return; }
        if (this.hitAt < 0) { return this.findStep(1); }
        var h = this.hits[this.hitAt], by = this.fr.value, at = this.hitAt;
        if (this.fo.re) { by = h.t.replace(new RegExp(this.fq.value, this.fo.cs ? "" : "i"), by); }
        try { h.r.deleteContents(); h.r.insertNode(document.createTextNode(by)); } catch (e) { }
        this.findRun(true);
        this.hitAt = Math.min(at, this.hits.length - 1);
        this.findCount();
        this.drawHits();
        this.changed();
    };
    P.replaceAll = function () {
        if (this.o.readonly || !this.hits.length) { this.findRun(); }
        var i, n = this.hits.length, by = this.fr.value, h;
        for (i = n - 1; i >= 0; i--) {
            h = this.hits[i];
            var t = this.fo.re ? h.t.replace(new RegExp(this.fq.value, this.fo.cs ? "" : "i"), by) : by;
            try { h.r.deleteContents(); h.r.insertNode(document.createTextNode(t)); } catch (e) { }
        }
        this.findRun();
        this.fn.innerHTML = n + " replaced";
        this.changed();
    };

    /* ------------------------------------------------------------ the output */
    P.html = function () {
        var h = this.doc.innerHTML;
        h = h.replace(/&#8203;|\u200B/g, "");
        if (/^\s*(<p>(<br>|&nbsp;|\s)*<\/p>\s*)*$/i.test(h)) { return ""; }
        return h.replace(/(\s*<p>(\s|&nbsp;|<br>)*<\/p>)+\s*$/i, "");
    };
    P.text = function () { return String(this.doc.innerText || this.doc.textContent || "").replace(/\u200B/g, ""); };
    P.value = function () {
        var f = this.o.format || "html";
        return f === "md" ? this.markdown() : f === "text" ? this.text() : this.html();
    };
    P.markdown = function () { return mdOf(this.doc).replace(/\n{3,}/g, "\n\n").replace(/^\s+|\s+$/g, ""); };

    function inl(node) {
        var out = "", k, i, t, tg, inner;
        for (i = 0; i < node.childNodes.length; i++) {
            k = node.childNodes[i];
            if (k.nodeType === 3) { out += k.nodeValue.replace(/\u200B/g, "").replace(/\s+/g, " "); continue; }
            if (k.nodeType !== 1) { continue; }
            tg = k.tagName.toLowerCase();
            inner = inl(k);
            if (tg === "b" || tg === "strong") { t = /\S/.test(inner) ? "**" + inner + "**" : inner; }
            else if (tg === "i" || tg === "em") { t = /\S/.test(inner) ? "*" + inner + "*" : inner; }
            else if (tg === "s" || tg === "strike" || tg === "del") { t = "~~" + inner + "~~"; }
            else if (tg === "u") { t = "<u>" + inner + "</u>"; }
            else if (tg === "code") { t = "`" + k.textContent.replace(/\u200B/g, "") + "`"; }
            else if (tg === "a") { t = "[" + inner + "](" + (k.getAttribute("href") || "") + ")"; }
            else if (tg === "img") { t = "![" + (k.getAttribute("alt") || "") + "](" + (k.getAttribute("src") || "") + ")"; }
            else if (tg === "br") { t = "  \n"; }
            else { t = inner; }
            out += t;
        }
        return out;
    }
    function mdOf(node, depth) {
        var out = "", k, i, tg, j, rows, cells, line;
        depth = depth || 0;
        for (i = 0; i < node.childNodes.length; i++) {
            k = node.childNodes[i];
            if (k.nodeType === 3) { if (/\S/.test(k.nodeValue.replace(/\u200B/g, ""))) { out += k.nodeValue.replace(/\u200B/g, "").replace(/\s+/g, " "); } continue; }
            if (k.nodeType !== 1) { continue; }
            tg = k.tagName.toLowerCase();
            if (/^h[1-6]$/.test(tg)) { out += "\n" + new Array(parseInt(tg.charAt(1), 10) + 1).join("#") + " " + inl(k).replace(/^\s+|\s+$/g, "") + "\n\n"; }
            else if (tg === "p" || tg === "div") { var p = inl(k).replace(/^\s+|\s+$/g, ""); out += p ? p + "\n\n" : ""; }
            else if (tg === "blockquote") { out += mdOf(k, depth).replace(/^\s+|\s+$/g, "").replace(/^/gm, "> ") + "\n\n"; }
            else if (tg === "pre") { out += "```\n" + (k.innerText || k.textContent).replace(/\u200B/g, "").replace(/\s+$/, "") + "\n```\n\n"; }
            else if (tg === "hr") { out += "---\n\n"; }
            else if (tg === "ul" || tg === "ol") {
                var n = 0;
                for (j = 0; j < k.childNodes.length; j++) {
                    var li = k.childNodes[j];
                    if (li.nodeType !== 1 || li.tagName.toLowerCase() !== "li") { continue; }
                    n++;
                    var pad = new Array(depth + 1).join("  "), subs = "", own = document.createElement("div"), c2;
                    for (c2 = 0; c2 < li.childNodes.length; c2++) {
                        var ch = li.childNodes[c2];
                        if (ch.nodeType === 1 && /^(ul|ol)$/i.test(ch.tagName)) {
                            var wrap = document.createElement("div"); wrap.appendChild(ch.cloneNode(true));
                            subs += mdOf(wrap, depth + 1);
                        } else { own.appendChild(ch.cloneNode(true)); }
                    }
                    out += pad + (tg === "ol" ? n + ". " : "- ") + inl(own).replace(/^\s+|\s+$/g, "") + "\n" + subs;
                }
                if (!depth) { out += "\n"; }
            } else if (tg === "table") {
                rows = k.rows;
                for (j = 0; j < rows.length; j++) {
                    cells = rows[j].cells; line = "|";
                    for (var c = 0; c < cells.length; c++) { line += " " + inl(cells[c]).replace(/\|/g, "\\|").replace(/^\s+|\s+$/g, "") + " |"; }
                    out += line + "\n";
                    if (j === 0) { line = "|"; for (c = 0; c < cells.length; c++) { line += " --- |"; } out += line + "\n"; }
                }
                out += "\n";
            } else if (tg === "br") { out += "\n"; }
            else { out += inl(k); }
        }
        return out;
    }

    /* ------------------------------------------------- talking to AutoHotkey */
    P.post = function (m) {
        this.queue.push(m);
        var self = this;
        if (!this.qTimer) { this.qTimer = window.setTimeout(function () { self.pump(); }, 0); }
    };
    P.pump = function () {
        this.qTimer = null;
        if (!this.queue.length || !this.req) { return; }
        this.qdata.value = JSON.stringify(this.queue.shift());
        try { this.req.click(); } catch (e) { try { this.req.fireEvent("onclick"); } catch (e2) { } }
        if (this.queue.length) { var self = this; this.qTimer = window.setTimeout(function () { self.pump(); }, 0); }
    };

    /* ============================================================== AXRT */
    AXRT.make = function (id, json) {
        var o = {}, k;
        try { o = JSON.parse(json || "{}"); } catch (e) { }
        for (k in o) { if (o.hasOwnProperty(k) && (o[k] === 0 || o[k] === 1) && /^(readonly|pastePlain|images)$/.test(k)) { o[k] = o[k] === 1; } }
        AXRT.inst[id] = new Rt(id, o);
        var r = AXRT.inst[id];
        r.sent = r.value();
        r.val.value = r.sent;
        return true;
    };
    AXRT.get = function (id) { return AXRT.inst[id]; };
    AXRT.call = function (id, name, json) {
        var r = AXRT.inst[id], a = [];
        if (!r) { return ""; }
        try { a = JSON.parse(json || "[]"); } catch (e) { }
        switch (name) {
        case "value": return r.value();
        case "html": return r.html();
        case "text": return r.text();
        case "md": return r.markdown();
        case "sethtml":
            r.doc.innerHTML = String(a[0] || "");
            r.ensureTail();
            r.status();
            /* set from AutoHotkey: no Change back to it for its own text */
            r.sent = r.value(); r.val.value = r.sent;
            if (r.findOn) { r.findRun(); }
            return "";
        case "insert": r.insertHtml(String(a[0])); return "";
        case "exec": r.run(String(a[0])); return "";
        case "native": r.restore(); r.exec(String(a[0]), a[1]); r.changed(); return "";
        case "table": r.table(a[0], a[1]); return "";
        case "readonly": r.setReadonly(!!a[0]); return "";
        case "focus": r.restore(); return "";
        case "find": r.openFind(!!a[1]); if (a[0]) { r.fq.value = String(a[0]); r.findRun(); } return "";
        case "words": var t = r.text(); return String((t.match(/\S+/g) || []).length);
        }
        return "";
    };
}());
