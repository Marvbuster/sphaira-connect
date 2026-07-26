---
project_name: "Sphaira Connect"
wiki_root: ".wiki"
article_dir: "articles"
inbox_dir: "_inbox"
archive_dir: "_archive"
default_language: "en"
auto_index: true
auto_crosslink: true
categories:
  - architecture
  - protocol
  - usb
  - ui
  - operations
tech_stack:
  - libusb
  - macos
  - swift
  - swift-testing
  - swiftpm
  - swiftui
  - usb
  - xcode

---

# Wiki Configuration

Sphaira Connect is a native macOS app (SwiftUI, macOS 26.5) that transfers NSP/XCI/NSZ/XCZ files
over USB to the Sphaira homebrew app on a Nintendo Switch, replacing the Python script
`usb_install.py`. This wiki documents the module boundaries, the SPH0 wire format and its session
flow, the libusb layer, the user interface and day-to-day operations.

## Categories

| Category | Scope |
|----------|-------|
| `architecture` | Module boundaries (Core/USB/Shared/Features), concurrency and cancellation, queue and data model |
| `protocol` | SPH0 wire format, CRC32C, commands, install-session state machine, progress calculation |
| `usb` | libusb binding, device discovery, endpoints, timeouts, connection teardown |
| `ui` | Design system (Liquid Glass, tokens), window behaviour, SwiftUI views |
| `operations` | Xcode build settings, testing strategy, release-notes workflow, troubleshooting |

## Code Roots

- App: `Sphaira Connect/` (SwiftUI, macOS 26.5, wired in via `PBXFileSystemSynchronizedRootGroup`)
  - `Core/` — pure logic, no SwiftUI and no USB dependency
  - `USB/` — libusb binding and protocol state machine, `nonisolated` throughout
  - `Shared/` — design system
  - `Features/` and `Features/Views/` — view model and SwiftUI views
- Contract: `CONTRACT.md` (binding interface contract, single source of truth for signatures)
- Tests: `SphairaCoreTests/` (standalone SwiftPM package, `Sources/SphairaCore` is a symlink to `Sphaira Connect/Core`)
- Project file: `Sphaira Connect.xcodeproj/project.pbxproj` (single source of truth for `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`)

## Conventions

- File names: kebab-case (e.g. `sph0-wire-protocol.md`)
- One self-contained topic per file (max. 400 lines, target 100–250)
- Frontmatter is mandatory (`title`, `created`, `updated`, `category`, `tags`, `status`, `related`, `code_refs`)
- Mermaid diagrams preferred for flows and state machines
- Code paths relative to the project root (`Sphaira Connect/USB/InstallSession.swift`, never absolute)
- Cross-references are bidirectional (if A → B, then B → A in `related`)
- Language: English for the wiki prose; identifiers, field names and constants stay as they appear in code
- Coloured boxes in Mermaid always use black text (`color:#000`)
- No claim about code that has not been read — every statement must be backed by a `code_ref`

## Article Lifecycle

| Status | Meaning |
|--------|---------|
| `current` | Active and up to date |
| `draft` | Work in progress |
| `stale` | Needs review |
| `archived` | Obsolete, moved to `_archive/` |

## Project Rules (from CONTRACT.md)

- Target platform macOS 26.5, Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
  → anything that touches USB or blocks is explicitly `nonisolated` and/or `@unchecked Sendable`
- App Sandbox off, Hardened Runtime on; libusb statically linked, bridging header in place
- The project file is **not** touched when files are added (file-system-synchronized group)
- Code comments and user-facing strings are German, identifiers are English
- No source file over 400 lines
- Changes to the session flow or the wire format: **always check** `CONTRACT.md` first,
  then update the articles under `protocol/`

## Versioning and Release Notes

- `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Sphaira Connect.xcodeproj/project.pbxproj`
  are the single source of truth for version and build number
- Release notes live in the project under `release_notes/v{VERSION}/build_{N}.md`
  (one file per build, since there is only one platform), plus a `README.md` per version folder
  and a top-level `release_notes/README.md`
- Wrap procedure: determine the changes since the last release commit, decide the version/build bump
  in the pbxproj (new features = minor, fixes only = patch), write the build notes and README
  tables, update the affected wiki articles including their `code_refs` and `updated` date
  (a mandatory part of every wrap), then commit following the pattern
  `chore: v{VERSION} (Build {N}) — {summary}`
