# Sphaira Connect macOS v1.1 Build 3

**Date:** 2026-07-26 | **Status:** Done | **Minimum macOS:** 26.5
**MARKETING_VERSION:** 1.1 | **CURRENT_PROJECT_VERSION:** 3

## Summary

Follow-up to build 2. That fix corrected the per-file `.done`/`.skipped` state but missed a second
place with the same root cause: the *progress numbers* used for the overall-session summary still
reported the raw, tolerance-short byte count. Found in the field, again — a batch of 2 files
completed with no per-file errors and a "Fertig — 2 Datei(en) übertragen" log line, yet the main
view kept showing a warning triangle and "Transfer incomplete".

## Features & Changes

| Type | Description |
|------|-------------|
| FIX | `emitProgress(force: true)` reported `tracker.clampedSent` — short by up to `completionTolerance` bytes for a file that succeeded within that margin — as `itemSent`/`overallSent`. The last progress snapshot of a batch's final file is never superseded by a later update, so `ProgressPanelView.isComplete` (`overallSent >= overallTotal`, no tolerance) kept reading the session as incomplete even though every file had actually finished. `emitProgress` now accepts a `sentOverride`, reporting the file's full size once it's known to have succeeded instead of the raw clamped count (`USB/InstallSession.swift`) — see [[protocol/progress-tracking]] and [[operations/troubleshooting]], case 10 |

## Tests

62 tests passing, unchanged — outside the `SphairaCoreTests` boundary, same as build 2 (see
[[operations/testing-strategy]]); verified via a clean Debug and Release build. Not yet
re-confirmed against real hardware.
