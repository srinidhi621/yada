import XCTest
import SwiftUI
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
        XCTAssertEqual(FieldDelivery.choose(bundleID: "unknown", selectedTextSettable: false), .paste)
    }

    func testMicrosoftPasteCannotBypassSecureDisabledOrNonTextFields() {
        let bundle = "com.microsoft.teams2"
        XCTAssertEqual(FieldDelivery.assess(bundleID: bundle, role: "AXTextField", subrole: "AXSecureTextField", enabled: true, selectedTextSettable: true), .failure(.secure))
        XCTAssertEqual(FieldDelivery.assess(bundleID: bundle, role: "AXTextArea", subrole: nil, enabled: false, selectedTextSettable: false), .failure(.disabled))
        XCTAssertEqual(FieldDelivery.assess(bundleID: bundle, role: "AXButton", subrole: nil, enabled: true, selectedTextSettable: true), .failure(.notText))
        XCTAssertEqual(FieldDelivery.assess(bundleID: bundle, role: nil, subrole: nil, enabled: nil, selectedTextSettable: false), .failure(.notText))
        XCTAssertEqual(FieldDelivery.assess(bundleID: bundle, role: "AXTextArea", subrole: nil, enabled: true, selectedTextSettable: false), .success(.paste))
    }

    func testNonWritableTextEditorUsesPasteButNonTextControlIsRejected() {
        XCTAssertEqual(FieldDelivery.assess(bundleID: "web.editor", role: "AXTextArea", subrole: nil, enabled: true, selectedTextSettable: false), .success(.paste))
        XCTAssertEqual(FieldDelivery.assess(bundleID: "web.editor", role: "AXButton", subrole: nil, enabled: true, selectedTextSettable: false), .failure(.notText))
        XCTAssertEqual(FieldDelivery.assess(bundleID: "native.editor", role: "AXTextArea", subrole: nil, enabled: nil, selectedTextSettable: true), .success(.selectedText))
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

final class CleanupTests: XCTestCase {
    func testSpacingKeepsMeaningQuotesCodeAndLineBreaks() {
        let raw = "I  do not agree.\nPay  1,200 on  12/09. Say \"two  spaces\" and `let  x = 2`.\n    code  stays"
        XCTAssertEqual(TextCleanup.apply(raw, replacements: []), "I do not agree.\nPay 1,200 on 12/09. Say \"two  spaces\" and `let  x = 2`.\n    code  stays")
        let clean = "Well, I actually like this. Tuesday, sorry, Thursday."
        XCTAssertEqual(TextCleanup.apply(clean, replacements: []), clean)
    }
    func testTermsRespectCaseBoundariesQuotesAndDoNotCascade() {
        let terms = [TermReplacement(source: "yada", replacement: "Yada"), TermReplacement(source: "Yada", replacement: "Wrong"), TermReplacement(source: "cafe", replacement: "café")]
        XCTAssertEqual(TextCleanup.apply("yada yadax _yada YADA cafe \"yada\" `yada`", replacements: terms), "Yada yadax _yada YADA café \"yada\" `yada`")
    }
    func testTermBoundariesPreserveCombiningMarks() {
        let terms = [TermReplacement(source: "cafe", replacement: "coffee")]
        XCTAssertEqual(TextCleanup.apply("cafe cafe\u{301} \u{301}cafe café", replacements: terms),
                       "coffee cafe\u{301} \u{301}cafe café")
        XCTAssertEqual(TextCleanup.apply("cafe\u{301}", replacements: [TermReplacement(source: "cafe\u{301}", replacement: "coffee")]), "coffee")
    }

    func testModelNumberWarningIsNotAnEquivalenceClaim() {
        XCTAssertTrue(FormatReview.warning(original: "Pay 120", formatted: "Pay 200").contains("Numbers"))
        XCTAssertTrue(FormatReview.warning(original: "Do not pay 120", formatted: "Pay 120").contains("meaning"))
    }
}

@MainActor
private final class FakeFormatter: TextFormatting {
    var availabilityMessage = "Synthetic formatter"
    var output = "Formatted words."
    var failure: Error?
    var calls: [String] = []
    var hold = false
    var gate: CheckedContinuation<Void, Never>?
    func format(_ text: String, style: TextMode, locale: Locale) async throws -> String {
        calls.append(text)
        if hold { await withCheckedContinuation { gate = $0 } }
        if let failure { throw failure }
        return output
    }
}

@MainActor
final class TextProcessingTests: XCTestCase {
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<2000 { if condition() { return }; await Task.yield() }
        XCTFail("Expected text processing transition")
    }
    func testCleanIsAppliedBeforeInsertionAndRawIsSaved() async {
        let settings = CleanupSettings(); settings.setMode(.clean)
        settings.add(source: "Final", replacement: "Corrected")
        let target = FakeInsertionTarget()
        let controller = SessionController(cleanup: settings, formatter: FakeFormatter()) { FakeRecognition() }
        controller.toggle(locale: Locale(identifier: "en-US"), insertion: .target(target))
        await waitUntil { controller.state == .recording }
        // Mid-session changes cannot alter this session's corrections.
        settings.delete("Final")
        controller.stop()
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(target.calls, ["Corrected words."])
        XCTAssertEqual(controller.transcript.finalText, "Final words.")
        XCTAssertEqual(controller.history.entries.first?.rawText, "Final words.")
        XCTAssertEqual(controller.history.entries.first?.cleanedText, "Corrected words.")
        XCTAssertEqual(controller.history.entries.first?.transformVersion, TextCleanup.version)
    }
    func testRawBypassesReplacementsAndModel() async {
        let settings = CleanupSettings(); settings.setMode(.raw); settings.add(source: "Final", replacement: "Changed")
        let formatter = FakeFormatter()
        let controller = SessionController(cleanup: settings, formatter: formatter) { FakeRecognition() }
        controller.toggle(locale: Locale(identifier: "en-US"))
        await waitUntil { controller.state == .recording }; controller.stop()
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(controller.outputText, "Final words.")
        XCTAssertTrue(formatter.calls.isEmpty)
    }
    func testFormattingRequiresReviewThenFreshTargetAndNeverRecordsOnInsert() async {
        let settings = CleanupSettings(); settings.setMode(.bullets)
        let formatter = FakeFormatter()
        let originalTarget = FakeInsertionTarget(), reviewedTarget = FakeInsertionTarget()
        var sessions = 0
        let controller = SessionController(cleanup: settings, formatter: formatter) { sessions += 1; return FakeRecognition() }
        controller.toggle(locale: Locale(identifier: "en-US"), insertion: .target(originalTarget))
        await waitUntil { controller.state == .recording }; controller.stop()
        await waitUntil { controller.formattedText != nil && controller.state == .ready }
        XCTAssertTrue(originalTarget.calls.isEmpty)
        XCTAssertEqual(controller.outputText, "Final words.")
        XCTAssertEqual(controller.history.entries.first?.formattedText, formatter.output)
        controller.prepareReviewedInsertion(useFormatted: true)
        controller.handleShortcut(locale: Locale(identifier: "en-US"), setupBusy: false, capture: { .target(reviewedTarget) })
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(reviewedTarget.calls, [formatter.output])
        XCTAssertEqual(sessions, 1)
        XCTAssertFalse(controller.readyToInsert)
        controller.prepareReviewedInsertion(useFormatted: false)
        XCTAssertEqual(controller.outputText, "Final words.")
    }
    func testModelFailureKeepsRawAndDoesNotAutoInsert() async {
        let settings = CleanupSettings(); settings.setMode(.email)
        let formatter = FakeFormatter(); formatter.failure = YadaError("Model unavailable")
        let target = FakeInsertionTarget()
        let controller = SessionController(cleanup: settings, formatter: formatter) { FakeRecognition() }
        controller.toggle(locale: Locale(identifier: "en-US"), insertion: .target(target))
        await waitUntil { controller.state == .recording }; controller.stop()
        await waitUntil { controller.message == "Model unavailable" }
        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(controller.outputText, "Final words.")
        XCTAssertNil(controller.formattedText)
        XCTAssertTrue(target.calls.isEmpty)
    }
    func testCancelledModelCannotOverwriteNewSession() async {
        let settings = CleanupSettings(); settings.setMode(.prose)
        let formatter = FakeFormatter(); formatter.hold = true
        let controller = SessionController(cleanup: settings, formatter: formatter) { FakeRecognition() }
        controller.toggle(locale: Locale(identifier: "en-US"))
        await waitUntil { controller.state == .recording }; controller.stop()
        await waitUntil { formatter.gate != nil }
        controller.cancelFormatting()
        XCTAssertEqual(controller.outputText, "Final words.")
        settings.setMode(.raw)
        controller.toggle(locale: Locale(identifier: "en-US"))
        await waitUntil { controller.state == .recording }
        formatter.gate?.resume(); formatter.gate = nil
        await Task.yield()
        XCTAssertNil(controller.formattedText)
        XCTAssertEqual(controller.state, .recording)
        controller.cancel()
        await waitUntil { !controller.cleaningUp }
    }
    func testFormattingTimeoutKeepsTextAndIgnoresLateResult() async throws {
        let settings = CleanupSettings(); settings.setMode(.prose)
        let formatter = FakeFormatter(); formatter.hold = true
        let controller = SessionController(cleanup: settings, formatter: formatter) { FakeRecognition() }
        controller.toggle(locale: .current)
        await waitUntil { controller.state == .recording }; controller.stop()
        await waitUntil { formatter.gate != nil }
        for _ in 0..<350 {
            if controller.state == .ready { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(controller.state, .ready)
        XCTAssertTrue(controller.message.contains("timed out"))
        XCTAssertEqual(controller.outputText, "Final words.")
        formatter.gate?.resume(); formatter.gate = nil
        await Task.yield()
        XCTAssertNil(controller.formattedText)
    }

    func testLateRecognitionFailurePreservesFinalizedText() async {
        let recognition = FakeRecognition()
        let controller = SessionController(formatter: FakeFormatter()) { recognition }
        controller.toggle(locale: .current)
        await waitUntil { controller.state == .recording }
        controller.stop()
        await waitUntil { controller.state == .ready }
        recognition.onFailure?("Late recognition failure")
        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(controller.transcript.finalText, "Final words.")
        XCTAssertEqual(controller.outputText, "Final words.")
        XCTAssertEqual(controller.history.entries.count, 1)
        XCTAssertEqual(controller.history.entries.first?.text, "Final words.")
        XCTAssertTrue(controller.canCopy)
    }

    func testReviewedInsertionFallbackPresentsPreviouslyHiddenPreview() async {
        let target = FakeInsertionTarget()
        let controller = SessionController(formatter: FakeFormatter()) { FakeRecognition() }
        controller.toggle(locale: .current, insertion: .target(target))
        await waitUntil { controller.state == .recording }
        controller.stop()
        await waitUntil { controller.state == .ready }
        XCTAssertFalse(controller.shouldPresentPreview)
        controller.prepareReviewedInsertion(useFormatted: false)
        controller.handleShortcut(locale: .current, setupBusy: false, capture: { .preview("Unsupported field") })
        XCTAssertEqual(controller.state, .ready)
        XCTAssertTrue(controller.shouldPresentPreview)
        XCTAssertEqual(controller.message, "Unsupported field")
        XCTAssertEqual(controller.outputText, "Final words.")
        XCTAssertEqual(target.calls, ["Final words."])
        XCTAssertFalse(controller.readyToInsert)
    }

    func testAutomaticAndReviewedDeliveryShareResultHandling() async {
        let cases: [(InsertionResult, SessionState, Bool)] = [
            (.inserted, .ready, false),
            (.notInserted("Changed field"), .ready, true),
            (.uncertain("Check destination"), .outcomeUnknown, true)
        ]
        for (result, state, preview) in cases {
            for reviewed in [false, true] {
                let target = FakeInsertionTarget(); target.result = result
                let controller = SessionController(formatter: FakeFormatter()) { FakeRecognition() }
                if reviewed {
                    controller.showSaved(SavedTranscript(id: UUID(), createdAt: .now, text: "Saved words."))
                    controller.prepareReviewedInsertion(useFormatted: false)
                    controller.handleShortcut(locale: .current, setupBusy: false, capture: { .target(target) })
                } else {
                    controller.toggle(locale: .current, insertion: .target(target))
                    await waitUntil { controller.state == .recording }
                    controller.stop()
                }
                await waitUntil { controller.state == state }
                XCTAssertEqual(controller.shouldPresentPreview, preview)
                XCTAssertEqual(target.calls.count, 1)
                XCTAssertTrue(controller.canCopy)
                XCTAssertFalse(controller.readyToInsert)
            }
        }
    }

    func testReviewedInsertionPermissionFailureCanBeRetried() async {
        let controller = SessionController(formatter: FakeFormatter()) { FakeRecognition() }
        let entry = SavedTranscript(id: UUID(), createdAt: .now, text: "Pay 10", rawText: "Pay 10", formattedText: "Pay 20")
        controller.showSaved(entry)
        XCTAssertTrue(controller.reviewWarning.contains("Numbers"))
        controller.prepareReviewedInsertion(useFormatted: true)
        controller.handleShortcut(locale: .current, setupBusy: false, capture: { .needsAccessibility })
        XCTAssertEqual(controller.state, .ready)
        XCTAssertTrue(controller.canCopy)
        XCTAssertTrue(controller.needsAccessibility)
        controller.prepareReviewedInsertion(useFormatted: true)
        XCTAssertTrue(controller.readyToInsert)
        let target = FakeInsertionTarget()
        controller.handleShortcut(locale: .current, setupBusy: false, capture: { .target(target) })
        await waitUntil { controller.state == .ready }
        XCTAssertEqual(target.calls, ["Pay 20"])
        XCTAssertFalse(controller.needsAccessibility)
    }

    func testLegacyHistoryAndVariantsRoundTripWithoutLosingOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "history.json")
        let id = UUID()
        let legacy = "[{\"id\":\"\(id.uuidString)\",\"createdAt\":0,\"text\":\"Legacy words\"}]"
        try Data(legacy.utf8).write(to: url)
        let store = RecentTranscripts(fileURL: url)
        XCTAssertEqual(store.entries.first?.text, "Legacy words")
        let added = try XCTUnwrap(store.append("Cleaned", rawText: "Raw", cleanedText: "Cleaned", transformVersion: TextCleanup.version))
        store.saveFormatted(id: added, text: "Formatted", style: .prose)
        let loaded = RecentTranscripts(fileURL: url)
        XCTAssertEqual(loaded.entries.count, 2)
        XCTAssertEqual(loaded.entries.first?.rawText, "Raw")
        XCTAssertEqual(loaded.entries.first?.formattedText, "Formatted")
        XCTAssertEqual(loaded.entries.last?.text, "Legacy words")
    }
    func testSettingsPersistAndCorruptFileIsNotOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "settings.json")
        let settings = CleanupSettings(fileURL: url)
        settings.add(source: "acme", replacement: "Acme")
        settings.setMode(.clean)
        let loaded = CleanupSettings(fileURL: url)
        XCTAssertEqual(loaded.mode, .clean)
        XCTAssertEqual(loaded.replacements.count, 1)
        loaded.add(source: "acme", replacement: "Duplicate")
        XCTAssertNotNil(loaded.errorMessage)
        let corrupt = Data("not JSON".utf8)
        try corrupt.write(to: url)
        let broken = CleanupSettings(fileURL: url)
        broken.setMode(.email)
        XCTAssertEqual(broken.mode, .raw)
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }
}

