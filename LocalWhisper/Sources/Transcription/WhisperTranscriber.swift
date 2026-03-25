import Foundation
import whisper

/// Errors that can occur during whisper model operations.
public enum WhisperError: LocalizedError, Sendable {
    case modelNotFound(String)
    case couldNotInitializeContext
    case transcriptionFailed
    case memoryAllocationFailed

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Model file not found at: \(path)"
        case .couldNotInitializeContext:
            return "Failed to initialize whisper context – invalid or corrupted model file?"
        case .transcriptionFailed:
            return "whisper_full() returned an error during transcription"
        case .memoryAllocationFailed:
            return "Failed to allocate memory for language string"
        }
    }
}

/// Thin Swift wrapper around the whisper.cpp C API.
///
/// This class is intentionally decoupled from any UI framework so it can be
/// reused in a menu-bar app, global-hotkey daemon, or any other context.
///
/// Thread-safety: all access to the whisper context is serialized through
/// `contextLock`. The class is `@unchecked Sendable` because `NSLock`
/// provides the necessary synchronization that the compiler cannot verify.
public final class WhisperTranscriber: @unchecked Sendable {

    // MARK: - Private

    private var context: OpaquePointer? // whisper_context *
    private let contextLock = NSLock()
    private let language: String
    /// Stable C string for whisper params (must outlive whisper_full calls).
    private let languageCStr: UnsafeMutablePointer<CChar>

    /// Maximum threads to use for inference.
    private var maxThreads: Int {
        max(1, ProcessInfo.processInfo.processorCount - 2)
    }

    // MARK: - Init / Deinit

    /// Initialize the transcriber by loading a GGML model from disk.
    ///
    /// - Parameters:
    ///   - modelPath: Absolute path to a `.bin` GGML whisper model file.
    ///   - language: BCP-47 language code, e.g. `"pl"` for Polish. Defaults to `"pl"`.
    public init(modelPath: String, language: String = "pl") throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperError.modelNotFound(modelPath)
        }

        self.language = language
        guard let cStr = strdup(language) else {
            throw WhisperError.memoryAllocationFailed
        }
        self.languageCStr = cStr

        var params = whisper_context_default_params()
        params.flash_attn = true // enable flash attention on Apple Silicon

        guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperError.couldNotInitializeContext
        }

        self.context = ctx
    }

    deinit {
        contextLock.lock()
        if let context {
            whisper_free(context)
            self.context = nil
        }
        contextLock.unlock()
        free(languageCStr)
    }

    // MARK: - Public API

    /// Transcribe PCM audio samples (16 kHz, mono, Float32) to text.
    ///
    /// This is a **synchronous, blocking** call. Run it on a background thread.
    /// Thread-safe: serialized via `contextLock`.
    ///
    /// - Parameter samples: Audio samples in 16 kHz mono Float32 format.
    /// - Returns: The transcribed text.
    public func transcribe(samples: [Float]) throws -> String {
        contextLock.lock()
        defer { contextLock.unlock() }

        guard let context else {
            throw WhisperError.couldNotInitializeContext
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(maxThreads)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.no_context = true
        params.single_segment = false

        // Set language (use stable pointer – withCString creates a dangling pointer)
        params.language = UnsafePointer(languageCStr)

        let result = samples.withUnsafeBufferPointer { buf in
            whisper_full(context, params, buf.baseAddress, Int32(buf.count))
        }

        guard result == 0 else {
            throw WhisperError.transcriptionFailed
        }

        // Collect all segments into a single string
        let segmentCount = whisper_full_n_segments(context)
        var text = ""

        for i in 0..<segmentCount {
            if let cStr = whisper_full_get_segment_text(context, i) {
                text += String(cString: cStr)
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
