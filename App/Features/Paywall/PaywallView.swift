import SwiftUI
import SwiftData
import ChessCore

/// The in-app paywall sheet (a Pro feature, Settings → Get Coach Pro): the shared paywall
/// with a close button, personalised from what onboarding saved.
struct PaywallView: View {
    let feature: ProFeature?

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserProfile.updated, order: .reverse) private var profiles: [UserProfile]
    @Query(sort: \TrainingPlanRecord.created, order: .reverse) private var plans: [TrainingPlanRecord]

    var body: some View {
        PaywallScreen(story: PaywallStory(moment: .feature(feature), profile: profiles.first, plan: plans.first?.plan),
                      onClose: { dismiss() }, onUnlocked: { dismiss() })
            .presentationBackground(DS.Color.background)
    }
}

/// The launch gate under `HARD_PAYWALL`: an onboarded user without the `pro` entitlement
/// (expired, refunded, a reinstall that never subscribed) sees the same paywall, no close.
/// Pro arriving (purchase, restore, renewal) swaps it for the tabs (RootTabView's route).
struct PaywallGate: View {
    @Query(sort: \UserProfile.updated, order: .reverse) private var profiles: [UserProfile]
    @Query(sort: \TrainingPlanRecord.created, order: .reverse) private var plans: [TrainingPlanRecord]

    var body: some View {
        PaywallScreen(story: PaywallStory(moment: .returning, profile: profiles.first, plan: plans.first?.plan),
                      onClose: nil, onUnlocked: {})
    }
}

/// One paywall for onboarding, the launch gate and the in-app sheet (refs: Duolingo and
/// Chessigma's narrator, Mobbin trial timelines; docs/design/decisions.md "Hard paywall").
///
/// The coach presents it in his bubble, in onboarding's voice and from the user's own result;
/// the user's road (tier piece and rating → goal); the honest trial timeline in the week's
/// track language (Today · reminder · billing, real dates, the store's price); the two plans
/// with the billed price as the loudest number; a pinned CTA with the price sentence under
/// it and Restore · Terms · Privacy. No close button unless `onClose` is set.
struct PaywallScreen: View {
    let story: PaywallStory
    /// Shows a close button (the in-app sheet). Nil = blocking (onboarding, launch gate).
    var onClose: (() -> Void)?
    /// After a purchase or restore that unlocked Pro (once).
    let onUnlocked: () -> Void

    @Environment(Entitlements.self) private var entitlements
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedID: String?
    @State private var busy = false
    @State private var note: String?
    @State private var unlocked = false

    private var selected: Entitlements.Plan? {
        entitlements.plans.first { $0.id == selectedID }
            ?? entitlements.plans.first { $0.period == .yearly }
            ?? entitlements.plans.first
    }

    private enum Offer { case pro, loading, failed, cantPay, plan(Entitlements.Plan) }

    private var offer: Offer {
        if entitlements.isPro { return .pro }
        if let selected { return entitlements.canMakePayments ? .plan(selected) : .cantPay }
        if entitlements.plansFailed && !entitlements.loadingPlans { return .failed }
        return .loading
    }

