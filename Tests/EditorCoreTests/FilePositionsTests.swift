import Foundation
import Testing
@testable import EditorCore

struct FilePositionsTests {
    private func at(_ location: Int) -> FilePosition {
        FilePosition(location: location, length: 0, topLine: 0, atEnd: false)
    }

    @Test func remembersByPathAndReplaces() {
        var positions = FilePositions()
        positions.set(at(5), for: "/a")
        positions.set(at(7), for: "/b")
        positions.set(at(9), for: "/a")
        #expect(positions.position(for: "/a") == at(9))
        #expect(positions.position(for: "/b") == at(7))
        #expect(positions.position(for: "/c") == nil)
        #expect(positions.count == 2)
    }

    @Test func theStartOfAFileIsForgotten() {
        var positions = FilePositions()
        positions.set(at(5), for: "/a")
        positions.set(at(0), for: "/a")
        #expect(positions.position(for: "/a") == nil)
        #expect(positions.count == 0)
    }

    @Test func dropsTheOldestPastTheLimit() {
        var positions = FilePositions()
        for index in 0...FilePositions.limit { positions.set(at(index + 1), for: "/\(index)") }
        #expect(positions.count == FilePositions.limit)
        #expect(positions.position(for: "/0") == nil)
        #expect(positions.position(for: "/1") != nil)
        // Saving again makes a file the newest.
        positions.set(at(1), for: "/1")
        positions.set(at(1), for: "/new")
        #expect(positions.position(for: "/1") != nil)
        #expect(positions.position(for: "/2") == nil)
    }

    @Test func survivesEncoding() throws {
        var positions = FilePositions()
        positions.set(FilePosition(location: 3, length: 2, topLine: 1, atEnd: true), for: "/a")
        let decoded = try JSONDecoder().decode(FilePositions.self, from: JSONEncoder().encode(positions))
        #expect(decoded == positions)
    }

    @Test func theSelectionFitsTheTextOfToday() {
        let position = FilePosition(location: 2, length: 3, topLine: 0, atEnd: false)
        #expect(position.selection(in: "abcdefgh") == NSRange(location: 2, length: 3))
        #expect(position.selection(in: "abcd") == NSRange(location: 2, length: 0), "the selection no longer fits")
        #expect(position.selection(in: "a") == NSRange(location: 1, length: 0), "the file got shorter")
        #expect(at(1).selection(in: "😀a") == NSRange(location: 0, length: 0), "never inside a character")
        // A damaged value in the defaults can't crash an open.
        #expect(at(-1).selection(in: "abc") == NSRange(location: 0, length: 0))
        #expect(FilePosition(location: 1, length: .max, topLine: 0, atEnd: false).selection(in: "abc") == NSRange(location: 1, length: 0))
        #expect(FilePosition(location: 1, length: -5, topLine: 0, atEnd: false).selection(in: "abc") == NSRange(location: 1, length: 0))
    }
}
