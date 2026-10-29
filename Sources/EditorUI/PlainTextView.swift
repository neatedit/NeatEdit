import AppKit
import EditorCore

/// A plain-text NSTextView: pastes without formatting exactly at the caret
/// and never "helps" by rewriting what you type.
public final class PlainTextView: NSTextView, NSLayoutManagerDelegate {
    /// Builds a TextKit 1 stack, which handles multi-hundred-MB documents with
    /// non-contiguous layout far better than TextKit 2.
    public static func make(storage: NSTextStorage = NSTextStorage(), font: NSFont = Preferences.font) -> PlainTextView {
        let layoutManager = InvisiblesLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let view = PlainTextView(frame: .zero, textContainer: container)
        layoutManager.delegate = view
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

    // MARK: Line commands

    @objc func duplicateLine(_ sender: Any?) { apply(LineEdit.duplicate, "Duplicate") }
    override func moveLineUp(_ sender: Any?) { apply(LineEdit.moveUp, "Move Line Up") }
    override func moveLineDown(_ sender: Any?) { apply(LineEdit.moveDown, "Move Line Down") }

    /// One undo step; a column selection counts as the lines it spans.
    private func apply(_ make: (NSString, NSRange) -> LineEdit?, _ actionName: String) {
        let ranges = selectedRanges.map(\.rangeValue)
        let selection = ranges.dropFirst().reduce(ranges.first ?? selectedRange()) { NSUnionRange($0, $1) }
        guard isEditable, let edit = make(string as NSString, selection) else { return NSSound.beep() }
        guard replace(edit.range, with: edit.replacement, asUndoStep: actionName) else { return }
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
    }

    override public func performFindPanelAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag,
              let action = NSTextFinder.Action(rawValue: tag) else { return }
        findController?.perform(action)
    }

    override public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performFindPanelAction(_:)) { return findController != nil }
        if [#selector(duplicateLine(_:)), #selector(moveLineUp(_:)), #selector(moveLineDown(_:))].contains(menuItem.action) {
            // With a sheet up the keys are meant for it, not the document behind.
            return isEditable && window?.attachedSheet == nil
        }
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
        invalidateCurrentLine()
    }

    /// Marks for spaces, tabs and line ends, drawn by the layout manager.
    var showsInvisibles: Bool {
        get { (layoutManager as? InvisiblesLayoutManager)?.showsInvisibles ?? false }
        set {
            guard let manager = layoutManager as? InvisiblesLayoutManager, manager.showsInvisibles != newValue else { return }
            manager.showsInvisibles = newValue
            needsDisplay = true
        }
    }

    var highlightsCurrentLine = true {
        didSet { if highlightsCurrentLine != oldValue { invalidateCurrentLine() } }
    }

    /// The caret's line (every wrapped row, up to `bandRowLimit` each way),
    /// across the view, in view coordinates. Nil while text is selected or
    /// when off. Cached: drawing asks for it once per tile.
    var currentLineRect: NSRect? {
        let ranges = selectedRanges.map(\.rangeValue)
        guard highlightsCurrentLine, ranges.count == 1, let caret = ranges.first, caret.length == 0,
              let layoutManager, let storage = textStorage else { return nil }
        let key = BandKey(caret: caret.location, length: storage.length, storage: ObjectIdentifier(storage),
                          width: bounds.width, generation: layoutGeneration)
        if let bandCache, bandCache.key == key { return bandCache.rect }
        // Never lay out while the storage is mid-edit; ask again afterwards.
        guard storage.editedMask.isEmpty else { return nil }
        measuringBand = true
        defer { measuringBand = false }
        let rect = Self.lineBand(at: caret.location, in: storage.string as NSString, layoutManager: layoutManager)
            .map { NSRect(x: 0, y: $0.minY + textContainerOrigin.y, width: bounds.width, height: $0.height) }
        bandCache = (key, rect)
        return rect
    }

    private struct BandKey: Equatable {
        let caret: Int, length: Int, storage: ObjectIdentifier, width: CGFloat, generation: Int
    }

    private var bandCache: (key: BandKey, rect: NSRect?)?
    /// Bumped when line geometry changes without the key noticing (an edit
    /// of the same length, a new font, wrapping on or off).
    private var layoutGeneration = 0
    /// The band as last painted, so a move repaints where it really was.
    private var paintedBand: NSRect?
    private var bandRefreshPending = false
    /// Layout we force while measuring the band isn't news about it.
    private var measuringBand = false

    /// Any edit to the storage, including ones that bypass the text view
    /// (a reload of the same length): the band may have moved.
    func textStorageDidEdit() { invalidateCurrentLine() }

    /// Non-contiguous layout catching up can move lines below what it laid out.
    public func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
        guard !measuringBand, highlightsCurrentLine else { return }
        invalidateCurrentLine()
    }

    /// A very long line (minified JSON) is banded only this many rows around
    /// the caret, so a caret move never lays out the whole line.
    static let bandRowLimit = 200

    /// Rows of the logical line around `caret`, in container coordinates.
    private static func lineBand(at caret: Int, in text: NSString, layoutManager: NSLayoutManager) -> NSRect? {
        if caret == text.length, text.length == 0 || isLineBreak(text.character(at: text.length - 1)) {
            // After a final line break: the empty last line.
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: max(text.length - 1, 0), length: min(text.length, 1)))
            let extra = layoutManager.extraLineFragmentRect
            return extra.height > 0 ? extra : nil
        }
        var glyphs = NSRange()
        let at = layoutManager.glyphIndexForCharacter(at: min(caret, text.length - 1))
        var band = layoutManager.lineFragmentRect(forGlyphAt: at, effectiveRange: &glyphs)
        var start = glyphs, end = glyphs
        for _ in 0..<bandRowLimit {
            let first = layoutManager.characterIndexForGlyph(at: start.location)
            guard first > 0, !isLineBreak(text.character(at: first - 1)) else { break }
            band = band.union(layoutManager.lineFragmentRect(forGlyphAt: start.location - 1, effectiveRange: &start))
        }
        for _ in 0..<bandRowLimit {
            let next = layoutManager.characterIndexForGlyph(at: NSMaxRange(end))
            guard NSMaxRange(end) > end.location, next < text.length, !isLineBreak(text.character(at: next - 1)) else { break }
            band = band.union(layoutManager.lineFragmentRect(forGlyphAt: NSMaxRange(end), effectiveRange: &end))
        }
        return band.height > 0 ? band : nil
    }

    private static func isLineBreak(_ c: unichar) -> Bool {
        c == 0x0A || c == 0x0D || c == 0x85 || c == 0x2028 || c == 0x2029
    }

    /// Line geometry changed: forget the band and repaint it later.
    private func invalidateCurrentLine() {
        layoutGeneration += 1
        scheduleBandRefresh()
    }

    /// After the current event (and any storage edit) settles, repaint where
    /// the band was and where it is now.
    private func scheduleBandRefresh() {
        guard !bandRefreshPending else { return }
        bandRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bandRefreshPending = false
            let band = self.currentLineRect
            guard band != self.paintedBand else { return }
            if let old = self.paintedBand { self.setNeedsDisplay(old) }
            if let band { self.setNeedsDisplay(band) }
        }
    }

    override public func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        scheduleBandRefresh()
    }

    override public func didChangeText() {
        super.didChangeText()
        invalidateCurrentLine()
    }

    override public func setFrameSize(_ newSize: NSSize) {
        let rewraps = newSize.width != frame.width
        super.setFrameSize(newSize)
        if rewraps { invalidateCurrentLine() }
    }

    override public func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let band = currentLineRect
        paintedBand = band
        guard let band = band?.intersection(rect), !band.isEmpty else { return }
        NSColor.currentLine.setFill()
        band.fill(using: .sourceOver)
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
        invalidateCurrentLine()
        needsDisplay = true
    }
}

