import SwiftUI
import UserNotifications
import ChessCore

/// The hard paywall (build setting `HARD_PAYWALL`, Config/App.xcconfig → Info.plist
/// `HardPaywall`). On: onboarding ends on the paywall and a launch without the `pro`
/// entitlement shows the same paywall before the tabs. Off: the free tier with `ProGate`.
enum HardPaywall {
    /// Read once, at first use (launch).
    static let isOn: Bool = {
        #if DEBUG
        // `-hardPaywall YES|NO` overrides the build setting (screenshots of either mode).
        if UserDefaults.standard.object(forKey: "hardPaywall") != nil {
            return UserDefaults.standard.bool(forKey: "hardPaywall")
        }
        #endif
        return parse(Bundle.main.object(forInfoDictionaryKey: "HardPaywall"))
    }()

    /// "1" / "YES" / true → on, "0" / "NO" / false → off. Missing or unexpanded
    /// (`$(HARD_PAYWALL)`) → on, the build setting's default.
    static func parse(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String:
            switch s.trimmingCharacters(in: .whitespaces).lowercased() {
            case "0", "no", "false": return false
            default: return true
            }
        default: return true
        }
    }
}

extension EnvironmentValues {
    /// Whether the hard paywall applies; tests inject it, the app uses the build setting.
    @Entry var hardPaywall: Bool = HardPaywall.isOn
}

/// What the root shows at launch and whenever onboarding or Pro status changes.
enum LaunchRoute: Equatable {
    /// First run: the onboarding flow (it ends on its own paywall step under the hard paywall).
    case onboarding
    /// Onboarded, hard paywall, Pro status not known yet: a blank frame, never a flash of the gate.
    case checking
    /// Onboarded, hard paywall, no `pro` entitlement: the paywall as a blocking gate.
    case paywall
    case tabs

    static func resolve(onboarded: Bool, onboardingInProgress: Bool, hardPaywall: Bool,
                        status: EntitlementStatus) -> LaunchRoute {
        if onboardingInProgress || !onboarded { return .onboarding }
        guard hardPaywall else { return .tabs }
        switch status {
        case .pro: return .tabs
        case .unknown: return .checking
        case .free: return .paywall
        }
    }

    /// The onboarding flow's last step: the paywall, unless Pro is already active (restored
    /// earlier, forced) or this is Settings' re-import.
    static func onboardingEndsOnPaywall(hardPaywall: Bool, isPro: Bool, reimport: Bool) -> Bool {
        hardPaywall && !isPro && !reimport
    }
}

/// What the coach says on the paywall, from the user's own onboarding result: tier, goal,
/// the habit their games showed, and the plan's first day.
struct PaywallStory: Equatable {
    enum Moment: Equatable {
        /// The last onboarding step.
        case onboarding
        /// The launch gate (expired, refunded, a reinstall that never subscribed).
        case returning
        /// Opened from a Pro feature in the app (HARD_PAYWALL=0, or Settings).
        case feature(ProFeature?)
    }

    var moment: Moment
    var rating: Int?
    var goal: Int?
    var goalDate: Date?
    /// The habit that costs the most points.
    var focus: Motif?
    /// True when `focus` came from the user's imported games (not a new player's answers).
    var fromGames = false
    /// Titles of the plan's day-1 steps: "5 of your own mistakes", "Queen checkmate", "Play Apex".
    var dayOne: [String] = []

    /// "1500 by May".
    func goalText(calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let goal else { return nil }
        guard let goalDate else { return "\(goal)" }
        var style = Date.FormatStyle(locale: locale, calendar: calendar).month(.wide)
        style.timeZone = calendar.timeZone
        return "\(goal) by \(goalDate.formatted(style))"
    }

    /// The coach's line in the bubble (Markdown bold, like the rest of onboarding).
    func coachLine(isPro: Bool, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if isPro { return "You have **Coach Pro**. Everything is unlocked on this Apple Account." }
        let goal = goalText(calendar: calendar, locale: locale)
        let habit = focus?.shortName.lowercased()
        switch moment {
        case .onboarding:
            let opener = goal.map { "**\($0)**." } ?? "Your week is ready."
            if let habit {
                let source = fromGames ? "Your games keep giving away **\(habit)**" : "We start with **\(habit)**"
                return "\(opener) \(source), so that's where day 1 starts."
            }
            return "\(opener) Let's unlock your plan."
        case .returning:
            if let goal { return "Welcome back. Your plan for **\(goal)** is waiting." }
            return "Welcome back. Your plan is waiting."
        case .feature(let feature):
            return feature?.pitch ?? "With Pro I review every move of every game, and your whole week opens up."
        }
    }

    /// The "Today" row's detail: the plan's day 1 when there is one, else what Pro opens.
    var todayDetail: String {
        switch moment {
        case .feature: break
        case .onboarding where !dayOne.isEmpty: return "Day 1: " + dayOne.joined(separator: " · ")
        case .returning where !dayOne.isEmpty: return "Your plan: " + dayOne.joined(separator: " · ")
        default: break
        }
        return "Full game reviews, every explanation, all lessons, unlimited puzzles."
    }
}

