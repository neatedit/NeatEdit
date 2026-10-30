import Foundation

/// Where a file was left: restored the next time it opens.
public struct FilePosition: Codable, Equatable, Sendable {
    public var location: Int
    public var length: Int
    /// Zero-based line at the top of the view.
    public var topLine: Int
    /// Scrolled to the bottom: comes back at the bottom, however much a log has grown.
    public var atEnd: Bool

    public init(location: Int, length: Int, topLine: Int, atEnd: Bool) {
        self.location = location
        self.length = length
        self.topLine = topLine
        self.atEnd = atEnd
    }

    /// Nothing worth remembering: a file opens like this anyway.
    public var isStart: Bool { location == 0 && length == 0 && topLine == 0 && !atEnd }

    /// The selection in today's text, which may be shorter than it was.
    public func selection(in text: NSString) -> NSRange {
        let location = max(location, 0)
        guard location < text.length else { return NSRange(location: text.length, length: 0) }
        let start = text.rangeOfComposedCharacterSequence(at: location).location
        let fits = length > 0 && length <= text.length - location
        return NSRange(location: start, length: fits ? location + length - start : 0)
    }
}

/// The positions of recently closed files, by path; the oldest are dropped.
public struct FilePositions: Codable, Equatable, Sendable {
    public static let limit = 500

    private struct Entry: Codable, Equatable, Sendable {
        let path: String
        let position: FilePosition
    }

    /// Most recently saved last.
    private var entries: [Entry] = []

    public init() {}

    public var count: Int { entries.count }

    public func position(for path: String) -> FilePosition? {
        entries.last { $0.path == path }?.position
    }

    public mutating func set(_ position: FilePosition, for path: String) {
        entries.removeAll { $0.path == path }
        guard !position.isStart else { return }
        entries.append(Entry(path: path, position: position))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }
}
