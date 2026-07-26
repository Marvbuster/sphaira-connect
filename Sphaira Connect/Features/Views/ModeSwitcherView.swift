import SwiftUI

enum RootViewMode: String, CaseIterable, Identifiable {
    case install
    case rcm

    var id: Self { self }
}

/// Segmented switch between the Sphaira installer and RCM payload injection,
/// with a matched-geometry highlight that slides between the two buttons.
struct ModeSwitcherView: View {
    @Binding var mode: RootViewMode
    var isDisabled: Bool

    @Namespace private var modeSelection

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Modus", systemImage: "rectangle.2.swap")
                .font(Fonts.helper)
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.xs) {
                modeButton(.install, title: String(localized: "Sphaira-Installation"), systemImage: "shippingbox")
                modeButton(.rcm, title: String(localized: "RCM-Payload"), systemImage: "bolt.horizontal")
            }
            .padding(4)
            .background(GlassBackground(cornerRadius: 14, tint: .clear))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Arbeitsmodus")
    }

    private func modeButton(
        _ target: RootViewMode,
        title: String,
        systemImage: String
    ) -> some View {
        let isSelected = mode == target

        return Button {
            withAnimation(.snappy(duration: 0.28)) {
                mode = target
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Colors.accent.opacity(0.18))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Colors.accent.opacity(0.42), lineWidth: 1)
                            }
                            .matchedGeometryEffect(id: "mode-selection", in: modeSelection)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassInteractive(radius: 10)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
