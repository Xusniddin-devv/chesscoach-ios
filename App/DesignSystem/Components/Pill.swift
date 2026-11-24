import SwiftUI

struct Pill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.Font.caption.weight(.semibold))
            .foregroundStyle(DS.Color.text)
            .padding(.horizontal, DS.Spacing.s + 2)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.surface2, in: Capsule())
    }
}
