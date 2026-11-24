import SwiftUI
import SwiftData
import ChessCore

/// Learn tab: three tracks, each one list of lessons with a completion ring.
struct LearnView: View {
    @Query private var completed: [LessonProgress]
    @Environment(Entitlements.self) private var entitlements
    @State private var open: Lesson?
    @State private var showPaywall = false

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
        .paywall(isPresented: $showPaywall, feature: .allLessons)
        .fullScreenCover(item: $open) { lesson in
            LessonView(lesson: lesson) { next in open = next }
                .id(lesson.id)
        }
        #if DEBUG
        // `-debugLesson <track>:<n>` (e.g. openings:1) opens a lesson (screenshots).
        .task {
            guard let arg = UserDefaults.standard.string(forKey: "debugLesson") else { return }
            let parts = arg.split(separator: ":")
            let track = LessonTrack.allCases.first { "\($0)" == parts.first.map(String.init) } ?? .openings
            let n = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
            let lessons = LessonLibrary.lessons(in: track)
            if lessons.indices.contains(n - 1) { open = lessons[n - 1] }
        }
        #endif
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
                    let locked = LessonAllowance.isLocked(index: index, isPro: entitlements.isPro)
                    Button { if locked { showPaywall = true } else { open = lesson } } label: {
                        LessonRow(number: index + 1, lesson: lesson, done: done.contains(lesson.id), locked: locked)
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
    var locked = false

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
            if locked {
                Image("Icons/lock")  // Icons8, the app's one icon pack
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(DS.Color.textSecondary)
                    .frame(width: 16, height: 16)
                    .frame(width: 18, height: 18)
                    .accessibilityLabel("Pro")
            } else {
                DoneRing(done: done, size: 18)
            }
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
