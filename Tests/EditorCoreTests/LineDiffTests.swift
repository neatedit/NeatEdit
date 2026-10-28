import Foundation
import Testing
@testable import EditorCore

struct LineDiffTests {
    private func diff(_ old: String, _ new: String) -> [DiffHunk] {
        LineDiff.hunks(old: normalizedLines(old), new: normalizedLines(new))
    }

    @Test func identicalTextHasNoHunks() {
        #expect(diff("a\nb", "a\nb") == [])
    }

    @Test func crlfAndLfAreIdentical() {
        #expect(normalizedLines("a\r\nb\r\n") == normalizedLines("a\nb\n"))
        #expect(normalizedLines("a\rb") == ["a", "b"])
        #expect(normalizedLines("a\nb\n") == ["a", "b", ""])
    }

    @Test func changedLine() {
        #expect(diff("a\nb\nc", "a\nB\nc") == [DiffHunk(oldRange: 1..<2, newLines: ["B"])])
    }

    @Test func insertion() {
        #expect(diff("a\nc", "a\nb\nc") == [DiffHunk(oldRange: 1..<1, newLines: ["b"])])
    }

    @Test func deletion() {
        #expect(diff("a\nb\nc", "a\nc") == [DiffHunk(oldRange: 1..<2, newLines: [])])
    }

    @Test func twoSeparateHunks() {
        #expect(diff("1\n2\n3\n4\n5", "X\n2\n3\n4\nY") == [
            DiffHunk(oldRange: 0..<1, newLines: ["X"]),
            DiffHunk(oldRange: 4..<5, newLines: ["Y"]),
        ])
    }

    @Test func appendAtEnd() {
        #expect(diff("a", "a\nb") == [DiffHunk(oldRange: 1..<1, newLines: ["b"])])
    }

    @Test func everythingReplaced() {
        #expect(diff("a\nb", "x\ny\nz") == [DiffHunk(oldRange: 0..<2, newLines: ["x", "y", "z"])])
    }

    @Test func rewrittenFileBecomesOneHunk() {
        let old = (0..<3_000).map { Substring("old \($0)") }
        let new = (0..<3_000).map { Substring("new \($0)") }
        let hunks = LineDiff.hunks(old: old, new: new)
        #expect(hunks.count == 1)
        #expect(hunks[0].oldRange == 0..<3_000)
        #expect(hunks[0].newLines.count == 3_000)
    }

    @Test func diffOf100kLinesWithFewChangesIsFast() {
        let old = (0..<100_000).map { "line \($0)" }
        var new = old
        for i in stride(from: 5_000, to: 100_000, by: 10_000) { new[i] = "changed \(i)" }
        let start = Date()
        let hunks = LineDiff.hunks(old: old.map { Substring($0) }, new: new.map { Substring($0) })
        #expect(Date().timeIntervalSince(start) < 0.5)
        #expect(hunks.count == 10)
        #expect(hunks[0] == DiffHunk(oldRange: 5_000..<5_001, newLines: ["changed 5000"]))
    }
}
