import SwiftUI
import ChessCore

/// What Coach Pro unlocks (spec → Monetization, "Free vs Pro"). Each case carries the one line
/// the paywall opens with when the user came from that feature.
///
/// Gate API, for the screens on other branches:
///
///     // Show one thing to Pro users and another to free users:
///     ProGate(.fullReview) { BadgesOnBoard() } locked: { UpgradeButton(.fullReview, title: "Unlock review") }
///
///     // A plain check (counts, limits):
///     @Environment(Entitlements.self) private var entitlements
///     if entitlements.isPro || solvedToday < ProFeature.freePuzzlesPerDay { … }
///
///     // Open the paywall from any button:
///     UpgradeButton(.allLessons, title: "Unlock all lessons")        // accent text button
///     UpgradeButton(.allLessons) { LockedLessonRow(lesson) }         // custom label
///     .paywall(isPresented: $showing, feature: .gameImport)          // own state
///
/// Rule: analysis is always computed and stored for everyone; gate only what is shown.
enum ProFeature: String, CaseIterable, Identifiable {
    /// Training mode: the coach card's explanation text (the class pill stays free).
    case trainingExplanations
    /// Review: on-board badges/colours, explanations, branching, best lines and arrows.
    case fullReview
    /// Puzzles beyond `freePuzzlesPerDay` + the daily one. Own-mistake puzzles count inside
    /// the free allowance (ruling, decisions.md "Pro gates").
    case unlimitedPuzzles
    /// Learn: lessons after the first in each track.
    case allLessons
    /// chess.com / Lichess game import (outside onboarding, which is free).
    case gameImport
    /// Guess-the-move.
    case guessTheMove
    /// Deep analysis (longer engine search).
    case deepAnalysis
    /// Profile: the habits after the top one (`WeaknessAllowance`). Freeplay's live grades
    /// stay free (ruling, decisions.md "Pro gates").
    case allWeaknesses
    /// New chess.com / Lichess games synced from the linked account on their own.
    case autoSync

    var id: String { rawValue }

    /// Free allowances (spec: "my call, tune later").
    static let freePuzzlesPerDay = 5
    static let freeLessonsPerTrack = 1

    /// The paywall's subtitle when opened from this feature.
    var pitch: String {
        switch self {
        case .trainingExplanations: "The coach tells you why, in plain words, after every mistake."
        case .fullReview: "Every move of every game graded on the board, with the better line."
        case .unlimitedPuzzles: "Keep solving after today's five, including puzzles from your own games."
        case .allLessons: "Every lesson in every track."
        case .gameImport: "Bring your chess.com and Lichess games in and review them here."
        case .guessTheMove: "Guess the moves of your games and see how close you came to the engine."
        case .deepAnalysis: "Let the engine think longer on every position."
        case .allWeaknesses: "See every habit that keeps costing you games, not just the top one."
        case .autoSync: "Your new chess.com and Lichess games arrive on their own, analysed and turned into puzzles."
        }
    }
}

/// Shows `content` to Pro users and `locked` to everyone else.
struct ProGate<Content: View, Locked: View>: View {
    let feature: ProFeature
    @ViewBuilder let content: () -> Content
    @ViewBuilder let locked: () -> Locked

    @Environment(Entitlements.self) private var entitlements

    init(_ feature: ProFeature, @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder locked: @escaping () -> Locked) {
        self.feature = feature
        self.content = content
        self.locked = locked
    }

    var body: some View {
        if entitlements.isPro { content() } else { locked() }
    }
}

/// A button that opens the paywall for `feature`. It owns its sheet, so it works inside
/// full-screen covers and other sheets.
struct UpgradeButton<Label: View>: View {
    let feature: ProFeature?
    @ViewBuilder let label: () -> Label
    @State private var showing = false

    init(_ feature: ProFeature?, @ViewBuilder label: @escaping () -> Label) {
        self.feature = feature
        self.label = label
    }

    var body: some View {
        Button { showing = true } label: { label() }
            .buttonStyle(.plain)
            .paywall(isPresented: $showing, feature: feature)
    }
}

extension UpgradeButton where Label == Text {
    /// Accent `headline` text button: "Unlock explanations".
    init(_ feature: ProFeature?, title: String) {
        self.init(feature) {
            Text(title)
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.accent)
        }
    }
}

extension View {
    /// Presents the paywall as a sheet.
    func paywall(isPresented: Binding<Bool>, feature: ProFeature? = nil) -> some View {
        sheet(isPresented: isPresented) {
            PaywallView(feature: feature)
        }
    }
}

/// The coach card's explanation slot for free users: one quiet line and the unlock button.
struct LockedExplanation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Why it's a mistake, in plain words, is part of Pro.")
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Subheadline, not headline: "Show best" below stays the card's one loud accent.
            UpgradeButton(.trainingExplanations) {
                Text("Unlock explanations")
                    .font(DS.Font.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Color.accent)
            }
        }
    }
}

/// Free puzzle allowance: `ProFeature.freePuzzlesPerDay` puzzles a day besides the daily one.
enum PuzzleAllowance {
    /// Distinct puzzles first attempted or retried today, not counting the daily puzzle.
    static func usedToday(_ progress: [PuzzleProgress], dailyId: String?, now: Date = .now,
                          calendar: Calendar = .current) -> Int {
        Set(progress.filter { row in
            row.puzzleId != dailyId && (row.lastAttempt.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
        }.map(\.puzzleId)).count
    }

    /// Puzzles left today; nil means unlimited (Pro).
    static func remaining(_ progress: [PuzzleProgress], dailyId: String?, isPro: Bool, now: Date = .now) -> Int? {
        isPro ? nil : max(0, ProFeature.freePuzzlesPerDay - usedToday(progress, dailyId: dailyId, now: now))
    }
}

/// Profile: up to `shown` habits; free users see the top `free` one, the rest as a locked
/// teaser (spec: "weaknesses show the top one free and the rest Pro").
enum WeaknessAllowance {
    static let shown = 3
    static let free = 1

    static func split<T>(_ all: [T], isPro: Bool) -> (open: [T], locked: [T]) {
        let top = Array(all.prefix(shown))
        let open = isPro ? top.count : min(free, top.count)
        return (Array(top.prefix(open)), Array(top.dropFirst(open)))
    }
}

/// Learn allowance: the first `ProFeature.freeLessonsPerTrack` lessons of each track are free.
enum LessonAllowance {
    static func isLocked(index: Int, isPro: Bool) -> Bool {
        !isPro && index >= ProFeature.freeLessonsPerTrack
    }

    static func isLocked(_ lesson: Lesson, isPro: Bool) -> Bool {
        let track = LessonLibrary.lessons(in: lesson.track)
        guard let i = track.firstIndex(where: { $0.id == lesson.id }) else { return false }
        return isLocked(index: i, isPro: isPro)
    }
}
