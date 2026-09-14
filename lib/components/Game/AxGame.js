/* =========================================================================
   AxGame.js -- a small low-poly 3D game engine for Trident (IE11).

   The page does what has to happen every frame; AutoHotkey does the rules.

     here (60 steps a second)            AutoHotkey (a "tick", ~30 a second)
     ------------------------            -----------------------------------
     the keyboard                        what the keys mean for the game
     movement, gravity, the ground       spawning, scoring, lives, levels
     behaviours: control, chase, spin,   what a collision means
       bob, roll, life, bounds
     collisions between tagged things    the camera, the world, the HUD
     particles, the camera, rendering    anything else: it is your script

   Each tick carries the keys held and just pressed, the collisions since the
   last one, and the state of every entity being watched; AutoHotkey answers
   with a batch of commands (AXGE.run) and an "ack", which is how the round
   trip is timed. Nothing waits on AutoHotkey: a slow tick costs latency in
   the rules, never frames.

   The tick goes to AutoHotkey through a function it handed the page
   (AXGE.hook), not a click on a hidden element: a direct call costs under a
   microsecond, a click runs the library's whole click path (~0.2 ms and up).
   AutoHotkey only files the message there and runs the rules on a thread of
   its own after the frame is out.

   Smoothness: the world steps at a fixed 60 a second, and every frame is
   drawn between the last two steps (interpolated), so motion stays even on a
   screen that is not refreshing at exactly 60, or when a frame comes late.

   The renderer: flat-shaded triangles, back faces culled, clipped against
   the near plane, sorted far to near (painter's algorithm), with a light,
   fog, a sky gradient, a tiled ground that follows the camera and blob
   shadows. The ground is four fills and a fog gradient however many tiles
   it has; anything off the screen is skipped before it is transformed; no
   arrays are made per polygon. ES5 only: this is Internet Explorer 11.
   ========================================================================= */
