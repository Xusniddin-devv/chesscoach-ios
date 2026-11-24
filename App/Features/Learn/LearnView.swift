import SwiftUI
import SwiftData
import ChessCore

/// Learn tab: the next lesson as the hero (its key position on a big board), then one track
/// at a time (segmented): progress as board squares and the lessons as rows with their
/// position in miniature, a number, title and goal; done = Icons8 check, Pro = Icons8 lock.
/// No cards: rows sit on the background between hairlines.
struct LearnView: View {
    @Query private var completed: [LessonProgress]
    @Environment(Entitlements.self) private var entitlements
    @State private var open: Lesson?
    @State private var showPaywall = false
    @AppStorage("learn.track") private var track: LessonTrack = .openings

    static let margin: CGFloat = 20

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let next = upNext { hero(next) }
                    Picker("Track", selection: $track) {
                        ForEach(LessonTrack.allCases, id: \.self) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 30)
                    trackSection(track)
                }
                .padding(.horizontal, Self.margin)
                .padding(.bottom, DS.Spacing.xl)
            }
            .contentMargins(.bottom, DS.Spacing.xl, for: .scrollContent)
            .scrollIndicators(.hidden)
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

    /// The first lesson not done yet that the player can open, across the tracks in order.
    private var upNext: Lesson? {
        let done = doneIds
        for track in LessonTrack.allCases {
            for (index, lesson) in LessonLibrary.lessons(in: track).enumerated()
            where !done.contains(lesson.id) && !LessonAllowance.isLocked(index: index, isPro: entitlements.isPro) {
                return lesson
            }
        }
        return nil
    }

    // MARK: Hero

    private func hero(_ lesson: Lesson) -> some View {
        Button { open = lesson } label: {
            HStack(alignment: .top, spacing: DS.Spacing.m) {
                MiniBoard(fen: lesson.previewFen, orientation: lesson.userColor)
                    .frame(width: 164, height: 164)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Up next · \(lesson.track.title)")
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(lesson.title)
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(DS.Color.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(lesson.summary)
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                    Text("Start lesson")
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Color.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: 164)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, DS.Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Starts the lesson")
    }

    // MARK: Track

    @ViewBuilder
    private func trackSection(_ track: LessonTrack) -> some View {
        let lessons = LessonLibrary.lessons(in: track)
        let done = doneIds
        let doneCount = lessons.filter { done.contains($0.id) }.count
        HStack(alignment: .center) {
            SquareProgress(done: doneCount, total: lessons.count, cell: 10)
            Spacer()
            Text("\(doneCount) of \(lessons.count) done")
                .font(DS.Font.subheadline.monospacedDigit())
                .foregroundStyle(DS.Color.textSecondary)
        }
        .padding(.top, DS.Spacing.m)
        .padding(.bottom, DS.Spacing.s)
        VStack(spacing: 0) {
            ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                let locked = LessonAllowance.isLocked(index: index, isPro: entitlements.isPro)
                Button { if locked { showPaywall = true } else { open = lesson } } label: {
                    LessonRow(number: index + 1, lesson: lesson, done: done.contains(lesson.id), locked: locked)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    if index < lessons.count - 1 { Rectangle().fill(DS.Color.surface2).frame(height: 1) }
                }
            }
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
            MiniBoard(fen: lesson.previewFen, orientation: lesson.userColor)
                .frame(width: 52, height: 52)
                .opacity(locked ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%02d", number))
                        .font(DS.Font.subheadline.monospacedDigit())
                        .foregroundStyle(DS.Color.textSecondary)
                    Text(lesson.title)
                        .font(DS.Font.headline)
                        .foregroundStyle(locked ? DS.Color.textSecondary : DS.Color.text)
                        .lineLimit(1)
                }
                Text(meta)
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.s)
            if locked {
                IconImage("lock", size: 16)
                    .foregroundStyle(DS.Color.textSecondary)
                    .accessibilityLabel("Pro")
            } else if done {
                IconImage("check", size: 18)
                    .foregroundStyle(DS.Color.accent)
                    .accessibilityLabel("Done")
            }
        }
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
        case .win: return "Checkmate as \(side)"
        case .draw: return "Hold the draw as \(side)"
        }
    }
}

extension LessonTrack {
    /// Segmented-control label.
    var shortTitle: String {
        switch self {
        case .openings: "Openings"
        case .endgames: "Endgames"
        case .checkmates: "Checkmates"
        }
    }
}

extension Lesson {
    /// The position that says what the lesson is: an opening's position after its line,
    /// otherwise the start.
    var previewFen: String {
        guard goal == .line, !steps.isEmpty else { return startFen }
        return Rules.fen(startFen: startFen, moves: steps.map(\.uci)) ?? startFen
    }
}
