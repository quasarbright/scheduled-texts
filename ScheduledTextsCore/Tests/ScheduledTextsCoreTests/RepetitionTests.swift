import Foundation
import XCTest
@testable import ScheduledTextsCore

final class RepetitionTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// The first `count` repeats after the anchor.
    private func series(_ rule: Repetition, from anchor: Date, count: Int) -> [Date] {
        var out: [Date] = []
        var last = anchor
        while out.count < count, let next = rule.nextOccurrence(after: last, anchor: anchor, calendar: calendar) {
            out.append(next)
            last = next
        }
        return out
    }

    func testDaily() {
        // Wed Nov 25 2026, 9 AM.
        let anchor = date(2026, 11, 25)
        XCTAssertEqual(series(.daily, from: anchor, count: 3), [date(2026, 11, 26), date(2026, 11, 27), date(2026, 11, 28)])
        XCTAssertEqual(
            series(Repetition(frequency: .daily, interval: 3), from: anchor, count: 2),
            [date(2026, 11, 28), date(2026, 12, 1)]
        )
    }

    func testDailyKeepsTimeAcrossDaylightSaving() {
        // DST ends Nov 1 2026 in New York.
        let anchor = date(2026, 10, 31, 8, 30)
        XCTAssertEqual(series(.daily, from: anchor, count: 2), [date(2026, 11, 1, 8, 30), date(2026, 11, 2, 8, 30)])
    }

    func testWeeklyOnChosenDays() {
        // Mon, Tue, Wed. Anchor is Wed Nov 25.
        let rule = Repetition(frequency: .weekly, weekdays: [2, 3, 4])
        XCTAssertEqual(
            series(rule, from: date(2026, 11, 25), count: 4),
            [date(2026, 11, 30), date(2026, 12, 1), date(2026, 12, 2), date(2026, 12, 7)]
        )
    }

    func testEveryOtherWeekKeepsItsWeeks() {
        // Every 2 weeks on Mon and Fri, starting Mon Nov 23.
        let rule = Repetition(frequency: .weekly, interval: 2, weekdays: [2, 6])
        XCTAssertEqual(
            series(rule, from: date(2026, 11, 23), count: 4),
            [date(2026, 11, 27), date(2026, 12, 7), date(2026, 12, 11), date(2026, 12, 21)]
        )
    }

    func testPlainWeeklyUsesTheAnchorsDay() {
        XCTAssertEqual(series(.weekly, from: date(2026, 11, 25), count: 2), [date(2026, 12, 2), date(2026, 12, 9)])
    }

    func testMonthlySkipsShortMonths() {
        // Like Calendar: the 31st skips months without one.
        XCTAssertEqual(
            series(.monthly, from: date(2027, 1, 31), count: 3),
            [date(2027, 3, 31), date(2027, 5, 31), date(2027, 7, 31)]
        )
    }

    func testMonthlyOnAWeekday() {
        let first = Repetition(frequency: .monthly, monthlyWeekday: .init(ordinal: 1, weekday: 2))
        XCTAssertEqual(series(first, from: date(2026, 11, 2), count: 2), [date(2026, 12, 7), date(2027, 1, 4)])

        let last = Repetition(frequency: .monthly, monthlyWeekday: .init(ordinal: -1, weekday: 6))
        XCTAssertEqual(series(last, from: date(2026, 11, 27), count: 2), [date(2026, 12, 25), date(2027, 1, 29)])
    }

    func testOrdinalWeekdayOfADate() {
        XCTAssertEqual(Repetition.OrdinalWeekday.of(date(2026, 11, 25), calendar: calendar), .init(ordinal: 4, weekday: 4))
        // Nov 30 2026 is the fifth Monday, which is the last one.
        XCTAssertEqual(Repetition.OrdinalWeekday.of(date(2026, 11, 30), calendar: calendar), .init(ordinal: -1, weekday: 2))
    }

    func testYearlySkipsMissingLeapDays() {
        XCTAssertEqual(series(.yearly, from: date(2028, 2, 29), count: 2), [date(2032, 2, 29), date(2036, 2, 29)])
        XCTAssertEqual(series(.yearly, from: date(2026, 12, 25), count: 1), [date(2027, 12, 25)])
    }

    func testEndDateIncludesThatWholeDay() {
        let rule = Repetition(frequency: .daily, endDate: date(2026, 11, 27, 0, 0))
        XCTAssertEqual(series(rule, from: date(2026, 11, 25, 21, 0), count: 5), [date(2026, 11, 26, 21, 0), date(2026, 11, 27, 21, 0)])
    }

    func testSummaries() {
        let wed = date(2026, 11, 25)
        func s(_ r: Repetition, _ anchor: Date = wed) -> String {
            r.summary(anchor: anchor, calendar: calendar, locale: Locale(identifier: "en_US"))
        }
        XCTAssertEqual(s(.daily), "Every Day")
        XCTAssertEqual(s(.biweekly), "Every 2 Weeks")
        XCTAssertEqual(s(Repetition(frequency: .weekly, weekdays: [4])), "Every Week")
        XCTAssertEqual(s(Repetition(frequency: .weekly, weekdays: [2, 4])), "Every Week on Monday and Wednesday")
        XCTAssertEqual(s(Repetition(frequency: .weekly, weekdays: [2, 3, 4])), "Every Week on Monday, Tuesday, and Wednesday")
        XCTAssertEqual(s(Repetition(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])), "Every Week on Weekdays")
        XCTAssertEqual(s(Repetition(frequency: .daily, interval: 3)), "Every 3 Days")
        XCTAssertEqual(s(Repetition(frequency: .monthly, interval: 2)), "Every 2 Months on the 25th")
        XCTAssertEqual(
            s(Repetition(frequency: .monthly, monthlyWeekday: .init(ordinal: 1, weekday: 2))),
            "Every Month on the first Monday"
        )
        XCTAssertEqual(s(Repetition(frequency: .yearly, interval: 2)), "Every 2 Years")
        // The end date doesn't change the name.
        XCTAssertEqual(s(Repetition(frequency: .daily, endDate: wed)), "Every Day")
    }

    func testDayOrdinals() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map(Repetition.dayOrdinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd", "31st"])
    }

    // MARK: - A repeating text

    func testSendingMovesToTheNextOne() {
        let message = ScheduledMessage(recipientAddress: "1", body: "hi", sendAt: date(2026, 11, 25), repetition: .daily)
        let next = message.nextInSeries(now: date(2026, 11, 25, 9, 5), calendar: calendar)
        XCTAssertEqual(next?.id, message.id)
        XCTAssertEqual(next?.sendAt, date(2026, 11, 26))
        XCTAssertEqual(next?.seriesAnchor, date(2026, 11, 25))
    }

    func testSendingEarlyCountsAsThisOne() {
        // Send Now the day before: tomorrow's is done, so the next is the day after.
        let message = ScheduledMessage(recipientAddress: "1", body: "hi", sendAt: date(2026, 11, 26), repetition: .daily)
        XCTAssertEqual(message.nextInSeries(now: date(2026, 11, 25, 15, 0), calendar: calendar)?.sendAt, date(2026, 11, 27))
    }

    func testSendingLateSkipsTheMissedOnes() {
        let message = ScheduledMessage(recipientAddress: "1", body: "hi", sendAt: date(2026, 11, 25), repetition: .daily)
        XCTAssertEqual(message.nextInSeries(now: date(2026, 11, 28, 12, 0), calendar: calendar)?.sendAt, date(2026, 11, 29))
    }

    func testRemindLaterKeepsTheSchedule() {
        let message = ScheduledMessage(recipientAddress: "1", body: "hi", sendAt: date(2026, 11, 25), repetition: .weekly)
        let reminded = message.reminded(at: date(2026, 11, 25, 20, 0))
        XCTAssertEqual(reminded.scheduledAt, date(2026, 11, 25))
        XCTAssertEqual(reminded.nextInSeries(now: date(2026, 11, 25, 20, 1), calendar: calendar)?.sendAt, date(2026, 12, 2))
    }

    func testOneOffTextsDontRepeat() {
        let message = ScheduledMessage(recipientAddress: "1", body: "hi", sendAt: date(2026, 11, 25))
        XCTAssertNil(message.nextInSeries(now: date(2026, 11, 25), calendar: calendar))
        XCTAssertNil(message.reminded(at: date(2026, 11, 26)).occurrence)
    }

    func testEndedSeriesHasNoNext() {
        let rule = Repetition(frequency: .daily, endDate: date(2026, 11, 25))
        let message = ScheduledMessage(recipientAddress: "1", body: "hi", sendAt: date(2026, 11, 25), repetition: rule)
        XCTAssertNil(message.nextInSeries(now: date(2026, 11, 25, 9, 1), calendar: calendar))
    }

    func testOldSavedTextsStillLoad() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","recipientAddress":"1","body":"hi","sendAt":0}"#
        let message = try JSONDecoder().decode(ScheduledMessage.self, from: Data(json.utf8))
        XCTAssertNil(message.repetition)
    }

    func testRepeatingTextsRoundTrip() throws {
        let message = ScheduledMessage(
            recipientAddress: "1", body: "hi", sendAt: date(2026, 11, 25),
            repetition: Repetition(frequency: .monthly, interval: 2, monthlyWeekday: .init(ordinal: -1, weekday: 6), endDate: date(2027, 6, 1))
        )
        let decoded = try JSONDecoder().decode(ScheduledMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded, message)
    }
}
