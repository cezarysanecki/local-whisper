// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalWhisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LocalWhisper", targets: ["LocalWhisper"])
    ],
    targets: [
        .executableTarget(
            name: "LocalWhisper",
            dependencies: [
                "Audio",
                "Transcription",
                "UI"
            ],
            path: "LocalWhisper/Sources/App"
        ),
        .target(
            name: "Audio",
            path: "LocalWhisper/Sources/Audio"
        ),
        .target(
            name: "Transcription",
            dependencies: ["WhisperFramework"],
            path: "LocalWhisper/Sources/Transcription"
        ),
        .target(
            name: "UI",
            dependencies: ["Audio", "Transcription"],
            path: "LocalWhisper/Sources/UI"
        ),
        .binaryTarget(
            name: "WhisperFramework",
            path: "LocalWhisper/Frameworks/whisper.xcframework"
        )
    ]
)
