import AppKit
import EditorCore

/// Strip at the top of a tab when its file changed or vanished on disk.
/// It waits for the user; nothing pops up on its own.
final class ExternalChangeBanner: NSView {
    let message = NSTextField(labelWithString: "")
    let primaryButton = NSButton(title: "Review Changes", target: nil, action: nil)
    let dismissButton = NSButton(title: "Dismiss", target: nil, action: nil)
    var onPrimary: (() -> Void)?
    var onDismiss: (() -> Void)?

    init() {
        super.init(frame: .zero)
        isHidden = true
        message.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        for button in [primaryButton, dismissButton] {
            button.controlSize = .small
            button.bezelStyle = .rounded
            button.target = self
        }
        primaryButton.action = #selector(primaryClicked)
        dismissButton.action = #selector(dismissClicked)

        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)!)
        icon.contentTintColor = .systemOrange
        let stack = NSStackView(views: [icon, message, NSView(), primaryButton, dismissButton])
        stack.orientation = .horizontal
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ state: TextDocument.ExternalState) {
        switch state {
        case .none:
            isHidden = true
        case .changed(let merge, _):
            isHidden = false
            message.stringValue = "File changed on disk"
            primaryButton.isHidden = false
            primaryButton.isEnabled = true
            primaryButton.title = merge.isBig ? "Save My Version As…" : "Review Changes"
        case .checking:
            isHidden = false
            message.stringValue = "File changed on disk"
            primaryButton.isHidden = false
            primaryButton.isEnabled = false
            primaryButton.title = "Comparing…"
        case .deleted:
            isHidden = false
            message.stringValue = "Deleted from disk"
            primaryButton.isHidden = true
        }
    }

    @objc private func primaryClicked() { onPrimary?() }
    @objc private func dismissClicked() { onDismiss?() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemOrange.withAlphaComponent(0.12).setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

/// Sheet listing what changed on disk, one row per hunk, each accepted or
/// skipped on its own. Nothing touches the text until Apply.
final class ChangeReviewController: NSViewController {
    private(set) var merge: ExternalMerge
    private(set) var decisions: [Int: HunkDecision] = [:]
    var onApply: (([Int: HunkDecision]) -> Void)?
    var onCancel: (() -> Void)?

    private let rows = NSStackView()
    private var choices: [Int: NSSegmentedControl] = [:]

    init(merge: ExternalMerge) {
        self.merge = merge
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var rowCount: Int { rows.arrangedSubviews.count }

    override func loadView() {
        let title = NSTextField(labelWithString: "Changes made on disk")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let info = NSTextField(wrappingLabelWithString:
            "Choose which changes to bring into your text. Changes you don't decide on are skipped.")
        info.textColor = .secondaryLabelColor

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 14
        rows.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let document = FlippedView()
        rows.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rows)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: document.topAnchor),
            rows.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let apply = NSButton(title: "Apply", target: self, action: #selector(apply(_:)))
        apply.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, apply])

        let root = NSStackView(views: [title, info, scroll, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        for view in [info, scroll, buttons] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32).isActive = true
        }
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        root.frame = NSRect(x: 0, y: 0, width: 680, height: 520)
        view = root
        rebuildRows()
    }

    /// The file changed again while reviewing: keep decisions on hunks that are still there.
    func update(merge: ExternalMerge) {
        // A hunk that kept its place (e.g. a log tail that grew) keeps its decision.
        var byPlace: [Range<Int>: HunkDecision] = [:]
        for hunk in self.merge.hunks {
            if let decision = decisions[hunk.id] { byPlace[hunk.base.oldRange] = decision }
        }
        self.merge = merge
        decisions = [:]
        for hunk in merge.hunks {
            if let decision = byPlace[hunk.base.oldRange] { decisions[hunk.id] = decision }
        }
        if isViewLoaded { rebuildRows() }
    }

    func decide(_ id: Int, _ decision: HunkDecision) {
        decisions[id] = decision
        choices[id]?.selectedSegment = decision == .accept ? 0 : 1
    }

    func choiceLabels(for id: Int) -> [String] {
        guard let control = choices[id] else { return [] }
        return (0..<control.segmentCount).compactMap { control.label(forSegment: $0) }
    }

    private func rebuildRows() {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        choices = [:]
        for hunk in merge.hunks {
            rows.addArrangedSubview(row(for: hunk))
        }
    }

    private func row(for hunk: ExternalHunk) -> NSView {
        let first = hunk.base.oldRange.lowerBound + 1
        var heading = hunk.base.oldRange.count > 1 ? "Lines \(first)–\(hunk.base.oldRange.upperBound)" : "Line \(first)"
        if hunk.isConflict { heading += " — you edited these lines too" }
        let label = NSTextField(labelWithString: heading)
        label.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = hunk.isConflict ? .systemOrange : .labelColor

        let titles = hunk.isConflict ? ["Take Disk", "Keep Mine"] : ["Accept", "Skip"]
        let control = NSSegmentedControl(labels: titles, trackingMode: .selectOne, target: self, action: #selector(choose(_:)))
        control.controlSize = .small
        control.tag = hunk.id
        control.selectedSegment = decisions[hunk.id].map { $0 == .accept ? 0 : 1 } ?? -1
        choices[hunk.id] = control

        let header = NSStackView(views: [label, NSView(), control])
        let diff = NSTextField(labelWithAttributedString: Self.diffText(hunk))
        diff.isSelectable = true
        diff.lineBreakMode = .byCharWrapping
        diff.maximumNumberOfLines = 0
        diff.preferredMaxLayoutWidth = 600
        let row = NSStackView(views: [header, diff])
        row.orientation = .vertical
        row.alignment = .leading
        header.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        return row
    }

    /// More than this per side is summarized, so a huge append can't stall the sheet.
    static let maxLinesPerSide = 200

    static func diffText(_ hunk: ExternalHunk) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let out = NSMutableAttributedString()
        func add(_ lines: [String], _ prefix: String, _ color: NSColor) {
            for line in lines.prefix(maxLinesPerSide) {
                out.append(NSAttributedString(string: prefix + line + "\n", attributes: [.font: font, .foregroundColor: color]))
            }
            if lines.count > maxLinesPerSide {
                out.append(NSAttributedString(string: "  … \(lines.count - maxLinesPerSide) more lines\n",
                                              attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
            }
        }
        if hunk.isConflict {
            add(hunk.mineLines, "  mine  ", .systemOrange)
        }
        add(hunk.oldLines, "  −  ", .systemRed)
        add(hunk.base.newLines, "  +  ", .systemGreen)
        if out.length > 0 { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        return out
    }

    @objc private func choose(_ sender: NSSegmentedControl) {
        decisions[sender.tag] = sender.selectedSegment == 0 ? .accept : .skip
    }

    @objc private func apply(_ sender: Any?) { onApply?(decisions) }
    @objc private func cancel(_ sender: Any?) { onCancel?() }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
