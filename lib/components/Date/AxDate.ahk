#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\AxRich.ahk
; single-file exe: embed this component's stylesheet (harmless uncompiled).
; The main script must set U_AxLib, exactly as lib\AxAssets.ahk documents.
;@Ahk2Exe-AddResource %U_AxLib%\components\Date\AxDate.css, AX_COMPONENTS_DATE_AXDATE_CSS

; =============================================================================
;  AxDate -- everything about dates, as one component that takes many forms.
;
;    g.AddDate("vDue")                          a date box; its calendar is a popover
;    g.AddDate("vAt Mode=datetime")             a date and a time
;    g.AddDate("vStay Mode=range")              a range: two months, presets, start and end
;    g.AddDate("vAlarm Mode=time Step=15")      a time
;    g.AddDate("vPeriod Mode=month")            a month
;    g.AddDate("vDob Plain")                    just the box: type it, arrows step it
;    g.AddCalendar("vDay Mode=range Months=2")  the calendar itself, on the page
;    v := g.PickDate({Mode: "range"})           a dialog, when a window is wanted
;
;  Shortcuts: g.AddDateRange(...) is Mode=range, g.AddTime(...) is Mode=time,
;  and the Inline flag on AddDate is AddCalendar.
;
;  ------------------------------------------------------------------ values
;  Values are ISO text, so they sort, compare and store as they are:
;      date      2026-09-11            month   2026-09
;      datetime  2026-09-11 14:30      time    14:30
;      range     2026-09-01/2026-09-12        (an ISO interval; either side may be blank)
;  ctl.Value reads and writes that. ctl.Component.Start / .End / .Stamp hand
;  back AutoHotkey timestamps for FormatTime and DateDiff, and .Days counts a
;  range. Setting a value also takes what someone would type ("today", "+3").
;
;  ------------------------------------------------------------------ typing
;  The box reads what people write: 12/9/2026, 12.9.26, 2026-09-12, 12 Sep,
;  sep 12 2026, today, tomorrow, yesterday, fri, next mon, last fri, +3, -2w,
;  +1m, 3pm, 14:30, "1 - 12 sep" for a range. Up and Down step it by a day (a
;  step of minutes for a time); Alt+Down or F4 opens the calendar.
;
;  In the calendar: arrows move a day or a week, Page Up / Page Down a month
;  (with Shift, a year), Home and End the week, Enter or Space picks, T is
;  today, Delete clears. The month's name opens the months, and the year's
;  name the years.
;
;  ----------------------------------------------------------------- options
;    Mode       date | datetime | time | range | month   (or the flag Range, Time...)
;    Format     how the box shows it -- FormatTime's patterns ("d MMM yyyy")
;    Order      dmy (default) | mdy | ymd -- how 1/2/2026 is read
;    Min, Max   the first and last day that can be picked (ISO, or "today", "+30")
;    Months     1 or 2 side by side (a range shows 2)
;    FirstDay   mon (default) | sun
;    Step       minutes between the times offered (5)
;    Placeholder                         Weeks      week numbers down the side
;    NoPresets  a range without Today, Last 7 days...   Hour12   9:30 PM
;    Confirm    a range waits for Apply     Plain    no calendar at all
;    NoClear    no clear button
; =============================================================================
class AxDate {
    static _reg := AxDate._Install()
    static _Install() {
        rec := AxRich.Register("Date", "components\Date\AxDate.css", (*) => (
            AxRich.AddMethod("AddDate", (c, o := "", v := "") => AxDate._AddBox(c, o, v, "")),
            AxRich.AddMethod("AddDateRange", (c, o := "", v := "") => AxDate._AddBox(c, o, v, "range")),
            AxRich.AddMethod("AddTime", (c, o := "", v := "") => AxDate._AddBox(c, o, v, "time")),
            AxRich.AddMethod("AddCalendar", (c, o := "", v := "") => AxDate._AddCal(c, o, v)),
            AxRich.WindowMethod("PickDate", (w, o := "") => AxDate.Show(AxDate._Owned(w, o))),
            AxWindow.RegisterValue("datebox",
                (w, el) => AxWindow._Attr(el, "data-value"),
                (w, el, v) => AxDate._SetVia(w, el, v)),
            AxWindow.RegisterValue("calendar",
                (w, el) => AxWindow._Attr(el, "data-value"),
                (w, el, v) => AxDate._SetVia(w, el, v))), true)
        return rec
    }
    static _SetVia(win, el, v) {
        c := AxRich.At(win, el.id)
        if IsObject(c)
            c.Value := v
        else
            el.setAttribute("data-value", v)
    }
    static _Unbad(w, id) {
        try AxWindow._SetClass(w.El(id), "bad", false)
    }
    static _Owned(win, opts) {
        o := {Owner: AxRich.Owner(win)}
        if IsObject(opts)
            for k, v in opts.OwnProps()
                o.%k% := v
        return o
    }

    ; ============================================================ the maths
    ; Timestamps throughout, as AutoHotkey writes them: yyyyMMddHHmmss.
    static Today() => FormatTime(, "yyyyMMdd") "000000"
    static Now() => FormatTime(, "yyyyMMddHHmm") "00"
    static Make(y, m, d, hh := 0, mi := 0) => Format("{:04}{:02}{:02}{:02}{:02}00", y, m, d, hh, mi)
    static YearOf(ts) => Integer(SubStr(ts, 1, 4))
    static MonthOf(ts) => Integer(SubStr(ts, 5, 2))
    static DayOf(ts) => Integer(SubStr(ts, 7, 2))
    static HourOf(ts) => (StrLen(ts) >= 10) ? Integer(SubStr(ts, 9, 2)) : 0
    static MinOf(ts) => (StrLen(ts) >= 12) ? Integer(SubStr(ts, 11, 2)) : 0
    static Day(ts) => SubStr(ts, 1, 8)                    ; the day alone, yyyyMMdd
    static WithTime(ts, hh, mi) => SubStr(ts, 1, 8) Format("{:02}{:02}00", hh, mi)
    static DaysIn(y, m) {
        if (m = 2)
            return (Mod(y, 4) = 0 && (Mod(y, 100) != 0 || Mod(y, 400) = 0)) ? 29 : 28
        return (m = 4 || m = 6 || m = 9 || m = 11) ? 30 : 31
    }
    static Valid(y, m, d) => (y >= 1601 && y <= 9999 && m >= 1 && m <= 12 && d >= 1 && d <= AxDate.DaysIn(y, m))
    static AddDays(ts, n) => DateAdd(ts, n, "Days")
    static AddMonths(ts, n) {
        m0 := AxDate.MonthOf(ts) - 1 + n
        y := AxDate.YearOf(ts) + Floor(m0 / 12)
        m := Mod(Mod(m0, 12) + 12, 12) + 1
        return AxDate.Make(y, m, Min(AxDate.DayOf(ts), AxDate.DaysIn(y, m)), AxDate.HourOf(ts), AxDate.MinOf(ts))
    }
    static FirstOfMonth(ts) => SubStr(ts, 1, 6) "01000000"
    static Dow(ts) => Integer(FormatTime(ts, "WDay")) - 1          ; 0 is Sunday
    static Week(ts) => Integer(SubStr(FormatTime(ts, "YWeek"), 5))  ; the ISO week
    static Diff(a, b) => DateDiff(a, b, "Days")
    static MonthNames := ["January", "February", "March", "April", "May", "June", "July",
                          "August", "September", "October", "November", "December"]
    static DayNames := ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    ; ------------------------------------------------------------ ISO text
    static Iso(ts, mode := "date") {
        if (ts = "")
            return ""
        switch mode {
        case "time":     return FormatTime(ts, "HH:mm")
        case "datetime": return FormatTime(ts, "yyyy-MM-dd HH:mm")
        case "month":    return FormatTime(ts, "yyyy-MM")
        }
        return FormatTime(ts, "yyyy-MM-dd")
    }
    static FromIso(s) {
        s := Trim(String(s))
        if RegExMatch(s, "i)^(\d{4})-(\d{1,2})(?:-(\d{1,2}))?(?:[ T](\d{1,2}):(\d{2})(?::\d{2})?)?$", &m) {
            y := Integer(m[1]), mo := Integer(m[2]), d := (m[3] = "") ? 1 : Integer(m[3])
            hh := (m[4] = "") ? 0 : Integer(m[4]), mi := (m[5] = "") ? 0 : Integer(m[5])
            return (AxDate.Valid(y, mo, d) && hh < 24 && mi < 60) ? AxDate.Make(y, mo, d, hh, mi) : ""
        }
        if RegExMatch(s, "^(\d{1,2}):(\d{2})$", &m)
            return (Integer(m[1]) < 24 && Integer(m[2]) < 60) ? AxDate.WithTime(AxDate.Today(), m[1], m[2]) : ""
        if RegExMatch(s, "^(\d{4})(\d{2})(\d{2})(\d{6})?$", &m)        ; an AutoHotkey timestamp
            return AxDate.Valid(Integer(m[1]), Integer(m[2]), Integer(m[3])) ? (m[4] = "" ? s "000000" : s) : ""
        return ""
    }
    ; a range as [start, end], either of which may be ""
    static RangeOf(v) {
        v := Trim(String(v))
        if (v = "")
            return ["", ""]
        p := InStr(v, "/")
        if !p
            return [AxDate.FromIso(v), ""]
        return [AxDate.FromIso(SubStr(v, 1, p - 1)), AxDate.FromIso(SubStr(v, p + 1))]
    }
    static RangeIso(a, b) => (a = "" && b = "") ? "" : AxDate.Iso(a) "/" AxDate.Iso(b)

