import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// View ▸ Highlight Current Line: a soft band behind the caret's line.
@MainActor
final class CurrentLineTests: XCTestCase {
    private var saved: UserDefaults!

    override func setUp() {
        saved = Preferences.defaults
        Preferences.defaults = UserDefaults(suiteName: "CurrentLineTests-\(UUID().uuidString)")!
        Preferences.registerDefaults()
    }

    override func tearDown() { Preferences.defaults = saved }

    private func editor(_ text: String, width: CGFloat = 300) -> (EditorViewController, NSWindow) {
        let controller = EditorViewController(model: EditorModel(file: TextFile(text: text)))
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: width, height: 200))
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        return (controller, window)
    }

    private func pixels(of view: NSView) -> Data {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.visibleRect)!
        view.cacheDisplay(in: view.visibleRect, to: rep)
        return rep.tiffRepresentation!
    }

    func testOnByDefaultAndToggledFromTheViewMenu() throws {
        XCTAssertTrue(Preferences.highlightsCurrentLine)
        let view = try XCTUnwrap(MainMenu.make().item(withTitle: "View")?.submenu)
        let item = try XCTUnwrap(view.item(withTitle: "Highlight Current Line"))
        let (controller, window) = editor("a\nb\n")
        defer { window.close() }
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)
        controller.toggleCurrentLine(nil)
        XCTAssertFalse(Preferences.highlightsCurrentLine)
        XCTAssertFalse(controller.textView.highlightsCurrentLine)
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)
    }

    func testBandCoversTheWholeLogicalLineAcrossTheWidth() throws {
        Preferences.wrapsLines = true
        let long = String(repeating: "word ", count: 30)
        let (controller, window) = editor("top\n" + long + "\nend")
        defer { window.close() }
        let view = controller.textView
        view.setSelectedRange(NSRange(location: 10, length: 0))
        let band = try XCTUnwrap(view.currentLineRect)
        let lm = try XCTUnwrap(view.layoutManager)
        let first = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: 4), effectiveRange: nil)
        XCTAssertEqual(band.minY, first.minY + view.textContainerOrigin.y, accuracy: 0.5)
        XCTAssertGreaterThan(band.height, first.height * 2, "every row of the wrapped line")
        XCTAssertEqual(band.minX, 0)
        XCTAssertEqual(band.width, view.bounds.width)
    }

    func testTheEmptyLastLineGetsTheBandToo() throws {
        let (controller, window) = editor("a\nb\n")
        defer { window.close() }
        let view = controller.textView
        view.setSelectedRange(NSRange(location: 4, length: 0))
        let band = try XCTUnwrap(view.currentLineRect)
        XCTAssertEqual(band.minY, view.layoutManager!.extraLineFragmentRect.minY + view.textContainerOrigin.y, accuracy: 0.5)
    }

    func testNoBandWhileTextIsSelectedOrWhenOff() {
        let (controller, window) = editor("a\nb\n")
        defer { window.close() }
        let view = controller.textView
        view.setSelectedRange(NSRange(location: 0, length: 1))
        XCTAssertNil(view.currentLineRect)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertNotNil(view.currentLineRect)
        view.highlightsCurrentLine = false
        XCTAssertNil(view.currentLineRect)
    }

    /// The colour at the right edge of the view, in the middle of `line`'s row.
    private func colorAtRowEnd(_ line: Int, of view: PlainTextView) -> NSColor? {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let lm = view.layoutManager!
        let starts = (view.string as NSString).components(separatedBy: "\n").prefix(line).map { ($0 as NSString).length + 1 }.reduce(0, +)
        let row = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: starts), effectiveRange: nil)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        return rep.colorAt(x: rep.pixelsWide - 3, y: Int((row.midY + view.textContainerOrigin.y) * scale))
    }

    func testTheBandIsDrawnBehindTheCaretLineOnly() {
        let (controller, window) = editor("one\ntwo\nthree\n")
        defer { window.close() }
        let view = controller.textView
        view.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertNotEqual(colorAtRowEnd(1, of: view), colorAtRowEnd(0, of: view), "the caret's row is tinted")
        XCTAssertEqual(colorAtRowEnd(0, of: view), colorAtRowEnd(2, of: view))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertNotEqual(colorAtRowEnd(0, of: view), colorAtRowEnd(1, of: view), "and the band moved")
        view.highlightsCurrentLine = false
        XCTAssertEqual(colorAtRowEnd(0, of: view), colorAtRowEnd(1, of: view))
    }

    func testTheViewerHighlightsTheCaretLine() throws {
        let view = LargeTextView(model: EditorModel(file: TextFile(text: "one\ntwo\nthree\n")))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.documentView = view
        view.setSelection(NSRange(location: 5, length: 0), scroll: false)
        let band = try XCTUnwrap(view.currentLineRect)
        XCTAssertEqual(band, view.lineRect(forLine: 1))
        view.setSelection(NSRange(location: 5, length: 2), scroll: false)
        XCTAssertNil(view.currentLineRect)
        view.setSelection(NSRange(location: 5, length: 0), scroll: false)
        view.highlightsCurrentLine = false
        XCTAssertNil(view.currentLineRect)
    }

    func testTheViewerFillsTheWindowWidthSoTheBandDoes() throws {
        let saved = TextDocument.largeFileThreshold
        defer { TextDocument.largeFileThreshold = saved }
        TextDocument.largeFileThreshold = 3
        let document = TextDocument()
        try document.read(from: Data("short\nlines\n".utf8), ofType: "public.plain-text")
        document.makeWindowControllers()
        defer { document.close() }
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? LargeFileViewController)
        let window = try XCTUnwrap(controller.view.window)
        window.setContentSize(NSSize(width: 500, height: 300))
        window.layoutIfNeeded()
        let clip = try XCTUnwrap(controller.textView.enclosingScrollView?.contentView)
        XCTAssertEqual(controller.textView.frame.width, clip.bounds.width, accuracy: 1)
        XCTAssertEqual(controller.textView.currentLineRect?.width ?? 0, clip.bounds.width, accuracy: 1)
    }

    func testAHugeSingleLineIsBandedOnlyAroundTheCaret() throws {
        Preferences.wrapsLines = true
        let (controller, window) = editor(String(repeating: "abcdefghij ", count: 50_000))
        defer { window.close() }
        let view = controller.textView
        view.setSelectedRange(NSRange(location: 250_000, length: 0))
        let band = try XCTUnwrap(view.currentLineRect)
        let row = view.layoutManager!.defaultLineHeight(for: Preferences.font)
        XCTAssertLessThanOrEqual(band.height, row * CGFloat(2 * PlainTextView.bandRowLimit + 1) + 1)
    }

    func testANewFontMovesTheBand() throws {
        let (controller, window) = editor("one\ntwo\nthree\n")
        defer { window.close() }
        let view = controller.textView
        view.setSelectedRange(NSRange(location: 5, length: 0))
        let before = try XCTUnwrap(view.currentLineRect)
        view.setFont(NSFont.monospacedSystemFont(ofSize: 30, weight: .regular))
        let after = try XCTUnwrap(view.currentLineRect)
        XCTAssertGreaterThan(after.height, before.height)
        XCTAssertGreaterThan(after.minY, before.minY)
    }

    func testAnEditStraightToTheStorageMovesTheBand() throws {
        let (controller, window) = editor("one\ntwo\nthree\n")
        defer { window.close() }
        let view = controller.textView
        view.setSelectedRange(NSRange(location: 9, length: 0))
        let before = try XCTUnwrap(view.currentLineRect)
        // Same length, no text view involved: "one\ntwo\n" becomes "o\ne\ntwo\n" minus a char.
        view.textStorage?.replaceCharacters(in: NSRange(location: 1, length: 1), with: "\n")
        let after = try XCTUnwrap(view.currentLineRect)
        XCTAssertGreaterThan(after.minY, before.minY, "the caret's line is now one row lower")
    }
}
