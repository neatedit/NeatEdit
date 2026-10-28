import AppKit
import XCTest
@testable import EditorUI

@MainActor
final class PreferencesTests: XCTestCase {
    private var saved: UserDefaults!

    override func setUp() {
        saved = Preferences.defaults
        let suite = "PreferencesTests-\(UUID().uuidString)"
        Preferences.defaults = UserDefaults(suiteName: suite)!
        Preferences.registerDefaults()
    }

    override func tearDown() {
        Preferences.defaults = saved
    }

    func testFreshDefaults() {
        XCTAssertFalse(Preferences.wrapsLines)
        XCTAssertFalse(Preferences.showsLineNumbers)
        XCTAssertEqual(Preferences.font, NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
    }

    func testChosenMonospacedFontIsUsed() {
        Preferences.fontName = "Menlo-Regular"
        XCTAssertEqual(Preferences.font.fontName, "Menlo-Regular")
        XCTAssertEqual(Preferences.font.pointSize, 13)
    }

    func testProportionalFontFallsBackToSystemMonospaced() {
        Preferences.fontName = "Helvetica"
        XCTAssertEqual(Preferences.font, NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
    }

    func testActualSizeKeepsFamily() {
        Preferences.fontName = "Menlo-Regular"
        Preferences.fontSize = 20
        let controller = EditorViewController(model: EditorModel(file: .init(text: "")))
        controller.makeTextStandardSize(nil)
        XCTAssertEqual(Preferences.font.fontName, "Menlo-Regular")
        XCTAssertEqual(Preferences.font.pointSize, 13)
    }

    func testFontPanelChoiceRejectsProportionalFonts() {
        Preferences.adoptFontPanelChoice(NSFont(name: "Menlo-Bold", size: 16)!)
        XCTAssertEqual(Preferences.font.fontName, "Menlo-Bold")
        XCTAssertEqual(Preferences.fontSize, 16)
        Preferences.adoptFontPanelChoice(NSFont(name: "Helvetica", size: 18)!)
        XCTAssertEqual(Preferences.font.fontName, "Menlo-Bold")
        XCTAssertEqual(Preferences.fontSize, 16)
    }

    func testToggleLineNumbers() {
        let controller = EditorViewController(model: EditorModel(file: .init(text: "")))
        controller.toggleLineNumbers(nil)
        XCTAssertTrue(Preferences.showsLineNumbers)
    }
}
