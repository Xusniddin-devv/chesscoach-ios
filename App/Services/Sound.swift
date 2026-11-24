import AVFoundation
import OSLog

/// Game sounds, synthesised at launch (no bundled audio, nothing to license): a soft wooden
/// "thock" for a move, a double knock for a capture, two quick thocks for castling, a quiet
/// two-tone ping for check, a rising major triad for a win and a falling minor third for a loss.
/// `.ambient` session: mixes with the user's music and stays silent with the ring switch off.
/// Honours `Pref.sound`.
@MainActor
final class SoundPlayer {
    enum Effect: CaseIterable { case move, capture, castle, check, win, lose }

    static let shared = SoundPlayer()

    private static let log = Logger(subsystem: "uz.xq.chessc", category: "sound")
    private static let sampleRate = 44_100.0

    private let engine = AVAudioEngine()
    private let players = (0..<3).map { _ in AVAudioPlayerNode() }
    private var next = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundPlayer.sampleRate, channels: 1)!
    private lazy var buffers: [Effect: AVAudioPCMBuffer] = Dictionary(
        uniqueKeysWithValues: Effect.allCases.compactMap { e in Self.render(e, format: format).map { (e, $0) } })
    private var started = false

    private init() {}

    func play(_ effect: Effect) {
        guard Pref.bool(Pref.sound, default: Pref.Default.sound) else { return }
        guard startIfNeeded(), let buffer = buffers[effect] else { return }
        let player = players[next]
        next = (next + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    /// The sound for a move given its SAN ("Nxe5+", "O-O").
    static func effect(forSAN san: String) -> Effect {
        if san.contains("+") || san.contains("#") { return .check }
        if san.hasPrefix("O-O") { return .castle }
        if san.contains("x") { return .capture }
        return .move
    }

    private func startIfNeeded() -> Bool {
        if started && engine.isRunning { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            // Voice input switches to playAndRecord while listening and back here after.
            if session.category != .playAndRecord {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
            if !started {
                for player in players {
                    engine.attach(player)
                    engine.connect(player, to: engine.mainMixerNode, format: format)
                }
                engine.mainMixerNode.outputVolume = 0.8
            }
            try engine.start()
            started = true
            return true
        } catch {
            Self.log.error("Sound engine failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Synthesis

    /// One voice: a sine partial with an exponential decay, starting at `at` seconds.
    private struct Partial {
        var at: Double
        var freq: Double
        var amp: Double
        var decay: Double  // seconds to 1/e
    }

    /// A short low-passed noise burst (the "wood" of a knock).
    private struct Knock {
        var at: Double
        var amp: Double
    }

    private static func thock(at t: Double, pitch: Double = 1, amp: Double = 1) -> ([Partial], [Knock]) {
        ([Partial(at: t, freq: 170 * pitch, amp: 0.55 * amp, decay: 0.030),
          Partial(at: t, freq: 410 * pitch, amp: 0.22 * amp, decay: 0.018),
          Partial(at: t, freq: 980 * pitch, amp: 0.06 * amp, decay: 0.008)],
         [Knock(at: t, amp: 0.35 * amp)])
    }

    private static func note(_ freq: Double, at t: Double, amp: Double = 0.28, decay: Double = 0.22) -> [Partial] {
        [Partial(at: t, freq: freq, amp: amp, decay: decay),
         Partial(at: t, freq: freq * 2, amp: amp * 0.18, decay: decay * 0.6)]
    }

    private static func recipe(_ effect: Effect) -> (length: Double, partials: [Partial], knocks: [Knock]) {
        switch effect {
        case .move:
            let a = thock(at: 0)
            return (0.16, a.0, a.1)
        case .capture:
            let a = thock(at: 0, pitch: 0.92), b = thock(at: 0.045, pitch: 1.25, amp: 0.8)
            return (0.22, a.0 + b.0, a.1 + b.1)
        case .castle:
            let a = thock(at: 0), b = thock(at: 0.09, pitch: 1.06, amp: 0.85)
            return (0.26, a.0 + b.0, a.1 + b.1)
        case .check:
            let a = thock(at: 0)
            return (0.42, a.0 + note(1046.5, at: 0.03, amp: 0.12, decay: 0.12) + note(1318.5, at: 0.11, amp: 0.10, decay: 0.14), a.1)
        case .win:  // C5 E5 G5
            return (0.9, note(523.25, at: 0) + note(659.25, at: 0.11) + note(783.99, at: 0.22, decay: 0.32), [])
        case .lose:  // G4 → E♭4
            return (0.9, note(392.0, at: 0, amp: 0.22, decay: 0.25) + note(311.13, at: 0.18, amp: 0.22, decay: 0.35), [])
        }
    }

    private static func render(_ effect: Effect, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let r = recipe(effect)
        let frames = AVAudioFrameCount(r.length * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var rng = SystemRandomNumberGenerator()
        var low = 0.0
        let attack = 0.003, release = 0.02
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            var s = 0.0
            for p in r.partials where t >= p.at {
                let dt = t - p.at
                let env = min(1, dt / attack) * exp(-dt / p.decay)
                s += p.amp * env * sin(2 * .pi * p.freq * dt)
            }
            let noise = Double.random(in: -1...1, using: &rng)
            low += 0.18 * (noise - low)  // one-pole low-pass
            for k in r.knocks where t >= k.at {
                let dt = t - k.at
                s += k.amp * low * exp(-dt / 0.006)
            }
            let tail = min(1, (r.length - t) / release)  // fade out the last 20 ms
            out[i] = Float(max(-1, min(1, s * tail)))
        }
        return buffer
    }
}
