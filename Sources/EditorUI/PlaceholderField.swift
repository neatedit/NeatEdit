import AppKit
import EditorCore

/// A numbered placeholder chip inside a find/replace field.
final class PlaceholderAttachment: NSTextAttachment {
    let number: Int

    init(number: Int, font: NSFont) {
        self.number = number
        super.init(data: nil, ofType: nil)
        let label = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: font.pointSize - 1, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = label.size(withAttributes: attributes)
        let size = NSSize(width: max(textSize.width + 10, font.pointSize + 5), height: font.pointSize + 3)
        image = NSImage(size: size, flipped: false) { rect in
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            label.draw(at: NSPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2),
                       withAttributes: attributes)
            return true
        }
        bounds = NSRect(origin: NSPoint(x: 0, y: font.descender + 0.5), size: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// A one-line text field that can hold placeholder chips between pieces of text.
final class PlaceholderField: NSTextView {
    var onChange: (() -> Void)?
    var onCommit: ((_ backwards: Bool) -> Void)?
    var onCancel: (() -> Void)?
    weak var findController: FindController?
    var placeholder = "" { didSet { needsDisplay = true } }
    /// The bordered scroll view the field lives in; add this to the layout.
    private(set) var box: NSScrollView!

    static let fieldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    static func make() -> PlaceholderField {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 2
        layoutManager.addTextContainer(container)

        let field = PlaceholderField(frame: NSRect(x: 0, y: 0, width: 200, height: 22), textContainer: container)
        field.isRichText = false
        field.importsGraphics = false
        field.allowsUndo = true
        field.isHorizontallyResizable = true
        field.isVerticallyResizable = false
        field.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 22)
        field.textContainerInset = NSSize(width: 2, height: 3)
        field.isAutomaticQuoteSubstitutionEnabled = false
        field.isAutomaticDashSubstitutionEnabled = false
        field.isAutomaticTextReplacementEnabled = false
        field.isAutomaticSpellingCorrectionEnabled = false
        field.isContinuousSpellCheckingEnabled = false
        field.smartInsertDeleteEnabled = false
        field.font = fieldFont
        field.typingAttributes = Self.textAttributes

        let box = NSScrollView()
        box.borderType = .bezelBorder
        box.hasVerticalScroller = false
        box.hasHorizontalScroller = false
        box.documentView = field
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 24).isActive = true
        field.box = box
        return field
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: fieldFont, .foregroundColor: NSColor.textColor]
    }

    var tokens: [FindToken] {
        get {
            guard let storage = textStorage else { return [] }
            var tokens: [FindToken] = []
            var text = ""
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if let chip = value as? PlaceholderAttachment {
                    if !text.isEmpty { tokens.append(.text(text)); text = "" }
                    // One attachment character per chip, even if runs merge.
                    for _ in 0..<range.length { tokens.append(.placeholder(chip.number)) }
                } else {
                    text += storage.attributedSubstring(from: range).string.replacingOccurrences(of: "\u{FFFC}", with: "")
                }
            }
            if !text.isEmpty { tokens.append(.text(text)) }
            return tokens
        }
        set {
            let result = NSMutableAttributedString()
            for token in newValue {
                switch token {
                case .text(let text): result.append(NSAttributedString(string: text, attributes: Self.textAttributes))
                case .placeholder(let number): result.append(chip(number))
                }
            }
            textStorage?.setAttributedString(result)
            setSelectedRange(NSRange(location: result.length, length: 0))
            needsDisplay = true
        }
    }

    var placeholderNumbers: [Int] {
        tokens.compactMap { if case .placeholder(let n) = $0 { n } else { nil } }
    }

    func insertPlaceholder(_ number: Int) {
        let range = selectedRange()
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: "\u{FFFC}") else { return }
        storage.replaceCharacters(in: range, with: chip(number))
        didChangeText()
        setSelectedRange(NSRange(location: range.location + 1, length: 0))
        typingAttributes = Self.textAttributes
    }

    private func chip(_ number: Int) -> NSAttributedString {
        let string = NSMutableAttributedString(attachment: PlaceholderAttachment(number: number, font: Self.fieldFont))
        string.addAttributes(Self.textAttributes, range: NSRange(location: 0, length: string.length))
        return string
    }

    func selectAllText() { setSelectedRange(NSRange(location: 0, length: textStorage?.length ?? 0)) }

    // MARK: Keys

    override func didChangeText() {
        super.didChangeText()
        typingAttributes = Self.textAttributes
        onChange?()
    }

    override func insertNewline(_ sender: Any?) {
        onCommit?(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) { insertNewline(sender) }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func insertTab(_ sender: Any?) { window?.makeFirstResponder(nextKeyView) }
    override func insertBacktab(_ sender: Any?) { window?.makeFirstResponder(previousKeyView) }

    // ⌘G and friends keep working while typing in the bar.
    override func performFindPanelAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag,
              let action = NSTextFinder.Action(rawValue: tag) else { return }
        findController?.perform(action)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performFindPanelAction(_:)) { return findController != nil }
        return super.validateMenuItem(menuItem)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        (placeholder as NSString).draw(
            at: NSPoint(x: textContainerInset.width + 2, y: textContainerInset.height),
            withAttributes: [.font: Self.fieldFont, .foregroundColor: NSColor.placeholderTextColor])
    }
}