    ; ---------------------------------------------------------- what people type
    ; Parse(text, mode, order) -> a timestamp, or "" when it cannot be read.
    static Parse(text, mode := "date", order := "dmy") {
        t := StrLower(Trim(String(text)))
        if (t = "")
            return ""
        if ((ts := AxDate.FromIso(t)) != "")
            return (mode = "time") ? AxDate.WithTime(AxDate.Today(), AxDate.HourOf(ts), AxDate.MinOf(ts)) : ts
        if (t = "now")
            return AxDate.Now()
        ; a time anywhere in it: 3pm, 3:30 pm, 14:30
        hh := -1, mi := 0
        if RegExMatch(t, "(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a|p)\b", &tm) || RegExMatch(t, "(\d{1,2}):(\d{2})", &tm) {
            hh := Integer(tm[1]), mi := (tm[2] = "") ? 0 : Integer(tm[2])
            if (tm.Count >= 3 && tm[3] != "") {
                if (hh > 12)
                    return ""
                hh := Mod(hh, 12) + (SubStr(tm[3], 1, 1) = "p" ? 12 : 0)
            }
            if (hh > 23 || mi > 59)
                return ""
            t := Trim(StrReplace(t, tm[0], " "))
        }
        if (mode = "time") {
            if (hh < 0) {
                if RegExMatch(t, "^(\d{1,2})(\d{2})$", &m4)
                    hh := Integer(m4[1]), mi := Integer(m4[2])
                else if RegExMatch(t, "^\d{1,2}$")
                    hh := Integer(t), mi := 0
                else
                    return ""
                if (hh > 23 || mi > 59)
                    return ""
            }
            return AxDate.WithTime(AxDate.Today(), hh, mi)
        }
        day := (t = "") ? AxDate.Today() : AxDate._ParseDay(t, order, mode)
        if (day = "")
            return ""
        if (hh < 0)
            return day
        return AxDate.WithTime(day, hh, mi)
    }
    static _ParseDay(t, order, mode) {
        today := AxDate.Today()
        t := Trim(RegExReplace(t, "[,\s]+", " "))
        switch t {
        case "today", "t", "tod":                     return today
        case "tomorrow", "tom", "tmrw", "tmr":        return AxDate.AddDays(today, 1)
        case "yesterday", "yest", "yday", "yda":      return AxDate.AddDays(today, -1)
        }
        if RegExMatch(t, "^([+-])\s*(\d+)\s*(d|days?|w|wks?|weeks?|m|mos?|months?|y|yrs?|years?)?$", &m) {
            n := Integer(m[2]) * (m[1] = "-" ? -1 : 1), u := SubStr(m[3], 1, 1)
            return (u = "w") ? AxDate.AddDays(today, 7 * n) : (u = "m") ? AxDate.AddMonths(today, n)
                 : (u = "y") ? AxDate.AddMonths(today, 12 * n) : AxDate.AddDays(today, n)
        }
        ; a weekday: the coming one, "next" the one after today, "last" the one before
        if RegExMatch(t, "^(next |last |this )?(sun|mon|tue|wed|thu|fri|sat)[a-z]*$", &m) {
            want := 0
            for i, w in ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
                if (w = m[2])
                    want := i - 1
            cur := AxDate.Dow(today)
            if (Trim(m[1]) = "last") {
                back := Mod(cur - want + 7, 7)
                return AxDate.AddDays(today, -(back = 0 ? 7 : back))
            }
            ahead := Mod(want - cur + 7, 7)
            if (Trim(m[1]) = "next" && ahead = 0)
                ahead := 7
            return AxDate.AddDays(today, ahead)
        }
        ; a month by name
        mo := 0
        if RegExMatch(t, "(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?", &mm) {
            for i, nm in AxDate.MonthNames
                if (StrLower(SubStr(nm, 1, 3)) = mm[1])
                    mo := i
            t := Trim(StrReplace(t, mm[0], " "))
        }
        nums := []
        pos := 1
        while RegExMatch(t, "\d+", &nm, pos)
            nums.Push(nm[0]), pos := nm.Pos + nm.Len
        y := AxDate.YearOf(today), d := 0
        if mo {
            for x in nums {
                if (StrLen(x) = 4)
                    y := Integer(x)
                else if (!d && Integer(x) >= 1 && Integer(x) <= 31)
                    d := Integer(x)
                else if (d && StrLen(x) <= 2)
                    y := AxDate._Year2(x)
            }
            if !d
                d := 1
        } else {
            if (nums.Length < 2 || nums.Length > 3)
                return ""
            if (StrLen(nums[1]) = 4) {                            ; year first
                y := Integer(nums[1]), mo := Integer(nums[2]), d := (nums.Length > 2) ? Integer(nums[3]) : 1
            } else if (nums.Length = 2 && StrLen(nums[2]) = 4) {  ; 9/2026: a month
                mo := Integer(nums[1]), y := Integer(nums[2]), d := 1
            } else {
                a := Integer(nums[1]), b := Integer(nums[2])
                if (order = "mdy")
                    mo := a, d := b
                else
                    mo := b, d := a
                if (mo > 12 && d <= 12)                          ; it can only be the other way
                    tmp := mo, mo := d, d := tmp
                if (nums.Length > 2)
                    y := (StrLen(nums[3]) <= 2) ? AxDate._Year2(nums[3]) : Integer(nums[3])
            }
        }
        return AxDate.Valid(y, mo, d) ? AxDate.Make(y, mo, d) : ""
    }
    static _Year2(x) => (Integer(x) < 70 ? 2000 : 1900) + Integer(x)
    ; "1 sep - 12 sep", "1 - 12 sep", "2026-09-01/2026-09-12" -> [start, end]
    static ParseRange(text, order := "dmy") {
        t := Trim(String(text))
        if (t = "")
            return ["", ""]
        if RegExMatch(t, "^\d{4}-\d{1,2}-\d{1,2}/(\d{4}-\d{1,2}-\d{1,2})?$") {
            r := AxDate.RangeOf(t)
            return (r[2] != "" && AxDate.Day(r[2]) < AxDate.Day(r[1])) ? [r[2], r[1]] : r
        }
        parts := StrSplit(RegExReplace(t, "i)\s*(?:\x{2013}|\x{2014}|\.\.|\bto\b|\buntil\b|\s-\s|^-|-$)\s*", "|"), "|")
        list := []
        for p in parts
            if (Trim(p) != "")
                list.Push(Trim(p))
        if !list.Length
            return ["", ""]
        a := AxDate.Parse(list[1], "date", order)
        b := (list.Length > 1) ? AxDate.Parse(list[list.Length], "date", order) : ""
        ; "1 - 12 sep": the first side borrows the month and year of the second
        if (a = "" && b != "" && RegExMatch(list[1], "^\d{1,2}$") && AxDate.Valid(AxDate.YearOf(b), AxDate.MonthOf(b), Integer(list[1])))
            a := AxDate.Make(AxDate.YearOf(b), AxDate.MonthOf(b), Integer(list[1]))
        if (a = "")
            return ["", ""]
        if (b != "" && AxDate.Day(b) < AxDate.Day(a))
            tmp := a, a := b, b := tmp
        return [a, b]
    }
    ; Min= / Max= as a timestamp: ISO, or anything Parse reads ("today", "+30")
    static Bound(s) => (Trim(String(s)) = "") ? "" : AxDate.Parse(s, "date")
    ; a value as given -- ISO or typed -- into the ISO the component keeps
    static Norm(v, mode, order := "dmy") {
        v := Trim(String(v))
        if (v = "")
            return ""
        if (mode = "range") {
            r := InStr(v, "/") ? AxDate.RangeOf(v) : AxDate.ParseRange(v, order)
            return AxDate.RangeIso(r[1], r[2])
        }
        ts := AxDate.Parse(v, mode, order)
        return AxDate.Iso(ts, mode)
    }

