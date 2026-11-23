import SwiftUI

/// Small uppercase section label ("RECENT GAMES", "MODE").
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(DS.Font.label)
            .tracking(DS.Font.labelTracking)
            .foregroundStyle(DS.Color.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}
