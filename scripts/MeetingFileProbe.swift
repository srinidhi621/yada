import AVFoundation
import Foundation

struct YadaError: Error { let message: String; init(_ message: String) { self.message = message } }

@main
struct MeetingFileProbe {
    @MainActor static func main() async {
        do { try await run() }
        catch { print("Probe failed: " + ((error as? YadaError)?.message ?? String(describing: error))); exit(1) }
    }
    @MainActor static func run() async throws {
        guard CommandLine.arguments.count == 4 else { exit(2) }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let input = URL(fileURLWithPath: CommandLine.arguments[2])
        let audio = try AVAudioFile(forReading: input)
        let origin = mach_absolute_time()
        let archive = try MeetingArchive(root: root, origin: origin)
        var offset = 0.0
        while audio.framePosition < audio.length {
            let frames = AVAudioFrameCount(min(8000, audio.length - audio.framePosition))
            let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: frames)!
            try audio.read(into: buffer, frameCount: frames)
            try await archive.append(MeetingAudioPacket(buffer: buffer, hostTime: origin + AVAudioTime.hostTime(forSeconds: offset), track: .remote))
            offset += Double(buffer.frameLength) / buffer.format.sampleRate
        }
        try await archive.checkpoint(status: "saved")
        let text = try await MeetingTranscriber().transcribe(directory: archive.directory, locale: Locale(identifier: CommandLine.arguments[3]))
        try text.write(to: root.appending(path: "synthetic-transcript.md"), atomically: true, encoding: .utf8)
        print(text)
    }
}
