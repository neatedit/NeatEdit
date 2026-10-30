import Foundation
import Testing
@testable import EditorCore

/// Editing a few lines of a huge file: pick them, then write them back into
/// the file without rewriting it from the decoded text.
struct LineSpliceTests {
    private func lines(_ count: Int, prefix: String = "line") -> String {
        (1...count).map { "\(prefix) \($0)\n" }.joined()
    }

    private func file(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try data.write(to: url)
        return url
    }

    private func pick(
        _ text: String, around selection: NSRange, context: Int = 10,
        encoding: String.Encoding = .utf8, hasBOM: Bool = false
    ) -> LineSplice.Chunk {
        let string = text as NSString
        return LineSplice.chunk(around: selection, context: context, in: string, lineIndex: LineIndex(string),
                                encoding: encoding, hasBOM: hasBOM)
    }

    // MARK: Picking the lines

    @Test func takesTheCaretLineAndTenEachSideWithoutTheLastBreak() {
        let text = lines(100)
        let offset = (text as NSString).range(of: "line 50\n").location + 2
        let chunk = pick(text, around: NSRange(location: offset, length: 0))
        #expect(chunk.firstLine == 39 && chunk.lastLine == 59)
        #expect(chunk.text.hasPrefix("line 40\n") && chunk.text.hasSuffix("line 60"))
    }

    @Test func takesEverySelectedLinePlusContext() {
        let text = lines(100)
        let start = (text as NSString).range(of: "line 30\n").location
        let end = (text as NSString).range(of: "line 35\n").location + 3
        let chunk = pick(text, around: NSRange(location: start, length: end - start))
        #expect(chunk.firstLine == 19 && chunk.lastLine == 44)
    }

    @Test func stopsAtTheEdgesOfTheFile() {
        let text = lines(5)
        let chunk = pick(text, around: NSRange(location: 0, length: 0))
        #expect(chunk.firstLine == 0)
        #expect(chunk.text == "line 1\nline 2\nline 3\nline 4\nline 5")
        let noBreak = pick("a\nb", around: NSRange(location: 2, length: 0))
        #expect(noBreak.text == "a\nb")
    }

    // MARK: Writing them back

    @Test func writesTheEditBetweenTheUntouchedBytes() throws {
        let text = "заголовок\n" + lines(50)  // multibyte text before the chunk
        let url = try file(Data(text.utf8))
        let chunk = pick(text, around: NSRange(location: (text as NSString).range(of: "line 25").location, length: 0), context: 1)
        try LineSplice.write("line 24\nEDITED\nand one more\nline 26", over: chunk, to: url)
        let expected = text.replacingOccurrences(of: "line 25\n", with: "EDITED\nand one more\n")
        #expect(try String(contentsOf: url, encoding: .utf8) == expected)
    }