    ; ----------------------------------------------------------------- showing
    static DefaultFormat(mode, h12 := false) {
        tf := h12 ? "h:mm tt" : "HH:mm"
        switch mode {
        case "time":     return tf
        case "datetime": return "d MMM yyyy  " tf
        case "month":    return "MMMM yyyy"
        }
        return "d MMM yyyy"
    }
    static Text(ts, mode := "date", fmt := "", h12 := false) {
        if (ts = "")
            return ""
        return FormatTime(ts, (fmt != "") ? fmt : AxDate.DefaultFormat(mode, h12))
    }
    ; "1 - 12 Sep 2026", "28 Aug - 3 Sep 2026", "30 Dec 2026 - 2 Jan 2027"
    static RangeText(a, b, fmt := "") {
        dash := " " Chr(0x2013) " "
        if (a = "")
            return ""
        if (b = "")
            return AxDate.Text(a, "date", fmt) dash Chr(0x2026)
        if (fmt != "")
            return AxDate.Text(a, "date", fmt) dash AxDate.Text(b, "date", fmt)
        if (AxDate.Day(a) = AxDate.Day(b))
            return FormatTime(a, "d MMM yyyy")
        if (AxDate.YearOf(a) = AxDate.YearOf(b)) {
            if (AxDate.MonthOf(a) = AxDate.MonthOf(b))
                return FormatTime(a, "d") dash FormatTime(b, "d MMM yyyy")
            return FormatTime(a, "d MMM") dash FormatTime(b, "d MMM yyyy")
        }
        return FormatTime(a, "d MMM yyyy") dash FormatTime(b, "d MMM yyyy")
    }
    ; what a box shows for a value it holds
    static ValueText(v, cfg) {
        O := (n, d := "") => (IsObject(cfg) && cfg.HasOwnProp(n)) ? cfg.%n% : d
        mode := O("Mode", "date")
        if (Trim(String(v)) = "")
            return ""
        if (mode = "range") {
            r := AxDate.RangeOf(v)
            return AxDate.RangeText(r[1], r[2], O("Format"))
        }
        return AxDate.Text(AxDate.FromIso(v), mode, O("Format"), O("Hour12", false))
    }

    ; ================================================================ AxGui
    static _Cfg(c, o, value, mode) {
        K := (k, d := "") => c._Kv(o, k, d)
        F := (k) => (o.Flags.Has(k) && o.Flags[k])
        m := (mode != "") ? mode : StrLower(K("mode", ""))
        if (m = "")
            m := F("range") ? "range" : F("datetime") ? "datetime" : F("time") ? "time" : F("month") ? "month" : "date"
        order := StrLower(K("order", "dmy"))
        cfg := {Mode: m, Order: order, Format: K("format"),
                Months: Integer(K("months", m = "range" ? 2 : 1)),
                FirstDay: (StrLower(K("firstday", "mon")) = "sun") ? 0 : 1,
                Weeks: F("weeks"), Presets: !F("nopresets"), Confirm: F("confirm"), Hour12: F("hour12"),
                Step: Integer(K("step", 5)), Min: AxDate.Bound(K("min")), Max: AxDate.Bound(K("max")),
                Placeholder: K("placeholder"), Plain: F("plain"), NoClear: F("noclear")}
        cfg.Value := AxDate.Norm(value != "" ? value : K("value"), m, order)
        return cfg
    }
    static _AddBox(c, opts, value, mode) {
        o := c._Opt(opts, "dt")
        if (o.Flags.Has("inline") && o.Flags["inline"])
            return AxDate._AddCal(c, opts, value, o)
        cfg := AxDate._Cfg(c, o, value, mode)
        if (o.W = "" && !o.Flags.Has("fill"))
            o.W := (cfg.Mode = "range") ? 260 : (cfg.Mode = "datetime") ? 230 : (cfg.Mode = "time") ? 160
                 : (cfg.Mode = "month") ? 210 : 190
        ctl := c._Reg(o, "Date", AxDateBox.Html(o.Id, cfg, c._Common(o, "")))
        c.G.OnReady((w) => AxDateBox(w, o.Id, cfg))
        return ctl
    }
    static _AddCal(c, opts, value, parsed := "") {
        o := IsObject(parsed) ? parsed : c._Opt(opts, "cal")
        cfg := AxDate._Cfg(c, o, value, "")
        cfg.Inline := true
        ctl := c._Reg(o, "Calendar", AxCalendar.HostHtml(o.Id, cfg, c._Common(o, "")))
        c.G.OnReady((w) => AxCalendar(w, o.Id "_cal", cfg, "", o.Id).Wire())
        return ctl
    }

    ; ============================================================== dialog
    ; Show(opts) -> the value, or "" if cancelled.
    static Show(opts := "") => AxDateDialog(opts).ShowModal()
}

; =============================================================================
;  AxCalendar -- the calendar itself: days, months and years, a time, a range
;  with its presets. It lives on a page (AddCalendar) or in the date box's
;  popover, and draws itself again, whole, whenever something changes: a
;  month is forty-two cells, and one innerHTML is cheaper than tracking them.
; =============================================================================
class AxCalendar {
    ; the page element an inline calendar sits in: the value lives on it
    static HostHtml(id, cfg, attrs := "") {
        cal := AxCalendar("", id "_cal", cfg)
        cls := "axcal-host"
        if (attrs != "") {
            n := 0
            a := RegExReplace(attrs, 'S)class="([^"]*)"', 'class="' cls ' $1"', &n)
            if !n
                a .= ' class="' cls '"'
        } else
            a := ' id="' AxWindow._Esc(id) '" class="' cls '"'
        return '<div' a ' data-role="calendar" data-value="' AxWindow._Esc(cal.Value) '">' cal.Html() '</div>'
    }

    __New(win, id, cfg := "", onPick := "", hostId := "") {
        this.W := win, this.Id := id, this.HostId := hostId
        O := (n, d := "") => (IsObject(cfg) && cfg.HasOwnProp(n)) ? cfg.%n% : d
        this.Mode := O("Mode", "date")
        this.Months := Max(1, Min(3, Integer(O("Months", this.Mode = "range" ? 2 : 1))))
        if (this.Mode = "time" || this.Mode = "month")
            this.Months := 1
        this.FirstDay := O("FirstDay", 1)
        this.Weeks := O("Weeks", false)
        this.Presets := O("Presets", true) && this.Mode = "range"
        this.Min := O("Min", ""), this.Max := O("Max", "")
        this.Hour12 := O("Hour12", false)
        this.Step := Max(1, Min(30, Integer(O("Step", 5))))
        this.Confirm := O("Confirm", false)
        this.Popup := O("Popup", false)
        this.Format := O("Format", "")
        this.OnPick := onPick, this.OnCancel := ""
        this._cbs := []
        this.Start := "", this.End := "", this.Hover := "", this.Focus := ""
        this.Active := "start"
        this.SetValue(O("Value", ""))
        if (hostId != "" && IsObject(win))
            AxRich.Bind(win, hostId, this)
    }
    Wire() {
        w := this.W, id := this.Id
        w.On("click", id, (el, ev) => this._Click(ev))
        w.On("mouseover", id, (el, ev) => this._Over(ev))
        w.On("keydown", id, (el, ev) => this._Key(ev))
        w.On("change", id, (el, ev) => this._TimeTyped(ev))
        return this
    }

