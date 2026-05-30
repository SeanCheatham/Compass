#!/usr/bin/env bash
# Build (optional) and launch CompassLocal from /Applications.
#
# Usage:
#   ./scripts/run-local.sh              # build + open
#   ./scripts/run-local.sh --no-build   # open existing install only
#   ./scripts/run-local.sh --build-only # build + copy, do not launch
#
# Pass --clean through to build-local.sh:
#   ./scripts/run-local.sh --clean

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${COMPASS_DEBUG_APP_PATH:-/Applications/CompassLocal.app}"

BUILD=1
OPEN=1
CLEAN=0

usage() {
  cat >&2 <<USAGE
Usage: $(basename "$0") [--no-build | --build-only] [--clean]

  --no-build    Skip build; launch ${DEST} as-is
  --build-only  Build and copy only; do not launch
  --clean       Pass --clean to build-local.sh
  -h, --help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) BUILD=0 ;;
    --build-only) OPEN=0 ;;
    --clean) CLEAN=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "${BUILD}" -eq 1 ]]; then
  if [[ "${CLEAN}" -eq 1 ]]; then
    bash "${ROOT}/scripts/build-local.sh" --clean
  else
    bash "${ROOT}/scripts/build-local.sh"
  fi
fi

if [[ ! -d "${DEST}" ]]; then
  echo "error: ${DEST} not found; run without --no-build first" >&2
  exit 1
fi

if [[ "${OPEN}" -eq 1 ]]; then
  echo "Launching ${DEST}"
  open "${DEST}"
fi
