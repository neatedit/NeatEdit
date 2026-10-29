import Foundation
import Testing
@testable import EditorCore

/// Applies `replaceAll` and returns the resulting text.
private func replacingAll(_ query: FindQuery, in text: String, scope: NSRange? = nil) -> String {
    let string = text as NSString
    let result = NSMutableString(string: string)
    for edit in query.replaceAll(in: string, scope: scope ?? NSRange(location: 0, length: string.length)).reversed() {
        result.replaceCharacters(in: edit.range, with: edit.replacement)
    }
    return result as String
}

private func found(_ query: FindQuery, _ text: String, _ match: NSTextCheckingResult?) -> String? {
    match.map { (text as NSString).substring(with: $0.range) }
}

struct FindQueryTests {
    @Test func plainTextIsLiteralAndCaseInsensitiveByDefault() throws {
        let query = try FindQuery(find: [.text("a.b")], replace: [.text("X")])
        #expect(replacingAll(query, in: "a.b A.B axb") == "X X axb")
    }

    @Test func caseSensitiveOption() throws {
        let query = try FindQuery(find: [.text("a")], replace: [.text("-")], options: .init(caseSensitive: true))
        #expect(replacingAll(query, in: "aAa") == "-A-")
    }

    @Test func placeholdersSwapCapturedText() throws {
        // The Coda docs example: swap width and height.
        let query = try FindQuery(
            find: [.text("width=\""), .placeholder(1), .text("\" height=\""), .placeholder(2), .text("\"")],
            replace: [.text("width=\""), .placeholder(2), .text("\" height=\""), .placeholder(1), .text("\"")])
        #expect(replacingAll(query, in: #"<img width="10" height="20"> <img width="3" height="4">"#)
            == #"<img width="20" height="10"> <img width="4" height="3">"#)
    }

    @Test func placeholdersMatchLazilyWithinALine() throws {
        let query = try FindQuery(find: [.text("src=\""), .placeholder(1), .text("\"")], replace: [.placeholder(1)])
        #expect(replacingAll(query, in: #"src="a.jpg" alt="x" src="b.png""#) == #"a.jpg alt="x" b.png"#)
        // never spans lines
        #expect(replacingAll(query, in: "src=\"a\nb\"") == "src=\"a\nb\"")
    }

    @Test func trailingPlaceholderTakesRestOfLine() throws {
        let query = try FindQuery(find: [.text("name: "), .placeholder(1)], replace: [.text("<"), .placeholder(1), .text(">")])
        #expect(replacingAll(query, in: "name: John Smith\nname: Ann") == "<John Smith>\n<Ann>")
    }

    @Test func emptyReplaceDeletesMatches() throws {
        let query = try FindQuery(find: [.text(" alt=\""), .placeholder(1), .text("\"")])
        #expect(replacingAll(query, in: #"<img alt="x" src="y">"#) == #"<img src="y">"#)
    }

    @Test func repeatedPlaceholderMustMatchTheSameText() throws {
        let query = try FindQuery(find: [.text("<"), .placeholder(1), .text(">"), .placeholder(2), .text("</"), .placeholder(1), .text(">")],
                                  replace: [.placeholder(2)])
        #expect(replacingAll(query, in: "<b>bold</b> <i>no</b>") == "bold <i>no</b>")
    }

    @Test func placeholderMissingFromFindReplacesWithNothing() throws {
        let query = try FindQuery(find: [.text("a"), .placeholder(1), .text("c")], replace: [.placeholder(3), .placeholder(1)])
        #expect(replacingAll(query, in: "abc") == "b")
    }

    @Test func replaceTextIsLiteralOutsideRegexMode() throws {
        let query = try FindQuery(find: [.text("x")], replace: [.text("$1\\n")])
        #expect(replacingAll(query, in: "x") == "$1\\n")
    }

