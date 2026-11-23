import SwiftUI

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.m)
                .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
        .buttonStyle(.plain)
    }
}
