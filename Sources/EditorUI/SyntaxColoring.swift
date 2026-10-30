import AppKit
import EditorCore

/// Colours a text view's language with temporary attributes: never in the
/// storage, so they can't reach the file, the undo stack or a print. The whole
/// text is scanned off the main thread after an edit, one scan at a time; only
/// what's near the screen gets coloured.
@MainActor
final class SyntaxColoring {
    /// Longer text stays plain: a scan per edit would start to show.
    static var lengthLimit = 2_000_000
    /// Characters coloured each way from the top of the screen at most: one
    /// huge line is all "on screen" as far as layout goes, and each token costs.
    private static let reach = 20_000
    private static let delay: TimeInterval = 0.05

    private weak var textView: PlainTextView?
    private let scrollView: NSScrollView
    private var tokens: [SyntaxToken] = []
    /// `tokens` describe the text as it is now.
    private var tokensAreCurrent = false
    private var generation = 0
    private var coloredRange = NSRange(location: 0, length: 0)
    private var hasColors = false
    private var scanScheduled = false
    private var isScanning = false
    private var coloringScheduled = false

    /// Nil, or off in the View menu: no colours.
    var language: SyntaxLanguage? {
        didSet { if language != oldValue { textDidChange() } }
    }

    init(textView: PlainTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        textView.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(viewChanged), name: NSView.boundsDidChangeNotification, object: clip)
        center.addObserver(self, selector: #selector(viewChanged), name: NSView.frameDidChangeNotification, object: clip)
        center.addObserver(self, selector: #selector(viewChanged), name: NSView.frameDidChangeNotification, object: textView)
    }

    /// Colours are stale from now on; a new scan comes shortly.
    func textDidChange() {
        generation += 1
        tokensAreCurrent = false
        guard language != nil || hasColors else { return }  // a plain file costs nothing
        scheduleScan()
    }

    private func scheduleScan() {
        guard !scanScheduled else { return }
        scanScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay) { [weak self] in
            MainActor.assumeIsolated {
                self?.scanScheduled = false
                self?.scan()
            }
        }
    }

    private func scan() {
        guard !isScanning, !tokensAreCurrent, let storage = textView?.textStorage else { return }
        guard let language, storage.length <= Self.lengthLimit else {
            install([])
            return
        }
        isScanning = true
        let generation = generation
        let text = storage.string
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tokens = language.tokens(in: text)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isScanning = false
                    if self.generation == generation { self.install(tokens) } else { self.scheduleScan() }
                }
            }
        }
    }

    private func install(_ newTokens: [SyntaxToken]) {
        tokens = newTokens
        tokensAreCurrent = true
        coloredRange = NSRange(location: 0, length: 0)
        if tokens.isEmpty { clearAll() } else { colorVisible() }
    }

    private func clearAll() {
        guard hasColors, let layoutManager = textView?.layoutManager, let length = textView?.textStorage?.length else { return }
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        hasColors = false
    }

    /// Scrolled or resized, possibly in the middle of layout: colour once it's done.
    @objc private func viewChanged() {
        guard tokensAreCurrent, !tokens.isEmpty, !coloringScheduled else { return }
        coloringScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.coloringScheduled = false
                self?.colorVisible()
            }
        }
    }

    private func colorVisible() {
        // Old tokens would paint the wrong places.
        guard tokensAreCurrent, !tokens.isEmpty, let textView, let range = rangeToColor(in: textView),
              NSIntersectionRange(range, coloredRange) != range || range.length == 0 else { return }
        guard let layoutManager = textView.layoutManager else { return }
        coloredRange = range
        hasColors = true
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        for token in tokens(in: range) {
            let clipped = NSIntersectionRange(token.range, range)
            if clipped.length > 0 {
                layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.syntax(token.kind), forCharacterRange: clipped)
            }
        }
    }

    /// What's on screen and a screen each way, so a scroll starts out coloured.
    private func rangeToColor(in textView: PlainTextView) -> NSRange? {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let length = textView.textStorage?.length else { return nil }
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible.insetBy(dx: 0, dy: -visible.height), in: container)
        let all = NSIntersectionRange(layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil),
                                      NSRange(location: 0, length: length))
        guard all.length > 2 * Self.reach else { return all }
        // The screen's top row: below the last row there's only the text's end.
        let top = NSPoint(x: visible.midX - origin.x, y: max(visible.minY - origin.y, 0))
        let center = layoutManager.characterIndexForGlyph(at: layoutManager.glyphIndex(for: top, in: container))
        let start = max(center - Self.reach, 0)
        return NSRange(location: start, length: min(2 * Self.reach, length - start))
    }

    private func tokens(in range: NSRange) -> ArraySlice<SyntaxToken> {
        // The first token ending after the range starts: they're in order.
        var low = 0, high = tokens.count
        while low < high {
            let middle = (low + high) / 2
            if NSMaxRange(tokens[middle].range) <= range.location { low = middle + 1 } else { high = middle }
        }
        var end = low
        while end < tokens.count, tokens[end].range.location < NSMaxRange(range) { end += 1 }
        return tokens[low..<end]
    }

    /// The colour at `offset`, for tests.
    func color(at offset: Int) -> NSColor? {
        textView?.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: offset, effectiveRange: nil) as? NSColor
    }
}

extension NSColor {
    static func syntax(_ kind: SyntaxKind) -> NSColor {
        switch kind {
        case .keyword: .systemPurple
        case .string: .systemRed
        case .comment: .systemGray
        case .number: .systemOrange
        case .variable: .systemTeal
        case .key: .systemBlue
        case .tag: .systemBlue
        case .heading: .systemBlue
        case .emphasis: .systemOrange
        case .code: .systemBrown
        case .link: .systemTeal
        }
    }
}
