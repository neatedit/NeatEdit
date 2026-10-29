import Foundation

/// UTF-16 offsets of every line start, kept in sync with edits so that
/// cursor → line lookups stay O(log n) even for very large documents.
/// Line breaks are LF, CR and CRLF (CRLF counts as a single break).
public struct LineIndex: Sendable {
    public private(set) var starts: [Int]

    public init(_ text: NSString) {
        starts = [0]
        appendStarts(in: text, from: 1, through: text.length)
    }

    public var lineCount: Int { starts.count }

    /// Zero-based line containing `offset`.
    public func line(containing offset: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Length of the longest line in UTF-16 units, line break included,
    /// among lines `firstLine` and later.
    public func longestLine(textLength: Int, from firstLine: Int = 0) -> Int {
        var longest = 0
        for i in min(max(firstLine, 0), starts.count)..<starts.count {
            let end = i + 1 < starts.count ? starts[i + 1] : textLength
            longest = max(longest, end - starts[i])
        }
        return longest
    }

    /// Range of a zero-based line's content, excluding its line break.
    public func contentRange(ofLine line: Int, in text: NSString) -> NSRange {
        let start = starts[line]
        var end = line + 1 < starts.count ? starts[line + 1] : text.length
        if end > start, text.character(at: end - 1) == Self.lf { end -= 1 }
        if end > start, text.character(at: end - 1) == Self.cr { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Apply an edit already performed on `text`. `editedRange` is in the new
    /// text's coordinates, as reported by `NSTextStorage`.
    public mutating func update(in text: NSString, editedRange: NSRange, changeInLength delta: Int) {
        let location = editedRange.location
        let newEnd = editedRange.location + editedRange.length
        let oldEnd = newEnd - delta

        // A start at p depends only on the characters at p-1 and p, so only
        // starts in [location, end] can change.
        let lower = max(location, 1)
        let removeFrom = firstIndex(atLeast: lower)
        let removeTo = firstIndex(atLeast: oldEnd + 1)
        if delta != 0 {
            for i in removeTo..<starts.count { starts[i] += delta }
        }

        var fresh: [Int] = []
        if lower <= newEnd {
            Self.scanStarts(in: text, from: lower, through: min(newEnd, text.length)) { fresh.append($0) }
        }
        starts.replaceSubrange(removeFrom..<max(removeFrom, removeTo), with: fresh)
    }

    private func firstIndex(atLeast value: Int) -> Int {
        var low = 0
        var high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private mutating func appendStarts(in text: NSString, from lower: Int, through upper: Int) {
        guard lower <= upper else { return }
        var collected = starts
        Self.scanStarts(in: text, from: lower, through: upper) { collected.append($0) }
        starts = collected
    }

    private static let lf: unichar = 0x0A
    private static let cr: unichar = 0x0D

    /// Calls `found` for every line start p in [lower, upper], ascending.
    private static func scanStarts(in text: NSString, from lower: Int, through upper: Int, _ found: (Int) -> Void) {
        let length = text.length
        guard lower >= 1, lower <= upper, upper <= length else { return }

        // Read characters p-1 ... upper (plus one lookahead for CRLF) in chunks.
        let chunkSize = 64 * 1024
        var buffer = [unichar](repeating: 0, count: chunkSize + 1)
        var chunkStart = lower - 1
        let scanEnd = min(upper + 1, length)  // exclusive bound of characters to read

        while chunkStart < upper {
            let count = min(chunkSize + 1, scanEnd - chunkStart)
            buffer.withUnsafeMutableBufferPointer { ptr in
                text.getCharacters(ptr.baseAddress!, range: NSRange(location: chunkStart, length: count))
            }
            // i indexes the character before candidate start p = chunkStart + i + 1
            let lastPrev = min(chunkSize, upper - chunkStart) - 1
            if lastPrev >= 0 {
                for i in 0...lastPrev {
                    let c = buffer[i]
                    if c == lf {
                        found(chunkStart + i + 1)
                    } else if c == cr {
                        let next = i + 1 < count ? buffer[i + 1] : 0
                        if chunkStart + i + 1 == length || next != lf {
                            found(chunkStart + i + 1)
                        }
                    }
                }
            }
            chunkStart += chunkSize
        }
    }
}
