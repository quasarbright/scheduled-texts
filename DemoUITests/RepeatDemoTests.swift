import XCTest

/// Walks through making a weekly repeating text (Mon, Tue, Wed) and saves a
/// screenshot of each screen, for checking the Repeat UI.
/// The screenshots are attachments in the test result; export them with
/// `xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>`.
///
/// On a fresh install, grant Contacts first or iOS's full-screen "How do you
/// want to share contacts?" sheet covers the editor:
/// `xcrun simctl privacy <udid> grant contacts com.quasarbright.ScheduledTexts`
final class RepeatDemoTests: XCTestCase {
    func testWeeklyRepeat() throws {
        let app = XCUIApplication()
        app.launch()
        dismissAlerts()

        app.buttons["New Text"].firstMatch.tap()
        dismissAlerts()

        let to = app.textFields["Name, number or email"]
        XCTAssertTrue(to.waitForExistence(timeout: 5))
        to.tap()
        to.typeText("5551234567\n")
        dismissAlerts()

        let body = app.textFields["What do you want to say?"]
        body.tap()
        body.typeText("Trash goes out tonight")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }

        let repeatRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Repeat'")).firstMatch
        if !repeatRow.waitForExistence(timeout: 3) { print("TREE:\n\(app.debugDescription)") }
        repeatRow.tap()
        XCTAssertTrue(app.navigationBars["Repeat"].waitForExistence(timeout: 5))
        sleep(1)
        shot("5-repeat-never")
        app.buttons["Custom"].tap()
        XCTAssertTrue(app.navigationBars["Custom"].waitForExistence(timeout: 5))

        // Frequency is a menu picker.
        let frequency = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Frequency'")).firstMatch
        if !frequency.waitForExistence(timeout: 3) { print("TREE:\n\(app.debugDescription)") }
        frequency.tap()
        app.buttons.matching(NSPredicate(format: "label == 'Weekly'")).firstMatch.tap()
        sleep(1)

        // Weekly starts on the send time's weekday. Make it exactly Mon/Tue/Wed.
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        for day in days {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", day)).firstMatch
            if !row.waitForExistence(timeout: 3) { print("TREE:\n\(app.debugDescription)") }
            XCTAssertTrue(row.exists, "No \(day) row")
            let checked = row.images["checkmark"].exists
            let want = ["Monday", "Tuesday", "Wednesday"].contains(day)
            if checked != want { row.tap() }
        }
        sleep(1)
        shot("3-custom-weekly")

        app.navigationBars["Custom"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Repeat"].waitForExistence(timeout: 5))
        sleep(1)
        shot("2-repeat-screen")

        app.navigationBars["Repeat"].buttons.firstMatch.tap()
        sleep(1)
        // Put the keyboard away, then scroll so the When section is in view.
        let done = app.buttons["Done"].firstMatch
        if done.exists { done.tap() }
        sleep(1)
        app.swipeUp()
        sleep(1)
        shot("1-editor-repeat")

        app.buttons["Save"].tap()
        sleep(2)
        dismissAlerts()
        shot("4-list-row")
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
