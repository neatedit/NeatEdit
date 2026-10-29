import Foundation
import Testing
@testable import EditorCore

struct FileTailTests {
    /// A file on "disk" the tail reads byte ranges from.
    private final class Disk {
        var data: Data
        var reads: [Range<Int>] = []
        init(_ text: String) { data = Data(text.utf8) }
        func append(_ bytes: Data) { data.append(bytes) }
        func append(_ text: String) { append(Data(text.utf8)) }
        func read(_ range: Range<Int>) -> Data {
            reads.append(range)
            return data.subdata(in: range.clamped(to: 0..<data.count))
        }
    }

    private func update(_ tail: inout FileTail, _ disk: Disk) -> FileTail.Change {
        tail.update(size: disk.data.count, read: disk.read)
    }

    @Test func appendedTextIsDecodedReadingOnlyTheEnd() throws {
        let disk = Disk(String(repeating: "old line\n", count: 2_000))
        var tail = try #require(FileTail(data: disk.data, encoding: .utf8))
        let size = disk.data.count
        disk.append("new line\n")
        #expect(update(&tail, disk) == .appended("new line\n"))
        // The check sample just before the old end, then the new bytes.
        #expect(disk.reads.allSatisfy { $0.lowerBound >= size - FileTail.sampleSize })
        #expect(tail.byteCount == disk.data.count)
    }

    @Test func sameSizeIsUnchanged() throws {
        let disk = Disk("a\n")
        var tail = try #require(FileTail(data: disk.data, encoding: .utf8))
        #expect(update(&tail, disk) == .unchanged)
    }

    @Test func shrinkingOrRewrittenFileNeedsAFullReload() throws {
        let disk = Disk("first\nsecond\n")
        var tail = try #require(FileTail(data: disk.data, encoding: .utf8))
        disk.data = Data("first\n".utf8)
        #expect(update(&tail, disk) == .rewritten)

        let other = Disk("aaaa\n")
        var otherTail = try #require(FileTail(data: other.data, encoding: .utf8))
        other.data = Data("bbbb\nmore\n".utf8)
        #expect(update(&otherTail, other) == .rewritten)
    }

    @Test func splitUTF8CharacterWaitsForItsLastByte() throws {
        let disk = Disk("x")
        var tail = try #require(FileTail(data: disk.data, encoding: .utf8))
        let letter = Data("ї".utf8)  // two bytes
        disk.append(letter.prefix(1))
        #expect(update(&tail, disk) == .unchanged)
        disk.append(letter.suffix(1))
        disk.append("!")
        #expect(update(&tail, disk) == .appended("ї!"))
    }

    @Test func singleByteEncodingsWork() throws {
        let disk = Disk("")
        disk.data = "Привіт\n".data(using: .windowsCP1251)!
        var tail = try #require(FileTail(data: disk.data, encoding: .windowsCP1251))
        disk.append("світ\n".data(using: .windowsCP1251)!)
        #expect(update(&tail, disk) == .appended("світ\n"))
    }

    @Test func wideEncodingsAreNotFollowed() {
        #expect(FileTail(data: Data(), encoding: .utf16LittleEndian) == nil)
    }

    @Test func invalidAppendedBytesNeedAFullReload() throws {
        let disk = Disk("ok\n")
        var tail = try #require(FileTail(data: disk.data, encoding: .utf8))
        disk.append(Data([0xFF, 0xFE, 0x41]))
        #expect(update(&tail, disk) == .rewritten)
    }

    @Test func successiveAppendsKeepFollowing() throws {
        let disk = Disk("")
        var tail = try #require(FileTail(data: disk.data, encoding: .utf8))
        for i in 0..<5 {
            disk.append("line \(i)\n")
            #expect(update(&tail, disk) == .appended("line \(i)\n"))
        }
    }
}
