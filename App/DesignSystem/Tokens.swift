import SwiftUI
import ChessCore

/// Design tokens. Values come from the spec (global-constraints.md).
enum DS {
    enum Color {
        static let background = SwiftUI.Color(hex: 0x131516)
        static let surface = SwiftUI.Color(hex: 0x1D2022)
        static let surface2 = SwiftUI.Color(hex: 0x2A2E31)
        static let text = SwiftUI.Color(hex: 0xECEEEE)
        static let textSecondary = SwiftUI.Color(hex: 0xECEEEE).opacity(0.6)
        static let accent = SwiftUI.Color(hex: 0xFF6A1A)
        static let accentPressed = SwiftUI.Color(hex: 0xCC4F0C)
        static let onAccent = SwiftUI.Color(hex: 0xFFFFFF)
        static let danger = SwiftUI.Color(hex: 0xFF3B46)
        static let boardLight = SwiftUI.Color(hex: 0xD6D9D8)
        static let boardDark = SwiftUI.Color(hex: 0x7D8483)

        /// Move-class colors. placeholder — replaced in Task 12 (web palette for now).
        static func moveClass(_ c: MoveClass) -> SwiftUI.Color {
            switch c {
            case .book: SwiftUI.Color(hex: 0xA88865)
            case .brilliant: SwiftUI.Color(hex: 0x26C2A3)
            case .great: SwiftUI.Color(hex: 0x5C8BB0)
            case .best: SwiftUI.Color(hex: 0x95BB4A)
            case .excellent: SwiftUI.Color(hex: 0x96BC4B)
            case .good: SwiftUI.Color(hex: 0x96AF8B)
            case .forced: SwiftUI.Color(hex: 0x9A9A94)
            case .inaccuracy: SwiftUI.Color(hex: 0xF0C15C)
            case .mistake: SwiftUI.Color(hex: 0xE58F2A)
            case .miss: SwiftUI.Color(hex: 0xFF7769)
            case .blunder: SwiftUI.Color(hex: 0xCA3431)
            }
        }
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
        static let large: CGFloat = 20
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    /// System font until the type scale is chosen in Task 12.
    enum Font {
        static let title = SwiftUI.Font.system(.title2, weight: .bold)
        static let headline = SwiftUI.Font.system(.headline)
        static let body = SwiftUI.Font.system(.body)
        static let caption = SwiftUI.Font.system(.caption)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}
