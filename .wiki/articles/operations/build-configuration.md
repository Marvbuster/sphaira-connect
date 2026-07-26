---
title: "Build Configuration — Static libusb, Bridging Header, Sandbox Off"
created: 2026-07-26
updated: 2026-07-26
category: operations
tags: [xcode, build, libusb, linker, sandbox, hardened-runtime, pbxproj]
status: current
related:
  - usb/libusb-transport
  - architecture/concurrency-and-cancellation
  - operations/testing-strategy
  - operations/troubleshooting
code_refs:
  - Sphaira Connect.xcodeproj/project.pbxproj
  - Sphaira Connect/USB/SphairaConnect-Bridging-Header.h
  - CONTRACT.md
---

# Build Configuration

Four settings decide whether this project builds and runs at all: libusb is linked **statically** from the Homebrew prefix, a bridging header makes the C interface globally visible without an `import`, the App Sandbox is **off** (no USB access otherwise) while the Hardened Runtime is on, and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` turns the basic assumption of the entire source tree upside down. On top of that comes a quirk of the project format: the source files are wired in through a `PBXFileSystemSynchronizedRootGroup`, which is why the project file may and must **not** be touched when new files are created.

All values live in `Sphaira Connect.xcodeproj/project.pbxproj` and are set identically for Debug and Release.

## Linking libusb statically

```
OTHER_LDFLAGS = (
    "$(inherited)",
    "/opt/homebrew/lib/libusb-1.0.a",
    "-framework",
    IOKit,
    "-framework",
    CoreFoundation,
    "-framework",
    Security,
);
HEADER_SEARCH_PATHS = (
    "$(inherited)",
    "/opt/homebrew/include/libusb-1.0",
);
LIBRARY_SEARCH_PATHS = (
    "$(inherited)",
    /opt/homebrew/lib,
);
```

The path to the static library is given as an **absolute path directly in `OTHER_LDFLAGS`**, not as `-lusb-1.0`. That is deliberate: with `-l` the linker would prefer the dynamic `libusb-1.0.dylib` as soon as it is on the search path — and then every machine running the app would need a Homebrew libusb installed at exactly that location. With the `.a`, the app runs standalone; the comment in the bridging header says the same thing.

The three frameworks are the dependencies of the libusb backends on macOS. A static library inevitably lacks them, because `.a` archives do not carry their dependencies — with dynamic linking you would have got them for free. Forget one and the build fails with undefined symbols, and only in the link step.

**Consequences for the build machine:** the path `/opt/homebrew` is the Apple Silicon default. On an Intel Mac (`/usr/local`) or without the `libusb` formula installed, the project does not build. `LIBRARY_SEARCH_PATHS` is set as well, but it only takes effect for `-l` references.

## Bridging header

```
SWIFT_OBJC_BRIDGING_HEADER = "Sphaira Connect/USB/SphairaConnect-Bridging-Header.h";
```

The file contains exactly one effective line — `#import <libusb.h>` — and is resolved via `HEADER_SEARCH_PATHS`. The effect: `libusb_init`, `libusb_bulk_transfer` and every other symbol are visible in **every** Swift file of the target without an `import`. This is why the top of `USBTransport.swift` only says `import Foundation`.

That is convenient and at the same time the reason for a discipline rule from `CONTRACT.md`: libusb is used exclusively inside `Sphaira Connect/USB/`. The compiler does not enforce it — it would happily compile a `libusb_open` call inside a SwiftUI view. Details on the usage are in [[usb/libusb-transport]].

## Sandbox off, Hardened Runtime on

```
ENABLE_APP_SANDBOX = NO;
ENABLE_HARDENED_RUNTIME = YES;
ENABLE_USER_SELECTED_FILES = readonly;
```

The App Sandbox only permits USB access through the `com.apple.security.device.usb` entitlement, and even with it libusb does not reliably reach a raw bulk interface on macOS. For this project — a local developer and tinkering app with no App Store ambitions — the sandbox is therefore switched off.

The Hardened Runtime nevertheless stays on. It costs nothing here (no JIT, no third-party libraries loaded, no `DYLD_` environment tricks) and is a prerequisite for notarisation later on.

