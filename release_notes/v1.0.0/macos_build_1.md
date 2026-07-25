# Sphaira Connect macOS v1.0 Build 1

**Datum:** 26.07.2026 | **Status:** Fertig | **Minimales macOS:** 26.5
**MARKETING_VERSION:** 1.0 | **CURRENT_PROJECT_VERSION:** 1
**Commit:** `77527a1` — *feat: Sphaira Connect — native macOS-App für USB-Installation*

## Zusammenfassung

Erstes Release. Sphaira Connect ersetzt das Python-Skript `usb_install.py` durch eine
native SwiftUI-App: Sie spricht das SPH0-Protokoll direkt gegen statisch gelinktes
libusb, nimmt NSP/XCI/NSZ/XCZ per Drag-and-drop entgegen und überträgt sie an die
Homebrew-App Sphaira auf der Nintendo Switch. Die Kernlogik liegt SwiftUI- und
USB-frei unter `Sphaira Connect/Core/` und wird von einem eigenständigen
SwiftPM-Testpaket mit 52 Tests geprüft, das die Quellen per Symlink einbindet —
ohne zweite Kopie der Dateien.

Der zweite Teil des Releases sind die Korrekturen aus den ersten Praxisläufen: der
Fortschrittsbalken stand bei XCI sofort auf 100 %, die Abschlussmeldung blieb nach
Sitzungsende aus, und ein hängender Schreibvorgang machte „Abbrechen" wirkungslos.

## Features & Änderungen

