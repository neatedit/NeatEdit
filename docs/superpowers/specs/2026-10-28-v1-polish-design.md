# v1 polish: external changes, status bar menus, line numbers, font

Date: 2026-10-28

## Why

SimpleTextEdit works well for its author; these are the gaps other people would
hit in the first five minutes. The biggest one: a file changed on disk (git pull,
another editor, a log being written) silently diverges from the open tab.

Already shipped, not part of this work: Go to Line (⌘L, `line` or `line:col`),
Bigger / Smaller / Actual Size (⌘+ ⌘− ⌘0), Wrap Lines toggle (⌥⌘W).

## Goals

1. Files changed on disk are picked up, and conflicting edits can be merged hunk by hunk.
2. Clicking the encoding in the status bar re-reads the file in another encoding.
3. Clicking the line ending in the status bar converts line endings.
4. Optional line number gutter.
5. Font family can be chosen.

## Non-goals

- Diff/merge for the large file viewer (read-only, nothing to merge).
- Character-level diff, side-by-side diff editor, syntax highlighting.
- `tail -f` follow mode (later; the silent reload below is the groundwork).

## Anti-goals

- Losing the user's unsaved text in any branch of the external-change flow.
- Modal dialogs popping up on their own while the user is typing.
- Making normal typing or opening big (up to 20 MB) documents noticeably slower.

## 1. File changed on disk

### Tab has no unsaved edits
Reload silently. Caret and scroll position stay where they were (clamped if the
file got shorter). No dialog, no banner.

### Tab has unsaved edits
- A banner appears at the top of the tab (same slot style as the find bar):
  "File changed on disk" with **Review Changes** and **Dismiss**.
  Not a modal; it waits until the user acts.
- **The diff is base → disk**, where *base* is the text as it was last loaded or
  saved. So it shows only what changed outside, never the user's own edits.