@MainActor
final class PermissionSetupTests: XCTestCase {
    func testRefreshTracksGrantAndRevocationWithoutRequestingPermission() {
        var trusted = false
        var status: AVAuthorizationStatus = .denied
        let setup = PermissionSetup(readAccessibility: { trusted }, readMicrophone: { status }, requestMicrophone: { XCTFail("Refresh must not prompt"); return false })
        setup.refresh()
        XCTAssertFalse(setup.accessibility)
        XCTAssertEqual(setup.microphone, .denied)
        trusted = true; status = .authorized
        setup.refresh()
        XCTAssertTrue(setup.accessibility)
        XCTAssertEqual(setup.microphone, .authorized)
        trusted = false
        setup.refresh()
        XCTAssertFalse(setup.accessibility)
    }

    func testMicrophoneRequestIsExplicitAndNotRepeatedAfterDecision() async {
        var status: AVAuthorizationStatus = .notDetermined
        var requests = 0
        let setup = PermissionSetup(readAccessibility: { false }, readMicrophone: { status }, requestMicrophone: {
            requests += 1; status = .denied; return false
        })
        await setup.allowMicrophone()
        await setup.allowMicrophone()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(setup.microphone, .denied)
        XCTAssertFalse(setup.requestingMicrophone)
    }

