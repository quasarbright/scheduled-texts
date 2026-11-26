import ScheduledTextsCore
import SwiftUI
import UIKit

/// The main screen: texts waiting to be sent, then texts scheduled for later.
struct ContentView: View {
    @EnvironmentObject private var store: MessageStore
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase

    @State private var notificationsAllowed = true
    @State private var unsendable: ScheduledMessage?
    /// The repeating text being asked about by Don't Send.
    @State private var askingDontSend: ScheduledMessage?
    /// What's typed in the search field, like Notes.
    @State private var searchText = ""
    @ObservedObject private var birthdays = BirthdayStore.shared

    var body: some View {
        NavigationStack {
            // Re-render every 15 seconds so texts move from Scheduled to
            // Ready to Send when their time comes.
            TimelineView(.periodic(from: .now, by: 15)) { context in
                list(now: context.date)
            }
            .navigationTitle("Scheduled Texts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.open(.settings)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            // Search and compose share the bottom bar, like Notes. Nothing
            // to search in an empty list, so no search field there.
            .modifier(BottomBar(
                searchText: $searchText,
                searchable: !store.queue.isEmpty,
                compose: { router.open(.new) }
            ))
            // Pinned to the screen, outside the scrolling list, so it shows
            // however long the list is or wherever it's scrolled. Inside the
            // navigation stack so it sits above the bottom toolbar.
            .overlay(alignment: .bottom) {
                if let change = store.lastChange {
                    UndoToast(summary: change.summary) {
                        withAnimation { store.undo() }
                    }
                    .id(change.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: change.id) {
                        try? await Task.sleep(for: .seconds(8))
                        if store.lastChange?.id == change.id {
                            withAnimation { store.dismissUndo() }
                        }
                    }
                }
            }
        }
        .animation(.snappy, value: store.lastChange)
        .dontSendDialog(asking: $askingDontSend, store: store)
        .sheet(item: $router.sheet) { route in
            sheet(for: route)
        }
        .onOpenURL { url in
            // Taps on the widgets.
            switch DeepLink(url: url) {
            case .list: router.close()
            case .new: router.open(.new)
            case .text(let id):
                guard let message = store.message(id: id) else { router.close(); return }
                router.open(message.isDue(at: Date()) ? .review(id) : .edit(id))
            case nil: break
            }
        }
        .onReceive(router.$pendingSend.compactMap { $0 }) { id in
            router.pendingSend = nil
            send(id)
        }
        .task {
            await NotificationScheduler.requestAuthorization()
            notificationsAllowed = await NotificationScheduler.isAuthorized()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { notificationsAllowed = await NotificationScheduler.isAuthorized() }
        }
        .alert(
            "This iPhone can't send texts",
            isPresented: Binding(get: { unsendable != nil }, set: { if !$0 { unsendable = nil } }),
            presenting: unsendable
        ) { message in
            Button("Copy Message") { UIPasteboard.general.string = message.body }
            Button("OK", role: .cancel) {}
        } message: { message in
            Text("Messages isn't available here. You can copy the text and send it to \(message.displayRecipient) yourself.")
        }
    }

    @ViewBuilder
    private func list(now: Date) -> some View {
        let searching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let due = store.queue.due(at: now).filter { $0.matches(search: searchText) }
        let allUpcoming = store.queue.upcoming(at: now).filter { $0.matches(search: searchText) }
        // Birthday texts fold into one Birthdays row until they're ready,
        // so a year of birthdays doesn't fill the list. Search still finds them.
        let upcoming = searching ? allUpcoming : allUpcoming.filter { $0.birthdayContactID == nil }
        let birthdayTexts = searching ? [] : allUpcoming.filter { $0.birthdayContactID != nil }
        let prompt = searching ? nil : birthdays.prompt(queue: store.queue, now: now)

        List {
            if !notificationsAllowed {
                Section {
                    NotificationsOffNotice()
                }
            }

            if let prompt {
                Section {
                    BirthdayPromptCard(
                        contact: prompt.contact,
                        day: prompt.day,
                        schedule: {
                            if let text = BirthdayPlanner.handmadeText(for: prompt.contact, settings: birthdays.settings, now: Date()) {
                                router.open(.draft(text))
                            }
                        },
                        turnOnForEveryone: {
                            router.turnOnBirthdaysWhenShown = true
                            router.open(.settings)
                        },
                        dismiss: {
                            withAnimation { birthdays.dismissPrompt(prompt.contact, day: prompt.day) }
                        }
                    )
                }
            }

            if !due.isEmpty {
                Section("Ready to Send") {
                    ForEach(due) { message in
                        row(message, now: now, route: .review(message.id))
                    }
                }
            }

            if !upcoming.isEmpty || !birthdayTexts.isEmpty {
                Section("Scheduled") {
                    ForEach(upcoming) { message in
                        row(message, now: now, route: .edit(message.id))
                    }
                    if let next = birthdayTexts.first {
                        NavigationLink {
                            BirthdayTextsView()
                        } label: {
                            BirthdaysRow(count: birthdayTexts.count, next: next, now: now)
                        }
                    }
                }
            }
        }
        // An empty list would otherwise drop to a plain white background.
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .overlay {
            if !store.queue.isEmpty && due.isEmpty && upcoming.isEmpty && birthdayTexts.isEmpty && prompt == nil {
                ContentUnavailableView.search(text: searchText)
            } else if store.queue.isEmpty && notificationsAllowed {
                ContentUnavailableView {
                    Label("No Scheduled Texts", systemImage: "clock")
                } description: {
                    // The compose button in the corner is the one way in,
                    // like Notes and Mail.
                    Text("Tap \(Image(systemName: "square.and.pencil")) to write a text now and get a reminder to send it later.")
                }
            }
        }
    }

    private func row(_ message: ScheduledMessage, now: Date, route: Route) -> some View {
        Button {
            router.open(route)
        } label: {
            MessageRow(message: message, now: now)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                if !store.dontSendIfOneOff(message) {
                    askingDontSend = message
                }
            } label: {
                Label("Don't Send", systemImage: "xmark")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                send(message.id)
            } label: {
                Label(message.isDue(at: now) ? "Send" : "Send Now", systemImage: "paperplane")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private func sheet(for route: Route) -> some View {
        switch route {
        case .new:
            MessageEditorView(existing: nil)
        case .draft(let template):
            MessageEditorView(existing: nil, template: template)
        case .settings:
            SettingsView()
        case .edit(let id):
            if let message = store.message(id: id) {
                MessageEditorView(existing: message)
            } else {
                MissingMessageView()
            }
        case .review(let id):
            if let message = store.message(id: id) {
                ReviewView(message: message)
            } else {
                MissingMessageView()
            }
        case .send:
            // Never shown as a sheet; see Router.open.
            EmptyView()
        }
    }

    /// Opens the compose sheet and removes the text once it's sent. If the
    /// person backs out, the text stays in the list.
    private func send(_ id: UUID) {
        guard let message = store.message(id: id) else { return }
        guard MessageSender.canSendText else {
            unsendable = message
            return
        }
        Task {
            if await MessageSender.shared.compose(message) == .sent {
                store.markSent(id: id)
            }
        }
    }
}

/// The list's search field, like Notes. Left off when there's nothing to search.
/// The bottom of the list: a search field with the compose button to its
/// right, like Notes on iOS 26. Older iOS puts search under the title and
/// compose alone in the bottom bar.
private struct BottomBar: ViewModifier {
    @Binding var searchText: String
    let searchable: Bool
    let compose: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if searchable {
                content
                    .searchable(text: $searchText, prompt: "Search")
                    .toolbar {
                        DefaultToolbarItem(kind: .search, placement: .bottomBar)
                        ToolbarSpacer(.fixed, placement: .bottomBar)
                        ToolbarItem(placement: .bottomBar) { composeButton }
                    }
            } else {
                content.toolbar {
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) { composeButton }
                }
            }
        } else {
            let base = content.toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    composeButton
                }
            }
            if searchable {
                base.searchable(text: $searchText, prompt: "Search texts and names")
            } else {
                base
            }
        }
    }

    private var composeButton: some View {
        Button(action: compose) {
            Label("New Text", systemImage: "square.and.pencil")
        }
    }
}

