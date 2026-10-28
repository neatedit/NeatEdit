import Foundation
import Testing
@testable import EditorCore

struct LineIndexTests {
    @Test func buildsLineStarts() {
        #expect(LineIndex("" as NSString).starts == [0])
        #expect(LineIndex("ab" as NSString).starts == [0])
        #expect(LineIndex("ab\ncd\n" as NSString).starts == [0, 3, 6])
        #expect(LineIndex("a\r\nb\rc" as NSString).starts == [0, 3, 5])
    }

    @Test func longestLineIncludesBreakInUTF16Units() {
        #expect(LineIndex("" as NSString).longestLine(textLength: 0) == 0)
        let text = "ab\nabcdef\nx" as NSString
        #expect(LineIndex(text).longestLine(textLength: text.length) == 7)
    }

    @Test func findsLineContainingOffset() {
        let index = LineIndex("ab\ncd\nef" as NSString)
        #expect(index.line(containing: 0) == 0)
        #expect(index.line(containing: 2) == 0)
        #expect(index.line(containing: 3) == 1)
        #expect(index.line(containing: 8) == 2)
    }

    @Test func splittingCRLFCreatesTwoBreaks() {
        let text = NSMutableString(string: "a\r\nb")
        var index = LineIndex(text)
        text.insert("x", at: 2)  // "a\rx\nb"
        index.update(in: text, editedRange: NSRange(location: 2, length: 1), changeInLength: 1)
        #expect(index.starts == [0, 2, 4])
    }

    @Test func joiningCRAndLFCreatesOneBreak() {
        let text = NSMutableString(string: "a\rx\nb")
        var index = LineIndex(text)
        text.deleteCharacters(in: NSRange(location: 2, length: 1))  // "a\r\nb"
        index.update(in: text, editedRange: NSRange(location: 2, length: 0), changeInLength: -1)
        #expect(index.starts == [0, 3])
    }

    @Test func incrementalUpdatesMatchFullRebuild() {
        var rng = SystemRandomNumberGenerator()
        let alphabet = ["a", "b", "\n", "\r", "\r\n", "й", "👍🏽"]
        let text = NSMutableString(string: "hello\nworld\r\nfoo\rbar")
        var index = LineIndex(text)

        for _ in 0..<2000 {
            let length = text.length
            let location = Int.random(in: 0...length, using: &rng)
            let deleteLength = Int.random(in: 0...min(3, length - location), using: &rng)
            let insert = (0..<Int.random(in: 0...3, using: &rng))
                .map { _ in alphabet.randomElement(using: &rng)! }
                .joined()
            text.replaceCharacters(in: NSRange(location: location, length: deleteLength), with: insert)
            let inserted = (insert as NSString).length
            index.update(
                in: text,
                editedRange: NSRange(location: location, length: inserted),
                changeInLength: inserted - deleteLength
            )
            #expect(index.starts == LineIndex(text).starts, "text: \(text.debugDescription)")
            if index.starts != LineIndex(text).starts { break }
        }
    }
}
