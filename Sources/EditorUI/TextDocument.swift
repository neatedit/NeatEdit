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
                (controller.contentViewController as? DocumentContent)?.externalStateDidChange()
            }
        }
    }

    /// The text as last loaded or saved, LF line endings: what external
    /// changes are diffed against. Not kept for the read-only viewer.
    private(set) var baseText = ""
    private var diskCheck: DispatchWorkItem?

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
        // What lands on disk becomes the new base, unless it went to another file.
        let snapshot = saveOperation == .saveToOperation ? nil : model.map { Self.normalized($0.storage.string) }
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil, let snapshot, let self, !self.isViewer { self.baseText = snapshot }
            completionHandler(error)
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
    override public func presentedItemDidChange() {
        // Not calling super: NSDocument would revert or warn on its own terms.
        DispatchQueue.main.async { self.scheduleDiskCheck() }
    }

    private func scheduleDiskCheck() {
        diskCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let url = self.fileURL else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                var data: Data?
                var date: Date?
                NSFileCoordinator(filePresenter: self).coordinate(readingItemAt: url, options: .withoutChanges, error: nil) { url in
                    data = try? Data(contentsOf: url)
                    date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                }
                DispatchQueue.main.async { self.diskDidChange(data, modificationDate: date) }
            }
        }
        diskCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// The file on disk now holds `data` (nil: it's gone). A clean tab
    /// reloads in place; an edited one gets an external change to review.
    func diskDidChange(_ data: Data?, modificationDate: Date? = nil) {
        guard let model, let data else { return }
        guard let disk = (try? TextFile(data: data, encoding: model.file.encoding)) ?? (try? TextFile(data: data)) else { return }
        let date = modificationDate ?? fileURL.flatMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }

        if isViewer {
            install(EditorModel(file: disk))
            fileModificationDate = date
            return
        }
        let diskText = Self.normalized(disk.text)
        guard diskText != baseText else { return }

        if isDocumentEdited {
            externalState = .changed(ExternalMerge(base: baseText, mine: model.storage.string, disk: disk.text), disk: disk)
        } else {
            for controller in windowControllers {
                (controller.contentViewController as? DocumentContent)?.reload(from: disk)
            }
            baseText = diskText
            fileModificationDate = date
            updateChangeCount(.changeCleared)
        }
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
