import SwiftUI
import ChessCore

/// Sounds and haptics for a game screen, keyed off what the screen already shows: the SAN
/// list (a new last move → its sound and a light tap; a take-back is silent), a coach
/// interrupt (warning) and the result (success / error + win / lose sound).
/// Honours `Pref.sound` (inside `SoundPlayer`) and `Pref.haptics`.
///
///     .gameFeedback(sans: session.sans, interrupted: model.interruption != nil, outcome: model.outcome)
struct GameFeedback: ViewModifier {
    enum Outcome: Equatable { case won, lost, draw }

    let sans: [String]
    let interrupted: Bool
    let outcome: Outcome?

    @AppStorage(Pref.haptics) private var haptics = Pref.Default.haptics

    func body(content: Content) -> some View {
        content
            .onChange(of: sans) { old, new in
                guard new.count > old.count, let last = new.last else { return }
                SoundPlayer.shared.play(SoundPlayer.effect(forSAN: last))
            }
            .onChange(of: outcome) { _, result in
                switch result {
                case .won: SoundPlayer.shared.play(.win)
                case .lost: SoundPlayer.shared.play(.lose)
                case .draw, nil: break
                }
            }
            .sensoryFeedback(trigger: sans) { old, new in
                guard haptics, new.count > old.count, let last = new.last else { return nil }
                return last.contains("x") ? .impact(weight: .medium, intensity: 0.8) : .impact(weight: .light, intensity: 0.6)
            }
            .sensoryFeedback(trigger: interrupted) { _, now in
                haptics && now ? .warning : nil
            }
            .sensoryFeedback(trigger: outcome) { _, result in
                guard haptics, let result else { return nil }
                return result == .lost ? .error : .success
            }
    }
}

extension View {
    func gameFeedback(sans: [String], interrupted: Bool, outcome: GameFeedback.Outcome?) -> some View {
        modifier(GameFeedback(sans: sans, interrupted: interrupted, outcome: outcome))
    }
}
