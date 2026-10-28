import Foundation

/// Undoes the hard wrapping a terminal UI adds when it prints prose (Claude
/// Code and the like): real line breaks at the window width plus a common
/// left margin. Paragraphs, list items, quotes, headings, tables, box
/// drawings and fenced code keep their own lines.
public enum TextUnwrap {
    /// Pastes bigger than this (UTF-8 bytes) are never unwrapped automatically.
    public static let maxAutoLength = 256 * 1024
    /// Terminals are rarely narrower than 80 columns; shorter lines are deliberate.
    static let minWidth = 70
    /// An automatic wrap point must reach this close to the window width.
    static let nearWidth = 20

    /// The unwrapped text when `text` clearly looks hard-wrapped, else nil.
    /// Used on paste, so it errs on the side of leaving text alone.
    public static func unwrapIfWrapped(_ text: String) -> String? {
        guard text.utf8.count <= maxAutoLength else { return nil }
        let block = Block(text)
        guard block.lines.count >= 2, block.width >= minWidth, !block.looksLikeCodeOrData else { return nil }
        let points = block.wrapPoints(nearWidthOnly: true)
        // One wrap is enough when the block has a terminal-style margin.
        guard points.count >= 2 || (points.count == 1 && block.hasMargin) else { return nil }
        let result = block.render(joining: points)
        return result == text ? nil : result
    }

    /// Always unwraps (an explicit command on a selection).
    public static func unwrap(_ text: String) -> String {
        let block = Block(text)
        return block.render(joining: block.wrapPoints(nearWidthOnly: false))
    }

    private struct Line {
        /// Margin removed; trailing whitespace trimmed unless frozen.
        var text: Substring
        /// Fenced code or box drawing: kept exactly, never joined.
        var frozen = false
        /// Leading whitespace and quote markers ("  ▎ ").
        var prefix: Substring = ""
        var content: Substring = ""
        /// Width of the whole line in terminal columns.
        var width = 0
        /// Width of a list marker at the start of `content` ("- ", "12. "), or nil.
        var listMarker: Int?
        var startsBlock = false
    }

    private struct Block {
        let separator: String
        var lines: [Line] = []
        var hasMargin = false
        /// The longest line: the best guess at the terminal width.
        var width = 0

        init(_ text: String) {
            separator = text.contains("\r\n") ? "\r\n" : "\n"
            var raw = text.components(separatedBy: separator).map { Substring($0) }

            // Claude Code starts an answer with "⏺ " in the margin.
            if let first = raw.first, first.hasPrefix("⏺ ") || first.hasPrefix("● ") {
                raw[0] = first.dropFirst(2)
                hasMargin = true
            }

            // The common margin: the same whitespace on every non-empty line.
            // A first line without any is a selection that began after it.
            let measured = raw.enumerated().filter { !$0.element.isEmpty && !($0.offset == 0 && !Self.isSpace($0.element.first)) }
            var margin = measured.first.map { $0.element.prefix(while: { Self.isSpace($0) }) } ?? ""
            for (_, line) in measured.dropFirst() {
                margin = margin.commonPrefix(with: line.prefix(while: { Self.isSpace($0) }))[...]
            }
            if !margin.isEmpty { hasMargin = true }

            var inFence = false
            for line in raw {
                var text = line.hasPrefix(margin) ? line.dropFirst(margin.count) : line
                let isFence = text.drop(while: { $0 == " " }).hasPrefix("```")
                let frozen = inFence || isFence || text.unicodeScalars.contains { (0x2500...0x257F).contains($0.value) }
                if isFence { inFence.toggle() }
                if !frozen {
                    while let last = text.last, Self.isSpace(last) { text = text.dropLast() }
                }
                var parsed = Line(text: text, frozen: frozen)
                let prefix = text.prefix(while: { Self.isSpace($0) || $0 == "▎" || $0 == ">" })
                parsed.prefix = prefix
                parsed.content = text.dropFirst(prefix.count)
                parsed.width = Self.columns(text)
                parsed.listMarker = Self.listMarker(parsed.content)
                parsed.startsBlock = parsed.listMarker != nil || Self.startsBlock(parsed.content)
                lines.append(parsed)
                if !frozen { width = max(width, parsed.width) }
            }
        }

