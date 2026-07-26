import SwiftUI

/// Queue: name, size, state icon, remove button.
/// The entry currently in flight is highlighted.
struct QueueListView: View {
    var items: [InstallItem]
    var isBusy: Bool
    var onRemove: (InstallItem) -> Void

    private static let rowHeight: CGFloat = 40
    private static let rowSpacing: CGFloat = 2
    private static let maxListHeight: CGFloat = 320

    private var listHeight: CGFloat {
        let rows = CGFloat(items.count)
        let content = rows * Self.rowHeight + max(0, rows - 1) * Self.rowSpacing + Spacing.sm * 2
        return min(content, Self.maxListHeight)
    }

    private var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.byteCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("\(items.count) Titel · \(ByteFormat.size(totalBytes))")
                    .font(Fonts.helper)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            ScrollView {
                LazyVStack(spacing: Self.rowSpacing) {
                    ForEach(items) { item in
                        QueueRow(item: item, isBusy: isBusy) { onRemove(item) }
                    }
                }
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.sm)
            }
            .frame(height: listHeight)
        }
        .padding(.bottom, Spacing.xs)
        .connectCard()
    }
}

private struct QueueRow: View {
    let item: InstallItem
    let isBusy: Bool
    let onRemove: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            stateIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .failed(let reason) = item.state {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(Colors.danger)
                        .lineLimit(1)
                } else if case .skipped(let reason) = item.state {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(Colors.warning)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.md)

            Text(ByteFormat.size(item.byteCount))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isBusy ? 0.25 : (hovered ? 1 : 0.55))
            .accessibilityLabel("\(item.displayName) aus der Liste entfernen")
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(item.state == .transferring
                      ? Colors.accent.opacity(0.22)
                      : Color.white.opacity(hovered ? 0.07 : 0))
        )
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.2), value: item.state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.displayName), \(ByteFormat.size(item.byteCount)), \(stateDescription)")
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch item.state {
        case .queued:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.secondary)
        case .transferring:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Colors.success)
        case .skipped:
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(Colors.warning)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Colors.danger)
        }
    }

    private var stateDescription: String {
        switch item.state {
        case .queued: String(localized: "wartet")
        case .transferring: String(localized: "wird übertragen")
        case .done: String(localized: "fertig")
        case .skipped(let reason): String(localized: "übersprungen: \(reason)")
        case .failed(let reason): String(localized: "fehlgeschlagen: \(reason)")
        }
    }
}
