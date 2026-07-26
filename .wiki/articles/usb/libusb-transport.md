---
title: "libusb Binding — Transport, Device Discovery and Pitfalls"
created: 2026-07-26
updated: 2026-07-26
category: usb
tags: [libusb, usb, transport, endpoints, timeout, cancellation, nonisolated]
status: current
related:
  - protocol/install-session-flow
  - protocol/sph0-wire-protocol
  - protocol/rcm-payload-injection
  - architecture/concurrency-and-cancellation
  - operations/build-configuration
  - operations/troubleshooting
code_refs:
  - Sphaira Connect/USB/USBTransport.swift
  - Sphaira Connect/USB/LibUSBProbe.swift
  - Sphaira Connect/USB/SphairaConnect-Bridging-Header.h
  - Sphaira Connect/Features/InstallerModel.swift
---

# libusb Binding

`USBTransport` is the only place in the project where libusb's C functions are called. Everything above it (session flow, view model, user interface) sees nothing but `Packet`, `InstallError` and a `cancel` closure. The layer is small, yet it contains most of the pitfalls in the whole project: timeouts here are not errors but opportunities to cancel, partial bytes may already have been transferred even on a timeout, and the connection teardown must not happen synchronously, because libusb can block once the peer has dropped the link.

## Where it sits

```
InstallerModel  (MainActor)
      │  Task.detached
InstallSession  (nonisolated, blocking)
      │
USBTransport    (nonisolated, blocking)  ←  here
      │
libusb (statically linked, visible via the bridging header)
```

`libusb_*` is globally visible without an `import` because `Sphaira Connect/USB/SphairaConnect-Bridging-Header.h` contains exactly one line:

```c
#import <libusb.h>
```

How the library is found and statically linked is described in [[operations/build-configuration]].

The class is `final class USBTransport: @unchecked Sendable` and every method is explicitly `nonisolated`. That is not cosmetic: the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every type would be bound to the main thread by default. A blocking `libusb_bulk_transfer` on the MainActor would freeze the UI for the entire transfer — the full picture is in [[architecture/concurrency-and-cancellation]].

If you are looking for the layer **above** — packet ordering, commands, file transfer — it is in [[protocol/install-session-flow]]; the wire format itself is in [[protocol/sph0-wire-protocol]]. `USB/RCMTransport.swift` is a structural sibling of this file for an entirely different device and one-shot operation — the Tegra recovery-mode exploit, not the Sphaira installer — described in [[protocol/rcm-payload-injection]].

## Device discovery

The search is for a device with a fixed identifier:

| Constant | Value |
|---|---|
| `vendorID` | `0x057E` (Nintendo) |
| `productID` | `0x3000` (Sphaira in USB install mode) |

There are two implementations of the same search. `LibUSBProbe.isSwitchAttached()` is the original smoke test of the binding (together with `LibUSBProbe.version()`, which formats `libusb_get_version()` as `major.minor.micro`); `USBTransport.isSwitchAttached()` is the copy that the view model actually polls. According to `CONTRACT.md`, `LibUSBProbe.swift` stays unchanged — the duplication is a deliberate trade-off, not an oversight.

Both work the same way: their own `libusb_init` context, `libusb_get_device_list`, a `libusb_get_device_descriptor` for every device, a comparison of `idVendor`/`idProduct`, then `libusb_free_device_list(list, 1)` and `libusb_exit` via `defer`. So **no** device is opened — the query needs no access rights and is cheap enough for the two-second cadence of `InstallerModel.startMonitoring()`. Even so it runs there inside a `Task.detached(priority: .utility)`, because building the device list blocks briefly.

## Connecting

`open(cancel:)` is deliberately built as a wait loop — the user starts the transfer before opening Sphaira on the console:

```swift
var deviceHandle: OpaquePointer?
while deviceHandle == nil {
    if cancel() {
        close()
        throw InstallError.cancelled
    }
    deviceHandle = libusb_open_device_with_vid_pid(newContext, Self.vendorID, Self.productID)
    if deviceHandle == nil {
        usleep(250_000)
    }
}
```

