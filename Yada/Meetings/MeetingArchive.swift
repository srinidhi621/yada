import AVFoundation

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

/// Serial disk writer. Audio callbacks only copy/yield buffers to a bounded stream.
actor MeetingArchive {
    nonisolated let directory: URL
    private var manifest: MeetingManifest
    private let origin: UInt64
    private var files: [MeetingTrack: AVAudioFile] = [:]
    private var active: [MeetingTrack: MeetingChunk] = [:]
    private var sequence = 0

    init(root: URL, origin: UInt64) throws {
        let id = UUID()
        directory = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        self.origin = origin
        manifest = MeetingManifest(id: id, startedAt: .now, status: "recording", chunks: [])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Self.save(manifest, to: directory)
    }

    func append(_ packet: MeetingAudioPacket) throws {
        let buffer = packet.buffer
        guard buffer.frameLength > 0, buffer.format.sampleRate > 0 else { return }
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        guard duration <= 5, packet.hostTime >= origin else { throw YadaError("Invalid meeting audio timing. Saved chunks remain available.") }
        let offset = AVAudioTime.seconds(forHostTime: packet.hostTime - origin)
        if let current = active[packet.track], let file = files[packet.track] {
            let end = current.startSeconds + current.durationSeconds
            if current.durationSeconds + duration > 5 || abs(offset - end) > 0.1 || file.processingFormat != buffer.format {
                try close(packet.track)
            }
        }
        if files[packet.track] == nil {
            sequence += 1
            let name = "\(packet.track.rawValue)-\(sequence).caf"
            let url = directory.appending(path: name)
            files[packet.track] = try AVAudioFile(forWriting: url, settings: buffer.format.settings, commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            active[packet.track] = MeetingChunk(file: name, track: packet.track, startSeconds: offset, durationSeconds: 0)
        }
        try files[packet.track]!.write(from: buffer)
        let current = active[packet.track]!
        active[packet.track] = MeetingChunk(file: current.file, track: current.track, startSeconds: current.startSeconds, durationSeconds: current.durationSeconds + duration)
    }

    func checkpoint(status: String) throws {
        for track in MeetingTrack.allCases { try close(track) }
        manifest.status = status
        try Self.save(manifest, to: directory)
    }

    private func close(_ track: MeetingTrack) throws {
        files[track] = nil // Close the CAF before publishing it in the manifest.
        if let chunk = active.removeValue(forKey: track) { manifest.chunks.append(chunk) }
        try Self.save(manifest, to: directory)
    }

    private static func save(_ manifest: MeetingManifest, to directory: URL) throws {
        let url = directory.appending(path: "manifest.json")
        try JSONEncoder().encode(manifest).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
