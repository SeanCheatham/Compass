#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo build --release -p compass-engine
printf '%s\n' "$PWD/target/release/compass-engine"
