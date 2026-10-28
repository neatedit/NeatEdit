import AppKit

/// App-wide settings kept in UserDefaults. Changes are broadcast so every
/// open tab follows along.
public enum Preferences {
    public static let didChange = Notification.Name("SimpleTextEditPreferencesDidChange")

    private static let fontSizeKey = "fontSize"
    private static let wrapKey = "wrapLines"
    static let defaultFontSize: CGFloat = 13

    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            fontSizeKey: Double(defaultFontSize),
            wrapKey: true,
            // Reopen every tab (including unsaved scratch tabs) after quitting,
            // regardless of the system "close windows when quitting" setting.
            "NSQuitAlwaysKeepsWindows": true,
        ])
    }

    public static var fontSize: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: fontSizeKey)).clamped(to: 8...48, default: defaultFontSize) }
        set { set(Double(newValue.clamped(to: 8...48, default: defaultFontSize)), forKey: fontSizeKey) }
    }

    public static var wrapsLines: Bool {
        get { UserDefaults.standard.bool(forKey: wrapKey) }
        set { set(newValue, forKey: wrapKey) }
    }

    public static var font: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private static func set(_ value: Any, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>, default fallback: CGFloat) -> CGFloat {
        self == 0 ? fallback : Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
