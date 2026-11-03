import AppKit
import XCTest
@testable import EditorUI

/// View → Appearance: the app follows the system unless told to stay light or dark.
@MainActor
final class AppearanceTests: XCTestCase {
    private var saved: UserDefaults!
    private var savedAppearance: NSAppearance?

    override func setUp() {
        saved = Preferences.defaults
        Preferences.defaults = UserDefaults(suiteName: "AppearanceTests-\(UUID().uuidString)")!
        Preferences.registerDefaults()
        savedAppearance = NSApplication.shared.appearance
    }

    override func tearDown() {
        Preferences.defaults = saved
        NSApp.appearance = savedAppearance
    }

    private func menuItems() throws -> [NSMenuItem] {
        let view = try XCTUnwrap(MainMenu.make().item(withTitle: "View")?.submenu)
        return try XCTUnwrap(view.item(withTitle: "Appearance")?.submenu).items
    }

    func testFollowsTheSystemByDefault() {
        XCTAssertEqual(Preferences.appearance, .system)
        XCTAssertNil(Preferences.Appearance.system.nsAppearance)
    }

    func testUnknownStoredValueFallsBackToSystem() {
        Preferences.defaults.set("sepia", forKey: "appearance")
        XCTAssertEqual(Preferences.appearance, .system)
    }

    func testLightAndDarkMapToAquaAppearances() {
        XCTAssertEqual(Preferences.Appearance.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(Preferences.Appearance.dark.nsAppearance?.name, .darkAqua)
    }

    func testMenuOffersEveryChoiceAndChecksTheCurrentOne() throws {
        let items = try menuItems()
        XCTAssertEqual(items.map(\.title), ["Same as System", "Light", "Dark"])
        let delegate = AppDelegate()
        XCTAssertEqual(items.map { delegate.validateMenuItem($0) ? $0.state : .mixed }, [.on, .off, .off])
    }

    func testChoosingLightKeepsItAndAppliesItToTheApp() throws {
        let delegate = AppDelegate()
        let light = try XCTUnwrap(try menuItems().first { $0.title == "Light" })
        delegate.chooseAppearance(light)
        XCTAssertEqual(Preferences.appearance, .light)
        XCTAssertEqual(NSApp.appearance?.name, .aqua)

        let system = try XCTUnwrap(try menuItems().first { $0.title == "Same as System" })
        delegate.chooseAppearance(system)
        XCTAssertEqual(Preferences.appearance, .system)
        XCTAssertNil(NSApp.appearance)
    }
}
