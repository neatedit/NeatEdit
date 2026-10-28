# SimpleTextEdit

A small, native macOS plain-text editor (Swift + AppKit, no dependencies).

- Tabs are native macOS window tabs (⌘T / ⌘N). Unsaved tabs survive quitting — no "Save?" prompts.
- Paste always inserts plain text exactly at the caret.
- Status bar: line, column, position, current line length, selection size, total characters/lines, encoding, line endings.
- Files are saved back in their original encoding, BOM and line endings.
- Find & replace (⌘F / ⌥⌘F) with Coda-style numbered placeholders: ★ adds a chip to Find that matches any text on the line, and the same number in Replace puts that text back. Options (⚙): match case, regular expression (`$1` templates, `^`/`$` per line), in selection. Replace All is a single undo step.
- New documents save as `.txt` by default.
- Files over ~20 MB open in a read-only viewer that stays instant at hundreds of MB (select, copy, find, go to line).

## Build

```sh
./scripts/build-app.sh        # → build/SimpleTextEdit.app
swift test                    # unit + UI tests
swift scripts/make-icon.swift # regenerate Resources/AppIcon.icns
swift test -c release -Xswiftc -enable-testing --filter testLargeFile   # 200 MB load benchmark
```

## Layout

- `Sources/EditorCore` — pure logic: line index, cursor position, decoding, status text, navigation, viewer geometry, find queries.
- `Sources/EditorUI` — AppKit: document, tabs, editor view, find bar, large file viewer, menus.
- `Sources/SimpleTextEdit` — `main.swift` only.
