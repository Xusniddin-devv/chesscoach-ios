import SwiftUI
import ChessCore

/// "vs Pip", when, and the result from the user's side.
struct GameRow: View {
    let snapshot: GameSnapshot

    private var bot: Bot? { snapshot.isImported ? nil : Bot.all.first { $0.id == snapshot.botId } }
    private var platform: ImportPlatform? { snapshot.source.flatMap(ImportPlatform.init(rawValue:)) }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let bot {
                AvatarTile(bot: bot, size: 32)
            } else if let platform {
                // Imported game: the platform's mark where a bot's figure would be.
                Glyph(name: platform == .lichess ? "lichess" : "chesscom", size: 18)
                    .foregroundStyle(DS.Color.text)
                    .frame(width: 32, height: 32)
                    .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: AvatarTile.radius(32)))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(bot?.name ?? snapshot.opponentName ?? snapshot.botId)")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.text)
                Text(when)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(outcome.score).font(DS.Font.numeral).foregroundStyle(DS.Color.text)
                Text(outcome.word).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var when: String {
        let date = snapshot.date
        let mode = platform?.title ?? (snapshot.mode == .training ? "Training" : "Silent")
        let day: String
        if Calendar.current.isDateInToday(date) {
            day = date.formatted(date: .omitted, time: .shortened)
        } else if Calendar.current.isDateInYesterday(date) {
            day = "Yesterday"
        } else {
            day = date.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(day) · \(mode)"
    }

    private var outcome: (score: String, word: String) {
        switch snapshot.result {
        case .draw: return ("½–½", "Draw")
        case .ongoing: return ("–", "Unfinished")
        case .whiteWins, .blackWins:
            let won = (snapshot.result == .whiteWins) == (snapshot.userColor == .white)
            return won ? ("1–0", "Won") : ("0–1", "Lost")
        }
    }
}
