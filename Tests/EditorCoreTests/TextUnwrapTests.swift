import Testing
@testable import EditorCore

struct TextUnwrapTests {
    /// Greedy word wrap the way a terminal UI does it: every line gets
    /// `indent`, continuation lines of a list item also get `hang`.
    private func wrap(_ paragraph: String, width: Int, indent: String = "  ", hang: String = "") -> [String] {
        var lines: [String] = []
        var current = indent
        var first = true
        for word in paragraph.split(separator: " ") {
            let prefix = first ? indent : indent + hang
            if current.count > prefix.count, current.count + 1 + word.count > width {
                lines.append(current)
                current = indent + hang + word
                first = false
            } else {
                current += (current.count > prefix.count ? " " : "") + word
            }
        }
        lines.append(current)
        return lines
    }

    private let sentence = "Play strongly ranks apps by rating, so it is worth adding the built-in review prompt from Google and showing it right after a good moment, for example when the AI recognized a box or something was found."

    @Test func claudeCodeSampleIsUnwrapped() {
        let pasted = """
              5. Caniipu v raatpu. Lmsv sugmtr lltain ol levcutirm. Cllcr nrnlcu c olscrsitrp csinrcltuv olduc raatpu can Oddome (Lmsv Vr-Sll Ceaveo): drploiclcu vrir dasgd cnlgrir mrmetci, tldlupgln prgu SV lrodaotlc
              prlrspi lsr vrsm otlvugrsd. Ae tecegupl olnlol c prna, mrai olrsucu rplemum LC.
            """
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == "5. Caniipu v raatpu. Lmsv sugmtr lltain ol levcutirm. Cllcr nrnlcu c olscrsitrp csinrcltuv olduc raatpu can Oddome (Lmsv Vr-Sll Ceaveo): drploiclcu vrir dasgd cnlgrir mrmetci, tldlupgln prgu SV lrodaotlc prlrspi lsr vrsm otlvugrsd. Ae tecegupl olnlol c prna, mrai olrsucu rplemum LC.")
    }

    @Test func wrappedParagraphsComeBackWhole() {
        let second = "A second paragraph that is also long enough to wrap over more than one line of the terminal window."
        let pasted = (wrap(sentence, width: 60) + [""] + wrap(second, width: 60)).joined(separator: "\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == sentence + "\n\n" + second)
    }

    @Test func listItemsStaySeparateAndHangingIndentIsJoined() {
        let item = "- " + sentence
        let pasted = (wrap(item, width: 70, hang: "  ") + ["  - Short item.", "  - Another short one."]).joined(separator: "\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == item + "\n- Short item.\n- Another short one.")
    }

    @Test func trailingSpacesAreTrimmed() {
        let pasted = wrap(sentence, width: 50).map { $0 + "   " }.joined(separator: "\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == sentence)
    }

    @Test func codeIsLeftAlone() {
        let code = """
            func makeTextBigger(_ sender: Any?) { Preferences.fontSize += 1; NotificationCenter.default.post(name: x) }
            func makeTextSmaller(_ sender: Any?) { Preferences.fontSize -= 1; NotificationCenter.default.post(name: y) }
            func makeTextStandardSize(_ sender: Any?) { Preferences.fontSize = Preferences.defaultFontSize }
            """
        #expect(TextUnwrap.unwrapIfWrapped(code) == nil)
    }

    @Test func poemIsLeftAlone() {
        let poem = "Roses are red,\nviolets are blue,\nsugar is sweet,\nand so are you."
        #expect(TextUnwrap.unwrapIfWrapped(poem) == nil)
    }

    @Test func singleLineIsLeftAlone() {
        #expect(TextUnwrap.unwrapIfWrapped("  just one line  ") == nil)
    }

    @Test func fencedCodeInsideWrappedTextIsKept() {
        let pasted = (wrap(sentence, width: 60) + ["  ```", "  let a = 1", "  let b = 2", "  ```"]).joined(separator: "\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == sentence + "\n```\nlet a = 1\nlet b = 2\n```")
    }

    @Test func headingsAndTablesStartNewLines() {
        let pasted = (wrap(sentence, width: 60) + ["  # Heading", "  | a | b |"]).joined(separator: "\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == sentence + "\n# Heading\n| a | b |")
    }

    @Test func manualUnwrapJoinsWithoutIndent() {
        let pasted = wrap(sentence, width: 60, indent: "").joined(separator: "\n")
        #expect(TextUnwrap.unwrap(pasted) == sentence)
    }

    @Test func keepsWindowsLineEndings() {
        let pasted = (wrap(sentence, width: 60) + ["", "  End."]).joined(separator: "\r\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == sentence + "\r\n\r\nEnd.")
    }
}
