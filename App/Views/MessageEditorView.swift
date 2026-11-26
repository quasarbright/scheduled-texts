import ScheduledTextsCore
import SwiftUI

/// Create a new scheduled text, or change one.
struct MessageEditorView: View {
    let existing: ScheduledMessage?
    /// What a filled-in new text started as, so Cancel only asks once
    /// something was changed.
    let template: ScheduledMessage?

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
    @State private var repetition: Repetition?
    /// The repeating text being asked about by Don't Send.
    @State private var askingDontSend: ScheduledMessage?
    /// Which field has the keyboard, if any.
    @FocusState private var focus: EditorField?
    @State private var confirmingDiscard = false

    private let id: UUID

    /// Fills in a new text, as "Schedule for Kate" does. Still a new text:
    /// Cancel throws it away.
    init(existing: ScheduledMessage?, template: ScheduledMessage? = nil) {
        self.existing = existing
        self.template = template
        let source = existing ?? template
        id = source?.id ?? UUID()
        if let source, let name = source.recipientName {
            _recipient = State(initialValue: ChosenRecipient(
                name: name,
                address: source.recipientAddress,
                contactID: source.contactIdentifier
            ))
            _query = State(initialValue: "")
        } else {
            _recipient = State(initialValue: nil)
            _query = State(initialValue: source?.recipientAddress ?? "")
        }
        _text = State(initialValue: source?.body ?? "")
        _sendAt = State(initialValue: source?.sendAt ?? Self.defaultSendTime())
        _repetition = State(initialValue: source?.repetition)
    }

    /// An hour from now, on the minute.
    private static func defaultSendTime() -> Date {
        Date().addingTimeInterval(60 * 60).truncatedToMinute()
    }

    private var draft: ScheduledMessage {
        // A repeating text keeps its place in the schedule unless the time
        // or the repeat changed, which starts the schedule over from here.
        let keepsSchedule = existing.map {
            $0.sendAt == sendAt.truncatedToMinute() && $0.repetition == repetition
        } ?? false
        return ScheduledMessage(
            id: id,
            recipientName: recipient?.name,
            contactIdentifier: recipient?.contactID,
            recipientAddress: recipient?.address ?? query,
            body: text,
            sendAt: sendAt,
            repetition: repetition,
            seriesAnchor: keepsSchedule ? existing?.seriesAnchor : nil,
            occurrence: keepsSchedule ? existing?.occurrence : nil,
            // A birthday text stays one while only its message changes.
            // Moving it or changing the repeat makes it a text of your own.
            birthdayContactID: keepsSchedule ? existing?.birthdayContactID : nil
        )
    }

    @ObservedObject private var birthdays = BirthdayStore.shared

    var body: some View {
        NavigationStack {
            Form {
                if let contactID = existing?.birthdayContactID {
                    Section {
                        Label {
                            Text("Birthday text. Changes here are just for \(firstName).")
                        } icon: {
                            Image(systemName: "birthday.cake").foregroundStyle(.pink)
                        }
                        .font(.subheadline)
                        if text.trimmingCharacters(in: .whitespacesAndNewlines) != birthdays.settings.message {
                            Button("Use Default Message") {
                                text = birthdays.settings.message
                            }
                        }
                    } footer: {
                        if draft.birthdayContactID == nil {
                            Text("Changing the time or repeat makes this your own text, and \(firstName) won't get the birthday text from Settings.")
                        }
                    }
                    .id(contactID)
                }

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
                    TextField("What do you want to say?", text: $text, axis: .vertical)
                        .lineLimit(3...12)
                        .focused($focus, equals: .message)
                }

                Section {
                    DatePicker("Remind me at", selection: $sendAt)
                    NavigationLink {
                        RepeatPicker(repetition: $repetition, anchor: draft.anchor)
                    } label: {
                        LabeledContent("Repeat", value: draft.repeatSummary() ?? "Never")
                    }
                    if repetition != nil {
                        NavigationLink {
                            EndRepeatPicker(repetition: $repetition, anchor: draft.anchor)
                        } label: {
                            LabeledContent(
                                "End Repeat",
                                value: repetition?.endDate?.formatted(date: .abbreviated, time: .omitted) ?? "Never"
                            )
                        }
                    }
                } header: {
                    Text("When")
                } footer: {
                    if sendAt > Date() {
                        Text("You'll get a notification asking whether to send it.")
                    } else if let existing, existing.isDue(at: Date()) {
                        Text("This text is ready to send now.")
                    } else {
                        Text("That time has passed, so this text will be ready to send right away.")
                    }
                }

                if let existing {
                    Section {
                        // Sends this one now instead of waiting. Any edits
                        // are saved first, so the compose sheet gets them.
                        Button {
                            sendNow()
                        } label: {
                            Label("Send Now", systemImage: "paperplane.fill")
                        }
                        .disabled(!draft.isValid)

                        Button(role: .destructive) {
                            if store.dontSendIfOneOff(existing) {
                                router.close()
                            } else {
                                askingDontSend = existing
                            }
                        } label: {
                            // A form tints the icon blue unless told otherwise.
                            Label("Don't Send", systemImage: "xmark")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .dontSendDialog(asking: $askingDontSend, store: store) {
                router.close()
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
            // Return adds a new line in the message, so the keyboard needs
            // another way out, or it covers the time picker.
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(existing == nil ? "New Text" : "Edit Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges {
                            confirmingDiscard = true
                        } else {
                            closeEditor()
                        }
                    }
                    .confirmationDialog(
                        existing == nil ? "Discard this text?" : "Discard your changes?",
                        isPresented: $confirmingDiscard,
                        titleVisibility: .visible
                    ) {
                        Button("Discard", role: .destructive) { closeEditor() }
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDraft()
                        router.closeEditor(stillDue: draft.isDue(at: Date()))
                    }
                    .disabled(!draft.isValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    /// Saves any edits, closes the editor and opens the prefilled compose
    /// sheet. The text leaves the list once it's sent, like the Send
    /// button and the swipe action.
    private func sendNow() {
        if hasChanges {
            saveDraft()
        }
        router.open(.send(id))
    }

    /// Saves, and keeps Birthday Texts in step: a new message becomes this
    /// person's own; a moved birthday text stops being one.
    private func saveDraft() {
        let message = draft
        store.save(message)
        if let contactID = existing?.birthdayContactID {
            if message.birthdayContactID == nil {
                birthdays.stopped(contactID: contactID)
            } else {
                birthdays.edited(message)
            }
        }
    }

    private var firstName: String {
        let name = existing?.displayRecipient ?? ""
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    /// Leaves without saving: back to "Send this text?" if that's where the
    /// editor was opened from, otherwise to the list.
    private func closeEditor() {
        router.closeEditor(stillDue: existing?.isDue(at: Date()) ?? false)
    }

    private var hasChanges: Bool {
        if existing == nil, var template {
            // A new text has no place in a schedule yet, so compare only
            // what you can see and change.
            template.seriesAnchor = nil
            template.occurrence = nil
            template.birthdayContactID = nil
            return draft.normalized() != template.normalized()
        }
        guard let existing else { return !text.isEmpty || recipient != nil || !query.isEmpty }
        return draft.normalized() != existing
    }
}
