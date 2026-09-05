import XCTest
import AVFoundation
import Speech
@testable import Yada

final class TranscriptTests: XCTestCase {
    func segment(_ start: Double, _ end: Double, _ text: String, final: Bool = false) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text, isFinal: final)
    }
    func testRepeatedProvisionalRevisionsAndFinalReplacement() {
        var transcript = Transcript()
        transcript.receive(segment(0, 1, "I"))
        transcript.receive(segment(0, 2, "I wood"))
        transcript.receive(segment(0, 3, "I would like"))
        XCTAssertEqual(transcript.preview, "I would like")
        transcript.receive(segment(0, 3, "I would like.", final: true))
        XCTAssertEqual(transcript.finalText, "I would like.")
    }
    func testMultipleFinalSegmentsPreserveRawWhitespaceAndIgnoreLateResults() {
        var transcript = Transcript()
        transcript.receive(segment(0, 1, "Hello.", final: true))
        transcript.receive(segment(1, 2, "  Next line!", final: true))
        transcript.receive(segment(0, 1, "Wrong"))
        transcript.receive(segment(0, 1, "Duplicate", final: true))
        XCTAssertEqual(transcript.finalText, "Hello.  Next line!")
        transcript.finish()
        transcript.receive(segment(2, 3, " Late", final: true))
        XCTAssertEqual(transcript.preview, "Hello.  Next line!")
    }
    func testEmptyAndUnfinalizedAudioNeverBecomeFinalText() {
        var transcript = Transcript()
        XCTAssertEqual(transcript.finalText, "")
        transcript.receive(segment(0, 1, "Maybe"))
        transcript.finish()
        XCTAssertEqual(transcript.preview, "")
    }
    func testFinalRangeReplacesOverlappingProvisionalSegments() {
        var transcript = Transcript()
        transcript.receive(segment(0, 1, "one"))
        transcript.receive(segment(1, 2, " two"))
        transcript.receive(segment(0, 2, "One two.", final: true))
        XCTAssertEqual(transcript.preview, "One two.")
    }
}

@MainActor
final class FakeRecognition: RecognitionSession {
    var onResult: (@MainActor (TranscriptSegment) -> Void)?
    var onFailure: (@MainActor (String) -> Void)?
    var onLevel: (@MainActor (Float) -> Void)?
    var started = false
    var cancelled = false
    var stopped = false
    var prepareGate: CheckedContinuation<Void, Never>?
    var stopGate: CheckedContinuation<Void, Never>?
    var holdPreparation = false
    var holdStop = false
    var holdCancel = false
    var cancelGate: CheckedContinuation<Void, Never>?
    func start(locale: Locale, onResult: @escaping @MainActor (TranscriptSegment) -> Void,
               onLevel: @escaping @MainActor (Float) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        self.onResult = onResult
        self.onFailure = onFailure
        self.onLevel = onLevel
        started = true
        if holdPreparation { await withCheckedContinuation { prepareGate = $0 } }
    }
    func stop() async throws {
        stopped = true
        if holdStop { await withCheckedContinuation { stopGate = $0 } }
        onResult?(TranscriptSegment(start: 0, end: 1, text: "Final words.", isFinal: true))
    }
    func cancel() async {
        cancelled = true
        if holdCancel { await withCheckedContinuation { cancelGate = $0 } }
        prepareGate?.resume(); prepareGate = nil
        stopGate?.resume(); stopGate = nil
    }
}

