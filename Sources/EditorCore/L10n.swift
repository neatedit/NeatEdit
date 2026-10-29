import Foundation

/// User-visible text. The key is the English text itself; translations live
/// in the app's <language>.lproj/Localizable.strings (Resources/Localization).
/// Counts go in as "%ld" and pre-formatted numbers as "%@", and translations
/// avoid plural-dependent wording ("Matches: 5" rather than "5 matches").
public enum L10n {
    /// Where the .lproj folders are: the app bundle (tests may point elsewhere).
    nonisolated(unsafe) public static var bundle = Bundle.main

    public static func tr(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    public static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), arguments: arguments)
    }
}
