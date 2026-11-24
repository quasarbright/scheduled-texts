import ContactsUI
import ScheduledTextsCore
import UIKit

/// The system contact picker. Used only when the app doesn't have Contacts
/// access, since the picker runs outside the app and needs no permission.
///
/// Tapping a person picks them; the "To" field then uses their default
/// number, the same as picking them from the suggestions.
@MainActor
final class ContactPicker: NSObject, CNContactPickerDelegate {
    static let shared = ContactPicker()

    private var continuation: CheckedContinuation<ContactCard?, Never>?

    func pick() async -> ContactCard? {
        guard continuation == nil else { return nil }

        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey]
        picker.predicateForEnablingContact = NSPredicate(
            format: "phoneNumbers.@count > 0 OR emailAddresses.@count > 0"
        )

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            Task {
                if await !UIApplication.shared.presentWhenReady(picker) {
                    self.finish(nil)
                }
            }
        }
    }

    nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let card = ContactDirectory.card(for: contact)
        MainActor.assumeIsolated {
            self.finish(card)
        }
    }

    nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        MainActor.assumeIsolated {
            self.finish(nil)
        }
    }

    private func finish(_ card: ContactCard?) {
        continuation?.resume(returning: card)
        continuation = nil
    }
}
