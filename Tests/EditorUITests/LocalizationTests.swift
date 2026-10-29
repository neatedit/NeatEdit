import Foundation
import XCTest
@testable import EditorCore
@testable import EditorUI

/// Every text the code shows has an English entry, and every language has
/// exactly the English keys with the same placeholders.
final class LocalizationTests: XCTestCase {
    static let languages = [
        "bg", "cs", "da", "de", "el", "es", "et", "fi", "fr", "ga", "hr", "hu",
        "it", "lt", "lv", "mt", "nl", "pl", "pt-PT", "ro", "sk", "sl", "sv", "uk",
    ]

    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private var localization: URL { root.appendingPathComponent("Resources/Localization") }

    private func table(_ language: String) throws -> [String: String] {
        let url = localization.appendingPathComponent("\(language).lproj/Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "\(language) is missing or doesn't parse")
    }

    /// Keys the sources pass to L10n: tr("…") calls, menu builder titles and the Text menu.
    private func keysInSources() throws -> Set<String> {
        var keys = Set(TextTransform.allCases.map(\.englishTitle))
        let sources = root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        let call = try NSRegularExpression(pattern: #"L10n\.tr\("((?:[^"\\]|\\.)*)""#)
        let menu = try NSRegularExpression(pattern: #"\b(?:item|submenu|find|addSubmenu)\("((?:[^"\\]|\\.)*)""#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            var patterns = [call]
            if file.lastPathComponent == "AppDelegate.swift" { patterns.append(menu) }
            for pattern in patterns {
                for match in pattern.matches(in: text, range: range) {
                    keys.insert(String(text[Range(match.range(at: 1), in: text)!]))
                }
            }
        }
        return keys
    }

    /// "%ld", "%@" and their positional forms ("%2$@"), in any order.
    private func placeholders(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(@|ld|d)"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { (text as NSString).substring(with: $0.range(at: 1)) }.sorted()
    }

    func testEnglishCoversExactlyWhatTheCodeShows() throws {
        let english = Set(try table("en").keys)
        let used = try keysInSources()
        XCTAssertEqual(used.subtracting(english).sorted(), [], "add these to en.lproj")
        XCTAssertEqual(english.subtracting(used).sorted(), [], "no longer used")
    }

    func testEveryLanguageHasTheEnglishKeysAndPlaceholders() throws {
        let english = try table("en")
        for language in Self.languages {
            let strings = try table(language)
            XCTAssertEqual(Set(strings.keys), Set(english.keys), language)
            for (key, value) in strings {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language): \(key)")
                XCTAssertEqual(placeholders(value), placeholders(key), "\(language): \(key) → \(value)")
            }
        }
    }

    func testLookupGoesThroughTheBundle() throws {
        let saved = L10n.bundle
        defer { L10n.bundle = saved }
        let bundle = try XCTUnwrap(Bundle(path: localization.appendingPathComponent("uk.lproj").path))
        L10n.bundle = bundle
        XCTAssertEqual(L10n.tr("Not found"), try table("uk")["Not found"])
        XCTAssertEqual(L10n.tr("%ld of %ld", 2, 5), String(format: try table("uk")["%ld of %ld"]!, 2, 5))
        XCTAssertEqual(L10n.tr("No such key"), "No such key")
    }
}
