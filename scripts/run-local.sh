#!/usr/bin/env bash
# Build and launch Compass through the local SwiftPM app-bundle path.
#
# Usage:
#   ./scripts/run-local.sh              # build + open dist/Compass.app
#   ./scripts/run-local.sh --no-build   # open existing dist/Compass.app only
#   ./scripts/run-local.sh --build-only # build dist/Compass.app, do not launch
#
# Pass --signed to use the legacy Xcode-signed /Applications path for
# Virtualization helper debugging:
#   ./scripts/run-local.sh --signed

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_APP="${ROOT}/dist/Compass.app"
SIGNED_DEST="${COMPASS_DEBUG_APP_PATH:-/Applications/CompassLocal.app}"

BUILD=1
OPEN=1
CLEAN=0
SIGNED=0

usage() {
  cat >&2 <<USAGE
Usage: $(basename "$0") [--no-build | --build-only] [--clean] [--signed]

  --no-build    Skip build; launch ${LOCAL_APP} as-is
  --build-only  Build and copy only; do not launch
  --clean       Remove local SwiftPM build outputs before building
  --signed      Use legacy Xcode build copied to ${SIGNED_DEST}
  -h, --help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) BUILD=0 ;;
    --build-only) OPEN=0 ;;
    --clean) CLEAN=1 ;;
    --signed) SIGNED=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "${SIGNED}" -eq 1 ]]; then
  if [[ "${CLEAN}" -eq 1 ]]; then
    bash "${ROOT}/scripts/build-local.sh" --clean
  elif [[ "${BUILD}" -eq 1 ]]; then
    bash "${ROOT}/scripts/build-local.sh"
  fi

  if [[ ! -d "${SIGNED_DEST}" ]]; then
    echo "error: ${SIGNED_DEST} not found; run without --no-build first" >&2
    exit 1
  fi

  if [[ "${OPEN}" -eq 1 ]]; then
    echo "Launching ${SIGNED_DEST}"
    open "${SIGNED_DEST}"
  fi
  exit 0
fi

if [[ "${CLEAN}" -eq 1 ]]; then
  rm -rf "${ROOT}/.build" "${ROOT}/dist"
fi

if [[ "${BUILD}" -eq 1 ]]; then
  if [[ "${OPEN}" -eq 1 ]]; then
    exec "${ROOT}/script/build_and_run.sh"
  fi
  exec "${ROOT}/script/build_and_run.sh" --build-only
fi

if [[ ! -d "${LOCAL_APP}" ]]; then
  echo "error: ${LOCAL_APP} not found; run without --no-build first" >&2
  exit 1
fi

if [[ "${OPEN}" -eq 1 ]]; then
  echo "Launching ${LOCAL_APP}"
  open -n "${LOCAL_APP}"
fi
