import SwiftUI
import ChessCore

/// "Where do you play" and "what's your name there" as one short conversation. The coach
/// greets and asks; the user's answer is their reply bubble, typed in place at the bottom;
/// both platforms are searched as they type and the coach answers with what he found, right
/// in his bubble. The column is anchored to the bottom like a chat, so it sits on the input
/// in every state.
struct FindStep: View {
    @Bindable var model: OnboardingModel
    var onClose: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let onClose {
                    BarButton(systemImage: "xmark", label: "Close", action: onClose)
                } else if model.canGoBack {
                    BarButton(systemImage: "chevron.left", label: "Back", action: model.back)
                }
                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, DS.Spacing.s)

            GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Spacer(minLength: 0)
                    // The conversation's header, like a contact card at the top of a chat: the
                    // coach standing on his board. With the keyboard up it scrolls out of view.
                    // Folds away once accounts are found, so the answer has the room.
                    CoachHeader()
                        .padding(.bottom, DS.Spacing.m)
                        .frame(height: state == .found ? 0 : nil, alignment: .top)
                        .opacity(state == .found ? 0 : 1)
                        .clipped()
                    CoachTurn(pose: greetingPose) {
                        ChatBubble(text: "Hi, I'm your coach.")
                        ChatBubble(text: "What's your username? I'll find you on **chess.com** or **Lichess**.")
                        if state == .empty {
                            QuickReply(title: "I'm new to chess", action: model.startQuestions)
                                .padding(.top, DS.Spacing.xs)
                                .transition(.opacity)
                        }
                    }
                    reply
                        .id("reply")
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.sm)
                // Bottom-anchored like a chat: short conversations sit on the reply field.
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .bottomLeading)
                .animation(.snappy(duration: 0.3), value: state)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            }

            ReplyField(text: $model.username, focused: $focused, onSubmit: submit)
                .onChange(of: model.username) { model.usernameChanged() }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.s)
        }
        .onAppear {
            focused = true
            model.releaseFocus = { focused = false }
        }
        .onDisappear { model.releaseFocus = nil }
        .sensoryFeedback(.success, trigger: model.foundProfiles.count) { old, new in new > old }
    }

    // MARK: State

    enum ChatState: Equatable { case empty, searching, found, notFound, failed }

    private var state: ChatState {
        let all = ImportPlatform.allCases.map { model.lookup($0) }
        if all.allSatisfy({ $0 == .idle }) { return .empty }
        if !model.foundProfiles.isEmpty { return .found }
        if all.contains(.checking) { return .searching }
        if all.allSatisfy({ $0 == .notFound }) { return .notFound }
        return .failed
    }

    private var greetingPose: CoachPose {
        switch state {
        case .empty: .neutral
        case .searching: .thinking
        case .found: .pleased
        case .notFound, .failed: .concerned
        }
    }

    /// The coach's answer to what is typed.
    @ViewBuilder
    private var reply: some View {
        switch state {
        case .empty:
            EmptyView()
        case .searching:
            CoachTurn(pose: .thinking, showsAvatar: false) { TypingBubble() }
                .transition(.opacity)
        case .found:
            CoachTurn(pose: .pleased, showsAvatar: false) {
                ChatBubble {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        CoachText(foundLine)
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.text)
                        ForEach(model.foundProfiles, id: \.platform) { profile in
                            ProfileRow(profile: profile) { model.pick(profile) }
                        }
                        if model.isSearching {
                            HStack(spacing: DS.Spacing.s) {
                                ProgressView().controlSize(.mini).tint(DS.Color.textSecondary)
                                Text("Still checking the other site")
                            }
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .notFound:
            CoachTurn(pose: .concerned, showsAvatar: false) {
                ChatBubble(text: "I couldn't find **\(typed)** on either site. Check the spelling?")
            }
            .transition(.opacity)
        case .failed:
            CoachTurn(pose: .concerned, showsAvatar: false) {
                ChatBubble {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        Text(failureLine)
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.text)
                        HStack(spacing: DS.Spacing.s) {
                            ForEach(failedPlatforms, id: \.self) { platform in
                                QuickReply(title: "Try \(platform.title) again") { model.retryLookup(platform) }
                            }
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private var typed: String { model.username.trimmingCharacters(in: .whitespaces) }

    private var foundLine: String {
        let found = model.foundProfiles
        if found.count == 2 { return "Found you on both. **Which one do you play on most?**" }
        return "Found you on \(found.first?.platform.title ?? ""). **Tap to pick it.**"
    }

    private var failedPlatforms: [ImportPlatform] {
        ImportPlatform.allCases.filter { if case .failed = model.lookup($0) { true } else { false } }
    }

    private var failureLine: String {
        let names = failedPlatforms.map(\.title).joined(separator: " and ")
        return "\(names) isn't answering right now."
    }

    /// Return picks the only account found.
    private func submit() {
        if model.foundProfiles.count == 1, let only = model.foundProfiles.first { model.pick(only) }
    }
}

// MARK: - Chat pieces

/// The coach on the near edge of his board, with his name: the top of the conversation.
private struct CoachHeader: View {
    var body: some View {
        VStack(spacing: 0) {
            CoachAvatar(pose: .pleased, size: 150, grounded: true)
                .padding(.bottom, -26)
                .zIndex(1)
            BoardEdge(ranks: 2, height: 70)
                .padding(.horizontal, -DS.Spacing.m)
            Text("Coach")
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.text)
                .padding(.top, DS.Spacing.s)
            Text("Reads your games on this iPhone · Powered by Stockfish")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The coach's turn: his bubbles stacked, his avatar at the bottom left of the group.
private struct CoachTurn<Content: View>: View {
    var pose: CoachPose = .neutral
    var showsAvatar = true
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.s) {
            Group {
                if showsAvatar {
                    CoachAvatar(pose: pose, size: 56)
                        .id(pose)
                        .transition(.opacity)
                } else {
                    Color.clear
                }
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) { content }
            Spacer(minLength: DS.Spacing.s)
        }
    }
}

/// A coach bubble: flat `surface`, the corner nearest the coach tucked in.
struct ChatBubble<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.surface, in: UnevenRoundedRectangle(
                topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20))
    }
}

extension ChatBubble where Content == AnyView {
    init(text: String) {
        self.init {
            AnyView(CoachText(text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.text)
                .fixedSize(horizontal: false, vertical: true))
        }
    }
}

/// Three dots that breathe while the coach looks the name up.
private struct TypingBubble: View {
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ChatBubble {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(DS.Color.textSecondary)
                        .frame(width: 8, height: 8)
                        .opacity(reduceMotion ? 0.7 : (phase ? 1 : 0.3))
                        .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.16), value: phase)
                }
            }
            .frame(height: 22)
        }
        .onAppear { phase = true }
        .accessibilityLabel("Looking you up")
    }
}

