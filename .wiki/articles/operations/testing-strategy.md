---
title: "Testing Strategy — SwiftPM Package with a Symlink to Core"
created: 2026-07-26
updated: 2026-07-26
category: operations
tags: [tests, swift-testing, swiftpm, symlink, ci]
status: current
related:
  - operations/build-configuration
  - operations/troubleshooting
  - protocol/sph0-wire-protocol
  - protocol/progress-tracking
  - architecture/queue-and-file-scanning
code_refs:
  - SphairaCoreTests/Package.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/CRC32CTests.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/PacketTests.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/ItemScannerTests.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/ByteFormatTests.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/ProgressTrackerTests.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/InstallErrorTests.swift
---

# Testing Strategy

Only `Sphaira Connect/Core/` is tested — checksum, wire format, file scanning, number formatting, progress calculation, error texts. That does not happen in an Xcode test target but in a standalone SwiftPM package next to it, whose source folder is a **symlink** to the Core files of the Xcode project. This means there is no second copy of the files, no Xcode is needed to run the tests, and a `swift test` completes in a few seconds.

## Layout

```
SphairaCoreTests/
├── Package.swift
├── Sources/
│   └── SphairaCore -> ../../Sphaira Connect/Core   (symlink)
└── Tests/
    └── SphairaCoreTests/
        ├── ByteFormatTests.swift
        ├── CRC32CTests.swift
        ├── InstallErrorTests.swift
        ├── ItemScannerTests.swift
        ├── PacketTests.swift
        └── ProgressTrackerTests.swift
```

```swift
// swift-tools-version: 6.0
import PackageDescription

// Standalone test package: pulls in the Core sources of the Xcode project
// via a symlink, so that there is no second copy of the files.
let package = Package(
    name: "SphairaCoreTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SphairaCore",
            path: "Sources/SphairaCore"
        ),
        .testTarget(
            name: "SphairaCoreTests",
            dependencies: ["SphairaCore"],
            path: "Tests/SphairaCoreTests"
        ),
    ]
)
```

Run it with:

```bash
cd SphairaCoreTests && swift test
```

## Why a symlink and not an Xcode test target

Four reasons, in this order:

1. **No second copy of the files.** A copied `CRC32C.swift` in the test package would silently drift apart from the app version at the next fix — the tests would then be green against code that nobody runs.
2. **The project file stays untouched.** An Xcode test target would need an entry in `project.pbxproj`; that is exactly what the file-system-synchronized group forbids (see [[operations/build-configuration]]).
3. **No Xcode required.** `swift test` needs only the toolchain, no `.xcodeproj`, no simulators, no scheme. That makes the test run scriptable and CI-friendly.
4. **No libusb.** The package links nothing, because by contract `Core/` may know neither SwiftUI nor USB. That very restriction is what makes the construction possible in the first place — it is architectural rule and test prerequisite in one.

Two differences from the app environment are accepted deliberately:

- **Platform declaration `.macOS(.v14)`** instead of 26.5. Core uses only `Foundation`, so the package also runs on older systems and with older toolchains.
- **No `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** In the app every type is bound to the main thread by default, in the package it is not. That the tests nevertheless check the same behaviour as the app is due to the Core types being almost all declared explicitly `nonisolated` — `nonisolated enum CRC32C`, `nonisolated struct Packet`, `nonisolated enum ItemScanner`, `nonisolated enum ByteFormat`, `nonisolated enum InstallError`. The only exception is `struct ProgressTracker` (without `nonisolated`); in the app it is therefore MainActor-isolated, which in the Swift 5 language mode produces only a warning when it is called from the session ([[architecture/concurrency-and-cancellation]]). So the annotations are not only there for the USB thread, they also keep the two compilation environments congruent.

The price of the symlink: it has to survive in the repository. Anyone who copies the folder instead of cloning it, or unpacks the archive with a tool that resolves symlinks, ends up with a silent copy — with exactly the problem point 1 was meant to avoid.

## Tooling

Swift Testing instead of XCTest: `import Testing`, `@Suite("…")`, `@Test("…")`, `#expect(…)`. For error cases `#expect(throws: InstallError.badMagic) { … }`, which checks the equality of the thrown value — possible because `InstallError: Equatable`. The test names are German sentences, so that the output of a failing run is understandable without looking at the source.

## The six suites

| Suite | Focus |
|---|---|
| `CRC32C` | Reference values, comparison against a second implementation |
| `Packet` | Wire format byte by byte, round trip, error cases |
| `ItemScanner` | A real folder tree in the temporary directory |
| `ByteFormat` | Boundary values and German formatting |
| `ProgressTracker` | Progress calculation including the regression case |
| `InstallError` | Completeness and content of the plain-text messages |

### CRC32C

At its core is an **independent second implementation** in the test code:

```swift
/// Independent bitwise reference implementation (without a table), so that the
/// table-driven production variant is checked against a second source.
private func referenceCRC32C(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (crc >> 1) ^ 0x82F6_3B78 : crc >> 1
        }
    }
    return ~crc
}
```

