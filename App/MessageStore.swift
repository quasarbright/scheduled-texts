import Foundation
import ScheduledTextsCore

/// The app's copy of the queue. Saves to disk and updates notifications
/// after every change.
@MainActor
final class MessageStore: ObservableObject {
    static let shared = MessageStore()

    @Published private(set) var queue: MessageQueue

    private let fileURL: URL
    private var syncTask: Task<Void, Never>?

    init(fileURL: URL = MessageStore.defaultFileURL) {
        self.fileURL = fileURL
        do {
            queue = try MessageStorage.load(from: fileURL)
        } catch {
            // Keep the unreadable file around rather than overwrite it on
            // the next save.
            print("Couldn't read \(fileURL.path): \(error)")
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            queue = MessageQueue()
        }
    }

    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("messages.json")
    }

    func message(id: UUID) -> ScheduledMessage? {
        queue.message(id: id)
    }

    /// Adds a new message or saves changes to an existing one.
    func save(_ message: ScheduledMessage) {
        queue.upsert(message.normalized())
        persist()
        resync()
    }

    /// The last change the person can undo, and what it said it did.
    struct UndoableChange: Equatable {
        let id = UUID()
        let summary: String
        /// The text as it was before. Saving it again undoes the change.
        let previous: ScheduledMessage
    }

    @Published private(set) var lastChange: UndoableChange?

    /// Removes a text. `undoable` is false when nobody's looking (a
    /// notification action), so no Undo shows up later.
    func delete(id: UUID, undoable: Bool = true) {
        guard let removed = queue.remove(id: id) else { return }
        lastChange = undoable
            ? UndoableChange(summary: "Won't send to \(removed.displayRecipient)", previous: removed)
            : nil
        persist()
        resync()
    }

    /// Moves a text to a Remind Me Later time.
    func remindLater(id: UUID, _ option: RemindLater, undoable: Bool = true, now: Date = Date()) {
        guard var message = queue.message(id: id) else { return }
        let previous = message
        message.sendAt = option.date(from: now)
        save(message)
        lastChange = undoable
            ? UndoableChange(
                summary: "Asking again \(SendTimeFormat.string(for: message.sendAt, now: now))",
                previous: previous
            )
            : nil
    }

    /// Puts back the text as it was before the last change.
    func undo() {
        guard let change = lastChange else { return }
        lastChange = nil
        save(change.previous)
    }

    func dismissUndo() {
        lastChange = nil
    }

    /// The person tapped Send in the compose sheet, so the text is done.
    func markSent(id: UUID) {
        delete(id: id, undoable: false)
    }

    /// Brings notifications and the badge up to date. Syncs run one at a
    /// time and each one reads the queue when it starts, so the last one
    /// always reflects the latest state.
    @discardableResult
    func resync() -> Task<Void, Never> {
        let previous = syncTask
        let task = Task {
            await previous?.value
            await NotificationScheduler.sync(with: self.queue)
        }
        syncTask = task
        return task
    }

    func waitForSync() async {
        await syncTask?.value
    }

    private func persist() {
        do {
            try MessageStorage.save(queue, to: fileURL)
        } catch {
            print("Couldn't save messages: \(error)")
        }
    }
}
