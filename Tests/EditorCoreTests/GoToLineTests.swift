import Foundation
import Testing
@testable import EditorCore

struct GoToLineTests {
    @Test func parsesLineAndOptionalColumn() {
        #expect(GoToLine.parse("12") == GoToLine(line: 12, column: 1))
        #expect(GoToLine.parse(" 12:5 ") == GoToLine(line: 12, column: 5))
        #expect(GoToLine.parse("3,4") == GoToLine(line: 3, column: 4))
        #expect(GoToLine.parse("") == nil)
        #expect(GoToLine.parse("abc") == nil)
        #expect(GoToLine.parse("0") == nil)
    }

    @Test func resolvesToUTF16Offset() {
        let text = "ab\n👍🏽cd\nx" as NSString
        let index = LineIndex(text)
        #expect(GoToLine(line: 1, column: 1).offset(in: text, lineIndex: index) == 0)
        #expect(GoToLine(line: 2, column: 1).offset(in: text, lineIndex: index) == 3)
        // column counts characters, so column 2 is after the 4-unit emoji
        #expect(GoToLine(line: 2, column: 2).offset(in: text, lineIndex: index) == 7)
    }

    @Test func clampsToLineAndDocumentEnds() {
        let text = "ab\ncd" as NSString
        let index = LineIndex(text)
        #expect(GoToLine(line: 1, column: 99).offset(in: text, lineIndex: index) == 2)
        #expect(GoToLine(line: 99, column: 1).offset(in: text, lineIndex: index) == 3)
    }
}
