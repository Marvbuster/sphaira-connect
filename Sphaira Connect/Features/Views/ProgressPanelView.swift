import SwiftUI

/// Fortschrittsanzeige: Gesamtbalken und aktueller Dateibalken,
/// Geschwindigkeit, Restzeit und "x von y".
struct ProgressPanelView: View {
    var progress: TransferProgress
    var totalCount: Int
    var isFinished: Bool = false

    private var overallFraction: Double {
        guard progress.overallTotal > 0 else { return 0 }
        return isFinished ? 1 : min(1, Double(progress.overallSent) / Double(progress.overallTotal))
    }

    private var itemFraction: Double {
        guard progress.itemTotal > 0 else { return 0 }
        return isFinished ? 1 : min(1, Double(progress.itemSent) / Double(progress.itemTotal))
    }

    private var remainingText: String {
        guard !isFinished, progress.bytesPerSecond > 0 else { return ByteFormat.duration(.nan) }
        let remaining = Double(progress.overallTotal - progress.overallSent) / progress.bytesPerSecond
        return ByteFormat.duration(remaining)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Label(isFinished ? "Übertragung abgeschlossen" : "Übertragung läuft",
                      systemImage: isFinished ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(Fonts.subtitle)
                    .foregroundStyle(isFinished ? Colors.success : .primary)
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

    /// Balken mit abgerundeten Enden und weicher Animation.
    private func bar(fraction: Double, tint: Color, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(tint.gradient)
                    // Mindestbreite = Höhe, damit die Kapsel nie zum Strich kollabiert.
                    .frame(width: max(height, geo.size.width * fraction))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}
