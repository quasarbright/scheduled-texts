import ScheduledTextsCore
import SwiftUI

/// Who a text goes to, once a contact has been picked.
struct ChosenRecipient: Equatable {
    var name: String
    var address: String
    var contactID: String?
}

enum EditorField: Hashable {
    case to
    case message
}

/// The "To:" rows of the editor, like the Messages app: type a name and
/// pick a suggestion, or type a number or email and keep going.
///
/// Picking a person uses their default number (`ContactCard.defaultAddress`),
/// and the number under their name is a menu for switching to another one.
struct RecipientField: View {
    @Binding var recipient: ChosenRecipient?
    @Binding var query: String
    var focus: FocusState<EditorField?>.Binding

    @ObservedObject var directory: ContactDirectory

    private var suggestions: [ContactCard] {
        ContactSearch.matches(query, in: directory.contacts, limit: 6)
    }

    var body: some View {
        if let recipient {
            chosenRow(recipient)
        } else {
            fieldRow
            ForEach(suggestions) { card in
                suggestionRow(card)
            }
            if directory.access == .denied {
                Button {
                    Task {
                        if let card = await ContactPicker.shared.pick() {
                            choose(card, address: card.defaultAddress)
                        }
                    }
                } label: {
                    Label("Choose from Contacts", systemImage: "person.crop.circle.badge.plus")
                }
            }
        }
    }

    // MARK: - Rows

    private var fieldRow: some View {
        HStack {
            Text("To:")
                .foregroundStyle(.secondary)
            TextField("Name, number or email", text: $query)
                .focused(focus, equals: .to)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit(submit)
        }
    }

    private func suggestionRow(_ card: ContactCard) -> some View {
        Button {
            choose(card, address: addressForSuggestion(card))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .foregroundStyle(.primary)
                if let address = addressForSuggestion(card) {
                    Text(describe(address))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHint("Sends to this contact")
    }

    private func chosenRow(_ recipient: ChosenRecipient) -> some View {
        HStack(spacing: 10) {
            Text("To:")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipient.name)
                addressLine(recipient)
            }
            Spacer(minLength: 0)
            Button {
                self.recipient = nil
                query = ""
                focus.wrappedValue = .to
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(recipient.name)")
        }
    }

    /// The number being used. A menu when the contact has more than one.
    @ViewBuilder
    private func addressLine(_ recipient: ChosenRecipient) -> some View {
        let card = card(for: recipient)
        let current = card?.address(matching: recipient.address)
        let text = current.map(describe) ?? recipient.address

        if let card, card.addresses.count > 1 {
            Menu {
                ForEach(card.addresses, id: \.self) { address in
                    Button {
                        self.recipient?.address = address.value
                    } label: {
                        if address == current {
                            Label(describe(address), systemImage: "checkmark")
                        } else {
                            Text(describe(address))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(text)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .font(.subheadline)
            }
            .accessibilityLabel("Number: \(text)")
            .accessibilityHint("Choose a different number")
        } else {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    /// Return picks the top suggestion, or keeps a typed number as is.
    private func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if ContactSearch.looksLikeAddress(trimmed) {
            if let card = ContactSearch.contact(withAddress: trimmed, in: directory.contacts) {
                choose(card, address: card.address(matching: trimmed))
            } else {
                focus.wrappedValue = .message
            }
        } else if let first = suggestions.first {
            choose(first, address: addressForSuggestion(first))
        }
    }

    private func choose(_ card: ContactCard, address: ContactAddress?) {
        guard let address = address ?? card.defaultAddress else { return }
        recipient = ChosenRecipient(name: card.name, address: address.value, contactID: card.id)
        query = ""
        focus.wrappedValue = .message
    }

    // MARK: - Helpers

    /// When the person typed one of this contact's numbers, use that one.
    /// Otherwise their default.
    private func addressForSuggestion(_ card: ContactCard) -> ContactAddress? {
        if ContactSearch.looksLikeAddress(query), let typed = card.address(matching: query) {
            return typed
        }
        return card.defaultAddress
    }

    /// The contact behind a chosen recipient. Texts saved before contact
    /// ids were stored fall back to looking up the number.
    private func card(for recipient: ChosenRecipient) -> ContactCard? {
        if let id = recipient.contactID, let card = directory.contact(id: id) {
            return card
        }
        return ContactSearch.contact(withAddress: recipient.address, in: directory.contacts)
    }

    /// "mobile · (555) 123-4567", or just the number when it has no label.
    private func describe(_ address: ContactAddress) -> String {
        address.label.isEmpty ? address.value : "\(address.label) · \(address.value)"
    }
}
