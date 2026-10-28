# SimpleTextEdit

A small, native macOS plain-text editor (Swift + AppKit, no dependencies).

- Tabs are native macOS window tabs (⌘T / ⌘N). Unsaved tabs survive quitting — no "Save?" prompts.
- Paste always inserts plain text exactly at the caret.
- Status bar: line, column, position, current line length, selection size, total characters/lines, encoding, line endings.
- Files are saved back in their original encoding, BOM and line endings.
- Files over ~20 MB open in a read-only viewer that stays instant at hundreds of MB (select, copy, find, go to line).

## Build

```sh
./scripts/build-app.sh        # → build/SimpleTextEdit.app
swift test                    # unit + UI tests
swift test -c release -Xswiftc -enable-testing --filter testLargeFile   # 200 MB load benchmark
```

## Layout

- `Sources/EditorCore` — pure logic: line index, cursor position, decoding, status text, navigation, viewer geometry.
- `Sources/EditorUI` — AppKit: document, tabs, editor view, large file viewer, menus.
- `Sources/SimpleTextEdit` — `main.swift` only.
