import SwiftUI

/// Coach Pro paywall (refs: docs/design/references/paywall/notes.md). Left-aligned title and
/// the line for the feature that opened it, four concrete value lines, two plan rows (Yearly
/// preselected, ring marks the choice), then a pinned bottom with the one accent button, the
/// billing sentence and Restore · Terms · Privacy. No hero art, ribbons, strike-through
/// prices or countdowns.
struct PaywallView: View {
    let feature: ProFeature?

    @Environment(Entitlements.self) private var entitlements
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var busy = false
    @State private var note: String?

    static let values = [
        "Explanations for every mistake",
        "Full game review with move-by-move badges",
        "Unlimited puzzles from your own blunders",
        "All 34 lessons",
    ]

    private var selected: Entitlements.Plan? {
        entitlements.plans.first { $0.id == selectedID } ?? entitlements.plans.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    header
                    valueList
                    if !entitlements.isPro { plans }
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(DS.Color.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .tint(DS.Color.text)
        .presentationBackground(DS.Color.background)
        .preferredColorScheme(.dark)
        .task {
            if entitlements.plans.isEmpty && !entitlements.loadingPlans { await entitlements.loadPlans() }
            if selectedID == nil { selectedID = entitlements.plans.first { $0.period == .yearly }?.id }
        }
        .onChange(of: entitlements.plans) { _, plans in
            if selectedID == nil { selectedID = plans.first { $0.period == .yearly }?.id }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text(entitlements.isPro ? "You have Coach Pro" : "Coach Pro")
                .font(DS.Font.largeTitle)
                .foregroundStyle(DS.Color.text)
            Text(entitlements.isPro ? "Everything below is unlocked on this Apple Account."
                                    : (feature?.pitch ?? "The whole coach, on every game you play."))
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DS.Spacing.s)
    }

    private var valueList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(Self.values, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DS.Color.accent)
                        .frame(width: 6, height: 6)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1.5 }
                    Text(line)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var plans: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if entitlements.plansFailed && !entitlements.loadingPlans {
                InlineErrorRow(message: "Couldn't load the plans.", actionTitle: "Retry") {
                    Task { await entitlements.loadPlans() }
                }
            } else if entitlements.plans.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 148)
            } else {
                ForEach(entitlements.plans) { plan in
                    PlanRow(plan: plan, selected: plan.id == selected?.id) { selectedID = plan.id }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: DS.Spacing.sm) {
            if entitlements.isPro {
                PrimaryButton(title: "Done") { dismiss() }
            } else {
                PrimaryButton(title: busy ? "One moment…" : ctaTitle) { buy() }
                    .disabled(busy || selected == nil)
                    .opacity(selected == nil ? 0.5 : 1)
                Text(note ?? billingLine)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: DS.Spacing.m) {
                if !entitlements.isPro {
                    Button("Restore") { restore() }.disabled(busy)
                }
                Link("Terms", destination: AppInfo.termsURL)
                Link("Privacy", destination: AppInfo.privacyURL)
            }
            .font(DS.Font.caption.weight(.semibold))
            .foregroundStyle(DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.m)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.s)
        .background(DS.Color.background)
    }

    private var ctaTitle: String {
        guard let plan = selected else { return "Subscribe" }
        if let trial = plan.freeTrial { return "Try \(trial) free" }
        return "Subscribe"
    }

    private var billingLine: String {
        guard let plan = selected else { return " " }
        let cancel = "Cancel anytime in Settings."
        switch plan.period {
        case .yearly:
            if let trial = plan.freeTrial { return "\(trial) free, then \(plan.price) a year. \(cancel)" }
            return "\(plan.price) a year. \(cancel)"
        case .monthly:
            return "\(plan.price) a month. \(cancel)"
        }
    }

    // MARK: Actions

    private func buy() {
        guard let plan = selected, !busy else { return }
        busy = true
        note = nil
        Task {
            let result = await entitlements.purchase(plan)
            busy = false
            switch result {
            case .purchased: dismiss()
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
                let pro = try await entitlements.restore()
                if pro { dismiss() } else { note = "No Coach Pro purchase found on this Apple Account." }
            } catch {
                note = "Couldn't reach the App Store. Try again in a moment."
            }
            busy = false
        }
    }
}

/// One plan: name and billing on the left, the monthly figure in mono on the right.
/// Selection is a 2 pt accent ring; the unselected row has a hairline.
private struct PlanRow: View {
    let plan: Entitlements.Plan
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
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
                    Text(plan.perMonth ?? plan.price)
                        .font(DS.Font.numeral)
                        .foregroundStyle(DS.Color.text)
                    Text("a month")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .padding(DS.Spacing.m)
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.large)
                    .strokeBorder(selected ? DS.Color.accent : DS.Color.surface2, lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var detail: String {
        switch plan.period {
        case .yearly:
            if let trial = plan.freeTrial { return "\(trial) free, then \(plan.price) a year" }
            return "\(plan.price) a year"
        case .monthly:
            return "Billed every month"
        }
    }
}
