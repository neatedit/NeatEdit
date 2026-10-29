import AppKit
import EditorCore

/// One editable tab: the text view on top, the status bar underneath.
final class EditorViewController: NSViewController, DocumentContent, NSTextViewDelegate, NSMenuItemValidation {
    private(set) var model: EditorModel
    let textView: PlainTextView
    let scrollView = NSScrollView()
    private(set) var lineNumberRuler: LineNumberRuler?
    let statusBar = StatusBar()
    let banner = ExternalChangeBanner()
    private var review: ChangeReviewController?
    private(set) var lastReplacedRange: NSRange?
    /// Shown instead of the caret position until the next edit or move.
    private var statusHint: String?
    private var hintArmed = false
    private(set) lazy var findController = FindController(textView: textView)
    var leftStatus: NSTextField { statusBar.left }
    var rightStatus: String { statusBar.rightText }

    /// Above this many UTF-16 units we only lay out what's on screen and skip
    /// live find highlighting; both otherwise chew through the whole file.
    static var largeDocumentLimit = 5_000_000

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
        view = EditorChrome.root(scrollView: scrollView, statusBar: statusBar, banner: banner, findBar: findController.bar)
        banner.onPrimary = { [weak self] in self?.resolveExternalChange() }
        textView.onPasteUnwrapped = { [weak self] in self?.showHint("Unwrapped pasted text — ⌘Z for original") }
        banner.onDismiss = { [weak self] in self?.document?.dismissExternalChange() }
        statusBar.encodingButton.target = self
        statusBar.encodingButton.action = #selector(showEncodingMenu(_:))

        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged), name: Preferences.didChange, object: nil)
        attach(model)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        textView.wrapsLines = Preferences.wrapsLines
        textView.showsInvisibles = Preferences.showsInvisibles
        applyLineNumbers()
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

    func reload(from file: TextFile) {
        let origin = scrollView.contentView.bounds.origin
        replaceAllText(with: file.text, actionName: TextDocument.reloadActionName) {
            self.setFormat(file, lineEnding: LineEnding.detect(in: file.text))
        }
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func replaceText(with text: String, actionName: String) {
        replaceAllText(with: text, actionName: actionName)
    }

    func externalStateDidChange(_ state: TextDocument.ExternalState) {
        banner.show(state)
        guard let review else { return }
        if case .changed(let merge, _) = state, !merge.isBig {
            review.update(merge: merge)
        } else {
            dismiss(review)
            self.review = nil
        }
    }

    /// Banner button: review hunk by hunk, or for a big change save mine
    /// elsewhere and take the disk version.
    func resolveExternalChange() {
        guard let document, let merge = document.currentMerge() else { return }
        if merge.isBig {
            saveMyVersionAs(document)
        } else {
            let review = ChangeReviewController(merge: merge)
            review.onApply = { [weak self, weak document] decisions in
                self?.closeReview()
                document?.applyReview(decisions)
            }
            review.onCancel = { [weak self] in self?.closeReview() }
            self.review = review
            presentAsSheet(review)
        }
    }

    private func closeReview() {
        if let review { dismiss(review) }
        review = nil
    }

    private func saveMyVersionAs(_ document: TextDocument) {
        guard let window = view.window, let fileURL = document.fileURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = TextDocument.myVersionName(for: fileURL)
        panel.directoryURL = fileURL.deletingLastPathComponent()
        panel.allowsOtherFileTypes = true
        panel.beginSheetModal(for: window) { [weak document] response in
            guard response == .OK, let url = panel.url, let document else { return }
            do {
                try document.saveMyVersionAs(url: url)
            } catch {
                document.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
            }
        }
    }

    /// Turns the text into `text` as one top-level undo step, replacing only
    /// the part that differs (small undo entries, caret stays on its text).
    /// `alongside` runs inside the same undo group and registers its own undo.
    private func replaceAllText(with text: String, actionName: String, alongside: () -> Void = {}) {
        guard let storage = textView.textStorage else { return }
        let range = Self.changedRange(from: storage.string as NSString, to: text as NSString)
        let replacement = (text as NSString).substring(with: NSRange(
            location: range.location, length: (text as NSString).length - (storage.length - range.length)))
        let caret = textView.selectedRange().location
        let delta = (replacement as NSString).length - range.length

        // An explicit top-level group: NSDocument counts the change when it
        // closes, here, not when an automatic per-event group closes later
        // (which would mark a silently reloaded tab dirty again).
        let undoManager = textView.undoManager
        let groupsByEvent = undoManager?.groupsByEvent ?? true
        undoManager?.groupsByEvent = false
        defer { undoManager?.groupsByEvent = groupsByEvent }
        textView.breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        alongside()
        if textView.shouldChangeText(in: range, replacementString: replacement) {
            storage.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: textView.typingAttributes))
            textView.didChangeText()
        }
        undoManager?.setActionName(actionName)
        undoManager?.endUndoGrouping()
        lastReplacedRange = range

        let newCaret = caret <= range.location ? caret
            : caret >= NSMaxRange(range) ? caret + delta
            : range.location + (replacement as NSString).length
        textView.setSelectedRange(NSRange(location: min(newCaret, storage.length), length: 0))
    }

    /// The span of `old` that differs from `new` (common prefix and suffix
    /// trimmed), never splitting a surrogate pair or a CRLF.
    static func changedRange(from old: NSString, to new: NSString) -> NSRange {
        let limit = min(old.length, new.length)
        var prefix = 0
        while prefix < limit, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        while prefix > 0, Self.splitsPair(old, at: prefix) || Self.splitsPair(new, at: prefix) { prefix -= 1 }
        var suffix = 0
        while suffix < limit - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        while suffix > 0, Self.splitsPair(old, at: old.length - suffix) || Self.splitsPair(new, at: new.length - suffix) { suffix -= 1 }
        return NSRange(location: prefix, length: old.length - suffix - prefix)
    }

    private static func splitsPair(_ text: NSString, at index: Int) -> Bool {
        guard index > 0, index < text.length else { return false }
        let before = text.character(at: index - 1), after = text.character(at: index)
        return UTF16.isLeadSurrogate(before) && UTF16.isTrailSurrogate(after) || (before == 0x0D && after == 0x0A)
    }

    private func setFormat(_ file: TextFile, lineEnding: LineEnding) {
        let old = (file: model.file, lineEnding: model.lineEnding)
        model.adoptFormat(of: file)
        model.lineEnding = lineEnding
        textView.undoManager?.registerUndo(withTarget: self) { $0.setFormat(old.file, lineEnding: old.lineEnding) }
        updateStatus()
    }

    private func attach(_ model: EditorModel) {
        model.onTotalsChanged = { [weak self] in self?.updateStatus() }
        let isLarge = model.storage.length > Self.largeDocumentLimit
        textView.layoutManager?.backgroundLayoutEnabled = !isLarge
        updateStatus()
    }

    // MARK: Status bar

    func textViewDidChangeSelection(_ notification: Notification) { clearHint(); scheduleStatusUpdate() }
    func textDidChange(_ notification: Notification) { clearHint(); scheduleStatusUpdate() }

    private func showHint(_ hint: String) {
        statusHint = hint
        hintArmed = false
        scheduleStatusUpdate()
        // Changes made by the action itself are still arriving; arm after them.
        DispatchQueue.main.async { [weak self] in self?.hintArmed = true }
    }

    private func clearHint() {
        guard hintArmed, statusHint != nil else { return }
        statusHint = nil
    }

    private func scheduleStatusUpdate() {
        statusBar.scheduleUpdate { [weak self] in self?.updateStatus() }
    }

    private func updateStatus() {
        statusBar.show(model.status(selectedRange: textView.selectedRange()))
        if let statusHint { statusBar.left.stringValue = statusHint }
    }

    // MARK: Commands

    @objc private func preferencesChanged() {
        textView.setFont(Preferences.font)
        textView.wrapsLines = Preferences.wrapsLines
        textView.showsInvisibles = Preferences.showsInvisibles
        applyLineNumbers()
    }

    private func applyLineNumbers() {
        guard Preferences.showsLineNumbers else {
            scrollView.rulersVisible = false
            return
        }
        if lineNumberRuler == nil {
            let ruler = LineNumberRuler(textView: textView) { [unowned self] in self.model }
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            lineNumberRuler = ruler
        }
        lineNumberRuler?.needsDisplay = true
        scrollView.rulersVisible = true
    }

    @objc func makeTextBigger(_ sender: Any?) { Preferences.fontSize += 1 }
    @objc func makeTextSmaller(_ sender: Any?) { Preferences.fontSize -= 1 }
    @objc func makeTextStandardSize(_ sender: Any?) { Preferences.fontSize = Preferences.defaultFontSize }
    @objc func toggleWrapLines(_ sender: Any?) { Preferences.wrapsLines.toggle() }
    @objc func toggleUnwrapPastedText(_ sender: Any?) { Preferences.unwrapsPastedText.toggle() }

    /// Text menu items: the tag is the transform's index in `allCases`.
    @objc func transformText(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag,
              TextTransform.allCases.indices.contains(tag) else { return }
        apply(TextTransform.allCases[tag])
    }

    /// Converts the selection, or the whole document when nothing is
    /// selected, as one undo step. Line transforms take whole lines.
    func apply(_ transform: TextTransform) {
        let storage = model.storage.string as NSString
        let selection = textView.selectedRange()
        var range = selection.length > 0 ? selection : NSRange(location: 0, length: storage.length)
        if transform.worksOnWholeLines { range = Self.wholeLines(range, in: storage) }
        let text = storage.substring(with: range)
        let result: String
        do {
            result = try transform.apply(to: text)
        } catch {
            NSSound.beep()
            return showHint((error as? TextTransform.Failure)?.message ?? "\(transform.title) failed")
        }
        guard result != text else { return showHint("\(transform.title): nothing to change") }
        if selection.length > 0 {
            guard textView.replace(range, with: result, asUndoStep: transform.title) else { return }
            textView.setSelectedRange(NSRange(location: range.location, length: (result as NSString).length))
        } else {
            replaceAllText(with: storage.replacingCharacters(in: range, with: result), actionName: transform.title)
        }
    }

    /// `range` grown to the lines it touches, without the last line break.
    /// A selection that ends right after a line break stops at that line.
    static func wholeLines(_ range: NSRange, in text: NSString) -> NSRange {
        let last = range.length > 0 ? NSMaxRange(range) - 1 : range.location
        let start = text.lineRange(for: NSRange(location: range.location, length: 0)).location
        var end = NSMaxRange(text.lineRange(for: NSRange(location: last, length: 0)))
        if end > start, text.character(at: end - 1) == 0x0A { end -= 1 }
        if end > start, text.character(at: end - 1) == 0x0D { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
    @objc func toggleLineNumbers(_ sender: Any?) { Preferences.showsLineNumbers.toggle() }
    @objc func toggleInvisibles(_ sender: Any?) { Preferences.showsInvisibles.toggle() }
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

    func encodingMenu() -> NSMenu {
        EditorChrome.encodingMenu(
            current: model.file.encoding,
            reopen: document?.fileURL == nil ? nil : #selector(reopenWithEncoding(_:)),
            save: #selector(saveWithEncoding(_:)),
            target: self)
    }

    @objc func saveWithEncoding(_ sender: NSMenuItem) {
        guard let encoding = EditorChrome.encoding(of: sender), !applySaveEncoding(encoding),
              let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "This text can't be saved as \(TextFile.name(of: encoding))."
        alert.informativeText = "Some characters don't exist in that encoding. The encoding was not changed."
        alert.beginSheetModal(for: window)
    }

    /// Switches the encoding used for saving; false when the text doesn't fit.
    @discardableResult
    func applySaveEncoding(_ encoding: String.Encoding) -> Bool {
        guard encoding != model.file.encoding else { return true }
        guard TextFile(text: model.storage.string).canEncode(as: encoding) else { return false }
        model.setEncoding(encoding)
        document?.updateChangeCount(.changeDone)
        updateStatus()
        return true
    }

    @objc func chooseLineEnding(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let ending = LineEnding(rawValue: raw) else { return }
        setLineEnding(ending)
    }

    /// Converts every line break in the text; one undo step reverts both the
    /// text and the setting.
    func setLineEnding(_ ending: LineEnding) {
        guard ending != model.lineEnding else { return }
        let caret = textView.selectedRange().location
        replaceAllText(with: ending.apply(to: model.storage.string), actionName: "Convert Line Endings") {
            self.setFormat(self.model.file, lineEnding: ending)
        }
        textView.setSelectedRange(NSRange(location: min(caret, model.storage.length), length: 0))
    }

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
        if menuItem.action == #selector(toggleInvisibles(_:)) {
            menuItem.state = Preferences.showsInvisibles ? .on : .off
        }
        if menuItem.action == #selector(toggleUnwrapPastedText(_:)) {
            menuItem.state = Preferences.unwrapsPastedText ? .on : .off
        }
        if menuItem.action == #selector(transformText(_:)) { return textView.isEditable }
        return true
    }
}
