import SwiftUI

/// Hold-to-talk mic, one cell of the flat `GameActionBar`: press and hold, say a move, let go.
/// Same footprint as `GameAction` (24 pt Icons8 icon over an 11 pt label); while listening
/// the cell turns accent and reads "Listening". VoiceOver: a double-tap starts listening, a
/// second one stops.
struct VoiceMicButton: View {
    let voice: VoiceInput
    /// The final transcript of a press.
    let onText: (String) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var holding = false

    private var listening: Bool { voice.phase == .listening }

    var body: some View {
        VStack(spacing: 3) {
            Image("Icons/mic")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
            Text(listening ? "Listening" : "Voice")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(listening ? DS.Color.accent : DS.Color.text)
        .opacity(isEnabled ? 1 : 0.3)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.medium)
                .fill(holding ? DS.Color.surface2 : .clear)
        }
        .scaleEffect(holding ? 0.96 : 1)
        .animation(.snappy(duration: 0.15), value: holding)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled, !holding else { return }
                    holding = true
                    Task { await voice.begin(onText: onText) }
                }
                .onEnded { _ in
                    guard holding else { return }
                    holding = false
                    voice.end()
                })
        .sensoryFeedback(.impact(weight: .light), trigger: holding) { _, now in now }
        .accessibilityElement()
        .accessibilityLabel("Say a move")
        .accessibilityHint("Hold, say a move like knight to f3, then let go.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if listening { voice.end() } else { Task { await voice.begin(onText: onText) } }
        }
    }
}
