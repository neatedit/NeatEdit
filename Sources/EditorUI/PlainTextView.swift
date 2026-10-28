import AppKit
import EditorCore

/// A plain-text NSTextView: pastes without formatting exactly at the caret
/// and never "helps" by rewriting what you type.
public final class PlainTextView: NSTextView {
    /// Builds a TextKit 1 stack, which handles multi-hundred-MB documents with
    /// non-contiguous layout far better than TextKit 2.
    public static func make(storage: NSTextStorage = NSTextStorage(), font: NSFont = Preferences.font) -> PlainTextView {
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let view = PlainTextView(frame: .zero, textContainer: container)
        view.configure(font: font)
        return view
    }

    static func make(text: String) -> PlainTextView {
        make(storage: NSTextStorage(string: text))
    }

    private func configure(font: NSFont) {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        // Find & replace is our own bar (FindController), not NSTextFinder.
        usesFindBar = false
        usesFontPanel = false
        smartInsertDeleteEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticTextCompletionEnabled = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainerInset = NSSize(width: 4, height: 6)
        setFont(font)
    }

    weak var findController: FindController?
    /// Called after a paste was unwrapped, so the tab can say so.
    var onPasteUnwrapped: (() -> Void)?

    /// ⌘V / Paste. When the text gets unwrapped we do the whole paste
    /// ourselves: NSTextView's own `paste:` adds an (empty) undo step after
    /// ours, which would make the first ⌘Z appear to do nothing.
    override public func paste(_ sender: Any?) {
        if !pasteUnwrapping(from: .general) { super.paste(sender) }
    }

    /// The paste path, with an explicit pasteboard.
    @discardableResult
    func paste(from pboard: NSPasteboard) -> Bool {
        pasteUnwrapping(from: pboard) || readSelection(from: pboard)
    }

    /// Pastes as is, then unwraps it as a separate undo step — one ⌘Z gives
    /// the original back. False (nothing done) when the text doesn't look
    /// hard-wrapped. Services and drops come through `readSelection` and
    /// are never unwrapped.
    private func pasteUnwrapping(from pboard: NSPasteboard) -> Bool {
        guard Preferences.unwrapsPastedText, isEditable, let raw = pboard.string(forType: .string),
              let unwrapped = TextUnwrap.unwrapIfWrapped(raw),
              (undoManager?.groupingLevel ?? 0) == 0 else { return false }
        let start = selectedRange().location
        guard replace(selectedRange(), with: raw, asUndoStep: "Paste") else { return true }
        if replace(NSRange(location: start, length: (raw as NSString).length), with: unwrapped, asUndoStep: "Unwrap Pasted Text") {
            onPasteUnwrapped?()
        }
        return true
    }

    /// Replaces `range` as a top-level undo step of its own (when nothing
    /// else is open in this event) and puts the caret after it.
    @discardableResult
    func replace(_ range: NSRange, with text: String, asUndoStep actionName: String) -> Bool {
        let undo = undoManager
        let groupsByEvent = undo?.groupsByEvent ?? true
        undo?.groupsByEvent = false
        defer { undo?.groupsByEvent = groupsByEvent }
        breakUndoCoalescing()
        undo?.beginUndoGrouping()
        let changed = shouldChangeText(in: range, replacementString: text)
        if changed {
            textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: typingAttributes))
            didChangeText()
            undo?.setActionName(actionName)
        }
        undo?.endUndoGrouping()
        guard changed else { return false }
        setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
        scrollRangeToVisible(selectedRange())
        return true
    }

    override public func performFindPanelAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag,
              let action = NSTextFinder.Action(rawValue: tag) else { return }
        findController?.perform(action)
    }

    override public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performFindPanelAction(_:)) { return findController != nil }
        return super.validateMenuItem(menuItem)
    }

    /// The font is an app-wide preference: hand the font panel's choice up
    /// the responder chain (to the tab controller) instead of restyling text.
    override public func changeFont(_ sender: Any?) {
        _ = nextResponder?.tryToPerform(#selector(changeFont(_:)), with: sender)
    }

    public func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        [.collection, .face, .size]
    }

    public func setFont(_ font: NSFont) {
        // Re-applying the same font would invalidate layout of the whole document.
        if self.font == font, typingAttributes[.font] as? NSFont == font { return }
        self.font = font
        typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
        if let storage = textStorage, storage.length > 0 {
            storage.addAttributes(typingAttributes, range: NSRange(location: 0, length: storage.length))
        }
    }

    public var wrapsLines: Bool = true {
        didSet { applyWrapping() }
    }

    private func applyWrapping() {
        guard let container = textContainer, let scrollView = enclosingScrollView else { return }
        if wrapsLines {
            scrollView.hasHorizontalScroller = false
            isHorizontallyResizable = false
            autoresizingMask = [.width]
            container.widthTracksTextView = true
            setFrameSize(NSSize(width: scrollView.contentSize.width, height: frame.height))
        } else {
            scrollView.hasHorizontalScroller = true
            isHorizontallyResizable = true
            autoresizingMask = []
            container.widthTracksTextView = false
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        needsDisplay = true
    }
}
