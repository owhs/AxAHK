/* Overlay scrollbars for Trident.

   Trident's scrollbars can only be recoloured (scrollbar-*-color), never
   reshaped; on Windows 10/11 it draws them in the modern style whatever the
   sheet says (flat, chevron arrows), they take width out of every pane -- a
   row's right-hand button ends up under them -- and they paint above every
   z-index. So the native bars are hidden (-ms-overflow-style: none still
   scrolls) and drawn here instead. Two kinds, chosen by the theme through the
   probe's width:

     thin     (.ax-sb-probe width 0, the default): one rounded thumb per axis
              in a 14px hit strip that never resizes (the bar widens on :hover
              inside it, so the target does not move under the pointer).
              Colour: the theme's scrollbar-face-color, as a default any theme
              rule for .ax-sb-bar outranks.
     classic  (.ax-sb-probe { width: 2px; }, win98 / winxp): a whole bar --
              arrow buttons (.ax-sb-up / .ax-sb-dn), the track (the strip
              itself) and the thumb (.ax-sb-bar) -- styled by the theme. Arrows
              step and repeat while held, the track pages, the thumb drags.
     native   (.ax-sb-probe { width: 1px; }): Trident's own.

   Two sets of bars (.ax-sb-v / .ax-sb-h, styled by class):
     page     the page's own scroller (#content, else the document). With
              "always" it stays up for good and the pane gives up a gutter for
              it (a transparent right border), like a real scrollbar -- so
              nothing sits under it.
     hover    whatever other pane is under the mouse or scrolling; shows while
              it is in use, fades when idle (classic: while the mouse is over).
   "always" is the theme's default through the probe's height (1px: win98 and
   winxp), or window.axSbAlways = "always" | "auto" (AxWindow's Scrollbars).

   z-index 99990: above the page, under menus, tips, dialogs (100000+).
*/
(function () {
    if (window.axThinScroll) { return; }
    window.axThinScroll = true;
    var d = document, root = d.documentElement;
    var IDLE = 900, MIN = 24, HIT = 14, CL = 16, STEP = 40;

    var st = d.createElement("style");
    st.type = "text/css";
    st.textContent = "html.ax-thin, html.ax-thin * { -ms-overflow-style: none !important; }"
        + ".ax-sb { position: fixed; display: none; z-index: 99990; opacity: 0; visibility: hidden;"
        + " transition: opacity .2s ease, visibility 0s linear .2s; }"
        + ".ax-sb.on, .ax-sb.drag { opacity: 1; visibility: visible; transition: opacity .12s ease; }"
        + ".ax-sb-bar { position: absolute; border-radius: 5px; opacity: .6; transition: width .12s ease, height .12s ease, opacity .12s ease; }"
        + ".ax-sb-v { width: " + HIT + "px; } .ax-sb-v .ax-sb-bar { right: 2px; top: 0; bottom: 0; width: 6px; }"
        + ".ax-sb-h { height: " + HIT + "px; } .ax-sb-h .ax-sb-bar { bottom: 2px; left: 0; right: 0; height: 6px; }"
        + ".ax-sb-v:hover .ax-sb-bar, .ax-sb-v.drag .ax-sb-bar { width: 9px; opacity: .95; }"
        + ".ax-sb-h:hover .ax-sb-bar, .ax-sb-h.drag .ax-sb-bar { height: 9px; opacity: .95; }"
        /* thin, always up: the thumb rides in the gutter, a track under it */
        + ".ax-sb.full .ax-sb-bar { top: auto; bottom: auto; }"
        + ".ax-sb-up, .ax-sb-dn { display: none; position: absolute; }"
        /* classic: the whole bar, no fade, no hover growth; the theme paints it */
        + "html.ax-classic .ax-sb { transition: none; }"
        + "html.ax-classic .ax-sb-bar, html.ax-classic .ax-sb-v .ax-sb-bar, html.ax-classic .ax-sb-h .ax-sb-bar { opacity: 1; transition: none; }"
        + "html.ax-classic .ax-sb-v .ax-sb-bar { left: 0; right: 0; width: auto; }"
        + "html.ax-classic .ax-sb-h .ax-sb-bar { top: 0; bottom: 0; height: auto; }"
        + "html.ax-classic .ax-sb-up, html.ax-classic .ax-sb-dn { display: block; }"
        + "html.ax-classic .ax-sb-v .ax-sb-up { left: 0; right: 0; top: 0; height: " + CL + "px; }"
        + "html.ax-classic .ax-sb-v .ax-sb-dn { left: 0; right: 0; bottom: 0; height: " + CL + "px; }"
        + "html.ax-classic .ax-sb-h .ax-sb-up { top: 0; bottom: 0; left: 0; width: " + CL + "px; }"
        + "html.ax-classic .ax-sb-h .ax-sb-dn { top: 0; bottom: 0; right: 0; width: " + CL + "px; }"
        + ".ax-sb-probe { position: absolute; left: -9999px; top: 0; width: 0; height: 0; visibility: hidden; }";
    var head = d.getElementsByTagName("head")[0];
    head.insertBefore(st, head.firstChild);      /* first, so any theme rule wins */
    /* the bar's default colour (the theme's scrollbar-face-color) as a rule
       at the very top of <head>: any theme rule for .ax-sb-bar outranks it */
    var colSt = d.createElement("style"), colNow = "";
    colSt.type = "text/css"; head.insertBefore(colSt, head.firstChild);
    function paint() {
        var c = face();
        if (c !== colNow) { colNow = c; colSt.textContent = ".ax-sb-bar { background-color: " + c + "; }"; }
    }

    function mk(id, axis) {
        var t = d.createElement("div"), u = d.createElement("div"), b = d.createElement("div"), n = d.createElement("div");
        t.id = id; t.className = "ax-sb ax-sb-" + axis; u.className = "ax-sb-up"; b.className = "ax-sb-bar"; n.className = "ax-sb-dn";
        t.appendChild(u); t.appendChild(b); t.appendChild(n); d.body.appendChild(t);
        t.bar = b;
        return t;
    }
    var probe = d.createElement("div"); probe.className = "ax-sb-probe"; d.body.appendChild(probe);
    /* a set of bars: the hover one keeps the old ids (#axSbV / #axSbH) */
    function Bars(v, h, page) { var o = { V: mk(v, "v"), H: mk(h, "h"), cur: null, hideT: 0, frame: 0, page: page }; o.V.set = o.H.set = o; return o; }
    var P = Bars("axSbPV", "axSbPH", true), Hv = Bars("axSbV", "axSbH", false);

    var drag = null, over = false, kind = "", always = false, mx = -1, my = -1, rep = 0, gutEl = null, gutW = 0;

    function has(el, n) { return (" " + el.className + " ").indexOf(" " + n + " ") >= 0; }
    function cls(el, n, on) {
        if (on && !has(el, n)) { el.className += " " + n; }
        if (!on && has(el, n)) { el.className = (" " + el.className + " ").replace(" " + n + " ", " ").replace(/^\s+|\s+$/g, ""); }
    }
    /* which kind the theme asks for ("" = the native bars), and whether bars stay up */
    function mode() {
        var w = probe.offsetWidth, k = w === 0 ? "thin" : w === 2 ? "classic" : "";
        var want = window.axSbAlways === "always" ? true : window.axSbAlways === "auto" ? false : probe.offsetHeight === 1;
        if (k !== kind) {
            kind = k;
            cls(root, "ax-thin", k !== "");
            cls(root, "ax-classic", k === "classic");
            var all = [P.V, P.H, Hv.V, Hv.H];
            for (var i = 0; i < all.length; i++) { all[i].bar.style.top = all[i].bar.style.height = all[i].bar.style.left = all[i].bar.style.width = ""; }
        }
        if (!k) { want = false; }
        if (want !== always) { always = want; if (!always) { gutter(null); off(P); } }
        return k;
    }
    function face() {
        var c = (d.body.currentStyle || {}).scrollbarFaceColor;
        return (c && c !== "transparent") ? c : "rgba(128,128,128,.7)";
    }
    function page(el) { return el === root || el === d.body; }
    function ov(el, ax) { var s = el.currentStyle || window.getComputedStyle(el); return ax === "y" ? s.overflowY : s.overflowX; }
    function canY(el) {
        if (el.scrollHeight <= el.clientHeight + 1) { return false; }
        if (page(el)) { return true; }
        var o = ov(el, "y"); return o === "auto" || o === "scroll";
    }
    function canX(el) {
        if (el.scrollWidth <= el.clientWidth + 1) { return false; }
        if (page(el)) { return true; }
        var o = ov(el, "x"); return o === "auto" || o === "scroll";
    }
    function mine(el) { for (; el && el.nodeType === 1; el = el.parentNode) { if (has(el, "ax-sb")) { return el.set; } } return null; }
    function scroller(el) {
        for (var n = 0; el && el.nodeType === 1 && n < 40; el = el.parentNode, n++) {
            if (canY(el) || canX(el)) { return page(el) ? root : el; }
        }
        return (canY(root) || canX(root)) ? root : null;
    }
    /* the page's own scroller: AxGui's #content, else the document */
    function pageEl() {
        var c = d.getElementById("content");
        if (c) { var o = ov(c, "y"); if (o === "auto" || o === "scroll") { return c; } }
        return root;
    }
    /* a gutter for the page's bar: a transparent right border, so the pane's
       content stops short of it (the background runs on under it) */
    function gutter(el) {
        var w = kind === "classic" ? CL : HIT;
        if (gutEl && (gutEl !== el || gutW !== w)) { gutEl.style.borderRight = ""; gutEl = null; }
        if (el && el !== root && !gutEl) { el.style.borderRight = w + "px solid transparent"; gutEl = el; gutW = w; }
    }
    function box(el) {
        if (el === root) { return { l: 0, t: 0, w: root.clientWidth, h: root.clientHeight }; }
        var r = el.getBoundingClientRect();
        return { l: r.left + el.clientLeft, t: r.top + el.clientTop, w: el.clientWidth, h: el.clientHeight };
    }
    /* the part of el actually on screen: every ancestor that clips (a card,
       the page's own scroller) and the window cut it down */
    function visible(el, b) {
        var v = { l: b.l, t: b.t, r: b.l + b.w, b: b.t + b.h }, p, s, r;
        for (p = el === root ? null : el.parentNode; p && p.nodeType === 1 && p !== root; p = p.parentNode) {
            s = p.currentStyle || window.getComputedStyle(p);
            if (s.overflowX === "visible" && s.overflowY === "visible") { continue; }
            r = p.getBoundingClientRect();
            v.l = Math.max(v.l, r.left + p.clientLeft); v.t = Math.max(v.t, r.top + p.clientTop);
            v.r = Math.min(v.r, r.left + p.clientLeft + p.clientWidth); v.b = Math.min(v.b, r.top + p.clientTop + p.clientHeight);
        }
        v.l = Math.max(v.l, 0); v.t = Math.max(v.t, 0);
        v.r = Math.min(v.r, root.clientWidth); v.b = Math.min(v.b, root.clientHeight);
        return v;
    }
    /* put a strip at x,y (w x h) and show only what lies inside v */
    function put(t, x, y, w, h, v) {
        var cl = Math.max(0, v.l - x), ct = Math.max(0, v.t - y), cr = Math.min(w, v.r - x), cb = Math.min(h, v.b - y);
        if (cr - cl < 3 || cb - ct < 8 && has(t, "ax-sb-v") || cr - cl < 8 && has(t, "ax-sb-h") || cb - ct < 3) { t.style.display = "none"; return; }
        t.style.left = x + "px"; t.style.top = y + "px"; t.style.width = w + "px"; t.style.height = h + "px";
        t.style.clip = (cl || ct || cr < w || cb < h) ? "rect(" + ct + "px," + cr + "px," + cb + "px," + cl + "px)" : "rect(auto,auto,auto,auto)";
        t.style.display = "block";
    }
    function metrics(el) {
        var m = { sh: el.scrollHeight, sw: el.scrollWidth, ch: el.clientHeight, cw: el.clientWidth, top: el.scrollTop, left: el.scrollLeft };
        if (el === root) {        /* the page scrolls on html or body, whichever moved */
            m.sh = Math.max(root.scrollHeight, d.body.scrollHeight); m.sw = Math.max(root.scrollWidth, d.body.scrollWidth);
            m.top = root.scrollTop || d.body.scrollTop; m.left = root.scrollLeft || d.body.scrollLeft;
        }
        return m;
    }
    function place(o) {
        o.frame = 0;
        var cur = o.cur;
        if (!cur || (cur !== root && !root.contains(cur))) { o.cur = null; o.V.style.display = o.H.style.display = "none"; return; }
        var b = box(cur), v = visible(cur, b), m = metrics(cur), y = canY(cur), x = canX(cur), both = y && x;
        /* the page's bar, always up: in the gutter just right of the content */
        var inGut = o.page && always && cur === gutEl, W = kind === "classic" ? CL : HIT;
        if (inGut) { v.r = Math.min(root.clientWidth, v.r + W); }
        var right = inGut ? b.l + b.w + W : b.l + b.w;
        paint();
        cls(o.V, "full", inGut && kind !== "classic"); cls(o.H, "full", inGut && kind !== "classic");
        if (kind === "classic" || inGut) {
            /* the whole bar along the edge; the thumb moves inside it */
            var E = kind === "classic" ? CL : 0, S = kind === "classic" ? CL : HIT;
            if (y && b.h > 2 * E + 8) {
                var vh = b.h - (both ? S : 0), vl = vh - 2 * E, vth = Math.max(kind === "classic" ? 8 : MIN, Math.round(vl * m.ch / m.sh));
                o.V.bar.style.top = (E + Math.round((vl - vth) * m.top / Math.max(1, m.sh - m.ch))) + "px";
                o.V.bar.style.height = vth + "px";
                put(o.V, right - S, b.t, S, vh, v);
            } else { o.V.style.display = "none"; }
            if (x && b.w > 2 * E + 8) {
                var hw = b.w - (both && !inGut ? S : 0), hl = hw - 2 * E, hth = Math.max(kind === "classic" ? 8 : MIN, Math.round(hl * m.cw / m.sw));
                o.H.bar.style.left = (E + Math.round((hl - hth) * m.left / Math.max(1, m.sw - m.cw))) + "px";
                o.H.bar.style.width = hth + "px";
                put(o.H, b.l, b.t + b.h - S, hw, S, v);
            } else { o.H.style.display = "none"; }
            return;
        }
        o.V.bar.style.top = o.V.bar.style.height = o.H.bar.style.left = o.H.bar.style.width = "";
        if (y && b.h > MIN) {
            var tl = b.h - (both ? HIT : 4), th = Math.max(MIN, Math.round(tl * m.ch / m.sh));
            var ty = b.t + 2 + Math.round((tl - th) * m.top / Math.max(1, m.sh - m.ch));
            put(o.V, right - HIT, ty, HIT, th, v);
        } else { o.V.style.display = "none"; }
        if (x && b.w > MIN) {
            var wl = b.w - (both ? HIT : 4), tw = Math.max(MIN, Math.round(wl * m.cw / m.sw));
            var tx = b.l + 2 + Math.round((wl - tw) * m.left / Math.max(1, m.sw - m.cw));
            put(o.H, tx, b.t + b.h - HIT, tw, HIT, v);
        } else { o.H.style.display = "none"; }
    }
    function queue(o) { if (!o.frame) { o.frame = window.requestAnimationFrame(function () { place(o); }); } }
    function off(o) { if (o.hideT) { window.clearTimeout(o.hideT); o.hideT = 0; } cls(o.V, "on", false); cls(o.H, "on", false); }
    /* the page's bar, always up; its pane with a gutter only while it scrolls */
    function pinPage() {
        if (!always) { return; }
        var el = pageEl(), need = el !== root && (canY(el) || (gutEl === el && el.scrollHeight > el.clientHeight + 1));
        gutter(need ? el : null);
        if (canY(el) || canX(el)) {
            P.cur = el; queue(P);
            cls(P.V, "on", true); cls(P.H, "on", true);
        } else { P.cur = null; queue(P); }
    }
    function show(el) {
        if (!el) { return; }
        if (!mode()) { off(P); off(Hv); P.V.style.display = P.H.style.display = Hv.V.style.display = Hv.H.style.display = "none"; gutter(null); return; }
        if (always && (el === pageEl() || (el === root && pageEl() === root))) { pinPage(); return; }
        var o = Hv;
        o.cur = el;
        queue(o);
        cls(o.V, "on", true); cls(o.H, "on", true);
        if (o.hideT) { window.clearTimeout(o.hideT); }
        o.hideT = window.setTimeout(function () { hide(o); }, IDLE);
    }
    /* is the mouse over the pane these bars belong to? (classic bars stay up then) */
    function pointerIn(o) {
        if (!o.cur || mx < 0) { return false; }
        var v = visible(o.cur, box(o.cur));
        return mx >= v.l && mx < v.r && my >= v.t && my < v.b;
    }
    function hide(o) {
        o.hideT = 0;
        if ((drag && drag.o === o) || over === o || (rep && rep.o === o) || (kind === "classic" && pointerIn(o))) {
            o.hideT = window.setTimeout(function () { hide(o); }, IDLE); return;
        }
        cls(o.V, "on", false); cls(o.H, "on", false);      /* fades; visibility drops after it */
    }

    /* what is under the mouse, what scrolls */
    window.addEventListener("mouseover", function (e) {
        if (drag) { return; }
        var t = e.target || e.srcElement;
        if (mine(t)) { return; }
        var s = scroller(t);
        if (s) { show(s); }
    }, true);
    d.addEventListener("mousemove", function (e) { mx = e.clientX; my = e.clientY; }, true);
    d.addEventListener("scroll", function (e) {
        var t = e.target || e.srcElement;
        if (drag && t !== drag.o.cur && !(drag.o.cur === root && (t === d || page(t)))) { return; }
        show(t === d || page(t) ? root : t);
    }, true);
    function refresh() { mode(); pinPage(); if (Hv.cur) { queue(Hv); } }
    /* a panel closing (a popover, a dialog): the bars of what scrolls inside it go
       with it, now -- not when their idle timer runs out after the panel has faded */
    window.axSbDrop = function (el) {
        var c = Hv.cur;
        if (!c || c === root || (el && el !== c && !el.contains(c))) { return; }
        off(Hv); Hv.cur = null; Hv.V.style.display = Hv.H.style.display = "none";
    };
    window.addEventListener("resize", refresh, false);
    /* a redraw (a page switch, a list filled in) can make the page scroll or stop */
    var mt = 0;
    if (window.MutationObserver) {
        new MutationObserver(function () { if (!mt) { mt = window.setTimeout(function () { mt = 0; refresh(); }, 60); } })
            .observe(d.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
    }

    /* scrolling it: the page scrolls on html or body, whichever moved */
    function target(o) { return (o.cur === root && !root.scrollTop && !root.scrollLeft && (d.body.scrollTop || d.body.scrollLeft)) ? d.body : o.cur; }
    function by(o, vert, px) { var t = target(o); if (vert) { t.scrollTop += px; } else { t.scrollLeft += px; } }
    /* an arrow or the track held down: once, then again and again */
    function hold(o, fn) {
        fn();
        rep = { o: o, t: window.setTimeout(function again() { fn(); if (rep) { rep.t = window.setTimeout(again, 50); } }, 350) };
    }
    function unhold() { if (rep) { window.clearTimeout(rep.t); rep = 0; } }

    /* the thumbs: hover (CSS) widens the bar; press and drag to scroll */
    function wire(t, vert) {
        var o = t.set;
        t.onmouseenter = function () { over = o; if (o.hideT) { window.clearTimeout(o.hideT); o.hideT = 0; } };
        t.onmouseleave = function () { over = false; if (!o.page || !always) { if (!o.hideT) { o.hideT = window.setTimeout(function () { hide(o); }, IDLE); } } };
        t.addEventListener("mousedown", function (e) {
            if (!o.cur || e.button !== 0) { return; }
            var hit = e.target || e.srcElement, m = metrics(o.cur), b = box(o.cur);
            e.preventDefault(); e.stopPropagation();
            var full = kind === "classic" || has(t, "full");
            if (full && hit !== t.bar) {
                var sign = 0, pg = (vert ? m.ch : m.cw) - STEP;
                if (has(hit, "ax-sb-up")) { sign = -1; }
                else if (has(hit, "ax-sb-dn")) { sign = 1; }
                if (sign) { cls(hit, "down", true); t.held = hit; hold(o, function () { by(o, vert, sign * STEP); }); return; }
                /* the track: page toward the press, until the thumb reaches it */
                var at = vert ? e.clientY : e.clientX;
                hold(o, function () {
                    var r = t.bar.getBoundingClientRect(), lo = vert ? r.top : r.left, hi = vert ? r.bottom : r.right;
                    if (at < lo) { by(o, vert, -pg); } else if (at > hi) { by(o, vert, pg); } else { unhold(); }
                });
                return;
            }
            var E = kind === "classic" ? 2 * CL : 0;
            var len = full
                ? (vert ? t.offsetHeight - E - t.bar.offsetHeight : t.offsetWidth - E - t.bar.offsetWidth)
                : (vert ? b.h - t.offsetHeight - 4 : b.w - t.offsetWidth - 4);
            drag = { o: o, t: t, y: vert, at: vert ? e.clientY : e.clientX, from: vert ? m.top : m.left,
                     k: (vert ? m.sh - m.ch : m.sw - m.cw) / Math.max(1, len) };
            cls(t, "drag", true);
        }, false);
        t.addEventListener("click", function (e) { e.stopPropagation(); }, false);
    }
    wire(P.V, true); wire(P.H, false); wire(Hv.V, true); wire(Hv.H, false);
    d.addEventListener("mousemove", function (e) {
        if (!drag || !drag.o.cur) { return; }
        var v = Math.round(drag.from + ((drag.y ? e.clientY : e.clientX) - drag.at) * drag.k), t = target(drag.o);
        if (drag.y) { t.scrollTop = v; } else { t.scrollLeft = v; }
        e.preventDefault(); e.stopPropagation();
    }, true);
    d.addEventListener("mouseup", function (e) {
        var mineUp = drag || rep;
        unhold();
        var all = [P.V, P.H, Hv.V, Hv.H];
        for (var i = 0; i < all.length; i++) { if (all[i].held) { cls(all[i].held, "down", false); all[i].held = null; } }
        if (!mineUp) { return; }
        var o = drag ? drag.o : null;
        if (drag) { cls(drag.t, "drag", false); drag = null; }
        e.stopPropagation();
        if (o && o.cur) { show(o.cur); }
    }, true);

    refresh();
})();
