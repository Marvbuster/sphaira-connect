import SwiftUI

/// Progress display: overall bar and current-file bar, speed, remaining time
/// and "x of y".
struct ProgressPanelView: View {
    var progress: TransferProgress
    var totalCount: Int
    var isFinished: Bool = false

    // The bars always show the real state. Forcing them to 100 % in the finished
    // state produced a full bar next to honest numbers like "741.8 MB of 1.1 GB"
    // — the display was lying.
    private var overallFraction: Double {
        guard progress.overallTotal > 0 else { return 0 }
        return min(1, Double(progress.overallSent) / Double(progress.overallTotal))
    }

    private var itemFraction: Double {
        guard progress.itemTotal > 0 else { return 0 }
        return min(1, Double(progress.itemSent) / Double(progress.itemTotal))
    }

    /// Complete means: every byte actually went over the wire.
    private var isComplete: Bool {
        isFinished && progress.overallSent >= progress.overallTotal
    }

    private var headlineText: String {
        guard isFinished else { return String(localized: "Übertragung läuft") }
        return isComplete
            ? String(localized: "Übertragung abgeschlossen")
            : String(localized: "Übertragung unvollständig")
    }

    private var headlineSymbol: String {
        guard isFinished else { return "arrow.down.circle" }
        return isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var headlineTint: Color {
        guard isFinished else { return .primary }
        return isComplete ? Colors.success : Colors.warning
    }

    private var remainingText: String {
        guard !isFinished, progress.bytesPerSecond > 0 else { return ByteFormat.duration(.nan) }
        let remaining = Double(progress.overallTotal - progress.overallSent) / progress.bytesPerSecond
        return ByteFormat.duration(remaining)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Label(headlineText, systemImage: headlineSymbol)
                    .font(Fonts.subtitle)
                    .foregroundStyle(headlineTint)
                    .contentTransition(.symbolEffect(.replace))
                Spacer()
                Text("\(min(progress.itemIndex + 1, max(totalCount, 1))) von \(max(totalCount, 1))")
                    .font(Fonts.badge)
                    .foregroundStyle(.secondary)
            }

            bar(fraction: overallFraction, tint: Colors.accent, height: 10)

            HStack {
                Text(progress.itemName)
                    .font(Fonts.helper)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(ByteFormat.size(progress.itemSent)) / \(ByteFormat.size(progress.itemTotal))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            bar(fraction: itemFraction, tint: Colors.success, height: 6)

            HStack(spacing: Spacing.lg) {
                Label(ByteFormat.rate(isFinished ? .nan : progress.bytesPerSecond), systemImage: "speedometer")
                Label("Rest: \(remainingText)", systemImage: "clock")
                Spacer()
                Text("\(ByteFormat.size(progress.overallSent)) von \(ByteFormat.size(progress.overallTotal))")
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(Spacing.lg)
        .connectCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fortschritt: \(Int(overallFraction * 100)) Prozent, \(progress.itemName)")
    }

    /// Bar with rounded caps and a soft animation.
    private func bar(fraction: Double, tint: Color, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(tint.gradient)
                    // Minimum width = height, so the capsule never collapses into a line.
                    .frame(width: max(height, geo.size.width * fraction))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}
