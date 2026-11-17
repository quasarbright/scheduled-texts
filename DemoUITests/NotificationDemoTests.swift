import XCTest

/// Drives a "Send text to …?" notification the way a person would, for
/// recording demos and checking the notification buttons. The text has to be
/// scheduled already; this waits for its banner.
///
/// Environment (pass with a TEST_RUNNER_ prefix to xcodebuild):
///   DEMO_ACTION: tap (default), send or cancel
///   DEMO_TITLE:  text the banner contains, default "Send text to"
final class NotificationDemoTests: XCTestCase {
    func testNotification() throws {
        let env = ProcessInfo.processInfo.environment
        let action = env["DEMO_ACTION"] ?? "tap"
        let title = env["DEMO_TITLE"] ?? "Send text to"
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)

        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", title))
            .firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 180), "No banner containing \(title)")
        sleep(2)

        switch action {
        case "tap":
            banner.tap()
        default:
            banner.press(forDuration: 1.2)
            let name = action == "send" ? "Send" : "Cancel Text"
            let button = springboard.buttons[name]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "No \(name) button")
            sleep(2)
            button.tap()
            if action == "cancel" {
                // Nothing opens. Show the list afterwards so the text is visibly gone.
                sleep(3)
                springboard.icons["Scheduled Texts"].tap()
            }
        }
        sleep(5)
    }
}
