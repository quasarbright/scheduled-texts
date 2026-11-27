import XCTest
@testable import ScheduledTextsCore

final class BirthdayDedupTests: XCTestCase {
    func card(_ id: String, _ name: String, _ numbers: [String], _ m: Int = 12, _ d: Int = 3) -> ContactCard {
        ContactCard(id: id, name: name,
                    addresses: numbers.map { ContactAddress(kind: .mobile, label: "mobile", value: $0) },
                    birthday: DateComponents(month: m, day: d))
    }

    func testSameNameSameBirthdayIsOnePerson() {
        let result = BirthdayContact.deduplicated([
            card("icloud", "Kate Bell", ["(555) 123-4567"]),
            card("gmail", "kate bell ", ["555-999-0000", "555-999-0001"]),
        ])
        XCTAssertEqual(result.map(\.id), ["gmail"], "keeps the card with more numbers")
    }

    func testSharedNumberSameBirthdayIsOnePerson() {
        let result = BirthdayContact.deduplicated([
            card("a", "Kate Bell", ["+1 (555) 123-4567"]),
            card("b", "Katie", ["5551234567"]),
        ])
        XCTAssertEqual(result.map(\.id), ["a"])
    }

    func testChainsThroughSharedKeys() {
        // a and b share a name, b and c share a number.
        let result = BirthdayContact.deduplicated([
            card("a", "Kate Bell", ["555-000-0001"]),
            card("b", "Kate Bell", ["555-000-0002"]),
            card("c", "K", ["555-000-0002"]),
        ])
        XCTAssertEqual(result.count, 1)
    }

    func testPrefersCardThatAlreadyHasAText() {
        let result = BirthdayContact.deduplicated([
            card("icloud", "Kate Bell", ["555-123-4567"]),
            card("gmail", "Kate Bell", ["555-999-0000", "555-999-0001"]),
        ], preferring: ["icloud"])
        XCTAssertEqual(result.map(\.id), ["icloud"])
    }

    func testDifferentBirthdaysStaySeparate() {
        // Twins, or two people named John Smith.
        let result = BirthdayContact.deduplicated([
            card("a", "John Smith", ["555-123-4567"], 1, 2),
            card("b", "John Smith", ["555-123-4567"], 5, 6),
        ])
        XCTAssertEqual(result.count, 2)
    }

    func testDifferentPeopleSameBirthdayStaySeparate() {
        let result = BirthdayContact.deduplicated([
            card("a", "Kate Bell", ["555-123-4567"]),
            card("b", "Dad", ["555-765-4321"]),
        ])
        XCTAssertEqual(result.map(\.id), ["a", "b"])
    }

    func testOneCardWithManyNumbersIsOneBirthday() {
        let result = BirthdayContact.deduplicated([card("a", "Kate", ["555-1", "555-2", "555-3"])])
        XCTAssertEqual(result.count, 1)
    }
}
