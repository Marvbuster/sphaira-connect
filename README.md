# Sphaira Connect

**Native macOS-App, die Titelpakete per USB an [Sphaira](https://github.com/ITotalJustice/sphaira) auf der Nintendo Switch überträgt.**

[![Plattform](https://img.shields.io/badge/Plattform-macOS%2026%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Lizenz](https://img.shields.io/badge/Lizenz-GPL--3.0-blue)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-52%20grün-brightgreen)](SphairaCoreTests)
[![Sprachen](https://img.shields.io/badge/Sprachen-DE%20%7C%20EN-lightgrey)](Sphaira%20Connect/Localizable.xcstrings)

Sphaira hat mit Version 1.0.0 sein USB-Protokoll von Tinfoil auf ein eigenes
umgestellt ([Issue #249](https://github.com/ITotalJustice/sphaira/issues/249)).
Seitdem funktionieren NS-USBloader, Fluffy und frhop nicht mehr damit — der
einzige verbliebene Weg war das mitgelieferte Python-Skript `tools/usb_install.py`.
Sphaira Connect ist dessen native Entsprechung: eine echte macOS-App mit
Warteschlange, Fortschrittsanzeige und Protokoll, ohne Python-Umgebung.

<!-- Screenshots hier einsetzen, sobald vorhanden:
<p align="center">
  <img src="docs/screenshots/queue.png" width="800" alt="Warteschlange">
</p>
-->

---

## Download

Fertige Versionen liegen unter **[Releases](../../releases)**. Die App ist signiert,
aber nicht notarisiert — beim ersten Start deshalb Rechtsklick → „Öffnen", sonst
verweigert Gatekeeper den Start.

libusb ist statisch eingebunden, es wird also **kein Homebrew** benötigt, um die
fertige App zu benutzen.

---

## Funktionen

- **Drag-and-drop** für `.nsp`, `.xci`, `.nsz` und `.xcz` — Ordner werden rekursiv
  aufgelöst, Duplikate fallen raus
- **Ehrlicher Fortschritt** mit Durchsatz und Restzeit, geglättet statt zappelnd
- **Warteschlange** mit Zustand je Eintrag; scheitert eine Datei, endet die Sitzung
  geordnet statt mit einem USB-Abriss
- **Geräteerkennung** im Hintergrund — die App sieht, ob die Switch am Bus hängt
- **Abbruch, der greift**, auch mitten in der Übertragung
- **Liquid Glass** durchgehend, mit transparenter Titelleiste und Fenster, das sich
  dem Inhalt anpasst

## Voraussetzungen

| | |
|---|---|
| macOS | 26.0 oder neuer (Apple Silicon) |
| Switch | Custom Firmware mit [Atmosphère](https://github.com/Atmosphere-NX/Atmosphere) |
| Konsolen-App | [Sphaira](https://github.com/ITotalJustice/sphaira) 1.0.0 oder neuer |

## Auf der Switch vorbereiten

Ohne diese drei Schritte passiert nichts, und die App kann das nicht für dich tun:

1. **Optionen → Install Options → „Enable sysmmc"** einschalten. Installieren ist in
   Sphaira ab Werk deaktiviert — das ist die häufigste Ursache dafür, dass scheinbar
   gar nichts geschieht.
2. **„Install location"** auf die SD-Karte stellen, falls die Titel nicht in den
   internen Speicher sollen.
3. **MTP ausschalten** und **USB Install starten**. MTP und USB-Installation belegen
   dieselbe Schnittstelle und blockieren sich gegenseitig.

Zeigt Sphaira „Warten auf USB Verbindung…", ist die Konsole bereit.

## Bauen

```bash
brew install libusb
open "Sphaira Connect.xcodeproj"
```

libusb wird **statisch** gelinkt, die fertige App braucht Homebrew also nicht.
Der Pfad steht in `OTHER_LDFLAGS`; auf Intel-Macs liegt die Bibliothek unter
`/usr/local` statt `/opt/homebrew` und muss dort angepasst werden.

Tests laufen in einem eigenständigen SwiftPM-Paket, das die Kernlogik per Symlink
einbindet:

```bash
cd SphairaCoreTests && swift test
```

## Aufbau

```
Sphaira Connect/
  Core/        Reine Logik — Protokoll, CRC32C, Fortschritt, Dateiauswahl
  USB/         libusb-Anbindung und Protokoll-Zustandsautomat
  Shared/      Designsystem (Liquid Glass, Tokens, Fenstersteuerung)
  Features/    Ansichtsmodell und SwiftUI-Oberfläche
```

`Core/` hat bewusst weder SwiftUI- noch libusb-Abhängigkeit. Nur deshalb lässt sich
die Protokoll- und Fortschrittslogik ohne Konsole und ohne Xcode-Testtarget prüfen.

Ausführliche Dokumentation liegt im `.wiki/`-Ordner (lesbar mit dem `wiki`-CLI oder
direkt als Markdown).

## Das Protokoll

Sphaira spricht ein eigenes, CRC32C-gesichertes Paketformat. Sechs 32-Bit-Werte,
little-endian, das letzte Feld sichert die ersten fünf ab:

```
magic ("SPH0") | arg2 | arg3 | arg4 | arg5 | crc32c
```

Die Konsole fordert Datenbereiche aktiv an — auch quer über die Datei und nicht
der Reihe nach. Wer daraus einen Fortschrittsbalken bauen will, darf deshalb
**nicht** die höchste angefragte Position hochzählen: Bei einer XCI liest Sphaira
früh Partitionsdaten nahe dem Dateiende, und der Balken stünde sofort auf 100 %.
Gezählt werden die tatsächlich gesendeten Bytes.

Details stehen in `.wiki/articles/` und in `Core/SphairaProtocol.swift`.

## Bekannte Stolpersteine

| Symptom | Ursache |
|---|---|
| „Zugriff verweigert" | NS-USBloader oder ein anderes Programm hält die USB-Schnittstelle noch |
| Nichts passiert, Sphaira wartet ewig | „Enable sysmmc" ist aus, oder MTP läuft parallel |
| Übertragung hängt am Anfang | Der Titel ist bereits installiert |
| „Übertragung unvollständig" | Sphaira hat die Datei verworfen, meist wegen ungültigem Kopfsatz |

Ausführlicher steht das in
[`.wiki/articles/operations/troubleshooting.md`](.wiki/articles/operations/troubleshooting.md).

## Vergleich mit dem Python-Skript

| | `usb_install.py` | Sphaira Connect |
|---|---|---|
| Voraussetzung | Python, venv, pyusb | keine |
| Eingabe | genau ein Pfad als Argument | Drag-and-drop, beliebig viele |
| Fortschritt | keiner | zwei Balken, Durchsatz, Restzeit |
| Abbruch | Strg-C wirkt verzögert | jederzeit |
| Bereits installierter Titel | hängt kommentarlos | wird gemeldet |
| Sprache | Englisch | Deutsch und Englisch |

## Lizenz

**GPL-3.0** — siehe [LICENSE](LICENSE).

Das ist keine freie Wahl, sondern folgt aus den Abhängigkeiten. Die
Protokollimplementierung ist aus `tools/usb_install.py` von
[Sphaira](https://github.com/ITotalJustice/sphaira) (GPL-3.0) abgeleitet, und das
statisch gelinkte [libusb](https://libusb.info) steht unter LGPL-2.1-or-later.
GPL-3.0 ist mit beidem verträglich. [NS-USBloader](https://github.com/developersu/ns-usbloader)
steht aus demselben Grund unter GPL-3.0.

## Dank

- [ITotalJustice](https://github.com/ITotalJustice) für Sphaira und für `usb_install.py`,
  ohne das die Protokollarbeit deutlich mühsamer gewesen wäre
- [libusb](https://libusb.info) für den USB-Unterbau
- [Atmosphère](https://github.com/Atmosphere-NX/Atmosphere) als Grundlage von allem

## Hinweis

Sphaira Connect überträgt Dateien über USB. Was übertragen wird, verantwortest du
selbst — sichere nur Software, die du besitzt, und beachte die Rechtslage in deinem
Land. Das Projekt steht in keiner Verbindung zu Nintendo.
