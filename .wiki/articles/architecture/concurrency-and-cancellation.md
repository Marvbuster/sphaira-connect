---
title: "Concurrency and Cancellation — MainActor Default, Event Channel, CancelFlag"
created: 2026-07-26
updated: 2026-07-26
category: architecture
tags: [concurrency, mainactor, asyncstream, cancellation, sendable, threading]
status: current
related:
  - architecture/system-overview
  - protocol/install-session-flow
  - protocol/progress-tracking
  - usb/libusb-transport
  - operations/troubleshooting
code_refs:
  - Sphaira Connect/Features/InstallerModel.swift
  - Sphaira Connect/USB/InstallSession.swift
  - Sphaira Connect/USB/USBTransport.swift
---

# Concurrency and Cancellation

The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: **every type is `@MainActor`
by default** unless stated otherwise. For an app whose core job is making blocking
`libusb_bulk_transfer` calls for hours on end, that is exactly the wrong default — which is why
`Core/` and `USB/` are marked `nonisolated` almost throughout (the sole exception is
`ProgressTracker`, see Pitfalls), the session runs inside a `Task.detached`, and **every** piece of
feedback comes back through exactly one ordered `AsyncStream`. Cancellation does not go through
`Task.cancel()` but through an `NSLock`-guarded flag that the blocking loops poll between two USB
timeouts.

## The MainActor default and its consequences

Because the default is inverted, the keyword shows up in places you would otherwise never see it —
on enums, structs and constants:

```swift
nonisolated enum CRC32C { … }
nonisolated struct Packet: Equatable, Sendable { … }
nonisolated struct TransferProgress: Equatable, Sendable { … }
```

Without that `nonisolated`, `CRC32C.checksum` would be a MainActor call and simply unreachable
from `InstallSession`. For the two classes in `USB/`, `nonisolated` alone is not enough, because
they hold mutable state:

```swift
final class USBTransport: @unchecked Sendable {
    nonisolated(unsafe) private var context: OpaquePointer?
    nonisolated(unsafe) private var handle: OpaquePointer?
```

`@unchecked Sendable` is a promise to the compiler that the caller has to keep: **one
`USBTransport` instance belongs to exactly one thread.** In this project that holds — the instance
is created in `InstallerModel.start()`, handed to the session immediately and from then on used
only from its detached task. `isSwitchAttached()` is `static` and opens its own libusb context, so
it shares nothing.

## Session start: `Task.detached`, no model reference

```swift
Task.detached(priority: .userInitiated) {
    defer { continuation.finish() }
    do {
        try session.run(
            onLog: { continuation.yield(.log($0)) },
            …
            cancel: { flag.isSet() }
        )
        continuation.yield(.finished(transferred: doneCounter.value()))
    } catch InstallError.cancelled {
        continuation.yield(.cancelled)
    } catch { … }
}
```

`Task.detached` — not `Task { }` — because a plain `Task` in a `@MainActor` context inherits the
isolation, and the main thread would then be tied up for the entire transfer. Equally important:
**the session holds no reference to `InstallerModel`.** It only writes into the continuation. That
rules out both a reference cycle and the temptation to read MainActor state from the USB thread.

## One channel instead of many tasks

The obvious approach would have been to send each callback back as a `Task { @MainActor in … }`.
That is wrong, and the comment in the code says why:

```swift
/// Feedback from the session. It travels through exactly one ordered channel
/// so that progress and log lines do not arrive out of order — individual
/// unstructured tasks guarantee no ordering.
fileprivate enum SessionEvent: Sendable { … }
```

Unstructured tasks are not executed in creation order. In practice that would mean: "file X done"
appears before "transferring X …", or a stale progress snapshot overwrites a newer one. The
`AsyncStream` with `bufferingPolicy: .unbounded` solves both — ordering is guaranteed, and the USB
thread never blocks on a full buffer (a `yield` into an unbounded stream returns immediately). The
consumer side is a single loop:

```swift
eventTask = Task { @MainActor [weak self] in
    for await event in stream {
        self?.apply(event)
    }
    // The stream ended without a completion event arriving.
    guard let self, self.isBusy else { return }
    self.progress = nil
    self.phase = .idle
    self.appendLog("Sitzung ohne Abschlussmeldung beendet.")
}
```

The fallback after the loop is not decoration: `continuation.finish()` sits in the detached task's
`defer` and therefore fires **always**, including on paths that delivered no completion event.
Without this branch the UI would stay stuck on "running" with "Cancel" still active even though
nothing is happening any more.

