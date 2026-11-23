import SwiftUI

/// Hold-to-talk mic for the glass action bar: press and hold, say a move, let go.
/// Same 48 pt footprint and neutral glyph as `ActionBarButton`; while listening the glyph
/// fills in the accent. VoiceOver: a double-tap starts listening, a second one stops.
struct VoiceMicButton: View {
    let voice: VoiceInput
    /// The final transcript of a press.
    let onText: (String) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var holding = false

    var body: some View {
        Image(systemName: voice.phase == .listening ? "mic.fill" : "mic")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(glyphColor)
            .symbolEffect(.pulse, isActive: voice.phase == .listening)
            .frame(width: 48, height: 48)
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
                if voice.phase == .listening { voice.end() } else { Task { await voice.begin(onText: onText) } }
            }
    }

    private var glyphColor: Color {
        if !isEnabled { return DS.Color.text.opacity(0.3) }
        return voice.phase == .listening ? DS.Color.accent : DS.Color.text
    }
}
