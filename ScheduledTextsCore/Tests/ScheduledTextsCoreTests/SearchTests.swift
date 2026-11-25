import Foundation
import XCTest
@testable import ScheduledTextsCore

final class SearchTests: XCTestCase {
    private let message = ScheduledMessage(
        recipientName: "Zoë Park",
        recipientAddress: "(555) 123-4567",
        body: "Happy birthday! Want to get dinner Friday?",
        sendAt: Date()
    )

    func testMatchesTextNameAndNumber() {
        XCTAssertTrue(message.matches(search: ""))
        XCTAssertTrue(message.matches(search: "birthday"))
        XCTAssertTrue(message.matches(search: "DINNER"))
        XCTAssertTrue(message.matches(search: "zoe"))
        XCTAssertTrue(message.matches(search: "park dinner"))
        XCTAssertTrue(message.matches(search: "5551234"))
        XCTAssertTrue(message.matches(search: "123-4567"))
        XCTAssertFalse(message.matches(search: "lunch"))
        XCTAssertFalse(message.matches(search: "zoe lunch"))
        XCTAssertFalse(message.matches(search: "999"))
    }
}
