import AppKit
import AVFoundation
import CoreAudio
import Observation

@MainActor
protocol MeetingAudioCapturing: AnyObject {
    func start(processID: AudioObjectID) throws -> AsyncThrowingStream<MeetingAudioPacket, Error>
    func stop()
}
extension MeetingAudioSource: MeetingAudioCapturing {}

@MainActor @Observable
final class MeetingController {
    enum State: String { case idle = "Idle", recording = "Recording", pausing = "Saving", paused = "Paused", stopping = "Stopping", ready = "Saved", failed = "Stopped with an error", transcribing = "Transcribing" }
    private(set) var state: State = .idle
    private(set) var applications: [MeetingAudioApplication] = []
    var selectedID: AudioObjectID = 0
    var consent = false
    private(set) var message = "Choose the meeting's audio process. Use headphones and obtain participants' permission before recording."
    private(set) var elapsed: Double = 0
    private(set) var directory: URL?
    private(set) var transcript = ""
    private(set) var microphoneLevel: Float = 0
    private(set) var remoteLevel: Float = 0
    private var capturedTracks: Set<MeetingTrack> = []
    private var archive: MeetingArchive?
    private var source: (any MeetingAudioCapturing)?
    private var task: Task<Void, Never>?
    private let storageRoot: URL
    private let makeSource: () -> any MeetingAudioCapturing
    private let microphoneAllowed: () -> Bool
    init(root: URL? = nil, makeSource: @escaping () -> any MeetingAudioCapturing = { MeetingAudioSource() },
         microphoneAllowed: @escaping () -> Bool = { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }) {
        storageRoot = root ?? Self.root
        self.makeSource = makeSource
        self.microphoneAllowed = microphoneAllowed
    }
    private var stopRequested = false
    private var started: UInt64 = 0
    private var sleepObserver: NSObjectProtocol?
    var busy: Bool { [.recording, .pausing, .paused, .stopping, .transcribing].contains(state) }
    var capturing: Bool { state == .recording }
    static var root: URL { AppStorage.directory.appending(path: "Meetings", directoryHint: .isDirectory) }

    func refreshApplications() {
        guard !busy else { return }
        do { applications = try MeetingAudioSource.applications(); if !applications.contains(where: { $0.id == selectedID }) { selectedID = applications.first?.id ?? 0 } }
        catch { message = Self.userMessage(error) }
    }

    func start(dictationBusy: Bool) {
        guard !busy, !dictationBusy, consent, selectedID != 0 else { return }
        guard microphoneAllowed() else {
            message = "Allow microphone access in the Dictation setup tab first. Nothing was recorded."
            return
        }
        do {
            stopRequested = false
            started = mach_absolute_time()
            let archive = try MeetingArchive(root: storageRoot, origin: started)
            self.archive = archive; directory = archive.directory
            transcript = ""; elapsed = 0; capturedTracks = []
            try beginCapture()
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        } catch { fail(error) }
    }

    private func beginCapture() throws {
        guard let archive else { return }
        let source = makeSource()
        self.source = source
        let packets = try source.start(processID: selectedID)
        state = .recording
        message = "Recording microphone and selected app. Muting in Teams does not mute Yada. Use Pause here."
        task = Task {
            do {
                for try await packet in packets {
                    try await archive.append(packet)
                    capturedTracks.insert(packet.track)
                    elapsed = max(elapsed, AVAudioTime.seconds(forHostTime: packet.hostTime - started))
                    if packet.track == .microphone { microphoneLevel = AudioConverter.peak(packet.buffer) }
                    else { remoteLevel = AudioConverter.peak(packet.buffer) }
                }
                source.stop()
                let paused = state == .pausing && !stopRequested
                try await archive.checkpoint(status: paused ? "paused" : "saved")
                if !paused { removeSleepObserver() }
                state = paused ? .paused : .ready
                if paused { message = "Paused. Neither track is being captured." }
                else if capturedTracks.count == 2 { message = "Both audio tracks saved locally. Choose Transcribe to create a local transcript." }
                else { message = "Recording stopped. Missing audio from: " + MeetingTrack.allCases.filter { !capturedTracks.contains($0) }.map(\.label).joined(separator: ", ") + ". Check permissions and the selected process before another recording." }
            } catch {
                source.stop()
                try? await archive.checkpoint(status: "interrupted")
                fail(error)
            }
            self.source = nil
            microphoneLevel = 0; remoteLevel = 0
        }
    }

    func pause() {
        guard state == .recording else { return }
        state = .pausing
        source?.stop()
    }

    func resume() {
        guard state == .paused else { return }
        stopRequested = false
        state = .pausing
        task = Task {
            do {
                try await archive?.checkpoint(status: "recording")
                if stopRequested {
                    try await archive?.checkpoint(status: "saved")
                    state = .ready; message = "Audio saved locally."
                } else { try beginCapture() }
            } catch { fail(error) }
        }
    }

    func stop() {
        guard [.recording, .paused, .pausing].contains(state) else { return }
        stopRequested = true
        removeSleepObserver()
        if state == .pausing { return }
        if state == .paused {
            state = .stopping
            task = Task {
                do { try await archive?.checkpoint(status: "saved"); state = .ready; message = "Audio saved locally." }
                catch { fail(error) }
            }
        } else { state = .stopping; source?.stop() }
    }

    func transcribe(locale: Locale) {
        guard !busy, let directory else { return }
        state = .transcribing
        message = "Transcribing saved audio on this Mac. No upload."
        task = Task {
            do {
                let result = try await MeetingTranscriber().transcribe(directory: directory, locale: locale)
                try Task.checkCancellation()
                let url = directory.appending(path: "transcript.md")
                try result.write(to: url, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                transcript = result; state = .ready; message = "Transcript saved beside the audio. Track labels are not speaker identities."
            } catch { state = .ready; message = "Transcription did not finish. Audio is preserved for retry. " + Self.userMessage(error) }
        }
    }

    func finishForQuit() async {
        while busy {
            if state == .transcribing { task?.cancel() }
            else { stop() }
            let pending = task
            await pending?.value
        }
    }

    func cancelTranscription() { if state == .transcribing { task?.cancel() } }

    func openSaved(_ url: URL) {
        guard !busy, url.deletingLastPathComponent().standardizedFileURL == storageRoot.standardizedFileURL else { return }
        directory = url; transcript = ""; state = .ready
        message = "Saved meeting selected. Interrupted sessions contain only the chunks listed in their manifest; partial files may remain in the folder."
    }

    func savedDirectories() -> [URL] {
        guard !UIValidation.isEnabled else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: storageRoot, includingPropertiesForKeys: nil)) ?? []).filter { UUID(uuidString: $0.lastPathComponent) != nil }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func deleteCurrent() {
        guard !busy, let directory, directory.deletingLastPathComponent().standardizedFileURL == storageRoot.standardizedFileURL else { return }
        do { try FileManager.default.removeItem(at: directory); self.directory = nil; archive = nil; transcript = ""; state = .idle; message = "Meeting audio and transcript deleted." }
        catch { message = "Could not delete the meeting. " + Self.userMessage(error) }
    }

    private static func userMessage(_ error: Error) -> String {
        (error as? YadaError)?.message ?? (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func fail(_ error: Error) {
        source?.stop(); source = nil; removeSleepObserver()
        state = .failed; message = Self.userMessage(error) + " Completed chunks remain saved locally."
    }
    private func removeSleepObserver() {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        sleepObserver = nil
    }
}
