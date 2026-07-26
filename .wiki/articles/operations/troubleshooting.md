---
title: "Troubleshooting — Field Findings and Their Fixes"
created: 2026-07-26
updated: 2026-07-26
category: operations
tags: [troubleshooting, field-findings, libusb, progress, nswindow, cancellation]
status: current
related:
  - usb/libusb-transport
  - protocol/progress-tracking
  - protocol/install-session-flow
  - architecture/concurrency-and-cancellation
  - operations/testing-strategy
  - operations/build-configuration
  - ui/window-and-views
code_refs:
  - Sphaira Connect/USB/USBTransport.swift
  - Sphaira Connect/Features/InstallerModel.swift
  - Sphaira Connect/Core/ProgressTracker.swift
  - Sphaira Connect/Shared/WindowStyleConfigurator.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/ProgressTrackerTests.swift
---

# Troubleshooting

This page collects bugs that actually occurred while building Sphaira Connect — not hypothetical ones. Each case is given as symptom, cause, fix and where it lives in the code. Most of them share the same root: the Switch does not behave like a well-mannered USB device, and two state machines (protocol flow and user interface) run on different threads.

---

## 1. XCI jumps straight to 100 %

**Symptom.** While transferring an XCI, the progress bar shows 100 % within the first second and then sits there for minutes. With NSP files it was inconspicuous or much less pronounced.

**Cause.** Progress was computed as a **high-water mark** over the position requested by the Switch: `max(so far, offset + bytes read)` — which is still how the original flow in `CONTRACT.md` describes it. The assumption behind it is that the peer reads a file from front to back. Sphaira does not do that: it reads header and partition data scattered across the file, with an XCI often near the end of the file on the very first access. A single 64 KB block at offset 17.4 GB sets the high-water mark to 17.4 GB out of 17.5 GB.

**Fix.** `ProgressTracker` now counts only the **bytes actually transferred** and ignores the position completely:

```swift
/// Records a transferred block.
///
/// The position requested by the Switch is deliberately NOT taken into account:
/// it reads header and partition data across the file, often early on near the
/// end. A high-water mark over the highest position would sit at 100 % at once.
mutating func record(chunkSize: Int) {
    guard chunkSize > 0 else { return }
    sentBytes += Int64(chunkSize)
}
```

Because the Switch is allowed to request ranges **more than once**, the sum can exceed the file size. Hence `clampedSent` (`min(sentBytes, totalBytes)`) and a likewise clamped `fraction`. The display therefore rises monotonically to 100 % and never beyond.

**Covered by** `SphairaCoreTests/Tests/SphairaCoreTests/ProgressTrackerTests.swift`, test `lateOffsetDoesNotInflateProgress` — with the real pair of numbers from the failure (17.5 GB total size, 64 KB transferred, `fraction < 0.0001`).

**Rule of thumb.** Progress is what went over the wire — not where the peer happens to be reading. The full calculation is in [[protocol/progress-tracking]].

---

## 2. "Running" stays on screen forever even though everything is transferred

**Symptom.** The last file is through, the log shows "Switch hat die Sitzung beendet.", but the UI stays in the "running" state: Cancel active, Install disabled, bar frozen. Seconds later — or never — the completion message arrived.

**Cause.** `InstallSession.run` tears the transport down via `defer { transport.close() }`. `close()` called `libusb_release_interface`, `libusb_close` and `libusb_exit` synchronously. If the Switch has already dropped the connection on its side — which is exactly what happens at the end of a session — these calls can block. The `defer` runs **before** returning from `run`, so before `continuation.yield(.finished(...))`. Result: the finished transfer only reports in once libusb has torn itself loose.

**Fix.** `close()` clears its own references immediately and pushes the libusb teardown onto a background queue:

```swift
handle = nil
context = nil
interfaceClaimed = false

guard openHandle != nil || openContext != nil else { return }

DispatchQueue.global(qos: .utility).async {
    if let openHandle {
        if wasClaimed {
            _ = libusb_release_interface(openHandle, 0)
        }
        libusb_close(openHandle)
    }
    if let openContext {
        libusb_exit(openContext)
    }
}
```

