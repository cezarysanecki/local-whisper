import SwiftUI
import UI

@main
struct LocalWhisperApp: App {

    /// Path to the GGML model file.
    /// Looks for the model in the `models/` directory relative to the executable,
    /// or falls back to a hardcoded path for development.
    private let modelPath: String = {
        // 1. Check environment variable (useful for dev/testing)
        if let envPath = ProcessInfo.processInfo.environment["WHISPER_MODEL_PATH"],
           FileManager.default.fileExists(atPath: envPath) {
            return envPath
        }

        // 2. Check models/ directory relative to the repo root
        // When running via `swift run`, the working directory is the repo root
        let repoModelsPath = "models/ggml-whisper-small-pl.bin"
        if FileManager.default.fileExists(atPath: repoModelsPath) {
            return repoModelsPath
        }

        // 3. Check next to the executable
        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let execDir = executableURL.deletingLastPathComponent()
        let execModelsPath = execDir.appendingPathComponent("models/ggml-whisper-small-pl.bin").path
        if FileManager.default.fileExists(atPath: execModelsPath) {
            return execModelsPath
        }

        // 4. Fallback – will show an error in the UI when transcription is attempted
        return repoModelsPath
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(modelPath: modelPath)
        }
        .windowResizability(.contentSize)
    }
}
