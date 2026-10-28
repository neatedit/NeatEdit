import Foundation

/// Caret movement over UTF-16 offsets that never splits a character
/// (emoji, CRLF) and never scans more than the lines involved.
public struct TextNavigator {
    public let text: NSString
    public let lineIndex: LineIndex

    public init(text: NSString, lineIndex: LineIndex) {
        self.text = text
        self.lineIndex = lineIndex
    }

    public func snap(_ offset: Int) -> Int {
        let clamped = min(max(offset, 0), text.length)
        guard clamped < text.length else { return clamped }
        if isCRLF(at: clamped - 1) { return clamped - 1 }
        return text.rangeOfComposedCharacterSequence(at: clamped).location
    }

    public func right(from offset: Int) -> Int {
        let start = snap(offset)
        guard start < text.length else { return start }
        if isCRLF(at: start) { return start + 2 }
        return NSMaxRange(text.rangeOfComposedCharacterSequence(at: start))
    }

    public func left(from offset: Int) -> Int {
        let start = snap(offset)
        guard start > 0 else { return 0 }
        if isCRLF(at: start - 2) { return start - 2 }
        return text.rangeOfComposedCharacterSequence(at: start - 1).location
    }

    /// NSString treats CR and LF as separate characters; users don't.
    private func isCRLF(at index: Int) -> Bool {
        index >= 0 && index + 1 < text.length
            && text.character(at: index) == 0x0D && text.character(at: index + 1) == 0x0A
    }

    /// Move `lines` up (negative) or down, landing at `preferredColumn`
    /// (UTF-16 units) or the end of a shorter line. Past either end of the
    /// document it goes to the very start/end, like NSTextView.
    public func vertical(from offset: Int, lines: Int, preferredColumn: Int) -> Int {
        let current = lineIndex.line(containing: offset)
        let target = current + lines
        if target < 0 { return 0 }
        if target >= lineIndex.lineCount { return text.length }
        let content = lineIndex.contentRange(ofLine: target, in: text)
        return snap(content.location + min(preferredColumn, content.length))
    }

    public func lineStart(of offset: Int) -> Int {
        lineIndex.starts[lineIndex.line(containing: offset)]
    }

    public func lineEnd(of offset: Int) -> Int {
        NSMaxRange(lineIndex.contentRange(ofLine: lineIndex.line(containing: offset), in: text))
    }

    /// The whole line including its line break.
    public func lineRange(of offset: Int) -> NSRange {
        let line = lineIndex.line(containing: offset)
        let start = lineIndex.starts[line]
        let end = line + 1 < lineIndex.lineCount ? lineIndex.starts[line + 1] : text.length
        return NSRange(location: start, length: end - start)
    }

    /// Word under `offset` (for double-click), or the single character there.
    public func word(at offset: Int) -> NSRange {
        let content = lineIndex.contentRange(ofLine: lineIndex.line(containing: offset), in: text)
        var found: NSRange?
        text.enumerateSubstrings(in: content, options: [.byWords, .substringNotRequired]) { _, range, _, stop in
            if range.location <= offset, offset < NSMaxRange(range) {
                found = range
                stop.pointee = true
            } else if range.location > offset {
                stop.pointee = true
            }
        }
        if let found { return found }
        guard offset < NSMaxRange(content) else { return NSRange(location: offset, length: 0) }
        return text.rangeOfComposedCharacterSequence(at: offset)
    }
}
