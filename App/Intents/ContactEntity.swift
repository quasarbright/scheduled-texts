import AppIntents
import Contacts
import ScheduledTextsCore

/// Someone to text, for Siri and Shortcuts: a contact (sent to their default
/// number), or a number or email address said or typed as is.
struct RecipientEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Recipient"
    static var defaultQuery = RecipientQuery()

    /// "contact:<id>" for a contact, "address:<value>" for a typed number.
    var id: String
    var name: String?
    var contactIdentifier: String?
    var address: String

    var displayRepresentation: DisplayRepresentation {
        if let name {
            return DisplayRepresentation(title: "\(name)", subtitle: "\(address)")
        }
        return DisplayRepresentation(title: "\(address)")
    }

    init(card: ContactCard, address: ContactAddress) {
        id = "contact:\(card.id)"
        name = card.name
        contactIdentifier = card.id
        self.address = address.value
    }

    init(address: String) {
        id = "address:\(address)"
        self.address = address
    }
}

struct RecipientQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RecipientEntity] {
        let contacts = Self.contacts()
        return identifiers.compactMap { id in
            if id.hasPrefix("contact:") {
                let contactID = String(id.dropFirst("contact:".count))
                guard let card = contacts.first(where: { $0.id == contactID }),
                      let address = card.defaultAddress else { return nil }
                return RecipientEntity(card: card, address: address)
            }
            if id.hasPrefix("address:") {
                return RecipientEntity(address: String(id.dropFirst("address:".count)))
            }
            return nil
        }
    }

    /// What Siri heard ("Kate") or what was typed in Shortcuts. Several
    /// matches make Siri ask which one.
    func entities(matching string: String) async throws -> [RecipientEntity] {
        let contacts = Self.contacts()
        let found = ContactSearch.matches(string, in: contacts, limit: 6).compactMap { card in
            card.defaultAddress.map { RecipientEntity(card: card, address: $0) }
        }
        if !found.isEmpty { return found }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if ContactSearch.looksLikeAddress(trimmed) {
            if let card = ContactSearch.contact(withAddress: trimmed, in: contacts),
               let address = card.address(matching: trimmed) {
                return [RecipientEntity(card: card, address: address)]
            }
            return [RecipientEntity(address: trimmed)]
        }
        return []
    }

    /// The people already in scheduled texts, for the Shortcuts picker.
    @MainActor
    func suggestedEntities() async throws -> [RecipientEntity] {
        let contacts = Self.contacts()
        var seen = Set<String>()
        var result: [RecipientEntity] = []
        for message in MessageStore.shared.queue.messages {
            let entity: RecipientEntity
            if let id = message.contactIdentifier, let card = contacts.first(where: { $0.id == id }) {
                entity = RecipientEntity(
                    card: card,
                    address: card.address(matching: message.recipientAddress)
                        ?? card.defaultAddress
                        ?? ContactAddress(kind: .otherPhone, label: "", value: message.recipientAddress)
                )
            } else {
                entity = RecipientEntity(address: message.recipientAddress)
            }
            if seen.insert(entity.id).inserted { result.append(entity) }
        }
        return result
    }

    /// Contacts, read fresh. Empty without access: Siri can't show the
    /// permission prompt, so it then only takes numbers.
    static func contacts() -> [ContactCard] {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined, .denied, .restricted: return []
        default: return ContactDirectory.fetchAll(from: CNContactStore()).cards
        }
    }
}
