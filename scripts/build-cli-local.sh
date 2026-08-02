#!/usr/bin/env bash
# Build and sign compass-cli for Apple Containerization.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

CONFIGURATION="${CONFIGURATION:-debug}"
ENTITLEMENTS="${ROOT}/App/CompassCLI.entitlements"
BINARY="${ROOT}/.build/${CONFIGURATION}/compass-cli"
IDENTITY="${COMPASS_CLI_SIGN_IDENTITY:--}"
XCODE_CONFIGURATION="${XCODE_CONFIGURATION:-Debug}"

swift build -c "${CONFIGURATION}" --product compass-cli
# The embedded macOS VM guest agent must sit next to compass-cli so
# SharedCompassVM can plant it into the guest at provisioning time.
swift build -c "${CONFIGURATION}" --product CompassGuestAgent

BIN_DIR="$(cd "$(dirname "${BINARY}")" && pwd)"
SWIFTPM_BIN_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"

if [[ ! -x "${BINARY}" ]]; then
  echo "error: expected built compass-cli at ${BINARY}" >&2
  exit 1
fi

find_mlx_metallib() {
  local candidate
  for candidate in \
    "${BIN_DIR}/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "${SWIFTPM_BIN_DIR}/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "${ROOT}/DerivedData/Build/Products/${XCODE_CONFIGURATION}/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "${ROOT}/DerivedData/Build/Products/${XCODE_CONFIGURATION}/Compass.app/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
  do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

METALLIB_SOURCE="$(find_mlx_metallib || true)"
if [[ -z "${METALLIB_SOURCE}" ]]; then
  echo "Building Xcode resources for MLX metallib..."
  xcodebuild \
    -project "${ROOT}/Compass.xcodeproj" \
    -scheme Compass \
    -configuration "${XCODE_CONFIGURATION}" \
    -derivedDataPath "${ROOT}/DerivedData" \
    build >/dev/null
  METALLIB_SOURCE="$(find_mlx_metallib || true)"
fi

if [[ -z "${METALLIB_SOURCE}" ]]; then
  cat >&2 <<EOF
error: could not find MLX default.metallib.

compass-cli loads MLX kernels from a colocated mlx.metallib. Build the Compass
Xcode scheme once, or inspect the mlx-swift_Cmlx resource bundle generation.
EOF
  exit 1
fi

for destination_dir in "${BIN_DIR}" "${SWIFTPM_BIN_DIR}"; do
  mkdir -p "${destination_dir}"
  cp "${METALLIB_SOURCE}" "${destination_dir}/mlx.metallib"
done

codesign --force --sign "${IDENTITY}" --entitlements "${ENTITLEMENTS}" "${BINARY}"

ENTITLEMENTS_OUTPUT="$(codesign -d --entitlements - "${BINARY}" 2>/dev/null)"
if ! /usr/bin/grep -q "com.apple.security.virtualization" <<<"${ENTITLEMENTS_OUTPUT}" \
  || ! /usr/bin/grep -q "com.apple.security.network.client" <<<"${ENTITLEMENTS_OUTPUT}"; then
  cat >&2 <<EOF
error: signed compass-cli is missing required entitlements.

Apple Containerization requires com.apple.security.virtualization and network
client access. Re-run this script, or set COMPASS_CLI_SIGN_IDENTITY to a signing
identity that can carry App/CompassCLI.entitlements.
EOF
  exit 1
fi

echo "${BINARY}"
