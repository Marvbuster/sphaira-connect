import Foundation
import Observation

enum RCMPayloadPreset: String, CaseIterable, Identifiable {
    case hekate
    case fusee

    var id: Self { self }

    var title: String {
        switch self {
        case .hekate: return "Hekate"
        case .fusee: return "Fusée"
        }
    }

    var systemImage: String {
        switch self {
        case .hekate: return "square.grid.2x2"
        case .fusee: return "flame"
        }
    }

    fileprivate var defaultsKey: String {
        "rcmPreset.\(rawValue).path"
    }
}

fileprivate enum RCMEvent: Sendable {
    case prepared(imageBytes: Int, transmittedBytes: Int)
    case deviceID(String)
    case progress(sent: Int, total: Int, bytesPerSecond: Double)
    case succeeded
    case failed(String)
}

@Observable
final class RCMInjectorModel {
    enum Phase: Equatable {
        case idle
        case preparing
        case injecting
        case succeeded
        case failed(String)
    }

    var payloadURL: URL?
    var payloadByteCount: Int64?
    var phase: Phase = .idle
    var sentBytes = 0
    var totalBytes = 0
    var bytesPerSecond: Double = 0
    var rcmAttached = false
    var deviceID: String?
    var log: [AppLogLine] = []
    var isLogExpanded = false
    var presetURLs: [RCMPayloadPreset: URL] = [:]
    var isDownloadingHekate = false
    var isLoadingHekateReleases = false
    var hekateVersion: String?
    var hekateReleases: [HekateRelease] = []
    var isDownloadingFusee = false
    var isLoadingFuseeReleases = false
    var fuseeVersion: String?
    var fuseeReleases: [FuseeRelease] = []

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var hekateTask: Task<Void, Never>?
    @ObservationIgnored private var hekateCatalogTask: Task<Void, Never>?
    @ObservationIgnored private var fuseeTask: Task<Void, Never>?
    @ObservationIgnored private var fuseeCatalogTask: Task<Void, Never>?

    private static let maxLogLines = 500

    init() {
        for preset in RCMPayloadPreset.allCases {
            guard let path = UserDefaults.standard.string(forKey: preset.defaultsKey) else {
                continue
            }
            let url = URL(fileURLWithPath: path)
            if Self.isUsablePayload(url) {
                presetURLs[preset] = url
            } else {
                UserDefaults.standard.removeObject(forKey: preset.defaultsKey)
            }
        }
    }

    var isBusy: Bool {
        phase == .preparing
            || phase == .injecting
            || isDownloadingHekate
            || isDownloadingFusee
    }

    var canInject: Bool {
        payloadURL != nil && rcmAttached && !isBusy
    }

