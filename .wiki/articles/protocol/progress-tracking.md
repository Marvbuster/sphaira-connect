---
title: "Progress Calculation — Cumulative Counting Instead of a High-Water Mark"
created: 2026-07-26
updated: 2026-07-26
category: protocol
tags: [progress, progresstracker, xci, throughput, throttling, tests]
status: current
related:
  - protocol/install-session-flow
  - protocol/sph0-wire-protocol
  - architecture/system-overview
  - architecture/queue-and-file-scanning
  - ui/window-and-views
  - operations/testing-strategy
  - operations/troubleshooting
code_refs:
  - Sphaira Connect/Core/ProgressTracker.swift
  - Sphaira Connect/USB/InstallSession.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/ProgressTrackerTests.swift
---

# Progress Calculation

`CONTRACT.md` originally prescribed a high-water mark: `max(so far, offset + bytes read)`. That
sounds reasonable and failed immediately in the field — for XCI files the bar sat at 100 % after
the very first block. The reason lies in the protocol: **the Switch reads at random, not
sequentially**, and with XCI it likes to start with header and partition data near the end of the
file. The fix is a dedicated type, `Core/ProgressTracker.swift`, which ignores the requested
*position* entirely and instead **sums the bytes actually transferred**.

## The bug

Sphaira requests blocks via `dataOffset`/`dataSize` ([[protocol/sph0-wire-protocol]]). For a
17.5 GB XCI the very first block can sit at offset ~17.4 GB and be 64 KB in size. With a high-water
mark that would give:

```
max(0, 17_400_000_000 + 65_536) / 17_500_000_000 ≈ 99.4 %
```

— after 64 transferred kilobytes. The rest of the transfer would then run for what feels like
forever against a bar that is already pegged; remaining time and throughput would be equally
meaningless. The test captures the case as regression protection:

```swift
/// The bug that occurred in the field: with an XCI the Switch requests data
/// near the end of the file early on. A high-water mark over the highest
/// position would therefore sit at 100 % immediately.
@Test("Anfragen nahe dem Dateiende treiben den Fortschritt nicht hoch")
func lateOffsetDoesNotInflateProgress() {
    var tracker = ProgressTracker(totalBytes: 17_500_000_000, startNanos: 0)
    tracker.record(chunkSize: 65_536)
    #expect(tracker.fraction < 0.0001)
}
```

## The correction: sum up and clamp

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

/// Transferred bytes, clamped to the file size — the Switch is allowed to
/// request a range more than once.
var clampedSent: Int64 { min(sentBytes, totalBytes) }

