---
project_name: "Sphaira Connect"
wiki_root: ".wiki"
article_dir: "articles"
inbox_dir: "_inbox"
archive_dir: "_archive"
default_language: "de"
auto_index: true
auto_crosslink: true
categories:
  - architecture
  - protocol
  - usb
  - ui
  - operations
tech_stack:
  - libusb
  - macos
  - swift
  - swift-testing
  - swiftpm
  - swiftui
  - usb
  - xcode

---

# Wiki Configuration

Sphaira Connect ist eine native macOS-App (SwiftUI, macOS 26.5), die NSP/XCI/NSZ/XCZ-Dateien
per USB an die Homebrew-App Sphaira auf einer Nintendo Switch überträgt und damit das
Python-Skript `usb_install.py` ersetzt. Dieses Wiki dokumentiert den Modulschnitt, das
SPH0-Drahtformat samt Sitzungsablauf, die libusb-Schicht, die Oberfläche und den Betrieb.

## Categories

| Category | Scope |
|----------|-------|
| `architecture` | Modulschnitt (Core/USB/Shared/Features), Nebenläufigkeit und Abbruch, Warteschlangen- und Datenmodell |
| `protocol` | SPH0-Drahtformat, CRC32C, Kommandos, Zustandsautomat der Installationssitzung, Fortschrittsberechnung |
| `usb` | libusb-Anbindung, Geräteerkennung, Endpunkte, Timeouts, Abbau der Verbindung |
| `ui` | Designsystem (Liquid Glass, Tokens), Fensterverhalten, SwiftUI-Ansichten |
| `operations` | Xcode-Build-Einstellungen, Teststrategie, Release-Notes-Workflow, Fehlersuche |

## Code Roots

- App: `Sphaira Connect/` (SwiftUI, macOS 26.5, per `PBXFileSystemSynchronizedRootGroup` eingebunden)
  - `Core/` — reine Logik, keine SwiftUI-, keine USB-Abhängigkeit
  - `USB/` — libusb-Anbindung und Protokoll-Zustandsautomat, durchgehend `nonisolated`
  - `Shared/` — Designsystem
  - `Features/` und `Features/Views/` — Ansichtsmodell und SwiftUI-Ansichten
- Vertrag: `CONTRACT.md` (verbindlicher Schnittstellenvertrag, Single Source of Truth für Signaturen)
- Tests: `SphairaCoreTests/` (eigenständiges SwiftPM-Paket, `Sources/SphairaCore` ist ein Symlink auf `Sphaira Connect/Core`)
- Projektdatei: `Sphaira Connect.xcodeproj/project.pbxproj` (Single Source of Truth für `MARKETING_VERSION` und `CURRENT_PROJECT_VERSION`)

## Conventions

- Dateinamen: kebab-case (z. B. `sph0-wire-protocol.md`)
- Ein abgegrenztes Thema pro Datei (max. 400 Zeilen, Ziel 100–250)
- Frontmatter obligatorisch (`title`, `created`, `updated`, `category`, `tags`, `status`, `related`, `code_refs`)
- Mermaid-Diagramme bevorzugt für Abläufe und Zustandsautomaten
- Code-Pfade relativ zum Projekt-Root (`Sphaira Connect/USB/InstallSession.swift`, nicht absolut)
- Cross-References bidirektional (wenn A → B, dann B → A in `related`)
- Sprache: Deutsch für fachliche Inhalte, Englisch nur für rein technische Refs (Bezeichner, Feldnamen, Konstanten)
- Farbige Boxen in Mermaid immer mit schwarzer Schrift (`color:#000`)
- Keine Aussage über Code, der nicht gelesen wurde — jede Behauptung muss durch einen `code_ref` gedeckt sein

## Article Lifecycle

| Status | Bedeutung |
|--------|-----------|
| `current` | Aktiv und aktuell |
| `draft` | In Arbeit |
| `stale` | Braucht Review |
| `archived` | Veraltet, in `_archive/` verschoben |

## Projektregeln (aus CONTRACT.md)

- Zielplattform macOS 26.5, Swift-5-Sprachmodus, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
  → alles, was USB macht oder blockiert, ist explizit `nonisolated` bzw. `@unchecked Sendable`
- App-Sandbox aus, Hardened Runtime an; libusb statisch gelinkt, Bridging-Header vorhanden
- Die Projektdatei wird bei neuen Dateien **nicht** angefasst (Dateisystem-synchronisierte Gruppe)
- Kommentare und Oberflächentexte auf Deutsch, Bezeichner auf Englisch
- Keine Quelldatei über 400 Zeilen
- Änderungen am Sitzungsablauf oder am Drahtformat: **immer zuerst** `CONTRACT.md` prüfen,
  dann die Artikel unter `protocol/` aktualisieren

## Versionierung und Release Notes

- `MARKETING_VERSION` und `CURRENT_PROJECT_VERSION` aus `Sphaira Connect.xcodeproj/project.pbxproj`
  sind die Single Source of Truth für Versions- und Build-Nummer
- Release Notes liegen im Projekt unter `release_notes/v{VERSION}/build_{N}.md`
  (eine Datei je Build, da es nur eine Plattform gibt), plus `README.md` je Versionsordner
  und `release_notes/README.md` auf oberster Ebene
- Wrap-Ablauf: Änderungen seit dem letzten Release-Commit ermitteln, Versions-/Build-Bump im
  pbxproj entscheiden (neue Funktionen = Minor, nur Fixes = Patch), Build-Notes und
  README-Tabellen schreiben, betroffene Wiki-Artikel samt `code_refs` und `updated`-Datum
  aktualisieren (Pflichtteil jedes Wraps), Commit im Muster
  `chore: v{VERSION} (Build {N}) — {Zusammenfassung}`
