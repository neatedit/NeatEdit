# NeatEdit

A small, native macOS plain-text editor (Swift + AppKit, no dependencies).

- Tabs are native macOS window tabs (⌘T / ⌘N). Unsaved tabs survive quitting — no "Save?" prompts.
- Paste always inserts plain text exactly at the caret. Text copied from a terminal UI (hard-wrapped at the window width, with a left margin — e.g. Claude Code output) is unwrapped back into paragraphs; lists, headings, tables and fenced code keep their lines. The unwrap is its own undo step: one ⌘Z gives the text exactly as copied. Turn it off with Edit ▸ Unwrap Pasted Text; Text ▸ Unwrap Lines does it on demand.
- Status bar: line, column, position, current line length, selection size, total characters/lines, encoding, line endings. Click the encoding to reopen the file as another encoding (or pick one for saving); click the line ending to convert LF / CRLF / CR (one ⌘Z undoes it).
- View menu: line numbers (⌥⌘L), wrap lines (⌥⌘W), bigger / smaller (⌘+ / ⌘−), Font… (monospaced fonts only). Line numbers and wrapping are off by default.
- Files changed on disk: an unedited tab reloads quietly (⌘Z brings the old text back). If the tab has unsaved edits, a banner offers to review the outside changes piece by piece — accept or skip each one, conflicts with your own edits are marked — or, when most of the file changed, to save your version under another name and load the new one. ⌘S and autosave never overwrite an outside change you haven't looked at. A deleted file keeps its text; saving recreates it.
- Files are saved back in their original encoding, BOM and line endings.
- Find & replace (⌘F / ⌥⌘F) with Coda-style numbered placeholders: ★ adds a chip to Find that matches any text on the line, and the same number in Replace puts that text back. Options (⚙): match case, regular expression (`$1` templates, `^`/`$` per line), in selection. Replace All is a single undo step.
- Text menu: UPPERCASE / lowercase / Title Case; sort lines (natural order), remove duplicate or empty lines, trim trailing whitespace, join lines, unwrap lines; tabs ↔ spaces (tab width 4, Spaces to Tabs touches indentation only); format / minify JSON (key order and numbers kept as written); Base64 and URL encode / decode. Each acts on the selection — line commands take whole lines — or on the whole text when nothing is selected, as one ⌘Z. Invalid JSON or Base64 leaves the text alone and says why in the status bar.
- Edit ▸ Go to Line… (⌘L), Go to Beginning (⌘↑), Go to End (⌘↓). In the viewer, Go to End also starts following new lines.
- New documents save as `.txt` by default.
- Files over ~20 MB open in a read-only viewer that stays instant at hundreds of MB (select, copy, find with the same placeholder bar as the editor — no replace — and go to line). It follows a growing file like `tail -f`: only the added bytes are read, and when you're at the bottom the view keeps up with new lines (scroll up and it stays put). A truncated, rewritten or recreated file is reloaded whole.

## Build

```sh
./scripts/build-app.sh        # → build/NeatEdit.app
swift test                    # unit + UI tests
swift scripts/make-icon.swift # regenerate Resources/AppIcon.icns
swift test -c release -Xswiftc -enable-testing --filter testLargeFile   # 200 MB load benchmark
```

## Install

```sh
./scripts/install.sh          # → ~/Applications/NeatEdit.app and ~/.local/bin/neatedit
neatedit notes.txt app.log    # open files (a missing file is created empty)
some-command | neatedit -     # open stdin
```

## Layout

- `Sources/EditorCore` — pure logic: line index, cursor position, decoding, status text, navigation, viewer geometry, find queries.
- `Sources/EditorUI` — AppKit: document, tabs, editor view, find bar, large file viewer, menus.
- `Sources/NeatEdit` — `main.swift` only.
