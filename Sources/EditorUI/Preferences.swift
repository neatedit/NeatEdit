import AppKit

/// App-wide settings kept in UserDefaults. Changes are broadcast so every
/// open tab follows along.
public enum Preferences {
    public static let didChange = Notification.Name("NeatEditPreferencesDidChange")

    /// Swappable so tests don't touch the user's settings.
    static var defaults = UserDefaults.standard

    private static let fontSizeKey = "fontSize"
    private static let fontNameKey = "fontName"
    private static let wrapKey = "wrapLines"
    private static let lineNumbersKey = "showLineNumbers"
    private static let viewerLineNumbersKey = "viewerShowLineNumbers"
    private static let unwrapPasteKey = "unwrapPastedText"
    private static let invisiblesKey = "showInvisibles"
    private static let currentLineKey = "highlightCurrentLine"
    static let defaultFontSize: CGFloat = 13

    public static func registerDefaults() {
        defaults.register(defaults: [
            fontSizeKey: Double(defaultFontSize),
            wrapKey: false,
            lineNumbersKey: false,
            viewerLineNumbersKey: true,
            unwrapPasteKey: true,
            invisiblesKey: false,
            currentLineKey: true,
        ])
        // Reopen every tab (including unsaved scratch tabs) after quitting,
        // regardless of the system "close windows when quitting" setting.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": true])
    }

    public static var fontSize: CGFloat {
        get { CGFloat(defaults.double(forKey: fontSizeKey)).clamped(to: 8...48, default: defaultFontSize) }
        set { set(Double(newValue.clamped(to: 8...48, default: defaultFontSize)), forKey: fontSizeKey) }
    }

    /// PostScript name of the chosen font; nil means the system monospaced font.
    public static var fontName: String? {
        get { defaults.string(forKey: fontNameKey) }
        set { set(newValue, forKey: fontNameKey) }
    }

    public static var wrapsLines: Bool {
        get { defaults.bool(forKey: wrapKey) }
        set { set(newValue, forKey: wrapKey) }
    }

    public static var showsLineNumbers: Bool {
        get { defaults.bool(forKey: lineNumbersKey) }
        set { set(newValue, forKey: lineNumbersKey) }
    }

    /// The large file viewer's own setting: a log is read by its line numbers.
    public static var viewerShowsLineNumbers: Bool {
        get { defaults.bool(forKey: viewerLineNumbersKey) }
        set { set(newValue, forKey: viewerLineNumbersKey) }
    }

    /// Marks for spaces, tabs and line ends.
    public static var showsInvisibles: Bool {
        get { defaults.bool(forKey: invisiblesKey) }
        set { set(newValue, forKey: invisiblesKey) }
    }

    /// A soft band behind the caret's line.
    public static var highlightsCurrentLine: Bool {
        get { defaults.bool(forKey: currentLineKey) }
        set { set(newValue, forKey: currentLineKey) }
    }

    /// Undo terminal hard wrapping in pasted text (as its own undo step).
    public static var unwrapsPastedText: Bool {
        get { defaults.bool(forKey: unwrapPasteKey) }
        set { set(newValue, forKey: unwrapPasteKey) }
    }

    /// Only fixed-pitch fonts: the large file viewer lays text out on a grid.
    public static var font: NSFont {
        if let fontName, let font = NSFont(name: fontName, size: fontSize), font.isFixedPitch {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// Takes face and size from the font panel; proportional fonts are ignored.
    static func adoptFontPanelChoice(_ font: NSFont) {
        guard font.isFixedPitch else { NSSound.beep(); return }
        fontName = font.fontName
        fontSize = font.pointSize
    }

    /// Opens the standard font panel on the current font.
    static func showFontPanel() {
        NSFontManager.shared.setSelectedFont(font, isMultiple: false)
        NSFontManager.shared.orderFrontFontPanel(nil)
    }

    private static func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>, default fallback: CGFloat) -> CGFloat {
        self == 0 ? fallback : Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
