---
title: "RCM Payload Injection — Fusée Gelée Image, Trigger, Official Presets"
created: 2026-07-26
updated: 2026-07-26
category: protocol
tags: [rcm, fusee-gelee, apx, libusb, tegra, hekate, github-api, cryptokit]
status: current
related:
  - usb/libusb-transport
  - architecture/system-overview
  - operations/build-configuration
  - operations/testing-strategy
  - protocol/progress-tracking
  - ui/window-and-views
code_refs:
  - Sphaira Connect/Core/RCMPayload.swift
  - Sphaira Connect/Core/RCMTriggerOutcome.swift
  - Sphaira Connect/Core/HekateRelease.swift
  - Sphaira Connect/Core/FuseeRelease.swift
  - Sphaira Connect/USB/RCMTransport.swift
  - Sphaira Connect/Features/RCMInjectorModel.swift
  - Sphaira Connect/Features/HekateDownloader.swift
  - Sphaira Connect/Features/FuseeDownloader.swift
  - Sphaira Connect/Features/Views/RCMPayloadPickerView.swift
  - Sphaira Connect/Features/Views/RCMPresetView.swift
---

# RCM Payload Injection

Alongside the Sphaira USB installer, Sphaira Connect has a second, independent mode: manual RCM
payload injection for an unpatched Erista/V1 Nintendo Switch, based on the publicly documented
**Fusée Gelée** USB recovery-mode exploit. It shares nothing at runtime with the SPH0 installer
path — different USB device, different transport, different view model — but follows the same
architectural rules from `CONTRACT.md`: pure image-building logic in `Core/`, the blocking libusb
call in `USB/`, an `@Observable` model plus views in `Features/`.

## Why this is safe ground

