import AppKit
import EditorCore

/// The find & replace strip above the text, Coda style:
///
///     [⚙] [Find ..........][★]  2 of 7  [‹ ›] [Done]
///         [Replace .......][★]  [Replace] [All]
final class FindBar: NSView {
    let findField = PlaceholderField.make()
    let replaceField = PlaceholderField.make()
    let statusLabel = NSTextField(labelWithString: "")
    let optionsButton = NSPopUpButton(frame: .zero, pullsDown: true)
    let caseItem = NSMenuItem(title: L10n.tr("Match Case"), action: nil, keyEquivalent: "")
    let regexItem = NSMenuItem(title: L10n.tr("Regular Expression"), action: nil, keyEquivalent: "")
    let selectionItem = NSMenuItem(title: L10n.tr("In Selection"), action: nil, keyEquivalent: "")
    private let findStar = FindBar.button(symbol: "star.fill", tip: L10n.tr("Insert a placeholder: matches any text on the line"))
    private let replaceStar = FindBar.button(symbol: "star", tip: L10n.tr("Insert the text a Find placeholder matched"))
    private let navigation = NSSegmentedControl()
    private let doneButton = NSButton(title: L10n.tr("Done"), target: nil, action: nil)
    private let replaceButton = NSButton(title: L10n.tr("Replace"), target: nil, action: nil)
    private let replaceAllButton = NSButton(title: L10n.tr("All"), target: nil, action: nil)

    weak var controller: FindController? {
        didSet { wire() }
    }

    private var replaceRow: NSStackView?

    /// Off for read-only text: the bar is just the Find row.
    var showsReplace = true {
        didSet {
            replaceRow?.isHidden = !showsReplace
            findField.nextKeyView = showsReplace ? replaceField : nil
        }
    }

