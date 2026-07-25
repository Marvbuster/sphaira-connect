---
title: Sphaira Connect
one_liner: "Native macOS-App, die NSP/XCI/NSZ/XCZ per USB an die Switch-Homebrew-App Sphaira überträgt"
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
  notes: "Xcode-Build, statisch gelinktes libusb, Sandbox aus, Hardened Runtime an"
quick_links:
  contract: "CONTRACT.md"
last_active: 2026-07-26
---
# In a nutshell

**Sphaira Connect** ist eine native macOS-App (SwiftUI, macOS 26.5), die Nintendo-Switch-Dateien
(`nsp`, `xci`, `nsz`, `xcz`) per USB an die Homebrew-App **Sphaira** überträgt. Sie ersetzt das
Python-Skript `usb_install.py` — die App ist also im Kern ein Reimplement von dessen USB-Protokoll,
verpackt in eine Oberfläche mit Ablagefläche, Warteschlange, Fortschritt und Protokollkonsole.

## Aufbau

Vier Schichten, festgeschrieben in `CONTRACT.md` (verbindlicher Schnittstellenvertrag — keine
Signatur wird ohne Vertragsänderung angefasst):

- `Sphaira Connect/Core/` — reine Logik ohne SwiftUI- und USB-Abhängigkeit: CRC32C, Paketformat,
  Fehlertypen, Warteschlangenmodell, Größenformatierung, Fortschrittsbuchführung
- `Sphaira Connect/USB/` — libusb-Anbindung und der Zustandsautomat der Installationssitzung
- `Sphaira Connect/Shared/` — Designsystem (Liquid Glass, Tokens, Fensterstil)
- `Sphaira Connect/Features/` (+ `Views/`) — Ansichtsmodell und SwiftUI-Ansichten

## Was man als Erstes wissen muss

1. **`CONTRACT.md` zuerst lesen.** Er legt Signaturen, Ordnerzuordnung und den exakten
   Sitzungsablauf fest — weicht man davon ab, hängt die Switch.
2. **MainActor ist der Default** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Alles, was USB
   macht oder blockiert, muss explizit `nonisolated` sein; die Sitzung läuft über `Task.detached`.
3. **Das Protokoll ist das Herzstück**: 24-Byte-Pakete aus sechs `UInt32` little-endian mit
   CRC32C über die ersten 20 Bytes; die Switch fordert Dateien per Index und Offset an.
4. **Fortschritt wird summiert, nicht per Hochwassermarke gemessen** — die Switch liest bei XCI
   früh Daten nahe dem Dateiende, eine Hochwassermarke stünde sofort bei 100 %.
5. **Projektdatei nicht anfassen**: Quelldateien werden über eine dateisystem-synchronisierte
   Gruppe eingebunden; libusb ist statisch gelinkt, App-Sandbox ist aus (USB-Zugriff).
6. **Tests laufen ohne Xcode**: `SphairaCoreTests/` ist ein eigenes SwiftPM-Paket, dessen
   `Sources/SphairaCore` ein Symlink auf `Sphaira Connect/Core` ist — `swift test` genügt.

## Was dokumentiert ist

- **architecture** (3 Artikel) — Modulschnitt, Nebenläufigkeit und Abbruch, Warteschlange und Dateiscan
- **protocol** (3 Artikel) — SPH0-Drahtformat, Sitzungs-Zustandsautomat, Fortschrittsberechnung
- **usb** (1 Artikel) — libusb-Transport, Geräteerkennung, Timeouts und Fallstricke
- **ui** (2 Artikel) — Designsystem (Liquid Glass) sowie Fenster und Ansichten
- **operations** (3 Artikel) — Build-Konfiguration, Teststrategie, Fehlersuche
