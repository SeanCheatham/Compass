#!/bin/bash
set -euo pipefail

# Copy the freshly-built Debug app to /Applications so the Virtualization
# restore/install helper will accept connections from us.
#
# This is on by default for developer builds because VZ helper checks reject
# the same bundle from DerivedData. The destination defaults to
# /Applications/CompassLocal.app so debug builds never overwrite a real
# /Applications/Compass.app install.
#
# Two failure modes are at play, both with the same symptom (VZErrorDomain
# 10001 / 10004, "Installation service returned an unexpected error"):
#
#   1) The bundle path matters. The VZ install helper, via TCC, refuses callers
#      whose .app lives under ~/Library/Developer/Xcode/DerivedData/.
#
#   2) The launching parent matters. Even from /Applications, a process spawned
#      by Xcode/lldb via debugserver gets treated as a tools child and the
#      helper still rejects it. Launch the copied app via Finder/launchd.

if [[ "${CONFIGURATION:-}" != "Debug" ]]; then
  echo "Skipping /Applications debug copy for ${CONFIGURATION:-unknown} build"
  exit 0
fi

if [[ "${COMPASS_COPY_DEBUG_APP_TO_APPLICATIONS:-YES}" != "YES" ]]; then
  echo "Skipping /Applications debug copy; COMPASS_COPY_DEBUG_APP_TO_APPLICATIONS=${COMPASS_COPY_DEBUG_APP_TO_APPLICATIONS:-NO}"
  exit 0
fi

if [[ -z "${BUILT_PRODUCTS_DIR:-}" || -z "${WRAPPER_NAME:-}" ]]; then
  echo "error: Build settings are unavailable. Run this script as the Compass scheme post-build action." >&2
  exit 1
fi

SRC="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}"
DEST="${COMPASS_DEBUG_APP_PATH:-/Applications/CompassLocal.app}"

case "${DEST}" in
  /Applications/*.app) ;;
  *)
    echo "error: COMPASS_DEBUG_APP_PATH must be a .app bundle under /Applications for VZ helper testing: ${DEST}" >&2
    exit 1
    ;;
esac

if [[ ! -d "${SRC}" ]]; then
  echo "Skipping /Applications debug copy; built app is missing: ${SRC}"
  exit 0
fi

if [[ -e "${DEST}" && ! -w "${DEST}" ]]; then
  echo "error: ${DEST} is not writable. Choose another COMPASS_DEBUG_APP_PATH or fix permissions." >&2
  exit 1
fi

rm -rf "${DEST}"
ditto "${SRC}" "${DEST}"
echo "Copied ${WRAPPER_NAME} to ${DEST}"

LEGACY_DEST="/Applications/Compass.app"
if [[ "${DEST}" != "${LEGACY_DEST}" && -e "${LEGACY_DEST}" ]]; then
  echo "note: ${LEGACY_DEST} still exists; launch ${DEST} for local VZ testing."
fi
