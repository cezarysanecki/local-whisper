# Local Whisper

Natywna aplikacja macOS do transkrypcji polskiego języka mówionego, działająca w pełni offline. Używa modelu [bardsai/whisper-small-pl](https://huggingface.co/bardsai/whisper-small-pl) uruchamianego lokalnie przez [whisper.cpp](https://github.com/ggerganov/whisper.cpp).

## Wymagania

- macOS 14+ (Sonoma)
- Xcode 16+ (lub Command Line Tools)
- Python 3.8+ (do konwersji modelu)
- ~500 MB wolnego miejsca na dysku (model)

## Szybki start

### 1. Pobierz XCFramework whisper.cpp

```bash
# Pobierz ze strony releases whisper.cpp (v1.8.4)
curl -L -o /tmp/whisper-xcframework.zip \
  https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.4/whisper-v1.8.4-xcframework.zip

# Rozpakuj do projektu
mkdir -p LocalWhisper/Frameworks
unzip /tmp/whisper-xcframework.zip -d LocalWhisper/Frameworks
mv LocalWhisper/Frameworks/build-apple/whisper.xcframework LocalWhisper/Frameworks/
rm -rf LocalWhisper/Frameworks/build-apple
```

### 2. Skonwertuj model

```bash
# Zainstaluj zależności Pythona
pip install torch numpy transformers

# Zainstaluj git-lfs (jeśli nie masz)
brew install git-lfs && git lfs install

# Uruchom skrypt konwersji
./scripts/convert_model.sh
```

Skrypt pobiera `bardsai/whisper-small-pl` z HuggingFace i konwertuje do formatu GGML. Wynikowy plik: `models/ggml-whisper-small-pl.bin` (~466 MB).

### 3. Zbuduj i uruchom

```bash
swift build
swift run LocalWhisper
```

Lub otwórz w Xcode:
```bash
open Package.swift
```

## Użytkowanie

1. Kliknij **Nagrywaj** (lub naciśnij `Spacja`)
2. Mów po polsku
3. Kliknij **Zatrzymaj**
4. Poczekaj na transkrypcję (pierwsze uruchomienie ładuje model, może potrwać kilka sekund)
5. Tekst pojawi się w polu tekstowym

## Architektura

```
App (entry point)
 └── UI (SwiftUI: ContentView + ViewModel)
      ├── Audio (AVAudioEngine, 16kHz mono Float32)
      └── Transcription (whisper.cpp C API wrapper)
```

Moduły **Audio** i **Transcription** nie zależą od SwiftUI – mogą być użyte niezależnie, np. w:
- aplikacji menu bar
- daemonie z globalnym skrótem klawiszowym
- narzędziu CLI

## Zmienne środowiskowe

| Zmienna | Opis |
|---|---|
| `WHISPER_MODEL_PATH` | Nadpisuje domyślną ścieżkę do modelu GGML |

## Przyszłe plany

- [ ] Menu bar app z globalnym skrótem klawiszowym (np. `⌥ + Space`)
- [ ] Automatyczne wklejanie transkrypcji do aktywnej aplikacji
- [ ] Streaming – transkrypcja w czasie rzeczywistym
- [ ] Obsługa wielu języków
