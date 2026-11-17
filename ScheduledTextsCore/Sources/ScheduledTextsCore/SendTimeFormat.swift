import Foundation

/// How a send time reads in the app: "Today, 4:01 PM", "Tomorrow, 9:00 AM",
/// "Nov 23, 10:15 AM", and the year only when it isn't this year.
public enum SendTimeFormat {
    public static func string(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let time = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .hour().minute())
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0

        switch offset {
        case 0: return "Today, \(time)"
        case 1: return "Tomorrow, \(time)"
        case -1: return "Yesterday, \(time)"
        default:
            var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .month(.abbreviated).day()
            if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
                style = style.year()
            }
            return "\(date.formatted(style)), \(time)"
        }
    }
}
