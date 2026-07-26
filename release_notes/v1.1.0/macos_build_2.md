# Sphaira Connect macOS v1.1 Build 2

**Date:** 2026-07-26 | **Status:** Done | **Minimum macOS:** 26.5
**MARKETING_VERSION:** 1.1 | **CURRENT_PROJECT_VERSION:** 2

## Summary

Fixes a false-positive "skipped" report for installs that actually succeeded. Found in the field:
a title with a visibly complete, successful install was reported as "the Switch requested only
4.3 GB of 4.3 GB" — both numbers identical at the display's one-decimal rounding, yet the raw byte
comparison still failed by a small margin.

## Features & Changes

| Type | Description |
|------|-------------|
| FIX | The transfer-completion check required the exact byte count (`tracker.sentBytes >= size`) with no tolerance. NSP/XCI containers pad their last entry to an alignment boundary that the Switch never explicitly requests, so a fully successful install could still fall a few hundred bytes short of the raw file size and get reported as skipped. A `completionTolerance` of 4096 bytes now absorbs this container padding while staying negligible next to a genuine skip, which is typically short by tens of megabytes or more (`USB/InstallSession.swift`) — see [[protocol/install-session-flow]] and [[operations/troubleshooting]], case 10 |

## Tests

62 tests passing, unchanged — this fix sits in `USB/InstallSession.swift`, outside the
`SphairaCoreTests` boundary (see [[operations/testing-strategy]]); verified via a clean Debug and
Release build. Not yet re-confirmed against real hardware.
