import AVFoundation
import Speech
import Observation
import OSLog
import ChessCore

/// Hold-to-talk speech → move. Recognition runs on the device only
/// (`requiresOnDeviceRecognition`); when the device cannot do that, voice is unavailable
/// rather than falling back to Apple's servers. The transcript goes through
/// `VoiceMove.parse` (ChessCore) against the live position.
@MainActor @Observable
final class VoiceInput {
    enum Phase: Equatable {
        case idle
        case listening
        /// The button was released; waiting for the recogniser's final text.
        case finishing
    }

    private(set) var phase = Phase.idle
    /// What the recogniser has heard so far in this press.
    private(set) var transcript = ""
    /// One short line for the status row after a press: "Didn't catch “…”", a permission problem.
    private(set) var message: String?

    var isActive: Bool { phase != .idle }

    private static let log = Logger(subsystem: "uz.xq.chessc", category: "voice")

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var press = 0
    @ObservationIgnored private var onText: ((String) -> Void)?
    @ObservationIgnored private var messageClear: Task<Void, Never>?

    /// Words the recogniser should favour.
    private static let vocabulary = [
        "pawn", "knight", "bishop", "rook", "queen", "king", "takes", "castle", "kingside", "queenside",
        "promote", "a", "b", "c", "d", "e", "f", "g", "h",
    ]

    /// Starts listening (finger down). `onText` gets the final transcript once, after `end()`.
    func begin(onText: @escaping (String) -> Void) async {
        guard phase == .idle else { return }
        press += 1
        let thisPress = press
        transcript = ""
        show(nil)
        self.onText = onText

        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            show("Voice moves need on-device speech, which this iPhone doesn't offer.")
            return
        }
        guard await Self.authorize() else {
            show("Allow the microphone and speech recognition in Settings to use voice.")
            return
        }
        guard press == thisPress else { return }  // released while the permission prompt was up

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.contextualStrings = Self.vocabulary
            request.taskHint = .confirmation

            // No usable input route (the mic is held by a call or another app, some Bluetooth
            // routes, a Simulator without audio input): a 0-channel or 0 Hz format makes
            // installTap raise an Objective-C exception that Swift cannot catch.
            guard session.isInputAvailable else { throw VoiceError.noInput }
            let engine = AVAudioEngine()
            try Self.installTap(on: engine.inputNode, feeding: request)
            engine.prepare()
            try engine.start()

            self.engine = engine
            self.request = request
            task = Self.recognize(request, with: recognizer) { [weak self] text, isFinal in
                Task { @MainActor in self?.heard(text, isFinal: isFinal, press: thisPress) }
            }
            phase = .listening
        } catch {
            Self.log.error("Voice start failed: \(error.localizedDescription, privacy: .public)")
            teardown()
            show("The microphone isn't available right now.")
        }
    }

    /// Finger up: stop the audio and wait (briefly) for the final text.
    func end() {
        guard phase == .listening else {
            press += 1  // cancels a begin() still waiting on permission
            return
        }
        phase = .finishing
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        let thisPress = press
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            if press == thisPress && phase == .finishing { finish() }
        }
    }

    /// Shown in the status line when a transcript did not name a legal move.
    func didNotUnderstand(_ text: String) {
        show(text.isEmpty ? "Didn't hear a move. Hold the mic and say one." : "Didn't catch “\(text)”. Try “knight to f3”.")
    }

    private func heard(_ text: String?, isFinal: Bool, press thisPress: Int) {
        guard thisPress == press, phase != .idle else { return }
        if let text { transcript = text }
        if isFinal || text == nil { finish() }
    }

    private func finish() {
        let text = transcript
        let deliver = onText
        teardown()
        deliver?(text)
    }

    private func teardown() {
        task?.cancel()
        task = nil
        if let engine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        request = nil
        onText = nil
        phase = .idle
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    private func show(_ text: String?) {
        message = text
        messageClear?.cancel()
        guard text != nil else { return }
        messageClear = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { message = nil }
        }
    }

    // MARK: Off the main actor
    // The tap and the result handler run on audio / recogniser threads; they are built in
    // nonisolated functions so they do not inherit main-actor isolation.

    enum VoiceError: Error { case noInput }

    /// Whether an input format can carry audio; anything else crashes `installTap`.
    nonisolated static func isUsable(channels: AVAudioChannelCount, sampleRate: Double) -> Bool {
        channels > 0 && sampleRate > 0
    }

    private nonisolated static func installTap(on input: AVAudioInputNode, feeding request: SFSpeechAudioBufferRecognitionRequest) throws {
        let format = input.outputFormat(forBus: 0)
        guard isUsable(channels: format.channelCount, sampleRate: format.sampleRate) else { throw VoiceError.noInput }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func recognize(
        _ request: SFSpeechAudioBufferRecognitionRequest,
        with recognizer: SFSpeechRecognizer,
        handler: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            if let result {
                handler(result.bestTranscription.formattedString, result.isFinal)
            } else if error != nil {
                handler(nil, true)
            }
        }
    }

    private nonisolated static func authorize() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { done in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
