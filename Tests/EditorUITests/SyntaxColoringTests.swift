import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// Colours from the file's name, kept out of the text.
@MainActor
final class SyntaxColoringTests: XCTestCase {
    private var saved: UserDefaults!
    private var savedLimit = 0

    override func setUp() {
        saved = Preferences.defaults
        Preferences.defaults = UserDefaults(suiteName: "SyntaxColoringTests-\(UUID().uuidString)")!
        Preferences.registerDefaults()
        savedLimit = SyntaxColoring.lengthLimit
    }

    override func tearDown() {
        Preferences.defaults = saved
        SyntaxColoring.lengthLimit = savedLimit
    }

    private func open(_ text: String, name: String) throws -> (TextDocument, EditorViewController, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorViewController)
        controller.view.window?.setContentSize(NSSize(width: 500, height: 300))
        controller.view.window?.makeKeyAndOrderFront(nil)
        return (document, controller, url)
    }

    private func wait(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }

    func testAJSONFileIsColouredAndItsTextIsUntouched() throws {
        let text = #"{"name": "value", "n": 12}"#
        let (document, controller, _) = try open(text, name: "a.json")
        defer { document.close() }
        let coloring = controller.syntaxColoring
        wait { coloring.color(at: 1) != nil }
        XCTAssertEqual(coloring.color(at: 1), .syntax(.key))
        XCTAssertEqual(coloring.color(at: 9), .syntax(.string))
        XCTAssertNil(coloring.color(at: 0))
        let storage = controller.model.storage
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, _, _ in
            XCTAssertEqual(attributes[.foregroundColor] as? NSColor, .textColor, "no colours in the storage")
        }
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertFalse(controller.textView.undoManager?.canUndo ?? false)
    }

    func testAPlainTextFileHasNoColours() throws {
        let (document, controller, _) = try open("if \"x\" 12", name: "notes.txt")
        defer { document.close() }
        settle()
        XCTAssertNil(controller.syntaxColoring.color(at: 0))
        XCTAssertNil(controller.syntaxColoring.color(at: 3))
    }

    func testTypingRecolours() throws {
        let (document, controller, _) = try open("let a", name: "a.js")
        defer { document.close() }
        let coloring = controller.syntaxColoring
        wait { coloring.color(at: 0) != nil }
        controller.textView.setSelectedRange(NSRange(location: 5, length: 0))
        controller.textView.insertText(" // note", replacementRange: controller.textView.selectedRange())
        wait { coloring.color(at: 8) == .syntax(.comment) }
        XCTAssertEqual(coloring.color(at: 8), .syntax(.comment))
    }

    func testAnUnterminatedCommentRecoloursTheTextAfterIt() throws {
        let (document, controller, _) = try open("let a\nlet b\n", name: "a.js")
        defer { document.close() }
        let coloring = controller.syntaxColoring
        wait { coloring.color(at: 6) == .syntax(.keyword) }
        controller.textView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.textView.insertText("/*", replacementRange: NSRange(location: 0, length: 0))
        wait { coloring.color(at: 8) == .syntax(.comment) }
        XCTAssertEqual(coloring.color(at: 8), .syntax(.comment))
    }

    func testScrollingColoursWhatComesIntoView() throws {
        let text = (1...20_000).map { "let a\($0) = \($0)\n" }.joined()
        let (document, controller, _) = try open(text, name: "a.js")
        defer { document.close() }
        let coloring = controller.syntaxColoring
        wait { coloring.color(at: 0) != nil }
        let offset = controller.model.lineIndex.starts[15_000]
        XCTAssertNil(coloring.color(at: offset), "only near the screen")
        controller.textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
        wait { coloring.color(at: offset) != nil }
        XCTAssertEqual(coloring.color(at: offset), .syntax(.keyword))
    }

    func testTheViewMenuTurnsThemOff() throws {
        let (document, controller, _) = try open("let a", name: "a.js")
        defer { document.close() }
        let coloring = controller.syntaxColoring
        wait { coloring.color(at: 0) != nil }
        let view = try XCTUnwrap(MainMenu.make().item(withTitle: "View")?.submenu)
        let item = try XCTUnwrap(view.item(withTitle: "Syntax Highlighting"))
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .on)
        controller.toggleSyntaxHighlighting(nil)
        wait { coloring.color(at: 0) == nil }
        XCTAssertNil(coloring.color(at: 0))
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)
        controller.toggleSyntaxHighlighting(nil)
        wait { coloring.color(at: 0) != nil }
        XCTAssertNotNil(coloring.color(at: 0))
    }

    func testTextOverTheLimitStaysPlain() throws {
        SyntaxColoring.lengthLimit = 3
        let (document, controller, _) = try open("let a", name: "a.js")
        defer { document.close() }
        settle()
        XCTAssertNil(controller.syntaxColoring.color(at: 0))
    }

    func testRevertingToNewTextColoursIt() throws {
        let (document, controller, _) = try open("let a", name: "a.js")
        defer { document.close() }
        let coloring = controller.syntaxColoring
        wait { coloring.color(at: 0) != nil }
        controller.replaceModel(EditorModel(file: TextFile(text: "x = 'q'")))
        wait { coloring.color(at: 4) == .syntax(.string) }
        XCTAssertEqual(coloring.color(at: 4), .syntax(.string))
    }

    func testSavingUnderAnotherNameChangesTheLanguage() throws {
        let (document, controller, url) = try open("let a", name: "a.txt")
        defer { document.close() }
        settle()
        XCTAssertNil(controller.syntaxColoring.color(at: 0))
        document.fileURL = url.deletingLastPathComponent().appendingPathComponent("a.js")
        wait { controller.syntaxColoring.color(at: 0) != nil }
        XCTAssertEqual(controller.syntaxColoring.color(at: 0), .syntax(.keyword))
    }

    func testAScrollRightAfterAnEditDoesNotLockInOldColours() throws {
        let text = (1...200).map { "let a\($0)\n" }.joined()
        let (document, controller, _) = try open(text, name: "a.js")
        defer { document.close() }
        let coloring = controller.syntaxColoring
        wait { coloring.color(at: 0) == .syntax(.keyword) }
        controller.textView.insertText("// x\n", replacementRange: NSRange(location: 0, length: 0))
        controller.textView.scroll(NSPoint(x: 0, y: 2))
        wait { coloring.color(at: 0) == .syntax(.comment) }
        XCTAssertEqual(coloring.color(at: 0), .syntax(.comment))
    }

    func testColoursGoWhenTheTextNoLongerHasAny() throws {
        let (document, controller, _) = try open("# abc", name: "a.py")
        defer { document.close() }
        let coloring = controller.syntaxColoring
        wait { coloring.color(at: 2) != nil }
        controller.textView.insertText("", replacementRange: NSRange(location: 0, length: 1))
        wait { coloring.color(at: 2) == nil }
        XCTAssertNil(coloring.color(at: 2))
    }

    func testOneHugeLineIsOnlyColouredAroundTheScreen() throws {
        Preferences.wrapsLines = false
        let (document, controller, _) = try open("[" + String(repeating: "1,", count: 150_000) + "2]", name: "a.json")
        defer { document.close() }
        let coloring = controller.syntaxColoring
        wait { coloring.color(at: 1) != nil }
        XCTAssertEqual(coloring.color(at: 1), .syntax(.number))
        XCTAssertNil(coloring.color(at: 200_001), "far past the window")

        // Scrolled along the line, the colours follow.
        let lm = try XCTUnwrap(controller.textView.layoutManager)
        let x = lm.location(forGlyphAt: lm.glyphIndexForCharacter(at: 200_001)).x
        controller.textView.enclosingScrollView?.contentView.scroll(to: NSPoint(x: x, y: 0))
        wait { coloring.color(at: 200_001) != nil }
        XCTAssertNotNil(coloring.color(at: 200_001))
    }

    func testAWindowMadeBiggerColoursWhatItNowShows() throws {
        let text = (1...2000).map { "let a\($0)\n" }.joined()
        let (document, controller, _) = try open(text, name: "a.js")
        defer { document.close() }
        let coloring = controller.syntaxColoring
        wait { coloring.color(at: 0) != nil }
        // The first line past what's been painted so far.
        let starts = controller.model.lineIndex.starts
        let row = try XCTUnwrap(starts.first { coloring.color(at: $0) == nil })
        controller.view.window?.setContentSize(NSSize(width: 500, height: 3000))
        wait { coloring.color(at: row) != nil }
        XCTAssertEqual(coloring.color(at: row), .syntax(.keyword))
    }

    func testTurnedOffWhileTheFirstScanRunsStaysOff() throws {
        let text = String(repeating: "let a = 1\n", count: 100_000)
        let (document, controller, _) = try open(text, name: "a.js")
        defer { document.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))  // the scan has started
        controller.toggleSyntaxHighlighting(nil)
        settle()
        settle()
        XCTAssertNil(controller.syntaxColoring.color(at: 0))
    }

    func testTheViewerOffersNoColours() throws {
        let threshold = TextDocument.largeFileThreshold
        defer { TextDocument.largeFileThreshold = threshold }
        TextDocument.largeFileThreshold = 3
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).js")
        try Data("let a\nlet b\n".utf8).write(to: url)
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        defer { document.close() }
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? LargeFileViewController)
        let view = try XCTUnwrap(MainMenu.make().item(withTitle: "View")?.submenu)
        XCTAssertFalse(controller.validateMenuItem(try XCTUnwrap(view.item(withTitle: "Syntax Highlighting"))))
    }
}