    ; ------------------------------------------------------------- the value
    SetValue(v) {
        this.Start := "", this.End := ""
        if (this.Mode = "range") {
            r := AxDate.RangeOf(v)
            this.Start := r[1], this.End := r[2]
        } else if (Trim(String(v)) != "")
            this.Start := AxDate.FromIso(v)
        this.Active := (this.Mode = "range" && this.Start != "" && this.End = "") ? "end" : "start"
        this.Hover := "", this.Focus := ""
        this.Level := (this.Mode = "month") ? "months" : "days"
        ; the view opens on what is picked, or on today
        base := (this.Start != "") ? this.Start : AxDate.Today()
        this.View := AxDate.FirstOfMonth(base)
        ; a second month shows the end when it is the next month along
        return this
    }
    Value {
        get {
            if (this.Mode = "range")
                return AxDate.RangeIso(this.Start, this.End)
            return AxDate.Iso(this.Start, this.Mode)
        }
        set {
            this.SetValue(AxDate.Norm(value, this.Mode))
            this.Render()
            this._Mirror()
        }
    }
    Stamp => this.Start
    Days => (this.Start != "" && this.End != "") ? AxDate.Diff(this.End, this.Start) + 1 : 0
    Text => (this.Mode = "range") ? AxDate.RangeText(this.Start, this.End, this.Format)
          : AxDate.Text(this.Start, this.Mode, this.Format, this.Hour12)
    OnChange(fn) {
        this._cbs.Push(fn)
        return this
    }
    Clear() => this._SetAndEmit("", "", true)

    ; ----------------------------------------------------------------- markup
    Html() {
        cls := "axcal mode-" this.Mode (this.Popup ? " popup" : " inline") (this.Months > 1 ? " multi" : "")
             . (this.Presets && this.Level = "days" ? " haspre" : "")
        return '<div class="' cls '" id="' AxWindow._Esc(this.Id) '" tabindex="0">' this.Inner() '</div>'
    }
    Inner() {
        switch this.Level {
        case "months": body := this._MonthsHtml()
        case "years":  body := this._YearsHtml()
        default:       body := (this.Mode = "time") ? this._TimeHtml() : this._DaysHtml()
        }
        h := (this.Mode = "range") ? this._RangeBar() : ""
        if (this.Presets && this.Level = "days")
            h .= '<div class="axcal-body"><div class="axcal-presets">' this._PresetsHtml() '</div>'
              .  '<div class="axcal-main">' body '</div></div>'
        else
            h .= '<div class="axcal-main">' body '</div>'
        if (this.Mode = "datetime" && this.Level = "days")
            h .= this._TimeRow()
        return h this._Foot()
    }
    Render() {
        if !IsObject(this.W)
            return
        try {
            el := this.W.El(this.Id)
            if IsObject(el) {
                el.innerHTML := this.Inner()
                AxWindow._SetClass(el, "haspre", this.Presets && this.Level = "days")
            }
        }
    }

