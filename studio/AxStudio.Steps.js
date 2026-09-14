/* =========================================================================
   AxStudio.Steps.js -- a piece of code as steps (see AxStudio.Steps.ahk).

   Top to bottom, one block per statement, said in words. An "if" opens
   into its branches side by side and closes below them; a loop holds what
   it repeats and says so at its foot; "try" holds what it tries with what
   happens if it fails beside it. Between any two steps, and at the top and
   foot of every branch, is a place to add one (the + on the line).

   Clicking a block picks it; AutoHotkey draws what can be done with it in
   the panel on the right. Everything that changes the code goes through
   AutoHotkey (AXD.post "steps"), which changes the text and sends the
   piece back read again -- nothing is changed here.

   Trident: tables for the side-by-side branches (flex wraps unpredictably
   in IE11), borders for the connecting lines, no SVG.
   ========================================================================= */

var AXS = {
    data: null, sel: null, drag: null, justDragged: false,

    load: function (d) {
        this.data = d;
        this.wire();
        this.render();
    },
    esc: function (s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    },
    glyph: { act: "&#xE768;", set: "&#xE70F;", "if": "&#xE8AB;", loop: "&#xE8EE;", "try": "&#xE9D9;",
             end: "&#xE71A;", note: "&#xE8BD;", code: "&#xE943;" },

    render: function () {
        var host = document.getElementById("axsView"), d = this.data;
        if (!host || !d) { return; }
        var h = [], hasRules = d.rules && d.rules.length;
        h.push('<div class="axs-chart' + (d.ro ? ' ro' : '') + '">');
        h.push('<div class="axs-cap axs-top"><span class="ico">&#xE768;</span>' + this.esc(d.when || d.title || "Starts") + '</div>');
        if (hasRules) {
            /* its rules run first: said as they are written; a click changes one */
            h.push(this.join("first") + '<div class="axs-rules"><span class="ico">&#xE945;</span><b>First, its rules</b>' +
                   '<i class="axs-rulesub">no code -- click one to change it</i>');
            for (var r = 0; r < d.rules.length; r++) {
                h.push('<div class="axs-rule" data-srule="' + r + '" title="Change this rule">' + this.esc(d.rules[r]) + '</div>');
            }
            if (!d.ro) { h.push('<div class="axs-rulego" data-sdo="addrule">+ Add a rule</div>'); }
            h.push('</div>');
        }
        if (d.shared && d.shared.length) {
            h.push('<div class="axs-shared">Works on the program&#39;s ' + (d.shared.length === 1 ? 'value ' : 'values ') +
                   this.chips(d.shared, "r") + '</div>');
        }
        if (!d.steps.length && !d.ro) {
            /* nothing to do yet: the first step is one click */
            h.push(this.join(hasRules ? "then" : "") + this.quick() + this.join(""));
        } else {
            h.push(this.list(d.steps, "root", hasRules ? "then" : ""));
        }
        h.push('<div class="axs-cap axs-foot"><span class="ico">&#xE71A;</span>Done</div>');
        h.push('</div>');
        host.innerHTML = h.join("");
    },
    quickKinds: [["msg", "E8BD", "Show a message"], ["ctl", "E71D", "Change a control"], ["set", "E70F", "Change a value"],
                 ["if", "E8AB", "Only if..."], ["run", "E8A7", "Open something"], ["type", "E765", "Type or press keys"],
                 ["uia", "E7C4", "Click in another program"], ["lib", "E82D", "Use a library"], ["call", "E8F4", "Do one of your functions"], ["", "E710", "Something else..."]],
    quick: function () {
        var h = '<div class="axs-quick"><div class="axs-qh">What should happen?</div><div class="axs-qt">', i, q;
        for (i = 0; i < this.quickKinds.length; i++) {
            q = this.quickKinds[i];
            h += '<span class="axs-qk" data-squick="' + q[0] + '"><span class="ico">&#x' + q[1] + ';</span>' + q[2] + '</span>';
        }
        return h + '</div></div>';
    },
    chips: function (names, kind) {
        var s = "", i;
        for (i = 0; i < names.length && i < 6; i++) {
            s += '<span class="axs-chip c-' + kind + '">' + this.esc(names[i]) + '</span>';
        }
        return s;
    },
    /* a join: the line down to what comes next, its arrow, what it means
       (then / each time / either way), and -- unless read only -- the + */
    words: { then: "then", first: "first", each: "each time", either: "then, either way", after: "when it has finished" },
    jl: function (label) {
        return label ? '<span class="axs-jl">' + this.words[label] + '</span>' : '';
    },
    join: function (label) {
        return '<div class="axs-line">' + this.jl(label) + '</div>';
    },
    ins: function (key, pos, label) {
        if (this.data.ro) { return this.join(label); }
        return '<div class="axs-ins" data-ins="' + this.esc(key) + '|' + pos + '" title="Add a step here">' + this.jl(label) +
               '<b>+</b><span class="axs-insl">Add a step</span></div>';
    },
    list: function (steps, key, first) {
        var h = '<div class="axs-list">', i, lab;
        for (i = 0; i < steps.length; i++) {
            lab = (i === 0) ? (first || "") : this.after(steps[i - 1]);
            h += this.ins(key, i, lab) + this.block(steps[i]);
        }
        h += this.ins(key, steps.length, steps.length ? this.after(steps[steps.length - 1]) : (first || "")) + '</div>';
        return h;
    },
    after: function (st) {
        return (st.k === "if" || st.k === "try") ? "either" : st.k === "loop" ? "after" : "";
    },
    head: function (st, extra) {
        var sel = (st.id === this.sel) ? " sel" : "";
        var uses = "";
        if (st.writes && st.writes.length) { uses += this.chips(st.writes, "w"); }
        if (st.reads && st.reads.length) { uses += this.chips(st.reads, "r"); }
        if (st.call) { uses += '<span class="axs-chip c-call" data-sopen="' + this.esc(st.call) + '">see its steps &#x203A;</span>'; }
        if (st.piece) { uses += '<span class="axs-chip c-call" data-spiece="' + this.esc(st.piece) + '">see its steps &#x203A;</span>'; }
        return '<div class="axs-b k-' + st.k + sel + (extra || "") + '" data-sid="' + st.id + '" title="' + this.esc(st.code) +
               (this.data.ro ? '' : '&#10;&#10;Double-click to change it, drag it to move it, right-click for more.') + '">' +
               '<span class="ico">' + (this.glyph[st.k] || this.glyph.code) + '</span>' +
               '<div class="axs-bt">' + this.esc(st.t) + '</div>' +
               (st.k !== "note" && st.code && st.code !== st.t ? '<div class="axs-bc">' + this.esc(st.code) + '</div>' : '') +
               (uses ? '<div class="axs-uses">' + uses + '</div>' : '') + '</div>';
    },
    block: function (st) {
        var h, i, b;
        if (st.k === "if" || (st.k === "try")) {
            /* the test, a line down to the fork, the branches side by side
               (each cell draws its own share of the fork and the join as
               background lines, so short branches still reach the join),
               and a line on down */
            h = '<div class="axs-fork k-' + st.k + '">' + this.head(st) + '<div class="axs-stub"></div>';
            h += '<table class="axs-br" cellspacing="0" cellpadding="0"><tr>';
            var cols = [];
            if (st.k === "try") { cols.push({ l: "Try", key: st.bkey, steps: st.body }); }
            for (i = 0; i < st.br.length; i++) { cols.push(st.br[i]); }
            for (i = 0; i < cols.length; i++) {
                b = cols[i];
                /* one column alone has no fork to draw: "only" keeps its
                   crossbars from running out to nothing */
                h += '<td class="axs-col' + (cols.length === 1 ? ' only' : i === 0 ? ' first' : i === cols.length - 1 ? ' last' : ' mid') +
                     (b.none ? ' none' : '') + '">' +
                     '<div class="axs-bl' + (i === 0 && st.k === "if" && !st.sw ? ' yes' : '') + '">' + this.esc(b.l) + '</div>' +
                     (b.none && !this.data.ro
                        ? '<div class="axs-ins axs-else" data-ins="' + this.esc(b.key) + '|0" title="' + this.esc(b.add || "Add what happens otherwise") + '">' +
                          '<b>+</b><span class="axs-insl">' + this.esc(b.add || "Add what happens otherwise") + '</span></div>'
                        : this.list(b.steps, b.key)) + '<div class="axs-cend"></div></td>';
            }
            h += '</tr></table><div class="axs-stub"></div></div>';
            return h;
        }
        if (st.k === "loop") {
            return '<div class="axs-loop">' + this.head(st) +
                   '<div class="axs-lbody">' + this.list(st.body, st.bkey, "each") + '</div>' +
                   '<div class="axs-lfoot"><span class="ico">&#xE72C;</span>back to the top</div></div>';
        }
        return this.head(st);
    },

    pick: function (id) {
        this.sel = id;
        var all = document.querySelectorAll("#axsView .axs-b"), i;
        for (i = 0; i < all.length; i++) {
            all[i].className = all[i].className.replace(/ sel\b/, "") + (all[i].getAttribute("data-sid") === id ? " sel" : "");
        }
    },

    dragMove: function (ev) {
        var d = this.drag;
        if (!d) { return; }
        if (!d.on) {
            if (Math.abs(ev.clientX - d.x) + Math.abs(ev.clientY - d.y) < 7) { return; }
            d.on = true;
            d.ghost = document.createElement("div");
            d.ghost.className = "axs-ghost";
            var bt = d.el.querySelector(".axs-bt");
            d.ghost.innerHTML = bt ? bt.innerHTML : "a step";
            document.body.appendChild(d.ghost);
            d.el.className += " axs-moving";
            var v = document.getElementById("axsView");
            if (v) { v.className = "axs-dragging"; }
        }
        d.ghost.style.left = (ev.clientX + 14) + "px";
        d.ghost.style.top = (ev.clientY + 10) + "px";
        var t = document.elementFromPoint(ev.clientX, ev.clientY), over = null;
        while (t && t.getAttribute) { if (t.getAttribute("data-ins") !== null) { over = t; break; } t = t.parentNode; }
        if (over !== d.over) {
            if (d.over) { d.over.className = d.over.className.replace(/ drop\b/g, ""); }
            if (over) { over.className += " drop"; }
            d.over = over;
        }
        if (ev.preventDefault) { ev.preventDefault(); }
    },
    dragEnd: function () {
        var d = this.drag;
        this.drag = null;
        if (!d || !d.on) { return; }
        if (d.ghost && d.ghost.parentNode) { d.ghost.parentNode.removeChild(d.ghost); }
        d.el.className = d.el.className.replace(/ axs-moving\b/g, "");
        var v = document.getElementById("axsView");
        if (v) { v.className = ""; }
        this.justDragged = true;
        var self = this;
        setTimeout(function () { self.justDragged = false; }, 300);
        if (d.over) {
            d.over.className = d.over.className.replace(/ drop\b/g, "");
            AXD.post("steps", { act: "move", id: d.id, at: d.over.getAttribute("data-ins") });
        }
    },

    wire: function () {
        var view = document.getElementById("axsView");
        if (!view || view.getAttribute("data-wired")) { return; }
        view.setAttribute("data-wired", "1");
        var self = this, root = document.getElementById("axsWrap") || view;
        var up = function (el, attr) {
            while (el && el.getAttribute) { if (el.getAttribute(attr) !== null) { return el; } el = el.parentNode; }
            return null;
        };
        root.onclick = function (ev) {
            ev = ev || window.event;
            var t = ev.target || ev.srcElement, el;
            if ((el = up(t, "data-sopen"))) { AXD.post("steps", { act: "open", fn: el.getAttribute("data-sopen") }); return; }
            if (self.justDragged) { self.justDragged = false; return; }
            if ((el = up(t, "data-ins"))) { AXD.post("steps", { act: "ins", at: el.getAttribute("data-ins") }); return; }
            if ((el = up(t, "data-squick"))) { AXD.post("steps", { act: "quick", kind: el.getAttribute("data-squick") }); return; }
            if ((el = up(t, "data-srule"))) { AXD.post("steps", { act: "rule", i: el.getAttribute("data-srule") }); return; }
            if ((el = up(t, "data-spiece")) && el.className.indexOf("axs-chip") >= 0) {
                AXD.post("steps", { act: "piece", key: el.getAttribute("data-spiece") }); return;
            }
            if ((el = up(t, "data-sid"))) {
                var id = el.getAttribute("data-sid");
                self.pick(id);
                AXD.post("steps", { act: "pick", id: id });
                return;
            }
            if ((el = up(t, "data-spiece"))) { AXD.post("steps", { act: "piece", key: el.getAttribute("data-spiece") }); return; }
            if ((el = up(t, "data-sdo"))) { AXD.post("steps", { act: "do", v: el.getAttribute("data-sdo") }); return; }
            if (t.id === "axsView") { self.pick(null); AXD.post("steps", { act: "pick", id: "" }); }
        };
        /* the bar over the chart: which piece, Steps or Code, add */
        var head = document.getElementById("axsHead");
        if (head) {
            head.onclick = function (ev) {
                ev = ev || window.event;
                var el = up(ev.target || ev.srcElement, "data-sdo");
                if (el) { AXD.post("steps", { act: "do", v: el.getAttribute("data-sdo") }); }
            };
        }
        root.oncontextmenu = function (ev) {
            ev = ev || window.event;
            var el = up(ev.target || ev.srcElement, "data-sid");
            if (!el || self.data.ro) { return; }
            var id = el.getAttribute("data-sid");
            self.pick(id);
            AXD.post("steps", { act: "menu", id: id });
            ev.returnValue = false;
            if (ev.preventDefault) { ev.preventDefault(); }
            return false;
        };
        /* drag a step onto a + to move it there: the + under the pointer
           lights, and letting go on it moves the step (AutoHotkey does it) */
        root.onmousedown = function (ev) {
            ev = ev || window.event;
            var t = ev.target || ev.srcElement;
            if (!self.data || self.data.ro || ev.button === 2) { return; }
            var el = up(t, "data-sid");
            if (!el || up(t, "data-sopen") || up(t, "data-spiece")) { return; }
            self.drag = { id: el.getAttribute("data-sid"), el: el, x: ev.clientX, y: ev.clientY, on: false, over: null, ghost: null };
        };
        document.addEventListener("mousemove", function (ev) { self.dragMove(ev); });
        document.addEventListener("mouseup", function () { self.dragEnd(); });
        root.ondblclick = function (ev) {
            ev = ev || window.event;
            var el = up(ev.target || ev.srcElement, "data-sid");
            if (el) { AXD.post("steps", { act: "do", v: "change" }); }
        };
        root.onkeydown = function (ev) {
            ev = ev || window.event;
            var t = ev.target || ev.srcElement;
            if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA")) { return; }
            if (!self.sel) { return; }
            var k = ev.keyCode, v = "";
            if (k === 46) { v = "delete"; }
            else if (k === 113 || k === 13) { v = "change"; }
            else if (ev.altKey && k === 38) { v = "up"; }
            else if (ev.altKey && k === 40) { v = "down"; }
            if (v) { AXD.post("steps", { act: "do", v: v }); ev.returnValue = false; return false; }
        };
    }
};
