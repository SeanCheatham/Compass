#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <fixture-dir>" >&2
  exit 64
fi

FIXTURE_DIR="$1"
if [[ ! -d "$FIXTURE_DIR" ]]; then
  echo "fixture directory does not exist: $FIXTURE_DIR" >&2
  exit 66
fi

if [[ ! -f "$FIXTURE_DIR/config.json" ]]; then
  echo "fixture is missing config.json: $FIXTURE_DIR" >&2
  exit 66
fi

cargo test -p compass-core --test agent_tools
echo "Agent fixture harness placeholder ready for: $FIXTURE_DIR"
