import AppKit
import EditorCore

public final class TextDocument: NSDocument {
    private var model: EditorModel?
    /// Set by `read` (possibly on a background thread), consumed on main.
    private var prepared: EditorModel.Prepared?
    private let preparedLock = NSLock()

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

    override public func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        // Any extension (or none) is fine for a plain-text editor.
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        return true
    }

    private func currentModel() -> EditorModel {
        if let model { return model }
        let prepared = preparedLock.withLock { () -> EditorModel.Prepared? in
            defer { self.prepared = nil }
            return self.prepared
        }
        let model = prepared.map(EditorModel.init(prepared:)) ?? EditorModel(file: TextFile(text: ""))
        self.model = model
        return model
    }

    private func applyPrepared() {
        guard let prepared = preparedLock.withLock({ () -> EditorModel.Prepared? in
            defer { self.prepared = nil }
            return self.prepared
        }) else { return }
        let newModel = EditorModel(prepared: prepared)
        model = newModel
        for controller in windowControllers {
            (controller.contentViewController as? DocumentContent)?.replaceModel(newModel)
        }
    }
}

/// Every file type opens as a `TextDocument`; new documents are plain text.
public final class DocumentController: NSDocumentController {
    override public func documentClass(forType typeName: String) -> AnyClass? { TextDocument.self }
    override public var defaultType: String? { "public.plain-text" }
}