@MainActor
final class LifecycleTests: XCTestCase {
    let locale = Locale(identifier: "en-US")
    func waitUntil(_ condition: @escaping @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Expected lifecycle transition did not occur", file: file, line: line)
    }
    func testStopDrainsFinalResultsBeforeCopyIsAllowed() async {
        let fake = FakeRecognition(); fake.holdStop = true
        let controller = SessionController { fake }
        controller.toggle(locale: locale)
        await waitUntil { controller.state == .recording }
        controller.stop()
        await waitUntil { fake.stopGate != nil }
        XCTAssertEqual(controller.state, .finalizing)
        XCTAssertFalse(controller.canCopy)
        controller.toggle(locale: locale)
        XCTAssertEqual(controller.state, .finalizing)
        fake.stopGate?.resume(); fake.stopGate = nil
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(controller.transcript.finalText, "Final words.")
        XCTAssertTrue(controller.canCopy)
    }
    func testRapidToggleDuringPreparationCancelsAndDoesNotStartAgain() async {
        let fake = FakeRecognition(); fake.holdPreparation = true
        let controller = SessionController { fake }
        controller.toggle(locale: locale)
        await waitUntil { fake.prepareGate != nil }
        controller.toggle(locale: locale)
        controller.toggle(locale: locale)
        await waitUntil { !controller.cleaningUp }
        XCTAssertEqual(controller.state, .cancelled)
        XCTAssertTrue(fake.cancelled)
        XCTAssertFalse(controller.canCopy)
    }
    func testStaleCallbacksCannotAffectNewSession() async {
        let first = FakeRecognition(), second = FakeRecognition()
        var sessions = [first, second]
        let controller = SessionController { sessions.removeFirst() }
        controller.toggle(locale: locale)
        await waitUntil { controller.state == .recording }
        controller.cancel()
        await waitUntil { !controller.cleaningUp }
        controller.toggle(locale: locale)
        await waitUntil { controller.state == .recording }
        first.onResult?(TranscriptSegment(start: 0, end: 1, text: "Old", isFinal: true))
        first.onFailure?("Old failure")
        XCTAssertEqual(controller.transcript.preview, "")
        XCTAssertEqual(controller.state, .recording)
        controller.stop()
        await waitUntil { controller.state == .ready }
    }
    func testCancellationDuringFinalizationDiscardsLateFinalText() async {
        let fake = FakeRecognition(); fake.holdStop = true
        let controller = SessionController { fake }
        controller.toggle(locale: locale)
        await waitUntil { controller.state == .recording }
        controller.stop()
        await waitUntil { fake.stopGate != nil }
        controller.cancel()
        await waitUntil { !controller.cleaningUp }
        XCTAssertEqual(controller.state, .cancelled)
        XCTAssertEqual(controller.transcript.preview, "")
        XCTAssertFalse(controller.canCopy)
    }
    func testRepeatedCancelCannotReleaseCleanupGateEarly() async {
        let fake = FakeRecognition(); fake.holdCancel = true
        var created = 0
        let controller = SessionController { created += 1; return fake }
        controller.toggle(locale: locale)
        await waitUntil { controller.state == .recording }
        controller.cancel()
        await waitUntil { fake.cancelGate != nil }
        controller.cancel()
        controller.toggle(locale: locale)
        XCTAssertTrue(controller.cleaningUp)
        XCTAssertEqual(created, 1)
        fake.cancelGate?.resume(); fake.cancelGate = nil
        await waitUntil { !controller.cleaningUp }
        XCTAssertEqual(controller.state, .cancelled)
    }

    func testRepeatedStartStopAndRecoverableFailure() async {
        var latest = FakeRecognition()
        let controller = SessionController { latest = FakeRecognition(); return latest }
        for _ in 0..<3 {
            controller.toggle(locale: locale)
            await waitUntil { controller.state == .recording }
            controller.stop()
            await waitUntil { controller.state == .ready }
            XCTAssertEqual(controller.transcript.finalText, "Final words.")
        }
        controller.toggle(locale: locale)
        await waitUntil { controller.state == .recording }
        latest.onFailure?("Microphone disconnected")
        await waitUntil { !controller.cleaningUp }
        XCTAssertEqual(controller.state, .failure)
        XCTAssertFalse(controller.canCopy)
        controller.toggle(locale: locale)
        await waitUntil { controller.state == .recording }
        controller.cancel()
        await waitUntil { !controller.cleaningUp }
    }
}

