---
title: "Build-Konfiguration — statisches libusb, Bridging-Header, Sandbox aus"
created: 2026-07-26
updated: 2026-07-26
category: operations
tags: [xcode, build, libusb, linker, sandbox, hardened-runtime, pbxproj]
status: current
related:
  - usb/libusb-transport
  - architecture/concurrency-and-cancellation
  - operations/testing-strategy
  - operations/troubleshooting
code_refs:
  - Sphaira Connect.xcodeproj/project.pbxproj
  - Sphaira Connect/USB/SphairaConnect-Bridging-Header.h
  - CONTRACT.md
---

# Build-Konfiguration

Vier Einstellungen entscheiden darüber, ob dieses Projekt überhaupt baut und läuft: libusb wird **statisch** aus dem Homebrew-Präfix gelinkt, ein Bridging-Header macht die C-Schnittstelle ohne `import` global sichtbar, die App-Sandbox ist **aus** (sonst kein USB-Zugriff) bei eingeschalteter Hardened Runtime, und `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` stellt die Grundannahme des gesamten Quelltextes auf den Kopf. Dazu kommt eine Eigenheit des Projektformats: Die Quelldateien sind über eine `PBXFileSystemSynchronizedRootGroup` eingebunden, deshalb darf und muss die Projektdatei beim Anlegen neuer Dateien **nicht** angefasst werden.

Alle Werte stehen in `Sphaira Connect.xcodeproj/project.pbxproj` und sind für Debug und Release identisch gesetzt.

## libusb statisch linken

```
OTHER_LDFLAGS = (
    "$(inherited)",
    "/opt/homebrew/lib/libusb-1.0.a",
    "-framework",
    IOKit,
    "-framework",
    CoreFoundation,
    "-framework",
    Security,
);
HEADER_SEARCH_PATHS = (
    "$(inherited)",
    "/opt/homebrew/include/libusb-1.0",
);
LIBRARY_SEARCH_PATHS = (
    "$(inherited)",
    /opt/homebrew/lib,
);
```

Der Pfad zur statischen Bibliothek steht als **absoluter Pfad direkt in `OTHER_LDFLAGS`**, nicht als `-lusb-1.0`. Das ist Absicht: Mit `-l` würde der Linker die dynamische `libusb-1.0.dylib` bevorzugen, sobald sie im Suchpfad liegt — und dann bräuchte jeder Rechner, auf dem die App läuft, ein installiertes Homebrew-libusb an genau diesem Ort. Mit der `.a` ist die App eigenständig lauffähig; genau das steht auch im Kommentar des Bridging-Headers.

Die drei Frameworks sind die Abhängigkeiten der libusb-Backends auf macOS. Sie fehlen einer statischen Bibliothek naturgemäß, weil `.a`-Archive keine Abhängigkeiten mitführen — beim dynamischen Linken hätte man sie geschenkt bekommen. Vergisst man eines, scheitert der Build mit undefinierten Symbolen erst im Linker-Schritt.

**Folgen für den Bauplatz:** Der Pfad `/opt/homebrew` ist der Apple-Silicon-Standard. Auf einem Intel-Mac (`/usr/local`) oder ohne installiertes `libusb`-Formula baut das Projekt nicht. `LIBRARY_SEARCH_PATHS` ist zusätzlich gesetzt, wirkt aber nur für `-l`-Referenzen.

## Bridging-Header

```
SWIFT_OBJC_BRIDGING_HEADER = "Sphaira Connect/USB/SphairaConnect-Bridging-Header.h";
```

Die Datei enthält genau eine wirksame Zeile — `#import <libusb.h>` — und wird über `HEADER_SEARCH_PATHS` aufgelöst. Der Effekt: `libusb_init`, `libusb_bulk_transfer` und alle anderen Symbole sind in **jeder** Swift-Datei des Ziels ohne `import` sichtbar. Deshalb steht in `USBTransport.swift` oben nur `import Foundation`.

Das ist bequem und gleichzeitig der Grund für eine Disziplinregel aus `CONTRACT.md`: libusb wird ausschließlich in `Sphaira Connect/USB/` benutzt. Der Compiler erzwingt das nicht — er würde einen `libusb_open`-Aufruf in einer SwiftUI-Ansicht anstandslos übersetzen. Details zur Nutzung stehen in [[usb/libusb-transport]].

## Sandbox aus, Hardened Runtime an

```
ENABLE_APP_SANDBOX = NO;
ENABLE_HARDENED_RUNTIME = YES;
ENABLE_USER_SELECTED_FILES = readonly;
```

Die App-Sandbox erlaubt USB-Zugriff nur über das `com.apple.security.device.usb`-Recht, und selbst damit greift libusb auf macOS nicht zuverlässig auf ein rohes Bulk-Interface zu. Für dieses Projekt — eine lokale Entwickler- und Bastelanwendung, die kein App-Store-Ziel hat — ist die Sandbox deshalb abgeschaltet.

Die Hardened Runtime bleibt trotzdem an. Sie kostet hier nichts (kein JIT, keine geladenen Fremdbibliotheken, keine `DYLD_`-Umgebungstricks) und ist Voraussetzung für eine spätere Notarisierung.

