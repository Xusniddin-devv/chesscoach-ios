import SwiftUI
import SwiftData
import ChessCore

/// Learn tab: a dark winding path (Duolingo's structure) told as a chess story (Chessigma's
/// locked bosses). Each track is a unit: a banner with its progress, then its lessons as
/// chunky round tokens with an Icons8 piece glyph, snaking left and right — done tokens in
/// accent, the next one pulsing with the coach standing beside it, later ones dimmed, Pro
/// ones locked — and a boss at the end: the sparring bot to beat to clear the unit
/// (a silhouette until the unit's lessons are done). Tapping a token opens a popover
/// anchored to it with the title and Start.
struct LearnView: View {
    @Query private var completed: [LessonProgress]
    @Query(sort: \GameRecord.date, order: .reverse) private var records: [GameRecord]
    @Environment(Entitlements.self) private var entitlements
    @State private var open: Lesson?
    @State private var showPaywall = false
    @State private var popover: String?
    @State private var bossGame: PlaySetup?

    /// The boss at the end of each unit, in track order (strength rises with the units).
    static let bosses: [LessonTrack: String] = [.openings: "ron", .endgames: "blaze", .checkmates: "cadet"]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(LessonTrack.allCases.enumerated()), id: \.element) { index, track in
                            unit(index: index, track: track)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.m)
                    .padding(.bottom, DS.Spacing.xl)
                }
                .contentMargins(.bottom, DS.Spacing.xl, for: .scrollContent)
                .scrollIndicators(.hidden)
                .background(DS.Color.background)
                .task {
                    if let current { proxy.scrollTo(current.id, anchor: .center) }
                    #if DEBUG
                    if UserDefaults.standard.string(forKey: "debugLearnPopover") != nil, let current {
                        try? await Task.sleep(for: .seconds(0.8))
                        popover = current.id
                    }
                    #endif
                }
            }
            .navigationTitle("Learn")
            .navigationBarTitleDisplayMode(.inline)
        }
        .paywall(isPresented: $showPaywall, feature: .allLessons)
        .fullScreenCover(item: $open) { lesson in
            LessonView(lesson: lesson) { next in open = next }
                .id(lesson.id)
        }
        .fullScreenCover(item: $bossGame) { setup in
            PlayView(setup: setup) { _ in }
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

    // MARK: State

    private var doneIds: Set<String> { Set(completed.map(\.lessonId)) }

    /// The next lesson to do: the first not done that the player can open, in path order.
    private var current: Lesson? {
        let done = doneIds
        for track in LessonTrack.allCases {
            for (index, lesson) in LessonLibrary.lessons(in: track).enumerated()
            where !done.contains(lesson.id) && !LessonAllowance.isLocked(index: index, isPro: entitlements.isPro) {
                return lesson
            }
        }
        return nil
    }

    /// Path order of a lesson, to dim everything after the current one.
    private func order(_ lesson: Lesson) -> Int {
        var n = 0
        for track in LessonTrack.allCases {
            for l in LessonLibrary.lessons(in: track) {
                if l.id == lesson.id { return n }
                n += 1
            }
        }
        return n
    }

    private func beaten(_ bot: Bot) -> Bool {
        records.contains { record in
            guard let s = record.snapshot, !s.isFreeplay, !s.isImported, s.botId == bot.id else { return false }
            return ProfileModel.outcome(of: s) == .win
        }
    }

    // MARK: Unit

    @ViewBuilder
    private func unit(index: Int, track: LessonTrack) -> some View {
        let lessons = LessonLibrary.lessons(in: track)
        let done = doneIds
        let doneCount = lessons.filter { done.contains($0.id) }.count
        let isCurrentUnit = current.map { $0.track == track } ?? false
        UnitBanner(number: index + 1, track: track, done: doneCount, total: lessons.count, highlighted: isCurrentUnit)
            .padding(.top, index == 0 ? DS.Spacing.s : 40)
            .padding(.bottom, DS.Spacing.l)
        let currentOrder = current.map(order) ?? Int.max
        ForEach(Array(lessons.enumerated()), id: \.element.id) { i, lesson in
            let state = nodeState(lesson, index: i, done: done, currentOrder: currentOrder)
            PathRow(offset: Self.offset(i), showsCoach: state == .current) {
                LessonToken(glyph: Self.glyph(for: lesson), state: state) { popover = lesson.id }
                    .popover(isPresented: binding(lesson.id), attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        LessonPopover(lesson: lesson, number: i + 1, state: state) {
                            popover = nil
                            if state == .locked { showPaywall = true } else { open = lesson }
                        }
                        .presentationCompactAdaptation(.popover)
                    }
            }
            .id(lesson.id)
        }
        if let id = Self.bosses[track], let bot = Bot.all.first(where: { $0.id == id }) {
            let unlocked = doneCount == lessons.count
            let cleared = unlocked && beaten(bot)
            PathRow(offset: 0, showsCoach: false) {
                BossToken(bot: bot, unlocked: unlocked, cleared: cleared) { popover = "boss-\(track)" }
                    .popover(isPresented: binding("boss-\(track)"), attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        BossPopover(bot: bot, track: track, unlocked: unlocked, cleared: cleared) {
                            popover = nil
                            bossGame = PlaySetup(bot: bot, mode: .training, color: .white)
                        }
                        .presentationCompactAdaptation(.popover)
                    }
            }
            .padding(.top, DS.Spacing.s)
        }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding { popover == id } set: { if !$0, popover == id { popover = nil } }
    }

    private func nodeState(_ lesson: Lesson, index: Int, done: Set<String>, currentOrder: Int) -> LessonToken.State {
        if done.contains(lesson.id) { return .done }
        if LessonAllowance.isLocked(index: index, isPro: entitlements.isPro) { return .locked }
        let o = order(lesson)
        if o == currentOrder { return .current }
        return o > currentOrder ? .later : .open
    }

    /// The snake: tokens swing left and right around the centre line.
    static func offset(_ i: Int) -> CGFloat {
        let pattern: [CGFloat] = [0, 0.55, 0.9, 0.55, 0, -0.55, -0.9, -0.55]
        return pattern[i % pattern.count] * 84
    }

    /// The Icons8 piece glyph that says what the lesson is about.
    static func glyph(for lesson: Lesson) -> String {
        let t = lesson.title.lowercased()
        if t.contains("queen") { return "piece-queen" }
        if t.contains("rook") { return "piece-rook" }
        if t.contains("bishop") { return "piece-bishop" }
        if t.contains("knight") { return "piece-knight" }
        if t.contains("pawn") { return "piece-pawn" }
        switch lesson.track {
        case .openings: return lesson.userColor == .white ? "piece-knight" : "piece-pawn"
        case .endgames: return "piece-king"
        case .checkmates: return "piece-queen"
        }
    }
}

