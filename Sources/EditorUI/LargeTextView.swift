import AppKit
import EditorCore

/// Read-only text view for huge files. Every line is one fixed-height row, so
/// drawing, hit testing and scrolling only ever touch the lines on screen —
/// unlike NSTextView, which lays out from the top of the document.
final class LargeTextView: NSView, NSMenuItemValidation {
    enum Granularity { case character, word, line }

    private(set) var model: EditorModel
    private(set) var layout: ViewerLayout
    private(set) var selection = NSRange(location: 0, length: 0)
    var onSelectionChange: (() -> Void)?
    weak var findController: FindController?
    var showsInvisibles = Preferences.showsInvisibles {
        didSet { if showsInvisibles != oldValue { needsDisplay = true } }
    }

    private var font: NSFont
    private var anchor = NSRange(location: 0, length: 0)
    private var preferredColumn: Int?
    private var longestLine: Int

    init(model: EditorModel, font: NSFont = Preferences.font) {
        self.model = model
        self.font = font
        layout = Self.layout(for: font)
        longestLine = model.lineIndex.longestLine(textLength: model.storage.length)
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    private var text: NSString { model.storage.string as NSString }
    private var navigator: TextNavigator { TextNavigator(text: text, lineIndex: model.lineIndex) }

    var documentSize: NSSize {
        layout.documentSize(lineCount: model.lineIndex.lineCount, longestLine: longestLine)
    }

    func replaceModel(_ newModel: EditorModel) {
        model = newModel
        longestLine = newModel.lineIndex.longestLine(textLength: newModel.storage.length)
        updateFrameSize()
        setSelection(NSRange(location: min(selection.location, newModel.storage.length), length: 0))
    }

    var isScrolledToBottom: Bool { visibleRect.maxY >= bounds.height - layout.lineHeight }

    /// Text was added at the end of the model (a followed log). If it was
    /// scrolled to the bottom (`follow`), the view keeps up; otherwise it stays put.
    func textDidGrow(from oldLength: Int, follow: Bool) {
        let firstNewLine = model.lineIndex.line(containing: max(oldLength - 1, 0))
        longestLine = max(longestLine, model.lineIndex.longestLine(textLength: model.storage.length, from: firstNewLine))
        updateFrameSize()
        needsDisplay = true
        if follow { scrollToEndOfDocument(nil) }
    }

    func setFont(_ newFont: NSFont) {
        font = newFont
        layout = Self.layout(for: newFont)
        updateFrameSize()
        needsDisplay = true
    }

    private static func layout(for font: NSFont) -> ViewerLayout {
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font).rounded(.up)
        let charWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        return ViewerLayout(lineHeight: lineHeight, charWidth: charWidth, inset: CGSize(width: 4, height: 6))
    }

    private func updateFrameSize() {
        let size = documentSize
        let visible = enclosingScrollView?.contentSize ?? .zero
        setFrameSize(NSSize(width: max(size.width, visible.width), height: max(size.height, visible.height)))
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateFrameSize()
    }

    // MARK: Line geometry

    /// One visible line, typeset just enough to draw and hit-test it.
    private struct LineRun {
        let content: NSRange
        let window: Range<Int>  // UTF-16 columns of `content` that were typeset
        let line: CTLine
        let originX: CGFloat

        func x(forOffset offset: Int) -> CGFloat {
            let index = min(max(offset - content.location - window.lowerBound, 0), window.count)
            return originX + CTLineGetOffsetForStringIndex(line, index, nil)
        }

        func offset(forX x: CGFloat) -> Int {
            let index = CTLineGetStringIndexForPosition(line, CGPoint(x: x - originX, y: 0))
            return content.location + window.lowerBound + max(0, index == kCFNotFound ? window.count : index)
        }
    }

    private func run(forLine line: Int, visibleX: Range<CGFloat>) -> LineRun {
        let content = model.lineIndex.contentRange(ofLine: line, in: text)
        let window = layout.columnWindow(lineLength: content.length, visibleX: visibleX)
        let piece = text.substring(with: NSRange(location: content.location + window.lowerBound, length: window.count))
        let attributed = NSAttributedString(string: piece, attributes: [.font: font, .foregroundColor: NSColor.textColor])
        return LineRun(
            content: content,
            window: window,
            line: CTLineCreateWithAttributedString(attributed),
            originX: layout.inset.width + CGFloat(window.lowerBound) * layout.charWidth
        )
    }

    private var visibleXRange: Range<CGFloat> {
        let rect = visibleRect.isEmpty ? bounds : visibleRect
        return rect.minX..<max(rect.maxX, rect.minX + 1)
    }