final class AudioConversionTests: XCTestCase {
    func testResamplerDrainsTailAndFinishesOnce() throws {
        let source = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false))
        let converter = try AudioConverter(from: source, to: target)
        var frames = 0
        for _ in 0..<10 {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 1024))
            buffer.frameLength = 1024
            for i in 0..<1024 { buffer.floatChannelData![0][i] = 0.2 }
            frames += Int(try converter.convert(AnalyzerInput(buffer: buffer)).buffer.frameLength)
        }
        let beforeDrain = frames
        var reachedEnd = false
        for _ in 0..<10 {
            guard let tail = try converter.finish() else { reachedEnd = true; break }
            frames += Int(tail.buffer.frameLength)
        }
        XCTAssertTrue(reachedEnd)
        XCTAssertGreaterThan(frames, beforeDrain, "Residual samples must reach recognition before finalization")
        XCTAssertGreaterThanOrEqual(frames, 3413)
        XCTAssertLessThan(frames, 3500)
        XCTAssertNil(try converter.finish())
    }
    func testMeterReadsIntegerAndFloatAudio() throws {
        for type in [AVAudioCommonFormat.pcmFormatFloat32, .pcmFormatInt16] {
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: type, sampleRate: 16000, channels: 1, interleaved: false))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
            buffer.frameLength = 1
            buffer.floatChannelData?[0][0] = 0.125
            buffer.int16ChannelData?[0][0] = 4096
            XCTAssertEqual(AudioConverter.peak(buffer), 0.5, accuracy: 0.01)
        }
    }
    func testEmptyConvertedStreamEndsWithoutAudio() async throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let pair = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
        pair.continuation.finish()
        let converter = try AudioConverter(from: format, to: format)
        var iterator = ConvertedAudioSequence(source: pair.stream, converter: converter, onLevel: { _ in }).makeAsyncIterator()
        let result = try await iterator.next()
        XCTAssertNil(result)
    }
}

@MainActor
final class HistoryTests: XCTestCase {
    func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "yada-history-test-\(UUID().uuidString)/history.json")
    }
    func testRoundTripPreservesTextAndSupportsDeletion() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let history = RecentTranscripts(fileURL: file)
        history.append("  Synthetic text.\nExact whitespace.  ")
        history.append("Second synthetic entry.")
        let loaded = RecentTranscripts(fileURL: file)
        XCTAssertEqual(loaded.entries, history.entries)
        XCTAssertEqual(loaded.entries.last?.text, "  Synthetic text.\nExact whitespace.  ")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
        loaded.delete(id: loaded.entries[0].id)
        XCTAssertEqual(RecentTranscripts(fileURL: file).entries.count, 1)
        loaded.clear()
        XCTAssertTrue(RecentTranscripts(fileURL: file).entries.isEmpty)
    }
    func testBoundedHistoryAndEmptyResults() {
        let history = RecentTranscripts()
        history.append("")
        XCTAssertTrue(history.entries.isEmpty)
        for i in 0..<60 { history.append("Synthetic \(i)") }
        XCTAssertEqual(history.entries.count, 50)
        XCTAssertEqual(history.entries.first?.text, "Synthetic 59")
        XCTAssertEqual(history.entries.last?.text, "Synthetic 10")
    }
    func testUnreadableHistoryIsPreservedUntilExplicitClear() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("invalid synthetic fixture".utf8)
        try original.write(to: file)
        let history = RecentTranscripts(fileURL: file)
        XCTAssertNotNil(history.errorMessage)
        history.append("Must not overwrite damaged history")
        XCTAssertEqual(try Data(contentsOf: file), original)
        history.clear()
        history.append("New synthetic entry")
        XCTAssertEqual(RecentTranscripts(fileURL: file).entries.count, 1)
    }
    func testSaveFailureDoesNotClaimSuccess() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let history = RecentTranscripts(fileURL: file.appending(path: "blocked/record.json"))
        try Data().write(to: file.appending(path: "blocked"))
        history.append("Synthetic")
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertNotNil(history.errorMessage)
    }
    func testOnlyCompletedSessionsAreSavedAndRecallDoesNotDuplicate() async {
        let history = RecentTranscripts()
        let controller = SessionController(history: history) { FakeRecognition() }
        let locale = Locale(identifier: "en-US")
        controller.toggle(locale: locale)
        for _ in 0..<1000 where controller.state != .recording { await Task.yield() }
        controller.cancel()
        for _ in 0..<1000 where controller.cleaningUp { await Task.yield() }
        XCTAssertTrue(history.entries.isEmpty)
        controller.toggle(locale: locale)
        for _ in 0..<1000 where controller.state != .recording { await Task.yield() }
        controller.stop()
        for _ in 0..<1000 where controller.state != .ready { await Task.yield() }
        XCTAssertEqual(history.entries.count, 1)
        if let entry = history.entries.first { controller.showSaved(entry) }
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(controller.transcript.finalText, "Final words.")
        controller.clear()
        XCTAssertEqual(history.entries.count, 1)
    }
    func testPillCannotTakeKeyboardFocusAndHidesAfterCancel() async throws {
        let fake = FakeRecognition()
        let controller = SessionController { fake }
        let pill = RecordingPill()
        controller.toggle(locale: Locale(identifier: "en-US"))
        for _ in 0..<1000 where controller.state != .recording { await Task.yield() }
        pill.update(controller: controller)
        let panel = try XCTUnwrap(pill.panel)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.isVisible)
        fake.onLevel?(0.7)
        // Render only this synthetic panel's view, never the user's screen or transcripts.
        await Task.yield()
        let view = try XCTUnwrap(panel.contentView)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        try png.write(to: root.appending(path: ".build/pill-preview.png"))
        controller.cancel()
        pill.update(controller: controller)
        XCTAssertFalse(panel.isVisible)
        for _ in 0..<1000 where controller.cleaningUp { await Task.yield() }
    }
}

