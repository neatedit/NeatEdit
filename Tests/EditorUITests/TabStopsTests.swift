import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// Tabs must never break a line on their own: AppKit's default paragraph
/// style stops after 12 tab stops (~336pt) and wraps any tab past them.
@MainActor
final class TabStopsTests: XCTestCase {
    private func lineFragments(in view: PlainTextView) -> Int {
        let manager = view.layoutManager!
        manager.ensureLayout(for: view.textContainer!)
        var count = 0
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, _, _ in count += 1 }
        return count
    }

    func testTabSeparatedRowFitsOnOneLineInWideView() {
        let row = "10.0.0.0 – 10.0.0.255\tSample Widgets Trading Company\t/ 24\t01.02.2020\t1000"
        let view = PlainTextView.make(text: row)
        view.frame = NSRect(x: 0, y: 0, width: 2000, height: 400)

        XCTAssertEqual(lineFragments(in: view), 1)
    }

    func testTypedTabsUseFourColumnStops() {
        let view = PlainTextView.make(text: "")
        view.frame = NSRect(x: 0, y: 0, width: 2000, height: 400)
        view.insertText("\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\tx", replacementRange: view.selectedRange())

        XCTAssertEqual(lineFragments(in: view), 1)
        let style = view.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let space = ("    " as NSString).size(withAttributes: [.font: view.font!]).width
        XCTAssertEqual(style?.defaultTabInterval ?? 0, space, accuracy: 0.01)
        XCTAssertEqual(style?.tabStops.count, 0)
    }

    func testChangingFontKeepsTabInterval() {
        let view = PlainTextView.make(text: "a\tb")
        let big = NSFont.monospacedSystemFont(ofSize: 24, weight: .regular)
        view.setFont(big)

        let style = view.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let space = ("    " as NSString).size(withAttributes: [.font: big]).width
        XCTAssertEqual(style?.defaultTabInterval ?? 0, space, accuracy: 0.01)
    }
}
