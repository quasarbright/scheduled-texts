import ScheduledTextsCore
import SwiftUI

/// Don't Send, everywhere it appears. A one-off text is deleted right away.
/// A repeating text asks first whether to skip only this time or stop the
/// repeat, like deleting a repeating event in Calendar.
struct DontSendDialog: ViewModifier {
    /// The repeating text being asked about.
    @Binding var asking: ScheduledMessage?
    let store: MessageStore
    /// Runs after the text is skipped or deleted, for example to close a sheet.
    var onDone: () -> Void = {}

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "This text repeats",
            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
            titleVisibility: .visible,
            presenting: asking
        ) { message in
            Button("Skip This One") {
                store.skip(id: message.id)
                onDone()
            }
            Button("Stop Repeating", role: .destructive) {
                store.delete(id: message.id)
                onDone()
            }
            Button("Cancel", role: .cancel) {}
        } message: { message in
            Text("\(message.repeatSummary() ?? ""). Skip only this one, or stop sending it?")
        }
    }
}

extension View {
    func dontSendDialog(
        asking: Binding<ScheduledMessage?>,
        store: MessageStore,
        onDone: @escaping () -> Void = {}
    ) -> some View {
        modifier(DontSendDialog(asking: asking, store: store, onDone: onDone))
    }
}

extension MessageStore {
    /// Don't Send: deletes a one-off text and returns true. For a repeating
    /// text it does nothing and returns false, so the caller asks first.
    func dontSendIfOneOff(_ message: ScheduledMessage) -> Bool {
        guard message.repetition == nil else { return false }
        delete(id: message.id)
        return true
    }
}