    @Test func regexModeUsesTemplatesAndLineAnchors() throws {
        let query = try FindQuery(find: [.text(#"^(\w+)=(\d+)$"#)], replace: [.text("$2:$1")], options: .init(regex: true))
        #expect(replacingAll(query, in: "a=1\nb=22\nc=x") == "1:a\n22:b\nc=x")
    }

    @Test func regexModeAllowsZeroLengthMatches() throws {
        let query = try FindQuery(find: [.text("^")], replace: [.text("> ")], options: .init(regex: true))
        #expect(replacingAll(query, in: "a\nb") == "> a\n> b")
    }

    @Test func regexModeMixesWithPlaceholders() throws {
        let query = try FindQuery(find: [.text(#"(\d+)px "#), .placeholder(1), .text(";")],
                                  replace: [.placeholder(1), .text(" $1em;")], options: .init(regex: true))
        #expect(replacingAll(query, in: "12px solid;") == "solid 12em;")
    }

    @Test func invalidRegexThrows() {
        #expect(throws: FindError.self) { try FindQuery(find: [.text("(")], options: .init(regex: true)) }
        #expect(throws: FindError.self) { try FindQuery(find: []) }
        #expect(throws: FindError.self) { try FindQuery(find: [.text("")]) }
    }

    @Test func onlyPlaceholdersNeverMatchEmptyText() throws {
        let query = try FindQuery(find: [.placeholder(1)], replace: [.text("[")])
        #expect(query.count(in: "ab\n\ncd", scope: NSRange(location: 0, length: 6)) == 2)
    }

    @Test func replaceAllStaysInsideScope() throws {
        let query = try FindQuery(find: [.text("a")], replace: [.text("b")])
        #expect(replacingAll(query, in: "aaaa", scope: NSRange(location: 1, length: 2)) == "abba")
    }

    @Test func listsMatchRangesUpToALimit() throws {
        let query = try FindQuery(find: [.text("a")])
        let text = "a a a" as NSString
        #expect(query.ranges(in: text, scope: NSRange(location: 0, length: 5), limit: 2)
            == [NSRange(location: 0, length: 1), NSRange(location: 2, length: 1)])
    }

    @Test func countsMatches() throws {
        let query = try FindQuery(find: [.text("ab")])
        let text = "ab abab x" as NSString
        #expect(query.count(in: text, scope: NSRange(location: 0, length: text.length)) == 3)
    }

    @Test func nextSearchesFromSelectionAndWraps() throws {
        let text = "one two one two"
        let query = try FindQuery(find: [.text("one")])
        let all = NSRange(location: 0, length: 15)
        let first = query.next(in: text as NSString, after: NSRange(location: 0, length: 0), scope: all)
        #expect(first?.range == NSRange(location: 0, length: 3))
        let second = query.next(in: text as NSString, after: first!.range, scope: all)
        #expect(second?.range == NSRange(location: 8, length: 3))
        let wrapped = query.next(in: text as NSString, after: second!.range, scope: all)
        #expect(wrapped?.range == NSRange(location: 0, length: 3))
        #expect(query.next(in: text as NSString, after: second!.range, scope: all, wraps: false) == nil)
    }

    @Test func previousSearchesBackwardAndWraps() throws {
        let text = "one two one two"
        let query = try FindQuery(find: [.text("two")])
        let all = NSRange(location: 0, length: 15)
        let last = query.previous(in: text as NSString, before: NSRange(location: 15, length: 0), scope: all)
        #expect(last?.range == NSRange(location: 12, length: 3))
        let earlier = query.previous(in: text as NSString, before: last!.range, scope: all)
        #expect(earlier?.range == NSRange(location: 4, length: 3))
        let wrapped = query.previous(in: text as NSString, before: earlier!.range, scope: all)
        #expect(wrapped?.range == NSRange(location: 12, length: 3))
    }

    @Test func nextSkipsTheEmptyMatchAtTheCaret() throws {
        let text = "a\nb\nc" as NSString
        let query = try FindQuery(find: [.text("^")], options: .init(regex: true))
        let all = NSRange(location: 0, length: text.length)
        let first = query.next(in: text, after: NSRange(location: 0, length: 0), scope: all)
        #expect(first?.range == NSRange(location: 2, length: 0))
    }

    @Test func matchAtSelectionOnlyWhenSelectionIsExactlyAMatch() throws {
        let text = "width=\"1\" x" as NSString
        let query = try FindQuery(find: [.text("width=\""), .placeholder(1), .text("\"")], replace: [.placeholder(1)])
        let all = NSRange(location: 0, length: text.length)
        let match = try #require(query.match(at: NSRange(location: 0, length: 9), in: text, scope: all))
        #expect(query.replacement(for: match, in: text) == "1")
        #expect(query.match(at: NSRange(location: 0, length: 5), in: text, scope: all) == nil)
        #expect(query.match(at: NSRange(location: 1, length: 8), in: text, scope: all) == nil)
    }

    @Test func searchRespectsWordBoundariesAtScopeEdges() throws {
        // Transparent bounds: \b sees the text around the scope.
        let text = "cat concat" as NSString
        let query = try FindQuery(find: [.text(#"\bcat"#)], options: .init(regex: true))
        #expect(query.count(in: text, scope: NSRange(location: 7, length: 3)) == 0)
        #expect(found(query, text as String, query.next(in: text, after: NSRange(location: 1, length: 0),
                                                        scope: NSRange(location: 0, length: 10))) == "cat")
    }

    @Test func previousInAHugeTextOnlyLooksNearTheCaret() throws {
        let query = try FindQuery(find: [.text("needle")])
        let filler = String(repeating: "hay hay hay hay\n", count: 1_500_000)  // 24 MB
        let text = ("needle\n" + filler + "needle here\n" + filler) as NSString
        let all = NSRange(location: 0, length: text.length)
        let start = Date()
        let near = query.previous(in: text, before: NSRange(location: text.length, length: 0), scope: all)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(near?.range.location == 7 + (filler as NSString).length)
        // Far away it still finds the first one.
        let far = query.previous(in: text, before: near!.range, scope: all)
        #expect(far?.range.location == 0)
    }

    @Test func previousWithAPlaceholderMatchingEveryLineIsQuick() throws {
        let query = try FindQuery(find: [.text("hay "), .placeholder(1), .text(" hay")])
        let text = String(repeating: "hay hay hay hay\n", count: 1_500_000) as NSString
        let all = NSRange(location: 0, length: text.length)
        let start = Date()
        let match = query.previous(in: text, before: NSRange(location: text.length, length: 0), scope: all)
        #expect(Date().timeIntervalSince(start) < 0.2)
        #expect(match?.range.location == text.length - 16)
    }

    @Test func previousFindsAMatchAcrossTheWindowEdge() throws {
        let query = try FindQuery(find: [.text("ab")])
        let text = (String(repeating: "x", count: 65_535) + "ab" + String(repeating: "y", count: 10)) as NSString
        let match = query.previous(in: text, before: NSRange(location: text.length, length: 0), scope: NSRange(location: 0, length: text.length))
        #expect(match?.range == NSRange(location: 65_535, length: 2))
    }
}
