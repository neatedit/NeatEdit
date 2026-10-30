import Foundation

public enum SyntaxKind: Sendable, CaseIterable {
    case keyword, string, comment, number, variable, key, tag, heading, emphasis, code, link
}

public struct SyntaxToken: Equatable, Sendable {
    public let range: NSRange
    public let kind: SyntaxKind

    public init(_ kind: SyntaxKind, _ range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

/// A language, picked by file name, and a small scanner for it: enough to
/// colour comments, strings, numbers and keywords, not to parse anything.
public struct SyntaxLanguage: Equatable, Sendable {
    public let name: String
    fileprivate let grammar: Grammar

    public static func detect(fileName: String) -> SyntaxLanguage? {
        let name = fileName.lowercased()
        if shellFileNames.contains(name) { return shell }
        let ext = (name as NSString).pathExtension
        return all.first { $0.extensions.contains(ext) }?.language
    }

    /// Sorted by location, not overlapping.
    public func tokens(in text: String) -> [SyntaxToken] {
        var scanner = SyntaxScanner(text)
        scanner.scan(grammar)
        return scanner.tokens
    }

    public static let json = SyntaxLanguage(name: "JSON", grammar: .json)
    public static let markdown = SyntaxLanguage(name: "Markdown", grammar: .markdown)
    public static let yaml = SyntaxLanguage(name: "YAML", grammar: .yaml)
    public static let html = SyntaxLanguage(name: "HTML", grammar: .html)
    public static let php = SyntaxLanguage(name: "PHP", grammar: .php(CodeRules.php))
    public static let javascript = SyntaxLanguage(name: "JavaScript", grammar: .code(CodeRules.javascript))
    public static let python = SyntaxLanguage(name: "Python", grammar: .code(CodeRules.python))
    public static let css = SyntaxLanguage(name: "CSS", grammar: .code(CodeRules.css))
    public static let shell = SyntaxLanguage(name: "Shell", grammar: .code(CodeRules.shell))
    public static let sql = SyntaxLanguage(name: "SQL", grammar: .code(CodeRules.sql))
    public static let swift = SyntaxLanguage(name: "Swift", grammar: .code(CodeRules.swift))
    public static let cFamily = SyntaxLanguage(name: "C", grammar: .code(CodeRules.cFamily))
    public static let go = SyntaxLanguage(name: "Go", grammar: .code(CodeRules.go))

    private static let shellFileNames: Set<String> = [".bashrc", ".bash_profile", ".zshrc", ".zprofile", ".profile"]

    private static let all: [(extensions: Set<String>, language: SyntaxLanguage)] = [
        (["json", "geojson"], json),
        (["md", "markdown", "mdown"], markdown),
        (["yml", "yaml"], yaml),
        (["html", "htm", "xml", "svg", "plist", "xhtml"], html),
        (["php", "phtml"], php),
        (["js", "jsx", "mjs", "cjs", "ts", "tsx"], javascript),
        (["py", "pyw"], python),
        (["css", "scss"], css),
        (["sh", "bash", "zsh"], shell),
        (["sql"], sql),
        (["swift"], swift),
        (["c", "h", "cc", "cpp", "cxx", "hpp", "m", "mm", "java", "cs"], cFamily),
        (["go"], go),
    ]
}

fileprivate enum Grammar: Equatable, Sendable {
    case json, markdown, yaml, html
    case php(CodeRules)
    case code(CodeRules)
}

fileprivate struct CodeRules: Equatable, Sendable {
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)? = nil
    /// Each ends at its line's end unless it's also in `multilineQuotes`.
    var quotes: [String] = ["\"", "'"]
    var multilineQuotes: [String] = []
    /// A backslash means nothing inside these (shell and SQL single quotes).
    var rawQuotes: [String] = []
    var keywords: Set<String> = []
    var ignoresCase = false
    /// `#` starts a comment only after a space or at a line's start (shell).
    var commentAfterSpace = false
    /// `#[` is an attribute, not a comment (PHP).
    var hashAttributes = false
    /// `$name` is a variable.
    var dollarVariables = false
    /// `@name` (and `#name`, in C) reads as a keyword.
    var atWords = false
    var hashWords = false
    /// Ends the code, unless inside a string or a block comment (PHP's `?>`).
    var closeTag: String? = nil
    /// Inside braces, `name:` is a key and `#abc` a number (CSS).
    var cssBlocks = false

    static func == (a: CodeRules, b: CodeRules) -> Bool {
        a.lineComments == b.lineComments && a.quotes == b.quotes && a.keywords == b.keywords
    }

    private static func words(_ list: String) -> Set<String> { Set(list.split(separator: " ").map(String.init)) }

    static let php = CodeRules(
        lineComments: ["//", "#"], blockComment: ("/*", "*/"), multilineQuotes: ["\"", "'"],
        keywords: words("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enum extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield true false null self parent"),
        ignoresCase: true, hashAttributes: true, dollarVariables: true, closeTag: "?>")

    static let javascript = CodeRules(
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'", "`"], multilineQuotes: ["`"],
        keywords: words("abstract any as async await boolean break case catch class const continue debugger declare default delete do else enum export extends false finally for from function get if implements import in instanceof interface let namespace new null number of private protected public readonly return set static string super switch this throw true try type typeof undefined var void while with yield"),
        atWords: true)

    static let python = CodeRules(
        lineComments: ["#"], quotes: ["\"\"\"", "'''", "\"", "'"], multilineQuotes: ["\"\"\"", "'''"],
        keywords: words("False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda match nonlocal not or pass raise return self try while with yield"),
        atWords: true)

    static let css = CodeRules(blockComment: ("/*", "*/"), keywords: words("important"), atWords: true, cssBlocks: true)

    static let shell = CodeRules(
        lineComments: ["#"], multilineQuotes: ["\"", "'"], rawQuotes: ["'"],
        keywords: words("alias break case cd continue do done echo elif else esac eval exec exit export fi for function if in local read readonly return set shift source then trap unset until while"),
        commentAfterSpace: true, dollarVariables: true)

    static let sql = CodeRules(
        lineComments: ["--"], blockComment: ("/*", "*/"), multilineQuotes: ["'"], rawQuotes: ["'"],
        keywords: words("add all alter and as asc begin between by case check column commit constraint create cross database default delete desc distinct drop else end exists foreign from group having if in index inner insert into is join key left like limit not null offset on or order outer primary references right rollback select set table then transaction union unique update values view when where with"),
        ignoresCase: true)

    static let swift = CodeRules(
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"\"\"", "\""], multilineQuotes: ["\"\"\""],
        keywords: words("actor any as associatedtype async await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate final for func guard if import in init inout internal is let lazy mutating nil nonisolated open override private protocol public repeat rethrows return self Self some static struct subscript super switch throw throws true try typealias var weak where while"),
        atWords: true, hashWords: true)