Fusée Gelée (CVE-2018-6242) has been public since 2018 and is the basis of essentially every
Switch homebrew entry point — Hekate, Atmosphère's Fusée payload, TegraRcmGUI, `fusee-launcher`,
and the reference this implementation leans on, [ironfoil](https://github.com/sermuns/ironfoil).
Only **unpatched** V1/Erista consoles are affected; Nintendo closed the hole in later board
revisions. The app never triggers an injection on its own — `RCMInjectorModel.inject()` is the
only entry point, and neither selecting a file nor detecting a console calls it.

## The image — `Core/RCMPayload.swift`

`RCMPayloadBuilder.build(userPayload:)` assembles the exact byte layout the vulnerable boot ROM
expects, entirely without USB, which is what makes it testable byte-for-byte:

| Offset | Content |
|---|---|
| `0x0` | `rcmLength` (`0x30298`), little-endian `UInt32` — a fixed value every Fusée Gelée implementation uses |
| `0x2A8` (`addressTableOffset`) | 96 repeated pointers to `intermezzoLocation` (`0x4001F000`), one per 4-byte slot up to the intermezzo itself |
| after the address table | the 92-byte intermezzo relocator (standard, permissively licensed machine code shared by `fusee-launcher` and ironfoil) |
| `userPayloadOffset` | the user's own payload (Hekate, Fusée, or any other RCM `.bin`), copied verbatim |

The image is padded up to a `0x1000`-byte boundary. `requiresParityPadding` adds one further
`0x1000` zero packet whenever the total packet count would be even — an artifact of how the
vulnerable USB stack reads its transfer, also inherited from the reference implementations.
`RCMPayloadTests.swift` checks the header, the address table, the intermezzo bytes and the parity
rule against literal expected byte values, not just "does it not crash".

## The transport — `USB/RCMTransport.swift`

Structurally a sibling of `USBTransport` (see [[usb/libusb-transport]]) but for a different device
and a one-shot operation rather than a session:

1. Find the device by `vendorID = 0x0955`, `productID = 0x7321` — the distinct APX
   (auto-detect/recovery) identifier, not Sphaira's own `0x057E`/`0x3000`.
2. Read 16 bytes as the device ID (`readExactly`), surfaced to the UI as a hex string.
3. Write the image in `RCMPayloadBuilder.packetSize` (`0x1000`)-byte chunks via
   `libusb_bulk_transfer`, reporting `(sent, total)` after every chunk.
4. Send the parity packet if required.
5. Trigger the exploit: an oversized `libusb_control_transfer` (device-to-host, 0x7000-byte
   buffer) that the vulnerable boot ROM never gets to answer — it jumps to the payload first.

## Interpreting the trigger — `Core/RCMTriggerOutcome.swift`

The control transfer's return code is the only signal the app gets back, and libusb reports "the
device vanished mid-request" inconsistently across platforms and host controllers.
`RCMTriggerOutcome.classify(_:)` maps the raw `Int32` into three cases:

- **`.payloadStarted`** — `-1`, `-4`, `-7` or `-9` (`LIBUSB_ERROR_IO`/`NO_DEVICE`/`TIMEOUT`/`PIPE`).
  This is the **success** path: the boot ROM left USB recovery to run the payload.
- **`.deviceResponded(code)`** — the transfer actually completed (`code >= 0`). The console
  answered normally, which almost always means it is patched, or the request never reached the
  vulnerable code path.
- **`.usbFailure(code)`** — any other negative code is a genuine transport failure.

Pulling this out of `RCMTransport.inject` and into its own `nonisolated enum` made the
classification independently testable (`RCMTriggerOutcomeTests.swift`) without touching real USB
hardware.

## Official presets and downloads

Manual `.bin` selection (`RCMPayloadPickerView`, drag-and-drop or `NSOpenPanel`, restricted to the
`.bin` extension) is always available. On top of it, `RCMInjectorModel` keeps two **presets** —
Hekate and Fusée — whose file paths persist across launches via `UserDefaults`
(`rcmPreset.<name>.path`), re-validated on launch (`isUsablePayload`) so a moved or deleted file
falls back cleanly instead of crashing.

Each preset can also fetch an **official release** directly:

- `HekateDownloader` lists releases from `CTCaer/hekate` and picks the asset named
  `hekate_ctcaer_<version>.bin` — explicitly excluding the `ram8gb` variant.
- `FuseeDownloader` lists releases from `Atmosphere-NX/Atmosphere` and picks the asset literally
  named `fusee.bin`.

Both:

- call the GitHub REST API unauthenticated (`per_page=10`, filtered to non-draft/non-prerelease
  releases with a matching asset, capped to the 5 most recent),
- reject an asset whose declared size is `0` or over 2 MB before downloading,
- verify the downloaded byte count against the declared size,
- verify the SHA-256 digest against GitHub's `digest` field when GitHub publishes one,
- write the result into `~/Library/Application Support/Sphaira Connect/Payloads/`,
- and reject any asset name that isn't its own last path component — the guard against a
  path-traversing name like `../hekate_ctcaer_v1.bin`, covered explicitly by
  `HekateReleaseTests`/`FuseeReleaseTests`.

Downloading and selecting a preset only populates `payloadURL` — exactly like picking a file
manually. It never calls `inject()`.

## View model and UI

`RCMInjectorModel` mirrors `InstallerModel`'s shape: an `AsyncStream` of `RCMEvent` values
(`prepared`, `deviceID`, `progress`, `succeeded`, `failed`) collected on the `MainActor`, a
`Phase` enum (`idle`/`preparing`/`injecting`/`succeeded`/`failed`), and its own 2-second
`isRCMAttached()` polling loop — independent of `InstallerModel.startMonitoring()`, since the two
modes watch for different USB devices. `RootView` switches between the Sphaira-installer and the
RCM view with a segmented mode picker ([[ui/window-and-views]], `ModeSwitcherView`), stopping and
restarting whichever monitor is no longer active.

Since v1.2, `.progress` also carries a `bytesPerSecond` — the `.injecting` phase feeds the same
`Core/ProgressTracker` the installer uses into the large remaining-time countdown at the top of the
window (see [[protocol/progress-tracking]] for how, [[ui/window-and-views]] for the badge itself).
