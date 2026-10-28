import AppKit
import XCTest
@testable import EditorUI

@MainActor
final class PlainTextViewTests: XCTestCase {
    private func makePasteboard(plain: String, rtf: String) -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("SimpleTextEditTests-\(UUID().uuidString)"))
        pb.clearContents()
        let attributed = NSAttributedString(string: rtf, attributes: [.font: NSFont.boldSystemFont(ofSize: 30)])
        let rtfData = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])!
        pb.declareTypes([.rtf, .string], owner: nil)
        pb.setData(rtfData, forType: .rtf)
        pb.setString(plain, forType: .string)
        return pb
    }

    func testPasteInsertsPlainTextExactlyAtCaret() {
        let view = PlainTextView.make(text: "hello world")
        view.setSelectedRange(NSRange(location: 5, length: 0))

        XCTAssertTrue(view.readSelection(from: makePasteboard(plain: "XYZ", rtf: "XYZ")))

        XCTAssertEqual(view.string, "helloXYZ world")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 8, length: 0))
    }

    func testPasteDropsFormatting() {
        let view = PlainTextView.make(text: "")
        XCTAssertTrue(view.readSelection(from: makePasteboard(plain: "bold", rtf: "bold")))

        let font = view.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font, view.font)
        XCTAssertFalse(view.isRichText)
    }

    func testPasteDoesNotAddSmartSpaces() {
        let view = PlainTextView.make(text: "ab")
        view.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertTrue(view.readSelection(from: makePasteboard(plain: "word", rtf: "word")))
        XCTAssertEqual(view.string, "awordb")
    }

    func testPasteReplacesSelection() {
        let view = PlainTextView.make(text: "one two three")
        view.setSelectedRange(NSRange(location: 4, length: 3))
        XCTAssertTrue(view.readSelection(from: makePasteboard(plain: "2", rtf: "2")))
        XCTAssertEqual(view.string, "one 2 three")
    }

    func testTypingIsNotAutoCorrected() {
        let view = PlainTextView.make(text: "")
        XCTAssertFalse(view.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(view.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(view.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(view.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(view.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(view.smartInsertDeleteEnabled)
    }
}
