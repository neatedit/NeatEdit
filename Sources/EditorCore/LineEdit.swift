import Foundation

/// Line commands (duplicate, move up / down) as one replacement plus the
/// selection to show afterwards. Line breaks stay where they were: moving
/// the last line, which has none, doesn't glue two lines together.
public struct LineEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange

    /// No selection, or one across lines: the lines are copied below.
    /// A selection within a line is copied right after itself.
    public static func duplicate(in text: NSString, selection: NSRange) -> LineEdit {
        if selection.length > 0, !text.substring(with: selection).contains(where: \.isNewline) {
            let copy = text.substring(with: selection)
            return LineEdit(range: NSRange(location: NSMaxRange(selection), length: 0), replacement: copy,
                            selection: NSRange(location: NSMaxRange(selection), length: selection.length))
        }
        let block = Block(text, selection)
        let insert: String
        if block.terminator.isEmpty {
            // The last line: borrow the previous line's break, if there is one.
            let previous = block.start > 0 ? Block(text, NSRange(location: block.start - 1, length: 0)).terminator : ""
            insert = (previous.isEmpty ? "\n" : previous) + block.body
        } else {
            insert = block.body + block.terminator
        }
        let shift = (insert as NSString).length
        return LineEdit(range: NSRange(location: block.end, length: 0), replacement: insert,
                        selection: NSRange(location: selection.location + shift, length: selection.length))
    }

    public static func moveUp(in text: NSString, selection: NSRange) -> LineEdit? {
        let block = Block(text, selection)
        guard block.start > 0 else { return nil }
        let above = Block(text, NSRange(location: block.start - 1, length: 0))
        return LineEdit(range: NSRange(location: above.start, length: block.end - above.start),
                        replacement: block.body + above.terminator + above.body + block.terminator,
                        selection: NSRange(location: selection.location - block.start + above.start, length: selection.length))
    }

    public static func moveDown(in text: NSString, selection: NSRange) -> LineEdit? {
        let block = Block(text, selection)
        guard !block.terminator.isEmpty, block.end < text.length else { return nil }
        let below = Block(text, NSRange(location: block.end, length: 0))
        let newStart = block.start + (below.body as NSString).length + (block.terminator as NSString).length
        return LineEdit(range: NSRange(location: block.start, length: below.end - block.start),
                        replacement: below.body + block.terminator + block.body + below.terminator,
                        selection: NSRange(location: selection.location - block.start + newStart, length: selection.length))
    }

    /// The whole lines a selection touches; one ending right after a line
    /// break stops at that line.
    private struct Block {
        let start: Int
        let end: Int
        let body: String
        let terminator: String

        init(_ text: NSString, _ selection: NSRange) {
            let last = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
            var start = 0, end = 0, contentsEnd = 0
            text.getLineStart(&start, end: nil, contentsEnd: nil, for: NSRange(location: selection.location, length: 0))
            text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: last, length: 0))
            self.start = start
            self.end = end
            body = text.substring(with: NSRange(location: start, length: contentsEnd - start))
            terminator = text.substring(with: NSRange(location: contentsEnd, length: end - contentsEnd))
        }
    }
}
