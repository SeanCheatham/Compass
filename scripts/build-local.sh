#!/usr/bin/env bash
# Build CompassLocal via xcodebuild and copy to /Applications.
#
# Shared VM work needs the signed Xcode app bundle (Virtualization entitlement).
# Pure `swift build` / `swift run` is fine for tests and non-VM work only.
#
# Usage:
#   ./scripts/build-local.sh          # incremental Debug build + copy
#   ./scripts/build-local.sh --clean  # wipe DerivedData/ first
#
# Team id: set COMPASS_DEVELOPMENT_TEAM or App/LocalSigning.xcconfig
# (see App/LocalSigning.example.xcconfig).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

DERIVED_DATA="${ROOT}/DerivedData"
CONFIGURATION="Debug"
DEST="${COMPASS_DEBUG_APP_PATH:-/Applications/CompassLocal.app}"
CLEAN=0

usage() {
  cat >&2 <<USAGE
Usage: $(basename "$0") [--clean]

  Build Compass with xcodebuild and copy the Debug app to:
    ${DEST}

  Options:
    --clean   Remove ${DERIVED_DATA} before building
    -h, --help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

read_team() {
  if [[ -n "${COMPASS_DEVELOPMENT_TEAM:-}" ]]; then
    echo "${COMPASS_DEVELOPMENT_TEAM}"
    return
  fi
  local file="${ROOT}/App/LocalSigning.xcconfig"
  if [[ -f "${file}" ]]; then
    awk -F= '/^[[:space:]]*COMPASS_DEVELOPMENT_TEAM[[:space:]]*=/ {
      sub(/^[[:space:]]+/, "", $2)
      sub(/[[:space:]]+$/, "", $2)
      print $2
      exit
    }' "${file}"
  fi
}

TEAM="$(read_team || true)"
if [[ -z "${TEAM}" ]]; then
  cat >&2 <<EOF
error: no development team configured.

  export COMPASS_DEVELOPMENT_TEAM=YOUR_TEAM_ID
  # or copy App/LocalSigning.example.xcconfig → App/LocalSigning.xcconfig
EOF
  exit 1
fi

if [[ "${CLEAN}" -eq 1 ]]; then
  echo "Removing ${DERIVED_DATA}"
  rm -rf "${DERIVED_DATA}"
fi

echo "Building Compass (Debug) → ${DEST}"
xcodebuild \
  -project "${ROOT}/Compass.xcodeproj" \
  -scheme Compass \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  COMPASS_DEVELOPMENT_TEAM="${TEAM}" \
  build

PRODUCTS_DIR="${DERIVED_DATA}/Build/Products/${CONFIGURATION}"
BUILT_APP="${PRODUCTS_DIR}/Compass.app"
if [[ ! -d "${BUILT_APP}" ]]; then
  echo "error: build finished but ${BUILT_APP} is missing" >&2
  exit 1
fi

BUILT_PRODUCTS_DIR="${PRODUCTS_DIR}" \
  WRAPPER_NAME="Compass.app" \
  CONFIGURATION="${CONFIGURATION}" \
  COMPASS_DEBUG_APP_PATH="${DEST}" \
  bash "${ROOT}/scripts/copy-debug-app-to-applications.sh"

DYLIB="${DEST}/Contents/MacOS/Compass.debug.dylib"
if [[ -f "${DYLIB}" ]]; then
  echo "Installed: ${DEST}"
  echo "  $(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${DYLIB}")  Compass.debug.dylib"
else
  echo "Installed: ${DEST}"
fi
