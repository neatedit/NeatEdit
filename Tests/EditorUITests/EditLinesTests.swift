import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// Edit ▸ Edit Lines… in the large file viewer: a sheet with the lines
/// around the caret, saved straight into the file.
@MainActor
final class EditLinesTests: XCTestCase {
    private var savedThreshold = 0

    override func setUp() {
        savedThreshold = TextDocument.largeFileThreshold
        TextDocument.largeFileThreshold = 10
    }

    override func tearDown() { TextDocument.largeFileThreshold = savedThreshold }

    private func openLog(_ text: String) throws -> (TextDocument, LargeFileViewController, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).log")
        try Data(text.utf8).write(to: url)
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? LargeFileViewController)
        controller.view.window?.makeKeyAndOrderFront(nil)
        return (document, controller, url)
    }

    private var log: String { (1...100).map { "line \($0)\n" }.joined() }

    private func offset(of line: String, in controller: LargeFileViewController) -> Int {
        (controller.model.storage.string as NSString).range(of: line).location
    }

    private func wait(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    private func sheet(of controller: LargeFileViewController) throws -> LineEditorController {
        try XCTUnwrap(controller.presentedViewControllers?.first as? LineEditorController)
    }

    func testMenuItemWithCommandReturnWorksOnlyInTheViewer() throws {
        let edit = try XCTUnwrap(MainMenu.make().item(withTitle: "Edit")?.submenu)
        let item = try XCTUnwrap(edit.item(withTitle: "Edit Lines…"))
        XCTAssertEqual(item.keyEquivalent, "\r")
        XCTAssertEqual(item.keyEquivalentModifierMask, .command)
        XCTAssertFalse(EditorViewController(model: EditorModel(file: TextFile(text: "a"))).responds(to: item.action))

        let (document, controller, _) = try openLog(log)
        defer { document.close() }
        XCTAssertTrue(controller.validateMenuItem(item))
    }

    func testOpensTheCaretLineWithTenLinesEachSide() throws {
        let (document, controller, _) = try openLog(log)
        defer { document.close() }
        controller.textView.setSelection(NSRange(location: offset(of: "line 50\n", in: controller), length: 0))
        controller.editLines(nil)
        let editor = try sheet(of: controller)
        XCTAssertEqual(editor.textView.string, (40...60).map { "line \($0)" }.joined(separator: "\n"))
        XCTAssertEqual(editor.titleLabel.stringValue, "Lines 40–60")
        editor.cancel(nil)
        XCTAssertNil(controller.presentedViewControllers?.first)
    }

    func testTheCaretStartsWhereItWasInTheViewer() throws {
        let (document, controller, _) = try openLog(log)
        defer { document.close() }
        let line = offset(of: "line 50\n", in: controller)
        controller.textView.setSelection(NSRange(location: line + 2, length: 3))
        controller.editLines(nil)
        let editor = try sheet(of: controller)
        defer { editor.cancel(nil) }
        let chunkStart = ((1...100).prefix(39).map { "line \($0)\n" }.joined() as NSString).length
        XCTAssertEqual(editor.textView.selectedRange(), NSRange(location: line + 2 - chunkStart, length: 3))
        XCTAssertEqual((editor.textView.string as NSString).substring(with: editor.textView.selectedRange()), "ne ")
        XCTAssertTrue(editor.textView.visibleRect.height > 0)
    }

    func testAnEditTypedStraightAwayLandsOnTheChosenLine() throws {
        let (document, controller, url) = try openLog(log)
        defer { document.close() }
        controller.textView.setSelection(NSRange(location: offset(of: "line 50\n", in: controller), length: 0))
        controller.editLines(nil)
        let editor = try sheet(of: controller)
        editor.textView.insertText("new ", replacementRange: editor.textView.selectedRange())
        editor.save(nil)
        wait { controller.presentedViewControllers?.first == nil }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), log.replacingOccurrences(of: "line 50\n", with: "new line 50\n"))
    }

    func testSavingWritesTheFileAndTheViewerShowsIt() throws {
        let (document, controller, url) = try openLog(log)
        defer { document.close() }
        controller.textView.setSelection(NSRange(location: offset(of: "line 50\n", in: controller), length: 0))
        controller.editLines(nil)
        let editor = try sheet(of: controller)
        let text = editor.textView.string.replacingOccurrences(of: "line 50", with: "EDITED 50\nnew line")
        editor.textView.string = text
        editor.save(nil)
        wait { controller.presentedViewControllers?.first == nil }

        let expected = log.replacingOccurrences(of: "line 50\n", with: "EDITED 50\nnew line\n")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), expected)
        XCTAssertNil(controller.presentedViewControllers?.first, "the sheet closes")
        wait { controller.model.storage.string == expected }
        XCTAssertEqual(controller.model.storage.string, expected)
        XCTAssertFalse(document.isDocumentEdited)
    }

    func testAChangeOnDiskKeepsTheSheetOpenAndSaysWhy() throws {
        let (document, controller, url) = try openLog(log)
        defer { document.close() }
        controller.textView.setSelection(NSRange(location: offset(of: "line 50\n", in: controller), length: 0))
        controller.editLines(nil)
        let editor = try sheet(of: controller)
        let changed = log.replacingOccurrences(of: "line 45", with: "LINE 45")
        try Data(changed.utf8).write(to: url)
        editor.textView.string = "mine"
        editor.save(nil)
        wait { !editor.isSaving }

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), changed, "nothing written")
        XCTAssertTrue(try sheet(of: controller) === editor, "still open, the edit isn't lost")
        XCTAssertFalse(editor.errorLabel.isHidden)
        XCTAssertEqual(editor.errorLabel.stringValue, "These lines changed on disk. Cancel and open them again to edit the current text.")
        editor.cancel(nil)
    }

    func testRightClickSelectsTheLineAndOffersEditLines() throws {
        let (document, controller, _) = try openLog(log)
        defer { document.close() }
        let view = controller.textView
        let row = view.lineRect(forLine: 3)
        let point = view.convert(NSPoint(x: 20, y: row.midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try XCTUnwrap(view.menu(for: event))
        XCTAssertNotNil(menu.items.first { $0.action == #selector(LargeFileViewController.editLines(_:)) })
        XCTAssertEqual(controller.model.lineIndex.line(containing: view.selection.location), 3)
    }

    func testATypoFixOfTheSameLengthShowsUpInTheViewer() throws {
        // Far from the end, so the tail's 4 KB sample can't notice it.
        let big = (1...2000).map { "line \($0)\n" }.joined()
        let (document, controller, url) = try openLog(big)
        defer { document.close() }
        controller.textView.setSelection(NSRange(location: offset(of: "line 20\n", in: controller), length: 0))
        controller.editLines(nil)
        let editor = try sheet(of: controller)
        editor.textView.string = editor.textView.string.replacingOccurrences(of: "line 20\n", with: "LINE 20\n")
        editor.save(nil)
        let expected = big.replacingOccurrences(of: "line 20\n", with: "LINE 20\n")
        wait { controller.model.storage.string == expected }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), expected)
        XCTAssertEqual(controller.model.storage.string, expected)
    }

    func testNewLinesInACRLFFileGetCRLF() throws {
        let crlf = (1...100).map { "line \($0)\r\n" }.joined()
        let (document, controller, url) = try openLog(crlf)
        defer { document.close() }
        controller.textView.setSelection(NSRange(location: offset(of: "line 50\r", in: controller), length: 0))
        controller.editLines(nil)
        let editor = try sheet(of: controller)
        editor.textView.string = editor.textView.string.replacingOccurrences(of: "line 50", with: "line 50\nadded")
        editor.save(nil)
        wait { controller.presentedViewControllers?.first == nil }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), crlf.replacingOccurrences(of: "line 50\r\n", with: "line 50\r\nadded\r\n"))
    }
}
