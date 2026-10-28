import Foundation

/// A character count that may fall back to UTF-16 units for huge spans.
public struct CharacterCount: Equatable, Sendable {
    public var value: Int
    public var isApproximate: Bool

    public init(value: Int, isApproximate: Bool) {
        self.value = value
        self.isApproximate = isApproximate
    }

    public init(in text: NSString, range: NSRange, exactLimit: Int = CursorPosition.defaultExactCountLimit) {
        if range.length > exactLimit {
            self.init(value: range.length, isApproximate: true)
        } else {
            self.init(value: range.length == 0 ? 0 : text.substring(with: range).count, isApproximate: false)
        }
    }
}

/// The two halves of the status bar, as plain strings.
public struct StatusLine: Equatable, Sendable {
    public var left: String
    public var right: String

    public init(
        position: CursorPosition,
        selection: CharacterCount?,
        totalCharacters: CharacterCount?,
        lines: Int,
        encoding: String,
        lineEnding: LineEnding
    ) {
        let approx = position.isApproximate ? "~" : ""
        var left = "Ln \(Self.format(position.line)), Col \(approx)\(Self.format(position.column))"
            + "   Pos \(approx)\(Self.format(position.offset))"
            + "   Line \(approx)\(Self.format(position.lineLength)) chars"
        if let selection {
            left += "   Sel \(Self.format(selection))"
        }
        self.left = left

        let total = totalCharacters.map(Self.format) ?? "…"
        right = "\(total) chars, \(Self.format(lines)) lines   \(encoding)   \(lineEnding.rawValue)"
    }

    private static func format(_ count: CharacterCount) -> String {
        (count.isApproximate ? "~" : "") + format(count.value)
    }

    /// Thin groups separated by a plain space ("1 234 567"), locale-independent.
    static func format(_ number: Int) -> String {
        let digits = String(number.magnitude)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(" ") }
            out.append(ch)
        }
        return (number < 0 ? "-" : "") + out
    }
}
