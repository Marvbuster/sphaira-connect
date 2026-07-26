# Sphaira Connect macOS v1.0 Build 1

**Date:** 2026-07-26 | **Status:** Done | **Minimum macOS:** 26.5
**MARKETING_VERSION:** 1.0 | **CURRENT_PROJECT_VERSION:** 1
**Commit:** `0986a08` — *initial release of the native macOS app*

## Summary

First release. Sphaira Connect replaces the Python script `usb_install.py` with a native
SwiftUI app: it speaks the SPH0 protocol directly against a statically linked libusb,
accepts NSP/XCI/NSZ/XCZ by drag and drop and transfers them to the Sphaira homebrew app
on the Nintendo Switch. The core logic sits in `Sphaira Connect/Core/`, free of SwiftUI
and USB, and is covered by a standalone SwiftPM test package with 52 tests that pulls in
the sources via a symlink — without a second copy of the files.

The second half of this release are the corrections that came out of the first
real-world runs: with XCI the progress bar jumped straight to 100 %, the completion
message never appeared once the session had ended, and a stuck write made "Cancel" do
nothing.

## Features & Changes

| Type | Description |
|------|-------------|
| FEATURE | SPH0 packet format implemented natively: 24 bytes, six little-endian `UInt32` values, magic `0x53504830`, CRC32C over the first 20 bytes (`Core/SphairaProtocol.swift`) |
| FEATURE | CRC-32C (Castagnoli, reflected polynomial `0x82F63B78`) as a table-driven, `nonisolated` implementation without a third-party library (`Core/CRC32C.swift`) |
| FEATURE | Session flow as a state machine: send the file list, then a command loop over `open` and `quit`, file chunks on request from the Switch (`USB/InstallSession.swift`) — see the wiki article `protocol/install-session-flow` |
| FEATURE | libusb binding using bulk transfers, endpoints taken from the active configuration, falling back to `0x81`/`0x01` (`USB/USBTransport.swift`) |
| FEATURE | libusb statically linked (`/opt/homebrew/lib/libusb-1.0.a`) via a bridging header; App Sandbox off, Hardened Runtime on (`Sphaira Connect.xcodeproj/project.pbxproj`, `USB/SphairaConnect-Bridging-Header.h`) |
| FEATURE | Device detection via VID `0x057E` / PID `0x3000`; the status indicator polls every 2 seconds off the MainActor (`USB/LibUSBProbe.swift`, `Features/InstallerModel.swift`) |
| FEATURE | Queue filled by drag and drop or through a file dialog; folders are resolved recursively, duplicates are dropped by their standardised path, only `nsp`/`xci`/`nsz`/`xcz` are accepted, order is stable and alphabetical (`Core/InstallItem.swift`, `Features/Views/DropZoneView.swift`) |
| FEATURE | Queue list with a state per title (queued / transferring / done / failed), single removal and "remove all" — locked while a session is running (`Features/Views/QueueListView.swift`) |
| FEATURE | Progress display with per-file and overall share, smoothed throughput and estimated remaining time; refreshed at most every 100 ms (`Core/ProgressTracker.swift`, `Features/Views/ProgressPanelView.swift`) |
| FEATURE | German size, throughput and time formatting with a decimal comma, without `NumberFormatter` (`Core/ByteFormat.swift`) |
| FEATURE | Collapsible log with timestamps, capped at the last 500 lines (`Features/Views/LogConsoleView.swift`, `Features/InstallerModel.swift`) |
| FEATURE | Cancellation possible at any time: the cancellation flag is made atomic by an `NSLock` and is checked on the USB thread between transfers, without waiting on MainActor state (`Features/InstallerModel.swift`, `USB/USBTransport.swift`) |
| FEATURE | German-language error messages for every failure case — Switch not found, access denied, USB error with code, short packet, wrong magic, checksum mismatch, unexpected command, unreadable file, cancellation (`Core/InstallError.swift`) |
| FEATURE | Liquid Glass interface with its own design system: colour and spacing tokens, glass buttons, the window follows its content with an animation (`Shared/DesignTokens.swift`, `Shared/GlassButton.swift`, `Shared/WindowStyleConfigurator.swift`, `Features/Views/RootView.swift`) |
| FEATURE | Standalone SwiftPM test package with 52 tests covering the packet format, CRC32C, folder scanning, progress, formatting and error messages; pulls in `Sphaira Connect/Core/` via a symlink (`SphairaCoreTests/Package.swift`) |
| FIX | Progress counted the highest position requested by the Switch instead of the bytes actually sent — with XCI that put the bar at 100 % right away. `ProgressTracker.record` now only sums the chunks that were transferred and clamps to the file size, because the Switch is free to request the same ranges more than once (`Core/ProgressTracker.swift`) |
| FIX | `close()` blocked after the end of a session and held back the completion message, which left "Cancel" enabled. The libusb teardown now runs asynchronously on a background queue, with the references released beforehand (`USB/USBTransport.swift`) |
| FIX | Writes had no timeout, so a cancellation did not take effect in the middle of a chunk. Bulk writes now run with a 5000 ms timeout, timeouts count as an opportunity to check for cancellation, and bytes already transferred are accounted for (`USB/USBTransport.swift`) |
| FIX | Callbacks from the session ran through individual unstructured tasks and therefore arrived out of order. All events now go through exactly one `AsyncStream`, and the number of completed files is kept by a locked counter on the session thread (`Features/InstallerModel.swift`) |
| FIX | If the event stream ended without a completion message, the interface stayed on "running"; a fallback now sets the phase back to "ready" and writes a log line (`Features/InstallerModel.swift`) |
| FIX | Overall progress skipped over a failed file — only files transferred in full are counted now (`USB/InstallSession.swift`) |
| FIX | On a file error an error packet goes to the Switch and the command loop then answers the quit command as usual; the session ends in an orderly way instead of an abrupt USB teardown (`USB/InstallSession.swift`) |
| CHANGE | The SwiftData scaffolding from the Xcode template is gone: `Item.swift` deleted, `ContentView.swift` and `Sphaira_ConnectApp.swift` switched over to `RootView` |