/// ⌥↑ / ⌥↓ are menu shortcuts for moving lines. Every other text view
/// (find fields, sheets) keeps what they do there: paragraph start / end.
extension NSTextView {
    @objc func moveLineUp(_ sender: Any?) {
        moveBackward(sender)
        moveToBeginningOfParagraph(sender)
    }

    @objc func moveLineDown(_ sender: Any?) {
        moveForward(sender)
        moveToEndOfParagraph(sender)
    }
}

/// Draws whitespace marks over the glyphs it draws, so only what's on
/// screen is looked at, however long the document.
extension NSColor {
    /// Soft yellow behind the caret's line, fainter in dark mode.
    static let currentLine = NSColor(name: "currentLine") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.systemYellow.withAlphaComponent(0.10)
            : NSColor.systemYellow.withAlphaComponent(0.16)
    }
}

final class InvisiblesLayoutManager: NSLayoutManager {
    var showsInvisibles = false

    override func processEditing(
        for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions, range newCharRange: NSRange,
        changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange
    ) {
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange,
                             changeInLength: delta, invalidatedRange: invalidatedCharRange)
        (firstTextView as? PlainTextView)?.textStorageDidEdit()
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard showsInvisibles, let storage = textStorage else { return }
        // A long unwrapped line comes in whole: look only at what's in the clip.
        var glyphs = glyphsToShow
        if let clip = NSGraphicsContext.current?.cgContext.boundingBoxOfClipPath, let container = textContainers.first {
            glyphs = NSIntersectionRange(glyphs, glyphRange(forBoundingRect: clip.offsetBy(dx: -origin.x, dy: -origin.y), in: container))
        }
        guard glyphs.length > 0 else { return }
        let text = storage.string as NSString
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let color = NSColor.tertiaryLabelColor
        for offset in characters.location..<NSMaxRange(characters) {
            let character = text.character(at: offset)
            let symbol: String
            if let mark = Invisibles.symbol(for: character) {
                symbol = mark
            } else if Self.isLineEnd(character, followedBy: offset + 1 < text.length ? text.character(at: offset + 1) : nil) {
                symbol = Invisibles.lineEnd
            } else {
                continue
            }
            let glyph = glyphIndexForCharacter(at: offset)
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let location = location(forGlyphAt: glyph)
            guard let font = storage.attribute(.font, at: offset, effectiveRange: nil) as? NSFont else { continue }
            // From the baseline, so a line made taller by an emoji keeps its marks in place.
            let point = NSPoint(x: origin.x + line.minX + location.x, y: origin.y + line.minY + location.y - font.ascender)
            (symbol as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
        }
    }

    /// One mark per line end: CRLF gets it on the LF.
    private static func isLineEnd(_ character: unichar, followedBy next: unichar?) -> Bool {
        switch character {
        case 0x0A, 0x85, 0x2028, 0x2029: true
        case 0x0D: next != 0x0A
        default: false
        }
    }
}
