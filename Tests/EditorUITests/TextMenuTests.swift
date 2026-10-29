import AppKit
import XCTest
import EditorCore
@testable import EditorUI

@MainActor
final class TextMenuTests: XCTestCase {
    private func editor(_ text: String) -> (EditorViewController, NSWindow) {
        let controller = EditorViewController(model: EditorModel(file: TextFile(text: text)))
        let window = NSWindow(contentViewController: controller)
        window.makeFirstResponder(controller.textView)
        return (controller, window)
    }

    private func range(of part: String, in controller: EditorViewController) -> NSRange {
        (controller.textView.string as NSString).range(of: part)
    }

    func testWithoutSelectionTransformsTheWholeDocumentAsOneUndoStep() throws {
        let (controller, window) = editor("b\na\nc\n")
        controller.apply(.sortLines)
        XCTAssertEqual(controller.textView.string, "a\nb\nc\n")
        let undo = try XCTUnwrap(controller.textView.undoManager)
        XCTAssertEqual(undo.undoActionName, "Sort Lines")
        undo.undo()
        XCTAssertEqual(controller.textView.string, "b\na\nc\n")
        _ = window
    }

    func testSelectionIsTransformedAndStaysSelected() {
        let (controller, window) = editor("keep hello keep")
        controller.textView.setSelectedRange(range(of: "hello", in: controller))
        controller.apply(.uppercase)
        XCTAssertEqual(controller.textView.string, "keep HELLO keep")
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 5, length: 5))
        _ = window
    }

    func testLineTransformsExtendAPartialSelectionToWholeLines() {
        let (controller, window) = editor("top\nzeta\nalpha\nbottom")
        // From the middle of "zeta" to the middle of "alpha".
        controller.textView.setSelectedRange(NSRange(location: 6, length: 6))
        controller.apply(.sortLines)
        XCTAssertEqual(controller.textView.string, "top\nalpha\nzeta\nbottom")
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 4, length: 10))
        _ = window
    }

    func testSelectionEndingAtALineStartDoesNotTakeTheNextLine() {
        let (controller, window) = editor("b\na\nz")
        controller.textView.setSelectedRange(NSRange(location: 0, length: 4))  // "b\na\n"
        controller.apply(.sortLines)
        XCTAssertEqual(controller.textView.string, "a\nb\nz")
        _ = window
    }

    func testWholeLinesLeavesOutAFinalCRLF() {
        let text = "b\r\na\r\nz" as NSString
        XCTAssertEqual(EditorViewController.wholeLines(NSRange(location: 1, length: 4), in: text), NSRange(location: 0, length: 4))
    }

    func testFailureLeavesTextAloneAndSaysWhy() {
        let (controller, window) = editor("{oops}")
        controller.apply(.formatJSON)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(controller.textView.string, "{oops}")
        XCTAssertTrue(controller.leftStatus.stringValue.hasPrefix("Not valid JSON"), controller.leftStatus.stringValue)
        _ = window
    }

    func testMenuHasEveryTransformAndRoutesItByTag() throws {
        let menu = try XCTUnwrap(MainMenu.make().item(withTitle: "Text")?.submenu)
        let items = menu.items.filter { $0.action == #selector(EditorViewController.transformText(_:)) }
        XCTAssertEqual(Set(items.map(\.title)), Set(TextTransform.allCases.map(\.title)))

        let (controller, window) = editor("abc")
        let item = try XCTUnwrap(items.first { $0.title == "UPPERCASE" })
        controller.transformText(item)
        XCTAssertEqual(controller.textView.string, "ABC")
        _ = window
    }

    func testDisabledWhenReadOnly() throws {
        let (controller, window) = editor("abc")
        let item = NSMenuItem(title: "x", action: #selector(EditorViewController.transformText(_:)), keyEquivalent: "")
        XCTAssertTrue(controller.validateMenuItem(item))
        controller.textView.isEditable = false
        XCTAssertFalse(controller.validateMenuItem(item))
        _ = window
    }
}
