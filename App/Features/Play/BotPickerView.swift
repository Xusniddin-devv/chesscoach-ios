import SwiftUI
import ChessCore

extension Bot {
    /// The bot closest in strength to the player (800 → Rookie Ron until ratings exist).
    static var suggested: Bot {
        all.min { abs($0.elo - PlayerProfile.defaultRating) < abs($1.elo - PlayerProfile.defaultRating) }!
    }
}

/// Pushed from Home: all 8 bots in one list, then mode and colour, and a pinned Play button.
struct BotPickerView: View {
    let onStart: (PlaySetup) -> Void

    @State private var selected = Bot.suggested
    @State private var mode = Pref.defaultModeValue
    @State private var color = PlaySetup.ColorChoice.white

    var body: some View {
        ScrollView {
            botList
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.m)
        }
        .background(DS.Color.background)
        .navigationTitle("Choose a bot")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        .safeAreaBar(edge: .bottom) { setup }
    }

    /// Mode, colour and Play stay pinned, so all three are always visible over the list.
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
            PrimaryButton(title: "Play \(selected.name)") {
                onStart(PlaySetup(bot: selected, mode: mode, color: color))
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

    private var botList: some View {
        VStack(spacing: 0) {
            ForEach(Bot.all) { bot in
                if bot.id != Bot.all.first?.id {
                    Divider().overlay(DS.Color.surface2).padding(.leading, DS.Spacing.m + 40 + DS.Spacing.sm)
                }
                BotRow(bot: bot, isSelected: bot == selected)
                    .onTapGesture { selected = bot }
            }
        }
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.large))
    }
}

private struct BotRow: View {
    let bot: Bot
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            AvatarTile(bot: bot, size: 40)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: DS.Radius.small + 3)
                            .strokeBorder(DS.Color.accent, lineWidth: 2)
                            .padding(-3)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                    Text(bot.name).font(DS.Font.headline).foregroundStyle(DS.Color.text)
                    Text(bot.elo, format: .number.grouping(.never))
                        .font(DS.Font.numeral)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Text(bot.blurb)
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.sm)
        .background { Rectangle().fill(isSelected ? DS.Color.surface2 : .clear) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private let settingLabelWidth: CGFloat = 72

/// "MODE  [ segmented ]": an uppercase label in a fixed column, then a segmented control.
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
