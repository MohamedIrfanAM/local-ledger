import XCTest

final class LocalLedgerUITests: XCTestCase {
    @MainActor func testDemoNavigationAndPrivacy() throws {
        let app = XCUIApplication()
        app.launch()
        let demo = app.buttons["Take a look around"]
        if demo.waitForExistence(timeout: 5) { if !demo.isHittable { app.swipeUp() }; demo.tap() }
        XCTAssertTrue(app.tabBars.buttons["Overview"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Budgets"].tap()
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Categories & tags"].waitForExistence(timeout: 5))
        app.staticTexts["Categories & tags"].tap()
        XCTAssertTrue(app.staticTexts["Food"].waitForExistence(timeout: 5))
    }
}
