import Foundation
import Testing
@testable import EditorCore

struct StatusLineTests {
    @Test func countsCharactersInRange() {
        let text = "a👍🏽\r\nб" as NSString
        #expect(CharacterCount(in: text, range: NSRange(location: 0, length: text.length)) == CharacterCount(value: 4, isApproximate: false))
        #expect(CharacterCount(in: text, range: NSRange(location: 0, length: text.length), exactLimit: 2) == CharacterCount(value: 8, isApproximate: true))
    }

    @Test func formatsCaretWithoutSelection() {
        let status = StatusLine(
            position: CursorPosition(in: "hello\nworld", utf16Offset: 8),
            selection: nil,
            totalCharacters: CharacterCount(value: 11, isApproximate: false),
            lines: 2,
            encoding: "UTF-8",
            lineEnding: .lf
        )
        #expect(status.left == "Ln 2, Col 3   Pos 8   Line 5 chars")
        #expect(status.right == "11 chars, 2 lines   UTF-8   LF")
        #expect(status.totals == "11 chars, 2 lines")
        #expect(status.encoding == "UTF-8")
        #expect(status.lineEnding == .lf)
    }

    @Test func formatsSelectionAndBigNumbersWithSeparators() {
        let status = StatusLine(
            position: CursorPosition(in: "abc", utf16Offset: 1),
            selection: CharacterCount(value: 1234, isApproximate: false),
            totalCharacters: CharacterCount(value: 1_234_567, isApproximate: true),
            lines: 20_000,
            encoding: "UTF-8",
            lineEnding: .crlf
        )
        #expect(status.left == "Ln 1, Col 2   Pos 1   Line 3 chars   Sel 1 234")
        #expect(status.right == "~1 234 567 chars, 20 000 lines   UTF-8   CRLF")
    }

    @Test func totalsStillCountingShowEllipsis() {
        let status = StatusLine(
            position: CursorPosition(in: "", utf16Offset: 0),
            selection: nil,
            totalCharacters: nil,
            lines: 1,
            encoding: "UTF-8",
            lineEnding: .lf
        )
        #expect(status.right == "… chars, 1 lines   UTF-8   LF")
    }
}
