import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// View ▸ Show Invisibles marks spaces, tabs and line ends.
@MainActor
final class ShowInvisiblesTests: XCTestCase {
    private var saved: UserDefaults!
    private var savedThreshold = 0

    override func setUp() {
        saved = Preferences.defaults
        Preferences.defaults = UserDefaults(suiteName: "ShowInvisiblesTests-\(UUID().uuidString)")!
        Preferences.registerDefaults()
        savedThreshold = TextDocument.largeFileThreshold
    }

    override func tearDown() {
        Preferences.defaults = saved
        TextDocument.largeFileThreshold = savedThreshold
    }

    private func pixels(of view: NSView) -> Data {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.visibleRect)!
        view.cacheDisplay(in: view.visibleRect, to: rep)
        return rep.tiffRepresentation!
    }

    private let text = "a\tb c\u{00A0}d\nnext line\n"

    func testMenuItemTogglesThePreference() throws {
        let view = try XCTUnwrap(MainMenu.make().item(withTitle: "View")?.submenu)
        let item = try XCTUnwrap(view.item(withTitle: "Show Invisibles"))
        XCTAssertEqual(item.keyEquivalent, "i")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .option])

        let controller = EditorViewController(model: EditorModel(file: TextFile(text: text)))
        let window = NSWindow(contentViewController: controller)
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)
        controller.toggleInvisibles(nil)
        XCTAssertTrue(Preferences.showsInvisibles)
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)
        _ = window
    }

    func testEditorDrawsMarksOnlyWhenOn() throws {
        let controller = EditorViewController(model: EditorModel(file: TextFile(text: text)))
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 300, height: 200))
        window.layoutIfNeeded()
        let before = pixels(of: controller.textView)
        Preferences.showsInvisibles = true
        let after = pixels(of: controller.textView)
        XCTAssertNotEqual(before, after)
        Preferences.showsInvisibles = false
        XCTAssertEqual(pixels(of: controller.textView), before)
        _ = window
    }

    func testViewerDrawsMarksOnlyWhenOn() throws {
        TextDocument.largeFileThreshold = 10
        let document = TextDocument()
        try document.read(from: Data(text.utf8), ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? LargeFileViewController)
        let window = try XCTUnwrap(controller.view.window)
        window.setContentSize(NSSize(width: 300, height: 200))
        window.layoutIfNeeded()
        let item = try XCTUnwrap(MainMenu.make().item(withTitle: "View")?.submenu?.item(withTitle: "Show Invisibles"))
        XCTAssertTrue(controller.validateMenuItem(item))

        let before = pixels(of: controller.textView)
        controller.toggleInvisibles(nil)
        XCTAssertNotEqual(pixels(of: controller.textView), before)
        controller.toggleInvisibles(nil)
        XCTAssertEqual(pixels(of: controller.textView), before)
        document.close()
    }
}
