#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <baseline-compass-dir> <actual-compass-dir>" >&2
  exit 64
fi

BASELINE="$1"
ACTUAL="$2"

if [[ ! -d "$BASELINE" ]]; then
  echo "baseline directory does not exist: $BASELINE" >&2
  exit 66
fi

if [[ ! -d "$ACTUAL" ]]; then
  echo "actual directory does not exist: $ACTUAL" >&2
  exit 66
fi

diff -ru --exclude '*.log' --exclude '.DS_Store' "$BASELINE" "$ACTUAL"
