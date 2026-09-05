import Foundation
import Observation

@MainActor
protocol RecognitionSession: AnyObject {
    func start(locale: Locale, onResult: @escaping @MainActor (TranscriptSegment) -> Void,
               onLevel: @escaping @MainActor (Float) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws
    func stop() async throws
    func cancel() async
}

enum SessionState: String {
    case idle = "Idle", preparing = "Preparing", recording = "Recording"
    case delivering = "Inserting", outcomeUnknown = "Check insertion"
    case finalizing = "Finalizing", ready = "Ready", cancelled = "Cancelled", failure = "Could not finish"
}

@MainActor @Observable
final class SessionController {
    private(set) var state: SessionState = .idle
    private(set) var transcript = Transcript()
    private(set) var message = "Choose a shortcut and check the speech language to begin."
    private(set) var level: Float = 0
    private(set) var readinessMS: Double?
    private(set) var finalizationMS: Double?
    private(set) var cleaningUp = false
    private(set) var shouldPresentPreview = true
    private(set) var needsAccessibility = false
    private var insertionTarget: (any InsertionTarget)?
    private var previewReason: String?
    let history: RecentTranscripts
    private var generation = UUID()
    private var session: (any RecognitionSession)?
    private var operation: Task<Void, Never>?
    private let makeSession: () -> any RecognitionSession
    var busy: Bool { [.preparing, .recording, .finalizing, .delivering].contains(state) || cleaningUp }
    var canCopy: Bool { [.ready, .outcomeUnknown].contains(state) && !transcript.finalText.isEmpty }
    var canCancel: Bool { [.preparing, .recording, .finalizing].contains(state) && !cleaningUp }

    init(history: RecentTranscripts = RecentTranscripts(), makeSession: @escaping () -> any RecognitionSession = { AppleSpeechSession() }) {
        self.makeSession = makeSession
        self.history = history
    }

    // A running session always gets its stop key, even if setup is refreshing.
    func handleShortcut(locale: Locale, setupBusy: Bool, capture: () -> InsertionPreparation) {
        if busy {
            toggle(locale: locale)
        } else if !setupBusy {
            toggle(locale: locale, insertion: capture())
        }
    }

    func toggle(locale: Locale, insertion: InsertionPreparation = .preview(nil)) {
        guard !cleaningUp else { return }
        switch state {
        case .preparing: cancel()
        case .recording: stop()
        case .finalizing, .delivering: break
        default: start(locale: locale, insertion: insertion)
        }
    }

    private func start(locale: Locale, insertion: InsertionPreparation) {
        insertionTarget = nil
        previewReason = nil
        shouldPresentPreview = true
        needsAccessibility = false
        switch insertion {
        case .target(let target): insertionTarget = target
        case .preview(let reason): previewReason = reason
        case .needsAccessibility:
            needsAccessibility = true
            state = .failure
            message = "Allow Yada in macOS Accessibility once, then return to your text field and press your shortcut again. No recording has started."
            return
        }
        let id = UUID()
        generation = id
        transcript = Transcript()
        readinessMS = nil
        finalizationMS = nil
        level = 0
        state = .preparing
        message = "Preparing local recognition. Wait for Recording before speaking."
        let active = makeSession()
        session = active
        let started = ContinuousClock.now
        operation = Task {
            do {
                try await active.start(locale: locale, onResult: { [weak self] result in
                    guard let self, self.generation == id,
                          [.preparing, .recording, .finalizing].contains(self.state) else { return }
                    self.transcript.receive(result)
                }, onLevel: { [weak self] value in
                    guard let self, self.generation == id, self.state == .recording else { return }
                    self.level = value
                }, onFailure: { [weak self] message in
                    guard let self, self.generation == id else { return }
                    self.fail(message)
                })
                guard generation == id, state == .preparing else { return }
                readinessMS = Self.milliseconds(since: started)
                state = .recording
                message = "Recording — speak now. Stop to finalize, or Cancel to discard."
            } catch {
                guard generation == id else { return }
                fail(Self.userMessage(error))
            }
        }
    }

    func stop() {
        guard state == .recording, let active = session else { return }
        state = .finalizing
        level = 0
        message = "Finishing the last words…"
        let id = generation
        let stopped = ContinuousClock.now
        operation = Task {
            do {
                try await active.stop()
                guard generation == id, state == .finalizing else { return }
                transcript.finish()
                history.append(transcript.finalText)
                finalizationMS = Self.milliseconds(since: stopped)
                session = nil
                if let target = insertionTarget, !transcript.finalText.isEmpty {
                    state = .delivering
                    message = "Inserting into your text field…"
                    let result = await target.insert(transcript.finalText)
                    insertionTarget = nil
                    switch result {
                    case .inserted:
                        shouldPresentPreview = false
                        message = "Inserted into your text field."
                        state = .ready
                    case .notInserted(let reason):
                        message = reason
                        state = .ready
                    case .uncertain(let reason):
                        message = reason
                        state = .outcomeUnknown
                    }
                } else {
                    insertionTarget = nil
                    message = transcript.finalText.isEmpty ? "No speech was finalized. Nothing to copy." : (previewReason ?? "Finalized. Review the text, then choose Copy.")
                    state = .ready
                }
            } catch {
                guard generation == id else { return }
                fail(Self.userMessage(error))
            }
        }
    }

    func cancel() { end(state: .cancelled, message: "Cancelled. Audio and text discarded.") }
    func fail(_ message: String) { end(state: .failure, message: message) }

    private func end(state: SessionState, message: String) {
        guard !cleaningUp, self.state != .delivering else { return }
        insertionTarget = nil
        generation = UUID()
        operation?.cancel()
        let pending = operation
        let active = session
        session = nil
        self.state = state
        self.message = message
        transcript = Transcript()
        level = 0
        cleaningUp = active != nil
        operation = Task {
            await active?.cancel()
            await pending?.value
            cleaningUp = false
        }
    }

    func clear() {
        guard !busy else { return }
        generation = UUID()
        insertionTarget = nil
        needsAccessibility = false
        shouldPresentPreview = true
        transcript = Transcript()
        state = .idle
        message = "Current-session text cleared."
    }

    func showSaved(_ entry: SavedTranscript) {
        guard !busy else { return }
        shouldPresentPreview = true
        needsAccessibility = false
        // Notify the presentation observer even when replacing an already-ready preview.
        state = .idle
        generation = UUID()
        transcript = Transcript()
        transcript.receive(TranscriptSegment(start: 0, end: 0, text: entry.text, isFinal: true))
        transcript.finish()
        readinessMS = nil
        finalizationMS = nil
        state = .ready
        message = "Saved transcript. Review or copy it; start recording for a new one."
    }

    static func userMessage(_ error: Error) -> String {
        (error as? YadaError)?.message ?? "Local speech processing failed. Check the input device and installed language, then retry."
    }
    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: .now).components
        return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
    }
}

struct YadaError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
