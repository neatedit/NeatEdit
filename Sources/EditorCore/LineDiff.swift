import Foundation

/// Lines of `text` with CRLF and CR treated as LF, so files that differ only
/// in line endings compare equal. A trailing break yields a final empty line.
public func normalizedLines(_ text: String) -> [Substring] {
    // utf8, not Character: "\r\n" is a single Character that doesn't contain "\r".
    let lf = text.utf8.contains(0x0D)
        ? text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        : text
    return lf.split(separator: "\n", omittingEmptySubsequences: false)
}

/// One change: the old lines in `oldRange` become `newLines`. An empty range
/// is a pure insertion before that line.
public struct DiffHunk: Equatable, Hashable, Sendable {
    public var oldRange: Range<Int>
    public var newLines: [String]

    public init(oldRange: Range<Int>, newLines: [String]) {
        self.oldRange = oldRange
        self.newLines = newLines
    }
}

public enum LineDiff {
    /// Above this many differences the middle part is reported as one hunk
    /// instead of tracing Myers' paths (memory grows with the square of it).
    static let maxEditDistance = 2_000

    /// Sorted, non-overlapping hunks turning `old` into `new` (Myers O(ND)).
    public static func hunks(old: [Substring], new: [Substring]) -> [DiffHunk] {
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }

        let oldMiddle = old[prefix..<(old.count - suffix)]
        let newMiddle = new[prefix..<(new.count - suffix)]
        if oldMiddle.isEmpty, newMiddle.isEmpty { return [] }

        // Compare integers, not strings, in the hot loop.
        var ids: [Substring: Int] = [:]
        let a = oldMiddle.map { line in ids[line] ?? { ids[line] = ids.count; return ids.count - 1 }() }
        let b = newMiddle.map { line in ids[line] ?? { ids[line] = ids.count; return ids.count - 1 }() }

        guard let matches = matches(a, b) else {
            return [DiffHunk(oldRange: prefix..<(old.count - suffix), newLines: newMiddle.map(String.init))]
        }

        var result: [DiffHunk] = []
        var i = 0, j = 0
        for (x, y) in matches + [(a.count, b.count)] {
            if x > i || y > j {
                result.append(DiffHunk(
                    oldRange: (prefix + i)..<(prefix + x),
                    newLines: newMiddle[(prefix + j)..<(prefix + y)].map(String.init)))
            }
            i = x + 1
            j = y + 1
        }
        return result
    }

    /// Index pairs of equal elements on a shortest edit path, ascending, or
    /// nil when the edit distance exceeds `maxEditDistance`.
    private static func matches(_ a: [Int], _ b: [Int]) -> [(Int, Int)]? {
        let n = a.count, m = b.count
        let limit = min(n + m, maxEditDistance)
        let offset = limit + 1
        var v = [Int](repeating: 0, count: 2 * limit + 3)
        // trace[d][k + d] = furthest x on diagonal k after d edits.
        var trace: [[Int]] = []
        var found: Int?

        search: for d in 0...limit {
            for k in stride(from: -d, through: d, by: 2) {
                var x = (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]))
                    ? v[offset + k + 1]
                    : v[offset + k - 1] + 1
                var y = x - k
                while x < n, y < m, a[x] == b[y] { x += 1; y += 1 }
                v[offset + k] = x
                if x >= n, y >= m {
                    trace.append(Array(v[(offset - d)...(offset + d)]))
                    found = d
                    break search
                }
            }
            trace.append(Array(v[(offset - d)...(offset + d)]))
        }
        guard let distance = found else { return nil }

        var result: [(Int, Int)] = []
        var x = n, y = m
        for d in stride(from: distance, to: 0, by: -1) {
            let previous = trace[d - 1]
            let k = x - y
            let prevK = (k == -d || (k != d && previous[k - 1 + d - 1] < previous[k + 1 + d - 1])) ? k + 1 : k - 1
            let prevX = previous[prevK + d - 1]
            let prevY = prevX - prevK
            while x > prevX, y > prevY {
                x -= 1; y -= 1
                result.append((x, y))
            }
            x = prevX
            y = prevY
        }
        while x > 0, y > 0 {
            x -= 1; y -= 1
            result.append((x, y))
        }
        return result.reversed()
    }
}
