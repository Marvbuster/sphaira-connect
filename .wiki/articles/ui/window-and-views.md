---
title: "Fenster und Ansichten — RootView, WindowStyleConfigurator und die View-Bausteine"
created: 2026-07-26
updated: 2026-07-26
category: ui
tags: [swiftui, appkit, nswindow, rootview, ansichten, layout]
status: current
related:
  - ui/design-system-liquid-glass
  - architecture/system-overview
  - architecture/queue-and-file-scanning
  - operations/troubleshooting
code_refs:
  - Sphaira Connect/Features/Views/RootView.swift
  - Sphaira Connect/Shared/WindowStyleConfigurator.swift
  - Sphaira Connect/Features/Views/StatusPill.swift
  - Sphaira Connect/Features/Views/DropZoneView.swift
  - Sphaira Connect/Features/Views/QueueListView.swift
  - Sphaira Connect/Features/Views/ProgressPanelView.swift
  - Sphaira Connect/Features/Views/LogConsoleView.swift
---

# Fenster und Ansichten

Die Oberfläche hat keine Navigation, keine Tabs und keinen zweiten Bildschirm — sie ist **ein** Fenster, das seine Größe dem Inhalt anpasst und seine Grundfarbe der Phase der Übertragung. Der Zusammenbau steckt vollständig in `RootView`; das Fenster selbst wird von `WindowStyleConfigurator` konfiguriert, einem `NSViewRepresentable` ohne sichtbaren Inhalt. Die fünf Bausteine darunter (Ablage, Warteschlange, Fortschritt, Protokoll, Statusanzeige) sind reine Darstellungen: Sie bekommen Werte herein und geben Aktionen als Closures heraus.

## RootView — der ZStack

```swift
ZStack {
    VisualEffectBlur()
        .ignoresSafeArea()
    backgroundTint
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: model.phase)

    content
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.lg)

    // Konfiguriert das NSWindow und lässt es dem Inhalt animiert folgen.
    WindowStyleConfigurator(sizeKey: sizeKey)
        .allowsHitTesting(false)
        .frame(width: 0, height: 0)
}
```

Vier Ebenen von unten nach oben: Schreibtisch-Unschärfe, Zustandsfarbe, Inhalt, Fensterkonfiguration. Die Bausteine der ersten beiden Ebenen sind in [[ui/design-system-liquid-glass]] beschrieben.

`WindowStyleConfigurator` liegt als 0×0-Ansicht mit abgeschaltetem Hit-Testing im Stapel. Das ist der übliche Weg, in SwiftUI an das umgebende `NSWindow` zu kommen, ohne die Ansichtshierarchie zu verändern.

Die Zustandsfarbe kommt aus einer einzigen berechneten Eigenschaft:

```swift
private var backgroundTint: Color {
    switch model.phase {
    case .transferring, .waitingForSwitch: Colors.backgroundTintActive
    case .failed: Colors.backgroundTintError
    case .idle, .finished: Colors.backgroundTint
    }
}
```

Bemerkenswert: `.finished` bekommt wieder das ruhige Blau, nicht das Grün. Das Grün signalisiert **Aktivität**, nicht Erfolg — für den Erfolg gibt es die Fußnote in der Aktionsleiste und den grünen Haken im Fortschrittspanel. `.waitingForSwitch` teilt sich die Farbe mit `.transferring`, weil das Warten aus Sicht des Benutzers schon zur laufenden Übertragung gehört.

## Kopfzeile und Statusanzeige als Overlays

Weil die Titelleiste transparent ist und der Inhalt bis unter sie reicht, liegen Titel und Statusanzeige nicht im Inhaltsstapel, sondern als Overlays mit negativem Versatz in der Titelleisten-Zone:

```swift
.overlay(alignment: .topLeading) {
    Text("\(Text("Sphaira ").fontWeight(.medium))\(Text("Connect").fontWeight(.heavy))")
        .font(.system(size: 14))
        .fontWidth(.expanded)
        .foregroundStyle(.white.opacity(0.9))
        .padding(.leading, 80)
        .offset(y: -22)
        .accessibilityHidden(true)
}
.overlay(alignment: .topTrailing) {
    StatusPill(attached: model.switchAttached, deviceSummary: model.deviceSummary)
        .padding(.trailing, 14)
        .offset(y: -24)
}
```

