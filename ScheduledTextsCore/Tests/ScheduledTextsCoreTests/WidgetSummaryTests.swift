import XCTest
@testable import ScheduledTextsCore

final class WidgetSummaryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func text(_ name: String, _ minutes: Double) -> ScheduledMessage {
        ScheduledMessage(recipientName: name, recipientAddress: "555", body: "hi", sendAt: now.addingTimeInterval(minutes * 60))
    }

    func testReadyFirstThenSoonest() {
        let queue = MessageQueue([text("Later", 60), text("Old", -120), text("New", -5), text("Soon", 10), text("Far", 600)])
        let summary = WidgetSummary(queue: queue, now: now)
        XCTAssertEqual(summary.readyCount, 2)
        XCTAssertEqual(summary.texts.map(\.recipientName), ["Old", "New", "Soon"])
        XCTAssertEqual(summary.moreCount, 2)
        XCTAssertEqual(summary.next?.recipientName, "Old")
    }

    func testEmpty() {
        let summary = WidgetSummary(queue: MessageQueue(), now: now)
        XCTAssertNil(summary.next)
        XCTAssertEqual(summary.readyCount, 0)
        XCTAssertEqual(summary.moreCount, 0)
    }

    func testChangeDatesAreUpcomingSendTimesWithoutDuplicates() {
        let a = text("A", 10), b = text("B", 10), c = text("C", 30)
        let queue = MessageQueue([text("Due", -1), a, b, c])
        XCTAssertEqual(WidgetSummary.changeDates(queue: queue, now: now), [a.sendAt, c.sendAt])
    }

    func testDeepLinksRoundTrip() {
        let id = UUID()
        for link in [DeepLink.list, .new, .text(id)] {
            XCTAssertEqual(DeepLink(url: link.url), link)
        }
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/text/\(id)")!))
        XCTAssertNil(DeepLink(url: URL(string: "scheduledtexts://text/not-a-uuid")!))
    }
}
