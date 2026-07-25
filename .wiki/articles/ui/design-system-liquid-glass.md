---
title: "Designsystem — Liquid Glass, Tokens und das Glas-in-Glas-Verbot"
created: 2026-07-26
updated: 2026-07-26
category: ui
tags: [designsystem, liquid-glass, swiftui, appkit, tokens, macos-26]
status: current
related:
  - ui/window-and-views
  - architecture/system-overview
code_refs:
  - Sphaira Connect/Shared/DesignTokens.swift
  - Sphaira Connect/Shared/GlassEffectTheme.swift
  - Sphaira Connect/Shared/GlassButton.swift
  - Sphaira Connect/Shared/GlassInteractive.swift
---

# Designsystem

Vier Dateien unter `Sphaira Connect/Shared/` bilden das gesamte visuelle Vokabular: Maße, Schriften und Farben als Konstanten (`DesignTokens.swift`), zwei Hintergrund-Bausteine (`GlassEffectTheme.swift`), ein Knopf (`GlassButton.swift`) und ein Hover-Modifikator (`GlassInteractive.swift`). Die zentrale Regel dahinter ist ein Verbot: **Glas darf nicht in Glas geschachtelt werden.** Deshalb gibt es mit `GlassBackground` und `connectCard` bewusst zwei Kartenhintergründe, von denen nur einer echtes Glas ist.

## Tokens

`DesignTokens.swift` enthält keine Logik, nur Konstanten — 37 Zeilen, bewusst knapp gehalten.

