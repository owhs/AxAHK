#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-Let U_AxLib = %A_ScriptDir%\..\lib     ; compile: embed themes/icons (single-file exe)
#Include ..\lib\AxGui.ahk
#Include ..\lib\AxAssets.ahk

; ─────────────────────────────────────────────────────────────────────────────
;  Calculator.ahk — Windows 11 Calculator (Standard) clone built with AxGui
;  Everything is AutoHotkey: layout, styling (Css option) and the engine.
;  Keyboard: digits, + - * / .  Enter =  Backspace, Esc (C), Delete (CE),
;            F9 (+/-), R (1/x), Q (x²), @ (√).
; ─────────────────────────────────────────────────────────────────────────────


; ── Styles ──────────────────────────────────────────────────────────────────

Css := "
(
    /* Shell & content — fill the window, key rows grow with it (like real app) */
    #shell   { height: calc(100% - 32px); }

    /* Explicit height: IE11 resolves 100% inside a flex item against the body */
    #content {
        display:        flex;
        flex-direction: column;
        height:         calc(100vh - 32px);
        margin:         0;
        padding:        0 1px 1px 1px;
        overflow:       hidden;
    }

    .ax-line              { flex: none; margin: 0; }
    .ax-line:nth-child(-n+4) { margin-bottom: 4px; }
    .ax-line > *          { margin-right: 0; }

    /* IE11 ignores a flex shorthand whose basis has no unit: always write 0px */
    /* Basis = natural size, so only the spare height is shared 1:2            */
    .ax-line:nth-child(3)   { flex: 1 1 76px; min-height: 76px; }                    /* display  */
    .ax-line:nth-child(n+5) { flex: 2 1 52px; min-height: 52px; align-items: stretch; } /* key rows */
    .ax-line > .fill        { flex: 1 1 0px; }

    .calc-head {
        display:     flex;
        align-items: center;
        height:      44px;
        padding:     0 4px;
    }

    .calc-head .ico {
        font-size:   16px;
        width:       36px;
        height:      36px;
        line-height: 36px;
        text-align:  center;
        border-radius: 4px;
    }

    .calc-head .ico:hover { background: rgba(255, 255, 255, .0605); }
    .calc-head .ttl       { font-size: 20px; font-weight: 600; margin: 0 8px 0 6px; }

    .expr {
        height:      24px;
        line-height: 24px;
        text-align:  right;
        padding:     0 12px;
        font-size:   14px;
        color:       rgba(255, 255, 255, .6);
        white-space: nowrap;
        overflow:    hidden;
    }

    .disp {
        display:         flex;
        align-items:     flex-end;
        justify-content: flex-end;
        height:          100%;
        padding:         0 12px 8px 12px;
        font-size:       46px;
        line-height:     1.15;
        font-weight:     600;
        white-space:     nowrap;
        overflow:        hidden;
    }

    .disp.small { font-size: 30px; }
    .disp.tiny  { font-size: 20px; }

    .mem {
        height:     28px;
        line-height: 26px;
        font-size:  12px;
        padding:    0;
        min-width:  0;
        background: transparent;
        border-color: transparent;
        color:      rgba(255, 255, 255, .55);
    }

    .mem:hover          { background: rgba(255, 255, 255, .0605); color: #fff; }
    .mem.disabled       { color: rgba(255, 255, 255, .3); }

    .calc {
        display:         inline-flex;
        align-items:     center;
        justify-content: center;
        height:          auto;
        min-height:      52px;
        line-height:     normal;
        min-width:       0;
        padding:         0;
        font-size:       18px;
    }

    /* Gutters live inside each key: a window-coloured border nothing overrides  */
    .ax-line > .calc,
    .ax-line > .mem {
        margin:          0 !important;
        border:          3px solid #202020 !important;
        border-radius:   9px;
        background-clip: padding-box !important;
    }

    .ax-line > .mem { border-width: 2px 3px !important; }

    body.theme-light .ax-line > .calc,
    body.theme-light .ax-line > .mem { border-color: #f3f3f3 !important; }

    .calc.num          { background: #3b3b3b; font-weight: 600; }
    .calc.num:hover    { background: #323232; }
    .calc.op           { background: #323232; font-size: 16px; }
    .calc.op:hover     { background: #3b3b3b; }
    .calc.fn           { font-size: 15px; }
    .calc.eq           { font-size: 22px; }

    body.theme-light .calc.num { background: #fbfbfb; }
    body.theme-light .calc.op  { background: #e9e9e9; }
)"

; ── Window ──────────────────────────────────────────────────────────────────

g := AxGui({
    Title:        "Calculator",
    Width:        320,
    Height:       640,
    MinWidth:     320,
    MinHeight:    520,
    BackColor:    "202020",
    Theme:        "dark",
    Icon:         "E8EF",
    Css:          Css,
    RoundCorners: true
})


; ── Header ──────────────────────────────────────────────────────────────────

g.AddHtml("Fill",
    '<div class="calc-head">'
    . '<span class="ico" id="hbMenu">&#xE700;</span>'
    . '<span class="ttl">Standard</span>'
    . '<span class="ico" id="hbTop" data-tip="Keep on top">&#xE840;</span>'
    . '<span class="spacer"></span>'
    . '<span class="ico" id="hbHist" data-tip="History">&#xE81C;</span>'
    . '</div>'
)

expr := g.AddHtml("vexpr Fill Class=expr", "")
disp := g.AddHtml("vdisp Fill Class=disp", "0")


; ── Memory row ──────────────────────────────────────────────────────────────

MemIds := ["btnMC", "btnMR", "btnMadd", "btnMsub", "btnMS"]

for i, m in ["MC", "MR", "M+", "M−", "MS"] {
    g.AddButton(
        (i > 1 ? "x+4 " : "") . "v" . MemIds[i] . " Fill Class=mem", m
    ).OnClick(Mem.Bind(m))
}


; ── Keypad ──────────────────────────────────────────────────────────────────

Rows := [
    ["%",   "CE", "C",   "⌫"],
    ["¹⁄ₓ", "x²", "²√x", "÷"],
    ["7",   "8",  "9",   "×"],
    ["4",   "5",  "6",   "−"],
    ["1",   "2",  "3",   "+"],
    ["+/−", "0",  ".",   "="]
]

for r in Rows {
    for i, k in r {
        cls := (IsDigit(k) || k = ".")                  ? "num"
            : (k = "=")                                 ? "eq accent"
            : InStr("%CE C ⌫ ¹⁄ₓ x² ²√x +/−", k)         ? "op fn"
            :                                             "op"

        g.AddButton(
            (i > 1 ? "x+4 " : "") . "Fill Class=`"calc " . cls . "`"", k
        ).OnClick(Press.Bind(k))
    }
}


; ── Window chrome handlers ──────────────────────────────────────────────────

; Wildcard keyboard hook — fires for any key when no element-specific hook matched.
g.On("keydown", "*", KeyDown)

g.On("click", "hbTop", (*) => ToggleTop())

ToggleTop() {
    global AOT

    AOT := !AOT
    g.AlwaysOnTop(AOT)
    g.Toast(AOT ? "Kept on top" : "Normal", 1200)
}

g.On("click", "hbMenu", (*) => g.Toast("Only Standard mode in this demo", 1500))
g.On("click", "hbHist", (*) => g.Alert(History = "" ? "No history yet" : History, "History"))

AOT := false

g.OnReady((*) => (
    g.Ctl("btnMC").Enabled := false,
    g.Ctl("btnMR").Enabled := false
))

g.Show()


; ══════════════════════════════════════════════════════════════════════════════
;  Engine
; ══════════════════════════════════════════════════════════════════════════════

Cur        := "0"
Acc        := ""
Op         := ""
Fresh      := true
LastB      := ""
LastOp     := ""
MemVal     := ""
History    := ""
ErrorState := false


Press(k, *) {
    global Cur, Acc, Op, Fresh, LastB, LastOp, ErrorState, History

    if (ErrorState && !(k = "C" || k = "CE")) {
        return
    }

    switch k {

        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            if (Fresh) {
                Cur   := k
                Fresh := false
            } else if (Cur = "0") {
                Cur := k
            } else if (StrLen(StrReplace(Cur, "-", "")) < 16) {
                Cur .= k
            }

        case ".":
            if (Fresh) {
                Cur   := "0."
                Fresh := false
            } else if (!InStr(Cur, ".")) {
                Cur .= "."
            }

        case "+", "−", "×", "÷":
            if (Op != "" && !Fresh) {
                Acc := Calc(Acc, Op, Cur)
                Cur := Acc
            } else if (Acc = "" || Fresh && Op = "") {
                Acc := Cur
            }
            Op    := k
            Fresh := true
            SetExpr(Fmt(Acc) . " " . k)

        case "=":
            if (Op != "") {
                if (Fresh && LastOp = "") {             ; "5 + =" → uses Cur as operand (matches Windows)
                    LastB := Cur
                }
                b      := Fresh ? (LastOp != "" ? LastB : Cur) : Cur
                LastB  := b
                LastOp := Op
                SetExpr(Fmt(Acc) . " " . Op . " " . Fmt(b) . " =")
                res := Calc(Acc, Op, b)
                AddHistory(Fmt(Acc) . " " . Op . " " . Fmt(b) . " = " . Fmt(res))
                Cur := res
                Acc := res
                Op  := ""
            } else if (LastOp != "") {                  ; repeated "="
                SetExpr(Fmt(Cur) . " " . LastOp . " " . Fmt(LastB) . " =")
                Cur := Calc(Cur, LastOp, LastB)
            } else {
                SetExpr(Fmt(Cur) . " =")
            }
            Fresh := true

        case "C":
            Cur        := "0"
            Acc        := ""
            Op         := ""
            Fresh      := true
            LastOp     := ""
            ErrorState := false
            SetExpr("")

        case "CE":
            Cur        := "0"
            Fresh      := true
            ErrorState := false

        case "⌫":
            if (!Fresh) {
                Cur := SubStr(Cur, 1, -1)
                if (Cur = "" || Cur = "-" || Cur = "-0") {
                    Cur   := "0"
                    Fresh := true
                }
            }

        case "+/−":
            if (Cur != "0") {
                Cur := (SubStr(Cur, 1, 1) = "-") ? SubStr(Cur, 2) : "-" . Cur
            }

        case "%":
            Cur   := (Op != "" && Acc != "") ? Num(Acc) * Num(Cur) / 100 : 0
            Cur   := Clean(Cur)
            Fresh := true

        case "¹⁄ₓ":
            SetExpr("1/(" . Fmt(Cur) . ")")
            if (Num(Cur) = 0) {
                return Fail("Cannot divide by zero")
            }
            Cur   := Clean(1 / Num(Cur))
            Fresh := true

        case "x²":
            SetExpr("sqr(" . Fmt(Cur) . ")")
            Cur   := Clean(Num(Cur) ** 2)
            Fresh := true

        case "²√x":
            SetExpr("√(" . Fmt(Cur) . ")")
            if (Num(Cur) < 0) {
                return Fail("Invalid input")
            }
            Cur   := Clean(Sqrt(Num(Cur)))
            Fresh := true
    }

    if (!ErrorState) {                                  ; Fail() already drew the error text
        Show()
    }
}


Calc(a, op, b) {
    global ErrorState

    a := Num(a)
    b := Num(b)

    switch op {
        case "+": r := a + b
        case "−": r := a - b
        case "×": r := a * b
        case "÷":
            if (b = 0) {
                Fail(a = 0 ? "Result is undefined" : "Cannot divide by zero")
                return "0"
            }
            r := a / b
    }

    return Clean(r)
}

Num(s) => (s = "" || s = "-" || s = "." || !IsNumber(s)) ? 0 : Number(s)

; Drop float noise: 0.1 + 0.2 → 0.3, 1e21 stays readable.
Clean(v) {
    if (v = Integer(v) && Abs(v) < 1e16) {
        return String(Integer(v))
    }
    s := Format("{:.14g}", v)
    if (InStr(s, "e")) {
        return s
    }
    if (InStr(s, ".")) {
        s := RTrim(RTrim(s, "0"), ".")
    }
    return s
}

; Thousands separators for the display, as typed while entering.
Fmt(s) {
    if (s = "" || !IsNumber(s)) {
        return s
    }

    neg := SubStr(s, 1, 1) = "-"
    if (neg) {
        s := SubStr(s, 2)
    }

    p    := InStr(s, ".")
    intp := p ? SubStr(s, 1, p - 1) : s
    frac := p ? SubStr(s, p)        : ""

    if (InStr(s, "e")) {
        return (neg ? "-" : "") . s
    }

    out := ""
    loop StrLen(intp) {
        c   := SubStr(intp, StrLen(intp) - A_Index + 1, 1)
        out := c . out
        if (Mod(A_Index, 3) = 0 && A_Index < StrLen(intp)) {
            out := "," . out
        }
    }

    return (neg ? "-" : "") . out . frac
}

Show() {
    global Cur

    t := Fmt(Cur)
    disp.El.className := "disp fill" . (StrLen(t) > 18 ? " tiny" : StrLen(t) > 11 ? " small" : "")
    disp.Text         := t
}

SetExpr(t) => expr.Text := t

Fail(msg) {
    global ErrorState, Cur, Fresh

    ErrorState          := true
    Fresh               := true
    Cur                 := "0"
    disp.El.className   := "disp fill small"
    disp.Text           := msg

    return ""
}

AddHistory(line) {
    global History

    History := line . "`n" . History
    if (StrLen(History) > 1500) {
        History := SubStr(History, 1, 1500)
    }
}


; ── Memory ──────────────────────────────────────────────────────────────────

Mem(which, *) {
    global MemVal, Cur, Fresh

    switch which {
        case "MS": MemVal := Cur, Fresh := true
        case "MC": MemVal := ""
        case "MR":
            if (MemVal != "") {
                Cur   := MemVal
                Fresh := true
                Show()
            }
        case "M+": MemVal := Clean(Num(MemVal) + Num(Cur)), Fresh := true
        case "M−": MemVal := Clean(Num(MemVal) - Num(Cur)), Fresh := true
    }

    has := (MemVal != "")

    for id in ["btnMC", "btnMR"] {
        g.Ctl(id).Enabled := has
    }

    g.Toast(has ? "Memory: " . Fmt(MemVal) : "Memory cleared", 1200)
}


; ── Keyboard ────────────────────────────────────────────────────────────────

KeyDown(el, ev) {
    static keymap := Map(
        13,  "=",   8,   "⌫",   27, "C",    46,  "CE",
        106, "×",   107, "+",   109, "−",  111, "÷",
        110, ".",   190, ".",   120, "+/−", 82, "¹⁄ₓ",
        81,  "x²"
    )

    k     := ev.keyCode
    shift := ev.shiftKey

    if (k >= 48 && k <= 57) {
        if (shift) {                                    ; Shift+8 = *, Shift+= handled below, Shift+5 = %
            if (k = 56) {
                Press("×")
            } else if (k = 53) {
                Press("%")
            } else if (k = 50) {
                Press("²√x")                            ; Shift+2 = @
            } else {
                return
            }
        } else {
            Press(Chr(k))
        }

    } else if (k >= 96 && k <= 105) {
        Press(Chr(k - 48))

    } else if (k = 187) {                               ; "=" key, "+" with shift
        Press(shift ? "+" : "=")

    } else if (k = 189) {
        Press("−")

    } else if (k = 191) {
        Press("÷")

    } else if (keymap.Has(k)) {
        Press(keymap[k])

    } else {
        return
    }

    ev.returnValue := false
}
