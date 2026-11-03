import AppKit
import XCTest
@testable import EditorUI

/// Asking "save this?" only makes sense when there is something to lose.
@MainActor
final class ClosingEmptyDocumentTests: XCTestCase {
    private final class CloseAnswer: NSObject {
        var shouldClose: Bool?

        @objc func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
            self.shouldClose = shouldClose
        }
    }

    private func untitled(typing text: String) throws -> (TextDocument, EditorViewController) {
        let document = try TextDocument(type: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorViewController)
        _ = controller.view
        controller.textView.insertText(text, replacementRange: NSRange(location: 0, length: 0))
        drainMainQueue()
        XCTAssertTrue(document.isDocumentEdited)
        return (document, controller)
    }

    private func askToClose(_ document: TextDocument) -> CloseAnswer {
        let answer = CloseAnswer()
        document.canClose(
            withDelegate: answer,
            shouldClose: #selector(CloseAnswer.document(_:shouldClose:contextInfo:)),
            contextInfo: nil)
        drainMainQueue()
        return answer
    }

    func testUntitledDocumentEmptiedByTheUserClosesWithoutAsking() throws {
        let (document, controller) = try untitled(typing: "draft")
        controller.textView.selectAll(nil)
        controller.textView.insertText("", replacementRange: controller.textView.selectedRange())
        drainMainQueue()
        XCTAssertEqual(controller.textView.string, "")

        let answer = askToClose(document)

        XCTAssertNil(controller.view.window?.attachedSheet)
        XCTAssertEqual(answer.shouldClose, true)
    }

    /// The deleted draft must not stay behind in Autosave Information.
    func testClosingAnEmptiedUntitledDocumentLeavesNoAutosavedCopy() throws {
        let (document, controller) = try untitled(typing: "draft")
        let saved = expectation(description: "autosaved")
        document.autosave(withImplicitCancellability: false) { error in
            XCTAssertNil(error)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 5)
        let copy = try XCTUnwrap(document.autosavedContentsFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))

        controller.textView.selectAll(nil)
        controller.textView.insertText("", replacementRange: controller.textView.selectedRange())
        drainMainQueue()
        XCTAssertEqual(askToClose(document).shouldClose, true)
        document.close()
        drainMainQueue()

        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }

    /// A saved file is autosaved in place, so it never asked: emptying it is
    /// an edit like any other and reaches the disk.
    func testEmptiedSavedFileClosesWithoutAskingAndIsWritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("text".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorViewController)
        _ = controller.view
        controller.textView.selectAll(nil)
        controller.textView.insertText("", replacementRange: controller.textView.selectedRange())
        drainMainQueue()
        XCTAssertTrue(document.isDocumentEdited)

        let answer = askToClose(document)
        let deadline = Date().addingTimeInterval(5)
        while answer.shouldClose == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertNil(controller.view.window?.attachedSheet)
        XCTAssertEqual(answer.shouldClose, true)
        XCTAssertEqual(try Data(contentsOf: url), Data())
    }

    func testUntitledDocumentWithTextStillAsks() throws {
        let (document, controller) = try untitled(typing: "draft")
        let window = try XCTUnwrap(controller.view.window)
        defer { window.attachedSheet.map { window.endSheet($0) } }

        let answer = askToClose(document)

        XCTAssertNotNil(window.attachedSheet)
        XCTAssertNil(answer.shouldClose)
    }
}