(function () {
    if (window.AXGE) { return; }
    var AXGE = window.AXGE = { inst: {}, meshes: {} };
    var raf = window.requestAnimationFrame || function (f) { return window.setTimeout(f, 16); };
    var D2R = Math.PI / 180, STEP = 1 / 60;
    function $(id) { return document.getElementById(id); }
    function now() { return window.performance && performance.now ? performance.now() : new Date().getTime(); }
    function num(v, d) { v = parseFloat(v); return isNaN(v) ? d : v; }
    function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
    function lower(o) {
        var r = {}, k;
        for (k in o) { if (o.hasOwnProperty(k)) { r[k.toLowerCase()] = (o[k] && typeof o[k] === "object" && !(o[k] instanceof Array)) ? lower(o[k]) : o[k]; } }
        return r;
    }
    var HEX = [];
    (function () { for (var i = 0; i < 256; i++) { HEX.push((i < 16 ? "0" : "") + i.toString(16)); } })();
    function hex3(r, g, b) {                                   /* a colour string without a regex or a join */
        r = (r + 0.5) | 0; g = (g + 0.5) | 0; b = (b + 0.5) | 0;
        return "#" + HEX[r < 0 ? 0 : r > 255 ? 255 : r] + HEX[g < 0 ? 0 : g > 255 ? 255 : g] + HEX[b < 0 ? 0 : b > 255 ? 255 : b];
    }
    var rgbCache = {};
    function rgb(c) {
        var k = c || "", hit = rgbCache[k];
        if (hit) { return hit; }
        return (rgbCache[k] = parseRgb(k));
    }
    function parseRgb(c) {
        var m = /^#([0-9a-f]{6})$/i.exec(c || "");
        if (m) { var n = parseInt(m[1], 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
        m = /^#([0-9a-f]{3})$/i.exec(c || "");
        if (m) { return [parseInt(m[1].charAt(0) + m[1].charAt(0), 16), parseInt(m[1].charAt(1) + m[1].charAt(1), 16), parseInt(m[1].charAt(2) + m[1].charAt(2), 16)]; }
        return [200, 200, 200];
    }

    /* ----------------------------------------------------------- vectors */
    function sub(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; }
    function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
    function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
    function norm(a) { var l = Math.sqrt(dot(a, a)) || 1; return [a[0] / l, a[1] / l, a[2] / l]; }

    /* ------------------------------------------------------------ meshes */
    /* A mesh is {v: [[x,y,z]...], f: [[a,b,c]...]} around the origin. Faces
       are turned to face outwards here (from the middle of the mesh), so a
       mesh can be written without minding the winding -- for shapes that
       are convex, which low poly nearly always is. */
    function addMesh(name, v, f) {
        var c = [0, 0, 0], i, j;
        for (i = 0; i < v.length; i++) { for (j = 0; j < 3; j++) { c[j] += v[i][j] / v.length; } }
        var faces = [];
        for (i = 0; i < f.length; i++) {
            var a = v[f[i][0]], b = v[f[i][1]], d = v[f[i][2]];
            var n = cross(sub(b, a), sub(d, a)), m = [(a[0] + b[0] + d[0]) / 3 - c[0], (a[1] + b[1] + d[1]) / 3 - c[1], (a[2] + b[2] + d[2]) / 3 - c[2]];
            faces.push(dot(n, m) < 0 ? [f[i][0], f[i][2], f[i][1], f[i][3]] : f[i].slice(0));
        }
        var r = 0;
        for (i = 0; i < v.length; i++) { r = Math.max(r, Math.sqrt(dot(v[i], v[i]))); }
        AXGE.meshes[name] = { v: v, f: faces, r: r };
    }
    (function () {
        var p = (1 + Math.sqrt(5)) / 2, s = 0.5 / Math.sqrt(1 + p * p);
        addMesh("cube", [[-.5, -.5, -.5], [.5, -.5, -.5], [.5, .5, -.5], [-.5, .5, -.5], [-.5, -.5, .5], [.5, -.5, .5], [.5, .5, .5], [-.5, .5, .5]],
            [[0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6], [0, 4, 5], [0, 5, 1], [3, 2, 6], [3, 6, 7], [0, 3, 7], [0, 7, 4], [1, 5, 6], [1, 6, 2]]);
        addMesh("tetra", [[.5, .5, .5], [-.5, -.5, .5], [-.5, .5, -.5], [.5, -.5, -.5]], [[0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]]);
        addMesh("octa", [[.5, 0, 0], [-.5, 0, 0], [0, .5, 0], [0, -.5, 0], [0, 0, .5], [0, 0, -.5]],
            [[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]]);
        addMesh("pyramid", [[-.5, -.5, -.5], [.5, -.5, -.5], [.5, -.5, .5], [-.5, -.5, .5], [0, .5, 0]],
            [[0, 1, 2], [0, 2, 3], [0, 4, 1], [1, 4, 2], [2, 4, 3], [3, 4, 0]]);
        addMesh("ico", [[-s, p * s, 0], [s, p * s, 0], [-s, -p * s, 0], [s, -p * s, 0], [0, -s, p * s], [0, s, p * s], [0, -s, -p * s], [0, s, -p * s],
                        [p * s, 0, -s], [p * s, 0, s], [-p * s, 0, -s], [-p * s, 0, s]],
            [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
             [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]);
        var hv = [], hf = [], i;                          /* a hexagonal prism */
        for (i = 0; i < 6; i++) { var a = i * Math.PI / 3; hv.push([.5 * Math.cos(a), .5, .5 * Math.sin(a)], [.5 * Math.cos(a), -.5, .5 * Math.sin(a)]); }
        for (i = 0; i < 6; i++) {
            var t = i * 2, u = ((i + 1) % 6) * 2;
            hf.push([t, u, u + 1], [t, u + 1, t + 1]);
            if (i > 0 && i < 5) { hf.push([0, u, t], [1, t + 1, u + 1]); }
        }
        addMesh("prism", hv, hf);
        addMesh("ship", [[0, 0, -1.1], [-.85, 0, .6], [.85, 0, .6], [0, .42, .35], [0, -.24, .35], [0, .06, .78]],
            [[0, 1, 3], [0, 3, 2], [0, 4, 1], [0, 2, 4], [1, 5, 3], [3, 5, 2], [1, 4, 5], [4, 2, 5]]);
    })();

    AXGE.make = function (id, json) {
        var o = {};
        try { o = lower(JSON.parse(json || "{}")); } catch (e) { }
        if (AXGE.inst[id]) { AXGE.inst[id].alive = false; }
        AXGE.inst[id] = new Game(id, o);
        return 1;
    };
    /* AutoHotkey hands over the function the ticks go to */
    AXGE.hook = function (id, fn) { var g = AXGE.inst[id]; if (g) { g.cb = fn || null; } return 1; };
    AXGE.run = function (id, json) { var g = AXGE.inst[id]; if (g) { g.run(JSON.parse(json)); } return ""; };
    AXGE.call = function (id, name, json) {
        var g = AXGE.inst[id];
        if (!g || typeof g["q_" + name] !== "function") { return ""; }
        var r = g["q_" + name].apply(g, JSON.parse(json || "[]"));
        return r == null ? "" : (typeof r === "object" ? JSON.stringify(r) : String(r));
    };

    /* ============================================================== a game */
    var KEYS = { 37: "left", 38: "up", 39: "right", 40: "down", 32: "space", 13: "enter", 27: "escape", 16: "shift", 17: "ctrl", 9: "tab" };
    (function () {                                         /* every letter and digit, by its own name */
        var i;
        for (i = 65; i <= 90; i++) { KEYS[i] = String.fromCharCode(i + 32); }
        for (i = 48; i <= 57; i++) { KEYS[i] = String.fromCharCode(i); }
    })();
    function Game(id, o) {
        var self = this;
        this.id = id; this.el = $(id); this.alive = true;
        this.cv = this.el.getElementsByTagName("canvas")[0];
        this.ctx = this.cv.getContext("2d");
        this.qdata = $(id + "_q"); this.req = $(id + "_req");
        this.ents = []; this.byId = {}; this.hud = {}; this.contacts = {}; this.hits = [];
        this.keys = {}; this.pressed = {}; this.watch = {}; this.pn = 0; this.gone = [];
        this.world = { gravity: 22, sky: ["#1b2440", "#7a93c4"], fog: [18, 55], fogcolor: "", ambient: 0.38,
                       light: norm([-0.45, 0.85, 0.35]), ground: { tile: 4, colors: ["#3f6f4a", "#47794f"], radius: 10 },
                       bounds: 26, timescale: 1, paused: false, shake: 0,
                       mode: String(o.mode || "3d").toLowerCase(), tile: 32, zoom: 1, back: "#0d0f14" };
        this.map = null; this.sprites = {}; this.sprCache = {};
        this.debug = { stats: true, colliders: false, wire: false };
        this.cam = { follow: "", dist: 13, height: 8.5, fov: 60, eye: [0, 8.5, 13], at: [0, 1, 0], x: 0, y: 8.5, z: 13, tx: 0, ty: 1, tz: 0, smooth: 6 };
        this.tickHz = num(o.tick, 30); this.tickAcc = 0; this.seq = 0; this.sent = {}; this.waiting = false; this.waitSince = 0;
        this.stat = { fps: 0, ms: 0, tris: 0, ents: 0, rtt: 0, logic: 0, ticks: 0, tickHz: 0, bytes: 0 };
        this.fpsN = 0; this.fpsT = now(); this.tickN = 0; this.acc = 0; this.last = now(); this.time = 0; this.frame = 0;
        this.el.className += " axge-live";
        this.el.tabIndex = 0;
        this.el.onmousedown = function () { try { self.el.focus(); } catch (e) { } };
        function key(e, down) {
            e = e || window.event;
            if (!self.alive || !self.focused()) { return; }
            var k = KEYS[e.keyCode];
            if (!k) { return; }
            if (down && !self.keys[k]) { self.pressed[k] = 1; }
            self.keys[k] = down ? 1 : 0;
            if (k !== "tab" && k !== "escape") {
                if (e.preventDefault) { e.preventDefault(); }
                e.returnValue = false;
            }
        }
        document.addEventListener("keydown", function (e) { key(e, true); }, true);
        document.addEventListener("keyup", function (e) { key(e, false); }, true);
        window.addEventListener("blur", function () { self.keys = {}; });
        try { this.el.focus(); } catch (e) { }
        this.resize();
        raf(function tick() { if (!self.alive) { return; } self.loop(); raf(tick); });
    }
    var G = Game.prototype;
    G.focused = function () {
        var a = document.activeElement;
        return a === this.el || (a && this.el.contains && this.el.contains(a)) || a === document.body || !a;
    };

    /* ------------------------------------------------ talking to AutoHotkey */
    G.post = function (m) {
        var s = JSON.stringify(m), cb = this.cb;
        this.stat.bytes = s.length;
        if (cb) {
            try { cb(s); return; } catch (e) { this.cb = null; }   /* gone (the script ended): the old way */
        }
        this.qdata.value = s;
        try { this.req.click(); } catch (e3) { try { this.req.fireEvent("onclick"); } catch (e2) { } }
    };
    G.sendTick = function () {
        var t = now(), k, w = {}, e, i, list = null;
        for (k in this.watch) {
            e = this.byId[k];
            w[k] = e ? { x: r2(e.x), y: r2(e.y), z: r2(e.z), vx: r2(e.vx), vy: r2(e.vy), vz: r2(e.vz), ry: r2(e.ry), fx: r2(e.fx), fy: r2(e.fy) } : null;
        }
        if (this.wantList && (this.seq % 6 === 0)) {                  /* the debug panel's list, a few times a second */
            list = [];
            for (i = 0; i < this.ents.length && i < 200; i++) { e = this.ents[i]; if (!e.particle) { list.push([e.id, e.tag || "", r2(e.x), r2(e.y), r2(e.z)]); } }
        }
        var keysHeld = [], pressed = [];
        for (k in this.keys) { if (this.keys[k]) { keysHeld.push(k); } }
        for (k in this.pressed) { pressed.push(k); }
        this.pressed = {};
        var m = { kind: "tick", seq: ++this.seq, t: r2(this.time), keys: keysHeld, pressed: pressed, hits: this.hits, gone: this.gone, watch: w,
                  stats: this.stat, list: list };
        this.hits = []; this.gone = [];
        this.sent[this.seq] = t;
        this.waiting = true; this.waitSince = t;
        this.post(m);
    };
    function r2(v) { return Math.round((v || 0) * 100) / 100; }

    /* ------------------------------------------------------------ commands */
    G.run = function (cmds) {
        var i, m, e;
        for (i = 0; i < cmds.length; i++) {
            m = cmds[i];
            switch (m[0]) {
            case "spawn": this.spawn(m[1], lower(m[2] || {})); break;
            case "set":
                e = this.byId[m[1]];
                if (e) { this.apply(e, lower(m[2] || {})); }
                break;
            case "kill": this.kill(m[1]); break;
            case "killtag":
                for (var j = this.ents.length - 1; j >= 0; j--) { if (this.ents[j].tag === m[1]) { this.kill(this.ents[j].id); } }
                break;
            case "world":
                var wv = lower(m[1] || {}), k;
                for (k in wv) {
                    if (k === "light") { this.world.light = norm(wv.light); }
                    else if (k === "mode") { this.world.mode = String(wv.mode).toLowerCase(); }
                    else if (k === "ground") { for (var gk in wv.ground) { this.world.ground[gk] = wv.ground[gk]; } }
                    else { this.world[k] = wv[k]; }
                }
                break;
            case "debug": var dv = lower(m[1] || {}); for (var dk in dv) { this.debug[dk] = dv[dk]; } break;
            case "cam": var cv = lower(m[1] || {}); for (var ck in cv) { this.cam[ck] = cv[ck]; } break;
            case "mesh": addMesh(m[1], m[2], m[3]); break;
            case "map": this.setMap(m[1] || [], m[2] || {}); break;
            case "tile": this.setTile(num(m[1], 0) | 0, num(m[2], 0) | 0, String(m[3] || " ").charAt(0)); break;
            case "sprite": this.sprites[m[1]] = { rows: m[2] || [], pal: m[3] || {} }; this.dropSprite(m[1]); break;
            case "float": this.floatText(num(m[1], 0), num(m[2], 0), String(m[3]), lower(m[4] || {})); break;
            case "burst": this.burst(lower(m[1] || {})); break;
            case "hud":
                if (m[2] == null || m[2] === "") { delete this.hud[m[1]]; }
                else { var hv = this.hud[m[1]] || {}, h2 = lower(m[2]); for (var hk in h2) { hv[hk] = h2[hk]; } this.hud[m[1]] = hv; }
                break;
            case "watch": if (m[2]) { this.watch[m[1]] = 1; } else { delete this.watch[m[1]]; } break;
            case "tick": this.tickHz = Math.max(1, num(m[1], 30)); break;
            case "list": this.wantList = !!m[1]; break;
            case "step": this.update(STEP); this.acc = 0; break;
            case "clear": this.ents = []; this.byId = {}; this.contacts = {}; this.gone = []; this.camOn = ""; break;
            case "ack":
                var st = this.sent[m[1]];
                if (st) { this.stat.rtt = Math.round((now() - st) * 10) / 10; delete this.sent[m[1]]; }
                this.stat.logic = num(m[2], 0);
                if (m[1] >= this.seq) { this.waiting = false; }
                break;
            }
        }
    };

    /* ------------------------------------------------------------ entities */
    var DEFAULTS = { x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, rx: 0, ry: 0, rz: 0, sx: 1, sy: 1, sz: 1,
                     color: "#cccccc", mesh: "cube", bounce: 0, shadow: true };
    G.spawn = function (id, p) {
        if (this.byId[id]) { this.kill(id); }
        var e = { id: id }, k;
        for (k in DEFAULTS) { e[k] = DEFAULTS[k]; }
        this.apply(e, p);
        e.born = this.time; e.by = e.y;
        this.ents.push(e); this.byId[id] = e;
        return e;
    };
    G.apply = function (e, p) {
        var k;
        for (k in p) { if (p.hasOwnProperty(k)) { e[k] = p[k]; } }
        if (p.scale != null) { e.sx = e.sy = e.sz = num(p.scale, 1); }
        if (p.color) { e.rgb = rgb(p.color); }
        if (!e.rgb) { e.rgb = rgb(e.color); }
        if (p.y != null) { e.by = e.y; }
        var m = AXGE.meshes[e.mesh] || AXGE.meshes.cube;
        if (this.world.mode === "2d") {                          /* in tiles: a thing is Size across, 0.8 by default */
            e.r = p.radius != null ? num(p.radius, 0.4) : (e.radius != null ? e.radius : num(e.size, 0.8) * 0.42);
        } else {
            e.r = p.radius != null ? num(p.radius, 1) : (e.radius != null ? e.radius : m.r * Math.max(e.sx, e.sy, e.sz) * 0.9);
        }
        e.vr = m.r * Math.max(e.sx, e.sy, e.sz) * 1.05;          /* what it covers on screen, for culling */
        /* where it was a step ago, for drawing between steps; a jump set from
           the script is a jump, not a slide */
        if (p.x != null || e.px == null) { e.px = e.x; }
        if (p.y != null || e.py == null) { e.py = e.y; }
        if (p.z != null || e.pz == null) { e.pz = e.z; }
        if (p.rx != null || e.prx == null) { e.prx = e.rx; }
        if (p.ry != null || e.pry == null) { e.pry = e.ry; }
        if (p.rz != null || e.prz == null) { e.prz = e.rz; }
    };
    G.kill = function (id) {
        var e = this.byId[id], i;
        if (!e) { return; }
        delete this.byId[id];
        if (!e.particle) { this.gone.push(id); }                   /* told to AutoHotkey with the next tick */
        for (i = 0; i < this.ents.length; i++) { if (this.ents[i] === e) { this.ents.splice(i, 1); break; } }
        for (var k in this.contacts) { if (k.indexOf(id + "|") === 0 || k.indexOf("|" + id) > 0) { delete this.contacts[k]; } }
    };
    G.burst = function (b) {
        var n = num(b.n, 16), i, sp = num(b.speed, 7), life = num(b.life, 0.8), sz = num(b.size, 0.28);
        if (this.world.mode === "2d") {                        /* sparks on the flat: out and slowing down */
            sp = num(b.speed, 4); sz = num(b.size, 0.14);
            for (i = 0; i < n; i++) {
                var a2 = Math.random() * Math.PI * 2, v2 = sp * (0.3 + Math.random() * 0.9);
                this.spawn("p" + (++this.pn), {
                    particle: 1, color: b.color || "#ffffff", size: sz * (0.6 + Math.random() * 0.9), shape: "box", layer: 3,
                    x: num(b.x, 0), y: num(b.y, 0), vx: Math.cos(a2) * v2, vy: Math.sin(a2) * v2, drag: 3.5,
                    life: life * (0.6 + Math.random() * 0.7), shadow: false
                });
            }
            return;
        }
        for (i = 0; i < n; i++) {
            var a = Math.random() * Math.PI * 2, up = Math.random();
            this.spawn("p" + (++this.pn), {
                particle: 1, mesh: b.mesh || "tetra", color: b.color || "#ffffff", scale: sz * (0.6 + Math.random() * 0.8),
                x: num(b.x, 0), y: num(b.y, 1), z: num(b.z, 0),
                vx: Math.cos(a) * sp * (0.4 + Math.random()), vz: Math.sin(a) * sp * (0.4 + Math.random()), vy: sp * (0.5 + up),
                spin: [Math.random() * 720 - 360, Math.random() * 720 - 360, 0], gravity: 1, solid: 1, bounce: 0.4, life: life * (0.7 + Math.random() * 0.6),
                shadow: false, glow: 1
            });
        }
    };

    /* ------------------------------------------------------------ the step */
    G.loop = function () {
        var t = now(), dt = Math.min(0.1, (t - this.last) / 1000), f0 = t;
        this.last = t;
        this.resize();
        if (!this.world.paused) {
            this.acc += dt * num(this.world.timescale, 1);
            var n = 0;
            while (this.acc >= STEP && n < 6) { this.update(STEP); this.acc -= STEP; n++; }
            if (n >= 6) { this.acc = 0; }
        }
        /* how far between the last two steps this frame falls */
        this.alpha = this.world.paused ? 1 : clamp(this.acc / STEP, 0, 1);
        this.frameDt = dt;
        this.render();
        /* the rules' tick, after the drawing: one at a time, and never more
           often than asked */
        this.tickAcc += dt;
        if (this.tickAcc >= 1 / this.tickHz && (!this.waiting || t - this.waitSince > 500)) {
            this.tickAcc = Math.min(this.tickAcc - 1 / this.tickHz, 1 / this.tickHz); this.tickN++;     /* the remainder kept: 2 frames at 60 are 33.2 ms, not 1/30 s */
            this.sendTick();
        }
        this.fpsN++;
        this.stat.ms = Math.round((now() - f0) * 10) / 10;
        if (t - this.fpsT >= 500) {
            this.stat.fps = Math.round(this.fpsN * 1000 / (t - this.fpsT));
            this.stat.tickHz = Math.round(this.tickN * 1000 / (t - this.fpsT));
            this.fpsN = 0; this.tickN = 0; this.fpsT = t;
        }
    };
    G.update = function (dt) {
        if (this.world.mode === "2d") { return this.update2d(dt); }
        var W = this.world, i, e, k = this.keys, j;
        this.time += dt; this.frame++;
        for (i = this.ents.length - 1; i >= 0; i--) {
            e = this.ents[i];
            e.px = e.x; e.py = e.y; e.pz = e.z; e.prx = e.rx; e.pry = e.ry; e.prz = e.rz;
            if (e.frozen) { continue; }
            if (e.control) {                                     /* the player: the keys, at once */
                var c = e.control, ix = (k.right || k.d ? 1 : 0) - (k.left || k.a ? 1 : 0), iz = (k.down || k.s ? 1 : 0) - (k.up || k.w ? 1 : 0);
                var l = Math.sqrt(ix * ix + iz * iz) || 1, spd = num(c.speed, 10), acc = num(c.accel, 9);
                e.vx += (ix / l * spd - e.vx) * Math.min(1, acc * dt);
                e.vz += (iz / l * spd - e.vz) * Math.min(1, acc * dt);
                if ((ix || iz) && c.face !== false) { turnTo(e, Math.atan2(-ix, -iz) / D2R, num(c.turn, 12) * dt); }
                if (c.jump && this.pressed.space && e.y <= e.r + 0.05) { e.vy = num(c.jump, 9); }
                e.rz += ((-ix * 18) - e.rz) * Math.min(1, 6 * dt);         /* a lean into the turn */
            }
            if (e.chase) {
                var tg = this.byId[e.chase.target];
                if (tg) {
                    var dx = tg.x - e.x, dz = tg.z - e.z, dl = Math.sqrt(dx * dx + dz * dz) || 1, cs = num(e.chase.speed, 4);
                    e.vx += (dx / dl * cs - e.vx) * Math.min(1, num(e.chase.turn, 1.5) * dt);
                    e.vz += (dz / dl * cs - e.vz) * Math.min(1, num(e.chase.turn, 1.5) * dt);
                }
            }
            if (e.gravity) { e.vy -= W.gravity * num(e.gravity, 1) * dt; }
            e.x += e.vx * dt; e.y += e.vy * dt; e.z += e.vz * dt;
            if (e.solid && e.y < e.r) {                          /* the ground */
                e.y = e.r;
                e.vy = Math.abs(e.vy) > 1.5 ? -e.vy * num(e.bounce, 0) : 0;
                if (e.particle) { e.vx *= 0.8; e.vz *= 0.8; }
            }
            if (e.drag) { var dr = Math.max(0, 1 - num(e.drag, 0) * dt); e.vx *= dr; e.vz *= dr; }
            if (e.spin) { e.rx += num(e.spin[0], 0) * dt; e.ry += num(e.spin[1], 0) * dt; e.rz += num(e.spin[2], 0) * dt; }
            if (e.roll) { e.rx += e.vz * dt / (e.r || 1) / D2R; e.rz -= e.vx * dt / (e.r || 1) / D2R; }
            if (e.bounds) {
                var B = num(W.bounds, 26);
                if (Math.abs(e.x) > B || Math.abs(e.z) > B) {
                    if (e.bounds === "kill") { this.kill(e.id); continue; }
                    if (e.bounds === "bounce") { if (Math.abs(e.x) > B) { e.vx = -e.vx; } if (Math.abs(e.z) > B) { e.vz = -e.vz; } }
                    e.x = clamp(e.x, -B, B); e.z = clamp(e.z, -B, B);
                }
            }
            if (e.life != null) {
                e.life -= dt;
                if (e.life <= 0) { this.kill(e.id); continue; }
            }
        }
        this.collide();
        if (W.shake > 0) { W.shake = Math.max(0, W.shake - dt * 2.2); }
    };
    /* collisions: each thing that lists tags it hits, against those; told
       once when they touch, and again only after they have come apart */
    G.collide = function () {
        var i, j, e;
        for (i = 0; i < this.ents.length; i++) {
            e = this.ents[i];
            if (!e.hits || e.hidden) { continue; }
            for (j = 0; j < this.ents.length; j++) {
                var o = this.ents[j];
                if (o === e || o.particle || o.hidden || !o.tag || e.hits.indexOf(o.tag) < 0) { continue; }
                var ddx = o.x - e.x, ddy = o.y - e.y, ddz = o.z - e.z, rr = e.r + o.r, key2 = e.id + "|" + o.id;
                if (ddx * ddx + ddy * ddy + ddz * ddz < rr * rr) {
                    if (!this.contacts[key2]) { this.contacts[key2] = 1; this.hits.push([e.id, o.id, o.tag]); }
                } else if (this.contacts[key2]) { delete this.contacts[key2]; }
            }
        }
    };
    function turnTo(e, deg, rate) {
        var d = ((deg - e.ry) % 360 + 540) % 360 - 180;
        e.ry += d * Math.min(1, rate);
    }

    /* ----------------------------------------------------------- the camera */
    G.resize = function () {
        var w = this.el.clientWidth, h = this.el.clientHeight, r = window.devicePixelRatio || (screen.deviceXDPI && screen.logicalXDPI ? screen.deviceXDPI / screen.logicalXDPI : 1) || 1;
        if (w === this.w && h === this.h && r === this.dpr) { return; }
        this.w = w; this.h = h; this.dpr = r;
        this.cv.width = Math.max(1, Math.round(w * r)); this.cv.height = Math.max(1, Math.round(h * r));
        this.cv.style.width = w + "px"; this.cv.style.height = h + "px";
    };
    /* The eye goes after what it follows as it is DRAWN (between steps), and
       the smoothing is by time, not by frame, so it is the same at any rate */
    G.placeCamera = function (dt, rt) {
        var C = this.cam, t = this.byId[C.follow], a = this.alpha == null ? 1 : this.alpha, k = 1 - Math.exp(-num(C.smooth, 6) * dt);
        if (t) {
            var fx = t.px + (t.x - t.px) * a, fy = t.py + (t.y - t.py) * a, fz = t.pz + (t.z - t.pz) * a;
            if (this.camOn !== C.follow) { C.tx = fx; C.ty = fy * 0.5 + 0.8; C.tz = fz; this.camOn = C.follow; }   /* a new target: be there */
            C.tx += (fx - C.tx) * k; C.ty += (fy * 0.5 + 0.8 - C.ty) * k; C.tz += (fz - C.tz) * k;
        }
        var ex = C.tx, ey = C.ty + num(C.height, 8), ez = C.tz + num(C.dist, 13);
        if (!t && C.x != null && !C.follow) { ex = num(C.x, 0); ey = num(C.y, 8); ez = num(C.z, 13); }
        var s = this.world.shake || 0;
        if (s) { ex += Math.sin(rt * 47.3) * s * 0.5; ey += Math.sin(rt * 61.7 + 1) * s * 0.5; }   /* a shudder, the same at any frame rate */
        C.eye = [ex, ey, ez]; C.at = [C.tx, C.ty, C.tz];
        var f = norm(sub(C.at, C.eye)), r = norm(cross(f, [0, 1, 0])), u = cross(r, f);
        C.f = f; C.r = r; C.u = u;
        C.focal = (this.h / 2) / Math.tan(num(C.fov, 60) * D2R / 2);
    };
    /* a world point into view space: [right, up, depth] */
    G.view = function (p) {
        var C = this.cam, d = sub(p, C.eye);
        return [dot(d, C.r), dot(d, C.u), dot(d, C.f)];
    };

    /* ------------------------------------------------------------ rendering */
    /* View space here is mirrored (right, up, forward is left-handed), so a
       cross product taken in it points the other way: a face looks at the eye
       when (n . A) > 0, and its light is -(n . L). */
    var NEAR = 0.25, TRI = [], CLIP = [], QUAD = [], COS8 = [], SIN8 = [];
    (function () { for (var i = 0; i < 8; i++) { COS8.push(Math.cos(i * Math.PI / 4)); SIN8.push(Math.sin(i * Math.PI / 4)); } })();
    /* Sutherland-Hodgman against z = NEAR, on flat [x, y, z, x, y, z ...] lists */
    function clipNear(src, n, out) {
        var i, m = 0;
        for (i = 0; i < n; i++) {
            var a = i * 3, b = ((i + 1) % n) * 3, az = src[a + 2], bz = src[b + 2], ain = az >= NEAR, bin = bz >= NEAR;
            if (ain) { out[m * 3] = src[a]; out[m * 3 + 1] = src[a + 1]; out[m * 3 + 2] = az; m++; }
            if (ain !== bin) {
                var t = (NEAR - az) / (bz - az);
                out[m * 3] = src[a] + (src[b] - src[a]) * t; out[m * 3 + 1] = src[a + 1] + (src[b + 1] - src[a + 1]) * t; out[m * 3 + 2] = NEAR; m++;
            }
        }
        return m;
    }
    function byDepth(p, q) { return q.z - p.z; }
    G.shade = function (r, g, b, lit, depth) {
        var fog = (depth - this.f0) * this.fk, F = this.fogRgb;
        fog = fog < 0 ? 0 : fog > 1 ? 1 : fog;
        var q = lit * (1 - fog);
        return hex3(r * q + F[0] * fog, g * q + F[1] * fog, b * q + F[2] * fog);
    };
    /* a polygon in view space into the frame's list: clipped, projected, and
       kept in a record from the pool -- nothing is allocated per polygon */
    G.addPoly = function (src, n, colour, z, wire) {
        var cx = this.w / 2, cy = this.h / 2, fc = this.cam.focal, k, m = n, pts = src;
        for (k = 0; k < n; k++) {
            if (src[k * 3 + 2] < NEAR) { m = clipNear(src, n, CLIP); pts = CLIP; break; }
        }
        if (m < 3) { return; }
        var f = this.pool[this.nf];
        if (!f) { f = this.pool[this.nf] = { p: [], n: 0, z: 0, c: "", wire: false }; }
        this.nf++;
        for (k = 0; k < m; k++) {
            var vz = pts[k * 3 + 2];
            f.p[k * 2] = cx + pts[k * 3] / vz * fc; f.p[k * 2 + 1] = cy - pts[k * 3 + 1] / vz * fc;
        }
        f.n = m; f.c = colour; f.z = z; f.wire = wire;
    };
    G.render = function () {
        var c = this.ctx, W = this.world, w = this.w, h = this.h, i;
        if (!w || !h) { return; }
        if (W.mode === "2d") { return this.render2d(); }
        var a = this.alpha == null ? 1 : this.alpha, rt = this.time - STEP * (1 - a);     /* the moment this frame shows */
        this.placeCamera(Math.min(0.1, this.frameDt || 1 / 60), rt);
        this.fogRgb = rgb(W.fogcolor || W.sky[1]);
        this.f0 = num(W.fog[0], 18); this.far = num(W.fog[1], 55); this.fk = 1 / Math.max(1, this.far - this.f0);
        c.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
        var skyKey = W.sky[0] + "|" + W.sky[1] + "|" + h;
        if (this.skyKey !== skyKey) {
            var sky = c.createLinearGradient(0, 0, 0, h);
            sky.addColorStop(0, W.sky[0]); sky.addColorStop(1, W.sky[1]);
            this.sky = sky; this.skyKey = skyKey;
        }
        c.fillStyle = this.sky; c.fillRect(0, 0, w, h);
        if (!this.pool) { this.pool = []; this.order = []; }
        this.nf = 0;
        var flat = this.drawGround();
        flat += this.drawShadows(a, rt);
        this.gather(a, rt);
        var list = this.order, n = this.nf;
        list.length = n;
        for (i = 0; i < n; i++) { list[i] = this.pool[i]; }
        list.sort(byDepth);
        this.fill(list, n);
        this.stat.tris = flat + n;
        this.stat.ents = this.ents.length;
        if (this.debug.colliders) { this.colliders(a, rt); }
        this.drawHud();
        if (this.debug.stats) { this.drawStats(); }
    };
    /* The ground: the tile corners round the camera's target are transformed
       once each, and the tiles are filled as four paths -- every tile in the
       first colour (so a seam between colours shows that, not the sky), the
       second colour over it, then the tiles outside the bounds, darker, the
       same way. Fog on flat ground depends only on the screen row, so it is
       one gradient over the lot. */
    G.drawGround = function () {
        var c = this.ctx, W = this.world, C = this.cam, G0 = W.ground, T = num(G0.tile, 4), R = Math.max(1, num(G0.radius, 10) | 0);
        var gx = Math.round(C.tx / T), gz = Math.round(C.tz / T), n = 2 * R + 2, i, j, k;
        var E = C.eye, r = C.r, u = C.u, f = C.f, fc = C.focal, w = this.w, h = this.h, cx = w / 2, cy = h / 2;
        var far = this.far + T * 2, B = num(W.bounds, 26), gv = this.gv || (this.gv = []), gs = this.gs || (this.gs = []);
        var y = -E[1];
        for (i = 0; i < n; i++) {
            var x = (gx - R + i) * T - E[0];
            for (j = 0; j < n; j++) {
                var z = (gz - R + j) * T - E[2], o = i * n + j;
                var vx = x * r[0] + y * r[1] + z * r[2], vy = x * u[0] + y * u[1] + z * u[2], vz = x * f[0] + y * f[1] + z * f[2];
                gv[o * 3] = vx; gv[o * 3 + 1] = vy; gv[o * 3 + 2] = vz;
                if (vz >= NEAR) { gs[o * 2] = cx + vx / vz * fc; gs[o * 2 + 1] = cy - vy / vz * fc; }
            }
        }
        var amb = num(W.ambient, 0.38), lit = amb + (1 - amb) * Math.max(0, W.light[1]);
        var c0 = rgb(G0.colors[0]), c1 = rgb(G0.colors[1] || G0.colors[0]);
        var cols = [hex3(c1[0] * lit, c1[1] * lit, c1[2] * lit), hex3(c0[0] * lit, c0[1] * lit, c0[2] * lit),
                    hex3(c1[0] * lit * 0.55, c1[1] * lit * 0.55, c1[2] * lit * 0.6), hex3(c0[0] * lit * 0.55, c0[1] * lit * 0.55, c0[2] * lit * 0.6)];
        var count = 0;
        for (k = 0; k < 4; k++) {
            var any = false, outPass = k >= 2, oddOnly = (k & 1) === 1;
            c.beginPath();
            for (i = 0; i < n - 1; i++) {
                var ti = gx - R + i, outX = Math.abs((ti + 0.5) * T) > B;
                for (j = 0; j < n - 1; j++) {
                    var tj = gz - R + j, out = outX || Math.abs((tj + 0.5) * T) > B;
                    if (out !== outPass || (oddOnly && !((ti + tj) & 1))) { continue; }
                    var o0 = i * n + j, o1 = o0 + n, o2 = o0 + n + 1, o3 = o0 + 1;
                    var z0 = gv[o0 * 3 + 2], z1 = gv[o1 * 3 + 2], z2 = gv[o2 * 3 + 2], z3 = gv[o3 * 3 + 2];
                    if ((z0 < NEAR && z1 < NEAR && z2 < NEAR && z3 < NEAR) || (z0 > far && z1 > far && z2 > far && z3 > far)) { continue; }
                    if (z0 >= NEAR && z1 >= NEAR && z2 >= NEAR && z3 >= NEAR) {
                        var x0 = gs[o0 * 2], x1 = gs[o1 * 2], x2 = gs[o2 * 2], x3 = gs[o3 * 2];
                        var y0 = gs[o0 * 2 + 1], y1 = gs[o1 * 2 + 1], y2 = gs[o2 * 2 + 1], y3 = gs[o3 * 2 + 1];
                        if ((x0 < 0 && x1 < 0 && x2 < 0 && x3 < 0) || (x0 > w && x1 > w && x2 > w && x3 > w) ||
                            (y0 > h && y1 > h && y2 > h && y3 > h)) { continue; }
                        c.moveTo(x0, y0); c.lineTo(x1, y1); c.lineTo(x2, y2); c.lineTo(x3, y3); c.closePath();
                    } else {
                        var q = [o0, o1, o2, o3], m;
                        for (m = 0; m < 4; m++) { QUAD[m * 3] = gv[q[m] * 3]; QUAD[m * 3 + 1] = gv[q[m] * 3 + 1]; QUAD[m * 3 + 2] = gv[q[m] * 3 + 2]; }
                        var cn = clipNear(QUAD, 4, CLIP);
                        if (cn < 3) { continue; }
                        for (m = 0; m < cn; m++) {
                            var px = cx + CLIP[m * 3] / CLIP[m * 3 + 2] * fc, py = cy - CLIP[m * 3 + 1] / CLIP[m * 3 + 2] * fc;
                            if (m) { c.lineTo(px, py); } else { c.moveTo(px, py); }
                        }
                        c.closePath();
                    }
                    any = true;
                    if (!oddOnly) { count++; }
                }
            }
            if (any) { c.fillStyle = cols[k]; c.fill(); }
        }
        /* the fog: a row at screen y sees the ground at depth
           d(y) = -eye.y * focal / (f.y * focal + u.y * (cy - y)), so y(d) is exact */
        var fy = f[1], uy = u[1], ey = E[1], f0 = this.f0, f1 = this.far;
        if (uy > 0.05 && ey > 0 && f1 > f0) {
            var yOf = function (d) { return cy - (-ey * fc / d - fy * fc) / uy; };
            var yh = cy + fy * fc / uy, yn = yOf(Math.max(NEAR, f0)), yf = yOf(f1), top = Math.max(0, yh);
            if (yh < h && yn > yf + 1 && Math.min(h, yn) > top) {
                var F = this.fogRgb, base = "rgba(" + F[0] + "," + F[1] + "," + F[2] + ",", fg = c.createLinearGradient(0, yf, 0, yn);
                for (k = 6; k >= 0; k--) {
                    fg.addColorStop(clamp((yOf(Math.max(NEAR, f0 + (f1 - f0) * k / 6)) - yf) / (yn - yf), 0, 1), base + (k / 6).toFixed(3) + ")");
                }
                c.fillStyle = fg;
                c.fillRect(0, top, w, Math.min(h, yn) - top);
            }
        }
        return count;
    };
    /* Blob shadows, in eight shades: each shade is one path, so shadows that
       overlap do not darken twice */
    G.drawShadows = function (a, rt) {
        var c = this.ctx, C = this.cam, E = C.eye, r = C.r, u = C.u, f = C.f, fc = C.focal, cx = this.w / 2, cy = this.h / 2;
        var i, j, e, b, cnt = 0, todo = this.shadowList || (this.shadowList = []);
        todo.length = 0;
        for (i = 0; i < this.ents.length; i++) {
            e = this.ents[i];
            if (e.hidden || e.shadow === false || e.shadow === 0) { continue; }
            var ex = e.px + (e.x - e.px) * a, ey = e.py + (e.y - e.py) * a, ez = e.pz + (e.z - e.pz) * a;
            if (e.bob) { ey += bobOf(e, rt); }
            var hgt = Math.max(0, ey - e.r * 0.4), sr = e.r * (0.8 + hgt * 0.04);
            var vz = (ex - E[0]) * f[0] - E[1] * f[1] + (ez - E[2]) * f[2];
            if (vz - sr < NEAR || vz > this.far) { continue; }
            var fog = clamp((vz - this.f0) * this.fk, 0, 1), q = Math.round(clamp(1 - hgt / 12, 0.15, 1) * (1 - fog) * 8);
            if (q < 1) { continue; }
            e.sq = q; e.swx = ex; e.swz = ez; e.swr = sr;
            todo.push(e);
        }
        for (b = 1; b <= 8; b++) {
            var any = false;
            c.beginPath();
            for (i = 0; i < todo.length; i++) {
                e = todo[i];
                if (e.sq !== b) { continue; }
                for (j = 0; j < 8; j++) {
                    var px = e.swx + COS8[j] * e.swr - E[0], py = 0.02 - E[1], pz = e.swz + SIN8[j] * e.swr - E[2];
                    var wz = px * f[0] + py * f[1] + pz * f[2];
                    var sx = cx + (px * r[0] + py * r[1] + pz * r[2]) / wz * fc, sy = cy - (px * u[0] + py * u[1] + pz * u[2]) / wz * fc;
                    if (j) { c.lineTo(sx, sy); } else { c.moveTo(sx, sy); }
                }
                c.closePath();
                any = true; cnt++;
            }
            if (any) { c.fillStyle = "rgba(0,0,0," + (0.32 * b / 8).toFixed(3) + ")"; c.fill(); }
        }
        return cnt;
    };
    /* every visible face of every thing on the screen, into the pool */
    G.gather = function (a, rt) {
        var C = this.cam, E = C.eye, r = C.r, u = C.u, f = C.f, fc = C.focal, W = this.world;
        var hw = this.w / 2 / fc, hh = this.h / 2 / fc, kw = Math.sqrt(1 + hw * hw), kh = Math.sqrt(1 + hh * hh);
        var L = W.light, Lx = L[0] * r[0] + L[1] * r[1] + L[2] * r[2], Ly = L[0] * u[0] + L[1] * u[1] + L[2] * u[2], Lz = L[0] * f[0] + L[1] * f[1] + L[2] * f[2];
        var amb = num(W.ambient, 0.38), wire = !!this.debug.wire, far = this.far, flashK = 0.5 + 0.5 * Math.sin(rt * 30);
        var i, j, e, VB = this.vb || (this.vb = []);
        for (i = 0; i < this.ents.length; i++) {
            e = this.ents[i];
            if (e.hidden) { continue; }
            var ex = e.px + (e.x - e.px) * a, ey = e.py + (e.y - e.py) * a, ez = e.pz + (e.z - e.pz) * a;
            if (e.bob) { ey += bobOf(e, rt); }
            var dx = ex - E[0], dy = ey - E[1], dz = ez - E[2], vr = e.vr || 1;
            var cz = dx * f[0] + dy * f[1] + dz * f[2];
            if (cz + vr < NEAR || cz - vr > far) { continue; }                 /* behind the eye, or lost in the fog */
            var cxv = dx * r[0] + dy * r[1] + dz * r[2], cyv = dx * u[0] + dy * u[1] + dz * u[2];
            if (Math.abs(cxv) - vr * kw > cz * hw || Math.abs(cyv) - vr * kh > cz * hh) { continue; }   /* off a side of the screen */
            var M = AXGE.meshes[e.mesh] || AXGE.meshes.cube, nv = M.v.length;
            var fadeK = (e.life != null && e.particle) ? clamp(e.life * 3, 0, 1) : 1;
            var rx = (e.prx + (e.rx - e.prx) * a) * D2R, ry = (e.pry + (e.ry - e.pry) * a) * D2R, rz = (e.prz + (e.rz - e.prz) * a) * D2R;
            var cyr = Math.cos(ry), syr = Math.sin(ry), cxr = Math.cos(rx), sxr = Math.sin(rx), czr = Math.cos(rz), szr = Math.sin(rz);
            var sx = e.sx * fadeK, sy = e.sy * fadeK, sz = e.sz * fadeK;
            for (j = 0; j < nv; j++) {
                var v = M.v[j], x = v[0] * sx, y = v[1] * sy, z = v[2] * sz, t;
                t = x * czr - y * szr; y = x * szr + y * czr; x = t;          /* z */
                t = y * cxr - z * sxr; z = y * sxr + z * cxr; y = t;          /* x */
                t = x * cyr + z * syr; z = -x * syr + z * cyr; x = t;         /* y */
                x += dx; y += dy; z += dz;
                VB[j * 3] = x * r[0] + y * r[1] + z * r[2]; VB[j * 3 + 1] = x * u[0] + y * u[1] + z * u[2]; VB[j * 3 + 2] = x * f[0] + y * f[1] + z * f[2];
            }
            var col = e.rgb, flash = e.flash ? flashK : 0;
            for (j = 0; j < M.f.length; j++) {
                var F = M.f[j], A = F[0] * 3, Bi = F[1] * 3, Ci = F[2] * 3;
                var ax = VB[A], ay = VB[A + 1], az = VB[A + 2], bx = VB[Bi], by = VB[Bi + 1], bz = VB[Bi + 2], qx = VB[Ci], qy = VB[Ci + 1], qz = VB[Ci + 2];
                var ux = bx - ax, uy = by - ay, uz = bz - az, wx = qx - ax, wy = qy - ay, wz = qz - az;
                var nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
                if (nx * ax + ny * ay + nz * az <= 0) { continue; }             /* facing away */
                var litv = 1;
                if (!e.glow) {
                    var nl = Math.sqrt(nx * nx + ny * ny + nz * nz) || 1, ld = -(nx * Lx + ny * Ly + nz * Lz) / nl;
                    litv = amb + (1 - amb) * (ld > 0 ? ld : 0);
                }
                var fcol = F[3] ? rgb(F[3]) : col, cr = fcol[0], cg = fcol[1], cb = fcol[2];
                if (flash) { cr += (255 - cr) * flash; cg += (255 - cg) * flash; cb += (255 - cb) * flash; }
                var zz = (az + bz + qz) / 3;
                TRI[0] = ax; TRI[1] = ay; TRI[2] = az; TRI[3] = bx; TRI[4] = by; TRI[5] = bz; TRI[6] = qx; TRI[7] = qy; TRI[8] = qz;
                this.addPoly(TRI, 3, this.shade(cr, cg, cb, litv, zz), zz, wire);
            }
        }
    };
    function bobOf(e, t) { return num(e.bob.amp, 0.3) * Math.sin((t - (e.born || 0)) * num(e.bob.speed, 3)); }
    G.fill = function (list, n) {
        var c = this.ctx, i, k, t, p, seams = this.debug.seams !== false && this.debug.seams !== 0;
        c.lineJoin = "round"; c.lineWidth = 0.6;
        for (i = 0; i < n; i++) {
            t = list[i]; p = t.p;
            c.beginPath();
            c.moveTo(p[0], p[1]);
            for (k = 1; k < t.n; k++) { c.lineTo(p[k * 2], p[k * 2 + 1]); }
            c.closePath();
            c.fillStyle = t.c; c.fill();
            if (seams) { c.strokeStyle = t.c; c.stroke(); }               /* hides the hairline cracks */
            if (t.wire) { c.strokeStyle = "rgba(255,255,255,.55)"; c.lineWidth = 1; c.stroke(); c.lineWidth = 0.6; }
        }
    };
    G.colliders = function (a, rt) {
        var c = this.ctx, i, e, C = this.cam;
        c.lineWidth = 1.2;
        for (i = 0; i < this.ents.length; i++) {
            e = this.ents[i];
            if (e.particle || e.hidden) { continue; }
            var v = this.view([e.px + (e.x - e.px) * a, e.py + (e.y - e.py) * a + (e.bob ? bobOf(e, rt) : 0), e.pz + (e.z - e.pz) * a]);
            if (v[2] < NEAR) { continue; }
            var sx = this.w / 2 + v[0] / v[2] * C.focal, sy = this.h / 2 - v[1] / v[2] * C.focal, sr = e.r / v[2] * C.focal;
            c.strokeStyle = e.hits ? "rgba(255,210,0,.9)" : e.tag ? "rgba(0,255,200,.8)" : "rgba(255,255,255,.35)";
            c.beginPath(); c.arc(sx, sy, sr, 0, Math.PI * 2); c.stroke();
            c.fillStyle = "rgba(255,255,255,.85)"; c.font = "10px Consolas, monospace"; c.textAlign = "center"; c.textBaseline = "bottom";
            c.fillText(e.id, sx, sy - sr - 2);
        }
    };
    G.drawHud = function () {
        var c = this.ctx, k, t;
        for (k in this.hud) {
            t = this.hud[k];
            if (t.hidden) { continue; }
            var size = num(t.size, 18), x = pos(t.x, this.w), y = pos(t.y, this.h);
            c.font = (t.bold === false ? "" : "bold ") + size + 'px "Segoe UI Variable Display", "Segoe UI", sans-serif';
            c.textAlign = t.align || "left"; c.textBaseline = "top";
            var lines = String(t.text).split("\n"), li;
            if (t.box && String(t.text) !== "") {                /* a panel behind it: speech, a sign, a menu */
                var bw = 0, pad = num(t.pad, 12), lh = size * 1.25;
                for (li = 0; li < lines.length; li++) { bw = Math.max(bw, c.measureText(lines[li]).width); }
                if (t.width) { bw = Math.max(bw, pos(t.width, this.w) - pad * 2); }
                var bx = t.align === "center" ? x - bw / 2 : t.align === "right" ? x - bw : x;
                c.fillStyle = t.box === true || t.box === 1 ? "rgba(10,12,24,.82)" : t.box;
                roundRect(c, bx - pad, y - pad, bw + pad * 2, lines.length * lh - (lh - size) + pad * 2, 8); c.fill();
                if (t.border) { c.strokeStyle = t.border; c.lineWidth = 2; c.stroke(); }
            }
            for (li = 0; li < lines.length; li++) {
                c.fillStyle = "rgba(0,0,0,.45)"; c.fillText(lines[li], x + 1.5, y + 2 + li * size * 1.25);
                c.fillStyle = t.color || "#ffffff"; c.fillText(lines[li], x, y + li * size * 1.25);
            }
        }
    };
    function pos(v, span) {
        if (typeof v === "string" && /%$/.test(v)) { return parseFloat(v) / 100 * span; }
        v = num(v, 0);
        return v < 0 ? span + v : v;
    }
    G.drawStats = function () {
        var c = this.ctx, s = this.stat, lines = [
            s.fps + " fps   " + s.ms + " ms/frame",
            s.tris + (this.world.mode === "2d" ? " drawn   " : " polygons   ") + s.ents + " things",
            "AHK " + s.tickHz + " ticks/s   " + s.rtt + " ms round trip",
            "AHK rules " + s.logic + " ms   " + s.bytes + " bytes/tick"
        ], w = 250, x = this.w - w - 10, y = 10, i;
        c.fillStyle = "rgba(0,0,0,.5)"; c.fillRect(x, y, w, lines.length * 15 + 10);
        c.font = "11px Consolas, monospace"; c.textAlign = "left"; c.textBaseline = "top";
        for (i = 0; i < lines.length; i++) { c.fillStyle = i ? "#cfe" : "#9f9"; c.fillText(lines[i], x + 8, y + 6 + i * 15); }
    };

    /* ================================================================ 2D */
    /* World({Mode: "2d"}), or Mode=2D on the control: a top-down world of
       tiles, the way an old adventure game is. x runs right and y down, both
       in tiles; a thing's Size is how many tiles across it is drawn (0.8).

         Map(rows, legend)   rows are strings, one character a tile; the
                             legend says what each character is:
                             {Color, Solid, Deco, Sprite, Accent}
         Deco draws a pattern on the colour: grass flowers brick water planks
                             path tree rock door roof
         Sprite(name, rows, palette)  pixel art: "." is see-through, every
                             other character a colour from the palette

       Things that move with Solid stop at solid tiles. Behaviours: Control
       (8 ways), Chase {Target, Speed, Range}, Wander {Speed, Every}, Life,
       Bounds, Flash, Bob; Label writes a name over a thing, Text a glyph on it.
       The map is drawn once into a picture of its own and copied to the
       screen in one call a frame; things are drawn from their own cached
       pictures, lowest on the screen last. */
    var SPRITES = {
        hero: [["...hhhh...", "..hhhhhh..", "..hssssh..", "..sesses..", "...ssss...", "..bbbbbb..", ".sbbybbbs.", "..bbbbbb..", "..bb..bb..", "..dd..dd.."],
               { h: "#6b3e26", s: "#f2c7a0", e: "#1b1b2f", b: "#3a78d8", y: "#e8c547", d: "#4a3222" }],
        elder: [["...wwww...", "..wssssw..", "..sesses..", "..swwwws..", "...wwww...", "..pppppp..", ".sppppppg.", "..pppppp.g", "..pppppp.g", "..dd..dd.g"],
                { w: "#e8e8e8", s: "#f2c7a0", e: "#1b1b2f", p: "#7a4fb5", g: "#8b6b3a", d: "#4a3222" }],
        villager: [["...hhhh...", "..hhhhhh..", "..hsssshh.", "..sesses..", "...ssss...", "..rrrrrr..", ".srrrrrrs.", "..rrrrrr..", ".rrrrrrrr.", "...s..s..."],
                   { h: "#c0662b", s: "#f2c7a0", e: "#1b1b2f", r: "#d8435a" }],
        slime: [["..........", "...gggg...", "..gggggg..", ".gglggggg.", ".ggeggegg.", "gggggggggg", "gggggggggg", ".gggggggg."],
                { g: "#4fbf5a", l: "#b6ff9e", e: "#10301a" }],
        coin: [["..yyyy..", ".yYYYYy.", ".yYyyYy.", ".yYyyYy.", ".yYyyYy.", ".yYYYYy.", "..yyyy.."],
               { y: "#e8b923", Y: "#fff2a8" }],
        potion: [["...cc...", "...gg...", "..gRRg..", ".gRRRRg.", ".gRrRRg.", ".gRRRRg.", "..gggg.."],
                 { c: "#8b5a2b", g: "#cfe8ff", R: "#e23b4b", r: "#ff8a95" }],
        key: [["..........", ".yyy......", "y...y.....", "y...yyyyyy", "y...y..y.y", ".yyy......"], { y: "#f2c230" }],
        chest: [[".bbbbbbbb.", "bddddddddb", "bbbbbbbbbb", "bbbbyybbbb", "bddddddddb", "bbbbbbbbbb"],
                { b: "#9b6a35", d: "#5a3a1b", y: "#f2c230" }],
        heart: [[".rr..rr.", "rrrrrrrr", "rrrrrrrr", ".rrrrrr.", "..rrrr..", "...rr..."], { r: "#ff4d6d" }],
        gem: [["..cccc..", ".cCCCCc.", "cCCccCCc", ".cCccCc.", "..cCCc..", "...cc..."], { c: "#2aa7d8", C: "#9ff0ff" }]
    };
    function hashT(x, y) { var h = (x * 374761393 + y * 668265263) | 0; h = (h ^ (h >>> 13)) * 1274126177; return ((h ^ (h >>> 16)) >>> 0) / 4294967296; }
    function mix(c, k) {                                       /* lighter (k > 0) or darker (k < 0) */
        var a = rgb(c), t = k > 0 ? 255 : 0, f = Math.abs(k);
        return hex3(a[0] + (t - a[0]) * f, a[1] + (t - a[1]) * f, a[2] + (t - a[2]) * f);
    }
    G.setMap = function (rows, legend) {
        var leg = {}, k, w = 0, i;
        for (k in legend) { if (legend.hasOwnProperty(k)) { leg[k] = lower(legend[k] || {}); } }
        for (i = 0; i < rows.length; i++) { rows[i] = String(rows[i]); w = Math.max(w, rows[i].length); }
        for (i = 0; i < rows.length; i++) { while (rows[i].length < w) { rows[i] += " "; } }
        this.map = { rows: rows, legend: leg, w: w, h: rows.length };
        this.tileCache = null;
        this.camOn = "";
    };
    G.setTile = function (x, y, ch) {
        var M = this.map;
        if (!M || y < 0 || y >= M.h || x < 0 || x >= M.w) { return; }
        M.rows[y] = M.rows[y].substr(0, x) + ch + M.rows[y].substr(x + 1);
        if (this.tileCache) { this.paintTile(this.tileCache.getContext("2d"), x, y, this.tilePx); }
    };
    G.solidAt = function (tx, ty) {
        var M = this.map;
        if (!M) { return false; }
        if (tx < 0 || ty < 0 || tx >= M.w || ty >= M.h) { return true; }
        var t = M.legend[M.rows[ty].charAt(tx)];
        return !!(t && t.solid);
    };
    /* a step that stops at solid tiles, one axis at a time, so a thing slides
       along a wall rather than sticking to it */
    G.moveTiles = function (e, dx, dy) {
        var r = e.r * 0.85, eps = 0.0005, lo, hi, t, i, hit = false;
        e.x += dx;
        lo = Math.floor(e.y - r); hi = Math.floor(e.y + r - eps);
        if (dx > 0) { t = Math.floor(e.x + r); for (i = lo; i <= hi; i++) { if (this.solidAt(t, i)) { e.x = t - r - eps; e.vx = 0; hit = true; break; } } }
        else if (dx < 0) { t = Math.floor(e.x - r); for (i = lo; i <= hi; i++) { if (this.solidAt(t, i)) { e.x = t + 1 + r + eps; e.vx = 0; hit = true; break; } } }
        e.y += dy;
        lo = Math.floor(e.x - r); hi = Math.floor(e.x + r - eps);
        if (dy > 0) { t = Math.floor(e.y + r); for (i = lo; i <= hi; i++) { if (this.solidAt(i, t)) { e.y = t - r - eps; e.vy = 0; hit = true; break; } } }
        else if (dy < 0) { t = Math.floor(e.y - r); for (i = lo; i <= hi; i++) { if (this.solidAt(i, t)) { e.y = t + 1 + r + eps; e.vy = 0; hit = true; break; } } }
        return hit;
    };
    G.update2d = function (dt) {
        var W = this.world, M = this.map, i, e, k = this.keys;
        this.time += dt; this.frame++;
        for (i = this.ents.length - 1; i >= 0; i--) {
            e = this.ents[i];
            e.px = e.x; e.py = e.y; e.pz = e.z; e.prx = e.rx; e.pry = e.ry; e.prz = e.rz;
            if (e.frozen) { continue; }
            if (e.control) {                                     /* the player: eight ways, at once */
                var c = e.control, ix = (k.right || k.d ? 1 : 0) - (k.left || k.a ? 1 : 0), iy = (k.down || k.s ? 1 : 0) - (k.up || k.w ? 1 : 0);
                var l = Math.sqrt(ix * ix + iy * iy) || 1, spd = num(c.speed, 5), acc = num(c.accel, 16);
                e.vx += (ix / l * spd - e.vx) * Math.min(1, acc * dt);
                e.vy += (iy / l * spd - e.vy) * Math.min(1, acc * dt);
                if (ix || iy) { e.fx = ix / l; e.fy = iy / l; }  /* the way it faces, for the script */
            }
            e.chasing = false;
            if (e.chase) {
                var tg = this.byId[e.chase.target];
                if (tg && !tg.hidden) {
                    var dx = tg.x - e.x, dy = tg.y - e.y, dl = Math.sqrt(dx * dx + dy * dy) || 1, rng = num(e.chase.range, 0);
                    if (!rng || dl < rng) {
                        var cs = num(e.chase.speed, 2), ct = Math.min(1, num(e.chase.turn, 3) * dt);
                        e.vx += (dx / dl * cs - e.vx) * ct; e.vy += (dy / dl * cs - e.vy) * ct;
                        e.chasing = true;
                    }
                }
            }
            if (e.wander && !e.chasing) {
                e.wt = (e.wt || 0) - dt;
                if (e.wt <= 0) {
                    e.wt = num(e.wander.every, 1.6) * (0.5 + Math.random());
                    var wa = Math.random() * Math.PI * 2, ws = Math.random() < 0.3 ? 0 : num(e.wander.speed, 1.2);
                    e.wx = Math.cos(wa) * ws; e.wy = Math.sin(wa) * ws;
                }
                e.vx += ((e.wx || 0) - e.vx) * Math.min(1, 4 * dt); e.vy += ((e.wy || 0) - e.vy) * Math.min(1, 4 * dt);
            }
            if (e.drag) { var dr = Math.max(0, 1 - num(e.drag, 0) * dt); e.vx *= dr; e.vy *= dr; }
            if (e.spin) { e.rz += (e.spin instanceof Array ? num(e.spin[2], 0) || num(e.spin[1], 0) : num(e.spin, 0)) * dt; }
            if (e.solid && M) {
                if (this.moveTiles(e, e.vx * dt, e.vy * dt) && e.wander) { e.wt = 0; }     /* a wanderer at a wall turns round */
            } else { e.x += e.vx * dt; e.y += e.vy * dt; }
            if (e.vx > 0.1) { e.flip = false; } else if (e.vx < -0.1) { e.flip = true; }
            if (M && (e.bounds || e.solid)) {
                var out = e.x < 0 || e.y < 0 || e.x > M.w || e.y > M.h;
                if (out && e.bounds === "kill") { this.kill(e.id); continue; }
                e.x = clamp(e.x, e.r, M.w - e.r); e.y = clamp(e.y, e.r, M.h - e.r);
            }
            if (e.life != null) {
                e.life -= dt;
                if (e.life <= 0) { this.kill(e.id); continue; }
            }
        }
        this.collide();
        if (W.shake > 0) { W.shake = Math.max(0, W.shake - dt * 2.2); }
    };
    G.floatText = function (x, y, text, o) {                  /* "+1", "-3": rises and fades */
        this.spawn("p" + (++this.pn), { particle: 1, float: text, x: x, y: y, vy: -num(o.speed, 1.4), drag: 1.2, life: num(o.life, 0.9),
                                        color: o.color || "#ffffff", size: num(o.size, 0.5), shadow: false, layer: 4 });
    };

    /* ---- pictures: tiles and sprites, each drawn once and kept */
    G.paintTile = function (c, tx, ty, s) {
        var M = this.map, ch = M.rows[ty].charAt(tx), t = M.legend[ch], x = tx * s, y = ty * s, h = hashT(tx, ty), h2 = hashT(ty + 7, tx + 3);
        if (!t) { c.clearRect(x, y, s, s); return; }
        var col = t.color || "#3a5a40", d = String(t.deco || "").toLowerCase(), u = s / 16, i;
        c.fillStyle = col; c.fillRect(x, y, s, s);
        switch (d) {
        case "grass": case "flowers": case "tree":
            c.fillStyle = mix(col, -0.18);
            for (i = 0; i < 3; i++) { var gx = x + (hashT(tx * 3 + i, ty) * 13 + 1) * u, gy = y + (hashT(ty * 3 + i, tx) * 12 + 2) * u; c.fillRect(gx, gy, u, u * 2); c.fillRect(gx + u, gy + u, u, u); }
            c.fillStyle = mix(col, 0.12);
            c.fillRect(x + h * 12 * u + u, y + h2 * 12 * u + u, u, u);
            if (d === "flowers") {
                c.fillStyle = t.accent || (h > 0.5 ? "#ffd84a" : "#ff8fc7");
                c.fillRect(x + (h2 * 10 + 2) * u, y + (h * 10 + 3) * u, u * 2, u * 2);
                c.fillStyle = t.accent2 || "#ffffff";
                c.fillRect(x + (h * 9 + 4) * u, y + (h2 * 9 + 2) * u, u * 2, u * 2);
            }
            if (d === "tree") {
                c.fillStyle = "rgba(0,0,0,.22)"; c.beginPath(); c.arc(x + s / 2, y + s * 0.82, s * 0.36, 0, Math.PI * 2); c.fill();
                c.fillStyle = "#6b4a2f"; c.fillRect(x + s * 0.44, y + s * 0.55, s * 0.12, s * 0.3);
                c.fillStyle = t.accent || "#2f7d45"; c.beginPath(); c.arc(x + s / 2, y + s * 0.42, s * 0.36, 0, Math.PI * 2); c.fill();
                c.fillStyle = mix(t.accent || "#2f7d45", 0.18); c.beginPath(); c.arc(x + s * 0.4, y + s * 0.33, s * 0.18, 0, Math.PI * 2); c.fill();
            }
            break;
        case "brick": case "wall":
            c.fillStyle = mix(col, -0.28);
            c.fillRect(x, y + s / 2 - u / 2, s, u); c.fillRect(x, y + s - u, s, u);
            c.fillRect(x + (ty % 2 ? s / 2 : 0), y, u, s / 2); c.fillRect(x + (ty % 2 ? 0 : s / 2), y + s / 2, u, s / 2);
            c.fillStyle = mix(col, 0.14); c.fillRect(x, y, s, u);
            break;
        case "water":
            c.strokeStyle = mix(col, 0.25); c.lineWidth = Math.max(1, u);
            c.beginPath();
            var wy = y + (4 + h * 8) * u;
            c.moveTo(x + 2 * u, wy); c.quadraticCurveTo(x + 5 * u, wy - 2 * u, x + 8 * u, wy);
            wy = y + (9 + h2 * 5) * u;
            c.moveTo(x + 8 * u, wy); c.quadraticCurveTo(x + 11 * u, wy - 2 * u, x + 14 * u, wy);
            c.stroke();
            break;
        case "planks":
            c.fillStyle = mix(col, -0.22);
            c.fillRect(x, y + s / 3, s, u * 0.8); c.fillRect(x, y + s * 2 / 3, s, u * 0.8);
            c.fillRect(x + h * s * 0.8, y, u * 0.8, s / 3);
            break;
        case "path": case "sand":
            c.fillStyle = mix(col, -0.12);
            for (i = 0; i < 4; i++) { c.fillRect(x + hashT(tx * 5 + i, ty) * 14 * u, y + hashT(ty * 5 + i, tx) * 14 * u, u, u); }
            break;
        case "rock":
            c.fillStyle = "rgba(0,0,0,.2)"; c.beginPath(); c.arc(x + s / 2, y + s * 0.62, s * 0.38, 0, Math.PI * 2); c.fill();
            c.fillStyle = t.accent || "#8a8793"; c.beginPath(); c.arc(x + s / 2, y + s / 2, s * 0.36, 0, Math.PI * 2); c.fill();
            c.fillStyle = mix(t.accent || "#8a8793", 0.25); c.beginPath(); c.arc(x + s * 0.42, y + s * 0.42, s * 0.14, 0, Math.PI * 2); c.fill();
            break;
        case "door":
            c.fillStyle = t.accent || "#7a4f2a"; c.fillRect(x + s * 0.18, y + s * 0.1, s * 0.64, s * 0.9);
            c.fillStyle = mix(t.accent || "#7a4f2a", -0.3); c.fillRect(x + s * 0.48, y + s * 0.1, u, s * 0.9);
            c.fillStyle = "#f2c230"; c.fillRect(x + s * 0.62, y + s * 0.55, u * 1.5, u * 1.5);
            break;
        case "roof":
            c.fillStyle = mix(col, -0.2);
            for (i = 0; i < 4; i++) { c.fillRect(x, y + i * s / 4 + s / 8, s, u); }
            c.fillStyle = mix(col, 0.15); c.fillRect(x, y, s, u);
            break;
        }
        if (t.sprite) { this.drawSprite(c, t.sprite, x + s / 2, y + s * 0.9, s * num(t.size, 0.8), false, 1); }
    };
    G.tiles = function (px) {                                  /* the whole map, drawn once at this tile size */
        var M = this.map;
        if (this.tileCache && this.tilePx === px) { return this.tileCache; }
        var w = M.w * px, h = M.h * px;
        if (w > 8000 || h > 8000 || w * h > 40000000) { this.tileCache = null; return null; }     /* too big to keep: drawn tile by tile */
        var cv = document.createElement("canvas");
        cv.width = w; cv.height = h;
        var c = cv.getContext("2d"), x, y;
        for (y = 0; y < M.h; y++) { for (x = 0; x < M.w; x++) { this.paintTile(c, x, y, px); } }
        this.tileCache = cv; this.tilePx = px;
        return cv;
    };
    G.dropSprite = function (name) {
        for (var k in this.sprCache) { if (k.indexOf(name + "|") === 0) { delete this.sprCache[k]; } }
    };
    /* a sprite at a pixel size, from the pixel art, flipped if asked; kept */
    G.spritePic = function (name, px, flip) {
        var key = name + "|" + px + (flip ? "f" : ""), hit = this.sprCache[key];
        if (hit) { return hit; }
        var def = this.sprites[name], rows, pal;
        if (def) { rows = def.rows; pal = def.pal; } else if (SPRITES[name]) { rows = SPRITES[name][0]; pal = SPRITES[name][1]; } else { return null; }
        var h = rows.length, w = 0, x, y;
        for (y = 0; y < h; y++) { w = Math.max(w, String(rows[y]).length); }
        var cv = document.createElement("canvas");
        cv.width = Math.max(1, w * px); cv.height = Math.max(1, h * px);
        var c = cv.getContext("2d");
        for (y = 0; y < h; y++) {
            var row = String(rows[y]);
            for (x = 0; x < row.length; x++) {
                var ch = row.charAt(x), col = pal[ch];
                if (ch === "." || ch === " " || !col) { continue; }
                c.fillStyle = col;
                c.fillRect((flip ? w - 1 - x : x) * px, y * px, px, px);
            }
        }
        cv.cols = w; cv.lines = h;
        return (this.sprCache[key] = cv);
    };
    /* a sprite standing at (sx, sy) -- its feet -- `size` pixels across */
    G.drawSprite = function (c, name, sx, sy, size, flip, dpr) {
        var probe = this.spritePic(name, 1, false);
        if (!probe) { return false; }
        var px = Math.max(1, Math.round(size * dpr / probe.cols)), pic = this.spritePic(name, px, flip);
        var dw = probe.cols * px / dpr, dh = probe.lines * px / dpr;
        c.drawImage(pic, Math.round(sx - dw / 2), Math.round(sy - dh), dw, dh);
        return true;
    };

    /* ---- the camera and the frame */
    G.render2d = function () {
        var c = this.ctx, W = this.world, w = this.w, h = this.h, M = this.map, dpr = this.dpr, i, e;
        var a = this.alpha == null ? 1 : this.alpha, rt = this.time - STEP * (1 - a);
        var T = num(W.tile, 32) * num(W.zoom, 1), C = this.cam, dt = Math.min(0.1, this.frameDt || 1 / 60);
        var mw = M ? M.w : 20, mh = M ? M.h : 15, vw = w / T, vh = h / T;
        /* the eye: after the thing it follows, kept inside the map */
        var t = this.byId[C.follow], k = 1 - Math.exp(-num(C.smooth, 8) * dt);
        if (t) {
            var fx = t.px + (t.x - t.px) * a, fy = t.py + (t.y - t.py) * a;
            if (this.camOn !== C.follow) { C.tx = fx; C.tz = fy; this.camOn = C.follow; }
            C.tx += (fx - C.tx) * k; C.tz += (fy - C.tz) * k;
        } else if (!C.follow) { C.tx = num(C.x, mw / 2); C.tz = num(C.y, mh / 2); }
        var cx = vw >= mw ? mw / 2 : clamp(C.tx, vw / 2, mw - vw / 2), cy = vh >= mh ? mh / 2 : clamp(C.tz, vh / 2, mh - vh / 2);
        var s = W.shake || 0;
        if (s) { cx += Math.sin(rt * 47.3) * s * 0.3; cy += Math.sin(rt * 61.7 + 1) * s * 0.3; }
        var ox = cx - vw / 2, oy = cy - vh / 2;                /* the top left of the view, in tiles */
        this.view2d = { ox: ox, oy: oy, T: T };
        c.setTransform(dpr, 0, 0, dpr, 0, 0);
        c.fillStyle = W.back || "#0d0f14"; c.fillRect(0, 0, w, h);
        try { c.msImageSmoothingEnabled = false; c.imageSmoothingEnabled = false; } catch (e0) { }
        /* the map: one copy from its picture */
        if (M) {
            var px = Math.max(1, Math.round(T * dpr)), pic = this.tiles(px);
            if (pic) {
                var sx0 = ox * px, sy0 = oy * px, sw = vw * px, sh = vh * px, dx0 = 0, dy0 = 0;
                if (sx0 < 0) { dx0 = -sx0 / px * T; sw += sx0; sx0 = 0; }
                if (sy0 < 0) { dy0 = -sy0 / px * T; sh += sy0; sy0 = 0; }
                sw = Math.min(sw, pic.width - sx0); sh = Math.min(sh, pic.height - sy0);
                if (sw > 0 && sh > 0) { c.drawImage(pic, sx0, sy0, sw, sh, dx0, dy0, sw / px * T, sh / px * T); }
            } else {                                          /* too big to keep: the tiles in view, each frame */
                c.save(); c.setTransform(1, 0, 0, 1, 0, 0);
                var x0 = Math.max(0, Math.floor(ox)), y0 = Math.max(0, Math.floor(oy)), x1 = Math.min(M.w - 1, Math.ceil(ox + vw)), y1 = Math.min(M.h - 1, Math.ceil(oy + vh)), yy, xx;
                c.translate(-ox * px, -oy * px);
                for (yy = y0; yy <= y1; yy++) { for (xx = x0; xx <= x1; xx++) { this.paintTile(c, xx, yy, px); } }
                c.restore();
            }
        }
        /* what is in view, lowest on the screen drawn last */
        var list = this.order2 || (this.order2 = []), n = 0;
        for (i = 0; i < this.ents.length; i++) {
            e = this.ents[i];
            if (e.hidden) { continue; }
            var ex = e.px + (e.x - e.px) * a, ey = e.py + (e.y - e.py) * a, sz = num(e.size, 0.8);
            if (ex + sz < ox || ex - sz > ox + vw || ey + sz < oy || ey - sz * 1.5 > oy + vh) { continue; }
            e._dx = (ex - ox) * T; e._dy = (ey - oy) * T; e._dz = ey + num(e.layer, 1) * 1000;
            list[n++] = e;
        }
        list.length = n;
        list.sort(byLayer);
        /* the shadows, as one path */
        c.fillStyle = "rgba(0,0,0,.26)";
        c.beginPath();
        for (i = 0; i < n; i++) {
            e = list[i];
            if (e.particle || e.shadow === false || e.shadow === 0) { continue; }
            var rs = num(e.size, 0.8) * T * 0.34;
            c.save(); c.translate(e._dx, e._dy + rs * 0.95); c.scale(1, 0.38); c.moveTo(rs, 0); c.arc(0, 0, rs, 0, Math.PI * 2); c.restore();
        }
        c.fill();
        for (i = 0; i < n; i++) { this.drawThing(c, list[i], T, rt); }
        this.stat.tris = n;
        this.stat.ents = this.ents.length;
        if (this.debug.colliders) {
            c.lineWidth = 1.2; c.font = "10px Consolas, monospace"; c.textAlign = "center"; c.textBaseline = "bottom";
            for (i = 0; i < n; i++) {
                e = list[i];
                if (e.particle) { continue; }
                c.strokeStyle = e.hits ? "rgba(255,210,0,.9)" : e.tag ? "rgba(0,255,200,.8)" : "rgba(255,255,255,.35)";
                c.beginPath(); c.arc(e._dx, e._dy, e.r * T, 0, Math.PI * 2); c.stroke();
                c.fillStyle = "rgba(255,255,255,.85)"; c.fillText(e.id, e._dx, e._dy - e.r * T - 2);
            }
        }
        this.drawHud();
        if (this.debug.stats) { this.drawStats(); }
    };
    function byLayer(p, q) { return p._dz - q._dz; }
    G.drawThing = function (c, e, T, rt) {
        var S = num(e.size, 0.8) * T, x = e._dx, y = e._dy, moving = (e.vx * e.vx + e.vy * e.vy) > 0.25;
        if (e.bob) { y -= Math.abs(num(e.bob.amp, 0.12) * Math.sin((rt - (e.born || 0)) * num(e.bob.speed, 3))) * T; }
        else if (moving && !e.particle && e.walk !== false) { y -= Math.abs(Math.sin(rt * 13 + (e.born || 0) * 7)) * S * 0.08; }   /* a step */
        var fade = e.particle && e.life != null ? clamp(e.life * 3, 0, 1) : 1;
        c.globalAlpha = (e.flash && Math.sin(rt * 30) > 0) ? 0.3 * fade : fade;
        var feet = y + S * 0.42;
        if (e.float != null) {
            c.font = "bold " + Math.round(S * 0.9) + 'px "Segoe UI", sans-serif'; c.textAlign = "center"; c.textBaseline = "middle";
            c.fillStyle = "rgba(0,0,0,.6)"; c.fillText(e.float, x + 1, y + 1.5);
            c.fillStyle = e.color || "#fff"; c.fillText(e.float, x, y);
        } else if (!(e.sprite && this.drawSprite(c, e.sprite, x, feet, S, e.flip && e.face !== false, this.dpr))) {
            var col = e.color || "#cccccc", shp = e.shape || "circle", r = S / 2;
            c.fillStyle = col;
            c.beginPath();
            if (shp === "box") {
                if (e.rz) { c.save(); c.translate(x, y); c.rotate(e.rz * D2R); c.rect(-r, -r, S, S); c.restore(); }
                else { c.rect(x - r, y - r, S, S); }
            } else if (shp === "diamond") { c.moveTo(x, y - r); c.lineTo(x + r, y); c.lineTo(x, y + r); c.lineTo(x - r, y); c.closePath(); }
            else { c.arc(x, y, r, 0, Math.PI * 2); }
            c.fill();
            if (!e.particle) { c.strokeStyle = mix(col, -0.35); c.lineWidth = Math.max(1, S / 16); c.stroke(); }
        }
        if (e.text != null && e.text !== "") {
            c.font = "bold " + Math.round(S * 0.6) + 'px "Segoe UI", sans-serif'; c.textAlign = "center"; c.textBaseline = "middle";
            c.fillStyle = e.textcolor || "#ffffff"; c.fillText(String(e.text), x, y - S * 0.1);
        }
        c.globalAlpha = 1;
        if (e.label) {
            var lt = String(e.label);
            c.font = 'bold ' + Math.max(10, Math.round(T * 0.34)) + 'px "Segoe UI", sans-serif'; c.textAlign = "center"; c.textBaseline = "bottom";
            var lw = c.measureText(lt).width + 10, lh = Math.max(14, Math.round(T * 0.46)), ly = y - S * 0.62;
            c.fillStyle = "rgba(10,12,20,.72)"; roundRect(c, x - lw / 2, ly - lh, lw, lh, 4); c.fill();
            c.fillStyle = e.labelcolor || "#ffffff"; c.fillText(lt, x, ly - 2);
        }
    };
    function roundRect(c, x, y, w, h, r) {
        c.beginPath();
        c.moveTo(x + r, y); c.lineTo(x + w - r, y); c.quadraticCurveTo(x + w, y, x + w, y + r);
        c.lineTo(x + w, y + h - r); c.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
        c.lineTo(x + r, y + h); c.quadraticCurveTo(x, y + h, x, y + h - r);
        c.lineTo(x, y + r); c.quadraticCurveTo(x, y, x + r, y); c.closePath();
    }
    /* the nearest thing with a tag within a distance of another -- for "talk
       to whoever is next to you", "hit the nearest slime" */
    G.q_near = function (id, tag, dist) {
        var me = this.byId[id], best = "", bd = num(dist, 1.5), i, e;
        if (!me) { return ""; }
        bd = bd * bd;
        for (i = 0; i < this.ents.length; i++) {
            e = this.ents[i];
            if (e === me || e.hidden || e.particle || (tag && e.tag !== tag)) { continue; }
            var dx = e.x - me.x, dy = e.y - me.y, dz = e.z - me.z, d = dx * dx + dy * dy + dz * dz;
            if (d <= bd) { bd = d; best = e.id; }
        }
        return best;
    };
    /* every thing with a tag, within a distance of a place */
    G.q_within = function (x, y, dist, tag) {
        var out = [], i, e, r2 = num(dist, 1) * num(dist, 1);
        for (i = 0; i < this.ents.length; i++) {
            e = this.ents[i];
            if (e.hidden || e.particle || (tag && e.tag !== tag)) { continue; }
            var dx = e.x - x, dy = e.y - y;
            if (dx * dx + dy * dy <= r2) { out.push(e.id); }
        }
        return out;
    };

    /* ------------------------------------------------------------ questions */
    G.q_stats = function () { return this.stat; };
    G.q_entity = function (id) { var e = this.byId[id]; return e ? { x: e.x, y: e.y, z: e.z, vx: e.vx, vy: e.vy, vz: e.vz, ry: e.ry, tag: e.tag || "" } : ""; };
    G.q_focus = function () { try { this.el.focus(); } catch (e) { } return 1; };
})();
