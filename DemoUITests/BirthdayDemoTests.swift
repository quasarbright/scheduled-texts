import XCTest

/// Walks through Birthday Texts and saves a screenshot at each step.
///
/// Needs contacts with birthdays (one within the next week) and Contacts
/// access granted before launch:
/// `xcrun simctl addmedia <udid> birthdays.vcf`
/// `xcrun simctl privacy <udid> grant contacts com.quasarbright.ScheduledTexts`
/// Pass the soonest birthday's first name in BIRTHDAY_FIRST (default "Ava").
final class BirthdayDemoTests: XCTestCase {
    func testBirthdayTexts() throws {
        let first = ProcessInfo.processInfo.environment["BIRTHDAY_FIRST"] ?? "Ava"
        let app = XCUIApplication()
        app.launch()
        dismissAlerts()

        // a. The prompt card, with Birthday Texts off.
        let schedule = app.buttons["Schedule for \(first)"]
        if !schedule.waitForExistence(timeout: 10) { print("TREE:\n\(app.debugDescription)") }
        XCTAssertTrue(schedule.exists)
        sleep(1)
        shot("01-prompt-card")

        // g. "Schedule for X" opens New Text, filled in.
        schedule.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        sleep(1)
        shot("02-schedule-for-draft")
        app.swipeUp()
        sleep(1)
        shot("03-schedule-for-draft-when")
        app.buttons["Cancel"].tap()
        let discard = app.buttons["Discard"]
        if discard.waitForExistence(timeout: 2) {
            shot("03b-schedule-for-cancel-asks")
            discard.tap()
        }
        sleep(1)

        // b. Turn On for Everyone: Settings opens and the switch flips on.
        app.buttons["Turn On for Everyone"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        sleep(2)
        dismissAlerts()
        shot("04-settings-on")

        // c. People: Disable All, Enable All (on the first section header).
        let people = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'People'")).firstMatch
        if !people.waitForExistence(timeout: 5) { print("TREE:\n\(app.debugDescription)") }
        people.tap()
        XCTAssertTrue(app.navigationBars["Birthdays"].waitForExistence(timeout: 5))
        sleep(1)
        shot("05-people")
        app.swipeUp()
        sleep(1)
        shot("05b-people-end")
        app.swipeDown()
        app.buttons["Disable All"].tap()
        sleep(1)
        shot("06-people-select-none")
        app.buttons["Enable All"].tap()
        sleep(1)
        shot("07-people-select-all")
        app.navigationBars["Birthdays"].buttons.firstMatch.tap()
        sleep(1)
        shot("08-settings-after-people")
        app.navigationBars["Settings"].buttons["Done"].tap()
        sleep(1)

        // d. One Birthdays row under Scheduled, and the Birthdays list.
        shot("09-list-birthdays-row")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Birthdays'")).firstMatch
        if !row.waitForExistence(timeout: 5) { print("TREE:\n\(app.debugDescription)") }
        row.tap()
        XCTAssertTrue(app.navigationBars["Birthdays"].waitForExistence(timeout: 5))
        sleep(1)
        shot("10-birthdays-list")
        app.swipeUp()
        sleep(1)
        shot("10b-birthdays-list-end")
        app.swipeDown()
        sleep(1)

        // e. Edit one person's birthday text.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", first)).firstMatch.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        sleep(1)
        shot("11-birthday-editor")
        let body = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value BEGINSWITH 'Happy birthday'")).firstMatch
        // Tap at the end of the text so the deletes clear it.
        body.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        app.typeText("Happy birthday \(first)! Dinner soon?")
        sleep(1)
        shot("12-birthday-editor-changed")
        app.buttons["Save"].tap()
        sleep(1)
        shot("13-birthdays-list-custom")
        app.navigationBars["Birthdays"].buttons.firstMatch.tap()
        sleep(1)

        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'People'")).firstMatch.tap()
        sleep(1)
        shot("14-people-custom")
        app.navigationBars["Birthdays"].buttons.firstMatch.tap()
        sleep(1)

        // f. Turn it off: the birthday texts go.
        let toggle = app.switches.firstMatch
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        sleep(1)
        shot("15-settings-off")
        app.navigationBars["Settings"].buttons["Done"].tap()
        sleep(2)
        shot("16-list-after-off")
    }

    private func dismissAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "Allow Full Access", "OK", "Continue"] {
            let b = springboard.alerts.buttons[name].firstMatch
            if b.waitForExistence(timeout: 1) { b.tap() }
        }
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
