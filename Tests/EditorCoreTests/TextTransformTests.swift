import Foundation
import Testing
@testable import EditorCore

struct TextTransformTests {
    private func apply(_ transform: TextTransform, _ text: String) throws -> String {
        try transform.apply(to: text)
    }

    // MARK: Case

    @Test func changesCase() throws {
        #expect(try apply(.uppercase, "Привіт, world") == "ПРИВІТ, WORLD")
        #expect(try apply(.lowercase, "Привіт, WORLD") == "привіт, world")
        #expect(try apply(.titleCase, "hello wORLD, привіт світ") == "Hello World, Привіт Світ")
    }

    // MARK: Lines

    @Test func sortsLinesNaturally() throws {
        #expect(try apply(.sortLines, "file10\nFile2\nfile1\nbanana") == "banana\nfile1\nFile2\nfile10")
    }

    @Test func removesDuplicateLinesKeepingTheFirst() throws {
        #expect(try apply(.removeDuplicateLines, "b\na\nb\nc\na\nb") == "b\na\nc")
        #expect(try apply(.removeDuplicateLines, "a\nA\na ") == "a\nA\na ")
    }

    @Test func removesEmptyAndBlankLines() throws {
        #expect(try apply(.removeEmptyLines, "a\n\n  \n\tb\n\t\nc") == "a\n\tb\nc")
    }

    @Test func trimsTrailingWhitespace() throws {
        #expect(try apply(.trimTrailingWhitespace, "a  \n  b\t\n\nc \t ") == "a\n  b\n\nc")
    }

    @Test func joinsLinesWithSingleSpaces() throws {
        #expect(try apply(.joinLines, "first  \n   second\n\n\tthird") == "first second third")
        #expect(try apply(.joinLines, "  indented\nnext") == "  indented next")
    }

    @Test func expandsTabsToTabStops() throws {
        #expect(try TextTransform.tabsToSpaces.apply(to: "\ta\tb\nab\tc", tabWidth: 4) == "    a   b\nab  c")
    }

    @Test func convertsLeadingSpacesToTabs() throws {
        #expect(try TextTransform.spacesToTabs.apply(to: "        a  b\n      c\n \td", tabWidth: 4) == "\t\ta  b\n\t  c\n\td")
    }

    // MARK: JSON

    @Test func formatsJSONKeepingKeyOrderAndNumbers() throws {
        let json = #"{"z":1.50,"a":[1,2,{}],"s":"x, y: {\"q\"}","e":[]}"#
        #expect(try apply(.formatJSON, json) == """
            {
              "z": 1.50,
              "a": [
                1,
                2,
                {}
              ],
              "s": "x, y: {\\"q\\"}",
              "e": []
            }
            """)
    }

    @Test func minifiesJSON() throws {
        let json = """
            {
              "a" : [ 1, 2 ],
              "s": "keep  spaces"
            }
            """
        #expect(try apply(.minifyJSON, json) == #"{"a":[1,2],"s":"keep  spaces"}"#)
    }

    @Test func jsonKeepsSurroundingWhitespace() throws {
        #expect(try apply(.minifyJSON, "\n  [1, 2]\n") == "\n  [1,2]\n")
    }

    @Test func invalidJSONThrows() {
        #expect(throws: TextTransform.Failure.self) { try apply(.formatJSON, "{a: 1}") }
        #expect(throws: TextTransform.Failure.self) { try apply(.minifyJSON, "") }
    }

    // MARK: Base64 and URL

    @Test func base64RoundTrips() throws {
        #expect(try apply(.base64Encode, "Привіт") == "0J/RgNC40LLRltGC")
        #expect(try apply(.base64Decode, "0J/RgNC40LLRltGC") == "Привіт")
    }

    @Test func base64KeepsSurroundingWhitespace() throws {
        #expect(try apply(.base64Encode, "hello\n") == "aGVsbG8=\n")
    }

    @Test func base64DecodeAcceptsWrappedURLSafeAndUnpadded() throws {
        #expect(try apply(.base64Decode, "aGVs\nbG8") == "hello")
        #expect(try apply(.base64Decode, "Pz8_") == "???")
    }

    @Test func base64DecodeRejectsGarbageAndBinary() {
        #expect(throws: TextTransform.Failure.self) { try apply(.base64Decode, "not base64!") }
        #expect(throws: TextTransform.Failure.self) { try apply(.base64Decode, "/w==") }  // 0xFF
    }

    @Test func urlEncodesEverythingButUnreserved() throws {
        #expect(try apply(.urlEncode, "a b&c=д/~._-") == "a%20b%26c%3D%D0%B4%2F~._-")
    }

    @Test func urlDecodes() throws {
        #expect(try apply(.urlDecode, "a%20b%26c%3D%D0%B4+x") == "a b&c=д+x")
        #expect(throws: TextTransform.Failure.self) { try apply(.urlDecode, "100%") }
    }

    @Test func lineTransformsSayTheyWorkOnWholeLines() {
        #expect(TextTransform.sortLines.worksOnWholeLines)
        #expect(TextTransform.spacesToTabs.worksOnWholeLines)
        #expect(!TextTransform.uppercase.worksOnWholeLines)
        #expect(!TextTransform.formatJSON.worksOnWholeLines)
    }
}
