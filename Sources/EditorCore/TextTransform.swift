import Foundation

/// The Text menu's conversions. Each turns a piece of text into another;
/// the editor decides which piece (the selection, or the whole document).
public enum TextTransform: CaseIterable, Sendable {
    case uppercase, lowercase, titleCase
    case sortLines, removeDuplicateLines, removeEmptyLines, trimTrailingWhitespace, joinLines, unwrapLines
    case tabsToSpaces, spacesToTabs
    case formatJSON, minifyJSON
    case base64Encode, base64Decode, urlEncode, urlDecode

    /// Why the text couldn't be converted, worded for the status bar.
    public struct Failure: Error, Equatable {
        public let message: String
    }

    public static let defaultTabWidth = 4

    public var title: String {
        switch self {
        case .uppercase: "UPPERCASE"
        case .lowercase: "lowercase"
        case .titleCase: "Title Case"
        case .sortLines: "Sort Lines"
        case .removeDuplicateLines: "Remove Duplicate Lines"
        case .removeEmptyLines: "Remove Empty Lines"
        case .trimTrailingWhitespace: "Trim Trailing Whitespace"
        case .joinLines: "Join Lines"
        case .unwrapLines: "Unwrap Lines"
        case .tabsToSpaces: "Tabs to Spaces"
        case .spacesToTabs: "Spaces to Tabs"
        case .formatJSON: "Format JSON"
        case .minifyJSON: "Minify JSON"
        case .base64Encode: "Base64 Encode"
        case .base64Decode: "Base64 Decode"
        case .urlEncode: "URL Encode"
        case .urlDecode: "URL Decode"
        }
    }

    /// Line transforms get whole lines even when the selection starts or
    /// ends mid-line.
    public var worksOnWholeLines: Bool {
        switch self {
        case .sortLines, .removeDuplicateLines, .removeEmptyLines, .trimTrailingWhitespace, .joinLines, .unwrapLines,
             .tabsToSpaces, .spacesToTabs:
            true
        default:
            false
        }
    }

    public func apply(to text: String, tabWidth: Int = defaultTabWidth) throws -> String {
        switch self {
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .titleCase: return text.capitalized
        case .sortLines:
            return Self.lines(text).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
        case .removeDuplicateLines:
            var seen = Set<Substring>()
            return Self.lines(text).filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .removeEmptyLines:
            return Self.lines(text).filter { !$0.allSatisfy(Self.isBlank) }.joined(separator: "\n")
        case .trimTrailingWhitespace:
            return Self.lines(text).map(Self.trimmingTrailing).joined(separator: "\n")
        case .joinLines:
            let lines = Self.lines(text).enumerated().map { i, line in
                Self.trimmingTrailing(i == 0 ? line : line.drop(while: Self.isBlank))
            }
            return lines.filter { !$0.isEmpty }.joined(separator: " ")
        case .unwrapLines: return TextUnwrap.unwrap(text)
        case .tabsToSpaces:
            return Self.lines(text).map { Self.expandingTabs($0, tabWidth: tabWidth) }.joined(separator: "\n")
        case .spacesToTabs:
            return Self.lines(text).map { Self.tabbingIndent($0, tabWidth: tabWidth) }.joined(separator: "\n")
        case .formatJSON: return try Self.keepingSurroundingWhitespace(text) { try JSONLayout.reformat($0, pretty: true) }
        case .minifyJSON: return try Self.keepingSurroundingWhitespace(text) { try JSONLayout.reformat($0, pretty: false) }
        case .base64Encode:
            return Self.keepingSurroundingWhitespace(text) { Data($0.utf8).base64EncodedString() }
        case .base64Decode: return try Self.keepingSurroundingWhitespace(text, Self.base64Decoded)
        case .urlEncode:
            return Self.keepingSurroundingWhitespace(text) {
                $0.addingPercentEncoding(withAllowedCharacters: Self.urlUnreserved) ?? $0
            }
        case .urlDecode:
            return try Self.keepingSurroundingWhitespace(text) {
                guard let decoded = $0.removingPercentEncoding else { throw Failure(message: "Not valid URL encoding") }
                return decoded
            }
        }
    }

