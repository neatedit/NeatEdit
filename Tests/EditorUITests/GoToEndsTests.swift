import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// Edit ▸ Go to Beginning / Go to End, in the editor and in the viewer.
@MainActor
final class GoToEndsTests: XCTestCase {
    private var savedThreshold = 0

    override func setUp() {
        savedThreshold = TextDocument.largeFileThreshold
    }

    override func tearDown() {
        TextDocument.largeFileThreshold = savedThreshold
    }

    private func menuItem(_ title: String) throws -> NSMenuItem {
        let edit = try XCTUnwrap(MainMenu.make().item(withTitle: "Edit")?.submenu)
        return try XCTUnwrap(edit.item(withTitle: title))
    }

    private var log: String { (1...500).map { "line \($0)\n" }.joined() }

    func testMenuItemsUseCommandArrows() throws {
        let beginning = try menuItem("Go to Beginning")
        let end = try menuItem("Go to End")
        XCTAssertEqual(beginning.keyEquivalent, String(UnicodeScalar(NSUpArrowFunctionKey)!))
        XCTAssertEqual(end.keyEquivalent, String(UnicodeScalar(NSDownArrowFunctionKey)!))
        XCTAssertEqual(beginning.keyEquivalentModifierMask, .command)
        XCTAssertEqual(end.keyEquivalentModifierMask, .command)
    }

    func testEditorGoesToBothEnds() throws {
        let controller = EditorViewController(model: EditorModel(file: TextFile(text: log)))
        let window = NSWindow(contentViewController: controller)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(controller.textView)
        let length = (controller.textView.string as NSString).length

        controller.textView.perform(try XCTUnwrap(menuItem("Go to End").action), with: nil)
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: length, length: 0))
        controller.textView.perform(try XCTUnwrap(menuItem("Go to Beginning").action), with: nil)
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 0, length: 0))
        window.close()
    }

    func testViewerGoToEndScrollsToTheBottomAndFollowsTheTail() throws {
        TextDocument.largeFileThreshold = 10
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).log")
        try Data(log.utf8).write(to: url)
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? LargeFileViewController)
        let window = try XCTUnwrap(controller.view.window)
        window.setContentSize(NSSize(width: 400, height: 300))
        window.layoutIfNeeded()
        window.makeFirstResponder(controller.textView)
        let clip = try XCTUnwrap(controller.textView.enclosingScrollView?.contentView)

        let end = try menuItem("Go to End")
        XCTAssertTrue(controller.textView.validateMenuItem(end))
        controller.textView.perform(try XCTUnwrap(end.action), with: nil)
        XCTAssertEqual(controller.textView.selection, NSRange(location: controller.model.storage.length, length: 0))
        XCTAssertEqual(clip.bounds.maxY, controller.textView.bounds.height, accuracy: 1)

        // From there new lines keep the view at the bottom.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((501...600).map { "line \($0)\n" }.joined().utf8))
        try handle.close()
        let deadline = Date().addingTimeInterval(3)
        while controller.model.lineIndex.lineCount < 601, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(clip.bounds.maxY, controller.textView.bounds.height, accuracy: 1)

        controller.textView.perform(try XCTUnwrap(menuItem("Go to Beginning").action), with: nil)
        XCTAssertEqual(controller.textView.selection, NSRange(location: 0, length: 0))
        XCTAssertEqual(clip.bounds.minY, 0, accuracy: 1)
        document.close()
    }
}
