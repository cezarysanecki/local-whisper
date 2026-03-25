import SwiftUI
import Audio
import Transcription

/// Connects AudioRecorder and WhisperTranscriber to the UI.
///
/// This is the only place where Audio and Transcription modules meet.
/// In the future, a menu-bar / global-hotkey controller can use the same
/// AudioRecorder + WhisperTranscriber without touching this class.
@MainActor
@Observable
public final class TranscriptionViewModel {

    // MARK: - Public state

    public enum State: Equatable {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    public private(set) var state: State = .idle
    public private(set) var transcribedText: String = ""
    public private(set) var hasSamples: Bool = false

    /// Set to `true` to show the playback button in the UI (for debugging audio capture).
    public var debugPlayback: Bool = false

    /// Whether the last recording can be played back.
    public var canPlayback: Bool {
        debugPlayback && hasSamples && state == .idle
    }

    // MARK: - Private

    private let recorder = AudioRecorder()
    private var transcriber: WhisperTranscriber?
    private let modelPath: String

    // MARK: - Init

    public init(modelPath: String) {
        self.modelPath = modelPath
    }

    // MARK: - Public API

    /// Request microphone permission. Call on app appear.
    public func requestMicrophoneAccess() {
        Task {
            let granted = await AudioRecorder.requestPermission()
            if !granted {
                state = .error("Microphone access denied. Grant permission in System Settings > Privacy & Security > Microphone.")
            }
        }
    }

    /// Play back the last recording through speakers (debugging aid).
    public func playRecordedAudio() {
        do {
            try recorder.playRecordedAudio()
        } catch {
            state = .error("Playback failed: \(error.localizedDescription)")
        }
    }

    /// Toggle recording: if idle, start recording; if recording, stop and transcribe.
    public func toggleRecording() {
        switch state {
        case .idle, .error:
            startRecording()
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            break // ignore taps while transcribing
        }
    }

    // MARK: - Private

    private func startRecording() {
        do {
            hasSamples = false
            try recorder.startRecording()
            state = .recording
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    private func stopAndTranscribe() {
        let samples = recorder.stopRecording()
        hasSamples = !samples.isEmpty
        state = .transcribing

        guard !samples.isEmpty else {
            state = .error("No audio recorded")
            return
        }

        Task.detached { [modelPath] in
            do {
                // Lazy-init transcriber on first use (model loading is slow)
                let transcriber: WhisperTranscriber
                if let existing = await self.transcriber {
                    transcriber = existing
                } else {
                    transcriber = try WhisperTranscriber(modelPath: modelPath)
                    await MainActor.run { self.transcriber = transcriber }
                }

                let text = try transcriber.transcribe(samples: samples)

                await MainActor.run {
                    self.transcribedText = text
                    self.state = .idle
                    // Clear audio data from memory if playback is not needed
                    if !self.debugPlayback {
                        self.recorder.clearSamples()
                        self.hasSamples = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }
}