Nulling out the references **before** dispatching the block is part of the fix: a second `close()` call (from `deinit`, say) must not free anything twice. Since every session gets a fresh `USBTransport` with its own context, the old context outliving it briefly does no harm. Details in [[usb/libusb-transport]].

---

## 3. Packets are suddenly rejected as `badMagic` or `checksumMismatch`

**Symptom.** In the middle of a running transfer the session aborts with a checksum or magic error, even though cable and console are fine. A second attempt fails at a different point.

**Cause.** `libusb_bulk_transfer` writes the amount actually transferred into `transferred` even when it returns `LIBUSB_ERROR_TIMEOUT` (-7). If that value is discarded in the timeout branch, the buffer has already received bytes that nobody counted. From then on the byte stream is shifted by exactly that amount, and the next 24-byte packet is decoded at the wrong position — with the wrong magic or the wrong checksum.

**Fix.** In both directions `transferred` is counted in the timeout branch:

```swift
if code == 0 || code == Self.errorTimeout {
    // Even on a timeout, partial bytes may have arrived.
    received += Int(transferred)
}
```

**Rule of thumb.** `LIBUSB_ERROR_TIMEOUT` means "not finished yet", not "nothing happened".

---

## 4. Access denied instead of a meaningless number

**Symptom.** The Switch is detected (the status pill shows "Switch verbunden"), but starting the transfer produces an error with code `-3`.

**Cause.** `libusb_claim_interface` fails with `LIBUSB_ERROR_ACCESS`. The usual reasons on macOS: the App Sandbox has been switched back on, another process holds the interface (a second installer, the old `usb_install.py`), or the signature does not match the granted entitlements.

**Fix.** The code gets its own error case instead of a bare number — in all three places where it can occur (`claim_interface`, reading, writing):

```swift
if claimResult == Self.errorAccess { throw InstallError.accessDenied }
```

`InstallError.accessDenied` carries a German plain-text message that ends up in the footnote of the action bar and in the log. For the build side of the problem see [[operations/build-configuration]].

---

## 5. The UI hangs when the session ends without a completion message

**Symptom.** Very rare and hard to reproduce: the transfer flow ends without any of the completion events (`finished`, `cancelled`, `failed`) reaching the UI. The state stays on "running".

**Cause.** All feedback travels through an `AsyncStream`. The session writes into it, a `Task { @MainActor }` reads out of it. If the stream ends without a completion event having been written first, the `for await` loop simply falls out of its body — and nobody resets the phase.

**Fix.** A fallback after the loop:

```swift
eventTask = Task { @MainActor [weak self] in
    for await event in stream {
        self?.apply(event)
    }
    // The stream ended without a completion event arriving.
    // Without this fallback the UI would stay stuck on "running"
    // with "Cancel" active even though nothing is happening.
    guard let self, self.isBusy else { return }
    self.progress = nil
    self.phase = .idle
    self.appendLog("Sitzung ohne Abschlussmeldung beendet.")
}
```

The `isBusy` check makes sure the fallback does nothing in the normal case — there the phase is already `.finished`, `.idle` or `.failed`.

**Why a stream at all and not many small tasks?** The comment above `SessionEvent` says it: individual unstructured `Task { @MainActor }` calls guarantee **no ordering**. Progress values and log lines could arrive out of order, and in the worst case the completion event would arrive before the last progress value. The stream is exactly one ordered channel.

For the same reason a separate `DoneCounter` (with an `NSLock`) counts the finished files **on the session thread** before the event is sent off — otherwise the final "x titles transferred" result would depend on the delivery order.

---

## 6. "Nintendo Nintendo Switch" in the connection message

**Symptom.** The log reported `Verbunden: Nintendo Nintendo Switch`.

**Cause.** The message concatenated manufacturer and product. But the console's product string descriptor already contains the manufacturer name — and the same effect occurs with the fallback values in `USBTransport.stringDescriptor` (`"Nintendo"` and `"Nintendo Switch"`).