var fraction: Double {
    guard totalBytes > 0 else { return 0 }
    return min(1, Double(clampedSent) / Double(totalBytes))
}
```

Cumulative counting has a downside, and that downside is the reason for `clampedSent`: if Sphaira
requests a range twice — which the protocol permits — the tracker counts it twice. `sentBytes`
therefore measures *bus traffic*, not *file coverage*. For display it is clamped to the file size;
`sentBytes` stays visible in its raw form and is thus the more honest value for diagnostics. The
test `duplicateReadsAreClamped` nails exactly this behaviour down: `record(80)` twice with
`totalBytes: 100` yields `sentBytes == 160`, `clampedSent == 100`.

Three further edge cases are deliberately covered:

| Case | Behaviour |
|---|---|
| `chunkSize <= 0` | ignored (empty answer at end of file, see [[protocol/install-session-flow]]) |
| `totalBytes == 0` | `fraction == 0` instead of a division by zero |
| `totalBytes < 0` | raised to 0 in `init` (`max(0, totalBytes)`) |

## Throttling — a 100 ms minimum interval

A 64 KB block at 20 MB/s means a good 300 requests per second. Writing every one of them into an
`@Observable` property would mean 300 SwiftUI updates per second — the main thread would be busy
drawing progress bars while the transfer waits on it. `tick(now:force:)` is the brake:

```swift
mutating func tick(now: UInt64, force: Bool = false) -> Bool {
    let elapsedNanos = now &- lastEmitNanos
    guard force || elapsedNanos >= Self.emitIntervalNanos else { return false }

    if elapsedNanos > 0 {
        let sample = Double(sentBytes - lastEmitBytes) / (Double(elapsedNanos) / 1e9)
        bytesPerSecond = bytesPerSecond == 0
            ? sample
            : bytesPerSecond * (1 - Self.rateSmoothing) + sample * Self.rateSmoothing
    }

    lastEmitNanos = now
    lastEmitBytes = sentBytes
    return true
}
```

`emitIntervalNanos = 100_000_000` caps UI updates at ten per second. The return value is the only
control: only if `tick` returns `true` does `InstallSession` build a `TransferProgress` at all and
push it through the event channel.

Worth noting is `now &- lastEmitNanos` — wrapping subtraction instead of `-`.
`DispatchTime.now().uptimeNanoseconds` is monotonic, but the `&-` variant keeps the arithmetic
crash-proof even if a caller passes in a timestamp smaller than the one recorded last time.

## Throughput smoothing

The raw value of a 100 ms window jumps around a lot, because Sphaira itself writes and computes
checksums between blocks. An exponentially smoothed average with `rateSmoothing = 0.2` (20 % new
sample, 80 % history) makes the display readable without making it sluggish.

The special case `bytesPerSecond == 0 ? sample : …` matters: without it, every file would start at
0 B/s and need a good many windows to reach the real value. This way the first sample counts fully
and all later ones are smoothed. Two tests cover both directions — `rateReflectsThroughput` (1 MB
in 100 ms ⇒ exactly 10 MB/s for the first window) and `rateIsSmoothed` (a doubled throughput in the
second window must not jump straight to the new value).

If the transfer stalls, the value decays automatically because `sample` is then 0
(`rateDecaysWhenStalled`). That is exactly what the remaining-time display needs so that it does
not freeze at an old, optimistic value when the connection hangs.

## Why the timestamp is passed in

```swift
/// Deliberately without a time or USB dependency: the timestamp is passed in
/// so that the behaviour can be verified deterministically.
init(totalBytes: Int64, startNanos: UInt64)
mutating func tick(now: UInt64, force: Bool = false) -> Bool
```

If the tracker called `DispatchTime.now()` itself, throttling and throughput calculation could only
be tested with `sleep` — slow, and unreliable on loaded CI machines. As it is, the test simply
writes `tick(now: 100 * ms)` and expects exact numbers ([[operations/testing-strategy]]). The only
place where real time enters the picture is in `InstallSession`:

```swift
var tracker = ProgressTracker(
    totalBytes: Int64(size),
    startNanos: DispatchTime.now().uptimeNanoseconds
)
```

`DispatchTime` and not `Date`: a clock change or an NTP correction must not drag the throughput into
absurdity.

## Embedding in the session

The tracker is **per file** — it is created in `transferFile` and lives only for that one transfer.
The overall progress only comes into being when the event is built:

```swift
func emitProgress(force: Bool, sentOverride: Int64? = nil) {
    guard tracker.tick(now: DispatchTime.now().uptimeNanoseconds, force: force) else { return }
    let sent = sentOverride ?? tracker.clampedSent
    onProgress(TransferProgress(
        itemIndex: index,
        itemName: item.displayName,
        itemSent: sent,
        itemTotal: Int64(size),
        overallSent: completedBytes + sent,
        overallTotal: overallTotal,
        bytesPerSecond: tracker.bytesPerSecond
    ))
}
```

`completedBytes` are the bytes of files already **completed** (only successful ones count, see
[[protocol/install-session-flow]]), `overallTotal` is the sum of all `byteCount` values from the
scan ([[architecture/queue-and-file-scanning]]). At the end of a file there is an
`emitProgress(force: true)` that bypasses the throttling — otherwise a file's last message could be
swallowed and the bar would stop just short of 100 %.

`sentOverride` exists because `clampedSent` alone isn't enough once `completionTolerance` is in the
picture ([[operations/troubleshooting]], case 10): a file that succeeded within the tolerance still
has `sentBytes` a few bytes short of `size`, and that final (`force: true`) snapshot is never
superseded by a later update if it happens to be the *last* file in a batch. Passing `Int64(size)`
as the override once the file is known to have succeeded is what keeps `overallSent` reaching
`overallTotal` — and with it `ProgressPanelView.isComplete` — accurate for the whole session, not
just for the individual file's `.done`/`.skipped` state.

`ProgressPanelView` ([[ui/window-and-views]]) takes it from there: two bars (overall and current
file), both clamped to 1 and pinned to 1 when `isFinished`, plus the remaining time as
`(overallTotal − overallSent) / bytesPerSecond`. If the throughput is 0 or the transfer is done,
`.nan` is deliberately handed to `ByteFormat.duration` and turns into an en dash — see
[[architecture/queue-and-file-scanning]].

## One known loose end

`itemTotal` comes from `seekToEnd()` on the opened file, whereas `overallTotal` comes from the
`byteCount` values recorded during the scan. If a file changes between being dropped and being
transferred, the per-file bar still fits but the overall bar is no longer exact. The case is rare
and, thanks to the clamping to ≤ 100 %, harmless in the display — deliberately not abstracted away.
