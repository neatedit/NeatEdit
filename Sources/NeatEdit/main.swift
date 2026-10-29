import AppKit
import EditorUI

// The first NSDocumentController created becomes the shared one.
_ = DocumentController()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