    ; the days of the months in view
    _DaysHtml() {
        E := (x) => AxWindow._Esc(x)
        h := '<div class="axcal-nav"><span class="axcal-arrow ico" data-act="prev" data-tip="Previous month">&#xE76B;</span>'
        loop this.Months {
            ms := AxDate.AddMonths(this.View, A_Index - 1)
            h .= '<span class="axcal-title" data-act="months" data-tip="Pick a month">'
              .  E(AxDate.MonthNames[AxDate.MonthOf(ms)]) ' <span class="axcal-yr">' AxDate.YearOf(ms) '</span></span>'
        }
        h .= '<span class="axcal-arrow ico" data-act="next" data-tip="Next month">&#xE76C;</span></div>'
        h .= '<div class="axcal-months">'
        loop this.Months
            h .= '<div class="axcal-m">' this._MonthTable(AxDate.AddMonths(this.View, A_Index - 1)) '</div>'
        return h '</div>'
    }
    _MonthTable(ms) {
        y := AxDate.YearOf(ms), m := AxDate.MonthOf(ms)
        first := AxDate.Make(y, m, 1)
        lead := Mod(AxDate.Dow(first) - this.FirstDay + 7, 7)
        cur := AxDate.AddDays(first, -lead)
        today := AxDate.Day(AxDate.Today())
        lo := (this.Min != "") ? AxDate.Day(this.Min) : "", hi := (this.Max != "") ? AxDate.Day(this.Max) : ""
        rg := this._Band()
        h := '<table class="axcal-t" cellspacing="0" cellpadding="0"><tr class="axcal-dn">'
        if this.Weeks
            h .= '<th class="axcal-wn"></th>'
        loop 7
            h .= '<th>' AxDate.DayNames[Mod(this.FirstDay + A_Index - 1, 7) + 1] '</th>'
        h .= '</tr>'
        loop 6 {
            h .= '<tr>'
            if this.Weeks
                h .= '<td class="axcal-wn">' AxDate.Week(AxDate.AddDays(cur, 3)) '</td>'
            loop 7 {
                col := A_Index
                dd := AxDate.Day(cur)
                inMonth := (AxDate.MonthOf(cur) = m)
                if (!inMonth && this.Months > 1) {
                    h .= '<td class="axcal-d blank"></td>'           ; two months: no doubles
                    cur := AxDate.AddDays(cur, 1)
                    continue
                }
                dis := (lo != "" && dd < lo) || (hi != "" && dd > hi)
                cls := "axcal-d" (inMonth ? "" : " out") (dd = today ? " today" : "") (dis ? " dis" : "")
                if (dd = this.Focus)
                    cls .= " kf"
                if IsObject(rg) {
                    if (dd = rg.Lo && dd = rg.Hi)
                        cls .= " sel solo"
                    else if (dd = rg.Lo)
                        cls .= " sel rs"
                    else if (dd = rg.Hi)
                        cls .= (rg.Preview ? " pv re" : " sel re")
                    else if (dd > rg.Lo && dd < rg.Hi)
                        cls .= " inr" (col = 1 ? " bl" : "") (col = 7 ? " br" : "") (rg.Preview ? " pvb" : "")
                } else if (this.Start != "" && dd = AxDate.Day(this.Start))
                    cls .= " sel"
                h .= '<td class="' cls '"' (dis ? "" : ' data-d="' dd '"') '><b>' AxDate.DayOf(cur) '</b></td>'
                cur := AxDate.AddDays(cur, 1)
            }
            h .= '</tr>'
        }
        return h '</table>'
    }
    ; the range as it stands, with the day under the pointer standing in for
    ; an end not picked yet
    _Band() {
        if (this.Mode != "range" || this.Start = "")
            return ""
        a := AxDate.Day(this.Start)
        preview := false
        if (this.End != "")
            b := AxDate.Day(this.End)
        else if (this.Active = "end" && this.Hover != "")
            b := this.Hover, preview := true
        else
            b := a
        if (b < a)
            tmp := a, a := b, b := tmp
        return {Lo: a, Hi: b, Preview: preview}
    }
    _MonthsHtml() {
        y := AxDate.YearOf(this.View)
        h := '<div class="axcal-nav"><span class="axcal-arrow ico" data-act="prevy" data-tip="Previous year">&#xE76B;</span>'
          .  '<span class="axcal-title" data-act="years" data-tip="Pick a year">' y '</span>'
          .  '<span class="axcal-arrow ico" data-act="nexty" data-tip="Next year">&#xE76C;</span></div>'
        now := SubStr(AxDate.Today(), 1, 6)
        pick := (this.Start != "") ? SubStr(this.Start, 1, 6) : ""
        lo := (this.Min != "") ? SubStr(this.Min, 1, 6) : "", hi := (this.Max != "") ? SubStr(this.Max, 1, 6) : ""
        h .= '<table class="axcal-g" cellspacing="0" cellpadding="0">'
        loop 4 {
            r := A_Index
            h .= '<tr>'
            loop 3 {
                mo := (r - 1) * 3 + A_Index
                ym := Format("{:04}{:02}", y, mo)
                dis := (lo != "" && ym < lo) || (hi != "" && ym > hi)
                cls := "axcal-cell" (ym = now ? " today" : "") (ym = pick ? " sel" : "") (dis ? " dis" : "")
                h .= '<td class="' cls '"' (dis ? "" : ' data-mo="' ym '"') '><b>' SubStr(AxDate.MonthNames[mo], 1, 3) '</b></td>'
            }
            h .= '</tr>'
        }
        return h '</table>'
    }
    _YearsHtml() {
        y := AxDate.YearOf(this.View), y0 := y - Mod(y, 12)
        h := '<div class="axcal-nav"><span class="axcal-arrow ico" data-act="prevd" data-tip="Earlier">&#xE76B;</span>'
          .  '<span class="axcal-title">' y0 ' ' Chr(0x2013) ' ' (y0 + 11) '</span>'
          .  '<span class="axcal-arrow ico" data-act="nextd" data-tip="Later">&#xE76C;</span></div>'
        now := AxDate.YearOf(AxDate.Today()), pick := (this.Start != "") ? AxDate.YearOf(this.Start) : 0
        h .= '<table class="axcal-g" cellspacing="0" cellpadding="0">'
        loop 4 {
            r := A_Index
            h .= '<tr>'
            loop 3 {
                yy := y0 + (r - 1) * 3 + A_Index - 1
                cls := "axcal-cell" (yy = now ? " today" : "") (yy = pick ? " sel" : "")
                h .= '<td class="' cls '" data-yr="' yy '"><b>' yy '</b></td>'
            }
            h .= '</tr>'
        }
        return h '</table>'
    }
    ; a time on its own: the hours and the minutes, each a grid to click
    _TimeHtml() {
        ts := (this.Start != "") ? this.Start : ""
        hh := (ts != "") ? AxDate.HourOf(ts) : -1, mi := (ts != "") ? AxDate.MinOf(ts) : -1
        big := (ts = "") ? "--:--" : AxDate.Text(ts, "time", "", this.Hour12)
        h := '<div class="axcal-tbig">' AxWindow._Esc(big) '</div><div class="axcal-tcols">'
        h .= '<div class="axcal-tcol"><div class="axcal-tcap">Hour</div><table class="axcal-g axcal-hg" cellspacing="0" cellpadding="0">'
        if this.Hour12 {
            pm := (hh >= 12)
            loop 2 {
                r := A_Index
                h .= '<tr>'
                loop 6 {
                    n := (r - 1) * 6 + A_Index - 1                 ; 0..11, shown as 12, 1..11
                    v := n + (pm ? 12 : 0)
                    h .= '<td class="axcal-cell' (v = hh ? " sel" : "") '" data-hh="' v '"><b>' (n = 0 ? 12 : n) '</b></td>'
                }
                h .= '</tr>'
            }
            h .= '</table><div class="axcal-ap"><span class="axcal-seg' (hh >= 0 && !pm ? " on" : "") '" data-ap="am">AM</span>'
              .  '<span class="axcal-seg' (pm ? " on" : "") '" data-ap="pm">PM</span></div></div>'
        } else {
            loop 4 {
                r := A_Index
                h .= '<tr>'
                loop 6 {
                    v := (r - 1) * 6 + A_Index - 1
                    h .= '<td class="axcal-cell' (v = hh ? " sel" : "") '" data-hh="' v '"><b>' Format("{:02}", v) '</b></td>'
                }
                h .= '</tr>'
            }
            h .= '</table></div>'
        }
        h .= '<div class="axcal-tcol"><div class="axcal-tcap">Minute</div><table class="axcal-g axcal-mg" cellspacing="0" cellpadding="0">'
        stepm := (this.Step >= 5) ? this.Step : 5
        count := 60 // stepm, cols := (count > 12) ? 6 : 4
        i := 0
        while (i < count) {
            h .= '<tr>'
            loop cols {
                if (i >= count) {
                    h .= '<td></td>'
                    continue
                }
                v := i * stepm
                h .= '<td class="axcal-cell' (v = mi ? " sel" : "") '" data-mi="' v '"><b>' Format("{:02}", v) '</b></td>'
                i++
            }
            h .= '</tr>'
        }
        return h '</table></div></div>'
    }
    ; a date and a time: the time sits under the days
    _TimeRow() {
        ts := (this.Start != "") ? this.Start : AxDate.Now()
        hh := AxDate.HourOf(ts), mi := AxDate.MinOf(ts)
        shown := this.Hour12 ? (Mod(hh, 12) = 0 ? 12 : Mod(hh, 12)) : hh
        id := AxWindow._Esc(this.Id)
        h := '<div class="axcal-trow"><span class="ico axcal-tico">&#xE823;</span><span class="axcal-tlbl">Time</span>'
          .  '<span class="axcal-spin"><input type="text" id="' id '_hh" value="' Format("{:02}", shown) '" maxlength="2" autocomplete="off">'
          .  '<span class="axcal-sb"><span class="ico" data-act="h+">&#xE70E;</span><span class="ico" data-act="h-">&#xE70D;</span></span></span>'
          .  '<span class="axcal-colon">:</span>'
          .  '<span class="axcal-spin"><input type="text" id="' id '_mi" value="' Format("{:02}", mi) '" maxlength="2" autocomplete="off">'
          .  '<span class="axcal-sb"><span class="ico" data-act="m+">&#xE70E;</span><span class="ico" data-act="m-">&#xE70D;</span></span></span>'
        if this.Hour12
            h .= '<span class="axcal-seg' (hh < 12 ? " on" : "") '" data-ap="am">AM</span><span class="axcal-seg' (hh >= 12 ? " on" : "") '" data-ap="pm">PM</span>'
        return h '<span class="axcal-chip" data-act="now">Now</span></div>'
    }
    _RangeBar() {
        E := (x) => AxWindow._Esc(x)
        a := (this.Start != "") ? FormatTime(this.Start, "ddd d MMM yyyy") : "Pick a day"
        b := (this.End != "") ? FormatTime(this.End, "ddd d MMM yyyy")
           : (this.Start != "" && this.Hover != "" && this.Active = "end") ? FormatTime(this.Hover "000000", "ddd d MMM yyyy") : "Pick a day"
        n := this.Days
        if (!n && this.Start != "" && this.Hover != "" && this.Active = "end")
            n := Abs(AxDate.Diff(this.Hover "000000", AxDate.Day(this.Start) "000000")) + 1
        return '<div class="axcal-rbar">'
             . '<span class="axcal-rchip' (this.Active = "start" ? " on" : "") (this.Start = "" ? " empty" : "") '" data-act="astart">'
             . '<small>Start</small><b>' E(a) '</b></span>'
             . '<span class="axcal-rto ico">&#xE72A;</span>'
             . '<span class="axcal-rchip' (this.Active = "end" ? " on" : "") (this.End = "" ? " empty" : "") '" data-act="aend">'
             . '<small>End</small><b>' E(b) '</b></span>'
             . '<span class="axcal-rlen">' (n ? n " day" (n = 1 ? "" : "s") : "") '</span></div>'
    }
    static PresetList := [["today", "Today"], ["yesterday", "Yesterday"], ["7", "Last 7 days"], ["30", "Last 30 days"],
                          ["week", "This week"], ["lastweek", "Last week"], ["month", "This month"],
                          ["lastmonth", "Last month"], ["90", "Last 90 days"], ["year", "This year"]]
    _PresetsHtml() {
        h := ""
        for p in AxCalendar.PresetList {
            r := this.PresetRange(p[1])
            on := (this.Start != "" && this.End != "" && AxDate.Day(r[1]) = AxDate.Day(this.Start) && AxDate.Day(r[2]) = AxDate.Day(this.End))
            h .= '<span class="axcal-pre' (on ? " on" : "") '" data-pre="' p[1] '">' p[2] '</span>'
        }
        return h
    }
    ; the months in view: the range's first, unless its end would fall past
    ; the last month shown -- then the end's, as the last
    ShowRange(a, b) {
        span := (AxDate.YearOf(b) - AxDate.YearOf(a)) * 12 + AxDate.MonthOf(b) - AxDate.MonthOf(a)
        this.View := (span >= this.Months) ? AxDate.AddMonths(AxDate.FirstOfMonth(b), -(this.Months - 1))
                   : AxDate.FirstOfMonth(a)
        return this
    }
    PresetRange(key) {
        t := AxDate.Today()
        wk := AxDate.AddDays(t, -Mod(AxDate.Dow(t) - this.FirstDay + 7, 7))
        switch key {
        case "today":     return [t, t]
        case "yesterday": return [AxDate.AddDays(t, -1), AxDate.AddDays(t, -1)]
        case "7":         return [AxDate.AddDays(t, -6), t]
        case "30":        return [AxDate.AddDays(t, -29), t]
        case "90":        return [AxDate.AddDays(t, -89), t]
        case "week":      return [wk, AxDate.AddDays(wk, 6)]
        case "lastweek":  return [AxDate.AddDays(wk, -7), AxDate.AddDays(wk, -1)]
        case "month":
            f := AxDate.FirstOfMonth(t)
            return [f, AxDate.AddDays(AxDate.AddMonths(f, 1), -1)]
        case "lastmonth":
            f := AxDate.AddMonths(AxDate.FirstOfMonth(t), -1)
            return [f, AxDate.AddDays(AxDate.AddMonths(f, 1), -1)]
        case "year":
            y := AxDate.YearOf(t)
            return [AxDate.Make(y, 1, 1), AxDate.Make(y, 12, 31)]
        }
        return [t, t]
    }
    _Foot() {
        E := (x) => AxWindow._Esc(x)
        b := (act, txt, accent := false) => '<span class="axcal-btn' (accent ? " accent" : "") '" data-act="' act '">' txt '</span>'
        say := ""
        switch this.Mode {
        case "range":
            say := (this.Start = "") ? "Pick the first day" : (this.End = "") ? "Now the last day" : ""
        case "date", "datetime":
            say := (this.Start != "") ? FormatTime(this.Start, "dddd") : ""
        }
        h := '<div class="axcal-foot"><span class="axcal-say">' E(say) '</span>'
        if (this.Mode = "time")
            h .= b("now", "Now")
        else if (this.Mode = "month")
            h .= b("today", "This month")
        else if (this.Mode != "range")
            h .= b("today", "Today")
        h .= b("clear", "Clear")
        if this.Popup {
            if (this.Mode = "datetime" || (this.Mode = "range" && this.Confirm))
                h .= b("cancel", "Cancel") b("done", this.Mode = "range" ? "Apply" : "Done", true)
        }
        return h '</div>'
    }

