# Sphaira Connect macOS v1.2 Build 1

**Date:** 2026-07-26 | **Status:** Done | **Minimum macOS:** 26.5
**MARKETING_VERSION:** 1.2 | **CURRENT_PROJECT_VERSION:** 1
**Commit:** `fc1ba26` — *large remaining-time countdown, extracted view files*

## Summary

Adds a large, prominent remaining-time countdown at the top of the window while either mode is
actively running — a transfer in Sphaira Install, or an injection in RCM Payload. It animates
smoothly on every update (SwiftUI's native counting-down digit transition) instead of just
appearing and snapping to new values. RCM injection did not previously track throughput at all;
it now feeds the same `Core/ProgressTracker` the installer uses. `RootView.swift` was split further
to stay under the 400-line contract limit as part of this work.

## Features & Changes

| Type | Description |
|------|-------------|
| FEATURE | Large remaining-time countdown overlaid at the top of the window whenever a transfer (Sphaira Install) or injection (RCM Payload) is actively running — `.monospacedDigit()` plus `.contentTransition(.numericText(countsDown: true))` for the native counting-down digit animation, gated by a single `.animation(.snappy(duration: 0.3), value: activeRemainingSeconds)` so appearing, disappearing and every tick all animate the same way (`Features/Views/CountdownBadgeView.swift`, `Features/Views/RootView.swift`) — see [[ui/window-and-views]] |
| FEATURE | RCM injection now computes throughput: `RCMInjectorModel.inject()` feeds `RCMTransport`'s cumulative `(sent, total)` callback into a `Core/ProgressTracker`, the same tracker and smoothing the installer already used (`Features/RCMInjectorModel.swift`) — see [[protocol/progress-tracking]] |
| CHANGE | `RootView`'s mode switcher (segmented Sphaira Install / RCM Payload picker with its matched-geometry highlight) extracted into `ModeSwitcherView` to keep `RootView.swift` under the 400-line limit from `CONTRACT.md` (`Features/Views/ModeSwitcherView.swift`) |

## Tests

62 tests passing, unchanged — this feature sits in the SwiftUI/Features layer, outside the
`SphairaCoreTests` boundary (see [[operations/testing-strategy]]); verified via a clean Debug and
Release build. Not yet re-confirmed against real hardware.
