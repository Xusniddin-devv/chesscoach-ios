import SwiftUI
import SwiftData
import ChessCore

/// The onboarding container: one step at a time, a plain back chevron, no carousel dots.
/// First launch shows it in place of the tabs; Settings → Import games presents it again.
struct OnboardingFlow: View {
    @State private var model: OnboardingModel
    @Environment(\.modelContext) private var context
    @Environment(BackgroundAnalysis.self) private var background: BackgroundAnalysis?
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.hardPaywall) private var hardPaywall
    @Query private var lessons: [LessonProgress]
    let onFinish: () -> Void
    /// Whether the flow must stay up against a synced profile (`OnboardingModel.holdsOnboarding`).
    var onEngagedChange: (Bool) -> Void = { _ in }

    init(reimport: Bool = false, onEngagedChange: @escaping (Bool) -> Void = { _ in }, onFinish: @escaping () -> Void) {
        _model = State(initialValue: OnboardingModel(reimport: reimport))
        self.onEngagedChange = onEngagedChange
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            let _ = model.stepRevision  // see OnboardingModel.stepRevision
            Group {
                switch model.step {
                case .welcome: WelcomeStep(model: model)
                case .find: FindStep(model: model, onClose: model.reimport ? onFinish : nil)
                case .importing: ImportStep(model: model)
                case .question(let i): QuestionStep(model: model, index: i)
                case .reveal: RevealStep(model: model)
                case .goal: GoalStep(model: model) {
                    model.buildPlan(completedLessons: Set(lessons.map(\.lessonId)))
                    model.go(.plan)
                }
                case .plan: PlanStep(model: model, startTitle: endsOnPaywall ? "Continue" : "Start day 1") {
                    finishPlan()
                }
                case .paywall: PaywallScreen(moment: .onboarding,
                                             onClose: LaunchRoute.onboardingPaywallClosable(hardPaywall: hardPaywall) ? onFinish : nil,
                                             onUnlocked: onFinish)
                }
            }
            // One identity per step, so a step that leaves is really removed (without it the
            // find step could linger over the import after its removal transition).
            .id(model.step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .preferredColorScheme(.dark)
        .onAppear {
            model.background = background
            model.finishPlan = finishPlan
        }
        .onChange(of: model.holdsOnboarding, initial: true) { _, holds in onEngagedChange(holds) }
        #if DEBUG
        .task { await OnboardingDebug.apply(model, context: context) }
        #endif
    }
}

extension OnboardingFlow {
    private var endsOnPaywall: Bool {
        LaunchRoute.onboardingEndsOnPaywall(hardPaywall: hardPaywall, isPro: entitlements.isPro, reimport: model.reimport)
    }

    /// Saves everything first (a launch after quitting on the paywall lands on the launch
    /// gate, not a second onboarding), then the paywall or the app.
    private func finishPlan() {
        model.save(in: context)
        if endsOnPaywall { model.go(.paywall) } else { onFinish() }
    }
}

/// Shared layout: back chevron, sentence-case title, content, one pinned primary action.
struct OnboardingScaffold<Content: View, Footer: View>: View {
    let model: OnboardingModel
    var title: String?
    var subtitle: String?
    var showsBack = true
    var leading: (() -> Void)?
    var leadingSystemImage = "chevron.left"
    /// The coach's remark, pinned above the footer.
    var coach: CoachLine?
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let leading {
                    BarButton(systemImage: leadingSystemImage, label: "Close", action: leading)
                } else if showsBack && model.canGoBack {
                    BarButton(systemImage: "chevron.left", label: "Back", action: model.back)
                }
                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, DS.Spacing.s)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    if title != nil || subtitle != nil {
                        VStack(alignment: .leading, spacing: DS.Spacing.s) {
                            if let title {
                                Text(title)
                                    .font(DS.Font.largeTitle)
                                    .foregroundStyle(DS.Color.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let subtitle {
                                Text(subtitle)
                                    .font(DS.Font.body)
                                    .foregroundStyle(DS.Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    content
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.top, DS.Spacing.s)
                .padding(.bottom, DS.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            if let coach {
                CoachBubble(coach, avatarSize: 88)
                    .padding(.horizontal, DS.Spacing.m)
                    .padding(.bottom, DS.Spacing.sm)
            }
            footer
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.s)
        }
    }
}

/// A plain icon button for the top row (no glass circle on content screens).
struct BarButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(DS.Color.text)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// An Icons8 glyph (vectorised template asset) tinted by the current foreground style.
struct Glyph: View {
    let name: String
    var size: CGFloat = 22

    var body: some View {
        Image("Icons/\(name)")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A big 3D piece from the board set.
struct PieceArt: View {
    let kind: Piece.Kind
    var color: Piece.Color = .white
    var size: CGFloat

    var body: some View {
        PieceImage(piece: Piece(kind, color: color, square: .a1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
