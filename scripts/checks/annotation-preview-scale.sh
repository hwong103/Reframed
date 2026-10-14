#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SOURCES=(
  Reframed/Annotation/AnnotationCanvasView.swift
  Reframed/Annotation/AnnotationCanvasView+Drawing.swift
  Reframed/Annotation/AnnotationCanvasView+Geometry.swift
  Reframed/Annotation/AnnotationCanvasView+Interaction.swift
  Reframed/Annotation/AnnotationCanvasView+Text.swift
  Reframed/Annotation/AnnotationCanvasView+Viewport.swift
  Reframed/Annotation/AnnotationCanvasView+DragCompose.swift
  Reframed/Annotation/AnnotationCommandStack.swift
  Reframed/Annotation/AnnotationDocument.swift
  Reframed/Annotation/AnnotationEditorModel.swift
  Reframed/Annotation/AnnotationItem.swift
  Reframed/Annotation/AnnotationPresets.swift
  Reframed/Annotation/AnnotationRenderer.swift
  Reframed/Annotation/AnnotationRenderer+Beautify.swift
  Reframed/Annotation/AnnotationRenderer+Effects.swift
  Reframed/Annotation/AnnotationRenderer+Shapes.swift
  Reframed/Annotation/BeautifyStyle.swift
  Reframed/Compositor/BackgroundStyle.swift
  Reframed/Compositor/GradientPresets.swift
  Reframed/Utilities/CodableColor.swift
)

for source in "${SOURCES[@]}"; do
  if [[ ! -f "$REPO_ROOT/$source" ]]; then
    echo "missing source: $source" >&2
    exit 1
  fi
done

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/annotation-preview-scale.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

PATHS=()
for source in "${SOURCES[@]}"; do
  PATHS+=("$REPO_ROOT/$source")
done
PATHS+=("$SCRIPT_DIR/annotation-preview-scale/main.swift")

echo "compiling annotation preview scale check" >&2
xcrun --sdk macosx swiftc -o "$BUILD_DIR/run" "${PATHS[@]}"

"$BUILD_DIR/run"
