#!/usr/bin/env bash
# Run Rust checks for the Compass engine bridge.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${ROOT}/rust/compass-engine/Cargo.toml"

cargo fmt --manifest-path "${MANIFEST}" -- --check
cargo clippy --manifest-path "${MANIFEST}" --all-targets -- -D warnings
cargo test --manifest-path "${MANIFEST}" --all-targets