    func testAccessibilityGrantClearsBlockedStartWithoutRecording() {
        let controller = SessionController { XCTFail("Granting permission must not start recording"); return FakeRecognition() }
        controller.toggle(locale: .current, insertion: .needsAccessibility)
        XCTAssertTrue(controller.needsAccessibility)
        controller.accessibilityGranted()
        XCTAssertFalse(controller.needsAccessibility)
        XCTAssertEqual(controller.state, .idle)
    }

    func testAccessibilityGrantPreservesReviewedText() {
        let controller = SessionController { FakeRecognition() }
        controller.showSaved(SavedTranscript(id: UUID(), createdAt: .now, text: "Synthetic saved text"))
        controller.prepareReviewedInsertion(useFormatted: false)
        controller.handleShortcut(locale: .current, setupBusy: false, capture: { .needsAccessibility })
        controller.accessibilityGranted()
        XCTAssertFalse(controller.needsAccessibility)
        XCTAssertEqual(controller.outputText, "Synthetic saved text")
        XCTAssertEqual(controller.state, .ready)
        XCTAssertFalse(controller.readyToInsert)
    }
}

@MainActor
private final class FakeMeetingSource: MeetingAudioCapturing {
    var continuation: AsyncThrowingStream<MeetingAudioPacket, Error>.Continuation?
    var starts = 0
    var stops = 0
    func start(processID: UInt32) throws -> AsyncThrowingStream<MeetingAudioPacket, Error> {
        starts += 1
        let pair = AsyncThrowingStream<MeetingAudioPacket, Error>.makeStream()
        continuation = pair.continuation
        return pair.stream
    }
    func stop() { stops += 1; continuation?.finish(); continuation = nil }
}

