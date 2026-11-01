import AppKit
import XCTest
import EditorCore
@testable import EditorUI

@MainActor
final class FindBarTests: XCTestCase {
    private var document: TextDocument!

    private func open(_ text: String) throws -> EditorViewController {
        document = TextDocument()
        try document.read(from: Data(text.utf8), ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController as? EditorViewController)
        _ = controller.view
        return controller
    }

    private func menuItem(_ action: NSTextFinder.Action) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "")
        item.tag = action.rawValue
        return item
    }

    func testFindMenuShowsBarAndEscapeHidesIt() throws {
        let controller = try open("abc")
        let find = controller.findController
        XCTAssertFalse(find.isVisible)

        controller.textView.performFindPanelAction(menuItem(.showFindInterface))
        XCTAssertTrue(find.isVisible)
        XCTAssertTrue(find.bar.findField.window?.firstResponder === find.bar.findField)

        find.bar.findField.cancelOperation(nil)
        XCTAssertFalse(find.isVisible)
        XCTAssertTrue(controller.view.window?.firstResponder === controller.textView)
    }

    func testFieldTokensRoundTripThroughPlaceholderChips() throws {
        let field = PlaceholderField.make()
        field.tokens = [.text("a=\""), .placeholder(1), .text("\" "), .placeholder(2)]
        XCTAssertEqual(field.tokens, [.text("a=\""), .placeholder(1), .text("\" "), .placeholder(2)])

        field.tokens = [.text("x")]
        field.setSelectedRange(NSRange(location: 1, length: 0))
        field.insertPlaceholder(1)
        field.insertText("y", replacementRange: field.selectedRange())
        XCTAssertEqual(field.tokens, [.text("x"), .placeholder(1), .text("y")])
    }

    func testStarInsertsNextUnusedNumberAndReplaceOffersFindNumbers() throws {
        let controller = try open("")
        let bar = controller.findController.bar
        bar.insertFindPlaceholder(nil)
        bar.findField.insertText("-", replacementRange: bar.findField.selectedRange())
        bar.insertFindPlaceholder(nil)
        XCTAssertEqual(bar.findField.tokens, [.placeholder(1), .text("-"), .placeholder(2)])
        XCTAssertEqual(bar.replacePlaceholderMenu().items.map(\.title), ["1", "2"])
    }

    func testFindNextSelectsMatchesAndReportsPosition() throws {
        let controller = try open("one two one two")
        let find = controller.findController
        find.perform(.showFindInterface)
        find.bar.findField.tokens = [.text("two")]

        find.perform(.nextMatch)
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 4, length: 3))
        XCTAssertEqual(find.bar.statusLabel.stringValue, "1 of 2")

        find.perform(.nextMatch)
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 12, length: 3))
        XCTAssertEqual(find.bar.statusLabel.stringValue, "2 of 2")

        find.perform(.previousMatch)
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 4, length: 3))
    }

    func testTypingInFindJumpsToFirstMatchAfterCaret() throws {
        let controller = try open("cat dog cat")
        controller.textView.setSelectedRange(NSRange(location: 2, length: 0))
        let find = controller.findController
        find.perform(.showFindInterface)
        find.bar.findField.insertText("cat", replacementRange: find.bar.findField.selectedRange())
        drainMainQueue()
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 8, length: 3))
        XCTAssertEqual(find.bar.statusLabel.stringValue, "2 of 2")
        XCTAssertTrue(find.bar.findField.window?.firstResponder === find.bar.findField)
    }

    func testReplaceAllSwapsPlaceholdersAndUndoesInOneStep() throws {
        let original = "<img width=\"10\" height=\"20\">\n<img width=\"3\" height=\"4\">"
        let controller = try open(original)
        let find = controller.findController
        find.perform(.showReplaceInterface)
        find.bar.findField.tokens = [.text("width=\""), .placeholder(1), .text("\" height=\""), .placeholder(2), .text("\"")]
        find.bar.replaceField.tokens = [.text("width=\""), .placeholder(2), .text("\" height=\""), .placeholder(1), .text("\"")]

        find.perform(.replaceAll)
        XCTAssertEqual(controller.textView.string, "<img width=\"20\" height=\"10\">\n<img width=\"4\" height=\"3\">")
        XCTAssertEqual(find.bar.statusLabel.stringValue, "Replaced 2")
        drainMainQueue()
        XCTAssertTrue(document.isDocumentEdited)

        controller.textView.undoManager?.undo()
        XCTAssertEqual(controller.textView.string, original)
    }

    func testReplaceReplacesCurrentMatchThenSelectsNext() throws {
        let controller = try open("a1 a2 a3")
        let find = controller.findController
        find.perform(.showReplaceInterface)
        find.bar.findField.tokens = [.text("a"), .placeholder(1), .text(" ")]
        find.bar.replaceField.tokens = [.text("<"), .placeholder(1), .text("> ")]

        // Nothing selected yet: Replace just finds the first match.
        find.perform(.replace)
        XCTAssertEqual(controller.textView.string, "a1 a2 a3")
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 0, length: 3))

        find.perform(.replace)
        XCTAssertEqual(controller.textView.string, "<1> a2 a3")
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 4, length: 3))
    }

    func testReplaceAllInSelectionOnly() throws {
        let controller = try open("x x x x")
        let find = controller.findController
        controller.textView.setSelectedRange(NSRange(location: 2, length: 3))
        find.perform(.showReplaceInterface)
        find.inSelection = true
        find.bar.findField.tokens = [.text("x")]
        find.bar.replaceField.tokens = [.text("y")]

        find.perform(.replaceAll)
        XCTAssertEqual(controller.textView.string, "x y y x")
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 2, length: 3))
    }

    /// Search `selection` of a new tab, with find and replace fields set.
    private func openWithScope(_ text: String, _ selection: NSRange, find: String, replace: String = "") throws -> EditorViewController {
        let controller = try open(text)
        controller.textView.setSelectedRange(selection)
        controller.findController.perform(.showReplaceInterface)
        controller.findController.inSelection = true
        controller.findController.bar.findField.tokens = [.text(find)]
        controller.findController.bar.replaceField.tokens = [.text(replace)]
        return controller
    }

    private func edit(_ controller: EditorViewController, _ range: NSRange, _ text: String) {
        _ = controller.textView.replaceFound(range, with: text, actionName: "Edit")
    }

    func testTheScopeMovesWithTextAddedBeforeIt() throws {
        let controller = try openWithScope("cat cat", NSRange(location: 4, length: 3), find: "cat")
        edit(controller, NSRange(location: 0, length: 0), "xxxx")
        controller.textView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.findController.perform(.nextMatch)
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 8, length: 3))
    }

    func testTheScopeGrowsWithTextAddedInsideIt() throws {
        let controller = try openWithScope("x x x x", NSRange(location: 2, length: 3), find: "x", replace: "y")
        edit(controller, NSRange(location: 3, length: 0), " x")
        controller.findController.perform(.replaceAll)
        XCTAssertEqual(controller.textView.string, "x y y y x")
    }

    func testTextAfterTheScopeLeavesItAlone() throws {
        let controller = try openWithScope("x x x x", NSRange(location: 0, length: 3), find: "x", replace: "y")
        edit(controller, NSRange(location: 3, length: 1), "")
        controller.findController.perform(.replaceAll)
        XCTAssertEqual(controller.textView.string, "y yx x")
    }

    func testAnEditAcrossTheScopeEdgeShrinksIt() throws {
        let controller = try openWithScope("x x x x", NSRange(location: 2, length: 3), find: "x", replace: "y")
        edit(controller, NSRange(location: 1, length: 2), "")
        XCTAssertEqual(controller.textView.string, "x x x")
        controller.findController.perform(.replaceAll)
        XCTAssertEqual(controller.textView.string, "x y x")
    }

    func testADeletedScopeDoesNotWidenToTheWholeText() throws {
        let controller = try openWithScope("x x x x", NSRange(location: 2, length: 3), find: "x", replace: "y")
        edit(controller, NSRange(location: 2, length: 3), "")
        controller.findController.perform(.replaceAll)
        XCTAssertEqual(controller.textView.string, "x  x")
        XCTAssertEqual(controller.findController.bar.statusLabel.stringValue, "Not found")
    }

    func testUndoingReplaceAllRestoresTheScope() throws {
        let controller = try openWithScope("x x x x", NSRange(location: 2, length: 3), find: "x", replace: "yy")
        controller.findController.perform(.replaceAll)
        XCTAssertEqual(controller.textView.string, "x yy yy x")
        controller.textView.undoManager?.undo()
        XCTAssertEqual(controller.textView.string, "x x x x")
        controller.findController.bar.replaceField.tokens = [.text("z")]
        controller.findController.perform(.replaceAll)
        XCTAssertEqual(controller.textView.string, "x z z x")
    }

    func testAnotherTextTurnsTheScopeOff() throws {
        let controller = try openWithScope("x x x x", NSRange(location: 2, length: 3), find: "x")
        controller.replaceModel(EditorModel(file: TextFile(text: "x x x")))
        XCTAssertFalse(controller.findController.inSelection, "the switch must not claim a scope that's gone")
    }

    func testAShorterTextWithASelectionPastItsEndDoesNotCrash() throws {
        let controller = try open("x x x x")
        controller.textView.setSelectedRange(NSRange(location: 2, length: 3))
        controller.replaceModel(EditorModel(file: TextFile(text: "x")))
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 1, length: 0))
    }

    func testInSelectionWithNothingSelectedStaysOff() throws {
        let controller = try open("x x")
        controller.findController.perform(.showReplaceInterface)
        controller.findController.inSelection = true
        XCTAssertFalse(controller.findController.inSelection, "on with no scope would mean the whole text")
    }

    func testReopeningTheBarWithNothingSelectedTurnsInSelectionOff() throws {
        let controller = try openWithScope("x x x x", NSRange(location: 2, length: 3), find: "x", replace: "y")
        controller.findController.close()
        controller.textView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.findController.perform(.showReplaceInterface)
        XCTAssertFalse(controller.findController.inSelection)
    }

    func testRegexOptionAndInvalidPatternMessage() throws {
        let controller = try open("a1 b22")
        let find = controller.findController
        find.perform(.showReplaceInterface)
        find.options.regex = true
        find.bar.findField.tokens = [.text("(")]
        find.perform(.nextMatch)
        XCTAssertEqual(find.bar.statusLabel.stringValue, "Invalid pattern")

        find.bar.findField.tokens = [.text(#"(\w)(\d+)"#)]
        find.bar.replaceField.tokens = [.text("$2$1")]
        find.perform(.replaceAll)
        XCTAssertEqual(controller.textView.string, "1a 22b")
    }

    func testUseSelectionForFind() throws {
        let controller = try open("hello world")
        controller.textView.setSelectedRange(NSRange(location: 6, length: 5))
        controller.findController.perform(.setSearchString)
        XCTAssertEqual(controller.findController.bar.findField.tokens, [.text("world")])
    }

    func testNoMatchesBeepsQuietlyWithStatus() throws {
        let controller = try open("abc")
        let find = controller.findController
        find.perform(.showFindInterface)
        find.bar.findField.tokens = [.text("zzz")]
        find.perform(.nextMatch)
        XCTAssertEqual(find.bar.statusLabel.stringValue, "Not found")
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 0, length: 0))
    }
}
