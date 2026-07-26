//
//  InstallSession.swift
//  Sphaira Connect
//
//  Protocol state machine of the Sphaira USB installer. Runs entirely
//  blocking on a background thread, hence nonisolated throughout.
//

import Foundation

nonisolated struct TransferProgress: Equatable, Sendable {
    var itemIndex: Int
    var itemName: String
    var itemSent: Int64
    var itemTotal: Int64
    var overallSent: Int64
    var overallTotal: Int64
    var bytesPerSecond: Double
}

final class InstallSession: @unchecked Sendable {
    /// NSP/XCI containers pad their last entry to an alignment boundary that
    /// the Switch never explicitly requests — a handful of trailing bytes it
    /// already knows are not content. Within this margin, a transfer still
    /// counts as complete instead of being reported as skipped.
    private nonisolated static let completionTolerance: Int64 = 4096

    private nonisolated let items: [InstallItem]
    private nonisolated let transport: USBTransport

    nonisolated init(items: [InstallItem], transport: USBTransport) {
        self.items = items
        self.transport = transport
    }

    nonisolated func run(
        onLog: @Sendable @escaping (String) -> Void,
        onDevice: @Sendable @escaping (USBTransport.DeviceInfo) -> Void,
        onProgress: @Sendable @escaping (TransferProgress) -> Void,
        onItemState: @Sendable @escaping (Int, InstallItem.State) -> Void,
        cancel: @Sendable @escaping () -> Bool
    ) throws {
        defer { transport.close() }

        // The view model already logs the waiting and connected messages;
        // emitting them here would only duplicate them in the log.
        let device = try transport.open(cancel: cancel)
        onDevice(device)

        var tableBytes: [UInt8] = []
        for item in items {
            tableBytes.append(contentsOf: Array((item.displayName + "\n").utf8))
        }

        // The first packet from the Switch carries no payload — decode validates
        // magic and CRC, and nothing else matters here.
        _ = try transport.readPacket(cancel: cancel)
        try transport.send(.ok, arg3: UInt32(tableBytes.count), arg4: 0, cancel: cancel)
        try transport.write(tableBytes, cancel: cancel)
        onLog(String(localized: "Namensliste mit \(items.count) Einträgen gesendet."))

        let overallTotal = items.reduce(Int64(0)) { $0 + $1.byteCount }
        var completedBytes: Int64 = 0

        while true {
            let packet = try transport.readPacket(cancel: cancel)

            switch packet.command {
            case SphairaCommand.quit.rawValue:
                try transport.send(.ok, arg3: 0, arg4: 0, cancel: cancel)
                onLog(String(localized: "Switch hat die Sitzung beendet."))
                return

            case SphairaCommand.open.rawValue:
                let index = Int(packet.arg3)
                guard items.indices.contains(index) else {
                    try transport.send(.error, arg3: 0, arg4: 0, cancel: cancel)
                    throw InstallError.fileUnreadable(
                        path: "#\(index)",
                        reason: String(localized: "Dateiindex außerhalb der Liste")
                    )
                }
                let transferred = try transferFile(
                    index: index,
                    completedBytes: completedBytes,
                    overallTotal: overallTotal,
                    onLog: onLog,
                    onProgress: onProgress,
                    onItemState: onItemState,
                    cancel: cancel
                )
                // Only count bytes that were actually transferred, otherwise the
                // overall progress jumps across a file that failed.
                if transferred {
                    completedBytes += items[index].byteCount
                }

            default:
                try transport.send(.error, arg3: 0, arg4: 0, cancel: cancel)
                throw InstallError.unexpectedCommand(packet.command)
            }
        }
    }

    // MARK: - Single file

