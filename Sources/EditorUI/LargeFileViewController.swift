import AppKit
import EditorCore

/// A read-only tab for files too big for NSTextView.
final class LargeFileViewController: NSViewController, TailFollowing, NSMenuItemValidation {
    private(set) var model: EditorModel
    let textView: LargeTextView
    private let scrollView = NSScrollView()
    let statusBar = StatusBar()
    private(set) lazy var findController = FindController(textView: textView)
    var leftStatus: NSTextField { statusBar.left }
    var rightStatus: String { statusBar.rightText }

    init(model: EditorModel) {
        self.model = model
        textView = LargeTextView(model: model)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = textView
        view = EditorChrome.root(scrollView: scrollView, statusBar: statusBar, findBar: findController.bar)
        statusBar.canChangeLineEnding = false
        statusBar.encodingButton.target = self
        statusBar.encodingButton.action = #selector(showEncodingMenu(_:))

        textView.findController = findController
        textView.onSelectionChange = { [weak self] in
            self?.statusBar.scheduleUpdate { self?.updateStatus() }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged), name: Preferences.didChange, object: nil)
        attach(model)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    func replaceModel(_ newModel: EditorModel) {
        model = newModel
        textView.replaceModel(newModel)
        findController.textWasReplaced()
        attach(newModel)
    }

    func reload(from file: TextFile) { replaceModel(EditorModel(file: file)) }

    var isScrolledToBottom: Bool { textView.isScrolledToBottom }

    func textDidGrow(from oldLength: Int, follow: Bool) {
        textView.textDidGrow(from: oldLength, follow: follow)
        findController.textDidChange()
        updateStatus()
    }
    func replaceText(with text: String, actionName: String) {}
    func externalStateDidChange(_ state: TextDocument.ExternalState) {}

    private func attach(_ model: EditorModel) {
        model.onTotalsChanged = { [weak self] in self?.updateStatus() }
        updateStatus()
    }

    private func updateStatus() {
        statusBar.show(model.status(selectedRange: textView.selection))
    }

    @objc private func preferencesChanged() {
        textView.setFont(Preferences.font)
        textView.showsInvisibles = Preferences.showsInvisibles
        textView.highlightsCurrentLine = Preferences.highlightsCurrentLine
    }

    /// Lines around the caret (or the selected lines) with this many on each side.
    static let editContext = 10

    /// Edit ▸ Edit Lines…: a sheet with a few lines, written straight into the file.
    @objc func editLines(_ sender: Any?) {
        guard presentedViewControllers?.isEmpty ?? true, let document = view.window?.windowController?.document as? TextDocument
        else { return }
        let text = model.storage.string as NSString
        let chunk = LineSplice.chunk(around: textView.selection, context: Self.editContext, in: text, lineIndex: model.lineIndex,
                                     encoding: model.file.encoding, hasBOM: model.file.hasBOM)
        let editor = LineEditorController(chunk: chunk)
        editor.onSave = { [weak document] text, done in
            guard let document else { return done(CocoaError(.fileNoSuchFile)) }
            document.writeLines(text, over: chunk, completion: done)
        }
        presentAsSheet(editor)
    }

    @objc func toggleInvisibles(_ sender: Any?) { Preferences.showsInvisibles.toggle() }
    @objc func toggleCurrentLine(_ sender: Any?) { Preferences.highlightsCurrentLine.toggle() }

    @objc func makeTextBigger(_ sender: Any?) { Preferences.fontSize += 1 }
    @objc func makeTextSmaller(_ sender: Any?) { Preferences.fontSize -= 1 }
    @objc func makeTextStandardSize(_ sender: Any?) { Preferences.fontSize = Preferences.defaultFontSize }
    @objc func showFontPanel(_ sender: Any?) { Preferences.showFontPanel() }
    @objc func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        Preferences.adoptFontPanelChoice(manager.convert(Preferences.font))
    }
    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask { [.collection, .face, .size] }

    var document: TextDocument? { view.window?.windowController?.document as? TextDocument }

    @objc func showEncodingMenu(_ sender: NSButton) {
        StatusBar.pop(encodingMenu(), under: sender)
    }

    @objc func reopenWithEncoding(_ sender: NSMenuItem) {
        guard let encoding = EditorChrome.encoding(of: sender) else { return }
        document?.reopenAskingFirst(with: encoding, in: view.window)
    }

    /// Read-only: only re-decoding is offered.
    func encodingMenu() -> NSMenu {
        EditorChrome.encodingMenu(current: model.file.encoding, reopen: #selector(reopenWithEncoding(_:)), save: nil, target: self)
    }

    @objc func goToLine(_ sender: Any?) {
        guard let window = view.window else { return }
        EditorChrome.askForLine(on: window) { [weak self] target in
            guard let self else { return }
            let offset = target.offset(in: self.model.storage.string as NSString, lineIndex: self.model.lineIndex)
            self.textView.setSelection(NSRange(location: offset, length: 0))
            self.textView.centerSelectionInVisibleArea(nil)
            window.makeFirstResponder(self.textView)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleInvisibles(_:)) {
            menuItem.state = Preferences.showsInvisibles ? .on : .off
        }
        if menuItem.action == #selector(editLines(_:)) {
            return LineSplice.supports(model.file.encoding) && (presentedViewControllers?.isEmpty ?? true)
        }
        if menuItem.action == #selector(toggleCurrentLine(_:)) {
            menuItem.state = Preferences.highlightsCurrentLine ? .on : .off
        }
        // Lines never wrap or get numbered in the viewer.
        return menuItem.action != #selector(EditorViewController.toggleWrapLines(_:))
            && menuItem.action != #selector(EditorViewController.toggleLineNumbers(_:))
    }
}
