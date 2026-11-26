import AppIntents
import SwiftUI
import ScheduledTextsCore

/// "Schedule a text in Scheduled Texts": Siri asks who, what and when,
/// shows the whole text, and saves it like any other. Nothing is sent: at
/// that time the usual "Send text to Kate?" notification comes.
struct ScheduleTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Schedule Text"
    static var description = IntentDescription(
        "Schedules a text. At that time you get a notification asking whether to send it."
    )

    @Parameter(title: "To")
    var recipient: RecipientEntity?

    @Parameter(title: "Message", inputOptions: String.IntentInputOptions(multiline: true))
    var message: String?

    @Parameter(title: "When")
    var sendAt: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Schedule a text to \(\.$recipient) saying \(\.$message) at \(\.$sendAt)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Asked here rather than by each parameter, so the questions come in
        // this order and the second one can use the name.
        let recipient: RecipientEntity
        if let given = self.recipient {
            recipient = given
        } else {
            recipient = try await $recipient.requestValue("Who’s it for?")
        }
        let who = recipient.name ?? recipient.address

        var body = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        while body.isEmpty {
            body = try await $message.requestValue("What do you want to say to \(who)?")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var date: Date
        if let given = sendAt {
            date = given.truncatedToMinute()
        } else {
            date = try await $sendAt.requestValue("When should I ask you to send it?").truncatedToMinute()
        }
        if date <= Date() {
            date = try await $sendAt.requestValue("That time has passed. When should I ask you to send it?")
                .truncatedToMinute()
            guard date > Date() else {
                throw $sendAt.needsValueError("That time has passed. When should I ask you to send it?")
            }
        }

        let text = ScheduledMessage(
            recipientName: recipient.name,
            contactIdentifier: recipient.contactIdentifier,
            recipientAddress: recipient.address,
            body: body,
            sendAt: date
        )

        let schedule: ConfirmationActionName
        if #available(iOS 18.0, *) {
            schedule = .custom(
                acceptLabel: "Schedule", acceptAlternatives: ["Yes", "Schedule it"],
                denyLabel: "Cancel", denyAlternatives: ["No"],
                destructive: false
            )
        } else {
            schedule = .set
        }
        try await requestConfirmation(
            result: .result(dialog: "Ready to schedule it?") {
                ScheduleTextSnippet(message: text)
            },
            confirmationActionName: schedule
        )

        MessageStore.shared.save(text)
        await MessageStore.shared.waitForSync()

        let time = SendTimeFormat.string(for: text.sendAt).lowercasedDayWord
        return .result(
            dialog: "Done. I’ll ask you \(time) whether to send it to \(who)."
        ) {
            ScheduleTextSnippet(message: text)
        }
    }
}

/// To, Message and When, as Siri shows them before and after saving.
struct ScheduleTextSnippet: View {
    let message: ScheduledMessage

    var body: some View {
        VStack(spacing: 0) {
            row("To", message.displayRecipient)
            Divider()
            row("Message", message.body)
            Divider()
            row("When", SendTimeFormat.string(for: message.sendAt))
        }
        .padding()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }
}

private extension String {
    /// "Tomorrow, 9:00 AM" reads "tomorrow at 9:00 AM" in a sentence.
    var lowercasedDayWord: String {
        for word in ["Today", "Tomorrow", "Yesterday"] where hasPrefix(word + ", ") {
            return word.lowercased() + " at " + dropFirst(word.count + 2)
        }
        let parts = components(separatedBy: ", ")
        guard parts.count >= 2 else { return self }
        return "on " + parts.dropLast().joined(separator: ", ") + " at " + parts.last!
    }
}
