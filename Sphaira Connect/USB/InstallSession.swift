//
//  InstallSession.swift
//  Sphaira Connect
//
//  Protokoll-Zustandsautomat des Sphaira-USB-Installers. Läuft komplett
//  blockierend auf einem Hintergrund-Thread, daher durchgehend nonisolated.
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

        // Warte- und Verbindungsmeldung schreibt das Ansichtsmodell,
        // hier würden sie nur doppelt im Protokoll landen.
        let device = try transport.open(cancel: cancel)
        onDevice(device)

        var tableBytes: [UInt8] = []
        for item in items {
            tableBytes.append(contentsOf: Array((item.displayName + "\n").utf8))
        }

        // Das erste Paket der Switch trägt keinen Inhalt — decode prüft
        // Magic und CRC, mehr zählt hier nicht.
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
                // Nur tatsächlich übertragene Bytes zählen, sonst springt der
                // Gesamtfortschritt über eine gescheiterte Datei hinweg.
                if transferred {
                    completedBytes += items[index].byteCount
                }

            default:
                try transport.send(.error, arg3: 0, arg4: 0, cancel: cancel)
                throw InstallError.unexpectedCommand(packet.command)
            }
        }
    }

    // MARK: - Einzelne Datei

    /// Liefert `true`, wenn die Datei vollständig übertragen wurde.
    ///
    /// Bei einem Dateifehler geht ein Fehlerpaket an die Switch. Sphaira bricht
    /// daraufhin die gesamte Installation ab, schickt aber noch den Abschluss-
    /// beziehungsweise Quit-Befehl — den beantwortet die Kommandoschleife regulär.
    /// So endet die Sitzung geordnet statt mit einem abrupten USB-Abriss.
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

        func emitProgress(force: Bool) {
            guard tracker.tick(now: DispatchTime.now().uptimeNanoseconds, force: force) else { return }
            let sent = tracker.clampedSent
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
                // nil bedeutet Dateiende — als leere Antwort behandeln.
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

        emitProgress(force: true)

        // Sphaira schließt die Datei nach wenigen Kilobyte auch dann, wenn es sie
        // überspringt (bereits installiert) oder verwirft (ungültiger Kopfsatz).
        // Beide Fälle sind auf dem Draht nicht unterscheidbar — also melden wir
        // den Sachverhalt und nicht eine geratene Ursache.
        guard tracker.sentBytes >= Int64(size) else {
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
