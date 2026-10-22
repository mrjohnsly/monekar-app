import XCTest

@MainActor
final class LaunchNavigationTests: XCTestCase {
    func testLibraryScanIsReachable() {
        let app = XCUIApplication()
        app.launch()
        openTab("Settings", in: app)

        let scan = app.buttons["showLibraryScan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 10))
        scan.tap()

        XCTAssertTrue(app.buttons["Refresh Status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rescanLibrary"].exists)
    }

    func testLaunchAndReturnFromConnection() {
        let app = XCUIApplication()
        app.launch()
        openTab("Settings", in: app)

        let connection = app.buttons["showConnection"]
        XCTAssertTrue(connection.waitForExistence(timeout: 10))
        connection.tap()

        let done = app.buttons["closeConnection"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        XCTAssertTrue(connection.waitForExistence(timeout: 5))
        XCTAssertFalse(done.exists)
    }

    func testTabNavigationKeepsSettingsHistorySeparate() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.otherElements["homeScreen"].waitForExistence(timeout: 10))
        openTab("Settings", in: app)
        app.buttons["showConnection"].tap()
        XCTAssertTrue(app.buttons["closeConnection"].waitForExistence(timeout: 5))

        openTab("Models", in: app)
        XCTAssertTrue(app.otherElements["homeScreen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["closeConnection"].exists)

        openTab("Favourites", in: app)
        XCTAssertTrue(app.navigationBars["Favourites"].waitForExistence(timeout: 5))
        openTab("Tags", in: app)
        XCTAssertTrue(app.navigationBars["Tags"].waitForExistence(timeout: 5))

        openTab("Settings", in: app)
        XCTAssertTrue(app.buttons["closeConnection"].waitForExistence(timeout: 5))
    }

    private func openTab(_ title: String, in app: XCUIApplication) {
        let tab = app.buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }
}