**Fix.** Use only `product`, with the reasoning in the code so that nobody "fixes" it back:

```swift
case .device(let info):
    deviceSummary = "\(info.product) · \(info.serial)"
    phase = .transferring
    // info.product already contains "Nintendo Switch" — prefixing the
    // manufacturer would produce "Nintendo Nintendo Switch".
    appendLog("Verbunden: \(info.product) (Seriennummer \(info.serial))")
```

`DeviceInfo.manufacturer` is still determined, just not displayed.

---

## 7. The window starts at the wrong size

**Symptom.** At launch the window is far too large — with a lot of empty space below the empty drop zone. The size matched the state at the last quit, typically with a filled queue and an expanded log.

**Cause.** AppKit automatically restores the last saved window frame. Here, though, the window size is a **function of the content** — and at launch the content is always the empty state.

**Fix.** Switch persistence off and fit to the content once, with a delay:

```swift
// At launch AppKit restores the last saved frame — switch persistence
// off and fit to the content once.
window.setFrameAutosaveName("")
window.isRestorable = false
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
    self?.fitWindowToContent()
}
```

The delay is necessary because at the time of `viewDidMoveToWindow` SwiftUI has not yet measured a reliable ideal size. Two neighbouring pitfalls from the same file are described in [[ui/window-and-views]]: with `NSHostingView`, `fittingSize` can silently return zero (hence `intrinsicContentSize` first), and the window origin has to be recomputed against the top left corner, because macOS coordinates start at the bottom left.

---

## 8. Cancellation does not take effect immediately

**Symptom.** "Cancel" is pressed but the transfer keeps running for a moment.

**Explanation, not a bug.** Cancellation is a flag that the USB thread polls — it is not interrupted. It is polled in three places:

| Site | Cadence |
|---|---|
| Wait loop in `open` | every 250 ms (`usleep(250_000)`) |
| Read loop | every 500 ms (read timeout) |
| Write loop | per block, at the latest after 5 s (write timeout) |

The worst case is therefore a stalled write block. That is precisely why the write timeout is **finite**: without it the session would be uncancellable as soon as the console stalls in the middle of a block.

The flag itself is a small class with an `NSLock`, not a model property:

```swift
/// Cancellation flag with atomic access. Read from the session's cancel
/// closure — which must never wait on MainActor state, otherwise the USB
/// thread blocks against the main thread.
fileprivate nonisolated final class CancelFlag: @unchecked Sendable
```

Accessing `@Observable` state from the `cancel` closure would be the classic deadlock: the USB thread waits on the MainActor, the MainActor waits on the UI, which waits on the transfer. See [[architecture/concurrency-and-cancellation]].

---

## 9. Overall progress jumps over a failed file

**Symptom.** If a file was unreadable, the overall bar nevertheless advanced by its full size — the display ran ahead of reality.

**Fix.** `InstallSession.transferFile` returns a boolean, and only a `true` counts:

```swift
// Count only bytes actually transferred, otherwise the overall
// progress jumps over a failed file.
if transferred {
    completedBytes += items[index].byteCount
}
```

Part of the behaviour on a file error is also (see [[protocol/install-session-flow]]): an error packet goes to the Switch, the file is marked `.failed` — and the command loop keeps running. Sphaira then aborts the installation but still sends the quit command, which is answered normally. The session therefore ends in an orderly fashion instead of with an abrupt USB drop.

---

## Quick diagnosis

| Observation | First place to look |
|---|---|
| Progress at 100 % immediately | Case 1 — `ProgressTracker.record` |
| "Running" after the end | Case 2 — synchronous `close()` |
| `badMagic` / `checksumMismatch` mid-run | Case 3 — partial bytes on timeout |
| Error code `-3` | Case 4 — sandbox or a second process |
| UI hangs with no message | Case 5 — fallback in `eventTask` |
| Window too large at launch | Case 7 — frame persistence |
| Cancellation reacts sluggishly | Case 8 — flag cadence, not a bug |
| Bar runs ahead of reality | Case 9 — failed file counted |
