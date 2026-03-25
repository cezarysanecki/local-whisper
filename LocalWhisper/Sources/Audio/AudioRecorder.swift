@preconcurrency import AVFoundation
import Foundation

/// Records audio from the system microphone using AVAudioEngine.
/// Outputs 16kHz mono Float32 PCM samples – the format required by whisper.cpp.
///
/// This class is intentionally decoupled from any UI framework so it can be
/// reused in a menu-bar app, global-hotkey daemon, or any other context.
public final class AudioRecorder: @unchecked Sendable {

    // MARK: - Errors

    public enum RecordingError: LocalizedError {
        case microphonePermissionDenied
        case conversionFailed

        public var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone access denied. Grant permission in System Settings > Privacy & Security > Microphone."
            case .conversionFailed:
                return "Failed to convert audio to 16kHz mono format."
            }
        }
    }

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

    private var engine: AVAudioEngine?
    private let targetSampleRate: Double = 16_000
    private var player: AVAudioPlayer?

    /// Raw buffers captured at the native mic sample rate
    private var rawBuffers: [AVAudioPCMBuffer] = []
    private var rawFormat: AVAudioFormat?

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Request microphone permission. Call once at app startup.
    public static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start capturing audio from the default input device.
    public func startRecording() throws {
        guard case .idle = state else { return }

        // Check microphone permission
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecordingError.microphonePermissionDenied
        }

        samples.removeAll()
        rawBuffers.removeAll()

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        rawFormat = nativeFormat

        // Tap in the native mic format – no conversion issues
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.rawBuffers.append(buffer)
        }

        engine.prepare()
        try engine.start()
        state = .recording
    }

    /// Stop capturing and return the recorded samples (16 kHz, mono, Float32).
    @discardableResult
    public func stopRecording() -> [Float] {
        guard case .recording = state else { return samples }

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        state = .idle

        // Convert captured raw buffers to 16 kHz mono Float32
        guard let rawFormat, !rawBuffers.isEmpty else { return samples }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: rawFormat, to: targetFormat) else {
            state = .error("Failed to create audio converter")
            return samples
        }

        // Calculate total frame count in target sample rate
        var totalInputFrames: AVAudioFrameCount = 0
        for buf in rawBuffers {
            totalInputFrames += buf.frameLength
        }

        let ratio = targetSampleRate / rawFormat.sampleRate
        let totalOutputFrames = AVAudioFrameCount(Double(totalInputFrames) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: totalOutputFrames
        ) else {
            state = .error("Failed to allocate output buffer")
            return samples
        }

        // Feed all raw buffers through the converter
        nonisolated(unsafe) var bufferIndex = 0
        var error: NSError?

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if bufferIndex >= self.rawBuffers.count {
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            let buf = self.rawBuffers[bufferIndex]
            bufferIndex += 1
            return buf
        }

        if let error {
            state = .error("Audio conversion failed: \(error.localizedDescription)")
            return samples
        }

        // Extract Float32 samples
        guard let channelData = outputBuffer.floatChannelData else { return samples }
        let count = Int(outputBuffer.frameLength)
        samples = Array(UnsafeBufferPointer(start: channelData.pointee, count: count))

        // Free raw buffers
        rawBuffers.removeAll()

        return samples
    }

    /// Whether there are samples available for playback.
    public var hasSamples: Bool {
        !samples.isEmpty
    }

    /// Play back the last recorded (and converted) audio through the speakers.
    public func playRecordedAudio() throws {
        guard !samples.isEmpty else { return }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let dst = buffer.floatChannelData!.pointee
        samples.withUnsafeBufferPointer { src in
            dst.update(from: src.baseAddress!, count: samples.count)
        }

        // Write to a temporary WAV file and play it
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-whisper-debug.wav")

        let audioFile = try AVAudioFile(
            forWriting: tmpURL,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try audioFile.write(from: buffer)

        player = try AVAudioPlayer(contentsOf: tmpURL)
        player?.play()
    }
}