Die `padding(.leading, 80)` hält Abstand zu den Ampelknöpfen, die `WindowStyleConfigurator` bewusst sichtbar lässt. Der Titel ist `accessibilityHidden` — er ist Dekoration, der Fenstername steht ohnehin in der Fensterliste.

`StatusPill` zeigt einen Punkt plus Text und wechselt animiert (`.easeInOut(duration: 0.35)`) zwischen Grün (verbunden, mit Leuchtschein über `shadow`) und weiß-transparent (nicht verbunden). Der Text ist dreistufig: die Gerätezusammenfassung aus der laufenden Sitzung, sonst „Switch verbunden", sonst „Keine Switch". Für Hilfstechnik fasst `accessibilityLabel("Verbindungsstatus: \(text)")` beides zusammen.

## Der sizeKey

```swift
private var sizeKey: String {
    "\(model.items.count)-\(showsProgress)-\(model.isLogExpanded)-\(model.isBusy)"
}
```

Das ist der Auslöser für die Fensteranpassung: genau die vier Zustände, die die Höhe des Inhalts verändern. Die Zeichenkette selbst ist bedeutungslos — nur ihre **Änderung** zählt. Bewusst nicht enthalten sind Fortschrittswerte, Protokollzeilen und Phasenwechsel ohne Layoutfolge; sonst würde das Fenster während der Übertragung mehrmals pro Sekunde nachzumessen versuchen.

## Der Inhalt und seine Übergänge

```swift
if model.items.isEmpty {
    DropZoneView(isCompact: false, isEnabled: !model.isBusy, onURLs: addAnimated)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
} else {
    QueueListView(items: model.items, isBusy: model.isBusy) { item in
        withAnimation(.snappy(duration: 0.3)) { model.remove(item) }
    }
    .transition(.opacity.combined(with: .move(edge: .top)))

    DropZoneView(isCompact: true, isEnabled: !model.isBusy, onURLs: addAnimated)
}
```

Die Ablagefläche existiert in beiden Zuständen — leer als große Fläche (230 pt hoch), gefüllt als schmale Zeile (44 pt) unter der Liste. Danach folgen bedingt die Wartezeile (`ProgressView` plus Hinweistext, nur bei `.waitingForSwitch`), das Fortschrittspanel, das Protokoll und die Aktionsleiste.

Ob das Fortschrittspanel erscheint, entscheidet:

```swift
private var showsProgress: Bool {
    switch model.phase {
    case .transferring, .finished: model.progress != nil
    default: false
    }
}
```

`.finished` ist absichtlich dabei: Der letzte Stand bleibt nach dem Ende stehen, statt weggeblendet zu werden. Bei `.failed` und nach einem Abbruch verschwindet das Panel — dort setzt `InstallerModel` `progress` auf `nil`.

Drei Animationen liegen am `content`-Block und nicht an den Einzelteilen: `items.isEmpty`, `showsProgress` und `phase`. Damit läuft der Wechsel zwischen Ablage und Liste als **eine** Bewegung ab.

## Aktionsleiste

Drei Knöpfe, jeder mit einer eigenen Regel:

| Knopf | Art | Aktiv, wenn |
|---|---|---|
| Liste leeren | `.clear` | Einträge vorhanden **und** nicht beschäftigt |
| Abbrechen | `.red` | nur sichtbar, wenn `model.isBusy` |
| Installieren | `.green` | `model.canStart` |

„Abbrechen" wird nicht gesperrt, sondern ein- und ausgeblendet (`.transition(.opacity.combined(with: .scale(scale: 0.9)))`). Links daneben steht die Fußnote: bei `.failed` die Fehlermeldung in Rot (auf zwei Zeilen begrenzt), bei `.finished` die Anzahl übertragener Titel in Grün, sonst nichts.

Alle drei tragen ein `accessibilityLabel`, das aussagekräftiger ist als die Beschriftung („Übertragung zur Switch starten" statt „Installieren").

## WindowStyleConfigurator

