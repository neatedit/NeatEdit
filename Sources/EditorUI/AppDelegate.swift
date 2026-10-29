import AppKit
import EditorCore

public final class AppDelegate: NSObject, NSApplicationDelegate {
    override public init() {
        super.init()
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.mainMenu = MainMenu.make()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
    }

    @objc func newTab(_ sender: Any?) {
        NSDocumentController.shared.newDocument(sender)
    }

    @objc func installCommandLineTool(_ sender: Any?) {
        let alert = Self.commandLineToolAlert(script: Bundle.main.url(forResource: "neatedit", withExtension: nil))
        guard alert.runModal() == .alertFirstButtonReturn, let field = alert.accessoryView as? NSTextField else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(field.stringValue, forType: .string)
    }

    /// The command to link the bundled script into the PATH, ready to copy.
    static func commandLineToolAlert(script: URL?) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = L10n.tr("Install Command Line Tool")
        guard let script else {
            alert.informativeText = L10n.tr("This build of NeatEdit doesn't include the neatedit command.")
            alert.addButton(withTitle: L10n.tr("OK"))
            return alert
        }
        // Opened straight from Downloads or a disk image: macOS runs it from a
        // random read-only copy, and a link to that breaks later.
        guard !script.path.contains("/AppTranslocation/") else {
            alert.informativeText = L10n.tr("Move NeatEdit to the Applications folder and open it from there first.")
            alert.addButton(withTitle: L10n.tr("OK"))
            return alert
        }
        alert.informativeText = L10n.tr("Run this in Terminal once to open files with “neatedit file.txt” (or “some-command | neatedit -”). Move NeatEdit to its final place first.")
        let field = NSTextField(wrappingLabelWithString: CommandLineTool.installCommand(script: script.path))
        field.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.isSelectable = true
        field.preferredMaxLayoutWidth = 360
        field.frame.size = field.fittingSize
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.tr("Copy Command"))
        alert.addButton(withTitle: L10n.tr("Done"))
        return alert
    }
}

