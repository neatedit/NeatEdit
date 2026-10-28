import Foundation

/// Undoes the hard wrapping a terminal UI adds when it prints prose: real
/// line breaks at the window width plus a common left margin. Paragraphs,
/// list items, headings, tables and fenced code keep their own lines.
public enum TextUnwrap {
    /// Narrower than this isn't a terminal window; it's short lines on purpose.
    static let minWidth = 40

    /// The unwrapped text when `text` clearly looks hard-wrapped, else nil.
    /// Used on paste, so it errs on the side of leaving text alone.
    public static func unwrapIfWrapped(_ text: String) -> String? {
        let parsed = Parsed(text)
        guard parsed.lines.count >= 2, parsed.width >= minWidth, parsed.codeLikeLines < 2 else { return nil }
        let points = parsed.wrapPoints()
        // One wrap is enough when the whole block has a terminal-style margin.
        guard points.count >= 2 || (points.count == 1 && parsed.indent > 0) else { return nil }
        let result = parsed.render(joining: points)
        return result == text ? nil : result
    }

    /// Always unwraps (an explicit command on a selection).
    public static func unwrap(_ text: String) -> String {
        let parsed = Parsed(text)
        return parsed.render(joining: parsed.wrapPoints())
    }

    private struct Parsed {
        let separator: String
        /// Trailing whitespace trimmed, common indent removed.
        let lines: [String]
        let indent: Int
        /// Inside (or delimiting) a ``` fence: never joined.
        let frozen: [Bool]
        /// The longest line: the best guess at the terminal width.
        let width: Int
        let codeLikeLines: Int

        init(_ text: String) {
            separator = text.contains("\r\n") ? "\r\n" : "\n"
            let raw = text.components(separatedBy: separator).map { line in
                String(line.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
            }
            let indent = raw.filter { !$0.isEmpty }.map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }.min() ?? 0
            let lines = raw.map { $0.isEmpty ? $0 : String($0.dropFirst(indent)) }

            var inFence = false
            let frozen = lines.map { line -> Bool in
                let isFence = line.drop(while: { $0 == " " }).hasPrefix("```")
                defer { if isFence { inFence.toggle() } }
                return inFence || isFence
            }
            self.indent = indent
            self.lines = lines
            self.frozen = frozen
            width = zip(lines, frozen).filter { !$1 }.map(\.0.count).max() ?? 0
            codeLikeLines = lines.filter { $0.last.map { "{};".contains($0) } ?? false }.count
        }

        /// Indexes of lines that the terminal broke: the next line's first
        /// word would have fit on them otherwise.
        func wrapPoints() -> Set<Int> {
            var points = Set<Int>()
            for i in lines.indices.dropLast() where !frozen[i] && !frozen[i + 1] {
                let line = lines[i]
                let next = lines[i + 1].drop(while: { $0 == " " })
                guard !line.isEmpty, !next.isEmpty, !Self.startsBlock(next) else { continue }
                if let last = line.last, "{};".contains(last) { continue }
                let firstWord = next.prefix(while: { $0 != " " })
                if line.count + 1 + firstWord.count > width { points.insert(i) }
            }
            return points
        }

        func render(joining points: Set<Int>) -> String {
            var out: [String] = []
            var joinNext = false
            for (i, line) in lines.enumerated() {
                if joinNext, let last = out.popLast() {
                    out.append(last + " " + line.drop(while: { $0 == " " }))
                } else {
                    out.append(line)
                }
                joinNext = points.contains(i)
            }
            return out.joined(separator: separator)
        }

        /// List item, heading, quote, table row or fence: starts its own line.
        static func startsBlock(_ line: Substring) -> Bool {
            line.contains(#/^(?:[-*•+]\s|\d{1,3}[.)]\s|[a-z][.)]\s|#|\||>|```)/#)
        }
    }
}
