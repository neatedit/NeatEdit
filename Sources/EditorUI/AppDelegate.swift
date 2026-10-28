import AppKit

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
}

enum MainMenu {
    static func make() -> NSMenu {
        let appName = ProcessInfo.processInfo.processName
        let main = NSMenu()

        main.addSubmenu(appName, [
            item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"),
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
        ])

        main.addSubmenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Delete", #selector(NSText.delete(_:))),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
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
            .separator(),
            item("Uppercase", #selector(NSResponder.uppercaseWord(_:))),
            item("Lowercase", #selector(NSResponder.lowercaseWord(_:))),
            item("Capitalize", #selector(NSResponder.capitalizeWord(_:))),
        ])

        main.addSubmenu("View", [
            item("Wrap Lines", #selector(EditorViewController.toggleWrapLines(_:)), "w", [.command, .option]),
            .separator(),
            item("Bigger", #selector(EditorViewController.makeTextBigger(_:)), "+"),
            item("Smaller", #selector(EditorViewController.makeTextSmaller(_:)), "-"),
            item("Actual Size", #selector(EditorViewController.makeTextStandardSize(_:)), "0"),
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

    private static func item(
        _ title: String, _ action: Selector, _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func find(
        _ title: String, _ action: NSTextFinder.Action, _ key: String,
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = self.item(title, #selector(NSTextView.performFindPanelAction(_:)), key, modifiers)
        item.tag = action.rawValue
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
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
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        item.submenu = menu
        addItem(item)
        return menu
    }
}
