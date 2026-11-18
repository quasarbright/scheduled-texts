import Foundation

/// "Remind Me Later" choices, the same in the app and on the notification.
public enum RemindLater: String, CaseIterable, Identifiable {
    case inAnHour
    case tonight
    case tomorrowMorning

    public var id: String { rawValue }

    /// "Tonight" means this hour today.
    public static let tonightHour = 20
    /// "Tomorrow Morning" means this hour.
    public static let morningHour = 9

    /// The label in the app's Remind Me Later menu.
    public var title: String {
        switch self {
        case .inAnHour: return "In 1 Hour"
        case .tonight: return "Tonight"
        case .tomorrowMorning: return "Tomorrow Morning"
        }
    }

    /// The button on the notification, which can't show a menu under a
    /// "Remind Me Later" heading, so each choice says it in full.
    public var notificationTitle: String {
        switch self {
        case .inAnHour: return "Remind Me in 1 Hour"
        case .tonight: return "Remind Me Tonight"
        case .tomorrowMorning: return "Remind Me Tomorrow Morning"
        }
    }

    /// The choices that make sense at `now`. "Tonight" goes away once it's
    /// less than an hour before tonight's time, where it would be no later
    /// than "In 1 Hour".
    public static func options(at now: Date, calendar: Calendar = .current) -> [RemindLater] {
        allCases.filter { $0 != .tonight || offersTonight(at: now, calendar: calendar) }
    }

    public static func offersTonight(at now: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: now) < tonightHour - 1
    }

    /// When to ask again, on the minute.
    public func date(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .inAnHour:
            return now.addingTimeInterval(60 * 60).truncatedToMinute(calendar: calendar)
        case .tonight:
            return calendar.date(bySettingHour: Self.tonightHour, minute: 0, second: 0, of: now)!
        case .tomorrowMorning:
            // In the small hours, "tomorrow morning" is this morning.
            let day = calendar.component(.hour, from: now) < 5
                ? now
                : calendar.date(byAdding: .day, value: 1, to: now)!
            return calendar.date(bySettingHour: Self.morningHour, minute: 0, second: 0, of: day)!
        }
    }
}
