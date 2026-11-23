import SwiftUI
import ChessCore

/// A bot's figure on a rounded tile. The tile is the board's dark square colour, so every
/// figure reads the way it does on the board: the slate figures (Wall, Vera, Apex) were
/// dark-on-dark on `surface2`, while cream and orange figures stay clear on stone grey.
struct AvatarTile: View {
    let bot: Bot
    var size: CGFloat = 40

    var body: some View {
        Image(bot.avatarAsset)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .background(DS.Color.boardDark, in: RoundedRectangle(cornerRadius: Self.radius(size)))
            .accessibilityHidden(true)
    }

    /// `Radius.medium` at 64 pt, `Radius.small` at 32–40 pt.
    static func radius(_ size: CGFloat) -> CGFloat { size >= 56 ? DS.Radius.medium : DS.Radius.small }
}

/// The user's tile: accent fill with an initial.
struct UserTile: View {
    var size: CGFloat = 32

    var body: some View {
        Text("Y")
            .font(DS.Font.headline)
            .foregroundStyle(DS.Color.onAccent)
            .frame(width: size, height: size)
            .background(DS.Color.accent, in: RoundedRectangle(cornerRadius: AvatarTile.radius(size)))
            .accessibilityHidden(true)
    }
}
