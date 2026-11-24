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

        /// Move-class badge fills (docs/design/decisions.md, "Move-class palette").
        /// No hue can reach 3:1 against both board squares, so every badge carries a
        /// 2 pt `moveClassRing` stroke; the ring is what separates it from either square.
        static func moveClass(_ c: MoveClass) -> SwiftUI.Color {
            switch c {
            case .brilliant: SwiftUI.Color(hex: 0x22B3A6)
            case .great: SwiftUI.Color(hex: 0x4F8CE0)
            case .best: SwiftUI.Color(hex: 0x6DAA3C)
            case .excellent: SwiftUI.Color(hex: 0xA4C766)
            case .good: SwiftUI.Color(hex: 0x93B07C)
            case .book: SwiftUI.Color(hex: 0xB48A62)
            case .forced: SwiftUI.Color(hex: 0xAEB2B1)
            case .inaccuracy: SwiftUI.Color(hex: 0xF2C14E)
            case .mistake: SwiftUI.Color(hex: 0xF59A2E)
            case .miss: SwiftUI.Color(hex: 0xF2786B)
            case .blunder: SwiftUI.Color(hex: 0xFF3B46)
            }
        }

        /// Glyph colour on a move-class fill: the higher-contrast of white and ink.
        /// For the current palette ink wins for every class (5.2:1 to 10.9:1).
        static func moveClassGlyph(_: MoveClass) -> SwiftUI.Color { ink }

        /// Ring around move-class badges (12.9:1 on board light, 4.8:1 on board dark).
        static let moveClassRing = background
        /// Dark text/glyph colour used on light fills.
        static let ink = SwiftUI.Color(hex: 0x131516)
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
        static let large: CGFloat = 20
    }

    /// 4 pt grid. Screen side margin and card padding = m.
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let sm: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    /// Type scale (docs/design/decisions.md, "Type"). SF Pro for words, SF Mono for
    /// numbers that change or line up: clocks, Elo, accuracy, scores. All sizes are
    /// Dynamic Type text styles so they scale with the user's setting.
    enum Font {
        static let largeTitle = SwiftUI.Font.system(.largeTitle, weight: .bold)
        static let title = SwiftUI.Font.system(.title2, weight: .bold)
        static let headline = SwiftUI.Font.system(.headline)
        static let body = SwiftUI.Font.system(.body)
        static let subheadline = SwiftUI.Font.system(.subheadline)
        static let caption = SwiftUI.Font.system(.caption)
        /// Section labels: caption2 semibold, used uppercased with `labelTracking`.
        static let label = SwiftUI.Font.system(.caption2, weight: .semibold)
        static let labelTracking: CGFloat = 0.8
        /// Big result numerals (game-over accuracy, score).
        static let numeralLarge = SwiftUI.Font.system(.largeTitle, design: .monospaced, weight: .semibold)
        /// Inline numbers: Elo, move numbers, stat values.
        static let numeral = SwiftUI.Font.system(.headline, design: .monospaced, weight: .medium)
        /// Chess clock.
        static let clock = SwiftUI.Font.system(.title3, design: .monospaced, weight: .semibold)
        /// Move-class badge glyph.
        static let badgeGlyph = SwiftUI.Font.system(size: 12, weight: .heavy)
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
