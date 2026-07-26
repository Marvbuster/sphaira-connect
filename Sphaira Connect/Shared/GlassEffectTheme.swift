import SwiftUI
import AppKit

// Liquid Glass card background (native glassEffect, macOS 26+)
struct GlassBackground: View {
    var cornerRadius: CGFloat = 14
    var tint: Color = Colors.backgroundTint

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    private var glass: Glass {
        tint == .clear ? .regular : .regular.tint(tint)
    }
}

// Blur behind the window — glassEffect cannot sample the desktop behind the
// window, but NSVisualEffectView can.
struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .underWindowBackground
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension View {
    // Grouping without a glass effect, for areas that contain glass elements
    // themselves (glass inside glass is unsupported and renders blurry)
    func connectCard(radius: CGFloat = 14, tint: Color = Colors.backgroundTint) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tint)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        )
    }
}
