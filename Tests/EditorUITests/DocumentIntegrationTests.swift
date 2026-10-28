import AppKit
import XCTest
import EditorCore
@testable import EditorUI

@MainActor
final class DocumentIntegrationTests: XCTestCase {
    private func open(_ data: Data) throws -> (TextDocument, EditorViewController) {
        let document = TextDocument()
        try document.read(from: data, ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorViewController)
        _ = controller.view
        return (document, controller)
    }

    private func drainMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    func testUntitledDocumentsSaveAsTxtByDefault() {
        let document = TextDocument()
        // Restored untitled tabs come back typed as generic data/text, which has no extension.
        for type in ["public.plain-text", "public.data", "public.text"] {
            XCTAssertEqual(document.fileNameExtension(forType: type, saveOperation: .saveAsOperation), "txt", type)
        }
    }

    func testSavedFilesKeepTheirOwnExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Makefile")
        try Data("all:\n".utf8).write(to: url)
        let document = try TextDocument(contentsOf: url, ofType: "public.data")
        XCTAssertNil(document.fileNameExtension(forType: "public.data", saveOperation: .saveAsOperation))
    }

    func testOpensFileAndShowsStatus() throws {
        let (_, controller) = try open(Data("hello\nсвіт\n".utf8))
        XCTAssertEqual(controller.textView.string, "hello\nсвіт\n")
        XCTAssertEqual(controller.leftStatus.stringValue, "Ln 1, Col 1   Pos 0   Line 5 chars")
        XCTAssertEqual(controller.rightStatus, "11 chars, 3 lines   UTF-8   LF")
    }

    func testStatusFollowsTypingAndSelection() throws {
        let (_, controller) = try open(Data("hello\nсвіт".utf8))
        let textView = controller.textView
        textView.setSelectedRange(NSRange(location: 8, length: 0))
        textView.insertText("ХХ", replacementRange: textView.selectedRange())
        drainMainQueue()
        XCTAssertEqual(controller.leftStatus.stringValue, "Ln 2, Col 5   Pos 10   Line 6 chars")

        textView.setSelectedRange(NSRange(location: 6, length: 6))
        drainMainQueue()
        XCTAssertEqual(controller.leftStatus.stringValue, "Ln 2, Col 1   Pos 6   Line 6 chars   Sel 6")
    }

    func testSavesInOriginalEncodingAndLineEndings() throws {
        let original = "a\r\nб".data(using: .windowsCP1251)!
        let (document, controller) = try open(original)
        controller.textView.setSelectedRange(NSRange(location: 4, length: 0))
        controller.textView.insertText("\nв", replacementRange: controller.textView.selectedRange())
        XCTAssertEqual(try document.data(ofType: "public.plain-text"), "a\r\nб\r\nв".data(using: .windowsCP1251)!)
    }

    func testChoosingLineEndingConvertsAndUndoes() throws {
        let (document, controller) = try open(Data("a\nb".utf8))
        let undoManager = try XCTUnwrap(controller.textView.undoManager)
        controller.setLineEnding(LineEnding.crlf)
        drainMainQueue()
        XCTAssertEqual(try document.data(ofType: "public.plain-text"), Data("a\r\nb".utf8))
        XCTAssertEqual(controller.statusBar.lineEndingButton.title, "CRLF")
        XCTAssertTrue(document.isDocumentEdited)

        undoManager.undo()
        drainMainQueue()
        XCTAssertEqual(controller.textView.string, "a\nb")
        XCTAssertEqual(controller.statusBar.lineEndingButton.title, "LF")
        XCTAssertEqual(try document.data(ofType: "public.plain-text"), Data("a\nb".utf8))
    }

    func testLineEndingMenuListsAllChoices() throws {
        let (_, controller) = try open(Data("a".utf8))
        let menu = controller.statusBar.lineEndingMenu()
        XCTAssertEqual(menu.items.map(\.title), ["LF", "CRLF", "CR"])
        XCTAssertEqual(menu.items.map(\.state), [.on, .off, .off])
    }

    private func openFile(_ data: Data, name: String) throws -> (TextDocument, EditorViewController) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorViewController)
        _ = controller.view
        return (document, controller)
    }

    func testReopenWithEncodingRedecodesFileBytes() throws {
        let (document, controller) = try openFile("привіт".data(using: .windowsCP1251)!, name: "cp1251.txt")
        XCTAssertEqual(controller.textView.string, "привіт")

        try document.reopen(with: .isoLatin1)
        XCTAssertEqual(controller.textView.string, "ïðèâ³ò")
        XCTAssertEqual(controller.statusBar.encodingButton.title, "ISO-8859-1")
        XCTAssertFalse(document.isDocumentEdited)

        XCTAssertThrowsError(try document.reopen(with: .utf8))
        XCTAssertEqual(controller.textView.string, "ïðèâ³ò")

        try document.reopen(with: .windowsCP1251)
        XCTAssertEqual(controller.textView.string, "привіт")
    }

    func testSaveWithEncodingChangesBytesAndMarksEdited() throws {
        let (document, controller) = try open(Data("hi".utf8))
        XCTAssertTrue(controller.applySaveEncoding(.utf16LittleEndian))
        drainMainQueue()
        XCTAssertEqual(try document.data(ofType: "public.plain-text"), Data([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00]))
        XCTAssertEqual(controller.statusBar.encodingButton.title, "UTF-16 LE")
        XCTAssertTrue(document.isDocumentEdited)
    }

    func testSaveWithEncodingRefusesTextThatDoesNotFit() throws {
        let (document, controller) = try open(Data("привіт".utf8))
        XCTAssertFalse(controller.applySaveEncoding(.isoLatin1))
        XCTAssertEqual(controller.statusBar.encodingButton.title, "UTF-8")
        XCTAssertFalse(document.isDocumentEdited)
    }

    func testEncodingMenuSections() throws {
        let (_, untitled) = try open(Data("x".utf8))
        let saveOnly = untitled.encodingMenu()
        XCTAssertEqual(saveOnly.items.first?.title, "Save with Encoding")
        XCTAssertEqual(saveOnly.items.filter { $0.state == .on }.map(\.title), ["UTF-8"])

        let (_, file) = try openFile(Data("x".utf8), name: "x.txt")
        let both = file.encodingMenu()
        XCTAssertEqual(both.items.first?.title, "Reopen with Encoding")
        XCTAssertEqual(both.items.filter(\.isSectionHeader).map(\.title), ["Reopen with Encoding", "Save with Encoding"])
        XCTAssertEqual(both.items.count, 2 + 1 + 2 * TextFile.choices.count)
    }

    func testEditsMarkDocumentDirty() throws {
        let (document, controller) = try open(Data("x".utf8))
        XCTAssertFalse(document.isDocumentEdited)
        controller.textView.insertText("y", replacementRange: NSRange(location: 1, length: 0))
        drainMainQueue()
        XCTAssertTrue(document.isDocumentEdited)
    }

    func testRevertSwapsTextIntoOpenTab() throws {
        let (document, controller) = try open(Data("old".utf8))
        try document.read(from: Data("new text".utf8), ofType: "public.plain-text")
        drainMainQueue()
        XCTAssertEqual(controller.textView.string, "new text")
        XCTAssertEqual(controller.rightStatus, "8 chars, 1 lines   UTF-8   LF")
    }

    func testHugeDocumentsSkipBackgroundLayout() throws {
        let (_, small) = try open(Data("small".utf8))
        XCTAssertTrue(small.textView.layoutManager!.backgroundLayoutEnabled)

        let big = Data(repeating: 0x61, count: EditorViewController.largeDocumentLimit + 1)
        let (_, large) = try open(big)
        XCTAssertFalse(large.textView.layoutManager!.backgroundLayoutEnabled)
        XCTAssertTrue(large.textView.layoutManager!.allowsNonContiguousLayout)
    }

    func testFilesOverThresholdOpenReadOnlyInViewer() throws {
        let saved = TextDocument.largeFileThreshold
        TextDocument.largeFileThreshold = 10
        defer { TextDocument.largeFileThreshold = saved }

        let document = TextDocument()
        try document.read(from: Data("line one\nline two\n".utf8), ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? LargeFileViewController)
        _ = controller.view
        XCTAssertEqual(controller.rightStatus, "18 chars, 3 lines   UTF-8   LF")
        XCTAssertEqual(controller.leftStatus.stringValue, "Ln 1, Col 1   Pos 0   Line 8 chars")

        controller.textView.moveDown(nil)
        drainMainQueue()
        XCTAssertEqual(controller.leftStatus.stringValue, "Ln 2, Col 1   Pos 9   Line 8 chars")
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(try document.data(ofType: "public.plain-text"), Data("line one\nline two\n".utf8))
    }

    func testViewerReloadKeepsScrollAndSelection() throws {
        let saved = TextDocument.largeFileThreshold
        TextDocument.largeFileThreshold = 10
        defer { TextDocument.largeFileThreshold = saved }

        let lines = (1...500).map { "line \($0)" }.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).log")
        try Data(lines.utf8).write(to: url)
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? LargeFileViewController)
        let window = try XCTUnwrap(controller.view.window)
        window.setContentSize(NSSize(width: 400, height: 300))
        window.layoutIfNeeded()

        controller.textView.setSelection(NSRange(location: 3, length: 0), scroll: false)
        let clip = try XCTUnwrap(controller.textView.enclosingScrollView?.contentView)
        clip.scroll(to: NSPoint(x: 0, y: 2000))
        let origin = clip.bounds.origin

        document.diskDidChange(Data((lines + "\nline 501").utf8))
        XCTAssertEqual(controller.model.lineIndex.lineCount, 501)
        XCTAssertEqual(controller.textView.selection, NSRange(location: 3, length: 0))
        XCTAssertEqual(clip.bounds.origin, origin)
        guard case .none = document.externalState else { return XCTFail("viewer never has pending changes") }
    }

    func testLargeFileLoadsQuicklyAndCaretMovesInstantly() throws {
        // ~200 MB of UTF-8 in release (`swift test -c release -Xswiftc -enable-testing`),
        // 20 MB in debug where unoptimized loops are ~40x slower.
        #if DEBUG
        let lines = 350_000
        #else
        let lines = 3_500_000
        #endif
        let line = Data("0123456789 lorem ipsum dolor sit amet, привіт світ 123456\n".utf8)
        var data = Data(capacity: line.count * lines)
        for _ in 0..<lines { data.append(line) }

        let start = Date()
        let prepared = try EditorModel.prepare(data: data)
        let loadTime = Date().timeIntervalSince(start)
        let model = EditorModel(prepared: prepared)
        XCTAssertEqual(model.lineIndex.lineCount, lines + 1)

        let caretStart = Date()
        for offset in stride(from: 0, to: model.storage.length, by: model.storage.length / 50) {
            _ = model.status(selectedRange: NSRange(location: offset, length: 0))
        }
        let caretTime = Date().timeIntervalSince(caretStart) / 50

        model.storage.replaceCharacters(in: NSRange(location: 1000, length: 0), with: "\n")
        XCTAssertEqual(model.lineIndex.lineCount, lines + 2)

        print("\(data.count / 1_000_000)MB load: \(String(format: "%.2f", loadTime))s, status per caret move: \(String(format: "%.2f", caretTime * 1000))ms")
        XCTAssertLessThan(caretTime, 0.02)
    }
}
