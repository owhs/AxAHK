/* =========================================================================
   AxStudio.Map.js -- the program as a map (see AxStudio.Map.ahk).

   Four columns, left to right: When (what starts things), Does (what they
   run first), Uses (what that calls), Data (what it reads and writes). Each
   column is ordered by the average place of what connects to it, twice over,
   which keeps most lines short and most crossings out.

   Pick something, or type, and the map is laid out again with only what is
   in play: what you picked or what matches, in full, and what is one step
   away (or two, or three -- "Around it") in fog, read-only, with the lines
   in and out still drawn. Nothing else gets in the way. Clear, or Esc, and
   the whole program is back. Double-click opens the thing itself.

   Trident: plain DOM for the nodes, one SVG for the lines (made element by
   element: there is no innerHTML on SVG), `zoom` for size.
   ========================================================================= */

var AXM = {
    data: null, byId: {}, ins: {}, outs: {}, lanes: [1, 1, 1, 1],
    kinds: { trig: 1, call: 1, write: 1, read: 1 },
    pick: null, find: "", zoom: 1, hops: 1,
    W: 210, H: 40, GX: 300, GY: 62, TOP: 44, LEFT: 20,

    load: function (d) {
        this.data = d;
        this.byId = {}; this.ins = {}; this.outs = {};
        var i, n, e;
        for (i = 0; i < d.nodes.length; i++) {
            n = d.nodes[i];
            this.byId[n.id] = n;
            this.ins[n.id] = []; this.outs[n.id] = [];
        }
        for (i = 0; i < d.edges.length; i++) {
            e = d.edges[i];
            if (!this.byId[e.a] || !this.byId[e.b]) { continue; }
            this.outs[e.a].push(e); this.ins[e.b].push(e);
        }
        if (this.pick && !this.byId[this.pick]) { this.pick = null; }
        this.wire();
        this.render();
    },

    /* --- what is in play ------------------------------------------------- */
    /* lit[id]: 2 = picked or matching, 1 = within `hops` steps (fog) */
    visible: function () {
        var lit = {}, i, n, e, q = this.find.toLowerCase(), any = false, frontier = [], next, h, j, list, o;
        if (q) {
            for (i = 0; i < this.data.nodes.length; i++) {
                n = this.data.nodes[i];
                if ((n.label + " " + n.sub + " " + n.win).toLowerCase().indexOf(q) >= 0) { lit[n.id] = 2; frontier.push(n.id); any = true; }
            }
            /* nothing by name: what has it in its code */
            if (!any) {
                for (i = 0; i < this.data.nodes.length; i++) {
                    n = this.data.nodes[i];
                    if (n.code && n.code.toLowerCase().indexOf(q) >= 0) { lit[n.id] = 2; frontier.push(n.id); any = true; }
                }
            }
        }
        if (this.pick && lit[this.pick] !== 2) { lit[this.pick] = 2; frontier.push(this.pick); any = true; }
        for (h = 0; any && h < this.hops; h++) {
            next = [];
            for (i = 0; i < frontier.length; i++) {
                list = this.ins[frontier[i]].concat(this.outs[frontier[i]]);
                for (j = 0; j < list.length; j++) {
                    o = (list[j].a === frontier[i]) ? list[j].b : list[j].a;
                    if (!lit[o]) { lit[o] = 1; next.push(o); }
                }
            }
            frontier = next;
        }
        var nodes = [], edges = [];
        for (i = 0; i < this.data.nodes.length; i++) {
            n = this.data.nodes[i];
            if (!this.lanes[n.lane]) { continue; }
            if (any && !lit[n.id]) { continue; }
            nodes.push(n);
        }
        var shown = {};
        for (i = 0; i < nodes.length; i++) { shown[nodes[i].id] = true; }
        for (i = 0; i < this.data.edges.length; i++) {
            e = this.data.edges[i];
            if (shown[e.a] && shown[e.b] && this.kinds[e.k] !== 0) { edges.push(e); }
        }
        return { nodes: nodes, edges: edges, lit: lit, any: any };
    },
    render: function () {
        var v = this.visible();
        this.layout(v.nodes);
        this.draw(v.nodes, v.edges, v.lit, v.any);
        this.info();
        var cnt = document.getElementById("axmCount");
        if (cnt) {
            cnt.innerHTML = (v.any ? v.nodes.length + " of " : "") + this.data.nodes.length + " things, " +
                (v.any ? v.edges.length + " of " : "") + this.data.edges.length + " lines";
        }
        if (this.pick) { this.show(this.pick); }
    },

    /* --- where everything goes ------------------------------------------ */
    layout: function (nodes) {
        var cols = [[], [], [], []], i, n, c, pass, place = {};
        for (i = 0; i < nodes.length; i++) {
            n = nodes[i];
            n.row = undefined;
            place[n.id] = true;
            cols[Math.max(0, Math.min(3, n.lane))].push(n);
        }
        this.place = place;
        cols[0].sort(function (a, b) {
            return (a.win < b.win ? -1 : a.win > b.win ? 1 : 0) || (a.label.toLowerCase() < b.label.toLowerCase() ? -1 : 1);
        });
        for (i = 0; i < cols[0].length; i++) { cols[0][i].row = i; }
        for (pass = 0; pass < 2; pass++) {
            for (c = 1; c < 4; c++) {
                for (i = 0; i < cols[c].length; i++) {
                    n = cols[c][i];
                    n.key = this.bary(n, pass ? null : c);
                }
                cols[c].sort(function (a, b) { return a.key - b.key; });
                for (i = 0; i < cols[c].length; i++) { cols[c][i].row = i; }
            }
        }
        this.cols = cols;
        /* the columns share out the width there is, so lines have room to
           turn in the gaps rather than bunching in 90px; never narrower
           than 90px a gap, never wider than 260 */
        var view = document.getElementById("axmView"), used = [], u = 0;
        for (c = 0; c < 4; c++) { if (this.lanes[c] && cols[c].length) { used.push(c); } }
        var gap = 120;
        if (view && used.length > 1) {
            gap = Math.max(90, Math.min(260, (view.clientWidth / this.zoom - this.LEFT * 2 - used.length * this.W) / (used.length - 1)));
        }
        this.GX = this.W + gap;
        this.colX = [];
        var tall = 0;
        for (c = 0; c < 4; c++) {
            this.colX[c] = this.LEFT + u * this.GX;
            if (this.lanes[c] && cols[c].length) { u++; }
            for (i = 0; i < cols[c].length; i++) {
                n = cols[c][i];
                n.x = this.colX[c];
                n.y = this.TOP + i * this.GY;
            }
            tall = Math.max(tall, cols[c].length);
        }
        this.tall = tall;
        this.width = this.LEFT * 2 + Math.max(0, u - 1) * this.GX + this.W;
        this.height = this.TOP + tall * this.GY + 20;
    },
    /* the average row of the nodes linked to n that are laid out (from
       columns to its left only on the first pass, from anywhere after) */
    bary: function (n, col) {
        var sum = 0, k = 0, i, e, o, lists = [this.ins[n.id], this.outs[n.id]], L;
        for (L = 0; L < 2; L++) {
            for (i = 0; i < lists[L].length; i++) {
                e = lists[L][i];
                o = this.byId[L === 0 ? e.a : e.b];
                if (!o || !this.place[o.id] || o.row === undefined) { continue; }
                if (col !== null && o.lane >= col) { continue; }
                sum += o.row; k++;
            }
        }
        return k ? sum / k : 1e6 + (n.label.toLowerCase().charCodeAt(0) || 0);
    },

    /* --- drawing ---------------------------------------------------------- */
    esc: function (s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    },
    icon: { event: "&#xE7C9;", hotkey: "&#xE765;", timer: "&#xE916;", start: "&#xE768;", handler: "&#xE943;",
            rule: "&#xE945;", library: "&#xE82D;", "function": "&#xE8F4;", method: "&#xE8F4;", window: "&#xE737;",
            value: "&#xE8EF;", control: "&#xE71D;" },
    draw: function (nodes, edges, lit, any) {
        var host = document.getElementById("axmNodes"), svg = document.getElementById("axmSvg");
        if (!host || !svg) { return; }
        var h = [], i, n, cls, heads = ["When", "Does", "Uses", "Data"];
        for (i = 0; i < 4; i++) {
            if (!this.lanes[i] || !this.cols[i].length) { continue; }
            h.push('<div class="axm-head" style="left:' + this.colX[i] + 'px">' + heads[i] +
                   ' <span>' + this.cols[i].length + '</span></div>');
        }
        for (i = 0; i < nodes.length; i++) {
            n = nodes[i];
            cls = "axm-node k-" + n.kind + (any ? (lit[n.id] === 2 ? " lit" : " fog") : "") + (n.id === this.pick ? " picked" : "");
            h.push('<div class="' + cls + '" data-mid="' + this.esc(n.id) + '" style="left:' + n.x +
                   'px;top:' + n.y + 'px;width:' + this.W + 'px">' +
                   '<span class="ico">' + (this.icon[n.kind] || "&#xE8F4;") + '</span>' +
                   '<b>' + this.esc(n.label) + '</b><small>' + this.esc(n.sub) + (n.win ? ' &middot; ' + this.esc(n.win) : '') +
                   '</small><span class="axm-port" data-mport="' + this.esc(n.id) + '" title="Drag to another card to connect them"></span></div>');
        }
        if (!nodes.length) {
            h.push('<div class="axm-none">Nothing here matches.</div>');
        }
        host.innerHTML = h.join("");
        while (svg.firstChild) { svg.removeChild(svg.firstChild); }
        var NS = "http://www.w3.org/2000/svg", e, a, b, L, R, x1, y1, x2, y2, mx, path, d, g, yg, r, best, k;
        g = this.GX - this.W;
        var gapY = function (row) { return AXM.TOP + row * AXM.GY - (AXM.GY - AXM.H) / 2; };
        for (i = 0; i < edges.length; i++) {
            e = edges[i];
            a = this.byId[e.a]; b = this.byId[e.b];
            if (a.lane === b.lane) {           /* a call within a column loops out to the right */
                x1 = a.x + this.W; x2 = b.x + this.W; y1 = a.y + this.H / 2; y2 = b.y + this.H / 2;
                mx = x1 + 30 + Math.min(g / 2 - 10, Math.abs(y2 - y1) / 4);
                d = "M" + x1 + " " + y1 + " C" + mx + " " + y1 + " " + mx + " " + y2 + " " + x2 + " " + y2;
            } else {
                /* drawn from the one on the left to the one on the right */
                L = (a.x < b.x) ? a : b; R = (L === a) ? b : a;
                x1 = L.x + this.W; y1 = L.y + this.H / 2; x2 = R.x; y2 = R.y + this.H / 2;
                if (x2 - x1 <= g + 1) {
                    mx = (x1 + x2) / 2;
                    d = "M" + x1 + " " + y1 + " C" + mx + " " + y1 + " " + mx + " " + y2 + " " + x2 + " " + y2;
                } else {
                    /* past a column: along the gap between two rows, so the
                       line never runs through a card on the way */
                    best = 0;
                    for (r = 0; r <= this.tall; r++) {
                        if (Math.abs(gapY(r) - (y1 + y2) / 2) < Math.abs(gapY(best) - (y1 + y2) / 2)) { best = r; }
                    }
                    k = (i % 7) - 3;
                    yg = gapY(best) + k * 3;
                    d = "M" + x1 + " " + y1 +
                        " C" + (x1 + g / 2) + " " + y1 + " " + (x1 + g / 2) + " " + yg + " " + (x1 + g) + " " + yg +
                        " L" + (x2 - g) + " " + yg +
                        " C" + (x2 - g / 2) + " " + yg + " " + (x2 - g / 2) + " " + y2 + " " + x2 + " " + y2;
                }
            }
            path = document.createElementNS(NS, "path");
            path.setAttribute("d", d);
            path.setAttribute("data-a", e.a);
            path.setAttribute("data-b", e.b);
            path.setAttribute("class", "axm-e e-" + e.k + (any && (lit[e.a] === 2 || lit[e.b] === 2) ? " lit" : ""));
            svg.appendChild(path);
        }
        svg.setAttribute("width", this.width);
        svg.setAttribute("height", this.height);
        var plane = document.getElementById("axmPlane");
        plane.style.width = this.width + "px";
        plane.style.height = this.height + "px";
        plane.style.zoom = this.zoom;
    },

    /* --- the side panel --------------------------------------------------- */
    info: function () {
        var box = document.getElementById("axmInfo"), n = this.pick ? this.byId[this.pick] : null;
        if (!box) { return; }
        if (!n) {
            box.innerHTML = '<div class="axm-hint">Pick anything, or type, and the map shows only what is in play: that, ' +
                'and what it touches in fog, with the lines in and out. Double-click to open it.</div>' +
                this.around() + this.legend();
            return;
        }
        var h = '<div class="axm-ih k-' + n.kind + '"><span class="ico">' + (this.icon[n.kind] || "") + '</span><b>' +
                this.esc(n.label) + '</b><small>' + this.esc(n.sub) + (n.win ? ' &middot; ' + this.esc(n.win) : '') + '</small></div>';
        var list = function (title, edges, far) {
            if (!edges.length) { return ""; }
            var s = '<div class="axm-ish">' + title + '</div>', j, o;
            for (j = 0; j < edges.length; j++) {
                o = AXM.byId[far ? edges[j].b : edges[j].a];
                s += '<div class="axm-il" data-mgo="' + AXM.esc(o.id) + '"><span class="axm-ik e-' + edges[j].k + '"></span>' +
                     AXM.esc(o.label) + ' <small>' + AXM.esc(AXM.word(edges[j].k, far)) + '</small></div>';
            }
            return s;
        };
        h += this.around();
        h += list("Comes from", this.ins[n.id], false) + list("Goes to", this.outs[n.id], true);
        if (n.pc) {
            h += '<div class="axm-open axm-steps" data-mpc="' + this.esc(n.pc) + '"><span class="ico">&#xE8FD;</span>See it step by step</div>';
            /* a step added from here, without leaving the map */
            h += '<div class="axm-open axm-alt" data-maddstep="' + this.esc(n.pc) + '"><span class="ico">&#xE710;</span>Add a step to it...</div>';
        }
        if (n.code) { h += '<div class="axm-ish">Code</div><pre class="axm-code">' + this.esc(n.code) + '</pre>'; }
        if (n.go) { h += '<div class="axm-open' + (n.pc ? ' axm-alt' : '') + '" data-mopen="' + this.esc(n.id) + '">Open it</div>'; }
        /* a control's event: something to do about it, without code */
        if (n.id.indexOf("ev:") === 0) {
            h += '<div class="axm-open axm-alt" data-mrule="' + this.esc(n.id) + '">Add a rule for it</div>';
        }
        box.innerHTML = h;
    },
    around: function () {
        var s = '<div class="axm-ish">Around it</div><div class="axm-hops">', i;
        for (i = 1; i <= 3; i++) {
            s += '<span class="axm-chip' + (this.hops === i ? ' on' : '') + '" data-mhops="' + i + '">' +
                 (i === 1 ? "one step" : i === 2 ? "two" : "three") + '</span>';
        }
        return s + '</div>';
    },
    word: function (k, far) {
        return { call: far ? "calls it" : "called from", trig: far ? "runs it" : "started by", read: far ? "reads it" : "read by",
                 write: far ? "writes it" : "written by" }[k] || k;
    },
    /* the key, and the switch: a kind of line clicked off is not drawn */
    legend: function () {
        var s = '<div class="axm-ish">Lines <small>click to hide or show</small></div>', i,
            k = [["trig", "starts"], ["call", "calls"], ["write", "writes"], ["read", "reads"]];
        for (i = 0; i < k.length; i++) {
            s += '<div class="axm-leg' + (this.kinds[k[i][0]] === 0 ? ' off' : '') + '" data-mkind="' + k[i][0] + '">' +
                 '<span class="axm-ik e-' + k[i][0] + '"></span>' + k[i][1] + '</div>';
        }
        return s + '<div class="axm-ish">Tips</div><div class="axm-tip">Hover a card to see only its lines. ' +
               'Pick one, then <b>See it step by step</b> to read and change what it does.<br><br>' +
               '<b>Connect two:</b> drag from the dot on a card&#39;s right edge onto another -- a button onto a function, ' +
               'a control onto a value -- and say what the line should mean.</div>';
    },
    /* the line being dragged, from the card's dot to the pointer */
    dragMove: function (d, ev) {
        if (!d) { return; }
        var plane = document.getElementById("axmPlane");
        if (!plane) { return; }
        var r = plane.getBoundingClientRect(), z = this.zoom || 1;
        var x1 = d.a.x + this.W, y1 = d.a.y + this.H / 2;
        var x2 = (ev.clientX - r.left) / z, y2 = (ev.clientY - r.top) / z, mx = (x1 + x2) / 2;
        d.path.setAttribute("d", "M" + x1 + " " + y1 + " C" + mx + " " + y1 + " " + mx + " " + y2 + " " + x2 + " " + y2);
    },
    /* hovering a card: its lines, and what they reach, stand out */
    hot: function (id) {
        var svg = document.getElementById("axmSvg"), nodes = document.querySelectorAll("#axmNodes .axm-node"), i, p, near = {};
        if (!svg) { return; }
        var paths = svg.childNodes;
        for (i = 0; i < paths.length; i++) {
            p = paths[i];
            var on = id && (p.getAttribute("data-a") === id || p.getAttribute("data-b") === id);
            if (on) { near[p.getAttribute("data-a")] = 1; near[p.getAttribute("data-b")] = 1; }
            p.setAttribute("class", p.getAttribute("class").replace(/ (hot|dim)\b/g, "") + (id ? (on ? " hot" : " dim") : ""));
        }
        for (i = 0; i < nodes.length; i++) {
            var nid = nodes[i].getAttribute("data-mid");
            nodes[i].className = nodes[i].className.replace(/ (hot|cold)\b/g, "") + (id ? (near[nid] || nid === id ? " hot" : " cold") : "");
        }
    },

    /* --- hands ------------------------------------------------------------ */
    wire: function () {
        var view = document.getElementById("axmView");
        if (!view || view.getAttribute("data-wired")) { return; }
        view.setAttribute("data-wired", "1");
        var self = this, root = view.parentNode.parentNode;
        var up = function (el, attr) {
            while (el && el.getAttribute) { if (el.getAttribute(attr) !== null) { return el; } el = el.parentNode; }
            return null;
        };
        /* Connecting: drag from the dot on a card's right edge to another
           card, and AutoHotkey asks what the connection should be -- a rule,
           a step, a binding -- from what the two are. */
        var drag = null;
        root.onmousedown = function (ev) {
            ev = ev || window.event;
            var t = ev.target || ev.srcElement, el = up(t, "data-mport");
            if (!el) { return; }
            var a = self.byId[el.getAttribute("data-mport")], svg = document.getElementById("axmSvg");
            if (!a || !svg) { return; }
            var p = document.createElementNS("http://www.w3.org/2000/svg", "path");
            p.setAttribute("class", "axm-e axm-drag");
            svg.appendChild(p);
            drag = { a: a, path: p };
            ev.returnValue = false;
            if (ev.preventDefault) { ev.preventDefault(); }
            return false;
        };
        document.attachEvent ? document.attachEvent("onmousemove", function (ev) { self.dragMove(drag, ev || window.event); })
                             : document.addEventListener("mousemove", function (ev) { self.dragMove(drag, ev); });
        var end = function (ev) {
            ev = ev || window.event;
            if (!drag) { return; }
            var d = drag;
            drag = null;
            if (d.path.parentNode) { d.path.parentNode.removeChild(d.path); }
            var el = up(ev.target || ev.srcElement, "data-mid");
            if (el && el.getAttribute("data-mid") !== d.a.id) {
                self.justDragged = true;
                AXD.post("map", { act: "connect", a: d.a.id, b: el.getAttribute("data-mid") });
            }
        };
        document.attachEvent ? document.attachEvent("onmouseup", end) : document.addEventListener("mouseup", end);
        root.onclick = function (ev) {
            ev = ev || window.event;
            var t = ev.target || ev.srcElement, el;
            if (self.justDragged) { self.justDragged = false; return; }
            if ((el = up(t, "data-mid"))) {
                var id = el.getAttribute("data-mid");
                self.pick = (self.pick === id) ? null : id;
                self.render(); return;
            }
            if ((el = up(t, "data-mgo"))) { self.pick = el.getAttribute("data-mgo"); self.render(); return; }
            if ((el = up(t, "data-mopen"))) { AXD.post("map", { act: "go", id: el.getAttribute("data-mopen") }); return; }
            if ((el = up(t, "data-mrule"))) { AXD.post("map", { act: "rule", id: el.getAttribute("data-mrule") }); return; }
            if ((el = up(t, "data-mhops"))) { self.hops = +el.getAttribute("data-mhops"); self.render(); return; }
            if ((el = up(t, "data-mlane"))) {
                var li = +el.getAttribute("data-mlane");
                self.lanes[li] = self.lanes[li] ? 0 : 1;
                el.className = "axm-chip" + (self.lanes[li] ? " on" : "");
                self.render(); return;
            }
            if ((el = up(t, "data-mdo"))) { self.act(el.getAttribute("data-mdo")); return; }
            if ((el = up(t, "data-mmode"))) { AXD.post("map", { act: "mode", v: el.getAttribute("data-mmode") }); return; }
            if ((el = up(t, "data-mpc"))) { AXD.post("map", { act: "steps", key: el.getAttribute("data-mpc") }); return; }
            if ((el = up(t, "data-maddstep"))) { AXD.post("map", { act: "addstep", key: el.getAttribute("data-maddstep") }); return; }
            if ((el = up(t, "data-mkind"))) {
                var kk = el.getAttribute("data-mkind");
                self.kinds[kk] = self.kinds[kk] === 0 ? 1 : 0;
                self.render(); return;
            }
            if (t.id === "axmView" || t.id === "axmPlane" || t.id === "axmNodes") { if (self.pick) { self.pick = null; self.render(); } }
        };
        root.ondblclick = function (ev) {
            ev = ev || window.event;
            var el = up(ev.target || ev.srcElement, "data-mid");
            if (!el) { return; }
            var n = self.byId[el.getAttribute("data-mid")];
            /* a piece of code opens step by step; anything else where it is set */
            if (n.pc) { AXD.post("map", { act: "steps", key: n.pc }); }
            else if (n.go) { AXD.post("map", { act: "go", id: n.id }); }
        };
        var nodesHost = document.getElementById("axmNodes"), hotId = null;
        if (nodesHost) {
            nodesHost.onmouseover = function (ev) {
                ev = ev || window.event;
                var el = up(ev.target || ev.srcElement, "data-mid"), id = el ? el.getAttribute("data-mid") : null;
                if (id !== hotId) { hotId = id; self.hot(id); }
            };
            nodesHost.onmouseout = function (ev) {
                ev = ev || window.event;
                var to = ev.relatedTarget || ev.toElement;
                if (!to || !up(to, "data-mid")) { hotId = null; self.hot(null); }
            };
        }
        var box = document.getElementById("axmFind");
        if (box) {
            box.onkeyup = function (ev) {
                ev = ev || window.event;
                if (ev.keyCode === 27) { box.value = ""; self.pick = null; }
                if (box.value === self.find && ev.keyCode !== 27) { return; }
                self.find = box.value; self.render();
            };
        }
        view.onmousewheel = function (ev) {
            ev = ev || window.event;
            if (!ev.ctrlKey) { return; }
            self.act(ev.wheelDelta > 0 ? "in" : "out");
            ev.returnValue = false;
            return false;
        };
    },
    act: function (what) {
        var plane = document.getElementById("axmPlane"), view = document.getElementById("axmView");
        if (what === "in") { this.zoom = Math.min(2, this.zoom + 0.15); }
        else if (what === "out") { this.zoom = Math.max(0.3, this.zoom - 0.15); }
        else if (what === "fit") {
            this.zoom = Math.max(0.3, Math.min(1.5, Math.min(view.clientWidth / this.width, view.clientHeight / this.height)));
        } else if (what === "clear") {
            this.pick = null; this.find = ""; this.hops = 1;
            var box = document.getElementById("axmFind");
            if (box) { box.value = ""; }
            this.lanes = [1, 1, 1, 1];
            var chips = document.querySelectorAll("[data-mlane]"), i;
            for (i = 0; i < chips.length; i++) { chips[i].className = "axm-chip on"; }
            this.render();
            return;
        } else if (what === "rebuild") { AXD.post("map", { act: "rebuild" }); return; }
        plane.style.zoom = this.zoom;
    },
    /* bring a node into view */
    show: function (id) {
        var n = this.byId[id], view = document.getElementById("axmView");
        if (!n || !view || n.x === undefined) { return; }
        view.scrollLeft = Math.max(0, n.x * this.zoom - view.clientWidth / 3);
        view.scrollTop = Math.max(0, n.y * this.zoom - view.clientHeight / 3);
    }
};
