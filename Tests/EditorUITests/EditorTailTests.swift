import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// An editor tab with no unsaved changes follows a growing file like the
/// viewer does: new text is added in place, quickly, and followed at the bottom.
@MainActor
final class EditorTailTests: XCTestCase {
    private func makeLog(lines: Int, ending: String = "\n") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).log")
        try Data((1...lines).map { "line \($0)\(ending)" }.joined().utf8).write(to: url)
        return url
    }

    private func open(_ url: URL) throws -> (TextDocument, EditorViewController, NSClipView) {
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorViewController)
        let window = try XCTUnwrap(controller.view.window)
        window.setContentSize(NSSize(width: 400, height: 300))
        window.layoutIfNeeded()
        return (document, controller, controller.scrollView.contentView)
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    /// Waits for the tab's own watcher (no file presenter nudge).
    private func wait(_ seconds: TimeInterval = 3, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    private func lines(_ controller: EditorViewController) -> Int { controller.model.lineIndex.lineCount }

    private func isPending(_ document: TextDocument) -> Bool {
        if case .changed = document.externalState { return true }
        return false
    }

    func testAppendedLinesShowUpQuicklyAndTheTabStaysClean() throws {
        let url = try makeLog(lines: 100)
        let (document, controller, _) = try open(url)
        defer { document.close() }
        try append("line 101\nline 102\n", to: url)
        let start = Date()
        wait { lines(controller) == 103 }

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.6)
        XCTAssertTrue(controller.textView.string.hasSuffix("line 100\nline 101\nline 102\n"))
        drainMainQueue()
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertFalse(document.undoManager?.canUndo ?? true, "following the file is not an edit to undo")
        XCTAssertEqual(document.baseText, controller.textView.string)
        XCTAssertTrue(controller.rightStatus.contains("103 lines"), controller.rightStatus)
    }

    func testAtTheBottomTheViewFollows() throws {
        let url = try makeLog(lines: 500)
        let (document, controller, clip) = try open(url)
        defer { document.close() }
        controller.textView.scrollToEndOfDocument(nil)
        try append((501...600).map { "line \($0)\n" }.joined(), to: url)
        wait { lines(controller) == 601 }
        controller.view.window?.layoutIfNeeded()

        XCTAssertEqual(clip.bounds.maxY, controller.textView.bounds.height, accuracy: 1)
    }

    func testScrolledUpTheViewAndCaretStayPut() throws {
        let url = try makeLog(lines: 500)
        let (document, controller, clip) = try open(url)
        defer { document.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))  // let the new window settle
        controller.textView.setSelectedRange(NSRange(location: 3, length: 2))
        clip.scroll(to: NSPoint(x: 0, y: 1000))
        let origin = clip.bounds.origin
        try append("line 501\n", to: url)
        wait { lines(controller) == 502 }

        XCTAssertEqual(clip.bounds.origin, origin)
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 3, length: 2))
    }

    func testAConstantWriterDoesNotStarveUpdates() throws {
        let url = try makeLog(lines: 100)
        let (document, controller, _) = try open(url)
        defer { document.close() }
        let start = Date()
        var written = 100
        var seenWhileWriting = 0
        while Date().timeIntervalSince(start) < 1 {
            written += 1
            try append("line \(written)\n", to: url)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            seenWhileWriting = lines(controller) - 1
        }
        XCTAssertGreaterThan(seenWhileWriting, 100)
    }

    func testTypingAfterAnAppendSavesWithoutAConflict() throws {
        let url = try makeLog(lines: 3)
        let (document, controller, _) = try open(url)
        defer { document.close() }
        try append("line 4\n", to: url)
        wait { lines(controller) == 5 }
        controller.textView.insertText("!", replacementRange: NSRange(location: 0, length: 0))
        drainMainQueue()

        let saved = expectation(description: "save")
        var saveError: Error?
        document.save(to: url, ofType: "public.plain-text", for: .saveOperation) { saveError = $0; saved.fulfill() }
        wait(for: [saved], timeout: 5)
        XCTAssertNil(saveError)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "!line 1\nline 2\nline 3\nline 4\n")
    }

    func testAnEditedTabIsNotAppendedTo() throws {
        let url = try makeLog(lines: 3)
        let (document, controller, _) = try open(url)
        defer { document.close() }
        controller.textView.insertText("!", replacementRange: NSRange(location: 0, length: 0))
        drainMainQueue()
        try append("line 4\n", to: url)
        wait(2) { isPending(document) }

        XCTAssertEqual(controller.textView.string, "!line 1\nline 2\nline 3\n")
        XCTAssertTrue(isPending(document), "the edited tab gets the usual review instead")
    }

    func testCRLFAppendsKeepWholeLineBreaks() throws {
        let url = try makeLog(lines: 3, ending: "\r\n")
        let (document, controller, _) = try open(url)
        defer { document.close() }
        // A line break split across two writes.
        try append("line 4\r", to: url)
        wait { controller.textView.string.hasSuffix("line 4\r") }
        try append("\nline 5\r\n", to: url)
        wait { controller.textView.string.hasSuffix("line 5\r\n") }

        XCTAssertEqual(controller.textView.string, "line 1\r\nline 2\r\nline 3\r\nline 4\r\nline 5\r\n")
        XCTAssertEqual(document.baseText, "line 1\nline 2\nline 3\nline 4\nline 5\n")
        XCTAssertFalse(document.isDocumentEdited)
    }

    func testATruncatedFileIsReloadedAndFollowedAgain() throws {
        let url = try makeLog(lines: 100)
        let (document, controller, _) = try open(url)
        defer { document.close() }
        try Data("rotated\n".utf8).write(to: url)
        wait { controller.textView.string == "rotated\n" }
        XCTAssertEqual(controller.textView.string, "rotated\n")

        try append("next\n", to: url)
        wait { controller.textView.string == "rotated\nnext\n" }
        XCTAssertEqual(controller.textView.string, "rotated\nnext\n")
        XCTAssertFalse(document.isDocumentEdited)
    }
}
