import SwiftUI

/// Main view: background with a state-dependent colour wash, header in the title
/// bar zone, drop zone or queue, progress, log, actions.
struct RootView: View {
    @State private var model = InstallerModel()
    @State private var rcmModel = RCMInjectorModel()
    @State private var mode: RootViewMode = .install

    // The countdown badge's own displayed value, refreshed at most once a
    // second — see `refreshCountdown(with:)` for why.
    @State private var displayedRemainingSeconds: Double?
    @State private var lastCountdownRefresh: Date = .distantPast

    private var backgroundTint: Color {
        if mode == .rcm {
            switch rcmModel.phase {
            case .preparing, .injecting: return Colors.backgroundTintActive
            case .failed: return Colors.backgroundTintError
            case .idle, .succeeded: return Colors.backgroundTint
            }
        }
        return switch model.phase {
        case .transferring, .waitingForSwitch: Colors.backgroundTintActive
        case .failed: Colors.backgroundTintError
        case .idle, .finished: Colors.backgroundTint
        }
    }

    private var isFinished: Bool {
        if case .finished = model.phase { return true }
        return false
    }

    private var showsProgress: Bool {
        switch model.phase {
        case .transferring, .finished: model.progress != nil
        default: false
        }
    }

    /// `nil` — nothing running, badge hidden. `.nan` — running but the estimate
    /// isn't trustworthy yet (rate unknown, or too few samples for the exponential
    /// smoothing in `ProgressTracker` to have settled), rendered by
    /// `ByteFormat.duration` as an en dash. This is the raw, per-tick value — see
    /// `refreshCountdown(with:)` for why the badge doesn't bind to it directly.
    private var rawRemainingSeconds: Double? {
        if mode == .install, model.phase == .transferring, let progress = model.progress {
            guard progress.bytesPerSecond > 0, progress.sampleCount >= 3 else { return .nan }
            return Double(progress.overallTotal - progress.overallSent) / progress.bytesPerSecond
        }
        if mode == .rcm, rcmModel.phase == .injecting {
            guard rcmModel.bytesPerSecond > 0, rcmModel.sampleCount >= 3 else { return .nan }
            return Double(rcmModel.totalBytes - rcmModel.sentBytes) / rcmModel.bytesPerSecond
        }
        return nil
    }

    private var sizeKey: String {
        "\(mode.rawValue)-\(model.items.count)-\(showsProgress)-\(model.isLogExpanded)-\(model.isBusy)-\(rcmModel.isLogExpanded)-\(rcmModel.isBusy)-\(displayedRemainingSeconds != nil)"
    }

    /// The tracker feeding this emits a fresh sample roughly every 100 ms. Binding
    /// the countdown's animation directly to that would retrigger a new 0.3 s
    /// transaction before the previous one finishes — the badge would never
    /// settle, looking restless for the whole transfer rather than just at the
    /// start. Refreshing the *displayed* value at most once a second gives each
    /// animation room to complete, like a real clock ticking instead of scrubbing.
    private func refreshCountdown(with newValue: Double?) {
        guard let newValue else {
            displayedRemainingSeconds = nil
            return
        }
        let previousWasSettled = displayedRemainingSeconds?.isFinite == true
        if previousWasSettled, newValue.isFinite,
           Date().timeIntervalSince(lastCountdownRefresh) < 1.0 {
            return
        }
        lastCountdownRefresh = Date()
        displayedRemainingSeconds = newValue
    }

    var body: some View {
        ZStack {
            VisualEffectBlur()
                .ignoresSafeArea()
            backgroundTint
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.35), value: model.phase)