    var isShowingReplace: Bool { replaceRow?.isHidden == false }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 62))
        findField.placeholder = L10n.tr("Find")
        replaceField.placeholder = L10n.tr("Replace")
        findField.nextKeyView = replaceField
        replaceField.nextKeyView = findField

        optionsButton.addItem(withTitle: "")
        optionsButton.item(at: 0)?.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: L10n.tr("Options"))
        optionsButton.menu?.addItem(caseItem)
        optionsButton.menu?.addItem(regexItem)
        optionsButton.menu?.addItem(selectionItem)
        (optionsButton.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        optionsButton.bezelStyle = .flexiblePush
        optionsButton.isBordered = false
        optionsButton.toolTip = L10n.tr("Search options")

        navigation.segmentCount = 2
        navigation.trackingMode = .momentary
        navigation.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: L10n.tr("Previous")), forSegment: 0)
        navigation.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: L10n.tr("Next")), forSegment: 1)
        navigation.setToolTip(L10n.tr("Previous (⇧⌘G)"), forSegment: 0)
        navigation.setToolTip(L10n.tr("Next (⌘G)"), forSegment: 1)

        statusLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        for button in [doneButton, replaceButton, replaceAllButton] {
            button.bezelStyle = .push
            button.controlSize = .small
        }
        doneButton.keyEquivalent = "\u{1b}"
        layOut()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func button(symbol: String, tip: String) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: nil, action: nil)
        button.isBordered = false
        button.contentTintColor = .controlAccentColor
        button.toolTip = tip
        return button
    }

    private func layOut() {
        let indent = NSView()
        let findRow = NSStackView(views: [optionsButton, findField.box, findStar, statusLabel, navigation, doneButton])
        let gap = NSView()
        gap.setContentHuggingPriority(.init(1), for: .horizontal)
        let replaceRow = NSStackView(views: [indent, replaceField.box, replaceStar, gap, replaceButton, replaceAllButton])
        self.replaceRow = replaceRow
        let rows = NSStackView(views: [findRow, replaceRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        rows.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 8)
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        for row in [findRow, replaceRow] {
            row.spacing = 6
            row.widthAnchor.constraint(equalTo: rows.widthAnchor, constant: -14).isActive = true
        }
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
            optionsButton.widthAnchor.constraint(equalToConstant: 34),
            indent.widthAnchor.constraint(equalTo: optionsButton.widthAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: 110),
            replaceField.box.widthAnchor.constraint(equalTo: findField.box.widthAnchor),
            replaceStar.centerXAnchor.constraint(equalTo: findStar.centerXAnchor),
            // Line the replace buttons up under status/navigation/done.
            replaceAllButton.trailingAnchor.constraint(equalTo: doneButton.trailingAnchor),
            findField.box.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        findField.box.setContentHuggingPriority(.defaultLow, for: .horizontal)
        replaceField.box.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func wire() {
        guard let controller else { return }
        findField.findController = controller
        replaceField.findController = controller
        for (item, action) in [(caseItem, #selector(FindController.toggleCaseSensitive(_:))),
                               (regexItem, #selector(FindController.toggleRegex(_:))),
                               (selectionItem, #selector(FindController.toggleInSelection(_:)))] {
            item.target = controller
            item.action = action
        }
        findStar.target = self
        findStar.action = #selector(insertFindPlaceholder(_:))
        replaceStar.target = self
        replaceStar.action = #selector(showReplacePlaceholders(_:))
        navigation.target = controller
        navigation.action = #selector(FindController.navigate(_:))
        doneButton.target = controller
        doneButton.action = #selector(FindController.close)
        replaceButton.target = controller
        replaceButton.action = #selector(FindController.replaceCurrent(_:))
        replaceAllButton.target = controller
        replaceAllButton.action = #selector(FindController.replaceEverything(_:))
    }

    func showOptions(_ options: FindOptions, inSelection: Bool) {
        caseItem.state = options.caseSensitive ? .on : .off
        regexItem.state = options.regex ? .on : .off
        selectionItem.state = inSelection ? .on : .off
    }

    func showStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    // MARK: Placeholders

    /// Adds the smallest number not yet used in Find.
    @objc func insertFindPlaceholder(_ sender: Any?) {
        let used = Set(findField.placeholderNumbers)
        let number = (1...).first { !used.contains($0) }!
        window?.makeFirstResponder(findField)
        findField.insertPlaceholder(number)
    }

    func replacePlaceholderMenu() -> NSMenu {
        let menu = NSMenu()
        let numbers = Array(Set(findField.placeholderNumbers)).sorted()
        if numbers.isEmpty {
            let hint = NSMenuItem(title: L10n.tr("Add placeholders to Find first"), action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        for number in numbers {
            let item = NSMenuItem(title: "\(number)", action: #selector(insertReplacePlaceholder(_:)), keyEquivalent: "")
            item.tag = number
            item.target = self
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        return menu
    }

    @objc private func showReplacePlaceholders(_ sender: NSButton) {
        replacePlaceholderMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func insertReplacePlaceholder(_ sender: NSMenuItem) {
        window?.makeFirstResponder(replaceField)
        replaceField.insertPlaceholder(sender.tag)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

/// What a find bar searches: the editor's text view or the large file viewer.
@MainActor
protocol FindTarget: NSView {
    /// The text as it is now, safe to search (not re-bridged per match).
    /// May copy the whole document: take it once per search.
    var findText: NSString { get }
    var findLength: Int { get }
    func findSubstring(_ range: NSRange) -> String
    var findSelection: NSRange { get }
    /// Selects and scrolls to a match (or just moves the caret).
    func selectFound(_ range: NSRange, indicate: Bool)
    /// False hides Replace and makes its actions beep.
    var canReplaceFound: Bool { get }
    /// Replaces `range` as one undo step named `actionName`.
    func replaceFound(_ range: NSRange, with text: String, actionName: String) -> Bool
    /// Highlights every match (nil: none). Optional: the viewer doesn't.
    func highlightFound(_ ranges: [NSRange]?)
}

extension FindTarget {
    func highlightFound(_ ranges: [NSRange]?) {}
}

extension PlainTextView: FindTarget {
    /// An immutable copy, so regex matching doesn't re-bridge the live storage.
    var findText: NSString { (textStorage?.mutableString.copy() as? NSString) ?? "" }
    var findLength: Int { textStorage?.length ?? 0 }
    func findSubstring(_ range: NSRange) -> String { textStorage?.attributedSubstring(from: range).string ?? "" }
    var findSelection: NSRange { selectedRange() }
    var canReplaceFound: Bool { isEditable }

    func selectFound(_ range: NSRange, indicate: Bool) {
        setSelectedRange(range)
        guard indicate else { return }
        scrollRangeToVisible(range)
        if window?.isVisible == true { showFindIndicator(for: range) }
    }

    func replaceFound(_ range: NSRange, with text: String, actionName: String) -> Bool {
        guard shouldChangeText(in: range, replacementString: text) else { return false }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        undoManager?.setActionName(actionName)
        return true
    }

    func highlightFound(_ ranges: [NSRange]?) {
        guard let layoutManager, let length = textStorage?.length else { return }
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
        let color = NSColor.systemYellow.withAlphaComponent(0.35)
        for range in ranges ?? [] where range.length > 0 {
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }
    }
}

/// Runs searches and replacements for one tab.
@MainActor
final class FindController: NSObject {
    let bar = FindBar()
    private unowned let textView: FindTarget
    private var anchor = 0
    private var selectionScope: NSRange?
    private var refreshPending = false
    private var highlighted = false

    var options = FindOptions() {
        didSet { optionsChanged() }
    }

    var inSelection = false {
        didSet {
            let selection = textView.findSelection
            selectionScope = inSelection && selection.length > 0 ? selection : nil
            optionsChanged()
        }
    }

    var isVisible: Bool { !bar.isHidden }

    init(textView: FindTarget) {
        self.textView = textView
        super.init()
        bar.isHidden = true
        bar.controller = self
        bar.showsReplace = textView.canReplaceFound
        bar.showOptions(options, inSelection: inSelection)
        bar.findField.onChange = { [weak self] in self?.scheduleRefresh(jump: true) }
        bar.findField.onCommit = { [weak self] backwards in self?.find(forward: !backwards) }
        bar.findField.onCancel = { [weak self] in self?.close() }
        bar.replaceField.onChange = nil
        bar.replaceField.onCommit = { [weak self] _ in self?.replace() }
        bar.replaceField.onCancel = { [weak self] in self?.close() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange), name: NSText.didChangeNotification, object: textView)
    }

    private var isLarge: Bool { textView.findLength > EditorViewController.largeDocumentLimit }

    // MARK: Actions

    func perform(_ action: NSTextFinder.Action) {
        switch action {
        case .showFindInterface: show(focus: bar.findField)
        case .showReplaceInterface: show(focus: bar.replaceField)
        case .hideFindInterface: close()
        case .nextMatch: find(forward: true)
        case .previousMatch: find(forward: false)
        case .replace, .replaceAndFind: replace()
        case .replaceAll: replaceAll()
        case .setSearchString: useSelectionForFind()
        default: NSSound.beep()
        }
    }

    /// Whether `action` can run now (menu validation).
    func validate(_ action: NSTextFinder.Action) -> Bool {
        switch action {
        case .replace, .replaceAndFind, .replaceAll, .showReplaceInterface: textView.canReplaceFound
        default: true
        }
    }

    private func show(focus field: PlaceholderField) {
        if !isVisible {
            anchor = textView.findSelection.location
            bar.isHidden = false
            if inSelection { selectionScope = textView.findSelection.length > 0 ? textView.findSelection : nil }
        }
        let field = textView.canReplaceFound ? field : bar.findField
        textView.window?.makeFirstResponder(field)
        field.selectAllText()
        scheduleRefresh(jump: false)
    }

    @objc func close() {
        guard isVisible else { return }
        bar.isHidden = true
        clearHighlights()
        textView.window?.makeFirstResponder(textView)
    }

    @objc func navigate(_ sender: NSSegmentedControl) { find(forward: sender.selectedSegment == 1) }
    @objc func replaceCurrent(_ sender: Any?) { replace() }
    @objc func replaceEverything(_ sender: Any?) { replaceAll() }
    @objc func toggleCaseSensitive(_ sender: Any?) { options.caseSensitive.toggle() }
    @objc func toggleRegex(_ sender: Any?) { options.regex.toggle() }
    @objc func toggleInSelection(_ sender: Any?) { inSelection.toggle() }

    private func optionsChanged() {
        bar.showOptions(options, inSelection: inSelection)
        scheduleRefresh(jump: false)
    }

    private func useSelectionForFind() {
        let selection = textView.findSelection
        guard selection.length > 0 else { return NSSound.beep() }
        bar.findField.tokens = [.text(textView.findSubstring(selection))]
        anchor = selection.location
        scheduleRefresh(jump: false)
    }

    // MARK: Searching

    private var text: NSString { textView.findText }

    private func scope(in text: NSString) -> NSRange {
        let all = NSRange(location: 0, length: text.length)
        guard let scope = selectionScope else { return all }
        return NSIntersectionRange(scope, all)
    }

    /// The current query, or nil after reporting why there isn't one.
    private func query(reportingErrors: Bool = true) -> FindQuery? {
        do {
            return try FindQuery(find: bar.findField.tokens, replace: bar.replaceField.tokens, options: options)
        } catch FindError.invalidPattern {
            if reportingErrors { bar.showStatus(L10n.tr("Invalid pattern"), isError: true) }
        } catch {
            if reportingErrors { bar.showStatus("") }
        }
        return nil
    }

    private func find(forward: Bool) {
        guard let query = query() else { return NSSound.beep() }
        let text = self.text
        let scope = scope(in: text)
        let selection = textView.findSelection
        let match = forward
            ? query.next(in: text, after: selection, scope: scope)
            : query.previous(in: text, before: selection, scope: scope)
        guard let match else {
            bar.showStatus(L10n.tr("Not found"))
            return NSSound.beep()
        }
        select(match.range, query: query, text: text, scope: scope)
    }

    private func select(_ range: NSRange, query: FindQuery, text: NSString, scope: NSRange) {
        textView.selectFound(range, indicate: true)
        anchor = range.location
        reportPosition(of: range, query: query, text: text, scope: scope)
    }

    private func reportPosition(of range: NSRange?, query: FindQuery, text: NSString, scope: NSRange) {
        // Counting (and searching as you type) would scan the whole document.
        guard !isLarge else { return bar.showStatus(range == nil ? L10n.tr("Return to find") : L10n.tr("Found")) }
        let total = query.count(in: text, scope: scope)
        guard let range, total > 0 else {
            return bar.showStatus(total == 0 ? L10n.tr("Not found") : total == 1 ? L10n.tr("1 match") : L10n.tr("%ld matches", total))
        }
        let before = query.count(in: text, scope: NSRange(location: scope.location, length: max(0, range.location - scope.location)))
        bar.showStatus(L10n.tr("%ld of %ld", before + 1, total))
    }

    // MARK: Replacing

    private func replace() {
        guard textView.canReplaceFound, let query = query() else { return NSSound.beep() }
        let text = self.text
        let scope = scope(in: text)
        let selection = textView.findSelection
        guard let match = query.match(at: selection, in: text, scope: scope) else {
            return find(forward: true)
        }
        let replacement = query.replacement(for: match, in: text)
        guard textView.replaceFound(selection, with: replacement, actionName: L10n.tr("Replace")) else { return NSSound.beep() }
        adjustScope(by: replacement.utf16.count - selection.length)

        let after = NSRange(location: selection.location + replacement.utf16.count, length: 0)
        let newText = self.text
        let newScope = self.scope(in: newText)
        if let next = query.next(in: newText, after: after, scope: newScope) {
            select(next.range, query: query, text: newText, scope: newScope)
        } else {
            textView.selectFound(after, indicate: false)
            bar.showStatus(L10n.tr("Not found"))
        }
    }

    private func replaceAll() {
        guard textView.canReplaceFound, let query = query() else { return NSSound.beep() }
        let text = self.text
        let scope = scope(in: text)
        let edits = query.replaceAll(in: text, scope: scope)
        guard let first = edits.first, let last = edits.last else {
            bar.showStatus(L10n.tr("Not found"))
            return NSSound.beep()
        }
        // One contiguous change: a single undo step, and fast with thousands of matches.
        let covered = NSRange(location: first.range.location, length: last.range.upperBound - first.range.location)
        var result = ""
        var cursor = covered.location
        for edit in edits {
            result += text.substring(with: NSRange(location: cursor, length: edit.range.location - cursor))
            result += edit.replacement
            cursor = edit.range.upperBound
        }
        guard textView.replaceFound(covered, with: result, actionName: L10n.tr("Replace All")) else { return NSSound.beep() }
        adjustScope(by: result.utf16.count - covered.length)
        textView.selectFound(selectionScope ?? NSRange(location: covered.location, length: 0), indicate: false)
        bar.showStatus(L10n.tr("Replaced %ld", edits.count))
    }

    private func adjustScope(by delta: Int) {
        guard let scope = selectionScope else { return }
        selectionScope = NSRange(location: scope.location, length: max(0, scope.length + delta))
    }

    // MARK: Live updates

    /// The text was swapped for a different one (the viewer reloaded its
    /// file): old offsets mean nothing now.
    func textWasReplaced() {
        selectionScope = nil
        anchor = 0
        textDidChange()
    }

    /// The text changed (the editor posts NSText's notification; the viewer calls this).
    @objc func textDidChange() {
        guard isVisible else { return }
        scheduleRefresh(jump: false)
    }

    /// Coalesces keystrokes; `jump` moves the selection to the first match after where the search started.
    private func scheduleRefresh(jump: Bool) {
        guard !refreshPending || jump else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.refresh(jump: jump)
        }
    }

    private func refresh(jump: Bool) {
        guard isVisible else { return }
        guard let query = query(reportingErrors: !bar.findField.tokens.isEmpty) else {
            if bar.findField.tokens.isEmpty { bar.showStatus("") }
            return clearHighlights()
        }
        let text = self.text
        let scope = scope(in: text)
        if jump, !isLarge, let match = query.next(in: text, after: NSRange(location: anchor, length: 0), scope: scope) {
            select(match.range, query: query, text: text, scope: scope)
        } else {
            let selection = textView.findSelection
            let current = query.match(at: selection, in: text, scope: scope) != nil ? selection : nil
            reportPosition(of: current, query: query, text: text, scope: scope)
        }
        highlight(query: query, text: text, scope: scope)
    }

    private static let highlightLimit = 5_000

    private func highlight(query: FindQuery, text: NSString, scope: NSRange) {
        clearHighlights()
        guard !isLarge else { return }
        textView.highlightFound(query.ranges(in: text, scope: scope, limit: Self.highlightLimit))
        highlighted = true
    }

    private func clearHighlights() {
        guard highlighted else { return }
        textView.highlightFound(nil)
        highlighted = false
    }
}
