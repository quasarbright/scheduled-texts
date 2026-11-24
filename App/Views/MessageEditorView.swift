import ScheduledTextsCore
import SwiftUI

/// Create a new scheduled text, or change one.
struct MessageEditorView: View {
    let existing: ScheduledMessage?

    @EnvironmentObject private var store: MessageStore
    @EnvironmentObject private var router: Router

    @ObservedObject private var directory = ContactDirectory.shared

    /// The contact picked in the "To" field.
    @State private var recipient: ChosenRecipient?
    /// What's typed in the "To" field. Used as the address when no contact
    /// is picked, so a typed number can be saved as is.
    @State private var query: String
    @State private var text: String
    @State private var sendAt: Date
    @FocusState private var focus: EditorField?

    private let id: UUID

    init(existing: ScheduledMessage?) {
        self.existing = existing
        id = existing?.id ?? UUID()
        if let existing, let name = existing.recipientName {
            _recipient = State(initialValue: ChosenRecipient(
                name: name,
                address: existing.recipientAddress,
                contactID: existing.contactIdentifier
            ))
            _query = State(initialValue: "")
        } else {
            _recipient = State(initialValue: nil)
            _query = State(initialValue: existing?.recipientAddress ?? "")
        }
        _text = State(initialValue: existing?.body ?? "")
        _sendAt = State(initialValue: existing?.sendAt ?? Self.defaultSendTime())
    }

    /// An hour from now, on the minute.
    private static func defaultSendTime() -> Date {
        Date().addingTimeInterval(60 * 60).truncatedToMinute()
    }

    private var draft: ScheduledMessage {
        ScheduledMessage(
            id: id,
            recipientName: recipient?.name,
            contactIdentifier: recipient?.contactID,
            recipientAddress: recipient?.address ?? query,
            body: text,
            sendAt: sendAt
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RecipientField(
                        recipient: $recipient,
                        query: $query,
                        focus: $focus,
                        directory: directory
                    )
                } footer: {
                    if directory.access == .denied && recipient == nil {
                        Text("Names won't autocomplete without Contacts access. You can turn it on in Settings.")
                    }
                }

                Section("Message") {
                    TextField("Message", text: $text, axis: .vertical)
                        .focused($focus, equals: .message)
                        .lineLimit(3...12)
                }

                Section {
                    DatePicker("Remind me at", selection: $sendAt)
                } header: {
                    Text("When")
                } footer: {
                    if sendAt <= Date() {
                        Text("That time has passed, so this text will be ready to send right away.")
                    } else {
                        Text("You'll get a notification asking whether to send it.")
                    }
                }

                if let existing {
                    Section {
                        Button("Delete Text", role: .destructive) {
                            store.delete(id: existing.id)
                            router.close()
                        }
                    }
                }
            }
            .onAppear {
                directory.refresh()
                directory.load()
            }
            .task {
                // Start in the "To" field for a new text, like Messages.
                // Focusing during the sheet's slide-up animation is ignored.
                guard existing == nil else { return }
                try? await Task.sleep(nanoseconds: 450_000_000)
                focus = .to
            }
            .navigationTitle(existing == nil ? "New Text" : "Edit Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { router.close() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.save(draft)
                        router.close()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    private var hasChanges: Bool {
        guard let existing else { return !text.isEmpty || recipient != nil || !query.isEmpty }
        return draft.normalized() != existing
    }
}