    @Test func refusesWhenTheLinesChangedOnDisk() throws {
        let text = lines(50)
        let url = try file(Data(text.utf8))
        let chunk = pick(text, around: NSRange(location: (text as NSString).range(of: "line 25").location, length: 0), context: 1)
        let changed = text.replacingOccurrences(of: "line 25", with: "LINE 25")
        try Data(changed.utf8).write(to: url)
        #expect(throws: LineSplice.Failure.changedOnDisk) {
            try LineSplice.write("x", over: chunk, to: url)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == changed)
    }

    @Test func keepsWhatWasAppendedAfterTheFileWasRead() throws {
        let text = lines(50)
        let url = try file(Data(text.utf8))
        let chunk = pick(text, around: NSRange(location: 0, length: 0), context: 0)
        try Data((text + "appended\n").utf8).write(to: url)
        try LineSplice.write("first", over: chunk, to: url)
        let result = try String(contentsOf: url, encoding: .utf8)
        #expect(result.hasPrefix("first\nline 2\n"))
        #expect(result.hasSuffix("line 50\nappended\n"))
    }

    @Test func keepsTheBOMAndTheEncoding() throws {
        let text = "Привіт\n" + lines(10)
        var data = Data([0xFF, 0xFE])
        data.append(text.data(using: .utf16LittleEndian)!)
        let url = try file(data)
        let chunk = pick(text, around: NSRange(location: (text as NSString).range(of: "line 5").location, length: 0), context: 0,
                         encoding: .utf16LittleEndian, hasBOM: true)
        try LineSplice.write("п'ять", over: chunk, to: url)
        let written = try Data(contentsOf: url)
        #expect(written.prefix(2) == Data([0xFF, 0xFE]))
        #expect(String(data: written.dropFirst(2), encoding: .utf16LittleEndian) == text.replacingOccurrences(of: "line 5\n", with: "п'ять\n"))

        let legacy = "Тест\n" + lines(3)
        let legacyURL = try file(legacy.data(using: .windowsCP1251)!)
        let legacyChunk = pick(legacy, around: NSRange(location: 6, length: 0), context: 0, encoding: .windowsCP1251)
        try LineSplice.write("Рядок", over: legacyChunk, to: legacyURL)
        #expect(String(data: try Data(contentsOf: legacyURL), encoding: .windowsCP1251) == "Тест\nРядок\nline 2\nline 3\n")
    }

    @Test func refusesTextTheEncodingCantHoldAndLeavesTheFileAlone() throws {
        let text = lines(3)
        let url = try file(text.data(using: .windowsCP1251)!)
        let chunk = pick(text, around: NSRange(location: 0, length: 0), context: 0, encoding: .windowsCP1251)
        #expect(throws: LineSplice.Failure.unencodable) {
            try LineSplice.write("😀", over: chunk, to: url)
        }
        #expect(try Data(contentsOf: url) == text.data(using: .windowsCP1251)!)
    }

    @Test func onlyEncodingsWithAFixedByteMappingAreSupported() {
        #expect(LineSplice.supports(.utf8) && LineSplice.supports(.utf16LittleEndian) && LineSplice.supports(.windowsCP1251))
        #expect(!LineSplice.supports(.utf32LittleEndian) && !LineSplice.supports(.utf16))
    }

    @Test func theSameLengthIsWrittenInPlace() throws {
        let text = lines(50)
        let url = try file(Data(text.utf8))
        let inode = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int
        let chunk = pick(text, around: NSRange(location: (text as NSString).range(of: "line 25").location, length: 0), context: 0)
        try LineSplice.write("LINE 25", over: chunk, to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == text.replacingOccurrences(of: "line 25\n", with: "LINE 25\n"))
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int == inode,
                "same file: a logger holding it open keeps writing to it")
    }

    @Test func aSymlinkIsWrittenThroughToItsTarget() throws {
        let text = lines(5)
        let target = try file(Data(text.utf8))
        let link = target.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString)-link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let chunk = pick(text, around: NSRange(location: 0, length: 0), context: 0)
        try LineSplice.write("the first line", over: chunk, to: link)
        #expect(try String(contentsOf: target, encoding: .utf8).hasPrefix("the first line\nline 2"))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil, "still a link")
    }

    @Test func theOffsetIsCountedWhenTheLinesArePicked() throws {
        let text = "ґанок\n" + lines(5)  // 11 bytes before "line 1"
        let chunk = pick(text, around: NSRange(location: 7, length: 0), context: 0)
        #expect(chunk.byteOffset == 11)
        #expect(pick(text, around: NSRange(location: 0, length: 0), encoding: .utf32LittleEndian).byteOffset == nil)
        #expect(LineSplice.byteCount(of: NSRange(location: 0, length: 100), in: "abc", encoding: .utf8) == nil)
    }

    @Test func onlyTypedLineBreaksTakeTheChunksEnding() {
        // Untouched text comes back byte for byte, whatever it holds.
        let mixed = "progress 10%\rprogress 20%\r\nlf only\nend"
        #expect(LineSplice.matchingLineBreaks(mixed, original: mixed) == mixed)
        #expect(LineSplice.matchingLineBreaks(mixed + "\nnew", original: mixed) == mixed + "\nnew", "mixed: leave it")
        // An all-CRLF chunk: a typed LF becomes CRLF; a lone CR inside a line stays.
        let crlf = "a 10%\r20%\r\nb\r\nc"
        #expect(LineSplice.matchingLineBreaks("a 10%\r20%\r\nb\nadded\r\nc", original: crlf) == "a 10%\r20%\r\nb\r\nadded\r\nc")
        #expect(LineSplice.matchingLineBreaks("x\ny", original: "a\rb") == "x\ry")
        #expect(LineSplice.matchingLineBreaks("x\ny", original: "a\nb") == "x\ny")
        #expect(LineSplice.matchingLineBreaks("x\ny", original: "single line") == "x\ny")
    }
}
