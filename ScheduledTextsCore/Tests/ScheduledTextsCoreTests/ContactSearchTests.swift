import Foundation
import XCTest
@testable import ScheduledTextsCore

final class ContactSearchTests: XCTestCase {
    private func phone(_ kind: ContactAddress.Kind, _ value: String, label: String = "") -> ContactAddress {
        ContactAddress(kind: kind, label: label, value: value)
    }

    private lazy var john = ContactCard(
        id: "john", name: "John Smith", otherNames: ["Johnny"],
        addresses: [phone(.mobile, "(555) 123-4567", label: "mobile")]
    )
    private lazy var jose = ContactCard(
        id: "jose", name: "José Álvarez",
        addresses: [phone(.otherPhone, "+1 555 999 0000", label: "home")]
    )
    private lazy var amy = ContactCard(
        id: "amy", name: "Amy Johnson", otherNames: ["Acme Corp"],
        addresses: [ContactAddress(kind: .email, label: "work", value: "amy@acme.com")]
    )
    private lazy var noAddresses = ContactCard(id: "none", name: "Joan Nobody", addresses: [])
    private var all: [ContactCard] { [amy, jose, john, noAddresses] }

    func testDefaultAddressPrefersIPhoneThenMobileThenMainThenOtherThenEmail() {
        let email = ContactAddress(kind: .email, label: "home", value: "a@b.com")
        let home = phone(.otherPhone, "1", label: "home")
        let main = phone(.main, "2", label: "main")
        let mobile = phone(.mobile, "3", label: "mobile")
        let iPhone = phone(.iPhone, "4", label: "iPhone")

        func pick(_ addresses: [ContactAddress]) -> ContactAddress? {
            ContactCard(id: "x", name: "X", addresses: addresses).defaultAddress
        }
        XCTAssertEqual(pick([email, home, main, mobile, iPhone]), iPhone)
        XCTAssertEqual(pick([email, home, main, mobile]), mobile)
        XCTAssertEqual(pick([email, home, main]), main)
        XCTAssertEqual(pick([email, home]), home)
        XCTAssertEqual(pick([email]), email)
        XCTAssertNil(pick([]))
    }

    func testDefaultAddressTieGoesToFirstListed() {
        let first = phone(.mobile, "1")
        let second = phone(.mobile, "2")
        XCTAssertEqual(ContactCard(id: "x", name: "X", addresses: [first, second]).defaultAddress, first)
    }

    func testMatchesByNamePrefixes() {
        XCTAssertEqual(ContactSearch.matches("jo sm", in: all).map(\.id), ["john"])
        XCTAssertEqual(ContactSearch.matches("smith", in: all).map(\.id), ["john"])
        XCTAssertEqual(ContactSearch.matches("JOHNNY", in: all).map(\.id), ["john"])
        XCTAssertEqual(ContactSearch.matches("acme", in: all).map(\.id), ["amy"])
        XCTAssertEqual(ContactSearch.matches("mith", in: all).map(\.id), [])
    }

    func testMatchesIgnoreAccents() {
        XCTAssertEqual(ContactSearch.matches("jose alv", in: all).map(\.id), ["jose"])
    }

    func testSkipsContactsWithNothingToSendTo() {
        XCTAssertFalse(ContactSearch.matches("joan", in: all).contains { $0.id == "none" })
    }

    func testFirstNameMatchesRankAboveLastNameMatches() {
        // "jo" starts John's and José's first names but only Amy's last name.
        XCTAssertEqual(ContactSearch.matches("jo", in: all).map(\.id), ["john", "jose", "amy"])
    }

    func testEmptyQueryMatchesNothing() {
        XCTAssertEqual(ContactSearch.matches("  ", in: all), [])
    }

    func testMatchesByNumberDigits() {
        XCTAssertEqual(ContactSearch.matches("555-123", in: all).map(\.id), ["john"])
        XCTAssertEqual(ContactSearch.matches("999", in: all).map(\.id), ["jose"])
        // Too few digits to search numbers.
        XCTAssertEqual(ContactSearch.matches("55", in: all).map(\.id), [])
    }

    func testRespectsLimit() {
        let many = (0..<20).map { ContactCard(id: "\($0)", name: "Sam \($0)", addresses: [phone(.mobile, "\($0)")]) }
        XCTAssertEqual(ContactSearch.matches("sam", in: many, limit: 5).count, 5)
    }

    func testLooksLikeAddress() {
        XCTAssertTrue(ContactSearch.looksLikeAddress("555-1234"))
        XCTAssertTrue(ContactSearch.looksLikeAddress("+1 (555) 123-4567"))
        XCTAssertTrue(ContactSearch.looksLikeAddress("amy@acme.com"))
        XCTAssertFalse(ContactSearch.looksLikeAddress("amy"))
        XCTAssertFalse(ContactSearch.looksLikeAddress("amy@acme"))
        XCTAssertFalse(ContactSearch.looksLikeAddress("12"))
        XCTAssertFalse(ContactSearch.looksLikeAddress("john 555"))
    }

    func testContactWithAddressIgnoresFormatting() {
        XCTAssertEqual(ContactSearch.contact(withAddress: "+1 555-123-4567", in: all)?.id, "john")
        XCTAssertEqual(ContactSearch.contact(withAddress: "AMY@acme.com", in: all)?.id, "amy")
        XCTAssertNil(ContactSearch.contact(withAddress: "555-123-0000", in: all))
        XCTAssertNil(ContactSearch.contact(withAddress: "", in: all))
    }

    func testOldSavedTextsDecodeWithoutContactIdentifier() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","recipientName":"Al","recipientAddress":"1","body":"hi","sendAt":0}"#
        let message = try JSONDecoder().decode(ScheduledMessage.self, from: Data(json.utf8))
        XCTAssertNil(message.contactIdentifier)
        XCTAssertEqual(message.recipientName, "Al")
    }
}
