import Foundation

/// What the status bar shows about the caret. Counts are user-perceived
/// characters (an emoji or CRLF is one character), 1-based for line/column.
public struct CursorPosition: Equatable, Sendable {
    public var line: Int
    public var column: Int
    /// Characters from the start of the document.
    public var offset: Int
    /// Characters in the current line, excluding the line break.
    public var lineLength: Int
    /// True when a span was too long to count characters exactly and UTF-16
    /// units were reported instead (only happens in huge documents/lines).
    public var isApproximate: Bool

    /// Spans longer than this many UTF-16 units are not counted character by
    /// character, keeping caret movement instant in multi-hundred-MB files.
    public static let defaultExactCountLimit = 1_000_000

    public init(
        in text: NSString,
        utf16Offset: Int,
        lineIndex: LineIndex,
        exactCountLimit: Int = CursorPosition.defaultExactCountLimit
    ) {
        let caret = min(max(utf16Offset, 0), text.length)
        let lineNumber = lineIndex.line(containing: caret)
        let content = lineIndex.contentRange(ofLine: lineNumber, in: text)
        let lineStart = content.location

        var approximate = false
        func count(_ range: NSRange) -> Int {
            if range.length == 0 { return 0 }
            if range.length > exactCountLimit {
                approximate = true
                return range.length
            }
            return text.substring(with: range).count
        }

        line = lineNumber + 1
        column = count(NSRange(location: lineStart, length: caret - lineStart)) + 1
        offset = count(NSRange(location: 0, length: caret))
        lineLength = count(NSRange(location: lineStart, length: content.length))
        isApproximate = approximate
    }

    public init(in text: String, utf16Offset: Int) {
        let ns = text as NSString
        self.init(in: ns, utf16Offset: utf16Offset, lineIndex: LineIndex(ns))
    }
}
