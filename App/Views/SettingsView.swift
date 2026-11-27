import ScheduledTextsCore
import SwiftUI

/// Settings, from the gear on the list. For now it's one row: Birthdays.
struct SettingsView: View {
    @EnvironmentObject private var router: Router
    @ObservedObject private var birthdays = BirthdayStore.shared
    @State private var path: [SettingsPage] = []

    enum SettingsPage: Hashable { case birthdays }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    NavigationLink(value: SettingsPage.birthdays) {
                        LabeledContent {
                            Text(summary)
                        } label: {
                            Label {
                                Text("Birthdays")
                            } icon: {
                                Image(systemName: "birthday.cake").foregroundStyle(.pink)
                            }
                        }
                    }
                } header: {
                    Text("Birthday Texts")
                } footer: {
                    Text("Text people on their birthdays, using the birthdays saved in Contacts.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsPage.self) { _ in
                BirthdaysView()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { router.close() }
                }
            }
            .onAppear {
                birthdays.refresh()
                // "Turn On for Everyone" goes straight to Birthdays, which
                // flips the switch where you can see it.
                if router.turnOnBirthdaysWhenShown { path = [.birthdays] }
            }
        }
    }

    private var summary: String {
        guard birthdays.settings.enabled else { return "Off" }
        let total = birthdays.contacts.count
        let included = birthdays.contacts.filter { birthdays.settings.isIncluded($0.id) }.count
        if total == 0 { return "On" }
        return included == total ? "All \(total)" : "\(included) of \(total)"
    }
}

/// Everything about birthday texts on one screen: the switch, the default
/// message and time, and who gets one. Opened from Settings and from the
/// Birthdays row on the list. The checkmark turns a person on or off;
/// tapping the rest of the row opens their text.
struct BirthdaysView: View {
    @EnvironmentObject private var store: MessageStore
    @EnvironmentObject private var router: Router
    @ObservedObject private var birthdays = BirthdayStore.shared
    @ObservedObject private var directory = ContactDirectory.shared

    /// The message as typed, saved when you leave the field or the screen,
    /// not on every keystroke.
    @State private var message = ""
    @FocusState private var editingMessage: Bool
    /// The birthday text open in the editor.
    @State private var editing: ScheduledMessage?

    var body: some View {
        let now = Date()
        let soon = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        let on = birthdays.settings.enabled
        let comingUp = on ? birthdays.contacts.filter { ($0.nextBirthdayDay(from: now) ?? .distantFuture) <= soon } : []
        let later = on ? birthdays.contacts.filter { ($0.nextBirthdayDay(from: now) ?? .distantFuture) > soon } : []
        let allIncluded = birthdays.contacts.allSatisfy { birthdays.settings.isIncluded($0.id) }

        List {
            Section {
                Toggle(isOn: Binding(
                    get: { birthdays.settings.enabled },
                    set: { on in
                        withAnimation {
                            if on { birthdays.turnOn() } else { birthdays.settings.enabled = false }
                        }
                    }
                )) {
                    Label {
                        Text("Birthday Texts")
                    } icon: {
                        Image(systemName: "birthday.cake").foregroundStyle(.pink)
                    }
                }
                if on {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Message").font(.footnote).foregroundStyle(.secondary).textCase(.uppercase)
                        TextField(BirthdaySettings.defaultMessage, text: $message, axis: .vertical)
                            .lineLimit(1...6)
                            .focused($editingMessage)
                            .onSubmit(commitMessage)
                    }
                    DatePicker("Remind me at", selection: time, displayedComponents: .hourAndMinute)
                    Toggle("Add New Birthdays", isOn: $birthdays.settings.addNewBirthdays)
                }
            } footer: {
                Text(footer)
            }
            // Enable All / Disable All sits on the first section's header,
            // next to the list it acts on.
            if !comingUp.isEmpty {
                Section {
                    ForEach(comingUp) { row($0, now: now) }
                } header: {
                    header("Coming Up", allIncluded: allIncluded, showsButton: true)
                }
            }
            if !later.isEmpty {
                Section {
                    ForEach(later) { row($0, now: now) }
                } header: {
                    header("Later", allIncluded: allIncluded, showsButton: comingUp.isEmpty)
                }
            }
        }
        .navigationTitle("Birthdays")
        // Inline, like a Settings page. A large title pushed inside the
        // Settings sheet drew over the Birthday Texts switch.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editingMessage = false }
            }
        }
        .sheet(item: $editing) { text in
            MessageEditorView(existing: store.message(id: text.id) ?? text, onClose: { editing = nil })
        }
        .onChange(of: editingMessage) { _, editing in
            if !editing { commitMessage() }
        }
        .onDisappear(perform: commitMessage)
        .onAppear {
            message = birthdays.settings.message
        }
        .task {
            // "Turn On for Everyone": flip the switch once the screen is
            // up, so you see it happen.
            guard router.turnOnBirthdaysWhenShown else { return }
            router.turnOnBirthdaysWhenShown = false
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(.snappy) { birthdays.turnOn() }
        }
    }

    private var footer: String {
        if !birthdays.settings.enabled {
            return "Get asked to text people on their birthdays, using the birthdays saved in Contacts."
        }
        if directory.access == .denied {
            return "Birthday Texts needs Contacts access to see birthdays. You can turn it on in the Settings app."
        }
        if birthdays.contacts.isEmpty {
            return "Add birthdays to people in Contacts and they'll show up here."
        }
        return "Each person gets a yearly text with this message. To change one person's text, tap their name."
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: birthdays.settings.hour, minute: birthdays.settings.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                birthdays.settings.hour = parts.hour ?? 9
                birthdays.settings.minute = parts.minute ?? 0
            }
        )
    }

    private func commitMessage() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? BirthdaySettings.defaultMessage : trimmed
        if value != birthdays.settings.message {
            birthdays.settings.message = value
        }
        if trimmed.isEmpty { message = value }
    }

    private func header(_ title: String, allIncluded: Bool, showsButton: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            if showsButton {
                Button(allIncluded ? "Disable All" : "Enable All") {
                    withAnimation { birthdays.selectAll(!allIncluded) }
                }
                .font(.subheadline)
                .textCase(nil)
            }
        }
    }

    private func row(_ contact: BirthdayContact, now: Date) -> some View {
        let included = birthdays.settings.isIncluded(contact.id)
        let custom = birthdays.settings.customMessages[contact.id]
        let text = included ? store.queue.messages.first { $0.birthdayContactID == contact.id } : nil
        return HStack(spacing: 12) {
            // Tapping the name opens their text. Without a text (switched
            // off), it flips the switch instead.
            Button {
                if let text {
                    editing = text
                } else {
                    withAnimation { birthdays.setIncluded(contact.id, !included) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    // The full name wins; the date gives way first.
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(contact.name).font(.headline).lineLimit(1).layoutPriority(1)
                        Text("· " + birthdayLabel(contact, now: now))
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Group {
                        if !included {
                            Text("No text")
                        } else if let custom {
                            Text(custom).foregroundStyle(.primary)
                        } else {
                            Text(birthdays.settings.message)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(contact.name, isOn: Binding(
                get: { included },
                set: { on in withAnimation { birthdays.setIncluded(contact.id, on) } }
            ))
            .labelsHidden()
        }
    }
}

/// "Mar 22": the month and day of the next birthday.
func birthdayLabel(_ contact: BirthdayContact, now: Date) -> String {
    guard let day = contact.nextBirthdayDay(from: now) else { return "" }
    return day.formatted(.dateTime.month(.abbreviated).day())
}
