import SwiftUI

/// Main view: a record button and a text area showing transcription results.
public struct ContentView: View {

    @State private var viewModel: TranscriptionViewModel

    public init(modelPath: String) {
        _viewModel = State(initialValue: TranscriptionViewModel(modelPath: modelPath))
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Transcription output
            GroupBox("Transkrypcja") {
                ScrollView {
                    Text(viewModel.transcribedText.isEmpty ? "Nacisnij przycisk i zacznij mowic..." : viewModel.transcribedText)
                        .foregroundStyle(viewModel.transcribedText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }

            // Status + record button
            VStack(spacing: 12) {
                statusView

                HStack(spacing: 12) {
                    Button(action: { viewModel.toggleRecording() }) {
                        Label(buttonTitle, systemImage: buttonIcon)
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(buttonTint)
                    .disabled(viewModel.state == .transcribing)
                    .keyboardShortcut(.space, modifiers: [])

                    Button(action: { viewModel.playRecordedAudio() }) {
                        Label("Odtwórz", systemImage: "play.circle")
                            .font(.title3)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canPlayback)
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 350)
        .onAppear {
            viewModel.requestMicrophoneAccess()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .recording:
            Label("Nagrywanie...", systemImage: "waveform")
                .foregroundStyle(.red)
                .font(.callout)
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Transkrypcja w toku...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.callout)
        }
    }

    // MARK: - Computed

    private var buttonTitle: String {
        switch viewModel.state {
        case .idle, .error: "Nagrywaj"
        case .recording: "Zatrzymaj"
        case .transcribing: "Przetwarzanie..."
        }
    }

    private var buttonIcon: String {
        switch viewModel.state {
        case .idle, .error: "mic"
        case .recording: "stop.circle"
        case .transcribing: "brain"
        }
    }

    private var buttonTint: Color {
        switch viewModel.state {
        case .idle, .error: .blue
        case .recording: .red
        case .transcribing: .gray
        }
    }
}