`ENABLE_USER_SELECTED_FILES = readonly` beschreibt ein Sandbox-Recht für vom Benutzer ausgewählte Dateien. Bei ausgeschalteter Sandbox hat die Einstellung keine praktische Wirkung; sie bleibt gesetzt, damit die Absicht dokumentiert ist — die App liest die ausgewählten Titel und schreibt nie zurück.

Signiert wird mit `CODE_SIGN_STYLE = Automatic` und gesetztem `DEVELOPMENT_TEAM`.

## Nebenläufigkeit: MainActor als Vorgabe

```
SWIFT_VERSION = 5.0;
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
SWIFT_APPROACHABLE_CONCURRENCY = YES;
SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
MACOSX_DEPLOYMENT_TARGET = 26.5;
```

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` ist die folgenreichste Zeile der ganzen Datei: **Jeder** Typ ohne ausdrückliche Angabe ist an den Hauptthread gebunden. Für eine Oberfläche ist das genau richtig — man spart sich `@MainActor` an jedem Ansichtsmodell und bekommt die Datenrennen-Prüfung geschenkt.

Für alles, was blockiert, ist es eine Falle. Deshalb ist im gesamten Projekt jede blockierende oder in einem Hintergrund-Thread laufende Einheit ausdrücklich markiert:

- `Sphaira Connect/USB/USBTransport.swift` und `InstallSession.swift`: `final class ... : @unchecked Sendable`, jede Methode `nonisolated`
- `Sphaira Connect/Core/`: die Typen mit vorangestelltem `nonisolated` (`nonisolated enum CRC32C`, `nonisolated struct Packet`, `nonisolated enum ItemScanner`, …) — einzige Ausnahme ist `struct ProgressTracker`, das die Markierung nicht trägt; im Swift-5-Sprachmodus erzeugt sein Gebrauch aus der Sitzung nur eine Warnung ([[architecture/concurrency-and-cancellation]])

Ohne diese Markierungen würde der Übertragungsablauf auf dem MainActor landen und die Oberfläche für die gesamte Dauer einer XCI einfrieren; wie das Zusammenspiel im Einzelnen aussieht, beschreibt [[architecture/concurrency-and-cancellation]]. Dass die Core-Typen ausdrücklich `nonisolated` sind, ist außerdem die Voraussetzung dafür, dass sie im Testpaket ohne diese Build-Einstellung übersetzen — siehe [[operations/testing-strategy]].

`MACOSX_DEPLOYMENT_TARGET = 26.5` ist keine Bequemlichkeit: Das Designsystem benutzt das native `glassEffect` von macOS 26.

## Dateisystem-synchronisierte Gruppe

```
/* Begin PBXFileSystemSynchronizedRootGroup section */
        00A048C830155B7C00A8B128 /* Sphaira Connect */ = {
                isa = PBXFileSystemSynchronizedRootGroup;
                path = "Sphaira Connect";
                sourceTree = "<group>";
        };
/* End PBXFileSystemSynchronizedRootGroup section */
```

Das Ziel referenziert diese Gruppe über `fileSystemSynchronizedGroups`. Alles, was unter `Sphaira Connect/` im Dateisystem liegt, wird automatisch kompiliert — es gibt **keine** `PBXBuildFile`-Einträge je Quelldatei und keine `PBXFileReference` außer der für das gebaute Produkt.

Praktische Regel daraus, wörtlich aus `CONTRACT.md`:

> Dateien liegen unter `Sphaira Connect/` und werden per `PBXFileSystemSynchronizedRootGroup` automatisch kompiliert. **Projektdatei nicht anfassen.**

Eine neue Swift-Datei wird also einfach angelegt. Wer stattdessen versucht, sie „ordentlich" in die `project.pbxproj` einzutragen, erzeugt einen doppelten Übersetzungseintrag oder ein inkonsistentes Projekt. Das Format setzt `objectVersion = 77` voraus und ist damit an neuere Xcode-Versionen gebunden.

Für Werkzeuge und Agenten heißt das auch: Ein Diff, der `project.pbxproj` verändert, ist bei reinen Quelltextänderungen ein Warnsignal.

## Versionierung

`MARKETING_VERSION` (aktuell `1.0`) und `CURRENT_PROJECT_VERSION` (aktuell `1`) im pbxproj sind laut `.wiki/wiki.config.md` die einzige Quelle für Versions- und Build-Nummer; die Release-Notizen unter `release_notes/` folgen ihnen. Das Info.plist wird generiert (`GENERATE_INFOPLIST_FILE = YES`), es gibt also keine zweite Stelle, an der eine Version stehen könnte.

## Prüfliste bei Build-Fehlern

| Symptom | Wahrscheinliche Ursache |
|---|---|
| `'libusb.h' file not found` | `HEADER_SEARCH_PATHS` zeigt nicht auf `/opt/homebrew/include/libusb-1.0` oder das Formula fehlt |
| Undefinierte Symbole `_libusb_*` | Pfad zur `.a` in `OTHER_LDFLAGS` stimmt nicht |
| Undefinierte Symbole `_IOService*`, `_CF*`, `_Sec*` | Eines der drei Frameworks fehlt |
| `libusb_claim_interface` liefert `-3` zur Laufzeit | Sandbox wieder eingeschaltet — siehe `accessDenied` in [[operations/troubleshooting]] |
| „Cannot find … in scope" für einen frisch angelegten Typ | Datei liegt außerhalb von `Sphaira Connect/` |
| `glassEffect` unbekannt | Deployment-Ziel unter macOS 26 |
