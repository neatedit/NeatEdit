import Foundation
import Testing
@testable import EditorCore

struct TextFileTests {
    @Test func decodesUTF8() throws {
        let file = try TextFile(data: Data("привіт\n".utf8))
        #expect(file.text == "привіт\n")
        #expect(file.encoding == .utf8)
        #expect(file.hasBOM == false)
    }

    @Test func decodesUTF8WithBOMAndRemembersIt() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("hi".utf8)
        let file = try TextFile(data: data)
        #expect(file.text == "hi")
        #expect(file.encoding == .utf8)
        #expect(file.hasBOM == true)
        #expect(file.encoded() == data)
    }

    @Test func decodesUTF16LEWithBOM() throws {
        let data = Data([0xFF, 0xFE]) + "ok".data(using: .utf16LittleEndian)!
        let file = try TextFile(data: data)
        #expect(file.text == "ok")
        #expect(file.encoding == .utf16LittleEndian)
        #expect(file.encoded() == data)
    }

    @Test func fallsBackToWindows1251ForCyrillic() throws {
        let data = "привіт".data(using: .windowsCP1251)!
        let file = try TextFile(data: data)
        #expect(file.text == "привіт")
        #expect(file.encoding == .windowsCP1251)
    }

    @Test func encodingNames() throws {
        #expect(try TextFile(data: Data("x".utf8)).encodingName == "UTF-8")
        #expect(try TextFile(data: Data([0xEF, 0xBB, 0xBF, 0x78])).encodingName == "UTF-8 BOM")
        #expect(try TextFile(data: "ї".data(using: .windowsCP1251)!).encodingName == "Windows-1251")
    }

    @Test func emptyDataIsEmptyUTF8() throws {
        let file = try TextFile(data: Data())
        #expect(file.text == "")
        #expect(file.encoding == .utf8)
    }

    @Test func roundTripsPlainUTF8() throws {
        let data = Data("a\r\nb".utf8)
        #expect(try TextFile(data: data).encoded() == data)
    }

    @Test func detectsLineEndings() {
        #expect(LineEnding.detect(in: "a\nb") == .lf)
        #expect(LineEnding.detect(in: "a\r\nb\r\n") == .crlf)
        #expect(LineEnding.detect(in: "a\rb") == .cr)
        #expect(LineEnding.detect(in: "no breaks") == .lf)
    }

    @Test func convertsLineEndings() {
        #expect(LineEnding.crlf.apply(to: "a\nb\r\nc\rd") == "a\r\nb\r\nc\r\nd")
        #expect(LineEnding.lf.apply(to: "a\r\nb\rc") == "a\nb\nc")
    }

    @Test func textStatsCountsCharactersAndLines() {
        let stats = TextStats(text: "ab\ncd\n")
        #expect(stats.characters == 6)
        #expect(stats.lines == 3)
        #expect(TextStats(text: "").lines == 1)
        #expect(TextStats(text: "x\r\ny").lines == 2)
    }
}
