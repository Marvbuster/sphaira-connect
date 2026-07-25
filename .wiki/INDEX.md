# Sphaira Connect — Wiki Index

> Auto-maintained. Regenerate with `/wiki-index` (oder `wiki ls sphaira-connect`).
> **Last updated:** 2026-07-26 | **Articles:** 12 (geplant) | **Archived:** 0 | **App:** v1.0 (Build 1)

---

## Architecture (3)

- [Systemüberblick — Module, Vertrag und Datenfluss](articles/architecture/system-overview.md) — Vier-Schichten-Schnitt (Core/USB/Shared/Features), CONTRACT.md als verbindlicher Vertrag, Weg der Daten von der Ablagefläche bis zur Switch
- [Nebenläufigkeit und Abbruch — MainActor-Default, Ereigniskanal, CancelFlag](articles/architecture/concurrency-and-cancellation.md) — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `Task.detached`-Sitzungsstart, ein geordneter `AsyncStream` (`SessionEvent`), NSLock-gesichertes CancelFlag
- [Warteschlange und Dateiscan — InstallItem, ItemScanner, ByteFormat](articles/architecture/queue-and-file-scanning.md) — Ordnerrekursion, Endungsfilter (nsp/xci/nsz/xcz), Duplikaterkennung, stabile Sortierung, absturzsichere Formatierung

## Protocol (3)

- [Das SPH0-USB-Protokoll — Paketformat, CRC32C, Kommandos](articles/protocol/sph0-wire-protocol.md) — 24-Byte-Paket aus sechs `UInt32` LE, CRC32C über die ersten 20 Bytes, Prüfreihenfolge in `decode`, `quit`/`open`, dataOffset über 4 GB, sendFileInfo-Bitpackung
- [Ablauf einer Installationssitzung — der Zustandsautomat](articles/protocol/install-session-flow.md) — open → Namensliste → Kommandoschleife → Dateitransfer, geordnetes Sitzungsende nach Dateifehler, Zählung nur tatsächlich übertragener Bytes
- [Fortschrittsberechnung — Summenzählung statt Hochwassermarke](articles/protocol/progress-tracking.md) — Warum XCI sofort 100 % zeigte, Summierung geklemmt auf die Dateigröße, 100-ms-Drosselung, exponentielle Durchsatzglättung mit hereingereichtem Zeitstempel

## USB (1)

- [libusb-Anbindung — Transport, Geräteerkennung und Fallstricke](articles/usb/libusb-transport.md) — VID 0x057E/PID 0x3000, Endpunkte aus der aktiven Konfiguration mit Rückfall 0x81/0x01, 500-ms-Lese- und 5-s-Schreib-Timeouts, Teilbytes bei Timeout, asynchrones `close()`

## UI (2)

- [Designsystem — Liquid Glass, Tokens und das Glas-in-Glas-Verbot](articles/ui/design-system-liquid-glass.md) — Spacing/Fonts/Colors, drei Zustands-Farbschleier, `GlassBackground` über natives `glassEffect`, `VisualEffectBlur`, `connectCard` als glasfreie Gruppierung, GlassButton
- [Fenster und Ansichten — RootView, WindowStyleConfigurator und die View-Bausteine](articles/ui/window-and-views.md) — RootView-ZStack mit Overlays in der Titelleisten-Zone, per `sizeKey` animierte NSWindow-Anpassung, DropZone/QueueList/ProgressPanel/LogConsole

## Operations (3)

- [Build-Konfiguration — statisches libusb, Bridging-Header, Sandbox aus](articles/operations/build-configuration.md) — `/opt/homebrew/lib/libusb-1.0.a` in OTHER_LDFLAGS, Header-Suchpfad, `ENABLE_APP_SANDBOX = NO` bei aktiver Hardened Runtime, MainActor-Default, dateisystem-synchronisierte Gruppe
- [Teststrategie — SwiftPM-Paket mit Symlink auf Core](articles/operations/testing-strategy.md) — `SphairaCoreTests` mit `Sources/SphairaCore` → `Sphaira Connect/Core`, `swift test` mit Swift Testing, Pflichtfälle aus dem Vertrag
- [Fehlersuche — Praxisfunde und ihre Lösungen](articles/operations/troubleshooting.md) — Hochwassermarken-Fehler, blockierendes `libusb_close`/`libusb_exit`, Teilbytes trotz TIMEOUT, `accessDenied`, AsyncStream-Rückfall, Namensdoppelung, wiederhergestellte Fenstergröße

---

## Stats

- **Total:** 12 articles (0 archived)
- **By category:** Architecture(3), Protocol(3), USB(1), UI(2), Operations(3)
- **Sprache:** Deutsch
- **Konvention:** kebab-case Dateinamen, Frontmatter obligatorisch, Mermaid bevorzugt
- **Vertrag:** `CONTRACT.md` — verbindlich für alle Signaturen und den Sitzungsablauf
- **Build:** MARKETING_VERSION 1.0 · CURRENT_PROJECT_VERSION 1 · macOS 26.5
