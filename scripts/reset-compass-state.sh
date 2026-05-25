#!/bin/bash
set -euo pipefail

# Wipes Compass on-disk + Keychain state so the next launch performs a
# clean install of the Shared VM (download IPSW, run VZMacOSInstaller,
# plant headless first-boot, boot).
#
# Three reset modes, controlled by the first positional argument:
#   --full      Wipe everything: VM bundle, IPSW cache, known projects,
#               worktree scratch, Keychain credential. Slowest re-bootstrap
#               (~14 GB IPSW re-download). Default.
#   --vm-only   Keep the known-projects list. Wipe SharedVM + worktrees +
#               Keychain. Use when you only care about resetting the VM.
#   --keep-ipsw In-app "Reset VM artifacts" parity. Wipes installed VM
#               disk/aux/identity but preserves the cached IPSW and the
#               Compass SSH keypair. Fastest retry.
#
# Pass --dry-run as the second argument to print what would happen
# without touching anything.

usage() {
  cat >&2 <<'USAGE'
Usage: reset-compass-state.sh [--full | --vm-only | --keep-ipsw] [--dry-run]

  --full       Nuke everything (default): VM bundle, IPSW cache, known
               projects, worktrees, Keychain entry.
  --vm-only    Keep known-projects list. Wipe SharedVM + worktrees +
               Keychain.
  --keep-ipsw  Preserve the cached IPSW and Compass SSH keypair, like
               the in-app "Reset VM artifacts" button.
  --dry-run    Print actions without performing them.
USAGE
}

MODE="--full"
DRY_RUN=0

for arg in "$@"; do
  case "${arg}" in
    --full|--vm-only|--keep-ipsw)
      MODE="${arg}"
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument ${arg}" >&2
      usage
      exit 1
      ;;
  esac
done

APPSUPPORT="${HOME}/Library/Application Support/Compass"
CACHES="${HOME}/Library/Caches/Compass"
BUNDLE="${APPSUPPORT}/SharedVM/bundle.vmbundle"
DISK_IMAGE="${BUNDLE}/Disk.img"
AUXILIARY_STORAGE="${BUNDLE}/AuxiliaryStorage"
IPSW_CACHE="${BUNDLE}/cache"
SSH_KEY="${BUNDLE}/id_ed25519"
SSH_KEY_PUB="${BUNDLE}/id_ed25519.pub"
KEYCHAIN_SERVICE="com.seancheatham.Compass.SharedVM"
VZ_HELPER_PATTERN='com\.apple\.Virtualization\.(Installation|Restore|VirtualMachine)'

run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '  [dry-run] %s\n' "$*"
  else
    eval "$@"
  fi
}

compass_vz_helper_pids() {
  local path pid command
  for path in "${DISK_IMAGE}" "${AUXILIARY_STORAGE}"; do
    [[ -e "${path}" ]] || continue
    while read -r pid; do
      [[ "${pid}" =~ ^[0-9]+$ ]] || continue
      command="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
      if [[ "${command}" =~ ${VZ_HELPER_PATTERN} ]]; then
        printf '%s\n' "${pid}"
      fi
    done < <(lsof -t "${path}" 2>/dev/null || true)
  done | sort -u
}

# ---- 1. Make sure Compass is not running so its file handles are released.

if pgrep -x Compass >/dev/null 2>&1; then
  echo "Compass is running — sending quit signal."
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '  [dry-run] osascript -e %q\n' 'tell application "Compass" to quit'
  else
    osascript -e 'tell application "Compass" to quit' || true
    # Give it a couple of seconds to stop cleanly before we wipe state.
    for _ in 1 2 3 4 5; do
      if ! pgrep -x Compass >/dev/null 2>&1; then break; fi
      sleep 1
    done
    if pgrep -x Compass >/dev/null 2>&1; then
      echo "warning: Compass is still running. Quit it manually before re-running this script." >&2
      exit 1
    fi
  fi
fi

