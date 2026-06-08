# compassd Protocol

`compassd` accepts newline-delimited JSON over a user-owned Unix domain
socket. Every request receives exactly one response on the same connection.
Long-running event streaming is reserved in `schemas/compassd/v1/events.json`.

## Request

```json
{
  "schema_version": 1,
  "id": "uuid-or-client-id",
  "method": "ping",
  "params": {}
}
```

## Response

```json
{
  "schema_version": 1,
  "id": "uuid-or-client-id",
  "ok": true,
  "result": {},
  "errors": []
}
```

## Methods

| Method | Purpose |
| --- | --- |
| `ping` | Health check; returns daemon/core versions and schema version. |
| `get_capabilities` | Lists supported methods and coarse feature capabilities. |
| `shutdown` | Requests graceful daemon shutdown. |
| `tournament_load` | Loads `.compass/tournament/state.json`, returning empty V2 state when absent. |
| `tournament_validate` | Validates the loaded tournament state and returns parity errors. |
| `tournament_read_model` | Returns a stable read-only tournament summary for Swift shadow mode. |
| `agent_tool_list` | Lists host-tool specs currently implemented in Rust. |
| `agent_run_start` | Starts the Rust agent lifecycle; Phase 3 uses deterministic/mock completion. |
| `agent_run_status` | Returns lifecycle state for a started agent run. |
| `agent_run_cancel` | Marks a tracked run cancelled. |

The socket should be created with mode `0600`. Swift owns launch and shutdown;
Rust owns request decoding, method dispatch, and structured daemon logging.
