import AppKit
import EditorCore

/// What a tab's content controller must do for its document.
protocol DocumentContent: NSViewController {
    func replaceModel(_ newModel: EditorModel)
    /// Replace the text with the file's new contents as one undo step.
    func reload(from file: TextFile)
    /// Replace the text as one undo step (format unchanged).
    func replaceText(with text: String, actionName: String)
    func externalStateDidChange(_ state: TextDocument.ExternalState)
}

/// A tab that follows its file as it grows (`tail -f`).
protocol TailFollowing: DocumentContent {
    /// Asked before the text grows: whether to keep up with it.
    var isScrolledToBottom: Bool { get }
    /// The document appended to the model past `oldLength`.
    func textDidGrow(from oldLength: Int, follow: Bool)
}

/// The strip under the text: caret/selection on the left, totals on the
/// right, then encoding and line ending, which open menus when clicked.
final class StatusBar: NSStackView {
    let left = StatusBar.label()
    let right = StatusBar.label()
    let encodingButton = StatusBar.button()
    let lineEndingButton = StatusBar.button()
    /// Whether clicking the line ending offers conversion (not in the read-only viewer).
    var canChangeLineEnding = true {
        didSet { lineEndingButton.isEnabled = canChangeLineEnding }
    }
    private var lineEnding = LineEnding.lf
    private var updatePending = false

    init() {
        super.init(frame: .zero)
        setViews([left, NSView(), right, encodingButton, lineEndingButton], in: .leading)
        spacing = 12
        lineEndingButton.target = self
        lineEndingButton.action = #selector(showLineEndingMenu(_:))
        orientation = .horizontal
        edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        left.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ status: StatusLine) {
        left.stringValue = status.left
        right.stringValue = status.totals
        encodingButton.title = status.encoding
        lineEndingButton.title = status.lineEnding.rawValue
        lineEnding = status.lineEnding
    }

    /// Everything on the right as one string, as the status bar reads.
    var rightText: String {
        "\(right.stringValue)   \(encodingButton.title)   \(lineEndingButton.title)"
    }

    /// Items go up the responder chain to `chooseLineEnding(_:)`.
    func lineEndingMenu() -> NSMenu {
        let menu = NSMenu()
        for ending in LineEnding.allCases {
            let item = NSMenuItem(title: ending.rawValue, action: #selector(EditorViewController.chooseLineEnding(_:)), keyEquivalent: "")
            item.representedObject = ending.rawValue
            item.state = ending == lineEnding ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func showLineEndingMenu(_ sender: NSButton) {
        Self.pop(lineEndingMenu(), under: sender)
    }

    static func pop(_ menu: NSMenu, under button: NSButton) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    /// Coalesce bursts (typing, dragging a selection) into one update per run loop pass.
    func scheduleUpdate(_ update: @escaping () -> Void) {
        guard !updatePending else { return }
        updatePending = true
        DispatchQueue.main.async { [weak self] in
            self?.updatePending = false
            update()
        }
    }

    private static func button() -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        button.isBordered = false
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        button.contentTintColor = .secondaryLabelColor
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    private static func label() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = true
        return label
    }
}

enum EditorChrome {
    /// Optional find bar, scroll view filling the tab, a hairline, then the status bar.
    static func root(scrollView: NSScrollView, statusBar: StatusBar, banner: NSView? = nil, findBar: NSView? = nil) -> NSView {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let separator = NSBox()
        separator.boxType = .separator

        // A stack so the hidden find bar takes no space.
        let content = NSStackView(views: [banner, findBar, scrollView].compactMap { $0 })
        content.orientation = .vertical
        content.spacing = 0
        for view in content.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        findBar?.setContentHuggingPriority(.required, for: .vertical)
        banner?.setContentHuggingPriority(.required, for: .vertical)

        let root = NSView()
        for sub in [content, separator, statusBar] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.topAnchor.constraint(equalTo: content.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.topAnchor.constraint(equalTo: separator.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 22),
        ])
        root.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        return root
    }

    /// "Reopen with Encoding" (files on disk only) and "Save with Encoding"
    /// sections; items carry the encoding's raw value and call `target`.
    static func encodingMenu(current: String.Encoding, reopen: Selector?, save: Selector?, target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [("Reopen with Encoding", reopen), ("Save with Encoding", save)] {
            guard let action else { continue }
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: title))
            for encoding in TextFile.choices {
                let item = NSMenuItem(title: TextFile.name(of: encoding), action: action, keyEquivalent: "")
                item.target = target
                item.representedObject = encoding.rawValue
                item.state = encoding == current ? .on : .off
                menu.addItem(item)
            }
        }
        return menu
    }

    static func encoding(of item: NSMenuItem) -> String.Encoding? {
        (item.representedObject as? UInt).map(String.Encoding.init(rawValue:))
    }

    /// Sheet asking for "line" or "line:column"; calls back only with valid input.
    static func askForLine(on window: NSWindow, _ completion: @escaping (GoToLine) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.informativeText = "Line, or line:column"
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "e.g. 120 or 120:5"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn, let target = GoToLine.parse(field.stringValue) else { return }
            completion(target)
        }
    }
}