- Changes are listed as hunks (line-based). Each hunk can be **accepted**
  (applied into the user's text at the corresponding place) or **skipped**.
- A hunk whose base line range overlaps lines the user also changed
  (base → buffer) is a **conflict**. Its choices are **take disk** or **keep mine**.
- After review the tab is still unsaved (dirty) and the disk version becomes the
  new base, so a later external change is diffed against it.
- **Dismiss** keeps the user's text unchanged and also makes the disk version the
  new base (so the banner doesn't come back for the same change). Saving then
  overwrites disk with the user's text, without NSDocument's "changed by another
  application" alert — the user has already seen and decided.
- **Big diff**: when the change is too large to review piece by piece — more than
  half of the base lines changed, or the file was effectively rewritten — the
  banner offers **Save My Version As…** instead of Review. On save, the user's
  text goes to the new file (standard save panel, suggested name
  `<name> (my version).<ext>` next to the original) and the tab switches to the
  disk version. Cancelling the save panel changes nothing.

### Saving while the banner is up (user's decision)
⌘S does not save while an external change is unresolved. It opens the review
instead (or, for a big diff, **Save My Version As…**). Outside changes are never
overwritten unseen. Autosave must not overwrite the disk version either while
the banner is up.

### Review details
- Decisions are collected in the review and applied together with **Apply**, as
  one undo step. Closing the review without Apply changes nothing and the banner
  stays. Undecided hunks at Apply time count as skipped (keeps the user's text).
- If the file changes again while the banner or review is up, re-diff against the
  same base and refresh the list; decisions on hunks that are unchanged are kept.
  Diffing is cancelled/restarted, never queued.
- The disk version is decoded with the tab's current encoding first, falling back
  to auto-detection. Line endings are normalized before diffing, so a pure
  CRLF↔LF change is not "every line changed". After Apply, the tab keeps its own
  encoding and line ending.
- Silent reload (clean tab) follows the disk version's encoding and line ending,
  and is one undoable step rather than clearing the undo stack.

### File deleted or moved away
The tab keeps its text and shows a "Deleted from disk" banner (edited or not; it
is informational, no modal). Saving recreates the file at the original path. If
the file reappears at the same path (git checkout, delete-then-write saves), it is
treated as an ordinary change against base. If NSDocument tracks a move/rename,
it follows the new path as it does today.

### Large file viewer (> 20 MB)
Read-only, so always reload silently, keeping the scroll position.

## 2. Status bar: encoding menu

The encoding part of the status bar becomes clickable and opens a menu:

- **Reopen with Encoding** (top, the main use: file opened as mojibake):
  UTF-8, UTF-16 LE, UTF-16 BE, Windows-1251, KOI8-U, KOI8-R, ISO-8859-1,
  Windows-1252, Mac Roman. Re-decodes the file bytes from disk. If the tab has
  unsaved edits, a confirmation says they will be lost. If the bytes don't decode
  in the chosen encoding, show an error and keep the current text.
  Untitled tabs (no file on disk) don't have this section.
- **Save with Encoding**: same list; changes the encoding used on the next save
  (marks the document dirty). If the text can't be represented, warn before
  switching and keep the old encoding.
- The current encoding is checkmarked.

## 3. Status bar: line ending menu

Clicking LF / CRLF / CR opens a menu with the three options; choosing one
converts the whole text and marks the document dirty. One ⌘Z undoes it.

## 4. Line numbers

- View ▸ Show Line Numbers toggles a gutter on the left. **Off by default.**
- With wrapping on, only the first visual line of each logical line is numbered.
- Must stay fast on documents up to the 20 MB threshold: only visible lines are
  drawn, numbers come from the existing `LineIndex`, no full-document work on
  scroll or typing.
- Gutter uses the editor font at a smaller size and secondary label color, and
  widens as the line count gains digits.
- The large file viewer: out of scope (it has its own view).

## 5. Font

- View ▸ Font… (no shortcut — ⌘T is New Tab) opens the standard font panel,
  limited to fixed-pitch families (the large file viewer's horizontal layout
  assumes a monospaced font).
  Only family/face is taken from it; the size stays driven by ⌘+ / ⌘− / ⌘0
  (picking a size in the panel also sets the size preference).
- Default stays the system monospaced font (SF Mono) at 13 pt. Actual Size resets
  the size only, not the family.
- Applies to all tabs and both the editor and the large file viewer; remembered
  across launches (UserDefaults, like the existing size).

## 6. Defaults

- Wrap Lines: **off** by default (was on). Users who already toggled it keep
  their stored value.
- Line numbers: off by default.

## Constraints

- Swift + AppKit, no dependencies. Logic that can be pure goes in `EditorCore`
  with unit tests first (TDD): line diff, hunk classification (clean vs.
  conflict), applying accepted hunks to the buffer, big-diff detection,
  line-ending conversion. UI wiring gets integration tests like
  `DocumentIntegrationTests`.
- Keeping the base text costs one extra copy of the document in memory; fine for
  documents under the 20 MB threshold.
- Diffing runs off the main thread for large documents so the app doesn't hang
  when a big file changes.

## Left to the builder

- Diff algorithm (Myers or similar, line-based) and how hunks map onto the buffer.
- Exact layout of the review UI (list of hunks with Accept / Skip, or similar),
  as long as each hunk can be decided individually and conflicts are marked.
- How the change is detected (NSFilePresenter via NSDocument is expected) and
  how NSDocument's built-in conflict alert is suppressed.
- Gutter implementation (NSRulerView or custom).

## Calls made (not discussed with the user)

- Banner, not modal, for the edited-tab case.
- Dismiss makes disk the new base; next save overwrites without NSDocument's alert.
- Big-diff threshold: more than half of base lines changed.
- Suggested name for the saved copy: `<name> (my version).<ext>`.
- Deleted file: keep text, saving recreates it.
- Encoding list contents; "Save with Encoding" as a secondary section.
- Font panel only picks the family; size stays on ⌘+ / ⌘−.
- Font… has no shortcut; monospaced families only.
- Review applies all decisions at once as one undo step; closing without Apply
  keeps the banner; undecided hunks count as skipped.
- A second external change during review re-diffs and keeps unchanged decisions.
- Disk version decoded in the tab's encoding first; line endings normalized
  before diffing.
- Silent reload is undoable and follows the disk encoding/line ending.
- Deleted file shows an informational banner even for clean tabs; a reappearing
  file is an ordinary change.