    // MARK: Helpers

    private static func lines(_ text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    private static func isBlank(_ c: Character) -> Bool { c.isWhitespace && !c.isNewline }

    private static func trimmingTrailing(_ line: Substring) -> String {
        var line = line
        while let last = line.last, isBlank(last) { line = line.dropLast() }
        return String(line)
    }

    private static func expandingTabs(_ line: Substring, tabWidth: Int) -> String {
        var out = ""
        var column = 0
        for c in line {
            if c == "\t" {
                let spaces = tabWidth - column % tabWidth
                out += String(repeating: " ", count: spaces)
                column += spaces
            } else {
                out.append(c)
                column += 1
            }
        }
        return out
    }

    /// Only the indentation: spaces inside a line are usually alignment.
    private static func tabbingIndent(_ line: Substring, tabWidth: Int) -> String {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
        var column = 0
        for c in indent { column = c == "\t" ? (column / tabWidth + 1) * tabWidth : column + 1 }
        return String(repeating: "\t", count: column / tabWidth) + String(repeating: " ", count: column % tabWidth)
            + line.dropFirst(indent.count)
    }

    /// Converts the text between leading and trailing whitespace, so a
    /// selection (or document) ending in a newline keeps it.
    private static func keepingSurroundingWhitespace(_ text: String, _ convert: (String) throws -> String) rethrows -> String {
        let start = text.firstIndex(where: { !$0.isWhitespace }) ?? text.endIndex
        let end = text.lastIndex(where: { !$0.isWhitespace }).map(text.index(after:)) ?? start
        return String(text[..<start]) + (try convert(String(text[start..<end]))) + String(text[end...])
    }

    private static let urlUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Accepts line-wrapped, URL-safe and unpadded Base64.
    private static func base64Decoded(_ text: String) throws -> String {
        var compact = String(text.filter { !$0.isWhitespace })
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if compact.count % 4 != 0 { compact += String(repeating: "=", count: 4 - compact.count % 4) }
        guard let data = Data(base64Encoded: compact) else { throw Failure(message: "Not valid Base64") }
        guard let decoded = String(data: data, encoding: .utf8) else { throw Failure(message: "Decoded Base64 isn't UTF-8 text") }
        return decoded
    }
}

/// Re-lays out JSON token by token, so key order and number spelling stay
/// exactly as written (JSONSerialization would reorder and reformat them).
enum JSONLayout {
    static func reformat(_ text: String, pretty: Bool) throws -> String {
        do {
            _ = try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
        } catch {
            let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
            throw TextTransform.Failure(message: "Not valid JSON" + (detail.map { ": \($0)" } ?? ""))
        }

        let scalars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var depth = 0
        var inString = false
        var escaped = false
        func newline() {
            guard pretty else { return }
            out.append("\n")
            out.append(contentsOf: String(repeating: "  ", count: depth).unicodeScalars)
        }

        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            defer { i += 1 }
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"":
                inString = true
                out.append(c)
            case "{", "[":
                out.append(c)
                var next = i + 1
                while next < scalars.count, isSpace(scalars[next]) { next += 1 }
                if next < scalars.count, scalars[next] == "}" || scalars[next] == "]" {
                    out.append(scalars[next])
                    i = next
                } else {
                    depth += 1
                    newline()
                }
            case "}", "]":
                depth -= 1
                newline()
                out.append(c)
            case ",":
                out.append(c)
                newline()
            case ":":
                out.append(c)
                if pretty { out.append(" ") }
            default:
                if !isSpace(c) { out.append(c) }
            }
        }
        return String(out)
    }

    private static func isSpace(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" || c == "\n" || c == "\r" }
}
