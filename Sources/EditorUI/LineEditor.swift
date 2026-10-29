import AppKit
import EditorCore

/// The sheet for Edit Lines…: a few lines of a large file, edited as plain
/// text and written straight back into the file.
final class LineEditorController: NSViewController {
    let chunk: LineSplice.Chunk
    let textView = PlainTextView.make(text: "")
    let titleLabel = NSTextField(labelWithString: "")
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    /// Writes the edited text; throws to keep the sheet open with the reason.
    var onSave: ((String) throws -> Void)?

    init(chunk: LineSplice.Chunk) {
        self.chunk = chunk
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        titleLabel.stringValue = L10n.tr("Lines %ld–%ld", chunk.firstLine + 1, chunk.lastLine + 1)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true

        textView.string = chunk.text
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 640).isActive = true

        let cancel = NSButton(title: L10n.tr("Cancel"), target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: L10n.tr("Save"), target: self, action: #selector(save(_:)))
        save.keyEquivalent = "s"
        save.keyEquivalentModifierMask = .command
        let buttons = NSStackView(views: [errorLabel, NSView(), cancel, save])

        let stack = NSStackView(views: [titleLabel, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        buttons.widthAnchor.constraint(equalTo: scroll.widthAnchor).isActive = true
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        view = stack
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        textView.wrapsLines = false
        view.window?.makeFirstResponder(textView)
    }

    @objc func save(_ sender: Any?) {
        do {
            try onSave?(textView.string)
            dismiss(nil)
        } catch {
            errorLabel.stringValue = Self.message(for: error)
            errorLabel.isHidden = false
        }
    }

    @objc func cancel(_ sender: Any?) { dismiss(nil) }

    static func message(for error: Error) -> String {
        switch error as? LineSplice.Failure {
        case .changedOnDisk: L10n.tr("These lines changed on disk. Cancel and open them again to edit the current text.")
        case .unencodable: L10n.tr("Some characters don't exist in the file's encoding.")
        case .unsupportedEncoding: L10n.tr("Lines can't be edited in this file's encoding.")
        case nil: error.localizedDescription
        }
    }
}
