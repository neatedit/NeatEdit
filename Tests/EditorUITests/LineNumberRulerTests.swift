import AppKit
import XCTest
import EditorCore
@testable import EditorUI

@MainActor
final class LineNumberRulerTests: XCTestCase {
    private var saved: UserDefaults!

    override func setUp() {
        saved = Preferences.defaults
        Preferences.defaults = UserDefaults(suiteName: "LineNumberRulerTests-\(UUID().uuidString)")!
        Preferences.registerDefaults()
    }

    override func tearDown() {
        Preferences.defaults = saved
    }

    private func show(_ text: String) -> EditorViewController {
        let controller = EditorViewController(model: EditorModel(file: TextFile(text: text)))
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 400, height: 300))
        window.layoutIfNeeded()
        controller.viewDidAppear()
        return controller
    }

    func testHiddenByDefault() {
        let controller = show("a\nb")
        XCTAssertFalse(controller.scrollView.rulersVisible)
    }

    func testShowsOneNumberPerLine() throws {
        Preferences.showsLineNumbers = true
        let controller = show("a\nb\nc\nd\ne")
        XCTAssertTrue(controller.scrollView.rulersVisible)
        let ruler = try XCTUnwrap(controller.lineNumberRuler)
        XCTAssertEqual(ruler.visibleNumbers().map(\.line), [1, 2, 3, 4, 5])
    }

    func testWrappedLineIsNumberedOnce() throws {
        Preferences.showsLineNumbers = true
        Preferences.wrapsLines = true
        let long = String(repeating: "word ", count: 200)
        let controller = show("first\n\(long)\nlast")
        let numbers = try XCTUnwrap(controller.lineNumberRuler).visibleNumbers()
        XCTAssertEqual(numbers.map(\.line), [1, 2, 3])
        XCTAssertGreaterThan(numbers[2].y - numbers[1].y, (numbers[1].y - numbers[0].y) * 2)
    }

    func testGutterWidensWithDigits() throws {
        Preferences.showsLineNumbers = true
        let small = try XCTUnwrap(show("1\n2\n3").lineNumberRuler)
        let big = try XCTUnwrap(show(Array(repeating: "x", count: 10_000).joined(separator: "\n")).lineNumberRuler)
        XCTAssertGreaterThan(big.ruleThickness, small.ruleThickness)
    }

    func testGutterWidensWithFontSize() throws {
        Preferences.showsLineNumbers = true
        let ruler = try XCTUnwrap(show("1\n2\n3").lineNumberRuler)
        let before = ruler.ruleThickness
        Preferences.fontSize = 40
        ruler.updateThickness()
        XCTAssertGreaterThan(ruler.ruleThickness, before)
    }

    func testTogglingOffHidesGutter() {
        Preferences.showsLineNumbers = true
        let controller = show("a")
        Preferences.showsLineNumbers = false
        XCTAssertFalse(controller.scrollView.rulersVisible)
    }

    func testFollowsEdits() throws {
        Preferences.showsLineNumbers = true
        let controller = show("a")
        controller.textView.insertText("\nb\nc", replacementRange: NSRange(location: 1, length: 0))
        XCTAssertEqual(try XCTUnwrap(controller.lineNumberRuler).visibleNumbers().map(\.line), [1, 2, 3])
    }
}
