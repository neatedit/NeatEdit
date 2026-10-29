import Foundation

/// Follows a file that grows at the end (a log being written): remembers
/// how much of it is known and turns only the bytes added since into text,
/// so a write to a 500 MB log costs what was written, not 500 MB.
public struct FileTail: Sendable {
    public enum Change: Equatable, Sendable {
        case unchanged
        case appended(String)
        /// Shrunk, or the known part changed (rotated, rewritten): read it all again.
        case rewritten
    }

    /// Bytes of the file accounted for, including `pending`.
    public private(set) var byteCount: Int
    /// The last known bytes: if they're still there, the file only grew.
    private var sample: Data
    /// The start of a character whose remaining bytes haven't been written yet.
    private var pending = Data()
    private let encoding: String.Encoding

    static let sampleSize = 4096

    /// Nil for encodings where a byte offset may split a code unit (UTF-16/32).
    public init?(data: Data, encoding: String.Encoding) {
        guard encoding == .utf8 || Self.singleByte.contains(encoding) else { return nil }
        self.encoding = encoding
        byteCount = data.count
        sample = Data(data.suffix(Self.sampleSize))
    }

    private static let singleByte: [String.Encoding] = [
        .ascii, .isoLatin1, .isoLatin2, .macOSRoman,
        .windowsCP1250, .windowsCP1251, .windowsCP1252, .windowsCP1253, .windowsCP1254,
    ]

    /// `size` is the file's current length; `read` returns its bytes in a range.
    public mutating func update(size: Int, read: (Range<Int>) throws -> Data) rethrows -> Change {
        guard size >= byteCount else { return .rewritten }
        guard try read(byteCount - sample.count..<byteCount) == sample else { return .rewritten }
        guard size > byteCount else { return .unchanged }

        let chunk = try read(byteCount..<size)
        let bytes = pending + chunk
        let complete = encoding == .utf8 ? Self.completeUTF8Prefix(bytes) : bytes.count
        guard let text = String(data: bytes.prefix(complete), encoding: encoding) else { return .rewritten }

        byteCount += chunk.count
        sample = Data((sample + chunk).suffix(Self.sampleSize))
        pending = Data(bytes.suffix(from: bytes.startIndex + complete))
        return text.isEmpty ? .unchanged : .appended(text)
    }

    /// Length of `bytes` without a trailing, unfinished UTF-8 sequence.
    static func completeUTF8Prefix(_ bytes: Data) -> Int {
        let start = bytes.startIndex
        var lead = bytes.endIndex
        // A sequence is at most 4 bytes: find the last byte that starts one.
        while lead > max(start, bytes.endIndex - 4) {
            lead -= 1
            if bytes[lead] & 0xC0 != 0x80 { break }
        }
        guard lead < bytes.endIndex else { return bytes.count }
        let first = bytes[lead]
        let needed = first < 0x80 ? 1 : first >= 0xF0 ? 4 : first >= 0xE0 ? 3 : first >= 0xC0 ? 2 : 1
        return bytes.endIndex - lead < needed ? lead - start : bytes.count
    }
}
