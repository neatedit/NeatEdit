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

    func testOpensFileAndShowsStatus() throws {
        let (_, controller) = try open(Data("hello\nсвіт\n".utf8))
        XCTAssertEqual(controller.textView.string, "hello\nсвіт\n")
        XCTAssertEqual(controller.leftStatus.stringValue, "Ln 1, Col 1   Pos 0   Line 5 chars")
        XCTAssertEqual(controller.rightStatus.stringValue, "11 chars, 3 lines   UTF-8   LF")
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
        XCTAssertEqual(controller.rightStatus.stringValue, "8 chars, 1 lines   UTF-8   LF")
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
        XCTAssertEqual(controller.rightStatus.stringValue, "18 chars, 3 lines   UTF-8   LF")
        XCTAssertEqual(controller.leftStatus.stringValue, "Ln 1, Col 1   Pos 0   Line 8 chars")

        controller.textView.moveDown(nil)
        drainMainQueue()
        XCTAssertEqual(controller.leftStatus.stringValue, "Ln 2, Col 1   Pos 9   Line 8 chars")
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(try document.data(ofType: "public.plain-text"), Data("line one\nline two\n".utf8))
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
