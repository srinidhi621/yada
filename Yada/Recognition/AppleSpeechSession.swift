import AppKit
import AVFoundation
import Speech

@MainActor
final class AppleSpeechSession: RecognitionSession {
    private var audio: AudioCapture?
    private var analyzer: SpeechAnalyzer?
    private var resultTask: Task<Void, Error>?
    private var inputTask: Task<Void, Error>?
    private var sleepObserver: NSObjectProtocol?
    private var cancelled = false

    func start(locale: Locale, onResult: @escaping @MainActor (TranscriptSegment) -> Void,
               onLevel: @escaping @MainActor (Float) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        guard SpeechTranscriber.isAvailable else { throw YadaError("Apple on-device transcription is unavailable on this Mac.") }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw YadaError("This language is not supported by Apple on-device transcription. Choose another language.")
        }
        try checkCancellation()
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw YadaError("Speech language assets are missing. Use Download language in setup before recording.")
        }
        try checkCancellation()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw YadaError("Microphone access was denied. Enable Yada in System Settings → Privacy & Security → Microphone, then retry.")
            }
        default: throw YadaError("Microphone access is denied or restricted. Check System Settings → Privacy & Security → Microphone.")
        }
        try checkCancellation()
        let capture = AudioCapture()
        audio = capture
        let nativeFormat = capture.format
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else { throw YadaError("No input device is available. Connect a microphone and retry.") }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: nativeFormat) else {
            throw YadaError("No compatible local speech audio format is available.")
        }
        try checkCancellation()
        let converter = try AudioConverter(from: nativeFormat, to: format)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: format)
        try checkCancellation()
        resultTask = Task {
            do {
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    onResult(TranscriptSegment(start: result.range.start.seconds, end: result.range.end.seconds,
                                               text: String(result.text.characters), isFinal: result.isFinal))
                }
            } catch {
                if !Task.isCancelled { onFailure(SessionController.userMessage(error)) }
                throw error
            }
        }
        let stream = try capture.start()
        inputTask = Task.detached(priority: .userInitiated) {
            do {
                let converted = ConvertedAudioSequence(source: stream, converter: converter, onLevel: onLevel)
                _ = try await analyzer.analyzeSequence(converted)
                try Task.checkCancellation()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                if !Task.isCancelled { await onFailure(SessionController.userMessage(error)) }
                throw error
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in onFailure("The Mac is going to sleep. Recording was discarded; retry after waking.") }
        }
    }

    func stop() async throws {
        audio?.stop()
        removeSleepObserver()
        // Input drains first, analyzer finalizes, then the results sequence drains.
        try await inputTask?.value
        try await resultTask?.value
        audio = nil
        analyzer = nil
        inputTask = nil
        resultTask = nil
    }

    func cancel() async {
        cancelled = true
        audio?.stop()
        removeSleepObserver()
        inputTask?.cancel()
        resultTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        _ = try? await inputTask?.value
        _ = try? await resultTask?.value
        audio = nil
        analyzer = nil
        inputTask = nil
        resultTask = nil
    }

    private func checkCancellation() throws {
        try Task.checkCancellation()
        if cancelled { throw CancellationError() }
    }
    private func removeSleepObserver() {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
    }
}
