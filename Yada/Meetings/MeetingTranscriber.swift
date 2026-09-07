import AVFoundation
import Foundation
import Speech

/// Transcribes saved tracks only. No microphone, asset download, or network fallback.
@MainActor
final class MeetingTranscriber {
    func transcribe(directory: URL, locale: Locale) async throws -> String {
        let manifest = try JSONDecoder().decode(MeetingManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        guard !manifest.chunks.isEmpty else { throw YadaError("This meeting has no saved audio chunks.") }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        var filenames = Set<String>()
        for chunk in manifest.chunks {
            let name = chunk.file
            guard !name.isEmpty, name == (name as NSString).lastPathComponent,
                  !name.contains("/"), !name.contains("\\"), (name as NSString).pathExtension == "caf",
                  filenames.insert(name).inserted,
                  chunk.startSeconds.isFinite, chunk.startSeconds >= 0,
                  chunk.durationSeconds.isFinite, chunk.durationSeconds > 0,
                  (chunk.startSeconds + chunk.durationSeconds).isFinite else {
                throw YadaError("The meeting manifest contains an invalid audio chunk.")
            }
            let file = root.appendingPathComponent(name).resolvingSymlinksInPath().standardizedFileURL
            guard file.deletingLastPathComponent() == root,
                  try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw YadaError("A meeting audio chunk is not a regular file inside its recording folder.")
            }
        }
        try Task.checkCancellation()
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw YadaError("This language is not supported by Apple on-device transcription.")
        }
        let module = SpeechTranscriber(locale: supported, preset: .transcription)
        guard await AssetInventory.status(forModules: [module]) == .installed else {
            throw YadaError("Install this speech language in Dictation setup before transcribing the meeting.")
        }
        var lines = ["# Meeting transcript", "", "Recorded: \(manifest.startedAt.formatted(.iso8601))",
            "", "Local transcription; review against the saved audio. Track labels identify audio sources, not speakers. Remote audio may contain multiple people. Each chunk is transcribed independently; words crossing chunk boundaries may be incomplete or repeated. Gaps indicate missing captured audio, not necessarily silence."]
        for track in [MeetingTrack.microphone, .remote] {
            let chunks = manifest.chunks.filter { $0.track == track }.sorted { $0.startSeconds < $1.startSeconds }
            lines += ["", "## \(track.label)", ""]
            if chunks.isEmpty {
                lines.append("No audio was saved for this track.")
                continue
            }
            var previousEnd = 0.0
            for chunk in chunks {
                try Task.checkCancellation()
                if chunk.startSeconds > previousEnd + 0.1 {
                    lines += ["Captured-audio gap: \(timestamp(previousEnd))–\(timestamp(chunk.startSeconds)).", ""]
                } else if chunk.startSeconds < previousEnd - 0.1 {
                    lines += ["Audio chunks overlap here; repeated words are possible.", ""]
                }
                lines += ["### Chunk \(timestamp(chunk.startSeconds))–\(timestamp(chunk.startSeconds + chunk.durationSeconds))", ""]
                let segments = try await transcribeFile(root.appendingPathComponent(chunk.file), locale: supported)
                if segments.isEmpty { lines.append("No speech was recognized in this chunk.") }
                for segment in segments {
                    lines.append("[\(timestamp(chunk.startSeconds + segment.start))] \(segment.text)")
                }
                lines.append("")
                previousEnd = max(previousEnd, chunk.startSeconds + chunk.durationSeconds)
            }
        }
        try Task.checkCancellation()
        return lines.joined(separator: "\n") + "\n"
    }

    private struct Segment: Sendable {
        let start: Double
        let text: String
    }

    private func transcribeFile(_ url: URL, locale: Locale) async throws -> [Segment] {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        return try await withTaskCancellationHandler {
            do {
                return try await withThrowingTaskGroup(of: [Segment].self) { group in
                    group.addTask {
                        let audio = try AVAudioFile(forReading: url)
                        _ = try await analyzer.analyzeSequence(from: audio)
                        try Task.checkCancellation()
                        try await analyzer.finalizeAndFinishThroughEndOfInput()
                        return []
                    }
                    group.addTask {
                        var segments: [Segment] = []
                        for try await result in transcriber.results {
                            try Task.checkCancellation()
                            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !text.isEmpty { segments.append(Segment(start: result.range.start.seconds, text: text)) }
                        }
                        return segments
                    }
                    do {
                        var segments: [Segment] = []
                        for try await result in group { segments += result }
                        return segments.sorted { $0.start < $1.start }
                    } catch {
                        group.cancelAll()
                        await analyzer.cancelAndFinishNow()
                        throw error
                    }
                }
            } catch {
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        String(format: "%02.0f:%04.1f", floor(seconds / 60), seconds.truncatingRemainder(dividingBy: 60))
    }
}
