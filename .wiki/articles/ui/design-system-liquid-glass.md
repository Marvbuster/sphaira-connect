---
title: "Design System — Liquid Glass, Tokens and the No-Glass-on-Glass Rule"
created: 2026-07-26
updated: 2026-07-26
category: ui
tags: [design-system, liquid-glass, swiftui, appkit, tokens, macos-26]
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

# Design System

Four files under `Sphaira Connect/Shared/` make up the entire visual vocabulary: metrics, fonts and colors as constants (`DesignTokens.swift`), two background building blocks (`GlassEffectTheme.swift`), one button (`GlassButton.swift`) and a hover modifier (`GlassInteractive.swift`). The central rule behind them is a prohibition: **glass must not be nested inside glass.** That is why there are deliberately two card backgrounds, `GlassBackground` and `connectCard`, only one of which is real glass.

## Tokens

`DesignTokens.swift` contains no logic, only constants — 37 lines, deliberately terse.

| Enum | Contents |
|---|---|
| `Spacing` | `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 24, `xxl` 32 |
| `Fonts` | `title` 24/semibold, `subtitle` 16/regular, `mono` (`.body`, `.monospaced`), `helper` 12/regular, `badge` 11/semibold |
| `Colors` | three background tints plus `accent`, `success`, `warning`, `danger` |

The state tints are the most conspicuous part of the interface — the window changes its overall mood with the phase of the transfer:

```swift
static let backgroundTint = Color(hex: 0x0B1220, alpha: 0.45)        // calm blue, base state
static let backgroundTintActive = Color(hex: 0x0E2416, alpha: 0.42)  // greenish, during the transfer
static let backgroundTintError = Color(hex: 0x2A0E12, alpha: 0.42)   // reddish, on errors
```

Three things matter about this:

- These are **very dark, very desaturated** colors — not a rich green but an almost black hint of green. The tint sits on top of the desktop blur and is meant to shift the mood, not to colorize the interface.
- All three are semi-transparent (0.42–0.45). Without alpha, the blur underneath would disappear.
- `accent`, `success`, `warning` and `danger` are deliberately the system colors (`Color.accentColor`, `.green`, `.yellow`, `.red`) — that way they follow the user's system settings and the contrast behaviour of macOS.

`Color(hex:alpha:)` is the usual decomposition into three byte channels:

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

Which tint applies when is decided by `RootView` based on the phase — see [[ui/window-and-views]].

## GlassBackground — real glass

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

The native `glassEffect` of macOS 26 does the actual work — refraction, edge highlight, adaptation to whatever is behind it. The special case `tint == .clear` prevents a transparent color from being passed in as a tint; plain `.regular` is used instead.

In this project `GlassBackground` is used in exactly **one** place: the `StatusPill` in the title-bar zone. That is precisely where it belongs — the pill floats freely above the window background and does not sit inside any other glass surface.

## VisualEffectBlur — the blur behind the window

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

The comment above it names the reason for the detour through AppKit:

> Blur behind the window — glassEffect cannot sample the desktop behind the window, NSVisualEffectView can.

That is the crucial division of labour: `glassEffect` refracts whatever lies **inside the window** behind the element. What is on the desktop behind the window pane is only seen by `NSVisualEffectView` with `blendingMode = .behindWindow`. This is why the blur forms the bottom layer of the `ZStack` in `RootView`, and why the window has to be transparent in the first place (`isOpaque = false`, `backgroundColor = .clear` in `WindowStyleConfigurator`).

`state = .active` forces the blur even when the window is not frontmost — otherwise the window would visibly "flip" whenever focus changes.

## connectCard — grouping without glass

```swift
extension View {
    // Grouping without a glass effect for areas that themselves contain glass
    // elements (glass in glass is unsupported and renders blurry)
    func connectCard(radius: CGFloat = 14, tint: Color = Colors.backgroundTint) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tint)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        )
    }
}
```

This is the practically most important rule of the design system. Nested glass is not supported by macOS; the result is not an error but a mushy, doubly refracted surface in which the contours of the inner elements smear. You only notice it once you see it — and then you go looking for the bug in the wrong place.

Instead of glass, `connectCard` therefore uses the classic combination of a color fill and `.thinMaterial`. Visually close enough, but nestable.

`connectCard` is applied to exactly the three areas that can themselves contain controls or glass surfaces:

| View | Call |
|---|---|
| `QueueListView` | `.connectCard()` (radius 14) |
| `ProgressPanelView` | `.connectCard()` (radius 14) |
| `LogConsoleView` | `.connectCard(radius: 12)` |

`DropZoneView` uses neither background but its own dashed border with a very faint fill — a drop zone should not look like a card, it should look like a hole.

## GlassButton

`GlassButton` is the project's only button. Four kinds, two sizes:

```swift
enum GlassButtonKind { case clear, green, red, orange }
enum GlassButtonSize { case compact, standard }
```

The size carries its own metrics instead of scattering them across the call sites:

| | `compact` | `standard` |
|---|---|---|
| `vPad` | 6 | 10 |
| `hPad` | 10 | 14 |
| `minHeight` | 30 | 36 |
| `font` | 13/semibold | 14/semibold |
| `spacing` | `Spacing.sm` | `Spacing.md` |

The glass itself lives in a private `ViewModifier`:

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

`.interactive()` enables the glass's native reaction to pointer and press. The tints are deliberately weak at 0.2 opacity — a green button should shimmer greenish, not be green.

Around it, four deliberate decisions:

- `.buttonStyle(.plain)` — the system style would put a second background underneath the glass.
- `.contentShape(Rectangle())` — otherwise only the text would be clickable, not the whole glass surface.
- `.disabled(!isEnabled)` **and** `.opacity(isEnabled ? 1.0 : 0.45)` — glass alone does not indicate a disabled state clearly enough.
- `isEnabled` is an ordinary parameter, not an environment value. `RootView` passes expressions such as `!model.items.isEmpty && !model.isBusy` and `model.canStart` into it.

## glassInteractive

```swift
extension View {
    func glassInteractive(radius: CGFloat = 14) -> some View
}
```

On hover, the modifier lays a white overlay at 0.08 opacity over the element and fades in a soft shadow (`radius: 10`, `y: 4`, black at 0.20). Both are switched smoothly with `.animation(.snappy(duration: 0.18), value: hovered)`.

Two details that are easy to get wrong:

- The overlay is `.allowsHitTesting(false)`. Without that it would swallow the very click it visually advertises.
- The `hovered` state lives in the modifier, not in the button. That makes `glassInteractive` applicable to arbitrary views independently of `GlassButton`.

Right now only `GlassButton` uses it (in `body`, directly after `contentShape`). `QueueRow` in `QueueListView` brings its own, different hover logic, because a table row should not cast a shadow.

## In summary: which background do I use?

| Situation | Building block |
|---|---|
| Small free-floating element above the window background | `GlassBackground` |
| Card that contains buttons, lists or other glass surfaces | `connectCard` |
| Bottom window layer (desktop blur) | `VisualEffectBlur` |
| Clickable surface | `GlassButton` or `glassInteractive` |
