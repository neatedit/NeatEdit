import Foundation

/// One external change to review: base lines `base.oldRange` (`oldLines`)
/// became `base.newLines` on disk. A conflict also touches lines the user
/// edited; `mineLines` is the user's text for the same region.
public struct ExternalHunk: Equatable, Sendable, Identifiable {
    /// Same hunk → same id across re-diffs within a run, so decisions survive.
    public let id: Int
    public let base: DiffHunk
    public let oldLines: [String]
    public let mineLines: [String]
    public let isConflict: Bool
}

/// For a conflict, `accept` takes the disk version and `skip` keeps mine.
public enum HunkDecision: Sendable {
    case accept, skip
}

/// Three-way view of an external change: base (last loaded or saved),
/// mine (the open tab) and disk. Lists base → disk changes and merges the
/// accepted ones into mine.
public struct ExternalMerge: Sendable {
    public let hunks: [ExternalHunk]
    private let baseLines: [String]
    /// Regions in base order; each is either an external hunk or the user's own edit.
    private let regions: [Region]

    private struct Region: Sendable {
        var range: Range<Int>
        var mine: [String]
        var hunkID: Int?
        var disk: [String]
    }

    public init(base: String, mine: String, disk: String) {
        let baseLines = normalizedLines(base)
        let ours = LineDiff.hunks(old: baseLines, new: normalizedLines(mine))
        let theirs = LineDiff.hunks(old: baseLines, new: normalizedLines(disk))
        self.baseLines = baseLines.map(String.init)
        changedLineCount = theirs.reduce(0) { $0 + max($1.oldRange.count, 1) }

        var regions: [Region] = []
        var hunks: [ExternalHunk] = []
        for cluster in Self.clusters(ours: ours, theirs: theirs) {
            let mineLines = Self.render(cluster.range, cluster.ours, self.baseLines)
            guard !cluster.theirs.isEmpty else {
                regions.append(Region(range: cluster.range, mine: mineLines, hunkID: nil, disk: mineLines))
                continue
            }
            let diskLines = Self.render(cluster.range, cluster.theirs, self.baseLines)
            let oldLines = Array(self.baseLines[cluster.range])
            let hunk = DiffHunk(oldRange: cluster.range, newLines: diskLines)
            var hasher = Hasher()
            hasher.combine(hunk)
            hasher.combine(oldLines)
            let id = hasher.finalize()
            hunks.append(ExternalHunk(
                id: id, base: hunk, oldLines: oldLines, mineLines: mineLines,
                isConflict: !cluster.ours.isEmpty))
            regions.append(Region(range: cluster.range, mine: mineLines, hunkID: id, disk: diskLines))
        }
        self.hunks = hunks
        self.regions = regions
    }

    public var isEmpty: Bool { hunks.isEmpty }

    /// Base lines touched by the external change (an insertion counts as one).
    private let changedLineCount: Int

    /// Too much changed to review piece by piece: more than half of base.
    public var isBig: Bool { changedLineCount * 2 > baseLines.count }

    /// The user's text with accepted hunks applied, LF line endings.
    /// Hunks without a decision are skipped.
    public func apply(_ decisions: [Int: HunkDecision]) -> String {
        var out: [String] = []
        var position = 0
        for region in regions {
            out += baseLines[position..<region.range.lowerBound]
            let accepted = region.hunkID.flatMap { decisions[$0] } == .accept
            out += accepted ? region.disk : region.mine
            position = region.range.upperBound
        }
        out += baseLines[position...]
        return out.joined(separator: "\n")
    }

    // MARK: Building

    private struct Cluster {
        var range: Range<Int>
        var ours: [DiffHunk] = []
        var theirs: [DiffHunk] = []
    }

    /// Groups hunks from both sides that overlap or touch, in base order.
    private static func clusters(ours: [DiffHunk], theirs: [DiffHunk]) -> [Cluster] {
        let all = (ours.map { ($0, true) } + theirs.map { ($0, false) })
            .sorted { $0.0.oldRange.lowerBound < $1.0.oldRange.lowerBound }
        var result: [Cluster] = []
        for (hunk, isOurs) in all {
            if var last = result.last, overlaps(last.range, hunk.oldRange) {
                last.range = min(last.range.lowerBound, hunk.oldRange.lowerBound)
                    ..< max(last.range.upperBound, hunk.oldRange.upperBound)
                if isOurs { last.ours.append(hunk) } else { last.theirs.append(hunk) }
                result[result.count - 1] = last
            } else {
                var cluster = Cluster(range: hunk.oldRange)
                if isOurs { cluster.ours.append(hunk) } else { cluster.theirs.append(hunk) }
                result.append(cluster)
            }
        }
        return result
    }

    /// Non-empty ranges must share a line; an insertion also counts when it
    /// sits right at the edge of the other range.
    private static func overlaps(_ a: Range<Int>, _ b: Range<Int>) -> Bool {
        if a.isEmpty || b.isEmpty {
            return a.lowerBound <= b.upperBound && b.lowerBound <= a.upperBound
        }
        return a.lowerBound < b.upperBound && b.lowerBound < a.upperBound
    }

    /// Base lines in `range` with `hunks` (sorted, inside the range) applied.
    private static func render(_ range: Range<Int>, _ hunks: [DiffHunk], _ base: [String]) -> [String] {
        var out: [String] = []
        var position = range.lowerBound
        for hunk in hunks {
            out += base[position..<hunk.oldRange.lowerBound]
            out += hunk.newLines
            position = hunk.oldRange.upperBound
        }
        out += base[position..<range.upperBound]
        return out
    }
}
