import ScheduledTextsCore
import SwiftUI

/// Settings, from the gear on the list. For now it's Birthday Texts.
struct SettingsView: View {
    @EnvironmentObject private var router: Router
    @ObservedObject private var birthdays = BirthdayStore.shared
    @ObservedObject private var directory = ContactDirectory.shared

    /// The message as typed, saved when you leave the field or Settings,
    /// not on every keystroke.
    @State private var message = ""
    @FocusState private var editingMessage: Bool

    var body: some View {
        NavigationStack {
            Form {
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

                    if birthdays.settings.enabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Message").font(.footnote).foregroundStyle(.secondary).textCase(.uppercase)
                            TextField(BirthdaySettings.defaultMessage, text: $message, axis: .vertical)
                                .lineLimit(1...6)
                                .focused($editingMessage)
                                .onSubmit(commitMessage)
                        }
                        DatePicker("Remind me at", selection: time, displayedComponents: .hourAndMinute)
                        NavigationLink {
                            PeopleView()
                        } label: {
                            LabeledContent("People", value: peopleSummary)
                        }
                    }
                } header: {
                    Text("Birthday Texts")
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitMessage()
                        router.close()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingMessage = false }
                }
            }
            .onChange(of: editingMessage) { _, editing in
                if !editing { commitMessage() }
            }
            .onDisappear(perform: commitMessage)
            .onAppear {
                message = birthdays.settings.message
                birthdays.refresh()
            }
            .task {
                // "Turn On for Everyone": flip the switch once the sheet is
                // up, so you see it happen.
                guard router.turnOnBirthdaysWhenShown else { return }
                router.turnOnBirthdaysWhenShown = false
                try? await Task.sleep(for: .milliseconds(550))
                withAnimation(.snappy) { birthdays.turnOn() }
            }
        }
    }

    private var footer: String {
        if !birthdays.settings.enabled {
            return "Get asked to text people on their birthdays, using the birthdays saved in Contacts."
        }
        if directory.access == .denied {
            return "Birthday Texts needs Contacts access to see birthdays. You can turn it on in the Settings app."
        }
        return "Uses the birthdays saved in Contacts. Each person gets a yearly text with this message. To change it for one person, edit their text."
    }

    private var peopleSummary: String {
        let total = birthdays.contacts.count
        let included = birthdays.contacts.filter { birthdays.settings.isIncluded($0.id) }.count
        if total == 0 { return "None" }
        return included == total ? "All \(total)" : "\(included) of \(total)"
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
}

/// Settings > People: who gets a birthday text.
struct PeopleView: View {
    @ObservedObject private var birthdays = BirthdayStore.shared

    var body: some View {
        let now = Date()
        let soon = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        let comingUp = birthdays.contacts.filter { ($0.nextBirthdayDay(from: now) ?? .distantFuture) <= soon }
        let later = birthdays.contacts.filter { ($0.nextBirthdayDay(from: now) ?? .distantFuture) > soon }
        let allIncluded = birthdays.contacts.allSatisfy { birthdays.settings.isIncluded($0.id) }

        List {
            Section {
                Toggle("Add New Birthdays", isOn: $birthdays.settings.addNewBirthdays)
            } footer: {
                Text("When you add a birthday in Contacts, they get a text too.")
            }
            // Enable All / Disable All sits on the first section's header,
            // next to the list it acts on.
            if !comingUp.isEmpty {
                Section {
                    ForEach(comingUp) { row($0, now: now, soon: true) }
                } header: {
                    header("Coming Up", allIncluded: allIncluded, showsButton: true)
                }
            }
            if !later.isEmpty {
                Section {
                    ForEach(later) { row($0, now: now, soon: false) }
                } header: {
                    header("Later", allIncluded: allIncluded, showsButton: comingUp.isEmpty)
                }
            }
        }
        .overlay {
            if birthdays.contacts.isEmpty {
                ContentUnavailableView(
                    "No Birthdays",
                    systemImage: "birthday.cake",
                    description: Text("Add birthdays to people in Contacts and they'll show up here.")
                )
            }
        }
        .navigationTitle("Birthdays")
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

    private func row(_ contact: BirthdayContact, now: Date, soon: Bool) -> some View {
        let included = birthdays.settings.isIncluded(contact.id)
        let custom = birthdays.settings.customMessages[contact.id]
        return Button {
            birthdays.setIncluded(contact.id, !included)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(included ? Color.accentColor : Color(.tertiaryLabel))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(contact.name).font(.headline).lineLimit(1)
                        Spacer()
                        Text(birthdayLabel(contact, now: now, soon: soon))
                            .font(.subheadline).foregroundStyle(.secondary)
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
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(included ? .isSelected : [])
    }
}

/// "Thu, Dec 3" for a birthday this month, "Mar 22" further out.
func birthdayLabel(_ contact: BirthdayContact, now: Date, soon: Bool) -> String {
    guard let day = contact.nextBirthdayDay(from: now) else { return "" }
    return soon
        ? day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        : day.formatted(.dateTime.month(.abbreviated).day())
}

/// The list's Birthdays row opens this: every birthday text, soonest first.
/// Tapping one opens it, to change that person's message.
struct BirthdayTextsView: View {
    @EnvironmentObject private var store: MessageStore
    @EnvironmentObject private var router: Router
    @ObservedObject private var birthdays = BirthdayStore.shared

    var body: some View {
        let now = Date()
        let soon = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        let texts = store.queue.upcoming(at: now).filter { $0.birthdayContactID != nil }
        List {
            let comingUp = texts.filter { $0.sendAt <= soon }
            let later = texts.filter { $0.sendAt > soon }
            if !comingUp.isEmpty {
                Section("Coming Up") { ForEach(comingUp) { row($0, soon: true) } }
            }
            if !later.isEmpty {
                Section("Later") { ForEach(later) { row($0, soon: false) } }
            }
        }
        .overlay {
            if texts.isEmpty {
                ContentUnavailableView("No Birthday Texts", systemImage: "birthday.cake")
            }
        }
        .navigationTitle("Birthdays")
    }

    private func row(_ message: ScheduledMessage, soon: Bool) -> some View {
        let isDefault = birthdays.settings.customMessages[message.birthdayContactID ?? ""] == nil
        return Button {
            router.open(.edit(message.id))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.displayRecipient).font(.headline).lineLimit(1)
                    Spacer()
                    Text(soon
                         ? message.sendAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                         : message.sendAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(isDefault ? Color.secondary : Color.primary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
