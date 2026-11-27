import Foundation

/// The Birthday Texts setting: one switch that gives everyone with a
/// birthday in Contacts a yearly text, with a default message and time.
public struct BirthdaySettings: Codable, Equatable {
    public static let defaultMessage = "Happy birthday!"

    public var enabled = false
    public var message = BirthdaySettings.defaultMessage
    /// When to ask, on the birthday.
    public var hour = 9
    public var minute = 0
    /// Whether people who get a birthday in Contacts later get a text too.
    public var addNewBirthdays = true
    /// People turned off in Settings > People.
    public var excluded: Set<String> = []
    /// Everyone seen with a birthday so far, so a new one can be told apart
    /// when Add New Birthdays is off.
    public var known: Set<String> = []
    /// One person's own message, made by editing their birthday text.
    public var customMessages: [String: String] = [:]
    /// Birthdays whose prompt card was closed, as "contactID:year".
    public var dismissedPrompts: Set<String> = []

    public init() {}

    public func message(for contactID: String) -> String {
        customMessages[contactID] ?? message
    }

    public func isIncluded(_ contactID: String) -> Bool {
        !excluded.contains(contactID)
    }
}

/// Someone in Contacts with a birthday and something to text.
public struct BirthdayContact: Equatable, Identifiable {
    public var id: String
    public var name: String
    public var address: String
    public var month: Int
    public var day: Int

    public init(id: String, name: String, address: String, month: Int, day: Int) {
        self.id = id
        self.name = name
        self.address = address
        self.month = month
        self.day = day
    }

    public init?(card: ContactCard) {
        guard let birthday = card.birthday, let month = birthday.month, let day = birthday.day,
              let address = card.defaultAddress else { return nil }
        self.init(id: card.id, name: card.name, address: address.value, month: month, day: day)
    }

    /// The next birthday at `hour:minute` strictly after `now`. A Feb 29
    /// birthday is on Feb 28 in other years, like most calendars do.
    public func nextBirthday(after now: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Date? {
        let year = calendar.component(.year, from: now)
        for y in year...(year + 1) {
            guard let date = birthday(in: y, calendar: calendar),
                  let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) else { continue }
            if time > now { return time }
        }
        return nil
    }

    /// The day of the birthday in `year`.
    public func birthday(in year: Int, calendar: Calendar = .current) -> Date? {
        var d = day
        if month == 2 && day == 29,
           let feb = calendar.date(from: DateComponents(year: year, month: 2)),
           calendar.range(of: .day, in: .month, for: feb)?.count == 28 {
            d = 28
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: d))
    }

    /// The day of the next birthday, counting today.
    public func nextBirthdayDay(from now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: now)
        return (year...(year + 1)).lazy.compactMap { self.birthday(in: $0, calendar: calendar) }.first { $0 >= today }
    }
}