struct MessageRow: View {
    let message: ScheduledMessage
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Name and time on one line when they fit; at large text sizes
            // the time gets its own line instead of wrapping mid-phrase.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    name
                    Spacer()
                    time.fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    name
                    time
                }
            }
            Text(message.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var name: some View {
        Text(message.displayRecipient)
            .font(.headline)
            .lineLimit(1)
    }

    private var time: some View {
        HStack(spacing: 4) {
            if let summary = message.repeatSummary() {
                Image(systemName: "repeat")
                    .imageScale(.small)
                    .accessibilityLabel(summary)
            }
            Text(SendTimeFormat.string(for: message.sendAt, now: now))
        }
        .font(.subheadline)
        .foregroundStyle(message.isDue(at: now) ? Color.orange : Color.secondary)
    }
}

/// "Won't send to Kate Bell · Undo", for a few seconds after a change.
private struct UndoToast: View {
    let summary: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(summary)
                .font(.subheadline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Undo", action: undo)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

private struct NotificationsOffNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notifications are off", systemImage: "bell.slash")
                .font(.headline)
            Text("You won't be reminded when it's time to send. Texts still show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Turn On in Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct MissingMessageView: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Already Handled",
                systemImage: "checkmark.circle",
                description: Text("This text was already sent or deleted.")
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { router.close() }
                }
            }
        }
    }
}

/// The Birthdays row at the end of Scheduled: every birthday text in one.
private struct BirthdaysRow: View {
    let count: Int
    let next: ScheduledMessage
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "birthday.cake")
                .font(.title3)
                .foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 2) {
                Text("Birthdays").font(.headline)
                Text("\(count) \(count == 1 ? "person" : "people") · \(next.displayRecipient) next, \(next.sendAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Shown on the list while Birthday Texts is off, for the soonest birthday
/// in the next week that has no text. Never a notification.
private struct BirthdayPromptCard: View {
    let contact: BirthdayContact
    let day: Date
    let schedule: () -> Void
    let turnOnForEveryone: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "birthday.cake").foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(contact.name)'s birthday is \(dayText)")
                        .font(.subheadline.weight(.semibold))
                    Text("Want a reminder to send a text?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Not Now")
            }
            HStack(spacing: 8) {
                Button(action: schedule) {
                    Text("Schedule for \(firstName)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: turnOnForEveryone) {
                    Text("Turn On for Everyone").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
    }

    private var firstName: String {
        contact.name.split(separator: " ").first.map(String.init) ?? contact.name
    }

    /// "today", "tomorrow", or "Thu, Dec 3".
    private var dayText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "today" }
        if calendar.isDateInTomorrow(day) { return "tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
