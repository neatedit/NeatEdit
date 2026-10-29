import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// Where the file is (window subtitle, Copy Path, Show in Finder) and printing.
@MainActor
final class FileMenuTests: XCTestCase {
    private var savedThreshold = 0

    override func setUp() { savedThreshold = TextDocument.largeFileThreshold }
    override func tearDown() { TextDocument.largeFileThreshold = savedThreshold }

    private func open(_ text: String = "hello\n") throws -> (TextDocument, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try Data(text.utf8).write(to: url)
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        return (document, url)
    }

    private func fileItem(_ title: String) throws -> NSMenuItem {
        let file = try XCTUnwrap(MainMenu.make().item(withTitle: "File")?.submenu)
        return try XCTUnwrap(file.item(withTitle: title), title)
    }

    // MARK: Path

    func testSubtitleIsTheFolderWithTheHomeAbbreviated() {
        let home = "/Users/me"
        XCTAssertEqual(TextDocument.subtitle(for: URL(fileURLWithPath: "/Users/me/notes/a.txt"), home: home, viewer: false), "~/notes")
        XCTAssertEqual(TextDocument.subtitle(for: URL(fileURLWithPath: "/Users/me/a.txt"), home: home, viewer: false), "~")
        XCTAssertEqual(TextDocument.subtitle(for: URL(fileURLWithPath: "/Users/meg/a.txt"), home: home, viewer: false), "/Users/meg")
        XCTAssertEqual(TextDocument.subtitle(for: URL(fileURLWithPath: "/var/log/system.log"), home: home, viewer: true),
                       "/var/log — Read-only (large file)")
        XCTAssertEqual(TextDocument.subtitle(for: nil, home: home, viewer: false), "")
    }

    func testWindowShowsWhereTheFileIs() throws {
        let (document, url) = try open()
        defer { document.close() }
        let window = try XCTUnwrap(document.windowControllers.first?.window)
        XCTAssertEqual(window.subtitle, TextDocument.subtitle(for: url, home: TextDocument.homeDirectory, viewer: false))
        XCTAssertFalse(window.subtitle.isEmpty)
    }

    func testSubtitleFollowsTheFileToANewPlace() throws {
        let (document, _) = try open()
        defer { document.close() }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let moved = folder.appendingPathComponent("moved.txt")
        document.fileURL = moved
        XCTAssertEqual(document.windowControllers.first?.window?.subtitle,
                       TextDocument.subtitle(for: moved, home: TextDocument.homeDirectory, viewer: false))
    }

    func testCopyPathPutsTheFullPathOnThePasteboard() throws {
        let (document, url) = try open()
        defer { document.close() }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NeatEditTests-\(UUID().uuidString)"))
        document.copyPath(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), url.path)
    }

    // MARK: Menu

    func testFileMenuItems() throws {
        XCTAssertEqual(try fileItem("Copy Path").action, #selector(TextDocument.copyPath(_:)))
        XCTAssertEqual(try fileItem("Show in Finder").action, #selector(TextDocument.showInFinder(_:)))
        let setup = try fileItem("Page Setup…")
        XCTAssertEqual(setup.action, #selector(NSDocument.runPageLayout(_:)))
        XCTAssertEqual(setup.keyEquivalent, "p")
        XCTAssertEqual(setup.keyEquivalentModifierMask, [.command, .shift])
        let print = try fileItem("Print…")
        XCTAssertEqual(print.action, #selector(NSDocument.printDocument(_:)))
        XCTAssertEqual(print.keyEquivalent, "p")
        XCTAssertEqual(print.keyEquivalentModifierMask, .command)
    }

    func testPathItemsNeedASavedFile() throws {
        let untitled = TextDocument()
        for title in ["Copy Path", "Show in Finder"] {
            XCTAssertFalse(untitled.validateMenuItem(try fileItem(title)), title)
        }
        let (document, _) = try open()
        defer { document.close() }
        for title in ["Copy Path", "Show in Finder"] {
            XCTAssertTrue(document.validateMenuItem(try fileItem(title)), title)
        }
    }

    // MARK: Print

    func testPrintsTheTextInTheEditorFontWrappedToThePage() throws {
        let (document, _) = try open("first line\nsecond line\n")
        defer { document.close() }
        let operation = try document.printOperation(withSettings: [:])
        let view = try XCTUnwrap(operation.view as? NSTextView)
        XCTAssertEqual(view.string, "first line\nsecond line\n")
        XCTAssertEqual(view.font, Preferences.font)
        let info = operation.printInfo
        XCTAssertEqual(view.frame.width, info.imageablePageBounds.width, accuracy: 1)
        XCTAssertEqual(info.horizontalPagination, .fit)
        XCTAssertFalse(info.isVerticallyCentered)
    }

    func testTheViewerDoesNotPrint() throws {
        TextDocument.largeFileThreshold = 3
        let (document, _) = try open("a big file\n")
        defer { document.close() }
        XCTAssertFalse(document.validateMenuItem(try fileItem("Print…")))
        XCTAssertTrue(document.validateMenuItem(try fileItem("Show in Finder")))
    }
}
