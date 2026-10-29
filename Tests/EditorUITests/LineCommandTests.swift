import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// Edit ▸ Duplicate Line (⌘D), Move Line Up / Down (⌥↑ / ⌥↓), column selection.
@MainActor
final class LineCommandTests: XCTestCase {
    private func editor(_ text: String) -> (EditorViewController, NSWindow) {
        let controller = EditorViewController(model: EditorModel(file: TextFile(text: text)))
        let window = NSWindow(contentViewController: controller)
        window.makeFirstResponder(controller.textView)
        return (controller, window)
    }

    private func menuItem(_ title: String) throws -> NSMenuItem {
        let edit = try XCTUnwrap(MainMenu.make().item(withTitle: "Edit")?.submenu)
        return try XCTUnwrap(edit.item(withTitle: title))
    }

    private func run(_ title: String, on view: PlainTextView) throws {
        let item = try menuItem(title)
        XCTAssertTrue(view.validateMenuItem(item))
        XCTAssertTrue(view.tryToPerform(try XCTUnwrap(item.action), with: item))
    }

    func testShortcuts() throws {
        XCTAssertEqual(try menuItem("Duplicate Line").keyEquivalent, "d")
        let up = try menuItem("Move Line Up")
        XCTAssertEqual(up.keyEquivalent, String(UnicodeScalar(NSUpArrowFunctionKey)!))
        XCTAssertEqual(up.keyEquivalentModifierMask, .option)
        XCTAssertEqual(try menuItem("Move Line Down").keyEquivalentModifierMask, .option)
    }

    func testDuplicateLineIsOneUndoStep() throws {
        let (controller, window) = editor("one\ntwo\n")
        let view = controller.textView
        view.setSelectedRange(NSRange(location: 1, length: 0))
        try run("Duplicate Line", on: view)
        XCTAssertEqual(view.string, "one\none\ntwo\n")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 5, length: 0))
        try XCTUnwrap(view.undoManager).undo()
        XCTAssertEqual(view.string, "one\ntwo\n")
        _ = window
    }

    func testMovingALineUpAndDownAgain() throws {
        let (controller, window) = editor("a\nb\nc\n")
        let view = controller.textView
        view.setSelectedRange(NSRange(location: 4, length: 0))
        try run("Move Line Up", on: view)
        XCTAssertEqual(view.string, "a\nc\nb\n")
        try run("Move Line Up", on: view)
        XCTAssertEqual(view.string, "c\na\nb\n")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 0))
        try run("Move Line Down", on: view)
        XCTAssertEqual(view.string, "a\nc\nb\n")
        let undo = try XCTUnwrap(view.undoManager)
        XCTAssertEqual(undo.undoActionName, "Move Line Down")
        undo.undo(); undo.undo(); undo.undo()
        XCTAssertEqual(view.string, "a\nb\nc\n")
        _ = window
    }

    func testReadOnlyViewDoesNothing() throws {
        let (controller, window) = editor("a\nb")
        controller.textView.isEditable = false
        XCTAssertFalse(controller.textView.validateMenuItem(try menuItem("Duplicate Line")))
        controller.textView.moveLineDown(nil)
        XCTAssertEqual(controller.textView.string, "a\nb")
        _ = window
    }

    func testAColumnSelectionMovesTheLinesItSpans() throws {
        let (controller, window) = editor("x\naaa\nbbb\nz\n")
        let view = controller.textView
        view.selectedRanges = [NSRange(location: 3, length: 1), NSRange(location: 7, length: 1)] as [NSValue]
        try run("Move Line Down", on: view)
        XCTAssertEqual(view.string, "x\nz\naaa\nbbb\n")
        _ = window
    }

    /// ⌥-drag makes one range per line; copying gives the column.
    func testColumnSelectionCopiesTheColumn() throws {
        let (controller, window) = editor("abc\ndef\nghi\n")
        let view = controller.textView
        view.selectedRanges = [NSRange(location: 1, length: 1), NSRange(location: 5, length: 1), NSRange(location: 9, length: 1)] as [NSValue]
        let pb = NSPasteboard(name: NSPasteboard.Name("LineCommandTests-\(UUID().uuidString)"))
        pb.clearContents()
        XCTAssertTrue(view.writeSelection(to: pb, types: view.writablePasteboardTypes), "\(view.writablePasteboardTypes)")
        XCTAssertEqual(pb.string(forType: .string), "b\ne\nh")
        _ = window
    }
}
