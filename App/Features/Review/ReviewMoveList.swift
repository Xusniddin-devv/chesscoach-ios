import SwiftUI
import ChessCore

/// The whole game as a classified list (a sheet from Review's action bar): accuracy and how
/// many moves of each class both sides played, then every move with its class. Tapping a
/// move shows it on the board.
struct ReviewMoveList: View {
    let model: ReviewModel
    let onSelect: (Int) -> Void

    /// Classes in the order a review reads them, best first.
    private static let summaryOrder: [MoveClass] = [
        .brilliant, .great, .best, .excellent, .good, .book, .forced, .inaccuracy, .mistake, .miss, .blunder,
    ]

    private var userColor: Piece.Color { model.snapshot.userColor }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    if model.analysis != nil { summary }
                    moves
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.top, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.l)
            }
            .onAppear {
                if model.selectedPly > 0 { proxy.scrollTo(rowNumber(forPly: model.selectedPly), anchor: .center) }
            }
        }
        .background(DS.Color.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DS.Color.background)
    }

    // MARK: Summary

    private var summary: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Accuracy")
                Spacer()
                column("You")
                column(model.botName)
            }
            .padding(.bottom, DS.Spacing.xs)
            HStack(alignment: .firstTextBaseline) {
                Spacer()
                numeral(model.accuracy(for: userColor).map { $0.formatted(.number.precision(.fractionLength(1))) })
                numeral(model.accuracy(for: userColor.opposite).map { $0.formatted(.number.precision(.fractionLength(1))) })
            }
            .padding(.bottom, DS.Spacing.sm)
            ForEach(Self.summaryOrder.filter { total($0) > 0 }, id: \.self) { moveClass in
                Divider().overlay(DS.Color.surface2)
                HStack {
                    Text(moveClass.glyph)
                        .font(DS.Font.badgeGlyph)
                        .foregroundStyle(DS.Color.moveClass(moveClass))
                        .frame(width: 22, alignment: .leading)
                    Text(moveClass.label)
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.text)
                    Spacer()
                    numeral("\(count(moveClass, userColor))", secondary: true)
                    numeral("\(count(moveClass, userColor.opposite))", secondary: true)
                }
                .padding(.vertical, DS.Spacing.s)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(moveClass.label): you \(count(moveClass, userColor)), \(model.botName) \(count(moveClass, userColor.opposite))")
            }
        }
        .padding(DS.Spacing.m)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
    }

    private static let columnWidth: CGFloat = 72

    private func column(_ title: String) -> some View {
        Text(title)
            .font(DS.Font.caption)
            .foregroundStyle(DS.Color.textSecondary)
            .lineLimit(1)
            .frame(width: Self.columnWidth, alignment: .trailing)
    }

    private func numeral(_ value: String?, secondary: Bool = false) -> some View {
        Text(value ?? "-")
            .font(secondary ? DS.Font.subheadline.monospacedDigit() : DS.Font.numeral)
            .foregroundStyle(DS.Color.text)
            .frame(width: Self.columnWidth, alignment: .trailing)
    }

    private func count(_ moveClass: MoveClass, _ color: Piece.Color) -> Int {
        model.analysis?.verdicts.filter { $0.mover == color && $0.classification == moveClass }.count ?? 0
    }

    private func total(_ moveClass: MoveClass) -> Int {
        count(moveClass, .white) + count(moveClass, .black)
    }

    // MARK: Moves

    private var rows: [MoveStripGroup] {
        let items = model.snapshot.sans.enumerated().map { index, san in
            MoveStripItem(ply: index + 1, san: san, moveClass: model.gameVerdict(atPly: index + 1)?.classification)
        }
        return MoveStripGroup.groups(items, startFen: model.snapshot.startFen)
    }

    private func rowNumber(forPly ply: Int) -> Int {
        rows.first { $0.white?.ply == ply || $0.black?.ply == ply }?.number ?? 0
    }

    private var moves: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            SectionLabel("Moves")
            VStack(spacing: 0) {
                ForEach(rows, id: \.number) { row in
                    HStack(spacing: DS.Spacing.s) {
                        Text("\(row.number).")
                            .font(DS.Font.subheadline.monospacedDigit())
                            .foregroundStyle(DS.Color.textSecondary)
                            .frame(width: 36, alignment: .leading)
                        cell(row.white)
                        cell(row.black)
                    }
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 2)
                    .id(row.number)
                }
            }
            .padding(.vertical, DS.Spacing.s)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
        }
    }

    @ViewBuilder
    private func cell(_ item: MoveStripItem?) -> some View {
        if let item {
            let current = !model.isInBranch && item.ply == model.selectedPly
            Button { onSelect(item.ply) } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Text(item.san)
                        .font(DS.Font.body.weight(current ? .semibold : .regular))
                        .foregroundStyle(DS.Color.text)
                    if let moveClass = item.moveClass {
                        Text(moveClass.glyph)
                            .font(DS.Font.badgeGlyph)
                            .foregroundStyle(DS.Color.moveClass(moveClass))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Spacing.s)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(current ? DS.Color.surface2 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.small))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.moveClass.map { "\(item.san), \($0.label)" } ?? item.san)
            .accessibilityAddTraits(current ? .isSelected : [])
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 40)
        }
    }
}
