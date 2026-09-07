import AppKit
import AVFoundation
import CoreAudio

struct MeetingAudioApplication: Identifiable, Sendable {
    let id: AudioObjectID
    let name: String
    let pid: Int32
}

// Each packet owns a copy; capture callbacks never reuse its samples after yielding.
struct MeetingAudioPacket: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let hostTime: UInt64
    let track: MeetingTrack
}

private struct MeetingCaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class MeetingAudioSource {
    private var engine: AVAudioEngine?
    private var microphoneTapInstalled = false
    private var generation = UUID()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var continuation: AsyncThrowingStream<MeetingAudioPacket, Error>.Continuation?
    private var configurationObserver: NSObjectProtocol?
    private var processListener: AudioObjectPropertyListenerBlock?
    private var formatListener: AudioObjectPropertyListenerBlock?

    /// Core Audio processes are intentionally shown individually, including helpers.
    /// Selecting one never silently expands capture to other apps or all system audio.
    static func applications() throws -> [MeetingAudioApplication] {
        var address = property(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size), "List audio applications")
        guard size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try ids.withUnsafeMutableBytes { data in
            try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, data.baseAddress!), "Read audio applications")
        }
        return ids.compactMap { id in
            var pid: Int32 = 0
            var pidAddress = property(kAudioProcessPropertyPID)
            var pidSize = UInt32(MemoryLayout<Int32>.size)
            guard AudioObjectGetPropertyData(id, &pidAddress, 0, nil, &pidSize, &pid) == noErr,
                  pid != ProcessInfo.processInfo.processIdentifier else { return nil }
            let app = NSRunningApplication(processIdentifier: pid)
            return MeetingAudioApplication(id: id, name: app?.localizedName ?? "Audio process \(pid)", pid: pid)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func start(processID: AudioObjectID) throws -> AsyncThrowingStream<MeetingAudioPacket, Error> {
        guard continuation == nil else { throw MeetingCaptureError(message: "Meeting capture is already running.") }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw MeetingCaptureError(message: "Allow Yada microphone access before recording a meeting.")
        }
        guard try Self.applications().contains(where: { $0.id == processID }) else {
            throw MeetingCaptureError(message: "The selected audio process has closed. Refresh the application list.")
        }
        let pair = AsyncThrowingStream<MeetingAudioPacket, Error>.makeStream(bufferingPolicy: .bufferingOldest(128))
        continuation = pair.continuation
        let captureID = UUID()
        generation = captureID
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == captureID else { return }
                self.stop()
            }
        }
        do {
            let description = CATapDescription(stereoMixdownOfProcesses: [processID])
            description.name = "Yada selected meeting audio"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try Self.check(AudioHardwareCreateProcessTap(description, &tapID), "Create selected-app audio tap (check System Audio Recording permission)")
            var asbd = AudioStreamBasicDescription()
            var address = Self.property(kAudioTapPropertyFormat)
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd), "Read meeting audio format")
            guard let format = AVAudioFormat(streamDescription: &asbd), asbd.mBytesPerFrame > 0 else {
                throw MeetingCaptureError(message: "The selected application has an unsupported audio format.")
            }
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Yada private meeting capture",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                  kAudioSubTapDriftCompensationKey: true]]
            ]
            try Self.check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID), "Create meeting capture device")
            let sink = MeetingPacketSink(continuation: pair.continuation)
            try Self.check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, deviceID, nil) { _, input, inputTime, _, _ in
                sink.copy(input, format: format, hostTime: inputTime.pointee.mHostTime, track: .remote)
            }, "Prepare meeting audio capture")

            let engine = AVAudioEngine()
            self.engine = engine
            let micFormat = engine.inputNode.outputFormat(forBus: 0)
            guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else {
                throw MeetingCaptureError(message: "No usable microphone is available.")
            }
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: micFormat) { buffer, time in
                guard time.isHostTimeValid else {
                    sink.fail("The microphone did not provide a capture timestamp.")
                    return
                }
                sink.copy(buffer.audioBufferList, format: buffer.format, hostTime: time.hostTime, track: .microphone)
            }
            microphoneTapInstalled = true
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
                sink.fail("The microphone changed. Stop and start a new recording with the new device.")
            }
            let processListener: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in
                    do {
                        guard try Self.applications().contains(where: { $0.id == processID }) else {
                            sink.fail("The selected audio process closed. The captured audio is retained.")
                            return
                        }
                    } catch { sink.fail("The selected audio process could not be checked.") }
                }
            }
            var processAddress = Self.property(kAudioHardwarePropertyProcessObjectList)
            try Self.check(AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &processAddress, .main, processListener), "Watch meeting application")
            self.processListener = processListener
            let formatListener: AudioObjectPropertyListenerBlock = { _, _ in
                sink.fail("The meeting audio format changed. Start a new recording to use the new format.")
            }
            try Self.check(AudioObjectAddPropertyListenerBlock(tapID, &address, .main, formatListener), "Watch meeting audio format")
            self.formatListener = formatListener
            try Self.check(AudioDeviceStart(deviceID, ioProc), "Start meeting application audio")
            try engine.start()
            return pair.stream
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        generation = UUID()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if let processListener {
            var address = Self.property(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, processListener)
        }
        processListener = nil
        if let formatListener {
            var address = Self.property(kAudioTapPropertyFormat)
            AudioObjectRemovePropertyListenerBlock(tapID, &address, .main, formatListener)
        }
        formatListener = nil
        if let engine {
            engine.stop()
            if microphoneTapInstalled { engine.inputNode.removeTap(onBus: 0) }
        }
        engine = nil
        microphoneTapInstalled = false
        if let ioProc {
            AudioDeviceStop(deviceID, ioProc)
            AudioDeviceDestroyIOProcID(deviceID, ioProc)
        }
        ioProc = nil
        if deviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(deviceID) }
        deviceID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        continuation?.finish()
        continuation = nil
    }

    private static func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw MeetingCaptureError(message: "\(operation) failed (\(status)).") }
    }
}

