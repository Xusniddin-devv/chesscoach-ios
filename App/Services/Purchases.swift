import Foundation
import Observation
import OSLog
import StoreKit
import RevenueCat

/// Who has Coach Pro, the two plans and buying / restoring them.
///
/// Two back ends behind one API:
/// - **RevenueCat** when the build setting `REVENUECAT_API_KEY` (→ Info.plist `RevenueCatAPIKey`)
///   is set: offerings' monthly / annual packages, entitlement `pro`.
/// - **StoreKit 2 only** when it is empty: the two product ids below, Pro = an active
///   transaction for either. The scheme's `Config/ChessCoach.storekit` serves them in the
///   Simulator, so the paywall works with no RevenueCat project.
///
/// Gating principle (spec): analysis is always computed and stored; only the UI checks
/// `isPro`. Use `ProGate` / `UpgradeButton` (App/Features/Paywall/ProGate.swift) in views.
/// Under `HARD_PAYWALL` the launch gate reads `status` (App/Features/Paywall/HardPaywall.swift).
@MainActor @Observable
final class Entitlements {
    static let entitlementID = "pro"
    static let yearlyID = "uz.xq.chessc.pro.yearly"
    static let monthlyID = "uz.xq.chessc.pro.monthly"

    private(set) var isPro = false
    private(set) var plans: [Plan] = []
    private(set) var loadingPlans = false
    private(set) var plansFailed = false
    /// True once the first status check has answered (cached or fresh), so a launch gate
    /// never flashes the paywall at a subscriber whose status hasn't loaded yet.
    private(set) var resolved = false
    /// False when this iPhone can't buy (Screen Time / parental controls).
    private(set) var canMakePayments = true

    enum Backend: Equatable { case revenueCat, storeKit }
    let backend: Backend

    private static let log = Logger(subsystem: "uz.xq.chessc", category: "purchases")
    @ObservationIgnored private var packages: [String: Package] = [:]
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var started = false
    /// DEBUG: `-forcePro YES|NO` launch argument pins `isPro` (screenshots, UI tests).
    @ObservationIgnored private let forced: Bool?

    /// - Parameter forcedPro: pins `isPro` (tests); DEBUG builds also read `-forcePro YES|NO`.
    init(apiKey: String? = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
         forcedPro: Bool? = nil) {
        let key = (apiKey ?? "").trimmingCharacters(in: .whitespaces)
        // Only a public Apple SDK key ("appl_…") configures RevenueCat. Empty, an unexpanded
        // "$(REVENUECAT_API_KEY)", a placeholder or a secret key all mean StoreKit 2 only, so an
        // archive without Config/Secrets.xcconfig still sells through StoreKit.
        // DEBUG builds also accept a RevenueCat Test Store key ("test_…"): purchases work in the
        // Simulator without App Store Connect. Release never configures with a test key.
        #if DEBUG
        let usable = key.hasPrefix("appl_") || key.hasPrefix("test_")
        #else
        let usable = key.hasPrefix("appl_")
        #endif
        if !usable {
            backend = .storeKit
        } else {
            backend = .revenueCat
            Purchases.logLevel = .warn
            Purchases.configure(withAPIKey: key)
        }
        #if DEBUG
        // Launch arguments arrive as strings ("YES"): `bool(forKey:)` reads them, `as? Bool` doesn't.
        forced = forcedPro ?? (UserDefaults.standard.object(forKey: "forcePro") == nil ? nil : UserDefaults.standard.bool(forKey: "forcePro"))
        #else
        forced = forcedPro
        #endif
        if let forced {
            isPro = forced
            resolved = true
        }
    }

    /// Call once at launch: current status, plans, and a listener for renewals / refunds.
    func start() async {
        guard !started else { return }
        started = true
        canMakePayments = AppStore.canMakePayments
        switch backend {
        case .revenueCat:
            updates = Task { [weak self] in
                for await info in Purchases.shared.customerInfoStream {
                    self?.apply(info)
                }
            }
            // Cached when offline; a failure still resolves (the gate offers Restore and Retry).
            if let info = try? await Purchases.shared.customerInfo() { apply(info) }
        case .storeKit:
            updates = Task { [weak self] in
                for await update in Transaction.updates {
                    if case .verified(let transaction) = update { await transaction.finish() }
                    await self?.refreshStoreKit()
                }
            }
            await refreshStoreKit()
        }
        resolved = true
        await loadPlans()
    }

    /// Status for the launch gate: unknown until the first check answers.
    var status: EntitlementStatus {
        if isPro { return .pro }
        return resolved ? .free : .unknown
    }

    // MARK: Plans

    struct Plan: Identifiable, Equatable {
        enum Period { case yearly, monthly }
        let id: String
        let period: Period
        /// "$29.99"
        let price: String
        /// "$2.50" for yearly; nil for monthly.
        let perMonth: String?
        /// "7 days" when a free trial applies to this user.
        let freeTrial: String?
        /// The trial's length in days (3), when `freeTrial` is set.
        var trialDays: Int?
        /// Zero in the product's currency ("$0.00"), for "Try for $0.00".
        var free: String?
    }

