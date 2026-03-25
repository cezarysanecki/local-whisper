@preconcurrency import AVFoundation
import Foundation

/// Records audio from the system microphone using AVAudioEngine.
/// Outputs 16kHz mono Float32 PCM samples – the format required by whisper.cpp.
///
/// This class is intentionally decoupled from any UI framework so it can be
/// reused in a menu-bar app, global-hotkey daemon, or any other context.
public final class AudioRecorder: @unchecked Sendable {

    // MARK: - Public state

    public enum State: Sendable {
        case idle
        case recording
        case error(String)
    }

    public private(set) var state: State = .idle

    /// Accumulated PCM samples (16 kHz, mono, Float32) from the current recording session.
    public private(set) var samples: [Float] = []

    // MARK: - Private

    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16_000

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Start capturing audio from the default input device.
    public func startRecording() throws {
        guard case .idle = state else { return }

        samples.removeAll()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Install a tap that converts to 16 kHz mono Float32
        let convertFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        let converter = AVAudioConverter(from: inputFormat, to: convertFormat)!

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.convertAndAppend(buffer: buffer, converter: converter, outputFormat: convertFormat)
        }

        engine.prepare()
        try engine.start()
        state = .recording
    }

    /// Stop capturing and return the recorded samples.
    @discardableResult
    public func stopRecording() -> [Float] {
        guard case .recording = state else { return samples }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state = .idle

        return samples
    }

    // MARK: - Private helpers

    private func convertAndAppend(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) {
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
        )
        guard frameCount > 0 else { return }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: frameCount
        ) else { return }

        var error: NSError?
        nonisolated(unsafe) var consumedAll = false
        let inputBuffer = buffer

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumedAll {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumedAll = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let error {
            state = .error("Audio conversion failed: \(error.localizedDescription)")
            return
        }

        guard let channelData = outputBuffer.floatChannelData else { return }
        let count = Int(outputBuffer.frameLength)
        let pointer = channelData.pointee
        let newSamples = Array(UnsafeBufferPointer(start: pointer, count: count))
        samples.append(contentsOf: newSamples)
    }
}
