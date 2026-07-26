---
title: "Window and Views — RootView, WindowStyleConfigurator and the View Building Blocks"
created: 2026-07-26
updated: 2026-07-26
category: ui
tags: [swiftui, appkit, nswindow, rootview, views, layout]
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

# Window and Views

The interface has no navigation, no tabs and no second screen — it is **one** window that fits its size to the content and its base color to the phase of the transfer. The assembly lives entirely in `RootView`; the window itself is configured by `WindowStyleConfigurator`, an `NSViewRepresentable` with no visible content. The five building blocks below it (drop zone, queue, progress, log, status indicator) are pure presentation: they take values in and hand actions back out as closures.

## RootView — the ZStack

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

    // Configures the NSWindow and makes it follow the content with an animation.
    WindowStyleConfigurator(sizeKey: sizeKey)
        .allowsHitTesting(false)
        .frame(width: 0, height: 0)
}
```

Four layers from bottom to top: desktop blur, state color, content, window configuration. The building blocks of the first two layers are described in [[ui/design-system-liquid-glass]].

`WindowStyleConfigurator` sits in the stack as a 0×0 view with hit testing switched off. That is the usual way to reach the surrounding `NSWindow` from SwiftUI without changing the view hierarchy.

The state color comes from a single computed property:

```swift
private var backgroundTint: Color {
    switch model.phase {
    case .transferring, .waitingForSwitch: Colors.backgroundTintActive
    case .failed: Colors.backgroundTintError
    case .idle, .finished: Colors.backgroundTint
    }
}
```

Note that `.finished` gets the calm blue back, not the green. The green signals **activity**, not success — for success there is the footnote in the action bar and the green check mark in the progress panel. `.waitingForSwitch` shares its color with `.transferring`, because from the user's point of view the waiting is already part of the running transfer.

## Header and status indicator as overlays

Because the title bar is transparent and the content reaches up underneath it, the title and the status indicator do not live in the content stack but as overlays with a negative offset in the title-bar zone:

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

The `padding(.leading, 80)` keeps clear of the traffic-light buttons, which `WindowStyleConfigurator` deliberately leaves visible. The title is `accessibilityHidden` — it is decoration, and the window name is in the window list anyway.

`StatusPill` shows a dot plus text and switches with an animation (`.easeInOut(duration: 0.35)`) between green (connected, with a glow via `shadow`) and translucent white (not connected). The text has three tiers: the device summary from the running session, otherwise "Switch verbunden", otherwise "Keine Switch". For assistive technology, `accessibilityLabel("Verbindungsstatus: \(text)")` combines both.

## The sizeKey

```swift
private var sizeKey: String {
    "\(model.items.count)-\(showsProgress)-\(model.isLogExpanded)-\(model.isBusy)"
}
```

This is the trigger for resizing the window: exactly the four states that change the height of the content. The string itself is meaningless — only its **change** counts. Deliberately not included are progress values, log lines and phase changes without layout consequences; otherwise the window would try to re-measure itself several times per second during a transfer.

## The content and its transitions

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

The drop zone exists in both states — empty as a large area (230 pt tall), filled as a narrow strip (44 pt) below the list. After that come, conditionally, the waiting row (`ProgressView` plus a hint text, only for `.waitingForSwitch`), the progress panel, the log and the action bar.

Whether the progress panel appears is decided by:

```swift
private var showsProgress: Bool {
    switch model.phase {
    case .transferring, .finished: model.progress != nil
    default: false
    }
}
```

`.finished` is included on purpose: the final state stays on screen after the end instead of being faded out. For `.failed` and after a cancellation the panel disappears — there `InstallerModel` sets `progress` to `nil`.

Three animations are attached to the `content` block rather than to the individual parts: `items.isEmpty`, `showsProgress` and `phase`. This makes the switch between drop zone and list run as **one** movement.

## Action bar

Three buttons, each with its own rule:

| Button | Kind | Enabled when |
|---|---|---|
| `Liste leeren` (clear list) | `.clear` | entries present **and** not busy |
| `Abbrechen` (cancel) | `.red` | only visible while `model.isBusy` |
| `Installieren` (install) | `.green` | `model.canStart` |

"Abbrechen" is not disabled but faded in and out (`.transition(.opacity.combined(with: .scale(scale: 0.9)))`). To its left sits the footnote: for `.failed` the error message in red (limited to two lines), for `.finished` the number of transferred titles in green, otherwise nothing.

All three carry an `accessibilityLabel` that is more meaningful than the visible caption ("Übertragung zur Switch starten" instead of "Installieren").

## WindowStyleConfigurator

The `NSViewRepresentable` creates a private `ConfigView` that does three things.

**1. Make the title bar transparent** — on the first `viewDidMoveToWindow`:

```swift
window.titleVisibility = .hidden
window.titlebarAppearsTransparent = true
window.isOpaque = false
window.backgroundColor = .clear
window.styleMask.insert(.fullSizeContentView)
window.isMovableByWindowBackground = true
```

`isOpaque = false` and `backgroundColor = .clear` are the prerequisite for `VisualEffectBlur` being able to let the desktop show through at all. `fullSizeContentView` pulls the content up underneath the title bar — only then do the overlays above work. The traffic-light buttons are explicitly set visible again.

**2. Switch off frame persistence:**

```swift
// At launch AppKit restores the last saved frame — switch persistence
// off and fit to the content once.
window.setFrameAutosaveName("")
window.isRestorable = false
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
    self?.fitWindowToContent()
}
```

Without these three lines the app starts at the size it had when it was last quit — typically with an expanded list and an open log, even though at launch only the empty drop zone is on screen. The case is described in [[operations/troubleshooting]].

**3. Follow the content** — `refitIfNeeded(key:)` remembers the last `sizeKey`:

```swift
guard let previous = lastKey else {
    lastKey = key
    return
}
guard previous != key else { return }
lastKey = key
// Let SwiftUI settle the new layout first, then resize.
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
    self?.fitWindowToContent()
}
```

The first call only sets the key and does **not** resize — otherwise the fit from `viewDidMoveToWindow` would run twice. The 0.1 second delay is necessary because `updateNSView` runs before SwiftUI has finished computing the new layout; measuring immediately returns the old size.

The measurement itself:

```swift
// NSHostingView reports the SwiftUI ideal size via intrinsicContentSize;
// fittingSize can silently return zero.
var fitting = content.intrinsicContentSize
if fitting.width <= 100 || fitting.height <= 100 {
    fitting = content.fittingSize
}
guard fitting.width > 100, fitting.height > 100 else { return }
var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: fitting))
let old = window.frame
frame.origin = NSPoint(x: old.origin.x, y: old.maxY - frame.height) // keep the top left corner
window.setFrame(frame, display: true, animate: true)
```

Three pitfalls are baked in here: with `NSHostingView`, `fittingSize` may silently return zero (hence `intrinsicContentSize` first), implausible values below 100 pt are discarded rather than applied (otherwise the window shrinks to postage-stamp size), and the origin is recomputed against the **top left** corner, because macOS coordinates start at the bottom left — without that line the window would grow upwards instead of downwards.

The minimum width does not come from here but from `RootView`: `.frame(minWidth: 560)`.

## The building blocks

### DropZoneView

A `Button` with `.buttonStyle(.plain)`, a dashed border and `.onDrop(of: [.fileURL], isTargeted:)`. Hovering is acknowledged clearly: accent color instead of white, stroke width 2 instead of 1.5, `scaleEffect(1.015)`, symbol change via `.contentTransition(.symbolEffect(.replace))`.

One detail matters when dropping:

```swift
_ = provider.loadObject(ofClass: URL.self) { url, _ in
    guard let url else { return }
    // The provider delivers on an arbitrary queue — hop back to the MainActor.
    Task { @MainActor in deliver([url]) }
}
```

`NSItemProvider` calls its completion block on an arbitrary queue, but `onURLs` writes into the `@Observable` model. Hopping to the MainActor is mandatory, not politeness. A side effect: every dropped URL arrives individually, so `InstallerModel.add(urls:)` is called once per file and has to guard against duplicates itself — which it does.

The click path goes through `NSOpenPanel` with `canChooseDirectories = true` and `allowsMultipleSelection = true`; resolving the folders is then handled by `ItemScanner` — see [[architecture/queue-and-file-scanning]].

### QueueListView

The list computes its own height instead of leaving it to SwiftUI:

```swift
private var listHeight: CGFloat {
    let rows = CGFloat(items.count)
    let content = rows * Self.rowHeight + max(0, rows - 1) * Self.rowSpacing + Spacing.sm * 2
    return min(content, Self.maxListHeight)
}
```

With `rowHeight` 40, `rowSpacing` 2 and `maxListHeight` 320, the window therefore grows along up to about eight entries and caps after that. This is exactly why `items.count` is part of the `sizeKey`.

Every row shows a state symbol (dotted circle / spinner / green check mark / red warning triangle), the name with `truncationMode(.middle)`, on errors the cause in red underneath, the size in monospace and the remove button. The entry currently being transferred is backed with `Colors.accent.opacity(0.22)`. The remove button is disabled during the transfer and dimmed to 0.25 opacity.

### ProgressPanelView

Two bars (overall in the accent color, current file in green), a header with "x von y", below it speed, remaining time and transferred-of-total size — all in monospace so the numbers do not jitter as they count.

`isFinished` intervenes in three places: both fractions are set to `1`, the speed to `ByteFormat.rate(.nan)` (i.e. "–") and the remaining time likewise. That leaves a clean final state after the end instead of a frozen intermediate value.

The bar has a lower bound:

```swift
Capsule()
    .fill(tint.gradient)
    // Minimum width = height, so the capsule never collapses into a line.
    .frame(width: max(height, geo.size.width * fraction))
```

At 0 % a capsule with width 0 would otherwise be a visual glitch.

The counting is guarded against outliers: `min(progress.itemIndex + 1, max(totalCount, 1))` and `max(totalCount, 1)` prevent "3 von 2" and "1 von 0".

### LogConsoleView

A `DisclosureGroup` with an animated binding (`$isExpanded.animation(.snappy(duration: 0.3))`), containing a 150 pt tall `ScrollView` in monospace. Every line carries a timestamp (`hour(.twoDigits(amPM: .omitted))`, minute, second) in tertiary color and the text in secondary, with `.textSelection(.enabled)` for copying.

Auto-scrolling hangs off the line count, not the content:

```swift
.onChange(of: lines.count) {
    guard let last = lines.last else { return }
    withAnimation(.easeOut(duration: 0.2)) {
        proxy.scrollTo(last.id, anchor: .bottom)
    }
}
```

In addition, `onAppear` jumps to the end — otherwise the log would sit at the top when expanded, even though the interesting lines are at the bottom. The empty state has its own branch ("Noch keine Einträge.") so that the card does not appear as a blank area.
