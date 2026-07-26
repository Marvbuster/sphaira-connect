# Sphaira Connect — Binding Interface Contract

> This document was the original build specification and describes the module
> boundaries. The continuously maintained description of the system lives in `.wiki/`.

Every module is built against **exactly** these signatures. No deviation, no renaming,
no additional required parameters. Anything you find missing is added **additively**
(a new method), without changing what already exists.

## Ground rules (non-negotiable)

- Target: **macOS 26.5**, Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
  → Every type is `@MainActor` by default. Anything that touches USB or blocks
  **must** be explicitly `nonisolated`, or `final class ... : @unchecked Sendable`.
- The App Sandbox is **off**, Hardened Runtime is on. libusb is statically linked and a
  bridging header is in place — `libusb_*` is globally visible without an `import`.
- Sources live under `Sphaira Connect/` and are compiled automatically via
  `PBXFileSystemSynchronizedRootGroup`. **Do not touch the project file.**
- Comments and identifiers in **English**. User-facing strings stay **German** —
  they double as the keys in `Localizable.xcstrings`, whose source language is
  German; English ships as a translation.
- No file longer than 400 lines.

## Folder layout

| Folder | Contents |
|---|---|
| `Sphaira Connect/Core/` | Pure logic, no SwiftUI and no USB dependency |
| `Sphaira Connect/USB/` | libusb binding and protocol state machine |
| `Sphaira Connect/Shared/` | Design system |
| `Sphaira Connect/Features/` | View model |
| `Sphaira Connect/Features/Views/` | SwiftUI views |

---

## 1. Core — `Sphaira Connect/Core/`

### CRC32C.swift
```swift
enum CRC32C {
    static func checksum<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8
}
```
Castagnoli, reflected polynomial `0x82F63B78`, seed `0xFFFFFFFF`, final inversion.
Reference values for tests: `checksum([])` = `0`, `checksum("123456789".utf8)` = `0xE3069283`.

### SphairaProtocol.swift
```swift
enum SphairaCommand: UInt32 { case quit = 0, open = 1 }
enum SphairaResult: UInt32 { case ok = 0, error = 1 }

enum TransferFlags {
    static let none: UInt32 = 0
    static let stream: UInt32 = 1 << 0
}

struct Packet: Equatable, Sendable {
    static let magic: UInt32 = 0x5350_4830
    static let byteCount: Int = 24

    var arg2: UInt32
    var arg3: UInt32
    var arg4: UInt32
    var arg5: UInt32

    init(arg2: UInt32 = 0, arg3: UInt32 = 0, arg4: UInt32 = 0, arg5: UInt32 = 0)

    func encoded() -> [UInt8]
    static func decode(_ bytes: [UInt8]) throws -> Packet

    var command: UInt32 { get }      // == arg2
    var dataOffset: UInt64 { get }   // UInt64(arg2) << 32 | UInt64(arg3)
    var dataSize: UInt32 { get }     // == arg4
}
```
Wire format: six little-endian `UInt32` values — `magic, arg2, arg3, arg4, arg5, crc32c`.
The CRC32C covers the **first 20 bytes**. `decode` throws on a wrong magic
(`InstallError.badMagic`), a wrong length (`.shortPacket`) and a checksum error
(`.checksumMismatch`).

### InstallError.swift
```swift
enum InstallError: LocalizedError, Equatable {
    case switchNotFound
    case accessDenied
    case usb(operation: String, code: Int32)
    case shortPacket(expected: Int, got: Int)
    case badMagic
    case checksumMismatch
    case unexpectedCommand(UInt32)
    case fileUnreadable(path: String, reason: String)
    case cancelled

    var errorDescription: String? { get }   // plain German text
}
```

### InstallItem.swift
```swift
struct InstallItem: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case queued
        case transferring
        case done
        case skipped(String)   // the Switch closed the file after only a few bytes
        case failed(String)
    }

    let id: UUID
    let url: URL
    let displayName: String     // file name including extension — sent to the Switch as is
    let byteCount: Int64
    var state: State

    init(url: URL, byteCount: Int64)
}

enum ItemScanner {
    static let installableExtensions: Set<String>   // ["nsp", "xci", "nsz", "xcz"]

    /// Folders are resolved recursively, duplicates (same path) are dropped and
    /// non-installable extensions are ignored. Order: stable alphabetical.
    static func scan(_ urls: [URL]) -> [InstallItem]
}
```

### ByteFormat.swift
```swift
enum ByteFormat {
    static func size(_ bytes: Int64) -> String            // "1,4 GB"
    static func rate(_ bytesPerSecond: Double) -> String  // "23,1 MB/s"
    static func duration(_ seconds: Double) -> String     // "2:05" or "–"
}
```
Non-finite or negative input yields `"–"`, never a crash.
The decimal separator follows the selected language, so expectations in tests must
not hard-code it.