    func loadPlans() async {
        loadingPlans = true
        plansFailed = false
        defer { loadingPlans = false }
        do {
            switch backend {
            case .revenueCat:
                let offering = try await Purchases.shared.offerings().current
                var found: [Plan] = []
                packages = [:]
                for (package, period) in [(offering?.annual, Plan.Period.yearly), (offering?.monthly, .monthly)] {
                    guard let package else { continue }
                    packages[package.storeProduct.productIdentifier] = package
                    if let sk2 = package.storeProduct.sk2Product {
                        found.append(await Self.plan(from: sk2, period: period))
                    } else {
                        found.append(await Self.plan(from: package.storeProduct, period: period))
                    }
                }
                plans = found
            case .storeKit:
                let products = try await Product.products(for: [Self.yearlyID, Self.monthlyID])
                var found: [Plan] = []
                for product in products {
                    found.append(await Self.plan(from: product, period: product.id == Self.yearlyID ? .yearly : .monthly))
                }
                plans = found.sorted { $0.period == .yearly && $1.period != .yearly }  // yearly first
            }
            #if DEBUG
            // `-demoPlans YES`: StoreKit's local config only serves runs started from Xcode;
            // screenshots launched with simctl get these instead.
            if plans.isEmpty, UserDefaults.standard.bool(forKey: "demoPlans") {
                plans = [Plan(id: Self.yearlyID, period: .yearly, price: "$29.99", perMonth: "$2.50", freeTrial: "3 days", trialDays: 3,
                              free: "$0.00"),
                         Plan(id: Self.monthlyID, period: .monthly, price: "$4.99", perMonth: nil, freeTrial: nil)]
            }
            #endif
            plansFailed = plans.isEmpty
        } catch {
            Self.log.error("Loading plans failed: \(error.localizedDescription, privacy: .public)")
            plansFailed = true
        }
    }

    private static func plan(from product: Product, period: Plan.Period) async -> Plan {
        var trial: String?
        var trialDays: Int?
        if let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial,
           await product.subscription?.isEligibleForIntroOffer == true {
            trial = describe(offer.period)
            trialDays = days(offer.period)
        }
        let perMonth = period == .yearly
            ? (product.price / 12).formatted(product.priceFormatStyle)
            : nil
        return Plan(id: product.id, period: period, price: product.displayPrice, perMonth: perMonth, freeTrial: trial,
                    trialDays: trialDays, free: Decimal(0).formatted(product.priceFormatStyle))
    }

    /// RevenueCat's StoreProduct when no StoreKit 2 product is behind it: its
    /// `introductoryDiscount`, if this customer is still eligible for it.
    private static func plan(from product: StoreProduct, period: Plan.Period) async -> Plan {
        var trial: String?
        var trialDays: Int?
        if let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial {
            let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: product)
            if eligibility == .eligible {
                let days = days(value: intro.subscriptionPeriod.value, unit: intro.subscriptionPeriod.unit)
                trialDays = days
                trial = "\(days) day\(days == 1 ? "" : "s")"
            }
        }
        return Plan(id: product.productIdentifier, period: period, price: product.localizedPriceString,
                    perMonth: period == .yearly ? product.localizedPricePerMonth : nil,
                    freeTrial: trial, trialDays: trialDays, free: product.priceFormatter?.string(from: 0))
    }

    private static func days(value: Int, unit: RevenueCat.SubscriptionPeriod.Unit) -> Int {
        switch unit {
        case .day: value
        case .week: value * 7
        case .month: value * 30
        case .year: value * 365
        @unknown default: value
        }
    }

    /// Whole days in a trial period (a month counts 30, a year 365).
    static func days(_ period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: period.value
        case .week: period.value * 7
        case .month: period.value * 30
        case .year: period.value * 365
        @unknown default: period.value
        }
    }

    /// "7 days", "1 month".
    private static func describe(_ period: Product.SubscriptionPeriod) -> String {
        let (n, unit): (Int, String) = switch period.unit {
        case .day: (period.value, "day")
        case .week: (period.value * 7, "day")
        case .month: (period.value, "month")
        case .year: (period.value, "year")
        @unknown default: (period.value, "day")
        }
        return "\(n) \(unit)\(n == 1 ? "" : "s")"
    }

    // MARK: Buying

    enum PurchaseResult { case purchased, cancelled, pending, failed(String) }

    func purchase(_ plan: Plan) async -> PurchaseResult {
        do {
            switch backend {
            case .revenueCat:
                guard let package = packages[plan.id] else { return .failed("This plan isn't available right now.") }
                let result = try await Purchases.shared.purchase(package: package)
                if result.userCancelled { return .cancelled }
                apply(result.customerInfo)
                return isPro ? .purchased : .pending
            case .storeKit:
                guard let product = try await Product.products(for: [plan.id]).first else {
                    return .failed("This plan isn't available right now.")
                }
                switch try await product.purchase() {
                case .success(let verification):
                    guard case .verified(let transaction) = verification else {
                        return .failed("The App Store couldn't verify this purchase.")
                    }
                    await transaction.finish()
                    await refreshStoreKit()
                    return .purchased
                case .userCancelled: return .cancelled
                case .pending: return .pending
                @unknown default: return .cancelled
                }
            }
        } catch {
            Self.log.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// Restore purchases. Returns whether Pro is active afterwards; throws on a store error.
    @discardableResult
    func restore() async throws -> Bool {
        switch backend {
        case .revenueCat:
            apply(try await Purchases.shared.restorePurchases())
        case .storeKit:
            try await AppStore.sync()
            await refreshStoreKit()
        }
        return isPro
    }

    // MARK: Status

    private func apply(_ info: CustomerInfo) {
        guard forced == nil else { return }
        isPro = info.entitlements[Self.entitlementID]?.isActive == true
        resolved = true
    }

    private func refreshStoreKit() async {
        guard forced == nil else { return }
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, [Self.yearlyID, Self.monthlyID].contains(t.productID),
               t.revocationDate == nil {
                active = true
            }
        }
        isPro = active
    }
}

/// Pro status as the launch gate sees it.
enum EntitlementStatus: Equatable, Sendable { case unknown, pro, free }
