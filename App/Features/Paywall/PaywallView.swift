import SwiftUI

/// The in-app paywall sheet (a Pro feature, Settings → Get Coach Pro): the same paywall
/// with a close button.
struct PaywallView: View {
    let feature: ProFeature?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PaywallScreen(moment: .feature, onClose: { dismiss() }, onUnlocked: { dismiss() })
            .presentationBackground(DS.Color.background)
    }
}

/// The launch gate under `HARD_PAYWALL`: an onboarded user without the `pro` entitlement
/// (expired, refunded, a reinstall that never subscribed) sees the same paywall, no close.
/// Pro arriving (purchase, restore, renewal) swaps it for the tabs (RootTabView's route).
struct PaywallGate: View {
    var body: some View {
        PaywallScreen(moment: .returning, onClose: nil, onUnlocked: {})
    }
}

/// One paywall for onboarding's last step, the launch gate and the in-app sheet
/// (refs: Duolingo Super's trial paywall, Savee's "Your plan expired"; decisions.md
/// "Hard paywall"). The coach large on the edge of a board, a two-line headline with the
/// offer in accent, one quiet line, the button, a text switch to the other plan, and
/// Restore · Terms · Privacy. At most 25 words besides that row. No close button unless
/// `onClose` is set.
struct PaywallScreen: View {
    let moment: PaywallCopy.Moment
    /// Shows a close button (the in-app sheet). Nil = blocking (onboarding, launch gate).
    var onClose: (() -> Void)?
    /// After a purchase or restore that unlocked Pro (once).
    let onUnlocked: () -> Void

    @Environment(Entitlements.self) private var entitlements
    @State private var selectedID: String?
    @State private var busy = false
    @State private var note: String?
    @State private var unlocked = false
    @State private var appeared = false

    private var selected: Entitlements.Plan? {
        entitlements.plans.first { $0.id == selectedID }
            ?? entitlements.plans.first { $0.period == .yearly }
            ?? entitlements.plans.first
    }

    /// The plan the text switch offers instead.
    private var other: Entitlements.Plan? {
        entitlements.plans.first { $0.id != selected?.id }
    }

    private enum Phase { case pro, loading, failed, cantPay, plan(Entitlements.Plan) }

    private var state: Phase {
        if entitlements.isPro { return .pro }
        if let selected { return entitlements.canMakePayments ? .plan(selected) : .cantPay }
        if entitlements.plansFailed && !entitlements.loadingPlans { return .failed }
        return .loading
    }

    private var copy: PaywallCopy? {
        guard case .plan(let plan) = state else { return nil }
        return PaywallCopy(moment: moment, plan: plan)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let onClose {
                    BarButton(systemImage: "xmark", label: "Close", action: onClose)
                }
                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, DS.Spacing.s)

            Spacer(minLength: 0)
            hero
            headline
                .padding(.top, DS.Spacing.l)
                .padding(.horizontal, DS.Spacing.l)
            Spacer(minLength: DS.Spacing.l)
            actions
                .padding(.horizontal, DS.Spacing.m)
        }
        .background(DS.Color.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(onClose == nil)
        .task {
            if entitlements.plans.isEmpty && !entitlements.loadingPlans { await entitlements.loadPlans() }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.3).delay(0.1)) { appeared = true }
        }
        .onChange(of: entitlements.isPro) { _, pro in
            if pro { unlock() }
        }
    }

    /// The coach, as large as he appears anywhere, standing on the near edge of a board.
    private var hero: some View {
        VStack(spacing: 0) {
            CoachAvatar(pose: .pleased, size: 250, grounded: true)
                .padding(.bottom, -36)
                .zIndex(1)
            BoardEdge(ranks: 3, height: 120)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(spacing: DS.Spacing.sm) {
            VStack(spacing: 2) {
                Text(entitlements.isPro ? "You have Coach Pro." : PaywallCopy.headline(moment))
                    .foregroundStyle(DS.Color.text)
                if let copy {
                    Text(copy.offer)
                        .foregroundStyle(DS.Color.accent)
                        .contentTransition(.opacity)
                }
            }
            .font(.system(.largeTitle, weight: .bold))
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            detail
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.25), value: copy)
    }

    @ViewBuilder
    private var detail: some View {
        switch state {
        case .pro: Text("Everything is unlocked.")
        case .loading: Text("Loading prices…")
        case .failed:
            HStack(spacing: DS.Spacing.s) {
                Text("Couldn't load prices.")
                Button("Try again") { Task { await entitlements.loadPlans() } }
                    .font(DS.Font.body.weight(.semibold))
                    .foregroundStyle(DS.Color.accent)
            }
        case .cantPay: Text("Purchases are turned off on this iPhone.")
        case .plan: Text(note ?? copy?.detail ?? "")
        }
    }

    private var actions: some View {
        VStack(spacing: DS.Spacing.xs) {
            switch state {
            case .pro:
                PrimaryButton(title: "Done") { if let onClose { onClose() } else { unlock() } }
            case .plan(let plan):
                PrimaryButton(title: busy ? "One moment…" : (copy?.cta ?? "Subscribe")) { buy(plan) }
                    .disabled(busy)
            case .loading, .failed, .cantPay:
                PrimaryButton(title: "Subscribe") {}
                    .disabled(true)
                    .opacity(0.4)
            }
            Group {
                if case .plan = state, let other {
                    Button(PaywallCopy.switchLabel(to: other)) {
                        withAnimation(.snappy(duration: 0.25)) { selectedID = other.id }
                    }
                    .foregroundStyle(DS.Color.text)
                    .accessibilityHint("Switches the plan")
                } else {
                    Text(" ").accessibilityHidden(true)
                }
            }
            .font(DS.Font.subheadline.weight(.semibold))
            .frame(minHeight: 40)
            .sensoryFeedback(.selection, trigger: selectedID)

            HStack(spacing: DS.Spacing.l) {
                if !entitlements.isPro {
                    Button("Restore") { restore() }.disabled(busy)
                }
                Link("Terms", destination: AppInfo.termsURL)
                Link("Privacy", destination: AppInfo.privacyURL)
            }
            .font(DS.Font.footnote.weight(.semibold))
            .foregroundStyle(DS.Color.textSecondary)
            .frame(minHeight: 30)
            if let note, !isPlan {
                Text(note)
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var isPlan: Bool {
        if case .plan = state { return true }
        return false
    }

    // MARK: Actions

    private func unlock() {
        guard !unlocked else { return }
        unlocked = true
        onUnlocked()
    }

    private func buy(_ plan: Entitlements.Plan) {
        guard !busy else { return }
        busy = true
        note = nil
        Task {
            let result = await entitlements.purchase(plan)
            busy = false
            switch result {
            case .purchased:
                if plan.trialDays != nil { Task { await TrialReminder.schedule(plan: plan) } }
                unlock()
            case .cancelled: break
            case .pending: note = "Waiting for approval. Pro unlocks once it's approved."
            case .failed(let message): note = message
            }
        }
    }

    private func restore() {
        busy = true
        note = nil
        Task {
            do {
                if try await entitlements.restore() { unlock() } else { note = "No Coach Pro purchase on this Apple Account." }
            } catch {
                note = "Couldn't reach the App Store. Try again in a moment."
            }
            busy = false
        }
    }
}
