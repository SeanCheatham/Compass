# Compass Architecture

Compass keeps the native macOS experience while moving product logic into Rust.

```text
Compass.app (Swift)
  UI, app lifecycle, Keychain, Foundation Models, Virtualization.framework
        |
        | Unix socket NDJSON, schema_version = 1
        v
compassd / compass-core (Rust)
  tournament state, agent lifecycle, tools, schemas, replay tests
        |
        | AgentRPC vsock JSON
        v
Guest workspace
  bash, cargo, compass-engine, future compass-guest-agent
```

The Swift shell should aggregate UI state and call `compassd`; it should not own
new tournament transitions or HTTP agent-loop behavior. Rust APIs should remain
schema-first and process-isolated rather than FFI-bound so streaming and
cancellation can evolve without Swift ABI coupling.

Current migration flags:

| Flag | Meaning |
| --- | --- |
| `COMPASS_RUST_DAEMON_DISABLED=1` | Skip daemon launch for UI-only work. |
| `COMPASS_RUST_TOURNAMENT_SHADOW=1` | Compare Swift tournament reads with Rust read models. |
| `COMPASS_RUST_TOURNAMENT_DRIVER=1` | Route tournament mutations through Rust when enabled. |
| `COMPASS_RUST_AGENT_EXECUTOR=1` | Route HTTP-provider agent runs through Rust. |
| `COMPASS_RUST_GUEST_AGENT=1` | Install/use the Rust guest agent. |
| `COMPASS_LINUX_GUEST=1` | Enable the experimental Linux guest path. |

The Linux guest spike is documented in
[`docs/linux-guest-spike.md`](linux-guest-spike.md).
