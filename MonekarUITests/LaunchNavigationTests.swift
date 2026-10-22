import XCTest

@MainActor
final class LaunchNavigationTests: XCTestCase {
    func testLibraryScanIsReachable() {
        let app = XCUIApplication()
        app.launch()

        let scan = app.buttons["showLibraryScan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 10))
        scan.tap()

        XCTAssertTrue(app.buttons["Refresh Status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rescanLibrary"].exists)
    }

    func testLaunchAndReturnFromConnection() {
        let app = XCUIApplication()
        app.launch()

        let connection = app.buttons["showConnection"]
        XCTAssertTrue(connection.waitForExistence(timeout: 10))
        connection.tap()

        let done = app.buttons["closeConnection"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        XCTAssertTrue(connection.waitForExistence(timeout: 5))
        XCTAssertFalse(done.exists)
    }
}