/// A chunky reply chip with a pressed bottom edge.
struct QuickReply: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.subheadline.weight(.semibold))
                .foregroundStyle(selected ? DS.Color.onAccent : DS.Color.text)
                .padding(.horizontal, DS.Spacing.m)
                .frame(minHeight: 40)
        }
        .buttonStyle(ChunkyStyle(fill: selected ? DS.Color.accent : DS.Color.surface2,
                                 edge: selected ? DS.Color.accentPressed : Color(hex: 0x1F2225),
                                 radius: 20))
    }
}

/// Solid face, a darker 3 pt edge underneath; pressing pushes the face down onto it.
struct ChunkyStyle: ButtonStyle {
    let fill: Color
    let edge: Color
    var radius: CGFloat = DS.Radius.medium

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: radius).fill(edge).offset(y: pressed ? 0 : 3)
            }
            .offset(y: pressed ? 3 : 0)
            .padding(.bottom, 3)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// One account the coach found, inside his bubble: avatar, platform and name, a chip per
/// time control, games played. Tapping it picks it.
private struct ProfileRow: View {
    let profile: PlatformProfile
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                HStack(spacing: DS.Spacing.sm) {
                    PlayerAvatar(url: profile.avatarURL, rating: profile.currentRating ?? 800, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.platform.title)
                            .font(DS.Font.caption.weight(.semibold))
                            .foregroundStyle(DS.Color.textSecondary)
                        HStack(spacing: DS.Spacing.xs) {
                            if let title = profile.title {
                                Text(title)
                                    .font(DS.Font.caption.weight(.heavy))
                                    .foregroundStyle(DS.Color.accent)
                            }
                            Text(profile.username)
                                .font(DS.Font.headline)
                                .foregroundStyle(DS.Color.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 0)
                }
                RatingChips(ratings: Self.ratings(profile))
                if let games = profile.gameCount, games > 0 {
                    Text("\(games.formatted()) games played")
                        .font(DS.Font.caption.monospacedDigit())
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChunkyStyle(fill: DS.Color.surface2, edge: Color(hex: 0x1F2225), radius: DS.Radius.medium))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Reads your last 20 games on \(profile.platform.title)")
    }

    /// Time controls in the order they speak for the player.
    static func ratings(_ p: PlatformProfile) -> [(String, Int)] {
        PlatformProfile.ratingPreference.compactMap { key in p.ratings[key].map { (key.capitalized, $0) } }
    }
}

/// "Rapid 2838" chips: the word in sans, the number in mono.
private struct RatingChips: View {
    let ratings: [(String, Int)]

    var body: some View {
        if ratings.isEmpty {
            Text("No rated games yet")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
        } else {
            // Two chips a line, never truncated.
            let shown = Array(ratings.prefix(4))
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(Array(stride(from: 0, to: shown.count, by: 2)), id: \.self) { i in
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(shown[i..<min(i + 2, shown.count)], id: \.0) { name, value in
                            chip(name, value)
                        }
                    }
                }
            }
        }
    }

    private func chip(_ name: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundStyle(DS.Color.textSecondary)
            Text(value, format: .number.grouping(.never)).monospaced().foregroundStyle(DS.Color.text)
        }
        .font(DS.Font.caption.weight(.medium))
        .fixedSize()
        .padding(.horizontal, DS.Spacing.s)
        .padding(.vertical, 4)
        .background(DS.Color.background, in: Capsule())
    }
}

/// The user's reply bubble, typed in place: right-aligned, large type, accent caret.
private struct ReplyField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: DS.Spacing.xl)
            TextField("", text: $text, prompt: Text("your username").foregroundStyle(DS.Color.textSecondary.opacity(0.55)))
                .font(.title.weight(.semibold))
                .foregroundStyle(DS.Color.text)
                .tint(DS.Color.accent)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.username)
                .submitLabel(.go)
                .focused(focused)
                .onSubmit(onSubmit)
                .fixedSize(horizontal: text.count < 18, vertical: false)
                .padding(.horizontal, DS.Spacing.m)
                .frame(minWidth: 180, minHeight: 56)
                .background(DS.Color.surface2, in: UnevenRoundedRectangle(
                    topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 6, topTrailingRadius: 22))
                .accessibilityLabel("Your chess.com or Lichess username")
        }
    }
}
