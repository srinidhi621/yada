import AVFoundation
import Speech
import Synchronization

/// Copies tap-owned memory into a bounded stream. No inference, disk or UI work in the tap.
final class AudioCapture {
    private let engine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
    private var hasTap = false
    private var configurationObserver: NSObjectProtocol?
    var format: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    func start() throws -> AsyncThrowingStream<AnalyzerInput, Error> {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw YadaError("No usable microphone is available. Connect or select an input device and retry.")
        }
        let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        self.continuation = continuation
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
            continuation.finish(throwing: YadaError("The audio input changed or disconnected. Check the microphone and retry."))
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
                continuation.finish(throwing: YadaError("Audio buffer allocation failed. Retry recording."))
                return
            }
            copy.frameLength = buffer.frameLength
            let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for (sourceBuffer, destinationBuffer) in zip(source, destination) {
                if let sourceData = sourceBuffer.mData, let destinationData = destinationBuffer.mData {
                    memcpy(destinationData, sourceData, Int(sourceBuffer.mDataByteSize))
                }
            }
            if case .dropped = continuation.yield(AnalyzerInput(buffer: copy)) {
                continuation.finish(throwing: YadaError("Recognition could not keep up with audio. Recording stopped to avoid silently losing words."))
            }
        }
        hasTap = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw YadaError("The microphone could not start. Check the selected input device and retry.")
        }
        return stream
    }

    func stop() {
        if let observer = configurationObserver { NotificationCenter.default.removeObserver(observer) }
        configurationObserver = nil
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        continuation?.finish()
        continuation = nil
    }
}

/// Used only by the single recognition input task, never by the audio callback.
final class AudioConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    init(from source: AVAudioFormat, to target: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: source, to: target) else {
            throw YadaError("The microphone format cannot be converted for local recognition.")
        }
        converter.primeMethod = .none
        self.converter = converter
        self.target = target
    }

    private var drained = false
    func finish() throws -> AnalyzerInput? {
        guard !drained else { return nil }
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096) else {
            throw YadaError("Could not allocate the final recognition audio buffer.")
        }
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            state.pointee = .endOfStream
            return nil
        }
        guard status != .error, error == nil else { throw YadaError("Could not finalize audio conversion.") }
        drained = status == .endOfStream || output.frameLength == 0
        return output.frameLength > 0 ? AnalyzerInput(buffer: output) : nil
    }

    static func peak(_ buffer: AVAudioPCMBuffer) -> Float {
        var peak: Float = 0
        if let channel = buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[i])) }
        } else if let channel = buffer.int16ChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(Float(channel[i])) / 32768) }
        } else if let channel = buffer.int32ChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(Float(channel[i])) / 2147483648) }
        }
        return min(1, peak * 4)
    }

    func convert(_ input: AnalyzerInput) throws -> AnalyzerInput {
        let buffer = input.buffer
        let frames = AVAudioFrameCount(ceil(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: frames) else {
            throw YadaError("Could not allocate a recognition audio buffer.")
        }
        let supplied = Mutex(false)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            let first = supplied.withLock { value in
                if value { return false }
                value = true
                return true
            }
            guard first else { state.pointee = .noDataNow; return nil }
            state.pointee = .haveData
            return input.buffer
        }
        guard status != .error, error == nil else { throw YadaError("Microphone audio conversion failed. Retry recording.") }
        return AnalyzerInput(buffer: output)
    }
}

/// Pull-based conversion keeps the tap queue bounded and flushes resampler tails at EOF.
struct ConvertedAudioSequence: AsyncSequence, Sendable {
    typealias Element = AnalyzerInput
    let source: AsyncThrowingStream<AnalyzerInput, Error>
    let converter: AudioConverter
    let onLevel: @MainActor @Sendable (Float) -> Void
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(source: source.makeAsyncIterator(), converter: converter, onLevel: onLevel) }

    struct AsyncIterator: AsyncIteratorProtocol {
        var source: AsyncThrowingStream<AnalyzerInput, Error>.Iterator
        let converter: AudioConverter
        let onLevel: @MainActor @Sendable (Float) -> Void
        var ended = false
        mutating func next() async throws -> AnalyzerInput? {
            while !ended {
                try Task.checkCancellation()
                if let input = try await source.next() {
                    await onLevel(AudioConverter.peak(input.buffer))
                    let output = try converter.convert(input)
                    if output.buffer.frameLength > 0 { return output }
                } else { ended = true }
            }
            return try converter.finish()
        }
    }
}
