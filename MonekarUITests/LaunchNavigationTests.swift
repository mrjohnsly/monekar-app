import XCTest

@MainActor
final class LaunchNavigationTests: XCTestCase {
    func testModelSelectionPushesAndNativeBackReturnsToTheGrid() {
        let app = XCUIApplication()
        app.launchArguments.append("--test-model-navigation")
        app.launch()

        let model = app.buttons["person-7"]
        XCTAssertTrue(model.waitForExistence(timeout: 10))
        model.tap()
        XCTAssertTrue(app.segmentedControls["personSection"].waitForExistence(timeout: 5))

        goBackFromPerson(in: app)
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls["personSection"].exists)

        model.tap()
        XCTAssertTrue(app.segmentedControls["personSection"].waitForExistence(timeout: 5))
        openTab("Settings", in: app)
        openTab("Models", in: app)
        XCTAssertTrue(app.segmentedControls["personSection"].waitForExistence(timeout: 5))

        goBackFromPerson(in: app)
        XCTAssertTrue(model.waitForExistence(timeout: 5))
    }

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

    func testSettingsNavigationCanReturnUsingTheBackButton() {
        let app = XCUIApplication()
        app.launch()
        openTab("Settings", in: app)

        app.buttons["showConnection"].tap()
        XCTAssertTrue(app.buttons["closeConnection"].waitForExistence(timeout: 5))
        app.navigationBars["Connection"].buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["showConnection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["showLibraryScan"].exists)
        XCTAssertFalse(app.buttons["closeConnection"].exists)
    }

    private func openTab(_ title: String, in app: XCUIApplication) {
        let tab = app.buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func goBackFromPerson(in app: XCUIApplication) {
        #if os(macOS)
        let back = app.buttons["Back"].firstMatch
        #else
        let back = app.navigationBars["Person"].buttons.element(boundBy: 0)
        #endif
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
    }
}
