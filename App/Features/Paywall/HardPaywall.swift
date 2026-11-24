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
    /// earlier, forced) or this is Settings' re-import. Shown in both modes: every new user
    /// sees the offer once.
    static func onboardingEndsOnPaywall(hardPaywall: Bool, isPro: Bool, reimport: Bool) -> Bool {
        !isPro && !reimport
    }

    /// Whether the onboarding paywall has an X. Without the hard paywall the X leads to the
    /// free tier; with it there is nowhere to go but the launch gate, so no X.
    static func onboardingPaywallClosable(hardPaywall: Bool) -> Bool {
        !hardPaywall
    }
}

/// The paywall's words. Few on purpose (owner: at most 25 visible words besides
/// Restore · Terms · Privacy): a headline in two lines, the second in accent, one quiet line,
/// the button, and a text switch to the other plan. Every price and the trial come from the
/// store's product (price, intro offer length, this account's eligibility).
struct PaywallCopy: Equatable {
    enum Moment: Equatable {
        /// The last onboarding step.
        case onboarding
        /// The launch gate (expired, refunded, a reinstall that never subscribed).
        case returning
        /// Opened from a Pro feature in the app (HARD_PAYWALL=0, or Settings).
        case feature
    }

    /// "Your plan is ready."
    let headline: String
    /// "Try 3 days free." / "$4.99 a month." (accent)
    let offer: String
    /// "Then $29.99 a year. We'll remind you before it ends."
    let detail: String
    /// "Try for $0.00" / "Subscribe"
    let cta: String

    static func headline(_ moment: Moment) -> String {
        switch moment {
        case .onboarding: "Your plan is ready."
        case .returning: "Your plan is waiting."
        case .feature: "Get the whole coach."
        }
    }

    init(moment: Moment, plan: Entitlements.Plan) {
        headline = Self.headline(moment)
        let unit = plan.period == .yearly ? "year" : "month"
        if let days = plan.trialDays, days > 0, plan.freeTrial != nil {
            offer = "Try \(days) day\(days == 1 ? "" : "s") free."
            // Two lines, a sentence each (no orphaned last word under the headline).
            let reminder = TrialReminder.lead(trialDays: days) == nil ? "" : "\nWe'll remind you before it ends."
            detail = "Then \(plan.price) a \(unit).\(reminder)"
            cta = plan.free.map { "Try for \($0)" } ?? "Start free trial"
        } else {
            offer = "\(plan.price) a \(unit)."
            detail = plan.period == .yearly ? "Billed yearly.\nCancel anytime." : "Billed monthly.\nCancel anytime."
            cta = "Subscribe"
        }
    }

    /// The small text button under the CTA that switches to `plan`: "or $4.99 a month",
    /// "or try 3 days free".
    static func switchLabel(to plan: Entitlements.Plan) -> String {
        if let days = plan.trialDays, days > 0, plan.freeTrial != nil {
            return "or try \(days) day\(days == 1 ? "" : "s") free"
        }
        return "or \(plan.price) a \(plan.period == .yearly ? "year" : "month")"
    }

    /// Words a person reads, for the owner's 25-word budget.
    var words: Int {
        [headline, offer, detail, cta].joined(separator: " ").split(whereSeparator: \.isWhitespace).count
    }
}

/// "We'll remind you before it ends": a local notification before the trial ends, scheduled
/// right after the trial starts (asks for permission then).
enum TrialReminder {
    static let id = "trial-reminder"

    /// Days before the trial ends: one in a short trial (day 2 of 3), two in a week (day 5 of
    /// 7). Nil when the trial is too short for a reminder.
    static func lead(trialDays days: Int) -> Int? {
        let lead = days >= 7 ? 2 : 1
        return days > lead ? lead : nil
    }

    static func fireDate(trialDays: Int, from start: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let lead = lead(trialDays: trialDays) else { return nil }
        return calendar.date(byAdding: .day, value: trialDays - lead, to: start)
    }

    static func schedule(plan: Entitlements.Plan, from start: Date = .now) async {
        guard let days = plan.trialDays, let lead = lead(trialDays: days),
              let fire = fireDate(trialDays: days, from: start),
              let ends = Calendar.current.date(byAdding: .day, value: days, to: start) else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = lead == 1 ? "Your free trial ends tomorrow" : "Your free trial ends in \(lead) days"
        let unit = plan.period == .yearly ? "year" : "month"
        content.body = "Coach Pro renews at \(plan.price) a \(unit) on \(ends.formatted(.dateTime.weekday(.wide).month(.wide).day())) "
            + "unless you cancel. To cancel: Settings, your name, Subscriptions."
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        try? await center.add(request)
    }
}
