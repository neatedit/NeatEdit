import Foundation
import Testing
@testable import EditorCore

struct TextUnwrapTests {
    /// Greedy word wrap the way a terminal UI does it: every line gets
    /// `indent`, continuation lines of a list item also get `hang`.
    private func wrap(_ paragraph: String, width: Int, indent: String = "  ", hang: String = "") -> [String] {
        var lines: [String] = []
        var current = indent
        for word in paragraph.split(separator: " ") {
            let isFresh = current.allSatisfy { $0 == " " }
            if !isFresh, current.count + 1 + word.count > width {
                lines.append(current)
                current = indent + hang + word
            } else {
                current += (isFresh ? "" : " ") + word
            }
        }
        lines.append(current)
        return lines
    }

    private let sentence = "Play strongly ranks apps by rating, so it is worth adding the built-in review prompt from Google and showing it right after a good moment, for example when the AI recognized a box or something was found in one of the places."

    // MARK: Unwrapped

    @Test func claudeCodeSampleIsUnwrapped() {
        let pasted = """
              5. Caniipu v raatpu. Lmsv sugmtr lltain ol levcutirm. Cllcr nrnlcu c olscrsitrp csinrcltuv olduc raatpu can Oddome (Lmsv Vr-Sll Ceaveo): drploiclcu vrir dasgd cnlgrir mrmetci, tldlupgln prgu SV lrodaotlc
              prlrspi lsr vrsm otlvugrsd. Ae tecegupl olnlol c prna, mrai olrsucu rplemum LC.
            """
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == "5. Caniipu v raatpu. Lmsv sugmtr lltain ol levcutirm. Cllcr nrnlcu c olscrsitrp csinrcltuv olduc raatpu can Oddome (Lmsv Vr-Sll Ceaveo): drploiclcu vrir dasgd cnlgrir mrmetci, tldlupgln prgu SV lrodaotlc prlrspi lsr vrsm otlvugrsd. Ae tecegupl olnlol c prna, mrai olrsucu rplemum LC.")
    }

    @Test func claudeCodeAnswerWithListsQuotesAndMarkerIsUnwrapped() {
        let pasted = """
            ⏺ Oirnet: seo nocatpac a deleduspu. Rnut gusc, i dprmi cae n cse: vr crtu rclumircm, vr can tue clesl, vr ae prucin. Candrcanm drclastl rntl, «clp», a crtu rclumircm ircrcuv prmdgepc.

              Cllaltc S — rsmat seo ilruev. Llnai slme o tmrir droutlcu.
              - Vr rclumircm crtu. Seoprucrcti «naupi» ngd scroe pgantcac: «otlvce, vr geaucm i clurmi srpsa». Ve masdam-clu Lcd seoprucrctr ngd oetae pgantcac, l Lcd — ae tersmeaete nrcr-lrodaotlclttd (i Acee crtr
                rsmeaete tl masdam). Dgrs scrlatpl-oilnpl tl resngeln.idt i lronaga «spglnu-dllctelu» o drsuglttdm tl tue: ngd tue ae ocrlrcte drsuglttd a pgantcu o druipi.
              - Vr lrsgdcm crtu. Rnti o clmre leoev tl cusal, isa ecugutta:
                - caulrcm tl leaedaao lsr sagd cerni S4-drscel o SC;
                - nrnlrcm ldnrp a drsuglttd i caclgmtuv gusc trcrmi pgantci;

              Cllaltc C — dllctelpl o cansrcprm. Dp nrdrctettd nr S, ngd cue, prmi olmlgr dlrscr «naupu». Dllctel rclumin, tldlupgln, 30 % can delurir lrpi dglctro danduspu cue, ecr dluvurc o vrir prni. Mrcucin sugmtaue,
              lge drclasta rsgap a cudglcu. Dlrdrticlcu llnai o nliiro ecuga, prgu sine vr lleiclcu.

              ▎ Uv, V't nue adernec da Resngeln, sr sll nusn meni ledlme ludndocslu sr dler cdu srn oen s mvin da ousn'i vrivne, nuer iesciu "ouece'i nue ncvmm?" sicdii smm nuevc lmsiei, vrimenvro nuevc indcsoe ervn.
              ▎ Rdre da nue indcsoe slli oe'ae ieer nd nuvi; vdeci usrnmei cddgvro srn siieii, deci usrnmei ousn'i vrivne nue cdu.
              ▎
              ▎ Nue daaec, acee:
              ▎ – vdec ieindteci oen 3 tdrnui da Resngeln Lcd ovnu vdec idne;
              ▎ – oe mvin vde dr resngeln.idt/lscnreci (s mvrg nd vdec ivne);

              1. Dlrmrprnu. I Oddome Lmsv n dlrmrprnu tl danduspi, a oe delecalucu clesl deluumu. Dpvr oe olmlgr (gamac tl pcllclg) lsr drclaset ve v ces, lrsumr scav dllctelsmpuv prn: Lcd tl R masdaac a rsgap, ecr prir
                 dlucac. Ae tecegupl olnlol c sepetna.
            """
        let expected = """
            Oirnet: seo nocatpac a deleduspu. Rnut gusc, i dprmi cae n cse: vr crtu rclumircm, vr can tue clesl, vr ae prucin. Candrcanm drclastl rntl, «clp», a crtu rclumircm ircrcuv prmdgepc.

            Cllaltc S — rsmat seo ilruev. Llnai slme o tmrir droutlcu.
            - Vr rclumircm crtu. Seoprucrcti «naupi» ngd scroe pgantcac: «otlvce, vr geaucm i clurmi srpsa». Ve masdam-clu Lcd seoprucrctr ngd oetae pgantcac, l Lcd — ae tersmeaete nrcr-lrodaotlclttd (i Acee crtr rsmeaete tl masdam). Dgrs scrlatpl-oilnpl tl resngeln.idt i lronaga «spglnu-dllctelu» o drsuglttdm tl tue: ngd tue ae ocrlrcte drsuglttd a pgantcu o druipi.
            - Vr lrsgdcm crtu. Rnti o clmre leoev tl cusal, isa ecugutta:
              - caulrcm tl leaedaao lsr sagd cerni S4-drscel o SC;
              - nrnlrcm ldnrp a drsuglttd i caclgmtuv gusc trcrmi pgantci;

            Cllaltc C — dllctelpl o cansrcprm. Dp nrdrctettd nr S, ngd cue, prmi olmlgr dlrscr «naupu». Dllctel rclumin, tldlupgln, 30 % can delurir lrpi dglctro danduspu cue, ecr dluvurc o vrir prni. Mrcucin sugmtaue, lge drclasta rsgap a cudglcu. Dlrdrticlcu llnai o nliiro ecuga, prgu sine vr lleiclcu.

            ▎ Uv, V't nue adernec da Resngeln, sr sll nusn meni ledlme ludndocslu sr dler cdu srn oen s mvin da ousn'i vrivne, nuer iesciu "ouece'i nue ncvmm?" sicdii smm nuevc lmsiei, vrimenvro nuevc indcsoe ervn. Rdre da nue indcsoe slli oe'ae ieer nd nuvi; vdeci usrnmei cddgvro srn siieii, deci usrnmei ousn'i vrivne nue cdu.
            ▎
            ▎ Nue daaec, acee:
            ▎ – vdec ieindteci oen 3 tdrnui da Resngeln Lcd ovnu vdec idne;
            ▎ – oe mvin vde dr resngeln.idt/lscnreci (s mvrg nd vdec ivne);

            1. Dlrmrprnu. I Oddome Lmsv n dlrmrprnu tl danduspi, a oe delecalucu clesl deluumu. Dpvr oe olmlgr (gamac tl pcllclg) lsr drclaset ve v ces, lrsumr scav dllctelsmpuv prn: Lcd tl R masdaac a rsgap, ecr prir dlucac. Ae tecegupl olnlol c sepetna.
            """
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == expected)
    }

    @Test func wrappedParagraphsComeBackWhole() {
        let second = "A second paragraph that is also long enough to wrap over more than one line of the terminal window, and then some more words."
        let pasted = (wrap(sentence, width: 80) + [""] + wrap(second, width: 80)).joined(separator: "\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == sentence + "\n\n" + second)
    }

    @Test func listItemsStaySeparateAndHangingIndentIsJoined() {
        let item = "- " + sentence
        let pasted = (wrap(item, width: 80, hang: "  ") + ["  - Short item.", "  - Another short one."]).joined(separator: "\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == item + "\n- Short item.\n- Another short one.")
    }

    @Test func trailingSpacesAreTrimmed() {
        let pasted = wrap(sentence, width: 80).map { $0 + "   " }.joined(separator: "\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == sentence)
    }

    @Test func fencedCodeInsideWrappedTextIsKept() {
        let pasted = (wrap(sentence, width: 80) + ["  ```", "  let a = 1  ", "      let b = 2", "  ```"]).joined(separator: "\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == sentence + "\n```\nlet a = 1  \n    let b = 2\n```")
    }

    @Test func headingsTablesAndBoxTablesKeepTheirLines() {
        let box = ["  ┌───────────┬──────────────┐", "  │ File      │ Change       │", "  ├───────────┼──────────────┤", "  │ Foo.swift │ adds a thing │", "  └───────────┴──────────────┘"]
        let pasted = (wrap(sentence, width: 80) + ["  # Heading", "  | a | b |"] + box).joined(separator: "\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == ([sentence, "# Heading", "| a | b |"] + box.map { String($0.dropFirst(2)) }).joined(separator: "\n"))
    }

    @Test func cjkJoinsWithoutASpace() {
        let line1 = "  " + String(repeating: "漢字", count: 20)
        let line2 = "  " + String(repeating: "かな", count: 5)
        let line3 = "  " + String(repeating: "文章", count: 20)
        let line4 = "  終わり"
        let pasted = [line1, line2, "", line3, line4].joined(separator: "\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == String(repeating: "漢字", count: 20) + String(repeating: "かな", count: 5)
            + "\n\n" + String(repeating: "文章", count: 20) + "終わり")
    }

    @Test func manualUnwrapJoinsWithoutMargin() {
        let pasted = wrap(sentence, width: 60, indent: "").joined(separator: "\n")
        #expect(TextUnwrap.unwrap(pasted) == sentence)
    }

    @Test func keepsWindowsLineEndings() {
        let pasted = (wrap(sentence, width: 80) + ["", "  End."]).joined(separator: "\r\n")
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == sentence + "\r\n\r\nEnd.")
    }

    // MARK: Left alone

    @Test(arguments: [
        // shell commands with a margin
        "  git commit -m \"Unwrap terminal-wrapped text on paste properly\"\n  git push origin main",
        // function body
        "        result = compute_something(argument_one, argument_two)\n        return result",
        // code with braces
        "func makeTextBigger(_ sender: Any?) { Preferences.fontSize += 1; NotificationCenter.default.post(name: x) }\nfunc makeTextSmaller(_ sender: Any?) { Preferences.fontSize -= 1; NotificationCenter.default.post(name: y) }\nfunc makeTextStandardSize(_ sender: Any?) { Preferences.fontSize = Preferences.defaultFontSize }",
        // python
        "def load(path):\n    with open(path) as handle:\n        data = json.load(handle)  # parse the whole configuration file right here now\n    if not data:\n        raise ValueError(\"empty configuration file found at the given path, please check\")\n    return data",
        // yaml
        "services:\n  web:\n    image: registry.example.com/team/web-application-server:1.2.3\n    command: bundle exec puma -C config/puma.rb --environment production --port 3000\n    environment:\n      RAILS_ENV: production",
        // csv
        "id,name,email,created_at,updated_at,status,plan,country\n1,Alice,alice@example.com,2026-01-01,2026-02-01,active,pro,UA\n2,Bob,bob@example.com,2026-01-02,2026-02-02,active,free,PL\n3,Carol,carol@example.com,2026-01-03,2026-02-03,closed,pro,DE",
        // logs
        "2026-10-28 22:01:13.456 INFO  [main] Starting application server on port 8080 with profile production and 16 workers\n2026-10-28 22:01:13.789 INFO  [main] Connected to database primary.example.internal:5432 in 120 ms\n2026-10-28 22:01:14.001 WARN  [pool-1] Slow query detected on table inventory_items, took 1530 ms to complete\n2026-10-28 22:01:14.002 INFO  [main] Ready",
        // java stack trace
        "Exception in thread \"main\" java.lang.IllegalStateException: Something went wrong while loading the configuration\n\tat com.example.app.config.ConfigurationLoader.load(ConfigurationLoader.java:42)\n\tat com.example.app.Main.main(Main.java:17)",
        // python traceback
        "Traceback (most recent call last):\n  File \"/Users/me/projects/application/scripts/import_inventory_from_spreadsheet.py\", line 10, in <module>\n    main()\n  File \"/Users/me/projects/application/scripts/import_inventory_from_spreadsheet.py\", line 6, in main\n    raise ValueError(\"bad row\")",
        // poem
        "Roses are red,\nviolets are blue,\nsugar is sweet,\nand so are you.",
        // address
        "  Acmeboxy Ltd., 12 Example Street, Office 4, Kyiv 01001\n  Ukraine",
        // a single line
        "  just one line  ",
    ])
    func leftAlone(_ text: String) {
        #expect(TextUnwrap.unwrapIfWrapped(text) == nil)
    }

    @Test func hugePastesAreLeftAlone() {
        let pasted = Array(repeating: wrap(sentence, width: 80).joined(separator: "\n"), count: 2_000).joined(separator: "\n\n")
        #expect(pasted.utf8.count > TextUnwrap.maxAutoLength)
        #expect(TextUnwrap.unwrapIfWrapped(pasted) == nil)
    }

    @Test func largeUnwrapIsFast() {
        let pasted = Array(repeating: wrap(sentence, width: 80).joined(separator: "\n"), count: 1_000).joined(separator: "\n\n")
        let start = Date()
        let result = TextUnwrap.unwrap(pasted)
        #expect(Date().timeIntervalSince(start) < 1.0)
        #expect(result.hasPrefix(sentence + "\n\n"))
    }
}
