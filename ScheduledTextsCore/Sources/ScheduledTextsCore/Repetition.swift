import Foundation

/// How a text repeats, modeled on the Repeat and Custom screens in the iOS
/// Calendar app: every N days, weeks (on chosen weekdays), months (on the
/// same date, or on "the first Monday") or years, until an optional end date.
///
/// The schedule starts at the text's first send time (its anchor), which also
/// sets the time of day. The first text goes out at the anchor even when it
/// doesn't match the rule, like the first event in Calendar.
public struct Repetition: Codable, Equatable, Hashable {
    public enum Frequency: String, Codable, CaseIterable, Identifiable {
        case daily, weekly, monthly, yearly
        public var id: String { rawValue }
    }

    /// "The first Monday", "the last Friday". `ordinal` is 1 to 4, or -1 for
    /// the last one in the month. `weekday` uses Calendar numbering, 1 is Sunday.
    public struct OrdinalWeekday: Codable, Equatable, Hashable {
        public var ordinal: Int
        public var weekday: Int

        public init(ordinal: Int, weekday: Int) {
            self.ordinal = ordinal
            self.weekday = weekday
        }

        /// The one `date` falls on: the 2nd Tuesday, say.
        public static func of(_ date: Date, calendar: Calendar = .current) -> OrdinalWeekday {
            // A fifth Monday is always the last one.
            let day = calendar.component(.day, from: date)
            let ordinal = (day - 1) / 7 + 1
            return OrdinalWeekday(ordinal: ordinal > 4 ? -1 : ordinal, weekday: calendar.component(.weekday, from: date))
        }
    }

    public var frequency: Frequency
    /// Every this many days, weeks, months or years. At least 1.
    public var interval: Int
    /// Weekly only: which days, in Calendar numbering (1 is Sunday). Empty
    /// means the anchor's weekday.
    public var weekdays: Set<Int>
    /// Monthly only: nil repeats on the anchor's day of the month (months
    /// without that day are skipped, like Calendar). Set, it repeats on that
    /// weekday of the month instead.
    public var monthlyWeekday: OrdinalWeekday?
    /// No texts after the end of this day. Nil repeats forever.
    public var endDate: Date?

    public init(
        frequency: Frequency,
        interval: Int = 1,
        weekdays: Set<Int> = [],
        monthlyWeekday: OrdinalWeekday? = nil,
        endDate: Date? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.monthlyWeekday = monthlyWeekday
        self.endDate = endDate
    }

    public static let daily = Repetition(frequency: .daily)
    public static let weekly = Repetition(frequency: .weekly)
    public static let biweekly = Repetition(frequency: .weekly, interval: 2)
    public static let monthly = Repetition(frequency: .monthly)
    public static let yearly = Repetition(frequency: .yearly)

    /// The first time this repeats strictly after `date`, for a schedule that
    /// starts at `anchor`. Nil once the end date has passed.
    public func nextOccurrence(after date: Date, anchor: Date, calendar: Calendar = .current) -> Date? {
        let step = max(interval, 1)
        let time = calendar.dateComponents([.hour, .minute], from: anchor)
        let limit = endDate.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }

        // Periods (days, weeks, months, years) from the anchor's period to
        // `date`'s, rounded down to a multiple of the interval, so the search
        // starts near `date` instead of walking from the anchor.
        let unit: Calendar.Component
        let periodStart: (Date) -> Date
        switch frequency {
        case .daily:
            unit = .day
            periodStart = { calendar.startOfDay(for: $0) }
        case .weekly:
            unit = .weekOfYear
            periodStart = { calendar.dateInterval(of: .weekOfYear, for: $0)!.start }
        case .monthly:
            unit = .month
            periodStart = { calendar.dateInterval(of: .month, for: $0)!.start }
        case .yearly:
            unit = .year
            periodStart = { calendar.dateInterval(of: .year, for: $0)!.start }
        }
        let firstPeriod = periodStart(anchor)
        let elapsed = calendar.dateComponents([unit], from: firstPeriod, to: periodStart(max(date, anchor))).value(for: unit) ?? 0
        var k = max(0, elapsed / step * step)

