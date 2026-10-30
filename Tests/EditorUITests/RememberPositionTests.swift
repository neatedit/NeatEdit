import AppKit
import XCTest
import EditorCore
@testable import EditorUI

/// A file reopens where it was left, in the editor and in the viewer.
@MainActor
final class RememberPositionTests: XCTestCase {
    private var saved: UserDefaults!
    private var savedThreshold = 0
    private let log = (1...5000).map { "line \($0)\n" }.joined()

    override func setUp() {
        saved = Preferences.defaults
        Preferences.defaults = UserDefaults(suiteName: "RememberPositionTests-\(UUID().uuidString)")!
        Preferences.registerDefaults()
        savedThreshold = TextDocument.largeFileThreshold
    }

    override func tearDown() {
        Preferences.defaults = saved
        TextDocument.largeFileThreshold = savedThreshold
    }

    private func file(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).log")
        try Data(text.utf8).write(to: url)
        return url
    }

    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }

    private func open(_ url: URL) throws -> (TextDocument, NSViewController) {
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first?.contentViewController)
        controller.view.window?.setContentSize(NSSize(width: 500, height: 300))
        controller.view.window?.makeKeyAndOrderFront(nil)
        settle()
        return (document, controller)
    }

    private func openViewer(_ url: URL) throws -> (TextDocument, LargeFileViewController) {
        TextDocument.largeFileThreshold = 10
        let (document, controller) = try open(url)
        return (document, try XCTUnwrap(controller as? LargeFileViewController))
    }

    private func openEditor(_ url: URL) throws -> (TextDocument, EditorViewController) {
        TextDocument.largeFileThreshold = 10_000_000
        let (document, controller) = try open(url)
        return (document, try XCTUnwrap(controller as? EditorViewController))
    }

    /// As ⌘W does: AppKit takes the window controller off the document before close().
    private func closeWindow(of document: TextDocument) {
        document.windowControllers.first?.window?.close()
        settle()
    }

    func testTheViewerComesBackWhereItWasLeftEvenWithoutAClick() throws {
        let url = try file(log)
        var (document, controller) = try openViewer(url)
        let view = controller.textView
        view.scroll(NSPoint(x: 0, y: view.lineRect(forLine: 2000).minY))
        let offset = controller.model.lineIndex.starts[2003]
        view.setSelection(NSRange(location: offset, length: 4), scroll: false)
        closeWindow(of: document)

        (document, controller) = try openViewer(url)
        defer { document.close() }
        XCTAssertEqual(controller.textView.selection, NSRange(location: offset, length: 4))
        XCTAssertEqual(controller.textView.visibleLineNumbers().first?.line, 2001)
    }

    func testTheEditorComesBackWhereItWasLeft() throws {
        let url = try file(log)
        var (document, controller) = try openEditor(url)
        let starts = controller.model.lineIndex.starts
        let lm = try XCTUnwrap(controller.textView.layoutManager)
        let row = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: starts[2000]), effectiveRange: nil)
        controller.textView.scroll(NSPoint(x: 0, y: row.minY + controller.textView.textContainerOrigin.y))
        controller.textView.setSelectedRange(NSRange(location: starts[2003], length: 0))
        closeWindow(of: document)

        (document, controller) = try openEditor(url)
        defer { document.close() }
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: starts[2003], length: 0))
        let glyphs = controller.textView.layoutManager!.glyphRange(forBoundingRect: controller.textView.visibleRect, in: controller.textView.textContainer!)
        let top = controller.textView.layoutManager!.characterIndexForGlyph(at: glyphs.location)
        XCTAssertEqual(controller.model.lineIndex.line(containing: top), 2000)
    }

    func testAnUntouchedFileLeavesNothingBehind() throws {
        let url = try file(log)
        let (document, _) = try openViewer(url)
        closeWindow(of: document)
        XCTAssertNil(Preferences.filePosition(for: url))
    }

    func testAFileLeftAtTheBottomComesBackAtTheBottomAfterGrowing() throws {
        let url = try file(log)
        var (document, controller) = try openViewer(url)
        controller.textView.scrollToEndOfDocument(nil)
        closeWindow(of: document)
        try Data((log + (1...1000).map { "more \($0)\n" }.joined()).utf8).write(to: url)

        (document, controller) = try openViewer(url)
        defer { document.close() }
        XCTAssertTrue(controller.isScrolledToBottom, "a followed log keeps being followed")
    }

    func testOneLongWrappedLineLeftAtTheBottomComesBackThere() throws {
        Preferences.wrapsLines = true
        let url = try file(String(repeating: "abcdefghij ", count: 20_000))
        var (document, controller) = try openEditor(url)
        controller.textView.scrollToEndOfDocument(nil)
        settle()
        closeWindow(of: document)

        (document, controller) = try openEditor(url)
        defer { document.close() }
        settle()
        XCTAssertTrue(controller.isScrolledToBottom)
    }

    func testAFileThatGotShorterOpensWithoutTrouble() throws {
        let url = try file(log)
        var (document, controller) = try openViewer(url)
        controller.textView.setSelection(NSRange(location: controller.model.lineIndex.starts[4000], length: 3))
        closeWindow(of: document)
        try Data("short\nfile\n".utf8).write(to: url)

        (document, controller) = try openViewer(url)
        defer { document.close() }
        XCTAssertEqual(controller.textView.selection, NSRange(location: 11, length: 0))
    }

    func testATabThatNeverAppearedKeepsWhatWasRemembered() throws {
        let url = try file(log)
        let position = FilePosition(location: 100, length: 0, topLine: 10, atEnd: false)
        Preferences.remember(position, for: url)
        TextDocument.largeFileThreshold = 10
        let document = try TextDocument(contentsOf: url, ofType: "public.plain-text")
        document.makeWindowControllers()  // a tab in the background: never shown
        document.savePosition()
        XCTAssertEqual(Preferences.filePosition(for: url), position)
        document.close()
    }

    func testRememberingDoesNotCountAsAPreferenceChange() throws {
        let url = try file(log)
        var posted = false
        let observer = NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { posted = true }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        Preferences.remember(FilePosition(location: 1, length: 0, topLine: 0, atEnd: false), for: url)
        XCTAssertFalse(posted)
    }

    func testSymlinksShareThePositionOfTheirTarget() throws {
        let url = try file(log)
        let link = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString)-link.log")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        let position = FilePosition(location: 1, length: 0, topLine: 0, atEnd: false)
        Preferences.remember(position, for: link)
        XCTAssertEqual(Preferences.filePosition(for: url), position)
    }
}