    ; ---------------------------------------------------------------- events
    ; the nearest element that says what it is, from where the event landed
    static _Hit(ev) {
        try el := ev.srcElement
        catch
            return ""
        loop 6 {
            if !IsObject(el)
                return ""
            for k in ["data-d", "data-act", "data-mo", "data-yr", "data-pre", "data-hh", "data-mi", "data-ap"] {
                v := AxWindow._Attr(el, k)
                if (v != "")
                    return {K: SubStr(k, 6), V: v}
            }
            try {
                if (el.id != "" && InStr(el.id, "_cal"))
                    return ""
            }
            el := AxWindow._ParentEl(el)
        }
        return ""
    }
    _Click(ev) {
        h := AxCalendar._Hit(ev)
        if !IsObject(h)
            return
        switch h.K {
        case "d":   return this.PickDay(h.V)
        case "mo":  return this._PickMonth(h.V)
        case "yr":  return (this.View := Format("{:04}", h.V) SubStr(this.View, 5), this.Level := "months", this.Render())
        case "pre":
            r := this.PresetRange(h.V)
            this.ShowRange(r[1], r[2])
            return this._SetAndEmit(r[1], r[2], !this.Confirm)
        case "hh":  return this._SetTime(Integer(h.V), -1, false)
        case "mi":  return this._SetTime(-1, Integer(h.V), this.Mode = "time")
        case "ap":  return this._SetAmPm(h.V)
        case "act": return this._Act(h.V)
        }
    }
    _Act(a) {
        switch a {
        case "prev":   this.View := AxDate.AddMonths(this.View, -1)
        case "next":   this.View := AxDate.AddMonths(this.View, 1)
        case "prevy":  this.View := AxDate.AddMonths(this.View, -12)
        case "nexty":  this.View := AxDate.AddMonths(this.View, 12)
        case "prevd":  this.View := AxDate.AddMonths(this.View, -144)
        case "nextd":  this.View := AxDate.AddMonths(this.View, 144)
        case "months": this.Level := "months"
        case "years":  this.Level := "years"
        case "astart":
            this.Active := "start", this.Hover := ""
        case "aend":
            if (this.Start != "")
                this.Active := "end", this.Hover := ""
        case "today":
            t := AxDate.Today()
            if (this.Mode = "range")
                return this._SetAndEmit(t, t, !this.Confirm)
            this.View := AxDate.FirstOfMonth(t)
            return this._SetAndEmit(this.Mode = "month" ? AxDate.FirstOfMonth(t) : t, "", true)
        case "now":
            n := AxDate.Now()
            this.View := AxDate.FirstOfMonth(n)
            return this._SetAndEmit(n, "", true)
        case "clear":  return this._SetAndEmit("", "", true)
        case "done":   return this._Emit(true)
        case "cancel":
            if IsObject(this.OnCancel)
                this.OnCancel.Call()
            return
        case "h+", "h-", "m+", "m-":
            ts := (this.Start != "") ? this.Start : AxDate.Now()
            hh := AxDate.HourOf(ts), mi := AxDate.MinOf(ts)
            switch a {
            case "h+": hh := Mod(hh + 1, 24)
            case "h-": hh := Mod(hh + 23, 24)
            case "m+": mi := Mod(mi + this.Step, 60)
            case "m-": mi := Mod(mi - this.Step + 60, 60)
            }
            return this._SetTime(hh, mi, false)
        }
        this.Render()
    }
    PickDay(dd) {
        dd := SubStr(dd, 1, 8)
        if (this.Min != "" && dd < AxDate.Day(this.Min)) || (this.Max != "" && dd > AxDate.Day(this.Max))
            return
        this.Focus := dd
        switch this.Mode {
        case "range":
            if (this.Active = "start" || this.Start = "") {
                keep := (this.End != "" && dd <= AxDate.Day(this.End)) ? this.End : ""
                this.Start := dd "000000", this.End := keep, this.Hover := ""
                this.Active := "end"
                if (keep != "")
                    return this._Emit(!this.Confirm)
                this.Render(), this._Mirror()
                return this._Emit(false)
            }
            ts := dd "000000"
            if (dd < AxDate.Day(this.Start))
                this.End := this.Start, this.Start := ts
            else
                this.End := ts
            this.Active := "start", this.Hover := ""
            return this._Emit(!this.Confirm)
        case "datetime":
            base := (this.Start != "") ? this.Start : AxDate.Now()
            this.Start := AxDate.WithTime(dd, AxDate.HourOf(base), AxDate.MinOf(base) - Mod(AxDate.MinOf(base), this.Step))
            return this._Emit(false)
        }
        this.Start := dd "000000"
        return this._Emit(true)
    }
    _PickMonth(ym) {
        if (this.Mode = "month") {
            this.View := ym "01000000"
            return this._SetAndEmit(ym "01000000", "", true)
        }
        this.View := ym "01000000", this.Level := "days"
        this.Render()
    }
    _SetTime(hh, mi, final) {
        base := (this.Start != "") ? this.Start : (this.Mode = "time" ? AxDate.Today() : AxDate.Now())
        if (this.Start = "" && this.Mode != "time")
            base := AxDate.WithTime(base, AxDate.HourOf(base), AxDate.MinOf(base) - Mod(AxDate.MinOf(base), this.Step))
        hh := (hh < 0) ? AxDate.HourOf(base) : hh
        mi := (mi < 0) ? ((this.Start = "") ? 0 : AxDate.MinOf(base)) : mi
        this.Start := AxDate.WithTime(base, hh, mi)
        return this._Emit(final)
    }
    _SetAmPm(ap) {
        if (this.Start = "")
            this.Start := AxDate.WithTime(this.Mode = "time" ? AxDate.Today() : AxDate.Now(), 9, 0)
        hh := AxDate.HourOf(this.Start)
        if (ap = "pm" && hh < 12)
            hh += 12
        else if (ap = "am" && hh >= 12)
            hh -= 12
        this.Start := AxDate.WithTime(this.Start, hh, AxDate.MinOf(this.Start))
        return this._Emit(false)
    }
    ; typed into the hour or the minute box of a date and time
    _TimeTyped(ev) {
        try id := ev.srcElement.id
        catch
            return
        if (id != this.Id "_hh" && id != this.Id "_mi")
            return
        try v := Trim(ev.srcElement.value)
        catch
            return
        if !RegExMatch(v, "^\d{1,2}$")
            return this.Render()
        n := Integer(v)
        if (id = this.Id "_hh") {
            if this.Hour12 {
                pm := (this.Start != "" && AxDate.HourOf(this.Start) >= 12)
                n := Mod(Min(n, 12), 12) + (pm ? 12 : 0)
            }
            return (n < 24) ? this._SetTime(n, -1, false) : this.Render()
        }
        return (n < 60) ? this._SetTime(-1, n, false) : this.Render()
    }
    _Over(ev) {
        if (this.Mode != "range" || this.Active != "end" || this.Start = "" || this.End != "" || this.Level != "days")
            return
        h := AxCalendar._Hit(ev)
        if (!IsObject(h) || h.K != "d" || h.V = this.Hover)
            return
        this.Hover := h.V
        this.Render()
    }
    _Key(ev) {
        try {
            k := ev.keyCode, id := ev.srcElement.id
        } catch
            return
        ; the hour and minute boxes: Up and Down step them, Enter settles them
        if (id = this.Id "_hh" || id = this.Id "_mi") {
            if (k = 38 || k = 40) {
                this._Act((id = this.Id "_hh" ? "h" : "m") (k = 38 ? "+" : "-"))
                try this.W.El(id).focus()
                try ev.returnValue := false
            } else if (k = 13) {
                this._TimeTyped(ev)
                this._Emit(true)
            }
            return
        }
        if (this.Level != "days" || this.Mode = "time") {
            if (k = 27 && this.Level != "days" && this.Mode != "month")
                this.Level := "days", this.Render()
            return
        }
        f := (this.Focus != "") ? this.Focus : (this.Start != "") ? AxDate.Day(this.Start) : AxDate.Day(AxDate.Today())
        ts := f "000000"
        sh := false
        try sh := ev.shiftKey
        switch k {
        case 37: ts := AxDate.AddDays(ts, -1)
        case 39: ts := AxDate.AddDays(ts, 1)
        case 38: ts := AxDate.AddDays(ts, -7)
        case 40: ts := AxDate.AddDays(ts, 7)
        case 33: ts := AxDate.AddMonths(ts, sh ? -12 : -1)
        case 34: ts := AxDate.AddMonths(ts, sh ? 12 : 1)
        case 36: ts := AxDate.AddDays(ts, -Mod(AxDate.Dow(ts) - this.FirstDay + 7, 7))
        case 35: ts := AxDate.AddDays(ts, 6 - Mod(AxDate.Dow(ts) - this.FirstDay + 7, 7))
        case 84: ts := AxDate.Today()
        case 13, 32:
            try ev.returnValue := false
            return this.PickDay(f)
        case 46, 8:
            try ev.returnValue := false
            return this._SetAndEmit("", "", true)
        default:
            return
        }
        try ev.returnValue := false
        this.Focus := AxDate.Day(ts)
        if (this.Mode = "range" && this.Active = "end" && this.Start != "" && this.End = "")
            this.Hover := this.Focus
        ; keep the focused day in view
        first := SubStr(this.View, 1, 6), last := SubStr(AxDate.AddMonths(this.View, this.Months - 1), 1, 6)
        at := SubStr(ts, 1, 6)
        if (at < first)
            this.View := AxDate.FirstOfMonth(ts)
        else if (at > last)
            this.View := AxDate.AddMonths(AxDate.FirstOfMonth(ts), -(this.Months - 1))
        this.Render()
    }

