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
    case formatting = "Formatting", delivering = "Inserting", outcomeUnknown = "Check insertion"
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
    let cleanup: CleanupSettings
    private let formatter: any TextFormatting
    private(set) var outputText = ""
    private(set) var cleanedText = ""
    private(set) var formattedText: String?
    private(set) var reviewWarning = ""
    private(set) var readyToInsert = false
    private(set) var modelStatus = ""
    private(set) var formattingMS: Double?
    private var savedID: UUID?
    private var activeMode: TextMode = .raw
    private var activeReplacements: [TermReplacement] = []
    private var activeLocale = Locale.current
    private var formatTask: Task<Void, Never>?
    private var formatTimeout: Task<Void, Never>?
    var canFormat: Bool { state == .ready && !outputText.isEmpty && !readyToInsert }

    private var generation = UUID()
    private var session: (any RecognitionSession)?
    private var operation: Task<Void, Never>?
    private let makeSession: () -> any RecognitionSession
    var busy: Bool { [.preparing, .recording, .finalizing, .formatting, .delivering].contains(state) || cleaningUp }
    var canCopy: Bool { [.ready, .outcomeUnknown].contains(state) && !transcript.finalText.isEmpty }
    var canCancel: Bool { [.preparing, .recording, .finalizing].contains(state) && !cleaningUp }

    init(history: RecentTranscripts = RecentTranscripts(), cleanup: CleanupSettings = CleanupSettings(), formatter: any TextFormatting = LocalFormatter(), makeSession: @escaping () -> any RecognitionSession = { AppleSpeechSession() }) {
        self.makeSession = makeSession
        self.history = history
        self.cleanup = cleanup
        self.formatter = formatter
        modelStatus = formatter.availabilityMessage
    }

    // A running session always gets its stop key, even if setup is refreshing.
    func handleShortcut(locale: Locale, setupBusy: Bool, capture: () -> InsertionPreparation) {
        if busy {
            toggle(locale: locale)
        } else if readyToInsert {
            deliverReviewed(capture())
        } else if !setupBusy {
            toggle(locale: locale, insertion: capture())
        }
    }

    func toggle(locale: Locale, insertion: InsertionPreparation = .preview(nil)) {
        guard !cleaningUp else { return }
        switch state {
        case .preparing: cancel()
        case .recording: stop()
        case .finalizing, .formatting, .delivering: break
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
        resetTextVersions()
        activeMode = cleanup.mode
        activeReplacements = cleanup.replacements
        activeLocale = locale
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
                    guard let self, self.generation == id,
                          [.preparing, .recording, .finalizing].contains(self.state) else { return }
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
                finalizeTranscript()
                finalizationMS = Self.milliseconds(since: stopped)
                session = nil
                if activeMode.requiresReview, !outputText.isEmpty {
                    insertionTarget = nil
                    state = .ready
                    format(style: activeMode)
                    return
                }
                if let target = insertionTarget, !outputText.isEmpty {
                    await deliver(to: target, successMessage: "Inserted into your text field.")
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

    private func finalizeTranscript() {
        transcript.finish()
        let raw = transcript.finalText
        let useCleanup = activeMode != .raw
        cleanedText = useCleanup ? TextCleanup.apply(raw, replacements: activeReplacements) : raw
        outputText = cleanedText
        savedID = history.append(outputText, rawText: raw, cleanedText: useCleanup ? cleanedText : nil,
                                 transformVersion: useCleanup ? TextCleanup.version : nil)
    }

    private func deliver(to target: any InsertionTarget, successMessage: String) async {
        state = .delivering
        message = "Inserting into your text field…"
        let result = await target.insert(outputText)
        insertionTarget = nil
        switch result {
        case .inserted:
            shouldPresentPreview = false
            message = successMessage
            state = .ready
        case .notInserted(let reason):
            shouldPresentPreview = true
            message = reason
            state = .ready
        case .uncertain(let reason):
            shouldPresentPreview = true
            message = reason
            state = .outcomeUnknown
        }
    }

    func cancel() { if state == .formatting { cancelFormatting(); return }; end(state: .cancelled, message: "Cancelled. Audio and text discarded.") }
    func fail(_ message: String) { end(state: .failure, message: message) }

    private func end(state: SessionState, message: String) {
        guard !cleaningUp, self.state != .delivering, self.state != .formatting else { return }
        insertionTarget = nil
        generation = UUID()
        operation?.cancel()
        let pending = operation
        let active = session
        session = nil
        self.state = state
        self.message = message
        transcript = Transcript()
        resetTextVersions()
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
        resetTextVersions()
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
        resetTextVersions()
        outputText = entry.text
        cleanedText = entry.cleanedText ?? entry.rawText ?? entry.text
        formattedText = entry.formattedText
        if let formattedText { reviewWarning = FormatReview.warning(original: entry.rawText ?? entry.text, formatted: formattedText) }
        savedID = entry.id
        transcript.receive(TranscriptSegment(start: 0, end: 0, text: entry.rawText ?? entry.text, isFinal: true))
        transcript.finish()
        readinessMS = nil
        finalizationMS = nil
        state = .ready
        message = "Saved transcript. Review or copy it; start recording for a new one."
    }

    func refreshModelStatus() { modelStatus = formatter.availabilityMessage }

    private func resetTextVersions() {
        outputText = ""; cleanedText = ""; formattedText = nil; reviewWarning = ""
        readyToInsert = false; savedID = nil; formattingMS = nil
    }

    func format(style: TextMode) {
        guard canFormat, style.requiresReview else { return }
        readyToInsert = false
        formattedText = nil
        reviewWarning = ""
        shouldPresentPreview = true
        state = .formatting
        message = "Formatting on this Mac. Your original text is preserved."
        refreshModelStatus()
        let id = generation
        let source = cleanedText
        let started = ContinuousClock.now
        // Separate timeout task releases the UI even if the framework is slow to cancel.
        formatTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.generation == id, self.state == .formatting else { return }
            self.cancelFormatting(message: "Formatting timed out. Your original text is preserved.")
        }
        formatTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await formatter.format(source, style: style, locale: activeLocale)
                guard generation == id, state == .formatting, !Task.isCancelled else { return }
                guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw YadaError("The model returned no text. Your original text is preserved.") }
                formattedText = result
                reviewWarning = FormatReview.warning(original: transcript.finalText, formatted: result)
                formattingMS = Self.milliseconds(since: started)
                if let savedID { history.saveFormatted(id: savedID, text: result, style: style) }
                message = "Review the formatted text against Raw before using it."
            } catch {
                guard generation == id, state == .formatting, !Task.isCancelled else { return }
                message = (error as? YadaError)?.message ?? "Local formatting could not finish. The model may have refused the text or exceeded its context limit. Your original text is preserved."
            }
            formatTimeout?.cancel(); formatTimeout = nil
            formatTask = nil
            state = .ready
        }
    }

    func cancelFormatting(message: String = "Formatting cancelled. Your original text is preserved.") {
        guard state == .formatting else { return }
        generation = UUID()
        formatTask?.cancel(); formatTask = nil
        formatTimeout?.cancel(); formatTimeout = nil
        self.message = message
        state = .ready
    }

    func prepareReviewedInsertion(useFormatted: Bool) {
        guard state == .ready else { return }
        if useFormatted {
            guard let formattedText else { return }
            outputText = formattedText
        } else {
            outputText = cleanedText
        }
        readyToInsert = !outputText.isEmpty
        message = "Click the destination text field, then press your shortcut once to insert this reviewed text. No recording will start."
    }

    func accessibilityGranted() {
        guard needsAccessibility, !busy else { return }
        needsAccessibility = false
        message = canCopy ? "Text insertion is ready. Choose the text to insert below, then press your shortcut in the destination." : "Text insertion is ready. Return to your text field and press your shortcut."
        if state == .failure { state = .idle }
    }

    func discardReviewedInsertion() { readyToInsert = false; message = "Insertion cancelled. Your text remains available here." }

    private func deliverReviewed(_ preparation: InsertionPreparation) {
        readyToInsert = false
        needsAccessibility = false
        switch preparation {
        case .needsAccessibility:
            needsAccessibility = true
            message = "Allow Yada in macOS Accessibility, then choose Use reviewed text again."
            shouldPresentPreview = true
            state = .idle; state = .ready
        case .preview(let reason):
            message = reason ?? "Click an editable field outside Yada, then choose Use reviewed text again."
            shouldPresentPreview = true
            state = .idle; state = .ready
        case .target(let target):
            // Mark delivery synchronously so a second shortcut cannot start recording.
            state = .delivering
            operation = Task { await deliver(to: target, successMessage: "Inserted reviewed text.") }
        }
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
