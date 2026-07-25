# Sphaira Connect — Release Notes

**App:** Sphaira Connect — native macOS-App, die NSP/XCI/NSZ/XCZ per USB an die
Homebrew-App Sphaira auf einer Nintendo Switch überträgt
**Plattform:** macOS 26.5+ (SwiftUI, Swift 5 Sprachmodus, statisch gelinktes libusb)
**Autor:** Marvbuster

---

## Versionsübersicht

| Version | Build | Datum | Status | Kurzfassung |
|---------|-------|-------|--------|-------------|
| v1.0.0 | 1 | 26.07.2026 | Abgeschlossen | Erstes Release — SPH0-Protokoll nativ, Warteschlange, Fortschritt, Liquid-Glass-Oberfläche |

## Verzeichnisstruktur

```
release_notes/
├── README.md              ← diese Datei: alle Versionen mit je einem Satz
└── v1.0.0/
    ├── README.md          ← Builds-Tabelle dieser Version
    └── macos_build_1.md   ← Notes zu genau einem Build
```

Ein Ordner je Version, eine Datei je Build. Es gibt nur eine Plattform, also auch nur
eine Build-Datei pro Build — das Präfix `macos_` bleibt zur Klarheit im Dateinamen.

## Single Source of Truth: die Projektdatei

Beide Nummern stehen in `Sphaira Connect.xcodeproj/project.pbxproj` und werden
ausschließlich dort gepflegt:

| Nummer | Build-Setting | Bedeutung |
|--------|---------------|-----------|
| Version | `MARKETING_VERSION` | Namensgeber des Versionsordners (`release_notes/v{VERSION}/`, auf drei Stellen normalisiert — `1.0` → `v1.0.0`) |
| Build | `CURRENT_PROJECT_VERSION` | Namensgeber der Build-Datei (`macos_build_{N}.md`) |

Prüfen lässt sich der aktuelle Stand mit:

```
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" "Sphaira Connect.xcodeproj/project.pbxproj" | sort -u
```

## Wie hochgezählt wird

- **Neue Funktionen** → Minor anheben (`1.0` → `1.1`), `CURRENT_PROJECT_VERSION` zurück auf `1`,
  neuer Ordner `release_notes/v1.1.0/` mit `macos_build_1.md`.
- **Nur Fixes innerhalb einer Version** → `CURRENT_PROJECT_VERSION` um 1 erhöhen, Datei
  `macos_build_{N}.md` im bestehenden Versionsordner ergänzen und dessen `README.md`
  um eine Zeile erweitern.
- **Breaking Change am USB-Protokoll oder am Sitzungsablauf** → Major anheben und im
  Abschnitt „Zusammenfassung" der Build-Notes ausdrücklich als solcher benennen.
- Jede neue Version bekommt zusätzlich eine Zeile in der Versionsübersicht oben.

Den kompletten Ablauf — Änderungen ermitteln, Bump entscheiden, Notes schreiben, Tests
laufen lassen, Wiki aktualisieren, committen — beschreibt `.claude/commands/wrap.md`.

## Typen in den Build-Notes

| Typ | Bedeutung |
|-----|-----------|
| `FEATURE` | Neue Funktionalität |
| `FIX` | Behobener Fehler |
| `CHANGE` | Geändertes oder entferntes Verhalten ohne neue Funktion |

Einträge, die das USB-Protokoll oder den Sitzungsablauf betreffen, verweisen zusätzlich
auf den zugehörigen Wiki-Artikel (z. B. `protocol/install-session-flow`).

## Später ergänzbar

Ein `features/`-Ordner wie im Schnack-Projekt ist zu Beginn nicht nötig. Er kommt dazu,
sobald sich Feature-Sammelbeschreibungen sinnvoll von den Build-Notes lösen lassen.