        // A few hundred periods covers every skip (a Feb 29 waits at most
        // 8 years; a 31st at most 2 months).
        for _ in 0..<500 {
            guard let period = calendar.date(byAdding: unit, value: k, to: firstPeriod) else { return nil }
            if let limit, period >= limit { return nil }
            let candidates = occurrences(inPeriodStarting: period, anchor: anchor, time: time, calendar: calendar)
            if let hit = candidates.first(where: { $0 > date && $0 >= anchor }) {
                if let limit, hit >= limit { return nil }
                return hit
            }
            k += step
        }
        return nil
    }

    /// Every time in one period (a day, week, month or year) that matches
    /// the rule, in order.
    private func occurrences(
        inPeriodStarting period: Date,
        anchor: Date,
        time: DateComponents,
        calendar: Calendar
    ) -> [Date] {
        func at(_ day: Date) -> Date? {
            calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day)
        }
        switch frequency {
        case .daily:
            return at(period).map { [$0] } ?? []
        case .weekly:
            let days = weekdays.isEmpty ? [calendar.component(.weekday, from: anchor)] : weekdays
            return (0..<7).compactMap { offset -> Date? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: period),
                      days.contains(calendar.component(.weekday, from: day)) else { return nil }
                return at(day)
            }
        case .monthly:
            if let monthlyWeekday {
                return Self.day(monthlyWeekday, inMonthStarting: period, calendar: calendar).flatMap(at).map { [$0] } ?? []
            }
            let dayOfMonth = calendar.component(.day, from: anchor)
            return Self.date(monthStart: period, day: dayOfMonth, calendar: calendar).flatMap(at).map { [$0] } ?? []
        case .yearly:
            let month = calendar.component(.month, from: anchor)
            let dayOfMonth = calendar.component(.day, from: anchor)
            guard let monthStart = calendar.date(byAdding: .month, value: month - 1, to: period) else { return [] }
            return Self.date(monthStart: monthStart, day: dayOfMonth, calendar: calendar).flatMap(at).map { [$0] } ?? []
        }
    }

    /// That day of the month, or nil when the month is too short.
    private static func date(monthStart: Date, day: Int, calendar: Calendar) -> Date? {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart), range.contains(day) else { return nil }
        return calendar.date(byAdding: .day, value: day - 1, to: monthStart)
    }

    private static func day(_ rule: OrdinalWeekday, inMonthStarting monthStart: Date, calendar: Calendar) -> Date? {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return nil }
        let matches = range.compactMap { day -> Date? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart),
                  calendar.component(.weekday, from: date) == rule.weekday else { return nil }
            return date
        }
        if rule.ordinal == -1 { return matches.last }
        return matches.indices.contains(rule.ordinal - 1) ? matches[rule.ordinal - 1] : nil
    }
}

// MARK: - Words

extension Repetition {
    /// The choices on the Repeat screen, in Calendar's order. Anything else
    /// is Custom.
    public static let presets: [(title: String, rule: Repetition)] = [
        ("Every Day", .daily),
        ("Every Week", .weekly),
        ("Every 2 Weeks", .biweekly),
        ("Every Month", .monthly),
        ("Every Year", .yearly),
    ]

    /// The preset this rule is, ignoring the end date. A weekly rule whose
    /// only day is the anchor's weekday is the plain "Every Week".
    public func preset(anchor: Date, calendar: Calendar = .current) -> Repetition? {
        var plain = self
        plain.endDate = nil
        if plain.frequency == .weekly, plain.weekdays == [calendar.component(.weekday, from: anchor)] {
            plain.weekdays = []
        }
        return Self.presets.map(\.rule).first { $0 == plain }
    }

    /// "Every Day", "Every 2 Weeks on Monday and Wednesday", "Monthly on the
    /// first Monday". Shown on the Repeat row, the list and "Send this text?".
    public func summary(anchor: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if let preset = preset(anchor: anchor, calendar: calendar),
           let title = Self.presets.first(where: { $0.rule == preset })?.title {
            return title
        }
        let n = max(interval, 1)
        let noun: String
        switch frequency {
        case .daily: noun = n == 1 ? "Day" : "\(n) Days"
        case .weekly: noun = n == 1 ? "Week" : "\(n) Weeks"
        case .monthly: noun = n == 1 ? "Month" : "\(n) Months"
        case .yearly: noun = n == 1 ? "Year" : "\(n) Years"
        }
        var text = "Every \(noun)"
        switch frequency {
        case .weekly:
            let days = weekdays.isEmpty ? [calendar.component(.weekday, from: anchor)] : weekdays
            text += " on " + Self.weekdayList(days, calendar: calendar, locale: locale)
        case .monthly:
            if let monthlyWeekday {
                text += " on the " + Self.ordinalName(monthlyWeekday.ordinal) + " "
                    + Self.weekdayName(monthlyWeekday.weekday, locale: locale)
            } else {
                text += " on the " + Self.dayOrdinal(calendar.component(.day, from: anchor))
            }
        case .daily, .yearly:
            break
        }
        return text
    }

    /// Weekdays in the week's order for this calendar (Sunday first in the
    /// US), as Calendar numbers.
    public static func weekdayOrder(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    public static func weekdayName(_ weekday: Int, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.weekdaySymbols[weekday - 1]
    }

    public static func ordinalName(_ ordinal: Int) -> String {
        switch ordinal {
        case 1: return "first"
        case 2: return "second"
        case 3: return "third"
        case 4: return "fourth"
        default: return "last"
        }
    }

    /// 1st, 2nd, 3rd, 11th, 22nd.
    public static func dayOrdinal(_ day: Int) -> String {
        let suffix: String
        switch (day % 10, day % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(day)\(suffix)"
    }

    static func weekdayList(_ days: Set<Int>, calendar: Calendar, locale: Locale) -> String {
        let order = weekdayOrder(calendar: calendar)
        let names = order.filter(days.contains).map { weekdayName($0, locale: locale) }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + ", and " + names.last!
        }
    }
}
