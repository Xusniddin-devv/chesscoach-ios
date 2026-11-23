import Testing
import UIKit
import ChessCore

/// Piece and bot art must resolve under the namespaced names the app uses.
struct AssetTests {
    static let pieceCodes = ["wk", "wq", "wr", "wb", "wn", "wp", "bk", "bq", "br", "bb", "bn", "bp"]

    @Test(arguments: pieceCodes)
    func pieceImageLoads(code: String) {
        #expect(UIImage(named: "Pieces/\(code)") != nil)
    }

    @Test(arguments: Bot.all)
    func botAvatarLoads(bot: Bot) {
        #expect(UIImage(named: bot.avatarAsset) != nil)
    }
}
