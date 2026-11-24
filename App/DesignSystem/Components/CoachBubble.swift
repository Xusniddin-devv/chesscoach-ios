import SwiftUI
import UIKit
import ChessCore

/// The coach character: a cream knight with round glasses and a Signal-Orange scarf,
/// in the board's matte piece style (assets `Coach/{neutral,pleased,thinking,concerned}`).
enum CoachPose: String, CaseIterable, Sendable {
    case neutral, pleased, thinking, concerned

    init(_ mood: CoachMood) { self = CoachPose(rawValue: mood.rawValue) ?? .neutral }

    /// The coach's face for a graded move: pleased at the good ones, concerned at mistakes.
    init(_ moveClass: MoveClass) {
        switch moveClass {
        case .brilliant, .great, .best, .excellent: self = .pleased
        case .mistake, .miss, .blunder: self = .concerned
        case .inaccuracy: self = .thinking
        case .good, .book, .forced: self = .neutral
        }
    }

    var asset: String { "Coach/\(rawValue)" }
}

/// The coach figure alone. Transparent canvas; the piece stands on the bottom edge.
struct CoachAvatar: View {
    var pose: CoachPose = .neutral
    var size: CGFloat = 72
    /// Draws a soft contact shadow under the base, for when the coach stands on a board.
    var grounded = false

    var body: some View {
        Image(pose.asset)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .background(alignment: .bottom) {
                if grounded {
                    Ellipse()
                        .fill(.black.opacity(0.5))
                        .frame(width: size * 0.56, height: size * 0.09)
                        .blur(radius: size * 0.025)
                        .offset(y: -size * 0.01)
                }
            }
            .accessibilityHidden(true)
    }
}

/// The coach speaking: figure on the left, a flat `surface` bubble whose tail points at its head.
///
///     CoachBubble(pose: .concerned, text: "Your knight on [g5] was left hanging on move 9.")
///     CoachBubble(.init(.pleased, "Clean game."), avatarSize: 96)   // from a ChessCore CoachLine
///
/// `text` supports square chips (`[e4]`, drawn as small board-coloured tiles) and
/// `**bold**` (Markdown). A new `text` pops in; pass `animated: false` to swap silently.
struct CoachBubble: View {
    let pose: CoachPose
    let text: String
    var avatarSize: CGFloat = 72
    var animated = true
    /// Bubble fill; `surface2` when the bubble sits on a `surface` card.
    var fill: Color = DS.Color.surface
    var grounded = false

    init(pose: CoachPose, text: String, avatarSize: CGFloat = 72, animated: Bool = true,
         fill: Color = DS.Color.surface, grounded: Bool = false) {
        self.grounded = grounded
        self.pose = pose
        self.text = text
        self.avatarSize = avatarSize
        self.animated = animated
        self.fill = fill
    }

    init(_ line: CoachLine, avatarSize: CGFloat = 72, animated: Bool = true, fill: Color = DS.Color.surface) {
        self.init(pose: CoachPose(line.mood), text: line.text, avatarSize: avatarSize, animated: animated, fill: fill)
    }

    var body: some View {
        // The figure fills the middle ~55 % of its square canvas: pull the bubble in over the
        // empty right margin and lift it so the tail points at the head.
        HStack(alignment: .bottom, spacing: -avatarSize * 0.2) {
            CoachAvatar(pose: pose, size: avatarSize, grounded: grounded)
                .id(pose)
                .transition(.opacity)
            bubble
                .padding(.bottom, avatarSize * 0.5)
        }
        .animation(animated ? .spring(duration: 0.35, bounce: 0.25) : nil, value: text)
        .animation(animated ? .easeInOut(duration: 0.2) : nil, value: pose)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach: \(CoachText.plain(text))")
    }

    private var bubble: some View {
        CoachText(text)
            .font(DS.Font.body)
            .foregroundStyle(DS.Color.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BubbleShape(tailY: 22).fill(fill))
            .id(text)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.94, anchor: .bottomLeading).combined(with: .opacity),
                removal: .opacity))
    }
}