    ; ----------------------------------------------------------- telling others
    _SetAndEmit(a, b, final) {
        this.Start := a, this.End := b, this.Hover := ""
        this.Active := (this.Mode = "range" && a != "" && b = "") ? "end" : "start"
        return this._Emit(final)
    }
    ; draw, tell the page element, then whoever is listening: the date box
    ; (OnPick), or for a calendar on the page its own OnChange and OnValue
    _Emit(final) {
        this.Render()
        this._Mirror()
        v := this.Value
        if IsObject(this.OnPick)
            this.OnPick.Call(v, final)
        if (this.HostId != "" && (final || this.Mode = "datetime")) {
            if (v = this._last)
                return
            this._last := v
            for fn in this._cbs.Clone()
                try fn(v, this)
            try this.W._FireValue(this.W.El(this.HostId), v)
        }
    }
    _last := ""
    _Mirror() {
        if (this.HostId = "" || !IsObject(this.W))
            return
        try this.W.El(this.HostId).setAttribute("data-value", this.Value)
    }
}

; =============================================================================
;  AxDateBox -- the box: what people type into, and the anchor the calendar
;  pops over. Plain leaves the calendar out and keeps the typing.
; =============================================================================
class AxDateBox {
    static Html(id, cfg, attrs := "") {
        O := (n, d := "") => (IsObject(cfg) && cfg.HasOwnProp(n)) ? cfg.%n% : d
        E := (x) => AxWindow._Esc(x)
        mode := O("Mode", "date"), v := O("Value", "")
        txt := AxDate.ValueText(v, cfg)
        static say := Map("date", "Pick a date", "datetime", "Pick a date and time", "time", "Pick a time",
                          "range", "Pick a range", "month", "Pick a month")
        ph := (O("Placeholder") != "") ? O("Placeholder") : say.Has(mode) ? say[mode] : ""
        cls := "textbox axdate mode-" mode (txt != "" ? " has" : "") (O("Plain", false) ? " plain" : "")
             . (O("NoClear", false) ? " noclear" : "")
        if (attrs != "") {
            n := 0
            a := RegExReplace(attrs, 'S)class="([^"]*)"', 'class="' cls ' $1"', &n)
            if !n
                a .= ' class="' cls '"'
        } else
            a := ' id="' E(id) '" class="' cls '"'
        ico := (mode = "time") ? "E823" : (mode = "range") ? "E8BF" : "E787"
        return '<span' a ' data-role="datebox" data-value="' E(v) '" data-mode="' mode '">'
             . '<input type="text" id="' E(id) '_in" value="' E(txt) '" placeholder="' E(ph) '" autocomplete="off" spellcheck="false">'
             . '<span class="axdate-ico ico" id="' E(id) '_ico">&#x' ico ';</span>'
             . '<span class="axdate-x ico" id="' E(id) '_x" data-tip="Clear">&#xE711;</span>'
             . (O("Plain", false) ? "" : '<span class="axdate-dd ico" id="' E(id) '_dd" data-tip="Open the calendar (Alt+Down)">&#xE70D;</span>')
             . '</span>'
    }

    __New(win, id, cfg := "") {
        this.W := win, this.Id := id
        this.Cfg := IsObject(cfg) ? cfg : {}
        O := (n, d := "") => this.Cfg.HasOwnProp(n) ? this.Cfg.%n% : d
        this.Mode := O("Mode", "date"), this.Order := O("Order", "dmy")
        this.Plain := O("Plain", false), this.Step := Max(1, Integer(O("Step", 5)))
        this.Val := O("Value", ""), this._before := ""
        this._cbs := [], this._focusCal := false
        c := {}
        for k, v in this.Cfg.OwnProps()
            c.%k% := v
        c.Popup := true
        this.Cal := AxCalendar(win, id "_cal", c, (v, final) => this._Picked(v, final))
        this.Cal.OnCancel := () => this._Cancel()
        this.Cal.Wire()
        AxRich.Bind(win, id, this)
        if !this.Plain
            win.Popover(id, {On: "none", Build: (*) => this._Build(), Class: "axcal-pop", Align: "left", Gap: 4,
                             OnOpen: (w, a) => this._Opened(), OnClose: (w, a) => this._Closed()})
        for part in ["_ico", "_dd"]
            win.On("click", id part, (el, ev) => this.Toggle(true))
        win.On("click", id "_in", (el, ev) => this._InClick())
        win.On("click", id "_x", (el, ev) => this.Clear())
        win.On("keydown", id "_in", (el, ev) => this._Key(ev))
        win.On("focusout", id "_in", (el, ev) => this._Commit())
    }
    _O(n, d := "") => this.Cfg.HasOwnProp(n) ? this.Cfg.%n% : d