### ProgressTracker.swift
```swift
struct ProgressTracker {
    static let emitIntervalNanos: UInt64   // 100_000_000
    static let rateSmoothing: Double       // 0.2

    let totalBytes: Int64
    private(set) var sentBytes: Int64
    private(set) var bytesPerSecond: Double

    init(totalBytes: Int64, startNanos: UInt64)

    mutating func record(chunkSize: Int)
    mutating func tick(now: UInt64, force: Bool = false) -> Bool

    var clampedSent: Int64 { get }
    var fraction: Double { get }
}
```
Added after the fact: the first implementation counted the highest **requested**
offset, which pegged the bar at 100 % within seconds on an XCI. Progress is the
**sum of transferred chunks**, clamped to the file size, because the Switch may
request the same range more than once. The timestamp is passed in rather than read
from a clock, which is what makes the throughput smoothing deterministically
testable.

---

## 2. USB — `Sphaira Connect/USB/`

`LibUSBProbe.swift` already exists and stays unchanged.

### USBTransport.swift
```swift
final class USBTransport: @unchecked Sendable {
    struct DeviceInfo: Sendable {
        let manufacturer: String
        let product: String
        let serial: String
    }

    nonisolated init()

    nonisolated static func isSwitchAttached() -> Bool

    /// Blocks until the Switch shows up. `cancel` is polled regularly.
    nonisolated func open(cancel: () -> Bool) throws -> DeviceInfo
    nonisolated func close()

    nonisolated func readPacket(cancel: () -> Bool) throws -> Packet
    nonisolated func send(_ result: SphairaResult, arg3: UInt32, arg4: UInt32, cancel: () -> Bool) throws
    nonisolated func sendFileInfo(size: UInt64, flags: UInt32, cancel: () -> Bool) throws
    nonisolated func write(_ bytes: [UInt8], cancel: () -> Bool) throws
}
```
Reads run in a loop with a 500 ms timeout so that `cancel` takes effect;
`LIBUSB_ERROR_TIMEOUT` is not an error. `LIBUSB_ERROR_ACCESS` (-3) throws
`.accessDenied`. Endpoints are taken from the active configuration, falling back to
`0x81` (IN) and `0x01` (OUT).

### InstallSession.swift
```swift
struct TransferProgress: Equatable, Sendable {
    var itemIndex: Int
    var itemName: String
    var itemSent: Int64
    var itemTotal: Int64
    var overallSent: Int64
    var overallTotal: Int64
    var bytesPerSecond: Double
}

final class InstallSession: @unchecked Sendable {
    nonisolated init(items: [InstallItem], transport: USBTransport)

    nonisolated func run(
        onLog: @Sendable @escaping (String) -> Void,
        onDevice: @Sendable @escaping (USBTransport.DeviceInfo) -> Void,
        onProgress: @Sendable @escaping (TransferProgress) -> Void,
        onItemState: @Sendable @escaping (Int, InstallItem.State) -> Void,
        cancel: @Sendable @escaping () -> Bool
    ) throws
}
```

**Sequence — exactly like this, otherwise the Switch hangs:**
1. `transport.open` → `onDevice`
2. Build the file list: for every entry `displayName` + `"\n"`, UTF-8
3. Read **one** packet (`readPacket`) — its contents are discarded, only the magic matters
4. `send(.ok, arg3: UInt32(tableBytes.count), arg4: 0)`, then `write(tableBytes)`
5. Loop: `readPacket`
   - `command == 0` (quit) → `send(.ok, 0, 0)`, leave the loop, done
   - `command == 1` (open) → transfer the file at index `packet.arg3`
   - otherwise → `send(.error, 0, 0)` and throw `InstallError.unexpectedCommand`
6. Transferring a file:
   - open the file, determine its size, `sendFileInfo(size:flags: TransferFlags.none)`
   - loop: `readPacket` → `dataOffset`/`dataSize`
     - both `0` → `send(.ok, 0, 0)`, file complete
     - otherwise: seek to the offset, read `dataSize` bytes,
       `send(.ok, arg3: UInt32(bytesRead), arg4: CRC32C.checksum(bytesRead))`,
       then `write(data)`
   - Progress: the sum of the bytes actually sent, clamped to the file size — NOT the
     highest requested position (see ProgressTracker); `onProgress` at most every 100 ms

`onItemState` reports `.transferring` when a file starts and `.done` when it finishes.
Cancellation throws `InstallError.cancelled`. `close()` belongs in a `defer`.

---

## 3. Design system — `Sphaira Connect/Shared/`

The stylistic template is NovaTimePuncher under `<workspace>/NovaTimePuncher/NovaTimePuncher/Shared/`.
What is adopted is the approach, **not** the subject matter.

### DesignTokens.swift
```swift
enum Spacing { static let xs, sm, md, lg, xl, xxl: CGFloat }   // 4, 8, 12, 16, 24, 32
enum Fonts { static let title, subtitle, mono, helper, badge: Font }
enum Colors {
    static let backgroundTint: Color        // calm blue, idle state
    static let backgroundTintActive: Color  // greenish, during a transfer
    static let backgroundTintError: Color   // reddish, on errors
    static let accent, success, warning, danger: Color
}
extension Color { init(hex: UInt32, alpha: Double = 1.0) }
```

