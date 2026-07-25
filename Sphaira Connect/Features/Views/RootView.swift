import SwiftUI

/// Hauptansicht: Hintergrund mit Zustands-Farbschleier, Kopfzeile in der
/// Titelleisten-Zone, Ablage bzw. Warteschlange, Fortschritt, Protokoll, Aktionen.
struct RootView: View {
    @State private var model = InstallerModel()

    private var backgroundTint: Color {
        switch model.phase {
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

    private var sizeKey: String {
        "\(model.items.count)-\(showsProgress)-\(model.isLogExpanded)-\(model.isBusy)"
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

            // Konfiguriert das NSWindow und lässt es dem Inhalt animiert folgen.
            WindowStyleConfigurator(sizeKey: sizeKey)
                .allowsHitTesting(false)
                .frame(width: 0, height: 0)
        }
        // Kopfzeile in der Titelleisten-Zone, auf Höhe der Ampelknöpfe.
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
            StatusPill(attached: model.switchAttached, deviceSummary: model.deviceSummary)
                .padding(.trailing, 14)
                .offset(y: -24)
        }
        .frame(minWidth: 560)
        .onAppear { model.startMonitoring() }
        .onDisappear { model.stopMonitoring() }
    }

    private var content: some View {
        VStack(spacing: Spacing.lg) {
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
        .animation(.snappy(duration: 0.35), value: model.items.isEmpty)
        .animation(.snappy(duration: 0.35), value: showsProgress)
        .animation(.easeInOut(duration: 0.25), value: model.phase)
    }

    private var actionBar: some View {
        HStack(spacing: Spacing.sm) {
            statusFootnote
            Spacer()

            GlassButton("Liste leeren", systemImage: "trash",
                        kind: .clear, size: .standard,
                        isEnabled: !model.items.isEmpty && !model.isBusy) {
                withAnimation(.snappy(duration: 0.35)) { model.clearAll() }
            }
            .accessibilityLabel("Warteschlange leeren")

            if model.isBusy {
                GlassButton("Abbrechen", systemImage: "xmark.circle",
                            kind: .red, size: .standard) {
                    model.cancel()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .accessibilityLabel("Übertragung abbrechen")
            }

            GlassButton("Installieren", systemImage: "arrow.down.circle.fill",
                        kind: .green, size: .standard,
                        isEnabled: model.canStart) {
                model.start()
            }
            .accessibilityLabel("Übertragung zur Switch starten")
        }
        .animation(.snappy(duration: 0.25), value: model.isBusy)
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
}