    var progressFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(sentBytes) / Double(totalBytes))
    }

    func selectPayload(_ url: URL) {
        guard !isBusy else { return }
        guard url.pathExtension.lowercased() == "bin" else {
            phase = .failed(String(localized: "RCM-Payloads müssen die Dateiendung .bin haben."))
            appendLog(String(localized: "Ungültige Payload ausgewählt: \(url.lastPathComponent)"))
            return
        }

        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            payloadURL = url
            payloadByteCount = values.fileSize.map(Int64.init)
            phase = .idle
            sentBytes = 0
            totalBytes = 0
            deviceID = nil
            appendLog(String(localized: "Payload ausgewählt: \(url.lastPathComponent)"))
        } catch {
            phase = .failed(String(localized: "Payload nicht lesbar: \(error.localizedDescription)"))
        }
    }

    func usePreset(_ preset: RCMPayloadPreset) {
        guard let url = presetURLs[preset] else { return }
        guard Self.isUsablePayload(url) else {
            presetURLs[preset] = nil
            UserDefaults.standard.removeObject(forKey: preset.defaultsKey)
            phase = .failed(String(localized: "Die Datei des Presets „\(preset.title)“ wurde nicht gefunden."))
            appendLog(String(localized: "Preset-Datei fehlt: \(url.lastPathComponent)"))
            return
        }
        selectPayload(url)
        appendLog(String(localized: "Preset „\(preset.title)“ ausgewählt."))
    }

    func assignPreset(_ preset: RCMPayloadPreset, url: URL) {
        selectPayload(url)
        guard payloadURL?.standardizedFileURL == url.standardizedFileURL,
              phase == .idle else { return }
        presetURLs[preset] = url
        UserDefaults.standard.set(url.path, forKey: preset.defaultsKey)
        appendLog(String(localized: "Preset „\(preset.title)“ gespeichert."))
    }

    func removePreset(_ preset: RCMPayloadPreset) {
        guard let removed = presetURLs.removeValue(forKey: preset) else { return }
        UserDefaults.standard.removeObject(forKey: preset.defaultsKey)
        appendLog(String(localized: "Preset „\(preset.title)“ entfernt (\(removed.lastPathComponent))."))
    }

    func loadHekateReleases() {
        guard hekateReleases.isEmpty, !isLoadingHekateReleases else { return }
        isLoadingHekateReleases = true
        hekateCatalogTask?.cancel()
        hekateCatalogTask = Task { [weak self] in
            defer { self?.isLoadingHekateReleases = false }
            do {
                let releases = try await HekateDownloader().availableReleases()
                guard !Task.isCancelled else { return }
                self?.hekateReleases = releases
            } catch {
                guard !Task.isCancelled else { return }
                self?.appendLog(String(localized: "Hekate-Versionen konnten nicht geladen werden: \(error.localizedDescription)"))
            }
        }
    }

    func downloadHekate(_ release: HekateRelease) {
        guard !isBusy else { return }
        isDownloadingHekate = true
        appendLog(String(localized: "Lade Hekate \(release.tagName) aus der offiziellen Release …"))

        hekateTask?.cancel()
        hekateTask = Task { [weak self] in
            defer { self?.isDownloadingHekate = false }
            do {
                let url = try await HekateDownloader().download(release)
                guard !Task.isCancelled else { return }
                self?.isDownloadingHekate = false
                self?.assignPreset(.hekate, url: url)
                self?.hekateVersion = release.tagName
                self?.appendLog(String(localized: "Hekate \(release.tagName) wurde geladen und ausgewählt."))
            } catch is CancellationError {
                // A replaced task should not surface as an error.
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(String(
                    localized: "Hekate konnte nicht geladen werden: \(error.localizedDescription)"
                ))
                self?.appendLog(String(localized: "Hekate-Download fehlgeschlagen: \(error.localizedDescription)"))
            }
        }
    }

    func loadFuseeReleases() {
        guard fuseeReleases.isEmpty, !isLoadingFuseeReleases else { return }
        isLoadingFuseeReleases = true
        fuseeCatalogTask?.cancel()
        fuseeCatalogTask = Task { [weak self] in
            defer { self?.isLoadingFuseeReleases = false }
            do {
                let releases = try await FuseeDownloader().availableReleases()
                guard !Task.isCancelled else { return }
                self?.fuseeReleases = releases
            } catch {
                guard !Task.isCancelled else { return }
                self?.appendLog(String(localized: "Fusée-Versionen konnten nicht geladen werden: \(error.localizedDescription)"))
            }
        }
    }

    func downloadFusee(_ release: FuseeRelease) {
        guard !isBusy else { return }
        isDownloadingFusee = true
        appendLog(String(localized: "Lade Fusée \(release.tagName) aus der offiziellen Atmosphère-Release …"))

        fuseeTask?.cancel()
        fuseeTask = Task { [weak self] in
            defer { self?.isDownloadingFusee = false }
            do {
                let url = try await FuseeDownloader().download(release)
                guard !Task.isCancelled else { return }
                self?.isDownloadingFusee = false
                self?.assignPreset(.fusee, url: url)
                self?.fuseeVersion = release.tagName
                self?.appendLog(String(localized: "Fusée \(release.tagName) wurde geladen und ausgewählt."))
            } catch is CancellationError {
                // A replaced task should not surface as an error.
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(String(
                    localized: "Fusée konnte nicht geladen werden: \(error.localizedDescription)"
                ))
                self?.appendLog(String(localized: "Fusée-Download fehlgeschlagen: \(error.localizedDescription)"))
            }
        }
    }

    /// The only entry point that injects anything. Selection and device
    /// detection never call this automatically.
    func inject() {
        guard canInject, let payloadURL else { return }
        phase = .preparing
        sentBytes = 0
        totalBytes = 0
        bytesPerSecond = 0
        deviceID = nil
        appendLog(String(localized: "Bereite \(payloadURL.lastPathComponent) vor …"))

        let (stream, continuation) = AsyncStream.makeStream(
            of: RCMEvent.self,
            bufferingPolicy: .unbounded
        )
        eventTask?.cancel()
        eventTask = Task { @MainActor [weak self] in
            for await event in stream {
                self?.apply(event)
            }
        }

        Task.detached(priority: .userInitiated) {
            defer { continuation.finish() }
            do {
                let userPayload = [UInt8](try Data(contentsOf: payloadURL, options: .mappedIfSafe))
                let image = try RCMPayloadBuilder.build(userPayload: userPayload)
                let transmitted = RCMPayloadBuilder.transmittedByteCount(imageByteCount: image.count)
                continuation.yield(.prepared(imageBytes: image.count, transmittedBytes: transmitted))

                // Same tracker-based rate smoothing as InstallSession, fed from
                // RCMTransport's cumulative (sent, total) callback rather than a
                // per-chunk one — the delta against the previous call is the chunk.
                var tracker = ProgressTracker(
                    totalBytes: Int64(transmitted),
                    startNanos: DispatchTime.now().uptimeNanoseconds
                )
                var lastSent = 0
                try RCMTransport().inject(
                    image: image,
                    onDeviceID: { continuation.yield(.deviceID($0)) },
                    onProgress: { sent, total in
                        tracker.record(chunkSize: sent - lastSent)
                        lastSent = sent
                        if tracker.tick(now: DispatchTime.now().uptimeNanoseconds) {
                            continuation.yield(.progress(sent: sent, total: total, bytesPerSecond: tracker.bytesPerSecond))
                        }
                    }
                )
                continuation.yield(.succeeded)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                continuation.yield(.failed(message))
            }
        }
    }

    private func apply(_ event: RCMEvent) {
        switch event {
        case let .prepared(imageBytes, transmittedBytes):
            phase = .injecting
            totalBytes = transmittedBytes
            appendLog(String(localized: "RCM-Abbild erstellt: \(imageBytes) Bytes."))
        case let .deviceID(id):
            deviceID = id
            appendLog(String(localized: "RCM-Switch verbunden · Geräte-ID \(id)"))
        case let .progress(sent, total, rate):
            sentBytes = sent
            totalBytes = total
            bytesPerSecond = rate
        case .succeeded:
            sentBytes = totalBytes
            bytesPerSecond = 0
            phase = .succeeded
            appendLog(String(localized: "Payload injiziert — die Switch startet sie jetzt."))
        case let .failed(message):
            phase = .failed(message)
            appendLog(String(localized: "Fehler: \(message)"))
        }
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task {
            while !Task.isCancelled {
                let attached = await Task.detached(priority: .utility) {
                    RCMTransport.isRCMAttached()
                }.value
                guard !Task.isCancelled else { break }
                if rcmAttached != attached {
                    rcmAttached = attached
                    appendLog(attached
                        ? String(localized: "Switch im RCM-Modus erkannt.")
                        : String(localized: "RCM-Switch getrennt."))
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

    private func appendLog(_ text: String) {
        log.append(AppLogLine(id: UUID(), date: .now, text: text))
        if log.count > Self.maxLogLines {
            log.removeFirst(log.count - Self.maxLogLines)
        }
    }

    private static func isUsablePayload(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "bin" else { return false }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
            return false
        }
        return values.isRegularFile == true
            && FileManager.default.isReadableFile(atPath: url.path)
    }
}
