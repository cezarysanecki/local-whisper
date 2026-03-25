@preconcurrency import AVFoundation
import Accelerate
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
    private var playbackProcess: Process?

    /// Raw buffers captured at the native mic sample rate
    private var rawBuffers: [AVAudioPCMBuffer] = []
    private var rawFormat: AVAudioFormat?

    /// Dedicated temp directory for audio files.
    private static let tempDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-whisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Init

    public init() {}

    // MARK: - Temp File Management

    /// Remove all temporary audio files. Call on app launch and termination.
    public static func cleanupTempFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? fm.removeItem(at: file)
        }
    }

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

        // Tap in the native mic format – no conversion issues.
        // IMPORTANT: We must copy each buffer because the callback reuses the same memory.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
            copy.frameLength = buffer.frameLength
            let src = buffer.floatChannelData!
            let dst = copy.floatChannelData!
            for ch in 0..<Int(buffer.format.channelCount) {
                dst[ch].update(from: src[ch], count: Int(buffer.frameLength))
            }
            self.rawBuffers.append(copy)
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
        var rawSamples = Array(UnsafeBufferPointer(start: channelData.pointee, count: count))

        // Post-processing: reduce background noise
        rawSamples = applyHighPassFilter(rawSamples, sampleRate: targetSampleRate, cutoffHz: 80)
        rawSamples = applyNoiseGate(rawSamples, sampleRate: targetSampleRate)
        rawSamples = normalize(rawSamples)

        samples = rawSamples

        // Free raw buffers
        rawBuffers.removeAll()

        return samples
    }

    /// Whether there are samples available for playback.
    public var hasSamples: Bool {
        !samples.isEmpty
    }

    /// Securely clear recorded samples from memory.
    public func clearSamples() {
        samples.withUnsafeMutableBufferPointer { buf in
            if let base = buf.baseAddress {
                memset(base, 0, buf.count * MemoryLayout<Float>.stride)
            }
        }
        samples.removeAll()
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
        let tmpURL = Self.tempDirectory
            .appendingPathComponent("debug-\(UUID().uuidString.prefix(8)).wav")

        let audioFile = try AVAudioFile(
            forWriting: tmpURL,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try audioFile.write(from: buffer)

        // Restrict file permissions to owner only
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tmpURL.path
        )

        // Stop any previous playback
        playbackProcess?.terminate()

        // Play via afplay (system utility, no UI dependency)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [tmpURL.path]
        try process.run()
        playbackProcess = process
    }

    // MARK: - Audio Processing

    /// Second-order Butterworth high-pass filter to remove low-frequency rumble.
    private func applyHighPassFilter(_ samples: [Float], sampleRate: Double, cutoffHz: Double) -> [Float] {
        guard samples.count > 2 else { return samples }

        // Compute second-order Butterworth high-pass coefficients
        let w0 = 2.0 * Double.pi * cutoffHz / sampleRate
        let alpha = sin(w0) / (2.0 * sqrt(2.0)) // Q = sqrt(2)/2 for Butterworth

        let b0 = Float((1.0 + cos(w0)) / 2.0 / (1.0 + alpha))
        let b1 = Float(-(1.0 + cos(w0)) / (1.0 + alpha))
        let b2 = b0
        let a1 = Float(-2.0 * cos(w0) / (1.0 + alpha))
        let a2 = Float((1.0 - alpha) / (1.0 + alpha))

        var output = [Float](repeating: 0, count: samples.count)

        // Direct Form II transposed
        var z1: Float = 0
        var z2: Float = 0

        for i in 0..<samples.count {
            let x = samples[i]
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            output[i] = y
        }

        return output
    }

    /// Noise gate: estimates noise floor from the quietest portions and gates below threshold.
    ///
    /// Works in frames (~20ms). Measures RMS per frame, finds the noise floor,
    /// then smoothly attenuates frames whose RMS is close to the noise floor.
    private func applyNoiseGate(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard samples.count > 0 else { return samples }

        let frameSize = Int(sampleRate * 0.02) // 20ms frames
        let frameCount = samples.count / frameSize
        guard frameCount > 2 else { return samples }

        // Calculate RMS for each frame
        var rmsValues = [Float](repeating: 0, count: frameCount)
        samples.withUnsafeBufferPointer { ptr in
            let base = ptr.baseAddress!
            for i in 0..<frameCount {
                let offset = i * frameSize
                var sumSq: Float = 0
                vDSP_svesq(base + offset, 1, &sumSq, vDSP_Length(frameSize))
                rmsValues[i] = sqrt(sumSq / Float(frameSize))
            }
        }

        // Estimate noise floor: median of the lowest 20% of frame RMS values
        let sorted = rmsValues.sorted()
        let lowCount = max(1, frameCount / 5)
        let noiseFloor = sorted[lowCount - 1]

        // Gate threshold: 1.5x the noise floor (gentle, to avoid clipping speech)
        let threshold = max(noiseFloor * 1.5, 1e-5)

        var output = samples
        output.withUnsafeMutableBufferPointer { ptr in
            let base = ptr.baseAddress!
            for i in 0..<frameCount {
                let rms = rmsValues[i]
                let offset = i * frameSize

                if rms < threshold {
                    // Below threshold: soft gate (attenuate proportionally)
                    var gain = max(0, (rms / threshold))
                    vDSP_vsmul(base + offset, 1, &gain, base + offset, 1, vDSP_Length(frameSize))
                }
                // Above threshold: pass through unchanged
            }
        }

        // Handle remaining samples (tail shorter than one frame) – pass through
        return output
    }

    /// Peak-normalize audio to ~0.95 full scale so quiet recordings are boosted.
    private func normalize(_ samples: [Float], targetPeak: Float = 0.95) -> [Float] {
        guard !samples.isEmpty else { return samples }

        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))

        guard peak > 1e-6 else { return samples } // silence, don't amplify noise

        let gain = targetPeak / peak
        guard gain > 1.01 else { return samples } // already loud enough

        var output = samples
        var g = gain
        output.withUnsafeMutableBufferPointer { ptr in
            vDSP_vsmul(ptr.baseAddress!, 1, &g, ptr.baseAddress!, 1, vDSP_Length(ptr.count))
        }
        return output
    }
}