### GlassEffectTheme.swift
```swift
struct GlassBackground: View { var cornerRadius: CGFloat; var tint: Color }
struct VisualEffectBlur: NSViewRepresentable    // .behindWindow, .underWindowBackground, .active
extension View { func connectCard(radius: CGFloat = 14, tint: Color = Colors.backgroundTint) -> some View }
```
**Important:** glass must not be nested inside glass. `connectCard` provides the
grouping without the glass effect, for areas that contain glass elements themselves.

### GlassInteractive.swift
```swift
extension View { func glassInteractive(radius: CGFloat = 14) -> some View }
```

### GlassButton.swift
```swift
enum GlassButtonKind { case clear, green, red, orange }
enum GlassButtonSize { case compact, standard }

struct GlassButton: View {
    init(_ title: String,
         systemImage: String? = nil,
         kind: GlassButtonKind = .clear,
         cornerRadius: CGFloat = 14,
         size: GlassButtonSize = .compact,
         isEnabled: Bool = true,
         action: @escaping () -> Void)
}
```
Implemented via `.glassEffect(Glass.regular.tint(...).interactive(), in: .rect(cornerRadius:))`.

### WindowStyleConfigurator.swift
```swift
struct WindowStyleConfigurator: NSViewRepresentable { var sizeKey: AnyHashable }
```
Transparent title bar, `fullSizeContentView`, draggable by its background, the window
resizes to its content with an animation. The traffic-light buttons stay visible.

---

## 4. View model — `Sphaira Connect/Features/InstallerModel.swift`

```swift
@Observable
final class InstallerModel {
    enum Phase: Equatable {
        case idle
        case waitingForSwitch
        case transferring
        case finished(transferred: Int)
        case failed(String)
    }

    struct LogLine: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let text: String
    }

    var items: [InstallItem]
    var phase: Phase
    var progress: TransferProgress?
    var log: [LogLine]
    var switchAttached: Bool
    var deviceSummary: String?
    var isLogExpanded: Bool

    var totalBytes: Int64 { get }
    var canStart: Bool { get }        // items present and no transfer running
    var isBusy: Bool { get }

    func add(urls: [URL])
    func remove(_ item: InstallItem)
    func clearAll()
    func start()
    func cancel()
    func startMonitoring()            // polls `USBTransport.isSwitchAttached()` every 2 s
    func stopMonitoring()
}
```
`start()` launches the session via `Task.detached` so the main thread stays free; all
feedback is routed back through `Task { @MainActor in ... }`.
`cancel()` sets a cancellation flag that the session polls.
The protocol must **not** run on the MainActor.

---

## 5. Views — `Sphaira Connect/Features/Views/`

- `RootView.swift` — `ZStack`: `VisualEffectBlur`, state colour, content,
  `WindowStyleConfigurator`. Header with title and status indicator, below it the drop
  area or the queue, at the bottom progress and actions.
- `StatusPill.swift` — connection indicator, dot plus text, animated colour change.
- `DropZoneView.swift` — `.onDrop` for files and folders, a click opens `NSOpenPanel`
  (multiple selection, folders allowed). Clear visual feedback on hover.
- `QueueListView.swift` — list of entries with name, size, state icon and a remove
  button. The entry currently running is highlighted.
- `ProgressPanelView.swift` — overall and current-file progress, throughput, remaining
  time, bytes transferred out of the total size.
- `LogConsoleView.swift` — collapsible, monospaced, auto-scrolled to the bottom.

`ContentView.swift` becomes a thin shell that shows `RootView`.
`Sphaira_ConnectApp.swift` stays lean (`WindowGroup`, `.hiddenTitleBar`, `.contentSize`).

---

## 6. Tests — `SphairaCoreTests/` (a separate SwiftPM package next to the Xcode project)

What is tested is the pure logic from `Core/`, pulled in via a symlink. Swift Testing
(`import Testing`, `@Test`, `#expect`). Mandatory cases:

- CRC32C against the reference values, empty input, incremental equality
- `Packet` round-trip, little-endian field layout, `dataOffset` beyond the 4 GB
  boundary, a corrupted byte ⇒ `checksumMismatch`, a wrong magic ⇒ `badMagic`,
  too short ⇒ `shortPacket`
- `ItemScanner`: folder recursion, extension filter, duplicates, stable ordering,
  extension case-insensitivity
- `ByteFormat`: boundary values, negative, `.infinity`, `.nan`
- `ProgressTracker`: a chunk requested near the end of the file must **not** inflate
  progress (the regression that shipped once), chunks summed regardless of order,
  duplicate ranges clamped to the file size, zero and negative sizes safe, the
  100 ms throttle, and smoothed throughput — all driven by injected timestamps
  rather than a real clock