Das `NSViewRepresentable` erzeugt eine private `ConfigView`, die drei Dinge tut.

**1. Titelleiste transparent machen** — beim ersten `viewDidMoveToWindow`:

```swift
window.titleVisibility = .hidden
window.titlebarAppearsTransparent = true
window.isOpaque = false
window.backgroundColor = .clear
window.styleMask.insert(.fullSizeContentView)
window.isMovableByWindowBackground = true
```

`isOpaque = false` und `backgroundColor = .clear` sind die Voraussetzung dafür, dass `VisualEffectBlur` den Schreibtisch überhaupt durchscheinen lassen kann. `fullSizeContentView` zieht den Inhalt unter die Titelleiste — erst dadurch funktionieren die Overlays oben. Die Ampelknöpfe werden ausdrücklich wieder sichtbar gesetzt.

**2. Die Rahmenpersistenz abschalten:**

```swift
// AppKit stellt beim Start den zuletzt gesicherten Rahmen wieder her —
// Persistenz abschalten und einmal an den Inhalt anpassen.
window.setFrameAutosaveName("")
window.isRestorable = false
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
    self?.fitWindowToContent()
}
```

Ohne diese drei Zeilen startet die App in der Größe, die sie beim letzten Beenden hatte — typischerweise mit ausgeklappter Liste und offenem Protokoll, obwohl beim Start nur die leere Ablagefläche zu sehen ist. Der Fall ist in [[operations/troubleshooting]] beschrieben.

**3. Dem Inhalt folgen** — `refitIfNeeded(key:)` merkt sich den letzten `sizeKey`:

```swift
guard let previous = lastKey else {
    lastKey = key
    return
}
guard previous != key else { return }
lastKey = key
// Erst SwiftUI das neue Layout festschreiben lassen, dann anpassen.
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
    self?.fitWindowToContent()
}
```

Der erste Aufruf setzt nur den Schlüssel und passt **nicht** an — sonst würde die Anpassung aus `viewDidMoveToWindow` doppelt laufen. Die 0,1 Sekunden Verzögerung sind nötig, weil `updateNSView` läuft, bevor SwiftUI das neue Layout fertig gerechnet hat; ein sofortiges Messen liefert die alte Größe.

Die Messung selbst:

```swift
// NSHostingView meldet die SwiftUI-Idealgröße über intrinsicContentSize;
// fittingSize kann stillschweigend Null liefern.
var fitting = content.intrinsicContentSize
if fitting.width <= 100 || fitting.height <= 100 {
    fitting = content.fittingSize
}
guard fitting.width > 100, fitting.height > 100 else { return }
var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: fitting))
let old = window.frame
frame.origin = NSPoint(x: old.origin.x, y: old.maxY - frame.height) // obere linke Ecke halten
window.setFrame(frame, display: true, animate: true)
```

Drei Fallstricke stecken hier drin: `fittingSize` liefert bei `NSHostingView` unter Umständen kommentarlos Null (deshalb `intrinsicContentSize` zuerst), unplausible Werte unter 100 pt werden verworfen statt angewendet (sonst schrumpft das Fenster auf Briefmarkengröße), und der Ursprung wird auf die **obere linke** Ecke umgerechnet, weil macOS-Koordinaten unten links beginnen — ohne diese Zeile würde das Fenster beim Wachsen nach oben statt nach unten aufgehen.

Die Mindestbreite kommt nicht von hier, sondern aus `RootView`: `.frame(minWidth: 560)`.

## Die Bausteine

### DropZoneView

Ein `Button` mit `.buttonStyle(.plain)`, gestrichelter Umrandung und `.onDrop(of: [.fileURL], isTargeted:)`. Beim Überfahren wird deutlich quittiert: Akzentfarbe statt Weiß, Strichstärke 2 statt 1,5, `scaleEffect(1.015)`, Symbolwechsel per `.contentTransition(.symbolEffect(.replace))`.

Beim Ablegen ist ein Detail wichtig:

```swift
_ = provider.loadObject(ofClass: URL.self) { url, _ in
    guard let url else { return }
    // Der Provider liefert auf einer beliebigen Queue — zurück auf den MainActor.
    Task { @MainActor in deliver([url]) }
}
```

