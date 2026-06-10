#!/usr/bin/env bash
# Build and sign compass-cli for Apple Containerization.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

CONFIGURATION="${CONFIGURATION:-debug}"
ENTITLEMENTS="${ROOT}/App/CompassCLI.entitlements"
BINARY="${ROOT}/.build/${CONFIGURATION}/compass-cli"
IDENTITY="${COMPASS_CLI_SIGN_IDENTITY:--}"

swift build -c "${CONFIGURATION}" --product compass-cli

if [[ ! -x "${BINARY}" ]]; then
  echo "error: expected built compass-cli at ${BINARY}" >&2
  exit 1
fi

codesign --force --sign "${IDENTITY}" --entitlements "${ENTITLEMENTS}" "${BINARY}"

if ! codesign -d --entitlements - "${BINARY}" 2>/dev/null \
  | /usr/bin/grep -q "com.apple.security.virtualization"; then
  cat >&2 <<EOF
error: signed compass-cli is missing com.apple.security.virtualization.

Apple Containerization requires the Virtualization entitlement. Re-run this
script, or set COMPASS_CLI_SIGN_IDENTITY to a signing identity that can carry
App/CompassCLI.entitlements.
EOF
  exit 1
fi

echo "${BINARY}"