@MainActor
final class MeetingTests: XCTestCase {
    private func buffer(seconds: Double = 1) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
        let frames = AVAudioFrameCount(seconds * 8000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 0.05)) * 0.1 }
        return buffer
    }
    private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString) }
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2000 { if condition() { return }; try? await Task.sleep(for: .milliseconds(1)) }
        XCTFail("Meeting condition timed out")
    }

    func testArchiveWritesSeparateBoundedChunksAndPauseGap() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let origin = mach_absolute_time()
        let archive = try MeetingArchive(root: root, origin: origin)
        for offset in 0..<7 {
            for track in MeetingTrack.allCases {
                try await archive.append(MeetingAudioPacket(buffer: buffer(), hostTime: origin + AVAudioTime.hostTime(forSeconds: Double(offset)), track: track))
            }
        }
        try await archive.checkpoint(status: "paused")
        try await archive.append(MeetingAudioPacket(buffer: buffer(), hostTime: origin + AVAudioTime.hostTime(forSeconds: 12), track: .microphone))
        try await archive.checkpoint(status: "saved")
        let directory = archive.directory
        let manifest = try JSONDecoder().decode(MeetingManifest.self, from: Data(contentsOf: directory.appending(path: "manifest.json")))
        XCTAssertEqual(manifest.status, "saved")
        XCTAssertEqual(manifest.chunks.count, 5)
        XCTAssertTrue(manifest.chunks.allSatisfy { $0.durationSeconds <= 5 })
        XCTAssertEqual(manifest.chunks.last?.startSeconds, 12)
        for chunk in manifest.chunks {
            let file = try AVAudioFile(forReading: directory.appending(path: chunk.file))
            XCTAssertEqual(Double(file.length) / file.fileFormat.sampleRate, chunk.durationSeconds, accuracy: 0.001)
        }
    }

    func testCheckpointManifestSurvivesUnfinishedCurrentChunk() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let origin = mach_absolute_time()
        let archive = try MeetingArchive(root: root, origin: origin)
        for i in 0..<6 { try await archive.append(MeetingAudioPacket(buffer: buffer(), hostTime: origin + AVAudioTime.hostTime(forSeconds: Double(i)), track: .remote)) }
        let manifest = try JSONDecoder().decode(MeetingManifest.self, from: Data(contentsOf: archive.directory.appending(path: "manifest.json")))
        XCTAssertEqual(manifest.status, "recording")
        XCTAssertEqual(manifest.chunks.count, 1)
        XCTAssertEqual(manifest.chunks.first?.durationSeconds, 5)
        try await archive.checkpoint(status: "interrupted")
    }

    func testConsentPermissionAndDictationGateCapture() {
        let source = FakeMeetingSource()
        let controller = MeetingController(root: temporaryRoot(), makeSource: { source }, microphoneAllowed: { false })
        controller.selectedID = 1
        controller.start(dictationBusy: false)
        controller.consent = true
        controller.start(dictationBusy: true)
        controller.start(dictationBusy: false)
        XCTAssertEqual(source.starts, 0)
        XCTAssertFalse(controller.busy)
        XCTAssertNil(controller.directory)
    }

    func testPauseResumeStopAndQuitReleaseBothSources() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let source = FakeMeetingSource()
        let controller = MeetingController(root: root, makeSource: { source }, microphoneAllowed: { true })
        controller.selectedID = 1; controller.consent = true
        controller.start(dictationBusy: false)
        XCTAssertEqual(controller.state, .recording)
        source.continuation?.yield(MeetingAudioPacket(buffer: buffer(), hostTime: mach_absolute_time(), track: .microphone))
        controller.pause()
        await waitUntil { controller.state == .paused }
        XCTAssertTrue(controller.busy)
        controller.resume()
        await waitUntil { controller.state == .recording }
        XCTAssertEqual(source.starts, 2)
        await controller.finishForQuit()
        XCTAssertEqual(controller.state, .ready)
        XCTAssertFalse(controller.busy)
        XCTAssertGreaterThanOrEqual(source.stops, 2)
        let manifest = try JSONDecoder().decode(MeetingManifest.self, from: Data(contentsOf: controller.directory!.appending(path: "manifest.json")))
        XCTAssertEqual(manifest.status, "saved")
        XCTAssertEqual(manifest.chunks.count, 1)
    }

    func testCaptureErrorPreservesCompletedAudioAndStops() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let source = FakeMeetingSource()
        let controller = MeetingController(root: root, makeSource: { source }, microphoneAllowed: { true })
        controller.selectedID = 1; controller.consent = true
        controller.start(dictationBusy: false)
        source.continuation?.yield(MeetingAudioPacket(buffer: buffer(), hostTime: mach_absolute_time(), track: .remote))
        await waitUntil { controller.elapsed > 0 }
        source.continuation?.finish(throwing: YadaError("Synthetic disconnect"))
        await waitUntil { controller.state == .failed }
        let manifest = try JSONDecoder().decode(MeetingManifest.self, from: Data(contentsOf: controller.directory!.appending(path: "manifest.json")))
        XCTAssertEqual(manifest.status, "interrupted")
        XCTAssertEqual(manifest.chunks.count, 1)
        XCTAssertGreaterThan(source.stops, 0)
    }

    func testQuitDuringResumeDoesNotRestartCapture() async {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let source = FakeMeetingSource()
        let controller = MeetingController(root: root, makeSource: { source }, microphoneAllowed: { true })
        controller.selectedID = 1; controller.consent = true
        controller.start(dictationBusy: false)
        controller.pause()
        await waitUntil { controller.state == .paused }
        controller.resume()
        await controller.finishForQuit()
        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(source.starts, 1)
    }

    func testStopWhilePauseIsSavingFinalizesMeeting() async {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let source = FakeMeetingSource()
        let controller = MeetingController(root: root, makeSource: { source }, microphoneAllowed: { true })
        controller.selectedID = 1; controller.consent = true
        controller.start(dictationBusy: false)
        controller.pause(); controller.stop()
        await waitUntil { controller.state == .ready }
        XCTAssertFalse(controller.busy)
    }

    func testSyntheticMeetingViewRendersWithoutCapture() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let meeting = MeetingController(root: root, makeSource: { XCTFail("Rendering must not capture"); return FakeMeetingSource() }, microphoneAllowed: { false })
        let view = NSHostingView(rootView: MeetingView(meeting: meeting, dictation: SessionController { FakeRecognition() }, language: LanguageSetup()))
        view.frame = NSRect(x: 0, y: 0, width: 700, height: 850)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        try png.write(to: repository.appending(path: ".build/meeting-preview.png"))
        XCTAssertFalse(meeting.busy)
    }

    func testTranscriberRejectsUnsafeManifestBeforeInference() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = MeetingManifest(id: UUID(), startedAt: .now, status: "saved", chunks: [MeetingChunk(file: "../private.caf", track: .remote, startSeconds: 0, durationSeconds: 1)])
        try JSONEncoder().encode(manifest).write(to: root.appending(path: "manifest.json"))
        do { _ = try await MeetingTranscriber().transcribe(directory: root, locale: Locale(identifier: "en-US")); XCTFail("Unsafe path accepted") }
        catch { XCTAssertTrue(SessionController.userMessage(error).contains("invalid audio chunk")) }
    }
}

