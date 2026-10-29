import AppKit
import EditorCore

/// The text of one document plus everything derived from it: the line index
/// (kept in sync on every edit) and the totals shown in the status bar.
public final class EditorModel: NSObject, NSTextStorageDelegate {
    public let storage: NSTextStorage
    public private(set) var lineIndex: LineIndex
    /// Encoding and BOM of the file on disk. `file.text` is not kept — the
    /// storage is the single copy of the text.
    public private(set) var file: TextFile
    public var lineEnding: LineEnding

    /// Called on the main thread when totals finished counting in the background.
    public var onTotalsChanged: (() -> Void)?

    private var totalCharacters: CharacterCount?
    private var countGeneration = 0
    private var countWork: DispatchWorkItem?
    /// Characters appended since the background count took its snapshot, so
    /// a followed log doesn't restart (and starve) it. Nil when no count is
    /// running, or something other than an append changed the text.
    private var appendedDuringCount: Int?
    private var isAppending = false
    /// Bumped by every change except an append from disk, so a disk read can
    /// tell whether the text changed while it was in flight.
    public private(set) var editCount = 0

    /// Documents up to this many UTF-16 units are counted synchronously.
    static let syncCountLimit = 1_000_000

    /// Heavy lifting that's safe off the main thread: decoding, building the
    /// storage and the line index.
    public struct Prepared: @unchecked Sendable {
        let storage: NSTextStorage
        let lineIndex: LineIndex
        let file: TextFile
        let lineEnding: LineEnding
    }

    public static func prepare(_ file: TextFile) -> Prepared {
        var meta = file
        meta.text = ""
        let storage = NSTextStorage(string: file.text, attributes: [.font: Preferences.font])
        return Prepared(
            storage: storage,
            lineIndex: LineIndex(storage.string as NSString),
            file: meta,
            lineEnding: LineEnding.detect(in: file.text)
        )
    }

    public static func prepare(data: Data) throws -> Prepared {
        try prepare(TextFile(data: data))
    }

    public init(prepared: Prepared) {
        storage = prepared.storage
        lineIndex = prepared.lineIndex
        file = prepared.file
        lineEnding = prepared.lineEnding
        super.init()
        storage.delegate = self
    }

    public convenience init(file: TextFile) {
        self.init(prepared: Self.prepare(file))
    }

    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        lineIndex.update(in: textStorage.string as NSString, editedRange: editedRange, changeInLength: delta)
        guard !isAppending else { return }
        editCount += 1
        totalCharacters = nil
        appendedDuringCount = nil
    }

    /// Adds text at the end (a log being written), updating the totals
    /// without counting the whole document again.
    public func append(_ text: String) {
        guard !text.isEmpty else { return }
        let length = storage.length
        // The last character may absorb the start of the new text (CR + LF,
        // an accent, half an emoji): count them together.
        let current = storage.string as NSString
        let last = length > 0 ? current.substring(with: current.rangeOfComposedCharacterSequence(at: length - 1)) : ""
        let added = (last + text).count - (last.isEmpty ? 0 : 1)
        isAppending = true
        storage.append(NSAttributedString(string: text, attributes: [.font: Preferences.font]))
        isAppending = false
        if let total = totalCharacters {
            totalCharacters = CharacterCount(value: total.value + added, isApproximate: total.isApproximate)
        } else if let counted = appendedDuringCount {
            appendedDuringCount = counted + added
        }
    }

    public func status(selectedRange: NSRange) -> StatusLine {
        let text = storage.string as NSString
        let selection = selectedRange.length > 0 ? CharacterCount(in: text, range: selectedRange) : nil
        return StatusLine(
            position: CursorPosition(in: text, utf16Offset: selectedRange.location, lineIndex: lineIndex),
            selection: selection,
            totalCharacters: totals(),
            lines: lineIndex.lineCount,
            encoding: file.encodingName,
            lineEnding: lineEnding
        )
    }

    /// Exact totals: immediately for normal documents, in the background
    /// (debounced while typing) for huge ones. Nil while counting.
    private func totals() -> CharacterCount? {
        if let totalCharacters { return totalCharacters }
        let length = storage.length
        if length <= Self.syncCountLimit {
            let count = CharacterCount(in: storage.string as NSString, range: NSRange(location: 0, length: length), exactLimit: .max)
            totalCharacters = count
            return count
        }
        // A count is already on its way and appends are being added to it.
        if appendedDuringCount != nil { return nil }
        scheduleBackgroundCount()
        return nil
    }

    private func scheduleBackgroundCount() {
        countWork?.cancel()
        countGeneration += 1
        let generation = countGeneration
        appendedDuringCount = 0
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.countGeneration, self.appendedDuringCount != nil else { return }
            // Appends until now are in the snapshot; later ones are added on top.
            self.appendedDuringCount = 0
            let snapshot = (self.storage.string as NSString).copy() as! NSString
            DispatchQueue.global(qos: .utility).async {
                let count = (snapshot as String).count
                DispatchQueue.main.async {
                    guard generation == self.countGeneration, let appended = self.appendedDuringCount else { return }
                    self.appendedDuringCount = nil
                    self.totalCharacters = CharacterCount(value: count + appended, isApproximate: false)
                    self.onTotalsChanged?()
                }
            }
        }
        countWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Takes encoding and BOM from `file` (its text is ignored).
    public func adoptFormat(of file: TextFile) {
        self.file.encoding = file.encoding
        self.file.hasBOM = file.hasBOM
    }

    /// Encoding for the next save. UTF-16 always gets a BOM so it can be
    /// recognized when the file is opened again.
    public func setEncoding(_ encoding: String.Encoding) {
        file.encoding = encoding
        file.hasBOM = encoding == .utf16LittleEndian || encoding == .utf16BigEndian
    }

    /// Bytes to write: original encoding, BOM and line endings. Falls back to
    /// UTF-8 when the text gained characters the original encoding can't hold.
    public func encodedData() throws -> Data {
        let text = lineEnding == .lf ? storage.string : lineEnding.apply(to: storage.string)
        let candidate = TextFile(text: text, encoding: file.encoding, hasBOM: file.hasBOM)
        if let data = candidate.encoded() { return data }
        file.encoding = .utf8
        file.hasBOM = false
        guard let data = TextFile(text: text).encoded() else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }
}
