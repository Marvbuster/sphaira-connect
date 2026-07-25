import SwiftUI

/// Verbindungsanzeige in der Titelleisten-Zone: Punkt plus Text, animierter Farbwechsel.
struct StatusPill: View {
    var attached: Bool
    var deviceSummary: String?

    private var color: Color {
        attached ? Colors.success : Color.white.opacity(0.35)
    }

    private var text: String {
        if let deviceSummary, attached { return deviceSummary }
        return attached ? "Switch verbunden" : "Keine Switch"
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(attached ? 0.8 : 0), radius: 4)
            Text(text)
                .font(Fonts.badge)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 5)
        .background(GlassBackground(cornerRadius: 12, tint: color.opacity(0.15)))
        .animation(.easeInOut(duration: 0.35), value: attached)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verbindungsstatus: \(text)")
    }
}
