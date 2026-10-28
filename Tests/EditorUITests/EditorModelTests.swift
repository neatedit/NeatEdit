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

    func testEncodesWithOriginalEncodingAndLineEnding() throws {
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("a\r\nb".utf8)
        let model = EditorModel(file: try TextFile(data: original))
        model.storage.replaceCharacters(in: NSRange(location: 4, length: 0), with: "\nc")
        XCTAssertEqual(model.lineEnding, .crlf)
        XCTAssertEqual(try model.encodedData(), Data([0xEF, 0xBB, 0xBF]) + Data("a\r\nb\r\nc".utf8))
    }

    func testFallsBackToUTF8WhenTextNoLongerFitsEncoding() throws {
        let model = EditorModel(file: try TextFile(data: "привіт".data(using: .windowsCP1251)!))
        model.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "👍")
        XCTAssertEqual(try model.encodedData(), Data("👍привіт".utf8))
        XCTAssertEqual(model.file.encoding, .utf8)
    }
}
