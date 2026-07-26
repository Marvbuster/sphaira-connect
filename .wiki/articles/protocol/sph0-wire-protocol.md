---
title: "The SPH0 USB Protocol — Packet Format, CRC32C, Commands"
created: 2026-07-26
updated: 2026-07-26
category: protocol
tags: [protocol, sph0, crc32c, packet-format, libusb, little-endian]
status: current
related:
  - protocol/install-session-flow
  - protocol/progress-tracking
  - architecture/system-overview
  - architecture/concurrency-and-cancellation
  - usb/libusb-transport
  - operations/testing-strategy
code_refs:
  - Sphaira Connect/Core/SphairaProtocol.swift
  - Sphaira Connect/Core/CRC32C.swift
  - Sphaira Connect/Core/InstallError.swift
  - Sphaira Connect/USB/USBTransport.swift
---

# The SPH0 Wire Format

Sphaira and Sphaira Connect exchange nothing but **fixed-size 24-byte packets**: six little-endian
`UInt32` values — `magic, arg2, arg3, arg4, arg5, crc32c` — followed (where needed) by raw payload
outside the packet. The four `arg` fields have **no fixed meaning**; they are read differently
depending on the direction and the state of the state machine. That is the most common source of
confusion when reading the code, and the reason `Packet` offers three named views (`command`,
`dataOffset`, `dataSize`) alongside the raw fields.

## Byte layout

| Offset | Length | Field | Contents |
|---|---|---|---|
| 0 | 4 | `magic` | `0x53504830`, constant |
| 4 | 4 | `arg2` | Command (Switch → host) or result code (host → Switch) |
| 8 | 4 | `arg3` | context-dependent |
| 12 | 4 | `arg4` | context-dependent |
| 16 | 4 | `arg5` | unused, always 0 |
| 20 | 4 | `crc32c` | CRC-32C over the **first 20 bytes** |

`0x53504830` is ASCII `"SPH0"` — but written little-endian, meaning the bytes on the wire are
`30 48 50 53`. Anyone capturing the traffic therefore sees `"0HPS"` at the start of a packet. The
test `wireLayoutLittleEndian` in `PacketTests.swift` verifies every single byte position.

`arg5` is never populated by the code (`init` defaults it to 0 and no send site sets it); the
round trip through encode/decode nevertheless preserves it losslessly, so that a future protocol
step can use it without breaking the format.

## CRC32C (Castagnoli)

```swift
nonisolated enum CRC32C {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var crc = UInt32(index)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0x82F6_3B78 : crc >> 1
            }
            return crc
        }
    }()

    static func checksum<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)] }
        return ~crc
    }
}
```

Parameters: reflected polynomial `0x82F63B78`, initial value `0xFFFFFFFF`, final negation, no
reflection of the result (that is already baked into the reflected form). This is the same CRC-32C
as in RFC 3720 (iSCSI) and in the `crc32c` hardware instruction of modern CPUs — the far side on
the Switch computes the same variant.

Reference values, stated in the contract and checked in `CRC32CTests.swift`:

| Input | Result |
|---|---|
| `[]` | `0` |
| `"123456789"` (UTF-8) | `0xE3069283` |
| 32 × `0x00` | `0x8A9136AA` |
| 32 × `0xFF` | `0x62A8AB43` |

The signature is generic over `Collection`, not over `[UInt8]`. That is not gold-plating:
`Packet.decode` checks with `CRC32C.checksum(bytes.prefix(20))`, i.e. over an `ArraySlice` —
without the generic, every packet would have to be copied once at this hot spot.

**Important for understanding the session:** the packet CRC only protects the 20-byte header. The
actual payload (file list, file blocks) travels alongside it over the wire unprotected — for that,
the host sends the CRC32C of the block in `arg4` of the corresponding OK packet
([[protocol/install-session-flow]]).

## Encoding and decoding

```swift
func encoded() -> [UInt8] {
    var bytes = [UInt8]()
    bytes.reserveCapacity(Self.byteCount)
    for word in [Self.magic, arg2, arg3, arg4, arg5] {
        bytes.append(contentsOf: Self.littleEndianBytes(word))
    }
    bytes.append(contentsOf: Self.littleEndianBytes(CRC32C.checksum(bytes)))
    return bytes
}
```

The CRC is computed over the buffer that has already been filled — which makes it impossible for
header construction and checksum to drift apart.

When decoding, the **validation order is fixed: length → magic → CRC.**

```swift
static func decode(_ bytes: [UInt8]) throws -> Packet {
    // Validation order per the contract: length first, then magic, then CRC.
    guard bytes.count == byteCount else {
        throw InstallError.shortPacket(expected: byteCount, got: bytes.count)
    }
    let words = (0..<6).map { readWord(bytes, at: $0 * 4) }
    guard words[0] == magic else { throw InstallError.badMagic }
    guard CRC32C.checksum(bytes.prefix(20)) == words[5] else {
        throw InstallError.checksumMismatch
    }
    return Packet(arg2: words[1], arg3: words[2], arg4: words[3], arg5: words[4])
}
```

