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

/// The user's avatar: their rating tier's piece (Pawn … King, `RatingTier`) in cream on the
/// same board-dark tile as the bots, so both players read as pieces on a dark square.
struct PlayerAvatarTile: View {
    let tier: RatingTier
    var size: CGFloat = 32

    var body: some View {
        AvatarImage(asset: tier.avatarAsset, size: size)
    }
}

/// An avatar asset on the board-dark tile. Piece art (`Pieces/…`) fills its canvas, so it
/// gets a margin to sit like the bot figures, which are already fitted into 80 %.
struct AvatarImage: View {
    let asset: String
    var size: CGFloat = 32

    var body: some View {
        Image(asset)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .padding(asset.hasPrefix("Pieces/") ? size * 0.12 : 0)
            .frame(width: size, height: size)
            .background(DS.Color.boardDark, in: RoundedRectangle(cornerRadius: AvatarTile.radius(size)))
            .accessibilityHidden(true)
    }
}

extension RatingTier {
    /// The tier's cream piece, e.g. "Pieces/wn" for the Knight.
    var avatarAsset: String {
        let letter = pieceKind == .pawn ? "p" : pieceKind.rawValue.lowercased()
        return "Pieces/w\(letter)"
    }
}
