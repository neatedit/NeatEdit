import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// Line numbers in the large file viewer and in the Edit Lines sheet.
@MainActor
final class ViewerLineNumbersTests: XCTestCase {
    private var saved: UserDefaults!
    private var savedThreshold = 0

    override func setUp() {
        saved = Preferences.defaults
        Preferences.defaults = UserDefaults(suiteName: "ViewerLineNumbersTests-\(UUID().uuidString)")!
        Preferences.registerDefaults()
        savedThreshold = TextDocument.largeFileThreshold
        TextDocument.largeFileThreshold = 10
    }

    override func tearDown() {
        Preferences.defaults = saved
        TextDocument.largeFileThreshold = savedThreshold
    }

    private func openViewer(_ text: String) throws -> (TextDocument, LargeFileViewController) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).log")
        try Data(text.utf8).write(to: url)
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? LargeFileViewController)
        controller.view.window?.setContentSize(NSSize(width: 500, height: 300))
        controller.view.window?.layoutIfNeeded()
        return (document, controller)
    }

    private var log: String { (1...1000).map { "line \($0)\n" }.joined() }

    func testTheViewerNumbersItsLinesByDefaultAndTextStartsAfterTheGutter() throws {
        let (document, controller) = try openViewer(log)
        defer { document.close() }
        let view = controller.textView
        XCTAssertEqual(view.visibleLineNumbers().first?.line, 1)
        XCTAssertEqual(view.visibleLineNumbers().first?.y, view.lineRect(forLine: 0).minY)
        XCTAssertGreaterThan(view.gutterWidth, 0)
        XCTAssertEqual(view.layout.inset.width, view.gutterWidth + 4)
        XCTAssertEqual(view.enclosingScrollView?.contentView.bounds.minX, 0)
    }

    func testTheNumbersFollowTheScroll() throws {
        let (document, controller) = try openViewer(log)
        defer { document.close() }
        let view = controller.textView
        view.scroll(NSPoint(x: 0, y: view.lineRect(forLine: 500).minY))
        let numbers = view.visibleLineNumbers()
        XCTAssertEqual(numbers.first?.y, view.lineRect(forLine: numbers[0].line - 1).minY)
        XCTAssertTrue((499...501).contains(try XCTUnwrap(numbers.first?.line)))
        XCTAssertLessThan(numbers.count, 40, "only what's on screen")
    }

    func testTheViewMenuTurnsThemOffOnlyInTheViewer() throws {
        let (document, controller) = try openViewer(log)
        defer { document.close() }
        let view = try XCTUnwrap(MainMenu.make().item(withTitle: "View")?.submenu)
        let item = try XCTUnwrap(view.item(withTitle: "Show Line Numbers"))
        XCTAssertFalse(Preferences.showsLineNumbers, "the editor's setting is its own")
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)

        controller.toggleLineNumbers(nil)
        XCTAssertEqual(controller.textView.gutterWidth, 0)
        XCTAssertEqual(controller.textView.layout.inset.width, 4)
        XCTAssertTrue(controller.textView.visibleLineNumbers().isEmpty)
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)
        XCTAssertFalse(Preferences.showsLineNumbers)
    }

    func testTheGutterWidensAsTheFileGrows() throws {
        let (document, controller) = try openViewer("line one\nline two\n")
        defer { document.close() }
        let view = controller.textView
        let before = view.gutterWidth
        let oldLength = controller.model.storage.length
        controller.model.append(String(repeating: "x\n", count: 5000))
        controller.textDidGrow(from: oldLength, follow: false)
        XCTAssertGreaterThan(view.gutterWidth, before)
        XCTAssertEqual(view.layout.inset.width, view.gutterWidth + 4)
    }

    func testAClickRightAfterTheGutterIsTheStartOfTheLine() throws {
        let (document, controller) = try openViewer(log)
        defer { document.close() }
        let view = controller.textView
        let row = view.lineRect(forLine: 2)
        XCTAssertEqual(view.offset(at: NSPoint(x: view.gutterWidth + 4, y: row.midY)),
                       view.model.lineIndex.starts[2])
    }

    func testAMatchFarToTheRightStaysClearOfTheGutter() throws {
        let long = String(repeating: "x", count: 2000) + "END\n" + log
        let (document, controller) = try openViewer(long)
        defer { document.close() }
        let view = controller.textView
        view.setSelection(NSRange(location: 2000, length: 0))
        let caretX = view.layout.inset.width + 2000 * view.layout.charWidth
        XCTAssertGreaterThanOrEqual(caretX, view.visibleRect.minX + view.gutterWidth)
        XCTAssertLessThan(caretX, view.visibleRect.maxX)
        view.setSelection(NSRange(location: 0, length: 0))
        XCTAssertGreaterThanOrEqual(view.layout.inset.width, view.visibleRect.minX + view.gutterWidth, "back at the start")
    }

    func testAClickOnTheGutterLandsOnTheFirstVisibleColumn() throws {
        let long = String(repeating: "x", count: 2000) + "\n" + log
        let (document, controller) = try openViewer(long)
        defer { document.close() }
        let view = controller.textView
        view.setSelection(NSRange(location: 2000, length: 0))
        let left = view.visibleRect.minX
        XCTAssertGreaterThan(left, 0, "scrolled sideways")
        let row = view.lineRect(forLine: 0)
        XCTAssertEqual(view.offset(at: NSPoint(x: left + 2, y: row.midY)),
                       view.offset(at: NSPoint(x: left + view.gutterWidth, y: row.midY)))
    }

    func testTheGutterIsOnlyCountedOnceInTheDocumentWidth() throws {
        let (document, controller) = try openViewer(log)
        defer { document.close() }
        let view = controller.textView
        let numbered = view.documentSize.width
        let gutter = view.gutterWidth
        view.showsLineNumbers = false
        XCTAssertEqual(numbered - view.documentSize.width, gutter, accuracy: 0.5)
    }

    func testTheSheetsNumbersFollowALineBreakOfTheSameLength() throws {
        let (document, controller) = try openViewer(log)
        defer { document.close() }
        controller.editLines(nil)
        let editor = try XCTUnwrap(controller.presentedViewControllers?.first as? LineEditorController)
        defer { editor.cancel(nil) }
        editor.view.window?.layoutIfNeeded()
        let ruler = try XCTUnwrap(editor.lineNumberRuler)
        let before = ruler.visibleNumbers().map(\.line)
        editor.textView.textStorage?.replaceCharacters(in: NSRange(location: 2, length: 1), with: "\n")
        XCTAssertEqual(ruler.visibleNumbers().map(\.line).count, before.count + 1)
    }

    func testTheSheetNumbersLinesAsInTheFile() throws {
        let (document, controller) = try openViewer(log)
        defer { document.close() }
        let offset = (controller.model.storage.string as NSString).range(of: "line 50\n").location
        controller.textView.setSelection(NSRange(location: offset, length: 0))
        controller.editLines(nil)
        let editor = try XCTUnwrap(controller.presentedViewControllers?.first as? LineEditorController)
        defer { editor.cancel(nil) }
        editor.view.window?.layoutIfNeeded()
        let ruler = try XCTUnwrap(editor.lineNumberRuler)
        XCTAssertEqual(ruler.visibleNumbers().first?.line, 40)
        XCTAssertTrue(editor.textView.enclosingScrollView?.rulersVisible ?? false)

        // A line added at the top pushes the numbers below it down.
        editor.textView.string = "new\n" + editor.textView.string
        let numbers = ruler.visibleNumbers().map(\.line)
        XCTAssertEqual(numbers.first, 40)
        XCTAssertEqual(numbers.dropFirst().first, 41)
        XCTAssertEqual(ruler.visibleNumbers().count, numbers.count)
    }

    func testTheSheetsGutterFitsTheFilesBigNumbers() {
        let text = String(repeating: "x\n", count: 20_000) as NSString
        let index = LineIndex(text)
        let chunkAt = { (offset: Int) in
            LineSplice.chunk(around: NSRange(location: offset, length: 0), context: 0, in: text, lineIndex: index)
        }
        let small = LineEditorController(chunk: chunkAt(0))
        let big = LineEditorController(chunk: chunkAt(39_990))
        _ = small.view
        _ = big.view
        XCTAssertGreaterThan(big.lineNumberRuler!.ruleThickness, small.lineNumberRuler!.ruleThickness)
    }
}