    private var timeline: TrialTimeline? {
        guard case .plan(let plan) = offer else { return nil }
        return TrialTimeline(plan: plan, todayDetail: story.todayDetail)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let onClose {
                    BarButton(systemImage: "xmark", label: "Close", action: onClose)
                }
                Spacer()
            }
            .frame(height: onClose == nil ? DS.Spacing.s : 44)
            .padding(.horizontal, DS.Spacing.s)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CoachBubble(pose: coachPose, text: coachText, avatarSize: 76)
                    // The road is the onboarding / gate's picture; the in-app sheet is shorter
                    // and about the feature that opened it.
                    if onClose == nil, let rating = story.rating, let goal = story.goal, goal > rating {
                        GoalRoad(rating: rating, goal: goal, goalDate: story.goalDate)
                    }
                    offerSection
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.top, DS.Spacing.s)
                .padding(.bottom, DS.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectStyle(.soft, for: .bottom)

            footer
        }
        .background(DS.Color.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(onClose == nil)
        .task {
            if entitlements.plans.isEmpty && !entitlements.loadingPlans { await entitlements.loadPlans() }
        }
        .onChange(of: entitlements.isPro) { _, pro in
            if pro { unlock() }
        }
    }

    /// The story's line; when the store can't sell, the coach says why instead (inline, with
    /// the button below as the way out).
    private var coachText: String {
        switch offer {
        case .failed: "I couldn't reach the App Store to load the plans. Check your connection and **try again**."
        case .cantPay: "Purchases are turned off on this iPhone, often by Screen Time. Subscribed before? **Restore** below."
        default: story.coachLine(isPro: entitlements.isPro)
        }
    }

    private var coachPose: CoachPose {
        switch offer {
        case .failed, .cantPay: .thinking
        default: .pleased
        }
    }

    // MARK: Offer

    @ViewBuilder
    private var offerSection: some View {
        switch offer {
        case .pro:
            EmptyView()
        case .loading:
            heading("Coach Pro")
            VStack(spacing: DS.Spacing.s) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                        .fill(DS.Color.surface)
                        .frame(height: 68)
                }
            }
            .overlay { ProgressView().tint(DS.Color.textSecondary) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading the plans")
        case .failed, .cantPay:
            // What Pro opens, without a price or trial the store hasn't confirmed.
            heading("Coach Pro")
            TimelineTrack(steps: [TrialTimeline.Step(kind: .today, marker: "With Pro", date: nil,
                                                     title: "Everything unlocked", detail: story.todayDetail)])
        case .plan(let plan):
            if let timeline {
                heading(timeline.heading)
                TimelineTrack(steps: timeline.steps)
            }
            // Accessibility sizes: the plans scroll with the story so the pinned footer
            // (button, price sentence, links) still fits.
            if typeSize.isAccessibilitySize { planPicker(plan) }
        }
    }

    private func planPicker(_ plan: Entitlements.Plan) -> some View {
        VStack(spacing: DS.Spacing.s) {
            ForEach(entitlements.plans) { option in
                PlanOption(plan: option, selected: option.id == plan.id) {
                    withAnimation(.snappy(duration: 0.25)) { selectedID = option.id }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.title)
            .foregroundStyle(DS.Color.text)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: DS.Spacing.s) {
            switch offer {
            case .pro:
                PrimaryButton(title: "Done") { if let onClose { onClose() } else { unlock() } }
            case .loading:
                PrimaryButton(title: "Loading plans…") {}
                    .disabled(true)
                    .opacity(0.5)
            case .failed:
                PrimaryButton(title: "Try again") { Task { await entitlements.loadPlans() } }
            case .cantPay:
                PrimaryButton(title: "Subscribe") {}
                    .disabled(true)
                    .opacity(0.5)
            case .plan(let plan):
                // The plans sit with the button: price, period and the monthly alternative
                // are always on screen next to the CTA.
                if !typeSize.isAccessibilitySize {
                    planPicker(plan).padding(.bottom, DS.Spacing.xs)
                }
                PrimaryButton(title: busy ? "One moment…" : (timeline?.cta ?? "Subscribe")) { buy(plan) }
                    .disabled(busy)
            }
            if let line = note ?? timeline?.billing {
                Text(line)
                    .font(DS.Font.footnote.weight(.medium))
                    .foregroundStyle(DS.Color.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.top, DS.Spacing.sm)
        .background(DS.Color.background)
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
            case .pending: note = "Waiting for approval. Pro unlocks as soon as it's approved."
            case .failed(let message): note = message
            }
        }
    }

    private func restore() {
        busy = true
        note = nil
        Task {
            do {
                if try await entitlements.restore() { unlock() } else { note = "No Coach Pro purchase found on this Apple Account." }
            } catch {
                note = "Couldn't reach the App Store. Try again in a moment."
            }
            busy = false
        }
    }
}

/// The user's road in one row: their tier piece and rating, a dashed accent road, the goal
/// and its month beside the goal tier's piece. Home's "960 → 1500 by May" as a picture.
private struct GoalRoad: View {
    let rating: Int
    let goal: Int
    let goalDate: Date?

