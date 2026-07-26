---
title: Sphaira Connect
one_liner: "Native macOS app that transfers NSP/XCI/NSZ/XCZ files over USB to the Switch homebrew app Sphaira"
status: active
tech_stack:
  - libusb
  - macos
  - swift
  - swift-testing
  - swiftpm
  - swiftui
  - usb
  - xcode
versions:
  app: "1.0"
  build: 1
  macos_min: "26.5"
  swift_language_mode: "5"
size:
  files: 29
  prod_files: 23
  test_files: 6
  loc: 2581
  prod_loc: 1979
  test_loc: 602
  languages:
    swift: 2581
deployment:
  platform: macos
  notes: "Xcode build, statically linked libusb, sandbox off, Hardened Runtime on"
quick_links:
  contract: "CONTRACT.md"
last_active: 2026-07-26
---
# In a nutshell

**Sphaira Connect** is a native macOS app (SwiftUI, macOS 26.5) that transfers Nintendo Switch
files (`nsp`, `xci`, `nsz`, `xcz`) over USB to the homebrew app **Sphaira**. It replaces the Python
script `usb_install.py` — at its core the app is a reimplementation of that script's USB protocol,
wrapped in a user interface with a drop zone, a queue, progress reporting and a log console.

## Structure

Four layers, pinned down in `CONTRACT.md` (a binding interface contract — no signature is touched
without amending the contract):

- `Sphaira Connect/Core/` — pure logic with no SwiftUI or USB dependency: CRC32C, packet format,
  error types, queue model, size formatting, progress bookkeeping
- `Sphaira Connect/USB/` — libusb binding and the install-session state machine
- `Sphaira Connect/Shared/` — design system (Liquid Glass, tokens, window style)
- `Sphaira Connect/Features/` (+ `Views/`) — view model and SwiftUI views

## What you need to know first

1. **Read `CONTRACT.md` first.** It fixes the signatures, the folder assignment and the exact
   session flow — deviate from it and the Switch hangs.
2. **MainActor is the default** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Anything that talks
   to USB or blocks must be explicitly `nonisolated`; the session runs via `Task.detached`.
3. **The protocol is the heart of it**: 24-byte packets of six little-endian `UInt32` values with a
   CRC32C over the first 20 bytes; the Switch requests files by index and offset.
4. **Progress is summed up, not measured with a high-water mark** — for XCI the Switch reads data
   near the end of the file early on, so a high-water mark would sit at 100 % immediately.
5. **Do not touch the project file**: source files are wired in through a file-system-synchronized
   group; libusb is statically linked, the App Sandbox is off (USB access).
6. **Tests run without Xcode**: `SphairaCoreTests/` is a standalone SwiftPM package whose
   `Sources/SphairaCore` is a symlink to `Sphaira Connect/Core` — `swift test` is all you need.

## What is documented

- **architecture** (3 articles) — module boundaries, concurrency and cancellation, queue and file scanning
- **protocol** (3 articles) — SPH0 wire format, session state machine, progress calculation
- **usb** (1 article) — libusb transport, device discovery, timeouts and pitfalls
- **ui** (2 articles) — design system (Liquid Glass) plus window and views
- **operations** (3 articles) — build configuration, testing strategy, troubleshooting
