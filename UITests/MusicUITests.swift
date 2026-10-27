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
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 20))
        capture(app, "Document-Picker")
        cancel.tap()
        // Cancel must reset the presentation so a second import can be opened.
        XCTAssertTrue(app.buttons["importMusic"].waitForExistence(timeout: 10))
        app.buttons["importMusic"].tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 20))
        cancel.tap()
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
        let mini = app.buttons["openPlayerExpanded"]
        XCTAssertTrue(mini.waitForExistence(timeout: 15))
        // The native iOS 26 accessory can report an invalid AX activation point.
        // Tap the actual element's center and still require the player to open.
        mini.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Now playing"].waitForExistence(timeout: 10))
        capture(app, "Player")
        app.buttons["Lyrics"].tap()
        XCTAssertTrue(app.buttons["Your music. Your world."].waitForExistence(timeout: 10))
        capture(app, "Synchronized-Lyrics")
        let details = app.buttons["playerDetailsMenu"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        details.tap()
        app.buttons["Edit tags"].tap()
        XCTAssertTrue(app.navigationBars["Edit tags"].waitForExistence(timeout: 10))
        capture(app, "Tag-Editor")
    }
}