| Typ | Beschreibung |
|-----|-------------|
| FEATURE | SPH0-Paketformat nativ implementiert: 24 Bytes, sechs `UInt32` little-endian, Magic `0x53504830`, CRC32C über die ersten 20 Bytes (`Core/SphairaProtocol.swift`) |
| FEATURE | CRC-32C (Castagnoli, gespiegeltes Polynom `0x82F63B78`) als tabellenbasierte, `nonisolated` Implementierung ohne Fremdbibliothek (`Core/CRC32C.swift`) |
| FEATURE | Sitzungsablauf als Zustandsautomat: Namensliste senden, danach Kommandoschleife über `open` und `quit`, Dateiblöcke auf Anfrage der Switch (`USB/InstallSession.swift`) — siehe Wiki `protocol/install-session-flow` |
| FEATURE | libusb-Anbindung mit Bulk-Transfers, Endpunkte aus der aktiven Konfiguration ermittelt, Rückfall auf `0x81`/`0x01` (`USB/USBTransport.swift`) |
| FEATURE | libusb statisch gelinkt (`/opt/homebrew/lib/libusb-1.0.a`) über Bridging-Header; App-Sandbox aus, Hardened Runtime an (`Sphaira Connect.xcodeproj/project.pbxproj`, `USB/SphairaConnect-Bridging-Header.h`) |
| FEATURE | Geräteerkennung über VID `0x057E` / PID `0x3000`, Statusanzeige pollt alle 2 Sekunden abseits des MainActors (`USB/LibUSBProbe.swift`, `Features/InstallerModel.swift`) |
| FEATURE | Warteschlange per Drag-and-drop oder Auswahldialog; Ordner werden rekursiv aufgelöst, Duplikate über den standardisierten Pfad verworfen, nur `nsp`/`xci`/`nsz`/`xcz` übernommen, Reihenfolge stabil alphabetisch (`Core/InstallItem.swift`, `Features/Views/DropZoneView.swift`) |
| FEATURE | Warteschlangenliste mit Zustand je Titel (wartet / überträgt / fertig / fehlgeschlagen), Einzelentfernung und „alle entfernen" — im laufenden Betrieb gesperrt (`Features/Views/QueueListView.swift`) |
| FEATURE | Fortschrittsanzeige mit Datei- und Gesamtanteil, geglättetem Durchsatz und geschätzter Restzeit; Aktualisierung höchstens alle 100 ms (`Core/ProgressTracker.swift`, `Features/Views/ProgressPanelView.swift`) |
| FEATURE | Deutsche Größen-, Durchsatz- und Zeitformatierung mit Dezimalkomma, ohne `NumberFormatter` (`Core/ByteFormat.swift`) |
| FEATURE | Aufklappbares Protokoll mit Zeitstempeln, begrenzt auf die letzten 500 Zeilen (`Features/Views/LogConsoleView.swift`, `Features/InstallerModel.swift`) |
| FEATURE | Abbruch jederzeit möglich: Das Abbruch-Flag ist über ein `NSLock` atomar und wird im USB-Thread zwischen den Transfers geprüft, ohne auf MainActor-Zustand zu warten (`Features/InstallerModel.swift`, `USB/USBTransport.swift`) |
| FEATURE | Deutschsprachige Fehlertexte für alle Fehlerfälle — Switch nicht gefunden, Zugriff verweigert, USB-Fehler mit Code, kurzes Paket, falsche Magic, Prüfsummenfehler, unerwarteter Befehl, unlesbare Datei, Abbruch (`Core/InstallError.swift`) |
| FEATURE | Liquid-Glass-Oberfläche mit eigenem Designsystem: Farb- und Abstands-Token, Glas-Buttons, Fenster folgt dem Inhalt animiert (`Shared/DesignTokens.swift`, `Shared/GlassButton.swift`, `Shared/WindowStyleConfigurator.swift`, `Features/Views/RootView.swift`) |
| FEATURE | Eigenständiges SwiftPM-Testpaket mit 52 Tests über Paketformat, CRC32C, Ordnerscan, Fortschritt, Formatierung und Fehlertexte; bindet `Sphaira Connect/Core/` per Symlink ein (`SphairaCoreTests/Package.swift`) |
| FIX | Fortschritt zählte die höchste von der Switch angefragte Position statt der real gesendeten Bytes — bei XCI stand der Balken dadurch sofort auf 100 %. `ProgressTracker.record` summiert jetzt nur übertragene Blöcke und klemmt auf die Dateigröße, da die Switch Bereiche mehrfach anfordern darf (`Core/ProgressTracker.swift`) |
| FIX | `close()` blockierte nach Sitzungsende und hielt die Abschlussmeldung auf, wodurch „Abbrechen" aktiv blieb. Der libusb-Abbau läuft jetzt asynchron auf einer Hintergrund-Queue, die Referenzen werden vorher gelöst (`USB/USBTransport.swift`) |
| FIX | Schreibvorgänge hatten kein Zeitlimit, ein Abbruch griff mitten im Block nicht. Bulk-Writes laufen jetzt mit 5000 ms Zeitlimit, Timeouts gelten als Gelegenheit zur Abbruchprüfung, bereits übertragene Teilbytes werden mitgezählt (`USB/USBTransport.swift`) |
| FIX | Rückmeldungen der Sitzung liefen über einzelne unstrukturierte Tasks und kamen dadurch ungeordnet an. Alle Ereignisse laufen jetzt durch genau einen `AsyncStream`, die Zahl fertiger Dateien zählt ein gesperrter Zähler auf dem Sitzungs-Thread (`Features/InstallerModel.swift`) |
| FIX | Endet der Ereignisstrom ohne Abschlussmeldung, blieb die Oberfläche auf „läuft" stehen; ein Rückfall setzt die Phase jetzt auf „bereit" und schreibt eine Protokollzeile (`Features/InstallerModel.swift`) |
| FIX | Der Gesamtfortschritt sprang über eine gescheiterte Datei hinweg — gezählt werden jetzt nur vollständig übertragene Dateien (`USB/InstallSession.swift`) |
| FIX | Bei einem Dateifehler geht ein Fehlerpaket an die Switch, die Kommandoschleife beantwortet danach den Quit-Befehl regulär; die Sitzung endet geordnet statt mit abruptem USB-Abriss (`USB/InstallSession.swift`) |
| CHANGE | Die SwiftData-Vorlage des Xcode-Templates entfällt: `Item.swift` gelöscht, `ContentView.swift` und `Sphaira_ConnectApp.swift` auf `RootView` umgestellt |