/// Rounded rectangle with a short tail on the left edge, `tailY` above the bottom.
struct BubbleShape: Shape {
    var radius: CGFloat = DS.Radius.large
    var tailY: CGFloat = 22
    var tail: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect.insetBy(dx: 0, dy: 0), cornerRadius: radius, style: .continuous)
        let y = max(radius, rect.maxY - tailY)
        var t = Path()
        t.move(to: CGPoint(x: rect.minX + 1, y: y - tail))
        t.addQuadCurve(to: CGPoint(x: rect.minX - tail, y: y + tail * 0.6),
                       control: CGPoint(x: rect.minX - 1, y: y))
        t.addQuadCurve(to: CGPoint(x: rect.minX + 1, y: y + tail * 0.5),
                       control: CGPoint(x: rect.minX - 1, y: y + tail * 0.6))
        t.closeSubpath()
        p.addPath(t)
        return p
    }
}

/// Text with inline square chips: "lands on [c4] and stares at [f7]" → chips for c4 and f7.
/// Also renders `**bold**`. Reusable in coach cards, review and lessons.
struct CoachText: View {
    let source: String
    @Environment(\.displayScale) private var scale

    init(_ source: String) { self.source = source }

    var body: some View {
        Self.segments(source).reduce(Text("")) { text, segment in
            switch segment {
            case .words(let words):
                let attributed = (try? AttributedString(markdown: words, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    ?? AttributedString(words)
                return Text("\(text)\(Text(attributed))")
            case .square(let square):
                let chip = Text(Image(uiImage: SquareChip.image(square, scale: scale))).baselineOffset(-4)
                return Text("\(text)\(chip)")
            }
        }
    }

    enum Segment: Equatable { case words(String), square(String) }

    static func segments(_ s: String) -> [Segment] {
        var out: [Segment] = []
        var rest = Substring(s)
        let pattern = /\[([a-h][1-8])\]/
        while let match = rest.firstMatch(of: pattern) {
            let before = rest[rest.startIndex..<match.range.lowerBound]
            if !before.isEmpty { out.append(.words(String(before))) }
            out.append(.square(String(match.1)))
            rest = rest[match.range.upperBound...]
        }
        if !rest.isEmpty { out.append(.words(String(rest))) }
        return out
    }

    /// Marks up engine-written prose for `CoachText`: bare square names ("on g5") become
    /// chips, and `san` (the move being talked about) is set in bold. Square names inside a
    /// move ("Nf3", "exd5") and text already marked are left alone.
    static func marked(_ plain: String, san: String? = nil) -> String {
        var s = plain
        if let san, !san.isEmpty, !s.contains("**") {
            s = s.replacingOccurrences(of: san, with: "**\(san)**")
        }
        let range = NSRange(s.startIndex..., in: s)
        // Not after a letter, digit, "[" or "*" (bold SAN) and not before a letter, digit or "]".
        let regex = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9\\[*])([a-h][1-8])(?![A-Za-z0-9\\]*])")
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: "[$1]")
    }

    /// The text without chip brackets, for VoiceOver.
    static func plain(_ s: String) -> String {
        segments(s).map { if case .words(let w) = $0 { w.replacingOccurrences(of: "**", with: "") } else if case .square(let q) = $0 { q } else { "" } }.joined()
    }
}

/// A square name on its own board colour: light squares stone, dark squares slate, ink text.
enum SquareChip {
    @MainActor private static var cache: [String: UIImage] = [:]

    static func isLight(_ square: String) -> Bool {
        guard let f = square.first?.asciiValue, let r = square.last?.wholeNumberValue else { return true }
        return (Int(f - 97) + r) % 2 == 0
    }

    @MainActor
    static func image(_ square: String, scale: CGFloat) -> UIImage {
        let pointSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        let key = "\(square)-\(scale)-\(pointSize)"
        if let hit = cache[key] { return hit }
        let renderer = ImageRenderer(content:
            Text(square)
                .font(.system(size: pointSize * 0.82, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.Color.ink)
                .padding(.horizontal, 5)
                .frame(height: pointSize * 1.25)
                .background(isLight(square) ? DS.Color.boardLight : DS.Color.boardDark,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        )
        renderer.scale = scale
        let image = renderer.uiImage ?? UIImage()
        cache[key] = image
        return image
    }
}

#Preview {
    VStack(spacing: 24) {
        CoachBubble(pose: .neutral, text: "I'll read your last 20 games, move by move.")
        CoachBubble(pose: .concerned, text: "Game 4: your knight on [g5] was left hanging on move 9. Noted.")
        CoachBubble(pose: .pleased, text: "**Clean game.** No blunders at all.", avatarSize: 96)
    }
    .padding()
    .background(DS.Color.background)
}
