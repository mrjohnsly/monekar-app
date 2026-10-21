import XCTest

@MainActor
final class LaunchNavigationTests: XCTestCase {
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
