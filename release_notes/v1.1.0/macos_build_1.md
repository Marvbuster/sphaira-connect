# Sphaira Connect macOS v1.1 Build 1

**Date:** 2026-07-26 | **Status:** Done | **Minimum macOS:** 26.5
**MARKETING_VERSION:** 1.1 | **CURRENT_PROJECT_VERSION:** 1
**Commit:** `PENDING` — *RCM payload injection, official Hekate/Fusée presets*

## Summary

Sphaira Connect gains a second mode alongside the existing USB installer: manual RCM
payload injection for unpatched Erista/V1 Switch consoles, based on the publicly
documented Fusée Gelée protocol. The app builds the RCM image itself (header, address
table, intermezzo relocator, user payload), detects the distinct APX device
(`0955:7321`), transfers it over libusb and triggers the exploit with an oversized
control transfer — never automatically, only on an explicit button press. On top of
manual `.bin` selection, two persistent presets (Hekate, Fusée) can fetch the current
or four previous official releases directly from GitHub, verifying size and SHA-256
digest before use. The shared log line type used by both the installer and the RCM
view was factored out along the way.

## Features & Changes

| Type | Description |
|------|-------------|
| FEATURE | RCM image builder: 4-byte header (`rcmLength`), 96-entry address table pointing at the intermezzo relocator, the 92-byte relocator itself, and the user payload appended and packet-aligned to `0x1000` (`Core/RCMPayload.swift`) |
| FEATURE | APX-mode device detection via VID `0x0955` / PID `0x7321`, polled every 2 seconds independent of the installer's own Switch monitor (`USB/RCMTransport.swift`, `Features/RCMInjectorModel.swift`) |
| FEATURE | RCM transport: reads the 16-byte device ID, writes the image in `0x1000`-byte chunks with parity padding for an even packet count, then triggers Fusée Gelée with an oversized control transfer (`USB/RCMTransport.swift`) |
| FEATURE | `RCMTriggerOutcome` classifies the libusb result of the trigger transfer into "payload started" (expected disconnect-style errors), "device responded" (likely patched) and "USB failure", replacing an inline check with a dedicated, independently testable type (`Core/RCMTriggerOutcome.swift`) |
| FEATURE | `RCMInjectorModel` mirrors `InstallerModel`'s event-stream architecture for the RCM flow: preparing/injecting/succeeded/failed phases, progress and log, all routed through one `AsyncStream` (`Features/RCMInjectorModel.swift`) |
| FEATURE | Manual `.bin` selection via drag-and-drop or `NSOpenPanel`, restricted to the `.bin` extension and validated as a regular, readable file before use (`Features/Views/RCMPayloadPickerView.swift`) |
| FEATURE | Persistent Hekate and Fusée presets: the chosen file path survives app restarts via `UserDefaults`, is re-validated on launch, and falls back cleanly if the file has moved or been deleted (`Features/RCMInjectorModel.swift`) |
| FEATURE | Official-release download menus for both presets: the current and four previous stable releases are listed from the GitHub API (`CTCaer/hekate`, `Atmosphere-NX/Atmosphere`), the correct asset is picked by name (rejecting the 8 GB Hekate variant and non-`fusee.bin` Atmosphère assets), and any path-traversing asset name is rejected outright (`Core/HekateRelease.swift`, `Core/FuseeRelease.swift`, `Features/HekateDownloader.swift`, `Features/FuseeDownloader.swift`) |
| FEATURE | Downloaded payloads are size-capped at 2 MB and checked against the SHA-256 digest GitHub publishes for the asset, when present, before being written into Application Support (`Features/HekateDownloader.swift`, `Features/FuseeDownloader.swift`) |
| FEATURE | Mode switch in the main window (Sphaira installation ⇄ RCM payload), each with its own device monitor, status pill and log, switching monitors cleanly on change (`Features/Views/RootView.swift`) |
| CHANGE | `InstallerModel.LogLine` extracted into a shared `AppLogLine`, now used by both `InstallerModel` and `RCMInjectorModel` so the log console view has a single type to render (`Shared/AppLogLine.swift`, `Features/InstallerModel.swift`, `Features/Views/LogConsoleView.swift`) |
| CHANGE | About panel and README/NOTICE credit the Fusée Gelée protocol and the [ironfoil](https://github.com/sermuns/ironfoil) reference implementation; README documents the new RCM flow, the preset downloads and the project's licensing stance in a new "Open source, no agenda" section (`Sphaira_ConnectApp.swift`, `README.md`, `README.de.md`, `NOTICE.md`) |

## Tests

62 tests passing (up from 52), adding `RCMPayloadTests`, `RCMTriggerOutcomeTests`,
`HekateReleaseTests` and `FuseeReleaseTests` — including explicit coverage for
rejecting the 8 GB Hekate variant, rejecting non-`fusee.bin` assets, and rejecting
path-traversing asset names (`../hekate_ctcaer_v1.bin`).
