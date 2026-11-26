import AppIntents
import SwiftUI
import ScheduledTextsCore

/// "What's scheduled in Scheduled Texts?": reads out how many are ready and
/// how many are later, and shows the next few. Also the Get Scheduled Texts
/// action in Shortcuts.
struct GetScheduledTextsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Scheduled Texts"
    static var description = IntentDescription("Lists the texts waiting to be sent, soonest first.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[ScheduledTextEntity]> & ProvidesDialog & ShowsSnippetView {
        let now = Date()
        let queue = MessageStore.shared.queue
        let ready = queue.due(at: now).count
        let later = queue.upcoming(at: now).count
        let entities = queue.messages.map { ScheduledTextEntity($0, now: now) }
        return .result(
            value: entities,
            dialog: IntentDialog(stringLiteral: Self.summary(ready: ready, later: later))
        ) {
            ScheduledTextsSnippet(texts: Array(queue.messages.prefix(5)), now: now, more: max(queue.messages.count - 5, 0))
        }
    }

    static func summary(ready: Int, later: Int) -> String {
        switch (ready, later) {
        case (0, 0): return "Nothing is scheduled."
        case (_, 0): return "You have \(ready) ready to send."
        case (0, _): return "Nothing is ready yet. You have \(later) scheduled."
        default: return "You have \(ready) ready to send and \(later) later."
        }
    }
}

/// Opens a text in the app: "Send this text?" when it's ready, otherwise
/// the editor.
struct OpenScheduledTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Scheduled Text"
    static var openAppWhenRun = true

    @Parameter(title: "Text")
    var text: ScheduledTextEntity

    init() {}

    init(text: ScheduledTextEntity) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let message = MessageStore.shared.message(id: text.id) else { return .result() }
        Router.shared.open(message.isDue(at: Date()) ? .review(message.id) : .edit(message.id))
        return .result()
    }
}

/// The next few texts, each a button that opens it.
struct ScheduledTextsSnippet: View {
    let texts: [ScheduledMessage]
    let now: Date
    let more: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(texts) { text in
                Button(intent: OpenScheduledTextIntent(text: ScheduledTextEntity(text, now: now))) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(text.displayRecipient).font(.headline)
                            Text(text.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(SendTimeFormat.string(for: text.sendAt, now: now))
                            .font(.subheadline)
                            .foregroundStyle(text.isDue(at: now) ? Color.orange : Color.secondary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if text.id != texts.last?.id { Divider() }
            }
            if more > 0 {
                Text("+\(more) more").font(.footnote).foregroundStyle(.secondary).padding(.top, 6)
            }
        }
        .padding()
    }
}

struct ScheduledTextsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScheduleTextIntent(),
            phrases: [
                "Schedule a text in \(.applicationName)",
                "Schedule a text with \(.applicationName)",
                "New text in \(.applicationName)",
                "New scheduled text in \(.applicationName)",
            ],
            shortTitle: "Schedule Text",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: GetScheduledTextsIntent(),
            phrases: [
                "What’s scheduled in \(.applicationName)",
                "What's scheduled in \(.applicationName)",
                "Show my \(.applicationName)",
                "Check \(.applicationName)",
            ],
            shortTitle: "What’s Scheduled",
            systemImageName: "list.bullet"
        )
    }
}
