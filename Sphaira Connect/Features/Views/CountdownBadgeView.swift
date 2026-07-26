import SwiftUI

/// Prominent remaining-time countdown shown at the top of the window while a
/// transfer or injection is actively running. Visibility is the caller's
/// responsibility (conditionally including this view); `.nan` still renders
/// gracefully as an en dash via `ByteFormat.duration`, so a momentary unknown
/// rate does not flicker the badge in and out.
struct CountdownBadgeView: View {
    var remainingSeconds: Double

    var body: some View {
        VStack(spacing: 2) {
            Text(ByteFormat.duration(remainingSeconds))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            Text("Verbleibend")
                .font(Fonts.helper)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .transition(.opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.92)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Verbleibende Zeit: \(ByteFormat.duration(remainingSeconds))")
    }
}
