#!/usr/bin/env bash
# Run the SwiftPM test suite (fast iteration; no app bundle / VM entitlements).
#
# Usage:
#   ./scripts/test-local.sh
#   ./scripts/test-local.sh --filter ForgeProfileTests

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--filter" && -n "${2:-}" ]]; then
  exec swift test --filter "${2}"
fi

exec swift test "$@"
