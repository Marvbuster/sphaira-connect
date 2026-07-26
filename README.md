# Sphaira Connect

**A native macOS app that sends title packages over USB to [Sphaira](https://github.com/ITotalJustice/sphaira) on the Nintendo Switch.**

[![Platform](https://img.shields.io/badge/Platform-macOS%2026%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-52%20passing-brightgreen)](SphairaCoreTests)
[![Languages](https://img.shields.io/badge/Languages-EN%20%7C%20DE-lightgrey)](Sphaira%20Connect/Localizable.xcstrings)

*[Deutsche Fassung](README.de.md)*

Sphaira 1.0.0 replaced its Tinfoil-compatible USB protocol with a custom one
([issue #249](https://github.com/ITotalJustice/sphaira/issues/249)). NS-USBloader,
Fluffy and frhop stopped working with it, leaving the bundled Python script
`tools/usb_install.py` as the only way to install over USB. Sphaira Connect is its
native counterpart: a real macOS app with a queue, progress display and a log —
no Python environment required.

<!-- Add screenshots here once available:
<p align="center">
  <img src="docs/screenshots/queue.png" width="800" alt="Transfer queue">
</p>
-->

---

## Download

Prebuilt versions live under **[Releases](../../releases)**.

The app is **ad-hoc signed** — it carries no Developer ID and is not notarised, so
Gatekeeper will refuse it on first launch. Right-click the app and choose **Open**
once, and macOS remembers the decision. If you would rather not trust a binary from
a stranger, build it yourself; it takes one command and about a minute.

libusb is linked statically, so the finished app does **not** need Homebrew.

---

## Features

- **Drag and drop** for `.nsp`, `.xci`, `.nsz` and `.xcz` — folders are expanded
  recursively, duplicates are dropped
- **Honest progress** with throughput and time remaining, smoothed rather than jittery
- **Per-item queue state**; if a file fails, the session ends cleanly instead of
  tearing down the USB connection
- **Device detection** in the background — the app knows whether a Switch is attached
- **Cancellation that actually works**, even mid-transfer
- **Liquid Glass** throughout, with a transparent title bar and a window that
  resizes to its content

## Requirements

| | |
|---|---|
| macOS | 26.0 or newer (Apple Silicon) |
| Switch | Custom firmware with [Atmosphère](https://github.com/Atmosphere-NX/Atmosphere) |
| Console app | [Sphaira](https://github.com/ITotalJustice/sphaira) 1.0.0 or newer |

## Preparing the Switch

Without these three steps nothing happens, and no host app can do them for you:

1. Enable **Options → Install Options → "Enable sysmmc"**. Installing is switched
   **off by default** in Sphaira. This is by far the most common reason people see
   the console sit there doing nothing.
2. Set **"Install location"** to the SD card unless you want titles in internal storage.
3. **Turn MTP off** and start **USB Install**. MTP and USB installation claim the
   same interface and block each other.

Once Sphaira shows "waiting for USB connection…", the console is ready.

## Building

```bash
brew install libusb
open "Sphaira Connect.xcodeproj"
```

libusb is linked **statically**, so the resulting app has no runtime dependency on
Homebrew. The path lives in `OTHER_LDFLAGS`; on Intel Macs the library sits under
`/usr/local` instead of `/opt/homebrew` and needs adjusting there.

Tests live in a standalone SwiftPM package that pulls in the core sources via a symlink:

```bash
cd SphairaCoreTests && swift test
```

## Layout

```
Sphaira Connect/
  Core/        Pure logic — protocol, CRC32C, progress, file scanning
  USB/         libusb transport and the protocol state machine
  Shared/      Design system (Liquid Glass, tokens, window handling)
  Features/    View model and SwiftUI interface
```

`Core/` deliberately depends on neither SwiftUI nor libusb. That is the only reason
the protocol and progress logic can be tested without a console and without an
Xcode test target.

Detailed documentation lives in the `.wiki/` folder as plain Markdown. **Note:** the
wiki articles are written in German; the code, its comments and this README are the
authoritative English reference.

## The protocol

Sphaira speaks a custom, CRC32C-protected packet format. Six 32-bit values,
little-endian, where the last field protects the first five:

```
magic ("SPH0") | arg2 | arg3 | arg4 | arg5 | crc32c
```

The console actively requests byte ranges, and it does so **out of order** — not
sequentially from the start. Anyone building a progress bar on top of this must
therefore not track the highest requested offset: with an XCI, Sphaira reads
partition data near the end of the file almost immediately, which would peg the bar
at 100 % within seconds. Count the bytes actually sent instead.

Details are in `.wiki/articles/` and in `Core/SphairaProtocol.swift`.

## Known pitfalls

| Symptom | Cause |
|---|---|
| "Access denied" | NS-USBloader or another program still holds the USB interface |
| Nothing happens, Sphaira waits forever | "Enable sysmmc" is off, or MTP is running in parallel |
| Transfer stalls right at the start | The title is already installed |
| "Transfer incomplete" / item marked skipped | Sphaira closed the file after a few kilobytes — usually because the title is already installed, otherwise because it rejected the file |

That last one deserves a note: the two cases are **indistinguishable on the wire**.
Sphaira sends the same close command whether it skips a duplicate or rejects a bad
file, so the app reports what it can prove and names both possibilities rather than
guessing.

## Compared to the Python script

| | `usb_install.py` | Sphaira Connect |
|---|---|---|
| Prerequisites | Python, venv, pyusb | none |
| Input | exactly one path as an argument | drag and drop, any number |
| Progress | none | two bars, throughput, time remaining |
| Cancelling | Ctrl-C only takes effect after a delay | any time |
| Already-installed title | hangs without a word | reported |
| Languages | English | English and German |

## License

**GPL-3.0** — see [LICENSE](LICENSE).

This is not a free choice but a consequence of the dependencies. The protocol
implementation is derived from `tools/usb_install.py` in
[Sphaira](https://github.com/ITotalJustice/sphaira) (GPL-3.0), and the statically
linked [libusb](https://libusb.info) is LGPL-2.1-or-later. GPL-3.0 is compatible
with both. [NS-USBloader](https://github.com/developersu/ns-usbloader) is GPL-3.0
for the same reason.

## Thanks

- [ITotalJustice](https://github.com/ITotalJustice) for Sphaira and for
  `usb_install.py`, without which working out the protocol would have been
  considerably more painful
- [libusb](https://libusb.info) for the USB plumbing
- [Atmosphère](https://github.com/Atmosphere-NX/Atmosphere), on which all of this rests

## Notice

Sphaira Connect transfers files over USB. What you transfer is your responsibility —
only back up software you own, and mind the law where you live. This project is not
affiliated with or endorsed by Nintendo.
