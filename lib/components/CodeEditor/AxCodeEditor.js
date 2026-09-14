/* =========================================================================
   AxCodeEditor.js -- a code editor for Trident (IE11), any number to a page.

   The surface is a contenteditable with one <div> per line. The text lives
   in a model (an array of lines, and the colouring state each line starts
   in); a keystroke re-colours only the line it landed on -- and the lines
   after it only while their starting state changes (an opened block
   comment) -- and puts the caret back inside that one line. Everything that
   looks at the whole text (folding, the outline, the minimap, the undo
   point, telling AutoHotkey) waits for a pause in the typing.

   What must sit under the text (the current line, the matching bracket,
   the same word elsewhere, find hits, problem underlines) is a layer BEHIND
   it, drawn for the lines in view only.

   Suggestions are ranked here, as you type, from what the page already has
   (the language, the text's own words and definitions, and word lists
   AutoHotkey handed over once); a service behind it is asked once per word,
   not once per key, and what it answers joins the same list.

   AutoHotkey talks to it through AXCE:
       AXCE.make(id, optionsJson)      build the editor on the markup
       AXCE.call(id, "method", argsJson)   anything below, by name
       AXCE.recv(id, messageJson)      answers: items, marks, hover
   and it talks back by writing a request into #<id>_q and clicking
   #<id>_req -- one request a turn, so AutoHotkey never edits a page it is
   inside.

   Languages are data (AXCE.langs), so a new one is an object, from here or
   from AutoHotkey. ES5 only: this is Internet Explorer 11.
   ========================================================================= */