    ; ------------------------------------------------------------- the value
    Value {
        get => this.Val
        set => this._Apply(AxDate.Norm(value, this.Mode, this.Order), false)
    }
    Text => AxDate.ValueText(this.Val, this.Cfg)
    Stamp => (this.Mode = "range") ? AxDate.RangeOf(this.Val)[1] : AxDate.FromIso(this.Val)
    Start => this.Stamp
    End => (this.Mode = "range") ? AxDate.RangeOf(this.Val)[2] : this.Stamp
    Days {
        get {
            r := AxDate.RangeOf(this.Val)
            return (r[1] != "" && r[2] != "") ? AxDate.Diff(r[2], r[1]) + 1 : 0
        }
    }
    OnChange(fn) {
        this._cbs.Push(fn)
        return this
    }
    Clear() {
        this._Apply("", true)
        if (this.W.PopoverOpen = this.Id)
            this.W.ClosePopover()
        return this
    }
    ; put the value in the page, and tell whoever listens if it moved
    _Apply(v, fire) {
        same := (v = this.Val)
        this.Val := v
        w := this.W, id := this.Id
        txt := AxDate.ValueText(v, this.Cfg)
        try {
            w.El(id).setAttribute("data-value", v)
            w.El(id "_in").value := txt
            AxWindow._SetClass(w.El(id), "has", txt != "")
            AxWindow._SetClass(w.El(id), "bad", false)
        }
        if (fire && !same) {
            for fn in this._cbs.Clone()
                try fn(v, this)
            try w._FireValue(w.El(id), v)
        }
        return this
    }

    ; ----------------------------------------------------------- the calendar
    Open(focusCal := true) {
        if this.Plain
            return this
        this._focusCal := focusCal
        this.W.ShowPopover(this.Id)
        return this
    }
    Close() {
        if (this.W.PopoverOpen = this.Id)
            this.W.ClosePopover()
        return this
    }
    Toggle(focusCal := true) => (this.W.PopoverOpen = this.Id) ? this.Close() : this.Open(focusCal)
    IsOpen => (this.W.PopoverOpen = this.Id)
    _Build() {
        this._before := this.Val
        this.Cal.SetValue(this.Val)
        return this.Cal.Html()
    }
    _Opened() {
        AxWindow._SetClass(this.W.El(this.Id), "open", true)
        if this._focusCal
            try this.W.El(this.Cal.Id).focus()
    }
    _Closed() {
        try AxWindow._SetClass(this.W.El(this.Id), "open", false)
        ; a range left half-picked is not a range: the box keeps what it had
        if (this.Mode = "range")
            this._Apply(this.Val, false)
    }
    _InClick() {
        if (!this.Plain && !this.IsOpen)
            this.Open(false)
    }
    _Picked(v, final) {
        if (this.Mode = "range" && !final) {
            ; half a range: the box says so, the value waits for the other end
            r := AxDate.RangeOf(v)
            try this.W.El(this.Id "_in").value := AxDate.RangeText(r[1], r[2], this._O("Format"))
            return
        }
        this._Apply(v, true)
        if final {
            this.Close()
            try this.W.El(this.Id "_in").focus()
        }
    }
    _Cancel() {
        this._Apply(this._before, true)
        this.Close()
    }

    ; ---------------------------------------------------------------- typing
    _Key(ev) {
        try {
            k := ev.keyCode, alt := ev.altKey
        } catch
            return
        if (k = 13) {
            this._Commit()
            this.Close()
            try ev.returnValue := false
        } else if (k = 115 || (k = 40 && alt)) {
            this.Open(true)
            try ev.returnValue := false
        } else if ((k = 38 || k = 40) && !alt) {
            if this.IsOpen {
                if (k = 40)
                    try this.W.El(this.Cal.Id).focus()
            } else
                this.StepBy(k = 38 ? 1 : -1)
            try ev.returnValue := false
        }
    }
    ; Up and Down: a day, a month, or a step of minutes
    StepBy(n) {
        if (this.Mode = "range")
            return this
        ts := (this.Val != "") ? AxDate.FromIso(this.Val) : (this.Mode = "time" ? AxDate.WithTime(AxDate.Today(), 9, 0) : AxDate.Today())
        switch this.Mode {
        case "time":  ts := DateAdd(ts, n * this.Step, "Minutes")
        case "month": ts := AxDate.AddMonths(ts, n)
        default:      ts := AxDate.AddDays(ts, n)
        }
        mn := this._O("Min"), mx := this._O("Max")
        if (mn != "" && AxDate.Day(ts) < AxDate.Day(mn)) || (mx != "" && AxDate.Day(ts) > AxDate.Day(mx))
            return this
        return this._Apply(AxDate.Iso(ts, this.Mode), true)
    }
    ; what was typed, read; what cannot be read goes back to what it was
    _Commit() {
        try t := this.W.El(this.Id "_in").value
        catch
            return
        if (Trim(t) = "")
            return this._Apply("", true)
        if (t = AxDate.ValueText(this.Val, this.Cfg))
            return
        if (this.Mode = "range") {
            r := AxDate.ParseRange(t, this.Order)
            v := (r[1] != "") ? AxDate.RangeIso(r[1], r[2] != "" ? r[2] : r[1]) : ""
        } else {
            ts := AxDate.Parse(t, this.Mode, this.Order)
            mn := this._O("Min"), mx := this._O("Max")
            if (ts != "" && ((mn != "" && AxDate.Day(ts) < AxDate.Day(mn)) || (mx != "" && AxDate.Day(ts) > AxDate.Day(mx))))
                ts := ""
            v := AxDate.Iso(ts, this.Mode)
        }
        if (v = "") {
            this._Apply(this.Val, false)
            try AxWindow._SetClass(this.W.El(this.Id), "bad", true)
            SetTimer(this._UnBadFn(), -1400)
            return
        }
        this._Apply(v, true)
    }
    _UnBadFn() => (*) => AxDate._Unbad(this.W, this.Id)
}

; =============================================================================
;  AxDateDialog -- the calendar as a window of its own.
; =============================================================================
class AxDateDialog extends AxRichDialog {
    ; the window is sized to the calendar it holds once the page has loaded
    ; (AxRichDialog._FitContent); the numbers below are only the first layout
    FitDefault := "both"
    _Build(defaults := "") {
        mode := this.O("Mode", "date")
        months := this.O("Months", mode = "range" ? 2 : 1)
        pre := (mode = "range" && this.O("Presets", true)) ? 150 : 0
        width := this.O("Width", Max(380, months * 292 + pre + 56))
        height := this.O("Height", (mode = "time") ? 470 : (mode = "range") ? 590 : (mode = "datetime") ? 590 : 540)
        heading := this.O("Heading", this.O("Title", mode = "range" ? "Pick a range" : mode = "time" ? "Pick a time" : "Pick a date"))
        d := {Title: this.O("Title", heading), Width: width, Height: height, Icon: (mode = "time") ? "E823" : "E787"}
        if !this.Opts.HasOwnProp("Css")
            this.Opts.Css := AxRich.CssText("Date")
        return super._Build(d)
    }
    _Content(g) {
        mode := this.O("Mode", "date")
        heading := this.O("Heading", this.O("Title", mode = "range" ? "Pick a range" : mode = "time" ? "Pick a time" : "Pick a date"))
        if (heading != "")
            g.AddHtml("", "<h1>" AxWindow._Esc(heading) "</h1>")
        cfg := {Mode: mode, Months: this.O("Months", mode = "range" ? 2 : 1), Value: AxDate.Norm(this.O("Value", ""), mode),
                FirstDay: this.O("FirstDay", 1), Weeks: this.O("Weeks", false), Presets: this.O("Presets", true),
                Min: AxDate.Bound(this.O("Min", "")), Max: AxDate.Bound(this.O("Max", "")), Hour12: this.O("Hour12", false),
                Step: this.O("Step", 5), Format: this.O("Format", "")}
        this._cfg := cfg
        g.AddHtml("vaxdtHost", AxCalendar.HostHtml("axdt", cfg))
        this._Footer(g, this.O("Buttons", ["Cancel", "OK"]), (i, isDefault) => this.Done(isDefault ? this.Cal.Value : ""))
    }
    _Ready(g) {
        this.Cal := AxCalendar(g, "axdt_cal", this._cfg, "", "axdt").Wire()
        try g.El("axdt_cal").focus()
    }
}
