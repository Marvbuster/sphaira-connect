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

    var items: [InstallItem] = []
    var phase: Phase = .idle
    var progress: TransferProgress?
    var log: [AppLogLine] = []
    var switchAttached = false
    var deviceSummary: String?
    var isLogExpanded = false

    @ObservationIgnored private var cancelFlag: CancelFlag?
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var integrityTask: Task<Void, Never>?
    @ObservationIgnored private var integrityCancel = CancelFlag()

    private static let maxLogLines = 500

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.byteCount }
    }

    var canStart: Bool {
        items.contains { !$0.integrity.isCorrupt } && !isBusy
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
        scheduleIntegrityChecks(for: fresh)
    }

    // MARK: - Integrity

    /// Checks the freshly added files in the background, one after the other:
    /// first the quick structural/hash pass, then — if that is clean — the deep
    /// zero-run scan with progress. Batches queue up behind each other so two
    /// drops never compete for the disk. Results arrive through one ordered
    /// channel, like the session events.
    private func scheduleIntegrityChecks(for fresh: [InstallItem]) {
        let flag = integrityCancel
        let targets = fresh.map { ($0.id, $0.url) }
        let previous = integrityTask
        integrityTask = Task { @MainActor [weak self] in
            await previous?.value
            let (stream, continuation) = AsyncStream.makeStream(
                of: (UUID, InstallItem.Integrity).self,
                bufferingPolicy: .unbounded
            )
            Task.detached(priority: .utility) {
                defer { continuation.finish() }
                for (id, url) in targets {
                    if flag.isSet() { return }
                    let quick = ContainerIntegrity.check(url: url, deep: false, cancel: { flag.isSet() })
                    guard quick.verdict == .ok else {
                        continuation.yield((id, .verified(quick.verdict)))
                        continue
                    }
                    continuation.yield((id, .checking(0)))
                    let deep = ContainerIntegrity.check(
                        url: url,
                        deep: true,
                        cancel: { flag.isSet() },
                        progress: { continuation.yield((id, .checking($0))) }
                    )
                    continuation.yield((id, .verified(deep.verdict)))
                }
            }
            for await (id, integrity) in stream {
                self?.applyIntegrity(id: id, integrity)
            }
        }
    }

    private func applyIntegrity(id: UUID, _ integrity: InstallItem.Integrity) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].integrity = integrity
        let name = items[index].displayName
        switch integrity {
        case .verified(.corrupt(let reason)):
            appendLog(String(localized: "Dump beschädigt — \(name): \(reason)"))
        case .verified(.warning(let reason)):
            appendLog(String(localized: "Dump-Warnung — \(name): \(reason)"))
        default:
            break
        }
    }

    /// Stops running checks; the next batch starts with a fresh flag.
    private func cancelIntegrityChecks() {
        integrityCancel.set()
        integrityCancel = CancelFlag()
    }

    func remove(_ item: InstallItem) {
        guard !isBusy else { return }
        items.removeAll { $0.id == item.id }
    }

    func clearAll() {
        guard !isBusy else { return }
        cancelIntegrityChecks()
        items.removeAll()
        progress = nil
        if phase != .idle { phase = .idle }
    }

    // MARK: - Transfer

    func start() {
        guard canStart else { return }
        cancelIntegrityChecks()

        // Corrupt dumps stay behind: the Switch would reject them after
        // gigabytes of transfer (NcaBadMagic). The session sees only the
        // healthy items; indexMap translates its indices back to the queue.
        var sessionItems: [InstallItem] = []
        var indexMap: [Int] = []
        var withheld = 0
        for index in items.indices {
            if case .verified(.corrupt(let reason)) = items[index].integrity {
                items[index].state = .failed(String(localized: "nicht gesendet — Dump beschädigt: \(reason)"))
                withheld += 1
            } else {
                items[index].state = .queued
                indexMap.append(index)
                sessionItems.append(items[index])
            }
        }
        if withheld > 0 {
            appendLog(String(localized: "\(withheld) Datei(en) wegen beschädigtem Dump nicht gesendet."))
        }
        progress = nil
        deviceSummary = nil
        phase = .waitingForSwitch
        appendLog(String(localized: "Warte auf die Switch — Sphaira auf der Konsole öffnen (USB-Installation)."))
        appendLog(String(localized: "Hinweis: Nur Sphaira ab 1.0.0 spricht das USB-Protokoll von Sphaira Connect — Awoo, Tinfoil, NS-USBloader & Co. bleiben stumm."))

        let flag = CancelFlag()
        cancelFlag = flag
        let doneCounter = DoneCounter()
        let session = InstallSession(items: sessionItems, transport: USBTransport())

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
                        continuation.yield(.itemState(index: indexMap[index], state: state))
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
            phase = .transferring
            // info.product already contains "Nintendo Switch" — prefixing the
            // manufacturer would produce "Nintendo Nintendo Switch".
            if let serial = DeviceSerial.display(info.serial) {
                deviceSummary = "\(info.product) · \(serial)"
                appendLog(String(localized: "Verbunden: \(info.product) (Seriennummer \(serial))"))
            } else {
                deviceSummary = info.product
                appendLog(String(localized: "Verbunden: \(info.product)"))
            }
            // Sphaira reports the console's real serial. The libnx default
            // descriptor means some other homebrew app owns the USB interface —
            // it will never send an SPH0 packet, and we would wait forever.
            if DeviceSerial.isPlaceholder(info.serial) {
                appendLog(String(localized: "Die Konsole meldet sich mit der libnx-Standardkennung — dort läuft vermutlich Awoo, Tinfoil oder eine andere App statt Sphaira."))
            }

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
        log.append(AppLogLine(id: UUID(), date: .now, text: text))
        if log.count > Self.maxLogLines {
            log.removeFirst(log.count - Self.maxLogLines)
        }
    }
}
