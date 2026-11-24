import XCTest
@testable import ScheduledTextsCore

final class ContactInitialsTests: XCTestCase {
    func testFirstAndLastWord() {
        XCTAssertEqual(ContactInitials.of("John Smith"), "JS")
        XCTAssertEqual(ContactInitials.of("Mary Ann van Dyke"), "MD")
    }

    func testOneWordGivesOneLetter() {
        XCTAssertEqual(ContactInitials.of("Cher"), "C")
        XCTAssertEqual(ContactInitials.of("  cher  "), "C")
    }

    func testLowercaseAndAccentsAreKept() {
        XCTAssertEqual(ContactInitials.of("josé álvarez"), "JÁ")
    }

    func testPunctuationIsSkipped() {
        XCTAssertEqual(ContactInitials.of("Smith, John"), "SJ")
        XCTAssertEqual(ContactInitials.of("Pat O'Brien"), "PO")
        XCTAssertEqual(ContactInitials.of("Mary-Jane Watson"), "MW")
    }

    func testNoLettersGivesEmpty() {
        XCTAssertEqual(ContactInitials.of("(555) 123-4567"), "")
        XCTAssertEqual(ContactInitials.of(""), "")
    }

    func testDigitsInsideANameAreIgnored() {
        XCTAssertEqual(ContactInitials.of("Apartment 4B"), "AB")
    }
}
