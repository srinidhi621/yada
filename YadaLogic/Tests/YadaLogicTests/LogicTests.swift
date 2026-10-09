import XCTest
@testable import YadaLogic

final class TranscriptLogicTests: XCTestCase {
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
    func testOutOfOrderFinalsSortAndRejectInvalidRanges() {
        var transcript = Transcript()
        transcript.receive(segment(2, 3, " second", final: true))
        transcript.receive(segment(0, 1, "first ", final: true))
        transcript.receive(segment(3, 2, "backwards", final: true))
        transcript.receive(segment(.nan, 1, "bad"))
        transcript.receive(segment(0, .infinity, "bad"))
        XCTAssertEqual(transcript.finalText, "first  second")
        transcript.receive(segment(1, 2, " middle", final: true))
        XCTAssertEqual(transcript.preview, "first  middle second")
    }
    func testFinishDropsNonOverlappingProvisionalsAndKeepsTouchingFinals() {
        var transcript = Transcript()
        transcript.receive(segment(0, 1, "keep "))
        transcript.receive(segment(2, 3, "stay", final: true))
        XCTAssertEqual(transcript.preview, "keep stay")
        transcript.finish()
        XCTAssertEqual(transcript.finalText, "stay")
        var adjacent = Transcript()
        adjacent.receive(segment(0, 1, "A", final: true))
        adjacent.receive(segment(1, 2, "B", final: true))
        XCTAssertEqual(adjacent.finalText, "AB")
    }
}

final class CleanupLogicTests: XCTestCase {
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
    func testLongerTerminologyWinsAndMetacharactersStayLiteral() {
        let terms = [TermReplacement(source: "York", replacement: "Y"), TermReplacement(source: "New York", replacement: "NYC")]
        XCTAssertEqual(TextCleanup.apply("New York and York", replacements: terms), "NYC and Y")
        XCTAssertEqual(TextCleanup.apply("pay 1.20 now", replacements: [TermReplacement(source: "1.20", replacement: "1.50")]), "pay 1.50 now")
        XCTAssertEqual(TextCleanup.apply("a+b a", replacements: [TermReplacement(source: "a+b", replacement: "sum")]), "sum a")
    }
    func testDuplicateAndEmptyTermsDoNotCrashOrDeleteText() {
        let terms = [TermReplacement(source: "yada", replacement: "Yada"), TermReplacement(source: "yada", replacement: "Wrong"), TermReplacement(source: "", replacement: "nope")]
        XCTAssertEqual(TextCleanup.apply("yada  yada", replacements: terms), "Yada Yada")
        XCTAssertEqual(TextCleanup.apply("yada  app", replacements: [TermReplacement(source: "yada", replacement: "")]), "yada app")
    }
    func testFencedCodeAndCurlyQuotesKeepInternalSpacing() {
        let raw = "hello  world\n```\nlet  x = 1\n```\nSay “two  spaces”\nbye  now"
        XCTAssertEqual(TextCleanup.apply(raw, replacements: []), "hello world\n```\nlet  x = 1\n```\nSay “two  spaces”\nbye now")
    }
    func testModelNumberWarningIsNotAnEquivalenceClaim() {
        XCTAssertTrue(FormatReview.warning(original: "Pay 120", formatted: "Pay 200").contains("Numbers"))
        XCTAssertTrue(FormatReview.warning(original: "Do not pay 120", formatted: "Pay 120").contains("meaning"))
        XCTAssertTrue(FormatReview.warning(original: "120 and 120", formatted: "120").contains("Numbers"))
        XCTAssertTrue(FormatReview.warning(original: "See 01/02", formatted: "See 01/02").contains("meaning"))
    }
}