`ENABLE_USER_SELECTED_FILES = readonly` describes a sandbox entitlement for user-selected files. With the sandbox off the setting has no practical effect; it stays set so the intent is documented — the app reads the selected titles and never writes back.

Signing uses `CODE_SIGN_STYLE = Automatic` with `DEVELOPMENT_TEAM` set.

## Concurrency: MainActor as the default

```
SWIFT_VERSION = 5.0;
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
SWIFT_APPROACHABLE_CONCURRENCY = YES;
SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
MACOSX_DEPLOYMENT_TARGET = 26.5;
```

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is the most consequential line in the whole file:
**every** type without an explicit annotation is bound to the main thread. For a user interface that is exactly right — you save yourself a `@MainActor` on every view model and get the data-race checking for free.

For anything that blocks, it is a trap. That is why every blocking unit, or one running on a background thread, is explicitly marked throughout the project:

- `Sphaira Connect/USB/USBTransport.swift` and `InstallSession.swift`: `final class ... : @unchecked Sendable`, every method `nonisolated`
- `Sphaira Connect/Core/`: the types carry a leading `nonisolated` (`nonisolated enum CRC32C`, `nonisolated struct Packet`, `nonisolated enum ItemScanner`, …) — the only exception is `struct ProgressTracker`, which does not carry the marker; in the Swift 5 language mode its use from the session produces only a warning ([[architecture/concurrency-and-cancellation]])

Without these markers the transfer flow would end up on the MainActor and freeze the UI for the entire duration of an XCI; how the pieces fit together in detail is described in [[architecture/concurrency-and-cancellation]]. The Core types being explicitly `nonisolated` is moreover the prerequisite for them compiling in the test package, which does not have this build setting — see [[operations/testing-strategy]].

`MACOSX_DEPLOYMENT_TARGET = 26.5` is not a convenience: the design system uses the native `glassEffect` of macOS 26.

## File-system-synchronized group

```
/* Begin PBXFileSystemSynchronizedRootGroup section */
        00A048C830155B7C00A8B128 /* Sphaira Connect */ = {
                isa = PBXFileSystemSynchronizedRootGroup;
                path = "Sphaira Connect";
                sourceTree = "<group>";
        };
/* End PBXFileSystemSynchronizedRootGroup section */
```

The target references this group via `fileSystemSynchronizedGroups`. Everything that lives under `Sphaira Connect/` in the file system is compiled automatically — there are **no** per-source-file `PBXBuildFile` entries and no `PBXFileReference` other than the one for the built product.

The practical rule that follows, verbatim from `CONTRACT.md`:

> Files live under `Sphaira Connect/` and are compiled automatically via `PBXFileSystemSynchronizedRootGroup`. **Do not touch the project file.**

So a new Swift file is simply created. Anyone who instead tries to register it "properly" in `project.pbxproj` produces a duplicate compilation entry or an inconsistent project. The format requires `objectVersion = 77` and is therefore tied to newer Xcode versions.

For tools and agents this also means: a diff that changes `project.pbxproj` is a warning sign when the change is supposed to be source-only.

## Versioning

`MARKETING_VERSION` (currently `1.1`) and `CURRENT_PROJECT_VERSION` (currently `1`) in the pbxproj are, according to `.wiki/wiki.config.md`, the single source for version and build number; the release notes under `release_notes/` follow them. The Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`), so there is no second place where a version could live.

## Checklist for build failures

| Symptom | Likely cause |
|---|---|
| `'libusb.h' file not found` | `HEADER_SEARCH_PATHS` does not point at `/opt/homebrew/include/libusb-1.0`, or the formula is missing |
| Undefined symbols `_libusb_*` | The path to the `.a` in `OTHER_LDFLAGS` is wrong |
| Undefined symbols `_IOService*`, `_CF*`, `_Sec*` | One of the three frameworks is missing |
| `libusb_claim_interface` returns `-3` at runtime | Sandbox switched back on — see `accessDenied` in [[operations/troubleshooting]] |
| "Cannot find … in scope" for a freshly created type | The file lives outside `Sphaira Connect/` |
| `glassEffect` unknown | Deployment target below macOS 26 |
