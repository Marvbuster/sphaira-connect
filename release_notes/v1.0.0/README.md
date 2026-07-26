# Sphaira Connect v1.0 — First Release

**Period:** July 2026
**Focus:** A native macOS app replacing `usb_install.py` — the SPH0 protocol spoken
directly against libusb, a drag-and-drop queue, progress with throughput and remaining
time, Liquid Glass interface.
**Minimum macOS:** 26.5 | **MARKETING_VERSION:** 1.0

## Builds

| Build | Date | Short description |
|-------|------|-------------------|
| **1** | 2026-07-26 | First release: native SPH0 protocol (packet, CRC32C, session flow), statically linked libusb, queue with recursive folder resolution, progress/throughput/remaining time, log console, cancellation; 52 tests in the SwiftPM core package. Fixes from the first real-world runs: progress accounting, blocking `close()`, missing write timeout, out-of-order callbacks. |

## Files

| File | Contents |
|------|----------|
| `macos_build_1.md` | Complete list of features and fixes for build 1 |

The build number corresponds to `CURRENT_PROJECT_VERSION` and the version number to
`MARKETING_VERSION` — both taken from `Sphaira Connect.xcodeproj/project.pbxproj`.