(function () {
    if (window.AXCE) { return; }

    function words(s) {
        var o = {}, a = String(s).split(/\s+/), i;
        for (i = 0; i < a.length; i++) { if (a[i]) { o[a[i].toLowerCase()] = a[i]; } }
        return o;
    }
    function esc(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
    function attr(s) { return esc(s).replace(/"/g, "&quot;"); }
    function reEsc(s) { return String(s).replace(/[.*+?^${}()|[\]\\\/]/g, "\\$&"); }
    function $(id) { return document.getElementById(id); }
    function has(el, c) { return !!el && (" " + el.className + " ").indexOf(" " + c + " ") >= 0; }
    function idx(list, node) { return Array.prototype.indexOf.call(list, node); }
    function stop(e) {
        if (e.preventDefault) { e.preventDefault(); }
        e.returnValue = false;
        e.cancelBubble = true;
        return false;
    }
    function lead(s) { return (/^[ \t]*/.exec(s) || [""])[0]; }

    var AXCE = window.AXCE = { inst: {}, langs: {} };

    /* ------------------------------------------------------------ languages */
    /* line: a line comment; lineSpace: it only counts at the start or after a
       space (AutoHotkey's semicolon); block: [open, close]; strings: quote
       characters; escape: the escape character; ci: keywords ignore case;
       kw / bi / types: word lists; more: more words to suggest (as {word:
       detail}); directive: a line-start prefix; fold: "brace" | "indent" |
       "heading" | "section"; pairs: what closes itself; wordRe: what a word is */
    AXCE.langs.ahk = {
        name: "AutoHotkey", line: ";", lineSpace: true, block: ["/*", "*/"], strings: "\"'", escape: "`",
        ci: true, directive: "#", fold: "brace", pairs: "()[]{}\"\"''", indent: "    ",
        kw: words("and as break case catch class continue default else extends false finally for global goto if in is isset local loop not or return static super switch this throw true try unset until while"),
        bi: words("A_AhkPath A_AhkVersion A_AppData A_AppDataCommon A_Args A_Clipboard A_ComputerName A_ComSpec A_Cursor A_DD A_DDD A_DDDD A_DefaultMouseSpeed A_Desktop A_DetectHiddenText A_DetectHiddenWindows A_EndChar A_EventInfo A_FileEncoding A_HotkeyInterval A_Hour A_IconFile A_IconHidden A_IconNumber A_IconTip A_Index A_InitialWorkingDir A_Is64bitOS A_IsAdmin A_IsCompiled A_IsCritical A_IsPaused A_IsSuspended A_KeyDelay A_Language A_LastError A_LineFile A_LineNumber A_LoopField A_LoopFileName A_LoopFilePath A_LoopFileFullPath A_LoopFileDir A_LoopFileExt A_LoopFileSize A_LoopFileSizeKB A_LoopFileTimeModified A_LoopReadLine A_LoopRegName A_MDay A_MM A_MMM A_MMMM A_Min A_MSec A_MyDocuments A_Now A_NowUTC A_OSVersion A_PriorHotkey A_PriorKey A_ProgramFiles A_Programs A_PtrSize A_ScreenDPI A_ScreenHeight A_ScreenWidth A_ScriptDir A_ScriptFullPath A_ScriptHwnd A_ScriptName A_Sec A_Space A_StartMenu A_Startup A_Tab A_Temp A_ThisFunc A_ThisHotkey A_TickCount A_TimeIdle A_TimeIdlePhysical A_TimeSincePriorHotkey A_TimeSinceThisHotkey A_TitleMatchMode A_TrayMenu A_UserName A_WDay A_WinDir A_WorkingDir A_YDay A_Year A_YWeek A_YYYY"),
        types: words("Array Buffer ClipboardAll Class Closure ComObjArray ComObject ComValue Enumerator Error File Float Func Gui Integer Map Menu MenuBar MethodError Number Object OSError Primitive PropertyError RegExMatchInfo String TargetError TimeoutError TypeError ValueError VarRef ZeroDivisionError"),
        snippets: [
            { label: "if", body: "if ($0) {\n    \n}" },
            { label: "else", body: "else {\n    $0\n}" },
            { label: "for", body: "for k, v in $0 {\n    \n}" },
            { label: "loop", body: "loop $0 {\n    \n}" },
            { label: "while", body: "while ($0) {\n    \n}" },
            { label: "try", body: "try {\n    $0\n} catch as e {\n    \n}" },
            { label: "switch", body: "switch $0 {\ncase 1:\n    \ndefault:\n    \n}" },
            { label: "class", body: "class $0 {\n    __New() {\n    }\n}" },
            { label: "func", body: "$0() {\n    \n}" },
            { label: "hotkey", body: "^j:: {\n    $0\n}" },
            { label: "gui", body: "g := Gui(, \"$0\")\ng.AddText(, \"Hello\")\ng.Show()" }]
    };
    AXCE.langs.js = {
        name: "JavaScript", line: "//", block: ["/*", "*/"], strings: "\"'`", escape: "\\", fold: "brace",
        pairs: "()[]{}\"\"''``", indent: "    ",
        kw: words("async await break case catch class const continue debugger default delete do else export extends false finally for function if import in instanceof let new null of return static super switch this throw true try typeof undefined var void while with yield"),
        bi: words("Array Boolean Date Error JSON Math Number Object Promise RegExp String Symbol console document window parseInt parseFloat isNaN setTimeout setInterval clearTimeout clearInterval"),
        members: {
            console: "log warn error info table", Math: "abs ceil floor round max min pow random sqrt PI",
            JSON: "parse stringify", document: "getElementById querySelector querySelectorAll createElement body title",
            Object: "keys values entries assign create freeze", Array: "isArray from of",
            "*": "length push pop shift unshift slice splice indexOf join map filter forEach reduce concat sort reverse replace split substring toLowerCase toUpperCase trim"
        },
        snippets: [
            { label: "function", body: "function $0() {\n    \n}" },
            { label: "for", body: "for (var i = 0; i < $0; i++) {\n    \n}" },
            { label: "forof", body: "for (const item of $0) {\n    \n}" },
            { label: "if", body: "if ($0) {\n    \n}" },
            { label: "log", body: "console.log($0);" }]
    };
    AXCE.langs.json = { name: "JSON", strings: "\"", escape: "\\", fold: "brace", pairs: "[]{}\"\"", indent: "  ",
                        kw: words("true false null"), props: true };
    AXCE.langs.css = { name: "CSS", block: ["/*", "*/"], strings: "\"'", escape: "\\", fold: "brace", css: true,
        pairs: "()[]{}\"\"''", indent: "    ", kw: words("!important inherit initial none auto"), wordRe: "[A-Za-z_\\-][\\w\\-]*",
        more: words("align-items background background-color border border-radius bottom box-shadow box-sizing color cursor display flex flex-direction font font-family font-size font-weight gap grid height justify-content left line-height margin max-height max-width min-height min-width opacity outline overflow padding position right text-align text-decoration top transform transition visibility white-space width z-index"),
        snippets: [{ label: "rule", body: ".$0 {\n    \n}" }, { label: "media", body: "@media (max-width: $0px) {\n    \n}" }] };
    AXCE.langs.html = { name: "HTML", block: ["<!--", "-->"], html: true, fold: "indent", pairs: "\"\"''", indent: "  ",
        more: words("html head body title meta link script style div span p a img ul ol li table thead tbody tr th td h1 h2 h3 button input label select option textarea form section header footer nav main class id href src alt style type value"),
        snippets: [{ label: "page", body: "<!doctype html>\n<html>\n<head>\n  <meta charset=\"utf-8\">\n  <title>$0</title>\n</head>\n<body>\n  \n</body>\n</html>" },
                   { label: "div", body: "<div class=\"$0\">\n  \n</div>" }, { label: "a", body: "<a href=\"$0\"></a>" }] };
    AXCE.langs.xml = AXCE.langs.html;
    AXCE.langs.ini = { name: "INI", line: ";", ini: true, fold: "section", indent: "" };
    AXCE.langs.md = { name: "Markdown", md: true, fold: "heading", indent: "  ", wrap: true,
        snippets: [{ label: "table", body: "| $0 | |\n| --- | --- |\n|  |  |" }, { label: "code", body: "```\n$0\n```" },
                   { label: "link", body: "[$0](https://)" }] };
    AXCE.langs.ps1 = {
        name: "PowerShell", line: "#", block: ["<#", "#>"], strings: "\"'", escape: "`", ci: true, fold: "brace",
        dollar: true, pairs: "()[]{}\"\"''", indent: "    ", wordRe: "[A-Za-z_$][\\w\\-]*",
        kw: words("begin break catch class continue data do dynamicparam else elseif end exit filter finally for foreach function if in param process return switch throw trap try until using while -eq -ne -gt -lt -ge -le -like -notlike -match -notmatch -and -or -not"),
        more: words("Get-ChildItem Get-Content Set-Content Add-Content Get-Item Remove-Item Copy-Item Move-Item New-Item Test-Path Join-Path Split-Path Get-Process Stop-Process Start-Process Get-Service Write-Host Write-Output Write-Error Select-Object Where-Object ForEach-Object Sort-Object Measure-Object Out-File Invoke-WebRequest ConvertTo-Json ConvertFrom-Json"),
        snippets: [{ label: "function", body: "function $0 {\n    param()\n    \n}" }, { label: "foreach", body: "foreach ($item in $0) {\n    \n}" }]
    };
    AXCE.langs.py = {
        name: "Python", line: "#", strings: "\"'", escape: "\\", fold: "indent", pairs: "()[]{}\"\"''", indent: "    ",
        kw: words("and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield"),
        bi: words("print len range str int float list dict set tuple open enumerate zip map filter sorted isinstance super self"),
        snippets: [{ label: "def", body: "def $0():\n    " }, { label: "class", body: "class $0:\n    def __init__(self):\n        " },
                   { label: "for", body: "for item in $0:\n    " }, { label: "main", body: "if __name__ == \"__main__\":\n    $0" }]
    };
    AXCE.langs.sql = { name: "SQL", line: "--", block: ["/*", "*/"], strings: "'\"", ci: true, fold: "indent", indent: "    ",
        kw: words("select from where and or not insert into values update set delete create table drop alter index join left right inner outer on group by order having limit as distinct null is in like between union all case when then else end primary key"),
        bi: words("count sum avg min max coalesce ifnull upper lower length substr round now date"),
        snippets: [{ label: "sel", body: "SELECT $0\nFROM \nWHERE " }] };
    AXCE.langs.plain = { name: "Plain text", plain: true, fold: "indent", indent: "    " };

    /* ------------------------------------------------------------- colouring */
    function hlCode(line, st, L) {
        var out = "", i = 0, n = line.length, c, j, w, lw, cls, q;
        if (st.block) {
            j = line.indexOf(L.block[1]);
            if (j < 0) { return '<i class="c">' + esc(line) + "</i>"; }
            st.block = false;
            out += '<i class="c">' + esc(line.substring(0, j + L.block[1].length)) + "</i>";
            i = j + L.block[1].length;
        }
        if (L.directive && L.directive === "#" && /^\s*#/.test(line)) {
            j = line.indexOf("#");
            var m = /^#[A-Za-z]+/.exec(line.substring(j));
            if (m && j >= i) {
                out += esc(line.substring(i, j)) + '<i class="d">' + esc(m[0]) + "</i>";
                i = j + m[0].length;
            }
        }
        while (i < n) {
            c = line.charAt(i);
            if (L.line && line.substr(i, L.line.length) === L.line
                && (!L.lineSpace || i === 0 || /\s/.test(line.charAt(i - 1)))) {
                return out + '<i class="c">' + esc(line.substring(i)) + "</i>";
            }
            if (L.block && line.substr(i, L.block[0].length) === L.block[0]) {
                j = line.indexOf(L.block[1], i + L.block[0].length);
                if (j < 0) { st.block = true; return out + '<i class="c">' + esc(line.substring(i)) + "</i>"; }
                out += '<i class="c">' + esc(line.substring(i, j + L.block[1].length)) + "</i>";
                i = j + L.block[1].length;
                continue;
            }
            if (L.strings && L.strings.indexOf(c) >= 0) {
                q = c; j = i + 1;
                while (j < n) {
                    if (L.escape && line.charAt(j) === L.escape) { j += 2; continue; }
                    if (line.charAt(j) === q) { j++; break; }
                    j++;
                }
                if (j > n) { j = n; }
                cls = "s";
                if (L.props && /^\s*:/.test(line.substring(j))) { cls = "p"; }
                out += '<i class="' + cls + '">' + esc(line.substring(i, j)) + "</i>";
                i = j;
                continue;
            }
            if (L.dollar && c === "$") {
                j = i + 1;
                while (j < n && /[A-Za-z0-9_:]/.test(line.charAt(j))) { j++; }
                out += '<i class="v">' + esc(line.substring(i, j)) + "</i>";
                i = j;
                continue;
            }
            if (L.css && c === "#" && /[0-9A-Fa-f]/.test(line.charAt(i + 1))) {
                j = i + 1;
                while (j < n && /[0-9A-Fa-f]/.test(line.charAt(j))) { j++; }
                out += '<i class="n">' + esc(line.substring(i, j)) + "</i>";
                i = j;
                continue;
            }
            if (L.css && c === "@") {
                j = i + 1;
                while (j < n && /[A-Za-z-]/.test(line.charAt(j))) { j++; }
                out += '<i class="d">' + esc(line.substring(i, j)) + "</i>";
                i = j;
                continue;
            }
            if (/[0-9]/.test(c) && !/[A-Za-z_$]/.test(line.charAt(i - 1) || " ")) {
                j = i;
                while (j < n && /[0-9A-Fa-fxX._]/.test(line.charAt(j))) { j++; }
                if (L.css) { while (j < n && /[a-z%]/.test(line.charAt(j))) { j++; } }
                out += '<i class="n">' + esc(line.substring(i, j)) + "</i>";
                i = j;
                continue;
            }
            if (/[A-Za-z_]/.test(c) || (L.css && c === "-" && /[A-Za-z]/.test(line.charAt(i + 1)))) {
                j = i + 1;
                while (j < n && /[A-Za-z0-9_\-]/.test(line.charAt(j))) {
                    if (line.charAt(j) === "-" && !L.css && !L.dollar) { break; }
                    j++;
                }
                w = line.substring(i, j);
                lw = w.toLowerCase();
                if (L.css) {
                    cls = /^\s*:/.test(line.substring(j)) && !/\{/.test(line.substring(j)) ? "p" : "";
                } else if (L.kw && L.kw.hasOwnProperty(lw) && (L.ci || L.kw[lw] === w)) {
                    cls = "k";
                } else if (L.types && L.types.hasOwnProperty(lw)) {
                    cls = "t";
                } else if (L.bi && L.bi.hasOwnProperty(lw)) {
                    cls = "v";
                } else if (line.charAt(i - 1) === ".") {
                    cls = line.charAt(j) === "(" ? "f" : "p";
                } else if (line.charAt(j) === "(") {
                    cls = "f";
                } else {
                    cls = "";
                }
                out += cls ? '<i class="' + cls + '">' + esc(w) + "</i>" : esc(w);
                i = j;
                continue;
            }
            if ("+-*/%:=<>!&|.?,^~".indexOf(c) >= 0) {
                out += '<i class="o">' + esc(c) + "</i>";
                i++;
                continue;
            }
            if ("()[]{}".indexOf(c) >= 0) {
                out += '<i class="b">' + esc(c) + "</i>";
                i++;
                continue;
            }
            out += esc(c);
            i++;
        }
        return out;
    }
    function hlHtml(line, st) {
        var out = "", i = 0, n = line.length, j, m;
        if (st.block) {
            j = line.indexOf("-->");
            if (j < 0) { return '<i class="c">' + esc(line) + "</i>"; }
            st.block = false;
            out += '<i class="c">' + esc(line.substring(0, j + 3)) + "</i>";
            i = j + 3;
        }
        while (i < n) {
            if (line.substr(i, 4) === "<!--") {
                j = line.indexOf("-->", i + 4);
                if (j < 0) { st.block = true; return out + '<i class="c">' + esc(line.substring(i)) + "</i>"; }
                out += '<i class="c">' + esc(line.substring(i, j + 3)) + "</i>";
                i = j + 3;
                continue;
            }
            if (line.charAt(i) === "<") {
                m = /^<\/?[A-Za-z][\w:\-]*/.exec(line.substring(i));
                if (m) {
                    out += '<i class="t">' + esc(m[0]) + "</i>";
                    i += m[0].length;
                    while (i < n && line.charAt(i) !== ">") {
                        var rest = line.substring(i);
                        if ((m = /^\s+/.exec(rest))) { out += m[0]; i += m[0].length; continue; }
                        if ((m = /^[\w:\-]+/.exec(rest))) { out += '<i class="a">' + esc(m[0]) + "</i>"; i += m[0].length; continue; }
                        if ((m = /^"[^"]*"?|^'[^']*'?/.exec(rest))) { out += '<i class="s">' + esc(m[0]) + "</i>"; i += m[0].length; continue; }
                        out += esc(line.charAt(i)); i++;
                    }
                    if (i < n) { out += '<i class="t">&gt;</i>'; i++; }
                    continue;
                }
            }
            if (line.charAt(i) === "&" && (m = /^&[#\w]+;/.exec(line.substring(i)))) {
                out += '<i class="n">' + esc(m[0]) + "</i>";
                i += m[0].length;
                continue;
            }
            out += esc(line.charAt(i));
            i++;
        }
        return out;
    }
    function hlIni(line) {
        var m;
        if (/^\s*[;#]/.test(line)) { return '<i class="c">' + esc(line) + "</i>"; }
        if ((m = /^(\s*)(\[[^\]]*\])(.*)$/.exec(line))) { return esc(m[1]) + '<i class="k">' + esc(m[2]) + "</i>" + esc(m[3]); }
        if ((m = /^(\s*)([^=]+?)(\s*=)(.*)$/.exec(line))) {
            return esc(m[1]) + '<i class="p">' + esc(m[2]) + '</i><i class="o">' + esc(m[3]) + "</i>" + '<i class="s">' + esc(m[4]) + "</i>";
        }
        return esc(line);
    }
    function hlMd(line, st) {
        var m;
        if (/^\s*```/.test(line)) { st.fence = !st.fence; return '<i class="d">' + esc(line) + "</i>"; }
        if (st.fence) { return '<i class="s">' + esc(line) + "</i>"; }
        if ((m = /^(#{1,6}\s.*)$/.exec(line))) { return '<i class="h">' + esc(m[1]) + "</i>"; }
        if (/^\s*>/.test(line)) { return '<i class="c">' + esc(line) + "</i>"; }
        var s = esc(line);
        s = s.replace(/^(\s*)([-*+]|\d+\.)(\s)/, '$1<i class="k">$2</i>$3');
        s = s.replace(/`([^`]+)`/g, '<i class="s">`$1`</i>');
        s = s.replace(/\*\*([^*]+)\*\*/g, '<i class="bo">**$1**</i>');
        s = s.replace(/(^|[^*])\*([^*]+)\*/g, '$1<i class="it">*$2*</i>');
        s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<i class="a">[$1]</i><i class="l">($2)</i>');
        return s;
    }
    function hl(line, st, L) {
        if (L.plain) { return esc(line); }
        if (L.html) { return hlHtml(line, st); }
        if (L.ini) { return hlIni(line); }
        if (L.md) { return hlMd(line, st); }
        return hlCode(line, st, L);
    }
    function stKey(st) { return (st.block ? "b" : "") + (st.fence ? "f" : ""); }
    function stOf(k) { k = k || ""; return { block: k.indexOf("b") >= 0, fence: k.indexOf("f") >= 0 }; }

    /* ----------------------------------------------------------- folding */
    /* [{a: first line, b: last line}] -- zero-based, a < b */
    function foldRanges(lines, L) {
        var out = [], i, j, k, ind, next;
        var indentOf = function (s) { return lead(s).replace(/\t/g, "    ").length; };
        if (L.fold === "brace") {
            var stack = [];
            for (i = 0; i < lines.length; i++) {
                var s = lines[i];
                if (s.indexOf("{") < 0 && s.indexOf("}") < 0 && s.indexOf("[") < 0 && s.indexOf("]") < 0) { continue; }
                s = s.replace(/"(?:[^"`\\]|[`\\].)*"|'(?:[^'`\\]|[`\\].)*'/g, "");
                if (L.line) {
                    k = s.indexOf(L.line);
                    if (k >= 0 && (!L.lineSpace || k === 0 || /\s/.test(s.charAt(k - 1)))) { s = s.substring(0, k); }
                }
                for (j = 0; j < s.length; j++) {
                    var c = s.charAt(j);
                    if (c === "{" || c === "[") { stack.push(i); }
                    else if ((c === "}" || c === "]") && stack.length) {
                        var a = stack.pop();
                        if (i > a) { out.push({ a: a, b: i }); }
                    }
                }
            }
        } else if (L.fold === "heading") {
            var heads = [];
            for (i = 0; i < lines.length; i++) {
                var m = /^(#{1,6})\s/.exec(lines[i]);
                if (m) { heads.push({ i: i, lv: m[1].length }); }
            }
            for (j = 0; j < heads.length; j++) {
                var end = lines.length - 1;
                for (k = j + 1; k < heads.length; k++) { if (heads[k].lv <= heads[j].lv) { end = heads[k].i - 1; break; } }
                while (end > heads[j].i && !/\S/.test(lines[end])) { end--; }
                if (end > heads[j].i) { out.push({ a: heads[j].i, b: end }); }
            }
        } else if (L.fold === "section") {
            var last = -1;
            for (i = 0; i <= lines.length; i++) {
                if (i === lines.length || /^\s*\[/.test(lines[i])) {
                    if (last >= 0) {
                        var e2 = i - 1;
                        while (e2 > last && !/\S/.test(lines[e2])) { e2--; }
                        if (e2 > last) { out.push({ a: last, b: e2 }); }
                    }
                    last = i;
                }
            }
        } else {
            for (i = 0; i < lines.length; i++) {
                if (!/\S/.test(lines[i])) { continue; }
                ind = indentOf(lines[i]);
                next = i + 1;
                while (next < lines.length && !/\S/.test(lines[next])) { next++; }
                if (next >= lines.length || indentOf(lines[next]) <= ind) { continue; }
                j = next;
                var lastIn = next;
                while (j < lines.length && (!/\S/.test(lines[j]) || indentOf(lines[j]) > ind)) {
                    if (/\S/.test(lines[j])) { lastIn = j; }
                    j++;
                }
                out.push({ a: i, b: lastIn });
            }
        }
        out.sort(function (x, y) { return x.a - y.a; });
        return out;
    }

    /* The lines of a piece of the page, however Trident left it: one <div>
       per line as we draw it, or text it typed straight into the box, or a
       <div> it split inside another, or a <br> in the middle of a line. */
    function flatten(root) {
        var out = [], cur = null;
        var push = function () { out.push(cur === null ? "" : cur); cur = null; };
        var block = function (t) { return t === "DIV" || t === "P" || t === "LI" || t === "PRE" || t === "H1" || t === "H2" || t === "H3" || t === "BLOCKQUOTE"; };
        var walk = function (el) {
            var k = el.childNodes, j, c;
            for (j = 0; j < k.length; j++) {
                c = k[j];
                if (c.nodeType === 3) { cur = (cur || "") + c.nodeValue; }
                else if (c.nodeType === 1) {
                    if (c.tagName === "BR") {
                        if (j === k.length - 1) { if (cur === null) { cur = ""; } }
                        else { push(); cur = ""; }
                    } else if (block(c.tagName)) {
                        if (cur !== null) { push(); }
                        cur = "";
                        walk(c);
                        if (cur !== null) { push(); }
                    } else { walk(c); }
                }
            }
        };
        var top = root.childNodes, i, c2;
        for (i = 0; i < top.length; i++) {
            c2 = top[i];
            if (c2.nodeType === 1 && block(c2.tagName)) {
                if (cur !== null) { push(); }
                cur = "";
                walk(c2);
                if (cur !== null) { push(); }
            } else if (c2.nodeType === 3) {
                cur = (cur || "") + c2.nodeValue;
            } else if (c2.nodeType === 1) {
                if (c2.tagName === "BR") { push(); cur = ""; }
                else { cur = cur || ""; walk(c2); }
            }
        }
        if (cur !== null) { push(); }
        if (!out.length) { out.push(""); }
        for (i = 0; i < out.length; i++) { out[i] = out[i].replace(/\u00a0/g, " ").replace(/[\r\n]/g, ""); }
        return out;
    }

    /* How well a label fits what was typed: those that start with it first,
       then those whose words' first letters spell it (fr -> FileRead), then
       those that only have its letters in order. {s: score, m: [where]} */
    function fuzzy(lk, label, q, qRaw) {
        var i, m = [];
        if (!q) { return { s: 1, m: m }; }
        if (lk.indexOf(q) === 0) {
            for (i = 0; i < q.length; i++) { m.push(i); }
            return { s: 1000 - lk.length + (label.substring(0, q.length) === qRaw ? 40 : 0), m: m };
        }
        var j = 0, s = 0, prev = -2, first = -1;
        for (i = 0; i < lk.length && j < q.length; i++) {
            if (lk.charAt(i) !== q.charAt(j)) { continue; }
            var ch = label.charAt(i), pv = i ? label.charAt(i - 1) : "";
            var bound = i === 0 || pv === "_" || pv === "-" || pv === "." || pv === " "
                || (ch !== ch.toLowerCase() && pv === pv.toLowerCase());
            if (j === 0) { first = i; if (!bound) { break; } }
            s += bound ? 30 : (prev === i - 1 ? 14 : 1);
            m.push(i); prev = i; j++;
        }
        if (j < q.length) {
            var at = lk.indexOf(q);
            if (at < 0 || q.length < 3) { return null; }
            m = [];
            for (i = 0; i < q.length; i++) { m.push(at + i); }
            return { s: 300 - lk.length, m: m };
        }
        return { s: 500 + s - lk.length - first, m: m };
    }

    var KIND = { kw: "k", fn: "f", method: "m", "var": "v", "class": "c", prop: "p", snippet: "s", word: "w", file: "d", heading: "h", section: "h" };

    /* ============================================================ an editor */
    function Ed(id, o) {
        this.id = id;
        this.o = o || {};
        this.root = $(id);
        this.ed = $(id + "_ed");
        this.gut = $(id + "_gut");
        this.scroll = $(id + "_scroll");
        this.under = $(id + "_under");
        this.acEl = $(id + "_ac");
        this.tipEl = $(id + "_tip");
        this.findEl = $(id + "_find");
        this.statEl = $(id + "_stat");
        this.val = $(id + "_val");
        this.req = $(id + "_req");            /* clicked to ask AutoHotkey */
        this.qdata = $(id + "_q");            /* and what is asked, as JSON */
        this.L = AXCE.langs[this.o.lang] || AXCE.langs.plain;
        this.lines = [""];                    /* the text */
        this.divs = [];                       /* its line <div>s, in order */
        this.sts = [""];                      /* the colouring state each line starts in */
        this.txt = null;                      /* the lines joined, until they change */
        this.folds = {};                      /* first line of a folded range -> true */
        this.ranges = []; this.starts = {};
        this.marks = [];
        this.undoS = []; this.redoS = []; this.last = null;
        this.sets = {};                       /* word lists from AutoHotkey, by name */
        this.snips = [];
        this.sigs = {};                       /* name -> "Name(params)" for the signature card */
        this.ac = { open: false, items: [], i: 0 };
        this.sess = null;                     /* the word being suggested for */
        this.qn = 0; this.queue = []; this.qTimer = null;
        this.sTimer = null; this.cTimer = null; this.hTimer = null; this.dTimer = null; this.kTimer = null; this.pTimer = null;
        this.hits = []; this.hitAt = -1;
        this.fo = { cs: false, ww: false, re: false };
        this.lastC = { line: 0, col: 0, aLine: 0, aCol: 0 };
        this.focused = false;
        this.dirty = false;
        this.index = null;                    /* the text's words and definitions, until it changes */
        this.plain = false;
        this.LIMIT = 250000;
        this.lastCh = "";
        this.build();
        if (!this.o.design) { this.wire(); }
        this.apply();
        if (this.o.design) { this.ed.contentEditable = "false"; }
        this.load(this.val ? this.val.value : "");
        this.whenShown();
    }
    var P = Ed.prototype;

    /* Made on a page that is not showing, it measures as nothing: the map,
       the guides and the gutter's heights wait until it has a size. */
    P.whenShown = function () {
        var self = this;
        if (this.root.offsetWidth && this.cw) { return; }
        if (this.shownTimer) { return; }
        this.shownTimer = window.setInterval(function () {
            if (!self.root.offsetWidth) { return; }
            self.shownNow();
        }, 300);
    };
    /* Shown: everything that waited for a size, now. Called in the same turn
       as the page or tab that shows it (window.axShown, from ShowPage), so
       the first frame already has its colours and its gutter -- not a frame
       of plain text and a gutter that jumps a moment later. */
    P.shownNow = function () {
        if (this.shownTimer) { window.clearInterval(this.shownTimer); this.shownTimer = null; }
        this.guides();
        this.paintNear();
        this.fitGutter();
        this.decorate();
        this.drawMini();
        this.shownW = this.root.offsetWidth; this.shownH = this.root.offsetHeight;
    };
    /* ------------------------------------------------------- the extra parts */
    P.build = function () {
        var d;
        if (!this.o.design) {
            d = this.miniBox = document.createElement("div");
            d.className = "axce-minibox";
            d.innerHTML = '<canvas class="axce-mini"></canvas><div class="axce-mview"></div>';
            this.scroll.parentNode.appendChild(d);
            this.mini = d.firstChild; this.mview = d.lastChild;
        }
        d = this.sigEl = document.createElement("div");
        d.className = "axce-sig";
        this.root.appendChild(d);
        if (this.findEl) {
            var I = this.id;
            this.findEl.innerHTML =
                '<div class="axce-frow"><span data-f="rep" class="axce-ftog" title="Replace too (Ctrl+H)">&#x203A;</span>'
                + '<input id="' + I + '_fq" placeholder="Find   (:line  @symbol)" spellcheck="false">'
                + '<span data-f="cs" title="Match case (Alt+C)">Aa</span><span data-f="ww" title="Whole word (Alt+W)"><u>ab</u></span>'
                + '<span data-f="re" title="Regular expression (Alt+R)">.*</span>'
                + '<span class="axce-fn" id="' + I + '_fn"></span>'
                + '<span data-f="prev" title="Previous (Shift+Enter)">&#x2191;</span><span data-f="next" title="Next (Enter)">&#x2193;</span>'
                + '<span data-f="x" title="Close (Esc)">&#x2715;</span></div>'
                + '<div class="axce-frep"><input id="' + I + '_fr" placeholder="Replace with   ($1 is a group)" spellcheck="false">'
                + '<span data-f="one" title="Replace this one (Enter)">Replace</span><span data-f="all" title="Replace them all (Ctrl+Alt+Enter)">All</span></div>'
                + '<div class="axce-flist" id="' + I + '_fl"></div>';
            this.fq = $(I + "_fq"); this.fr = $(I + "_fr"); this.fn = $(I + "_fn"); this.fl = $(I + "_fl");
        }
    };

    /* ------------------------------------------------------------ options */
    P.apply = function () {
        var o = this.o, r = this.root;
        r.className = (r.className.replace(/\baxce-t-\S+/g, "") + " axce-t-" + (o.theme || "auto")).replace(/\s+/g, " ");
        this.toggle("axce-wrap", o.wrap != null ? !!o.wrap : !!this.L.wrap);
        this.toggle("axce-nogut", o.gutter === false);
        this.toggle("axce-nostat", o.status === false);
        this.toggle("axce-ro", !!o.readonly);
        this.toggle("axce-hasmini", !!o.minimap && !o.design);
        var fs = o.fontSize || 13, lh = Math.round(fs * 1.5);
        this.ed.style.fontSize = fs + "px";
        this.ed.style.lineHeight = lh + "px";
        this.gut.style.fontSize = Math.max(10, fs - 1) + "px";
        this.gut.style.lineHeight = lh + "px";
        this.ed.style.fontFamily = o.font || "";
        this.lh = lh;
        this.ed.contentEditable = (o.readonly || o.design) ? "false" : "true";
        this.ed.setAttribute("data-ph", o.placeholder || "");
        this.colors = null;
        this.guides();
    };
    /* how wide a character is in this font: the indent guides are drawn in
       the layer under the text, one indent apart */
    P.guides = function () {
        try {
            var probe = document.createElement("span");
            probe.style.cssText = "position:absolute;visibility:hidden;white-space:pre";
            probe.appendChild(document.createTextNode("0000000000"));
            this.ed.appendChild(probe);
            var cw = probe.offsetWidth / 10;
            this.ed.removeChild(probe);
            if (cw) { this.cw = cw; }
        } catch (e) { }
    };
    P.toggle = function (c, on) {
        var r = this.root, has1 = has(r, c);
        if (on && !has1) { r.className += " " + c; }
        if (!on && has1) { r.className = (" " + r.className + " ").replace(" " + c + " ", " ").replace(/^\s+|\s+$/g, ""); }
    };
    P.wrapped = function () { return has(this.root, "axce-wrap"); };
    P.setOption = function (k, v) {
        var c = this.selNow();
        this.o[k] = flag(k, v);
        if (k === "lang") {
            this.L = AXCE.langs[v] || AXCE.langs.plain;
            this.folds = {};
            this.index = null;
            this.closeAc();
        }
        this.apply();
        if (k === "lang") { this.renderAll(); this.placeSel(c); }
        this.refold();
        this.fitGutter();
        this.decorate();
        this.status();
        this.drawMini();
    };

    /* -------------------------------------------------------------- wiring */
    /* The text box's own listeners. A whole new text is drawn into a fresh
       box that then takes the old one's place (see renderAll), so these go
       onto each box in turn; the old box's fall silent. */
    P.wireEd = function (ed) {
        var self = this;
        var on = function (type, fn) { ed.addEventListener(type, function (e) { if (ed === self.ed) { return fn(e); } }, false); };
        on("keydown", function (e) { self.onKeyDown(e); });
        on("keypress", function (e) { self.onKeyPress(e); });
        on("keyup", function (e) { self.onKeyUp(e); });
        on("paste", function (e) { self.onPaste(e); });
        on("cut", function () { window.setTimeout(function () { self.sync(true); }, 0); });
        on("drop", function () { window.setTimeout(function () { self.sync(true); }, 0); });
        on("mousedown", function () { self.closeAc(); self.hideTip(); });
        on("mouseup", function () { window.setTimeout(function () { self.caretMoved(); }, 0); });
        on("focus", function () { self.focused = true; });
        on("blur", function () {
            self.sync();
            self.focused = false;
            /* leaving it: what was typed is told at once, not after the pause --
               the next thing clicked may well read it */
            self.settle();
            self.sendChange();
            window.setTimeout(function () { if (!self.focused) { self.closeAc(); self.hideSig(); } }, 150);
        });
        on("mousemove", function (e) { self.onMouseMove(e); });
        on("mouseleave", function () { if (self.hTimer) { window.clearTimeout(self.hTimer); } self.hideTip(); });
        on("mousewheel", function (e) {
            if (!e.ctrlKey) { return; }
            self.zoom(e.wheelDelta > 0 ? 1 : -1);
            return stop(e);
        });
        on("mscontrolselect", function (e) { return stop(e); });
        on("controlselect", function (e) { return stop(e); });
    };
    P.wire = function () {
        var self = this;
        this.wireEd(this.ed);
        /* the window resized: the map and what is under the text, redrawn to fit */
        window.addEventListener("resize", function () {
            if (self.rzTimer) { window.clearTimeout(self.rzTimer); }
            self.rzTimer = window.setTimeout(function () { self.rzTimer = null; self.paintNear(); self.fitGutter(); self.decorate(); self.drawMini(); }, 150);
        }, false);
        this.scroll.addEventListener("scroll", function () {
            self.gut.scrollTop = self.scroll.scrollTop;
            if (self.ac.open) { self.placeAc(); }
            if (self.sigOn) { self.hideSig(); }
            self.hideTip();
            self.drawMiniView();
            if (!self.dTimer) { self.dTimer = window.setTimeout(function () { self.dTimer = null; self.paintNear(); self.decorate(); }, 30); }
        }, false);
        this.gut.addEventListener("mousedown", function (e) { self.onGutter(e); return stop(e); }, false);
        this.acEl.addEventListener("mousedown", function (e) {
            var t = e.target || e.srcElement;
            while (t && t !== self.acEl && !(t.getAttribute && t.getAttribute("data-i"))) { t = t.parentNode; }
            if (t && t !== self.acEl) { self.ac.i = parseInt(t.getAttribute("data-i"), 10); self.accept(); }
            return stop(e);
        }, false);
        if (this.statEl) {
            this.statEl.addEventListener("mousedown", function (e) {
                var t = e.target || e.srcElement;
                while (t && t !== self.statEl && !(t.getAttribute && t.getAttribute("data-s"))) { t = t.parentNode; }
                if (!t || t === self.statEl) { return; }
                var a = t.getAttribute("data-s");
                if (a === "next") { self.problem(1); }
                else if (a === "wrap") { self.setOption("wrap", !self.wrapped()); }
                else if (a === "map") { self.setOption("minimap", !self.o.minimap); }
                return stop(e);
            }, false);
        }
        if (this.miniBox) { this.wireMini(); }
        if (this.findEl) { this.wireFind(); }
    };
    P.onGutter = function (e) {
        var t = e.target || e.srcElement;
        while (t && t !== this.gut && !(t.getAttribute && t.getAttribute("data-ln"))) { t = t.parentNode; }
        if (!t || t === this.gut) { return; }
        var ln = parseInt(t.getAttribute("data-ln"), 10);
        this.sync();
        if (this.starts[ln] && (has(e.target || e.srcElement, "axce-fm") || e.offsetX > t.offsetWidth - 16)) { return this.toggleFold(ln); }
        /* a click on a number picks its line */
        var end = ln + 1 < this.lines.length ? { line: ln + 1, col: 0 } : { line: ln, col: this.lines[ln].length };
        this.focus();
        this.setSel(ln, 0, end.line, end.col);
        this.caretMoved();
    };

    /* ---------------------------------------------------------------- text */
    P.value = function () {
        if (this.txt === null) { this.txt = this.lines.join("\n"); }
        return this.txt;
    };
    P.load = function (text) {
        text = String(text == null ? "" : text).replace(/\r\n/g, "\n").replace(/\r/g, "\n");
        this.lines = text.split("\n");
        this.txt = text;
        this.folds = {};
        this.sess = null;
        this.closeAc();
        this.plain = text.length > this.LIMIT;
        this.scroll.scrollTop = 0;
        this.renderAll();
        this.lastC = { line: 0, col: 0, aLine: 0, aCol: 0 };
        this.undoS = []; this.redoS = [];
        this.last = { t: text, c: this.lastC };
        this.sent = text;
        if (this.val) { this.val.value = text; }
        this.scroll.scrollTop = 0;
        this.scroll.scrollLeft = 0;
        this.index = null;
        this.refold();
        this.fitGutter();
        this.decorate();
        this.status();
        this.drawMini();
    };
    P.lineHtml = function (s, st) {
        if (this.plain) { return esc(s); }
        return hl(s, st, this.L);
    };
    P.hiddenSet = function () {
        var hid = {}, f, i;
        for (f in this.folds) {
            if (this.folds.hasOwnProperty(f) && this.starts[f]) {
                for (i = this.starts[f].a + 1; i <= this.starts[f].b; i++) { hid[i] = true; }
            }
        }
        return hid;
    };
    P.lineCls = function (i, hid) { return hid[i] ? "axce-hid" : (this.folds[i] ? "axce-folded" : ""); };
    /* Only the lines near the view are coloured; the rest are plain text
       until they are scrolled to (paintNear). Trident lays out a coloured
       line -- ten elements -- many times slower than a plain one, and three
       thousand of them took it seconds. The colouring state of every line
       is still worked out, so a line is right the moment it is painted. */
    P.LAZY = 300;
    P.near = function () {
        var n = this.lines.length;
        if (n <= this.LAZY) { return { a: 0, b: n }; }
        var v = this.visible();
        return { a: Math.max(0, v.a - 40), b: Math.min(n, v.b + 40) };
    };
    P.renderAll = function () {
        var L = this.lines, n = L.length, out = new Array(n), st = {}, i, hid = this.hiddenSet(), cls, v = this.near(), raw = [], h;
        this.sts = new Array(n);
        for (i = 0; i < n; i++) {
            this.sts[i] = stKey(st);
            cls = this.lineCls(i, hid);
            h = this.lineHtml(L[i], st);
            if (i < v.a || i >= v.b) { h = esc(L[i]); raw.push(i); }
            out[i] = (cls ? '<div class="' + cls + '">' : "<div>") + (h || "<br>") + "</div>";
        }
        /* Into a fresh box, which then takes the old one's place: Trident
           tracks every change inside the box being edited, and filling (or
           emptying) that one with thousands of lines took seconds where a new
           box takes a tenth of it. */
        var old = this.ed, fresh = old.cloneNode(false), had = this.focused;
        fresh.innerHTML = out.join("");
        this.ed = fresh;
        old.parentNode.replaceChild(fresh, old);
        if (!this.o.design) { this.wireEd(fresh); }
        if (had) { try { fresh.focus(); } catch (e) { } this.focused = true; }
        this.walk();
        for (i = 0; i < raw.length; i++) { this.divs[raw[i]].axr = true; }
        this.gutSig = "";
        this.drawGutter();
    };
    /* the plain lines that have come near the view, coloured now */
    P.paintNear = function () {
        if (this.plain || this.lines.length <= this.LAZY) { return; }
        var v = this.near(), kids = this.divs, L = this.lines, i, d, c = this.focused ? this.selNow() : null, lo = -1, hi = -1;
        for (i = v.a; i < v.b; i++) {
            d = kids[i];
            if (d && d.axr) {
                d.innerHTML = this.lineHtml(L[i], stOf(this.sts[i])) || "<br>";
                d.axr = false;
                if (lo < 0) { lo = i; }
                hi = i;
            }
        }
        /* a caret on a line just painted is put back where it was */
        if (c && lo >= 0 && Math.max(c.line, c.aLine) >= lo && Math.min(c.line, c.aLine) <= hi) { this.placeSel(c); }
    };
    /* The line <div>s, in an array of our own: Trident's childNodes[i] walks
       the list from the start each time, so every loop over it -- and every
       indexOf -- was quadratic in the number of lines. */
    P.walk = function () {
        var out = [], k = this.ed.firstChild;
        for (; k; k = k.nextSibling) { out.push(k); }
        this.divs = out;
        return out;
    };
    P.gutDivs = function () {
        var out = [], k = this.gut.firstChild;
        for (; k; k = k.nextSibling) { out.push(k); }
        return out;
    };
    /* lines a.. coloured again, and on past b while the state they start in changes */
    P.rehl = function (a, b) {
        var kids = this.divs, L = this.lines, st = stOf(this.sts[a]), i, k, wrap = this.wrapped(), v = this.near(), h, d;
        for (i = a; i < L.length; i++) {
            k = stKey(st);
            if (i >= b && this.sts[i] === k) { break; }
            this.sts[i] = k;
            h = this.lineHtml(L[i], st);
            d = kids[i];
            if (!d) { continue; }
            if (i >= v.a && i < v.b) { d.innerHTML = h || "<br>"; d.axr = false; }
            else if (i < b || !d.axr) { d.innerHTML = esc(L[i]) || "<br>"; d.axr = true; }
            if (wrap) { this.fitLine(i); }
        }
    };
    /* lines a..b-1 become nl: the model, the page and the gutter follow */
    P.splice = function (a, b, nl) {
        var L = this.lines, ed = this.ed, kids = this.divs, d, i, frag, ref, s0 = this.sts[a] || "", made = [], div;
        if (!nl.length && a === 0 && b >= L.length) { nl = [""]; }
        d = nl.length - (b - a);
        Array.prototype.splice.apply(L, [a, b - a].concat(nl));
        Array.prototype.splice.apply(this.sts, [a, b - a].concat(new Array(nl.length)));
        this.sts[a] = s0;
        ref = kids[b] || null;
        for (i = Math.min(b, kids.length) - 1; i >= a; i--) { if (kids[i].parentNode === ed) { ed.removeChild(kids[i]); } }
        frag = document.createDocumentFragment();
        for (i = 0; i < nl.length; i++) { div = document.createElement("div"); made.push(div); frag.appendChild(div); }
        ed.insertBefore(frag, ref && ref.parentNode === ed ? ref : null);
        Array.prototype.splice.apply(kids, [a, b - a].concat(made));
        this.rehl(a, a + nl.length);
        this.txt = null;
        this.dirty = true;
        this.shift(a, b, d);
        if (d) { if (this.anyFolds()) { this.drawGutter(); } else { this.gutCount(); } }
    };
    /* marks and folds after a change move with their lines */
    P.shift = function (a, b, d) {
        var i, mk, nf = {}, f, n;
        if (!d) { return; }
        for (i = 0; i < this.marks.length; i++) {
            mk = this.marks[i];
            if (mk.line - 1 >= b) { mk.line += d; }
        }
        for (f in this.folds) {
            if (!this.folds.hasOwnProperty(f)) { continue; }
            n = parseInt(f, 10);
            if (n < a) { nf[n] = true; }
            else if (n >= b) { nf[n + d] = true; }
        }
        this.folds = nf;
        /* the ranges too, until the pause works them out again */
        var ns = {}, r;
        for (f in this.starts) {
            if (!this.starts.hasOwnProperty(f)) { continue; }
            n = parseInt(f, 10); r = this.starts[f];
            if (n < a && r.b < a) { ns[n] = r; }
            else if (n >= b) { ns[n + d] = { a: r.a + d, b: r.b + d }; }
        }
        this.starts = ns;
    };
    P.anyFolds = function () { for (var f in this.folds) { if (this.folds.hasOwnProperty(f)) { return true; } } return false; };
    /* the whole text becomes t: only the lines that differ are touched */
    P.setAll = function (t) {
        var nl = String(t).replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n"), L = this.lines, m = L.length, n = nl.length, a = 0, b = 0;
        while (a < m && a < n && L[a] === nl[a]) { a++; }
        if (a === m && a === n) { return false; }
        while (b < m - a && b < n - a && L[m - 1 - b] === nl[n - 1 - b]) { b++; }
        this.splice(a, m - b, nl.slice(a, n - b));
        return true;
    };

    /* ----------------------------------------------- the page -> the model */
    P.clean = function (div) {
        if (div.nodeType !== 1 || div.tagName !== "DIV") { return false; }
        if (div.getElementsByTagName("div").length || div.getElementsByTagName("p").length) { return false; }
        var br = div.getElementsByTagName("br");
        return !br.length || (br.length === 1 && br[0] === div.lastChild);
    };
    /* after Trident has put a key in: the line it went into, and only that */
    P.sync = function (full) {
        var L = this.lines, c;
        /* nobody can type in it without the keyboard: the page is still ours */
        if (!full && !this.focused) { return false; }
        if (!full && this.ed.childNodes.length === L.length) {
            c = this.domSel();
            if (c && c.line === c.aLine) {
                var div = this.divs[c.line];
                if (div && div.parentNode === this.ed && this.clean(div)) {
                    var t = (div.textContent || "").replace(/\u00a0/g, " ");
                    if (t === L[c.line]) { return false; }
                    L[c.line] = t;
                    this.txt = null;
                    this.dirty = true;
                    this.rehl(c.line, c.line + 1);
                    this.placeSel(c);
                    this.after(true);
                    return true;
                }
            }
        }
        return this.syncSlow();
    };
    P.syncSlow = function () {
        var kids = this.walk(), clean = true, i, texts, c = this.selAny();
        for (i = 0; i < kids.length && clean; i++) { clean = this.clean(kids[i]); }
        if (clean) {
            texts = new Array(kids.length);
            for (i = 0; i < kids.length; i++) { texts[i] = (kids[i].textContent || "").replace(/\u00a0/g, " "); }
            if (!texts.length) { clean = false; texts = [""]; }
        } else {
            texts = flatten(this.ed);
        }
        var L = this.lines, m = L.length, n = texts.length, a = 0, b = 0;
        while (a < m && a < n && L[a] === texts[a]) { a++; }
        if (a === m && a === n) {
            if (!clean) { this.renderAll(); this.placeSel(c); }
            return false;
        }
        while (b < m - a && b < n - a && L[m - 1 - b] === texts[n - 1 - b]) { b++; }
        var nl = texts.slice(a, n - b), d = n - m;
        if (clean) {
            var s0 = this.sts[a] || "";
            Array.prototype.splice.apply(L, [a, m - b - a].concat(nl));
            Array.prototype.splice.apply(this.sts, [a, m - b - a].concat(new Array(nl.length)));
            this.sts[a] = s0;
            this.rehl(a, n - b);
            this.shift(a, m - b, d);
            if (d) { this.drawGutter(); }
        } else {
            Array.prototype.splice.apply(L, [a, m - b - a].concat(nl));
            this.shift(a, m - b, d);
            this.renderAll();
        }
        this.txt = null;
        this.dirty = true;
        this.placeSel(c);
        this.after(true);
        return true;
    };

    /* --------------------------------------------------------------- caret */
    /* (line, col) of a DOM place, from the line <div> it is in */
    P.lcOf = function (node, off) {
        var ed = this.ed, top = node, kids = this.divs, i;
        if (node === ed) {
            if (off >= kids.length) { i = kids.length - 1; return { line: Math.max(0, i), col: i >= 0 ? (kids[i].textContent || "").length : 0 }; }
            return { line: off, col: 0 };
        }
        while (top && top.parentNode !== ed) { top = top.parentNode; }
        if (!top) { return null; }
        i = kids.indexOf(top);
        if (i < 0) { return null; }
        return { line: i, col: this.offsetIn(top, node, off) };
    };
    P.offsetIn = function (line, node, off) {
        var n = 0, done = false, j;
        if (node === line) {
            for (j = 0; j < off && j < line.childNodes.length; j++) { n += (line.childNodes[j].textContent || "").length; }
            return n;
        }
        var walk = function (el) {
            var k = el.childNodes, i, c;
            for (i = 0; i < k.length && !done; i++) {
                c = k[i];
                if (c === node) {
                    if (c.nodeType === 3) { n += off; }
                    else { for (j = 0; j < off && j < c.childNodes.length; j++) { n += (c.childNodes[j].textContent || "").length; } }
                    done = true;
                    return;
                }
                if (c.nodeType === 3) { n += c.nodeValue.length; }
                else if (c.nodeType === 1) { walk(c); }
            }
        };
        walk(line);
        return n;
    };
    /* the selection as it is on the page, or null when it is elsewhere */
    P.domSel = function () {
        var sel, r, a, f;
        try { sel = window.getSelection(); } catch (e) { return null; }
        if (!sel || !sel.rangeCount) { return null; }
        r = sel.getRangeAt(0);
        if (!this.contains(r.startContainer) || !this.contains(r.endContainer)) { return null; }
        var back = sel.anchorNode === r.endContainer && sel.anchorOffset === r.endOffset && !r.collapsed;
        a = this.lcOf(r.startContainer, r.startOffset);
        f = r.collapsed ? a : this.lcOf(r.endContainer, r.endOffset);
        if (!a || !f) { return null; }
        return back ? { line: a.line, col: a.col, aLine: f.line, aCol: f.col } : { line: f.line, col: f.col, aLine: a.line, aCol: a.col };
    };
    /* the same, however untidy the page is: by the text in front of it */
    P.selAny = function () {
        try {
            var sel = window.getSelection(), r, box, t, u;
            if (!sel.rangeCount) { return this.lastC; }
            r = sel.getRangeAt(0);
            if (!this.contains(r.startContainer)) { return this.lastC; }
            var at = function (node, off, ed) {
                var x = document.createRange();
                x.setStart(ed, 0); x.setEnd(node, off);
                box = document.createElement("div");
                box.appendChild(x.cloneContents());
                t = flatten(box);
                return { line: t.length - 1, col: t[t.length - 1].length };
            };
            u = at(r.endContainer, r.endOffset, this.ed);
            var s = r.collapsed ? u : at(r.startContainer, r.startOffset, this.ed);
            return { line: u.line, col: u.col, aLine: s.line, aCol: s.col };
        } catch (e) { return this.lastC; }
    };
    P.contains = function (b) { var a = this.ed; while (b) { if (b === a) { return true; } b = b.parentNode; } return false; };
    /* where the selection is now: the page's when it has one, else the last known */
    P.selNow = function () {
        if (this.focused) { var c = this.domSel(); if (c) { this.lastC = c; } }
        return this.lastC;
    };
    P.ord = function (c) {
        c = c || this.lastC;
        if (c.aLine < c.line || (c.aLine === c.line && c.aCol <= c.col)) { return { sl: c.aLine, sc: c.aCol, el: c.line, ec: c.col }; }
        return { sl: c.line, sc: c.col, el: c.aLine, ec: c.aCol };
    };
    P.collapsed = function (c) { c = c || this.lastC; return c.line === c.aLine && c.col === c.aCol; };
    P.offAt = function (line, col) {
        var t = 0, i, L = this.lines;
        line = Math.max(0, Math.min(line, L.length - 1));
        for (i = 0; i < line; i++) { t += L[i].length + 1; }
        return t + Math.min(col, L[line].length);
    };
    P.lcAt = function (off) {
        var i, L = this.lines;
        off = Math.max(0, off);
        for (i = 0; i < L.length; i++) {
            if (off <= L[i].length) { return { line: i, col: off }; }
            off -= L[i].length + 1;
        }
        return { line: L.length - 1, col: L[L.length - 1].length };
    };
    /* the DOM place of (line, col) */
    P.nodeAt = function (line, col) {
        var kids = this.divs, div = kids[Math.max(0, Math.min(line, kids.length - 1))], seen = 0, found = null;
        if (!div) { return { node: this.ed, off: 0 }; }
        var walk = function (el) {
            var j, k = el.childNodes;
            for (j = 0; j < k.length && !found; j++) {
                if (k[j].nodeType === 3) {
                    var l = k[j].nodeValue.length;
                    if (seen + l >= col) { found = { node: k[j], off: col - seen }; return; }
                    seen += l;
                } else if (k[j].nodeType === 1) { walk(k[j]); }
            }
        };
        walk(div);
        if (!found) {
            var last = div.lastChild;
            if (last && last.nodeType === 1 && last.tagName === "BR") { return { node: div, off: idx(div.childNodes, last) }; }
            return { node: div, off: div.childNodes.length };
        }
        return found;
    };
    /* the page's selection -- only while the editor has the keyboard: a
       caret put anywhere else would take it from wherever the user is */
    P.setSel = function (aLine, aCol, line, col) {
        var L = this.lines;
        aLine = Math.max(0, Math.min(aLine, L.length - 1)); line = Math.max(0, Math.min(line, L.length - 1));
        aCol = Math.max(0, Math.min(aCol, L[aLine].length)); col = Math.max(0, Math.min(col, L[line].length));
        this.lastC = { line: line, col: col, aLine: aLine, aCol: aCol };
        if (!this.focused) { return; }
        try {
            var o = this.ord(), p = this.nodeAt(o.sl, o.sc), q = this.nodeAt(o.el, o.ec), r = document.createRange();
            r.setStart(p.node, p.off);
            r.setEnd(q.node, q.off);
            var sel = window.getSelection();
            sel.removeAllRanges();
            sel.addRange(r);
        } catch (e) { }
    };
    P.placeSel = function (c) { if (c) { this.setSel(c.aLine, c.aCol, c.line, c.col); } };
    P.setCaretOff = function (at, selTo) {
        var p = this.lcAt(at), q = selTo == null ? p : this.lcAt(selTo);
        if (selTo == null) { this.setSel(p.line, p.col, p.line, p.col); } else { this.setSel(p.line, p.col, q.line, q.col); }
    };
    P.focus = function () {
        if (this.focused) { return; }
        try { this.ed.focus(); } catch (e) { }
        this.focused = true;
        this.placeSel(this.lastC);
    };
    P.goLine = function (line, col) {
        var ln = Math.max(1, Math.min(line, this.lines.length)) - 1;
        this.unfoldAt(ln);
        this.focus();
        this.setSel(ln, (col || 1) - 1, ln, (col || 1) - 1);
        this.reveal(ln, true);
        this.caretMoved();
    };
    /* the line in view; centred when it was far off */
    P.reveal = function (ln, centre) {
        var div = this.divs[ln], s = this.scroll;
        if (!div) { return; }
        var top = div.offsetTop, h = div.offsetHeight || this.lh;
        if (top < s.scrollTop + 4 || top + h > s.scrollTop + s.clientHeight - 4) {
            s.scrollTop = centre ? Math.max(0, top - s.clientHeight / 3) : (top < s.scrollTop ? top - 6 : top + h - s.clientHeight + this.lh);
            this.paintNear();
        }
        try {
            var p = this.nodeAt(ln, this.lastC.col), r = document.createRange();
            r.setStart(p.node, p.off); r.collapse(true);
            var b = r.getBoundingClientRect(), sb = s.getBoundingClientRect();
            if (b && (b.left || b.right)) {
                if (b.left < sb.left + 30) { s.scrollLeft = Math.max(0, s.scrollLeft - (sb.left + 60 - b.left)); }
                else if (b.left > sb.right - 30) { s.scrollLeft += b.left - sb.right + 60; }
            }
        } catch (e) { }
    };
    P.revealCaret = function () { this.reveal(this.lastC.line, false); };

    /* ---------------------------------------------------------------- input */
    P.onKeyUp = function (e) {
        var k = e.keyCode;
        if ((k >= 33 && k <= 40) || k === 36 || k === 35) { this.sync(); this.caretMoved(); if (this.ac.open && (k === 37 || k === 39)) { this.closeAc(); } return; }
        if (k === 16 || k === 17 || k === 18 || k === 27) { return; }
        this.kick();
    };
    /* the next turn, when Trident has put the key in */
    P.kick = function () {
        var self = this;
        if (this.kTimer) { return; }
        this.kTimer = window.setTimeout(function () {
            self.kTimer = null;
            var ch = self.lastCh;
            self.lastCh = "";
            if (!self.sync()) { return; }
            if (ch) {
                if (/[\w$#@]/.test(ch) || ch === "." || (ch === "-" && self.L.css)) { self.suggest(false); }
                else if (self.ac.open) { self.closeAc(); }
                if (ch === "(" || ch === ",") { self.sigUpdate(true); return; }
            } else if (self.ac.open) {
                self.suggest(false);
            }
            self.sigUpdate();
        }, 0);
    };
    P.onKeyPress = function (e) {
        if (this.o.readonly || this.o.design) { return; }
        if (e.ctrlKey && !e.altKey) { return; }
        var code = e.charCode || e.keyCode;
        /* Enter and Tab were answered on the way down: their character must
           not put in a line or a tab of Trident's own as well */
        if (code === 13 || code === 9) { return stop(e); }
        if (!code || code < 32) { return; }
        var ch = String.fromCharCode(code);
        this.lastCh = ch;
        if (this.typeChar(ch)) { this.lastCh = ""; this.kickAfterEdit(ch); return stop(e); }
        this.kick();
    };
    /* after one of ours took the key: suggestions and the card as if typed */
    P.kickAfterEdit = function (ch) {
        if (ch === "(" || ch === ",") { this.sigUpdate(true); }
        else if (ch === ")") { this.sigUpdate(); }
        if (this.ac.open && !/[\w$]/.test(ch)) { this.closeAc(); }
    };
    P.onKeyDown = function (e) {
        var k = e.keyCode, c = e.ctrlKey || e.metaKey, sh = e.shiftKey, alt = e.altKey;
        if (this.kTimer) { window.clearTimeout(this.kTimer); this.kTimer = null; }
        this.sync();
        if (this.ac.open) {
            if (k === 40) { this.moveAc(1); return stop(e); }
            if (k === 38) { this.moveAc(-1); return stop(e); }
            if (k === 34) { this.moveAc(8); return stop(e); }
            if (k === 33) { this.moveAc(-8); return stop(e); }
            if (k === 13 || k === 9) { this.accept(); return stop(e); }
            if (k === 27) { this.closeAc(); return stop(e); }
        }
        if (k === 27) { this.hideSig(); this.hideTip(); if (has(this.root, "axce-finding")) { this.closeFind(); } return; }
        if (c && !sh && !alt && k === 70) { this.openFind(false); return stop(e); }
        if (c && !alt && k === 72) { this.openFind(true); return stop(e); }
        if (c && !sh && k === 71) { this.openFind(false, ":"); return stop(e); }
        if (c && sh && k === 79) { this.openFind(false, "@"); return stop(e); }
        if (k === 114) { this.findStep(sh ? -1 : 1, true); return stop(e); }
        if (k === 119) { this.problem(sh ? -1 : 1); return stop(e); }
        if (c && k === 83) { this.post({ kind: "save" }); return stop(e); }
        if (c && !sh && (k === 187 || k === 107)) { this.zoom(1); return stop(e); }
        if (c && !sh && (k === 189 || k === 109)) { this.zoom(-1); return stop(e); }
        if (c && !sh && (k === 48 || k === 96)) { this.zoom(0); return stop(e); }
        if (alt && !c && k === 90) { this.setOption("wrap", !this.wrapped()); return stop(e); }
        if (c && sh && k === 220) { this.toBracket(); return stop(e); }
        if (c && !sh && k === 67 && this.collapsed()) { this.copyLine(false); return stop(e); }
        if (c && !sh && k === 76) { this.selectLine(); return stop(e); }
        if (this.o.readonly) {
            if (!c && !(k >= 33 && k <= 40) && k !== 9) { return stop(e); }
            return;
        }
        if (c && !sh && k === 88) { this.cut(); return stop(e); }
        if (c && !sh && k === 90) { this.undo(); return stop(e); }
        if (c && (k === 89 || (sh && k === 90))) { this.redo(); return stop(e); }
        if (c && k === 32) { if (sh) { this.sigUpdate(true, true); } else { this.suggest(true); } return stop(e); }
        if (c && k === 191) { this.comment(); return stop(e); }
        if (c && !sh && !alt && k === 68) { this.duplicate(1); return stop(e); }
        if (alt && sh && (k === 38 || k === 40)) { this.duplicate(k === 40 ? 1 : -1); return stop(e); }
        if (alt && !sh && !c && (k === 38 || k === 40)) { this.moveLine(k === 38 ? -1 : 1); return stop(e); }
        if (c && sh && k === 75) { this.deleteLine(); return stop(e); }
        if (c && k === 13) { this.openLine(sh ? -1 : 1); return stop(e); }
        if (c && sh && (k === 219 || k === 221)) {
            if (this.dirty) { this.refold(); }
            var rr = this.rangeFor(this.lastC.line);
            if (rr) { if (k === 219) { this.folds[rr.a] = true; } else { delete this.folds[rr.a]; } this.foldsChanged(); }
            return stop(e);
        }
        if (c && alt && (k === 219 || k === 221)) { this.foldAll(k === 219); return stop(e); }
        if (c && !sh && (k === 219 || k === 221)) { this.indent(k === 219, true); return stop(e); }
        if (k === 9) { this.indent(sh); return stop(e); }
        if (k === 13) { this.newline(); return stop(e); }
        if ((k === 8 || k === 46) && !alt && this.erase(k === 8, c)) { return stop(e); }
        if (k === 36 && !c && !sh) { this.smartHome(); return stop(e); }
    };
    /* settle what was typed before a command acts on the text */
    P.flush = function () {
        if (this.kTimer) { window.clearTimeout(this.kTimer); this.kTimer = null; }
        this.sync();
        this.selNow();
        this.remember();
    };
    /* one command: text a..b becomes s, the caret where it is asked */
    P.edit = function (a, b, s, caretAt, selTo) {
        this.flush();
        var A = this.lcAt(a), B = this.lcAt(b), L = this.lines;
        var txt = L[A.line].substring(0, A.col) + s + L[B.line].substring(B.col);
        this.splice(A.line, B.line + 1, txt.split("\n"));
        this.setCaretOff(caretAt == null ? a + s.length : caretAt, selTo);
        this.remember();
        this.revealCaret();
        this.after(true);
    };
    P.selOffs = function () {
        var o = this.ord();
        return { a: this.offAt(o.sl, o.sc), b: this.offAt(o.el, o.ec), o: o };
    };
    P.insert = function (s) {
        this.flush();
        var r = this.selOffs();
        this.edit(r.a, r.b, s);
    };
    P.newline = function () {
        this.flush();
        var r = this.selOffs(), o = r.o, L = this.lines, line = L[o.sl], before = line.substring(0, o.sc), after = L[o.el].substring(o.ec);
        var ind = lead(line), unit = this.L.indent || "    ", m;
        if (ind.length > o.sc) { ind = ind.substring(0, o.sc); }
        /* Markdown: a list goes on, and an empty item ends it */
        if (this.L.md && (m = /^(\s*)([-*+]|\d+[.)])(\s+)(\[[ xX]\]\s+)?/.exec(before))) {
            if (!/\S/.test(before.substring(m[0].length)) && !/\S/.test(after)) {
                return this.edit(this.offAt(o.sl, 0), r.b, "", this.offAt(o.sl, 0));
            }
            var mk = /\d/.test(m[2]) ? (parseInt(m[2], 10) + 1) + m[2].replace(/\d+/, "") : m[2];
            return this.edit(r.a, r.b, "\n" + m[1] + mk + m[3] + (m[4] ? "[ ] " : ""));
        }
        var opens = /[\{\[\(]\s*$/.test(before) || (this.L.fold === "indent" && !this.L.plain && !this.L.html && /:\s*$/.test(before));
        var closing = /^\s*[\}\]\)]/.test(after);
        after = after.replace(/^[ \t]+/, "");
        var tail = L[o.el].length - o.ec - after.length;
        if (opens) {
            var inner = ind + unit;
            if (closing) { return this.edit(r.a, r.b + tail, "\n" + inner + "\n" + ind, r.a + 1 + inner.length); }
            return this.edit(r.a, r.b + tail, "\n" + inner);
        }
        this.edit(r.a, r.b + tail, "\n" + ind);
    };
    P.openLine = function (d) {
        this.flush();
        var o = this.ord(), L = this.lines, ln = d > 0 ? o.el : o.sl, ind = lead(L[ln]);
        if (d > 0 && /[\{\[\(]\s*$/.test(L[ln])) { ind += this.L.indent || "    "; }
        if (d > 0) { var e = this.offAt(ln, L[ln].length); this.edit(e, e, "\n" + ind); }
        else { var s = this.offAt(ln, 0); this.edit(s, s, ind + "\n", s + ind.length); }
    };
    P.smartHome = function () {
        var c = this.lastC, s = this.lines[c.line], first = lead(s).length;
        var to = (c.col === first) ? 0 : first;
        this.setSel(c.line, to, c.line, to);
        this.caretMoved();
    };
    /* Backspace and Delete: a pair at once, an indent at once, a line join
       done here rather than by Trident (it joins <div>s its own way) */
    P.erase = function (back, word) {
        var r = this.selOffs(), o = r.o, L = this.lines, s = L[o.sl], c = o.sc, unit = this.L.indent || "    ";
        if (r.a !== r.b) {
            if (o.sl === o.el) { return false; }
            this.edit(r.a, r.b, "");
            return true;
        }
        if (word) {
            var t = this.value(), p = r.a;
            if (back) { while (p > 0 && /\s/.test(t.charAt(p - 1)) && t.charAt(p - 1) !== "\n") { p--; } while (p > 0 && /[\w$]/.test(t.charAt(p - 1))) { p--; } if (p === r.a && p > 0) { p--; } this.edit(p, r.a, ""); }
            else { while (p < t.length && /\s/.test(t.charAt(p)) && t.charAt(p) !== "\n") { p++; } while (p < t.length && /[\w$]/.test(t.charAt(p))) { p++; } if (p === r.a && p < t.length) { p++; } this.edit(r.a, p, ""); }
            return true;
        }
        if (back) {
            if (c === 0) { if (o.sl === 0) { return true; } this.edit(r.a - 1, r.a, ""); return true; }
            var pairs = this.L.pairs || "", pv = s.charAt(c - 1), nx = s.charAt(c), i;
            for (i = 0; i < pairs.length; i += 2) {
                if (pairs.charAt(i) === pv && pairs.charAt(i + 1) === nx) { this.edit(r.a - 1, r.a + 1, ""); return true; }
            }
            var before = s.substring(0, c);
            if (unit && /^ +$/.test(before) && before.length >= 2) {
                var cut = before.length % unit.length || unit.length;
                this.edit(r.a - cut, r.a, "");
                return true;
            }
            return false;
        }
        if (c >= s.length) { if (o.sl >= L.length - 1) { return true; } this.edit(r.a, r.a + 1, ""); return true; }
        return false;
    };
    P.indent = function (back, whole) {
        this.flush();
        var r = this.selOffs(), o = r.o, L = this.lines, unit = this.L.indent || "    ", i, lines = [], first = 0, lastD = 0;
        if (!whole && r.a === r.b && !back) {
            var col = o.sc, pad = unit === "    " || /^ +$/.test(unit) ? unit.length - (col % unit.length) : 0;
            return this.edit(r.a, r.b, pad ? new Array(pad + 1).join(" ") : unit);
        }
        var el = o.el;
        if (el > o.sl && o.ec === 0) { el--; }
        for (i = o.sl; i <= el; i++) {
            var s = L[i], d;
            if (back) {
                var cut = s.indexOf(unit) === 0 ? unit.length : (s.charAt(0) === "\t" ? 1 : lead(s).length);
                cut = Math.min(cut, unit.length);
                d = -cut;
                s = s.substring(cut);
            } else {
                d = /\S/.test(s) || o.sl === el ? unit.length : 0;
                if (d) { s = unit + s; }
            }
            if (i === o.sl) { first = d; }
            if (i === o.el) { lastD = d; }
            lines.push(s);
        }
        var a = this.offAt(o.sl, 0), b = this.offAt(el, L[el].length);
        var c0 = this.lastC, selA = { line: c0.aLine, col: Math.max(0, c0.aCol + (c0.aLine === o.sl ? first : lastD)) };
        var selB = { line: c0.line, col: Math.max(0, c0.col + (c0.line === o.sl ? first : lastD)) };
        this.edit(a, b, lines.join("\n"));
        this.setSel(selA.line, selA.col, selB.line, selB.col);
    };
    P.comment = function () {
        this.flush();
        var o = this.ord(), L = this.lines, Lg = this.L, el = o.el, i, all = true, tok, lines = [];
        if (el > o.sl && o.ec === 0) { el--; }
        for (i = o.sl; i <= el; i++) { lines.push(L[i]); }
        var a = this.offAt(o.sl, 0), b = this.offAt(el, L[el].length), block = lines.join("\n"), out;
        if (!Lg.line && Lg.block) {
            var op = Lg.block[0], cl = Lg.block[1], t = block.replace(/^\s+|\s+$/g, "");
            out = (t.indexOf(op) === 0 && t.lastIndexOf(cl) === t.length - cl.length)
                ? block.replace(op + " ", "").replace(op, "").replace(" " + cl, "").replace(cl, "")
                : lead(block) + op + " " + block.replace(/^\s+/, "") + " " + cl;
            return this.edit(a, b, out, a, a + out.length);
        }
        tok = Lg.line || "#";
        var minInd = 1e9;
        for (i = 0; i < lines.length; i++) {
            if (!/\S/.test(lines[i])) { continue; }
            if (lines[i].replace(/^\s+/, "").indexOf(tok) !== 0) { all = false; }
            minInd = Math.min(minInd, lead(lines[i]).length);
        }
        var re = new RegExp("^(\\s*)" + reEsc(tok) + " ?");
        for (i = 0; i < lines.length; i++) {
            if (!/\S/.test(lines[i])) { continue; }
            lines[i] = all ? lines[i].replace(re, "$1") : lines[i].substring(0, minInd) + tok + " " + lines[i].substring(minInd);
        }
        out = lines.join("\n");
        if (this.collapsed()) {
            var col = Math.max(0, this.lastC.col + (out.length - block.length));
            this.edit(a, b, out);
            this.setSel(o.sl, col, o.sl, col);
        } else {
            this.edit(a, b, out, a, a + out.length);
        }
    };
    P.duplicate = function (d) {
        this.flush();
        var o = this.ord(), L = this.lines, el = o.el, i, lines = [];
        if (el > o.sl && o.ec === 0) { el--; }
        for (i = o.sl; i <= el; i++) { lines.push(L[i]); }
        var block = lines.join("\n"), end = this.offAt(el, L[el].length), c = this.lastC, n = el - o.sl + 1;
        this.edit(end, end, "\n" + block);
        if (d > 0) { this.setSel(c.aLine + n, c.aCol, c.line + n, c.col); } else { this.setSel(c.aLine, c.aCol, c.line, c.col); }
        this.revealCaret();
    };
    P.moveLine = function (d) {
        this.flush();
        var o = this.ord(), L = this.lines, first = o.sl, last = o.el, c = this.lastC;
        if (last > first && o.ec === 0) { last--; }
        if ((d < 0 && first === 0) || (d > 0 && last >= L.length - 1)) { return; }
        var nl = L.slice(first, last + 1), a, b;
        if (d < 0) { nl.push(L[first - 1]); a = first - 1; b = last + 1; }
        else { nl.unshift(L[last + 1]); a = first; b = last + 2; }
        this.splice(a, b, nl);
        this.setSel(c.aLine + d, c.aCol, c.line + d, c.col);
        this.remember();
        this.revealCaret();
        this.after(true);
    };
    P.deleteLine = function () {
        this.flush();
        var o = this.ord(), L = this.lines, el = o.el, c = this.lastC;
        if (el > o.sl && o.ec === 0) { el--; }
        var a, b;
        if (el < L.length - 1) { a = this.offAt(o.sl, 0); b = this.offAt(el + 1, 0); }
        else if (o.sl > 0) { a = this.offAt(o.sl - 1, L[o.sl - 1].length); b = this.offAt(el, L[el].length); }
        else { a = 0; b = this.offAt(el, L[el].length); }
        this.edit(a, b, "");
        var ln = Math.min(o.sl, this.lines.length - 1);
        this.setSel(ln, Math.min(c.col, this.lines[ln].length), ln, Math.min(c.col, this.lines[ln].length));
    };
    /* Ctrl+L: the line, and the next one each time again */
    P.selectLine = function () {
        var o = this.ord(), L = this.lines, to = o.el + 1;
        if (to < L.length) { this.setSel(o.sl, 0, to, 0); } else { this.setSel(o.sl, 0, L.length - 1, L[L.length - 1].length); }
        this.caretMoved();
    };
    /* Ctrl+C with nothing picked copies the line; Ctrl+X cuts it */
    P.copyLine = function (cut) {
        var c = this.lastC, L = this.lines, ln = c.line, keep = { line: c.line, col: c.col, aLine: c.aLine, aCol: c.aCol };
        if (ln + 1 < L.length) { this.setSel(ln, 0, ln + 1, 0); } else { this.setSel(ln, 0, ln, L[ln].length); }
        try { document.execCommand("copy", false, null); } catch (e) { }
        if (cut) {
            var a = this.offAt(ln, 0), b = ln + 1 < L.length ? this.offAt(ln + 1, 0) : this.offAt(ln, L[ln].length);
            if (ln + 1 >= L.length && ln > 0) { a = this.offAt(ln - 1, L[ln - 1].length); }
            this.edit(a, b, "");
            var l2 = Math.min(ln, this.lines.length - 1);
            this.setSel(l2, 0, l2, 0);
        } else {
            this.placeSel(keep);
        }
    };
    P.cut = function () {
        this.flush();
        if (this.collapsed()) { return this.copyLine(true); }
        var r = this.selOffs();
        try { document.execCommand("copy", false, null); } catch (e) { }
        this.edit(r.a, r.b, "");
    };
    /* the key's character, when it is one we answer for: pairs, typing over a
       closer, a } that finds its own indent, a picked piece replaced */
    P.typeChar = function (ch) {
        var pairs = this.L.pairs || "", r = this.selOffs(), o = r.o, L = this.lines, s = L[o.sl], i, op, cl;
        for (i = 0; i < pairs.length; i += 2) {
            op = pairs.charAt(i); cl = pairs.charAt(i + 1);
            if (r.a === r.b && ch === cl && s.charAt(o.sc) === cl && (op !== cl || s.charAt(o.sc - 1) !== "\\")) {
                this.setSel(o.sl, o.sc + 1, o.sl, o.sc + 1);
                this.caretMoved(true);
                return true;
            }
            if (ch === op) {
                if (r.a !== r.b) { this.edit(r.a, r.b, op + this.value().substring(r.a, r.b) + cl, r.a + 1, r.b + 1); return true; }
                var nx = s.charAt(o.sc), pv = s.charAt(o.sc - 1);
                if (nx && !/[\s\)\]\},;:]/.test(nx)) { return false; }
                if (op === cl && (/[\w$]/.test(pv) || this.inToken(o.sl, o.sc - 1, "c"))) { return false; }
                if (op === cl && this.inToken(o.sl, o.sc - 1, "s")) { return false; }
                this.edit(r.a, r.b, op + cl, r.a + 1);
                return true;
            }
        }
        if ((ch === "}" || ch === "]") && r.a === r.b && /^\s+$/.test(s.substring(0, o.sc)) && o.sc === s.length) {
            var unit = this.L.indent || "    ", ind = s.substring(0, o.sc);
            var less = ind.substring(0, Math.max(0, ind.length - unit.length));
            this.edit(this.offAt(o.sl, 0), r.a, less + ch);
            return true;
        }
        if (r.a !== r.b && o.sl !== o.el) { this.edit(r.a, r.b, ch); this.lastCh = ch; this.kickSuggest(ch); return true; }
        return false;
    };
    P.kickSuggest = function (ch) { if (/[\w$]/.test(ch)) { var self = this; window.setTimeout(function () { self.suggest(false); }, 0); } };
    /* is the character at (line, i) inside a comment ("c") or a string ("s")? */
    P.inToken = function (line, i, cls) {
        if (i < 0) { return false; }
        try {
            var n = this.nodeAt(line, i + 1).node;
            while (n && n !== this.ed && !(n.tagName === "DIV")) {
                if (n.nodeType === 1 && n.className === cls) { return true; }
                n = n.parentNode;
            }
        } catch (e) { }
        return false;
    };
    P.onPaste = function (e) {
        var t = null;
        try { t = window.clipboardData.getData("Text"); } catch (err) { }
        if (this.o.readonly) { return stop(e); }
        if (t == null) { var self = this; window.setTimeout(function () { self.sync(true); }, 0); return; }
        stop(e);
        this.insert(String(t).replace(/\r\n/g, "\n").replace(/\r/g, "\n"));
    };
    P.zoom = function (d) {
        var fs = this.o.fontSize || 13;
        if (!this.o.baseFont) { this.o.baseFont = fs; }
        this.setOption("fontSize", d === 0 ? this.o.baseFont : Math.max(8, Math.min(32, fs + d)));
    };
    P.toBracket = function () {
        var p = this.matchBracket(this.lastC.line, this.lastC.col);
        if (!p) { return; }
        var c = this.lastC, to = (p[0][0] === c.line && (p[0][1] === c.col || p[0][1] === c.col - 1)) ? p[1] : p[0];
        this.setSel(to[0], to[1], to[0], to[1]);
        this.revealCaret();
        this.caretMoved();
    };

    /* ------------------------------------------------- what happens after */
    /* any change to the text or the caret: what shows at once */
    P.after = function (typing) {
        this.caretMoved(typing);
        if (typing) {
            var self = this;
            if (this.sTimer) { window.clearTimeout(this.sTimer); }
            this.sTimer = window.setTimeout(function () { self.sTimer = null; self.settle(); }, 260);
            if (this.cTimer) { window.clearTimeout(this.cTimer); this.cTimer = null; }
        }
    };
    /* the typing has paused: what looks at the whole text */
    P.settle = function () {
        if (!this.dirty) { return; }
        this.dirty = false;
        var big = this.value().length > this.LIMIT;
        if (big !== this.plain) { var c = this.selNow(); this.plain = big; this.renderAll(); this.placeSel(c); }
        this.index = null;
        this.refold();
        this.fitGutter();
        this.remember();
        if (has(this.root, "axce-finding") && this.fq && this.fq.value && /^[^:@]/.test(this.fq.value)) { this.findRun(true); }
        this.decorate();
        this.drawMini();
        this.changed();
    };
    P.caretMoved = function (typing) {
        var c = this.selNow();
        if (!typing && this.isHidden(c.line)) { this.unfoldAt(c.line); }
        this.decorate();
        this.status();
        this.drawMiniView();
        if (!typing) { this.sigUpdate(); }
        if (this.o.caret) {
            var self = this;
            if (this.pTimer) { window.clearTimeout(this.pTimer); }
            this.pTimer = window.setTimeout(function () {
                self.pTimer = null;
                self.post({ kind: "caret", line: self.lastC.line + 1, col: self.lastC.col + 1 });
            }, 120);
        }
    };
    /* the undo stack: the state before each settled change */
    P.remember = function () {
        var t = this.value(), c = this.lastC;
        if (this.last && this.last.t !== t) {
            this.undoS.push(this.last);
            if (this.undoS.length > 400) { this.undoS.shift(); }
            this.redoS = [];
        }
        this.last = { t: t, c: { line: c.line, col: c.col, aLine: c.aLine, aCol: c.aCol } };
    };
    P.undo = function () {
        this.flush();
        if (!this.undoS.length) { return; }
        var s = this.undoS.pop();
        this.redoS.push(this.last);
        this.restoreState(s);
    };
    P.redo = function () {
        this.flush();
        if (!this.redoS.length) { return; }
        var s = this.redoS.pop();
        this.undoS.push(this.last);
        this.restoreState(s);
    };
    P.restoreState = function (s) {
        this.last = s;
        this.setAll(s.t);
        this.placeSel(s.c);
        this.revealCaret();
        this.dirty = true;
        this.after(true);
    };

    /* -------------------------------------------------------------- gutter */
    P.drawGutter = function () {
        var n = this.lines.length, out = new Array(n), i, hid = this.hiddenSet(), marksAt = {}, mk, ln, cls, sig = [n];
        for (i = 0; i < this.marks.length; i++) {
            mk = this.marks[i]; ln = (mk.line || 1) - 1;
            if (!marksAt[ln] || mk.sev === "error") { marksAt[ln] = mk; }
            sig.push(ln + mk.sev + mk.msg);
        }
        /* drawn again only when what it shows is different */
        sig = sig.join("|") + "#" + Object.keys(this.starts).join(",") + "#" + Object.keys(this.folds).join(",");
        if (sig === this.gutSig && this.gut.childNodes.length === n) { this.gutWidth(); return; }
        this.gutSig = sig;
        for (i = 0; i < n; i++) {
            mk = marksAt[i];
            cls = "axce-ln" + (hid[i] ? " axce-hid" : "") + (mk ? " axce-m-" + (mk.sev || "error") : "");
            out[i] = '<div class="' + cls + '" data-ln="' + i + '"' + (mk ? ' title="' + attr(mk.msg || "") + '"' : "") + ">"
                + (i + 1) + (this.starts[i] ? '<span class="axce-fm' + (this.folds[i] ? " shut" : "") + '"></span>' : "") + "</div>";
        }
        this.gut.innerHTML = out.join("");
        this.gutWidth();
        this.gut.scrollTop = this.scroll.scrollTop;
    };
    /* the numbers' column as wide as the longest number, the text beside it */
    P.gutWidth = function () {
        var digits = String(this.lines.length).length, fs = Math.max(10, (this.o.fontSize || 13) - 1);
        var w = Math.max(42, 26 + Math.ceil(digits * fs * 0.62));
        if (w !== this.gw) { this.gw = w; this.gut.style.width = w + "px"; this.scroll.style.left = w + "px"; }
    };
    /* only the count changed: numbers on or off the end */
    P.gutCount = function () {
        var g = this.gut, n = this.lines.length, have = g.childNodes.length, i, d;
        if (have > n) { for (i = have - 1; i >= n; i--) { g.removeChild(g.lastChild); } }
        else {
            var frag = document.createDocumentFragment();
            for (i = have; i < n; i++) {
                d = document.createElement("div");
                d.className = "axce-ln";
                d.setAttribute("data-ln", String(i));
                d.appendChild(document.createTextNode(String(i + 1)));
                frag.appendChild(d);
            }
            g.appendChild(frag);
        }
        this.gutWidth();
        this.gutSig = "";
        g.scrollTop = this.scroll.scrollTop;
    };
    /* wrapped lines are taller: the numbers follow their line's height */
    P.fitGutter = function () {
        if (!this.wrapped()) {
            if (this.fitted) { var g0 = this.gutDivs(), j; for (j = 0; j < g0.length; j++) { g0[j].style.height = ""; } this.fitted = false; }
            return;
        }
        var k = this.divs, g = this.gutDivs(), i;
        for (i = 0; i < k.length && i < g.length; i++) { g[i].style.height = k[i].offsetHeight ? k[i].offsetHeight + "px" : ""; }
        this.fitted = true;
    };
    P.fitLine = function (i) {
        var k = this.divs[i], g = this.gut.childNodes[i];
        if (k && g) { g.style.height = k.offsetHeight ? k.offsetHeight + "px" : ""; }
    };

    /* ---------------------------------------------------------------- folds */
    P.refold = function () {
        this.ranges = (this.o.fold === false || this.plain) ? [] : foldRanges(this.lines, this.L);
        var starts = {}, i, r, f, changed = false;
        for (i = 0; i < this.ranges.length; i++) {
            r = this.ranges[i];
            if (!starts.hasOwnProperty(r.a) || starts[r.a].b < r.b) { starts[r.a] = r; }
        }
        this.starts = starts;
        for (f in this.folds) { if (this.folds.hasOwnProperty(f) && !starts[f]) { delete this.folds[f]; changed = true; } }
        this.drawGutter();
        if (this.anyFolds() || changed || this.hadFolds) { this.applyFolds(); }
    };
    P.applyFolds = function () {
        var kids = this.divs, hid = this.hiddenSet(), i, cls;
        for (i = 0; i < kids.length; i++) {
            cls = this.lineCls(i, hid);
            if (kids[i].className !== cls) { kids[i].className = cls; }
        }
        this.hadFolds = this.anyFolds();
    };
    P.foldsChanged = function () {
        this.applyFolds();
        this.drawGutter();
        var c = this.lastC;
        if (this.isHidden(c.line)) {
            var r = this.rangeFor(c.line);
            while (r && this.isHidden(r.a)) { r = this.rangeFor(r.a - 1); }
            if (r) { this.setSel(r.a, this.lines[r.a].length, r.a, this.lines[r.a].length); }
        }
        this.fitGutter();
        this.decorate();
        this.drawMini();
    };
    P.rangeFor = function (ln) {
        var best = null, i, r;
        for (i = 0; i < this.ranges.length; i++) {
            r = this.ranges[i];
            if (r.a <= ln && r.b >= ln && (!best || r.a > best.a)) { best = r; }
        }
        return best;
    };
    P.isHidden = function (ln) {
        for (var f in this.folds) {
            if (this.folds.hasOwnProperty(f) && this.starts[f] && ln > this.starts[f].a && ln <= this.starts[f].b) { return true; }
        }
        return false;
    };
    P.unfoldAt = function (ln) {
        var did = false;
        for (var f in this.folds) {
            if (this.folds.hasOwnProperty(f) && this.starts[f] && ln > this.starts[f].a && ln <= this.starts[f].b) { delete this.folds[f]; did = true; }
        }
        if (did) { this.foldsChanged(); }
    };
    P.toggleFold = function (ln) {
        if (this.folds[ln]) { delete this.folds[ln]; } else { this.folds[ln] = true; }
        this.foldsChanged();
    };
    P.foldAll = function (on) {
        this.sync();
        if (this.dirty) { this.refold(); }
        this.folds = {};
        if (on) { for (var i = 0; i < this.ranges.length; i++) { this.folds[this.ranges[i].a] = true; } }
        this.foldsChanged();
    };

    /* ---------------------------------------------------- under the text */
    /* the lines in view, as [a, b) */
    P.visible = function () {
        var n = this.lines.length, s = this.scroll, top = s.scrollTop, h = s.clientHeight || 400, lh = this.lh || 20;
        if (!this.hadFolds && !this.wrapped()) {
            return { a: Math.max(0, Math.floor((top - 6) / lh) - 1), b: Math.min(n, Math.ceil((top + h) / lh) + 1) };
        }
        var kids = this.divs, i, a = -1, b = n, d, y;
        for (i = 0; i < kids.length; i++) {
            d = kids[i];
            if (d.className === "axce-hid") { continue; }
            y = d.offsetTop;
            if (a < 0 && y + d.offsetHeight >= top) { a = i; }
            if (y > top + h) { b = i + 1; break; }
        }
        return { a: Math.max(0, a), b: Math.min(n, b) };
    };
    /* the current line, the matching bracket, the same word, the find hits, problems */
    P.decorate = function () {
        if (!this.under) { return; }
        var html = [], c = this.lastC, L = this.lines, div, i, v = this.visible(), coll = this.collapsed(c), mk;
        div = this.divs[c.line];
        if (div && coll && this.o.currentLine !== false && !this.o.design) {
            html.push('<div class="axce-cur" style="top:' + div.offsetTop + "px;height:" + (div.offsetHeight || this.lh) + 'px"></div>');
        }
        if (this.o.guides !== false && !this.plain && this.cw && !this.L.plain) { this.drawGuides(html, v); }
        if (coll && !this.o.design) {
            var pair = this.matchBracket(c.line, c.col);
            if (pair) {
                this.boxes(html, pair[0][0], pair[0][1], pair[0][0], pair[0][1] + 1, "axce-br");
                this.boxes(html, pair[1][0], pair[1][1], pair[1][0], pair[1][1] + 1, "axce-br");
            }
            var w = this.o.occur === false || this.hits.length ? "" : this.wordUnder(c.line, c.col);
            if (w && w.length > 1 && !/^\d/.test(w)) {
                var re = new RegExp("(^|[^\\w$])(" + reEsc(w) + ")(?![\\w$])", "g"), m, n = 0, list = [];
                for (i = v.a; i < v.b && n < 200; i++) {
                    re.lastIndex = 0;
                    while ((m = re.exec(L[i])) && n < 200) { list.push([i, m.index + m[1].length]); n++; if (!m[0].length) { re.lastIndex++; } }
                }
                if (list.length > 1) {
                    for (i = 0; i < list.length; i++) { this.boxes(html, list[i][0], list[i][1], list[i][0], list[i][1] + w.length, "axce-occ"); }
                }
            }
        }
        for (i = 0; i < this.hits.length; i++) {
            var h = this.hits[i];
            if (h.line < v.a) { continue; }
            if (h.line >= v.b) { break; }
            this.boxes(html, h.line, h.col, h.eLine, h.eCol, i === this.hitAt ? "axce-hit on" : "axce-hit");
        }
        for (i = 0; i < this.marks.length; i++) {
            mk = this.marks[i];
            var ln = (mk.line || 1) - 1;
            if (ln < v.a || ln >= v.b || ln >= L.length) { continue; }
            var col = Math.max(0, (mk.col || 1) - 1), end = mk.len ? col + mk.len : L[ln].length;
            if (end <= col) { end = col + 1; }
            if (!mk.len && /^\s/.test(L[ln])) { col = Math.max(col, lead(L[ln]).length); }
            this.boxes(html, ln, col, ln, Math.min(end, Math.max(L[ln].length, col + 1)), "axce-uline axce-u-" + (mk.sev || "error"));
        }
        this.under.innerHTML = html.join("");
    };
    /* the indent guides of the lines in view: one line per indent, down
       through the lines indented past it (a blank line keeps those around it) */
    P.drawGuides = function (html, v) {
        var L = this.lines, kids = this.divs, unit = (this.L.indent || "    ").length || 4, w = this.cw * unit;
        var open = [], runs = [], i, k, lv, prev = 0, div, top, h, s, last = 0, j;
        var levelOf = function (t) { return Math.floor(lead(t).replace(/\t/g, "    ").length / unit); };
        for (i = v.a; i < v.b; i++) {
            div = kids[i];
            if (!div || div.className === "axce-hid") { continue; }
            s = L[i];
            if (/\S/.test(s)) { lv = levelOf(s); prev = lv; }
            else {
                j = i + 1;
                while (j < L.length && j < i + 60 && !/\S/.test(L[j])) { j++; }
                lv = Math.min(prev, j < L.length ? levelOf(L[j]) : 0);
            }
            top = div.offsetTop; h = div.offsetHeight || this.lh;
            for (k = lv; k < open.length; k++) { if (open[k] != null) { runs.push([k, open[k], last]); open[k] = null; } }
            for (k = 0; k < lv; k++) { if (open[k] == null) { open[k] = top; } }
            last = top + h;
        }
        for (k = 0; k < open.length; k++) { if (open[k] != null) { runs.push([k, open[k], last]); } }
        for (i = 0; i < runs.length && i < 600; i++) {
            html.push('<div class="axce-guide" style="left:' + Math.round(8 + runs[i][0] * w) + "px;top:" + runs[i][1]
                + "px;height:" + Math.max(0, runs[i][2] - runs[i][1]) + 'px"></div>');
        }
    };
    P.boxes = function (html, l1, c1, l2, c2, cls) {
        try {
            var p = this.nodeAt(l1, c1), q = this.nodeAt(l2, c2), r = document.createRange();
            r.setStart(p.node, p.off); r.setEnd(q.node, q.off);
            var rects = r.getClientRects(), s = this.scroll.getBoundingClientRect(), i, x;
            if (!rects.length && cls.indexOf("uline") >= 0) { rects = [r.getBoundingClientRect()]; }
            for (i = 0; i < rects.length && i < 30; i++) {
                x = rects[i];
                if (!x.width && cls.indexOf("uline") < 0) { continue; }
                html.push('<div class="' + cls + '" style="left:' + Math.round(x.left - s.left + this.scroll.scrollLeft)
                    + "px;top:" + Math.round(x.top - s.top + this.scroll.scrollTop) + "px;width:" + Math.max(5, Math.round(x.width))
                    + "px;height:" + Math.round(x.height || this.lh) + 'px"></div>');
            }
        } catch (e) { }
    };
    P.wordUnder = function (line, col) {
        var s = this.lines[line] || "", a = col, b = col;
        while (a > 0 && /[\w$]/.test(s.charAt(a - 1))) { a--; }
        while (b < s.length && /[\w$]/.test(s.charAt(b))) { b++; }
        return s.substring(a, b);
    };
    /* the bracket by the caret and its partner: [[line, col], [line, col]] */
    P.matchBracket = function (line, col) {
        var L = this.lines, s = L[line] || "", open = "([{", close = ")]}", c = s.charAt(col), at = col, d, want, depth = 0, i, j, k = 0, t;
        if (open.indexOf(c) < 0 && close.indexOf(c) < 0) { at = col - 1; c = s.charAt(at); }
        if (at < 0) { return null; }
        if (open.indexOf(c) >= 0) { d = 1; want = close.charAt(open.indexOf(c)); }
        else if (close.indexOf(c) >= 0) { d = -1; want = open.charAt(close.indexOf(c)); }
        else { return null; }
        for (i = line; i >= 0 && i < L.length && k < 3000; i += d, k++) {
            t = L[i];
            for (j = (i === line ? at : (d > 0 ? 0 : t.length - 1)); j >= 0 && j < t.length; j += d) {
                var x = t.charAt(j);
                if (x === c) { depth++; }
                else if (x === want) { depth--; if (depth === 0) { return [[line, at], [i, j]]; } }
            }
        }
        return null;
    };

    /* -------------------------------------------------------------- status */
    P.status = function () {
        this.toggle("axce-empty", this.lines.length === 1 && this.lines[0] === "");
        if (!this.statEl || this.o.status === false) { return; }
        var c = this.lastC, e = 0, w = 0, i, o = this.ord(c), sel = 0;
        if (!this.collapsed(c)) { sel = this.offAt(o.el, o.ec) - this.offAt(o.sl, o.sc); }
        for (i = 0; i < this.marks.length; i++) { if (this.marks[i].sev === "warn") { w++; } else if (this.marks[i].sev !== "info") { e++; } }
        var ind = this.L.indent ? (this.L.indent.charAt(0) === "\t" ? "Tabs" : "Spaces: " + this.L.indent.length) : "";
        var h = '<span>Ln ' + (c.line + 1) + ", Col " + (c.col + 1) + (sel ? " (" + sel + " selected)" : "") + "</span>"
            + (e ? '<span class="axce-se" data-s="next" title="Next problem (F8)">&#x2716; ' + e + "</span>" : "")
            + (w ? '<span class="axce-sw" data-s="next" title="Next problem (F8)">&#x26A0; ' + w + "</span>" : "")
            + '<span class="axce-sl">' + esc(this.L.name || "") + "</span>"
            + (ind ? '<span class="axce-sl">' + ind + "</span>" : "")
            + '<span class="axce-sl axce-sb' + (this.wrapped() ? " on" : "") + '" data-s="wrap" title="Wrap long lines (Alt+Z)">Wrap</span>'
            + (this.miniBox ? '<span class="axce-sl axce-sb' + (this.o.minimap ? " on" : "") + '" data-s="map" title="The map of the text">Map</span>' : "");
        if (h !== this.statHtml) { this.statHtml = h; this.statEl.innerHTML = h; }
    };
    /* the text changed: tell AutoHotkey once the typing pauses */
    P.changed = function (quiet) {
        var self = this;
        this.quiet = !!quiet;
        if (this.cTimer) { window.clearTimeout(this.cTimer); }
        this.cTimer = window.setTimeout(function () { self.cTimer = null; self.sendChange(true); }, this.o.changeDelay || 350);
    };
    /* the change, now (or, from its timer, as it was due) */
    P.sendChange = function (due) {
        if (!due) {
            if (!this.cTimer) { return; }
            window.clearTimeout(this.cTimer);
            this.cTimer = null;
        }
        var v = this.value();
        if (this.val) { this.val.value = v; }
        if (this.sent === v) { this.quiet = false; return; }
        this.sent = v;
        this.post({ kind: "change", quiet: this.quiet ? 1 : 0 });
        this.quiet = false;
    };

    /* --------------------------------------------------------------- the map */
    P.wireMini = function () {
        var self = this, box = this.miniBox, drag = false;
        var go = function (e) {
            var r = box.getBoundingClientRect(), y = (e.clientY - r.top), n = self.lines.length, lh = self.miniLh || 2;
            var ln = Math.max(0, Math.min(n - 1, Math.floor(y / lh))), div = self.divs[ln];
            if (div) { self.scroll.scrollTop = Math.max(0, div.offsetTop - self.scroll.clientHeight / 2); }
        };
        var move = function (e) { if (drag) { go(e); return stop(e); } };
        var up = function () { drag = false; document.removeEventListener("mousemove", move, true); document.removeEventListener("mouseup", up, true); };
        box.addEventListener("mousedown", function (e) {
            drag = true;
            go(e);
            document.addEventListener("mousemove", move, true);
            document.addEventListener("mouseup", up, true);
            return stop(e);
        }, false);
    };
    P.themeColors = function () {
        if (this.colors) { return this.colors; }
        var probe = document.createElement("div"), cls = "c s k n f v d o t p a b h l bo it".split(" "), i, out = {}, h = "";
        probe.className = "axce-ed";
        probe.style.position = "absolute"; probe.style.visibility = "hidden"; probe.style.left = "-9999px";
        for (i = 0; i < cls.length; i++) { h += '<i class="' + cls[i] + '">x</i>'; }
        probe.innerHTML = h;
        this.scroll.appendChild(probe);
        try {
            out[""] = window.getComputedStyle(this.ed).color;
            for (i = 0; i < cls.length; i++) { out[cls[i]] = window.getComputedStyle(probe.childNodes[i]).color; }
        } catch (e) { out[""] = "#888"; }
        this.scroll.removeChild(probe);
        this.colors = out;
        return out;
    };
    P.drawMini = function () {
        if (!this.miniBox) { return; }
        var on = !!this.o.minimap && !this.wrapped() && !!this.mini.getContext;
        this.miniBox.style.display = on ? "" : "none";
        this.toggle("axce-mapon", on);
        if (!on) { return; }
        var cv = this.mini, W = this.miniBox.clientWidth, H = this.miniBox.clientHeight, n = this.lines.length;
        if (!W || !H) { return; }
        if (cv.width !== W) { cv.width = W; }
        if (cv.height !== H) { cv.height = H; }
        var ctx = cv.getContext("2d"), col = this.themeColors(), lh = Math.min(3, H / Math.max(1, n)), i, x, y;
        this.miniLh = lh;
        ctx.clearRect(0, 0, W, H);
        ctx.globalAlpha = 0.7;
        var th = Math.max(1, lh * 0.72), maxX = W - 7, max = Math.min(n, 6000);
        var run = function (text, color) {
            var k, s = -1;
            ctx.fillStyle = color;
            for (k = 0; k <= text.length; k++) {
                var ch = text.charAt(k);
                if (k < text.length && ch !== " " && ch !== "\t") { if (s < 0) { s = x; } }
                else if (s >= 0) { if (s < maxX) { ctx.fillRect(2 + s, y, Math.min(x, maxX) - s, th); } s = -1; }
                if (k < text.length) { x += ch === "\t" ? 4 : 1; }
            }
        };
        /* from the text, not the page: a comment in its colour, the rest in
           the text's (walking thousands of coloured lines took longer than
           the pause it runs in) */
        var Lg = this.L, tok = Lg.line || "", sts = this.sts, L = this.lines, s, t;
        for (i = 0; i < max; i++) {
            y = i * lh;
            x = 0;
            s = L[i];
            t = s.replace(/^\s+/, "");
            if ((sts[i] && sts[i].indexOf("b") >= 0) || (tok && t.indexOf(tok) === 0) || (Lg.md && t.charAt(0) === "#")) {
                run(s, Lg.md ? col.h : col.c);
            } else {
                run(s, col[""]);
            }
        }
        /* the problems and the finds, on the right edge */
        ctx.globalAlpha = 1;
        var edge = function (ln, c) { ctx.fillStyle = c; ctx.fillRect(W - 4, Math.min(H - 2, ln * lh), 4, Math.max(2, lh)); };
        for (i = 0; i < this.hits.length && i < 2000; i++) { edge(this.hits[i].line, "#e0a000"); }
        for (i = 0; i < this.marks.length; i++) { edge((this.marks[i].line || 1) - 1, this.marks[i].sev === "warn" ? "#cca700" : this.marks[i].sev === "info" ? "#3794ff" : "#f14c4c"); }
        this.drawMiniView();
    };
    P.drawMiniView = function () {
        if (!this.miniBox || this.miniBox.style.display === "none" || !this.o.minimap) { return; }
        var s = this.scroll, n = this.lines.length, lh = this.miniLh || 2, total = n * lh, sh = s.scrollHeight || 1;
        var y = s.scrollTop / sh * total, h = Math.max(10, s.clientHeight / sh * total);
        this.mview.style.top = Math.round(y) + "px";
        this.mview.style.height = Math.round(h) + "px";
    };

    /* ----------------------------------------------------------- suggestions */
    P.wordAt = function () {
        var c = this.lastC, s = this.lines[c.line] || "", head = s.substring(0, c.col), m;
        var wre = this.L.wordRe ? new RegExp("(" + this.L.wordRe + ")$") : /([A-Za-z_#$@][\w$]*)$/;
        m = /([A-Za-z_$][\w$]*)\.([\w$]*)$/.exec(head);
        if (m && !this.L.css && !this.L.md) { return { line: c.line, scope: m[1], word: m[2], from: c.col - m[2].length }; }
        /* after a call: "g.AddButton(...)." -- what calls give back, scope "()" */
        m = /\)\s*\.([\w$]*)$/.exec(head);
        if (m && !this.L.css && !this.L.md) { return { line: c.line, scope: "()", word: m[1], from: c.col - m[1].length }; }
        m = wre.exec(head);
        if (m) { return { line: c.line, scope: "", word: m[1], from: c.col - m[1].length }; }
        return { line: c.line, scope: "", word: "", from: c.col };
    };
    /* the text's words and what it defines, once per pause */
    P.docIndex = function () {
        if (this.index) { return this.index; }
        var t = this.value(), re = this.L.css ? /[A-Za-z_\-][\w\-]{2,}/g : /[A-Za-z_$][\w$]{2,}/g, m, cnt = {}, list = [], n = 0, lk;
        while ((m = re.exec(t)) && n < 30000) {
            n++;
            lk = m[0].toLowerCase();
            if (!cnt.hasOwnProperty(lk)) { cnt[lk] = 0; list.push(m[0]); }
            cnt[lk]++;
        }
        var syms = AXCE.symbols(t, this.o.lang), mem = {}, re2 = /([A-Za-z_$][\w$]*)\.([A-Za-z_$][\w$]*)/g, i;
        while ((m = re2.exec(t)) && n < 60000) {
            n++;
            lk = m[1].toLowerCase();
            if (!mem[lk]) { mem[lk] = {}; }
            mem[lk][m[2].toLowerCase()] = m[2];
        }
        for (i = 0; i < syms.length; i++) {
            if (syms[i].detail && (syms[i].kind === "fn" || syms[i].kind === "method")) { this.sigs[syms[i].name.toLowerCase()] = syms[i].name + syms[i].detail; }
        }
        this.index = { words: list, cnt: cnt, syms: syms, mem: mem };
        return this.index;
    };
    /* what may be suggested for a scope ("" at the top level) */
    P.pool = function (scope) {
        var out = [], seen = {}, L = this.L, idx2 = this.docIndex(), k, i, s, list, set, x, lang = this.o.lang;
        var add = function (label, kind, detail, insert, rank) {
            if (!label) { return; }
            var lk = String(label).toLowerCase();
            if (seen[lk]) { return; }
            seen[lk] = 1;
            out.push({ label: String(label), lk: lk, kind: kind || "word", detail: detail || "", insert: insert || "", rank: rank || 0 });
        };
        var sl = scope.toLowerCase();
        for (k in this.sets) {
            if (!this.sets.hasOwnProperty(k)) { continue; }
            set = this.sets[k];
            if (set.lang && set.lang !== lang) { continue; }
            for (i = 0; i < set.items.length; i++) {
                x = set.items[i];
                var xs = String(x.scope || "").toLowerCase();
                /* a scope may be several at once: "ctl|btnOk|name" -- the same members for each */
                var hit = scope ? (xs === sl || xs === "*" || (xs.indexOf("|") >= 0 && ("|" + xs + "|").indexOf("|" + sl + "|") >= 0)) : !xs;
                if (hit) { add(x.label, x.kind || (scope ? "prop" : "var"), x.detail, x.insert, 2); }
            }
        }
        if (!scope) {
            for (i = 0; i < idx2.syms.length; i++) {
                s = idx2.syms[i];
                if (s.kind === "hotkey" || s.kind === "heading" || s.kind === "section") { continue; }
                add(s.name, s.kind, (s.detail || "") + "  line " + s.line, "", 4);
            }
            list = (L.snippets || []).concat(this.snips);
            for (i = 0; i < list.length; i++) { add(list[i].label, "snippet", list[i].detail || "snippet", list[i].body, 1); }
            for (k in L.kw || {}) { if (L.kw.hasOwnProperty(k) && /^[a-z]/i.test(k)) { add(L.kw[k], "kw", "keyword", "", 1); } }
            for (k in L.types || {}) { if (L.types.hasOwnProperty(k)) { add(L.types[k], "class", "class"); } }
            for (k in L.bi || {}) { if (L.bi.hasOwnProperty(k)) { add(L.bi[k], "var", "built-in"); } }
            for (k in L.more || {}) { if (L.more.hasOwnProperty(k)) { add(L.more[k], L.css ? "prop" : "word", L.name); } }
            for (i = 0; i < idx2.words.length; i++) { add(idx2.words[i], "word", ""); }
        } else {
            var mm = L.members || {};
            for (k in mm) {
                if (mm.hasOwnProperty(k) && (k.toLowerCase() === sl)) {
                    list = mm[k].split(" ");
                    for (i = 0; i < list.length; i++) { add(list[i], "prop", k); }
                }
            }
            var mine = idx2.mem[sl];
            if (mine) { for (k in mine) { if (mine.hasOwnProperty(k)) { add(mine[k], "prop", scope); } } }
            if (mm["*"]) { list = mm["*"].split(" "); for (i = 0; i < list.length; i++) { add(list[i], "method", ""); } }
        }
        return out;
    };
    P.suggest = function (force) {
        if (this.o.suggest === false && !force) { return; }
        if (this.o.readonly || this.o.design || !this.collapsed()) { return this.closeAc(); }
        var w = this.wordAt(), s = this.sess;
        if (!force && !w.scope && w.word.length < (this.o.suggestAfter || 1)) { this.sess = null; return this.closeAc(); }
        if (!force && (this.inToken(w.line, w.from, "c") || this.inToken(w.line, w.from, "s"))) { this.sess = null; return this.closeAc(); }
        if (!s || s.line !== w.line || s.from !== w.from || s.scope !== w.scope || force) {
            s = this.sess = { line: w.line, from: w.from, scope: w.scope, pool: this.pool(w.scope), q: 0, forced: !!force };
            var remote = this.o.remote === true || this.o.remote === 1 || (this.o.remote === "scope" && w.scope);
            if (remote) {
                s.q = ++this.qn;
                this.post({ kind: "complete", q: s.q, word: w.word, scope: w.scope, line: w.line + 1, col: this.lastC.col + 1 });
            }
        }
        s.word = w.word;
        this.showAc(this.rank(s));
    };
    P.rank = function (s) {
        var q = s.word || "", ql = q.toLowerCase(), out = [], i, x, r, cnt = this.index ? this.index.cnt : {};
        for (i = 0; i < s.pool.length; i++) {
            x = s.pool[i];
            if (x.lk === ql && x.kind === "word" && (cnt[x.lk] || 0) <= 1) { continue; }
            r = fuzzy(x.lk, x.label, ql, q);
            if (!r) { continue; }
            out.push({ it: x, s: r.s + x.rank * 6, m: r.m });
        }
        out.sort(function (a, b) { return (b.s - a.s) || (a.it.lk < b.it.lk ? -1 : a.it.lk > b.it.lk ? 1 : 0); });
        if (out.length > 60) { out.length = 60; }
        /* the word already typed out in full, alone, needs no list */
        if (!s.forced && out.length === 1 && out[0].it.lk === ql && out[0].it.kind !== "snippet") { return []; }
        return out;
    };
    P.showAc = function (items) {
        if (!items.length) { return this.closeAc(); }
        var keep = this.ac.open && this.ac.items[this.ac.i] ? this.ac.items[this.ac.i].it.lk : "";
        this.ac.items = items;
        this.ac.i = 0;
        if (keep) { for (var i = 0; i < items.length; i++) { if (items[i].it.lk === keep && i < 3) { this.ac.i = i; break; } } }
        this.drawAc();
    };
    P.drawAc = function () {
        var h = [], i, j, e, it, lab, m, b;
        for (i = 0; i < this.ac.items.length; i++) {
            e = this.ac.items[i]; it = e.it; m = {}; lab = "";
            for (j = 0; j < e.m.length; j++) { m[e.m[j]] = 1; }
            for (j = 0; j < it.label.length; j++) {
                b = m[j] && !m[j - 1] ? "<b>" : "";
                lab += b + esc(it.label.charAt(j)) + (m[j] && !m[j + 1] ? "</b>" : "");
            }
            h.push('<div class="axce-aci' + (i === this.ac.i ? " on" : "") + '" data-i="' + i + '"><i class="axce-ak ak-' + esc(it.kind || "word")
                + '">' + (KIND[it.kind] || "w") + "</i>" + lab + (it.detail ? '<span title="' + attr(it.detail) + '">' + esc(it.detail) + "</span>" : "") + "</div>");
        }
        this.acEl.innerHTML = h.join("");
        this.acEl.style.display = "block";
        this.ac.open = true;
        this.placeAc();
        this.acEl.scrollTop = 0;
        this.acInView();
    };
    P.acInView = function () {
        var el = this.acEl.childNodes[this.ac.i];
        if (!el) { return; }
        if (el.offsetTop < this.acEl.scrollTop) { this.acEl.scrollTop = el.offsetTop; }
        else if (el.offsetTop + el.offsetHeight > this.acEl.scrollTop + this.acEl.clientHeight) { this.acEl.scrollTop = el.offsetTop + el.offsetHeight - this.acEl.clientHeight; }
    };
    /* by the start of the word, not the caret, so it does not creep as you type */
    P.caretRect = function (line, col) {
        try {
            var p = this.nodeAt(line, col), r = document.createRange();
            r.setStart(p.node, p.off); r.collapse(true);
            var b = r.getBoundingClientRect();
            if (b && (b.left || b.top)) { return b; }
            var div = this.divs[line];
            if (div) { var d = div.getBoundingClientRect(); return { left: d.left + 8, top: d.top, bottom: d.top + this.lh }; }
        } catch (e) { }
        return null;
    };
    P.placeAc = function () {
        var s = this.sess, r = s ? this.caretRect(s.line, s.from) : null, root = this.root.getBoundingClientRect();
        var x = 40, y = 24, H = this.acEl.offsetHeight || 200;
        if (r) { x = r.left - root.left - 26; y = r.bottom - root.top + 2; }
        var maxX = root.right - root.left - (this.acEl.offsetWidth || 280) - 4;
        if (x > maxX) { x = maxX; }
        if (x < 0) { x = 0; }
        if (y + H > root.bottom - root.top && r) { y = Math.max(0, r.top - root.top - H - 2); }
        this.acEl.style.left = Math.round(x) + "px";
        this.acEl.style.top = Math.round(y) + "px";
    };
    P.moveAc = function (d) {
        var n = this.ac.items.length, was = this.ac.i, k = this.acEl.childNodes;
        if (!n) { return; }
        if (Math.abs(d) > 1) { this.ac.i = Math.max(0, Math.min(n - 1, was + d)); }
        else { this.ac.i = (was + d + n) % n; }
        if (k[was]) { k[was].className = "axce-aci"; }
        if (k[this.ac.i]) { k[this.ac.i].className = "axce-aci on"; }
        this.acInView();
    };
    P.accept = function () {
        var e = this.ac.items[this.ac.i], s = this.sess;
        this.closeAc();
        this.sess = null;
        if (!e || !s) { return; }
        var it = e.it, c = this.lastC, body = it.insert || it.label, L = this.lines, line = L[s.line] || "";
        var from = this.offAt(s.line, s.from), end = this.offAt(c.line, c.col);
        /* the rest of the word after the caret goes too */
        var j = c.col;
        while (j < line.length && /[\w$]/.test(line.charAt(j))) { j++; }
        end += j - c.col;
        if ((it.kind === "fn" || it.kind === "method") && !it.insert && line.charAt(j) !== "(" && this.sigs[it.lk] && !this.L.css) { body = it.label + "($0)"; }
        if (body.indexOf("$0") >= 0 || body.indexOf("\n") >= 0) {
            var ind = lead(line);
            body = body.replace(/\n/g, "\n" + ind);
            var at = body.indexOf("$0");
            body = body.replace("$0", "");
            this.edit(from, end, body, from + (at >= 0 ? at : body.length));
        } else {
            this.edit(from, end, body);
        }
        if (body.indexOf("(") >= 0) { this.sigUpdate(true); }
    };
    P.closeAc = function () {
        this.ac.open = false;
        if (this.acEl) { this.acEl.style.display = "none"; }
    };

    /* ----------------------------------------------------- the parameters card */
    P.sigUpdate = function (open, force) {
        if (this.o.suggest === false || this.o.design) { return; }
        if (!open && !this.sigOn) { return; }
        var c = this.lastC;
        if (!this.collapsed(c)) { return this.hideSig(); }
        var s = (this.lines[c.line] || "").substring(0, c.col), depth = 0, commas = 0, i, ch, q = "";
        for (i = s.length - 1; i >= 0; i--) {
            ch = s.charAt(i);
            if (q) { if (ch === q) { q = ""; } continue; }
            if (ch === "\"" || ch === "'") { q = ch; continue; }
            if (ch === ")" || ch === "]" || ch === "}") { depth++; }
            else if (ch === "(" || ch === "[" || ch === "{") {
                if (depth === 0) { break; }
                depth--;
            } else if (ch === "," && depth === 0) { commas++; }
        }
        if (i < 0 || s.charAt(i) !== "(") { return this.hideSig(); }
        var m = /([A-Za-z_$][\w$]*)\s*$/.exec(s.substring(0, i));
        var sig = m ? this.sigs[m[1].toLowerCase()] : "";
        if (!sig) { return this.hideSig(); }
        var p = sig.indexOf("("), name = sig.substring(0, p), rest = sig.substring(p + 1), close = rest.lastIndexOf(")");
        var params = close >= 0 ? rest.substring(0, close) : rest, tail = close >= 0 ? rest.substring(close + 1) : "";
        var parts = params ? params.split(/,\s*/) : [], h = [];
        for (i = 0; i < parts.length; i++) {
            var on = i === commas || (i === parts.length - 1 && /\*$/.test(parts[i]) && commas > i);
            h.push(on ? "<b>" + esc(parts[i]) + "</b>" : esc(parts[i]));
        }
        this.sigEl.innerHTML = "<code>" + esc(name) + "(" + h.join(", ") + ")" + esc(tail) + "</code>";
        this.sigEl.style.display = "block";
        this.sigOn = true;
        var r = this.caretRect(c.line, c.col), root = this.root.getBoundingClientRect();
        if (r) {
            var x = Math.max(0, Math.min(r.left - root.left - 10, root.right - root.left - this.sigEl.offsetWidth - 6));
            var y = r.top - root.top - this.sigEl.offsetHeight - 4;
            if (y < 0 || (this.ac.open && this.acEl.offsetTop < r.top - root.top)) { y = r.bottom - root.top + 4 + (this.ac.open ? this.acEl.offsetHeight + 4 : 0); }
            this.sigEl.style.left = Math.round(x) + "px";
            this.sigEl.style.top = Math.round(y) + "px";
        }
        if (force) { this.sigOn = true; }
    };
    P.hideSig = function () { this.sigOn = false; if (this.sigEl) { this.sigEl.style.display = "none"; } };

    /* ------------------------------------------------------------- hovering */
    P.onMouseMove = function (e) {
        var self = this, x = e.clientX, y = e.clientY;
        if (this.hTimer) { window.clearTimeout(this.hTimer); }
        if (this.tipOn && this.tipAt && Math.abs(x - this.tipAt.x) + Math.abs(y - this.tipAt.y) > 24) { this.hideTip(); }
        this.hTimer = window.setTimeout(function () { self.hTimer = null; self.hoverAt(x, y); }, 450);
    };
    P.hoverAt = function (x, y) {
        var el = document.elementFromPoint(x, y), div = el, line, col = -1;
        while (div && div.parentNode !== this.ed) { div = div.parentNode; }
        if (!div) { return; }
        line = this.divs.indexOf(div);
        try {
            var tr = document.body.createTextRange();
            tr.moveToPoint(x, y);
            var lr = document.body.createTextRange();
            lr.moveToElementText(div);
            lr.setEndPoint("EndToStart", tr);
            col = lr.text.replace(/[\r\n]/g, "").length;
        } catch (e2) { return; }
        if (line < 0 || col < 0) { return; }
        var s = this.lines[line] || "";
        this.tipAt = { x: x, y: y };
        /* a problem under the mouse speaks for itself */
        var i, mk, said = [];
        for (i = 0; i < this.marks.length; i++) {
            mk = this.marks[i];
            if ((mk.line || 1) - 1 !== line) { continue; }
            var c1 = (mk.col || 1) - 1, c2 = mk.len ? c1 + mk.len : s.length;
            if (col >= Math.min(c1, lead(s).length) - 1 && col <= c2 + 1) { said.push('<div class="axce-tm axce-tm-' + (mk.sev || "error") + '">' + esc(mk.msg || "") + "</div>"); }
        }
        var a = col, b = col;
        while (a > 0 && /[\w$#]/.test(s.charAt(a - 1))) { a--; }
        while (b < s.length && /[\w$]/.test(s.charAt(b))) { b++; }
        var word = s.substring(a, b);
        this.tipMarks = said.join("");
        if (said.length) { this.showTip(""); }
        if (!this.o.hover || !/^[A-Za-z_#$][\w$]*$/.test(word)) { if (!said.length) { this.hideTip(); } return; }
        this.hoverQ = ++this.qn;
        this.post({ kind: "hover", q: this.hoverQ, word: word, line: line + 1, col: a + 1 });
    };
    P.showTip = function (html) {
        html = (this.tipMarks || "") + (html || "");
        if (!html) { return this.hideTip(); }
        var root = this.root.getBoundingClientRect(), t = this.tipEl;
        t.innerHTML = html;
        t.style.display = "block";
        this.tipOn = true;
        var x = (this.tipAt ? this.tipAt.x : root.left) - root.left + 8, y = (this.tipAt ? this.tipAt.y : root.top) - root.top + 16;
        if (x + t.offsetWidth > root.right - root.left) { x = Math.max(0, root.right - root.left - t.offsetWidth - 4); }
        if (y + t.offsetHeight > root.bottom - root.top) { y = Math.max(0, y - t.offsetHeight - 26); }
        t.style.left = Math.round(x) + "px";
        t.style.top = Math.round(y) + "px";
    };
    P.hideTip = function () { this.tipOn = false; this.tipMarks = ""; if (this.tipEl) { this.tipEl.style.display = "none"; } };
    /* F8: the next problem, and what it says */
    P.problem = function (d) {
        if (!this.marks.length) { return; }
        var list = this.marks.slice(0).sort(function (a, b) { return (a.line - b.line) || ((a.col || 1) - (b.col || 1)); });
        var c = this.lastC, i, pick = null;
        if (d > 0) { for (i = 0; i < list.length; i++) { if (list[i].line - 1 > c.line || (list[i].line - 1 === c.line && (list[i].col || 1) - 1 > c.col)) { pick = list[i]; break; } } if (!pick) { pick = list[0]; } }
        else { for (i = list.length - 1; i >= 0; i--) { if (list[i].line - 1 < c.line || (list[i].line - 1 === c.line && (list[i].col || 1) - 1 < c.col)) { pick = list[i]; break; } } if (!pick) { pick = list[list.length - 1]; } }
        this.goLine(pick.line, pick.col || 1);
        var r = this.caretRect(pick.line - 1, (pick.col || 1) - 1);
        this.tipAt = r ? { x: r.left, y: r.bottom - 8 } : null;
        this.tipMarks = '<div class="axce-tm axce-tm-' + (pick.sev || "error") + '">' + esc(pick.msg || "") + "</div>";
        this.showTip("");
    };

    /* ------------------------------------------------------------------ find */
    P.wireFind = function () {
        var self = this, q = this.fq, r = this.fr;
        this.findEl.addEventListener("mousedown", function (e) {
            var t = e.target || e.srcElement;
            while (t && t !== self.findEl && !(t.getAttribute && (t.getAttribute("data-f") || t.getAttribute("data-fl")))) { t = t.parentNode; }
            if (!t || t === self.findEl) { return; }
            var act = t.getAttribute("data-f");
            if (t.getAttribute("data-fl")) { self.symPick(parseInt(t.getAttribute("data-fl"), 10)); return stop(e); }
            if (act === "next") { self.findStep(1); }
            else if (act === "prev") { self.findStep(-1); }
            else if (act === "one") { self.replaceOne(); }
            else if (act === "all") { self.replaceAllHits(); }
            else if (act === "cs" || act === "ww" || act === "re") { self.fo[act] = !self.fo[act]; self.findFlags(); self.findRun(); }
            else if (act === "rep") { self.toggle("axce-replacing", !has(self.root, "axce-replacing") && !self.o.readonly); }
            else if (act === "x") { self.closeFind(); }
            return stop(e);
        }, false);
        var keys = function (e, rep) {
            var k = e.keyCode;
            if (e.altKey && (k === 67 || k === 87 || k === 82)) { var f = k === 67 ? "cs" : k === 87 ? "ww" : "re"; self.fo[f] = !self.fo[f]; self.findFlags(); self.findRun(); return stop(e); }
            if (k === 27) { self.closeFind(); return stop(e); }
            if (e.ctrlKey && k === 72) { self.toggle("axce-replacing", !self.o.readonly); try { self.fr.focus(); } catch (x) { } return stop(e); }
            if (e.ctrlKey && e.altKey && k === 13) { self.replaceAllHits(); return stop(e); }
            if (!rep && self.symMode) {
                if (k === 40 || k === 38) { self.symMove(k === 40 ? 1 : -1); return stop(e); }
                if (k === 13) { self.symPick(self.symAt); return stop(e); }
            }
            if (k === 13) {
                if (rep) { self.replaceOne(); }
                else if (/^:\d+/.test(q.value)) { var parts = q.value.substring(1).split(/[:,]/); self.closeFind(); self.goLine(parseInt(parts[0], 10), parseInt(parts[1] || "1", 10)); }
                else { self.findStep(e.shiftKey ? -1 : 1); }
                return stop(e);
            }
            if (k === 114) { self.findStep(e.shiftKey ? -1 : 1); return stop(e); }
        };
        q.addEventListener("keydown", function (e) { return keys(e, false); }, false);
        r.addEventListener("keydown", function (e) { return keys(e, true); }, false);
        q.addEventListener("keyup", function (e) {
            var k = e.keyCode;
            if (k === 13 || k === 27 || k === 38 || k === 40 || k === 16 || k === 18 || k === 114) { return; }
            if (self.fTimer) { window.clearTimeout(self.fTimer); }
            self.fTimer = window.setTimeout(function () { self.fTimer = null; self.findRun(); }, self.lines.length > 3000 ? 140 : 30);
        }, false);
    };
    P.findFlags = function () {
        var k = this.findEl.getElementsByTagName("span"), i, f;
        for (i = 0; i < k.length; i++) {
            f = k[i].getAttribute("data-f");
            if (f === "cs" || f === "ww" || f === "re") { k[i].className = this.fo[f] ? "on" : ""; }
        }
    };
    P.openFind = function (replace, pre) {
        if (!this.findEl) { return; }
        this.flush();
        var q = this.fq, c = this.lastC, o = this.ord();
        this.toggle("axce-finding", true);
        this.toggle("axce-replacing", !!replace && !this.o.readonly);
        if (pre != null && pre !== "") { q.value = pre; }
        else if (!this.collapsed(c) && o.sl === o.el) { q.value = this.lines[o.sl].substring(o.sc, o.ec); }
        else if (!q.value) { q.value = this.wordUnder(c.line, c.col); }
        this.findFlags();
        try { q.focus(); if (pre === ":" || pre === "@") { var r = q.createTextRange(); r.collapse(false); r.select(); } else { q.select(); } } catch (e) { }
        this.hitAt = -1;
        this.findRun();
    };
    P.closeFind = function () {
        var h = this.hits[this.hitAt];
        this.toggle("axce-finding", false);
        this.toggle("axce-replacing", false);
        this.symMode = false;
        if (this.fl) { this.fl.style.display = "none"; }
        this.hits = [];
        this.hitAt = -1;
        this.focus();
        if (h) { this.setSel(h.line, h.col, h.eLine, h.eCol); }
        this.caretMoved();
        this.drawMini();
    };
    P.findRe = function (q, global) {
        var src = this.fo.re ? q : reEsc(q);
        if (this.fo.ww) { src = "(?:^|\\b)(?:" + src + ")(?:\\b|$)"; }
        return new RegExp(src, (global === false ? "" : "g") + (this.fo.cs ? "" : "i") + "m");
    };
    P.findRun = function (keep) {
        if (!this.fq) { return; }
        var q = this.fq.value, t, re, hits = [], m, i, line = 0, ls = 0, L = this.lines;
        this.symMode = q.charAt(0) === "@";
        if (this.fl) { this.fl.style.display = this.symMode ? "block" : "none"; }
        this.hits = [];
        if (!keep) { this.hitAt = -1; }
        this.fn.className = "axce-fn";
        if (this.symMode) { this.fn.innerHTML = ""; this.symList(q.substring(1)); this.decorate(); return; }
        if (q.charAt(0) === ":") { this.fn.innerHTML = "line 1-" + L.length; this.decorate(); this.drawMini(); return; }
        if (!q) { this.fn.innerHTML = ""; this.decorate(); this.drawMini(); return; }
        try { re = this.findRe(q); } catch (e) { this.fn.innerHTML = "not a pattern"; this.fn.className = "axce-fn bad"; this.decorate(); return; }
        t = this.value();
        while ((m = re.exec(t)) && hits.length < 20000) {
            if (!m[0].length) { re.lastIndex++; continue; }
            hits.push({ a: m.index, len: m[0].length });
        }
        /* where each one is, walking the lines once */
        var starts = [0];
        for (i = 1; i < L.length; i++) { starts[i] = starts[i - 1] + L[i - 1].length + 1; }
        var lineOf = function (off, from) { var k = from; while (k + 1 < starts.length && starts[k + 1] <= off) { k++; } return k; };
        for (i = 0; i < hits.length; i++) {
            line = lineOf(hits[i].a, line);
            hits[i].line = line; hits[i].col = hits[i].a - starts[line];
            ls = lineOf(hits[i].a + hits[i].len, line);
            hits[i].eLine = ls; hits[i].eCol = hits[i].a + hits[i].len - starts[ls];
        }
        this.hits = hits;
        if (keep && this.hitAt >= hits.length) { this.hitAt = hits.length - 1; }
        this.findCount();
        this.decorate();
        this.drawMini();
    };
    P.findCount = function () {
        var n = this.hits.length;
        this.fn.innerHTML = n ? (this.hitAt >= 0 ? (this.hitAt + 1) + " of " + n : n + " found") + (n >= 20000 ? "+" : "") : "No results";
        this.fn.className = n ? "axce-fn" : "axce-fn none";
    };
    P.findStep = function (d, fromEditor) {
        if (this.fq && !this.hits.length && this.fq.value && /^[^:@]/.test(this.fq.value)) { this.findRun(); }
        if (!this.hits.length) { if (fromEditor) { this.openFind(false); } return; }
        var c = this.lastC, off = this.offAt(c.line, c.col), i, n = this.hits.length;
        if (this.hitAt < 0) {
            this.hitAt = d > 0 ? 0 : n - 1;
            for (i = 0; i < n; i++) { if (this.hits[i].a >= off) { this.hitAt = d > 0 ? i : (i - 1 + n) % n; break; } }
        } else {
            this.hitAt = (this.hitAt + d + n) % n;
        }
        var h = this.hits[this.hitAt];
        this.unfoldAt(h.line);
        this.lastC = { line: h.eLine, col: h.eCol, aLine: h.line, aCol: h.col };
        if (fromEditor || this.focused) { this.setSel(h.line, h.col, h.eLine, h.eCol); }
        this.reveal(h.line, true);
        this.findCount();
        this.decorate();
        this.status();
    };
    function expand(by, m) {
        if (!m) { return by; }
        return by.replace(/\$(\$|&|\d{1,2})/g, function (x, g) {
            if (g === "$") { return "$"; }
            if (g === "&") { return m[0]; }
            var k = parseInt(g, 10);
            return m[k] != null ? m[k] : "";
        });
    }
    P.replBy = function () {
        var by = this.fr ? this.fr.value : "";
        return this.fo.re ? by.replace(/\\n/g, "\n").replace(/\\t/g, "\t") : by;
    };
    P.replaceOne = function () {
        if (this.o.readonly) { return; }
        if (this.hitAt < 0 || !this.hits[this.hitAt]) { return this.findStep(1); }
        var h = this.hits[this.hitAt], by = this.replBy(), t = this.value(), rep = by;
        if (this.fo.re) {
            var re = this.findRe(this.fq.value);
            re.lastIndex = h.a;
            var m = re.exec(t);
            if (m && m.index === h.a) { rep = expand(by, m); }
        }
        var at = h.a, wasFocused = this.focused;
        this.edit(h.a, h.a + h.len, rep, h.a + rep.length);
        this.findRun(true);
        this.hitAt = -1;
        for (var i = 0; i < this.hits.length; i++) { if (this.hits[i].a >= at + rep.length) { this.hitAt = i; break; } }
        if (this.hitAt < 0 && this.hits.length) { this.hitAt = 0; }
        if (this.hits.length) { var n = this.hits[this.hitAt]; this.reveal(n.line, true); }
        this.findCount();
        this.decorate();
        if (!wasFocused) { try { this.fr.focus(); } catch (e) { } }
    };
    P.replaceAllHits = function () {
        if (this.o.readonly || !this.fq || !this.fq.value) { return; }
        var n = this.replaceAllOf(this.fq.value, this.replBy());
        this.findRun();
        this.fn.innerHTML = n + " replaced";
    };
    P.replaceAllOf = function (q, by) {
        this.flush();
        var re = this.findRe(q), t = this.value(), n = 0, rx = this.fo.re;
        var out = t.replace(re, function () {
            n++;
            return rx ? expand(by, Array.prototype.slice.call(arguments, 0, arguments.length - 2)) : by;
        });
        if (!n) { return 0; }
        this.setAll(out);
        var c = this.lastC;
        this.setSel(Math.min(c.line, this.lines.length - 1), 0, Math.min(c.line, this.lines.length - 1), 0);
        this.remember();
        this.after(true);
        return n;
    };
    /* "@": what the text defines, to jump to */
    P.symList = function (q) {
        var syms = AXCE.symbols(this.value(), this.o.lang), out = [], i, r, ql = q.toLowerCase(), h = [];
        for (i = 0; i < syms.length; i++) {
            r = fuzzy(syms[i].name.toLowerCase(), syms[i].name, ql, q);
            if (r) { out.push({ s: r.s, it: syms[i], m: r.m }); }
        }
        if (q) { out.sort(function (a, b) { return b.s - a.s; }); }
        if (out.length > 40) { out.length = 40; }
        this.symItems = out;
        this.symAt = 0;
        for (i = 0; i < out.length; i++) {
            h.push('<div data-fl="' + i + '"' + (i === 0 ? ' class="on"' : "") + '><i class="axce-ak ak-' + esc(out[i].it.kind) + '">'
                + (KIND[out[i].it.kind] || "w") + "</i>" + esc(out[i].it.name) + "<span>" + out[i].it.line + "</span></div>");
        }
        this.fl.innerHTML = h.join("") || '<div class="axce-fnone">Nothing defined by that name</div>';
    };
    P.symMove = function (d) {
        var k = this.fl.childNodes, n = this.symItems ? this.symItems.length : 0;
        if (!n) { return; }
        if (k[this.symAt]) { k[this.symAt].className = ""; }
        this.symAt = (this.symAt + d + n) % n;
        if (k[this.symAt]) { k[this.symAt].className = "on"; }
    };
    P.symPick = function (i) {
        var it = this.symItems && this.symItems[i];
        if (!it) { return; }
        this.fq.value = "";
        this.closeFind();
        this.goLine(it.it.line, 1);
    };

    /* ------------------------------------------------- talking to AutoHotkey */
    P.post = function (m) {
        if (!this.req || this.o.design) { return; }
        this.queue.push(m);
        var self = this;
        if (!this.qTimer) { this.qTimer = window.setTimeout(function () { self.pump(); }, 0); }
    };
    P.pump = function () {
        this.qTimer = null;
        if (!this.queue.length) { return; }
        var m = this.queue.shift();
        this.qdata.value = JSON.stringify(m);
        try { this.req.click(); } catch (e) { try { this.req.fireEvent("onclick"); } catch (e2) { } }
        if (this.queue.length) { var self = this; this.qTimer = window.setTimeout(function () { self.pump(); }, 0); }
    };
    P.norm = function (list) {
        var out = [], i, x;
        for (i = 0; i < (list || []).length; i++) {
            x = list[i];
            if (typeof x === "string") { x = { label: x }; }
            if (!x || x.label == null) { continue; }
            x.label = String(x.label);
            out.push(x);
            if ((x.kind === "fn" || x.kind === "method") && x.detail && String(x.detail).charAt(0) === "(") { this.sigs[x.label.toLowerCase()] = x.label + x.detail; }
            else if ((x.kind === "fn" || x.kind === "method") && x.detail && String(x.detail).indexOf(x.label + "(") === 0) { this.sigs[x.label.toLowerCase()] = String(x.detail); }
        }
        return out;
    };
    P.recv = function (m) {
        if (m.kind === "items") {
            var s = this.sess;
            if (!s || m.q !== s.q) { return; }
            var items = this.norm(m.items), seen = {}, i, x, lk, had = s.pool.length;
            for (i = 0; i < s.pool.length; i++) { seen[s.pool[i].lk] = s.pool[i]; }
            for (i = 0; i < items.length; i++) {
                x = items[i]; lk = x.label.toLowerCase();
                if (seen[lk]) {
                    /* one the page had already: a list's own word stays as it
                       is; a plain word of the text takes what the service knows */
                    if (seen[lk].kind === "word") {
                        if (x.detail) { seen[lk].detail = x.detail; }
                        if (x.kind) { seen[lk].kind = x.kind; }
                        if (x.insert) { seen[lk].insert = x.insert; }
                        seen[lk].rank = Math.max(seen[lk].rank, 3);
                    } else if (!seen[lk].detail && x.detail) {
                        seen[lk].detail = x.detail;
                    }
                    continue;
                }
                /* after what the page already knew for this place: a service's
                   guess (the members of any object) comes behind a list's own */
                seen[lk] = { label: x.label, lk: lk, kind: x.kind || "word", detail: x.detail || "", insert: x.insert || "", rank: had ? 0 : 3 };
                s.pool.push(seen[lk]);
            }
            var c = this.lastC;
            if (c.line === s.line && this.collapsed() && this.wordAt().from === s.from) { s.word = this.wordAt().word; this.showAc(this.rank(s)); }
        } else if (m.kind === "marks") {
            this.setMarks(m.marks || []);
        } else if (m.kind === "hover") {
            if (m.q === this.hoverQ) { this.showTip(m.html || (m.text ? esc(m.text).replace(/\n/g, "<br>") : "")); }
        }
    };
    P.setMarks = function (list) {
        this.marks = list || [];
        this.drawGutter();
        this.decorate();
        this.status();
        this.drawMini();
    };

    /* ============================================================= AXCE */
    /* AutoHotkey has no true or false: they arrive as 1 and 0 */
    var FLAGS = { wrap: 1, gutter: 1, status: 1, fold: 1, suggest: 1, currentLine: 1, readonly: 1, hover: 1, remote: 1, minimap: 1, guides: 1, occur: 1, caret: 1, design: 1 };
    function flag(k, v) { return FLAGS[k] && (v === 0 || v === 1 || v === "0" || v === "1") ? (v == 1) : v; }
    AXCE.make = function (id, json) {
        var o = {}, k;
        try { o = JSON.parse(json || "{}"); } catch (e) { }
        for (k in o) { if (o.hasOwnProperty(k)) { o[k] = flag(k, o[k]); } }
        AXCE.inst[id] = new Ed(id, o);
        return true;
    };
    AXCE.get = function (id) { return AXCE.inst[id]; };
    /* a page or a tab has just been shown: the editors now in view catch up
       before it is painted (see P.shownNow) */
    (window.axShownFns = window.axShownFns || []).push(function () {
        var id, ed;
        for (id in AXCE.inst) {
            ed = AXCE.inst[id];
            if (ed && ed.root && ed.root.offsetWidth) { try { ed.shownNow(); } catch (e) { } }
        }
    });
    if (!window.axShown) {
        window.axShown = function () {
            var f = window.axShownFns || [], i;
            for (i = 0; i < f.length; i++) { try { f[i](); } catch (e) { } }
        };
    }
    AXCE.recv = function (id, json) {
        var ed = AXCE.inst[id];
        if (ed) { try { ed.recv(JSON.parse(json)); } catch (e) { } }
    };
    /* AXCE.call(id, name, argsJson) -> a string for AutoHotkey */
    AXCE.call = function (id, name, json) {
        var ed = AXCE.inst[id], a = [], r, t, o;
        if (!ed) { return ""; }
        try { a = JSON.parse(json || "[]"); } catch (e) { }
        switch (name) {
        case "value": ed.sync(); return ed.value();
        case "load": ed.load(a[0]); ed.sent = null; ed.changed(true); return "";
        case "touch": ed.sent = null; ed.changed(true); return "";
        case "flush": ed.sync(); ed.settle(); ed.sendChange(); return "";
        case "set":
            ed.flush();
            t = String(a[0]).replace(/\r\n/g, "\n").replace(/\r/g, "\n");
            if (ed.setAll(t)) {
                o = ed.lastC;
                ed.setSel(Math.min(o.aLine, ed.lines.length - 1), o.aCol, Math.min(o.line, ed.lines.length - 1), o.col);
                ed.remember();
                ed.after(true);
                ed.settle();
                ed.changed(true);
            }
            return "";
        case "insert": ed.insert(String(a[0])); return "";
        case "append":
            ed.sync();
            t = String(a[0]).replace(/\r\n/g, "\n").replace(/\r/g, "\n");
            var last = ed.lines.length - 1, parts = t.split("\n");
            parts[0] = ed.lines[last] + parts[0];
            ed.splice(last, last + 1, parts);
            if (a[1] !== 0 && a[1] !== false) { ed.scroll.scrollTop = ed.scroll.scrollHeight; }
            ed.after(true);
            return "";
        case "selected": ed.selNow(); r = ed.selOffs(); return ed.value().substring(r.a, r.b);
        case "select":
            var p = ed.lcAt(a[0]), q = ed.lcAt(a[1] == null ? a[0] : a[1]);
            ed.setSel(p.line, p.col, q.line, q.col);
            ed.revealCaret(); ed.caretMoved();
            return "";
        case "caret":
            o = ed.selNow();
            r = ed.selOffs();
            return JSON.stringify({ a: r.a, b: r.b, line: o.line + 1, col: o.col + 1 });
        case "goto": ed.goLine(a[0], a[1]); return "";
        case "option": ed.setOption(a[0], a[1]); return "";
        case "fold": ed.foldAll(!!a[0]); return "";
        case "undo": ed.undo(); return "";
        case "redo": ed.redo(); return "";
        case "find": ed.openFind(!!a[1], a[0] || ""); return "";
        case "replaceall":
            o = String(a[2] || "");
            ed.fo = { cs: o.indexOf("c") >= 0, ww: o.indexOf("w") >= 0, re: o.indexOf("r") >= 0 };
            try { return String(ed.replaceAllOf(String(a[0]), String(a[1] == null ? "" : a[1]))); } catch (e2) { return "-1"; }
        case "words": ed.sets.user = { items: ed.norm(a[0]), lang: "" }; ed.sess = null; return "";
        case "wordset": ed.sets[String(a[0])] = { items: ed.norm(a[1]), lang: a[2] || "" }; ed.sess = null; return "";
        case "snippets": ed.snips = a[0] || []; return "";
        case "marks": ed.setMarks(a[0] || []); return "";
        case "lang": AXCE.langs[a[0]] = AXCE.fromDef(a[1]); return "";
        case "focus": ed.focus(); return "";
        case "symbols": return JSON.stringify(AXCE.symbols(ed.value(), ed.o.lang));
        }
        return "";
    };
    /* a language given from AutoHotkey: word lists come as strings */
    AXCE.fromDef = function (d) {
        var L = {}, k;
        for (k in d) { if (d.hasOwnProperty(k)) { L[k] = d[k]; } }
        if (typeof L.kw === "string") { L.kw = words(L.kw); }
        if (typeof L.bi === "string") { L.bi = words(L.bi); }
        if (typeof L.types === "string") { L.types = words(L.types); }
        if (typeof L.more === "string") { L.more = words(L.more); }
        if (L.block && !(L.block instanceof Array)) { L.block = null; }
        return L;
    };
    /* the outline of a text: what is defined where (detail: its parameters) */
    AXCE.symbols = function (t, lang) {
        var out = [], lines = String(t).split("\n"), i, m, s, inBlock = false;
        for (i = 0; i < lines.length; i++) {
            s = lines[i];
            if (lang === "md") { if (/^\s*```/.test(s)) { inBlock = !inBlock; continue; } if (!inBlock && (m = /^(#{1,6})\s+(.*)$/.exec(s))) { out.push({ name: m[2], kind: "heading", line: i + 1, level: m[1].length }); } continue; }
            if (lang === "ini") { if ((m = /^\s*\[([^\]]+)\]/.exec(s))) { out.push({ name: m[1], kind: "section", line: i + 1 }); } continue; }
            if (lang === "css") { if ((m = /^\s*([^\s{][^{]*?)\s*\{/.exec(s))) { out.push({ name: m[1], kind: "class", line: i + 1 }); } continue; }
            if (lang === "html" || lang === "xml") { if ((m = /<(h[1-6]|section|header|footer|main|nav|form|table)\b[^>]*?(?:id="([^"]+)")?[^>]*>/i.exec(s))) { out.push({ name: m[2] ? m[1] + "#" + m[2] : m[1], kind: "prop", line: i + 1 }); } continue; }
            if (lang === "sql") { if ((m = /^\s*create\s+(?:table|view|index|procedure|function)\s+([\w.]+)/i.exec(s))) { out.push({ name: m[1], kind: "class", line: i + 1 }); } continue; }
            if ((m = /^\s*class\s+([A-Za-z_]\w*)/i.exec(s))) { out.push({ name: m[1], kind: "class", line: i + 1 }); continue; }
            if (lang === "js") {
                if ((m = /function\s+([A-Za-z_$][\w$]*)\s*(\([^)]*\))/.exec(s))) { out.push({ name: m[1], kind: "fn", line: i + 1, detail: m[2] }); continue; }
                if ((m = /^\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(\([^)]*\))\s*=>/.exec(s))) { out.push({ name: m[1], kind: "fn", line: i + 1, detail: m[2] }); continue; }
                if ((m = /^\s+(?:async\s+)?([A-Za-z_$][\w$]*)\s*(\([^)]*\))\s*\{/.exec(s)) && !/^(if|for|while|switch|catch|function)$/.test(m[1])) { out.push({ name: m[1], kind: "method", line: i + 1, detail: m[2] }); continue; }
                continue;
            }
            if (lang === "py") { if ((m = /^(\s*)(?:async\s+)?def\s+([A-Za-z_]\w*)\s*(\([^)]*\))/.exec(s))) { out.push({ name: m[2], kind: m[1].length ? "method" : "fn", line: i + 1, detail: m[3] }); } continue; }
            if (lang === "ps1") { if ((m = /^\s*function\s+([\w\-]+)/i.exec(s))) { out.push({ name: m[1], kind: "fn", line: i + 1 }); } continue; }
            if (lang === "ahk" || !lang) {
                if ((m = /^(\s*)(static\s+)?([A-Za-z_]\w*)\s*(\([^)]*\))\s*(\{|=>)/.exec(s)) && !/^(if|while|for|switch|loop|return|catch)$/i.test(m[3])) {
                    out.push({ name: m[3], kind: m[1].length ? "method" : "fn", line: i + 1, detail: m[4] });
                } else if ((m = /^(\s*)(static\s+)?([A-Za-z_]\w*)\s*(\([^)]*\))\s*$/.exec(s)) && i + 1 < lines.length && /^\s*\{/.test(lines[i + 1]) && !/^(if|while|for|switch|loop|return|catch)$/i.test(m[3])) {
                    out.push({ name: m[3], kind: m[1].length ? "method" : "fn", line: i + 1, detail: m[4] });
                } else if ((m = /^\s*([^\s:;"'][^:;"']*?)::/.exec(s))) {
                    out.push({ name: m[1], kind: "hotkey", line: i + 1 });
                }
            }
        }
        return out;
    };
}());
