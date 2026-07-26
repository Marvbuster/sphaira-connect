# Sphaira Connect

**Native macOS-App für Sphaira-USB-Installationen und manuelle RCM-Payload-Injektion auf der Nintendo Switch.**

[![Plattform](https://img.shields.io/badge/Plattform-macOS%2026%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.3-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Lizenz](https://img.shields.io/badge/Lizenz-GPL--3.0-blue)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-62%20grün-brightgreen)](SphairaCoreTests)
[![Sprachen](https://img.shields.io/badge/Sprachen-DE%20%7C%20EN-lightgrey)](Sphaira%20Connect/Localizable.xcstrings)

*[English version](README.md)*

Sphaira hat mit Version 1.0.0 sein USB-Protokoll von Tinfoil auf ein eigenes
umgestellt ([Issue #249](https://github.com/ITotalJustice/sphaira/issues/249)).
Seitdem funktionieren NS-USBloader, Fluffy und frhop nicht mehr damit — der
einzige verbliebene Weg war das mitgelieferte Python-Skript `tools/usb_install.py`.
Sphaira Connect ist dessen native Entsprechung: eine echte macOS-App mit
Warteschlange, Fortschrittsanzeige und Protokoll, ohne Python-Umgebung.

---

## Download

Fertige Versionen liegen unter **[Releases](../../releases)**.

Die App ist **ad-hoc signiert** — sie trägt keine Developer-ID und ist nicht
notarisiert, Gatekeeper verweigert beim ersten Start also den Dienst. Einmal
Rechtsklick → „Öffnen", danach merkt macOS sich die Entscheidung. Wer einem Binary
von Fremden nicht traut, baut es selbst; das ist ein Befehl und etwa eine Minute.

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
- **RCM-Payload-Injektion** für `.bin`-Dateien wie Hekate oder Fusée, mit genauer
  APX-Erkennung, Fortschritt und ausschließlich manueller Auslösung
- **Persistente Hekate- und Fusée-Presets**; für beide stehen die aktuelle und
  vier ältere offizielle Versionen direkt zur Wahl, eigene `.bin` bleiben möglich
- **Abbruch, der greift**, auch mitten in der Übertragung
- **Liquid Glass** durchgehend, mit transparenter Titelleiste und Fenster, das sich
  dem Inhalt anpasst

## Voraussetzungen

| | |
|---|---|
| macOS | 26.0 oder neuer (Apple Silicon) |
| Switch | Custom Firmware mit [Atmosphère](https://github.com/Atmosphere-NX/Atmosphere); für RCM-Injektion eine ungepatchte Erista/V1 |
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

## RCM-Payload injizieren

1. Eine ungepatchte V1-Switch in RCM versetzen und per USB verbinden. Der Bildschirm
   bleibt in RCM schwarz; die App erkennt das separate APX-Gerät als `0955:7321`.
2. **RCM-Payload** auswählen und eine `.bin`-Datei wie Hekate oder Fusée wählen oder
   ablegen.
3. **Payload injizieren** drücken. Weder Dateiauswahl noch Geräteverbindung starten
   jemals automatisch eine Injektion.

Die Payload selbst wird nicht mitgeliefert. Das Download-Menü der Hekate-Karte
lädt auf expliziten Klick die aktuelle oder eine der vier vorherigen stabilen
Standard-Payloads aus den offiziellen
[CTCaer/hekate-Releases](https://github.com/CTCaer/hekate/releases). Die App prüft
Dateigröße und, sofern veröffentlicht, die SHA-256-Prüfsumme. Gepatchte
V1-Geräte und spätere Switch-Revisionen können RCM erreichen, sind aber nicht für
Fusée Gelée anfällig.

Die Preset-Karten für Hekate und Fusée merken sich lokale Dateipfade über
App-Starts hinweg. Über Plus beziehungsweise Stift wird weiterhin jede eigene
`.bin` zugewiesen oder ersetzt; auch Download und Preset-Auswahl injizieren erst
nach **Payload injizieren**.

Das Fusée-Menü bezieht `fusee.bin` direkt aus den offiziellen
[Atmosphère-Releases](https://github.com/Atmosphere-NX/Atmosphere/releases) und
prüft ebenfalls Dateigröße sowie eine veröffentlichte SHA-256-Prüfsumme.

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

Ausführliche Dokumentation liegt im `.wiki/`-Ordner als reines Markdown.

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
| „Übertragung unvollständig" / Eintrag „übersprungen" | Sphaira hat die Datei nach wenigen Kilobyte geschlossen — meist weil der Titel schon installiert ist, sonst weil es sie verworfen hat |

Zum letzten Punkt: Die beiden Fälle sind **auf dem Draht nicht unterscheidbar**.
Sphaira schickt denselben Abschluss-Befehl, egal ob es ein Duplikat überspringt oder
eine fehlerhafte Datei verwirft. Die App meldet deshalb den belegbaren Sachverhalt
und nennt beide Möglichkeiten, statt eine Ursache zu raten.

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

## Open Source, ohne Agenda

Sphaira Connect ist GPL-3.0, Punkt — keine geschlossenen Extras, keine Telemetrie
und kein Lizenz-Kleingedrucktes oder README-Manifest über die vier Freiheiten der
GPL hinaus. Das hier ist ein USB-Werkzeug für das Sphaira-Homebrew-Ökosystem, keine
Bühne: es knüpft Nutzung, Forken oder Weiterverbreitung an keinerlei politische oder
ideologische Bedingungen — und wird das auch nie tun.

## Fremde Bestandteile

Ausführlich in [NOTICE.md](NOTICE.md).

- **Grafik des App-Symbols:** „nintendo switch" von **Mikicon**,
  [Noun Project](https://thenounproject.com/browse/icons/term/nintendo-switch/),
  lizenziert unter [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) —
  bearbeitet (Beschriftung entfernt, neu zentriert, umgefärbt)
- **libusb** — LGPL-2.1-or-later, statisch gelinkt
- **Protokollimplementierung** — abgeleitet aus `usb_install.py` von Sphaira, GPL-3.0
- **RCM-Implementierung** — basiert auf dem öffentlichen Fusée-Gelée-Protokoll und
  wurde durch [ironfoil](https://github.com/sermuns/ironfoil) informiert,
  Apache-2.0/MIT

## Dank

- [ITotalJustice](https://github.com/ITotalJustice) für Sphaira und für `usb_install.py`,
  ohne das die Protokollarbeit deutlich mühsamer gewesen wäre
- [Mikicon](https://thenounproject.com/mikicon/) für die Konsolengrafik
- [libusb](https://libusb.info) für den USB-Unterbau
- [Atmosphère](https://github.com/Atmosphere-NX/Atmosphere) als Grundlage von allem
- [ironfoil](https://github.com/sermuns/ironfoil) für seine klare, kompakte
  RCM-Implementierung als Referenz

## Hinweis

Sphaira Connect überträgt Dateien über USB. Was übertragen wird, verantwortest du
selbst — sichere nur Software, die du besitzt, und beachte die Rechtslage in deinem
Land. Das Projekt steht in keiner Verbindung zu Nintendo.
