import Foundation

/// "Go to line" target typed as `line`, `line:column` or `line,column` (1-based).
public struct GoToLine: Equatable, Sendable {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public static func parse(_ input: String) -> GoToLine? {
        let parts = input.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == ":" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard (1...2).contains(parts.count),
              let line = Int(parts[0]), line >= 1 else { return nil }
        let column = parts.count == 2 ? Int(parts[1]) : 1
        guard let column, column >= 1 else { return nil }
        return GoToLine(line: line, column: column)
    }

    /// UTF-16 offset of the target, clamped to the last line and to the
    /// end of the line's content.
    public func offset(in text: NSString, lineIndex: LineIndex) -> Int {
        let lineNumber = min(line, lineIndex.lineCount) - 1
        let content = lineIndex.contentRange(ofLine: lineNumber, in: text)
        let start = content.location
        let end = NSMaxRange(content)

        var offset = start
        var remaining = column - 1
        while remaining > 0, offset < end {
            offset = NSMaxRange(text.rangeOfComposedCharacterSequence(at: offset))
            remaining -= 1
        }
        return min(offset, end)
    }
}
