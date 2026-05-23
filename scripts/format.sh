#!/usr/bin/env bash
# Run swift-format across the Compass codebase.
#
#   ./scripts/format.sh         # rewrite files in place
#   ./scripts/format.sh --lint  # report violations without modifying files

set -euo pipefail

cd "$(dirname "$0")/.."

TARGETS=(Sources Tests Package.swift)

if [[ "${1:-}" == "--lint" ]]; then
    exec swift format lint --strict --parallel --recursive "${TARGETS[@]}"
else
    exec swift format --in-place --parallel --recursive "${TARGETS[@]}"
fi