/// No disk or UI work runs on capture callbacks. The bounded stream fails on loss,
/// rather than pretending a recording with dropped buffers is complete.
private final class MeetingPacketSink: Sendable {
    let continuation: AsyncThrowingStream<MeetingAudioPacket, Error>.Continuation
    init(continuation: AsyncThrowingStream<MeetingAudioPacket, Error>.Continuation) { self.continuation = continuation }

    func fail(_ message: String) { continuation.finish(throwing: MeetingCaptureError(message: message)) }

    func copy(_ source: UnsafePointer<AudioBufferList>, format: AVAudioFormat, hostTime: UInt64, track: MeetingTrack) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source))
        guard let first = buffers.first, first.mDataByteSize > 0 else { return }
        let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        guard bytesPerFrame > 0, hostTime != 0 else { fail("Audio capture returned an invalid format or timestamp."); return }
        let frames = first.mDataByteSize / bytesPerFrame
        guard frames <= 16384, let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            fail("Audio capture returned an unsupported buffer size."); return
        }
        copy.frameLength = frames
        let output = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard output.count == buffers.count else { fail("Audio channel layout changed during recording."); return }
        for index in buffers.indices {
            guard buffers[index].mDataByteSize == output[index].mDataByteSize,
                  let src = buffers[index].mData, let dst = output[index].mData else {
                fail("Audio buffer layout changed during recording."); return
            }
            memcpy(dst, src, Int(buffers[index].mDataByteSize))
        }
        switch continuation.yield(MeetingAudioPacket(buffer: copy, hostTime: hostTime, track: track)) {
        case .dropped: fail("Recording could not keep up with audio. Captured chunks have been retained.")
        case .enqueued, .terminated: break
        @unknown default: fail("Audio capture stopped unexpectedly.")
        }
    }
}
