#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
OUTPUT="$PROJECT_DIR/build/NEON_RUN_AFTERLIGHT.apk"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "Godot 4.7.2 was not found. Set GODOT_BIN to its executable." >&2
  exit 2
fi
mkdir -p "$PROJECT_DIR/build"
"$GODOT_BIN" --headless --editor --path "$PROJECT_DIR" --import
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-debug Android "$OUTPUT"
echo "APK exported to: $OUTPUT"