    /// Returns `true` if the file was transferred completely.
    ///
    /// On a file error an error packet goes to the Switch. Sphaira then aborts
    /// the whole installation, but still sends the finish or quit command — the
    /// command loop answers that one normally. The session therefore ends in an
    /// orderly fashion instead of with an abrupt USB disconnect.
    private nonisolated func transferFile(
        index: Int,
        completedBytes: Int64,
        overallTotal: Int64,
        onLog: (String) -> Void,
        onProgress: (TransferProgress) -> Void,
        onItemState: (Int, InstallItem.State) -> Void,
        cancel: () -> Bool
    ) throws -> Bool {
        let item = items[index]
        onItemState(index, .transferring)
        onLog(String(localized: "Übertrage \(item.displayName) …"))

        func reportFailure(_ reason: String) throws {
            try transport.send(.error, arg3: 0, arg4: 0, cancel: cancel)
            onItemState(index, .failed(reason))
            onLog(String(localized: "Fehler bei \(item.displayName): \(reason)"))
        }

        let file: FileHandle
        let size: UInt64
        do {
            file = try FileHandle(forReadingFrom: item.url)
            size = try file.seekToEnd()
        } catch {
            try reportFailure(error.localizedDescription)
            return false
        }
        defer { try? file.close() }

        try transport.sendFileInfo(size: size, flags: TransferFlags.none, cancel: cancel)

        var tracker = ProgressTracker(
            totalBytes: Int64(size),
            startNanos: DispatchTime.now().uptimeNanoseconds
        )

        // `sentOverride` reports the file as fully sent once it counts as complete
        // (see completionTolerance below) — otherwise the last progress snapshot of
        // a batch stays a few bytes short of overallTotal forever, and the summary
        // view keeps showing "incomplete" even though every file actually succeeded.
        func emitProgress(force: Bool, sentOverride: Int64? = nil) {
            guard tracker.tick(now: DispatchTime.now().uptimeNanoseconds, force: force) else { return }
            let sent = sentOverride ?? tracker.clampedSent
            onProgress(TransferProgress(
                itemIndex: index,
                itemName: item.displayName,
                itemSent: sent,
                itemTotal: Int64(size),
                overallSent: completedBytes + sent,
                overallTotal: overallTotal,
                bytesPerSecond: tracker.bytesPerSecond
            ))
        }

        while true {
            let packet = try transport.readPacket(cancel: cancel)
            let offset = packet.dataOffset
            let requested = Int(packet.dataSize)

            if offset == 0 && requested == 0 {
                try transport.send(.ok, arg3: 0, arg4: 0, cancel: cancel)
                break
            }

            let chunk: [UInt8]
            do {
                try file.seek(toOffset: offset)
                // nil means end of file — treat it as an empty response.
                chunk = [UInt8](try file.read(upToCount: requested) ?? Data())
            } catch {
                try reportFailure(error.localizedDescription)
                return false
            }

            try transport.send(
                .ok,
                arg3: UInt32(chunk.count),
                arg4: CRC32C.checksum(chunk),
                cancel: cancel
            )
            try transport.write(chunk, cancel: cancel)

            tracker.record(chunkSize: chunk.count)
            emitProgress(force: false)
        }

        // Sphaira also closes the file after a few kilobytes when it skips the
        // title (already installed) or rejects it (invalid header). The two cases
        // are indistinguishable on the wire — so we report the observed facts
        // rather than a guessed cause. A shortfall within completionTolerance is
        // container padding, not a skip: the install still succeeded.
        let succeeded = tracker.sentBytes >= Int64(size) - Self.completionTolerance
        emitProgress(force: true, sentOverride: succeeded ? Int64(size) : nil)

        guard succeeded else {
            let reason = String(
                localized: "übersprungen — Switch hat nur \(ByteFormat.size(tracker.sentBytes)) von \(ByteFormat.size(Int64(size))) angefordert"
            )
            onItemState(index, .skipped(reason))
            onLog(String(
                localized: "\(item.displayName): \(reason). Meist ist der Titel schon installiert; sonst hat Sphaira die Datei verworfen."
            ))
            return false
        }

        onItemState(index, .done)
        onLog(String(localized: "\(item.displayName) fertig übertragen."))
        return true
    }
}
