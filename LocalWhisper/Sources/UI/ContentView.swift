import SwiftUI

/// Main view: large circular mic button, with transcription result sliding in after processing.
public struct ContentView: View {

    @State private var viewModel: TranscriptionViewModel
    @State private var copied = false
    @State private var showSettings = false

    public init(modelPath: String) {
        _viewModel = State(initialValue: TranscriptionViewModel(modelPath: modelPath))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top bar with settings
            HStack {
                Spacer()
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings, arrowEdge: .top) {
                    settingsPanel
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Spacer()

            // Transcription result (slides in when available)
            if !viewModel.transcribedText.isEmpty && viewModel.state != .recording {
                transcriptionCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 32)
            }

            // Status label
            statusLabel
                .padding(.bottom, 16)

            // Main mic button
            micButton
                .padding(.bottom, 8)

            // Hint
            Text("Spacja aby nagrywać")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
                .frame(height: 32)
        }
        .frame(minWidth: 360, idealWidth: 400, minHeight: 400, idealHeight: 500)
        .background(.background)
        .animation(.easeInOut(duration: 0.3), value: viewModel.state)
        .animation(.easeInOut(duration: 0.3), value: viewModel.transcribedText)
        .onAppear {
            viewModel.requestMicrophoneAccess()
        }
    }

    // MARK: - Mic Button

    private var micButton: some View {
        Button(action: { viewModel.toggleRecording() }) {
            ZStack {
                // Pulse ring when recording
                if viewModel.state == .recording {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: viewModel.state
                        )
                }

                // Button circle
                Circle()
                    .fill(buttonColor.gradient)
                    .frame(width: 80, height: 80)
                    .shadow(color: buttonColor.opacity(0.4), radius: 12, y: 4)

                // Icon
                Image(systemName: buttonIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.state == .transcribing)
        .keyboardShortcut(.space, modifiers: [])
    }

    // MARK: - Transcription Card

    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(viewModel.transcribedText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)

            HStack {
                Spacer()

                if viewModel.debugPlayback {
                    Button(action: { viewModel.playRecordedAudio() }) {
                        Label("Odtwórz", systemImage: "play.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!viewModel.canPlayback)
                }

                Button(action: copyToClipboard) {
                    Label(copied ? "Skopiowano!" : "Kopiuj", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(copied ? .green : .accentColor)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Status Label

    @ViewBuilder
    private var statusLabel: some View {
        switch viewModel.state {
        case .idle:
            Text(viewModel.transcribedText.isEmpty ? "Naciśnij aby nagrać" : "Gotowe")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .recording:
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Nagrywanie...")
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Przetwarzanie...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(2)
                .padding(.horizontal)
        }
    }

    // MARK: - Settings Panel

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ustawienia")
                .font(.headline)

            Toggle("Odtwarzanie nagrania", isOn: $viewModel.debugPlayback)
                .font(.body)

            Text("Pozwala odsłuchać nagranie przed transkrypcją.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 260)
    }

    // MARK: - Helpers

    private var buttonIcon: String {
        switch viewModel.state {
        case .idle, .error: "mic"
        case .recording: "stop.fill"
        case .transcribing: "ellipsis"
        }
    }

    private var buttonColor: Color {
        switch viewModel.state {
        case .idle, .error: .blue
        case .recording: .red
        case .transcribing: .gray
        }
    }

    private var pulseScale: CGFloat {
        viewModel.state == .recording ? 1.3 : 1.0
    }

    private var pulseOpacity: Double {
        viewModel.state == .recording ? 0.0 : 0.6
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.transcribedText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
