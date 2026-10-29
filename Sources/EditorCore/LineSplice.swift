import Foundation

/// Edits a few lines of a file too big to edit whole: the lines are picked
/// from the decoded text, and the edit is written between the file's own
/// untouched bytes before and after them.
public enum LineSplice {
    public struct Chunk: Equatable, Sendable {
        /// Zero-based, inclusive.
        public let firstLine: Int
        public let lastLine: Int
        /// In the decoded text, without the last line's line break.
        public let range: NSRange
        public let text: String
    }

    public enum Failure: Error, Equatable {
        /// The bytes where the lines were are different now: nothing written.
        case changedOnDisk
        /// The new text has characters the file's encoding can't hold.
        case unencodable
        case unsupportedEncoding
    }

    /// The lines the selection touches, with `context` lines on each side.
    public static func chunk(around selection: NSRange, context: Int, in text: NSString, lineIndex: LineIndex) -> Chunk {
        let lastOffset = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        let first = max(lineIndex.line(containing: selection.location) - context, 0)
        let selectedLast = lineIndex.line(containing: lastOffset)
        var last = min(selectedLast + context, lineIndex.lineCount - 1)
        // The empty "line" after a final line break is only taken when it's the one selected.
        if last > selectedLast, lineIndex.starts[last] == text.length { last -= 1 }
        let start = lineIndex.starts[first]
        let end = NSMaxRange(lineIndex.contentRange(ofLine: last, in: text))
        let range = NSRange(location: start, length: end - start)
        return Chunk(firstLine: first, lastLine: last, range: range, text: text.substring(with: range))
    }

    /// Encodings where a character's bytes don't depend on what's around it,
    /// so a byte offset can be counted from the decoded text.
    public static func supports(_ encoding: String.Encoding) -> Bool {
        [.utf8, .utf16LittleEndian, .utf16BigEndian, .ascii, .isoLatin1, .isoLatin2, .macOSRoman,
         .windowsCP1250, .windowsCP1251, .windowsCP1252, .windowsCP1253, .windowsCP1254,
         TextFile.koi8U, TextFile.koi8R].contains(encoding)
    }

    /// Writes `replacement` where `chunk` is in the file at `url`, which
    /// `text` was decoded from. Refuses (and writes nothing) unless the file
    /// still has the chunk's bytes there; text appended since is kept.
    public static func write(
        _ replacement: String, over chunk: Chunk, in text: NSString,
        encoding: String.Encoding, hasBOM: Bool, to url: URL
    ) throws {
        guard supports(encoding) else { throw Failure.unsupportedEncoding }
        guard let expected = chunk.text.data(using: encoding) else { throw Failure.changedOnDisk }
        guard let new = replacement.data(using: encoding) else { throw Failure.unencodable }
        let bom = hasBOM ? (encoding == .utf8 ? 3 : 2) : 0
        guard let before = byteCount(of: NSRange(location: 0, length: chunk.range.location), in: text, encoding: encoding) else {
            throw Failure.changedOnDisk
        }
        let start = UInt64(bom + before)

        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            do {
                try splice(url, at: start, expected: expected, with: new)
            } catch {
                failure = error
            }
        }
        if let error = failure ?? coordinationError { throw error }
    }

    private static func splice(_ url: URL, at start: UInt64, expected: Data, with new: Data) throws {
        let source = try FileHandle(forReadingFrom: url)
        defer { try? source.close() }
        let size = try source.seekToEnd()
        try source.seek(toOffset: start)
        guard start + UInt64(expected.count) <= size, try source.read(upToCount: expected.count) ?? Data() == expected else {
            throw Failure.changedOnDisk
        }

        let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let temp = folder.appendingPathComponent(url.lastPathComponent)
        guard FileManager.default.createFile(atPath: temp.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: temp)
        do {
            try copy(source, from: 0, to: start, into: output)
            try output.write(contentsOf: new)
            // Keep up with a writer appending meanwhile: copy until the size holds.
            var copied = start + UInt64(expected.count)
            var end = size
            while copied < end {
                try copy(source, from: copied, to: end, into: output)
                copied = end
                end = try source.seekToEnd()
            }
            try output.synchronize()
            try output.close()
        } catch {
            try? output.close()
            throw error
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    }

    private static func copy(_ source: FileHandle, from start: UInt64, to end: UInt64, into output: FileHandle) throws {
        try source.seek(toOffset: start)
        var left = end - start
        while left > 0 {
            let block = try source.read(upToCount: Int(min(left, 4 << 20))) ?? Data()
            guard !block.isEmpty else { throw Failure.changedOnDisk }
            try output.write(contentsOf: block)
            left -= UInt64(block.count)
        }
    }

    /// Bytes `range` of `text` takes in `encoding`, counted without copying it.
    static func byteCount(of range: NSRange, in text: NSString, encoding: String.Encoding) -> Int? {
        guard range.length > 0 else { return 0 }
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
        var used: CFIndex = 0
        let converted = CFStringGetBytes(text as CFString, CFRange(location: range.location, length: range.length),
                                         cfEncoding, 0, false, nil, 0, &used)
        return converted == range.length ? used : nil
    }
}