@MainActor
final class EverydaySetupTests: XCTestCase {
    func testSavedReviewModeMigratesToSingleAutomaticPath() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "settings.json")
        let old = CleanupSettings(fileURL: url)
        old.add(source: "acme", replacement: "Acme")
        old.setMode(.email)
        let loaded = CleanupSettings(fileURL: url)
        XCTAssertEqual(loaded.mode, .clean)
        XCTAssertEqual(loaded.replacements, [TermReplacement(source: "acme", replacement: "Acme")])
        XCTAssertEqual(CleanupSettings().mode, .clean)
    }

    func testSpeechLanguagePersistsImmediatelyAcrossLaunches() {
        let name = "YadaTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let setup = LanguageSetup(defaults: defaults)
        setup.selectedID = "en-GB"
        XCTAssertEqual(LanguageSetup(defaults: defaults).selectedID, "en-GB")
    }

    func testOnlyOneInstanceCanHoldSharedLock() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var first: AppInstance? = AppInstance()
        let second = AppInstance()
        XCTAssertTrue(try first!.acquireLock(at: url))
        XCTAssertFalse(try second.acquireLock(at: url))
        first = nil
        XCTAssertTrue(try second.acquireLock(at: url))
    }

    func testInstanceDetectionIncludesOldAndDevelopmentCopiesButNotPreview() {
        XCTAssertEqual(AppInstance.existingPID([(1, "com.srinidhi621.yada"), (2, "com.srinidhi621.yada.dev")], currentPID: 2), 1)
        XCTAssertEqual(AppInstance.existingPID([(1, "com.srinidhi621.yada.dev")], currentPID: 2), 1)
        XCTAssertNil(AppInstance.existingPID([(1, "com.srinidhi621.yada.preview"), (2, "com.srinidhi621.yada")], currentPID: 2))
    }

    func testReleaseMustLaunchFromCanonicalInstallation() {
        XCTAssertTrue(AppInstance.validLocation(bundleID: "com.srinidhi621.yada", bundleURL: URL(fileURLWithPath: "/Applications/Yada.app")))
        XCTAssertFalse(AppInstance.validLocation(bundleID: "com.srinidhi621.yada", bundleURL: URL(fileURLWithPath: "/Volumes/Yada Local Test/Yada.app")))
        XCTAssertTrue(AppInstance.validLocation(bundleID: "com.srinidhi621.yada.dev", bundleURL: URL(fileURLWithPath: "/tmp/Yada.app")))
    }
}
