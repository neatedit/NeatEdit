import AppKit
import XCTest
@testable import EditorUI
import EditorCore

@MainActor
final class CommandLineToolMenuTests: XCTestCase {
    func testAppMenuOffersTheCommandLineTool() throws {
        let appMenu = try XCTUnwrap(MainMenu.make().items.first?.submenu)
        let item = try XCTUnwrap(appMenu.item(withTitle: "Install Command Line Tool…"))
        XCTAssertEqual(item.action, #selector(AppDelegate.installCommandLineTool(_:)))
    }

    func testAlertShowsTheCommandForTheBundledScript() throws {
        let script = URL(fileURLWithPath: "/Applications/NeatEdit.app/Contents/Resources/neatedit")
        let alert = AppDelegate.commandLineToolAlert(script: script)
        let field = try XCTUnwrap(alert.accessoryView as? NSTextField)
        XCTAssertEqual(field.stringValue, CommandLineTool.installCommand(script: script.path))
        XCTAssertTrue(field.isSelectable)
        XCTAssertEqual(alert.buttons.map(\.title), ["Copy Command", "Done"])
    }

    func testWithoutABundledScriptTheAlertSaysSo() {
        let alert = AppDelegate.commandLineToolAlert(script: nil)
        XCTAssertNil(alert.accessoryView)
        XCTAssertEqual(alert.buttons.map(\.title), ["OK"])
    }
}
