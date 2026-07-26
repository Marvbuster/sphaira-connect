//
//  InstallerModel.swift
//  Sphaira Connect
//
//  View model: keeps the UI state on the MainActor and mirrors back the
//  callbacks of the InstallSession running in the background.
//

import Foundation
import Observation

/// Cancellation flag with atomic access. Read from the session's cancel closure —
/// which must never wait on MainActor state, otherwise the USB thread deadlocks
/// against the main thread.
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

/// Counts completed files on the session thread so the final result does not
/// depend on the ordering of unstructured tasks.
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

/// Callbacks from the session. They travel through exactly one ordered channel
/// so progress and log lines cannot arrive out of order — individual
/// unstructured tasks guarantee no ordering.
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

    // MARK: - Queue

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

    // MARK: - Transfer

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
            // The stream ended without a terminal event arriving. Without this
            // fallback the UI would stay stuck on "in progress" with "Cancel"
            // still enabled, even though nothing is happening any more.
            guard let self, self.isBusy else { return }
            self.progress = nil
            self.phase = .idle
            self.appendLog(String(localized: "Sitzung ohne Abschlussmeldung beendet."))
        }

        // The session itself holds no reference to the model — it only writes to
        // the channel. That avoids a retain cycle and any access to MainActor
        // state from the USB thread.
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
            // info.product already contains "Nintendo Switch" — prefixing the
            // manufacturer would produce "Nintendo Nintendo Switch".
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

    // MARK: - Device monitoring

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task {
            while !Task.isCancelled {
                // isSwitchAttached blocks briefly (libusb device list),
                // so do not run it on the MainActor.
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

    // MARK: - Log

    private func appendLog(_ text: String) {
        log.append(LogLine(id: UUID(), date: .now, text: text))
        if log.count > Self.maxLogLines {
            log.removeFirst(log.count - Self.maxLogLines)
        }
    }
}
