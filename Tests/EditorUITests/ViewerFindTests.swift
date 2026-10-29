import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// The viewer uses the same find bar as the editor, without replacing.
@MainActor
final class ViewerFindTests: XCTestCase {
    private var savedThreshold = 0
    private var savedLargeLimit = 0
    private var document: TextDocument!

    /// Small files take the paths real viewer files (20 MB and up) take.
    override func setUp() {
        savedThreshold = TextDocument.largeFileThreshold
        savedLargeLimit = EditorViewController.largeDocumentLimit
        TextDocument.largeFileThreshold = 10
        EditorViewController.largeDocumentLimit = 10
    }

    override func tearDown() {
        TextDocument.largeFileThreshold = savedThreshold
        EditorViewController.largeDocumentLimit = savedLargeLimit
    }

    private func open(_ text: String) throws -> LargeFileViewController {
        document = TextDocument()
        try document.read(from: Data(text.utf8), ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? LargeFileViewController)
        _ = controller.view
        return controller
    }

    private func menuItem(_ action: NSTextFinder.Action) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "")
        item.tag = action.rawValue
        return item
    }

    func testFindMenuShowsOurBarWithoutReplace() throws {
        let controller = try open("alpha beta gamma beta")
        let find = controller.findController
        XCTAssertFalse(find.isVisible)
        XCTAssertTrue(controller.textView.validateMenuItem(menuItem(.showFindInterface)))
        controller.textView.performFindPanelAction(menuItem(.showFindInterface))
        XCTAssertTrue(find.isVisible)
        XCTAssertFalse(find.bar.isShowingReplace)
        XCTAssertNil(find.bar.findField.nextKeyView, "Tab must be able to leave the find field")
        XCTAssertFalse(controller.textView.validateMenuItem(menuItem(.replaceAll)))

        find.bar.findField.cancelOperation(nil)
        XCTAssertFalse(find.isVisible)
        XCTAssertTrue(controller.view.window?.firstResponder === controller.textView)
    }

    func testPlaceholderFindSelectsMatchesAndWraps() throws {
        let controller = try open("id=17 name=x\nid=204 name=y\n")
        let find = controller.findController
        find.perform(.showFindInterface)
        find.bar.findField.tokens = [.text("id="), .placeholder(1), .text(" name")]
        find.perform(.nextMatch)
        XCTAssertEqual(controller.textView.selection, NSRange(location: 0, length: 10))
        find.perform(.nextMatch)
        XCTAssertEqual(controller.textView.selection, NSRange(location: 13, length: 11))
        find.perform(.nextMatch)
        XCTAssertEqual(controller.textView.selection, NSRange(location: 0, length: 10))
        find.perform(.previousMatch)
        XCTAssertEqual(controller.textView.selection, NSRange(location: 13, length: 11))
    }

    func testReplaceDoesNothingInTheViewer() throws {
        let controller = try open("cat dog cat")
        let find = controller.findController
        find.perform(.showFindInterface)
        find.bar.findField.tokens = [.text("cat")]
        find.bar.replaceField.tokens = [.text("cow")]
        find.perform(.replaceAll)
        find.perform(.replace)
        XCTAssertEqual(controller.model.storage.string, "cat dog cat")
        XCTAssertFalse(document.isDocumentEdited)
    }

    func testUseSelectionForFind() throws {
        let controller = try open("one two one")
        controller.textView.setSelection(NSRange(location: 0, length: 3))
        let find = controller.findController
        find.perform(.setSearchString)
        find.perform(.showFindInterface)
        find.perform(.nextMatch)
        XCTAssertEqual(controller.textView.selection, NSRange(location: 8, length: 3))
    }

    func testTypingSaysToPressReturn() throws {
        let controller = try open("alpha beta gamma")
        let find = controller.findController
        find.perform(.showFindInterface)
        find.bar.findField.insertText("beta", replacementRange: find.bar.findField.selectedRange())
        drainMainQueue()
        XCTAssertEqual(find.bar.statusLabel.stringValue, "Return to find")
        XCTAssertEqual(controller.textView.selection, NSRange(location: 0, length: 0))
        find.perform(.nextMatch)
        XCTAssertEqual(controller.textView.selection, NSRange(location: 6, length: 4))
        XCTAssertEqual(find.bar.statusLabel.stringValue, "Found")
    }

    func testReloadDropsTheOldInSelectionScope() throws {
        let controller = try open("cat cat cat cat cat\n")
        let find = controller.findController
        controller.textView.setSelection(NSRange(location: 12, length: 7))
        find.perform(.showFindInterface)
        find.inSelection = true
        find.bar.findField.tokens = [.text("dog")]
        document.diskDidChange(Data("dog\n".utf8))
        find.perform(.nextMatch)
        XCTAssertEqual(controller.textView.selection, NSRange(location: 0, length: 3))
    }
}
