import Foundation

/// A piece of the Find or Replace field: typed text or a numbered placeholder chip.
public enum FindToken: Equatable, Sendable {
    case text(String)
    case placeholder(Int)
}

public struct FindOptions: Equatable, Sendable {
    public var caseSensitive: Bool
    /// Text tokens are regular expressions and Replace text is a `$1` template.
    public var regex: Bool

    public init(caseSensitive: Bool = false, regex: Bool = false) {
        self.caseSensitive = caseSensitive
        self.regex = regex
    }
}

public enum FindError: Error, Equatable {
    case emptyPattern
    case invalidPattern(String)
}

/// Coda-style find & replace: each placeholder in Find matches any text on the
/// line (lazily; a trailing one takes the rest of the line) and the same number
/// in Replace inserts what it matched. Placeholders compile to named groups, so
/// they work in regex mode too without disturbing the user's `$1` groups.
public struct FindQuery {
    public let options: FindOptions
    let regex: NSRegularExpression
    private let replace: [FindToken]

    public init(find: [FindToken], replace: [FindToken] = [], options: FindOptions = FindOptions()) throws {
        guard find.contains(where: { $0 != .text("") }) else { throw FindError.emptyPattern }
        var pattern = ""
        var seen = Set<Int>()
        for (index, token) in find.enumerated() {
            switch token {
            case .text(let text):
                pattern += options.regex ? text : NSRegularExpression.escapedPattern(for: text)
            case .placeholder(let number) where seen.contains(number):
                pattern += "\\k<p\(number)>"
            case .placeholder(let number):
                seen.insert(number)
                let isLast = find[(index + 1)...].allSatisfy { $0 == .text("") }
                pattern += "(?<p\(number)>.*\(isLast ? "" : "?"))"
            }
        }
        var regexOptions: NSRegularExpression.Options = [.anchorsMatchLines]
        if !options.caseSensitive { regexOptions.insert(.caseInsensitive) }
        do {
            regex = try NSRegularExpression(pattern: pattern, options: regexOptions)
        } catch {
            throw FindError.invalidPattern(pattern)
        }
        self.replace = replace
        self.options = options
    }

    private static let matching: NSRegularExpression.MatchingOptions = [.withTransparentBounds, .withoutAnchoringBounds]

    /// Calls `body` for every usable match in `range`; return false to stop.
    private func forEachMatch(in text: NSString, range: NSRange, _ body: (NSTextCheckingResult) -> Bool) {
        guard range.length >= 0, range.location != NSNotFound else { return }
        regex.enumerateMatches(in: text as String, options: Self.matching, range: range) { result, _, stop in
            guard let result else { return }
            // Without regex mode an empty match is never what the user meant.
            if result.range.length == 0 && !options.regex { return }
            if !body(result) { stop.pointee = true }
        }
    }

    public func count(in text: NSString, scope: NSRange) -> Int {
        var count = 0
        forEachMatch(in: text, range: scope) { _ in count += 1; return true }
        return count
    }

    /// The first match after `selection` (the selection itself excluded), wrapping to the scope start.
    public func next(in text: NSString, after selection: NSRange, scope: NSRange, wraps: Bool = true) -> NSTextCheckingResult? {
        let start = min(max(selection.upperBound, scope.location), scope.upperBound)
        if let match = first(in: text, range: NSRange(location: start, length: scope.upperBound - start), excluding: selection) {
            return match
        }
        return wraps ? first(in: text, range: scope, excluding: selection) : nil
    }

    /// The last match before `selection`, wrapping to the scope end.
    public func previous(in text: NSString, before selection: NSRange, scope: NSRange, wraps: Bool = true) -> NSTextCheckingResult? {
        let end = min(max(selection.location, scope.location), scope.upperBound)
        if let match = last(in: text, range: NSRange(location: scope.location, length: end - scope.location), excluding: selection) {
            return match
        }
        return wraps ? last(in: text, range: scope, excluding: selection) : nil
    }

    /// The match that covers exactly `selection`, if the selection is one.
    public func match(at selection: NSRange, in text: NSString, scope: NSRange) -> NSTextCheckingResult? {
        guard selection.location >= scope.location, selection.upperBound <= scope.upperBound else { return nil }
        guard let match = regex.firstMatch(in: text as String, options: Self.matching.union(.anchored), range: selection),
              match.range == selection, match.range.length > 0 || options.regex else { return nil }
        return match
    }

    /// Every match in `scope` with its replacement, in ascending order.
    public func replaceAll(in text: NSString, scope: NSRange) -> [(range: NSRange, replacement: String)] {
        var edits: [(range: NSRange, replacement: String)] = []
        forEachMatch(in: text, range: scope) { result in
            edits.append((result.range, replacement(for: result, in: text)))
            return true
        }
        return edits
    }

    public func replacement(for match: NSTextCheckingResult, in text: NSString) -> String {
        var output = ""
        for token in replace {
            switch token {
            case .placeholder(let number):
                if let range = captured(named: "p\(number)", in: match) { output += text.substring(with: range) }
            case .text(let string):
                output += options.regex ? expand(template: string, match: match, in: text) : string
            }
        }
        return output
    }

    private func captured(named name: String, in match: NSTextCheckingResult) -> NSRange? {
        // range(withName:) raises for names the pattern does not define.
        guard regex.pattern.contains("(?<\(name)>") else { return nil }
        let range = match.range(withName: name)
        return range.location == NSNotFound ? nil : range
    }

    /// `$n` inserts group n, `\x` is a literal x — the same rules as NSRegularExpression templates.
    private func expand(template: String, match: NSTextCheckingResult, in text: NSString) -> String {
        var output = ""
        var chars = template[...]
        while let char = chars.popFirst() {
            if char == "\\", let escaped = chars.popFirst() {
                output.append(escaped)
            } else if char == "$", let digit = chars.first?.wholeNumberValue {
                chars.removeFirst()
                var group = digit
                // Take more digits while they still name an existing group.
                while let next = chars.first?.wholeNumberValue, group * 10 + next < match.numberOfRanges {
                    group = group * 10 + next
                    chars.removeFirst()
                }
                if group < match.numberOfRanges, match.range(at: group).location != NSNotFound {
                    output += text.substring(with: match.range(at: group))
                }
            } else {
                output.append(char)
            }
        }
        return output
    }

    private func first(in text: NSString, range: NSRange, excluding selection: NSRange) -> NSTextCheckingResult? {
        var found: NSTextCheckingResult?
        forEachMatch(in: text, range: range) { result in
            guard result.range != selection else { return true }
            found = result
            return false
        }
        return found
    }

    private func last(in text: NSString, range: NSRange, excluding selection: NSRange) -> NSTextCheckingResult? {
        var found: NSTextCheckingResult?
        forEachMatch(in: text, range: range) { result in
            if result.range != selection { found = result }
            return true
        }
        return found
    }
}
