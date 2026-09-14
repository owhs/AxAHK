/* =========================================================================
   AxCanvas.js -- a drawing surface for Trident (IE11), any number to a page.

   Two layers, drawn together every frame:
     the picture   what AutoHotkey drew (Rect, Text, Image ...) and what the
                   user painted, kept in an offscreen canvas so the scene
                   above it can move without AutoHotkey drawing it again
     the scene     shapes with an id: they can be changed, moved, animated,
                   dragged and clicked, and are drawn again each frame

   AutoHotkey talks to it through AXCV:
       AXCV.make(id, optionsJson)     build it on the markup
       AXCV.run(id, commandsJson)     a batch of drawing commands, in one call
       AXCV.call(id, "name", argsJson)  a question (size, the picture as PNG)
   and it talks back through a function AutoHotkey hands it (AXCV.hook),
   or failing that by writing a message into #<id>_q and clicking #<id>_req
   -- one message a turn, so AutoHotkey never edits a page it is inside. Pointer work (dragging, painting, animation) never leaves the page:
   AutoHotkey hears the result, not every mouse move.

   ES5 only: this is Internet Explorer 11 (no Path2D, no ctx.ellipse, no
   isPointInStroke -- each is worked round below).
   ========================================================================= */
(function () {
    if (window.AXCV) { return; }
    var AXCV = window.AXCV = { inst: {} };
    var raf = window.requestAnimationFrame || function (f) { return window.setTimeout(f, 16); };
    function $(id) { return document.getElementById(id); }
    function num(v, d) { v = parseFloat(v); return isNaN(v) ? d : v; }
    function pixelRatio() {
        var r = window.devicePixelRatio;
        if (!r && screen.deviceXDPI && screen.logicalXDPI) { r = screen.deviceXDPI / screen.logicalXDPI; }
        return r || 1;
    }

    AXCV.make = function (id, json) {
        var o = {};
        try { o = JSON.parse(json || "{}"); } catch (e) { }
        if (AXCV.inst[id]) { AXCV.inst[id].stop(); }
        AXCV.inst[id] = new Cv(id, o);
        return 1;
    };
    AXCV.hook = function (id, fn) { var c = AXCV.inst[id]; if (c) { c.cb = fn || null; } return 1; };
    AXCV.run = function (id, json) {
        var c = AXCV.inst[id];
        if (!c) { return ""; }
        c.run(JSON.parse(json));
        return "";
    };
    AXCV.call = function (id, name, json) {
        var c = AXCV.inst[id];
        if (!c || typeof c["q_" + name] !== "function") { return ""; }
        var r = c["q_" + name].apply(c, JSON.parse(json || "[]"));
        return r == null ? "" : (typeof r === "object" ? JSON.stringify(r) : String(r));
    };

    /* ------------------------------------------------------------ colours */
    function hex2(c) {
        var m = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(c);
        if (!m) { return null; }
        var h = m[1];
        if (h.length === 3) { h = h.charAt(0) + h.charAt(0) + h.charAt(1) + h.charAt(1) + h.charAt(2) + h.charAt(2); }
        return [parseInt(h.substr(0, 2), 16), parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16)];
    }
    function mixHex(a, b, t) {
        var x = hex2(a), y = hex2(b);
        if (!x || !y) { return t < 1 ? a : b; }
        var r = [], i;
        for (i = 0; i < 3; i++) { r.push(Math.round(x[i] + (y[i] - x[i]) * t)); }
        return "#" + ((1 << 24) + (r[0] << 16) + (r[1] << 8) + r[2]).toString(16).slice(1);
    }
    var EASE = {
        linear: function (t) { return t; },
        "in": function (t) { return t * t * t; },
        out: function (t) { t = 1 - t; return 1 - t * t * t; },
        inout: function (t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; },
        back: function (t) { var c = 1.70158; t = t - 1; return 1 + (c + 1) * t * t * t + c * t * t; },
        bounce: function (t) {
            var n = 7.5625, d = 2.75;
            if (t < 1 / d) { return n * t * t; }
            if (t < 2 / d) { t -= 1.5 / d; return n * t * t + 0.75; }
            if (t < 2.5 / d) { t -= 2.25 / d; return n * t * t + 0.9375; }
            t -= 2.625 / d; return n * t * t + 0.984375;
        },
        elastic: function (t) {
            if (t === 0 || t === 1) { return t; }
            return Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * (2 * Math.PI) / 3) + 1;
        }
    };

    /* ------------------------------------------------------ SVG path data */
    /* M L H V C S Q T Z, absolute and relative (no A: the arcs of SVG need
       more than a canvas gives, and a path with one is drawn up to it) */
    function svgPath(c, d, ox, oy) {
        var tok = String(d).match(/[MmLlHhVvCcSsQqTtZz]|-?(?:\d*\.\d+|\d+)(?:e[-+]?\d+)?/g) || [];
        var i = 0, cmd = "", x = 0, y = 0, sx = 0, sy = 0, cx = 0, cy = 0, prev = "";
        function n() { return parseFloat(tok[i++]); }
        function isNum() { return i < tok.length && !/[A-Za-z]/.test(tok[i]); }
        while (i < tok.length) {
            if (/[A-Za-z]/.test(tok[i])) { cmd = tok[i++]; }
            var rel = cmd === cmd.toLowerCase(), C = cmd.toUpperCase(), a, b, e, f, g, h;
            switch (C) {
            case "M":
                a = n(); b = n(); x = rel ? x + a : a; y = rel ? y + b : b; sx = x; sy = y;
                c.moveTo(x + ox, y + oy); cmd = rel ? "l" : "L"; break;
            case "L": a = n(); b = n(); x = rel ? x + a : a; y = rel ? y + b : b; c.lineTo(x + ox, y + oy); break;
            case "H": a = n(); x = rel ? x + a : a; c.lineTo(x + ox, y + oy); break;
            case "V": a = n(); y = rel ? y + a : a; c.lineTo(x + ox, y + oy); break;
            case "C":
                a = n(); b = n(); e = n(); f = n(); g = n(); h = n();
                if (rel) { a += x; b += y; e += x; f += y; g += x; h += y; }
                c.bezierCurveTo(a + ox, b + oy, e + ox, f + oy, g + ox, h + oy); cx = e; cy = f; x = g; y = h; break;
            case "S":
                e = n(); f = n(); g = n(); h = n();
                if (rel) { e += x; f += y; g += x; h += y; }
                a = /[CS]/.test(prev) ? 2 * x - cx : x; b = /[CS]/.test(prev) ? 2 * y - cy : y;
                c.bezierCurveTo(a + ox, b + oy, e + ox, f + oy, g + ox, h + oy); cx = e; cy = f; x = g; y = h; break;
            case "Q":
                a = n(); b = n(); g = n(); h = n();
                if (rel) { a += x; b += y; g += x; h += y; }
                c.quadraticCurveTo(a + ox, b + oy, g + ox, h + oy); cx = a; cy = b; x = g; y = h; break;
            case "T":
                g = n(); h = n();
                if (rel) { g += x; h += y; }
                a = /[QT]/.test(prev) ? 2 * x - cx : x; b = /[QT]/.test(prev) ? 2 * y - cy : y;
                c.quadraticCurveTo(a + ox, b + oy, g + ox, h + oy); cx = a; cy = b; x = g; y = h; break;
            case "Z": c.closePath(); x = sx; y = sy; break;
            default: return;
            }
            prev = C;
            if (C === "Z" && isNum()) { cmd = rel ? "l" : "L"; }
        }
    }

    /* ============================================================ a canvas */
    function Cv(id, o) {
        var self = this;
        this.id = id; this.o = o; this.el = $(id);
        this.cv = this.el.getElementsByTagName("canvas")[0];
        this.ctx = this.cv.getContext("2d");
        this.pic = document.createElement("canvas");
        this.pctx = this.pic.getContext("2d");
        this.qdata = $(id + "_q"); this.req = $(id + "_req");
        this.queue = []; this.shapes = []; this.byId = {}; this.anims = []; this.imgs = {};
        this.listen = {}; this.paint = null; this.undo = []; this.drag = null; this.hot = null;
        this.bg = o.background || "";
        this.dpr = pixelRatio(); this.w = 0; this.h = 0; this.dirty = false; this.alive = true;
        this.theme = document.body.className;
        this.el.className += " axcv-live";
        this.resize();
        this.made = true;
        this.cv.onmousedown = function (e) { return self.down(e || window.event); };
        this.cv.onmousemove = function (e) { if (!self.drag && !self.stroke) { self.hover(e || window.event); } };
        this.cv.onmouseout = function () { if (!self.drag) { self.setHot(null); } };
        this.cv.oncontextmenu = function (e) { e = e || window.event; self.click(e, 2); if (e.preventDefault) { e.preventDefault(); } return false; };
        this.cv.ondblclick = function (e) { self.click(e || window.event, 0, true); };
        this.cv.onselectstart = function () { return false; };
        /* the size can change with no resize event (Grow, a page shown, a
           splitter); a look at it now and then is cheap, and the theme too */
        this.timer = window.setInterval(function () {
            if (!document.getElementById(self.id)) { self.stop(); return; }
            self.resize();
            if (document.body.className !== self.theme) { self.theme = document.body.className; self.colours = null; self.redraw(); }
        }, 250);
    }
    var P = Cv.prototype;
    P.stop = function () { this.alive = false; window.clearInterval(this.timer); };

    /* ------------------------------------------------ talking to AutoHotkey */
    P.post = function (m) {
        if (!this.req) { return; }
        this.queue.push(m);
        var self = this;
        if (!this.qTimer) { this.qTimer = window.setTimeout(function () { self.pump(); }, 0); }
    };
    P.pump = function () {
        this.qTimer = null;
        if (!this.queue.length) { return; }
        var cb = this.cb;
        if (cb) {                                   /* the function AutoHotkey handed over: all of them, at once */
            try {
                while (this.queue.length) { cb(JSON.stringify(this.queue[0])); this.queue.shift(); }
                return;
            } catch (e3) { this.cb = null; }
        }
        this.qdata.value = JSON.stringify(this.queue.shift());
        try { this.req.click(); } catch (e) { try { this.req.fireEvent("onclick"); } catch (e2) { } }
        if (this.queue.length) { var self = this; this.qTimer = window.setTimeout(function () { self.pump(); }, 0); }
    };

    /* ------------------------------------------------------------- size */
    P.resize = function () {
        var w = this.el.clientWidth, h = this.el.clientHeight, r = pixelRatio();
        if (w === this.w && h === this.h && r === this.dpr) { return; }
        var had = this.w > 0 && this.h > 0, keep = null;
        if (had) {                                   /* the picture survives a resize */
            keep = document.createElement("canvas");
            keep.width = this.pic.width; keep.height = this.pic.height;
            keep.getContext("2d").drawImage(this.pic, 0, 0);
        }
        this.w = w; this.h = h; this.dpr = r;
        var W = Math.max(1, Math.round(w * r)), H = Math.max(1, Math.round(h * r));
        this.cv.width = W; this.cv.height = H; this.cv.style.width = w + "px"; this.cv.style.height = h + "px";
        this.pic.width = W; this.pic.height = H;
        if (keep) { this.pctx.drawImage(keep, 0, 0); }
        this.pctx.setTransform(r, 0, 0, r, 0, 0);
        this.redraw(true);
        /* a canvas on a page not shown yet is 0 x 0: its first real size is news too */
        if (this.made && w > 0 && h > 0 && this.listen.resize) { this.post({ kind: "resize", w: w, h: h }); }
    };

    /* ---------------------------------------------------------- colours */
    P.col = function (c) {
        if (c == null || c === "") { return null; }
        if (typeof c !== "string") { return c; }
        var k = c.toLowerCase();
        if (k === "accent" || k === "text" || k === "back" || k === "muted") {
            if (!this.colours) {
                var s = document.createElement("span"), cs;
                s.className = "link"; s.style.display = "none";
                this.el.appendChild(s);
                cs = s.currentStyle || window.getComputedStyle(s);
                var acc = cs.color;
                this.el.removeChild(s);
                var me = this.el.currentStyle || window.getComputedStyle(this.el);
                var bd = document.body.currentStyle || window.getComputedStyle(document.body);
                this.colours = { accent: acc, text: me.color, back: bd.backgroundColor,
                                 muted: /light/.test(document.body.className) ? "rgba(0,0,0,.45)" : "rgba(255,255,255,.5)" };
            }
            return this.colours[k];
        }
        return c;
    };
    /* a fill: a colour, or a list of colours as a gradient across the shape */
    P.paintOf = function (c, v, bb, st) {
        if (!(v instanceof Array)) { return this.col(v); }
        var g, i, a = num(st.angle, 90) * Math.PI / 180;
        if (st.radial) {
            var r = Math.max(bb.w, bb.h) / 2;
            g = c.createRadialGradient(bb.x + bb.w / 2, bb.y + bb.h / 2, 0, bb.x + bb.w / 2, bb.y + bb.h / 2, r);
        } else {
            var cx = bb.x + bb.w / 2, cy = bb.y + bb.h / 2, dx = Math.sin(a) * bb.w / 2, dy = -Math.cos(a) * bb.h / 2;
            g = c.createLinearGradient(cx - dx, cy - dy, cx + dx, cy + dy);
        }
        for (i = 0; i < v.length; i++) { g.addColorStop(v.length > 1 ? i / (v.length - 1) : 0, this.col(v[i])); }
        return g;
    };

    /* ---------------------------------------------------- one thing drawn */
    function bbox(it, c) {
        var k = it.kind;
        if (k === "circle") { return { x: it.x - it.r, y: it.y - it.r, w: 2 * it.r, h: 2 * it.r }; }
        if (k === "ellipse") { return { x: it.x - it.rx, y: it.y - it.ry, w: 2 * it.rx, h: 2 * it.ry }; }
        if (k === "line") { return { x: Math.min(it.x, it.x2), y: Math.min(it.y, it.y2), w: Math.abs(it.x2 - it.x), h: Math.abs(it.y2 - it.y) }; }
        if (k === "poly" && it.pts) {
            var i, x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
            for (i = 0; i + 1 < it.pts.length; i += 2) {
                x0 = Math.min(x0, it.pts[i]); x1 = Math.max(x1, it.pts[i]);
                y0 = Math.min(y0, it.pts[i + 1]); y1 = Math.max(y1, it.pts[i + 1]);
            }
            return { x: x0 + (it.x || 0), y: y0 + (it.y || 0), w: x1 - x0, h: y1 - y0 };
        }
        if (k === "text" && c) {
            font(c, it);
            var w = c.measureText(String(it.text)).width, h = num(it.size, 14) * 1.25, ax = it.align || "left";
            return { x: it.x - (ax === "center" ? w / 2 : ax === "right" ? w : 0), y: it.y, w: w, h: h };
        }
        return { x: it.x || 0, y: it.y || 0, w: it.w || 0, h: it.h || 0 };
    }
    function font(c, it) {
        c.font = (it.italic ? "italic " : "") + (it.bold ? "bold " : "") + num(it.size, 14) + "px " +
                 (it.font ? '"' + it.font + '", ' : "") + '"Segoe UI Variable Text", "Segoe UI", sans-serif';
        c.textAlign = it.align || "left";
        c.textBaseline = it.baseline || "top";
    }
    function roundRect(c, x, y, w, h, r) {
        r = Math.max(0, Math.min(r, Math.abs(w) / 2, Math.abs(h) / 2));
        c.moveTo(x + r, y);
        c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r);
        c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r);
        c.closePath();
    }
    /* the outline of a thing, as the current path */
    P.trace = function (c, it) {
        c.beginPath();
        switch (it.kind) {
        case "rect":
            if (it.radius) { roundRect(c, it.x, it.y, it.w, it.h, num(it.radius, 0)); } else { c.rect(it.x, it.y, it.w, it.h); }
            break;
        case "circle": c.arc(it.x, it.y, Math.max(0, it.r), 0, 2 * Math.PI); break;
        case "ellipse":
            c.save(); c.translate(it.x, it.y); c.scale(Math.max(it.rx, 0.01), Math.max(it.ry, 0.01));
            c.arc(0, 0, 1, 0, 2 * Math.PI); c.restore(); break;
        case "line": c.moveTo(it.x, it.y); c.lineTo(it.x2, it.y2); break;
        case "poly":
            var p = it.pts || [], i, ox = it.x || 0, oy = it.y || 0;
            for (i = 0; i + 1 < p.length; i += 2) { if (i) { c.lineTo(p[i] + ox, p[i + 1] + oy); } else { c.moveTo(p[i] + ox, p[i + 1] + oy); } }
            if (it.close !== false && it.fill != null) { c.closePath(); }
            break;
        case "path": svgPath(c, it.d, it.x || 0, it.y || 0); break;
        case "arc":
            var a0 = num(it.start, 0) * Math.PI / 180, a1 = num(it.end, 360) * Math.PI / 180;
            if (it.pie) { c.moveTo(it.x, it.y); }
            c.arc(it.x, it.y, Math.max(0, it.r), a0 - Math.PI / 2, a1 - Math.PI / 2);
            if (it.pie) { c.closePath(); }
            break;
        }
    };
    P.draw = function (c, it) {
        if (it.hidden) { return; }
        var bb = bbox(it, c);
        c.save();
        if (it.opacity != null) { c.globalAlpha = Math.max(0, Math.min(1, num(it.opacity, 1))); }
        if (it.blend) { try { c.globalCompositeOperation = it.blend; } catch (e) { } }
        if (it.rotate) {
            var cx = it.kind === "circle" || it.kind === "ellipse" || it.kind === "arc" ? it.x : bb.x + bb.w / 2;
            var cy = it.kind === "circle" || it.kind === "ellipse" || it.kind === "arc" ? it.y : bb.y + bb.h / 2;
            c.translate(cx, cy); c.rotate(num(it.rotate, 0) * Math.PI / 180); c.translate(-cx, -cy);
        }
        if (it.shadow) {
            var s = String(it.shadow).split(/\s+/);
            c.shadowColor = this.col(s[0]) || "rgba(0,0,0,.4)";
            c.shadowBlur = num(s[1], 8); c.shadowOffsetX = num(s[2], 0); c.shadowOffsetY = num(s[3], 2);
        }
        if (it.kind === "text") {
            font(c, it);
            var lines = String(it.text).split("\n"), lh = num(it.size, 14) * 1.3, i;
            if (it.fill != null || it.stroke == null) { c.fillStyle = this.paintOf(c, it.fill != null ? it.fill : "text", bb, it); }
            for (i = 0; i < lines.length; i++) {
                if (it.stroke != null) {
                    c.lineWidth = num(it.width, 1); c.strokeStyle = this.col(it.stroke);
                    c.strokeText(lines[i], it.x, it.y + i * lh);
                }
                if (it.fill != null || it.stroke == null) { c.fillText(lines[i], it.x, it.y + i * lh); }
            }
        } else if (it.kind === "image") {
            var im = this.image(it.src);
            if (im && im.done) {
                var w = it.w || im.width, h = it.h || (it.w ? im.height * it.w / im.width : im.height);
                if (it.radius) { this.trace(c, { kind: "rect", x: it.x, y: it.y, w: w, h: h, radius: it.radius }); c.clip(); }
                c.drawImage(im, it.x, it.y, w, h);
            }
        } else {
            this.trace(c, it);
            var line = it.kind === "line" || (it.kind === "poly" && it.fill == null) || (it.kind === "arc" && !it.pie);
            if (it.fill != null && !line) { c.fillStyle = this.paintOf(c, it.fill, bb, it); c.fill(); }
            if (it.stroke != null || line) {
                c.shadowColor = it.fill != null && !line ? "transparent" : c.shadowColor;
                c.lineWidth = num(it.width, line ? 2 : 1);
                c.strokeStyle = this.paintOf(c, it.stroke != null ? it.stroke : "text", bb, it);
                c.lineCap = it.cap || (line ? "round" : "butt"); c.lineJoin = it.join || "round";
                if (it.dash && c.setLineDash) { c.setLineDash(it.dash); }
                c.stroke();
            }
        }
        c.restore();
    };
    P.image = function (src) {
        if (!src) { return null; }
        var im = this.imgs[src], self = this;
        if (!im) {
            im = this.imgs[src] = new Image();
            im.onload = function () {
                im.done = true;
                var p = im.waiting || [], i;
                im.waiting = null;
                for (i = 0; i < p.length; i++) { self.draw(self.pctx, p[i]); }
                self.redraw();
            };
            im.src = src;
        }
        return im;
    };

    /* ----------------------------------------------------------- frames */
    P.redraw = function (now) {
        if (now) { this.frame(); return; }
        if (this.dirty) { return; }
        this.dirty = true;
        var self = this;
        raf(function () { self.frame(); });
    };
    P.frame = function () {
        this.dirty = false;
        if (!this.alive) { return; }
        var c = this.ctx, r = this.dpr, t = new Date().getTime(), i, a, busy = false;
        for (i = this.anims.length - 1; i >= 0; i--) {
            a = this.anims[i];
            if (!this.byId[a.s.id]) { this.anims.splice(i, 1); continue; }
            var p = Math.min(1, (t - a.t0) / a.ms), e = (EASE[a.ease] || EASE.out)(p), k;
            for (k in a.to) {
                if (typeof a.to[k] === "number") { a.s[k] = a.from[k] + (a.to[k] - a.from[k]) * e; }
                else if (typeof a.to[k] === "string" && hex2(a.to[k])) { a.s[k] = mixHex(a.from[k], a.to[k], e); }
                else if (p >= 1) { a.s[k] = a.to[k]; }
            }
            if (p >= 1) {
                this.anims.splice(i, 1);
                if (a.token) { this.post({ kind: "done", token: a.token, id: a.s.id }); }
            } else { busy = true; }
        }
        c.setTransform(1, 0, 0, 1, 0, 0);
        c.clearRect(0, 0, this.cv.width, this.cv.height);
        if (this.bg) { c.fillStyle = this.col(this.bg); c.fillRect(0, 0, this.cv.width, this.cv.height); }
        c.drawImage(this.pic, 0, 0);
        c.setTransform(r, 0, 0, r, 0, 0);
        for (i = 0; i < this.shapes.length; i++) { this.draw(c, this.shapes[i]); }
        if (busy) { this.redraw(); }
    };

    /* --------------------------------------------------------- commands */
    function lower(o) {
        var r = {}, k;
        for (k in o) { if (o.hasOwnProperty(k)) { r[k.toLowerCase()] = o[k]; } }
        return r;
    }
    function item(kind, geo, st) {
        var it = lower(st || {}), k;
        it.kind = kind;
        for (k in geo) { if (geo.hasOwnProperty(k)) { it[k] = geo[k]; } }
        return it;
    }
    P.run = function (cmds) {
        var i, m, c = this.pctx, it;
        for (i = 0; i < cmds.length; i++) {
            m = cmds[i];
            switch (m[0]) {
            case "clear":
                c.save(); c.setTransform(1, 0, 0, 1, 0, 0);
                c.clearRect(0, 0, this.pic.width, this.pic.height);
                if (m[1]) { c.fillStyle = this.col(m[1]); c.fillRect(0, 0, this.pic.width, this.pic.height); }
                c.restore(); this.undo = []; break;
            case "rect": this.draw(c, item("rect", { x: m[1], y: m[2], w: m[3], h: m[4] }, m[5])); break;
            case "circle": this.draw(c, item("circle", { x: m[1], y: m[2], r: m[3] }, m[4])); break;
            case "ellipse": this.draw(c, item("ellipse", { x: m[1], y: m[2], rx: m[3], ry: m[4] }, m[5])); break;
            case "arc": this.draw(c, item("arc", { x: m[1], y: m[2], r: m[3], start: m[4], end: m[5] }, m[6])); break;
            case "line": this.draw(c, item("line", { x: m[1], y: m[2], x2: m[3], y2: m[4] }, m[5])); break;
            case "poly": this.draw(c, item("poly", { pts: m[1] }, m[2])); break;
            case "path": this.draw(c, item("path", { d: m[1] }, m[2])); break;
            case "text": this.draw(c, item("text", { x: m[1], y: m[2], text: m[3] }, m[4])); break;
            case "image":
                it = item("image", { src: m[1], x: m[2], y: m[3], w: m[4], h: m[5] }, m[6]);
                var im = this.image(it.src);
                if (im.done) { this.draw(c, it); } else { (im.waiting = im.waiting || []).push(it); }
                break;
            case "ctx":                             /* anything else a 2D context does */
                try {
                    if (m[1].charAt(0) === "=") { c[m[1].substr(1)] = m[2]; }
                    else { c[m[1]].apply(c, m[2] || []); }
                } catch (e) { }
                break;
            case "bg": this.bg = m[1] || ""; break;
            case "listen": this.listen[m[1]] = !!m[2]; break;
            case "paint": this.paint = m[1] ? lower(m[1]) : null; this.cv.style.cursor = this.paint ? "crosshair" : ""; break;
            case "undo": this.q_undo(); break;
            case "add": this.add(m[1], m[2], lower(m[3] || {})); break;
            case "set": this.set(m[1], lower(m[2] || {})); break;
            case "del": this.del(m[1]); break;
            case "wipe": this.shapes = []; this.byId = {}; this.anims = []; break;
            case "order": this.order(m[1], m[2]); break;
            case "anim": this.anim(m[1], lower(m[2] || {}), num(m[3], 400), m[4] || "out", m[5] || 0); break;
            }
        }
        this.redraw();
    };

    /* ------------------------------------------------------------ scene */
    P.add = function (id, kind, props) {
        if (this.byId[id]) { this.del(id); }
        props.kind = kind; props.id = id;
        this.shapes.push(props); this.byId[id] = props;
        if (kind === "image") { this.image(props.src); }
    };
    P.set = function (id, props) {
        var s = this.byId[id], k;
        if (!s) { return; }
        for (k in props) { if (props.hasOwnProperty(k)) { s[k] = props[k]; } }
        if (s.kind === "image") { this.image(s.src); }
    };
    P.del = function (id) {
        var s = this.byId[id], i;
        if (!s) { return; }
        delete this.byId[id];
        for (i = 0; i < this.shapes.length; i++) { if (this.shapes[i] === s) { this.shapes.splice(i, 1); break; } }
        if (this.hot === s) { this.hot = null; }
    };
    P.order = function (id, where) {
        var s = this.byId[id], i;
        if (!s) { return; }
        for (i = 0; i < this.shapes.length; i++) { if (this.shapes[i] === s) { this.shapes.splice(i, 1); break; } }
        if (where === "back") { this.shapes.unshift(s); } else { this.shapes.push(s); }
    };
    P.anim = function (id, to, ms, ease, token) {
        var s = this.byId[id], k, from = {}, i;
        if (!s) { return; }
        for (i = this.anims.length - 1; i >= 0; i--) {           /* a new move of the same property wins */
            for (k in to) { if (this.anims[i].s === s && k in this.anims[i].to) { delete this.anims[i].to[k]; } }
        }
        for (k in to) { from[k] = s[k] != null ? s[k] : (typeof to[k] === "number" ? 0 : to[k]); }
        this.anims.push({ s: s, from: from, to: to, t0: new Date().getTime(), ms: Math.max(1, ms), ease: ease, token: token });
    };

    /* ------------------------------------------------------------ the pointer */
    P.pos = function (e) {
        var r = this.cv.getBoundingClientRect();
        return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    function segDist(px, py, x1, y1, x2, y2) {
        var dx = x2 - x1, dy = y2 - y1, l = dx * dx + dy * dy, t = l ? ((px - x1) * dx + (py - y1) * dy) / l : 0;
        t = Math.max(0, Math.min(1, t));
        dx = x1 + t * dx - px; dy = y1 + t * dy - py;
        return Math.sqrt(dx * dx + dy * dy);
    }
    /* the topmost shape under a point that takes the pointer */
    P.hit = function (x, y) {
        var c = this.ctx, r = this.dpr, i, s, bb, px, py, a, cx, cy, j, d;
        for (i = this.shapes.length - 1; i >= 0; i--) {
            s = this.shapes[i];
            if (s.hidden || s.hit === false || s.hit === 0) { continue; }
            px = x; py = y;
            bb = bbox(s, c);
            if (s.rotate) {                         /* the point turned back into the shape's own frame */
                cx = s.kind === "circle" || s.kind === "ellipse" || s.kind === "arc" ? s.x : bb.x + bb.w / 2;
                cy = s.kind === "circle" || s.kind === "ellipse" || s.kind === "arc" ? s.y : bb.y + bb.h / 2;
                a = -num(s.rotate, 0) * Math.PI / 180;
                px = cx + (x - cx) * Math.cos(a) - (y - cy) * Math.sin(a);
                py = cy + (x - cx) * Math.sin(a) + (y - cy) * Math.cos(a);
            }
            if (s.kind === "text" || s.kind === "image") {
                if (s.kind === "image") { var im = this.image(s.src); bb.w = s.w || (im && im.width) || 0; bb.h = s.h || (im && im.height) || 0; }
                if (px >= bb.x && px <= bb.x + bb.w && py >= bb.y && py <= bb.y + bb.h) { return s; }
                continue;
            }
            if (s.kind === "line" || (s.kind === "poly" && s.fill == null) || (s.kind === "arc" && !s.pie)) {
                d = num(s.width, 2) / 2 + 4;
                if (s.kind === "line") { if (segDist(px, py, s.x, s.y, s.x2, s.y2) <= d) { return s; } continue; }
                if (s.kind === "poly") {
                    for (j = 0; j + 3 < (s.pts || []).length; j += 2) {
                        if (segDist(px, py, s.pts[j] + (s.x || 0), s.pts[j + 1] + (s.y || 0), s.pts[j + 2] + (s.x || 0), s.pts[j + 3] + (s.y || 0)) <= d) { return s; }
                    }
                    continue;
                }
            }
            c.save(); c.setTransform(r, 0, 0, r, 0, 0);
            this.trace(c, s);
            var inside = c.isPointInPath(px * r, py * r);
            c.restore();
            if (inside) { return s; }
        }
        return null;
    };
    P.setHot = function (s) {
        if (s === this.hot) { return; }
        var was = this.hot;
        this.hot = s;
        this.cv.style.cursor = this.paint ? "crosshair" : (s && (s.drag || s.cursor)) ? (s.cursor || "move") : "";
        if (this.listen.hover) { this.post({ kind: "hover", id: s ? s.id : "", was: was ? was.id : "" }); }
    };
    P.hover = function (e) { var p = this.pos(e); this.setHot(this.hit(p.x, p.y)); };
    P.click = function (e, button, dbl) {
        var p = this.pos(e), s = this.hit(p.x, p.y);
        if (this.listen.click) { this.post({ kind: dbl ? "dblclick" : "click", id: s ? s.id : "", x: Math.round(p.x), y: Math.round(p.y), button: button }); }
    };
    P.down = function (e) {
        var p = this.pos(e), s = this.hit(p.x, p.y), self = this, left = e.button !== 2 && e.button !== 4;
        if (!left) { return; }
        var start = { x: p.x, y: p.y }, moved = false;
        if (s && s.drag) {
            this.order(s.id, "front");
            this.drag = { s: s, last: p };
        } else if (this.paint) {
            this.beginStroke(p);
        }
        document.onmousemove = function (ev) {
            ev = ev || window.event;
            var q = self.pos(ev);
            if (Math.abs(q.x - start.x) + Math.abs(q.y - start.y) > 3) { moved = true; }
            if (self.drag) {
                var dx = q.x - self.drag.last.x, dy = q.y - self.drag.last.y, d = self.drag.s;
                if (d.drag === "x") { dy = 0; } else if (d.drag === "y") { dx = 0; }
                d.x = (d.x || 0) + dx; d.y = (d.y || 0) + dy;
                if (d.kind === "line") { d.x2 += dx; d.y2 += dy; }
                if (d.bounds !== false) {                 /* kept on the canvas */
                    var b = bbox(d, self.ctx), fx = 0, fy = 0;
                    if (b.x < 0) { fx = -b.x; } else if (b.x + b.w > self.w) { fx = self.w - b.x - b.w; }
                    if (b.y < 0) { fy = -b.y; } else if (b.y + b.h > self.h) { fy = self.h - b.y - b.h; }
                    d.x += fx; d.y += fy; if (d.kind === "line") { d.x2 += fx; d.y2 += fy; }
                }
                self.drag.last = q;
                self.redraw();
            } else if (self.stroke) {
                self.moveStroke(q);
            }
            return false;
        };
        document.onmouseup = function () {
            document.onmousemove = null; document.onmouseup = null;
            if (self.drag) {
                var d = self.drag.s;
                self.drag = null;
                if (moved) {
                    if (self.listen.drop) { self.post({ kind: "drop", id: d.id, x: Math.round(d.x), y: Math.round(d.y) }); }
                    return;
                }
            }
            if (self.stroke) { self.endStroke(); if (moved) { return; } }
            if (!moved && self.listen.click) {
                self.post({ kind: "click", id: s ? s.id : "", x: Math.round(start.x), y: Math.round(start.y), button: 1 });
            }
        };
        if (e.preventDefault) { e.preventDefault(); }
        return false;
    };

    /* ------------------------------------------------------------ painting */
    P.snap = function () {
        try {
            this.undo.push(this.pctx.getImageData(0, 0, this.pic.width, this.pic.height));
            if (this.undo.length > 25) { this.undo.shift(); }
        } catch (e) { }
    };
    P.q_undo = function () {
        var d = this.undo.pop();
        if (!d) { return 0; }
        this.pctx.putImageData(d, 0, 0);
        this.redraw();
        return 1;
    };
    P.brush = function () {
        var c = this.pctx, b = this.paint;
        c.lineCap = "round"; c.lineJoin = "round";
        c.lineWidth = num(b.size, 4);
        c.strokeStyle = this.col(b.color || "text");
        c.globalAlpha = b.opacity != null ? num(b.opacity, 1) : 1;
        c.globalCompositeOperation = b.eraser ? "destination-out" : "source-over";
    };
    P.beginStroke = function (p) {
        this.snap();
        this.stroke = { pts: [p] };
        var c = this.pctx;
        c.save(); this.brush();
        c.beginPath(); c.arc(p.x, p.y, c.lineWidth / 2, 0, 2 * Math.PI);
        c.fillStyle = c.strokeStyle; c.fill();
        c.restore();
        this.redraw();
    };
    P.moveStroke = function (q) {
        var s = this.stroke, pts = s.pts, c = this.pctx, a = pts[pts.length - 1];
        pts.push(q);
        c.save(); this.brush();
        c.beginPath();
        if (pts.length < 3) { c.moveTo(a.x, a.y); c.lineTo(q.x, q.y); }
        else {                                              /* through the midpoints: a smooth line */
            var b = pts[pts.length - 3];
            c.moveTo((b.x + a.x) / 2, (b.y + a.y) / 2);
            c.quadraticCurveTo(a.x, a.y, (a.x + q.x) / 2, (a.y + q.y) / 2);
        }
        c.stroke(); c.restore();
        this.redraw();
    };
    P.endStroke = function () {
        this.stroke = null;
        if (this.listen.paint) { this.post({ kind: "paint" }); }
    };

    /* ------------------------------------------------------------ questions */
    P.q_size = function () { this.resize(); return { w: this.w, h: this.h }; };    /* measured now, not at the last look */
    P.q_png = function (withScene) {
        if (withScene === 0) { return this.pic.toDataURL("image/png"); }
        this.frame();
        return this.cv.toDataURL("image/png");
    };
    P.q_shape = function (id) {
        var s = this.byId[id], r = {}, k;
        if (!s) { return ""; }
        for (k in s) { if (s.hasOwnProperty(k) && typeof s[k] !== "function") { r[k] = s[k]; } }
        return r;
    };
    P.q_at = function (x, y) { var s = this.hit(x, y); return s ? s.id : ""; };
})();
