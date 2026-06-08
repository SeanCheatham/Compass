#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SCENARIO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      SCENARIO="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

if [[ -z "$SCENARIO" ]]; then
  echo "usage: $0 --scenario <name>" >&2
  exit 64
fi

SCENARIO_DIR="$ROOT/tests/tournament_replay/scenarios/$SCENARIO"
if [[ ! -d "$SCENARIO_DIR" ]]; then
  echo "missing replay scenario: $SCENARIO_DIR" >&2
  echo "Add commands.jsonl and expected_final.json before enabling this replay." >&2
  exit 66
fi

cargo test -p compass-core --test tournament_store
echo "Replay harness placeholder ready for scenario: $SCENARIO"
