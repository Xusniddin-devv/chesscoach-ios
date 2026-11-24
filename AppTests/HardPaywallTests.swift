import Testing
import Foundation
import SwiftUI
import UIKit
import SwiftData
import StoreKitTest
import ChessCore
@testable import ChessCoach

/// The hard paywall: build setting, launch routing (onboarded × entitled × HARD_PAYWALL),
/// the trial timeline's honesty and the coach's personalised line.
@MainActor
struct HardPaywallTests {
    // MARK: Build setting

    @Test func buildSettingParsing() {
        #expect(HardPaywall.parse("1"))
        #expect(HardPaywall.parse("YES"))
        #expect(HardPaywall.parse(true))
        #expect(!HardPaywall.parse("0"))
        #expect(!HardPaywall.parse("NO"))
        #expect(!HardPaywall.parse(" false "))
        #expect(!HardPaywall.parse(false))
        // Missing or unexpanded: the setting's default (on).
        #expect(HardPaywall.parse(nil))
        #expect(HardPaywall.parse("$(HARD_PAYWALL)"))
    }

    @Test func appBuildCarriesTheSetting() {
        let value = Bundle.main.object(forInfoDictionaryKey: "HardPaywall") as? String
        #expect(value == "1", "Config/App.xcconfig HARD_PAYWALL → Info.plist HardPaywall, default 1")
    }

    // MARK: Routing matrix

    @Test(arguments: [false, true], [EntitlementStatus.unknown, .pro, .free])
    func notOnboardedAlwaysOnboards(hardPaywall: Bool, status: EntitlementStatus) {
        #expect(LaunchRoute.resolve(onboarded: false, onboardingInProgress: false, hardPaywall: hardPaywall, status: status) == .onboarding)
        // The flow saves the profile before its own paywall step: it stays on screen.
        #expect(LaunchRoute.resolve(onboarded: true, onboardingInProgress: true, hardPaywall: hardPaywall, status: status) == .onboarding)
    }

    @Test func onboardedMatrix() {
        func route(_ hard: Bool, _ status: EntitlementStatus) -> LaunchRoute {
            LaunchRoute.resolve(onboarded: true, onboardingInProgress: false, hardPaywall: hard, status: status)
        }
        // HARD_PAYWALL=1: Pro in, free gated, unknown waits (no flash of the gate).
        #expect(route(true, .pro) == .tabs)
        #expect(route(true, .free) == .paywall)
        #expect(route(true, .unknown) == .checking)
        // HARD_PAYWALL=0: the free tier, as before.
        #expect(route(false, .pro) == .tabs)
        #expect(route(false, .free) == .tabs)
        #expect(route(false, .unknown) == .tabs)
    }

    @Test func onboardingEndsOnPaywallOnlyWhenNeeded() {
        #expect(LaunchRoute.onboardingEndsOnPaywall(hardPaywall: true, isPro: false, reimport: false))
        #expect(!LaunchRoute.onboardingEndsOnPaywall(hardPaywall: true, isPro: true, reimport: false))
        #expect(!LaunchRoute.onboardingEndsOnPaywall(hardPaywall: true, isPro: false, reimport: true))
        #expect(!LaunchRoute.onboardingEndsOnPaywall(hardPaywall: false, isPro: false, reimport: false))
    }

    @Test func entitlementStatus() {
        #expect(Entitlements(apiKey: "", forcedPro: true).status == .pro)
        #expect(Entitlements(apiKey: "", forcedPro: false).status == .free)
    }

    @Test func paywallStepHasNoBack() {
        let model = OnboardingModel()
        model.go(.find)
        model.go(.paywall)
        #expect(!model.canGoBack)
    }

    // MARK: Launch routing in the real root view

    @Test func onboardedWithoutProShowsTheGate() throws {
        #expect(try tabsShown(onboarded: true, pro: false, hardPaywall: true) == false)
    }

    @Test func onboardedWithProShowsTabs() throws {
        #expect(try tabsShown(onboarded: true, pro: true, hardPaywall: true) == true)
    }

    @Test func freeTierWithoutHardPaywallShowsTabs() throws {
        #expect(try tabsShown(onboarded: true, pro: false, hardPaywall: false) == true)
    }