    func offset(at point: NSPoint) -> Int {
        let lineCount = model.lineIndex.lineCount
        if point.y < layout.inset.height { return 0 }
        if point.y >= layout.inset.height + CGFloat(lineCount) * layout.lineHeight { return text.length }
        let line = layout.line(atY: point.y, lineCount: lineCount)
        let visible = visibleXRange
        let around = min(point.x, visible.lowerBound)..<max(point.x + 1, visible.upperBound)
        return navigator.snap(run(forLine: line, visibleX: around).offset(forX: point.x))
    }

    private func caretRect(for offset: Int) -> NSRect {
        let line = model.lineIndex.line(containing: offset)
        let x = run(forLine: line, visibleX: visibleXRange).x(forOffset: offset)
        let row = layout.lineRect(line, width: 0)
        return NSRect(x: x, y: row.minY, width: 1, height: row.height)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        let lines = layout.lines(in: dirtyRect, lineCount: model.lineIndex.lineCount)
        let visibleX = dirtyRect.minX..<dirtyRect.maxX
        let isActive = window?.firstResponder === self && window?.isKeyWindow == true
        let selectionColor = isActive ? NSColor.selectedTextBackgroundColor : NSColor.unemphasizedSelectedTextBackgroundColor
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        for line in lines {
            let run = run(forLine: line, visibleX: visibleX)
            let row = layout.lineRect(line, width: bounds.width)

            let lineSelection = NSIntersectionRange(selection, NSRange(location: run.content.location, length: run.content.length + 1))
            if selection.length > 0, lineSelection.length > 0 || (selection.location <= run.content.location && NSMaxRange(selection) > NSMaxRange(run.content)) {
                let start = max(selection.location, run.content.location)
                let x0 = run.x(forOffset: start)
                let x1 = NSMaxRange(selection) > NSMaxRange(run.content) ? bounds.width : run.x(forOffset: NSMaxRange(selection))
                selectionColor.setFill()
                NSRect(x: x0, y: row.minY, width: max(x1 - x0, 0), height: row.height).fill()
            }

            context.saveGState()
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: run.originX, y: row.minY + font.ascender + (row.height - font.ascender + font.descender) / 2)
            CTLineDraw(run.line, context)
            context.restoreGState()
            if showsInvisibles { drawInvisibles(in: run, row: row, visibleX: visibleX) }

            if isActive, selection.length == 0, lines.contains(model.lineIndex.line(containing: selection.location)),
               model.lineIndex.line(containing: selection.location) == line {
                NSColor.textInsertionPointColor.setFill()
                NSRect(x: run.x(forOffset: selection.location), y: row.minY, width: 1, height: row.height).fill()
            }
        }
    }

    /// Marks over the typeset part of the line, and its line end when shown.
    private func drawInvisibles(in run: LineRun, row: NSRect, visibleX: Range<CGFloat>) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        // A fixed-pitch grid: only the columns in the dirty rect, plus a little slack.
        let first = Int((visibleX.lowerBound - layout.inset.width) / layout.charWidth) - 2
        let last = Int((visibleX.upperBound - layout.inset.width) / layout.charWidth) + 2
        let columns = run.window.clamped(to: max(first, 0)..<max(last, 0))
        for column in columns {
            let offset = run.content.location + column
            guard let symbol = Invisibles.symbol(for: text.character(at: offset)) else { continue }
            (symbol as NSString).draw(at: NSPoint(x: run.x(forOffset: offset), y: row.minY), withAttributes: attributes)
        }
        let end = NSMaxRange(run.content)
        if end < text.length, run.window.upperBound == run.content.length {
            (Invisibles.lineEnd as NSString).draw(at: NSPoint(x: run.x(forOffset: end), y: row.minY), withAttributes: attributes)
        }
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    // MARK: Selection

    func setSelection(_ range: NSRange, scroll: Bool = true) {
        let length = text.length
        let location = min(max(range.location, 0), length)
        let clamped = NSRange(location: location, length: min(max(range.length, 0), length - location))
        guard clamped != selection else { return }
        selection = clamped
        needsDisplay = true
        if scroll { scrollToCaret() }
        onSelectionChange?()
    }

    private func scrollToCaret() {
        guard enclosingScrollView != nil else { return }
        scrollToVisible(caretRect(for: selection.location).insetBy(dx: -layout.charWidth * 4, dy: 0))
    }

    func select(at point: NSPoint, granularity: Granularity, extending: Bool) {
        let offset = offset(at: point)
        let hit: NSRange
        switch granularity {
        case .character: hit = NSRange(location: offset, length: 0)
        case .word: hit = navigator.word(at: offset)
        case .line: hit = navigator.lineRange(of: offset)
        }
        if !extending {
            anchor = hit
            preferredColumn = nil
            setSelection(hit, scroll: false)
            return
        }
        setSelection(NSUnionRange(anchor, hit), scroll: false)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let granularity: Granularity = switch event.clickCount {
        case 2: .word
        case 3...: .line
        default: .character
        }
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.shift) {
            anchor = NSRange(location: selection.location, length: 0)
            select(at: point, granularity: granularity, extending: true)
        } else {
            select(at: point, granularity: granularity, extending: false)
        }
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            autoscroll(with: next)
            select(at: convert(next.locationInWindow, from: nil), granularity: granularity, extending: true)
        }
    }

    override func selectAll(_ sender: Any?) {
        anchor = NSRange(location: 0, length: 0)
        setSelection(NSRange(location: 0, length: text.length), scroll: false)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    /// The fixed end of a keyboard selection and the end that moves.
    private var keyboardEnds: (fixed: Int, moving: Int) {
        if selection.length == 0 { return (selection.location, selection.location) }
        return anchor.location == selection.location
            ? (selection.location, NSMaxRange(selection))
            : (NSMaxRange(selection), selection.location)
    }

    private func move(extending: Bool, keepColumn: Bool = false, _ target: (Int) -> Int) {
        let (fixed, moving) = keyboardEnds
        let destination = target(moving)
        if !keepColumn { preferredColumn = nil }
        if extending {
            anchor = NSRange(location: fixed, length: 0)
            setSelection(NSRange(location: min(fixed, destination), length: abs(destination - fixed)))
        } else {
            anchor = NSRange(location: destination, length: 0)
            setSelection(NSRange(location: destination, length: 0))
        }
    }

    private func vertical(_ lines: Int, extending: Bool) {
        let moving = keyboardEnds.moving
        let column = preferredColumn ?? (moving - navigator.lineStart(of: moving))
        preferredColumn = column
        move(extending: extending, keepColumn: true) { self.navigator.vertical(from: $0, lines: lines, preferredColumn: column) }
    }

    private var pageLines: Int { max(Int(visibleRect.height / layout.lineHeight) - 1, 1) }

    override func moveLeft(_ sender: Any?) {
        if selection.length > 0 { return move(extending: false) { _ in self.selection.location } }
        move(extending: false) { self.navigator.left(from: $0) }
    }
    override func moveRight(_ sender: Any?) {
        if selection.length > 0 { return move(extending: false) { _ in NSMaxRange(self.selection) } }
        move(extending: false) { self.navigator.right(from: $0) }
    }
    override func moveUp(_ sender: Any?) { vertical(-1, extending: false) }
    override func moveDown(_ sender: Any?) { vertical(1, extending: false) }
    override func moveLeftAndModifySelection(_ sender: Any?) { move(extending: true) { self.navigator.left(from: $0) } }
    override func moveRightAndModifySelection(_ sender: Any?) { move(extending: true) { self.navigator.right(from: $0) } }
    override func moveUpAndModifySelection(_ sender: Any?) { vertical(-1, extending: true) }
    override func moveDownAndModifySelection(_ sender: Any?) { vertical(1, extending: true) }
    override func moveToBeginningOfLine(_ sender: Any?) { move(extending: false) { self.navigator.lineStart(of: $0) } }
    override func moveToEndOfLine(_ sender: Any?) { move(extending: false) { self.navigator.lineEnd(of: $0) } }
    override func moveToLeftEndOfLine(_ sender: Any?) { moveToBeginningOfLine(sender) }
    override func moveToRightEndOfLine(_ sender: Any?) { moveToEndOfLine(sender) }
    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) { move(extending: true) { self.navigator.lineStart(of: $0) } }
    override func moveToEndOfLineAndModifySelection(_ sender: Any?) { move(extending: true) { self.navigator.lineEnd(of: $0) } }
    override func moveToLeftEndOfLineAndModifySelection(_ sender: Any?) { moveToBeginningOfLineAndModifySelection(sender) }
    override func moveToRightEndOfLineAndModifySelection(_ sender: Any?) { moveToEndOfLineAndModifySelection(sender) }
    // All the way to the edge, past the inset, as NSTextView does.
    override func moveToBeginningOfDocument(_ sender: Any?) {
        move(extending: false) { _ in 0 }
        scrollToBeginningOfDocument(sender)
    }
    override func moveToEndOfDocument(_ sender: Any?) {
        move(extending: false) { _ in self.text.length }
        scrollToEndOfDocument(sender)
    }
    override func moveToBeginningOfDocumentAndModifySelection(_ sender: Any?) { move(extending: true) { _ in 0 } }
    override func moveToEndOfDocumentAndModifySelection(_ sender: Any?) { move(extending: true) { _ in self.text.length } }
    override func moveWordLeft(_ sender: Any?) { move(extending: false) { self.wordLeft(from: $0) } }
    override func moveWordRight(_ sender: Any?) { move(extending: false) { self.wordRight(from: $0) } }
    override func moveWordLeftAndModifySelection(_ sender: Any?) { move(extending: true) { self.wordLeft(from: $0) } }
    override func moveWordRightAndModifySelection(_ sender: Any?) { move(extending: true) { self.wordRight(from: $0) } }
    override func pageDown(_ sender: Any?) { vertical(pageLines, extending: false) }
    override func pageUp(_ sender: Any?) { vertical(-pageLines, extending: false) }
    override func pageDownAndModifySelection(_ sender: Any?) { vertical(pageLines, extending: true) }
    override func pageUpAndModifySelection(_ sender: Any?) { vertical(-pageLines, extending: true) }
    override func scrollPageDown(_ sender: Any?) { scroll(byLines: pageLines) }
    override func scrollPageUp(_ sender: Any?) { scroll(byLines: -pageLines) }
    override func scrollToBeginningOfDocument(_ sender: Any?) { scroll(NSPoint(x: visibleRect.minX, y: 0)) }
    override func scrollToEndOfDocument(_ sender: Any?) { scroll(NSPoint(x: visibleRect.minX, y: bounds.height - visibleRect.height)) }

    private func scroll(byLines lines: Int) {
        scroll(NSPoint(x: visibleRect.minX, y: visibleRect.minY + CGFloat(lines) * layout.lineHeight))
    }

    private func wordRight(from offset: Int) -> Int {
        var position = offset
        let length = text.length
        while position < length {
            let word = navigator.word(at: position)
            let isWord = word.length > 1 || CharacterSet.alphanumerics.contains(UnicodeScalar(text.character(at: position)) ?? " ")
            position = max(NSMaxRange(word), navigator.right(from: position))
            if isWord { break }
        }
        return position
    }

    private func wordLeft(from offset: Int) -> Int {
        var position = offset
        while position > 0 {
            let previous = navigator.left(from: position)
            let word = navigator.word(at: previous)
            let isWord = word.length > 1 || CharacterSet.alphanumerics.contains(UnicodeScalar(text.character(at: previous)) ?? " ")
            position = min(word.location, previous)
            if isWord { break }
        }
        return position
    }

    // Read-only: typing and deleting just beep.
    override func insertText(_ insertString: Any) { NSSound.beep() }
    override func deleteBackward(_ sender: Any?) { NSSound.beep() }
    override func deleteForward(_ sender: Any?) { NSSound.beep() }
    override func insertNewline(_ sender: Any?) { NSSound.beep() }
    override func doCommand(by selector: Selector) {
        if responds(to: selector) { perform(selector, with: nil) } else { super.doCommand(by: selector) }
    }

    // MARK: Copy & find

    @objc func copy(_ sender: Any?) {
        writeSelection(to: .general)
    }

    func writeSelection(to pasteboard: NSPasteboard) {
        guard selection.length > 0 else { return }
        pasteboard.clearContents()
        pasteboard.setString(text.substring(with: selection), forType: .string)
    }

    @objc func performFindPanelAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag,
              let action = NSTextFinder.Action(rawValue: tag) else { return }
        findController?.perform(action)
    }

    override func centerSelectionInVisibleArea(_ sender: Any?) {
        let caret = caretRect(for: selection.location)
        scroll(NSPoint(x: visibleRect.minX, y: caret.midY - visibleRect.height / 2))
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)): return selection.length > 0
        case #selector(performFindPanelAction(_:)):
            guard let action = NSTextFinder.Action(rawValue: item.tag), let findController else { return false }
            return findController.validate(action)
        case #selector(NSText.paste(_:)), #selector(NSText.cut(_:)), #selector(NSText.delete(_:)):
            return false
        default:
            return true
        }
    }

    // MARK: Find

    var isEditable: Bool { false }

    func scrollRangeToVisible(_ range: NSRange) {
        let start = caretRect(for: range.location)
        // Put the match a third of the way down rather than at the very edge.
        let target = NSRect(x: start.minX, y: start.minY - visibleRect.height / 3, width: 1, height: visibleRect.height / 3 * 2)
        scrollToVisible(target.insetBy(dx: -layout.charWidth * 8, dy: 0))
    }
}

extension LargeTextView: FindTarget {
    var findText: NSString { text }
    var findLength: Int { model.storage.length }
    func findSubstring(_ range: NSRange) -> String { text.substring(with: range) }
    var findSelection: NSRange { selection }
    var canReplaceFound: Bool { false }

    func selectFound(_ range: NSRange, indicate: Bool) {
        anchor = NSRange(location: range.location, length: 0)
        setSelection(range, scroll: false)
        if indicate { scrollRangeToVisible(range) }
    }

    func replaceFound(_ range: NSRange, with text: String, actionName: String) -> Bool { false }
}
