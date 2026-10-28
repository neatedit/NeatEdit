import AppKit
import EditorCore

/// One editable tab: the text view on top, the status bar underneath.
final class EditorViewController: NSViewController, DocumentContent, NSTextViewDelegate, NSMenuItemValidation {
    private(set) var model: EditorModel
    let textView: PlainTextView
    private let scrollView = NSScrollView()
    private let statusBar = StatusBar()
    private(set) lazy var findController = FindController(textView: textView)
    var leftStatus: NSTextField { statusBar.left }
    var rightStatus: NSTextField { statusBar.right }

    /// Above this many UTF-16 units we only lay out what's on screen and skip
    /// live find highlighting; both otherwise chew through the whole file.
    static let largeDocumentLimit = 5_000_000

    init(model: EditorModel) {
        self.model = model
        textView = PlainTextView.make(storage: model.storage)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        scrollView.documentView = textView
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = self
        textView.findController = findController
        view = EditorChrome.root(scrollView: scrollView, statusBar: statusBar, findBar: findController.bar)

        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged), name: Preferences.didChange, object: nil)
        attach(model)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        textView.wrapsLines = Preferences.wrapsLines
        view.window?.makeFirstResponder(textView)
    }

    /// Swap in freshly loaded text (revert, or the file changed on disk).
    func replaceModel(_ newModel: EditorModel) {
        let selection = textView.selectedRange()
        model.storage.removeLayoutManager(textView.layoutManager!)
        newModel.storage.addLayoutManager(textView.layoutManager!)
        model = newModel
        attach(newModel)
        let location = min(selection.location, newModel.storage.length)
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    private func attach(_ model: EditorModel) {
        model.onTotalsChanged = { [weak self] in self?.updateStatus() }
        let isLarge = model.storage.length > Self.largeDocumentLimit
        textView.layoutManager?.backgroundLayoutEnabled = !isLarge
        updateStatus()
    }

    // MARK: Status bar

    func textViewDidChangeSelection(_ notification: Notification) { scheduleStatusUpdate() }
    func textDidChange(_ notification: Notification) { scheduleStatusUpdate() }

    private func scheduleStatusUpdate() {
        statusBar.scheduleUpdate { [weak self] in self?.updateStatus() }
    }

    private func updateStatus() {
        statusBar.show(model.status(selectedRange: textView.selectedRange()))
    }

    // MARK: Commands

    @objc private func preferencesChanged() {
        textView.setFont(Preferences.font)
        textView.wrapsLines = Preferences.wrapsLines
    }

    @objc func makeTextBigger(_ sender: Any?) { Preferences.fontSize += 1 }
    @objc func makeTextSmaller(_ sender: Any?) { Preferences.fontSize -= 1 }
    @objc func makeTextStandardSize(_ sender: Any?) { Preferences.fontSize = Preferences.defaultFontSize }
    @objc func toggleWrapLines(_ sender: Any?) { Preferences.wrapsLines.toggle() }
    @objc func toggleLineNumbers(_ sender: Any?) { Preferences.showsLineNumbers.toggle() }
    @objc func showFontPanel(_ sender: Any?) { Preferences.showFontPanel() }
    @objc func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        Preferences.adoptFontPanelChoice(manager.convert(Preferences.font))
    }
    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask { [.collection, .face, .size] }

    @objc func goToLine(_ sender: Any?) {
        guard let window = view.window else { return }
        EditorChrome.askForLine(on: window) { [weak self] target in
            guard let self else { return }
            let offset = target.offset(in: self.model.storage.string as NSString, lineIndex: self.model.lineIndex)
            let range = NSRange(location: offset, length: 0)
            self.textView.setSelectedRange(range)
            self.textView.scrollRangeToVisible(range)
            window.makeFirstResponder(self.textView)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleWrapLines(_:)) {
            menuItem.state = Preferences.wrapsLines ? .on : .off
        }
        if menuItem.action == #selector(toggleLineNumbers(_:)) {
            menuItem.state = Preferences.showsLineNumbers ? .on : .off
        }
        return true
    }
}
