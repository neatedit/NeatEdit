import Testing
@testable import EditorCore

struct ExternalMergeTests {
    @Test func cleanHunkAppliesIntoMyEdits() throws {
        let merge = ExternalMerge(base: "a\nb\nc\nd", mine: "A\nb\nc\nd", disk: "a\nb\nc\nD")
        let hunk = try #require(merge.hunks.first)
        #expect(merge.hunks.count == 1)
        #expect(!hunk.isConflict)
        #expect(hunk.oldLines == ["d"])
        #expect(hunk.base.newLines == ["D"])
        #expect(merge.apply([hunk.id: .accept]) == "A\nb\nc\nD")
    }

    @Test func skipKeepsMine() {
        let merge = ExternalMerge(base: "a\nb\nc\nd", mine: "A\nb\nc\nd", disk: "a\nb\nc\nD")
        #expect(merge.apply([:]) == "A\nb\nc\nd")
        #expect(merge.apply([merge.hunks[0].id: .skip]) == "A\nb\nc\nd")
    }

    @Test func overlapIsConflict() throws {
        let merge = ExternalMerge(base: "a\nb", mine: "a\nX", disk: "a\nY")
        let hunk = try #require(merge.hunks.first)
        #expect(hunk.isConflict)
        #expect(hunk.mineLines == ["X"])
        #expect(merge.apply([hunk.id: .accept]) == "a\nY")
        #expect(merge.apply([hunk.id: .skip]) == "a\nX")
    }

    @Test func insertionNextToMyChangedLineIsConflict() {
        let merge = ExternalMerge(base: "a\nb", mine: "a\nB", disk: "a\nnew\nb")
        #expect(merge.hunks.count == 1)
        #expect(merge.hunks[0].isConflict)
        #expect(merge.apply([merge.hunks[0].id: .accept]) == "a\nnew\nb")
    }

    @Test func insertionShiftedByMyInsertions() {
        let merge = ExternalMerge(base: "a\nb", mine: "0\na\nb", disk: "a\nb\nc")
        #expect(merge.hunks.count == 1)
        #expect(!merge.hunks[0].isConflict)
        #expect(merge.apply([merge.hunks[0].id: .accept]) == "0\na\nb\nc")
    }

    @Test func acceptsSomeAndSkipsOthers() {
        let merge = ExternalMerge(base: "1\n2\n3\n4\n5", mine: "1\n2\nmine\n4\n5", disk: "X\n2\n3\n4\nY")
        #expect(merge.hunks.map(\.isConflict) == [false, false])
        #expect(merge.apply([merge.hunks[1].id: .accept]) == "1\n2\nmine\n4\nY")
    }

    @Test func idsStableAcrossRediff() {
        let first = ExternalMerge(base: "a\nb\nc\nd", mine: "A\nb\nc\nd", disk: "a\nb\nc\nD")
        let second = ExternalMerge(base: "a\nb\nc\nd", mine: "a\nB\nc\nd", disk: "a\nb\nc\nD")
        #expect(first.hunks.map(\.id) == second.hunks.map(\.id))
    }

    @Test func bigWhenMoreThanHalfChanged() {
        let base = (1...10).map(String.init).joined(separator: "\n")
        let six = ["a", "b", "c", "d", "e", "f", "7", "8", "9", "10"].joined(separator: "\n")
        let five = ["a", "b", "c", "d", "e", "6", "7", "8", "9", "10"].joined(separator: "\n")
        #expect(ExternalMerge(base: base, mine: base, disk: six).isBig)
        #expect(!ExternalMerge(base: base, mine: base, disk: five).isBig)
    }

    @Test func lineEndingOnlyChangeIsEmpty() {
        let merge = ExternalMerge(base: "a\nb", mine: "a\nb", disk: "a\r\nb")
        #expect(merge.isEmpty)
        #expect(!merge.isBig)
    }
}
