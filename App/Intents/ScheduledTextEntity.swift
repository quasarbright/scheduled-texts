import AppIntents
import ScheduledTextsCore

/// A text in the list, for "What's scheduled?" and Shortcuts.
struct ScheduledTextEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Scheduled Text"
    static var defaultQuery = ScheduledTextQuery()

    var id: UUID

    @Property(title: "To")
    var recipient: String

    @Property(title: "Message")
    var message: String

    @Property(title: "When")
    var sendAt: Date

    @Property(title: "Ready to Send")
    var isReady: Bool

    init(_ text: ScheduledMessage, now: Date = Date()) {
        id = text.id
        recipient = text.displayRecipient
        message = text.body
        sendAt = text.sendAt
        isReady = text.isDue(at: now)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(recipient)",
            subtitle: "\(SendTimeFormat.string(for: sendAt)) · \(message)"
        )
    }
}

struct ScheduledTextQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ScheduledTextEntity] {
        identifiers.compactMap { MessageStore.shared.message(id: $0).map { ScheduledTextEntity($0) } }
    }

    @MainActor
    func suggestedEntities() async throws -> [ScheduledTextEntity] {
        MessageStore.shared.queue.messages.map { ScheduledTextEntity($0) }
    }
}
