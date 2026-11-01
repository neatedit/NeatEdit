import AppKit
import XCTest
import EditorCore
@testable import EditorUI

@MainActor
final class EditorModelTests: XCTestCase {
    func testLineIndexFollowsEdits() {
        let model = EditorModel(file: TextFile(text: "a\nb"))
        model.storage.replaceCharacters(in: NSRange(location: 1, length: 0), with: "\n\n")
        XCTAssertEqual(model.lineIndex.starts, [0, 2, 3, 4])
        model.storage.replaceCharacters(in: NSRange(location: 0, length: 3), with: "")
        XCTAssertEqual(model.lineIndex.starts, LineIndex(model.storage.string as NSString).starts)
    }

    func testStatusForCaretAndSelection() {
        let model = EditorModel(file: TextFile(text: "hello\nworld"))
        XCTAssertEqual(model.status(selectedRange: NSRange(location: 8, length: 0)).left,
                       "Ln 2, Col 3   Pos 8   Line 5 chars")
        XCTAssertEqual(model.status(selectedRange: NSRange(location: 6, length: 5)).left,
                       "Ln 2, Col 1   Pos 6   Line 5 chars   Sel 5")
    }

    func testSmallDocumentTotalsAreImmediate() {
        let model = EditorModel(file: TextFile(text: "привіт\n"))
        XCTAssertEqual(model.status(selectedRange: NSRange(location: 0, length: 0)).right,
                       "7 chars, 2 lines   UTF-8   LF")
    }

    func testAppendKeepsLinesAndTotals() {
        let model = EditorModel(file: TextFile(text: "a\r"))
        _ = model.status(selectedRange: NSRange(location: 0, length: 0))
        model.append("\nb\n")
        XCTAssertEqual(model.storage.string, "a\r\nb\n")
        XCTAssertEqual(model.lineIndex.starts, LineIndex(model.storage.string as NSString).starts)
        // "\r" + "\n" became one character, and it isn't the "\n" that follows.
        XCTAssertEqual(model.status(selectedRange: NSRange(location: 0, length: 0)).right, "4 chars, 3 lines   UTF-8   Mixed")
    }

    func testAnAppendCompletingTheFirstLineBreakIsNotMixed() {
        let model = EditorModel(file: TextFile(text: "a\r"))
        model.append("\nb\r\n")
        XCTAssertFalse(model.hasMixedEndings)
    }

    func testAppendThatCompletesTheLastCharacterAddsNone() {
        let model = EditorModel(file: TextFile(text: "cafe"))
        _ = model.status(selectedRange: NSRange(location: 0, length: 0))
        model.append("\u{301}!")
        XCTAssertEqual(model.status(selectedRange: NSRange(location: 0, length: 0)).right, "5 chars, 1 lines   UTF-8   LF")
    }

    func testAppendsWhileCountingDoNotRestartTheCount() {
        let model = EditorModel(file: TextFile(text: String(repeating: "a", count: EditorModel.syncCountLimit + 1)))
        var finished = false
        model.onTotalsChanged = { finished = true }
        XCTAssertTrue(model.status(selectedRange: NSRange(location: 0, length: 0)).right.hasPrefix("… chars"), model.status(selectedRange: NSRange(location: 0, length: 0)).right)
        let deadline = Date().addingTimeInterval(10)
        var appended = 0
        // A log written faster than the count's debounce must not starve it.
        while !finished, Date() < deadline {
            model.append("x")
            appended += 1
            _ = model.status(selectedRange: NSRange(location: 0, length: 0))
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(finished)
        let total = EditorModel.syncCountLimit + 1 + appended
        let right = model.status(selectedRange: NSRange(location: 0, length: 0)).right
        XCTAssertTrue(right.replacingOccurrences(of: " ", with: "").hasPrefix("\(total)chars"), right)
    }

    func testEncodesWithOriginalEncodingAndLineEnding() throws {
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("a\r\nb".utf8)
        let model = EditorModel(file: try TextFile(data: original))
        model.storage.replaceCharacters(in: NSRange(location: 4, length: 0), with: "\nc")
        XCTAssertEqual(model.lineEnding, .crlf)
        XCTAssertEqual(try model.encodedData(), Data([0xEF, 0xBB, 0xBF]) + Data("a\r\nb\r\nc".utf8))
    }

    func testMixedLineEndingsAreSavedAsTheyWere() throws {
        for text in ["a\r\nb\nc", "a\nb\r\nc", "a\r\nb\rc\nd", "a\rb\nc"] {
            let model = EditorModel(file: TextFile(text: text))
            XCTAssertEqual(try model.encodedData(), Data(text.utf8), text.debugDescription)
        }
    }

    func testAnEditInAMixedFileLeavesItsOtherLineEndingsAlone() throws {
        let model = EditorModel(file: TextFile(text: "a\r\nb\nc"))
        model.storage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "A")
        XCTAssertEqual(try model.encodedData(), Data("A\r\nb\nc".utf8))
    }

    func testAnAppendWithAnotherLineEndingMakesTheTextMixed() throws {
        let model = EditorModel(file: TextFile(text: "a\r\nb"))
        model.append("\r\nc")
        XCTAssertFalse(model.hasMixedEndings)
        model.append("\nd")
        XCTAssertTrue(model.hasMixedEndings)
        XCTAssertEqual(try model.encodedData(), Data("a\r\nb\r\nc\nd".utf8))
    }

    func testAppendsToACRLFTextEndingInALineBreakAreNotMixed() {
        let model = EditorModel(file: TextFile(text: "a\r\nb\r\n"))
        model.append("c\r\n")
        model.append("d\r\n")
        XCTAssertFalse(model.hasMixedEndings)
    }

    func testAnAppendCompletingALineBreakIsNotMixed() {
        let model = EditorModel(file: TextFile(text: "a\r\nb\r"))
        model.append("\nc")
        XCTAssertFalse(model.hasMixedEndings)
    }

    func testAFirstAppendSetsNoMixtureByItself() {
        let model = EditorModel(file: TextFile(text: "partial"))
        model.append(" line\r\nnext\r\n")
        XCTAssertFalse(model.hasMixedEndings)
    }

    func testTheFirstLineBreakAppendedSetsTheLineEnding() {
        let model = EditorModel(file: TextFile(text: "partial"))
        model.append(" line\r\n")
        XCTAssertEqual(model.lineEnding, .crlf)
        model.append("next\r\n")
        XCTAssertFalse(model.hasMixedEndings)
    }

    func testFallsBackToUTF8WhenTextNoLongerFitsEncoding() throws {
        let model = EditorModel(file: try TextFile(data: "привіт".data(using: .windowsCP1251)!))
        model.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "👍")
        XCTAssertEqual(try model.encodedData(), Data("👍привіт".utf8))
        XCTAssertEqual(model.file.encoding, .utf8)
    }
}
