import Foundation
import Testing
@testable import EditorCore

struct SyntaxLanguageTests {
    /// The text of every token of `kind`.
    private func found(_ kind: SyntaxKind, _ language: SyntaxLanguage, _ text: String) -> [String] {
        language.tokens(in: text).filter { $0.kind == kind }.map { (text as NSString).substring(with: $0.range) }
    }

    @Test func picksTheLanguageByFileName() {
        #expect(SyntaxLanguage.detect(fileName: "a.JSON") == .json)
        #expect(SyntaxLanguage.detect(fileName: "README.md") == .markdown)
        #expect(SyntaxLanguage.detect(fileName: "index.php") == .php)
        #expect(SyntaxLanguage.detect(fileName: "app.tsx") == .javascript)
        #expect(SyntaxLanguage.detect(fileName: "run.py") == .python)
        #expect(SyntaxLanguage.detect(fileName: ".zshrc") == .shell)
        #expect(SyntaxLanguage.detect(fileName: "main.go") == .go)
        #expect(SyntaxLanguage.detect(fileName: "notes.txt") == nil)
        #expect(SyntaxLanguage.detect(fileName: "app.log") == nil)
        #expect(SyntaxLanguage.detect(fileName: "noextension") == nil)
    }

    @Test func json() {
        let text = #"{"name": "a \"b\"", "n": -1.5e+3, "ok": true, "x": null, "list": ["item"]}"#
        #expect(found(.key, .json, text) == [#""name""#, #""n""#, #""ok""#, #""x""#, #""list""#])
        #expect(found(.string, .json, text) == [#""a \"b\"""#, #""item""#])
        #expect(found(.number, .json, text) == ["-1.5e+3"])
        #expect(found(.keyword, .json, text) == ["true", "null"])
    }

    @Test func markdown() {
        let text = """
        # Title
        ## Second
        #hashtag
        text with `code`, **bold**, *em*, snake_case_name and [a link](http://x.y).
        - item
        1. first
        > quote
        ```swift
        let # not a heading
        ```
        after
        """
        #expect(found(.heading, .markdown, text) == ["# Title", "## Second"])
        #expect(found(.emphasis, .markdown, text) == ["**bold**", "*em*"])
        #expect(found(.link, .markdown, text) == ["[a link](http://x.y)"])
        #expect(found(.keyword, .markdown, text) == ["-", "1."])
        #expect(found(.comment, .markdown, text) == ["> quote"])
        #expect(found(.code, .markdown, text) == ["`code`", "```swift\nlet # not a heading\n```"])
    }

    @Test func aFenceLeftOpenRunsToTheEnd() {
        #expect(found(.code, .markdown, "a\n```\nb\nc") == ["```\nb\nc"])
    }

    @Test func php() {
        let text = """
        <html class="a"><?php
        // note
        # another
        #[Attr]
        FUNCTION go($name) { return "x $name" . 'y' . 12; } /* block */
        ?><b>end</b><?= $v ?>
        """
        #expect(found(.tag, .php, text) == ["html", "b", "b"])
        #expect(found(.comment, .php, text) == ["// note", "# another", "/* block */"])
        #expect(found(.keyword, .php, text) == ["<?php", "FUNCTION", "return", "?>", "<?=", "?>"])
        #expect(found(.variable, .php, text) == ["$name", "$v"])
        #expect(found(.string, .php, text) == [#""a""#, #""x $name""#, "'y'"])
        #expect(found(.number, .php, text) == ["12"])
    }

    @Test func javascriptAndPython() {
        let js = "const a = `x\ny`; // c\nlet b = 'q'; /* d */ if (a1 > 0x1F) {}"
        #expect(found(.keyword, .javascript, js) == ["const", "let", "if"])
        #expect(found(.string, .javascript, js) == ["`x\ny`", "'q'"])
        #expect(found(.comment, .javascript, js) == ["// c", "/* d */"])
        #expect(found(.number, .javascript, js) == ["0x1F"])

        let py = "@cached\ndef f(x):\n    \"\"\"doc\n    more\"\"\"\n    return x  # no\n"
        #expect(found(.keyword, .python, py) == ["@cached", "def", "return"])
        #expect(found(.string, .python, py) == ["\"\"\"doc\n    more\"\"\""])
        #expect(found(.comment, .python, py) == ["# no"])
    }

    @Test func html() {
        let text = #"<!-- c --><!DOCTYPE html><a href="x" data-y='z'>text</a>"#
        #expect(found(.comment, .html, text) == ["<!-- c -->"])
        #expect(found(.keyword, .html, text) == ["<!DOCTYPE html>"])
        #expect(found(.tag, .html, text) == ["a", "a"])
        #expect(found(.key, .html, text) == ["href", "data-y"])
        #expect(found(.string, .html, text) == [#""x""#, "'z'"])
    }

    @Test func css() {
        let text = "/* c */ @media print { a:hover { color: #fff; margin-top: 10px !important; } }"
        #expect(found(.comment, .css, text) == ["/* c */"])
        #expect(found(.keyword, .css, text) == ["@media"])
        #expect(found(.key, .css, text).contains("color") && found(.key, .css, text).contains("margin-top"))
        #expect(found(.number, .css, text) == ["#fff", "10px"])
    }

