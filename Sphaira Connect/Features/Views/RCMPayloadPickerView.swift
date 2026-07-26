import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RCMPayloadPickerView: View {
    var selectedURL: URL?
    var byteCount: Int64?
    var isEnabled: Bool
    var onSelect: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        Button(action: openPanel) {
            VStack(spacing: Spacing.lg) {
                Image(systemName: selectedURL == nil ? "bolt.horizontal.circle" : "doc.badge.checkmark")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(isTargeted ? Colors.accent : .secondary)
                    .contentTransition(.symbolEffect(.replace))

                if let selectedURL {
                    VStack(spacing: Spacing.xs) {
                        Text(selectedURL.lastPathComponent)
                            .font(Fonts.subtitle)
                            .lineLimit(1)
                        if let byteCount {
                            Text(ByteFormat.size(byteCount))
                                .font(Fonts.helper)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(spacing: Spacing.xs) {
                        Text("RCM-Payload auswählen")
                            .font(Fonts.subtitle)
                        Text(".bin hier ablegen oder zum Auswählen klicken")
                            .font(Fonts.helper)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 190)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isTargeted ? Colors.accent.opacity(0.18) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isTargeted ? Colors.accent : Color.white.opacity(0.25),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [7, 6])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else {
                return false
            }
            let deliver = onSelect
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in deliver(url) }
            }
            return true
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel("RCM-Payload auswählen")
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "bin") ?? .data,
        ]
        panel.prompt = String(localized: "Payload auswählen")
        panel.message = String(localized: "Hekate-, Fusée- oder andere RCM-Payload auswählen")
        if panel.runModal() == .OK, let url = panel.url {
            onSelect(url)
        }
    }
}
