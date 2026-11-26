import Foundation

/// One phone number or email address on a contact.
public struct ContactAddress: Equatable, Hashable {
    /// What kind of number or address this is. Decides which one a contact
    /// gets by default.
    public enum Kind: Int, Comparable {
        // Lower raw values win when picking a default.
        case iPhone = 0
        case mobile
        case main
        case otherPhone
        case email

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var kind: Kind
    /// The label as Contacts shows it, like "mobile" or "home". Empty when
    /// the number has no label.
    public var label: String
    public var value: String

    public init(kind: Kind, label: String, value: String) {
        self.kind = kind
        self.label = label
        self.value = value
    }
}

/// A contact, reduced to what the "To" field needs.
public struct ContactCard: Identifiable, Equatable {
    public var id: String
    public var name: String
    /// Other names to match against, like a nickname or company.
    public var otherNames: [String]
    public var addresses: [ContactAddress]
    /// Month and day (and year when known) from Contacts. Nil when there's
    /// no birthday.
    public var birthday: DateComponents?

    public init(id: String, name: String, otherNames: [String] = [], addresses: [ContactAddress], birthday: DateComponents? = nil) {
        self.id = id
        self.birthday = birthday
        self.name = name
        self.otherNames = otherNames
        self.addresses = addresses
    }

    /// The address to use when the person picks this contact without
    /// choosing a number. iOS doesn't tell apps which number iMessage uses,
    /// so this prefers numbers labeled iPhone, then mobile, then main, then
    /// any other phone, then email. Ties go to the one listed first.
    public var defaultAddress: ContactAddress? {
        addresses.enumerated()
            .min { ($0.element.kind, $0.offset) < ($1.element.kind, $1.offset) }?
            .element
    }

    /// The address that matches `value`, ignoring formatting, if any.
    public func address(matching value: String) -> ContactAddress? {
        let key = ContactSearch.addressKey(value)
        guard !key.isEmpty else { return nil }
        return addresses.first { ContactSearch.addressKey($0.value) == key }
    }
}

/// Matches what's typed in the "To" field against contacts.
public enum ContactSearch {
    /// Contacts that match `query`, best first.
    ///
    /// Every word typed has to start some word of the contact's name,
    /// nickname or company, so "jo sm" finds "John Smith". A query that's
    /// mostly digits also finds contacts whose number contains those digits.
    public static func matches(_ query: String, in contacts: [ContactCard], limit: Int = 8) -> [ContactCard] {
        let queryWords = words(query)
        guard !queryWords.isEmpty else { return [] }
        let queryDigits = digits(query)
        let searchByNumber = queryDigits.count >= 3 && looksLikePhoneNumber(query)

        var scored: [(score: Int, card: ContactCard)] = []
        for card in contacts where !card.addresses.isEmpty {
            if let score = nameScore(queryWords, card) {
                scored.append((score, card))
            } else if searchByNumber,
                      card.addresses.contains(where: { digits($0.value).contains(queryDigits) }) {
                scored.append((3, card))
            }
        }
        scored.sort {
            if $0.score != $1.score { return $0.score < $1.score }
            return $0.card.name.localizedStandardCompare($1.card.name) == .orderedAscending
        }
        return scored.prefix(limit).map(\.card)
    }

    /// True when the text could be sent to as is: an email address, or
    /// something that looks like a phone number.
    public static func looksLikeAddress(_ text: String) -> Bool {
        looksLikeEmail(text) || (looksLikePhoneNumber(text) && digits(text).count >= 3)
    }

    /// The first contact that has `address`, ignoring formatting, so a
    /// typed number can show the person's name.
    public static func contact(withAddress address: String, in contacts: [ContactCard]) -> ContactCard? {
        contacts.first { $0.address(matching: address) != nil }
    }

    // MARK: - Helpers

    /// Lower score is a better match. Nil means no match.
    private static func nameScore(_ queryWords: [String], _ card: ContactCard) -> Int? {
        let nameWords = words(card.name)
        let allWords = nameWords + card.otherNames.flatMap(words)
        let everyWordMatches = queryWords.allSatisfy { q in allWords.contains { $0.hasPrefix(q) } }
        guard everyWordMatches else { return nil }

        let joinedName = nameWords.joined(separator: " ")
        if joinedName.hasPrefix(queryWords.joined(separator: " ")) { return 0 }
        if let first = nameWords.first, first.hasPrefix(queryWords[0]) { return 1 }
        return 2
    }

    /// Lowercased words with accents removed.
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func digits(_ text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.map(Character.init))
    }

    static func looksLikeEmail(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        let local = trimmed[..<at]
        let domain = trimmed[trimmed.index(after: at)...]
        return !local.isEmpty && domain.contains(".") && !domain.hasSuffix(".") && !trimmed.contains(" ")
    }

    static func looksLikePhoneNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let allowed = CharacterSet(charactersIn: "0123456789+-(). ")
        return !trimmed.isEmpty && trimmed.unicodeScalars.allSatisfy(allowed.contains) && !digits(trimmed).isEmpty
    }

    /// A form of an address for comparing: lowercased email, or the phone
    /// number's last 10 digits so "+1 (555) 123-4567" equals "5551234567".
    static func addressKey(_ address: String) -> String {
        if looksLikeEmail(address) {
            return address.trimmingCharacters(in: .whitespaces).lowercased()
        }
        return String(digits(address).suffix(10))
    }
}
