# Sphaira Connect macOS v1.2 Build 1

**Date:** 2026-07-26 | **Status:** Done | **Minimum macOS:** 26.5
**MARKETING_VERSION:** 1.2 | **CURRENT_PROJECT_VERSION:** 1
**Commit:** `PENDING` — *large remaining-time countdown, extracted view files*

## Summary

Adds a large, prominent remaining-time countdown while either mode is actively running — a
transfer in Sphaira Install, or an injection in RCM Payload. RCM injection did not previously
track throughput at all; it now feeds the same `Core/ProgressTracker` the installer uses.
`RootView.swift` was split further to stay under the 400-line contract limit as part of this work.

Caught in local testing before this ever shipped: the first pass placed the badge as a floating
overlay (it covered the mode switcher instead of the window growing to fit it), and animated its
raw, per-tick value directly — since a fresh sample arrives roughly every 100 ms but each animation
takes 300 ms, the badge never finished one transition before the next one interrupted it, looking
restless for the entire transfer rather than just at the start. Both are fixed below.

## Features & Changes

| Type | Description |
|------|-------------|
| FEATURE | Large remaining-time countdown, part of the normal content layout above the mode switcher (the window grows to fit it, exactly like the queue or the progress panel) whenever a transfer or injection is actively running — `.monospacedDigit()` plus `.contentTransition(.numericText(countsDown: true))` for the native counting-down digit animation (`Features/Views/CountdownBadgeView.swift`, `Features/Views/RootView.swift`) — see [[ui/window-and-views]] |
| FEATURE | The displayed countdown value refreshes at most once a second (`RootView.refreshCountdown(with:)`), decoupled from the underlying ~100 ms sample rate, so each animation has time to settle instead of being interrupted by the next one — a real "clock ticking down" instead of a scrubbing number. The raw per-tick estimate is additionally withheld (shown as an en dash) until `ProgressTracker.tickCount` reaches 3, so the exponential smoothing has a moment to settle before anything is displayed at all (`Core/ProgressTracker.swift`, `Features/Views/RootView.swift`) — see [[protocol/progress-tracking]] |
| FEATURE | RCM injection now computes throughput: `RCMInjectorModel.inject()` feeds `RCMTransport`'s cumulative `(sent, total)` callback into a `Core/ProgressTracker`, the same tracker and smoothing the installer already used (`Features/RCMInjectorModel.swift`) — see [[protocol/progress-tracking]] |
| CHANGE | `RootView`'s mode switcher (segmented Sphaira Install / RCM Payload picker with its matched-geometry highlight) extracted into `ModeSwitcherView` to keep `RootView.swift` under the 400-line limit from `CONTRACT.md` (`Features/Views/ModeSwitcherView.swift`) |

## Tests

63 tests passing (was 62) — adds `tickCountCountsEmissions` to `ProgressTrackerTests`. The rest of
this feature sits in the SwiftUI/Features layer, outside the `SphairaCoreTests` boundary (see
[[operations/testing-strategy]]); verified via a clean Debug and Release build. Not yet
re-confirmed against real hardware.