// MARK: Pieces of the path

/// "Unit 1 · Openings", the unit's goal and its progress. Accent for the unit in progress.
private struct UnitBanner: View {
    let number: Int
    let track: LessonTrack
    let done: Int
    let total: Int
    let highlighted: Bool

    private var subtitle: String {
        switch track {
        case .openings: "Start games the way strong players do"
        case .endgames: "Turn an extra piece into a win"
        case .checkmates: "The patterns that finish games"
        }
    }

    var body: some View {
        let ink: Color = highlighted ? DS.Color.onAccent : DS.Color.text
        HStack(alignment: .center, spacing: DS.Spacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Unit \(number) · \(track.title)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(ink.opacity(0.75))
                Text(subtitle)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ink.opacity(0.22))
                        Capsule().fill(ink).frame(width: max(8, geo.size.width * CGFloat(done) / CGFloat(max(total, 1))))
                            .opacity(done > 0 ? 1 : 0)
                    }
                }
                .frame(height: 6)
                .padding(.top, 6)
            }
            Text(verbatim: "\(done)/\(total)")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(ink)
        }
        .padding(DS.Spacing.m)
        .background(highlighted ? DS.Color.accent : DS.Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(highlighted ? DS.Color.accentPressed : Color(hex: 0x0E1011))
                .offset(y: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One step of the snake: the token at its offset, the coach beside it when it's the next one.
private struct PathRow<Token: View>: View {
    let offset: CGFloat
    let showsCoach: Bool
    @ViewBuilder let token: Token

    var body: some View {
        ZStack {
            token.offset(x: offset)
            if showsCoach {
                CoachAvatar(pose: .neutral, size: 92, grounded: true)
                    .offset(x: offset > 0 ? offset - 118 : offset + 118, y: -6)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
    }
}

/// A chunky round lesson token with the lesson's piece glyph.
private struct LessonToken: View {
    enum State { case done, current, open, later, locked }

    let glyph: String
    let state: State
    let action: () -> Void
    @SwiftUI.State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var face: Color {
        switch state {
        case .done, .current: DS.Color.accent
        case .open, .later, .locked: DS.Color.surface2
        }
    }

    private var edge: Color {
        switch state {
        case .done, .current: DS.Color.accentPressed
        default: Color(hex: 0x0E1011)
        }
    }

    var body: some View {
        Button(action: action) {
            IconImage(glyph, size: 36)
                .foregroundStyle(state == .done || state == .current ? DS.Color.onAccent
                                 : state == .open ? DS.Color.text : DS.Color.text.opacity(0.38))
        }
        .buttonStyle(TokenStyle(face: face, edge: edge))
        .frame(width: 74, height: 74)
        .background {
            if state == .current {
                Circle()
                    .strokeBorder(DS.Color.accent.opacity(0.55), lineWidth: 5)
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse ? 1.08 : 0.96)
                    .opacity(pulse ? 0.35 : 0.9)
                    .offset(y: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if state == .done || state == .locked {
                IconImage(state == .done ? "check" : "lock", size: 12)
                    .foregroundStyle(state == .done ? DS.Color.accent : DS.Color.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(DS.Color.background, in: Circle())
                    .overlay(Circle().strokeBorder(state == .done ? DS.Color.accent : DS.Color.surface2, lineWidth: 2))
                    .offset(x: 4, y: -4)
            }
        }
        .onAppear {
            guard state == .current, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel(label)
    }

    private var label: String {
        switch state {
        case .done: "Done"
        case .current: "Next lesson"
        case .open, .later: "Lesson"
        case .locked: "Pro lesson"
        }
    }
}

/// A round chunky face over a darker edge that it sinks into when pressed.
private struct TokenStyle: ButtonStyle {
    let face: Color
    let edge: Color

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .frame(width: 74, height: 68)
            .background(face, in: Ellipse())
            .background(alignment: .bottom) {
                Ellipse().fill(edge).frame(height: 68).offset(y: pressed ? 0 : 6)
            }
            .offset(y: pressed ? 6 : 0)
            .animation(.snappy(duration: 0.12), value: pressed)
    }
}

/// The unit's boss: the sparring bot on a bigger token; a silhouette with a lock until the
/// unit's lessons are done; a check once beaten.
private struct BossToken: View {
    let bot: Bot
    let unlocked: Bool
    let cleared: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(bot.avatarAsset)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 70, height: 70)
                    .saturation(unlocked ? 1 : 0)
                    .brightness(unlocked ? 0 : -0.62)
            }
            .buttonStyle(BossStyle(face: unlocked ? DS.Color.boardDark : DS.Color.surface,
                                   ring: cleared ? DS.Color.accent : unlocked ? DS.Color.text.opacity(0.7) : DS.Color.surface2))
            .overlay(alignment: .bottomTrailing) {
                IconImage(cleared ? "check" : "lock", size: 13)
                    .foregroundStyle(cleared ? DS.Color.accent : DS.Color.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(DS.Color.background, in: Circle())
                    .overlay(Circle().strokeBorder(cleared ? DS.Color.accent : DS.Color.surface2, lineWidth: 2))
                    .opacity(cleared || !unlocked ? 1 : 0)
            }
            Text(unlocked ? "Boss · \(bot.name)" : "Boss · ???")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(unlocked ? DS.Color.text : DS.Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(unlocked ? "Boss \(bot.name)" : "Locked boss")
    }
}

private struct BossStyle: ButtonStyle {
    let face: Color
    let ring: Color

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .frame(width: 92, height: 88)
            .background(face, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(ring, lineWidth: 3))
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(hex: 0x0E1011))
                    .frame(height: 88).offset(y: pressed ? 0 : 6)
            }
            .offset(y: pressed ? 6 : 0)
            .animation(.snappy(duration: 0.12), value: pressed)
    }
}

private struct LessonPopover: View {
    let lesson: Lesson
    let number: Int
    let state: LessonToken.State
    let onStart: () -> Void

    private var meta: String {
        let side = lesson.userColor == .white ? "White" : "Black"
        switch lesson.goal {
        case .line: return "Lesson \(number) · play as \(side) · \(lesson.steps.filter { $0.side == .user }.count) moves"
        case .mate: return "Lesson \(number) · mate in one"
        case .win: return "Lesson \(number) · checkmate as \(side)"
        case .draw: return "Lesson \(number) · hold the draw"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text(lesson.title)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(DS.Color.text)
            Text(meta)
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
            CoachText(CoachText.marked(lesson.summary))
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.text)
                .fixedSize(horizontal: false, vertical: true)
            Button(state == .locked ? "Unlock with Pro" : state == .done ? "Practise again" : "Start", action: onStart)
                .buttonStyle(ChunkyButtonStyle(height: 46))
                .padding(.top, DS.Spacing.xs)
        }
        .padding(DS.Spacing.m)
        .frame(width: 280, alignment: .leading)
        .presentationBackground(DS.Color.surface)
    }
}

private struct BossPopover: View {
    let bot: Bot
    let track: LessonTrack
    let unlocked: Bool
    let cleared: Bool
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text(unlocked ? "Boss: \(bot.name)" : "A boss waits here")
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(DS.Color.text)
            Text(unlocked
                 ? (cleared ? "Beaten. The unit is clear. Play again any time." : "Beat \(bot.name) (\(bot.elo)) with what this unit taught you to clear it.")
                 : "Finish every \(track.title.lowercased()) lesson to see who it is.")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if unlocked {
                Button("Play \(bot.name)", action: onPlay)
                    .buttonStyle(ChunkyButtonStyle(height: 46))
                    .padding(.top, DS.Spacing.xs)
            }
        }
        .padding(DS.Spacing.m)
        .frame(width: 280, alignment: .leading)
        .presentationBackground(DS.Color.surface)
    }
}
