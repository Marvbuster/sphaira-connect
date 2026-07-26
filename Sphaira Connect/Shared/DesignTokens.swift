import SwiftUI

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Fonts {
    static let title = Font.system(size: 24, weight: .semibold)
    static let subtitle = Font.system(size: 16, weight: .regular)
    static let mono = Font.system(.body, design: .monospaced)
    static let helper = Font.system(size: 12, weight: .regular)
    static let badge = Font.system(size: 11, weight: .semibold)
}

enum Colors {
    static let backgroundTint = Color(hex: 0x0B1220, alpha: 0.45)        // calm blue, idle state
    static let backgroundTintActive = Color(hex: 0x0E2416, alpha: 0.42)  // greenish, while transferring
    static let backgroundTintError = Color(hex: 0x2A0E12, alpha: 0.42)   // reddish, on errors
    static let accent = Color.accentColor
    static let success = Color.green
    static let warning = Color.yellow
    static let danger = Color.red
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self = Color(red: r, green: g, blue: b, opacity: alpha)
    }
}
