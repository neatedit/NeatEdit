import AppKit
import EditorCore

/// Gutter with logical line numbers. Only lines starting in the visible rect
/// are looked at, so it costs the same on a 5-line and a 20 MB document.
/// `firstLine` is the number of lines before the text, for a piece of a bigger file.
final class LineNumberRuler: NSRulerView {
    private weak var textView: PlainTextView?
    private let lineIndex: () -> LineIndex
    private let firstLine: Int
    private var digits = 0
    private var measuredSize: CGFloat = 0

    init(textView: PlainTextView, firstLine: Int = 0, lineIndex: @escaping () -> LineIndex) {
        self.textView = textView
        self.lineIndex = lineIndex
        self.firstLine = firstLine
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        clipsToBounds = true  // numbers past the last row stay inside the scroll view
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange), name: NSText.didChangeNotification, object: textView)
        updateThickness()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    private var labelFont: NSFont {
        let font = Preferences.font
        return NSFont(descriptor: font.fontDescriptor, size: max(font.pointSize - 2, 8)) ?? font
    }

    @objc private func textDidChange() {
        updateThickness()
        needsDisplay = true
    }

    /// Room for the widest number (at least two digits) plus padding.
    func updateThickness() {
        let count = max(String(firstLine + lineIndex().lineCount).count, 2)
        let font = labelFont
        guard count != digits || font.pointSize != measuredSize || ruleThickness == 0 else { return }
        digits = count
        measuredSize = font.pointSize
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        ruleThickness = ceil(CGFloat(count) * digitWidth + 12)
    }

    /// 1-based numbers of lines whose first character is on screen, with the
    /// top of that line in text view coordinates.
    func visibleNumbers() -> [(line: Int, y: CGFloat)] {
        guard let textView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return [] }
        let index = lineIndex()
        let starts = index.starts
        let length = layoutManager.textStorage?.length ?? 0
        let glyphs = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let chars = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)

        var line = index.line(containing: chars.location)
        if starts[line] < chars.location { line += 1 }  // its number is above the view
        var result: [(line: Int, y: CGFloat)] = []
        while line < starts.count, starts[line] <= NSMaxRange(chars) {
            let start = starts[line]
            let rect = start < length
                ? layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
                : layoutManager.extraLineFragmentRect
            result.append((firstLine + line + 1, rect.minY + textView.textContainerOrigin.y))
            line += 1
        }
        return result
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView else { return }
        updateThickness()
        let font = labelFont
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let lineHeight = textView.layoutManager?.defaultLineHeight(for: Preferences.font) ?? font.pointSize
        for (line, y) in visibleNumbers() {
            let label = String(line) as NSString
            let size = label.size(withAttributes: attributes)
            let top = convert(NSPoint(x: 0, y: y), from: textView).y
            label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: top + (lineHeight - size.height) / 2),
                       withAttributes: attributes)
        }
    }
}