public enum BirthdayPlanner {
    /// Brings the birthday texts in `queue` in line with the setting and
    /// Contacts: adds a yearly text for each included person who lacks one,
    /// updates messages and times, and removes texts for people who are
    /// turned off, gone from Contacts, or when the setting is off. Also
    /// records newly seen birthdays in `settings`.
    ///
    /// A text that's ready to send is left alone apart from its message, so
    /// changing a setting never makes one disappear before it's sent.
    /// Where a birthday text belongs: the next birthday at the set time, or
    /// the one a year after that when this year's was skipped (Don't Send >
    /// Skip This One). Only one year on: a yearly repeat from Feb 29 jumps
    /// four years, and that should still come back to the next birthday.
    static func birthdayTime(
        for message: ScheduledMessage,
        contact: BirthdayContact,
        settings: BirthdaySettings,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard let next = contact.nextBirthday(after: now, hour: settings.hour, minute: settings.minute, calendar: calendar) else { return nil }
        let year = calendar.component(.year, from: message.sendAt)
        guard year == calendar.component(.year, from: next) + 1,
              let day = contact.birthday(in: year, calendar: calendar),
              let later = calendar.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day)
        else { return next }
        return later
    }

    public static func reconcile(
        queue: MessageQueue,
        contacts: [BirthdayContact],
        settings: inout BirthdaySettings,
        now: Date,
        calendar: Calendar = .current
    ) -> MessageQueue {
        var queue = queue
        let ids = Set(contacts.map(\.id))
        if settings.enabled {
            let new = ids.subtracting(settings.known)
            if !settings.addNewBirthdays && !settings.known.isEmpty {
                settings.excluded.formUnion(new)
            }
            settings.known.formUnion(ids)
        }

        // Remove birthday texts that shouldn't exist.
        for message in queue.messages {
            guard let id = message.birthdayContactID else { continue }
            let keep = settings.enabled && ids.contains(id) && settings.isIncluded(id)
            if !keep && !message.isDue(at: now) {
                queue.remove(id: message.id)
            } else if !keep {
                // Ready to send: it stays until it's sent or skipped, but
                // won't come back next year.
                var copy = message
                copy.repetition = nil
                copy.seriesAnchor = nil
                copy.occurrence = nil
                copy.birthdayContactID = nil
                queue.upsert(copy)
            }
        }
        guard settings.enabled else { return queue }

        for contact in contacts where settings.isIncluded(contact.id) {
            let body = settings.message(for: contact.id)
            if var existing = queue.messages.first(where: { $0.birthdayContactID == contact.id }) {
                let before = existing
                existing.body = body
                existing.recipientName = contact.name
                // Keep it on the next birthday at the set time. Not when it's
                // ready, or moved by Remind Me Later. This also moves a
                // Feb 29 birthday between Feb 28 and Feb 29 each year.
                if !existing.isDue(at: now) && existing.occurrence == nil,
                   let next = Self.birthdayTime(for: existing, contact: contact, settings: settings, now: now, calendar: calendar),
                   next != existing.sendAt {
                    existing.sendAt = next
                    existing.seriesAnchor = next
                }
                if existing != before { queue.upsert(existing) }
                continue
            }
            // Someone who already has a yearly text on their birthday that
            // they wrote by hand (say from "Schedule for Kate") keeps that one.
            if queue.messages.contains(where: { isHandmadeBirthdayText($0, for: contact, calendar: calendar) }) {
                continue
            }
            guard let next = contact.nextBirthday(after: now, hour: settings.hour, minute: settings.minute, calendar: calendar) else { continue }
            queue.upsert(ScheduledMessage(
                recipientName: contact.name,
                contactIdentifier: contact.id,
                recipientAddress: contact.address,
                body: body,
                sendAt: next,
                repetition: .yearly,
                seriesAnchor: next,
                birthdayContactID: contact.id
            ))
        }
        return queue
    }

    static func isHandmadeBirthdayText(_ message: ScheduledMessage, for contact: BirthdayContact, calendar: Calendar) -> Bool {
        guard message.birthdayContactID == nil,
              message.contactIdentifier == contact.id,
              message.repetition?.frequency == .yearly else { return false }
        let parts = calendar.dateComponents([.month, .day], from: message.anchor)
        return parts.month == contact.month && parts.day == contact.day
    }

    /// The prompt card on the list while Birthday Texts is off: the soonest
    /// birthday from today through 7 days from now that has no text yet and
    /// whose card wasn't closed. Only ever shown in the app.
    public static func prompt(
        contacts: [BirthdayContact],
        queue: MessageQueue,
        settings: BirthdaySettings,
        now: Date,
        calendar: Calendar = .current
    ) -> (contact: BirthdayContact, day: Date)? {
        guard !settings.enabled else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: 7, to: today) else { return nil }
        var best: (contact: BirthdayContact, day: Date)?
        for contact in contacts {
            guard let day = contact.nextBirthdayDay(from: now, calendar: calendar), day <= horizon else { continue }
            if settings.dismissedPrompts.contains(promptKey(contact.id, day: day, calendar: calendar)) { continue }
            let hasText = queue.messages.contains { message in
                message.contactIdentifier == contact.id && calendar.isDate(message.sendAt, inSameDayAs: day)
            }
            if hasText { continue }
            if best == nil || day < best!.day
                || (day == best!.day && contact.name.localizedStandardCompare(best!.contact.name) == .orderedAscending) {
                best = (contact, day)
            }
        }
        return best
    }

    public static func promptKey(_ contactID: String, day: Date, calendar: Calendar = .current) -> String {
        "\(contactID):\(calendar.component(.year, from: day))"
    }

    /// The text "Schedule for Kate" opens in New Text: the birthday at the
    /// default time, every year, with the default message. It's a normal
    /// text, so it stays if Birthday Texts is turned on or off later.
    public static func handmadeText(
        for contact: BirthdayContact,
        settings: BirthdaySettings,
        now: Date,
        calendar: Calendar = .current
    ) -> ScheduledMessage? {
        guard let next = contact.nextBirthday(after: now, hour: settings.hour, minute: settings.minute, calendar: calendar) else { return nil }
        return ScheduledMessage(
            recipientName: contact.name,
            contactIdentifier: contact.id,
            recipientAddress: contact.address,
            body: settings.message,
            sendAt: next,
            repetition: .yearly,
            seriesAnchor: next
        )
    }
}

extension BirthdayContact {
    /// One birthday per person from the person's contact cards. The same
    /// person often has more than one card that Contacts didn't link (one
    /// from iCloud and one from Gmail, say), and each would get its own
    /// birthday text. Two cards are the same person when they share a
    /// birthday and either a name or a phone number or email.
    ///
    /// Of each group, it keeps the card in `preferred` (one that already has
    /// a birthday text or its own message), else the one with the most
    /// numbers and emails, else the first.
    public static func deduplicated(_ cards: [ContactCard], preferring preferred: Set<String> = []) -> [BirthdayContact] {
        struct Candidate { var card: ContactCard; var contact: BirthdayContact; var keys: Set<String> }
        let candidates: [Candidate] = cards.compactMap { card in
            guard let contact = BirthdayContact(card: card) else { return nil }
            let name = card.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var keys = Set(card.addresses.map { "a:" + ContactSearch.addressKey($0.value) }.filter { $0.count > 2 })
            if !name.isEmpty { keys.insert("n:" + name) }
            return Candidate(card: card, contact: contact, keys: keys)
        }

        // Union-find over cards that share a birthday and a key.
        var parent = Array(candidates.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        var owner: [String: Int] = [:]
        for (i, c) in candidates.enumerated() {
            for key in c.keys {
                let k = "\(c.contact.month)/\(c.contact.day)|\(key)"
                if let j = owner[k] { parent[root(i)] = root(j) } else { owner[k] = i }
            }
        }

        var best: [Int: Int] = [:]
        func better(_ a: Candidate, than b: Candidate) -> Bool {
            let ap = preferred.contains(a.card.id), bp = preferred.contains(b.card.id)
            if ap != bp { return ap }
            return a.card.addresses.count > b.card.addresses.count
        }
        for i in candidates.indices {
            let r = root(i)
            if let b = best[r], !better(candidates[i], than: candidates[b]) { continue }
            best[r] = i
        }
        return best.values.sorted().map { candidates[$0].contact }
    }
}
