import SwiftUI
import ChessCore

/// What a player bar shows. `avatarAsset` nil means the user (accent tile with an initial).
/// `captured` holds piece codes as in the asset names ("bp", "wn"), cheapest first.
struct PlayerBarModel: Equatable {
    var name: String
    var elo: Int?
    var avatarAsset: String?
    var captured: [String]
    var materialLead: Int
    /// Review: the player's accuracy for the game, shown at the trailing edge.
    var accuracy: Double? = nil
}

/// One player above or below the board: avatar, name and Elo on the left; what they have
/// captured and their material lead on the right. 44 pt tall.
struct PlayerBar: View {
    let model: PlayerBarModel

    static let height: CGFloat = 44

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            avatar
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                Text(model.name)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.text)
                if let elo = model.elo {
                    Text(elo, format: .number.grouping(.never))
                        .font(DS.Font.numeral)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: DS.Spacing.s)
            CapturedTray(codes: model.captured, lead: model.materialLead)
            if let accuracy = model.accuracy {
                AccuracyChip(value: accuracy)
            }
        }
        .frame(height: Self.height)
        .padding(.horizontal, DS.Spacing.m)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var avatar: some View {
        if let asset = model.avatarAsset {
            Image(asset)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .background(DS.Color.boardDark, in: RoundedRectangle(cornerRadius: AvatarTile.radius(32)))
                .accessibilityHidden(true)
        } else {
            UserTile(size: 32)
        }
    }
}

/// "87.4" in mono on a quiet tile: the player's accuracy in Review.
private struct AccuracyChip: View {
    let value: Double

    var body: some View {
        Text(value, format: .number.precision(.fractionLength(1)))
            .font(DS.Font.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(DS.Color.text)
            .padding(.horizontal, DS.Spacing.s)
            .frame(minWidth: 52, minHeight: 28)
            .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.small))
            .accessibilityLabel("Accuracy \(value.formatted(.number.precision(.fractionLength(1))))")
    }
}

/// Small piece images, grouped by kind with same-kind pieces overlapping, then "+N".
private struct CapturedTray: View {
    let codes: [String]
    let lead: Int

    private static let size: CGFloat = 22

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                HStack(spacing: -Self.size * 0.55) {
                    ForEach(0..<group.count, id: \.self) { _ in
                        Image("Pieces/\(group.code)")
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: Self.size, height: Self.size)
                    }
                }
            }
            if lead > 0 {
                Text("+\(lead)")
                    .font(DS.Font.caption.monospaced().weight(.medium))
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.leading, DS.Spacing.xs)
            }
        }
        .accessibilityHidden(true)
    }

    private var groups: [(code: String, count: Int)] {
        var result: [(code: String, count: Int)] = []
        for code in codes {
            if let last = result.last, last.code == code {
                result[result.count - 1].count += 1
            } else {
                result.append((code, 1))
            }
        }
        return result
    }
}
