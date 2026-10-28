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

    // MARK: Review, dismiss, big diff

    /// Writes new contents to the file (with a fresh date) and reports it.
    private func changeOnDisk(_ text: String, at url: URL, document: TextDocument) throws {
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        document.diskDidChange(try Data(contentsOf: url))
    }

    private func diskDate(_ url: URL) throws -> Date? {
        try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func testBannerShowsForEditedTab() throws {
        let (document, controller, url) = try open("a\nb\nc\nd")
        XCTAssertTrue(controller.banner.isHidden)
        type("!", at: 0, in: controller)
        try changeOnDisk("a\nb\nc\nD", at: url, document: document)
        XCTAssertFalse(controller.banner.isHidden)
        XCTAssertEqual(controller.banner.message.stringValue, "File changed on disk")
        XCTAssertEqual(controller.banner.primaryButton.title, "Review Changes")
    }

    func testApplyAcceptsChosenHunksAsOneUndoStep() throws {
        let (document, controller, url) = try open("1\n2\n3\n4\n5")
        type("!", at: 4, in: controller)  // "1\n2\n!3\n4\n5"
        try changeOnDisk("X\n2\n3\n4\nY", at: url, document: document)
        let merge = try XCTUnwrap(self.merge(document))
        document.applyReview([merge.hunks[1].id: .accept])
        XCTAssertEqual(controller.textView.string, "1\n2\n!3\n4\nY")
        XCTAssertTrue(document.isDocumentEdited)
        XCTAssertTrue(controller.banner.isHidden)
        XCTAssertEqual(document.baseText, "X\n2\n3\n4\nY")
        XCTAssertEqual(document.fileModificationDate, try diskDate(url))

        document.undoManager?.undo()
        XCTAssertEqual(controller.textView.string, "1\n2\n!3\n4\n5")
    }

    func testApplyKeepsTabLineEndings() throws {
        let (document, controller, url) = try open("a\r\nb\r\nc")
        type("!", at: 0, in: controller)
        try changeOnDisk("a\r\nb\r\nC", at: url, document: document)
        let merge = try XCTUnwrap(self.merge(document))
        document.applyReview([merge.hunks[0].id: .accept])
        XCTAssertEqual(controller.textView.string, "!a\r\nb\r\nC")
    }

    func testUndecidedHunksAreSkipped() throws {
        let (document, controller, url) = try open("a\nb")
        type("!", at: 0, in: controller)
        try changeOnDisk("a\nB", at: url, document: document)
        document.applyReview([:])
        XCTAssertEqual(controller.textView.string, "!a\nb")
        guard case .none = document.externalState else { return XCTFail("applied review clears the change") }
    }

    func testDismissKeepsMineAndAdoptsDiskAsBase() throws {
        let (document, controller, url) = try open("a\nb")
        type("!", at: 0, in: controller)
        try changeOnDisk("a\nB", at: url, document: document)
        document.dismissExternalChange()
        XCTAssertEqual(controller.textView.string, "!a\nb")
        XCTAssertTrue(controller.banner.isHidden)
        XCTAssertEqual(document.baseText, "a\nB")
        XCTAssertEqual(document.fileModificationDate, try diskDate(url))

        // The same disk contents don't bring the banner back.
        document.diskDidChange(try Data(contentsOf: url))
        XCTAssertTrue(controller.banner.isHidden)
    }

    func testBigDiffOffersSaveMyVersionAs() throws {
        let (document, controller, url) = try open("1\n2\n3\n4")
        type("!", at: 0, in: controller)
        try changeOnDisk("a\nb\nc\n4", at: url, document: document)
        XCTAssertEqual(controller.banner.primaryButton.title, "Save My Version As…")
    }

    func testSaveMyVersionAsWritesCopyAndLoadsDisk() throws {
        let (document, controller, url) = try open("1\n2\n3\n4")
        type("!", at: 0, in: controller)
        try changeOnDisk("a\nb\nc\n4", at: url, document: document)
        let copy = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString) (my version).txt")
        try document.saveMyVersionAs(url: copy)
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "!1\n2\n3\n4")
        XCTAssertEqual(controller.textView.string, "a\nb\nc\n4")
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertTrue(controller.banner.isHidden)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a\nb\nc\n4")
    }

    func testSuggestedNameForMyVersion() {
        XCTAssertEqual(TextDocument.myVersionName(for: URL(fileURLWithPath: "/x/notes.txt")), "notes (my version).txt")
        XCTAssertEqual(TextDocument.myVersionName(for: URL(fileURLWithPath: "/x/Makefile")), "Makefile (my version)")
    }

    func testRediffKeepsDecisionsForUnchangedHunks() throws {
        let first = ExternalMerge(base: "1\n2\n3\n4\n5", mine: "1\n2\n3\n4\n5", disk: "X\n2\n3\n4\n5")
        let review = ChangeReviewController(merge: first)
        _ = review.view
        review.decide(first.hunks[0].id, .accept)
        let second = ExternalMerge(base: "1\n2\n3\n4\n5", mine: "1\n2\n3\n4\n5", disk: "X\n2\n3\n4\nY")
        review.update(merge: second)
        XCTAssertEqual(review.decisions, [first.hunks[0].id: .accept])
        XCTAssertEqual(review.rowCount, 2)
    }

    func testConflictRowsOfferTakeDiskOrKeepMine() throws {
        let merge = ExternalMerge(base: "a\nb", mine: "a\nX", disk: "a\nY")
        let review = ChangeReviewController(merge: merge)
        _ = review.view
        XCTAssertEqual(review.choiceLabels(for: merge.hunks[0].id), ["Take Disk", "Keep Mine"])
    }

    func testRepeatedChangesKeepOneBannerWithLatestDiff() throws {
        let (document, controller, url) = try open("log")
        type("!", at: 0, in: controller)
        var text = "log"
        for i in 1...10 {
            text += "\nline \(i)"
            try changeOnDisk(text, at: url, document: document)
        }
        XCTAssertFalse(controller.banner.isHidden)
        XCTAssertEqual(merge(document)?.hunks.first?.base.newLines.count, 11)
    }

    // MARK: Saving while a change is pending, deleted files

    private func save(_ document: TextDocument, to url: URL, _ operation: NSDocument.SaveOperationType) -> Error? {
        let done = expectation(description: "save")
        var result: Error?
        document.save(to: url, ofType: "public.plain-text", for: operation) { error in
            result = error
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    func testSaveWhileChangedDoesNotWrite() throws {
        let (document, controller, url) = try open("a\nb")
        type("!", at: 0, in: controller)
        try changeOnDisk("a\nB", at: url, document: document)
        let error = save(document, to: url, .saveOperation)
        XCTAssertEqual((error as? CocoaError)?.code, .userCancelled)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a\nB")
        XCTAssertTrue(document.isDocumentEdited)
    }

    func testAutosaveWhileChangedDoesNotWrite() throws {
        let (document, controller, url) = try open("a\nb")
        type("!", at: 0, in: controller)
        try changeOnDisk("a\nB", at: url, document: document)

        let periodic = expectation(description: "periodic autosave")
        document.autosave(withImplicitCancellability: true) { _ in periodic.fulfill() }
        wait(for: [periodic], timeout: 5)
        XCTAssertNotNil(save(document, to: url, .autosaveInPlaceOperation))

        let closing = expectation(description: "autosave before close")
        var closingError: Error?
        document.autosave(withImplicitCancellability: false) { error in
            closingError = error
            closing.fulfill()
        }
        wait(for: [closing], timeout: 5)
        XCTAssertNotNil(closingError, "closing must not silently drop either version")

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a\nB")
        XCTAssertTrue(document.isDocumentEdited)
        XCTAssertEqual(controller.textView.string, "!a\nb")
    }

    func testSaveAsWhileChangedIsAllowedAndClearsTheChange() throws {
        let (document, controller, url) = try open("a\nb")
        type("!", at: 0, in: controller)
        try changeOnDisk("a\nB", at: url, document: document)
        let other = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).txt")
        XCTAssertNil(save(document, to: other, .saveAsOperation))
        XCTAssertEqual(try String(contentsOf: other, encoding: .utf8), "!a\nb")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a\nB")
        guard case .none = document.externalState else { return XCTFail("a different file has no pending change") }
    }

    func testDeletedFileShowsBannerAndSaveRecreates() throws {
        let (document, controller, url) = try open("a")
        try FileManager.default.removeItem(at: url)
        document.diskDidChange(nil)
        XCTAssertFalse(controller.banner.isHidden)
        XCTAssertEqual(controller.banner.message.stringValue, "Deleted from disk")
        XCTAssertTrue(controller.banner.primaryButton.isHidden)
        XCTAssertEqual(controller.textView.string, "a")

        type("b", at: 1, in: controller)
        XCTAssertNil(save(document, to: url, .saveOperation))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "ab")
        XCTAssertTrue(controller.banner.isHidden)
    }

    func testDismissHidesDeletedBanner() throws {
        let (document, controller, url) = try open("a")
        try FileManager.default.removeItem(at: url)
        document.diskDidChange(nil)
        document.dismissExternalChange()
        XCTAssertTrue(controller.banner.isHidden)
    }

    func testReappearingFileIsOrdinaryChange() throws {
        let (document, controller, url) = try open("a")
        try FileManager.default.removeItem(at: url)
        document.diskDidChange(nil)
        try changeOnDisk("a", at: url, document: document)
        XCTAssertTrue(controller.banner.isHidden)

        try FileManager.default.removeItem(at: url)
        document.diskDidChange(nil)
        try changeOnDisk("new", at: url, document: document)
        XCTAssertTrue(controller.banner.isHidden)
        XCTAssertEqual(controller.textView.string, "new")
    }
}
