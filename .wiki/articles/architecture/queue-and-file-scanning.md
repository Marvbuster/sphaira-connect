---
title: "Queue and File Scanning — InstallItem, ItemScanner, ByteFormat"
created: 2026-07-26
updated: 2026-07-26
category: architecture
tags: [queue, file-scanning, filemanager, sorting, formatting, core]
status: current
related:
  - architecture/system-overview
  - architecture/concurrency-and-cancellation
  - protocol/install-session-flow
  - protocol/progress-tracking
  - ui/window-and-views
  - operations/testing-strategy
code_refs:
  - Sphaira Connect/Core/InstallItem.swift
  - Sphaira Connect/Core/ByteFormat.swift
  - Sphaira Connect/Features/InstallerModel.swift
---

# Queue and File Scanning

Between "drag a folder onto the app" and "the list that goes to the Switch" sits exactly one
function: `ItemScanner.scan([URL]) -> [InstallItem]`. It resolves folders recursively, filters for
four extensions, discards duplicates, skips everything unreadable **without failing** and sorts
stably in natural language order. It is fed by `DropZoneView` ([[ui/window-and-views]]). The result
is the order in which Sphaira shows the titles on the Switch — so the scanner determines not only
*what* is transferred, but also *what it is called* and *in which order it appears*.

## `InstallItem` — the entry

```swift
nonisolated struct InstallItem: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case queued
        case transferring
        case done
        case failed(String)
    }

    let id: UUID
    let url: URL
    let displayName: String     // File name including extension — goes to the Switch as-is
    let byteCount: Int64
    var state: State
}
```

Four details worth knowing:

- **`displayName` is `url.lastPathComponent`, unfiltered.** Exactly this string ends up in the
  file list the Switch receives ([[protocol/install-session-flow]]). Renaming the file on disk
  therefore means a different name in Sphaira. There is no sanitising of special characters — the
  list goes onto the wire as UTF-8.
- **`id` is a fresh `UUID` per scan.** Two scans of the same file produce two different `id`s;
  identity for SwiftUI lists yes, identity across runs no. Duplicate detection therefore works on
  paths, not on `id`.
- **`state` is the only mutable field.** Everything else is `let`; state transitions come
  exclusively from the session's `onItemState`.
- **`byteCount` comes from the file system at scan time**, not from the transfer. The size that is
  actually reported to the Switch is determined by the session itself via `file.seekToEnd()`. If a
  file changes between being dropped and the start, the *overall progress* is no longer exact —
  the per-file progress still is.

## `ItemScanner.scan` — the pipeline

The order of the steps is deliberate and can be read straight off `scan`:

```swift
for url in urls {
    for fileURL in resolve(url) {
        guard installableExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
        let path = fileURL.standardizedFileURL.path
        guard !seenPaths.contains(path) else { continue }
        guard let byteCount = readableFileSize(of: fileURL) else { continue }
        seenPaths.insert(path)
        items.append(InstallItem(url: fileURL, byteCount: byteCount))
    }
}
```

**1. Resolving.** `resolve(_:)` checks with `fileExists(atPath:isDirectory:)`. If it is neither a
file nor a folder, an empty list comes back — non-existent URLs are not an error. Folders are
walked with `FileManager.enumerator`, using an error handler that deliberately keeps going:

```swift
// errorHandler returns true: skip unreadable subfolders instead of aborting.
errorHandler: { _, _ in true }
```

Without that `true`, a single subfolder without read permission — say inside a network share or a
Time Machine directory — would abort the whole enumeration and silently return half a list. Only
regular files (`isRegularFileKey`) make it into the result; symlinks to folders and bundles are
thereby not dragged along.

**2. Extension filter.** `installableExtensions` is `["nsp", "xci", "nsz", "xcz"]`, compared
against `pathExtension.lowercased()`. So `Bravo.XCI` and `echo.NSP` are recognised — explicitly
covered by the test fixture. A `notes.txt` passed in directly is dropped just like one that was
found by the walk.

