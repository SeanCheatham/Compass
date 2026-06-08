#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${COMPASS_RUST_PROFILE:-release}"

cd "$ROOT"

if [[ "$PROFILE" == "debug" ]]; then
  cargo build -p compassd -p compass-engine
  TARGET_DIR="$ROOT/target/debug"
else
  cargo build -p compassd -p compass-engine --release
  TARGET_DIR="$ROOT/target/release"
fi

if [[ -n "${COMPASS_APP_BUNDLE:-}" ]]; then
  MACOS_DIR="$COMPASS_APP_BUNDLE/Contents/MacOS"
  mkdir -p "$MACOS_DIR"
  cp "$TARGET_DIR/compassd" "$MACOS_DIR/compassd"
  cp "$TARGET_DIR/compass-engine" "$MACOS_DIR/compass-engine"
fi

echo "Built Compass Rust binaries in $TARGET_DIR"