@MainActor
private final class FakeInsertionTarget: InsertionTarget {
    var calls: [String] = []
    var result: InsertionResult = .inserted
    var gate: CheckedContinuation<Void, Never>?
    var hold = false
    func insert(_ text: String) async -> InsertionResult {
        calls.append(text)
        if hold { await withCheckedContinuation { gate = $0 } }
        return result
    }
}

@MainActor
final class InsertionTests: XCTestCase {
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Expected transition did not occur")
    }

    func testInsertionRunsOnlyAfterFinalizationAndDoesNotPresentWindow() async {
        let recognition = FakeRecognition(); recognition.holdStop = true
        let insertion = FakeInsertionTarget()
        let controller = SessionController { recognition }
        controller.toggle(locale: Locale(identifier: "en-US"), insertion: .target(insertion))
        await waitUntil { controller.state == .recording }
        XCTAssertTrue(insertion.calls.isEmpty)
        controller.stop()
        await waitUntil { recognition.stopGate != nil }
        XCTAssertTrue(insertion.calls.isEmpty)
        recognition.stopGate?.resume(); recognition.stopGate = nil
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(insertion.calls, ["Final words."])
        XCTAssertFalse(controller.shouldPresentPreview)
        XCTAssertTrue(controller.canCopy)
    }

    func testCancelledFinalizationNeverInserts() async {
        let recognition = FakeRecognition(); recognition.holdStop = true
        let insertion = FakeInsertionTarget()
        let controller = SessionController { recognition }
        controller.toggle(locale: Locale(identifier: "en-US"), insertion: .target(insertion))
        await waitUntil { controller.state == .recording }
        controller.stop()
        await waitUntil { recognition.stopGate != nil }
        controller.cancel()
        await waitUntil { !controller.cleaningUp }
        XCTAssertTrue(insertion.calls.isEmpty)
        XCTAssertEqual(controller.state, .cancelled)
    }

    func testAmbiguousPasteIsNotRetriedAndKeepsPreview() async {
        let insertion = FakeInsertionTarget(); insertion.hold = true
        insertion.result = .uncertain("Check insertion")
        let controller = SessionController { FakeRecognition() }
        controller.toggle(locale: Locale(identifier: "en-US"), insertion: .target(insertion))
        await waitUntil { controller.state == .recording }
        controller.stop()
        await waitUntil { insertion.gate != nil }
        XCTAssertEqual(controller.state, .delivering)
        XCTAssertFalse(controller.canCancel)
        controller.cancel()
        controller.fail("Late recognition failure")
        controller.toggle(locale: Locale(identifier: "en-US"))
        XCTAssertEqual(controller.state, .delivering)
        XCTAssertEqual(insertion.calls.count, 1)
        insertion.gate?.resume(); insertion.gate = nil
        await waitUntil { controller.state == .outcomeUnknown }
        XCTAssertTrue(controller.shouldPresentPreview)
        XCTAssertTrue(controller.canCopy)
        XCTAssertEqual(insertion.calls.count, 1)
    }

    func testChangedTargetReturnsFinalTextForManualCopy() async {
        let insertion = FakeInsertionTarget(); insertion.result = .notInserted("Target changed")
        let controller = SessionController { FakeRecognition() }
        controller.toggle(locale: Locale(identifier: "en-US"), insertion: .target(insertion))
        await waitUntil { controller.state == .recording }
        controller.stop()
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(controller.message, "Target changed")
        XCTAssertTrue(controller.shouldPresentPreview)
        XCTAssertTrue(controller.canCopy)
    }

    func testShortcutStartsThenStopsAndInsertsWithoutRecapturingTarget() async {
        let recognition = FakeRecognition()
        let insertion = FakeInsertionTarget()
        let controller = SessionController { recognition }
        var captures = 0
        let capture: () -> InsertionPreparation = { captures += 1; return .target(insertion) }
        controller.handleShortcut(locale: Locale(identifier: "en-US"), setupBusy: false, capture: capture)
        await waitUntil { controller.state == .recording }
        controller.handleShortcut(locale: Locale(identifier: "en-US"), setupBusy: true, capture: capture)
        controller.handleShortcut(locale: Locale(identifier: "en-US"), setupBusy: false, capture: capture)
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(captures, 1)
        XCTAssertEqual(insertion.calls, ["Final words."])
        XCTAssertFalse(controller.shouldPresentPreview)
    }

    func testOfficeEditorsUsePasteWithoutRequiringWritableSelectedText() {
        for app in ["com.microsoft.Outlook", "com.microsoft.teams2", "com.microsoft.teams"] {
            XCTAssertEqual(FieldDelivery.choose(bundleID: app, selectedTextSettable: false), .paste)
            XCTAssertEqual(FieldDelivery.choose(bundleID: app, selectedTextSettable: true), .paste)
        }
        XCTAssertEqual(FieldDelivery.choose(bundleID: "com.apple.TextEdit", selectedTextSettable: true), .selectedText)
        XCTAssertNil(FieldDelivery.choose(bundleID: "unknown", selectedTextSettable: false))
    }

    func testMissingPermissionDoesNotStartMicrophone() {
        var created = false
        let controller = SessionController { created = true; return FakeRecognition() }
        controller.toggle(locale: Locale(identifier: "en-US"), insertion: .needsAccessibility)
        XCTAssertFalse(created)
        XCTAssertTrue(controller.needsAccessibility)
        XCTAssertEqual(controller.state, .failure)
    }

    func testUnicodeSelectionReplacementAndEditedFieldRejection() throws {
        let before = "A🙂 café Z"
        let range = (before as NSString).range(of: "café")
        let snapshot = try XCTUnwrap(FieldSnapshot(text: before, selection: range))
        XCTAssertEqual(snapshot.expectedText(before: before, inserting: "नमस्ते"), "A🙂 नमस्ते Z")
        XCTAssertNil(snapshot.expectedText(before: "Changed document", inserting: "text"))
        XCTAssertNotEqual(snapshot, FieldSnapshot(text: before, selection: NSRange(location: 0, length: 0)))
        XCTAssertNil(FieldSnapshot(text: before, selection: NSRange(location: NSNotFound, length: 0)))
        XCTAssertNil(FieldSnapshot(text: before, selection: NSRange(location: 1, length: Int.max)))
    }

}
