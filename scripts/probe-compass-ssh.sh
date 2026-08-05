#!/bin/bash
# Probe the Compass shared VM from the host in the same way Compass
# itself does, but interactively so we can see every error. Run while
# Compass is showing the "SSH probe failed" error — does NOT require
# the VM to be shut down (unlike dump-firstboot-log.sh).
#
# Note: SSH is only used for provisioning/readiness probes today;
# workspace sync runs over vsock CAS (tar fallback), not SSH.
#
# Tells us:
#   1. Whether Compass populated known_hosts during its latest attempt
#      (i.e. is the host-side ssh-keyscan code path being exercised?).
#   2. Whether ssh-keyscan reaches the guest from the terminal.
#   3. What the strict SSH probe sees with BatchMode=yes — including
#      the actual stderr that Compass's probe throws away.
#
# Run with: ./scripts/probe-compass-ssh.sh

set -uo pipefail

# The Compass bundle root is the .vmbundle directory itself, NOT the
# parent SharedVM directory — id_ed25519 / known_hosts / state.json
# live inside the bundle alongside the VZ disk/aux storage.
BUNDLE="$HOME/Library/Application Support/Compass/SharedVM/bundle.vmbundle"
KNOWN_HOSTS="$BUNDLE/known_hosts"
PRIVATE_KEY="$BUNDLE/id_ed25519"
STATE_FILE="$BUNDLE/state.json"

echo "=== Compass bundle ==="
ls -la "$BUNDLE" 2>&1 | head -25 || true

echo
echo "=== state.json (Compass's persisted bundle state) ==="
if [[ -f "$STATE_FILE" ]]; then
  cat "$STATE_FILE" 2>&1 || true
else
  echo "(missing — bundle never reached the state-persistence step)"
fi

echo
echo "=== known_hosts ==="
if [[ -f "$KNOWN_HOSTS" ]]; then
  ls -la "$KNOWN_HOSTS"
  echo "--- contents ---"
  cat "$KNOWN_HOSTS"
else
  echo "(missing — Compass's populateKnownHosts step is either disabled, never ran, or failed silently)"
fi

echo
echo "=== private key ==="
if [[ -f "$PRIVATE_KEY" ]]; then
  ls -la "$PRIVATE_KEY"
  echo "fingerprint:"
  ssh-keygen -lf "$PRIVATE_KEY" 2>&1 || true
else
  echo "(missing — Compass should have generated this during provisioning)"
fi

echo
echo "=== guest IP from dhcpd_leases ==="
# bootpd prepends new leases to the file (newest entry on top), so the
# CURRENT guest IP is the FIRST ip_address line, not the last. Pull it
# directly. If multiple Compass resets have happened in this session
# you'll see a stack of stale leases below.
GUEST_IP=""
if [[ -r /var/db/dhcpd_leases ]]; then
  GUEST_IP=$(awk -F= '/ip_address/{print $2; exit}' /var/db/dhcpd_leases)
  echo "Newest ip_address line: ${GUEST_IP:-(none)}"
  echo "--- full lease file (oldest at bottom) ---"
  cat /var/db/dhcpd_leases
else
  echo "(/var/db/dhcpd_leases not readable — falling back to sudo)"
  GUEST_IP=$(sudo awk -F= '/ip_address/{print $2; exit}' /var/db/dhcpd_leases 2>/dev/null)
  echo "Newest ip_address line (via sudo): ${GUEST_IP:-(none)}"
fi

if [[ -z "$GUEST_IP" ]]; then
  echo "Could not auto-detect guest IP. Pass it as the first argument: $0 192.168.64.X"
  GUEST_IP="${1:-}"
fi

if [[ -z "$GUEST_IP" ]]; then
  echo "No IP — aborting probes."
  exit 1
fi

echo
echo "=== ssh-keyscan against $GUEST_IP ==="
echo "(if this fails, the guest sshd is unreachable from the host even though it's listening internally)"
/usr/bin/ssh-keyscan -T 5 -t ed25519,rsa,ecdsa "$GUEST_IP" 2>&1 || echo "(keyscan failed)"

echo
echo "=== strict SSH probe to compass@$GUEST_IP (mirrors Compass's probe) ==="
echo "If known_hosts is populated above, this should succeed. If not, you'll see the exact error Compass swallows."
if [[ -f "$PRIVATE_KEY" && -f "$KNOWN_HOSTS" ]]; then
  /usr/bin/ssh \
    -i "$PRIVATE_KEY" \
    -o "UserKnownHostsFile=$KNOWN_HOSTS" \
    -o "StrictHostKeyChecking=yes" \
    -o "BatchMode=yes" \
    -o "ConnectTimeout=5" \
    -T \
    -v \
    "compass@$GUEST_IP" \
    true 2>&1 | tail -40
  echo "exit: $?"
elif [[ -f "$PRIVATE_KEY" ]]; then
  echo "(skipping strict probe because known_hosts is missing — try the next probe with accept-new instead)"
fi

echo
echo "=== relaxed SSH probe with accept-new (would the strict probe pass if known_hosts were populated?) ==="
if [[ -f "$PRIVATE_KEY" ]]; then
  /usr/bin/ssh \
    -i "$PRIVATE_KEY" \
    -o "StrictHostKeyChecking=accept-new" \
    -o "BatchMode=yes" \
    -o "ConnectTimeout=5" \
    -T \
    -v \
    "compass@$GUEST_IP" \
    true 2>&1 | tail -40
  echo "exit: $?"
else
  echo "(no private key — cannot probe)"
fi
