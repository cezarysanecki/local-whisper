import SwiftUI
import UI

@main
struct LocalWhisperApp: App {

    /// Path to the GGML model file.
    /// Looks for the model in the `models/` directory relative to the executable,
    /// or falls back to a hardcoded path for development.
    private static let modelFileName = "ggml-whisper-small-pl.bin"

    private let modelPath: String = {
        let fm = FileManager.default

        // 1. Check environment variable (useful for dev/testing)
        if let envPath = ProcessInfo.processInfo.environment["WHISPER_MODEL_PATH"],
           fm.fileExists(atPath: envPath) {
            return envPath
        }

        // 2. Check models/ relative to the executable (covers swift run & open)
        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let execDir = executableURL.deletingLastPathComponent()

        // Walk up from the executable to find the repo root with models/ dir.
        // swift run places the binary in .build/arm64-apple-macosx/debug/
        var searchDir = execDir
        for _ in 0..<5 {
            let candidate = searchDir.appendingPathComponent("models/\(modelFileName)").path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
            searchDir = searchDir.deletingLastPathComponent()
        }

        // 3. Check models/ relative to the current working directory
        let cwdPath = fm.currentDirectoryPath + "/models/\(modelFileName)"
        if fm.fileExists(atPath: cwdPath) {
            return cwdPath
        }

        // 4. Fallback – will show an error in the UI when transcription is attempted
        return cwdPath
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(modelPath: modelPath)
        }
        .windowResizability(.contentSize)
    }
}
