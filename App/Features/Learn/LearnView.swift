import SwiftUI
import SwiftData
import ChessCore

/// Learn tab: three tracks, each one list of lessons with a completion ring.
struct LearnView: View {
    @Query private var completed: [LessonProgress]
    @State private var open: Lesson?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    ForEach(LessonTrack.allCases, id: \.self) { track in
                        section(track)
                    }
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.l)
            }
            .background(DS.Color.background)
            .navigationTitle("Learn")
        }
        .fullScreenCover(item: $open) { lesson in
            LessonView(lesson: lesson) { next in open = next }
                .id(lesson.id)
        }
    }

    private var doneIds: Set<String> { Set(completed.map(\.lessonId)) }

    private func section(_ track: LessonTrack) -> some View {
        let lessons = LessonLibrary.lessons(in: track)
        let done = doneIds
        return VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(track.title)
                Spacer()
                Text("\(lessons.filter { done.contains($0.id) }.count) / \(lessons.count)")
                    .font(DS.Font.caption.monospaced())
                    .foregroundStyle(DS.Color.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                    if index > 0 {
                        Divider().overlay(DS.Color.surface2).padding(.leading, DS.Spacing.m + 28 + DS.Spacing.sm)
                    }
                    Button { open = lesson } label: {
                        LessonRow(number: index + 1, lesson: lesson, done: done.contains(lesson.id))
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
        }
    }
}

private struct LessonRow: View {
    let number: Int
    let lesson: Lesson
    let done: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(String(format: "%02d", number))
                .font(DS.Font.numeral)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.text)
                Text(meta)
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.s)
            DoneRing(done: done, size: 18)
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var meta: String {
        let side = lesson.userColor == .white ? "White" : "Black"
        switch lesson.goal {
        case .line: return "Play as \(side) · \(lesson.steps.filter { $0.side == .user }.count) moves"
        case .mate: return "Mate in one"
        case .win: return "Goal: checkmate as \(side)"
        case .draw: return "Goal: hold the draw as \(side)"
        }
    }
}
