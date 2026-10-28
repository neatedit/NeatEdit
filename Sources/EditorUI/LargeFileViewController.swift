import AppKit
import EditorCore

/// A read-only tab for files too big for NSTextView.
final class LargeFileViewController: NSViewController, DocumentContent, NSMenuItemValidation {
    private(set) var model: EditorModel
    let textView: LargeTextView
    private let scrollView = NSScrollView()
    let statusBar = StatusBar()
    private let textFinder = NSTextFinder()
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
        view = EditorChrome.root(scrollView: scrollView, statusBar: statusBar)
        statusBar.canChangeLineEnding = false
        statusBar.encodingButton.target = self
        statusBar.encodingButton.action = #selector(showEncodingMenu(_:))

        textFinder.client = textView
        textFinder.findBarContainer = scrollView
        textFinder.isIncrementalSearchingEnabled = false
        textView.textFinder = textFinder
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
        textFinder.noteClientStringWillChange()
        attach(newModel)
    }

    private func attach(_ model: EditorModel) {
        model.onTotalsChanged = { [weak self] in self?.updateStatus() }
        updateStatus()
    }

    private func updateStatus() {
        statusBar.show(model.status(selectedRange: textView.selection))
    }

    @objc private func preferencesChanged() {
        textView.setFont(Preferences.font)
    }

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
        // Lines never wrap or get numbered in the viewer.
        menuItem.action != #selector(EditorViewController.toggleWrapLines(_:))
            && menuItem.action != #selector(EditorViewController.toggleLineNumbers(_:))
    }
}
