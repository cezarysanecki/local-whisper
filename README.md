# Local Whisper

A native macOS app that transcribes spoken Polish fully offline. It runs the [bardsai/whisper-small-pl](https://huggingface.co/bardsai/whisper-small-pl) model locally through [whisper.cpp](https://github.com/ggerganov/whisper.cpp). The interface is in Polish 🇵🇱 PL.

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 16 or newer (or the Command Line Tools)
- Python 3.8 or newer, to convert the model
- about 500 MB of disk space for the model

## Quick start

### 1. Download the whisper.cpp XCFramework

```bash
# Download from the whisper.cpp releases page (v1.8.4)
curl -L -o /tmp/whisper-xcframework.zip \
  https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.4/whisper-v1.8.4-xcframework.zip

# Unpack into the project
mkdir -p LocalWhisper/Frameworks
unzip /tmp/whisper-xcframework.zip -d LocalWhisper/Frameworks
mv LocalWhisper/Frameworks/build-apple/whisper.xcframework LocalWhisper/Frameworks/
rm -rf LocalWhisper/Frameworks/build-apple
```

### 2. Convert the model

```bash
# Python dependencies
pip install torch numpy transformers

# git-lfs, if you do not have it
brew install git-lfs && git lfs install

# Conversion
./scripts/convert_model.sh
```

The script downloads `bardsai/whisper-small-pl` from Hugging Face and converts it to GGML. The result is `models/ggml-whisper-small-pl.bin` (about 466 MB).

### 3. Install as a macOS app

```bash
./scripts/install.sh
```

The script builds a release binary, packs it into `Local Whisper.app` together with the model and the framework, and installs it in `/Applications/`. After that it starts like any other app, from Launchpad, Spotlight or the Dock.

A different location:
```bash
./scripts/install.sh ~/Desktop
```

### Alternative: run from the terminal without installing

```bash
swift build
swift run LocalWhisper
```

Or open it in Xcode:
```bash
open Package.swift
```

## Usage

1. Click the microphone button or press `Space`.
2. Speak Polish.
3. Click the button again (or press `Space`) to stop.
4. Wait for the transcription. The first run loads the model, which can take a few seconds.
5. The text appears in the text field, ready to copy.

## Architecture

```
App (entry point)
 └── UI (SwiftUI: ContentView + ViewModel)
      ├── Audio (AVAudioEngine, 16 kHz mono Float32)
      └── Transcription (whisper.cpp C API wrapper)
```

The **Audio** and **Transcription** modules do not depend on SwiftUI, so they can be reused, for example in:
- a menu bar app,
- a daemon with a global keyboard shortcut,
- a CLI tool.

## Environment variables

| Variable | Description |
|---|---|
| `WHISPER_MODEL_PATH` | Overrides the default path to the GGML model |

## Security

### Sandbox

The app runs **without the sandbox** (`com.apple.security.app-sandbox = false`). This is deliberate: the sandbox would block direct access to the model on disk, running `afplay` for debug playback, and a future global keyboard shortcut (`NSEvent.addGlobalMonitorForEvents`).

That is acceptable because the app:
- works only locally, with no network access,
- processes no user data other than audio recordings,
- removes temporary files on start and on exit.

Distribution through the App Store would require turning the sandbox on and adapting the architecture.

### Audio data

- Temporary files have `0600` permissions (owner only).
- Audio samples are zeroed after transcription (`memset` and `removeAll`).
- The temporary directory is cleaned on start, on exit and on SIGTERM.

## Plans

- [ ] Menu bar app with a global shortcut (for example `⌥ + Space`)
- [ ] Pasting the transcription into the active app
- [ ] Streaming, real-time transcription
- [ ] More languages

## License

MIT, see [`LICENSE`](LICENSE).
