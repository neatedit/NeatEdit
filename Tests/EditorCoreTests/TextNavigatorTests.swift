import Foundation
import Testing
@testable import EditorCore

struct TextNavigatorTests {
    private func nav(_ text: String) -> TextNavigator {
        let ns = text as NSString
        return TextNavigator(text: ns, lineIndex: LineIndex(ns))
    }

    @Test func leftAndRightStepOverWholeCharacters() {
        let n = nav("a👍🏽\r\nb")
        #expect(n.right(from: 0) == 1)
        #expect(n.right(from: 1) == 5)  // emoji with skin tone is 4 units
        #expect(n.right(from: 5) == 7)  // CRLF is one step
        #expect(n.right(from: 8) == 8)
        #expect(n.left(from: 7) == 5)
        #expect(n.left(from: 5) == 1)
        #expect(n.left(from: 0) == 0)
    }

    @Test func upAndDownKeepColumnAndClampToShortLines() {
        let n = nav("hello\nhi\nworld")
        // from "hel|lo" down lands at end of "hi", then down again back to column 3
        #expect(n.vertical(from: 3, lines: 1, preferredColumn: 3) == 8)
        #expect(n.vertical(from: 8, lines: 1, preferredColumn: 3) == 12)
        #expect(n.vertical(from: 12, lines: -2, preferredColumn: 3) == 3)
        #expect(n.vertical(from: 3, lines: -1, preferredColumn: 3) == 0)
        #expect(n.vertical(from: 12, lines: 5, preferredColumn: 3) == 14)
    }

    @Test func lineStartAndEnd() {
        let n = nav("ab\r\ncd")
        #expect(n.lineStart(of: 1) == 0)
        #expect(n.lineEnd(of: 1) == 2)
        #expect(n.lineStart(of: 5) == 4)
        #expect(n.lineEnd(of: 4) == 6)
        #expect(n.lineRange(of: 1) == NSRange(location: 0, length: 4))
    }

    @Test func wordAtOffset() {
        let n = nav("foo bar-baz привіт")
        #expect(n.word(at: 1) == NSRange(location: 0, length: 3))
        #expect(n.word(at: 5) == NSRange(location: 4, length: 3))
        #expect(n.word(at: 14) == NSRange(location: 12, length: 6))
        #expect(n.word(at: 3) == NSRange(location: 3, length: 1))  // the space itself
    }

    @Test func snapsToCharacterBoundary() {
        let n = nav("a👍🏽b")
        #expect(n.snap(2) == 1)
        #expect(n.snap(5) == 5)
        #expect(n.snap(99) == 6)
    }
}
