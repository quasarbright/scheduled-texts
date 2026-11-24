import Foundation

/// The letters shown in a contact's avatar when they have no photo, like
/// Messages: the first letters of the first and last words of their name.
public enum ContactInitials {
    /// "John Smith" → "JS", "Cher" → "C", "Mary Ann van Dyke" → "MD".
    /// Empty when the name has no letters to show, like a phone number,
    /// so the avatar can show a person symbol instead.
    public static func of(_ name: String) -> String {
        // The first letter of each space-separated word that has one, so
        // "O'Brien" and "Mary-Jane" count as one word each.
        let letters = name
            .components(separatedBy: .whitespacesAndNewlines)
            .compactMap { $0.first(where: \.isLetter) }
        guard let first = letters.first else { return "" }
        guard letters.count > 1, let last = letters.last else {
            return String(first).uppercased()
        }
        return (String(first) + String(last)).uppercased()
    }
}
