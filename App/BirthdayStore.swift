import Combine
import Foundation
import ScheduledTextsCore

/// Birthday Texts: the setting, and keeping the yearly texts in the list in
/// line with it and with Contacts.
@MainActor
final class BirthdayStore: ObservableObject {
    static let shared = BirthdayStore()

    @Published var settings: BirthdaySettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            sync()
        }
    }

    /// Everyone in Contacts with a birthday and something to text,
    /// soonest birthday first.
    @Published private(set) var contacts: [BirthdayContact] = []

    private let defaults: UserDefaults
    private static let key = "birthdaySettings"
    private var cancellables: Set<AnyCancellable> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(BirthdaySettings.self, from: data) {
            settings = saved
        } else {
            settings = BirthdaySettings()
        }
        ContactDirectory.shared.$contacts
            .sink { [weak self] cards in
                self?.contactsChanged(cards)
            }
            .store(in: &cancellables)
    }

    /// Reads Contacts again (when the app comes to the front), without
    /// asking for access. Birthdays and the prompt need access already given.
    func refresh() {
        let directory = ContactDirectory.shared
        directory.refresh()
        directory.loadIfAllowed()
    }

    private func contactsChanged(_ cards: [ContactCard]) {
        let now = Date()
        // Keep the card that already has a birthday text or its own message,
        // so deduping never moves someone's text to a different card.
        let preferred = Set(MessageStore.shared.queue.messages.compactMap(\.birthdayContactID))
            .union(settings.customMessages.keys)
        contacts = BirthdayContact.deduplicated(cards, preferring: preferred).sorted {
            ($0.nextBirthdayDay(from: now) ?? .distantFuture, $0.name) < ($1.nextBirthdayDay(from: now) ?? .distantFuture, $1.name)
        }
        sync()
    }

    /// Adds, updates and removes birthday texts. Does nothing until contacts
    /// have loaded, so a slow load never wipes the texts.
    func sync() {
        // Turning it off needs no contacts: every birthday text goes.
        guard !settings.enabled
                || (ContactDirectory.shared.access == .granted && !ContactDirectory.shared.contacts.isEmpty)
        else { return }
        var updated = settings
        let store = MessageStore.shared
        let queue = BirthdayPlanner.reconcile(queue: store.queue, contacts: contacts, settings: &updated, now: Date())
        if updated != settings { settings = updated }
        store.replaceQueue(queue)
    }

    /// Turns it on, asking for Contacts access first if needed.
    func turnOn() {
        settings.enabled = true
        ContactDirectory.shared.load()
    }

    // MARK: - Per person

    /// Saving a birthday text from the editor: a message other than the
    /// default becomes that person's own message.
    func edited(_ message: ScheduledMessage) {
        guard let id = message.birthdayContactID else { return }
        let body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body == settings.message || body.isEmpty {
            settings.customMessages[id] = nil
        } else {
            settings.customMessages[id] = body
        }
    }

    /// Stop Repeating on someone's birthday text turns them off, so it
    /// doesn't come back on the next sync.
    func stopped(contactID: String) {
        settings.excluded.insert(contactID)
    }

    /// Undo of Stop Repeating.
    func restarted(contactID: String) {
        settings.excluded.remove(contactID)
    }

    func setIncluded(_ id: String, _ included: Bool) {
        if included { settings.excluded.remove(id) } else { settings.excluded.insert(id) }
    }

    func selectAll(_ on: Bool) {
        settings.excluded = on ? [] : Set(contacts.map(\.id))
    }

    // MARK: - Prompt card

    func prompt(queue: MessageQueue, now: Date) -> (contact: BirthdayContact, day: Date)? {
        BirthdayPlanner.prompt(contacts: contacts, queue: queue, settings: settings, now: now)
    }

    func dismissPrompt(_ contact: BirthdayContact, day: Date) {
        settings.dismissedPrompts.insert(BirthdayPlanner.promptKey(contact.id, day: day))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
