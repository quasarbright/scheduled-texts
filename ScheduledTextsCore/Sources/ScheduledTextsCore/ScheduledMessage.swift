import Foundation

/// A text the person wants to send later.
///
/// The app never sends on its own: iOS only lets an app open a prefilled
/// compose sheet, and the person has to tap Send there. So a message stays
/// in the queue until it's sent or deleted.
public struct ScheduledMessage: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    /// Display name, for example from Contacts. Nil when the person typed a number.
    public var recipientName: String?
    /// The Contacts identifier of the person, when they were picked from
    /// Contacts. Lets the editor offer their other numbers later.
    /// Missing in texts saved before this existed.
    public var contactIdentifier: String?
    /// The phone number or email address the compose sheet sends to.
    /// iMessage and SMS both go through the same compose sheet.
    public var recipientAddress: String
    public var body: String
    /// When to ask. Remind Me Later moves this.
    public var sendAt: Date
    /// How the text repeats. Nil sends it once.
    public var repetition: Repetition?
    /// The start of the repeat schedule, which sets the pattern (the day of
    /// the month, every other week). Nil means `scheduledAt`.
    public var seriesAnchor: Date?
    /// The time this text was due before Remind Me Later moved it, so the
    /// next repeat keeps to the schedule. Nil means `sendAt`.
    public var occurrence: Date?

    public init(
        id: UUID = UUID(),
        recipientName: String? = nil,
        contactIdentifier: String? = nil,
        recipientAddress: String,
        body: String,
        sendAt: Date,
        repetition: Repetition? = nil,
        seriesAnchor: Date? = nil,
        occurrence: Date? = nil
    ) {
        self.id = id
        self.recipientName = recipientName
        self.contactIdentifier = contactIdentifier
        self.recipientAddress = recipientAddress
        self.body = body
        self.sendAt = sendAt
        self.repetition = repetition
        self.seriesAnchor = seriesAnchor
        self.occurrence = occurrence
    }

    /// When this one was due on the schedule, before any Remind Me Later.
    public var scheduledAt: Date { occurrence ?? sendAt }

    /// Where the repeat schedule starts.
    public var anchor: Date { seriesAnchor ?? scheduledAt }

    /// The same text moved to a later time by Remind Me Later. A repeating
    /// text remembers when it was due, so the next one stays on schedule.
    public func reminded(at date: Date) -> ScheduledMessage {
        var copy = self
        if repetition != nil {
            copy.occurrence = scheduledAt
            copy.seriesAnchor = anchor
        }
        copy.sendAt = date
        return copy
    }

    /// The next text in the series once this one is sent or skipped at
    /// `now`. Nil when it doesn't repeat or the repeat has ended. Texts
    /// missed while it waited aren't queued up; it picks up at the next
    /// time after now.
    public func nextInSeries(now: Date, calendar: Calendar = .current) -> ScheduledMessage? {
        guard let repetition,
              let next = repetition.nextOccurrence(after: max(scheduledAt, now), anchor: anchor, calendar: calendar)
        else { return nil }
        var copy = self
        copy.seriesAnchor = anchor
        copy.occurrence = nil
        copy.sendAt = next
        return copy
    }

    /// "Every Week", or nil for a text that doesn't repeat.
    public func repeatSummary(calendar: Calendar = .current, locale: Locale = .current) -> String? {
        repetition?.summary(anchor: anchor, calendar: calendar, locale: locale)
    }

    /// The name if there is one, otherwise the number or address.
    public var displayRecipient: String {
        if let name = recipientName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return recipientAddress
    }

    /// True once the send time has arrived. A due message waits for the
    /// person to send it; it doesn't expire.
    public func isDue(at now: Date) -> Bool {
        sendAt <= now
    }

    /// Search on the main list: true when every word of `query` is in the
    /// text, the name or the address, ignoring case and accents. Digits
    /// also match a phone number however it's punctuated, so "5551234"
    /// finds "(555) 123-4567".
    public func matches(search query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let fields = [body, recipientName ?? "", recipientAddress]
        let addressDigits = recipientAddress.filter(\.isNumber)
        return words.allSatisfy { word in
            if fields.contains(where: { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
                return true
            }
            let digits = word.filter(\.isNumber)
            return !digits.isEmpty && digits.count == word.filter { !"()-+.".contains($0) }.count
                && addressDigits.contains(digits)
        }
    }

    /// A message needs someone to send to and something to say.
    public var isValid: Bool {
        !recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A copy with surrounding whitespace removed from the address and body,
    /// and the send time rounded down to the minute (the date picker has
    /// minute precision, so stray seconds would only be confusing).
    public func normalized(calendar: Calendar = .current) -> ScheduledMessage {
        var copy = self
        copy.recipientAddress = recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sendAt = sendAt.truncatedToMinute(calendar: calendar)
        copy.seriesAnchor = seriesAnchor?.truncatedToMinute(calendar: calendar)
        copy.occurrence = occurrence?.truncatedToMinute(calendar: calendar)
        if var repetition {
            repetition.interval = max(repetition.interval, 1)
            if repetition.frequency != .weekly { repetition.weekdays = [] }
            if repetition.frequency != .monthly { repetition.monthlyWeekday = nil }
            copy.repetition = repetition
        } else {
            copy.seriesAnchor = nil
            copy.occurrence = nil
        }
        if let name = recipientName?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.recipientName = name.isEmpty ? nil : name
        }
        return copy
    }
}

extension Date {
    /// This date with its seconds and fractional seconds dropped.
    public func truncatedToMinute(calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        return calendar.date(from: parts) ?? self
    }
}
