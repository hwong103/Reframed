#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ocr-runtime-fallback.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "compiling OCR runtime fallback check" >&2
xcrun --sdk macosx swiftc -o "$BUILD_DIR/run" \
  "$REPO_ROOT/Reframed/Screenshot/OCRService.swift" \
  "$REPO_ROOT/Reframed/Screenshot/OCRService+Ordering.swift" \
  "$SCRIPT_DIR/ocr-runtime-fallback/main.swift"

"$BUILD_DIR/run"
