import AppKit
import EditorCore

public final class TextDocument: NSDocument {
    private var model: EditorModel?
    /// Set by `read` (possibly on a background thread), consumed on main.
    private var prepared: EditorModel.Prepared?
    private let preparedLock = NSLock()

    /// What happened to the file on disk that the user hasn't dealt with yet.
    enum ExternalState {
        case none
        /// Changed while the tab had unsaved edits; `disk` is the new file.
        case changed(ExternalMerge, disk: TextFile)
        /// Changed; a big document is still being diffed. Saves are already blocked.
        case checking(disk: TextFile)
        case deleted
    }

    private(set) var externalState = ExternalState.none {
        didSet {
            for controller in windowControllers {
                (controller.contentViewController as? DocumentContent)?.externalStateDidChange(externalState)
            }
        }
    }

    /// The text as last loaded or saved, LF line endings: what external
    /// changes are diffed against. Not kept for the read-only viewer.
    private(set) var baseText = ""
    private var diskCheck: DispatchWorkItem?
    /// Tabs watch their file directly: file presenter news arrives late
    /// (~1 s) and merged, too slow to follow a log.
    private var appendWatcher: DispatchSourceFileSystemObject?
    /// Modification date of the disk version behind `externalState`.
    private var pendingDiskDate: Date?
    /// Bumped by every completed save: a disk read started before it may
    /// have seen the file before our own write, so its result is stale.
    private(set) var diskReadStamp = 0
    /// Edited documents longer than this (UTF-16 units) are diffed in the background.
    static var syncMergeLimit = 1_000_000
    private var mergeInFlight = false
    private var queuedMergeDisk: TextFile?
    /// Bumped whenever the pending state is resolved or reset, so results of
    /// merges started before that are dropped.
    private var stateEpoch = 0
    /// Set when the tab is built; see `isViewer`.
    private var opensInViewer: Bool?
    /// How far the viewer has read the file, so appends are read alone.
    /// Nil for encodings it can't follow (the whole file is read again).
    /// Editor tabs (under 20 MB) always read the whole file: only that tells
    /// an append from a rewrite that happens to grow it.
    private var tail: FileTail?
    /// From `read`, possibly on a background thread; taken with `prepared`.
    private var preparedTail: FileTail?

    /// Documents longer than this (UTF-16 units, ~20 MB of text) open in the
    /// read-only viewer, which stays instant no matter the size.
    static var largeFileThreshold = 20_000_000

    override public class var autosavesInPlace: Bool { true }

