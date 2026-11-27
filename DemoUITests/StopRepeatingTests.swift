import XCTest

/// Swipe a repeating text on the list, tap Don't Send, then Stop Repeating.
/// This crashed the app (2026-11-27): the swipe button was destructive, so
/// the list dropped the row before the dialog was answered.
///
/// On a fresh install, grant Contacts first:
/// `xcrun simctl privacy <udid> grant contacts com.quasarbright.ScheduledTexts`
final class StopRepeatingTests: XCTestCase {
    func testStopRepeatingFromSwipe() throws {
        let app = XCUIApplication()
        app.launch()
        dismissAlerts()

        let body = "Stop repeating test \(Int.random(in: 1000...9999))"
        app.buttons["New Text"].firstMatch.tap()
        dismissAlerts()
        let to = app.textFields["Name, number or email"]
        XCTAssertTrue(to.waitForExistence(timeout: 5))
        to.tap()
        to.typeText("5551234567\n")
        dismissAlerts()
        let field = app.textFields["What do you want to say?"]
        field.tap()
        field.typeText(body)
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Repeat'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Repeat"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Every Day' OR label BEGINSWITH 'Daily'")).firstMatch.tap()
        sleep(1)
        app.buttons["Save"].tap()
        sleep(1)

        let row = app.staticTexts[body].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Don't Send"].firstMatch.tap()
        let stop = app.buttons["Stop Repeating"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        sleep(2)

        XCTAssertEqual(app.state, .runningForeground, "The app crashed")
        XCTAssertFalse(app.staticTexts[body].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Stopped repeating'")).firstMatch.exists)
    }

    /// The case that crashed on Mike's phone: a repeating text that's
    /// already due, in Ready to Send. Needs a seeded messages.json in the
    /// app group with a daily text "Due stop test" whose time has passed;
    /// skipped without it.
    func testStopRepeatingDueFromSwipe() throws {
        let app = XCUIApplication()
        app.launch()
        dismissAlerts()
        let row = app.staticTexts["Due stop test"].firstMatch
        guard row.waitForExistence(timeout: 5) else {
            throw XCTSkip("No seeded due text")
        }
        XCTAssertTrue(app.staticTexts["Ready to Send"].exists)
        row.swipeLeft()
        app.buttons["Don't Send"].firstMatch.tap()
        let stop = app.buttons["Stop Repeating"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        sleep(2)

        XCTAssertEqual(app.state, .runningForeground, "The app crashed")
        XCTAssertFalse(app.staticTexts["Due stop test"].exists)
    }

    private func dismissAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "Allow Full Access", "OK", "Continue"] {
            let b = springboard.alerts.buttons[name].firstMatch
            if b.waitForExistence(timeout: 1) { b.tap() }
        }
    }
}