            content
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)

            // Configures the NSWindow and lets it follow the content with animation.
            WindowStyleConfigurator(sizeKey: sizeKey)
                .allowsHitTesting(false)
                .frame(width: 0, height: 0)
        }
        // Header in the title bar zone, level with the traffic-light buttons.
        .overlay(alignment: .topLeading) {
            Text("\(Text("Sphaira ").fontWeight(.medium))\(Text("Connect").fontWeight(.heavy))")
                .font(.system(size: 14))
                .fontWidth(.expanded)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.leading, 80)
                .offset(y: -22)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            StatusPill(
                attached: mode == .install ? model.switchAttached : rcmModel.rcmAttached,
                deviceSummary: mode == .install
                    ? model.deviceSummary
                    : (rcmModel.rcmAttached ? String(localized: "Switch · RCM") : nil)
            )
                .padding(.trailing, 14)
                .offset(y: -24)
        }
        .frame(minWidth: 560)
        .onAppear { startSelectedMonitor() }
        .onDisappear {
            model.stopMonitoring()
            rcmModel.stopMonitoring()
        }
        .onChange(of: mode) {
            model.stopMonitoring()
            rcmModel.stopMonitoring()
            startSelectedMonitor()
        }
        .onChange(of: rawRemainingSeconds) { _, newValue in
            refreshCountdown(with: newValue)
        }
    }

    private var content: some View {
        VStack(spacing: Spacing.lg) {
            // Part of the normal layout flow, not an overlay: the window grows to
            // fit it in (see `sizeKey`) instead of it floating on top of the mode
            // switcher underneath.
            if let seconds = displayedRemainingSeconds {
                CountdownBadgeView(remainingSeconds: seconds)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ModeSwitcherView(mode: $mode, isDisabled: model.isBusy || rcmModel.isBusy)

            if mode == .install {
                installerContent
            } else {
                rcmContent
            }
        }
        .animation(.snappy(duration: 0.35), value: mode)
        .animation(.snappy(duration: 0.35), value: model.items.isEmpty)
        .animation(.snappy(duration: 0.35), value: showsProgress)
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .animation(.easeInOut(duration: 0.25), value: rcmModel.phase)
        .animation(.snappy(duration: 0.3), value: displayedRemainingSeconds)
    }

    @ViewBuilder
    private var installerContent: some View {
        Group {
            if model.items.isEmpty {
                DropZoneView(isCompact: false, isEnabled: !model.isBusy, onURLs: addAnimated)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                QueueListView(items: model.items, isBusy: model.isBusy) { item in
                    withAnimation(.snappy(duration: 0.3)) { model.remove(item) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                DropZoneView(isCompact: true, isEnabled: !model.isBusy, onURLs: addAnimated)
            }

            if model.phase == .waitingForSwitch {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Warte auf die Switch — dort die USB-Installation in Sphaira öffnen …")
                        .font(Fonts.helper)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            if let progress = model.progress, showsProgress {
                ProgressPanelView(progress: progress, totalCount: model.items.count, isFinished: isFinished)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            LogConsoleView(lines: model.log, isExpanded: $model.isLogExpanded)

            actionBar
        }
    }

    @ViewBuilder
    private var rcmContent: some View {
        RCMPresetView(
            presetURLs: rcmModel.presetURLs,
            selectedURL: rcmModel.payloadURL,
            isEnabled: !rcmModel.isBusy,
            isDownloadingHekate: rcmModel.isDownloadingHekate,
            isLoadingHekateReleases: rcmModel.isLoadingHekateReleases,
            hekateReleases: rcmModel.hekateReleases,
            isDownloadingFusee: rcmModel.isDownloadingFusee,
            isLoadingFuseeReleases: rcmModel.isLoadingFuseeReleases,
            fuseeReleases: rcmModel.fuseeReleases,
            onUse: rcmModel.usePreset,
            onAssign: rcmModel.assignPreset,
            onRemove: rcmModel.removePreset,
            onDownloadHekate: rcmModel.downloadHekate,
            onLoadHekateReleases: rcmModel.loadHekateReleases,
            onDownloadFusee: rcmModel.downloadFusee,
            onLoadFuseeReleases: rcmModel.loadFuseeReleases
        )

        RCMPayloadPickerView(
            selectedURL: rcmModel.payloadURL,
            byteCount: rcmModel.payloadByteCount,
            isEnabled: !rcmModel.isBusy,
            onSelect: rcmModel.selectPayload
        )

        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Die Switch muss sich im RCM-Modus befinden. Die Injektion startet ausschließlich mit dem Button unten und niemals automatisch.")
                .font(Fonts.helper)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.md)

        if rcmModel.isBusy || rcmModel.phase == .succeeded {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text(rcmProgressTitle)
                        .font(Fonts.helper)
                    Spacer()
                    if rcmModel.totalBytes > 0 {
                        Text("\(ByteFormat.size(Int64(rcmModel.sentBytes))) / \(ByteFormat.size(Int64(rcmModel.totalBytes)))")
                            .font(Fonts.helper)
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: rcmModel.progressFraction)
                    .progressViewStyle(.linear)
            }
            .padding(Spacing.md)
            .connectCard(radius: 12)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        LogConsoleView(lines: rcmModel.log, isExpanded: $rcmModel.isLogExpanded)
        rcmActionBar
    }

    private var actionBar: some View {
        HStack(spacing: Spacing.sm) {
            statusFootnote
            Spacer()

            GlassButton(String(localized: "Liste leeren"), systemImage: "trash",
                        kind: .clear, size: .standard,
                        isEnabled: !model.items.isEmpty && !model.isBusy) {
                withAnimation(.snappy(duration: 0.35)) { model.clearAll() }
            }
            .accessibilityLabel("Warteschlange leeren")

            if model.isBusy {
                GlassButton(String(localized: "Abbrechen"), systemImage: "xmark.circle",
                            kind: .red, size: .standard) {
                    model.cancel()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .accessibilityLabel("Übertragung abbrechen")
            }

            GlassButton(String(localized: "Installieren"), systemImage: "arrow.down.circle.fill",
                        kind: .green, size: .standard,
                        isEnabled: model.canStart) {
                model.start()
            }
            .accessibilityLabel("Übertragung zur Switch starten")
        }
        .animation(.snappy(duration: 0.25), value: model.isBusy)
    }

    private var rcmActionBar: some View {
        HStack(spacing: Spacing.sm) {
            rcmStatusFootnote
            Spacer()

            GlassButton(
                String(localized: "Payload injizieren"),
                systemImage: "bolt.horizontal.fill",
                kind: .orange,
                size: .standard,
                isEnabled: rcmModel.canInject
            ) {
                rcmModel.inject()
            }
            .accessibilityLabel("Ausgewählte Payload jetzt zur RCM-Switch senden")
        }
    }

    @ViewBuilder
    private var rcmStatusFootnote: some View {
        switch rcmModel.phase {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Fonts.helper)
                .foregroundStyle(Colors.danger)
                .lineLimit(2)
        case .succeeded:
            Label("Payload erfolgreich injiziert", systemImage: "checkmark.circle.fill")
                .font(Fonts.helper)
                .foregroundStyle(Colors.success)
        case .idle where !rcmModel.rcmAttached:
            Label("Keine Switch im RCM-Modus", systemImage: "cable.connector.slash")
                .font(Fonts.helper)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var rcmProgressTitle: String {
        switch rcmModel.phase {
        case .preparing: return String(localized: "Payload wird vorbereitet …")
        case .injecting: return String(localized: "Payload wird übertragen …")
        case .succeeded: return String(localized: "Payload wurde injiziert")
        default: return ""
        }
    }

    @ViewBuilder
    private var statusFootnote: some View {
        switch model.phase {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(Fonts.helper)
                .foregroundStyle(Colors.danger)
                .lineLimit(2)
        case .finished(let transferred):
            Label("\(transferred) Titel übertragen", systemImage: "checkmark.circle.fill")
                .font(Fonts.helper)
                .foregroundStyle(Colors.success)
        default:
            EmptyView()
        }
    }

    private func addAnimated(_ urls: [URL]) {
        withAnimation(.snappy(duration: 0.35)) { model.add(urls: urls) }
    }

    private func startSelectedMonitor() {
        if mode == .install {
            model.startMonitoring()
        } else {
            rcmModel.startMonitoring()
        }
    }
}
