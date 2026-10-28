import AppKit
import EditorCore

/// What a tab's content controller must do for its document.
protocol DocumentContent: NSViewController {
    func replaceModel(_ newModel: EditorModel)
}

/// The strip under the text: caret/selection on the left, totals on the right.
final class StatusBar: NSStackView {
    let left = StatusBar.label()
    let right = StatusBar.label()
    private var updatePending = false

    init() {
        super.init(frame: .zero)
        setViews([left, NSView(), right], in: .leading)
        orientation = .horizontal
        edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        left.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ status: StatusLine) {
        left.stringValue = status.left
        right.stringValue = status.right
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
    /// Scroll view filling the tab, a hairline, then the status bar.
    static func root(scrollView: NSScrollView, statusBar: StatusBar) -> NSView {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let separator = NSBox()
        separator.boxType = .separator

        let root = NSView()
        for sub in [scrollView, separator, statusBar] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
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
