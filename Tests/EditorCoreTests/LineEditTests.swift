import Foundation
import Testing
@testable import EditorCore

struct LineEditTests {
    /// Applies the edit and returns the text and the new selection.
    private func run(_ text: String, _ selection: NSRange, _ make: (NSString, NSRange) -> LineEdit?) -> (String, NSRange)? {
        let string = text as NSString
        guard let edit = make(string, selection) else { return nil }
        return (string.replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
    }

    private func at(_ location: Int, _ length: Int = 0) -> NSRange { NSRange(location: location, length: length) }

    // MARK: Duplicate

    @Test func duplicateCopiesTheCaretLineBelowAndFollowsIt() {
        let result = run("one\ntwo\nthree", at(5), LineEdit.duplicate)
        #expect(result?.0 == "one\ntwo\ntwo\nthree")
        #expect(result?.1 == at(9))
    }

    @Test func duplicateOfTheLastLineWithoutABreakAddsOne() {
        #expect(run("one\ntwo", at(6), LineEdit.duplicate)?.0 == "one\ntwo\ntwo")
        #expect(run("one\r\ntwo", at(7), LineEdit.duplicate)?.0 == "one\r\ntwo\r\ntwo")
        #expect(run("solo", at(2), LineEdit.duplicate)?.0 == "solo\nsolo")
        #expect(run("solo", at(2), LineEdit.duplicate)?.1 == at(7))
    }

    @Test func duplicateCopiesASelectionInPlaceAndSelectsTheCopy() {
        let result = run("say hello!", at(4, 5), LineEdit.duplicate)
        #expect(result?.0 == "say hellohello!")
        #expect(result?.1 == at(9, 5))
    }

    @Test func duplicateOfASelectionOverSeveralLinesCopiesThoseLines() {
        let result = run("a\nbb\ncc\nd", at(3, 3), LineEdit.duplicate)
        #expect(result?.0 == "a\nbb\ncc\nbb\ncc\nd")
        #expect(result?.1 == at(9, 3))
    }

    // MARK: Move

    @Test func moveUpSwapsWithThePreviousLine() {
        let result = run("one\ntwo\nthree\n", at(6), LineEdit.moveUp)
        #expect(result?.0 == "two\none\nthree\n")
        #expect(result?.1 == at(2))
    }

    @Test func moveDownSwapsWithTheNextLine() {
        let result = run("one\ntwo\nthree\n", at(1, 1), LineEdit.moveDown)
        #expect(result?.0 == "two\none\nthree\n")
        #expect(result?.1 == at(5, 1))
    }

    @Test func movingTheLastLineWithoutABreakKeepsBreaksInPlace() {
        #expect(run("one\ntwo", at(5), LineEdit.moveUp)?.0 == "two\none")
        #expect(run("one\ntwo", at(1), LineEdit.moveDown)?.0 == "two\none")
        #expect(run("one\ntwo", at(1), LineEdit.moveDown)?.1 == at(5))
    }

    @Test func aSelectionMovesAllItsLines() {
        // "bb\ncc" selected, ending right after the break of "cc": two lines.
        let result = run("a\nbb\ncc\nd\n", at(2, 6), LineEdit.moveUp)
        #expect(result?.0 == "bb\ncc\na\nd\n")
        #expect(result?.1 == at(0, 6))
    }

    @Test func nothingToMoveAtTheEdges() {
        #expect(run("one\ntwo", at(1), LineEdit.moveUp) == nil)
        #expect(run("one\ntwo", at(5), LineEdit.moveDown) == nil)
        #expect(run("one\ntwo\n", at(5), LineEdit.moveDown) == nil)
        #expect(run("", at(0), LineEdit.moveDown) == nil)
    }

    @Test func crlfLinesStayWhole() {
        #expect(run("a\r\nb\r\nc", at(3), LineEdit.moveUp)?.0 == "b\r\na\r\nc")
        #expect(run("a\r\nb", at(0), LineEdit.moveDown)?.0 == "b\r\na")
    }
}
