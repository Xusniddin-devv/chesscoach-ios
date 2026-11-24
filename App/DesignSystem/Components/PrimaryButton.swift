import SwiftUI

/// Solid accent button with a 3 pt darker bottom edge. No gradient.
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.m)
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let edge: CGFloat = configuration.isPressed ? 0 : 3
        configuration.label
            .background(configuration.isPressed ? DS.Color.accentPressed : DS.Color.accent,
                        in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: DS.Radius.medium)
                    .fill(DS.Color.accentPressed)
                    .offset(y: edge)
            }
            .offset(y: configuration.isPressed ? 3 : 0)
            .padding(.bottom, 3)
    }
}
