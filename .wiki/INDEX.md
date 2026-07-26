# Sphaira Connect — Wiki Index

> Auto-maintained. Regenerate with `/wiki-index` (or `wiki ls sphaira-connect`).
> **Last updated:** 2026-07-26 | **Articles:** 13 (planned) | **Archived:** 0 | **App:** v1.2 (Build 1)

---

## Architecture (3)

- [System Overview — Modules, Contract and Data Flow](articles/architecture/system-overview.md) — Four-layer split (Core/USB/Shared/Features), CONTRACT.md as the binding contract, the path data takes from the drop zone to the Switch
- [Concurrency and Cancellation — MainActor Default, Event Channel, CancelFlag](articles/architecture/concurrency-and-cancellation.md) — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, session start via `Task.detached`, one ordered `AsyncStream` (`SessionEvent`), NSLock-guarded CancelFlag
- [Queue and File Scanning — InstallItem, ItemScanner, ByteFormat](articles/architecture/queue-and-file-scanning.md) — Folder recursion, extension filter (nsp/xci/nsz/xcz), duplicate detection, stable sorting, crash-proof formatting

## Protocol (4)

- [The SPH0 USB Protocol — Packet Format, CRC32C, Commands](articles/protocol/sph0-wire-protocol.md) — 24-byte packet of six `UInt32` LE, CRC32C over the first 20 bytes, validation order in `decode`, `quit`/`open`, dataOffset beyond 4 GB, sendFileInfo bit packing
- [Install Session Flow — The State Machine](articles/protocol/install-session-flow.md) — open → file list → command loop → file transfer, orderly session shutdown after a file error, counting only the bytes actually transferred
- [Progress Calculation — Cumulative Counting Instead of a High-Water Mark](articles/protocol/progress-tracking.md) — Why XCI jumped straight to 100 %, summation clamped to the file size, 100 ms throttling, exponential throughput smoothing with an injected timestamp
- [RCM Payload Injection — Fusée Gelée Image, Trigger, Official Presets](articles/protocol/rcm-payload-injection.md) — RCM image layout (header, address table, intermezzo relocator), `RCMTriggerOutcome` classification, Hekate/Fusée official-release downloads with SHA-256 verification and path-traversal guards

## USB (1)

- [libusb Binding — Transport, Device Discovery and Pitfalls](articles/usb/libusb-transport.md) — VID 0x057E/PID 0x3000, endpoints from the active configuration with a 0x81/0x01 fallback, 500 ms read and 5 s write timeouts, partial bytes on timeout, asynchronous `close()`

## UI (2)

- [Design System — Liquid Glass, Tokens and the No-Glass-on-Glass Rule](articles/ui/design-system-liquid-glass.md) — Spacing/fonts/colors, three state tints, `GlassBackground` on top of the native `glassEffect`, `VisualEffectBlur`, `connectCard` as glass-free grouping, GlassButton
- [Window and Views — RootView, WindowStyleConfigurator and the View Building Blocks](articles/ui/window-and-views.md) — RootView ZStack with overlays in the title-bar zone, NSWindow resizing animated via `sizeKey`, DropZone/QueueList/ProgressPanel/LogConsole

## Operations (3)

- [Build Configuration — Static libusb, Bridging Header, Sandbox Off](articles/operations/build-configuration.md) — `/opt/homebrew/lib/libusb-1.0.a` in OTHER_LDFLAGS, header search path, `ENABLE_APP_SANDBOX = NO` with Hardened Runtime enabled, MainActor default, file-system-synchronized group
- [Testing Strategy — SwiftPM Package with a Symlink to Core](articles/operations/testing-strategy.md) — `SphairaCoreTests` with `Sources/SphairaCore` → `Sphaira Connect/Core`, `swift test` with Swift Testing, the mandatory cases from the contract
- [Troubleshooting — Field Findings and Their Fixes](articles/operations/troubleshooting.md) — The high-water-mark bug, blocking `libusb_close`/`libusb_exit`, partial bytes despite TIMEOUT, `accessDenied`, AsyncStream fallback, duplicated names, restored window size

---

## Stats

- **Total:** 13 articles (0 archived)
- **By category:** Architecture(3), Protocol(4), USB(1), UI(2), Operations(3)
- **Language:** English
- **Conventions:** kebab-case file names, mandatory frontmatter, Mermaid preferred
- **Contract:** `CONTRACT.md` — binding for all signatures and the session flow
- **Build:** MARKETING_VERSION 1.2 · CURRENT_PROJECT_VERSION 1 · macOS 26.5
