/* =========================================================================
   AxStudio.js -- the canvas interaction layer.

   AutoHotkey owns the design tree; this file owns the pointer. Trident does
   not deliver mousemove to AHK at all (AxWindow gates it behind its own
   title-bar drag), so a design surface driven from AHK would move in steps.
   Here the ghost, the guides, the drop highlight and the insertion caret are
   pure DOM at frame rate, and exactly one message crosses to AHK -- on drop,
   saying what happened in the tree's own words: "node n7 into box n2, index 3,
   on a new line". AHK edits the model, regenerates the markup, writes it back
   and calls after(). Nothing here has an opinion about what a control is.

   Messages out (a click on the bridge div, payload in a textarea):
     select {sel}      open {id}     page {id}    tab {id,tab}
     ctx    {id,x,y}   panes {kind,v}             jserr {msg}
     move   {ids,to,tab,index,place,x,y,copy}
     create {type,to,tab,index,place,x,y}
     resize {id,w,h,x,y}
   Messages in (AXD.pump reads #axdIn):
     after {sel:[ids]}  select {sel:[ids]}  opts {...}  code {h}  panes {}
   ========================================================================= */

var AXD = {
    paper: null, content: null, hud: null, bridge: null, data: null, inbox: null, wrap: null,
    selIds: [], grid: 8, snap: 1, guides: 1,
    q: [], timer: null, drag: null, boxes: [], edges: { x: [], y: [] }, pageBox: null,
    skip: null, skipIds: [],
    test: false, measuring: false, measId: "",
    zoom: 1, alAnchor: "each",
    pal: { items: [], open: false, sel: 0, hits: [], el: null, input: null, list: null, mode: "cmd" },

    /* ---------------------------------------------------------- plumbing */
    init: function () {
        this.paper = document.getElementById("axdPaper");
        this.content = document.getElementById("axdContent");
        this.hud = document.getElementById("axdHud");
        this.bridge = document.getElementById("axdBridge");
        this.data = document.getElementById("axdBridgeData");
        this.inbox = document.getElementById("axdIn");
        this.wrap = document.getElementById("axdCanvasWrap");
        if (!this.paper) { return; }
        var me = this;
        /* Ctrl and the wheel over the canvas: zoom, not Trident's page zoom */
        if (this.wrap) {
            this.wrap.addEventListener("mousewheel", function (e) {
                if (!e.ctrlKey) { return; }
                me.post("zoom", { d: (e.wheelDelta || 0) > 0 ? 1 : -1 });
                if (e.preventDefault) { e.preventDefault(); }
                e.returnValue = false;
            }, false);
        }
        /* the page on the canvas scrolls like the running window does: the
           outline and the grips drawn over the selection follow it. Scroll
           events do not bubble, so they are caught on the way down. */
        document.addEventListener("scroll", function (e) {
            var t = e.target || e.srcElement;
            if (!t || !me.paper || !me.inside(t, me.paper)) { return; }
            if (me.scrollTimer) { return; }
            me.scrollTimer = setTimeout(function () { me.scrollTimer = 0; if (!me.drag) { me.paint(); } }, 16);
        }, true);
        /* an alignment button in the inspector, pointed at: what it would do */
        document.addEventListener("mouseover", function (e) {
            var t = e.target || e.srcElement;
            var a = t && t.getAttribute ? (t.getAttribute("data-align") || (t.parentNode && t.parentNode.getAttribute
                    ? t.parentNode.getAttribute("data-align") : null)) : null;
            if (a) { me.alPreview(a); }
            else if (me.alShown) { me.alShown = false; me.paint(); }
        }, true);
        var self = this;
        var on = function (name, fn) {
            document.addEventListener(name, function (e) {
                try { fn(e); } catch (err) { self.oops(name, err); }
            }, true);
        };
        var live = function (name, fn) {
            /* In test mode the design surface is left alone entirely: the
               controls on it are real controls, and the only way to find out
               whether they behave is to stop intercepting them. */
            on(name, function (e) { if (!(self.test && self.inPaper(e))) { fn(e); } });
        };
        live("mousedown", function (e) { self.onDown(e); });
        live("mousemove", function (e) { self.onMove(e); });
        live("mouseup", function (e) { self.onUp(e); });
        live("dblclick", function (e) { self.onDbl(e); });
        live("click", function (e) { self.onClick(e); });
        live("contextmenu", function (e) { self.onCtx(e); });
        on("keydown", function (e) { self.onKey(e); });
        this.after([]);
    },
    /* A throw inside a pointer handler used to leave a half-finished drag and
       a canvas that looked frozen. Now it is cleaned up and reported. */
    oops: function (where, err) {
        this.endDrag();
        try { this.post("jserr", { msg: where + ": " + (err && err.message ? err.message : String(err)) }); } catch (e) { }
    },
    pump: function () {
        var m;
        try { m = JSON.parse(this.inbox.value); } catch (e) { return; }
        if (!m || !m.cmd) { return; }
        if (m.cmd === "after") { this.after(m.sel); }
        else if (m.cmd === "select") { this.selIds = m.sel || []; this.paint(); }
        /* the code drawer is gone: the middle is tabbed, and AutoHotkey
           shows and hides the panels itself */
        else if (m.cmd === "test") { this.setTest(m.on); }
        else if (m.cmd === "shell") { this.shell(m); }
        else if (m.cmd === "taborder") { this.tabItems = m.on ? (m.items || []) : null; this.paint(); }
        else if (m.cmd === "opts") {
            if (m.grid != null) { this.grid = m.grid; }
            if (m.snap != null) { this.snap = m.snap; }
            if (m.guides != null) { this.guides = m.guides; }
            if (m.zoom != null) { this.zoom = m.zoom || 1; }
            if (m.anchor != null) { this.alAnchor = m.anchor; }
        }
    },
    post: function (t, p) {
        this.q.push({ t: t, p: p });
        if (!this.timer) {
            var self = this;
            this.timer = window.setTimeout(function () { self.flush(); }, 0);
        }
    },
    /* One message per turn. AHK answers on its own thread and usually rewrites
       the canvas, so handing it a second message from inside the first would
       have it editing a DOM that is about to be replaced. */
    flush: function () {
        this.timer = null;
        if (!this.q.length) { return; }
        var m = this.q.shift();
        this.data.value = JSON.stringify(m);
        try { this.bridge.click(); } catch (e) {
            try { this.bridge.fireEvent("onclick"); } catch (e2) { }
        }
        if (this.q.length) {
            var self = this;
            this.timer = window.setTimeout(function () { self.flush(); }, 0);
        }
    },

    /* ------------------------------------------------------- pane sizes */
    /* One function places every region, from one set of numbers: the
       workspace in front, the two side panes and the bottom panel. The side
       panes only exist in Design; the other workspaces have the whole width.
       It used to be two setters and a message whose zero meant "no change",
       so a pane could not be folded through it at all. */
    lay: { ws: "design", left: 240, right: 312, panel: 31, top: 40, ah: 0 },
    shell: function (o) {
        var s = this.lay, k;
        if (o) {
            for (k in o) {
                if (o.hasOwnProperty(k) && k !== "cmd" && o[k] !== null && o[k] !== undefined) { s[k] = o[k]; }
            }
        }
        var design = s.ws === "design";
        var L = design ? s.left : 0, R = design ? s.right : 0, B = s.panel, T = s.top;
        /* the bottom bar hidden: the regions run to the bottom, and the panel's
           row of tabs waits below the edge (autoHide) */
        var PB = B;
        if (s.ah) { B = 0; }
        var px = function (v) { return Math.round(v) + "px"; };
        var put = function (id, css) {
            var el = document.getElementById(id), p;
            if (!el) { return; }
            for (p in css) { if (css.hasOwnProperty(p)) { el.style[p] = css[p]; } }
        };
        put("axdTop", { height: px(T) });
        put("axdLeft", { top: px(T), bottom: px(B), width: px(L), display: L > 0 ? "block" : "none" });
        put("axdRight", { top: px(T), bottom: px(B), width: px(R), display: R > 0 ? "block" : "none" });
        put("axdMid", { top: px(T), bottom: px(B), left: px(L), right: px(R) });
        /* folded to nothing, a splitter stays at the edge: it is still the way back */
        put("axdSplitL", { top: px(T), bottom: px(B), left: px(Math.max(0, L - 5)),
                           display: design ? "block" : "none" });
        put("axdSplitR", { top: px(T), bottom: px(B), right: px(Math.max(0, R - 5)),
                           display: design ? "block" : "none" });
        put("axdPanel", { height: px(PB) });
        put("axdSplitB", { bottom: px(B - 3), display: B > 40 ? "block" : "none" });
        this.autoHide(!!s.ah);
    },
    /* ---------------------------------------------- the bottom bar, hidden */
    ahOn: false, ahShown: false, ahTimer: null, ahWired: false,
    autoHide: function (on) {
        var self = this, body = document.body;
        this.ahOn = on;
        body.className = body.className.replace(/\s*\baxd-ah(show)?\b/g, "") + (on ? " axd-ah" : "");
        this.ahShown = false;
        this.ahPlace();
        var hint = document.getElementById("axdAhHint");
        if (!hint) {
            hint = document.createElement("div");
            hint.id = "axdAhHint";
            hint.title = "The bottom bar -- bring the pointer here";
            body.appendChild(hint);
        }
        hint.style.display = on ? "block" : "none";
        if (this.ahWired) { return; }
        this.ahWired = true;
        document.addEventListener("mousemove", function (e) { self.ahMove(e); }, true);
    },
    ahMove: function (e) {
        if (!this.ahOn) { return; }
        var h = document.documentElement.clientHeight, y = e.clientY, self = this;
        if (y >= h - 8) {
            if (this.ahTimer) { window.clearTimeout(this.ahTimer); this.ahTimer = null; }
            if (!this.ahShown) { this.ahShown = true; this.ahPlace(); }
        } else if (this.ahShown && y < h - 76 && !this.ahTimer) {
            this.ahTimer = window.setTimeout(function () {
                self.ahTimer = null;
                self.ahShown = false;
                self.ahPlace();
            }, 350);
        } else if (this.ahShown && y >= h - 76 && this.ahTimer) {
            window.clearTimeout(this.ahTimer); this.ahTimer = null;
        }
    },
    ahPlace: function () {
        var body = document.body, p = document.getElementById("axdPanel");
        var sb = document.getElementById("axStatusBar"), sh = sb ? sb.offsetHeight : 0;
        body.className = body.className.replace(/\s*\baxd-ahshow\b/g, "") + (this.ahOn && this.ahShown ? " axd-ahshow" : "");
        if (p) { p.style.bottom = !this.ahOn ? "" : (this.ahShown ? sh + "px" : "-34px"); }
    },
    setLeft: function (w) { this.shell({ left: w }); },
    setRight: function (w) { this.shell({ right: w }); },
    clamp: function (v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); },
    folded: { L: 0, R: 0 },
    fold: function (side) {
        var cur = side === "L" ? document.getElementById("axdLeft").offsetWidth
                               : document.getElementById("axdRight").offsetWidth;
        if (cur > 24) {
            this.folded[side] = cur;
            if (side === "L") { this.setLeft(0); } else { this.setRight(0); }
            this.post("panes", { kind: side, v: 0 });
        } else {
            var back = this.folded[side] || (side === "L" ? 240 : 312);
            if (side === "L") { this.setLeft(back); } else { this.setRight(back); }
            this.post("panes", { kind: side, v: back });
        }
    },

    /* Trident paints a native scrollbar above everything, popups included, so
       an open menu is sliced by whatever pane happens to be scrolled. The
       library shields the scrollers a dropdown overlaps; the menu bar and the
       context menu do not go through that path, so the panes give their
       scrollbars up for as long as a menu is open. */
    watchMenus: function () {
        if (this.menuWatch) { return; }
        var self = this;
        var check = function () {
            var open = !!document.querySelector(".axmb-item.open");
            if (!open) {
                var ctx = document.getElementById("axCtx");
                open = !!(ctx && ctx.style && ctx.style.display === "block");
            }
            if (open === self.menuOpen) { return; }
            self.menuOpen = open;
            var b = document.body;
            if (open) { self.add(b, "axd-menuopen"); } else { self.rem(b, "axd-menuopen"); }
        };
        this.menuOpen = false;
        this.menuWatch = window.setInterval(check, 120);
    },

    /* ------------------------------------------------------ dom helpers */
    cn: function (el) { return (el && typeof el.className === "string") ? el.className : ""; },
    has: function (el, c) { return (" " + this.cn(el) + " ").indexOf(" " + c + " ") >= 0; },
    add: function (el, c) { if (el && !this.has(el, c)) { el.className = this.cn(el) ? this.cn(el) + " " + c : c; } },
    rem: function (el, c) {
        if (!el || !this.has(el, c)) { return; }
        el.className = (" " + this.cn(el) + " ").split(" " + c + " ").join(" ").replace(/^\s+|\s+$/g, "");
    },
    idOf: function (el) {
        var m = /(?:^|\s)axd-id-(n\d+|root)/.exec(this.cn(el));
        return m ? m[1] : "";
    },
    elOf: function (id) {
        if (!id) { return null; }
        var all = this.paper.querySelectorAll(".axd"), i;
        for (i = 0; i < all.length; i++) { if (this.idOf(all[i]) === id) { return all[i]; } }
        return null;
    },
    nodeAt: function (el) {
        while (el && el !== this.paper) {
            if (this.has(el, "axd") && !this.has(el, "axd-locked")) { return el; }
            el = el.parentNode;
        }
        return null;
    },
    boxOf: function (el) {
        while (el && el !== this.paper) {
            if (this.has(el, "tab-panel") && el.id) {
                var m = /^d_(n\d+)_(\d+)$/.exec(el.id);
                if (m) { return { id: m[1], el: el, tab: parseInt(m[2], 10) }; }
            }
            if (this.has(el, "axd-box")) { return { id: this.idOf(el), el: el, tab: 0 }; }
            el = el.parentNode;
        }
        return null;
    },
    /* a control scrolled out of the page's view gets no grips floating over
       the window's frame */
    shownIn: function (el) {
        var c = document.getElementById("axdContent");
        if (!c || !this.inside(el, c)) { return true; }
        var r = el.getBoundingClientRect(), v = c.getBoundingClientRect();
        return r.bottom > v.top && r.top < v.bottom;
    },
    inside: function (el, anc) {
        while (el) { if (el === anc) { return true; } el = el.parentNode; }
        return false;
    },
    rel: function (el) {
        var r = el.getBoundingClientRect(), p = this.paper.getBoundingClientRect();
        return { l: r.left - p.left, t: r.top - p.top, w: r.right - r.left, h: r.bottom - r.top };
    },
    labelOf: function (el) {
        return el.getAttribute("data-axd-label") || "control";
    },
    escape: function (s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    },
    inArr: function (a, v) {
        for (var i = 0; i < a.length; i++) { if (a[i] === v) { return true; } }
        return false;
    },

    /* ----------------------------------------------------- selection ui */
    after: function (sel) {
        /* the frame is rebuilt on every draw, so the cached content element
           is a different node each time */
        this.content = document.getElementById("axdContent") || this.content;
        this.watchMenus();
        if (sel && sel.length != null) { this.selIds = sel; }
        var keep = [], i;
        for (i = 0; i < this.selIds.length; i++) {
            if (this.elOf(this.selIds[i])) { keep.push(this.selIds[i]); }
        }
        this.selIds = keep;
        this.paint();
    },
    isSel: function (id) { return this.inArr(this.selIds, id); },
    /* A radio group shares its HTML name with any other it is grouped with:
       picking in one unpicks the rest. Those others, outlined and labelled. */
    mates: function (el) {
        var inp = el.querySelector("input[type=radio]"), all, i, n, seen = [], r, tag;
        if (!inp || !inp.name) { return; }
        all = this.paper.querySelectorAll("input[type=radio]");
        for (i = 0; i < all.length; i++) {
            if (all[i].name !== inp.name) { continue; }
            n = this.nodeAt(all[i]);
            if (n && n !== el && !this.inArr(seen, n)) { seen.push(n); }
        }
        for (i = 0; i < seen.length; i++) {
            r = this.rel(seen[i]);
            this.mk("axd-mate", r.l - 3, r.t - 3, r.w + 6, r.h + 6);
            tag = this.mk("axd-tag axd-matetag", r.l - 3, r.t - 22);
            tag.innerHTML = "same group: " + this.escape(inp.name);
        }
    },

    /* ------------------------------------------------------ lining up */
    /* One plan for every alignment, worked out here from where things really
       are on screen: where each control would go, which one stays put, and
       which cannot move because it sits in the flow. The inspector's buttons
       show the plan while pointed at, and it is the plan that is carried
       out -- so what is shown is what happens. */
    alShown: false,
    alGap: function () {
        var g = document.getElementById("axdAlGap"), v = g ? parseFloat(g.value) : 8;
        return isNaN(v) ? 8 : v;
    },
    alPlan: function (op) {
        var ids = this.selIds, i, el, r, bx = [], Z = this.zoom || 1;
        var pg = document.getElementById("axdPage");
        if (!pg || ids.length < 2) { return null; }
        var pr = pg.getBoundingClientRect();
        for (i = 0; i < ids.length; i++) {
            el = this.elOf(ids[i]);
            if (!el) { continue; }
            r = el.getBoundingClientRect();
            bx.push({ id: ids[i], el: el, l: r.left, t: r.top, w: r.right - r.left, h: r.bottom - r.top,
                      abs: this.has(el, "axd-pos") && !this.has(el, "axd-dock") });
        }
        if (bx.length < 2) { return null; }
        for (i = 0; i < bx.length; i++) { bx[i].nl = bx[i].l; bx[i].nt = bx[i].t; bx[i].nw = bx[i].w; bx[i].nh = bx[i].h; }
        var mode = this.alAnchor, key = bx[bx.length - 1], ref, b;
        if (mode === "page") { ref = { l: pr.left, t: pr.top, r: pr.right, b: pr.bottom }; }
        else if (mode === "last") { ref = { l: key.l, t: key.t, r: key.l + key.w, b: key.t + key.h }; }
        else {
            ref = { l: 1e9, t: 1e9, r: -1e9, b: -1e9 };
            for (i = 0; i < bx.length; i++) {
                b = bx[i];
                ref.l = Math.min(ref.l, b.l); ref.t = Math.min(ref.t, b.t);
                ref.r = Math.max(ref.r, b.l + b.w); ref.b = Math.max(ref.b, b.t + b.h);
            }
        }
        var space = (op === "distx" || op === "disty" || op === "gapx" || op === "gapy");
        var across = (op === "distx" || op === "gapx");
        if (space) {
            var list = bx.slice(0), axis = across ? "l" : "t", size = across ? "w" : "h";
            list.sort(function (a, c) { return a[axis] - c[axis]; });
            var gap;
            if (op === "distx" || op === "disty") {
                var total = 0, span = (list[list.length - 1][axis] + list[list.length - 1][size]) - list[0][axis];
                for (i = 0; i < list.length; i++) { total += list[i][size]; }
                gap = (span - total) / (list.length - 1);
            } else {
                gap = this.alGap() * Z;
            }
            var at = list[0][axis] + list[0][size];
            for (i = 1; i < list.length; i++) {
                b = list[i];
                b.cur = b[axis] - (list[i - 1][axis] + list[i - 1][size]);  /* the gap it has now */
                b["n" + axis] = at + gap;
                b.flowd = gap - b.cur;                                     /* what its margin changes by */
                at = b["n" + axis] + b[size];
            }
            return { items: bx, key: null, mode: mode, pr: pr, Z: Z, op: op, space: true, across: across, gap: gap };
        }
        for (i = 0; i < bx.length; i++) {
            b = bx[i];
            if (mode === "last" && b === key) { continue; }
            switch (op) {
            case "left":    b.nl = ref.l; break;
            case "right":   b.nl = ref.r - b.w; break;
            case "hcenter": b.nl = (ref.l + ref.r) / 2 - b.w / 2; break;
            case "top":     b.nt = ref.t; break;
            case "bottom":  b.nt = ref.b - b.h; break;
            case "vcenter": b.nt = (ref.t + ref.b) / 2 - b.h / 2; break;
            case "samew":   if (b !== key) { b.nw = key.w; } break;
            case "sameh":   if (b !== key) { b.nh = key.h; } break;
            }
        }
        return { items: bx, key: (mode === "last" || op === "samew" || op === "sameh") ? key : null,
                 mode: mode, pr: pr, Z: Z, op: op, space: false };
    },
    /* whether the plan moves or resizes this one, and whether it can */
    alFate: function (plan, b) {
        var moved = Math.abs(b.nl - b.l) > 0.5 || Math.abs(b.nt - b.t) > 0.5;
        var sized = Math.abs(b.nw - b.w) > 0.5 || Math.abs(b.nh - b.h) > 0.5;
        if (plan.key === b) { return "stays"; }
        if (sized) { return "resized"; }
        if (!moved) { return "there"; }
        if (b.abs || (plan.space && b.flowd != null)) { return "moves"; }
        return "flow";
    },
    alPreview: function (op) {
        this.paint();
        var plan = this.alPlan(op), p = this.paper.getBoundingClientRect(), i, b, f, tag, words;
        if (!plan) { return; }
        this.alShown = true;
        words = { stays: "stays", resized: "resized", there: "already there", moves: "moves",
                  flow: "in the flow -- cannot move" };
        for (i = 0; i < plan.items.length; i++) {
            b = plan.items[i];
            f = this.alFate(plan, b);
            if (f === "moves" || f === "resized") {
                this.mk("axd-alto", b.nl - p.left, b.nt - p.top, b.nw, b.nh);
            }
            if (f === "stays") { this.mk("axd-alstay", b.l - p.left - 3, b.t - p.top - 3, b.w + 6, b.h + 6); }
            tag = this.mk("axd-tag axd-altag axd-al-" + f, (f === "moves" || f === "resized" ? b.nl : b.l) - p.left,
                          (f === "moves" || f === "resized" ? b.nt : b.t) - p.top - 21);
            tag.innerHTML = words[f];
        }
    },
    alDo: function (op) {
        var plan = this.alPlan(op), i, b, f, out = [], Z, pr, it;
        if (!plan) { this.post("align", { op: op, items: [] }); return; }
        Z = plan.Z; pr = plan.pr;
        for (i = 0; i < plan.items.length; i++) {
            b = plan.items[i];
            f = this.alFate(plan, b);
            it = { id: b.id, fate: f };
            if (f === "resized") {
                if (Math.abs(b.nw - b.w) > 0.5) { it.w = Math.round(b.nw / Z); }
                if (Math.abs(b.nh - b.h) > 0.5) { it.h = Math.round(b.nh / Z); }
            } else if (f === "moves") {
                if (b.abs) {
                    it.x = Math.round((b.nl - pr.left) / Z);
                    it.y = Math.round((b.nt - pr.top) / Z);
                } else if (plan.across) {
                    it.dgap = Math.round(b.flowd / Z);
                } else {
                    it.dtop = Math.round(b.flowd / Z);
                }
            }
            out.push(it);
        }
        this.alShown = false;
        this.post("align", { op: op, items: out });
    },
    /* The tab order, set by clicking: each control that takes the keyboard
       wears its number; the ones already clicked this time are marked. */
    tabItems: null,
    tabPaint: function () {
        var h = "", i, it, el, r;
        for (i = 0; i < this.tabItems.length; i++) {
            it = this.tabItems[i];
            el = this.elOf(it.id);
            if (!el) { continue; }
            r = this.rel(el);
            h += '<span class="axd-tabno' + (it.set ? " set" : "") + '" style="left:' + Math.round(r.l - 8)
               + 'px;top:' + Math.round(r.t - 8) + 'px">' + it.n + '</span>';
        }
        this.hud.insertAdjacentHTML("beforeend", h);
    },
    select: function (id, add) {
        if (!id) { this.selIds = []; }
        else if (add) {
            if (this.isSel(id)) {
                var out = [], i;
                for (i = 0; i < this.selIds.length; i++) { if (this.selIds[i] !== id) { out.push(this.selIds[i]); } }
                this.selIds = out;
            } else { this.selIds.push(id); }
        } else { this.selIds = [id]; }
        this.paint();
        this.post("select", { sel: this.selIds });
    },
    paint: function () {
        var all = this.paper.querySelectorAll(".axd"), i;
        for (i = 0; i < all.length; i++) {
            this.rem(all[i], "axd-sel");
            this.rem(all[i], "axd-sel2");
        }
        this.clearHud();
        /* setting the tab order: a number on each control, and nothing else */
        if (this.tabItems) { return this.tabPaint(); }
        /* Nothing is selected while you are trying the design out: an outline
           and eight grips over a button you are about to click are exactly
           what test mode exists to get out of the way. */
        if (this.test || !this.selIds.length) { return; }
        for (i = 0; i < this.selIds.length; i++) {
            var el = this.elOf(this.selIds[i]);
            if (el) { this.add(el, i === this.selIds.length - 1 ? "axd-sel" : "axd-sel2"); }
        }
        if (this.selIds.length === 1) {
            var last = this.elOf(this.selIds[0]);
            if (last && !this.has(last, "axd-pagebox") && this.shownIn(last)) { this.handles(last); this.actbar(last); this.mates(last); }
        } else {
            /* several: the bar goes on the last one picked, and offers what is
               done to several -- which is when Group and Align are wanted */
            var prim = this.elOf(this.selIds[this.selIds.length - 1]);
            if (prim) { this.actbar(prim, this.multiActs); }
        }
    },
    /* The things done to a control most often, on the control: its code, a
       copy of it, up to what holds it, away with it, and everything else. The
       right-click menu has them too -- but nobody right-clicks what they
       cannot see is there. Above the control, or below it when there is no
       room above; never past the right edge of the paper. */
    acts: [["code", "E943", "Its code    Enter"], ["dup", "E8C8", "Duplicate    Ctrl+D"],
           ["parent", "E74A", "Select what holds it"], ["del", "E74D", "Delete    Del"],
           ["more", "E712", "Everything else    Shift+F10"]],
    multiActs: [["group", "E8B0", "Put them in a box"], ["align", "E8E4", "Align them"],
                ["dup", "E8C8", "Duplicate them    Ctrl+D"], ["del", "E74D", "Delete them    Del"]],
    actbar: function (el, acts) {
        var r = this.rel(el), i, h = "";
        acts = acts || this.acts;
        for (i = 0; i < acts.length; i++) {
            h += '<span class="axd-actbtn" data-hudact="' + acts[i][0] + '" data-tip="'
               + acts[i][2] + '">&#x' + acts[i][1] + ';</span>';
        }
        var bar = this.mk("axd-actbar", r.l, r.t - 32);
        bar.innerHTML = h;
        var w = bar.offsetWidth || 150;
        var pw = this.paper.offsetWidth || 9999;
        if (r.l + w > pw - 4) { bar.style.left = Math.max(4, pw - w - 4) + "px"; }
        if (r.t < 36) { bar.style.top = Math.round(r.t + r.h + 6) + "px"; }
    },
    clearHud: function () {
        while (this.hud.firstChild) { this.hud.removeChild(this.hud.firstChild); }
    },
    mk: function (cls, l, t, w, h) {
        var d = document.createElement("div");
        d.className = cls;
        d.style.left = Math.round(l) + "px";
        d.style.top = Math.round(t) + "px";
        if (w != null) { d.style.width = Math.max(0, Math.round(w)) + "px"; }
        if (h != null) { d.style.height = Math.max(0, Math.round(h)) + "px"; }
        this.hud.appendChild(d);
        return d;
    },
    handles: function (el) {
        var r = this.rel(el);
        var dirs = [["nw", 0, 0], ["n", .5, 0], ["ne", 1, 0], ["e", 1, .5],
                    ["se", 1, 1], ["s", .5, 1], ["sw", 0, 1], ["w", 0, .5]];
        for (var i = 0; i < dirs.length; i++) {
            var d = dirs[i];
            var h = this.mk("axd-handle axd-h-" + d[0], r.l + r.w * d[1] - 4, r.t + r.h * d[2] - 4, 8, 8);
            h.setAttribute("data-dir", d[0]);
        }
    },
    strip: function (cls) {
        var k = this.hud.childNodes, i;
        for (i = k.length - 1; i >= 0; i--) {
            if (this.has(k[i], cls)) { this.hud.removeChild(k[i]); }
        }
    },

    /* --------------------------------------------------------- pointer */
    onDown: function (e) {
        var t = e.target || e.srcElement;
        if (this.has(t, "axd-split")) {
            this.drag = { mode: "split", kind: t.id === "axdSplitL" ? "L" : (t.id === "axdSplitB" ? "B" : "R"),
                          live: true, x0: e.clientX, y0: e.clientY };
            return this.stop(e);
        }
        if (t.id === "axdSizeGrip") {
            var pr = this.paper.getBoundingClientRect();
            this.drag = { mode: "size", live: true, x0: e.clientX, y0: e.clientY,
                          w0: pr.right - pr.left, h0: pr.bottom - pr.top };
            return this.stop(e);
        }
        if (this.acHit(t)) { return this.stop(e); }
        var act = this.closestAttr(t, "data-hudact", this.paper);
        if (act) {
            this.post("hud", { act: act.getAttribute("data-hudact"), id: this.selIds[0] || "",
                               x: e.clientX, y: e.clientY });
            return this.stop(e);
        }
        var h = t;
        while (h && h !== this.hud) {
            if (this.has(h, "axd-handle")) {
                this.startResize(e, h.getAttribute("data-dir"));
                return this.stop(e);
            }
            h = h.parentNode;
        }
        /* the toolbox and the outline are both drag sources */
        var src = this.closestAttr(t, "data-newtype", document.body);
        if (src) {
            this.arm(e, { mode: "create", type: src.getAttribute("data-newtype"),
                          label: src.getAttribute("data-newlabel") || src.getAttribute("data-newtype") });
            return this.stop(e);
        }
        var tree = this.closestAttr(t, "data-dragid", document.body);
        if (tree && e.button === 0) {
            this.arm(e, { mode: "move", ids: [tree.getAttribute("data-dragid")],
                          label: tree.getAttribute("data-draglabel") || "control" });
            return;                                  /* the click still selects */
        }
        if (!this.inside(t, this.paper)) { return; }
        if (this.tabItems) {
            var tn = this.nodeAt(t);
            if (tn) { this.post("tabpick", { id: this.idOf(tn) }); }
            return this.stop(e);
        }

        var nav = this.closestAttr(t, "data-nav", this.paper);
        if (nav) { this.post("page", { id: nav.getAttribute("data-nav") }); return this.stop(e); }
        var tab = this.closestClass(t, "tab");
        if (tab && tab.getAttribute("data-target")) {
            this.switchTab(tab);
            return this.stop(e);
        }
        var node = this.nodeAt(t);
        var id = node ? this.idOf(node) : "";
        var addTo = e.ctrlKey || e.shiftKey;
        if (!node || this.has(node, "axd-pagebox")) {
            if (!addTo) { this.select(node ? id : "", false); }
            this.arm(e, { mode: "marquee", base: addTo ? this.selIds.slice(0) : [] });
            return this.stop(e);
        }
        /* Ctrl or Shift and a click adds it to the group (or takes it out);
           holding on and dragging carries the whole group from there -- the one
           under the mouse first, so the rest keep their places around it */
        if (addTo) {
            this.select(id, true);
            if (this.isSel(id) && (e.button === 0 || e.button == null)) {
                this.arm(e, { mode: "move", ids: this.dragIds(id), label: this.labelOf(node), picked: true });
            }
            return this.stop(e);
        }
        if (!this.isSel(id)) { this.select(id, false); }
        if (e.button === 0 || e.button == null) {
            this.arm(e, { mode: "move", ids: this.dragIds(id), label: this.labelOf(node) });
        }
        this.stop(e);
    },
    dragIds: function (id) {
        var out = [id], i;
        for (i = 0; i < this.selIds.length; i++) { if (this.selIds[i] !== id) { out.push(this.selIds[i]); } }
        return out;
    },
    acHit: function (t) {
        var el = t;
        while (el) {
            if (el.getAttribute && el.getAttribute("data-ac") != null) {
                try { AXE.clickAc(parseInt(el.getAttribute("data-ac"), 10)); } catch (e) { }
                return true;
            }
            el = el.parentNode;
        }
        return false;
    },
    closestAttr: function (el, a, stopAt) {
        while (el && el !== stopAt) {
            if (el.getAttribute && el.getAttribute(a)) { return el; }
            el = el.parentNode;
        }
        return null;
    },
    closestClass: function (el, c) {
        while (el && el !== this.paper) {
            if (this.has(el, c)) { return el; }
            el = el.parentNode;
        }
        return null;
    },
    switchTab: function (tab) {
        var strip = tab.parentNode, i;
        var tabs = strip.getElementsByTagName("div");
        for (i = 0; i < tabs.length; i++) {
            if (this.has(tabs[i], "tab")) { this.rem(tabs[i], "active"); }
        }
        this.add(tab, "active");
        var owner = this.idOf(strip), n = 1, pn;
        while ((pn = document.getElementById("d_" + owner + "_" + n))) {
            this.rem(pn, "visible");
            n++;
        }
        var target = document.getElementById(tab.getAttribute("data-target"));
        if (target) { this.add(target, "visible"); }
        this.paint();
        var m = /_(\d+)$/.exec(tab.getAttribute("data-target"));
        this.post("tab", { id: owner, tab: m ? parseInt(m[1], 10) : 1 });
    },
    onDbl: function (e) {
        var t = e.target || e.srcElement;
        if (this.has(t, "axd-split")) {
            /* a pane you are not using should be one gesture away from gone */
            if (t.id === "axdSplitL") { this.fold("L"); }
            else if (t.id === "axdSplitR") { this.fold("R"); }
            else if (t.id === "axdSplitB") { this.post("panes", { kind: "B", v: 0 }); }
            return this.stop(e);
        }
        if (!this.inside(t, this.paper)) { return; }
        /* a drag that has just ended is not a double-click on what it moved */
        if (new Date().getTime() - (this.dragEndAt || 0) < 700) { return this.stop(e); }
        var node = this.nodeAt(t);
        if (node) { this.post("open", { id: this.idOf(node) }); }
        this.stop(e);
    },
    onClick: function (e) {
        var t = e.target || e.srcElement;
        if (t === this.bridge) { return; }
        if (this.inside(t, this.paper)) { this.stop(e); }
    },
    onCtx: function (e) {
        var t = e.target || e.srcElement;
        if (!this.inside(t, this.paper)) { return; }
        var node = this.nodeAt(t);
        var id = node ? this.idOf(node) : "";
        if (id && !this.isSel(id)) { this.select(id, false); }
        this.post("ctx", { id: id, x: e.clientX, y: e.clientY });
        this.stop(e);
    },
    onKey: function (e) {
        /* Ctrl+Shift+P is every command, Ctrl+P is every place. Both are
           handled here rather than in AutoHotkey because the palette is a
           plain <input>, and AHK's own key hook steps aside for those. */
        if (e.ctrlKey && e.keyCode === 80) {
            this.palOpen(e.shiftKey ? "cmd" : "go");
            this.stop(e);
            return;
        }
        /* Escape is the way out of everything, and while the canvas is live
           it is the only thing on it that still belongs to the studio. */
        if (e.keyCode === 27 && this.test) {
            this.post("cmd", { id: "cmd:test" });
            this.stop(e);
            return;
        }
        if (e.keyCode === 27 && this.pal.open) {
            this.palClose();
            this.stop(e);
            return;
        }
        if (e.keyCode === 27 && this.drag) {
            this.endDrag();
            this.paint();
            this.stop(e);
        }
    },
    stop: function (e) {
        if (e.stopPropagation) { e.stopPropagation(); }
        if (e.preventDefault) { e.preventDefault(); }
        e.cancelBubble = true;
        e.returnValue = false;
    },

    /* ------------------------------------------------------------ drag */
    arm: function (e, d) {
        d.x0 = e.clientX;
        d.y0 = e.clientY;
        d.live = false;
        this.drag = d;
    },
    endDrag: function () {
        var d = this.drag;
        this.drag = null;
        if (this.paper) { this.rem(this.paper, "axd-moving"); }
        if (!d) { return; }
        if (d.els) {
            for (var i = 0; i < d.els.length; i++) { this.rem(d.els[i], "axd-dragging"); }
        }
        this.clearHud();
    },
    startResize: function (e, dir) {
        var id = this.selIds.length ? this.selIds[this.selIds.length - 1] : "";
        var el = this.elOf(id);
        if (!el) { return; }
        var r = this.rel(el), pg = document.getElementById("axdPage");
        this.drag = { mode: "resize", dir: dir, id: id, el: el, x0: e.clientX, y0: e.clientY,
                      r0: r, live: true, w: r.w, h: r.h, l: r.l, t: r.t,
                      abs: this.has(el, "axd-pos"), page: pg ? this.rel(pg) : { l: 0, t: 0 } };
        if (this.paper) { this.add(this.paper, "axd-moving"); }
        this.clearHud();
        this.drag.box = this.mk("axd-rez", r.l, r.t, r.w, r.h);
        this.drag.tag = this.mk("axd-tag", r.l, r.t - 21);
        this.drag.tag.innerHTML = Math.round(r.w / (this.zoom || 1)) + " x " + Math.round(r.h / (this.zoom || 1));
    },
    onMove: function (e) {
        var d = this.drag;
        if (!d) { this.measure(e); return; }
        if (!d.live) {
            if (Math.abs(e.clientX - d.x0) + Math.abs(e.clientY - d.y0) < 5) { return; }
            this.begin(d, e);
            if (!this.drag) { return; }
        }
        if (d.mode === "split") { this.moveSplit(d, e); }
        else if (d.mode === "size") { this.moveSize(d, e); }
        else if (d.mode === "resize") { this.moveResize(d, e); }
        else if (d.mode === "marquee") { this.moveMarquee(d, e); }
        else { this.autoScroll(e); this.moveDrop(d, e); }
        this.stop(e);
    },
    moveSplit: function (d, e) {
        var shell = document.getElementById("axdShell").getBoundingClientRect();
        if (d.kind === "L") { d.v = this.clamp(e.clientX - shell.left, 170, 460); this.setLeft(d.v); }
        else if (d.kind === "R") { d.v = this.clamp(shell.right - e.clientX, 210, 560); this.setRight(d.v); }
        /* the bottom panel: never so tall that the workspace above it is gone */
        else if (d.kind === "B") {
            d.v = this.clamp(shell.bottom - e.clientY, 90, Math.max(120, shell.bottom - shell.top - 220));
            this.shell({ panel: d.v });
        }
    },
    moveSize: function (d, e) {
        var Z = this.zoom || 1, g = this.grid * Z;
        d.w = Math.max(200 * Z, Math.round(d.w0 + (e.clientX - d.x0)));
        d.h = Math.max(120 * Z, Math.round(d.h0 + (e.clientY - d.y0)));
        if (this.snap && this.grid > 1) {
            d.w = Math.round(d.w / g) * g;
            d.h = Math.round(d.h / g) * g;
        }
        this.paper.style.width = d.w + "px";
        this.paper.style.height = d.h + "px";
    },
    begin: function (d, e) {
        d.live = true;
        /* the grid comes forward while something is being placed on it */
        if (this.paper) { this.add(this.paper, "axd-moving"); }
        this.clearHud();
        var p = this.paper.getBoundingClientRect();
        d.px = p.left; d.py = p.top;
        if (d.mode === "marquee") {
            d.box = this.mk("axd-marquee", 0, 0, 0, 0);
            return;
        }
        if (d.mode === "move") {
            d.els = [];
            for (var i = 0; i < d.ids.length; i++) {
                var el = this.elOf(d.ids[i]);
                if (el) { d.els.push(el); this.add(el, "axd-dragging"); }
            }
            if (!d.els.length) { this.drag = null; return; }
            var r = this.rel(d.els[0]);
            d.ox = (e.clientX - p.left) - r.l;
            d.oy = (e.clientY - p.top) - r.t;
            if (d.ox < 0 || d.ox > r.w) { d.ox = Math.min(24, r.w / 2); }
            if (d.oy < 0 || d.oy > r.h) { d.oy = Math.min(14, r.h / 2); }
            d.ghost = this.ghostOf(d.els[0], r, d.ids.length);
            d.abs = this.has(d.els[0], "axd-pos");
        } else {
            d.ghost = this.mk("axd-ghost axd-newghost", 0, 0);
            d.ghost.innerHTML = this.escape(d.label);
            d.ox = 14; d.oy = 12;
            d.abs = false;
            d.els = [];
        }
        d.hint = this.mk("axd-hint", 0, 0);
        this.cache(d.els.length === 1 ? d.els[0] : null, d.ids || []);
    },
    ghostOf: function (el, r, count) {
        var g = this.mk("axd-ghost", r.l, r.t, r.w, r.h);
        var c = el.cloneNode(true);
        this.stripIds(c);
        c.className = this.cn(c).replace(/axd-sel2|axd-sel|axd-dragging/g, "");
        g.appendChild(c);
        if (count > 1) {
            var b = document.createElement("div");
            b.className = "axd-count";
            b.innerHTML = count + "";
            g.appendChild(b);
        }
        return g;
    },
    stripIds: function (el) {
        if (el.nodeType !== 1) { return; }
        if (el.id) { el.id = ""; }
        var k = el.childNodes;
        for (var i = 0; i < k.length; i++) { this.stripIds(k[i]); }
    },

    /* Rects are read once, at the start of the drag. Reading them per move is
       what makes a designer feel like treacle, and nothing moves mid-drag. */
    cache: function (skipEl, skipIds) {
        var boxes = [], self = this;
        var page = document.getElementById("axdPage");
        var ids = skipIds || [];
        var skipped = function (el) {
            if (skipEl && self.inside(el, skipEl)) { return true; }
            var n = el;
            while (n && n !== self.paper) {
                var id = self.idOf(n);
                if (id && self.inArr(ids, id)) { return true; }
                n = n.parentNode;
            }
            return false;
        };
        var rect = function (el) {
            var r = el.getBoundingClientRect();
            return { l: r.left, t: r.top, r: r.right, b: r.bottom, w: r.right - r.left, h: r.bottom - r.top };
        };
        var depth = function (el) { var n = 0; while (el && el !== self.paper) { n++; el = el.parentNode; } return n; };
        if (page) { boxes.push({ id: this.idOf(page), el: page, tab: 0, rect: rect(page), depth: 0, name: "the page" }); }
        var list = this.content.querySelectorAll(".axd-box"), i;
        for (i = 0; i < list.length; i++) {
            var b = list[i];
            if (b === page || skipped(b)) { continue; }
            var id = this.idOf(b), nm = this.labelOf(b);
            if (this.has(b, "tabs") || this.has(b, "tabs-frame")) {
                var n = 1, pn;
                while ((pn = document.getElementById(b.id + "_" + n))) {
                    if (this.has(pn, "visible") && !skipped(pn)) {
                        boxes.push({ id: id, el: pn, tab: n, rect: rect(pn), depth: depth(pn), name: nm + " tab " + n });
                    }
                    n++;
                }
            } else {
                boxes.push({ id: id, el: b, tab: 0, rect: rect(b), depth: depth(b), name: nm });
            }
        }
        this.boxes = boxes;
        this.pageBox = boxes.length ? boxes[0] : null;
        this.skip = skipEl;
        this.skipIds = ids;
        var edges = { x: [], y: [] };
        var all = this.content.querySelectorAll(".axd");
        for (i = 0; i < all.length; i++) {
            if (skipped(all[i])) { continue; }
            var r2 = rect(all[i]);
            edges.x.push(r2.l, r2.r, (r2.l + r2.r) / 2);
            edges.y.push(r2.t, r2.b, (r2.t + r2.b) / 2);
        }
        this.edges = edges;
    },
    autoScroll: function (e) {
        var r = this.wrap.getBoundingClientRect(), pad = 44, step = 18;
        if (e.clientY < r.top + pad) { this.wrap.scrollTop -= step; }
        else if (e.clientY > r.bottom - pad) { this.wrap.scrollTop += step; }
        if (e.clientX < r.left + pad) { this.wrap.scrollLeft -= step; }
        else if (e.clientX > r.right - pad) { this.wrap.scrollLeft += step; }
    },
    hitBox: function (x, y) {
        var best = null;
        for (var i = 0; i < this.boxes.length; i++) {
            var b = this.boxes[i];
            if (x >= b.rect.l && x < b.rect.r && y >= b.rect.t && y < b.rect.b) {
                if (!best || b.depth > best.depth) { best = b; }
            }
        }
        return best || this.pageBox;
    },
    kidsOf: function (box) {
        var out = [], all = box.el.querySelectorAll(".axd"), i;
        for (i = 0; i < all.length; i++) {
            var e = all[i];
            if (this.skip && this.inside(e, this.skip)) { continue; }
            if (this.inArr(this.skipIds, this.idOf(e))) { continue; }
            var b = this.boxOf(e.parentNode);
            if (b && b.el === box.el) { out.push(e); }
        }
        return out;
    },

    moveDrop: function (d, e) {
        var x = e.clientX, y = e.clientY;
        this.strip("axd-caret");
        this.strip("axd-guide");
        this.strip("axd-drophi");
        var free = e.altKey || (d.abs && !e.shiftKey);
        if (free) { return this.moveFree(d, e); }
        var box = this.hitBox(x, y);
        if (!box) { return; }
        d.drop = { box: box, index: 1, place: "flow", x: 0, y: 0 };
        this.mk("axd-drophi", box.rect.l - d.px, box.rect.t - d.py, box.rect.w, box.rect.h);
        var kids = this.kidsOf(box);
        this.ghost(d, x - d.ox, y - d.oy);
        var where;
        if (!kids.length) {
            this.mk("axd-caret axd-caret-h", box.rect.l - d.px + 8, box.rect.t - d.py + 10, box.rect.w - 16, 3);
            where = "into " + box.name;
        } else {
            var pick = 0, bestDist = 1e9, i, r;
            for (i = 0; i < kids.length; i++) {
                r = kids[i].getBoundingClientRect();
                var cy = (r.top + r.bottom) / 2;
                var dist = (y >= r.top && y < r.bottom) ? 0 : Math.abs(y - cy);
                if (dist < bestDist) { bestDist = dist; pick = i; }
            }
            r = kids[pick].getBoundingClientRect();
            if (y >= r.top && y < r.bottom) {
                var before = x < (r.left + r.right) / 2;
                d.drop.index = pick + (before ? 1 : 2);
                d.drop.place = "same";
                this.mk("axd-caret axd-caret-v", (before ? r.left - 4 : r.right + 1) - d.px, r.top - d.py - 2,
                        3, (r.bottom - r.top) + 4);
                where = (before ? "before " : "after ") + this.labelOf(kids[pick]) + ", same line";
            } else {
                var below = y > (r.top + r.bottom) / 2;
                d.drop.index = pick + (below ? 2 : 1);
                d.drop.place = "flow";
                this.mk("axd-caret axd-caret-h", box.rect.l - d.px + 4, (below ? r.bottom + 3 : r.top - 5) - d.py,
                        box.rect.w - 8, 3);
                where = "new line in " + box.name;
            }
        }
        this.hint(d, x, y, where + "    Alt free    Ctrl copy");
    },
    /* Alt, or dragging something already free: absolute placement against the
       page, which is the only box AxGui positions children against. */
    moveFree: function (d, e) {
        var page = this.pageBox;
        if (!page) { return; }
        var x = e.clientX - d.ox, y = e.clientY - d.oy;
        var w = d.ghost.offsetWidth, h = d.ghost.offsetHeight;
        var sx = this.snapTo(x, w, "x"), sy = this.snapTo(y, h, "y");
        var Z = this.zoom || 1;
        d.drop = { box: page, index: 0, place: "abs",
                   x: Math.round((sx.v - page.rect.l) / Z), y: Math.round((sy.v - page.rect.t) / Z) };
        this.ghost(d, sx.v, sy.v);
        if (this.guides) {
            if (sx.g != null) { this.mk("axd-guide axd-guide-v", sx.g - d.px, page.rect.t - d.py, 1, page.rect.h); }
            if (sy.g != null) { this.mk("axd-guide axd-guide-h", page.rect.l - d.px, sy.g - d.py, page.rect.w, 1); }
        }
        this.hint(d, e.clientX, e.clientY, "free at " + d.drop.x + ", " + d.drop.y + "    Shift back into the flow");
    },
    hint: function (d, x, y, text) {
        if (!d.hint) { return; }
        d.hint.innerHTML = this.escape(text);
        d.hint.style.left = Math.round(x - d.px + 16) + "px";
        d.hint.style.top = Math.round(y - d.py + 22) + "px";
    },
    snapTo: function (v, size, axis) {
        if (!this.snap) { return { v: v, g: null }; }
        var list = this.edges[axis], best = null, bd = 7, i, k;
        var probes = [v, v + size, v + size / 2];
        for (i = 0; i < list.length; i++) {
            for (k = 0; k < 3; k++) {
                var dd = Math.abs(probes[k] - list[i]);
                if (dd < bd) { bd = dd; best = { v: v + (list[i] - probes[k]), g: list[i] }; }
            }
        }
        if (best) { return best; }
        if (this.grid > 1) {
            var base = this.pageBox ? this.pageBox.rect[axis === "x" ? "l" : "t"] : 0, gz = this.grid * (this.zoom || 1);
            return { v: base + Math.round((v - base) / gz) * gz, g: null };
        }
        return { v: v, g: null };
    },
    ghost: function (d, x, y) {
        d.ghost.style.left = Math.round(x - d.px) + "px";
        d.ghost.style.top = Math.round(y - d.py) + "px";
    },

    moveMarquee: function (d, e) {
        var p = this.paper.getBoundingClientRect();
        var l = Math.min(d.x0, e.clientX), t = Math.min(d.y0, e.clientY);
        var w = Math.abs(e.clientX - d.x0), h = Math.abs(e.clientY - d.y0);
        d.box.style.left = Math.round(l - p.left) + "px";
        d.box.style.top = Math.round(t - p.top) + "px";
        d.box.style.width = Math.round(w) + "px";
        d.box.style.height = Math.round(h) + "px";
        var hit = d.base.slice(0), all = this.content.querySelectorAll(".axd"), i;
        for (i = 0; i < all.length; i++) {
            var el = all[i];
            if (this.has(el, "axd-pagebox")) { continue; }
            var r = el.getBoundingClientRect();
            if (r.left >= l && r.top >= t && r.right <= l + w && r.bottom <= t + h) {
                var id = this.idOf(el);
                if (id && !this.inArr(hit, id)) { hit.push(id); }
            }
        }
        d.hit = hit;
        this.selIds = hit;
        for (i = 0; i < all.length; i++) {
            this.rem(all[i], "axd-sel");
            this.rem(all[i], "axd-sel2");
            if (this.inArr(hit, this.idOf(all[i]))) { this.add(all[i], "axd-sel2"); }
        }
    },

    moveResize: function (d, e) {
        var dx = e.clientX - d.x0, dy = e.clientY - d.y0;
        var l = d.r0.l, t = d.r0.t, w = d.r0.w, h = d.r0.h;
        if (d.dir.indexOf("e") >= 0) { w = d.r0.w + dx; }
        if (d.dir.indexOf("s") >= 0) { h = d.r0.h + dy; }
        if (d.dir.indexOf("w") >= 0) { w = d.r0.w - dx; l = d.r0.l + dx; }
        if (d.dir.indexOf("n") >= 0) { h = d.r0.h - dy; t = d.r0.t + dy; }
        var Z = this.zoom || 1;
        if (this.snap && this.grid > 1 && !e.altKey) {
            w = Math.round(w / (this.grid * Z)) * this.grid * Z;
            h = Math.round(h / (this.grid * Z)) * this.grid * Z;
        }
        w = Math.max(8, w); h = Math.max(8, h);
        d.w = w; d.h = h; d.l = l; d.t = t;
        d.box.style.left = Math.round(l) + "px";
        d.box.style.top = Math.round(t) + "px";
        d.box.style.width = Math.round(w) + "px";
        d.box.style.height = Math.round(h) + "px";
        d.tag.style.left = Math.round(l) + "px";
        d.tag.style.top = Math.round(t - 21) + "px";
        d.tag.innerHTML = Math.round(w / Z) + " x " + Math.round(h / Z);
    },

    onUp: function (e) {
        var d = this.drag;
        this.drag = null;
        if (this.paper) { this.rem(this.paper, "axd-moving"); }
        if (!d) { return; }
        if (d.els) {
            for (var i = 0; i < d.els.length; i++) { this.rem(d.els[i], "axd-dragging"); }
        }
        if (!d.live) {
            /* a press that never became a drag: from the toolbox that means
               "add it where I am", from anywhere else it was just a click */
            this.clearHud();
            if (d.mode === "create") { this.post("create", { type: d.type, to: "", index: 0, place: "flow" }); }
            else { this.paint(); }
            return;
        }
        this.stop(e);
        /* the second press of a double-click can end a drag: not an "open" */
        this.dragEndAt = new Date().getTime();
        if (d.mode === "split") {
            this.post("panes", { kind: d.kind, v: Math.round(d.v || 0) });
            this.paint();
            return;
        }
        if (d.mode === "size") {
            this.post("size", { w: Math.round(d.w / (this.zoom || 1)), h: Math.round(d.h / (this.zoom || 1)) });
            return;
        }
        if (d.mode === "marquee") {
            this.clearHud();
            this.selIds = d.hit || [];
            this.paint();
            this.post("select", { sel: this.selIds });
            return;
        }
        if (d.mode === "resize") {
            var only = (d.dir === "e" || d.dir === "w") ? "w" : (d.dir === "n" || d.dir === "s") ? "h" : "";
            var Zr = this.zoom || 1;
            var msg = { id: d.id, w: (only === "h" ? null : Math.round(d.w / Zr)),
                        h: (only === "w" ? null : Math.round(d.h / Zr)) };
            if (d.abs && (d.dir.indexOf("n") >= 0 || d.dir.indexOf("w") >= 0)) {
                msg.x = Math.round((d.l - d.page.l) / Zr);
                msg.y = Math.round((d.t - d.page.t) / Zr);
            }
            this.post("resize", msg);
            return;
        }
        if (!d.drop) { this.clearHud(); this.paint(); return; }
        var p = { to: d.drop.box.id, tab: d.drop.box.tab, index: d.drop.index,
                  place: d.drop.place, x: d.drop.x, y: d.drop.y };
        if (d.mode === "create") { p.type = d.type; this.post("create", p); }
        /* Ctrl at the drop copies -- unless Ctrl was how the group was picked */
        else { p.ids = d.ids; p.copy = (e.ctrlKey && !d.picked) ? 1 : 0; this.post("move", p); }
    },

    /* --------------------------------------------------------- measuring */
    /* Hold Alt and point at a control: the gap between it and whatever is
       nearest on each of the four sides, with the number on it. Every design
       argument ends up being about these four numbers, and until now the only
       way to know them was to read the option string and do the arithmetic. */
    measure: function (e) {
        var alt = !!(e.altKey);
        if (!alt) {
            if (this.measuring) { this.measuring = false; this.strip("axd-meas"); this.strip("axd-measlab"); }
            return;
        }
        var el = this.nodeAt(e.srcElement || e.target);
        if (!el) {
            if (this.measuring) { this.strip("axd-meas"); this.strip("axd-measlab"); this.measuring = false; }
            return;
        }
        var id = this.idOf(el);
        if (this.measuring && this.measId === id) { return; }
        this.strip("axd-meas");
        this.strip("axd-measlab");
        this.measuring = true;
        this.measId = id;
        var r = this.rel(el), box = el.parentNode;
        var pr = (box && box !== this.paper) ? this.rel(box) : { l: 0, t: 0,
                  w: this.paper.offsetWidth, h: this.paper.offsetHeight };
        /* the nearest edge on each side: a sibling if one is in the way,
           otherwise the inside of the container */
        var lim = { l: pr.l, t: pr.t, r: pr.l + pr.w, b: pr.t + pr.h };
        var sib = box ? box.childNodes : [], i;
        for (i = 0; i < sib.length; i++) {
            var o = sib[i];
            if (!o || o.nodeType !== 1 || o === el || !this.has(o, "axd")) { continue; }
            var q = this.rel(o);
            if (q.t < r.t + r.h && q.t + q.h > r.t) {
                if (q.l + q.w <= r.l && q.l + q.w > lim.l) { lim.l = q.l + q.w; }
                if (q.l >= r.l + r.w && q.l < lim.r) { lim.r = q.l; }
            }
            if (q.l < r.l + r.w && q.l + q.w > r.l) {
                if (q.t + q.h <= r.t && q.t + q.h > lim.t) { lim.t = q.t + q.h; }
                if (q.t >= r.t + r.h && q.t < lim.b) { lim.b = q.t; }
            }
        }
        var cx = r.l + r.w / 2, cy = r.t + r.h / 2;
        this.measSpan(lim.l, cy, r.l - lim.l, 0);
        this.measSpan(r.l + r.w, cy, lim.r - (r.l + r.w), 0);
        this.measSpan(cx, lim.t, 0, r.t - lim.t);
        this.measSpan(cx, r.t + r.h, 0, lim.b - (r.t + r.h));
        var tag = this.mk("axd-measlab axd-tag", r.l, r.t - 20, null, null);
        tag.innerHTML = Math.round(r.w / (this.zoom || 1)) + " &#215; " + Math.round(r.h / (this.zoom || 1));
    },
    measSpan: function (l, t, w, h) {
        var n = Math.round((w || h) / (this.zoom || 1));
        if (n < 1) { return; }
        this.mk("axd-meas", w ? l : l, h ? t : t - 1, w ? w : 1, h ? h : 1);
        var lab = this.mk("axd-measlab axd-tag", w ? l + w / 2 - 10 : l + 4, h ? t + h / 2 - 8 : t - 20, null, null);
        lab.innerHTML = String(n);
    },

    /* ---------------------------------------------------------- testing */
    inPaper: function (e) {
        var t = e.srcElement || e.target;
        if (!t || !this.paper) { return false; }
        try { return this.paper === t || this.paper.contains(t); } catch (err) { return false; }
    },
    setTest: function (on) {
        this.test = !!on;
        this.endDrag();
        this.clearHud();
        var b = document.body;
        if (this.test) {
            if (b.className.indexOf("axd-testing") < 0) { b.className += " axd-testing"; }
        } else {
            b.className = b.className.replace(/\s*axd-testing/g, "");
        }
        this.paint();
    },

    /* ==================================================================
       The command palette.

       Everything the studio can do, and everything the project contains,
       in one list you type at. AutoHotkey sends the list on each refresh
       (pump, "palette") and gets back only the id of what was chosen, so
       the filtering happens at typing speed rather than at bridge speed.

       The search box is a real <input>, which is also what keeps AHK's
       global key hook out of the way: it returns early for INPUT.
       ================================================================== */
    palBuild: function () {
        var p = this.pal, self = this;
        var el = document.createElement("div");
        el.id = "axdPal";
        el.className = "axd-pal";
        el.innerHTML = '<div class="axd-pal-box">'
            + '<input id="axdPalInput" class="axd-pal-input" autocomplete="off">'
            + '<div id="axdPalList" class="axd-pal-list"></div>'
            + '<div class="axd-pal-foot">Enter to run &#183; Esc to close</div></div>';
        document.body.appendChild(el);
        p.el = el;
        p.input = document.getElementById("axdPalInput");
        p.list = document.getElementById("axdPalList");
        p.input.onkeydown = function (e) { self.palKey(e || window.event); };
        p.input.onkeyup = function (e) {
            var k = (e || window.event).keyCode;
            if (k !== 38 && k !== 40 && k !== 13 && k !== 27) { p.sel = 0; self.palRender(); }
        };
        el.onmousedown = function (e) {
            var t = (e || window.event).srcElement || (e || window.event).target;
            if (t === el) { self.palClose(); }
        };
        p.list.onclick = function (e) {
            var t = (e || window.event).srcElement || (e || window.event).target;
            while (t && t !== p.list && !t.getAttribute("data-pi")) { t = t.parentNode; }
            if (t && t.getAttribute) {
                var i = parseInt(t.getAttribute("data-pi"), 10);
                if (!isNaN(i)) { p.sel = i; self.palPick(); }
            }
        };
    },
    palOpen: function (mode) {
        var p = this.pal;
        if (!p.el) { this.palBuild(); }
        p.mode = mode || "cmd";
        p.open = true;
        p.sel = 0;
        p.input.value = "";
        p.el.style.display = "block";
        this.palRender();
        try { p.input.focus(); } catch (e) { }
    },
    palClose: function () {
        var p = this.pal;
        p.open = false;
        if (p.el) { p.el.style.display = "none"; }
        try { if (this.paper) { this.paper.focus(); } } catch (e) { }
    },
    palKey: function (e) {
        var p = this.pal, k = e.keyCode;
        if (k === 27) { this.palClose(); this.stop(e); return; }
        if (k === 13) { this.palPick(); this.stop(e); return; }
        if (k === 40) { p.sel++; this.palRender(); this.stop(e); return; }
        if (k === 38) { p.sel--; this.palRender(); this.stop(e); return; }
    },
    /* A subsequence match, scored so that matching the start of a word beats
       matching the middle of one: "adw" finds "Add a window" ahead of
       "Advanced". Nothing here is clever, but it is the difference between a
       palette you use and one you scroll. */
    palScore: function (text, q) {
        if (!q) { return 1; }
        var t = text.toLowerCase(), i = 0, j = 0, score = 0, run = 0;
        while (i < t.length && j < q.length) {
            if (t.charAt(i) === q.charAt(j)) {
                var start = (i === 0 || t.charAt(i - 1) === " " || t.charAt(i - 1) === ".");
                score += 1 + (start ? 6 : 0) + run;
                run += 2;
                j++;
            } else { run = 0; }
            i++;
        }
        return (j === q.length) ? score : 0;
    },
    palRender: function () {
        var p = this.pal, q = (p.input.value || "").toLowerCase().replace(/\s+/g, ""), hits = [], i;
        for (i = 0; i < p.items.length; i++) {
            var it = p.items[i];
            if (p.mode === "go" && !it.go) { continue; }
            var sc = this.palScore((it.label || "") + " " + (it.group || ""), q);
            if (sc > 0) { hits.push({ it: it, sc: sc }); }
        }
        hits.sort(function (a, b) { return b.sc - a.sc; });
        if (hits.length > 40) { hits = hits.slice(0, 40); }
        p.hits = hits;
        if (p.sel < 0) { p.sel = hits.length - 1; }
        if (p.sel >= hits.length) { p.sel = 0; }
        var h = "";
        for (i = 0; i < hits.length; i++) {
            var x = hits[i].it;
            h += '<div class="axd-pal-row' + (i === p.sel ? " on" : "") + '" data-pi="' + i + '">'
               + (x.icon ? '<span class="ico">&#x' + x.icon + ';</span>' : '<span class="ico"></span>')
               + '<span class="axd-pal-label">' + this.esc(x.label) + '</span>'
               + (x.group ? '<span class="axd-pal-group">' + this.esc(x.group) + '</span>' : "")
               + (x.key ? '<span class="axd-pal-key">' + this.esc(x.key) + '</span>' : "")
               + '</div>';
        }
        p.list.innerHTML = h || '<div class="axd-pal-none">Nothing matches.</div>';
        var sel = p.list.childNodes[p.sel];
        if (sel && sel.scrollIntoView) { try { sel.scrollIntoView(false); } catch (e) { } }
    },
    palPick: function () {
        var p = this.pal;
        if (!p.hits.length) { return; }
        var it = p.hits[p.sel].it;
        this.palClose();
        this.post("cmd", { id: it.id });
    },
    esc: function (s) {
        return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
};

