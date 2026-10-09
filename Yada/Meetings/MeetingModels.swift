import Foundation

// Track labels describe capture sources, not speaker identities.
enum MeetingTrack: String, Codable, Sendable, CaseIterable {
    case microphone, remote
    var label: String { self == .microphone ? "Local microphone" : "Selected app audio" }
}

struct MeetingChunk: Codable, Sendable {
    let file: String
    let track: MeetingTrack
    let startSeconds: Double
    let durationSeconds: Double
}

struct MeetingManifest: Codable, Sendable {
    let id: UUID
    let startedAt: Date
    var status: String
    var chunks: [MeetingChunk]
}

/// Name and timing checks that run before any audio file is opened.
enum MeetingChunkRules {
    static func accepts(_ chunk: MeetingChunk, seen: inout Set<String>) -> Bool {
        let name = chunk.file
        guard !name.isEmpty,
              name == (name as NSString).lastPathComponent,
              !name.contains("/"),
              !name.contains("\\"),
              (name as NSString).pathExtension == "caf",
              chunk.startSeconds.isFinite, chunk.startSeconds >= 0,
              chunk.durationSeconds.isFinite, chunk.durationSeconds > 0,
              (chunk.startSeconds + chunk.durationSeconds).isFinite,
              seen.insert(name).inserted else {
            return false
        }
        return true
    }
}

/// Clock text for meeting transcripts. A rounded tenth never displays as 60 seconds.
enum MeetingTranscriptClock {
    static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < 100 * 60 * 60 else { return "--:--.-" }
        let totalTenths = Int((seconds * 10).rounded(.toNearestOrAwayFromZero))
        let minutes = totalTenths / 600
        let remainder = totalTenths % 600
        return String(format: "%02d:%02d.%d", minutes, remainder / 10, remainder % 10)
    }
}