This checks not only against fixed expected values but against a second derivation of the same specification — all 256 individual bytes, several strings, a 1 MiB buffer with a deterministic xorshift pattern and random buffers of various lengths. Plus the values mandated by the contract (`checksum([])` = 0, `checksum("123456789")` = `0xE3069283`) and four vectors from RFC 3720.

Two further cases lock down properties that are easily lost: an `ArraySlice` must produce the same result as an `Array` (the signature is generic over `Collection`), and flipping any single bit must change the checksum.

### Packet

The byte layout is not checked via a round trip — that would be green even with a consistently wrong byte order — but **verified position by position**:

```swift
// magic 0x53504830 → LE: 30 48 50 53
#expect(Array(bytes[0..<4]) == [0x30, 0x48, 0x50, 0x53])
// arg2 0x01020304 → LE: 04 03 02 01
#expect(Array(bytes[4..<8]) == [0x04, 0x03, 0x02, 0x01])
```

What is being checked here is described in [[protocol/sph0-wire-protocol]]. Beyond that: 200 random packets through a round trip, boundary values (`0`, `1`, `0x7FFFFFFF`, `0x80000000`, `.max`), a `dataOffset` beyond the 4 GB boundary (the case that occurs with every XCI), and every individually flipped byte must throw — `badMagic` within the first four bytes, `checksumMismatch` after that.

Two subtleties deserve mention because they cover real risks of confusion:

- **A wrong magic with a correctly recomputed CRC** must still yield `badMagic`. Otherwise the magic check would effectively be superseded by the CRC check.
- **Length is checked before magic.** `Packet.decode([0xFF, 0xFF, 0xFF, 0xFF])` is too short *and* has the wrong magic; what is expected is `shortPacket(expected: 24, got: 4)`. Without this test the order would be accidental — and a `shortPacket` message is far more helpful when hunting a bug.

### ItemScanner

The only test that touches a real file system. `withFixture` creates a tree with nested folders under `NSTemporaryDirectory()` and clears it away again via `defer`. It contains extensions in both upper and lower case (`Bravo.XCI`, `echo.NSP`), non-installable files (`.txt`, `.md`, `.zip`) and a file with no extension at all.

The rules being checked are laid out in [[architecture/queue-and-file-scanning]]. Covered are recursion, the extension filter, stable alphabetical ordering independent of the order the URLs were passed in, correct `byteCount` values and de-duplication — including for non-normalised paths:

```swift
let unnormalized = root.appendingPathComponent("sub/../alpha.nsp")
let items = ItemScanner.scan([root, file, unnormalized, root])
#expect(items.count == 5)
```

The most interesting case is the unreadable entry: a file is given `posixPermissions: 0o000` and must be **skipped** rather than making the whole scan fail. That matters more than it sounds — otherwise a single unreadable title inside a large folder would prevent adding anything at all. `defer` restores the permissions so that the cleanup succeeds.

### ByteFormat

Pure table checking, but with two assertions: the scaling is **decimal** (1000 bytes = "1,0 kB", 1024 bytes also "1,0 kB") and the formatting is German (comma as the decimal separator). `Int64.max` must end up in "PB" instead of overflowing. Invalid inputs — negative, `.nan`, `±.infinity` — consistently yield the en dash `–` and never a crash. That is what the contract prescribes, and the UI relies on it: `ProgressPanelView` deliberately passes `.nan` in once a transfer has finished, in order to display "–".

### ProgressTracker

This suite carries a real field finding as a regression test — with the rationale right in the test code:

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

The full story is in [[operations/troubleshooting]], the arithmetic behind it in [[protocol/progress-tracking]]. Further cases: summation independent of order, clamping for ranges requested more than once (`sentBytes == 160`, but `clampedSent == 100`), empty and negative blocks having no effect, an empty file without a division by zero, a negative total size raised to zero.

The timing side is testable because `ProgressTracker` gets its time **passed in** instead of fetching it itself — the doc comment names that explicitly as a design goal. That makes it possible to check the throttling exactly (`tick(now: 99 ms) == false`, `tick(now: 100 ms) == true`), likewise `force`, the throughput (1 MB in 100 ms gives exactly 10 MB/s), the smoothing (the second value rises but does not jump to the new sample) and the decay when the transfer stalls.

### InstallError

Checks that **every** one of the nine cases yields a non-empty German plain-text message, that associated values appear in it (operation name, error code, expected and received length, command number, file path) and that `Equatable` distinguishes both cases and associated values. The last point is not a formality: the `#expect(throws:)` checks of the Packet suite depend on it.

## What is not tested

Deliberate gaps, so that nobody mistakes them for oversights:

| Area | Reason |
|---|---|
| `USB/USBTransport.swift` | Needs real hardware; libusb cannot be usefully mocked |
| `USB/InstallSession.swift` | Depends on the transport; the flow is verified against the real Switch |
| `Features/` and `Features/Views/` | Views and view model, MainActor-bound, outside the package |

The consequence: anything changed in the protocol flow or the USB layer has to be reproduced on real hardware. The cases that have already come up are collected in [[operations/troubleshooting]].
