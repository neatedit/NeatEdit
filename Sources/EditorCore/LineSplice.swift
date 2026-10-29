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
        /// Where the chunk starts in the file, counted when it was picked from
        /// the text it came from. Nil for encodings that can't be counted.
        public let byteOffset: UInt64?
        public let encoding: String.Encoding
    }

    public enum Failure: Error, Equatable {
        /// The bytes where the lines were are different now: nothing written.
        case changedOnDisk
        /// The new text has characters the file's encoding can't hold.
        case unencodable
        case unsupportedEncoding
    }

    /// The lines the selection touches, with `context` lines on each side.
    public static func chunk(
        around selection: NSRange, context: Int, in text: NSString, lineIndex: LineIndex,
        encoding: String.Encoding = .utf8, hasBOM: Bool = false
    ) -> Chunk {
        let lastOffset = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        let first = max(lineIndex.line(containing: selection.location) - context, 0)
        let selectedLast = lineIndex.line(containing: lastOffset)
        var last = min(selectedLast + context, lineIndex.lineCount - 1)
        // The empty "line" after a final line break is only taken when it's the one selected.
        if last > selectedLast, lineIndex.starts[last] == text.length { last -= 1 }
        let start = lineIndex.starts[first]
        let end = NSMaxRange(lineIndex.contentRange(ofLine: last, in: text))
        let range = NSRange(location: start, length: end - start)
        let bom = hasBOM ? (encoding == .utf8 ? 3 : 2) : 0
        let offset = supports(encoding)
            ? byteCount(of: NSRange(location: 0, length: start), in: text, encoding: encoding).map { UInt64(bom + $0) }
            : nil
        return Chunk(firstLine: first, lastLine: last, range: range, text: text.substring(with: range),
                     byteOffset: offset, encoding: encoding)
    }

    /// Return in a text view types LF. When the chunk's own line breaks are
    /// all CRLF (or all CR), the LFs that came in that way get the same
    /// break; anything else in the text, lone CRs included, is left exactly
    /// as it is, so unedited lines never change.
    public static func matchingLineBreaks(_ edited: String, original: String) -> String {
        let text = original as NSString
        let hasCRLF = text.range(of: "\r\n").location != NSNotFound
        let bareLF = original.replacingOccurrences(of: "\r\n", with: "").contains("\n")
        let target: String
        if hasCRLF, !bareLF {
            target = "\r\n"
        } else if !hasCRLF, !bareLF, original.contains("\r") {
            target = "\r"
        } else {
            return edited
        }
        var result = ""
        var previous: Character?
        for character in edited {
            // "\r\n" is one Character in Swift; a lone "\n" is a typed break.
            result += character == "\n" && previous != "\r" ? target : String(character)
            previous = character
        }
        return result
    }

    /// Encodings where a character's bytes don't depend on what's around it,
    /// so a byte offset can be counted from the decoded text.
    public static func supports(_ encoding: String.Encoding) -> Bool {
        [.utf8, .utf16LittleEndian, .utf16BigEndian, .ascii, .isoLatin1, .isoLatin2, .macOSRoman,
         .windowsCP1250, .windowsCP1251, .windowsCP1252, .windowsCP1253, .windowsCP1254,
         TextFile.koi8U, TextFile.koi8R].contains(encoding)
    }

    /// Writes `replacement` where `chunk` is in the file at `url`. Refuses
    /// (and writes nothing) unless the file still has the chunk's bytes there.
    ///
    /// The same number of bytes is written in place: no new file, so a program
    /// holding the file open (a logger) and hard links keep seeing it. A
    /// different length copies the bytes around the chunk into a replacement
    /// file, keeping what was appended up to the moment of the swap; a writer
    /// with the file still open keeps writing to the old copy.
    public static func write(_ replacement: String, over chunk: Chunk, to url: URL) throws {
        guard let start = chunk.byteOffset, let expected = chunk.text.data(using: chunk.encoding) else {
            throw Failure.unsupportedEncoding
        }
        guard let new = replacement.data(using: chunk.encoding) else { throw Failure.unencodable }
        let url = url.resolvingSymlinksInPath()

        var failure: Error?
        var coordinationError: NSError?
        let options: NSFileCoordinator.WritingOptions = new.count == expected.count ? [] : .forReplacing
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options, error: &coordinationError) { url in
            do {
                if new.count == expected.count {
                    try overwrite(url, at: start, expected: expected, with: new)
                } else {
                    try splice(url, at: start, expected: expected, with: new)
                }
            } catch {
                failure = error
            }
        }
        if let error = failure ?? coordinationError { throw error }
    }

    private static func verify(_ handle: FileHandle, at start: UInt64, expected: Data) throws -> UInt64 {
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: start)
        guard start + UInt64(expected.count) <= size, try handle.read(upToCount: expected.count) ?? Data() == expected else {
            throw Failure.changedOnDisk
        }
        return size
    }

    private static func overwrite(_ url: URL, at start: UInt64, expected: Data, with new: Data) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        _ = try verify(handle, at: start, expected: expected)
        try handle.seek(toOffset: start)
        try handle.write(contentsOf: new)
        try handle.synchronize()
    }

    private static func splice(_ url: URL, at start: UInt64, expected: Data, with new: Data) throws {
        let source = try FileHandle(forReadingFrom: url)
        defer { try? source.close() }
        let size = try verify(source, at: start, expected: expected)

        let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let temp = folder.appendingPathComponent(url.lastPathComponent)
        guard FileManager.default.createFile(atPath: temp.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: temp)
        do {
            try copy(source, from: 0, to: start, into: output)
            try output.write(contentsOf: new)
            // Keep up with a writer appending meanwhile, including during the
            // flush to disk, so the window before the swap stays tiny.
            var copied = start + UInt64(expected.count)
            var end = size
            while true {
                try copy(source, from: copied, to: end, into: output)
                copied = end
                try output.synchronize()
                end = try source.seekToEnd()
                // Shrunk (truncated, rotated): putting old bytes back would be wrong.
                guard end >= copied else { throw Failure.changedOnDisk }
                if end == copied { break }
            }
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
        guard range.location >= 0, NSMaxRange(range) <= text.length else { return nil }
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
        var used: CFIndex = 0
        let converted = CFStringGetBytes(text as CFString, CFRange(location: range.location, length: range.length),
                                         cfEncoding, 0, false, nil, 0, &used)
        return converted == range.length ? used : nil
    }
}
