/* =========================================================================
   AxAudio.js -- a sound player for Trident (IE11): the page's own <audio>
   (MP3 and AAC/M4A in IE11), with a small player drawn round it.

   AutoHotkey talks to it through AXAU:
       AXAU.make(id, optionsJson)
       AXAU.call(id, "name", argsJson)      play pause stop seek set get ...
   and it talks back through #<id>_q / #<id>_req, as the other components do.
   ES5 only.
   ========================================================================= */
(function () {
    if (window.AXAU) { return; }
    var AXAU = window.AXAU = { inst: {} };
    function $(id) { return document.getElementById(id); }
    function fmt(s) {
        if (!isFinite(s) || s < 0) { s = 0; }
        s = Math.floor(s);
        var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, x = s % 60;
        return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (x < 10 ? "0" : "") + x;
    }

    AXAU.make = function (id, json) {
        var o = {};
        try { o = JSON.parse(json || "{}"); } catch (e) { }
        AXAU.inst[id] = new Au(id, o);
        return 1;
    };
    AXAU.call = function (id, name, json) {
        var a = AXAU.inst[id];
        if (!a || typeof a["q_" + name] !== "function") { return ""; }
        var r = a["q_" + name].apply(a, JSON.parse(json || "[]"));
        return r == null ? "" : (typeof r === "object" ? JSON.stringify(r) : String(r));
    };
    /* a sound with no player: fire and forget, any number at once */
    AXAU.sound = function (src, vol) {
        try { var s = new Audio(src); s.volume = Math.max(0, Math.min(1, vol)); s.play(); } catch (e) { }
        return 1;
    };

    function Au(id, o) {
        var self = this;
        this.id = id; this.el = $(id); this.a = $(id + "_a");
        this.qdata = $(id + "_q"); this.req = $(id + "_req"); this.queue = [];
        this.listen = {}; this.lastTime = 0;
        this.play = $(id + "_play"); this.bar = $(id + "_bar"); this.fill = $(id + "_fill");
        this.t = $(id + "_t"); this.d = $(id + "_d"); this.vol = $(id + "_vol");
        var a = this.a;
        a.loop = !!o.loop;
        if (o.volume != null) { a.volume = Math.max(0, Math.min(1, o.volume / 100)); }
        a.addEventListener("timeupdate", function () { self.ui(); self.tick(); });
        a.addEventListener("durationchange", function () { self.ui(); });
        a.addEventListener("loadedmetadata", function () { self.ui(); self.post({ kind: "ready", duration: a.duration }); });
        a.addEventListener("play", function () { self.ui(); self.post({ kind: "play" }); });
        a.addEventListener("pause", function () { self.ui(); self.post({ kind: "pause" }); });
        a.addEventListener("ended", function () { self.ui(); self.post({ kind: "end" }); });
        a.addEventListener("volumechange", function () { self.ui(); });
        a.addEventListener("error", function () {
            var c = a.error ? a.error.code : 0;
            self.post({ kind: "error", code: c, message: ["", "stopped", "network", "can't decode", "format not supported"][c] || "error" });
        });
        if (this.play) { this.play.onclick = function () { self.q_toggle(); }; }
        if (this.vol) { this.vol.onclick = function () { a.muted = !a.muted; }; }
        if (this.bar) {
            this.bar.onmousedown = function (e) {
                e = e || window.event;
                self.seekTo(e);
                document.onmousemove = function (ev) { self.seekTo(ev || window.event); return false; };
                document.onmouseup = function () { document.onmousemove = null; document.onmouseup = null; };
                return false;
            };
        }
        this.el.className += " axau-live";
        this.ui();
        if (o.autoplay) { this.q_play(); }
    }
    var P = Au.prototype;
    P.post = function (m) {
        if (!this.req || !this.listen[m.kind]) { return; }
        this.queue.push(m);
        var self = this;
        if (!this.qTimer) { this.qTimer = window.setTimeout(function () { self.pump(); }, 0); }
    };
    P.pump = function () {
        this.qTimer = null;
        if (!this.queue.length) { return; }
        this.qdata.value = JSON.stringify(this.queue.shift());
        try { this.req.click(); } catch (e) { try { this.req.fireEvent("onclick"); } catch (e2) { } }
        if (this.queue.length) { var self = this; this.qTimer = window.setTimeout(function () { self.pump(); }, 0); }
    };
    /* where the sound is, told to AutoHotkey at most every `every` ms */
    P.tick = function () {
        if (!this.listen.time) { return; }
        var now = new Date().getTime();
        if (now - this.lastTime < (this.every || 250)) { return; }
        this.lastTime = now;
        this.post({ kind: "time", pos: this.a.currentTime, duration: this.a.duration });
    };
    P.seekTo = function (e) {
        var r = this.bar.getBoundingClientRect(), f = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
        if (isFinite(this.a.duration)) { this.a.currentTime = f * this.a.duration; }
        this.ui();
    };
    P.ui = function () {
        var a = this.a, d = isFinite(a.duration) ? a.duration : 0;
        if (this.play) { this.play.innerHTML = a.paused ? "&#xE768;" : "&#xE769;"; this.play.title = a.paused ? "Play" : "Pause"; }
        if (this.fill) { this.fill.style.width = (d ? a.currentTime / d * 100 : 0) + "%"; }
        if (this.t) { this.t.innerHTML = fmt(a.currentTime); }
        if (this.d) { this.d.innerHTML = fmt(d); }
        if (this.vol) { this.vol.innerHTML = a.muted || a.volume === 0 ? "&#xE74F;" : a.volume < 0.34 ? "&#xE993;" : a.volume < 0.67 ? "&#xE994;" : "&#xE995;"; }
    };

    /* ------------------------------------------------------------ asked */
    P.q_play = function () { try { this.a.play(); } catch (e) { } return 1; };
    P.q_pause = function () { this.a.pause(); return 1; };
    P.q_toggle = function () { if (this.a.paused) { this.q_play(); } else { this.a.pause(); } return 1; };
    P.q_stop = function () { this.a.pause(); try { this.a.currentTime = 0; } catch (e) { } this.ui(); return 1; };
    P.q_seek = function (s) { try { this.a.currentTime = Math.max(0, s); } catch (e) { } this.ui(); return 1; };
    P.q_load = function (src, play) { this.a.src = src; this.a.load(); if (play) { this.q_play(); } this.ui(); return 1; };
    P.q_listen = function (kind, on, every) { this.listen[kind] = !!on; if (every) { this.every = every; } return 1; };
    P.q_set = function (name, v) {
        var a = this.a;
        switch (name) {
        case "volume": a.volume = Math.max(0, Math.min(1, v / 100)); break;
        case "muted": a.muted = !!v; break;
        case "loop": a.loop = !!v; break;
        case "rate": a.playbackRate = Math.max(0.25, Math.min(4, v)); break;
        }
        this.ui();
        return 1;
    };
    P.q_get = function () {
        var a = this.a;
        return { pos: a.currentTime, duration: isFinite(a.duration) ? a.duration : 0, paused: a.paused ? 1 : 0,
                 ended: a.ended ? 1 : 0, volume: Math.round(a.volume * 100), muted: a.muted ? 1 : 0,
                 loop: a.loop ? 1 : 0, rate: a.playbackRate, src: a.currentSrc || a.src };
    };
})();