## `CancelFlag` and `DoneCounter` — why two tiny classes with `NSLock`

```swift
fileprivate nonisolated final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    func isSet() -> Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
```

The `cancel` closure is called **synchronously from the USB thread**, in the middle of a blocking
loop. It must therefore contain no `await` and read no MainActor state — otherwise the USB thread
would wait on the main thread while that one is possibly waiting on USB results. A boolean behind
an `NSLock` is the smallest construction that satisfies this.

`DoneCounter` solves a related problem: the number of completed files is incremented **on the
session thread**, right inside the `onItemState` callback, before the event goes into the stream:

```swift
onItemState: { index, state in
    if state == .done { doneCounter.increment() }
    continuation.yield(.itemState(index: index, state: state))
},
```

That way the value is already final when `.finished(transferred:)` is created — the completion
message does not depend on whether the MainActor side has processed the preceding events yet.

## The cancellation path

Cancellation is not `Task.cancel()`, because the session is not suspended at `await` points but
inside C calls. Instead every blocking loop checks the flag between two timeouts:

| Site | Timeout | Behaviour |
|---|---|---|
| `USBTransport.open` | 250 ms `usleep` between open attempts | `cancel()` → `close()` + `InstallError.cancelled` |
| `USBTransport.read` (private) | `readTimeoutMS = 500` | `LIBUSB_ERROR_TIMEOUT` (−7) is **not an error**, just the opportunity to check `cancel` |
| `USBTransport.write` | `writeTimeoutMS = 5_000` | same; more generous because a block is in flight |

```swift
if code == 0 || code == Self.errorTimeout {
    // Even on a timeout, partial bytes may have arrived.
    received += Int(transferred)
}
```

That line is the actual trick: a timeout is booked as partial progress, not as an abort. This is
why `read(count:)` keeps reading until the requested bytes are fully there — a packet that
trickles in across a timeout boundary is not lost. Practical consequence for the user: a
cancellation takes effect within roughly 500 ms while reading, but in the worst case only after
about 5 s while writing. The libusb side of this is covered in [[usb/libusb-transport]].

What is thrown is always `InstallError.cancelled`; `InstallerModel` catches that separately and
reports `.cancelled` instead of `.failed`, so that a deliberate cancellation does not look like a
failure.

## `close()` returns immediately

```swift
DispatchQueue.global(qos: .utility).async {
    if let openHandle {
        if wasClaimed { _ = libusb_release_interface(openHandle, 0) }
        libusb_close(openHandle)
    }
    if let openContext { libusb_exit(openContext) }
}
```

`close()` sits in the `defer` of `InstallSession.run` — so it runs immediately before the
completion message. If the Switch has already torn down the connection on its side, `libusb_close`
and `libusb_exit` can block; the transfer would then look like it is "running" forever even though
it is done. That is why `close()` first clears its own references (`handle = nil`, `context = nil`,
so a second call does not free anything twice) and pushes the actual teardown onto a background
queue.

## Device monitoring

`startMonitoring()` polls every two seconds for a Switch on the bus. The loop lives on the
MainActor (it writes `switchAttached`), the blocking part does not:

```swift
let attached = await Task.detached(priority: .utility) {
    USBTransport.isSwitchAttached()
}.value
```

`isSwitchAttached()` sets up and tears down its own libusb context every time and is therefore
short-lived, but blocking nonetheless. A `Task.isCancelled` check before the write and a
`catch break` around the `Task.sleep` make sure that `stopMonitoring()` (called from
`RootView.onDisappear`) takes effect cleanly.

## Pitfalls

- **New code in `Core/` without `nonisolated`** is automatically MainActor-isolated. In the
  project's Swift 5 language mode, calling it from a `nonisolated` context is only a **warning**,
  not an error — `struct ProgressTracker` (declared without `nonisolated`) is used exactly that
  way from `InstallSession.transferFile` and still compiles. Under the Swift 6 language mode this
  would become a compiler error; mark new Core types `nonisolated` explicitly for that reason.
- **Avoid `NumberFormatter` and friends.** `ByteFormat` formats by hand because its callers are
  `nonisolated`; see [[architecture/queue-and-file-scanning]].
- **No `await` in the `cancel` closure.** It is a synchronous `() -> Bool` and is called deep
  inside the USB thread.
- **Do not share `USBTransport` between tasks.** `@unchecked Sendable` switches the compiler check
  off; the single-thread promise is pure discipline.
