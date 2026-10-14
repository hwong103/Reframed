#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SOURCES=(
  Reframed/Screenshot/OCRService.swift
  Reframed/Screenshot/OCRService+Ordering.swift
)

for source in "${SOURCES[@]}"; do
  if [[ ! -f "$REPO_ROOT/$source" ]]; then
    echo "missing source: $source" >&2
    exit 1
  fi
done

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ocr-line-order.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

PATHS=()
for source in "${SOURCES[@]}"; do
  PATHS+=("$REPO_ROOT/$source")
done
PATHS+=("$SCRIPT_DIR/ocr-line-order/main.swift")

echo "compiling OCR line order check" >&2
xcrun --sdk macosx swiftc -o "$BUILD_DIR/run" "${PATHS[@]}"

"$BUILD_DIR/run"
