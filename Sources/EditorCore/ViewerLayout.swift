import CoreGraphics
import Foundation

/// Fixed-height-line geometry for the large file viewer: every line is one
/// row (no wrapping), so any point maps to a line in O(1).
public struct ViewerLayout: Equatable, Sendable {
    public var lineHeight: CGFloat
    public var charWidth: CGFloat
    public var inset: CGSize

    /// Lines up to this many UTF-16 units are drawn whole; longer ones only
    /// around the visible columns.
    public static let wholeLineLimit = 4096

    public init(lineHeight: CGFloat, charWidth: CGFloat, inset: CGSize) {
        self.lineHeight = lineHeight
        self.charWidth = charWidth
        self.inset = inset
    }

    public func lines(in rect: CGRect, lineCount: Int) -> Range<Int> {
        let first = Int(((rect.minY - inset.height) / lineHeight).rounded(.down))
        let last = Int(((rect.maxY - inset.height) / lineHeight).rounded(.up))
        let lower = min(max(first, 0), lineCount)
        return lower..<max(lower, min(last, lineCount))
    }

    public func line(atY y: CGFloat, lineCount: Int) -> Int {
        let line = Int(((y - inset.height) / lineHeight).rounded(.down))
        return min(max(line, 0), max(lineCount - 1, 0))
    }

    public func lineRect(_ line: Int, width: CGFloat) -> CGRect {
        CGRect(x: 0, y: inset.height + CGFloat(line) * lineHeight, width: width, height: lineHeight)
    }

    public func documentSize(lineCount: Int, longestLine: Int) -> CGSize {
        CGSize(
            width: inset.width * 2 + CGFloat(longestLine) * charWidth + charWidth,
            height: inset.height * 2 + CGFloat(lineCount) * lineHeight
        )
    }

    /// UTF-16 columns of a line worth drawing for the visible x range.
    public func columnWindow(lineLength: Int, visibleX: Range<CGFloat>, slack: Int = 256) -> Range<Int> {
        if lineLength <= Self.wholeLineLimit { return 0..<lineLength }
        let first = Int(((visibleX.lowerBound - inset.width) / charWidth).rounded(.down)) - slack
        let last = Int(((visibleX.upperBound - inset.width) / charWidth).rounded(.up)) + slack
        let lower = min(max(first, 0), lineLength)
        return lower..<max(lower, min(last, lineLength))
    }
}
