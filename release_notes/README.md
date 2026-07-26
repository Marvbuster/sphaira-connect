# Sphaira Connect — Release Notes

**App:** Sphaira Connect — a native macOS app that transfers NSP/XCI/NSZ/XCZ over USB to
the Sphaira homebrew app on a Nintendo Switch
**Platform:** macOS 26.5+ (SwiftUI, Swift 5 language mode, statically linked libusb)
**Author:** Marvbuster

---

## Version overview

| Version | Build | Date | Status | In brief |
|---------|-------|------|--------|----------|
| v1.0.0 | 1 | 2026-07-26 | Shipped | First release — native SPH0 protocol, queue, progress, Liquid Glass interface |
| v1.1.0 | 3 | 2026-07-26 | Shipped | RCM payload injection for unpatched Switches, official Hekate/Fusée presets with GitHub downloads |
| v1.2.0 | 1 | 2026-07-26 | Done | Large remaining-time countdown for both modes, RCM throughput tracking |

## Directory structure

```
release_notes/
├── README.md              ← this file: every version in a single sentence
└── v1.0.0/
    ├── README.md          ← builds table for this version
    └── macos_build_1.md   ← notes for exactly one build
```

One folder per version, one file per build. There is only one platform, hence only one
build file per build — the `macos_` prefix stays in the file name for clarity.

## Single source of truth: the project file

Both numbers live in `Sphaira Connect.xcodeproj/project.pbxproj` and are maintained
there and nowhere else:

| Number | Build setting | Meaning |
|--------|---------------|---------|
| Version | `MARKETING_VERSION` | Names the version folder (`release_notes/v{VERSION}/`, normalised to three components — `1.0` → `v1.0.0`) |
| Build | `CURRENT_PROJECT_VERSION` | Names the build file (`macos_build_{N}.md`) |

The current state can be checked with:

```
grep -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" "Sphaira Connect.xcodeproj/project.pbxproj" | sort -u
```

## How the numbers are raised

- **New functionality** → raise the minor (`1.0` → `1.1`), reset `CURRENT_PROJECT_VERSION`
  to `1`, new folder `release_notes/v1.1.0/` containing `macos_build_1.md`.
- **Fixes only, within a version** → increase `CURRENT_PROJECT_VERSION` by 1, add
  `macos_build_{N}.md` to the existing version folder and add one line to its `README.md`.
- **Breaking change to the USB protocol or the session flow** → raise the major and call it
  out explicitly as such in the "Summary" section of the build notes.
- Every new version also gets a line in the version overview above.

The full procedure — determine the changes, decide the bump, write the notes, run the
tests, update the wiki, commit — is described in `.claude/commands/wrap.md`.

## Types used in the build notes

| Type | Meaning |
|------|---------|
| `FEATURE` | New functionality |
| `FIX` | A bug that was fixed |
| `CHANGE` | Changed or removed behaviour without new functionality |

Entries that concern the USB protocol or the session flow additionally reference the
corresponding wiki article (e.g. `protocol/install-session-flow`).

## Possible additions later

A `features/` folder like the one in the Schnack project is not needed at the start. It
will be added once collected feature descriptions can usefully be separated from the
build notes.
