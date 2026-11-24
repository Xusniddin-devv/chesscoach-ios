import SwiftUI

/// Small section label ("Recent games", "Mode"): sentence case, semibold, secondary.
/// No all-caps tracked labels (anti-slop).
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.Color.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}
