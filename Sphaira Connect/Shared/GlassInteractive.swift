import SwiftUI

struct GlassInteractiveModifier: ViewModifier {
    var radius: CGFloat = 14
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(hovered ? 0.08 : 0.0))
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(hovered ? 0.20 : 0.0), radius: hovered ? 10 : 0, x: 0, y: hovered ? 4 : 0)
            .onHover { hovered = $0 }
            .animation(.snappy(duration: 0.18), value: hovered)
    }
}

extension View {
    func glassInteractive(radius: CGFloat = 14) -> some View {
        modifier(GlassInteractiveModifier(radius: radius))
    }
}
