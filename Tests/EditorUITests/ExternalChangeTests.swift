import AppKit
import XCTest
import EditorCore
@testable import EditorUI

@MainActor
final class ExternalChangeTests: XCTestCase {
    private func open(_ text: String, name: String = "file.txt") throws -> (TextDocument, EditorViewController, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data(text.utf8).write(to: url)
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorViewController)
        _ = controller.view
        return (document, controller, url)
    }

    private func type(_ text: String, at location: Int, in controller: EditorViewController) {
        controller.textView.insertText(text, replacementRange: NSRange(location: location, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func merge(_ document: TextDocument) -> ExternalMerge? {
        if case .changed(let merge, _) = document.externalState { return merge }
        return nil
    }

    func testCleanTabReloadsSilently() throws {
        let (document, controller, _) = try open("a\nb")
        controller.textView.setSelectedRange(NSRange(location: 2, length: 0))
        document.diskDidChange(Data("a\nc".utf8))
        XCTAssertEqual(controller.textView.string, "a\nc")
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 2, length: 0))
        guard case .none = document.externalState else { return XCTFail("expected no pending change") }

        document.undoManager?.undo()
        XCTAssertEqual(controller.textView.string, "a\nb")
    }

    func testSilentReloadFollowsDiskEncodingAndLineEndings() throws {
        let (document, controller, _) = try open("a\nb")
        document.diskDidChange("a\r\nб".data(using: .windowsCP1251)!)
        XCTAssertEqual(controller.textView.string, "a\r\nб")
        XCTAssertEqual(controller.statusBar.encodingButton.title, "Windows-1251")
        XCTAssertEqual(controller.statusBar.lineEndingButton.title, "CRLF")
        XCTAssertFalse(document.isDocumentEdited)
    }

    func testLineIndexMatchesAfterUndoOfReload() throws {
        let (document, controller, _) = try open("a\nb\nc\nd")
        document.diskDidChange(Data("x".utf8))
        document.undoManager?.undo()
        let model = controller.model
        XCTAssertEqual(model.lineIndex.starts, LineIndex(model.storage.string as NSString).starts)
        XCTAssertEqual(model.lineIndex.lineCount, 4)
    }

    func testOwnSaveEchoIsIgnored() throws {
        let (document, controller, url) = try open("a")
        type("b", at: 1, in: controller)
        let saved = expectation(description: "saved")
        document.save(to: url, ofType: "public.plain-text", for: .saveOperation) { error in
            XCTAssertNil(error)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 5)
        document.diskDidChange(try Data(contentsOf: url))
        guard case .none = document.externalState else { return XCTFail("own save must not look external") }
        XCTAssertEqual(controller.textView.string, "ab")
        XCTAssertFalse(document.isDocumentEdited)
    }

    func testEditedTabIsNotReloaded() throws {
        let (document, controller, _) = try open("a\nb")
        type("!", at: 0, in: controller)
        document.diskDidChange(Data("a\nB".utf8))
        XCTAssertEqual(controller.textView.string, "!a\nb")
        XCTAssertTrue(document.isDocumentEdited)
        XCTAssertEqual(merge(document)?.hunks.count, 1)
    }

    func testCrlfFileWithOneExternalChangeIsOneHunk() throws {
        let (document, controller, _) = try open("a\r\nb\r\nc")
        type("!", at: 0, in: controller)
        document.diskDidChange(Data("a\r\nB\r\nc".utf8))
        XCTAssertEqual(merge(document)?.hunks.count, 1)
        XCTAssertEqual(merge(document)?.hunks.first?.isConflict, false)
    }

    func testLineEndingOnlyChangeOnEditedTabIsIgnored() throws {
        let (document, controller, _) = try open("a\nb")
        type("!", at: 0, in: controller)
        document.diskDidChange(Data("a\r\nb".utf8))
        guard case .none = document.externalState else { return XCTFail("line endings alone are not a change") }
    }
}
