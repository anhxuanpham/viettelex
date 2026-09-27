#!/bin/sh
# Tải encoder FUTO Swipe từ Hugging Face (kiểm sha256), chuyển sang futoswipe.bin (fp16) cho iOS +
# Android, sinh lại fixture parity. Chỉ python3 stdlib + curl. Chạy từ gốc repo:
#   sh Scripts/futo-swipe/build.sh
# Weights: FUTO Model Weights License 1.0 (docs/DATA-SOURCES.md mục FUTO Swipe).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="${TMPDIR:-/tmp}/futo-swipe-build"
mkdir -p "$TMP"
URL="https://huggingface.co/futo-org/futo-swipe/resolve/18328c3042b066952c0936b3771d492fe2ec289a/honorable_sturgeon/model_fp32.pte"
SHA="725242bab5d14345e96ff214e8de2bfbc1f962c232d320df9c24cb82ffd1fbaf"
PTE="$TMP/model_fp32.pte"
[ -f "$PTE" ] || curl -sfL -o "$PTE" "$URL"
echo "$SHA  $PTE" | shasum -a 256 -c -
cd "$HERE"
python3 convert.py "$PTE" "$TMP/futoswipe.bin" | head -1
python3 verify.py "$PTE" "$TMP/futoswipe.bin"
cp "$TMP/futoswipe.bin" "$ROOT/iOS/Keyboard/Resources/futoswipe.bin"
cp "$TMP/futoswipe.bin" "$ROOT/android/app/src/main/assets/futoswipe.bin"
python3 gen_fixture.py "$TMP/futoswipe.bin" "$ROOT/iOS/KeyboardTests/Fixtures/swipe-paths.txt" \
    "$ROOT/iOS/KeyboardTests/Fixtures/futo-swipe-fixture.txt"
rm -rf "$HERE/__pycache__"
shasum -a 256 "$ROOT/iOS/Keyboard/Resources/futoswipe.bin"
