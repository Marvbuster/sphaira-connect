//
//  InstallerModel.swift
//  Sphaira Connect
//
//  Ansichtsmodell: hält den UI-Zustand auf dem MainActor und spiegelt
//  Rückmeldungen der im Hintergrund laufenden InstallSession zurück.
//

import Foundation
import Observation

/// Abbruch-Flag mit atomarem Zugriff. Wird aus dem cancel-Closure der Sitzung
/// gelesen — der darf niemals auf MainActor-Zustand warten, sonst blockiert
/// der USB-Thread gegen den Hauptthread.
fileprivate nonisolated final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    func isSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

/// Zählt fertig übertragene Dateien auf dem Sitzungs-Thread, damit das
/// Endergebnis nicht von der Reihenfolge unstrukturierter Tasks abhängt.
fileprivate nonisolated final class DoneCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// Rückmeldungen der Sitzung. Sie laufen durch genau einen geordneten Kanal,
/// damit Fortschritt und Protokollzeilen nicht vertauscht ankommen — einzelne
/// unstrukturierte Tasks garantieren keine Reihenfolge.
fileprivate enum SessionEvent: Sendable {
    case log(String)
    case device(USBTransport.DeviceInfo)
    case progress(TransferProgress)
    case itemState(index: Int, state: InstallItem.State)
    case finished(transferred: Int)
    case cancelled
    case failed(String)
}

@Observable
final class InstallerModel {
    enum Phase: Equatable {
        case idle
        case waitingForSwitch
        case transferring
        case finished(transferred: Int)
        case failed(String)
    }

    struct LogLine: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let text: String
    }

    var items: [InstallItem] = []
    var phase: Phase = .idle
    var progress: TransferProgress?
    var log: [LogLine] = []
    var switchAttached = false
    var deviceSummary: String?
    var isLogExpanded = false

    @ObservationIgnored private var cancelFlag: CancelFlag?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    private static let maxLogLines = 500

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.byteCount }
    }

    var canStart: Bool {
        !items.isEmpty && !isBusy
    }

    var isBusy: Bool {
        phase == .waitingForSwitch || phase == .transferring
    }

    // MARK: - Warteschlange

    func add(urls: [URL]) {
        let existing = Set(items.map { $0.url.standardizedFileURL.path })
        let fresh = ItemScanner.scan(urls).filter {
            !existing.contains($0.url.standardizedFileURL.path)
        }
        guard !fresh.isEmpty else { return }
        items.append(contentsOf: fresh)
        appendLog(String(localized: "\(fresh.count) Datei(en) zur Warteschlange hinzugefügt."))
    }

    func remove(_ item: InstallItem) {
        guard !isBusy else { return }
        items.removeAll { $0.id == item.id }
    }

    func clearAll() {
        guard !isBusy else { return }
        items.removeAll()
        progress = nil
        if phase != .idle { phase = .idle }
    }

    // MARK: - Übertragung

    func start() {
        guard canStart else { return }

        for index in items.indices {
            items[index].state = .queued
        }
        progress = nil
        deviceSummary = nil
        phase = .waitingForSwitch
        appendLog(String(localized: "Warte auf die Switch — Sphaira auf der Konsole öffnen (USB-Installation)."))

        let flag = CancelFlag()
        cancelFlag = flag
        let doneCounter = DoneCounter()
        let session = InstallSession(items: items, transport: USBTransport())

        let (stream, continuation) = AsyncStream.makeStream(
            of: SessionEvent.self,
            bufferingPolicy: .unbounded
        )

        eventTask?.cancel()
        eventTask = Task { @MainActor [weak self] in
            for await event in stream {
                self?.apply(event)
            }
            // Der Strom ist zu Ende, ohne dass ein Abschlussereignis kam.
            // Ohne diesen Rückfall bliebe die Oberfläche auf „läuft" stehen
            // und „Abbrechen" aktiv, obwohl nichts mehr passiert.
            guard let self, self.isBusy else { return }
            self.progress = nil
            self.phase = .idle
            self.appendLog(String(localized: "Sitzung ohne Abschlussmeldung beendet."))
        }

        // Die Sitzung selbst hält keine Referenz auf das Modell — sie schreibt
        // nur in den Kanal. Damit gibt es keinen Zyklus und keinen Zugriff auf
        // MainActor-Zustand aus dem USB-Thread heraus.
        Task.detached(priority: .userInitiated) {
            defer { continuation.finish() }
            do {
                try session.run(
                    onLog: { continuation.yield(.log($0)) },
                    onDevice: { continuation.yield(.device($0)) },
                    onProgress: { continuation.yield(.progress($0)) },
                    onItemState: { index, state in
                        if state == .done { doneCounter.increment() }
                        continuation.yield(.itemState(index: index, state: state))
                    },
                    cancel: { flag.isSet() }
                )
                continuation.yield(.finished(transferred: doneCounter.value()))
            } catch InstallError.cancelled {
                continuation.yield(.cancelled)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                continuation.yield(.failed(message))
            }
        }
    }

    private func apply(_ event: SessionEvent) {
        switch event {
        case .log(let text):
            appendLog(text)

        case .device(let info):
            deviceSummary = "\(info.product) · \(info.serial)"
            phase = .transferring
            // info.product enthält bereits „Nintendo Switch" — den Hersteller
            // davorzusetzen ergäbe „Nintendo Nintendo Switch".
            appendLog(String(localized: "Verbunden: \(info.product) (Seriennummer \(info.serial))"))

        case .progress(let value):
            progress = value

        case .itemState(let index, let state):
            if items.indices.contains(index) {
                items[index].state = state
            }

        case .finished(let transferred):
            phase = .finished(transferred: transferred)
            appendLog(String(localized: "Fertig — \(transferred) Datei(en) übertragen."))

        case .cancelled:
            progress = nil
            phase = .idle
            appendLog(String(localized: "Übertragung abgebrochen."))

        case .failed(let message):
            progress = nil
            phase = .failed(message)
            appendLog(String(localized: "Fehler: \(message)"))
        }
    }

    func cancel() {
        guard isBusy else { return }
        cancelFlag?.set()
        appendLog(String(localized: "Abbruch angefordert …"))
    }

    // MARK: - Geräteüberwachung

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task {
            while !Task.isCancelled {
                // isSwitchAttached blockiert kurz (libusb-Geräteliste),
                // deshalb nicht auf dem MainActor ausführen.
                let attached = await Task.detached(priority: .utility) {
                    USBTransport.isSwitchAttached()
                }.value
                guard !Task.isCancelled else { break }
                if switchAttached != attached {
                    switchAttached = attached
                    appendLog(attached
                              ? String(localized: "Switch erkannt.")
                              : String(localized: "Switch getrennt."))
                }
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Protokoll

    private func appendLog(_ text: String) {
        log.append(LogLine(id: UUID(), date: .now, text: text))
        if log.count > Self.maxLogLines {
            log.removeFirst(log.count - Self.maxLogLines)
        }
    }
}