# ---- 2. Reap orphaned Virtualization.framework XPC helpers that still have
# Compass's VM artifacts open. Docker Desktop and other host services can also
# run com.apple.Virtualization.VirtualMachine, so never kill by process name
# alone. A wedged Compass helper keeps an flock on AuxiliaryStorage / Disk.img
# and makes the next launch fail with "Failed to lock auxiliary storage
# [VZErrorDomain 2] / EAGAIN".
while read -r helper_pid; do
  [[ -z "${helper_pid}" ]] && continue
  echo "Reaping orphaned Compass VZ helper PID ${helper_pid}"
  run "kill -9 ${helper_pid}"
done < <(compass_vz_helper_pids)

# ---- 3. Detach the VM disk image if a previous run left it attached.

if [[ -f "${DISK_IMAGE}" ]]; then
  while read -r attached_dev; do
    [[ -z "${attached_dev}" ]] && continue
    echo "Detaching lingering attachment ${attached_dev} for ${DISK_IMAGE}"
    run "hdiutil detach \"${attached_dev}\" -force"
  done < <(hdiutil info 2>/dev/null \
    | awk -v img="${DISK_IMAGE}" '
        /^image-path/ { last_path = $0 }
        /^\/dev\/disk[0-9]+\s/ && index(last_path, img) > 0 { print $1 }
      ')
fi

# ---- 4. Wipe per the requested mode.

case "${MODE}" in
  --full)
    echo "Mode: --full (wipe everything, including known projects)"
    run "rm -rf \"${APPSUPPORT}\""
    run "rm -rf \"${CACHES}\""
    ;;

  --vm-only)
    echo "Mode: --vm-only (preserve known-projects list)"
    run "rm -rf \"${APPSUPPORT}/SharedVM\""
    run "rm -rf \"${CACHES}\""
    ;;

  --keep-ipsw)
    echo "Mode: --keep-ipsw (preserve IPSW cache + Compass SSH keypair)"
    if [[ ! -d "${BUNDLE}" ]]; then
      echo "  no bundle at ${BUNDLE}; nothing to preserve, falling back to --vm-only semantics"
      run "rm -rf \"${APPSUPPORT}/SharedVM\""
    else
      # Mirror SharedCompassVMBundle.resetInstalledArtifacts: remove the
      # disk image, auxiliary storage, hardware identity, known_hosts,
      # and state.json. Keep cache/ and the Compass-owned SSH keypair.
      for path in \
        "${BUNDLE}/Disk.img" \
        "${BUNDLE}/AuxiliaryStorage" \
        "${BUNDLE}/HardwareModel" \
        "${BUNDLE}/MachineIdentifier" \
        "${BUNDLE}/known_hosts" \
        "${BUNDLE}/state.json"
      do
        if [[ -e "${path}" ]]; then
          run "rm -rf \"${path}\""
        fi
      done
    fi
    run "rm -rf \"${CACHES}\""
    ;;
esac

# ---- 5. Drop the Keychain entry holding the auto-generated guest password.
# Loop because there may be multiple entries from past test runs (the
# headless planter allocates a fresh per-bundle account on each install).

while security find-generic-password -s "${KEYCHAIN_SERVICE}" >/dev/null 2>&1; do
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '  [dry-run] security delete-generic-password -s %s\n' "${KEYCHAIN_SERVICE}"
    break
  fi
  security delete-generic-password -s "${KEYCHAIN_SERVICE}" >/dev/null 2>&1 || break
done

echo
echo "Done. Next Compass launch will reprovision the Shared VM."
case "${MODE}" in
  --full)
    echo "  Expect ~14 GB IPSW download + ~30 min macOS install + headless first boot."
    ;;
  --vm-only)
    echo "  Expect ~14 GB IPSW download + ~30 min macOS install + headless first boot."
    echo "  Known-projects list preserved at ${APPSUPPORT}/projects.json."
    ;;
  --keep-ipsw)
    echo "  IPSW cache preserved — install resumes from cache (~30 min)."
    ;;
esac