/* =========================================================================
   AXP -- the inspector as a property grid. AutoHotkey writes the groups and
   rows (AxPanes); this arranges what it wrote, and shows it:
     arrange(az)   every note becomes a hint (its buttons lifted out, so they
                   stay), each group with hints gets an (i), and with az the
                   rows of each tab are sorted A to Z into one list
     view(tab, hints, finding)
                   the tab shown -- one with nothing in it gives way to one
                   that has something -- the hints on or off, and the tabs
                   counted; a find shows every tab
   ========================================================================= */
var AXP = {
    tab: "props",
    tabs: ["props", "layout", "events"],
    arrange: function (az) {
        var body = document.getElementById("axdRightBody");
        if (!body) { return; }
        var grps = body.querySelectorAll(".axd-grp"), i, j, k, g, notes, n, btns, box, lab, info;
        for (i = 0; i < grps.length; i++) {
            g = grps[i];
            notes = g.querySelectorAll(".axd-note");
            for (j = 0; j < notes.length; j++) {
                n = notes[j];
                /* a note's buttons are things to do, not things to read: they
                   stay in sight when the hints are put away */
                btns = n.querySelectorAll(".axd-hbtn");
                if (btns.length) {
                    box = document.createElement("div");
                    box.className = "axd-align axd-noteacts";
                    for (k = 0; k < btns.length; k++) { box.appendChild(btns[k]); }
                    n.parentNode.insertBefore(box, n);
                    if (!/\S/.test(n.innerText || "")) { n.parentNode.removeChild(n); continue; }
                }
                n.className += " axd-phint";
            }
            if (notes.length && g.id && g.id.substr(0, 4) === "grp_") {
                lab = g.querySelector(".axd-glabel");
                if (lab && !lab.querySelector(".axd-ginfo")) {
                    info = document.createElement("span");
                    info.className = "axd-ginfo ico";
                    info.setAttribute("data-ginfo", g.id.substr(4));
                    info.setAttribute("title", "What these are for");
                    info.innerHTML = "&#xE946;";
                    lab.appendChild(info);
                }
            }
        }
        if (az) { this.sortAz(body, grps); }
    },
    sortAz: function (body, grps) {
        var byTab = {}, first = {}, i, j, g, t, rows, lab, list, grp, gb;
        for (i = 0; i < grps.length; i++) {
            g = grps[i];
            t = g.getAttribute("data-tab") || "props";
            if (!first[t]) { first[t] = g; }
            rows = g.querySelectorAll(".axd-gbody > .axd-p");
            for (j = 0; j < rows.length; j++) {
                lab = rows[j].querySelector("label");
                if (!lab) { continue; }
                (byTab[t] = byTab[t] || []).push({ el: rows[j], key: (lab.innerText || "").toLowerCase() });
            }
        }
        for (t in byTab) {
            if (!byTab.hasOwnProperty(t)) { continue; }
            list = byTab[t];
            list.sort(function (a, b) { return a.key < b.key ? -1 : a.key > b.key ? 1 : 0; });
            grp = document.createElement("div");
            grp.className = "axd-grp axd-azgrp";
            grp.id = "grp_az_" + t;
            grp.setAttribute("data-tab", t);
            grp.innerHTML = '<span class="axd-glabel">A to Z</span><div class="axd-gbody"></div>';
            gb = grp.lastChild;
            for (j = 0; j < list.length; j++) { gb.appendChild(list[j].el); }
            first[t].parentNode.insertBefore(grp, first[t]);
        }
        /* a group left with nothing in it goes; one with buttons or hints stays */
        for (i = 0; i < grps.length; i++) {
            gb = grps[i].querySelector(".axd-gbody");
            if (gb && !gb.children.length) { grps[i].className += " axd-emptied"; }
        }
    },
    view: function (tab, hints, finding) {
        var right = document.getElementById("axdRight"), body = document.getElementById("axdRightBody");
        if (!right || !body) { return; }
        var grps = body.querySelectorAll(".axd-grp"), cnt = { props: 0, layout: 0, events: 0 }, i, t, el;
        for (i = 0; i < grps.length; i++) {
            if (/\baxd-emptied\b/.test(grps[i].className)) { continue; }
            t = grps[i].getAttribute("data-tab") || "props";
            if (cnt.hasOwnProperty(t)) { cnt[t]++; }
        }
        var eff = cnt[tab] ? tab : cnt.props ? "props" : cnt.layout ? "layout" : cnt.events ? "events" : "props";
        this.tab = eff;
        var cls = right.className.replace(/\s*\b(pt-\w+|axd-hints|axd-finding|axd-onetab)\b/g, "");
        cls += " pt-" + eff + (hints ? " axd-hints" : "") + (finding ? " axd-finding" : "");
        var shown = 0;
        for (i = 0; i < this.tabs.length; i++) {
            t = this.tabs[i];
            el = document.getElementById("axdPt_" + t);
            if (!el) { continue; }
            el.style.display = cnt[t] ? "" : "none";
            shown += cnt[t] ? 1 : 0;
            el.className = "axd-ptab" + (t === eff && !finding ? " on" : "");
        }
        /* how many handlers are written, on the Events tab */
        var nEv = body.querySelectorAll('.axd-grp[data-tab="events"] .axd-ev.on').length;
        el = document.getElementById("axdPtn_events");
        if (el) { el.innerHTML = nEv ? String(nEv) : ""; }
        if (shown < 2) { cls += " axd-onetab"; }
        right.className = cls;
    }
};
