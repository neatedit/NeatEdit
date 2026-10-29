import AppKit
import XCTest
import EditorCore
@testable import EditorUI

@MainActor
final class LargeTextViewTests: XCTestCase {
    private func makeView(_ text: String) -> LargeTextView {
        let view = LargeTextView(model: EditorModel(file: TextFile(text: text)))
        view.frame = NSRect(origin: .zero, size: view.documentSize)
        return view
    }

    /// Point in the middle of the given line, `column` characters in.
    private func point(_ view: LargeTextView, line: Int, column: Int) -> NSPoint {
        let layout = view.layout
        return NSPoint(
            x: layout.inset.width + (CGFloat(column) + 0.2) * layout.charWidth,
            y: layout.lineRect(line, width: 0).midY
        )
    }

    func testDocumentSizeFollowsLinesAndLongestLine() {
        let view = makeView("ab\nabcdef\nx")
        let expected = view.layout.documentSize(lineCount: 3, longestLine: 7)  // longest line incl. its break
        XCTAssertEqual(view.documentSize, expected)
    }

    func testClickPlacesCaret() {
        let view = makeView("hello\nworld")
        view.select(at: point(view, line: 1, column: 2), granularity: .character, extending: false)
        XCTAssertEqual(view.selection, NSRange(location: 8, length: 0))
    }

    func testClickPastLineEndGoesToLineEnd() {
        let view = makeView("hi\nworld")
        view.select(at: point(view, line: 0, column: 40), granularity: .character, extending: false)
        XCTAssertEqual(view.selection, NSRange(location: 2, length: 0))
    }

    func testShiftClickAndDragExtendFromAnchor() {
        let view = makeView("hello\nworld")
        view.select(at: point(view, line: 0, column: 1), granularity: .character, extending: false)
        view.select(at: point(view, line: 1, column: 3), granularity: .character, extending: true)
        XCTAssertEqual(view.selection, NSRange(location: 1, length: 8))
        // dragging back above the anchor flips the range
        view.select(at: point(view, line: 0, column: 0), granularity: .character, extending: true)
        XCTAssertEqual(view.selection, NSRange(location: 0, length: 1))
    }

    func testDoubleAndTripleClick() {
        let view = makeView("foo bar\nbaz")
        view.select(at: point(view, line: 0, column: 5), granularity: .word, extending: false)
        XCTAssertEqual(view.selection, NSRange(location: 4, length: 3))
        view.select(at: point(view, line: 0, column: 1), granularity: .line, extending: false)
        XCTAssertEqual(view.selection, NSRange(location: 0, length: 8))
    }

    func testKeyboardMovement() {
        let view = makeView("hello\nhi\nworld")
        view.setSelection(NSRange(location: 3, length: 0))
        view.moveDown(nil)
        XCTAssertEqual(view.selection.location, 8)
        view.moveDown(nil)
        XCTAssertEqual(view.selection.location, 12, "keeps the column from before the short line")
        view.moveRightAndModifySelection(nil)
        XCTAssertEqual(view.selection, NSRange(location: 12, length: 1))
        view.moveToEndOfDocument(nil)
        XCTAssertEqual(view.selection, NSRange(location: 14, length: 0))
        view.moveToBeginningOfDocumentAndModifySelection(nil)
        XCTAssertEqual(view.selection, NSRange(location: 0, length: 14))
        view.moveLeft(nil)
        XCTAssertEqual(view.selection, NSRange(location: 0, length: 0), "left collapses to selection start")
    }

    func testCopyWritesPlainSelectedText() {
        let view = makeView("hello\nworld")
        view.setSelection(NSRange(location: 3, length: 5))
        let pb = NSPasteboard(name: NSPasteboard.Name("SimpleTextEditTests-\(UUID().uuidString)"))
        view.writeSelection(to: pb)
        XCTAssertEqual(pb.string(forType: .string), "lo\nwo")
    }

    func testSelectAll() {
        let view = makeView("abc")
        view.selectAll(nil)
        XCTAssertEqual(view.selection, NSRange(location: 0, length: 3))
    }

    func testSelectionChangesNotify() {
        let view = makeView("abc")
        var calls = 0
        view.onSelectionChange = { calls += 1 }
        view.moveRight(nil)
        XCTAssertEqual(calls, 1)
    }

    func testIsReadOnly() {
        let view = makeView("abc")
        view.setSelection(NSRange(location: 1, length: 0))
        view.insertText("x")
        view.deleteBackward(nil)
        XCTAssertEqual(view.model.storage.string, "abc")
        XCTAssertFalse(view.isEditable)
    }

    func testScrollRangeToVisibleReachesTheEnd() {
        let view = makeView((0..<1000).map { "line \($0)" }.joined(separator: "\n"))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        scroll.documentView = view
        view.scrollRangeToVisible(NSRange(location: (view.model.storage.string as NSString).length - 1, length: 1))
        XCTAssertGreaterThan(view.visibleRect.minY, 1000)
    }
}
