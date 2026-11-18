import ScheduledTextsCore
import SwiftUI

/// "Send this text?" Shown when the person taps a notification or a text
/// that's ready to send.
struct ReviewView: View {
    let message: ScheduledMessage

    @EnvironmentObject private var store: MessageStore
    @EnvironmentObject private var router: Router

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // The part you're deciding on scrolls, so a long message or
                // large text is never cut off. The buttons stay put.
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("To \(message.displayRecipient)")
                                .font(.headline)
                            if message.recipientName != nil {
                                Text(message.recipientAddress)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(message.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundStyle(.white)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .containerRelativeFrame(.horizontal, alignment: .trailing) { width, _ in width * 0.8 }
                            .frame(maxWidth: .infinity, alignment: .trailing)

                        Text("Scheduled for \(SendTimeFormat.string(for: message.sendAt))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)

                VStack(spacing: 12) {
                    Button {
                        router.open(.send(message.id))
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Menu {
                        ForEach(RemindLater.options(at: Date())) { option in
                            Button(option.title) {
                                store.remindLater(id: message.id, option)
                                router.close()
                            }
                        }
                    } label: {
                        Label("Remind Me Later", systemImage: "clock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    // Soonest first, top to bottom, even though the menu
                    // opens upward from a button low on the screen.
                    .menuOrder(.fixed)

                    Button {
                        router.editFromReview(message.id)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        store.delete(id: message.id)
                        router.close()
                    } label: {
                        Label("Don't Send", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("Send this text?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Leaves the text in Ready to Send. Remind Me Later is the
                    // way to be asked again.
                    Button("Close") { router.close() }
                }
            }
        }
        // Full height: with four buttons, half the screen leaves too little
        // room for the message you're deciding on.
        .presentationDetents([.large])
    }
}