    /// Lets big files load off the main thread so the app stays responsive.
    override public class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }

    override public func read(from data: Data, ofType typeName: String) throws {
        let prepared = try EditorModel.prepare(data: data)
        let tail = FileTail(data: data, encoding: prepared.file.encoding)
        preparedLock.withLock {
            self.prepared = prepared
            self.preparedTail = tail
        }
        if model != nil {
            // Revert or external change: swap the text in the open tab.
            if Thread.isMainThread {
                applyPrepared()
            } else {
                DispatchQueue.main.async { self.applyPrepared() }
            }
        }
    }

    override public func data(ofType typeName: String) throws -> Data {
        try currentModel().encodedData()
    }

    override public func save(
        to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // Never write over a disk change the user hasn't seen.
        if hasUnresolvedDiskChange, Self.sameFile(url, fileURL) {
            switch saveOperation {
            case .saveOperation, .saveAsOperation, .saveToOperation:
                DispatchQueue.main.async { self.showExternalChangeResolution() }
                return completionHandler(CocoaError(.userCancelled))
            case .autosaveInPlaceOperation:
                return completionHandler(unresolvedChangeError())
            default:
                break
            }
        }
        // What lands on disk becomes the new base, unless it went to another file.
        let snapshot = saveOperation == .saveToOperation ? nil : model.map { Self.normalized($0.storage.string) }
        saveInFlight += 1
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            self?.saveInFlight -= 1
            if error == nil, saveOperation != .saveToOperation, let self {
                self.diskReadStamp += 1
                if let snapshot, !self.isViewer { self.baseText = snapshot }
                self.savedOverExternalState()
            }
            completionHandler(error)
        }
    }

    /// After a save: a pending change from before the save is resolved (we
    /// saved over it or moved away), but one that arrived during the save is
    /// re-diffed against what we just wrote and stays pending.
    private func savedOverExternalState() {
        switch externalState {
        case .changed(_, let disk) where pendingArrivedDuringSave, .checking(let disk) where pendingArrivedDuringSave:
            if Self.normalized(disk.text) == baseText {
                resetExternalState()
            } else if let model {
                externalState = .changed(ExternalMerge(base: baseText, mine: model.storage.string, disk: disk.text), disk: disk)
            }
        default:
            resetExternalState()
        }
        pendingArrivedDuringSave = false
    }

    /// Periodic autosaves skip quietly; the one before closing or quitting
    /// fails with an explanation, so neither version is dropped.
    override public func autosave(withImplicitCancellability autosavingIsImplicitlyCancellable: Bool, completionHandler: @escaping (Error?) -> Void) {
        guard hasUnresolvedDiskChange else {
            return super.autosave(withImplicitCancellability: autosavingIsImplicitlyCancellable, completionHandler: completionHandler)
        }
        completionHandler(autosavingIsImplicitlyCancellable ? CocoaError(.userCancelled) : unresolvedChangeError())
    }

    private var pendingArrivedDuringSave = false
    private var saveInFlight = 0

    private static func sameFile(_ a: URL?, _ b: URL?) -> Bool {
        guard let a, let b else { return false }
        return a.standardizedFileURL.resolvingSymlinksInPath() == b.standardizedFileURL.resolvingSymlinksInPath()
    }

    private var hasUnresolvedDiskChange: Bool {
        switch externalState {
        case .changed, .checking: return true
        case .none, .deleted: return false
        }
    }

    private func unresolvedChangeError() -> Error {
        NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue, userInfo: [
            NSLocalizedDescriptionKey: L10n.tr("“%@” changed on disk while it had unsaved changes.", displayName ?? L10n.tr("This document")),
            NSLocalizedRecoverySuggestionErrorKey: L10n.tr("Review the changes or dismiss them first, so neither version is lost."),
        ])
    }

    private func showExternalChangeResolution() {
        for controller in windowControllers {
            (controller.contentViewController as? EditorViewController)?.resolveExternalChange()
        }
    }

    override public func makeWindowControllers() {
        let model = currentModel()
        opensInViewer = model.storage.length > Self.largeFileThreshold
        let controller: NSViewController = opensInViewer == true
            ? LargeFileViewController(model: model)
            : EditorViewController(model: model)
        let window = NSWindow(contentViewController: controller)
        window.subtitle = Self.subtitle(for: fileURL, home: Self.homeDirectory, viewer: opensInViewer == true)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "NeatEdit"
        window.setContentSize(NSSize(width: 800, height: 600))
        let windowController = NSWindowController(window: window)
        windowController.windowFrameAutosaveName = "EditorWindow"
        windowController.shouldCascadeWindows = true
        addWindowController(windowController)
        if let fileURL { (controller as? DocumentContent)?.pendingPosition = Preferences.filePosition(for: fileURL) }
        watchForAppends()
    }

    // Closing a window takes its controller off before close() runs.
    override public func removeWindowController(_ windowController: NSWindowController) {
        savePosition()
        super.removeWindowController(windowController)
    }

    /// Remembers where the file is, for the next time it opens. A tab that
    /// never appeared is still where it was left.
    func savePosition() {
        guard let fileURL, let content = windowControllers.first?.contentViewController as? DocumentContent,
              content.isViewLoaded, content.pendingPosition == nil else { return }
        Preferences.remember(content.currentPosition, for: fileURL)
    }

    /// Saved under a new name: follow that file from its next read.
    override public var fileURL: URL? {
        didSet {
            guard !Self.sameFile(oldValue, fileURL), !windowControllers.isEmpty else { return }
            let subtitle = Self.subtitle(for: fileURL, home: Self.homeDirectory, viewer: isViewer)
            windowControllers.forEach { $0.window?.subtitle = subtitle }
            // Moved, not deleted: show and follow the file where it is now.
            if case .deleted = externalState { resetExternalState() }
            watchForAppends()
            scheduleDiskCheck()
        }
    }

    // MARK: Where the file is

    /// The folder under the name in the title bar, home shortened to "~".
    static func subtitle(for url: URL?, home: String, viewer: Bool) -> String {
        let note = viewer ? L10n.tr("Read-only (large file)") : ""
        guard let url else { return note }
        var folder = url.deletingLastPathComponent().path
        if folder == home {
            folder = "~"
        } else if folder.hasPrefix(home + "/") {
            folder = "~" + folder.dropFirst(home.count)
        }
        return note.isEmpty ? folder : "\(folder) — \(note)"
    }

    /// The user's real home: in the sandbox NSHomeDirectory() is the container.
    static let homeDirectory: String = {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return NSHomeDirectory() }
        return String(cString: dir)
    }()

    @objc func copyPath(_ sender: Any?) { copyPath(to: .general) }

    func copyPath(to pasteboard: NSPasteboard) {
        guard let fileURL else { return }
        pasteboard.clearContents()
        pasteboard.setString(fileURL.path, forType: .string)
    }

    @objc func showInFinder(_ sender: Any?) {
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    override public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copyPath(_:)), #selector(showInFinder(_:)): return fileURL != nil
        // Hundreds of MB of pages is never what's meant.
        case #selector(printDocument(_:)): return !isViewer && super.validateMenuItem(menuItem)
        default: return super.validateMenuItem(menuItem)
        }
    }

    // MARK: Editing lines of a large file

    /// Writes `text` over `chunk` in the file off the main thread (a big
    /// file is a long copy), then reads the whole file again: an edit of the
    /// same length looks like nothing happened to the tail.
    func writeLines(_ text: String, over chunk: LineSplice.Chunk, completion: @escaping (Error?) -> Void) {
        guard let fileURL, model != nil else { return completion(CocoaError(.fileNoSuchFile)) }
        let replacement = LineSplice.matchingLineBreaks(text, original: chunk.text)
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: Error?
            do { try LineSplice.write(replacement, over: chunk, to: fileURL) } catch { failure = error }
            DispatchQueue.main.async {
                if failure == nil {
                    self.tail = nil
                    self.scheduleDiskCheck()
                }
                completion(failure)
            }
        }
    }

    // MARK: Printing

    /// The text as plain text in the editor font, wrapped to the page width.
    override public func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard !isViewer else { throw CocoaError(.userCancelled) }
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        // Between the Page Setup margins, which is where the operation lays it out.
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        view.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.isRichText = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.string = currentModel().storage.string
        view.font = Preferences.font
        view.sizeToFit()
        return NSPrintOperation(view: view, printInfo: info)
    }

    /// New text gets ".txt"; files that already exist keep whatever name they have.
    override public func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        super.fileNameExtension(forType: typeName, saveOperation: saveOperation) ?? (fileURL == nil ? "txt" : nil)
    }

    override public func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        // Suggest .txt, but any extension (or none) is fine for a plain-text editor.
        if fileURL == nil { savePanel.allowedContentTypes = [.plainText] }
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        return true
    }

    /// Decodes the file on disk again, exactly as `encoding`. Throws (and
    /// leaves the tab alone) when the bytes aren't valid in that encoding.
    func reopen(with encoding: String.Encoding) throws {
        guard let fileURL else { return }
        let data = try Data(contentsOf: fileURL)
        let file = try TextFile(data: data, encoding: encoding)
        install(EditorModel(file: file))
        tail = FileTail(data: data, encoding: encoding)
        undoManager?.removeAllActions()
        updateChangeCount(.changeCleared)
        // The tab now shows the disk exactly: nothing is pending.
        resetExternalState()
        fileModificationDate = Self.modificationDate(of: fileURL)
    }

    /// Menu entry point: confirms first when unsaved edits would be lost.
    func reopenAskingFirst(with encoding: String.Encoding, in window: NSWindow?) {
        let reopen = { [weak self] in
            do {
                try self?.reopen(with: encoding)
            } catch {
                let alert = NSAlert()
                alert.messageText = L10n.tr("The file isn't valid %@.", TextFile.name(of: encoding))
                alert.informativeText = L10n.tr("The text was left as it is.")
                if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            }
        }
        guard isDocumentEdited, let window else { return reopen() }
        let alert = NSAlert()
        alert.messageText = L10n.tr("Reopen as %@?", TextFile.name(of: encoding))
        alert.informativeText = L10n.tr("Unsaved changes in this tab will be lost.")
        alert.addButton(withTitle: L10n.tr("Reopen"))
        alert.addButton(withTitle: L10n.tr("Cancel"))
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { reopen() }
        }
    }

    // MARK: External changes

    override public func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { self.diskDidChange(nil) }
        completionHandler(nil)
    }

    /// Called by the file coordinator on its own queue.
    override public func presentedItemDidChange() {
        // Not calling super: NSDocument would revert or warn on its own terms.
        DispatchQueue.main.async { self.scheduleDiskCheck() }
    }

    /// What a disk read produced, prepared off the main thread.
    struct DiskRead {
        var file: TextFile
        /// LF line endings, for comparing with `baseText` (empty for the viewer).
        var normalized: String
        /// Ready-made model for the viewer, which just swaps it in.
        var prepared: EditorModel.Prepared?
        /// Where the viewer resumes following the file.
        var tail: FileTail?
        var date: Date?

        static func make(_ data: Data, preferring encoding: String.Encoding, forViewer: Bool, date: Date?) -> DiskRead? {
            guard let file = TextDocument.decode(data, preferring: encoding) else { return nil }
            return DiskRead(
                file: file,
                normalized: forViewer ? "" : TextDocument.normalized(file.text),
                prepared: forViewer ? EditorModel.prepare(file) : nil,
                tail: forViewer ? FileTail(data: data, encoding: file.encoding) : nil,
                date: date)
        }
    }

    /// Coalesces bursts (a log written every few ms), then reads and decodes
    /// the file off the main thread.
    private func scheduleDiskCheck() {
        // A tab following the file throttles instead: a log written every few
        // ms would keep postponing a debounced check forever. One read at a
        // time; news that arrives meanwhile asks for one more afterwards.
        let forViewer = isViewer
        let following = followsDisk
        if following {
            guard !followReadBusy else { followRecheck = true; return }
            followReadBusy = true
        } else {
            diskCheck?.cancel()
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let url = self.fileURL, let model = self.model else { return following ? self.followReadDone() : () }
            let stamp = self.diskReadStamp
            let text = self.textStamp
            let encoding = model.file.encoding
            let tail = forViewer ? self.tail : nil
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = Self.readDisk(url, presenter: self, tail: tail, preferring: encoding, forViewer: forViewer)
                DispatchQueue.main.async {
                    switch outcome {
                    case .appended(let followed, let change, let date):
                        self.tailReadFinished(followed, change, from: tail!)
                        self.fileModificationDate = date
                    case .read(let read): self.diskReadFinished(read, stamp: stamp, text: text)
                    case .nothing: break
                    }
                    if following { self.followReadDone() }
                }
            }
        }
        if !following { diskCheck = work }
        DispatchQueue.main.asyncAfter(deadline: .now() + (following ? 0.1 : 0.3), execute: work)
    }

    private var followReadBusy = false
    private var followRecheck = false

    private func followReadDone() {
        followReadBusy = false
        guard followRecheck else { return }
        followRecheck = false
        scheduleDiskCheck()
    }

    /// The viewer, or an unedited editor tab: new text at the end of the file
    /// is added in place. An edited tab reviews changes instead.
    private var followsDisk: Bool {
        if isViewer { return true }
        guard !isDocumentEdited, saveInFlight == 0, case .none = externalState else { return false }
        return true
    }

    private enum DiskOutcome {
        case appended(FileTail, FileTail.Change, Date?)
        /// Nil: the file is gone.
        case read(DiskRead?)
        /// Unreadable or undecodable right now: wait for the next change.
        case nothing
    }

    private nonisolated static func readDisk(
        _ url: URL, presenter: NSFilePresenter, tail: FileTail?, preferring encoding: String.Encoding, forViewer: Bool
    ) -> DiskOutcome {
        // A followed log: read just what was added, if that's all that happened.
        if let tail, let (followed, change, date) = readAppended(to: tail, at: url, presenter: presenter) {
            return .appended(followed, change, date)
        }
        var data: Data?
        var date: Date?
        NSFileCoordinator(filePresenter: presenter).coordinate(readingItemAt: url, options: .withoutChanges, error: nil) { url in
            data = try? Data(contentsOf: url)
            date = modificationDate(of: url)
        }
        // Unreadable but still there (permissions, a write in progress) is not "deleted".
        guard let data else { return FileManager.default.fileExists(atPath: url.path) ? .nothing : .read(nil) }
        return DiskRead.make(data, preferring: encoding, forViewer: forViewer, date: date).map { .read($0) } ?? .nothing
    }

    private func watchForAppends() {
        appendWatcher?.cancel()
        appendWatcher = nil
        guard let url = fileURL else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, unowned source] in
            guard let self else { return }
            let events = source.data
            if !events.isDisjoint(with: [.delete, .rename]) {
                // Replaced or moved (log rotation): watch whatever is at the path now.
                source.cancel()
                self.appendWatcher = nil
                self.rewatch(attemptsLeft: 20)
                // An editor tab leaves moves and deletions to the file presenter,
                // which knows where the file went.
                guard self.isViewer else { return }
            }
            self.scheduleDiskCheck()
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        appendWatcher = source
    }

    /// The file may take a while to come back (a rotator recreating it).
    private func rewatch(attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.appendWatcher == nil, !self.windowControllers.isEmpty else { return }
            self.watchForAppends()
            if self.appendWatcher == nil, attemptsLeft > 1 {
                self.rewatch(attemptsLeft: attemptsLeft - 1)
            } else if self.appendWatcher != nil {
                self.scheduleDiskCheck()
            }
        }
    }

    override public func close() {
        savePosition()
        appendWatcher?.cancel()
        appendWatcher = nil
        super.close()
    }

    /// Nil when the file can't be read that way (gone, or rewritten).
    private nonisolated static func readAppended(
        to tail: FileTail, at url: URL, presenter: NSFilePresenter
    ) -> (FileTail, FileTail.Change, Date?)? {
        var result: (FileTail, FileTail.Change, Date?)?
        NSFileCoordinator(filePresenter: presenter).coordinate(readingItemAt: url, options: .withoutChanges, error: nil) { url in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? handle.close() }
            var tail = tail
            let change = try? tail.update(size: Int(handle.seekToEnd())) { range in
                try handle.seek(toOffset: UInt64(range.lowerBound))
                return try handle.read(upToCount: range.count) ?? Data()
            }
            guard let change, change != .rewritten else { return }
            result = (tail, change, modificationDate(of: url))
        }
        return result
    }

    private func tailReadFinished(_ followed: FileTail, _ change: FileTail.Change, from start: FileTail) {
        // Another read got there first (or the file was reloaded): look again.
        guard isViewer, tail?.byteCount == start.byteCount else { return scheduleDiskCheck() }
        tail = followed
        guard case .appended(let text) = change else { return }
        appendFromDisk(text)
    }

    /// One model behind every view: append once, tell each view. Not an
    /// undoable edit: the tab keeps showing exactly what's on disk.
    private func appendFromDisk(_ text: String) {
        guard let model else { return }
        let views = windowControllers.compactMap { $0.contentViewController as? TailFollowing }
        let atBottom = views.map(\.isScrolledToBottom)
        let oldLength = model.storage.length
        // A tab opened on a partial first line guessed its line ending.
        let guessed = !isViewer && (model.storage.string as NSString).range(of: "\n").location == NSNotFound
        model.append(text)
        if guessed { model.lineEnding = LineEnding.detect(in: model.storage.string) }
        for (view, follow) in zip(views, atBottom) { view.textDidGrow(from: oldLength, follow: follow) }
    }

    /// A background read finished. If we saved since it started, it may
    /// predate our own write; if the text changed (a keystroke NSDocument
    /// hasn't counted yet, a revert), the clean/edited decision is stale.
    /// Either way, read again instead of trusting it.
    func diskReadFinished(_ read: DiskRead?, stamp: Int, text: TextStamp? = nil) {
        // An edited tab diffs against its current text anyway; only the clean
        // path needs the text unchanged (steady typing mustn't hold the banner back).
        guard stamp == diskReadStamp, isDocumentEdited || text == nil || text == textStamp else { return scheduleDiskCheck() }
        diskDidChange(read)
    }

    struct TextStamp: Equatable {
        let model: ObjectIdentifier?
        let edits: Int
    }

    var textStamp: TextStamp { TextStamp(model: model.map(ObjectIdentifier.init), edits: model?.editCount ?? 0) }

    /// Same as a finished read, decoding on the spot (tests, deletion).
    func diskDidChange(_ data: Data?, modificationDate: Date? = nil) {
        guard let model else { return }
        guard let data else { return diskDidChange(nil as DiskRead?) }
        let date = modificationDate ?? fileURL.flatMap(Self.modificationDate(of:))
        guard let read = DiskRead.make(data, preferring: model.file.encoding, forViewer: isViewer, date: date) else { return }
        diskDidChange(read)
    }

    /// The file on disk now holds `read` (nil: it's gone). A clean tab
    /// reloads in place; an edited one gets an external change to review.
    private func diskDidChange(_ read: DiskRead?) {
        guard let model else { return }
        guard let read else {
            externalState = .deleted
            return
        }
        let disk = read.file

        if isViewer {
            install(read.prepared.map(EditorModel.init(prepared:)) ?? EditorModel(file: disk))
            tail = read.tail
            fileModificationDate = read.date
            return
        }

        if !isDocumentEdited {
            // Clean tab: follow the disk exactly, including line endings and encoding.
            let same = (model.storage.string as NSString).isEqual(to: disk.text)
                && disk.encoding == model.file.encoding && disk.hasBOM == model.file.hasBOM
            if let added = Self.appendedText(from: model, to: disk) {
                // A log being written: add the new lines in place.
                appendFromDisk(added)
            } else if !same {
                reloadClean(from: disk)
            }
            baseText = read.normalized
            fileModificationDate = read.date
            resetExternalState()
            return
        }

        guard read.normalized != baseText else {
            // Back to what we already know (or the file reappeared as it was).
            resetExternalState()
            fileModificationDate = read.date
            return
        }
        pendingDiskDate = read.date
        // Saves are gated by `externalState` from here on; keep NSDocument's
        // own "changed by another application" check out of the way.
        fileModificationDate = read.date
        pendingArrivedDuringSave = saveInFlight > 0

        guard model.storage.length > Self.syncMergeLimit else {
            externalState = .changed(ExternalMerge(base: baseText, mine: model.storage.string, disk: disk.text), disk: disk)
            return
        }
        // Big document: gate saves now, diff in the background.
        if case .changed = externalState {} else { externalState = .checking(disk: disk) }
        startBackgroundMerge(disk)
    }

    /// One merge in flight and at most one queued. A finished merge is shown
    /// even if a newer change is queued, so a steady writer can't starve it.
    private func startBackgroundMerge(_ disk: TextFile) {
        guard !mergeInFlight else {
            queuedMergeDisk = disk
            return
        }
        guard let model else { return }
        mergeInFlight = true
        let epoch = stateEpoch
        let base = baseText
        let mine = model.storage.string
        DispatchQueue.global(qos: .userInitiated).async {
            let merge = ExternalMerge(base: base, mine: mine, disk: disk.text)
            DispatchQueue.main.async { self.backgroundMergeFinished(merge, disk: disk, epoch: epoch) }
        }
    }

    private func backgroundMergeFinished(_ merge: ExternalMerge, disk: TextFile, epoch: Int) {
        mergeInFlight = false
        let next = queuedMergeDisk
        queuedMergeDisk = nil
        if epoch == stateEpoch {
            if isDocumentEdited {
                externalState = .changed(merge, disk: disk)
            } else {
                // Saved or undone meanwhile: a clean tab simply follows the disk.
                let latest = next ?? disk
                reloadClean(from: latest)
                baseText = Self.normalized(latest.text)
                fileModificationDate = pendingDiskDate
                resetExternalState()
                return
            }
        }
        if let next, isDocumentEdited {
            if case .none = externalState { externalState = .checking(disk: next) }
            startBackgroundMerge(next)
        }
    }

    /// The pending change, diffed against the text as it is now (the user may
    /// have kept typing since the banner appeared).
    func currentMerge() -> ExternalMerge? {
        guard case .changed(_, let disk) = externalState, let model else { return nil }
        return ExternalMerge(base: baseText, mine: model.storage.string, disk: disk.text)
    }

    /// Straight from the file system: URL resource values are cached and can
    /// be stale within a run loop pass.
    static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// A BOM decides. A UTF-16/32 tab tries its own encoding first (its bytes
    /// often look like valid UTF-8). Otherwise real non-ASCII UTF-8 wins (a
    /// file converted by iconv), and the tab's encoding is tried before
    /// guessing.
    static func decode(_ data: Data, preferring encoding: String.Encoding) -> TextFile? {
        let detected = try? TextFile(data: data)
        if let detected, detected.hasBOM { return detected }
        let wide: [String.Encoding] = [.utf16, .utf16LittleEndian, .utf16BigEndian, .utf32, .utf32LittleEndian, .utf32BigEndian]
        if wide.contains(encoding) { return (try? TextFile(data: data, encoding: encoding)) ?? detected }
        if let detected, detected.encoding == .utf8, !data.allSatisfy({ $0 < 0x80 }) { return detected }
        return (try? TextFile(data: data, encoding: encoding)) ?? detected
    }

    /// Brings the accepted hunks into the text as one undo step. The tab
    /// stays unsaved; the disk version becomes the new base.
    func applyReview(_ decisions: [Int: HunkDecision]) {
        guard case .changed(_, let disk) = externalState, let merge = currentMerge(), let model else { return }
        let merged = merge.apply(decisions)
        let text = model.lineEnding == .lf ? merged : model.lineEnding.apply(to: merged)
        for controller in windowControllers {
            (controller.contentViewController as? DocumentContent)?.replaceText(with: text, actionName: L10n.tr("Apply Disk Changes"))
        }
        adoptDiskAsBase(disk)
    }

    /// Keep my text as it is, but stop treating this disk version as news.
    func dismissExternalChange() {
        switch externalState {
        case .changed(_, let disk), .checking(let disk): adoptDiskAsBase(disk)
        case .deleted: externalState = .none
        case .none: break
        }
    }

    /// Writes my text to `url`, then shows the disk version in this tab.
    func saveMyVersionAs(url: URL) throws {
        guard case .changed(_, let disk) = externalState, let model else { return }
        guard !Self.sameFile(url, fileURL) else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue, userInfo: [
                NSLocalizedDescriptionKey: L10n.tr("Choose another name for your version."),
                NSLocalizedRecoverySuggestionErrorKey: L10n.tr("This is the file that changed on disk; saving here would overwrite those changes."),
            ])
        }
        try model.encodedData().write(to: url, options: .atomic)
        reloadClean(from: disk)
        adoptDiskAsBase(disk)
    }

    /// Reloading from disk is undoable, so NSDocument counts it as an edit
    /// (later, from its own queued block). The tab shows exactly what's on
    /// disk, so that one count is dropped: only while our reload is still the
    /// latest undo step, never for the user's own typing or for undo/redo.
    override public func updateChangeCount(_ change: NSDocument.ChangeType) {
        if change == .changeDone, let undoManager, undoManager.undoActionName == Self.reloadActionName,
           !undoManager.isUndoing, !undoManager.isRedoing, reloadsAwaitingCount > 0 {
            reloadsAwaitingCount -= 1
            return
        }
        super.updateChangeCount(change)
    }

    static var reloadActionName: String { L10n.tr("Reload from Disk") }
    private var reloadsAwaitingCount = 0

    /// Shows the disk version in the tab as one undo step and leaves it clean.
    private func reloadClean(from disk: TextFile) {
        reloadsAwaitingCount = 1
        for controller in windowControllers {
            (controller.contentViewController as? DocumentContent)?.reload(from: disk)
        }
        updateChangeCount(.changeCleared)
    }

    /// What the disk added after the tab's text, if that's all that changed
    /// (same encoding and BOM, the tab's text a strict prefix of the file's).
    static func appendedText(from model: EditorModel, to disk: TextFile) -> String? {
        let mine = model.storage.string as NSString, theirs = disk.text as NSString
        guard theirs.length > mine.length, disk.encoding == model.file.encoding, disk.hasBOM == model.file.hasBOM,
              theirs.compare(mine as String, options: .literal, range: NSRange(location: 0, length: mine.length)) == .orderedSame
        else { return nil }
        return theirs.substring(from: mine.length)
    }

    /// "notes.txt" → "notes (my version).txt"
    static func myVersionName(for url: URL) -> String {
        // A translation must not turn into a path.
        let mine = L10n.tr("(my version)").replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let name = url.deletingPathExtension().lastPathComponent + " " + mine
        return url.pathExtension.isEmpty ? name : name + "." + url.pathExtension
    }

    private func adoptDiskAsBase(_ disk: TextFile) {
        baseText = Self.normalized(disk.text)
        // NSDocument compares this with the file before saving; matching it
        // means no "changed by another application" alert for a decided change.
        fileModificationDate = pendingDiskDate
        // A newer change already queued for diffing is still news.
        let queued = queuedMergeDisk
        resetExternalState()
        if let queued, let model, isDocumentEdited {
            externalState = .checking(disk: queued)
            if model.storage.length > Self.syncMergeLimit {
                startBackgroundMerge(queued)
            } else {
                externalState = .changed(ExternalMerge(base: baseText, mine: model.storage.string, disk: queued.text), disk: queued)
            }
        }
    }

    /// Nothing pending; merges still running belong to the old state.
    private func resetExternalState() {
        stateEpoch += 1
        queuedMergeDisk = nil
        if case .none = externalState {} else { externalState = .none }
    }

    /// Decided once, when the tab is built: an editor tab that grows past the
    /// threshold stays an editor (with everything that protects its edits).
    private var isViewer: Bool {
        opensInViewer ?? ((model?.storage.length ?? 0) > Self.largeFileThreshold)
    }

    static func normalized(_ text: String) -> String {
        (text as NSString).range(of: "\r").location == NSNotFound ? text : LineEnding.lf.apply(to: text)
    }

    private func currentModel() -> EditorModel {
        if let model { return model }
        let prepared = preparedLock.withLock { () -> EditorModel.Prepared? in
            defer { self.prepared = nil }
            if self.prepared != nil { tail = preparedTail }
            preparedTail = nil
            return self.prepared
        }
        let model = prepared.map(EditorModel.init(prepared:)) ?? EditorModel(file: TextFile(text: ""))
        self.model = model
        updateBase()
        return model
    }

    private func applyPrepared() {
        guard let prepared = preparedLock.withLock({ () -> EditorModel.Prepared? in
            defer { self.prepared = nil }
            if self.prepared != nil { tail = preparedTail }
            preparedTail = nil
            return self.prepared
        }) else { return }
        install(EditorModel(prepared: prepared))
        // Revert: the tab now shows the disk, so nothing is pending.
        resetExternalState()
    }

    private func install(_ newModel: EditorModel) {
        model = newModel
        updateBase()
        for controller in windowControllers {
            (controller.contentViewController as? DocumentContent)?.replaceModel(newModel)
        }
    }

    private func updateBase() {
        baseText = isViewer ? "" : Self.normalized(model?.storage.string ?? "")
    }
}

/// Every file type opens as a `TextDocument`; new documents are plain text.
public final class DocumentController: NSDocumentController {
    override public func documentClass(forType typeName: String) -> AnyClass? { TextDocument.self }
    override public var defaultType: String? { "public.plain-text" }
}
