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

    // MARK: Trial timeline

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private static let locale = Locale(identifier: "en_US")
    /// Tuesday, Nov 24 2026, noon UTC.
    private static let today = Date(timeIntervalSince1970: 1_795_521_600)

    private static let yearly = Entitlements.Plan(id: Entitlements.yearlyID, period: .yearly, price: "$29.99",
                                                  perMonth: "$2.50", freeTrial: "7 days", trialDays: 7)
    private static let monthly = Entitlements.Plan(id: Entitlements.monthlyID, period: .monthly, price: "$4.99",
                                                   perMonth: nil, freeTrial: nil)

    @Test func trialTimelineIsHonest() {
        let t = TrialTimeline(plan: Self.yearly, todayDetail: "Day 1 of your plan", now: Self.today,
                              calendar: Self.calendar, locale: Self.locale)
        #expect(t.steps.map(\.kind) == [.today, .reminder, .billing])
        #expect(t.steps.map(\.marker) == ["Today", "Day 5", "Day 7"])
        #expect(t.steps[1].date == "Sun, Nov 29")
        #expect(t.steps[2].date == "Tue, Dec 1")
        #expect(t.steps[2].title == "$29.99 a year begins")
        #expect(t.steps[2].detail == "Cancel before then and you pay nothing.")
        #expect(t.cta == "Start my free week")
        #expect(t.billing == "7 days free, then $29.99 a year. Cancel anytime in Settings.")
        #expect(t.heading.contains("Coach Pro"))
    }

    @Test func noTrialMeansNoTrialPromise() {
        let t = TrialTimeline(plan: Self.monthly, todayDetail: "x", now: Self.today, calendar: Self.calendar, locale: Self.locale)
        #expect(t.steps.map(\.kind) == [.today, .renews])
        #expect(t.cta == "Subscribe")
        #expect(t.billing.hasPrefix("$4.99 a month"))
        #expect(!t.billing.contains("free"))
        // A yearly plan whose trial this account already used: no trial either.
        let used = Entitlements.Plan(id: Entitlements.yearlyID, period: .yearly, price: "$29.99", perMonth: "$2.50", freeTrial: nil)
        #expect(TrialTimeline(plan: used, todayDetail: "x", now: Self.today).cta == "Subscribe")
    }

    /// The monthly plan's 3-day trial, read from the store like the yearly's 7 days.
    @Test func threeDayTrialOnMonthly() {
        let plan = Entitlements.Plan(id: Entitlements.monthlyID, period: .monthly, price: "$4.99", perMonth: nil,
                                     freeTrial: "3 days", trialDays: 3)
        let t = TrialTimeline(plan: plan, todayDetail: "x", now: Self.today, calendar: Self.calendar, locale: Self.locale)
        #expect(t.steps.map(\.marker) == ["Today", "Day 2", "Day 3"])
        #expect(t.steps[1].date == "Thu, Nov 26")
        #expect(t.steps[2].date == "Fri, Nov 27")
        #expect(t.steps[2].title == "$4.99 a month begins")
        #expect(t.cta == "Try 3 days free")
        #expect(t.billing == "3 days free, then $4.99 a month. Cancel anytime in Settings.")
    }

    @Test func reminderLeads() {
        #expect(TrialTimeline.reminderLead(trialDays: 7) == 2)
        #expect(TrialTimeline.reminderLead(trialDays: 14) == 2)
        #expect(TrialTimeline.reminderLead(trialDays: 3) == 1)
        #expect(TrialTimeline.reminderLead(trialDays: 1) == nil)
    }

    @Test func oneDayTrialSkipsTheReminder() {
        let plan = Entitlements.Plan(id: "p", period: .monthly, price: "$4.99", perMonth: nil, freeTrial: "1 day", trialDays: 1)
        let t = TrialTimeline(plan: plan, todayDetail: "x", now: Self.today, calendar: Self.calendar, locale: Self.locale)
        #expect(!t.steps.contains { $0.kind == .reminder })
        #expect(TrialReminder.fireDate(trialDays: 1, from: Self.today) == nil)
    }

    @Test func reminderFiresTwoDaysBeforeTheTrialEnds() throws {
        let fire = try #require(TrialReminder.fireDate(trialDays: 7, from: Self.today, calendar: Self.calendar))
        #expect(Self.calendar.dateComponents([.day], from: Self.today, to: fire).day == 5)
    }

    // MARK: The coach's line

    private func story(_ moment: PaywallStory.Moment, fromGames: Bool = true) -> PaywallStory {
        PaywallStory(moment: moment, rating: 960, goal: 1500,
                     goalDate: Self.calendar.date(from: DateComponents(year: 2027, month: 5, day: 24)),
                     focus: .missedCapture, fromGames: fromGames,
                     dayOne: ["5 of your own mistakes", "Queen checkmate", "Play Apex"])
    }

    @Test func onboardingLineUsesTheirResult() {
        let line = story(.onboarding).coachLine(isPro: false, calendar: Self.calendar, locale: Self.locale)
        #expect(line.contains("**1500 by May**"))
        #expect(line.contains("Your games keep giving away **free material**"))
        let newPlayer = story(.onboarding, fromGames: false).coachLine(isPro: false, calendar: Self.calendar, locale: Self.locale)
        #expect(newPlayer.contains("We start with **free material**"))
        #expect(story(.onboarding).todayDetail == "Day 1: 5 of your own mistakes · Queen checkmate · Play Apex")
    }

    @Test func gateAndFeatureLines() {
        #expect(story(.returning).coachLine(isPro: false, calendar: Self.calendar, locale: Self.locale)
            .hasPrefix("Welcome back. Your plan for **1500 by May**"))
        #expect(story(.feature(.fullReview)).coachLine(isPro: false) == ProFeature.fullReview.pitch)
        #expect(!story(.feature(nil)).todayDetail.hasPrefix("Day 1"))
        #expect(story(.onboarding).coachLine(isPro: true).contains("You have **Coach Pro**"))
        let empty = PaywallStory(moment: .returning)
        #expect(empty.coachLine(isPro: false) == "Welcome back. Your plan is waiting.")
    }

}

/// The scheme's ChessCoach.storekit through StoreKitTest (one session at a time): real
/// products, the 7-day intro offer, a purchase unlocking Pro.
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
            #expect(yearly.trialDays == 7)
            #expect(entitlements.plans.last?.price == "$4.99")
            #expect(entitlements.plans.last?.trialDays == 3)
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
