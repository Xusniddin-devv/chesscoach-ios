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
@MainActor @Observable
final class Entitlements {
    static let entitlementID = "pro"
    static let yearlyID = "uz.xq.chessc.pro.yearly"
    static let monthlyID = "uz.xq.chessc.pro.monthly"

    private(set) var isPro = false
    private(set) var plans: [Plan] = []
    private(set) var loadingPlans = false
    private(set) var plansFailed = false

    enum Backend: Equatable { case revenueCat, storeKit }
    let backend: Backend

    private static let log = Logger(subsystem: "uz.xq.chessc", category: "purchases")
    @ObservationIgnored private var packages: [String: Package] = [:]
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var started = false
    /// DEBUG: `-forcePro YES|NO` launch argument pins `isPro` (screenshots, UI tests).
    @ObservationIgnored private let forced: Bool?

    init(apiKey: String? = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String) {
        let key = (apiKey ?? "").trimmingCharacters(in: .whitespaces)
        // An unexpanded "$(REVENUECAT_API_KEY)" also means "no key".
        if key.isEmpty || key.hasPrefix("$(") {
            backend = .storeKit
        } else {
            backend = .revenueCat
            Purchases.logLevel = .warn
            Purchases.configure(withAPIKey: key)
        }
        #if DEBUG
        forced = UserDefaults.standard.object(forKey: "forcePro") as? Bool
        #else
        forced = nil
        #endif
        if let forced { isPro = forced }
    }

    /// Call once at launch: current status, plans, and a listener for renewals / refunds.
    func start() async {
        guard !started else { return }
        started = true
        switch backend {
        case .revenueCat:
            updates = Task { [weak self] in
                for await info in Purchases.shared.customerInfoStream {
                    self?.apply(info)
                }
            }
        case .storeKit:
            updates = Task { [weak self] in
                for await update in Transaction.updates {
                    if case .verified(let transaction) = update { await transaction.finish() }
                    await self?.refreshStoreKit()
                }
            }
            await refreshStoreKit()
        }
        await loadPlans()
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
                        found.append(Plan(id: package.storeProduct.productIdentifier, period: period,
                                          price: package.storeProduct.localizedPriceString,
                                          perMonth: period == .yearly ? package.storeProduct.localizedPricePerMonth : nil,
                                          freeTrial: nil))
                    }
                }
                plans = found
            case .storeKit:
                let products = try await Product.products(for: [Self.yearlyID, Self.monthlyID])
                var found: [Plan] = []
                for product in products {
                    found.append(await Self.plan(from: product, period: product.id == Self.yearlyID ? .yearly : .monthly))
                }
                plans = found.sorted { a, _ in a.period == .yearly }
            }
            plansFailed = plans.isEmpty
        } catch {
            Self.log.error("Loading plans failed: \(error.localizedDescription, privacy: .public)")
            plansFailed = true
        }
    }

    private static func plan(from product: Product, period: Plan.Period) async -> Plan {
        var trial: String?
        if let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial,
           await product.subscription?.isEligibleForIntroOffer == true {
            trial = describe(offer.period)
        }
        let perMonth = period == .yearly
            ? (product.price / 12).formatted(product.priceFormatStyle)
            : nil
        return Plan(id: product.id, period: period, price: product.displayPrice, perMonth: perMonth, freeTrial: trial)
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
