import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RCMPresetView: View {
    var presetURLs: [RCMPayloadPreset: URL]
    var selectedURL: URL?
    var isEnabled: Bool
    var isDownloadingHekate: Bool
    var isLoadingHekateReleases: Bool
    var hekateReleases: [HekateRelease]
    var isDownloadingFusee: Bool
    var isLoadingFuseeReleases: Bool
    var fuseeReleases: [FuseeRelease]
    var onUse: (RCMPayloadPreset) -> Void
    var onAssign: (RCMPayloadPreset, URL) -> Void
    var onRemove: (RCMPayloadPreset) -> Void
    var onDownloadHekate: (HekateRelease) -> Void
    var onLoadHekateReleases: () -> Void
    var onDownloadFusee: (FuseeRelease) -> Void
    var onLoadFuseeReleases: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Payload-Presets", systemImage: "star")
                .font(Fonts.helper)
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.sm) {
                ForEach(RCMPayloadPreset.allCases) { preset in
                    presetCard(preset)
                }
            }
        }
    }

    private func presetCard(_ preset: RCMPayloadPreset) -> some View {
        let url = presetURLs[preset]
        let isSelected = url?.standardizedFileURL == selectedURL?.standardizedFileURL

        return HStack(spacing: Spacing.sm) {
            Button {
                if url == nil {
                    configure(preset)
                } else {
                    onUse(preset)
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: preset.systemImage)
                        .foregroundStyle(isSelected ? Colors.accent : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preset.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(url?.lastPathComponent ?? String(localized: "Noch nicht eingerichtet"))
                            .font(Fonts.helper)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                configure(preset)
            } label: {
                Image(systemName: url == nil ? "plus.circle" : "pencil.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(url == nil
                  ? String(localized: "Preset einrichten")
                  : String(localized: "Preset-Datei ändern"))

            if preset == .hekate {
                if isLoadingHekateReleases || isDownloadingHekate {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 15, height: 15)
                        .padding(4)
                } else if hekateReleases.isEmpty {
                    Button {
                        onLoadHekateReleases()
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Verfügbare Hekate-Versionen laden")
                } else {
                    Menu {
                        ForEach(Array(hekateReleases.prefix(5).enumerated()), id: \.element.id) { index, release in
                            Button {
                                onDownloadHekate(release)
                            } label: {
                                if index == 0 {
                                    Text("\(release.tagName) (Neueste)")
                                } else {
                                    Text(release.tagName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Offizielle Hekate-Version laden")
                }
            } else if isLoadingFuseeReleases || isDownloadingFusee {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 15, height: 15)
                    .padding(4)
            } else if fuseeReleases.isEmpty {
                Button {
                    onLoadFuseeReleases()
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Verfügbare Fusée-Versionen laden")
            } else {
                Menu {
                    ForEach(Array(fuseeReleases.prefix(5).enumerated()), id: \.element.id) { index, release in
                        Button {
                            onDownloadFusee(release)
                        } label: {
                            if index == 0 {
                                Text("\(release.tagName) (Neueste)")
                            } else {
                                Text(release.tagName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Offizielle Fusée-Version laden")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(GlassBackground(
            cornerRadius: 12,
            tint: isSelected ? Colors.accent.opacity(0.15) : .clear
        ))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? Colors.accent.opacity(0.7) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .contextMenu {
            if url != nil {
                Button("Preset entfernen", role: .destructive) {
                    onRemove(preset)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(preset.title)-Preset")
        .onAppear {
            if preset == .hekate {
                onLoadHekateReleases()
            } else {
                onLoadFuseeReleases()
            }
        }
    }

    private func configure(_ preset: RCMPayloadPreset) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "bin") ?? .data,
        ]
        panel.prompt = String(localized: "Preset speichern")
        panel.message = String(localized: "Payload-Datei für \(preset.title) auswählen")
        if panel.runModal() == .OK, let url = panel.url {
            onAssign(preset, url)
        }
    }
}
