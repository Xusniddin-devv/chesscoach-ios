import SwiftUI
import SwiftData
import ChessCore

extension Bot {
    /// The bot closest in strength to the player (800 → Rookie Ron until ratings exist).
    static var suggested: Bot {
        all.min { abs($0.elo - PlayerProfile.defaultRating) < abs($1.elo - PlayerProfile.defaultRating) }!
    }
}

/// Pushed from Home: the bots as a sparring ladder (beat a bot to open the next), then mode
/// and colour, and a pinned Play button. The next unbeaten bot is highlighted and selected;
/// bots above the player's reach are dimmed with a lock and "Beat Cadet to unlock". Pip,
/// Rookie Ron and Cadet are always open (`BotLadder`).
struct BotPickerView: View {
    let onStart: (PlaySetup) -> Void

    @Environment(EngineHub.self) private var hub
    @Query private var records: [GameRecord]
    @State private var selected: Bot?
    @State private var mode = Pref.defaultModeValue
    @State private var color = PlaySetup.ColorChoice.white

    private var ladder: BotLadder { BotLadder(records: records) }
    private var bot: Bot { selected ?? ladder.next ?? Bot.suggested }

    var body: some View {
        ScrollView {
            ladderList(ladder)
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.m)
        }
        .background(DS.Color.background)
        .navigationTitle("Sparring")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        .safeAreaBar(edge: .bottom) { setup }
    }

    /// Mode, colour and Play stay pinned, so all three are always visible over the ladder.
    private var setup: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                SettingRow(label: "Mode") {
                    Picker("Mode", selection: $mode) {
                        Text("Training").tag(PlayMode.training)
                        Text("Silent").tag(PlayMode.silent)
                    }
                }
                Text(modeExplanation)
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.leading, settingLabelWidth)
            }
            SettingRow(label: "Play as") {
                Picker("Play as", selection: $color) {
                    ForEach(PlaySetup.ColorChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            PrimaryButton(title: "Play \(bot.name)") {
                onStart(PlaySetup(bot: bot, mode: mode, color: color))
            }
            .padding(.top, DS.Spacing.xs)
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.s)
    }

    private var modeExplanation: String {
        switch mode {
        case .training: "The coach stops you after a mistake."
        case .silent: "No interruptions. Moves are still graded."
        }
    }

    private func ladderList(_ ladder: BotLadder) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(zip(ladder.bots, ladder.rungs).enumerated()), id: \.element.0.id) { index, item in
                let (rowBot, rung) = item
                LadderRow(bot: rowBot, rung: rung, isSelected: rowBot == bot,
                          isFirst: index == 0, isLast: index == ladder.bots.count - 1,
                          railAboveDone: index > 0 && ladder.rungs[index - 1].isBeaten,
                          railBelowDone: rung.isBeaten)
                    .onTapGesture {
                        guard ladder.isOpen(rowBot) else { return }
                        withAnimation(.snappy(duration: 0.2)) { selected = rowBot }
                    }
            }
        }
    }
}

extension BotLadder {
    /// The ladder from the saved games' wins and the player's estimate (analysis-board games
    /// never count).
    @MainActor init(records: [GameRecord], profile: ProfileModel? = nil) {
        let profile = profile ?? ProfileModel(records: records)
        var wins: [String: Int] = [:]
        for game in profile.games where ProfileModel.outcome(of: game.snapshot) == .win {
            wins[game.snapshot.botId, default: 0] += 1
        }
        self.init(wins: wins, rating: profile.estimate)
    }
}

extension BotLadder.Rung {
    var isBeaten: Bool {
        if case .beaten = self { return true }
        return false
    }
}

/// One rung: the bot's figure on the ladder's rail, name and Elo, and where it stands —
/// "Beaten · 2 wins", "Next up" (accent), its blurb when open, or a lock and "Beat Cadet to
/// unlock" (dimmed). The selected row sits on `surface` with an accent ring on the figure.
private struct LadderRow: View {
    let bot: Bot
    let rung: BotLadder.Rung
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let railAboveDone: Bool
    let railBelowDone: Bool

    private static let avatar: CGFloat = 52
    private var locked: Bool { if case .locked = rung { true } else { false } }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            figure
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                    Text(bot.name)
                        .font(DS.Font.headline)
                        .foregroundStyle(locked ? DS.Color.textSecondary : DS.Color.text)
                    Text(bot.elo, format: .number.grouping(.never))
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(DS.Color.textSecondary)
                }
                status
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.large)
                .fill(isSelected ? DS.Color.surface : .clear)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The figure on its tile, with the rail running through it from rung to rung.
    private var figure: some View {
        AvatarImage(asset: bot.avatarAsset, size: Self.avatar)
            .saturation(locked ? 0 : 1)
            .opacity(locked ? 0.35 : 1)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.medium + 3)
                        .strokeBorder(DS.Color.accent, lineWidth: 2)
                        .padding(-3)
                }
            }
            .background {
                // The rail: a 2 pt line between rungs, lit up to the last beaten bot.
                VStack(spacing: 0) {
                    Rectangle().fill(isFirst ? .clear : rail(railAboveDone))
                    Rectangle().fill(isLast ? .clear : rail(railBelowDone))
                }
                .frame(width: 2)
                .padding(.vertical, -14)
            }
    }

    private func rail(_ done: Bool) -> Color {
        done ? DS.Color.textSecondary : DS.Color.surface2
    }

    @ViewBuilder private var status: some View {
        switch rung {
        case .beaten(let wins):
            Text("Beaten · \(wins) \(wins == 1 ? "win" : "wins")")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
        case .next:
            Text("Next up")
                .font(DS.Font.subheadline.weight(.semibold))
                .foregroundStyle(DS.Color.accent)
        case .open:
            Text(bot.blurb)
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(2)
        case .locked(let requires):
            HStack(spacing: 5) {
                Image("Icons/lock")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 13, height: 13)
                Text("Beat \(requires.name) to unlock")
            }
            .font(DS.Font.subheadline)
            .foregroundStyle(DS.Color.textSecondary)
        }
    }
}

private let settingLabelWidth: CGFloat = 72

/// "Mode  [ segmented ]": a label in a fixed column, then a segmented control.
private struct SettingRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 0) {
            SectionLabel(label).frame(width: settingLabelWidth, alignment: .leading)
            control().pickerStyle(.segmented)
        }
    }
}