    private var month: String? { goalDate?.formatted(.dateTime.month(.wide)) }

    var body: some View {
        let from = RatingTier(rating: rating), to = RatingTier(rating: goal)
        HStack(spacing: DS.Spacing.s) {
            PieceArt(kind: from.pieceKind, size: 36)
            end(value: rating, label: from.name, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule()
                        .fill(i == 0 ? DS.Color.accent : DS.Color.accent.opacity(0.7 - Double(i) * 0.07))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, DS.Spacing.xs)
            end(value: goal, label: month.map { "by \($0)" } ?? to.name, alignment: .trailing)
            PieceArt(kind: to.pieceKind, size: 36)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From \(rating), \(from.name), to \(goal)\(month.map { " by \($0)" } ?? "")")
    }

    private func end(value: Int, label: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(verbatim: "\(value)")
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundStyle(DS.Color.text)
            Text(label)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .fixedSize()
    }
}

/// The trial timeline in the week's track language: chunky round tokens joined by a track,
/// today lit in accent.
private struct TimelineTrack: View {
    let steps: [TrialTimeline.Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                let last = i == steps.count - 1
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        TimelineToken(kind: step.kind)
                        if !last {
                            Rectangle()
                                .fill(DS.Color.surface2)
                                .frame(width: 5)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 0) {
                            Text(step.marker)
                                .foregroundStyle(step.kind == .today ? DS.Color.accent : DS.Color.textSecondary)
                            if let date = step.date {
                                Text(verbatim: " · \(date)").foregroundStyle(DS.Color.textSecondary)
                            }
                        }
                        .font(DS.Font.footnote.weight(.semibold))
                        Text(step.title)
                            .font(DS.Font.headline)
                            .foregroundStyle(DS.Color.text)
                        Text(step.detail)
                            .font(DS.Font.subheadline)
                            .foregroundStyle(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 1)
                    .padding(.bottom, last ? 0 : DS.Spacing.m)
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A timeline step's token: the week's chunky round token, accent for today.
private struct TimelineToken: View {
    let kind: TrialTimeline.Step.Kind

    var body: some View {
        let lit = kind == .today
        ZStack {
            Ellipse().fill(lit ? DS.Color.accentPressed : Color(hex: 0x0E1011)).frame(width: 48, height: 44).offset(y: 4)
            Ellipse().fill(lit ? DS.Color.accent : DS.Color.surface2).frame(width: 48, height: 44)
            IconImage(icon, size: 22)
                .foregroundStyle(lit ? DS.Color.onAccent : DS.Color.text)
        }
        .frame(height: 50)
        .accessibilityHidden(true)
    }

    private var icon: String {
        switch kind {
        case .today: "unlock"
        case .reminder: "reminder"
        case .billing, .renews: "calendar"
        }
    }
}

/// One plan: a radio mark, the name and its terms, the billed price as the loudest number
/// (App Review 3.1.2); the yearly's per-month figure stays secondary.
private struct PlanOption: View {
    let plan: Entitlements.Plan
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                ZStack {
                    Circle()
                        .strokeBorder(selected ? DS.Color.accent : DS.Color.surface2, lineWidth: 2.5)
                    if selected {
                        Circle().fill(DS.Color.accent).padding(5)
                    }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.period == .yearly ? "Yearly" : "Monthly")
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Color.text)
                    Text(detail)
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer(minLength: DS.Spacing.s)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.price)
                        .font(DS.Font.headline.monospacedDigit())
                        .foregroundStyle(DS.Color.text)
                    Text(plan.period == .yearly ? "a year" : "a month")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, 10)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)
                    .strokeBorder(selected ? DS.Color.accent : .clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var detail: String {
        switch plan.period {
        case .yearly:
            let perMonth = plan.perMonth.map { "\($0) a month" }
            if let trial = plan.freeTrial { return ["\(trial) free", perMonth].compactMap { $0 }.joined(separator: " · ") }
            return perMonth ?? "Billed once a year"
        case .monthly:
            return plan.freeTrial.map { "\($0) free · billed monthly" } ?? "Billed monthly, no trial"
        }
    }
}
