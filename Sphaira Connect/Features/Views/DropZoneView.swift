import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Drop area for files and folders. A click opens the file picker; drag-and-drop
/// highlights the area clearly while hovering.
struct DropZoneView: View {
    var isCompact: Bool = false
    var isEnabled: Bool = true
    var onURLs: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        Button(action: openPanel) {
            label
                .frame(maxWidth: .infinity)
                .frame(minHeight: isCompact ? 44 : 230)
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
        .scaleEffect(isTargeted ? 1.015 : 1)
        .animation(.snappy(duration: 0.2), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { handleDrop($0) }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel("Ablagefläche: Dateien oder Ordner ablegen, klicken zum Auswählen")
    }

    @ViewBuilder
    private var label: some View {
        if isCompact {
            HStack(spacing: Spacing.md) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "plus.circle.dashed")
                    .font(.system(size: 18, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                Text("Weitere Titel hier ablegen oder klicken")
                    .font(Fonts.helper)
            }
            .foregroundStyle(.secondary)
        } else {
            VStack(spacing: Spacing.md) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle.dotted")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(isTargeted ? Colors.accent : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text("NSP, XCI, NSZ oder XCZ hier ablegen")
                    .font(Fonts.subtitle)
                Text("Klicken zum Auswählen — Ordner werden durchsucht")
                    .font(Fonts.helper)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let usable = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !usable.isEmpty else { return false }
        let deliver = onURLs
        for provider in usable {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                // The provider delivers on an arbitrary queue — hop back to the MainActor.
                Task { @MainActor in deliver([url]) }
            }
        }
        return true
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Hinzufügen")
        panel.message = String(localized: "Titel oder Ordner auswählen")
        if panel.runModal() == .OK {
            onURLs(panel.urls)
        }
    }
}