The `cancel()` closure is polled between attempts, so at most 250 ms apart. That is why the UI can offer "Cancel" even though the thread is really just waiting.

After that four things happen, in this order:

1. `libusb_set_auto_detach_kernel_driver(deviceHandle, 1)` — the return value is deliberately discarded with `_ =`. On macOS this usually returns `NOT_SUPPORTED`; there is no kernel driver to detach there in the Linux sense. A `guard` at this point would make the app fail on every Mac.
2. `resolveEndpoints(deviceHandle:)` (see below).
3. `libusb_claim_interface(deviceHandle, 0)`. If that fails with `-3`, `InstallError.accessDenied` is thrown instead of a meaningless numeric error; any other code is passed on as `InstallError.usb(operation: "libusb_claim_interface", code:)`. In both cases `close()` is called beforehand.
4. `libusb_get_device_descriptor` and three string descriptors for `DeviceInfo`.

`stringDescriptor(index:fallback:)` reads via `libusb_get_string_descriptor_ascii` into a 256-byte buffer and falls back to a default if the index is `0`, the length is `<= 0` or the trimmed text is empty. The defaults are `"Nintendo"`, `"Nintendo Switch"` and `"unbekannt"` — which leads to a quirk in the connection message, see [[operations/troubleshooting]].

## Endpoints

The endpoint addresses are not guessed but read from the active configuration:

```swift
for interfaceIndex in 0..<Int(config.pointee.bNumInterfaces) {
    let interface = config.pointee.interface[interfaceIndex]
    for altIndex in 0..<Int(interface.num_altsetting) {
        let altsetting = interface.altsetting[altIndex]
        for endpointIndex in 0..<Int(altsetting.bNumEndpoints) {
            let address = altsetting.endpoint[endpointIndex].bEndpointAddress
            if address & 0x80 != 0 {
                if foundIn == nil { foundIn = address }
            } else if foundOut == nil {
                foundOut = address
            }
        }
    }
}
```

Bit 7 of the address distinguishes direction IN (set) from OUT. The **first** match in each direction wins. If the loop finds nothing — or if `libusb_get_active_config_descriptor` already fails — the presets `endpointIn = 0x81` and `endpointOut = 0x01` remain in place. Those are the values the Python script hard-wired as well; the fallback is therefore the status quo, not a guessing game.

`libusb_free_config_descriptor` runs via `defer`.

## Error codes as numbers instead of C enums

```swift
private nonisolated static let errorTimeout: Int32 = -7  // LIBUSB_ERROR_TIMEOUT
private nonisolated static let errorAccess: Int32 = -3   // LIBUSB_ERROR_ACCESS
private nonisolated static let errorNoDevice: Int32 = -4 // LIBUSB_ERROR_NO_DEVICE
```

The comment in the code states the reason: depending on how they are imported, the C enum constants are not directly comparable with `Int32`. `libusb_bulk_transfer`, however, returns a bare `Int32`. A comparison against `LIBUSB_ERROR_TIMEOUT` would either not compile or need a detour via `rawValue`. The three constants are part of the stable libusb ABI and do not change.

## Reading — a timeout is not an error

```swift
let code = libusb_bulk_transfer(
    handle, endpointIn,
    pointer.baseAddress! + received, Int32(count - received),
    &transferred, Self.readTimeoutMS
)
if code == 0 || code == Self.errorTimeout {
    // Even on a timeout, partial bytes may have arrived.
    received += Int(transferred)
} else if code == Self.errorAccess {
    throw InstallError.accessDenied
} else {
    throw InstallError.usb(operation: "libusb_bulk_transfer(in)", code: code)
}
```

Two decisions are baked into this:

**The 500 ms timeout sets the cadence of cancellation.** Reading always continues until exactly `count` bytes are there. Without a timeout, `read` would be uncancellable while the Switch stays silent; with 500 ms the loop regularly passes `if cancel() { throw InstallError.cancelled }`. The flip side: between two requests from the Switch the protocol spends most of its time in exactly this loop, which is entirely normal.