        /// Signs of code, logs, traces or tables: those keep their lines.
        var looksLikeCodeOrData: Bool {
            var signals = 0
            var nonEmpty = 0
            for (i, line) in lines.enumerated() where !line.frozen && !line.content.isEmpty {
                nonEmpty += 1
                let content = line.content
                let next = i + 1 < lines.count ? lines[i + 1] : nil
                if let last = content.last, "{}".contains(last) {
                    signals += 1
                } else if !content.contains(" "), content.count >= 20, Self.columns(content) == content.count {
                    signals += 1  // CSV rows, paths, URLs
                } else if content.prefix(4).allSatisfy(\.isNumber) || Self.startsWithTime(content) {
                    signals += 1  // log timestamps
                } else if ["at ", "File \"", "$ ", "Traceback", "def ", "return ", "import ", "func "].contains(where: { content.hasPrefix($0) }) {
                    signals += 1
                } else if content.hasSuffix(":"), let next, !next.content.isEmpty, next.listMarker == nil,
                          next.prefix.count > line.prefix.count {
                    signals += 1  // YAML / Python blocks
                }
            }
            return signals >= 2 && signals * 4 >= nonEmpty
        }

        /// Lines the terminal broke: the next line's first word would have
        /// fit on them otherwise, and it continues the same paragraph.
        func wrapPoints(nearWidthOnly: Bool) -> Set<Int> {
            var points = Set<Int>()
            // Where a continuation line may start: under the paragraph's text,
            // or (for list items, as some renderers do) under the marker.
            var continuation: Set<Int> = []
            for i in lines.indices {
                let line = lines[i]
                if line.startsBlock || !points.contains(i - 1) {
                    continuation = [line.prefix.count, line.prefix.count + (line.listMarker ?? 0)]
                }
                guard i + 1 < lines.count else { break }
                let next = lines[i + 1]
                guard !line.frozen, !next.frozen, !line.content.isEmpty, !next.content.isEmpty, !next.startsBlock else { continue }
                guard Self.quoteMarks(next.prefix) == Self.quoteMarks(line.prefix), continuation.contains(next.prefix.count) else { continue }
                if nearWidthOnly, line.width < width - nearWidth { continue }
                let firstWord = next.content.prefix(while: { $0 != " " })
                if line.width + 1 + Self.columns(firstWord) > width { points.insert(i) }
            }
            return points
        }

        func render(joining points: Set<Int>) -> String {
            var out: [String] = []
            var paragraph: [Substring] = []
            for (i, line) in lines.enumerated() {
                if points.contains(i - 1) {
                    let previous = paragraph.last?.last
                    let isWide = previous.map { Self.isWide($0) } ?? false || line.content.first.map(Self.isWide) ?? false
                    if !isWide { paragraph.append(" ") }
                    paragraph.append(line.content)
                } else {
                    if !paragraph.isEmpty { out.append(paragraph.joined()) }
                    paragraph = [line.text]
                }
            }
            if !paragraph.isEmpty { out.append(paragraph.joined()) }
            return out.joined(separator: separator)
        }

        // MARK: Character classes

        static func isSpace(_ c: Character?) -> Bool { c == " " || c == "\t" }

        static func quoteMarks(_ prefix: Substring) -> String { String(prefix.filter { $0 == "▎" || $0 == ">" }) }

        /// "- ", "* ", "• ", "+ ", "– ", "1. ", "12) ", "a) " → its width.
        static func listMarker(_ content: Substring) -> Int? {
            if let first = content.first, "-*•+–".contains(first), content.dropFirst().first == " " { return 2 }
            let digits = content.prefix(while: \.isNumber)
            if (1...3).contains(digits.count) {
                let rest = content.dropFirst(digits.count)
                if let mark = rest.first, ".)".contains(mark), rest.dropFirst().first == " " { return digits.count + 2 }
            }
            if let first = content.first, first.isLetter, first.isLowercase, content.dropFirst().first == ")", content.dropFirst(2).first == " " {
                return 3
            }
            return nil
        }

        /// Heading, table row, fence or bold lead-in: starts its own line.
        static func startsBlock(_ content: Substring) -> Bool {
            ["#", "|", "```", "**"].contains { content.hasPrefix($0) }
        }

        static func startsWithTime(_ content: Substring) -> Bool {
            let chars = Array(content.prefix(3))
            return chars.count == 3 && chars[0].isNumber && chars[1].isNumber && chars[2] == ":"
        }

        /// Terminal columns: East Asian wide characters and emoji take two.
        static func columns(_ text: Substring) -> Int {
            var total = 0
            for scalar in text.unicodeScalars {
                switch scalar.value {
                case 0x0300...0x036F, 0x200B...0x200F, 0xFE00...0xFE0F: break
                default: total += isWide(scalar) ? 2 : 1
                }
            }
            return total
        }

        static func isWide(_ c: Character) -> Bool { c.unicodeScalars.first.map(isWide) ?? false }

        static func isWide(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.value {
            case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F,
                 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x1F300...0x1FAFF, 0x20000...0x3FFFD:
                true
            default:
                false
            }
        }
    }
}