| Enum | Inhalt |
|---|---|
| `Spacing` | `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 24, `xxl` 32 |
| `Fonts` | `title` 24/semibold, `subtitle` 16/regular, `mono` (`.body`, `.monospaced`), `helper` 12/regular, `badge` 11/semibold |
| `Colors` | drei Hintergrundschleier plus `accent`, `success`, `warning`, `danger` |

Die Zustands-Hintergrundschleier sind der auffälligste Teil der Oberfläche — das Fenster wechselt seine Grundstimmung mit der Phase der Übertragung:

```swift
static let backgroundTint = Color(hex: 0x0B1220, alpha: 0.45)        // ruhiges Blau, Grundzustand
static let backgroundTintActive = Color(hex: 0x0E2416, alpha: 0.42)  // grünlich, während der Übertragung
static let backgroundTintError = Color(hex: 0x2A0E12, alpha: 0.42)   // rötlich, bei Fehlern
```

Drei Punkte sind daran wichtig:

- Es sind **sehr dunkle, sehr entsättigte** Farben — kein sattes Grün, sondern ein fast schwarzer Grünstich. Der Schleier liegt über der Schreibtisch-Unschärfe und soll die Stimmung kippen, nicht die Oberfläche einfärben.
- Alle drei sind halbtransparent (0,42–0,45). Ohne Alpha würde die Unschärfe darunter verschwinden.
- `accent`, `success`, `warning` und `danger` sind bewusst die Systemfarben (`Color.accentColor`, `.green`, `.yellow`, `.red`) — sie folgen damit der Systemeinstellung des Benutzers und dem Kontrastverhalten von macOS.

`Color(hex:alpha:)` ist die übliche Zerlegung in drei Byte-Kanäle:

```swift
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self = Color(red: r, green: g, blue: b, opacity: alpha)
    }
}
```

Wer welchen Schleier wann bekommt, entscheidet `RootView` anhand der Phase — siehe [[ui/window-and-views]].

## GlassBackground — echtes Glas

```swift
struct GlassBackground: View {
    var cornerRadius: CGFloat = 14
    var tint: Color = Colors.backgroundTint

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    private var glass: Glass {
        tint == .clear ? .regular : .regular.tint(tint)
    }
}
```

Das native `glassEffect` von macOS 26 macht die eigentliche Arbeit — Brechung, Kantenlicht, Anpassung an den Untergrund. Der Sonderfall `tint == .clear` verhindert, dass ein durchsichtiger Farbton als Tönung übergeben wird; dann kommt schlicht `.regular` zum Einsatz.

Im Projekt wird `GlassBackground` nur an **einer** Stelle benutzt: der `StatusPill` in der Titelleisten-Zone. Genau dort ist es richtig — die Pille schwebt frei über dem Fensterhintergrund und liegt in keiner anderen Glasfläche.

## VisualEffectBlur — die Unschärfe hinter dem Fenster

```swift
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .underWindowBackground
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
```

Der Kommentar darüber nennt den Grund für den AppKit-Umweg:

> Unschärfe hinter dem Fenster — glassEffect kann den Schreibtisch hinter dem Fenster nicht abtasten, NSVisualEffectView schon.

Das ist die entscheidende Arbeitsteilung: `glassEffect` bricht, was **im Fenster** hinter dem Element liegt. Was hinter der Fensterscheibe auf dem Schreibtisch steht, sieht nur `NSVisualEffectView` mit `blendingMode = .behindWindow`. Deshalb bildet der Blur in `RootView` die unterste Ebene des `ZStack`, und deshalb muss das Fenster überhaupt transparent sein (`isOpaque = false`, `backgroundColor = .clear` in `WindowStyleConfigurator`).

`state = .active` erzwingt die Unschärfe auch dann, wenn das Fenster nicht im Vordergrund ist — sonst würde das Fenster beim Fokuswechsel sichtbar „umkippen".

## connectCard — Gruppierung ohne Glas

```swift
extension View {
    // Gruppierung ohne Glaseffekt für Bereiche, die selbst Glaselemente
    // enthalten (Glas in Glas wird nicht unterstützt und rendert unscharf)
    func connectCard(radius: CGFloat = 14, tint: Color = Colors.backgroundTint) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tint)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        )
    }
}
```

Das ist die praktisch wichtigste Regel des Designsystems. Verschachteltes Glas wird von macOS nicht unterstützt; das Ergebnis ist kein Fehler, sondern eine matschige, doppelt gebrochene Fläche, bei der die Konturen der inneren Elemente verschwimmen. Man merkt es erst, wenn man es sieht — und dann sucht man den Fehler an der falschen Stelle.

Statt Glas nimmt `connectCard` deshalb die klassische Kombination aus Farbfüllung und `.thinMaterial`. Optisch nah genug, aber schachtelbar.

Angewendet wird `connectCard` auf genau die drei Bereiche, die selbst Bedienelemente oder Glasflächen enthalten können:

| Ansicht | Aufruf |
|---|---|
| `QueueListView` | `.connectCard()` (Radius 14) |
| `ProgressPanelView` | `.connectCard()` (Radius 14) |
| `LogConsoleView` | `.connectCard(radius: 12)` |

`DropZoneView` benutzt keinen der beiden Hintergründe, sondern eine eigene gestrichelte Umrandung mit sehr schwacher Füllung — eine Ablagefläche soll nicht wie eine Karte aussehen, sondern wie ein Loch.

## GlassButton

`GlassButton` ist der einzige Knopf des Projekts. Vier Ausprägungen, zwei Größen:

```swift
enum GlassButtonKind { case clear, green, red, orange }
enum GlassButtonSize { case compact, standard }
```

Die Größe trägt ihre Maße selbst, statt sie an der Aufrufstelle zu verteilen:

| | `compact` | `standard` |
|---|---|---|
| `vPad` | 6 | 10 |
| `hPad` | 10 | 14 |
| `minHeight` | 30 | 36 |
| `font` | 13/semibold | 14/semibold |
| `spacing` | `Spacing.sm` | `Spacing.md` |

Das Glas selbst liegt in einem privaten `ViewModifier`:

```swift
private var glass: Glass {
    switch kind {
    case .clear: return .regular.interactive()
    case .green: return .regular.tint(.green.opacity(0.2)).interactive()
    case .red: return .regular.tint(.red.opacity(0.2)).interactive()
    case .orange: return .regular.tint(.orange.opacity(0.2)).interactive()
    }
}
```

`.interactive()` schaltet die native Reaktion des Glases auf Zeiger und Druck ein. Die Tönungen sind mit 0,2 Deckkraft absichtlich schwach — ein grüner Knopf soll grünlich schimmern, nicht grün sein.

Drumherum vier bewusste Entscheidungen:

- `.buttonStyle(.plain)` — der Systemstil würde einen zweiten Hintergrund unter das Glas legen.
- `.contentShape(Rectangle())` — sonst wäre nur der Text klickbar, nicht die ganze Glasfläche.
- `.disabled(!isEnabled)` **und** `.opacity(isEnabled ? 1.0 : 0.45)` — Glas alleine zeigt einen gesperrten Zustand nicht deutlich genug an.
- `isEnabled` ist ein normaler Parameter, keine Umgebungsvariable. `RootView` reicht dort Ausdrücke wie `!model.items.isEmpty && !model.isBusy` und `model.canStart` hinein.

## glassInteractive

```swift
extension View {
    func glassInteractive(radius: CGFloat = 14) -> some View
}
```

Der Modifikator legt bei Hover eine weiße Überlagerung mit 0,08 Deckkraft über das Element und blendet einen weichen Schatten ein (`radius: 10`, `y: 4`, Schwarz mit 0,20). Beides wird mit `.animation(.snappy(duration: 0.18), value: hovered)` weich geschaltet.

Zwei Details, die man leicht falsch macht:

- Die Überlagerung ist `.allowsHitTesting(false)`. Ohne das würde sie den Klick abfangen, den sie visuell ankündigt.
- Der `hovered`-Zustand steckt im Modifikator, nicht im Knopf. Dadurch ist `glassInteractive` unabhängig von `GlassButton` auf beliebige Ansichten anwendbar.

Aktuell nutzt ihn nur `GlassButton` (in `body`, direkt nach `contentShape`). `QueueRow` in `QueueListView` bringt seine eigene, andersartige Hover-Logik mit, weil eine Tabellenzeile keinen Schatten werfen soll.

## Zusammengefasst: welchen Hintergrund nehme ich?

| Situation | Baustein |
|---|---|
| Freischwebendes kleines Element über dem Fensterhintergrund | `GlassBackground` |
| Karte, die Knöpfe, Listen oder andere Glasflächen enthält | `connectCard` |
| Unterste Fensterebene (Schreibtisch-Unschärfe) | `VisualEffectBlur` |
| Anklickbare Fläche | `GlassButton` bzw. `glassInteractive` |
