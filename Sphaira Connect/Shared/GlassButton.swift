import SwiftUI

enum GlassButtonKind {
    case clear
    case green
    case red
    case orange
}

enum GlassButtonSize {
    case compact
    case standard

    var vPad: CGFloat { self == .compact ? 6 : 10 }
    var hPad: CGFloat { self == .compact ? 10 : 14 }
    var minHeight: CGFloat { self == .compact ? 30 : 36 }
    var font: Font { self == .compact ? .system(size: 13, weight: .semibold) : .system(size: 14, weight: .semibold) }
    var spacing: CGFloat { self == .compact ? Spacing.sm : Spacing.md }
}

struct GlassButton: View {
    let title: String
    let systemImage: String?
    let kind: GlassButtonKind
    var cornerRadius: CGFloat = 14
    var size: GlassButtonSize = .compact
    var isEnabled: Bool = true
    var action: () -> Void

    init(_ title: String,
         systemImage: String? = nil,
         kind: GlassButtonKind = .clear,
         cornerRadius: CGFloat = 14,
         size: GlassButtonSize = .compact,
         isEnabled: Bool = true,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.cornerRadius = cornerRadius
        self.size = size
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: size.spacing) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(size.font)
            }
            .padding(.vertical, size.vPad)
            .padding(.horizontal, size.hPad)
            .frame(minHeight: size.minHeight)
            .modifier(GlassBody(cornerRadius: cornerRadius, kind: kind))
            .contentShape(Rectangle())
            .glassInteractive(radius: cornerRadius)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.45)
    }
}

private struct GlassBody: ViewModifier {
    var cornerRadius: CGFloat
    var kind: GlassButtonKind

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.clear)
                .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        )
    }

    private var glass: Glass {
        switch kind {
        case .clear: return .regular.interactive()
        case .green: return .regular.tint(.green.opacity(0.2)).interactive()
        case .red: return .regular.tint(.red.opacity(0.2)).interactive()
        case .orange: return .regular.tint(.orange.opacity(0.2)).interactive()
        }
    }
}
