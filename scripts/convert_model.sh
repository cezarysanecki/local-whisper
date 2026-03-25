#!/usr/bin/env bash
#
# Convert bardsai/whisper-small-pl from HuggingFace format to GGML format
# for use with whisper.cpp.
#
# Prerequisites:
#   - Python 3.8+
#   - pip install torch numpy transformers
#   - git lfs install
#
# Usage:
#   ./scripts/convert_model.sh [output_dir]
#
# The output GGML model will be placed in models/ by default.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_DIR/models}"
WORK_DIR="$PROJECT_DIR/.model-conversion-tmp"

HF_MODEL="bardsai/whisper-small-pl"
OUTPUT_NAME="ggml-whisper-small-pl.bin"

echo "=== Local Whisper – Model Conversion ==="
echo ""
echo "This script converts $HF_MODEL to GGML format."
echo "Output: $OUTPUT_DIR/$OUTPUT_NAME"
echo ""

# Check Python dependencies
python3 -c "import torch, numpy, transformers" 2>/dev/null || {
    echo "ERROR: Missing Python dependencies. Install them with:"
    echo "  pip install torch numpy transformers"
    exit 1
}

# Check git-lfs
git lfs version >/dev/null 2>&1 || {
    echo "ERROR: git-lfs is required. Install with:"
    echo "  brew install git-lfs && git lfs install"
    exit 1
}

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# 1. Clone OpenAI whisper repo (needed for mel_filters.npz)
if [ ! -d "$WORK_DIR/whisper" ]; then
    echo ">>> Cloning openai/whisper (for mel_filters.npz)..."
    git clone --depth 1 https://github.com/openai/whisper "$WORK_DIR/whisper"
else
    echo ">>> openai/whisper already cloned, skipping."
fi

# 2. Clone whisper.cpp (for conversion script)
if [ ! -d "$WORK_DIR/whisper.cpp" ]; then
    echo ">>> Cloning whisper.cpp (for conversion script)..."
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp "$WORK_DIR/whisper.cpp"
else
    echo ">>> whisper.cpp already cloned, skipping."
fi

# 3. Clone the HuggingFace model
if [ ! -d "$WORK_DIR/whisper-small-pl" ]; then
    echo ">>> Cloning $HF_MODEL from HuggingFace (this may take a while)..."
    git clone "https://huggingface.co/$HF_MODEL" "$WORK_DIR/whisper-small-pl"
else
    echo ">>> $HF_MODEL already cloned, skipping."
fi

# 4. Run conversion
echo ">>> Converting to GGML format (f16)..."
python3 "$WORK_DIR/whisper.cpp/models/convert-h5-to-ggml.py" \
    "$WORK_DIR/whisper-small-pl" \
    "$WORK_DIR/whisper" \
    "$OUTPUT_DIR"

# 5. Rename output
if [ -f "$OUTPUT_DIR/ggml-model.bin" ]; then
    mv "$OUTPUT_DIR/ggml-model.bin" "$OUTPUT_DIR/$OUTPUT_NAME"
fi

echo ""
echo "=== Done! ==="
echo "Model saved to: $OUTPUT_DIR/$OUTPUT_NAME"
echo ""
echo "You can now clean up temporary files with:"
echo "  rm -rf $WORK_DIR"
