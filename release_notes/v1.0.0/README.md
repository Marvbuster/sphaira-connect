# Sphaira Connect v1.0 — Erstes Release

**Zeitraum:** Juli 2026
**Fokus:** Native macOS-App als Ersatz für `usb_install.py` — SPH0-Protokoll direkt gegen
libusb, Warteschlange mit Drag-and-drop, Fortschritt mit Durchsatz und Restzeit,
Liquid-Glass-Oberfläche.
**Minimales macOS:** 26.5 | **MARKETING_VERSION:** 1.0

## Builds

| Build | Datum | Kurzbeschreibung |
|-------|-------|------------------|
| **1** | 26.07.2026 | Erstes Release: SPH0-Protokoll nativ (Paket, CRC32C, Sitzungsablauf), libusb statisch gelinkt, Warteschlange mit rekursiver Ordnerauflösung, Fortschritt/Durchsatz/Restzeit, Protokollkonsole, Abbruch; 52 Tests im SwiftPM-Kernpaket. Fixes aus den ersten Praxisläufen: Fortschrittszählung, blockierendes `close()`, fehlendes Schreib-Zeitlimit, ungeordnete Rückmeldungen. |

## Dateien

| Datei | Inhalt |
|-------|--------|
| `macos_build_1.md` | Vollständige Feature- und Fix-Liste zu Build 1 |

Die Build-Nummer entspricht der `CURRENT_PROJECT_VERSION`, die Versionsnummer der
`MARKETING_VERSION` — beide aus `Sphaira Connect.xcodeproj/project.pbxproj`.
