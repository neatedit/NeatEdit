import Foundation

/// The name macOS suggests for an unsaved draft.
public enum DraftName {
    /// `name` without the app's own name. macOS suggests a name from the
    /// draft's text, but it also reads the draft file's name, which is
    /// "Unsaved <App> Document", and so puts the app's name into the result.
    /// Returns nil when nothing else is left.
    public static func removing(app: String, from name: String) -> String? {
        let junk = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—:_·|,"))
        guard !app.isEmpty else { return name }
        var result = name
        var search = result.startIndex..<result.endIndex
        while let found = result.range(of: app, options: .caseInsensitive, range: search) {
            let wordBefore = found.lowerBound > result.startIndex && isWord(result[result.index(before: found.lowerBound)])
            let wordAfter = found.upperBound < result.endIndex && isWord(result[found.upperBound])
            if wordBefore || wordAfter {
                search = found.upperBound..<result.endIndex
                continue
            }
            // Take the separator on one side too: the one in front at the
            // very start, otherwise the one behind.
            var lower = found.lowerBound, upper = found.upperBound
            let atStart = result[..<lower].unicodeScalars.allSatisfy(junk.contains)
            if atStart {
                lower = result.startIndex
                while upper < result.endIndex, result[upper].unicodeScalars.allSatisfy(junk.contains) { upper = result.index(after: upper) }
            } else {
                while lower > result.startIndex, result[result.index(before: lower)].unicodeScalars.allSatisfy(junk.contains) { lower = result.index(before: lower) }
                let atEnd = result[upper...].unicodeScalars.allSatisfy(junk.contains)
                if atEnd { upper = result.endIndex }
            }
            let offset = result.distance(from: result.startIndex, to: lower)
            result.removeSubrange(lower..<upper)
            search = result.index(result.startIndex, offsetBy: offset)..<result.endIndex
        }
        result = result.trimmingCharacters(in: junk)
        return result.isEmpty ? nil : result
    }

    private static func isWord(_ character: Character) -> Bool { character.isLetter || character.isNumber }
}
