import XCTest

/// Tries to reproduce the 2026-11-27 crash: on Mike's phone, swiping his
/// due yearly text, tapping Don't Send and then Stop Repeating crashed in
/// UICollectionView ("Invalid number of items in section").
///
/// Needs a seeded list (scripts in the commit message): a due repeating
/// text whose message contains "REPRO", in Ready to Send. Each round stops
/// it, checks the app is alive, and undoes, so the text comes back.
/// REPRO_ROUNDS sets how many rounds (default 20); REPRO_FULL_SWIPE=1 uses a
/// full swipe instead of tapping the swipe button.
final class StopRepeatingReproTests: XCTestCase {
    func testStopRepeatingDueTextRepeatedly() throws {
        let env = ProcessInfo.processInfo.environment
        let rounds = Int(env["REPRO_ROUNDS"] ?? "") ?? 20
        let fullSwipe = env["REPRO_FULL_SWIPE"] == "1"
        let app = XCUIApplication()
        app.launch()
        if env["REPRO_DENY_NOTIFICATIONS"] == "1" {
            // Leaves the "Notifications are off" section at the top.
            let deny = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Don’t Allow"].firstMatch
            if deny.waitForExistence(timeout: 3) { deny.tap() }
        }
        dismissAlerts()

        if env["REPRO_BIRTHDAYS"] == "1" { turnOnBirthdays(app) }

        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'REPRO'")).firstMatch
        guard row.waitForExistence(timeout: 8) else { throw XCTSkip("No seeded REPRO text") }

        for round in 1...rounds {
            XCTAssertTrue(row.waitForExistence(timeout: 8), "Round \(round): text didn't come back")
            if fullSwipe {
                let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                let end = row.coordinate(withNormalizedOffset: CGVector(dx: -0.6, dy: 0.5))
                start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
            } else {
                row.swipeLeft(velocity: .fast)
                app.buttons["Don't Send"].firstMatch.tap()
            }
            let stop = app.buttons["Stop Repeating"].firstMatch
            guard stop.waitForExistence(timeout: 3) else {
                XCTAssertEqual(app.state, .runningForeground, "Round \(round): crashed before the dialog")
                XCTFail("Round \(round): no Stop Repeating dialog")
                return
            }
            if round == 1 {
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "dialog"
                shot.lifetime = .keepAlways
                add(shot)
            }
            stop.tap()
            usleep(300_000)
            XCTAssertEqual(app.state, .runningForeground, "Round \(round): the app crashed after Stop Repeating")
            if app.state != .runningForeground { return }
            let undo = app.buttons["Undo"].firstMatch
            XCTAssertTrue(undo.waitForExistence(timeout: 3), "Round \(round): no Undo")
            undo.tap()
            sleep(1)
        }
    }

    /// Turns Birthday Texts on through Settings, on old and new layouts,
    /// so the Scheduled section gets its Birthdays row.
    private func turnOnBirthdays(_ app: XCUIApplication) {
        app.buttons["Settings"].firstMatch.tap()
        _ = app.navigationBars["Settings"].waitForExistence(timeout: 5)
        let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS 'Birthday Texts'")).firstMatch
        if !toggle.waitForExistence(timeout: 3) {
            // New layout: Settings has a Birthdays row ("Birthdays, Off"
            // or "Birthdays, All 11"). The list's own Birthdays row is
            // behind the sheet, so match the one that says Off.
            let off = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Birthdays' AND label CONTAINS 'Off'")).firstMatch
            if !off.exists {
                app.buttons["Done"].firstMatch.tap()
                sleep(1)
                return
            }
            off.tap()
            _ = toggle.waitForExistence(timeout: 5)
        }
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        sleep(2)
        dismissAlerts()
        let done = app.buttons["Done"].firstMatch
        if !done.exists { app.navigationBars.buttons.firstMatch.tap() }
        app.buttons["Done"].firstMatch.tap()
        sleep(2)
    }

    private func dismissAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "Allow Full Access", "OK", "Continue"] {
            let b = springboard.alerts.buttons[name].firstMatch
            if b.waitForExistence(timeout: 1) { b.tap() }
        }
    }
}