**3. Duplicates.** The key is `standardizedFileURL.path`. That is more than a string comparison:
`…/sub/../alpha.nsp` and `…/alpha.nsp` normalise to the same path. Drop the same folder twice, or
a folder *and* a file it contains, and you still get each title once.

**4. Readability and size.** `readableFileSize` checks `isReadableFile(atPath:)` and reads
`fileSizeKey`. If either fails, the entry is skipped — and that happens **before** the path lands
in `seenPaths`. An unreadable file therefore does not block the chance of picking up that same
file later via a different route.

**5. Sorting.**

```swift
// sort(by:) is stable — identical names keep the order in which they were found.
return items.sorted {
    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
}
```

`localizedStandardCompare` is the comparison the Finder uses too: case is ignored and digit runs
are compared numerically — "Part 2" comes before "Part 10", not after it. Together with the
stability of `sorted`, the output is deterministic no matter in which order the file system
enumerates the folders. For the display on the Switch, that is the difference between a sorted list
and chance.

All of these steps are covered in `ItemScannerTests.swift` against a temporary folder fixture —
nested folders, uppercase extensions, non-normalised paths and a file made unreadable via
`chmod 000` ([[operations/testing-strategy]]).

## Interplay with `InstallerModel`

`scan` removes duplicates only **within a single call**. The view model therefore filters a second
time, this time against the queue that already exists:

```swift
func add(urls: [URL]) {
    let existing = Set(items.map { $0.url.standardizedFileURL.path })
    let fresh = ItemScanner.scan(urls).filter {
        !existing.contains($0.url.standardizedFileURL.path)
    }
    guard !fresh.isEmpty else { return }
    items.append(contentsOf: fresh)
    appendLog("\(fresh.count) Datei(en) zur Warteschlange hinzugefügt.")
}
```

Important: **entries added later are appended to the end, not merged into the sort order.** So the
overall list is alphabetical throughout only if it was dropped in one go. That is intentional —
re-sorting would make entries jump out from under the cursor.

`remove(_:)` and `clearAll()` are guarded by `guard !isBusy`: while a transfer is running the list
must not change, because the session works with a copy and indices (`packet.arg3`,
`onItemState(index:)`) would otherwise point nowhere. `add` is deliberately *not* locked — new
files then land in the list but do not belong to the running session.

## `ByteFormat` — formatting without a crash and without a formatter

All size, rate and time values in the UI go through three functions whose top rule is: **never
crash, when in doubt show an en dash.**

```swift
static func rate(_ bytesPerSecond: Double) -> String {
    guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return dash }
    return scaled(bytesPerSecond) + "/s"
}
```

`.nan`, `.infinity` and negative values yield `"–"`. This is not a theoretical case:
`ProgressPanelView` deliberately passes `.nan` in once the transfer is finished
(`ByteFormat.rate(isFinished ? .nan : progress.bytesPerSecond)`) to make the speed disappear, and
`remainingText` does the same for the remaining time as long as no throughput is known. The en dash
is therefore a *used* interface, not an emergency exit.

Scaling is **decimal** (steps of 1000, `B, kB, MB, GB, TB, PB`) — the same counting macOS uses in
the Finder, so that a 17.5 GB XCI is 17.5 GB in the app as well. The formatting is done by hand:

```swift
// German number format with exactly one decimal place, without NumberFormatter
// (it is not thread-safe and the callers are nonisolated).
let tenths = Int((value * 10).rounded())
return "\(tenths / 10),\(tenths % 10) \(units[unitIndex])"
```

The reason is stated in the comment and hangs directly off
[[architecture/concurrency-and-cancellation]]: `ByteFormat` lives in `Core/` and is called from
`nonisolated` contexts; a shared `NumberFormatter` would be a data race there. Below 1000 bytes the
value is printed as an integer (`"512 B"`), above that always with exactly one decimal place and a
comma as the decimal separator (the app's UI language is German).

`duration` returns `m:ss`, and `h:mm:ss` from one hour on; here too the en dash applies for
`.nan`/`.infinity`/negative values. In `ProgressPanelView` it is fed from
`(overallTotal − overallSent) / bytesPerSecond`, that is, from the smoothed throughput of
[[protocol/progress-tracking]].