    static let cFamily = CodeRules(
        lineComments: ["//"], blockComment: ("/*", "*/"),
        keywords: words("abstract auto bool boolean break byte case catch char class const constexpr continue default delete do double else enum explicit extends extern false final finally float for friend goto if implements import inline instanceof int interface long namespace new null nullptr override package private protected public register return short signed sizeof static struct super switch template this throw throws true try typedef typename union unsigned using var virtual void volatile while"),
        atWords: true, hashWords: true)

    static let go = CodeRules(
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'", "`"], multilineQuotes: ["`"],
        keywords: words("any bool break byte case chan const continue default defer else error fallthrough false float64 for func go goto if import int int64 interface iota map nil package range return rune select string struct switch true type uint var"))
}

private struct SyntaxScanner {
    private let c: [UInt16]
    private(set) var tokens: [SyntaxToken] = []

    init(_ text: String) { c = Array(text.utf16) }

    mutating func scan(_ grammar: Grammar) {
        let all = 0..<c.count
        switch grammar {
        case .json: json(all)
        case .markdown: markdown(all)
        case .yaml: yaml(all)
        case .html: html(all)
        case .php(let rules): php(rules)
        case .code(let rules): code(rules, all)
        }
    }

    // MARK: Helpers

    private mutating func emit(_ kind: SyntaxKind, _ start: Int, _ end: Int) {
        if end > start { tokens.append(SyntaxToken(kind, NSRange(location: start, length: end - start))) }
    }

    private func char(_ s: Unicode.Scalar) -> UInt16 { UInt16(s.value) }

    private func matches(_ s: [UInt16], at i: Int, _ end: Int) -> Bool {
        guard i + s.count <= end else { return false }
        for offset in s.indices where c[i + offset] != s[offset] { return false }
        return true
    }

