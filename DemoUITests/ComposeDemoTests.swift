import XCTest

/// Screenshots of the compose button in the bottom toolbar, the empty list,
/// and the Undo toast after Don't Send. Run on a fresh install with Contacts
/// granted (see RepeatDemoTests). Export with `xcrun xcresulttool export attachments`.
final class ComposeDemoTests: XCTestCase {
    func testComposeButtonAndUndo() throws {
        let app = XCUIApplication()
        app.launch()
        dismissAlerts()
        sleep(1)
        shot("14-empty")

        compose(app, to: "5551234567", body: "Happy birthday! Hope it's a great one")
        compose(app, to: "5559876543", body: "Don't forget the dentist at 3")
        sleep(1)

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'dentist'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Don't Send"].firstMatch.tap()
        sleep(1)
        shot("8-undo-above-toolbar")

        // Undo it so the list has two texts to search, and let the toast go.
        app.buttons["Undo"].firstMatch.tap()
        sleep(2)
        compose(app, to: "5554443333", body: "Pick up the cake on the way home")
        sleep(1)
        shot("12-bottom-search")

        // On iOS 26 the bottom search pill is a button until it's tapped.
        let pill = app.searchFields.firstMatch.exists
            ? app.searchFields.firstMatch
            : app.buttons["Search"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        pill.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("cake")
        sleep(1)
        shot("13-bottom-search-typing")

        search.typeText("zzz")
        sleep(1)
        shot("11-search-no-results")
    }

    private func compose(_ app: XCUIApplication, to recipient: String, body text: String) {
        let compose = app.toolbars.buttons["New Text"].firstMatch
        XCTAssertTrue(compose.waitForExistence(timeout: 5))
        compose.tap()
        dismissAlerts()
        let to = app.textFields["Name, number or email"]
        XCTAssertTrue(to.waitForExistence(timeout: 5))
        to.tap()
        to.typeText("\(recipient)\n")
        let body = app.textFields["What do you want to say?"]
        body.tap()
        body.typeText(text)
        app.buttons["Save"].tap()
        sleep(2)
        dismissAlerts()
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