`NSItemProvider` ruft seinen Abschlussblock auf einer beliebigen Warteschlange auf; `onURLs` schreibt aber in das `@Observable`-Modell. Der Sprung auf den MainActor ist Pflicht, nicht Höflichkeit. Nebenwirkung: Jede abgelegte URL kommt einzeln an, `InstallerModel.add(urls:)` wird also pro Datei einmal aufgerufen und muss selbst gegen Duplikate schützen — was es tut.

Der Klickpfad geht über `NSOpenPanel` mit `canChooseDirectories = true` und `allowsMultipleSelection = true`; die Auflösung der Ordner übernimmt danach `ItemScanner` — siehe [[architecture/queue-and-file-scanning]].

### QueueListView

Die Liste rechnet ihre Höhe selbst aus, statt sie SwiftUI zu überlassen:

```swift
private var listHeight: CGFloat {
    let rows = CGFloat(items.count)
    let content = rows * Self.rowHeight + max(0, rows - 1) * Self.rowSpacing + Spacing.sm * 2
    return min(content, Self.maxListHeight)
}
```

Bei `rowHeight` 40, `rowSpacing` 2 und `maxListHeight` 320 wächst das Fenster also bis etwa acht Einträge mit und deckelt danach. Genau deswegen steht `items.count` im `sizeKey`.

Jede Zeile zeigt Zustandssymbol (gepunkteter Kreis / Spinner / grüner Haken / rotes Warndreieck), Namen mit `truncationMode(.middle)`, bei Fehlern die Ursache in Rot darunter, die Größe in Monospace und den Entfernen-Knopf. Der laufende Eintrag wird mit `Colors.accent.opacity(0.22)` hinterlegt. Der Entfernen-Knopf ist während der Übertragung gesperrt und auf 0,25 Deckkraft gedimmt.

### ProgressPanelView

Zwei Balken (Gesamt in Akzentfarbe, aktuelle Datei in Grün), Kopfzeile mit „x von y", darunter Geschwindigkeit, Restzeit und übertragene von Gesamtgröße — alles in Monospace, damit die Zahlen beim Zählen nicht springen.

`isFinished` greift an drei Stellen ein: Beide Anteile werden auf `1` gesetzt, die Geschwindigkeit auf `ByteFormat.rate(.nan)` (also „–") und die Restzeit ebenfalls. Damit bleibt nach dem Ende ein sauberer Endstand stehen statt eines eingefrorenen Zwischenwerts.

Der Balken hat eine Untergrenze:

```swift
Capsule()
    .fill(tint.gradient)
    // Mindestbreite = Höhe, damit die Kapsel nie zum Strich kollabiert.
    .frame(width: max(height, geo.size.width * fraction))
```

Bei 0 % wäre eine Kapsel mit Breite 0 sonst ein optischer Fehler.

Die Zählung ist gegen Ausreißer abgesichert: `min(progress.itemIndex + 1, max(totalCount, 1))` und `max(totalCount, 1)` verhindern „3 von 2" und „1 von 0".

### LogConsoleView

Ein `DisclosureGroup` mit animierter Bindung (`$isExpanded.animation(.snappy(duration: 0.3))`), darin ein 150 pt hoher `ScrollView` in Monospace. Jede Zeile trägt einen Zeitstempel (`hour(.twoDigits(amPM: .omitted))`, Minute, Sekunde) in tertiärer Farbe und den Text in sekundärer, mit `.textSelection(.enabled)` zum Kopieren.

Das automatische Scrollen hängt an der Zeilenzahl, nicht am Inhalt:

```swift
.onChange(of: lines.count) {
    guard let last = lines.last else { return }
    withAnimation(.easeOut(duration: 0.2)) {
        proxy.scrollTo(last.id, anchor: .bottom)
    }
}
```

Zusätzlich springt `onAppear` ans Ende — sonst stünde das Protokoll beim Aufklappen am Anfang, obwohl die interessanten Zeilen unten liegen. Der leere Zustand hat einen eigenen Zweig („Noch keine Einträge."), damit die Karte nicht als leere Fläche erscheint.