enum MainMenu {
    static func make() -> NSMenu {
        let appName = ProcessInfo.processInfo.processName
        let main = NSMenu()

        main.addSubmenu(appName, [
            item(localized: L10n.tr("About %@", appName), #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Install Command Line Tool…", #selector(AppDelegate.installCommandLineTool(_:))),
            .separator(),
            item(localized: L10n.tr("Hide %@", appName), #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item(localized: L10n.tr("Quit %@", appName), #selector(NSApplication.terminate(_:)), "q"),
        ])

        main.addSubmenu("File", [
            item("New Tab", #selector(AppDelegate.newTab(_:)), "t"),
            item("New", #selector(NSDocumentController.newDocument(_:)), "n"),
            item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
            openRecent(),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Save…", #selector(NSDocument.save(_:)), "s"),
            item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]),
            item("Rename…", #selector(NSDocument.rename(_:))),
            item("Move To…", #selector(NSDocument.move(_:))),
            item("Revert To Saved", #selector(NSDocument.revertToSaved(_:))),
            .separator(),
            item("Copy Path", #selector(TextDocument.copyPath(_:))),
            item("Show in Finder", #selector(TextDocument.showInFinder(_:))),
            .separator(),
            item("Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift]),
            item("Print…", #selector(NSDocument.printDocument(_:)), "p"),
        ])

        main.addSubmenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Unwrap Pasted Text", #selector(EditorViewController.toggleUnwrapPastedText(_:))),
            item("Delete", #selector(NSText.delete(_:))),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Duplicate Line", #selector(PlainTextView.duplicateLine(_:)), "d"),
            item("Move Line Up", #selector(NSTextView.moveLineUp(_:)), arrow(NSUpArrowFunctionKey), .option),
            item("Move Line Down", #selector(NSTextView.moveLineDown(_:)), arrow(NSDownArrowFunctionKey), .option),
            .separator(),
            submenu("Find", [
                find("Find…", .showFindInterface, "f"),
                find("Find and Replace…", .showReplaceInterface, "f", [.command, .option]),
                find("Find Next", .nextMatch, "g"),
                find("Find Previous", .previousMatch, "g", [.command, .shift]),
                find("Use Selection for Find", .setSearchString, "e"),
                .separator(),
                find("Replace", .replace, ""),
                find("Replace All", .replaceAll, ""),
                .separator(),
                item("Jump to Selection", #selector(NSTextView.centerSelectionInVisibleArea(_:)), "j"),
            ]),
            item("Go to Line…", #selector(EditorViewController.goToLine(_:)), "l"),
            item("Go to Beginning", #selector(NSResponder.moveToBeginningOfDocument(_:)), arrow(NSUpArrowFunctionKey)),
            item("Go to End", #selector(NSResponder.moveToEndOfDocument(_:)), arrow(NSDownArrowFunctionKey)),
        ])

        // Each acts on the selection, or on the whole text when nothing is selected.
        main.addSubmenu("Text", [
            transform(.uppercase), transform(.lowercase), transform(.titleCase),
            .separator(),
            transform(.sortLines), transform(.removeDuplicateLines), transform(.removeEmptyLines),
            transform(.trimTrailingWhitespace), transform(.joinLines), transform(.unwrapLines),
            .separator(),
            transform(.tabsToSpaces), transform(.spacesToTabs),
            .separator(),
            transform(.formatJSON), transform(.minifyJSON),
            .separator(),
            transform(.base64Encode), transform(.base64Decode), transform(.urlEncode), transform(.urlDecode),
        ])

        main.addSubmenu("View", [
            item("Wrap Lines", #selector(EditorViewController.toggleWrapLines(_:)), "w", [.command, .option]),
            item("Show Line Numbers", #selector(EditorViewController.toggleLineNumbers(_:)), "l", [.command, .option]),
            item("Show Invisibles", #selector(EditorViewController.toggleInvisibles(_:)), "i", [.command, .option]),
            item("Highlight Current Line", #selector(EditorViewController.toggleCurrentLine(_:))),
            .separator(),
            item("Bigger", #selector(EditorViewController.makeTextBigger(_:)), "+"),
            item("Smaller", #selector(EditorViewController.makeTextSmaller(_:)), "-"),
            item("Actual Size", #selector(EditorViewController.makeTextStandardSize(_:)), "0"),
            item("Font…", #selector(EditorViewController.showFontPanel(_:))),
            .separator(),
            item("Show Tab Bar", #selector(NSWindow.toggleTabBar(_:))),
            item("Show All Tabs", #selector(NSWindow.toggleTabOverview(_:)), "\\", [.command, .shift]),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])

        let window = main.addSubmenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "{"),
            item("Show Next Tab", #selector(NSWindow.selectNextTab(_:)), "}"),
            item("Move Tab to New Window", #selector(NSWindow.moveTabToNewWindow(_:))),
            item("Merge All Windows", #selector(NSWindow.mergeAllWindows(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = window
        return main
    }

    /// `title` is the English key; it's translated here.
    private static func item(
        _ title: String, _ action: Selector, _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        item(localized: L10n.tr(title), action, key, modifiers)
    }

    private static func item(
        localized title: String, _ action: Selector, _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func arrow(_ key: Int) -> String {
        String(UnicodeScalar(UInt16(key))!)
    }

    private static func find(
        _ title: String, _ action: NSTextFinder.Action, _ key: String,
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = self.item(title, #selector(NSTextView.performFindPanelAction(_:)), key, modifiers)
        item.tag = action.rawValue
        return item
    }

    private static func transform(_ transform: TextTransform) -> NSMenuItem {
        let item = self.item(localized: transform.title, #selector(EditorViewController.transformText(_:)))
        item.tag = TextTransform.allCases.firstIndex(of: transform)!
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: L10n.tr(title), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L10n.tr(title))
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    /// AppKit fills the submenu that contains a "clearRecentDocuments:" item.
    private static func openRecent() -> NSMenuItem {
        submenu("Open Recent", [
            item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:))),
        ])
    }
}

private extension NSMenu {
    @discardableResult
    func addSubmenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let item = NSMenuItem(title: L10n.tr(title), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L10n.tr(title))
        items.forEach(menu.addItem)
        item.submenu = menu
        addItem(item)
        return menu
    }
}
