import Foundation
import Testing
@testable import EditorCore

struct CursorPositionTests {
    private func pos(_ text: String, _ offset: Int) -> (Int, Int, Int) {
        let p = CursorPosition(in: text, utf16Offset: offset)
        return (p.line, p.column, p.offset)
    }

    @Test func startOfText() {
        #expect(pos("hello", 0) == (1, 1, 0))
    }

    @Test func middleOfFirstLine() {
        #expect(pos("hello", 3) == (1, 4, 3))
    }

    @Test func secondLineAfterLF() {
        #expect(pos("ab\ncd", 4) == (2, 2, 4))
    }

    @Test func rightAfterNewlineIsColumnOne() {
        #expect(pos("ab\ncd", 3) == (2, 1, 3))
    }

    @Test func crlfCountsAsOneLineBreakAndOneCharacter() {
        // "ab\r\ncd" — cursor before "d"
        #expect(pos("ab\r\ncd", 5) == (2, 2, 4))
    }

    @Test func classicMacCR() {
        #expect(pos("ab\rcd", 4) == (2, 2, 4))
    }

    @Test func emojiAndCyrillicCountAsSingleCharacters() {
        // "👍🏽" is 4 UTF-16 units but one character
        let text = "👍🏽при"
        #expect(pos(text, (text as NSString).length) == (1, 5, 4))
    }

    @Test func offsetBeyondEndIsClamped() {
        #expect(pos("ab", 99) == (1, 3, 2))
    }

    @Test func emptyText() {
        #expect(pos("", 0) == (1, 1, 0))
    }

    @Test func reportsCurrentLineLengthWithoutLineBreak() {
        let text = "ab\r\nпривіт👍🏽\nx"
        #expect(CursorPosition(in: text, utf16Offset: 1).lineLength == 2)
        #expect(CursorPosition(in: text, utf16Offset: 5).lineLength == 7)
        #expect(CursorPosition(in: text, utf16Offset: (text as NSString).length).lineLength == 1)
    }

    @Test func fallsBackToUTF16CountsBeyondLimit() {
        let text = "👍🏽👍🏽" as NSString
        let index = LineIndex(text)
        let p = CursorPosition(in: text, utf16Offset: 8, lineIndex: index, exactCountLimit: 4)
        #expect(p.offset == 8)
        #expect(p.column == 9)
        #expect(p.lineLength == 8)
        #expect(p.isApproximate)
    }
}
