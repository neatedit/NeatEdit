import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// The viewer follows a growing file like `tail -f`.
@MainActor
final class ViewerTailTests: XCTestCase {
    private var savedThreshold = 0

    override func setUp() {
        savedThreshold = TextDocument.largeFileThreshold
        TextDocument.largeFileThreshold = 10
    }

    override func tearDown() {
        TextDocument.largeFileThreshold = savedThreshold
    }

    private func makeLog(lines: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).log")
        try Data((1...lines).map { "line \($0)\n" }.joined().utf8).write(to: url)
        return url
    }

    private func open(_ url: URL) throws -> (TextDocument, LargeFileViewController, NSClipView) {
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? LargeFileViewController)
        let window = try XCTUnwrap(controller.view.window)
        window.setContentSize(NSSize(width: 400, height: 300))
        window.layoutIfNeeded()
        return (document, controller, try XCTUnwrap(controller.textView.enclosingScrollView?.contentView))
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    /// Tells the document the file changed and waits for it to catch up.
    private func waitForDisk(_ document: TextDocument, until done: () -> Bool) {
        document.presentedItemDidChange()
        let deadline = Date().addingTimeInterval(5)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    func testAppendedLinesAreAddedInPlace() throws {
        let url = try makeLog(lines: 100)
        let (document, controller, _) = try open(url)
        let model = controller.model
        try append("line 101\nline 102\n", to: url)
        waitForDisk(document) { controller.model.lineIndex.lineCount == 103 }

        XCTAssertTrue(controller.model === model, "appends must not rebuild the whole model")
        XCTAssertTrue(controller.model.storage.string.hasSuffix("line 100\nline 101\nline 102\n"))
        drainMainQueue()
        XCTAssertTrue(controller.rightStatus.hasPrefix("\(controller.model.storage.length) chars, 103 lines"), controller.rightStatus)
        XCTAssertFalse(document.isDocumentEdited)
    }

    func testAtTheBottomTheViewFollowsNewLines() throws {
        let url = try makeLog(lines: 500)
        let (document, controller, clip) = try open(url)
        controller.textView.scrollToEndOfDocument(nil)
        try append((501...600).map { "line \($0)\n" }.joined(), to: url)
        waitForDisk(document) { controller.model.lineIndex.lineCount == 601 }

        XCTAssertEqual(clip.bounds.maxY, controller.textView.bounds.height, accuracy: 1)
    }

    func testScrolledUpTheViewStaysPut() throws {
        let url = try makeLog(lines: 500)
        let (document, controller, clip) = try open(url)
        controller.textView.setSelection(NSRange(location: 3, length: 0), scroll: false)
        clip.scroll(to: NSPoint(x: 0, y: 2000))
        let origin = clip.bounds.origin
        try append("line 501\n", to: url)
        waitForDisk(document) { controller.model.lineIndex.lineCount == 502 }

        XCTAssertEqual(clip.bounds.origin, origin)
        XCTAssertEqual(controller.textView.selection, NSRange(location: 3, length: 0))
    }

    func testNoticesAppendsQuicklyOnItsOwn() throws {
        let url = try makeLog(lines: 100)
        let (document, controller, _) = try open(url)
        try append("line 101\n", to: url)
        let start = Date()
        while controller.model.lineIndex.lineCount < 102, Date().timeIntervalSince(start) < 3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(controller.model.lineIndex.lineCount, 102)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.6)
        document.close()
    }

    func testAConstantWriterDoesNotStarveUpdates() throws {
        let url = try makeLog(lines: 100)
        let (document, controller, _) = try open(url)
        let start = Date()
        var written = 100
        // A write every 20 ms for a second: lines must show up along the way.
        var seenWhileWriting = 0
        while Date().timeIntervalSince(start) < 1 {
            written += 1
            try append("line \(written)\n", to: url)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            seenWhileWriting = controller.model.lineIndex.lineCount - 1
        }
        XCTAssertGreaterThan(seenWhileWriting, 100)
        document.close()
    }

    func testFollowsAFileRecreatedLater() throws {
        let url = try makeLog(lines: 100)
        let (document, controller, _) = try open(url)
        try FileManager.default.removeItem(at: url)
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        try Data("fresh\n".utf8).write(to: url)
        let deadline = Date().addingTimeInterval(4)
        while controller.model.storage.string != "fresh\n", Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(controller.model.storage.string, "fresh\n")
        try append("more\n", to: url)
        let next = Date().addingTimeInterval(2)
        while controller.model.lineIndex.lineCount < 3, Date() < next { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(controller.model.storage.string, "fresh\nmore\n")
        document.close()
    }

    func testTruncatedFileIsReloadedWhole() throws {
        let url = try makeLog(lines: 100)
        let (document, controller, _) = try open(url)
        try Data("rotated\n".utf8).write(to: url)
        waitForDisk(document) { controller.model.lineIndex.lineCount == 2 }

        XCTAssertEqual(controller.model.storage.string, "rotated\n")
        // And it keeps following the new file.
        try append("next\n", to: url)
        waitForDisk(document) { controller.model.lineIndex.lineCount == 3 }
        XCTAssertEqual(controller.model.storage.string, "rotated\nnext\n")
    }
}
