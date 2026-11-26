import XCTest
@testable import ScheduledTextsCore

final class BirthdayTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    lazy var now = date(2026, 11, 26, 12)
    let kate = BirthdayContact(id: "kate", name: "Kate Bell", address: "555-1", month: 12, day: 3)
    let dad = BirthdayContact(id: "dad", name: "Dad", address: "555-2", month: 12, day: 7)
    let leap = BirthdayContact(id: "leap", name: "Lee", address: "555-3", month: 2, day: 29)

    func on() -> BirthdaySettings {
        var s = BirthdaySettings()
        s.enabled = true
        return s
    }

    func birthdayTexts(_ q: MessageQueue) -> [ScheduledMessage] {
        q.messages.filter { $0.birthdayContactID != nil }
    }

    func testDefaults() {
        let s = BirthdaySettings()
        XCTAssertFalse(s.enabled)
        XCTAssertEqual(s.message, "Happy birthday!")
        XCTAssertEqual(s.hour, 9)
        XCTAssertTrue(s.addNewBirthdays)
    }

    func testOffMakesNothing() {
        var s = BirthdaySettings()
        let q = BirthdayPlanner.reconcile(queue: MessageQueue(), contacts: [kate], settings: &s, now: now, calendar: calendar)
        XCTAssertTrue(q.isEmpty)
    }

    func testOnMakesYearlyTextAtNineOnTheBirthday() {
        var s = on()
        let q = BirthdayPlanner.reconcile(queue: MessageQueue(), contacts: [kate, dad], settings: &s, now: now, calendar: calendar)
        let texts = birthdayTexts(q)
        XCTAssertEqual(texts.count, 2)
        let k = texts.first { $0.birthdayContactID == "kate" }!
        XCTAssertEqual(k.sendAt, date(2026, 12, 3, 9))
        XCTAssertEqual(k.body, "Happy birthday!")
        XCTAssertEqual(k.repetition, .yearly)
        XCTAssertEqual(k.recipientAddress, "555-1")
        XCTAssertEqual(s.known, ["kate", "dad"])
    }

    func testReconcileIsStable() {
        var s = on()
        let q1 = BirthdayPlanner.reconcile(queue: MessageQueue(), contacts: [kate], settings: &s, now: now, calendar: calendar)
        let q2 = BirthdayPlanner.reconcile(queue: q1, contacts: [kate], settings: &s, now: now, calendar: calendar)
        XCTAssertEqual(q1, q2)
    }

    func testBirthdayAlreadyPastToday() {
        var s = on()
        let today = BirthdayContact(id: "t", name: "T", address: "1", month: 11, day: 26)
        let q = BirthdayPlanner.reconcile(queue: MessageQueue(), contacts: [today], settings: &s, now: now, calendar: calendar)
        XCTAssertEqual(q.messages.first?.sendAt, date(2027, 11, 26, 9))
    }

    func testLeapDayWaitsForLeapYear() {
        var s = on()
        let q = BirthdayPlanner.reconcile(queue: MessageQueue(), contacts: [leap], settings: &s, now: now, calendar: calendar)
        XCTAssertEqual(q.messages.first?.sendAt, date(2028, 2, 29, 9))
    }

    func testMessageTimeAndOverrideUpdates() {
        var s = on()
        var q = BirthdayPlanner.reconcile(queue: MessageQueue(), contacts: [kate, dad], settings: &s, now: now, calendar: calendar)
        s.message = "HBD!"
        s.hour = 8
        s.customMessages["dad"] = "Happy birthday Dad!"
        q = BirthdayPlanner.reconcile(queue: q, contacts: [kate, dad], settings: &s, now: now, calendar: calendar)
        let k = q.messages.first { $0.birthdayContactID == "kate" }!
        let d = q.messages.first { $0.birthdayContactID == "dad" }!
        XCTAssertEqual(k.body, "HBD!")
        XCTAssertEqual(k.sendAt, date(2026, 12, 3, 8))
        XCTAssertEqual(d.body, "Happy birthday Dad!")
    }

    func testExcludedAndRemovedContactsLoseTheirText() {
        var s = on()
        var q = BirthdayPlanner.reconcile(queue: MessageQueue(), contacts: [kate, dad], settings: &s, now: now, calendar: calendar)
        s.excluded = ["kate"]
        q = BirthdayPlanner.reconcile(queue: q, contacts: [dad], settings: &s, now: now, calendar: calendar)
        XCTAssertEqual(birthdayTexts(q).map(\.birthdayContactID), ["dad"])
    }

    func testTurningOffRemovesThemButKeepsOtherTexts() {
        var s = on()
        var q = MessageQueue([ScheduledMessage(recipientAddress: "9", body: "mine", sendAt: date(2026, 12, 1))])
        q = BirthdayPlanner.reconcile(queue: q, contacts: [kate], settings: &s, now: now, calendar: calendar)
        s.enabled = false
        q = BirthdayPlanner.reconcile(queue: q, contacts: [kate], settings: &s, now: now, calendar: calendar)
        XCTAssertEqual(q.messages.map(\.body), ["mine"])
    }

    func testReadyBirthdayTextStaysWhenTurnedOffButStopsRepeating() {
        var s = on()
        var q = BirthdayPlanner.reconcile(queue: MessageQueue(), contacts: [kate], settings: &s, now: now, calendar: calendar)
        let birthday = date(2026, 12, 3, 10)
        s.enabled = false
        q = BirthdayPlanner.reconcile(queue: q, contacts: [kate], settings: &s, now: birthday, calendar: calendar)
        XCTAssertEqual(q.messages.count, 1)
        XCTAssertNil(q.messages[0].repetition)
        XCTAssertNil(q.messages[0].birthdayContactID)
    }

    func testRemindLaterIsNotUndone() {
        var s = on()
        var q = BirthdayPlanner.reconcile(queue: MessageQueue(), contacts: [kate], settings: &s, now: now, calendar: calendar)
        let birthday = date(2026, 12, 3, 9, 30)
        let reminded = q.messages[0].reminded(at: date(2026, 12, 3, 13))
        q.upsert(reminded)
        q = BirthdayPlanner.reconcile(queue: q, contacts: [kate], settings: &s, now: birthday, calendar: calendar)
        XCTAssertEqual(q.messages[0].sendAt, date(2026, 12, 3, 13))
    }

    func testAddNewBirthdaysOff() {
        var s = on()
        s.addNewBirthdays = false
        var q = BirthdayPlanner.reconcile(queue: MessageQueue(), contacts: [kate], settings: &s, now: now, calendar: calendar)
        // Kate was there when it was turned on, so she's in.
        XCTAssertEqual(birthdayTexts(q).count, 1)
        q = BirthdayPlanner.reconcile(queue: q, contacts: [kate, dad], settings: &s, now: now, calendar: calendar)
        XCTAssertEqual(birthdayTexts(q).map(\.birthdayContactID), ["kate"])
        XCTAssertTrue(s.excluded.contains("dad"))
    }

    func testHandmadeYearlyTextIsNotDuplicated() {
        var s = on()
        let handmade = BirthdayPlanner.handmadeText(for: kate, settings: s, now: now, calendar: calendar)!
        let q = BirthdayPlanner.reconcile(queue: MessageQueue([handmade]), contacts: [kate], settings: &s, now: now, calendar: calendar)
        XCTAssertEqual(q.messages.count, 1)
        XCTAssertNil(q.messages[0].birthdayContactID)
    }

    func testPromptSoonestWithinAWeekWithoutText() {
        let s = BirthdaySettings()
        let far = BirthdayContact(id: "far", name: "Far", address: "1", month: 1, day: 20)
        let p = BirthdayPlanner.prompt(contacts: [dad, kate, far], queue: MessageQueue(), settings: s, now: now, calendar: calendar)
        XCTAssertEqual(p?.contact.id, "kate")
        XCTAssertEqual(p?.day, date(2026, 12, 3))
    }

    func testNoPromptWhenOnScheduledDismissedOrFar() {
        var s = BirthdaySettings()
        XCTAssertNil(BirthdayPlanner.prompt(contacts: [dad], queue: MessageQueue(), settings: s, now: now, calendar: calendar))
        let handmade = BirthdayPlanner.handmadeText(for: kate, settings: s, now: now, calendar: calendar)!
        XCTAssertNil(BirthdayPlanner.prompt(contacts: [kate], queue: MessageQueue([handmade]), settings: s, now: now, calendar: calendar))
        s.dismissedPrompts = [BirthdayPlanner.promptKey("kate", day: date(2026, 12, 3), calendar: calendar)]
        XCTAssertNil(BirthdayPlanner.prompt(contacts: [kate], queue: MessageQueue(), settings: s, now: now, calendar: calendar))
        var enabled = BirthdaySettings(); enabled.enabled = true
        XCTAssertNil(BirthdayPlanner.prompt(contacts: [kate], queue: MessageQueue(), settings: enabled, now: now, calendar: calendar))
    }

    func testPromptIncludesToday() {
        let today = BirthdayContact(id: "t", name: "T", address: "1", month: 11, day: 26)
        let p = BirthdayPlanner.prompt(contacts: [today, kate], queue: MessageQueue(), settings: BirthdaySettings(), now: now, calendar: calendar)
        XCTAssertEqual(p?.contact.id, "t")
    }

    func testOldSavedTextsStillDecode() throws {
        let json = #"{"version":1,"messages":[{"id":"5B1E0B0E-1C55-4E0B-9D0E-1F2B9C1D2E3F","recipientAddress":"555","body":"hi","sendAt":0}]}"#
        let q = try MessageStorage.decode(Data(json.utf8))
        XCTAssertNil(q.messages[0].birthdayContactID)
    }
}