    @Test func shell() {
        let text = "if [ $# -gt 0 ]; then echo \"$HOME ${X}\" $Y # note\nfi\nurl=a#b\n"
        #expect(found(.keyword, .shell, text) == ["if", "then", "echo", "fi"])
        #expect(found(.variable, .shell, text) == ["$Y"])
        #expect(found(.comment, .shell, text) == ["# note"])
        #expect(found(.string, .shell, text) == ["\"$HOME ${X}\""])
    }

    @Test func yaml() {
        let text = "# top\nname: app # note\nlist:\n  - a: 1\n  - \"b\"\nok: true\nurl: http://x.y\n\"q k\": 'v'\n"
        #expect(found(.comment, .yaml, text) == ["# top", "# note"])
        #expect(found(.key, .yaml, text) == ["name", "list", "a", "ok", "url", "\"q k\""])
        #expect(found(.number, .yaml, text) == ["1"])
        #expect(found(.keyword, .yaml, text) == ["true"])
        #expect(found(.string, .yaml, text) == ["\"b\"", "'v'"])
    }

    @Test func sqlSwiftCAndGo() {
        #expect(found(.keyword, .sql, "select a FROM t -- x") == ["select", "FROM"])
        #expect(found(.comment, .sql, "select a FROM t -- x") == ["-- x"])
        #expect(found(.keyword, .swift, "@MainActor final class A { #if DEBUG\nlet x = 1 }") == ["@MainActor", "final", "class", "#if", "let"])
        #expect(found(.keyword, .cFamily, "#include <a.h>\nint main() { return 0; }") == ["#include", "int", "return"])
        #expect(found(.string, .go, "x := `a\nb`") == ["`a\nb`"])
    }

    @Test func aBackslashIsPlainInShellAndSQLSingleQuotes() {
        #expect(found(.string, .shell, "tr -d '\\' x\necho 'y'") == ["'\\'", "'y'"])
        #expect(found(.string, .sql, "select 'C:\\' , 'd'") == ["'C:\\'", "'d'"])
        #expect(found(.string, .shell, #"echo "a\"b""#) == [#""a\"b""#], "double quotes still escape")
    }

    @Test func backticksClosedOnTheirOwnLineAreNotAFence() {
        let text = "```code``` here\n**bold**\n"
        #expect(found(.code, .markdown, text) == ["```code```"])
        #expect(found(.emphasis, .markdown, text) == ["**bold**"])
    }

    @Test func phpEndsOnlyAtACloseTagOutsideStrings() {
        let text = "<?php echo \"?>\"; return 1; // done ?><b>x</b>"
        #expect(found(.keyword, .php, text) == ["<?php", "echo", "return", "?>"])
        #expect(found(.string, .php, text) == [#""?>""#])
        #expect(found(.comment, .php, text) == ["// done "])
        #expect(found(.tag, .php, text) == ["b", "b"])
    }

    @Test func emphasisAndLinksReachOnlySoFar() {
        let far = String(repeating: "x", count: 1000)
        #expect(found(.emphasis, .markdown, "*" + far + "*").isEmpty)
        #expect(found(.link, .markdown, "[" + far + "](y)").isEmpty)
    }

    @Test func aStringStopsAtItsLineEnd() {
        // A stray quote can't colour the rest of the file.
        let text = "let a = 'open\nlet b = 1"
        #expect(found(.string, .javascript, text) == ["'open"])
        #expect(found(.keyword, .javascript, text) == ["let", "let"])
    }

    @Test func wordsAreNotFoundInsideWords() {
        #expect(found(.keyword, .javascript, "iffy notif x1if ifа").isEmpty)
        #expect(found(.number, .javascript, "a1 b2").isEmpty)
    }

    /// Every language on awkward text: no crash, tokens in order, in bounds.
    @Test(arguments: [SyntaxLanguage.json, .markdown, .yaml, .html, .php, .javascript, .python, .css, .shell, .sql, .swift, .cFamily, .go])
    func survivesAnyText(language: SyntaxLanguage) {
        let samples = [
            "", "\"", "'", "\\", "`", "*", "_", "#", "<", "<?", "<?php", "<a", "<a b=\"", "<!--", "/*", "$", "${", "@", "-", "[", "[a](", "```", ":",
            "😀 \"😀\" # 😀\r\n<a😀>", "\"\\", "a: \"\\", "**", "* *", "__a", "1.", "- ", "?>", "{\"a\"", "\r\r\n\n", "#\r",
        ]
        for sample in samples + samples.map({ $0 + $0 + " x\n" + $0 }) {
            let tokens = language.tokens(in: sample)
            var last = 0
            let length = (sample as NSString).length
            for token in tokens {
                #expect(token.range.location >= last, "\(language.name) on \(sample.debugDescription)")
                #expect(token.range.length > 0 && NSMaxRange(token.range) <= length, "\(language.name) on \(sample.debugDescription)")
                last = NSMaxRange(token.range)
            }
        }
    }

    @Test func scansTwoMegabytesQuickly() {
        let text = "<?php\n" + String(repeating: "function go($a) { return \"x\" . 12; } // note\n", count: 45_000)
        let start = Date()
        #expect(!SyntaxLanguage.php.tokens(in: text).isEmpty)
        #expect(Date().timeIntervalSince(start) < 3, "debug build")
    }
}
