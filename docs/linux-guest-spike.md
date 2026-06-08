# Linux Guest Spike

The Rust core cutover does not require replacing the current macOS
`Virtualization.framework` guest. The Linux path is tracked as an experimental
runtime behind `COMPASS_LINUX_GUEST=1`.

## Proposed Host Command

`compass-core::vm::linux::LinuxGuestConfig` builds a QEMU aarch64 command with:

- HVF acceleration on Apple Silicon.
- A qcow2 image at
  `~/Library/Application Support/Compass/SharedVM/linux/compass-guest.qcow2`.
- SSH forwarded to `127.0.0.1:<port>`.
- A vhost-vsock device with a fixed guest CID for AgentRPC.

The default image should contain:

- `compass` user with SSH enabled.
- Rust toolchain, git, ripgrep, Python 3, and build essentials.
- `/usr/local/bin/compass-engine`.
- `/usr/local/bin/compass-guest-agent`.
- A first-boot marker script that can be safely rerun.

## Readiness Contract

Linux readiness should map onto the existing Shared VM UI states:

```text
notProvisioned -> downloadingImage -> provisioning -> installingToolchain -> ready
```

The host should consider the guest ready only after both checks pass:

```bash
ssh compass@127.0.0.1 -p <port> true
compass-guest-agent framed ping over vsock
```

## Rollout

1. Build the qcow2 image locally and prove `cargo run -p xtask -- verify`.
2. Add image manifest/signature verification.
3. Wire Swift settings to `COMPASS_LINUX_GUEST=1`.
4. Keep macOS guest as fallback until Develop + Verify pass in nightly smoke.