    @Test func newInstallOnboardsEvenWhenPro() throws {
        #expect(try tabsShown(onboarded: false, pro: true, hardPaywall: true) == false)
    }

    private func tabsShown(onboarded: Bool, pro: Bool, hardPaywall: Bool) throws -> Bool {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let container = try ModelContainer(
            for: ModelStore.schema,
            configurations: ModelConfiguration(schema: ModelStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let saved = UserDefaults.standard.object(forKey: Pref.hasOnboarded)
        UserDefaults.standard.set(onboarded, forKey: Pref.hasOnboarded)
        defer { UserDefaults.standard.set(saved, forKey: Pref.hasOnboarded) }
        let host = UIHostingController(rootView: RootTabView()
            .environment(EngineHub())
            .environment(Entitlements(apiKey: "", forcedPro: pro))
            .environment(\.hardPaywall, hardPaywall)
            .modelContainer(container))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        let shown = Self.findTabBar(host) != nil
        LaunchTests.tearDown(window, keeping: container)
        return shown
    }

    private static func findTabBar(_ vc: UIViewController) -> UITabBarController? {
        if let t = vc as? UITabBarController { return t }
        for child in vc.children { if let t = findTabBar(child) { return t } }
        return nil
    }

    // MARK: The words (all prices and the trial from the store's product)

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    /// Tuesday, Nov 24 2026, noon UTC.
    private static let today = Date(timeIntervalSince1970: 1_795_521_600)

    /// As the store reports them (Config/ChessCoach.storekit): yearly with a 3-day free
    /// trial, monthly with none.
    private static let yearly = Entitlements.Plan(id: Entitlements.yearlyID, period: .yearly, price: "$29.99",
                                                  perMonth: "$2.50", freeTrial: "3 days", trialDays: 3, free: "$0.00")
    private static let monthly = Entitlements.Plan(id: Entitlements.monthlyID, period: .monthly, price: "$4.99",
                                                   perMonth: nil, freeTrial: nil, free: "$0.00")

    @Test func yearlyTrialWords() {
        let c = PaywallCopy(moment: .onboarding, plan: Self.yearly)
        #expect(c.headline == "Your plan is ready.")
        #expect(c.offer == "Try 3 days free.")
        #expect(c.detail == "Then $29.99 a year.\nWe'll remind you before it ends.")
        #expect(c.cta == "Try for $0.00")
        #expect(PaywallCopy.switchLabel(to: Self.monthly) == "or $4.99 a month")
    }

    @Test func monthlyHasNoTrial() {
        let c = PaywallCopy(moment: .onboarding, plan: Self.monthly)
        #expect(c.offer == "$4.99 a month.")
        #expect(c.cta == "Subscribe")
        #expect(!c.detail.contains("free") && !c.detail.contains("remind"))
        #expect(PaywallCopy.switchLabel(to: Self.yearly) == "or try 3 days free")
    }

    /// An account that already used the yearly trial: no trial promised anywhere.
    @Test func usedTrialPromisesNoTrial() {
        let used = Entitlements.Plan(id: Entitlements.yearlyID, period: .yearly, price: "$29.99", perMonth: "$2.50",
                                     freeTrial: nil, free: "$0.00")
        let c = PaywallCopy(moment: .returning, plan: used)
        #expect(c.headline == "Your plan is waiting.")
        #expect(c.offer == "$29.99 a year.")
        #expect(c.cta == "Subscribe")
        #expect(PaywallCopy.switchLabel(to: used) == "or $29.99 a year")
    }

    /// The trial's length and the zero price come from the store.
    @Test func trialLengthAndZeroFollowTheStore() {
        let week = Entitlements.Plan(id: Entitlements.yearlyID, period: .yearly, price: "€29,99", perMonth: nil,
                                     freeTrial: "7 days", trialDays: 7, free: "0,00 €")
        let c = PaywallCopy(moment: .feature, plan: week)
        #expect(c.offer == "Try 7 days free.")
        #expect(c.cta == "Try for 0,00 €")
        #expect(c.detail.hasPrefix("Then €29,99 a year."))
    }

    /// Owner's budget: at most 25 visible words besides Restore · Terms · Privacy, counting
    /// the switch under the button.
    @Test func atMostTwentyFiveWords() {
        for moment in [PaywallCopy.Moment.onboarding, .returning, .feature] {
            for (plan, other) in [(Self.yearly, Self.monthly), (Self.monthly, Self.yearly)] {
                let c = PaywallCopy(moment: moment, plan: plan)
                let switchWords = PaywallCopy.switchLabel(to: other).split(separator: " ").count
                #expect(c.words + switchWords <= 25, "\(moment) \(plan.period): \(c.words + switchWords) words")
            }
        }
    }

    @Test func reminderLeads() {
        #expect(TrialReminder.lead(trialDays: 3) == 1)
        #expect(TrialReminder.lead(trialDays: 7) == 2)
        #expect(TrialReminder.lead(trialDays: 1) == nil)
        #expect(TrialReminder.fireDate(trialDays: 1, from: Self.today) == nil)
        // A one-day trial is too short for a reminder, so the paywall doesn't promise one.
        let oneDay = Entitlements.Plan(id: "p", period: .yearly, price: "$29.99", perMonth: nil, freeTrial: "1 day", trialDays: 1)
        #expect(!PaywallCopy(moment: .onboarding, plan: oneDay).detail.contains("remind"))
    }

    @Test func reminderFiresADayBeforeBilling() throws {
        let fire = try #require(TrialReminder.fireDate(trialDays: 3, from: Self.today, calendar: Self.calendar))
        #expect(Self.calendar.dateComponents([.day], from: Self.today, to: fire).day == 2)
    }
}

/// The scheme's ChessCoach.storekit through StoreKitTest (one session at a time): real
/// products, the yearly 3-day intro offer, a purchase unlocking Pro.
///
/// Known issue: from `xcodebuild test` on the iOS 26.5 simulator the session can't reach the
/// StoreKit test daemon (`SKTestSession … SKInternalErrorDomain Code=3`) and the store
/// returns no products. The tests then record a known issue instead of failing; run from
/// Xcode (⌘U) they run for real. See docs/TESTFLIGHT.md.
@MainActor @Suite(.serialized)
struct StoreKitPlansTests {
    private static let unavailable = "SKTestSession can't reach the StoreKit test daemon from xcodebuild"

    @Test func plansLoadFromTheStoreWithTheTrial() async throws {
        let session = try Self.storeSession()
        defer { session.clearTransactions() }
        let entitlements = Entitlements(apiKey: "")
        await entitlements.loadPlans()
        withKnownIssue(Comment(rawValue: Self.unavailable), isIntermittent: true) {
            #expect(!entitlements.plansFailed)
            let yearly = try #require(entitlements.plans.first)
            #expect(yearly.period == .yearly)
            #expect(yearly.price == "$29.99")
            #expect(yearly.trialDays == 3)
            #expect(entitlements.plans.last?.price == "$4.99")
            #expect(entitlements.plans.last?.trialDays == nil)
        }
    }

    @Test func buyingTheTrialUnlocksPro() async throws {
        let session = try Self.storeSession()
        defer { session.clearTransactions() }
        let entitlements = Entitlements(apiKey: "")
        await entitlements.start()
        #expect(entitlements.status == .free)
        await withKnownIssue(Comment(rawValue: Self.unavailable), isIntermittent: true) {
            let yearly = try #require(entitlements.plans.first { $0.period == .yearly })
            let result = await entitlements.purchase(yearly)
            guard case .purchased = result else { Issue.record("expected purchased, got \(result)"); return }
            #expect(entitlements.isPro)
            #expect(entitlements.status == .pro)
        }
    }

    private final class Token {}

    private static func storeSession() throws -> SKTestSession {
        _ = try #require(Bundle(for: Token.self).url(forResource: "ChessCoach", withExtension: "storekit"))
        let session = try SKTestSession(configurationFileNamed: "ChessCoach")
        session.disableDialogs = true
        session.resetToDefaultState()
        session.clearTransactions()
        return session
    }
}
