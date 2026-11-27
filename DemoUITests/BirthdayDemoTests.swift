import XCTest

/// Walks through Birthday Texts and saves a screenshot at each step.
///
/// Needs contacts with birthdays (one within the next week) and Contacts
/// access granted before launch:
/// `xcrun simctl addmedia <udid> birthdays.vcf`
/// `xcrun simctl privacy <udid> grant contacts com.quasarbright.ScheduledTexts`
/// Pass the soonest birthday's name in BIRTHDAY_NAME (default "Ava Chen");
/// with xcodebuild, set TEST_RUNNER_BIRTHDAY_NAME.
final class BirthdayDemoTests: XCTestCase {
    private var app: XCUIApplication!
    private var person = "Ava Chen"
    private var first: String { String(person.split(separator: " ").first ?? "") }

    func testBirthdayTexts() throws {
        person = ProcessInfo.processInfo.environment["BIRTHDAY_NAME"] ?? person
        app = XCUIApplication()
        app.launch()
        dismissAlerts()

        // The prompt card, with Birthday Texts off.
        let schedule = app.buttons["Schedule for \(first)"]
        if !schedule.waitForExistence(timeout: 10) { print("TREE:\n\(app.debugDescription)") }
        XCTAssertTrue(schedule.exists)
        sleep(1)
        shot("01-prompt-card")

        // "Schedule for X" opens New Text, filled in. Cancel on an
        // untouched one closes without asking.
        schedule.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        sleep(1)
        shot("02-schedule-for-draft")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Discard"].waitForExistence(timeout: 2), "Cancel asked to discard an untouched draft")
        sleep(1)

        // Turn On for Everyone lands on Birthdays and flips the switch.
        app.buttons["Turn On for Everyone"].tap()
        XCTAssertTrue(app.navigationBars["Birthdays"].waitForExistence(timeout: 5))
        sleep(2)
        dismissAlerts()
        XCTAssertEqual(birthdaySwitch.value as? String, "1", "The switch didn't flip on")
        shot("03-birthdays-on")
        app.swipeUp()
        sleep(1)
        shot("04-birthdays-on-scrolled")
        app.swipeDown()
        sleep(1)

        // The checkmark turns one person off and on.
        let check = app.buttons.matching(NSPredicate(format: "label == %@", person)).firstMatch
        XCTAssertTrue(check.exists)
        check.tap()
        sleep(1)
        XCTAssertTrue(personRow.label.contains("No text"), "Checkmark didn't turn \(first) off: \(personRow.label)")
        shot("05-birthdays-one-off")
        check.tap()
        sleep(1)
        XCTAssertFalse(personRow.label.contains("No text"))

        // Disable All / Enable All.
        app.buttons["Disable All"].tap()
        sleep(1)
        shot("06-birthdays-disable-all")
        app.buttons["Enable All"].tap()
        sleep(1)

        // Tapping the row opens that person's text; Cancel, Save and
        // Don't Send each close only the editor.
        openEditor()
        shot("07-editor-from-row")
        app.buttons["Cancel"].tap()
        assertBackOnBirthdays("Cancel")

        openEditor()
        // The Birthdays screen behind the sheet has a "Happy birthday!"
        // field too; the editor's is the lower one.
        let body = app.descendants(matching: .any)
            .matching(NSPredicate(format: "value BEGINSWITH 'Happy birthday'"))
            .allElementsBoundByIndex.max { $0.frame.minY < $1.frame.minY }!
        body.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        app.typeText("Happy birthday \(first)! Dinner soon?")
        app.buttons["Save"].tap()
        assertBackOnBirthdays("Save")
        XCTAssertTrue(personRow.label.contains("Dinner soon"), "Custom message not shown: \(personRow.label)")
        shot("08-birthdays-custom-message")

        openEditor()
        app.swipeUp()
        sleep(1)
        app.buttons["Don't Send"].firstMatch.tap()
        let skip = app.buttons["Skip This One"].firstMatch
        if skip.waitForExistence(timeout: 3) {
            shot("09-editor-dont-send-asks")
            skip.tap()
        }
        assertBackOnBirthdays("Don't Send")
        shot("09b-after-skip")
        // Skipping one year keeps them a birthday text.
        XCTAssertFalse(personRow.label.contains("No text"), "Skip This One turned \(first)'s birthday text off: \(personRow.label)")

        // Send Now: the editor and Settings close, and the compose screen
        // opens (the simulator can't send, so it says so).
        openEditor()
        app.swipeUp()
        sleep(1)
        app.buttons["Send Now"].firstMatch.tap()
        sleep(2)
        shot("10-editor-send-now")
        let cantSend = app.alerts["This iPhone can't send texts"]
        XCTAssertTrue(cantSend.waitForExistence(timeout: 5), "No compose screen or can't-send alert after Send Now")
        cantSend.buttons["OK"].tap()
        sleep(1)
        shot("11-after-send-now")

        // Settings shows one Birthdays row.
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        sleep(1)
        shot("12-settings")
        app.navigationBars["Settings"].buttons["Done"].tap()
        sleep(1)

        // The list's Birthdays row opens the same screen.
        shot("13-list-birthdays-row")
        let listRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Birthdays'")).firstMatch
        XCTAssertTrue(listRow.waitForExistence(timeout: 5))
        listRow.tap()
        XCTAssertTrue(app.navigationBars["Birthdays"].waitForExistence(timeout: 5))
        XCTAssertTrue(birthdaySwitch.exists, "List's Birthdays row didn't open the Birthdays screen")
        sleep(1)
        shot("14-birthdays-from-list")
        openEditor()
        app.buttons["Cancel"].tap()
        assertBackOnBirthdays("Cancel from the list's Birthdays")

        // Turn it off.
        birthdaySwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        sleep(1)
        XCTAssertEqual(birthdaySwitch.value as? String, "0")
        shot("15-birthdays-off")
        app.navigationBars["Birthdays"].buttons.firstMatch.tap()
        sleep(2)
        shot("16-list-after-off")
    }

    private var birthdaySwitch: XCUIElement {
        app.switches.matching(NSPredicate(format: "label CONTAINS 'Birthday Texts'")).firstMatch
    }

    /// The row's main button (not the checkmark, whose label is just the name).
    private var personRow: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label != %@", person, person)).firstMatch
    }

    private func openEditor() {
        let row = personRow
        if !row.waitForExistence(timeout: 5) { print("TREE:\n\(app.debugDescription)") }
        row.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5), "Row didn't open the editor")
        sleep(1)
    }

    private func assertBackOnBirthdays(_ action: String, line: UInt = #line) {
        sleep(1)
        XCTAssertFalse(app.buttons["Save"].exists, "\(action) didn't close the editor", line: line)
        XCTAssertTrue(app.navigationBars["Birthdays"].exists, "\(action) closed more than the editor", line: line)
        XCTAssertTrue(birthdaySwitch.exists, "\(action) left the Birthdays screen", line: line)
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