@MainActor
extension PaywallStory {
    /// From the onboarding that just finished.
    init(onboarding model: OnboardingModel, now: Date = .now) {
        // The plan's own focus: built from every game read by the goal step, so it can name a
        // habit the reveal (fewer games) hadn't seen yet.
        self.init(moment: .onboarding,
                  rating: model.rating,
                  goal: model.target,
                  goalDate: Calendar.current.date(byAdding: .month, value: model.months, to: now),
                  focus: model.plan?.focus.first ?? (model.platform == nil ? nil : model.report?.top.first),
                  fromGames: model.platform != nil && model.planFromGames,
                  dayOne: model.plan.map { Self.dayOneTitles($0, on: now) } ?? [])
    }

    /// From what onboarding saved (the gate, the in-app paywall).
    init(moment: Moment, profile: UserProfile?, plan: TrainingPlan?, now: Date = .now) {
        self.init(moment: moment,
                  rating: profile?.currentRating,
                  goal: profile?.goalRating,
                  goalDate: profile?.goalDate,
                  focus: plan?.focus.first,
                  fromGames: profile?.importPlatform != nil,
                  dayOne: plan.map { Self.dayOneTitles($0, on: now) } ?? [])
    }

    /// Today's steps of the plan (day 1 on the day it was made), as the week shows them.
    static func dayOneTitles(_ plan: TrainingPlan, on now: Date) -> [String] {
        let index = plan.dayIndex(on: now) ?? 0
        guard let day = plan.days.first(where: { $0.index == index }) ?? plan.days.first else { return [] }
        return WeekView.steps(day, in: plan).map(\.title)
    }
}

/// The honest trial timeline under the coach: what happens today, when we remind, when the
/// store bills. Built from the selected plan's real price and trial.
struct TrialTimeline: Equatable {
    struct Step: Equatable, Identifiable {
        enum Kind: Equatable { case today, reminder, billing, renews }
        let kind: Kind
        /// "Today", "Day 5", "Day 7", "Every year".
        let marker: String
        /// "Sat, Nov 29"; nil for today.
        let date: String?
        let title: String
        let detail: String
        var id: String { marker }
    }

    let heading: String
    let steps: [Step]
    /// The CTA's title.
    let cta: String
    /// The sentence under the CTA: price and period, legible.
    let billing: String

    /// Days before the trial ends that the reminder fires: two in a week-long trial (day 5 of
    /// 7), one in a short one (day 2 of 3). Nil when the trial is too short for a reminder.
    static func reminderLead(trialDays days: Int) -> Int? {
        let lead = days >= 7 ? 2 : 1
        return days > lead ? lead : nil
    }

    init(plan: Entitlements.Plan, todayDetail: String, now: Date = .now, calendar: Calendar = .current,
         locale: Locale = .current) {
        var style = Date.FormatStyle(locale: locale, calendar: calendar).weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        let date = { (days: Int) in (calendar.date(byAdding: .day, value: days, to: now) ?? now).formatted(style) }
        let unit = plan.period == .yearly ? "year" : "month"
        let cancel = "Cancel anytime in Settings."

        if let trial = plan.freeTrial, let days = plan.trialDays, days > 0 {
            let week = days == 7
            heading = week ? "Coach Pro, free for a week" : "Coach Pro, free for \(trial)"
            var steps = [Step(kind: .today, marker: "Today", date: nil, title: "Everything unlocked", detail: todayDetail)]
            if let lead = Self.reminderLead(trialDays: days) {
                let day = days - lead
                steps.append(Step(kind: .reminder, marker: "Day \(day)", date: date(day), title: "We remind you",
                                  detail: "A notification before the trial ends."))
            }
            steps.append(Step(kind: .billing, marker: "Day \(days)", date: date(days),
                              title: "\(plan.price) a \(unit) begins",
                              detail: "Cancel before then and you pay nothing."))
            self.steps = steps
            cta = week ? "Start my free week" : "Try \(trial) free"
            billing = "\(trial) free, then \(plan.price) a \(unit). \(cancel)"
        } else {
            heading = "Coach Pro"
            steps = [
                Step(kind: .today, marker: "Today", date: nil, title: "Everything unlocked · \(plan.price)", detail: todayDetail),
                Step(kind: .renews, marker: plan.period == .yearly ? "Yearly" : "Monthly", date: nil,
                     title: "Renews every \(unit)", detail: "\(plan.price) a \(unit) until you cancel. \(cancel)"),
            ]
            cta = "Subscribe"
            billing = "\(plan.price) a \(unit), renews automatically. \(cancel)"
        }
    }
}

/// The "we remind you" promise of the timeline: a local notification two days before the
/// trial ends, scheduled right after the trial starts (asks for permission then).
enum TrialReminder {
    static let id = "trial-reminder"

    static func fireDate(trialDays: Int, from start: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let lead = TrialTimeline.reminderLead(trialDays: trialDays) else { return nil }
        return calendar.date(byAdding: .day, value: trialDays - lead, to: start)
    }

    static func schedule(plan: Entitlements.Plan, from start: Date = .now) async {
        guard let days = plan.trialDays, let lead = TrialTimeline.reminderLead(trialDays: days),
              let fire = fireDate(trialDays: days, from: start),
              let ends = Calendar.current.date(byAdding: .day, value: days, to: start) else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = lead == 1 ? "Your free trial ends tomorrow" : "Your free trial ends in \(lead) days"
        let unit = plan.period == .yearly ? "year" : "month"
        content.body = "Coach Pro renews at \(plan.price) a \(unit) on \(ends.formatted(.dateTime.weekday(.wide).month(.wide).day())) "
            + "unless you cancel. To cancel: Settings → your name → Subscriptions."
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        try? await center.add(request)
    }
}