    /// Where `s` starts at or after `i`, or nil.
    private func find(_ s: [UInt16], from i: Int, _ end: Int) -> Int? {
        var i = i
        while i + s.count <= end {
            if c[i] == s[0], matches(s, at: i, end) { return i }
            i += 1
        }
        return nil
    }

    private func isBreak(_ ch: UInt16) -> Bool { ch == 10 || ch == 13 }
    private func isBlank(_ ch: UInt16) -> Bool { ch == 32 || ch == 9 }
    private func isDigit(_ ch: UInt16) -> Bool { ch >= 48 && ch <= 57 }
    private func isIdentStart(_ ch: UInt16) -> Bool {
        (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 95 || ch > 127
    }
    private func isIdent(_ ch: UInt16) -> Bool { isIdentStart(ch) || isDigit(ch) }

    private func lineEnd(_ i: Int, _ end: Int) -> Int {
        var i = i
        while i < end, !isBreak(c[i]) { i += 1 }
        return i
    }

    /// The start of the next line.
    private func nextLine(_ i: Int, _ end: Int) -> Int {
        var i = lineEnd(i, end)
        if i < end, c[i] == 13 { i += 1; if i < end, c[i] == 10 { i += 1 } } else if i < end { i += 1 }
        return i
    }

    private func identEnd(_ i: Int, _ end: Int, dashes: Bool = false) -> Int {
        var i = i
        while i < end, isIdent(c[i]) || (dashes && c[i] == 45) { i += 1 }
        return i
    }

    private func word(_ start: Int, _ end: Int) -> String { String(decoding: c[start..<end], as: UTF16.self) }

    /// Past the closing quote, honouring backslashes; at the line's end if it isn't closed there.
    private func stringEnd(_ i: Int, quote: [UInt16], multiline: Bool, raw: Bool = false, _ end: Int) -> Int {
        var i = i + quote.count
        while i < end {
            if c[i] == 92, !raw { i += 2; continue }
            if !multiline, isBreak(c[i]) { return i }
            if matches(quote, at: i, end) { return i + quote.count }
            i += 1
        }
        return end
    }

    private func numberEnd(_ i: Int, _ end: Int) -> Int {
        var i = i
        while i < end, isIdent(c[i]) || (c[i] == 46 && i + 1 < end && isDigit(c[i + 1])) { i += 1 }
        return i
    }

    // MARK: Code

    /// Returns where the code stopped: at the close tag, or at the range's end.
    @discardableResult
    private mutating func code(_ rules: CodeRules, _ range: Range<Int>) -> Int {
        let end = range.upperBound
        let closeTag = rules.closeTag.map { Array($0.utf16) }
        let lineComments = rules.lineComments.map { Array($0.utf16) }
        let block = rules.blockComment.map { (open: Array($0.open.utf16), close: Array($0.close.utf16)) }
        let quotes = rules.quotes.map {
            (quote: Array($0.utf16), multiline: rules.multilineQuotes.contains($0), raw: rules.rawQuotes.contains($0))
        }
        let longestKeyword = rules.keywords.map(\.count).max() ?? 0
        var depth = 0
        var i = range.lowerBound

        scanning: while i < end {
            let ch = c[i]
            if let closeTag, matches(closeTag, at: i, end) { return i }
            for comment in lineComments where matches(comment, at: i, end) {
                if rules.commentAfterSpace, i > range.lowerBound, !isBlank(c[i - 1]), !isBreak(c[i - 1]) { continue }
                if rules.hashAttributes, ch == 35, i + 1 < end, c[i + 1] == 91 { continue }
                let lineStop = lineEnd(i, end)
                let stop = closeTag.flatMap { find($0, from: i, lineStop) } ?? lineStop
                emit(.comment, i, stop)
                i = stop
                continue scanning
            }
            if let block, matches(block.open, at: i, end) {
                let close = find(block.close, from: i + block.open.count, end)
                let stop = close.map { $0 + block.close.count } ?? end
                emit(.comment, i, stop)
                i = stop
                continue
            }
            for (quote, multiline, raw) in quotes where matches(quote, at: i, end) {
                let stop = min(stringEnd(i, quote: quote, multiline: multiline, raw: raw, end), end)
                emit(.string, i, stop)
                i = stop
                continue scanning
            }
            if isDigit(ch) {
                let stop = numberEnd(i, end)
                emit(.number, i, stop)
                i = stop
                continue
            }
            if rules.dollarVariables, ch == 36, i + 1 < end {
                if c[i + 1] == 123, let close = find([125], from: i + 2, lineEnd(i, end)) {
                    emit(.variable, i, close + 1)
                    i = close + 1
                    continue
                }
                if isIdent(c[i + 1]) {
                    let stop = identEnd(i + 1, end)
                    emit(.variable, i, stop)
                    i = stop
                    continue
                }
            }
            if rules.cssBlocks {
                if ch == 123 { depth += 1 } else if ch == 125 { depth = max(depth - 1, 0) }
                if ch == 35, depth > 0, i + 1 < end, isIdent(c[i + 1]) {
                    let stop = identEnd(i + 1, end)
                    emit(.number, i, stop)
                    i = stop
                    continue
                }
            }
            if (rules.atWords && ch == 64) || (rules.hashWords && ch == 35), i + 1 < end, isIdentStart(c[i + 1]) {
                let stop = identEnd(i + 1, end, dashes: rules.cssBlocks)
                emit(.keyword, i, stop)
                i = stop
                continue
            }
            if isIdentStart(ch) || (rules.cssBlocks && ch == 45) {
                let stop = identEnd(i + 1, end, dashes: rules.cssBlocks)
                if rules.cssBlocks, depth > 0 {
                    var next = stop
                    while next < end, isBlank(c[next]) { next += 1 }
                    if next < end, c[next] == 58 { emit(.key, i, stop) }
                } else if stop - i <= longestKeyword {
                    let name = word(i, stop)
                    if rules.keywords.contains(rules.ignoresCase ? name.lowercased() : name) { emit(.keyword, i, stop) }
                }
                i = stop
                continue
            }
            i += 1
        }
        return end
    }

    // MARK: PHP

    /// HTML up to `<?php`, code up to `?>`, and so on.
    private mutating func php(_ rules: CodeRules) {
        let open = Array("<?".utf16)
        var i = 0
        let end = c.count
        while i < end {
            guard let start = find(open, from: i, end) else { html(i..<end); return }
            html(i..<start)
            var body = start + 2
            let tagEnd = identEnd(body, end)
            if tagEnd > body || (body < end && c[body] == 61) {
                body = tagEnd > body ? tagEnd : body + 1
            }
            emit(.keyword, start, body)
            let stop = code(rules, body..<end)
            guard stop < end else { return }
            emit(.keyword, stop, stop + 2)
            i = stop + 2
        }
    }

    // MARK: HTML

    private mutating func html(_ range: Range<Int>) {
        let end = range.upperBound
        let commentOpen = Array("<!--".utf16), commentClose = Array("-->".utf16), piClose = Array("?>".utf16)
        var i = range.lowerBound
        while i < end {
            guard c[i] == 60 else { i += 1; continue }
            if matches(commentOpen, at: i, end) {
                let stop = find(commentClose, from: i + 4, end).map { $0 + 3 } ?? end
                emit(.comment, i, stop)
                i = stop
            } else if i + 1 < end, c[i + 1] == 33 || c[i + 1] == 63 {
                let close = c[i + 1] == 63 ? piClose : [62]
                let stop = find(close, from: i + 2, end).map { $0 + close.count } ?? end
                emit(.keyword, i, stop)
                i = stop
            } else {
                var name = i + 1
                if name < end, c[name] == 47 { name += 1 }
                guard name < end, isIdentStart(c[name]) else { i += 1; continue }
                let nameEnd = attributeNameEnd(name, end)
                emit(.tag, name, nameEnd)
                i = attributes(from: nameEnd, end)
            }
        }
    }

    private func attributeNameEnd(_ i: Int, _ end: Int) -> Int {
        var i = i
        while i < end, isIdent(c[i]) || c[i] == 45 || c[i] == 58 || c[i] == 46 { i += 1 }
        return i
    }

    /// Inside a tag: names and quoted values, up to past its `>`.
    private mutating func attributes(from start: Int, _ end: Int) -> Int {
        var i = start
        while i < end {
            let ch = c[i]
            if ch == 62 { return i + 1 }
            if ch == 34 || ch == 39 {
                var stop = i + 1
                while stop < end, c[stop] != ch { stop += 1 }
                stop = min(stop + 1, end)
                emit(.string, i, stop)
                i = stop
            } else if isIdentStart(ch) {
                let stop = attributeNameEnd(i, end)
                emit(.key, i, stop)
                i = stop
            } else {
                i += 1
            }
        }
        return end
    }

    // MARK: JSON

    private mutating func json(_ range: Range<Int>) {
        let end = range.upperBound
        let quote = Array("\"".utf16)
        let literals: Set<String> = ["true", "false", "null"]
        var i = range.lowerBound
        while i < end {
            let ch = c[i]
            if ch == 34 {
                let stop = min(stringEnd(i, quote: quote, multiline: false, end), end)
                var next = stop
                while next < end, isBlank(c[next]) || isBreak(c[next]) { next += 1 }
                emit(next < end && c[next] == 58 ? .key : .string, i, stop)
                i = stop
            } else if isDigit(ch) || (ch == 45 && i + 1 < end && isDigit(c[i + 1])) {
                var stop = i + 1
                while stop < end, isIdent(c[stop]) || c[stop] == 46 || ((c[stop] == 45 || c[stop] == 43) && (c[stop - 1] | 32) == 101) { stop += 1 }
                emit(.number, i, stop)
                i = stop
            } else if isIdentStart(ch) {
                let stop = identEnd(i, end)
                if stop - i <= 5, literals.contains(word(i, stop)) { emit(.keyword, i, stop) }
                i = stop
            } else {
                i += 1
            }
        }
    }

    // MARK: YAML

    private mutating func yaml(_ range: Range<Int>) {
        let end = range.upperBound
        let literals: Set<String> = ["true", "false", "null", "yes", "no", "on", "off"]
        var line = range.lowerBound
        while line < end {
            let stop = lineEnd(line, end)
            var i = line
            while i < stop, isBlank(c[i]) { i += 1 }
            while i + 1 < stop, c[i] == 45, isBlank(c[i + 1]) {
                i += 2
                while i < stop, isBlank(c[i]) { i += 1 }
            }
            if let colon = keyColon(i, stop) {
                emit(.key, i, colon)
                i = colon + 1
                while i < stop, isBlank(c[i]) { i += 1 }
            }
            yamlValue(i, stop, literals)
            line = nextLine(line, end)
        }
    }

    /// The `:` that ends a key starting at `i`.
    private func keyColon(_ i: Int, _ stop: Int) -> Int? {
        guard i < stop, c[i] != 35 else { return nil }
        if c[i] == 34 || c[i] == 39 {
            var close = i + 1
            while close < stop, c[close] != c[i] { close += 1 }
            let colon = close + 1
            return colon < stop && c[colon] == 58 ? colon : nil
        }
        var j = i
        while j < stop {
            if c[j] == 58, j + 1 == stop || isBlank(c[j + 1]) { return j }
            if c[j] == 35, j > i, isBlank(c[j - 1]) { return nil }
            j += 1
        }
        return nil
    }

    private mutating func yamlValue(_ start: Int, _ stop: Int, _ literals: Set<String>) {
        var i = start
        guard i < stop else { return }
        if c[i] == 34 || c[i] == 39 {
            let quote = c[i]
            var close = i + 1
            while close < stop, c[close] != quote {
                if quote == 34, c[close] == 92 { close += 1 }
                close += 1
            }
            close = min(close + 1, stop)
            emit(.string, i, close)
            i = close
        } else if c[i] != 35 {
            var valueEnd = i
            while valueEnd < stop, !(c[valueEnd] == 35 && valueEnd > i && isBlank(c[valueEnd - 1])) { valueEnd += 1 }
            var trimmed = valueEnd
            while trimmed > i, isBlank(c[trimmed - 1]) { trimmed -= 1 }
            let value = word(i, trimmed)
            if literals.contains(value.lowercased()) {
                emit(.keyword, i, trimmed)
            } else if Double(value) != nil {
                emit(.number, i, trimmed)
            }
            i = valueEnd
        }
        while i < stop, isBlank(c[i]) { i += 1 }
        if i < stop, c[i] == 35 { emit(.comment, i, stop) }
    }

    // MARK: Markdown

    private mutating func markdown(_ range: Range<Int>) {
        let end = range.upperBound
        var fence: (char: UInt16, count: Int)?
        var fenceStart = 0
        var line = range.lowerBound
        while line < end {
            let stop = lineEnd(line, end)
            var i = line
            while i < stop, i - line < 3, c[i] == 32 { i += 1 }
            var run = i
            let first = i < stop ? c[i] : 0
            if first == 96 || first == 126 { while run < stop, c[run] == first { run += 1 } }
            let runLength = run - i

            if let open = fence {
                if first == open.char, runLength >= open.count {
                    emit(.code, fenceStart, stop)
                    fence = nil
                }
            } else if runLength >= 3, first != 96 || find([96], from: run, stop) == nil {
                fence = (first, runLength)
                fenceStart = line
            } else if first == 35, isHeading(i, stop) {
                emit(.heading, i, stop)
            } else if first == 62 {
                emit(.comment, i, stop)
            } else {
                inline(listMarker(i, stop), stop)
            }
            line = nextLine(line, end)
        }
        if fence != nil { emit(.code, fenceStart, end) }
    }

    private func isHeading(_ i: Int, _ stop: Int) -> Bool {
        var j = i
        while j < stop, c[j] == 35 { j += 1 }
        return j - i <= 6 && (j == stop || isBlank(c[j]))
    }

    /// Colours a list marker; the line's text starts where this returns.
    private mutating func listMarker(_ start: Int, _ stop: Int) -> Int {
        var i = start
        while i < stop, isBlank(c[i]) { i += 1 }
        guard i < stop else { return i }
        var marker = i
        if c[i] == 45 || c[i] == 42 || c[i] == 43 {
            marker = i + 1
        } else if isDigit(c[i]) {
            while marker < stop, isDigit(c[marker]) { marker += 1 }
            guard marker < stop, c[marker] == 46 || c[marker] == 41 else { return i }
            marker += 1
        }
        guard marker > i, marker < stop, isBlank(c[marker]) else { return i }
        emit(.keyword, i, marker)
        return marker
    }

    /// How far a mark looks for its other end, so a very long line stays linear.
    private static let inlineReach = 500

    private mutating func inline(_ start: Int, _ stop: Int) {
        var i = start
        while i < stop {
            let ch = c[i]
            if ch == 92 {
                i += 2
            } else if ch == 96 {
                var run = i
                while run < stop, c[run] == 96 { run += 1 }
                let ticks = [UInt16](repeating: 96, count: run - i)
                if let close = find(ticks, from: run, min(run + Self.inlineReach, stop)) {
                    emit(.code, i, close + ticks.count)
                    i = close + ticks.count
                } else {
                    i = run
                }
            } else if ch == 42 || ch == 95 {
                let stopAt = emphasisEnd(i, stop)
                if let stopAt {
                    emit(.emphasis, i, stopAt)
                    i = stopAt
                } else {
                    i += 1
                }
            } else if ch == 91, let stopAt = linkEnd(i, stop) {
                emit(.link, i, stopAt)
                i = stopAt
            } else {
                i += 1
            }
        }
    }

    /// `*a*`, `**a**`, `_a_`, `__a__`: past the closing marks. `_` only at a word's edge.
    private func emphasisEnd(_ i: Int, _ stop: Int) -> Int? {
        let stop = min(i + Self.inlineReach, stop)
        let mark = c[i]
        var run = i
        while run < stop, c[run] == mark { run += 1 }
        let count = run - i
        guard count <= 2, run < stop, !isBlank(c[run]) else { return nil }
        if mark == 95, i > 0, isIdent(c[i - 1]) { return nil }
        let closing = [UInt16](repeating: mark, count: count)
        var j = run
        while let close = find(closing, from: j, stop) {
            let after = close + count
            if !isBlank(c[close - 1]), close > run, mark != 95 || after == stop || !isIdent(c[after]) { return after }
            j = close + 1
        }
        return nil
    }

    /// `[text](url)`: past the `)`.
    private func linkEnd(_ i: Int, _ stop: Int) -> Int? {
        let stop = min(i + Self.inlineReach, stop)
        guard let close = find([93], from: i + 1, stop), close + 1 < stop, c[close + 1] == 40,
              let paren = find([41], from: close + 2, stop) else { return nil }
        return paren + 1
    }
}
