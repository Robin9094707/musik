import XCTest

final class MusicUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func launch(_ language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-appLanguage", language, "-theme", "dark"]
        app.launch(); return app
    }
    func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testLibraryAndDocumentPickerOpen() {
        let app = launch()
        XCTAssertTrue(app.buttons["importMusic"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Afterglow"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "Library-English")
        app.buttons["importMusic"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        capture(app, "Document-Picker")
        // Dismiss the native picker, then verify settings and all four icon options.
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 5) { cancel.tap() }
    }
    func testGermanSettingsAndIconChoices() {
        let app = launch("de")
        app.tabBars.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.staticTexts["Simplex Music Player"].waitForExistence(timeout: 10))
        for name in ["Aurora", "Ember", "Glacier", "Obsidian"] { XCTAssertTrue(app.buttons[name].exists) }
        capture(app, "Settings-German")
    }
    func testPlaybackPlayerLyricsAndTagEditor() {
        let app = launch()
        let title = app.staticTexts["Afterglow"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15)); title.tap()
        let minis = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Now playing: "))
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in minis.allElementsBoundByIndex.contains { $0.isHittable } }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed)
        guard let mini = minis.allElementsBoundByIndex.first(where: { $0.isHittable }) else { XCTFail("Mini-player must be visible and tappable"); return }
        mini.tap()
        XCTAssertTrue(app.navigationBars["Now playing"].waitForExistence(timeout: 10))
        capture(app, "Player")
        app.buttons["Lyrics"].tap()
        XCTAssertTrue(app.buttons["Your music. Your world."].waitForExistence(timeout: 10))
        capture(app, "Synchronized-Lyrics")
        app.buttons["Details"].tap()
        app.buttons["Edit tags"].tap()
        XCTAssertTrue(app.navigationBars["Edit tags"].waitForExistence(timeout: 10))
        capture(app, "Tag-Editor")
    }
}