Why this order and not some other:

- **Length first**, because otherwise `readWord` reads past the end of the buffer and the process
  crashes instead of reporting an error. The test `lengthCheckedBeforeMagic` locks that down.
- **Magic before CRC**, because the two errors name different causes. `badMagic` means "this
  answer is not from Sphaira at all" (wrong device, wrong endpoint, bus out of step);
  `checksumMismatch` means "right peer, broken line". The German error texts in `InstallError` say
  precisely that: *"Ungültige Paketkennung — Antwort stammt nicht von Sphaira."* versus
  *"Prüfsummenfehler im empfangenen Paket."* A packet with a foreign magic and a correctly
  recomputed CRC is therefore reported as `badMagic`, not accepted as valid.

The caller never gets to see either check in isolation: `USBTransport.readPacket` reads exactly
`Packet.byteCount` bytes and hands them straight to `decode`.

## Commands and result codes

```swift
nonisolated enum SphairaCommand: UInt32 { case quit = 0, open = 1 }
nonisolated enum SphairaResult: UInt32 { case ok = 0, error = 1 }
```

In **Switch → host** packets `arg2` carries the command, in **host → Switch** packets the result
code. Both enumerations use the values 0 and 1 — so a `0` is either `quit` or `ok` depending on
direction. This is why the view `packet.command` (== `arg2`) only makes sense in the command loop,
and `send(_ result:…)` only in the opposite direction.

Anything other than `quit` and `open` is answered by the session with `send(.error, 0, 0)` and
throws `InstallError.unexpectedCommand(command)` — no silent ignoring, because an unknown command
means the two sides disagree about the state machine.

## `dataOffset` — 64 bits from two words

```swift
var command: UInt32 { arg2 }
var dataOffset: UInt64 { UInt64(arg2) << 32 | UInt64(arg3) }
var dataSize: UInt32 { arg4 }
```

During a file transfer the Switch requests ranges; the position is a 64-bit value split across
`arg2` (upper 32 bits) and `arg3` (lower 32 bits). That is not a precaution but everyday reality:
an XCI can be 32 GB in size, and the 4 GB boundary (`0x1_0000_0000`) is crossed by every larger
title. `PacketTests` checks that boundary explicitly — `Packet(arg2: 1, arg3: 0).dataOffset ==
4_294_967_296`.

Note the overlap: the very same `arg2` that carries the command in the command loop is the upper
offset word inside the file loop. An offset ≥ 4 GB looks, at field level, like "command 1, 2, 3 …".
The two meanings do not collide because they are read in different states of the machine — mix the
states up and you have built an unfindable bug at exactly this spot.

## `sendFileInfo` — size and flags in one packet

The answer to an `open` has to carry both the file size *and* the transfer flags, but only `arg3`
and `arg4` are free for it — `arg2` is taken by the result code in this direction:

```swift
nonisolated func sendFileInfo(size: UInt64, flags: UInt32, cancel: () -> Bool) throws {
    let lsb = UInt32(truncatingIfNeeded: size)
    let msb = UInt32((size >> 32) & 0xFFFF) | (flags << 16)
    try send(.ok, arg3: msb, arg4: lsb, cancel: cancel)
}
```

- `arg4` = lower 32 bits of the size
- `arg3`, lower 16 bits = bits 32…47 of the size → maximum representable file size 2^48 − 1 bytes
  (256 TiB), far more than enough for Switch titles
- `arg3`, upper 16 bits = flags

So compared with `dataOffset`, the size is **shifted by one word** (there `arg2`/`arg3`, here
`arg3`/`arg4`). Confuse the two encodings and you report a file size to the Switch that is off by a
factor of 2^32 — visible only once Sphaira starts requesting blocks beyond the end of the file.

```swift
nonisolated enum TransferFlags {
    static let none: UInt32 = 0
    static let stream: UInt32 = 1 << 0
}
```

`TransferFlags.stream` is defined but never sent anywhere in the project: `InstallSession` calls
`sendFileInfo(size:flags: TransferFlags.none)`. The flag is reserved as a placeholder for a future
streaming mode (data that does not come from a file).

## Transport layer

`USBTransport` wraps libusb and provides only two raw operations: "read exactly *n* bytes" and
"write this buffer completely". Both loops treat `LIBUSB_ERROR_TIMEOUT` (−7) as partial progress
rather than an error, and promote `LIBUSB_ERROR_ACCESS` (−3) to `InstallError.accessDenied`;
details in [[architecture/concurrency-and-cancellation]]. The endpoints are taken by
`resolveEndpoints` from the active configuration descriptor (first IN, first OUT endpoint); with no
match it falls back to `0x81` / `0x01`. The complete libusb binding is described in
[[usb/libusb-transport]].
