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
        // The question is still open, so nothing has been deleted yet: the
        // row must still be in the list. (A destructive swipe button
        // dropped it here, which is what crashed the list on 2026-11-27.)
        assertRowStillListed(app, body)
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
        assertRowStillListed(app, "Due stop test", under: "Ready to Send")
        stop.tap()
        sleep(2)

        XCTAssertEqual(app.state, .runningForeground, "The app crashed")
        XCTAssertFalse(app.staticTexts["Due stop test"].exists)
    }

    /// The crash, made repeatable: two repeating texts in one section, stop
    /// the second. With the old destructive swipe button the list dropped
    /// that row at once, and the store's delete then asked UIKit to delete
    /// it again: "attempt to delete item 1 from section 1 which only
    /// contains 1 items before the update". Red on 755bc21^, green after.
    func testStopRepeatingSecondOfTwo() throws {
        let app = XCUIApplication()
        app.launch()
        dismissAlerts()
        let first = makeDailyText(app)
        let second = makeDailyText(app)
        let row = app.staticTexts[second].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Don't Send"].firstMatch.tap()
        let stop = app.buttons["Stop Repeating"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        assertRowStillListed(app, second)
        stop.tap()
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "The app crashed")
        XCTAssertFalse(app.staticTexts[second].exists)
        XCTAssertTrue(app.staticTexts[first].exists)
    }

    /// Don't Send, then backing out of "This text repeats": nothing was
    /// deleted, so the row stays (and stays after the question closes).
    func testCancelKeepsTheRow() throws {
        let app = XCUIApplication()
        app.launch()
        dismissAlerts()
        let body = makeDailyText(app)
        let row = app.staticTexts[body].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Don't Send"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Stop Repeating"].firstMatch.waitForExistence(timeout: 5))
        assertRowStillListed(app, body)

        // The question is a popover: Cancel, or a tap outside it.
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        }
        sleep(1)
        XCTAssertFalse(app.buttons["Stop Repeating"].exists, "The question didn't close")
        assertRowStillListed(app, body)
        // And it's really still saved: it survives a relaunch.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[body].firstMatch.waitForExistence(timeout: 5), "Cancel deleted the text")
    }

    /// A new daily text an hour from now, with a unique message.
    private func makeDailyText(_ app: XCUIApplication) -> String {
        let body = "Cancel test \(Int.random(in: 1000...9999))"
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
        return body
    }

    /// The text's row is on screen in the list, and (when given) sits right
    /// under that section's header.
    private func assertRowStillListed(_ app: XCUIApplication, _ body: String, under header: String? = nil,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let text = app.staticTexts[body].firstMatch
        XCTAssertTrue(text.exists, "The row for \"\(body)\" left the list before anything was deleted", file: file, line: line)
        guard text.exists else { return }
        // Not isHittable: the open question is modal, so nothing behind it
        // is hittable. Check the row is laid out on screen instead.
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(text.frame), "The row for \"\(body)\" isn't on screen (\(text.frame))", file: file, line: line)
        XCTAssertGreaterThan(text.frame.height, 0, file: file, line: line)
        if let header {
            let h = app.staticTexts[header].firstMatch
            XCTAssertTrue(h.exists, "No \(header) section", file: file, line: line)
            let gap = text.frame.minY - h.frame.maxY
            XCTAssertTrue(gap > 0 && gap < 80, "\"\(body)\" isn't the row under \(header) (gap \(gap))", file: file, line: line)
        }
    }

    private func dismissAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "Allow Full Access", "OK", "Continue"] {
            let b = springboard.alerts.buttons[name].firstMatch
            if b.waitForExistence(timeout: 1) { b.tap() }
        }
    }
}
