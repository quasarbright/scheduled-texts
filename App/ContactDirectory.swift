import Contacts
import ScheduledTextsCore

/// The person's contacts, loaded once so the "To" field can suggest them
/// as they type.
@MainActor
final class ContactDirectory: ObservableObject {
    static let shared = ContactDirectory()

    enum Access {
        case unknown
        /// Full access, or the limited set of contacts the person shared.
        case granted
        /// Denied or restricted. The "To" field still takes numbers, and
        /// the system contact picker still works without access.
        case denied
    }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var contacts: [ContactCard] = []

    private let store = CNContactStore()
    private var loadTask: Task<Void, Never>?

    /// Asks for access the first time, then loads contacts. Safe to call
    /// often: it reloads at most once per call to `refresh()`.
    func load() {
        guard loadTask == nil else { return }
        loadTask = Task {
            let status = CNContactStore.authorizationStatus(for: .contacts)
            let allowed: Bool
            switch status {
            case .notDetermined:
                allowed = (try? await store.requestAccess(for: .contacts)) ?? false
            case .denied, .restricted:
                allowed = false
            default:
                // .authorized, and .limited on iOS 18.
                allowed = true
            }
            guard allowed else {
                access = .denied
                return
            }
            access = .granted
            let store = store
            contacts = await Task.detached(priority: .userInitiated) {
                Self.fetchAll(from: store)
            }.value
        }
    }

    /// Reloads on the next `load()`, to pick up contacts added since.
    func refresh() {
        loadTask = nil
    }

    func contact(id: String) -> ContactCard? {
        contacts.first { $0.id == id }
    }

    nonisolated private static let keys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
    ]

    nonisolated private static func fetchAll(from store: CNContactStore) -> [ContactCard] {
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var cards: [ContactCard] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                if let card = card(for: contact) { cards.append(card) }
            }
        } catch {
            print("Couldn't read contacts: \(error)")
        }
        return cards
    }

    /// Converts a contact, or nil if it has no name and nothing to send to.
    nonisolated static func card(for contact: CNContact) -> ContactCard? {
        let phones = contact.isKeyAvailable(CNContactPhoneNumbersKey) ? contact.phoneNumbers : []
        let emails = contact.isKeyAvailable(CNContactEmailAddressesKey) ? contact.emailAddresses : []

        var addresses: [ContactAddress] = phones.compactMap { labeled in
            guard let kind = phoneKind(labeled.label) else { return nil }
            return ContactAddress(kind: kind, label: localized(labeled.label), value: labeled.value.stringValue)
        }
        addresses += emails.map {
            ContactAddress(kind: .email, label: localized($0.label), value: $0.value as String)
        }
        guard !addresses.isEmpty else { return nil }

        let nickname = contact.isKeyAvailable(CNContactNicknameKey) ? contact.nickname : ""
        let company = contact.isKeyAvailable(CNContactOrganizationNameKey) ? contact.organizationName : ""
        let formatted = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        let name = [formatted, nickname, company, addresses[0].value].first { !$0.isEmpty } ?? ""

        return ContactCard(
            id: contact.identifier,
            name: name,
            otherNames: [nickname, company].filter { !$0.isEmpty },
            addresses: addresses
        )
    }

    /// Nil for numbers that can't get texts, like fax and pager.
    nonisolated private static func phoneKind(_ label: String?) -> ContactAddress.Kind? {
        switch label {
        case CNLabelPhoneNumberiPhone: return .iPhone
        case CNLabelPhoneNumberMobile: return .mobile
        case CNLabelPhoneNumberMain: return .main
        case CNLabelPhoneNumberHomeFax, CNLabelPhoneNumberWorkFax,
             CNLabelPhoneNumberOtherFax, CNLabelPhoneNumberPager:
            return nil
        default: return .otherPhone
        }
    }

    nonisolated private static func localized(_ label: String?) -> String {
        guard let label else { return "" }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }
}
