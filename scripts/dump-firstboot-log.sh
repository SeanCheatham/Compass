#!/bin/bash
set -euo pipefail

# Mounts the Compass shared-VM Data volume read-only and dumps the
# headless first-boot log + LaunchDaemon presence so we can see exactly
# what happened on the guest's first boot.
#
# REQUIRES: the VM must be shut down. Mounting the Data volume while VZ
# has the disk image open would corrupt the volume. Run this only when
# the Compass UI shows the VM is stopped, OR after forcing shutdown via
# the power-button affordance in the embedded VM view.
#
# Run with: ./scripts/dump-firstboot-log.sh

DISK="$HOME/Library/Application Support/Compass/SharedVM/bundle.vmbundle/Disk.img"

if [[ ! -f "$DISK" ]]; then
  echo "error: no VM disk image at $DISK" >&2
  exit 1
fi

if pgrep -lf 'com\.apple\.Virtualization\.VirtualMachine' >/dev/null 2>&1; then
  echo "error: a VZ VirtualMachine process is still alive — shut down the Compass VM first" >&2
  pgrep -lf 'com\.apple\.Virtualization\.VirtualMachine' >&2
  exit 1
fi

WHOLE_DEV=$(hdiutil attach -nomount -plist -nobrowse "$DISK" \
  | python3 -c "
import sys, plistlib
p = plistlib.loads(sys.stdin.read().encode())
for e in p['system-entities']:
    h = e.get('content-hint', '')
    d = e.get('dev-entry', '')
    if h == 'GUID_partition_scheme':
        print(d); break")

if [[ -z "$WHOLE_DEV" ]]; then
  echo "error: could not identify whole-disk devnode" >&2
  exit 1
fi
echo "Attached at $WHOLE_DEV"

cleanup() {
  hdiutil detach "$WHOLE_DEV" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Wait briefly for APFS synthesis.
sleep 1

DATA_DEV=$(diskutil apfs list -plist | python3 -c "
import sys, plistlib
p = plistlib.loads(sys.stdin.read().encode())
ps_needle = '${WHOLE_DEV#/dev/}s2'
for c in p.get('Containers', []):
    if any(s.get('DeviceIdentifier') == ps_needle for s in c.get('PhysicalStores', [])):
        for v in c.get('Volumes', []):
            if 'Data' in v.get('Roles', []):
                print('/dev/' + v['DeviceIdentifier']); break")

if [[ -z "$DATA_DEV" ]]; then
  echo "error: could not locate Data volume" >&2
  exit 1
fi
echo "Data volume: $DATA_DEV"

MNT=$(mktemp -d /tmp/compass-firstboot-dump.XXXXXX)
# Read-only is safest for forensic dump.
echo "Mounting read-only at $MNT (will prompt for password)..."
osascript -e "do shell script \"/usr/sbin/diskutil mount readOnly -mountPoint '$MNT' -nobrowse '$DATA_DEV' 2>&1 || /sbin/mount_apfs -o rdonly,nobrowse '$DATA_DEV' '$MNT'\" with administrator privileges"

echo
echo "=== /Users/Shared/compass-firstboot/ contents ==="
ls -la "$MNT/Users/Shared/compass-firstboot/" 2>&1 || echo "(directory missing — staging dir was never created)"

echo
echo "=== firstboot.log ==="
if [[ -f "$MNT/Users/Shared/compass-firstboot/firstboot.log" ]]; then
  cat "$MNT/Users/Shared/compass-firstboot/firstboot.log"
else
  echo "(log missing — LaunchDaemon never ran; check LaunchDaemons dir below)"
fi

echo
echo "=== LaunchDaemon presence ==="
ls -la "$MNT/Library/LaunchDaemons/" 2>/dev/null | grep -i compass || echo "(no compass LaunchDaemon plist — plant did not write to /Library/LaunchDaemons)"

echo
echo "=== bootstrap script presence ==="
ls -la "$MNT/usr/local/libexec/" 2>/dev/null | grep -i compass || echo "(no bootstrap script — plant did not write to /usr/local/libexec)"

echo
echo "=== AppleSetupDone marker ==="
ls -la "$MNT/private/var/db/.AppleSetupDone" 2>/dev/null || echo "(missing — Setup Assistant would have run)"

echo
echo "=== sudoers fragment ==="
ls -la "$MNT/private/etc/sudoers.d/" 2>/dev/null | grep -i compass || echo "(no compass sudoers fragment)"

echo
echo "=== dslocal hierarchy on disk (root walk) ==="
# /var/db/dslocal/nodes/Default has mode 0700 on disk, and the read-only
# APFS mount on the host remaps stored uid 0 to the mounting user, so a
# plain `ls` as ourselves sees the dir as ours-without-x and prints
# nothing. Walk the tree as root so we actually see the user record.
# Emit a tiny helper script and invoke it via osascript-admin (which the
# user already authenticated to for the mount).
WALKER=$(mktemp /tmp/compass-dslocal-walker.XXXXXX.sh)
cat > "$WALKER" <<EOF
#!/bin/bash
for path in \\
  "$MNT/private/var/db/dslocal" \\
  "$MNT/private/var/db/dslocal/nodes" \\
  "$MNT/private/var/db/dslocal/nodes/Default" \\
  "$MNT/private/var/db/dslocal/nodes/Default/users" \\
  "$MNT/private/var/db/dslocal/nodes/Default/groups"; do
  if [ -d "\$path" ]; then
    echo "--- \$path ---"
    ls -la "\$path" 2>&1 | head -40
  else
    echo "(missing: \$path)"
  fi
done
EOF
chmod +x "$WALKER"
# AppleScript's `do shell script` returns the shell's stdout as a single
# Text value with CR (\r) line separators rather than LF (\n). When that
# string is printed back to a terminal, every CR moves the cursor to
# column 0 and the next line overwrites the previous one — which is why
# this section used to render as a single garbled line. Translate CRs
# back to LFs so multi-line ls output renders correctly.
osascript -e "do shell script \"'$WALKER'\" with administrator privileges" 2>&1 \
  | tr '\r' '\n' \
  || echo "(dslocal walk failed — admin auth cancelled?)"
rm -f "$WALKER"

echo
echo "Unmounting..."
osascript -e "do shell script \"/usr/sbin/diskutil unmount '$MNT' || /sbin/umount '$MNT'\" with administrator privileges" >/dev/null 2>&1 || true
rmdir "$MNT" 2>/dev/null || true
