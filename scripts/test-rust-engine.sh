#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo test -p compass-engine
cargo clippy -p compass-engine -- -D warnings
