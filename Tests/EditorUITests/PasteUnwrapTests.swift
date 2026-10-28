import AppKit
import XCTest
import EditorCore
@testable import EditorUI

@MainActor
final class PasteUnwrapTests: XCTestCase {
    private var saved: UserDefaults!
    private let wrapped = """
          5. Caniipu v raatpu. Lmsv sugmtr lltain ol levcutirm. Cllcr nrnlcu c olscrsitrp csinrcltuv olduc raatpu can Oddome (Lmsv Vr-Sll Ceaveo): drploiclcu vrir dasgd cnlgrir mrmetci, tldlupgln prgu SV lrodaotlc
          prlrspi lsr vrsm otlvugrsd. Ae tecegupl olnlol c prna, mrai olrsucu rplemum LC.
        """
    private var unwrapped: String { TextUnwrap.unwrapIfWrapped(wrapped)! }

    override func setUp() {
        saved = Preferences.defaults
        Preferences.defaults = UserDefaults(suiteName: "PasteUnwrapTests-\(UUID().uuidString)")!
        Preferences.registerDefaults()
    }

    override func tearDown() {
        Preferences.defaults = saved
    }

    private func editor(_ text: String = "") -> (EditorViewController, NSWindow) {
        let controller = EditorViewController(model: EditorModel(file: TextFile(text: text)))
        let window = NSWindow(contentViewController: controller)
        window.makeFirstResponder(controller.textView)
        return (controller, window)
    }

    private func pasteboard(_ string: String) -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("PasteUnwrapTests-\(UUID().uuidString)"))
        pb.clearContents()
        pb.setString(string, forType: .string)
        return pb
    }

    private func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

    func testWrappedPasteIsUnwrapped() {
        let (controller, window) = editor()
        XCTAssertTrue(controller.textView.paste(from: pasteboard(wrapped)))
        XCTAssertEqual(controller.textView.string, unwrapped)
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: (unwrapped as NSString).length, length: 0))
        _ = window
    }

    func testFirstUndoRestoresTheOriginalPasteSecondRemovesIt() throws {
        let (controller, window) = editor("x")
        controller.textView.setSelectedRange(NSRange(location: 1, length: 0))
        _ = controller.textView.paste(from: pasteboard(wrapped))
        spin()
        let undo = try XCTUnwrap(controller.textView.undoManager)
        XCTAssertEqual(undo.undoActionName, "Unwrap Pasted Text")
        undo.undo()
        XCTAssertEqual(controller.textView.string, "x" + wrapped)
        spin()
        undo.undo()
        XCTAssertEqual(controller.textView.string, "x")
        _ = window
    }

    func testStatusBarSaysWhatHappenedUntilTheNextChange() {
        let (controller, window) = editor()
        _ = controller.textView.paste(from: pasteboard(wrapped))
        spin()
        XCTAssertEqual(controller.leftStatus.stringValue, "Unwrapped pasted text — ⌘Z for original")
        controller.textView.insertText("!", replacementRange: controller.textView.selectedRange())
        spin()
        XCTAssertTrue(controller.leftStatus.stringValue.hasPrefix("Ln 1"))
        _ = window
    }

    func testOrdinaryPasteIsUntouched() {
        let (controller, window) = editor()
        _ = controller.textView.paste(from: pasteboard("short\nlines"))
        spin()
        XCTAssertEqual(controller.textView.string, "short\nlines")
        XCTAssertTrue(controller.leftStatus.stringValue.hasPrefix("Ln 2"))
        _ = window
    }

    func testTurnedOffPastesAsIs() {
        Preferences.unwrapsPastedText = false
        let (controller, window) = editor()
        _ = controller.textView.paste(from: pasteboard(wrapped))
        XCTAssertEqual(controller.textView.string, wrapped)
        _ = window
    }

    func testMenuPasteGoesThroughUnwrap() {
        let general = NSPasteboard.general
        let previous = general.string(forType: .string)
        defer {
            general.clearContents()
            if let previous { general.setString(previous, forType: .string) }
        }
        general.clearContents()
        general.setString(wrapped, forType: .string)
        let (controller, window) = editor()
        controller.textView.paste(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(controller.textView.string, unwrapped)
        // One ⌘Z (the Undo menu goes up the responder chain) gives the original back.
        XCTAssertTrue(controller.textView.tryToPerform(Selector(("undo:")), with: nil))
        XCTAssertEqual(controller.textView.string, wrapped)
        _ = window
    }

    func testUnwrapLinesCommandWorksOnSelection() throws {
        let (controller, window) = editor("before\n" + wrapped + "\nafter")
        let range = (controller.textView.string as NSString).range(of: wrapped)
        controller.textView.setSelectedRange(range)
        controller.unwrapLines(nil)
        XCTAssertEqual(controller.textView.string, "before\n" + unwrapped + "\nafter")
        try XCTUnwrap(controller.textView.undoManager).undo()
        XCTAssertEqual(controller.textView.string, "before\n" + wrapped + "\nafter")
        _ = window
    }

    func testServicesReplacingTheSelectionAreNotUnwrapped() {
        let (controller, window) = editor()
        XCTAssertTrue(controller.textView.readSelection(from: pasteboard(wrapped)))
        XCTAssertEqual(controller.textView.string, wrapped)
        _ = window
    }

    func testReadOnlyViewDoesNotHalfReplace() {
        let (controller, window) = editor("abc")
        controller.textView.isEditable = false
        controller.textView.setSelectedRange(NSRange(location: 3, length: 0))
        _ = controller.textView.paste(from: pasteboard(wrapped))
        XCTAssertEqual(controller.textView.string, "abc")
        _ = window
    }

    func testPreferenceDefaultsOn() {
        XCTAssertTrue(Preferences.unwrapsPastedText)
    }
}
