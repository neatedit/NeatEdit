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
    /// Modification date of the disk version behind `externalState`.
    private var pendingDiskDate: Date?
    /// Bumped by every completed save: a disk read started before it may
    /// have seen the file before our own write, so its result is stale.
    private(set) var diskReadStamp = 0
    /// Edited documents longer than this (UTF-16 units) are diffed in the background.
    static var syncMergeLimit = 1_000_000

    /// Documents longer than this (UTF-16 units, ~20 MB of text) open in the
    /// read-only viewer, which stays instant no matter the size.
    static var largeFileThreshold = 20_000_000

    override public class var autosavesInPlace: Bool { true }

    /// Lets big files load off the main thread so the app stays responsive.
    override public class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }

    override public func read(from data: Data, ofType typeName: String) throws {
        let prepared = try EditorModel.prepare(data: data)
        preparedLock.withLock { self.prepared = prepared }
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
        case .changed(_, let disk) where pendingArrivedDuringSave:
            if Self.normalized(disk.text) == baseText {
                externalState = .none
            } else if let model {
                externalState = .changed(ExternalMerge(base: baseText, mine: model.storage.string, disk: disk.text), disk: disk)
            }
        default:
            externalState = .none
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
        if case .changed = externalState { return true }
        return false
    }

    private func unresolvedChangeError() -> Error {
        NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "“\(displayName ?? "This document")” changed on disk while it had unsaved changes.",
            NSLocalizedRecoverySuggestionErrorKey: "Review the changes or dismiss them first, so neither version is lost.",
        ])
    }

    private func showExternalChangeResolution() {
        for controller in windowControllers {
            (controller.contentViewController as? EditorViewController)?.resolveExternalChange()
        }
    }

    override public func makeWindowControllers() {
        let model = currentModel()
        let controller: NSViewController = model.storage.length > Self.largeFileThreshold
            ? LargeFileViewController(model: model)
            : EditorViewController(model: model)
        let window = NSWindow(contentViewController: controller)
        if controller is LargeFileViewController {
            window.subtitle = "Read-only (large file)"
        }
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "SimpleTextEdit"
        window.setContentSize(NSSize(width: 800, height: 600))
        let windowController = NSWindowController(window: window)
        windowController.windowFrameAutosaveName = "EditorWindow"
        windowController.shouldCascadeWindows = true
        addWindowController(windowController)
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
        let file = try TextFile(data: Data(contentsOf: fileURL), encoding: encoding)
        install(EditorModel(file: file))
        undoManager?.removeAllActions()
        updateChangeCount(.changeCleared)
    }

    /// Menu entry point: confirms first when unsaved edits would be lost.
    func reopenAskingFirst(with encoding: String.Encoding, in window: NSWindow?) {
        let reopen = { [weak self] in
            do {
                try self?.reopen(with: encoding)
            } catch {
                let alert = NSAlert()
                alert.messageText = "The file isn't valid \(TextFile.name(of: encoding))."
                alert.informativeText = "The text was left as it is."
                if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            }
        }
        guard isDocumentEdited, let window else { return reopen() }
        let alert = NSAlert()
        alert.messageText = "Reopen as \(TextFile.name(of: encoding))?"
        alert.informativeText = "Unsaved changes in this tab will be lost."
        alert.addButton(withTitle: "Reopen")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { reopen() }
        }
    }

    // MARK: External changes

    /// Called by the file coordinator on its own queue. Coalesces bursts
    /// (a log written every few ms) and reads the file off the main thread.
    override public func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.main.async { self.diskDidChange(nil) }
        completionHandler(nil)
    }

    override public func presentedItemDidChange() {
        // Not calling super: NSDocument would revert or warn on its own terms.
        DispatchQueue.main.async { self.scheduleDiskCheck() }
    }

    private func scheduleDiskCheck() {
        diskCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let url = self.fileURL else { return }
            let stamp = self.diskReadStamp
            DispatchQueue.global(qos: .userInitiated).async {
                var data: Data?
                var date: Date?
                NSFileCoordinator(filePresenter: self).coordinate(readingItemAt: url, options: .withoutChanges, error: nil) { url in
                    data = try? Data(contentsOf: url)
                    date = Self.modificationDate(of: url)
                }
                // Unreadable but still there (permissions, a write in progress) is not "deleted".
                if data == nil, FileManager.default.fileExists(atPath: url.path) { return }
                DispatchQueue.main.async { self.diskReadFinished(data, modificationDate: date, stamp: stamp) }
            }
        }
        diskCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// A background read finished. If we saved since it started, it may
    /// predate our own write: read again instead of trusting it.
    func diskReadFinished(_ data: Data?, modificationDate: Date?, stamp: Int) {
        guard stamp == diskReadStamp else { return scheduleDiskCheck() }
        diskDidChange(data, modificationDate: modificationDate)
    }

    /// The file on disk now holds `data` (nil: it's gone). A clean tab
    /// reloads in place; an edited one gets an external change to review.
    func diskDidChange(_ data: Data?, modificationDate: Date? = nil) {
        guard let model else { return }
        guard let data else {
            externalState = .deleted
            return
        }
        guard let disk = Self.decode(data, preferring: model.file.encoding) else { return }
        let date = modificationDate ?? fileURL.flatMap(Self.modificationDate(of:))

        if isViewer {
            install(EditorModel(file: disk))
            fileModificationDate = date
            return
        }

        if !isDocumentEdited {
            // Clean tab: follow the disk exactly, including line endings and encoding.
            let same = disk.text == model.storage.string && disk.encoding == model.file.encoding && disk.hasBOM == model.file.hasBOM
            if !same {
                reloadClean(from: disk)
            }
            baseText = Self.normalized(disk.text)
            fileModificationDate = date
            if case .none = externalState {} else { externalState = .none }
            return
        }

        let diskText = Self.normalized(disk.text)
        guard diskText != baseText else {
            // Back to what we already know (or the file reappeared as it was).
            if case .none = externalState {} else { externalState = .none }
            fileModificationDate = date
            return
        }
        pendingDiskDate = date
        // Saves are gated by `externalState`; keep NSDocument's own
        // "changed by another application" check out of the way.
        fileModificationDate = date
        pendingArrivedDuringSave = saveInFlight > 0
        mergeGeneration += 1
        let generation = mergeGeneration
        let base = baseText
        let mine = model.storage.string
        guard mine.utf16.count > Self.syncMergeLimit else {
            externalState = .changed(ExternalMerge(base: base, mine: mine, disk: disk.text), disk: disk)
            return
        }
        // Big document: diff off the main thread; only the latest change counts.
        DispatchQueue.global(qos: .userInitiated).async {
            let merge = ExternalMerge(base: base, mine: mine, disk: disk.text)
            DispatchQueue.main.async {
                guard generation == self.mergeGeneration, self.isDocumentEdited else { return }
                self.externalState = .changed(merge, disk: disk)
            }
        }
    }

    private var mergeGeneration = 0

    /// Straight from the file system: URL resource values are cached and can
    /// be stale within a run loop pass.
    static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// BOM or real UTF-8 wins; plain ASCII keeps the tab's (ASCII-compatible)
    /// encoding; anything else is tried as the tab's encoding first.
    static func decode(_ data: Data, preferring encoding: String.Encoding) -> TextFile? {
        let detected = try? TextFile(data: data)
        if let detected, detected.hasBOM { return detected }
        let isASCII = data.allSatisfy { $0 < 0x80 }
        let asciiCompatible = ![String.Encoding.utf16, .utf16LittleEndian, .utf16BigEndian, .utf32, .utf32LittleEndian, .utf32BigEndian]
            .contains(encoding)
        if isASCII {
            return asciiCompatible ? (try? TextFile(data: data, encoding: encoding)) ?? detected : detected
        }
        if let detected, detected.encoding == .utf8 { return detected }
        return (try? TextFile(data: data, encoding: encoding)) ?? detected
    }

    /// Brings the accepted hunks into the text as one undo step. The tab
    /// stays unsaved; the disk version becomes the new base.
    func applyReview(_ decisions: [Int: HunkDecision]) {
        guard case .changed(let merge, let disk) = externalState, let model else { return }
        let merged = merge.apply(decisions)
        let text = model.lineEnding == .lf ? merged : model.lineEnding.apply(to: merged)
        for controller in windowControllers {
            (controller.contentViewController as? DocumentContent)?.replaceText(with: text, actionName: "Apply Disk Changes")
        }
        adoptDiskAsBase(disk)
    }

    /// Keep my text as it is, but stop treating this disk version as news.
    func dismissExternalChange() {
        switch externalState {
        case .changed(_, let disk): adoptDiskAsBase(disk)
        case .deleted: externalState = .none
        case .none: break
        }
    }

    /// Writes my text to `url`, then shows the disk version in this tab.
    func saveMyVersionAs(url: URL) throws {
        guard case .changed(_, let disk) = externalState, let model else { return }
        guard !Self.sameFile(url, fileURL) else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "Choose another name for your version.",
                NSLocalizedRecoverySuggestionErrorKey: "This is the file that changed on disk; saving here would overwrite those changes.",
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

    static let reloadActionName = "Reload from Disk"
    private var reloadsAwaitingCount = 0

    /// Shows the disk version in the tab as one undo step and leaves it clean.
    private func reloadClean(from disk: TextFile) {
        reloadsAwaitingCount = 1
        for controller in windowControllers {
            (controller.contentViewController as? DocumentContent)?.reload(from: disk)
        }
        updateChangeCount(.changeCleared)
    }

    /// "notes.txt" → "notes (my version).txt"
    static func myVersionName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent + " (my version)"
        return url.pathExtension.isEmpty ? name : name + "." + url.pathExtension
    }

    private func adoptDiskAsBase(_ disk: TextFile) {
        mergeGeneration += 1
        baseText = Self.normalized(disk.text)
        // NSDocument compares this with the file before saving; matching it
        // means no "changed by another application" alert for a decided change.
        fileModificationDate = pendingDiskDate
        externalState = .none
    }

    private var isViewer: Bool {
        (model?.storage.length ?? 0) > Self.largeFileThreshold
    }

    static func normalized(_ text: String) -> String {
        LineEnding.lf.apply(to: text)
    }

    private func currentModel() -> EditorModel {
        if let model { return model }
        let prepared = preparedLock.withLock { () -> EditorModel.Prepared? in
            defer { self.prepared = nil }
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
            return self.prepared
        }) else { return }
        install(EditorModel(prepared: prepared))
        // Revert: the tab now shows the disk, so nothing is pending.
        if case .none = externalState {} else { externalState = .none }
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