final class MeetingLogicTests: XCTestCase {
    func testChunkRulesRejectTraversalAndInvalidTiming() {
        var seen = Set<String>()
        XCTAssertTrue(MeetingChunkRules.accepts(MeetingChunk(file: "microphone-1.caf", track: .microphone, startSeconds: 0, durationSeconds: 5), seen: &seen))
        XCTAssertFalse(MeetingChunkRules.accepts(MeetingChunk(file: "microphone-1.caf", track: .microphone, startSeconds: 0, durationSeconds: 5), seen: &seen))
        XCTAssertFalse(MeetingChunkRules.accepts(MeetingChunk(file: "../private.caf", track: .remote, startSeconds: 0, durationSeconds: 1), seen: &seen))
        XCTAssertFalse(MeetingChunkRules.accepts(MeetingChunk(file: "note.txt", track: .remote, startSeconds: 0, durationSeconds: 1), seen: &seen))
        XCTAssertFalse(MeetingChunkRules.accepts(MeetingChunk(file: "dir\\file.caf", track: .remote, startSeconds: 0, durationSeconds: 1), seen: &seen))
        XCTAssertFalse(MeetingChunkRules.accepts(MeetingChunk(file: "remote-1.caf", track: .remote, startSeconds: -1, durationSeconds: 1), seen: &seen))
        XCTAssertTrue(MeetingChunkRules.accepts(MeetingChunk(file: "remote-1.caf", track: .remote, startSeconds: 0, durationSeconds: 1), seen: &seen))
        XCTAssertFalse(MeetingChunkRules.accepts(MeetingChunk(file: "remote-2.caf", track: .remote, startSeconds: 0, durationSeconds: 0), seen: &seen))
        XCTAssertFalse(MeetingChunkRules.accepts(MeetingChunk(file: "remote-3.caf", track: .remote, startSeconds: .infinity, durationSeconds: 1), seen: &seen))
    }
    func testTranscriptClockRoundsFiftyNineSecondsIntoTheNextMinute() {
        XCTAssertEqual(MeetingTranscriptClock.timestamp(0), "00:00.0")
        XCTAssertEqual(MeetingTranscriptClock.timestamp(5), "00:05.0")
        XCTAssertEqual(MeetingTranscriptClock.timestamp(65.12), "01:05.1")
        XCTAssertEqual(MeetingTranscriptClock.timestamp(59.94), "00:59.9")
        XCTAssertEqual(MeetingTranscriptClock.timestamp(59.96), "01:00.0")
        XCTAssertEqual(MeetingTranscriptClock.timestamp(119.96), "02:00.0")
        XCTAssertEqual(MeetingTranscriptClock.timestamp(.nan), "--:--.-")
        XCTAssertEqual(MeetingTranscriptClock.timestamp(-1), "--:--.-")
    }
}

final class HistoryLogicTests: XCTestCase {
    func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "yada-history-test-\(UUID().uuidString)/history.json")
    }
    func testRoundTripPreservesTextAndSupportsDeletion() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await MainActor.run {
            let history = RecentTranscripts(fileURL: file)
            history.append("  Synthetic text.\nExact whitespace.  ")
            history.append("Second synthetic entry.")
            let loaded = RecentTranscripts(fileURL: file)
            XCTAssertEqual(loaded.entries, history.entries)
            XCTAssertEqual(loaded.entries.last?.text, "  Synthetic text.\nExact whitespace.  ")
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let mode = attributes[.posixPermissions] as? Int ?? (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
            XCTAssertEqual(mode & 0o777, 0o600)
            loaded.delete(id: loaded.entries[0].id)
            XCTAssertEqual(RecentTranscripts(fileURL: file).entries.count, 1)
            loaded.clear()
            XCTAssertTrue(RecentTranscripts(fileURL: file).entries.isEmpty)
        }
    }
    func testBoundedHistoryAndEmptyResults() async {
        await MainActor.run {
            let history = RecentTranscripts()
            history.append("")
            XCTAssertTrue(history.entries.isEmpty)
            for i in 0..<60 { history.append("Synthetic \(i)") }
            XCTAssertEqual(history.entries.count, 50)
            XCTAssertEqual(history.entries.first?.text, "Synthetic 59")
            XCTAssertEqual(history.entries.last?.text, "Synthetic 10")
        }
    }
    func testUnreadableHistoryIsPreservedUntilExplicitClear() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("invalid synthetic fixture".utf8)
        try original.write(to: file)
        try await MainActor.run {
            let history = RecentTranscripts(fileURL: file)
            XCTAssertNotNil(history.errorMessage)
            history.append("Must not overwrite damaged history")
            XCTAssertEqual(try Data(contentsOf: file), original)
            history.clear()
            history.append("New synthetic entry")
            XCTAssertEqual(RecentTranscripts(fileURL: file).entries.count, 1)
        }
    }
    func testSaveFailureDoesNotClaimSuccess() async throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        try Data().write(to: file.appending(path: "blocked"))
        await MainActor.run {
            let history = RecentTranscripts(fileURL: file.appending(path: "blocked/record.json"))
            history.append("Synthetic")
            XCTAssertTrue(history.entries.isEmpty)
            XCTAssertNotNil(history.errorMessage)
        }
    }
    func testLegacyHistoryAndVariantsRoundTripWithoutLosingOriginal() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "history.json")
        let id = UUID()
        let legacy = "[{\"id\":\"\(id.uuidString)\",\"createdAt\":0,\"text\":\"Legacy words\"}]"
        try Data(legacy.utf8).write(to: url)
        try await MainActor.run {
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
    }
}

final class SettingsLogicTests: XCTestCase {
    func testSettingsPersistAndCorruptFileIsNotOverwritten() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "settings.json")
        try await MainActor.run {
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
    func testSavedReviewModeMigratesToSingleAutomaticPath() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "settings.json")
        await MainActor.run {
            let old = CleanupSettings(fileURL: url)
            old.add(source: "acme", replacement: "Acme")
            old.setMode(.email)
            let loaded = CleanupSettings(fileURL: url)
            XCTAssertEqual(loaded.mode, .clean)
            XCTAssertEqual(loaded.replacements, [TermReplacement(source: "acme", replacement: "Acme")])
            XCTAssertEqual(CleanupSettings().mode, .clean)
        }
    }
}