**`transferred` is accounted for in the timeout case too.** libusb writes the amount actually transferred into `transferred` — and that can be greater than zero on `LIBUSB_ERROR_TIMEOUT`. Discard the value and the buffer falls out of step, so a packet would be decoded incorrectly from the next byte onwards (result: `badMagic` or `checksumMismatch`, even though the line is fine).

## Writing — a finite timeout on purpose

The write path is symmetric but uses `writeTimeoutMS = 5_000`. The comment in the code justifies both numbers:

> More generous than for reading — a block is in flight, but it must not be able to hang indefinitely, otherwise cancellation would have no effect.

When reading you are waiting for a decision by the Switch (which can take a while); when writing, a block that has already been announced is in flight (which should be quick). An unlimited timeout would be the convenient route, but it makes the session uncancellable as soon as the console stalls in the middle of a block. Here too: `sent += Int(transferred)` also runs in the timeout branch.

`Int32(clamping: pointer.count - sent)` protects the conversion of the remaining length — the file list and the data blocks are small, but `clamping` costs nothing.

## Protocol helpers

`readPacket`, `send` and `sendFileInfo` are thin caps on top of `read`/`write`. The only interesting part is the bit packing of the file size:

```swift
nonisolated func sendFileInfo(size: UInt64, flags: UInt32, cancel: () -> Bool) throws {
    let lsb = UInt32(truncatingIfNeeded: size)
    let msb = UInt32((size >> 32) & 0xFFFF) | (flags << 16)
    try send(.ok, arg3: msb, arg4: lsb, cancel: cancel)
}
```

`arg4` carries the lower 32 bits of the size, `arg3` carries the upper 16 bits of the size in its lower 16 bits and the transfer flags in its upper 16 bits. From that follows a practical upper limit of 48 bits for a file size — 256 TB, far beyond any XCI. The field usage of the packets is described in [[protocol/sph0-wire-protocol]].

## Teardown in the background

`close()` is the most surprising part of the file. It clears its own references immediately and pushes the actual libusb work onto a background queue:

```swift
handle = nil
context = nil
interfaceClaimed = false

guard openHandle != nil || openContext != nil else { return }

DispatchQueue.global(qos: .utility).async {
    if let openHandle {
        if wasClaimed {
            _ = libusb_release_interface(openHandle, 0)
        }
        libusb_close(openHandle)
    }
    if let openContext {
        libusb_exit(openContext)
    }
}
```

The reason is in the doc comment above it: if the Switch has already torn down the connection on its side, `libusb_close` and `libusb_exit` can block. `close()` runs from a `defer` at the end of `InstallSession.run` — the completion message to the UI would then only arrive after the block clears, and the transfer would look like it is "running" forever. The whole case is described in [[operations/troubleshooting]].

Two details make this safe:

- The references are nulled out **before** the block is dispatched, so a second `close()` call does not free anything twice.
- `deinit` calls `close()`, so that is also the cleanup path when nobody holds a reference any more.

The price of the solution: the context lives briefly beyond the end of the session. Since a fresh `USBTransport` with its own context is built for every session (`InstallSession(items:transport: USBTransport())` in `InstallerModel.start()`), that does no harm.

## Pitfalls at a glance

| Pitfall | How the code handles it |
|---|---|
| Treating `LIBUSB_ERROR_TIMEOUT` as an error | A timeout is the normal case and an opportunity to cancel |
| Discarding `transferred` on a timeout | It is counted in both directions |
| Unlimited write timeout | 5 s, otherwise cancellation has no effect |
| Comparing against C enum constants | Numeric `Int32` constants (`-7`, `-3`, `-4`) |
| Checking `auto_detach_kernel_driver` | Return value deliberately ignored (macOS) |
| Assuming fixed endpoints | Read from the active configuration, fallback `0x81`/`0x01` |
| Synchronous `libusb_close`/`libusb_exit` | Teardown on a background queue |
| Transport on the MainActor | Everything `nonisolated`, session via `Task.detached` |
